import { randomUUID } from 'node:crypto';
import { requireSourceObject, requireSourceHash, sourceTextHash } from './WorkbenchSourceRecords.mjs';
import { prepareEvaluationInput, readRecordedReconciliationRequest, readAssessmentRecoveryPlan, withEvaluationTransaction } from './WorkbenchEvaluations.mjs';
import { readSelectedCapacityConfiguration } from './WorkbenchWorkspace.mjs';
import { readAdjudicationComponents, validateAdjudicationResult } from './WorkbenchRelationshipComponents.mjs';
import { evaluationResultError } from './WorkbenchEvaluationFailures.mjs';

function positiveIds(value, label, allowEmpty = false) {
  if (!Array.isArray(value) || (!allowEmpty && value.length === 0) || new Set(value).size !== value.length ||
    value.some(id => !Number.isSafeInteger(id) || id < 1)) throw new Error(`${label} requires unique positive identities`);
  return value;
}

// Prevent relationship decisions from starting while source coverage or final reconciliation is incomplete.
export function assertAdjudicationReady(connection, request) {
  const profiles = connection.all(`SELECT DISTINCT evaluation.evaluator_profile_id AS id FROM run_evaluations used
    JOIN evaluations evaluation ON evaluation.id = used.evaluation_id JOIN evaluator_profiles profile ON profile.id = evaluation.evaluator_profile_id
    WHERE used.run_id = ? AND profile.task_code = 'assessment'`, [request.runId]);
  const sourceProfileId = request.sourceProfileId ?? profiles[0]?.id;
  if (!sourceProfileId || profiles.some(profile => profile.id !== sourceProfileId)) throw new Error('Adjudication requires one pinned source-assessment profile');
  const recovery = readAssessmentRecoveryPlan(connection, { binding: request.binding, runId: request.runId, profileId: sourceProfileId });
  const assessments = connection.all(`SELECT result.id FROM assessment_results result JOIN run_evaluations used ON used.evaluation_id = result.evaluation_id
    WHERE used.run_id = ?`, [request.runId]);
  const dispositions = connection.all('SELECT assessment_result_id AS id FROM reconciliation_dispositions WHERE run_id = ?', [request.runId]);
  if (recovery.remainingSourceVersionIds.length || recovery.unfinishedEvaluationIds.length ||
    assessments.length !== dispositions.length || assessments.some(assessment => !dispositions.some(disposition => disposition.id === assessment.id)) ||
    connection.get(`SELECT evaluation.id FROM evaluations evaluation JOIN run_evaluations used ON used.evaluation_id = evaluation.id
      JOIN evaluator_profiles profile ON profile.id = evaluation.evaluator_profile_id
      WHERE used.run_id = ? AND evaluation.outcome = 'running' AND profile.task_code = 'reconciliation' LIMIT 1`, [request.runId])) {
    throw new Error('Adjudication requires complete committed source assessment and final reconciliation');
  }
}

