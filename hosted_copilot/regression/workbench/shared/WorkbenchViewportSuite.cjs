let assertionCount = 0;

function assert(condition, message) {
  assertionCount += 1;
  if (!condition) throw new Error(message);
}

async function waitForWorkbench(page) {
  await page.waitForFunction(() => Number(document.querySelector("#catalog-count")?.textContent) > 0);
}

async function settleLayout(page, browserDriver, label) {
  if (browserDriver.beforeValidation) await browserDriver.beforeValidation(page, label);
  await page.evaluate(async () => {
    if (document.fonts?.ready) await document.fonts.ready;
    await new Promise((resolve) => requestAnimationFrame(() => requestAnimationFrame(resolve)));
  });
}

async function activateCandidateDetails(page) {
  await page.evaluate(() => {
    document.querySelector('[data-view="catalog"]').click();
    document.querySelector('[data-workspace-tab="candidate-sources"]').click();
    document.querySelector('[data-candidate-pane="candidates"]').click();
    const source = [...document.querySelectorAll("#candidate-list > details.candidate-source-root")]
      .find((item) => item.querySelector("[data-candidate-key]"));
    source.open = true;
    source.querySelector("[data-candidate-key]").click();
  });
}

async function activateAssessmentDetails(page) {
  await page.evaluate(() => {
    document.querySelector('[data-workspace-tab="assessment-results"]').click();
    document.querySelector('[data-assessment-pane="details"]').click();
    const detail = document.querySelector("#assessment-results-detail");
    detail.innerHTML = '<div class="assessment-title"><div><div class="source-line detail-identity"><span>Interactive rule</span><span>/</span><span>LAYOUT-PROBE</span></div><h2 class="detail-rule-title">Assessment layout probe</h2></div><span class="status-badge warning">Excluded</span></div><div class="assessment-content"></div>';
    const panel = detail.querySelector(":scope > .assessment-content");
    const probe = document.createElement("div");
    probe.dataset.layoutProbe = "assessment";
    probe.style.height = "1600px";
    panel.appendChild(probe);
  });
}

async function activateViewWithProbe(page, view, ownerSelector) {
  await page.evaluate(({ view, ownerSelector }) => {
    document.querySelector(`[data-view="${view}"]`).click();
    const owner = document.querySelector(ownerSelector);
    const probe = document.createElement("div");
    probe.dataset.layoutProbe = view;
    probe.style.width = "1200px";
    probe.style.height = "1600px";
    owner.appendChild(probe);
  }, { view, ownerSelector });
}

async function assertContainedScroll(page, width, name, ownerSelector, fixedSelector) {
  const result = await page.evaluate(({ ownerSelector, fixedSelector }) => {
    const owner = document.querySelector(ownerSelector);
    const fixed = document.querySelector(fixedSelector);
    const fixedTop = fixed.getBoundingClientRect().top;
    owner.scrollTop = 320;
    owner.scrollLeft = 160;
    return {
      documentHeight: document.documentElement.scrollHeight,
      documentWidth: document.documentElement.scrollWidth,
      viewportHeight: innerHeight,
      viewportWidth: innerWidth,
      windowY: scrollY,
      ownerClientHeight: owner.clientHeight,
      ownerScrollHeight: owner.scrollHeight,
      ownerScrollTop: owner.scrollTop,
      fixedTop,
      fixedTopAfter: fixed.getBoundingClientRect().top,
    };
  }, { ownerSelector, fixedSelector });

  assert(result.documentHeight <= result.viewportHeight + 1, `${width}px ${name}: document scrolls vertically`);
  assert(result.documentWidth <= result.viewportWidth + 1, `${width}px ${name}: document scrolls horizontally`);
  assert(result.windowY === 0, `${width}px ${name}: window scroll position changed`);
  assert(result.ownerScrollHeight > result.ownerClientHeight, `${width}px ${name}: designated pane is not scrollable`);
  assert(result.ownerScrollTop > 0, `${width}px ${name}: designated pane did not accept scroll`);
  assert(result.fixedTopAfter === result.fixedTop, `${width}px ${name}: fixed view controls moved with pane content`);
}

async function assertRuleActionPreservesContext(page, width) {
  const before = await page.evaluate(() => {
    const body = document.querySelector("#candidate-sources-panel .assessment-panel > .assessment-content");
    const control = [...document.querySelectorAll(".action-options [data-rule-action]")]
      .find((item) => !item.checked && !item.disabled);
    if (!control) return { controlAvailable: false };
    const bodyRect = body.getBoundingClientRect();
    const controlRect = control.getBoundingClientRect();
    const controlTop = body.scrollTop + controlRect.top - bodyRect.top;
    body.scrollTop = Math.max(0, controlTop - (body.clientHeight - controlRect.height) / 2);
    control.focus({ preventScroll: true });
    body.dataset.ruleActionContextProbe = "true";
    return {
      controlAvailable: true,
      action: control.dataset.ruleAction,
      scrollTop: body.scrollTop,
      scrollHeight: body.scrollHeight,
      clientHeight: body.clientHeight,
    };
  });

  assert(before.controlAvailable, `${width}px Rule Action: no alternative action is available`);
  await page.click(`.action-options [data-rule-action="${before.action}"]`);

  const result = await page.evaluate(({ action, scrollTop }) => {
    const currentBody = document.querySelector("#candidate-sources-panel .assessment-panel > .assessment-content");
    const control = document.querySelector(`.action-options [data-rule-action="${action}"]`);
    const selectedBadge = document.querySelector("#candidate-sources-panel .assessment-title .decision-badge");
    const bodyPreserved = currentBody.dataset.ruleActionContextProbe === "true";
    delete currentBody.dataset.ruleActionContextProbe;
    return {
      bodyPreserved,
      scrollPreserved: Math.abs(currentBody.scrollTop - scrollTop) < 0.1,
      scrollTopBefore: scrollTop,
      scrollTopAfter: currentBody.scrollTop,
      scrollHeightAfter: currentBody.scrollHeight,
      clientHeightAfter: currentBody.clientHeight,
      focusPreserved: document.activeElement === control,
      selectionPreserved: control.checked && selectedBadge?.textContent.trim().toLowerCase().replaceAll(" ", "-") === control.dataset.ruleAction,
    };
  }, before);

  assert(result.bodyPreserved, `${width}px Rule Action: Details body was replaced`);
  assert(result.scrollPreserved, `${width}px Rule Action ${before.action}: Details scroll position changed from ${result.scrollTopBefore}/${before.scrollHeight}/${before.clientHeight} to ${result.scrollTopAfter}/${result.scrollHeightAfter}/${result.clientHeightAfter}`);
  assert(result.focusPreserved, `${width}px Rule Action: selected radio lost focus`);
  assert(result.selectionPreserved, `${width}px Rule Action: selected action and header badge diverged`);
}

