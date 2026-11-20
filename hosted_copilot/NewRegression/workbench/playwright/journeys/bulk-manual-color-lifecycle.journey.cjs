const { mockRelationshipReviews, openWorkbench, getCandidateHierarchy, getCssTokenColor, revealCandidate, reviewCandidateRelationships } = require("../helpers/workbench.cjs");

const behaviorIds = [
  "WB-UX-OWNERSHIP-001",
  "WB-UX-OWNERSHIP-002",
  "WB-UX-OWNERSHIP-003",
  "WB-UX-OWNERSHIP-004"
];

async function inspectCandidate(page, candidateKey) {
  const hierarchy = await getCandidateHierarchy(page, candidateKey);
  return page.evaluate(({ key, hierarchy }) => {
    const candidate = state.candidates.find((item) => item.key === key);
    const decision = getDecision(candidate);
    const row = document.querySelector(`[data-candidate-key="${key}"]`);
    const parentRows = hierarchy.parentIds.map((id) => document.querySelector(`#candidate-list [data-node-id="${CSS.escape(id)}"]`));
    const inspectNode = (parentRow) => {
      const label = parentRow.querySelector(".candidate-parent-label > strong, .source-summary-label > strong");
      const icon = parentRow.querySelector(".candidate-parent-decoration-icon");
      return {
        classes: parentRow.className,
        color: getComputedStyle(label).color,
        iconColor: getComputedStyle(icon).color,
        iconHidden: icon.hasAttribute("hidden"),
        description: parentRow.querySelector(".candidate-decoration-description").textContent
      };
    };
    const leafIcon = row.querySelector(".candidate-decoration-icon");
    return {
      decision: {
        action: decision.action,
        inPlan: decision.inPlan,
        source: decision.planMembershipSource,
        bulkOperationId: decision.bulkOperationId,
        rationale: decision.rationale
      },
      operationOwnsCandidate: state.session.bulkOperations.some((operation) => operation.candidateKeys.includes(key)),
      bulkUndoDisabled: elements["bulk-undo"].disabled,
      leaf: {
        classes: row.className,
        color: getComputedStyle(row.querySelector(".candidate-tree-copy strong")).color,
        iconColor: getComputedStyle(leafIcon).color,
        iconHidden: leafIcon.hasAttribute("hidden"),
        description: row.querySelector(".candidate-decoration-description").textContent
      },
      category: inspectNode(parentRows.at(-1)),
      source: inspectNode(parentRows[0])
    };
  }, { key: candidateKey, hierarchy });
}

function hierarchyMatches(snapshot, status, color) {
  const className = status === "ready" ? "ready" : "needs-input";
  return snapshot.leaf.classes.includes(`candidate-decoration-${className}`)
    && snapshot.category.classes.includes(`candidate-aggregate-${className}`)
    && snapshot.source.classes.includes(`candidate-aggregate-${className}`)
    && [snapshot.leaf, snapshot.category, snapshot.source].every((item) => item.color === color && item.iconColor === color && !item.iconHidden);
}

