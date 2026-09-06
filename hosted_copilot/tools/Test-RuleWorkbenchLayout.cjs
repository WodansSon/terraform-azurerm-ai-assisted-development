const path = require("path");

function resolvePuppeteer() {
  const packageRoots = (process.env.PATH || "")
    .split(path.delimiter)
    .filter((entry) => entry.includes("_npx"))
    .map((entry) => path.dirname(entry));

  return require(require.resolve("puppeteer", { paths: packageRoots }));
}

function assert(condition, message) {
  if (!condition) throw new Error(message);
}

async function waitForWorkbench(page) {
  await page.waitForFunction(() => Number(document.querySelector("#catalog-count")?.textContent) > 0);
}

async function activateCandidateDetails(page) {
  await page.evaluate(() => {
    document.querySelector('[data-view="catalog"]').click();
    document.querySelector('[data-workspace-tab="candidate-sources"]').click();
    document.querySelector('[data-candidate-pane="candidates"]').click();
    const source = [...document.querySelectorAll("#candidate-list > details.candidate-source-root")]
      .find((item) => item.querySelector("[data-candidate-key]"));
    source.open = true;
    source.querySelector("[data-candidate-key]").click();
  });
}

async function activateAssessmentDetails(page) {
  await page.evaluate(() => {
    document.querySelector('[data-workspace-tab="assessment-results"]').click();
    document.querySelector('[data-assessment-pane="details"]').click();
    const panel = document.querySelector("#assessment-results-panel .assessment-panel");
    const probe = document.createElement("div");
    probe.dataset.layoutProbe = "assessment";
    probe.style.height = "1600px";
    panel.appendChild(probe);
  });
}

async function activateViewWithProbe(page, view, ownerSelector) {
  await page.evaluate(({ view, ownerSelector }) => {
    document.querySelector(`[data-view="${view}"]`).click();
    const owner = document.querySelector(ownerSelector);
    const probe = document.createElement("div");
    probe.dataset.layoutProbe = view;
    probe.style.width = "1200px";
    probe.style.height = "1600px";
    owner.appendChild(probe);
  }, { view, ownerSelector });
}

async function assertContainedScroll(page, width, name, ownerSelector, fixedSelector) {
  const result = await page.evaluate(({ ownerSelector, fixedSelector }) => {
    const owner = document.querySelector(ownerSelector);
    const fixed = document.querySelector(fixedSelector);
    const fixedTop = fixed.getBoundingClientRect().top;
    owner.scrollTop = 320;
    owner.scrollLeft = 160;
    return {
      documentHeight: document.documentElement.scrollHeight,
      documentWidth: document.documentElement.scrollWidth,
      viewportHeight: innerHeight,
      viewportWidth: innerWidth,
      windowY: scrollY,
      ownerClientHeight: owner.clientHeight,
      ownerScrollHeight: owner.scrollHeight,
      ownerScrollTop: owner.scrollTop,
      fixedTop,
      fixedTopAfter: fixed.getBoundingClientRect().top,
    };
  }, { ownerSelector, fixedSelector });

  assert(result.documentHeight <= result.viewportHeight + 1, `${width}px ${name}: document scrolls vertically`);
  assert(result.documentWidth <= result.viewportWidth + 1, `${width}px ${name}: document scrolls horizontally`);
  assert(result.windowY === 0, `${width}px ${name}: window scroll position changed`);
  assert(result.ownerScrollHeight > result.ownerClientHeight, `${width}px ${name}: designated pane is not scrollable`);
  assert(result.ownerScrollTop > 0, `${width}px ${name}: designated pane did not accept scroll`);
  assert(result.fixedTopAfter === result.fixedTop, `${width}px ${name}: fixed view controls moved with pane content`);
}

