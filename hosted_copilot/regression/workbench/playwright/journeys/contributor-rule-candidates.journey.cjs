const { openWorkbench, revealCandidate, waitForWorkbenchTooltip } = require("../helpers/workbench.cjs");

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
    const previousSourceExpansion = assessmentExpansionState.has(sourceNodeId) ? assessmentExpansionState.get(sourceNodeId) : null;
    assessmentExpansionState.set(sourceNodeId, true);
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

  const proposedIdField = page.getByRole("textbox", { name: "Proposed Hosted Rule ID:" });
  const proposedIdStatus = page.locator("#proposed-hosted-rule-id-status");
  const proposedIdCounter = page.locator("#proposed-hosted-rule-id-limit");
  assert(await proposedIdField.inputValue() === "REVIEW-REPO-001", "Add candidate does not initialize from its persisted assessment identity");
  assert(await proposedIdField.getAttribute("maxlength") === "32", "proposed Hosted rule ID does not enforce the 32-character limit");
  assert(await proposedIdStatus.innerText() === "Proposed Hosted Rule ID is valid.", "persisted proposed Hosted rule ID is not initially valid");
  assert((await proposedIdStatus.locator("use").getAttribute("href"))?.endsWith("#codicon-check-compact"), "valid proposed Hosted rule ID does not use the compact check icon");

  await proposedIdField.fill("IMPL-PATCH-001");
  await page.waitForTimeout(350);
  assert((await proposedIdStatus.innerText()).includes("already assigned to an existing Hosted rule"), "catalog collision does not report the existing-rule reason");
  assert((await proposedIdStatus.locator("use").getAttribute("href"))?.endsWith("#codicon-circle-slash-compact"), "invalid proposed Hosted rule ID does not use the compact circle-slash icon");
  const blocked = await page.evaluate((candidateKey) => {
    const candidate = state.candidates.find((item) => item.key === candidateKey);
    return { plan: getPlanReadiness(candidate), preview: getPreviewReadiness() };
  }, structure.addCandidate);
  assert(!blocked.plan.ready && blocked.plan.label === "Needs valid rule ID" && !blocked.preview.ready, "catalog collision does not block plan and approval readiness");

  const fullLengthId = "IMPLEMENTATION-EVID-RULESETS-001";
  await proposedIdField.fill("CUSTOM-EVID-001");
  await page.waitForTimeout(350);
  assert(await proposedIdStatus.innerText() === "Proposed Hosted Rule ID is valid.", "collision state did not return to valid before debounce testing");
  await proposedIdField.click();
  await proposedIdField.press("Control+A");
  const mutationCount = await page.evaluate(() => {
    globalThis.__proposedIdStatusMutationCount = 0;
    globalThis.__proposedIdStatusObserver = new MutationObserver(() => { globalThis.__proposedIdStatusMutationCount += 1; });
    globalThis.__proposedIdStatusObserver.observe(document.querySelector("#proposed-hosted-rule-id-status"), { childList: true, subtree: true, characterData: true, attributes: true });
    return globalThis.__proposedIdStatusMutationCount;
  });
  assert(mutationCount === 0, "proposed Hosted rule ID mutation observer did not initialize cleanly");
  await proposedIdField.pressSequentially(fullLengthId, { delay: 10 });
  assert(await proposedIdCounter.innerText() === "32 / 32 characters", "character count does not update immediately at the maximum length");
  await page.waitForTimeout(350);
  const boundary = await page.evaluate(() => {
    globalThis.__proposedIdStatusObserver.disconnect();
    const input = document.querySelector("#proposed-hosted-rule-id");
    const status = document.querySelector("#proposed-hosted-rule-id-status");
    const counter = document.querySelector("#proposed-hosted-rule-id-limit");
    const inputStyle = getComputedStyle(input);
    const rationaleStyle = getComputedStyle(document.querySelector('[data-decision-field="rationale"]'));
    const statusRect = status.getBoundingClientRect();
    const counterRect = counter.getBoundingClientRect();
    return {
      valueLength: input.value.length,
      status: status.innerText,
      mutationCount: globalThis.__proposedIdStatusMutationCount,
      overlap: statusRect.right > counterRect.left && statusRect.bottom > counterRect.top && statusRect.top < counterRect.bottom,
      metadataOverflow: status.parentElement.scrollWidth > status.parentElement.clientWidth,
      inputOverflow: input.scrollWidth > input.clientWidth,
      stylesMatch: inputStyle.backgroundColor === rationaleStyle.backgroundColor
        && inputStyle.borderColor === rationaleStyle.borderColor
        && inputStyle.color === rationaleStyle.color
        && inputStyle.padding === rationaleStyle.padding
        && inputStyle.borderRadius === rationaleStyle.borderRadius
    };
  });
  assert(boundary.valueLength === 32 && boundary.status === "Proposed Hosted Rule ID is valid.", "full-length valid proposed Hosted rule ID was not retained");
  assert(boundary.mutationCount === 0, "unchanged valid feedback flickered while entering a valid proposed Hosted rule ID");
  assert(!boundary.overlap && !boundary.metadataOverflow && !boundary.inputOverflow, "32-character proposed Hosted rule ID overlaps or overflows at 768px");
  assert(boundary.stylesMatch, "proposed Hosted rule ID field does not match Decision Rationale control colors and geometry");

  const propagated = await page.evaluate((candidateKey) => {
    const candidate = state.candidates.find((item) => item.key === candidateKey);
    const treeId = document.querySelector(`[data-candidate-key="${CSS.escape(candidateKey)}"] .candidate-tree-copy strong`)?.textContent;
    const detailId = document.querySelector("#assessment-panel > .assessment-title .detail-identity span:last-child")?.textContent;
    switchView("plan");
    const planId = document.querySelector(`[data-plan-row="${CSS.escape(candidateKey)}"] .candidate-link`)?.textContent;
    switchView("preview");
    const previewId = [...document.querySelectorAll(".preview-change")]
      .find((item) => item.getAttribute("aria-label")?.includes(candidate.assessment.assessmentId))
      ?.querySelector(".diff-file-heading > span")?.textContent;
    const payloadDecision = buildApprovalPayload().decisions.find((item) => item.candidateId === candidate.assessment.assessmentId);
    return { treeId, detailId, planId, previewId, payloadDecision, readiness: getPreviewReadiness() };
  }, structure.addCandidate);
  assert([propagated.treeId, propagated.detailId, propagated.planId, propagated.previewId].every((value) => value === fullLengthId), "accepted proposed Hosted rule ID does not propagate across Workbench views");
  assert(propagated.payloadDecision.proposedHostedRuleId === fullLengthId && propagated.payloadDecision.hostedRuleId === null, "approval payload does not separate proposed and existing Hosted rule identities");
  assert(propagated.readiness.ready, "valid proposed Hosted rule ID does not restore approval readiness");

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
  const mappedProposedIdField = page.getByRole("textbox", { name: "Proposed Hosted Rule ID:" });
  const mappedIdentity = await page.evaluate((candidateKey) => {
    const candidate = state.candidates.find((item) => item.key === candidateKey);
    const payloadDecision = buildApprovalPayload().decisions.find((item) => item.candidateId === candidate.assessment.assessmentId);
    const sharedTargetCandidate = {
      ...candidate,
      key: `${candidate.key}:shared-target`,
      assessment: { ...candidate.assessment, assessmentId: "shared-target-reference" }
    };
    state.assessedCandidates.push(sharedTargetCandidate);
    const readiness = getPlanReadiness(candidate);
    state.assessedCandidates.pop();
    return {
      payloadDecision,
      readiness
    };
  }, structure.updateCandidate);
  assert(await mappedProposedIdField.inputValue() === "IMPL-PATCH-001" && await mappedProposedIdField.isEditable() === false, "mapped update does not expose its generated proposal identity as the immutable target ID");
  assert(mappedIdentity.payloadDecision.hostedRuleId === "IMPL-PATCH-001" && mappedIdentity.payloadDecision.proposedHostedRuleId === "IMPL-PATCH-001", "mapped update export does not preserve existing and proposed Hosted identities");
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
  await parentTitle.hover({ position: { x: 20, y: 10 } });
  await waitForWorkbenchTooltip(page);
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
