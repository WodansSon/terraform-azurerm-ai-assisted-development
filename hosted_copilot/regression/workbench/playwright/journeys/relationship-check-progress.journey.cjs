const { openWorkbench } = require("../helpers/workbench.cjs");
const { createSavedRuleEvaluation } = require("../helpers/saved-rule-evaluation.cjs");

const behaviorIds = ["WB-UX-RELATIONSHIP-001", "WB-UX-RELATIONSHIP-002", "WB-UX-RELATIONSHIP-003", "WB-UX-RELATIONSHIP-004"];

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
              const positions = getComputedStyle(frame, "::before").maskPosition.split(",").map((position) => position.trim().split(/\s+/).map(parseFloat));
              const distance = (phase % 1) * length;
              const expected = [[distance, 0], [width - band, distance - width], [-height - distance, height - band], [0, -distance]];
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
    const relatedRule = state.bundle.catalog.rules.find((rule) => rule.status === "active" && rule.id !== getEffectiveHostedRuleId(candidate));
    if (!relatedRule) throw new Error("Relationship progress fixture requires an active related Hosted rule");
    return {
      candidate, relatedRule, candidateKey: candidate.key, originalAction: getDecision(candidate).action,
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

  await page.evaluate(() => renderAssessment());
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
    if (issue) expected.innerHTML = renderRuleIssueContent(issue);
    return Boolean(issue && elements["assessment-panel"].querySelector(".manual-relationship-reviews").innerHTML === expected.innerHTML);
  });
  assert(sharedResult, "Details did not render the exact shared Rule Issues content");
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
  assert(await page.getByText("Relationship check failed with 503", { exact: true }).isVisible(), "Failed relationship check did not expose its error");
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
}

module.exports = { name: "relationship check progress", behaviorIds, viewport: { width: 1180, height: 900 }, run };
