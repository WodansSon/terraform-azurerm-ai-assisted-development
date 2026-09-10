const { openWorkbench, getCssTokenColor } = require("../helpers/workbench.cjs");

const behaviorIds = [
  "WB-UX-TREE-001",
  "WB-UX-TREE-002",
  "WB-UX-TREE-003",
  "WB-UX-TREE-004",
  "WB-UX-TREE-005"
];

async function clickStickyFolder(page, owner) {
  const target = await owner.evaluate((node) => ({
    depth: node.dataset.treeDepth,
    label: node.querySelector(":scope > summary strong").textContent.trim()
  }));
  const folders = page.locator(`#candidate-sticky-stack > .candidate-sticky-layer.active > details[data-sticky-depth="${target.depth}"]`);
  for (let index = 0; index < await folders.count(); index += 1) {
    if ((await folders.nth(index).locator(":scope > summary strong").textContent())?.trim() !== target.label) continue;
    await folders.nth(index).locator(":scope > summary").click();
    return;
  }
  throw new Error(`sticky folder not found: ${target.label}`);
}

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
  if (!(await source.evaluate((node) => node.open))) await clickStickyFolder(page, source);
  const category = row.locator('xpath=ancestor::details[contains(@class,"candidate-category")]');
  if (!(await category.evaluate((node) => node.open))) await clickStickyFolder(page, category);
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

  await clickStickyFolder(page, category);
  await clickStickyFolder(page, source);
  const collapsed = await snapshotDecoration(page, key);
  assert(!collapsed.category.open && !collapsed.source.open && !collapsed.category.iconHidden && !collapsed.source.iconHidden, "collapsed ancestors hide readiness status");
  assert(collapsed.category.description === "1 selected, all ready for promotion" && collapsed.source.description === "1 selected, all ready for promotion", "collapsed ancestor descriptions are incomplete");

  const overrides = await page.evaluate(async (candidateKey) => {
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
      const sourceFolder = root.querySelector(":scope > .override-source-folder");
      const originFolder = sourceFolder.querySelector(":scope > .override-origin-folder");
      const overrideRow = root.querySelector(`[data-candidate-key="${candidate.key}"]`);
      const summary = root.querySelector(":scope > summary");
      const expectedSourceLabel = candidate.sourceType === "interactive" ? "Interactive Toolkit" : candidate.sourceType === "upstream" ? "Contributor Guidance" : "Maintainer Proposals";
      const expectedOriginLabel = candidate.sourceType === "upstream"
        ? candidate.sourceTitle
        : candidate.sourceType === "interactive"
          ? formatHostedCategory(candidate.assessment.hostedCategory)
          : candidate.category;
      const naturalPath = [root, sourceFolder, originFolder].map((node) => node.querySelector(":scope > summary strong").textContent.trim());
      const countLabels = [root, sourceFolder, originFolder].map((node) => node.querySelector(":scope > summary .count-badge").textContent.trim());
      const treeDepths = [root, sourceFolder, originFolder, originFolder.querySelector(":scope > .candidate-category-items")].map((node) => node.dataset.treeDepth);
      const initialStickyLayer = document.querySelector("#candidate-sticky-stack > .candidate-sticky-layer.active");
      const initialStickyPath = [...initialStickyLayer.querySelectorAll("summary strong")].map((node) => node.textContent.trim());
      const sortButton = originFolder.querySelector('.candidate-list-header [data-candidate-sort="candidate"]');
      const scroller = document.querySelector("#candidate-list");
      const scrollTopBeforeSort = scroller.scrollTop;
      sortButton.click();
      await new Promise((resolve) => requestAnimationFrame(() => requestAnimationFrame(() => requestAnimationFrame(resolve))));
      await new Promise((resolve) => setTimeout(resolve, 150));
      const sortedStickyLayer = document.querySelector("#candidate-sticky-stack > .candidate-sticky-layer.active");
      const sortedStickyPath = [...sortedStickyLayer.querySelectorAll("summary strong")].map((node) => node.textContent.trim());
      const sortPreserved = Math.abs(scroller.scrollTop - scrollTopBeforeSort) < 0.1;
      const nextSource = root.nextElementSibling;
      nextSource.open = true;
      const nextCategory = [...nextSource.querySelectorAll(":scope > details.candidate-category")].find((node) => node.querySelector("[data-candidate-key]"));
      if (nextCategory) nextCategory.open = true;
      await new Promise((resolve) => requestAnimationFrame(() => requestAnimationFrame(() => requestAnimationFrame(resolve))));
      const stickyStack = document.querySelector("#candidate-sticky-stack");
      const nextSourceNaturalTop = getCandidateStickyNaturalTop(nextSource.querySelector(":scope > summary"));
      const scrollProbe = document.createElement("div");
      scrollProbe.style.height = `${scroller.clientHeight}px`;
      scroller.appendChild(scrollProbe);
      const boundaryReachable = scroller.scrollHeight - scroller.clientHeight > nextSourceNaturalTop;
      scroller.scrollTop = Math.max(1, nextSourceNaturalTop - stickyStack.getBoundingClientRect().height + 20);
      await new Promise((resolve) => requestAnimationFrame(() => requestAnimationFrame(() => requestAnimationFrame(resolve))));
      const pushedStickyLayer = stickyStack.querySelector(":scope > .candidate-sticky-layer.active");
      const pushedStickyPath = [...pushedStickyLayer.querySelectorAll("summary strong")].map((node) => node.textContent.trim());
      const boundaryValid = pushedStickyPath.join("|") === naturalPath.join("|")
        && stickyStack.querySelectorAll(":scope > .candidate-sticky-layer").length === 1
        && getComputedStyle(stickyStack).overflow === "hidden"
        && getComputedStyle(scroller).scrollSnapType === "none";
      scroller.scrollTop = nextSourceNaturalTop + 1;
      await new Promise((resolve) => {
        let remainingFrames = 60;
        const waitForTransfer = () => {
          const layer = stickyStack.querySelector(":scope > .candidate-sticky-layer.active");
          const sourceLabels = [...layer.querySelectorAll(':scope > details[data-sticky-depth="0"] > summary strong')].map((node) => node.textContent.trim());
          if (sourceLabels.includes(nextSource.querySelector(":scope > summary strong").textContent.trim()) || remainingFrames-- === 0) {
            resolve();
            return;
          }
          requestAnimationFrame(waitForTransfer);
        };
        waitForTransfer();
      });
      const transferredStickyLayer = stickyStack.querySelector(":scope > .candidate-sticky-layer.active");
      const transferredSources = [...transferredStickyLayer.querySelectorAll(':scope > details[data-sticky-depth="0"] > summary strong')].map((node) => node.textContent.trim());
      const transferValid = transferredSources.join("|") === ["OVERRIDES", nextSource.querySelector(":scope > summary strong").textContent.trim()].join("|")
        && stickyStack.querySelectorAll(":scope > .candidate-sticky-layer").length === 1
        && getComputedStyle(scroller).scrollSnapType === "none";
      const hierarchyValid = naturalPath.join("|") === ["OVERRIDES", expectedSourceLabel, expectedOriginLabel].join("|")
        && initialStickyPath.join("|") === naturalPath.join("|")
        && sortedStickyPath.join("|") === naturalPath.join("|")
        && countLabels.every((label) => label === "1 Override")
        && treeDepths.join("|") === "0|1|2|3"
        && sortedStickyLayer.querySelectorAll(".candidate-list-header").length === 1
        && sortPreserved;
      const modified = resolveColor("--modified-resource");
      const needsInputValid = !summary.hasAttribute("data-workbench-tooltip")
        && summary.querySelector(".count-badge").dataset.workbenchTooltip === "1 selected, 1 needs input"
        && [summary.querySelector(".candidate-parent-label > strong"), summary.querySelector(".candidate-parent-decoration-icon"), overrideRow.querySelector(".candidate-tree-copy strong"), overrideRow.querySelector(".candidate-decoration-icon")]
          .every((node) => getComputedStyle(node).color === modified);

      state.session.decisions[candidate.key] = {
        ...state.session.decisions[candidate.key],
        action: assessment.recommendation,
        rationale: getBulkDecisionRationale(candidate, assessment.recommendation)
      };
      syncCandidateTreeRows();
      const added = resolveColor("--added-resource");
      const readyValid = !summary.hasAttribute("data-workbench-tooltip")
        && summary.querySelector(".count-badge").dataset.workbenchTooltip === "1 selected, all ready for promotion"
        && [summary.querySelector(".candidate-parent-label > strong"), summary.querySelector(".candidate-parent-decoration-icon"), overrideRow.querySelector(".candidate-tree-copy strong"), overrideRow.querySelector(".candidate-decoration-icon")]
          .every((node) => getComputedStyle(node).color === added);
      return { boundaryReachable, boundaryValid, hierarchyValid, needsInputValid, readyValid, transferValid };
    } finally {
      state.session = sessionSnapshot;
      renderCandidateList();
    }
  }, key);
  assert(overrides.hierarchyValid, "Overrides do not preserve source/category ancestry, override counts, and one sticky sort header after sorting");
  assert(overrides.boundaryReachable, "Overrides boundary fixture is not scrollable enough to validate sticky ownership transfer");
  assert(overrides.boundaryValid, "four-level Overrides ancestry does not remain one clipped active layer with native snapping suspended at the next source boundary");
  assert(overrides.transferValid, "sticky ownership does not transfer cleanly from four-level Overrides to the next three-level source");
  assert(overrides.needsInputValid, "Overrides root and leaf do not share needs-input color or singular description");
  assert(overrides.readyValid, "Overrides root and leaf do not share ready color");
  assert(await page.locator("#candidate-list > .candidate-overrides-root").count() === 0, "Overrides probe did not restore the candidate tree");
}

module.exports = { name: "candidate decorations", behaviorIds, viewport: { width: 768, height: 900 }, run };