async function assertPlanTogglePreservesContext(page, width) {
  const before = await page.evaluate(() => {
    const panel = document.querySelector("#candidate-sources-panel .assessment-panel");
    const body = panel.querySelector(":scope > .assessment-content");
    const control = body.querySelector("[data-plan-toggle]");
    if (!control || control.checked) return { controlAvailable: false };
    const bodyRect = body.getBoundingClientRect();
    const controlRect = control.getBoundingClientRect();
    const controlTop = body.scrollTop + controlRect.top - bodyRect.top;
    body.scrollTop = Math.max(0, controlTop - (body.clientHeight - controlRect.height) / 2);
    control.focus({ preventScroll: true });
    body.dataset.planToggleContextProbe = "true";
    return {
      controlAvailable: true,
      scrollTop: body.scrollTop,
      headerHeight: panel.querySelector(":scope > .assessment-title").getBoundingClientRect().height,
    };
  });

  assert(before.controlAvailable, `${width}px Promotion Plan toggle: unchecked control is unavailable`);
  await page.click("#candidate-sources-panel [data-plan-toggle]");

  const result = await page.evaluate(({ scrollTop, headerHeight }) => {
    const panel = document.querySelector("#candidate-sources-panel .assessment-panel");
    const currentBody = panel.querySelector(":scope > .assessment-content");
    const control = currentBody.querySelector("[data-plan-toggle]");
    const bodyPreserved = currentBody.dataset.planToggleContextProbe === "true";
    return {
      bodyPreserved,
      scrollPreserved: Math.abs(currentBody.scrollTop - scrollTop) < 0.1,
      focusPreserved: document.activeElement === control,
      selectionPreserved: control.checked,
      headerPreserved: Math.abs(panel.querySelector(":scope > .assessment-title").getBoundingClientRect().height - headerHeight) < 0.1,
    };
  }, before);

  assert(result.bodyPreserved, `${width}px Promotion Plan toggle: Details body was replaced`);
  assert(result.scrollPreserved, `${width}px Promotion Plan toggle: Details scroll position changed`);
  assert(result.focusPreserved, `${width}px Promotion Plan toggle: checkbox lost focus`);
  assert(result.selectionPreserved, `${width}px Promotion Plan toggle: checkbox selection was not retained`);
  assert(result.headerPreserved, `${width}px Promotion Plan toggle: fixed header height changed`);

  await page.click("#candidate-sources-panel [data-plan-toggle]");
  const removed = await page.evaluate(({ scrollTop, headerHeight }) => {
    const panel = document.querySelector("#candidate-sources-panel .assessment-panel");
    const currentBody = panel.querySelector(":scope > .assessment-content");
    const control = currentBody.querySelector("[data-plan-toggle]");
    const result = {
      bodyPreserved: currentBody.dataset.planToggleContextProbe === "true",
      scrollPreserved: Math.abs(currentBody.scrollTop - scrollTop) < 0.1,
      focusPreserved: document.activeElement === control,
      selectionRemoved: !control.checked,
      detailsPreserved: document.querySelector('[data-candidate-pane="details"]')?.getAttribute("aria-selected") === "true",
      headerPreserved: Math.abs(panel.querySelector(":scope > .assessment-title").getBoundingClientRect().height - headerHeight) < 0.1,
    };
    delete currentBody.dataset.planToggleContextProbe;
    return result;
  }, before);

  assert(removed.bodyPreserved, `${width}px Promotion Plan toggle removal: Details body was replaced`);
  assert(removed.scrollPreserved, `${width}px Promotion Plan toggle removal: Details scroll position changed`);
  assert(removed.focusPreserved, `${width}px Promotion Plan toggle removal: checkbox lost focus`);
  assert(removed.selectionRemoved, `${width}px Promotion Plan toggle removal: checkbox remained selected`);
  assert(removed.detailsPreserved, `${width}px Promotion Plan toggle removal: navigation left Details`);
  assert(removed.headerPreserved, `${width}px Promotion Plan toggle removal: fixed header height changed`);

  await page.evaluate(async () => {
    const sessionId = localStorage.getItem("hosted-rule-workbench.active-session");
    const database = await new Promise((resolve, reject) => {
      const request = indexedDB.open("hosted-rule-workbench");
      request.onsuccess = () => resolve(request.result);
      request.onerror = () => reject(request.error);
    });
    await new Promise((resolve, reject) => {
      const request = database.transaction("sessions", "readonly").objectStore("sessions").get(sessionId);
      request.onsuccess = () => resolve(request.result);
      request.onerror = () => reject(request.error);
    });
    database.close();
  });
}

