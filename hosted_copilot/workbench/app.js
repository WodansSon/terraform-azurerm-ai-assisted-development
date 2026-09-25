"use strict";

const DATABASE_NAME = "hosted-rule-workbench";
const DATABASE_VERSION = 1;
const ACTIVE_SESSION_KEY = "hosted-rule-workbench.active-session";
const WORKBENCH_DISPLAY_SCHEMA_VERSION = 4;
const SESSION_SCHEMA_VERSION = 6;
const WORKBENCH_DRAFT_SCHEMA_VERSION = 4;
const APPROVED_RULES_SCHEMA_VERSION = 4;
const DECISION_RATIONALE_MAX_LENGTH = 500;
const OVERRIDE_RATIONALE_MAX_LENGTH = 500;
const WORKBENCH_TOOLTIP_DELAY_MS = 500;
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
  raw: "Approved rules"
};
const IMPLEMENTATION_MODELS = ["legacy", "typed", "framework"];
const RULE_ISSUE_RELATIONSHIPS = {
  equivalent: { kind: "duplicate", label: "Duplicate", semantic: "equivalent" },
  "partial-overlap": { kind: "overlap", label: "Partial overlap", semantic: "partial" },
  "assessment-extends-hosted": { kind: "overlap", label: "Broader overlap", sourceBreadth: "broader" },
  "assessment-narrows-hosted": { kind: "overlap", label: "Narrower overlap", sourceBreadth: "narrower" },
  conflicts: { kind: "contradiction", label: "Contradiction", semantic: "conflict" }
};
const RULE_ISSUE_FILTERS = [
  ["contradiction", "Contradictions"],
  ["duplicate", "Duplicates"],
  ["overlap", "Overlaps"]
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
  Object.values(normalized.manualRelationshipChecks || {}).forEach((check) => normalizeTimestampProperty(check, "checkedAt"));
  (normalized.bulkOperations || []).forEach((operation) => normalizeTimestampProperty(operation, "createdAt"));
  return normalized;
}

const state = {
  bundle: null,
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
  planSort: { field: "candidate", direction: "ascending" }
};

const elements = {};
let databasePromise;
let persistencePromise = Promise.resolve();
let toastTimer;
let truncationTooltipFrame;
let candidateHierarchicalView;
let assessmentHierarchicalView;
let previewFilesByScope = { proposed: [], payload: [], raw: [] };
let previewBodyVirtualizer;
let previewVirtualizationResizeTimer;
const previewExpandedScopes = new Set(Object.keys(PREVIEW_SCOPE_LABELS));
let previewSelectedFilePath = "";
let previewTreeResizePointerId = null;
const candidateExpansionState = new Map();
const assessmentExpansionState = new Map();
const activeRelationshipChecks = new Set();
const workbenchTooltip = {
  anchorX: 0,
  owner: null,
  showTimer: 0,
  suppressedOwner: null
};
function icon(name) {
  if (!/^[a-z0-9-]+$/.test(name)) throw new Error(`Invalid Codicon name: ${name}`);
  return `<svg class="codicon" aria-hidden="true"><use href="icons/codicons/sprite.svg#codicon-${name}"></use></svg>`;
}

function octicon(name) {
  if (!/^[a-z0-9-]+$/.test(name)) throw new Error(`Invalid Octicon name: ${name}`);
  return `<svg class="octicon" aria-hidden="true"><use href="icons/octicons/sprite.svg#octicon-${name}-16"></use></svg>`;
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
  captureElements();
  bindEvents();
  await loadBundle();
  refreshPresentation();
});

