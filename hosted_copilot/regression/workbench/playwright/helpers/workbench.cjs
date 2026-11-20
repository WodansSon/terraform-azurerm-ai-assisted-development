async function openWorkbench(page, baseUrl) {
  page.setDefaultTimeout(10000);
  page.setDefaultNavigationTimeout(10000);
  await page.goto(baseUrl, { waitUntil: "domcontentloaded" });
  await page.waitForFunction(() => (Number(document.querySelector("#catalog-count")?.textContent) > 0
      && !document.querySelector("#workspace")?.classList.contains("icon-paint-pending"))
    || document.querySelector("#assessment-panel .empty-state h2")?.textContent?.trim() === "Workbench Could Not Load");
  const loadState = await page.evaluate(() => ({
    catalogCount: Number(document.querySelector("#catalog-count")?.textContent) || 0,
    error: document.querySelector("#assessment-panel .empty-state p")?.textContent?.trim() || ""
  }));
  if (loadState.catalogCount === 0) throw new Error(`Workbench did not load: ${loadState.error || "no catalog rules rendered"}`);
  await page.evaluate(() => {
    globalThis.__HOSTED_RULE_WORKBENCH__.maintainerIdentity = {
      status: "validated",
      login: "fixture-codeowner",
      isCodeOwner: true,
      reason: null
    };
    autofillApproverName();
    renderBulkActions();
  });
}

async function getCssTokenColor(page, token) {
  return page.evaluate((tokenName) => {
    const probe = document.createElement("span");
    probe.style.color = `var(${tokenName})`;
    document.body.appendChild(probe);
    const color = getComputedStyle(probe).color;
    probe.remove();
    return color;
  }, token);
}

async function getCandidateHierarchy(page, candidateKey) {
  return page.evaluate((key) => {
    const leaf = candidateHierarchicalView.model.nodes.find((node) => node.data?.candidate?.key === key);
    if (!leaf) return null;
    const parents = [];
    for (let node = leaf.parent; node; node = node.parent) {
      if (node.kind === "source" || node.kind === "folder") parents.unshift(node);
    }
    return {
      leafId: leaf.id,
      parentIds: parents.map((node) => node.id),
      parentKinds: parents.map((node) => node.kind),
      parentLabels: parents.map((node) => node.data.label),
      rootId: parents[0]?.id || null,
      folderId: parents.at(-1)?.id || null
    };
  }, candidateKey);
}

async function revealCandidate(page, candidateKey) {
  await page.evaluate((key) => revealCandidateInTree(key), candidateKey);
  await page.waitForFunction((key) => Boolean(document.querySelector(`[data-candidate-key="${CSS.escape(key)}"]`)), candidateKey);
  return getCandidateHierarchy(page, candidateKey);
}

async function waitForWorkbenchTooltip(page, timeout = 10000) {
  await page.waitForFunction(() => document.querySelector("#status-surface-tooltip")?.classList.contains("visible"), null, { timeout });
}

async function hoverForWorkbenchTooltip(page, locator, options = {}) {
  const box = await locator.boundingBox();
  if (!box) throw new Error("Workbench tooltip owner is not visible");

  for (let attempt = 0; attempt < 2; attempt += 1) {
    await page.evaluate(() => hideStatusTooltip());
    await page.mouse.move(Math.max(0, box.x - 8), Math.max(0, box.y - 8));
    await locator.hover(options);
    await locator.evaluate((node) => {
      if (!node.matches(":hover")) throw new Error("Workbench tooltip owner did not receive hover state");
    });
    try {
      await waitForWorkbenchTooltip(page, 2000);
      return;
    } catch (error) {
      if (attempt === 1) throw error;
    }
  }
}

async function getRelationshipReviewFixtureResult(page, request) {
  return page.evaluate(request => {
    const candidate = state.assessedCandidates.find(item => item.key === request.candidateKey);
    const subject = request.proposals.find(proposal => proposal.candidateKey === request.candidateKey);
    if (!candidate || !subject) throw new Error("Synthetic relationship review requires its candidate in the working set");
    const decode = value => new TextDecoder("utf-8", { fatal: true }).decode(Uint8Array.from(atob(value), character => character.charCodeAt(0)));
    const id = getEffectiveHostedRuleId(candidate);
    const comparisonRules = [{ id, text: decode(subject.proposedTextBase64) }];
    const add = (relatedId, text) => {
      if (relatedId !== id && !comparisonRules.some(rule => rule.id === relatedId && rule.text === text)) {
        comparisonRules.push({ id: relatedId, text });
      }
    };
    for (const rule of [...state.bundle.catalog.rules.filter(rule => rule.status === "active"), ...state.bundle.catalog.protectedRules]) add(rule.id, rule.text);
    for (const proposal of request.proposals) {
      const item = state.assessedCandidates.find(candidate => candidate.key === proposal.candidateKey);
      if (!item) throw new Error("Synthetic comparison contains an unknown candidate");
      add(getEffectiveHostedRuleId(item), decode(proposal.proposedTextBase64));
    }
    const runtime = globalThis.__HOSTED_RULE_WORKBENCH__.relationshipReview;
    return {
      schemaVersion: 1, requestId: request.requestId, candidateKey: request.candidateKey,
      authoritySha256: request.authoritySha256, snapshotKey: request.snapshotKey, inputSha256: "d".repeat(64),
      changedRuleIds: [id], removedRuleIds: [], effectiveRuleIds: [...new Set(comparisonRules.map(rule => rule.id))],
      comparisonRules, findings: [], elapsedMilliseconds: 42, model: runtime.model, reasoningEffort: runtime.reasoningEffort
    };
  }, request);
}

