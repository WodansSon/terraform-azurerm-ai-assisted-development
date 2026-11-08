import { requireSourceObject, sourceTextHash } from './WorkbenchSourceRecords.mjs';
import { prepareEvaluationInput, readAssessmentRecoveryPlan, readRecordedReconciliationRequest, recordEvaluationRequest, commitReconciliationComponents, failEvaluation } from './WorkbenchEvaluations.mjs';
import { measureAssessmentInputBytes, estimateAssessmentMilliseconds } from './WorkbenchAssessmentExecution.mjs';
import { commitSynthesisResults } from './WorkbenchReconciliationResults.mjs';
import { prepareAdjudicationInput, recordAdjudicationRequest, commitAdjudicationResults } from './WorkbenchAdjudication.mjs';
import { completeNativeAnalysis } from './WorkbenchAnalysisCompletion.mjs';
import { readWorkbenchBudgets, planConsolidationShards, payloadBudgetError } from './WorkbenchSharding.mjs';
import { commitConsolidationMerge, readConsolidatedComponents } from './WorkbenchConsolidation.mjs';

function reconciliationRequest(connection, request, phase, assessmentResultIds, componentIds) {
  const sourceVersionIds = [...new Set(assessmentResultIds.map(id => {
    const result = connection.get('SELECT source_version_id FROM assessment_results WHERE id = ?', [id]);
    if (!result) throw new Error('Downstream planning requires captured assessment results');
    return result.source_version_id;
  }))].sort((left, right) => left - right);
  return { binding: request.binding, runId: request.runId, profileId: request.reconciliationProfileId,
    sourceVersionIds, assessmentResultIds, reconciliationPhase: phase, ...(componentIds ? { componentIds } : {}),
    ...(phase === 'consolidation' && request.routingProfileId !== undefined ? { componentProfileId: request.routingProfileId } : {}) };
}