async function assertPlanMembershipSynchronizesAcrossPanes(page, width) {
  const before = await page.evaluate(() => {
    const detailsBody = document.querySelector("#candidate-sources-panel .assessment-panel > .assessment-content");
    const detailsToggle = detailsBody.querySelector("[data-plan-toggle]");
    const activeRow = document.querySelector("#candidate-list [data-candidate-key][aria-current=\"true\"]");
    if (!detailsToggle || !activeRow || detailsToggle.checked) return { controlsAvailable: false };
    detailsToggle.click();
    return {
      controlsAvailable: true,
      candidateKey: activeRow.dataset.candidateKey,
      detailsChecked: detailsToggle.checked,
      treeChecked: activeRow.querySelector("[data-decision-key]").checked,
    };
  });

  assert(before.controlsAvailable, `${width}px Membership synchronization: controls are unavailable`);
  assert(before.detailsChecked && before.treeChecked, `${width}px Membership synchronization: Details check did not update the tree`);

  await page.click('[data-candidate-pane="candidates"]');
  await page.evaluate((candidateKey) => {
    const row = document.querySelector(`#candidate-list [data-candidate-key="${candidateKey}"]`);
    row.closest("details.candidate-source-root").open = true;
    const category = row.closest("details.candidate-category");
    if (category) category.open = true;
  }, before.candidateKey);

  const openState = await page.evaluate((candidateKey) => {
    const row = document.querySelector(`#candidate-list [data-candidate-key="${candidateKey}"]`);
    return {
      sourceOpen: row.closest("details.candidate-source-root").open,
      categoryOpen: row.closest("details.candidate-category")?.open ?? true,
    };
  }, before.candidateKey);
  await page.click(`#candidate-list [data-candidate-key="${before.candidateKey}"] [data-decision-key]`);

  const treeResult = await page.evaluate((candidateKey) => {
    const row = document.querySelector(`#candidate-list [data-candidate-key="${candidateKey}"]`);
    return {
      unchecked: !row.querySelector("[data-decision-key]").checked,
      selected: row.getAttribute("aria-current") === "true",
      sourceOpen: row.closest("details.candidate-source-root").open,
      categoryOpen: row.closest("details.candidate-category")?.open ?? true,
    };
  }, before.candidateKey);
  assert(treeResult.unchecked, `${width}px Membership synchronization: tree checkbox remained checked`);
  assert(treeResult.selected, `${width}px Membership synchronization: active tree selection changed`);
  assert(treeResult.sourceOpen === openState.sourceOpen && treeResult.categoryOpen === openState.categoryOpen, `${width}px Membership synchronization: tree disclosures collapsed`);

  await page.click('[data-candidate-pane="details"]');
  const detailsResult = await page.evaluate(() => ({
    unchecked: !document.querySelector("#candidate-sources-panel [data-plan-toggle]").checked,
    detailsActive: document.querySelector('[data-candidate-pane="details"]')?.getAttribute("aria-selected") === "true",
  }));
  assert(detailsResult.unchecked && detailsResult.detailsActive, `${width}px Membership synchronization: tree uncheck did not update Details`);
}

async function assertRationaleSaveLayout(page, width) {
  const result = await page.evaluate(() => {
    const heading = document.querySelector("#candidate-sources-panel .rationale-heading");
    const label = heading?.querySelector(".control-subtitle");
    const button = heading?.querySelector("[data-rationale-save]");
    const icon = button?.querySelector("svg");
    const draftButton = document.querySelector(".title-draft-menu > summary");
    if (!heading || !label || !button || !icon || !draftButton) return { available: false };

    const originalDisabled = button.disabled;
    button.disabled = false;
    const enabledStyle = getComputedStyle(button);
    const draftStyle = getComputedStyle(draftButton);
    const buttonRect = button.getBoundingClientRect();
    const labelRect = label.getBoundingClientRect();
    const iconRect = icon.getBoundingClientRect();
    const headingRect = heading.getBoundingClientRect();
    const toolbarVisualMatch = ["height", "padding", "color", "backgroundColor", "border", "borderRadius"]
      .every((property) => enabledStyle[property] === draftStyle[property]);
    const enabledCursor = enabledStyle.cursor;
    button.disabled = true;
    const disabledCursor = getComputedStyle(button).cursor;
    button.disabled = originalDisabled;

    return {
      available: true,
      accessibleIconOnly: !button.textContent.trim()
        && button.getAttribute("aria-label")?.startsWith("Save decision rationale")
        && button.dataset.workbenchTooltip.startsWith("Save")
        && icon.querySelector("use")?.getAttribute("href")?.endsWith("#codicon-save"),
      toolbarVisualMatch: toolbarVisualMatch && buttonRect.width === 34 && buttonRect.height === 34,
      baselineAligned: Math.abs(iconRect.bottom - labelRect.bottom) < 0.1,
      cursorsCorrect: enabledCursor === "pointer" && disabledCursor === "default",
      contained: labelRect.right <= buttonRect.left + 0.1 && buttonRect.right <= headingRect.right + 0.1 && heading.scrollWidth <= heading.clientWidth,
      containmentMetrics: {
        labelRight: labelRect.right,
        buttonLeft: buttonRect.left,
        buttonRight: buttonRect.right,
        headingRight: headingRect.right,
        scrollWidth: heading.scrollWidth,
        clientWidth: heading.clientWidth
      },
    };
  });

  assert(result.available, `${width}px Decision Rationale save: control is unavailable`);
  assert(result.accessibleIconOnly, `${width}px Decision Rationale save: icon-only accessibility contract is invalid`);
  assert(result.toolbarVisualMatch, `${width}px Decision Rationale save: toolbar style or hit target diverged from Draft options`);
  assert(result.baselineAligned, `${width}px Decision Rationale save: icon and label bottom edges are not aligned`);
  assert(result.cursorsCorrect, `${width}px Decision Rationale save: enabled or disabled cursor is incorrect`);
  assert(result.contained, `${width}px Decision Rationale save: label and action overlap or overflow (${JSON.stringify(result.containmentMetrics)})`);
}