async function mockRelationshipReviews(page) {
  const requests = new Map();
  const runtimeRoute = async route => {
    const response = await route.fetch();
    if (!response.ok()) throw new Error(`Synthetic Workbench runtime failed with ${response.status()}`);
    const config = await response.json();
    config.maintainerIdentity = { status: "validated", login: "fixture-codeowner", isCodeOwner: true, reason: null };
    await route.fulfill({ response, json: config });
  };
  const reviewRoute = async route => {
    const request = JSON.parse(Buffer.from(route.request().postDataJSON().payloadBase64, "base64").toString("utf8"));
    const result = await getRelationshipReviewFixtureResult(page, request);
    requests.set(request.requestId, { request, result });
    await route.fulfill({ status: 200, contentType: "application/json", body: JSON.stringify(result) });
  };
  const verificationRoute = async route => {
    const request = JSON.parse(Buffer.from(route.request().postDataJSON().payloadBase64, "base64").toString("utf8"));
    const projection = await page.evaluate(() => ({
      rules: [...getProjectedRuleCatalog().rules.values()],
      changedIds: getPlanCandidates().flatMap(buildApprovedMutations).filter(mutation => mutation.action !== "retire").map(mutation => mutation.rule.id),
      requiredKeys: getPlanCandidates().filter(candidate => getRelationshipReviewState(candidate).status !== "unchanged").map(candidate => candidate.key)
    }));
    const receipts = request.receipts.map(receipt => requests.get(receipt.requestId));
    const valid = Array.isArray(request.receipts) && request.receipts.length > 0
      && new Set(request.receipts.map(receipt => receipt.candidateKey)).size === request.receipts.length
      && projection.requiredKeys.every(key => request.receipts.some(receipt => receipt.candidateKey === key))
      && request.receipts.every((receipt, index) => {
        const reviewed = receipts[index]?.request;
        const prior = reviewed?.proposals.find(proposal => proposal.candidateKey === receipt.candidateKey);
        const current = request.proposals.find(proposal => proposal.candidateKey === receipt.candidateKey);
        return reviewed?.candidateKey === receipt.candidateKey && reviewed.authoritySha256 === request.authoritySha256
          && JSON.stringify(reviewed.sourceFiles) === JSON.stringify(request.sourceFiles)
          && prior?.sourceHash === current?.sourceHash && prior?.proposedTextBase64 === current?.proposedTextBase64;
      })
      && projection.changedIds.every(id => {
        const rule = projection.rules.find(rule => rule.id === id);
        return projection.rules.filter(related => related.id !== id).every(related => {
          const covering = receipts.filter(receipt => {
            const subject = receipt.result.comparisonRules.find(rule => rule.id === receipt.result.changedRuleIds[0]);
            const target = subject.id === rule.id && subject.text === rule.text ? related
              : subject.id === related.id && subject.text === related.text ? rule : null;
            return target && receipt.result.comparisonRules.some(compared => compared.id === target.id && compared.text === target.text);
          });
          return covering.length > 0 && covering.every(receipt => !receipt.result.findings.some(finding =>
            finding.relatedRuleId === (receipt.result.changedRuleIds[0] === id ? related.id : id)
            && finding.relatedText === (receipt.result.changedRuleIds[0] === id ? related.text : rule.text)));
        });
      });
    await route.fulfill({ status: valid ? 200 : 409, contentType: "application/json", body: JSON.stringify({ valid }) });
  };
  await page.route("**/runtime-config", runtimeRoute);
  await page.route("**/check-relationships", reviewRoute);
  await page.route("**/verify-relationship-reviews", verificationRoute);
  return {
    get count() { return requests.size; },
    async dispose() {
      await page.unroute("**/runtime-config", runtimeRoute);
      await page.unroute("**/check-relationships", reviewRoute);
      await page.unroute("**/verify-relationship-reviews", verificationRoute);
    }
  };
}

async function reviewCandidateRelationships(page, candidateKey) {
  await page.evaluate(key => {
    switchView("catalog");
    setWorkspaceTab("candidate-sources");
    selectCandidate(key);
    showCandidatePane("details");
  }, candidateKey);
  if (await page.locator("#toast.visible").count()) await page.locator("#toast-close").click();
  if (!await page.locator("#assessment-panel [data-relationship-review-open]").count()) {
    const context = await page.evaluate(key => {
      const candidate = state.assessedCandidates.find(item => item.key === key);
      const decision = candidate && getDecision(candidate);
      return {
        candidateFound: Boolean(candidate), active: state.activeKey === key, pane: state.candidatePane,
        action: decision?.action, inPlan: decision?.inPlan, retirements: decision?.retireHostedRuleIds,
        reviewStatus: candidate && getRelationshipReviewState(candidate).status
      };
    }, candidateKey);
    throw new Error(`Synthetic relationship control is unavailable: ${JSON.stringify(context)}`);
  }
  await page.locator("#assessment-panel [data-relationship-review-open]").click();
  await page.waitForFunction(key => {
    const candidate = state.assessedCandidates.find(item => item.key === key);
    return getRelationshipReviewState(candidate).status === "current" && !activeRelationshipReviews.has(key);
  }, candidateKey);
  await page.evaluate(() => persistencePromise);
}

module.exports = { getRelationshipReviewFixtureResult, hoverForWorkbenchTooltip, mockRelationshipReviews, openWorkbench, getCandidateHierarchy, getCssTokenColor, revealCandidate, reviewCandidateRelationships, waitForWorkbenchTooltip };
