const { openWorkbench } = require("../helpers/workbench.cjs");

const behaviorIds = [
  "WB-UX-ASSESSMENT-001",
  "WB-UX-OVERRIDE-001",
  "WB-UX-DECISION-001",
  "WB-UX-CAPACITY-001",
  "WB-UX-SYNC-001",
  "WB-UX-BACKTOTOP-001"
];

async function openAssessmentResult(page, query) {
  await page.locator('[data-workspace-tab="assessment-results"]').click();
  await page.locator('[data-assessment-pane="assessments"]').click();
  await page.locator("#search-input").fill(query);
  const row = page.locator("#assessment-results-list [data-assessment-key]").first();
  await row.waitFor({ state: "visible" });
  await row.click();
  await page.locator("#assessment-results-detail").waitFor({ state: "visible" });
  return row;
}

async function openCandidate(page, query) {
  await page.locator('[data-workspace-tab="candidate-sources"]').click();
  await page.locator('[data-candidate-pane="candidates"]').click();
  await page.locator("#search-input").fill(query);
  const row = page.locator("#candidate-list [data-candidate-key]").first();
  await row.waitFor({ state: "visible" });
  await row.locator(".candidate-tree-copy").click();
  await page.locator("#assessment-panel").waitFor({ state: "visible" });
  return row;
}

