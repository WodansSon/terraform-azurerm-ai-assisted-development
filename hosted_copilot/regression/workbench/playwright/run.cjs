const fs = require("node:fs");
const os = require("node:os");
const path = require("node:path");

const workbenchRegressionRoot = path.resolve(__dirname, "..");
const toolsRoot = path.resolve(workbenchRegressionRoot, "../../tools");
const { chromium } = require(require.resolve("@playwright/test", { paths: [toolsRoot] }));
const puppeteer = require(require.resolve("puppeteer", { paths: [toolsRoot] }));

function validateManifest(manifest) {
  if (manifest.schemaVersion !== 1) throw new Error("Workbench behavior manifest schemaVersion must be 1");
  if (manifest.targetHarness !== "playwright") throw new Error("Workbench behavior manifest targetHarness must be playwright");
  if (!Array.isArray(manifest.behaviors) || manifest.behaviors.length === 0) throw new Error("Workbench behavior manifest must contain behaviors");

  const behaviorIds = manifest.behaviors.map((behavior) => behavior.id);
  if (new Set(behaviorIds).size !== behaviorIds.length) throw new Error("Workbench behavior manifest contains duplicate behavior IDs");

  const journeys = new Map();
  for (const behavior of manifest.behaviors) {
    const journeyPath = path.resolve(workbenchRegressionRoot, behavior.journey);
    if (!journeyPath.startsWith(path.join(workbenchRegressionRoot, "playwright", "journeys") + path.sep)) {
      throw new Error(`Behavior ${behavior.id} points outside the Playwright journeys directory`);
    }
    if (!fs.existsSync(journeyPath)) throw new Error(`Behavior ${behavior.id} references missing journey ${behavior.journey}`);
    if (!journeys.has(journeyPath)) journeys.set(journeyPath, []);
    journeys.get(journeyPath).push(behavior.id);
  }

  return journeys;
}

