const { openWorkbench } = require("../helpers/workbench.cjs");

const behaviorIds = [
  "WB-UX-CONTRIBUTOR-001",
  "WB-UX-CONTRIBUTOR-002",
  "WB-UX-CONTRIBUTOR-003"
];

async function run({ page, baseUrl, assert, playback }) {
  await openWorkbench(page, baseUrl);
  await playback.show(page, "Contributor guidance rule candidates");

  const structure = await page.evaluate(() => {
    const documentNode = document.querySelector('[data-source-id="guide-new-resource"]');
    const summary = documentNode?.querySelector(":scope > summary");
    const rows = [...(documentNode?.querySelectorAll(":scope > .candidate-category-items > [data-candidate-key]") || [])];
    return {
      documentExists: Boolean(documentNode),
      parentActionable: Boolean(summary?.querySelector('input, [data-candidate-key], [data-decision-key]')),
      sourceId: documentNode?.dataset.sourceId,
      sourceTitle: summary?.querySelector(".candidate-parent-label strong")?.textContent,
      parentUsesSharedLabel: Boolean(summary?.querySelector(".candidate-parent-label")),
      parentHasSubtext: Boolean(summary?.querySelector("small")),
      candidateCount: rows.length,
      candidateIds: rows.map((row) => row.querySelector(".candidate-tree-copy strong")?.textContent),
      updateCandidate: state.candidates.find((candidate) => candidate.assessment.targetHostedRuleId === "IMPL-PATCH-001")?.key,
      addTarget: state.candidates.find((candidate) => candidate.assessment.assessmentId === "resource-identity-list-resource")?.assessment.targetHostedRuleId
    };
  });

  assert(structure.documentExists && !structure.parentActionable, "contributor document is missing or actionable");
  assert(structure.sourceId === "guide-new-resource" && structure.sourceTitle === "Guide: New Resource", "contributor document identity is incorrect");
  assert(structure.parentUsesSharedLabel && !structure.parentHasSubtext, "contributor document parent does not use the shared single-line sibling treatment");
  assert(structure.candidateCount === 3, `expected 3 rule candidates, found ${structure.candidateCount}`);
  assert(structure.candidateIds.includes("IMPL-PATCH-001") && structure.candidateIds.includes("resource-identity-list-resource") && structure.candidateIds.includes("DOCS-IMP-002"), "contributor rule candidates are incomplete");
  assert(structure.addTarget === null, "add candidate unexpectedly targets an existing Hosted rule");

  const truncation = await page.evaluate(() => {
    const documentNode = document.querySelector('[data-source-id="guide-new-resource"]');
    const sourceRoot = documentNode.closest("details.candidate-source-root");
    sourceRoot.open = true;
    documentNode.open = true;
    const summary = documentNode.querySelector(":scope > summary");
    const title = summary.querySelector(".candidate-parent-label strong");
    const pill = summary.querySelector(".count-badge");
    title.textContent = `${title.textContent} Lorem ipsum dolor sit amet consectetur adipiscing elit sed do eiusmod tempor incididunt ut labore et dolore magna aliqua`;
    syncTruncationTooltips();
    const childId = [...documentNode.querySelectorAll("[data-candidate-key] .candidate-tree-copy strong")]
      .find((node) => node.textContent === "resource-identity-list-resource");
    const titleRect = title.getBoundingClientRect();
    const pillRect = pill.getBoundingClientRect();
    const titleStyle = getComputedStyle(title);
    const childStyle = getComputedStyle(childId);
    return {
      parent: {
        clipped: title.scrollWidth > title.clientWidth,
        title: title.getAttribute("title"),
        generatedTooltip: title.hasAttribute("data-truncation-tooltip"),
        textAlign: titleStyle.textAlign,
        textOverflow: titleStyle.textOverflow,
        whiteSpace: titleStyle.whiteSpace,
        rowHeight: summary.getBoundingClientRect().height,
        gapToPill: pillRect.left - titleRect.right,
        overlapsPill: titleRect.right > pillRect.left
      },
      child: {
        clipped: childId.scrollWidth > childId.clientWidth,
        title: childId.getAttribute("title"),
        generatedTooltip: childId.hasAttribute("data-truncation-tooltip"),
        textOverflow: childStyle.textOverflow,
        whiteSpace: childStyle.whiteSpace
      }
    };
  });

  assert(truncation.parent.clipped && truncation.parent.textOverflow === "ellipsis" && truncation.parent.whiteSpace === "nowrap", "long contributor parent title does not ellipsize");
  assert(truncation.parent.title === null && truncation.parent.generatedTooltip && truncation.parent.textAlign === "left", "long contributor parent title retains a native tooltip or lacks shared tooltip ownership");
  assert(Math.abs(truncation.parent.rowHeight - 40) < 0.1 && truncation.parent.gapToPill >= 7.9 && !truncation.parent.overlapsPill, "long contributor parent title changes row geometry or overlaps its count pill");
  assert(truncation.child.clipped && truncation.child.textOverflow === "ellipsis" && truncation.child.whiteSpace === "nowrap" && truncation.child.title === null && truncation.child.generatedTooltip, "long contributor child ID does not ellipsize through the shared tooltip contract");

  const parentTitle = page.locator('[data-source-id="guide-new-resource"] > summary .candidate-parent-label > strong');
  await parentTitle.hover({ position: { x: 20, y: 10 } });
  const tooltip = await page.evaluate(() => {
    const node = document.querySelector("#status-surface-tooltip");
    const rect = node.getBoundingClientRect();
    const style = getComputedStyle(node);
    const contentHeight = rect.height - parseFloat(style.paddingTop) - parseFloat(style.paddingBottom) - parseFloat(style.borderTopWidth) - parseFloat(style.borderBottomWidth);
    return {
      visible: style.visibility === "visible",
      text: node.textContent,
      fontSize: style.fontSize,
      lineHeight: style.lineHeight,
      lines: Math.round(contentHeight / parseFloat(style.lineHeight)),
      left: rect.left,
      right: rect.right,
      width: rect.width
    };
  });
  assert(tooltip.visible && tooltip.text.includes("Lorem ipsum") && tooltip.fontSize === "14px" && tooltip.lineHeight === "20px", "tree truncation does not use the shared Workbench tooltip typography or complete text");
  assert(tooltip.lines === 2 && Math.abs(tooltip.width - 752) < 0.1 && tooltip.left >= 8 && tooltip.right <= 760.1, "long tree tooltip does not use the available 768px viewport while preserving 8px margins");

  const preview = await page.evaluate((candidateKey) => {
    const candidate = state.candidates.find((item) => item.key === candidateKey);
    updateDecision(candidate, {
      action: "update",
      inPlan: true,
      rationale: "The source adds PUT preference while preserving the existing PATCH clearing safeguard."
    });
    switchView("preview");
    const card = [...document.querySelectorAll(".preview-change")].find((item) => item.getAttribute("aria-label")?.includes("IMPL-PATCH-001"));
    const payload = buildApprovalPayload();
    const decision = payload.decisions.find((item) => item.candidateId === "IMPL-PATCH-001");
    return {
      heading: card?.querySelector(".preview-change-heading strong")?.textContent,
      target: card?.querySelector(".diff-file-heading > span")?.textContent,
      deleted: [...(card?.querySelectorAll(".diff-line.delete code") || [])].map((line) => line.textContent),
      added: [...(card?.querySelectorAll(".diff-line.add code") || [])].map((line) => line.textContent),
      decision,
      hasMappedHostedRuleIds: Object.hasOwn(decision, "mappedHostedRuleIds")
    };
  }, structure.updateCandidate);

  assert(preview.heading === "GUIDE-NEW-RESOURCE", "preview does not retain the contributor source identity");
  assert(preview.target === "IMPL-PATCH-001", "preview does not identify the singular semantic target");
  assert(preview.deleted.length === 1 && preview.deleted[0].includes("PATCH preserves omitted properties"), "preview removal is not scoped to the target rule");
  assert(preview.added.length === 1 && preview.added[0].includes("Prefer PUT") && preview.added[0].includes("If PATCH is required"), "preview replacement does not preserve and extend the target rule");
  assert(preview.decision.hostedRuleId === "IMPL-PATCH-001" && preview.decision.sourceId === "guide-new-resource" && preview.decision.candidateId === "IMPL-PATCH-001", "approval payload does not preserve singular source, candidate, and target identities");
  assert(!preview.hasMappedHostedRuleIds, "approval payload still exports aggregate provenance mappings as action targets");
}

module.exports = { name: "contributor rule candidates", behaviorIds, viewport: { width: 768, height: 900 }, run };
