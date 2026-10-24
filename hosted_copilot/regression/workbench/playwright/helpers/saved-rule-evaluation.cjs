const { createHash } = require("node:crypto");

function readSavedRuleRequest(route) {
  return JSON.parse(Buffer.from(route.request().postDataJSON().payloadBase64, "base64").toString("utf8"));
}

function createSavedRuleEvaluation(route, { candidate, comparisonCandidates = [], relatedRule, relatedCandidateKeys = [], additionalRelatedRules = [], grouped = false, scopeReview, assessmentOverrides = {}, unchanged = false, originalRuleIssues }) {
  const request = readSavedRuleRequest(route);
  const text = Buffer.from(request.ruleTextBase64, "base64").toString("utf8");
  const rootId = candidate.catalogMapping.hostedRuleId || candidate.recommendation.hostedId;
  const related = [...(relatedRule ? [{ rule: relatedRule, candidateKeys: relatedCandidateKeys }] : []), ...additionalRelatedRules];
  if (grouped && !related.length) throw new Error("A grouped saved-rule fixture requires related Hosted rules");
  const candidateKeys = new Set([candidate.key, ...related.flatMap((entry) => entry.candidateKeys)]);
  const coveredProposals = request.proposals.filter((proposal) => candidateKeys.has(proposal.candidateKey)).map((proposal) => ({
    candidateKey: proposal.candidateKey,
    sourceHash: proposal.sourceHash,
    action: proposal.action,
    inPlan: proposal.inPlan,
    proposedText: Buffer.from(proposal.proposedTextBase64, "base64").toString("utf8"),
    retireHostedRuleIds: proposal.retireHostedRuleIds
  }));
  const baseline = candidate.recommendation.ruleText;
  const assessmentProposals = coveredProposals.filter((proposal) => {
    if (proposal.candidateKey === candidate.key) return true;
    const owner = comparisonCandidates.find((item) => item.key === proposal.candidateKey);
    if (!owner) throw new Error("Saved-rule fixtures require the actual baseline for every comparison candidate");
    return proposal.proposedText.replace(/\r\n/g, "\n") !== owner.recommendation.ruleText.replace(/\r\n/g, "\n");
  });
  const issues = grouped ? [{
    id: `relationship:${rootId}:saved-fixture`,
    classification: "overlap", label: "Overlap", title: "Saved edit fixture group",
    bannerTitle: "Saved Edit Requires Grouped Review", bannerMessage: "The adjudicator supplies one complete grouped recommendation.",
    blocking: false, ruleIds: [rootId, ...related.map((entry) => entry.rule.id)], protectedRuleIds: [], candidateKeys: [...candidateKeys],
    rules: [
      { id: rootId, status: candidate.catalogMapping.state === "active" ? "active" : "proposed", disposition: candidate.catalogMapping.state === "active" ? "replace" : "promote", text, candidateKeys: [candidate.key] },
      ...related.map(({ rule, candidateKeys: keys }) => ({ id: rule.id, status: "active", disposition: "keep", text: rule.text, candidateKeys: keys }))
    ],
    relationships: related.map(({ rule }) => ({ sourceRuleId: rootId, relatedRuleId: rule.id, relationship: "partial-overlap", kind: "overlap", rationale: "The adjudicator retains this material fixture relationship.", candidateKey: candidate.key })),
    assessmentSummary: "The complete baseline preserves the independent existing obligation.",
    wording: { status: "selected", label: "Suggested Consolidated Wording", presentation: "section", text: baseline, sourceRuleId: rootId },
    recommendedMaintainerAction: {
      summary: "Use the complete baseline and keep the other rule active.",
      operations: [{ candidateKey: candidate.key, ruleId: rootId, action: candidate.catalogMapping.state === "active" ? "update" : "add", proposedText: baseline, retireHostedRuleIds: [] }]
    }
  }] : [];
  const result = {
    schemaVersion: 4, candidateKey: request.candidateKey, requestId: request.requestId,
    ruleTextSha256: createHash("sha256").update(text).digest("hex"),
    authoritySha256: request.authoritySha256, evaluationContextSha256: createHash("sha256").update(JSON.stringify(request.proposals)).digest("hex"),
    scopeReview: scopeReview || {
      disposition: "within-scope", ownerRuleId: null, baselineQuote: baseline, proposalQuote: text,
      rationale: "The fixture preserves the complete baseline scope.",
      wordingStatus: "acceptable", wordingRationale: "The complete fixture wording expresses an enforceable rule."
    },
    affectedRuleIds: [rootId, ...related.map((entry) => entry.rule.id)],
    coveredProposals,
    assessments: assessmentProposals.map((proposal) => ({
      candidateKey: proposal.candidateKey,
      ruleTextSha256: createHash("sha256").update(proposal.proposedText).digest("hex"),
      summary: "The complete saved wording is reassessed.",
      impactDescription: "The fixture reassesses the current saved proposal.",
      hostedApplicable: true,
      applicabilityRationale: "The saved obligation is observable in a Hosted review.",
      selectionFactors: { severity: 5, frequency: 4, breadth: 3, hostedDetectability: 5, evidenceStrength: 5, falsePositiveRisk: 0, redundancy: 1 },
      selectionRationale: "The refreshed assessment evaluates the complete saved wording and its current source evidence.",
      existingCoverage: { score: 1, rationale: "Existing Hosted rules supply limited coverage of this saved proposal." },
      relatedHostedCoverage: related.map(({ rule }) => ({ hostedRuleId: rule.id, relationship: "related", rationale: "The refreshed fixture identifies a distinct existing obligation." })),
      recommendation: proposal.candidateKey === candidate.key ? candidate.catalogMapping.state === "active" ? "update" : candidate.catalogMapping.state === "retired" ? "defer" : "add" : proposal.action,
      ...(proposal.candidateKey === candidate.key ? assessmentOverrides : {})
    })),
    ruleIssues: {
      $schema: "workbench-rule-issues-v4.schema.json", schemaVersion: 4, kind: "hosted-rule-workbench-rule-issues",
      generatedAt: new Date().toISOString(), readOnly: true, sourceFiles: request.sourceFiles, issues
    }
  };
  if (unchanged) {
    if (!originalRuleIssues || grouped || related.length) throw new Error("An unchanged saved-rule fixture requires the original Rule Issues and no newly evaluated relationships");
    result.evaluationMode = "unchanged";
    result.assessments = [];
    result.ruleIssues = originalRuleIssues;
  }
  return result;
}

module.exports = { readSavedRuleRequest, createSavedRuleEvaluation };
