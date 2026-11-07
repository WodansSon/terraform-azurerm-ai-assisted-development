import { lstatSync, unlinkSync } from 'node:fs';
import { openWorkbenchSqlite } from './WorkbenchSqlite.mjs';
import { migrateNewWorkbenchApplication, validateWorkbenchApplicationSchema } from './WorkbenchApplicationSchema.mjs';
import { initializeNativeWorkspace } from './WorkbenchNativeWorkspace.mjs';
import { beginAnalysisRun, registerEvaluatorProfile, recordEvaluationRequest, commitAssessmentResults, commitReconciliationComponents, failEvaluation } from './WorkbenchEvaluations.mjs';
import { commitSynthesisResults } from './WorkbenchReconciliationResults.mjs';
import { recordAdjudicationRequest, commitAdjudicationResults } from './WorkbenchAdjudication.mjs';
import { completeNativeAnalysis } from './WorkbenchAnalysisCompletion.mjs';
import { readSelectedCapacityConfiguration } from './WorkbenchWorkspace.mjs';
import { readNativeLlmRuntime, runNativeAssessments, runNativeDownstream } from './WorkbenchAnalysis.mjs';
import { resumeNativeAssessments, withAssessmentExecutionLock, withExecutionCancellation } from './WorkbenchAssessmentRecovery.mjs';

async function readRequest() {
  const chunks = [];
  let length = 0;
  for await (const chunk of process.stdin) {
    length += chunk.length;
    if (length > 128 * 1024 * 1024) throw new Error('Workbench capture exceeds its supported input size');
    chunks.push(chunk);
  }
  return JSON.parse(Buffer.concat(chunks).toString('utf8'));
}

async function create(databasePath) {
  const request = await readRequest();
  request.protectedCapture.files = request.protectedCapture.files.map(file => ({ ...file, contentBytes: Uint8Array.from(file.contentBytes) }));
  const connection = openWorkbenchSqlite({ mode: 'create', databasePath });
  const created = lstatSync(databasePath);
  let complete = false;
  try {
    migrateNewWorkbenchApplication(connection);
    const result = initializeNativeWorkspace(connection, request);
    const validation = validateWorkbenchApplicationSchema(connection);
    if (!validation.valid) throw new Error('Fresh database schema validation failed');
    complete = true;
    return result;
  } finally {
    connection.close();
    if (!complete) {
      const current = lstatSync(databasePath, { throwIfNoEntry: false });
      if (current && current.dev === created.dev && current.ino === created.ino) {
        for (const suffix of ['', '-wal', '-shm']) {
          if (lstatSync(databasePath + suffix, { throwIfNoEntry: false })) unlinkSync(databasePath + suffix);
        }
      }
    }
  }
}

async function execute(operation, databasePath) {
  if (operation === 'create') return create(databasePath);
  const supported = ['llm-runtime', 'assess', 'resume-assess', 'continue-analysis', 'analysis-begin', 'evaluation-request', 'assessment-result', 'evaluation-fail', 'analysis-sources',
    'reconciliation-components', 'reconciliation-result', 'adjudication-request', 'adjudication-result', 'analysis-complete'];
  if (!supported.includes(operation)) throw new Error('Database operation is not registered');
  const request = await readRequest();
  const connection = openWorkbenchSqlite({ mode: operation === 'llm-runtime' ? 'read-only' : 'read-write', databasePath });
  try {
    const validation = validateWorkbenchApplicationSchema(connection);
    if (!validation.valid) {
      if (operation === 'continue-analysis' && validateWorkbenchApplicationSchema(connection, { schemaVersion: 1 }).valid) {
        throw new Error('Native downstream continuation requires the explicit reviewed revision-two database upgrade before execution');
      }
      throw new Error('Selected database requires compatible schema initialization before evaluation');
    }
    if (operation === 'llm-runtime') return readNativeLlmRuntime(connection, request.databaseGuid);
    if (operation === 'continue-analysis') return await withAssessmentExecutionLock(databasePath, async control => {
      let failedPhase = null;
      try {
        return await runNativeDownstream(withExecutionCancellation(connection, control), request, progress => {
          if (progress.state === 'failed') failedPhase ??= progress.phase;
          console.log(JSON.stringify({ kind: 'downstream-progress', ...progress }));
        });
      } catch (error) {
        if (failedPhase !== null && !control.cancelled) {
          error.code = 'workbench-native-stage-failed';
          error.phase = failedPhase;
        }
        throw error;
      }
    });
    if (operation === 'assess' || operation === 'resume-assess') return await withAssessmentExecutionLock(databasePath, async control => {
      const assess = operation === 'assess' ? runNativeAssessments : resumeNativeAssessments;
      return assess(withExecutionCancellation(connection, control), request, progress => console.log(JSON.stringify({ kind: 'assessment-progress', ...progress })));
    });
    readSelectedCapacityConfiguration(connection, request.binding);
    if (operation === 'analysis-begin') {
      const profileId = registerEvaluatorProfile(connection, request.profile);
      const run = beginAnalysisRun(connection, { binding: request.binding, actorId: request.actorId, scoringPolicyId: request.scoringPolicyId, force: request.force, llmAssignmentIds: request.llmAssignmentIds });
      return { ...run, profileId };
    }
    if (operation === 'evaluation-request') return recordEvaluationRequest(connection, request);
    if (operation === 'assessment-result') return commitAssessmentResults(connection, request);
    if (operation === 'reconciliation-components') return commitReconciliationComponents(connection, request);
    if (operation === 'reconciliation-result') return commitSynthesisResults(connection, request);
    if (operation === 'adjudication-request') return recordAdjudicationRequest(connection, request);
    if (operation === 'adjudication-result') return commitAdjudicationResults(connection, request);
    if (operation === 'analysis-complete') return completeNativeAnalysis(connection, request);
    if (operation === 'evaluation-fail') return failEvaluation(connection, request);
    const sources = connection.all(`SELECT member.source_version_id AS sourceVersionId, definition.code AS sourceDefinitionId,
      configuration.assessment_batch_size AS batchSize FROM run_collections captured
      JOIN source_collections collection ON collection.id = captured.collection_id
      JOIN source_definition_versions configuration ON configuration.id = collection.definition_version_id
      JOIN source_definitions definition ON definition.id = collection.definition_id
      JOIN source_collection_members member ON member.collection_id = collection.id
      WHERE captured.run_id = ? AND member.presence = 'present' ORDER BY definition.id, member.ordinal`, [request.runId]);
    return { runId: request.runId, sources };
  } finally { connection.close(); }
}

try {
  if (!process.argv[2] || !process.argv[3]) throw new Error('Select an explicit native database operation and destination');
  console.log(JSON.stringify(await execute(process.argv[2], process.argv[3])));
} catch (error) {
  if (error.code === 'workbench-execution-already-running') {
    console.log(JSON.stringify({ kind: 'execution-refused', code: error.code }));
  } else if (error.code === 'workbench-native-stage-failed') {
    console.log(JSON.stringify({ kind: 'execution-failed', code: error.code, phase: error.phase }));
  } else console.error(error.message);
  process.exitCode = 1;
}
