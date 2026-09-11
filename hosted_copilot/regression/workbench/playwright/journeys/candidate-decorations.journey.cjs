const { openWorkbench, getCandidateHierarchy, getCssTokenColor } = require("../helpers/workbench.cjs");

const behaviorIds = [
  "WB-UX-TREE-001",
  "WB-UX-TREE-002",
  "WB-UX-TREE-003",
  "WB-UX-TREE-004",
  "WB-UX-TREE-005"
];

async function snapshotDecoration(page, candidateKey) {
  const hierarchy = await getCandidateHierarchy(page, candidateKey);
  return page.evaluate(({ key, hierarchy }) => {
    const row = document.querySelector(`[data-candidate-key="${CSS.escape(key)}"]`);
    const inspectParent = (id) => {
      const parent = document.querySelector(`#candidate-list [data-node-id="${CSS.escape(id)}"]`);
      const label = parent.querySelector(".candidate-parent-label > strong, .source-summary-label > strong");
      const icon = parent.querySelector(".candidate-parent-decoration-icon");
      const count = parent.querySelector(".count-badge");
      const labelOwner = parent.querySelector(".candidate-parent-label, .source-summary-label");
      return {
        expanded: candidateHierarchicalView.model.nodesById.get(id).expanded,
        classes: parent.className,
        color: getComputedStyle(label).color,
        description: parent.querySelector(".candidate-decoration-description").textContent,
        iconHidden: icon.hasAttribute("hidden"),
        titleEdgeDelta: labelOwner.getBoundingClientRect().right - icon.getBoundingClientRect().right,
        iconToCountGap: count.getBoundingClientRect().left - icon.getBoundingClientRect().right
      };
    };
    const copy = row?.querySelector(".candidate-tree-copy");
    const icon = row?.querySelector(".candidate-decoration-icon");
    return {
      leaf: row ? {
        classes: row.className,
        color: getComputedStyle(copy.querySelector("strong")).color,
        description: row.querySelector(".candidate-decoration-description").textContent,
        iconHidden: icon.hasAttribute("hidden"),
        iconHref: icon.querySelector("use").getAttribute("href"),
        trailingDelta: copy.getBoundingClientRect().right - icon.getBoundingClientRect().right
      } : null,
      parents: hierarchy.parentIds.map(inspectParent)
    };
  }, { key: candidateKey, hierarchy });
}

async function clickHierarchyNode(page, nodeId) {
  await page.evaluate((id) => {
    const sticky = document.querySelector(`#candidate-sticky-stack [data-node-id="${CSS.escape(id)}"]`);
    const natural = document.querySelector(`#candidate-list [data-node-id="${CSS.escape(id)}"]`);
    const row = sticky && getComputedStyle(sticky).visibility !== "hidden" ? sticky : natural;
    row.click();
  }, nodeId);
}