async function assertOverridesDecoration(page, width) {
  const result = await page.evaluate(() => {
    const sessionSnapshot = structuredClone(state.session);
    const candidate = state.candidates.find((item) => item.assessment.hostedApplicable);
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
        rationale: "Viewport regression override.",
        recordedAt: new Date().toISOString(),
        recordedBy: { type: "github-cli", login: "fixture-codeowner" }
      };
      state.session.decisions[candidate.key] = { ...defaultDecision(candidate), ...createPlanMembership("override") };
      renderCandidateList();

      const root = document.querySelector("#candidate-list > .candidate-overrides-root");
      const row = root.querySelector(`[data-candidate-key="${candidate.key}"]`);
      const summary = root.querySelector(":scope > summary");
      const needsInputColor = resolveColor("--modified-resource");
      const needsInputValid = root.classList.contains("candidate-aggregate-needs-input")
        && row.classList.contains("candidate-decoration-needs-input")
        && summary.dataset.workbenchTooltip === "1 selected, 1 needs input"
        && summary.querySelector(".candidate-decoration-description").textContent === "1 selected, 1 needs input"
        && [summary.querySelector(".candidate-parent-label > strong"), summary.querySelector(".candidate-parent-decoration-icon"), row.querySelector(".candidate-tree-copy strong"), row.querySelector(".candidate-decoration-icon")]
          .every((node) => getComputedStyle(node).color === needsInputColor);

      state.session.decisions[candidate.key] = {
        ...state.session.decisions[candidate.key],
        action: assessment.recommendation,
        rationale: getBulkDecisionRationale(candidate, assessment.recommendation)
      };
      syncCandidateTreeRows();
      const readyColor = resolveColor("--added-resource");
      const readyValid = root.classList.contains("candidate-aggregate-ready")
        && row.classList.contains("candidate-decoration-ready")
        && summary.dataset.workbenchTooltip === "1 selected, all ready for promotion"
        && [summary.querySelector(".candidate-parent-label > strong"), summary.querySelector(".candidate-parent-decoration-icon"), row.querySelector(".candidate-tree-copy strong"), row.querySelector(".candidate-decoration-icon")]
          .every((node) => getComputedStyle(node).color === readyColor);

      return { needsInputValid, readyValid };
    } finally {
      state.session = sessionSnapshot;
      renderCandidateList();
    }
  });

  assert(result.needsInputValid, `${width}px Overrides decorations: needs-input state or singular description is incorrect`);
  assert(result.readyValid, `${width}px Overrides decorations: ready state did not color the root label, icon, and leaf consistently`);
  const cleanedUp = await page.evaluate(() => !document.querySelector("#candidate-list > .candidate-overrides-root"));
  assert(cleanedUp, `${width}px Overrides decorations: regression probe did not restore the candidate tree`);
}

