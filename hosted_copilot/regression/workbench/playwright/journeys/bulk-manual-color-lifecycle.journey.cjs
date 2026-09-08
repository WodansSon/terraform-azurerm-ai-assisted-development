const { openWorkbench, getCssTokenColor } = require("../helpers/workbench.cjs");

const behaviorIds = [
  "WB-UX-OWNERSHIP-001",
  "WB-UX-OWNERSHIP-002",
  "WB-UX-OWNERSHIP-003",
  "WB-UX-OWNERSHIP-004"
];

async function inspectCandidate(page, candidateKey) {
  return page.evaluate((key) => {
    const candidate = state.candidates.find((item) => item.key === key);
    const decision = getDecision(candidate);
    const row = document.querySelector(`[data-candidate-key="${key}"]`);
    const category = row.closest("details.candidate-category");
    const source = row.closest("details.candidate-source-root");
    const inspectNode = (node, labelSelector, iconSelector) => {
      const summary = node.querySelector(":scope > summary");
      const label = summary.querySelector(labelSelector);
      const icon = summary.querySelector(iconSelector);
      return {
        classes: node.className,
        color: getComputedStyle(label).color,
        iconColor: getComputedStyle(icon).color,
        iconHidden: icon.hasAttribute("hidden"),
        description: summary.querySelector(".candidate-decoration-description").textContent
      };
    };
    const leafIcon = row.querySelector(".candidate-decoration-icon");
    return {
      decision: {
        action: decision.action,
        inPlan: decision.inPlan,
        source: decision.planMembershipSource,
        bulkOperationId: decision.bulkOperationId,
        rationale: decision.rationale
      },
      operationOwnsCandidate: state.session.bulkOperations.some((operation) => operation.candidateKeys.includes(key)),
      bulkUndoDisabled: elements["bulk-undo"].disabled,
      leaf: {
        classes: row.className,
        color: getComputedStyle(row.querySelector(".candidate-tree-copy strong")).color,
        iconColor: getComputedStyle(leafIcon).color,
        iconHidden: leafIcon.hasAttribute("hidden"),
        description: row.querySelector(".candidate-decoration-description").textContent
      },
      category: inspectNode(category, ".candidate-parent-label > strong", ".candidate-parent-decoration-icon"),
      source: inspectNode(source, ".source-summary-label > strong", ".candidate-parent-decoration-icon")
    };
  }, candidateKey);
}

function hierarchyMatches(snapshot, status, color) {
  const className = status === "ready" ? "ready" : "needs-input";
  return snapshot.leaf.classes.includes(`candidate-decoration-${className}`)
    && snapshot.category.classes.includes(`candidate-aggregate-${className}`)
    && snapshot.source.classes.includes(`candidate-aggregate-${className}`)
    && [snapshot.leaf, snapshot.category, snapshot.source].every((item) => item.color === color && item.iconColor === color && !item.iconHidden);
}

