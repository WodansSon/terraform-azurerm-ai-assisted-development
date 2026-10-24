const { openWorkbench } = require("../helpers/workbench.cjs");
const { readSavedRuleRequest, createSavedRuleEvaluation } = require("../helpers/saved-rule-evaluation.cjs");

const behaviorIds = ["WB-UX-RELATIONSHIP-001", "WB-UX-RELATIONSHIP-002", "WB-UX-RELATIONSHIP-003", "WB-UX-RELATIONSHIP-004", "WB-UX-RELATIONSHIP-005", "WB-UX-RELATIONSHIP-006"];

async function verifyWaitingPanels(page, assert, setZoom) {
  const initialRatio = await page.evaluate(() => devicePixelRatio);
  await page.evaluate(() => {
    const sheet = new CSSStyleSheet();
    sheet.replaceSync(`
      .waiting-panel-test-fixture { position: fixed; left: 23.45px; top: 28.3px; width: 406.2px; height: 320px; overflow: auto; z-index: 100; }
      .waiting-panel-test-content { padding-top: 70.35px; min-height: 700px; }
      .waiting-panel-test-content > .waiting-panel + .waiting-panel { width: 301.3px; margin-top: 13.3px; }
    `);
    document.adoptedStyleSheets = [...document.adoptedStyleSheets, sheet];
    const container = document.createElement("div");
    container.className = "waiting-panel-test-fixture";
    const title = "Loading <b>&</b> e\u0301 \u{1f469}\u200d\u{1f4bb}...";
    const body = "Body <script>not executable</script> & ordinary text.";
    container.innerHTML = `<div class="waiting-panel-test-content">${renderWaitingPanel({ title, body })}${renderWaitingPanel({ title: "Another task...", body: "A separate reusable waiting panel." })}</div>`;
    globalThis.__waitingPanelFixture = { container, sheet, title, body, baseline: waitingPanels.size };
    document.body.appendChild(container);
  });
  try {
    await page.waitForFunction(() => waitingPanels.size === globalThis.__waitingPanelFixture.baseline + 2
      && [...globalThis.__waitingPanelFixture.container.querySelectorAll(".waiting-panel")].every((panel) => panel.hasAttribute("data-waiting-panel-ready")));
    const markup = await page.evaluate(() => {
      const { container, title, body } = globalThis.__waitingPanelFixture;
      const panels = [...container.querySelectorAll(".waiting-panel")];
      return {
        escaped: panels[0].querySelector(".sr-only").textContent === title && panels[0].querySelector(".waiting-panel-body").textContent === body && !container.querySelector("b, script"),
        accessible: panels.every((panel) => panel.getAttribute("role") === "status" && panel.getAttribute("aria-live") === "polite" && panel.getAttribute("aria-atomic") === "true"),
        noInlineStyles: !container.querySelector("[style]"),
        independent: panels[0].dataset.waitingPanel !== panels[1].dataset.waitingPanel && panels[0].getBoundingClientRect().width !== panels[1].getBoundingClientRect().width,
        boundedRules: waitingPanelStyleSheet.cssRules.length === waitingPanels.size
      };
    });
    assert(markup.escaped && markup.accessible && markup.noInlineStyles, `Reusable waiting panels do not preserve escaped accessible text under the existing content policy: ${JSON.stringify(markup)}`);
    assert(markup.independent && markup.boundedRules, "Waiting panel instances share geometry or allocate duplicate rules");
    for (const scale of [1, 1.25, 1.5, 2]) {
      assert(Math.abs(await setZoom(scale) - scale) < 0.001, `Browser did not apply ${scale}x zoom`);
      await page.waitForFunction((ratio) => Math.abs(devicePixelRatio - ratio) < 0.001 && [...globalThis.__waitingPanelFixture.container.querySelectorAll(".waiting-panel")].every((panel) => {
        const pixel = parseFloat(getComputedStyle(panel).getPropertyValue("--waiting-panel-pixel"));
        return Math.abs(pixel * ratio - 1) < 0.001;
      }), initialRatio * scale);
      const result = await page.evaluate(() => {
        const splitLayers = (text) => {
          const layers = [];
          let depth = 0;
          let start = 0;
          for (let index = 0; index < text.length; index++) {
            if (text[index] === "(") depth++;
            else if (text[index] === ")") depth--;
            else if (text[index] === "," && depth === 0) { layers.push(text.slice(start, index)); start = index + 1; }
          }
          layers.push(text.slice(start));
          return layers;
        };
        return [...globalThis.__waitingPanelFixture.container.querySelectorAll(".waiting-panel")].map((panel) => {
          const frame = panel.querySelector(".waiting-panel-border");
          const frameStyle = getComputedStyle(frame);
          const computed = getComputedStyle(panel);
          const width = parseFloat(computed.getPropertyValue("--waiting-panel-width"));
          const height = parseFloat(computed.getPropertyValue("--waiting-panel-height"));
          const length = 2 * (width + height);
          const band = parseFloat(computed.getPropertyValue("--waiting-panel-band"));
          const animation = panel.getAnimations().find((item) => item.animationName === "waiting-panel-chase");
          if (!animation) throw new Error("Waiting panel CSS chase is missing");
          const masks = splitLayers(getComputedStyle(frame, "::before").maskImage);
          const profiles = masks.map((mask) => {
            const stops = splitLayers(mask.slice(mask.indexOf("(") + 1, -1));
            if (stops[0].trim().startsWith("to ")) stops.shift();
            return stops.map((stop) => {
              const match = stop.trim().match(/^(.*)\s+([\d.]+)%$/);
              if (!match) throw new Error(`Unexpected waiting panel opacity stop: ${stop}`);
              const channels = match[1].match(/[\d.]+/g)?.map(Number);
              return { position: Number(match[2]) / 100, alpha: match[1] === "transparent" ? 0 : channels.length === 4 ? channels[3] : 1 };
            });
          });
          const opacity = (edge, fraction) => {
            const profile = profiles[edge];
            let index = 1;
            while (fraction > profile[index].position) index++;
            const start = profile[index - 1], end = profile[index];
            return start.alpha + (end.alpha - start.alpha) * (fraction - start.position) / (end.position - start.position);
          };
          const modulo = (value) => ((value % length) + length) % length / length;
          const duration = Number(animation.effect.getTiming().duration);
          const time = animation.currentTime;
          const phases = [];
          animation.pause();
          try {
            for (const phase of [0, 0.125, 0.25, 0.375, 0.5, 0.625, 0.75, 0.875, 1.125, 1.5]) {
              animation.currentTime = phase * duration;
              const beforeStyle = getComputedStyle(frame, "::before");
              const dimensions = [parseFloat(beforeStyle.width), parseFloat(beforeStyle.height)];
              const sizes = beforeStyle.maskSize.split(",").map((size) => size.trim().split(/\s+/).map(parseFloat));
              const positions = beforeStyle.maskPosition.split(",").map((position, index) => {
                const values = position.trim().match(/calc\([^)]+\)|\S+/g);
                return values.map((value, axis) => {
                  const available = dimensions[axis] - sizes[index][axis];
                  if (/^-?[\d.]+px$/.test(value)) return parseFloat(value);
                  if (/^-?[\d.]+%$/.test(value)) return parseFloat(value) * available / 100;
                  const match = value.match(/^calc\((-?[\d.]+)% ([+-]) ([\d.]+)px\)$/);
                  if (!match) throw new Error(`Unexpected waiting mask position: ${value}`);
                  return Number(match[1]) * available / 100 + (match[2] === "-" ? -1 : 1) * Number(match[3]);
                });
              });
              const distance = (phase % 1) * length;
              const expected = [[distance, 0], [dimensions[0] - band, distance - width], [-height - distance, dimensions[1] - band], [0, -distance]];
              const active = Array.from({ length: 512 }, (_, index) => {
                const point = (index + 0.5) * length / 512;
                if (point < width) return opacity(0, modulo(point - positions[0][0])) > 0.0001;
                if (point < width + height) return opacity(1, modulo(point - width - positions[1][1])) > 0.0001;
                if (point < 2 * width + height) return opacity(2, modulo(positions[2][0] + length - (2 * width + height - point))) > 0.0001;
                return opacity(3, modulo(positions[3][1] + length - (length - point))) > 0.0001;
              });
              const runs = active.filter((value, index) => value && !active[(index + active.length - 1) % active.length]).length;
              const lit = active.filter(Boolean).length;
              phases.push(positions.length === 4 && positions.every((position, index) => position.every((value, axis) => Math.abs(value - expected[index][axis]) < 0.1))
                && runs === 1 && lit >= 126 && lit <= 130);
            }
          } finally {
            animation.currentTime = time;
            animation.play();
          }
          const image = getComputedStyle(frame, "::before").backgroundImage;
          const canvas = new OffscreenCanvas(Math.ceil(width), Math.ceil(height));
          const context = canvas.getContext("2d", { willReadFrequently: true });
          if (!context) throw new Error("Waiting panel palette verification requires a canvas context");
          const gradient = context.createConicGradient(-Math.PI / 2, width / 2, height / 2);
          for (const stop of splitLayers(image.slice(image.indexOf(",") + 1, -1))) {
            const match = stop.trim().match(/^(.*)\s+([\d.]+)deg$/);
            if (!match) throw new Error(`Unexpected waiting panel color stop: ${stop}`);
            gradient.addColorStop(Number(match[2]) / 360, match[1]);
          }
          context.fillStyle = gradient;
          context.fillRect(0, 0, canvas.width, canvas.height);
          const colors = [
            [(3 * width + height) / 4, 0, [74, 240, 192]],
            [(3 * width + height) / 4, height, [180, 74, 255]],
            [(width - height) / 4, height, [74, 240, 192]],
            [(width - height) / 4, 0, [81, 162, 255]]
          ].map(([x, y, expected]) => {
            const actual = [...context.getImageData(Math.min(canvas.width - 1, Math.floor(x)), Math.min(canvas.height - 1, Math.floor(y)), 1, 1).data].slice(0, 3);
            return actual.every((value, index) => Math.abs(value - expected[index]) <= 4);
          });
          return {
            edges: [frame.getBoundingClientRect().left, frame.getBoundingClientRect().right, frame.getBoundingClientRect().top, frame.getBoundingClientRect().bottom].map((edge) => edge * devicePixelRatio),
            pixelWidths: ["Top", "Bottom", "Left", "Right"].map((edge) => parseFloat(frameStyle[`border${edge}Width`]) * devicePixelRatio),
            duration, phases, colors,
            maskLayers: splitLayers(getComputedStyle(frame, "::before").maskImage).length,
            repeat: getComputedStyle(frame, "::before").maskRepeat,
            sharedPalette: image === getComputedStyle(panel.querySelector(".waiting-panel-glow"), "::before").backgroundImage,
            noInlineStyles: !panel.hasAttribute("style") && !panel.querySelector("[style]")
          };
        });
      });
      for (const panel of result) {
        assert(panel.edges.every((edge) => Math.abs(edge - Math.round(edge)) < 0.001), `Waiting frame edges are not device-pixel aligned at ${scale}x scale: ${JSON.stringify(panel)}`);
        assert(panel.pixelWidths.every((width) => Math.abs(width - 1) < 0.001), `Waiting border is not one physical pixel at ${scale}x scale: ${JSON.stringify(panel.pixelWidths)}`);
        assert(panel.duration === 3500 && panel.phases.every(Boolean) && panel.maskLayers === 4 && panel.repeat === "repeat-x, repeat-y, repeat-x, repeat-y", `Waiting chase does not follow one continuous perimeter phase at ${scale}x scale: ${JSON.stringify(panel)}`);
        assert(panel.colors.every(Boolean) && panel.sharedPalette && panel.noInlineStyles, `Waiting colors do not cover equal perimeter quarters under the production content policy at ${scale}x scale: ${JSON.stringify(panel)}`);
      }
      const paintedPanel = page.locator(".waiting-panel-test-fixture .waiting-panel").first();
      const paintedEdges = [];
      try {
        for (let edge = 0; edge < 4; edge++) {
          const bounds = await paintedPanel.evaluate((panel, edge) => {
            const style = getComputedStyle(panel);
            const width = parseFloat(style.getPropertyValue("--waiting-panel-width"));
            const height = parseFloat(style.getPropertyValue("--waiting-panel-height"));
            const points = [width / 2, width + height / 2, 1.5 * width + height, 2 * width + 1.5 * height];
            const animation = panel.getAnimations().find((item) => item.animationName === "waiting-panel-chase");
            animation.pause();
            animation.currentTime = ((points[edge] / (2 * (width + height)) - 0.1 + 1) % 1) * 3500;
            const frame = panel.querySelector(".waiting-panel-border").getBoundingClientRect();
            return { left: frame.left, top: frame.top, right: frame.right, bottom: frame.bottom, viewportWidth: innerWidth, viewportHeight: innerHeight };
          }, edge);
          const image = await page.screenshot();
          paintedEdges.push(await page.evaluate(async ({ base64, edge, bounds }) => {
            const image = new Image();
            image.src = `data:image/png;base64,${base64}`;
            await image.decode();
            const canvas = document.createElement("canvas");
            canvas.width = image.width;
            canvas.height = image.height;
            const context = canvas.getContext("2d");
            context.drawImage(image, 0, 0);
            const pixels = context.getImageData(0, 0, image.width, image.height).data;
            const scaleX = image.width / bounds.viewportWidth, scaleY = image.height / bounds.viewportHeight;
            const leftEdge = Math.round(bounds.left * scaleX), rightEdge = Math.round(bounds.right * scaleX);
            const topEdge = Math.round(bounds.top * scaleY), bottomEdge = Math.round(bounds.bottom * scaleY);
            const regions = [[leftEdge + 10, topEdge - 1, rightEdge - 10, topEdge + 2],
              [rightEdge - 2, topEdge + 10, rightEdge + 1, bottomEdge - 10],
              [leftEdge + 10, bottomEdge - 2, rightEdge - 10, bottomEdge + 1],
              [leftEdge - 1, topEdge + 10, leftEdge + 2, bottomEdge - 10]];
            const [left, top, right, bottom] = regions[edge];
            let chroma = 0;
            for (let y = top; y < bottom; y++) for (let x = left; x < right; x++) {
              const offset = (y * image.width + x) * 4;
              const rgb = pixels.slice(offset, offset + 3);
              chroma = Math.max(chroma, Math.max(...rgb) - Math.min(...rgb));
            }
            return chroma;
          }, { base64: image.toString("base64"), edge, bounds }));
        }
      } finally {
        await paintedPanel.evaluate((panel) => panel.getAnimations().find((item) => item.animationName === "waiting-panel-chase").play());
      }
      assert(paintedEdges.every((chroma) => chroma > 40), `The colored chase does not paint every actual border at ${scale}x zoom: ${JSON.stringify(paintedEdges)}`);
    }
    await page.evaluate(() => {
      const fixture = globalThis.__waitingPanelFixture;
      fixture.sheet.cssRules[0].style.width = "503.7px";
      fixture.container.scrollTop = 17;
    });
    await page.waitForFunction(() => [...globalThis.__waitingPanelFixture.container.querySelectorAll(".waiting-panel")].every((panel) => {
      const rect = panel.getBoundingClientRect();
      const frame = panel.querySelector(".waiting-panel-border").getBoundingClientRect();
      return [frame.left, frame.right, frame.top, frame.bottom].every((edge) => Math.abs(edge * devicePixelRatio - Math.round(edge * devicePixelRatio)) < 0.001)
        && Math.abs(frame.width - (Math.round(rect.right * devicePixelRatio) - Math.round(rect.left * devicePixelRatio)) / devicePixelRatio) < 0.001;
    }));
    assert(await page.evaluate(() => {
      const fixture = globalThis.__waitingPanelFixture;
      return fixture.sheet.cssRules[0].style.width === "503.7px" && fixture.container.scrollTop === 17;
    }), "Waiting panel resize and contained-scroll fixture did not execute");
  } finally {
    await setZoom(1);
    await page.evaluate(() => {
      const fixture = globalThis.__waitingPanelFixture;
      fixture.container.remove();
      document.adoptedStyleSheets = [...document.adoptedStyleSheets].filter((sheet) => sheet !== fixture.sheet);
    });
    await page.waitForFunction(() => waitingPanels.size === globalThis.__waitingPanelFixture.baseline && waitingPanelStyleSheet.cssRules.length === waitingPanels.size);
    assert(await page.evaluate(() => {
      const clean = waitingPanels.size === globalThis.__waitingPanelFixture.baseline && waitingPanelStyleSheet.cssRules.length === waitingPanels.size;
      delete globalThis.__waitingPanelFixture;
      return clean;
    }), "Removed waiting panels retained geometry observations or stylesheet rules");
  }
}

