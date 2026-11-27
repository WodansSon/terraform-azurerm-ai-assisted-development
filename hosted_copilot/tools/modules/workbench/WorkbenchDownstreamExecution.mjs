import { requireSourceObject, sourceTextHash } from './WorkbenchSourceRecords.mjs';
import { prepareEvaluationInput, readAssessmentRecoveryPlan, readRecordedReconciliationRequest, recordEvaluationRequest, commitReconciliationComponents, failEvaluation, withEvaluationPlanningSnapshot } from './WorkbenchEvaluations.mjs';
import { measureAssessmentInputBytes, estimateAssessmentMilliseconds } from './WorkbenchAssessmentExecution.mjs';
import { commitSynthesisResults } from './WorkbenchReconciliationResults.mjs';
import { prepareAdjudicationInput, readRecordedAdjudicationRequest, recordAdjudicationRequest, commitAdjudicationResults, assertAdjudicationReady } from './WorkbenchAdjudication.mjs';
import { completeNativeAnalysis } from './WorkbenchAnalysisCompletion.mjs';
import { readWorkbenchBudgets, planConsolidationShards, planAdjudicationShards, payloadBudgetError, synthesisAssessmentLimit } from './WorkbenchSharding.mjs';
import { commitConsolidationMerge, readConsolidatedComponents } from './WorkbenchConsolidation.mjs';
import { readAdjudicationComponents } from './WorkbenchRelationshipComponents.mjs';
import { describeEvaluationFailure } from './WorkbenchEvaluationFailures.mjs';

// Derive source scope from the selected assessments and carry the parent component profile when consolidation needs it.
function reconciliationRequest(connection, request, phase, assessmentResultIds, ruleVersionIds, componentIds) {
  const sourceVersionIds = [...new Set(assessmentResultIds.map(id => {
    const result = connection.get('SELECT source_version_id FROM assessment_results WHERE id = ?', [id]);
    if (!result) throw new Error('Downstream planning requires captured assessment results');
    return result.source_version_id;
  }))].sort((left, right) => left - right);
  return { binding: request.binding, runId: request.runId, profileId: request.reconciliationProfileId,
    sourceVersionIds, assessmentResultIds, ruleVersionIds, reconciliationPhase: phase, ...(componentIds ? { componentIds } : {}),
    ...(phase === 'consolidation' && request.routingProfileId !== undefined ? { componentProfileId: request.routingProfileId } : {}) };
}

// Plan phase-specific bounded requests while retaining completed synthesis scopes and keeping semantic components whole.
export function planNativeReconciliation(connection, request, phase, evaluatorInput) {
  return withEvaluationPlanningSnapshot(connection, snapshot => planReconciliationSnapshot(snapshot, request, phase, evaluatorInput));
}

