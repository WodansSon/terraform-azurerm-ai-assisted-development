const { openWorkbench } = require("../helpers/workbench.cjs");

const behaviorIds = ["WB-UX-CONSOLIDATION-001"];

async function run({ page, baseUrl, assert }) {
  let relationshipRequests = 0;
  await page.route("**/reconcile-rule", async (route) => { relationshipRequests += 1; await route.abort(); });
  await openWorkbench(page, baseUrl);
  const original = await page.evaluate(() => structuredClone(state.session));
  try {
    const applied = await page.evaluate(async () => {
      const issue = getOpenRuleIssues().find((item) => !item.blocking && getPendingRuleIssueOperations(item).length);
      if (!issue) throw new Error("The published fixture must contain an actionable Rule Issue.");
      const operations = getPendingRuleIssueOperations(issue);
      await stageRuleIssueRecommendation(issue);
      await persistencePromise;
      const stored = await readSession(state.session.id);
      return operations.every((operation) => {
        const candidate = state.assessedCandidates.find((item) => item.key === operation.candidateKey);
        const decision = getDecision(candidate);
        return decision.inPlan && decision.action === operation.action && decision.proposedText === operation.proposedText
          && JSON.stringify(decision.retireHostedRuleIds) === JSON.stringify(getRuleIssueAncillaryRetirements(operation))
          && stored.decisions[candidate.key].proposedText === operation.proposedText;
      }) && isRuleIssueRecommendationStaged(issue);
    });
    assert(applied && relationshipRequests === 0, "Published recommendations were not staged exactly without another AI check");
    const failed = await page.evaluate(async (session) => {
      state.session = structuredClone(session);
      await persistSession();
      const before = JSON.stringify(state.session);
      const storedBefore = JSON.stringify(await readSession(state.session.id));
      const issue = getOpenRuleIssues().find((item) => !item.blocking && getPendingRuleIssueOperations(item).length);
      const open = openDatabase;
      openDatabase = async () => { throw new Error("Synthetic persistence failure."); };
      try { await stageRuleIssueRecommendation(issue); }
      finally { openDatabase = open; }
      return JSON.stringify(state.session) === before && JSON.stringify(await readSession(state.session.id)) === storedBefore;
    }, original);
    assert(failed, "Failed recommendation persistence partially changed the draft");
  } finally {
    await page.evaluate(async (session) => {
      state.session = session;
      await persistSession();
    }, original);
  }
  return { behaviorIds };
}

module.exports = { behaviorIds, run };
