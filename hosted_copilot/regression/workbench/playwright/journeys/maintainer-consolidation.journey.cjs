const { openWorkbench } = require("../helpers/workbench.cjs");
const { readSavedRuleRequest, createSavedRuleEvaluation } = require("../helpers/saved-rule-evaluation.cjs");

const behaviorIds = ["WB-UX-CONSOLIDATION-001"];

async function fingerprint(page) {
  return page.evaluate(async () => {
    try { await persistencePromise; }
    catch (error) { if (error.message !== "Synthetic persistence failure.") throw error; }
    return {
      memory: JSON.stringify(normalizeSessionTimestamps(state.session)),
      persisted: JSON.stringify(await readSession(state.session.id))
    };
  });
}

async function run({ page, baseUrl, assert }) {
  await page.route("**/runtime-config", async (route) => {
    const response = await route.fetch();
    const config = await response.json();
    await route.fulfill({ response, json: {
      ...config, maintainerIdentity: { status: "validated", login: "fixture-codeowner", isCodeOwner: true, reason: null }
    } });
  });
  await openWorkbench(page, baseUrl);
  const initial = await page.evaluate(() => structuredClone(state.session));
  const fixture = await page.evaluate(() => {
    const candidates = state.assessedCandidates.filter((candidate) => candidate.catalogMapping.state === "active");
    if (candidates.length < 2) throw new Error("Consolidation requires two real mapped fixture candidates.");
    const [target, peer] = candidates;
    return {
      candidates: [target, peer].map(({ key, hash, recommendation, catalogMapping }) => ({ key, hash, recommendation, catalogMapping })),
      targetText: `${target.recommendation.ruleText} The merged requirement shoud retain the comparison obligation.`,
      peerText: `${peer.recommendation.ruleText} Retain the complete comparison requirement.`,
      peerRule: state.bundle.catalog.rules.find((rule) => rule.id === peer.catalogMapping.hostedRuleId)
    };
  });
  const [target, peer] = fixture.candidates;
  const corrected = `${target.recommendation.ruleText} The merged requirement should retain the comparison obligation. ${peer.recommendation.ruleText}`;
  let scenario = "recommend";
  const requests = [];
  await page.route("**/reconcile-rule", async (route) => {
    const request = readSavedRuleRequest(route);
    requests.push(request.candidateKey);
    if (scenario === "second-failure" && request.candidateKey === peer.key) {
      await route.fulfill({ status: 500, json: { error: "Synthetic second-operation validation failure." } });
      return;
    }
    if (scenario === "cancel") {
      await page.evaluate((key) => cancelRuleRelationshipCheck(key), request.candidateKey);
      await route.fulfill({ json: {} });
      return;
    }
    const candidate = fixture.candidates.find((item) => item.key === request.candidateKey);
    if (!candidate) throw new Error("The projected transaction evaluated an unknown fixture candidate.");
    const other = fixture.candidates.find((item) => item.key !== candidate.key);
    const relatedRule = candidate.key === target.key ? fixture.peerRule
      : { id: target.catalogMapping.hostedRuleId, text: target.recommendation.ruleText };
    const evaluation = createSavedRuleEvaluation(route, {
      candidate, comparisonCandidates: [other], relatedRule, relatedCandidateKeys: [other.key], grouped: scenario === "recommend"
    });
    if (scenario === "recommend") {
      evaluation.scopeReview.wordingStatus = "needs-review";
      evaluation.scopeReview.wordingRationale = "Correct the spelling and preserve the complete comparison before retiring it.";
      const issue = evaluation.ruleIssues.issues[0];
      issue.rules.find((rule) => rule.id === fixture.peerRule.id).disposition = "retire";
      issue.wording.text = corrected;
      issue.recommendedMaintainerAction.summary = "Keep the intended target, correct the wording, and retire the fully covered comparison.";
      issue.recommendedMaintainerAction.operations[0].proposedText = corrected;
      issue.recommendedMaintainerAction.operations[0].retireHostedRuleIds = [fixture.peerRule.id];
    }
    if (scenario === "warning") {
      evaluation.scopeReview.wordingStatus = "needs-review";
      evaluation.scopeReview.wordingRationale = "The projected wording still needs review.";
    }
    if (scenario === "inapplicable") {
      const assessment = evaluation.assessments.find((item) => item.candidateKey === request.candidateKey);
      assessment.hostedApplicable = false;
      assessment.applicabilityRationale = "This synthetic projected obligation cannot be evaluated in a Hosted review.";
    }
    if (scenario === "stale") {
      await page.evaluate((key) => {
        const candidate = state.assessedCandidates.find((item) => item.key === key);
        saveDecision(candidate, { ...getDecision(candidate), rationale: "A concurrent maintainer change must survive." });
      }, target.key);
    }
    if (scenario === "authority") evaluation.authoritySha256 = "e".repeat(64);
    await route.fulfill({ json: evaluation });
  });

  const prepare = async (multiple = false) => {
    scenario = "recommend";
    requests.length = 0;
    await page.evaluate(async ({ initial, fixture, multiple }) => {
      state.session = structuredClone(initial);
      for (const [index, owner] of fixture.candidates.entries()) {
        const candidate = state.assessedCandidates.find((item) => item.key === owner.key);
        state.session.decisions[candidate.key] = {
          ...defaultDecision(candidate), action: index && !multiple ? "no-change" : "update",
          proposedText: index ? multiple ? fixture.peerText : owner.recommendation.ruleText : fixture.targetText,
          retireHostedRuleIds: [], ...createPlanMembership()
        };
      }
      state.activeKey = fixture.candidates[0].key;
      renderAssessment();
      await persistSession();
    }, { initial, fixture, multiple });
    if (multiple) {
      scenario = "accept";
      const checked = await page.evaluate(async (key) => {
        const candidate = state.assessedCandidates.find((item) => item.key === key);
        return Boolean(await reconcileRuleTextRelationships(candidate, getDecision(candidate).proposedText));
      }, peer.key);
      assert(checked, "The additional edited group member did not obtain its required current validation.");
      scenario = "recommend";
    }
    const result = await page.evaluate(async (key) => {
      const candidate = state.assessedCandidates.find((item) => item.key === key);
      const evaluation = await reconcileRuleTextRelationships(candidate, getDecision(candidate).proposedText);
      return { success: Boolean(evaluation), toast: document.querySelector("#toast-message")?.textContent || "" };
    }, target.key);
    assert(result.success, `The source-shaped consolidation recommendation was rejected: ${result.toast}`);
    assert(await page.evaluate(({ key, text }) => {
      const candidate = state.assessedCandidates.find((item) => item.key === key);
      const decision = getDecision(candidate);
      return decision.proposedText === text && !decision.inPlan && decision.retireHostedRuleIds.length === 0;
    }, { key: target.key, text: fixture.targetText }), "Evaluation silently accepted wording, retirement, or Plan membership");
  };
  const apply = async () => {
    await page.evaluate(async (key) => {
      const issue = getOpenRuleIssues().find((item) => item.candidateKeys.includes(key));
      if (!issue) throw new Error("The consolidation recommendation is missing.");
      await stageRuleIssueRecommendation(issue);
    }, target.key);
    await page.evaluate(async () => {
      try { await persistencePromise; }
      catch (error) { if (error.message !== "Synthetic persistence failure.") throw error; }
    });
  };

  try {
    await prepare();
    const advisory = await fingerprint(page);
    assert(advisory.memory === advisory.persisted, "Advisory evaluation did not preserve a consistent saved draft");
    scenario = "accept";
    await page.locator('[data-workspace-tab="rule-issues"]').click();
    await page.evaluate((key) => {
      const issue = getOpenRuleIssues().find((item) => item.candidateKeys.includes(key));
      state.ruleIssueFilter = getRuleIssueFilterKey(issue);
      state.activeRuleIssueKey = issue.id;
      renderRuleIssues();
    }, target.key);
    await page.locator("[data-rule-issue-plan]:enabled:visible").click();
    await page.waitForFunction(() => activeRuleIssueRecommendations.size === 0);
    const accepted = await page.evaluate(({ key, peerId, corrected }) => {
      const candidate = state.assessedCandidates.find((item) => item.key === key);
      const decision = getDecision(candidate);
      return {
        combined: decision.inPlan && decision.action === "update" && decision.proposedText === corrected
          && JSON.stringify(decision.retireHostedRuleIds) === JSON.stringify([peerId]),
        current: getManualRelationshipValidation(candidate).status,
        draft: buildDraftExport(), stored: state.session.decisions[key].proposedText
      };
    }, { key: target.key, peerId: fixture.peerRule.id, corrected });
    assert(accepted.combined && accepted.current === "current", "Explicit acceptance failed to stage corrected wording and retirement together");
    const committed = await fingerprint(page);
    assert(committed.memory === committed.persisted, "Accepted consolidation was not persisted atomically");
    assert(requests.length === 2, "A single-target consolidation did not use exactly one projected acceptance evaluation");
    await page.reload();
    await page.waitForFunction(() => Number(document.querySelector("#catalog-count")?.textContent) > 0);
    assert(await page.evaluate(({ key, corrected, peerId }) => {
      const candidate = state.assessedCandidates.find((item) => item.key === key);
      return getDecision(candidate).proposedText === corrected && getDecision(candidate).retireHostedRuleIds.includes(peerId);
    }, { key: target.key, corrected, peerId: fixture.peerRule.id }), "Reload discarded accepted retirement intent");
    const imported = await page.evaluate((draft) => {
      state.session = deserializeDraft(draft, state.assessedCandidates);
      const candidate = state.assessedCandidates.find((item) => item.key === Object.keys(draft.decisions).find((key) => draft.decisions[key].selected));
      return getDecision(candidate).retireHostedRuleIds.length === 1 && requiresManualRelationshipCheck(candidate);
    }, accepted.draft);
    assert(imported, "Portable import discarded accepted retirement intent or treated it as prevalidated");

    for (const failure of ["warning", "inapplicable", "authority", "cancel", "persistence"]) {
      await prepare();
      const before = await fingerprint(page);
      scenario = failure;
      if (failure === "persistence") {
        await page.evaluate(() => {
          globalThis.consolidationOriginalOpenDatabase = openDatabase;
          openDatabase = async () => { throw new Error("Synthetic persistence failure."); };
        });
      }
      try { await apply(); }
      finally {
        if (failure === "persistence") {
          await page.evaluate(() => { openDatabase = globalThis.consolidationOriginalOpenDatabase; delete globalThis.consolidationOriginalOpenDatabase; });
        }
      }
      const after = await fingerprint(page);
      assert(after.memory === before.memory && after.persisted === before.persisted,
        `${failure} changed a decision, receipt, timestamp, or persisted field before acceptance`);
    }

    await prepare();
    const beforeStale = await page.evaluate((key) => structuredClone(state.session.decisions[key]), target.key);
    scenario = "stale";
    await apply();
    assert(await page.evaluate(({ key, before }) => {
      const decision = state.session.decisions[key];
      return decision.proposedText === before.proposedText && decision.inPlan === before.inPlan
        && decision.retireHostedRuleIds.length === 0 && decision.rationale === "A concurrent maintainer change must survive.";
    }, { key: target.key, before: beforeStale }), "Stale acceptance overwrote concurrent maintainer work");

    for (const failSecond of [true, false]) {
      await prepare(true);
      await page.evaluate(({ targetKey, peerKey, peerText }) => {
        const issue = getOpenRuleIssues().find((item) => item.candidateKeys.includes(targetKey));
        issue.rules.find((rule) => rule.candidateKeys.includes(peerKey)).disposition = "replace";
        issue.recommendedMaintainerAction.operations[0].retireHostedRuleIds = [];
        const candidate = state.assessedCandidates.find((item) => item.key === peerKey);
        issue.recommendedMaintainerAction.operations.push({
          candidateKey: peerKey, ruleId: candidate.catalogMapping.hostedRuleId, action: "update",
          proposedText: peerText, retireHostedRuleIds: []
        });
      }, { targetKey: target.key, peerKey: peer.key, peerText: fixture.peerText });
      const before = await fingerprint(page);
      requests.length = 0;
      scenario = failSecond ? "second-failure" : "accept";
      await apply();
      assert(requests.length === 2 && new Set(requests).size === 2, "Grouped acceptance failed to validate every affected candidate");
      const after = await fingerprint(page);
      if (failSecond) {
        assert(after.memory === before.memory && after.persisted === before.persisted, "Second-operation failure partially applied the group");
      } else {
        assert(await page.evaluate((keys) => keys.every((key) => {
          const candidate = state.assessedCandidates.find((item) => item.key === key);
          return getDecision(candidate).inPlan && getManualRelationshipValidation(candidate).status === "current";
        }), [target.key, peer.key]), "Successful grouped acceptance failed to persist every candidate's validation");
        assert(after.memory === after.persisted, "Grouped acceptance diverged from its persisted transaction");
      }
    }
    const invalidRetirements = await page.evaluate(({ key, draft }) => {
      const ownId = state.assessedCandidates.find((item) => item.key === key).catalogMapping.hostedRuleId;
      const protectedId = state.bundle.catalog.protectedRules[0].id;
      return [ownId, protectedId, "MISSING-RULE-001"].every((id) => {
        const invalid = structuredClone(draft);
        invalid.decisions[key].retireHostedRuleIds = [id];
        try { deserializeDraft(invalid, state.assessedCandidates); return false; }
        catch (error) { return error.message.includes("retirement"); }
      });
    }, { key: target.key, draft: accepted.draft });
    assert(invalidRetirements, "Portable import admitted a self, protected, or unknown retirement");
  } finally {
    await page.unroute("**/reconcile-rule");
    await page.unroute("**/runtime-config");
    await page.evaluate(async (snapshot) => {
      state.session = snapshot;
      await persistSession();
      refreshSavedRuleIssues();
      renderAssessment();
      renderDecisionOutputs();
    }, initial);
  }
}

module.exports = { behaviorIds, run };
