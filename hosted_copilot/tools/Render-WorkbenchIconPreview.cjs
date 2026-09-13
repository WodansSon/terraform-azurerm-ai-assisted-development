const path = require("node:path");
const { pathToFileURL } = require("node:url");
const puppeteer = require("puppeteer");

async function run() {
  const [sourcePath, outputPath, widthValue, heightValue] = process.argv.slice(2);
  const width = Number(widthValue);
  const height = Number(heightValue);
  if (!sourcePath || !outputPath || !Number.isInteger(width) || width <= 0 || !Number.isInteger(height) || height <= 0) {
    throw new Error("Usage: node Render-WorkbenchIconPreview.cjs <source.svg> <output.png> <width> <height>");
  }

  const browser = await puppeteer.launch({
    headless: true,
    args: ["--no-sandbox", "--disable-setuid-sandbox", "--disable-gpu"]
  });
  try {
    const page = await browser.newPage();
    await page.setViewport({ width, height, deviceScaleFactor: 1 });
    await page.goto(pathToFileURL(path.resolve(sourcePath)).href, { waitUntil: "load" });
    await page.screenshot({
      path: path.resolve(outputPath),
      type: "png",
      clip: { x: 0, y: 0, width, height }
    });
  } finally {
    await browser.close();
  }
}

run().catch((error) => {
  process.stderr.write(`${error.stack || error.message}\n`);
  process.exitCode = 1;
});