async function assertBulkActionsPreserveContext(page, width) {
  await page.click('[data-candidate-pane="candidates"]');
  const authorization = await page.evaluate(() => {
    globalThis.__HOSTED_RULE_WORKBENCH__.maintainerIdentity = {
      status: "unauthorized",
      login: "fixture-viewer",
      isCodeOwner: false,
      reason: "The authenticated GitHub user is not a CODEOWNER for Hosted Toolkit changes."
    };
    renderBulkActions();
    const commands = [...document.querySelectorAll("#bulk-actions button")];
    const unauthorizedDisabled = commands.every((button) => button.disabled);
    globalThis.__HOSTED_RULE_WORKBENCH__.maintainerIdentity = {
      status: "validated",
      login: "fixture-codeowner",
      isCodeOwner: true,
      reason: null
    };
    renderBulkActions();
    return { unauthorizedDisabled };
  });
  assert(authorization.unauthorizedDisabled, `${width}px Bulk Actions: non-CODEOWNER commands remain enabled`);
  const trigger = await page.$("#bulk-actions > summary");
  const menu = await page.$("#bulk-actions .bulk-actions-menu");
  assert(trigger && menu, `${width}px Bulk Actions: menu controls are unavailable`);

  await trigger.click();
  const triggerBox = await trigger.boundingBox();
  const menuBox = await menu.boundingBox();
  await page.mouse.move(triggerBox.x + triggerBox.width / 2, triggerBox.y + triggerBox.height / 2);
  await page.mouse.move(menuBox.x + menuBox.width / 2, menuBox.y - 2);
  await new Promise((resolve) => setTimeout(resolve, 250));
  const openAcrossGap = await page.$eval("#bulk-actions", (node) => node.open);
  await page.mouse.move(menuBox.x + menuBox.width / 2, menuBox.y + 18);
  await new Promise((resolve) => setTimeout(resolve, 250));
  const openWhileReading = await page.$eval("#bulk-actions", (node) => node.open);
  await page.mouse.move(Math.max(0, menuBox.x - 40), menuBox.y + menuBox.height + 40);
  const closedAfterLeave = await page.$eval("#bulk-actions", (node) => !node.open);

  const result = await page.evaluate(async () => {
    const candidateList = document.querySelector("#candidate-list");
    const firstRow = candidateList.querySelector("[data-candidate-key]");
    const sessionSnapshot = structuredClone(state.session);
    state.session.decisions = {};
    state.session.bulkOperations = [];
    renderBulkSelectionOutputs();
    const manualCandidate = getBulkActionCandidates("actionable")[0];
    state.session.decisions[manualCandidate.key] = {
      ...defaultDecision(manualCandidate),
      action: "defer",
      rationale: "Manual decision retained during bulk selection.",
      ...createPlanMembership()
    };
    const manualDecisionBefore = JSON.stringify(state.session.decisions[manualCandidate.key]);
    let rootChildReplacements = 0;
    const observer = new MutationObserver((records) => {
      rootChildReplacements += records.filter((record) => record.type === "childList").length;
    });
    observer.observe(candidateList, { childList: true });
    candidateList.querySelectorAll("details").forEach((node) => { node.open = false; });
    const planCountBefore = Object.values(state.session.decisions).filter((decision) => decision.inPlan).length;
    document.querySelector('#bulk-actions [data-bulk-scope="actionable"]').click();
    const remainedCollapsedAfterAdd = !document.querySelector("#candidate-list details[open]");
    const firstRowPreservedAfterAdd = candidateList.querySelector("[data-candidate-key]") === firstRow;
    const disabledCursor = getComputedStyle(document.querySelector('#bulk-actions [data-bulk-scope="actionable"]')).cursor;
    const operation = getLatestBulkOperation();
    const bulkDecisionsComplete = operation.candidateKeys.every((key) => {
      const candidate = state.candidates.find((item) => item.key === key);
      const decision = state.session.decisions[key];
      const recommendation = getAssessment(candidate, decision).recommendation;
      return decision.action === recommendation
        && decision.rationale === getBulkDecisionRationale(candidate, recommendation)
        && decision.inPlan
        && decision.planMembershipSource === "bulk"
        && decision.bulkOperationId === operation.id;
    });
    const operationAuditValid = operation.recordedBy.type === "github-cli"
      && operation.recordedBy.login === "fixture-codeowner"
      && operation.candidateKeys.every((key) => operation.candidateSourceHashes[key] === state.session.decisions[key].sourceHash);
    const manualDecisionPreserved = !operation.candidateKeys.includes(manualCandidate.key)
      && JSON.stringify(state.session.decisions[manualCandidate.key]) === manualDecisionBefore;

    const decoratedRow = [...candidateList.querySelectorAll("[data-candidate-key]")]
      .find((row) => operation.candidateKeys.includes(row.dataset.candidateKey)
        && row.closest("details.candidate-category")?.dataset.category);
    const decoratedCandidate = state.candidates.find((candidate) => candidate.key === decoratedRow.dataset.candidateKey);
    const decoratedCategory = decoratedRow.closest("details.candidate-category");
    const decoratedSource = decoratedRow.closest("details.candidate-source-root");
    const leafIcon = decoratedRow.querySelector(".candidate-decoration-icon");
    const categorySummary = decoratedCategory.querySelector(":scope > summary");
    const sourceSummary = decoratedSource.querySelector(":scope > summary");
    const categoryIcon = categorySummary.querySelector(".candidate-parent-decoration-icon");
    const sourceIcon = sourceSummary.querySelector(".candidate-parent-decoration-icon");
    const resolveColor = (token) => {
      const probe = document.createElement("span");
      probe.style.color = `var(${token})`;
      document.body.appendChild(probe);
      const color = getComputedStyle(probe).color;
      probe.remove();
      return color;
    };
    const addedColor = resolveColor("--added-resource");
    const modifiedColor = resolveColor("--modified-resource");
    const decorationPaletteValid = getComputedStyle(document.documentElement).getPropertyValue("--added-resource").trim() === "#78a680"
      && getComputedStyle(document.documentElement).getPropertyValue("--modified-resource").trim() === "#e2c08d";
    const readyDecorationValid = decoratedRow.classList.contains("candidate-decoration-ready")
      && decoratedCategory.classList.contains("candidate-aggregate-ready")
      && decoratedSource.classList.contains("candidate-aggregate-ready")
      && !leafIcon.hasAttribute("hidden") && !categoryIcon.hasAttribute("hidden") && !sourceIcon.hasAttribute("hidden")
      && leafIcon.querySelector("use").getAttribute("href").endsWith("#codicon-diff-modified")
      && [decoratedRow.querySelector(".candidate-tree-copy strong"), leafIcon, categorySummary.querySelector("strong"), categoryIcon, sourceSummary.querySelector("strong"), sourceIcon]
        .every((node) => getComputedStyle(node).color === addedColor);
    const parentDecorationPlacement = Math.abs(decoratedRow.querySelector(".candidate-tree-copy").getBoundingClientRect().right - leafIcon.getBoundingClientRect().right) < 0.1
      && Math.abs(categorySummary.querySelector(".candidate-parent-label").getBoundingClientRect().right - categoryIcon.getBoundingClientRect().right) < 0.1
      && Math.abs(categorySummary.querySelector(".count-badge").getBoundingClientRect().left - categoryIcon.getBoundingClientRect().right - 8) < 0.1
      && Math.abs(sourceSummary.querySelector(".source-summary-label").getBoundingClientRect().right - sourceIcon.getBoundingClientRect().right) < 0.1
      && Math.abs(sourceSummary.querySelector(".count-badge").getBoundingClientRect().left - sourceIcon.getBoundingClientRect().right - 8) < 0.1;
    const decorationAccessibilityValid = leafIcon.getAttribute("aria-hidden") === "true"
      && leafIcon.dataset.workbenchTooltip === "Selected, ready for promotion"
      && decoratedRow.querySelector(".candidate-decoration-description").textContent === "Selected, ready for promotion"
      && categorySummary.dataset.workbenchTooltip.endsWith("all ready for promotion")
      && sourceSummary.dataset.workbenchTooltip.endsWith("all ready for promotion");

    const originalRationale = state.session.decisions[decoratedCandidate.key].rationale;
    state.session.decisions[decoratedCandidate.key].rationale = "";
    syncCandidateTreeRows();
    const needsInputWins = decoratedRow.classList.contains("candidate-decoration-needs-input")
      && decoratedCategory.classList.contains("candidate-aggregate-needs-input")
      && decoratedSource.classList.contains("candidate-aggregate-needs-input")
      && [decoratedRow.querySelector(".candidate-tree-copy strong"), leafIcon, categorySummary.querySelector("strong"), categoryIcon, sourceSummary.querySelector("strong"), sourceIcon]
        .every((node) => getComputedStyle(node).color === modifiedColor)
      && leafIcon.dataset.workbenchTooltip === "Selected, needs input before promotion"
      && categorySummary.dataset.workbenchTooltip.endsWith("1 needs input")
      && sourceSummary.dataset.workbenchTooltip.endsWith("1 needs input");
    state.session.decisions[decoratedCandidate.key].rationale = originalRationale;
    syncCandidateTreeRows();

    const source = [...document.querySelectorAll("#candidate-list > details.candidate-source-root")]
      .find((node) => node.querySelector('details.candidate-category[data-category]'));
    const category = source.querySelector('details.candidate-category[data-category]');
    source.open = true;
    category.open = true;
    const sourceType = source.dataset.sourceType;
    const categoryName = category.dataset.category;
    document.querySelector("#bulk-actions").open = true;
    document.querySelector("#bulk-undo").click();
    await persistencePromise;
    await new Promise((resolve) => setTimeout(resolve, 200));
    observer.disconnect();
    const firstRowPreservedAfterUndo = candidateList.querySelector("[data-candidate-key]") === firstRow;

    const restoredSource = document.querySelector(`#candidate-list > details.candidate-source-root[data-source-type="${sourceType}"]`);
    const restoredCategory = restoredSource?.querySelector(`details.candidate-category[data-category="${categoryName}"]`);
    const toast = document.querySelector("#toast").getBoundingClientRect();
    const statusbar = document.querySelector(".ide-statusbar").getBoundingClientRect();
    const planRestored = Object.values(state.session.decisions).filter((decision) => decision.inPlan).length === planCountBefore;

    const verifyManualPromotion = (change) => {
      const candidate = getBulkActionCandidates("actionable")[0];
      const recommendation = getAssessment(candidate, getDecision(candidate)).recommendation;
      state.queries["candidate-sources"] = candidate.id;
      renderCandidateList();
      applyBulkSelection(recommendation);
      const bulkDecision = getDecision(candidate);
      updateDecision(candidate, change(bulkDecision));
      const decision = getDecision(candidate);
      const row = document.querySelector(`[data-plan-row="${candidate.key}"]`);
      const promoted = decision.planMembershipSource === "manual"
        && decision.bulkOperationId === null
        && state.session.bulkOperations.length === 0
        && elements["bulk-undo"].disabled
        && row?.querySelector(".plan-membership-badge")?.textContent.trim() === "Manual";
      delete state.session.decisions[candidate.key];
      state.session.bulkOperations = [];
      state.queries["candidate-sources"] = "";
      renderCandidateList();
      return promoted;
    };
    const rationaleEditPromotedToManual = verifyManualPromotion((decision) => ({ rationale: `${decision.rationale} Maintainer confirmed.` }));
    const actionEditPromotedToManual = verifyManualPromotion(() => ({ action: "defer" }));

    state.session = sessionSnapshot;
    await persistSession();
    renderBulkSelectionOutputs();
    return {
      remainedCollapsedAfterAdd,
      disabledCursor,
      bulkDecisionsComplete,
      operationAuditValid,
      manualDecisionPreserved,
      decorationPaletteValid,
      readyDecorationValid,
      parentDecorationPlacement,
      decorationAccessibilityValid,
      needsInputWins,
      treeDomPreserved: rootChildReplacements === 0
        && firstRowPreservedAfterAdd
        && firstRowPreservedAfterUndo,
      disclosuresPreserved: restoredSource?.open && restoredCategory?.open,
      planRestored,
      rationaleEditPromotedToManual,
      actionEditPromotedToManual,
      toastGap: statusbar.top - toast.bottom,
    };
  });

  assert(openAcrossGap, `${width}px Bulk Actions: menu closed while crossing the pointer bridge`);
  assert(openWhileReading, `${width}px Bulk Actions: menu closed while the pointer remained inside`);
  assert(closedAfterLeave, `${width}px Bulk Actions: menu remained open after the pointer left`);
  assert(result.remainedCollapsedAfterAdd, `${width}px Bulk Actions: Add changed a fully collapsed tree`);
  assert(result.disabledCursor === "default", `${width}px Bulk Actions: disabled command does not use the normal arrow`);
  assert(result.bulkDecisionsComplete, `${width}px Bulk Actions: generated decisions are incomplete`);
  assert(result.operationAuditValid, `${width}px Bulk Actions: operation audit metadata is incomplete`);
  assert(result.manualDecisionPreserved, `${width}px Bulk Actions: existing manual decision was changed`);
  assert(result.decorationPaletteValid, `${width}px Candidate decorations: product-owned palette values are incorrect`);
  assert(result.readyDecorationValid, `${width}px Candidate decorations: ready state did not propagate through the tree`);
  assert(result.parentDecorationPlacement, `${width}px Candidate decorations: trailing icons changed Candidate or count geometry`);
  assert(result.decorationAccessibilityValid, `${width}px Candidate decorations: tooltip or accessible description is incomplete`);
  assert(result.needsInputWins, `${width}px Candidate decorations: needs-input state did not override ready ancestors`);
  assert(result.treeDomPreserved, `${width}px Bulk Actions: candidate tree DOM was replaced and can flicker`);
  assert(result.disclosuresPreserved, `${width}px Bulk Actions: Undo collapsed expanded source or category disclosures`);
  assert(result.planRestored, `${width}px Bulk Actions: Undo did not restore the initial plan count`);
  assert(result.rationaleEditPromotedToManual, `${width}px Bulk Actions: rationale edit did not promote ownership to Manual`);
  assert(result.actionEditPromotedToManual, `${width}px Bulk Actions: action edit did not promote ownership to Manual`);
  assert(Math.abs(result.toastGap - 4) < 0.1, `${width}px toast: expected 4px status-bar clearance, got ${result.toastGap}px`);
}

