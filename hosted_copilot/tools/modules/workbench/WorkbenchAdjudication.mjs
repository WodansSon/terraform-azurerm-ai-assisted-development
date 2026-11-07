import { randomUUID } from 'node:crypto';
import { requireSourceObject, requireSourceText, requireSourceHash, sourceTextHash } from './WorkbenchSourceRecords.mjs';
import { prepareEvaluationInput, withEvaluationTransaction } from './WorkbenchEvaluations.mjs';
import { readSelectedCapacityConfiguration } from './WorkbenchWorkspace.mjs';

function positiveIds(value, label, allowEmpty = false) {
  if (!Array.isArray(value) || (!allowEmpty && value.length === 0) || new Set(value).size !== value.length ||
    value.some(id => !Number.isSafeInteger(id) || id < 1)) throw new Error(`${label} requires unique positive identities`);
  return value;
}

function subjectKey(subject) {
  requireSourceObject(subject, ['kind', 'id'], ['kind', 'id'], 'Comparison subject');
  if (!['group', 'rule'].includes(subject.kind) || !Number.isSafeInteger(subject.id) || subject.id < 1) throw new Error('Comparison subject has an invalid identity');
  return `${subject.kind}:${subject.id}`;
}

function pairKey(left, right) {
  return `${subjectKey(left)}|${subjectKey(right)}`;
}

export function prepareAdjudicationInput(connection, request) {
  const fields = ['binding', 'runId', 'profileId', 'groupVersionIds'];
  requireSourceObject(request, [...fields, 'rightGroupVersionIds'], fields, 'Adjudication request');
  readSelectedCapacityConfiguration(connection, request.binding);
  const leftIds = positiveIds(request.groupVersionIds, 'Adjudication groups');
  const rightIds = positiveIds(request.rightGroupVersionIds ?? [], 'Cross-comparison groups', true);
  if (rightIds.some(id => leftIds.includes(id))) throw new Error('Cross-comparison group sets must be disjoint');
  const context = connection.get(`SELECT context.*, run.outcome FROM analysis_run_contexts context
    JOIN analysis_runs run ON run.id = context.run_id WHERE context.run_id = ?`, [request.runId]);
  const profile = connection.get('SELECT * FROM evaluator_profiles WHERE id = ?', [request.profileId]);
  if (!context || context.outcome !== 'running' || profile?.task_code !== 'adjudication' ||
    !connection.get('SELECT assignment_id FROM analysis_run_llm_assignments WHERE run_id = ? AND task_code = ? AND assignment_id = ?',
      [request.runId, 'adjudication', profile.llm_assignment_id])) throw new Error('Adjudication requires its running pinned task context');
  const parents = new Map();
  const groups = [...leftIds, ...rightIds].map(groupVersionId => {
    const group = connection.get(`SELECT version.*, wording.text AS wording, evaluation.input_fingerprint, evaluation.evaluator_profile_id,
      profile.llm_assignment_id, profile.task_code FROM group_versions version JOIN wording_versions wording ON wording.id = version.suggested_wording_id
      JOIN evaluations evaluation ON evaluation.id = version.synthesis_evaluation_id JOIN evaluator_profiles profile ON profile.id = evaluation.evaluator_profile_id
      JOIN run_evaluations used ON used.evaluation_id = evaluation.id
      WHERE version.id = ? AND used.run_id = ? AND evaluation.outcome = 'complete'`, [groupVersionId, request.runId]);
    if (!group || group.task_code !== 'reconciliation' || !connection.get('SELECT assignment_id FROM analysis_run_llm_assignments WHERE run_id = ? AND task_code = ? AND assignment_id = ?',
      [request.runId, 'reconciliation', group.llm_assignment_id])) throw new Error('Adjudication group does not belong to completed pinned synthesis');
    if (!parents.has(group.synthesis_evaluation_id)) {
      const inputs = connection.all('SELECT * FROM evaluation_inputs WHERE evaluation_id = ? ORDER BY id', [group.synthesis_evaluation_id]);
      const prepared = prepareEvaluationInput(connection, { binding: request.binding, runId: request.runId, profileId: group.evaluator_profile_id,
        sourceVersionIds: inputs.filter(row => row.role_code === 'source').map(row => row.source_version_id),
        assessmentResultIds: inputs.filter(row => row.role_code === 'assessment-result').map(row => row.assessment_result_id),
        componentIds: inputs.filter(row => row.role_code === 'component').map(row => row.reconciliation_component_id), reconciliationPhase: 'synthesis' });
      if (sourceTextHash(prepared.serializedInput) !== group.input_fingerprint) throw new Error('Adjudication refuses changed synthesis inputs');
      parents.set(group.synthesis_evaluation_id, JSON.parse(prepared.serializedInput));
    }
    const parent = parents.get(group.synthesis_evaluation_id);
    const members = connection.all('SELECT assessment_result_id AS assessmentResultId, member_role AS role, meaning_coverage_rationale AS coverageRationale FROM group_members WHERE group_version_id = ? ORDER BY assessment_result_id',
      [groupVersionId]).map(row => ({ ...row }));
    if (members.length === 0 || members.some(member => !parent.assessments.some(assessment => assessment.assessmentResultId === member.assessmentResultId))) {
      throw new Error('Adjudication group membership does not match its synthesis evidence');
    }
    const operations = connection.all(`SELECT operation.operation_role AS role, action.code AS action, operation.target_rule_version_id AS targetRuleVersionId,
      operation.rationale, surface.code AS surfaceCode, operation.section_heading AS sectionHeading FROM recommended_changes operation
      JOIN action_definitions action ON action.id = operation.action_id LEFT JOIN guidance_surfaces surface ON surface.id = operation.surface_id
      WHERE operation.group_version_id = ? ORDER BY operation.ordinal`, [groupVersionId]).map(row => ({ ...row }));
    if (operations.filter(operation => operation.role === 'primary').length !== 1) throw new Error('Adjudication group lacks complete recommendations');
    return { groupVersionId, groupId: group.group_id, title: group.title, wording: group.wording, semanticSummary: group.semantic_summary,
      reviewState: group.review_state, needsReview: Boolean(group.needs_review), members, operations };
  });
  const parent = parents.values().next().value;
  const activeRules = parent.catalogRules.filter(rule => rule.kind === 'managed' && rule.lifecycle === 'active');
  const protectedRules = parent.protectedRules;
  const leftSubjects = leftIds.map(id => ({ kind: 'group', id }));
  const rightSubjects = rightIds.map(id => ({ kind: 'group', id }));
  const comparisonPairs = [];
  for (const [index, left] of leftSubjects.entries()) {
    const comparisons = rightIds.length ? rightSubjects : [
      ...leftSubjects.slice(index + 1), ...activeRules.map(rule => ({ kind: 'rule', id: rule.ruleVersionId })),
      ...protectedRules.map(rule => ({ kind: 'rule', id: rule.ruleVersionId })),
    ];
    for (const right of comparisons) comparisonPairs.push({ left, right });
  }
  const input = { stage: 'adjudication', phase: 'relationships', mode: rightIds.length ? 'cross-groups' : 'groups-and-baseline',
    groups, activeRules, protectedRules, comparisonPairs, baseCatalogId: context.base_catalog_id, protectedSnapshotId: context.protected_snapshot_id,
    scoringPolicyId: context.scoring_policy_id, capacityPolicyId: context.capacity_policy_id };
  return { context, input, serializedInput: JSON.stringify(input) };
}

