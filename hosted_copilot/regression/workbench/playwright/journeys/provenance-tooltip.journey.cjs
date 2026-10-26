const { getCssTokenColor, openWorkbench, waitForWorkbenchTooltip } = require("../helpers/workbench.cjs");

const behaviorIds = ["WB-UX-PROVENANCE-001", "WB-UX-PROVENANCE-002"];

async function run({ page, baseUrl, assert, playback }) {
  await page.emulateMedia({ reducedMotion: "no-preference" });
  await openWorkbench(page, baseUrl);
  assert(await page.evaluate(() => !matchMedia("(prefers-reduced-motion: reduce)").matches), "Tooltip journey requires normal motion");
  const disabledControls = await page.evaluate(() => {
    const probe = document.createElement("div");
    document.body.append(probe);
    try {
      return ["disabled", 'aria-disabled="true"', 'class="titlebar-icon disabled"'].map(attribute => {
        probe.innerHTML = `<button ${attribute} data-workbench-tooltip="Unavailable action" aria-label="Unavailable action"><span>Action</span></button>`;
        const button = probe.firstElementChild;
        button.classList.add("titlebar-icon");
        hideStatusTooltip();
        showWorkbenchTooltip(button);
        const style = getComputedStyle(button);
        return getWorkbenchTooltipOwner(button) === null && getWorkbenchTooltipOwner(button.firstElementChild) === null
          && !document.querySelector("#status-surface-tooltip").classList.contains("visible")
          && style.cursor === "default" && style.opacity === "0.52" && Boolean(button.getAttribute("aria-label"));
      });
    } finally { probe.remove(); hideStatusTooltip(); }
  });
  assert(disabledControls.every(Boolean), "Shared disabled controls retained tooltips, active presentation, or lost accessible names");
  await playback.show(page, "Provenance tooltip · 768px viewport");
  const roots = await page.evaluate(() => {
    const revision = state.assessedCandidates.find((candidate) => candidate.sourceType === "upstream")?.revision;
    const expected = `${revision.repository} · ${revision.configuredRef}@${revision.resolvedCommit.slice(0, 8)}`;
    const candidate = document.querySelector('#candidate-list [data-node-id="candidate:source:upstream"] .source-provenance-pill')?.textContent.trim();
    const originalAssessedCandidates = state.assessedCandidates;
    if (!originalAssessedCandidates.some((item) => item.sourceType === "upstream" && !item.assessment.hostedApplicable)) {
      const excludedContributor = structuredClone(originalAssessedCandidates.find((item) => item.sourceType === "upstream"));
      excludedContributor.key = `${excludedContributor.key}:provenance-root-probe`;
      excludedContributor.assessment.hostedApplicable = false;
      state.assessedCandidates = [...originalAssessedCandidates, excludedContributor];
      renderAssessmentResults();
    }
    setWorkspaceTab("assessment-results");
    const assessment = document.querySelector('#assessment-results-list [data-node-id="assessment:source:upstream"] .source-provenance-pill')?.textContent.trim();
    state.assessedCandidates = originalAssessedCandidates;
    renderAssessmentResults();
    setWorkspaceTab("candidate-sources");
    return { expected, candidate, assessment };
  });
  assert(roots.candidate === roots.expected && roots.assessment === roots.expected, `real Contributor Guidance roots lost provenance: ${JSON.stringify(roots)}`);
  const treeMetric = await page.evaluate(() => {
    const root = document.documentElement;
    const original = root.style.getPropertyValue("--tree-row-height");
    const initial = getWorkbenchPixelMetric("--tree-row-height");
    let changed;
    try {
      root.style.setProperty("--tree-row-height", `${initial + 4}px`);
      candidateHierarchicalView.refresh();
      const rows = [...document.querySelectorAll("#candidate-list .hierarchical-view-row")];
      changed = candidateHierarchicalView.model.nodes.every(node => node.rowHeight === initial + 4)
        && rows.length > 0 && rows.every(node => Math.abs(node.getBoundingClientRect().height - initial - 4) < 1);
    } finally {
      if (original) root.style.setProperty("--tree-row-height", original);
      else root.style.removeProperty("--tree-row-height");
      candidateHierarchicalView.refresh();
    }
    return changed && candidateHierarchicalView.model.nodes.every(node => node.rowHeight === initial);
  });
  assert(treeMetric, "Candidate tree layout and rendering do not consume the same CSS row metric");
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
    tooltip: node.dataset.workbenchTooltip,
    title: node.getAttribute("title")
  }));
  assert(contract.text === contract.tooltip && /^[^·]+ · [^@]+@[0-9a-f]{8}$/.test(contract.text), "tooltip does not retain repository, ref, and concise short-SHA provenance");
  assert(contract.title === null && !contract.text.startsWith("Contributor guidance source:"), "native or redundant provenance tooltip text remains active");

  const enterAt = async (entryX, entryY = box.y + box.height / 2) => {
    await page.mouse.move(box.x - 12, entryY);
    await page.waitForFunction(() => !document.querySelector("#status-surface-tooltip").classList.contains("visible"));
    if (!await page.evaluate(point => getWorkbenchTooltipOwner(document.elementFromPoint(point.x, point.y))
      === document.querySelector("#source-provenance-tooltip-probe .source-provenance-pill"), { x: entryX, y: entryY })) {
      throw new Error("Tooltip entry point is outside the pill hit area");
    }
    await page.mouse.move(entryX, entryY);
    await waitForWorkbenchTooltip(page);
    return page.evaluate((anchorX) => {
      const owner = document.querySelector("#source-provenance-tooltip-probe .source-provenance-pill");
      const tooltip = document.querySelector("#status-surface-tooltip");
      const ownerRect = owner.getBoundingClientRect();
      const tooltipRect = tooltip.getBoundingClientRect();
      const preferredLeft = anchorX - tooltipRect.width / 2;
      return {
        visible: getComputedStyle(tooltip).visibility === "visible",
        textMatches: tooltip.textContent === owner.textContent.trim(),
        left: tooltipRect.left,
        right: tooltipRect.right,
        expectedLeft: Math.floor(Math.min(Math.max(8, preferredLeft), innerWidth - tooltipRect.width - 8)),
        expectedTop: Math.floor(ownerRect.bottom + 6),
        top: tooltipRect.top
      };
    }, entryX);
  };

  const leftEntry = await enterAt(box.x + 2);
  const rightEntry = await enterAt(box.x + box.width - 2);
  assert(leftEntry.visible && leftEntry.textMatches, "pointer-triggered tooltip is hidden or has incorrect text");
  assert(Math.abs(leftEntry.left - leftEntry.expectedLeft) < 0.1, "left-side pointer entry is not used as the tooltip anchor");
  assert(Math.abs(rightEntry.left - rightEntry.expectedLeft) < 0.1 && rightEntry.right <= 760.1, "right-side pointer entry is not clamped to the 8px viewport inset");
  assert(Math.abs(leftEntry.top - leftEntry.expectedTop) < 0.1 && Math.abs(rightEntry.top - rightEntry.expectedTop) < 0.1 && leftEntry.top === rightEntry.top,
    "Tooltip vertical placement changed with pointer entry height instead of keeping the 6px control gap");
  const upperEntry = await enterAt(box.x + box.width / 2, box.y + box.height / 4);
  const lowerEntry = await enterAt(box.x + box.width / 2, box.y + box.height * 3 / 4);
  assert(Math.abs(upperEntry.top - upperEntry.expectedTop) < 0.1 && Math.abs(lowerEntry.top - lowerEntry.expectedTop) < 0.1 && upperEntry.top === lowerEntry.top,
    "Entering the upper and lower parts of the same control changed the tooltip's vertical gap");

  await page.mouse.move(box.x + box.width - 6, box.y + box.height / 2);
  const movement = await page.evaluate(() => {
    const tooltip = document.querySelector("#status-surface-tooltip");
    const rect = tooltip.getBoundingClientRect();
    return { visible: tooltip.classList.contains("visible"), left: rect.left, top: rect.top, pending: Boolean(workbenchTooltip.showTimer) };
  });
  assert(movement.visible && !movement.pending && movement.left === lowerEntry.left && movement.top === lowerEntry.top, "Moving within a tooltip owner dismissed, delayed, or repositioned the visible tooltip");
  const tooltipBox = await page.locator("#status-surface-tooltip").boundingBox();
  await page.mouse.move(tooltipBox.x + tooltipBox.width / 2, tooltipBox.y + tooltipBox.height / 2);
  await page.waitForFunction(() => document.querySelector("#status-surface-tooltip").matches(":hover"));
  assert(await page.locator("#status-surface-tooltip").evaluate(node => node.classList.contains("visible") && getComputedStyle(node).pointerEvents === "auto"), "The visible tooltip cannot retain hover independently of its trigger");
  await page.mouse.move(box.x + box.width - 6, box.y + box.height / 2);
  await page.keyboard.press("Escape");
  await page.mouse.move(box.x + box.width - 8, box.y + box.height / 2);
  const dismissed = await page.evaluate(() => ({
    hidden: !document.querySelector("#status-surface-tooltip").classList.contains("visible"),
    suppressed: workbenchTooltip.suppressedOwner === document.querySelector("#source-provenance-tooltip-probe .source-provenance-pill"),
    noPendingShow: workbenchTooltip.showTimer === 0
  }));
  assert(dismissed.hidden && dismissed.suppressed && dismissed.noPendingShow, "Escape did not keep the tooltip dismissed during further movement inside the same trigger");
  await enterAt(box.x + 2);
  await page.mouse.move(8, 8);
  await page.waitForFunction(() => !document.querySelector("#status-surface-tooltip").classList.contains("visible"));

  await page.mouse.move(box.x + 2, box.y + box.height / 2);
  await page.mouse.move(box.x + box.width - 2, box.y + box.height / 2);
  await waitForWorkbenchTooltip(page);
  assert(await page.evaluate(entryX => {
    const rect = document.querySelector("#status-surface-tooltip").getBoundingClientRect();
    const expectedLeft = Math.floor(Math.min(Math.max(8, entryX - rect.width / 2), innerWidth - rect.width - 8));
    return Math.abs(workbenchTooltip.anchorX - entryX) < 0.1 && Math.abs(rect.left - expectedLeft) < 0.1;
  }, box.x + 2), "Movement during the opening delay replaced the pointer entry-point anchor");
  await page.mouse.move(8, 8);
  await page.waitForFunction(() => !document.querySelector("#status-surface-tooltip").classList.contains("visible"));

  await page.evaluate(() => {
    const source = document.querySelector("#source-provenance-tooltip-probe .source-provenance-pill");
    const probe = source.cloneNode(true);
    probe.id = "source-provenance-tooltip-fallback";
    probe.style.position = "fixed";
    probe.style.right = "4px";
    probe.style.bottom = "4px";
    document.body.appendChild(probe);
  });
  const fallbackProbe = page.locator("#source-provenance-tooltip-fallback");
  const fallbackBox = await fallbackProbe.boundingBox();
  await page.mouse.move(fallbackBox.x + fallbackBox.width / 2, fallbackBox.y + fallbackBox.height / 2);
  await waitForWorkbenchTooltip(page);
  const fallback = await page.evaluate(() => {
    const probe = document.querySelector("#source-provenance-tooltip-fallback");
    const probeRect = probe.getBoundingClientRect();
    const tooltipRect = document.querySelector("#status-surface-tooltip").getBoundingClientRect();
    const result = {
      aboveGap: probeRect.top - tooltipRect.bottom,
      horizontallyContained: tooltipRect.left >= 8 && tooltipRect.right <= innerWidth - 8 + 0.1,
      verticallyContained: tooltipRect.top >= 8
    };
    probe.remove();
    return result;
  });
  assert(Math.abs(fallback.aboveGap - 6) < 1 && fallback.horizontallyContained && fallback.verticallyContained, "Tooltip does not flip above the control with the fixed 6px gap when insufficient space remains below");

  await page.evaluate(() => document.querySelector("#source-provenance-tooltip-probe").remove());

  const protectedPresentation = await page.evaluate(() => {
    const protectedRule = state.protectedRules[0];
    const issue = state.ruleIssues[0];
    if (!protectedRule || !issue) throw new Error("Tooltip fixture requires protected catalog guidance and a complete Rule Issue");
    const probe = document.createElement("div");
    probe.id = "protected-rule-information-probe";
    probe.style.cssText = "position: fixed; top: 120px; left: 260px; width: 300px; z-index: 20";
    probe.innerHTML = renderRuleIssueRule({ id: protectedRule.id, text: protectedRule.text, status: "protected", disposition: "keep", candidateKeys: [] }, issue);
    document.body.append(probe);
    const row = probe.querySelector(".protected-reference");
    const pill = row.querySelector(".catalog-status.protected");
    const body = row.querySelector(".rule-issue-rule-body");
    const mutable = document.createElement("template");
    mutable.innerHTML = renderRuleIssueRule(issue.rules.find(rule => rule.status !== "protected"), issue);
    return {
      pills: [...row.querySelectorAll(".rule-issue-rule-statuses > span")].map(node => node.textContent),
      textColor: getComputedStyle(body).color,
      cursor: getComputedStyle(body).cursor,
      selectable: getComputedStyle(body).userSelect === "text",
      noEditingControls: !body.querySelector('input, textarea, [contenteditable="true"]'),
      plainStatus: !pill.hasAttribute("tabindex") && !pill.hasAttribute("aria-describedby") && getWorkbenchTooltipOwner(pill) === null && !row.hasAttribute("tabindex")
        && getWorkbenchTooltipOwner(row) === null && getWorkbenchTooltipOwner(body) === null && getWorkbenchTooltipOwner(row.querySelector(".immutable")) === null,
      mutableActionRetained: Boolean(mutable.content.querySelector(".decision-badge")) && !mutable.content.querySelector(".immutable"),
      session: JSON.stringify(state.session)
    };
  });
  assert(protectedPresentation.pills.join(",") === "Protected,Immutable" && protectedPresentation.mutableActionRetained, "Protected references retain a suggested action or mutable rules lost their action pill");
  assert(protectedPresentation.textColor === await getCssTokenColor(page, "--disabled-foreground") && protectedPresentation.cursor === "default"
    && protectedPresentation.selectable && protectedPresentation.noEditingControls, "Protected references lost read-only styling or selection");
  assert(protectedPresentation.plainStatus, "Protected status or rule text still triggers the protection explanation");
  const noticePresentation = await page.evaluate(() => {
    const base = state.ruleIssues[0];
    const protectedRule = state.protectedRules[0];
    const issue = {
      ...structuredClone(base),
      id: `${base.id}:protected-notice`,
      classification: "protected-conflict",
      label: "Protected",
      bannerTitle: "Protected rule conflict",
      bannerMessage: "The proposed rule conflicts with protected guidance.",
      ruleIds: [...new Set([...base.ruleIds, protectedRule.id])],
      protectedRuleIds: [protectedRule.id],
      rules: [...base.rules, { id: protectedRule.id, text: protectedRule.text, status: "protected", disposition: "keep", candidateKeys: [] }]
    };
    const probe = document.querySelector("#protected-rule-information-probe");
    probe.innerHTML = renderRuleIssueContent(issue);
    const warning = probe.querySelector(".rule-issue-banner");
    const notice = probe.querySelector(".protected-rule-information");
    const expectedInset = getWorkbenchPixelMetric("--detail-pane-inset");
    const expectedSectionGap = getWorkbenchPixelMetric("--section-gap");
    const expectedLabelGap = getWorkbenchPixelMetric("--section-label-gap");
    const headingGaps = [...probe.querySelectorAll(":scope > .section-label")].every(node =>
      Math.abs(node.getBoundingClientRect().top - node.previousElementSibling.getBoundingClientRect().bottom - expectedSectionGap) < 1
      && Math.abs(node.nextElementSibling.getBoundingClientRect().top - node.getBoundingClientRect().bottom - expectedLabelGap) < 1);
    const content = notice.textContent;
    const adjacent = warning.nextElementSibling === notice;
    const matchingGap = Math.abs(notice.getBoundingClientRect().top - warning.getBoundingClientRect().bottom - expectedInset) < 1;
    const allProtected = RULE_ISSUE_FILTERS.find(filter => filter.key === "protected").classifications.every(classification => {
      const template = document.createElement("template");
      template.innerHTML = renderRuleIssueContent({ ...issue, classification });
      return template.content.querySelectorAll(".protected-rule-information").length === 1;
    });
    const ordinary = document.createElement("template");
    ordinary.innerHTML = renderRuleIssueContent(base);
    state.dismissedRuleIssueBannerKeys.add(issue.id);
    let dismissed;
    try {
      probe.innerHTML = renderRuleIssueContent(issue);
      const remaining = probe.querySelector(".protected-rule-information");
      dismissed = probe.firstElementChild === remaining && getComputedStyle(remaining).marginTop === "0px";
    } finally { state.dismissedRuleIssueBannerKeys.delete(issue.id); }
    const lineHeight = getComputedStyle(probe.querySelector(".protected-rule-information p")).lineHeight;
    probe.hidden = true;
    const keyboardButton = document.createElement("button");
    keyboardButton.id = "shared-keyboard-tooltip-probe";
    keyboardButton.type = "button";
    keyboardButton.className = "titlebar-icon";
    keyboardButton.setAttribute("aria-label", "Tooltip fixture");
    keyboardButton.dataset.workbenchTooltip = "Tooltip fixture";
    keyboardButton.innerHTML = icon("info");
    keyboardButton.style.cssText = "position: fixed; top: 80px; left: 260px; z-index: 21";
    document.body.append(keyboardButton);
    return {
      adjacent,
      matchingGap,
      headingGaps,
      allProtected,
      ordinaryHasNoNotice: !ordinary.content.querySelector(".protected-rule-information"),
      dismissed,
      content: content.includes("Edit the protected source file directly") && content.includes("-Rebuild") && content.includes("significant processing time"),
      lineHeight
    };
  });
  assert(noticePresentation.adjacent && noticePresentation.matchingGap && noticePresentation.headingGaps, "Protected notice or equivalent section headings do not use shared layout spacing");
  assert(noticePresentation.allProtected && noticePresentation.ordinaryHasNoNotice && noticePresentation.dismissed && noticePresentation.content,
    "Protected guidance is missing, applies to an ordinary issue, or disappears with the warning");
  assert(noticePresentation.lineHeight === "20px", "Information panels do not resolve the shared body line height");
  await page.mouse.move(8, 8);
  await page.locator("#shared-keyboard-tooltip-probe").focus();
  await page.keyboard.press("Shift+Tab");
  await page.keyboard.press("Tab");
  await waitForWorkbenchTooltip(page);
  const keyboard = await page.evaluate(() => {
    const pill = document.querySelector("#shared-keyboard-tooltip-probe");
    const tooltip = document.querySelector("#status-surface-tooltip");
    const rect = tooltip.getBoundingClientRect();
    const style = getComputedStyle(pill);
    const outline = [style.outlineStyle, style.outlineWidth, style.outlineColor, style.outlineOffset].join("|");
    const reference = document.querySelector("button.workspace-tab");
    reference.focus({ preventScroll: true });
    const referenceStyle = getComputedStyle(reference);
    const expectedOutline = [referenceStyle.outlineStyle, referenceStyle.outlineWidth, referenceStyle.outlineColor, referenceStyle.outlineOffset].join("|");
    pill.focus({ preventScroll: true });
    return {
      focused: document.activeElement === pill && pill.matches(":focus-visible"),
      matchingFocus: outline === expectedOutline,
      belowGap: rect.top - pill.getBoundingClientRect().bottom,
      correctExplanation: tooltip.textContent === pill.dataset.workbenchTooltip,
      borderColor: getComputedStyle(tooltip).borderColor,
      noLargeFade: getComputedStyle(tooltip, "::after").content === "none"
    };
  });
  assert(keyboard.focused && keyboard.matchingFocus && keyboard.correctExplanation && keyboard.belowGap >= 5 && keyboard.belowGap <= 6, "Keyboard tooltips or protected-reference focus no longer use the shared element-anchored treatment");
  assert(keyboard.borderColor === await getCssTokenColor(page, "--muted") && keyboard.noLargeFade, "Shared tooltips lost the lighter border or restored the oversized fade");
  await page.keyboard.press("Escape");
  assert(await page.evaluate(() => {
    const pill = document.querySelector("#shared-keyboard-tooltip-probe");
    return document.activeElement === pill && workbenchTooltip.suppressedOwner === pill && workbenchTooltip.showTimer === 0
      && !document.querySelector("#status-surface-tooltip").classList.contains("visible");
  }), "Escape changed keyboard focus or failed to dismiss and suppress its tooltip");
  await page.keyboard.press("Shift+Tab");
  await page.keyboard.press("Tab");
  await waitForWorkbenchTooltip(page);
  assert(await page.evaluate(() => workbenchTooltip.owner === document.querySelector("#shared-keyboard-tooltip-probe")), "A fresh keyboard-focus entry did not restore its tooltip");
  assert(await page.evaluate(session => JSON.stringify(state.session) === session, protectedPresentation.session), "Protected-reference inspection changed saved decisions");
  await page.evaluate(() => {
    document.querySelector("#protected-rule-information-probe").remove();
    document.querySelector("#shared-keyboard-tooltip-probe").remove();
    hideStatusTooltip();
  });
}

module.exports = { name: "provenance tooltip", behaviorIds, viewport: { width: 768, height: 900 }, run };