function planReconciliationSnapshot(connection, request, phase, evaluatorInput) {
  if (!['routing', 'consolidation', 'synthesis'].includes(phase)) throw new Error('Downstream reconciliation phase is not supported');
  measureAssessmentInputBytes('', evaluatorInput);
  const recovery = readAssessmentRecoveryPlan(connection, { binding: request.binding, runId: request.runId, profileId: request.sourceProfileId });
  if (recovery.remainingSourceVersionIds.length || recovery.unfinishedEvaluationIds.length) {
    throw new Error('Downstream planning requires complete committed source assessment');
  }
  const budgets = readWorkbenchBudgets(request.budgets);
  const budget = budgets.evaluatorPayloadBudgetBytes;
  const jobs = [];
  const completedSynthesisMembers = new Set();
  if (phase === 'synthesis') {
    const recorded = connection.all(`SELECT evaluation.id, evaluation.input_fingerprint FROM evaluations evaluation
      JOIN run_evaluations used ON used.evaluation_id = evaluation.id WHERE used.run_id = ? AND evaluation.evaluator_profile_id = ?
      AND evaluation.outcome = 'complete' AND (EXISTS(SELECT 1 FROM evaluation_inputs input
        LEFT JOIN reconciliation_components component ON component.id = input.reconciliation_component_id
        WHERE input.evaluation_id = evaluation.id AND (input.role_code = 'merged-component' OR (input.role_code = 'component' AND component.phase_code = 'consolidation')))
        OR (EXISTS(SELECT 1 FROM evaluation_inputs input WHERE input.evaluation_id = evaluation.id AND input.role_code = 'assessment-result')
          AND NOT EXISTS(SELECT 1 FROM reconciliation_components component WHERE component.evaluation_id = evaluation.id)))
      ORDER BY evaluation.id`, [request.runId, request.reconciliationProfileId]);
    for (const evaluation of recorded) {
      const recordedRequest = readRecordedReconciliationRequest(connection, request.binding, request.runId, evaluation.id, phase);
      const prepared = prepareEvaluationInput(connection, recordedRequest);
      if (sourceTextHash(prepared.serializedInput) !== evaluation.input_fingerprint ||
          recordedRequest.assessmentResultIds.some(id => completedSynthesisMembers.has(id))) {
        throw new Error('Synthesis recovery refuses changed evidence or overlapping completed scope');
      }
      recordedRequest.assessmentResultIds.forEach(id => completedSynthesisMembers.add(id));
      jobs.push({ request: recordedRequest, phase, inputFingerprint: evaluation.input_fingerprint,
        inputBytes: Buffer.byteLength(prepared.serializedInput), payloadBytes: measureAssessmentInputBytes(prepared.serializedInput, evaluatorInput) });
    }
  }
  const recoveredSynthesisJobs = jobs.length;
  let routingComponents;
  // Measure the exact request after choosing ordinary or merged component references, including all evaluator context.
  const componentRuleIds = (components, canonical) => [...new Set(components.flatMap(id => connection.all(
    `SELECT rule_version_id AS id FROM ${canonical ? 'consolidated_component_rules' : 'reconciliation_component_rules'} WHERE component_id = ? ORDER BY rule_version_id`, [id]).map(row => row.id)))].sort((left, right) => left - right);
  const prepare = (ids, components, canonical = false, rules = []) => {
    const preparedRequest = reconciliationRequest(connection, request, phase, ids,
      components ? componentRuleIds(components, canonical) : rules, components);
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
  // Combine only pending independent synthesis components; completed request boundaries must remain recoverable.
  const appendSynthesisJob = (job, canonical) => {
    const previous = jobs.length > recoveredSynthesisJobs ? jobs.at(-1) : null;
    const field = canonical ? 'consolidatedComponentIds' : 'componentIds';
    if (previous && Array.isArray(previous.request[field]) &&
      previous.request.assessmentResultIds.length + job.request.assessmentResultIds.length <= synthesisAssessmentLimit &&
      Boolean(previous.request[field].length) === Boolean(job.request[field].length)) {
      const combined = prepare([...previous.request.assessmentResultIds, ...job.request.assessmentResultIds].toSorted((left, right) => left - right),
        [...new Set([...previous.request[field], ...job.request[field]])].toSorted((left, right) => left - right), canonical);
      if (fits(combined)) { jobs[jobs.length - 1] = combined; return; }
    }
    jobs.push(job);
  };
  const appendSynthesisComponent = (assessmentIds, componentIds, canonical = false) => {
    // Baseline-only components remain covered by consolidation and do not manufacture source recommendations.
    if (!assessmentIds.length) return;
    const remaining = assessmentIds.filter(id => !completedSynthesisMembers.has(id));
    if (!remaining.length) return;
    if (remaining.length !== assessmentIds.length) throw new Error('Synthesis recovery refuses a partially completed semantic component');
    const job = prepare(assessmentIds, componentIds, canonical);
    if (!fits(job)) throw oversized(job);
    appendSynthesisJob(job, canonical);
  };
  const baselineRuleIds = connection.all(`SELECT member.rule_version_id AS id FROM catalog_members member
    JOIN analysis_run_contexts context ON context.base_catalog_id = member.catalog_id WHERE context.run_id = ?
    UNION SELECT member.rule_version_id AS id FROM protected_members member
    JOIN analysis_run_contexts context ON context.protected_snapshot_id = member.snapshot_id WHERE context.run_id = ? ORDER BY id`,
  [request.runId, request.runId]).map(row => row.id);
  if (phase === 'routing' && request.routingProfileId !== undefined && request.routingProfileId !== request.reconciliationProfileId) {
    const evaluations = connection.all(`SELECT evaluation.id, evaluation.input_fingerprint FROM evaluations evaluation JOIN run_evaluations used ON used.evaluation_id = evaluation.id
      WHERE used.run_id = ? AND evaluation.evaluator_profile_id = ? AND evaluation.outcome = 'complete' ORDER BY evaluation.id`, [request.runId, request.routingProfileId]);
    const covered = new Set();
    const coveredRules = new Set();
    const expected = connection.all(`SELECT result.id FROM assessment_results result JOIN run_evaluations used ON used.evaluation_id = result.evaluation_id
      WHERE used.run_id = ? AND result.hosted_applicable = 1`, [request.runId]).map(row => row.id);
    for (const evaluation of evaluations) {
      const recorded = readRecordedReconciliationRequest(connection, request.binding, request.runId, evaluation.id, 'routing');
      if (recorded.assessmentResultIds.some(id => covered.has(id) || !expected.includes(id))) throw new Error('Prior native routing recovery refuses overlapping or foreign coverage');
      if (recorded.ruleVersionIds.some(id => coveredRules.has(id) || !baselineRuleIds.includes(id))) throw new Error('Prior native routing recovery refuses overlapping or foreign rule coverage');
      const prepared = prepareEvaluationInput(connection, recorded);
      if (sourceTextHash(prepared.serializedInput) !== evaluation.input_fingerprint) throw new Error('Prior native routing recovery refuses changed recorded evidence');
      recorded.assessmentResultIds.forEach(id => covered.add(id));
      recorded.ruleVersionIds.forEach(id => coveredRules.add(id));
      jobs.push({ request: recorded, phase, inputFingerprint: evaluation.input_fingerprint, payloadBytes: measureAssessmentInputBytes(prepared.serializedInput, evaluatorInput) });
    }
    if (covered.size !== expected.length || coveredRules.size !== baselineRuleIds.length) throw new Error('Prior native routing recovery requires complete committed coverage');
  } else if (phase === 'routing') {
    const ids = connection.all(`SELECT result.id FROM assessment_results result JOIN run_evaluations used ON used.evaluation_id = result.evaluation_id
      JOIN evaluations evaluation ON evaluation.id = result.evaluation_id WHERE used.run_id = ? AND evaluation.outcome = 'complete'
      AND evaluation.evaluator_profile_id = ? AND result.hosted_applicable = 1 ORDER BY result.id`, [request.runId, request.sourceProfileId]).map(row => row.id);
    let members = [];
    let ruleMembers = [];
    let pending;
    for (const member of [...ids.map(id => ({ id, kind: 'assessment' })), ...baselineRuleIds.map(id => ({ id, kind: 'rule' }))]) {
      const nextAssessments = member.kind === 'assessment' ? [...members, member.id] : members;
      const nextRules = member.kind === 'rule' ? [...ruleMembers, member.id] : ruleMembers;
      const candidate = prepare(nextAssessments, undefined, false, nextRules);
      if (!fits(candidate)) {
        if (members.length + ruleMembers.length === 0) throw oversized(candidate);
        jobs.push(pending);
        members = [];
        ruleMembers = [];
        pending = prepare(member.kind === 'assessment' ? [member.id] : [], undefined, false, member.kind === 'rule' ? [member.id] : []);
        if (!fits(pending)) throw oversized(pending);
      } else pending = candidate;
      if (member.kind === 'assessment') members.push(member.id);
      else ruleMembers.push(member.id);
    }
    if (pending) jobs.push(pending);
  } else if (phase === 'synthesis' && request.consolidatedMergeId !== undefined) {
    for (const component of readConsolidatedComponents(connection, request.runId, request.reconciliationProfileId, request.consolidatedMergeId)) {
      appendSynthesisComponent(component.assessmentResultIds, [component.componentId], true);
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
        assessmentResultIds: memberIds(componentId), ruleVersionIds: componentRuleIds([componentId], false) }));
      const shards = planConsolidationShards(routingComponents, budgets, members => {
        const prepared = prepare(members.flatMap(component => component.assessmentResultIds), members.map(component => component.componentId));
        return { inputBytes: prepared.inputBytes, payloadBytes: prepared.payloadBytes };
      });
      for (const shard of shards) jobs.push(prepare(shard.componentIds.flatMap(memberIds), shard.componentIds));
    } else for (const componentId of components) appendSynthesisComponent(memberIds(componentId), [componentId]);
  }
  if (phase === 'synthesis') {
    const excluded = connection.all(`SELECT result.id FROM assessment_results result JOIN run_evaluations used ON used.evaluation_id = result.evaluation_id
      JOIN evaluations evaluation ON evaluation.id = result.evaluation_id WHERE used.run_id = ? AND evaluation.outcome = 'complete'
      AND evaluation.evaluator_profile_id = ? AND result.hosted_applicable = 0 ORDER BY result.id`, [request.runId, request.sourceProfileId]);
    for (const result of excluded) appendSynthesisComponent([result.id], []);
  }
  return { phase, jobs, budgets, ...(routingComponents ? { routingComponents } : {}), batchCount: jobs.length,
    pendingPayloadBytes: jobs.reduce((total, job) => total + job.payloadBytes, 0) };
}