function captureElements() {
  for (const id of [
    "target-chip", "status-target", "status-surface-tooltip", "close-button", "draft-menu", "export-button", "import-input", "catalog-count", "plan-count",
    "promotion-plan-stage", "promotion-plan-stage-icon", "plan-activity-count",
    "status-excluded", "status-mapped", "status-unmapped", "status-headroom", "preview-status", "save-indicator", "search-input",
    "candidate-list", "candidate-panel", "candidate-sticky-stack", "assessment-panel", "candidate-pane-candidates", "candidate-pane-details", "candidate-sources-panel", "assessment-results-panel", "rule-issues-panel",
    "bulk-actions", "bulk-scope-count", "bulk-add-count", "bulk-update-count", "bulk-actionable-count", "bulk-undo", "bulk-undo-count", "bulk-actions-note",
    "assessment-results-list", "assessment-sticky-stack", "assessment-results-detail", "rule-issues-tab-count", "rule-issues-filters", "rule-issues-list", "rule-issues-detail", "rule-issues-status", "rule-issues-status-count",
    "return-catalog-button", "plan-bulk-undo", "plan-table-head", "plan-table-body", "empty-plan", "capacity-panel", "approval-badge",
    "preview-summary", "preview-tree-resizer", "preview-diff", "preview-payload-diff", "raw-payload-empty", "preview-json", "preview-code",
    "preview-review-toolbar",
    "preview-review-context", "preview-review-toggle", "preview-review-popover", "preview-review-close", "approver-name", "approval-requirements",
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
  elements["plan-bulk-undo"].addEventListener("click", () => undoBulkOperation(getLatestBulkOperation()?.id));
  elements["close-button"].addEventListener("click", closeWorkbench);
  elements["export-button"].addEventListener("click", () => {
    exportDraft();
    elements["draft-menu"].removeAttribute("open");
  });
  elements["import-input"].addEventListener("change", async (event) => {
    await importDraft(event);
    elements["draft-menu"].removeAttribute("open");
  });
  elements["search-input"].addEventListener("input", (event) => updateFilter(event.target.value));
  elements["rule-issues-status"].addEventListener("click", () => setWorkspaceTab("rule-issues"));
  elements["rule-issues-filters"].addEventListener("click", (event) => {
    const filter = event.target.closest("[data-rule-issue-filter]")?.dataset.ruleIssueFilter;
    if (!filter) return;
    state.ruleIssueFilter = filter;
    state.activeRuleIssueKey = null;
    renderRuleIssues();
  });
  elements["rule-issues-list"].addEventListener("click", (event) => {
    const key = event.target.closest("[data-rule-issue-key]")?.dataset.ruleIssueKey;
    if (!key) return;
    state.activeRuleIssueKey = key;
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
  [elements["assessment-panel"], elements["assessment-results-detail"]].forEach((panel) => {
    panel.addEventListener("click", handleDetailBackToTopClick);
    panel.addEventListener("scroll", handleDetailContentScroll, true);
  });
  elements["plan-table-body"].addEventListener("click", (event) => {
    const undo = event.target.closest("[data-plan-undo]");
    if (undo) {
      const candidate = state.candidates.find((item) => item.key === undo.dataset.planUndo);
      if (candidate) undoDecision(candidate);
      return;
    }
    const detail = event.target.closest("[data-plan-detail]");
    if (detail) {
      openPlanCandidate(detail.dataset.planDetail, "rationale");
      return;
    }
    const action = event.target.closest("[data-plan-action]");
    if (action) {
      openPlanCandidate(action.dataset.planAction, "action");
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
  elements["preview-code"].addEventListener("click", handlePreviewReviewClick);
  elements["preview-code"].addEventListener("change", handlePreviewReviewChange);
  elements["approver-name"].addEventListener("input", handleApproverInput);
  elements["approve-export-button"].addEventListener("click", approveAndExport);
  elements["toast-close"].addEventListener("click", dismissNotification);
  document.addEventListener("keydown", (event) => {
    if (event.key === "Escape" && elements.toast.classList.contains("visible")) dismissNotification();
    if (event.key === "Escape") elements["preview-review-popover"].hidden = true;
  });
  window.addEventListener("resize", hideStatusTooltip);
  window.addEventListener("resize", scheduleTruncationTooltips);
  window.addEventListener("resize", () => {
    candidateHierarchicalView?.refreshLayout();
    assessmentHierarchicalView?.refreshLayout();
    setPreviewTreeWidth(Number(elements["preview-tree-resizer"].getAttribute("aria-valuenow")));
    schedulePreviewBodyVirtualizerRefresh();
  });
}

function showWorkbenchTooltip(item, anchorX = item.getBoundingClientRect().left + item.getBoundingClientRect().width / 2) {
  const value = item.dataset.workbenchTooltip || (item.hasAttribute("data-truncation-tooltip") ? item.textContent.trim() : "");
  if (!value) return;

  const tooltip = elements["status-surface-tooltip"];
  tooltip.textContent = value;
  tooltip.style.left = "8px";
  tooltip.style.top = "8px";
  tooltip.classList.add("visible");
  tooltip.setAttribute("aria-hidden", "false");

  const itemRect = item.getBoundingClientRect();
  const tooltipRect = tooltip.getBoundingClientRect();
  const left = Math.floor(Math.min(Math.max(8, anchorX - tooltipRect.width / 2), Math.max(8, window.innerWidth - tooltipRect.width - 8)));
  const below = itemRect.bottom + 6;
  const top = below + tooltipRect.height + 8 <= window.innerHeight
    ? below
    : Math.max(8, itemRect.top - tooltipRect.height - 6);
  tooltip.style.left = `${left}px`;
  tooltip.style.top = `${top}px`;
}

function getWorkbenchTooltipOwner(target) {
  return target.closest?.("[data-workbench-tooltip], [data-truncation-tooltip]")
    || null;
}

function cancelWorkbenchTooltipShow() {
  if (workbenchTooltip.showTimer) window.clearTimeout(workbenchTooltip.showTimer);
  workbenchTooltip.showTimer = 0;
}

function scheduleWorkbenchTooltip(owner, anchorX) {
  cancelWorkbenchTooltipShow();
  workbenchTooltip.owner = owner;
  workbenchTooltip.anchorX = anchorX;
  workbenchTooltip.showTimer = window.setTimeout(() => {
    workbenchTooltip.showTimer = 0;
    if (workbenchTooltip.owner !== owner || workbenchTooltip.suppressedOwner === owner || !owner.matches(":hover, :focus")) return;
    showWorkbenchTooltip(owner, workbenchTooltip.anchorX);
  }, WORKBENCH_TOOLTIP_DELAY_MS);
}

function handleWorkbenchTooltipPointerOver(event) {
  const owner = getWorkbenchTooltipOwner(event.target);
  if (!owner || owner.contains(event.relatedTarget)) return;
  if (workbenchTooltip.suppressedOwner === owner) return;
  workbenchTooltip.suppressedOwner = null;
  scheduleWorkbenchTooltip(owner, event.clientX);
}

function handleWorkbenchTooltipPointerMove(event) {
  const owner = getWorkbenchTooltipOwner(event.target);
  if (owner && workbenchTooltip.owner === owner && workbenchTooltip.showTimer) workbenchTooltip.anchorX = event.clientX;
}

function handleWorkbenchTooltipPointerOut(event) {
  const owner = getWorkbenchTooltipOwner(event.target);
  if (!owner || owner.contains(event.relatedTarget)) return;
  if (workbenchTooltip.suppressedOwner === owner) workbenchTooltip.suppressedOwner = null;
  hideStatusTooltip();
}

function handleWorkbenchTooltipPointerDown(event) {
  const owner = getWorkbenchTooltipOwner(event.target);
  if (!owner) return;
  workbenchTooltip.suppressedOwner = owner;
  hideStatusTooltip();
}

function handleWorkbenchTooltipFocusIn(event) {
  const owner = getWorkbenchTooltipOwner(event.target);
  if (!owner || workbenchTooltip.suppressedOwner === owner || owner.matches(":hover")) return;
  const rect = owner.getBoundingClientRect();
  scheduleWorkbenchTooltip(owner, rect.left + rect.width / 2);
}

function handleWorkbenchTooltipFocusOut(event) {
  if (getWorkbenchTooltipOwner(event.target)) hideStatusTooltip();
}

function hideStatusTooltip() {
  cancelWorkbenchTooltipShow();
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
  const sprites = [
    ["icons/codicons/sprite.svg", "codicon-diff-modified"],
    ["icons/octicons/sprite.svg", "octicon-shield-check-16"]
  ];
  const responses = await Promise.all(sprites.map(([path]) => fetch(path)));
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
  setSaveIndicator("Loading display");
  try {
    await preloadIconSprites();
    const response = await fetch("workbench-display.json", { cache: "no-store" });
    if (!response.ok) throw new Error(`Display request failed with ${response.status}`);
    const display = await response.json();
    validateDisplay(display);
    state.bundle = display;
    state.protectedRules = display.catalog.protectedRules;
    const discoveredCandidates = normalizeDisplayCandidates(display);
    const sessionId = getSessionId(display);
    const existing = await readSession(sessionId);
    state.session = migrateSession(existing, discoveredCandidates) || createSession(sessionId, display);
    autofillApproverName();
    const assessedCandidates = discoveredCandidates.map((candidate) => ({ candidate, assessment: getAssessment(candidate, getDecision(candidate)) }));
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
  const shutdownToken = globalThis.__HOSTED_RULE_WORKBENCH__?.shutdownToken;
  if (!shutdownToken) {
    showToast("Workbench shutdown is unavailable.", true);
    return;
  }
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
  if (!display || display.schemaVersion !== WORKBENCH_DISPLAY_SCHEMA_VERSION || display.kind !== "hosted-rule-workbench-display" || display.readOnly !== true || !/^[a-f0-9]{64}$/.test(display.inputFingerprint)) {
    throw new Error("The Workbench display does not satisfy the read-only display contract.");
  }
  if (!Array.isArray(display.candidates) || !display.catalog || !Array.isArray(display.catalog.rules) || !Array.isArray(display.catalog.protectedRules)) {
    throw new Error("The Workbench display does not contain candidates and a catalog projection.");
  }
  if (!display.guidanceCapacity || display.guidanceCapacity.reportCount !== 8) {
    throw new Error("The Workbench display does not contain all guidance capacity reports.");
  }
  if (!display.reconciliation || display.reconciliation.status !== "ready") {
    throw new Error("The Workbench display does not contain reconciliation status.");
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
      currentHostedCoverage: candidate.assessment.existingCoverage.rationale,
      recommendation: normalizedRecommendation?.action || (reviewState === "excluded" ? "exclude" : "defer"),
      proposedHostedRuleId,
      targetHostedRuleId,
      proposedText: normalizedRecommendation.ruleText,
      hostedCategory,
      guardedTokenDelta: normalizedRecommendation?.guardedTokenDelta || 0
    };
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
      requiresReview: Boolean(normalizedRecommendation?.needsReview) || candidate.assessment.confidence.level !== "high",
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
      catalogMapping: candidate.catalogMapping,
      mappedHostedRules: mappedHostedRuleId ? display.catalog.rules.filter((rule) => rule.id === mappedHostedRuleId) : []
    };
  });
}

function getRuleIndex() {
  return new Map([
    ...state.bundle.catalog.rules.filter((rule) => rule.status === "active").map((rule) => [rule.id, { ...rule, protected: false }]),
    ...state.protectedRules.map((rule) => [rule.id, { ...rule, status: "protected", protected: true }])
  ]);
}

function getRecommendationRetirementRuleIds(candidate) {
  const ruleIds = new Set(candidate.recommendation.retireHostedRuleIds);
  if (candidate.recommendation.action === "retire" && candidate.recommendation.targetHostedId) {
    ruleIds.add(candidate.recommendation.targetHostedId);
  }
  return [...ruleIds].sort();
}

function getDecisionRetirementRuleIds(candidate, decision = getDecision(candidate)) {
  const ruleIds = new Set(decision.retireHostedRuleIds);
  if (decision.action === "retire" && candidate.recommendation.targetHostedId) {
    ruleIds.add(candidate.recommendation.targetHostedId);
  }
  return [...ruleIds].sort();
}

function isActionableRuleIssueRelationship(candidate, sourceRuleId, relatedRuleId, relationship) {
  if (relationship === "conflicts" || relationship === "equivalent") return true;
  const retirementRuleIds = getRecommendationRetirementRuleIds(candidate);
  if (retirementRuleIds.includes(relatedRuleId)) return true;
  return retirementRuleIds.includes(sourceRuleId) && relationship === "assessment-narrows-hosted";
}

function buildRuleIssues() {
  const rulesById = getRuleIndex();
  const issuesByKey = new Map();
  const rank = { contradiction: 3, duplicate: 2, overlap: 1 };
  state.candidates.forEach((candidate) => {
    const manualCheck = getCurrentManualRelationshipCheck(candidate);
    const sourceRuleId = candidate.catalogMapping.hostedRuleId || (manualCheck ? candidate.assessment.proposedHostedRuleId : null);
    if (!sourceRuleId) return;
    if (!rulesById.has(sourceRuleId) && manualCheck) {
      rulesById.set(sourceRuleId, { id: sourceRuleId, text: manualCheck.proposedText, status: "proposed", protected: false });
    }
    if (!rulesById.has(sourceRuleId)) return;
    const coverageEntries = manualCheck ? manualCheck.relationships : candidate.recommendation.relatedHostedCoverage || [];
    coverageEntries.forEach((coverage) => {
      const descriptor = RULE_ISSUE_RELATIONSHIPS[coverage.relationship];
      const relatedRuleId = coverage.hostedRuleId;
      if (!descriptor || sourceRuleId === relatedRuleId || !rulesById.has(relatedRuleId)) return;
      if (!manualCheck && !isActionableRuleIssueRelationship(candidate, sourceRuleId, relatedRuleId, coverage.relationship)) return;
      const ruleIds = [sourceRuleId, relatedRuleId].sort();
      const key = ruleIds.join("::");
      const incoming = {
        key,
        kind: descriptor.kind,
        label: descriptor.label,
        relationship: coverage.relationship,
        sourceRuleId,
        relatedRuleId,
        title: candidate.title,
        rationale: coverage.rationale,
        suggestedConsolidatedText: coverage.suggestedConsolidatedText || "",
        retireHostedRuleIds: getRecommendationRetirementRuleIds(candidate).filter((id) => ruleIds.includes(id)),
        ruleIds,
        rules: ruleIds.map((id) => rulesById.get(id)).sort((left, right) => Number(right.protected) - Number(left.protected) || left.id.localeCompare(right.id)),
        candidateKeys: [candidate.key],
        manualRelationshipCheck: Boolean(manualCheck),
        protectedRuleIds: ruleIds.filter((id) => rulesById.get(id).protected)
      };
      const existing = issuesByKey.get(key);
      if (!existing) {
        issuesByKey.set(key, incoming);
        return;
      }
      existing.candidateKeys = [...new Set([...existing.candidateKeys, candidate.key])].sort();
      existing.retireHostedRuleIds = [...new Set([...existing.retireHostedRuleIds, ...incoming.retireHostedRuleIds])].sort();
      if (rank[incoming.kind] > rank[existing.kind] || (!existing.suggestedConsolidatedText && incoming.suggestedConsolidatedText)) {
        Object.assign(existing, { ...incoming, candidateKeys: existing.candidateKeys, retireHostedRuleIds: existing.retireHostedRuleIds });
      }
    });
  });
  return [...issuesByKey.values()]
    .filter((issue) => !isRuleIssueRecommendationStaged(issue))
    .sort((left, right) => rank[right.kind] - rank[left.kind] || left.key.localeCompare(right.key));
}

function getFilteredRuleIssues() {
  const query = state.queries["rule-issues"].trim().toLowerCase();
  return state.ruleIssues.filter((issue) => {
    if (issue.kind !== state.ruleIssueFilter) return false;
    if (!query) return true;
    return [issue.title, issue.label, issue.rationale, issue.suggestedConsolidatedText, ...issue.ruleIds, ...issue.rules.map((rule) => rule.text)]
      .some((value) => String(value || "").toLowerCase().includes(query));
  });
}

function formatRuleIssueSummary(issues) {
  const counts = Object.fromEntries(RULE_ISSUE_FILTERS.map(([kind]) => [kind, issues.filter((issue) => issue.kind === kind).length]));
  return `${formatCountLabel(issues.length, "rule issue")}: ${formatCountLabel(counts.contradiction, "contradiction")}, ${formatCountLabel(counts.duplicate, "duplicate")}, ${formatCountLabel(counts.overlap, "overlap")}`;
}

function renderRuleIssueFilters() {
  const counts = Object.fromEntries(RULE_ISSUE_FILTERS.map(([kind]) => [kind, state.ruleIssues.filter((issue) => issue.kind === kind).length]));
  const visibleFilters = RULE_ISSUE_FILTERS.filter(([kind]) => counts[kind] > 0);
  if (!visibleFilters.some(([kind]) => kind === state.ruleIssueFilter)) {
    state.ruleIssueFilter = visibleFilters[0]?.[0] || RULE_ISSUE_FILTERS[0][0];
  }
  elements["rule-issues-filters"].innerHTML = visibleFilters.map(([kind, label]) => `
    <button class="candidate-pane-tab clickable ${state.ruleIssueFilter === kind ? "active" : ""}" type="button" role="tab" data-rule-issue-filter="${kind}" aria-selected="${state.ruleIssueFilter === kind}">${escapeHtml(label)} <span>${formatNumber(counts[kind])}</span></button>
  `).join("");
}

function renderRuleReferences(value, ruleIds) {
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
    output += `<span class="rule-reference">${escapeHtml(match)}</span>`;
    offset = matchIndex + match.length;
  }
  return `${output}${escapeHtml(text.slice(offset))}`;
}

function renderRuleIssueIds(ruleIds) {
  return ruleIds.map((id) => `<span class="rule-reference">${escapeHtml(id)}</span>`).join('<span class="rule-issue-id-separator" aria-hidden="true">·</span>');
}

function getRuleIssueRecommendationCandidates(issue) {
  const candidates = issue.candidateKeys.map((key) => state.candidates.find((candidate) => candidate.key === key)).filter(Boolean);
  if (!issue.retireHostedRuleIds.length) return candidates.length ? candidates : null;
  const matches = candidates.filter((candidate) => issue.retireHostedRuleIds.every((ruleId) => getRecommendationRetirementRuleIds(candidate).includes(ruleId)));
  return matches.length ? matches : null;
}

function isRuleIssueRecommendationStaged(issue) {
  const candidates = getRuleIssueRecommendationCandidates(issue);
  return Boolean(candidates?.length) && candidates.every((candidate) => {
    const decision = getDecision(candidate);
    return decision.inPlan && issue.retireHostedRuleIds.every((ruleId) => getDecisionRetirementRuleIds(candidate, decision).includes(ruleId));
  });
}

function renderRuleIssuePlanAction(issue) {
  const candidates = getRuleIssueRecommendationCandidates(issue);
  const staged = isRuleIssueRecommendationStaged(issue);
  const identity = getValidatedCodeOwnerIdentity();
  const unavailableReason = !candidates
    ? "The recommendation cannot be mapped safely to retirement candidates."
    : globalThis.__HOSTED_RULE_WORKBENCH__?.maintainerIdentity?.reason || "A validated Hosted CODEOWNER identity is required.";
  const disabled = staged || !candidates || !identity;
  const tooltip = disabled && !staged ? ` data-workbench-tooltip="${escapeHtml(unavailableReason)}"` : "";
  return `<div class="rule-recommendation-actions"><button class="button primary rule-issue-plan-action ${disabled ? "" : "clickable"}" type="button" data-rule-issue-plan="${escapeHtml(issue.key)}" ${disabled ? "disabled" : ""}${tooltip}>${icon(staged ? "pass-filled" : "new-session")}<span class="button-label">${staged ? "Added to Promotion Plan" : "Add to Promotion Plan"}</span></button></div>`;
}

function stageRuleIssueRecommendation(issue) {
  const identity = getValidatedCodeOwnerIdentity();
  if (!identity) {
    showToast(globalThis.__HOSTED_RULE_WORKBENCH__?.maintainerIdentity?.reason || "A validated Hosted CODEOWNER identity is required.", true);
    return;
  }
  const candidates = getRuleIssueRecommendationCandidates(issue);
  if (!candidates?.length) {
    showToast("The recommendation cannot be mapped safely to retirement candidates.", true);
    return;
  }
  const updatedAt = toUtcTimestamp();
  const rationale = `Reviewed Rule Issues recommendation for ${issue.ruleIds.join(" and ")}: ${issue.rationale}`.slice(0, DECISION_RATIONALE_MAX_LENGTH);
  candidates.forEach((candidate) => {
    const { assessment, ...decision } = getDecision(candidate);
    const primaryAction = issue.retireHostedRuleIds.length
      ? isPromotionAction(candidate.recommendation.action) ? candidate.recommendation.action : "no-change"
      : "defer";
    removeCandidateFromBulkOperations(candidate.key);
    state.session.decisions[candidate.key] = {
      ...decision,
      action: primaryAction,
      rationale,
      proposedText: candidate.recommendation.ruleText,
      retireHostedRuleIds: [...candidate.recommendation.retireHostedRuleIds],
      ...createPlanMembership("manual"),
      sourceHash: candidate.hash,
      updatedAt
    };
  });
  state.session.updatedAt = updatedAt;
  persistSession();
  syncCandidateTreeRows();
  renderBulkActions();
  renderDecisionOutputs();
  renderRuleIssues();
  showToast(`${formatCountLabel(candidates.length, "Resolution")} added to the promotion plan.`);
}

function handleRuleIssueDetailClick(event) {
  const dismiss = event.target.closest("[data-dismiss-rule-issue-banner]");
  if (dismiss) {
    state.dismissedRuleIssueBannerKeys.add(dismiss.dataset.dismissRuleIssueBanner);
    dismiss.closest(".rule-issue-banner")?.remove();
    return;
  }
  const planAction = event.target.closest("[data-rule-issue-plan]");
  if (!planAction) return;
  const issue = state.ruleIssues.find((item) => item.key === planAction.dataset.ruleIssuePlan);
  if (issue) stageRuleIssueRecommendation(issue);
}

function renderRuleIssueRule(rule, issue) {
  const status = rule.protected ? "Protected" : capitalize(rule.status);
  const recommendation = issue.retireHostedRuleIds.length
    ? issue.retireHostedRuleIds.includes(rule.id) ? "retire" : "keep"
    : "";
  return `
    <section class="rule-issue-rule ${recommendation ? `recommend-${recommendation}` : ""}">
      <h3><span class="rule-reference">${escapeHtml(rule.id)}</span><span class="catalog-status ${escapeHtml(rule.status)}">${escapeHtml(status)}</span></h3>
      <div class="rule-issue-rule-body"><p>${renderRuleReferences(rule.text, issue.ruleIds)}</p></div>
    </section>
  `;
}

function renderRuleIssueDetail(issue) {
  if (!issue) {
    elements["rule-issues-detail"].innerHTML = renderPreviewEmptyState("warning-compact", "Select a Rule Issue", "Relationship evidence, affected rules, consolidated wording, and advisory actions will appear here.");
    return;
  }
  const protectedNotice = issue.protectedRuleIds.length
    ? "Protected guidance is immutable. Both rules remain generated until a maintainer explicitly changes lifecycle state."
    : "Both rules remain generated until a maintainer explicitly changes lifecycle state.";
  const retirementText = issue.retireHostedRuleIds.length
    ? `Review retirement of ${issue.retireHostedRuleIds.map((id) => `<span class="rule-reference">${escapeHtml(id)}</span>`).join(", ")} and the proposed wording in the Promotion Plan.`
    : "Reconciliation could not produce a complete lifecycle action. Maintainer input is required in the Promotion Plan.";
  const banner = state.dismissedRuleIssueBannerKeys.has(issue.key) ? "" : `
    <div class="rule-issue-banner ${escapeHtml(issue.kind)}">${icon(issue.kind === "contradiction" ? "chat-sparkle-error" : "warning")}<div><strong>${escapeHtml(getRuleIssueBannerTitle(issue))}</strong><p>${escapeHtml(protectedNotice)}</p></div><button class="rule-issue-banner-dismiss clickable" type="button" data-dismiss-rule-issue-banner="${escapeHtml(issue.key)}" aria-label="Dismiss issue message" data-workbench-tooltip="Dismiss">${icon("close")}</button></div>`;
  elements["rule-issues-detail"].innerHTML = `
    ${banner}
    <div class="rule-issue-comparison">${issue.rules.map((rule) => renderRuleIssueRule(rule, issue)).join("")}</div>
    <section class="rule-issue-assessment"><span class="section-label">Assessment:</span><p>${renderRuleReferences(issue.rationale, issue.ruleIds)}</p></section>
    ${issue.suggestedConsolidatedText ? `<section class="rule-issue-suggestion"><h3>Suggested Consolidated Wording</h3><p>${renderRuleReferences(issue.suggestedConsolidatedText, issue.ruleIds)}</p></section>` : ""}
    <span class="section-label rule-issue-recommendation-label">Recommended Maintainer Action:</span>
    <section class="rule-issue-recommendation"><p>${retirementText}</p>${renderRuleIssuePlanAction(issue)}</section>
  `;
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

function getRuleIssueBannerTitle(issue) {
  const descriptor = RULE_ISSUE_RELATIONSHIPS[issue.relationship];
  const sourceRule = issue.rules.find((rule) => rule.id === issue.sourceRuleId);
  const relatedRule = issue.rules.find((rule) => rule.id === issue.relatedRuleId);
  const protectedRule = issue.rules.find((rule) => rule.protected);
  const activeRule = issue.rules.find((rule) => !rule.protected);
  if (!descriptor || !sourceRule || !relatedRule) return issue.label;

  if (protectedRule && activeRule) {
    if (descriptor.semantic === "equivalent") return "Protected Guidance Duplicates This Active Rule";
    if (descriptor.semantic === "partial") return "Protected Guidance Partially Overlaps This Active Rule";
    if (descriptor.semantic === "conflict") return "Protected Guidance Conflicts With This Active Rule";
    const protectedBreadth = protectedRule.id === sourceRule.id
      ? descriptor.sourceBreadth
      : descriptor.sourceBreadth === "broader" ? "narrower" : "broader";
    return protectedBreadth === "broader"
      ? "Broader Protected Guidance Overlaps This Active Rule"
      : "This Active Rule Broadens Protected Guidance";
  }

  if (descriptor.semantic === "equivalent") return "These Active Rules Duplicate Each Other";
  if (descriptor.semantic === "partial") return "These Active Rules Partially Overlap";
  if (descriptor.semantic === "conflict") return "These Active Rules Conflict";
  return descriptor.sourceBreadth === "broader"
    ? "One Active Rule Broadens Another Active Rule"
    : "One Active Rule Narrows Another Active Rule";
}

function renderRuleIssues() {
  if (!elements["rule-issues-list"]) return;
  renderRuleIssueFilters();
  const issues = getFilteredRuleIssues();
  if (!issues.some((issue) => issue.key === state.activeRuleIssueKey)) state.activeRuleIssueKey = issues[0]?.key || null;
  if (!issues.length) {
    elements["rule-issues-list"].innerHTML = renderPreviewEmptyState("pass-compact", "No Rule Issues", "No rule relationships match the current filter and search.");
    renderRuleIssueDetail(null);
    return;
  }
  elements["rule-issues-list"].innerHTML = issues.map((issue) => `
    <button class="rule-issue-row clickable ${issue.key === state.activeRuleIssueKey ? "active" : ""}" type="button" data-rule-issue-key="${escapeHtml(issue.key)}" aria-pressed="${issue.key === state.activeRuleIssueKey}">
      <span class="rule-issue-row-heading"><strong>${escapeHtml(formatRuleIssueTitle(issue.title))}</strong><span class="rule-issue-kind ${escapeHtml(issue.kind)} status-badge ${issue.kind === "contradiction" ? "excluded" : "warning"} type-compact">${escapeHtml(capitalize(issue.kind))}</span></span>
      <span class="rule-issue-ids">${renderRuleIssueIds(issue.ruleIds)}</span>
    </button>
  `).join("");
  renderRuleIssueDetail(issues.find((issue) => issue.key === state.activeRuleIssueKey));
}

function getSessionId(display) {
  return display.inputFingerprint;
}

function createSession(id, display) {
  const timestamp = toUtcTimestamp();
  return {
    schemaVersion: SESSION_SCHEMA_VERSION,
    id,
    createdAt: timestamp,
    updatedAt: timestamp,
    inputFingerprint: display.inputFingerprint,
    approverName: "",
    decisions: {},
    manualRelationshipChecks: {},
    applicabilityOverrides: {},
    bulkOperations: []
  };
}

function migrateSession(session, candidates) {
  if (!session) return null;
  if (session.inputFingerprint !== session.id) return null;
  if (session.schemaVersion === 5) {
    return { ...session, schemaVersion: SESSION_SCHEMA_VERSION, manualRelationshipChecks: {} };
  }
  if (session.schemaVersion !== SESSION_SCHEMA_VERSION) return null;
  return { ...session, manualRelationshipChecks: session.manualRelationshipChecks || {} };
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
  const retireHostedRuleIds = candidate.recommendation.retireHostedRuleIds.filter((ruleId) => saved.retireHostedRuleIds.includes(ruleId));
  const allowedActions = getAllowedActions(candidate, proposedText);
  if (!allowedActions.includes(saved.action) || !isValidPlanMembership(saved, candidate.key)) return defaultDecision(candidate);
  return {
    ...saved,
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

function getManualRelationshipCheck(candidate, proposedText = getDecision(candidate).proposedText) {
  const check = state.session.manualRelationshipChecks?.[candidate.key];
  return check && check.proposedText === proposedText ? check : null;
}

function getCurrentManualRelationshipCheck(candidate, proposedText = getDecision(candidate).proposedText) {
  if (!hasMaintainerEditedRuleText(candidate, proposedText)) return null;
  const check = getManualRelationshipCheck(candidate, proposedText);
  return check?.status === "current" ? check : null;
}

function requiresManualRelationshipCheck(candidate, proposedText = getDecision(candidate).proposedText) {
  return hasMaintainerEditedRuleText(candidate, proposedText) && !getCurrentManualRelationshipCheck(candidate, proposedText);
}

function encodeBase64Utf8(value) {
  const bytes = new TextEncoder().encode(value);
  let binary = "";
  bytes.forEach((byte) => { binary += String.fromCharCode(byte); });
  return btoa(binary);
}

function renderManualRelationshipStatus(candidate, proposedText) {
  if (!hasMaintainerEditedRuleText(candidate, proposedText)) return '<span class="relationship-check-status status-badge neutral">Reconciled</span>';
  const check = getManualRelationshipCheck(candidate, proposedText);
  if (activeRelationshipChecks.has(candidate.key) || check?.status === "pending") return '<span class="relationship-check-status status-badge warning">Checking relationships</span>';
  if (check?.status === "current") return `<span class="relationship-check-status status-badge ${check.relationships.length ? "warning" : "success"}">${check.relationships.length ? formatCountLabel(check.relationships.length, "rule issue") : "Relationships current"}</span>`;
  if (check?.status === "failed") return '<span class="relationship-check-status status-badge excluded">Relationship check failed</span>';
  return '<span class="relationship-check-status status-badge warning">Relationship check required</span>';
}

function syncProposedRuleControls(candidate) {
  const textarea = elements["assessment-panel"].querySelector('[data-decision-field="proposedText"]');
  const save = elements["assessment-panel"].querySelector("[data-proposed-text-save]");
  const status = elements["assessment-panel"].querySelector(".relationship-check-status");
  if (!textarea || !save) return;
  const decision = getDecision(candidate);
  const dirty = textarea.value !== decision.proposedText;
  const check = getManualRelationshipCheck(candidate, textarea.value);
  const retryable = !dirty && hasMaintainerEditedRuleText(candidate, textarea.value) && check?.status === "failed";
  save.disabled = activeRelationshipChecks.has(candidate.key) || (!dirty && !retryable);
  save.setAttribute("aria-label", retryable ? "Retry proposed Hosted rule relationship check" : "Save proposed Hosted rule");
  setWorkbenchTooltip(save, save.getAttribute("aria-label"));
  if (status) status.outerHTML = renderManualRelationshipStatus(candidate, textarea.value);
}

async function reconcileManualRuleText(candidate, proposedText) {
  const existing = getManualRelationshipCheck(candidate, proposedText);
  if (!hasMaintainerEditedRuleText(candidate, proposedText) || existing?.status === "current") return true;
  activeRelationshipChecks.add(candidate.key);
  state.session.manualRelationshipChecks[candidate.key] = {
    status: "pending",
    proposedText,
    checkedAt: toUtcTimestamp(),
    relationships: []
  };
  state.session.updatedAt = toUtcTimestamp();
  await persistSession();
  syncProposedRuleControls(candidate);
  setSaveIndicator("Checking relationships...");
  try {
    const request = {
      candidateKey: candidate.key,
      ruleId: candidate.assessment.proposedHostedRuleId,
      ruleTextBase64: encodeBase64Utf8(proposedText),
      category: candidate.recommendation.category,
      placement: candidate.recommendation.placement
    };
    const response = await fetch("/reconcile-rule", {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "X-Workbench-Operation-Token": globalThis.__HOSTED_RULE_WORKBENCH__?.operationToken || ""
      },
      body: JSON.stringify({ payloadBase64: encodeBase64Utf8(JSON.stringify(request)) })
    });
    if (!response.ok) throw new Error(`Relationship check failed with ${response.status}`);
    const result = await response.json();
    if (result.schemaVersion !== 1 || !Array.isArray(result.relationships) || !/^[0-9a-f]{64}$/.test(result.ruleTextSha256 || "")) {
      throw new Error("Relationship check returned an invalid result");
    }
    state.session.manualRelationshipChecks[candidate.key] = {
      status: "current",
      proposedText,
      ruleTextSha256: result.ruleTextSha256,
      checkedAt: toUtcTimestamp(),
      relationships: result.relationships
    };
    state.session.updatedAt = toUtcTimestamp();
    await persistSession();
    state.ruleIssues = buildRuleIssues();
    renderRuleIssues();
    renderDecisionOutputs();
    showToast(result.relationships.length ? `${formatCountLabel(result.relationships.length, "Rule issue")} found.` : "Proposed Hosted rule saved; no relationship issues found.");
    return true;
  }
  catch (error) {
    state.session.manualRelationshipChecks[candidate.key] = {
      status: "failed",
      proposedText,
      checkedAt: toUtcTimestamp(),
      relationships: []
    };
    state.session.updatedAt = toUtcTimestamp();
    await persistSession();
    showToast(error.message, true);
    return false;
  }
  finally {
    activeRelationshipChecks.delete(candidate.key);
    syncProposedRuleControls(candidate);
  }
}

function isActionableDecision(decision) {
  return isPromotionAction(decision.action) || decision.retireHostedRuleIds.length > 0;
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
  return `<span class="catalog-status ${escapeHtml(catalogStatus.key)}">${escapeHtml(catalogStatus.label)}</span>`;
}

function renderDetailHeaderActions(statuses) {
  return `
    <div class="detail-header-actions">
      <span class="assessment-title-statuses">${statuses}</span>
      <button class="icon-button clickable detail-back-to-top" type="button" data-detail-back-to-top aria-label="Back to top" data-workbench-tooltip="Back to top" disabled>${icon("arrow-circle-up")}</button>
    </div>
  `;
}

function renderMappedHostedRules(catalogStatus, includePlacements = false) {
  if (!catalogStatus.rules.length) return "";
  const mappedRules = catalogStatus.rules.map((rule) => {
    const placements = rule.placements?.length
      ? rule.placements.map((placement) => `${placement.surfaceId} / ${placement.sectionHeading}`).join("; ")
      : "Placement unavailable in source bundle";
    return `<div class="overlap-item subcontext-container"><div><strong>${escapeHtml(rule.id)}</strong><span class="catalog-status ${escapeHtml(rule.status)}">${escapeHtml(capitalize(rule.status))}</span></div><p>${escapeHtml(rule.text)}</p>${includePlacements ? `<small>${escapeHtml(placements)}</small>` : ""}</div>`;
  }).join("");
  return `<div class="section-block"><span class="section-label">Mapped Hosted Rules:</span><div class="overlap-list">${mappedRules}</div></div>`;
}

function getAllowedActions(candidate, proposedText = defaultDecision(candidate).proposedText) {
  const catalogStatus = getCatalogStatus(candidate).key;
  if (catalogStatus === "mapped") {
    const actions = ["no-change"];
    if (hasHostedTextChange(candidate, proposedText)) actions.push("update");
    return [...actions, "retire", "defer"];
  }
  if (catalogStatus === "retired") return ["no-change", "restore", "defer"];
  return ["no-change", "add", "exclude", "defer"];
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

function getAssessment(candidate, decision) {
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

function updateDecision(candidate, changes) {
  const current = getDecision(candidate);
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
  removeCandidateFromBulkOperations(candidate.key);
  saveDecision(candidate, { ...maintainerDecision, ...createPlanMembership() });
}

function removeCandidateFromBulkOperations(candidateKey) {
  state.session.bulkOperations = state.session.bulkOperations
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

function saveDecision(candidate, decision) {
  if (decision) {
    const { assessment, ...maintainerDecision } = decision;
    state.session.decisions[candidate.key] = {
      ...maintainerDecision,
      sourceHash: candidate.hash,
      updatedAt: toUtcTimestamp()
    };
  } else {
    delete state.session.decisions[candidate.key];
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
    delete state.session.decisions[candidate.key];
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
  state.ruleIssues = buildRuleIssues();
  renderMetrics();
  renderPlan();
  renderCapacity();
  renderPreview();
  renderCounts();
  setSaveIndicator(`Saved ${formatTime(state.session.updatedAt)}`);
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
  return Math.ceil(estimated * 1.25);
}

function getAssessmentTokenValue(candidate, assessment, decision = getDecision(candidate)) {
  if (!getApplicabilityOverride(candidate) || assessment.guardedTokenDelta !== 0) return assessment.guardedTokenDelta;
  return estimateGuardedTokens(decision.proposedText || candidate.text);
}

function getActionTokenDelta(candidate, action, decision = getDecision(candidate)) {
  if (!isPromotionAction(action)) return 0;
  if (action === "retire") return -estimateGuardedTokens(getCurrentHostedText(candidate));
  const assessment = getAssessment(candidate, decision);
  if (!assessment) return 0;
  if (assessment.guardedTokenDelta !== 0) return assessment.guardedTokenDelta;
  const proposedTokens = estimateGuardedTokens(decision.proposedText || assessment.proposedText || candidate.text);
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
  state.ruleIssues = buildRuleIssues();
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
  setSaveIndicator(`Saved ${formatTime(state.session.updatedAt)}`);
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
    elements["status-target"].textContent = targetLabel;
    elements["status-target"].removeAttribute("title");
    elements["status-target"].removeAttribute("data-truncation-tooltip");
    elements["target-chip"].classList.toggle("sync-behind", behindBy > 0);
    elements["target-chip"].dataset.workbenchTooltip = [targetLabel, ...syncIndicators].join(" | ");
    elements["target-chip"].setAttribute("aria-label", `${targetLabel}.${behindBy > 0 ? ` ${behindBy} commits behind ${target.upstreamRepository} ${target.upstreamBranch}.` : ""}${aheadBy > 0 ? ` ${aheadBy} commits ahead.` : ""}`);
    return;
  }
  elements["status-target"].textContent = "Target unavailable";
  elements["target-chip"].classList.remove("sync-behind");
  elements["target-chip"].dataset.workbenchTooltip = target?.reason || "Promotion target could not be resolved";
  elements["target-chip"].setAttribute("aria-label", elements["target-chip"].dataset.workbenchTooltip);
}

function renderMetrics() {
  const excludedCount = getActiveExcludedCandidates().length;
  const capacity = getGuidanceCapacityProjection();
  elements["status-excluded"].textContent = formatNumber(excludedCount);
  elements["status-mapped"].textContent = formatNumber(state.candidates.filter((candidate) => getCatalogStatus(candidate).key === "mapped").length);
  elements["status-unmapped"].textContent = formatNumber(state.candidates.filter((candidate) => getCatalogStatus(candidate).key === "unmapped").length);
  elements["status-headroom"].textContent = formatNumber(capacity.projectedHeadroomTokens);
  const issueCount = state.ruleIssues.length;
  elements["rule-issues-status"].hidden = false;
  elements["rule-issues-status"].classList.toggle("has-issues", issueCount > 0);
  elements["rule-issues-status-count"].textContent = formatNumber(issueCount);
  const issueSummary = formatRuleIssueSummary(state.ruleIssues);
  elements["rule-issues-status"].dataset.workbenchTooltip = issueSummary;
  elements["rule-issues-status"].setAttribute("aria-label", `Open ${issueSummary}`);
}

function getFilteredCandidates() {
  const query = state.queries["candidate-sources"].trim().toLowerCase();
  return state.candidates.filter((candidate) => {
    if (!query) return true;
    return [getEffectiveHostedRuleId(candidate), candidate.id, candidate.title, candidate.sourceId, candidate.sourceTitle, candidate.sourcePath, candidate.text, candidate.category, candidate.sourceLabel]
      .some((value) => String(value || "").toLowerCase().includes(query));
  });
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
      && recommendations.includes(assessment.recommendation)
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
  const operation = {
    id: crypto.randomUUID(),
    createdAt: toUtcTimestamp(),
    action: recommendationScope,
    candidateKeys: candidates.map((candidate) => candidate.key)
  };
  state.session.bulkOperations.push(operation);
  candidates.forEach((candidate) => {
    const { assessment, ...decision } = getDecision(candidate);
    state.session.decisions[candidate.key] = {
      ...decision,
      action: assessment.recommendation,
      rationale: getBulkDecisionRationale(candidate, assessment.recommendation),
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
    delete state.session.decisions[key];
    removed += 1;
  });
  state.session.bulkOperations = state.session.bulkOperations.filter((item) => item.id !== operation.id);
  state.session.updatedAt = toUtcTimestamp();
  persistSession();
  renderBulkSelectionOutputs();
  showToast(`${formatCountLabel(removed, "Candidate")} removed by bulk Undo.`);
}

function getCandidateDecoration(candidate) {
  if (!getDecision(candidate).inPlan) return null;
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
  return `<span class="status-badge neutral count-badge type-compact"${tooltip}>${formatCountLabel(count, singular)}</span>`;
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
    rowHeight: 40,
    expanded: true,
    data: { sectionKey, override },
    children: sortCandidates(candidates, getCandidateSort(sectionKey)).map((candidate) => ({
      id: `candidate:leaf:${candidate.key}`,
      kind: "leaf",
      rowHeight: 40,
      stickyEligible: false,
      data: { candidate, override }
    }))
  }];
}

function buildCandidateFolderNode({ id, label, sourceType, candidates, sectionKey, override = false, expandedByDefault = false, extraClass = "" }) {
  return {
    id,
    kind: "folder",
    rowHeight: 40,
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
  const overrideCandidates = state.candidates.filter((candidate) => getApplicabilityOverride(candidate));
  const regularCandidates = state.candidates.filter((candidate) => !getApplicabilityOverride(candidate));
  const query = state.queries["candidate-sources"].trim().toLowerCase();
  const protectedRules = state.protectedRules.filter((rule) => !query || [rule.id, rule.title, rule.text, rule.surfaceId, rule.provenance, rule.protectionReason, rule.sourcePath]
    .some((value) => String(value || "").toLowerCase().includes(query)));
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
      rowHeight: 40,
      expanded: getCandidateExpansion(`candidate:protected-folder:${surfaceId}`),
      data: { label: capitalize(surfaceId), rules },
      children: [{
        id: `candidate:protected-header:${surfaceId}`,
        kind: "protected-header",
        rowHeight: 40,
        expanded: true,
        data: { sectionKey: `protected:${surfaceId}` },
        children: sortProtectedRules(rules, getCandidateSort(`protected:${surfaceId}`)).map((rule) => ({
          id: `candidate:protected-leaf:${rule.id}`,
          kind: "protected-leaf",
          rowHeight: 40,
          stickyEligible: false,
          data: { rule }
        }))
      }]
    }));
    nodes.push({
      id: overrideRootId,
      kind: "source",
      rowHeight: 40,
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
          rowHeight: 40,
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
      rowHeight: 40,
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
    ? `<span class="source-provenance-pill type-compact" data-workbench-tooltip="${escapeHtml(provenanceLabel)}">${escapeHtml(provenanceLabel)}</span>`
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
    if (sort.field === "impact") return calculateImpact(assessment.factors);
    if (sort.field === "cost") return getCandidateTokenValue(candidate, assessment);
    return formatRecommendation(assessment.recommendation);
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
      rowHeight: 40,
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
            rowHeight: 40,
            expanded: getAssessmentExpansion(categoryId, Boolean(state.queries["assessment-results"])),
            data: { label: formatHostedCategory(category), candidates: members },
            children: [{
              id: `assessment:header:${sourceType}:${category}`,
              kind: "header",
              rowHeight: 40,
              expanded: true,
              data: { sectionKey },
              children: sortAssessmentCandidates(members, getAssessmentSort(sectionKey)).map((candidate) => ({
                id: `assessment:leaf:${candidate.key}`,
                kind: "leaf",
                rowHeight: 40,
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
        ${icon("folder")}${renderSourceSummaryLabel(sourceType, label)}<span class="status-badge neutral count-badge type-compact">${formatNumber(candidates.length)} Excluded</span>
      </button>
    `);
  }
  if (node.kind === "category") {
    const { candidates, label } = node.data;
    return elementFromHtml(`
      <button class="hierarchical-parent-row candidate-folder-row clickable" type="button" data-hierarchical-toggle aria-expanded="${node.expanded}">
        ${icon("folder")}<span class="candidate-parent-label"><strong>${escapeHtml(label)}</strong></span><span class="status-badge neutral count-badge type-compact">${formatCountLabel(candidates.length, "Excluded")}</span>
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
    if (sort.field === "recommendation") return formatRecommendation(candidate.assessment.recommendation);
    return getApplicabilityOverride(candidate) ? "contested" : "none";
  };
  return [...candidates].sort((left, right) => {
    const compared = collator.compare(value(left), value(right));
    const directed = sort.direction === "ascending" ? compared : -compared;
    return directed || collator.compare(getEffectiveHostedRuleId(left), getEffectiveHostedRuleId(right));
  });
}

function renderAssessmentResultRow(candidate) {
  const assessment = candidate.assessment;
  const override = getApplicabilityOverride(candidate);
  const overrideStatus = override
    ? `<button class="status-badge warning assessment-override-pill clickable" type="button" data-assessment-override-detail="${escapeHtml(candidate.key)}" aria-label="Open Maintainer Override for ${escapeHtml(getEffectiveHostedRuleId(candidate))}">Contested</button>`
    : `<span class="status-badge neutral assessment-override-pill">None</span>`;
  return `
    <div class="assessment-result-row clickable ${candidate.key === state.assessmentActiveKey ? "active" : ""}" role="button" tabindex="0" data-assessment-key="${escapeHtml(candidate.key)}" ${candidate.key === state.assessmentActiveKey ? 'aria-current="true"' : ""}>
      <span class="candidate-tree-copy"><strong>${escapeHtml(getEffectiveHostedRuleId(candidate))}</strong><small>${escapeHtml(candidate.title)}</small></span>
      <span class="assessment-result-summary"><span class="candidate-lifecycle ${escapeHtml(candidate.state)}">${escapeHtml(capitalize(candidate.state))}</span><span class="recommendation-badge ${escapeHtml(assessment.recommendation)}">${escapeHtml(formatRecommendation(assessment.recommendation))}</span><span class="assessment-override-cell">${overrideStatus}</span></span>
    </div>
  `;
}

function renderAssessmentResultDetail() {
  const candidate = state.assessedCandidates.find((item) => item.key === state.assessmentActiveKey);
  if (!candidate) {
    elements["assessment-results-detail"].innerHTML = `<div class="empty-state">${icon("checklist")}<h2>Select an Assessment Result</h2><p>The source rule, applicability decision, AI rationale, and Hosted coverage will appear here.</p></div>`;
    return;
  }
  const assessment = candidate.assessment;
  const eligible = assessment.hostedApplicable;
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
        <span class="status-badge ${eligible ? "success" : "excluded"}">${eligible ? "Eligible" : "Excluded"}</span>
        ${override ? `<button class="status-badge warning clickable" type="button" data-override-jump="${escapeHtml(candidate.key)}" aria-label="Go to Maintainer Override" data-workbench-tooltip="Go to Maintainer Override">Contested</button>` : ""}
        ${included ? `<button class="status-badge success clickable" type="button" data-override-jump="${escapeHtml(candidate.key)}" aria-label="Go to Maintainer Override" data-workbench-tooltip="Go to Maintainer Override">Maintainer Included</button>` : ""}
        ${renderCatalogStatusBadge(catalogStatus)}
      `)}
    </div>
    <div class="assessment-content scroll-surface">
      <div class="section-block"><span class="section-label">Source Rule:</span><pre class="evidence-box scroll-surface">${escapeHtml(candidate.text)}</pre>${candidate.sourceRationale ? `<div class="assessment-rationale proposal-rationale"><strong>Proposal rationale</strong><p>${escapeHtml(candidate.sourceRationale)}</p></div>` : ""}</div>
      ${renderMappedHostedRules(catalogStatus)}
      <div class="section-block"><span class="section-label">Applicability Decision:</span><div class="ai-evaluation-summary subcontext-container"><div class="ai-evaluation-heading"><strong>${eligible ? "Eligible for candidate catalog" : "Excluded from candidate catalog"}</strong><span class="recommendation-badge ${escapeHtml(assessment.recommendation)}">Recommend ${escapeHtml(formatRecommendation(assessment.recommendation))}</span></div><p>${escapeHtml(assessment.applicabilityRationale)}</p></div></div>
      <div class="section-block"><span class="section-label">AI Evaluation:</span><h3>${escapeHtml(assessment.summary)}</h3><p class="coverage-summary">${escapeHtml(assessment.impactDescription)}</p>${renderPriorityAssessment(assessment)}</div>
      <div class="section-block"><span class="section-label">Related Hosted Coverage:</span><p class="coverage-summary evidence-summary-box subcontext-container">${escapeHtml(assessment.currentHostedCoverage)}</p></div>
      <div class="section-block"><span class="section-label">Proposed Hosted Rule:</span><div class="overlap-item subcontext-container"><div><strong>${escapeHtml(assessment.proposedHostedRuleId)}</strong><span class="status-badge neutral">Generated</span></div><p>${escapeHtml(assessment.proposedText)}</p></div></div>
      ${renderApplicabilityOverride(candidate)}
    </div>
  `;
}

function renderApplicabilityOverride(candidate) {
  const override = getApplicabilityOverride(candidate);
  const identity = globalThis.__HOSTED_RULE_WORKBENCH__?.maintainerIdentity;
  if (override) {
    const editing = state.assessmentOverrideEditingKey === candidate.key;
    const fieldId = `saved-override-rationale-${candidate.key}`;
    const actions = editing
      ? `<button class="titlebar-icon clickable rationale-save" type="button" data-override-save aria-label="Apply Override Rationale" data-workbench-tooltip="Apply Override Rationale" disabled>${icon("git-stash-apply")}</button><button class="titlebar-icon clickable" type="button" data-override-edit-cancel aria-label="Cancel Override Rationale Changes" data-workbench-tooltip="Cancel Override Rationale Changes">${icon("close")}</button>`
      : `<button class="titlebar-icon clickable" type="button" data-override-edit aria-label="Edit Override Rationale" data-workbench-tooltip="Edit Override Rationale">${icon("edit")}</button><button class="titlebar-icon clickable" type="button" data-override-remove aria-label="Remove Override" data-workbench-tooltip="Remove Override">${icon("discard")}</button>`;
    return `
      <div class="section-block maintainer-override" data-override-key="${escapeHtml(candidate.key)}">
        <span class="section-label">Maintainer Override:</span>
        <div class="override-record subcontext-container">
          <div class="override-rationale">
            <span class="rationale-heading"><label class="control-subtitle" for="${escapeHtml(fieldId)}">Override Rationale:</label><span class="override-record-actions">${actions}</span></span>
            <textarea id="${escapeHtml(fieldId)}" class="scroll-surface" maxlength="${OVERRIDE_RATIONALE_MAX_LENGTH}" data-saved-override-rationale ${editing ? "" : "readonly"}>${escapeHtml(override.rationale)}</textarea>
            ${editing ? `<small class="rationale-limit">${override.rationale.length} / ${OVERRIDE_RATIONALE_MAX_LENGTH} characters</small>` : ""}
          </div>
          <small class="override-record-audit">Last saved by @${escapeHtml(override.recordedBy.login)} on ${escapeHtml(formatTimestamp(override.recordedAt))}. The original AI exclusion remains in this audit.</small>
        </div>
        <div class="read-only-boundary">${icon("lock")}<span>The AI assessment is read-only. This provisional maintainer correction does not erase the original result.</span></div>
      </div>
    `;
  }
  const canOverride = Boolean(getValidatedCodeOwnerIdentity());
  const reason = canOverride ? "" : identity?.reason || "GitHub CLI authentication and Hosted CODEOWNER membership are required.";
  return `
    <div class="section-block maintainer-override" data-override-key="${escapeHtml(candidate.key)}">
      <span class="section-label">Maintainer Override:</span>
      <div class="override-summary subcontext-container">
        <div><strong>Disagree with this exclusion?</strong><p>Contest the AI applicability decision and record a separate provisional maintainer correction.</p>${reason ? `<small>${escapeHtml(reason)}</small>` : ""}</div>
        <button class="button warning-action clickable" type="button" data-override-open ${canOverride ? "" : "disabled"}>${icon("chat-sparkle-error")}Contest Assessment</button>
      </div>
      <div class="override-form subcontext-container" hidden>
        <span class="control-subtitle">Corrected Outcome:</span>
        <label class="override-outcome clickable"><input type="radio" name="corrected-outcome" value="eligible" checked><span>Eligible for Candidate Sources</span></label>
        <label class="override-rationale"><span class="rationale-heading"><span class="control-subtitle">Override Rationale:</span><span class="override-inline-actions"><button class="titlebar-icon clickable" type="button" data-override-apply aria-label="Apply Override" data-workbench-tooltip="Apply Override" disabled>${icon("git-stash-apply")}</button><button class="titlebar-icon clickable" type="button" data-override-cancel aria-label="Cancel Override" data-workbench-tooltip="Cancel Override">${icon("close")}</button></span></span><textarea class="scroll-surface" maxlength="${OVERRIDE_RATIONALE_MAX_LENGTH}" aria-describedby="override-rationale-limit" placeholder="Briefly explain why the AI exclusion is incorrect."></textarea><small id="override-rationale-limit" class="rationale-limit">0 / ${OVERRIDE_RATIONALE_MAX_LENGTH} characters</small></label>
        <p class="override-audit-note">The original AI result remains in the assessment audit. This provisional override records the corrected outcome, rationale, authenticated maintainer, and timestamp.</p>
      </div>
      <div class="read-only-boundary">${icon("lock")}<span>The AI assessment is read-only. A maintainer override records a separate correction without erasing the original result.</span></div>
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
  const impact = calculateImpact(assessment.factors);
  const catalogStatus = getCatalogStatus(candidate);
  const inPlan = decision.inPlan;
  const decoration = getCandidateDecoration(candidate);
  return `
    <div class="candidate-tree-row clickable ${candidate.key === state.activeKey ? "active" : ""} ${inPlan ? "in-plan" : ""} ${decoration ? `candidate-decoration-${decoration.status}` : ""}" role="button" tabindex="0" data-candidate-key="${escapeHtml(candidate.key)}" ${candidate.key === state.activeKey ? 'aria-current="true"' : ""}>
      <input type="checkbox" data-decision-key="${escapeHtml(candidate.key)}" aria-label="${inPlan ? "Remove" : "Add"} ${escapeHtml(displayId)} ${inPlan ? "from" : "to"} promotion plan" data-workbench-tooltip="${inPlan ? "Remove candidate from promotion plan" : "Add candidate to promotion plan"}" ${inPlan ? "checked" : ""}>
      <span class="candidate-tree-copy"><strong>${escapeHtml(displayId)}</strong><small>${escapeHtml(candidate.title)}</small>${renderCandidateDecoration(decoration, "candidate-decoration-icon")}</span>
      <span class="candidate-tree-summary"><span class="candidate-lifecycle ${escapeHtml(candidate.state)}">${escapeHtml(capitalize(candidate.state))}</span><span class="catalog-status ${catalogStatus.key}">${escapeHtml(catalogStatus.label)}</span><span class="tree-impact">${impact}</span><span class="tree-cost">${formatCandidateTokenValue(candidate, assessment)}</span><span class="recommendation-badge ${escapeHtml(assessment.recommendation)}">${escapeHtml(formatRecommendation(assessment.recommendation))}</span></span>
    </div>
  `;
}

function renderProtectedRuleTreeRow(rule) {
  return `
    <div class="candidate-tree-row clickable protected-rule-row ${rule.id === state.activeProtectedRuleId ? "active" : ""}" role="button" tabindex="0" data-protected-rule-id="${escapeHtml(rule.id)}" ${rule.id === state.activeProtectedRuleId ? 'aria-current="true"' : ""}>
      ${icon("lock")}<span class="candidate-tree-copy"><strong>${escapeHtml(rule.id)}</strong><small>${escapeHtml(rule.title)}</small></span>
      <span class="candidate-tree-summary"><span class="candidate-lifecycle required">Required</span><span class="catalog-status protected">Protected</span><span class="tree-impact">${rule.impact}</span><span class="tree-cost">${formatNumber(rule.guardedTokens)}</span><span class="recommendation-badge immutable">Immutable</span></span>
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
      ${renderDetailHeaderActions('<span class="candidate-state required">Required</span><span class="catalog-status protected">Protected</span>')}
    </div>
    <div class="assessment-content scroll-surface">
      <div class="section-block"><span class="section-label">Protected Instruction:</span><pre class="evidence-box scroll-surface">${escapeHtml(rule.text)}</pre></div>
      <div class="section-block"><span class="section-label">Protection:</span><div class="protected-rule-notice">${icon("lock")}<div><strong>${escapeHtml(rule.protectionReason)}</strong><p>This rule is always generated and cannot be changed through the promotion workflow.</p></div></div></div>
      <div class="section-block"><span class="section-label">Authored Source:</span><div class="subcontext-container">${escapeHtml(rule.sourcePath)}</div></div>
      <div class="score-strip protected-rule-score-strip"><div class="score-item impact"><span>Impact</span><strong>${rule.impact}</strong></div><div class="score-item cost"><span>Token cost</span><strong>${formatNumber(rule.guardedTokens)}</strong></div><div class="score-item efficiency"><span>Recommended</span><strong>Immutable</strong></div></div>
    </div>
  `;
}

function renderAssessment() {
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
  if (!assessment) {
    elements["assessment-panel"].innerHTML = `<div class="empty-state"><h2>AI Assessment Unavailable</h2><p>This candidate is not ready for maintainer review and should not appear in the evaluated candidate tree.</p></div>`;
    return;
  }
  const impact = assessment ? calculateImpact(assessment.factors) : null;
  const draftCost = getDecisionTokenDelta(candidate, decision);
  const projectedHeadroom = getAssessmentProjectedHeadroom(candidate, decision.action, decision);
  const catalogStatus = getCatalogStatus(candidate);
  const allowedActions = getAllowedActions(candidate, decision.proposedText);
  const unchangedMappedRule = catalogStatus.key === "mapped" && !hasHostedTextChange(candidate, decision.proposedText);
  const displayId = getEffectiveHostedRuleId(candidate);
  const rationaleDisabled = decision.action === "no-change" && decision.retireHostedRuleIds.length === 0;

  elements["assessment-panel"].innerHTML = `
    <div class="assessment-title">
      <div>
        <div class="source-line detail-identity">
          <span>${escapeHtml(candidate.sourceLabel)}</span>
          <span>/</span>
          <span>${escapeHtml(displayId)}</span>
        </div>
        <h2 class="detail-rule-title">${escapeHtml(candidate.title)}</h2>
        <div class="source-line"><span>${escapeHtml(candidate.sourcePath)}</span><span>${escapeHtml(candidate.hash.slice(0, 12))}</span></div>
      </div>
      ${renderDetailHeaderActions(`
        <span class="candidate-state ${escapeHtml(candidate.state)}">${escapeHtml(capitalize(candidate.state))}</span>
        <span class="decision-badge ${escapeHtml(decision.action)}">${escapeHtml(formatRecommendation(decision.action))}</span>
        ${renderCatalogStatusBadge(catalogStatus)}
      `)}
    </div>

    <div class="assessment-content scroll-surface">
      <div class="section-block">
        <span class="section-label">Source Rule:</span>
        <pre class="evidence-box scroll-surface">${escapeHtml(candidate.text)}</pre>
        ${candidate.sourceRationale ? `<div class="assessment-rationale proposal-rationale"><strong>Proposal rationale</strong><p>${escapeHtml(candidate.sourceRationale)}</p></div>` : ""}
      </div>

      ${renderMappedHostedRules(catalogStatus, true)}

      <div class="section-block">
        <span class="section-label">AI Evaluation:</span>
        <div class="ai-evaluation-summary subcontext-container">
          <div class="ai-evaluation-heading">
            <strong>${escapeHtml(assessment.summary)}</strong>
            <span class="recommendation-badge ${escapeHtml(assessment.recommendation)}">Recommend ${escapeHtml(formatRecommendation(assessment.recommendation))}</span>
          </div>
          <p>${escapeHtml(assessment.impactDescription || assessment.rationale)}</p>
        </div>
        <div class="score-strip">
          <div class="score-item impact"><span>Priority score</span><strong>${impact}</strong></div>
          <div class="score-item cost"><span>Token cost</span><strong>${draftCost === 0 ? "0" : formatSignedNumber(draftCost)}</strong></div>
          <div class="score-item efficiency"><span>Headroom after</span><strong>${formatNumber(projectedHeadroom)}</strong></div>
        </div>
        ${renderPriorityAssessment(assessment)}
      </div>

      <div class="section-block">
        <span class="section-label">Related Hosted Coverage:</span>
        <p class="coverage-summary evidence-summary-box subcontext-container">${escapeHtml(assessment.currentHostedCoverage)}</p>
      </div>

      <div class="section-block">
        <div class="proposed-rule-heading">
          <span class="section-label">Proposed Hosted Rule:</span>
          ${renderManualRelationshipStatus(candidate, decision.proposedText)}
          <button class="titlebar-icon proposed-rule-save" type="button" data-proposed-text-save aria-label="Save proposed Hosted rule" data-workbench-tooltip="Save proposed Hosted rule" disabled>${icon("save")}</button>
        </div>
        <label><textarea class="evidence-box proposed-rule scroll-surface" data-decision-field="proposedText" aria-label="Proposed Hosted rule wording">${escapeHtml(decision.proposedText || "")}</textarea></label>
      </div>

      <div class="section-block rule-actions">
        <span class="section-label">Rule Actions:</span>
        <div class="rule-actions-content subcontext-container">
          <div class="assessment-title rule-action-header">
            <div class="source-line detail-identity"><span>RULE:</span><span>${escapeHtml(candidate.assessment.proposedHostedRuleId)}</span></div>
          </div>
          <p class="section-help">${unchangedMappedRule ? "Current and proposed Hosted rule text are identical, so Update is unavailable." : "Choose one action. Hosted catalog status determines which actions are available."}</p>
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
          <div class="control-group implementation-model-control-group">
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
          </div>
          ${candidate.recommendation.retireHostedRuleIds.length ? `<div class="control-group ancillary-retirement-control-group">
            <span class="control-subtitle" id="ancillary-retirements-label">Related Hosted Rules to Retire:</span>
            <p class="section-help">Reconciliation supplied these lifecycle actions. Clear a rule to keep it active.</p>
            <div class="action-plan-group">
              <fieldset class="action-options ancillary-retirement-options" aria-labelledby="ancillary-retirements-label">
                <legend class="sr-only">Related Hosted rules to retire</legend>
                ${candidate.recommendation.retireHostedRuleIds.map((ruleId) => `
                  <label class="action-option clickable">
                    <input type="checkbox" data-retire-hosted-rule="${escapeHtml(ruleId)}" value="${escapeHtml(ruleId)}" ${decision.retireHostedRuleIds.includes(ruleId) ? "checked" : ""}>
                    <span>Retire ${escapeHtml(ruleId)}</span>
                  </label>
                `).join("")}
              </fieldset>
            </div>
          </div>` : ""}
          <div class="field-stack control-group rationale-control-group">
            <div class="rationale-heading"><span class="control-subtitle" id="decision-rationale-label">Decision Rationale:</span><button class="titlebar-icon clickable rationale-save" type="button" data-rationale-save aria-label="${state.rationaleReturnView === "plan" ? "Save decision and return to Promotion Plan" : "Save decision"}" data-workbench-tooltip="${state.rationaleReturnView === "plan" ? "Save decision and return to Promotion Plan" : "Save decision"}" ${!rationaleDisabled && (decision.rationale.trim() || state.session.decisions[candidate.key]) ? "" : "disabled"}>${icon("save")}</button></div>
            <label><textarea class="scroll-surface" data-decision-field="rationale" maxlength="${DECISION_RATIONALE_MAX_LENGTH}" aria-labelledby="decision-rationale-label" aria-describedby="decision-rationale-limit" placeholder="${rationaleDisabled ? "No rationale is required for No Change." : "Record why this action is appropriate."}" ${rationaleDisabled ? "disabled" : ""}>${escapeHtml(rationaleDisabled ? "" : decision.rationale)}</textarea><small class="rationale-limit" id="decision-rationale-limit">${rationaleDisabled ? 0 : decision.rationale.length} / ${DECISION_RATIONALE_MAX_LENGTH} characters</small></label>
          </div>
        </div>
      </div>
    </div>
  `;
}

function renderPriorityAssessment(assessment) {
  const factors = assessment.selectionFactors || assessment.factors;
  return `
    <div class="assessment-details-heading">
      <div><strong>Assessment Details:</strong><p>AI-adjudicated evidence. Maintainers can review these values but cannot edit them.</p></div>
    </div>
    <span class="control-subtitle scoring-legend-title">Scoring Legend:</span>
    <div class="scoring-legend subcontext-container">
      <div class="scoring-legend-items">
        <div class="scoring-legend-item"><span class="control-subtitle">Score Scale:</span><span>Scores run from 0 (none) through 5 (very high); a score of 4 means high.</span></div>
        <div class="scoring-legend-item"><span class="control-subtitle"><i class="legend-swatch value"></i>Rule Value:</span><span>Higher scores strengthen the case for adding or updating Hosted review coverage.</span></div>
        <div class="scoring-legend-item"><span class="control-subtitle"><i class="legend-swatch risk"></i>Review Risk:</span><span>Higher scores strengthen the reason to avoid a change and reduce the candidate priority.</span></div>
        <div class="scoring-legend-item"><span class="control-subtitle">Existing Coverage:</span><span>0 means no current Hosted coverage; 5 means active Hosted rules already cover the behavior completely.</span></div>
      </div>
    </div>
    <div class="factor-groups">
      <section class="factor-group value">
        <div class="factor-group-heading"><strong>Rule Value:</strong><span class="direction-badge positive">Adds to Impact</span></div>
        <div class="factor-grid">
          ${FACTORS.filter(([, , , kind]) => kind === "value").map(([name, label, description, kind]) => factorReadout(label, description, kind, factors[name])).join("")}
        </div>
      </section>
      <section class="factor-group penalty">
        <div class="factor-group-heading"><strong>Review Risk:</strong><span class="direction-badge negative">Reduces Impact</span></div>
        <div class="factor-grid">
          ${FACTORS.filter(([, , , kind]) => kind === "penalty").map(([name, label, description, kind]) => factorReadout(label, description, kind, factors[name])).join("")}
        </div>
      </section>
    </div>
    <span class="section-label adjudication-label">AI Adjudication Rationale:</span>
    <div class="assessment-rationale adjudication-text-box subcontext-container"><p>${escapeHtml(assessment.rationale)}</p></div>
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
  resetCandidate(candidate).then(() => {
    showToast(override ? "Override and plan item removed." : "Candidate removed and reset.");
  });
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
      syncProposedRuleControls(candidate);
    }
    if (event.target.dataset.decisionField === "rationale") {
      const counter = elements["assessment-panel"].querySelector(".rationale-limit");
      if (counter) counter.textContent = `${value.length} / ${DECISION_RATIONALE_MAX_LENGTH} characters`;
      const save = elements["assessment-panel"].querySelector("[data-rationale-save]");
      if (save) {
        const removesDecision = !value.trim() && Boolean(state.session.decisions[candidate.key]);
        save.disabled = !value.trim() && !removesDecision;
        save.setAttribute("aria-label", removesDecision ? "Remove saved decision" : "Save decision");
        setWorkbenchTooltip(save, removesDecision ? "Remove saved decision" : "Save decision");
      }
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
    badge.className = `decision-badge ${action}`;
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
  if (save) save.disabled = noChange || !rationale.value.trim();
}

async function handleAssessmentClick(event) {
  if (event.target.closest("[data-proposed-text-save]")) {
    const candidate = getActiveCandidate();
    if (!candidate) return;
    const proposedText = elements["assessment-panel"].querySelector('[data-decision-field="proposedText"]')?.value;
    if (proposedText === undefined) return;
    if (proposedText !== getDecision(candidate).proposedText) {
      const { assessment, ...maintainerDecision } = getDecision(candidate);
      saveDecision(candidate, { ...maintainerDecision, proposedText });
      await persistencePromise;
    }
    await reconcileManualRuleText(candidate, proposedText);
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
  const returnToPlan = state.rationaleReturnView === "plan";
  await persistencePromise;
  await reconcileManualRuleText(candidate, proposedText);
  renderAssessment();
  showToast("Decision saved");
  if (returnToPlan) {
    state.rationaleReturnView = null;
    switchView("plan");
  }
}

function refreshAssessmentScores(candidate, action = getDecision(candidate).action) {
  const decision = getDecision(candidate);
  const assessment = getAssessment(candidate, decision);
  const impact = calculateImpact(assessment.factors);
  const cost = getActionTokenDelta(candidate, action, decision);
  const scoreValues = elements["assessment-panel"].querySelectorAll(".score-item strong");
  if (scoreValues.length === 3) {
    scoreValues[0].textContent = impact;
    scoreValues[1].textContent = cost === 0 ? "0" : formatSignedNumber(cost);
    scoreValues[2].textContent = formatNumber(getAssessmentProjectedHeadroom(candidate, action, decision));
  }
}

function renderPlan() {
  const planCandidates = sortPlanCandidates(getPlanCandidates(), state.planSort);
  const latestBulkOperation = getLatestBulkOperation();
  const bulkUndoLabel = latestBulkOperation
    ? `Undo bulk ${latestBulkOperation.action} of ${formatNumber(latestBulkOperation.candidateKeys.length)} candidates`
    : "No bulk selection to undo";
  elements["plan-bulk-undo"].disabled = !latestBulkOperation;
  elements["plan-bulk-undo"].setAttribute("aria-label", bulkUndoLabel);
  setWorkbenchTooltip(elements["plan-bulk-undo"], bulkUndoLabel);
  elements["plan-table-head"].innerHTML = renderPlanHeader();
  elements["empty-plan"].hidden = planCandidates.length > 0;
  elements["plan-table-body"].innerHTML = planCandidates.map((candidate) => {
    const decision = getDecision(candidate);
    const assessment = getAssessment(candidate, decision);
    const impact = assessment ? calculateImpact(assessment.factors) : null;
    const cost = getPlanTokenDisplay(candidate);
    const readiness = getPlanReadiness(candidate);
    const displayId = getEffectiveHostedRuleId(candidate);
    return `
      <tr class="plan-candidate-row clickable" tabindex="0" data-plan-row="${escapeHtml(candidate.key)}" aria-label="Open ${escapeHtml(displayId)} candidate">
        <td class="plan-candidate"><span class="candidate-link">${escapeHtml(displayId)}</span><br><span class="plan-candidate-title">${escapeHtml(candidate.title)}</span></td>
        <td class="plan-source"><span class="status-badge neutral plan-source-pill type-compact">${escapeHtml(formatTitleCase(candidate.sourceLabel))}</span></td>
        <td class="plan-type"><span class="status-badge neutral plan-membership-badge">${escapeHtml(formatTitleCase(decision.planMembershipSource))}</span></td>
        <td class="plan-action"><span class="recommendation-badge ${escapeHtml(isPromotionAction(decision.action) ? decision.action : decision.retireHostedRuleIds.length ? "retire" : decision.action)}">${escapeHtml(formatPlanAction(decision))}</span></td>
        <td class="mono">${impact}</td>
        <td class="mono">${cost}</td>
        <td>${readiness.ready ? `<span class="status-badge success">${readiness.label}</span>` : readiness.actionRequired ? `<button class="status-badge warning plan-detail-link clickable" type="button" data-plan-action="${escapeHtml(candidate.key)}" aria-label="Choose a rule action for ${escapeHtml(displayId)}" data-workbench-tooltip="Open candidate and choose a rule action">${icon("edit")}<span>${readiness.label}</span></button>` : `<button class="status-badge warning plan-detail-link clickable" type="button" data-plan-detail="${escapeHtml(candidate.key)}" aria-label="Complete required fields for ${escapeHtml(displayId)}" data-workbench-tooltip="Open candidate and complete required fields">${icon("edit")}<span>${readiness.label}</span></button>`}</td>
        <td class="plan-actions"><span class="plan-action-controls"><button class="titlebar-icon clickable" type="button" data-plan-undo="${escapeHtml(candidate.key)}" aria-label="Undo this candidate" data-workbench-tooltip="Undo this candidate">${icon("discard")}</button></span></td>
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
  const relationshipCheckRequired = requiresManualRelationshipCheck(candidate, decision.proposedText);
  return {
    actionRequired,
    resourceTypeRequired,
    relationshipCheckRequired,
    ready: Boolean(assessment) && !actionRequired && !rationaleRequired && !resourceTypeRequired && !relationshipCheckRequired,
    label: actionRequired ? "Needs action" : resourceTypeRequired ? "Needs resource type" : rationaleRequired ? "Needs rationale" : relationshipCheckRequired ? "Needs relationship check" : assessment ? "Ready" : "Needs AI assessment"
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
  setWorkspaceTab("candidate-sources");
  selectCandidate(key, "plan");
  switchView("catalog");
  showCandidatePane(focusTarget ? "details" : "candidates");
  requestAnimationFrame(() => {
    revealCandidateInTree(key);
    const row = elements["candidate-list"].querySelector(`[data-candidate-key="${CSS.escape(key)}"]`);
    requestAnimationFrame(() => {
      if (focusTarget === "action") {
        const actions = elements["assessment-panel"].querySelector(".action-options");
        const control = actions?.querySelector("input:checked") || actions?.querySelector("input");
        scrollCandidateDetailTargetIntoView(actions);
        control?.focus({ preventScroll: true });
        return;
      }
      if (focusTarget === "rationale") {
        const field = elements["assessment-panel"].querySelector('[data-decision-field="rationale"]');
        scrollCandidateDetailTargetIntoView(field);
        field?.focus({ preventScroll: true });
        return;
      }
      if (!row) return;
      row.scrollIntoView({ block: "center", behavior: "smooth" });
      row.focus({ preventScroll: true });
    });
  });
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
  if (["add", "update", "restore"].includes(action)) surfaces.push(...(assessment?.affectedSurfaces || []));
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
  const budgetTokens = buckets.reduce((sum, bucket) => sum + bucket.budgetTokens, 0);
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
  const reportSurfaces = {
    "go-combined": new Set(["repository", "implementation", "review-skill"]),
    "test-combined": new Set(["repository", "implementation", "testing", "review-skill"]),
    "documentation-combined": new Set(["repository", "documentation", "review-skill"])
  }[report.name];
  if (!reportSurfaces) return 0;
  return getPlanCandidates().reduce((sum, candidate) => {
    return getPlanAffectedSurfaces(candidate).some((surface) => reportSurfaces.has(surface)) ? sum + getPlanTokenDelta(candidate) : sum;
  }, 0);
}

function renderPreview() {
  disconnectPreviewBodyVirtualizer();
  const readiness = getPreviewReadiness();
  const planCandidates = readiness.planCandidates;
  const ready = readiness.ready;
  elements["approval-badge"].className = `status-badge ${ready ? "success" : "warning"}`;
  elements["approval-badge"].textContent = ready ? "Ready to export" : "Not ready";
  elements["preview-status"].textContent = ready ? "Ready" : "Draft";
  const previewStatus = elements["preview-status"].closest(".status-item");
  previewStatus.classList.toggle("preview-ready", ready);
  previewStatus.classList.toggle("preview-draft", !ready);
  if (elements["approver-name"].value !== state.session.approverName) {
    elements["approver-name"].value = state.session.approverName || "";
  }
  renderApprovalRequirements(readiness);
  elements["approve-export-button"].disabled = !ready;
  previewFilesByScope = buildPreviewFiles(planCandidates);
  elements["preview-diff"].innerHTML = renderPreviewFiles(previewFilesByScope.proposed, "No Proposed Changes", "Add an available rule action to review its line-level diff.");
  elements["preview-payload-diff"].innerHTML = renderPreviewFiles(previewFilesByScope.payload, "No Payload Changes", "Add or update a Promotion Plan item to review its selection payload changes.");
  elements["preview-json"].innerHTML = renderPreviewFiles(previewFilesByScope.raw, "No Approved Rules", "Add, update, or retire a Promotion Plan item to review the approved catalog mutations.");
  elements["raw-payload-empty"].hidden = true;
  elements["preview-review-popover"].hidden = true;
  renderPreviewReview();
  initializePreviewBodyVirtualizer();
}

function buildPreviewFiles(candidates) {
  const proposed = candidates.flatMap((candidate) => buildApprovedMutations(candidate).map((mutation) => {
    const existingRule = state.bundle.catalog.rules.find((rule) => rule.id === mutation.rule.id);
    const before = mutation.action === "add" ? [] : splitDiffLines(existingRule?.text || "");
    const after = mutation.action === "retire" ? [] : splitDiffLines(mutation.rule.text);
    return createPreviewFile(`rules/${mutation.rule.id}.md`, candidate.title, before, after, false, candidate.sourceId, "proposed");
  }));
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
  const proposedPayload = buildApprovedRules();
  const currentPayload = {
    ...structuredClone(proposedPayload),
    mutations: []
  };
  const raw = candidates.length
    ? [createPreviewFile("approval/approved-rules.json", "Approved catalog mutations", JSON.stringify(currentPayload, null, 2).split("\n"), JSON.stringify(proposedPayload, null, 2).split("\n"), true, "", "raw")]
    : [];
  return { proposed, payload, raw };
}

function copyCatalogRule(rule) {
  return Object.fromEntries(["id", "origin", "status", "text", "provenance", "evidenceIds", "implementationModels", "documentationGap", "retirementReason", "lastPlacement", "selectionFactors", "selectionRationale"]
    .filter((property) => rule?.[property] !== undefined)
    .map((property) => [property, structuredClone(rule[property])]));
}

function buildApprovedMutation(candidate) {
  const decision = getDecision(candidate);
  const assessment = getAssessment(candidate, decision);
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
      rows.push({ changed: true, oldText: before[index], oldLine: before[index] === undefined ? undefined : beforeLine++, newText: after[index], newLine: after[index] === undefined ? undefined : afterLine++ });
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
  const additions = files.reduce((sum, file) => sum + file.additions, 0);
  const deletions = files.reduce((sum, file) => sum + file.deletions, 0);
  elements["preview-review-context"].innerHTML = `<strong>${files.length} file${files.length === 1 ? "" : "s"} changed</strong><span class="preview-change-summary"><b>+${additions}</b><i>-${deletions}</i></span>${renderPreviewDiffStat(additions, deletions)}`;
  document.querySelectorAll(".preview-proposed-review, .payload-review, .preview-raw-payload").forEach((section) => {
    section.hidden = false;
  });
  if (!files.some((file) => file.path === previewSelectedFilePath)) previewSelectedFilePath = files[0]?.path || "";
  renderPreviewFileTree();
  updatePreviewSelectedFile();
}

function renderPreviewFileTree() {
  elements["preview-summary"].innerHTML = `<label class="preview-file-filter">${icon("search")}<input type="search" placeholder="Filter changed files" aria-label="Filter changed files"></label><nav class="preview-artifact-tree" aria-label="Review artifacts">${Object.entries(previewFilesByScope).map(([scope, files]) => renderPreviewArtifactGroup(scope, files)).join("")}</nav>`;
}

function renderPreviewArtifactGroup(scope, files) {
  const expanded = previewExpandedScopes.has(scope);
  const children = files.map((file) => renderPreviewTreeFile(scope, { ...file, name: file.path.split("/").at(-1) })).join("");
  return `
    <section class="preview-artifact-group" data-preview-artifact-group="${escapeHtml(scope)}">
      <button class="preview-artifact-parent clickable" type="button" data-preview-artifact-scope="${escapeHtml(scope)}" aria-expanded="${expanded}">${octicon(`chevron-${expanded ? "down" : "right"}`)}${octicon(`file-directory-${expanded ? "open-" : ""}fill`)}<span>${escapeHtml(PREVIEW_SCOPE_LABELS[scope])}</span></button>
      <div class="preview-artifact-children" ${expanded ? "" : "hidden"}>${children}</div>
    </section>
  `;
}

function renderPreviewTreeFile(scope, file) {
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

function handlePreviewFileFilter(event) {
  if (!event.target.matches('input[type="search"]')) return;
  const query = event.target.value.trim().toLowerCase();
  elements["preview-summary"].querySelectorAll("[data-preview-file-jump]").forEach((button) => {
    button.hidden = !button.dataset.previewFileJump.toLowerCase().includes(query);
  });
  elements["preview-summary"].querySelectorAll(".preview-artifact-group").forEach((group) => {
    const hasMatches = [...group.querySelectorAll("[data-preview-file-jump]")].some((button) => !button.hidden);
    group.hidden = Boolean(query) && !hasMatches;
    group.querySelector(".preview-artifact-children").hidden = !hasMatches || (!query && !previewExpandedScopes.has(group.dataset.previewArtifactGroup));
  });
}

function handlePreviewFileNavigation(event) {
  const parent = event.target.closest("[data-preview-artifact-scope]");
  if (parent) {
    const scope = parent.dataset.previewArtifactScope;
    if (previewExpandedScopes.has(scope)) previewExpandedScopes.delete(scope);
    else previewExpandedScopes.add(scope);
    renderPreviewFileTree();
    return;
  }
  const button = event.target.closest("[data-preview-file-jump]");
  if (!button) return;
  const path = button.dataset.previewFileJump;
  const file = elements["preview-code"].querySelector(`[data-preview-file-path="${CSS.escape(path)}"]`);
  if (!file) return;
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

async function handlePreviewReviewClick(event) {
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

function getPreviewReadiness() {
  const planCandidates = getPlanCandidates();
  const missingActionCount = planCandidates.filter((candidate) => !isActionableDecision(getDecision(candidate))).length;
  const missingResourceTypeCount = planCandidates.filter((candidate) => {
    const decision = getDecision(candidate);
    return canEditImplementationModels(candidate, decision.action) && decision.implementationModels.length === 0;
  }).length;
  const missingRationaleCount = planCandidates.filter((candidate) => {
    const decision = getDecision(candidate);
    return !getAssessment(candidate, decision) || !decision.rationale.trim();
  }).length;
  const missingRationale = missingRationaleCount > 0;
  const missingRelationshipCheckCount = planCandidates.filter((candidate) => requiresManualRelationshipCheck(candidate)).length;
  const mutationRuleIds = planCandidates.flatMap((candidate) => buildApprovedMutations(candidate).map((mutation) => mutation.rule.id));
  const conflictingMutationCount = mutationRuleIds.length - new Set(mutationRuleIds).size;
  const approverName = String(state.session.approverName || "").trim();
  let status = "ready";
  if (planCandidates.length === 0) status = "no actions";
  else if (missingActionCount) status = "needs action";
  else if (missingResourceTypeCount) status = "needs resource type";
  else if (missingRationale) status = "needs rationale";
  else if (missingRelationshipCheckCount) status = "needs relationship check";
  else if (conflictingMutationCount) status = "conflicting mutations";
  else if (!approverName) status = "needs approver";
  return {
    planCandidates,
    approverName,
    missingActionCount,
    missingResourceTypeCount,
    missingRationaleCount,
    missingRelationshipCheckCount,
    conflictingMutationCount,
    status,
    ready: planCandidates.length > 0 && missingActionCount === 0 && missingResourceTypeCount === 0 && !missingRationale && missingRelationshipCheckCount === 0 && conflictingMutationCount === 0 && Boolean(approverName)
  };
}

function renderApprovalRequirements(readiness) {
  const requirements = [
    ["Plan actions", readiness.planCandidates.length ? `${readiness.planCandidates.length} selected` : "None selected", readiness.planCandidates.length > 0],
    ["Rule actions", readiness.missingActionCount ? `${readiness.missingActionCount} missing` : readiness.planCandidates.length ? "Complete" : "None selected", readiness.planCandidates.length > 0 && readiness.missingActionCount === 0],
    ["Resource types", readiness.missingResourceTypeCount ? `${readiness.missingResourceTypeCount} missing` : "Complete", readiness.planCandidates.length > 0 && readiness.missingResourceTypeCount === 0],
    ["Decision rationales", readiness.missingRationaleCount ? `${readiness.missingRationaleCount} missing` : "Complete", readiness.planCandidates.length > 0 && readiness.missingRationaleCount === 0],
    ["Relationship checks", readiness.missingRelationshipCheckCount ? `${readiness.missingRelationshipCheckCount} required` : "Current", readiness.planCandidates.length > 0 && readiness.missingRelationshipCheckCount === 0],
    ["Mutation targets", readiness.conflictingMutationCount ? `${readiness.conflictingMutationCount} conflicting` : "Unique", readiness.planCandidates.length > 0 && readiness.conflictingMutationCount === 0],
    ["GitHub identity", readiness.approverName || "Unavailable", Boolean(readiness.approverName)]
  ];
  elements["approval-requirements"].innerHTML = `<strong class="approval-requirements-title">Approval Requirements</strong>${requirements.map(([label, value, passed]) => `
    <div class="approval-requirement ${passed ? "passed" : "pending"}">
      ${icon(passed ? "pass" : "warning")}
      <span>${escapeHtml(label)}</span>
      <strong>${escapeHtml(value)}</strong>
    </div>
  `).join("")}`;
}

function renderCounts() {
  const planCount = getPlanCandidates().length;
  elements["catalog-count"].textContent = formatNumber(state.candidates.length);
  elements["plan-count"].textContent = formatNumber(planCount);
  elements["plan-activity-count"].textContent = planCount > 999 ? "999+" : formatNumber(planCount);
  elements["plan-activity-count"].hidden = planCount === 0;
  elements["rule-issues-tab-count"].textContent = formatNumber(state.ruleIssues.length);
  elements["rule-issues-tab-count"].hidden = state.ruleIssues.length === 0;
  const planLabel = `Promotion Plan (${formatNumber(planCount)})`;
  setWorkbenchTooltip(elements["promotion-plan-stage"], planLabel);
  elements["promotion-plan-stage"].setAttribute("aria-label", planLabel);
}

function formatCountLabel(count, singular) {
  return `${formatNumber(count)} ${count === 1 ? singular : `${singular}s`}`;
}

function getPlanCandidates() {
  return state.candidates.filter((candidate) => getDecision(candidate).inPlan);
}

function getCapacityReports() {
  return state.bundle.guidanceCapacity.reports;
}

function getActiveCandidate() {
  return state.candidates.find((candidate) => candidate.key === state.activeKey) || null;
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
      checkbox.checked = inPlan;
      setWorkbenchTooltip(checkbox, inPlan ? "Remove candidate from promotion plan" : "Add candidate to promotion plan");
      checkbox.setAttribute("aria-label", `${inPlan ? "Remove" : "Add"} ${getEffectiveHostedRuleId(candidate)} ${inPlan ? "from" : "to"} promotion plan`);
    }
    const candidateId = row.querySelector(".candidate-tree-copy strong");
    if (candidateId) candidateId.textContent = getEffectiveHostedRuleId(candidate);
    const assessment = candidate && getAssessment(candidate, getDecision(candidate));
    const token = row.querySelector(".tree-cost");
    if (assessment && token) token.textContent = formatCandidateTokenValue(candidate, assessment);
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
  syncCandidateTreeRows();
  renderAssessment();
  refreshPresentation();
}

function selectProtectedRule(id) {
  state.activeKey = null;
  state.activeProtectedRuleId = id;
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
}

function updateFilter(value) {
  state.queries[state.workspaceTab] = value;
  if (state.workspaceTab === "candidate-sources") {
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

function selectAssessmentResult(key) {
  if (state.assessmentActiveKey !== key) state.assessmentOverrideEditingKey = null;
  state.assessmentActiveKey = key;
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
}

function setWorkspaceTab(tab) {
  if (!["candidate-sources", "assessment-results", "rule-issues"].includes(tab)) return;
  dismissNotification();
  state.workspaceTab = tab;
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
  if (candidateCheckbox.checked) {
    updateDecision(candidate, { inPlan: true });
    selectCandidate(candidate.key);
  } else {
    removePlanMembership(candidate);
  }
}

function switchView(view) {
  dismissNotification();
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
    inputFingerprint: session.inputFingerprint,
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
  return {
    schemaVersion: SESSION_SCHEMA_VERSION,
    id: draft.inputFingerprint,
    inputFingerprint: draft.inputFingerprint,
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
  const approvedBy = String(state.session.approverName || identity?.login || "").trim();
  return {
    $schema: "approved-rules-v4.schema.json",
    schemaVersion: APPROVED_RULES_SCHEMA_VERSION,
    kind: "hosted-approved-rules",
    catalogContentSha256: state.bundle.catalog.contentSha256,
    approvedAt: toUtcTimestamp(state.session.updatedAt),
    approvedBy: {
      type: identity ? "github-authenticated" : "manual",
      id: identity?.login || approvedBy,
      displayName: approvedBy
    },
    mutations: getPlanCandidates().flatMap(buildApprovedMutations)
  };
}

function exportDraft() {
  const payload = JSON.stringify(buildDraftExport(), null, 2) + "\n";
  downloadJson(payload, `hosted-rule-draft-${toUtcTimestamp().replace(/[:.]/g, "-")}.json`);
  showToast("Draft exported");
}

function handleApproverInput(event) {
  state.session.approverName = event.target.value.slice(0, 120);
  state.session.updatedAt = toUtcTimestamp();
  persistSession();
  renderPreview();
  setSaveIndicator(`Saved ${formatTime(state.session.updatedAt)}`);
  refreshPresentation();
}

function approveAndExport() {
  const readiness = getPreviewReadiness();
  if (!readiness.ready) {
    showToast("Complete the selected rule rationale and approver name before exporting.", true);
    return;
  }
  elements["approve-export-button"].disabled = true;
  try {
    const approvedRules = buildApprovedRules();
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
    if (draft.inputFingerprint !== state.session.inputFingerprint) {
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
      if (!candidate || (!candidate.assessment.hostedApplicable && !overriddenCandidateKeys.has(key)) || decision.sourceHash !== candidate.hash || !getAllowedActions(candidate).includes(decision.action) || !isValidPlanMembership(decision, key, draft.bulkOperations) || typeof decision.rationale !== "string" || decision.rationale.length > DECISION_RATIONALE_MAX_LENGTH || decision.proposedHostedRuleId !== candidate.assessment.proposedHostedRuleId) {
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

async function persistSession() {
  if (!state.session) return;
  const snapshot = normalizeSessionTimestamps(state.session);
  persistencePromise = persistencePromise.then(async () => {
    const database = await openDatabase();
    await new Promise((resolve, reject) => {
      const request = database.transaction("sessions", "readwrite").objectStore("sessions").put(snapshot);
      request.onsuccess = () => resolve();
      request.onerror = () => reject(request.error);
    });
    setSaveIndicator(`Saved ${formatTime(snapshot.updatedAt)}`);
  });
  return persistencePromise;
}

function setSaveIndicator(text) {
  elements["save-indicator"].textContent = text;
}

function renderFatalError(error) {
  elements.workspace.classList.remove("icon-paint-pending");
  elements["candidate-list"].innerHTML = "";
  elements["assessment-panel"].innerHTML = `<div class="empty-state"><h2>Workbench Could Not Load</h2><p>${escapeHtml(error.message)}</p></div>`;
  setSaveIndicator("Bundle unavailable");
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
