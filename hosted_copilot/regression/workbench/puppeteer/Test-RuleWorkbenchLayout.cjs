const path = require("node:path");

const npmRoot = path.resolve(__dirname, "../../../tools/npm");
const puppeteer = require(require.resolve("puppeteer", { paths: [npmRoot] }));
const { runViewportSuite } = require("../shared/WorkbenchViewportSuite.cjs");

async function run() {
  const baseUrl = process.argv[2];
  if (!baseUrl) throw new Error("Workbench URL is required");

  const browser = await puppeteer.launch({
    headless: true,
    args: ["--no-sandbox", "--disable-setuid-sandbox"]
  });

  try {
    const page = await browser.newPage();
    await page.emulateMediaFeatures([{ name: "prefers-reduced-motion", value: "no-preference" }]);
    if (await page.evaluate(() => matchMedia("(prefers-reduced-motion: reduce)").matches)) {
      throw new Error("Workbench viewport verification requires normal motion");
    }
    page.setDefaultTimeout(10000);
    page.setDefaultNavigationTimeout(10000);
    const result = await runViewportSuite(page, baseUrl, {
      setViewport: (targetPage, viewport) => targetPage.setViewport({
        width: viewport.width,
        height: viewport.height,
        deviceScaleFactor: viewport.deviceScaleFactor
      }),
      goto: (targetPage, url) => targetPage.goto(url, { waitUntil: "domcontentloaded" })
    });
    process.stdout.write(JSON.stringify(result));
  } finally {
    await browser.close();
  }
}

run().catch((error) => {
  process.stderr.write(`${error.stack || error.message}\n`);
  process.exit(1);
});
