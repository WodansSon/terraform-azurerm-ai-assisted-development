const { openWorkbench } = require("../helpers/workbench.cjs");

const behaviorIds = [
  "WB-UX-PROTECTED-001",
  "WB-UX-PROTECTED-002",
  "WB-UX-PROTECTED-003"
];

async function settle(page) {
  await page.evaluate(() => new Promise((resolve) => requestAnimationFrame(() => requestAnimationFrame(resolve))));
}

async function run({ page, baseUrl, assert, playback }) {
  await openWorkbench(page, baseUrl);
  await playback.show(page, "Protected rule hierarchy and details");

  const setup = await page.evaluate(() => {
    const protectedOnlyCount = document.querySelector('.hierarchical-view-row[data-node-id="candidate:source:overrides"] .count-badge')?.textContent.trim();
    const candidate = state.assessedCandidates.find((item) => !item.assessment.hostedApplicable);
    state.session.applicabilityOverrides[candidate.key] = {
      state: "provisional",
      sourceContentSha256: candidate.hash,
      originalHostedApplicable: false,
      effectiveHostedApplicable: true,
      rationale: "Protected rule hierarchy regression override.",
      recordedAt: new Date().toISOString(),
      recordedBy: { type: "github-cli", login: "fixture-codeowner" }
    };
    refreshEffectiveCandidates();
    renderCandidateList();
    const protectedRule = state.protectedRules[0];
    const leaf = candidateHierarchicalView.model.nodesById.get(`candidate:protected-leaf:${protectedRule.id}`);
    return {
      combinedCount: document.querySelector('.hierarchical-view-row[data-node-id="candidate:source:overrides"] .count-badge')?.textContent.trim(),
      planCount: getPlanCandidates().length,
      protectedOnlyCount,
      protectedRule,
      path: [leaf.parent.parent.parent, leaf.parent.parent, leaf.parent, leaf].map((node) => ({ id: node.id, depth: node.depth, kind: node.kind }))
    };
  });

  assert(setup.protectedRule.id === "IMPL-WF-000" && setup.protectedRule.status === "protected", "protected catalog projection is missing or mutable");
  assert(setup.protectedOnlyCount === "1 Override" && setup.combinedCount === "2 Overrides", "Overrides count does not include protected rules with correct singular and plural labels");
  assert(setup.path.map((node) => node.depth).join("|") === "0|1|2|3", "protected rule does not use the existing four-level candidate hierarchy");
  assert(setup.path[0].id === "candidate:source:overrides" && setup.path[1].id === "candidate:protected-folder:implementation", "protected rule is not a category child of Overrides");

  await page.locator(`#candidate-list [data-node-id="${setup.path[0].id}"]`).click();
  await page.locator(`#candidate-list [data-node-id="${setup.path[1].id}"]`).click();
  const row = page.locator('[data-protected-rule-id="IMPL-WF-000"]');
  await row.waitFor({ state: "visible" });

  const rowState = await row.evaluate((node) => ({
    hasCheckbox: Boolean(node.querySelector('input[type="checkbox"]')),
    icon: node.querySelector("use")?.getAttribute("href"),
    state: node.querySelector(".candidate-lifecycle")?.textContent.trim(),
    status: node.querySelector(".catalog-status")?.textContent.trim(),
    impact: node.querySelector(".tree-impact")?.textContent.trim(),
    tokens: node.querySelector(".tree-cost")?.textContent.trim(),
    recommendation: node.querySelector(".recommendation-badge")?.textContent.trim(),
    colors: [".candidate-lifecycle", ".catalog-status", ".recommendation-badge"].map((selector) => getComputedStyle(node.querySelector(selector)).backgroundColor)
  }));
  assert(!rowState.hasCheckbox && rowState.icon?.endsWith("#codicon-lock"), "protected rule does not replace plan selection with a lock");
  assert(rowState.state === "Required" && rowState.status === "Protected" && rowState.recommendation === "Immutable", "protected rule pills do not expose required protected immutable semantics");
  assert(rowState.impact === "100" && Number(rowState.tokens) === setup.protectedRule.guardedTokens, "protected rule impact or computed token usage is incorrect");
  assert(new Set(rowState.colors).size === 3, "protected rule semantic pills do not use distinct colors");

  const stickyState = await page.evaluate(async (path) => {
    const scroller = document.querySelector("#candidate-list");
    const leaf = candidateHierarchicalView.model.nodesById.get(path[3].id);
    scroller.scrollTop = Math.max(0, leaf.layoutTop - 120);
    await new Promise((resolve) => requestAnimationFrame(() => requestAnimationFrame(resolve)));
    return [...document.querySelectorAll("#candidate-sticky-stack [data-node-id]")]
      .filter((row) => !row.hidden)
      .map((row) => row.dataset.nodeId);
  }, setup.path);
  assert(stickyState.join("|") === setup.path.slice(0, 3).map((node) => node.id).join("|"), "protected rule does not preserve Overrides category and header sticky context");

  await row.click();
  await settle(page);
  const details = await page.locator("#assessment-panel").evaluate((panel) => ({
    title: panel.querySelector(".detail-rule-title")?.textContent.trim(),
    badges: [...panel.querySelectorAll(".assessment-title-statuses > span")].map((badge) => badge.textContent.trim()),
    hasRuleActions: Boolean(panel.querySelector(".rule-actions")),
    protection: panel.querySelector(".protected-rule-notice strong")?.textContent.trim(),
    source: panel.querySelector(".section-block .subcontext-container")?.textContent.trim(),
    metrics: [...panel.querySelectorAll(".protected-rule-score-strip strong")].map((metric) => metric.textContent.trim())
  }));
  assert(details.title === setup.protectedRule.title && details.badges.join("|") === "Required|Protected", "protected rule details lost catalog identity or status");
  assert(!details.hasRuleActions && details.protection === setup.protectedRule.protectionReason, "protected rule details expose mutation actions or lose protection rationale");
  assert(details.source === setup.protectedRule.sourcePath && details.metrics.join("|") === `100|${setup.protectedRule.guardedTokens}|Immutable`, "protected rule details lose authored source or immutable metrics");

  const finalPlanCount = await page.evaluate(() => getPlanCandidates().length);
  assert(finalPlanCount === setup.planCount, "opening a protected rule changes Promotion Plan membership");
}

module.exports = { name: "protected rules", behaviorIds, viewport: { width: 768, height: 900 }, run };