async function assertStatusTooltip(page, width) {
  const item = await page.$("#status-headroom").then((node) => node.evaluateHandle((element) => element.parentElement));
  const box = await item.boundingBox();

  async function enterFrom(side) {
    await page.mouse.move(side === "right" ? box.x + box.width + 24 : box.x - 24, box.y + box.height / 2);
    await page.mouse.move(side === "right" ? box.x + box.width - 2 : box.x + 2, box.y + box.height / 2);
    return page.evaluate(() => {
      const tooltip = document.querySelector("#status-surface-tooltip");
      const statusbar = document.querySelector(".ide-statusbar");
      const rect = tooltip.getBoundingClientRect();
      return {
        text: tooltip.textContent,
        visible: getComputedStyle(tooltip).visibility === "visible",
        left: rect.left,
        right: rect.right,
        top: rect.top,
        bottom: rect.bottom,
        width: rect.width,
        statusTop: statusbar.getBoundingClientRect().top,
        nativeTitleCount: document.querySelectorAll(".ide-statusbar .status-item[title]").length,
      };
    });
  }

  const fromRight = await enterFrom("right");
  const fromLeft = await enterFrom("left");
  assert(fromRight.visible && fromLeft.visible, `${width}px status tooltip: tooltip is not visible`);
  assert(fromRight.text === "Test guidance headroom" && fromLeft.text === fromRight.text, `${width}px status tooltip: tooltip text is incorrect`);
  assert(fromRight.left >= 0 && fromRight.right <= width && fromRight.top >= 0, `${width}px status tooltip: tooltip leaves the rendered canvas`);
  assert(fromRight.bottom < fromRight.statusTop, `${width}px status tooltip: tooltip is not above the status bar`);
  assert(Math.abs(fromRight.left - fromLeft.left) < 0.1 && Math.abs(fromRight.width - fromLeft.width) < 0.1, `${width}px status tooltip: entry direction changes tooltip geometry`);
  assert(fromRight.nativeTitleCount === 0, `${width}px status tooltip: native status titles remain active`);
}

