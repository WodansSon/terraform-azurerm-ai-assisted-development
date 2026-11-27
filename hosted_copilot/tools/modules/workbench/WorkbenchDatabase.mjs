import { lstatSync, unlinkSync } from 'node:fs';
import { openWorkbenchSqlite } from './WorkbenchSqlite.mjs';
import { migrateNewWorkbenchApplication, validateWorkbenchApplicationSchema } from './WorkbenchApplicationSchema.mjs';
import { initializeNativeWorkspace } from './WorkbenchNativeWorkspace.mjs';
import { parseInitialRulesJson } from './WorkbenchInitialCatalog.mjs';
import { beginAnalysisRun, registerEvaluatorProfile, recordEvaluationRequest, commitAssessmentResults, commitReconciliationComponents, failEvaluation } from './WorkbenchEvaluations.mjs';
import { commitSynthesisResults } from './WorkbenchReconciliationResults.mjs';
import { recordAdjudicationRequest, commitAdjudicationResults } from './WorkbenchAdjudication.mjs';
import { completeNativeAnalysis } from './WorkbenchAnalysisCompletion.mjs';
import { readSelectedCapacityConfiguration, readNativeWorkspaceView } from './WorkbenchWorkspace.mjs';
import { readNativeLlmRuntime, readNativeWorkspaceBinding, runNativeAssessments, runNativeDownstream } from './WorkbenchAnalysis.mjs';
import { resumeNativeAssessments, withAssessmentExecutionLock, withExecutionCancellation } from './WorkbenchAssessmentRecovery.mjs';
import { createWorkbenchAudit } from './WorkbenchAudit.mjs';
import { requireSourceObject } from './WorkbenchSourceRecords.mjs';

// Accept one bounded JSON request over stdin so captures do not need command-line serialization.
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