async function run({ page, baseUrl, assert, playback }) {
  await openWorkbench(page, baseUrl);
  await playback.show(page, "Relationship check progress");
  await page.locator("#search-input").fill("REVIEW-REPO-001");
  await page.locator("#candidate-list .candidate-tree-copy").filter({ hasText: "REVIEW-REPO-001" }).first().click();
  const editor = page.locator('#assessment-panel [data-decision-field="proposedText"]');
  const save = page.locator("#assessment-panel [data-proposed-text-save]");
  const progress = page.locator("[data-manual-relationship-progress]");
  const statusPanel = progress.locator(".waiting-panel");
  await editor.waitFor({ state: "visible" });
  const originalText = await editor.inputValue();
  const setup = await page.evaluate(() => {
    const candidate = getActiveCandidate();
    updateDecision(candidate, {
      action: getAllowedActions(candidate).includes("update") ? "update" : "add",
      rationale: "Validate the edited wording before promotion.",
      ...createPlanMembership("manual")
    });
    renderAll();
    const relatedRule = state.bundle.catalog.rules.find((rule) => rule.status === "active" && rule.id !== getEffectiveHostedRuleId(candidate));
    if (!relatedRule) throw new Error("Relationship progress fixture requires an active related Hosted rule");
    return {
      candidate, relatedRule, comparisonCandidates: state.assessedCandidates, candidateKey: candidate.key, originalAction: getDecision(candidate).action,
      relatedCandidateKeys: state.assessedCandidates.filter((item) => (item.catalogMapping.hostedRuleId || item.recommendation.hostedId) === relatedRule.id).map((item) => item.key)
    };
  });
  assert(await progress.isHidden(), "Relationship progress is visible before a check starts");

  let receiveRoute;
  let relationshipRequestCount = 0;
  await page.route("**/reconcile-rule", (route) => {
    relationshipRequestCount += 1;
    receiveRoute(route);
  });
  const beginCheck = async () => {
    const routePromise = new Promise((resolve) => { receiveRoute = resolve; });
    await save.click();
    await progress.waitFor({ state: "visible" });
    assert(await save.isDisabled(), "Proposed rule save remains enabled during a relationship check");
    return routePromise;
  };
  const waitForCompletion = async () => {
    await progress.waitFor({ state: "hidden" });
    return page.evaluate((candidateKey) => ({
      status: state.session.manualRelationshipChecks[candidateKey]?.status,
      active: activeRelationshipChecks.has(candidateKey),
      action: getDecision(getActiveCandidate()).action
    }), setup.candidateKey);
  };
  const waitForSavedWording = async (text) => page.waitForFunction(({ candidateKey, proposedText }) => (
    getDecision(state.candidates.find((candidate) => candidate.key === candidateKey)).proposedText === proposedText
    && document.querySelector("[data-proposed-text-save]").disabled
  ), { candidateKey: setup.candidateKey, proposedText: text });
  const result = (route, grouped = false) => createSavedRuleEvaluation(route, { ...setup, grouped });

  const checkedText = `${originalText} Maintainer wording.`;
  await editor.fill(checkedText);
  const successRoute = await beginCheck();
  await statusPanel.locator("[aria-hidden='true'].waiting-panel-border").waitFor({ state: "visible" });
  assert(await statusPanel.getAttribute("role") === "status" && await statusPanel.getAttribute("aria-live") === "polite" && await statusPanel.getAttribute("aria-atomic") === "true", "Relationship progress does not expose a polite atomic live status");
  assert(await progress.locator(".waiting-panel-spinner").getAttribute("aria-hidden") === "true" && await progress.locator(".waiting-panel-border").getAttribute("aria-hidden") === "true" && await progress.locator(".waiting-panel-glow").getAttribute("aria-hidden") === "true", "Decorative relationship animations are exposed to assistive technology");
  assert((await progress.textContent()).includes("Checking rule relationships..."), "Relationship progress does not describe the active work");
  const elapsed = progress.locator(".waiting-panel-elapsed");
  assert(/^\[Elapsed: \d{2}:\d{2}:\d{2}\]$/.test(await elapsed.textContent()), "Elapsed time does not use HH:MM:SS");
  assert(await elapsed.getAttribute("role") === "timer" && await elapsed.getAttribute("aria-live") === "off", "Elapsed time repeatedly announces live status");
  const firstElapsed = await elapsed.textContent();
  await page.waitForFunction((previous) => document.querySelector(".manual-relationship-progress .waiting-panel-elapsed").textContent !== previous, firstElapsed);
  const viewport = page.viewportSize();
  await page.locator("#promotion-plan-stage").click();
  const pendingPill = page.locator(`[data-plan-detail="${setup.candidateKey}"]`);
  assert(await pendingPill.locator(":scope > span").textContent() === "Checking"
    && (await pendingPill.getAttribute("aria-label")).includes("Checking rule relationships")
    && (await pendingPill.getAttribute("data-workbench-tooltip")).includes("Checking rule relationships"),
  "Pending Plan readiness does not retain compact text and full accessible validation context");
  assert(await pendingPill.locator("use").getAttribute("href") === "icons/codicons/sprite.svg#codicon-search",
    "Pending Plan readiness does not use the search icon");
  for (const width of [1920, 1180, 768]) {
    await page.setViewportSize({ width, height: 900 });
    const geometry = await pendingPill.evaluate((button) => {
      const cell = button.closest("td"), controls = cell.nextElementSibling;
      const b = button.getBoundingClientRect(), c = cell.getBoundingClientRect(), next = controls.getBoundingClientRect();
      const icons = [button.querySelector("svg"), controls.querySelector("svg")];
      return {
        contained: b.left >= c.left && b.right <= next.left && b.bottom <= c.bottom,
        iconsVisible: icons.every((svg) => {
          const bounds = svg.getBBox(), rect = svg.getBoundingClientRect();
          return bounds.width > 0 && bounds.height > 0 && rect.width > 0 && rect.height > 0;
        })
      };
    });
    assert(geometry.contained && geometry.iconsVisible, `Pending Plan controls are invisible or overlap at ${width}px: ${JSON.stringify(geometry)}`);
  }
  await page.setViewportSize(viewport);
  await pendingPill.click();
  await progress.waitFor({ state: "visible" });
  await page.waitForFunction(() => document.activeElement?.hasAttribute("data-manual-relationship-progress"));
  assert(relationshipRequestCount === 1 && await page.evaluate(() => activeRelationshipChecks.size === 1),
    "Plan progress navigation restarted or duplicated validation");
  for (const width of [1180, 768]) {
    await page.setViewportSize({ width, height: 900 });
    const layout = await statusPanel.evaluate((panel) => {
      const button = panel.querySelector("[data-cancel-relationship-check]");
      const body = panel.querySelector(".waiting-panel-body");
      const timer = panel.querySelector(".waiting-panel-elapsed");
      const p = panel.getBoundingClientRect(), b = button.getBoundingClientRect();
      const style = getComputedStyle(panel), buttonStyle = getComputedStyle(button);
      return {
        transparent: style.backgroundColor === "rgba(0, 0, 0, 0)" && style.backgroundImage === "none",
        compact: Math.abs(b.height - 28) < 1 && Math.abs(b.width - 28) < 1 && parseFloat(buttonStyle.paddingLeft) === 0 && parseFloat(buttonStyle.paddingRight) === 0,
        nativeIcon: button.classList.contains("titlebar-icon") && button.getAttribute("aria-label") === "Cancel relationship check"
          && button.querySelector("use")?.getAttribute("href") === "icons/codicons/sprite.svg#codicon-stop-circle"
          && button.querySelector("svg").getBoundingClientRect().width === 16 && button.querySelector("use").getBBox().width > 0,
        timerWithText: timer.parentElement.classList.contains("waiting-panel-copy"),
        fits: b.right <= p.right && b.bottom <= p.bottom && body.scrollWidth <= body.clientWidth + 1
          && document.documentElement.scrollWidth === document.documentElement.clientWidth,
        noInlineStyles: !panel.hasAttribute("style") && !panel.querySelector("[style]")
      };
    });
    assert(Object.values(layout).every(Boolean), `Waiting control differs from the approved layout at ${width}px: ${JSON.stringify(layout)}`);
  }
  await page.setViewportSize(viewport);
  await progress.locator("[data-cancel-relationship-check]").hover();
  assert(await progress.locator("[data-cancel-relationship-check]").evaluate((button) => getComputedStyle(button).backgroundColor === "rgba(255, 255, 255, 0.06)"), "Stop control does not use the shared titlebar hover treatment");
  const motion = await progress.evaluate((element) => ({
    spinner: getComputedStyle(element.querySelector(".waiting-panel-spinner")).animationName,
    border: getComputedStyle(element.querySelector(".waiting-panel")).animationName,
    running: element.getAnimations({ subtree: true }).filter((animation) => animation.playState === "running").length,
    characterCount: element.querySelectorAll(".shimmer-character").length,
    height: element.getBoundingClientRect().height
  }));
  assert(motion.spinner === "waiting-panel-spin" && motion.border === "waiting-panel-chase" && motion.running === motion.characterCount + 2 && motion.characterCount > 0 && motion.height > 0, "Relationship progress animations are not running visibly");
  await playback.runBrowserZoom(baseUrl, { width: 1920, height: 900 }, async (zoomPage, setZoom) => {
    await openWorkbench(zoomPage, baseUrl);
    await verifyWaitingPanels(zoomPage, assert, setZoom);
  });

  const chase = await progress.evaluate((element) => {
    const canvas = document.createElement("canvas");
    canvas.width = canvas.height = 1;
    const context = canvas.getContext("2d", { colorSpace: "srgb", willReadFrequently: true });
    if (!context) throw new Error("Character chase color verification requires a canvas context");
    const normalizedColors = new Map();
    const rgb = (color) => {
      if (!normalizedColors.has(color)) {
        context.clearRect(0, 0, 1, 1);
        context.fillStyle = color;
        context.fillRect(0, 0, 1, 1);
        normalizedColors.set(color, [...context.getImageData(0, 0, 1, 1).data].slice(0, 3).join(","));
      }
      return normalizedColors.get(color);
    };
    const verify = (heading, text) => {
      const visual = heading.querySelector(".shimmer-characters");
      const characters = [...visual.children];
      const animations = visual.getAnimations({ subtree: true });
      const segments = [...new Intl.Segmenter(undefined, { granularity: "grapheme" }).segment(text)];
      const steps = segments.length + 7;
      const duration = parseFloat(getComputedStyle(characters[0]).animationDuration) * 1000;
      const probe = document.createElement("span");
      probe.hidden = true;
      heading.appendChild(probe);
      const palette = Object.fromEntries(["base", "soft", "bright", "peak"].map((name) => {
        probe.style.color = `var(--shimmer-${name}-color)`;
        return [name, rgb(getComputedStyle(probe).color)];
      }));
      probe.remove();
      const band = [palette.soft, palette.bright, palette.peak, palette.peak, palette.peak, palette.bright, palette.soft];
      let mismatch = null;
      let samples = 0;
      try {
        animations.forEach((animation) => animation.pause());
        for (let tick = 0; tick < steps * 2 && !mismatch; tick += 1) {
          for (const fraction of [0.25, 0.75]) {
            animations.forEach((animation) => { animation.currentTime = (tick + fraction) * duration / steps; });
            const colors = characters.map((character) => rgb(getComputedStyle(character).color));
            const expected = characters.map((character, index) => tick < index ? palette.base : band[(tick - index) % steps] || palette.base);
            samples += 1;
            if (JSON.stringify(colors) !== JSON.stringify(expected)) {
              mismatch = { tick, fraction, colors, expected };
              break;
            }
          }
        }
      } finally {
        animations.forEach((animation) => animation.play());
      }
      return {
        textPreserved: heading.querySelector(".sr-only").textContent === text && visual.textContent === text,
        decorative: visual.getAttribute("aria-hidden") === "true",
        graphemesPreserved: characters.length === segments.length && characters.every((character, index) => character.textContent === segments[index].segment),
        noInlineStyles: !heading.hasAttribute("style") && characters.every((character) => !character.hasAttribute("style")),
        animationCount: animations.length,
        characterCount: characters.length,
        palette,
        duration,
        samples,
        mismatch
      };
    };
    const heading = element.querySelector(".shimmer-heading");
    const text = heading.querySelector(".sr-only").textContent;
    const ruleCount = shimmerHeadingStyleSheet.cssRules.length;
    renderShimmerHeading(text);
    const reusesKeyframes = shimmerHeadingStyleSheet.cssRules.length === ruleCount;
    const scenarios = [verify(heading, text)];
    const fixture = document.createElement("div");
    fixture.style.position = "absolute";
    fixture.style.visibility = "hidden";
    document.body.appendChild(fixture);
    try {
      for (const label of ["Loading...", "Loading <b>&</b> e\u0301 \u{1f469}\u200d\u{1f4bb}..."]) {
        fixture.innerHTML = renderShimmerHeading(label);
        scenarios.push(verify(fixture.querySelector(".shimmer-heading"), label));
      }
    } finally {
      fixture.remove();
    }
    return { reusesKeyframes, scenarios };
  });
  assert(chase.reusesKeyframes, "Details rerenders allocate duplicate character chase keyframes");
  for (const scenario of chase.scenarios) {
    assert(scenario.textPreserved && scenario.decorative && scenario.graphemesPreserved && scenario.noInlineStyles, `Character chase does not preserve accessible, escaped graphemes under the existing content policy: ${JSON.stringify(scenario)}`);
    assert(scenario.duration === 1100 && scenario.animationCount === scenario.characterCount && scenario.samples > 0 && !scenario.mismatch, `The rendered seven-character palette or timing is incorrect: ${JSON.stringify(scenario)}`);
    assert(scenario.palette.base === "140,140,140" && scenario.palette.soft === "178,178,178" && scenario.palette.bright === "216,216,216" && scenario.palette.peak === "255,255,255", `The character chase does not use the accepted muted-gray palette: ${JSON.stringify(scenario.palette)}`);
  }

  const elapsedStart = await page.evaluate(() => activeRelationshipChecks.get(getActiveCandidate().key).startedAt);
  await page.evaluate(() => renderAssessment());
  assert(await page.evaluate((startedAt) => activeRelationshipChecks.get(getActiveCandidate().key).startedAt === startedAt, elapsedStart), "Details rerender restarted the elapsed clock");
  assert(await progress.isVisible() && await progress.count() === 1, "Details rerender lost or duplicated the running relationship progress");
  await page.emulateMedia({ reducedMotion: "reduce" });
  const reducedMotion = await progress.evaluate((element) => ({
    spinner: getComputedStyle(element.querySelector(".waiting-panel-spinner")).animationName,
    border: getComputedStyle(element.querySelector(".waiting-panel")).animationName,
    charactersStatic: [...element.querySelectorAll(".shimmer-character")].every((character) => getComputedStyle(character).animationName === "none" && getComputedStyle(character).color === getComputedStyle(element.querySelector(".shimmer-heading")).color)
  }));
  assert(await progress.isVisible() && reducedMotion.spinner === "none" && reducedMotion.border === "none" && reducedMotion.charactersStatic, "Reduced motion hides the status or leaves its animations running");
  await page.emulateMedia({ reducedMotion: "no-preference" });

  await successRoute.fulfill({
    json: result(successRoute, true)
  });
  const success = await waitForCompletion();
  assert(success.status === "current" && !success.active, "Successful relationship check did not complete");
  assert(await page.locator("#assessment-panel .manual-relationship-reviews .rule-issue-comparison").count() === 1, "Successful check lost the grouped adjudication");
  const sharedResult = await page.evaluate(() => {
    const candidate = getActiveCandidate();
    const issue = getOpenRuleIssues().find((item) => item.candidateKeys.includes(candidate.key));
    const expected = document.createElement("div");
    if (issue) expected.innerHTML = renderRuleIssueContent(issue, { candidateDetails: true, proposedText: getDecision(candidate).proposedText });
    return Boolean(issue && elements["assessment-panel"].querySelector(".manual-relationship-reviews").innerHTML === expected.innerHTML);
  });
  assert(sharedResult, "Details did not use the shared compact relationship presentation");
  assert(!await page.locator(".manual-relationship-reviews .rule-issue-assessment, .manual-relationship-reviews .rule-issue-suggestion").count()
    && await page.locator(".manual-relationship-reviews .rule-issue-recommendation > .information-panel").count() === 1,
    "Compact Details retained redundant assessment or suggested wording, or lost the shared recommendation panel");
  assert(await page.locator(".relationship-check-status").evaluate(node => node.tagName === "SPAN" && !node.hasAttribute("tabindex") && !node.hasAttribute("data-maintainer-resolution-jump")),
    "Relationship status remained an interactive navigation control");
  assert(await page.locator("[data-relationship-review-actions]").evaluate(node => node.previousElementSibling.querySelector('[data-decision-field="proposedText"]') !== null
    && node.nextElementSibling.matches("[data-maintainer-resolution]"))
    && await page.locator("[data-maintainer-resolution-jump]").textContent().then(text => text.trim()) === "Review Relationships",
    "Relationship review is not an explicit action directly after the proposed editor");
  const preview = await page.locator(".rule-issue-resolution-preview").evaluate(node => {
    const candidate = getActiveCandidate();
    const issue = getOpenRuleIssues().find(item => item.candidateKeys.includes(candidate.key));
    const file = createPreviewFile("", "Resolution wording", getDecision(candidate).proposedText.split("\n"), issue.wording.text.split("\n"));
    return {
      exactRows: node.querySelectorAll(".preview-split-row").length === file.rows.length,
      exactCounts: node.querySelector(".preview-change-summary").getAttribute("aria-label") === `${file.additions} additions and ${file.deletions} deletions`,
      readOnly: !node.querySelector("input,textarea,button"),
      noNestedScroll: getComputedStyle(node.querySelector(".preview-contextual-diff")).overflowY !== "auto"
    };
  });
  assert(Object.values(preview).every(Boolean), `Resolution preview lost its exact, read-only shared diff: ${JSON.stringify(preview)}`);
  const outerScroll = await page.locator(".app-shell").evaluate((node) => node.scrollTop);
  await page.locator("[data-maintainer-resolution-jump]").focus();
  await page.locator("[data-maintainer-resolution-jump]").press("Enter");
  assert(await page.locator("#maintainer-resolution-heading").evaluate((node) => document.activeElement === node && node.tabIndex === -1
    && getComputedStyle(node).outlineStyle === "none")
    && await page.locator(".app-shell").evaluate((node) => node.scrollTop) === outerScroll,
    "Review action keyboard navigation did not focus the resolution heading without scrolling the outer shell");
  assert(await page.evaluate(() => {
    const issue = getOpenRuleIssues().find((item) => item.candidateKeys.includes(getActiveCandidate().key));
    const content = document.createElement("div");
    content.innerHTML = renderRuleIssueContent(issue);
    return Boolean(content.querySelector(".rule-issue-assessment") && content.querySelector(".rule-issue-suggestion"));
  }), "The scoped Details presentation removed evidence from the global Rule Issues renderer");
  assert(await page.locator("[data-manual-relationship-mode], [data-manual-relationship-resolve]").count() === 0, "Save exposed independent consolidation or retirement controls");
  assert(success.action === setup.originalAction, "Relationship progress changed the staged rule action");

  await editor.fill(`${originalText} Unsaved wording.`);
  assert(await page.locator(".manual-relationship-reviews").count() === 0, "Editing checked wording retained stale relationship resolution controls");
  assert(await page.locator(".relationship-check-status").textContent() === "Relationship check required", "Edited wording retained the previous relationship status");
  await editor.fill(checkedText);
  assert(await page.locator("#assessment-panel .rule-issue-comparison").count() === 1 && await save.isDisabled(), "Returning to saved checked wording did not restore its grouped review");

  await editor.fill(originalText);
  assert(await page.locator(".relationship-check-status").textContent() === "Relationship check required", "Restored original wording bypassed saved-edit adjudication");
  assert(await page.locator(".manual-relationship-reviews").count() === 0, "Original wording retained obsolete resolution-required panels");
  const originalRoute = await beginCheck();
  await originalRoute.fulfill({ json: result(originalRoute) });
  await waitForCompletion();
  await waitForSavedWording(originalText);
  assert(await save.isDisabled(), "Saving original wording left the unchanged save control enabled");
  const originalState = await page.evaluate((candidateKey) => {
    const candidate = state.candidates.find((item) => item.key === candidateKey);
    return {
      requiresCheck: requiresManualRelationshipCheck(candidate),
      action: getDecision(candidate).action,
      active: activeRelationshipChecks.has(candidateKey)
    };
  }, setup.candidateKey);
  assert(!originalState.requiresCheck && !originalState.active && originalState.action === setup.originalAction, "Restored original wording did not finish a current adjudication without changing the rule action");
  assert(relationshipRequestCount === 2, "Restoring original wording did not run its explicit Save pipeline");
  await page.evaluate(() => renderAssessment());
  assert(await page.locator(".manual-relationship-reviews").count() === 0 && await page.locator(".relationship-check-status").textContent() === "Relationships resolved", "Details rerender restored obsolete relationship panels for original wording");

  await editor.fill(checkedText);
  assert(await save.isEnabled() && await page.locator(".manual-relationship-reviews").count() === 0, "Unsaved cached wording exposed actionable relationship reviews");
  const restoredRoute = await beginCheck();
  await restoredRoute.fulfill({ json: result(restoredRoute, true) });
  await waitForCompletion();
  await waitForSavedWording(checkedText);
  assert(await page.locator("#assessment-panel .rule-issue-comparison").count() === 1, "Saving restored checked wording did not restore its grouped review");
  assert(await page.locator("#assessment-panel [data-rule-issue-plan]").count() === 1, "Grouped review lost its shared recommended action");
  assert(relationshipRequestCount === 3 && await progress.isHidden(), "Restoring prior wording did not finish the source-bound pipeline");

  await editor.fill(`${originalText} Revised maintainer wording.`);
  assert(await page.locator(".manual-relationship-reviews").count() === 0, "Editing cached checked wording retained stale relationship panels");
  const failureRoute = await beginCheck();
  await failureRoute.fulfill({ status: 503, json: { error: "Synthetic relationship evaluator failure" } });
  const failure = await waitForCompletion();
  assert(failure.status === "failed" && !failure.active, "Failed relationship check left the job running");
  assert(await page.locator(".manual-relationship-reviews").count() === 0, "Failed relationship check restored stale resolution controls");
  assert(await page.locator("[data-manual-relationship-failure] .error-banner-message > span").textContent() === "Synthetic relationship evaluator failure", "Failed relationship check did not expose the evaluator diagnostic in its persistent inline error");
  assert(await page.getByRole("button", { name: "Retry proposed Hosted rule relationship check", exact: true }).isEnabled(), "Failed relationship check lost its retry control");

  const retryRoute = await beginCheck();
  await retryRoute.fulfill({ json: result(retryRoute) });
  const retry = await waitForCompletion();
  assert(retry.status === "current" && !retry.active, "Retried relationship check did not finish");
  assert(await page.locator(".relationship-check-status").textContent() === "Relationships resolved", "Empty successful retry did not show resolved relationships");
  assert(await page.locator(".manual-relationship-review").count() === 0, "Successful retry retained obsolete relationship reviews");
  assert(await save.isDisabled(), "Successful retry left unchanged proposed wording save enabled");

  await editor.fill(`${originalText} Stale response wording.`);
  const lateRoute = await beginCheck();
  await editor.fill(`${originalText} Newer unsaved wording.`);
  await lateRoute.fulfill({ json: result(lateRoute, true) });
  const late = await waitForCompletion();
  assert(late.status === "failed" && await page.locator(".manual-relationship-reviews").count() === 0, "A late result overwrote the newer editor context");
  assert((await editor.inputValue()).endsWith("Newer unsaved wording."), "Late result overwrote the editor text");

  const mismatchRoute = await beginCheck();
  const mismatch = result(mismatchRoute);
  mismatch.ruleTextSha256 = "0".repeat(64);
  await mismatchRoute.fulfill({ json: mismatch });
  const rejected = await waitForCompletion();
  assert(rejected.status === "failed", "An incorrect text hash was accepted as current adjudication");

  const evaluationCount = await page.evaluate(() => state.session.savedRuleEvaluations.length);
  const cancelledText = `${originalText} Cancelled check wording.`;
  await editor.fill(cancelledText);
  const cancelledRoute = await beginCheck();
  await page.evaluate(() => { globalThis.__cancelledCheck = activeRelationshipChecks.get(getActiveCandidate().key); });
  await progress.locator("[data-cancel-relationship-check]").click();
  await waitForCompletion();
  assert(await page.evaluate(() => globalThis.__cancelledCheck.controller.signal.aborted), "Cancel did not abort the active transport");
  await cancelledRoute.fulfill({ json: result(cancelledRoute) });
  const cancelled = await page.evaluate(() => {
    const candidate = getActiveCandidate();
    const check = getManualRelationshipCheck(candidate);
    delete globalThis.__cancelledCheck;
    return { text: getDecision(candidate).proposedText, required: requiresManualRelationshipCheck(candidate),
      failed: check?.status === "failed", count: state.session.savedRuleEvaluations.length };
  });
  assert(cancelled.text === cancelledText && cancelled.required && !cancelled.failed && cancelled.count === evaluationCount,
    `Cancellation lost wording, accepted a late result, or manufactured an evaluation failure: ${JSON.stringify(cancelled)}`);
  assert(await save.isEnabled() && await progress.isHidden(), "Cancellation did not clear progress and leave rechecking available");
  await openWorkbench(page, baseUrl);
  await page.evaluate((key) => { selectCandidate(key); showCandidatePane("details"); }, setup.candidateKey);
  assert(await editor.inputValue() === cancelledText && await save.isEnabled() && await progress.isHidden(), "Cancelled wording or retry state was not preserved after reload");

  const codeOwnerIdentity = await page.evaluate(() => getValidatedCodeOwnerIdentity());
  assert(Boolean(codeOwnerIdentity), "Bulk Undo validation requires the normal authenticated maintainer fixture");
  await page.route("**/runtime-config", async (route) => {
    const response = await route.fetch();
    await route.fulfill({ response, json: { ...(await response.json()), maintainerIdentity: codeOwnerIdentity } });
  });
  const warningCandidate = await page.evaluate(({ candidateKey, relatedRuleId }) => {
    const candidate = state.assessedCandidates.find((item) => !getDecision(item).inPlan
      && item.catalogMapping.state === "active"
      && ![getEffectiveHostedRuleId(state.candidates.find((item) => item.key === candidateKey)), relatedRuleId].includes(getEffectiveHostedRuleId(item)));
    if (!candidate) throw new Error("Undo validation fixtures require a separate mapped candidate");
    updateDecision(candidate, {
      action: "update",
      proposedText: `${candidate.recommendation.ruleText} Separate wording needing review.`
    });
    selectCandidate(candidate.key);
    showCandidatePane("details");
    return candidate;
  }, { candidateKey: setup.candidateKey, relatedRuleId: setup.relatedRule.id });
  const warningText = `${warningCandidate.recommendation.ruleText} Separate wording needing review.`;
  await editor.fill(warningText);
  const warningRoute = await beginCheck();
  await warningRoute.fulfill({ json: createSavedRuleEvaluation(warningRoute, {
    candidate: warningCandidate,
    comparisonCandidates: setup.comparisonCandidates,
    scopeReview: {
      disposition: "uncertain", ownerRuleId: null,
      baselineQuote: warningCandidate.recommendation.ruleText, proposalQuote: warningText,
      rationale: "Review the scope of this separate candidate.",
      wordingStatus: "acceptable", wordingRationale: "The separate wording expresses an enforceable obligation."
    }
  }) });
  await page.waitForFunction((key) => !activeRelationshipChecks.has(key), warningCandidate.key);
  const warningState = await page.evaluate((key) => ({
    status: state.session.manualRelationshipChecks[key]?.status,
    error: state.session.manualRelationshipChecks[key]?.errorMessage,
    attention: getRuleValidationAttention(state.candidates.find((item) => item.key === key))?.reason
  }), warningCandidate.key);
  assert(warningState.status === "current" && warningState.attention === "wording",
    `Separate warning fixture did not complete real validation: ${JSON.stringify(warningState)}`);
  const warningSnapshot = await page.evaluate((key) => JSON.stringify({
    decision: state.session.decisions[key],
    check: state.session.manualRelationshipChecks[key]
  }), warningCandidate.key);

  for (const undo of ["row", "manual", "bulk", "all", "bulk-operation"]) {
    await page.evaluate(async ({ key, originalAction, text, undo }) => {
      const candidate = state.candidates.find((item) => item.key === key);
      const bulk = ["bulk", "bulk-operation"].includes(undo);
      const operationId = bulk ? crypto.randomUUID() : null;
      if (bulk) state.session.bulkOperations.push({
        id: operationId, createdAt: toUtcTimestamp(), action: originalAction, candidateKeys: [key]
      });
      saveDecision(candidate, {
        ...getDecision(candidate), action: originalAction,
        proposedText: text, rationale: "Validate this saved draft before promotion.",
        ...createPlanMembership(bulk ? "bulk" : "manual", operationId)
      });
      await persistencePromise;
      switchView("catalog");
      setWorkspaceTab("candidate-sources");
      selectCandidate(key);
      showCandidatePane("details");
    }, { key: setup.candidateKey, originalAction: setup.originalAction, text: `${originalText} Undo ${undo} check.`, undo });
    const undoRoute = await beginCheck();
    await page.evaluate((key) => { globalThis.__undoCheck = activeRelationshipChecks.get(key); }, setup.candidateKey);
    try {
      if (undo === "row") {
        await page.evaluate((requestId) => {
          const original = validateSavedRuleEvaluation;
          globalThis.__undoValidationRace = { original, waiting: false, finished: false };
          validateSavedRuleEvaluation = async (...args) => {
            await original(...args);
            if (args[1].requestId !== requestId) return;
            globalThis.__undoValidationRace.waiting = true;
            await new Promise((resolve) => { globalThis.__undoValidationRace.release = resolve; });
            globalThis.__undoValidationRace.finished = true;
          };
        }, readSavedRuleRequest(undoRoute).requestId);
        await undoRoute.fulfill({ json: result(undoRoute) });
        await page.waitForFunction(() => globalThis.__undoValidationRace.waiting);
      }
      await page.locator("#promotion-plan-stage").click();
      const undoButton = page.locator(`[data-plan-undo="${setup.candidateKey}"]`);
      assert(await undoButton.isEnabled()
        && await undoButton.getAttribute("aria-label") === "Cancel validation and undo this candidate"
        && await undoButton.getAttribute("data-workbench-tooltip") === "Cancel validation and undo this candidate"
        && await undoButton.locator("use").getAttribute("href") === "icons/codicons/sprite.svg#codicon-discard",
      `${undo}: running validation changed or disabled the Undo action`);
      if (undo === "row") await undoButton.click();
      else if (undo === "bulk-operation") await page.evaluate(() => undoBulkOperation(getLatestBulkOperation().id));
      else {
        await page.locator("#plan-undo-trigger").click();
        await page.locator(`[data-plan-undo-scope="${undo}"]`).click();
      }
      await page.evaluate(() => persistencePromise);
      await page.waitForFunction((key) => !state.session.decisions[key] && !activeRelationshipChecks.has(key), setup.candidateKey);
      const reset = await page.evaluate(({ key, warningKey }) => {
        const candidate = state.candidates.find((item) => item.key === key);
        const warning = state.candidates.find((item) => item.key === warningKey);
        return {
          aborted: globalThis.__undoCheck.controller.signal.aborted,
          originalText: getDecision(candidate).proposedText,
          metadataCleared: !state.session.manualRelationshipChecks[key]
            && !state.session.savedRuleEvaluations.some((evaluation) => evaluation.candidateKey === key),
          warning: JSON.stringify({ decision: state.session.decisions[warningKey], check: state.session.manualRelationshipChecks[warningKey] }),
          warningVisible: getCandidateDecoration(warning)?.status === "needs-input"
            && getValidationProblems().some((problem) => problem.candidateKey === warningKey)
            && getRuleValidationAttention(warning)?.reason === "wording"
        };
      }, { key: setup.candidateKey, warningKey: warningCandidate.key });
      assert(reset.aborted && reset.originalText === originalText && reset.metadataCleared,
        `${undo}: Undo did not cancel and completely reset its own saved draft: ${JSON.stringify(reset)}`);
      assert(reset.warning === warningSnapshot && reset.warningVisible,
        `${undo}: Undo cleared another candidate's saved warning or decoration: ${JSON.stringify({ metadataPreserved: reset.warning === warningSnapshot, warningVisible: reset.warningVisible })}`);
      assert(await page.locator(`[data-plan-row="${setup.candidateKey}"]`).count() === 0, `${undo}: Undo retained its Plan row`);

      if (undo === "row") {
        await page.evaluate(({ key, proposedText, action }) => {
          updateDecision(state.candidates.find((item) => item.key === key), { action, proposedText });
          switchView("catalog");
          setWorkspaceTab("candidate-sources");
          selectCandidate(key);
          showCandidatePane("details");
        }, { key: setup.candidateKey, proposedText: `${originalText} Replacement check after Undo.`, action: setup.originalAction });
        await editor.fill(`${originalText} Replacement check after Undo.`);
        const replacementRoute = await beginCheck();
        await page.evaluate((key) => {
          globalThis.__replacementCheck = activeRelationshipChecks.get(key);
          validateSavedRuleEvaluation = globalThis.__undoValidationRace.original;
          globalThis.__undoValidationRace.release();
        }, setup.candidateKey);
        await page.waitForFunction(() => globalThis.__undoValidationRace.finished);
        const replacement = await page.evaluate((key) => ({
          stillActive: activeRelationshipChecks.get(key) === globalThis.__replacementCheck,
          notAborted: !globalThis.__replacementCheck.controller.signal.aborted,
          stillPending: state.session.manualRelationshipChecks[key]?.status === "pending",
          noDiscardedResult: !state.session.savedRuleEvaluations.some((evaluation) => evaluation.candidateKey === key)
        }), setup.candidateKey);
        assert(Object.values(replacement).every(Boolean), `Discarded validation overwrote or removed its replacement: ${JSON.stringify(replacement)}`);
        assert(await progress.isVisible() && await save.isDisabled(), "Discarded validation hid replacement progress or enabled a duplicate request");
        await replacementRoute.fulfill({ json: result(replacementRoute) });
        const completed = await waitForCompletion();
        assert(completed.status === "current" && !completed.active, "A replacement validation could not complete after Undo");
        await page.locator("#promotion-plan-stage").click();
        assert(await page.locator(`[data-plan-undo="${setup.candidateKey}"]`).count() === 0, "Replacement validation silently re-added the reset candidate to the Plan");
        await page.evaluate(async (key) => { await resetCandidate(state.candidates.find((item) => item.key === key)); }, setup.candidateKey);
      } else {
        await undoRoute.fulfill({ json: result(undoRoute) });
      }
      await page.evaluate(() => persistencePromise);
      assert(await page.evaluate((key) => !state.session.decisions[key]
        && !state.session.manualRelationshipChecks[key]
        && !state.session.savedRuleEvaluations.some((evaluation) => evaluation.candidateKey === key), setup.candidateKey),
      `${undo}: a late cancellation or result restored discarded draft state`);
    } finally {
      await page.evaluate(() => {
        if (globalThis.__undoValidationRace) {
          validateSavedRuleEvaluation = globalThis.__undoValidationRace.original;
          globalThis.__undoValidationRace.release?.();
          delete globalThis.__undoValidationRace;
        }
        delete globalThis.__undoCheck;
        delete globalThis.__replacementCheck;
      });
    }
  }
  await openWorkbench(page, baseUrl);
  assert(await page.evaluate(({ key, warningKey, warningSnapshot }) => !state.session.decisions[key]
    && !state.session.manualRelationshipChecks[key]
    && JSON.stringify({ decision: state.session.decisions[warningKey], check: state.session.manualRelationshipChecks[warningKey] }) === warningSnapshot,
  { key: setup.candidateKey, warningKey: warningCandidate.key, warningSnapshot }), "Reload restored an undone draft or lost another candidate's warning");
}

module.exports = { name: "relationship check progress", behaviorIds, viewport: { width: 1180, height: 900 }, run };
