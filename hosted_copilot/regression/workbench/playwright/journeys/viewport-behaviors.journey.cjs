const { runViewportSuite } = require("../../shared/WorkbenchViewportSuite.cjs");

const behaviorIds = [
  "WB-UX-VIEWPORT-001",
  "WB-UX-VIEWPORT-002",
  "WB-UX-VIEWPORT-003",
  "WB-UX-VIEWPORT-004",
  "WB-UX-VIEWPORT-005",
  "WB-UX-VIEWPORT-006",
  "WB-UX-VIEWPORT-007",
  "WB-UX-VIEWPORT-008",
  "WB-UX-VIEWPORT-009",
  "WB-UX-VIEWPORT-010"
];

async function run({ page, baseUrl, playback }) {
  const result = await runViewportSuite(page, baseUrl, {
    setViewport: async (targetPage, viewport) => {
      if (playback.headed) {
        await playback.resizeWindow(targetPage, viewport);
      } else {
        await targetPage.setViewportSize({ width: viewport.width, height: viewport.height });
      }
    },
    goto: (targetPage, url) => targetPage.goto(url, { waitUntil: "networkidle" }),
    announceViewport: (targetPage, width) => playback.show(targetPage, `Viewport behaviors · ${width}px viewport`),
    beforeValidation: (targetPage, label) => playback.show(targetPage, `Validate · ${label}`),
    reportFailure: async (_targetPage, width, label, error) => process.stderr.write(`[FAILED] ${width}px ${label}: ${error.message}\n`)
  });
  return { viewportAssertionCount: result.assertionCount, viewportCount: result.viewportCount };
}

module.exports = { name: "viewport behaviors", behaviorIds, physicalViewport: true, viewport: { width: 768, height: 900 }, run };