// Reconstruct complete component evidence from verified synthesis inputs and pinned rule/operation-target snapshots.
export function prepareAdjudicationInput(connection, request, parents = new Map()) {
  const fields = ['binding', 'runId', 'profileId', 'componentIds'];
  requireSourceObject(request, fields, fields, 'Adjudication request');
  readSelectedCapacityConfiguration(connection, request.binding);
  positiveIds(request.componentIds, 'Adjudication components');
  const context = connection.get(`SELECT context.*, run.outcome FROM analysis_run_contexts context
    JOIN analysis_runs run ON run.id = context.run_id WHERE context.run_id = ?`, [request.runId]);
  const profile = connection.get('SELECT * FROM evaluator_profiles WHERE id = ?', [request.profileId]);
  if (!context || context.outcome !== 'running' || profile?.task_code !== 'adjudication' ||
    !connection.get('SELECT assignment_id FROM analysis_run_llm_assignments WHERE run_id = ? AND task_code = ? AND assignment_id = ?',
      [request.runId, 'adjudication', profile.llm_assignment_id])) throw new Error('Adjudication requires its running pinned task context');
  const available = new Map(readAdjudicationComponents(connection, request.runId).map(component => [component.componentId, component]));
  const components = request.componentIds.toSorted((left, right) => left - right).map(id => {
    if (!available.has(id)) throw new Error('Adjudication requires complete recorded relationship components');
    return available.get(id);
  });
  const groupIds = [...new Set(components.flatMap(component => component.subjects.filter(subject => subject.kind === 'group').map(subject => subject.id)))].toSorted((left, right) => left - right);
  const groups = groupIds.map(groupVersionId => {
    const group = connection.get(`SELECT version.*, wording.text AS wording, evaluation.input_fingerprint, evaluation.evaluator_profile_id,
      profile.llm_assignment_id, profile.task_code FROM group_versions version JOIN wording_versions wording ON wording.id = version.suggested_wording_id
      JOIN evaluations evaluation ON evaluation.id = version.synthesis_evaluation_id JOIN evaluator_profiles profile ON profile.id = evaluation.evaluator_profile_id
      JOIN run_evaluations used ON used.evaluation_id = evaluation.id
      WHERE version.id = ? AND used.run_id = ? AND evaluation.outcome = 'complete'`, [groupVersionId, request.runId]);
    if (!group || group.task_code !== 'reconciliation' || !connection.get('SELECT assignment_id FROM analysis_run_llm_assignments WHERE run_id = ? AND task_code = ? AND assignment_id = ?',
      [request.runId, 'reconciliation', group.llm_assignment_id])) throw new Error('Adjudication group does not belong to completed pinned synthesis');
    if (!parents.has(group.synthesis_evaluation_id)) {
      const prepared = prepareEvaluationInput(connection,
        readRecordedReconciliationRequest(connection, request.binding, request.runId, group.synthesis_evaluation_id, 'synthesis'));
      if (sourceTextHash(prepared.serializedInput) !== group.input_fingerprint) throw new Error('Adjudication refuses changed synthesis inputs');
      parents.set(group.synthesis_evaluation_id, JSON.parse(prepared.serializedInput));
    }
    const parent = parents.get(group.synthesis_evaluation_id);
    let members = connection.all('SELECT assessment_result_id AS assessmentResultId, member_role AS role, meaning_coverage_rationale AS coverageRationale FROM group_members WHERE group_version_id = ? ORDER BY assessment_result_id',
      [groupVersionId]).map(row => ({ ...row }));
    if (members.length === 0 || members.some(member => !parent.assessments.some(assessment => assessment.assessmentResultId === member.assessmentResultId))) {
      throw new Error('Adjudication group membership does not match its synthesis evidence');
    }
    members = members.map(member => {
      const assessment = parent.assessments.find(candidate => candidate.assessmentResultId === member.assessmentResultId);
      return { ...member, sourceVersionId: assessment.sourceVersionId, sourceMeaning: assessment.sourceMeaning ??
        parent.sources.find(source => source.sourceVersionId === assessment.sourceMeaningSourceVersionId).content };
    });
    const operations = connection.all(`SELECT operation.operation_role AS role, action.code AS action, operation.target_rule_version_id AS targetRuleVersionId,
      operation.rationale, surface.code AS surfaceCode, operation.section_heading AS sectionHeading FROM recommended_changes operation
      JOIN action_definitions action ON action.id = operation.action_id LEFT JOIN guidance_surfaces surface ON surface.id = operation.surface_id
      WHERE operation.group_version_id = ? ORDER BY operation.ordinal`, [groupVersionId]).map(row => {
      const target = row.targetRuleVersionId === null ? null : parent.catalogRules.find(rule => rule.ruleVersionId === row.targetRuleVersionId && rule.kind === 'managed');
      if (row.targetRuleVersionId !== null && !target) throw new Error('Adjudication operation requires its exact pinned managed target');
      return { ...row, targetLifecycle: target?.lifecycle ?? null, targetRule: target ?? null };
    });
    if (operations.filter(operation => operation.role === 'primary').length !== 1) throw new Error('Adjudication group lacks complete recommendations');
    return { groupVersionId, groupId: group.group_id, title: group.title, wording: group.wording, semanticSummary: group.semantic_summary,
      reviewState: group.review_state, needsReview: Boolean(group.needs_review), members, operations };
  });
  const parent = parents.values().next().value;
  const ruleIds = new Set(components.flatMap(component => component.subjects.filter(subject => subject.kind === 'rule').map(subject => subject.id)));
  const rules = [...parent.catalogRules.filter(rule => rule.kind === 'managed'), ...parent.protectedRules.map(rule => ({ ...rule, kind: 'protected' }))]
    .filter(rule => ruleIds.has(rule.ruleVersionId)).toSorted((left, right) => left.ruleVersionId - right.ruleVersionId);
  if (rules.length !== ruleIds.size) throw new Error('Relationship rules must belong to the pinned managed or protected snapshot');
  const input = { stage: 'adjudication', phase: 'components', components,
    groups, rules, baseCatalogId: context.base_catalog_id, protectedSnapshotId: context.protected_snapshot_id,
    scoringPolicyId: context.scoring_policy_id, capacityPolicyId: context.capacity_policy_id };
  return { context, input, serializedInput: JSON.stringify(input) };
}

