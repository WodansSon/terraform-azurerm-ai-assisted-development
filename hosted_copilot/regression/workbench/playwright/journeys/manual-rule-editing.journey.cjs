const { openWorkbench } = require("../helpers/workbench.cjs");

const behaviorIds = ["WB-UX-EDITING-001", "WB-UX-EDITING-002", "WB-UX-EDITING-003"];

async function exerciseResolutionDialog(page, assert, candidateKey) {
  const viewport = page.viewportSize();
  const fixture = await page.evaluate((key) => {
    const candidate = state.assessedCandidates.find(item => item.key === key);
    const ruleId = candidate.catalogMapping.hostedRuleId;
    const baseline = getOriginalRuleBaseline(candidate);
    const originalText = baseline.proposedText;
    const updatedText = `${originalText} Preserve the maintainer's explicit wording.`;
    const related = state.bundle.catalog.rules.find(item => item.status === "active" && item.id !== ruleId);
    globalThis.__resolutionFixture = { session: structuredClone(state.session), issues: state.ruleIssues };
    state.session.decisions[key] = { ...getDecision(candidate), action: "retire", rationale: "Synthetic saved retirement rationale.", proposedText: updatedText, ...createPlanMembership(), sourceHash: candidate.hash };
    const issue = {
      id: `relationship:${ruleId}:fixture-resolution`, classification: "overlap", label: "Overlap",
      title: `${related.id} preserves ${ruleId}`, bannerTitle: "Hosted rule retirement is recommended",
      bannerMessage: `${related.id} preserves the enforceable meaning of ${ruleId}.`, blocking: false,
      ruleIds: [ruleId, related.id], protectedRuleIds: [], candidateKeys: [key],
      rules: [
        { id: ruleId, status: "active", disposition: "retire", text: originalText, candidateKeys: [key] },
        { id: related.id, status: "active", disposition: "keep", text: related.text, candidateKeys: [] }
      ],
      relationships: [{ sourceRuleId: ruleId, relatedRuleId: related.id, relationship: "assessment-narrows-hosted", kind: "overlap", rationale: `${related.id} preserves ${ruleId}.`, candidateKey: key }],
      assessmentSummary: `${related.id} preserves ${ruleId}.`,
      wording: { status: "selected", label: "Suggested Consolidated Wording", presentation: "member", text: related.text, sourceRuleId: related.id },
      recommendedMaintainerAction: { summary: `Retire ${ruleId} and retain ${related.id}.`, operations: [{ candidateKey: key, ruleId, action: "retire", proposedText: originalText, retireHostedRuleIds: [] }] }
    };
    state.ruleIssues = [issue];
    state.activeRuleIssueKey = issue.id;
    setWorkspaceTab("rule-issues");
    renderRuleIssues();
    return { key, ruleId, originalText, updatedText, originalAction: baseline.action, originalRationale: baseline.rationale, rationale: getDecision(candidate).rationale, before: JSON.stringify(state.session) };
  }, candidateKey);
  const open = async () => {
    await page.locator(`[data-rule-issue-rule="${fixture.ruleId}"]`).click();
    await page.locator("[data-rule-resolution-dialog]").waitFor();
  };
  try {
    await page.evaluate(() => {
      globalThis.__copyFixture = { writer: navigator.clipboard.writeText, toast: showToast, writes: [], messages: [], fail: false };
      navigator.clipboard.writeText = async text => { __copyFixture.writes.push(text); if (__copyFixture.fail) throw new Error("Synthetic clipboard failure"); };
      showToast = message => __copyFixture.messages.push(message);
    });
    try {
      await page.locator('[data-copy-consolidated-wording]').click();
      await page.waitForFunction(() => __copyFixture.messages.includes("Consolidated wording copied."));
      await page.evaluate(async () => { await copyConsolidatedWording("   "); __copyFixture.fail = true; await copyConsolidatedWording("Synthetic failed copy."); });
      assert(await page.evaluate(() => __copyFixture.writes.length === 2 && __copyFixture.writes.every(text => text.length > 0)
        && __copyFixture.messages.includes("Nothing to copy.") && __copyFixture.messages.includes("Copy failed.")),
      "Copy cleared the clipboard, duplicated a write, or lost empty/failure feedback");
      assert(await page.locator('[data-copy-consolidated-wording]').isEnabled(), "Advisory Copy became disabled after failure");
    } finally {
      await page.evaluate(() => { navigator.clipboard.writeText = __copyFixture.writer; showToast = __copyFixture.toast; delete globalThis.__copyFixture; });
    }
    await open();
    const dialog = page.locator("[data-rule-resolution-dialog]");
    const rationale = dialog.locator("#rule-resolution-rationale");
    const save = dialog.locator("[data-resolution-save]");
    const reset = dialog.locator("[data-resolution-reset]");
    const initial = await dialog.evaluate(element => {
      const panels = [...element.querySelectorAll(".rule-resolution-text")];
      const heading = element.querySelector(".modal-dialog-heading");
      return {
        width: element.getBoundingClientRect().width,
        titles: panels.map(panel => panel.querySelector(".rule-resolution-text-title").textContent),
        weights: panels.map(panel => getComputedStyle(panel.querySelector(".rule-resolution-text-title")).fontWeight),
        choicesInside: panels.every(panel => panel.querySelector("h3").nextElementSibling.classList.contains("rule-resolution-wording-choice")),
        sharedFill: getComputedStyle(panels[0].querySelector(".rule-resolution-wording-choice")).backgroundColor === getComputedStyle(element.querySelector(".rule-resolution-state .action-plan-group")).backgroundColor,
        mainHeaderFill: getComputedStyle(heading).backgroundColor === getComputedStyle(document.querySelector(".topbar")).backgroundColor,
        footerBorder: getComputedStyle(element.querySelector(".modal-dialog-actions")).borderTopWidth,
        resetLeft: element.querySelector("[data-resolution-reset]").nextElementSibling.matches("[data-dialog-close]"),
        oldTools: element.querySelectorAll("[data-resolution-action], [data-rule-resolution-text-toggle]").length,
        sharedRationale: element.querySelector("#rule-resolution-rationale").closest(".rationale-field") !== null
      };
    });
    assert(initial.width <= 768 && initial.titles.join("|") === "UPDATED TEXT|ORIGINAL TEXT"
      && initial.weights.every(weight => weight === "600"), "Resolution comparison size, order, or heading styling differs from the accepted design");
    assert(initial.choicesInside && initial.sharedFill && initial.mainHeaderFill && initial.footerBorder === "0px"
      && initial.resetLeft && initial.oldTools === 0 && initial.sharedRationale, "Resolution dialog does not reuse the accepted panel, header, or rationale presentation");
    assert(await dialog.getByRole("radio", { name: "Retire", exact: true }).isChecked()
      && await dialog.getByRole("radio", { name: "Keep Updated Text", exact: true }).isChecked()
      && await rationale.inputValue() === fixture.rationale
      && await save.isEnabled() && await reset.isEnabled(), "Resolution defaults do not match the saved action, pending Plan membership, and original-baseline Reset");
    await dialog.getByRole("radio", { name: "Keep Original Text", exact: true }).check();
    assert(await save.isEnabled() && await reset.isEnabled()
      && !(await dialog.getByRole("radio", { name: "Keep Updated Text", exact: true }).isChecked()), "Wording selection is not exclusive or does not dirty the resolution");
    await dialog.getByRole("radio", { name: "Keep Updated Text", exact: true }).check();
    assert(await save.isEnabled() && await reset.isEnabled(), "Returning to saved wording lost pending Plan staging or original-baseline Reset");
    await rationale.fill("x".repeat(500));
    assert(await dialog.locator(".rationale-limit").innerText() === "500 / 500 characters"
      && await rationale.getAttribute("maxlength") === "500", "Shared rationale counter or limit is incorrect");
    await reset.click();
    assert(await rationale.inputValue() === fixture.originalRationale
      && await dialog.locator(".rationale-limit").innerText() === `${fixture.originalRationale.length} / 500 characters`
      && await save.isEnabled() && await reset.isDisabled()
      && await dialog.locator('input[name="rule-resolution-action"]:checked').inputValue() === fixture.originalAction,
    "Reset failed to restore the immutable original baseline or its exact-revert rationale exception");
    await page.setViewportSize({ width: 768, height: 900 });
    const narrow = await dialog.evaluate(element => ({ width: element.getBoundingClientRect().width, overflow: element.scrollWidth > element.clientWidth, footer: element.querySelector(".modal-dialog-actions").getBoundingClientRect().bottom <= innerHeight }));
    assert(narrow.width === 736 && !narrow.overflow && narrow.footer, "Resolution does not fit the minimum supported viewport");
    await page.setViewportSize(viewport);
    await dialog.getByRole("button", { name: "Cancel", exact: true }).click();
    const resolve = page.locator(`[data-rule-issue-rule="${fixture.ruleId}"]`);
    const assertDismissed = async method => {
      await dialog.waitFor({ state: "detached" });
      assert(await resolve.evaluate(element => document.activeElement === element), `${method} did not restore keyboard focus to Resolve`);
      await page.waitForTimeout(await page.evaluate(() => WORKBENCH_TOOLTIP_DELAY_MS + 50));
      assert(await page.evaluate(() => !elements["status-surface-tooltip"].classList.contains("visible") && workbenchTooltip.showTimer === 0),
        `${method} left the Resolve tooltip visible or scheduled after focus restoration`);
      assert(await page.evaluate(before => JSON.stringify(state.session) === before, fixture.before), `${method} changed the saved draft`);
    };
    await assertDismissed("Cancel");
    await page.mouse.move(4, 4);
    await resolve.hover();
    await page.waitForFunction(() => elements["status-surface-tooltip"].classList.contains("visible"));
    assert(await page.locator("#status-surface-tooltip").textContent() === "Resolve rule", "A fresh hover did not restore the Resolve tooltip");
    for (const method of ["close X", "Escape", "backdrop"]) {
      await open();
      assert(await page.evaluate(() => !elements["status-surface-tooltip"].classList.contains("visible")), "Opening a dialog retained its trigger tooltip");
      if (method === "close X") await dialog.locator("[data-dialog-close]").click();
      else if (method === "Escape") await page.keyboard.press("Escape");
      else await page.mouse.click(4, 4);
      await assertDismissed(method);
    }
    await page.keyboard.press("Tab");
    await resolve.focus();
    await page.waitForFunction(() => elements["status-surface-tooltip"].classList.contains("visible"));
    assert(await page.locator("#status-surface-tooltip").textContent() === "Resolve rule", "A fresh keyboard focus did not restore the Resolve tooltip");
    assert(await page.evaluate(before => JSON.stringify(state.session) === before, fixture.before), "Cancelling resolution changed the saved draft");

    await open();
    await rationale.fill("Synthetic resolution persistence failure");
    await page.evaluate(() => { globalThis.__resolutionDatabase = openDatabase; openDatabase = () => Promise.reject(new Error("Synthetic resolution persistence failure")); });
    try {
      await save.click();
      await page.getByText("Resolution was not saved: Synthetic resolution persistence failure", { exact: true }).waitFor();
      assert(await page.evaluate(before => JSON.stringify(state.session) === before, fixture.before), "Failed resolution persistence changed the draft");
    } finally {
      await page.evaluate(() => { openDatabase = __resolutionDatabase; delete globalThis.__resolutionDatabase; });
    }
    await open();
    await rationale.fill("Preserve concurrent draft work.");
    await page.evaluate(() => { state.session.updatedAt = toUtcTimestamp(); state.session.approverName = "Concurrent fixture edit"; });
    const concurrent = await page.evaluate(() => JSON.stringify(state.session));
    await save.click();
    await page.getByText("Resolution was not saved: The resolution changed or is not valid. Review the current draft and protected integrity.", { exact: true }).waitFor();
    assert(await page.evaluate(before => JSON.stringify(state.session) === before, concurrent), "Stale resolution overwrote a concurrent draft");

    await open();
    await dialog.getByRole("radio", { name: "Keep Original Text", exact: true }).check();
    await rationale.fill("Retain the original rule wording without approving the Plan.");
    await save.click();
    await page.getByText("Resolution saved.", { exact: true }).waitFor();
    const saved = await page.evaluate(async (key) => {
      const candidate = state.assessedCandidates.find(item => item.key === key);
      const decision = getDecision(candidate);
      const stored = await readSession(state.session.id);
      return { text: decision.proposedText, action: decision.action, rationale: decision.rationale, inPlan: decision.inPlan, stored: stored.decisions[key].proposedText };
    }, fixture.key);
    assert(saved.text === fixture.originalText && saved.stored === fixture.originalText && saved.action === "retire"
      && saved.rationale === "Retain the original rule wording without approving the Plan." && saved.inPlan,
    "Saving a resolution lost its wording or action, or failed to stage the explicit Plan mutation");
    assert(await page.evaluate(key => {
      const candidate = state.assessedCandidates.find(item => item.key === key);
      return !getPlanReadiness(candidate).ready && getOpenRuleIssues().length === 0
        && state.ruleIssues.length === 1 && document.querySelector('[data-resolution-status="resolved"]')
        && document.querySelector('.banner-success use').getAttribute('href').endsWith('#codicon-git-pull-request-done');
    }, fixture.key), "Resolved history vanished or the unvalidated retirement became approved");
    await open();
    assert(await dialog.getByRole("radio", { name: "Retire", exact: true }).isChecked() && await reset.isEnabled(),
      "Reopening lost the saved action or original-baseline Reset target");
    await reset.click();
    assert(await rationale.inputValue() === fixture.originalRationale && await save.isEnabled(),
      "Exact original revert requires a new rationale or cannot remove the Plan mutation");
    await save.click();
    assert(await page.evaluate(key => !getDecision(state.assessedCandidates.find(item => item.key === key)).inPlan
      && getOpenRuleIssues().length === 1, fixture.key), "Original revert failed to reopen the issue or remove its Plan mutation");
  } finally {
    await page.setViewportSize(viewport);
    await page.evaluate(async () => {
      document.querySelector("[data-rule-resolution-dialog]")?.close();
      state.session = __resolutionFixture.session;
      state.ruleIssues = __resolutionFixture.issues;
      delete globalThis.__resolutionFixture;
      await persistSession();
      renderAll();
    });
  }
}