async function assertStatusTooltip(page, width) {
  const item = await page.$("#status-headroom").then((node) => node.evaluateHandle((element) => element.parentElement));
  const box = await item.boundingBox();

  async function enterFrom(side) {
    await page.mouse.move(side === "right" ? box.x + box.width + 24 : box.x - 24, box.y + box.height / 2);
    await page.mouse.move(side === "right" ? box.x + box.width - 2 : box.x + 2, box.y + box.height / 2);
    return page.evaluate(() => {
      const tooltip = document.querySelector("#status-surface-tooltip");
      const statusbar = document.querySelector(".ide-statusbar");
      const rect = tooltip.getBoundingClientRect();
      return {
        text: tooltip.textContent,
        visible: getComputedStyle(tooltip).visibility === "visible",
        left: rect.left,
        right: rect.right,
        top: rect.top,
        bottom: rect.bottom,
        width: rect.width,
        statusTop: statusbar.getBoundingClientRect().top,
        nativeTitleCount: document.querySelectorAll(".ide-statusbar .status-item[title]").length,
      };
    });
  }

  const fromRight = await enterFrom("right");
  const fromLeft = await enterFrom("left");
  assert(fromRight.visible && fromLeft.visible, `${width}px status tooltip: tooltip is not visible`);
  assert(fromRight.text === "Test guidance headroom" && fromLeft.text === fromRight.text, `${width}px status tooltip: tooltip text is incorrect`);
  assert(fromRight.left >= 0 && fromRight.right <= width && fromRight.top >= 0, `${width}px status tooltip: tooltip leaves the rendered canvas`);
  assert(fromRight.bottom < fromRight.statusTop, `${width}px status tooltip: tooltip is not above the status bar`);
  assert(Math.abs(fromRight.left - fromLeft.left) < 0.1 && Math.abs(fromRight.width - fromLeft.width) < 0.1, `${width}px status tooltip: entry direction changes tooltip geometry`);
  assert(fromRight.nativeTitleCount === 0, `${width}px status tooltip: native status titles remain active`);
}

async function run() {
  const baseUrl = process.argv[2];
  assert(baseUrl, "Workbench URL is required");

  const puppeteer = resolvePuppeteer();
  const browser = await puppeteer.launch({
    headless: true,
    args: ["--no-sandbox", "--disable-setuid-sandbox"],
  });

  try {
    const page = await browser.newPage();
    const viewports = [767, 768, 900, 901, 1180, 1181, 1399, 1400, 1920];
    let assertionCount = 0;

    for (const width of viewports) {
      await page.setViewport({ width, height: 900, deviceScaleFactor: 1 });
      await page.goto(baseUrl, { waitUntil: "networkidle0" });

      if (width === 767) {
        const unsupported = await page.evaluate(() => document.documentElement.classList.contains("mobile-unsupported")
          && getComputedStyle(document.querySelector(".unsupported-device")).display !== "none");
        assert(unsupported, "767px: unsupported-device boundary is not active");
        assertionCount += 1;
        continue;
      }

      await waitForWorkbench(page);
      await assertStatusTooltip(page, width);
      assertionCount += 6;

      await activateCandidateDetails(page);
      await assertContainedScroll(page, width, "Candidate Details", "#candidate-sources-panel .assessment-panel", ".candidate-pane-switch");
      assertionCount += 6;

      await activateAssessmentDetails(page);
      await assertContainedScroll(page, width, "Assessment Details", "#assessment-results-panel .assessment-panel", ".assessment-pane-switch");
      assertionCount += 6;

      await activateViewWithProbe(page, "plan", "#plan-view .plan-table-wrap");
      await assertContainedScroll(page, width, "Promotion Plan", "#plan-view .plan-table-wrap", "#plan-view .page-heading");
      assertionCount += 6;

      await activateViewWithProbe(page, "preview", "#preview-view .preview-code");
      await assertContainedScroll(page, width, "Preview", "#preview-view .preview-code", "#preview-view .page-heading");
      assertionCount += 6;
    }

    process.stdout.write(JSON.stringify({ status: "passed", viewportCount: viewports.length, assertionCount }));
  } finally {
    await browser.close();
  }
}

run().catch((error) => {
  process.stderr.write(`${error.stack || error.message}\n`);
  process.exit(1);
});
