import { requireSourceObject, requireSourceText } from './WorkbenchSourceRecords.mjs';
import { evaluationResultError } from './WorkbenchEvaluationFailures.mjs';

// Supply established group history only through approved or published catalog bindings, never unaccepted proposals.
export function readPinnedGroupEvidence(connection, catalogId) {
  if (catalogId === null) return [];
  const bindings = connection.all(`SELECT evidence.group_version_id AS groupVersionId, evidence.rule_id AS ruleId,
    member.rule_version_id AS ruleVersionId
    FROM accepted_group_evidence evidence JOIN catalog_members member
      ON member.catalog_id = evidence.catalog_id AND member.rule_id = evidence.rule_id
    WHERE evidence.catalog_id = ? ORDER BY evidence.group_version_id, evidence.rule_id`, [catalogId]);
  if (!bindings.length) return [];
  if (!connection.get('SELECT id FROM approvals WHERE catalog_id = ?', [catalogId]) &&
    !connection.get('SELECT workspace_id FROM workspace_publication WHERE current_catalog_id = ?', [catalogId])) {
    throw evaluationResultError('Group continuity requires approved or verified published catalog evidence');
  }
  const versions = [...new Set(bindings.map(binding => binding.groupVersionId))];
  const identities = new Set();
  return versions.map(groupVersionId => {
    const group = connection.get(`SELECT version.id AS groupVersionId, version.group_id AS groupId, version.revision,
      version.title, version.semantic_summary AS semanticSummary, wording.text AS suggestedWording
      FROM group_versions version JOIN evaluations evaluation ON evaluation.id = version.synthesis_evaluation_id
      JOIN wording_versions wording ON wording.id = version.suggested_wording_id
      WHERE version.id = ? AND evaluation.outcome = 'complete'`, [groupVersionId]);
    if (!group || group.groupId === null || identities.has(group.groupId)) {
      throw evaluationResultError('Pinned catalog group evidence requires one established version per group identity');
    }
    identities.add(group.groupId);
    return { ...group, catalogId,
      catalogBindings: bindings.filter(binding => binding.groupVersionId === groupVersionId)
        .map(({ ruleId, ruleVersionId }) => ({ ruleId, ruleVersionId })),
      members: connection.all(`SELECT member.assessment_result_id AS assessmentResultId, member.member_role AS role,
        member.meaning_coverage_rationale AS coverageRationale, assessment.local_result_key AS localResultKey,
        assessment.source_meaning AS sourceMeaning, source.id AS sourceVersionId, source.source_rule_id AS sourceRuleId,
        source.content_sha256 AS contentSha256, source.captured_text AS sourceContent,
        definition.code AS sourceDefinitionId, rule.external_key AS sourceId
        FROM group_members member JOIN assessment_results assessment ON assessment.id = member.assessment_result_id
        JOIN source_versions source ON source.id = assessment.source_version_id
        JOIN source_rules rule ON rule.id = source.source_rule_id
        JOIN source_definitions definition ON definition.id = rule.definition_id
        WHERE member.group_version_id = ? ORDER BY member.assessment_result_id`, [groupVersionId]).map(member => ({ ...member })),
    };
  });
}

