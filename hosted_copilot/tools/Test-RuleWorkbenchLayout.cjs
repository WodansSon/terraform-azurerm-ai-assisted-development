function resolvePuppeteer() {
  return require("puppeteer");
}

function assert(condition, message) {
  if (!condition) throw new Error(message);
}

async function waitForWorkbench(page) {
  await page.waitForFunction(() => Number(document.querySelector("#catalog-count")?.textContent) > 0);
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
        && button.title.startsWith("Save")
        && icon.querySelector("use")?.getAttribute("href")?.endsWith("#codicon-save"),
      toolbarVisualMatch: toolbarVisualMatch && buttonRect.width === 34 && buttonRect.height === 34,
      baselineAligned: Math.abs(iconRect.bottom - labelRect.bottom) < 0.1,
      cursorsCorrect: enabledCursor === "pointer" && disabledCursor === "default",
      contained: labelRect.right <= buttonRect.left && buttonRect.right <= headingRect.right && heading.scrollWidth <= heading.clientWidth,
    };
  });

  assert(result.available, `${width}px Decision Rationale save: control is unavailable`);
  assert(result.accessibleIconOnly, `${width}px Decision Rationale save: icon-only accessibility contract is invalid`);
  assert(result.toolbarVisualMatch, `${width}px Decision Rationale save: toolbar style or hit target diverged from Draft options`);
  assert(result.baselineAligned, `${width}px Decision Rationale save: icon and label bottom edges are not aligned`);
  assert(result.cursorsCorrect, `${width}px Decision Rationale save: enabled or disabled cursor is incorrect`);
  assert(result.contained, `${width}px Decision Rationale save: label and action overlap or overflow`);
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

async function run() {
  const baseUrl = process.argv[2];
  assert(baseUrl, "Workbench URL is required");

  const puppeteer = resolvePuppeteer();
  const browser = await puppeteer.launch({
    headless: true,
    args: ["--no-sandbox", "--disable-setuid-sandbox"],
  });

  try {
    const page = await browser.newPage();
    const viewports = [767, 768, 900, 901, 1180, 1181, 1399, 1400, 1920];
    let assertionCount = 0;

    for (const width of viewports) {
      await page.setViewport({ width, height: 900, deviceScaleFactor: 1 });
      await page.goto(baseUrl, { waitUntil: "networkidle0" });

      if (width === 767) {
        const unsupported = await page.evaluate(() => document.documentElement.classList.contains("mobile-unsupported")
          && getComputedStyle(document.querySelector(".unsupported-device")).display !== "none");
        assert(unsupported, "767px: unsupported-device boundary is not active");
        assertionCount += 1;
        continue;
      }

      await waitForWorkbench(page);
      await assertStatusTooltip(page, width);
      assertionCount += 6;

      await activateCandidateDetails(page);
      await assertContainedScroll(page, width, "Candidate Details", "#candidate-sources-panel .assessment-content", "#candidate-sources-panel .assessment-panel > .assessment-title");
      assertionCount += 6;
      await assertRuleActionPreservesContext(page, width);
      assertionCount += 5;
      await assertPlanTogglePreservesContext(page, width);
      assertionCount += 6;
      await assertPlanMembershipSynchronizesAcrossPanes(page, width);
      assertionCount += 6;
      await assertRationaleSaveLayout(page, width);
      assertionCount += 6;

      await activateAssessmentDetails(page);
      await assertContainedScroll(page, width, "Assessment Details", "#assessment-results-detail > .assessment-content", "#assessment-results-detail > .assessment-title");
      assertionCount += 6;

      await activateViewWithProbe(page, "plan", "#plan-view .plan-table-wrap");
      await assertContainedScroll(page, width, "Promotion Plan", "#plan-view .plan-table-wrap", "#plan-view .page-heading");
      assertionCount += 6;

      await activateViewWithProbe(page, "preview", "#preview-view .preview-code");
      await assertContainedScroll(page, width, "Preview", "#preview-view .preview-code", "#preview-view .page-heading");
      assertionCount += 6;
    }

    process.stdout.write(JSON.stringify({ status: "passed", viewportCount: viewports.length, assertionCount }));
  } finally {
    await browser.close();
  }
}

run().catch((error) => {
  process.stderr.write(`${error.stack || error.message}\n`);
  process.exit(1);
});
