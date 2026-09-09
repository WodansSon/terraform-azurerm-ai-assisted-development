const { openWorkbench } = require("../helpers/workbench.cjs");

const behaviorIds = [
  "WB-UX-SCROLLBAR-001",
  "WB-UX-SCROLLBAR-002",
  "WB-UX-SCROLLBAR-003"
];

async function run({ page, baseUrl, assert, playback }) {
  await openWorkbench(page, baseUrl);
  await playback.show(page, "Scrollbar visibility and timing");

  const sample = () => page.evaluate(() => {
    const scroller = document.querySelector("#candidate-list");
    const thumb = getComputedStyle(scroller, "::-webkit-scrollbar-thumb");
    const button = getComputedStyle(scroller, "::-webkit-scrollbar-button");
    const alpha = Number.parseFloat(thumb.backgroundColor.match(/[\d.]+(?=\))|[\d.]+(?=\s*\/\s*[\d.]+\))/g)?.at(-1) || "0");
    return {
      alpha,
      clientWidth: scroller.clientWidth,
      focusWithin: scroller.matches(":focus-within"),
      transitionDuration: getComputedStyle(scroller).transitionDuration,
      buttonDisplay: button.display,
      buttonWidth: button.width,
      buttonHeight: button.height,
      borderRadius: thumb.borderRadius,
      tooltipVisible: getComputedStyle(document.querySelector("#status-surface-tooltip")).visibility === "visible"
    };
  });

  await page.evaluate(() => {
    document.activeElement?.blur();
    hideStatusTooltip();
  });
  await page.mouse.move(16, 400);
  await page.waitForTimeout(420);
  const idle = await sample();

  const bounds = await page.locator("#candidate-list").boundingBox();
  await page.mouse.move(bounds.x + bounds.width - 3, bounds.y + 220);
  const enterStart = await sample();
  await page.waitForTimeout(90);
  const entering = await sample();
  await page.waitForTimeout(130);
  const visible = await sample();

  await page.mouse.move(16, 400);
  const leaveStart = await sample();
  await page.waitForTimeout(180);
  const leaving = await sample();
  await page.waitForTimeout(210);
  const hidden = await sample();

  await page.locator("#candidate-list summary").first().focus();
  await page.waitForTimeout(220);
  const focused = await sample();

  assert(idle.alpha === 0 && hidden.alpha === 0, "scrollbar thumb remains visible while idle");
  assert(enterStart.transitionDuration === "0.18s" && entering.alpha > 0 && entering.alpha < visible.alpha && visible.alpha >= 0.5, "scrollbar thumb does not fade in over 180ms");
  assert(leaveStart.transitionDuration === "0.36s" && leaving.alpha > 0 && leaving.alpha < leaveStart.alpha, "scrollbar thumb does not fade out over 360ms");
  assert(idle.buttonDisplay === "none" && idle.buttonWidth === "0px" && idle.buttonHeight === "0px" && idle.borderRadius === "0px", "scrollbar arrows or rounded thumb ends remain visible");
  assert(!visible.tooltipVisible && !idle.tooltipVisible, "scrollbar hover activates an unrelated Workbench tooltip");
  assert(focused.focusWithin && focused.alpha >= 0.5, "keyboard focus does not reveal the scrollbar thumb");
  assert([idle, enterStart, entering, visible, leaveStart, leaving, hidden, focused].every((value) => value.clientWidth === idle.clientWidth), "scrollbar visibility changes the content width");
}

module.exports = { name: "scrollbar visibility", behaviorIds, viewport: { width: 768, height: 900 }, run };