async function assertSourceProvenanceTooltip(page, width) {
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
  const pill = await page.$("#source-provenance-tooltip-probe .source-provenance-pill");
  const box = await pill.boundingBox();
  const contract = await page.evaluate(() => {
    const pills = [...document.querySelectorAll(".source-provenance-pill")];
    return pills.length > 0 && pills.every((item) => {
      const text = item.textContent.trim();
      return !item.hasAttribute("title")
        && item.dataset.workbenchTooltip === text
        && /^[^@]+@[0-9a-f]{8}$/.test(text)
        && !text.startsWith("Contributor guidance source:");
    });
  });

  async function enterAt(entryX) {
    await page.mouse.move(box.x - 12, box.y + box.height / 2);
    await page.mouse.move(entryX, box.y + box.height / 2);
    return page.evaluate((anchorX) => {
      const owner = document.querySelector("#source-provenance-tooltip-probe .source-provenance-pill");
      const tooltip = document.querySelector("#status-surface-tooltip");
      const ownerRect = owner.getBoundingClientRect();
      const tooltipRect = tooltip.getBoundingClientRect();
      const expectedLeft = Math.floor(Math.min(Math.max(8, anchorX), innerWidth - tooltipRect.width - 8));
      return {
        visible: getComputedStyle(tooltip).visibility === "visible",
        textMatches: tooltip.textContent === owner.textContent.trim(),
        viewportWidth: innerWidth,
        left: tooltipRect.left,
        right: tooltipRect.right,
        expectedLeft,
        belowGap: tooltipRect.top - ownerRect.bottom,
      };
    }, entryX);
  }

  const leftEntry = await enterAt(box.x + 2);
  const rightEntry = await enterAt(box.x + box.width - 2);
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
      verticallyContained: tooltipRect.top >= 8,
    };
    probe.remove();
    hideStatusTooltip();
    return result;
  });
  await page.evaluate(() => document.querySelector("#source-provenance-tooltip-probe").remove());

  assert(contract, `${width}px provenance tooltip: concise short-SHA ownership contract is invalid`);
  assert(leftEntry.visible && leftEntry.textMatches, `${width}px provenance tooltip: tooltip is hidden or has incorrect text`);
  assert(Math.abs(leftEntry.left - leftEntry.expectedLeft) < 0.1, `${width}px provenance tooltip: left entry is not pointer-anchored`);
  assert(Math.abs(rightEntry.left - rightEntry.expectedLeft) < 0.1, `${width}px provenance tooltip: right entry was not clamped only as needed`);
  assert(rightEntry.right <= rightEntry.viewportWidth - 8 + 0.1, `${width}px provenance tooltip: tooltip violates the right viewport inset`);
  assert(Math.abs(leftEntry.belowGap - 6) < 0.1 && Math.abs(rightEntry.belowGap - 6) < 0.1, `${width}px provenance tooltip: tooltip does not prefer placement below the pill`);
  assert(Math.abs(fallback.aboveGap - 6) < 0.1 && fallback.horizontallyContained && fallback.verticallyContained, `${width}px provenance tooltip: above fallback leaves the viewport`);
}

async function runViewportCheckpoint(page, browserDriver, width, label, operation, failures) {
  try {
    await settleLayout(page, browserDriver, `${width}px ${label}`);
    await operation();
  } catch (error) {
    failures.push({ width, label, message: error.message });
    if (browserDriver.reportFailure) await browserDriver.reportFailure(page, width, label, error);
  }
}

