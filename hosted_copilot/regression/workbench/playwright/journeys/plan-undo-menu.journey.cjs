const { openWorkbench } = require("../helpers/workbench.cjs");

const behaviorIds = [
  "WB-UX-OWNERSHIP-005",
  "WB-UX-OWNERSHIP-006",
  "WB-UX-OWNERSHIP-007",
  "WB-UX-OWNERSHIP-008"
];

async function setupMixedPlan(page) {
  return page.evaluate(async () => {
    await persistencePromise;
    elements["plan-undo-menu"].removeAttribute("open");
    state.session.decisions = {};
    state.session.applicabilityOverrides = {};
    state.session.bulkOperations = [];
    refreshEffectiveCandidates();
    const actionable = state.candidates.filter((candidate) => {
      const assessment = getAssessment(candidate, getDecision(candidate));
      return assessment && ["add", "update"].includes(assessment.recommendation);
    });
    const manualCandidate = actionable[0];
    const bulkCandidate = actionable[1];
    const unrelatedCandidate = state.candidates.find((candidate) => ![manualCandidate.key, bulkCandidate.key].includes(candidate.key));
    const overrideCandidate = getActiveExcludedCandidates()[0];
    if (!manualCandidate || !bulkCandidate || !overrideCandidate || !unrelatedCandidate) throw new Error("Mixed Plan Undo fixtures are unavailable");
    const storeDecision = (candidate, changes) => {
      const { assessment, ...base } = getDecision(candidate);
      state.session.decisions[candidate.key] = { ...base, ...changes, sourceHash: candidate.hash, updatedAt: toUtcTimestamp() };
    };
    const manualAssessment = getAssessment(manualCandidate, getDecision(manualCandidate));
    storeDecision(manualCandidate, { action: manualAssessment.recommendation, rationale: "Manual Plan Undo fixture.", ...createPlanMembership("manual") });
    const bulkAssessment = getAssessment(bulkCandidate, getDecision(bulkCandidate));
    const bulkOperationId = crypto.randomUUID();
    state.session.bulkOperations.push({ id: bulkOperationId, createdAt: toUtcTimestamp(), action: bulkAssessment.recommendation, candidateKeys: [bulkCandidate.key] });
    storeDecision(bulkCandidate, { action: bulkAssessment.recommendation, rationale: "Bulk Plan Undo fixture.", ...createPlanMembership("bulk", bulkOperationId) });
    state.session.applicabilityOverrides[overrideCandidate.key] = {
      state: "provisional",
      sourceContentSha256: overrideCandidate.hash,
      originalHostedApplicable: false,
      effectiveHostedApplicable: true,
      rationale: "Override Plan Undo fixture.",
      recordedAt: toUtcTimestamp(),
      recordedBy: { type: "github-cli", login: "fixture-codeowner" }
    };
    storeDecision(overrideCandidate, { ...createPlanMembership("override") });
    storeDecision(unrelatedCandidate, { action: "no-change", rationale: "Unrelated non-plan fixture.", ...createPlanMembership("none") });
    refreshEffectiveCandidates();
    renderAll();
    switchView("plan");
    return {
      manualKey: manualCandidate.key,
      bulkKey: bulkCandidate.key,
      overrideKey: overrideCandidate.key,
      unrelatedKey: unrelatedCandidate.key,
      unrelatedDecision: structuredClone(state.session.decisions[unrelatedCandidate.key])
    };
  });
}

async function inspectPlan(page, keys) {
  return page.evaluate(async ({ keys }) => {
    await persistencePromise;
    return {
      counts: Object.fromEntries(["all", "manual", "bulk", "override"].map((scope) => [scope, getPlanUndoCandidates(scope).length])),
      rowCount: document.querySelectorAll("[data-plan-row]").length,
      menuOpen: elements["plan-undo-menu"].open,
      triggerDisabled: elements["plan-undo-trigger"].getAttribute("aria-disabled"),
      options: [...elements["plan-undo-menu"].querySelectorAll("[data-plan-undo-scope]")].map((button) => ({ scope: button.dataset.planUndoScope, disabled: button.disabled, cursor: getComputedStyle(button).cursor })),
      decisions: Object.fromEntries(Object.entries(keys).filter(([name]) => name.endsWith("Key")).map(([name, key]) => [name, Boolean(state.session.decisions[key])])),
      overridePresent: Boolean(state.session.applicabilityOverrides[keys.overrideKey]),
      unrelatedPreserved: JSON.stringify(state.session.decisions[keys.unrelatedKey]) === JSON.stringify(keys.unrelatedDecision)
    };
  }, { keys });
}

