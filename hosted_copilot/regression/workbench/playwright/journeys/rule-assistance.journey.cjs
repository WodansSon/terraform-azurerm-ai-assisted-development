const { openWorkbench, getCssTokenColor } = require("../helpers/workbench.cjs");
const expectedWaitingPhrases = require("../../../../workbench/assistance-waiting-phrases.json");

const behaviorIds = ["WB-UX-ASSISTANCE-001"];

async function run({ page, baseUrl, assert }) {
  await openWorkbench(page, baseUrl);
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
  await root.scrollIntoViewIfNeeded();
  assert(await clear.isDisabled() && await send.isDisabled(), "Empty chat offers Clear or Send");
  assert(await root.locator(".assist-header").textContent() === "AI Assistance:", "Assistance heading changed");
  assert(!await page.locator('#assessment-panel [data-evidence-kind="coverage"]').count(), "Candidate Details retained inferred coverage");
  await page.waitForFunction(() => document.querySelector(".assist-chat-profile .llm-icon use")?.getBBox().width > 0
    && document.querySelector(".assist-chat-identity .codicon use")?.getBBox().width > 0);
  const modelIcon = await root.locator(".assist-chat-profile .llm-icon").evaluate((node) => ({
    reference: node.querySelector("use").getAttribute("href"),
    width: node.getBoundingClientRect().width,
    height: node.getBoundingClientRect().height,
    color: getComputedStyle(node).color,
    profileColor: getComputedStyle(node.parentElement).color,
    decorative: node.getAttribute("aria-hidden") === "true"
  }));
  assert(modelIcon.reference === "icons/llms/sprite.svg#llm-openai" && modelIcon.width === 12 && modelIcon.height === 12
    && modelIcon.color === modelIcon.profileColor && modelIcon.decorative && !await root.locator(".assist-chat-profile img").count(),
  `Model branding did not paint from the attributed LLM sprite: ${JSON.stringify(modelIcon)}`);
  const presentation = await root.evaluate((node) => {
    const heading = node.querySelector(".assist-header");
    const guidance = heading.nextElementSibling;
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
      emphasis: paragraph.querySelector("strong")?.textContent === "Advice only:"
        && getComputedStyle(paragraph.querySelector("strong")).fontWeight === "600"
        && getComputedStyle(paragraph).fontWeight === "400",
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
  assert(presentation.guidanceText === "Advice only: Conversation clears when switching rules or reloading; clearing conversation history does not change the draft."
    && presentation.emphasis, "Assistance guidance lost its accepted wording or semibold label");
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
      sized: composer.getBoundingClientRect().height === 160 && reply.getBoundingClientRect().height === 320
        && getComputedStyle(goal).resize === "none",
      scrolling: node.querySelector(".assist-chat-response").classList.contains("scroll-surface")
        && goal.classList.contains("scroll-surface"),
      metadata: getComputedStyle(node.querySelector(".assist-chat-profile")).fontSize === "12px"
        && getComputedStyle(node.querySelector(".assist-chat-context-label")).fontSize === "12px"
        && getComputedStyle(node.querySelector(".assist-chat-context-label")).fontStyle === "italic",
      placeholder: getComputedStyle(goal, "::placeholder").color === "rgb(115, 115, 115)",
      profile: node.querySelector(".assist-chat-profile").textContent
    };
  });
  assert(geometry.sized && geometry.scrolling && geometry.metadata && geometry.placeholder && geometry.profile.includes("GPT-5.4"), `Accepted assistance layout or runtime readout changed: ${JSON.stringify(geometry)}`);
  const resizer = root.getByRole("separator", { name: "Resize AI assistance conversation" });
  assert(await resizer.getAttribute("aria-orientation") === "horizontal"
    && await resizer.getAttribute("aria-controls") === "rule-assistance-conversation"
    && await resizer.getAttribute("aria-valuemin") === "160", "Conversation resizing lost accessible separator semantics");
  await resizer.evaluate((node) => node.scrollIntoView({ block: "center" }));
  let edge = await resizer.boundingBox();
  await page.mouse.move(edge.x + edge.width / 2, edge.y + edge.height / 2);
  await page.mouse.down();
  await page.mouse.move(edge.x + edge.width / 2, edge.y + edge.height / 2 + 64, { steps: 4 });
  await page.mouse.up();
  assert(await resizer.getAttribute("aria-valuenow") === "384"
    && await root.locator(".assist-chat-reply-window").evaluate((node) => node.getBoundingClientRect().height) === 384
    && await root.locator(".assist-chat-composer").evaluate((node) => node.getBoundingClientRect().height) === 160,
  "Dragging the lower response edge did not resize only the conversation by the pointer delta");
  await resizer.focus();
  assert(await resizer.evaluate((node) => getComputedStyle(node, "::after").backgroundColor) === await getCssTokenColor(page, "--accent"),
    "The conversation resize edge did not use the shared blue focus treatment");
  await resizer.evaluate((node) => node.scrollIntoView({ block: "center" }));
  edge = await resizer.boundingBox();
  await page.mouse.move(edge.x + edge.width / 2, edge.y + edge.height / 2);
  await page.mouse.down();
  await page.mouse.move(edge.x + edge.width / 2, edge.y + edge.height / 2 + 16);
  const canceledHeight = await resizer.getAttribute("aria-valuenow");
  await resizer.evaluate((node) => node.dispatchEvent(new PointerEvent("pointercancel", {
    bubbles: true, pointerId: ruleAssistanceResponseResize.pointerId
  })));
  await page.mouse.move(edge.x + edge.width / 2, edge.y + edge.height / 2 + 48);
  await page.mouse.up();
  assert(await resizer.getAttribute("aria-valuenow") === canceledHeight
    && await page.evaluate(() => !ruleAssistanceResponseResize && !document.querySelector(".assist-chat-response-resizing")),
  "Pointer cancellation left a captured or moving conversation resize");
  await resizer.evaluate((node) => node.scrollIntoView({ block: "center" }));
  edge = await resizer.boundingBox();
  await page.mouse.move(edge.x + edge.width / 2, edge.y + edge.height / 2);
  await page.mouse.down();
  await page.mouse.move(edge.x + edge.width / 2, edge.y + edge.height / 2 + 8);
  const rerenderHeight = await resizer.getAttribute("aria-valuenow");
  await page.evaluate(() => syncRuleAssistance());
  await page.mouse.up();
  assert(await resizer.getAttribute("aria-valuenow") === rerenderHeight
    && await page.evaluate(() => !ruleAssistanceResponseResize && !document.querySelector(".assist-chat-response-resizing")),
  "Rerendering during a drag lost the chosen height or left pointer state behind");
  await resizer.press("Home");
  await resizer.press("ArrowUp");
  assert(await resizer.getAttribute("aria-valuenow") === "160", "Keyboard resizing did not enforce the minimum height");
  await resizer.press("ArrowDown");
  assert(await resizer.getAttribute("aria-valuenow") === "176"
    && await resizer.getAttribute("aria-valuetext") === "Conversation height 176 pixels", "Keyboard resizing did not use accessible 16-pixel steps");
  await resizer.press("End");
  await resizer.press("ArrowDown");
  assert(await resizer.getAttribute("aria-valuenow") === String(page.viewportSize().height), "Keyboard resizing exceeded the viewport height");
  await page.setViewportSize({ width: 1440, height: 600 });
  await page.waitForFunction(() => document.querySelector("[data-assist-response-resizer]").getAttribute("aria-valuemax") === "600");
  assert(await resizer.getAttribute("aria-valuenow") === "600"
    && await root.locator(".assist-chat-reply-window").evaluate((node) => node.getBoundingClientRect().height) === 600,
  "Viewport changes did not clamp the conversation and its accessible maximum together");
  await page.setViewportSize({ width: 1440, height: 900 });
  await resizer.press("Home");
  for (let step = 0; step < 10; step += 1) await resizer.press("ArrowDown");
  await page.evaluate(() => syncRuleAssistance());
  assert(await resizer.getAttribute("aria-valuenow") === "320"
    && await resizer.evaluate((node) => document.activeElement === node), "Rerendering lost the chosen height or keyboard focus");
  assert(await page.evaluate((session) => JSON.stringify(state.session) === session, setup.session)
    && await editor.inputValue() === setup.text, "Conversation resizing mutated the draft or saved session");
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
    if (holdNext) {
      holdNext = false;
      await new Promise((resolve) => { pending = async () => { await route.fulfill({ json }); resolve(); }; });
      pending = null;
    } else if (failNext) {
      failNext = false;
      await route.fulfill({ status: 500, json: { error: "Synthetic assistance failure." } });
    } else await route.fulfill({ json });
  });

  await page.evaluate(() => { globalThis.__assistanceOriginalRandom = Math.random; Math.random = () => 0; });
  await input.press("Enter");
  await page.waitForFunction(() => Boolean(ruleAssistance?.active));
  await root.locator(".waiting-panel[data-waiting-panel-ready]").waitFor();
  assert(await clear.isDisabled() && await input.getAttribute("readonly") !== null
    && await send.getAttribute("aria-label") === "Cancel operation", "Running assistance lost cancellation or read-only controls");
  const running = await root.evaluate((node) => ({
    color: getComputedStyle(node.querySelector(".assist-chat-send")).color,
    animation: getComputedStyle(node.querySelector(".waiting-panel")).animationName,
    ring: Boolean(node.querySelector(".assist-chat-send circle")),
    square: Boolean(node.querySelector(".assist-chat-send rect"))
  }));
  assert(running.color === "rgb(140, 140, 140)" && running.animation === "waiting-panel-chase" && running.ring && running.square,
    "Running assistance did not use the native border or gray ring-and-square stop icon");
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
  const summary = root.locator(".assist-chat-suggestion summary");
  const visibleChevron = () => summary.locator(".assist-chat-suggestion-chevron .codicon:visible use").getAttribute("href");
  assert(await visibleChevron() === "icons/codicons/sprite.svg#codicon-chevron-down", "Collapsed suggestions did not show the shared down chevron");
  await summary.click();
  assert(await visibleChevron() === "icons/codicons/sprite.svg#codicon-chevron-up", "Expanded suggestions did not show the shared up chevron");
  const suggestionLayout = await root.locator(".assist-chat-suggestion").evaluate((node) => {
    const summary = node.querySelector("summary");
    const guidance = summary.nextElementSibling;
    const wording = node.querySelector("pre");
    const button = node.querySelector("[data-assist-use]");
    const chevron = summary.querySelector(".assist-chat-suggestion-chevron");
    const shared = document.querySelector("[data-rule-assistance] > .information-panel");
    return {
      guidance: guidance.matches(".information-panel.assist-chat-suggestion-guidance") && guidance.nextElementSibling === wording
        && guidance.textContent.trim() === "Only fills the editor. Review and Save through the existing validation flow."
        && ["backgroundColor", "borderColor", "borderLeftWidth", "padding", "borderRadius"].every((property) => getComputedStyle(guidance)[property] === getComputedStyle(shared)[property])
        && !node.querySelector(":scope > p"),
      button: getComputedStyle(button).marginTop === "16px" && Math.abs(button.getBoundingClientRect().right - wording.getBoundingClientRect().right) < 1,
      chevron: chevron.getBoundingClientRect().width === 24 && chevron.getBoundingClientRect().height === 24
        && Math.abs(chevron.getBoundingClientRect().right - summary.getBoundingClientRect().right) < 1
        && getComputedStyle(summary).listStyleType === "none"
    };
  });
  assert(suggestionLayout.guidance && suggestionLayout.button && suggestionLayout.chevron,
    `Suggested-wording guidance or controls lost the approved shared layout: ${JSON.stringify(suggestionLayout)}`);
  await summary.press("Enter");
  assert(await root.locator(".assist-chat-suggestion").getAttribute("open") === null
    && await visibleChevron() === "icons/codicons/sprite.svg#codicon-chevron-down", "Native keyboard disclosure did not collapse the suggestion and its chevron");
  await summary.press("Enter");
  await root.locator("[data-assist-use]").click();
  await page.waitForFunction(() => document.querySelector('[data-decision-field="proposedText"]').value.endsWith("Preserve the reviewed obligations."));
  assert((await editor.inputValue()).endsWith("Preserve the reviewed obligations.")
    && await page.evaluate((session) => JSON.stringify(state.session) === session, setup.session), "Explicit wording handoff saved or staged a change");
  await editor.fill(setup.text);
  await input.fill("Follow up on that advice. ".repeat(50));
  holdNext = true;
  await send.click();
  await waitForHeldReply();
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

  await input.fill("Keep this unsent text.");
  await clear.click();
  assert(await clear.isDisabled() && await input.inputValue() === "Keep this unsent text."
    && await editor.inputValue() === setup.text, "Clear did not preserve unsent input and draft");
  failNext = true;
  await send.click();
  await root.getByText("Rule assistance failed: Synthetic assistance failure.", { exact: true }).waitFor();
  assert(await input.inputValue() === "Keep this unsent text." && requests[2].messages.length === 1, "Clearing did not reset model context or failure lost input");
  assert(!await root.locator(".assist-chat-operation-message .shimmer-heading").count(), "A genuine failure was rendered as an animated waiting phrase");
  await clear.click();
  staleNext = true;
  await send.click();
  await root.getByText("Rule assistance failed: Rule assistance returned a stale or invalid reply.", { exact: true }).waitFor();

  await clear.click();
  await send.click();
  await page.waitForFunction(() => !ruleAssistance?.active);
  const handoffReply = await page.evaluate(() => ({
    answered: Boolean(ruleAssistance?.turns[0]?.answer),
    status: ruleAssistance?.turns[0]?.status,
    input: ruleAssistance?.input
  }));
  assert(handoffReply.answered, `Suggestion race fixture did not receive a successful reply: ${JSON.stringify(handoffReply)}`);
  let releaseConfig = null;
  await page.route("**/runtime-config", async (route) => {
    const response = await route.fetch();
    await new Promise((resolve) => { releaseConfig = async () => { await route.fulfill({ response }); resolve(); }; });
  });
  await root.locator(".assist-chat-suggestion summary").click();
  await root.locator("[data-assist-use]").click();
  for (let attempt = 0; !releaseConfig && attempt < 200; attempt += 1) await page.waitForTimeout(25);
  assert(Boolean(releaseConfig), "Suggestion handoff did not check current authority");
  await clear.click();
  await releaseConfig();
  await page.getByText("The rule or assistance context changed. Ask for an updated suggestion before using this wording.", { exact: true }).waitFor();
  assert(await editor.inputValue() === setup.text, "A cleared suggestion changed the editor after its authority check");
  await page.unroute("**/runtime-config");
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
  await page.evaluate((key) => {
    const other = state.candidates.find((candidate) => candidate.key !== key);
    selectCandidate(other.key);
    selectCandidate(key);
  }, setup.key);
  assert(await clear.isDisabled() && await input.inputValue() === "" && !await root.locator(".assist-chat-user-message").count(),
    "Switching rules retained conversation context");
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
