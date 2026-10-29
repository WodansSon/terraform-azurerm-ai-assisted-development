const { openWorkbench } = require("../helpers/workbench.cjs");

const behaviorIds = ["WB-UX-VALIDATION-003", "WB-UX-VALIDATION-004"];

async function run({ page, baseUrl, assert }) {
  await openWorkbench(page, baseUrl);
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
          const entries = [...document.querySelectorAll(".ide-statusbar .status-item:not([hidden])")];
          const rects = entries.map((entry) => entry.getBoundingClientRect());
          return rects.every((rect, index) => rect.left >= 0 && rect.right <= innerWidth + 0.5
            && (!index || rect.left >= rects[index - 1].right - 0.5))
            && entries.every((entry) => getComputedStyle(entry).fontSize === "12px")
            && document.querySelector(".ide-statusbar").getBoundingClientRect().height === 22
            && document.documentElement.scrollWidth <= innerWidth;
        }, { errors, warnings });
        assert(geometry, `${width}px validation status clips or overlaps with ${errors} errors and ${warnings} warnings`);
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