async function run({ page, baseUrl, assert, playback }) {
  await openWorkbench(page, baseUrl);
  await playback.show(page, "Candidate decorations · 768px viewport");
  const accentColor = await getCssTokenColor(page, "--accent-bright");
  const addedColor = await getCssTokenColor(page, "--added-resource");
  const modifiedColor = await getCssTokenColor(page, "--modified-resource");

  const noOverridesInitially = await page.evaluate(() => !candidateHierarchicalView.model.nodesById.has("candidate:source:overrides")
    && !document.querySelector('#candidate-list [data-node-id="candidate:source:overrides"]'));
  assert(noOverridesInitially, "an Overrides hierarchy exists without a provisional override");

  const candidate = await page.evaluate(() => {
    const item = getBulkActionCandidates("add").find((candidate) => candidate.sourceType === "interactive");
    return { key: item.key, id: item.id };
  });
  await page.locator("#search-input").fill(candidate.id);
  const row = page.locator(`[data-candidate-key="${candidate.key}"]`);
  const hierarchy = await getCandidateHierarchy(page, candidate.key);
  const rowHandle = await row.evaluateHandle((node) => node);

  const untouched = await snapshotDecoration(page, candidate.key);
  assert(untouched.leaf.color === accentColor && untouched.leaf.iconHidden && !untouched.leaf.description, "untouched leaf is not neutral blue");
  assert(untouched.parents.every((parent) => !parent.classes.includes("candidate-aggregate-")), "untouched ancestors are decorated");

  await row.locator("[data-decision-key]").click();
  await page.waitForFunction((key) => document.querySelector(`[data-candidate-key="${CSS.escape(key)}"]`)?.classList.contains("candidate-decoration-needs-input"), candidate.key);
  const needsInput = await snapshotDecoration(page, candidate.key);
  assert(needsInput.leaf.color === modifiedColor && needsInput.leaf.description === "Selected, needs input before promotion", "needs-input leaf decoration is incorrect");
  assert(needsInput.parents.every((parent) => parent.color === modifiedColor && parent.description === "1 selected, 1 needs input"), "needs-input state did not propagate to ancestors");

  await row.locator(".candidate-tree-copy").click();
  await page.locator('#assessment-panel [data-rule-action="add"]').click();
  await page.locator('#assessment-panel [data-decision-field="rationale"]').fill("Playwright journey confirms the selected rule is ready for promotion.");
  await page.locator('[data-candidate-pane="candidates"]').click();
  await page.waitForFunction((key) => document.querySelector(`[data-candidate-key="${CSS.escape(key)}"]`)?.classList.contains("candidate-decoration-ready"), candidate.key);
  const ready = await snapshotDecoration(page, candidate.key);
  const sameRow = await rowHandle.evaluate((before, key) => before === document.querySelector(`[data-candidate-key="${CSS.escape(key)}"]`), candidate.key);
  assert(sameRow, "candidate row was replaced during incremental decoration updates");
  assert(ready.leaf.color === addedColor && ready.leaf.description === "Selected, ready for promotion", "ready leaf decoration is incorrect");
  assert(ready.parents.every((parent) => parent.color === addedColor && parent.description === "1 selected, all ready for promotion"), "ready state did not propagate to ancestors");
  assert(!ready.leaf.iconHidden && ready.leaf.iconHref.endsWith("#codicon-diff-modified"), "ready leaf icon is hidden or incorrect");
  assert(Math.abs(ready.leaf.trailingDelta) < 0.1 && ready.parents.every((parent) => Math.abs(parent.titleEdgeDelta) < 0.1), "decorations are not at title-cell trailing edges");
  assert(ready.parents.every((parent) => Math.abs(parent.iconToCountGap - 8) < 0.1), "parent decoration spacing changed count geometry");

  await clickHierarchyNode(page, hierarchy.folderId);
  const folderCollapsed = await snapshotDecoration(page, candidate.key);
  const collapsedFolder = folderCollapsed.parents.at(-1);
  assert(folderCollapsed.leaf === null, "collapsed candidate leaf remains painted");
  assert(!collapsedFolder.expanded && !collapsedFolder.iconHidden && collapsedFolder.description === "1 selected, all ready for promotion", "collapsed folder hides or misdescribes readiness status");
  await clickHierarchyNode(page, hierarchy.rootId);
  const rootCollapsed = await page.evaluate((rootId) => {
    const root = document.querySelector(`#candidate-list [data-node-id="${CSS.escape(rootId)}"]`);
    return {
      expanded: candidateHierarchicalView.model.nodesById.get(rootId).expanded,
      iconHidden: root.querySelector(".candidate-parent-decoration-icon").hasAttribute("hidden"),
      description: root.querySelector(".candidate-decoration-description").textContent
    };
  }, hierarchy.rootId);
  assert(!rootCollapsed.expanded && !rootCollapsed.iconHidden && rootCollapsed.description === "1 selected, all ready for promotion", "collapsed source hides or misdescribes readiness status");

  const overrides = await page.evaluate(() => {
    const sessionSnapshot = structuredClone(state.session);
    const candidate = state.assessedCandidates.find((item) => !item.assessment.hostedApplicable) || state.candidates[0];
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
      refreshEffectiveCandidates();
      renderCandidateList();
      revealCandidateInTree(candidate.key);
      const root = document.querySelector('#candidate-list [data-node-id="candidate:source:overrides"]');
      const row = document.querySelector(`[data-candidate-key="${CSS.escape(candidate.key)}"]`);
      const modified = resolveColor("--modified-resource");
      const needsInputValid = root.classList.contains("candidate-aggregate-needs-input")
        && row.classList.contains("candidate-decoration-needs-input")
        && root.querySelector(".count-badge").dataset.workbenchTooltip === "1 selected, 1 needs input"
        && [root.querySelector(".candidate-parent-label > strong"), root.querySelector(".candidate-parent-decoration-icon"), row.querySelector(".candidate-tree-copy strong"), row.querySelector(".candidate-decoration-icon")]
          .every((node) => getComputedStyle(node).color === modified);
      state.session.decisions[candidate.key] = {
        ...state.session.decisions[candidate.key],
        action: getDefaultPlanAction(candidate, assessment.recommendation),
        rationale: "Playwright override is ready for promotion."
      };
      syncCandidateTreeRows();
      const added = resolveColor("--added-resource");
      const readyValid = root.classList.contains("candidate-aggregate-ready")
        && row.classList.contains("candidate-decoration-ready")
        && root.querySelector(".count-badge").dataset.workbenchTooltip === "1 selected, all ready for promotion"
        && [root.querySelector(".candidate-parent-label > strong"), root.querySelector(".candidate-parent-decoration-icon"), row.querySelector(".candidate-tree-copy strong"), row.querySelector(".candidate-decoration-icon")]
          .every((node) => getComputedStyle(node).color === added);
      return { needsInputValid, readyValid };
    } finally {
      state.session = sessionSnapshot;
      refreshEffectiveCandidates();
      renderCandidateList();
    }
  });
  assert(overrides.needsInputValid, "Overrides root and leaf do not share needs-input decoration");
  assert(overrides.readyValid, "Overrides root and leaf do not share ready decoration");
  assert(await page.locator('#candidate-list [data-node-id="candidate:source:overrides"]').count() === 0, "Overrides probe did not restore the candidate tree");
}

module.exports = { name: "candidate decorations", behaviorIds, viewport: { width: 768, height: 900 }, run };