async function openUndoMenu(page, assert) {
  assert(await page.locator("#plan-undo-menu").evaluate((menu) => !menu.open), "Plan Undo scenario did not start with a closed menu");
  await page.locator("#plan-undo-trigger").click();
  assert(await page.locator("#plan-undo-menu [role='menu']").isVisible(), "Plan Undo trigger did not reveal the menu options");
}

async function run({ page, baseUrl, assert, playback }) {
  await openWorkbench(page, baseUrl);
  const sessionSnapshot = await page.evaluate(() => structuredClone(state.session));
  try {
    let keys = await setupMixedPlan(page);
    await playback.show(page, "Plan Undo menu · fixed mixed-source scopes");
    await openUndoMenu(page, assert);
    let stateSnapshot = await inspectPlan(page, keys);
    assert(JSON.stringify(stateSnapshot.counts) === JSON.stringify({ all: 3, manual: 1, bulk: 1, override: 1 }), `Mixed Plan Undo counts are incorrect: ${JSON.stringify(stateSnapshot.counts)}`);
    assert(stateSnapshot.options.map((option) => option.scope).join(",") === "all,manual,bulk,override" && stateSnapshot.options.every((option) => !option.disabled), "Plan Undo menu does not expose four fixed enabled mixed-source actions");

    await page.locator('[data-plan-undo-scope="bulk"]').click();
    stateSnapshot = await inspectPlan(page, keys);
    assert(!stateSnapshot.menuOpen, "Undo Bulk Items did not close the menu");
    assert(stateSnapshot.counts.bulk === 0 && stateSnapshot.counts.manual === 1 && stateSnapshot.counts.override === 1, "Undo Bulk Items changed another ownership scope");
    assert(!stateSnapshot.decisions.bulkKey && stateSnapshot.decisions.manualKey && stateSnapshot.decisions.overrideKey && stateSnapshot.unrelatedPreserved, "Undo Bulk Items removed the wrong decision state");
    await openUndoMenu(page, assert);
    const disabledBulk = await page.locator('[data-plan-undo-scope="bulk"]').evaluate((button) => ({ disabled: button.disabled, cursor: getComputedStyle(button).cursor }));
    assert(disabledBulk.disabled && disabledBulk.cursor === "default", "Empty Undo Bulk Items did not remain visible with the default disabled cursor");

    keys = await setupMixedPlan(page);
    await openUndoMenu(page, assert);
    await page.locator('[data-plan-undo-scope="override"]').click();
    stateSnapshot = await inspectPlan(page, keys);
    assert(!stateSnapshot.menuOpen, "Undo Override Items did not close the menu");
    assert(stateSnapshot.counts.override === 0 && stateSnapshot.counts.manual === 1 && stateSnapshot.counts.bulk === 1, "Undo Override Items changed another ownership scope");
    assert(!stateSnapshot.decisions.overrideKey && !stateSnapshot.overridePresent && stateSnapshot.unrelatedPreserved, "Undo Override Items did not remove its decision and override record");

    keys = await setupMixedPlan(page);
    await openUndoMenu(page, assert);
    await page.locator('[data-plan-undo-scope="manual"]').click();
    stateSnapshot = await inspectPlan(page, keys);
    assert(!stateSnapshot.menuOpen, "Undo Manual Items did not close the menu");
    assert(stateSnapshot.counts.manual === 0 && stateSnapshot.counts.bulk === 1 && stateSnapshot.counts.override === 1, "Undo Manual Items changed another ownership scope");
    assert(!stateSnapshot.decisions.manualKey && stateSnapshot.decisions.bulkKey && stateSnapshot.decisions.overrideKey && stateSnapshot.unrelatedPreserved, "Undo Manual Items removed the wrong decision state");

    keys = await setupMixedPlan(page);
    await openUndoMenu(page, assert);
    await page.locator('[data-plan-undo-scope="all"]').click();
    stateSnapshot = await inspectPlan(page, keys);
    assert(!stateSnapshot.menuOpen, "Undo All Items did not close the menu");
    assert(stateSnapshot.rowCount === 0 && stateSnapshot.counts.all === 0 && stateSnapshot.triggerDisabled === "true", "Undo All Items did not empty and disable the Promotion Plan");
    assert(!stateSnapshot.decisions.manualKey && !stateSnapshot.decisions.bulkKey && !stateSnapshot.decisions.overrideKey && !stateSnapshot.overridePresent && stateSnapshot.unrelatedPreserved, "Undo All Items did not atomically reset only plan-owned state");
  } finally {
    await page.evaluate(async (snapshot) => {
      state.session = snapshot;
      refreshEffectiveCandidates();
      await persistSession();
      renderAll();
    }, sessionSnapshot).catch(() => {});
  }
}

module.exports = { name: "plan undo menu", behaviorIds, viewport: { width: 1180, height: 900 }, run };
