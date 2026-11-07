import { requireSourceObject, sourceTextHash } from './WorkbenchSourceRecords.mjs';
import { prepareEvaluationInput, readAssessmentRecoveryPlan, recordEvaluationRequest, commitReconciliationComponents, failEvaluation } from './WorkbenchEvaluations.mjs';
import { measureAssessmentInputBytes, estimateAssessmentMilliseconds } from './WorkbenchAssessmentExecution.mjs';
import { commitSynthesisResults } from './WorkbenchReconciliationResults.mjs';
import { prepareAdjudicationInput, recordAdjudicationRequest, commitAdjudicationResults } from './WorkbenchAdjudication.mjs';
import { completeNativeAnalysis } from './WorkbenchAnalysisCompletion.mjs';

function reconciliationRequest(connection, request, phase, assessmentResultIds, componentIds) {
  const sourceVersionIds = [...new Set(assessmentResultIds.map(id => {
    const result = connection.get('SELECT source_version_id FROM assessment_results WHERE id = ?', [id]);
    if (!result) throw new Error('Downstream planning requires captured assessment results');
    return result.source_version_id;
  }))].sort((left, right) => left - right);
  return { binding: request.binding, runId: request.runId, profileId: request.reconciliationProfileId,
    sourceVersionIds, assessmentResultIds, reconciliationPhase: phase, ...(componentIds ? { componentIds } : {}) };
}

export function planNativeReconciliation(connection, request, phase, evaluatorInput) {
  if (!['routing', 'consolidation', 'synthesis'].includes(phase)) throw new Error('Downstream reconciliation phase is not supported');
  measureAssessmentInputBytes('', evaluatorInput);
  const recovery = readAssessmentRecoveryPlan(connection, { binding: request.binding, runId: request.runId, profileId: request.sourceProfileId });
  if (recovery.remainingSourceVersionIds.length || recovery.unfinishedEvaluationIds.length) {
    throw new Error('Downstream planning requires complete committed source assessment');
  }
  const budget = 393216;
  const jobs = [];
  const prepare = (ids, components) => {
    const preparedRequest = reconciliationRequest(connection, request, phase, ids, components);
    const prepared = prepareEvaluationInput(connection, preparedRequest);
    return { request: preparedRequest, phase, inputFingerprint: sourceTextHash(prepared.serializedInput),
      payloadBytes: measureAssessmentInputBytes(prepared.serializedInput, evaluatorInput) };
  };
  if (phase === 'routing') {
    const ids = connection.all(`SELECT result.id FROM assessment_results result JOIN run_evaluations used ON used.evaluation_id = result.evaluation_id
      JOIN evaluations evaluation ON evaluation.id = result.evaluation_id WHERE used.run_id = ? AND evaluation.outcome = 'complete'
      AND evaluation.evaluator_profile_id = ? ORDER BY result.id`, [request.runId, request.sourceProfileId]).map(row => row.id);
    let members = [];
    let pending;
    for (const id of ids) {
      const candidate = prepare([...members, id]);
      if (candidate.payloadBytes > budget) {
        if (members.length === 0) throw new Error('A routing assessment and its complete evidence exceed the evaluator payload budget');
        jobs.push(pending);
        members = [];
        pending = prepare([id]);
        if (pending.payloadBytes > budget) throw new Error('A routing assessment and its complete evidence exceed the evaluator payload budget');
      } else pending = candidate;
      members.push(id);
    }
    if (pending) jobs.push(pending);
  } else {
    const parentPhase = phase === 'consolidation' ? 'routing' : 'consolidation';
    const components = connection.all(`SELECT component.id FROM reconciliation_components component JOIN evaluations evaluation ON evaluation.id = component.evaluation_id
      JOIN run_evaluations used ON used.evaluation_id = evaluation.id WHERE used.run_id = ? AND evaluation.outcome = 'complete'
      AND evaluation.evaluator_profile_id = ? AND component.phase_code = ? ORDER BY component.id`,
    [request.runId, request.reconciliationProfileId, parentPhase]).map(row => row.id);
    const memberIds = componentId => connection.all('SELECT assessment_result_id AS id FROM reconciliation_component_members WHERE component_id = ? ORDER BY assessment_result_id',
      [componentId]).map(row => row.id);
    if (phase === 'consolidation' && components.length) {
      const job = prepare(components.flatMap(memberIds), components);
      if (job.payloadBytes > budget) throw new Error('The complete global consolidation envelope exceeds the evaluator payload budget');
      jobs.push(job);
    } else for (const componentId of components) {
      const job = prepare(memberIds(componentId), [componentId]);
      if (job.payloadBytes > budget) throw new Error('A consolidated component and its complete synthesis evidence exceed the evaluator payload budget');
      jobs.push(job);
    }
  }
  return { phase, jobs, batchCount: jobs.length, pendingPayloadBytes: jobs.reduce((total, job) => total + job.payloadBytes, 0) };
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
  const budget = 393216;
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
      rightGroupVersionIds: inputs.filter(row => row.role_code === 'group-right').map(row => row.group_version_id) } : {
      binding: request.binding, runId: request.runId, profileId: job.request.profileId, reconciliationPhase: job.phase,
      sourceVersionIds: inputs.filter(row => row.role_code === 'source').map(row => row.source_version_id),
      assessmentResultIds: inputs.filter(row => row.role_code === 'assessment-result').map(row => row.assessment_result_id),
      ...(job.phase === 'routing' ? {} : { componentIds: inputs.filter(row => row.role_code === 'component').map(row => row.reconciliation_component_id) }),
    };
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
  const pending = plan.jobs.filter(job => !recoverJob(connection, request, job));
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
  report({ state: 'phase-complete', phase: plan.phase, runId: request.runId, batchCount: plan.jobs.length,
    evaluatedBatchCount: pending.length, recoveredBatchCount: plan.jobs.length - pending.length, totalElapsedMilliseconds: Math.round(performance.now() - started) });
}

