const { openWorkbench } = require("../helpers/workbench.cjs");
const { createSavedRuleEvaluation } = require("../helpers/saved-rule-evaluation.cjs");

const behaviorIds = ["WB-UX-DETAILS-001", "WB-UX-DETAILS-002", "WB-UX-DETAILS-003"];

async function verifyDetailLayout(panel, assert, context) {
  const snapshot = await panel.evaluate((node) => {
    const audit = node.id === "assessment-results-detail";
    const candidate = state.assessedCandidates.find((item) => item.key === (audit ? state.assessmentActiveKey : state.activeKey));
    const sources = node.querySelector('[data-evidence-kind="sources"]');
    const coverage = node.querySelector('[data-evidence-kind="coverage"]');
    const evidence = node.querySelector("[data-assessment-evidence]");
    const heading = evidence?.querySelector(".assessment-details-heading");
    const info = evidence?.querySelector(".information-panel.assessment-context");
    const strip = evidence?.querySelector(".score-strip");
    const factors = evidence?.querySelector(".factor-groups");
    const ordered = [sources, ...(audit ? [coverage] : []), heading, info, strip, factors, node.querySelector(".proposed-rule-heading")];
    const previousEvidence = audit ? coverage : sources;
    const cards = [...(strip?.querySelectorAll(".score-item") || [])];
    const borderColor = getComputedStyle(node.querySelector(".factor-group")).borderTopColor;
    const actions = node.querySelector(".rule-actions");
    const actionHeading = actions?.querySelector(":scope > .section-label");
    const actionId = actionHeading?.querySelector(".rule-reference");
    const actionInfo = actions?.querySelector(".rule-actions-guidance");
    const controls = actions?.querySelector(".rule-actions-content");
    const modelGroup = actions?.querySelector(".implementation-model-control-group");
    const proposed = node.querySelector('[data-decision-field="proposedText"]');
    const rationale = actions?.querySelector('[data-decision-field="rationale"]');
    const override = node.querySelector(".maintainer-override");
    const overrideHeading = override?.querySelector(":scope > .section-label");
    const overrideBanner = override?.querySelector(":scope > .information-panel");
    const overrideIcon = overrideBanner?.querySelector(":scope > svg");
    const savedOverride = Boolean(override?.querySelector(".override-record"));
    const editorProperties = ["backgroundColor", "borderTopColor", "borderTopWidth", "borderRadius", "padding", "font", "minHeight", "resize"];
    return {
      order: ordered.every((item, index) => item && (!index || (ordered[index - 1].compareDocumentPosition(item) & Node.DOCUMENT_POSITION_FOLLOWING))),
      boundary: previousEvidence.nextElementSibling === evidence
        && getComputedStyle(previousEvidence).borderBottomStyle === "solid"
        && getComputedStyle(previousEvidence).paddingBottom === "15px"
        && getComputedStyle(evidence).paddingTop === "15px"
        && Math.abs(heading.getBoundingClientRect().top - previousEvidence.getBoundingClientRect().bottom - 15) < 1,
      assistance: audit ? !node.querySelector("[data-rule-assistance]") : !coverage && Boolean(node.querySelector("[data-rule-assistance]")),
      info: heading.nextElementSibling === info && info.nextElementSibling === strip
        && !info.querySelector("button")
        && info.querySelector("p > strong")?.textContent === "Assessment:"
        && info.textContent.includes("Token Cost and Token Headroom reflect the current draft."),
      informationFill: [...node.querySelectorAll(".information-panel:not(.rule-action-resolution-information)")].every((banner) => {
        const style = getComputedStyle(banner);
        return style.backgroundColor === "rgba(0, 40, 72, 0.31)" && style.opacity === "1"
          && style.color === "rgb(255, 255, 255)" && style.borderTopColor === "rgb(0, 76, 135)"
          && style.borderLeftColor === "rgb(58, 160, 243)";
      }),
      labels: cards.map((card) => card.querySelector("span").textContent).join("|") === "Priority Score:|Token Cost:|Token Headroom:",
      rationaleLabel: node.querySelector("[data-assessment-explanation] strong")?.textContent === "Assessment rationale:",
      metricStyle: cards.length === 3 && getComputedStyle(strip).gap === "12px" && cards.every((card) => {
        const label = card.querySelector("span");
        const value = card.querySelector("strong");
        const style = getComputedStyle(label);
        return style.color === "rgb(255, 255, 255)" && style.fontWeight === "600"
          && getComputedStyle(card).borderTopColor === borderColor
          && getComputedStyle(card).borderTopStyle === "solid"
          && value.getBoundingClientRect().left >= label.getBoundingClientRect().right
          && Math.abs(value.getBoundingClientRect().top - label.getBoundingClientRect().top) < 2;
      }),
      actions: audit
        ? !node.querySelector('.rule-actions, [data-decision-field], [data-proposed-text-save]')
          && Boolean(node.querySelector(".hosted-rule-comparison pre.evidence-box"))
        : actionHeading.textContent === `Rule Actions: ${getEffectiveHostedRuleId(candidate)}`
          && getComputedStyle(actionId).color === "rgb(72, 160, 199)" && getComputedStyle(actionId).fontWeight === "600"
          && actionHeading.nextElementSibling === actionInfo && actionInfo.classList.contains("information-panel")
          && !actionInfo.querySelector("button") && !actions.querySelector(".rule-action-header, .subcontext-container")
          && getComputedStyle(controls).padding === "0px" && getComputedStyle(controls).borderWidth === "0px"
          && getComputedStyle(controls).backgroundColor === "rgba(0, 0, 0, 0)"
          && modelGroup.querySelector(".control-subtitle").nextElementSibling.classList.contains("information-panel")
          && modelGroup.querySelector(".information-panel").textContent.trim() === "Resource types apply only to implementation rules.",
      editors: audit || (rationale.classList.contains("evidence-box") && rationale.maxLength === 500
        && editorProperties.every((property) => getComputedStyle(rationale)[property] === getComputedStyle(proposed)[property])),
      overrideBanner: !audit || Boolean(overrideBanner && overrideIcon
        && overrideHeading.nextElementSibling === overrideBanner
        && overrideBanner.nextElementSibling.matches(savedOverride ? ".override-record" : ".override-summary")
        && override.querySelectorAll(":scope > .information-panel").length === 1
        && !override.querySelector(".read-only-boundary, .information-panel button")
        && !overrideBanner.hasAttribute("role")
        && overrideBanner.textContent.trim() === (savedOverride
          ? "The AI assessment is read-only. This provisional maintainer correction does not erase the original result."
          : "The AI assessment is read-only. A maintainer override records a separate correction without erasing the original result.")
        && overrideIcon.querySelector("use")?.getAttribute("href") === "icons/codicons/sprite.svg#codicon-lock"
        && overrideIcon.getAttribute("aria-hidden") === "true"
        && getComputedStyle(overrideIcon).width === "20px" && getComputedStyle(overrideIcon).height === "20px"
        && getComputedStyle(overrideIcon).color === getComputedStyle(info.querySelector("svg")).color
        && ["backgroundColor", "color", "padding", "borderLeft", "borderRadius"].every((property) =>
          getComputedStyle(overrideBanner)[property] === getComputedStyle(info)[property])
        && getComputedStyle(overrideBanner).marginBottom === "12px"
        && Math.abs(overrideBanner.nextElementSibling.getBoundingClientRect().top - overrideBanner.getBoundingClientRect().bottom - 12) < 1)
    };
  });
  for (const [name, passed] of Object.entries(snapshot)) {
    assert(passed, `${context} violates the shared detail UI specification: ${name}`);
  }
}

