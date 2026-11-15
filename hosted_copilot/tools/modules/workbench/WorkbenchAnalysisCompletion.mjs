import { requireSourceObject } from './WorkbenchSourceRecords.mjs';
import { readAssessmentRecoveryPlan, withEvaluationTransaction, prepareEvaluationInput, readRecordedReconciliationRequest } from './WorkbenchEvaluations.mjs';
import { prepareAdjudicationInput, readRecordedAdjudicationRequest, readAdjudicationResult } from './WorkbenchAdjudication.mjs';
import { sourceTextHash } from './WorkbenchSourceRecords.mjs';
import { readSelectedCapacityConfiguration, readWorkingCatalogId } from './WorkbenchWorkspace.mjs';
import { readWorkspaceLlmAssignments } from './WorkbenchLlmAssignments.mjs';
import { readConsolidatedComponents } from './WorkbenchConsolidation.mjs';
import { readAdjudicationComponents, validateAdjudicationResult } from './WorkbenchRelationshipComponents.mjs';

// Verify exact persisted coverage and unchanged authorities before atomically completing the run and advancing its analysis head.
export function completeNativeAnalysis(connection, request) {
  const fields = ['binding', 'runId', 'sourceProfileId', 'reconciliationProfileId', 'adjudicationProfileId', 'expectedHeadRunId'];
  requireSourceObject(request, [...fields, 'routingProfileId', 'consolidatedMergeId'], fields, 'Analysis completion');
  if (request.expectedHeadRunId !== null && (!Number.isSafeInteger(request.expectedHeadRunId) || request.expectedHeadRunId < 1)) {
    throw new Error('Analysis completion requires the explicit prior head identity');
  }
  return withEvaluationTransaction(connection, () => {
    const capacity = readSelectedCapacityConfiguration(connection, request.binding);
    const context = connection.get(`SELECT context.*, run.outcome FROM analysis_run_contexts context
      JOIN analysis_runs run ON run.id = context.run_id WHERE context.run_id = ?`, [request.runId]);
    const workspace = connection.get('SELECT team_profile_id, current_protected_snapshot_id FROM workspace_identity WHERE id = 1');
    const catalogId = readWorkingCatalogId(connection);
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
    const sourceResults = connection.all(`SELECT result.id, result.hosted_applicable FROM assessment_results result JOIN run_evaluations used ON used.evaluation_id = result.evaluation_id
      JOIN evaluations evaluation ON evaluation.id = used.evaluation_id WHERE used.run_id = ? AND evaluation.outcome = 'complete'
      AND evaluation.evaluator_profile_id = ? ORDER BY result.id`, [request.runId, request.sourceProfileId]);
    const dispositions = connection.all('SELECT assessment_result_id, disposition_code FROM reconciliation_dispositions WHERE run_id = ?', [request.runId]);
    if (dispositions.length !== sourceResults.length || sourceResults.some(result => !dispositions.some(row => row.assessment_result_id === result.id))) {
      throw new Error('Analysis completion requires a final disposition for every assessed meaning');
    }
    const eligible = sourceResults.filter(result => result.hosted_applicable);
    const components = request.consolidatedMergeId !== undefined
      ? readConsolidatedComponents(connection, request.runId, request.reconciliationProfileId, request.consolidatedMergeId)
      : connection.all(`SELECT component.id FROM reconciliation_components component JOIN evaluations evaluation ON evaluation.id = component.evaluation_id
        JOIN run_evaluations used ON used.evaluation_id = evaluation.id WHERE used.run_id = ? AND evaluation.evaluator_profile_id = ?
        AND evaluation.outcome = 'complete' AND component.phase_code = 'consolidation' ORDER BY component.id`,
      [request.runId, request.reconciliationProfileId]).map(component => ({
        assessmentResultIds: connection.all('SELECT assessment_result_id AS id FROM reconciliation_component_members WHERE component_id = ? ORDER BY assessment_result_id', [component.id]).map(row => row.id),
        ruleVersionIds: connection.all('SELECT rule_version_id AS id FROM reconciliation_component_rules WHERE component_id = ? ORDER BY rule_version_id', [component.id]).map(row => row.id),
      }));
    const consolidatedAssessments = components.flatMap(component => component.assessmentResultIds);
    const consolidatedRules = components.flatMap(component => component.ruleVersionIds);
    const expectedRules = connection.all(`SELECT rule_version_id AS id FROM catalog_members WHERE catalog_id = ?
      UNION SELECT rule_version_id AS id FROM protected_members WHERE snapshot_id = ? ORDER BY id`,
    [context.base_catalog_id, context.protected_snapshot_id]).map(row => row.id);
    if (consolidatedAssessments.length !== eligible.length || new Set(consolidatedAssessments).size !== consolidatedAssessments.length ||
      eligible.some(result => !consolidatedAssessments.includes(result.id)) ||
      consolidatedRules.length !== expectedRules.length || new Set(consolidatedRules).size !== consolidatedRules.length ||
      expectedRules.some(id => !consolidatedRules.includes(id))) {
      throw new Error('Analysis completion requires complete typed canonical consolidation membership');
    }
    const stageEvaluations = connection.all(`SELECT evaluation.*, profile.task_code FROM evaluations evaluation JOIN run_evaluations used ON used.evaluation_id = evaluation.id
      JOIN evaluator_profiles profile ON profile.id = evaluation.evaluator_profile_id WHERE used.run_id = ? AND profile.task_code IN ('reconciliation', 'adjudication')`, [request.runId]);
    if (stageEvaluations.some(evaluation => evaluation.outcome === 'running' ||
      (evaluation.outcome === 'complete' && evaluation.evaluator_profile_id !== (evaluation.task_code === 'reconciliation' ? request.reconciliationProfileId : request.adjudicationProfileId) &&
        !(evaluation.task_code === 'reconciliation' && evaluation.evaluator_profile_id === request.routingProfileId &&
          connection.all('SELECT role_code FROM evaluation_inputs WHERE evaluation_id = ?', [evaluation.id]).every(input => ['source', 'source-metadata', 'assessment-result'].includes(input.role_code)) &&
          connection.all('SELECT phase_code FROM reconciliation_components WHERE evaluation_id = ?', [evaluation.id]).every(component => component.phase_code === 'routing'))))) {
      throw new Error('Analysis completion refuses unfinished or mixed downstream evaluator identities');
    }
    const groups = connection.all(`SELECT version.id FROM group_versions version JOIN run_evaluations used ON used.evaluation_id = version.synthesis_evaluation_id
      JOIN evaluations evaluation ON evaluation.id = used.evaluation_id WHERE used.run_id = ? AND evaluation.outcome = 'complete'
      AND evaluation.evaluator_profile_id = ? ORDER BY version.id`, [request.runId, request.reconciliationProfileId]);
    const members = connection.all(`SELECT member.assessment_result_id AS id, version.review_state AS reviewState FROM group_members member JOIN group_versions version ON version.id = member.group_version_id
      JOIN run_evaluations used ON used.evaluation_id = version.synthesis_evaluation_id WHERE used.run_id = ?`, [request.runId]);
    if (new Set(members.map(member => member.id)).size !== members.length ||
      members.some(member => !dispositions.some(row => row.assessment_result_id === member.id &&
        row.disposition_code === (member.reviewState === 'recommended' ? 'grouped' : member.reviewState)))) {
      throw new Error('Analysis completion requires unique final ownership and matching member dispositions');
    }
    if (dispositions.some(row => row.disposition_code === 'grouped' && !members.some(member => member.id === row.assessment_result_id))) {
      throw new Error('Analysis completion refuses grouped meanings without final membership');
    }
    for (const evaluation of stageEvaluations.filter(row => row.task_code === 'reconciliation' && row.outcome === 'complete')) {
      const phase = connection.get('SELECT phase_code FROM reconciliation_components WHERE evaluation_id = ? ORDER BY id LIMIT 1', [evaluation.id])?.phase_code ?? 'synthesis';
      const prepared = prepareEvaluationInput(connection, readRecordedReconciliationRequest(connection, request.binding, request.runId, evaluation.id, phase));
      if (sourceTextHash(prepared.serializedInput) !== evaluation.input_fingerprint) {
        throw new Error('Analysis completion refuses changed reconciliation evidence');
      }
    }
    const relationshipComponents = readAdjudicationComponents(connection, request.runId);
    const expectedComponents = new Set(relationshipComponents.map(component => component.componentId));
    const coveredComponents = new Set();
    let comparisonCount = 0;
    const adjudicationParents = new Map();
    for (const evaluation of stageEvaluations.filter(row => row.task_code === 'adjudication' && row.outcome === 'complete')) {
      const prepared = prepareAdjudicationInput(connection, readRecordedAdjudicationRequest(connection, {
        binding: request.binding, runId: request.runId, profileId: request.adjudicationProfileId, evaluationId: evaluation.id }), adjudicationParents);
      if (sourceTextHash(prepared.serializedInput) !== evaluation.input_fingerprint) throw new Error('Analysis completion refuses changed adjudication evidence');
      for (const component of prepared.input.components) {
        if (!expectedComponents.has(component.componentId) || coveredComponents.has(component.componentId)) {
          throw new Error('Analysis completion refuses foreign or repeated component coverage');
        }
        coveredComponents.add(component.componentId);
      }
      const persisted = readAdjudicationResult(connection, evaluation.id);
      const validated = validateAdjudicationResult(prepared.input, persisted);
      if (connection.get('SELECT count(*) AS count FROM findings WHERE evaluation_id = ?', [evaluation.id]).count !== validated.decisions.size) {
        throw new Error('Analysis completion requires exact persisted relationship findings');
      }
      comparisonCount += validated.decisions.size;
    }
    if (coveredComponents.size !== expectedComponents.size) throw new Error('Analysis completion requires every recorded relationship component');
    connection.run("UPDATE analysis_runs SET outcome = 'complete', completed_at = ? WHERE id = ? AND outcome = 'running'", [new Date().toISOString(), request.runId]);
    connection.run('INSERT INTO workspace_analysis_head(workspace_id, run_id) VALUES (1, ?) ON CONFLICT(workspace_id) DO UPDATE SET run_id = excluded.run_id', [request.runId]);
    return { runId: request.runId, outcome: 'complete', sourceCount: recovery.completedSourceCount, assessmentCount: sourceResults.length,
      groupCount: groups.length, comparisonCount, readyForUi: false };
  });
}
