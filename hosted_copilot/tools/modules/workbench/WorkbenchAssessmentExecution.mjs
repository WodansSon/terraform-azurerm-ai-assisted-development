import { sourceTextHash } from './WorkbenchSourceRecords.mjs';
import { prepareEvaluationInput, readAssessmentRecoveryPlan, recordEvaluationRequest, commitAssessmentResults, failEvaluation } from './WorkbenchEvaluations.mjs';

export function measureAssessmentInputBytes(serializedInput, evaluatorInput) {
  if (typeof serializedInput !== 'string' || typeof evaluatorInput?.prompt !== 'string' || typeof evaluatorInput?.schema !== 'string') {
    throw new Error('Assessment payload measurement requires the complete evaluator input');
  }
  const prompt = `${evaluatorInput.prompt}\n\n## Output Contract\n${evaluatorInput.schema}\n\n## Untrusted Quoted Input\n${serializedInput}`;
  return Buffer.byteLength(prompt, 'utf8');
}

export function estimateAssessmentMilliseconds(completedPayloadBytes, completedWorkerMilliseconds, remainingPayloadBytes, workerCount) {
  if (remainingPayloadBytes <= 0) return 0;
  const workers = Math.max(1, workerCount);
  if (completedPayloadBytes <= 0 || completedWorkerMilliseconds <= 0) {
    return Math.ceil(remainingPayloadBytes / (200 * workers) * 1000);
  }
  const bytesPerMillisecondPerWorker = completedPayloadBytes / completedWorkerMilliseconds;
  return Math.ceil(remainingPayloadBytes / (bytesPerMillisecondPerWorker * workers));
}

function readCommittedProgress(connection, runId) {
  const completedSources = connection.get(`SELECT count(DISTINCT input.source_version_id) AS count FROM run_evaluations used
    JOIN evaluations evaluation ON evaluation.id = used.evaluation_id JOIN evaluator_profiles profile ON profile.id = evaluation.evaluator_profile_id
    JOIN evaluation_inputs input ON input.evaluation_id = evaluation.id AND input.role_code = 'source'
    WHERE used.run_id = ? AND evaluation.outcome = 'complete' AND profile.task_code = 'assessment'`, [runId]).count;
  const completedAssessments = connection.get(`SELECT count(*) AS count FROM run_evaluations used
    JOIN evaluations evaluation ON evaluation.id = used.evaluation_id JOIN assessment_results result ON result.evaluation_id = evaluation.id
    WHERE used.run_id = ? AND evaluation.outcome = 'complete'`, [runId]).count;
  return { completedSources, completedAssessments };
}

export function planAssessmentBatches(connection, request, evaluatorInput, maxParallelBatches = 3) {
  if (!Number.isSafeInteger(maxParallelBatches) || maxParallelBatches < 1 || maxParallelBatches > 16) {
    throw new Error('Assessment workers must be an integer between 1 and 16');
  }
  measureAssessmentInputBytes('', evaluatorInput);
  const payloadBudgetBytes = 393216;
  const recovery = readAssessmentRecoveryPlan(connection, request);
  const remaining = new Set(recovery.remainingSourceVersionIds);
  const sources = connection.all(`SELECT member.source_version_id AS sourceVersionId, definition.code AS sourceDefinitionId,
    configuration.assessment_batch_size AS batchSize FROM run_collections captured
    JOIN source_collections collection ON collection.id = captured.collection_id
    JOIN source_definition_versions configuration ON configuration.id = collection.definition_version_id
    JOIN source_definitions definition ON definition.id = collection.definition_id
    JOIN source_collection_members member ON member.collection_id = collection.id
    WHERE captured.run_id = ? AND member.presence = 'present' ORDER BY definition.id, member.ordinal`, [request.runId]);
  const pending = sources.filter(source => remaining.has(source.sourceVersionId));
  const batches = [];
  for (let offset = 0; offset < pending.length;) {
    const first = pending[offset];
    const sourceVersionIds = [];
    let prepared;
    let payloadBytes;
    while (offset < pending.length && sourceVersionIds.length < first.batchSize && pending[offset].sourceDefinitionId === first.sourceDefinitionId) {
      const candidate = prepareEvaluationInput(connection, { ...request, sourceVersionIds: [...sourceVersionIds, pending[offset].sourceVersionId] });
      const candidateBytes = measureAssessmentInputBytes(candidate.serializedInput, evaluatorInput);
      if (candidateBytes > payloadBudgetBytes) {
        if (sourceVersionIds.length === 0) {
          throw new Error(`Captured source ${pending[offset].sourceVersionId} exceeds evaluator payload budget: ${candidateBytes} bytes, budget ${payloadBudgetBytes} bytes; reduce or split the parser-owned source record`);
        }
        break;
      }
      sourceVersionIds.push(pending[offset++].sourceVersionId);
      prepared = candidate;
      payloadBytes = candidateBytes;
    }
    batches.push({ sourceVersionIds, sourceDefinitionId: first.sourceDefinitionId, batchId: `${first.sourceDefinitionId}-${batches.length + 1}`,
      inputFingerprint: sourceTextHash(prepared.serializedInput), payloadBytes });
  }
  const workerCount = Math.min(maxParallelBatches, batches.length);
  const pendingPayloadBytes = batches.reduce((total, batch) => total + batch.payloadBytes, 0);
  const estimatedMilliseconds = estimateAssessmentMilliseconds(0, 0, pendingPayloadBytes, workerCount);
  return { recovery, batches, totalSourceCount: sources.length, cachedSourceCount: 0,
    recoveredSourceCount: recovery.completedSourceCount, pendingSourceCount: pending.length, batchCount: batches.length,
    workerCount, pendingPayloadBytes, estimatedMilliseconds };
}