// Validate quoted predecessor correspondence and merge/split survivor rules before allowing stable identities to continue.
export function validateGroupContinuities(connection, input, groups, runId) {
  const priorGroups = new Map(input.priorGroups.map(group => [group.groupVersionId, group]));
  const assessments = new Map(input.assessments.map(assessment => [assessment.assessmentResultId, assessment]));
  const sources = new Map(input.sources.map(source => [source.sourceVersionId, source.content]));
  const claims = new Map();
  const retained = new Set();
  const plans = groups.map(group => {
    const fields = ['kind', 'priorGroupVersionIds', 'retainedGroupVersionId', 'confidence', 'rationale', 'memberMatches'];
    requireSourceObject(group.continuity, fields, fields, 'Group continuity');
    const continuity = group.continuity;
    requireSourceText(continuity.rationale, 'Group continuity rationale');
    if (!['new', 'equivalent', 'material-change', 'split', 'merge', 'unresolved'].includes(continuity.kind) ||
      !['high', 'medium', 'low'].includes(continuity.confidence) ||
      !Array.isArray(continuity.priorGroupVersionIds) || !Array.isArray(continuity.memberMatches) ||
      new Set(continuity.priorGroupVersionIds).size !== continuity.priorGroupVersionIds.length) {
      throw evaluationResultError('Group continuity requires an explicit classification and unique prior versions');
    }
    const priors = continuity.priorGroupVersionIds.map(id => {
      const prior = priorGroups.get(id);
      if (!prior) throw evaluationResultError('Group continuity references evidence outside the pinned catalog');
      return prior;
    });
    const survivor = continuity.retainedGroupVersionId === null ? null : priorGroups.get(continuity.retainedGroupVersionId);
    if (continuity.retainedGroupVersionId !== null && (!survivor || !priors.includes(survivor))) {
      throw evaluationResultError('Group survivor must be one of the explicitly referenced prior versions');
    }
    if ((continuity.kind === 'new' && (priors.length || survivor || continuity.memberMatches.length)) ||
      (['equivalent', 'material-change'].includes(continuity.kind) && (priors.length !== 1 || !survivor)) ||
      (continuity.kind === 'merge' && (priors.length < 2 || !survivor)) ||
      (continuity.kind === 'split' && priors.length !== 1) ||
      (continuity.kind === 'unresolved' && (!priors.length || survivor ||
        group.reviewState !== 'deferred' || group.needsReview !== true))) {
      throw evaluationResultError('Group continuity classification does not match its prior scope or survivor');
    }
    if (!['new', 'unresolved'].includes(continuity.kind) && continuity.confidence !== 'high') {
      throw evaluationResultError('Ambiguous or lower-confidence group continuity must remain unresolved');
    }
    if (survivor) {
      if (retained.has(survivor.groupId) || connection.get(`SELECT version.id FROM group_versions version
        JOIN run_evaluations used ON used.evaluation_id = version.synthesis_evaluation_id
        WHERE used.run_id = ? AND version.group_id = ?`, [runId, survivor.groupId])) {
        throw evaluationResultError('One analysis cannot propose competing revisions for the same group identity');
      }
      retained.add(survivor.groupId);
    }
    if (!Array.isArray(group.members)) throw evaluationResultError('Group continuity requires explicit current members');
    const memberIds = new Set(group.members.map(member => member.assessmentResultId));
    const matchedPriors = new Set();
    const matchedPairs = new Set();
    for (const match of continuity.memberMatches) {
      const fields = ['assessmentResultId', 'priorAssessmentResultId', 'currentQuote', 'priorQuote', 'rationale'];
      requireSourceObject(match, fields, fields, 'Group continuity member match');
      for (const field of ['currentQuote', 'priorQuote', 'rationale']) requireSourceText(match[field], field);
      const current = assessments.get(match.assessmentResultId);
      const prior = priors.find(candidate => candidate.members.some(member => member.assessmentResultId === match.priorAssessmentResultId));
      const priorMember = prior?.members.find(member => member.assessmentResultId === match.priorAssessmentResultId);
      const key = `${match.assessmentResultId}:${match.priorAssessmentResultId}`;
      const meaning = current?.sourceMeaning ?? sources.get(current?.sourceMeaningSourceVersionId);
      if (!memberIds.has(match.assessmentResultId) || !priorMember || matchedPairs.has(key) ||
        !meaning?.includes(match.currentQuote) || !priorMember.sourceMeaning.includes(match.priorQuote)) {
        throw evaluationResultError('Group continuity requires unique member matches grounded in exact supplied meanings');
      }
      matchedPairs.add(key);
      matchedPriors.add(prior.groupVersionId);
    }
    if (priors.some(prior => !matchedPriors.has(prior.groupVersionId))) {
      throw evaluationResultError('Every claimed prior group requires explicit member-meaning evidence');
    }
    if (continuity.kind === 'equivalent' && (continuity.memberMatches.length !== memberIds.size ||
      new Set(continuity.memberMatches.map(match => match.assessmentResultId)).size !== memberIds.size ||
      new Set(continuity.memberMatches.map(match => match.priorAssessmentResultId)).size !== priors[0].members.length)) {
      throw evaluationResultError('Equivalent group continuity requires complete one-to-one member coverage');
    }
    for (const prior of priors) {
      const uses = claims.get(prior.groupVersionId) ?? [];
      uses.push({ kind: continuity.kind, retained: survivor === prior });
      claims.set(prior.groupVersionId, uses);
    }
    return { continuity, priors, groupId: survivor?.groupId ?? null };
  });
  for (const [priorId, uses] of claims) {
    if (uses.some(use => use.kind === 'split')) {
      if (uses.length < 2 || uses.some(use => use.kind !== 'split') || uses.filter(use => use.retained).length !== 1) {
        throw evaluationResultError('A group split requires one continuing survivor and at least one separate successor in the same result');
      }
    } else if (uses.length !== 1) throw evaluationResultError('Group continuity cannot assign one prior version to competing outcomes');
    if (connection.get(`SELECT correspondence.id FROM group_correspondences correspondence
      JOIN group_versions version ON version.id = correspondence.next_group_version_id
      JOIN run_evaluations used ON used.evaluation_id = version.synthesis_evaluation_id
      WHERE used.run_id = ? AND correspondence.prior_group_version_id = ?`, [runId, priorId])) {
      throw evaluationResultError('Group continuity cannot claim a prior version already consumed by this analysis');
    }
  }
  return plans;
}