// Recover component scope from typed input rows and reject missing, extra, or obsolete pairwise dependencies.
export function readRecordedAdjudicationRequest(connection, { binding, runId, profileId, evaluationId }) {
  const inputs = connection.all('SELECT * FROM evaluation_inputs WHERE evaluation_id = ? ORDER BY id', [evaluationId]);
  const componentIds = inputs.filter(row => row.role_code === 'relationship-component').map(row => row.group_relationship_id);
  if (!componentIds.length || inputs.some(row => ['baseline-group', 'group-left', 'group-right'].includes(row.role_code))) {
    throw new Error('Recorded adjudication requires the connected-component contract');
  }
  const components = readAdjudicationComponents(connection, runId).filter(component => componentIds.includes(component.componentId));
  if (components.length !== componentIds.length) throw new Error('Recorded adjudication component scope has changed');
  const context = connection.get('SELECT * FROM analysis_run_contexts WHERE run_id = ?', [runId]);
  const expected = new Set([
    ...components.map(component => `relationship-component:group_relationship_id:${component.componentId}`),
    ...components.flatMap(component => component.relationships.map(relationship => `relationship:group_relationship_id:${relationship.relationshipId}`)),
    ...components.flatMap(component => component.subjects.filter(subject => subject.kind === 'group').map(subject => `group:group_version_id:${subject.id}`)),
    ...components.flatMap(component => component.subjects.filter(subject => subject.kind === 'rule').map(subject =>
      `${connection.get('SELECT rule_kind FROM rules rule JOIN rule_versions version ON version.rule_id = rule.id WHERE version.id = ?', [subject.id]).rule_kind === 'protected' ? 'protected-rule' : 'managed-rule'}:rule_version_id:${subject.id}`)),
    `protected:protected_snapshot_id:${context.protected_snapshot_id}`, `scoring:scoring_policy_id:${context.scoring_policy_id}`,
    `capacity:capacity_policy_id:${context.capacity_policy_id}`,
    ...(context.base_catalog_id === null ? [] : [`catalog:catalog_version_id:${context.base_catalog_id}`]),
  ]);
  const fields = ['group_relationship_id', 'group_version_id', 'rule_version_id', 'protected_snapshot_id', 'scoring_policy_id', 'capacity_policy_id', 'catalog_version_id'];
  const actual = inputs.map(row => {
    const field = fields.find(field => row[field] !== null);
    return `${row.role_code}:${field}:${row[field]}`;
  });
  if (actual.length !== expected.size || actual.some(key => !expected.has(key))) throw new Error('Recorded adjudication requires exact typed component inputs');
  return { binding, runId, profileId, componentIds };
}