export function planNativeReconciliation(connection, request, phase, evaluatorInput) {
  if (!['routing', 'consolidation', 'synthesis'].includes(phase)) throw new Error('Downstream reconciliation phase is not supported');
  measureAssessmentInputBytes('', evaluatorInput);
  const recovery = readAssessmentRecoveryPlan(connection, { binding: request.binding, runId: request.runId, profileId: request.sourceProfileId });
  if (recovery.remainingSourceVersionIds.length || recovery.unfinishedEvaluationIds.length) {
    throw new Error('Downstream planning requires complete committed source assessment');
  }
  const budgets = readWorkbenchBudgets(request.budgets);
  const budget = budgets.evaluatorPayloadBudgetBytes;
  const jobs = [];
  let routingComponents;
  const prepare = (ids, components, canonical = false) => {
    const preparedRequest = reconciliationRequest(connection, request, phase, ids, components);
    if (phase === 'routing') preparedRequest.profileId = request.routingProfileId ?? request.reconciliationProfileId;
    if (canonical) {
      delete preparedRequest.componentIds;
      preparedRequest.consolidatedComponentIds = components;
    }
    const prepared = prepareEvaluationInput(connection, preparedRequest);
    return { request: preparedRequest, phase, inputFingerprint: sourceTextHash(prepared.serializedInput),
      inputBytes: Buffer.byteLength(prepared.serializedInput, 'utf8'), payloadBytes: measureAssessmentInputBytes(prepared.serializedInput, evaluatorInput) };
  };
  const fits = job => job.inputBytes <= budgets.stagePayloadBudgetBytes && job.payloadBytes <= budget;
  const oversized = job => payloadBudgetError(phase, job.inputBytes > budgets.stagePayloadBudgetBytes ? job.inputBytes : job.payloadBytes,
    job.inputBytes > budgets.stagePayloadBudgetBytes ? budgets.stagePayloadBudgetBytes : budget);
  if (phase === 'routing' && request.routingProfileId !== undefined && request.routingProfileId !== request.reconciliationProfileId) {
    const evaluations = connection.all(`SELECT evaluation.id, evaluation.input_fingerprint FROM evaluations evaluation JOIN run_evaluations used ON used.evaluation_id = evaluation.id
      WHERE used.run_id = ? AND evaluation.evaluator_profile_id = ? AND evaluation.outcome = 'complete' ORDER BY evaluation.id`, [request.runId, request.routingProfileId]);
    const covered = new Set();
    const expected = connection.all(`SELECT result.id FROM assessment_results result JOIN run_evaluations used ON used.evaluation_id = result.evaluation_id
      WHERE used.run_id = ?`, [request.runId]).map(row => row.id);
    for (const evaluation of evaluations) {
      const recorded = readRecordedReconciliationRequest(connection, request.binding, request.runId, evaluation.id, 'routing');
      if (recorded.assessmentResultIds.some(id => covered.has(id) || !expected.includes(id))) throw new Error('Prior native routing recovery refuses overlapping or foreign coverage');
      const prepared = prepareEvaluationInput(connection, recorded);
      if (sourceTextHash(prepared.serializedInput) !== evaluation.input_fingerprint) throw new Error('Prior native routing recovery refuses changed recorded evidence');
      recorded.assessmentResultIds.forEach(id => covered.add(id));
      jobs.push({ request: recorded, phase, inputFingerprint: evaluation.input_fingerprint, payloadBytes: measureAssessmentInputBytes(prepared.serializedInput, evaluatorInput) });
    }
    if (covered.size !== expected.length) throw new Error('Prior native routing recovery requires complete committed coverage');
  } else if (phase === 'routing') {
    const ids = connection.all(`SELECT result.id FROM assessment_results result JOIN run_evaluations used ON used.evaluation_id = result.evaluation_id
      JOIN evaluations evaluation ON evaluation.id = result.evaluation_id WHERE used.run_id = ? AND evaluation.outcome = 'complete'
      AND evaluation.evaluator_profile_id = ? ORDER BY result.id`, [request.runId, request.sourceProfileId]).map(row => row.id);
    let members = [];
    let pending;
    for (const id of ids) {
      const candidate = prepare([...members, id]);
      if (!fits(candidate)) {
        if (members.length === 0) throw oversized(candidate);
        jobs.push(pending);
        members = [];
        pending = prepare([id]);
        if (!fits(pending)) throw oversized(pending);
      } else pending = candidate;
      members.push(id);
    }
    if (pending) jobs.push(pending);
  } else if (phase === 'synthesis' && request.consolidatedMergeId !== undefined) {
    for (const component of readConsolidatedComponents(connection, request.runId, request.reconciliationProfileId, request.consolidatedMergeId)) {
      const job = prepare(component.assessmentResultIds, [component.componentId], true);
      if (!fits(job)) throw oversized(job);
      jobs.push(job);
    }
  } else {
    const parentPhase = phase === 'consolidation' ? 'routing' : 'consolidation';
    const components = connection.all(`SELECT component.id FROM reconciliation_components component JOIN evaluations evaluation ON evaluation.id = component.evaluation_id
      JOIN run_evaluations used ON used.evaluation_id = evaluation.id WHERE used.run_id = ? AND evaluation.outcome = 'complete'
      AND evaluation.evaluator_profile_id = ? AND component.phase_code = ? ORDER BY component.id`,
    [request.runId, phase === 'consolidation' ? request.routingProfileId ?? request.reconciliationProfileId : request.reconciliationProfileId, parentPhase]).map(row => row.id);
    const memberIds = componentId => connection.all('SELECT assessment_result_id AS id FROM reconciliation_component_members WHERE component_id = ? ORDER BY assessment_result_id',
      [componentId]).map(row => row.id);
    if (phase === 'consolidation' && components.length) {
      routingComponents = components.map(componentId => ({ componentId,
        semanticSummary: connection.get('SELECT semantic_summary FROM reconciliation_components WHERE id = ?', [componentId]).semantic_summary,
        assessmentResultIds: memberIds(componentId) }));
      const shards = planConsolidationShards(routingComponents, budgets, members => prepare(members.flatMap(component => component.assessmentResultIds), members.map(component => component.componentId)).payloadBytes);
      for (const shard of shards) jobs.push(prepare(shard.componentIds.flatMap(memberIds), shard.componentIds));
    } else for (const componentId of components) {
      const job = prepare(memberIds(componentId), [componentId]);
      if (!fits(job)) throw oversized(job);
      jobs.push(job);
    }
  }
  return { phase, jobs, budgets, ...(routingComponents ? { routingComponents } : {}), batchCount: jobs.length,
    pendingPayloadBytes: jobs.reduce((total, job) => total + job.payloadBytes, 0) };
}