async function run() {
  const args = process.argv.slice(2);
  const baseUrl = args[0];
  if (!baseUrl) throw new Error("Workbench URL is required");
  const headed = args.includes("--headed");
  const optionValue = (name) => {
    const index = args.indexOf(name);
    return index >= 0 ? args[index + 1] : null;
  };
  const slowMo = Number(optionValue("--slow-mo") || 0);
  const transitionDelay = Number(optionValue("--transition-delay") || 0);
  const requestedJourney = optionValue("--journey");
  const journeyFilter = requestedJourney === "all" ? null : requestedJourney;
  const resultFile = optionValue("--result-file");
  const shutdownAtEnd = args.includes("--shutdown-at-end");
  if (!Number.isInteger(slowMo) || slowMo < 0 || slowMo > 2000) throw new Error("--slow-mo must be an integer from 0 through 2000");
  if (!Number.isInteger(transitionDelay) || transitionDelay < 0 || transitionDelay > 5000) throw new Error("--transition-delay must be an integer from 0 through 5000");
  if (headed && transitionDelay < 1000) throw new Error("headed playback requires --transition-delay of at least 1000 milliseconds");

  const manifestPath = path.join(workbenchRegressionRoot, "behavior-manifest.json");
  const manifest = JSON.parse(fs.readFileSync(manifestPath, "utf8"));
  const journeys = validateManifest(manifest);
  const selectedJourneys = new Map([...journeys].filter(([journeyPath]) => !journeyFilter || path.basename(journeyPath, ".journey.cjs") === journeyFilter));
  if (selectedJourneys.size === 0) throw new Error(`No Playwright journey matched ${journeyFilter}`);
  const executablePath = await puppeteer.executablePath();
  const browserArgs = ["--no-sandbox", "--disable-setuid-sandbox"];
  let browser = null;
  const getBrowser = async () => {
    if (!browser) browser = await chromium.launch({ executablePath, headless: !headed, slowMo, args: browserArgs });
    return browser;
  };
  let assertionCount = 0;
  let behaviorCount = 0;
  let viewportAssertionCount = 0;
  let viewportCount = 0;
  let shutdownVerified = false;
  let playbackError = null;
  const windowMetrics = new WeakMap();
  const playback = {
    headed,
    transitionDelay,
    exclusiveJourney: selectedJourneys.size === 1,
    async runBrowserZoom(baseUrl, viewport, callback) {
      const extensionPath = path.join(__dirname, "zoom-extension");
      const userDataDir = fs.mkdtempSync(path.join(os.tmpdir(), "hosted-workbench-zoom-"));
      let session = null;
      const context = await chromium.launchPersistentContext(userDataDir, {
        executablePath,
        headless: !headed,
        slowMo,
        viewport: headed ? null : viewport,
        args: [
          ...browserArgs,
          `--disable-extensions-except=${extensionPath}`,
          `--load-extension=${extensionPath}`
        ]
      });
      try {
        const pages = context.pages();
        const page = pages.find((item) => item.url().startsWith(baseUrl)) || pages[0] || await context.newPage();
        if (!page.url().startsWith(baseUrl)) await page.goto(baseUrl, { waitUntil: "networkidle" });
        for (const extraPage of context.pages()) {
          if (extraPage !== page) await extraPage.close();
        }
        const worker = context.serviceWorkers()[0] || await context.waitForEvent("serviceworker");
        session = await context.newCDPSession(page);
        const { windowId } = await session.send("Browser.getWindowForTarget");
        const getWindowBounds = async () => (await session.send("Browser.getWindowBounds", { windowId })).bounds;
        const setZoom = async (zoomFactor) => worker.evaluate(async ({ targetUrl, factor }) => {
          const tabs = await chrome.tabs.query({});
          const tab = tabs.find((item) => item.url?.startsWith(targetUrl));
          if (!tab?.id) throw new Error(`Workbench tab was not found for ${targetUrl}`);
          await chrome.tabs.setZoom(tab.id, factor);
          return chrome.tabs.getZoom(tab.id);
        }, { targetUrl: baseUrl, factor: zoomFactor });
        return await callback(page, setZoom, getWindowBounds);
      } finally {
        if (session) await session.detach().catch(() => {});
        await context.close();
        fs.rmSync(userDataDir, { recursive: true, force: true });
      }
    },
    async resizeWindow(page, viewport) {
      if (!headed) return;
      let metrics = windowMetrics.get(page);
      if (!metrics) {
        const session = await page.context().newCDPSession(page);
        const frame = await page.evaluate(() => ({
          horizontalChrome: Math.max(0, outerWidth - innerWidth),
          verticalChrome: Math.max(0, outerHeight - innerHeight),
          deviceScaleFactor: devicePixelRatio
        }));
        const { windowId } = await session.send("Browser.getWindowForTarget");
        metrics = { session, windowId, ...frame };
        windowMetrics.set(page, metrics);
      }
      await metrics.session.send("Emulation.clearDeviceMetricsOverride");
      let bounds = {
        width: viewport.width + metrics.horizontalChrome,
        height: viewport.height + metrics.verticalChrome
      };
      const samples = [];
      for (let attempt = 0; attempt < 8; attempt += 1) {
        await metrics.session.send("Browser.setWindowBounds", {
          windowId: metrics.windowId,
          bounds: { windowState: "normal", ...bounds }
        });
        await page.evaluate(() => new Promise((resolve) => requestAnimationFrame(() => requestAnimationFrame(resolve))));
        const value = await page.evaluate(() => ({ outerWidth, outerHeight, innerWidth, innerHeight, deviceScaleFactor: devicePixelRatio }));
        samples.push({ bounds: { ...bounds }, value });
        if (value.innerWidth === viewport.width && value.innerHeight === viewport.height) break;
        const nextBounds = {
          width: bounds.width + viewport.width - value.innerWidth,
          height: bounds.height + viewport.height - value.innerHeight
        };
        if (samples.some((sample) => sample.bounds.width === nextBounds.width && sample.bounds.height === nextBounds.height)) break;
        bounds = nextBounds;
      }
      const eligible = samples.filter(({ value }) => value.innerHeight === viewport.height
        && (viewport.breakpointSide === "min"
          ? value.innerWidth >= viewport.width
          : viewport.breakpointSide === "max"
            ? value.innerWidth <= viewport.width
            : true));
      const selected = eligible.sort((left, right) => Math.abs(left.value.innerWidth - viewport.width) - Math.abs(right.value.innerWidth - viewport.width))[0];
      if (!selected) {
        const observed = samples.map(({ value }) => `${value.innerWidth}x${value.innerHeight}`).join(", ");
        throw new Error(`No native-scale ${viewport.breakpointSide} viewport represented ${viewport.width}x${viewport.height}; observed ${observed}`);
      }
      await metrics.session.send("Browser.setWindowBounds", {
        windowId: metrics.windowId,
        bounds: { windowState: "normal", ...selected.bounds }
      });
      await page.evaluate(() => new Promise((resolve) => requestAnimationFrame(() => requestAnimationFrame(resolve))));
      const physical = await page.evaluate(() => ({ outerWidth, outerHeight, innerWidth, innerHeight, deviceScaleFactor: devicePixelRatio }));
      const target = physical.innerWidth === viewport.width ? "" : ` · ${viewport.width}px ${viewport.breakpointSide}-side target`;
      process.stderr.write(`[WINDOW] ${physical.outerWidth}x${physical.outerHeight} frame · ${physical.innerWidth}x${physical.innerHeight} viewport · ${physical.deviceScaleFactor}x native scale${target}\n`);
    },
    async show(page, label) {
      if (!headed) return;
      process.stderr.write(`[PLAYBACK] ${label}\n`);
      await page.evaluate((text) => {
        let indicator = document.querySelector("#workbench-playback-indicator");
        if (!indicator) {
          indicator = document.createElement("div");
          indicator.id = "workbench-playback-indicator";
          Object.assign(indicator.style, {
            position: "fixed",
            right: "12px",
            top: "44px",
            zIndex: "2147483647",
            padding: "6px 10px",
            color: "#ffffff",
            background: "#005fb8",
            border: "1px solid #75beff",
            borderRadius: "2px",
            font: "600 12px/16px 'Segoe UI', sans-serif",
            pointerEvents: "none"
          });
          document.body.appendChild(indicator);
        }
        indicator.textContent = text;
      }, label);
      await page.waitForTimeout(transitionDelay);
    }
  };

  try {
    for (const [journeyPath, manifestBehaviorIds] of selectedJourneys) {
      const journey = require(journeyPath);
      const declaredBehaviorIds = [...journey.behaviorIds].sort();
      const expectedBehaviorIds = [...manifestBehaviorIds].sort();
      if (JSON.stringify(declaredBehaviorIds) !== JSON.stringify(expectedBehaviorIds)) {
        throw new Error(`${path.basename(journeyPath)} behavior declarations do not match behavior-manifest.json`);
      }
      behaviorCount += manifestBehaviorIds.length;

      const context = journey.isolatedBrowser
        ? null
        : await (await getBrowser()).newContext(headed && journey.physicalViewport
          ? { viewport: null }
          : { viewport: journey.viewport || { width: 768, height: 900 } });
      const page = context ? await context.newPage() : null;
      const assert = (condition, message) => {
        assertionCount += 1;
        if (!condition) throw new Error(`${journey.name}: ${message}`);
      };
      const check = (condition) => {
        assertionCount += 1;
        return condition;
      };

      try {
        const journeyResult = await journey.run({ page, baseUrl, assert, check, playback });
        if (journeyResult?.shutdownVerified) shutdownVerified = true;
        if (journeyResult?.viewportAssertionCount) {
          viewportAssertionCount += journeyResult.viewportAssertionCount;
          viewportCount = journeyResult.viewportCount;
          assertionCount += journeyResult.viewportAssertionCount;
        }
      } finally {
        if (context) await context.close();
      }
    }

  } catch (error) {
    playbackError = error;
  } finally {
    if (shutdownAtEnd && playbackError && selectedJourneys.size === 1 && [...selectedJourneys.keys()].some((journeyPath) => require(journeyPath).isolatedBrowser)) {
      try {
        const configResponse = await fetch(new URL("shutdown-config.js", baseUrl));
        const config = await configResponse.text();
        const token = config.match(/"shutdownToken"\s*:\s*"([0-9a-f]{64})"/)?.[1];
        if (!token) throw new Error("headed playback: shutdown token was not found");
        try {
          await fetch(new URL("shutdown", baseUrl), {
            method: "POST",
            headers: { "X-Workbench-Shutdown-Token": token }
          });
        } catch {
          // The response can race with the owned server closing its listener.
        }
        shutdownVerified = true;
      } catch (error) {
        if (!playbackError) playbackError = error;
      }
    } else if (shutdownAtEnd && !shutdownVerified) {
      const context = await (await getBrowser()).newContext({ viewport: { width: 768, height: 900 } });
      const page = await context.newPage();
      try {
        await page.goto(baseUrl, { waitUntil: "networkidle" });
        await playback.show(page, "Close Workbench · shutdown verification");
        await page.locator("#close-button").click();
        await page.locator(".shutdown-state h1").waitFor({ state: "visible" });
        const closedState = await page.locator(".shutdown-state").evaluate((view) => {
          const icon = view.querySelector(".shutdown-brand-icon");
          return {
            productName: view.querySelector(".shutdown-product-name")?.textContent.trim(),
            heading: view.querySelector("h1")?.textContent.trim(),
            copy: view.querySelector(":scope > p:last-child")?.textContent.trim(),
            iconColor: getComputedStyle(icon).color,
            hasInlineIconPath: Boolean(icon?.querySelector("path")),
            hasObsoleteMark: Boolean(view.querySelector(".brand-mark, .unsupported-mark")) || view.textContent.trim().startsWith("HR")
          };
        });
        const closedChecks = [
          [closedState.productName === "HOSTED COPILOT RULE MANAGER", "closed state lost the approved product identity"],
          [closedState.heading === "Workbench Closed", "Close Workbench did not render the approved heading"],
          [closedState.copy === "The local server has stopped. This tab can be closed.", "closed state explanatory copy is incorrect"],
          [closedState.hasInlineIconPath && closedState.iconColor === "rgb(255, 255, 0)", "closed state does not use the approved self-contained yellow JSON-braces mark"],
          [!closedState.hasObsoleteMark, "closed state still renders an obsolete HR mark"]
        ];
        for (const [passed, message] of closedChecks) {
          assertionCount += 1;
          if (!passed) throw new Error(`headed playback: ${message}`);
        }
        shutdownVerified = true;
        if (headed) await page.waitForTimeout(transitionDelay);
      } catch (error) {
        if (!playbackError) playbackError = error;
      } finally {
        await context.close();
      }
    }
    if (browser) await browser.close();
  }

  if (playbackError) throw playbackError;

  const result = JSON.stringify({
    status: "passed",
    harness: "playwright",
    mode: headed ? "headed" : "headless",
    transitionDelay,
    shutdownVerified,
    journeyCount: selectedJourneys.size,
    behaviorCount,
    assertionCount,
    viewportAssertionCount,
    viewportCount
  });
  if (resultFile) {
    fs.writeFileSync(resultFile, result, "utf8");
  } else {
    process.stdout.write(result);
  }
}

run().catch((error) => {
  process.stderr.write(`${error.stack || error.message}\n`);
  process.exit(1);
});
