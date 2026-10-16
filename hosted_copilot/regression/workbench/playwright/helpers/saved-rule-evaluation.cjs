const { createHash } = require("node:crypto");

function readSavedRuleRequest(route) {
  return JSON.parse(Buffer.from(route.request().postDataJSON().payloadBase64, "base64").toString("utf8"));
}

function createSavedRuleEvaluation(route, { candidate, relatedRule, relatedCandidateKeys = [], grouped = false, scopeReview }) {
  const request = readSavedRuleRequest(route);
  const text = Buffer.from(request.ruleTextBase64, "base64").toString("utf8");
  const rootId = candidate.catalogMapping.hostedRuleId || candidate.recommendation.hostedId;
  const candidateKeys = new Set([candidate.key, ...relatedCandidateKeys]);
  const coveredProposals = request.proposals.filter((proposal) => candidateKeys.has(proposal.candidateKey)).map((proposal) => ({
    candidateKey: proposal.candidateKey,
    sourceHash: proposal.sourceHash,
    action: proposal.action,
    inPlan: proposal.inPlan,
    proposedText: Buffer.from(proposal.proposedTextBase64, "base64").toString("utf8"),
    retireHostedRuleIds: proposal.retireHostedRuleIds
  }));
  const baseline = candidate.recommendation.ruleText;
  const issues = grouped ? [{
    id: `relationship:${rootId}:saved-fixture`,
    classification: "overlap", label: "Overlap", title: "Saved edit fixture group",
    bannerTitle: "Saved Edit Requires Grouped Review", bannerMessage: "The adjudicator supplies one complete grouped recommendation.",
    blocking: false, ruleIds: [rootId, relatedRule.id], protectedRuleIds: [], candidateKeys: [...candidateKeys],
    rules: [
      { id: rootId, status: candidate.catalogMapping.state === "active" ? "active" : "proposed", disposition: candidate.catalogMapping.state === "active" ? "replace" : "promote", text, candidateKeys: [candidate.key] },
      { id: relatedRule.id, status: "active", disposition: "keep", text: relatedRule.text, candidateKeys: relatedCandidateKeys }
    ],
    relationships: [{ sourceRuleId: rootId, relatedRuleId: relatedRule.id, relationship: "partial-overlap", kind: "overlap", rationale: "The adjudicator retains this material fixture relationship.", candidateKey: candidate.key }],
    assessmentSummary: "The complete baseline preserves the independent existing obligation.",
    wording: { status: "selected", label: "Suggested Consolidated Wording", presentation: "section", text: baseline, sourceRuleId: rootId },
    recommendedMaintainerAction: {
      summary: "Use the complete baseline and keep the other rule active.",
      operations: [{ candidateKey: candidate.key, ruleId: rootId, action: candidate.catalogMapping.state === "active" ? "update" : "add", proposedText: baseline, retireHostedRuleIds: [] }]
    }
  }] : [];
  return {
    schemaVersion: 2, candidateKey: request.candidateKey, requestId: request.requestId,
    ruleTextSha256: createHash("sha256").update(text).digest("hex"),
    authoritySha256: request.authoritySha256, evaluationContextSha256: createHash("sha256").update(JSON.stringify(request.proposals)).digest("hex"),
    scopeReview: scopeReview || { disposition: "within-scope", ownerRuleId: null, baselineQuote: baseline, proposalQuote: text, rationale: "The fixture preserves the complete baseline scope." },
    affectedRuleIds: [rootId, ...(relatedRule ? [relatedRule.id] : [])],
    coveredProposals,
    ruleIssues: {
      $schema: "workbench-rule-issues-v4.schema.json", schemaVersion: 4, kind: "hosted-rule-workbench-rule-issues",
      generatedAt: new Date().toISOString(), readOnly: true, sourceFiles: request.sourceFiles, issues
    }
  };
}

module.exports = { readSavedRuleRequest, createSavedRuleEvaluation };