async function run({ page, baseUrl, assert, playback }) {
  const reviews = await mockRelationshipReviews(page);
  await openWorkbench(page, baseUrl);
  const sessionSnapshot = await page.evaluate(() => structuredClone(state.session));
  const addedColor = await getCssTokenColor(page, "--added-resource");
  const accentColor = await getCssTokenColor(page, "--accent-bright");
  const needsInputColor = await getCssTokenColor(page, "--modified-resource");

  try {
    const candidate = await page.evaluate(() => {
      const item = getBulkActionCandidates("add").find((candidate) => candidate.sourceType === "interactive");
      return { key: item.key, id: item.id };
    });
    await page.locator("#search-input").fill(candidate.id);
    const row = page.locator(`[data-candidate-key="${candidate.key}"]`);

    await page.locator("#bulk-actions > summary").click();
    await page.locator('#bulk-actions [data-bulk-scope="add"]').click();
    await page.waitForFunction(key => getDecision(state.candidates.find(item => item.key === key)).inPlan, candidate.key);
    assert(await page.evaluate(key => !getPlanReadiness(state.candidates.find(item => item.key === key)).ready, candidate.key)
      && reviews.count === 0, "Bulk Add bypassed relationship readiness or invoked AI automatically");
    await reviewCandidateRelationships(page, candidate.key);
    const reviewed = await page.evaluate(key => {
      const candidate = state.candidates.find(item => item.key === key);
      const readiness = getPlanReadiness(candidate);
      const row = document.querySelector(`[data-candidate-key="${key}"]`);
      return { ready: readiness.ready, attention: readiness.attention?.reason, label: readiness.label, rowClass: row?.className };
    }, candidate.key);
    assert(reviewed.ready && reviewed.rowClass?.includes("candidate-decoration-ready"),
      `Current relationship review did not update candidate readiness decoration: ${JSON.stringify(reviewed)}`);
    await page.locator('[data-candidate-pane="candidates"]').click();
    await page.waitForFunction((key) => document.querySelector(`[data-candidate-key="${key}"]`)?.classList.contains("candidate-decoration-ready"), candidate.key);
    await playback.show(page, "Bulk ownership · ready green hierarchy");
    const bulkReady = await inspectCandidate(page, candidate.key);
    assert(bulkReady.decision.source === "bulk" && Boolean(bulkReady.decision.bulkOperationId) && bulkReady.operationOwnsCandidate, "Bulk Add did not record bulk ownership");
    assert(hierarchyMatches(bulkReady, "ready", addedColor), "Bulk Add did not color the leaf, category, and source green");
    assert(bulkReady.leaf.description === "Selected, ready for promotion" && bulkReady.category.description === "1 selected, all ready for promotion" && bulkReady.source.description === "1 selected, all ready for promotion", "Bulk-ready accessible descriptions are incorrect");

    await row.locator(".candidate-tree-copy").click();
    await page.locator('#assessment-panel [data-rule-action="no-change"]').click();
    assert(await page.evaluate(key => getDecision(state.candidates.find(item => item.key === key)).inPlan, candidate.key),
      "Selecting No Change changed the saved Plan before explicit Save");
    await page.locator("#assessment-panel [data-rationale-save]").click();
    await page.evaluate(() => persistencePromise);
    await page.locator('[data-candidate-pane="candidates"]').click();
    await page.waitForFunction((key) => {
      const row = document.querySelector(`[data-candidate-key="${key}"]`);
      return row && !row.classList.contains("candidate-decoration-ready") && !row.classList.contains("candidate-decoration-needs-input");
    }, candidate.key);
    await playback.show(page, "No Change reset · neutral hierarchy");
    const reset = await inspectCandidate(page, candidate.key);
    assert(reset.decision.source === "none" && reset.decision.bulkOperationId === null && !reset.operationOwnsCandidate, "No Change did not clear bulk ownership and restore the default decision");
    assert(reset.decision.action === "no-change" && reset.bulkUndoDisabled, "No Change did not return the candidate to an unselected neutral state");

    await row.locator(".candidate-tree-copy").click();
    await page.locator('#assessment-panel [data-rule-action="add"]').click();
    await page.locator('#assessment-panel [data-decision-field="rationale"]').fill("Maintainer manually confirmed this Add decision after bulk review.");
    await page.locator("#assessment-panel [data-rationale-save]").click();
    await page.evaluate(() => persistencePromise);
    assert(reviews.count === 1, "Saving Manual Add invoked relationship evaluation automatically");
    const manualReviewStatus = await page.evaluate(key => getRelationshipReviewState(state.candidates.find(item => item.key === key)).status, candidate.key);
    assert(manualReviewStatus === "current", "Saving an unchanged Manual Add invalidated its saved relationship check");
    await page.locator('[data-candidate-pane="candidates"]').click();
    await page.waitForFunction((key) => document.querySelector(`[data-candidate-key="${key}"]`)?.classList.contains("candidate-decoration-ready"), candidate.key);
    await playback.show(page, "Manual ownership · completed green hierarchy");
    const manualReady = await inspectCandidate(page, candidate.key);
    assert(manualReady.decision.source === "manual" && manualReady.decision.action === "add" && manualReady.decision.rationale.startsWith("Maintainer manually confirmed"), "Completed decision did not retain Manual ownership and rationale");
    assert(hierarchyMatches(manualReady, "ready", addedColor), "Completed Manual decision did not return the full hierarchy to green");

    await row.locator("[data-decision-key]").uncheck();
    await page.waitForFunction((key) => !document.querySelector(`[data-candidate-key="${key}"]`)?.classList.contains("candidate-decoration-ready"), candidate.key);
    await playback.show(page, "Manual ownership · unselected neutral hierarchy");
    const unselected = await inspectCandidate(page, candidate.key);
    assert(!unselected.decision.inPlan && unselected.decision.source === "none" && unselected.decision.bulkOperationId === null, "Unselect did not remove only plan membership");
    assert(unselected.decision.action === "add" && unselected.decision.rationale.startsWith("Maintainer manually confirmed"), "Unselect did not preserve the Manual action and rationale");
    assert(unselected.leaf.color === accentColor && unselected.leaf.iconHidden && !unselected.leaf.description, "Unselected leaf did not return to neutral blue");
    assert(!unselected.category.classes.includes("candidate-aggregate-") && !unselected.source.classes.includes("candidate-aggregate-"), "Unselected ancestors retained aggregate decoration");

    await page.locator('[data-view="preview"]').click();
    const preview = await page.evaluate(() => ({
      proposedChangeCount: document.querySelectorAll("#preview-diff .preview-review-file").length,
      payloadChangeCount: document.querySelectorAll("#preview-payload-diff .preview-review-file").length,
      rawChangeCount: document.querySelectorAll("#preview-json .preview-review-file").length,
      proposedEmptyTitle: document.querySelector("#preview-diff .preview-empty-state h3")?.textContent,
      payloadEmptyTitle: document.querySelector("#preview-payload-diff .preview-empty-state h3")?.textContent,
      rawEmptyTitle: document.querySelector("#preview-json .preview-empty-state h3")?.textContent
    }));
    assert(preview.proposedChangeCount === 0 && preview.proposedEmptyTitle === "No Proposed Changes", "Unselected decision remained in Proposed Changes");
    assert(preview.payloadChangeCount === 0 && preview.payloadEmptyTitle === "No Payload Changes", "Unselected decision remained in Payload Changes");
    assert(preview.rawChangeCount === 0 && preview.rawEmptyTitle === "No Resulting Catalog", "Unselected decision remained in the Resulting Catalog");

    await page.locator('[data-view="catalog"]').click();
    await page.locator("#search-input").fill("");
    const siblings = await page.evaluate(() => {
      const good = state.candidates.find(item => getEffectiveHostedRuleId(item) === "IMPL-PATCH-001");
      const pending = state.candidates.find(item => getEffectiveHostedRuleId(item) === "REVIEW-REPO-001");
      if (!good || !pending) throw new Error("Mixed sibling validation fixture is missing");
      return { good: good.key, pending: pending.key, text: getDecision(good).proposedText };
    });
    await revealCandidate(page, siblings.good);
    const goodRow = page.locator(`[data-candidate-key="${siblings.good}"]`);
    await goodRow.locator(".candidate-tree-copy").click();
    await page.locator('#assessment-panel [data-rule-action="update"]').check();
    await page.locator('#assessment-panel [data-decision-field="rationale"]').fill("Synthetic mixed-sibling validation: preserve the clearing safeguard.");
    await page.locator("#assessment-panel [data-rationale-save]").click();
    await page.evaluate(() => persistencePromise);
    await reviewCandidateRelationships(page, siblings.good);
    const savedReview = await page.evaluate(key => JSON.stringify(state.session.relationshipReviews[key]), siblings.good);
    await page.locator('[data-candidate-pane="candidates"]').click();
    await revealCandidate(page, siblings.pending);
    const pendingRow = page.locator(`[data-candidate-key="${siblings.pending}"]`);
    await pendingRow.locator(".candidate-tree-copy").click();
    await page.locator('#assessment-panel [data-rule-action="add"]').check();
    await page.locator('#assessment-panel [data-decision-field="rationale"]').fill("Synthetic mixed-sibling validation: leave this sibling awaiting review.");
    await page.locator("#assessment-panel [data-rationale-save]").click();
    await page.evaluate(() => persistencePromise);
    await page.locator('[data-candidate-pane="candidates"]').click();
    const mixedGood = await inspectCandidate(page, siblings.good);
    const mixedPending = await inspectCandidate(page, siblings.pending);
    assert(mixedGood.leaf.color === addedColor && mixedGood.leaf.iconColor === addedColor
      && hierarchyMatches(mixedPending, "needs-input", needsInputColor)
      && mixedGood.category.color === needsInputColor && mixedGood.source.color === needsInputColor
      && mixedGood.category.description === "2 selected, 1 needs input", "One pending sibling did not leave the checked child green and both ancestors amber");
    await pendingRow.locator("[data-decision-key]").uncheck();
    const withoutPending = await inspectCandidate(page, siblings.good);
    assert(hierarchyMatches(withoutPending, "ready", addedColor)
      && await page.evaluate(({ key, saved }) => JSON.stringify(state.session.relationshipReviews[key]) === saved, { key: siblings.good, saved: savedReview }),
      "Unselecting the pending sibling transferred its attention to the unchanged checked rule");
    await pendingRow.locator("[data-decision-key]").check();
    assert(await page.evaluate(({ key, saved }) => getRelationshipReviewState(state.candidates.find(item => item.key === key)).status === "current"
      && JSON.stringify(state.session.relationshipReviews[key]) === saved, { key: siblings.good, saved: savedReview }),
      "Reselecting an unchanged sibling invalidated or replaced the checked rule's review");
    await pendingRow.locator("[data-decision-key]").uncheck();
    await goodRow.locator(".candidate-tree-copy").click();
    const editedText = siblings.text + " Verify that the clearing value is sent.";
    await page.locator('#assessment-panel [data-decision-field="proposedText"]').fill(editedText);
    await page.locator("#assessment-panel [data-proposed-text-save]").click();
    await page.waitForFunction(({ key, text }) => getDecision(state.candidates.find(item => item.key === key)).proposedText === text,
      { key: siblings.good, text: editedText });
    await page.locator('[data-candidate-pane="candidates"]').click();
    await pendingRow.locator("[data-decision-key]").check();
    const edited = await inspectCandidate(page, siblings.good);
    assert(hierarchyMatches(edited, "needs-input", needsInputColor)
      && edited.category.description === "2 selected, 2 need input"
      && await page.evaluate(key => state.session.relationshipReviews[key]?.status === "stale"
        && !getCurrentRelationshipReview(state.candidates.find(candidate => candidate.key === key)), siblings.good),
      "Reselecting a sibling revived the edited rule's invalidated review or produced incorrect ancestor colors");
    await reviewCandidateRelationships(page, siblings.good);
    const rechecked = await inspectCandidate(page, siblings.good);
    assert(rechecked.leaf.color === addedColor && rechecked.leaf.iconColor === addedColor
      && rechecked.category.color === needsInputColor && rechecked.source.color === needsInputColor
      && rechecked.category.description === "2 selected, 1 needs input", "Checking edited wording did not refresh the mixed hierarchy immediately");
    const checksBeforeRestoring = reviews.count;
    const priorRequestId = await page.evaluate(key => state.session.relationshipReviews[key].result.requestId, siblings.good);
    await page.locator('#assessment-panel [data-decision-field="proposedText"]').fill(siblings.text);
    await page.locator("#assessment-panel [data-proposed-text-save]").click();
    await page.waitForFunction(({ key, text }) => getDecision(state.candidates.find(item => item.key === key)).proposedText === text,
      { key: siblings.good, text: siblings.text });
    assert(await page.evaluate(key => state.session.relationshipReviews[key]?.status === "stale"
      && getRelationshipReviewState(state.candidates.find(item => item.key === key)).status === "stale"
      && !getCurrentRelationshipReview(state.candidates.find(item => item.key === key))
      && !getPlanReadiness(state.candidates.find(item => item.key === key)).ready, siblings.good),
      "Saving earlier wording resurrected an invalidated check without revalidation");
    assert(reviews.count === checksBeforeRestoring, "Saving earlier wording invoked relationship evaluation automatically");
    const restoredBeforeCheck = await inspectCandidate(page, siblings.good);
    assert(hierarchyMatches(restoredBeforeCheck, "needs-input", needsInputColor)
      && restoredBeforeCheck.category.description === "2 selected, 2 need input",
      "Restoring earlier wording did not retain pending readiness in the leaf and ancestors");

    await reviews.dispose();
    const [recheckRequest] = await Promise.all([
      page.waitForRequest(request => new URL(request.url()).pathname === "/check-relationships" && request.method() === "POST"),
      reviewCandidateRelationships(page, siblings.good)
    ]);
    const request = JSON.parse(Buffer.from(recheckRequest.postDataJSON().payloadBase64, "base64").toString("utf8"));
    const subject = request.proposals.find(proposal => proposal.candidateKey === siblings.good);
    assert(request.candidateKey === siblings.good && subject
      && Buffer.from(subject.proposedTextBase64, "base64").toString("utf8") === siblings.text,
      "The production recheck did not receive the exact restored earlier wording");
    assert(request.requestId !== priorRequestId, "Restored-wording revalidation reused the earlier check's request identity");
    const completedRecheck = await page.evaluate(async ({ key, requestId, text }) => {
      const candidate = state.candidates.find(item => item.key === key);
      const review = getCurrentRelationshipReview(candidate);
      const persisted = await readSession(state.session.id);
      return {
        current: getRelationshipReviewState(candidate).status === "current" && review?.result.requestId === requestId,
        ready: getPlanReadiness(candidate).ready,
        wording: getDecision(candidate).proposedText === text,
        evaluatedWording: review?.result.comparisonRules.some(rule => rule.id === getEffectiveHostedRuleId(candidate) && rule.text === text),
        persisted: persisted.relationshipReviews[key]?.status === "current"
          && persisted.relationshipReviews[key]?.result.requestId === requestId
          && persisted.decisions[key]?.proposedText === text
      };
    }, { key: siblings.good, requestId: request.requestId, text: siblings.text });
    assert(Object.values(completedRecheck).every(Boolean),
      `Production revalidation did not persist a new current, ready result for restored wording: ${JSON.stringify(completedRecheck)}`);
    const restoredAfterCheck = await inspectCandidate(page, siblings.good);
    assert(restoredAfterCheck.leaf.color === addedColor && restoredAfterCheck.leaf.iconColor === addedColor
      && restoredAfterCheck.category.color === needsInputColor && restoredAfterCheck.source.color === needsInputColor
      && restoredAfterCheck.category.description === "2 selected, 1 needs input",
      "The completed production recheck did not restore the older wording's green leaf while preserving the pending sibling");
  } finally {
    await reviews.dispose();
    await page.evaluate(async (snapshot) => {
      state.session = snapshot;
      await persistSession();
      renderCandidateList();
      renderBulkSelectionOutputs();
    }, sessionSnapshot);
  }
}

module.exports = { name: "bulk to manual color lifecycle", behaviorIds, viewport: { width: 1180, height: 900 }, run };
