import { sourceTextHash } from './WorkbenchSourceRecords.mjs';
import { withEvaluationTransaction, prepareEvaluationInput } from './WorkbenchEvaluations.mjs';
import { readSelectedCapacityConfiguration } from './WorkbenchWorkspace.mjs';
import { mergeConsolidationShards } from './WorkbenchSharding.mjs';

// Rehydrate canonical component membership only when every contributing shard belongs to the pinned completed lineage.
export function readConsolidatedComponents(connection, runId, profileId, mergeId) {
  const merge = connection.get('SELECT * FROM consolidation_merges WHERE id = ? AND run_id = ? AND evaluator_profile_id = ?', [mergeId, runId, profileId]);
  if (!merge) throw new Error('Synthesis requires its pinned canonical consolidation merge');
  const lineage = connection.all(`SELECT evaluation.* FROM consolidation_merge_evaluations member JOIN evaluations evaluation ON evaluation.id = member.evaluation_id
    JOIN run_evaluations used ON used.evaluation_id = evaluation.id WHERE member.merge_id = ? AND used.run_id = ? ORDER BY member.ordinal`, [mergeId, runId]);
  if (!lineage.length || lineage.some(evaluation => evaluation.outcome !== 'complete' || evaluation.evaluator_profile_id !== profileId)) {
    throw new Error('Canonical consolidation requires completed pinned shard lineage');
  }
  return connection.all('SELECT * FROM consolidated_components WHERE merge_id = ? ORDER BY ordinal', [mergeId]).map(component => ({
    componentId: component.id, mergeId, phase: 'consolidation', semanticSummary: component.semantic_summary,
    assessmentResultIds: connection.all('SELECT assessment_result_id AS id FROM consolidated_component_members WHERE component_id = ? ORDER BY assessment_result_id', [component.id]).map(row => row.id),
    ruleVersionIds: connection.all('SELECT rule_version_id AS id FROM consolidated_component_rules WHERE component_id = ? ORDER BY rule_version_id', [component.id]).map(row => row.id),
  }));
}

// Verify every planned shard and persist their deterministic union, reusing an existing merge only if membership matches.
export function commitConsolidationMerge(connection, request, plan, evaluationIds) {
  return withEvaluationTransaction(connection, () => {
    readSelectedCapacityConfiguration(connection, request.binding);
    if (evaluationIds.length !== plan.jobs.length || new Set(evaluationIds).size !== evaluationIds.length) throw new Error('Consolidation merge requires distinct results for every planned shard');
    const results = plan.jobs.map((job, index) => {
      const evaluation = connection.get(`SELECT evaluation.* FROM evaluations evaluation JOIN run_evaluations used ON used.evaluation_id = evaluation.id
        WHERE evaluation.id = ? AND used.run_id = ?`, [evaluationIds[index], request.runId]);
      if (!evaluation || evaluation.outcome !== 'complete' || evaluation.evaluator_profile_id !== request.reconciliationProfileId || evaluation.input_fingerprint !== job.inputFingerprint ||
        sourceTextHash(prepareEvaluationInput(connection, job.request).serializedInput) !== job.inputFingerprint) {
        throw new Error('Consolidation merge refuses unfinished, changed, or foreign shard evidence');
      }
      const recorded = connection.all("SELECT reconciliation_component_id AS id FROM evaluation_inputs WHERE evaluation_id = ? AND role_code = 'component' ORDER BY id", [evaluation.id]).map(row => row.id);
      if (JSON.stringify(recorded) !== JSON.stringify(job.request.componentIds)) throw new Error('Consolidation merge refuses changed recorded component scope');
      const components = connection.all("SELECT id FROM reconciliation_components WHERE evaluation_id = ? AND phase_code = 'consolidation' ORDER BY ordinal", [evaluation.id]).map(component => ({
        assessmentResultIds: connection.all('SELECT assessment_result_id AS id FROM reconciliation_component_members WHERE component_id = ? ORDER BY assessment_result_id', [component.id]).map(row => row.id),
        ruleVersionIds: connection.all('SELECT rule_version_id AS id FROM reconciliation_component_rules WHERE component_id = ? ORDER BY rule_version_id', [component.id]).map(row => row.id),
      }));
      return { componentIds: job.request.componentIds, components };
    });
    const merged = mergeConsolidationShards(plan.routingComponents, plan.jobs.map(job => ({ componentIds: job.request.componentIds })), results);
    const planHash = sourceTextHash(JSON.stringify({ budgets: plan.budgets, inputs: plan.jobs.map(job => job.inputFingerprint), components: plan.routingComponents }));
    const existing = connection.get('SELECT id FROM consolidation_merges WHERE run_id = ? AND evaluator_profile_id = ? AND plan_sha256 = ?', [request.runId, request.reconciliationProfileId, planHash]);
    if (existing) {
      const recorded = readConsolidatedComponents(connection, request.runId, request.reconciliationProfileId, existing.id);
      if (JSON.stringify(recorded.map(({ assessmentResultIds, ruleVersionIds }) => ({ assessmentResultIds, ruleVersionIds }))) !==
        JSON.stringify(merged.map(({ assessmentResultIds, ruleVersionIds }) => ({ assessmentResultIds, ruleVersionIds })))) {
        throw new Error('Canonical consolidation recovery refuses changed merged membership');
      }
      return existing.id;
    }
    const mergeId = Number(connection.run('INSERT INTO consolidation_merges(run_id,evaluator_profile_id,plan_sha256,created_at) VALUES (?,?,?,?)',
      [request.runId, request.reconciliationProfileId, planHash, new Date().toISOString()]).lastInsertRowid);
    for (const [ordinal, evaluationId] of evaluationIds.entries()) connection.run('INSERT INTO consolidation_merge_evaluations VALUES (?,?,?)', [mergeId, evaluationId, ordinal]);
    for (const [ordinal, component] of merged.entries()) {
      const componentId = Number(connection.run('INSERT INTO consolidated_components(merge_id,ordinal,semantic_summary) VALUES (?,?,?)', [mergeId, ordinal, component.semanticSummary]).lastInsertRowid);
      for (const id of component.assessmentResultIds) connection.run('INSERT INTO consolidated_component_members VALUES (?,?)', [componentId, id]);
      for (const id of component.ruleVersionIds) connection.run('INSERT INTO consolidated_component_rules VALUES (?,?)', [componentId, id]);
    }
    return mergeId;
  });
}
