const { openWorkbench } = require("../helpers/workbench.cjs");

const behaviorIds = [
  "WB-UX-STICKY-001",
  "WB-UX-STICKY-002",
  "WB-UX-STICKY-003"
];

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
  await source.locator(":scope > summary").click();
  await categories.nth(target.expandedIndex).locator(":scope > summary").click();

  const result = await page.evaluate(async ({ sourceIndex, expandedIndex }) => {
    const scroller = document.querySelector("#candidate-list");
    const source = scroller.querySelectorAll(":scope > details.candidate-source-root")[sourceIndex];
    const categories = source.querySelectorAll(":scope > details.candidate-category");
    const expanded = categories[expandedIndex];
    const candidates = expanded.querySelectorAll(":scope > .candidate-category-items > [data-candidate-key]");
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
    const sourceStyle = getComputedStyle(sourceSummary);
    const categoryStyle = getComputedStyle(categorySummary);
    const headerStyle = getComputedStyle(header);
    const candidateStyle = getComputedStyle(target);
    expanded.open = false;
    const closedHeaderRects = header.getClientRects().length;
    return {
      geometry: { top: rect.top, bottom: rect.bottom, width: rect.width, clientWidth: scroller.clientWidth },
      stickyStyles: {
        source: { position: sourceStyle.position, top: sourceStyle.top, zIndex: sourceStyle.zIndex, background: sourceStyle.backgroundColor },
        category: { position: categoryStyle.position, top: categoryStyle.top, zIndex: categoryStyle.zIndex, background: categoryStyle.backgroundColor },
        header: { position: headerStyle.position, top: headerStyle.top, zIndex: headerStyle.zIndex, background: headerStyle.backgroundColor }
      },
      closedHeaderRects,
      firstCandidateTop: firstCandidate?.top - rect.top,
      candidateSnapAlign: candidateStyle.scrollSnapAlign,
      scrollPaddingTop: getComputedStyle(scroller).scrollPaddingTop,
      scrollSnapType: getComputedStyle(scroller).scrollSnapType
    };
  }, target);

  assert(result.stickyStyles.source.position === "sticky" && result.stickyStyles.source.top === "0px" && result.stickyStyles.source.zIndex === "3", "source rows do not own the first sticky level");
  assert(result.stickyStyles.category.position === "sticky" && result.stickyStyles.category.top === "42px" && result.stickyStyles.category.zIndex === "2", "category rows do not own the second sticky level");
  assert(result.stickyStyles.header.position === "sticky" && result.stickyStyles.header.top === "82px" && result.stickyStyles.header.zIndex === "1", "candidate columns do not own the third sticky level");
  assert([result.stickyStyles.source, result.stickyStyles.category, result.stickyStyles.header].every((style) => style.background !== "rgba(0, 0, 0, 0)"), "sticky ancestry is not opaque");
  assert(result.closedHeaderRects === 0, "collapsed category content remains painted");
  assert(initial.gutter === "stable" && JSON.stringify(result.geometry) === JSON.stringify(initial.geometry), "candidate expansion changes scrollbar viewport geometry");
  assert(result.scrollSnapType === "y" && result.scrollPaddingTop === "117px" && result.candidateSnapAlign === "start", "candidate rows do not snap below sticky ancestry");
  if (result.firstCandidateTop !== undefined) assert(result.firstCandidateTop >= 116, "candidate row settles underneath sticky ancestry");
}

module.exports = { name: "candidate sticky context", behaviorIds, viewport: { width: 1440, height: 900 }, run };
