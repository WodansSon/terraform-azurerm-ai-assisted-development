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

async function waitForWorkbenchTooltip(page) {
  await page.waitForFunction(() => document.querySelector("#status-surface-tooltip")?.classList.contains("visible"));
}

module.exports = { openWorkbench, getCssTokenColor, waitForWorkbenchTooltip };
