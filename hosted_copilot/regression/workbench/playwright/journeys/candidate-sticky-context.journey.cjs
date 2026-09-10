const { openWorkbench } = require("../helpers/workbench.cjs");

const behaviorIds = [
  "WB-UX-STICKY-001",
  "WB-UX-STICKY-002",
  "WB-UX-STICKY-003",
  "WB-UX-STICKY-004",
  "WB-UX-STICKY-005",
  "WB-UX-STICKY-006"
];

async function clickStickyFolder(page, depth, label) {
  const folders = page.locator(`#candidate-sticky-stack > .candidate-sticky-layer.active > details[data-sticky-depth="${depth}"]`);
  for (let index = 0; index < await folders.count(); index += 1) {
    if ((await folders.nth(index).locator(":scope > summary strong").textContent())?.trim() !== label) continue;
    await folders.nth(index).locator(":scope > summary").click();
    return;
  }
  throw new Error(`sticky folder not found: ${label}`);
}

async function run({ page, baseUrl, assert, playback }) {
  await openWorkbench(page, baseUrl);
  await playback.show(page, "Candidate tree sticky context");

  const initial = await page.evaluate(() => {
    const scroller = document.querySelector("#candidate-list");
    const rect = scroller.getBoundingClientRect();
    return {
      allCollapsed: [...scroller.querySelectorAll("details")].every((node) => !node.open),
      geometry: { top: rect.top, bottom: rect.bottom, width: rect.width, clientWidth: scroller.clientWidth },
      gutter: getComputedStyle(scroller).scrollbarGutter
    };
  });
  assert(initial.allCollapsed, "one or more candidate tree nodes start expanded");

  const target = await page.evaluate(() => {
    const roots = [...document.querySelectorAll("#candidate-list > details.candidate-source-root")];
    for (let sourceIndex = 0; sourceIndex < roots.length; sourceIndex += 1) {
      const categories = [...roots[sourceIndex].querySelectorAll(":scope > details.candidate-category")];
      const candidateCounts = categories.map((category) => category.querySelectorAll(":scope > .candidate-category-items > [data-candidate-key]").length);
      const expandedIndex = candidateCounts.indexOf(Math.max(...candidateCounts));
      if (candidateCounts[expandedIndex] > 0) {
        return {
          sourceIndex,
          expandedIndex,
          sourceLabel: roots[sourceIndex].querySelector(":scope > summary strong").textContent.trim(),
          expandedLabel: categories[expandedIndex].querySelector(":scope > summary strong").textContent.trim()
        };
      }
    }
    return null;
  });
  assert(target, "candidate tree does not contain a non-empty testable category");

  const source = page.locator("#candidate-list > details.candidate-source-root").nth(target.sourceIndex);
  const categories = source.locator(":scope > details.candidate-category");
  await clickStickyFolder(page, 0, target.sourceLabel);
  await clickStickyFolder(page, 1, target.expandedLabel);

  const result = await page.evaluate(async ({ sourceIndex, expandedIndex, sourceLabel, expandedLabel }) => {
    const scroller = document.querySelector("#candidate-list");
    scroller.dispatchEvent(new WheelEvent("wheel", { bubbles: true, deltaY: 1 }));
    const source = scroller.querySelectorAll(":scope > details.candidate-source-root")[sourceIndex];
    const categories = source.querySelectorAll(":scope > details.candidate-category");
    const expanded = categories[expandedIndex];
    const group = expanded.querySelector(":scope > .candidate-category-items");
    const donor = [...scroller.querySelectorAll("[data-candidate-key]")].find((row) => !expanded.contains(row));
    if (!donor) throw new Error("candidate tree does not contain a second row for sort validation");
    group.appendChild(donor);
    const ascendingRows = [...group.querySelectorAll(":scope > [data-candidate-key]")].sort((left, right) => {
      const leftCandidate = state.candidates.find((candidate) => candidate.key === left.dataset.candidateKey);
      const rightCandidate = state.candidates.find((candidate) => candidate.key === right.dataset.candidateKey);
      return getEffectiveHostedRuleId(leftCandidate).localeCompare(getEffectiveHostedRuleId(rightCandidate), undefined, { numeric: true, sensitivity: "base" });
    });
    const ascendingFragment = document.createDocumentFragment();
    ascendingRows.forEach((row) => ascendingFragment.appendChild(row));
    group.appendChild(ascendingFragment);
    const candidates = group.querySelectorAll(":scope > [data-candidate-key]");
    const target = candidates[Math.min(10, candidates.length - 1)];
    const sourceSummary = source.querySelector(":scope > summary");
    const categorySummary = expanded.querySelector(":scope > summary");
    const header = expanded.querySelector(":scope > .candidate-category-items > .candidate-list-header");
    const scrollerRect = scroller.getBoundingClientRect();
    scroller.scrollTop += target.getBoundingClientRect().top - scrollerRect.top - 180;
    await new Promise((resolve) => setTimeout(resolve, 400));

    const rect = scroller.getBoundingClientRect();
    const firstCandidate = [...expanded.querySelectorAll(":scope > .candidate-category-items > [data-candidate-key]")]
      .map((node) => node.getBoundingClientRect())
      .find((rowRect) => rowRect.bottom > rect.top + 117);
    const stickyLayer = document.querySelector("#candidate-sticky-stack > .candidate-sticky-layer.active");
    const stickySource = [...stickyLayer.querySelectorAll(':scope > details[data-sticky-depth="0"]')]
      .find((node) => node.querySelector(":scope > summary strong").textContent.trim() === sourceLabel);
    const stickyCategory = [...stickyLayer.querySelectorAll(':scope > details[data-sticky-depth="1"]')]
      .find((node) => node.querySelector(":scope > summary strong").textContent.trim() === expandedLabel);
    const stickySlots = [
      stickySource.querySelector(":scope > summary"),
      stickyCategory.querySelector(":scope > summary"),
      stickyLayer.querySelector('.candidate-list-header[data-sticky-depth="2"]')
    ];
    const stickyStyles = stickySlots.map((node) => {
      const style = getComputedStyle(node);
      const rect = node.getBoundingClientRect();
      return { position: style.position, background: style.backgroundColor, top: rect.top, bottom: rect.bottom };
    });
    const naturalPositions = [sourceSummary, categorySummary, header].map((node) => getComputedStyle(node).position);
    const scrollSnapType = getComputedStyle(scroller).scrollSnapType;
    const orderBeforeSort = [...expanded.querySelectorAll(":scope > .candidate-category-items > [data-candidate-key]")].map((row) => row.dataset.candidateKey);
    const scrollTopBeforeSort = scroller.scrollTop;
    const candidateSort = header.querySelector('[data-candidate-sort="candidate"]');
    candidateSort.click();
    await new Promise((resolve) => requestAnimationFrame(() => requestAnimationFrame(() => requestAnimationFrame(resolve))));
    await new Promise((resolve) => setTimeout(resolve, 150));
    const orderAfterSort = [...expanded.querySelectorAll(":scope > .candidate-category-items > [data-candidate-key]")].map((row) => row.dataset.candidateKey);
    const sortPreservation = {
      changedOrder: orderBeforeSort.join("|") !== orderAfterSort.join("|"),
      scrollTopBefore: scrollTopBeforeSort,
      scrollTopAfter: scroller.scrollTop,
      sourceOpen: source.open,
      categoryOpen: expanded.open,
      scrollSnapType: getComputedStyle(scroller).scrollSnapType
    };
    expanded.open = false;
    const closedHeaderRects = header.getClientRects().length;
    return {
      geometry: { top: rect.top, bottom: rect.bottom, width: rect.width, clientWidth: scroller.clientWidth },
      stickyStyles: {
        source: stickyStyles[0],
        category: stickyStyles[1],
        header: stickyStyles[2]
      },
      stickyLayerCount: document.querySelectorAll("#candidate-sticky-stack > .candidate-sticky-layer").length,
      naturalPositions,
      closedHeaderRects,
      firstCandidateTop: firstCandidate?.top - rect.top,
      stickyStackHeight: document.querySelector("#candidate-sticky-stack").getBoundingClientRect().height,
      scrollPaddingTop: getComputedStyle(scroller).scrollPaddingTop,
      scrollSnapType,
      sortPreservation
    };
  }, target);

  assert(result.naturalPositions.every((position) => position === "static"), "natural candidate rows still compete with mirrored sticky slots");
  assert(result.stickyLayerCount === 1 && Object.values(result.stickyStyles).every((style) => style.position === "static"), "candidate ancestry is not rendered by one stable mirrored layer");
  assert(Math.abs(result.stickyStyles.category.top - result.stickyStyles.source.bottom) < 1 && Math.abs(result.stickyStyles.header.top - result.stickyStyles.category.bottom) < 1, "mirrored sticky levels contain gaps or overlaps");
  assert([result.stickyStyles.source, result.stickyStyles.category, result.stickyStyles.header].every((style) => style.background !== "rgba(0, 0, 0, 0)"), "sticky ancestry is not opaque");
  assert(result.closedHeaderRects === 0, "collapsed category content remains painted");
  assert(initial.gutter === "stable" && JSON.stringify(result.geometry) === JSON.stringify(initial.geometry), "candidate expansion changes scrollbar viewport geometry");
  assert(result.scrollSnapType === "none" && Math.abs(parseFloat(result.scrollPaddingTop) - result.stickyStackHeight) < 0.1, "candidate scrolling does not reserve stable sticky ancestry without snapping");
  if (result.firstCandidateTop !== undefined) assert(result.firstCandidateTop >= result.stickyStackHeight - 1, "candidate row settles underneath sticky ancestry");
  assert(result.sortPreservation.changedOrder, "candidate sort did not reorder the open category");
  assert(Math.abs(result.sortPreservation.scrollTopAfter - result.sortPreservation.scrollTopBefore) < 0.1, `candidate sort changed tree scroll position from ${result.sortPreservation.scrollTopBefore}px to ${result.sortPreservation.scrollTopAfter}px`);
  assert(result.sortPreservation.sourceOpen && result.sortPreservation.categoryOpen && result.sortPreservation.scrollSnapType === "none", "candidate sort changed disclosure or non-snapping scroll state");

  await page.waitForFunction(() => Boolean(document.querySelector("#candidate-sticky-stack > .candidate-sticky-layer.active .candidate-list-header")));
  await clickStickyFolder(page, 1, target.expandedLabel);
  await page.waitForFunction(() => {
    const layer = document.querySelector("#candidate-sticky-stack > .candidate-sticky-layer.active");
    return layer && !layer.querySelector("[data-sticky-category-index]")?.open && !layer.querySelector(".candidate-list-header");
  });
  const categoryClosed = await page.evaluate(() => {
    const layer = document.querySelector("#candidate-sticky-stack > .candidate-sticky-layer.active");
    return {
      categoryOpen: layer.querySelector("[data-sticky-category-index]")?.open,
      hasSortHeader: Boolean(layer.querySelector(".candidate-list-header")),
      sourceOpen: layer.querySelector("[data-sticky-source]")?.open
    };
  });
  assert(categoryClosed.sourceOpen && categoryClosed.categoryOpen === false && !categoryClosed.hasSortHeader, "closing the sticky category leaves its sort header visible");

  await clickStickyFolder(page, 1, target.expandedLabel);
  await page.waitForFunction(() => Boolean(document.querySelector("#candidate-sticky-stack > .candidate-sticky-layer.active .candidate-list-header")));
  await clickStickyFolder(page, 0, target.sourceLabel);
  await page.waitForFunction(() => {
    const layer = document.querySelector("#candidate-sticky-stack > .candidate-sticky-layer.active");
    return layer && !layer.querySelector("[data-sticky-source]")?.open && !layer.querySelector("[data-sticky-category-index]") && !layer.querySelector(".candidate-list-header");
  });
  const sourceClosed = await page.evaluate(() => {
    const layer = document.querySelector("#candidate-sticky-stack > .candidate-sticky-layer.active");
    return {
      categoryCount: layer.querySelectorAll("[data-sticky-category-index]").length,
      hasSortHeader: Boolean(layer.querySelector(".candidate-list-header")),
      sourceOpen: layer.querySelector("[data-sticky-source]")?.open
    };
  });
  assert(sourceClosed.sourceOpen === false && sourceClosed.categoryCount === 0 && !sourceClosed.hasSortHeader, "closing the sticky source leaves child headers visible");

  const siblingExpansion = await page.evaluate(async () => {
    const scroller = document.querySelector("#candidate-list");
    const source = scroller.querySelector(":scope > details.candidate-source-root");
    const categories = [...source.querySelectorAll(":scope > details.candidate-category")];
    const expanded = categories[0];
    const sibling = categories[1] || expanded.cloneNode(true);
    if (!categories[1]) {
      sibling.open = false;
      sibling.dataset.category = "Sibling";
      sibling.querySelector(":scope > summary strong").textContent = "Sibling";
      source.appendChild(sibling);
    }
    if (!source.open) source.querySelector(":scope > summary").click();
    if (!expanded.open) expanded.querySelector(":scope > summary").click();
    if (sibling.open) sibling.querySelector(":scope > summary").click();
    await new Promise((resolve) => requestAnimationFrame(() => requestAnimationFrame(resolve)));
    scroller.scrollTop = scroller.scrollHeight - scroller.clientHeight;
    await new Promise((resolve) => setTimeout(resolve, 300));
    const scrollTopBefore = scroller.scrollTop;
    const siblingTopBefore = sibling.querySelector(":scope > summary").getBoundingClientRect().top;
    sibling.querySelector(":scope > summary").click();
    await new Promise((resolve) => requestAnimationFrame(() => requestAnimationFrame(resolve)));
    await new Promise((resolve) => setTimeout(resolve, 150));
    const disclosureResult = {
      scrollTopBefore,
      scrollTopAfter: scroller.scrollTop,
      siblingTopBefore,
      siblingTopAfter: sibling.querySelector(":scope > summary").getBoundingClientRect().top,
      siblingOpen: sibling.open,
      suspendedSnapType: getComputedStyle(scroller).scrollSnapType
    };
    scroller.dispatchEvent(new WheelEvent("wheel", { bubbles: true, deltaY: 1 }));
    return {
      ...disclosureResult,
      restoredSnapType: getComputedStyle(scroller).scrollSnapType
    };
  });
  assert(siblingExpansion.siblingOpen, "sibling candidate folder did not expand");
  assert(Math.abs(siblingExpansion.scrollTopAfter - siblingExpansion.scrollTopBefore) < 0.1 && Math.abs(siblingExpansion.siblingTopAfter - siblingExpansion.siblingTopBefore) < 0.1, "opening a sibling candidate folder moved the tree instead of expanding downward");
  assert(siblingExpansion.suspendedSnapType === "none" && siblingExpansion.restoredSnapType === "none", "candidate disclosure changed the continuous non-snapping scroll state");
}

module.exports = { name: "candidate sticky context", behaviorIds, viewport: { width: 1440, height: 900 }, run };
