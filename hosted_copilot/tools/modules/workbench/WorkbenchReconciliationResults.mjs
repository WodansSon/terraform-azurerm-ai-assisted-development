import { requireSourceObject, requireSourceText, requireSourceHash, sourceTextHash } from './WorkbenchSourceRecords.mjs';
import { prepareEvaluationInput, withEvaluationTransaction, readRecordedReconciliationRequest } from './WorkbenchEvaluations.mjs';
import { readSelectedCapacityConfiguration } from './WorkbenchWorkspace.mjs';
import { validateGroupContinuities } from './WorkbenchGroupContinuity.mjs';
import { evaluationResultError } from './WorkbenchEvaluationFailures.mjs';

function insert(connection, sql, values) {
  return Number(connection.run(sql, values).lastInsertRowid);
}

function uniqueList(value, label) {
  if (!Array.isArray(value) || new Set(value).size !== value.length) throw evaluationResultError(`${label} requires a unique array`);
  return value;
}

// Atomically persist complete synthesized groups, continuity, quoted relationships, recommendations, and final member dispositions.
export function commitSynthesisResults(connection, request) {
  const fields = ['binding', 'runId', 'evaluationId', 'inputFingerprint', 'result'];
  requireSourceObject(request, fields, fields, 'Synthesis result command');
  readSelectedCapacityConfiguration(connection, request.binding);
  requireSourceHash(request.inputFingerprint, 'Synthesis input fingerprint');
  const resultFields = ['schemaVersion', 'stage', 'phase', 'groups', 'dispositions'];
  requireSourceObject(request.result, resultFields, resultFields, 'Synthesis result');
  if (request.result.schemaVersion !== 4 || request.result.stage !== 'reconciliation' || request.result.phase !== 'synthesis' ||
    !Array.isArray(request.result.groups) || !Array.isArray(request.result.dispositions)) throw evaluationResultError('Unsupported synthesis result contract');
  return withEvaluationTransaction(connection, () => {
    const evaluation = connection.get(`SELECT evaluation.*, profile.task_code, run.outcome AS run_outcome FROM evaluations evaluation
      JOIN run_evaluations used ON used.evaluation_id = evaluation.id JOIN evaluator_profiles profile ON profile.id = evaluation.evaluator_profile_id
      JOIN analysis_runs run ON run.id = used.run_id WHERE evaluation.id = ? AND used.run_id = ?`, [request.evaluationId, request.runId]);
    if (!evaluation || evaluation.outcome !== 'running' || evaluation.run_outcome !== 'running' || evaluation.task_code !== 'reconciliation' ||
      evaluation.input_fingerprint !== request.inputFingerprint) throw evaluationResultError('Synthesis result does not match its running request identity');
    const inputs = connection.all('SELECT * FROM evaluation_inputs WHERE evaluation_id = ? ORDER BY id', [request.evaluationId]);
    const prepared = prepareEvaluationInput(connection, readRecordedReconciliationRequest(connection, request.binding, request.runId, request.evaluationId, 'synthesis'));
    if (sourceTextHash(prepared.serializedInput) !== request.inputFingerprint) throw evaluationResultError('Synthesis result refuses changed evaluation inputs');
    const input = JSON.parse(prepared.serializedInput);
    const expected = new Set(input.assessments.map(assessment => assessment.assessmentResultId));
    const factors = connection.all('SELECT * FROM scoring_factors WHERE policy_id = ? ORDER BY id', [prepared.context.scoring_policy_id]);
    const provenance = new Set(input.provenanceCodes.map(row => row.code));
    const applicability = new Map(connection.all('SELECT id, code FROM applicability_definitions').map(row => [row.code, row.id]));
    const surfaces = new Map(connection.all('SELECT id, code FROM guidance_surfaces').map(row => [row.code, row.id]));
    const catalogRules = new Map(input.catalogRules.filter(rule => rule.kind === 'managed').map(rule => [rule.ruleVersionId, rule]));
    const relatedRules = new Map([...catalogRules.values(), ...input.protectedRules].map(rule => [rule.ruleVersionId, rule]));
    const assessments = new Map(input.assessments.map(assessment => [assessment.assessmentResultId, {
      ...assessment, sourceMeaning: assessment.sourceMeaning ?? input.sources.find(source => source.sourceVersionId === assessment.sourceMeaningSourceVersionId)?.content,
    }]));
    const continuityPlans = validateGroupContinuities(connection, input, request.result.groups, request.runId);
    const proposedOwners = new Map();
    for (const group of request.result.groups) {
      for (const member of group.members ?? []) {
        if (proposedOwners.has(member.assessmentResultId)) throw evaluationResultError('Synthesized groups require unique final assessment ownership');
        proposedOwners.set(member.assessmentResultId, group);
      }
    }
    const covered = new Set();
    const memberDispositions = new Map();
    const now = new Date().toISOString();
    const groupVersionIds = [];
    for (const [groupIndex, group] of request.result.groups.entries()) {
      const groupFields = ['title', 'semanticSummary', 'synthesisRationale', 'wording', 'selectionFactors', 'selectionRationale', 'reviewState', 'needsReview', 'members', 'operations', 'continuity', 'relatedCoverage'];
      requireSourceObject(group, groupFields, groupFields, 'Synthesized group');
      for (const field of ['title', 'semanticSummary', 'synthesisRationale', 'wording', 'selectionRationale']) requireSourceText(group[field], field);
      if (!['recommended', 'excluded', 'deferred'].includes(group.reviewState) || typeof group.needsReview !== 'boolean' ||
        !Array.isArray(group.members) || group.members.length === 0 || !Array.isArray(group.operations) ||
        group.operations.filter(operation => operation.role === 'primary').length !== 1) throw evaluationResultError('Synthesized group requires members and exactly one primary recommendation');
      const memberIds = new Set();
      for (const member of group.members) {
        requireSourceObject(member, ['assessmentResultId', 'role', 'coverageRationale'], ['assessmentResultId', 'role', 'coverageRationale'], 'Group member');
        requireSourceText(member.coverageRationale, 'Member coverage rationale');
        if (!expected.has(member.assessmentResultId) || covered.has(member.assessmentResultId) ||
          !assessments.get(member.assessmentResultId).hostedApplicable || !['primary', 'supporting'].includes(member.role)) {
          throw evaluationResultError('Synthesized group contains foreign, repeated, or invalid members');
        }
        memberIds.add(member.assessmentResultId);
        covered.add(member.assessmentResultId);
        memberDispositions.set(member.assessmentResultId, group.reviewState === 'recommended' ? 'grouped' : group.reviewState);
      }
      const canonicalOwners = new Set(input.canonicalBindings.filter(binding => memberIds.has(binding.assessmentResultId)).map(binding => binding.ruleVersionId));
      if (canonicalOwners.size > 1) throw evaluationResultError('Synthesized group cannot combine assessments owned by different canonical rules');
      const factorCodes = factors.map(factor => factor.code);
      requireSourceObject(group.selectionFactors, factorCodes, factorCodes, 'Synthesized selection factors');
      const cardId = insert(connection, 'INSERT INTO scorecards(policy_id, selection_rationale) VALUES (?, ?)', [prepared.context.scoring_policy_id, group.selectionRationale]);
      for (const factor of factors) connection.run('INSERT INTO scorecard_values VALUES (?, ?, ?)', [cardId, factor.id, group.selectionFactors[factor.code]]);
      const wordingId = insert(connection, 'INSERT INTO wording_versions(text, content_sha256, created_at) VALUES (?, ?, ?)', [group.wording, sourceTextHash(group.wording), now]);
      const plan = continuityPlans[groupIndex];
      const groupId = plan.continuity.kind === 'unresolved' ? null :
        plan.groupId ?? insert(connection, 'INSERT INTO semantic_groups(created_at) VALUES (?)', [now]);
      const revision = groupId === null ? 1 : connection.get('SELECT coalesce(max(revision), 0) + 1 AS revision FROM group_versions WHERE group_id = ?', [groupId]).revision;
      const groupVersionId = insert(connection, `INSERT INTO group_versions(group_id, revision, synthesis_evaluation_id, suggested_wording_id, scorecard_id,
        title, semantic_summary, synthesis_rationale, review_state, needs_review, continuity_kind, continuity_confidence, continuity_rationale)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
      [groupId, revision, request.evaluationId, wordingId, cardId, group.title, group.semanticSummary, group.synthesisRationale, group.reviewState,
        Number(group.needsReview), plan.continuity.kind, plan.continuity.confidence, plan.continuity.rationale]);
      groupVersionIds.push(groupVersionId);
      for (const member of group.members) connection.run('INSERT INTO group_members VALUES (?, ?, ?, ?)', [groupVersionId, member.assessmentResultId, member.role, member.coverageRationale]);
      if (!Array.isArray(group.relatedCoverage)) throw evaluationResultError('Synthesized group requires explicit related coverage', `/groups/${groupIndex}/relatedCoverage`);
      const relatedTargets = new Set();
      for (const [relationIndex, relation] of group.relatedCoverage.entries()) {
        const path = `/groups/${groupIndex}/relatedCoverage/${relationIndex}`;
        const relationFields = ['target', 'relationship', 'rationale', 'evidence'];
        requireSourceObject(relation, relationFields, relationFields, 'Provisional related coverage');
        requireSourceObject(relation.target, ['kind', 'id'], ['kind', 'id'], 'Related coverage target');
        const key = `${relation.target.kind}:${relation.target.id}`;
        const target = relation.target.kind === 'assessment' ? assessments.get(relation.target.id) :
          relation.target.kind === 'rule' ? relatedRules.get(relation.target.id) : null;
        if (!Number.isSafeInteger(relation.target.id) || !target || relatedTargets.has(key) ||
          (relation.target.kind === 'assessment' && (!proposedOwners.has(relation.target.id) || proposedOwners.get(relation.target.id) === group)) ||
          !['equivalent', 'partial-overlap', 'left-extends-right', 'left-narrows-right', 'conflicts'].includes(relation.relationship)) {
          throw evaluationResultError('Related coverage requires distinct supplied targets outside its final group and a supported relationship', path);
        }
        requireSourceText(relation.rationale, 'Related coverage rationale');
        if (!Array.isArray(relation.evidence) || !relation.evidence.length) {
          throw evaluationResultError('Related coverage requires nonempty member evidence', `${path}/evidence`);
        }
        relatedTargets.add(key);
        const relationshipId = insert(connection, `INSERT INTO group_relationships(group_version_id, target_assessment_id, target_rule_version_id,
          relationship_code, rationale, evidence_origin) VALUES (?, ?, ?, ?, ?, 'reconciliation')`,
        [groupVersionId, relation.target.kind === 'assessment' ? relation.target.id : null,
          relation.target.kind === 'rule' ? relation.target.id : null, relation.relationship, relation.rationale]);
        const evidenceMembers = new Set();
        for (const [ordinal, evidence] of relation.evidence.entries()) {
          const evidencePath = `${path}/evidence/${ordinal}`;
          const evidenceFields = ['assessmentResultId', 'sourceQuote', 'targetQuote'];
          requireSourceObject(evidence, evidenceFields, evidenceFields, 'Related coverage member evidence');
          if (!memberIds.has(evidence.assessmentResultId) || evidenceMembers.has(evidence.assessmentResultId)) {
            throw evaluationResultError('Related coverage requires distinct evidence members owned by its group', evidencePath);
          }
          for (const [field, text] of [['sourceQuote', assessments.get(evidence.assessmentResultId).sourceMeaning],
            ['targetQuote', relation.target.kind === 'assessment' ? target.sourceMeaning : target.text]]) {
            const quote = evidence[field];
            if (typeof quote !== 'string' || !quote.trim().length || quote.length > 2000 || !quote.isWellFormed() ||
              quote.includes('\0') || typeof text !== 'string' || !text.includes(quote)) {
              throw evaluationResultError('Related coverage quotes must occur in exact supplied meanings or rule text', `${evidencePath}/${field}`);
            }
          }
          evidenceMembers.add(evidence.assessmentResultId);
          connection.run('INSERT INTO group_relationship_evidence VALUES (?, ?, ?, ?, ?)',
            [relationshipId, ordinal, evidence.assessmentResultId, evidence.sourceQuote, evidence.targetQuote]);
        }
      }
      for (const prior of plan.priors) {
        const correspondenceId = insert(connection, `INSERT INTO group_correspondences(prior_group_version_id, next_group_version_id,
          correspondence_kind, rationale, evaluation_id, recorded_at, confidence_level) VALUES (?, ?, ?, ?, ?, ?, ?)`,
        [prior.groupVersionId, groupVersionId, plan.continuity.kind, plan.continuity.rationale, request.evaluationId, now, plan.continuity.confidence]);
        for (const match of plan.continuity.memberMatches.filter(match => prior.members.some(member => member.assessmentResultId === match.priorAssessmentResultId))) {
          connection.run('INSERT INTO group_correspondence_members VALUES (?, ?, ?, ?, ?, ?)',
            [correspondenceId, match.assessmentResultId, match.priorAssessmentResultId, match.currentQuote, match.priorQuote, match.rationale]);
        }
      }
      for (const [ordinal, operation] of group.operations.entries()) {
        const operationFields = ['role', 'action', 'targetRuleVersionId', 'surfaceCode', 'sectionHeading', 'rationale', 'relationship', 'provenanceCodes', 'evidenceCodes', 'applicabilityCodes'];
        requireSourceObject(operation, operationFields, operationFields, 'Recommended operation');
        requireSourceText(operation.rationale, 'Operation rationale');
        const action = connection.get('SELECT id FROM action_definitions WHERE code = ?', [operation.action]);
        if (!action || !['primary', 'ancillary'].includes(operation.role) || (operation.role === 'ancillary' && operation.action !== 'retire')) {
          throw evaluationResultError('Unsupported recommended operation or ancillary action');
        }
        const target = operation.targetRuleVersionId === null ? null : catalogRules.get(operation.targetRuleVersionId);
        if (operation.targetRuleVersionId !== null && !target) throw evaluationResultError('Operation target must be a managed rule in the pinned catalog');
        if (target) {
          requireSourceObject(operation.relationship, ['code', 'rationale'], ['code', 'rationale'], 'Recommended catalog relationship');
          requireSourceText(operation.relationship.rationale, 'Catalog relationship rationale');
          if (!['equivalent', 'partial-overlap', 'assessment-extends-hosted', 'assessment-narrows-hosted', 'conflicts'].includes(operation.relationship.code)) {
            throw evaluationResultError('Catalog relationship must be an explicit supported semantic claim');
          }
        } else if (operation.relationship !== null) throw evaluationResultError('Catalog relationship requires a pinned target rule');
        if ((['update', 'retire', 'restore', 'no-change'].includes(operation.action) && !target) || (operation.action === 'add' && target) ||
          (operation.action === 'restore' && target.lifecycle !== 'retired') || (['update', 'retire'].includes(operation.action) && target.lifecycle !== 'active')) {
          throw evaluationResultError('Operation target lifecycle does not match the recommended action');
        }
        const writesWording = ['add', 'update', 'restore'].includes(operation.action);
        const surfaceId = operation.surfaceCode === null ? null : surfaces.get(operation.surfaceCode);
        if (operation.surfaceCode !== null && !surfaceId) throw evaluationResultError('Recommendation category is not configured');
        if (writesWording && (!surfaceId || !connection.get('SELECT heading FROM guidance_sections WHERE surface_id = ? AND heading = ?', [surfaceId, operation.sectionHeading]))) {
          throw evaluationResultError('Wording recommendation requires a configured category and section');
        }
        if (group.reviewState !== 'recommended' && !['exclude', 'defer'].includes(operation.action)) throw evaluationResultError('Excluded or deferred groups cannot recommend catalog mutations');
        const provenanceCodes = uniqueList(operation.provenanceCodes, 'Operation provenance');
        const evidenceCodes = uniqueList(operation.evidenceCodes, 'Operation evidence');
        const applicabilityCodes = uniqueList(operation.applicabilityCodes, 'Operation applicability');
        if (provenanceCodes.some(code => !provenance.has(code)) || applicabilityCodes.some(code => !applicability.has(code)) ||
          (writesWording && provenanceCodes.length === 0)) throw evaluationResultError('Recommendation provenance or applicability does not match configured definitions');
        const changeId = insert(connection, `INSERT INTO recommended_changes(group_version_id, ordinal, operation_role, action_id, target_rule_version_id,
          wording_version_id, surface_id, section_heading, rationale) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)`,
        [groupVersionId, ordinal, operation.role, action.id, operation.targetRuleVersionId, writesWording ? wordingId : null, surfaceId, operation.sectionHeading, operation.rationale]);
        for (const [index, code] of provenanceCodes.entries()) connection.run('INSERT INTO recommended_change_provenances VALUES (?, ?, ?)', [changeId, index, code]);
        for (const code of applicabilityCodes) connection.run('INSERT INTO recommended_change_applicabilities VALUES (?, ?)', [changeId, applicability.get(code)]);
        for (const [index, code] of evidenceCodes.entries()) {
          if (prepared.context.base_catalog_id === null || !connection.get('SELECT code FROM catalog_evidence WHERE catalog_id = ? AND code = ?', [prepared.context.base_catalog_id, code])) {
            throw evaluationResultError('Recommendation evidence does not belong to the pinned catalog');
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
        !['grouped', 'excluded', 'deferred'].includes(disposition.code) ||
        (!assessments.get(disposition.assessmentResultId).hostedApplicable && disposition.code !== 'excluded') ||
        (disposition.code === 'grouped' && !covered.has(disposition.assessmentResultId))) {
        throw evaluationResultError('Synthesis dispositions contain foreign, repeated, or unsupported coverage');
      }
      if (covered.has(disposition.assessmentResultId) && memberDispositions.get(disposition.assessmentResultId) !== disposition.code) {
        throw evaluationResultError('Assessment disposition must agree with its final group review state');
      }
      disposed.add(disposition.assessmentResultId);
      connection.run('INSERT INTO reconciliation_dispositions VALUES (?, ?, ?, ?)', [request.runId, disposition.assessmentResultId, disposition.code, disposition.rationale]);
    }
    if (disposed.size !== expected.size) throw evaluationResultError('Synthesis must account for every supplied assessment disposition');
    connection.run("UPDATE evaluations SET outcome = 'complete', completed_at = ? WHERE id = ?", [now, request.evaluationId]);
    return { evaluationId: request.evaluationId, outcome: 'complete', groupVersionIds, dispositionCount: disposed.size };
  });
}
