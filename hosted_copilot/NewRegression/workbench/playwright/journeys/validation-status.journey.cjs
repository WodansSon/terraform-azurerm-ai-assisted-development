const { openWorkbench } = require("../helpers/workbench.cjs");

const behaviorIds = ["WB-UX-VALIDATION-003", "WB-UX-VALIDATION-004"];

async function run({ page, baseUrl, assert }) {
  await openWorkbench(page, baseUrl);
  assert(await page.evaluate(() => !matchMedia("(prefers-reduced-motion: reduce)").matches),
    "Status-bar validation requires normal motion");
  const nativeIcons = await page.evaluate(() => [
    ["status-target", "codicon-git-branch"],
    ["validation-warning-count", "codicon-warning"],
    ["status-excluded", "codicon-circle-slash"],
    ["status-mapped", "fluent-link-multiple-16-regular"],
    ["status-unmapped", "fluent-link-dismiss-16-regular"],
    ["preview-status", "codicon-shield"]
  ].every(([valueId, symbol]) => {
    const use = document.getElementById(valueId).parentElement.querySelector("svg use");
    const reference = new URL(use.getAttribute("href"), document.baseURI);
    return reference.origin === location.origin && reference.pathname === "/sprite/sprite.svg"
      && reference.hash === `#${symbol}` && use.getBBox().width > 0
      && !use.closest("svg").classList.contains("icon-not-found");
  }));
  assert(nativeIcons, "Status-bar entries must render the approved native Codicons and Regular Fluent sprite symbols");
  const viewport = page.viewportSize();
  try {
    for (const width of [1960, 1440, 1180, 1024, 902, 900, 820, 768]) {
      await page.setViewportSize({ width, height: 900 });
      for (const [errors, warnings] of [[0, 0], [1, 0], [12, 3], [999, 999]]) {
        const geometry = await page.evaluate(({ errors, warnings }) => {
          workbenchStatusBar.update("validationIssues", {
            segments: {
              errors: { text: String(errors), kind: errors ? "error" : "standard" },
              warnings: { text: String(warnings), kind: warnings ? "warning" : "standard" }
            }
          });
          const approval = workbenchStatusBar.getEntry("promotionApproval");
          const approvalWidth = approval.getBoundingClientRect().width;
          return ["Draft", "Ready", "Blocked"].every((text) => {
            workbenchStatusBar.update("promotionApproval", { text });
            const bar = document.querySelector(".ide-statusbar").getBoundingClientRect();
            const entries = [...document.querySelectorAll(".ide-statusbar .status-item:not([hidden])")];
            const rects = entries.map((entry) => entry.getBoundingClientRect());
            const icons = [...document.querySelectorAll(".ide-statusbar .status-item:not([hidden]) svg")];
            const approvalRect = approval.getBoundingClientRect();
            const approvalStyle = getComputedStyle(approval);
            const textRange = document.createRange();
            textRange.selectNodeContents(document.getElementById("preview-status"));
            const textRect = textRange.getBoundingClientRect();
            return rects.every((rect, index) => rect.left >= 0 && rect.right <= innerWidth + 0.5
              && rect.top >= bar.top && rect.bottom <= bar.bottom
              && (!index || rect.left >= rects[index - 1].right - 0.5))
              && entries.every((entry) => getComputedStyle(entry).fontSize === "12px")
              && icons.every((icon) => {
                const rect = icon.getBoundingClientRect();
                return rect.width === 16 && rect.height === 16 && rect.top >= bar.top && rect.bottom <= bar.bottom;
              })
              && approvalRect.width === approvalWidth
              && textRect.right <= approvalRect.right - parseFloat(approvalStyle.paddingRight) + 0.5
              && bar.height === 28 && bar.bottom === innerHeight
              && document.querySelector(".workspace").getBoundingClientRect().bottom <= bar.top
              && document.documentElement.scrollWidth <= innerWidth;
          });
        }, { errors, warnings });
        assert(geometry, `${width}px status bar clips, overlaps, or changes approval width with ${errors} errors and ${warnings} warnings`);
      }
    }
    const failed = await page.evaluate(async () => {
      const database = await openDatabase();
      const transactionFactory = database.transaction;
      database.transaction = function (...args) {
        const transaction = transactionFactory.apply(this, args);
        if (args[1] === "readwrite") queueMicrotask(() => transaction.abort());
        return transaction;
      };
      let rejected = false;
      try { await persistSession(); } catch { rejected = true; }
      finally { database.transaction = transactionFactory; }
      renderAll();
      return rejected && document.querySelector("#save-indicator").textContent === "Save failed"
        && workbenchStatusBar.getEntry("save").classList.contains("error-kind");
    });
    assert(failed, "Failed persistence was incorrectly reported as saved");
    const recovered = await page.evaluate(async () => {
      await persistSession();
      return document.querySelector("#save-indicator").textContent.startsWith("Saved ")
        && workbenchStatusBar.getEntry("save").classList.contains("success-kind");
    });
    assert(recovered, "A failed persistence transaction prevented recovery on the next save");
  } finally {
    await page.setViewportSize(viewport);
    await page.evaluate(() => { renderValidationIssues(); renderMetrics(); });
  }
  return { behaviorIds };
}

module.exports = { behaviorIds, run };
