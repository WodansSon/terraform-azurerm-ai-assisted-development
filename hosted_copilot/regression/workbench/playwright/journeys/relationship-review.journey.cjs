const { openWorkbench } = require("../helpers/workbench.cjs");
const reviewProfile = require("../../../../tools/config/llm.json").ruleEvaluation;

const behaviorIds = ["WB-UX-RELATIONSHIPS-001"];

async function run({ page, baseUrl, assert }) {
  await page.emulateMedia({ reducedMotion: "no-preference" });
  let mode = "success";
  let calls = 0;
  let releasePending = null;
  const errors = [];
  const onError = error => errors.push(error.message);
  page.on("pageerror", onError);
  await page.route("**/check-relationships", async route => {
    calls += 1;
    const body = route.request().postDataJSON();
    const request = JSON.parse(Buffer.from(body.payloadBase64, "base64").toString("utf8"));
    const context = await page.evaluate(key => ({ id: getEffectiveHostedRuleId(state.assessedCandidates.find(candidate => candidate.key === key)), ids: [...state.bundle.catalog.rules.map(rule => rule.id), ...state.bundle.catalog.protectedRules.map(rule => rule.id)] }), request.candidateKey);
    if (mode === "pending") await new Promise(resolve => { releasePending = resolve; });
    if (["transient", "hard"].includes(mode)) {
      const failure = mode === "transient"
        ? { code: "invalid-response", message: "The checker could not produce a usable result. Your saved rule is unchanged. Try again.", retryable: true, recovery: "retry" }
        : { code: "runtime-unavailable", message: "Check GitHub Copilot authentication and Luna access, then restart the Workbench.", retryable: false, recovery: "restart" };
      await route.fulfill({ status: 500, contentType: "application/json", body: JSON.stringify({ error: failure }) });
      return;
    }
    await route.fulfill({ status: 200, contentType: "application/json", body: JSON.stringify({ schemaVersion: 1, requestId: request.requestId, candidateKey: request.candidateKey,
      authoritySha256: request.authoritySha256, snapshotKey: request.snapshotKey, inputSha256: "d".repeat(64), changedRuleIds: [context.id], removedRuleIds: [], effectiveRuleIds: [...new Set([...context.ids, context.id])],
      findings: [], elapsedMilliseconds: 42, model: reviewProfile.model, reasoningEffort: reviewProfile.reasoningEffort }) });
  });
  await openWorkbench(page, baseUrl);
  const fixture = await page.evaluate(() => {
    const candidate = state.candidates.find(item => getCatalogStatus(item).key === "unmapped" && item.assessment.hostedApplicable);
    if (!candidate) throw new Error("Relationship journey requires an unmapped evaluated candidate.");
    globalThis.__relationshipJourneyOriginal = { session: structuredClone(state.session), issues: state.ruleIssues };
    state.ruleIssues = [];
    delete state.session.decisions[candidate.key];
    selectCandidate(candidate.key);
    showCandidatePane("details");
    return { key: candidate.key, text: getDecision(candidate).proposedText, id: getEffectiveHostedRuleId(candidate) };
  });
  if (await page.locator("#assist-panel-toggle").getAttribute("aria-pressed") === "true") await page.locator("#assist-panel-toggle").click();
  if (await page.locator("#toast.visible").count()) await page.locator("#toast-close").click();
  const reveal = async selector => {
    if (await page.locator("#toast.visible").count()) await page.locator("#toast-close").click();
    await page.evaluate(value => scrollCandidateDetailTargetIntoView(elements["assessment-panel"].querySelector(value)), selector);
    await page.waitForFunction(value => {
      const target = elements["assessment-panel"].querySelector(value);
      const pane = elements["assessment-panel"].querySelector(".assessment-content");
      if (!target || !pane) return false;
      const box = target.getBoundingClientRect();
      const bounds = pane.getBoundingClientRect();
      return box.top >= bounds.top - 1 && box.bottom <= bounds.bottom + 1;
    }, selector);
    return page.locator(`#assessment-panel ${selector}`);
  };
  const editAndSave = async suffix => {
    const editor = await reveal('[data-decision-field="proposedText"]');
    await editor.fill(fixture.text + suffix);
    await page.locator("#assessment-panel [data-proposed-text-save]").click();
    await page.waitForFunction(({ key, text }) => getDecision(state.assessedCandidates.find(candidate => candidate.key === key)).proposedText === text, { key: fixture.key, text: fixture.text + suffix });
  };
  try {
    assert(await page.evaluate(() => !matchMedia("(prefers-reduced-motion: reduce)").matches), "Relationship checks must retain normal motion");
    const noChange = await reveal('[data-rule-action="no-change"]');
    await noChange.check();
    const editor = await reveal('[data-decision-field="proposedText"]');
    await editor.fill(fixture.text + " Preserve explicit edited wording.");
    assert(await page.locator('#assessment-panel [data-rule-action="no-change"]').count() === 0
      && await page.locator("#assessment-panel [data-rule-action]:checked").count() === 0, "Edited wording retained No Change or silently chose another action");
    await page.locator("#assessment-panel [data-proposed-text-save]").click();
    const add = await reveal('[data-rule-action="add"]');
    await add.check();
    assert(await page.locator("#assessment-panel [data-rationale-save]").isDisabled(), "An empty rationale can save a changed rule decision");
    const rationale = await reveal('[data-decision-field="rationale"]');
    await rationale.fill("Retain the original obligations while making the proposed wording explicit.");
    await page.locator("#assessment-panel [data-rationale-save]").click();
    await page.waitForFunction(key => getDecision(state.assessedCandidates.find(candidate => candidate.key === key)).inPlan, fixture.key);
    assert(await page.evaluate(key => getPlanReadiness(state.assessedCandidates.find(candidate => candidate.key === key)).label === "Relationship Check Required", fixture.key), "Planned changed rule bypassed the check gate");
    const check = await reveal("[data-relationship-review-open]");
    await check.click();
    await page.waitForFunction(key => getRelationshipReviewState(state.assessedCandidates.find(candidate => candidate.key === key)).status === "current", fixture.key);
    assert(await page.evaluate(key => getPlanReadiness(state.assessedCandidates.find(candidate => candidate.key === key)).ready, fixture.key), "A clean check did not satisfy Plan relationship readiness");
    assert(await page.locator("#assessment-panel [data-relationship-review-status]").evaluate(node => node.tagName === "SPAN" && node.textContent === "Relationships Checked"), "Details success is not a static checked pill");
    await page.evaluate(() => switchView("plan"));
    assert(await page.locator("#plan-table-body").getByText("Ready", { exact: true }).count() === 1
      && await page.locator("#plan-table-body").getByRole("button", { name: "Ready", exact: true }).count() === 0, "Plan success is not the native noninteractive Ready pill");
    await page.evaluate(key => openPlanCandidate(key, '[data-decision-field="proposedText"]'), fixture.key);
    const changed = await reveal('[data-decision-field="proposedText"]');
    await changed.fill(fixture.text + " Preserve another explicit edit.");
    assert(await page.locator("#assessment-panel [data-relationship-review-status]").textContent() === "Revalidation Required"
      && await page.evaluate(key => getPlanReadiness(state.assessedCandidates.find(candidate => candidate.key === key)).label === "Revalidation Required", fixture.key), "Unsaved wording makes Details and Plan disagree");
    await page.locator("#assessment-panel [data-proposed-text-save]").click();
    mode = "transient";
    await (await reveal("[data-relationship-review-open]")).click();
    await page.locator("#assessment-panel .error-banner").waitFor();
    const beforeDismiss = calls;
    const banner = page.locator("#assessment-panel .error-banner");
    assert(await banner.evaluate(node => {
      const retry = node.querySelector("[data-relationship-review-run]");
      const close = node.querySelector("[data-relationship-review-dismiss]");
      return retry.nextElementSibling === close && retry.getBoundingClientRect().right <= close.getBoundingClientRect().left && node.querySelector(".banner-heading").textContent === "Relationship Check Failed:";
    }), "Retry is not immediately left of Close using the shared banner heading/actions");
    await banner.locator("[data-relationship-review-dismiss]").click();
    assert(calls === beforeDismiss && await page.evaluate(key => getRelationshipReviewState(state.assessedCandidates.find(candidate => candidate.key === key)).status === "failed", fixture.key), "Dismissal retried or cleared failure");
    await (await reveal("[data-relationship-review-open]")).click();
    assert(calls === beforeDismiss, "Reopening a failure implicitly retried");
    mode = "success";
    await page.locator("#assessment-panel [data-relationship-review-run]").click();
    await page.waitForFunction(key => getRelationshipReviewState(state.assessedCandidates.find(candidate => candidate.key === key)).status === "current", fixture.key);
    await editAndSave(" Preserve a fix-first example.");
    mode = "hard";
    await (await reveal("[data-relationship-review-open]")).click();
    await page.locator("#assessment-panel .error-banner").waitFor();
    assert(await page.locator("#assessment-panel [data-relationship-review-run]").count() === 0, "Fix-first error offers a blind retry");
    const hardCalls = calls;
    await page.evaluate(key => checkRuleRelationships(state.assessedCandidates.find(candidate => candidate.key === key)), fixture.key);
    assert(calls === hardCalls, "Programmatic retry bypassed the fix-first guard");
    await editAndSave(" Preserve cancellation behavior.");
    mode = "pending";
    await (await reveal("[data-relationship-review-open]")).click();
    await page.waitForFunction(() => activeRelationshipReviews.size === 1);
    const stableWaiting = await page.evaluate(key => {
      const candidate = state.assessedCandidates.find(item => item.key === key);
      const active = activeRelationshipReviews.get(key);
      const container = elements["assessment-panel"].querySelector("[data-relationship-review-panel]");
      const waiting = container.querySelector(".waiting-panel");
      const cancel = container.querySelector("[data-relationship-review-cancel]");
      cancel.focus();
      active.startedAt -= 2000;
      syncRelationshipReviewControls(candidate);
      return { samePanel: waiting === container.querySelector(".waiting-panel"), sameCancel: cancel === container.querySelector("[data-relationship-review-cancel]"),
        focusRetained: document.activeElement === cancel, elapsed: container.querySelector(".waiting-panel-elapsed").textContent,
        normalMotion: !matchMedia("(prefers-reduced-motion: reduce)").matches };
    }, fixture.key);
    assert(stableWaiting.samePanel && stableWaiting.sameCancel && stableWaiting.focusRetained, "Elapsed-time updates replaced the waiting panel or focused Cancel control");
    assert(/^\[Elapsed: 00:0[2-9]\]$/.test(stableWaiting.elapsed) && stableWaiting.normalMotion, "Waiting updates did not advance elapsed time with normal motion");
    await page.evaluate(() => switchView("plan"));
    await page.locator("#relationship-review-stop").click();
    await page.waitForFunction(() => activeRelationshipReviews.size === 0);
    releasePending?.();
    assert(await page.evaluate(key => !getPlanReadiness(state.assessedCandidates.find(candidate => candidate.key === key)).ready, fixture.key), "Cancellation left a false Ready state");
    assert(await page.evaluate(() => document.querySelector(".app-shell").scrollTop === 0 && document.querySelector("footer").getBoundingClientRect().bottom <= visualViewport.offsetTop + visualViewport.height), "Interaction scrolled the fixed shell or displaced the footer");
    assert(errors.length === 0, `Relationship journey raised browser errors: ${errors.join("; ")}`);
  } finally {
    releasePending?.();
    await page.unroute("**/check-relationships");
    page.off("pageerror", onError);
    await page.evaluate(async () => {
      for (const active of activeRelationshipReviews.values()) active.controller.abort();
      state.session = __relationshipJourneyOriginal.session;
      state.ruleIssues = __relationshipJourneyOriginal.issues;
      delete globalThis.__relationshipJourneyOriginal;
      await persistSession();
      renderAll();
    });
  }
  return { behaviorIds };
}

module.exports = { behaviorIds, run };