async function verifyOriginalAssessment(panel, assert, context) {
  await verifyDetailLayout(panel, assert, context);
  const snapshot = await panel.evaluate((node) => {
    const key = node.id === "assessment-results-detail" ? state.assessmentActiveKey : state.activeKey;
    const candidate = state.assessedCandidates.find((item) => item.key === key);
    const baseline = getBaselineAssessment(candidate, getDecision(candidate));
    const factors = [...FACTORS.filter(([, , , kind]) => kind === "value"), ...FACTORS.filter(([, , , kind]) => kind === "penalty")];
    return {
      original: node.querySelectorAll('[data-assessment-origin="original"]').length === 1,
      heading: node.querySelectorAll(".assessment-details-heading").length === 1,
      freshness: node.querySelector("[data-assessment-history]")?.textContent === `Assessment: Edited wording has not yet been reassessed. Priority and factor scores describe the original proposal, whose recommendation was ${formatRecommendation(baseline.recommendation)}; they do not validate the edited wording. Token Cost and Token Headroom reflect the current draft.`,
      factors: JSON.stringify([...node.querySelectorAll(".factor-value")].map((value) => Number(value.textContent)))
        === JSON.stringify(factors.map(([name]) => baseline.factors[name])),
      score: (node.querySelectorAll(".score-strip").length === 1
          && node.querySelector(".score-item.impact span").textContent === "Priority Score:"
          && node.querySelector(".score-item.impact strong").textContent === String(calculateImpact(baseline.factors))),
      rationale: node.querySelector("[data-assessment-explanation]").textContent.trim() === `Assessment rationale: ${baseline.rationale}`,
      coverage: node.id === "assessment-results-detail"
        ? node.querySelector(".coverage-summary strong")?.textContent === "Original assessment coverage:"
          && baseline.relatedHostedCoverage.every((item) => node.querySelector(".related-hosted-coverage")?.textContent.includes(item.rationale))
        : !node.querySelector('[data-evidence-kind="coverage"]') && Array.isArray(baseline.relatedHostedCoverage),
      noCurrentRecommendation: !node.querySelector(".current-hosted-rule-statuses .recommendation-badge"),
      notCurrent: !getAssessment(candidate),
      notReady: !getPlanReadiness(candidate).ready
    };
  });
  assert(Object.values(snapshot).every(Boolean) && await panel.locator(".assessment-details-heading").isVisible(),
    `${context} hid original assessment evidence or presented it as current: ${JSON.stringify(snapshot)}`);
}

