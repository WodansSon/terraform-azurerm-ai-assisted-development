import { requireSourceObject, requireSourceText } from './WorkbenchSourceRecords.mjs';
import { evaluationResultError } from './WorkbenchEvaluationFailures.mjs';

// Namespace subject identities so a group and rule with the same numeric ID remain distinct graph vertices.
export function adjudicationSubjectKey(subject) {
  requireSourceObject(subject, ['kind', 'id'], ['kind', 'id'], 'Adjudication subject');
  if (!['group', 'rule'].includes(subject.kind) || !Number.isSafeInteger(subject.id) || subject.id < 1) {
    throw evaluationResultError('Adjudication subject requires a typed positive identity');
  }
  return `${subject.kind}:${subject.id}`;
}

// Traverse recorded edges as an undirected graph while preserving direction, provenance, and deterministic component IDs.
export function connectedRelationshipComponents(relationships) {
  const adjacency = new Map();
  const incident = new Map();
  const ids = new Set();
  for (const relationship of relationships) {
    if (!Number.isSafeInteger(relationship.relationshipId) || relationship.relationshipId < 1 || ids.has(relationship.relationshipId)) {
      throw evaluationResultError('Relationship components require unique positive relationship identities');
    }
    ids.add(relationship.relationshipId);
    const left = adjudicationSubjectKey(relationship.left);
    const right = adjudicationSubjectKey(relationship.right);
    if (left === right) throw evaluationResultError('Relationship components refuse self relationships');
    for (const [from, to] of [[left, right], [right, left]]) {
      if (!adjacency.has(from)) adjacency.set(from, new Set());
      adjacency.get(from).add(to);
      if (!incident.has(from)) incident.set(from, []);
      incident.get(from).push(relationship);
    }
  }
  const components = [];
  const visited = new Set();
  for (const start of [...adjacency.keys()].sort()) {
    if (visited.has(start)) continue;
    const members = new Set();
    const related = new Map();
    const queue = [start];
    visited.add(start);
    for (let index = 0; index < queue.length; index++) {
      const key = queue[index];
      members.add(key);
      for (const relationship of incident.get(key)) related.set(relationship.relationshipId, relationship);
      for (const neighbor of adjacency.get(key)) {
        if (!visited.has(neighbor)) { visited.add(neighbor); queue.push(neighbor); }
      }
    }
    const edges = [...related.values()]
      .toSorted((left, right) => left.relationshipId - right.relationshipId);
    const subjects = [...members].map(key => {
      const [kind, id] = key.split(':');
      return { kind, id: Number(id) };
    }).toSorted((left, right) => left.kind.localeCompare(right.kind) || left.id - right.id);
    components.push({ componentId: edges[0].relationshipId, subjects, relationships: edges });
  }
  return components.toSorted((left, right) => left.componentId - right.componentId);
}