// Size complete recorded relationship components rather than manufacturing a Cartesian set of comparison jobs.
export function planNativeAdjudication(connection, request, evaluatorInput) {
  measureAssessmentInputBytes('', evaluatorInput);
  assertAdjudicationReady(connection, request);
  const components = readAdjudicationComponents(connection, request.runId);
  const budgets = readWorkbenchBudgets(request.budgets);
  const parents = new Map();
  const prepare = scope => {
    const preparedRequest = { binding: request.binding, runId: request.runId, profileId: request.adjudicationProfileId, ...scope };
    const prepared = prepareAdjudicationInput(connection, preparedRequest, parents);
    return { request: preparedRequest, phase: 'adjudication', inputFingerprint: sourceTextHash(prepared.serializedInput),
      inputBytes: Buffer.byteLength(prepared.serializedInput, 'utf8'),
      payloadBytes: measureAssessmentInputBytes(prepared.serializedInput, evaluatorInput),
      comparisonCount: prepared.input.components.reduce((count, component) => count + component.relationships.length, 0) };
  };
  const jobs = planAdjudicationShards(components, budgets, prepare);
  return { phase: 'adjudication', jobs, batchCount: jobs.length, pendingPayloadBytes: jobs.reduce((total, job) => total + job.payloadBytes, 0),
    comparisonCount: jobs.reduce((total, job) => total + job.comparisonCount, 0), componentCount: components.length };
}