// Initialize a new workspace and verify its persisted baseline after reopening; remove only owned files on failure.
async function create(databasePath) {
  const request = await readRequest();
  request.protectedCapture.files = request.protectedCapture.files.map(file => ({ ...file, contentBytes: Uint8Array.from(file.contentBytes) }));
  const connection = openWorkbenchSqlite({ mode: 'create', databasePath });
  const created = lstatSync(databasePath);
  let complete = false;
  let closed = false;
  try {
    migrateNewWorkbenchApplication(connection);
    const result = initializeNativeWorkspace(connection, request);
    const validation = validateWorkbenchApplicationSchema(connection);
    if (!validation.valid) throw new Error('Fresh database schema validation failed');
    connection.close();
    closed = true;
    const reopened = openWorkbenchSqlite({ mode: 'read-only', databasePath });
    try {
      if (!validateWorkbenchApplicationSchema(reopened).valid) throw new Error('Fresh database schema validation failed after reopening');
      const view = readNativeWorkspaceView(reopened, { binding: { databaseGuid: result.databaseGuid, repositoryId: result.repositoryId, branchRef: result.branchRef } });
      if (view.workingCatalog?.catalogId !== result.catalogId) throw new Error('Initial catalog selection was not preserved after reopening');
      if (request.initialRulesCapture) {
        const expected = parseInitialRulesJson(request.initialRulesCapture, request.profile);
        const actualRules = view.workingCatalog.rules.map(rule => [rule.displayedId, rule.wording, [...rule.applicabilities].sort()]);
        const expectedRules = expected.rules.map(rule => [rule.id, rule.text, [...rule.implementationModels].sort()]);
        if (JSON.stringify(actualRules) !== JSON.stringify(expectedRules) || view.publishedCatalog !== null ||
            view.workingCatalog.contentSha256 !== request.initialRulesCapture.contentSha256) throw new Error('Initial JSON baseline did not round-trip exactly');
          const locations = reopened.all('SELECT source_line, source_pointer FROM catalog_rule_guidance WHERE catalog_id = ? ORDER BY rule_id', [result.catalogId]);
          if (JSON.stringify(locations.map(location => [location.source_line, location.source_pointer])) !==
            JSON.stringify(expected.rules.map(rule => [null, rule.sourcePointer]))) throw new Error('Initial JSON rule locations did not round-trip exactly');
        for (const surface of expected.surfaces) {
          const actual = view.workingCatalog.surfaces.find(item => item.code === surface.code);
          if (!actual || JSON.stringify([actual.outputPath, actual.description, actual.title, actual.introduction, actual.closing, actual.sections]) !==
              JSON.stringify([surface.outputPath, surface.description, surface.title, surface.introduction, surface.closing, surface.sections])) {
            throw new Error('Initial instruction-file metadata did not round-trip exactly');
          }
        }
      }
    } finally { reopened.close(); }
    complete = true;
    return result;
  } finally {
    if (!closed) connection.close();
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

// Dispatch registered bridge operations with schema validation, explicit access modes, and owned analysis locks.
async function execute(operation, databasePath) {
  if (operation === 'create') return create(databasePath);
  const supported = ['audit', 'llm-runtime', 'read-workspace', 'assess', 'resume-assess', 'continue-analysis', 'analysis-begin', 'evaluation-request', 'assessment-result', 'evaluation-fail', 'analysis-sources',
    'reconciliation-components', 'reconciliation-result', 'adjudication-request', 'adjudication-result', 'analysis-complete'];
  if (!supported.includes(operation)) throw new Error('Database operation is not registered');
  const request = await readRequest();
  if (operation === 'audit') {
    requireSourceObject(request, ['actionCode', 'correlationGuid', 'context', 'transition', 'outcome', 'facts', 'databaseGuid', 'nextActionCode'],
      ['actionCode', 'correlationGuid', 'context', 'transition', 'facts'], 'Audit transport request');
    let binding = null;
    let reader;
    try {
      reader = openWorkbenchSqlite({ mode: 'read-only', databasePath });
      if (validateWorkbenchApplicationSchema(reader).valid) binding = readNativeWorkspaceBinding(reader, request.databaseGuid ?? null);
    } catch { binding = null; }
    finally { reader?.close(); }
    const audit = createWorkbenchAudit({ databasePath, binding, actionCode: request.actionCode, correlationGuid: request.correlationGuid, context: request.context });
    if (request.transition === 'start') audit.start(request.actionCode, request.facts);
    else if (request.transition === 'finish') audit.finish(request.outcome, request.facts);
    else if (request.transition === 'transition') audit.transition(request.nextActionCode, request.facts);
    else throw new Error('Audit transition is not registered');
    const warning = audit.takeWarning();
    return { context: audit.snapshot(), warning };
  }
  const connection = openWorkbenchSqlite({ mode: ['llm-runtime', 'read-workspace'].includes(operation) ? 'read-only' : 'read-write', databasePath });
  try {
    const validation = validateWorkbenchApplicationSchema(connection);
    if (!validation.valid) {
      throw new Error('Selected database requires compatible schema initialization before evaluation');
    }
    if (operation === 'llm-runtime') return readNativeLlmRuntime(connection, request.databaseGuid);
    if (operation === 'read-workspace') return readNativeWorkspaceView(connection, request);
    if (['assess', 'resume-assess', 'continue-analysis'].includes(operation)) {
      const { auditContext, ...domainRequest } = request;
      const actionCode = operation === 'continue-analysis' ? (request.adjudicationOnly ? 'adjudicate' : 'reconcile') : 'assess';
      const workspace = connection.get(`SELECT context.repository_id AS repositoryId, context.branch_ref AS branchRef
        FROM workspace_identity workspace JOIN repository_contexts context ON context.id = workspace.origin_context_id WHERE workspace.id = 1`);
      const binding = { databaseGuid: request.databaseGuid, repositoryId: workspace?.repositoryId, branchRef: workspace?.branchRef };
      const audit = createWorkbenchAudit({ databasePath, binding, actionCode, context: auditContext ?? null });
      if (auditContext == null) audit.start(actionCode, request.runId === undefined ? {} : { runId: request.runId });
      try {
        return await audit.run(async () => {
          const result = await withAssessmentExecutionLock(databasePath, async control => {
            if (operation !== 'continue-analysis') {
              const assess = operation === 'assess' ? runNativeAssessments : resumeNativeAssessments;
              return assess(withExecutionCancellation(connection, control), domainRequest,
                progress => console.log(JSON.stringify({ kind: 'assessment-progress', ...progress })));
            }
            let failedPhase = null;
            try {
              return await runNativeDownstream(withExecutionCancellation(connection, control), domainRequest, progress => {
                if (progress.state === 'failed') failedPhase ??= progress.phase;
                console.log(JSON.stringify({ kind: 'downstream-progress', ...progress }));
              }, audit);
            } catch (error) {
              if (failedPhase !== null && !control.cancelled) {
                error.code = 'workbench-native-stage-failed';
                error.phase = failedPhase;
              }
              throw error;
            }
          });
          audit.finish(result.evaluatedSourceCount === 0 && result.recoveredSourceCount > 0 ? 'reused' : 'succeeded',
            { runId: result.runId, itemCount: result.completedSources ?? result.comparisonCount });
          return result;
        });
      } finally {
        const warning = audit.takeWarning();
        if (warning) console.log(JSON.stringify(warning));
        console.log(JSON.stringify({ kind: 'audit-context', context: audit.snapshot() }));
      }
    }
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
