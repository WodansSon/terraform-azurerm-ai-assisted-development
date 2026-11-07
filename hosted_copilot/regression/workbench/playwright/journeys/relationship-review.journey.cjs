const { openWorkbench } = require("../helpers/workbench.cjs");
const reviewProfile = require("../../../../tools/config/llm.json").ruleEvaluation;

const behaviorIds = ["WB-UX-RELATIONSHIPS-001"];
const relationshipFixture = { proposedRuleId: "REVIEW-REPO-001", relatedRuleId: "IMPL-PATCH-001", issueId: "relationship:REVIEW-REPO-001:fixture" };

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
    const context = await page.evaluate(({ key, relatedRuleId }) => {
      const candidate = state.assessedCandidates.find(item => item.key === key);
      const id = getEffectiveHostedRuleId(candidate);
      return { id, text: getDecision(candidate).proposedText, related: state.bundle.catalog.rules.find(rule => rule.id === relatedRuleId), ids: [...state.bundle.catalog.rules.map(rule => rule.id), ...state.bundle.catalog.protectedRules.map(rule => rule.id)] };
    }, { key: request.candidateKey, relatedRuleId: relationshipFixture.relatedRuleId });
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
      findings: mode === "conflict" ? [{ ruleId: context.id, relatedRuleId: context.related.id, relationship: "conflicts", ruleQuote: context.text, relatedQuote: context.related.text, rationale: "Synthetic relationship finding for readiness coverage." }] : [],
      elapsedMilliseconds: 42, model: reviewProfile.model, reasoningEffort: reviewProfile.reasoningEffort }) });
  });
  await openWorkbench(page, baseUrl);
  const fixture = await page.evaluate(({ proposedRuleId, relatedRuleId, issueId }) => {
    const candidate = state.candidates.find(item => item.recommendation?.hostedId === proposedRuleId);
    const issue = state.ruleIssues.find(item => item.id === issueId);
    if (!candidate || getCatalogStatus(candidate).key !== "unmapped" || !candidate.assessment.hostedApplicable
      || !issue || issue.blocking || !issue.candidateKeys.includes(candidate.key)
      || !issue.relationships.some(pair => pair.sourceRuleId === proposedRuleId && pair.relatedRuleId === relatedRuleId)) {
      throw new Error("The permanent synthetic relationship scenario is missing or incompatible.");
    }
    globalThis.__relationshipJourneyOriginal = { session: structuredClone(state.session), issues: state.ruleIssues };
    delete state.session.decisions[candidate.key];
    selectCandidate(candidate.key);
    showCandidatePane("details");
    return { key: candidate.key, text: getDecision(candidate).proposedText, id: getEffectiveHostedRuleId(candidate), issueId };
  }, relationshipFixture);
  if (await page.locator("#assist-panel-toggle").getAttribute("aria-pressed") === "true") await page.locator("#assist-panel-toggle").click();
  if (await page.locator("#toast.visible").count()) await page.locator("#toast-close").click();
  const reveal = async selector => {
    await page.evaluate(async () => { await persistencePromise; });
    if (await page.locator("#toast.visible").count()) await page.locator("#toast-close").click();
    await page.evaluate(value => scrollCandidateDetailTargetIntoView(elements["assessment-panel"].querySelector(value)), selector);
    try { await page.waitForFunction(value => {
      const target = elements["assessment-panel"].querySelector(value);
      const pane = elements["assessment-panel"].querySelector(".assessment-content");
      if (!target || !pane) return false;
      const box = target.getBoundingClientRect();
      const bounds = pane.getBoundingClientRect();
      return box.top >= bounds.top - 1 && box.bottom <= bounds.bottom + 1;
    }, selector); } catch (error) {
      const geometry = await page.evaluate(value => {
        const target = elements["assessment-panel"].querySelector(value);
        const pane = elements["assessment-panel"].querySelector(".assessment-content");
        return { view: state.currentView, pane: state.candidatePane, selector: value, targetFound: Boolean(target), targetVisible: Boolean(target?.getClientRects().length), targetTop: target?.getBoundingClientRect().top, targetBottom: target?.getBoundingClientRect().bottom, paneTop: pane?.getBoundingClientRect().top, paneBottom: pane?.getBoundingClientRect().bottom };
      }, selector);
      throw new Error(`Relationship control reveal failed: ${JSON.stringify(geometry)}`, { cause: error });
    }
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
    assert(await page.evaluate(({ key, issueId }) => {
      const candidate = state.assessedCandidates.find(item => item.key === key);
      return getRelationshipReviewState(candidate).status === 'unchanged' && getOpenRuleIssues().some(issue => issue.id === issueId);
    }, fixture), "Untouched off-Plan baseline became a new validation obligation or lost its original issue");
    assert(await page.locator('#assessment-panel [data-relationship-review-status]').count() === 0, "Untouched baseline exposes a fresh relationship task");
    assert(await page.evaluate(() => getPreviewReadiness().openRuleIssueCount === 0), "Off-Plan proposal conflict blocks the projected catalog despite remaining visible as baseline evidence");
    await page.evaluate(key => checkRuleRelationships(state.assessedCandidates.find(item => item.key === key)), fixture.key);
    assert(calls === 0, "An untouched proposal launched a relationship request");
    await (await reveal('[data-rule-action="add"]')).check();
    await (await reveal('[data-decision-field="rationale"]')).fill('Add the selected proposal after resolving its existing relationship issue.');
    await page.locator('#assessment-panel [data-rationale-save]').click();
    assert(await page.evaluate(key => {
      const candidate = state.assessedCandidates.find(item => item.key === key);
      return getDecision(candidate).inPlan && getRelationshipReviewState(candidate).status === 'required' && !getPlanReadiness(candidate).ready;
    }, fixture.key), "Add of unchanged wording bypassed current relationship validation");
    assert(await page.evaluate(() => getPreviewReadiness().openRuleIssueCount === 1 && !getPreviewReadiness().ready), "Planned Add did not make its existing baseline conflict relevant to publication");
    mode = 'conflict';
    await (await reveal('[data-relationship-review-open]')).click();
    await page.waitForFunction(key => getRelationshipReviewState(state.assessedCandidates.find(item => item.key === key)).status === 'findings', fixture.key);
    assert(await page.evaluate(key => !getPlanReadiness(state.assessedCandidates.find(item => item.key === key)).ready, fixture.key), "An unresolved conflict allowed the planned Add to become Ready");
    assert(await page.evaluate(() => !getPreviewReadiness().ready && getPreviewReadiness().missingRelationshipReviewCount === 1), "Current relationship findings did not block Review Changes");
    assert(await page.evaluate(issueId => getRuleIssueState(state.ruleIssues.find(issue => issue.id === issueId)).status === "unresolved", fixture.issueId),
      "A current matching finding incorrectly marked its original issue resolved");
    await (await reveal('[data-rule-action="no-change"]')).check();
    assert(await page.evaluate(({ key, issueId }) => {
      const candidate = state.assessedCandidates.find(item => item.key === key);
      return !getDecision(candidate).inPlan && getRelationshipReviewState(candidate).status === 'unchanged'
        && Boolean(state.session.relationshipReviews[key]) && getOpenRuleIssues().some(issue => issue.id === issueId);
    }, fixture), "Removing an untouched proposal from Plan left a fresh task or hid baseline issues through an old review");
    assert(await page.locator('#assessment-panel [data-relationship-review-status]').count() === 0, "Retained review records forced untouched baseline validation");
    assert(await page.evaluate(() => getPreviewReadiness().openRuleIssueCount === 0), "Returning the untouched proposal off-Plan left a projected catalog issue blocker");
    mode = 'success';
    const editor = await reveal('[data-decision-field="proposedText"]');
    await editor.fill(fixture.text + " Preserve explicit edited wording.");
    assert(await page.locator('#assessment-panel [data-rule-action="no-change"]').count() === 0
      && await page.locator("#assessment-panel [data-rule-action]:checked").count() === 0, "Edited wording retained No Change or silently chose another action");
    await page.locator("#assessment-panel [data-proposed-text-save]").click();
    await (await reveal("[data-relationship-review-open]")).click();
    await page.waitForFunction(key => getRelationshipReviewState(state.assessedCandidates.find(item => item.key === key)).status === "current", fixture.key);
    assert(await page.evaluate(({ key, issueId }) => !getDecision(state.assessedCandidates.find(item => item.key === key)).inPlan
      && getOpenRuleIssues().some(issue => issue.id === issueId), fixture), "Off-Plan edited preview cleared original adjudicated issue evidence");
    const add = await reveal('[data-rule-action="add"]');
    await add.check();
    assert(await page.locator("#assessment-panel [data-rationale-save]").isDisabled(), "An empty rationale can save a changed rule decision");
    const rationale = await reveal('[data-decision-field="rationale"]');
    await rationale.fill("Retain the original obligations while making the proposed wording explicit.");
    await page.locator("#assessment-panel [data-rationale-save]").click();
    await page.waitForFunction(key => getDecision(state.assessedCandidates.find(candidate => candidate.key === key)).inPlan, fixture.key);
    assert(await page.evaluate(key => {
      const candidate = state.assessedCandidates.find(item => item.key === key);
      const readiness = getPlanReadiness(candidate);
      return getRelationshipReviewState(candidate).status === "stale" && readiness.label === "Revalidation Required" && !readiness.ready;
    }, fixture.key), "Edited planned rule did not retain a stale review and block readiness until revalidation");
    const check = await reveal("[data-relationship-review-open]");
    await check.click();
    await page.waitForFunction(key => getRelationshipReviewState(state.assessedCandidates.find(candidate => candidate.key === key)).status === "current", fixture.key);
    assert(await page.evaluate(key => getPlanReadiness(state.assessedCandidates.find(candidate => candidate.key === key)).ready, fixture.key), "A clean check did not satisfy Plan relationship readiness");
    assert(await page.evaluate(issueId => getRuleIssueState(state.ruleIssues.find(issue => issue.id === issueId)).status === "resolved"
      && state.ruleIssues.some(issue => issue.id === issueId), fixture.issueId), "Current clean review lost retained issue history or failed to derive resolved state");
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
    const hardDetails = page.locator('#assessment-panel [data-relationship-review-failure-details]');
    await hardDetails.locator('summary').click();
    assert((await hardDetails.textContent()).includes('runtime-unavailable') && (await hardDetails.textContent()).includes('restart'), "Fix-first failure does not expose its bounded code and recovery action");
    const clientPolicies = await page.evaluate(() => {
      const missing = getRelationshipReviewClientFailure('runtime-missing');
      const unexpected = getRelationshipReviewClientFailure('SYNTHETIC_SENSITIVE_VALUE');
      return { missing, unexpected };
    });
    assert(clientPolicies.missing.code === 'runtime-missing' && !clientPolicies.missing.retryable && clientPolicies.missing.recovery === 'restart-and-reload'
      && !clientPolicies.missing.message.includes('diagnostics'), "Missing runtime is misclassified as a proposal correction or inaccessible diagnostics");
    assert(clientPolicies.unexpected.code === 'unexpected-failure' && clientPolicies.unexpected.recovery === 'report-failure'
      && !clientPolicies.unexpected.message.includes('SYNTHETIC_SENSITIVE_VALUE'), "Unknown client errors expose arbitrary exception text or nonexistent diagnostics");
    await page.evaluate(key => {
      const candidate = state.assessedCandidates.find(item => item.key === key);
      globalThis.__relationshipJourneyHardFailure = structuredClone(state.session.relationshipReviews[key].failure);
      state.session.relationshipReviews[key].failure = { code: 'runtime-unavailable', message: 'Check Workbench diagnostics before trying again.', retryable: false, recovery: 'correct-and-recheck' };
      syncRelationshipReviewControls(candidate);
    }, fixture.key);
    const legacyBanner = page.locator('#assessment-panel .error-banner');
    assert((await legacyBanner.textContent()).includes('Restart it with the current source') && !(await legacyBanner.textContent()).includes('Check Workbench diagnostics'), "Retained missing-runtime failure still points to nonexistent diagnostics");
    await page.evaluate(key => {
      const candidate = state.assessedCandidates.find(item => item.key === key);
      state.session.relationshipReviews[key].failure = globalThis.__relationshipJourneyHardFailure;
      delete globalThis.__relationshipJourneyHardFailure;
      syncRelationshipReviewControls(candidate);
    }, fixture.key);
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
