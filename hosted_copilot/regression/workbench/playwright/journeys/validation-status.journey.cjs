const { openWorkbench, hoverForWorkbenchTooltip } = require("../helpers/workbench.cjs");
const { createSavedRuleEvaluation } = require("../helpers/saved-rule-evaluation.cjs");

const behaviorIds = [
  "WB-UX-VALIDATION-001", "WB-UX-VALIDATION-002", "WB-UX-VALIDATION-003",
  "WB-UX-VALIDATION-004", "WB-UX-VALIDATION-005", "WB-UX-VALIDATION-006", "WB-UX-VALIDATION-007",
  "WB-UX-VALIDATION-008", "WB-UX-VALIDATION-009"
];

async function expectCounts(page, assert, errors, warnings) {
  const actual = await page.evaluate(() => {
    const entry = workbenchStatusBar.getEntry("validationIssues");
    const error = document.querySelector("#validation-error-count");
    const warning = document.querySelector("#validation-warning-count");
    return {
      errors: error.textContent, warnings: warning.textContent,
      errorKind: error.parentElement.classList.contains("error-kind"),
      warningKind: warning.parentElement.classList.contains("warning-kind"),
      tooltip: entry.dataset.workbenchTooltip, label: entry.getAttribute("aria-label")
    };
  });
  const tooltip = errors || warnings
    ? `Validation Issues: ${errors} ${errors === 1 ? "Error" : "Errors"}, ${warnings} ${warnings === 1 ? "Warning" : "Warnings"}`
    : "No Problems";
  assert(actual.errors === String(errors) && actual.warnings === String(warnings), `Expected ${errors} validation errors and ${warnings} warnings, got ${actual.errors} and ${actual.warnings}`);
  assert(actual.errorKind === Boolean(errors) && actual.warningKind === Boolean(warnings), "Validation counters do not expose independent semantic colors");
  assert(actual.tooltip === tooltip && actual.label === (errors || warnings ? tooltip : "Validation Issues: No Problems"), "Validation tooltip or accessible label is incorrect");
}

async function verifyStatusLayout(page, assert) {
  const viewport = page.viewportSize();
  try {
    await page.evaluate(() => workbenchStatusBar.update("target", {
      text: "fixture-owner/a-long-target-repository feature/a-long-target-branch@01234567",
      tooltip: "fixture-owner/a-long-target-repository feature/a-long-target-branch@01234567"
    }));
    for (const width of [1960, 1440, 1180, 1024, 902, 900, 820, 768]) {
      await page.setViewportSize({ width, height: 900 });
      for (const [errors, warnings] of [[0, 0], [1, 0], [12, 3], [999, 999]]) {
        const layout = await page.evaluate(({ errors, warnings }) => {
          workbenchStatusBar.update("validationIssues", {
            segments: {
              errors: { text: String(errors), kind: errors ? "error" : "standard" },
              warnings: { text: String(warnings), kind: warnings ? "warning" : "standard" }
            }
          });
          const entries = [...document.querySelectorAll(".ide-statusbar .status-item:not([hidden])")];
          const rects = entries.map((entry) => entry.getBoundingClientRect());
          return {
            width: innerWidth,
            order: [...document.querySelector(".status-left").children].map((node) => node.id || node.querySelector("span").id),
            contained: rects.every((rect) => rect.left >= 0 && rect.right <= innerWidth + 0.5),
            separated: rects.every((rect, index) => index === 0 || rect.left >= rects[index - 1].right - 0.5),
            readable: entries.every((entry) => getComputedStyle(entry).fontSize === "12px"
              && (entry.id === "target-chip" || entry.scrollWidth <= entry.clientWidth + 1)),
            height: document.querySelector(".ide-statusbar").getBoundingClientRect().height,
            documentWidth: document.documentElement.scrollWidth
          };
        }, { errors, warnings });
        assert(layout.width === width && layout.contained && layout.separated && layout.readable
          && layout.height === 22 && layout.documentWidth <= width
          && JSON.stringify(layout.order) === JSON.stringify(["target-chip", "validation-issues-status", "save-indicator"]),
        `${width}px status bar clips, overlaps, reorders, or shrinks with ${errors} errors and ${warnings} warnings: ${JSON.stringify(layout)}`);
      }
    }
    await page.evaluate(() => {
      renderValidationIssues();
      renderMetrics();
    });
    for (const entryKey of ["validationIssues", "ruleIssues", "promotionApproval"]) {
      const selector = await page.evaluate((key) => {
        const entry = workbenchStatusBar.getEntry(key);
        return entry.id ? `#${entry.id}` : `[data-status-navigation="${entry.dataset.statusNavigation}"]`;
      }, entryKey);
      await hoverForWorkbenchTooltip(page, page.locator(selector));
      const tooltip = await page.locator("#status-surface-tooltip").evaluate((node) => {
        const rect = node.getBoundingClientRect();
        return { text: node.textContent, left: rect.left, right: rect.right, width: innerWidth };
      });
      assert(tooltip.text.length > 0 && tooltip.left >= 0 && tooltip.right <= tooltip.width, `768px ${entryKey} tooltip is clipped`);
    }
    const casing = await page.evaluate(() => STATUS_BAR_ENTRIES
      .filter((entry) => entry.key !== "target")
      .every((entry) => workbenchStatusBar.getEntry(entry.key).dataset.workbenchTooltip
        .split(/[ :,-]+/).filter((word) => /^[a-z]/i.test(word)).every((word) => /^[A-Z]/.test(word))));
    assert(casing, "A status-bar tooltip contains sentence-case descriptive words");
  } finally {
    await page.setViewportSize(viewport);
    await page.evaluate(() => {
      renderTarget();
      renderValidationIssues();
      hideStatusTooltip();
    });
  }
}

