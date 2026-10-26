"use strict";

const DATABASE_NAME = "hosted-rule-workbench";
const DATABASE_VERSION = 1;
const ACTIVE_SESSION_KEY = "hosted-rule-workbench.active-session";
const WORKBENCH_DISPLAY_SCHEMA_VERSION = 4;
const WORKBENCH_RULE_ISSUES_SCHEMA_VERSION = 4;
const SESSION_SCHEMA_VERSION = 7;
const WORKBENCH_DRAFT_SCHEMA_VERSION = 4;
const APPROVED_RULES_SCHEMA_VERSION = 4;
const DECISION_RATIONALE_MAX_LENGTH = 500;
const OVERRIDE_RATIONALE_MAX_LENGTH = 500;
const WORKBENCH_TOOLTIP_DELAY_MS = 500;
const WORKBENCH_TOOLTIP_HIDE_DELAY_MS = 150;
const PREVIEW_CONTEXT_LINE_COUNT = 2;
const PREVIEW_DIRECTIONAL_EXPAND_COUNT = 10;
const PREVIEW_TREE_DEFAULT_WIDTH = 380;
const PREVIEW_TREE_MIN_WIDTH = 296;
const PREVIEW_TREE_MAX_WIDTH = 520;
const PREVIEW_TREE_KEYBOARD_STEP = 16;
const PREVIEW_VIRTUALIZATION_BUFFER_VIEWPORTS = 2;
const PREVIEW_SCOPE_LABELS = {
  proposed: "Proposed changes",
  payload: "Payload changes",
  raw: "Resulting catalog",
  protected: "Protected rules"
};
const IMPLEMENTATION_MODELS = ["legacy", "typed", "framework"];
const RULE_ISSUE_FILTERS = [
  { key: "protected", label: "Protected", classifications: ["protected-integrity", "protected-conflict", "protected-coverage"] },
  { key: "contradiction", label: "Contradictions", classifications: ["contradiction"] },
  { key: "duplicate", label: "Duplicates", classifications: ["duplicate"] },
  { key: "overlap", label: "Overlaps", classifications: ["overlap"] }
];
const GUIDANCE_CAPACITY_BUCKETS = [
  { reportName: "repository", label: "Repository-wide Guidance", surface: "repository" },
  { reportName: "go", label: "Implementation Instructions", surface: "implementation" },
  { reportName: "test", label: "Testing Supplement", surface: "testing" },
  { reportName: "documentation", label: "Documentation Instructions", surface: "documentation" },
  { reportName: "skill", label: "Review Skill", surface: "review-skill" }
];
const FACTORS = [
  ["severity", "Severity", "Harm caused when this defect is missed", "value"],
  ["frequency", "Frequency", "How often this defect appears in provider changes", "value"],
  ["breadth", "Breadth", "How widely the rule applies across the provider", "value"],
  ["hostedDetectability", "Hosted detectability", "How reliably Hosted review can prove the defect", "value"],
  ["evidenceStrength", "Evidence strength", "How authoritative and durable the supporting evidence is", "value"],
  ["falsePositiveRisk", "False-positive risk", "Chance of producing unsupported findings", "penalty"],
  ["redundancy", "Existing coverage", "How completely current Hosted rules already cover it", "penalty"]
];

function toUtcTimestamp(value = new Date()) {
  const date = value instanceof Date ? value : new Date(value);
  if (Number.isNaN(date.getTime())) throw new Error(`Invalid timestamp: ${value}`);
  return date.toISOString().replace(/Z$/, "0000Z");
}

function normalizeTimestampProperty(target, property) {
  if (typeof target?.[property] === "string") target[property] = toUtcTimestamp(target[property]);
}

function normalizeSessionTimestamps(session) {
  const normalized = structuredClone(session);
  normalizeTimestampProperty(normalized, "createdAt");
  normalizeTimestampProperty(normalized, "updatedAt");
  Object.values(normalized.decisions || {}).forEach((decision) => normalizeTimestampProperty(decision, "updatedAt"));
  Object.values(normalized.applicabilityOverrides || {}).forEach((override) => normalizeTimestampProperty(override, "recordedAt"));
  (normalized.bulkOperations || []).forEach((operation) => normalizeTimestampProperty(operation, "createdAt"));
  return normalized;
}

const state = {
  bundle: null,
  ruleIssueBundle: null,
  session: null,
  assessedCandidates: [],
  candidates: [],
  protectedRules: [],
  ruleIssues: [],
  excludedCandidateCount: 0,
  activeKey: null,
  activeProtectedRuleId: null,
  assessmentActiveKey: null,
  assessmentOverrideEditingKey: null,
  candidatePane: "candidates",
  assessmentPane: "assessments",
  activeRuleIssueKey: null,
  ruleIssueFilter: null,
  ruleIssueTabPage: 0,
  ruleIssueSelections: {},
  ruleIssueResolutionHistory: [],
  dismissedRuleIssueBannerKeys: new Set(),
  rationaleReturnView: null,
  workspaceTab: "candidate-sources",
  currentView: "catalog",
  queries: {
    "candidate-sources": "",
    "assessment-results": "",
    "rule-issues": ""
  },
  candidateSorts: {},
  assessmentSorts: {},
  planSort: { field: "candidate", direction: "ascending" },
  planAttentionOnly: false
};

const elements = {};
let databasePromise;
let persistencePromise = Promise.resolve();
let toastTimer;
let truncationTooltipFrame;
let ruleIssueTabPaginationFrame;
let candidateHierarchicalView;
let assessmentHierarchicalView;
let previewFilesByScope = { proposed: [], payload: [], raw: [], protected: [] };
let previewBodyVirtualizer;
let previewVirtualizationResizeTimer;
const previewExpandedScopes = new Set(Object.keys(PREVIEW_SCOPE_LABELS));
let previewSelectedFilePath = "";
let previewTreeResizePointerId = null;
const candidateExpansionState = new Map();
const assessmentExpansionState = new Map();
const ruleAssistanceChats = new Map();
let ruleAssistance = null;
let ruleAssistanceExpanded = true;
let ruleAssistanceSidebarWidth = 420;
let ruleAssistanceSidebarResize = null;
let ruleAssistanceWaitingPhrases;
let llmBrandMap = [];
const expandedEvidencePanels = new Set();
const sourceRuleDisclosureStates = new Map();
const activeRuleIssueRecommendations = new Set();
const shimmerHeadingAnimations = new Set();
let shimmerHeadingStyleSheet;
const waitingPanels = new Map();
let waitingPanelStyleSheet;
let waitingPanelResizeObserver;
let waitingPanelMutationObserver;
let waitingPanelSequence = 0;
let waitingPanelGeometryFrame = 0;
const workbenchTooltip = {
  anchorX: 0,
  owner: null,
  hideTimer: 0,
  showTimer: 0,
  suppressedOwner: null
};
function icon(name) {
  if (!/^[a-z0-9-]+$/.test(name)) throw new Error(`Invalid Codicon name: ${name}`);
  return `<svg class="codicon" aria-hidden="true"><use href="icons/codicons/sprite.svg#codicon-${name}"></use></svg>`;
}

function llmIcon(name) {
  if (!/^[a-z0-9]+$/.test(name)) throw new Error(`Invalid LLM icon name: ${name}`);
  return `<svg class="llm-icon" aria-hidden="true"><use href="icons/llms/sprite.svg#llm-${name}"></use></svg>`;
}

function validateLlmBrandMap(entries) {
  if (!Array.isArray(entries) || !entries.length || entries.length > 128) throw new Error("LLM branding map requires a bounded nonempty array");
  const prefixes = [];
  for (const entry of entries) {
    if (!entry || Object.keys(entry).sort().join(",") !== "icon,prefix"
      || typeof entry.prefix !== "string" || !/^[a-z0-9]+(?:[.-][a-z0-9]+)*-$/.test(entry.prefix)
      || typeof entry.icon !== "string" || !/^[a-z0-9]+$/.test(entry.icon)) throw new Error("LLM branding map contains an invalid prefix or icon");
    if (prefixes.some(prefix => prefix.startsWith(entry.prefix) || entry.prefix.startsWith(prefix))) throw new Error("LLM branding map contains duplicate or ambiguous prefixes");
    prefixes.push(entry.prefix);
  }
  return entries;
}

function renderLlmModelIcon(model) {
  const brand = typeof model === "string" ? llmBrandMap.find(entry => model.startsWith(entry.prefix)) : null;
  return brand ? llmIcon(brand.icon) : icon("question");
}

function renderShimmerHeading(text) {
  const characters = [...new Intl.Segmenter(undefined, { granularity: "grapheme" }).segment(text)].map((item) => item.segment);
  const steps = characters.length + 7;
  const animationName = `shimmer-heading-${steps}`;
  if (!shimmerHeadingStyleSheet) {
    shimmerHeadingStyleSheet = new CSSStyleSheet();
    document.adoptedStyleSheets = [...document.adoptedStyleSheets, shimmerHeadingStyleSheet];
  }
  if (!shimmerHeadingAnimations.has(steps)) {
    // Length-dependent timing keeps one seven-character band across the complete label.
    const stops = [[0, "soft"], [1, "bright"], [2, "peak"], [5, "bright"], [6, "soft"], [7, "base"], [steps, "base"]];
    const keyframes = stops.map(([step, color]) => `${100 * step / steps}% { color: var(--shimmer-${color}-color); }`).join(" ");
    shimmerHeadingStyleSheet.insertRule(`@keyframes ${animationName} { ${keyframes} }`);
    const selector = `.shimmer-heading[data-shimmer-steps="${steps}"]`;
    shimmerHeadingStyleSheet.insertRule(`${selector} { --shimmer-animation: ${animationName}; --shimmer-cycle-steps: ${steps}; }`);
    characters.forEach((character, index) => {
      shimmerHeadingStyleSheet.insertRule(`${selector} .shimmer-character:nth-child(${index + 1}) { --shimmer-index: ${index}; }`);
    });
    shimmerHeadingAnimations.add(steps);
  }
  const visual = characters.map((character) => `<span class="shimmer-character">${escapeHtml(character)}</span>`).join("");
  return `<strong class="shimmer-heading" data-shimmer-steps="${steps}"><span class="sr-only">${escapeHtml(text)}</span><span class="shimmer-characters" aria-hidden="true">${visual}</span></strong>`;
}

function renderWaitingPanel({ title, body, elapsed = null, action = "" }) {
  if (typeof title !== "string" || !title.trim() || typeof body !== "string" || !body.trim()) {
    throw new Error("Waiting panels require non-empty title and body text");
  }
  if (!waitingPanelStyleSheet) {
    waitingPanelStyleSheet = new CSSStyleSheet();
    document.adoptedStyleSheets = [...document.adoptedStyleSheets, waitingPanelStyleSheet];
    waitingPanelResizeObserver = new ResizeObserver(scheduleWaitingPanelGeometry);
    waitingPanelMutationObserver = new MutationObserver(syncWaitingPanels);
    waitingPanelMutationObserver.observe(document.body, { childList: true, subtree: true, attributes: true, attributeFilter: ["hidden"] });
    window.addEventListener("resize", scheduleWaitingPanelGeometry, { passive: true });
    window.addEventListener("scroll", scheduleWaitingPanelGeometry, { passive: true, capture: true });
  }
  return `<div class="waiting-panel" role="status" aria-live="polite" aria-atomic="true">
    <div class="waiting-panel-heading"><span class="waiting-panel-spinner" aria-hidden="true"></span>${renderShimmerHeading(title)}</div>
    <div class="waiting-panel-body"><span class="waiting-panel-copy">${escapeHtml(body)}${elapsed === null ? "" : ` <span class="waiting-panel-elapsed" role="timer" aria-live="off">${escapeHtml(elapsed)}</span>`}</span>${action}</div>
    <span class="waiting-panel-frame waiting-panel-glow" aria-hidden="true"></span>
    <span class="waiting-panel-frame waiting-panel-border" aria-hidden="true"></span>
  </div>`;
}

function syncWaitingPanels() {
  for (const [panel, record] of waitingPanels) {
    if (panel.isConnected) continue;
    waitingPanelResizeObserver.unobserve(panel);
    waitingPanelStyleSheet.deleteRule([...waitingPanelStyleSheet.cssRules].indexOf(record.rule));
    panel.removeAttribute("data-waiting-panel");
    panel.removeAttribute("data-waiting-panel-ready");
    waitingPanels.delete(panel);
  }
  for (const panel of document.querySelectorAll(".waiting-panel")) {
    if (waitingPanels.has(panel)) continue;
    const frame = panel.querySelector(".waiting-panel-border");
    if (!frame) throw new Error("Waiting panel is missing its border frame");
    panel.dataset.waitingPanel = String(++waitingPanelSequence);
    const index = waitingPanelStyleSheet.insertRule(`.waiting-panel[data-waiting-panel="${waitingPanelSequence}"] {}`, waitingPanelStyleSheet.cssRules.length);
    waitingPanels.set(panel, { rule: waitingPanelStyleSheet.cssRules[index], frame, signature: "", paletteSize: "" });
    waitingPanelResizeObserver.observe(panel);
  }
  if (!waitingPanels.size) {
    cancelAnimationFrame(waitingPanelGeometryFrame);
    waitingPanelGeometryFrame = 0;
    return;
  }
  scheduleWaitingPanelGeometry();
}

function scheduleWaitingPanelGeometry() {
  if (!waitingPanels.size || waitingPanelGeometryFrame) return;
  waitingPanelGeometryFrame = requestAnimationFrame(() => {
    waitingPanelGeometryFrame = 0;
    for (const [panel, record] of waitingPanels) updateWaitingPanelGeometry(panel, record);
  });
}

function updateWaitingPanelGeometry(panel, record) {
  const rect = panel.getBoundingClientRect();
  if (!rect.width || !rect.height) {
    record.signature = "";
    return;
  }
  const scale = window.devicePixelRatio;
  const signature = [rect.left, rect.top, rect.right, rect.bottom, scale].join(",");
  if (record.signature === signature) return;
  const snap = (value) => Math.round(value * scale) / scale;
  const left = snap(rect.left);
  const top = snap(rect.top);
  const width = snap(rect.right) - left;
  const height = snap(rect.bottom) - top;
  const computed = getComputedStyle(panel);
  const style = record.rule.style;
  style.setProperty("--waiting-panel-pixel", `${1 / scale}px`);
  style.setProperty("--waiting-panel-left", `${left - rect.left - parseFloat(computed.borderLeftWidth)}px`);
  style.setProperty("--waiting-panel-top", `${top - rect.top - parseFloat(computed.borderTopWidth)}px`);
  style.setProperty("--waiting-panel-width", `${width}px`);
  style.setProperty("--waiting-panel-height", `${height}px`);
  style.setProperty("--waiting-panel-length", `${2 * (width + height)}px`);
  style.setProperty("--waiting-panel-band", `${Math.max(8, 2 * parseFloat(computed.borderTopLeftRadius))}px`);
  style.setProperty("--waiting-panel-translate-x", "0px");
  style.setProperty("--waiting-panel-translate-y", "0px");
  // Correct layout-unit rounding without scaling the one-device-pixel stroke.
  const frame = record.frame.getBoundingClientRect();
  style.setProperty("--waiting-panel-translate-x", `${left - frame.left}px`);
  style.setProperty("--waiting-panel-translate-y", `${top - frame.top}px`);
  const paletteSize = `${width},${height}`;
  if (record.paletteSize !== paletteSize) {
    style.setProperty("--waiting-panel-palette", buildWaitingPanelPalette(width, height));
    record.paletteSize = paletteSize;
  }
  panel.setAttribute("data-waiting-panel-ready", "");
  record.signature = signature;
}

function buildWaitingPanelPalette(width, height) {
  const perimeter = 2 * (width + height);
  const anchors = [[-0.125, "blue"], [0.125, "green"], [0.375, "purple"], [0.625, "green"], [0.875, "blue"], [1.125, "green"]];
  const fractions = new Set(Array.from({ length: 129 }, (_, index) => index / 128));
  for (const corner of [width / 2, width / 2 + height, 1.5 * width + height, 1.5 * width + 2 * height]) fractions.add(corner / perimeter);
  const stops = [...fractions].sort((a, b) => a - b).map((fraction) => {
    let distance = fraction * perimeter;
    let x;
    let y;
    if (distance <= width / 2) [x, y] = [width / 2 + distance, 0];
    else if ((distance -= width / 2) <= height) [x, y] = [width, distance];
    else if ((distance -= height) <= width) [x, y] = [width - distance, height];
    else if ((distance -= width) <= height) [x, y] = [0, height - distance];
    else [x, y] = [distance - height, 0];
    const angle = fraction === 0 ? 0 : fraction === 1 ? 360 : (Math.atan2(x - width / 2, height / 2 - y) * 180 / Math.PI + 360) % 360;
    let index = 0;
    while (fraction > anchors[index + 1][0]) index += 1;
    const [start, startColor] = anchors[index];
    const [end, endColor] = anchors[index + 1];
    const mix = (fraction - start) / (end - start);
    const color = `color-mix(in srgb, var(--waiting-panel-${startColor}) ${(100 * (1 - mix)).toFixed(6)}%, var(--waiting-panel-${endColor}))`;
    return `${color} ${angle.toFixed(7)}deg`;
  });
  return `conic-gradient(from 0deg in srgb, ${stops.join(", ")})`;
}

function octicon(name) {
  if (!/^[a-z0-9-]+$/.test(name)) throw new Error(`Invalid Octicon name: ${name}`);
  return `<svg class="octicon" aria-hidden="true"><use href="icons/octicons/sprite.svg#octicon-${name}-16"></use></svg>`;
}

const CORE_FLUENT_ICON_NAMES = new Set([
  "checkmark-circle-20-regular",
  "checkmark-circle-20-filled",
  "dismiss-circle-20-regular",
  "dismiss-circle-20-filled",
  "error-circle-20-regular",
  "error-circle-20-filled",
  "important-20-regular",
  "important-20-filled",
  "info-20-regular",
  "info-20-filled",
  "question-circle-20-regular",
  "question-circle-20-filled",
  "warning-20-regular",
  "warning-20-filled",
  "shield-checkmark-20-regular",
  "shield-checkmark-20-filled",
  "shield-dismiss-20-regular",
  "shield-dismiss-20-filled",
  "shield-error-20-regular",
  "shield-error-20-filled",
  "shield-question-20-regular",
  "shield-question-20-filled",
  "shield-task-20-regular",
  "shield-task-20-filled",
  "document-add-20-regular",
  "document-add-20-filled",
  "document-bullet-list-20-regular",
  "document-bullet-list-20-filled",
  "document-checkmark-20-regular",
  "document-checkmark-20-filled",
  "document-dismiss-20-regular",
  "document-dismiss-20-filled",
  "document-edit-20-regular",
  "document-edit-20-filled",
  "document-error-20-regular",
  "document-error-20-filled",
  "document-lock-20-regular",
  "document-lock-20-filled",
  "document-search-20-regular",
  "document-search-20-filled",
  "document-sync-20-regular",
  "document-sync-20-filled",
  "document-text-20-regular",
  "document-text-20-filled",
  "approvals-app-20-regular",
  "approvals-app-20-filled",
  "arrow-sync-circle-20-regular",
  "arrow-sync-circle-20-filled",
  "book-information-20-regular",
  "book-information-20-filled",
  "bot-sparkle-20-regular",
  "bot-sparkle-20-filled",
  "brain-circuit-20-regular",
  "brain-circuit-20-filled",
  "certificate-20-regular",
  "certificate-20-filled",
  "clipboard-checkmark-20-regular",
  "clipboard-checkmark-20-filled",
  "clipboard-task-list-ltr-20-regular",
  "clipboard-task-list-ltr-20-filled",
  "data-usage-20-regular",
  "data-usage-20-filled",
  "gauge-20-regular",
  "gauge-20-filled",
  "history-20-regular",
  "history-20-filled",
  "lightbulb-20-regular",
  "lightbulb-20-filled",
  "person-feedback-20-regular",
  "person-feedback-20-filled",
  "target-arrow-20-regular",
  "target-arrow-20-filled",
  "arrow-routing-20-regular",
  "arrow-routing-20-filled",
  "arrow-routing-rectangle-multiple-20-regular",
  "arrow-routing-rectangle-multiple-20-filled",
  "arrow-split-20-regular",
  "arrow-split-20-filled",
  "flow-20-regular",
  "flow-20-filled",
  "flowchart-20-regular",
  "flowchart-20-filled",
  "link-multiple-20-regular",
  "link-multiple-20-filled",
  "connected-20-regular",
  "connected-20-filled",
  "group-list-20-regular",
  "group-list-20-filled",
  "shape-intersect-20-regular",
  "shape-intersect-20-filled",
  "merge-20-regular",
  "merge-20-filled",
  "stack-20-regular",
  "stack-20-filled",
  "stack-arrow-forward-20-regular",
  "stack-arrow-forward-20-filled",
  "gavel-20-regular",
  "gavel-20-filled",
  "gavel-prohibited-20-regular",
  "gavel-prohibited-20-filled",
  "scales-20-regular",
  "scales-20-filled",
  "checkbox-checked-sync-20-regular",
  "checkbox-checked-sync-20-filled",
  "flag-checkered-20-regular",
  "flag-checkered-20-filled",
  "ribbon-20-regular",
  "ribbon-20-filled",
  "ribbon-off-20-regular",
  "ribbon-off-20-filled",
  "person-edit-20-regular",
  "person-edit-20-filled",
  "archive-20-regular",
  "archive-20-filled",
  "archive-arrow-back-20-regular",
  "archive-arrow-back-20-filled",
  "arrow-undo-20-regular",
  "arrow-undo-20-filled",
  "arrow-redo-20-regular",
  "arrow-redo-20-filled",
  "arrow-sync-checkmark-20-regular",
  "arrow-sync-checkmark-20-filled",
  "arrow-sync-dismiss-20-regular",
  "arrow-sync-dismiss-20-filled",
  "re-order-20-regular",
  "re-order-20-filled",
  "document-copy-20-regular",
  "document-copy-20-filled",
  "document-arrow-right-20-regular",
  "document-arrow-right-20-filled",
  "clipboard-search-20-regular",
  "clipboard-search-20-filled",
  "clipboard-text-ltr-20-regular",
  "clipboard-text-ltr-20-filled",
  "text-quote-20-regular",
  "text-quote-20-filled",
  "database-search-20-regular",
  "database-search-20-filled",
  "task-list-square-sparkle-20-regular",
  "task-list-square-sparkle-20-filled",
  "wand-20-regular",
  "wand-20-filled"
]);

function fluentIcon(name, className = "") {
  if (!CORE_FLUENT_ICON_NAMES.has(name) && !/^[a-z0-9]+(?:-[a-z0-9]+)*-(16|20)-(regular|filled)$/.test(name)) throw new Error(`Invalid Fluent icon name: ${name}`);
  return `<svg class="fluent-icon ${escapeHtml(className)}" aria-hidden="true"><use href="icons/fluent/sprite.svg#fluent-${name}"></use></svg>`;
}

function renderInformationPanel(content, { iconMarkup = fluentIcon("info-20-regular"), className = "", dataAttributes = {} } = {}) {
  const attributes = Object.entries(dataAttributes)
    .map(([name, value]) => ` data-${name}="${escapeHtml(value)}"`)
    .join("");
  return `<div class="information-panel${className ? ` ${escapeHtml(className)}` : ""}"${attributes}>${iconMarkup}${content}</div>`;
}

function renderPreviewEmptyState(iconName, title, message, className = "") {
  return `<div class="empty-state compact preview-empty-state ${escapeHtml(className)}">${icon(iconName)}<h3>${escapeHtml(title)}</h3><p>${escapeHtml(message)}</p></div>`;
}

function renderSortButton(column, sort, dataAttributes) {
  const [key, label, accessibleLabel, help] = column;
  const active = sort.field === key;
  const nextDirection = active && sort.direction === "ascending" ? "descending" : "ascending";
  const attributes = Object.entries(dataAttributes)
    .map(([name, value]) => `data-${name}="${escapeHtml(value)}"`)
    .join(" ");
  return `<button class="candidate-sort-button clickable ${active ? "active" : ""}" type="button" ${attributes} aria-label="Sort by ${escapeHtml(accessibleLabel)}, ${nextDirection}" data-workbench-tooltip="${escapeHtml(help)}" ${active ? 'aria-pressed="true"' : ""}><span class="sort-label">${escapeHtml(label)}</span><span class="sort-indicator" aria-hidden="true">${icon(`chevron-${active && sort.direction === "ascending" ? "up" : "down"}`)}</span></button>`;
}

const mobileDeviceDetected = window.matchMedia("(max-width: 767.98px)").matches || navigator.userAgentData?.mobile === true || /Android|iPhone|iPad|iPod|Mobile/i.test(navigator.userAgent);
if (mobileDeviceDetected) document.documentElement.classList.add("mobile-unsupported");

document.addEventListener("DOMContentLoaded", async () => {
  if (mobileDeviceDetected) return;
  workbenchStatusBar.render();
  captureElements();
  bindEvents();
  await loadBundle();
  refreshPresentation();
});

function captureElements() {
  for (const id of [
    "target-chip", "status-target", "status-surface-tooltip", "close-button", "draft-menu", "export-button", "import-input", "catalog-count", "plan-count",
    "assist-panel-toggle", "rule-assistance-panel", "assist-sidebar-content", "assist-sidebar-resizer",
    "promotion-plan-stage", "promotion-plan-stage-icon", "plan-activity-count",
    "status-excluded", "status-mapped", "status-unmapped", "status-headroom", "preview-status", "save-indicator", "search-input",
    "candidate-list", "candidate-panel", "candidate-sticky-stack", "assessment-panel", "candidate-pane-candidates", "candidate-pane-details", "candidate-sources-panel", "assessment-results-panel", "rule-issues-panel",
    "bulk-actions", "bulk-scope-count", "bulk-add-count", "bulk-update-count", "bulk-actionable-count", "bulk-undo", "bulk-undo-count", "bulk-actions-note",
    "assessment-results-list", "assessment-sticky-stack", "assessment-results-detail", "rule-issues-tab-count", "rule-issue-tab-pager", "rule-issue-tab-viewport", "rule-issues-previous", "rule-issues-filters", "rule-issues-next", "rule-issues-list", "rule-issues-detail", "rule-issues-status", "rule-issues-status-count",
    "return-catalog-button", "plan-attention-filter", "plan-attention-count", "plan-undo-menu", "plan-undo-trigger", "plan-undo-all-count", "plan-undo-manual-count", "plan-undo-bulk-count", "plan-undo-override-count", "plan-table-head", "plan-table-body", "empty-plan", "capacity-panel", "approval-badge",
    "preview-summary", "preview-tree-resizer", "preview-diff", "preview-payload-diff", "preview-json", "preview-protected", "preview-protected-section", "preview-code",
    "preview-review-toolbar",
    "preview-review-context", "preview-review-toggle", "preview-review-popover", "preview-review-close", "approval-requirements",
    "approve-export-button", "workspace", "toast", "toast-message", "toast-close"
  ]) {
    elements[id] = document.getElementById(id);
  }
}

function bindEvents() {
  document.addEventListener("pointerover", handleWorkbenchTooltipPointerOver);
  document.addEventListener("pointermove", handleWorkbenchTooltipPointerMove);
  document.addEventListener("pointerout", handleWorkbenchTooltipPointerOut);
  document.addEventListener("pointerdown", handleWorkbenchTooltipPointerDown);
  document.addEventListener("focusin", handleWorkbenchTooltipFocusIn);
  document.addEventListener("focusout", handleWorkbenchTooltipFocusOut);
  document.querySelectorAll("[data-view]").forEach((button) => {
    button.addEventListener("click", () => switchView(button.dataset.view));
  });
  elements["return-catalog-button"].addEventListener("click", () => switchView("catalog"));
  elements["plan-attention-filter"].addEventListener("click", () => {
    state.planAttentionOnly = !state.planAttentionOnly;
    renderPlan();
  });
  elements["plan-undo-menu"].addEventListener("click", handlePlanUndoMenuClick);
  elements["plan-undo-menu"].addEventListener("mouseleave", () => elements["plan-undo-menu"].removeAttribute("open"));
  elements["close-button"].addEventListener("click", closeWorkbench);
  elements["assist-panel-toggle"].addEventListener("click", () => setRuleAssistanceExpanded(!ruleAssistanceExpanded));
  elements["assist-sidebar-resizer"].addEventListener("pointerdown", handleAssistanceSidebarResizeStart);
  elements["assist-sidebar-resizer"].addEventListener("pointermove", handleAssistanceSidebarResizeMove);
  elements["assist-sidebar-resizer"].addEventListener("pointerup", finishAssistanceSidebarResize);
  elements["assist-sidebar-resizer"].addEventListener("pointercancel", finishAssistanceSidebarResize);
  elements["assist-sidebar-resizer"].addEventListener("lostpointercapture", finishAssistanceSidebarResize);
  elements["assist-sidebar-resizer"].addEventListener("keydown", handleAssistanceSidebarResizeKeyboard);
  setAssistanceSidebarWidth(ruleAssistanceSidebarWidth);
  setRuleAssistanceExpanded(ruleAssistanceExpanded);
  elements["export-button"].addEventListener("click", () => {
    exportDraft();
    elements["draft-menu"].removeAttribute("open");
  });
  elements["import-input"].addEventListener("change", async (event) => {
    await importDraft(event);
    elements["draft-menu"].removeAttribute("open");
  });
  elements["search-input"].addEventListener("input", (event) => updateFilter(event.target.value));
  document.querySelector(".ide-statusbar").addEventListener("click", handleStatusNavigation);
  elements["rule-issues-filters"].addEventListener("click", (event) => {
    const filter = event.target.closest("[data-rule-issue-filter]")?.dataset.ruleIssueFilter;
    if (!filter) return;
    if (state.activeRuleIssueKey) rememberRuleIssueSelection(state.activeRuleIssueKey);
    state.ruleIssueFilter = filter;
    state.activeRuleIssueKey = state.ruleIssueSelections[filter]?.issueId || null;
    renderRuleIssues();
  });
  elements["rule-issues-previous"].addEventListener("click", () => changeRuleIssueTabPage(-1));
  elements["rule-issues-next"].addEventListener("click", () => changeRuleIssueTabPage(1));
  window.addEventListener("resize", () => scheduleRuleIssueTabPagination(true));
  elements["rule-issues-list"].addEventListener("click", (event) => {
    const key = event.target.closest("[data-rule-issue-key]")?.dataset.ruleIssueKey;
    if (!key) return;
    state.activeRuleIssueKey = key;
    rememberRuleIssueSelection(key);
    renderRuleIssues();
  });
  elements["rule-issues-detail"].addEventListener("click", handleRuleIssueDetailClick);
  elements["bulk-actions"].addEventListener("click", handleBulkActionsClick);
  elements["bulk-actions"].addEventListener("mouseleave", handleBulkActionsMouseLeave);
  document.querySelectorAll("[data-workspace-tab]").forEach((button) => {
    button.addEventListener("click", () => setWorkspaceTab(button.dataset.workspaceTab));
  });
  document.querySelectorAll("[data-candidate-pane]").forEach((button) => {
    button.addEventListener("click", () => showCandidatePane(button.dataset.candidatePane));
  });
  document.querySelectorAll("[data-assessment-pane]").forEach((button) => {
    button.addEventListener("click", () => showAssessmentPane(button.dataset.assessmentPane));
  });
  elements["candidate-list"].addEventListener("click", (event) => {
    const sortButton = event.target.closest("[data-candidate-sort]");
    if (sortButton) {
      updateCandidateSort(sortButton);
      return;
    }
    if (event.target.closest('input[type="checkbox"], summary')) return;
    const protectedRow = event.target.closest("[data-protected-rule-id]");
    if (protectedRow) {
      selectProtectedRule(protectedRow.dataset.protectedRuleId);
      showCandidatePane("details");
      return;
    }
    const row = event.target.closest("[data-candidate-key]");
    if (row) {
      selectCandidate(row.dataset.candidateKey);
      showCandidatePane("details");
    }
  });
  elements["candidate-list"].addEventListener("change", handleTreeSelection);
  elements["candidate-list"].addEventListener("keydown", (event) => {
    const protectedRow = event.target.closest("[data-protected-rule-id]");
    if (protectedRow && ["Enter", " "].includes(event.key)) {
      event.preventDefault();
      selectProtectedRule(protectedRow.dataset.protectedRuleId);
      showCandidatePane("details");
      return;
    }
    handleRowKeyboardNavigation(event, elements["candidate-list"], "candidateKey", selectCandidate, () => showCandidatePane("details"));
  });
  elements["assessment-results-list"].addEventListener("click", (event) => {
    const sortButton = event.target.closest("[data-assessment-sort]");
    if (sortButton) {
      updateAssessmentSort(sortButton);
      return;
    }
    const overrideDetail = event.target.closest("[data-assessment-override-detail]");
    if (overrideDetail) {
      openAssessmentOverride(overrideDetail.dataset.assessmentOverrideDetail);
      return;
    }
    const row = event.target.closest("[data-assessment-key]");
    if (row) {
      selectAssessmentResult(row.dataset.assessmentKey);
      showAssessmentPane("details");
    }
  });
  elements["assessment-results-list"].addEventListener("keydown", (event) => {
    if (event.target.closest("button, input, a, label")) return;
    handleRowKeyboardNavigation(event, elements["assessment-results-list"], "assessmentKey", selectAssessmentResult, () => showAssessmentPane("details"));
  });
  elements["assessment-results-detail"].addEventListener("click", handleApplicabilityOverrideClick);
  elements["assessment-results-detail"].addEventListener("input", handleApplicabilityOverrideInput);
  elements["assessment-panel"].addEventListener("click", handleAssessmentClick);
  elements["assessment-panel"].addEventListener("input", handleAssessmentInput);
  elements["assist-sidebar-content"].addEventListener("click", handleRuleAssistanceClick);
  elements["assist-sidebar-content"].addEventListener("input", handleRuleAssistanceInput);
  elements["assist-sidebar-content"].addEventListener("scroll", handleDetailContentScroll, true);
  elements["assist-sidebar-content"].addEventListener("keydown", (event) => {
    if (!event.target.matches(".assist-goal") || event.key !== "Enter" || event.shiftKey || event.ctrlKey || event.altKey || event.metaKey || event.isComposing || event.repeat) return;
    event.preventDefault();
    if (!ruleAssistance?.active) void sendRuleAssistance();
  });
  for (const panel of [elements["assessment-panel"], elements["assessment-results-detail"]]) {
    panel.addEventListener("click", handleEvidenceDisclosureClick);
    panel.addEventListener("toggle", (event) => {
      if (event.target.matches("details[data-source-rule-key]")) sourceRuleDisclosureStates.set(event.target.dataset.sourceRuleKey, event.target.open);
    }, true);
  }
  [elements["assessment-panel"], elements["assessment-results-detail"]].forEach((panel) => {
    panel.addEventListener("click", handleDetailBackToTopClick);
    panel.addEventListener("scroll", handleDetailContentScroll, true);
  });
  elements["plan-table-body"].addEventListener("click", (event) => {
    const undo = event.target.closest("[data-plan-undo]");
    if (undo) {
      const candidate = state.assessedCandidates.find((item) => item.key === undo.dataset.planUndo);
      if (candidate) undoDecision(candidate);
      return;
    }
    const detail = event.target.closest("[data-plan-detail]");
    if (detail) {
      openPlanCandidate(detail.dataset.planDetail, "attention");
      return;
    }
    const action = event.target.closest("[data-plan-action]");
    if (action) {
      openPlanCandidate(action.dataset.planAction, "attention");
      return;
    }
    if (event.target.closest("button, input, a, label")) return;
    const row = event.target.closest("[data-plan-row]");
    if (row) openPlanCandidate(row.dataset.planRow);
  });
  elements["plan-table-body"].addEventListener("keydown", handlePlanRowKeyboardNavigation);
  elements["plan-table-head"].addEventListener("click", (event) => {
    const sortButton = event.target.closest("[data-plan-sort]");
    if (sortButton) updatePlanSort(sortButton);
  });
  elements["preview-summary"].addEventListener("input", handlePreviewFileFilter);
  elements["preview-summary"].addEventListener("click", handlePreviewFileNavigation);
  elements["preview-tree-resizer"].addEventListener("pointerdown", handlePreviewTreeResizeStart);
  elements["preview-tree-resizer"].addEventListener("pointermove", handlePreviewTreeResizeMove);
  elements["preview-tree-resizer"].addEventListener("pointerup", handlePreviewTreeResizeEnd);
  elements["preview-tree-resizer"].addEventListener("pointercancel", handlePreviewTreeResizeEnd);
  elements["preview-tree-resizer"].addEventListener("keydown", handlePreviewTreeResizeKeyboard);
  setPreviewTreeWidth(PREVIEW_TREE_DEFAULT_WIDTH);
  elements["preview-review-toolbar"].addEventListener("click", handlePreviewReviewClick);
  document.addEventListener("click", handlePreviewReviewOutsideInteraction, true);
  document.addEventListener("pointerdown", handlePreviewReviewOutsideInteraction, { passive: true, capture: true });
  document.addEventListener("wheel", handlePreviewReviewOutsideInteraction, { passive: true, capture: true });
  document.addEventListener("touchmove", handlePreviewReviewOutsideInteraction, { passive: true, capture: true });
  document.addEventListener("keydown", handlePreviewReviewOutsideInteraction, true);
  elements["preview-code"].addEventListener("click", handlePreviewReviewClick);
  elements["preview-code"].addEventListener("change", handlePreviewReviewChange);
  elements["approve-export-button"].addEventListener("click", approveAndExport);
  elements["toast-close"].addEventListener("click", dismissNotification);
  document.addEventListener("keydown", (event) => {
    if (event.key === "Escape" && workbenchTooltip.owner) {
      workbenchTooltip.suppressedOwner = workbenchTooltip.owner;
      hideStatusTooltip();
    }
    const scoringLegendDialog = elements["assessment-panel"].querySelector("[data-scoring-legend-dialog]");
    if (event.key === "Escape" && scoringLegendDialog?.open) {
      scoringLegendDialog.close();
      return;
    }
    if (event.key === "Escape" && elements.toast.classList.contains("visible")) dismissNotification();
    if (event.key === "Escape") elements["preview-review-popover"].hidden = true;
  });
  window.addEventListener("resize", hideStatusTooltip);
  window.addEventListener("resize", scheduleTruncationTooltips);
  window.addEventListener("resize", () => {
    candidateHierarchicalView?.refreshLayout();
    assessmentHierarchicalView?.refreshLayout();
    setPreviewTreeWidth(Number(elements["preview-tree-resizer"].getAttribute("aria-valuenow")));
    setAssistanceSidebarWidth(ruleAssistanceSidebarWidth);
    schedulePreviewBodyVirtualizerRefresh();
  });
}

function isWorkbenchTooltipDisabled(owner) {
  return Boolean(owner?.closest(":disabled, [aria-disabled='true'], .disabled"));
}

function getWorkbenchPixelMetric(name) {
  const value = getComputedStyle(document.documentElement).getPropertyValue(name).trim();
  const pixels = Number.parseFloat(value);
  if (!value.endsWith("px") || !Number.isFinite(pixels) || pixels <= 0) throw new Error(`Invalid Workbench pixel metric: ${name}`);
  return pixels;
}

function showWorkbenchTooltip(item, anchorX = item.getBoundingClientRect().left + item.getBoundingClientRect().width / 2) {
  if (isWorkbenchTooltipDisabled(item)) {
    hideStatusTooltip();
    return;
  }
  if (workbenchTooltip.suppressedOwner === item) return;
  const value = item.dataset.workbenchTooltip || (item.hasAttribute("data-truncation-tooltip") ? item.textContent.trim() : "");
  if (!value) return;

  cancelWorkbenchTooltipShow();
  cancelWorkbenchTooltipHide();
  workbenchTooltip.owner = item;
  const tooltip = elements["status-surface-tooltip"];
  const inset = getWorkbenchPixelMetric("--tooltip-viewport-inset");
  const gap = getWorkbenchPixelMetric("--tooltip-gap");
  tooltip.textContent = value;
  tooltip.style.left = `${inset}px`;
  tooltip.style.top = `${inset}px`;
  tooltip.classList.add("visible");
  tooltip.setAttribute("aria-hidden", "false");

  const itemRect = item.getBoundingClientRect();
  const tooltipRect = tooltip.getBoundingClientRect();
  const preferredLeft = anchorX - tooltipRect.width / 2;
  const left = Math.floor(Math.min(Math.max(inset, preferredLeft), Math.max(inset, window.innerWidth - tooltipRect.width - inset)));
  const below = itemRect.bottom + gap;
  const above = itemRect.top - tooltipRect.height - gap;
  const preferredTop = below + tooltipRect.height + inset <= window.innerHeight
    ? below
    : above;
  const top = Math.floor(Math.min(Math.max(inset, preferredTop), Math.max(inset, window.innerHeight - tooltipRect.height - inset)));
  tooltip.style.left = `${left}px`;
  tooltip.style.top = `${top}px`;
}

function getWorkbenchTooltipOwner(target) {
  const owner = target.closest?.("[data-workbench-tooltip], [data-truncation-tooltip]");
  return owner && !isWorkbenchTooltipDisabled(owner) ? owner : null;
}

function cancelWorkbenchTooltipShow() {
  if (workbenchTooltip.showTimer) window.clearTimeout(workbenchTooltip.showTimer);
  workbenchTooltip.showTimer = 0;
}

function cancelWorkbenchTooltipHide() {
  if (workbenchTooltip.hideTimer) window.clearTimeout(workbenchTooltip.hideTimer);
  workbenchTooltip.hideTimer = 0;
}

function isWorkbenchTooltipActive() {
  const owner = workbenchTooltip.owner;
  return Boolean(owner?.isConnected && !isWorkbenchTooltipDisabled(owner)
    && (owner.matches(":hover, :focus-within") || elements["status-surface-tooltip"].matches(":hover")));
}

function scheduleWorkbenchTooltipHide() {
  if (isWorkbenchTooltipActive()) { cancelWorkbenchTooltipHide(); return; }
  cancelWorkbenchTooltipShow();
  if (!workbenchTooltip.owner || workbenchTooltip.hideTimer) return;
  workbenchTooltip.hideTimer = window.setTimeout(() => {
    workbenchTooltip.hideTimer = 0;
    if (!isWorkbenchTooltipActive()) hideStatusTooltip();
  }, WORKBENCH_TOOLTIP_HIDE_DELAY_MS);
}

function scheduleWorkbenchTooltip(owner, anchorX) {
  hideStatusTooltip();
  workbenchTooltip.owner = owner;
  workbenchTooltip.anchorX = anchorX;
  workbenchTooltip.showTimer = window.setTimeout(() => {
    workbenchTooltip.showTimer = 0;
    if (workbenchTooltip.owner !== owner) return;
    if (workbenchTooltip.suppressedOwner === owner || !owner.isConnected || !owner.matches(":hover, :focus-within")) {
      hideStatusTooltip();
      return;
    }
    showWorkbenchTooltip(owner, workbenchTooltip.anchorX);
  }, WORKBENCH_TOOLTIP_DELAY_MS);
}

function handleWorkbenchTooltipPointerOver(event) {
  if (elements["status-surface-tooltip"].contains(event.target)) { cancelWorkbenchTooltipHide(); return; }
  const owner = getWorkbenchTooltipOwner(event.target);
  if (!owner) { scheduleWorkbenchTooltipHide(); return; }
  if (workbenchTooltip.owner === owner) { cancelWorkbenchTooltipHide(); return; }
  if (workbenchTooltip.suppressedOwner === owner) return;
  workbenchTooltip.suppressedOwner = null;
  scheduleWorkbenchTooltip(owner, event.clientX);
}

function handleWorkbenchTooltipPointerMove(event) {
  if (elements["status-surface-tooltip"].contains(event.target)) { cancelWorkbenchTooltipHide(); return; }
  const owner = getWorkbenchTooltipOwner(event.target);
  if (!owner) { scheduleWorkbenchTooltipHide(); return; }
  if (workbenchTooltip.suppressedOwner === owner) return;
  if (workbenchTooltip.owner === owner) {
    cancelWorkbenchTooltipHide();
    return;
  }
  scheduleWorkbenchTooltip(owner, event.clientX);
}

function handleWorkbenchTooltipPointerOut(event) {
  const tooltip = elements["status-surface-tooltip"];
  const owner = getWorkbenchTooltipOwner(event.target);
  if (owner?.contains(event.relatedTarget)) return;
  if (tooltip.contains(event.relatedTarget) || workbenchTooltip.owner?.contains(event.relatedTarget)) {
    cancelWorkbenchTooltipHide();
    return;
  }
  if (workbenchTooltip.suppressedOwner === owner) workbenchTooltip.suppressedOwner = null;
  scheduleWorkbenchTooltipHide();
}

function handleWorkbenchTooltipPointerDown(event) {
  const owner = getWorkbenchTooltipOwner(event.target);
  if (!owner) return;
  workbenchTooltip.suppressedOwner = owner;
  hideStatusTooltip();
}

function handleWorkbenchTooltipFocusIn(event) {
  const owner = getWorkbenchTooltipOwner(event.target);
  if (!owner) { scheduleWorkbenchTooltipHide(); return; }
  if (workbenchTooltip.suppressedOwner === owner) return;
  if (workbenchTooltip.owner === owner) { cancelWorkbenchTooltipHide(); return; }
  workbenchTooltip.suppressedOwner = null;
  const rect = owner.getBoundingClientRect();
  scheduleWorkbenchTooltip(owner, rect.left + rect.width / 2);
}

function handleWorkbenchTooltipFocusOut(event) {
  const owner = getWorkbenchTooltipOwner(event.target);
  if (owner?.contains(event.relatedTarget)) return;
  if (workbenchTooltip.suppressedOwner === owner) workbenchTooltip.suppressedOwner = null;
  scheduleWorkbenchTooltipHide();
}

function hideStatusTooltip() {
  cancelWorkbenchTooltipShow();
  cancelWorkbenchTooltipHide();
  workbenchTooltip.owner = null;
  elements["status-surface-tooltip"].classList.remove("visible");
  elements["status-surface-tooltip"].setAttribute("aria-hidden", "true");
}

function setWorkbenchTooltip(node, value) {
  if (value) node.dataset.workbenchTooltip = value;
  else delete node.dataset.workbenchTooltip;
  node.removeAttribute("title");
}

function handleRowKeyboardNavigation(event, container, keyProperty, selectRow, activateRow = null) {
  if (event.target.matches('input[type="checkbox"]')) return;
  const keyAttribute = keyProperty.replace(/[A-Z]/g, (letter) => `-${letter.toLowerCase()}`);
  const row = event.target.closest(`[data-${keyAttribute}]`);
  if (!row) return;
  if (event.key === "Enter" || event.key === " ") {
    event.preventDefault();
    selectRow(row.dataset[keyProperty]);
    activateRow?.();
    return;
  }
  if (event.key !== "ArrowUp" && event.key !== "ArrowDown") return;
  const rows = Array.from(container.querySelectorAll(`[data-${keyAttribute}]`))
    .filter((candidateRow) => candidateRow.getClientRects().length > 0);
  const currentIndex = rows.indexOf(row);
  if (currentIndex < 0) return;
  const offset = event.key === "ArrowDown" ? 1 : -1;
  const target = rows[Math.max(0, Math.min(rows.length - 1, currentIndex + offset))];
  event.preventDefault();
  selectRow(target.dataset[keyProperty]);
  target.focus();
  target.scrollIntoView({ block: "nearest" });
}

async function waitForIconSymbol(path, symbol) {
  const namespace = "http://www.w3.org/2000/svg";
  const probe = document.createElementNS(namespace, "svg");
  const use = document.createElementNS(namespace, "use");
  probe.setAttribute("width", "16");
  probe.setAttribute("height", "16");
  probe.style.cssText = "position:fixed;left:-32px;top:-32px;opacity:0;pointer-events:none";
  use.setAttribute("href", `${path}#${symbol}`);
  probe.appendChild(use);
  document.body.appendChild(probe);
  try {
    const deadline = performance.now() + 5000;
    while (performance.now() < deadline) {
      const bounds = use.getBBox();
      if (bounds.width > 0 && bounds.height > 0) return;
      await new Promise((resolve) => requestAnimationFrame(resolve));
    }
    throw new Error(`Icon symbol did not paint: ${symbol}`);
  } finally {
    probe.remove();
  }
}

async function preloadIconSprites() {
  const brandingResponse = await fetch("llm-brands.json", { cache: "no-store" });
  if (!brandingResponse.ok) throw new Error(`LLM branding map request failed with ${brandingResponse.status}`);
  llmBrandMap = validateLlmBrandMap(await brandingResponse.json());
  const sprites = [
    ["icons/codicons/sprite.svg", "codicon-diff-modified"],
    ["icons/octicons/sprite.svg", "octicon-shield-check-16"],
    ["icons/fluent/sprite.svg", "fluent-info-20-regular"],
    ...[...new Set(llmBrandMap.map(entry => entry.icon))].map(name => ["icons/llms/sprite.svg", `llm-${name}`]),
    ["icons/codicons/sprite.svg", "codicon-question"]
  ];
  const responses = await Promise.all([...new Set(sprites.map(([path]) => path))].map(path => fetch(path)));
  const failed = responses.find((response) => !response.ok);
  if (failed) throw new Error(`Icon sprite request failed with ${failed.status}`);
  await Promise.all(responses.map((response) => response.arrayBuffer()));
  await Promise.all(sprites.map(([path, symbol]) => waitForIconSymbol(path, symbol)));
}

async function waitForCandidateDecorationPaint() {
  const deadline = performance.now() + 5000;
  while (performance.now() < deadline) {
    const uses = [...elements["candidate-list"].querySelectorAll(".candidate-parent-decoration-icon:not([hidden]) use, .candidate-decoration-icon:not([hidden]) use")];
    if (uses.every((use) => {
      const bounds = use.getBBox();
      return bounds.width > 0 && bounds.height > 0;
    })) return;
    await new Promise((resolve) => requestAnimationFrame(resolve));
  }
  throw new Error("Candidate decoration icons did not paint");
}

async function loadBundle() {
  setSaveIndicator("Loading display", { kind: "standard", icon: "ellipsis" });
  try {
    await preloadIconSprites();
    const [displayResponse, ruleIssuesResponse, waitingPhrasesResponse] = await Promise.all([
      fetch("workbench-display.json", { cache: "no-store" }),
      fetch("workbench-rule-issues.json", { cache: "no-store" }),
      fetch("assistance-waiting-phrases.json", { cache: "no-store" })
    ]);
    if (!displayResponse.ok) throw new Error(`Display request failed with ${displayResponse.status}`);
    if (!ruleIssuesResponse.ok) throw new Error(`Rule Issues request failed with ${ruleIssuesResponse.status}`);
    if (!waitingPhrasesResponse.ok) throw new Error(`Assistance waiting phrases request failed with ${waitingPhrasesResponse.status}`);
    const [display, ruleIssueBundle, waitingPhrases] = await Promise.all([displayResponse.json(), ruleIssuesResponse.json(), waitingPhrasesResponse.json()]);
    validateDisplay(display);
    validateRuleIssueBundle(ruleIssueBundle);
    ruleAssistanceWaitingPhrases = validateRuleAssistanceWaitingPhrases(waitingPhrases);
    if (!sourceFilesEqual(display.sourceFiles, ruleIssueBundle.sourceFiles)) {
      throw new Error("The Workbench display and Rule Issues source files do not match.");
    }
    state.bundle = display;
    state.ruleIssueBundle = ruleIssueBundle;
    state.ruleIssues = structuredClone(ruleIssueBundle.issues);
    state.protectedRules = display.catalog.protectedRules;
    const discoveredCandidates = normalizeDisplayCandidates(display);
    const sessionId = getSessionId(display);
    const existing = await readSession(sessionId);
    state.session = migrateSession(existing, discoveredCandidates, display) || createSession(sessionId, display);
    autofillApproverName();
    const assessedCandidates = discoveredCandidates.map((candidate) => ({ candidate, assessment: getBaselineAssessment(candidate, getDecision(candidate)) }));
    const evaluatedCount = assessedCandidates.filter(({ assessment }) => assessment).length;
    if (evaluatedCount !== discoveredCandidates.length) {
      throw new Error(`AI assessment bundle is incomplete: ${evaluatedCount} of ${discoveredCandidates.length} candidates are evaluated.`);
    }
    state.assessedCandidates = assessedCandidates.map(({ candidate, assessment }) => ({
      ...candidate,
      assessment,
      category: candidate.sourceType === "upstream"
        ? getUpstreamCategory(candidate)
        : candidate.sourceType === "maintainer"
          ? capitalize(candidate.surface)
          : assessment.hostedApplicable
            ? formatHostedCategory(assessment.hostedCategory)
            : formatContractCategory(candidate.sourcePath)
    }));
    await loadWorkbenchRuntimeConfig();
          repairNoOpPlanMembership();
          repairOverridePlanMembership();
    state.excludedCandidateCount = assessedCandidates.filter(({ assessment }) => !assessment.hostedApplicable).length;
    refreshEffectiveCandidates();
    localStorage.setItem(ACTIVE_SESSION_KEY, sessionId);
    await persistSession();
    state.activeKey = null;
    state.activeProtectedRuleId = null;
    state.assessmentActiveKey = null;
    state.candidatePane = "candidates";
    state.assessmentPane = "assessments";
    renderAll();
    showCandidatePane("candidates");
    showAssessmentPane("assessments");
    await waitForCandidateDecorationPaint();
    elements.workspace.classList.remove("icon-paint-pending");
    showToast("Workbench draft loaded");
  } catch (error) {
    renderFatalError(error);
  }
}

async function closeWorkbench() {
  let shutdownConfig;
  try {
    const configResponse = await fetch("/shutdown-config", { cache: "no-store" });
    if (!configResponse.ok) throw new Error(`Workbench shutdown configuration failed with ${configResponse.status}`);
    shutdownConfig = await configResponse.json();
    if (!/^[0-9a-f]{64}$/.test(shutdownConfig?.shutdownToken || "")) {
      throw new Error("Workbench shutdown configuration is invalid");
    }
  } catch (error) {
    showToast(error.message, true);
    return;
  }
  const shutdownToken = shutdownConfig.shutdownToken;
  elements["close-button"].disabled = true;
  try {
    const response = await fetch("/shutdown", {
      method: "POST",
      headers: { "X-Workbench-Shutdown-Token": shutdownToken }
    });
    if (!response.ok) throw new Error(`Shutdown request failed with ${response.status}`);
    document.body.innerHTML = `
      <main class="shutdown-state">
        <div class="shutdown-brand-lockup">
          <svg class="shutdown-brand-icon" viewBox="0 0 16 16" aria-hidden="true"><path d="M5 2C3.89543 2 3 2.89543 3 4V6.00469C3 6.53494 2.99231 6.79889 2.91088 7.00209C2.84826 7.15835 2.71576 7.33309 2.2764 7.55276C2.10701 7.63745 2 7.81058 2 7.99997C2 8.18935 2.10699 8.36249 2.27638 8.44719C2.71569 8.66685 2.84809 8.84151 2.91076 8.99819C2.99233 9.20211 3 9.46732 3 10L3 12C3 13.1046 3.89543 14 5 14C5.27614 14 5.5 13.7761 5.5 13.5C5.5 13.2239 5.27614 13 5 13C4.44772 13 4 12.5523 4 12L4.00003 9.94145C4.00033 9.49235 4.00065 9.03033 3.83924 8.6268C3.74212 8.384 3.59654 8.17962 3.40072 8.00002C3.59646 7.82057 3.74199 7.61645 3.83912 7.37408C4.00065 6.971 4.00033 6.51001 4.00003 6.063L4 4C4 3.44772 4.44772 3 5 3C5.27614 3 5.5 2.77614 5.5 2.5C5.5 2.22386 5.27614 2 5 2ZM11 2C12.1046 2 13 2.89543 13 4V6.00469C13 6.53494 13.0077 6.79889 13.0891 7.00209C13.1517 7.15835 13.2842 7.33309 13.7236 7.55276C13.893 7.63745 14 7.81058 14 7.99997C14 8.18935 13.893 8.36249 13.7236 8.44719C13.2843 8.66685 13.1519 8.84151 13.0892 8.99819C13.0077 9.20211 13 9.46732 13 10V12C13 13.1046 12.1046 14 11 14C10.7239 14 10.5 13.7761 10.5 13.5C10.5 13.2239 10.7239 13 11 13C11.5523 13 12 12.5523 12 12L12 9.94145C11.9997 9.49235 11.9994 9.03033 12.1608 8.6268C12.2579 8.384 12.4035 8.17962 12.5993 8.00002C12.4035 7.82057 12.258 7.61645 12.1609 7.37408C11.9993 6.971 11.9997 6.51001 12 6.063L12 4C12 3.44772 11.5523 3 11 3C10.7239 3 10.5 2.77614 10.5 2.5C10.5 2.22386 10.7239 2 11 2Z"/></svg>
          <p class="shutdown-product-name">HOSTED COPILOT RULE MANAGER</p>
        </div>
        <h1>Workbench Closed</h1>
        <p>The local server has stopped. This tab can be closed.</p>
      </main>
    `;
  } catch (error) {
    elements["close-button"].disabled = false;
    showToast(error.message, true);
  }
}

function validateDisplay(display) {
  if (!display || display.schemaVersion !== WORKBENCH_DISPLAY_SCHEMA_VERSION || display.kind !== "hosted-rule-workbench-display" || display.readOnly !== true || !Array.isArray(display.sourceFiles) || display.sourceFiles.length === 0) {
    throw new Error("The Workbench display does not satisfy the read-only display contract.");
  }
  if (!Array.isArray(display.candidates) || !display.catalog || !Array.isArray(display.catalog.rules) || !Array.isArray(display.catalog.protectedRules) || !Array.isArray(display.catalog.protectedRuleFiles)) {
    throw new Error("The Workbench display does not contain candidates and a catalog projection.");
  }
  if (display.candidates.some((candidate) => !Array.isArray(candidate.members) || candidate.members.length === 0
    || candidate.members.some((member) => !member.source || !member.assessment || !member.meaningCoverageRationale || !member.catalogMapping))) {
    throw new Error("The Workbench display contains an invalid contributing-rule projection.");
  }
  if (display.catalog.protectedRuleFiles.some((file) => typeof file.path !== "string" || typeof file.content !== "string" || !file.content || !Array.isArray(file.ruleIds) || file.ruleIds.length === 0)) {
    throw new Error("The Workbench display contains an invalid protected rule file projection.");
  }
  if (!display.guidanceCapacity || !Array.isArray(display.guidanceCapacity.reports)
    || display.guidanceCapacity.reportCount !== display.guidanceCapacity.reports.length
    || display.guidanceCapacity.reportCount < 1
    || new Set(display.guidanceCapacity.reports.map((report) => report.name)).size !== display.guidanceCapacity.reportCount
    || !/^[a-f0-9]{64}$/.test(display.guidanceCapacity.tokenPolicySha256)
    || !Number.isInteger(display.guidanceCapacity.safetyMarginPercent)
    || display.guidanceCapacity.safetyMarginPercent < 0 || display.guidanceCapacity.safetyMarginPercent > 100
    || !Number.isInteger(display.guidanceCapacity.maximumGuidanceTokens) || display.guidanceCapacity.maximumGuidanceTokens < 1) {
    throw new Error("The Workbench display does not contain all guidance capacity reports.");
  }
  if (!display.reconciliation || display.reconciliation.status !== "ready") {
    throw new Error("The Workbench display does not contain reconciliation status.");
  }
}

function validateRuleIssueBundle(bundle) {
  const classifications = new Set(RULE_ISSUE_FILTERS.flatMap((filter) => filter.classifications));
  const wordingStatuses = new Set(["canonical", "selected", "unresolved"]);
  if (!bundle || bundle.schemaVersion !== WORKBENCH_RULE_ISSUES_SCHEMA_VERSION || bundle.kind !== "hosted-rule-workbench-rule-issues" || bundle.readOnly !== true || !Array.isArray(bundle.sourceFiles) || bundle.sourceFiles.length === 0) {
    throw new Error("The Workbench Rule Issues artifact does not satisfy its read-only contract.");
  }
  if (!Array.isArray(bundle.issues) || bundle.issues.some((issue) => !classifications.has(issue.classification)
    || !Array.isArray(issue.rules)
    || !Array.isArray(issue.relationships)
    || typeof issue.assessmentSummary !== "string"
    || issue.assessmentSummary.length < 1
    || issue.assessmentSummary.length > 600
    || !wordingStatuses.has(issue.wording?.status)
    || !["section", "member"].includes(issue.wording?.presentation)
    || (issue.wording.status === "unresolved" ? !issue.wording.reason : !issue.wording.text))) {
    throw new Error("The Workbench Rule Issues artifact does not contain display-ready issues.");
  }
}

function normalizeDisplayCandidates(display) {
  return display.candidates.map((candidate) => {
    const { source, recommendation, reviewState } = candidate;
    const normalizedRecommendation = recommendation
      ? { ...recommendation, retireHostedRuleIds: [...recommendation.retireHostedRuleIds] }
      : null;
    const sourceType = source.lane === "contributor" ? "upstream" : source.lane;
    const targetHostedRuleId = normalizedRecommendation?.targetHostedId || null;
    const proposedHostedRuleId = normalizedRecommendation?.hostedId || "";
    const hostedCategory = normalizedRecommendation?.category
      || candidate.assessment.affectedSurfaces.find((surface) => ["repository", "implementation", "testing", "documentation"].includes(surface))
      || "repository";
    const mappedHostedRuleId = candidate.catalogMapping.hostedRuleId;
    const assessment = {
      ...candidate.assessment,
      status: "evaluated",
      assessmentId: candidate.assessment.id,
      summary: candidate.assessment.sourceMeaning,
      assessmentConfidence: candidate.assessment.confidence,
      sourceContentSha256: source.contentSha256,
      relatedHostedCoverage: normalizedRecommendation.relatedHostedCoverage,
      recommendation: normalizedRecommendation?.action || (reviewState === "excluded" ? "exclude" : "defer"),
      proposedHostedRuleId,
      targetHostedRuleId,
      proposedText: normalizedRecommendation.ruleText,
      hostedCategory,
      guardedTokenDelta: normalizedRecommendation?.guardedTokenDelta || 0
    };
    const members = candidate.members.map((member) => {
      const memberSourceType = member.source.lane === "contributor" ? "upstream" : member.source.lane;
      return {
        source: member.source,
        assessment: member.assessment,
        meaningCoverageRationale: member.meaningCoverageRationale,
        catalogMapping: member.catalogMapping,
        sourceLabel: memberSourceType === "upstream" ? "Contributor guidance" : memberSourceType === "interactive" ? "Interactive rule" : "Maintainer proposal"
      };
    });
    return {
      key: `${source.lane}:${source.id}:${candidate.assessment.id}`,
      id: proposedHostedRuleId || targetHostedRuleId || candidate.assessment.id,
      sourceId: source.id,
      sourceTitle: source.title,
      sourceType,
      sourceLabel: sourceType === "upstream" ? "Contributor guidance" : sourceType === "interactive" ? "Interactive rule" : "Maintainer proposal",
      category: sourceType === "upstream" ? (source.transition === "changed" ? "Changed guidance (drift)" : "Current guidance") : sourceType === "maintainer" ? capitalize(source.surface) : formatContractCategory(source.location),
      title: candidate.assessment.title,
      state: source.transition,
      requiresReview: Boolean(normalizedRecommendation?.needsReview) || members.some((member) => member.assessment.confidence.level !== "high"),
      provenance: source.provenance,
      sourcePath: source.location,
      sourceRationale: source.rationale,
      surface: source.surface,
      revision: source.revision,
      hash: source.contentSha256,
      text: source.text,
      baselineText: source.priorText || null,
      priorDecision: null,
      recommendation: normalizedRecommendation,
      assessment,
      members,
      catalogMapping: candidate.catalogMapping,
      mappedHostedRules: mappedHostedRuleId ? display.catalog.rules.filter((rule) => rule.id === mappedHostedRuleId) : []
    };
  });
}

function getFilteredRuleIssues(filterKey = state.ruleIssueFilter, search = state.queries["rule-issues"]) {
  const query = search.trim().toLowerCase();
  const activeFilter = RULE_ISSUE_FILTERS.find((filter) => filter.key === filterKey);
  return getOpenRuleIssues().filter((issue) => {
    if (!activeFilter?.classifications.includes(issue.classification)) return false;
    if (!query) return true;
    return [issue.title, issue.label, issue.bannerTitle, issue.bannerMessage, issue.assessmentSummary, issue.wording?.text, issue.recommendedMaintainerAction.summary, ...issue.ruleIds, ...issue.rules.map((rule) => rule.text)]
      .some((value) => String(value || "").toLowerCase().includes(query));
  });
}

function getRuleIssueFilterKey(issue) {
  return RULE_ISSUE_FILTERS.find((filter) => filter.classifications.includes(issue.classification))?.key || null;
}

function rememberRuleIssueSelection(issueId, filter = state.ruleIssueFilter, preferredIndex = null) {
  if (!filter || !issueId) return;
  const issues = getFilteredRuleIssues();
  const index = preferredIndex ?? issues.findIndex((issue) => issue.id === issueId);
  state.ruleIssueSelections[filter] = { issueId, preferredIndex: Math.max(0, index) };
}

function rememberResolvedRuleIssue(issue, preferredIndex) {
  const filter = getRuleIssueFilterKey(issue);
  if (!filter) return;
  state.ruleIssueResolutionHistory = state.ruleIssueResolutionHistory.filter((entry) => entry.issueId !== issue.id);
  state.ruleIssueResolutionHistory.push({ issueId: issue.id, filter, preferredIndex });
}

function prepareRuleIssueRestore(candidateKeys) {
  const affectedKeys = new Set(candidateKeys);
  const affectedIssues = state.ruleIssues.filter((issue) => getRuleIssueOperations(issue).some((operation) => affectedKeys.has(operation.candidateKey) && isRuleIssueOperationApplied(operation)));
  if (!affectedIssues.length) return;
  const affectedIds = new Set(affectedIssues.map((issue) => issue.id));
  const remembered = [...state.ruleIssueResolutionHistory].reverse().find((entry) => affectedIds.has(entry.issueId));
  const issue = remembered ? affectedIssues.find((item) => item.id === remembered.issueId) : affectedIssues[0];
  const filter = remembered?.filter || getRuleIssueFilterKey(issue);
  const preferredIndex = remembered?.preferredIndex || 0;
  state.ruleIssueFilter = filter;
  state.activeRuleIssueKey = issue.id;
  state.ruleIssueSelections[filter] = { issueId: issue.id, preferredIndex };
}

function formatRuleIssueSummary(issues) {
  const counts = Object.fromEntries(RULE_ISSUE_FILTERS.map((filter) => [filter.key, issues.filter((issue) => filter.classifications.includes(issue.classification)).length]));
  const protectedCount = counts.protected;
  return `Rule Issues: ${protectedCount} Protected, ${formatCountLabel(counts.contradiction, "Contradiction")}, ${formatCountLabel(counts.duplicate, "Duplicate")}, ${formatCountLabel(counts.overlap, "Overlap")}`;
}

function getValidationProblems() {
  if (!state.session) return [];
  return getPlanCandidates().filter((candidate) => !getPlanReadiness(candidate).ready)
    .map((candidate) => ({ kind: "warning", candidateKey: candidate.key }));
}

function renderValidationIssues() {
  const problems = getValidationProblems();
  const errors = problems.filter((problem) => problem.kind === "error").length;
  const warnings = problems.filter((problem) => problem.kind === "warning").length;
  const tooltip = errors || warnings
    ? `Validation Issues: ${formatCountLabel(errors, "Error")}, ${formatCountLabel(warnings, "Warning")}`
    : "No Problems";
  workbenchStatusBar.update("validationIssues", {
    tooltip,
    ariaLabel: tooltip === "No Problems" ? "Validation Issues: No Problems" : tooltip,
    segments: {
      errors: { text: formatNumber(errors), kind: errors ? "error" : "standard" },
      warnings: { text: formatNumber(warnings), kind: warnings ? "warning" : "standard" }
    }
  });
}

function getRuleIssueTabPages(tabs, availableWidth) {
  const pages = [];
  let page = [];
  let pageWidth = 0;
  tabs.forEach((tab, index) => {
    const tabWidth = tab.getBoundingClientRect().width + Number.parseFloat(getComputedStyle(tab).marginRight || "0");
    if (page.length && pageWidth + tabWidth > availableWidth) {
      pages.push(page);
      page = [];
      pageWidth = 0;
    }
    page.push(index);
    pageWidth += tabWidth;
  });
  if (page.length) pages.push(page);
  return pages;
}

function renderRuleIssueTabPagination(revealSelected = false) {
  const pager = elements["rule-issue-tab-pager"];
  const viewport = elements["rule-issue-tab-viewport"];
  const previous = elements["rule-issues-previous"];
  const next = elements["rule-issues-next"];
  const tabs = [...elements["rule-issues-filters"].querySelectorAll('[role="tab"]')];
  tabs.forEach((tab) => tab.classList.remove("rule-issue-tab-page-hidden"));
  pager.classList.remove("paging");
  previous.hidden = true;
  next.hidden = true;
  previous.disabled = true;
  next.disabled = true;
  previous.tabIndex = -1;
  next.tabIndex = -1;
  if (!tabs.length) return;

  const totalWidth = tabs.reduce((total, tab) => total + tab.getBoundingClientRect().width + Number.parseFloat(getComputedStyle(tab).marginRight || "0"), 0);
  if (totalWidth <= pager.clientWidth + 0.5) {
    state.ruleIssueTabPage = 0;
    return;
  }

  pager.classList.add("paging");
  previous.hidden = false;
  next.hidden = false;
  const pages = getRuleIssueTabPages(tabs, viewport.clientWidth);
  if (revealSelected) {
    const selectedPage = pages.findIndex((page) => page.some((index) => tabs[index].getAttribute("aria-selected") === "true"));
    state.ruleIssueTabPage = selectedPage >= 0 ? selectedPage : 0;
  }
  state.ruleIssueTabPage = Math.max(0, Math.min(state.ruleIssueTabPage, pages.length - 1));
  const visibleTabs = new Set(pages[state.ruleIssueTabPage]);
  tabs.forEach((tab, index) => tab.classList.toggle("rule-issue-tab-page-hidden", !visibleTabs.has(index)));
  previous.disabled = state.ruleIssueTabPage === 0;
  next.disabled = state.ruleIssueTabPage === pages.length - 1;
  previous.tabIndex = previous.disabled ? -1 : 0;
  next.tabIndex = next.disabled ? -1 : 0;
}

function scheduleRuleIssueTabPagination(revealSelected = false) {
  cancelAnimationFrame(ruleIssueTabPaginationFrame);
  ruleIssueTabPaginationFrame = requestAnimationFrame(() => renderRuleIssueTabPagination(revealSelected));
}

function changeRuleIssueTabPage(direction) {
  state.ruleIssueTabPage += direction;
  renderRuleIssueTabPagination();
}

function renderRuleIssueFilters() {
  const openIssues = getOpenRuleIssues();
  const counts = Object.fromEntries(RULE_ISSUE_FILTERS.map((filter) => [filter.key, openIssues.filter((issue) => filter.classifications.includes(issue.classification)).length]));
  const visibleFilters = RULE_ISSUE_FILTERS.filter((filter) => counts[filter.key] > 0);
  if (!visibleFilters.some((filter) => filter.key === state.ruleIssueFilter)) {
    state.ruleIssueFilter = visibleFilters[0]?.key || RULE_ISSUE_FILTERS[0].key;
  }
  elements["rule-issues-filters"].innerHTML = visibleFilters.map((filter) => `
    <button class="candidate-pane-tab clickable ${state.ruleIssueFilter === filter.key ? "active" : ""}" type="button" role="tab" data-rule-issue-filter="${filter.key}" aria-selected="${state.ruleIssueFilter === filter.key}">${escapeHtml(filter.label)} <span>${formatNumber(counts[filter.key])}</span></button>
  `).join("");
  renderRuleIssueTabPagination(true);
}

function renderRuleReferences(value, ruleIds, referenceClass = "rule-reference") {
  const text = String(value || "");
  const references = [...new Set(ruleIds)].filter(Boolean).sort((left, right) => right.length - left.length);
  let offset = 0;
  let output = "";
  while (offset < text.length) {
    let match = null;
    let matchIndex = -1;
    references.forEach((reference) => {
      const index = text.indexOf(reference, offset);
      if (index < 0 || (matchIndex >= 0 && index > matchIndex)) return;
      if (index === matchIndex && match && reference.length <= match.length) return;
      match = reference;
      matchIndex = index;
    });
    if (!match) break;
    output += escapeHtml(text.slice(offset, matchIndex));
    output += `<span class="${escapeHtml(referenceClass)}">${escapeHtml(match)}</span>`;
    offset = matchIndex + match.length;
  }
  return `${output}${escapeHtml(text.slice(offset))}`;
}

function renderRuleIssueIds(ruleIds) {
  return ruleIds.map((id) => `<span class="rule-reference">${escapeHtml(id)}</span>`).join('<span class="rule-issue-id-separator" aria-hidden="true">·</span>');
}

function getRuleIssueOperations(issue) {
  return issue.recommendedMaintainerAction.operations;
}

function getRuleIssueAncillaryRetirements(operation) {
  return [...operation.retireHostedRuleIds].filter((ruleId) => ruleId !== operation.ruleId).sort();
}

function isRuleIssueOperationApplied(operation) {
  const candidate = state.assessedCandidates.find((item) => item.key === operation.candidateKey);
  if (!candidate) return false;
  const decision = getDecision(candidate);
  return decision.inPlan
    && decision.action === operation.action
    && decision.proposedText === operation.proposedText
    && JSON.stringify([...decision.retireHostedRuleIds].sort()) === JSON.stringify(getRuleIssueAncillaryRetirements(operation));
}

function getRuleIssueOperationStates(issue) {
  return new Map(getRuleIssueOperations(issue).map((operation) => [operation.candidateKey, {
    operation,
    applied: isRuleIssueOperationApplied(operation)
  }]));
}

function getPendingRuleIssueOperations(issue) {
  return [...getRuleIssueOperationStates(issue).values()].filter((entry) => !entry.applied).map((entry) => entry.operation);
}

function getVisibleRuleIssueRules(issue) {
  const operationStates = [...getRuleIssueOperationStates(issue).values()];
  const partiallyApplied = operationStates.some((entry) => entry.applied) && operationStates.some((entry) => !entry.applied);
  if (!partiallyApplied) return issue.rules;
  const pendingRuleIds = new Set(operationStates.filter((entry) => !entry.applied).map((entry) => entry.operation.ruleId));
  return issue.rules.filter((rule) => pendingRuleIds.has(rule.id));
}

function isRuleIssueRecommendationStaged(issue) {
  const operationStates = [...getRuleIssueOperationStates(issue).values()];
  return operationStates.length > 0 && operationStates.every((entry) => entry.applied);
}

function getOpenRuleIssues() {
  return state.ruleIssues.filter((issue) => !isRuleIssueRecommendationStaged(issue));
}

function renderRuleIssuePlanAction(issue) {
  const operations = getRuleIssueOperations(issue);
  const pendingOperations = getPendingRuleIssueOperations(issue);
  const candidates = pendingOperations.map((operation) => state.assessedCandidates.find((candidate) => candidate.key === operation.candidateKey));
  const staged = isRuleIssueRecommendationStaged(issue);
  const partiallyStaged = !staged && pendingOperations.length < operations.length;
  const checking = activeRuleIssueRecommendations.has(issue.id);
  const identity = getValidatedCodeOwnerIdentity();
  const unavailableReason = checking
    ? "Recommended actions are being applied."
    : issue.blocking
    ? "Protected integrity issues must be resolved in the protected source files."
    : !operations.length || candidates.some((candidate) => !candidate)
      ? "The supplied maintainer operations cannot be mapped to current candidates."
    : globalThis.__HOSTED_RULE_WORKBENCH__?.maintainerIdentity?.reason || "A validated Hosted CODEOWNER identity is required.";
  const disabled = checking || staged || issue.blocking || !operations.length || candidates.some((candidate) => !candidate) || !identity;
  const tooltip = disabled && !staged ? ` data-workbench-tooltip="${escapeHtml(unavailableReason)}"` : "";
  const label = checking ? "Applying Recommended Actions" : staged ? "Recommended Actions Applied" : partiallyStaged ? `Apply ${formatCountLabel(pendingOperations.length, "Remaining Action")}` : "Apply Recommended Actions";
  return `<div class="rule-recommendation-actions"><button class="button primary rule-issue-plan-action ${disabled ? "" : "clickable"}" type="button" data-rule-issue-plan="${escapeHtml(issue.id)}" ${disabled ? "disabled" : ""}${tooltip}>${icon(staged ? "pass-filled" : "new-session")}<span class="button-label">${label}</span></button></div>`;
}

async function stageRuleIssueRecommendation(issue) {
  const identity = getValidatedCodeOwnerIdentity();
  if (!identity) {
    showToast(globalThis.__HOSTED_RULE_WORKBENCH__?.maintainerIdentity?.reason || "A validated Hosted CODEOWNER identity is required.", true);
    return;
  }
  const operations = getPendingRuleIssueOperations(issue);
  if (issue.blocking || !operations.length) {
    showToast(issue.blocking ? "Resolve protected integrity in the protected source files." : "The artifact does not contain maintainer operations for this issue.", true);
    return;
  }
  const candidateOperations = operations.map((operation) => {
    const candidate = state.assessedCandidates.find((item) => item.key === operation.candidateKey);
    if (!candidate) throw new Error(`Rule Issues operation references an unknown candidate: ${operation.candidateKey}`);
    return { candidate, operation };
  });
  activeRuleIssueRecommendations.add(issue.id);
  renderRuleIssues();
  try {
    const editorIsSaved = () => {
      const active = getActiveCandidate();
      const editor = elements["assessment-panel"].querySelector('[data-decision-field="proposedText"]');
      return !editor || !active || editor.value === getDecision(active).proposedText;
    };
    if (!editorIsSaved()) throw new Error("Save the current wording before applying recommended actions.");
    const before = JSON.stringify(state.session);
    const assertCurrent = () => {
      if (JSON.stringify(state.session) !== before || !editorIsSaved()
        || getValidatedCodeOwnerIdentity()?.login !== identity.login) {
        throw new Error("The draft or maintainer identity changed. Review and apply the recommendation again.");
      }
    };
    const updatedAt = toUtcTimestamp();
    const rationale = issue.recommendedMaintainerAction.summary.slice(0, DECISION_RATIONALE_MAX_LENGTH);
    const visibleIssues = getFilteredRuleIssues();
    const resolvedIndex = Math.max(0, visibleIssues.findIndex((item) => item.id === issue.id));
    const nextSession = structuredClone(state.session);
    candidateOperations.forEach(({ candidate, operation }) => {
      const { assessment, ...decision } = getDecision(candidate);
      removeCandidateFromBulkOperations(candidate.key, nextSession);
      nextSession.decisions[candidate.key] = {
        ...decision,
        action: operation.action,
        rationale,
        proposedText: operation.proposedText,
        retireHostedRuleIds: getRuleIssueAncillaryRetirements(operation),
        ...createPlanMembership("manual"),
        sourceHash: candidate.hash,
        updatedAt
      };
    });
    nextSession.updatedAt = updatedAt;
    assertCurrent();
    await persistSession(nextSession, assertCurrent);
    try { assertCurrent(); }
    catch (error) {
      await persistSession();
      throw error;
    }
    state.session = nextSession;
    if (isRuleIssueRecommendationStaged(issue)) {
      rememberResolvedRuleIssue(issue, resolvedIndex);
      const remainingIssues = getFilteredRuleIssues();
      const nextIndex = Math.min(resolvedIndex, remainingIssues.length - 1);
      const nextIssue = remainingIssues[nextIndex] || null;
      state.activeRuleIssueKey = nextIssue?.id || null;
      if (nextIssue) rememberRuleIssueSelection(nextIssue.id, state.ruleIssueFilter, nextIndex);
    }
    syncCandidateTreeRows();
    renderBulkActions();
    renderDecisionOutputs();
    renderRuleIssues();
    renderAssessment();
    showToast(`${formatCountLabel(operations.length, "Resolution")} added to the promotion plan.`);
  }
  catch (error) {
    showToast(`Recommended actions were not applied: ${error.message}`, true);
  }
  finally {
    activeRuleIssueRecommendations.delete(issue.id);
    renderRuleIssues();
  }
}

async function handleRuleIssueDetailClick(event) {
  const dismiss = event.target.closest("[data-dismiss-rule-issue-banner]");
  if (dismiss) {
    state.dismissedRuleIssueBannerKeys.add(dismiss.dataset.dismissRuleIssueBanner);
    dismiss.closest(".rule-issue-banner")?.remove();
    return;
  }
  const planAction = event.target.closest("[data-rule-issue-plan]");
  if (!planAction) return;
  const issue = state.ruleIssues.find((item) => item.id === planAction.dataset.ruleIssuePlan);
  if (issue) await stageRuleIssueRecommendation(issue);
}

function renderRuleIssueRule(rule, issue) {
  const isProtected = rule.status === "protected" || state.protectedRules.some((item) => item.id === rule.id);
  const operation = getRuleIssueOperations(issue).find((item) => item.ruleId === rule.id);
  const action = operation?.action || ({ promote: "add", replace: "update", retire: "retire", exclude: "exclude", defer: "defer" })[rule.disposition];
  const actionBadge = isProtected
    ? `<span class="ui-badge status-capsule recommendation-badge immutable">Immutable</span>`
    : action
      ? `<span class="ui-badge status-capsule decision-badge ${escapeHtml(action)}">${escapeHtml(formatRecommendation(action))}</span>`
      : `<span class="ui-badge status-capsule decision-badge ${rule.disposition === "keep" ? "no-change" : "defer"}">${escapeHtml(capitalize(rule.disposition))}</span>`;
  return `
    <section class="rule-issue-rule recommend-${escapeHtml(rule.disposition)}${isProtected ? " protected-reference" : ""}"${isProtected ? ` role="group" aria-label="Protected rule ${escapeHtml(rule.id)}"` : ""}>
      <h3><span class="rule-reference">${escapeHtml(rule.id)}</span><span class="rule-issue-rule-statuses"><span class="ui-badge status-capsule catalog-status ${isProtected ? "protected" : escapeHtml(rule.status)}">${isProtected ? "Protected" : escapeHtml(capitalize(rule.status))}</span>${actionBadge}</span></h3>
      <div class="rule-issue-rule-body"${isProtected ? ' role="document" aria-label="Protected rule text, read only"' : ""}><p>${renderRuleReferences(rule.text, issue.ruleIds)}</p></div>
    </section>
  `;
}

function renderRuleIssueWording(wording, ruleIds) {
  const unresolved = wording.status === "unresolved";
  const text = unresolved ? wording.reason : wording.text;
  return `<section class="rule-issue-suggestion ${unresolved ? "rule-issue-wording-unresolved" : ""}"><h3>${escapeHtml(wording.label)}</h3><p>${renderRuleReferences(text, ruleIds)}</p></section>`;
}

function renderRuleIssueResolutionPreview(issue, proposedText) {
  if (issue.wording.status === "unresolved") return renderRuleIssueWording(issue.wording, issue.ruleIds);
  const file = createPreviewFile("", "Resolution wording", proposedText.split("\n"), issue.wording.text.split("\n"));
  return `<section class="rule-issue-resolution-preview" aria-label="Resolution wording preview">
    <div class="rule-issue-resolution-preview-heading"><h3>${escapeHtml(issue.wording.label)}</h3><span class="preview-change-summary" aria-label="${file.additions} additions and ${file.deletions} deletions"><b>+${file.additions}</b><i>-${file.deletions}</i></span></div>
    <div class="rule-issue-resolution-columns"><span>Saved Wording</span><span>Recommended Wording</span></div>
    <div class="preview-contextual-diff">${file.rows.map(row => renderPreviewDiffRow({ type: "line", row })).join("")}</div>
  </section>`;
}

function renderRuleIssueContent(issue, { candidateDetails = false, proposedText = null } = {}) {
  const visibleRules = getVisibleRuleIssueRules(issue);
  const protectedNotice = RULE_ISSUE_FILTERS.find((filter) => filter.key === "protected").classifications.includes(issue.classification)
    ? renderInformationPanel("<p>Protected rules cannot be changed in the Workbench. Edit the protected source file directly in the repository. Relaunch with <code>-Rebuild</code> to refresh the Workbench snapshot and analysis. Rebuilding refreshes assessments and Rule Issues and may require significant processing time.</p>", { className: "protected-rule-information" })
    : "";
  const ordinaryRelationship = candidateDetails && !issue.blocking && !issue.classification.includes("conflict") && issue.classification !== "contradiction";
  const banner = state.dismissedRuleIssueBannerKeys.has(issue.id) ? "" : `
    <div class="rule-issue-banner ${escapeHtml(issue.classification)}${ordinaryRelationship ? " relationship-review" : ""}">${icon(ordinaryRelationship ? "info" : issue.blocking || issue.classification.includes("conflict") || issue.classification === "contradiction" ? "chat-sparkle-error" : "warning")}<div><strong>${ordinaryRelationship ? `Rule Relationship Review &middot; ${escapeHtml(formatRuleIssueTitle(issue.classification))}` : escapeHtml(formatRuleIssueTitle(issue.bannerTitle))}</strong><p>${renderRuleReferences(issue.bannerMessage, issue.ruleIds, "rule-issue-banner-reference")}</p></div><button class="rule-issue-banner-dismiss clickable" type="button" data-dismiss-rule-issue-banner="${escapeHtml(issue.id)}" aria-label="Dismiss issue message" data-workbench-tooltip="Dismiss">${icon("close")}</button></div>`;
  return `
    ${banner}
    ${protectedNotice}
    <div class="rule-issue-comparison">${visibleRules.map((rule) => renderRuleIssueRule(rule, issue)).join("")}</div>
    ${candidateDetails && proposedText !== null ? renderRuleIssueResolutionPreview(issue, proposedText) : ""}
    ${candidateDetails ? "" : `<span class="section-label rule-issue-assessment-label">Assessment:</span>
    <section class="rule-issue-assessment"><p>${renderRuleReferences(issue.assessmentSummary, issue.ruleIds)}</p></section>
    ${renderRuleIssueWording(issue.wording, issue.ruleIds)}
    <span class="section-label rule-issue-recommendation-label">Recommended Maintainer Action:</span>`}
    <section class="rule-issue-recommendation">${candidateDetails ? renderInformationPanel(`<p>${renderRuleReferences(issue.recommendedMaintainerAction.summary, issue.ruleIds)}</p>`) : `<p>${renderRuleReferences(issue.recommendedMaintainerAction.summary, issue.ruleIds)}</p>`}${renderRuleIssuePlanAction(issue)}</section>
  `;
}

function renderRuleIssueDetail(issue) {
  elements["rule-issues-detail"].innerHTML = issue
    ? renderRuleIssueContent(issue)
    : renderPreviewEmptyState("warning-compact", "Select a Rule Issue", "Relationship evidence, affected rules, consolidated wording, and advisory actions will appear here.");
  scheduleTruncationTooltips();
}

function formatRuleIssueTitle(value) {
  const minorWords = new Set(["a", "an", "and", "as", "at", "but", "by", "for", "from", "in", "nor", "of", "on", "or", "the", "to", "up", "with"]);
  const words = String(value || "").split(/(\s+)/);
  const significantWords = words.filter((word) => word.trim());
  let significantIndex = 0;
  return words.map((word) => {
    if (!word.trim()) return word;
    const lower = word.toLowerCase();
    const first = significantIndex === 0;
    const last = significantIndex === significantWords.length - 1;
    significantIndex += 1;
    if (!first && !last && minorWords.has(lower)) return lower;
    return `${word[0].toUpperCase()}${word.slice(1)}`;
  }).join("");
}

function renderRuleIssues() {
  if (!elements["rule-issues-list"]) return;
  const requestedFilter = state.ruleIssueFilter;
  renderRuleIssueFilters();
  if (state.ruleIssueFilter !== requestedFilter) {
    state.activeRuleIssueKey = state.ruleIssueSelections[state.ruleIssueFilter]?.issueId || null;
  }
  const issues = getFilteredRuleIssues();
  const remembered = state.ruleIssueSelections[state.ruleIssueFilter];
  if (!issues.some((issue) => issue.id === state.activeRuleIssueKey)) {
    const rememberedIssue = issues.find((issue) => issue.id === remembered?.issueId);
    const fallbackIndex = Math.min(remembered?.preferredIndex || 0, Math.max(0, issues.length - 1));
    state.activeRuleIssueKey = rememberedIssue?.id || issues[fallbackIndex]?.id || null;
  }
  if (!issues.length) {
    elements["rule-issues-list"].innerHTML = renderPreviewEmptyState("pass-compact", "No Rule Issues", "No rule relationships match the current filter and search.");
    renderRuleIssueDetail(null);
    return;
  }
  elements["rule-issues-list"].innerHTML = issues.map((issue) => `
    <button class="rule-issue-row clickable ${issue.id === state.activeRuleIssueKey ? "active" : ""}" type="button" data-rule-issue-key="${escapeHtml(issue.id)}" aria-pressed="${issue.id === state.activeRuleIssueKey}">
      <span class="rule-issue-row-heading"><strong>${escapeHtml(formatRuleIssueTitle(issue.title))}</strong><span class="ui-badge status-capsule rule-issue-kind ${escapeHtml(issue.classification)} status-badge ${issue.blocking || issue.classification.includes("conflict") || issue.classification === "contradiction" ? "excluded" : "warning"} type-compact">${escapeHtml(issue.label)}</span></span>
      <span class="rule-issue-ids">${renderRuleIssueIds(getVisibleRuleIssueRules(issue).map((rule) => rule.id))}</span>
    </button>
  `).join("");
  renderRuleIssueDetail(issues.find((issue) => issue.id === state.activeRuleIssueKey));
  if (!state.queries["rule-issues"].trim() && state.activeRuleIssueKey && !remembered) {
    rememberRuleIssueSelection(state.activeRuleIssueKey);
  }
  scrollApprovalTargetIntoView(elements["rule-issues-list"].querySelector(`[data-rule-issue-key="${CSS.escape(state.activeRuleIssueKey)}"]`), elements["rule-issues-list"]);
}

function getSessionId(display) {
  return "current";
}

function sourceFilesEqual(left, right) {
  if (!Array.isArray(left) || !Array.isArray(right)) return false;
  const ordered = (sourceFiles) => [...sourceFiles].sort((first, second) =>
    String(first.sourceDefinitionId).localeCompare(String(second.sourceDefinitionId))
    || String(first.sourceId).localeCompare(String(second.sourceId)));
  return JSON.stringify(ordered(left)) === JSON.stringify(ordered(right));
}

function createSession(id, display) {
  const timestamp = toUtcTimestamp();
  return {
    schemaVersion: SESSION_SCHEMA_VERSION,
    id,
    createdAt: timestamp,
    updatedAt: timestamp,
    sourceFiles: structuredClone(display.sourceFiles),
    approverName: "",
    decisions: {},
    applicabilityOverrides: {},
    bulkOperations: []
  };
}

function migrateSession(session, candidates, display) {
  if (!session) return null;
  if (session.id !== "current" || session.schemaVersion !== SESSION_SCHEMA_VERSION || !sourceFilesEqual(session.sourceFiles, display.sourceFiles)) return null;
  const { manualRelationshipChecks, savedRuleEvaluations, ...currentSession } = session;
  return currentSession;
}

function createPlanMembership(source = "none", bulkOperationId = null) {
  return {
    inPlan: source !== "none",
    planMembershipSource: source,
    bulkOperationId: source === "bulk" ? bulkOperationId : null
  };
}

function isValidBulkOperation(operation) {
  return operation
    && typeof operation.id === "string"
    && Boolean(operation.id)
    && typeof operation.createdAt === "string"
    && ["add", "update", "actionable"].includes(operation.action)
    && Array.isArray(operation.candidateKeys)
    && operation.candidateKeys.length > 0
    && new Set(operation.candidateKeys).size === operation.candidateKeys.length
    && operation.candidateKeys.every((key) => typeof key === "string" && Boolean(key));
}

function isValidPlanMembership(decision, candidateKey, operations = state.session.bulkOperations) {
  if (decision.inPlan === false) return decision.planMembershipSource === "none" && decision.bulkOperationId === null;
  if (decision.inPlan !== true) return false;
  if (["manual", "override"].includes(decision.planMembershipSource)) return decision.bulkOperationId === null;
  if (decision.planMembershipSource !== "bulk" || typeof decision.bulkOperationId !== "string") return false;
  return operations.some((operation) => operation.id === decision.bulkOperationId && operation.candidateKeys.includes(candidateKey));
}

function autofillApproverName() {
  const login = globalThis.__HOSTED_RULE_WORKBENCH__?.maintainerIdentity?.login;
  if (!String(state.session.approverName || "").trim() && login) {
    state.session.approverName = String(login).slice(0, 120);
  }
}

function getValidatedCodeOwnerIdentity() {
  const identity = globalThis.__HOSTED_RULE_WORKBENCH__?.maintainerIdentity;
  return identity?.status === "validated" && identity.isCodeOwner === true && Boolean(identity.login) ? identity : null;
}

function getApplicabilityOverride(candidate) {
  const override = state.session.applicabilityOverrides?.[candidate.key];
  if (!override || override.sourceContentSha256 !== candidate.hash) return null;
  const valid = override.state === "provisional"
    && override.originalHostedApplicable === false
    && override.effectiveHostedApplicable === true
    && typeof override.rationale === "string"
    && Boolean(override.rationale.trim())
    && override.rationale.length <= OVERRIDE_RATIONALE_MAX_LENGTH
    && typeof override.recordedAt === "string"
    && Boolean(override.recordedBy?.login);
  return valid ? override : null;
}

function getEffectiveHostedApplicability(candidate) {
  return candidate.assessment.hostedApplicable || Boolean(getApplicabilityOverride(candidate));
}

function refreshEffectiveCandidates() {
  state.candidates = state.assessedCandidates.filter((candidate) => getEffectiveHostedApplicability(candidate));
}

function repairOverridePlanMembership() {
  state.assessedCandidates.forEach((candidate) => {
    if (!getApplicabilityOverride(candidate)) return;
    const decision = getDecision(candidate);
    if (decision.inPlan && decision.planMembershipSource === "override") return;
    const { assessment, ...maintainerDecision } = decision;
    state.session.decisions[candidate.key] = {
      ...maintainerDecision,
      ...createPlanMembership("override"),
      sourceHash: candidate.hash,
      updatedAt: toUtcTimestamp()
    };
  });
}

function repairNoOpPlanMembership() {
  state.assessedCandidates.forEach((candidate) => {
    const savedDecision = state.session.decisions[candidate.key];
    if (!savedDecision?.inPlan || savedDecision.action !== "no-change" || savedDecision.retireHostedRuleIds.length
      || !isCurrentMappedNoChangeNoOp(candidate)) return;
    removeCandidateFromBulkOperations(candidate.key);
    state.session.decisions[candidate.key] = { ...savedDecision, ...createPlanMembership() };
  });
}

function getActiveExcludedCandidates() {
  return state.assessedCandidates.filter((candidate) => !candidate.assessment.hostedApplicable && !getApplicabilityOverride(candidate));
}

function defaultDecision(candidate) {
  const assessment = candidate.assessment || getPriorAssessment(candidate);
  const existingRule = getCatalogStatus(candidate).rules[0] || null;
  return {
    sourceHash: candidate.hash,
    action: "no-change",
    ...createPlanMembership(),
    rationale: "",
    proposedText: assessment?.proposedText || (candidate.sourceType === "upstream" ? "" : extractRuleBody(candidate.text)),
    retireHostedRuleIds: [...candidate.recommendation.retireHostedRuleIds],
    proposedHostedRuleId: String(assessment?.proposedHostedRuleId || ""),
    implementationModels: candidate.recommendation?.category === "implementation"
      ? [...(existingRule?.implementationModels || ["legacy", "typed"])]
      : [],
    assessment,
    updatedAt: toUtcTimestamp()
  };
}

function getPriorAssessment(candidate) {
  const prior = candidate.priorDecision;
  if (candidate.state !== "current" || prior?.selectionFactors?.scoringStatus !== "scored") return null;
  const factors = Object.fromEntries(FACTORS.map(([name]) => [name, Number(prior.selectionFactors[name])]));
  if (Object.values(factors).some((value) => !Number.isInteger(value) || value < 0 || value > 5)) return null;
  return {
    status: "evaluated",
    sourceContentSha256: candidate.hash,
    selectionFactors: factors,
    selectionRationale: String(prior.selectionRationale || ""),
    source: "approved-ledger",
    assessedAt: prior.reviewedOn || null
  };
}

function extractRuleBody(text) {
  return String(text || "").replace(/^### [^\n]+\n+/, "").replace(/^- Rule:\s*/m, "").trim();
}

function getDecision(candidate) {
  const saved = state.session.decisions[candidate.key];
  if (!saved || saved.sourceHash !== candidate.hash) return defaultDecision(candidate);
  const defaults = defaultDecision(candidate);
  const proposedText = String(saved.proposedText ?? defaults.proposedText);
  const ownRuleId = candidate.catalogMapping.hostedRuleId || candidate.recommendation.hostedId;
  const availableRetirementIds = new Set(state.bundle.catalog.rules
    .filter((rule) => rule.status === "active" && rule.id !== ownRuleId).map((rule) => rule.id));
  const retireHostedRuleIds = saved.retireHostedRuleIds.filter((ruleId) => availableRetirementIds.has(ruleId));
  const allowedActions = getAllowedActions(candidate, proposedText);
  if (![null, "no-change", "add", "update", "retire", "restore", "exclude", "defer"].includes(saved.action)
    || !isValidPlanMembership(saved, candidate.key)) return defaultDecision(candidate);
  return {
    ...saved,
    action: allowedActions.includes(saved.action) ? saved.action : null,
    proposedText,
    retireHostedRuleIds,
    proposedHostedRuleId: defaults.proposedHostedRuleId,
    inPlan: saved.inPlan,
    planMembershipSource: saved.planMembershipSource,
    bulkOperationId: saved.bulkOperationId,
    rationale: String(saved.rationale || "").slice(0, DECISION_RATIONALE_MAX_LENGTH),
    implementationModels: candidate.recommendation?.category === "implementation"
      ? IMPLEMENTATION_MODELS.filter((model) => (saved.implementationModels || defaults.implementationModels).includes(model))
      : [],
    assessment: candidate.assessment || getPriorAssessment(candidate),
  };
}

function hasMaintainerEditedRuleText(candidate, proposedText = getDecision(candidate).proposedText) {
  return String(proposedText || "").replace(/\r\n/g, "\n") !== String(candidate.recommendation.ruleText || "").replace(/\r\n/g, "\n");
}

function encodeBase64Utf8(value) {
  const bytes = new TextEncoder().encode(value);
  let binary = "";
  bytes.forEach((byte) => { binary += String.fromCharCode(byte); });
  return btoa(binary);
}

function getAvailableRetirementRuleIds(candidate, decision = getDecision(candidate)) {
  return [...new Set([
    ...candidate.recommendation.retireHostedRuleIds,
    ...decision.retireHostedRuleIds
  ])];
}

function syncProposedRuleControls(candidate) {
  if (getActiveCandidate()?.key !== candidate.key) return;
  const textarea = elements["assessment-panel"].querySelector('[data-decision-field="proposedText"]');
  const save = elements["assessment-panel"].querySelector("[data-proposed-text-save]");
  const reset = elements["assessment-panel"].querySelector("[data-proposed-text-reset]");
  if (!textarea || !save) return;
  const decision = getDecision(candidate);
  if (reset) reset.disabled = !hasMaintainerEditedRuleText(candidate, textarea.value) && !hasMaintainerEditedRuleText(candidate);
  const dirty = textarea.value !== decision.proposedText;
  save.disabled = !dirty;
}

async function loadWorkbenchRuntimeConfig(signal) {
  const response = await fetch("/runtime-config", { cache: "no-store", signal });
  if (!response.ok) throw new Error(`Workbench runtime configuration failed with ${response.status}`);
  const config = await response.json();
  if (!/^[0-9a-f]{64}$/.test(config?.operationToken || "")) throw new Error("Workbench runtime configuration is invalid");
  globalThis.__HOSTED_RULE_WORKBENCH__ = config;
  return config;
}

function isActionableDecision(decision) {
  return ["add", "update", "retire", "restore", "exclude", "defer"].includes(decision.action)
    || decision.retireHostedRuleIds.length > 0;
}

function formatPlanAction(decision) {
  const primaryAction = isPromotionAction(decision.action) ? formatRecommendation(decision.action) : "";
  const retirementAction = decision.retireHostedRuleIds.length ? `Retire ${formatNumber(decision.retireHostedRuleIds.length)}` : "";
  return [primaryAction, retirementAction].filter(Boolean).join(" + ") || formatRecommendation(decision.action);
}

function getAncillaryRetirementRules(decision) {
  const retirementIds = new Set(decision.retireHostedRuleIds);
  return state.bundle.catalog.rules.filter((rule) => retirementIds.has(rule.id) && rule.status === "active");
}

function canEditImplementationModels(candidate, action = getDecision(candidate).action) {
  return candidate.recommendation?.category === "implementation" && ["add", "update"].includes(action);
}

function getEffectiveHostedRuleId(candidate) {
  return candidate.assessment.proposedHostedRuleId || candidate.assessment.targetHostedRuleId || candidate.assessment.assessmentId;
}

function getCatalogStatus(candidate) {
  if (candidate.catalogMapping.state === "active") return { key: "mapped", label: "Mapped", rules: candidate.mappedHostedRules };
  if (candidate.catalogMapping.state === "retired") return { key: "retired", label: "Retired", rules: candidate.mappedHostedRules };
  return { key: "unmapped", label: "Not Mapped", rules: [] };
}

function renderCatalogStatusBadge(catalogStatus) {
  return `<span class="ui-badge status-capsule catalog-status ${escapeHtml(catalogStatus.key)}">${escapeHtml(catalogStatus.label)}</span>`;
}

function renderDetailHeaderActions(statuses) {
  return `
    <div class="detail-header-actions">
      <span class="assessment-title-statuses">${statuses}</span>
      <button class="scroll-edge-button clickable detail-back-to-top" type="button" data-detail-back-to-top aria-label="Back to top" data-workbench-tooltip="Back to top" disabled>${icon("chevron-up")}</button>
    </div>
  `;
}

function renderCurrentHostedRules(catalogStatus) {
  if (!catalogStatus.rules.length) return "";
  return catalogStatus.rules.map((rule) => {
    return `<div class="current-hosted-rule">
      <div class="current-hosted-rule-heading"><span class="section-label">Current Hosted Rule: <strong class="rule-reference">${escapeHtml(rule.id)}</strong></span><span class="current-hosted-rule-statuses"><span class="ui-badge status-capsule catalog-status ${escapeHtml(rule.status)}">${escapeHtml(capitalize(rule.status))}</span></span></div>
      <pre class="evidence-box scroll-surface">${escapeHtml(rule.text)}</pre></div>`;
  }).join("");
}

function getAllowedActions(candidate, proposedText = defaultDecision(candidate).proposedText) {
  const catalogStatus = getCatalogStatus(candidate).key;
  if (catalogStatus === "mapped") {
    const hasRetirements = state.session.decisions[candidate.key]?.retireHostedRuleIds?.length > 0;
    const actions = isCurrentMappedNoChangeNoOp(candidate) && !hasRetirements ? [] : ["no-change"];
    if (hasHostedTextChange(candidate, proposedText)) actions.push("update");
    return [...actions, "retire", "defer"];
  }
  if (catalogStatus === "retired") return ["no-change", "restore", "defer"];
  return ["no-change", "add", "exclude", "defer"];
}

function isCurrentMappedNoChangeNoOp(candidate) {
  return candidate.state === "current"
    && getCatalogStatus(candidate).key === "mapped"
    && candidate.assessment?.recommendation === "no-change"
    && candidate.recommendation.retireHostedRuleIds.length === 0
    && !getApplicabilityOverride(candidate);
}

function canSelectCandidateForPlan(candidate, decision = getDecision(candidate)) {
  return !isCurrentMappedNoChangeNoOp(candidate) || isPromotionAction(decision.action) || decision.retireHostedRuleIds.length > 0;
}

function getCurrentHostedText(candidate) {
  return getCatalogStatus(candidate).rules[0]?.text || "";
}

function hasHostedTextChange(candidate, proposedText) {
  const normalize = (value) => String(value || "").replace(/\r\n/g, "\n");
  return normalize(getCurrentHostedText(candidate)) !== normalize(proposedText);
}

function getDefaultPlanAction(candidate, recommendation) {
  const allowedActions = getAllowedActions(candidate, defaultDecision(candidate).proposedText);
  if (isPromotionAction(recommendation) && allowedActions.includes(recommendation)) return recommendation;
  if (allowedActions.includes("restore")) return "restore";
  if (allowedActions.includes("update")) return "update";
  if (allowedActions.includes("add")) return "add";
  return "no-change";
}

function isPromotionAction(action) {
  return ["add", "update", "retire", "restore"].includes(action);
}

function getBaselineAssessment(candidate, decision) {
  const assessment = decision.assessment || candidate.assessment;
  if (assessment?.status !== "evaluated" || !assessment.selectionRationale?.trim() || !assessment.summary?.trim()) return null;
  const factors = assessment.selectionFactors;
  const valid = factors
    && FACTORS.every(([name]) => Number.isInteger(factors[name]) && factors[name] >= 0 && factors[name] <= 5)
    && ["add", "update", "retire", "restore", "no-change", "exclude", "defer"].includes(assessment.recommendation)
    && Number.isInteger(assessment.guardedTokenDelta)
    && typeof assessment.hostedApplicable === "boolean"
    && Boolean(assessment.applicabilityRationale?.trim())
    && Boolean(assessment.hostedCategory)
    && assessment.sourceContentSha256 === candidate.hash;
  return valid ? { ...assessment, factors, rationale: assessment.selectionRationale } : null;
}

function getAssessment(candidate, decision = getDecision(candidate)) {
  return getBaselineAssessment(candidate, decision);
}

function updateDecision(candidate, changes) {
  const current = getDecision(candidate);
  if (changes.inPlan === true && !canSelectCandidateForPlan(candidate, { ...current, ...changes })) return;
  const { assessment, ...maintainerDecision } = current;
  const promotesManualMembership = changes.inPlan === true
    || (current.inPlan && current.planMembershipSource === "bulk" && Object.keys(changes).some((key) => key !== "inPlan"));
  if (promotesManualMembership) removeCandidateFromBulkOperations(candidate.key);
  saveDecision(candidate, {
    ...maintainerDecision,
    ...changes,
    ...(promotesManualMembership ? createPlanMembership("manual") : {})
  });
}

function removePlanMembership(candidate) {
  const { assessment, ...maintainerDecision } = getDecision(candidate);
  prepareRuleIssueRestore([candidate.key]);
  removeCandidateFromBulkOperations(candidate.key);
  saveDecision(candidate, { ...maintainerDecision, ...createPlanMembership() });
}

function removeCandidateFromBulkOperations(candidateKey, session = state.session) {
  session.bulkOperations = session.bulkOperations
    .map((operation) => ({ ...operation, candidateKeys: operation.candidateKeys.filter((key) => key !== candidateKey) }))
    .filter((operation) => operation.candidateKeys.length > 0);
}

function restoreBulkOperationMembership(candidateKey, operationSnapshot) {
  if (!operationSnapshot) return;
  const existing = state.session.bulkOperations.find((operation) => operation.id === operationSnapshot.id);
  if (existing) {
    if (!existing.candidateKeys.includes(candidateKey)) {
      existing.candidateKeys.push(candidateKey);
    }
    return;
  }
  state.session.bulkOperations.push({
    ...operationSnapshot,
    candidateKeys: [candidateKey]
  });
}

function clearCandidateDecision(candidateKey) {
  delete state.session.decisions[candidateKey];
}

function hasOriginalRuleResetChanges(candidate, proposedText = getDecision(candidate).proposedText) {
  return hasMaintainerEditedRuleText(candidate, proposedText) || hasMaintainerEditedRuleText(candidate);
}

async function persistProposedRuleText(candidate, proposedText) {
  if (proposedText === getDecision(candidate).proposedText) return true;
  const before = JSON.stringify(state.session);
  const editor = elements["assessment-panel"].querySelector('[data-decision-field="proposedText"]');
  const editorText = editor?.value;
  const assertCurrent = () => {
    if (JSON.stringify(state.session) !== before || (editor?.isConnected && editor.value !== editorText)) {
      throw new Error("The draft changed. Review the wording and try again.");
    }
  };
  const nextSession = structuredClone(state.session);
  const { assessment, ...decision } = getDecision(candidate);
  const updatedAt = toUtcTimestamp();
  nextSession.decisions[candidate.key] = {
    ...decision,
    action: getAllowedActions(candidate, proposedText).includes(decision.action) ? decision.action : null,
    proposedText,
    sourceHash: candidate.hash,
    updatedAt
  };
  nextSession.updatedAt = updatedAt;
  try {
    await persistSession(nextSession, assertCurrent);
    try { assertCurrent(); }
    catch (error) {
      await persistSession();
      throw error;
    }
    state.session = nextSession;
    return true;
  } catch (error) {
    showToast(`Rule wording was not saved: ${error.message}`, true);
    return false;
  }
}

async function resetOriginalRule(candidate) {
  const content = elements["assessment-panel"].querySelector(".assessment-content");
  const scrollTop = content?.scrollTop || 0;
  if (!await persistProposedRuleText(candidate, defaultDecision(candidate).proposedText)) return;
  renderAll();
  showCandidatePane("details");
  const refreshedContent = elements["assessment-panel"].querySelector(".assessment-content");
  if (refreshedContent) refreshedContent.scrollTop = scrollTop;
  elements["assessment-panel"].querySelector('[data-decision-field="proposedText"]')?.focus({ preventScroll: true });
  showToast("Original rule proposal restored.");
}

function openOriginalRuleResetDialog(candidate, trigger) {
  if (elements["assessment-panel"].querySelector("[data-rule-reset-dialog]")) return;
  const dialog = document.createElement("dialog");
  dialog.className = "modal-dialog modal-dialog-warning";
  dialog.setAttribute("data-rule-reset-dialog", "");
  dialog.dataset.candidateKey = candidate.key;
  dialog.setAttribute("aria-labelledby", "rule-reset-dialog-title");
  dialog.innerHTML = `<div class="modal-dialog-heading"><div class="modal-dialog-title">${icon("debug-restart")}<h2 id="rule-reset-dialog-title">Reset Rule to Original?</h2></div><button class="titlebar-icon clickable" type="button" data-rule-reset-cancel aria-label="Close confirmation" data-workbench-tooltip="Close">${icon("close")}</button></div><div class="modal-dialog-content"><p>Restore the original proposed wording for <strong class="rule-reference">${escapeHtml(getEffectiveHostedRuleId(candidate))}</strong>?</p><p>This will replace the saved wording for this proposal.</p><div class="modal-dialog-actions"><button class="button primary clickable" type="button" data-rule-reset-cancel>Cancel</button><button class="button review clickable" type="button" data-rule-reset-confirm>${icon("debug-restart")}<span class="button-label">Reset to Original</span></button></div></div>`;
  dialog.addEventListener("close", () => { dialog.remove(); if (trigger.isConnected) trigger.focus({ preventScroll: true }); }, { once: true });
  dialog.addEventListener("click", event => {
    const rect = dialog.getBoundingClientRect();
    if (event.target === dialog && (event.clientX < rect.left || event.clientX > rect.right || event.clientY < rect.top || event.clientY > rect.bottom)) dialog.close();
  });
  elements["assessment-panel"].append(dialog);
  dialog.showModal();
  dialog.querySelector("[data-rule-reset-cancel]:not(.titlebar-icon)").focus();
}

function saveDecision(candidate, decision) {
  if (decision) {
    const { assessment, ...maintainerDecision } = decision;
    state.session.decisions[candidate.key] = {
      ...maintainerDecision,
      sourceHash: candidate.hash,
      updatedAt: toUtcTimestamp()
    };
  } else {
    clearCandidateDecision(candidate.key);
  }
  state.session.updatedAt = toUtcTimestamp();
  persistSession();
  syncCandidateTreeRows();
  renderBulkActions();
  renderDecisionOutputs();
}

function clearCandidateSelection(candidate) {
  if (state.activeKey === candidate.key) state.activeKey = null;
  if (state.assessmentActiveKey === candidate.key) state.assessmentActiveKey = null;
  state.rationaleReturnView = null;
}

async function updateOverrideLifecycle(candidate, override, decision) {
  if (override) state.session.applicabilityOverrides[candidate.key] = structuredClone(override);
  else delete state.session.applicabilityOverrides[candidate.key];
  if (decision) {
    const { assessment, ...maintainerDecision } = decision;
    state.session.decisions[candidate.key] = {
      ...maintainerDecision,
      sourceHash: candidate.hash,
      updatedAt: toUtcTimestamp()
    };
  } else {
    clearCandidateDecision(candidate.key);
  }
  clearCandidateSelection(candidate);
  state.session.updatedAt = toUtcTimestamp();
  refreshEffectiveCandidates();
  await persistSession();
  renderAll();
  showCandidatePane("candidates");
}

async function resetCandidate(candidate) {
  removeCandidateFromBulkOperations(candidate.key);
  if (getApplicabilityOverride(candidate)) {
    await updateOverrideLifecycle(candidate, null, null);
    return;
  }
  saveDecision(candidate, null);
  clearCandidateSelection(candidate);
  await persistencePromise;
  renderAll();
  showCandidatePane("candidates");
}

function renderDecisionOutputs() {
  renderMetrics();
  renderPlan();
  renderCapacity();
  renderPreview();
  renderCounts();
  refreshPresentation();
}

function calculateImpact(factors) {
  const score = 6 * factors.severity
    + 3 * factors.frequency
    + 3 * factors.breadth
    + 4 * factors.hostedDetectability
    + 4 * factors.evidenceStrength
    - 5 * factors.falsePositiveRisk
    - 3 * factors.redundancy;
  return Math.max(0, score);
}

function estimateGuardedTokens(text) {
  const estimated = Math.ceil(String(text || "").length / 4);
  return Math.ceil(estimated * (1 + state.bundle.guidanceCapacity.safetyMarginPercent / 100));
}

function getAssessmentTokenValue(candidate, assessment, decision = getDecision(candidate)) {
  if (!getApplicabilityOverride(candidate) || assessment.guardedTokenDelta !== 0) return assessment.guardedTokenDelta;
  return estimateGuardedTokens(decision.proposedText || candidate.text);
}

function getActionTokenDelta(candidate, action, decision = getDecision(candidate)) {
  if (!isPromotionAction(action)) return 0;
  if (action === "retire") return -estimateGuardedTokens(getCurrentHostedText(candidate));
  const assessment = getAssessment(candidate, decision);
  if (assessment && assessment.guardedTokenDelta !== 0) return assessment.guardedTokenDelta;
  const proposedTokens = estimateGuardedTokens(decision.proposedText || candidate.text);
  if (action === "update") return proposedTokens - estimateGuardedTokens(getCurrentHostedText(candidate));
  return proposedTokens;
}

function getDecisionTokenDelta(candidate, decision = getDecision(candidate)) {
  const retirementDelta = getAncillaryRetirementRules(decision)
    .reduce((sum, rule) => sum - estimateGuardedTokens(rule.text), 0);
  return getActionTokenDelta(candidate, decision.action, decision) + retirementDelta;
}

function getCandidateTokenValue(candidate, assessment) {
  const decision = getDecision(candidate);
  if (getApplicabilityOverride(candidate)) {
    if (decision.action === "retire") return -estimateGuardedTokens(getCurrentHostedText(candidate));
    return getAssessmentTokenValue(candidate, assessment, decision);
  }
  if (assessment.recommendation === "retire") return -estimateGuardedTokens(getCurrentHostedText(candidate));
  if (["add", "update", "restore"].includes(assessment.recommendation)) return assessment.guardedTokenDelta;
  return estimateGuardedTokens(getCurrentHostedText(candidate));
}

function formatCandidateTokenValue(candidate, assessment) {
  const value = getCandidateTokenValue(candidate, assessment);
  if (getApplicabilityOverride(candidate)) return isActionableDecision(getDecision(candidate)) ? formatSignedNumber(value) : formatNumber(value);
  return ["add", "update", "retire", "restore"].includes(assessment.recommendation) ? formatSignedNumber(value) : formatNumber(value);
}

function renderAll(shouldRenderAssessment = true) {
  if (!state.bundle || !state.session) return;
  renderTarget();
  renderMetrics();
  renderCandidateList();
  if (shouldRenderAssessment) renderAssessment();
  renderAssessmentResults();
  renderRuleIssues();
  renderPlan();
  renderCapacity();
  renderPreview();
  renderCounts();
  refreshPresentation();
}

function renderTarget() {
  const target = globalThis.__HOSTED_RULE_WORKBENCH__?.targetRepository;
  if (target?.status === "validated") {
    const targetLabel = `${target.repository} ${target.branch}@${target.commit.slice(0, 8)}`;
    const behindBy = Number(target.behindBy) || 0;
    const aheadBy = Number(target.aheadBy) || 0;
    const syncIndicators = [];
    if (behindBy > 0) syncIndicators.push(`↓ ${behindBy}`);
    if (aheadBy > 0) syncIndicators.push(`↑ ${aheadBy}`);
    elements["status-target"].removeAttribute("title");
    elements["status-target"].removeAttribute("data-truncation-tooltip");
    workbenchStatusBar.update("target", {
      text: targetLabel,
      tooltip: [targetLabel, ...syncIndicators].join(" | "),
      ariaLabel: `${targetLabel}.${behindBy > 0 ? ` ${behindBy} commits behind ${target.upstreamRepository} ${target.upstreamBranch}.` : ""}${aheadBy > 0 ? ` ${aheadBy} commits ahead.` : ""}`,
      kind: behindBy > 0 ? "warning" : "standard"
    });
    return;
  }
  const reason = target?.reason || "Promotion target could not be resolved";
  workbenchStatusBar.update("target", { text: "Target unavailable", tooltip: reason, ariaLabel: reason, kind: "error" });
}

function renderMetrics() {
  const excludedCount = getActiveExcludedCandidates().length;
  const capacity = getGuidanceCapacityProjection();
  workbenchStatusBar.update("excluded", { text: formatNumber(excludedCount) });
  workbenchStatusBar.update("mapped", { text: formatNumber(state.candidates.filter((candidate) => getCatalogStatus(candidate).key === "mapped").length) });
  workbenchStatusBar.update("unmapped", { text: formatNumber(state.candidates.filter((candidate) => getCatalogStatus(candidate).key === "unmapped").length) });
  workbenchStatusBar.update("capacity", { text: formatNumber(capacity.projectedHeadroomTokens) });
  const openIssues = getOpenRuleIssues();
  const issueCount = openIssues.length;
  const issueSummary = formatRuleIssueSummary(openIssues);
  workbenchStatusBar.update("ruleIssues", {
    text: formatNumber(issueCount),
    tooltip: issueSummary,
    ariaLabel: `Open ${formatCountLabel(issueCount, "Rule Issue")}. ${issueSummary}`,
    hidden: false,
    kind: issueCount > 0 ? "warning" : "standard"
  });
  renderValidationIssues();
}

function getFilteredCandidates() {
  const query = state.queries["candidate-sources"].trim().toLowerCase();
  const catalogStatusFilter = getCandidateCatalogStatusFilter(query);
  return state.candidates.filter((candidate) => {
    if (catalogStatusFilter && getCatalogStatus(candidate).key !== catalogStatusFilter) return false;
    if (!query || catalogStatusFilter) return true;
    return [getEffectiveHostedRuleId(candidate), candidate.id, candidate.title, candidate.sourceId, candidate.sourceTitle, candidate.sourcePath, candidate.text, candidate.category, candidate.sourceLabel,
      ...candidate.members.flatMap((member) => [member.source.id, member.source.title, member.source.location, member.source.text, member.assessment.sourceMeaning, member.meaningCoverageRationale])]
      .some((value) => String(value || "").toLowerCase().includes(query));
  });
}

function getCandidateCatalogStatusFilter(query = state.queries["candidate-sources"].trim().toLowerCase()) {
  const match = /^status:(mapped|unmapped)$/.exec(query);
  return match?.[1] || null;
}

function getBestCandidateSearchMatch() {
  const query = state.queries["candidate-sources"].trim().toLowerCase();
  if (!query) return null;
  const rank = (candidate) => {
    const values = [getEffectiveHostedRuleId(candidate), candidate.id, candidate.sourceId, candidate.title, candidate.sourceTitle]
      .map((value) => String(value || "").toLowerCase());
    if (values.some((value) => value === query)) return 0;
    if (values.some((value) => value.startsWith(query))) return 1;
    return 2;
  };
  return getFilteredCandidates().sort((left, right) => rank(left) - rank(right) || getEffectiveHostedRuleId(left).localeCompare(getEffectiveHostedRuleId(right)))[0] || null;
}

function revealCandidateInTree(key) {
  if (!candidateHierarchicalView) return null;
  const node = candidateHierarchicalView.model.nodes.find((item) => item.data?.candidate?.key === key);
  if (!node) return null;
  let changed = false;
  for (let ancestor = node.parent; ancestor; ancestor = ancestor.parent) {
    if (!ancestor.children.length || ancestor.expanded) continue;
    ancestor.expanded = true;
    candidateExpansionState.set(ancestor.id, true);
    changed = true;
  }
  if (changed) {
    candidateHierarchicalView.model.flatten();
    candidateHierarchicalView.layout.recalculate();
    candidateHierarchicalView.renderNaturalRows();
    candidateHierarchicalView.stickyController.update();
  }
  return node;
}

function navigateCandidateSearch({ scroll = true } = {}) {
  elements["candidate-list"].querySelectorAll(".candidate-tree-row.search-match").forEach((row) => row.classList.remove("search-match"));
  const candidate = getBestCandidateSearchMatch();
  if (!candidate) return;
  if (candidateHierarchicalView) {
    const node = revealCandidateInTree(candidate.key);
    if (!node) return;
    const row = elements["candidate-list"].querySelector(`[data-candidate-key="${CSS.escape(candidate.key)}"]`);
    row?.classList.add("search-match");
    if (scroll) elements["candidate-list"].scrollTop = Math.max(0, node.layoutTop - (elements["candidate-list"].clientHeight - node.rowHeight) / 2);
    return;
  }
  const row = elements["candidate-list"].querySelector(`[data-candidate-key="${CSS.escape(candidate.key)}"]`);
  if (!row) return;
  for (let ancestor = row.parentElement; ancestor && ancestor !== elements["candidate-list"]; ancestor = ancestor.parentElement) {
    if (ancestor.matches("details.candidate-category, details.candidate-source-root")) ancestor.setAttribute("open", "");
  }
  row.classList.add("search-match");
  if (scroll) row.scrollIntoView({ block: "center" });
}

function getBulkActionCandidates(recommendationScope) {
  const recommendations = recommendationScope === "actionable" ? ["add", "update"] : [recommendationScope];
  return getFilteredCandidates().filter((candidate) => {
    if (state.session.decisions[candidate.key]) return false;
    const decision = getDecision(candidate);
    const assessment = getAssessment(candidate, decision);
    return !decision.inPlan
      && assessment && recommendations.includes(assessment.recommendation)
      && getAllowedActions(candidate, decision.proposedText).includes(assessment.recommendation);
  });
}

function getLatestBulkOperation() {
  return state.session.bulkOperations.at(-1) || null;
}

function renderBulkActions() {
  const identity = getValidatedCodeOwnerIdentity();
  const unavailableReason = globalThis.__HOSTED_RULE_WORKBENCH__?.maintainerIdentity?.reason || "A validated Hosted CODEOWNER identity is required.";
  const filtered = getFilteredCandidates();
  const addCandidates = getBulkActionCandidates("add");
  const updateCandidates = getBulkActionCandidates("update");
  const actionableCandidates = getBulkActionCandidates("actionable");
  elements["bulk-scope-count"].textContent = formatCountLabel(filtered.length, "Candidate");
  elements["bulk-add-count"].textContent = formatCountLabel(addCandidates.length, "Candidate");
  elements["bulk-update-count"].textContent = formatCountLabel(updateCandidates.length, "Candidate");
  elements["bulk-actionable-count"].textContent = formatCountLabel(actionableCandidates.length, "Candidate");
  const setBulkCommandState = (selector, count) => {
    const button = elements["bulk-actions"].querySelector(selector);
    button.disabled = !identity || count === 0;
    setWorkbenchTooltip(button, identity ? "" : unavailableReason);
  };
  setBulkCommandState('[data-bulk-scope="add"]', addCandidates.length);
  setBulkCommandState('[data-bulk-scope="update"]', updateCandidates.length);
  setBulkCommandState('[data-bulk-scope="actionable"]', actionableCandidates.length);
  const latest = getLatestBulkOperation();
  elements["bulk-undo"].disabled = !identity || !latest;
  setWorkbenchTooltip(elements["bulk-undo"], identity ? "" : unavailableReason);
  elements["bulk-undo-count"].textContent = latest ? formatCountLabel(latest.candidateKeys.length, "Candidate") : "None";
  elements["bulk-actions-note"].textContent = identity
    ? "Bulk actions accept evaluated recommendations with attributed decision rationale."
    : unavailableReason;
}

function handleBulkActionsClick(event) {
  const scopeButton = event.target.closest("[data-bulk-scope]");
  if (scopeButton) {
    applyBulkSelection(scopeButton.dataset.bulkScope);
    return;
  }
  if (event.target.closest("[data-bulk-undo]")) undoBulkOperation(getLatestBulkOperation()?.id);
}

function handleBulkActionsMouseLeave() {
  elements["bulk-actions"].removeAttribute("open");
}

function renderBulkSelectionOutputs() {
  syncCandidateTreeRows();
  renderBulkActions();
  renderAssessment();
  renderDecisionOutputs();
}

function getBulkDecisionRationale(candidate, recommendation) {
  if (recommendation === "add") {
    const coverage = getCatalogStatus(candidate).key === "retired"
      ? "has only retired Hosted catalog coverage"
      : "has no active Hosted catalog mapping";
    return `Bulk accepted the AI recommendation to Add. This candidate is applicable and ${coverage}.`;
  }
  if (recommendation === "update") {
    return "Bulk accepted the AI recommendation to Update. This candidate is applicable, has active Hosted catalog coverage, and the evaluated source guidance differs.";
  }
  throw new Error(`Unsupported bulk recommendation: ${recommendation}`);
}

function applyBulkSelection(recommendationScope) {
  const identity = getValidatedCodeOwnerIdentity();
  if (!identity) {
    showToast(globalThis.__HOSTED_RULE_WORKBENCH__?.maintainerIdentity?.reason || "A validated Hosted CODEOWNER identity is required.", true);
    return;
  }
  const candidates = getBulkActionCandidates(recommendationScope);
  if (!candidates.length) return;
  const selections = candidates.map((candidate) => {
    const decision = getDecision(candidate);
    const assessment = getAssessment(candidate, decision);
    if (!assessment) throw new Error("A current complete assessment is required before accepting bulk recommendations");
    delete decision.assessment;
    return { candidate, decision, recommendation: assessment.recommendation };
  });
  const operation = {
    id: crypto.randomUUID(),
    createdAt: toUtcTimestamp(),
    action: recommendationScope,
    candidateKeys: candidates.map((candidate) => candidate.key)
  };
  state.session.bulkOperations.push(operation);
  selections.forEach(({ candidate, decision, recommendation }) => {
    state.session.decisions[candidate.key] = {
      ...decision,
      action: recommendation,
      rationale: getBulkDecisionRationale(candidate, recommendation),
      ...createPlanMembership("bulk", operation.id),
      sourceHash: candidate.hash,
      updatedAt: operation.createdAt
    };
  });
  state.session.updatedAt = operation.createdAt;
  persistSession();
  elements["bulk-actions"].removeAttribute("open");
  renderBulkSelectionOutputs();
  showToast(`${formatCountLabel(candidates.length, "Candidate")} added to the promotion plan.`);
}

function undoBulkOperation(operationId) {
  if (!getValidatedCodeOwnerIdentity()) {
    showToast(globalThis.__HOSTED_RULE_WORKBENCH__?.maintainerIdentity?.reason || "A validated Hosted CODEOWNER identity is required.", true);
    return;
  }
  const operation = state.session.bulkOperations.find((item) => item.id === operationId);
  if (!operation) return;
  let removed = 0;
  operation.candidateKeys.forEach((key) => {
    const decision = state.session.decisions[key];
    if (decision?.planMembershipSource !== "bulk" || decision.bulkOperationId !== operation.id) return;
    clearCandidateDecision(key);
    removed += 1;
  });
  state.session.bulkOperations = state.session.bulkOperations.filter((item) => item.id !== operation.id);
  state.session.updatedAt = toUtcTimestamp();
  persistSession();
  renderBulkSelectionOutputs();
  showToast(`${formatCountLabel(removed, "Candidate")} removed by bulk Undo.`);
}

function getPlanUndoCandidates(scope) {
  const candidates = getPlanCandidates();
  return scope === "all"
    ? candidates
    : candidates.filter((candidate) => getDecision(candidate).planMembershipSource === scope);
}

function handlePlanUndoMenuClick(event) {
  if (event.target.closest("summary") && elements["plan-undo-trigger"].getAttribute("aria-disabled") === "true") {
    event.preventDefault();
    return;
  }
  const command = event.target.closest("[data-plan-undo-scope]");
  if (!command || command.disabled) return;
  undoPlan(command.dataset.planUndoScope);
}

async function undoPlan(scope) {
  if (!["all", "manual", "bulk", "override"].includes(scope)) return;
  const candidates = getPlanUndoCandidates(scope);
  if (!candidates.length) return;
  prepareRuleIssueRestore(candidates.map((candidate) => candidate.key));
  candidates.forEach((candidate) => {
    removeCandidateFromBulkOperations(candidate.key);
    clearCandidateDecision(candidate.key);
    delete state.session.applicabilityOverrides[candidate.key];
    clearCandidateSelection(candidate);
  });
  state.session.updatedAt = toUtcTimestamp();
  refreshEffectiveCandidates();
  elements["plan-undo-menu"].removeAttribute("open");
  await persistSession();
  renderAll();
  showCandidatePane("candidates");
  showToast(`${formatCountLabel(candidates.length, "Candidate")} removed and reset.`);
}

function getCandidateDecoration(candidate) {
  const selected = getDecision(candidate).inPlan;
  if (!selected) return null;
  const ready = getPlanReadiness(candidate).ready;
  return {
    status: ready ? "ready" : "needs-input",
    description: ready ? "Selected, ready for promotion" : "Selected, needs input before promotion"
  };
}

function getCandidateAggregateDecoration(candidates) {
  const selected = candidates.filter((candidate) => getDecision(candidate).inPlan);
  if (!selected.length) return null;
  const needsInput = selected.filter((candidate) => !getPlanReadiness(candidate).ready).length;
  return {
    status: needsInput ? "needs-input" : "ready",
    description: needsInput
        ? `${formatNumber(selected.length)} selected, ${formatNumber(needsInput)} ${needsInput === 1 ? "needs" : "need"} input`
        : `${formatNumber(selected.length)} selected, all ready for promotion`
  };
}

function renderCandidateDecoration(decoration, className, includeTooltip = true) {
  const hidden = decoration ? "" : " hidden";
  const tooltip = decoration && includeTooltip ? ` data-workbench-tooltip="${escapeHtml(decoration.description)}"` : "";
  const description = decoration ? escapeHtml(decoration.description) : "";
  return `<svg class="codicon ${className}" aria-hidden="true"${tooltip}${hidden}><use href="icons/codicons/sprite.svg#codicon-diff-modified"></use></svg><span class="candidate-decoration-description sr-only">${description}</span>`;
}

function renderCandidateAggregateDecoration(decoration) {
  return renderCandidateDecoration(decoration, "candidate-parent-decoration-icon", false);
}

function renderCandidateAggregateAttributes(decoration) {
  return decoration ? ` data-selection-status="${decoration.status}"` : "";
}

function renderCandidateCountBadge(count, singular, decoration) {
  const tooltip = decoration ? ` data-workbench-tooltip="${escapeHtml(decoration.description)}"` : "";
  return `<span class="ui-badge count-badge type-compact"${tooltip}>${formatCountLabel(count, singular)}</span>`;
}

function candidateAggregateClass(decoration) {
  return decoration ? ` candidate-aggregate-${decoration.status}` : "";
}

function getCandidateExpansion(nodeId, expandedByDefault = false) {
  return candidateExpansionState.has(nodeId) ? candidateExpansionState.get(nodeId) : expandedByDefault;
}

function buildCandidateLeafNodes(sectionKey, candidates, override = false) {
  const headerId = `candidate:header:${sectionKey}`;
  return [{
    id: headerId,
    kind: "header",
    expanded: true,
    data: { sectionKey, override },
    children: sortCandidates(candidates, getCandidateSort(sectionKey)).map((candidate) => ({
      id: `candidate:leaf:${candidate.key}`,
      kind: "leaf",
      stickyEligible: false,
      data: { candidate, override }
    }))
  }];
}

function buildCandidateFolderNode({ id, label, sourceType, candidates, sectionKey, override = false, expandedByDefault = false, extraClass = "" }) {
  return {
    id,
    kind: "folder",
    expanded: getCandidateExpansion(id, expandedByDefault || Boolean(state.queries["candidate-sources"])),
    data: { label, sourceType, candidates, decoration: getCandidateAggregateDecoration(candidates), override, extraClass },
    children: buildCandidateLeafNodes(sectionKey, candidates, override)
  };
}

function buildCandidateTreeNodes() {
  const sources = [
    ["interactive", "Interactive Toolkit"],
    ["upstream", "Contributor Guidance"],
    ["maintainer", "Maintainer Proposals"]
  ];
  const query = state.queries["candidate-sources"].trim().toLowerCase();
  const catalogStatusFilter = getCandidateCatalogStatusFilter(query);
  const visibleCandidates = catalogStatusFilter
    ? state.candidates.filter((candidate) => getCatalogStatus(candidate).key === catalogStatusFilter)
    : state.candidates;
  const overrideCandidates = visibleCandidates.filter((candidate) => getApplicabilityOverride(candidate));
  const regularCandidates = visibleCandidates.filter((candidate) => !getApplicabilityOverride(candidate));
  const protectedRules = state.protectedRules.filter((rule) => !catalogStatusFilter && (!query || [rule.id, rule.title, rule.text, rule.surfaceId, rule.provenance, rule.protectionReason, rule.sourcePath]
    .some((value) => String(value || "").toLowerCase().includes(query))));
  const nodes = [];
  if (overrideCandidates.length || protectedRules.length) {
    const overrideRootId = "candidate:source:overrides";
    const protectedRulesBySurface = protectedRules.reduce((groups, rule) => {
      (groups[rule.surfaceId] ||= []).push(rule);
      return groups;
    }, {});
    const protectedFolders = Object.entries(protectedRulesBySurface).sort(([left], [right]) => left.localeCompare(right)).map(([surfaceId, rules]) => ({
      id: `candidate:protected-folder:${surfaceId}`,
      kind: "protected-folder",
      expanded: getCandidateExpansion(`candidate:protected-folder:${surfaceId}`),
      data: { label: capitalize(surfaceId), rules },
      children: [{
        id: `candidate:protected-header:${surfaceId}`,
        kind: "protected-header",
        expanded: true,
        data: { sectionKey: `protected:${surfaceId}` },
        children: sortProtectedRules(rules, getCandidateSort(`protected:${surfaceId}`)).map((rule) => ({
          id: `candidate:protected-leaf:${rule.id}`,
          kind: "protected-leaf",
          stickyEligible: false,
          data: { rule }
        }))
      }]
    }));
    nodes.push({
      id: overrideRootId,
      kind: "source",
      expanded: getCandidateExpansion(overrideRootId),
      data: { label: "OVERRIDES", sourceType: "overrides", candidates: overrideCandidates, protectedRuleCount: protectedRules.length, decoration: getCandidateAggregateDecoration(overrideCandidates), override: true },
      children: sources.map(([sourceType, label]) => {
        const sourceCandidates = overrideCandidates.filter((candidate) => candidate.sourceType === sourceType);
        if (!sourceCandidates.length) return null;
        const sourceId = `candidate:override-source:${sourceType}`;
        const origins = sourceType === "upstream"
          ? Object.entries(groupCandidatesBySource(sourceCandidates)).sort(([left], [right]) => left.localeCompare(right)).map(([, members]) => [members[0].sourceId, members[0].sourceTitle, members])
          : Object.entries(groupOverrideCandidatesByCategory(sourceCandidates)).sort(([left], [right]) => left.localeCompare(right)).map(([category, members]) => [category, category, members]);
        return {
          id: sourceId,
          kind: "folder",
          expanded: getCandidateExpansion(sourceId),
          data: { label, sourceType, candidates: sourceCandidates, decoration: getCandidateAggregateDecoration(sourceCandidates), override: true, extraClass: "override-source-folder" },
          children: origins.map(([originKey, originLabel, members]) => buildCandidateFolderNode({
            id: `candidate:override-origin:${sourceType}:${originKey}`,
            label: originLabel,
            sourceType,
            candidates: members,
            sectionKey: `overrides:${sourceType}:${originKey}`,
            override: true,
            extraClass: "override-origin-folder"
          }))
        };
      }).filter(Boolean).concat(protectedFolders)
    });
  }
  sources.forEach(([sourceType, label]) => {
    const candidates = regularCandidates.filter((candidate) => candidate.sourceType === sourceType);
    if (!candidates.length) return;
    const sourceId = `candidate:source:${sourceType}`;
    const groups = sourceType === "upstream" ? groupCandidatesBySource(candidates) : groupCandidatesByCategory(candidates);
    nodes.push({
      id: sourceId,
      kind: "source",
      expanded: getCandidateExpansion(sourceId, Boolean(state.queries["candidate-sources"])),
      data: { label, sourceType, candidates, decoration: getCandidateAggregateDecoration(candidates), override: false },
      children: Object.entries(groups).sort(([left], [right]) => left.localeCompare(right)).map(([groupKey, members]) => buildCandidateFolderNode({
        id: `candidate:folder:${sourceType}:${groupKey}`,
        label: sourceType === "upstream" ? members[0].sourceTitle : groupKey,
        sourceType,
        candidates: members,
        sectionKey: sourceType === "upstream" ? `upstream:${members[0].sourceId}` : `${sourceType}:${groupKey}`,
        extraClass: sourceType === "upstream" ? "contributor-document" : ""
      }))
    });
  });
  return nodes;
}

function elementFromHtml(html) {
  const template = document.createElement("template");
  template.innerHTML = html.trim();
  return template.content.firstElementChild;
}

function renderCandidateHierarchyRow(node) {
  if (node.kind === "header") return elementFromHtml(renderCandidateListHeader(node.data.sectionKey, node.depth));
  if (node.kind === "protected-header") return elementFromHtml(renderCandidateListHeader(node.data.sectionKey, node.depth));
  if (node.kind === "protected-leaf") return elementFromHtml(renderProtectedRuleTreeRow(node.data.rule));
  if (node.kind === "protected-folder") {
    return elementFromHtml(`
      <button class="hierarchical-parent-row candidate-folder-row clickable" type="button" data-hierarchical-toggle aria-expanded="${node.expanded}">
        ${icon("folder")}<span class="candidate-parent-label"><strong>${escapeHtml(node.data.label)}</strong></span>${renderCandidateCountBadge(node.data.rules.length, "Rule")}
      </button>
    `);
  }
  if (node.kind === "leaf") {
    const row = elementFromHtml(renderCandidateTreeRow(node.data.candidate));
    if (node.data.override) row.classList.add("candidate-override-row");
    return row;
  }
  const { candidates, decoration, extraClass = "", label, override, protectedRuleCount = 0, sourceType } = node.data;
  const source = node.kind === "source";
  const labelHtml = source && !override
    ? renderSourceSummaryLabel(sourceType, label, decoration)
    : `<span class="candidate-parent-label"><strong>${escapeHtml(label)}</strong>${renderCandidateAggregateDecoration(decoration)}</span>`;
  const countLabel = override ? "Override" : "Candidate";
  return elementFromHtml(`
    <button class="hierarchical-parent-row ${source ? "candidate-source-row" : "candidate-folder-row"} ${extraClass}${candidateAggregateClass(decoration)} clickable" type="button" data-hierarchical-toggle aria-expanded="${node.expanded}"${renderCandidateAggregateAttributes(decoration)}>
      ${icon(source && override ? "shield" : "folder")}${labelHtml}${renderCandidateCountBadge(candidates.length + protectedRuleCount, countLabel, decoration)}
    </button>
  `);
}

function ensureCandidateHierarchicalView() {
  if (candidateHierarchicalView) return candidateHierarchicalView;
  candidateHierarchicalView = new WorkbenchHierarchicalView.HierarchicalView({
    viewport: elements["candidate-list"],
    stickyContainer: elements["candidate-sticky-stack"],
    adapter: {
      accumulateRoots: true,
      keepLastRowVisible: true,
      buildNodes: buildCandidateTreeNodes,
      getDefaultRowHeight: () => getWorkbenchPixelMetric("--tree-row-height"),
      getInput: () => state.candidates,
      shouldCascadeTransition: ({ incomingRoot, stickyNodes }) => incomingRoot.data.override === true || stickyNodes.some((node) => node.depth === 0 && node.data.override === true),
      renderRow: renderCandidateHierarchyRow,
      onExpandedChange: (node, expanded) => candidateExpansionState.set(node.id, expanded),
      handleAction: (_node, event, target) => {
        if (target !== "sticky") return;
        const sortButton = event.target.closest("[data-candidate-sort]");
        if (sortButton) updateCandidateSort(sortButton);
      }
    }
  });
  return candidateHierarchicalView;
}

function renderCandidateList() {
  renderBulkActions();
  if (!state.candidates.length) {
    candidateHierarchicalView?.destroy();
    candidateHierarchicalView = null;
    elements["candidate-list"].innerHTML = `<div class="empty-state compact"><h3>No Candidates Available</h3><p>No AI-evaluated candidates are present in this bundle.</p></div>`;
    return;
  }
  ensureCandidateHierarchicalView().setInput(state.candidates);
  navigateCandidateSearch({ scroll: false });
}

function groupOverrideCandidatesByCategory(candidates) {
  return candidates.reduce((groups, candidate) => {
    const category = candidate.sourceType === "interactive"
      ? formatHostedCategory(candidate.assessment.hostedCategory)
      : candidate.category;
    (groups[category] ||= []).push(candidate);
    return groups;
  }, {});
}

function groupCandidatesBySource(candidates) {
  return candidates.reduce((groups, candidate) => {
    (groups[candidate.sourceId] ||= []).push(candidate);
    return groups;
  }, {});
}

function renderSourceSummaryLabel(sourceType, label, decoration) {
  const revision = state.assessedCandidates.find((candidate) => candidate.sourceType === "upstream")?.revision;
  const shortCommit = revision?.resolvedCommit?.slice(0, 8);
  const provenanceLabel = revision?.repository && revision?.configuredRef && shortCommit
    ? `${revision.repository} · ${revision.configuredRef}@${shortCommit}`
    : "";
  const provenance = sourceType === "upstream" && provenanceLabel
    ? `<span class="ui-badge status-capsule source-provenance-pill type-compact" data-workbench-tooltip="${escapeHtml(provenanceLabel)}">${escapeHtml(provenanceLabel)}</span>`
    : "";
  const selection = decoration === undefined ? "" : renderCandidateAggregateDecoration(decoration);
  return `<span class="source-summary-label"><strong>${escapeHtml(label)}</strong>${provenance}${selection}</span>`;
}

function renderCandidateListHeader(sectionKey, treeDepth = 2) {
  const sort = getCandidateSort(sectionKey);
  const columns = [
    ["candidate", "Candidate", "Candidate", "Proposed or mapped Hosted rule ID and title."],
    ["state", "State", "Source State", "Lifecycle state of the source rule."],
    ["catalog", "Status", "Catalog Status", "Current mapping in the Hosted catalog."],
    ["impact", "Impact", "Impact", "Priority score balancing rule value and review risk."],
    ["cost", "Tokens", "Token Usage", "Unsigned values show current guarded-token usage. Signed values show the estimated change if the recommended action is promoted."],
    ["recommendation", "Recommended", "Recommendation", "AI-recommended action for maintainer review."]
  ];
  const button = (column) => renderSortButton(column, sort, { "candidate-sort": column[0], "candidate-section": sectionKey });
  return `<div class="candidate-list-header" data-tree-depth="${treeDepth}"><span aria-hidden="true"></span>${button(columns[0])}<span class="candidate-list-header-summary">${columns.slice(1).map(button).join("")}</span></div>`;
}

function getCandidateSort(sectionKey) {
  return state.candidateSorts[sectionKey] || { field: "candidate", direction: "ascending" };
}

function updateCandidateSort(button) {
  const sectionKey = button.dataset.candidateSection;
  const field = button.dataset.candidateSort;
  const current = getCandidateSort(sectionKey);
  state.candidateSorts[sectionKey] = {
    field,
    direction: current.field === field && current.direction === "ascending" ? "descending" : "ascending"
  };
  if (candidateHierarchicalView) {
    candidateHierarchicalView.refresh();
    refreshPresentation();
    return;
  }
}

function sortCandidates(candidates, sort) {
  const collator = new Intl.Collator(undefined, { numeric: true, sensitivity: "base" });
  const value = (candidate) => {
    const assessment = getAssessment(candidate, getDecision(candidate));
    if (sort.field === "candidate") return `${getEffectiveHostedRuleId(candidate)} ${candidate.title}`;
    if (sort.field === "state") return candidate.state;
    if (sort.field === "catalog") return getCatalogStatus(candidate).label;
    if (sort.field === "impact") return assessment ? calculateImpact(assessment.factors) : Number.NEGATIVE_INFINITY;
    if (sort.field === "cost") return assessment ? getCandidateTokenValue(candidate, assessment) : Number.NEGATIVE_INFINITY;
    return assessment ? formatRecommendation(assessment.recommendation) : "Rebuild assessment missing";
  };
  return [...candidates].sort((left, right) => {
    const leftValue = value(left);
    const rightValue = value(right);
    const compared = typeof leftValue === "number" ? leftValue - rightValue : collator.compare(leftValue, rightValue);
    const directed = sort.direction === "ascending" ? compared : -compared;
    return directed || collator.compare(getEffectiveHostedRuleId(left), getEffectiveHostedRuleId(right));
  });
}

function sortProtectedRules(rules, sort) {
  const collator = new Intl.Collator(undefined, { numeric: true, sensitivity: "base" });
  const value = (rule) => {
    if (sort.field === "candidate") return `${rule.id} ${rule.title}`;
    if (sort.field === "state") return "Required";
    if (sort.field === "catalog") return "Protected";
    if (sort.field === "impact") return rule.impact;
    if (sort.field === "cost") return rule.guardedTokens;
    return "Immutable";
  };
  return [...rules].sort((left, right) => {
    const leftValue = value(left);
    const rightValue = value(right);
    const compared = typeof leftValue === "number" ? leftValue - rightValue : collator.compare(leftValue, rightValue);
    return (sort.direction === "ascending" ? compared : -compared) || collator.compare(left.id, right.id);
  });
}

function getFilteredAssessmentCandidates() {
  const query = state.queries["assessment-results"].trim().toLowerCase();
  return state.assessedCandidates.filter((candidate) => !candidate.assessment.hostedApplicable).filter((candidate) => {
    if (!query) return true;
    return [getEffectiveHostedRuleId(candidate), candidate.id, candidate.title, candidate.sourcePath, candidate.text, candidate.category, candidate.sourceLabel, candidate.assessment.applicabilityRationale]
      .some((value) => String(value || "").toLowerCase().includes(query));
  });
}

function getAssessmentExpansion(nodeId, expandedByDefault = false) {
  return assessmentExpansionState.has(nodeId) ? assessmentExpansionState.get(nodeId) : expandedByDefault;
}

function buildAssessmentTreeNodes() {
  const filtered = getFilteredAssessmentCandidates();
  const sources = [
    ["interactive", "Interactive Toolkit"],
    ["upstream", "Contributor Guidance"],
    ["maintainer", "Maintainer Proposals"]
  ];
  return sources.map(([sourceType, label]) => {
    const candidates = filtered.filter((candidate) => candidate.sourceType === sourceType);
    if (!candidates.length) return null;
    const sourceId = `assessment:source:${sourceType}`;
    return {
      id: sourceId,
      kind: "source",
      expanded: getAssessmentExpansion(sourceId, Boolean(state.queries["assessment-results"])),
      data: { label, sourceType, candidates },
      children: Object.entries(candidates.reduce((groups, candidate) => {
        const category = candidate.assessment.hostedCategory;
        (groups[category] ||= []).push(candidate);
        return groups;
      }, {}))
        .sort(([left], [right]) => formatHostedCategory(left).localeCompare(formatHostedCategory(right)))
        .map(([category, members]) => {
          const categoryId = `assessment:category:${sourceType}:${category}`;
          const sectionKey = `assessment:${sourceType}:${category}`;
          return {
            id: categoryId,
            kind: "category",
            expanded: getAssessmentExpansion(categoryId, Boolean(state.queries["assessment-results"])),
            data: { label: formatHostedCategory(category), candidates: members },
            children: [{
              id: `assessment:header:${sourceType}:${category}`,
              kind: "header",
              expanded: true,
              data: { sectionKey },
              children: sortAssessmentCandidates(members, getAssessmentSort(sectionKey)).map((candidate) => ({
                id: `assessment:leaf:${candidate.key}`,
                kind: "leaf",
                stickyEligible: false,
                expanded: false,
                data: { candidate }
              }))
            }]
          };
        })
    };
  }).filter(Boolean);
}

function renderAssessmentHierarchyRow(node) {
  if (node.kind === "header") return elementFromHtml(renderAssessmentResultsHeader(node.data.sectionKey));
  if (node.kind === "source") {
    const { candidates, label, sourceType } = node.data;
    return elementFromHtml(`
      <button class="hierarchical-parent-row candidate-source-row clickable" type="button" data-hierarchical-toggle aria-expanded="${node.expanded}">
        ${icon("folder")}${renderSourceSummaryLabel(sourceType, label)}<span class="ui-badge count-badge type-compact">${formatNumber(candidates.length)} Excluded</span>
      </button>
    `);
  }
  if (node.kind === "category") {
    const { candidates, label } = node.data;
    return elementFromHtml(`
      <button class="hierarchical-parent-row candidate-folder-row clickable" type="button" data-hierarchical-toggle aria-expanded="${node.expanded}">
        ${icon("folder")}<span class="candidate-parent-label"><strong>${escapeHtml(label)}</strong></span><span class="ui-badge count-badge type-compact">${formatCountLabel(candidates.length, "Excluded")}</span>
      </button>
    `);
  }
  return elementFromHtml(`<div>${renderAssessmentResultRow(node.data.candidate)}</div>`).querySelector("[data-assessment-key]");
}

function ensureAssessmentHierarchicalView() {
  if (assessmentHierarchicalView) return assessmentHierarchicalView;
  assessmentHierarchicalView = new WorkbenchHierarchicalView.HierarchicalView({
    viewport: elements["assessment-results-list"],
    stickyContainer: elements["assessment-sticky-stack"],
    adapter: {
      accumulateRoots: true,
      buildNodes: buildAssessmentTreeNodes,
      getDefaultRowHeight: () => getWorkbenchPixelMetric("--tree-row-height"),
      getInput: () => state.assessedCandidates,
      renderRow: renderAssessmentHierarchyRow,
      onExpandedChange: (node, expanded) => assessmentExpansionState.set(node.id, expanded),
      handleAction: (_node, event, target) => {
        if (target !== "sticky") return;
        const sortButton = event.target.closest("[data-assessment-sort]");
        if (sortButton) updateAssessmentSort(sortButton);
      }
    }
  });
  return assessmentHierarchicalView;
}

function renderAssessmentResults() {
  if (!state.assessedCandidates.length) return;
  if (!getFilteredAssessmentCandidates().length) {
    assessmentHierarchicalView?.destroy();
    assessmentHierarchicalView = null;
    elements["assessment-sticky-stack"].hidden = true;
    elements["assessment-results-list"].innerHTML = `<div class="empty-state compact"><h3>No Assessment Results</h3><p>No candidates match this outcome and search.</p></div>`;
  }
  else {
    ensureAssessmentHierarchicalView().setInput(state.assessedCandidates);
    syncAssessmentResultRows();
  }
  renderAssessmentResultDetail();
}

function renderAssessmentResultsHeader(sectionKey) {
  const sort = getAssessmentSort(sectionKey);
  const columns = [
    ["candidate", "Candidate", "Candidate", "Source rule ID and title."],
    ["state", "State", "Source State", "Lifecycle state relative to the source baseline."],
    ["recommendation", "Recommendation", "Recommendation", "AI-recommended action for maintainer review."],
    ["override", "Override", "Override", "Maintainer override state."]
  ];
  const button = (column) => renderSortButton(column, sort, { "assessment-sort": column[0], "assessment-section": sectionKey });
  return `<div class="assessment-results-header">${button(columns[0])}<span>${columns.slice(1).map(button).join("")}</span></div>`;
}

function getAssessmentSort(sectionKey) {
  return state.assessmentSorts[sectionKey] || { field: "candidate", direction: "ascending" };
}

function updateAssessmentSort(button) {
  const sectionKey = button.dataset.assessmentSection;
  const field = button.dataset.assessmentSort;
  const current = getAssessmentSort(sectionKey);
  state.assessmentSorts[sectionKey] = {
    field,
    direction: current.field === field && current.direction === "ascending" ? "descending" : "ascending"
  };
  if (assessmentHierarchicalView) {
    assessmentHierarchicalView.refresh();
    refreshPresentation();
    return;
  }
}

function sortAssessmentCandidates(candidates, sort) {
  const collator = new Intl.Collator(undefined, { numeric: true, sensitivity: "base" });
  const value = (candidate) => {
    if (sort.field === "candidate") return `${getEffectiveHostedRuleId(candidate)} ${candidate.title}`;
    if (sort.field === "state") return candidate.state;
    if (sort.field === "category") return formatHostedCategory(candidate.assessment.hostedCategory);
    if (sort.field === "recommendation") return formatRecommendation(getAssessment(candidate)?.recommendation || "Rebuild assessment missing");
    return getApplicabilityOverride(candidate) ? "contested" : "none";
  };
  return [...candidates].sort((left, right) => {
    const compared = collator.compare(value(left), value(right));
    const directed = sort.direction === "ascending" ? compared : -compared;
    return directed || collator.compare(getEffectiveHostedRuleId(left), getEffectiveHostedRuleId(right));
  });
}

function renderAssessmentResultRow(candidate) {
  const assessment = getAssessment(candidate);
  const override = getApplicabilityOverride(candidate);
  const overrideStatus = override
    ? `<button class="ui-badge status-capsule status-badge warning assessment-override-pill clickable" type="button" data-assessment-override-detail="${escapeHtml(candidate.key)}" aria-label="Open Maintainer Override for ${escapeHtml(getEffectiveHostedRuleId(candidate))}">Contested</button>`
    : `<span class="ui-badge status-capsule status-badge neutral assessment-override-pill">None</span>`;
  return `
    <div class="assessment-result-row clickable ${candidate.key === state.assessmentActiveKey ? "active" : ""}" role="button" tabindex="0" data-assessment-key="${escapeHtml(candidate.key)}" ${candidate.key === state.assessmentActiveKey ? 'aria-current="true"' : ""}>
      <span class="candidate-tree-copy"><strong>${escapeHtml(getEffectiveHostedRuleId(candidate))}</strong><small>${escapeHtml(candidate.title)}</small></span>
      <span class="assessment-result-summary"><span class="ui-badge status-capsule candidate-lifecycle ${escapeHtml(candidate.state)}">${escapeHtml(formatCandidateLifecycle(candidate.state))}</span>${renderAssessmentRecommendation(assessment, false)}<span class="assessment-override-cell">${overrideStatus}</span></span>
    </div>
  `;
}

function renderAssessmentResultDetail() {
  const candidate = state.assessedCandidates.find((item) => item.key === state.assessmentActiveKey);
  if (!candidate) {
    elements["assessment-results-detail"].innerHTML = `<div class="empty-state">${icon("checklist")}<h2>Select an Assessment Result</h2><p>The source rule, applicability decision, AI rationale, and Hosted coverage will appear here.</p></div>`;
    return;
  }
  const assessment = getAssessment(candidate);
  const decision = getDecision(candidate);
  const evidence = assessment || getBaselineAssessment(candidate, getDecision(candidate));
  const eligible = candidate.assessment.hostedApplicable;
  const override = getApplicabilityOverride(candidate);
  const included = Boolean(override && state.candidates.some((item) => item.key === candidate.key));
  const catalogStatus = getCatalogStatus(candidate);
  elements["assessment-results-detail"].innerHTML = `
    <div class="assessment-title">
      <div>
        <div class="source-line detail-identity"><span>${escapeHtml(candidate.sourceLabel)}</span><span>/</span><span>${escapeHtml(getEffectiveHostedRuleId(candidate))}</span></div>
        <h2 class="detail-rule-title">${escapeHtml(candidate.title)}</h2>
        <div class="source-line"><span>${escapeHtml(candidate.sourcePath)}</span><span>${escapeHtml(candidate.hash.slice(0, 12))}</span></div>
      </div>
      ${renderDetailHeaderActions(`
        <span class="ui-badge status-capsule status-badge ${eligible ? "success" : "excluded"}">${eligible ? "Eligible" : "Excluded"}</span>
        ${override ? `<button class="ui-badge status-capsule status-badge warning clickable" type="button" data-override-jump="${escapeHtml(candidate.key)}" aria-label="Go to Maintainer Override" data-workbench-tooltip="Go to maintainer override">Contested</button>` : ""}
        ${included ? `<button class="ui-badge status-capsule status-badge success clickable" type="button" data-override-jump="${escapeHtml(candidate.key)}" aria-label="Go to Maintainer Override" data-workbench-tooltip="Go to maintainer override">Maintainer Included</button>` : ""}
        ${renderCatalogStatusBadge(catalogStatus)}
      `)}
    </div>
    <div class="assessment-content scroll-surface">
      ${renderEvidenceDisclosure(candidate, "sources", "Source Rules", candidate.members.length, `${renderContributingRules(candidate)}${candidate.sourceRationale ? `<div class="assessment-rationale proposal-rationale"><strong>Proposal rationale</strong><p>${escapeHtml(candidate.sourceRationale)}</p></div>` : ""}`, "results")}
      ${renderRelatedHostedCoverage(candidate, assessment, "results")}
      <div class="section-block" data-assessment-evidence>${renderAssessmentEvidence(candidate, assessment, decision)}</div>
      <div class="section-block"><span class="section-label">Applicability Decision:</span><p class="coverage-summary">${assessment ? "" : "<strong>Original assessment:</strong> "}${escapeHtml(evidence.applicabilityRationale)}</p></div>
      <div class="section-block hosted-rule-comparison">${renderCurrentHostedRules(catalogStatus)}
        <div class="proposed-rule-heading"><span class="section-label">Proposed Hosted Rule:</span>${renderProposedRuleRecommendation(candidate, assessment)}</div>
        ${renderAssessmentExplanation(candidate, assessment)}
        <pre class="evidence-box scroll-surface">${escapeHtml(decision.proposedText)}</pre>
      </div>
      ${renderApplicabilityOverride(candidate)}
    </div>
  `;
}

function renderApplicabilityOverride(candidate) {
  const override = getApplicabilityOverride(candidate);
  const identity = globalThis.__HOSTED_RULE_WORKBENCH__?.maintainerIdentity;
  const readOnlyBanner = renderInformationPanel(`<p>${override
    ? "The AI assessment is read-only. This provisional maintainer correction does not erase the original result."
    : "The AI assessment is read-only. A maintainer override records a separate correction without erasing the original result."}</p>`, {
    iconMarkup: icon("lock"),
    className: "section-guidance"
  });
  if (override) {
    const editing = state.assessmentOverrideEditingKey === candidate.key;
    const fieldId = `saved-override-rationale-${candidate.key}`;
    const actions = editing
      ? `<button class="titlebar-icon clickable rationale-save" type="button" data-override-save aria-label="Apply Override Rationale" data-workbench-tooltip="Apply override rationale" disabled>${icon("git-stash-apply")}</button><button class="titlebar-icon clickable" type="button" data-override-edit-cancel aria-label="Cancel Override Rationale Changes" data-workbench-tooltip="Cancel override rationale changes">${icon("close")}</button>`
      : `<button class="titlebar-icon clickable" type="button" data-override-edit aria-label="Edit Override Rationale" data-workbench-tooltip="Edit override rationale">${icon("edit")}</button><button class="titlebar-icon clickable" type="button" data-override-remove aria-label="Remove Override" data-workbench-tooltip="Remove override">${icon("discard")}</button>`;
    return `
      <div class="section-block maintainer-override" data-override-key="${escapeHtml(candidate.key)}">
        <span class="section-label">Maintainer Override:</span>
        ${readOnlyBanner}
        <div class="override-record subcontext-container">
          <div class="override-rationale">
            <span class="rationale-heading"><label class="control-subtitle" for="${escapeHtml(fieldId)}">Override Rationale:</label><span class="override-record-actions">${actions}</span></span>
            <textarea id="${escapeHtml(fieldId)}" class="scroll-surface" maxlength="${OVERRIDE_RATIONALE_MAX_LENGTH}" data-saved-override-rationale ${editing ? "" : "readonly"}>${escapeHtml(override.rationale)}</textarea>
            ${editing ? `<small class="rationale-limit">${override.rationale.length} / ${OVERRIDE_RATIONALE_MAX_LENGTH} characters</small>` : ""}
          </div>
          <small class="override-record-audit">Last saved by @${escapeHtml(override.recordedBy.login)} on ${escapeHtml(formatTimestamp(override.recordedAt))}. The original AI exclusion remains in this audit.</small>
        </div>
      </div>
    `;
  }
  const canOverride = Boolean(getValidatedCodeOwnerIdentity());
  const reason = canOverride ? "" : identity?.reason || "GitHub CLI authentication and Hosted CODEOWNER membership are required.";
  return `
    <div class="section-block maintainer-override" data-override-key="${escapeHtml(candidate.key)}">
      <span class="section-label">Maintainer Override:</span>
      ${readOnlyBanner}
      <div class="override-summary subcontext-container">
        <div><strong>Disagree with this exclusion?</strong><p>Contest the AI applicability decision and record a separate provisional maintainer correction.</p>${reason ? `<small>${escapeHtml(reason)}</small>` : ""}</div>
        <button class="button warning-action clickable" type="button" data-override-open ${canOverride ? "" : "disabled"}>${icon("chat-sparkle-error")}Contest Assessment</button>
      </div>
      <div class="override-form subcontext-container" hidden>
        <span class="control-subtitle">Corrected Outcome:</span>
        <label class="override-outcome clickable"><input type="radio" name="corrected-outcome" value="eligible" checked><span>Eligible for Candidate Sources</span></label>
        <label class="override-rationale"><span class="rationale-heading"><span class="control-subtitle">Override Rationale:</span><span class="override-inline-actions"><button class="titlebar-icon clickable" type="button" data-override-apply aria-label="Apply Override" data-workbench-tooltip="Apply override" disabled>${icon("git-stash-apply")}</button><button class="titlebar-icon clickable" type="button" data-override-cancel aria-label="Cancel Override" data-workbench-tooltip="Cancel override">${icon("close")}</button></span></span><textarea class="scroll-surface" maxlength="${OVERRIDE_RATIONALE_MAX_LENGTH}" aria-describedby="override-rationale-limit" placeholder="Briefly explain why the AI exclusion is incorrect."></textarea><small id="override-rationale-limit" class="rationale-limit">0 / ${OVERRIDE_RATIONALE_MAX_LENGTH} characters</small></label>
        <p class="override-audit-note">The original AI result remains in the assessment audit. This provisional override records the corrected outcome, rationale, authenticated maintainer, and timestamp.</p>
      </div>
    </div>
  `;
}

function handleApplicabilityOverrideInput(event) {
  if (!event.target.matches(".override-rationale textarea")) return;
  const form = event.target.closest(".override-form");
  if (form) {
    form.querySelector(".rationale-limit").textContent = `${event.target.value.length} / ${OVERRIDE_RATIONALE_MAX_LENGTH} characters`;
    form.querySelector("[data-override-apply]").disabled = !event.target.value.trim();
    return;
  }
  const record = event.target.closest(".override-record");
  const candidate = state.assessedCandidates.find((item) => item.key === record?.closest(".maintainer-override")?.dataset.overrideKey);
  const override = candidate ? getApplicabilityOverride(candidate) : null;
  if (!record || !override) return;
  record.querySelector(".rationale-limit").textContent = `${event.target.value.length} / ${OVERRIDE_RATIONALE_MAX_LENGTH} characters`;
  record.querySelector("[data-override-save]").disabled = !event.target.value.trim() || event.target.value.trim() === override.rationale;
}

async function handleApplicabilityOverrideClick(event) {
  const overrideJump = event.target.closest("[data-override-jump]");
  if (overrideJump) {
    elements["assessment-results-detail"].querySelector(`.maintainer-override[data-override-key="${CSS.escape(overrideJump.dataset.overrideJump)}"]`)?.scrollIntoView({ block: "start", behavior: "smooth" });
    return;
  }
  const section = event.target.closest(".maintainer-override");
  if (!section) return;
  if (event.target.closest("[data-override-open]")) {
    section.querySelector(".override-summary").hidden = true;
    section.querySelector(".override-form").hidden = false;
    section.querySelector("textarea").focus();
    return;
  }
  if (event.target.closest("[data-override-cancel]")) {
    section.querySelector(".override-form").hidden = true;
    section.querySelector(".override-summary").hidden = false;
    return;
  }
  const candidate = state.assessedCandidates.find((item) => item.key === section.dataset.overrideKey);
  if (!candidate) return;
  if (event.target.closest("[data-override-edit]")) {
    state.assessmentOverrideEditingKey = candidate.key;
    renderAssessmentResultDetail();
    requestAnimationFrame(() => elements["assessment-results-detail"].querySelector("[data-saved-override-rationale]")?.focus());
    return;
  }
  if (event.target.closest("[data-override-edit-cancel]")) {
    state.assessmentOverrideEditingKey = null;
    renderAssessmentResultDetail();
    return;
  }
  if (event.target.closest("[data-override-remove]")) {
    state.assessmentOverrideEditingKey = null;
    await updateOverrideLifecycle(candidate, null, null);
    showToast("Provisional override removed");
    return;
  }
  if (event.target.closest("[data-override-save]")) {
    const identity = getValidatedCodeOwnerIdentity();
    const rationale = section.querySelector("[data-saved-override-rationale]").value.trim();
    const currentOverride = getApplicabilityOverride(candidate);
    if (!identity) {
      showToast(globalThis.__HOSTED_RULE_WORKBENCH__?.maintainerIdentity?.reason || "A validated Hosted CODEOWNER identity is required.", true);
      return;
    }
    if (!rationale || rationale === currentOverride.rationale) return;
    const recordedAt = toUtcTimestamp();
    state.session.applicabilityOverrides[candidate.key] = {
      ...currentOverride,
      rationale: rationale.slice(0, OVERRIDE_RATIONALE_MAX_LENGTH),
      recordedAt,
      recordedBy: { type: "github-cli", login: identity.login }
    };
    state.session.updatedAt = recordedAt;
    state.assessmentOverrideEditingKey = null;
    await persistSession();
    renderAssessmentResultDetail();
    showToast("Override rationale saved");
    return;
  }
  if (!event.target.closest("[data-override-apply]")) return;
  const identity = getValidatedCodeOwnerIdentity();
  const rationale = section.querySelector("textarea").value.trim();
  if (!identity) {
    showToast(globalThis.__HOSTED_RULE_WORKBENCH__?.maintainerIdentity?.reason || "A validated Hosted CODEOWNER identity is required.", true);
    return;
  }
  if (!rationale) return;
  const override = {
    state: "provisional",
    sourceContentSha256: candidate.hash,
    originalHostedApplicable: false,
    effectiveHostedApplicable: true,
    rationale: rationale.slice(0, OVERRIDE_RATIONALE_MAX_LENGTH),
    recordedAt: toUtcTimestamp(),
    recordedBy: { type: "github-cli", login: identity.login }
  };
  await updateOverrideLifecycle(candidate, override, { ...defaultDecision(candidate), ...createPlanMembership("override") });
  setWorkspaceTab("candidate-sources");
  showToast("Candidate moved to Overrides and added to plan");
}

function renderCandidateTreeRow(candidate) {
  const decision = getDecision(candidate);
  const assessment = getAssessment(candidate, decision);
  const displayId = getEffectiveHostedRuleId(candidate);
  const impact = assessment ? calculateImpact(assessment.factors) : "—";
  const catalogStatus = getCatalogStatus(candidate);
  const inPlan = decision.inPlan;
  const planSelectable = canSelectCandidateForPlan(candidate, decision);
  const planAriaLabel = planSelectable
    ? `${inPlan ? "Remove" : "Add"} ${displayId} ${inPlan ? "from" : "to"} promotion plan`
    : `${displayId} has no recommended change`;
  const planTooltip = planSelectable
    ? inPlan ? "Remove candidate from promotion plan" : "Add candidate to promotion plan"
    : "No change is recommended";
  const decoration = getCandidateDecoration(candidate);
  return `
    <div class="candidate-tree-row clickable ${candidate.key === state.activeKey ? "active" : ""} ${inPlan ? "in-plan" : ""} ${decoration ? `candidate-decoration-${decoration.status}` : ""}" role="button" tabindex="0" data-candidate-key="${escapeHtml(candidate.key)}" ${candidate.key === state.activeKey ? 'aria-current="true"' : ""}>
      <input class="${planSelectable ? "" : "candidate-plan-unavailable"}" type="checkbox" data-decision-key="${escapeHtml(candidate.key)}" aria-label="${escapeHtml(planAriaLabel)}" data-workbench-tooltip="${escapeHtml(planTooltip)}" ${inPlan ? "checked" : ""} ${planSelectable ? "" : 'disabled aria-hidden="true" tabindex="-1"'}>
      <span class="candidate-tree-copy"><strong>${escapeHtml(displayId)}</strong><small>${escapeHtml(candidate.title)}</small>${renderCandidateDecoration(decoration, "candidate-decoration-icon")}</span>
      <span class="candidate-tree-summary"><span class="ui-badge status-capsule candidate-lifecycle ${escapeHtml(candidate.state)}">${escapeHtml(formatCandidateLifecycle(candidate.state))}</span><span class="ui-badge status-capsule catalog-status ${catalogStatus.key}">${escapeHtml(catalogStatus.label)}</span><span class="tree-impact">${impact}</span><span class="tree-cost">${assessment ? formatCandidateTokenValue(candidate, assessment) : "—"}</span>${renderAssessmentRecommendation(assessment, false)}</span>
    </div>
  `;
}

function renderProtectedRuleTreeRow(rule) {
  return `
    <div class="candidate-tree-row clickable protected-rule-row ${rule.id === state.activeProtectedRuleId ? "active" : ""}" role="button" tabindex="0" data-protected-rule-id="${escapeHtml(rule.id)}" ${rule.id === state.activeProtectedRuleId ? 'aria-current="true"' : ""}>
      ${icon("lock")}<span class="candidate-tree-copy"><strong>${escapeHtml(rule.id)}</strong><small>${escapeHtml(rule.title)}</small></span>
      <span class="candidate-tree-summary"><span class="ui-badge status-capsule candidate-lifecycle required">Required</span><span class="ui-badge status-capsule catalog-status protected">Protected</span><span class="tree-impact">${rule.impact}</span><span class="tree-cost">${formatNumber(rule.guardedTokens)}</span><span class="ui-badge status-capsule recommendation-badge immutable">Immutable</span></span>
    </div>
  `;
}

function renderProtectedRuleDetails(rule) {
  elements["assessment-panel"].innerHTML = `
    <div class="assessment-title">
      <div>
        <div class="source-line detail-identity"><span>Protected rule</span><span>/</span><span>${escapeHtml(rule.id)}</span></div>
        <h2 class="detail-rule-title">${escapeHtml(rule.title)}</h2>
        <div class="source-line"><span>${escapeHtml(capitalize(rule.surfaceId))}</span><span>${escapeHtml(rule.provenance)}</span></div>
      </div>
      ${renderDetailHeaderActions('<span class="ui-badge status-capsule candidate-state required">Required</span><span class="ui-badge status-capsule catalog-status protected">Protected</span>')}
    </div>
    <div class="assessment-content scroll-surface">
      <div class="section-block"><span class="section-label">Protected Instruction:</span><pre class="evidence-box scroll-surface">${escapeHtml(rule.text)}</pre></div>
      <div class="section-block"><span class="section-label">Protection:</span><div class="protected-rule-notice">${icon("lock")}<div><strong>${escapeHtml(rule.protectionReason)}</strong><p>This rule is always generated and cannot be changed through the promotion workflow.</p></div></div></div>
      <div class="section-block"><span class="section-label">Authored Source:</span><div class="subcontext-container">${escapeHtml(rule.sourcePath)}</div></div>
      <div class="score-strip protected-rule-score-strip"><div class="score-item impact"><span>Impact</span><strong>${rule.impact}</strong></div><div class="score-item cost"><span>Token cost</span><strong>${formatNumber(rule.guardedTokens)}</strong></div><div class="score-item efficiency"><span>Recommended</span><strong>Immutable</strong></div></div>
    </div>
  `;
  scheduleTruncationTooltips();
}

function renderEvidenceDisclosure(candidate, kind, title, count, content, view = "details") {
  const key = `${view}:${candidate.key}:${kind}`;
  const id = `evidence-${encodeURIComponent(key)}`;
  const expanded = expandedEvidencePanels.has(key);
  const action = `${expanded ? "Collapse" : "Expand"} ${title === "Source Rules" ? "source rules" : "related Hosted coverage"}`;
  return `<section class="section-block evidence-disclosure" data-evidence-disclosure="${escapeHtml(key)}" data-evidence-kind="${escapeHtml(kind)}">
    <div class="evidence-disclosure-heading"><span class="section-label evidence-disclosure-label">${escapeHtml(title)}${count === null ? "" : `<span class="ui-badge count-badge type-compact">${formatNumber(count)}</span>`}</span>
      <button class="titlebar-icon clickable evidence-disclosure-toggle" type="button" data-evidence-toggle="${escapeHtml(key)}" data-evidence-title="${escapeHtml(title)}" aria-controls="${escapeHtml(id)}" aria-expanded="${expanded}" aria-label="${action}" data-workbench-tooltip="${action}">${icon(expanded ? "chevron-up" : "chevron-down")}</button>
    </div><div id="${escapeHtml(id)}" class="evidence-disclosure-body" ${expanded ? "" : "hidden"}>${content}</div></section>`;
}

function handleEvidenceDisclosureClick(event) {
  const summary = event.target.closest(".contributing-rule > summary");
  if (summary) {
    const details = summary.parentElement;
    sourceRuleDisclosureStates.set(details.dataset.sourceRuleKey, !details.open);
    return;
  }
  const button = event.target.closest("[data-evidence-toggle]");
  if (!button) return;
  const key = button.dataset.evidenceToggle;
  const expanded = button.getAttribute("aria-expanded") !== "true";
  if (expanded) expandedEvidencePanels.add(key);
  else expandedEvidencePanels.delete(key);
  button.setAttribute("aria-expanded", String(expanded));
  const title = button.dataset.evidenceTitle === "Source Rules" ? "source rules" : "related Hosted coverage";
  const action = `${expanded ? "Collapse" : "Expand"} ${title}`;
  button.setAttribute("aria-label", action);
  setWorkbenchTooltip(button, action);
  button.innerHTML = icon(expanded ? "chevron-up" : "chevron-down");
  document.getElementById(button.getAttribute("aria-controls")).hidden = !expanded;
}

function renderRelatedHostedCoverage(candidate, assessment, view = "details") {
  const evidence = assessment || getBaselineAssessment(candidate, getDecision(candidate));
  const coverage = evidence.relatedHostedCoverage;
  if (!coverage.length) return "";
  const content = `${assessment ? "" : '<p class="coverage-summary"><strong>Original assessment coverage:</strong> Edited wording has not yet been reassessed.</p>'}${coverage.length ? `<div class="related-hosted-coverage">${coverage.map((item) => `<p><strong class="rule-reference">${escapeHtml(item.hostedRuleId)}</strong> ${escapeHtml(item.rationale)}</p>`).join("")}</div>` : ""}`;
  return renderEvidenceDisclosure(candidate, "coverage", "Related Hosted Coverage", coverage.length, content, view);
}

function renderAssessmentRecommendation(assessment, prefix = true) {
  return assessment
    ? `<span class="ui-badge status-capsule recommendation-badge ${escapeHtml(assessment.recommendation)}">${prefix ? "Recommend " : ""}${escapeHtml(formatRecommendation(assessment.recommendation))}</span>`
    : '<span class="ui-badge status-capsule status-badge warning">Rebuild assessment missing</span>';
}

function renderProposedRuleRecommendation(candidate, assessment, proposedText = getDecision(candidate).proposedText) {
  return `<span data-assessment-recommendation>${hasMaintainerEditedRuleText(candidate, proposedText)
    ? '<span class="ui-badge status-capsule status-badge neutral">Maintainer edited</span>'
    : renderAssessmentRecommendation(assessment)}</span>`;
}

function renderAssessmentExplanation(candidate, assessment, proposedText = getDecision(candidate).proposedText, compact = false) {
  const evidence = assessment || getBaselineAssessment(candidate, getDecision(candidate));
  const label = hasMaintainerEditedRuleText(candidate, proposedText) ? "Original assessment rationale" : "Assessment rationale";
  return renderInformationPanel(`<p><strong>${label}:</strong> ${escapeHtml(evidence.rationale)}</p>`, {
    className: "assessment-explanation",
    dataAttributes: { "assessment-explanation": "" }
  });
}

function syncProposedRuleAssessment(candidate, assessment, proposedText) {
  const panel = elements["assessment-panel"];
  const recommendation = panel.querySelector("[data-assessment-recommendation]");
  if (recommendation) recommendation.outerHTML = renderProposedRuleRecommendation(candidate, assessment, proposedText);
  const explanationSlot = panel.querySelector("[data-proposed-rule-explanation]");
  if (explanationSlot) {
    explanationSlot.innerHTML = renderAssessmentExplanation(candidate, assessment, proposedText);
    return;
  }
  const explanation = panel.querySelector("[data-assessment-explanation]");
  if (explanation) explanation.outerHTML = renderAssessmentExplanation(candidate, assessment, proposedText, Boolean(explanation.closest("[data-maintainer-resolution]")));
}

function renderContributingRules(candidate) {
  return `
    ${renderInformationPanel("<p>These are the source requirements used to form the original Hosted proposal. Expand a rule to inspect its original wording and contribution. These references are evidence, not additional Hosted rules selected for the Promotion Plan.</p>", { className: "section-guidance" })}
    <div class="contributing-rules">
      ${candidate.members.map((member, index) => {
        const mappedRuleId = member.catalogMapping.hostedRuleId;
        const key = `${candidate.key}:${index}`;
        const open = sourceRuleDisclosureStates.get(key) ?? candidate.members.length === 1;
        return `
          <details class="contributing-rule" data-source-rule-key="${escapeHtml(key)}" ${open ? "open" : ""}>
            <summary>
              <span class="contributing-rule-identity"><strong class="rule-reference">${escapeHtml(member.source.id)}</strong><small>${escapeHtml(member.assessment.title)}</small></span>
              <span class="contributing-rule-badges"><span class="ui-badge status-capsule status-badge neutral">${escapeHtml(member.sourceLabel)}</span>${mappedRuleId && mappedRuleId !== member.source.id ? `<span class="ui-badge status-capsule catalog-status mapped">${escapeHtml(mappedRuleId)}</span>` : ""}${icon("chevron-down")}</span>
            </summary>
            <div class="contributing-rule-content">
              <div class="source-line"><span>${escapeHtml(member.source.location)}</span><span>${escapeHtml(member.source.contentSha256.slice(0, 12))}</span></div>
              <pre class="evidence-box scroll-surface">${escapeHtml(member.source.text)}</pre>
              <div class="contributing-rule-meaning"><strong>Source meaning</strong><p>${escapeHtml(member.assessment.sourceMeaning)}</p></div>
              <div class="contributing-rule-meaning"><strong>Meaning preserved in parent</strong><p>${escapeHtml(member.meaningCoverageRationale)}</p></div>
            </div>
          </details>
        `;
      }).join("")}
    </div>
  `;
}

function validateRuleAssistanceWaitingPhrases(phrases) {
  if (!Array.isArray(phrases) || !phrases.length
    || phrases.some((phrase) => typeof phrase !== "string" || !phrase.trim() || phrase !== phrase.trim() || /[\r\n]/.test(phrase))
    || new Set(phrases).size !== phrases.length) {
    throw new Error("Assistance waiting phrases must be a non-empty array of unique, trimmed, single-line strings.");
  }
  return phrases;
}

function syncRuleAssistanceScrollControl() {
  const root = elements["assist-sidebar-content"].querySelector("[data-rule-assistance]");
  const transcript = root?.querySelector(".assist-chat-response");
  const button = root?.querySelector("[data-assist-scroll-latest]");
  if (transcript && button) button.hidden = transcript.scrollHeight - transcript.clientHeight - transcript.scrollTop <= 4;
}

function setRuleAssistanceCandidate(candidate, viewKind = state.workspaceTab) {
  const contextKey = candidate ? JSON.stringify([viewKind, candidate.key]) : null;
  if (ruleAssistance?.contextKey === contextKey) {
    if (!elements["assist-sidebar-content"].hasChildNodes()) renderRuleAssistanceSidebar();
    else syncRuleAssistanceVisibility();
    return;
  }
  const transcript = elements["assist-sidebar-content"].querySelector(".assist-chat-response");
  if (ruleAssistance && transcript) ruleAssistance.scrollTop = transcript.scrollTop;
  if (candidate && !ruleAssistanceChats.has(contextKey)) {
    ruleAssistanceChats.set(contextKey, { contextKey, viewKind, candidateKey: candidate.key, input: "", turns: [], active: null, followOutput: true, scrollTop: 0 });
  }
  ruleAssistance = contextKey ? ruleAssistanceChats.get(contextKey) : null;
  renderRuleAssistanceSidebar();
}

function isCurrentRuleAssistanceRequest(chat, active) {
  return ruleAssistanceChats.get(chat.contextKey) === chat && chat.active === active;
}

function getRuleAssistanceCandidate() {
  return state.assessedCandidates.find(candidate => candidate.key === ruleAssistance?.candidateKey) || null;
}

function renderRuleAssistanceSidebar() {
  const candidate = getRuleAssistanceCandidate();
  elements["assist-sidebar-content"].innerHTML = candidate ? renderRuleAssistance(candidate)
    : '<div class="empty-state compact"><h2>AI Assistance</h2><p>No candidate selected.</p></div>';
  syncRuleAssistanceVisibility();
  requestAnimationFrame(syncRuleAssistanceScrollControl);
}

function setRuleAssistanceExpanded(expanded) {
  ruleAssistanceExpanded = expanded;
  syncRuleAssistanceVisibility();
}

function syncRuleAssistanceVisibility() {
  const candidate = getRuleAssistanceCandidate();
  const detail = state.workspaceTab === "candidate-sources" ? elements["assessment-panel"]
    : state.workspaceTab === "assessment-results" ? elements["assessment-results-detail"] : null;
  const candidateKey = state.workspaceTab === "candidate-sources" ? state.activeKey : state.assessmentActiveKey;
  const available = Boolean(candidate && candidate.key === candidateKey && ruleAssistance.viewKind === state.workspaceTab
    && detail?.dataset.sidebarEnabled === "true" && !detail.hidden
    && detail.closest("[data-view-panel]")?.classList.contains("active")
    && !detail.closest(".workspace-tab-panel")?.hidden);
  const expanded = available && ruleAssistanceExpanded;
  const transcript = elements["assist-sidebar-content"].querySelector(".assist-chat-response");
  if (!expanded && !elements["rule-assistance-panel"].hidden && ruleAssistance && transcript) ruleAssistance.scrollTop = transcript.scrollTop;
  if (!expanded) finishAssistanceSidebarResize();
  elements["rule-assistance-panel"].hidden = !expanded;
  document.querySelector(".app-shell").classList.toggle("assist-sidebar-open", expanded);
  const toggle = elements["assist-panel-toggle"];
  const label = `${ruleAssistanceExpanded ? "Hide" : "Show"} AI assistance`;
  toggle.setAttribute("aria-expanded", String(expanded));
  toggle.setAttribute("aria-pressed", String(ruleAssistanceExpanded));
  toggle.setAttribute("aria-label", label);
  setWorkbenchTooltip(toggle, label);
  toggle.innerHTML = icon(ruleAssistanceExpanded ? "layout-sidebar-right" : "layout-sidebar-right-off");
  if (expanded) requestAnimationFrame(() => {
    const response = elements["assist-sidebar-content"].querySelector(".assist-chat-response");
    if (response && ruleAssistance) response.scrollTop = ruleAssistance.followOutput ? response.scrollHeight : ruleAssistance.scrollTop;
    syncRuleAssistanceScrollControl();
  });
}

function setAssistanceSidebarWidth(value) {
  const maximum = Math.max(320, Math.min(680, document.documentElement.clientWidth - 400));
  ruleAssistanceSidebarWidth = Math.round(Math.max(320, Math.min(maximum, value)));
  document.documentElement.style.setProperty("--assist-sidebar-width", `${ruleAssistanceSidebarWidth}px`);
  const handle = elements["assist-sidebar-resizer"];
  handle.setAttribute("aria-valuemax", String(maximum));
  handle.setAttribute("aria-valuenow", String(ruleAssistanceSidebarWidth));
  handle.setAttribute("aria-valuetext", `Panel width ${ruleAssistanceSidebarWidth} pixels`);
  requestAnimationFrame(syncRuleAssistanceScrollControl);
}

function handleAssistanceSidebarResizeStart(event) {
  if (event.button !== 0 || ruleAssistanceSidebarResize) return;
  event.preventDefault();
  const handle = elements["assist-sidebar-resizer"];
  ruleAssistanceSidebarResize = { pointerId: event.pointerId, start: event.clientX, width: ruleAssistanceSidebarWidth };
  handle.setPointerCapture(event.pointerId);
}

function handleAssistanceSidebarResizeMove(event) {
  const resize = ruleAssistanceSidebarResize;
  if (!resize || resize.pointerId !== event.pointerId) return;
  setAssistanceSidebarWidth(resize.width + resize.start - event.clientX);
}

function finishAssistanceSidebarResize() {
  const resize = ruleAssistanceSidebarResize;
  if (!resize) return;
  ruleAssistanceSidebarResize = null;
  const handle = elements["assist-sidebar-resizer"];
  if (handle.hasPointerCapture(resize.pointerId)) handle.releasePointerCapture(resize.pointerId);
}

function handleAssistanceSidebarResizeKeyboard(event) {
  if (!["ArrowLeft", "ArrowRight", "Home", "End"].includes(event.key)) return;
  event.preventDefault();
  const maximum = Number(elements["assist-sidebar-resizer"].getAttribute("aria-valuemax"));
  setAssistanceSidebarWidth(event.key === "Home" ? 320 : event.key === "End" ? maximum
    : ruleAssistanceSidebarWidth + (event.key === "ArrowLeft" ? 16 : -16));
}

function cancelRuleAssistance() {
  const chat = ruleAssistance;
  const active = chat?.active;
  if (!active) return;
  active.controller.abort();
  active.turn.status = "Operation canceled.";
  active.turn.failed = false;
  if (active.submittedInput !== null && chat.input === "") chat.input = active.submittedInput;
  chat.active = null;
  syncRuleAssistance();
}

function getAssistanceEditorText() {
  const candidate = getRuleAssistanceCandidate();
  if (!candidate) return undefined;
  const editor = elements["assessment-panel"].querySelector('[data-decision-field="proposedText"]');
  return ruleAssistance.viewKind === "candidate-sources" && editor?.dataset.proposedCandidateKey === candidate.key
    ? editor.value : getDecision(candidate).proposedText;
}

function renderAssistanceSendIcon(running) {
  return running
    ? icon("stop-circle")
    : '<svg viewBox="0 0 20 20" aria-hidden="true"><path d="M10 16V4m-5 5 5-5 5 5" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round"/></svg>';
}

function renderAssistanceContextNote(message, iconName = "tools") {
  return `<p class="assist-chat-scope">${icon(iconName)}<span>${escapeHtml(message)}</span></p>`;
}

function canRetryRuleAssistance(turn) {
  return Boolean(turn?.failed && !turn.answer && ruleAssistance && !ruleAssistance.active
    && ruleAssistance.turns.at(-1) === turn && getAssistanceEditorText() === turn.proposedText);
}

function renderRuleAssistanceError(turn, index) {
  const failure = turn.error || { message: "The AI chat request could not be completed." };
  return `<div class="assist-chat-error" role="alert" aria-atomic="true">${icon("error")}<div class="assist-chat-error-content"><div class="assist-chat-error-message"><p>${escapeHtml(failure.message)}</p>${failure.diagnosticId ? `<p class="assist-chat-error-reference"><span class="assist-chat-error-reference-label">Diagnostic Reference:</span> ${escapeHtml(failure.diagnosticId)}</p>` : ""}</div><div class="assist-chat-error-actions"><button class="button clickable assist-chat-error-retry" type="button" data-assist-error-retry="${index}" ${canRetryRuleAssistance(turn) ? "" : "disabled"}>Try again</button></div></div></div>`;
}

function createRuleAssistanceError(message, code = "rule-assistance-failed", diagnosticId = null) {
  return Object.assign(new Error(message), { assistanceError: { code, message, diagnosticId } });
}

function renderRuleAssistance(candidate) {
  const chat = ruleAssistance;
  const profile = globalThis.__HOSTED_RULE_WORKBENCH__?.ruleAssistance;
  const running = Boolean(chat.active);
  const ready = Boolean(chat.input.trim() && profile?.model);
  const model = profile?.model === "gpt-6.1-sol" ? "GPT-6.1 Sol"
    : profile?.model === "gpt-5.4" ? "GPT-5.4" : profile?.model || "Unavailable";
  const messages = chat.turns.map((turn, index) => `
    <div class="assist-chat-user-message">${escapeHtml(turn.question)}</div>
    ${turn.answer ? `<div class="assist-chat-ai-message">
      <div class="assist-chat-message-author">Completed in ${escapeHtml(turn.duration)}</div>
      ${renderAssistanceContextNote("Assessment, sources, and catalog snapshot; excludes other drafts and Plan changes.")}
      <div class="assist-chat-message-text">${escapeHtml(turn.answer.message)}</div>
      ${turn.answer.suggestedWording ? `<section class="assist-chat-inline-wording">
        <p>I suggest updating the rule to:</p>
        <div class="assist-chat-wording-block">
          <pre class="evidence-box">${escapeHtml(turn.answer.suggestedWording)}</pre>
          <div class="assist-chat-floating-toolbar" role="toolbar" aria-label="Suggested wording actions">
            <button class="titlebar-icon clickable assist-chat-floating-action" type="button" data-assist-copy="${index}" aria-label="Copy suggested rule wording" data-workbench-tooltip="Copy suggested wording">${icon("copy")}</button>
          </div>
        </div>
      </section>` : ""}
    </div>` : ""}
    ${turn.failed ? renderRuleAssistanceError(turn, index) : turn.status ? `<div class="assist-chat-operation-message" role="status">${chat.active?.turn === turn ? renderShimmerHeading(turn.status) : escapeHtml(turn.status)}</div>` : ""}
  `).join("");
  const waiting = running ? renderWaitingPanel({ title: chat.active.turn.status, body: "Preparing rule assistance." })
    .replace('class="waiting-panel"', 'class="waiting-panel assist-chat-animation-layer" aria-hidden="true"') : "";
  return `<section class="rule-assistance" data-rule-assistance>
    <div class="assist-header"><span class="section-label">AI Assistance:</span><div class="assist-sidebar-heading-actions">
      <button class="titlebar-icon clickable" type="button" data-assist-clear aria-label="New chat" data-workbench-tooltip="New chat" aria-haspopup="dialog" ${running || !chat.turns.length ? "disabled" : ""}>${icon("add")}</button>
      <button class="titlebar-icon clickable" type="button" data-assist-sidebar-close aria-label="Close AI assistance" data-workbench-tooltip="Close AI assistance">${icon("close")}</button>
    </div></div>
    <div id="rule-assistance-body" data-assist-body>
    ${renderInformationPanel(`<p>${profile?.model ? "This response is AI-generated. Please review it for accuracy and relevance before use." : "AI assistance is unavailable. Restart the Workbench with the current source."}</p>`, { className: "section-guidance" })}
    <div class="assist-chat-reply-window">
      <div class="assist-chat-conversation-toolbar">
        <span class="assist-chat-identity">${icon("copilot")}<span>Copilot ·</span><em class="assist-chat-context-label">${escapeHtml(getEffectiveHostedRuleId(candidate))}</em></span>
      </div>
      <div class="assist-chat-response scroll-surface" id="rule-assistance-conversation" role="region" aria-label="AI assistance conversation">${messages}</div>
      <button class="scroll-edge-button assist-chat-scroll-latest clickable" type="button" data-assist-scroll-latest aria-label="Scroll to latest reply" data-workbench-tooltip="Scroll to latest reply" aria-controls="rule-assistance-conversation" hidden>${icon("chevron-down")}</button>
    </div>
    <div class="assist-chat-composer ${running ? "assist-chat-running" : ""}">
      ${waiting}
      <span class="assist-chat-context" title="Current Hosted rule context">
        <button class="assist-chat-add-context" type="button" disabled aria-label="Additional context is not available"><svg viewBox="0 0 20 20" aria-hidden="true"><path d="M10 2.5v15M2.5 10h15" fill="none" stroke="currentColor" stroke-width="1.2" stroke-linecap="round"/></svg></button>
        <svg viewBox="0 0 20 20" aria-hidden="true"><circle cx="10" cy="10" r="7.5"/><ellipse cx="10" cy="10" rx="3.25" ry="7.5"/><path d="M2.5 10h15M4 5.5h12M4 14.5h12"/></svg>
        <em class="assist-chat-context-label">${escapeHtml(getEffectiveHostedRuleId(candidate))}</em>
      </span>
      <textarea class="assist-goal scroll-surface" maxlength="8000" aria-label="Message AI about this rule" placeholder="Chat with Copilot to describe what you want to accomplish with this rule..." ${running ? "readonly" : ""}>${escapeHtml(chat.input)}</textarea>
      <div class="assist-chat-toolbar"><span class="assist-chat-profile">${renderLlmModelIcon(profile?.model)}${escapeHtml(model)}${profile?.reasoningEffort ? ` · ${escapeHtml(capitalize(profile.reasoningEffort))}` : ""}</span>
      <button class="assist-chat-send ${!running && ready ? "assist-chat-send-ready clickable" : ""}" type="button" data-assist-send aria-label="${running ? "Cancel operation" : "Send request"}" ${!running && !ready ? "disabled" : ""}>${renderAssistanceSendIcon(running)}</button></div>
    </div>
    </div>
  </section>`;
}

function syncRuleAssistance() {
  const root = elements["assist-sidebar-content"].querySelector("[data-rule-assistance]");
  const candidate = getRuleAssistanceCandidate();
  if (!root || !candidate) { renderRuleAssistanceSidebar(); return; }
  const transcript = root.querySelector(".assist-chat-response");
  const focus = root.contains(document.activeElement);
  const position = [root.querySelector(".assist-goal").selectionStart, root.querySelector(".assist-goal").selectionEnd];
  const scrollTop = transcript.scrollTop;
  root.outerHTML = renderRuleAssistance(candidate);
  const updated = elements["assist-sidebar-content"].querySelector("[data-rule-assistance]");
  const response = updated.querySelector(".assist-chat-response");
  response.scrollTop = ruleAssistance.followOutput ? response.scrollHeight : scrollTop;
  syncRuleAssistanceScrollControl();
  if (focus && ruleAssistanceExpanded) {
    const input = updated.querySelector(".assist-goal");
    input.focus({ preventScroll: true });
    if (input.matches(".assist-goal")) input.setSelectionRange(...position);
  }
  refreshPresentation();
}

async function sendRuleAssistance(retryTurn = null) {
  const chat = ruleAssistance;
  const candidate = getRuleAssistanceCandidate();
  if (!chat || chat.active || candidate?.key !== chat.candidateKey || (retryTurn ? !canRetryRuleAssistance(retryTurn) : !chat.input.trim())) return;
  const proposedText = getAssistanceEditorText();
  const controller = new AbortController();
  const turn = retryTurn || { question: chat.input.trim(), answer: null, proposedText };
  turn.failed = false;
  turn.error = null;
  turn.status = ruleAssistanceWaitingPhrases[Math.floor(Math.random() * ruleAssistanceWaitingPhrases.length)];
  const submittedInput = !retryTurn || chat.input.trim() === turn.question ? chat.input : null;
  const active = { controller, turn, submittedInput };
  chat.active = active;
  if (submittedInput !== null) chat.input = "";
  if (!retryTurn) chat.turns.push(turn);
  const startedAt = performance.now();
  syncRuleAssistance();
  try {
    const config = await loadWorkbenchRuntimeConfig(controller.signal);
    controller.signal.throwIfAborted();
    const profile = config.ruleAssistance;
    if (!profile?.model || !/^[0-9a-f]{64}$/.test(profile.authoritySha256 || "")) throw createRuleAssistanceError("Rule assistance runtime configuration is unavailable.");
    if (profile.catalogSha256 !== state.bundle.catalog.contentSha256 || profile.protectedRulesSha256 !== state.bundle.catalog.protectedRulesContentSha256) {
      throw createRuleAssistanceError("The Hosted catalog changed. Reload the Workbench before asking again.");
    }
    const messages = chat.turns.filter((item) => item.answer).flatMap((item) => [
      { role: "user", content: item.question },
      { role: "assistant", content: item.answer.message + (item.answer.suggestedWording ? `\n\nSuggested wording:\n${item.answer.suggestedWording}` : "") }
    ]);
    messages.push({ role: "user", content: turn.question });
    const request = {
      schemaVersion: 1, requestId: crypto.randomUUID(), authoritySha256: profile.authoritySha256,
      candidateKey: candidate.key, sourceHash: candidate.hash, proposedText, messages
    };
    const response = await fetch("/assist-rule", {
      method: "POST", signal: controller.signal,
      headers: { "Content-Type": "application/json", "X-Workbench-Operation-Token": config.operationToken },
      body: JSON.stringify({ payloadBase64: encodeBase64Utf8(JSON.stringify(request)) })
    });
    if (!response.ok) {
      const failure = response.headers.get("content-type")?.includes("application/json") ? await response.json() : null;
      const details = failure?.error;
      if (details && typeof details === "object" && typeof details.code === "string" && /^[a-z][a-z0-9-]{0,63}$/.test(details.code)
        && typeof details.message === "string" && details.message.trim() && details.message.length <= 2000
        && !/[\u0000-\u0008\u000b\u000c\u000e-\u001f]/.test(details.message)
        && (details.diagnosticId === null || (typeof details.diagnosticId === "string" && /^[a-f0-9]{32}$/.test(details.diagnosticId)))) {
        throw createRuleAssistanceError(details.message, details.code, details.diagnosticId);
      }
      throw createRuleAssistanceError(`Rule assistance failed with HTTP ${response.status}. No reply was accepted.`);
    }
    const answer = await response.json();
    controller.signal.throwIfAborted();
    if (!isCurrentRuleAssistanceRequest(chat, active)) return;
    const hash = Array.from(new Uint8Array(await crypto.subtle.digest("SHA-256", new TextEncoder().encode(proposedText))), (byte) => byte.toString(16).padStart(2, "0")).join("");
    const expectedIds = [...state.bundle.catalog.rules.filter((rule) => rule.status === "active"), ...state.bundle.catalog.protectedRules].map((rule) => rule.id).sort();
    if (answer?.schemaVersion !== 1 || answer.requestId !== request.requestId || answer.candidateKey !== candidate.key
      || answer.authoritySha256 !== request.authoritySha256 || answer.proposedTextSha256 !== hash
      || answer.catalogSha256 !== profile.catalogSha256 || answer.protectedRulesSha256 !== profile.protectedRulesSha256
      || answer.model !== profile.model || answer.reasoningEffort !== profile.reasoningEffort
      || !Array.isArray(answer.catalogRuleIds) || JSON.stringify([...answer.catalogRuleIds].sort()) !== JSON.stringify(expectedIds)
      || typeof answer.message !== "string" || !answer.message.trim() || answer.message.length > 20000
      || (answer.suggestedWording !== null && (typeof answer.suggestedWording !== "string" || !answer.suggestedWording.trim() || answer.suggestedWording.length > 20000))) {
      throw createRuleAssistanceError("Rule assistance returned a stale or invalid reply.");
    }
    controller.signal.throwIfAborted();
    if (!isCurrentRuleAssistanceRequest(chat, active)) return;
    turn.answer = answer;
    turn.duration = formatElapsedTime(performance.now() - startedAt);
    turn.status = "";
  } catch (error) {
    if (controller.signal.aborted) turn.status = "Operation canceled.";
    else {
      turn.status = "";
      turn.error = error?.assistanceError || { code: "rule-assistance-failed", message: "The AI chat request could not be completed.", diagnosticId: null };
    }
    turn.failed = !controller.signal.aborted;
  } finally {
    if (isCurrentRuleAssistanceRequest(chat, active)) {
      if (!turn.answer && active.submittedInput !== null && chat.input === "") chat.input = active.submittedInput;
      chat.active = null;
      if (ruleAssistance === chat) syncRuleAssistance();
    }
  }
}

function formatElapsedTime(milliseconds) {
  const seconds = Math.max(1, Math.round(milliseconds / 1000));
  return seconds < 60 ? `${seconds}s` : `${Math.floor(seconds / 60)}m ${seconds % 60}s`;
}

function openNewRuleAssistanceDialog(chat, trigger, { title, message }) {
  if (chat.active || !chat.turns.length || document.querySelector("[data-assist-new-chat-dialog]")) return;
  const dialog = document.createElement("dialog");
  dialog.className = "modal-dialog modal-dialog-warning";
  dialog.setAttribute("data-assist-new-chat-dialog", "");
  dialog.setAttribute("aria-labelledby", "assist-new-chat-title");
  dialog.setAttribute("aria-describedby", "assist-new-chat-description");
  dialog.innerHTML = `<div class="modal-dialog-heading"><div class="modal-dialog-title">${icon("warning")}<h2 id="assist-new-chat-title">${escapeHtml(title)}</h2></div><button class="titlebar-icon clickable" type="button" data-assist-new-chat-cancel aria-label="Close confirmation" data-workbench-tooltip="Close">${icon("close")}</button></div><div class="modal-dialog-content"><p id="assist-new-chat-description">${escapeHtml(message)}</p><p>This action cannot be undone.</p><div class="modal-dialog-actions"><button class="button primary clickable" type="button" data-assist-new-chat-cancel>Cancel</button><button class="button destructive clickable" type="button" data-assist-new-chat-confirm>${icon("trash")}<span>Clear Chat</span></button></div></div>`;
  dialog.addEventListener("close", () => {
    dialog.remove();
    const focusTarget = trigger.isConnected && !trigger.disabled ? trigger
      : !elements["rule-assistance-panel"].hidden ? elements["assist-sidebar-content"].querySelector(".assist-goal")
        : elements["assist-panel-toggle"];
    focusTarget?.focus({ preventScroll: true });
  }, { once: true });
  dialog.addEventListener("click", (event) => {
    if (!dialog.open) return;
    if (event.target.closest("[data-assist-new-chat-cancel]")) dialog.close();
    else if (event.target.closest("[data-assist-new-chat-confirm]")) {
      if (ruleAssistanceChats.get(chat.contextKey) === chat && !chat.active) {
        chat.turns = [];
        chat.followOutput = true;
        chat.scrollTop = 0;
        if (ruleAssistance === chat) syncRuleAssistance();
      }
      dialog.close();
    } else if (event.target === dialog) {
      const bounds = dialog.getBoundingClientRect();
      if (event.clientX < bounds.left || event.clientX > bounds.right || event.clientY < bounds.top || event.clientY > bounds.bottom) dialog.close();
    }
  });
  dialog.addEventListener("keydown", (event) => {
    if (event.key !== "Escape") return;
    event.preventDefault();
    event.stopPropagation();
    dialog.close();
  });
  document.body.append(dialog);
  dialog.showModal();
  dialog.querySelector(".button[data-assist-new-chat-cancel]").focus();
}

async function handleRuleAssistanceClick(event) {
  const chat = ruleAssistance;
  if (!chat) return;
  const retry = event.target.closest("[data-assist-error-retry]");
  if (retry) {
    const turn = chat.turns[Number(retry.dataset.assistErrorRetry)];
    if (canRetryRuleAssistance(turn)) await sendRuleAssistance(turn);
  } else if (event.target.closest("[data-assist-sidebar-close]")) {
    setRuleAssistanceExpanded(false);
    elements["assist-panel-toggle"].focus({ preventScroll: true });
  } else if (event.target.closest("[data-assist-clear]") && !chat.active) {
    const viewLabel = chat.viewKind === "assessment-results" ? "Assessment" : "Candidate";
    openNewRuleAssistanceDialog(chat, event.target.closest("[data-assist-clear]"), {
      title: `Start a New AI ${viewLabel} Chat?`,
      message: `This will permanently clear the ${viewLabel} AI chat history from this Workbench. Future AI requests in this chat will not include that history.`
    });
  } else if (event.target.closest("[data-assist-send]")) {
    if (chat.active) {
      cancelRuleAssistance();
    } else await sendRuleAssistance();
  } else if (event.target.closest("[data-assist-scroll-latest]")) {
    const transcript = elements["assist-sidebar-content"].querySelector(".assist-chat-response");
    if (!transcript) return;
    transcript.scrollTop = transcript.scrollHeight;
    chat.scrollTop = transcript.scrollTop;
    chat.followOutput = true;
    syncRuleAssistanceScrollControl();
  } else if (event.target.closest("[data-assist-copy]")) {
    const button = event.target.closest("[data-assist-copy]");
    const turn = chat.turns[Number(button.dataset.assistCopy)];
    if (!turn?.answer?.suggestedWording) return;
    try {
      await navigator.clipboard.writeText(turn.answer.suggestedWording);
      button.innerHTML = icon("check");
      button.setAttribute("aria-label", "Suggested rule wording copied");
      button.dataset.workbenchTooltip = "Copied";
    } catch {
      button.innerHTML = icon("copy");
      button.setAttribute("aria-label", "Unable to copy suggested rule wording");
      button.dataset.workbenchTooltip = "Unable to copy";
    }
  }
}

function renderAssessment() {
  if (state.workspaceTab === "candidate-sources") setRuleAssistanceCandidate(getActiveCandidate(), "candidate-sources");
  const protectedRule = getActiveProtectedRule();
  if (protectedRule) {
    renderProtectedRuleDetails(protectedRule);
    return;
  }
  const candidate = getActiveCandidate();
  if (!candidate) {
    elements["assessment-panel"].innerHTML = `<div class="empty-state">${icon("tasklist")}<h2>Select a Candidate</h2><p>The full source rule, AI evaluation, impact details, Hosted coverage, and maintainer actions will appear here.</p></div>`;
    refreshPresentation();
    return;
  }
  const decision = getDecision(candidate);
  const assessment = getAssessment(candidate, decision);
  if (!getBaselineAssessment(candidate, decision)) {
    elements["assessment-panel"].innerHTML = `<div class="empty-state"><h2>AI Assessment Unavailable</h2><p>This candidate is not ready for maintainer review and should not appear in the evaluated candidate tree.</p></div>`;
    return;
  }
  const catalogStatus = getCatalogStatus(candidate);
  const allowedActions = getAllowedActions(candidate, decision.proposedText);
  const unchangedMappedRule = catalogStatus.key === "mapped" && !hasHostedTextChange(candidate, decision.proposedText);
  const displayId = getEffectiveHostedRuleId(candidate);
  const hasSelectedRuleAction = allowedActions.includes(decision.action);
  const rationaleDisabled = !hasSelectedRuleAction || (decision.action === "no-change" && decision.retireHostedRuleIds.length === 0);
  const rationalePlaceholder = hasSelectedRuleAction ? "No rationale is required for No Change." : "Select a rule action to record rationale.";

  elements["assessment-panel"].innerHTML = `
    <div class="assessment-title">
      <div>
        <div class="source-line detail-identity">
          <span>Synthesized recommendation</span>
          <span>/</span>
          <span>${escapeHtml(displayId)}</span>
        </div>
        <h2 class="detail-rule-title">${escapeHtml(candidate.title)}</h2>
        <div class="source-line"><span>${escapeHtml(formatCountLabel(candidate.members.length, "source rule"))}</span><span>${escapeHtml(formatHostedCategory(candidate.assessment.hostedCategory))}</span><span>${escapeHtml(candidate.recommendation.placement)}</span></div>
      </div>
      ${renderDetailHeaderActions(`
        <span class="ui-badge status-capsule candidate-state ${escapeHtml(candidate.state)}">${escapeHtml(capitalize(candidate.state))}</span>
        <span class="ui-badge status-capsule decision-badge ${escapeHtml(decision.action)}">${escapeHtml(formatRecommendation(decision.action))}</span>
        ${renderCatalogStatusBadge(catalogStatus)}
      `)}
    </div>

    <div class="assessment-content scroll-surface">
      ${renderEvidenceDisclosure(candidate, "sources", "Source Rules", candidate.members.length, renderContributingRules(candidate))}
      <div class="section-block" data-assessment-evidence>${renderAssessmentEvidence(candidate, assessment, decision)}</div>

      <div class="section-block hosted-rule-comparison">
        ${renderCurrentHostedRules(catalogStatus)}
        <div class="proposed-rule-heading">
          <span class="section-label">Proposed Hosted Rule:</span>
          <span class="proposed-rule-statuses" role="group" aria-label="Proposed rule status">
            ${renderProposedRuleRecommendation(candidate, assessment)}
          </span>
          <span class="proposed-rule-actions" role="group" aria-label="Proposed rule actions">
            <button class="titlebar-icon proposed-rule-save" type="button" data-proposed-text-save aria-label="Save proposed Hosted rule" data-workbench-tooltip="Save proposed Hosted rule" disabled>${icon("save")}</button>
            <button class="titlebar-icon clickable" type="button" data-proposed-text-reset aria-label="Reset rule to original" data-workbench-tooltip="Reset rule to original" ${hasOriginalRuleResetChanges(candidate) ? "" : "disabled"}>${icon("debug-restart")}</button>
          </span>
        </div>
        <div data-proposed-rule-explanation>${renderAssessmentExplanation(candidate, assessment)}</div>
        <label><textarea class="evidence-box proposed-rule scroll-surface" data-decision-field="proposedText" data-proposed-candidate-key="${escapeHtml(candidate.key)}" aria-label="Proposed Hosted rule wording">${escapeHtml(decision.proposedText || "")}</textarea></label>
      </div>

      <div class="section-block rule-actions">
        <span class="section-label">Rule Actions: <strong class="rule-reference">${escapeHtml(displayId)}</strong></span>
        ${renderInformationPanel(`<p>${unchangedMappedRule ? "Current and proposed Hosted rule text are identical, so Update is unavailable." : "Choose one action. Hosted catalog status determines which actions are available."}</p>`, { className: "rule-actions-guidance section-guidance" })}
        <div class="rule-actions-content">
          <span class="control-subtitle">Rule Action:</span>
          <div class="control-group action-plan-group">
            <fieldset class="action-options">
              <legend class="sr-only">Rule action</legend>
              ${allowedActions.map((action) => `
                <label class="action-option clickable ${decision.action === action ? "selected" : ""}">
                  <input type="radio" name="rule-action" data-rule-action="${escapeHtml(action)}" value="${escapeHtml(action)}" ${decision.action === action ? "checked" : ""}>
                  <span>${escapeHtml(formatRecommendation(action))}</span>
                </label>
              `).join("")}
            </fieldset>
          </div>
          ${candidate.recommendation?.category === "implementation" ? `<div class="control-group implementation-model-control-group">
            <span class="control-subtitle" id="implementation-models-label">Rule Applies to Resource Type(s):</span>
            <div class="action-plan-group">
              <fieldset class="action-options implementation-model-options" aria-labelledby="implementation-models-label">
                <legend class="sr-only">Rule applies to resource types</legend>
                ${IMPLEMENTATION_MODELS.map((model) => `
                  <label class="action-option implementation-model-option ${canEditImplementationModels(candidate, decision.action) ? "clickable" : ""}">
                    <input type="checkbox" data-implementation-model="${escapeHtml(model)}" value="${escapeHtml(model)}" ${decision.implementationModels.includes(model) ? "checked" : ""} ${canEditImplementationModels(candidate, decision.action) ? "" : "disabled"}>
                    <span>${escapeHtml(capitalize(model))}</span>
                  </label>
                `).join("")}
              </fieldset>
            </div>
          </div>` : ""}
          ${getAvailableRetirementRuleIds(candidate, decision).length ? `<div class="control-group ancillary-retirement-control-group">
            <span class="control-subtitle" id="ancillary-retirements-label">Related Hosted Rules to Retire:</span>
            <p class="section-help">Reconciliation supplied these lifecycle actions. Clear a rule to keep it active.</p>
            <div class="action-plan-group">
              <fieldset class="action-options ancillary-retirement-options" aria-labelledby="ancillary-retirements-label">
                <legend class="sr-only">Related Hosted rules to retire</legend>
                ${getAvailableRetirementRuleIds(candidate, decision).map((ruleId) => `
                  <label class="action-option clickable">
                    <input type="checkbox" data-retire-hosted-rule="${escapeHtml(ruleId)}" value="${escapeHtml(ruleId)}" ${decision.retireHostedRuleIds.includes(ruleId) ? "checked" : ""}>
                    <span>Retire ${escapeHtml(ruleId)}</span>
                  </label>
                `).join("")}
              </fieldset>
            </div>
          </div>` : ""}
          <div class="field-stack control-group rationale-control-group">
            <div class="rationale-heading"><span class="control-subtitle" id="decision-rationale-label">Decision Rationale:</span><button class="titlebar-icon clickable rationale-save" type="button" data-rationale-save aria-label="${state.rationaleReturnView === "plan" ? "Save decision and return to Promotion Plan" : "Save decision"}" data-workbench-tooltip="${state.rationaleReturnView === "plan" ? "Save decision and return to Promotion Plan" : "Save decision"}" disabled>${icon("save")}</button></div>
            <label><textarea class="evidence-box scroll-surface" data-decision-field="rationale" maxlength="${DECISION_RATIONALE_MAX_LENGTH}" aria-labelledby="decision-rationale-label" aria-describedby="decision-rationale-limit" placeholder="${rationaleDisabled ? rationalePlaceholder : "Record why this action is appropriate."}" ${rationaleDisabled ? "disabled" : ""}>${escapeHtml(rationaleDisabled ? "" : decision.rationale)}</textarea><small class="rationale-limit" id="decision-rationale-limit">${rationaleDisabled ? 0 : decision.rationale.length} / ${DECISION_RATIONALE_MAX_LENGTH} characters</small></label>
          </div>
        </div>
      </div>
    </div>
  `;
  syncProposedRuleControls(candidate);
}

function renderAssessmentEvidence(candidate, assessment, decision) {
  const evidence = assessment || getBaselineAssessment(candidate, decision);
  const factors = evidence.selectionFactors || evidence.factors;
  const cost = getDecisionTokenDelta(candidate, decision);
  return `
    <div data-assessment-origin="${assessment && !hasMaintainerEditedRuleText(candidate) ? "current" : "original"}">
    <div class="assessment-details-heading">
      <div class="assessment-details-title-row"><strong class="section-label">Assessment Details:</strong><button class="titlebar-icon clickable scoring-legend-trigger" type="button" data-scoring-legend-open aria-label="Show scoring legend" data-workbench-tooltip="Show scoring legend">${icon("question")}</button></div>
    </div>
    ${renderInformationPanel(`<p ${assessment && !hasMaintainerEditedRuleText(candidate) ? "" : "data-assessment-history"}><strong>Assessment:</strong> ${assessment && !hasMaintainerEditedRuleText(candidate) ? "Priority and factor scores are AI-adjudicated evidence. Maintainers can review these values but cannot edit them." : `Priority and factor scores describe the original rebuild proposal, whose recommendation was ${escapeHtml(formatRecommendation(evidence.recommendation))}; they do not validate the maintainer-edited wording.`} Token Cost and Token Headroom reflect the current draft.</p>`, { className: "assessment-context section-guidance" })}
    <div class="score-strip">
      <div class="score-item impact"><span class="control-subtitle">Priority Score:</span><strong>${calculateImpact(factors)}</strong></div>
      <div class="score-item cost"><span class="control-subtitle">Token Cost:</span><strong>${cost === 0 ? "0" : formatSignedNumber(cost)}</strong></div>
      <div class="score-item efficiency"><span class="control-subtitle">Token Headroom:</span><strong>${formatNumber(getAssessmentProjectedHeadroom(candidate, decision.action, decision))}</strong></div>
    </div>
    <dialog class="modal-dialog" data-scoring-legend-dialog aria-labelledby="scoring-legend-dialog-title">
      <div class="modal-dialog-heading"><div class="modal-dialog-title">${icon("json")}<h2 id="scoring-legend-dialog-title">Scoring Legend</h2></div><button class="titlebar-icon clickable" type="button" data-scoring-legend-close aria-label="Close scoring legend" data-workbench-tooltip="Close scoring legend">${icon("close")}</button></div>
      <div class="modal-dialog-content scroll-surface">
        <div class="scoring-legend-items">
          <div class="scoring-legend-item"><span class="control-subtitle">Score Scale:</span><span>Scores run from 0 (none) through 5 (very high); a score of 4 means high.</span></div>
          <div class="scoring-legend-item"><span class="control-subtitle"><i class="legend-swatch value"></i>Rule Value:</span><span>Higher scores strengthen the case for adding or updating Hosted review coverage.</span></div>
          <div class="scoring-legend-item"><span class="control-subtitle"><i class="legend-swatch risk"></i>Review Risk:</span><span>Higher scores strengthen the reason to avoid a change and reduce the candidate priority.</span></div>
          <div class="scoring-legend-item"><span class="control-subtitle">Existing Coverage:</span><span>0 means no current Hosted coverage; 5 means active Hosted rules already cover the behavior completely.</span></div>
        </div>
      </div>
    </dialog>
    <div class="factor-groups">
      <section class="factor-group value">
        <div class="factor-group-heading"><strong>Rule Value:</strong><span class="ui-badge status-capsule direction-badge positive">Adds to Impact</span></div>
        <div class="factor-grid">
          ${FACTORS.filter(([, , , kind]) => kind === "value").map(([name, label, description, kind]) => factorReadout(label, description, kind, factors[name])).join("")}
        </div>
      </section>
      <section class="factor-group penalty">
        <div class="factor-group-heading"><strong>Review Risk:</strong><span class="ui-badge status-capsule direction-badge negative">Reduces Impact</span></div>
        <div class="factor-grid">
          ${FACTORS.filter(([, , , kind]) => kind === "penalty").map(([name, label, description, kind]) => factorReadout(label, description, kind, factors[name])).join("")}
        </div>
      </section>
    </div>
    </div>
  `;
}

function factorReadout(label, description, kind, value) {
  const riskClass = kind === "penalty" ? ` risk-${value <= 2 ? "low" : value === 3 ? "moderate" : "high"}` : "";
  return `
    <div class="factor-line ${kind}${riskClass}">
      <span class="factor-copy"><strong class="control-subtitle">${escapeHtml(label)}:</strong><small>${escapeHtml(description)}</small></span>
      <progress class="factor-meter" max="5" value="${Number(value)}">${Number(value)} of 5</progress>
      <span class="factor-value" aria-label="${escapeHtml(label)} score">${Number(value)}</span>
    </div>
  `;
}

function undoDecision(candidate) {
  const savedDecision = state.session.decisions[candidate.key];
  if (!getDecision(candidate).inPlan || !savedDecision) return;
  const override = getApplicabilityOverride(candidate);
  prepareRuleIssueRestore([candidate.key]);
  resetCandidate(candidate).then(() => {
    showToast(override ? "Override and plan item removed." : "Candidate removed and reset.");
  });
}

function handleRuleAssistanceInput(event) {
  if (event.target.matches(".assist-goal") && ruleAssistance) {
    ruleAssistance.input = event.target.value;
    const button = event.target.closest("[data-rule-assistance]").querySelector("[data-assist-send]");
    const ready = Boolean(event.target.value.trim() && globalThis.__HOSTED_RULE_WORKBENCH__?.ruleAssistance?.model && !ruleAssistance.active);
    button.disabled = !ruleAssistance.active && !ready;
    button.classList.toggle("assist-chat-send-ready", ready);
    button.classList.toggle("clickable", ready);
    return;
  }
}

function handleAssessmentInput(event) {
  const candidate = getActiveCandidate();
  if (!candidate) return;
  if (event.target.dataset.ruleAction) {
    const action = event.target.dataset.ruleAction;
    if (action === "no-change") {
      if (getDecision(candidate).retireHostedRuleIds.length) updateDecision(candidate, { action });
      else {
        removeCandidateFromBulkOperations(candidate.key);
        saveDecision(candidate, null);
      }
      syncAssessmentActionControls(candidate, action);
      syncImplementationModelControls(candidate, action);
      syncAssessmentRationaleControls(action, candidate);
      syncProposedRuleControls(candidate);
      event.target.focus({ preventScroll: true });
      return;
    }
    syncAssessmentActionControls(candidate, action);
    syncImplementationModelControls(candidate, action);
    syncAssessmentRationaleControls(action, candidate);
    return;
  }
  if (event.target.dataset.retireHostedRule) {
    const retireHostedRuleIds = [...elements["assessment-panel"].querySelectorAll("[data-retire-hosted-rule]:checked")]
      .map((control) => control.dataset.retireHostedRule);
    updateDecision(candidate, { retireHostedRuleIds });
    renderAssessment();
    return;
  }
  if (event.target.dataset.implementationModel) {
    const implementationModels = [...elements["assessment-panel"].querySelectorAll("[data-implementation-model]:checked")]
      .map((control) => control.dataset.implementationModel);
    updateDecision(candidate, { implementationModels });
    return;
  }
  if (event.target.dataset.decisionField) {
    const value = event.target.dataset.decisionField === "rationale"
      ? event.target.value.slice(0, DECISION_RATIONALE_MAX_LENGTH)
      : event.target.value;
    event.target.value = value;
    if (event.target.dataset.decisionField === "proposedText") {
      elements["assist-sidebar-content"].querySelectorAll("[data-assist-error-retry]").forEach(button => {
        button.disabled = !canRetryRuleAssistance(ruleAssistance?.turns[Number(button.dataset.assistErrorRetry)]);
      });
      syncProposedRuleControls(candidate);
    }
    if (event.target.dataset.decisionField === "rationale") {
      const counter = elements["assessment-panel"].querySelector(".rationale-limit");
      if (counter) counter.textContent = `${value.length} / ${DECISION_RATIONALE_MAX_LENGTH} characters`;
      syncDecisionSaveState(candidate);
    }
  }
}

function handleDetailBackToTopClick(event) {
  const button = event.target.closest("[data-detail-back-to-top]");
  if (!button || button.disabled) return;
  const content = button.closest(".assessment-panel")?.querySelector(":scope > .assessment-content");
  content?.scrollTo({ top: 0, behavior: "smooth" });
}

function handleDetailContentScroll(event) {
  const content = event.target;
  if (content instanceof Element && content.matches(".assist-chat-response") && ruleAssistance) {
    if (!ruleAssistanceExpanded) return;
    ruleAssistance.scrollTop = content.scrollTop;
    ruleAssistance.followOutput = content.scrollHeight - content.clientHeight - content.scrollTop <= 4;
    syncRuleAssistanceScrollControl();
    return;
  }
  if (!(content instanceof Element) || !content.matches(".assessment-content")) return;
  const button = content.parentElement?.querySelector(":scope > .assessment-title [data-detail-back-to-top]");
  if (button) button.disabled = content.scrollTop <= 1;
}
function syncAssessmentActionControls(candidate, action = getDecision(candidate).action) {
  elements["assessment-panel"].querySelectorAll("[data-rule-action]").forEach((control) => {
    const selected = control.dataset.ruleAction === action;
    control.checked = selected;
    control.closest(".action-option")?.classList.toggle("selected", selected);
  });
  const badge = elements["assessment-panel"].querySelector(":scope > .assessment-title .decision-badge");
  if (badge) {
    badge.className = `ui-badge status-capsule decision-badge ${action}`;
    badge.textContent = formatRecommendation(action);
  }
  refreshAssessmentScores(candidate, action);
}

function syncImplementationModelControls(candidate, action = getDecision(candidate).action) {
  const selectedModels = getDecision(candidate).implementationModels;
  const editable = canEditImplementationModels(candidate, action);
  elements["assessment-panel"].querySelectorAll("[data-implementation-model]").forEach((control) => {
    control.checked = selectedModels.includes(control.dataset.implementationModel);
    control.disabled = !editable;
    control.closest(".implementation-model-option")?.classList.toggle("clickable", editable);
  });
}

function syncDecisionSaveState(candidate = getActiveCandidate()) {
  const save = elements["assessment-panel"].querySelector("[data-rationale-save]");
  const rationale = elements["assessment-panel"].querySelector('[data-decision-field="rationale"]');
  const action = elements["assessment-panel"].querySelector("[data-rule-action]:checked")?.dataset.ruleAction;
  if (!save || !rationale || !candidate || !action) return;
  const persisted = getDecision(candidate);
  const value = rationale.value.trim();
  const removesDecision = !value && Boolean(state.session.decisions[candidate.key]);
  const dirty = action !== persisted.action || value !== persisted.rationale.trim();
  save.disabled = !(removesDecision || (Boolean(value) && dirty));
  const saveLabel = state.rationaleReturnView === "plan" ? "Save decision and return to Promotion Plan" : "Save decision";
  const label = removesDecision ? "Remove saved decision" : saveLabel;
  save.setAttribute("aria-label", label);
  setWorkbenchTooltip(save, label);
}

function syncAssessmentRationaleControls(action, candidate = getActiveCandidate()) {
  const rationale = elements["assessment-panel"].querySelector('[data-decision-field="rationale"]');
  const limit = elements["assessment-panel"].querySelector(".rationale-limit");
  const save = elements["assessment-panel"].querySelector("[data-rationale-save]");
  if (!rationale) return;
  const noChange = action === "no-change" && (!candidate || getDecision(candidate).retireHostedRuleIds.length === 0);
  if (noChange) rationale.value = "";
  rationale.disabled = noChange;
  rationale.placeholder = noChange ? "No rationale is required for No Change." : "Record why this action is appropriate.";
  if (limit) limit.textContent = `${noChange ? 0 : rationale.value.length} / ${DECISION_RATIONALE_MAX_LENGTH} characters`;
  if (save) {
    if (noChange) save.disabled = true;
    else syncDecisionSaveState(candidate);
  }
}

async function handleAssessmentClick(event) {
  const resetTrigger = event.target.closest("[data-proposed-text-reset]");
  if (resetTrigger) {
    const candidate = getActiveCandidate();
    if (candidate && !resetTrigger.disabled) openOriginalRuleResetDialog(candidate, resetTrigger);
    return;
  }
  const resetCancel = event.target.closest("[data-rule-reset-cancel]");
  if (resetCancel) { resetCancel.closest("dialog")?.close(); return; }
  if (event.target.closest("[data-rule-reset-confirm]")) {
    const dialog = event.target.closest("dialog");
    const candidate = getActiveCandidate();
    const key = dialog?.dataset.candidateKey;
    dialog?.close();
    if (candidate?.key === key) await resetOriginalRule(candidate);
    return;
  }
  if (event.target.closest("[data-rule-assistance]")) {
    await handleRuleAssistanceClick(event);
    return;
  }
  if (event.target.closest("[data-rule-issue-plan], [data-dismiss-rule-issue-banner]")) {
    await handleRuleIssueDetailClick(event);
    return;
  }
  const scoringLegendTrigger = event.target.closest("[data-scoring-legend-open]");
  if (scoringLegendTrigger) {
    const dialog = elements["assessment-panel"].querySelector("[data-scoring-legend-dialog]");
    if (!dialog) return;
    dialog.addEventListener("close", () => scoringLegendTrigger.focus(), { once: true });
    dialog.showModal();
    dialog.querySelector("[data-scoring-legend-close]")?.focus();
    return;
  }
  const scoringLegendClose = event.target.closest("[data-scoring-legend-close]");
  if (scoringLegendClose) {
    scoringLegendClose.closest("dialog")?.close();
    return;
  }
  if (event.target.closest("[data-proposed-text-save]")) {
    const candidate = getActiveCandidate();
    if (!candidate) return;
    const proposedText = elements["assessment-panel"].querySelector('[data-decision-field="proposedText"]')?.value;
    if (proposedText === undefined) return;
    const content = elements["assessment-panel"].querySelector(".assessment-content");
    const scrollTop = content?.scrollTop || 0;
    if (!await persistProposedRuleText(candidate, proposedText)) return;
    syncCandidateTreeRows();
    renderBulkActions();
    syncProposedRuleControls(candidate);
    renderAssessment();
    const refreshedContent = elements["assessment-panel"].querySelector(".assessment-content");
    if (refreshedContent) refreshedContent.scrollTop = scrollTop;
    renderRuleIssues();
    renderAssessmentResults();
    renderDecisionOutputs();
    showToast("Proposed Hosted rule saved.");
    return;
  }
  if (!event.target.closest("[data-rationale-save]")) return;
  const candidate = getActiveCandidate();
  if (!candidate) return;
  const rationale = elements["assessment-panel"].querySelector('[data-decision-field="rationale"]')?.value.trim() || "";
  const savedDecision = state.session.decisions[candidate.key];
  if (!rationale) {
    if (!savedDecision) return;
    removeCandidateFromBulkOperations(candidate.key);
    saveDecision(candidate, null);
    await persistencePromise;
    renderAssessment();
    showToast("Decision removed");
    return;
  }
  const action = elements["assessment-panel"].querySelector("[data-rule-action]:checked")?.dataset.ruleAction;
  if (!action) return;
  const current = getDecision(candidate);
  const proposedText = elements["assessment-panel"].querySelector('[data-decision-field="proposedText"]')?.value || current.proposedText;
  const retireHostedRuleIds = [...elements["assessment-panel"].querySelectorAll("[data-retire-hosted-rule]:checked")]
    .map((control) => control.dataset.retireHostedRule);
  const { assessment, ...maintainerDecision } = current;
  removeCandidateFromBulkOperations(candidate.key);
  saveDecision(candidate, {
    ...maintainerDecision,
    action,
    rationale,
    proposedText,
    retireHostedRuleIds,
    implementationModels: current.implementationModels,
    proposedHostedRuleId: candidate.assessment.proposedHostedRuleId,
    ...createPlanMembership(isPromotionAction(action) || retireHostedRuleIds.length ? "manual" : "none")
  });
  const submittedDecision = state.session.decisions[candidate.key];
  const returnToPlan = state.rationaleReturnView === "plan";
  await persistencePromise;
  if (state.session.decisions[candidate.key] !== submittedDecision) return;
  renderAssessment();
  showToast("Decision saved");
  if (returnToPlan) {
    state.rationaleReturnView = null;
    switchView("plan");
  }
}

function refreshAssessmentScores(candidate, action = getDecision(candidate).action) {
  syncAssessmentEvaluation(candidate, { ...getDecision(candidate), action });
}

function syncAssessmentEvaluation(candidate, decision = getDecision(candidate)) {
  const assessment = getAssessment(candidate, decision);
  const panel = elements["assessment-panel"];
  const displayDecision = decision;
  const evidence = panel.querySelector("[data-assessment-evidence]");
  if (evidence) evidence.innerHTML = renderAssessmentEvidence(candidate, assessment, displayDecision);
  const coverage = panel.querySelector('[data-evidence-kind="coverage"]');
  if (coverage) coverage.outerHTML = renderRelatedHostedCoverage(candidate, assessment);
  syncProposedRuleAssessment(candidate, assessment, displayDecision.proposedText);
}

function renderPlan() {
  const allPlanCandidates = sortPlanCandidates(getPlanCandidates(), state.planSort);
  const attentionCandidates = allPlanCandidates.filter((candidate) => !getPlanReadiness(candidate).ready);
  if (!attentionCandidates.length) state.planAttentionOnly = false;
  const attentionTooltip = !attentionCandidates.length
    ? "No promotion plan items need attention"
    : state.planAttentionOnly
      ? "Show all promotion plan items"
      : "Show only promotion plan items needing attention";
  elements["plan-attention-filter"].disabled = attentionCandidates.length === 0;
  elements["plan-attention-filter"].setAttribute("aria-pressed", String(state.planAttentionOnly));
  elements["plan-attention-filter"].setAttribute("aria-label", attentionCandidates.length ? `${attentionTooltip}, ${formatCountLabel(attentionCandidates.length, "Item")}` : attentionTooltip);
  setWorkbenchTooltip(elements["plan-attention-filter"], attentionTooltip);
  elements["plan-attention-count"].hidden = attentionCandidates.length === 0;
  elements["plan-attention-count"].textContent = formatNumber(attentionCandidates.length);
  const planCandidates = state.planAttentionOnly ? attentionCandidates : allPlanCandidates;
  const undoCounts = Object.fromEntries(["all", "manual", "bulk", "override"].map((scope) => [scope, getPlanUndoCandidates(scope).length]));
  const undoLabel = undoCounts.all ? `Undo promotion plan items, ${formatCountLabel(undoCounts.all, "Item")}` : "No plan items to undo";
  elements["plan-undo-trigger"].setAttribute("aria-disabled", String(undoCounts.all === 0));
  elements["plan-undo-trigger"].setAttribute("aria-label", undoLabel);
  elements["plan-undo-trigger"].tabIndex = undoCounts.all ? 0 : -1;
  setWorkbenchTooltip(elements["plan-undo-trigger"], undoLabel);
  if (!undoCounts.all) elements["plan-undo-menu"].removeAttribute("open");
  ["all", "manual", "bulk", "override"].forEach((scope) => {
    const button = elements["plan-undo-menu"].querySelector(`[data-plan-undo-scope="${scope}"]`);
    button.disabled = undoCounts[scope] === 0;
    elements[`plan-undo-${scope}-count`].textContent = formatCountLabel(undoCounts[scope], "Item");
  });
  elements["plan-table-head"].innerHTML = renderPlanHeader();
  elements["empty-plan"].hidden = planCandidates.length > 0;
  elements["plan-table-body"].innerHTML = planCandidates.map((candidate) => {
    const decision = getDecision(candidate);
    const assessment = getAssessment(candidate, decision);
    const impact = assessment ? calculateImpact(assessment.factors) : null;
    const cost = getPlanTokenDisplay(candidate);
    const readiness = getPlanReadiness(candidate);
    const displayId = getEffectiveHostedRuleId(candidate);
    const readinessLabel = readiness.attention?.actionLabel || readiness.label;
    const readinessIcon = readiness.attention?.actionIcon || "edit";
    const detailLabel = `${readiness.attention?.reason === "pending" ? "Checking rule relationships" : readinessLabel} for ${displayId}`;
    const detailTooltip = `Open candidate: ${readiness.attention?.reason === "pending" ? "Checking rule relationships" : readiness.label}`;
    const undoLabel = "Undo this candidate";
    return `
      <tr class="plan-candidate-row clickable" tabindex="0" data-plan-row="${escapeHtml(candidate.key)}" aria-label="Open ${escapeHtml(displayId)} candidate">
        <td class="plan-candidate"><span class="candidate-link">${escapeHtml(displayId)}</span><br><span class="plan-candidate-title">${escapeHtml(candidate.title)}</span></td>
        <td class="plan-source"><span class="ui-badge status-capsule status-badge neutral plan-source-pill type-compact">${escapeHtml(formatTitleCase(candidate.sourceLabel))}</span></td>
        <td class="plan-type"><span class="ui-badge status-capsule status-badge neutral plan-membership-badge">${escapeHtml(formatTitleCase(decision.planMembershipSource))}</span></td>
        <td class="plan-action"><span class="ui-badge status-capsule recommendation-badge ${escapeHtml(isPromotionAction(decision.action) ? decision.action : decision.retireHostedRuleIds.length ? "retire" : decision.action)}">${escapeHtml(formatPlanAction(decision))}</span></td>
        <td class="mono">${impact}</td>
        <td class="mono">${cost}</td>
        <td>${readiness.ready ? `<span class="ui-badge status-capsule status-badge success">${readiness.label}</span>` : readiness.actionRequired ? `<button class="ui-badge status-capsule status-badge warning plan-detail-link clickable" type="button" data-plan-action="${escapeHtml(candidate.key)}" aria-label="Choose a rule action for ${escapeHtml(displayId)}" data-workbench-tooltip="Open candidate and choose a rule action">${icon("edit")}<span>${readiness.label}</span></button>` : `<button class="ui-badge status-capsule status-badge warning plan-detail-link clickable" type="button" data-plan-detail="${escapeHtml(candidate.key)}" aria-label="${escapeHtml(detailLabel)}" data-workbench-tooltip="${escapeHtml(detailTooltip)}">${icon(readinessIcon)}<span>${readinessLabel}</span></button>`}</td>
        <td class="plan-actions"><span class="plan-action-controls"><button class="titlebar-icon clickable" type="button" data-plan-undo="${escapeHtml(candidate.key)}" aria-label="${escapeHtml(undoLabel)}" data-workbench-tooltip="${escapeHtml(undoLabel)}">${icon("discard")}</button></span></td>
      </tr>
    `;
  }).join("");
}

function renderPlanHeader() {
  const columns = [
    ["candidate", "Candidate", "Candidate", "Rule ID and title."],
    ["source", "Source", "Source", "Origin of the candidate rule."],
    ["type", "Type", "Type", "How the candidate entered the promotion plan."],
    ["action", "Action", "Action", "Selected promotion action."],
    ["impact", "Impact", "Impact", "Priority score for the candidate."],
    ["cost", "Draft Cost", "Draft Cost", "Estimated guarded-token change."],
    ["readiness", "Readiness", "Readiness", "Remaining work before approval."]
  ];
  const headers = columns.map((column) => {
    const active = state.planSort.field === column[0];
    return `<th scope="col" ${active ? `aria-sort="${state.planSort.direction}"` : ""}>${renderSortButton(column, state.planSort, { "plan-sort": column[0] })}</th>`;
  }).join("");
  return `<tr>${headers}<th scope="col">Controls</th></tr>`;
}

function updatePlanSort(button) {
  const field = button.dataset.planSort;
  state.planSort = {
    field,
    direction: state.planSort.field === field && state.planSort.direction === "ascending" ? "descending" : "ascending"
  };
  renderPlan();
}

function sortPlanCandidates(candidates, sort) {
  const collator = new Intl.Collator(undefined, { numeric: true, sensitivity: "base" });
  const value = (candidate) => {
    const decision = getDecision(candidate);
    const assessment = getAssessment(candidate, decision);
    if (sort.field === "candidate") return `${getEffectiveHostedRuleId(candidate)} ${candidate.title}`;
    if (sort.field === "source") return candidate.sourceLabel;
    if (sort.field === "type") return decision.planMembershipSource;
    if (sort.field === "action") return formatPlanAction(decision);
    if (sort.field === "impact") return assessment ? calculateImpact(assessment.factors) : Number.NEGATIVE_INFINITY;
    if (sort.field === "cost") return getPlanTokenValue(candidate);
    return getPlanReadiness(candidate).label;
  };
  return [...candidates].sort((left, right) => {
    const leftValue = value(left);
    const rightValue = value(right);
    const compared = typeof leftValue === "number" ? leftValue - rightValue : collator.compare(leftValue, rightValue);
    const directed = sort.direction === "ascending" ? compared : -compared;
    return directed || collator.compare(getEffectiveHostedRuleId(left), getEffectiveHostedRuleId(right));
  });
}

function getPlanReadiness(candidate) {
  const decision = getDecision(candidate);
  const assessment = getAssessment(candidate, decision);
  const actionRequired = !isActionableDecision(decision);
  const rationaleRequired = isActionableDecision(decision) && !decision.rationale.trim();
  const resourceTypeRequired = canEditImplementationModels(candidate, decision.action) && decision.implementationModels.length === 0;
  const attention = actionRequired ? { reason: "action", label: "Needs action", target: ".action-options input:checked, .action-options input" }
    : resourceTypeRequired ? { reason: "resource-type", label: "Needs resource type", target: "[data-implementation-model]" }
    : rationaleRequired ? { reason: "rationale", label: "Needs rationale", target: '[data-decision-field="rationale"]' }
    : !assessment ? { reason: "assessment", label: "Needs AI assessment", target: "[data-assessment-evidence]" } : null;
  return {
    actionRequired,
    rationaleRequired,
    resourceTypeRequired,
    attention,
    ready: Boolean(assessment) && !actionRequired && !rationaleRequired && !resourceTypeRequired,
    label: attention?.label || "Ready"
  };
}

function getPlanTokenValue(candidate) {
  return getPlanTokenDelta(candidate);
}

function getPlanTokenDisplay(candidate) {
  return formatSignedNumber(getPlanTokenValue(candidate));
}

function scrollCandidateDetailTargetIntoView(target) {
  const scroller = elements["assessment-panel"].querySelector(":scope > .assessment-content");
  if (!target || !scroller) return;
  const scrollerRect = scroller.getBoundingClientRect();
  const targetRect = target.getBoundingClientRect();
  const targetTop = scroller.scrollTop + targetRect.top - scrollerRect.top;
  const centeredOffset = Math.max(0, (scroller.clientHeight - targetRect.height) / 2);
  scroller.scrollTo({ top: Math.max(0, targetTop - centeredOffset), behavior: "smooth" });
}

function openPlanCandidate(key, focusTarget = null) {
  const candidateHasTreeRow = state.candidates.some((candidate) => candidate.key === key);
  setWorkspaceTab("candidate-sources");
  selectCandidate(key, "plan");
  switchView("catalog");
  showCandidatePane(focusTarget || !candidateHasTreeRow ? "details" : "candidates");
  requestAnimationFrame(() => {
    revealCandidateInTree(key);
    const row = elements["candidate-list"].querySelector(`[data-candidate-key="${CSS.escape(key)}"]`);
    requestAnimationFrame(() => {
      if (focusTarget === "attention") {
        const candidate = getActiveCandidate();
        focusCandidateAttention(getPlanReadiness(candidate).attention);
        return;
      }
      if (!row) return;
      row.scrollIntoView({ block: "center", behavior: "smooth" });
      row.focus({ preventScroll: true });
    });
  });
}

function focusCandidateAttention(attention) {
  if (!attention) {
    showToast("This candidate no longer needs attention.");
    return;
  }
  const target = elements["assessment-panel"].querySelector(attention.target);
  if (!target) {
    showToast(`The review control for ${attention.label.toLowerCase()} is unavailable.`, true);
    return;
  }
  if (!target.matches("button, input, textarea, select, [tabindex]")) {
    target.tabIndex = -1;
    target.setAttribute("role", "region");
    target.setAttribute("aria-label", attention.label);
  }
  scrollCandidateDetailTargetIntoView(target);
  target.focus({ preventScroll: true });
}

function handlePlanRowKeyboardNavigation(event) {
  const row = event.target.closest("[data-plan-row]");
  if (!row || event.target !== row || !["Enter", " "].includes(event.key)) return;
  event.preventDefault();
  openPlanCandidate(row.dataset.planRow);
}

function getPlanTokenDelta(candidate) {
  const decision = getDecision(candidate);
  return getDecisionTokenDelta(candidate, decision);
}

function getActionAffectedSurfaces(candidate, action, decision = getDecision(candidate)) {
  const assessment = getAssessment(candidate, decision);
  const surfaces = [];
  if (["add", "update", "restore"].includes(action)) surfaces.push(...(assessment?.affectedSurfaces || candidate.assessment.affectedSurfaces));
  if (action === "retire") {
    surfaces.push(...getCatalogStatus(candidate).rules.flatMap((rule) => (rule.placements || []).map((placement) => placement.surfaceId)));
  }
  surfaces.push(...getAncillaryRetirementRules(decision).flatMap((rule) => (rule.placements || []).map((placement) => placement.surfaceId)));
  return [...new Set(surfaces)];
}

function getPlanAffectedSurfaces(candidate) {
  const decision = getDecision(candidate);
  return getActionAffectedSurfaces(candidate, decision.action, decision);
}

function getAssessmentProjectedHeadroom(candidate, action, decision = getDecision(candidate)) {
  const capacity = getGuidanceCapacityProjection();
  const savedContribution = decision.inPlan
    ? getPlanTokenDelta(candidate) * getActionCapacityBucketNames(candidate, decision.action, decision).length
    : 0;
  const stagedDecision = { ...decision, action };
  const stagedContribution = getDecisionTokenDelta(candidate, stagedDecision) * getActionCapacityBucketNames(candidate, action, stagedDecision).length;
  return capacity.projectedHeadroomTokens + savedContribution - stagedContribution;
}

function renderCapacity() {
  const capacity = getGuidanceCapacityProjection();
  elements["capacity-panel"].innerHTML = `
    <p class="eyebrow">Plan projection</p>
    <h3>Guidance Capacity</h3>
    ${renderCapacityGroup("Overall Hosted Guidance", capacity.currentGuardedTokens, capacity.draftDeltaTokens, capacity.budgetTokens, true)}
    <div class="score-item"><span>Draft item estimate</span><strong>${formatNumber(capacity.draftDeltaTokens)} tokens</strong></div>
    <span class="control-subtitle guidance-capacity-buckets">Bucket Limits:</span>
    ${capacity.buckets.map((bucket) => renderCapacityGroup(bucket.label, bucket.currentGuardedTokens, bucket.draftDeltaTokens, bucket.budgetTokens)).join("")}
    <p class="capacity-footnote">Projected guarded-token usage. Each guidance file counts once toward the 25,000-token total and must also remain within its own bucket limit.</p>
  `;
}

function renderCapacityGroup(label, currentGuardedTokens, draftDeltaTokens, budgetTokens, overall = false) {
  const projectedGuardedTokens = Math.max(0, currentGuardedTokens + draftDeltaTokens);
  const projectedHeadroomTokens = budgetTokens - projectedGuardedTokens;
  const utilizationPercent = Math.round((projectedGuardedTokens / budgetTokens) * 10000) / 100;
  const percent = Math.min(100, utilizationPercent);
  const fillClass = percent > 85 ? "danger" : percent > 65 ? "warning" : "";
  const operator = draftDeltaTokens < 0 ? "&minus;" : "+";
  const projectedLabel = `${formatNumber(projectedGuardedTokens)} projected of ${formatNumber(budgetTokens)}`;
  return `
    <div class="capacity-group${overall ? " capacity-overall" : ""}" data-workbench-tooltip="${escapeHtml(projectedLabel)}">
      <div class="capacity-line"><strong class="capacity-label">${escapeHtml(label)}</strong><strong>${formatNumber(projectedHeadroomTokens)} free</strong></div>
      <progress class="capacity-progress ${fillClass}" max="100" value="${percent}" tabindex="0" aria-label="${escapeHtml(projectedLabel)}">${percent}%</progress>
      <div class="capacity-line"><span>${formatNumber(currentGuardedTokens)} current ${operator} ${formatNumber(Math.abs(draftDeltaTokens))} draft</span><span>${utilizationPercent}%</span></div>
    </div>
  `;
}

function getActionCapacityBucketNames(candidate, action, decision = getDecision(candidate)) {
  if (!isPromotionAction(action) && !decision.retireHostedRuleIds.length) return [];
  const surfaces = getActionAffectedSurfaces(candidate, action, decision);
  const reportNamesBySurface = Object.fromEntries(GUIDANCE_CAPACITY_BUCKETS.map((bucket) => [bucket.surface, bucket.reportName]));
  return [...new Set(surfaces.map((surface) => reportNamesBySurface[surface]).filter(Boolean))];
}

function getGuidanceCapacityProjection() {
  const reportsByName = Object.fromEntries(getCapacityReports().filter((report) => report.kind === "file").map((report) => [report.name, report]));
  const deltasByName = Object.fromEntries(GUIDANCE_CAPACITY_BUCKETS.map((bucket) => [bucket.reportName, 0]));
  getPlanCandidates().forEach((candidate) => {
    const decision = getDecision(candidate);
    const tokenDelta = getPlanTokenDelta(candidate);
    getActionCapacityBucketNames(candidate, decision.action, decision).forEach((reportName) => {
      deltasByName[reportName] += tokenDelta;
    });
  });
  const buckets = GUIDANCE_CAPACITY_BUCKETS.map((bucket) => {
    const report = reportsByName[bucket.reportName];
    return {
      ...bucket,
      currentGuardedTokens: report.guardedTokens,
      draftDeltaTokens: deltasByName[bucket.reportName],
      budgetTokens: report.budgetTokens
    };
  });
  const currentGuardedTokens = buckets.reduce((sum, bucket) => sum + bucket.currentGuardedTokens, 0);
  const draftDeltaTokens = buckets.reduce((sum, bucket) => sum + bucket.draftDeltaTokens, 0);
  const bucketNames = new Set(buckets.map((bucket) => bucket.reportName));
  const reservedTokens = getCapacityReports().filter((report) => report.kind === "file" && !bucketNames.has(report.name))
    .reduce((sum, report) => sum + report.guardedTokens, 0);
  const budgetTokens = Math.min(buckets.reduce((sum, bucket) => sum + bucket.budgetTokens, 0),
    state.bundle.guidanceCapacity.maximumGuidanceTokens - reservedTokens);
  return {
    buckets,
    currentGuardedTokens,
    draftDeltaTokens,
    budgetTokens,
    projectedGuardedTokens: currentGuardedTokens + draftDeltaTokens,
    projectedHeadroomTokens: budgetTokens - currentGuardedTokens - draftDeltaTokens
  };
}

function getProjectedCapacityDelta(report) {
  const paths = new Set(report.paths);
  const fileReports = new Map(getCapacityReports().filter((item) => item.kind === "file").map((item) => [item.name, item]));
  return getGuidanceCapacityProjection().buckets.reduce((sum, bucket) => {
    return fileReports.get(bucket.reportName).paths.some((path) => paths.has(path)) ? sum + bucket.draftDeltaTokens : sum;
  }, 0);
}

function renderPreview() {
  disconnectPreviewBodyVirtualizer();
  const readiness = getPreviewReadiness();
  const planCandidates = readiness.planCandidates;
  const ready = readiness.ready;
  const blocked = readiness.openRuleIssueCount > 0;
  const approvalState = blocked
    ? { text: "Blocked", kind: "error", badge: "Blocked by Rule Issues" }
    : ready
      ? { text: "Ready", kind: "success", badge: "Ready to export" }
      : { text: "Draft", kind: "warning", badge: "Not ready" };
  elements["approval-badge"].className = `ui-badge status-capsule status-badge ${approvalState.kind}`;
  elements["approval-badge"].textContent = approvalState.badge;
  workbenchStatusBar.update("promotionApproval", { text: approvalState.text, kind: approvalState.kind });
  renderApprovalRequirements(readiness);
  elements["approve-export-button"].disabled = !ready;
  previewFilesByScope = buildPreviewFiles(planCandidates);
  elements["preview-diff"].innerHTML = renderPreviewFiles(previewFilesByScope.proposed, "No Proposed Changes", "Add an available rule action to review its line-level diff.");
  elements["preview-payload-diff"].innerHTML = renderPreviewFiles(previewFilesByScope.payload, "No Payload Changes", "Add or update a Promotion Plan item to review its selection payload changes.");
  elements["preview-json"].innerHTML = planCandidates.some((candidate) => !getAssessment(candidate))
    ? renderPreviewEmptyState("warning", "Rebuild Assessment Missing", "The source display must contain a complete rebuild assessment before generating the resulting catalog.", "warning-state")
    : renderPreviewFiles(previewFilesByScope.raw, "No Resulting Catalog", "Add, update, or retire a Promotion Plan item to review the resulting catalog mutations.");
  elements["preview-protected"].innerHTML = previewFilesByScope.protected.map(renderPreviewFile).join("");
  elements["preview-protected-section"].hidden = previewFilesByScope.protected.length === 0;
  renderPreviewReview();
  initializePreviewBodyVirtualizer();
}

function buildPreviewFiles(candidates) {
  const proposed = candidates.flatMap((candidate) => {
    const decision = getDecision(candidate);
    const id = getEffectiveHostedRuleId(candidate);
    const files = isPromotionAction(decision.action) ? [createPreviewFile(
      `rules/${id}.md`, candidate.title,
      decision.action === "add" ? [] : splitDiffLines(getCurrentHostedText(candidate)),
      decision.action === "retire" ? [] : splitDiffLines(decision.proposedText),
      false, candidate.sourceId, "proposed"
    )] : [];
    for (const rule of getAncillaryRetirementRules(decision)) files.push(createPreviewFile(
      `rules/${rule.id}.md`, candidate.title, splitDiffLines(rule.text), [], false, candidate.sourceId, "proposed"
    ));
    return files;
  });
  const payload = candidates.map((candidate) => {
    const current = getDecision(candidate);
    const baseline = defaultDecision(candidate);
    const before = {
      action: baseline.action,
      inPlan: baseline.inPlan,
      planMembership: { source: baseline.planMembershipSource, bulkOperationId: baseline.bulkOperationId },
      rationale: baseline.rationale,
      proposedText: baseline.proposedText,
      retireHostedRuleIds: baseline.retireHostedRuleIds,
      proposedHostedRuleId: baseline.proposedHostedRuleId,
      applicabilityOverride: null
    };
    const after = {
      action: current.action,
      inPlan: current.inPlan,
      planMembership: { source: current.planMembershipSource, bulkOperationId: current.bulkOperationId },
      rationale: current.rationale,
      proposedText: current.proposedText,
      retireHostedRuleIds: current.retireHostedRuleIds,
      proposedHostedRuleId: current.proposedHostedRuleId,
      applicabilityOverride: getApplicabilityOverride(candidate)
    };
    const changedKeys = Object.keys(after).filter((key) => JSON.stringify(before[key]) !== JSON.stringify(after[key]));
    if (!changedKeys.length) return null;
    const changedBefore = Object.fromEntries(changedKeys.map((key) => [key, before[key]]));
    const changedAfter = Object.fromEntries(changedKeys.map((key) => [key, after[key]]));
    return createPreviewFile(`selection/${getEffectiveHostedRuleId(candidate)}.json`, candidate.title, JSON.stringify(changedBefore, null, 2).split("\n"), JSON.stringify(changedAfter, null, 2).split("\n"), false, "", "payload");
  }).filter(Boolean);
  const requiresAssessment = candidates.some((candidate) => !getAssessment(candidate));
  const proposedPayload = requiresAssessment ? null : buildApprovedRules();
  const currentPayload = proposedPayload ? { ...structuredClone(proposedPayload), mutations: [] } : null;
  const raw = proposedPayload?.mutations.length
    ? [createPreviewFile("approval/approved-rules.json", "Approved catalog mutations", JSON.stringify(currentPayload, null, 2).split("\n"), JSON.stringify(proposedPayload, null, 2).split("\n"), true, "", "raw")]
    : [];
  const protectedFiles = state.bundle.catalog.protectedRuleFiles.map((file) => {
    const lines = splitDiffLines(file.content);
    return {
      ...createPreviewFile(file.path, `${capitalize(file.surfaceId)} protected instructions`, lines, lines, false, "", "protected"),
      reference: true,
      content: file.content
    };
  });
  return { proposed, payload, raw, protected: protectedFiles };
}

function copyCatalogRule(rule) {
  return Object.fromEntries(["id", "origin", "status", "text", "provenance", "evidenceIds", "implementationModels", "documentationGap", "retirementReason", "lastPlacement", "selectionFactors", "selectionRationale"]
    .filter((property) => rule?.[property] !== undefined)
    .map((property) => [property, structuredClone(rule[property])]));
}

function buildApprovedMutation(candidate) {
  const decision = getDecision(candidate);
  const assessment = getAssessment(candidate, decision);
  if (!assessment) throw new Error("A current complete assessment is required before building approved rule mutations");
  const recommendation = candidate.recommendation;
  const existingRule = getCatalogStatus(candidate).rules[0] || null;
  const placement = { surfaceId: recommendation.category, sectionHeading: recommendation.placement };
  let rule;
  let placements;
  let canonicalCandidate;
  if (decision.action === "add") {
    rule = {
      id: getEffectiveHostedRuleId(candidate),
      origin: "hosted-catalog-addition",
      status: "active",
      text: decision.proposedText,
      provenance: [...recommendation.provenance],
      evidenceIds: [...recommendation.evidenceIds],
      ...(recommendation.category === "implementation" ? { implementationModels: [...decision.implementationModels] } : {}),
      selectionFactors: { scoringStatus: "scored", ...assessment.factors },
      selectionRationale: assessment.rationale
    };
    placements = [placement];
    canonicalCandidate = {
      sourceDefinitionId: candidate.sourceType === "upstream" ? "contributor-guidance" : candidate.sourceType === "interactive" ? "interactive-toolkit" : "maintainer-proposals",
      sourceId: candidate.sourceId,
      assessmentId: candidate.assessment.assessmentId
    };
  }
  else if (decision.action === "update") {
    rule = {
      ...copyCatalogRule(existingRule),
      status: "active",
      text: decision.proposedText,
      provenance: [...new Set([...(existingRule.provenance || []), ...recommendation.provenance])],
      evidenceIds: [...new Set([...(existingRule.evidenceIds || []), ...recommendation.evidenceIds])],
      ...(recommendation.category === "implementation" ? { implementationModels: [...decision.implementationModels] } : {}),
      selectionFactors: { scoringStatus: "scored", ...assessment.factors },
      selectionRationale: assessment.rationale
    };
    delete rule.retirementReason;
    delete rule.lastPlacement;
    placements = [placement];
    canonicalCandidate = structuredClone(existingRule.canonicalCandidate);
  }
  else if (decision.action === "retire") {
    rule = {
      ...copyCatalogRule(existingRule),
      status: "retired",
      retirementReason: decision.rationale.trim(),
      lastPlacement: existingRule.placements[0]
    };
    placements = [];
    canonicalCandidate = structuredClone(existingRule.canonicalCandidate);
  }
  else if (decision.action === "restore") {
    rule = {
      ...copyCatalogRule(existingRule),
      status: "active"
    };
    delete rule.retirementReason;
    delete rule.lastPlacement;
    placements = [placement];
    canonicalCandidate = structuredClone(existingRule.canonicalCandidate);
  }
  else {
    throw new Error(`Unsupported approved mutation action: ${decision.action}`);
  }
  return {
    action: decision.action,
    rationale: decision.rationale.trim(),
    rule,
    canonicalCandidate,
    placements,
    sourceRelationships: structuredClone(recommendation.sourceRelationships)
  };
}

function buildAncillaryRetirementMutation(candidate, existingRule) {
  const decision = getDecision(candidate);
  return {
    action: "retire",
    rationale: decision.rationale.trim(),
    rule: {
      ...copyCatalogRule(existingRule),
      status: "retired",
      retirementReason: decision.rationale.trim(),
      lastPlacement: existingRule.placements[0]
    },
    canonicalCandidate: structuredClone(existingRule.canonicalCandidate),
    placements: [],
    sourceRelationships: structuredClone(candidate.recommendation.sourceRelationships)
  };
}

function buildApprovedMutations(candidate) {
  const decision = getDecision(candidate);
  const mutations = isPromotionAction(decision.action) ? [buildApprovedMutation(candidate)] : [];
  getAncillaryRetirementRules(decision).forEach((rule) => mutations.push(buildAncillaryRetirementMutation(candidate, rule)));
  return mutations;
}

function createPreviewFile(path, title, beforeLines, afterLines, contextual = false, sourceId = "", scope = "") {
  const rows = alignPreviewLines(beforeLines, afterLines);
  return {
    path,
    displayPath: scope ? `${PREVIEW_SCOPE_LABELS[scope].toUpperCase()}/${path.split("/").at(-1)}` : path,
    title,
    sourceId,
    rows,
    contextual,
    beforeLineCount: beforeLines.length,
    afterLineCount: afterLines.length,
    additions: rows.filter((row) => row.changed && row.newText !== undefined).length,
    deletions: rows.filter((row) => row.changed && row.oldText !== undefined).length
  };
}

function alignPreviewLines(beforeLines, afterLines) {
  const rows = [];
  let beforeIndex = 0;
  let afterIndex = 0;
  let beforeLine = 1;
  let afterLine = 1;
  const lookahead = 300;
  const appendChanges = (before, after) => {
    const count = Math.max(before.length, after.length);
    for (let index = 0; index < count; index += 1) {
      rows.push({ changed: before[index] !== after[index], oldText: before[index], oldLine: before[index] === undefined ? undefined : beforeLine++, newText: after[index], newLine: after[index] === undefined ? undefined : afterLine++ });
    }
  };
  while (beforeIndex < beforeLines.length || afterIndex < afterLines.length) {
    if (beforeIndex < beforeLines.length && afterIndex < afterLines.length && beforeLines[beforeIndex] === afterLines[afterIndex]) {
      rows.push({ changed: false, oldText: beforeLines[beforeIndex], oldLine: beforeLine++, newText: afterLines[afterIndex], newLine: afterLine++ });
      beforeIndex += 1;
      afterIndex += 1;
      continue;
    }
    let match = null;
    const beforeLimit = Math.min(lookahead, beforeLines.length - beforeIndex);
    const afterLimit = Math.min(lookahead, afterLines.length - afterIndex);
    for (let distance = 1; distance <= beforeLimit + afterLimit && !match; distance += 1) {
      for (let beforeOffset = 0; beforeOffset <= Math.min(distance, beforeLimit); beforeOffset += 1) {
        const afterOffset = distance - beforeOffset;
        if (afterOffset > afterLimit || beforeLines[beforeIndex + beforeOffset] !== afterLines[afterIndex + afterOffset]) continue;
        const nextMatches = beforeLines[beforeIndex + beforeOffset + 1] === afterLines[afterIndex + afterOffset + 1]
          || beforeIndex + beforeOffset + 1 >= beforeLines.length
          || afterIndex + afterOffset + 1 >= afterLines.length;
        if (nextMatches) {
          match = { beforeOffset, afterOffset };
          break;
        }
      }
    }
    if (!match) {
      appendChanges(beforeLines.slice(beforeIndex), afterLines.slice(afterIndex));
      break;
    }
    appendChanges(beforeLines.slice(beforeIndex, beforeIndex + match.beforeOffset), afterLines.slice(afterIndex, afterIndex + match.afterOffset));
    beforeIndex += match.beforeOffset;
    afterIndex += match.afterOffset;
  }
  return rows;
}

function renderPreviewFiles(files, emptyTitle, emptyMessage) {
  if (!files.length) return renderPreviewEmptyState("diff", emptyTitle, emptyMessage);
  return files.map(renderPreviewFile).join("");
}

function renderPreviewFile(file) {
  if (file.reference) return renderPreviewReferenceFile(file);
  const rows = file.contextual ? createContextualPreviewRows(file.rows) : file.rows.map((row) => ({ type: "line", row }));
  const topHunk = file.contextual ? "" : renderPreviewTopHunk(file);
  const hasContextGaps = rows.some((row) => row.type === "gap");
  return `
    <section class="preview-review-file${file.path === previewSelectedFilePath ? " selected" : ""}" data-preview-file-path="${escapeHtml(file.path)}" data-preview-file-display-path="${escapeHtml(file.displayPath)}" ${file.sourceId ? `data-preview-source-id="${escapeHtml(file.sourceId)}"` : ""}>
      <div class="preview-file-heading-wrapper">
        <div class="preview-file-heading">
          <button class="preview-icon-button clickable" type="button" data-preview-file-collapse aria-label="Collapse ${escapeHtml(file.displayPath)}" aria-expanded="true">${octicon("chevron-down")}</button>
          <svg class="octicon preview-review-status-icon" aria-label="Owned by CODEOWNERS"><use href="icons/octicons/sprite.svg#octicon-shield-lock-16"></use></svg>
          <code class="preview-file-path">${escapeHtml(file.displayPath)}</code>
          <button class="preview-icon-button clickable" type="button" data-preview-copy-path="${escapeHtml(file.displayPath)}" aria-label="Copy ${escapeHtml(file.displayPath)} path" data-workbench-tooltip="Copy path">${octicon("copy")}</button>
          ${hasContextGaps ? `<button class="preview-icon-button clickable" type="button" data-preview-lines-toggle aria-label="Expand all lines: ${escapeHtml(file.displayPath)}" aria-pressed="false" data-workbench-tooltip="Expand all lines">${octicon("unfold")}</button>` : ""}
          <div class="preview-file-actions">
            <span class="preview-change-summary"><b>+${file.additions}</b><i>-${file.deletions}</i></span>
            ${renderPreviewDiffStat(file.additions, file.deletions)}
            <label class="preview-viewed clickable" aria-label="Not Viewed" aria-pressed="false">
              <input type="checkbox" data-preview-viewed>
              ${octicon("square")}
              ${octicon("checkbox-fill")}
              <span>Viewed</span>
            </label>
          </div>
        </div>
      </div>
      <div class="preview-file-body"><div class="preview-contextual-diff">${topHunk}${rows.map(renderPreviewDiffRow).join("")}</div></div>
    </section>
  `;
}

function renderPreviewReferenceFile(file) {
  const lines = splitDiffLines(file.content);
  return `
    <section class="preview-review-file preview-reference-file${file.path === previewSelectedFilePath ? " selected" : ""}" data-preview-file-path="${escapeHtml(file.path)}" data-preview-file-display-path="${escapeHtml(file.displayPath)}">
      <div class="preview-file-heading-wrapper">
        <div class="preview-file-heading">
          <button class="preview-icon-button clickable" type="button" data-preview-file-collapse aria-label="Collapse ${escapeHtml(file.displayPath)}" aria-expanded="true">${octicon("chevron-down")}</button>
          <svg class="octicon preview-review-status-icon protected" aria-label="Protected"><use href="icons/octicons/sprite.svg#octicon-shield-lock-16"></use></svg>
          <code class="preview-file-path">${escapeHtml(file.displayPath)}</code>
          <button class="preview-icon-button clickable" type="button" data-preview-copy-path="${escapeHtml(file.displayPath)}" aria-label="Copy ${escapeHtml(file.displayPath)} path" data-workbench-tooltip="Copy path">${octicon("copy")}</button>
          <div class="preview-file-actions"><span class="ui-badge status-capsule preview-reference-status">${icon("lock")}Protected</span></div>
        </div>
      </div>
      <div class="preview-file-body"><div class="preview-reference-content preview-reference-lines">${lines.map((line, index) => `<div class="preview-reference-row"><span class="preview-reference-line-number" aria-hidden="true">${index + 1}</span><code>${line ? escapeHtml(line) : " "}</code></div>`).join("")}</div></div>
    </section>
  `;
}

function hydratePreviewFileBody(file) {
  const body = file.querySelector(".preview-file-body");
  const entry = previewBodyVirtualizer?.cache.get(file.dataset.previewFilePath);
  if (!body || !entry || body.dataset.previewVirtualized !== "true") return;
  body.innerHTML = entry.html;
  body.style.height = "";
  delete body.dataset.previewVirtualized;
  body.removeAttribute("aria-hidden");
}

function virtualizePreviewFileBody(file) {
  const body = file.querySelector(".preview-file-body");
  const entry = previewBodyVirtualizer?.cache.get(file.dataset.previewFilePath);
  if (!body || !entry || body.dataset.previewVirtualized === "true") return;
  if (!body.hidden) {
    entry.html = body.innerHTML;
    entry.height = body.getBoundingClientRect().height;
  }
  body.replaceChildren();
  body.style.height = `${entry.height}px`;
  body.dataset.previewVirtualized = "true";
  body.setAttribute("aria-hidden", "true");
}

function disconnectPreviewBodyVirtualizer(hydrate = false) {
  clearTimeout(previewVirtualizationResizeTimer);
  if (!previewBodyVirtualizer) return;
  previewBodyVirtualizer.observer.disconnect();
  if (hydrate) previewBodyVirtualizer.files.forEach(hydratePreviewFileBody);
  previewBodyVirtualizer = null;
}

function initializePreviewBodyVirtualizer() {
  disconnectPreviewBodyVirtualizer();
  const scroller = elements["preview-code"];
  const files = [...scroller.querySelectorAll("[data-preview-file-path]")];
  if (!files.length || typeof IntersectionObserver !== "function") return;
  const cache = new Map(files.map((file) => {
    const body = file.querySelector(".preview-file-body");
    return [file.dataset.previewFilePath, { html: body.innerHTML, height: body.getBoundingClientRect().height }];
  }));
  const margin = scroller.clientHeight * PREVIEW_VIRTUALIZATION_BUFFER_VIEWPORTS;
  const viewport = scroller.getBoundingClientRect();
  previewBodyVirtualizer = { cache, files, observer: null };
  files.forEach((file) => {
    const rect = file.getBoundingClientRect();
    if (rect.bottom < viewport.top - margin || rect.top > viewport.bottom + margin) virtualizePreviewFileBody(file);
  });
  const observer = new IntersectionObserver((entries) => {
    entries.forEach((entry) => {
      const body = entry.target.querySelector(".preview-file-body");
      if (entry.isIntersecting && !body.hidden) hydratePreviewFileBody(entry.target);
      else if (!entry.isIntersecting) virtualizePreviewFileBody(entry.target);
    });
  }, { root: scroller, rootMargin: `${margin}px 0px` });
  previewBodyVirtualizer.observer = observer;
  files.forEach((file) => observer.observe(file));
}

function refreshPreviewBodyVirtualizer() {
  if (!previewBodyVirtualizer) return;
  const files = previewBodyVirtualizer.files;
  previewBodyVirtualizer.observer.disconnect();
  files.forEach(hydratePreviewFileBody);
  previewBodyVirtualizer = null;
  requestAnimationFrame(initializePreviewBodyVirtualizer);
}

function schedulePreviewBodyVirtualizerRefresh() {
  clearTimeout(previewVirtualizationResizeTimer);
  previewVirtualizationResizeTimer = setTimeout(refreshPreviewBodyVirtualizer, 100);
}

function renderPreviewTopHunk(file) {
  const beforeRange = file.beforeLineCount ? `1,${file.beforeLineCount}` : "0,0";
  const afterRange = file.afterLineCount ? `1,${file.afterLineCount}` : "0,0";
  return `<div class="preview-hunk-header"><span>${octicon("kebab-horizontal")}</span><code>@@ -${beforeRange} +${afterRange} @@</code></div>`;
}

function renderPreviewDiffStat(additions, deletions) {
  const total = Math.max(1, additions + deletions);
  const additionBlocks = Math.floor(5 * additions / total);
  const deletionBlocks = Math.floor(5 * deletions / total);
  return `<span class="preview-diff-stat" aria-label="${additions} additions and ${deletions} deletions">${Array.from({ length: 5 }, (_, index) => `<i class="${index < additionBlocks ? "add" : index < additionBlocks + deletionBlocks ? "delete" : "neutral"}"></i>`).join("")}</span>`;
}

function createContextualPreviewRows(rows) {
  const visible = new Set();
  rows.forEach((row, index) => {
    if (!row.changed) return;
    for (let offset = -PREVIEW_CONTEXT_LINE_COUNT; offset <= PREVIEW_CONTEXT_LINE_COUNT; offset += 1) {
      if (index + offset >= 0 && index + offset < rows.length) visible.add(index + offset);
    }
  });
  const rendered = [];
  let index = 0;
  while (index < rows.length) {
    if (rows[index].changed || visible.has(index)) {
      rendered.push({ type: "line", row: rows[index] });
      index += 1;
      continue;
    }
    const start = index;
    while (index < rows.length && !rows[index].changed && !visible.has(index)) index += 1;
    rendered.push({ type: "gap", direction: start === 0 ? "up" : index === rows.length ? "down" : "all", rows: rows.slice(start, index) });
  }
  return rendered;
}

function renderPreviewDiffRow(item) {
  if (item.type === "gap") return renderPreviewContextGap(item);
  const row = item.row;
  return `<div class="preview-split-row ${row.changed ? "changed" : "context"}">${renderPreviewDiffCell(row.oldText, row.oldLine, row.changed ? "delete" : "context")}${renderPreviewDiffCell(row.newText, row.newLine, row.changed ? "add" : "context")}</div>`;
}

function renderPreviewDiffCell(text, line, type) {
  if (text === undefined) return '<div class="preview-diff-cell empty"></div>';
  const marker = type === "add" ? "+" : type === "delete" ? "-" : "";
  return `<div class="preview-diff-cell ${type}"><span class="preview-line-number">${line}</span><span class="preview-line-marker" aria-hidden="true">${marker}</span><code>${escapeHtml(text)}</code></div>`;
}

function renderPreviewContextGap(gap) {
  const iconName = gap.direction === "up" ? "fold-up" : gap.direction === "down" ? "fold-down" : "unfold";
  const label = gap.direction === "up" ? "Expand Up" : gap.direction === "down" ? "Expand Down" : "Expand All";
  return `<div class="preview-context-gap" data-preview-context-gap><button class="preview-context-expand clickable" type="button" data-preview-context-direction="${gap.direction}" aria-label="${label}" data-workbench-tooltip="${label} (${gap.rows.length} hidden lines)">${octicon(iconName)}</button><code>@@ -${gap.rows[0]?.oldLine || 0},${gap.rows.length} +${gap.rows[0]?.newLine || 0},${gap.rows.length} @@</code><template>${gap.rows.map((row) => renderPreviewDiffRow({ type: "line", row })).join("")}</template></div>`;
}

function renderPreviewReview() {
  const files = Object.values(previewFilesByScope).flat();
  const changedFiles = files.filter((file) => !file.reference);
  const additions = changedFiles.reduce((sum, file) => sum + file.additions, 0);
  const deletions = changedFiles.reduce((sum, file) => sum + file.deletions, 0);
  elements["preview-review-context"].innerHTML = `<strong>${changedFiles.length} file${changedFiles.length === 1 ? "" : "s"} changed</strong><span class="preview-change-summary"><b>+${additions}</b><i>-${deletions}</i></span>${renderPreviewDiffStat(additions, deletions)}`;
  document.querySelectorAll(".preview-proposed-review, .payload-review, .preview-raw-payload").forEach((section) => {
    section.hidden = false;
  });
  elements["preview-protected-section"].hidden = previewFilesByScope.protected.length === 0;
  if (!files.some((file) => file.path === previewSelectedFilePath)) previewSelectedFilePath = files[0]?.path || "";
  renderPreviewFileTree();
  updatePreviewSelectedFile();
}

function renderPreviewFileTree() {
  const groups = Object.entries(previewFilesByScope).map(([scope, files]) => renderPreviewArtifactGroup(scope, files)).join("");
  let tree = elements["preview-summary"].querySelector(".preview-artifact-tree");
  if (!tree) {
    elements["preview-summary"].innerHTML = `<label class="preview-file-filter">${icon("search")}<input class="editable-text" type="search" placeholder="Filter preview files" aria-label="Filter preview files"></label><nav class="preview-artifact-tree" aria-label="Review artifacts"></nav>`;
    tree = elements["preview-summary"].querySelector(".preview-artifact-tree");
  }
  tree.innerHTML = groups;
  applyPreviewFileFilter(elements["preview-summary"].querySelector('.preview-file-filter input')?.value || "");
}

function renderPreviewIconBuffer(closedName, openName, expanded, className) {
  for (const name of [closedName, openName]) {
    if (!/^[a-z0-9-]+$/.test(name)) throw new Error(`Invalid Octicon name: ${name}`);
  }
  return `<span class="preview-icon-buffer ${escapeHtml(className)}" data-state="${expanded ? "open" : "closed"}" aria-hidden="true"><svg class="octicon buffer-closed"><use href="icons/octicons/sprite.svg#octicon-${closedName}-16"></use></svg><svg class="octicon buffer-open"><use href="icons/octicons/sprite.svg#octicon-${openName}-16"></use></svg></span>`;
}

function renderPreviewArtifactGroup(scope, files) {
  if (!files.length) return "";
  const expanded = previewExpandedScopes.has(scope);
  const children = files.map((file) => renderPreviewTreeFile(scope, { ...file, name: file.path.split("/").at(-1) })).join("");
  return `
    <section class="preview-artifact-group" data-preview-artifact-group="${escapeHtml(scope)}">
      <button class="preview-artifact-parent clickable" type="button" data-preview-artifact-scope="${escapeHtml(scope)}" aria-expanded="${expanded}">${renderPreviewIconBuffer("chevron-right", "chevron-down", expanded, "preview-chevron-buffer")}${renderPreviewIconBuffer("file-directory-fill", "file-directory-open-fill", expanded, "preview-folder-buffer")}<span class="preview-artifact-label">${escapeHtml(PREVIEW_SCOPE_LABELS[scope])}</span></button>
      <div class="preview-artifact-children" ${expanded ? "" : "hidden"}>${children}</div>
    </section>
  `;
}

function renderPreviewTreeFile(scope, file) {
  if (file.reference) {
    return `<button class="preview-file-tree-item clickable ${file.path === previewSelectedFilePath ? "active" : ""}" type="button" data-preview-artifact-file-scope="${escapeHtml(scope)}" data-preview-file-jump="${escapeHtml(file.path)}" data-workbench-tooltip="${escapeHtml(file.path)}"><svg class="octicon preview-tree-file-icon protected" aria-label="Protected"><use href="icons/octicons/sprite.svg#octicon-shield-lock-16"></use></svg><span>${escapeHtml(file.name)}</span></button>`;
  }
  const status = file.additions > 0 && file.deletions === 0 ? "added" : file.deletions > 0 && file.additions === 0 ? "removed" : "modified";
  const iconName = status === "modified" ? "file-diff" : `file-${status}`;
  const label = status[0].toUpperCase() + status.slice(1);
  return `<button class="preview-file-tree-item clickable ${file.path === previewSelectedFilePath ? "active" : ""}" type="button" data-preview-artifact-file-scope="${escapeHtml(scope)}" data-preview-file-jump="${escapeHtml(file.path)}" data-workbench-tooltip="${escapeHtml(file.path)}"><svg class="octicon preview-tree-file-icon ${status}" aria-label="${label}"><use href="icons/octicons/sprite.svg#octicon-${iconName}-16"></use></svg><span>${escapeHtml(file.name)}</span></button>`;
}

function updatePreviewSelectedFile() {
  elements["preview-code"].querySelectorAll("[data-preview-file-path]").forEach((file) => {
    file.classList.toggle("selected", file.dataset.previewFilePath === previewSelectedFilePath);
  });
}

function applyPreviewFileFilter(value) {
  const query = String(value || "").trim().toLowerCase();
  elements["preview-summary"].querySelectorAll("[data-preview-file-jump]").forEach((button) => {
    button.hidden = !button.dataset.previewFileJump.toLowerCase().includes(query);
  });
  elements["preview-summary"].querySelectorAll(".preview-artifact-group").forEach((group) => {
    const hasMatches = [...group.querySelectorAll("[data-preview-file-jump]")].some((button) => !button.hidden);
    group.hidden = Boolean(query) && !hasMatches;
    group.querySelector(".preview-artifact-children").hidden = !hasMatches || (!query && !previewExpandedScopes.has(group.dataset.previewArtifactGroup));
  });
}

function handlePreviewFileFilter(event) {
  if (!event.target.matches('input[type="search"]')) return;
  applyPreviewFileFilter(event.target.value);
}

function handlePreviewFileNavigation(event) {
  const parent = event.target.closest("[data-preview-artifact-scope]");
  if (parent) {
    const scope = parent.dataset.previewArtifactScope;
    if (previewExpandedScopes.has(scope)) previewExpandedScopes.delete(scope);
    else previewExpandedScopes.add(scope);
    requestAnimationFrame(() => {
      const expanded = previewExpandedScopes.has(scope);
      parent.setAttribute("aria-expanded", String(expanded));
      parent.querySelectorAll(".preview-icon-buffer").forEach((buffer) => {
        buffer.dataset.state = expanded ? "open" : "closed";
      });
      parent.closest(".preview-artifact-group").querySelector(".preview-artifact-children").hidden = !expanded;
    });
    return;
  }
  const button = event.target.closest("[data-preview-file-jump]");
  if (!button) return;
  const path = button.dataset.previewFileJump;
  const file = elements["preview-code"].querySelector(`[data-preview-file-path="${CSS.escape(path)}"]`);
  if (!file) return;
  hydratePreviewFileBody(file);
  previewSelectedFilePath = path;
  updatePreviewSelectedFile();
  file.scrollIntoView({ block: "start", behavior: "auto" });
  elements["preview-summary"].querySelectorAll("[data-preview-file-jump]").forEach((item) => item.classList.toggle("active", item === button));
}

function setPreviewTreeWidth(value) {
  const layout = elements["preview-tree-resizer"].parentElement;
  const availableMaximum = layout.clientWidth > 0 ? layout.clientWidth - 640 - 16 : PREVIEW_TREE_MAX_WIDTH;
  const maximum = Math.max(PREVIEW_TREE_MIN_WIDTH, Math.min(PREVIEW_TREE_MAX_WIDTH, availableMaximum));
  const width = Math.round(Math.max(PREVIEW_TREE_MIN_WIDTH, Math.min(maximum, value || PREVIEW_TREE_DEFAULT_WIDTH)));
  layout.style.setProperty("--preview-tree-width", `${width}px`);
  elements["preview-tree-resizer"].setAttribute("aria-valuemax", String(maximum));
  elements["preview-tree-resizer"].setAttribute("aria-valuenow", String(width));
  elements["preview-tree-resizer"].setAttribute("aria-valuetext", `Pane width ${width} pixels`);
}

function handlePreviewTreeResizeStart(event) {
  previewTreeResizePointerId = event.pointerId;
  elements["preview-tree-resizer"].setPointerCapture(event.pointerId);
  elements["preview-tree-resizer"].parentElement.classList.add("preview-tree-resizing");
  event.preventDefault();
}

function handlePreviewTreeResizeMove(event) {
  if (event.pointerId !== previewTreeResizePointerId) return;
  const layout = elements["preview-tree-resizer"].parentElement;
  setPreviewTreeWidth(event.clientX - layout.getBoundingClientRect().left);
}

function handlePreviewTreeResizeEnd(event) {
  if (event.pointerId !== previewTreeResizePointerId) return;
  if (elements["preview-tree-resizer"].hasPointerCapture(event.pointerId)) elements["preview-tree-resizer"].releasePointerCapture(event.pointerId);
  previewTreeResizePointerId = null;
  elements["preview-tree-resizer"].parentElement.classList.remove("preview-tree-resizing");
  refreshPreviewBodyVirtualizer();
}

function handlePreviewTreeResizeKeyboard(event) {
  if (!["ArrowLeft", "ArrowRight", "Home", "End"].includes(event.key)) return;
  event.preventDefault();
  const current = Number(elements["preview-tree-resizer"].getAttribute("aria-valuenow"));
  const value = event.key === "Home"
    ? PREVIEW_TREE_MIN_WIDTH
    : event.key === "End"
      ? PREVIEW_TREE_MAX_WIDTH
      : current + (event.key === "ArrowLeft" ? -PREVIEW_TREE_KEYBOARD_STEP : PREVIEW_TREE_KEYBOARD_STEP);
  setPreviewTreeWidth(value);
  refreshPreviewBodyVirtualizer();
}

function setPreviewFileCollapsed(file, collapsed) {
  const body = file.querySelector(".preview-file-body");
  const toggle = file.querySelector("[data-preview-file-collapse]");
  if (!collapsed) hydratePreviewFileBody(file);
  body.hidden = collapsed;
  toggle.setAttribute("aria-expanded", String(!collapsed));
  toggle.setAttribute("aria-label", `${collapsed ? "Expand" : "Collapse"} ${file.dataset.previewFileDisplayPath}`);
  toggle.innerHTML = octicon(`chevron-${collapsed ? "right" : "down"}`);
}

function setPreviewLinesExpanded(file, expanded) {
  const toggle = file.querySelector("[data-preview-lines-toggle]");
  if (!toggle) return;
  const action = expanded ? "Collapse all lines" : "Expand all lines";
  toggle.dataset.previewLinesExpanded = String(expanded);
  toggle.setAttribute("aria-label", `${action}: ${file.dataset.previewFileDisplayPath}`);
  toggle.setAttribute("aria-pressed", String(expanded));
  setWorkbenchTooltip(toggle, action);
  toggle.innerHTML = octicon(expanded ? "fold" : "unfold");
}

function expandAllPreviewLines(file) {
  file.querySelectorAll("[data-preview-context-gap]").forEach((gap) => {
    const fragment = document.createDocumentFragment();
    [...gap.querySelector("template").content.children].forEach((row) => fragment.appendChild(row));
    gap.before(fragment);
    gap.remove();
  });
  setPreviewLinesExpanded(file, true);
}

function collapseAllPreviewLines(file) {
  const previewFile = Object.values(previewFilesByScope).flat().find((item) => item.path === file.dataset.previewFilePath);
  if (!previewFile) return;
  const rows = createContextualPreviewRows(previewFile.rows);
  file.querySelector(".preview-contextual-diff").innerHTML = rows.map(renderPreviewDiffRow).join("");
  setPreviewLinesExpanded(file, false);
}

function handlePreviewReviewOutsideInteraction(event) {
  const popover = elements["preview-review-popover"];
  if (popover.hidden || popover.contains(event.target) || elements["preview-review-toggle"].contains(event.target)) return;
  if (event.type === "wheel" && (event.ctrlKey || (!event.deltaX && !event.deltaY))) return;
  if (event.type === "touchmove" && event.touches.length !== 1) return;
  if (event.type === "keydown") {
    const scrollKeys = ["ArrowUp", "ArrowDown", "ArrowLeft", "ArrowRight", "PageUp", "PageDown", "Home", "End", " "];
    if (!scrollKeys.includes(event.key) || event.ctrlKey || event.metaKey || event.altKey
      || event.target.closest("input, textarea, select, button, a, [contenteditable]:not([contenteditable='false'])")) return;
  }
  popover.hidden = true;
  hideStatusTooltip();
}

async function handlePreviewReviewClick(event) {
  const requirement = event.target.closest("[data-approval-target]");
  if (requirement) {
    await navigateApprovalRequirement(requirement.dataset.approvalTarget);
    return;
  }
  if (event.target.closest("#preview-review-toggle")) {
    elements["preview-review-popover"].hidden = !elements["preview-review-popover"].hidden;
    return;
  }
  if (event.target.closest("#preview-review-close")) {
    elements["preview-review-popover"].hidden = true;
    return;
  }
  const collapse = event.target.closest("[data-preview-file-collapse]");
  if (collapse) {
    const file = collapse.closest("[data-preview-file-path]");
    setPreviewFileCollapsed(file, !file.querySelector(".preview-file-body").hidden);
    return;
  }
  const copyPath = event.target.closest("[data-preview-copy-path]");
  if (copyPath) {
    await navigator.clipboard.writeText(copyPath.dataset.previewCopyPath);
    showToast("File path copied");
    return;
  }
  const linesToggle = event.target.closest("[data-preview-lines-toggle]");
  if (linesToggle) {
    const file = linesToggle.closest("[data-preview-file-path]");
    if (linesToggle.dataset.previewLinesExpanded === "true") collapseAllPreviewLines(file);
    else expandAllPreviewLines(file);
    return;
  }
  const expand = event.target.closest("[data-preview-context-direction]");
  if (!expand) return;
  const gap = expand.closest("[data-preview-context-gap]");
  const file = gap.closest("[data-preview-file-path]");
  const rows = [...gap.querySelector("template").content.children];
  const direction = expand.dataset.previewContextDirection;
  const selectedRows = direction === "all" ? rows : direction === "up" ? rows.slice(-PREVIEW_DIRECTIONAL_EXPAND_COUNT) : rows.slice(0, PREVIEW_DIRECTIONAL_EXPAND_COUNT);
  const fragment = document.createDocumentFragment();
  selectedRows.forEach((row) => fragment.appendChild(row));
  if (direction === "up") gap.after(fragment);
  else gap.before(fragment);
  updatePreviewContextGap(gap);
  setPreviewLinesExpanded(file, true);
}

function updatePreviewContextGap(gap) {
  const rows = [...gap.querySelector("template").content.children];
  if (!rows.length) {
    gap.remove();
    return;
  }
  const firstOld = rows[0].querySelector(".preview-diff-cell:first-child .preview-line-number")?.textContent || "0";
  const firstNew = rows[0].querySelector(".preview-diff-cell:last-child .preview-line-number")?.textContent || "0";
  gap.querySelector(":scope > code").textContent = `@@ -${firstOld},${rows.length} +${firstNew},${rows.length} @@`;
  const button = gap.querySelector("[data-preview-context-direction]");
  button.dataset.workbenchTooltip = `${button.getAttribute("aria-label")} (${rows.length} hidden lines)`;
}

function handlePreviewReviewChange(event) {
  const viewed = event.target.closest("[data-preview-viewed]");
  if (!viewed) return;
  const file = viewed.closest("[data-preview-file-path]");
  const control = viewed.closest(".preview-viewed");
  file.classList.toggle("viewed", viewed.checked);
  control.setAttribute("aria-label", viewed.checked ? "Viewed" : "Not Viewed");
  control.setAttribute("aria-pressed", String(viewed.checked));
  if (viewed.checked && !file.querySelector(".preview-file-body").hidden) setPreviewFileCollapsed(file, true);
}

function splitDiffLines(text) {
  const normalized = String(text || "").replace(/\r\n/g, "\n");
  return normalized ? normalized.split("\n") : [];
}

function diffTextLines(beforeText, afterText) {
  const before = splitDiffLines(beforeText);
  const after = splitDiffLines(afterText);
  const lengths = Array.from({ length: before.length + 1 }, () => Array(after.length + 1).fill(0));
  for (let beforeIndex = before.length - 1; beforeIndex >= 0; beforeIndex -= 1) {
    for (let afterIndex = after.length - 1; afterIndex >= 0; afterIndex -= 1) {
      lengths[beforeIndex][afterIndex] = before[beforeIndex] === after[afterIndex]
        ? lengths[beforeIndex + 1][afterIndex + 1] + 1
        : Math.max(lengths[beforeIndex + 1][afterIndex], lengths[beforeIndex][afterIndex + 1]);
    }
  }
  const lines = [];
  let beforeIndex = 0;
  let afterIndex = 0;
  while (beforeIndex < before.length && afterIndex < after.length) {
    if (before[beforeIndex] === after[afterIndex]) {
      lines.push({ type: "context", text: before[beforeIndex] });
      beforeIndex += 1;
      afterIndex += 1;
    }
    else if (lengths[beforeIndex + 1][afterIndex] >= lengths[beforeIndex][afterIndex + 1]) {
      lines.push({ type: "delete", text: before[beforeIndex] });
      beforeIndex += 1;
    }
    else {
      lines.push({ type: "add", text: after[afterIndex] });
      afterIndex += 1;
    }
  }
  while (beforeIndex < before.length) lines.push({ type: "delete", text: before[beforeIndex++] });
  while (afterIndex < after.length) lines.push({ type: "add", text: after[afterIndex++] });
  return lines;
}

function getUnsavedApprovalEditor() {
  const candidate = getActiveCandidate();
  const editor = elements["assessment-panel"].querySelector('[data-decision-field="proposedText"]');
  return candidate && editor && editor.value !== getDecision(candidate).proposedText ? { candidate, editor } : null;
}

function getCandidateMutationRuleIds(candidate) {
  const decision = getDecision(candidate);
  return [...(isPromotionAction(decision.action) ? [getEffectiveHostedRuleId(candidate)] : []), ...getAncillaryRetirementRules(decision).map((rule) => rule.id)];
}

function getPreviewReadiness() {
  const planCandidates = getPlanCandidates();
  const openRuleIssueCount = getOpenRuleIssues().length;
  const missingActionCount = planCandidates.filter((candidate) => !isActionableDecision(getDecision(candidate))).length;
  const missingResourceTypeCount = planCandidates.filter((candidate) => {
    const decision = getDecision(candidate);
    return canEditImplementationModels(candidate, decision.action) && decision.implementationModels.length === 0;
  }).length;
  const missingAssessmentCount = planCandidates.filter((candidate) => !getAssessment(candidate)).length;
  const missingRationaleCount = planCandidates.filter((candidate) => !getDecision(candidate).rationale.trim()).length;
  const missingRationale = missingRationaleCount > 0;
  const unsavedRuleText = Boolean(getUnsavedApprovalEditor());
  const mutationRuleIds = planCandidates.flatMap(getCandidateMutationRuleIds);
  const mutationCount = mutationRuleIds.length;
  const conflictingMutationCount = mutationRuleIds.length - new Set(mutationRuleIds).size;
  const approvalIdentity = getValidatedCodeOwnerIdentity();
  let status = "ready";
  if (openRuleIssueCount) status = "blocked by rule issues";
  else if (planCandidates.length === 0) status = "no actions";
  else if (missingActionCount) status = "needs action";
  else if (missingResourceTypeCount) status = "needs resource type";
  else if (missingAssessmentCount) status = "needs assessment";
  else if (missingRationale) status = "needs rationale";
  else if (unsavedRuleText) status = "unsaved rule wording";
  else if (mutationCount === 0) status = "no catalog mutations";
  else if (conflictingMutationCount) status = "conflicting mutations";
  else if (!approvalIdentity) status = "needs verified CODEOWNER";
  return {
    planCandidates,
    openRuleIssueCount,
    approvalIdentity,
    missingActionCount,
    missingResourceTypeCount,
    missingAssessmentCount,
    missingRationaleCount,
    unsavedRuleText,
    mutationCount,
    conflictingMutationCount,
    status,
    ready: openRuleIssueCount === 0 && planCandidates.length > 0 && missingActionCount === 0 && missingResourceTypeCount === 0 && missingAssessmentCount === 0 && !missingRationale && !unsavedRuleText && mutationCount > 0 && conflictingMutationCount === 0 && Boolean(approvalIdentity)
  };
}

function getApprovalRequirements(readiness) {
  const hasPlan = readiness.planCandidates.length > 0;
  const missingAssessment = hasPlan && readiness.missingAssessmentCount > 0;
  const metadata = globalThis.__HOSTED_RULE_WORKBENCH__?.maintainerIdentity;
  const identityReason = metadata?.login && metadata.isCodeOwner === false
    ? "This account is not a CODEOWNER for this repository."
    : "GitHub identity or CODEOWNERS authorization could not be verified. Check GitHub authentication and relaunch Workbench.";
  return [
    { id: "rule-issues", label: "Rule Issues", value: readiness.openRuleIssueCount ? `${readiness.openRuleIssueCount} pending` : "None pending", status: readiness.openRuleIssueCount ? "pending" : "passed" },
    { id: "plan-actions", label: "Plan actions", value: hasPlan ? `${readiness.planCandidates.length} selected` : "None selected", status: hasPlan ? "passed" : "pending" },
    { id: "rule-actions", label: "Rule actions", value: readiness.missingActionCount ? `${readiness.missingActionCount} missing` : hasPlan ? "Complete" : "None selected", status: hasPlan && !readiness.missingActionCount ? "passed" : "pending" },
    { id: "resource-types", label: "Resource types", value: hasPlan ? readiness.missingResourceTypeCount ? `${readiness.missingResourceTypeCount} missing` : "Complete" : "None selected", status: hasPlan && !readiness.missingResourceTypeCount ? "passed" : "pending" },
    { id: "assessments", label: "Rebuild assessments", value: missingAssessment ? "Not available" : hasPlan ? "Available" : "Not required", status: missingAssessment ? "failed" : "passed", description: missingAssessment ? "Required rebuild assessment evidence is missing or invalid. Close Workbench, relaunch with -Rebuild, then reload this page." : "" },
    { id: "rationales", label: "Decision rationales", value: hasPlan ? readiness.missingRationaleCount ? `${readiness.missingRationaleCount} missing` : "Complete" : "None selected", status: hasPlan && !readiness.missingRationaleCount ? "passed" : "pending" },
    { id: "wording", label: "Rule wording", value: readiness.unsavedRuleText ? "Unsaved changes" : "Saved", status: readiness.unsavedRuleText ? "pending" : "passed" },
    { id: "mutations", label: "Catalog mutations", value: readiness.mutationCount ? formatCountLabel(readiness.mutationCount, "mutation") : "None", status: readiness.mutationCount ? "passed" : "pending" },
    { id: "targets", label: "Mutation targets", value: hasPlan ? readiness.conflictingMutationCount ? `${readiness.conflictingMutationCount} conflicting` : "Unique" : "None selected", status: hasPlan && !readiness.conflictingMutationCount ? "passed" : "pending" },
    { id: "identity", label: "GitHub identity", value: readiness.approvalIdentity?.login || metadata?.login || "Unavailable", status: readiness.approvalIdentity ? "passed" : "failed", description: readiness.approvalIdentity ? "" : identityReason }
  ];
}

function renderApprovalRequirements(readiness) {
  elements["approval-requirements"].innerHTML = `<strong class="approval-requirements-title">Approval Requirements</strong>${getApprovalRequirements(readiness).map((requirement) => {
    const pending = requirement.status === "pending";
    const failed = requirement.status === "failed";
    const tag = pending ? "button" : "div";
    const descriptionId = `approval-${requirement.id}-description`;
    const attributes = pending
      ? `type="button" data-approval-target="${requirement.id}" aria-label="${escapeHtml(`${requirement.label}: ${requirement.value}. Go to correction`)}"`
      : failed ? `tabindex="0" role="group" aria-label="${escapeHtml(`${requirement.label}: ${requirement.value}`)}" aria-describedby="${descriptionId}" data-workbench-tooltip="${escapeHtml(requirement.description)}"` : "";
    return `<${tag} class="approval-requirement ${requirement.status}${pending ? " clickable" : ""}" data-approval-requirement="${requirement.id}" ${attributes}>
      ${icon(pending ? "warning" : failed ? "error" : "pass")}
      <span>${escapeHtml(requirement.label)}</span>
      <strong>${escapeHtml(requirement.value)}</strong>
      ${failed ? `<span id="${descriptionId}" hidden>${escapeHtml(requirement.description)}</span>` : ""}
    </${tag}>`;
  }).join("")}`;
}

function getApprovalRepairTarget(requirementId, readiness = getPreviewReadiness()) {
  if (requirementId === "rule-issues") {
    const filters = [...new Set([state.ruleIssueFilter, ...RULE_ISSUE_FILTERS.map((filter) => filter.key)])];
    for (const filter of filters) {
      const issue = getFilteredRuleIssues(filter, "")[0];
      if (issue) return { kind: "issue", issue, filter };
    }
    return null;
  }
  if (requirementId === "wording") {
    const unsaved = getUnsavedApprovalEditor();
    return unsaved ? { kind: "wording", ...unsaved } : null;
  }
  if (["assessments", "identity"].includes(requirementId)) return null;
  if (requirementId === "plan-actions" || !readiness.planCandidates.length) return { kind: "sources" };
  const candidates = sortPlanCandidates(readiness.planCandidates, state.planSort);
  const predicates = {
    "rule-actions": (candidate) => !isActionableDecision(getDecision(candidate)),
    "resource-types": (candidate) => getPlanReadiness(candidate).resourceTypeRequired,
    rationales: (candidate) => !getDecision(candidate).rationale.trim(),
    mutations: (candidate) => getCandidateMutationRuleIds(candidate).length === 0
  };
  let candidate;
  if (requirementId === "targets") {
    const counts = new Map();
    candidates.flatMap(getCandidateMutationRuleIds).forEach((id) => counts.set(id, (counts.get(id) || 0) + 1));
    candidate = candidates.find((item) => getCandidateMutationRuleIds(item).some((id) => counts.get(id) > 1));
  } else if (predicates[requirementId]) {
    candidate = candidates.find(predicates[requirementId]);
  }
  if (!candidate) return null;
  const selector = requirementId === "resource-types" ? "[data-implementation-model]:not(:disabled)"
    : requirementId === "rationales" ? '[data-decision-field="rationale"]'
      : ".action-options input:not(:disabled)";
  return { kind: "candidate", candidate, selector };
}

function scrollApprovalTargetIntoView(target, scroller, center = false) {
  if (!target || !scroller) return;
  const bounds = scroller.getBoundingClientRect();
  const item = target.getBoundingClientRect();
  let top = scroller.scrollTop;
  if (center) top += item.top - bounds.top - Math.max(0, (scroller.clientHeight - item.height) / 2);
  else if (item.top < bounds.top) top += item.top - bounds.top;
  else if (item.bottom > bounds.bottom) top += item.bottom - bounds.bottom;
  else return;
  scroller.scrollTo({ top: Math.max(0, top), behavior: "smooth" });
}

async function navigateApprovalRequirement(requirementId) {
  const readiness = getPreviewReadiness();
  const requirement = getApprovalRequirements(readiness).find((item) => item.id === requirementId);
  if (requirement?.status !== "pending") return null;
  if (getUnsavedApprovalEditor() && requirementId !== "wording") {
    showToast("Save or reset the current rule wording before navigating to another correction.", true);
    return null;
  }
  const target = getApprovalRepairTarget(requirementId, readiness);
  if (!target) {
    showToast("That requirement no longer needs a correction.");
    return null;
  }
  elements["preview-review-popover"].hidden = true;
  hideStatusTooltip();
  if (target.kind === "issue") {
    state.queries["rule-issues"] = "";
    state.ruleIssueFilter = target.filter;
    state.activeRuleIssueKey = target.issue.id;
    switchView("catalog");
    setWorkspaceTab("rule-issues");
    const row = elements["rule-issues-list"].querySelector(`[data-rule-issue-key="${CSS.escape(target.issue.id)}"]`);
    scrollApprovalTargetIntoView(row, elements["rule-issues-list"], true);
    row?.focus({ preventScroll: true });
    return target;
  }
  if (target.kind === "sources") {
    state.queries["candidate-sources"] = "";
    setWorkspaceTab("candidate-sources");
    switchView("catalog");
    showCandidatePane("candidates");
    candidateHierarchicalView?.refresh();
    elements["search-input"].focus({ preventScroll: true });
    return target;
  }
  if (target.kind === "wording") {
    const value = target.editor.value;
    const selection = [target.editor.selectionStart, target.editor.selectionEnd, target.editor.selectionDirection];
    setWorkspaceTab("candidate-sources");
    switchView("catalog");
    showCandidatePane("details");
    const editor = elements["assessment-panel"].querySelector(`[data-proposed-candidate-key="${CSS.escape(target.candidate.key)}"]`);
    if (editor) {
      editor.value = value;
      scrollCandidateDetailTargetIntoView(editor);
      editor.focus({ preventScroll: true });
      editor.setSelectionRange(...selection);
    }
    return target;
  }
  state.queries["candidate-sources"] = "";
  setWorkspaceTab("candidate-sources");
  selectCandidate(target.candidate.key, "plan");
  switchView("catalog");
  showCandidatePane("details");
  candidateHierarchicalView?.refresh();
  revealCandidateInTree(target.candidate.key);
  await new Promise((resolve) => requestAnimationFrame(() => requestAnimationFrame(resolve)));
  if (state.currentView === "catalog" && state.workspaceTab === "candidate-sources" && state.activeKey === target.candidate.key) {
    focusCandidateAttention({ target: target.selector, label: requirement.label });
  }
  return target;
}

function renderCounts() {
  const planCount = getPlanCandidates().length;
  workbenchStatusBar.update("eligible", { text: formatNumber(state.candidates.length) });
  workbenchStatusBar.update("plan", { text: formatNumber(planCount) });
  elements["plan-activity-count"].textContent = planCount > 999 ? "999+" : formatNumber(planCount);
  elements["plan-activity-count"].hidden = planCount === 0;
  const openRuleIssueCount = getOpenRuleIssues().length;
  elements["rule-issues-tab-count"].textContent = formatNumber(openRuleIssueCount);
  elements["rule-issues-tab-count"].hidden = openRuleIssueCount === 0;
  const planLabel = `Promotion Plan (${formatNumber(planCount)})`;
  setWorkbenchTooltip(elements["promotion-plan-stage"], `Open promotion plan (${formatNumber(planCount)})`);
  elements["promotion-plan-stage"].setAttribute("aria-label", planLabel);
}

function formatCountLabel(count, singular) {
  return `${formatNumber(count)} ${count === 1 ? singular : `${singular}s`}`;
}

function getPlanCandidates() {
  return state.assessedCandidates.filter((candidate) => getDecision(candidate).inPlan);
}

function getCapacityReports() {
  return state.bundle.guidanceCapacity.reports;
}

function getActiveCandidate() {
  return state.assessedCandidates.find((candidate) => candidate.key === state.activeKey) || null;
}

function getActiveProtectedRule() {
  return state.protectedRules.find((rule) => rule.id === state.activeProtectedRuleId) || null;
}

function syncCandidateTreeRows() {
  elements["candidate-list"].querySelectorAll("[data-candidate-key]").forEach((row) => {
    const key = row.dataset.candidateKey;
    const candidate = state.candidates.find((item) => item.key === key);
    const inPlan = candidate && getDecision(candidate).inPlan;
    const active = key === state.activeKey;
    row.classList.toggle("active", active);
    if (active) row.setAttribute("aria-current", "true");
    else row.removeAttribute("aria-current");
    row.classList.toggle("in-plan", inPlan);
    const decoration = candidate ? getCandidateDecoration(candidate) : null;
    row.classList.toggle("candidate-decoration-ready", decoration?.status === "ready");
    row.classList.toggle("candidate-decoration-needs-input", decoration?.status === "needs-input");
    const decorationIcon = row.querySelector(".candidate-decoration-icon");
    const decorationDescription = row.querySelector(".candidate-decoration-description");
    if (decorationIcon) {
      decorationIcon.toggleAttribute("hidden", !decoration);
      setWorkbenchTooltip(decorationIcon, decoration?.description || "");
    }
    if (decorationDescription) decorationDescription.textContent = decoration?.description || "";
    const checkbox = row.querySelector("[data-decision-key]");
    if (checkbox) {
      const planSelectable = canSelectCandidateForPlan(candidate, getDecision(candidate));
      checkbox.checked = inPlan;
      checkbox.disabled = !planSelectable;
      checkbox.classList.toggle("candidate-plan-unavailable", !planSelectable);
      checkbox.toggleAttribute("aria-hidden", !planSelectable);
      checkbox.tabIndex = planSelectable ? 0 : -1;
      setWorkbenchTooltip(checkbox, planSelectable ? inPlan ? "Remove candidate from promotion plan" : "Add candidate to promotion plan" : "No change is recommended");
      checkbox.setAttribute("aria-label", planSelectable
        ? `${inPlan ? "Remove" : "Add"} ${getEffectiveHostedRuleId(candidate)} ${inPlan ? "from" : "to"} promotion plan`
        : `${getEffectiveHostedRuleId(candidate)} has no recommended change`);
    }
    const candidateId = row.querySelector(".candidate-tree-copy strong");
    if (candidateId) candidateId.textContent = getEffectiveHostedRuleId(candidate);
    const assessment = candidate && getAssessment(candidate, getDecision(candidate));
    const token = row.querySelector(".tree-cost");
    if (token) token.textContent = assessment ? formatCandidateTokenValue(candidate, assessment) : "—";
    const impact = row.querySelector(".tree-impact");
    if (impact) impact.textContent = assessment ? calculateImpact(assessment.factors) : "—";
    const recommendation = row.querySelector(".recommendation-badge, .candidate-tree-summary > .status-badge.warning");
    if (recommendation) recommendation.outerHTML = renderAssessmentRecommendation(assessment, false);
  });
  syncCandidateTreeAggregates();
}

function syncCandidateTreeAggregates() {
  if (!candidateHierarchicalView) return;
  candidateHierarchicalView.model.nodes.filter((node) => node.data?.candidates).forEach((node) => {
    const candidates = node.data.candidates;
    const decoration = getCandidateAggregateDecoration(candidates);
    node.data.decoration = decoration;
    document.querySelectorAll(`[data-node-id="${CSS.escape(node.id)}"]`).forEach((row) => {
      row.classList.toggle("candidate-aggregate-ready", decoration?.status === "ready");
      row.classList.toggle("candidate-aggregate-needs-input", decoration?.status === "needs-input");
      if (decoration) row.dataset.selectionStatus = decoration.status;
      else delete row.dataset.selectionStatus;
      const decorationIcon = row.querySelector(".candidate-parent-decoration-icon");
      const countBadge = row.querySelector(".count-badge");
      const decorationDescription = row.querySelector(".candidate-decoration-description");
      if (decorationIcon) decorationIcon.toggleAttribute("hidden", !decoration);
      if (countBadge) setWorkbenchTooltip(countBadge, decoration?.description || "");
      if (decorationDescription) decorationDescription.textContent = decoration?.description || "";
    });
  });
}

function selectCandidate(key, rationaleReturnView = null) {
  state.activeKey = key;
  state.activeProtectedRuleId = null;
  state.rationaleReturnView = rationaleReturnView;
  setRuleAssistanceCandidate(getActiveCandidate(), "candidate-sources");
  syncCandidateTreeRows();
  renderAssessment();
  refreshPresentation();
}

function selectProtectedRule(id) {
  state.activeKey = null;
  state.activeProtectedRuleId = id;
  setRuleAssistanceCandidate(null);
  candidateHierarchicalView?.refresh();
  renderAssessment();
  refreshPresentation();
}

function showCandidatePane(pane) {
  const activePane = pane === "details" ? "details" : "candidates";
  state.candidatePane = activePane;
  const detailsActive = activePane === "details";
  elements["candidate-panel"].hidden = detailsActive;
  elements["assessment-panel"].hidden = !detailsActive;
  document.querySelectorAll("[data-candidate-pane]").forEach((button) => {
    const active = button.dataset.candidatePane === activePane;
    button.classList.toggle("active", active);
    button.setAttribute("aria-selected", String(active));
  });
  if (!detailsActive) candidateHierarchicalView?.refreshLayout();
  syncRuleAssistanceVisibility();
}

function updateFilter(value) {
  const previousCatalogStatusFilter = state.workspaceTab === "candidate-sources" ? getCandidateCatalogStatusFilter() : null;
  state.queries[state.workspaceTab] = value;
  if (state.workspaceTab === "candidate-sources") {
    if (previousCatalogStatusFilter !== getCandidateCatalogStatusFilter()) candidateHierarchicalView?.setInput(state.candidates);
    renderBulkActions();
    navigateCandidateSearch();
  }
  else if (state.workspaceTab === "assessment-results") {
    state.assessmentActiveKey = null;
    renderAssessmentResults();
  }
  else renderRuleIssues();
  refreshPresentation();
}

function handleStatusNavigation(event) {
  const control = event.target.closest("[data-status-navigation]");
  if (!control) return;
  const destination = control.dataset.statusNavigation;
  if (["eligible", "mapped", "unmapped"].includes(destination)) {
    switchView("catalog");
    setWorkspaceTab("candidate-sources");
    showCandidatePane("candidates");
    const query = destination === "eligible" ? "" : `status:${destination}`;
    elements["search-input"].value = query;
    updateFilter(query);
    return;
  }
  if (destination === "excluded") {
    switchView("catalog");
    setWorkspaceTab("assessment-results");
    showAssessmentPane("assessments");
    elements["search-input"].value = "";
    updateFilter("");
    return;
  }
  if (destination === "issues") {
    switchView("catalog");
    setWorkspaceTab("rule-issues");
    return;
  }
  if (destination === "validation-issues") {
    const problems = getValidationProblems();
    const problem = problems.find((item) => item.kind === "error") || problems[0];
    if (!problem) return;
    switchView("catalog");
    setWorkspaceTab("candidate-sources");
    selectCandidate(problem.candidateKey);
    showCandidatePane("details");
    focusCandidateAttention(getPlanReadiness(getActiveCandidate()).attention);
    return;
  }
  if (destination === "plan" || destination === "capacity") {
    switchView("plan");
    if (destination === "capacity") requestAnimationFrame(() => elements["capacity-panel"].focus({ preventScroll: true }));
    return;
  }
  if (destination === "preview") switchView("preview");
}

function selectAssessmentResult(key) {
  if (state.assessmentActiveKey !== key) state.assessmentOverrideEditingKey = null;
  state.assessmentActiveKey = key;
  setRuleAssistanceCandidate(state.assessedCandidates.find(candidate => candidate.key === key) || null, "assessment-results");
  syncAssessmentResultRows();
  renderAssessmentResultDetail();
  refreshPresentation();
}

function openAssessmentOverride(key) {
  state.assessmentOverrideEditingKey = null;
  selectAssessmentResult(key);
  showAssessmentPane("details");
}

function syncAssessmentResultRows() {
  elements["assessment-results-list"].querySelectorAll("[data-assessment-key]").forEach((row) => {
    const active = row.dataset.assessmentKey === state.assessmentActiveKey;
    row.classList.toggle("active", active);
    if (active) row.setAttribute("aria-current", "true");
    else row.removeAttribute("aria-current");
  });
}

function showAssessmentPane(pane) {
  const activePane = pane === "details" ? "details" : "assessments";
  if (activePane === "assessments" && state.assessmentPane === "details") {
    state.assessmentOverrideEditingKey = null;
    state.assessmentActiveKey = null;
    syncAssessmentResultRows();
    renderAssessmentResultDetail();
  }
  state.assessmentPane = activePane;
  const detailsActive = activePane === "details";
  elements["assessment-results-list"].closest(".candidate-panel").hidden = detailsActive;
  elements["assessment-results-detail"].hidden = !detailsActive;
  document.querySelectorAll("[data-assessment-pane]").forEach((button) => {
    const active = button.dataset.assessmentPane === activePane;
    button.classList.toggle("active", active);
    button.setAttribute("aria-selected", String(active));
  });
  if (!detailsActive) assessmentHierarchicalView?.refreshLayout();
  syncRuleAssistanceVisibility();
}

function setWorkspaceTab(tab) {
  if (!["candidate-sources", "assessment-results", "rule-issues"].includes(tab)) return;
  const key = tab === "candidate-sources" ? state.activeKey : tab === "assessment-results" ? state.assessmentActiveKey : null;
  const protectedTarget = tab === "candidate-sources" && Boolean(state.activeProtectedRuleId);
  dismissNotification();
  state.workspaceTab = tab;
  setRuleAssistanceCandidate(!protectedTarget && key ? state.assessedCandidates.find(candidate => candidate.key === key) || null : null);
  document.querySelectorAll("[data-workspace-tab]").forEach((button) => {
    const active = button.dataset.workspaceTab === tab;
    button.classList.toggle("active", active);
    button.setAttribute("aria-selected", String(active));
  });
  elements["candidate-sources-panel"].classList.toggle("active", tab === "candidate-sources");
  elements["candidate-sources-panel"].hidden = tab !== "candidate-sources";
  elements["assessment-results-panel"].classList.toggle("active", tab === "assessment-results");
  elements["assessment-results-panel"].hidden = tab !== "assessment-results";
  elements["rule-issues-panel"].classList.toggle("active", tab === "rule-issues");
  elements["rule-issues-panel"].hidden = tab !== "rule-issues";
  elements["search-input"].value = state.queries[tab];
  elements["search-input"].placeholder = tab === "candidate-sources"
    ? "Search sources, categories, or rules"
    : tab === "assessment-results"
      ? "Search excluded assessment results"
      : "Search rule issues";
  elements["search-input"].setAttribute("aria-label", elements["search-input"].placeholder);
  if (tab === "candidate-sources") candidateHierarchicalView?.refreshLayout();
  else if (tab === "assessment-results") assessmentHierarchicalView?.refreshLayout();
  else renderRuleIssues();
  refreshPresentation();
}

function handleTreeSelection(event) {
  const candidateCheckbox = event.target.closest("[data-decision-key]");
  if (!candidateCheckbox) return;
  const candidate = state.candidates.find((item) => item.key === candidateCheckbox.dataset.decisionKey);
  if (!candidate) return;
  if (!canSelectCandidateForPlan(candidate, getDecision(candidate))) {
    candidateCheckbox.checked = false;
    return;
  }
  if (candidateCheckbox.checked) {
    updateDecision(candidate, { inPlan: true });
    selectCandidate(candidate.key);
  } else {
    removePlanMembership(candidate);
  }
}

function switchView(view) {
  dismissNotification();
  if (view !== "preview") elements["preview-review-popover"].hidden = true;
  state.currentView = view;
  document.querySelectorAll("[data-view]").forEach((button) => button.classList.toggle("active", button.dataset.view === view));
  document.querySelectorAll("[data-view-panel]").forEach((panel) => panel.classList.toggle("active", panel.dataset.viewPanel === view));
  if (view === "plan") {
    renderPlan();
    renderCapacity();
  }
  if (view === "preview") renderPreview();
  refreshPresentation();
}

function buildDraftExport() {
  const session = normalizeSessionTimestamps(state.session);
  return {
    $schema: "workbench-draft-v4.schema.json",
    schemaVersion: WORKBENCH_DRAFT_SCHEMA_VERSION,
    kind: "hosted-rule-workbench-draft",
    sourceFiles: structuredClone(session.sourceFiles),
    createdAt: session.createdAt,
    updatedAt: session.updatedAt,
    approverName: session.approverName || "",
    decisions: Object.fromEntries(Object.entries(session.decisions).map(([key, decision]) => [key, {
      action: decision.action ?? null,
      selected: decision.inPlan,
      selectionSource: decision.planMembershipSource,
      bulkOperationId: decision.bulkOperationId,
      rationale: decision.rationale,
      proposedHostedRuleId: decision.proposedHostedRuleId || null,
      proposedText: decision.proposedText,
      retireHostedRuleIds: [...decision.retireHostedRuleIds],
      implementationModels: decision.implementationModels,
      sourceContentSha256: decision.sourceHash,
      updatedAt: decision.updatedAt
    }])),
    applicabilityOverrides: Object.fromEntries(Object.entries(session.applicabilityOverrides).map(([key, override]) => [key, {
      ...override,
      recordedBy: override.recordedBy.login
    }])),
    bulkOperations: session.bulkOperations.map((operation) => ({
      id: operation.id,
      action: operation.action,
      candidateKeys: operation.candidateKeys,
      createdAt: operation.createdAt
    }))
  };
}

function deserializeDraft(draft, candidates) {
  if (draft?.schemaVersion !== WORKBENCH_DRAFT_SCHEMA_VERSION || draft.kind !== "hosted-rule-workbench-draft") return null;
  const candidatesByKey = new Map(candidates.map((candidate) => [candidate.key, candidate]));
  const activeRuleIds = new Set(state.bundle.catalog.rules.filter((rule) => rule.status === "active").map((rule) => rule.id));
  for (const [key, decision] of Object.entries(draft.decisions || {})) {
    const candidate = candidatesByKey.get(key);
    if (!candidate) continue;
    const ownRuleId = candidate.catalogMapping.hostedRuleId || candidate.recommendation.hostedId;
    if (new Set(decision.retireHostedRuleIds).size !== decision.retireHostedRuleIds.length
      || decision.retireHostedRuleIds.some((id) => id === ownRuleId || !activeRuleIds.has(id))) {
      throw new Error("The imported draft contains an unknown, protected, duplicate, or self retirement.");
    }
  }
  return {
    schemaVersion: SESSION_SCHEMA_VERSION,
    id: "current",
    sourceFiles: structuredClone(draft.sourceFiles),
    createdAt: draft.createdAt,
    updatedAt: draft.updatedAt,
    approverName: draft.approverName,
    decisions: Object.fromEntries(Object.entries(draft.decisions || {}).map(([key, decision]) => [key, {
      action: decision.action,
      inPlan: decision.selected,
      planMembershipSource: decision.selectionSource,
      bulkOperationId: decision.bulkOperationId,
      rationale: decision.rationale,
      proposedHostedRuleId: candidatesByKey.get(key)?.assessment.proposedHostedRuleId || "",
      proposedText: decision.proposedText,
      retireHostedRuleIds: [...decision.retireHostedRuleIds],
      implementationModels: Array.isArray(decision.implementationModels) ? decision.implementationModels : undefined,
      sourceHash: decision.sourceContentSha256,
      updatedAt: decision.updatedAt
    }])),
    applicabilityOverrides: Object.fromEntries(Object.entries(draft.applicabilityOverrides || {}).map(([key, override]) => [key, {
      ...override,
      recordedBy: { type: "draft", login: override.recordedBy }
    }])),
    bulkOperations: (draft.bulkOperations || []).map((operation) => ({
      ...operation,
      candidateKeys: operation.candidateKeys.filter((key) => candidatesByKey.has(key))
    }))
  };
}

function buildApprovedRules() {
  const identity = getValidatedCodeOwnerIdentity();
  if (!identity) return null;
  return {
    $schema: "approved-rules-v4.schema.json",
    schemaVersion: APPROVED_RULES_SCHEMA_VERSION,
    kind: "hosted-approved-rules",
    catalogContentSha256: state.bundle.catalog.contentSha256,
    approvedAt: toUtcTimestamp(state.session.updatedAt),
    approvedBy: {
      type: "github-authenticated",
      id: identity.login,
      displayName: identity.login
    },
    mutations: getPlanCandidates().flatMap(buildApprovedMutations)
  };
}

function exportDraft() {
  const payload = JSON.stringify(buildDraftExport(), null, 2) + "\n";
  downloadJson(payload, `hosted-rule-draft-${toUtcTimestamp().replace(/[:.]/g, "-")}.json`);
  showToast("Draft exported");
}

async function approveAndExport() {
  try {
    await loadWorkbenchRuntimeConfig();
  } catch (error) {
    showToast(error.message, true);
    return;
  }
  const readiness = getPreviewReadiness();
  if (!readiness.ready) {
    showToast("Complete the approval requirements before exporting.", true);
    return;
  }
  elements["approve-export-button"].disabled = true;
  try {
    const approvedRules = buildApprovedRules();
    if (!approvedRules) {
      showToast("A verified CODEOWNER identity is required before exporting.", true);
      return;
    }
    downloadJson(JSON.stringify(approvedRules, null, 2) + "\n", `hosted-approved-rules-${approvedRules.approvedAt.replace(/[:.]/g, "-")}.json`);
    showToast("Approved rules exported");
  } catch {
    showToast("Approved rules could not be exported.", true);
  } finally {
    renderPreview();
  }
}

async function importDraft(event) {
  const file = event.target.files?.[0];
  event.target.value = "";
  if (!file) return;
  try {
    const importedDraft = JSON.parse(await file.text());
    const draft = deserializeDraft(importedDraft, state.assessedCandidates);
    if (!draft) throw new Error("The draft version is not supported.");
    if (!sourceFilesEqual(draft.sourceFiles, state.session.sourceFiles)) {
      throw new Error("The draft belongs to a different source snapshot.");
    }
    if (!draft.decisions || typeof draft.decisions !== "object" || Array.isArray(draft.decisions)) {
      throw new Error("The draft decisions are invalid.");
    }
    if (!draft.applicabilityOverrides || typeof draft.applicabilityOverrides !== "object" || Array.isArray(draft.applicabilityOverrides)) {
      throw new Error("The draft applicability overrides are invalid.");
    }
    if (!Array.isArray(draft.bulkOperations) || draft.bulkOperations.some((operation) => !isValidBulkOperation(operation)) || new Set(draft.bulkOperations.map((operation) => operation.id)).size !== draft.bulkOperations.length) {
      throw new Error("The draft bulk operations are invalid.");
    }
    const overriddenCandidateKeys = new Set();
    for (const [key, override] of Object.entries(draft.applicabilityOverrides)) {
      const candidate = state.assessedCandidates.find((item) => item.key === key);
      if (!candidate || candidate.assessment.hostedApplicable || override.sourceContentSha256 !== candidate.hash || override.state !== "provisional" || override.originalHostedApplicable !== false || override.effectiveHostedApplicable !== true || typeof override.rationale !== "string" || !override.rationale.trim() || override.rationale.length > OVERRIDE_RATIONALE_MAX_LENGTH || !override.recordedBy?.login || typeof override.recordedAt !== "string") {
        throw new Error(`The draft applicability override for ${key} is invalid.`);
      }
      overriddenCandidateKeys.add(key);
    }
    for (const [key, decision] of Object.entries(draft.decisions)) {
      const candidate = state.assessedCandidates.find((item) => item.key === key);
      if (!candidate || (!candidate.assessment.hostedApplicable && !overriddenCandidateKeys.has(key)) || decision.sourceHash !== candidate.hash || (decision.action !== null && !getAllowedActions(candidate, decision.proposedText).includes(decision.action)) || !isValidPlanMembership(decision, key, draft.bulkOperations) || typeof decision.rationale !== "string" || decision.rationale.length > DECISION_RATIONALE_MAX_LENGTH || decision.proposedHostedRuleId !== candidate.assessment.proposedHostedRuleId) {
        throw new Error(`The draft decision for ${key} is invalid.`);
      }
    }
    for (const operation of draft.bulkOperations) {
      if (operation.candidateKeys.some((key) => draft.decisions[key]?.planMembershipSource !== "bulk"
        || draft.decisions[key]?.bulkOperationId !== operation.id)) {
        throw new Error(`The draft bulk operation ${operation.id} is inconsistent with its decisions.`);
      }
    }
    state.session.approverName = String(draft.approverName || "").slice(0, 120);
    autofillApproverName();
    state.session.decisions = draft.decisions || {};
    state.session.applicabilityOverrides = draft.applicabilityOverrides || {};
    state.session.bulkOperations = draft.bulkOperations;
    refreshEffectiveCandidates();
    state.session.updatedAt = toUtcTimestamp();
    await persistSession();
    renderAll();
    showToast("Draft imported");
  } catch (error) {
    showToast(error.message, true);
  }
}

function downloadJson(content, filename) {
  const blob = new Blob([content], { type: "application/json" });
  const url = URL.createObjectURL(blob);
  const anchor = document.createElement("a");
  anchor.href = url;
  anchor.download = filename;
  anchor.click();
  URL.revokeObjectURL(url);
}

function openDatabase() {
  if (databasePromise) return databasePromise;
  databasePromise = new Promise((resolve, reject) => {
    const request = indexedDB.open(DATABASE_NAME, DATABASE_VERSION);
    request.onupgradeneeded = () => {
      const database = request.result;
      if (!database.objectStoreNames.contains("sessions")) database.createObjectStore("sessions", { keyPath: "id" });
    };
    request.onsuccess = () => resolve(request.result);
    request.onerror = () => reject(request.error);
  });
  return databasePromise;
}

async function readSession(id) {
  const database = await openDatabase();
  return new Promise((resolve, reject) => {
    const request = database.transaction("sessions", "readonly").objectStore("sessions").get(id);
    request.onsuccess = () => resolve(request.result || null);
    request.onerror = () => reject(request.error);
  });
}

function persistSession(session = state.session, beforeWrite) {
  if (!session) return Promise.resolve();
  const snapshot = normalizeSessionTimestamps(session);
  const writeSnapshot = async () => {
    const database = await openDatabase();
    beforeWrite?.();
    await new Promise((resolve, reject) => {
      const transaction = database.transaction("sessions", "readwrite");
      transaction.oncomplete = () => resolve();
      transaction.onabort = () => reject(transaction.error || new Error("The draft save was aborted"));
      transaction.objectStore("sessions").put(snapshot);
    });
    setSaveIndicator(`Saved ${formatTime(snapshot.updatedAt)}`);
  };
  persistencePromise = persistencePromise.then(writeSnapshot, writeSnapshot);
  persistencePromise.catch((error) => {
    setSaveIndicator("Save failed", { kind: "error", icon: "error", tooltip: `Draft Save Failed: ${error.message}` });
    showToast(`Draft could not be saved: ${error.message}`, true);
  });
  return persistencePromise;
}

function setSaveIndicator(text, { kind = "success", icon = "check-compact", tooltip = "Draft Autosave State" } = {}) {
  workbenchStatusBar.update("save", { text, kind, icon, tooltip });
}

function renderFatalError(error) {
  elements.workspace.classList.remove("icon-paint-pending");
  elements["candidate-list"].innerHTML = "";
  elements["assessment-panel"].innerHTML = `<div class="empty-state"><h2>Workbench Could Not Load</h2><p>${escapeHtml(error.message)}</p></div>`;
  showCandidatePane("details");
  setSaveIndicator("Bundle unavailable", { kind: "error", icon: "error", tooltip: "Bundle Unavailable" });
  showToast(error.message, true);
}

function dismissNotification() {
  clearTimeout(toastTimer);
  toastTimer = undefined;
  elements.toast.classList.remove("visible");
}

function showToast(message, error = false) {
  dismissNotification();
  elements["toast-message"].textContent = message;
  elements.toast.classList.toggle("error", error);
  elements.toast.setAttribute("role", error ? "alert" : "status");
  elements.toast.setAttribute("aria-live", error ? "assertive" : "polite");
  elements.toast.classList.add("visible");
  if (!error) toastTimer = setTimeout(dismissNotification, 8000);
}

function refreshPresentation() {
  syncRuleAssistanceVisibility();
  scheduleTruncationTooltips();
}

function scheduleTruncationTooltips() {
  cancelAnimationFrame(truncationTooltipFrame);
  truncationTooltipFrame = requestAnimationFrame(syncTruncationTooltips);
}

function syncTruncationTooltips() {
  document.querySelectorAll("[data-truncation-tooltip]").forEach((node) => {
    if (node.hasAttribute("data-workbench-tooltip") || node.closest("[data-truncation-owner]")) {
      node.removeAttribute("data-truncation-tooltip");
      return;
    }
    const clipped = node.getClientRects().length > 0
      && (node.scrollWidth > node.clientWidth || node.scrollHeight > node.clientHeight);
    if (clipped) return;
    node.removeAttribute("data-truncation-tooltip");
  });
  document.querySelectorAll(".app-shell *").forEach((node) => {
    if (!node.getClientRects().length || !node.textContent.trim() || node.hasAttribute("data-workbench-tooltip") || node.closest("[data-truncation-owner]")) return;
    if (getComputedStyle(node).textOverflow !== "ellipsis") return;
    if (node.scrollWidth <= node.clientWidth && node.scrollHeight <= node.clientHeight) return;
    node.setAttribute("data-truncation-tooltip", "");
  });
}

function escapeHtml(value) {
  return String(value ?? "")
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll('"', "&quot;")
    .replaceAll("'", "&#039;");
}

function formatNumber(value) {
  return new Intl.NumberFormat("en-US").format(Number(value || 0));
}

function formatSignedNumber(value) {
  const number = Number(value || 0);
  return `${number > 0 ? "+" : ""}${formatNumber(number)}`;
}

function capitalize(value) {
  const text = String(value || "");
  return text ? text[0].toUpperCase() + text.slice(1) : text;
}

function formatTitleCase(value) {
  return String(value || "").replace(/\b[a-z]/g, (letter) => letter.toUpperCase());
}

function formatRecommendation(value) {
  return value === "no-change" ? "No Change" : capitalize(value);
}

function formatCandidateLifecycle(value) {
  if (value === "added") return "New";
  if (value === "source-lifecycle-changed") return "Lifecycle Changed";
  return capitalize(value);
}

function formatHostedCategory(value) {
  const categories = {
    repository: "Repository",
    "review-classification-and-evidence": "Review classification & evidence",
    implementation: "Implementation",
    testing: "Testing",
    documentation: "Documentation"
  };
  return categories[value] || "Other";
}

function getUpstreamCategory(candidate) {
  return candidate.state === "changed" ? "Changed guidance (drift)" : "Current guidance";
}

function formatContractCategory(path) {
  return String(path).split("/").pop()
    .replace("-compliance-contract.instructions.md", "")
    .split("-")
    .map(capitalize)
    .join(" ");
}

function groupCandidatesByCategory(candidates) {
  return candidates.reduce((groups, candidate) => {
    (groups[candidate.category] ||= []).push(candidate);
    return groups;
  }, {});
}

function formatTime(value) {
  return new Intl.DateTimeFormat("en-US", { hour: "numeric", minute: "2-digit", second: "2-digit" }).format(new Date(value));
}

function formatTimestamp(value) {
  return new Intl.DateTimeFormat("en-US", { dateStyle: "medium", timeStyle: "short" }).format(new Date(value));
}