async function runViewportSuite(page, baseUrl, browserDriver) {
  assert(baseUrl, "Workbench URL is required");
  assertionCount = 0;
  const viewports = [
    { width: 767, breakpointSide: "max" },
    { width: 768, breakpointSide: "min" },
    { width: 900, breakpointSide: "max" },
    { width: 901, breakpointSide: "min" },
    { width: 1180, breakpointSide: "max" },
    { width: 1181, breakpointSide: "min" },
    { width: 1399, breakpointSide: "max" },
    { width: 1400, breakpointSide: "min" },
    { width: 1920, breakpointSide: "nearest" }
  ];
  const failures = [];

  for (const viewport of viewports) {
    const { width } = viewport;
    try {
      await browserDriver.setViewport(page, { ...viewport, height: 900, deviceScaleFactor: 1 });
      await browserDriver.goto(page, baseUrl);
      if (browserDriver.announceViewport) await browserDriver.announceViewport(page, width);
    } catch (error) {
      failures.push({ width, label: "viewport setup", message: error.message });
      if (browserDriver.reportFailure) await browserDriver.reportFailure(page, width, "viewport setup", error);
      continue;
    }

    if (width === 767) {
      await runViewportCheckpoint(page, browserDriver, width, "mobile rejection", async () => {
        const unsupported = await page.evaluate(() => {
          const view = document.querySelector(".unsupported-device");
          const icon = view.querySelector(".unsupported-brand-icon");
          return {
            active: document.documentElement.classList.contains("mobile-unsupported") && getComputedStyle(view).display !== "none",
            productName: view.querySelector(".unsupported-product-name")?.textContent.trim(),
            heading: view.querySelector("h1")?.textContent.trim(),
            iconHref: icon?.querySelector("use")?.getAttribute("href"),
            iconColor: getComputedStyle(icon).color,
            hasObsoleteMark: Boolean(view.querySelector(".unsupported-mark")) || view.textContent.trim().startsWith("HR")
          };
        });
        assert(unsupported.active, "767px: unsupported-device boundary is not active");
        assert(unsupported.productName === "HOSTED COPILOT RULE MANAGER", "767px: unsupported view lost the approved product identity");
        assert(unsupported.heading === "Mobile devices are not supported", "767px: unsupported view explanation is incorrect");
        assert(unsupported.iconHref?.endsWith("#codicon-json") && unsupported.iconColor === "rgb(255, 255, 0)", "767px: unsupported view does not use the approved yellow JSON-braces mark");
        assert(!unsupported.hasObsoleteMark, "767px: unsupported view still renders the obsolete HR mark");
      }, failures);
      continue;
    }

    await runViewportCheckpoint(page, browserDriver, width, "Workbench initialization", async () => {
      await waitForWorkbench(page);
    }, failures);
    await runViewportCheckpoint(page, browserDriver, width, "status tooltip", async () => {
      await assertStatusTooltip(page, width);
    }, failures);
    await runViewportCheckpoint(page, browserDriver, width, "provenance tooltip", async () => {
      await assertSourceProvenanceTooltip(page, width);
    }, failures);
    await runViewportCheckpoint(page, browserDriver, width, "Overrides decorations", async () => {
      await assertOverridesDecoration(page, width);
    }, failures);

    await runViewportCheckpoint(page, browserDriver, width, "Candidate Details layout", async () => {
      await activateCandidateDetails(page);
      await assertContainedScroll(page, width, "Candidate Details", "#candidate-sources-panel .assessment-content", "#candidate-sources-panel .assessment-panel > .assessment-title");
    }, failures);
    await runViewportCheckpoint(page, browserDriver, width, "Rule Actions", async () => {
      await assertRuleActionPreservesContext(page, width);
    }, failures);
    await runViewportCheckpoint(page, browserDriver, width, "plan toggle", async () => {
      await assertPlanTogglePreservesContext(page, width);
    }, failures);
    await runViewportCheckpoint(page, browserDriver, width, "plan membership synchronization", async () => {
      await assertPlanMembershipSynchronizesAcrossPanes(page, width);
    }, failures);
    await runViewportCheckpoint(page, browserDriver, width, "Decision Rationale layout", async () => {
      await assertRationaleSaveLayout(page, width);
    }, failures);
    await runViewportCheckpoint(page, browserDriver, width, "Bulk Actions", async () => {
      await assertBulkActionsPreserveContext(page, width);
    }, failures);

    await runViewportCheckpoint(page, browserDriver, width, "Assessment Details layout", async () => {
      await activateAssessmentDetails(page);
      await assertContainedScroll(page, width, "Assessment Details", "#assessment-results-detail > .assessment-content", "#assessment-results-detail > .assessment-title");
    }, failures);

    await runViewportCheckpoint(page, browserDriver, width, "Promotion Plan layout", async () => {
      await activateViewWithProbe(page, "plan", "#plan-view .plan-table-wrap");
      await assertContainedScroll(page, width, "Promotion Plan", "#plan-view .plan-table-wrap", "#plan-view .page-heading");
    }, failures);

    await runViewportCheckpoint(page, browserDriver, width, "Preview layout", async () => {
      await activateViewWithProbe(page, "preview", "#preview-view .preview-code");
      await assertContainedScroll(page, width, "Preview", "#preview-view .preview-code", "#preview-view .page-heading");
    }, failures);
  }

  if (failures.length) {
    const details = failures.map((failure) => `- ${failure.width}px ${failure.label}: ${failure.message}`).join("\n");
    throw new Error(`Viewport validation completed all ${viewports.length} widths with ${failures.length} failed checkpoint(s):\n${details}`);
  }

  return { status: "passed", viewportCount: viewports.length, assertionCount };
}

module.exports = { runViewportSuite };
