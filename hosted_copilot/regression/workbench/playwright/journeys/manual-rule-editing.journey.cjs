const { openWorkbench } = require("../helpers/workbench.cjs");

const behaviorIds = ["WB-UX-EDITING-001", "WB-UX-EDITING-002", "WB-UX-EDITING-003"];

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
      __editorPaintCheck.observer.observe(panel, { childList: true, subtree: true });
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
        replacedNodes: check.mutations.reduce((count, record) => count + record.addedNodes.length + record.removedNodes.length, 0),
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

    await page.locator('[data-rule-action="update"]').check();
    await page.locator('[data-decision-field="rationale"]').fill("Explicit maintainer wording for the v1 promotion preview.");
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