export function planNativeAdjudication(connection, request, evaluatorInput) {
  measureAssessmentInputBytes('', evaluatorInput);
  const ids = connection.all(`SELECT version.id FROM group_versions version JOIN evaluations evaluation ON evaluation.id = version.synthesis_evaluation_id
    JOIN run_evaluations used ON used.evaluation_id = evaluation.id WHERE used.run_id = ? AND evaluation.outcome = 'complete'
    AND evaluation.evaluator_profile_id = ? ORDER BY version.id`, [request.runId, request.reconciliationProfileId]).map(row => row.id);
  const prepare = (left, right) => {
    const preparedRequest = { binding: request.binding, runId: request.runId, profileId: request.adjudicationProfileId, groupVersionIds: left,
      ...(right ? { rightGroupVersionIds: right } : {}) };
    const prepared = prepareAdjudicationInput(connection, preparedRequest);
    return { request: preparedRequest, phase: 'adjudication', inputFingerprint: sourceTextHash(prepared.serializedInput),
      payloadBytes: measureAssessmentInputBytes(prepared.serializedInput, evaluatorInput), comparisonCount: prepared.input.comparisonPairs.length };
  };
  const budgets = readWorkbenchBudgets(request.budgets);
  const budget = budgets.evaluatorPayloadBudgetBytes;
  const jobs = [];
  const chunks = [];
  let members = [];
  let pending;
  for (const id of ids) {
    const candidate = prepare([...members, id]);
    if (candidate.payloadBytes > budget) {
      if (!members.length) throw new Error('A final group and its complete adjudication baseline exceed the evaluator payload budget');
      chunks.push(members);
      jobs.push(pending);
      members = [];
      pending = prepare([id]);
      if (pending.payloadBytes > budget) throw new Error('A final group and its complete adjudication baseline exceed the evaluator payload budget');
    } else pending = candidate;
    members.push(id);
  }
  if (pending) { chunks.push(members); jobs.push(pending); }
  const cross = (left, right) => {
    const job = prepare(left, right);
    if (job.payloadBytes <= budget) { jobs.push(job); return; }
    if (left.length > 1 && left.length >= right.length) {
      const midpoint = Math.ceil(left.length / 2);
      cross(left.slice(0, midpoint), right);
      cross(left.slice(midpoint), right);
    } else if (right.length > 1) {
      const midpoint = Math.ceil(right.length / 2);
      cross(left, right.slice(0, midpoint));
      cross(left, right.slice(midpoint));
    } else throw new Error('An indivisible cross-group comparison exceeds the evaluator payload budget');
  };
  for (const [index, left] of chunks.entries()) for (const right of chunks.slice(index + 1)) cross(left, right);
  const comparisons = jobs.filter(job => job.comparisonCount > 0);
  return { phase: 'adjudication', jobs: comparisons, batchCount: comparisons.length, pendingPayloadBytes: comparisons.reduce((total, job) => total + job.payloadBytes, 0) };
}

function recoverJob(connection, request, job) {
  const evaluations = connection.all(`SELECT evaluation.* FROM evaluations evaluation JOIN run_evaluations used ON used.evaluation_id = evaluation.id
    WHERE used.run_id = ? AND evaluation.evaluator_profile_id = ? AND evaluation.input_fingerprint = ? ORDER BY evaluation.id`,
  [request.runId, job.request.profileId, job.inputFingerprint]);
  let completed;
  for (const evaluation of evaluations) {
    const inputs = connection.all('SELECT * FROM evaluation_inputs WHERE evaluation_id = ? ORDER BY id', [evaluation.id]);
    const recordedRequest = job.phase === 'adjudication' ? { binding: request.binding, runId: request.runId, profileId: job.request.profileId,
      groupVersionIds: inputs.filter(row => row.role_code === 'group-left').map(row => row.group_version_id),
      rightGroupVersionIds: inputs.filter(row => row.role_code === 'group-right').map(row => row.group_version_id) } :
      readRecordedReconciliationRequest(connection, request.binding, request.runId, evaluation.id, job.phase);
    const prepared = job.phase === 'adjudication' ? prepareAdjudicationInput(connection, recordedRequest) : prepareEvaluationInput(connection, recordedRequest);
    if (sourceTextHash(prepared.serializedInput) !== job.inputFingerprint) throw new Error('Downstream recovery refuses changed recorded input dependencies');
    if (evaluation.outcome === 'complete') {
      if (completed) throw new Error('Downstream recovery refuses duplicate completed request coverage');
      completed = evaluation;
    } else if (evaluation.outcome === 'running') {
      failEvaluation(connection, { binding: request.binding, runId: request.runId, evaluationId: evaluation.id, failureCode: 'interrupted-before-result' });
    }
  }
  return completed;
}

