async function openWorkbench(page, baseUrl) {
  await page.goto(baseUrl, { waitUntil: "networkidle" });
  await page.waitForFunction(() => Number(document.querySelector("#catalog-count")?.textContent) > 0);
  await page.evaluate(() => {
    globalThis.__HOSTED_RULE_WORKBENCH__.maintainerIdentity = {
      status: "validated",
      login: "fixture-codeowner",
      isCodeOwner: true,
      reason: null
    };
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

async function waitForWorkbenchTooltip(page) {
  await page.waitForFunction(() => document.querySelector("#status-surface-tooltip")?.classList.contains("visible"));
}

module.exports = { openWorkbench, getCandidateHierarchy, getCssTokenColor, revealCandidate, waitForWorkbenchTooltip };
