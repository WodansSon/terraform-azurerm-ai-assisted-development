import { requireSourceObject, requireSourceText, requireSourceHash, sourceTextHash } from './WorkbenchSourceRecords.mjs';
import { prepareEvaluationInput, withEvaluationTransaction } from './WorkbenchEvaluations.mjs';
import { readSelectedCapacityConfiguration } from './WorkbenchWorkspace.mjs';

function insert(connection, sql, values) {
  return Number(connection.run(sql, values).lastInsertRowid);
}

function uniqueList(value, label) {
  if (!Array.isArray(value) || new Set(value).size !== value.length) throw new Error(`${label} requires a unique array`);
  return value;
}

export function commitSynthesisResults(connection, request) {
  const fields = ['binding', 'runId', 'evaluationId', 'inputFingerprint', 'result'];
  requireSourceObject(request, fields, fields, 'Synthesis result command');
  readSelectedCapacityConfiguration(connection, request.binding);
  requireSourceHash(request.inputFingerprint, 'Synthesis input fingerprint');
  const resultFields = ['schemaVersion', 'stage', 'phase', 'groups', 'dispositions'];
  requireSourceObject(request.result, resultFields, resultFields, 'Synthesis result');
  if (request.result.schemaVersion !== 4 || request.result.stage !== 'reconciliation' || request.result.phase !== 'synthesis' ||
    !Array.isArray(request.result.groups) || !Array.isArray(request.result.dispositions)) throw new Error('Unsupported synthesis result contract');
  return withEvaluationTransaction(connection, () => {
    const evaluation = connection.get(`SELECT evaluation.*, profile.task_code, run.outcome AS run_outcome FROM evaluations evaluation
      JOIN run_evaluations used ON used.evaluation_id = evaluation.id JOIN evaluator_profiles profile ON profile.id = evaluation.evaluator_profile_id
      JOIN analysis_runs run ON run.id = used.run_id WHERE evaluation.id = ? AND used.run_id = ?`, [request.evaluationId, request.runId]);
    if (!evaluation || evaluation.outcome !== 'running' || evaluation.run_outcome !== 'running' || evaluation.task_code !== 'reconciliation' ||
      evaluation.input_fingerprint !== request.inputFingerprint) throw new Error('Synthesis result does not match its running request identity');
    const inputs = connection.all('SELECT * FROM evaluation_inputs WHERE evaluation_id = ? ORDER BY id', [request.evaluationId]);
    const prepared = prepareEvaluationInput(connection, { binding: request.binding, runId: request.runId, profileId: evaluation.evaluator_profile_id,
      sourceVersionIds: inputs.filter(row => row.role_code === 'source').map(row => row.source_version_id),
      assessmentResultIds: inputs.filter(row => row.role_code === 'assessment-result').map(row => row.assessment_result_id),
      componentIds: inputs.filter(row => row.role_code === 'component').map(row => row.reconciliation_component_id), reconciliationPhase: 'synthesis' });
    if (sourceTextHash(prepared.serializedInput) !== request.inputFingerprint) throw new Error('Synthesis result refuses changed evaluation inputs');
    const input = JSON.parse(prepared.serializedInput);
    const expected = new Set(input.assessments.map(assessment => assessment.assessmentResultId));
    const factors = connection.all('SELECT * FROM scoring_factors WHERE policy_id = ? ORDER BY id', [prepared.context.scoring_policy_id]);
    const provenance = new Set(input.provenanceCodes.map(row => row.code));
    const applicability = new Map(connection.all('SELECT id, code FROM applicability_definitions').map(row => [row.code, row.id]));
    const surfaces = new Map(connection.all('SELECT id, code FROM guidance_surfaces').map(row => [row.code, row.id]));
    const catalogRules = new Map(input.catalogRules.filter(rule => rule.kind === 'managed').map(rule => [rule.ruleVersionId, rule]));
    const covered = new Set();
    const now = new Date().toISOString();
    const groupVersionIds = [];
    for (const group of request.result.groups) {
      const groupFields = ['title', 'semanticSummary', 'synthesisRationale', 'wording', 'selectionFactors', 'selectionRationale', 'reviewState', 'needsReview', 'members', 'operations'];
      requireSourceObject(group, groupFields, groupFields, 'Synthesized group');
      for (const field of ['title', 'semanticSummary', 'synthesisRationale', 'wording', 'selectionRationale']) requireSourceText(group[field], field);
      if (!['recommended', 'excluded', 'deferred'].includes(group.reviewState) || typeof group.needsReview !== 'boolean' ||
        !Array.isArray(group.members) || group.members.length === 0 || !Array.isArray(group.operations) ||
        group.operations.filter(operation => operation.role === 'primary').length !== 1) throw new Error('Synthesized group requires members and exactly one primary recommendation');
      const memberIds = new Set();
      for (const member of group.members) {
        requireSourceObject(member, ['assessmentResultId', 'role', 'coverageRationale'], ['assessmentResultId', 'role', 'coverageRationale'], 'Group member');
        requireSourceText(member.coverageRationale, 'Member coverage rationale');
        if (!expected.has(member.assessmentResultId) || memberIds.has(member.assessmentResultId) || !['primary', 'supporting'].includes(member.role)) {
          throw new Error('Synthesized group contains foreign, repeated, or invalid members');
        }
        memberIds.add(member.assessmentResultId);
        covered.add(member.assessmentResultId);
      }
      const factorCodes = factors.map(factor => factor.code);
      requireSourceObject(group.selectionFactors, factorCodes, factorCodes, 'Synthesized selection factors');
      const cardId = insert(connection, 'INSERT INTO scorecards(policy_id, selection_rationale) VALUES (?, ?)', [prepared.context.scoring_policy_id, group.selectionRationale]);
      for (const factor of factors) connection.run('INSERT INTO scorecard_values VALUES (?, ?, ?)', [cardId, factor.id, group.selectionFactors[factor.code]]);
      const wordingId = insert(connection, 'INSERT INTO wording_versions(text, content_sha256, created_at) VALUES (?, ?, ?)', [group.wording, sourceTextHash(group.wording), now]);
      const groupId = insert(connection, 'INSERT INTO semantic_groups(created_at) VALUES (?)', [now]);
      const groupVersionId = insert(connection, `INSERT INTO group_versions(group_id, revision, synthesis_evaluation_id, suggested_wording_id, scorecard_id,
        title, semantic_summary, synthesis_rationale, review_state, needs_review) VALUES (?, 1, ?, ?, ?, ?, ?, ?, ?, ?)`,
      [groupId, request.evaluationId, wordingId, cardId, group.title, group.semanticSummary, group.synthesisRationale, group.reviewState, Number(group.needsReview)]);
      groupVersionIds.push(groupVersionId);
      for (const member of group.members) connection.run('INSERT INTO group_members VALUES (?, ?, ?, ?)', [groupVersionId, member.assessmentResultId, member.role, member.coverageRationale]);
      for (const [ordinal, operation] of group.operations.entries()) {
        const operationFields = ['role', 'action', 'targetRuleVersionId', 'surfaceCode', 'sectionHeading', 'rationale', 'relationship', 'provenanceCodes', 'evidenceCodes', 'applicabilityCodes'];
        requireSourceObject(operation, operationFields, operationFields, 'Recommended operation');
        requireSourceText(operation.rationale, 'Operation rationale');
        const action = connection.get('SELECT id FROM action_definitions WHERE code = ?', [operation.action]);
        if (!action || !['primary', 'ancillary'].includes(operation.role) || (operation.role === 'ancillary' && operation.action !== 'retire')) {
          throw new Error('Unsupported recommended operation or ancillary action');
        }
        const target = operation.targetRuleVersionId === null ? null : catalogRules.get(operation.targetRuleVersionId);
        if (operation.targetRuleVersionId !== null && !target) throw new Error('Operation target must be a managed rule in the pinned catalog');
        if (target) {
          requireSourceObject(operation.relationship, ['code', 'rationale'], ['code', 'rationale'], 'Recommended catalog relationship');
          requireSourceText(operation.relationship.rationale, 'Catalog relationship rationale');
          if (!['equivalent', 'partial-overlap', 'assessment-extends-hosted', 'assessment-narrows-hosted', 'conflicts'].includes(operation.relationship.code)) {
            throw new Error('Catalog relationship must be an explicit supported semantic claim');
          }
        } else if (operation.relationship !== null) throw new Error('Catalog relationship requires a pinned target rule');
        if ((['update', 'retire', 'restore', 'no-change'].includes(operation.action) && !target) || (operation.action === 'add' && target) ||
          (operation.action === 'restore' && target.lifecycle !== 'retired') || (['update', 'retire'].includes(operation.action) && target.lifecycle !== 'active')) {
          throw new Error('Operation target lifecycle does not match the recommended action');
        }
        const writesWording = ['add', 'update', 'restore'].includes(operation.action);
        const surfaceId = operation.surfaceCode === null ? null : surfaces.get(operation.surfaceCode);
        if (operation.surfaceCode !== null && !surfaceId) throw new Error('Recommendation category is not configured');
        if (writesWording && (!surfaceId || !connection.get('SELECT heading FROM guidance_sections WHERE surface_id = ? AND heading = ?', [surfaceId, operation.sectionHeading]))) {
          throw new Error('Wording recommendation requires a configured category and section');
        }
        if (group.reviewState !== 'recommended' && !['exclude', 'defer'].includes(operation.action)) throw new Error('Excluded or deferred groups cannot recommend catalog mutations');
        const provenanceCodes = uniqueList(operation.provenanceCodes, 'Operation provenance');
        const evidenceCodes = uniqueList(operation.evidenceCodes, 'Operation evidence');
        const applicabilityCodes = uniqueList(operation.applicabilityCodes, 'Operation applicability');
        if (provenanceCodes.some(code => !provenance.has(code)) || applicabilityCodes.some(code => !applicability.has(code)) ||
          (writesWording && provenanceCodes.length === 0)) throw new Error('Recommendation provenance or applicability does not match configured definitions');
        const changeId = insert(connection, `INSERT INTO recommended_changes(group_version_id, ordinal, operation_role, action_id, target_rule_version_id,
          wording_version_id, surface_id, section_heading, rationale) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)`,
        [groupVersionId, ordinal, operation.role, action.id, operation.targetRuleVersionId, writesWording ? wordingId : null, surfaceId, operation.sectionHeading, operation.rationale]);
        for (const [index, code] of provenanceCodes.entries()) connection.run('INSERT INTO recommended_change_provenances VALUES (?, ?, ?)', [changeId, index, code]);
        for (const code of applicabilityCodes) connection.run('INSERT INTO recommended_change_applicabilities VALUES (?, ?)', [changeId, applicability.get(code)]);
        for (const [index, code] of evidenceCodes.entries()) {
          if (prepared.context.base_catalog_id === null || !connection.get('SELECT code FROM catalog_evidence WHERE catalog_id = ? AND code = ?', [prepared.context.base_catalog_id, code])) {
            throw new Error('Recommendation evidence does not belong to the pinned catalog');
          }
          connection.run('INSERT INTO recommended_change_evidence VALUES (?, ?, ?, ?)', [changeId, prepared.context.base_catalog_id, code, index]);
        }
        if (target) connection.run(`INSERT INTO group_catalog_anchors(group_version_id, rule_version_id, relationship_code, rationale)
          VALUES (?, ?, ?, ?)`, [groupVersionId, target.ruleVersionId, operation.relationship.code, operation.relationship.rationale]);
      }
    }
    const disposed = new Set();
    for (const disposition of request.result.dispositions) {
      requireSourceObject(disposition, ['assessmentResultId', 'code', 'rationale'], ['assessmentResultId', 'code', 'rationale'], 'Assessment disposition');
      requireSourceText(disposition.rationale, 'Disposition rationale');
      if (!expected.has(disposition.assessmentResultId) || disposed.has(disposition.assessmentResultId) ||
        !['grouped', 'excluded', 'deferred'].includes(disposition.code) || (disposition.code === 'grouped' && !covered.has(disposition.assessmentResultId))) {
        throw new Error('Synthesis dispositions contain foreign, repeated, or unsupported coverage');
      }
      disposed.add(disposition.assessmentResultId);
      connection.run('INSERT INTO reconciliation_dispositions VALUES (?, ?, ?, ?)', [request.runId, disposition.assessmentResultId, disposition.code, disposition.rationale]);
    }
    if (disposed.size !== expected.size) throw new Error('Synthesis must account for every supplied assessment disposition');
    connection.run("UPDATE evaluations SET outcome = 'complete', completed_at = ? WHERE id = ?", [now, request.evaluationId]);
    return { evaluationId: request.evaluationId, outcome: 'complete', groupVersionIds, dispositionCount: disposed.size };
  });
}