async function executePhase(connection, request, plan, evaluatorInput, evaluate, report, maxWorkers) {
  const recovered = plan.jobs.map(job => recoverJob(connection, request, job));
  const evaluationIds = recovered.map(evaluation => evaluation?.id);
  const pending = plan.jobs.filter((job, index) => !recovered[index]);
  const workerCount = Math.min(maxWorkers, pending.length);
  const bytes = pending.reduce((total, job) => total + job.payloadBytes, 0);
  report({ state: 'plan', phase: plan.phase, runId: request.runId, batchCount: pending.length,
    recoveredBatchCount: plan.jobs.length - pending.length, workerCount, pendingPayloadBytes: bytes,
    estimatedMilliseconds: estimateAssessmentMilliseconds(0, 0, bytes, workerCount) });
  const started = performance.now();
  let next = 0;
  let stopped = false;
  let completedBytes = 0;
  let workerMilliseconds = 0;
  let completedBatches = 0;
  const failures = [];
  const remainingTime = () => estimateAssessmentMilliseconds(completedBytes, workerMilliseconds, bytes - completedBytes, workerCount);
  async function worker() {
    while (!stopped && next < pending.length) {
      const batchNumber = ++next;
      const job = pending[batchNumber - 1];
      const batchStarted = performance.now();
      let recorded;
      try {
        recorded = job.phase === 'adjudication' ? recordAdjudicationRequest(connection, job.request) : recordEvaluationRequest(connection, job.request);
        if (recorded.inputFingerprint !== job.inputFingerprint) throw new Error('Downstream inputs changed after planning');
        if (connection.isTransaction) throw new Error('Downstream inference refuses an open transaction');
        report({ state: 'running', phase: plan.phase, runId: request.runId, evaluationId: recorded.evaluationId, batchNumber, batchCount: pending.length });
        const result = await evaluate(recorded, { phase: job.phase, evaluatorInput });
        const command = { binding: request.binding, runId: request.runId, evaluationId: recorded.evaluationId, inputFingerprint: recorded.inputFingerprint, result };
        const commit = job.phase === 'adjudication' ? commitAdjudicationResults : job.phase === 'synthesis' ? commitSynthesisResults : commitReconciliationComponents;
        const committed = commit(connection, command);
        evaluationIds[plan.jobs.indexOf(job)] = recorded.evaluationId;
        const elapsed = Math.round(performance.now() - batchStarted);
        completedBytes += job.payloadBytes;
        workerMilliseconds += elapsed;
        completedBatches += 1;
        report({ state: 'passed', phase: plan.phase, runId: request.runId, evaluationId: recorded.evaluationId, batchNumber,
          batchCount: pending.length, completedBatchCount: completedBatches, resultCount: committed.comparisonCount ?? committed.dispositionCount ?? committed.componentIds.length,
          batchElapsedMilliseconds: elapsed, totalElapsedMilliseconds: Math.round(performance.now() - started), remainingMilliseconds: remainingTime() });
      } catch (error) {
        stopped = true;
        failures.push(error);
        if (recorded && connection.get('SELECT outcome FROM evaluations WHERE id = ?', [recorded.evaluationId])?.outcome === 'running') {
          failEvaluation(connection, { binding: request.binding, runId: request.runId, evaluationId: recorded.evaluationId, failureCode: 'evaluator-or-result-failed' });
        }
        report({ state: 'failed', phase: plan.phase, runId: request.runId, batchNumber, batchCount: pending.length,
          batchElapsedMilliseconds: Math.round(performance.now() - batchStarted), totalElapsedMilliseconds: Math.round(performance.now() - started),
          failureCode: 'evaluator-or-result-failed' });
      }
    }
  }
  const settled = await Promise.allSettled(Array.from({ length: workerCount }, () => worker().catch(error => { stopped = true; throw error; })));
  if (failures.length || settled.some(result => result.status === 'rejected')) {
    throw new Error(`Native ${plan.phase} execution failed; in-flight jobs settled, committed results were retained, and the analysis head was not advanced`);
  }
  return { evaluationIds, batchCount: plan.jobs.length, evaluatedBatchCount: pending.length,
    recoveredBatchCount: plan.jobs.length - pending.length, totalElapsedMilliseconds: Math.round(performance.now() - started) };
}