async function run({ page, baseUrl, assert, playback }) {
  await openWorkbench(page, baseUrl);
  const sessionSnapshot = await page.evaluate(() => structuredClone(state.session));
  const candidateTitle = "Excluded assessment alpha";
  const initialHostedId = "REVIEW-EXCL-001";
  const selectedHostedId = initialHostedId;
  const initialRationale = "Phase 0 confirms this excluded assessment belongs in Hosted review.";
  const updatedRationale = "Phase 0 confirms the persisted override remains required for Hosted review.";
  const decisionRationale = "Promote the contested assessment as deterministic Hosted regression coverage.";

  try {
    await playback.show(page, "Assessment Results · search, sort, details, and return");
    await page.locator('[data-workspace-tab="assessment-results"]').click();
    await page.locator('#assessment-results-list [data-node-id="assessment:source:interactive"]').click();
    await page.locator('#assessment-results-list [data-node-id^="assessment:category:interactive:"]').first().click();
    const initialOrder = await page.locator("#assessment-results-list [data-assessment-key] .candidate-tree-copy strong").allTextContents();
    assert(initialOrder.join("|") === "REVIEW-EXCL-001|REVIEW-EXCL-002", `Assessment Results initial order is incorrect: ${initialOrder.join("|")}`);
    await page.locator('#assessment-results-list [data-assessment-sort="candidate"]').click();
    const descendingOrder = await page.locator("#assessment-results-list [data-assessment-key] .candidate-tree-copy strong").allTextContents();
    assert(descendingOrder.join("|") === "REVIEW-EXCL-002|REVIEW-EXCL-001", `Assessment Results sort did not reverse the fixture order: ${descendingOrder.join("|")}`);

    await page.locator("#search-input").fill(candidateTitle);
    const assessmentRows = page.locator("#assessment-results-list [data-assessment-key]");
    assert(await assessmentRows.count() === 1, "Assessment Results search did not isolate the expected excluded result");
    const candidateKey = await assessmentRows.first().getAttribute("data-assessment-key");
    await assessmentRows.first().click();
    const details = page.locator("#assessment-results-detail");
    assert(await details.locator(".detail-identity span").last().textContent() === initialHostedId, "Assessment Details opened the wrong result");
    assert((await details.locator(".evidence-box").first().textContent()).includes("explicit override rationale"), "Assessment Details omitted the source evidence");
    assert((await details.getByText("Excluded behavior remains available for maintainer audit.", { exact: true }).count()) === 1, "Assessment Details omitted the AI evaluation evidence");
    assert((await details.getByText("No Hosted rule is required for this excluded behavior.", { exact: true }).count()) === 1, "Assessment Details omitted related Hosted coverage");
    await page.locator('[data-assessment-pane="assessments"]').click();
    assert(await page.locator("#assessment-results-list-panel").isVisible() && await details.isHidden(), "Assessment Details return navigation did not restore the results list");

    await openAssessmentResult(page, candidateTitle);
    await page.locator("[data-override-open]").click();
    const overrideForm = page.locator(".override-form");
    assert(await overrideForm.isVisible(), "Contest Assessment did not open the override form");
    await overrideForm.locator("textarea").fill(initialRationale);
    assert(!await overrideForm.locator("[data-override-apply]").isDisabled(), "Override rationale did not enable Apply Override");
    await overrideForm.locator("[data-override-apply]").click();
    await page.locator("#candidate-sources-panel").waitFor({ state: "visible" });

    await page.locator("#search-input").fill(initialHostedId);
    const overriddenRow = page.locator("#candidate-list [data-candidate-key]").first();
    await overriddenRow.waitFor({ state: "visible" });
    assert(await overriddenRow.locator("[data-decision-key]").isChecked(), "Applied override did not add the candidate to the Promotion Plan");
    assert((await page.locator('#candidate-list [data-node-id="candidate:source:overrides"]').count()) === 1, "Applied override did not create the Overrides view");

    await openAssessmentResult(page, candidateTitle);
    await page.locator("[data-override-edit]").click();
    const savedRationale = page.locator("[data-saved-override-rationale]");
    assert(await savedRationale.isEditable(), "Edit Override Rationale did not make the saved rationale editable");
    await savedRationale.fill(updatedRationale);
    await page.locator("[data-override-save]").click();
    await page.waitForFunction(() => document.querySelector("[data-saved-override-rationale]")?.readOnly === true);
    assert(await page.locator("[data-saved-override-rationale]").inputValue() === updatedRationale, "Override rationale edit was not saved");
    assert(!await page.locator("[data-saved-override-rationale]").isEditable(), "Saved override rationale did not return to read-only mode");

    await openWorkbench(page, baseUrl);
    await openAssessmentResult(page, candidateTitle);
    assert(await page.locator("[data-saved-override-rationale]").inputValue() === updatedRationale, "Override rationale did not persist across reload");
    assert((await page.locator(".override-record-audit").textContent()).includes("@fixture-codeowner"), "Persisted override lost maintainer attribution");

    await playback.show(page, "Decision capture · synchronized Candidate, Assessment, Plan, and capacity state");
    const candidateRow = await openCandidate(page, initialHostedId);
    await page.locator('#assessment-panel [data-rule-action="add"]').click();
    const stagedAddScores = await page.locator("#assessment-panel .score-item strong").allTextContents();
    assert(stagedAddScores[1] === "+32" && stagedAddScores[2] === "4,808", `Staged Add did not project its exact token delta against global plan headroom: ${JSON.stringify(stagedAddScores)}`);
    await page.locator('#assessment-panel [data-rule-action="defer"]').click();
    const stagedDeferScores = await page.locator("#assessment-panel .score-item strong").allTextContents();
    assert(stagedDeferScores[1] === "0" && stagedDeferScores[2] === "4,840", `Staged Defer changed catalog tokens or global projected headroom: ${JSON.stringify(stagedDeferScores)}`);
    await page.locator('#assessment-panel [data-rule-action="no-change"]').click();
    const stagedNoChangeScores = await page.locator("#assessment-panel .score-item strong").allTextContents();
    assert(stagedNoChangeScores[1] === "0" && stagedNoChangeScores[2] === "4,840", `No Change did not restore zero token delta and global plan headroom: ${JSON.stringify(stagedNoChangeScores)}`);
    await page.locator('#assessment-panel [data-rule-action="add"]').click();
    await page.locator('#assessment-panel [data-decision-field="rationale"]').fill(decisionRationale);
    await page.locator("#assessment-panel [data-rationale-save]").click();
    await page.evaluate(() => persistencePromise);
    assert(await page.locator('#assessment-panel [data-rule-action="add"]').isChecked(), "Rule Action selection did not remain synchronized in Details");
    assert(await page.locator('#assessment-panel .rule-action-header .detail-identity span:last-child').innerText() === selectedHostedId, "Generated Hosted rule ID was not retained");
    assert(await page.locator('#assessment-panel [data-decision-field="rationale"]').inputValue() === decisionRationale, "Decision rationale was not retained");
    assert(await page.evaluate(() => getDecision(getActiveCandidate()).inPlan && getDecision(getActiveCandidate()).planMembershipSource === "manual"), "Saved promotion action did not create manual plan membership");

    await page.locator('[data-candidate-pane="candidates"]').click();
    await page.locator("#search-input").fill(candidateTitle);
    assert(await candidateRow.locator(".candidate-tree-copy strong").textContent() === selectedHostedId, "Candidate Sources did not synchronize the proposed Hosted identity");
    assert((await candidateRow.getAttribute("class")).includes("candidate-decoration-ready"), "Candidate Sources did not synchronize ready state");

    await page.locator('[data-workspace-tab="assessment-results"]').click();
    await page.locator("#search-input").fill(candidateTitle);
    const synchronizedAssessment = page.locator("#assessment-results-list [data-assessment-key]").first();
    assert(await synchronizedAssessment.locator(".candidate-tree-copy strong").textContent() === selectedHostedId, "Assessment Results did not synchronize the proposed Hosted identity");
    assert(await synchronizedAssessment.locator(".assessment-override-pill").textContent() === "Contested", "Assessment Results did not synchronize the override state");

    await page.locator('[data-view="plan"]').click();
    const planRow = page.locator("#plan-table-body [data-plan-row]").first();
    assert(await page.locator("#plan-table-body [data-plan-row]").count() === 1, "Promotion Plan contains an unexpected number of items");
    assert(await planRow.locator(".candidate-link").textContent() === selectedHostedId, "Promotion Plan did not synchronize the proposed Hosted identity");
    assert(await planRow.locator(".plan-action").innerText() === "Add", "Promotion Plan did not synchronize the selected action");
    assert(await planRow.locator("td").nth(6).innerText() === "Ready", "Promotion Plan did not synchronize decision readiness");

    const capacity = await page.locator("#capacity-panel .capacity-group").evaluateAll((groups) => Object.fromEntries(groups.map((group) => {
      const lines = group.querySelectorAll(".capacity-line");
      return [lines[0].querySelector(".capacity-label").textContent.trim(), {
        free: lines[0].querySelectorAll("strong")[1].textContent.trim(),
        equation: lines[1].querySelector("span").textContent.trim(),
        utilization: lines[1].querySelectorAll("span")[1].textContent.trim(),
        tooltip: group.dataset.workbenchTooltip,
        ariaLabel: group.querySelector("progress").getAttribute("aria-label")
      }];
    })));
    assert(JSON.stringify(capacity["Overall Hosted Guidance"]) === JSON.stringify({ free: "4,808 free", equation: "160 current + 32 draft", utilization: "3.84%", tooltip: "192 projected of 5,000", ariaLabel: "192 projected of 5,000" }), `Global guidance capacity did not equal the sum of all five buckets: ${JSON.stringify(capacity["Overall Hosted Guidance"])}`);
    assert(JSON.stringify(capacity["Repository-wide Guidance"]) === JSON.stringify({ free: "968 free", equation: "32 current + 0 draft", utilization: "3.2%", tooltip: "32 projected of 1,000", ariaLabel: "32 projected of 1,000" }), "Repository guidance capacity changed from the fixture baseline");
    assert(JSON.stringify(capacity["Implementation Instructions"]) === JSON.stringify({ free: "936 free", equation: "32 current + 32 draft", utilization: "6.4%", tooltip: "64 projected of 1,000", ariaLabel: "64 projected of 1,000" }), `Implementation capacity did not apply the exact 32-token generated-placement projection: ${JSON.stringify(capacity["Implementation Instructions"])}`);
    assert(JSON.stringify(capacity["Testing Supplement"]) === JSON.stringify({ free: "968 free", equation: "32 current + 0 draft", utilization: "3.2%", tooltip: "32 projected of 1,000", ariaLabel: "32 projected of 1,000" }), "Testing capacity changed from the fixture baseline");
    assert(JSON.stringify(capacity["Documentation Instructions"]) === JSON.stringify({ free: "968 free", equation: "32 current + 0 draft", utilization: "3.2%", tooltip: "32 projected of 1,000", ariaLabel: "32 projected of 1,000" }), "Documentation capacity changed from the fixture baseline");
    assert(JSON.stringify(capacity["Review Skill"]) === JSON.stringify({ free: "968 free", equation: "32 current + 0 draft", utilization: "3.2%", tooltip: "32 projected of 1,000", ariaLabel: "32 projected of 1,000" }), "Review Skill capacity changed from the fixture baseline");
    assert(await page.locator("#capacity-panel .capacity-group").count() === 6 && await page.locator("#capacity-panel .capacity-projected").count() === 0, "Guidance Capacity still renders overlapping combined rows or visible projected-detail rows");
    assert(await page.locator("#capacity-panel .score-item strong").textContent() === "32 tokens", "Draft item estimate did not equal the exact projected token delta");
    assert(await page.locator("#status-headroom").textContent() === "4,808", "Status bar did not synchronize global projected guidance headroom");

    const retireProjection = await page.evaluate(() => {
      const candidate = state.candidates.find((item) => {
        const decision = getDecision(item);
        return getAllowedActions(item, decision.proposedText).includes("retire")
          && getActionCapacityBucketNames(item, "retire", decision).length > 0;
      });
      if (!candidate) return { available: false };
      switchView("catalog");
      setWorkspaceTab("candidate-sources");
      selectCandidate(candidate.key);
      showCandidatePane("details");
      return {
        available: true,
        expectedDelta: -estimateGuardedTokens(getCurrentHostedText(candidate)),
        baselineHeadroom: Number(document.querySelector("#status-headroom").textContent.replaceAll(",", ""))
      };
    });
    assert(retireProjection.available, "Capacity fixture does not expose a mapped rule that can be retired");
    await page.locator('#assessment-panel [data-rule-action="retire"]').click();
    const stagedRetireScores = await page.locator("#assessment-panel .score-item strong").allTextContents();
    assert(stagedRetireScores[1] === String(retireProjection.expectedDelta) && Number(stagedRetireScores[2].replaceAll(",", "")) === retireProjection.baselineHeadroom - retireProjection.expectedDelta, `Staged Retire did not reclaim the current mapped rule tokens: ${JSON.stringify(stagedRetireScores)}`);
    await page.locator('#assessment-panel [data-rule-action="no-change"]').click();
    const revertedRetireScores = await page.locator("#assessment-panel .score-item strong").allTextContents();
    assert(revertedRetireScores[1] === "0" && Number(revertedRetireScores[2].replaceAll(",", "")) === retireProjection.baselineHeadroom, `No Change did not restore the pre-Retire projection: ${JSON.stringify(revertedRetireScores)}`);

    await page.locator('[data-view="catalog"]').click();
    await openCandidate(page, candidateTitle);
    const detailContent = page.locator("#assessment-panel > .assessment-content");
    const backToTop = page.locator("#assessment-panel [data-detail-back-to-top]");
    assert(await backToTop.isDisabled(), "Back to top is enabled before the Details pane is scrolled");
    await detailContent.evaluate((content) => { content.scrollTop = content.scrollHeight; });
    await page.waitForFunction(() => !document.querySelector("#assessment-panel [data-detail-back-to-top]").disabled);
    assert((await detailContent.evaluate((content) => content.scrollTop)) > 1, "Details pane did not accept real scrolling");
    await backToTop.click();
    await page.waitForFunction(() => {
      const content = document.querySelector("#assessment-panel > .assessment-content");
      const button = document.querySelector("#assessment-panel [data-detail-back-to-top]");
      return content.scrollTop <= 1 && button.disabled;
    });

    await openAssessmentResult(page, candidateTitle);
    await page.locator("[data-override-remove]").click();
    await page.waitForFunction((key) => {
      const candidate = state.assessedCandidates.find((item) => item.key === key);
      return candidate && !getApplicabilityOverride(candidate) && !state.candidates.some((item) => item.key === key);
    }, candidateKey);
    await page.evaluate(() => persistencePromise);
    await page.locator("#search-input").fill(candidateTitle);
    assert(await page.locator(`#assessment-results-list [data-assessment-key="${candidateKey}"] .assessment-override-pill`).textContent() === "None", "Removing the override did not clear Assessment Results state");
    await page.locator('[data-workspace-tab="candidate-sources"]').click();
    await page.locator("#search-input").fill(candidateTitle);
    assert(await page.locator(`#candidate-list [data-candidate-key="${candidateKey}"]:visible`).count() === 0, "Removing the override left the excluded candidate visible in Candidate Sources");
    await page.locator('[data-view="plan"]').click();
    assert(await page.locator("#plan-table-body [data-plan-row]").count() === 0, "Removing the override left its decision in the Promotion Plan");
  } finally {
    await page.evaluate(async (snapshot) => {
      state.session = snapshot;
      state.activeKey = null;
      state.assessmentActiveKey = null;
      state.assessmentOverrideEditingKey = null;
      refreshEffectiveCandidates();
      await persistSession();
      renderAll();
      switchView("catalog");
      setWorkspaceTab("candidate-sources");
      showCandidatePane("candidates");
    }, sessionSnapshot).catch(() => {});
  }
}

module.exports = { name: "assessment review lifecycle", behaviorIds, viewport: { width: 1180, height: 900 }, run };