// Commit the exact component, relationship, subject, and policy references before any adjudication inference begins.
export function recordAdjudicationRequest(connection, request) {
  return withEvaluationTransaction(connection, () => {
    assertAdjudicationReady(connection, request);
    const prepared = prepareAdjudicationInput(connection, request);
    const fingerprint = sourceTextHash(prepared.serializedInput);
    const evaluationId = Number(connection.run(`INSERT INTO evaluations(evaluator_profile_id, input_fingerprint, requested_at, outcome)
      VALUES (?, ?, ?, 'running')`, [request.profileId, fingerprint, new Date().toISOString()]).lastInsertRowid);
    connection.run("INSERT INTO run_evaluations VALUES (?, ?, 'executed')", [request.runId, evaluationId]);
    for (const component of prepared.input.components) {
      connection.run("INSERT INTO evaluation_inputs(evaluation_id, role_code, group_relationship_id) VALUES (?, 'relationship-component', ?)", [evaluationId, component.componentId]);
      for (const relationship of component.relationships) connection.run("INSERT INTO evaluation_inputs(evaluation_id, role_code, group_relationship_id) VALUES (?, 'relationship', ?)",
        [evaluationId, relationship.relationshipId]);
    }
    for (const group of prepared.input.groups) connection.run("INSERT INTO evaluation_inputs(evaluation_id, role_code, group_version_id) VALUES (?, 'group', ?)", [evaluationId, group.groupVersionId]);
    for (const rule of prepared.input.rules) {
      connection.run('INSERT INTO evaluation_inputs(evaluation_id, role_code, rule_version_id) VALUES (?, ?, ?)',
        [evaluationId, rule.kind === 'protected' ? 'protected-rule' : 'managed-rule', rule.ruleVersionId]);
    }
    for (const [role, field, id] of [
      ['protected', 'protected_snapshot_id', prepared.context.protected_snapshot_id], ['scoring', 'scoring_policy_id', prepared.context.scoring_policy_id],
      ['capacity', 'capacity_policy_id', prepared.context.capacity_policy_id], ['catalog', 'catalog_version_id', prepared.context.base_catalog_id],
    ]) {
      if (id !== null) connection.run(`INSERT INTO evaluation_inputs(evaluation_id, role_code, ${field}) VALUES (?, ?, ?)`, [evaluationId, role, id]);
    }
    return { evaluationId, runId: request.runId, profileId: request.profileId, inputFingerprint: fingerprint, serializedInput: prepared.serializedInput };
  });
}

