const { openWorkbench, getCssTokenColor } = require("../helpers/workbench.cjs");

const behaviorIds = [
  "WB-UX-TREE-001",
  "WB-UX-TREE-002",
  "WB-UX-TREE-003",
  "WB-UX-TREE-004",
  "WB-UX-TREE-005"
];

async function snapshotDecoration(page, key) {
  return page.evaluate((candidateKey) => {
    const row = document.querySelector(`[data-candidate-key="${candidateKey}"]`);
    const category = row.closest("details.candidate-category");
    const source = row.closest("details.candidate-source-root");
    const inspectParent = (disclosure) => {
      const summary = disclosure.querySelector(":scope > summary");
      const label = summary.querySelector(".candidate-parent-label, .source-summary-label");
      const icon = summary.querySelector(".candidate-parent-decoration-icon");
      const count = summary.querySelector(".count-badge");
      return {
        open: disclosure.open,
        classes: disclosure.className,
        color: getComputedStyle(summary.querySelector("strong")).color,
        description: summary.querySelector(".candidate-decoration-description").textContent,
        iconHidden: icon.hasAttribute("hidden"),
        titleEdgeDelta: label.getBoundingClientRect().right - icon.getBoundingClientRect().right,
        iconToCountGap: count.getBoundingClientRect().left - icon.getBoundingClientRect().right
      };
    };
    const copy = row.querySelector(".candidate-tree-copy");
    const icon = row.querySelector(".candidate-decoration-icon");
    return {
      leaf: {
        classes: row.className,
        color: getComputedStyle(copy.querySelector("strong")).color,
        description: row.querySelector(".candidate-decoration-description").textContent,
        iconHidden: icon.hasAttribute("hidden"),
        iconHref: icon.querySelector("use").getAttribute("href"),
        trailingDelta: copy.getBoundingClientRect().right - icon.getBoundingClientRect().right
      },
      category: inspectParent(category),
      source: inspectParent(source)
    };
  }, key);
}