export function recordAdjudicationRequest(connection, request) {
  return withEvaluationTransaction(connection, () => {
    const prepared = prepareAdjudicationInput(connection, request);
    const fingerprint = sourceTextHash(prepared.serializedInput);
    const evaluationId = Number(connection.run(`INSERT INTO evaluations(evaluator_profile_id, input_fingerprint, requested_at, outcome)
      VALUES (?, ?, ?, 'running')`, [request.profileId, fingerprint, new Date().toISOString()]).lastInsertRowid);
    connection.run("INSERT INTO run_evaluations VALUES (?, ?, 'executed')", [request.runId, evaluationId]);
    for (const [role, ids] of [['group-left', request.groupVersionIds], ['group-right', request.rightGroupVersionIds ?? []]]) {
      for (const id of ids) connection.run('INSERT INTO evaluation_inputs(evaluation_id, role_code, group_version_id) VALUES (?, ?, ?)', [evaluationId, role, id]);
    }
    for (const [role, rules] of [['active-rule', prepared.input.activeRules], ['protected-rule', prepared.input.protectedRules]]) {
      for (const rule of rules) connection.run('INSERT INTO evaluation_inputs(evaluation_id, role_code, rule_version_id) VALUES (?, ?, ?)', [evaluationId, role, rule.ruleVersionId]);
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

export function commitAdjudicationResults(connection, request) {
  const fields = ['binding', 'runId', 'evaluationId', 'inputFingerprint', 'result'];
  requireSourceObject(request, fields, fields, 'Adjudication result command');
  readSelectedCapacityConfiguration(connection, request.binding);
  requireSourceHash(request.inputFingerprint, 'Adjudication input fingerprint');
  const resultFields = ['schemaVersion', 'stage', 'phase', 'comparisons'];
  requireSourceObject(request.result, resultFields, resultFields, 'Adjudication result');
  if (request.result.schemaVersion !== 4 || request.result.stage !== 'adjudication' || request.result.phase !== 'relationships' ||
    !Array.isArray(request.result.comparisons)) throw new Error('Unsupported adjudication result contract');
  return withEvaluationTransaction(connection, () => {
    const evaluation = connection.get(`SELECT evaluation.*, profile.task_code, run.outcome AS run_outcome FROM evaluations evaluation
      JOIN evaluator_profiles profile ON profile.id = evaluation.evaluator_profile_id JOIN run_evaluations used ON used.evaluation_id = evaluation.id
      JOIN analysis_runs run ON run.id = used.run_id WHERE evaluation.id = ? AND used.run_id = ?`, [request.evaluationId, request.runId]);
    if (!evaluation || evaluation.outcome !== 'running' || evaluation.run_outcome !== 'running' || evaluation.task_code !== 'adjudication' ||
      evaluation.input_fingerprint !== request.inputFingerprint) throw new Error('Adjudication result does not match its running identity');
    const inputs = connection.all('SELECT * FROM evaluation_inputs WHERE evaluation_id = ? ORDER BY id', [request.evaluationId]);
    const prepared = prepareAdjudicationInput(connection, { binding: request.binding, runId: request.runId, profileId: evaluation.evaluator_profile_id,
      groupVersionIds: inputs.filter(row => row.role_code === 'group-left').map(row => row.group_version_id),
      rightGroupVersionIds: inputs.filter(row => row.role_code === 'group-right').map(row => row.group_version_id) });
    if (sourceTextHash(prepared.serializedInput) !== request.inputFingerprint) throw new Error('Adjudication refuses changed input scope or evidence');
    const expected = new Set(prepared.input.comparisonPairs.map(pair => pairKey(pair.left, pair.right)));
    const received = new Set();
    const subjects = new Map([
      ...prepared.input.groups.map(group => [`group:${group.groupVersionId}`, group.wording]),
      ...[...prepared.input.activeRules, ...prepared.input.protectedRules].map(rule => [`rule:${rule.ruleVersionId}`, rule.text]),
    ]);
    const findingIds = [];
    let issueCount = 0;
    for (const comparison of request.result.comparisons) {
      const comparisonFields = ['left', 'right', 'relationship', 'title', 'rationale', 'needsReview', 'leftQuote', 'rightQuote'];
      requireSourceObject(comparison, comparisonFields, comparisonFields, 'Adjudicated comparison');
      const key = pairKey(comparison.left, comparison.right);
      if (!expected.has(key) || received.has(key)) throw new Error('Adjudication contains foreign or repeated comparison coverage');
      if (!['independent', 'equivalent', 'partial-overlap', 'left-extends-right', 'left-narrows-right', 'conflicts'].includes(comparison.relationship) ||
        typeof comparison.needsReview !== 'boolean' || (comparison.relationship === 'independent' && comparison.needsReview)) {
        throw new Error('Adjudication relationship or review disposition is invalid');
      }
      for (const field of ['title', 'rationale']) requireSourceText(comparison[field], field);
      for (const [subject, quote] of [[comparison.left, comparison.leftQuote], [comparison.right, comparison.rightQuote]]) {
        if (quote === null && comparison.relationship === 'independent') continue;
        requireSourceText(quote, 'Comparison evidence quote');
        if (quote.length > 2000 || !subjects.get(subjectKey(subject)).includes(quote)) throw new Error('Comparison quote must occur in its exact supplied wording');
      }
      const findingId = Number(connection.run('INSERT INTO findings(evaluation_id, finding_kind, title, rationale) VALUES (?, ?, ?, ?)',
        [request.evaluationId, comparison.relationship, comparison.title, comparison.rationale]).lastInsertRowid);
      findingIds.push(findingId);
      for (const [ordinal, [role, subject, quote]] of [['left', comparison.left, comparison.leftQuote], ['right', comparison.right, comparison.rightQuote]].entries()) {
        const field = subject.kind === 'group' ? 'group_version_id' : 'rule_version_id';
        connection.run(`INSERT INTO finding_participants(finding_id, participant_role, ordinal, ${field}, evidence_quote) VALUES (?, ?, ?, ?, ?)`,
          [findingId, role, ordinal, subject.id, quote]);
      }
      if (comparison.needsReview) {
        const issueId = Number(connection.run('INSERT INTO issues(display_key, title, created_at) VALUES (?, ?, ?)',
          [`ISSUE-${randomUUID()}`, comparison.title, new Date().toISOString()]).lastInsertRowid);
        connection.run('INSERT INTO issue_findings(issue_id, finding_id, correspondence_rationale, matched_by_evaluation_id) VALUES (?, ?, ?, ?)',
          [issueId, findingId, comparison.rationale, request.evaluationId]);
        issueCount += 1;
      }
      received.add(key);
    }
    if (received.size !== expected.size) throw new Error('Adjudication must account for every requested comparison');
    connection.run("UPDATE evaluations SET outcome = 'complete', completed_at = ? WHERE id = ?", [new Date().toISOString(), request.evaluationId]);
    return { evaluationId: request.evaluationId, outcome: 'complete', findingIds, issueCount, comparisonCount: received.size };
  });
}