async function verifySaveFailure(page, assert) {
  const failure = await page.evaluate(async () => {
    const database = await openDatabase();
    const originalTransaction = database.transaction;
    database.transaction = function (...args) {
      const transaction = originalTransaction.apply(this, args);
      if (args[1] === "readwrite") queueMicrotask(() => transaction.abort());
      return transaction;
    };
    let rejected = false;
    try {
      await persistSession();
    } catch {
      rejected = true;
    } finally {
      database.transaction = originalTransaction;
    }
    renderAll();
    renderDecisionOutputs();
    const entry = workbenchStatusBar.getEntry("save");
    return {
      rejected, text: document.querySelector("#save-indicator").textContent,
      error: entry.classList.contains("error-kind"),
      icon: entry.querySelector("use").getAttribute("href"),
      tooltip: entry.dataset.workbenchTooltip
    };
  });
  assert(failure.rejected && failure.text === "Save failed" && failure.error
    && failure.icon.endsWith("#codicon-error") && failure.tooltip.startsWith("Draft Save Failed:"),
  "An aborted persistence transaction was reported as saved or hidden by rendering");
  await expectCounts(page, assert, 0, 0);
  const recovered = await page.evaluate(async () => {
    await persistSession();
    const entry = workbenchStatusBar.getEntry("save");
    return entry.classList.contains("success-kind")
      && document.querySelector("#save-indicator").textContent.startsWith("Saved ")
      && entry.querySelector("use").getAttribute("href").endsWith("#codicon-check-compact")
      && entry.dataset.workbenchTooltip === "Draft Autosave State";
  });
  assert(recovered, "A failed draft save poisoned subsequent persistence or retained its error state");
}

async function verifyRestoredValidation(page, baseUrl, assert, originalText) {
  const editor = page.locator('#assessment-panel [data-decision-field="proposedText"]');
  const save = page.locator("[data-proposed-text-save]");
  const checkedText = `${originalText} Additional maintainer wording.`;
  const checkSavedText = async () => {
    await save.click();
    await page.waitForFunction(() => ["current", "failed"].includes(
      state.session.manualRelationshipChecks[getActiveCandidate()?.key]?.status
    ), null, { timeout: 120000 });
    await page.evaluate(() => persistencePromise);
    const result = await page.evaluate(async () => {
      const candidate = getActiveCandidate();
      const check = state.session.manualRelationshipChecks[candidate.key];
      const stored = await readSession(state.session.id);
      return {
        status: check.status, error: check.errorMessage,
        current: isSavedEvaluationCurrent(check.evaluation),
        persisted: stored.manualRelationshipChecks[candidate.key].status === "current"
          && stored.savedRuleEvaluations.length === 1,
        hasSelfCoverage: state.bundle.candidates.some((item) => item.recommendation.relatedHostedCoverage.some(
          (coverage) => coverage.hostedRuleId === item.catalogMapping.hostedRuleId
        ))
      };
    });
    assert(result.status === "current" && result.current && result.persisted && result.hasSelfCoverage,
      `The production HTTP/checker/adjudicator pipeline did not validate and persist the saved wording with baseline self-coverage: ${JSON.stringify(result)}`);
    await expectCounts(page, assert, 0, 0);
  };
  const restoreAndInspect = async (expected) => {
    await openWorkbench(page, baseUrl);
    await expectCounts(page, assert, 0, 1);
    await page.locator("#validation-issues-status").click();
    assert(await editor.inputValue() === checkedText && await save.isEnabled()
      && await save.getAttribute("aria-label") === "Check saved Hosted rule relationships",
    "An unchanged restored draft requiring validation has no enabled recheck action");
    assert(await page.locator(".relationship-check-status").textContent() === "Revalidation required",
      "An obsolete saved check does not explain its revalidation state");
    assert(await save.evaluate((node) => node === document.activeElement), "Revalidation navigation did not focus the unchanged-wording check control");
    const actual = await page.evaluate(() => ({
      sessionUpdatedAt: state.session.updatedAt,
      decisionUpdatedAt: getDecision(getActiveCandidate()).updatedAt,
      checkedAt: state.session.manualRelationshipChecks[getActiveCandidate().key].checkedAt,
      savedLabel: document.querySelector("#save-indicator").textContent
    }));
    assert(JSON.stringify(actual) === JSON.stringify(expected), "Reload or Details rendering advanced saved, edit, or check timestamps");
  };
  await editor.fill(checkedText);
  await checkSavedText();
  const legacy = await page.evaluate(async () => {
    const candidate = getActiveCandidate();
    const check = state.session.manualRelationshipChecks[candidate.key];
    delete check.evaluation;
    check.relationships = state.bundle.catalog.rules.filter((rule) => rule.id !== getEffectiveHostedRuleId(candidate)).slice(0, 2)
      .map((rule) => ({ hostedRuleId: rule.id, relationship: "partial-overlap", rationale: "Legacy checker relationship awaiting revalidation." }));
    state.session.savedRuleEvaluations = [];
    await persistSession();
    return {
      sessionUpdatedAt: state.session.updatedAt,
      decisionUpdatedAt: getDecision(candidate).updatedAt,
      checkedAt: check.checkedAt,
      savedLabel: document.querySelector("#save-indicator").textContent
    };
  });
  await restoreAndInspect(legacy);
  await checkSavedText();
  const stale = await page.evaluate(async () => {
    const candidate = getActiveCandidate();
    state.session.manualRelationshipChecks[candidate.key].evaluation.authoritySha256 = "e".repeat(64);
    state.session.savedRuleEvaluations.forEach((evaluation) => { evaluation.authoritySha256 = "e".repeat(64); });
    await persistSession();
    return {
      sessionUpdatedAt: state.session.updatedAt,
      decisionUpdatedAt: getDecision(candidate).updatedAt,
      checkedAt: state.session.manualRelationshipChecks[candidate.key].checkedAt,
      savedLabel: document.querySelector("#save-indicator").textContent
    };
  });
  await restoreAndInspect(stale);
  await checkSavedText();
  assert(await page.evaluate((timestamp) => getDecision(getActiveCandidate()).updatedAt === timestamp, stale.decisionUpdatedAt),
    "Revalidating unchanged wording changed its edit timestamp");
}

