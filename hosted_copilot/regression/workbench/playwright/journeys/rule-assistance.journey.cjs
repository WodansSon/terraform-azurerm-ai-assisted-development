const { openWorkbench, getCssTokenColor } = require("../helpers/workbench.cjs");
const expectedWaitingPhrases = require("../../../../workbench/assistance-waiting-phrases.json");
const expectedBrandMap = require("../../../../workbench/llm-brands.json");
const expectedNormalProfile = require("../../../../tools/llm.json").normal;

const behaviorIds = ["WB-UX-ASSISTANCE-001"];

async function run({ page, baseUrl, assert }) {
  await openWorkbench(page, baseUrl);
  const startup = await page.evaluate(() => {
    const toggle = document.getElementById("assist-panel-toggle");
    return {
      hidden: document.getElementById("rule-assistance-panel").hidden,
      disabled: toggle.disabled,
      visible: toggle.getBoundingClientRect().width > 0,
      inRow: toggle.parentElement.id === "candidate-assistance-controls",
      outsideTablist: !toggle.closest('[role="tablist"]'),
      outsideHeader: !toggle.closest(".topbar-actions"),
      defaultCursor: getComputedStyle(toggle).cursor === "default"
    };
  });
  assert(startup.hidden && startup.disabled && startup.visible && startup.inRow && startup.outsideTablist && startup.outsideHeader && startup.defaultCursor,
    "Startup must hide empty assistance and retain one disabled command beside the candidate tabs");
  const phrases = await page.evaluate(() => ruleAssistanceWaitingPhrases);
  assert(phrases.length > 0 && new Set(phrases).size === phrases.length
    && JSON.stringify(phrases) === JSON.stringify(expectedWaitingPhrases), "The complete waiting-phrase catalog did not load");
  const invalidCatalogs = await page.evaluate(() => [null, {}, [], [""], [" spaced "], ["two\nlines"], ["same", "same"], [42]].map((value) => {
    try {
      validateRuleAssistanceWaitingPhrases(value);
      return false;
    } catch (error) {
      return error.message.startsWith("Assistance waiting phrases must be");
    }
  }));
  assert(invalidCatalogs.every(Boolean), "Invalid waiting-phrase catalog entries were accepted");
  assert(await page.evaluate(() => JSON.stringify(llmBrandMap)) === JSON.stringify(expectedBrandMap), "The presentation branding map did not load");
  const branding = await page.evaluate(async () => {
    const cases = [["gpt-example", "llm-openai"], ["claude-example", "llm-claude"], ["gemini-example", "llm-gemini"], ["grok-example", "llm-grok"], ["future-example", "codicon-question"]];
    const probe = document.createElement("span");
    probe.className = "assist-chat-profile sr-only";
    document.body.append(probe);
    try {
      const results = [];
      for (const [model, expected] of cases) {
        probe.innerHTML = renderLlmModelIcon(model);
        const glyph = probe.querySelector("svg");
        const deadline = performance.now() + 5000;
        do {
          await new Promise(requestAnimationFrame);
        } while (glyph.querySelector("use").getBBox().width === 0 && performance.now() < deadline);
        results.push({ expected, reference: glyph.querySelector("use").getAttribute("href"), painted: glyph.querySelector("use").getBBox().width > 0, width: glyph.getBoundingClientRect().width, height: glyph.getBoundingClientRect().height });
      }
      return results;
    } finally { probe.remove(); }
  });
  assert(branding.every(result => result.reference.endsWith(`#${result.expected}`) && result.painted && result.width === 12 && result.height === 12), `Mapped brands or the Codicons fallback failed: ${JSON.stringify(branding)}`);
  const invalidBrandMaps = await page.evaluate(() => [null, {}, [], [{ prefix: "gpt-", icon: "../invalid" }], [{ prefix: "gpt-", icon: "openai" }, { prefix: "gpt-", icon: "claude" }], [{ prefix: "gpt-", icon: "openai" }, { prefix: "gpt-6-", icon: "openai" }]].map(value => {
    try { validateLlmBrandMap(value); return false; } catch { return true; }
  }));
  assert(invalidBrandMaps.every(Boolean), "Invalid or ambiguous branding mappings were accepted");
  const contextNotes = await page.evaluate(async () => {
    const session = JSON.stringify(state.session);
    const chat = JSON.stringify(ruleAssistance);
    const message = "Context: <img src=x onerror=alert(1)> remains literal text. Catalog snapshot only; other draft and Plan changes are not included.";
    const probe = document.createElement("div");
    probe.style.cssText = "position:fixed;left:-10000px;top:0;width:240px";
    document.body.append(probe);
    try {
      const notes = [];
      for (const iconName of [undefined, "terminal-compact", "edit-compact"]) {
        probe.innerHTML = renderAssistanceContextNote(message, iconName);
        const note = probe.querySelector(".assist-chat-scope");
        const glyph = note.querySelector("svg");
        const reference = glyph.querySelector("use");
        const deadline = performance.now() + 5000;
        do {
          await new Promise(requestAnimationFrame);
        } while (reference.getBBox().width === 0 && performance.now() < deadline);
        const text = note.querySelector("span");
        const range = document.createRange();
        range.selectNodeContents(text);
        const lines = [...range.getClientRects()];
        const textLeft = text.getBoundingClientRect().left;
        notes.push({
          reference: reference.getAttribute("href"),
          painted: reference.getBBox().width > 0,
          iconFirst: note.firstElementChild === glyph && glyph.nextElementSibling === text,
          decorative: glyph.getAttribute("aria-hidden") === "true",
          escaped: text.textContent === message && !note.querySelector("img"),
          color: getComputedStyle(note).color,
          iconColor: getComputedStyle(glyph).color,
          width: glyph.getBoundingClientRect().width,
          height: glyph.getBoundingClientRect().height,
          gap: textLeft - glyph.getBoundingClientRect().right,
          wrapped: lines.length > 1 && lines.every(line => Math.abs(line.left - textLeft) < 1),
          contained: note.scrollWidth <= note.clientWidth
        });
      }
      let invalidIconRejected = false;
      try { renderAssistanceContextNote(message, 'tools" onload="alert(1)'); } catch { invalidIconRejected = true; }
      return { notes, invalidIconRejected, unchanged: JSON.stringify(state.session) === session && JSON.stringify(ruleAssistance) === chat };
    } finally { probe.remove(); }
  });
  assert(contextNotes.notes.every((note, index) => note.reference === `icons/codicons/sprite.svg#codicon-${["tools", "terminal-compact", "edit-compact"][index]}`
    && note.painted && note.iconFirst && note.decorative), "Context-note helper lost its default, override, painted, or decorative Codicon");
  assert(contextNotes.notes.every(note => note.escaped) && contextNotes.invalidIconRejected && contextNotes.unchanged,
    "Context-note helper accepted markup, accepted an unsafe icon name, or mutated chat or draft state");
  assert(contextNotes.notes.every(note => note.color === "rgb(115, 115, 115)" && note.iconColor === note.color
    && note.width === 14 && note.height === 14 && Math.abs(note.gap - 8) < 1 && note.wrapped && note.contained),
    "Context notes lost their approved muted-gray inline layout, stable icon size, gap, or aligned wrapping");
  const setup = await page.evaluate(() => {
    const candidate = state.candidates.find((item) => getCatalogStatus(item).key === "mapped");
    selectCandidate(candidate.key);
    showCandidatePane("details");
    return { key: candidate.key, ruleId: getEffectiveHostedRuleId(candidate), text: getDecision(candidate).proposedText, session: JSON.stringify(state.session) };
  });
  const root = page.locator("[data-rule-assistance]");
  const input = root.locator(".assist-goal");
  const send = root.locator("[data-assist-send]");
  const clear = root.locator("[data-assist-clear]");
  const editor = page.locator('[data-decision-field="proposedText"]');
  const editorSizing = await editor.evaluate((node) => {
    const originalText = node.value;
    const measure = () => ({
      height: node.getBoundingClientRect().height,
      clientHeight: node.clientHeight,
      scrollHeight: node.scrollHeight,
      overflow: getComputedStyle(node).overflowY
    });
    const container = node.closest(".hosted-rule-comparison");
    const originalWidth = container.style.width;
    try {
      node.value = "";
      const empty = measure();
      node.value = "Keep the existing rule.";
      const short = measure();
      node.value = "Preserve every required obligation, condition, and exception in the proposed Hosted rule. ".repeat(40);
      const long = measure();
      container.style.width = "280px";
      const narrow = measure();
      container.style.width = originalWidth;
      const restoredWidth = measure();
      node.value = "Keep the existing rule.";
      return { empty, short, long, narrow, restoredWidth, shortened: measure() };
    } finally {
      node.value = originalText;
      container.style.width = originalWidth;
    }
  });
  assert(editorSizing.empty.height === 84 && editorSizing.short.height === 84,
    `Empty and short proposed wording lost the 84px minimum: ${JSON.stringify(editorSizing)}`);
  assert(editorSizing.long.height > 84 && editorSizing.long.scrollHeight <= editorSizing.long.clientHeight
    && editorSizing.long.overflow === "hidden", `Long proposed wording did not fit without scrolling: ${JSON.stringify(editorSizing)}`);
  assert(editorSizing.narrow.height > editorSizing.long.height && editorSizing.narrow.scrollHeight <= editorSizing.narrow.clientHeight,
    `Proposed wording did not grow when its container narrowed: ${JSON.stringify(editorSizing)}`);
  assert(editorSizing.restoredWidth.height === editorSizing.long.height && editorSizing.shortened.height === 84,
    `Proposed wording did not shrink back to fit: ${JSON.stringify(editorSizing)}`);
  assert(await page.evaluate(() => JSON.stringify(state.session)) === setup.session,
    "Content sizing changed saved rule decisions");
  await root.scrollIntoViewIfNeeded();
  assert(await page.locator("#assist-panel-toggle").getAttribute("aria-expanded") === "true"
    && await root.locator("[data-assist-body]").isVisible()
    && !await page.locator("#assessment-panel [data-rule-assistance]").count()
    && await page.locator("#candidate-assistance-controls #assist-panel-toggle").isEnabled(), "Selected Candidate Details did not enable its shared sidebar control");
  assert(await clear.isDisabled() && await send.isDisabled(), "Empty chat offers Clear or Send");
  assert(await root.locator(".assist-header > .section-label").textContent() === "AI Assistance:", "Assistance heading changed");
  assert(!await page.locator('#assessment-panel [data-evidence-kind="coverage"]').count(), "Candidate Details retained inferred coverage");
  const expectedBrand = expectedBrandMap.find(entry => expectedNormalProfile.model.toLowerCase().startsWith(entry.prefix));
  const expectedModelIconReference = expectedBrand ? `icons/llms/sprite.svg#llm-${expectedBrand.icon}` : "icons/codicons/sprite.svg#codicon-question";
  await page.waitForFunction(() => document.querySelector(".assist-chat-profile svg use")?.getBBox().width > 0
    && document.querySelector(".assist-chat-identity .codicon use")?.getBBox().width > 0);
  const modelIcon = await root.locator(".assist-chat-profile svg").evaluate((node) => ({
    reference: node.querySelector("use").getAttribute("href"),
    width: node.getBoundingClientRect().width,
    height: node.getBoundingClientRect().height,
    color: getComputedStyle(node).color,
    profileColor: getComputedStyle(node.parentElement).color,
    decorative: node.getAttribute("aria-hidden") === "true"
  }));
  assert(modelIcon.reference === expectedModelIconReference && modelIcon.width === 12 && modelIcon.height === 12
    && modelIcon.color === modelIcon.profileColor && modelIcon.decorative && !await root.locator(".assist-chat-profile img").count(),
  `Configured model branding did not paint from its local sprite: ${JSON.stringify(modelIcon)}`);
  const presentation = await root.evaluate((node) => {
    const heading = node.querySelector(".assist-header");
    const guidance = heading.nextElementSibling.querySelector(":scope > .information-panel");
    const paragraph = guidance.querySelector("p");
    const reference = document.querySelector(".assessment-context.information-panel");
    const sharedPanelStyle = getComputedStyle(reference);
    const guidanceStyle = getComputedStyle(guidance);
    const identity = node.querySelector(".assist-chat-identity");
    const context = node.querySelector(".assist-chat-context");
    const identityStyle = getComputedStyle(identity);
    const contextStyle = getComputedStyle(context);
    const rule = identity.querySelector("em");
    const glyph = identity.querySelector(".codicon");
    const clear = node.querySelector("[data-assist-clear]");
    return {
      guidanceFirst: guidance.matches(".information-panel.section-guidance")
        && guidance.nextElementSibling.matches(".assist-chat-reply-window"),
      guidanceText: paragraph.textContent,
      emphasis: !paragraph.querySelector("strong") && getComputedStyle(paragraph).fontWeight === "400",
      sharedPanel: ["backgroundColor", "borderColor", "borderLeftWidth", "padding", "borderRadius"].every((property) => guidanceStyle[property] === sharedPanelStyle[property])
        && guidanceStyle.marginBottom === "12px"
        && guidance.querySelector(".fluent-icon").getAttribute("aria-hidden") === "true",
      noFooter: !node.querySelector(".assist-chat-note"),
      reference: glyph.querySelector("use").getAttribute("href"),
      glyphSize: glyph.getBoundingClientRect().width === 16 && glyph.getBoundingClientRect().height === 16,
      decorative: glyph.getAttribute("aria-hidden") === "true",
      identityPrefix: identity.querySelector("span").textContent,
      muted: getComputedStyle(glyph).color === contextStyle.color
        && getComputedStyle(identity.querySelector("span")).color === contextStyle.color,
      ruleId: rule.textContent,
      ruleStyle: getComputedStyle(rule).color === "rgb(255, 255, 255)"
        && getComputedStyle(rule).fontStyle === "italic"
        && getComputedStyle(rule).fontSize === "12px"
        && getComputedStyle(identity.querySelector("span")).fontSize === "12px",
      matchingChip: ["borderStyle", "borderColor", "borderWidth", "borderRadius", "padding"].every((property) => identityStyle[property] === contextStyle[property]),
      clearSeparate: clear.parentElement === identity.parentElement
        && clear.getBoundingClientRect().left >= identity.getBoundingClientRect().right,
      transparent: [".assist-chat-reply-window", ".assist-chat-composer", ".assist-goal"].every((selector) => {
        const style = getComputedStyle(node.querySelector(selector));
        return style.backgroundColor === "rgba(0, 0, 0, 0)" && style.backgroundImage === "none";
      })
    };
  });
  assert(presentation.guidanceFirst && presentation.sharedPanel && presentation.noFooter,
    `Assistance guidance did not use the shared information panel beneath its heading: ${JSON.stringify(presentation)}`);
  assert(presentation.guidanceText === "This response is AI-generated. Please review it for accuracy and relevance before use."
    && presentation.emphasis, "Assistance guidance lost its approved wording or regular weight");
  assert(presentation.reference === "icons/codicons/sprite.svg#codicon-copilot" && presentation.glyphSize && presentation.decorative
    && presentation.identityPrefix === "Copilot ·" && presentation.muted, "Copilot identity lost its native glyph or muted prefix");
  assert(presentation.ruleId === setup.ruleId && presentation.ruleStyle && presentation.matchingChip && presentation.clearSeparate,
    `Copilot identity did not match the current-rule chip or displaced Clear: ${JSON.stringify(presentation)}`);
  assert(presentation.transparent, "The assistance reply or composer retained a filled background");
  const geometry = await root.evaluate((node) => {
    const composer = node.querySelector(".assist-chat-composer");
    const reply = node.querySelector(".assist-chat-reply-window");
    const goal = node.querySelector(".assist-goal");
    return {
      sized: composer.getBoundingClientRect().height === 160 && reply.getBoundingClientRect().height > 160
        && Math.abs(reply.getBoundingClientRect().bottom + parseFloat(getComputedStyle(reply).marginBottom) - composer.getBoundingClientRect().top) < 1
        && getComputedStyle(goal).resize === "none",
      scrolling: node.querySelector(".assist-chat-response").classList.contains("scroll-surface")
        && goal.classList.contains("scroll-surface"),
      metadata: getComputedStyle(node.querySelector(".assist-chat-profile")).fontSize === "12px"
        && getComputedStyle(node.querySelector(".assist-chat-context-label")).fontSize === "12px"
        && getComputedStyle(node.querySelector(".assist-chat-context-label")).fontStyle === "italic",
      placeholder: getComputedStyle(goal, "::placeholder").color === "rgb(115, 115, 115)",
      profile: node.querySelector(".assist-chat-profile").textContent,
      runtimeModel: globalThis.__HOSTED_RULE_WORKBENCH__.ruleAssistance.model,
      runtimeEffort: globalThis.__HOSTED_RULE_WORKBENCH__.ruleAssistance.reasoningEffort
    };
  });
  const expectedModelLabel = { "gpt-6.1-sol": "GPT-6.1 Sol", "gpt-5.4": "GPT-5.4" }[expectedNormalProfile.model] || expectedNormalProfile.model;
  const expectedEffortLabel = expectedNormalProfile.reasoningEffort[0].toUpperCase() + expectedNormalProfile.reasoningEffort.slice(1);
  assert(geometry.sized && geometry.scrolling && geometry.metadata && geometry.placeholder
    && geometry.runtimeModel === expectedNormalProfile.model && geometry.runtimeEffort === expectedNormalProfile.reasoningEffort
    && geometry.profile.trim() === `${expectedModelLabel} · ${expectedEffortLabel}`, `Accepted assistance layout or runtime readout changed: ${JSON.stringify(geometry)}`);
  const sidebar = page.locator("#rule-assistance-panel");
  const resizer = page.locator("#assist-sidebar-resizer");
  assert(await resizer.getAttribute("aria-orientation") === "vertical"
    && await resizer.getAttribute("aria-controls") === "rule-assistance-panel"
    && await resizer.getAttribute("aria-valuemin") === "320", "Sidebar resizing lost accessible separator semantics");
  await resizer.evaluate((node) => node.scrollIntoView({ block: "center" }));
  let edge = await resizer.boundingBox();
  await page.mouse.move(edge.x + edge.width / 2, edge.y + edge.height / 2);
  await page.mouse.down();
  await page.mouse.move(edge.x + edge.width / 2 - 64, edge.y + edge.height / 2, { steps: 4 });
  await page.mouse.up();
  assert(await resizer.getAttribute("aria-valuenow") === "484"
    && await sidebar.evaluate((node) => node.getBoundingClientRect().width) === 484
    && await root.locator(".assist-chat-composer").evaluate((node) => node.getBoundingClientRect().height) === 160,
  "Dragging the sidebar divider did not resize the panel without changing the composer");
  await resizer.focus();
  assert(await sidebar.evaluate((node) => getComputedStyle(node).borderLeftColor) === await getCssTokenColor(page, "--accent")
    && await resizer.evaluate(node => getComputedStyle(node).backgroundColor) === "rgba(0, 0, 0, 0)"
    && await sidebar.evaluate(node => parseFloat(getComputedStyle(node).borderLeftWidth) <= 1),
    "The sidebar resize focus filled the grab area instead of highlighting only its thin divider");
  await resizer.evaluate((node) => node.scrollIntoView({ block: "center" }));
  edge = await resizer.boundingBox();
  await page.mouse.move(edge.x + edge.width / 2, edge.y + edge.height / 2);
  await page.mouse.down();
  await page.mouse.move(edge.x + edge.width / 2 - 16, edge.y + edge.height / 2);
  const canceledHeight = await resizer.getAttribute("aria-valuenow");
  await resizer.evaluate((node) => node.dispatchEvent(new PointerEvent("pointercancel", {
    bubbles: true, pointerId: ruleAssistanceSidebarResize.pointerId
  })));
  await page.mouse.move(edge.x + edge.width / 2 - 48, edge.y + edge.height / 2);
  await page.mouse.up();
  assert(await resizer.getAttribute("aria-valuenow") === canceledHeight
    && await page.evaluate(() => !ruleAssistanceSidebarResize),
  "Pointer cancellation left a captured or moving sidebar resize");
  await resizer.evaluate((node) => node.scrollIntoView({ block: "center" }));
  edge = await resizer.boundingBox();
  await page.mouse.move(edge.x + edge.width / 2, edge.y + edge.height / 2);
  await page.mouse.down();
  await page.mouse.move(edge.x + edge.width / 2 - 8, edge.y + edge.height / 2);
  const rerenderHeight = await resizer.getAttribute("aria-valuenow");
  await page.evaluate(() => syncRuleAssistance());
  await page.mouse.up();
  assert(await resizer.getAttribute("aria-valuenow") === rerenderHeight
    && await page.evaluate(() => !ruleAssistanceSidebarResize),
  "Rerendering during a drag lost the chosen width or left pointer state behind");
  await resizer.press("Home");
  await resizer.press("ArrowRight");
  assert(await resizer.getAttribute("aria-valuenow") === "320", "Keyboard resizing did not enforce the minimum width");
  await resizer.press("ArrowLeft");
  assert(await resizer.getAttribute("aria-valuenow") === "336"
    && await resizer.getAttribute("aria-valuetext") === "Panel width 336 pixels", "Keyboard resizing did not use accessible 16-pixel steps");
  await resizer.press("End");
  await resizer.press("ArrowLeft");
  assert(await resizer.getAttribute("aria-valuenow") === "680", "Keyboard resizing exceeded the maximum width");
  await page.setViewportSize({ width: 900, height: 600 });
  await page.waitForFunction(() => document.querySelector("#assist-sidebar-resizer").getAttribute("aria-valuemax") === "500");
  assert(await resizer.getAttribute("aria-valuenow") === "500"
    && await sidebar.evaluate(node => getComputedStyle(node).position === "fixed" && node.getBoundingClientRect().width === 500),
  "A narrower supported viewport did not clamp sidebar width and switch to a drawer");
  await page.setViewportSize({ width: 1440, height: 900 });
  await page.evaluate(() => setAssistanceSidebarWidth(420));
  await page.evaluate(() => syncRuleAssistance());
  assert(await resizer.getAttribute("aria-valuenow") === "420", "Rerendering lost the chosen sidebar width");
  assert(await page.evaluate((session) => JSON.stringify(state.session) === session, setup.session)
    && await editor.inputValue() === setup.text, "Sidebar resizing mutated the draft or saved session");
  await input.fill("   ");
  assert(await send.isDisabled(), "Whitespace enabled Send");
  await input.fill("Check this rule against the Hosted catalog.");
  await input.press("Shift+Enter");
  assert((await input.inputValue()).endsWith("\n"), "Shift+Enter submitted instead of adding a newline");

  const requests = [];
  let pending = null;
  let failNext = false;
  let holdNext = true;
  let staleNext = false;
  async function waitForHeldReply() {
    for (let attempt = 0; !pending && attempt < 200; attempt += 1) await page.waitForTimeout(25);
    assert(Boolean(pending), "Assistance request did not reach the held synthetic endpoint");
  }
  await page.route("**/assist-rule", async (route) => {
    const envelope = route.request().postDataJSON();
    const request = JSON.parse(Buffer.from(envelope.payloadBase64, "base64").toString("utf8"));
    requests.push(request);
    const json = await page.evaluate(async (request) => {
      const hash = Array.from(new Uint8Array(await crypto.subtle.digest("SHA-256", new TextEncoder().encode(request.proposedText))), (byte) => byte.toString(16).padStart(2, "0")).join("");
      const profile = globalThis.__HOSTED_RULE_WORKBENCH__.ruleAssistance;
      return {
        schemaVersion: 1, requestId: request.requestId, candidateKey: request.candidateKey, authoritySha256: request.authoritySha256,
        proposedTextSha256: hash, model: profile.model, reasoningEffort: profile.reasoningEffort,
        catalogSha256: profile.catalogSha256, protectedRulesSha256: profile.protectedRulesSha256,
        elapsedMilliseconds: 9000, catalogRuleIds: [...state.bundle.catalog.rules.filter((rule) => rule.status === "active"), ...state.bundle.catalog.protectedRules].map((rule) => rule.id),
        message: "Catalog advice <img src=x onerror=alert(1)>.",
        suggestedWording: `${request.proposedText} Preserve the reviewed obligations.`
      };
    }, request);
    if (staleNext) { json.requestId = "stale"; staleNext = false; }
    const response = failNext
      ? { status: 500, json: { error: { code: "synthetic-failure", message: "Synthetic assistance failure.", diagnosticId: "d".repeat(32) } } }
      : { json };
    failNext = false;
    if (holdNext) {
      holdNext = false;
      await new Promise((resolve) => { pending = async () => { await route.fulfill(response); resolve(); }; });
      pending = null;
    } else await route.fulfill(response);
  });

  await page.evaluate(() => { globalThis.__assistanceOriginalRandom = Math.random; Math.random = () => 0; });
  await input.press("Enter");
  await page.waitForFunction(() => Boolean(ruleAssistance?.active));
  await root.locator(".waiting-panel[data-waiting-panel-ready]").waitFor();
  assert(await clear.isDisabled() && await input.getAttribute("readonly") !== null
    && await send.getAttribute("aria-label") === "Cancel operation", "Running assistance lost cancellation or read-only controls");
  assert(await input.inputValue() === ""
    && await root.locator(".assist-chat-user-message").last().textContent() === "Check this rule against the Hosted catalog.",
    "Enter did not immediately move submitted text from the composer into the transcript");
  await page.waitForFunction(() => document.querySelector(".assist-chat-send .codicon use")?.getBBox().width > 0);
  const running = await root.evaluate((node) => {
    const glyph = node.querySelector(".assist-chat-send .codicon");
    const reference = glyph.querySelector("use");
    const bounds = glyph.getBoundingClientRect();
    return {
      color: getComputedStyle(node.querySelector(".assist-chat-send")).color,
      animation: getComputedStyle(node.querySelector(".waiting-panel")).animationName,
      reference: reference.getAttribute("href"),
      width: bounds.width,
      height: bounds.height,
      fill: getComputedStyle(glyph).fill,
      glyphWidth: reference.getBBox().width
    };
  });
  assert(running.color === "rgb(140, 140, 140)" && running.animation === "waiting-panel-chase"
    && running.reference === "icons/codicons/sprite.svg#codicon-stop-circle"
    && running.width === 16 && running.height === 16 && running.glyphWidth > 0 && running.fill === running.color,
    `Running assistance did not use the native border or gray 16px Codicon stop symbol: ${JSON.stringify(running)}`);
  await waitForHeldReply();
  const waiting = root.locator(".assist-chat-operation-message .shimmer-heading");
  assert(await waiting.locator(".sr-only").textContent() === phrases[0], "The request did not select the first phrase at the lower random boundary");
  assert(await waiting.locator(".shimmer-character").first().evaluate((node) => getComputedStyle(node).animationName.startsWith("shimmer-heading-")),
    "Waiting text did not reuse the shared shimmer animation");
  await page.evaluate(() => { Math.random = () => 0.999999; syncRuleAssistance(); });
  await page.waitForTimeout(5200);
  assert(await waiting.locator(".sr-only").textContent() === phrases[0], "A waiting phrase changed during rerender or rotated during a request");
  await page.emulateMedia({ reducedMotion: "reduce" });
  assert(await waiting.locator(".shimmer-character").first().evaluate((node) => getComputedStyle(node).animationName) === "none"
    && await waiting.locator(".sr-only").textContent() === phrases[0], "Reduced motion removed the phrase or retained animated text");
  await page.emulateMedia({ reducedMotion: "no-preference" });
  await pending();
  await page.waitForFunction(() => !ruleAssistance?.active && Boolean(ruleAssistance?.turns[0]?.answer));
  assert(!await root.locator(".assist-chat-operation-message .shimmer-heading").count(), "Completed assistance retained animated waiting text");
  assert(await root.locator(".assist-chat-ai-message").textContent().then((text) => text.includes("<img src=x onerror=alert(1)>"))
    && !await root.locator(".assist-chat-ai-message img").count(), "AI reply was interpreted as HTML");
  assert(await input.inputValue() === "" && !await clear.isDisabled(), "Completed reply did not reset input or enable Clear");
  assert(await page.evaluate((session) => JSON.stringify(state.session) === session, setup.session), "Reading an answer mutated persisted draft state");
  assert(await editor.inputValue() === setup.text, "AI completion edited the rule automatically");
  const replyLayout = await root.evaluate((node) => {
    const transcript = node.querySelector(".assist-chat-response");
    const transcriptStyle = getComputedStyle(transcript);
    const availableWidth = transcript.clientWidth - parseFloat(transcriptStyle.paddingLeft) - parseFloat(transcriptStyle.paddingRight);
    const bubble = transcript.querySelector(".assist-chat-user-message").getBoundingClientRect();
    const rightEdge = transcript.getBoundingClientRect().left + parseFloat(transcriptStyle.paddingLeft) + availableWidth;
    const answer = transcript.querySelector(".assist-chat-ai-message");
    const scope = getComputedStyle(answer.querySelector(".assist-chat-scope"));
    return {
      shortBubble: bubble.width < availableWidth * 0.9 - 1 && Math.abs(bubble.right - rightEdge) < 1,
      fullReply: Math.abs(answer.getBoundingClientRect().width - availableWidth) < 1,
      spacing: getComputedStyle(answer.querySelector(".assist-chat-message-author")).marginBottom === "16px"
        && scope.marginTop === "16px" && scope.marginBottom === "16px"
    };
  });
  assert(replyLayout.shortBubble && replyLayout.fullReply, "Short user text did not shrink to fit at the right edge, or the AI reply lost full width");
  assert(replyLayout.spacing, "Completion time and Context did not retain their accepted 16-pixel gaps");
  const contextNote = await root.locator(".assist-chat-scope").evaluate(node => ({
    reference: node.querySelector("use").getAttribute("href"),
    iconFirst: node.firstElementChild.matches("svg") && node.lastElementChild.matches("span"),
    color: getComputedStyle(node).color,
    expectedText: node.querySelector("span").textContent === `Context: ${ruleAssistance.turns[0].answer.catalogRuleIds.length} active or protected Hosted rules. Catalog snapshot only; other draft and Plan changes are not included.`
  }));
  assert(contextNote.reference === "icons/codicons/sprite.svg#codicon-tools" && contextNote.iconFirst
    && contextNote.color === "rgb(115, 115, 115)" && contextNote.expectedText,
    "Successful reply did not render its unchanged catalog scope through the shared muted icon-first note helper");
  const suggestion = root.locator(".assist-chat-inline-wording");
  const copy = root.locator("[data-assist-copy]");
  const suggestionLayout = await suggestion.evaluate((node) => {
    const wording = node.querySelector("pre");
    const message = node.closest(".assist-chat-ai-message");
    const style = getComputedStyle(wording);
    return {
      inline: node.firstElementChild.textContent === "I suggest updating the rule to:" && !node.querySelector("details,summary,[data-assist-use]"),
      exact: wording.textContent === ruleAssistance.turns[0].answer.suggestedWording,
      unscrolled: style.maxHeight === "none" && style.overflowY === "visible" && wording.scrollHeight <= wording.clientHeight + 1,
      metadataOrder: message.children[0].matches(".assist-chat-message-author") && message.children[1].matches(".assist-chat-scope")
        && message.children[2].matches(".assist-chat-message-text") && message.children[3] === node
    };
  });
  assert(suggestionLayout.inline && suggestionLayout.exact && suggestionLayout.unscrolled && suggestionLayout.metadataOrder,
    `Inline wording or reply metadata lost the accepted layout: ${JSON.stringify(suggestionLayout)}`);
  await root.locator(".assist-chat-conversation-toolbar").hover();
  assert(await suggestion.locator(".assist-chat-floating-toolbar").evaluate(node => getComputedStyle(node).opacity) === "0",
    "The wording action toolbar remained visible away from hover and keyboard focus");
  await copy.focus();
  assert(await suggestion.locator(".assist-chat-floating-toolbar").evaluate(node => getComputedStyle(node).opacity) === "1",
    "Keyboard focus did not reveal the wording action toolbar");
  await input.focus();
  await suggestion.hover();
  await copy.hover();
  const copyLayout = await copy.evaluate(button => {
    const toolbar = button.parentElement;
    const bounds = toolbar.getBoundingClientRect();
    const action = button.getBoundingClientRect();
    const style = getComputedStyle(toolbar);
    return {
      visible: style.opacity === "1",
      vertical: Math.abs(action.top - bounds.top - parseFloat(style.borderTopWidth)) < 1
        && Math.abs(bounds.bottom - action.bottom - parseFloat(style.borderBottomWidth)) < 1,
      gutters: Math.abs(action.left - bounds.left - parseFloat(style.borderLeftWidth) - 3) < 1
        && Math.abs(bounds.right - action.right - parseFloat(style.borderRightWidth) - 3) < 1,
      tooltip: !button.hasAttribute("title") && button.dataset.workbenchTooltip === "Copy suggested wording"
    };
  });
  assert(copyLayout.visible && copyLayout.vertical && copyLayout.gutters && copyLayout.tooltip,
    `The floating copy action lost its hover geometry or custom-only tooltip: ${JSON.stringify(copyLayout)}`);
  await page.evaluate(() => Object.defineProperty(navigator, "clipboard", { configurable: true, value: {
    writeText: async text => { globalThis.__assistanceCopiedWording = text; }
  } }));
  await copy.click();
  await page.waitForFunction(() => document.querySelector("[data-assist-copy]").dataset.workbenchTooltip === "Copied");
  assert(await page.evaluate(() => globalThis.__assistanceCopiedWording === ruleAssistance.turns[0].answer.suggestedWording)
    && await editor.inputValue() === setup.text
    && await page.evaluate(session => JSON.stringify(state.session) === session, setup.session), "Copy changed the editor or draft, or copied different wording");
  assert(await copy.getAttribute("title") === null && await copy.getAttribute("aria-label") === "Suggested rule wording copied",
    "Copy feedback restored a native tooltip or lost its accessible label");
  await page.evaluate(() => Object.defineProperty(navigator, "clipboard", { configurable: true, value: {
    writeText: async () => { throw new Error("Synthetic clipboard denial"); }
  } }));
  await copy.click();
  await page.waitForFunction(() => document.querySelector("[data-assist-copy]").dataset.workbenchTooltip === "Unable to copy");
  assert(await copy.getAttribute("title") === null && await editor.inputValue() === setup.text
    && await copy.locator("use").getAttribute("href") === "icons/codicons/sprite.svg#codicon-copy",
    "Clipboard failure retained a success icon, restored a native tooltip or changed the editor");
  await input.fill("Follow up on that advice. ".repeat(50));
  holdNext = true;
  await send.click();
  await waitForHeldReply();
  assert(await input.inputValue() === ""
    && await root.locator(".assist-chat-user-message").last().textContent() === requests[1].messages.at(-1).content,
    "Send did not immediately move submitted text from the composer into the transcript");
  assert(await waiting.locator(".sr-only").textContent() === phrases.at(-1), "A new request did not independently select the last phrase at the upper random boundary");
  await page.evaluate(() => { Math.random = globalThis.__assistanceOriginalRandom; delete globalThis.__assistanceOriginalRandom; });
  await pending();
  await page.waitForFunction(() => ruleAssistance?.turns.filter((turn) => turn.answer).length === 2);
  const longBubble = await root.evaluate((node) => {
    const transcript = node.querySelector(".assist-chat-response");
    const style = getComputedStyle(transcript);
    const width = transcript.clientWidth - parseFloat(style.paddingLeft) - parseFloat(style.paddingRight);
    return Math.abs(Array.from(transcript.querySelectorAll(".assist-chat-user-message")).at(-1).getBoundingClientRect().width - width * 0.9) < 1;
  });
  assert(longBubble, "Long user text did not fill its 90-percent maximum without the old character-width cap");
  assert(requests[1].messages.length === 3 && requests[1].messages[1].role === "assistant", "Follow-up omitted completed conversation context");
  const scrolling = await root.evaluate((node) => {
    const transcript = node.querySelector(".assist-chat-response");
    const toolbar = node.querySelector(".assist-chat-conversation-toolbar");
    transcript.scrollTop = 0;
    const top = toolbar.getBoundingClientRect().top;
    transcript.scrollTop = transcript.scrollHeight;
    return {
      scrollable: transcript.scrollHeight > transcript.clientHeight && transcript.scrollTop > 0,
      fixed: toolbar.getBoundingClientRect().top === top && !transcript.contains(toolbar),
      singleIdentity: node.querySelectorAll(".assist-chat-identity").length === 1
    };
  });
  assert(scrolling.scrollable && scrolling.fixed && scrolling.singleIdentity,
    `Conversation scrolling moved or repeated the Copilot header: ${JSON.stringify(scrolling)}`);
  const latest = root.locator("[data-assist-scroll-latest]");
  await page.waitForFunction(() => document.querySelector("[data-assist-scroll-latest]").hidden);
  await root.locator(".assist-chat-response").evaluate(node => { node.scrollTop = 0; });
  await latest.waitFor({ state: "visible" });
  const latestLayout = await latest.evaluate(button => {
    const response = button.parentElement.querySelector(".assist-chat-response");
    const bounds = button.getBoundingClientRect();
    const viewport = response.getBoundingClientRect();
    let surface = response;
    while (surface && getComputedStyle(surface).backgroundColor === "rgba(0, 0, 0, 0)") surface = surface.parentElement;
    return {
      circular: bounds.width === 28 && bounds.height === 28 && getComputedStyle(button).borderRadius === "50%",
      bottomRight: Math.abs(viewport.right - bounds.right - 12) < 1 && bounds.bottom <= viewport.bottom,
      background: Boolean(surface) && getComputedStyle(button).backgroundColor === getComputedStyle(surface).backgroundColor,
      chevron: getComputedStyle(button.querySelector("svg")).transform === "matrix(1, 0, 0, 1, 0, 1)",
      tooltip: !button.hasAttribute("title") && button.dataset.workbenchTooltip === "Scroll to latest reply"
    };
  });
  assert(Object.values(latestLayout).every(Boolean), `Scroll-to-latest lost its accepted appearance: ${JSON.stringify(latestLayout)}`);
  await page.evaluate(() => syncRuleAssistance());
  assert(await latest.isVisible() && await root.locator(".assist-chat-response").evaluate(node => node.scrollTop) === 0,
    "Rerendering pulled the reader down instead of retaining the earlier reply");
  await page.locator("#assist-panel-toggle").click();
  await page.locator("#assist-panel-toggle").click();
  await page.waitForFunction(() => !ruleAssistance.followOutput && !document.querySelector("[data-assist-scroll-latest]").hidden);
  assert(await root.locator(".assist-chat-response").evaluate(node => node.scrollTop) === 0,
    "Hiding and showing the sidebar lost the earlier reading position");
  await latest.click();
  await page.waitForFunction(() => document.querySelector("[data-assist-scroll-latest]").hidden);
  assert(await page.evaluate(() => ruleAssistance.followOutput) && await root.locator(".assist-chat-response").evaluate(node => node.scrollHeight - node.clientHeight - node.scrollTop <= 4),
    "Scroll-to-latest did not reach the bottom and restore output following");

  await input.fill("Keep this unsent text.");
  await clear.click();
  assert(await clear.isDisabled() && await input.inputValue() === "Keep this unsent text."
    && await editor.inputValue() === setup.text, "Clear did not preserve unsent input and draft");
  failNext = true;
  await send.click();
  await root.locator(".assist-chat-error").getByText("Synthetic assistance failure.", { exact: true }).waitFor();
  assert(await input.inputValue() === "Keep this unsent text." && requests[2].messages.length === 1, "Clearing did not reset model context or failure lost input");
  assert(!await root.locator(".assist-chat-operation-message .shimmer-heading").count(), "A genuine failure was rendered as an animated waiting phrase");
  const errorPanel = root.locator(".assist-chat-error");
  const errorFillsReply = await errorPanel.evaluate(node => {
    const transcript = node.parentElement;
    const style = getComputedStyle(transcript);
    const availableWidth = transcript.clientWidth - parseFloat(style.paddingLeft) - parseFloat(style.paddingRight);
    return Math.abs(node.getBoundingClientRect().width - availableWidth) <= 1;
  });
  assert(errorFillsReply, "Assistance error panel did not fill the reply area's available width");
  assert(await errorPanel.locator(".assist-chat-error-title").textContent() === "Rule assistance failed"
    && await errorPanel.locator(".assist-chat-error-reference").textContent() === `Diagnostic reference: ${"d".repeat(32)}`
    && await errorPanel.evaluate(node => node.parentElement.id === "rule-assistance-conversation")
    && !await root.locator(".error-banner").count(), "Assistance failure lost its dedicated inline notification or diagnostic reference");
  const failedState = await page.evaluate(() => ({ session: JSON.stringify(state.session), input: ruleAssistance.input, turns: ruleAssistance.turns.length }));
  const requestsBeforeDismiss = requests.length;
  for (const selector of [".assist-chat-error-close", ".assist-chat-error-dismiss"]) {
    await errorPanel.locator(selector).click();
    assert(await errorPanel.count() === 0 && requests.length === requestsBeforeDismiss
      && await page.evaluate(before => JSON.stringify(state.session) === before.session && ruleAssistance.input === before.input
        && ruleAssistance.turns.length === before.turns && ruleAssistance.turns.at(-1).failed, failedState), "Dismissing assistance failure changed the draft, conversation or started inference");
    await page.evaluate(() => { ruleAssistance.turns.at(-1).errorDismissed = false; syncRuleAssistance(); });
  }
  await editor.fill(setup.text + " Changed after failure.");
  assert(await errorPanel.locator("[data-assist-error-retry]").isDisabled(), "Retry remained enabled for a different wording snapshot");
  await editor.fill(setup.text);
  assert(await errorPanel.locator("[data-assist-error-retry]").isEnabled(), "Restoring request wording did not re-enable Retry");
  await input.fill("Preserve this different unsent input.");
  holdNext = true;
  await errorPanel.locator("[data-assist-error-retry]").click();
  await waitForHeldReply();
  assert(await input.inputValue() === "Preserve this different unsent input.", "Starting Retry cleared an unrelated unsent draft");
  await pending();
  await page.waitForFunction(() => !ruleAssistance.active && Boolean(ruleAssistance.turns.at(-1).answer));
  assert(requests.length === requestsBeforeDismiss + 1 && requests.at(-1).messages.at(-1).content === "Keep this unsent text."
    && await page.evaluate(count => ruleAssistance.turns.length === count, failedState.turns)
    && await input.inputValue() === "Preserve this different unsent input.", "Explicit Retry duplicated the turn, retried another question or discarded unsent input");
  await input.fill("Keep this unsent text.");
  await clear.click();
  staleNext = true;
  await send.click();
  await root.locator(".assist-chat-error").getByText("Rule assistance returned a stale or invalid reply.", { exact: true }).waitFor();

  await clear.click();
  await send.click();
  await page.waitForFunction(() => !ruleAssistance?.active);
  const handoffReply = await page.evaluate(() => ({
    answered: Boolean(ruleAssistance?.turns[0]?.answer),
    status: ruleAssistance?.turns[0]?.status,
    input: ruleAssistance?.input
  }));
  assert(handoffReply.answered, `Suggestion race fixture did not receive a successful reply: ${JSON.stringify(handoffReply)}`);
  await page.evaluate(() => Object.defineProperty(navigator, "clipboard", { configurable: true, value: {
    writeText: text => new Promise(resolve => {
      globalThis.__assistanceCopiedWording = text;
      globalThis.__assistanceReleaseCopy = resolve;
    })
  } }));
  await suggestion.hover();
  await copy.click();
  await page.waitForFunction(() => typeof globalThis.__assistanceReleaseCopy === "function");
  await clear.click();
  await page.evaluate(() => { globalThis.__assistanceReleaseCopy(); delete globalThis.__assistanceReleaseCopy; });
  assert(await editor.inputValue() === setup.text && await copy.count() === 0
    && await page.evaluate(session => JSON.stringify(state.session) === session, setup.session), "Completing a cleared copy mutated the editor, draft or conversation");
  await input.fill("Keep this unsent text.");

  holdNext = true;
  await send.click();
  await waitForHeldReply();
  await send.click();
  await root.getByText("Operation canceled.", { exact: true }).waitFor();
  await pending();
  assert(!await root.locator(".assist-chat-ai-message").count() && await input.inputValue() === "Keep this unsent text.",
    "Cancellation accepted a late reply or discarded the request text");
  assert(!await root.locator(".assist-chat-operation-message .shimmer-heading").count(), "Cancellation retained animated waiting text");

  const disclosure = page.locator("#assist-panel-toggle");
  const headerCancel = root.locator("[data-assist-header-cancel]");
  const navigationDialog = page.locator("[data-assist-navigation-dialog]");
  const otherKey = await page.evaluate((key) => state.candidates.find((candidate) => candidate.key !== key).key, setup.key);
  const savedBeforeNavigation = await page.evaluate(() => JSON.stringify(state.session));
  const headerGeometry = () => disclosure.evaluate((node) => ({ left: node.getBoundingClientRect().left, width: node.getBoundingClientRect().width }));
  await disclosure.click();
  assert(!await sidebar.isVisible() && await disclosure.getAttribute("data-workbench-tooltip") === "Show AI assistance"
    && await disclosure.locator("use").getAttribute("href") === "icons/codicons/sprite.svg#codicon-layout-sidebar-right-off",
  "Hiding assistance did not hide the shared sidebar and update its tab-row icon and tooltip");
  const initialCollapsedGeometry = await headerGeometry();
  await disclosure.click();
  assert(await input.inputValue() === "Keep this unsent text." && await editor.inputValue() === setup.text,
    "Sidebar visibility toggling discarded unsent request or proposed rule text");

  holdNext = true;
  await send.click();
  await waitForHeldReply();
  await disclosure.click();
  assert(!await sidebar.isVisible() && await page.evaluate(() => Boolean(ruleAssistance.active)),
    "Hiding the sidebar cancelled its running request");
  const collapsedGeometry = await headerGeometry();
  assert(collapsedGeometry.left === initialCollapsedGeometry.left && collapsedGeometry.width === initialCollapsedGeometry.width,
    "Request activity shifted the shared tab-row toggle");
  await disclosure.click();
  assert(await headerCancel.isVisible() && await root.locator(".assist-header-working").isVisible(),
    "Showing active assistance lost its activity or cancellation control");
  await page.emulateMedia({ reducedMotion: "reduce" });
  assert(await root.locator(".assist-header-working .waiting-panel-spinner").evaluate((node) => getComputedStyle(node).animationName) === "none",
    "Sidebar activity spinner ignored reduced motion");
  await page.emulateMedia({ reducedMotion: "no-preference" });
  assert(await root.locator(".assist-header-working .waiting-panel-spinner").evaluate((node) => getComputedStyle(node).animationName) === "waiting-panel-spin",
    "Sidebar activity did not reuse the shared spinner animation");
  await headerCancel.click();
  assert(!await headerCancel.isVisible()
    && !await root.locator(".assist-header-working").isVisible(), "Header cancellation retained activity or showed an error");
  await pending();
  assert(!await root.locator(".assist-chat-ai-message").count(), "Header cancellation accepted a late reply");

  failNext = true;
  await send.click();
  await page.waitForFunction(() => !ruleAssistance.active && ruleAssistance.turns.at(-1)?.failed);
  await disclosure.click();
  assert(!await sidebar.isVisible(), "Failure prevented the sidebar from being hidden");
  await disclosure.click();
  assert(await root.locator(".assist-chat-error").isVisible() && !await headerCancel.isVisible(),
    "Reopening the sidebar discarded its failure or retained a stale cancellation control");
  await clear.click();
  assert(!await root.locator(".assist-chat-error").count(), "Clearing conversation retained a stale failure");
  const sharedNavigation = await page.evaluate(() => {
    const chat = ruleAssistance;
    const node = document.querySelector("[data-rule-assistance]");
    const panel = document.getElementById("rule-assistance-panel");
    const toggle = document.getElementById("assist-panel-toggle");
    showCandidatePane("candidates");
    const onList = node.isConnected && ruleAssistance === chat && panel.hidden && toggle.disabled && toggle.getBoundingClientRect().width > 0;
    showCandidatePane("details");
    setRuleAssistanceExpanded(false);
    showCandidatePane("candidates");
    showCandidatePane("details");
    const collapsedRetained = panel.hidden && !toggle.disabled && !ruleAssistanceExpanded;
    setRuleAssistanceExpanded(true);
    switchView("plan");
    const onPlan = panel.hidden && toggle.disabled;
    switchView("preview");
    const onPreview = panel.hidden && toggle.disabled;
    switchView("catalog");
    setWorkspaceTab("rule-issues");
    const onIssues = panel.hidden && toggle.disabled;
    setWorkspaceTab("assessment-results");
    const onAssessment = node.isConnected && ruleAssistance === chat && panel.hidden && toggle.disabled && toggle.parentElement.id === "assessment-assistance-controls";
    setWorkspaceTab("candidate-sources");
    return { onList, onAssessment, onPlan, onPreview, onIssues, collapsedRetained, retained: ruleAssistance === chat && document.querySelectorAll("[data-rule-assistance]").length === 1 && document.querySelectorAll("#assist-panel-toggle").length === 1 && !panel.hidden && !toggle.disabled };
  });
  assert(Object.values(sharedNavigation).every(Boolean),
    `Contextual sidebar navigation lost control availability, expansion preference, or the shared conversation: ${JSON.stringify(sharedNavigation)}`);

  async function startHeldRequest(question) {
    await input.fill(question);
    holdNext = true;
    await send.click();
    await waitForHeldReply();
    assert(await input.inputValue() === "" && await root.locator(".assist-chat-user-message").last().textContent() === question,
      "Held request retained submitted input or lost its transcript question");
  }
  async function requestSwitch() {
    await page.evaluate((key) => selectCandidate(key), otherKey);
    await navigationDialog.waitFor({ state: "visible" });
  }
  const currentKey = () => page.evaluate(() => getActiveCandidate().key);
  const allowNavigation = navigationDialog.locator(".button[data-assist-navigation-allow]");
  const cancelNavigation = navigationDialog.locator("[data-assist-navigation-cancel]");
  await startHeldRequest("Retain this exact current request.");
  await editor.fill(setup.text + " Unsaved editor text.");
  await requestSwitch();
  assert(await currentKey() === setup.key && await page.evaluate(() => Boolean(ruleAssistance.active)),
    "Opening navigation confirmation silently switched rules or cancelled assistance");
  assert(await navigationDialog.locator("h2").textContent() === "AI Request in Progress"
    && await navigationDialog.locator("#assist-navigation-description").textContent()
      === `An AI request for ${setup.ruleId} is still running. Switching rules will cancel the current AI rule request before completion.`
    && await allowNavigation.textContent().then((text) => text.trim()) === "Allow Request to Complete"
    && await cancelNavigation.textContent().then((text) => text.trim()) === "Cancel Request",
    "Navigation confirmation lost approved title, body, or action labels");
  assert(await navigationDialog.locator("strong").textContent() === setup.ruleId
    && !await navigationDialog.textContent().then((text) => text.includes("Prototype preview"))
    && await allowNavigation.evaluate((node) => node.classList.contains("primary"))
    && await cancelNavigation.evaluate((node) => node.classList.contains("destructive")),
    "Production confirmation lost shared button variants, safe rule emphasis, or retained a prototype notice");
  await page.waitForFunction(() => Array.from(document.querySelectorAll("[data-assist-navigation-dialog] .button use")).every((node) => node.getBBox().width > 0));
  assert(await navigationDialog.locator(".button use").evaluateAll((nodes) => nodes.map((node) => node.getAttribute("href")).join(","))
    === "icons/codicons/sprite.svg#codicon-play-circle,icons/codicons/sprite.svg#codicon-stop-circle",
    "Navigation confirmation did not use the shared native play and stop symbols");
  await allowNavigation.click();
  assert(await currentKey() === setup.key && await page.evaluate(() => Boolean(ruleAssistance.active))
    && await editor.inputValue() === setup.text + " Unsaved editor text.", "Allow changed the rule, request, or unsaved wording");
  await pending();
  await page.waitForFunction(() => !ruleAssistance.active);
  assert(await currentKey() === setup.key, "Completion after Allow replayed discarded navigation");
  await editor.fill(setup.text);

  for (const dismissal of ["escape", "close"]) {
    await startHeldRequest("Continue after " + dismissal);
    await requestSwitch();
    if (dismissal === "escape") await page.keyboard.press("Escape");
    else await navigationDialog.locator(".titlebar-icon[data-assist-navigation-allow]").click();
    assert(!await navigationDialog.count() && await currentKey() === setup.key
      && await page.evaluate(() => Boolean(ruleAssistance.active)), `${dismissal} cancelled the request or switched rules`);
    await pending();
    await page.waitForFunction(() => !ruleAssistance.active);
    assert(await currentKey() === setup.key, `Completion after ${dismissal} replayed navigation`);
  }

  await startHeldRequest("Cancel only on explicit confirmation.");
  await requestSwitch();
  await cancelNavigation.click();
  assert(await currentKey() === otherKey && !await navigationDialog.count()
    && !await page.evaluate(() => Boolean(ruleAssistance.active)), "Explicit cancellation did not stop and switch once");
  await pending();
  assert(!await root.locator(".assist-chat-ai-message").count(), "A late cancelled answer attached to the new rule");
  await page.evaluate((key) => selectCandidate(key), setup.key);
  await startHeldRequest("Complete before confirmation.");
  await requestSwitch();
  const lateConfirmation = await cancelNavigation.elementHandle();
  await pending();
  await page.waitForFunction((key) => getActiveCandidate().key === key && !pendingRuleAssistanceNavigation, otherKey);
  assert(!await navigationDialog.count() && !await root.locator(".assist-chat-ai-message").count(),
    "Completion did not resume selection or leaked the old conversation into its destination");
  await lateConfirmation.evaluate((node) => node.click());
  assert(await currentKey() === otherKey, "Late confirmation repeated or reversed completed navigation");
  await page.evaluate((key) => selectCandidate(key), setup.key);
  await startHeldRequest("The first dismissed request.");
  await requestSwitch();
  await allowNavigation.click();
  await send.click();
  const oldReply = pending;
  await oldReply();
  await startHeldRequest("A separate current request.");
  await requestSwitch();
  await navigationDialog.locator(".titlebar-icon[data-assist-navigation-allow]").click();
  assert(await page.evaluate(() => pendingRuleAssistanceNavigation === null && Boolean(ruleAssistance.active)),
    "Dismissal did not detach navigation from the exact active request");
  await send.click();
  await pending();
  assert(await page.evaluate((session) => JSON.stringify(state.session) === session, savedBeforeNavigation),
    "Disclosure, confirmation, or request completion changed saved decisions");
  const excluded = await page.evaluate(() => {
    const candidate = state.assessedCandidates.find(item => !item.assessment.hostedApplicable && getDecision(item).proposedText?.trim());
    return candidate ? { key: candidate.key, text: getDecision(candidate).proposedText } : null;
  });
  assert(Boolean(excluded), "The fixture has no complete excluded assessment for sidebar context checks");
  await startHeldRequest("Keep the current context while reviewing assessments.");
  await page.evaluate(() => setWorkspaceTab("assessment-results"));
  assert(!await sidebar.isVisible() && await disclosure.isDisabled() && await page.evaluate(() => Boolean(ruleAssistance.active)),
    "Entering the assessment list exposed assistance or cancelled the current request");
  await page.evaluate(key => selectAssessmentResult(key), excluded.key);
  await navigationDialog.waitFor({ state: "visible" });
  assert(await page.evaluate(key => getRuleAssistanceCandidate().key === key && Boolean(ruleAssistance.active), setup.key),
    "Selecting an assessment silently replaced an in-flight sidebar context");
  await allowNavigation.click();
  await pending();
  await page.waitForFunction(() => !ruleAssistance.active);
  await page.evaluate(key => { selectAssessmentResult(key); showAssessmentPane("details"); }, excluded.key);
  assert(await page.evaluate(key => getRuleAssistanceCandidate().key === key, excluded.key)
    && await clear.isDisabled() && await input.inputValue() === ""
    && await page.locator("#assessment-assistance-controls #assist-panel-toggle").isEnabled(), "Assessment Details did not enable its control or retained another rule's conversation");
  await input.fill("Review this excluded assessment without editing its outcome.");
  await send.click();
  await page.waitForFunction(() => !ruleAssistance.active && Boolean(ruleAssistance.turns[0]?.answer));
  assert(requests.at(-1).candidateKey === excluded.key && requests.at(-1).proposedText === excluded.text,
    "Assessment assistance used the hidden Details editor or another candidate's identity");
  assert(await page.evaluate(session => JSON.stringify(state.session) === session, savedBeforeNavigation),
    "Assessment chat changed its applicability, saved decisions or Plan membership");
  await page.evaluate(() => { setWorkspaceTab("candidate-sources"); selectProtectedRule(state.protectedRules[0].id); });
  assert(await page.evaluate(() => ruleAssistance === null) && !await root.count(),
    "Protected-rule selection retained an editable chat target");
  await page.evaluate(key => { setWorkspaceTab("assessment-results"); selectAssessmentResult(key); }, excluded.key);
  await page.evaluate(() => setWorkspaceTab("candidate-sources"));
  assert(await page.evaluate(() => ruleAssistance === null) && !await root.count(),
    "Returning to a protected-rule view retained an assessment chat target");
  await page.evaluate(key => selectCandidate(key), setup.key);
  const categories = await page.evaluate(() => Array.from(new Map(state.candidates.map((candidate) => [candidate.recommendation.category, candidate.key])).entries()));
  for (const [category, key] of categories) {
    await page.evaluate((key) => selectCandidate(key), key);
    const applicable = page.locator(".implementation-model-control-group");
    assert(await applicable.count() === (category === "implementation" ? 1 : 0)
      && !await page.getByText("Resource types apply only to implementation rules.", { exact: true }).count(),
      `Resource applicability leaked into ${category} or retained redundant guidance`);
    if (category === "implementation") assert(await applicable.locator("input").evaluateAll((nodes) => nodes.map((node) => node.value).join(",")) === "legacy,typed,framework",
      "Implementation applicability lost its existing three resource models");
  }
  await page.evaluate((key) => selectCandidate(key), setup.key);
  await page.evaluate((key) => {
    const other = state.candidates.find((candidate) => candidate.key !== key);
    selectCandidate(other.key);
    selectCandidate(key);
  }, setup.key);
  assert(await clear.isDisabled() && await input.inputValue() === "" && !await root.locator(".assist-chat-user-message").count(),
    "Switching rules retained conversation context");
  const exactSubmittedInput = "  Restore this exact submitted draft.\n";
  await input.fill(exactSubmittedInput);
  failNext = true;
  holdNext = true;
  await send.click();
  await waitForHeldReply();
  assert(await input.inputValue() === "", "A pending failed request retained its submitted input");
  await pending();
  await page.waitForFunction(() => !ruleAssistance.active && ruleAssistance.turns.at(-1).failed);
  assert(await input.inputValue() === exactSubmittedInput, "Failure did not restore the exact submitted draft, including whitespace");
  holdNext = true;
  await errorPanel.locator("[data-assist-error-retry]").click();
  await waitForHeldReply();
  assert(await input.inputValue() === "" && await root.locator(".assist-chat-user-message").count() === 1,
    "Retry did not clear the restored submitted input or duplicated its transcript turn");
  await pending();
  await page.waitForFunction(() => !ruleAssistance.active && Boolean(ruleAssistance.turns.at(-1).answer));
  assert(await input.inputValue() === "", "Successful Retry restored text that had already been submitted");
  for (const outcome of ["success", "failure", "cancellation"]) {
    const submitted = `Submitted before ${outcome}.`;
    const newer = outcome === "success" ? submitted : `Newer draft during ${outcome}.`;
    failNext = outcome === "failure";
    await startHeldRequest(submitted);
    await page.evaluate(value => { ruleAssistance.input = value; syncRuleAssistance(); }, newer);
    if (outcome === "cancellation") await send.click();
    await pending();
    await page.waitForFunction(() => !ruleAssistance.active);
    assert(await input.inputValue() === newer, `${outcome} overwrote newer composer input`);
  }
  await clear.click();
  await input.fill("Not persisted.");
  await page.reload({ waitUntil: "domcontentloaded" });
  await page.waitForFunction(() => document.querySelector("#workspace")?.classList.contains("icon-paint-pending") === false);
  await page.evaluate((key) => { selectCandidate(key); showCandidatePane("details"); }, setup.key);
  assert(await input.inputValue() === "" && await clear.isDisabled(), "Reload persisted a conversation");
  await page.unroute("**/assist-rule");
  for (const response of [
    { status: 404, body: "Missing catalog" },
    { status: 200, contentType: "application/json", body: "not-json" },
    { status: 200, json: ["duplicate", "duplicate"] }
  ]) {
    await page.route("**/assistance-waiting-phrases.json", (route) => route.fulfill(response));
    await page.reload({ waitUntil: "domcontentloaded" });
    await page.getByRole("heading", { name: "Workbench Could Not Load", exact: true }).waitFor();
    assert(await page.evaluate(() => state.bundle === null && state.session === null)
      && !await page.locator("[data-rule-assistance]").count(), "A missing or invalid waiting catalog silently fell back to a working UI");
    await page.unroute("**/assistance-waiting-phrases.json");
  }
  await openWorkbench(page, baseUrl);
  assert(await page.evaluate((expected) => JSON.stringify(ruleAssistanceWaitingPhrases) === JSON.stringify(expected), expectedWaitingPhrases),
    "The complete waiting-phrase catalog did not recover after explicit load failures");
}

module.exports = { name: "rule assistance", behaviorIds, viewport: { width: 1440, height: 900 }, run };
