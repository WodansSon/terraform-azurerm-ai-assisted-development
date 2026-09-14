const { openWorkbench } = require("../helpers/workbench.cjs");

const behaviorIds = [
  "WB-UX-PREVIEW-001",
  "WB-UX-PREVIEW-002",
  "WB-UX-PREVIEW-003",
  "WB-UX-PREVIEW-004",
  "WB-UX-PREVIEW-005",
  "WB-UX-PREVIEW-006",
  "WB-UX-PREVIEW-007",
  "WB-UX-PREVIEW-008",
  "WB-UX-PREVIEW-009",
  "WB-UX-PREVIEW-010",
  "WB-UX-PREVIEW-011",
  "WB-UX-PREVIEW-012"
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

  const reviewModel = await page.evaluate(() => {
    const layout = document.querySelector("#preview-view .preview-layout");
    const view = document.querySelector("#preview-view");
    const toolbar = document.querySelector(".preview-review-toolbar");
    const scroller = document.querySelector("#preview-code");
    const splitter = document.querySelector("#preview-tree-resizer");
    const files = [...document.querySelectorAll(".preview-code [data-preview-file-path]")];
    const fileModels = Object.values(previewFilesByScope).flat();
    const first = files[0];
    const rows = [...document.querySelectorAll(".preview-split-row")];
    const gaps = files.slice(0, -1).map((file, index) => Math.round(files[index + 1].getBoundingClientRect().top - file.getBoundingClientRect().bottom));
    const treeIcons = Object.entries(previewFilesByScope).flatMap(([scope, scopeFiles]) => scopeFiles.map((file) => {
      const button = document.querySelector(`[data-preview-artifact-file-scope="${scope}"][data-preview-file-jump="${CSS.escape(file.path)}"]`);
      const status = file.additions > 0 && file.deletions === 0 ? "added" : file.deletions > 0 && file.additions === 0 ? "removed" : "modified";
      return {
        expected: `#octicon-file-${status === "modified" ? "diff" : status}-16`,
        href: button?.querySelector(":scope > .octicon use")?.getAttribute("href")
      };
    }));
    const folderIcons = [...document.querySelectorAll("[data-preview-artifact-scope]")].map((button) => button.querySelectorAll(":scope > .octicon use")[1]?.getAttribute("href"));
    const treeStatuses = [...document.querySelectorAll(".preview-tree-file-icon")].map((icon) => ({ label: icon.getAttribute("aria-label"), color: getComputedStyle(icon).color }));
    const displayPaths = files.map((file) => ({
      internal: file.dataset.previewFilePath,
      display: file.dataset.previewFileDisplayPath,
      heading: file.querySelector(".preview-file-path").textContent,
      copy: file.querySelector("[data-preview-copy-path]").dataset.previewCopyPath
    }));
    const firstGap = Math.round(first.getBoundingClientRect().top - scroller.getBoundingClientRect().top);
    const fileHierarchy = files.map((file) => ({
      children: [...file.children].map((child) => child.className),
      bodyInsideHeader: Boolean(file.querySelector(".preview-file-heading-wrapper .preview-file-body"))
    }));
    const toolbarDiffstat = [...document.querySelectorAll("#preview-review-context > .preview-diff-stat i")].map((cell) => cell.className);
    return {
      scopeControlAbsent: !document.querySelector("#preview-review-scope"),
      sidebarHeadingAbsent: !document.querySelector(".preview-sidebar-title"),
      parentCount: document.querySelectorAll("[data-preview-artifact-scope]").length,
      sidebarFiles: document.querySelectorAll("#preview-summary [data-preview-file-jump]").length,
      fileCount: files.length,
      proposedFiles: document.querySelectorAll(".preview-proposed-review [data-preview-file-path]").length,
      payloadFiles: document.querySelectorAll(".payload-review [data-preview-file-path]").length,
      rawFiles: document.querySelectorAll(".preview-raw-payload [data-preview-file-path]").length,
      columns: getComputedStyle(layout).gridTemplateColumns,
      viewChildren: [...view.children].map((child) => child.className),
      layoutChildren: [...layout.children].map((child) => child.className),
      codeChildren: [...scroller.children].map((child) => child.className),
      codeOverflow: getComputedStyle(scroller).overflow,
      codeContainment: getComputedStyle(scroller).contain,
      splitLabels: document.querySelectorAll(".preview-split-labels").length,
      lineNumberWidth: first?.querySelector(".preview-line-number")?.getBoundingClientRect().width || 0,
      splitColumns: rows[0] ? getComputedStyle(rows[0]).gridTemplateColumns.split(" ").map(parseFloat) : [],
      withinViewport: files.every((file) => file.getBoundingClientRect().right <= innerWidth),
      noHorizontalOverflow: files.every((file) => file.querySelector(".preview-file-body").scrollWidth === file.querySelector(".preview-file-body").clientWidth),
      allSectionsVisible: [...document.querySelectorAll(".preview-proposed-review, .payload-review, .preview-raw-payload")].every((section) => !section.hidden),
      uniformGaps: gaps.every((gap) => gap === 16),
      firstGap,
      sectionBordersAbsent: [...document.querySelectorAll(".preview-proposed-review, .payload-review, .preview-raw-payload")].every((section) => getComputedStyle(section).borderTopWidth === "0px"),
      topHunks: [...document.querySelectorAll(".preview-hunk-header use")].map((use) => use.getAttribute("href")),
      treeIcons,
      treeStatuses,
      folderIcons,
      displayPaths,
      fileHierarchy,
      toolbarHeight: toolbar.getBoundingClientRect().height,
      fileHeaderHeights: [...new Set(files.map((file) => file.querySelector(".preview-file-heading").getBoundingClientRect().height))],
      codeownerShields: document.querySelectorAll('.preview-review-status-icon use[href$="#octicon-shield-lock-16"]').length,
      viewedControls: [...document.querySelectorAll(".preview-viewed")].map((control) => ({ width: control.getBoundingClientRect().width, height: control.getBoundingClientRect().height })),
      toolbarText: document.querySelector("#preview-review-context").textContent.trim().replace(/\s+/g, " "),
      expectedToolbarText: `${fileModels.length} files changed+${fileModels.reduce((sum, file) => sum + file.additions, 0)}-${fileModels.reduce((sum, file) => sum + file.deletions, 0)}`,
      toolbarDiffstat,
      splitter: {
        role: splitter.getAttribute("role"),
        orientation: splitter.getAttribute("aria-orientation"),
        minimum: splitter.getAttribute("aria-valuemin"),
        maximum: splitter.getAttribute("aria-valuemax"),
        current: splitter.getAttribute("aria-valuenow"),
        width: splitter.getBoundingClientRect().width
      },
      initiallyExpanded: [...document.querySelectorAll("[data-preview-artifact-scope]")].every((button) => button.getAttribute("aria-expanded") === "true")
    };
  });
  assert(reviewModel.scopeControlAbsent && reviewModel.sidebarHeadingAbsent && reviewModel.parentCount === 3, "Preview still exposes obsolete scope or sidebar-heading controls");
  assert(reviewModel.fileCount === 9 && reviewModel.sidebarFiles === 9 && reviewModel.proposedFiles === 4 && reviewModel.payloadFiles === 4 && reviewModel.rawFiles === 1 && reviewModel.allSectionsVisible, `Preview is not one continuous nine-file review (${JSON.stringify(reviewModel)})`);
  assert(reviewModel.lineNumberWidth === 44 && reviewModel.splitLabels === 0 && reviewModel.withinViewport && reviewModel.noHorizontalOverflow, "Preview does not use GitHub split-diff geometry with wrapped content");
  assert(reviewModel.splitColumns.length === 2 && Math.abs(reviewModel.splitColumns[0] - reviewModel.splitColumns[1]) <= 1, "Preview split panes are not equal width");
  assert(reviewModel.firstGap === 16 && reviewModel.uniformGaps && reviewModel.sectionBordersAbsent, "Preview file spacing changes at the leading or artifact boundaries");
  assert(reviewModel.topHunks.length === 8 && reviewModel.topHunks.every((icon) => icon.endsWith("#octicon-kebab-horizontal-16")), "Top-file hunks do not use the local kebab-horizontal Octicon");
  assert(reviewModel.treeIcons.length === 9 && reviewModel.treeIcons.every((icon) => icon.href?.endsWith(icon.expected)), "Preview tree files do not use status-aware authenticated file icons");
  assert(reviewModel.treeStatuses.every((item) => ["Added", "Removed", "Modified"].includes(item.label)) && new Set(reviewModel.treeStatuses.map((item) => item.color)).size === 3, "Preview tree status icons do not retain distinct accessible states and colors");
  assert(reviewModel.folderIcons.length === 3 && reviewModel.folderIcons.every((icon) => icon.endsWith("#octicon-file-directory-open-fill-16")), "Preview tree folders do not use the authenticated open-directory icon");
  assert(reviewModel.displayPaths.every((item) => item.display === item.heading && item.display === item.copy && item.display !== item.internal && /^[A-Z ]+\//.test(item.display)), "Preview file headers do not expose virtual artifact paths while preserving internal navigation identity");
  assert(reviewModel.fileHierarchy.every((item) => item.children.join(",") === "preview-file-heading-wrapper,preview-file-body" && !item.bodyInsideHeader), "Preview file cards do not own sibling sticky-header and diff-body containers");
  assert(reviewModel.viewChildren.join(",") === "page-heading,preview-review-toolbar,preview-layout" && reviewModel.layoutChildren.join(",") === "preview-summary scroll-surface type-ui,preview-tree-resizer,preview-code scroll-surface type-editor" && !reviewModel.codeChildren.includes("preview-review-toolbar"), "Preview toolbar, tree, and diff scroller do not retain independent layer ownership");
  assert(reviewModel.codeOverflow === "auto" && reviewModel.codeContainment === "paint", "Preview diff flow is not isolated inside its owned scroll surface");
  assert(reviewModel.toolbarHeight === 60 && reviewModel.fileHeaderHeights.length === 1 && reviewModel.fileHeaderHeights[0] === 42, "Preview toolbar or sticky file headers do not match authenticated GitHub geometry");
  assert(reviewModel.codeownerShields === 9 && reviewModel.viewedControls.every((control) => control.width === 77 && control.height === 28), "Preview file headers do not retain CODEOWNERS and Viewed controls");
  assert(reviewModel.toolbarText === reviewModel.expectedToolbarText && reviewModel.toolbarDiffstat.length === 5 && reviewModel.toolbarDiffstat.includes("add") && reviewModel.toolbarDiffstat.includes("delete") && reviewModel.toolbarDiffstat.includes("neutral") && reviewModel.initiallyExpanded, `Preview toolbar totals, diffstat, or initial tree expansion are not synchronized to all files (${JSON.stringify(reviewModel)})`);
  assert(reviewModel.splitter.role === "slider" && reviewModel.splitter.orientation === "vertical" && reviewModel.splitter.minimum === "296" && Number(reviewModel.splitter.maximum) >= Number(reviewModel.splitter.current) && reviewModel.splitter.width === 5, "Preview changed-file tree does not expose an accessible five-pixel splitter");

  const firstFile = page.locator(".preview-proposed-review [data-preview-file-path]").first();
  await firstFile.locator("[data-preview-file-collapse]").click();
  assert(await firstFile.locator(".preview-file-body").isHidden(), "File collapse control does not hide the diff body");
  await firstFile.locator("[data-preview-file-collapse]").click();
  await firstFile.locator(".preview-viewed").click();
  const viewedCollapsed = await firstFile.evaluate((element) => ({
    viewed: element.classList.contains("viewed"),
    hidden: element.querySelector(".preview-file-body").hidden,
    expanded: element.querySelector("[data-preview-file-collapse]").getAttribute("aria-expanded"),
    chevron: element.querySelector("[data-preview-file-collapse] use")?.getAttribute("href"),
    pressed: element.querySelector(".preview-viewed").getAttribute("aria-pressed"),
    squareVisible: getComputedStyle(element.querySelector(".preview-viewed > .octicon:first-of-type")).display !== "none",
    checkedVisible: getComputedStyle(element.querySelector(".preview-viewed > .octicon:nth-of-type(2)")).display !== "none"
  }));
  assert(viewedCollapsed.viewed && viewedCollapsed.hidden && viewedCollapsed.expanded === "false" && viewedCollapsed.chevron.endsWith("#octicon-chevron-right-16") && viewedCollapsed.pressed === "true" && !viewedCollapsed.squareVisible && viewedCollapsed.checkedVisible, "Checking Viewed does not collapse an expanded file with the authenticated selected state");
  await firstFile.locator("[data-preview-file-collapse]").click();
  assert(await firstFile.evaluate((element) => element.classList.contains("viewed") && !element.querySelector(".preview-file-body").hidden && element.querySelector("[data-preview-file-collapse] use").getAttribute("href").endsWith("#octicon-chevron-down-16")), "Chevron does not reopen a Viewed file independently");
  await firstFile.locator(".preview-viewed").click();
  assert(await firstFile.evaluate((element) => !element.classList.contains("viewed") && !element.querySelector(".preview-file-body").hidden), "Unchecking Viewed changes the current disclosure state");
  await firstFile.locator("[data-preview-file-collapse]").click();
  await firstFile.locator(".preview-viewed").click();
  assert(await firstFile.evaluate((element) => element.classList.contains("viewed") && element.querySelector(".preview-file-body").hidden), "Checking Viewed changes an already collapsed file incorrectly");
  await firstFile.locator(".preview-viewed").click();
  assert(await firstFile.locator(".preview-file-body").isHidden(), "Unchecking Viewed expands a collapsed file");
  await firstFile.locator("[data-preview-file-collapse]").click();
  await firstFile.locator(".preview-viewed").click();
  const firstFilePath = await firstFile.getAttribute("data-preview-file-path");
  const firstTreeItem = page.locator(`[data-preview-file-jump="${firstFilePath}"]`);
  assert(await firstFile.evaluate((element) => element.classList.contains("viewed") && element.querySelector(".preview-file-body").hidden) && await firstTreeItem.getAttribute("aria-expanded") === null, "Viewed does not leave the file collapsed with navigation-only tree semantics");
  await firstTreeItem.click();
  assert(await firstFile.evaluate((element) => element.classList.contains("viewed") && element.querySelector(".preview-file-body").hidden), "Tree navigation changes a collapsed Viewed file card");
  await firstFile.locator("[data-preview-file-collapse]").click();
  await firstTreeItem.click();
  assert(await firstFile.evaluate((element) => element.classList.contains("viewed") && !element.querySelector(".preview-file-body").hidden), "Tree navigation changes an expanded Viewed file card");
  await firstFile.locator(".preview-viewed").click();

  const parentDisclosure = await page.evaluate(() => {
    const scroller = document.querySelector("#preview-code");
    const parent = document.querySelector('[data-preview-artifact-scope="payload"]');
    const selected = document.querySelector("[data-preview-file-jump].active")?.dataset.previewFileJump;
    scroller.scrollTop = 120;
    const before = { scrollTop: scroller.scrollTop, selected, proposed: document.querySelector('[data-preview-artifact-scope="proposed"]').getAttribute("aria-expanded"), raw: document.querySelector('[data-preview-artifact-scope="raw"]').getAttribute("aria-expanded") };
    parent.click();
    const collapsed = { scrollTop: scroller.scrollTop, selected: document.querySelector("[data-preview-file-jump].active")?.dataset.previewFileJump, expanded: document.querySelector('[data-preview-artifact-scope="payload"]').getAttribute("aria-expanded"), activeParents: document.querySelectorAll("[data-preview-artifact-scope].active").length };
    document.querySelector('[data-preview-artifact-scope="payload"]').click();
    const expanded = { scrollTop: scroller.scrollTop, selected: document.querySelector("[data-preview-file-jump].active")?.dataset.previewFileJump, expanded: document.querySelector('[data-preview-artifact-scope="payload"]').getAttribute("aria-expanded"), proposed: document.querySelector('[data-preview-artifact-scope="proposed"]').getAttribute("aria-expanded"), raw: document.querySelector('[data-preview-artifact-scope="raw"]').getAttribute("aria-expanded") };
    return { before, collapsed, expanded };
  });
  assert(parentDisclosure.collapsed.expanded === "false" && parentDisclosure.expanded.expanded === "true", "Artifact parent does not independently toggle its children");
  assert(parentDisclosure.before.scrollTop === parentDisclosure.collapsed.scrollTop && parentDisclosure.collapsed.scrollTop === parentDisclosure.expanded.scrollTop, "Artifact parent changes the review scroll position");
  assert(parentDisclosure.before.selected === parentDisclosure.collapsed.selected && parentDisclosure.collapsed.selected === parentDisclosure.expanded.selected && parentDisclosure.collapsed.activeParents === 0, "Artifact parent changes or duplicates file selection");
  assert(parentDisclosure.before.proposed === parentDisclosure.expanded.proposed && parentDisclosure.before.raw === parentDisclosure.expanded.raw, "Artifact parent changes sibling expansion state");

  const selectedPath = await page.evaluate(() => previewFilesByScope.payload[1].path);
  await page.locator(`[data-preview-file-jump="${selectedPath}"]`).click();
  await page.waitForFunction((path) => {
    const file = document.querySelector(`[data-preview-file-path="${CSS.escape(path)}"]`);
    const scroller = document.querySelector("#preview-code");
    return file && Math.abs(file.getBoundingClientRect().top - scroller.getBoundingClientRect().top - parseFloat(getComputedStyle(file).scrollMarginTop)) <= 1;
  }, selectedPath);
  const persistentSelection = await page.evaluate(async (path) => {
    const scroller = document.querySelector("#preview-code");
    const rawFile = document.querySelector('[data-preview-file-path="selection/promotion-selection.json"]');
    const selectedAfterClick = document.querySelector("[data-preview-file-jump].active")?.dataset.previewFileJump;
    rawFile.scrollIntoView({ block: "start", behavior: "auto" });
    scroller.scrollTop += 180;
    await new Promise((resolve) => requestAnimationFrame(() => requestAnimationFrame(resolve)));
    return {
      selectedAfterClick,
      selectedAfterScroll: document.querySelector("[data-preview-file-jump].active")?.dataset.previewFileJump,
      activeCount: document.querySelectorAll("[data-preview-file-jump].active").length,
      activeParents: document.querySelectorAll("[data-preview-artifact-scope].active").length,
      rawSticky: Math.abs(rawFile.querySelector(".preview-file-heading-wrapper").getBoundingClientRect().top - document.querySelector("#preview-code").getBoundingClientRect().top + 2) <= 1,
      visibleFiles: document.querySelectorAll(".preview-code [data-preview-file-path]").length,
      expected: path
    };
  }, selectedPath);
  assert(persistentSelection.selectedAfterClick === selectedPath && persistentSelection.selectedAfterScroll === selectedPath && persistentSelection.activeCount === 1 && persistentSelection.activeParents === 0, "Preview tree selection does not remain on the last explicitly selected file");
  assert(persistentSelection.rawSticky && persistentSelection.visibleFiles === 9, "Continuous review does not keep the current file header sticky while all files remain mounted");

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
      splitLabels: file.querySelectorAll(".preview-split-labels").length,
      linesToggle: {
        label: file.querySelector("[data-preview-lines-toggle]").getAttribute("aria-label"),
        pressed: file.querySelector("[data-preview-lines-toggle]").getAttribute("aria-pressed"),
        icon: file.querySelector("[data-preview-lines-toggle] use").getAttribute("href")
      }
    };
  });
  assert(raw.fileCount === 1 && raw.path === "selection/promotion-selection.json" && raw.nestedSections === 0, "Raw review is not one complete promotion-selection.json file");
  assert(raw.contextLineCount === 2 && raw.gapCount > 0 && raw.splitLabels === 0, "Raw review does not collapse unchanged ranges around two context lines");
  assert(raw.expanderWidth === raw.lineNumberWidth, "Raw context expander does not match the line-number gutter width");
  assert(raw.controls.some((control) => control.label === "Expand Up" && control.icon.endsWith("#octicon-fold-up-16")), "Raw review does not use the local Fold Up Octicon");
  assert(raw.controls.some((control) => control.label === "Expand All" && control.icon.endsWith("#octicon-unfold-16")), "Raw review does not use the local Unfold Octicon");
  assert(raw.controls.some((control) => control.label === "Expand Down" && control.icon.endsWith("#octicon-fold-down-16")), "Raw review does not use the local Fold Down Octicon");
  assert(raw.linesToggle.label === "Expand all lines: RAW SELECTION PAYLOAD/promotion-selection.json" && raw.linesToggle.pressed === "false" && raw.linesToggle.icon.endsWith("#octicon-unfold-16"), "Raw review does not start with the file-level Expand all lines override");

  const directionalExpansion = await page.evaluate(async () => {
    const file = document.querySelector(".preview-raw-payload [data-preview-file-path]");
    const button = document.querySelector('[data-preview-context-direction="up"]');
    const gap = button.closest("[data-preview-context-gap]");
    const before = gap.querySelector("template").content.children.length;
    button.click();
    await new Promise((resolve) => requestAnimationFrame(() => requestAnimationFrame(resolve)));
    const linesToggle = file.querySelector("[data-preview-lines-toggle]");
    const expanded = {
      remaining: gap.querySelector("template").content.children.length,
      label: linesToggle.getAttribute("aria-label"),
      pressed: linesToggle.getAttribute("aria-pressed"),
      icon: linesToggle.querySelector("use").getAttribute("href")
    };
    linesToggle.click();
    return {
      before,
      expanded,
      restored: {
        gaps: file.querySelectorAll("[data-preview-context-gap]").length,
        label: linesToggle.getAttribute("aria-label"),
        pressed: linesToggle.getAttribute("aria-pressed"),
        icon: linesToggle.querySelector("use").getAttribute("href")
      }
    };
  });
  assert(directionalExpansion.before - directionalExpansion.expanded.remaining === 10, "Fold Up does not reveal exactly ten lines");
  assert(directionalExpansion.expanded.label === "Collapse all lines: RAW SELECTION PAYLOAD/promotion-selection.json" && directionalExpansion.expanded.pressed === "true" && directionalExpansion.expanded.icon.endsWith("#octicon-fold-16"), "Inline context expansion does not switch the file-level override to Collapse all lines");
  assert(directionalExpansion.restored.gaps === raw.gapCount && directionalExpansion.restored.label === raw.linesToggle.label && directionalExpansion.restored.pressed === "false" && directionalExpansion.restored.icon.endsWith("#octicon-unfold-16"), "File-level Collapse all lines does not restore the canonical compact view and Expand all lines state");

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
    refreshEffectiveCandidates();
    await persistSession();
    renderAll();
    switchView("catalog");
  });
}

module.exports = { name: "promotion preview review", behaviorIds, viewport: { width: 1440, height: 900 }, run };