async function verifyFailureLayout(page, assert) {
  const viewport = page.viewportSize();
  try {
    for (const width of [1960, 1440, 1180, 1024, 902, 900, 820, 768]) {
      await page.setViewportSize({ width, height: 900 });
      const layout = await page.locator("[data-manual-relationship-failure]").evaluate((panel) => {
        const content = panel.querySelector(".error-banner-message");
        const dismiss = panel.querySelector(".error-banner-dismiss");
        const icon = panel.querySelector(".error-banner-icon");
        const rect = panel.getBoundingClientRect();
        const contentRect = content.getBoundingClientRect();
        const dismissRect = dismiss.getBoundingClientRect();
        const iconRect = icon.getBoundingClientRect();
        const style = getComputedStyle(panel);
        const naturalHeight = Math.max(contentRect.height, dismissRect.height, iconRect.height)
          + Number.parseFloat(style.paddingTop) + Number.parseFloat(style.paddingBottom)
          + Number.parseFloat(style.borderTopWidth) + Number.parseFloat(style.borderBottomWidth);
        return {
          grid: panel.classList.contains("error-banner") && style.display === "grid",
          dismissOnly: panel.querySelectorAll("button").length === 1 && dismiss.hasAttribute("data-dismiss-manual-relationship-failure")
            && dismiss.querySelector("use").getAttribute("href") === "icons/codicons/sprite.svg#codicon-close",
          pink: style.color === "rgb(246, 209, 211)" && getComputedStyle(icon).color === style.color
            && getComputedStyle(content).color === style.color && getComputedStyle(dismiss).color === style.color
            && getComputedStyle(content.querySelector("strong")).color === style.color
            && getComputedStyle(content.querySelector("span")).color === style.color,
          sized: iconRect.width === 20 && iconRect.height === 20 && dismissRect.width === 24 && dismissRect.height === 24,
          aligned: Math.abs(contentRect.top + contentRect.height / 2 - dismissRect.top - dismissRect.height / 2) <= 1,
          separated: contentRect.right <= dismissRect.left - 7,
          contained: rect.left >= 0 && rect.right <= innerWidth && dismissRect.right <= rect.right,
          readable: content.scrollWidth <= content.clientWidth + 1 && dismiss.scrollWidth <= dismiss.clientWidth + 1,
          compact: Math.abs(rect.height - Math.max(Number.parseFloat(style.minHeight), naturalHeight)) <= 1,
          documentWidth: document.documentElement.scrollWidth
        };
      });
      assert(layout.grid && layout.dismissOnly && layout.pink && layout.sized && layout.aligned && layout.separated
        && layout.contained && layout.readable && layout.compact && layout.documentWidth <= width,
      `${width}px failure banner loses its pink dismiss-only treatment, clips, overlaps, or wastes vertical space: ${JSON.stringify(layout)}`);
    }
  } finally {
    await page.setViewportSize(viewport);
  }
}