// Revalidate the recorded request and atomically store relationship decisions, grouped issues, wording, and advisory actions.
export function commitAdjudicationResults(connection, request) {
  const fields = ['binding', 'runId', 'evaluationId', 'inputFingerprint', 'result'];
  requireSourceObject(request, fields, fields, 'Adjudication result command');
  readSelectedCapacityConfiguration(connection, request.binding);
  requireSourceHash(request.inputFingerprint, 'Adjudication input fingerprint');
  return withEvaluationTransaction(connection, () => {
    const evaluation = connection.get(`SELECT evaluation.*, profile.task_code, run.outcome AS run_outcome FROM evaluations evaluation
      JOIN evaluator_profiles profile ON profile.id = evaluation.evaluator_profile_id JOIN run_evaluations used ON used.evaluation_id = evaluation.id
      JOIN analysis_runs run ON run.id = used.run_id WHERE evaluation.id = ? AND used.run_id = ?`, [request.evaluationId, request.runId]);
    if (!evaluation || evaluation.outcome !== 'running' || evaluation.run_outcome !== 'running' || evaluation.task_code !== 'adjudication' ||
      evaluation.input_fingerprint !== request.inputFingerprint) throw evaluationResultError('Adjudication result does not match its running identity');
    const prepared = prepareAdjudicationInput(connection, readRecordedAdjudicationRequest(connection, {
      binding: request.binding, runId: request.runId, profileId: evaluation.evaluator_profile_id, evaluationId: request.evaluationId }));
    if (sourceTextHash(prepared.serializedInput) !== request.inputFingerprint) throw evaluationResultError('Adjudication refuses changed input scope or evidence');
    const validated = validateAdjudicationResult(prepared.input, request.result);
    const findingIds = [];
    const findingByRelationship = new Map();
    const now = new Date().toISOString();
    const storeWording = text => Number(connection.run('INSERT INTO wording_versions(text, content_sha256, created_at) VALUES (?, ?, ?)',
      [text, sourceTextHash(text), now]).lastInsertRowid);
    for (const comparison of request.result.relationshipDecisions) {
      const relationship = validated.relationships.get(comparison.relationshipId);
      const findingId = Number(connection.run('INSERT INTO findings(evaluation_id, finding_kind, title, rationale) VALUES (?, ?, ?, ?)',
        [request.evaluationId, comparison.relationship, comparison.title, comparison.rationale]).lastInsertRowid);
      findingIds.push(findingId);
      findingByRelationship.set(comparison.relationshipId, findingId);
      for (const [ordinal, [role, subject, quote]] of [['left', relationship.left, comparison.leftQuote], ['right', relationship.right, comparison.rightQuote]].entries()) {
        const field = subject.kind === 'group' ? 'group_version_id' : 'rule_version_id';
        connection.run(`INSERT INTO finding_participants(finding_id, participant_role, ordinal, ${field}, evidence_quote) VALUES (?, ?, ?, ?, ?)`,
          [findingId, role, ordinal, subject.id, quote]);
      }
      connection.run('INSERT INTO adjudication_relationship_decisions VALUES (?, ?, ?, ?)',
        [request.evaluationId, comparison.relationshipId, findingId, comparison.disposition]);
    }
    for (const issue of request.result.issues) {
      const issueId = Number(connection.run('INSERT INTO issues(display_key, title, created_at) VALUES (?, ?, ?)',
        [`ISSUE-${randomUUID()}`, issue.title, now]).lastInsertRowid);
      const wordingSource = issue.wording.source;
      connection.run(`INSERT INTO adjudicated_issues VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
        [issueId, request.evaluationId, issue.anchor.kind === 'group' ? issue.anchor.id : null, issue.anchor.kind === 'rule' ? issue.anchor.id : null,
          issue.classification, Number(issue.blocking), issue.assessmentSummary, issue.wording.status,
          wordingSource?.kind === 'group' ? wordingSource.id : null, wordingSource?.kind === 'rule' ? wordingSource.id : null,
          issue.wording.text === null ? null : storeWording(issue.wording.text), issue.wording.rationale, issue.recommendedMaintainerAction.summary]);
      for (const relationshipId of issue.relationshipIds) {
        connection.run('INSERT INTO issue_findings(issue_id, finding_id, correspondence_rationale, matched_by_evaluation_id) VALUES (?, ?, ?, ?)',
          [issueId, findingByRelationship.get(relationshipId), validated.decisions.get(relationshipId).rationale, request.evaluationId]);
      }
      for (const [ordinal, member] of issue.members.entries()) {
        connection.run('INSERT INTO adjudicated_issue_members VALUES (?, ?, ?, ?, ?)',
          [issueId, ordinal, member.subject.kind === 'group' ? member.subject.id : null, member.subject.kind === 'rule' ? member.subject.id : null, member.disposition]);
      }
      for (const [ordinal, operation] of issue.recommendedMaintainerAction.operations.entries()) {
        const operationId = Number(connection.run(`INSERT INTO adjudicated_issue_operations(issue_id, ordinal, group_version_id, action_code, wording_version_id)
          VALUES (?, ?, ?, ?, ?)`, [issueId, ordinal, operation.subject.id, operation.action, storeWording(operation.proposedText)]).lastInsertRowid);
        for (const ruleId of operation.retireRuleVersionIds) connection.run('INSERT INTO adjudicated_operation_retirements VALUES (?, ?)', [operationId, ruleId]);
      }
    }
    connection.run("UPDATE evaluations SET outcome = 'complete', completed_at = ? WHERE id = ?", [now, request.evaluationId]);
    return { evaluationId: request.evaluationId, outcome: 'complete', findingIds, issueCount: request.result.issues.length,
      comparisonCount: validated.decisions.size };
  });
}

// Rebuild the grouped result from persisted rows, checking relationship participants before completion revalidates it.
export function readAdjudicationResult(connection, evaluationId) {
  const subject = (groupId, ruleId) => groupId === null ? { kind: 'rule', id: ruleId } : { kind: 'group', id: groupId };
  const relationshipDecisions = connection.all(`SELECT decision.*, finding.finding_kind, finding.title, finding.rationale
    FROM adjudication_relationship_decisions decision JOIN findings finding ON finding.id = decision.finding_id
    WHERE decision.evaluation_id = ? ORDER BY decision.relationship_id`, [evaluationId]).map(row => {
    const participants = connection.all('SELECT * FROM finding_participants WHERE finding_id = ? ORDER BY ordinal', [row.finding_id]);
    if (participants.length !== 2 || participants[0].participant_role !== 'left' || participants[1].participant_role !== 'right') {
      throw new Error('Adjudication requires exact persisted relationship participants');
    }
    const relation = connection.get('SELECT * FROM group_relationships WHERE id = ?', [row.relationship_id]);
    if (participants[0].group_version_id !== relation.group_version_id ||
      (relation.target_rule_version_id !== null && participants[1].rule_version_id !== relation.target_rule_version_id) ||
      (relation.target_assessment_id !== null && !connection.get(`SELECT member.group_version_id FROM group_members member
        JOIN group_versions version ON version.id = member.group_version_id JOIN run_evaluations used ON used.evaluation_id = version.synthesis_evaluation_id
        JOIN run_evaluations adjudication ON adjudication.run_id = used.run_id
        WHERE adjudication.evaluation_id = ? AND member.assessment_result_id = ? AND member.group_version_id = ?`,
      [evaluationId, relation.target_assessment_id, participants[1].group_version_id]))) {
      throw new Error('Persisted relationship participants do not match recorded evidence');
    }
    return { relationshipId: row.relationship_id, disposition: row.disposition, relationship: row.finding_kind,
      title: row.title, rationale: row.rationale, leftQuote: participants[0].evidence_quote, rightQuote: participants[1].evidence_quote };
  });
  const issues = connection.all(`SELECT detail.*, issue.title, wording.text FROM adjudicated_issues detail
    JOIN issues issue ON issue.id = detail.issue_id LEFT JOIN wording_versions wording ON wording.id = detail.wording_version_id
    WHERE detail.evaluation_id = ? ORDER BY detail.issue_id`, [evaluationId]).map(row => ({
    anchor: subject(row.anchor_group_version_id, row.anchor_rule_version_id), classification: row.classification, title: row.title,
    blocking: Boolean(row.blocking), assessmentSummary: row.assessment_summary,
    members: connection.all('SELECT * FROM adjudicated_issue_members WHERE issue_id = ? ORDER BY ordinal', [row.issue_id])
      .map(member => ({ subject: subject(member.group_version_id, member.rule_version_id), disposition: member.disposition })),
    relationshipIds: connection.all(`SELECT decision.relationship_id FROM issue_findings link
      JOIN adjudication_relationship_decisions decision ON decision.finding_id = link.finding_id WHERE link.issue_id = ? ORDER BY decision.relationship_id`, [row.issue_id]).map(link => link.relationship_id),
    wording: { status: row.wording_status, source: row.wording_status === 'unresolved' ? null : subject(row.wording_group_version_id, row.wording_rule_version_id),
      text: row.text, rationale: row.wording_rationale },
    recommendedMaintainerAction: { summary: row.action_summary,
      operations: connection.all(`SELECT operation.*, wording.text FROM adjudicated_issue_operations operation
        JOIN wording_versions wording ON wording.id = operation.wording_version_id WHERE operation.issue_id = ? ORDER BY operation.ordinal`, [row.issue_id])
        .map(operation => ({ subject: { kind: 'group', id: operation.group_version_id }, action: operation.action_code, proposedText: operation.text,
          retireRuleVersionIds: connection.all('SELECT rule_version_id FROM adjudicated_operation_retirements WHERE operation_id = ? ORDER BY rule_version_id', [operation.id]).map(rule => rule.rule_version_id) })) },
  }));
  return { schemaVersion: 4, stage: 'adjudication', phase: 'components', relationshipDecisions, issues };
}