async function run({ page, baseUrl, assert }) {
  await openWorkbench(page, baseUrl);
  const excluded = await page.evaluate(() => {
    const candidate = state.assessedCandidates.find((item) => !item.assessment.hostedApplicable && !getApplicabilityOverride(item));
    if (!candidate) throw new Error("The banner journey requires an excluded assessment without an override");
    setWorkspaceTab("assessment-results");
    selectAssessmentResult(candidate.key);
    showAssessmentPane("details");
    return { key: candidate.key, assessment: structuredClone(candidate.assessment) };
  });
  const excludedAudit = page.locator("#assessment-results-detail");
  await verifyDetailLayout(excludedAudit, assert, "Excluded Assessment Results");
  assert(!await excludedAudit.locator("[data-override-open]").isDisabled(), "The validated fixture maintainer cannot contest the assessment");
  await excludedAudit.locator("[data-override-open]").click();
  await excludedAudit.locator(".override-form textarea").fill("Banner regression preserves the original AI assessment and separate maintainer correction.");
  await excludedAudit.locator("[data-override-apply]").click();
  await page.locator("#candidate-sources-panel").waitFor({ state: "visible" });
  await page.evaluate(() => persistencePromise);
  await page.evaluate((key) => {
    setWorkspaceTab("assessment-results");
    selectAssessmentResult(key);
    showAssessmentPane("details");
  }, excluded.key);
  await verifyDetailLayout(excludedAudit, assert, "Saved Maintainer Override");
  assert(!await excludedAudit.locator("[data-saved-override-rationale]").isEditable(), "The saved override rationale lost its read-only boundary");
  await excludedAudit.locator("[data-override-edit]").click();
  await verifyDetailLayout(excludedAudit, assert, "Editing Maintainer Override");
  assert(await excludedAudit.locator("[data-saved-override-rationale]").isEditable(), "The shared banner prevented editing the separate maintainer correction");
  await excludedAudit.locator("[data-override-edit-cancel]").click();
  await excludedAudit.locator("[data-override-remove]").click();
  await page.evaluate(() => persistencePromise);
  await page.evaluate((key) => { selectAssessmentResult(key); showAssessmentPane("details"); }, excluded.key);
  await verifyDetailLayout(excludedAudit, assert, "Removed Maintainer Override");
  assert(await page.evaluate(({ key, assessment }) => {
    const candidate = state.assessedCandidates.find((item) => item.key === key);
    return !getApplicabilityOverride(candidate) && JSON.stringify(candidate.assessment) === JSON.stringify(assessment);
  }, excluded), "Maintainer Override changed the original AI assessment or survived removal");
  await page.evaluate(() => { setWorkspaceTab("candidate-sources"); showCandidatePane("candidates"); });
  const unchangedSetup = await page.evaluate(async () => {
    const candidate = state.assessedCandidates.find((item) => isCurrentMappedNoChangeNoOp(item));
    if (!candidate) throw new Error("The no-op journey requires a candidate identical to its current Hosted rule");
    const session = JSON.stringify(state.session);
    const currentText = getCurrentHostedText(candidate);
    state.session.decisions[candidate.key] = {
      ...defaultDecision(candidate), sourceHash: candidate.hash,
      proposedText: `${currentText} An inactive stored edit.`, action: "no-change"
    };
    if (getDecision(candidate).proposedText !== currentText) throw new Error("The no-op fixture must retain the effective unchanged decision");
    state.session.manualRelationshipChecks[candidate.key] = {
      status: "failed", proposedText: currentText, checkedAt: toUtcTimestamp(),
      relationships: [], errorMessage: "Synthetic obsolete no-op failure."
    };
    await persistSession();
    selectCandidate(candidate.key);
    showCandidatePane("details");
    return { candidate, currentText, session, originalRuleIssues: state.ruleIssueBundle, decisions: JSON.stringify(state.session.decisions) };
  });
  let unchangedRequests = 0;
  await page.route("**/reconcile-rule", async (route) => {
    unchangedRequests++;
    await route.fulfill({ json: createSavedRuleEvaluation(route, { ...unchangedSetup, unchanged: true }) });
  });
  const unchangedPanel = page.locator("#assessment-panel");
  const unchangedEditor = unchangedPanel.locator('[data-decision-field="proposedText"]');
  assert(await unchangedEditor.inputValue() === unchangedSetup.currentText
    && await unchangedPanel.locator("[data-proposed-text-save]").isDisabled()
    && !(await unchangedPanel.locator("[data-manual-relationship-failure]").count())
    && (await unchangedPanel.locator(".relationship-check-status").textContent()).trim() === "Unchanged",
  "Identical current and proposed wording offered a retry or displayed an obsolete evaluation failure");
  const unchangedEvidence = await page.evaluate(() => {
    const candidate = getActiveCandidate();
    return !requiresManualRelationshipCheck(candidate)
      && getAssessment(candidate)?.selectionRationale === candidate.assessment.selectionRationale
      && !getValidationProblems().some((problem) => problem.candidateKey === candidate.key)
      && document.querySelector("#assessment-panel [data-assessment-origin='current']")
      && !document.querySelector("#assessment-panel [data-assessment-history]")
      && !document.querySelector("#assessment-panel .current-hosted-rule-statuses").textContent.includes("Reassessment required");
  });
  assert(unchangedEvidence && unchangedRequests === 0, "Unchanged wording lost its original assessment or issued an evaluation request");
  await unchangedEditor.fill(`${unchangedSetup.currentText} A genuine editor change.`);
  assert(await unchangedPanel.locator("[data-proposed-text-save]").isEnabled(), "A genuine wording change did not enable Save");
  await unchangedEditor.fill(unchangedSetup.currentText);
  assert(await unchangedPanel.locator("[data-proposed-text-save]").isDisabled() && unchangedRequests === 0,
    "Restoring identical wording enabled reevaluation");
  const unchangedResult = await page.evaluate(async () => {
    const candidate = getActiveCandidate();
    const originalIssues = JSON.stringify(getOpenRuleIssues());
    const originalProblems = JSON.stringify(getValidationProblems());
    const result = await reconcileRuleTextRelationships(candidate, getDecision(candidate).proposedText, { notify: false });
    const invalid = [];
    for (const kind of ["assessments", "issues", "scope", "wording", "changedText"]) {
      const bad = structuredClone(result);
      const proposals = getSavedRuleProposals();
      if (kind === "assessments") bad.assessments = [{}];
      if (kind === "issues") bad.ruleIssues.issues = [];
      if (kind === "scope") bad.scopeReview.baselineQuote = "Not present in the baseline";
      if (kind === "wording") bad.scopeReview.wordingStatus = "needs-review";
      if (kind === "changedText") {
        const proposal = proposals.find((item) => item.candidateKey === candidate.key);
        proposal.proposedText += " A genuine changed proposal.";
        bad.coveredProposals[0].proposedText = proposal.proposedText;
      }
      let rejected = false;
      try { await validateSavedRuleEvaluation(bad, result, proposals, getDecision(candidate).proposedText, candidate); }
      catch { rejected = true; }
      if (!rejected) invalid.push(kind);
    }
    return {
      unchanged: result.evaluationMode === "unchanged" && result.assessments.length === 0,
      originalAssessment: getAssessment(candidate)?.selectionRationale === candidate.assessment.selectionRationale,
      originalIssues: JSON.stringify(getOpenRuleIssues()) === originalIssues,
      noValidationProblem: JSON.stringify(getValidationProblems()) === originalProblems,
      decisions: JSON.stringify(state.session.decisions), invalid
    };
  });
  assert(unchangedResult.unchanged && unchangedResult.originalAssessment && unchangedResult.originalIssues && unchangedResult.noValidationProblem
    && unchangedResult.decisions === unchangedSetup.decisions && unchangedResult.invalid.length === 0 && unchangedRequests === 1,
  `The no-op receipt changed baseline evidence, inactive draft wording, or accepted invalid results: ${JSON.stringify(unchangedResult.invalid)}`);
  await openWorkbench(page, baseUrl);
  await page.evaluate((key) => { selectCandidate(key); showCandidatePane("details"); }, unchangedSetup.candidate.key);
  assert(await unchangedPanel.locator("[data-proposed-text-save]").isDisabled()
    && !(await unchangedPanel.locator("[data-manual-relationship-failure]").count()),
  "Reload restored an evaluation requirement for unchanged wording");
  await page.unroute("**/reconcile-rule");
  await page.evaluate(async (session) => { state.session = JSON.parse(session); await persistSession(); renderAssessment(); renderDecisionOutputs(); }, unchangedSetup.session);
  const setup = await page.evaluate(() => {
    const candidate = state.assessedCandidates.find((item) => getCatalogStatus(item).key === "mapped"
      && item.assessment.relatedHostedCoverage.length > 0 && hasHostedTextChange(item, getDecision(item).proposedText));
    if (!candidate) throw new Error("The assessment journey requires a mapped update with source and coverage evidence");
    selectCandidate(candidate.key);
    showCandidatePane("details");
    const comparison = state.assessedCandidates.find((item) => item.key !== candidate.key && getCatalogStatus(item).key === "mapped"
      && !hasMaintainerEditedRuleText(item) && getBaselineAssessment(item, getDecision(item)));
    const relatedRule = comparison && state.bundle.catalog.rules.find((rule) => rule.status === "active" && rule.id === getEffectiveHostedRuleId(comparison));
    if (!relatedRule) throw new Error("The assessment journey requires an unchanged assessed comparison candidate");
    return {
      candidate, relatedRule, comparisonCandidates: state.assessedCandidates, relatedCandidateKeys: [comparison.key],
      baselineText: getDecision(candidate).proposedText, session: JSON.stringify(state.session)
    };
  });
  const panel = page.locator("#assessment-panel");
  await verifyDetailLayout(panel, assert, "Candidate Details");
  const sources = panel.locator('[data-evidence-title="Source Rules"]');
  assert(await sources.getAttribute("aria-expanded") === "false" && !await panel.locator('[data-evidence-kind="coverage"]').count(),
    "Source Rules must start collapsed and Candidate Details must not display inferred coverage");
  await panel.locator(".evidence-disclosure-label").first().click();
  assert(await sources.getAttribute("aria-expanded") === "false", "The static Source Rules title toggles its panel");
  await sources.focus();
  await page.keyboard.press("Enter");
  assert(await sources.getAttribute("aria-expanded") === "true", "Enter did not expand Source Rules");
  await page.keyboard.press("Space");
  assert(await sources.getAttribute("aria-expanded") === "false", "Space did not collapse Source Rules");
  await sources.click();
  const presentation = await page.evaluate(() => {
    const panel = document.querySelector("#assessment-panel");
    const candidate = getActiveCandidate();
    const sourcePanel = panel.querySelector("[data-evidence-title='Source Rules']").closest("section");
    const nodes = [
      sourcePanel, panel.querySelector(".assessment-details-heading"), panel.querySelector(".score-strip"), panel.querySelector("[data-rule-assistance]"),
      panel.querySelector(".current-hosted-rule"), panel.querySelector(".proposed-rule-heading"),
      panel.querySelector("[data-assessment-explanation]"), panel.querySelector("[data-proposed-candidate-key]"),
      panel.querySelector(".rule-actions > .section-label")
    ];
    return {
      order: nodes.every((node, index) => node && (!index || (nodes[index - 1].compareDocumentPosition(node) & Node.DOCUMENT_POSITION_FOLLOWING))),
      staticTitles: [...panel.querySelectorAll(".evidence-disclosure-label")].every((node) => node.tagName === "SPAN" && !node.hasAttribute("tabindex") && !node.hasAttribute("role")),
      counts: sourcePanel.querySelector(".count-badge").textContent === String(candidate.members.length),
      geometry: [...panel.querySelectorAll(".evidence-disclosure")].every((section) => {
        const badge = section.querySelector(".count-badge");
        const label = section.querySelector(".evidence-disclosure-label");
        const button = section.querySelector("button");
        const style = getComputedStyle(badge);
        return badge.getBoundingClientRect().height === 18 && style.fontSize === "12px" && style.fontWeight === "600"
          && style.color === "rgb(255, 255, 255)" && style.backgroundColor === "rgb(0, 122, 204)"
          && getComputedStyle(label).alignItems === "baseline" && getComputedStyle(label).gap === "8px"
          && button.getBoundingClientRect().height === 24 && button.getBoundingClientRect().width === 24;
      }),
      geometryDetails: [...panel.querySelectorAll(".evidence-disclosure")].map((section) => {
        const badge = section.querySelector(".count-badge");
        const label = section.querySelector(".evidence-disclosure-label");
        const button = section.querySelector("button");
        const style = getComputedStyle(badge);
        return {
          height: badge.getBoundingClientRect().height, fontSize: style.fontSize, fontWeight: style.fontWeight,
          color: style.color, background: style.backgroundColor, align: getComputedStyle(label).alignItems,
          gap: getComputedStyle(label).gap, buttonHeight: button.getBoundingClientRect().height, buttonWidth: button.getBoundingClientRect().width
        };
      }),
      sources: [...sourcePanel.querySelectorAll(".contributing-rule-identity strong")].every((node) => getComputedStyle(node).color === "rgb(72, 160, 199)" && getComputedStyle(node).fontWeight === "600"),
      provenance: [...sourcePanel.querySelectorAll(".contributing-rule-badges")].every((node, index) =>
        node.textContent.includes(candidate.members[index].sourceLabel)
        && (candidate.members[index].source.id !== candidate.members[index].catalogMapping.hostedRuleId
          || !node.querySelector(".catalog-status.mapped"))),
      sourcePurpose: sourcePanel.textContent.includes("These references are evidence, not additional Hosted rules selected for the Promotion Plan."),
      oneExplanation: panel.querySelectorAll("[data-assessment-explanation]").length === 1
        && !panel.querySelector("[data-assessment-explanation] button, .ai-evaluation-summary, .adjudication-text-box"),
      comparison: panel.querySelector(".current-hosted-rule-statuses").firstElementChild.textContent.trim() === "Active"
        && panel.querySelector(".current-hosted-rule-statuses").children.length === 1
        && panel.querySelector(".proposed-rule-heading .recommendation-badge").textContent.trim().startsWith("Recommend ")
        && getComputedStyle(panel.querySelector(".current-hosted-rule")).paddingBottom === "12px",
      session: JSON.stringify(state.session)
    };
  });
  for (const [name, passed] of Object.entries(presentation).filter(([name]) => !["session", "geometryDetails"].includes(name))) {
    assert(passed, `The accepted Details presentation failed ${name}${name === "geometry" ? `: ${JSON.stringify(presentation.geometryDetails)}` : ""}`);
  }
  assert(presentation.session === setup.session, "Evidence disclosure changed the saved draft");
  await panel.locator(".contributing-rule summary").first().click();
  const sourceWasOpen = await panel.locator(".contributing-rule").first().evaluate((node) => node.open);
  await page.evaluate(() => renderAssessment());
  assert(await sources.getAttribute("aria-expanded") === "true"
    && await panel.locator(".contributing-rule").first().evaluate((node) => node.open) === sourceWasOpen,
  "Ordinary rerender discarded independent evidence or source disclosure state");

  await page.evaluate(() => {
    const candidate = getActiveCandidate();
    updateDecision(candidate, { action: "update", ...createPlanMembership("manual"), rationale: "Keep the saved wording with its current assessment." });
    renderAssessment();
  });
  const editedText = `${setup.baselineText} Additional source-bound maintainer wording.`;
  const editor = panel.locator('[data-decision-field="proposedText"]');
  await editor.fill(editedText);
  await verifyOriginalAssessment(panel, assert, "Unsaved wording");
  let receiveRoute;
  const routeReady = new Promise((resolve) => { receiveRoute = resolve; });
  let fail = false;
  await page.route("**/reconcile-rule", async (route) => {
    if (fail) {
      await route.fulfill({ status: 503, json: { error: "Synthetic reassessment failure" } });
      return;
    }
    const result = createSavedRuleEvaluation(route, {
      ...setup,
      assessmentOverrides: {
        recommendation: "defer",
        selectionFactors: { severity: 4, frequency: 3, breadth: 2, hostedDetectability: 4, evidenceStrength: 5, falsePositiveRisk: 1, redundancy: 2 },
        selectionRationale: "The saved wording preserves its source obligations; this refreshed recommendation accounts for the current overlap.",
        existingCoverage: { score: 2, rationale: "The current catalog only partially covers the revised obligation." },
        relatedHostedCoverage: [{ hostedRuleId: setup.relatedRule.id, relationship: "partial-overlap", rationale: "This freshly assessed rule covers only part of the saved wording." }]
      }
    });
    await new Promise((resolve) => { receiveRoute(async () => { await route.fulfill({ json: result }); resolve(); }); });
  });
  await panel.locator("[data-proposed-text-save]").click();
  await panel.locator("[data-manual-relationship-progress]").waitFor({ state: "visible" });
  await verifyOriginalAssessment(panel, assert, "Inflight reassessment");
  await (await routeReady)();
  await panel.locator("[data-manual-relationship-progress]").waitFor({ state: "hidden" });
  const refreshed = await page.evaluate(async () => {
    const candidate = getActiveCandidate();
    const decision = getDecision(candidate);
    const assessment = getAssessment(candidate, decision);
    const stored = await readSession(state.session.id);
    const mutation = buildApprovedMutation(candidate);
    return {
      current: isSavedEvaluationCurrent(state.session.savedRuleEvaluations[0]),
      assessment, score: calculateImpact(assessment.factors),
      displayedScore: document.querySelector(".score-item.impact strong").textContent,
      explanation: document.querySelector("[data-assessment-explanation]").textContent.trim(),
      recommendation: document.querySelector(".proposed-rule-heading [data-assessment-recommendation]").textContent,
      recommendationColor: getComputedStyle(document.querySelector(".proposed-rule-heading .recommendation-badge")).color,
      coverage: assessment.relatedHostedCoverage.map((item) => item.rationale).join("\n"),
      approval: mutation.rule.selectionRationale === assessment.rationale
        && JSON.stringify(mutation.rule.selectionFactors) === JSON.stringify({ scoringStatus: "scored", ...assessment.factors }),
      persistence: stored.savedRuleEvaluations[0].assessments[0].selectionRationale === assessment.rationale,
      sourceUnchanged: candidate.assessment.selectionRationale !== assessment.rationale,
      currentPresentation: document.querySelector('#assessment-panel [data-assessment-origin="current"]') !== null
        && !document.querySelector("#assessment-panel [data-assessment-history]"),
      decisionUnchanged: decision.action === "update" && decision.inPlan && decision.proposedText === document.querySelector("[data-proposed-candidate-key]").value
    };
  });
  assert(refreshed.current && refreshed.assessment.recommendation === "defer"
    && refreshed.assessment.factors.redundancy === 2 && refreshed.assessment.existingCoverage.score === 2
    && refreshed.assessment.relatedHostedCoverage.length === 1, "The complete refreshed result was not projected as one assessment");
  assert(refreshed.displayedScore === String(refreshed.score) && refreshed.explanation === `Assessment rationale: ${refreshed.assessment.rationale}`
    && refreshed.recommendation.includes("Recommend Defer") && refreshed.recommendationColor === "rgb(255, 190, 11)"
    && refreshed.coverage.includes("freshly assessed"),
  "Details displays mismatched scores, explanation, recommendation, or coverage");
  assert(refreshed.approval && refreshed.persistence && refreshed.sourceUnchanged && refreshed.decisionUnchanged && refreshed.currentPresentation,
    "Fresh assessment persistence, approval projection, source provenance, or maintainer decision boundaries changed");
  assert(await page.evaluate((key) => {
    const comparison = state.assessedCandidates.find((item) => item.key === key);
    const evaluation = state.session.savedRuleEvaluations[0];
    return evaluation.coveredProposals.length === 2 && evaluation.assessments.length === 1
      && JSON.stringify(getAssessment(comparison)) === JSON.stringify(getBaselineAssessment(comparison, getDecision(comparison)))
      && !evaluation.assessments.some((assessment) => assessment.candidateKey === key);
  }, setup.relatedCandidateKeys[0]), "An unchanged comparison lost its original assessment or was relabelled as freshly assessed");
  await verifyDetailLayout(panel, assert, "Reassessed Candidate Details");
  const invalidResults = await page.evaluate(async () => {
    const original = state.session.savedRuleEvaluations[0];
    const candidate = getActiveCandidate();
    const failures = [];
    const mutations = {
      legacy: (result) => { result.schemaVersion = 2; },
      missing: (result) => { result.assessments = []; },
      duplicate: (result) => { result.assessments.push(result.assessments[0]); },
      staleText: (result) => { result.assessments[0].ruleTextSha256 = "e".repeat(64); },
      foreignCandidate: (result) => { result.assessments[0].candidateKey = "fixture:foreign:A1"; },
      unchangedComparison: (result) => { result.assessments[0].candidateKey = result.coveredProposals.find((proposal) => proposal.candidateKey !== candidate.key).candidateKey; },
      invalidScore: (result) => { result.assessments[0].selectionFactors.severity = 6; },
      coverageMismatch: (result) => { result.assessments[0].existingCoverage.score = 5; },
      foreignCoverage: (result) => { result.assessments[0].relatedHostedCoverage[0].hostedRuleId = "UNKNOWN-RULE-001"; },
      invalidRecommendation: (result) => { result.assessments[0].recommendation = "add"; }
    };
    for (const [name, mutate] of Object.entries(mutations)) {
      const result = structuredClone(original);
      mutate(result);
      let rejected = false;
      try { await validateSavedRuleEvaluation(result, original, original.coveredProposals, getDecision(candidate).proposedText, candidate); }
      catch { rejected = true; }
      if (!rejected) failures.push(name);
    }
    return failures;
  });
  assert(invalidResults.length === 0, `Invalid saved assessments were accepted: ${invalidResults.join(", ")}`);
  const currentEvaluation = await page.evaluate(() => structuredClone(state.session.savedRuleEvaluations[0]));
  for (const kind of ["legacy", "stale-proposal"]) {
    await page.evaluate(({ evaluation, kind }) => {
      const candidate = getActiveCandidate();
      state.session.savedRuleEvaluations[0] = structuredClone(evaluation);
      const result = state.session.savedRuleEvaluations[0];
      if (kind === "legacy") result.schemaVersion = 2;
      else result.coveredProposals.find((proposal) => proposal.candidateKey === candidate.key).proposedText += " Stale fixture context.";
      renderAssessment();
    }, { evaluation: currentEvaluation, kind });
    await verifyOriginalAssessment(panel, assert, `${kind} Details`);
    await page.evaluate((key) => { setWorkspaceTab("assessment-results"); selectAssessmentResult(key); showAssessmentPane("details"); }, setup.candidate.key);
    await verifyOriginalAssessment(page.locator("#assessment-results-detail"), assert, `${kind} Assessment Results`);
    await page.evaluate(() => { setWorkspaceTab("candidate-sources"); showCandidatePane("details"); });
  }
  await page.evaluate((evaluation) => {
    state.session.savedRuleEvaluations[0] = evaluation;
    renderAssessment();
  }, currentEvaluation);
  await openWorkbench(page, baseUrl);
  await page.evaluate((key) => { selectCandidate(key); showCandidatePane("details"); }, setup.candidate.key);
  assert(await editor.inputValue() === editedText
    && (await panel.locator("[data-assessment-explanation]").textContent()).trim() === refreshed.explanation,
  "Reload did not restore the complete current assessment with the saved wording");
  await page.evaluate((key) => { setWorkspaceTab("assessment-results"); selectAssessmentResult(key); showAssessmentPane("details"); }, setup.candidate.key);
  const audit = page.locator("#assessment-results-detail");
  await verifyDetailLayout(audit, assert, "Reassessed Assessment Results");
  assert((await audit.locator("[data-assessment-explanation]").textContent()).trim() === refreshed.explanation
    && (await audit.locator('section:has([data-evidence-title="Related Hosted Coverage"])').count()) === 1,
  "Assessment Results did not consume the same refreshed rationale and coverage");
  await page.evaluate(() => { setWorkspaceTab("candidate-sources"); showCandidatePane("details"); });
  fail = true;
  await editor.fill(`${editedText} A further edit awaiting reassessment.`);
  await panel.locator("[data-proposed-text-save]").click();
  await panel.locator("[data-manual-relationship-failure]").waitFor({ state: "visible" });
  await verifyOriginalAssessment(panel, assert, "Failed reassessment");
  const stalePreview = await page.evaluate(() => {
    const candidate = getActiveCandidate();
    const decision = getDecision(candidate);
    renderPreview();
    let rejectsApproval = false;
    try { buildApprovedRules(); } catch (error) { rejectsApproval = /current complete assessment/.test(error.message); }
    return {
      unavailable: !getPreviewReadiness().ready && previewFilesByScope.raw.length === 0
        && document.querySelector("#preview-json").textContent.includes("Reassessment Required"),
      assessmentRequirement: getPreviewReadiness().missingAssessmentCount > 0 && getPreviewReadiness().missingRationaleCount === 0
        && [...document.querySelectorAll("#approval-requirements .approval-requirement")].some((row) =>
          row.querySelector("span")?.textContent === "AI assessments" && row.classList.contains("pending")),
      preservesDraft: previewFilesByScope.proposed.some((file) => file.rows.some((row) => row.newText?.includes("A further edit awaiting reassessment."))),
      draftCapacity: getActionTokenDelta(candidate, decision.action, decision)
        === estimateGuardedTokens(decision.proposedText) - estimateGuardedTokens(getCurrentHostedText(candidate)),
      rejectsApproval
    };
  });
  assert(Object.values(stalePreview).every(Boolean),
    `Pending reassessment did not preserve draft previews and capacity while blocking catalog approval: ${JSON.stringify(stalePreview)}`);
  await page.evaluate(async () => {
    state.session.savedRuleEvaluations = [];
    await persistSession();
  });
  await openWorkbench(page, baseUrl);
  await page.evaluate((key) => { selectCandidate(key); showCandidatePane("details"); }, setup.candidate.key);
  await verifyOriginalAssessment(panel, assert, "Restored failed evaluation without a saved assessment");
  assert(await panel.locator("[data-manual-relationship-failure]").isVisible()
    && (await editor.inputValue()).endsWith("A further edit awaiting reassessment."),
  "Restoring original assessment evidence lost the failed validation or saved draft wording");
  await page.unroute("**/reconcile-rule");
}

module.exports = { name: "saved rule assessment", behaviorIds, viewport: { width: 1180, height: 900 }, run };