async function run({ page, baseUrl, assert, playback }) {
  await openWorkbench(page, baseUrl);
  await playback.show(page, "Validation status and persistent failures");
  await page.locator("#search-input").fill("REVIEW-REPO-001");
  await page.locator("#candidate-list .candidate-tree-copy").filter({ hasText: "REVIEW-REPO-001" }).first().click();
  const editor = page.locator('#assessment-panel [data-decision-field="proposedText"]');
  const save = page.locator("[data-proposed-text-save]");
  const progress = page.locator("[data-manual-relationship-progress]");
  const failurePanel = page.locator("[data-manual-relationship-failure]");
  const setup = await page.evaluate(() => {
    const candidate = getActiveCandidate();
    const related = state.bundle.catalog.rules.filter((rule) => rule.status === "active" && rule.id !== getEffectiveHostedRuleId(candidate)).slice(0, 2);
    if (related.length !== 2) throw new Error("Validation status requires two active related Hosted rules");
    const keys = (rule) => state.assessedCandidates.filter((item) => (item.catalogMapping.hostedRuleId || item.recommendation.hostedId) === rule.id).map((item) => item.key);
    return {
      candidate, comparisonCandidates: state.assessedCandidates, relatedRule: related[0], relatedCandidateKeys: keys(related[0]),
      additionalRelatedRules: [{ rule: related[1], candidateKeys: keys(related[1]) }],
      baselineIssues: getOpenRuleIssues().length
    };
  });
  const originalText = await editor.inputValue();
  assert(setup.baselineIssues > 0, "The validation fixture must contain independent catalog Rule Issues");
  await expectCounts(page, assert, 0, 0);
  await verifyStatusLayout(page, assert);
  await verifyRestoredValidation(page, baseUrl, assert, originalText);

  const serverFailure = await page.evaluate(async () => {
    const runtime = await loadSavedRuleRuntimeConfig();
    const response = await fetch("/reconcile-rule", {
      method: "POST",
      headers: { "Content-Type": "application/json", "X-Workbench-Operation-Token": runtime.operationToken },
      body: JSON.stringify({ payloadBase64: encodeBase64Utf8(JSON.stringify({ syntheticInvalid: true })) })
    });
    return { status: response.status, body: await response.json() };
  });
  assert(serverFailure.status === 500 && serverFailure.body.error.includes("Saved-rule request has an unexpected property set")
    && !/Line \||\.ps1:\d|Write-JsonSnapshot/.test(serverFailure.body.error),
  `The production loopback handler did not preserve the structured child-process failure without its PowerShell transcript: HTTP ${serverFailure.status}: ${serverFailure.body.error}`);

  let pendingRoute;
  let requestCount = 0;
  await page.route("**/reconcile-rule", (route) => {
    requestCount += 1;
    if (!pendingRoute) throw new Error("Unexpected validation request");
    const resolve = pendingRoute;
    pendingRoute = null;
    resolve(route);
  });
  const beginCheck = async (text, control = save) => {
    if (text !== undefined) await editor.fill(text);
    const received = new Promise((resolve) => { pendingRoute = resolve; });
    await control.click();
    await progress.waitFor({ state: "visible" });
    const saved = await page.locator("#save-indicator").textContent();
    assert(saved.startsWith("Saved ") && !saved.includes("Checking"), "Validation progress replaced the actual draft save status");
    return received;
  };
  const finishCheck = async (route, options = {}) => {
    await route.fulfill({ json: createSavedRuleEvaluation(route, { ...setup, ...options }) });
    await progress.waitFor({ state: "hidden" });
    if (await failurePanel.count()) assert(false, `Expected successful validation: ${await failurePanel.textContent()}`);
  };
  const failCheck = async (text) => {
    const route = await beginCheck(text);
    await route.fulfill({ status: 500, json: { error: evaluatorFailure } });
    await progress.waitFor({ state: "hidden" });
    await failurePanel.waitFor({ state: "visible" });
  };
  const evaluatorFailure = "Reconciliation stage `adjudication` shard `synthetic-shard` requires 1284517 bytes and exceeds the evaluator payload budget of 393216 bytes including retry-correction capacity. Run artifacts were retained at C:\\Synthetic\\hosted-rule-issue-adjudication\\fixture";

  const checkedText = `${originalText} Two relationship findings.`;
  await finishCheck(await beginCheck(checkedText), { grouped: true });
  await expectCounts(page, assert, 0, 2);
  assert(await page.locator(".manual-relationship-reviews .rule-issue-comparison").count() === 1
    && await failurePanel.count() === 0, "Successful validation did not replace progress with its grouped findings");
  const cached = await page.evaluate(async () => {
    const candidate = getActiveCandidate();
    await reconcileRuleTextRelationships(candidate, getDecision(candidate).proposedText, { notify: false });
    const stored = await readSession(state.session.id);
    return stored.manualRelationshipChecks[candidate.key].status;
  });
  assert(cached === "current" && requestCount === 1, "Cached validation persisted a pending state or invoked another evaluator");
  await expectCounts(page, assert, 0, 2);
  await openWorkbench(page, baseUrl);
  await expectCounts(page, assert, 0, 2);
  await page.locator("#validation-issues-status").click();
  assert(await editor.inputValue() === checkedText, "Cached validation did not survive reload for its exact saved proposal");
  assert(await page.locator(".manual-relationship-reviews").evaluate((node) => node === document.activeElement),
    "Relationship validation navigation did not focus its resolution region");

  const scopeText = `${originalText} Scope guidance fixture.`;
  await page.evaluate(() => {
    const candidate = getActiveCandidate();
    updateDecision(candidate, {
      action: getAllowedActions(candidate).includes("update") ? "update" : "add",
      rationale: "Review the saved wording before promotion.",
      ...createPlanMembership()
    });
    renderAll();
  });
  const scopeOptions = {
    scopeReview: {
      disposition: "uncertain", ownerRuleId: null, baselineQuote: originalText, proposalQuote: scopeText,
      rationale: "The maintainer must review the meaning of this saved wording.",
      wordingStatus: "acceptable", wordingRationale: "The complete wording expresses an enforceable obligation."
    },
    assessmentOverrides: { recommendation: "defer" }
  };
  await finishCheck(await beginCheck(scopeText), scopeOptions);
  await expectCounts(page, assert, 0, 1);
  await page.locator('[data-candidate-pane="candidates"]').click();
  await page.locator("#search-input").fill("REVIEW-REPO-001");
  const candidateRow = page.locator(`#candidate-list [data-candidate-key="${setup.candidate.key}"]`);
  await candidateRow.waitFor({ state: "visible" });
  const unselected = await page.evaluate(() => {
    const candidate = getActiveCandidate();
    const decoration = getCandidateDecoration(candidate);
    const aggregate = getCandidateAggregateDecoration([candidate]);
    const row = document.querySelector(`#candidate-list [data-candidate-key="${CSS.escape(candidate.key)}"]`);
    return !getDecision(candidate).inPlan && !row.querySelector("[data-decision-key]").checked
      && decoration?.status === "needs-input" && decoration.description === "Wording needs review"
      && !row.querySelector(".candidate-decoration-icon").hasAttribute("hidden")
      && aggregate?.status === "needs-input" && aggregate.description === "1 unselected candidate needs validation";
  });
  assert(unselected, "An unselected saved wording warning is hidden or falsely implies plan membership");
  await candidateRow.locator(".candidate-tree-copy").click();
  await page.evaluate(() => {
    updateDecision(getActiveCandidate(), createPlanMembership("manual"));
    renderAll();
  });
  await finishCheck(await beginCheck(), scopeOptions);
  const wordingSnapshot = async (panel) => panel.evaluate((node) => {
    const candidate = state.assessedCandidates.find((item) => item.key === (node.id === "assessment-results-detail" ? state.assessmentActiveKey : state.activeKey));
    const comparison = node.querySelector(".hosted-rule-comparison");
    const heading = comparison.querySelector(".proposed-rule-heading");
    const warning = comparison.querySelector("[data-saved-rule-scope]");
    const surface = comparison.querySelector("[data-proposed-candidate-key]") || comparison.querySelector(":scope > pre.evidence-box");
    const check = getCurrentManualRelationshipCheck(candidate);
    return {
      current: check?.status === "current" && isSavedEvaluationCurrent(check.evaluation)
        && check.relationships.length === 0 && check.evaluation.ruleIssues.issues.length === 0,
      blocked: !getPlanReadiness(candidate).ready && getPlanReadiness(candidate).attention.reason === "wording",
      oneWarning: comparison.querySelectorAll(".information-panel.warning").length === 1
        && comparison.querySelectorAll("[data-assessment-explanation]").length === 1
        && !comparison.querySelector(".manual-relationship-reviews"),
      order: heading.nextElementSibling === warning && Boolean(warning.compareDocumentPosition(surface) & Node.DOCUMENT_POSITION_FOLLOWING),
      explanation: warning.querySelector("strong").textContent === "Wording needs review"
        && warning.querySelector("p").textContent === (check.evaluation.scopeReview.wordingStatus === "needs-review"
          ? check.evaluation.scopeReview.wordingRationale : check.evaluation.scopeReview.rationale),
      appearance: getComputedStyle(warning).backgroundColor === "rgb(53, 42, 5)"
        && getComputedStyle(warning).color === "rgb(229, 186, 125)"
        && warning.querySelector("use").getAttribute("href") === "icons/codicons/sprite.svg#codicon-chat-sparkle-error"
        && getComputedStyle(warning.querySelector("svg")).color === "rgb(255, 190, 11)",
      advisoryHidden: !comparison.querySelector(".recommendation-badge")
        && getAssessment(candidate).recommendation === (check.evaluation.scopeReview.wordingStatus === "needs-review" ? "add" : "defer")
        && getAssessment(candidate).rationale.length > 0,
      currentStatusOnly: [...comparison.querySelectorAll(".current-hosted-rule-statuses")].every((statuses) => statuses.children.length === 1)
    };
  });
  const verifyWording = async (panel, context) => {
    for (const [name, passed] of Object.entries(await wordingSnapshot(panel))) {
      assert(passed, `${context} violates the completed wording-review design: ${name}`);
    }
  };
  await verifyWording(page.locator("#assessment-panel"), "Candidate Details");
  assert(await page.locator(".relationship-check-status").textContent() === "Wording needs review"
    && await page.locator(".relationship-check-status").evaluate((node) => node.classList.contains("warning")),
  "A completed uncertain result with no relationships is incorrectly green or implies another check is missing");
  const beforeNavigation = await page.evaluate(() => JSON.stringify(state.session));
  const requestsBeforeNavigation = requestCount;
  await page.locator("#validation-issues-status").click();
  assert(await page.locator("#assessment-panel [data-saved-rule-scope]").evaluate((node) => node === document.activeElement),
    "Status-bar navigation does not focus the wording warning");
  await page.locator('[data-view="plan"]').click();
  const planReview = page.locator(`[data-plan-detail="${setup.candidate.key}"]`);
  assert(await planReview.textContent() === "Review wording", "The plan presents a completed wording review as a missing reconciliation");
  await planReview.click();
  await page.waitForFunction(() => document.activeElement?.hasAttribute("data-saved-rule-scope"));
  await verifyWording(page.locator("#assessment-panel"), "Plan return");
  await page.evaluate((key) => {
    state.assessmentActiveKey = key;
    setWorkspaceTab("assessment-results");
    showAssessmentPane("details");
    renderAssessmentResults();
  }, setup.candidate.key);
  await verifyWording(page.locator("#assessment-results-detail"), "Assessment Results");
  assert(!await page.locator("#assessment-results-detail [data-decision-field], #assessment-results-detail [data-proposed-text-save]").count(),
    "The shared warning introduced editing or promotion controls into Assessment Results");
  await page.locator("#validation-issues-status").click();
  assert(await page.evaluate((before) => JSON.stringify(state.session) === before, beforeNavigation)
    && requestCount === requestsBeforeNavigation, "Review navigation changed the saved decision/evidence or restarted evaluation");
  await openWorkbench(page, baseUrl);
  await page.locator("#validation-issues-status").click();
  await verifyWording(page.locator("#assessment-panel"), "Restored current result");
  await page.evaluate(() => {
    updateDecision(getActiveCandidate(), { rationale: "" });
    renderAll();
  });
  await page.locator('[data-view="plan"]').click();
  assert(await planReview.textContent() === "Needs rationale", "A validation blocker obscures the higher-priority missing rationale");
  await planReview.click();
  await page.waitForFunction(() => document.activeElement?.getAttribute("data-decision-field") === "rationale");
  await page.locator("#validation-issues-status").click();
  assert(await page.locator("#assessment-panel [data-saved-rule-scope]").evaluate((node) => node === document.activeElement),
    "The validation warning incorrectly targets an unrelated missing decision rationale");
  await page.evaluate(() => {
    updateDecision(getActiveCandidate(), { rationale: "Review the saved wording before promotion." });
    renderAll();
  });
  await editor.fill(`${scopeText} Unsaved revision.`);
  assert(!await page.locator("#assessment-panel [data-saved-rule-scope]").count()
    && await page.locator("#assessment-panel [data-assessment-explanation] strong").textContent() === "Assessment rationale:",
  "Editing retained an obsolete wording warning instead of the original assessment context");
  await editor.fill(scopeText);
  await verifyWording(page.locator("#assessment-panel"), "Restored editor wording");

  const wordingText = `${originalText} A dancing teapot has opinions.`;
  const wordingOptions = {
    scopeReview: {
      disposition: "within-scope", ownerRuleId: null, baselineQuote: originalText, proposalQuote: wordingText,
      rationale: "The added sentence creates no distinct enforceable obligation.",
      wordingStatus: "needs-review", wordingRationale: "Remove the unrelated non-rule sentence before accepting this wording."
    },
    assessmentOverrides: { recommendation: "add" }
  };
  const savedAction = await page.evaluate(() => getDecision(getActiveCandidate()).action);
  const combinedText = `${wordingText} Preserve the complete baseline.`;
  await finishCheck(await beginCheck(combinedText), {
    ...wordingOptions,
    scopeReview: {
      ...wordingOptions.scopeReview,
      disposition: "uncertain", proposalQuote: combinedText, rationale: scopeOptions.scopeReview.rationale
    }
  });
  await expectCounts(page, assert, 0, 1);
  await verifyWording(page.locator("#assessment-panel"), "Combined scope and wording concerns");
  assert(await page.locator("#assessment-panel [data-saved-rule-scope] p").allTextContents().then((paragraphs) =>
    paragraphs.length === 2 && paragraphs.includes(wordingOptions.scopeReview.wordingRationale)
      && paragraphs.includes(scopeOptions.scopeReview.rationale)),
  "Combined scope and wording concerns lost an explanation or duplicated their warning panel");
  await finishCheck(await beginCheck(wordingText), wordingOptions);
  await expectCounts(page, assert, 0, 1);
  await verifyWording(page.locator("#assessment-panel"), "Within-scope wording concern");
  assert(await page.evaluate(({ action, text }) => {
    const candidate = getActiveCandidate();
    const check = getCurrentManualRelationshipCheck(candidate);
    return check.evaluation.scopeReview.disposition === "within-scope"
      && check.evaluation.ruleIssues.issues.length === 0 && check.relationships.length === 0
      && getDecision(candidate).action === action && getDecision(candidate).proposedText === text
      && !isManualRelationshipCheckResolved(check) && getPreviewReadiness().missingRelationshipCheckCount === 1
      && !getPreviewReadiness().ready;
  }, { action: savedAction, text: wordingText }), "Within-scope nonsense was accepted, rewritten, or changed the maintainer's action");
  const wordingRequests = requestCount;
  await page.locator("#validation-issues-status").click();
  assert(await page.locator("#assessment-panel [data-saved-rule-scope]").evaluate((node) => node === document.activeElement),
    "The status-bar wording concern does not focus its existing warning");
  await page.locator('[data-view="plan"]').click();
  assert(await planReview.textContent() === "Review wording", "Within-scope nonsense is shown as Ready in the Plan");
  await planReview.click();
  await page.waitForFunction(() => document.activeElement?.hasAttribute("data-saved-rule-scope"));
  await verifyWording(page.locator("#assessment-panel"), "Within-scope Plan return");
  await openWorkbench(page, baseUrl);
  await expectCounts(page, assert, 0, 1);
  await page.locator("#validation-issues-status").click();
  await verifyWording(page.locator("#assessment-panel"), "Restored wording concern");
  await page.evaluate((key) => {
    state.assessmentActiveKey = key;
    setWorkspaceTab("assessment-results");
    showAssessmentPane("details");
    renderAssessmentResults();
  }, setup.candidate.key);
  await verifyWording(page.locator("#assessment-results-detail"), "Within-scope Assessment Results");
  await page.locator("#validation-issues-status").click();
  assert(await page.locator("#assessment-panel [data-saved-rule-scope]").evaluate((node) => node === document.activeElement),
    "Within-scope Assessment Results lost the shared warning navigation destination");
  assert(requestCount === wordingRequests && await editor.inputValue() === wordingText,
    "Reload or warning navigation restarted evaluation or silently cleaned saved wording");

  const invalidWordings = await page.evaluate(async () => {
    const candidate = getActiveCandidate();
    const evaluation = getCurrentManualRelationshipCheck(candidate).evaluation;
    const rejected = [];
    for (const kind of ["missing-status", "invalid-status", "missing-rationale", "blank-rationale", "old-version"]) {
      const bad = structuredClone(evaluation);
      if (kind === "missing-status") delete bad.scopeReview.wordingStatus;
      if (kind === "invalid-status") bad.scopeReview.wordingStatus = "unspecified";
      if (kind === "missing-rationale") delete bad.scopeReview.wordingRationale;
      if (kind === "blank-rationale") bad.scopeReview.wordingRationale = " ";
      if (kind === "old-version") bad.schemaVersion = 3;
      try { await validateSavedRuleEvaluation(bad, evaluation, getSavedRuleProposals(), getDecision(candidate).proposedText, candidate); }
      catch { rejected.push(kind); }
    }
    return rejected;
  });
  assert(invalidWordings.length === 5, `Incomplete wording decisions were accepted: ${JSON.stringify(invalidWordings)}`);
  await page.evaluate(async () => {
    const candidate = getActiveCandidate();
    for (const evaluation of [state.session.manualRelationshipChecks[candidate.key].evaluation, ...state.session.savedRuleEvaluations]) {
      evaluation.schemaVersion = 3;
      delete evaluation.scopeReview.wordingStatus;
      delete evaluation.scopeReview.wordingRationale;
    }
    await persistSession();
  });
  await openWorkbench(page, baseUrl);
  await expectCounts(page, assert, 0, 1);
  await page.locator("#validation-issues-status").click();
  assert(await page.evaluate(() => getManualRelationshipValidation(getActiveCandidate()).status === "stale"
    && !getPlanReadiness(getActiveCandidate()).ready)
    && await editor.inputValue() === wordingText && await save.isEnabled(),
  "Older receipts lacking wording acceptance were trusted or prevented the draft from loading");
  await finishCheck(await beginCheck(`${originalText} Examples must retain all required inputs.`));
  await expectCounts(page, assert, 0, 0);
  assert(await page.evaluate(() => getPlanReadiness(getActiveCandidate()).ready
    && getPreviewReadiness().missingRelationshipCheckCount === 0)
    && !await page.locator("#assessment-panel [data-saved-rule-scope]").count(),
  "A newly acceptable result retained the wording blocker");

  await failCheck(`${originalText} Failure fixture.`);
  await expectCounts(page, assert, 1, 0);
  const inlineError = await failurePanel.evaluate((node) => ({
    alert: node.getAttribute("role") === "alert" && node.getAttribute("aria-atomic") === "true",
    message: node.querySelector(".error-banner-message > span").textContent,
    animations: node.getAnimations({ subtree: true }).filter((animation) => animation.playState === "running").length
  }));
  assert(inlineError.alert && inlineError.message === evaluatorFailure && inlineError.animations === 0,
    "Validation failure lacks a persistent accessible static error");
  await verifyFailureLayout(page, assert);
  const beforeDismiss = await page.evaluate(async () => {
    await persistencePromise;
    return {
      session: JSON.stringify(state.session),
      stored: JSON.stringify(await readSession(state.session.id)),
      savedLabel: document.querySelector("#save-indicator").textContent
    };
  });
  await failurePanel.getByRole("button", { name: "Dismiss relationship check error", exact: true }).click();
  assert(await failurePanel.count() === 0 && await save.evaluate((node) => node === document.activeElement), "Dismissing the error did not remove only the banner and restore editor-control focus");
  await page.evaluate(() => {
    renderAssessment();
    renderDecisionOutputs();
  });
  assert(await failurePanel.count() === 0 && await save.isEnabled(), "Rerender restored a dismissed failure banner or removed the external retry control");
  const dismissalPreservedFailure = await page.evaluate(async (before) => {
    await persistencePromise;
    return getManualRelationshipCheck(getActiveCandidate()).status === "failed"
      && JSON.stringify(state.session) === before.session
      && JSON.stringify(await readSession(state.session.id)) === before.stored
      && document.querySelector("#save-indicator").textContent === before.savedLabel;
  }, beforeDismiss);
  assert(dismissalPreservedFailure, "Dismissal cleared validation failure or changed saved state, persistence, or timestamps");
  await expectCounts(page, assert, 1, 0);
  await failCheck();
  assert(await failurePanel.isVisible(), "A new failed check inherited dismissal from an earlier failure");
  await page.locator('[data-view="plan"]').click();
  await expectCounts(page, assert, 1, 0);
  await page.locator('[data-view="preview"]').click();
  await page.locator("#preview-review-toggle").click();
  await page.locator("#approver-name").fill("Another fixture maintainer");
  await page.evaluate(() => persistencePromise);
  await expectCounts(page, assert, 1, 0);
  await openWorkbench(page, baseUrl);
  await expectCounts(page, assert, 1, 0);
  await page.locator("#validation-issues-status").click();
  assert(await failurePanel.isVisible() && await failurePanel.locator(".error-banner-message > span").textContent() === inlineError.message,
    "Validation navigation or reload lost the affected rule's persisted failure");
  assert(await save.isEnabled(), "Reload left unchanged failed wording without an enabled retry action");
  assert(await save.evaluate((node) => node === document.activeElement), "Failed-check navigation did not focus Retry");

  const retryRoute = await beginCheck();
  await expectCounts(page, assert, 1, 0);
  assert(await failurePanel.count() === 0, "Retry retained an error panel beside active validation");
  await finishCheck(retryRoute);
  await expectCounts(page, assert, 0, 0);
  assert(await failurePanel.count() === 0 && await page.locator(".manual-relationship-reviews").count() === 0,
    "Successful empty validation left an error or empty results panel");
  await openWorkbench(page, baseUrl);
  await expectCounts(page, assert, 0, 0);
  await page.locator("#search-input").fill("REVIEW-REPO-001");
  await page.locator("#candidate-list .candidate-tree-copy").filter({ hasText: "REVIEW-REPO-001" }).first().click();
  assert(await page.locator(".relationship-check-status").textContent() === "Relationships resolved"
    && await save.isDisabled() && await failurePanel.count() === 0,
  "Reload lost the successful retry or offered another check for unchanged resolved wording");

  const malformedRoute = await beginCheck(`${originalText} Invalid response fixture.`);
  await malformedRoute.fulfill({ contentType: "application/json", body: "synthetic-parser-detail" });
  await progress.waitFor({ state: "hidden" });
  const safeFailure = await page.evaluate(async () => {
    const stored = await readSession(state.session.id);
    return stored.manualRelationshipChecks[getActiveCandidate().key].errorMessage;
  });
  assert(safeFailure === "Relationship check returned an invalid response. Retry to validate the saved wording."
    && await failurePanel.locator(".error-banner-message > span").textContent() === safeFailure, "Validation persisted or rendered raw parser response details");
  await verifyFailureLayout(page, assert);

  await failCheck(`${originalText} Import reset fixture.`);
  const draft = await page.evaluate(() => JSON.stringify(buildDraftExport()));
  await page.locator("#import-input").setInputFiles({ name: "validation-draft.json", mimeType: "application/json", buffer: Buffer.from(draft) });
  await page.waitForFunction(() => document.querySelector("#toast-message").textContent === "Draft imported");
  await expectCounts(page, assert, 0, 1);
  assert(await page.evaluate(() => Object.keys(state.session.manualRelationshipChecks).length === 0
    && state.session.savedRuleEvaluations.length === 0
    && requiresManualRelationshipCheck(getActiveCandidate())
    && !getPreviewReadiness().ready), "Draft import inherited prior validation or allowed an unchecked edited rule");
  const beforeInvalidImport = await page.evaluate(async () => ({
    memory: JSON.stringify(state.session),
    stored: JSON.stringify(await readSession(state.session.id))
  }));
  const invalidDraft = JSON.parse(draft);
  invalidDraft.schemaVersion = 999;
  await page.locator("#import-input").setInputFiles({ name: "invalid-validation-draft.json", mimeType: "application/json", buffer: Buffer.from(JSON.stringify(invalidDraft)) });
  await page.waitForFunction(() => document.querySelector("#toast-message").textContent === "The draft version is not supported.");
  const unchanged = await page.evaluate(async (before) => before.memory === JSON.stringify(state.session)
    && before.stored === JSON.stringify(await readSession(state.session.id)), beforeInvalidImport);
  assert(unchanged, "An invalid draft import changed browser or persisted validation state");

  await failCheck(`${originalText} No Change discard fixture.`);
  const promotionAction = setup.candidate.catalogMapping.state === "active" ? "update" : "add";
  await page.locator(`[data-rule-action="${promotionAction}"]`).check();
  await page.locator('[data-rule-action="no-change"]').check();
  await page.evaluate(() => persistencePromise);
  await expectCounts(page, assert, 0, 0);
  assert(await failurePanel.count() === 0 && await page.evaluate(() => !state.session.manualRelationshipChecks[getActiveCandidate().key]),
    "No Change retained discarded validation metadata or its inline failure");

  await failCheck(`${originalText} Explicit discard fixture.`);
  await page.evaluate(async () => resetCandidate(getActiveCandidate()));
  await expectCounts(page, assert, 0, 0);
  const discarded = await page.evaluate(async (key) => {
    const stored = await readSession(state.session.id);
    return !stored.manualRelationshipChecks[key] && !stored.savedRuleEvaluations.some((evaluation) => evaluation.candidateKey === key);
  }, setup.candidate.key);
  assert(discarded, "Explicit discard retained persisted validation problems");
  await verifySaveFailure(page, assert);
}

module.exports = { name: "validation status", behaviorIds, viewport: { width: 1180, height: 900 }, run };