export async function executeAssessmentBatches(connection, request, evaluatorInput, evaluate, report = () => {}, maxParallelBatches = 3) {
  const { recovery, batches, ...plan } = planAssessmentBatches(connection, request, evaluatorInput, maxParallelBatches);
  report({ state: 'plan', runId: request.runId, ...plan });
  for (const evaluationId of recovery.unfinishedEvaluationIds) {
    failEvaluation(connection, { binding: request.binding, runId: request.runId, evaluationId, failureCode: 'interrupted-before-result' });
  }
  const started = performance.now();
  let nextBatch = 0;
  let stopped = false;
  let completedPayloadBytes = 0;
  let completedWorkerMilliseconds = 0;
  let evaluatedSources = 0;
  let evaluatedBatches = 0;
  const failures = [];
  const remainingTime = () => estimateAssessmentMilliseconds(completedPayloadBytes, completedWorkerMilliseconds,
    plan.pendingPayloadBytes - completedPayloadBytes, maxParallelBatches);
  async function worker() {
    while (!stopped && nextBatch < batches.length) {
      const batchNumber = ++nextBatch;
      const batch = batches[batchNumber - 1];
      const batchStarted = performance.now();
      let recorded;
      try {
        recorded = recordEvaluationRequest(connection, { ...request, sourceVersionIds: batch.sourceVersionIds });
        if (recorded.inputFingerprint !== batch.inputFingerprint) throw new Error('Assessment inputs changed after execution planning');
        if (connection.isTransaction) throw new Error('Inference refused an open assessment transaction');
        report({ state: 'running', runId: request.runId, evaluationId: recorded.evaluationId, batchNumber, batchCount: batches.length,
          batchId: batch.batchId, sourceDefinitionId: batch.sourceDefinitionId, sourceCount: batch.sourceVersionIds.length });
        const result = await evaluate(recorded);
        commitAssessmentResults(connection, { binding: request.binding, runId: request.runId, evaluationId: recorded.evaluationId,
          inputFingerprint: recorded.inputFingerprint, result });
      } catch (error) {
        stopped = true;
        failures.push(error);
        if (recorded && connection.get('SELECT outcome FROM evaluations WHERE id = ?', [recorded.evaluationId])?.outcome === 'running') {
          failEvaluation(connection, { binding: request.binding, runId: request.runId, evaluationId: recorded.evaluationId, failureCode: 'evaluator-or-result-failed' });
        }
        report({ state: 'failed', runId: request.runId, batchNumber, batchCount: batches.length,
          batchElapsedMilliseconds: Math.round(performance.now() - batchStarted), totalElapsedMilliseconds: Math.round(performance.now() - started),
          remainingMilliseconds: remainingTime(), failureCode: 'evaluator-or-result-failed' });
        return;
      }
      const batchElapsedMilliseconds = Math.round(performance.now() - batchStarted);
      completedPayloadBytes += batch.payloadBytes;
      completedWorkerMilliseconds += batchElapsedMilliseconds;
      evaluatedSources += batch.sourceVersionIds.length;
      evaluatedBatches += 1;
      const progress = readCommittedProgress(connection, request.runId);
      const elapsed = Math.round(performance.now() - started);
      report({ state: 'passed', runId: request.runId, evaluationId: recorded.evaluationId, batchNumber, batchCount: batches.length,
        sourceCount: progress.completedSources, assessmentCount: progress.completedAssessments, totalElapsedMilliseconds: elapsed,
        batchElapsedMilliseconds, remainingMilliseconds: remainingTime() });
    }
  }
  const settled = await Promise.allSettled(Array.from({ length: plan.workerCount }, () => worker().catch(error => {
    stopped = true;
    throw error;
  })));
  if (failures.length > 0 || settled.some(result => result.status === 'rejected')) {
    throw new Error('Assessment execution failed; in-flight work settled, committed results were retained, and unresolved sources require explicit recovery');
  }
  const progress = readCommittedProgress(connection, request.runId);
  if (progress.completedSources !== plan.totalSourceCount) throw new Error('Assessment completion does not cover the pinned source set');
  const result = { runId: request.runId, ...progress, sourceCount: plan.totalSourceCount, cachedSourceCount: 0,
    recoveredSourceCount: recovery.completedSourceCount, evaluatedSourceCount: evaluatedSources, evaluatedBatchCount: evaluatedBatches,
    assessmentComplete: true, readyForUi: false };
  report({ state: 'complete', ...result, totalElapsedMilliseconds: Math.round(performance.now() - started) });
  return result;
}
