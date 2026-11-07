import { requireSourceObject } from './WorkbenchSourceRecords.mjs';
import { readAssessmentRecoveryPlan, withEvaluationTransaction } from './WorkbenchEvaluations.mjs';
import { prepareAdjudicationInput } from './WorkbenchAdjudication.mjs';
import { sourceTextHash } from './WorkbenchSourceRecords.mjs';
import { readSelectedCapacityConfiguration } from './WorkbenchWorkspace.mjs';
import { readWorkspaceLlmAssignments } from './WorkbenchLlmAssignments.mjs';

function pairKey(left, right) {
  return [left, right].sort().join('|');
}

export function completeNativeAnalysis(connection, request) {
  const fields = ['binding', 'runId', 'sourceProfileId', 'reconciliationProfileId', 'adjudicationProfileId', 'expectedHeadRunId'];
  requireSourceObject(request, fields, fields, 'Analysis completion');
  if (request.expectedHeadRunId !== null && (!Number.isSafeInteger(request.expectedHeadRunId) || request.expectedHeadRunId < 1)) {
    throw new Error('Analysis completion requires the explicit prior head identity');
  }
  return withEvaluationTransaction(connection, () => {
    const capacity = readSelectedCapacityConfiguration(connection, request.binding);
    const context = connection.get(`SELECT context.*, run.outcome FROM analysis_run_contexts context
      JOIN analysis_runs run ON run.id = context.run_id WHERE context.run_id = ?`, [request.runId]);
    const workspace = connection.get('SELECT team_profile_id, current_protected_snapshot_id FROM workspace_identity WHERE id = 1');
    const catalogId = connection.get('SELECT current_catalog_id FROM workspace_publication WHERE workspace_id = 1')?.current_catalog_id ?? null;
    if (!context || context.outcome !== 'running' || context.team_profile_id !== workspace.team_profile_id ||
      context.protected_snapshot_id !== workspace.current_protected_snapshot_id || context.capacity_policy_id !== capacity.policy.policyId || context.base_catalog_id !== catalogId) {
      throw new Error('Analysis completion refuses changed workspace context');
    }
    const head = connection.get('SELECT run_id FROM workspace_analysis_head WHERE workspace_id = 1')?.run_id ?? null;
    if (head !== request.expectedHeadRunId) throw new Error('Analysis completion refuses a changed current analysis head');
    const assignments = readWorkspaceLlmAssignments(connection, request.binding);
    const pinned = connection.all('SELECT task_code, assignment_id FROM analysis_run_llm_assignments WHERE run_id = ?', [request.runId]);
    if (pinned.length !== assignments.length || assignments.some(assignment => !pinned.some(row => row.task_code === assignment.taskCode && row.assignment_id === assignment.assignmentId))) {
      throw new Error('Analysis completion refuses changed model assignments');
    }
    for (const [task, profileId] of [['assessment', request.sourceProfileId], ['reconciliation', request.reconciliationProfileId], ['adjudication', request.adjudicationProfileId]]) {
      if (!connection.get(`SELECT profile.id FROM evaluator_profiles profile JOIN analysis_run_llm_assignments assigned
        ON assigned.assignment_id = profile.llm_assignment_id AND assigned.task_code = profile.task_code
        WHERE assigned.run_id = ? AND profile.id = ? AND profile.task_code = ?`, [request.runId, profileId, task])) {
        throw new Error('Analysis completion requires its three pinned evaluator profiles');
      }
    }
    const recovery = readAssessmentRecoveryPlan(connection, { binding: request.binding, runId: request.runId, profileId: request.sourceProfileId });
    if (recovery.remainingSourceVersionIds.length || recovery.unfinishedEvaluationIds.length) throw new Error('Analysis completion requires complete source assessment');
    const sourceResults = connection.all(`SELECT result.id FROM assessment_results result JOIN run_evaluations used ON used.evaluation_id = result.evaluation_id
      JOIN evaluations evaluation ON evaluation.id = used.evaluation_id WHERE used.run_id = ? AND evaluation.outcome = 'complete'
      AND evaluation.evaluator_profile_id = ? ORDER BY result.id`, [request.runId, request.sourceProfileId]);
    const dispositions = connection.all('SELECT assessment_result_id, disposition_code FROM reconciliation_dispositions WHERE run_id = ?', [request.runId]);
    if (dispositions.length !== sourceResults.length || sourceResults.some(result => !dispositions.some(row => row.assessment_result_id === result.id))) {
      throw new Error('Analysis completion requires a final disposition for every assessed meaning');
    }
    const stageEvaluations = connection.all(`SELECT evaluation.*, profile.task_code FROM evaluations evaluation JOIN run_evaluations used ON used.evaluation_id = evaluation.id
      JOIN evaluator_profiles profile ON profile.id = evaluation.evaluator_profile_id WHERE used.run_id = ? AND profile.task_code IN ('reconciliation', 'adjudication')`, [request.runId]);
    if (stageEvaluations.some(evaluation => evaluation.outcome === 'running' ||
      evaluation.evaluator_profile_id !== (evaluation.task_code === 'reconciliation' ? request.reconciliationProfileId : request.adjudicationProfileId))) {
      throw new Error('Analysis completion refuses unfinished or mixed downstream evaluator identities');
    }
    const groups = connection.all(`SELECT version.id FROM group_versions version JOIN run_evaluations used ON used.evaluation_id = version.synthesis_evaluation_id
      JOIN evaluations evaluation ON evaluation.id = used.evaluation_id WHERE used.run_id = ? AND evaluation.outcome = 'complete'
      AND evaluation.evaluator_profile_id = ? ORDER BY version.id`, [request.runId, request.reconciliationProfileId]);
    const members = connection.all(`SELECT member.assessment_result_id AS id FROM group_members member JOIN group_versions version ON version.id = member.group_version_id
      JOIN run_evaluations used ON used.evaluation_id = version.synthesis_evaluation_id WHERE used.run_id = ?`, [request.runId]);
    if (dispositions.some(row => row.disposition_code === 'grouped' && !members.some(member => member.id === row.assessment_result_id))) {
      throw new Error('Analysis completion refuses grouped meanings without final membership');
    }
    const rules = catalogId === null ? [] : connection.all(`SELECT version.id FROM catalog_members member JOIN rule_versions version ON version.id = member.rule_version_id
      JOIN rules rule ON rule.id = version.rule_id WHERE member.catalog_id = ? AND rule.rule_kind = 'managed' AND version.lifecycle = 'active'`, [catalogId]);
    const protectedRules = connection.all('SELECT rule_version_id AS id FROM protected_members WHERE snapshot_id = ?', [context.protected_snapshot_id]);
    const expectedPairs = new Set();
    for (const [index, group] of groups.entries()) {
      for (const other of groups.slice(index + 1)) expectedPairs.add(pairKey(`group:${group.id}`, `group:${other.id}`));
      for (const rule of [...rules, ...protectedRules]) expectedPairs.add(pairKey(`group:${group.id}`, `rule:${rule.id}`));
    }
    const coveredPairs = new Set();
    for (const evaluation of stageEvaluations.filter(row => row.task_code === 'adjudication' && row.outcome === 'complete')) {
      const inputs = connection.all('SELECT * FROM evaluation_inputs WHERE evaluation_id = ? ORDER BY id', [evaluation.id]);
      const prepared = prepareAdjudicationInput(connection, { binding: request.binding, runId: request.runId, profileId: request.adjudicationProfileId,
        groupVersionIds: inputs.filter(row => row.role_code === 'group-left').map(row => row.group_version_id),
        rightGroupVersionIds: inputs.filter(row => row.role_code === 'group-right').map(row => row.group_version_id) });
      if (sourceTextHash(prepared.serializedInput) !== evaluation.input_fingerprint) throw new Error('Analysis completion refuses changed adjudication evidence');
      for (const pair of prepared.input.comparisonPairs) {
        const key = pairKey(`${pair.left.kind}:${pair.left.id}`, `${pair.right.kind}:${pair.right.id}`);
        if (!expectedPairs.has(key) || coveredPairs.has(key)) throw new Error('Analysis completion refuses foreign or repeated adjudication coverage');
        coveredPairs.add(key);
      }
      const findings = connection.all('SELECT id FROM findings WHERE evaluation_id = ?', [evaluation.id]);
      if (findings.length !== prepared.input.comparisonPairs.length || findings.some(finding =>
        connection.get('SELECT count(*) AS count FROM finding_participants WHERE finding_id = ?', [finding.id]).count !== 2)) {
        throw new Error('Analysis completion requires persisted comparison participants');
      }
    }
    if (coveredPairs.size !== expectedPairs.size) throw new Error('Analysis completion requires every final group and baseline comparison');
    connection.run("UPDATE analysis_runs SET outcome = 'complete', completed_at = ? WHERE id = ? AND outcome = 'running'", [new Date().toISOString(), request.runId]);
    connection.run('INSERT INTO workspace_analysis_head(workspace_id, run_id) VALUES (1, ?) ON CONFLICT(workspace_id) DO UPDATE SET run_id = excluded.run_id', [request.runId]);
    return { runId: request.runId, outcome: 'complete', sourceCount: recovery.completedSourceCount, assessmentCount: sourceResults.length,
      groupCount: groups.length, comparisonCount: coveredPairs.size, readyForUi: false };
  });
}