async function run({ page, baseUrl, assert, playback }) {
  await openWorkbench(page, baseUrl);
  await playback.show(page, "Candidate decorations · 768px viewport");
  const accentColor = await getCssTokenColor(page, "--accent-bright");
  const addedColor = await getCssTokenColor(page, "--added-resource");
  const modifiedColor = await getCssTokenColor(page, "--modified-resource");

  const candidate = await page.evaluate(() => {
    const item = getBulkActionCandidates("add").find((candidate) => candidate.sourceType === "interactive");
    return { key: item.key, id: item.id };
  });
  await page.locator("#search-input").fill(candidate.id);
  const row = page.locator(`[data-candidate-key="${candidate.key}"]`);
  const source = row.locator('xpath=ancestor::details[contains(@class,"candidate-source-root")]');
  if (!(await source.evaluate((node) => node.open))) await source.locator(":scope > summary").click();
  const category = row.locator('xpath=ancestor::details[contains(@class,"candidate-category")]');
  if (!(await category.evaluate((node) => node.open))) await category.locator(":scope > summary").click();
  const key = candidate.key;
  const rowHandle = await row.evaluateHandle((node) => node);

  const untouched = await snapshotDecoration(page, key);
  assert(untouched.leaf.color === accentColor && untouched.leaf.iconHidden && !untouched.leaf.description, "untouched leaf is not neutral blue");
  assert(!untouched.category.classes.includes("candidate-aggregate-") && !untouched.source.classes.includes("candidate-aggregate-"), "untouched ancestors are decorated");

  await row.locator("[data-decision-key]").click();
  await page.waitForFunction((candidateKey) => document.querySelector(`[data-candidate-key="${candidateKey}"]`)?.classList.contains("candidate-decoration-needs-input"), key);
  const needsInput = await snapshotDecoration(page, key);
  assert(needsInput.leaf.color === modifiedColor && needsInput.leaf.description === "Selected, needs input before promotion", "needs-input leaf decoration is incorrect");
  assert(needsInput.category.color === modifiedColor && needsInput.source.color === modifiedColor, "needs-input state did not propagate to ancestors");
  assert(needsInput.category.description === "1 selected, 1 needs input" && needsInput.source.description === "1 selected, 1 needs input", "singular needs-input descriptions are incorrect");

  await row.locator(".candidate-tree-copy").click();
  await page.locator('#assessment-panel [data-rule-action="add"]').click();
  await page.locator('#assessment-panel [data-decision-field="rationale"]').fill("Playwright journey confirms the selected rule is ready for promotion.");
  await page.locator('[data-candidate-pane="candidates"]').click();
  await page.waitForFunction((candidateKey) => document.querySelector(`[data-candidate-key="${candidateKey}"]`)?.classList.contains("candidate-decoration-ready"), key);
  const ready = await snapshotDecoration(page, key);
  const sameRow = await rowHandle.evaluate((before, candidateKey) => before === document.querySelector(`[data-candidate-key="${candidateKey}"]`), key);
  assert(sameRow, "candidate row was replaced during incremental decoration updates");
  assert(ready.leaf.color === addedColor && ready.leaf.description === "Selected, ready for promotion", "ready leaf decoration is incorrect");
  assert(ready.category.color === addedColor && ready.source.color === addedColor, "ready state did not propagate to ancestors");
  assert(!ready.leaf.iconHidden && ready.leaf.iconHref.endsWith("#codicon-diff-modified"), "ready leaf icon is hidden or incorrect");
  assert(Math.abs(ready.leaf.trailingDelta) < 0.1 && Math.abs(ready.category.titleEdgeDelta) < 0.1 && Math.abs(ready.source.titleEdgeDelta) < 0.1, "decorations are not at title-cell trailing edges");
  assert(Math.abs(ready.category.iconToCountGap - 8) < 0.1 && Math.abs(ready.source.iconToCountGap - 8) < 0.1, "parent decoration spacing changed count geometry");

  await category.locator(":scope > summary").click();
  await source.locator(":scope > summary").click();
  const collapsed = await snapshotDecoration(page, key);
  assert(!collapsed.category.open && !collapsed.source.open && !collapsed.category.iconHidden && !collapsed.source.iconHidden, "collapsed ancestors hide readiness status");
  assert(collapsed.category.description === "1 selected, all ready for promotion" && collapsed.source.description === "1 selected, all ready for promotion", "collapsed ancestor descriptions are incomplete");

  const overrides = await page.evaluate((candidateKey) => {
    const sessionSnapshot = structuredClone(state.session);
    const candidate = state.candidates.find((item) => item.key === candidateKey);
    const assessment = getAssessment(candidate, getDecision(candidate));
    const resolveColor = (token) => {
      const probe = document.createElement("span");
      probe.style.color = `var(${token})`;
      document.body.appendChild(probe);
      const color = getComputedStyle(probe).color;
      probe.remove();
      return color;
    };

    try {
      state.session.applicabilityOverrides[candidate.key] = {
        state: "provisional",
        sourceContentSha256: candidate.hash,
        originalHostedApplicable: false,
        effectiveHostedApplicable: true,
        rationale: "Playwright override decoration probe.",
        recordedAt: new Date().toISOString(),
        recordedBy: { type: "github-cli", login: "fixture-codeowner" }
      };
      state.session.decisions[candidate.key] = { ...defaultDecision(candidate), ...createPlanMembership("override") };
      renderCandidateList();

      const root = document.querySelector("#candidate-list > .candidate-overrides-root");
      const overrideRow = root.querySelector(`[data-candidate-key="${candidate.key}"]`);
      const summary = root.querySelector(":scope > summary");
      const modified = resolveColor("--modified-resource");
      const needsInputValid = summary.dataset.workbenchTooltip === "1 selected, 1 needs input"
        && [summary.querySelector(".candidate-parent-label > strong"), summary.querySelector(".candidate-parent-decoration-icon"), overrideRow.querySelector(".candidate-tree-copy strong"), overrideRow.querySelector(".candidate-decoration-icon")]
          .every((node) => getComputedStyle(node).color === modified);

      state.session.decisions[candidate.key] = {
        ...state.session.decisions[candidate.key],
        action: assessment.recommendation,
        rationale: getBulkDecisionRationale(candidate, assessment.recommendation)
      };
      syncCandidateTreeRows();
      const added = resolveColor("--added-resource");
      const readyValid = summary.dataset.workbenchTooltip === "1 selected, all ready for promotion"
        && [summary.querySelector(".candidate-parent-label > strong"), summary.querySelector(".candidate-parent-decoration-icon"), overrideRow.querySelector(".candidate-tree-copy strong"), overrideRow.querySelector(".candidate-decoration-icon")]
          .every((node) => getComputedStyle(node).color === added);
      return { needsInputValid, readyValid };
    } finally {
      state.session = sessionSnapshot;
      renderCandidateList();
    }
  }, key);
  assert(overrides.needsInputValid, "Overrides root and leaf do not share needs-input color or singular description");
  assert(overrides.readyValid, "Overrides root and leaf do not share ready color");
  assert(await page.locator("#candidate-list > .candidate-overrides-root").count() === 0, "Overrides probe did not restore the candidate tree");
}

module.exports = { name: "candidate decorations", behaviorIds, viewport: { width: 768, height: 900 }, run };
