const { openWorkbench } = require("../helpers/workbench.cjs");

const behaviorIds = [
  "WB-UX-PREVIEW-001",
  "WB-UX-PREVIEW-002",
  "WB-UX-PREVIEW-003",
  "WB-UX-PREVIEW-004",
  "WB-UX-PREVIEW-005"
];

async function run({ page, baseUrl, assert }) {
  await openWorkbench(page, baseUrl);
  const fixture = await page.evaluate(async () => {
    globalThis.__previewReviewSessionSnapshot = structuredClone(state.session);
    const selected = state.candidates.filter((candidate) => {
      const decision = defaultDecision(candidate);
      return getAllowedActions(candidate, decision.proposedText).some((action) => isPromotionAction(action));
    }).slice(0, 4);
    for (const candidate of selected) {
      const decision = defaultDecision(candidate);
      const allowed = getAllowedActions(candidate, decision.proposedText);
      const action = allowed.includes(candidate.assessment.recommendation) && isPromotionAction(candidate.assessment.recommendation)
        ? candidate.assessment.recommendation
        : allowed.find((item) => isPromotionAction(item));
      state.session.decisions[candidate.key] = {
        ...decision,
        action,
        rationale: `Review ${candidate.id} in the promotion preview.`,
        ...createPlanMembership("manual"),
        sourceHash: candidate.hash,
        updatedAt: new Date().toISOString()
      };
    }
    state.session.approverName = "fixture-codeowner";
    state.session.updatedAt = new Date().toISOString();
    refreshEffectiveCandidates();
    await persistSession();
    renderAll();
    switchView("preview");
    return { selectedCount: selected.length };
  });
  assert(fixture.selectedCount === 4, "Preview fixture did not create four reviewable plan items");

  const proposed = await page.evaluate(() => {
    const layout = document.querySelector("#preview-view .preview-layout");
    const files = [...document.querySelectorAll(".preview-proposed-review [data-preview-file-path]")];
    const first = files[0];
    return {
      scope: document.querySelector("#preview-review-scope").value,
      sidebarFiles: document.querySelectorAll("#preview-summary [data-preview-file-jump]").length,
      fileCount: files.length,
      columns: getComputedStyle(layout).gridTemplateColumns,
      splitLabels: first ? [...first.querySelectorAll(".preview-split-labels span")].map((item) => item.textContent.trim()) : [],
      lineNumberWidth: first?.querySelector(".preview-line-number")?.getBoundingClientRect().width || 0,
      withinViewport: Boolean(first && first.getBoundingClientRect().right <= innerWidth)
    };
  });
  assert(proposed.scope === "proposed" && proposed.fileCount === 4 && proposed.sidebarFiles === 4, `Proposed review does not expose four synchronized changed files (${JSON.stringify(proposed)})`);
  assert(proposed.splitLabels.join("|") === "Current file|Changes" && proposed.withinViewport, "Proposed review does not use a contained split-file presentation");

  const firstFile = page.locator(".preview-proposed-review [data-preview-file-path]").first();
  await firstFile.locator("[data-preview-file-collapse]").click();
  assert(await firstFile.locator(".preview-file-body").isHidden(), "File collapse control does not hide the diff body");
  await firstFile.locator("[data-preview-file-collapse]").click();
  await firstFile.locator("[data-preview-viewed]").check();
  assert(await firstFile.evaluate((element) => element.classList.contains("viewed")), "Viewed control does not update the file state");

  await page.locator("#preview-review-scope").selectOption("payload");
  const payload = await page.evaluate(() => ({
    scope: state.previewReviewScope,
    sidebarFiles: document.querySelectorAll("#preview-summary [data-preview-file-jump]").length,
    visibleFiles: document.querySelectorAll(".payload-review [data-preview-file-path]").length,
    proposedHidden: document.querySelector(".preview-proposed-review").hidden,
    rawHidden: document.querySelector(".preview-raw-payload").hidden
  }));
  assert(payload.scope === "payload" && payload.visibleFiles === payload.sidebarFiles && payload.proposedHidden && payload.rawHidden, "Payload review scope does not own its file tree and visible files");

  await page.locator("#preview-review-scope").selectOption("raw");
  const raw = await page.evaluate(() => {
    const file = document.querySelector(".preview-raw-payload [data-preview-file-path]");
    const controls = [...file.querySelectorAll("[data-preview-context-direction]")];
    return {
      fileCount: document.querySelectorAll(".preview-raw-payload [data-preview-file-path]").length,
      path: file.dataset.previewFilePath,
      nestedSections: file.querySelectorAll("details").length,
      controls: controls.map((button) => ({ label: button.getAttribute("aria-label"), icon: button.querySelector("use")?.getAttribute("href") })),
      gapCount: file.querySelectorAll("[data-preview-context-gap]").length,
      contextLineCount: PREVIEW_CONTEXT_LINE_COUNT,
      expanderWidth: controls[0].getBoundingClientRect().width,
      lineNumberWidth: file.querySelector(".preview-line-number").getBoundingClientRect().width,
      splitLabels: [...file.querySelectorAll(".preview-split-labels span")].map((item) => item.textContent.trim())
    };
  });
  assert(raw.fileCount === 1 && raw.path === "selection/promotion-selection.json" && raw.nestedSections === 0, "Raw review is not one complete promotion-selection.json file");
  assert(raw.contextLineCount === 2 && raw.gapCount > 0 && raw.splitLabels.join("|") === "Current file|Changes", "Raw review does not collapse unchanged ranges around two context lines");
  assert(raw.expanderWidth === raw.lineNumberWidth, "Raw context expander does not match the line-number gutter width");
  assert(raw.controls.some((control) => control.label === "Expand Up" && control.icon.endsWith("#octicon-fold-up-16")), "Raw review does not use the local Fold Up Octicon");
  assert(raw.controls.some((control) => control.label === "Expand All" && control.icon.endsWith("#octicon-unfold-16")), "Raw review does not use the local Unfold Octicon");
  assert(raw.controls.some((control) => control.label === "Expand Down" && control.icon.endsWith("#octicon-fold-down-16")), "Raw review does not use the local Fold Down Octicon");

  const directionalExpansion = await page.evaluate(() => {
    const button = document.querySelector('[data-preview-context-direction="up"]');
    const gap = button.closest("[data-preview-context-gap]");
    const before = gap.querySelector("template").content.children.length;
    button.click();
    return { before, after: gap.querySelector("template").content.children.length };
  });
  assert(directionalExpansion.before - directionalExpansion.after === 10, "Fold Up does not reveal exactly ten lines");

  await page.locator("#preview-review-toggle").click();
  const review = await page.evaluate(() => ({
    visible: !document.querySelector("#preview-review-popover").hidden,
    approval: Boolean(document.querySelector("#preview-review-popover #approve-export-button")),
    approver: Boolean(document.querySelector("#preview-review-popover #approver-name"))
  }));
  assert(review.visible && review.approval && review.approver, "Review changes does not expose the existing approval workflow");
  await page.locator("#preview-review-close").click();

  await page.setViewportSize({ width: 768, height: 900 });
  const narrow = await page.evaluate(() => {
    const sidebar = document.querySelector("#preview-view .preview-summary").getBoundingClientRect();
    const preview = document.querySelector("#preview-view .preview-code").getBoundingClientRect();
    const layout = document.querySelector("#preview-view .preview-layout");
    return {
      columns: getComputedStyle(layout).gridTemplateColumns,
      stacked: sidebar.bottom <= preview.top + 1,
      contained: layout.scrollWidth === layout.clientWidth
    };
  });
  assert(narrow.stacked && narrow.contained, "Narrow Preview does not stack the file navigator above a contained review surface");

  await page.evaluate(async () => {
    state.session = globalThis.__previewReviewSessionSnapshot;
    delete globalThis.__previewReviewSessionSnapshot;
    state.previewReviewScope = "proposed";
    refreshEffectiveCandidates();
    await persistSession();
    renderAll();
    switchView("catalog");
  });
}

module.exports = { name: "promotion preview review", behaviorIds, viewport: { width: 1440, height: 900 }, run };