export async function executeNativeDownstream(connection, request, evaluatorInputs, evaluate, report = () => {}, maxWorkers = 3) {
  const fields = ['binding', 'runId', 'sourceProfileId', 'reconciliationProfileId', 'adjudicationProfileId', 'expectedHeadRunId'];
  requireSourceObject(request, fields, fields, 'Native downstream execution');
  if (!Number.isSafeInteger(maxWorkers) || maxWorkers < 1 || maxWorkers > 16 || typeof evaluate !== 'function') {
    throw new Error('Native downstream execution requires a supported worker count and evaluator');
  }
  const head = connection.get('SELECT run_id FROM workspace_analysis_head WHERE workspace_id = 1')?.run_id ?? null;
  if (request.expectedHeadRunId !== head) throw new Error('Native downstream execution refuses a changed analysis head before inference');
  for (const [task, profileId] of [['reconciliation', request.reconciliationProfileId], ['adjudication', request.adjudicationProfileId]]) {
    const profile = connection.get(`SELECT profile.* FROM evaluator_profiles profile JOIN analysis_run_llm_assignments assigned
      ON assigned.assignment_id = profile.llm_assignment_id AND assigned.task_code = profile.task_code WHERE assigned.run_id = ? AND profile.id = ? AND profile.task_code = ?`,
    [request.runId, profileId, task]);
    const input = evaluatorInputs?.[task];
    measureAssessmentInputBytes('', input);
    if (!profile || profile.prompt_sha256 !== sourceTextHash(input.prompt) || profile.result_contract_sha256 !== sourceTextHash(input.schema)) {
      throw new Error('Downstream evaluator instructions do not match the pinned task profile');
    }
  }
  for (const phase of ['routing', 'consolidation', 'synthesis', 'adjudication']) {
    const task = phase === 'adjudication' ? 'adjudication' : 'reconciliation';
    const plan = phase === 'adjudication' ? planNativeAdjudication(connection, request, evaluatorInputs[task]) :
      planNativeReconciliation(connection, request, phase, evaluatorInputs[task]);
    await executePhase(connection, request, plan, evaluatorInputs[task], evaluate, report, maxWorkers);
  }
  const completed = completeNativeAnalysis(connection, request);
  report({ state: 'complete', ...completed });
  return completed;
}