// Resolve assessment targets to their unique final group owners and connect only persisted reconciliation relationships.
export function readAdjudicationComponents(connection, runId) {
  const owners = new Map();
  const groups = connection.all(`SELECT version.id, member.assessment_result_id FROM group_versions version
    JOIN group_members member ON member.group_version_id = version.id
    JOIN evaluations evaluation ON evaluation.id = version.synthesis_evaluation_id
    JOIN run_evaluations used ON used.evaluation_id = evaluation.id
    WHERE used.run_id = ? AND evaluation.outcome = 'complete' ORDER BY version.id, member.assessment_result_id`, [runId]);
  for (const group of groups) {
    if (owners.has(group.assessment_result_id)) throw evaluationResultError('Relationship components require unique final assessment ownership');
    owners.set(group.assessment_result_id, group.id);
  }
  const memberEvidence = new Map();
  for (const row of connection.all(`SELECT evidence.* FROM group_relationship_evidence evidence
    JOIN group_relationships relation ON relation.id = evidence.relationship_id
    JOIN group_versions version ON version.id = relation.group_version_id
    JOIN evaluations evaluation ON evaluation.id = version.synthesis_evaluation_id
    JOIN run_evaluations used ON used.evaluation_id = evaluation.id
    WHERE used.run_id = ? AND evaluation.outcome = 'complete' ORDER BY evidence.relationship_id, evidence.ordinal`, [runId])) {
    if (!memberEvidence.has(row.relationship_id)) memberEvidence.set(row.relationship_id, []);
    memberEvidence.get(row.relationship_id).push({
      assessmentResultId: row.source_assessment_id, sourceQuote: row.source_quote, targetQuote: row.target_quote,
    });
  }
  const relationships = connection.all(`SELECT relation.* FROM group_relationships relation
    JOIN group_versions version ON version.id = relation.group_version_id
    JOIN evaluations evaluation ON evaluation.id = version.synthesis_evaluation_id
    JOIN run_evaluations used ON used.evaluation_id = evaluation.id
    WHERE used.run_id = ? AND evaluation.outcome = 'complete' ORDER BY relation.id`, [runId]).map(row => {
    const targetGroupId = row.target_assessment_id === null ? null : owners.get(row.target_assessment_id);
    if (row.target_assessment_id !== null && targetGroupId === undefined) {
      throw evaluationResultError('Relationship evidence requires a final owner for its target assessment');
    }
    const members = memberEvidence.get(row.id);
    if (!members?.length) throw evaluationResultError('Relationship requires persisted supporting member evidence');
    return { relationshipId: row.id, left: { kind: 'group', id: row.group_version_id },
      right: targetGroupId === null ? { kind: 'rule', id: row.target_rule_version_id } : { kind: 'group', id: targetGroupId },
      relationship: row.relationship_code, rationale: row.rationale,
      evidence: { origin: row.evidence_origin, targetAssessmentResultId: row.target_assessment_id, members } };
  });
  return connectedRelationshipComponents(relationships);
}

function uniqueIds(value, label) {
  if (!Array.isArray(value) || !value.length || new Set(value).size !== value.length ||
    value.some(id => !Number.isSafeInteger(id) || id < 1)) throw evaluationResultError(`${label} requires unique positive identities`);
  return value;
}

