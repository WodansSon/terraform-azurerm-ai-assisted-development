const { openWorkbench } = require("../helpers/workbench.cjs");

const behaviorIds = [
  "WB-UX-ZOOM-001",
  "WB-UX-ZOOM-002",
  "WB-UX-ZOOM-003"
];

const profiles = [
  { percent: 100 },
  { percent: 125 },
  { percent: 150 },
  { percent: 200 }
];
const viewport = { width: 1920, height: 900 };

async function inspectZoom(page) {
  return page.evaluate(() => {
    const rect = (selector) => {
      const bounds = document.querySelector(selector).getBoundingClientRect();
      return { left: bounds.left, top: bounds.top, right: bounds.right, bottom: bounds.bottom, width: bounds.width, height: bounds.height };
    };
    const shell = rect(".app-shell");
    const titlebar = rect(".topbar");
    const activityRail = rect(".stage-nav");
    const statusbar = rect(".ide-statusbar");
    const workspace = rect(".workspace");
    const tolerance = 0.1;
    return {
      outer: { width: outerWidth, height: outerHeight },
      viewport: { width: innerWidth, height: innerHeight },
      deviceScaleFactor: devicePixelRatio,
      geometry: { shell, titlebar, activityRail, statusbar, workspace },
      shellContained: shell.left >= -tolerance && shell.top >= -tolerance && shell.right <= innerWidth + tolerance && shell.bottom <= innerHeight + tolerance,
      fixedChrome: Math.abs(titlebar.height - 35) <= tolerance && Math.abs(activityRail.width - 48) <= tolerance && Math.abs(statusbar.height - 22) <= tolerance,
      workspaceSeparated: workspace.top >= titlebar.bottom - tolerance && workspace.left >= activityRail.right - tolerance && workspace.bottom <= statusbar.top + tolerance,
      pageOverflow: document.documentElement.scrollWidth > innerWidth || document.documentElement.scrollHeight > innerHeight,
      unsupportedVisible: getComputedStyle(document.querySelector(".unsupported-device")).display !== "none"
    };
  });
}

async function run({ baseUrl, assert, check, playback }) {
  return playback.runBrowserZoom(baseUrl, viewport, async (page, setZoom, getWindowBounds) => {
    await openWorkbench(page, baseUrl);
    if (playback.headed) {
      await playback.resizeWindow(page, { ...viewport, breakpointSide: "nearest" });
    }
    await setZoom(1);
    const baseline = await inspectZoom(page);
    const baselineBounds = await getWindowBounds();
    const failures = [];

    try {
      for (const profile of profiles) {
        const expectedZoom = profile.percent / 100;
        const appliedZoom = await setZoom(expectedZoom);
        await page.evaluate(() => new Promise((resolve) => requestAnimationFrame(() => requestAnimationFrame(resolve))));
        await playback.show(page, `Browser zoom · ${profile.percent}% · fixed ${baselineBounds.width}×${baselineBounds.height} window`);
        const result = await inspectZoom(page);
        const bounds = await getWindowBounds();
        const measuredZoom = result.deviceScaleFactor / baseline.deviceScaleFactor;
        if (playback.headed) process.stderr.write(`[ZOOM] ${profile.percent}% · fixed ${bounds.width}×${bounds.height} window · ${result.viewport.width}×${result.viewport.height} CSS viewport\n`);
        const checks = [
          [Math.abs(appliedZoom - expectedZoom) < 0.01, `zoom API applied ${appliedZoom.toFixed(2)}x`],
          [bounds.width === baselineBounds.width && bounds.height === baselineBounds.height, `physical window changed to ${bounds.width}×${bounds.height}`],
          [Math.abs(measuredZoom - expectedZoom) < 0.02, `measured zoom was ${measuredZoom.toFixed(2)}x`],
          [Math.abs(result.viewport.width - Math.round(baseline.viewport.width / expectedZoom)) <= 1, `CSS viewport was ${result.viewport.width}px`],
          [result.shellContained, `shell left the ${result.viewport.width}×${result.viewport.height} viewport`],
          [result.fixedChrome, `fixed chrome changed: ${JSON.stringify(result.geometry)}`],
          [result.workspaceSeparated, `workspace overlapped chrome: ${JSON.stringify(result.geometry)}`],
          [!result.pageOverflow, `page overflowed the ${result.viewport.width}×${result.viewport.height} viewport`],
          [!result.unsupportedVisible, "unsupported-device screen became visible"]
        ];
        for (const [passed, message] of checks) {
          if (!check(passed)) failures.push(`${profile.percent}%: ${message}`);
        }
      }
    } finally {
      await setZoom(1).catch(() => {});
    }

    assert(failures.length === 0, `browser zoom completed all profiles with ${failures.length} failure(s):\n- ${failures.join("\n- ")}`);
    if (playback.exclusiveJourney) {
      await playback.show(page, "Close Workbench · shutdown verification");
      await page.locator("#close-button").click();
      await page.locator(".shutdown-state h1").waitFor({ state: "visible" });
      assert(await page.locator(".shutdown-state h1").textContent() === "Workbench Closed", "Close Workbench did not render the approved closed state");
      return { shutdownVerified: true };
    }
    return null;
  });
}

module.exports = { name: "browser zoom", behaviorIds, isolatedBrowser: true, viewport, run };