async function run({ page, baseUrl, assert }) {
  let relationshipRequests = 0;
  const pageErrors = [];
  const recordPageError = (error) => pageErrors.push(error.message);
  page.on("pageerror", recordPageError);
  await page.route("**/reconcile-rule", async (route) => {
    relationshipRequests += 1;
    await route.abort();
  });
  await openWorkbench(page, baseUrl);
  const original = await page.evaluate(() => structuredClone(state.session));
  const fixture = await page.evaluate(() => {
    const candidate = state.assessedCandidates.find((item) => item.assessment.hostedApplicable
      && item.catalogMapping.state === "active"
      && !state.ruleIssues.some((issue) => issue.candidateKeys.includes(item.key)));
    if (!candidate) throw new Error("Manual editing requires a mapped, evaluated candidate outside the published issues.");
    selectCandidate(candidate.key);
    showCandidatePane("details");
    return {
      key: candidate.key,
      text: getDecision(candidate).proposedText,
      assessment: JSON.stringify(getBaselineAssessment(candidate, getDecision(candidate))),
      issues: JSON.stringify(state.ruleIssues)
    };
  });
  try {
    const closeAssistance = page.getByRole("button", { name: "Close AI assistance", exact: true });
    if (await closeAssistance.isVisible()) await closeAssistance.click();
    const editor = page.locator('#assessment-panel [data-decision-field="proposedText"]');
    const savedText = `${fixture.text} Retain the explicit maintainer wording.`;
    await page.evaluate(() => {
      const panel = elements["assessment-panel"];
      globalThis.__editorPaintCheck = {
        pill: panel.querySelector("[data-assessment-recommendation]"),
        evidence: panel.querySelector("[data-assessment-evidence]")?.firstElementChild,
        mutations: []
      };
      __editorPaintCheck.observer = new MutationObserver((records) => __editorPaintCheck.mutations.push(...records));
      __editorPaintCheck.observer.observe(__editorPaintCheck.evidence, { childList: true, subtree: true });
      __editorPaintCheck.observer.observe(__editorPaintCheck.pill, { childList: true, subtree: true });
    });
    await editor.fill(savedText);
    const typing = await page.evaluate(() => {
      const check = __editorPaintCheck;
      check.mutations.push(...check.observer.takeRecords());
      check.observer.disconnect();
      delete globalThis.__editorPaintCheck;
      return {
        stablePill: check.pill === document.querySelector("[data-assessment-recommendation]"),
        stableEvidence: check.evidence === document.querySelector("[data-assessment-evidence]")?.firstElementChild,
        replacedNodes: check.mutations.filter(record => !record.target.closest?.(".score-item.cost, .score-item.efficiency"))
          .reduce((count, record) => count + record.addedNodes.length + record.removedNodes.length, 0),
        saveEnabled: !document.querySelector("[data-proposed-text-save]").disabled,
        resetEnabled: !document.querySelector("[data-proposed-text-reset]").disabled
      };
    });
    assert(typing.stablePill && typing.stableEvidence && typing.replacedNodes === 0 && typing.saveEnabled && typing.resetEnabled,
      "Typing rebuilt evidence, changed the saved-state pill, or failed to enable Save and Reset");
    const unsaved = await page.evaluate(() => getPreviewReadiness());
    assert(unsaved.unsavedRuleText && !unsaved.ready, "Unsaved wording does not block approval deterministically");
    assert(await page.locator("[data-manual-relationship-progress], [data-relationship-review-actions], [data-maintainer-resolution]").count() === 0,
      "Retired relationship controls remain in Details");
    const beforeFailure = await page.evaluate(() => ({ session: JSON.stringify(state.session), pill: document.querySelector("[data-assessment-recommendation]").textContent }));
    await page.evaluate(() => {
      globalThis.__originalEditorDatabase = openDatabase;
      openDatabase = () => Promise.reject(new Error("Synthetic wording persistence failure"));
    });
    try {
      await page.locator("[data-proposed-text-save]").click();
      await page.getByText("Rule wording was not saved: Synthetic wording persistence failure", { exact: true }).waitFor();
      assert(await page.evaluate(({ session, pill }) => JSON.stringify(state.session) === session
        && document.querySelector("[data-assessment-recommendation]").textContent === pill, beforeFailure)
        && await editor.inputValue() === savedText, "Failed Save changed the saved rule, pill, or unsaved buffer");
    } finally {
      await page.evaluate(() => { openDatabase = __originalEditorDatabase; delete globalThis.__originalEditorDatabase; });
    }
    await page.locator("[data-proposed-text-save]").click();
    await page.evaluate(() => persistencePromise);
    const saved = await page.evaluate(async ({ key, assessment, issues }) => {
      const candidate = state.assessedCandidates.find((item) => item.key === key);
      const stored = await readSession(state.session.id);
      return {
        text: getDecision(candidate).proposedText,
        stored: stored.decisions[key].proposedText,
        originalAssessment: JSON.stringify(getAssessment(candidate)) === assessment,
        originalIssues: JSON.stringify(state.ruleIssues) === issues,
        unsaved: getPreviewReadiness().unsavedRuleText,
        rationale: document.querySelector("[data-assessment-explanation] strong")?.textContent,
        saveDisabled: document.querySelector("[data-proposed-text-save]").disabled,
        resetEnabled: !document.querySelector("[data-proposed-text-reset]").disabled,
        assistance: Boolean(document.querySelector("#rule-assistance-panel [data-rule-assistance]"))
      };
    }, fixture);
    assert(saved.text === savedText && saved.stored === savedText && saved.saveDisabled && saved.resetEnabled && !saved.unsaved,
      "Save does not persist exact wording independently of AI");
    assert(saved.originalAssessment && saved.originalIssues && saved.rationale === "Original assessment rationale:",
      "Saving altered rebuild evidence or presented the edited wording as freshly assessed");
    assert(saved.assistance, "Removing relationship checks removed AI Assistance");

    await page.evaluate(async (key) => {
      state.session.manualRelationshipChecks = { [key]: { status: "failed", errorMessage: "Synthetic obsolete failure." } };
      state.session.savedRuleEvaluations = [{ schemaVersion: 0 }];
      await persistSession();
    }, fixture.key);
    await openWorkbench(page, baseUrl);
    const restored = await page.evaluate(({ key, issues }) => {
      const candidate = state.assessedCandidates.find((item) => item.key === key);
      selectCandidate(key);
      showCandidatePane("details");
      return {
        text: getDecision(candidate).proposedText,
        cleared: !Object.hasOwn(state.session, "manualRelationshipChecks") && !Object.hasOwn(state.session, "savedRuleEvaluations"),
        issues: JSON.stringify(state.ruleIssues) === issues
      };
    }, fixture);
    assert(restored.text === savedText && restored.cleared && restored.issues,
      "Reload restored retired checks, lost saved wording, or changed published Rule Issues");

    if (await closeAssistance.isVisible()) await closeAssistance.click();
    await page.locator('[data-rule-action="update"]').check();
    await page.locator('[data-decision-field="rationale"]').fill("Explicit maintainer wording for the v1 promotion preview.");
    assert(await page.locator('.rationale-field #decision-rationale-limit').innerText() === `${"Explicit maintainer wording for the v1 promotion preview.".length} / 500 characters`,
      "Details does not use the shared rationale field and live counter");
    await page.locator("[data-rationale-save]").click();
    await page.evaluate(() => persistencePromise);
    const plan = await page.evaluate((key) => {
      const candidate = state.assessedCandidates.find((item) => item.key === key);
      return { ready: getPlanReadiness(candidate).ready, selected: getDecision(candidate).inPlan };
    }, fixture.key);
    assert(plan.ready && plan.selected, "Saved wording still needs an AI relationship check before plan readiness");
    await page.locator('[data-view="preview"]').click();
    const preview = await page.evaluate((key) => ({
      readiness: getPreviewReadiness(),
      requirements: document.querySelector("#approval-requirements").textContent,
      mutations: buildApprovedRules().mutations,
      candidateId: getEffectiveHostedRuleId(state.assessedCandidates.find((item) => item.key === key))
    }), fixture.key);
    assert(!preview.requirements.includes("Relationship checks") && preview.requirements.includes("Rule wording"),
      "Promotion preview still advertises relationship certification");
    assert(preview.readiness.openRuleIssueCount > 0 && !preview.readiness.ready,
      "Removing edit checks bypassed the published Rule Issues gate");
    assert(preview.mutations.some((mutation) => mutation.rule.id === preview.candidateId && mutation.rule.text === savedText),
      "Promotion payload did not preserve exact maintainer-edited wording");
    const deterministic = await page.evaluate(() => {
      const published = state.ruleIssues;
      state.ruleIssues = [];
      try {
        const ready = getPreviewReadiness().ready;
        const candidate = getPlanCandidates()[0];
        const rationale = state.session.decisions[candidate.key].rationale;
        state.session.decisions[candidate.key].rationale = "";
        const missingRationale = getPreviewReadiness();
        state.session.decisions[candidate.key].rationale = rationale;
        return { ready, rationaleBlocked: !missingRationale.ready && missingRationale.missingRationaleCount > 0 };
      } finally {
        state.ruleIssues = published;
      }
    });
    assert(deterministic.ready && deterministic.rationaleBlocked,
      "Preview either retains the relationship gate or lost required rationale validation");
    await page.evaluate((key) => {
      switchView("catalog");
      setWorkspaceTab("candidate-sources");
      selectCandidate(key);
      showCandidatePane("details");
    }, fixture.key);
    await editor.fill(fixture.text);
    assert(await page.locator("[data-proposed-text-reset]").isEnabled()
      && await page.locator("[data-proposed-text-save]").isEnabled(),
    "Typing the original text hid the persisted edit from Reset or Save");
    const beforeReset = await page.evaluate((key) => {
      const decision = getDecision(state.assessedCandidates.find((item) => item.key === key));
      return { rationale: decision.rationale, inPlan: decision.inPlan };
    }, fixture.key);
    await page.locator("[data-proposed-text-reset]").click();
    await page.locator("[data-rule-reset-confirm]").click();
    await page.waitForFunction(() => document.querySelector("[data-proposed-text-reset]")?.disabled);
    const reset = await page.evaluate(async ({ key, text, rationale, inPlan }) => {
      const decision = getDecision(state.assessedCandidates.find((item) => item.key === key));
      const stored = await readSession(state.session.id);
      return decision.proposedText === text && stored.decisions[key].proposedText === text
        && decision.rationale === rationale && decision.inPlan === inPlan
        && document.querySelector("[data-proposed-text-save]").disabled
        && !document.querySelector("[data-assessment-recommendation]").textContent.includes("Maintainer edited");
    }, { ...fixture, ...beforeReset });
    assert(reset, "Reset did not persist original wording, restore its pill, or preserve independent decision fields");
    await exerciseResolutionDialog(page, assert, fixture.key);
    assert(relationshipRequests === 0, "Editing, saving, restoring, or previewing requested AI relationship evaluation");
    assert(pageErrors.length === 0, `Editing raised an uncaught browser error: ${pageErrors.join("; ")}`);
  } finally {
    page.off("pageerror", recordPageError);
    await page.evaluate(async (session) => {
      state.session = session;
      await persistSession();
    }, original);
  }
  return { behaviorIds };
}

module.exports = { behaviorIds, run };