// Require exact relationship accounting and coherent grouped issues with protected wording and lifecycle-valid advisory operations.
export function validateAdjudicationResult(input, result) {
  const fields = ['schemaVersion', 'stage', 'phase', 'relationshipDecisions', 'issues'];
  requireSourceObject(result, fields, fields, 'Grouped adjudication result');
  if (result.schemaVersion !== 4 || result.stage !== 'adjudication' || result.phase !== 'components' ||
    !Array.isArray(result.relationshipDecisions) || !Array.isArray(result.issues)) throw evaluationResultError('Unsupported grouped adjudication contract');
  const relationships = input.components.flatMap(component => component.relationships);
  const expected = new Map(relationships.map(relationship => [relationship.relationshipId, relationship]));
  const subjects = new Map([
    ...input.groups.map(group => [`group:${group.groupVersionId}`, { ...group, text: group.wording }]),
    ...input.rules.map(rule => [`rule:${rule.ruleVersionId}`, rule]),
  ]);
  const decisions = new Map();
  for (const decision of result.relationshipDecisions) {
    const decisionFields = ['relationshipId', 'disposition', 'relationship', 'title', 'rationale', 'leftQuote', 'rightQuote'];
    requireSourceObject(decision, decisionFields, decisionFields, 'Relationship decision');
    const relationship = expected.get(decision.relationshipId);
    if (!relationship || decisions.has(decision.relationshipId)) throw evaluationResultError('Adjudication contains foreign or repeated relationship coverage');
    const independent = decision.disposition === 'independent';
    if ((!independent && decision.disposition !== 'issue') ||
      (independent ? decision.relationship !== 'independent' :
        !['equivalent', 'partial-overlap', 'left-extends-right', 'left-narrows-right', 'conflicts'].includes(decision.relationship))) {
      throw evaluationResultError('Adjudication relationship and disposition must agree');
    }
    for (const field of ['title', 'rationale']) requireSourceText(decision[field], field);
    for (const [subject, quote] of [[relationship.left, decision.leftQuote], [relationship.right, decision.rightQuote]]) {
      if (independent && quote === null) continue;
      requireSourceText(quote, 'Relationship evidence quote');
      if (quote.length > 2000 || !subjects.get(adjudicationSubjectKey(subject))?.text.includes(quote)) {
        throw evaluationResultError('Relationship quote must occur in its exact supplied wording');
      }
    }
    decisions.set(decision.relationshipId, decision);
  }
  if (decisions.size !== expected.size) throw evaluationResultError('Adjudication must account for every recorded relationship');
  const issueComponents = connectedRelationshipComponents(relationships.filter(relationship => decisions.get(relationship.relationshipId).disposition === 'issue'));
  const covered = new Set();
  const operatedGroups = new Set();
  const retiredRules = new Set();
  for (const issue of result.issues) {
    const issueFields = ['anchor', 'classification', 'title', 'blocking', 'members', 'relationshipIds', 'assessmentSummary', 'wording', 'recommendedMaintainerAction'];
    requireSourceObject(issue, issueFields, issueFields, 'Adjudicated issue');
    for (const field of ['title', 'assessmentSummary']) requireSourceText(issue[field], field);
    const ids = uniqueIds(issue.relationshipIds, 'Issue relationships');
    const component = issueComponents.find(candidate => candidate.relationships.some(relationship => relationship.relationshipId === ids[0]));
    if (!component || ids.length !== component.relationships.length ||
      ids.some(id => !component.relationships.some(relationship => relationship.relationshipId === id) || covered.has(id))) {
      throw evaluationResultError('Each coherent material component requires exactly one complete grouped issue');
    }
    ids.forEach(id => covered.add(id));
    if (!Array.isArray(issue.members)) throw evaluationResultError('Issue requires complete member dispositions');
    const members = new Map();
    for (const member of issue.members) {
      requireSourceObject(member, ['subject', 'disposition'], ['subject', 'disposition'], 'Issue member');
      const key = adjudicationSubjectKey(member.subject);
      if (members.has(key) || !component.subjects.some(subject => adjudicationSubjectKey(subject) === key) ||
        !['keep', 'promote', 'replace', 'retire', 'exclude', 'defer', 'review'].includes(member.disposition)) {
        throw evaluationResultError('Issue contains foreign, repeated, or invalid member dispositions');
      }
      members.set(key, member.disposition);
    }
    const anchorKey = adjudicationSubjectKey(issue.anchor);
    if (members.size !== component.subjects.length || !members.has(anchorKey)) throw evaluationResultError('Issue requires its exact complete membership and one member anchor');
    const protectedMembers = component.subjects.filter(subject => subjects.get(adjudicationSubjectKey(subject)).kind === 'protected');
    const conflicting = ids.some(id => decisions.get(id).relationship === 'conflicts');
    const classification = protectedMembers.length > 1 ? 'protected-integrity' : protectedMembers.length === 1 ?
      conflicting ? 'protected-conflict' : 'protected-coverage' : conflicting ? 'contradiction' :
        ids.every(id => decisions.get(id).relationship === 'equivalent') ? 'duplicate' : 'overlap';
    if (issue.classification !== classification || issue.blocking !== (classification === 'protected-integrity') ||
      protectedMembers.some(subject => members.get(adjudicationSubjectKey(subject)) !== 'keep') ||
      (protectedMembers.length === 1 && anchorKey !== adjudicationSubjectKey(protectedMembers[0]))) {
      throw evaluationResultError('Issue classification, blocking state, and anchor must honor exact protected membership');
    }
    const action = issue.recommendedMaintainerAction;
    requireSourceObject(action, ['summary', 'operations'], ['summary', 'operations'], 'Advisory maintainer action');
    requireSourceText(action.summary, 'Advisory action summary');
    if (!Array.isArray(action.operations)) throw evaluationResultError('Advisory action requires complete operations');
    const operations = new Map();
    const ancillaryRetirements = new Set();
    for (const operation of action.operations) {
      const operationFields = ['subject', 'action', 'proposedText', 'retireRuleVersionIds'];
      requireSourceObject(operation, operationFields, operationFields, 'Adjudicated operation');
      const key = adjudicationSubjectKey(operation.subject);
      const group = subjects.get(key);
      if (operation.subject.kind !== 'group' || !members.has(key) || operations.has(key) || operatedGroups.has(key)) {
        throw evaluationResultError('Advisory operations must preserve unique supplied group ownership');
      }
      const primary = group.operations.find(candidate => candidate.role === 'primary');
      const allowed = group.groupId === null ? ['defer'] : primary.targetRuleVersionId === null ? ['add', 'exclude', 'defer'] :
        primary.targetLifecycle === 'retired' ? ['restore', 'defer'] : ['update', 'retire', 'defer'];
      const disposition = { add: 'promote', restore: 'promote', update: 'replace', retire: 'retire', exclude: 'exclude', defer: 'defer' }[operation.action];
      if (!allowed.includes(operation.action) || members.get(key) !== disposition) throw evaluationResultError('Advisory operation must match member disposition and pinned target lifecycle');
      requireSourceText(operation.proposedText, 'Advisory proposed text');
      if (!Array.isArray(operation.retireRuleVersionIds) || new Set(operation.retireRuleVersionIds).size !== operation.retireRuleVersionIds.length) {
        throw evaluationResultError('Advisory retirements require unique supplied rule identities');
      }
      for (const id of operation.retireRuleVersionIds) {
        const rule = subjects.get(`rule:${id}`);
        if (!Number.isSafeInteger(id) || !rule || rule.kind !== 'managed' || rule.lifecycle !== 'active' ||
          !members.has(`rule:${id}`) || members.get(`rule:${id}`) !== 'retire' || id === primary.targetRuleVersionId ||
          !['add', 'update', 'restore'].includes(operation.action) || ancillaryRetirements.has(id) || retiredRules.has(id)) {
          throw evaluationResultError('Advisory retirement requires a distinct active issue member and selected mutation');
        }
        ancillaryRetirements.add(id);
        retiredRules.add(id);
      }
      operations.set(key, operation);
      operatedGroups.add(key);
    }
    for (const [key, disposition] of members) {
      if (key.startsWith('group:') && !operations.has(key) && !['keep', 'review'].includes(disposition)) {
        throw evaluationResultError('Every changed group member requires its complete advisory operation');
      }
      if (key.startsWith('rule:') && disposition !== 'keep' && !(disposition === 'retire' && ancillaryRetirements.has(Number(key.slice(5))))) {
        throw evaluationResultError('Existing rule members require kept wording or an explicit ancillary retirement');
      }
    }
    const wordingFields = ['status', 'source', 'text', 'rationale'];
    requireSourceObject(issue.wording, wordingFields, wordingFields, 'Issue wording');
    requireSourceText(issue.wording.rationale, 'Issue wording rationale');
    if (issue.wording.status === 'unresolved') {
      if (issue.wording.source !== null || issue.wording.text !== null || protectedMembers.length === 1) {
        throw evaluationResultError('Unresolved wording cannot select text or replace single protected canonical wording');
      }
    } else {
      if (!['canonical', 'selected'].includes(issue.wording.status) || protectedMembers.length > 1) throw evaluationResultError('Issue wording status is invalid for protected integrity');
      const key = adjudicationSubjectKey(issue.wording.source);
      requireSourceText(issue.wording.text, 'Selected issue wording');
      if (!members.has(key)) throw evaluationResultError('Selected wording requires an issue member owner');
      const operation = operations.get(key);
      if (protectedMembers.length === 1) {
        if (issue.wording.status !== 'canonical' || key !== anchorKey || issue.wording.text !== subjects.get(key).text) {
          throw evaluationResultError('Single protected wording must remain exact and canonical');
        }
      } else if (issue.wording.status !== 'selected' ||
        (operation ? !['add', 'update', 'restore'].includes(operation.action) || operation.proposedText !== issue.wording.text :
          members.get(key) !== 'keep' || issue.wording.text !== subjects.get(key).text)) {
        throw evaluationResultError('Selected wording must match its kept owner or complete selected mutation');
      }
    }
    if (protectedMembers.length > 1 && issue.wording.status !== 'unresolved') throw evaluationResultError('Protected integrity requires unresolved wording');
  }
  if (covered.size !== issueComponents.reduce((count, component) => count + component.relationships.length, 0)) {
    throw evaluationResultError('Every issue relationship requires exactly one grouped issue');
  }
  return { relationships: expected, decisions };
}
