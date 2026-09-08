const { openWorkbench } = require("../helpers/workbench.cjs");

const behaviorIds = ["WB-UX-PROVENANCE-001", "WB-UX-PROVENANCE-002"];

async function run({ page, baseUrl, assert, playback }) {
  await openWorkbench(page, baseUrl);
  await playback.show(page, "Provenance tooltip · 768px viewport");
  await page.evaluate(() => {
    const probe = document.createElement("div");
    probe.id = "source-provenance-tooltip-probe";
    probe.style.position = "fixed";
    probe.style.top = "120px";
    probe.style.left = "260px";
    probe.innerHTML = renderSourceSummaryLabel("upstream", "Contributor Guidance");
    document.body.appendChild(probe);
    syncTruncationTooltips();
  });

  const pill = page.locator("#source-provenance-tooltip-probe .source-provenance-pill");
  const box = await pill.boundingBox();
  const contract = await pill.evaluate((node) => ({
    text: node.textContent.trim(),
    tooltip: node.dataset.sourceProvenanceTooltip,
    title: node.getAttribute("title")
  }));
  assert(contract.text === contract.tooltip && /^[^@]+@[0-9a-f]{8}$/.test(contract.text), "tooltip does not retain the complete concise short-SHA provenance");
  assert(contract.title === null && !contract.text.startsWith("Contributor guidance source:"), "native or redundant provenance tooltip text remains active");

  const enterAt = async (entryX) => {
    await page.mouse.move(box.x - 12, box.y + box.height / 2);
    await page.mouse.move(entryX, box.y + box.height / 2);
    return page.evaluate((anchorX) => {
      const owner = document.querySelector("#source-provenance-tooltip-probe .source-provenance-pill");
      const tooltip = document.querySelector("#status-surface-tooltip");
      const ownerRect = owner.getBoundingClientRect();
      const tooltipRect = tooltip.getBoundingClientRect();
      return {
        visible: getComputedStyle(tooltip).visibility === "visible",
        textMatches: tooltip.textContent === owner.textContent.trim(),
        left: tooltipRect.left,
        right: tooltipRect.right,
        expectedLeft: Math.floor(Math.min(Math.max(8, anchorX), innerWidth - tooltipRect.width - 8)),
        belowGap: tooltipRect.top - ownerRect.bottom
      };
    }, entryX);
  };

  const leftEntry = await enterAt(box.x + 2);
  const rightEntry = await enterAt(box.x + box.width - 2);
  assert(leftEntry.visible && leftEntry.textMatches, "pointer-triggered tooltip is hidden or has incorrect text");
  assert(Math.abs(leftEntry.left - leftEntry.expectedLeft) < 0.1, "left-side pointer entry is not used as the tooltip anchor");
  assert(Math.abs(rightEntry.left - rightEntry.expectedLeft) < 0.1 && rightEntry.right <= 760.1, "right-side pointer entry is not clamped to the 8px viewport inset");
  assert(Math.abs(leftEntry.belowGap - 6) < 0.1 && Math.abs(rightEntry.belowGap - 6) < 0.1, "tooltip does not prefer placement 6px below the pill");

  const fallback = await page.evaluate(() => {
    const source = document.querySelector("#source-provenance-tooltip-probe .source-provenance-pill");
    const probe = source.cloneNode(true);
    probe.style.position = "fixed";
    probe.style.right = "4px";
    probe.style.bottom = "4px";
    document.body.appendChild(probe);
    showSourceProvenanceTooltip(probe, innerWidth - 4);
    const probeRect = probe.getBoundingClientRect();
    const tooltipRect = document.querySelector("#status-surface-tooltip").getBoundingClientRect();
    const result = {
      aboveGap: probeRect.top - tooltipRect.bottom,
      horizontallyContained: tooltipRect.left >= 8 && tooltipRect.right <= innerWidth - 8 + 0.1,
      verticallyContained: tooltipRect.top >= 8
    };
    probe.remove();
    hideStatusTooltip();
    return result;
  });
  assert(Math.abs(fallback.aboveGap - 6) < 0.1 && fallback.horizontallyContained && fallback.verticallyContained, "tooltip does not flip above when insufficient space remains below");

  await page.evaluate(() => document.querySelector("#source-provenance-tooltip-probe").remove());
}

module.exports = { name: "provenance tooltip", behaviorIds, viewport: { width: 768, height: 900 }, run };
