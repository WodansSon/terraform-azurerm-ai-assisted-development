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
  const proposedId = "REVIEW-DRAFT-001";
  const rationale = "Capture and restore this exact Phase 0 draft decision.";

  try {
    await playback.show(page, "Draft export and import · exact downloaded bytes");
    await openCandidate(page, candidateSearchId);
    const initialActions = await page.locator("#assessment-panel [data-rule-action]").evaluateAll((controls) => controls.map((control) => control.dataset.ruleAction));
    assert(initialActions.includes("add"), `Draft candidate does not expose Add: ${initialActions.join(", ")}`);
    await page.locator('#assessment-panel [data-rule-action="add"]').click();
    await page.locator('#assessment-panel [data-decision-field="proposedHostedRuleId"]').fill(proposedId);
    await page.waitForTimeout(350);
    await page.locator('#assessment-panel [data-plan-toggle]').check();
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
    assert(draft.decisions[decisionKey].rationale === rationale && draft.decisions[decisionKey].selected && draft.decisions[decisionKey].selectionSource === "manual", "Draft download changed rationale or plan membership");

    await page.locator('#assessment-panel [data-rule-action="no-change"]').click();
    await page.locator('#assessment-panel [data-plan-toggle]').uncheck();
    await page.locator('#assessment-panel [data-decision-field="rationale"]').fill("Mutated after export.");
    await importBytes(page, draftBytes, "draft.json");
    await openCandidate(page, proposedId);
    assert(await page.locator('#assessment-panel [data-rule-action="add"]').isChecked(), "Draft import did not restore the selected action");
    assert(await page.locator('#assessment-panel [data-decision-field="proposedHostedRuleId"]').inputValue() === proposedId, "Draft import did not restore the proposed ID");
    assert(await page.locator('#assessment-panel [data-decision-field="rationale"]').inputValue() === rationale, "Draft import did not restore the rationale");
    assert(await page.locator('#assessment-panel [data-plan-toggle]').isChecked(), "Draft import did not restore plan membership");

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

    await playback.show(page, "Version 4 Draft persistence · import, persist, and reload");
    const persistedDraft = await page.evaluate(async (key) => {
      const persisted = await readSession(state.session.id);
      return {
        memoryVersion: state.session.schemaVersion,
        persistedVersion: persisted.schemaVersion,
        proposedHostedRuleId: persisted.decisions[key].proposedHostedRuleId
      };
    }, decisionKey);
    assert(persistedDraft.memoryVersion === 4 && persistedDraft.persistedVersion === 4, "Version 4 Draft did not persist as session schema version 4");
    assert(persistedDraft.proposedHostedRuleId === proposedId, "Version 4 Draft did not retain the selected proposed ID");

    await openWorkbench(page, baseUrl);
    await openCandidate(page, proposedId);
    assert(await page.locator('#assessment-panel [data-rule-action="add"]').isChecked(), "Migrated decision action did not survive reload");
    assert(await page.locator('#assessment-panel [data-decision-field="proposedHostedRuleId"]').inputValue() === proposedId, "Proposed ID did not survive reload");
    assert(await page.locator('#assessment-panel [data-decision-field="rationale"]').inputValue() === rationale, "Migrated rationale did not survive reload");
    assert(await page.locator('#assessment-panel [data-plan-toggle]').isChecked(), "Migrated plan membership did not survive reload");

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
