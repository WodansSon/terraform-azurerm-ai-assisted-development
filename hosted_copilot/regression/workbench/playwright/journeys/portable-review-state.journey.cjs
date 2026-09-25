const fs = require("node:fs");
const { openWorkbench } = require("../helpers/workbench.cjs");

const behaviorIds = [
  "WB-UX-DRAFT-001",
  "WB-UX-DRAFT-002",
  "WB-UX-SESSION-001",
  "WB-UX-APPROVAL-001"
];

async function readDownload(download) {
  const downloadPath = await download.path();
  if (!downloadPath) throw new Error("Playwright did not expose the downloaded file path");
  return fs.readFileSync(downloadPath);
}

async function importBytes(page, bytes, name) {
  await page.locator("#import-input").setInputFiles({ name, mimeType: "application/json", buffer: bytes });
  await page.evaluate(() => persistencePromise);
}

async function sessionFingerprint(page) {
  return page.evaluate(async () => {
    await persistencePromise;
    const persisted = await readSession(state.session.id);
    return {
      memory: JSON.stringify(normalizeSessionTimestamps(state.session)),
      persisted: JSON.stringify(persisted)
    };
  });
}

async function openCandidate(page, query) {
  await page.locator('[data-view="catalog"]').click();
  await page.locator('[data-workspace-tab="candidate-sources"]').click();
  await page.locator('[data-candidate-pane="candidates"]').click();
  await page.locator("#search-input").fill(query);
  const row = page.locator("#candidate-list [data-candidate-key]").filter({
    has: page.locator(".candidate-tree-copy strong", { hasText: query })
  }).first();
  await row.waitFor({ state: "visible" });
  await row.locator(".candidate-tree-copy").click();
  await page.waitForFunction((expected) => document.querySelector("#assessment-panel .detail-identity span:last-child")?.textContent.trim() === expected, query);
  return row;
}

