const { hoverForWorkbenchTooltip, openWorkbench, revealCandidate } = require("../helpers/workbench.cjs");

const behaviorIds = [
  "WB-UX-CONTRIBUTOR-001",
  "WB-UX-CONTRIBUTOR-002",
  "WB-UX-CONTRIBUTOR-003",
  "WB-UX-IDENTITY-001",
  "WB-UX-IDENTITY-002",
  "WB-UX-IDENTITY-003",
  "WB-UX-IDENTITY-004"
];

async function run({ page, baseUrl, assert, playback }) {
  await openWorkbench(page, baseUrl);
  await playback.show(page, "Contributor guidance rule candidates");

  const structure = await page.evaluate(() => {
    const documentNode = candidateHierarchicalView.model.nodes.find((node) => node.kind === "folder" && node.data.candidates?.some((candidate) => candidate.sourceId === "guide-new-resource"));
    revealCandidateInTree(documentNode.data.candidates[0].key);
    const row = document.querySelector(`#candidate-list [data-node-id="${CSS.escape(documentNode.id)}"]`);
    const candidates = documentNode.data.candidates;
    return {
      documentExists: Boolean(documentNode),
      parentActionable: Boolean(row?.querySelector('input, [data-candidate-key], [data-decision-key]')),
      sourceId: candidates[0]?.sourceId,
      sourceTitle: row?.querySelector(".candidate-parent-label strong")?.textContent,
      parentUsesSharedLabel: Boolean(row?.querySelector(".candidate-parent-label")),
      parentHasSubtext: Boolean(row?.querySelector("small")),
      candidateCount: candidates.length,
      candidateIds: candidates.map((candidate) => getEffectiveHostedRuleId(candidate)),
      updateCandidate: state.candidates.find((candidate) => candidate.assessment.targetHostedRuleId === "IMPL-PATCH-001")?.key,
      addCandidate: state.candidates.find((candidate) => candidate.assessment.assessmentId === "resource-identity-list-resource")?.key,
      addTarget: state.candidates.find((candidate) => candidate.assessment.assessmentId === "resource-identity-list-resource")?.assessment.targetHostedRuleId
    };
  });

  assert(structure.documentExists && !structure.parentActionable, "contributor document is missing or actionable");
  assert(structure.sourceId === "guide-new-resource" && structure.sourceTitle === "Guide: New Resource", "contributor document identity is incorrect");
  assert(structure.parentUsesSharedLabel && !structure.parentHasSubtext, "contributor document parent does not use the shared single-line sibling treatment");
  assert(structure.candidateCount === 3, `expected 3 rule candidates, found ${structure.candidateCount}`);
  assert(structure.candidateIds.includes("IMPL-PATCH-001") && structure.candidateIds.includes("REVIEW-REPO-001") && structure.candidateIds.includes("DOCS-IMP-002"), "contributor rule candidates are incomplete");
  assert(structure.addTarget === null, "add candidate unexpectedly targets an existing Hosted rule");

  const excludedProposal = await page.evaluate(() => {
    const source = state.assessedCandidates.find((candidate) => candidate.assessment.proposedHostedRuleId === "REVIEW-EVID-001");
    const probe = {
      ...source,
      key: `${source.key}:excluded-proposal-probe`,
      assessment: {
        ...source.assessment,
        assessmentId: "excluded-proposal-probe",
        hostedApplicable: false,
        hostedCategory: "not-applicable",
        recommendation: "exclude",
        proposedHostedRuleId: "REVIEW-EVID-099",
        proposedText: "Keep the complete generated Hosted proposal visible while its exclusion remains under review.",
        selectionFactors: { ...source.assessment.selectionFactors, falsePositiveRisk: 5, redundancy: 3 }
      }
    };
    state.assessedCandidates.push(probe);
    state.assessmentActiveKey = probe.key;
    const sourceNodeId = `assessment:source:${probe.sourceType}`;
    const categoryNodeId = `assessment:category:${probe.sourceType}:${probe.assessment.hostedCategory}`;
    const previousSourceExpansion = assessmentExpansionState.has(sourceNodeId) ? assessmentExpansionState.get(sourceNodeId) : null;
    const previousCategoryExpansion = assessmentExpansionState.has(categoryNodeId) ? assessmentExpansionState.get(categoryNodeId) : null;
    assessmentExpansionState.set(sourceNodeId, true);
    assessmentExpansionState.set(categoryNodeId, true);
    renderAssessmentResults();
    const row = document.querySelector(`[data-assessment-key="${CSS.escape(probe.key)}"]`);
    const detail = document.querySelector("#assessment-results-detail");
    const proposal = [...detail.querySelectorAll(".section-block")].find((section) => section.querySelector(":scope > .section-label")?.textContent === "Proposed Hosted Rule:");
    const actionButtons = [...detail.querySelectorAll(".override-inline-actions > button")];
    const factorClasses = [...detail.querySelectorAll(".factor-line.penalty")].map((line) => line.className);
    const result = {
      actionIcons: actionButtons.map((button) => button.querySelector("use")?.getAttribute("href")),
      actionLabels: actionButtons.map((button) => button.getAttribute("aria-label")),
      breadcrumbId: detail.querySelector(".detail-identity > span:last-child")?.textContent,
      factorClasses,
      proposalId: proposal?.querySelector(".overlap-item strong")?.textContent,
      proposalText: proposal?.querySelector(".overlap-item p")?.textContent,
      rowId: row?.querySelector(".candidate-tree-copy strong")?.textContent
    };
    state.assessedCandidates.pop();
    state.assessmentActiveKey = null;
    if (previousSourceExpansion === null) assessmentExpansionState.delete(sourceNodeId);
    else assessmentExpansionState.set(sourceNodeId, previousSourceExpansion);
    if (previousCategoryExpansion === null) assessmentExpansionState.delete(categoryNodeId);
    else assessmentExpansionState.set(categoryNodeId, previousCategoryExpansion);
    renderAssessmentResults();
    return result;
  });
  assert(excludedProposal.rowId === "REVIEW-EVID-099" && excludedProposal.breadcrumbId === "REVIEW-EVID-099", "excluded assessment does not use its generated Hosted identity in the tree and Details breadcrumb");
  assert(excludedProposal.proposalId === "REVIEW-EVID-099" && excludedProposal.proposalText?.startsWith("Keep the complete generated Hosted proposal"), "excluded assessment does not display its complete generated Hosted proposal");
  assert(excludedProposal.actionLabels.join("|") === "Apply Override|Cancel Override" && excludedProposal.actionIcons[0]?.endsWith("#codicon-git-stash-apply") && excludedProposal.actionIcons[1]?.endsWith("#codicon-close"), "override rationale actions do not use the accepted icon order");
  assert(excludedProposal.factorClasses.some((value) => value.includes("risk-high")) && excludedProposal.factorClasses.some((value) => value.includes("risk-moderate")), "excluded assessment factors do not retain high and moderate semantic risk classes");

  await page.evaluate((candidateKey) => {
    selectCandidate(candidateKey);
    showCandidatePane("details");
    const candidate = state.candidates.find((item) => item.key === candidateKey);
    updateDecision(candidate, {
      action: "add",
      inPlan: true,
      rationale: "The contributor guidance requires a new Hosted review safeguard."
    });
    syncAssessmentActionControls(candidate);
  }, structure.addCandidate);

  const generatedId = "REVIEW-REPO-001";
  const identityReadout = page.locator("#assessment-panel .rule-action-header .detail-identity");
  assert((await identityReadout.innerText()).replace(/\s+/g, " ") === `RULE: ${generatedId}`, "Add candidate does not show its generated Hosted identity in the embedded Rule Actions header");
  assert(await page.locator('#assessment-panel [data-decision-field="proposedHostedRuleId"]').count() === 0, "Details still exposes a maintainer-editable Hosted rule ID control");

  const propagated = await page.evaluate(({ candidateKey, generatedId }) => {
    const candidate = state.candidates.find((item) => item.key === candidateKey);
    const treeId = document.querySelector(`[data-candidate-key="${CSS.escape(candidateKey)}"] .candidate-tree-copy strong`)?.textContent;
    const detailId = document.querySelector("#assessment-panel > .assessment-title .detail-identity span:last-child")?.textContent;
    const readoutId = document.querySelector("#assessment-panel .rule-action-header .detail-identity span:last-child")?.textContent;
    switchView("plan");
    const planId = document.querySelector(`[data-plan-row="${CSS.escape(candidateKey)}"] .candidate-link`)?.textContent;
    switchView("preview");
    const previewId = [...document.querySelectorAll(".preview-proposed-review [data-preview-file-path]")]
      .find((item) => item.dataset.previewFilePath === `rules/${generatedId}.md`)
      ?.dataset.previewFilePath.replace(/^rules\//, "").replace(/\.md$/, "");
    const mutation = buildApprovedRules().mutations.find((item) => item.rule.id === generatedId);
    return { treeId, detailId, readoutId, planId, previewId, mutation, readiness: getPreviewReadiness() };
  }, { candidateKey: structure.addCandidate, generatedId });
  assert([propagated.treeId, propagated.detailId, propagated.readoutId, propagated.planId, propagated.previewId].every((value) => value === generatedId), "builder-generated Hosted rule ID does not propagate unchanged across Workbench views");
  assert(propagated.mutation.action === "add" && propagated.mutation.rule.id === generatedId && propagated.mutation.rule.origin === "hosted-catalog-addition", "approved Add mutation does not preserve the builder-generated Hosted identity");
  assert(propagated.readiness.ready, "builder-generated Hosted identity does not satisfy approval readiness");

  await page.evaluate(async (candidateKey) => {
    const candidate = state.candidates.find((item) => item.key === candidateKey);
    await resetCandidate(candidate);
  }, structure.addCandidate);
  await openWorkbench(page, baseUrl);

  await page.evaluate((candidateKey) => {
    selectCandidate(candidateKey);
    showCandidatePane("details");
    const candidate = state.candidates.find((item) => item.key === candidateKey);
    updateDecision(candidate, {
      action: "update",
      inPlan: true,
      rationale: "The mapped Hosted rule should adopt the complete proposed wording."
    });
    syncAssessmentActionControls(candidate);
  }, structure.updateCandidate);
  const mappedIdentityReadout = page.locator("#assessment-panel .rule-action-header .detail-identity span:last-child");
  const mappedIdentity = await page.evaluate((candidateKey) => {
    const candidate = state.candidates.find((item) => item.key === candidateKey);
    const mutation = buildApprovedRules().mutations.find((item) => item.rule.id === candidate.assessment.targetHostedRuleId);
    const sharedTargetCandidate = {
      ...candidate,
      key: `${candidate.key}:shared-target`,
      assessment: { ...candidate.assessment, assessmentId: "shared-target-reference" }
    };
    state.assessedCandidates.push(sharedTargetCandidate);
    const readiness = getPlanReadiness(candidate);
    state.assessedCandidates.pop();
    return {
      mutation,
      readiness
    };
  }, structure.updateCandidate);
  assert(await mappedIdentityReadout.innerText() === "IMPL-PATCH-001", "mapped update does not expose its generated proposal identity as the immutable target ID");
  assert(mappedIdentity.mutation.action === "update" && mappedIdentity.mutation.rule.id === "IMPL-PATCH-001", "mapped Update mutation does not preserve the existing Hosted identity");
  assert(mappedIdentity.readiness.ready, "mapped update proposal identity does not satisfy plan readiness when another assessment references the same target");

  await page.evaluate(async (candidateKey) => {
    const candidate = state.candidates.find((item) => item.key === candidateKey);
    await resetCandidate(candidate);
  }, structure.updateCandidate);
  await openWorkbench(page, baseUrl);

  await revealCandidate(page, structure.updateCandidate);

  const truncation = await page.evaluate(() => {
    const documentNode = candidateHierarchicalView.model.nodes.find((node) => node.kind === "folder" && node.data.candidates?.some((candidate) => candidate.sourceId === "guide-new-resource"));
    const row = document.querySelector(`#candidate-list [data-node-id="${CSS.escape(documentNode.id)}"]`);
    const title = row.querySelector(".candidate-parent-label strong");
    const pill = row.querySelector(".count-badge");
    title.textContent = `${title.textContent} Lorem ipsum dolor sit amet consectetur adipiscing elit sed do eiusmod tempor incididunt ut labore et dolore magna aliqua`;
    syncTruncationTooltips();
    const childId = [...document.querySelectorAll("#candidate-list [data-candidate-key] .candidate-tree-copy strong")]
      .find((node) => node.textContent === "REVIEW-REPO-001");
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
        rowHeight: row.getBoundingClientRect().height,
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
  const parentTitle = page.locator('#candidate-list [data-node-id="candidate:folder:upstream:guide-new-resource"] .candidate-parent-label > strong');
  await hoverForWorkbenchTooltip(page, parentTitle, { position: { x: 20, y: 10 } });
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
    const card = document.querySelector('[data-preview-file-path="rules/IMPL-PATCH-001.md"]');
    const mutation = buildApprovedRules().mutations.find((item) => item.rule.id === "IMPL-PATCH-001");
    return {
      heading: card?.dataset.previewSourceId?.toUpperCase(),
      target: card?.dataset.previewFilePath?.replace(/^rules\//, "").replace(/\.md$/, ""),
      deleted: [...(card?.querySelectorAll(".preview-diff-cell.delete code") || [])].map((line) => line.textContent),
      added: [...(card?.querySelectorAll(".preview-diff-cell.add code") || [])].map((line) => line.textContent),
      mutation,
      hasMappedHostedRuleIds: Object.hasOwn(mutation, "mappedHostedRuleIds")
    };
  }, structure.updateCandidate);

  assert(preview.heading === "GUIDE-NEW-RESOURCE", "preview does not retain the contributor source identity");
  assert(preview.target === "IMPL-PATCH-001", "preview does not identify the singular semantic target");
  assert(preview.deleted.length === 1 && preview.deleted[0].includes("PATCH preserves omitted properties"), "preview removal is not scoped to the target rule");
  assert(preview.added.length === 1 && preview.added[0].includes("Prefer PUT") && preview.added[0].includes("If PATCH is required"), "preview replacement does not preserve and extend the target rule");
  assert(preview.mutation.rule.id === "IMPL-PATCH-001" && preview.mutation.sourceRelationships.some((relationship) => relationship.sourceId === "guide-new-resource"), "approved mutation does not preserve singular source and target identities");
  assert(!preview.hasMappedHostedRuleIds, "approved mutation still exports aggregate provenance mappings as action targets");
}

module.exports = { name: "contributor rule candidates", behaviorIds, viewport: { width: 768, height: 900 }, run };