export async function executeNativeDownstream(connection, request, evaluatorInputs, evaluate, report = () => {}, maxWorkers = 3) {
  const fields = ['binding', 'runId', 'sourceProfileId', 'reconciliationProfileId', 'adjudicationProfileId', 'expectedHeadRunId'];
  requireSourceObject(request, [...fields, 'budgets', 'routingProfileId'], fields, 'Native downstream execution');
  readWorkbenchBudgets(request.budgets);
  if (!Number.isSafeInteger(maxWorkers) || maxWorkers < 1 || maxWorkers > 16 || typeof evaluate !== 'function') {
    throw new Error('Native downstream execution requires a supported worker count and evaluator');
  }
  const head = connection.get('SELECT run_id FROM workspace_analysis_head WHERE workspace_id = 1')?.run_id ?? null;
  if (request.expectedHeadRunId !== head) throw new Error('Native downstream execution refuses a changed analysis head before inference');
  for (const [task, profileId] of [['reconciliation', request.reconciliationProfileId], ['adjudication', request.adjudicationProfileId],
    ...(request.routingProfileId !== undefined ? [['reconciliation', request.routingProfileId]] : [])]) {
    const profile = connection.get(`SELECT profile.* FROM evaluator_profiles profile JOIN analysis_run_llm_assignments assigned
      ON assigned.assignment_id = profile.llm_assignment_id AND assigned.task_code = profile.task_code WHERE assigned.run_id = ? AND profile.id = ? AND profile.task_code = ?`,
    [request.runId, profileId, task]);
    const input = evaluatorInputs?.[task];
    measureAssessmentInputBytes('', input);
    if (!profile || profile.prompt_sha256 !== sourceTextHash(input.prompt) || profile.result_contract_sha256 !== sourceTextHash(input.schema)) {
      throw new Error('Downstream evaluator instructions do not match the pinned task profile');
    }
  }
  let consolidatedMergeId;
  for (const phase of ['routing', 'consolidation', 'synthesis', 'adjudication']) {
    const task = phase === 'adjudication' ? 'adjudication' : 'reconciliation';
    const phaseRequest = { ...request, ...(consolidatedMergeId !== undefined ? { consolidatedMergeId } : {}) };
    const plan = phase === 'adjudication' ? planNativeAdjudication(connection, phaseRequest, evaluatorInputs[task]) :
      planNativeReconciliation(connection, phaseRequest, phase, evaluatorInputs[task]);
    const completed = await executePhase(connection, request, plan, evaluatorInputs[task], evaluate, report, maxWorkers);
    if (phase === 'consolidation' && plan.jobs.length) consolidatedMergeId = commitConsolidationMerge(connection, request, plan, completed.evaluationIds);
    report({ state: 'phase-complete', phase, runId: request.runId, batchCount: completed.batchCount, evaluatedBatchCount: completed.evaluatedBatchCount,
      recoveredBatchCount: completed.recoveredBatchCount, totalElapsedMilliseconds: completed.totalElapsedMilliseconds });
  }
  const completionRequest = Object.fromEntries(fields.map(field => [field, request[field]]));
  if (request.routingProfileId !== undefined) completionRequest.routingProfileId = request.routingProfileId;
  if (consolidatedMergeId !== undefined) completionRequest.consolidatedMergeId = consolidatedMergeId;
  const completed = completeNativeAnalysis(connection, completionRequest);
  report({ state: 'complete', ...completed });
  return completed;
}