async function run({ page, baseUrl, assert, playback }) {
  await openWorkbench(page, baseUrl);
  const sessionSnapshot = await page.evaluate(() => structuredClone(state.session));
  const candidateId = "resource-identity-list-resource";
  const candidateSearchId = "REVIEW-REPO-001";
  const proposedId = candidateSearchId;
  const rationale = "Capture and restore this exact Phase 0 draft decision.";

  try {
    await playback.show(page, "Draft export and import · exact downloaded bytes");
    await openCandidate(page, candidateSearchId);
    const proposedEditor = page.locator('#assessment-panel [data-decision-field="proposedText"]');
    const proposedSave = page.locator("#assessment-panel [data-proposed-text-save]");
    const proposedEditorLayout = await proposedEditor.evaluate((element) => {
      const style = getComputedStyle(element);
      return { width: element.getBoundingClientRect().width, height: element.getBoundingClientRect().height, resize: style.resize, overflowY: style.overflowY };
    });
    assert(proposedEditorLayout.width > 300 && proposedEditorLayout.height === 84 && proposedEditorLayout.resize === "none" && proposedEditorLayout.overflowY === "auto", "Proposed Hosted Rule editor is not fixed, full-width, and internally scrollable");
    assert(await proposedSave.isDisabled(), "Unchanged Proposed Hosted Rule save is enabled");
    const proposedTextSaveSetup = await page.evaluate(() => {
      const candidate = getActiveCandidate();
      const textarea = elements["assessment-panel"].querySelector('[data-decision-field="proposedText"]');
      const save = elements["assessment-panel"].querySelector("[data-proposed-text-save]");
      const content = elements["assessment-panel"].querySelector(".assessment-content");
      const originalText = textarea.value;
      const originalAction = getDecision(candidate).action;
      const originalActiveKey = state.activeKey;
      textarea.value = `${originalText} Maintainer wording.`;
      textarea.dispatchEvent(new Event("input", { bubbles: true }));
      return {
        candidateKey: candidate.key,
        originalText,
        originalAction,
        originalActiveKey,
        enabledWhenDirty: !save.disabled,
        checkRequiredBeforeSave: requiresManualRelationshipCheck(candidate, textarea.value)
      };
    });
    await proposedSave.scrollIntoViewIfNeeded();
    proposedTextSaveSetup.originalScrollTop = await page.locator("#assessment-panel .assessment-content").evaluate((element) => element.scrollTop);
    await proposedSave.click();
    await page.waitForFunction((candidateKey) => ["current", "failed"].includes(state.session.manualRelationshipChecks[candidateKey]?.status), proposedTextSaveSetup.candidateKey, { timeout: 30000 });
    const relationshipOutcome = await page.evaluate((candidateKey) => ({
      status: state.session.manualRelationshipChecks[candidateKey]?.status,
      toast: document.querySelector("#toast-message")?.textContent || ""
    }), proposedTextSaveSetup.candidateKey);
    assert(relationshipOutcome.status === "current", `Proposed Hosted Rule relationship check ended as ${relationshipOutcome.status}: ${relationshipOutcome.toast}`);
    const proposedTextSaveResult = await page.evaluate(async (setup) => {
      const candidate = getActiveCandidate();
      const textarea = elements["assessment-panel"].querySelector('[data-decision-field="proposedText"]');
      const save = elements["assessment-panel"].querySelector("[data-proposed-text-save]");
      const content = elements["assessment-panel"].querySelector(".assessment-content");
      const saved = state.session.decisions[candidate.key];
      const canonicalCandidate = state.candidates.find((item) => item.key === candidate.key);
      const manualCheck = state.session.manualRelationshipChecks[candidate.key];
      const result = {
        enabledWhenDirty: setup.enabledWhenDirty,
        checkRequiredBeforeSave: setup.checkRequiredBeforeSave,
        disabledAfterSave: save.disabled,
        activeKeyPreserved: state.activeKey === setup.originalActiveKey,
        scrollPreserved: content.scrollTop === setup.originalScrollTop,
        proposedText: saved.proposedText,
        action: saved.action,
        originalAction: setup.originalAction,
        relationshipStatus: state.session.manualRelationshipChecks[candidate.key].status,
        checkCurrentAfterSave: !requiresManualRelationshipCheck(candidate, saved.proposedText),
        manualIssueCount: state.ruleIssues.filter((issue) => issue.manualRelationshipCheck && issue.candidateKeys.includes(candidate.key)).length,
        relationshipDiagnostics: {
          canonicalCandidate: Boolean(canonicalCandidate),
          canonicalProposedText: canonicalCandidate ? getDecision(canonicalCandidate).proposedText : null,
          activeProposedText: saved.proposedText,
          relationshipCount: manualCheck.relationships.length,
          relatedRuleId: manualCheck.relationships[0]?.hostedRuleId || null,
          relatedRuleKnown: Boolean(manualCheck.relationships[0] && getRuleIndex().has(manualCheck.relationships[0].hostedRuleId)),
          sourceRuleId: canonicalCandidate?.catalogMapping.hostedRuleId || canonicalCandidate?.assessment.proposedHostedRuleId || null
        }
      };
      return result;
    }, proposedTextSaveSetup);
    assert(proposedTextSaveResult.enabledWhenDirty && proposedTextSaveResult.disabledAfterSave, "Proposed Hosted Rule save dirty state is incorrect");
    assert(proposedTextSaveResult.checkRequiredBeforeSave && proposedTextSaveResult.relationshipStatus === "current" && proposedTextSaveResult.checkCurrentAfterSave, "Proposed Hosted Rule save did not complete an exact-text relationship check");
    assert(proposedTextSaveResult.manualIssueCount === 1, `Save-time overlap produced ${proposedTextSaveResult.manualIssueCount} manual Rule Issues instead of 1: ${JSON.stringify(proposedTextSaveResult.relationshipDiagnostics)}`);
    await page.locator('[data-workspace-tab="rule-issues"]').click();
    await playback.show(page, "Save-time relationship check · overlap appears in Rule Issues");
    const visibleRuleIssue = await page.locator("#rule-issues-list .rule-issue-row").first().isVisible();
    const ruleIssueUi = await page.evaluate(() => ({
      workspaceTab: state.workspaceTab,
      panelHidden: document.querySelector("#rule-issues-panel")?.hidden,
      panelActive: document.querySelector("#rule-issues-panel")?.classList.contains("active"),
      rowCount: document.querySelectorAll("#rule-issues-list .rule-issue-row").length
    }));
    assert(visibleRuleIssue, `Save-time overlap was not visible in Rule Issues: ${JSON.stringify(ruleIssueUi)}`);
    await page.locator('[data-workspace-tab="candidate-sources"]').click();
    await page.evaluate(async (setup) => {
      delete state.session.decisions[setup.candidateKey];
      delete state.session.manualRelationshipChecks[setup.candidateKey];
      state.session.updatedAt = toUtcTimestamp();
      await persistSession();
      const textarea = elements["assessment-panel"].querySelector('[data-decision-field="proposedText"]');
      if (textarea) textarea.value = setup.originalText;
      state.ruleIssues = buildRuleIssues();
      renderRuleIssues();
    }, proposedTextSaveSetup);
    assert(proposedTextSaveResult.activeKeyPreserved && proposedTextSaveResult.scrollPreserved, "Proposed Hosted Rule save changed the active Details context");
    assert(proposedTextSaveResult.proposedText.endsWith("Maintainer wording.") && proposedTextSaveResult.action === proposedTextSaveResult.originalAction, "Proposed Hosted Rule save captured fields other than the edited text");
    const initialActions = await page.locator("#assessment-panel [data-rule-action]").evaluateAll((controls) => controls.map((control) => control.dataset.ruleAction));
    assert(initialActions.includes("add"), `Draft candidate does not expose Add: ${initialActions.join(", ")}`);
    await page.locator('#assessment-panel [data-rule-action="add"]').click();
    assert(!await page.evaluate(() => Boolean(state.session.decisions[state.activeKey])), "Unsaved Rule Action unexpectedly persisted before its rationale was saved");
    await page.locator('#assessment-panel [data-decision-field="rationale"]').fill(rationale);
    await page.locator("#assessment-panel [data-rationale-save]").click();
    await page.evaluate(() => persistencePromise);

    await page.locator("#draft-menu > summary").click();
    const [draftDownload] = await Promise.all([
      page.waitForEvent("download"),
      page.locator("#export-button").click()
    ]);
    const draftBytes = await readDownload(draftDownload);
    const draft = JSON.parse(draftBytes.toString("utf8"));
    const decisionKey = Object.keys(draft.decisions).find((key) => key.endsWith(`:${candidateId}`) || draft.decisions[key].proposedHostedRuleId === proposedId);
    assert(draftBytes.at(-1) === 0x0a, "Draft download does not end with the expected newline byte");
    assert(draft.schemaVersion === 4 && draft.kind === "hosted-rule-workbench-draft", "Draft download has the wrong contract identity");
    assert(Boolean(decisionKey), "Draft download omitted the selected decision");
    assert(draft.decisions[decisionKey].action === "add" && draft.decisions[decisionKey].proposedHostedRuleId === proposedId, "Draft download changed the selected action or proposed ID");
    assert(Array.isArray(draft.decisions[decisionKey].retireHostedRuleIds) && draft.decisions[decisionKey].retireHostedRuleIds.length === 0, "Draft download omitted the explicit retirement selection");
    assert(draft.decisions[decisionKey].rationale === rationale && draft.decisions[decisionKey].selected && draft.decisions[decisionKey].selectionSource === "manual", "Draft download changed rationale or plan membership");

    await page.locator('#assessment-panel [data-rule-action="no-change"]').click();
    assert(await page.locator('#assessment-panel [data-decision-field="rationale"]').isDisabled(), "No Change did not disable Decision Rationale");
    assert(!await page.evaluate(() => Boolean(state.session.decisions[state.activeKey])), "No Change did not remove the saved decision");
    await importBytes(page, draftBytes, "draft.json");
    await openCandidate(page, proposedId);
    assert(await page.locator('#assessment-panel [data-rule-action="add"]').isChecked(), "Draft import did not restore the selected action");
    assert(await page.locator('#assessment-panel .rule-action-header .detail-identity span:last-child').innerText() === proposedId, "Draft import did not preserve the generated Hosted ID");
    assert(await page.locator('#assessment-panel [data-decision-field="rationale"]').inputValue() === rationale, "Draft import did not restore the rationale");
    assert(await page.evaluate(() => getDecision(getActiveCandidate()).inPlan), "Draft import did not restore action-derived plan membership");

    const beforeRejectedImports = await sessionFingerprint(page);
    const mismatchedDraft = { ...draft, inputFingerprint: "0".repeat(64) };
    await importBytes(page, Buffer.from(`${JSON.stringify(mismatchedDraft, null, 2)}\n`), "mismatched-draft.json");
    assert((await page.locator("#toast-message").textContent()).includes("different source snapshot"), "Mismatched Draft import did not report its bundle rejection");
    assert(JSON.stringify(await sessionFingerprint(page)) === JSON.stringify(beforeRejectedImports), "Mismatched Draft import changed browser or IndexedDB state");

    const invalidDraft = structuredClone(draft);
    invalidDraft.decisions[decisionKey].sourceContentSha256 = "0".repeat(64);
    await importBytes(page, Buffer.from(`${JSON.stringify(invalidDraft, null, 2)}\n`), "invalid-draft.json");
    assert((await page.locator("#toast-message").textContent()).includes("draft decision"), "Invalid Draft import did not report its decision rejection");
    assert(JSON.stringify(await sessionFingerprint(page)) === JSON.stringify(beforeRejectedImports), "Invalid Draft import changed browser or IndexedDB state");

    await playback.show(page, "Version 4 Draft persistence · import into session v6 and reload");
    const persistedDraft = await page.evaluate(async (key) => {
      const persisted = await readSession(state.session.id);
      return {
        memoryVersion: state.session.schemaVersion,
        persistedVersion: persisted.schemaVersion,
        proposedHostedRuleId: persisted.decisions[key].proposedHostedRuleId,
        retireHostedRuleIds: persisted.decisions[key].retireHostedRuleIds
      };
    }, decisionKey);
    assert(persistedDraft.memoryVersion === 6 && persistedDraft.persistedVersion === 6, "Version 4 Draft did not persist as session schema version 6");
    assert(persistedDraft.proposedHostedRuleId === proposedId, "Version 4 Draft did not retain the selected proposed ID");
    assert(Array.isArray(persistedDraft.retireHostedRuleIds) && persistedDraft.retireHostedRuleIds.length === 0, "Version 4 Draft did not retain the explicit retirement selection");

    await openWorkbench(page, baseUrl);
    await openCandidate(page, proposedId);
    assert(await page.locator('#assessment-panel [data-rule-action="add"]').isChecked(), "Migrated decision action did not survive reload");
    assert(await page.locator('#assessment-panel .rule-action-header .detail-identity span:last-child').innerText() === proposedId, "Generated Hosted ID did not survive reload");
    assert(await page.locator('#assessment-panel [data-decision-field="rationale"]').inputValue() === rationale, "Migrated rationale did not survive reload");
    assert(await page.evaluate(() => getDecision(getActiveCandidate()).inPlan), "Migrated action-derived plan membership did not survive reload");

    await playback.show(page, "Approval export · exact payload bytes and attribution");
    await page.locator('[data-view="preview"]').click();
    await page.locator("#preview-review-toggle").click();
    await page.locator("#approver-name").fill("Phase Zero Maintainer");
    await page.locator("#preview-review-toggle").click();
    assert(!await page.locator("#approve-export-button").isDisabled(), "UI-complete decision did not reach approval readiness");
    const expectedPayloadBytes = await page.evaluate(() => `${JSON.stringify(buildApprovedRules(), null, 2)}\n`);
    const [approvalDownload] = await Promise.all([
      page.waitForEvent("download"),
      page.locator("#approve-export-button").click()
    ]);
    const approvalBytes = await readDownload(approvalDownload);
    const approvedRules = JSON.parse(approvalBytes.toString("utf8"));
    const approvedMutation = approvedRules.mutations.find((mutation) => mutation.rule.id === proposedId);
    assert(approvalBytes.at(-1) === 0x0a, "Approved-rules download does not end with the expected newline byte");
    assert(approvalBytes.toString("utf8") === expectedPayloadBytes, "Downloaded approved rules differ from the exact Preview object");
    assert(approvedRules.schemaVersion === 4 && approvedRules.kind === "hosted-approved-rules", "Approved rules have the wrong contract identity");
    assert(/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{7}Z$/.test(approvedRules.approvedAt), "Approval timestamp is not canonical UTC");
    assert(approvedRules.approvedBy.type === "github-authenticated" && approvedRules.approvedBy.id === "fixture-codeowner" && approvedRules.approvedBy.displayName === "Phase Zero Maintainer", "Approved rules lost exact maintainer attribution");
    assert(approvedMutation.action === "add" && approvedMutation.rule.id === proposedId && approvedMutation.rule.status === "active", "Approved mutation changed the selected identity or action");
    assert(approvedMutation.rationale === rationale && approvedMutation.placements.length === 1 && approvedMutation.sourceRelationships.length > 0, "Approved mutation is incomplete");

    await playback.show(page, "Compound retirement · one Plan item, one retirement mutation");
    const compoundDecision = await page.evaluate(() => {
      const candidate = state.candidates.find((item) => item.catalogMapping.state === "active");
      const retirementRuleId = candidate.catalogMapping.hostedRuleId;
      candidate.recommendation.retireHostedRuleIds = [retirementRuleId];
      const decision = defaultDecision(candidate);
      const timestamp = toUtcTimestamp();
      state.session.decisions = {
        [candidate.key]: {
          ...decision,
          action: "no-change",
          rationale: "The mapped rule is redundant with the preserved canonical guidance.",
          retireHostedRuleIds: [retirementRuleId],
          ...createPlanMembership("manual"),
          sourceHash: candidate.hash,
          updatedAt: timestamp
        }
      };
      state.session.updatedAt = timestamp;
      state.session.approverName = "Phase Zero Maintainer";
      const readiness = getPreviewReadiness();
      const draft = buildDraftExport();
      const approved = buildApprovedRules();
      return {
        ready: readiness.ready,
        draftRetirements: draft.decisions[candidate.key].retireHostedRuleIds,
        mutations: approved.mutations.map((mutation) => ({ action: mutation.action, id: mutation.rule.id, status: mutation.rule.status }))
      };
    });
    assert(compoundDecision.ready, "Compound retirement decision did not reach approval readiness");
    assert(compoundDecision.draftRetirements.length === 1, "Strict draft did not preserve the compound retirement selection");
    assert(compoundDecision.mutations.length === 1 && compoundDecision.mutations[0].action === "retire" && compoundDecision.mutations[0].status === "retired", "Compound Plan item did not export exactly one retirement mutation");

    await playback.show(page, "Primary retirement · actionable issue and one retirement mutation");
    const primaryRetirement = await page.evaluate(async () => {
      const candidate = state.candidates.find((item) => item.catalogMapping.state === "active");
      const sourceRuleId = candidate.catalogMapping.hostedRuleId;
      const relatedRule = state.bundle.catalog.rules.find((rule) => rule.status === "active" && rule.id !== sourceRuleId);
      delete state.session.decisions[candidate.key];
      candidate.recommendation.action = "no-change";
      candidate.recommendation.targetHostedId = sourceRuleId;
      candidate.recommendation.retireHostedRuleIds = [];
      candidate.recommendation.relatedHostedCoverage = [{
        hostedRuleId: relatedRule.id,
        relationship: "partial-overlap",
        rationale: "The rules are related but require no lifecycle action.",
        suggestedConsolidatedText: ""
      }];
      const nonActionableIssueCount = buildRuleIssues().length;

      candidate.recommendation.action = "retire";
      candidate.recommendation.relatedHostedCoverage[0] = {
        hostedRuleId: relatedRule.id,
        relationship: "assessment-narrows-hosted",
        rationale: `${relatedRule.id} fully preserves ${sourceRuleId}.`,
        suggestedConsolidatedText: relatedRule.text
      };
      const issue = buildRuleIssues().find((item) => item.ruleIds.includes(sourceRuleId) && item.ruleIds.includes(relatedRule.id));
      state.ruleIssues = [issue];
      state.activeRuleIssueKey = issue.key;
      switchView("catalog");
      setWorkspaceTab("rule-issues");
      renderRuleIssues();
      renderMetrics();
      const actionLabel = document.querySelector(".rule-issue-recommendation-label");
      const recommendation = document.querySelector(".rule-issue-recommendation");
      const planAction = document.querySelector("[data-rule-issue-plan]");
      const ruleReference = recommendation.querySelector(".rule-reference");
      const ruleReferenceStyle = getComputedStyle(ruleReference);
      const status = elements["rule-issues-status"];
      const openUi = {
        actionLabel: actionLabel.textContent,
        actionLabelTransform: getComputedStyle(actionLabel).textTransform,
        actionLabelOutside: actionLabel.nextElementSibling === recommendation && !recommendation.contains(actionLabel),
        planActionText: planAction.textContent.trim(),
        planActionPrimary: planAction.classList.contains("primary"),
        planActionIcon: planAction.querySelector("use").getAttribute("href"),
        ruleReferenceText: ruleReference.textContent,
        ruleReferenceColor: ruleReferenceStyle.color,
        ruleReferenceWeight: ruleReferenceStyle.fontWeight,
        statusHidden: status.hidden,
        statusCount: elements["rule-issues-status-count"].textContent,
        statusHasIssues: status.classList.contains("has-issues")
      };
      stageRuleIssueRecommendation(issue);
      await persistencePromise;
      state.session.approverName = "Phase Zero Maintainer";
      const decision = getDecision(candidate);
      const approved = buildApprovedRules();
      const stagedUi = {
        issueCount: state.ruleIssues.length,
        issueRows: document.querySelectorAll("#rule-issues-list .rule-issue-row").length,
        statusHidden: status.hidden,
        statusCount: elements["rule-issues-status-count"].textContent,
        statusHasIssues: status.classList.contains("has-issues"),
        statusColor: getComputedStyle(status).color
      };
      delete state.session.decisions[candidate.key];
      renderDecisionOutputs();
      renderRuleIssues();
      const restoredUi = {
        issueCount: state.ruleIssues.length,
        issueRows: document.querySelectorAll("#rule-issues-list .rule-issue-row").length,
        statusHidden: status.hidden,
        statusCount: elements["rule-issues-status-count"].textContent,
        statusHasIssues: status.classList.contains("has-issues"),
        statusColor: getComputedStyle(status).color
      };
      return {
        nonActionableIssueCount,
        issueRetirements: issue.retireHostedRuleIds,
        action: decision.action,
        ancillaryRetirements: decision.retireHostedRuleIds,
        mutations: approved.mutations.filter((mutation) => mutation.rule.id === sourceRuleId).map((mutation) => ({ action: mutation.action, status: mutation.rule.status })),
        openUi,
        stagedUi,
        restoredUi
      };
    });
    assert(primaryRetirement.nonActionableIssueCount === 0, "Non-actionable broad-to-specific overlap was promoted to Rule Issues");
    assert(primaryRetirement.issueRetirements.length === 1, "Primary retirement target was omitted from the Rule Issue recommendation");
    assert(primaryRetirement.action === "retire" && primaryRetirement.ancillaryRetirements.length === 0, "Primary retirement was staged as an ancillary or non-retirement action");
    assert(primaryRetirement.mutations.length === 1 && primaryRetirement.mutations[0].action === "retire" && primaryRetirement.mutations[0].status === "retired", "Primary retirement did not export exactly one retirement mutation");
    assert(primaryRetirement.openUi.actionLabel === "Recommended Maintainer Action:" && primaryRetirement.openUi.actionLabelTransform === "uppercase" && primaryRetirement.openUi.actionLabelOutside, `Recommended Maintainer Action label hierarchy is incorrect: ${JSON.stringify(primaryRetirement.openUi)}`);
    assert(primaryRetirement.openUi.planActionText === "Add to Promotion Plan" && primaryRetirement.openUi.planActionPrimary && primaryRetirement.openUi.planActionIcon.endsWith("#codicon-new-session"), `Rule Issue action button presentation is incorrect: ${JSON.stringify(primaryRetirement.openUi)}`);
    assert(primaryRetirement.openUi.ruleReferenceText && primaryRetirement.openUi.ruleReferenceColor === "rgb(72, 160, 199)" && primaryRetirement.openUi.ruleReferenceWeight === "600", `Rule reference presentation is incorrect: ${JSON.stringify(primaryRetirement.openUi)}`);
    assert(!primaryRetirement.openUi.statusHidden && primaryRetirement.openUi.statusCount === "1" && primaryRetirement.openUi.statusHasIssues, `Open Rule Issues status is incorrect: ${JSON.stringify(primaryRetirement.openUi)}`);
    assert(primaryRetirement.stagedUi.issueCount === 0 && primaryRetirement.stagedUi.issueRows === 0, `Staged Rule Issue remained open: ${JSON.stringify(primaryRetirement.stagedUi)}`);
    assert(!primaryRetirement.stagedUi.statusHidden && primaryRetirement.stagedUi.statusCount === "0" && !primaryRetirement.stagedUi.statusHasIssues && primaryRetirement.stagedUi.statusColor === "rgb(140, 140, 140)", `Zero Rule Issues status is incorrect: ${JSON.stringify(primaryRetirement.stagedUi)}`);
    assert(primaryRetirement.restoredUi.issueCount === 1 && primaryRetirement.restoredUi.issueRows === 1, `Undone Rule Issue was not restored: ${JSON.stringify(primaryRetirement.restoredUi)}`);
    assert(!primaryRetirement.restoredUi.statusHidden && primaryRetirement.restoredUi.statusCount === "1" && primaryRetirement.restoredUi.statusHasIssues && primaryRetirement.restoredUi.statusColor === "rgb(229, 186, 125)", `Restored Rule Issues status is incorrect: ${JSON.stringify(primaryRetirement.restoredUi)}`);
  } finally {
    await page.evaluate(async (snapshot) => {
      state.session = snapshot;
      state.activeKey = null;
      refreshEffectiveCandidates();
      await persistSession();
      renderAll();
      switchView("catalog");
      setWorkspaceTab("candidate-sources");
      showCandidatePane("candidates");
    }, sessionSnapshot).catch(() => {});
  }
}

module.exports = { name: "portable review state", behaviorIds, viewport: { width: 1180, height: 900 }, run };