async function run({ page, baseUrl, assert, playback }) {
  await openWorkbench(page, baseUrl);
  const sessionSnapshot = await page.evaluate(() => structuredClone(state.session));
  const addedColor = await getCssTokenColor(page, "--added-resource");
  const modifiedColor = await getCssTokenColor(page, "--modified-resource");
  const accentColor = await getCssTokenColor(page, "--accent-bright");

  try {
    const candidate = await page.evaluate(() => {
      const item = getBulkActionCandidates("add").find((candidate) => candidate.sourceType === "interactive");
      return { key: item.key, id: item.id };
    });
    await page.locator("#search-input").fill(candidate.id);
    const row = page.locator(`[data-candidate-key="${candidate.key}"]`);

    await page.locator("#bulk-actions > summary").click();
    await page.locator('#bulk-actions [data-bulk-scope="add"]').click();
    await page.waitForFunction((key) => document.querySelector(`[data-candidate-key="${key}"]`)?.classList.contains("candidate-decoration-ready"), candidate.key);
    await playback.show(page, "Bulk ownership · ready green hierarchy");
    const bulkReady = await inspectCandidate(page, candidate.key);
    assert(bulkReady.decision.source === "bulk" && Boolean(bulkReady.decision.bulkOperationId) && bulkReady.operationOwnsCandidate, "Bulk Add did not record bulk ownership");
    assert(hierarchyMatches(bulkReady, "ready", addedColor), "Bulk Add did not color the leaf, category, and source green");
    assert(bulkReady.leaf.description === "Selected, ready for promotion" && bulkReady.category.description === "1 selected, all ready for promotion" && bulkReady.source.description === "1 selected, all ready for promotion", "Bulk-ready accessible descriptions are incorrect");

    await row.locator(".candidate-tree-copy").click();
    await page.locator('#assessment-panel [data-rule-action="no-change"]').click();
    await page.locator('[data-candidate-pane="candidates"]').click();
    await page.waitForFunction((key) => document.querySelector(`[data-candidate-key="${key}"]`)?.classList.contains("candidate-decoration-needs-input"), candidate.key);
    await playback.show(page, "Manual ownership · incomplete amber hierarchy");
    const manualIncomplete = await inspectCandidate(page, candidate.key);
    assert(manualIncomplete.decision.source === "manual" && manualIncomplete.decision.bulkOperationId === null && !manualIncomplete.operationOwnsCandidate, "Manual edit did not remove bulk ownership");
    assert(manualIncomplete.decision.action === "no-change" && hierarchyMatches(manualIncomplete, "needs-input", modifiedColor), "Manual incomplete decision did not color the full hierarchy amber");
    assert(manualIncomplete.bulkUndoDisabled, "Bulk Undo remained enabled after the candidate moved to Manual ownership");

    await row.locator(".candidate-tree-copy").click();
    await page.locator('#assessment-panel [data-rule-action="add"]').click();
    await page.locator('#assessment-panel [data-decision-field="rationale"]').fill("Maintainer manually confirmed this Add decision after bulk review.");
    await page.locator('[data-candidate-pane="candidates"]').click();
    await page.waitForFunction((key) => document.querySelector(`[data-candidate-key="${key}"]`)?.classList.contains("candidate-decoration-ready"), candidate.key);
    await playback.show(page, "Manual ownership · completed green hierarchy");
    const manualReady = await inspectCandidate(page, candidate.key);
    assert(manualReady.decision.source === "manual" && manualReady.decision.action === "add" && manualReady.decision.rationale.startsWith("Maintainer manually confirmed"), "Completed decision did not retain Manual ownership and rationale");
    assert(hierarchyMatches(manualReady, "ready", addedColor), "Completed Manual decision did not return the full hierarchy to green");

    await row.locator("[data-decision-key]").uncheck();
    await page.waitForFunction((key) => !document.querySelector(`[data-candidate-key="${key}"]`)?.classList.contains("candidate-decoration-ready"), candidate.key);
    await playback.show(page, "Manual ownership · unselected neutral hierarchy");
    const unselected = await inspectCandidate(page, candidate.key);
    assert(!unselected.decision.inPlan && unselected.decision.source === "none" && unselected.decision.bulkOperationId === null, "Unselect did not remove only plan membership");
    assert(unselected.decision.action === "add" && unselected.decision.rationale.startsWith("Maintainer manually confirmed"), "Unselect did not preserve the Manual action and rationale");
    assert(unselected.leaf.color === accentColor && unselected.leaf.iconHidden && !unselected.leaf.description, "Unselected leaf did not return to neutral blue");
    assert(!unselected.category.classes.includes("candidate-aggregate-") && !unselected.source.classes.includes("candidate-aggregate-"), "Unselected ancestors retained aggregate decoration");
  } finally {
    await page.evaluate(async (snapshot) => {
      state.session = snapshot;
      await persistSession();
      renderCandidateList();
      renderBulkSelectionOutputs();
    }, sessionSnapshot);
  }
}

module.exports = { name: "bulk to manual color lifecycle", behaviorIds, viewport: { width: 1180, height: 900 }, run };