// Reuse exactly one compatible completed request and mark interrupted attempts failed without discarding history.
function recoverJob(connection, request, job) {
  const evaluations = connection.all(`SELECT evaluation.* FROM evaluations evaluation JOIN run_evaluations used ON used.evaluation_id = evaluation.id
    WHERE used.run_id = ? AND evaluation.evaluator_profile_id = ? AND evaluation.input_fingerprint = ? ORDER BY evaluation.id`,
  [request.runId, job.request.profileId, job.inputFingerprint]);
  let completed;
  for (const evaluation of evaluations) {
    const recordedRequest = job.phase === 'adjudication' ? readRecordedAdjudicationRequest(connection, {
      binding: request.binding, runId: request.runId, profileId: job.request.profileId, evaluationId: evaluation.id }) :
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

// Recover durable results, dispatch only pending jobs, and settle all active workers before reporting phase failure.
async function executePhase(connection, request, plan, evaluatorInput, evaluate, report, maxWorkers) {
  const recovered = plan.jobs.map(job => recoverJob(connection, request, job));
  const evaluationIds = recovered.map(evaluation => evaluation?.id);
  const pending = plan.jobs.filter((job, index) => !recovered[index]);
  const workerCount = Math.min(maxWorkers, pending.length);
  const bytes = pending.reduce((total, job) => total + job.payloadBytes, 0);
  report({ state: 'plan', phase: plan.phase, runId: request.runId, batchCount: pending.length,
    recoveredBatchCount: plan.jobs.length - pending.length, workerCount, pendingPayloadBytes: bytes,
    estimatedMilliseconds: estimateAssessmentMilliseconds(0, 0, bytes, workerCount),
    ...(plan.phase === 'adjudication' ? { comparisonCount: plan.comparisonCount, componentCount: plan.componentCount } : {}) });
  const started = performance.now();
  let next = 0;
  let stopped = false;
  let completedBytes = 0;
  let workerMilliseconds = 0;
  let completedBatches = 0;
  const failures = [];
  const remainingTime = () => estimateAssessmentMilliseconds(completedBytes, workerMilliseconds, bytes - completedBytes, workerCount);
  // Record each request before inference and report success only after its phase-specific result commits.
  async function worker() {
    while (!stopped && next < pending.length) {
      const batchNumber = ++next;
      const job = pending[batchNumber - 1];
      const batchStarted = performance.now();
      let recorded;
      let failureStage = 'request';
      try {
        recorded = job.phase === 'adjudication' ? recordAdjudicationRequest(connection, job.request) : recordEvaluationRequest(connection, job.request);
        if (recorded.inputFingerprint !== job.inputFingerprint) throw new Error('Downstream inputs changed after planning');
        if (connection.isTransaction) throw new Error('Downstream inference refuses an open transaction');
        report({ state: 'running', phase: plan.phase, runId: request.runId, evaluationId: recorded.evaluationId, batchNumber, batchCount: pending.length });
        failureStage = 'evaluate';
        const result = await evaluate(recorded, { phase: job.phase, evaluatorInput });
        failureStage = 'commit';
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
        const failure = describeEvaluationFailure(error, failureStage);
        failures.push(failure);
        if (recorded && connection.get('SELECT outcome FROM evaluations WHERE id = ?', [recorded.evaluationId])?.outcome === 'running') {
          failEvaluation(connection, { binding: request.binding, runId: request.runId, evaluationId: recorded.evaluationId, ...failure });
        }
        report({ state: 'failed', phase: plan.phase, runId: request.runId, batchNumber, batchCount: pending.length,
          batchElapsedMilliseconds: Math.round(performance.now() - batchStarted), totalElapsedMilliseconds: Math.round(performance.now() - started),
          ...failure });
      }
    }
  }
  const settled = await Promise.allSettled(Array.from({ length: workerCount }, () => worker().catch(error => { stopped = true; throw error; })));
  if (failures.length || settled.some(result => result.status === 'rejected')) {
    const failure = failures[0];
    const detail = failure ? `; ${failure.failureStage}: ${failure.failureReason}${failure.failurePath ? ` at ${failure.failurePath}` : ''}` : '';
    throw new Error(`Native ${plan.phase} execution failed; in-flight jobs settled, committed results were retained, and the analysis head was not advanced${detail}`);
  }
  return { evaluationIds, batchCount: plan.jobs.length, evaluatedBatchCount: pending.length,
    recoveredBatchCount: plan.jobs.length - pending.length, totalElapsedMilliseconds: Math.round(performance.now() - started) };
}

// Run downstream phases in order with pinned contracts, then advance analysis only after complete persisted coverage.
export async function executeNativeDownstream(connection, request, evaluatorInputs, evaluate, report = () => {}, maxWorkers = 3, audit = null) {
  const fields = ['binding', 'runId', 'sourceProfileId', 'reconciliationProfileId', 'adjudicationProfileId', 'expectedHeadRunId'];
  requireSourceObject(request, [...fields, 'budgets', 'routingProfileId', 'adjudicationOnly'], fields, 'Native downstream execution');
  if (request.adjudicationOnly !== undefined && typeof request.adjudicationOnly !== 'boolean') throw new Error('Adjudication-only continuation must be explicit');
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
  let reconciledItems = 0;
  for (const phase of ['routing', 'consolidation', 'synthesis', 'adjudication']) {
    if (phase === 'adjudication' && !request.adjudicationOnly) audit?.transition('adjudicate', { runId: request.runId, itemCount: reconciledItems });
    const task = phase === 'adjudication' ? 'adjudication' : 'reconciliation';
    const phaseRequest = { ...request, ...(consolidatedMergeId !== undefined ? { consolidatedMergeId } : {}) };
    const plan = phase === 'adjudication' ? planNativeAdjudication(connection, phaseRequest, evaluatorInputs[task]) :
      planNativeReconciliation(connection, phaseRequest, phase, evaluatorInputs[task]);
    let completed;
    if (request.adjudicationOnly && phase !== 'adjudication') {
      const recovered = plan.jobs.map(job => recoverJob(connection, request, job));
      if (recovered.some(result => !result)) {
        throw new Error('Adjudication-only continuation requires fully committed reconciliation; no prior phase may be dispatched');
      }
      report({ state: 'plan', phase, runId: request.runId, batchCount: 0, recoveredBatchCount: plan.jobs.length,
        workerCount: 0, pendingPayloadBytes: 0, estimatedMilliseconds: 0 });
      completed = { evaluationIds: recovered.map(result => result.id), batchCount: plan.jobs.length,
        evaluatedBatchCount: 0, recoveredBatchCount: plan.jobs.length, totalElapsedMilliseconds: 0 };
    } else completed = await executePhase(connection, request, plan, evaluatorInputs[task], evaluate, report, maxWorkers);
    if (phase === 'consolidation' && plan.jobs.length) consolidatedMergeId = commitConsolidationMerge(connection, request, plan, completed.evaluationIds);
    if (phase === 'synthesis') reconciledItems = plan.jobs.reduce((count, job) => count + job.request.assessmentResultIds.length, 0);
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
