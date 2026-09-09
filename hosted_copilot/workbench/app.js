"use strict";

const DATABASE_NAME = "hosted-rule-workbench";
const DATABASE_VERSION = 1;
const ACTIVE_SESSION_KEY = "hosted-rule-workbench.active-session";
const SESSION_SCHEMA_VERSION = 6;
const APPROVAL_PAYLOAD_SCHEMA_VERSION = 5;
const DECISION_RATIONALE_MAX_LENGTH = 500;
const OVERRIDE_RATIONALE_MAX_LENGTH = 500;
const FACTORS = [
  ["severity", "Severity", "Harm caused when this defect is missed", "value"],
  ["frequency", "Frequency", "How often this defect appears in provider changes", "value"],
  ["breadth", "Breadth", "How widely the rule applies across the provider", "value"],
  ["hostedDetectability", "Hosted detectability", "How reliably Hosted review can prove the defect", "value"],
  ["evidenceStrength", "Evidence strength", "How authoritative and durable the supporting evidence is", "value"],
  ["falsePositiveRisk", "False-positive risk", "Chance of producing unsupported findings", "penalty"],
  ["redundancy", "Existing coverage", "How completely current Hosted rules already cover it", "penalty"]
];

const state = {
  bundle: null,
  session: null,
  assessedCandidates: [],
  candidates: [],
  excludedCandidateCount: 0,
  activeKey: null,
  assessmentActiveKey: null,
  assessmentOverrideExpandedKey: null,
  candidatePane: "candidates",
  assessmentPane: "assessments",
  rationaleReturnView: null,
  workspaceTab: "candidate-sources",
  currentView: "catalog",
  queries: {
    "candidate-sources": "",
    "assessment-results": ""
  },
  candidateSorts: {},
  assessmentSorts: {},
  planSort: { field: "candidate", direction: "ascending" }
};

const elements = {};
let databasePromise;
let persistencePromise = Promise.resolve();
let toastTimer;
let rawPayloadChangeIndex = 0;
let rawPayloadChangeCount = 0;
let truncationTooltipFrame;

function icon(name) {
  if (!/^[a-z0-9-]+$/.test(name)) throw new Error(`Invalid Codicon name: ${name}`);
  return `<svg class="codicon" aria-hidden="true"><use href="icons/codicons/sprite.svg#codicon-${name}"></use></svg>`;
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
    "promotion-plan-stage", "plan-activity-count",
    "status-excluded", "status-mapped", "status-unmapped", "status-headroom", "preview-status", "save-indicator", "search-input",
    "candidate-list", "candidate-panel", "assessment-panel", "candidate-pane-candidates", "candidate-pane-details", "candidate-sources-panel", "assessment-results-panel",
    "bulk-actions", "bulk-scope-count", "bulk-add-count", "bulk-update-count", "bulk-actionable-count", "bulk-undo", "bulk-undo-count", "bulk-actions-note",
    "assessment-results-list", "assessment-results-detail",
    "return-catalog-button", "plan-table-head", "plan-table-body", "empty-plan", "capacity-panel", "approval-badge",
    "preview-summary", "preview-diff", "preview-payload-diff", "preview-raw-heading", "raw-payload-empty", "preview-json", "raw-change-tools", "raw-change-count",
    "raw-change-position", "raw-previous-change", "raw-next-change", "copy-preview-button", "approver-name", "approval-requirements",
    "approve-export-button", "toast", "toast-message", "toast-close"
  ]) {
    elements[id] = document.getElementById(id);
  }
}

function bindEvents() {
  document.addEventListener("pointerover", handleWorkbenchTooltipPointerOver);
  document.addEventListener("pointerout", handleWorkbenchTooltipPointerOut);
  document.addEventListener("focusin", handleWorkbenchTooltipFocusIn);
  document.addEventListener("focusout", handleWorkbenchTooltipFocusOut);
  document.querySelectorAll("[data-view]").forEach((button) => {
    button.addEventListener("click", () => switchView(button.dataset.view));
  });
  elements["return-catalog-button"].addEventListener("click", () => switchView("catalog"));
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
    const row = event.target.closest("[data-candidate-key]");
    if (row) {
      selectCandidate(row.dataset.candidateKey);
      showCandidatePane("details");
    }
  });
  elements["candidate-list"].addEventListener("change", handleTreeSelection);
  elements["candidate-list"].addEventListener("keydown", (event) => {
    handleRowKeyboardNavigation(event, elements["candidate-list"], "candidateKey", selectCandidate, () => showCandidatePane("details"));
  });
  elements["assessment-results-list"].addEventListener("click", async (event) => {
    const sortButton = event.target.closest("[data-assessment-sort]");
    if (sortButton) {
      updateAssessmentSort(sortButton);
      return;
    }
    const overrideToggle = event.target.closest("[data-assessment-override-toggle]");
    if (overrideToggle) {
      const key = overrideToggle.dataset.assessmentOverrideToggle;
      state.assessmentOverrideExpandedKey = state.assessmentOverrideExpandedKey === key ? null : key;
      syncAssessmentOverrideDisclosures();
      return;
    }
    const overrideRemove = event.target.closest("[data-assessment-override-remove]");
    if (overrideRemove) {
      const candidate = state.assessedCandidates.find((item) => item.key === overrideRemove.dataset.assessmentOverrideRemove);
      if (!candidate) return;
      state.assessmentOverrideExpandedKey = null;
      await updateOverrideLifecycle(candidate, null, null);
      showToast("Provisional override removed");
      return;
    }
    const row = event.target.closest("[data-assessment-key]");
    if (row) {
      selectAssessmentResult(row.dataset.assessmentKey);
      showAssessmentPane("details");
    }
  });
  elements["assessment-results-list"].addEventListener("keydown", (event) => {
    if (event.target.closest("[data-assessment-override-toggle], [data-assessment-override-remove]")) return;
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
  elements["raw-previous-change"].addEventListener("click", () => navigateRawPayloadDirection(-1));
  elements["raw-next-change"].addEventListener("click", () => navigateRawPayloadDirection(1));
  elements["preview-json"].addEventListener("scroll", updateRawPayloadChangeNavigation);
  elements["copy-preview-button"].addEventListener("click", copyPreview);
  elements["approver-name"].addEventListener("input", handleApproverInput);
  elements["approve-export-button"].addEventListener("click", approveAndExport);
  elements["toast-close"].addEventListener("click", dismissNotification);
  document.addEventListener("keydown", (event) => {
    if (event.key === "Escape" && elements.toast.classList.contains("visible")) dismissNotification();
  });
  window.addEventListener("resize", hideStatusTooltip);
  window.addEventListener("resize", scheduleTruncationTooltips);
}

function showWorkbenchTooltip(item, anchorX = item.getBoundingClientRect().left) {
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
  const left = Math.floor(Math.min(Math.max(8, anchorX), Math.max(8, window.innerWidth - tooltipRect.width - 8)));
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

function handleWorkbenchTooltipPointerOver(event) {
  const owner = getWorkbenchTooltipOwner(event.target);
  if (!owner || owner.contains(event.relatedTarget)) return;
  showWorkbenchTooltip(owner, event.clientX);
}

function handleWorkbenchTooltipPointerOut(event) {
  const owner = getWorkbenchTooltipOwner(event.target);
  if (!owner || owner.contains(event.relatedTarget)) return;
  hideStatusTooltip();
}

function handleWorkbenchTooltipFocusIn(event) {
  const owner = getWorkbenchTooltipOwner(event.target);
  if (owner) showWorkbenchTooltip(owner);
}

function handleWorkbenchTooltipFocusOut(event) {
  if (getWorkbenchTooltipOwner(event.target)) hideStatusTooltip();
}

function showStatusTooltip(item) {
  showWorkbenchTooltip(item);
}

function showSourceProvenanceTooltip(pill, anchorX) {
  showWorkbenchTooltip(pill, anchorX);
}

function hideStatusTooltip() {
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

async function loadBundle() {
  setSaveIndicator("Loading bundle");
  try {
    const response = await fetch("rule-intake-review.json", { cache: "no-store" });
    if (!response.ok) throw new Error(`Bundle request failed with ${response.status}`);
    const bundle = await response.json();
    validateBundle(bundle);
    state.bundle = bundle;
    const discoveredCandidates = normalizeCandidates(bundle);
    const sessionId = getSessionId(bundle);
    const existing = await readSession(sessionId);
    state.session = existing?.schemaVersion === SESSION_SCHEMA_VERSION ? existing : createSession(sessionId, bundle);
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
    state.assessmentActiveKey = null;
    state.candidatePane = "candidates";
    state.assessmentPane = "assessments";
    renderAll();
    showCandidatePane("candidates");
    showAssessmentPane("assessments");
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

function validateBundle(bundle) {
  if (!bundle || bundle.readOnly !== true || bundle.refreshMode !== "regenerate-read-only-bundle") {
    throw new Error("The candidate bundle does not satisfy the read-only Workbench contract.");
  }
  if (!bundle.guidanceCapacity || bundle.guidanceCapacity.reportCount !== 8) {
    throw new Error("The candidate bundle does not contain all guidance capacity reports.");
  }
}

function normalizeCandidates(bundle) {
  const getAssessments = (candidate) => candidate.assessments || [];
  const normalizeAssessment = (assessment) => ({ ...assessment });
  const getTargetRules = (candidate, assessment) => assessment.targetHostedRuleId
    ? (bundle.hostedRules || candidate.relatedHostedRules || []).filter((rule) => rule.id === assessment.targetHostedRuleId)
    : [];
  const upstream = bundle.upstreamCandidates.flatMap((candidate) => getAssessments(candidate).map((rawAssessment) => {
    const assessment = normalizeAssessment(rawAssessment);
    return {
      key: `upstream:${candidate.id}:${assessment.assessmentId}`,
      id: assessment.targetHostedRuleId || assessment.assessmentId,
      sourceId: candidate.id,
      sourceTitle: candidate.title,
      sourceType: "upstream",
      sourceLabel: "Contributor guidance",
      category: getUpstreamCategory(candidate),
      title: assessment.title,
      state: assessment.candidateState,
      requiresReview: candidate.requiresReview,
      provenance: "published-upstream-standard",
      sourcePath: candidate.referenceUrl,
      hash: candidate.currentSha256,
      text: candidate.currentContent,
      baselineText: candidate.baselineContent,
      priorDecision: null,
      assessment,
      relatedHostedRules: getTargetRules(candidate, assessment)
    };
  }));
  const interactive = bundle.interactiveCandidates.flatMap((candidate) => getAssessments(candidate).map((rawAssessment) => {
    const assessment = normalizeAssessment(rawAssessment);
    return {
      key: `interactive:${candidate.id}:${assessment.assessmentId}`,
      id: assessment.targetHostedRuleId || assessment.assessmentId,
      sourceId: candidate.id,
      sourceTitle: candidate.title,
      sourceType: "interactive",
      sourceLabel: "Interactive rule",
      category: formatContractCategory(candidate.contractPath),
      title: assessment.title,
      state: assessment.candidateState,
      requiresReview: candidate.requiresReview,
      provenance: candidate.provenance,
      sourcePath: candidate.contractPath,
      hash: candidate.contentSha256,
      text: candidate.ruleText || "Retired source rule",
      baselineText: null,
      priorDecision: candidate.priorDecision,
      assessment,
      relatedHostedRules: getTargetRules(candidate, assessment)
    };
  }));
  const maintainer = bundle.maintainerCandidates.flatMap((candidate) => getAssessments(candidate).map((rawAssessment) => {
    const assessment = normalizeAssessment(rawAssessment);
    return {
      key: `maintainer:${candidate.id}:${assessment.assessmentId}`,
      id: assessment.targetHostedRuleId || assessment.assessmentId,
      sourceId: candidate.id,
      sourceTitle: candidate.title,
      sourceType: "maintainer",
      sourceLabel: "Maintainer proposal",
      category: capitalize(candidate.surface),
      title: assessment.title,
      state: assessment.candidateState,
      requiresReview: candidate.requiresReview,
      provenance: candidate.provenance,
      sourcePath: candidate.sourcePath,
      sourceRationale: candidate.rationale,
      surface: candidate.surface,
      hash: candidate.contentSha256,
      text: candidate.ruleText,
      baselineText: null,
      priorDecision: null,
      assessment,
      relatedHostedRules: getTargetRules(candidate, assessment)
    };
  }));
  return [...interactive, ...upstream, ...maintainer];
}

function getSessionId(bundle) {
  const snapshots = bundle.snapshots;
  return [snapshots.hostedCatalogSha256, snapshots.interactive.currentCatalogSha256, snapshots.upstream.currentCommit, snapshots.maintainer.sourceSha256].join(":");
}

function createSession(id, bundle) {
  return {
    schemaVersion: SESSION_SCHEMA_VERSION,
    id,
    createdAt: new Date().toISOString(),
    updatedAt: new Date().toISOString(),
    snapshots: bundle.snapshots,
    approverName: "",
    decisions: {},
    applicabilityOverrides: {},
    bulkOperations: []
  };
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
    && operation.scope === "current-results"
    && ["add", "update", "actionable"].includes(operation.recommendationScope)
    && typeof operation.query === "string"
    && operation.recordedBy?.type === "github-cli"
    && typeof operation.recordedBy.login === "string"
    && Boolean(operation.recordedBy.login)
    && operation.candidateSourceHashes
    && typeof operation.candidateSourceHashes === "object"
    && !Array.isArray(operation.candidateSourceHashes)
    && Array.isArray(operation.candidateKeys)
    && operation.candidateKeys.length > 0
    && new Set(operation.candidateKeys).size === operation.candidateKeys.length
    && Object.keys(operation.candidateSourceHashes).length === operation.candidateKeys.length
    && operation.candidateKeys.every((key) => typeof key === "string"
      && Boolean(key)
      && /^[a-f0-9]{64}$/.test(operation.candidateSourceHashes[key]));
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
      updatedAt: new Date().toISOString()
    };
  });
}

function getActiveExcludedCandidates() {
  return state.assessedCandidates.filter((candidate) => !candidate.assessment.hostedApplicable && !getApplicabilityOverride(candidate));
}

function defaultDecision(candidate) {
  const assessment = candidate.assessment || getPriorAssessment(candidate);
  return {
    sourceHash: candidate.hash,
    action: "no-change",
    ...createPlanMembership(),
    rationale: "",
    proposedText: assessment?.proposedText || (candidate.sourceType === "upstream" ? "" : extractRuleBody(candidate.text)),
    assessment,
    updatedAt: new Date().toISOString()
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
  const proposedText = String(saved.proposedText ?? defaultDecision(candidate).proposedText);
  const allowedActions = getAllowedActions(candidate, proposedText);
  if (!allowedActions.includes(saved.action) || !isValidPlanMembership(saved, candidate.key)) return defaultDecision(candidate);
  return {
    ...saved,
    proposedText,
    inPlan: saved.inPlan,
    planMembershipSource: saved.planMembershipSource,
    bulkOperationId: saved.bulkOperationId,
    rationale: String(saved.rationale || "").slice(0, DECISION_RATIONALE_MAX_LENGTH),
    assessment: candidate.assessment || getPriorAssessment(candidate),
  };
}

function getCatalogStatus(candidate) {
  const activeRules = candidate.relatedHostedRules.filter((rule) => rule.status === "active");
  const retiredRules = candidate.relatedHostedRules.filter((rule) => rule.status === "retired");
  if (activeRules.length) return { key: "mapped", label: "Mapped", rules: activeRules };
  if (retiredRules.length) return { key: "retired", label: "Retired", rules: retiredRules };
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
  if (candidate.state === "retired") {
    return catalogStatus === "mapped" ? ["no-change", "retire", "defer"] : ["no-change", "exclude", "defer"];
  }
  if (catalogStatus === "mapped") {
    const actions = ["no-change"];
    if (hasHostedTextChange(candidate, proposedText)) actions.push("update");
    return [...actions, "retire", "defer"];
  }
  if (catalogStatus === "retired") return ["no-change", "add", "defer"];
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
  if (candidate.state === "retired" && allowedActions.includes("retire")) return "retire";
  if (allowedActions.includes("update")) return "update";
  if (allowedActions.includes("add")) return "add";
  return "no-change";
}

function isPromotionAction(action) {
  return ["add", "update", "retire"].includes(action);
}

function getAssessment(candidate, decision) {
  const assessment = decision.assessment || candidate.assessment;
  if (assessment?.status !== "evaluated" || !assessment.selectionRationale?.trim() || !assessment.summary?.trim()) return null;
  const factors = assessment.selectionFactors;
  const valid = factors
    && FACTORS.every(([name]) => Number.isInteger(factors[name]) && factors[name] >= 0 && factors[name] <= 5)
    && ["add", "update", "retire", "no-change", "exclude", "defer"].includes(assessment.recommendation)
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
    .map((operation) => {
      const candidateSourceHashes = { ...operation.candidateSourceHashes };
      delete candidateSourceHashes[candidateKey];
      return { ...operation, candidateKeys: operation.candidateKeys.filter((key) => key !== candidateKey), candidateSourceHashes };
    })
    .filter((operation) => operation.candidateKeys.length > 0);
}

function restoreBulkOperationMembership(candidateKey, operationSnapshot) {
  if (!operationSnapshot) return;
  const existing = state.session.bulkOperations.find((operation) => operation.id === operationSnapshot.id);
  if (existing) {
    if (!existing.candidateKeys.includes(candidateKey)) {
      existing.candidateKeys.push(candidateKey);
      existing.candidateSourceHashes[candidateKey] = operationSnapshot.candidateSourceHashes[candidateKey];
    }
    return;
  }
  state.session.bulkOperations.push({
    ...operationSnapshot,
    candidateKeys: [candidateKey],
    candidateSourceHashes: { [candidateKey]: operationSnapshot.candidateSourceHashes[candidateKey] }
  });
}

function saveDecision(candidate, decision) {
  if (decision) {
    const { assessment, ...maintainerDecision } = decision;
    state.session.decisions[candidate.key] = {
      ...maintainerDecision,
      sourceHash: candidate.hash,
      updatedAt: new Date().toISOString()
    };
  } else {
    delete state.session.decisions[candidate.key];
  }
  state.session.updatedAt = new Date().toISOString();
  persistSession();
  syncCandidateTreeRows();
  renderBulkActions();
  syncAssessmentPlanToggle(candidate);
  renderDecisionOutputs();
}

function syncAssessmentPlanToggle(candidate) {
  if (state.activeKey !== candidate.key) return;
  const control = elements["assessment-panel"].querySelector("[data-plan-toggle]");
  if (control) control.checked = getDecision(candidate).inPlan;
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
      updatedAt: new Date().toISOString()
    };
  } else {
    delete state.session.decisions[candidate.key];
  }
  clearCandidateSelection(candidate);
  state.session.updatedAt = new Date().toISOString();
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

function getCandidateTokenValue(candidate, assessment) {
  const decision = getDecision(candidate);
  if (getApplicabilityOverride(candidate)) {
    if (decision.action === "retire") return -estimateGuardedTokens(getCurrentHostedText(candidate));
    return getAssessmentTokenValue(candidate, assessment, decision);
  }
  if (assessment.recommendation === "retire") return -estimateGuardedTokens(getCurrentHostedText(candidate));
  if (["add", "update"].includes(assessment.recommendation)) return assessment.guardedTokenDelta;
  return estimateGuardedTokens(getCurrentHostedText(candidate));
}

function formatCandidateTokenValue(candidate, assessment) {
  const value = getCandidateTokenValue(candidate, assessment);
  if (getApplicabilityOverride(candidate)) return isPromotionAction(getDecision(candidate).action) ? formatSignedNumber(value) : formatNumber(value);
  return ["add", "update", "retire"].includes(assessment.recommendation) ? formatSignedNumber(value) : formatNumber(value);
}

function renderAll(shouldRenderAssessment = true) {
  if (!state.bundle || !state.session) return;
  renderTarget();
  renderMetrics();
  renderCandidateList();
  if (shouldRenderAssessment) renderAssessment();
  renderAssessmentResults();
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
  const combined = getCapacityReports().find((report) => report.name === "test-combined");
  elements["status-excluded"].textContent = formatNumber(excludedCount);
  elements["status-mapped"].textContent = formatNumber(state.candidates.filter((candidate) => getCatalogStatus(candidate).key === "mapped").length);
  elements["status-unmapped"].textContent = formatNumber(state.candidates.filter((candidate) => getCatalogStatus(candidate).key === "unmapped").length);
  elements["status-headroom"].textContent = formatNumber(combined.budgetHeadroomTokens);
}

function getFilteredCandidates() {
  const query = state.queries["candidate-sources"].trim().toLowerCase();
  return state.candidates.filter((candidate) => {
    if (!query) return true;
    return [candidate.id, candidate.title, candidate.sourceId, candidate.sourceTitle, candidate.sourcePath, candidate.text, candidate.category, candidate.sourceLabel]
      .some((value) => String(value || "").toLowerCase().includes(query));
  });
}

function getBestCandidateSearchMatch() {
  const query = state.queries["candidate-sources"].trim().toLowerCase();
  if (!query) return null;
  const rank = (candidate) => {
    const values = [candidate.id, candidate.sourceId, candidate.title, candidate.sourceTitle]
      .map((value) => String(value || "").toLowerCase());
    if (values.some((value) => value === query)) return 0;
    if (values.some((value) => value.startsWith(query))) return 1;
    return 2;
  };
  return getFilteredCandidates().sort((left, right) => rank(left) - rank(right) || left.id.localeCompare(right.id))[0] || null;
}

function navigateCandidateSearch({ scroll = true } = {}) {
  elements["candidate-list"].querySelectorAll(".candidate-tree-row.search-match").forEach((row) => row.classList.remove("search-match"));
  const candidate = getBestCandidateSearchMatch();
  if (!candidate) return;
  const row = elements["candidate-list"].querySelector(`[data-candidate-key="${CSS.escape(candidate.key)}"]`);
  if (!row) return;
  row.closest("details.candidate-category")?.setAttribute("open", "");
  row.closest("details.candidate-source-root")?.setAttribute("open", "");
  row.classList.add("search-match");
  if (scroll) requestAnimationFrame(() => row.scrollIntoView({ block: "center", behavior: "smooth" }));
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
    createdAt: new Date().toISOString(),
    scope: "current-results",
    recommendationScope,
    query: state.queries["candidate-sources"],
    candidateKeys: candidates.map((candidate) => candidate.key),
    candidateSourceHashes: Object.fromEntries(candidates.map((candidate) => [candidate.key, candidate.hash])),
    recordedBy: { type: "github-cli", login: identity.login }
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
  state.session.updatedAt = new Date().toISOString();
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

function renderCandidateDecoration(decoration, className) {
  const hidden = decoration ? "" : " hidden";
  const tooltip = decoration ? ` data-workbench-tooltip="${escapeHtml(decoration.description)}"` : "";
  const description = decoration ? escapeHtml(decoration.description) : "";
  return `<svg class="codicon ${className}" aria-hidden="true"${tooltip}${hidden}><use href="icons/codicons/sprite.svg#codicon-diff-modified"></use></svg><span class="candidate-decoration-description sr-only">${description}</span>`;
}

function renderCandidateAggregateAttributes(decoration) {
  return decoration ? ` data-selection-status="${decoration.status}" data-workbench-tooltip="${escapeHtml(decoration.description)}"` : "";
}

function candidateAggregateClass(decoration) {
  return decoration ? ` candidate-aggregate-${decoration.status}` : "";
}

function renderCandidateList() {
  renderBulkActions();
  if (!state.candidates.length) {
    elements["candidate-list"].innerHTML = `<div class="empty-state compact"><h3>No Candidates Available</h3><p>No AI-evaluated candidates are present in this bundle.</p></div>`;
    return;
  }
  const overrideCandidates = state.candidates.filter((candidate) => getApplicabilityOverride(candidate));
  const regularCandidates = state.candidates.filter((candidate) => !getApplicabilityOverride(candidate));
  const overrideDecoration = getCandidateAggregateDecoration(overrideCandidates);
  const overrideGroup = overrideCandidates.length ? `
    <details class="candidate-source-root candidate-overrides-root${candidateAggregateClass(overrideDecoration)}" data-source-type="overrides" open>
      <summary class="clickable"${renderCandidateAggregateAttributes(overrideDecoration)}>${icon("shield")}<span class="candidate-parent-label"><strong>Overrides</strong>${renderCandidateDecoration(overrideDecoration, "candidate-parent-decoration-icon")}</span><span class="status-badge neutral count-badge type-compact">${formatCountLabel(overrideCandidates.length, "Override")}</span></summary>
      ${renderCandidateItems("overrides:all", overrideCandidates, "override-candidates")}
    </details>
  ` : "";
  const sources = [
    ["interactive", "Interactive Toolkit"],
    ["upstream", "Contributor Guidance"],
    ["maintainer", "Maintainer Proposals"]
  ];
  elements["candidate-list"].innerHTML = overrideGroup + sources.map(([sourceType, label]) => {
    const candidates = regularCandidates.filter((candidate) => candidate.sourceType === sourceType);
    if (!candidates.length) return "";
    const children = sourceType === "upstream"
      ? Object.entries(groupCandidatesBySource(candidates)).sort(([left], [right]) => left.localeCompare(right)).map(([, members]) => renderContributorDocument(members)).join("")
      : Object.entries(groupCandidatesByCategory(candidates)).sort(([left], [right]) => left.localeCompare(right)).map(([category, members]) => renderCandidateCategory(sourceType, category, members)).join("");
    const decoration = getCandidateAggregateDecoration(candidates);
    return `
      <details class="candidate-source-root${candidateAggregateClass(decoration)}" data-source-type="${escapeHtml(sourceType)}">
        <summary class="clickable"${renderCandidateAggregateAttributes(decoration)}>${icon("folder")}${renderSourceSummaryLabel(sourceType, label, decoration)}<span class="status-badge neutral count-badge type-compact">${formatCountLabel(candidates.length, "Candidate")}</span></summary>
        ${children}
      </details>
    `;
  }).join("");
  navigateCandidateSearch({ scroll: false });
}

function groupCandidatesBySource(candidates) {
  return candidates.reduce((groups, candidate) => {
    (groups[candidate.sourceId] ||= []).push(candidate);
    return groups;
  }, {});
}

function renderContributorDocument(candidates) {
  const source = candidates[0];
  const sectionKey = `upstream:${source.sourceId}`;
  const decoration = getCandidateAggregateDecoration(candidates);
  return `
    <details class="candidate-category contributor-document${candidateAggregateClass(decoration)}" data-source-type="upstream" data-source-id="${escapeHtml(source.sourceId)}">
      <summary class="clickable"${renderCandidateAggregateAttributes(decoration)}>
        ${icon("folder")}
        <span class="candidate-parent-label"><strong>${escapeHtml(source.sourceTitle)}</strong>${renderCandidateDecoration(decoration, "candidate-parent-decoration-icon")}</span>
        <span class="status-badge neutral count-badge type-compact">${formatCountLabel(candidates.length, "Candidate")}</span>
      </summary>
      ${renderCandidateItems(sectionKey, candidates, "contributor-candidates")}
    </details>
  `;
}

function renderSourceSummaryLabel(sourceType, label, decoration) {
  const source = state.bundle.snapshots.upstream;
  const shortCommit = source.currentCommit.slice(0, 8);
  const provenanceLabel = `${source.repository} · ${source.currentRef}@${shortCommit}`;
  const provenance = sourceType === "upstream"
    ? `<span class="source-provenance-pill type-compact" data-workbench-tooltip="${escapeHtml(provenanceLabel)}">${escapeHtml(provenanceLabel)}</span>`
    : "";
  const selection = decoration === undefined ? "" : renderCandidateDecoration(decoration, "candidate-parent-decoration-icon");
  return `<span class="source-summary-label"><strong>${escapeHtml(label)}</strong>${provenance}${selection}</span>`;
}

function renderCandidateCategory(sourceType, category, candidates) {
  const sectionKey = `${sourceType}:${category}`;
  const decoration = getCandidateAggregateDecoration(candidates);
  return `
    <details class="candidate-category${candidateAggregateClass(decoration)}" data-source-type="${escapeHtml(sourceType)}" data-category="${escapeHtml(category)}">
      <summary class="clickable"${renderCandidateAggregateAttributes(decoration)}>
        ${icon("folder")}
        <span class="candidate-parent-label"><strong>${escapeHtml(category)}</strong>${renderCandidateDecoration(decoration, "candidate-parent-decoration-icon")}</span>
        <span class="status-badge neutral count-badge type-compact">${formatCountLabel(candidates.length, "Candidate")}</span>
      </summary>
      ${renderCandidateItems(sectionKey, candidates)}
    </details>
  `;
}

function renderCandidateItems(sectionKey, candidates, extraClass = "") {
  const sortedCandidates = sortCandidates(candidates, getCandidateSort(sectionKey));
  return `<div class="candidate-category-items ${extraClass}" data-candidate-section="${escapeHtml(sectionKey)}">${renderCandidateListHeader(sectionKey)}${sortedCandidates.map(renderCandidateTreeRow).join("")}</div>`;
}

function renderCandidateListHeader(sectionKey) {
  const sort = getCandidateSort(sectionKey);
  const columns = [
    ["candidate", "Candidate", "Candidate", "Source rule ID and title."],
    ["state", "State", "Source State", "Lifecycle state of the source rule."],
    ["catalog", "Status", "Catalog Status", "Current mapping in the Hosted catalog."],
    ["impact", "Impact", "Impact", "Priority score balancing rule value and review risk."],
    ["cost", "Tokens", "Token Usage", "Unsigned values show current guarded-token usage. Signed values show the estimated change if the recommended action is promoted."],
    ["recommendation", "Recommended", "Recommendation", "AI-recommended action for maintainer review."]
  ];
  const button = (column) => renderSortButton(column, sort, { "candidate-sort": column[0], "candidate-section": sectionKey });
  return `<div class="candidate-list-header"><span aria-hidden="true"></span>${button(columns[0])}<span class="candidate-list-header-summary">${columns.slice(1).map(button).join("")}</span></div>`;
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
  const group = button.closest(".candidate-category-items");
  const candidates = Array.from(group.querySelectorAll(":scope > [data-candidate-key]"))
    .map((row) => state.candidates.find((candidate) => candidate.key === row.dataset.candidateKey))
    .filter(Boolean);
  const rowsByKey = new Map(Array.from(group.querySelectorAll(":scope > [data-candidate-key]")).map((row) => [row.dataset.candidateKey, row]));
  sortCandidates(candidates, state.candidateSorts[sectionKey]).forEach((candidate) => group.appendChild(rowsByKey.get(candidate.key)));
  group.querySelector(":scope > .candidate-list-header").outerHTML = renderCandidateListHeader(sectionKey);
  refreshPresentation();
}

function sortCandidates(candidates, sort) {
  const collator = new Intl.Collator(undefined, { numeric: true, sensitivity: "base" });
  const value = (candidate) => {
    const assessment = getAssessment(candidate, getDecision(candidate));
    if (sort.field === "candidate") return `${candidate.id} ${candidate.title}`;
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
    return directed || collator.compare(left.id, right.id);
  });
}

function getFilteredAssessmentCandidates() {
  const query = state.queries["assessment-results"].trim().toLowerCase();
  return state.assessedCandidates.filter((candidate) => !candidate.assessment.hostedApplicable).filter((candidate) => {
    if (!query) return true;
    return [candidate.id, candidate.title, candidate.sourcePath, candidate.text, candidate.category, candidate.sourceLabel, candidate.assessment.applicabilityRationale]
      .some((value) => String(value || "").toLowerCase().includes(query));
  });
}

function renderAssessmentResults() {
  if (!state.assessedCandidates.length) return;
  const filtered = getFilteredAssessmentCandidates();
  if (!filtered.length) {
    elements["assessment-results-list"].innerHTML = `<div class="empty-state compact"><h3>No Assessment Results</h3><p>No candidates match this outcome and search.</p></div>`;
  }
  else {
    const sources = [
      ["interactive", "Interactive Toolkit"],
      ["upstream", "Contributor Guidance"],
      ["maintainer", "Maintainer Proposals"]
    ];
    elements["assessment-results-list"].innerHTML = sources.map(([sourceType, label]) => {
      const candidates = filtered.filter((candidate) => candidate.sourceType === sourceType);
      if (!candidates.length) return "";
      const sectionKey = `assessment:${sourceType}`;
      const sortedCandidates = sortAssessmentCandidates(candidates, getAssessmentSort(sectionKey));
      return `
        <details class="candidate-source-root" ${state.queries["assessment-results"] ? "open" : ""}>
          <summary class="clickable">${icon("folder")}${renderSourceSummaryLabel(sourceType, label)}<span class="status-badge neutral count-badge type-compact">${formatNumber(candidates.length)} Excluded</span></summary>
          <div class="candidate-category-items" data-assessment-section="${escapeHtml(sectionKey)}">${renderAssessmentResultsHeader(sectionKey)}${sortedCandidates.map(renderAssessmentResultRow).join("")}</div>
        </details>
      `;
    }).join("");
  }
  syncAssessmentResultRows();
  renderAssessmentResultDetail();
}

function renderAssessmentResultsHeader(sectionKey) {
  const sort = getAssessmentSort(sectionKey);
  const columns = [
    ["candidate", "Candidate", "Candidate", "Source rule ID and title."],
    ["state", "State", "Source State", "Lifecycle state relative to the source baseline."],
    ["category", "Category", "Category", "AI-assigned Hosted category."],
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
  const group = button.closest(".candidate-category-items");
  const candidates = Array.from(group.querySelectorAll(":scope > [data-assessment-key]"))
    .map((row) => state.assessedCandidates.find((candidate) => candidate.key === row.dataset.assessmentKey))
    .filter(Boolean);
  const rowsByKey = new Map(Array.from(group.querySelectorAll(":scope > [data-assessment-key]")).map((row) => [row.dataset.assessmentKey, row]));
  const overridesByKey = new Map(Array.from(group.querySelectorAll(":scope > [data-assessment-override-for]")).map((panel) => [panel.dataset.assessmentOverrideFor, panel]));
  sortAssessmentCandidates(candidates, state.assessmentSorts[sectionKey]).forEach((candidate) => {
    group.appendChild(rowsByKey.get(candidate.key));
    const panel = overridesByKey.get(candidate.key);
    if (panel) group.appendChild(panel);
  });
  group.querySelector(":scope > .assessment-results-header").outerHTML = renderAssessmentResultsHeader(sectionKey);
  refreshPresentation();
}

function sortAssessmentCandidates(candidates, sort) {
  const collator = new Intl.Collator(undefined, { numeric: true, sensitivity: "base" });
  const value = (candidate) => {
    if (sort.field === "candidate") return `${candidate.id} ${candidate.title}`;
    if (sort.field === "state") return candidate.state;
    if (sort.field === "category") return formatHostedCategory(candidate.assessment.hostedCategory);
    if (sort.field === "recommendation") return formatRecommendation(candidate.assessment.recommendation);
    return getApplicabilityOverride(candidate) ? "contested" : "none";
  };
  return [...candidates].sort((left, right) => {
    const compared = collator.compare(value(left), value(right));
    const directed = sort.direction === "ascending" ? compared : -compared;
    return directed || collator.compare(left.id, right.id);
  });
}

function renderAssessmentResultRow(candidate) {
  const assessment = candidate.assessment;
  const override = getApplicabilityOverride(candidate);
  const expanded = override && state.assessmentOverrideExpandedKey === candidate.key;
  const overrideStatus = override
    ? `<button class="status-badge warning assessment-override-pill clickable" type="button" data-assessment-override-toggle="${escapeHtml(candidate.key)}" aria-expanded="${expanded}" aria-controls="assessment-override-${escapeHtml(candidate.key)}"><span>Contested</span><span class="assessment-override-chevron" aria-hidden="true">${icon(expanded ? "chevron-down" : "chevron-right")}</span></button>`
    : `<span class="status-badge neutral assessment-override-pill">None</span>`;
  const overridePanel = override ? `
    <div class="assessment-override-inline" id="assessment-override-${escapeHtml(candidate.key)}" data-assessment-override-for="${escapeHtml(candidate.key)}" ${expanded ? "" : "hidden"}>
      <div class="assessment-override-inline-copy"><strong>Provisional Override</strong><p>${escapeHtml(override.rationale)}</p><small>Recorded by @${escapeHtml(override.recordedBy.login)} on ${escapeHtml(formatTimestamp(override.recordedAt))}. The original AI exclusion remains in this audit.</small></div>
      <button class="icon-button clickable assessment-override-remove" type="button" data-assessment-override-remove="${escapeHtml(candidate.key)}" aria-label="Remove Override" data-workbench-tooltip="Remove Override">${icon("discard")}</button>
    </div>
  ` : "";
  return `
    <div class="assessment-result-row clickable ${candidate.key === state.assessmentActiveKey ? "active" : ""}" role="button" tabindex="0" data-assessment-key="${escapeHtml(candidate.key)}" ${candidate.key === state.assessmentActiveKey ? 'aria-current="true"' : ""}>
      <span class="candidate-tree-copy"><strong>${escapeHtml(candidate.id)}</strong><small>${escapeHtml(candidate.title)}</small></span>
      <span class="assessment-result-summary"><span class="candidate-lifecycle ${escapeHtml(candidate.state)}">${escapeHtml(capitalize(candidate.state))}</span><span>${escapeHtml(formatHostedCategory(assessment.hostedCategory))}</span><span class="recommendation-badge ${escapeHtml(assessment.recommendation)}">${escapeHtml(formatRecommendation(assessment.recommendation))}</span><span class="assessment-override-cell">${overrideStatus}</span></span>
    </div>
    ${overridePanel}
  `;
}

function syncAssessmentOverrideDisclosures() {
  elements["assessment-results-list"].querySelectorAll("[data-assessment-override-toggle]").forEach((button) => {
    const expanded = button.dataset.assessmentOverrideToggle === state.assessmentOverrideExpandedKey;
    button.setAttribute("aria-expanded", String(expanded));
    button.querySelector(".assessment-override-chevron").innerHTML = icon(expanded ? "chevron-down" : "chevron-right");
  });
  elements["assessment-results-list"].querySelectorAll("[data-assessment-override-for]").forEach((panel) => {
    panel.hidden = panel.dataset.assessmentOverrideFor !== state.assessmentOverrideExpandedKey;
  });
}

function renderAssessmentResultDetail() {
  const candidate = state.assessedCandidates.find((item) => item.key === state.assessmentActiveKey);
  if (!candidate) {
    elements["assessment-results-detail"].innerHTML = `<div class="empty-state">${icon("checklist")}<h2>Select an Assessment Result</h2><p>The source rule, applicability decision, AI rationale, and Hosted coverage will appear here.</p></div>`;
    return;
  }
  const assessment = candidate.assessment;
  const eligible = assessment.hostedApplicable;
  const catalogStatus = getCatalogStatus(candidate);
  elements["assessment-results-detail"].innerHTML = `
    <div class="assessment-title">
      <div>
        <div class="source-line detail-identity"><span>${escapeHtml(candidate.sourceLabel)}</span><span>/</span><span>${escapeHtml(candidate.id)}</span></div>
        <h2 class="detail-rule-title">${escapeHtml(candidate.title)}</h2>
        <div class="source-line"><span>${escapeHtml(candidate.sourcePath)}</span><span>${escapeHtml(candidate.hash.slice(0, 12))}</span></div>
      </div>
      ${renderDetailHeaderActions(`
        <span class="status-badge ${eligible ? "success" : "warning"}">${eligible ? "Eligible" : "Excluded"}</span>
        ${renderCatalogStatusBadge(catalogStatus)}
      `)}
    </div>
    <div class="assessment-content scroll-surface">
      <div class="section-block"><span class="section-label">Source Rule:</span><pre class="evidence-box scroll-surface">${escapeHtml(candidate.text)}</pre>${candidate.sourceRationale ? `<div class="assessment-rationale proposal-rationale"><strong>Proposal rationale</strong><p>${escapeHtml(candidate.sourceRationale)}</p></div>` : ""}</div>
      ${renderMappedHostedRules(catalogStatus)}
      <div class="section-block"><span class="section-label">Applicability Decision:</span><div class="ai-evaluation-summary subcontext-container"><div class="ai-evaluation-heading"><strong>${eligible ? "Eligible for candidate catalog" : "Excluded from candidate catalog"}</strong><span class="recommendation-badge ${escapeHtml(assessment.recommendation)}">Recommend ${escapeHtml(formatRecommendation(assessment.recommendation))}</span></div><p>${escapeHtml(assessment.applicabilityRationale)}</p></div></div>
      <div class="section-block"><span class="section-label">AI Evaluation:</span><h3>${escapeHtml(assessment.summary)}</h3><p class="coverage-summary">${escapeHtml(assessment.impactDescription)}</p>${renderPriorityAssessment(assessment)}</div>
      <div class="section-block"><span class="section-label">Related Hosted Coverage:</span><p class="coverage-summary evidence-summary-box subcontext-container">${escapeHtml(assessment.currentHostedCoverage)}</p></div>
      ${renderApplicabilityOverride(candidate)}
    </div>
  `;
}

function renderApplicabilityOverride(candidate) {
  const override = getApplicabilityOverride(candidate);
  const identity = globalThis.__HOSTED_RULE_WORKBENCH__?.maintainerIdentity;
  if (override) {
    return `
      <div class="section-block maintainer-override" data-override-key="${escapeHtml(candidate.key)}">
        <span class="section-label">Maintainer Override:</span>
        <div class="override-record subcontext-container">
          <div class="override-record-heading"><strong>Provisional Override</strong><span class="override-record-actions"><span class="status-badge warning">Reincluded</span><button class="icon-button clickable" type="button" data-override-remove aria-label="Remove Override" data-workbench-tooltip="Remove Override">${icon("discard")}</button></span></div>
          <label class="override-rationale"><span class="control-subtitle">Override Rationale:</span><textarea class="scroll-surface" readonly>${escapeHtml(override.rationale)}</textarea></label>
          <small>Recorded by @${escapeHtml(override.recordedBy.login)} on ${escapeHtml(formatTimestamp(override.recordedAt))}. The original AI exclusion remains in this audit.</small>
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
        <label class="override-rationale"><span class="control-subtitle">Override Rationale:</span><textarea class="scroll-surface" maxlength="${OVERRIDE_RATIONALE_MAX_LENGTH}" aria-describedby="override-rationale-limit" placeholder="Briefly explain why the AI exclusion is incorrect."></textarea><small id="override-rationale-limit" class="rationale-limit">0 / ${OVERRIDE_RATIONALE_MAX_LENGTH} characters</small></label>
        <p class="override-audit-note">The original AI result remains in the assessment audit. This provisional override records the corrected outcome, rationale, authenticated maintainer, and timestamp.</p>
        <div class="override-actions"><button class="button secondary clickable" type="button" data-override-cancel>Cancel</button><button class="button primary clickable" type="button" data-override-apply disabled>Apply Override</button></div>
      </div>
      <div class="read-only-boundary">${icon("lock")}<span>The AI assessment is read-only. A maintainer override records a separate correction without erasing the original result.</span></div>
    </div>
  `;
}

function handleApplicabilityOverrideInput(event) {
  if (!event.target.matches(".override-rationale textarea")) return;
  const form = event.target.closest(".override-form");
  form.querySelector(".rationale-limit").textContent = `${event.target.value.length} / ${OVERRIDE_RATIONALE_MAX_LENGTH} characters`;
  form.querySelector("[data-override-apply]").disabled = !event.target.value.trim();
}

async function handleApplicabilityOverrideClick(event) {
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
  if (event.target.closest("[data-override-remove]")) {
    await updateOverrideLifecycle(candidate, null, null);
    showToast("Provisional override removed");
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
    recordedAt: new Date().toISOString(),
    recordedBy: { type: "github-cli", login: identity.login }
  };
  await updateOverrideLifecycle(candidate, override, { ...defaultDecision(candidate), ...createPlanMembership("override") });
  setWorkspaceTab("candidate-sources");
  showToast("Candidate moved to Overrides and added to plan");
}

function renderCandidateTreeRow(candidate) {
  const decision = getDecision(candidate);
  const assessment = getAssessment(candidate, decision);
  const impact = calculateImpact(assessment.factors);
  const catalogStatus = getCatalogStatus(candidate);
  const inPlan = decision.inPlan;
  const decoration = getCandidateDecoration(candidate);
  return `
    <div class="candidate-tree-row clickable ${candidate.key === state.activeKey ? "active" : ""} ${inPlan ? "in-plan" : ""} ${decoration ? `candidate-decoration-${decoration.status}` : ""}" role="button" tabindex="0" data-candidate-key="${escapeHtml(candidate.key)}" ${candidate.key === state.activeKey ? 'aria-current="true"' : ""}>
      <input type="checkbox" data-decision-key="${escapeHtml(candidate.key)}" aria-label="${inPlan ? "Remove" : "Add"} ${escapeHtml(candidate.id)} ${inPlan ? "from" : "to"} promotion plan" data-workbench-tooltip="${inPlan ? "Remove candidate from promotion plan" : "Add candidate to promotion plan"}" ${inPlan ? "checked" : ""}>
      <span class="candidate-tree-copy"><strong>${escapeHtml(candidate.id)}</strong><small>${escapeHtml(candidate.title)}</small>${renderCandidateDecoration(decoration, "candidate-decoration-icon")}</span>
      <span class="candidate-tree-summary"><span class="candidate-lifecycle ${escapeHtml(candidate.state)}">${escapeHtml(capitalize(candidate.state))}</span><span class="catalog-status ${catalogStatus.key}">${escapeHtml(catalogStatus.label)}</span><span class="tree-impact">${impact}</span><span class="tree-cost">${formatCandidateTokenValue(candidate, assessment)}</span><span class="recommendation-badge ${escapeHtml(assessment.recommendation)}">${escapeHtml(formatRecommendation(assessment.recommendation))}</span></span>
    </div>
  `;
}

function renderAssessment() {
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
  const draftCost = getAssessmentTokenValue(candidate, assessment, decision);
  const combined = getCapacityReports().find((report) => report.name === "test-combined");
  const projectedHeadroom = combined.budgetHeadroomTokens - draftCost;
  const catalogStatus = getCatalogStatus(candidate);
  const allowedActions = getAllowedActions(candidate, decision.proposedText);
  const unchangedMappedRule = catalogStatus.key === "mapped" && !hasHostedTextChange(candidate, decision.proposedText);

  elements["assessment-panel"].innerHTML = `
    <div class="assessment-title">
      <div>
        <div class="source-line detail-identity">
          <span>${escapeHtml(candidate.sourceLabel)}</span>
          <span>/</span>
          <span>${escapeHtml(candidate.id)}</span>
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
          <div class="score-item cost"><span>Token cost</span><strong>${formatCandidateTokenValue(candidate, assessment)}</strong></div>
          <div class="score-item efficiency"><span>Headroom after</span><strong>${formatNumber(projectedHeadroom)}</strong></div>
        </div>
        ${renderPriorityAssessment(assessment)}
      </div>

      <div class="section-block">
        <span class="section-label">Related Hosted Coverage:</span>
        <p class="coverage-summary evidence-summary-box subcontext-container">${escapeHtml(assessment.currentHostedCoverage)}</p>
      </div>

      <div class="section-block">
        <span class="section-label">Proposed Hosted Rule:</span>
        <pre class="evidence-box proposed-rule scroll-surface">${escapeHtml(assessment.proposedText || "No Hosted rule change proposed.")}</pre>
      </div>

      <div class="section-block rule-actions">
        <span class="section-label">Rule Actions:</span>
        <div class="rule-actions-content subcontext-container">
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
            <label class="plan-toggle clickable">
              <input type="checkbox" data-plan-toggle ${decision.inPlan ? "checked" : ""}>
              <span>Include this candidate in the promotion plan</span>
            </label>
          </div>
          <div class="field-stack control-group rationale-control-group">
            <div class="rationale-heading"><span class="control-subtitle" id="decision-rationale-label">Decision Rationale:</span><button class="titlebar-icon clickable rationale-save" type="button" data-rationale-save aria-label="${state.rationaleReturnView === "plan" ? "Save decision rationale and return to Promotion Plan" : "Save decision rationale"}" data-workbench-tooltip="${state.rationaleReturnView === "plan" ? "Save and return to Promotion Plan" : "Save decision rationale"}" ${decision.rationale.trim() ? "" : "disabled"}>${icon("save")}</button></div>
            <label><textarea class="scroll-surface" data-decision-field="rationale" maxlength="${DECISION_RATIONALE_MAX_LENGTH}" aria-labelledby="decision-rationale-label" aria-describedby="decision-rationale-limit" placeholder="Record why this action is appropriate.">${escapeHtml(decision.rationale)}</textarea><small class="rationale-limit" id="decision-rationale-limit">${decision.rationale.length} / ${DECISION_RATIONALE_MAX_LENGTH} characters</small></label>
          </div>
        </div>
      </div>
    </div>
  `;
}

function renderPriorityAssessment(assessment) {
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
          ${FACTORS.filter(([, , , kind]) => kind === "value").map(([name, label, description, kind]) => factorReadout(label, description, kind, assessment.factors[name])).join("")}
        </div>
      </section>
      <section class="factor-group penalty">
        <div class="factor-group-heading"><strong>Review Risk:</strong><span class="direction-badge negative">Reduces Impact</span></div>
        <div class="factor-grid">
          ${FACTORS.filter(([, , , kind]) => kind === "penalty").map(([name, label, description, kind]) => factorReadout(label, description, kind, assessment.factors[name])).join("")}
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
    updateDecision(candidate, { action });
    syncAssessmentActionControls(candidate);
    return;
  }
  if (event.target.hasAttribute("data-plan-toggle")) {
    if (event.target.checked) updateDecision(candidate, { inPlan: true });
    else removePlanMembership(candidate);
    return;
  }
  if (event.target.dataset.decisionField) {
    const value = event.target.dataset.decisionField === "rationale"
      ? event.target.value.slice(0, DECISION_RATIONALE_MAX_LENGTH)
      : event.target.value;
    event.target.value = value;
    updateDecision(candidate, { [event.target.dataset.decisionField]: value });
    if (event.target.dataset.decisionField === "rationale") {
      const counter = elements["assessment-panel"].querySelector(".rationale-limit");
      if (counter) counter.textContent = `${value.length} / ${DECISION_RATIONALE_MAX_LENGTH} characters`;
      const save = elements["assessment-panel"].querySelector("[data-rationale-save]");
      if (save) save.disabled = !value.trim();
    }
    if (event.target.dataset.decisionField === "proposedText") refreshAssessmentScores(candidate);
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
function syncAssessmentActionControls(candidate) {
  const decision = getDecision(candidate);
  elements["assessment-panel"].querySelectorAll("[data-rule-action]").forEach((control) => {
    const selected = control.dataset.ruleAction === decision.action;
    control.checked = selected;
    control.closest(".action-option")?.classList.toggle("selected", selected);
  });
  const badge = elements["assessment-panel"].querySelector(":scope > .assessment-title .decision-badge");
  if (badge) {
    badge.className = `decision-badge ${decision.action}`;
    badge.textContent = formatRecommendation(decision.action);
  }
  refreshAssessmentScores(candidate);
}

async function handleAssessmentClick(event) {
  if (!event.target.closest("[data-rationale-save]")) return;
  const candidate = getActiveCandidate();
  if (!candidate || !getDecision(candidate).rationale.trim()) return;
  const returnToPlan = state.rationaleReturnView === "plan";
  await persistencePromise;
  showToast("Decision rationale saved");
  if (returnToPlan) {
    state.rationaleReturnView = null;
    switchView("plan");
  }
}

function refreshAssessmentScores(candidate) {
  const decision = getDecision(candidate);
  const assessment = getAssessment(candidate, decision);
  const impact = calculateImpact(assessment.factors);
  const cost = getAssessmentTokenValue(candidate, assessment, decision);
  const combined = getCapacityReports().find((report) => report.name === "test-combined");
  const scoreValues = elements["assessment-panel"].querySelectorAll(".score-item strong");
  if (scoreValues.length === 3) {
    scoreValues[0].textContent = impact;
    scoreValues[1].textContent = formatCandidateTokenValue(candidate, assessment);
    scoreValues[2].textContent = formatNumber(combined.budgetHeadroomTokens - cost);
  }
}

function renderPlan() {
  const planCandidates = sortPlanCandidates(getPlanCandidates(), state.planSort);
  elements["plan-table-head"].innerHTML = renderPlanHeader();
  elements["empty-plan"].hidden = planCandidates.length > 0;
  elements["plan-table-body"].innerHTML = planCandidates.map((candidate) => {
    const decision = getDecision(candidate);
    const assessment = getAssessment(candidate, decision);
    const impact = assessment ? calculateImpact(assessment.factors) : null;
    const cost = getPlanTokenDisplay(candidate);
    const readiness = getPlanReadiness(candidate);
    return `
      <tr class="plan-candidate-row clickable" tabindex="0" data-plan-row="${escapeHtml(candidate.key)}" aria-label="Open ${escapeHtml(candidate.id)} candidate">
        <td class="plan-candidate"><span class="candidate-link">${escapeHtml(candidate.id)}</span><br><span class="plan-candidate-title">${escapeHtml(candidate.title)}</span></td>
        <td class="plan-source">${escapeHtml(formatTitleCase(candidate.sourceLabel))}</td>
        <td class="plan-type"><span class="status-badge neutral plan-membership-badge">${escapeHtml(formatTitleCase(decision.planMembershipSource))}</span></td>
        <td class="plan-action"><span class="recommendation-badge ${escapeHtml(decision.action)}">${escapeHtml(formatRecommendation(decision.action))}</span></td>
        <td class="mono">${impact}</td>
        <td class="mono">${cost}</td>
        <td>${readiness.ready ? `<span class="status-badge success">${readiness.label}</span>` : readiness.actionRequired ? `<button class="status-badge warning plan-detail-link clickable" type="button" data-plan-action="${escapeHtml(candidate.key)}" aria-label="Choose a rule action for ${escapeHtml(candidate.id)}" data-workbench-tooltip="Open candidate and choose a rule action">${icon("edit")}<span>${readiness.label}</span></button>` : `<button class="status-badge warning plan-detail-link clickable" type="button" data-plan-detail="${escapeHtml(candidate.key)}" aria-label="Enter decision rationale for ${escapeHtml(candidate.id)}" data-workbench-tooltip="Open candidate and enter decision rationale">${icon("edit")}<span>${readiness.label}</span></button>`}</td>
        <td class="plan-actions"><button class="plan-undo clickable" type="button" data-plan-undo="${escapeHtml(candidate.key)}" aria-label="Undo decision and remove from promotion plan" data-workbench-tooltip="Undo decision and remove from promotion plan">${icon("discard")}</button></td>
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
    if (sort.field === "candidate") return `${candidate.id} ${candidate.title}`;
    if (sort.field === "source") return candidate.sourceLabel;
    if (sort.field === "type") return decision.planMembershipSource;
    if (sort.field === "action") return formatRecommendation(decision.action);
    if (sort.field === "impact") return assessment ? calculateImpact(assessment.factors) : Number.NEGATIVE_INFINITY;
    if (sort.field === "cost") return getPlanTokenValue(candidate);
    return getPlanReadiness(candidate).label;
  };
  return [...candidates].sort((left, right) => {
    const leftValue = value(left);
    const rightValue = value(right);
    const compared = typeof leftValue === "number" ? leftValue - rightValue : collator.compare(leftValue, rightValue);
    const directed = sort.direction === "ascending" ? compared : -compared;
    return directed || collator.compare(left.id, right.id);
  });
}

function getPlanReadiness(candidate) {
  const decision = getDecision(candidate);
  const assessment = getAssessment(candidate, decision);
  const actionRequired = !isPromotionAction(decision.action);
  const rationaleRequired = !decision.rationale.trim();
  return {
    actionRequired,
    ready: Boolean(assessment) && !actionRequired && !rationaleRequired,
    label: actionRequired ? "Needs action" : rationaleRequired ? "Needs rationale" : assessment ? "Ready" : "Needs AI assessment"
  };
}

function getPlanTokenValue(candidate) {
  const decision = getDecision(candidate);
  const assessment = getAssessment(candidate, decision);
  if (!isPromotionAction(decision.action) && getApplicabilityOverride(candidate) && assessment) {
    return getAssessmentTokenValue(candidate, assessment, decision);
  }
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
    const row = elements["candidate-list"].querySelector(`[data-candidate-key="${CSS.escape(key)}"]`);
    if (!row) return;
    row.closest("details.candidate-category")?.setAttribute("open", "");
    row.closest("details.candidate-source-root")?.setAttribute("open", "");
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
  const assessment = getAssessment(candidate, decision);
  if (["add", "update"].includes(decision.action)) return assessment ? getAssessmentTokenValue(candidate, assessment, decision) : 0;
  if (decision.action !== "retire") return 0;
  const estimatedTokens = Math.ceil(getCurrentHostedText(candidate).length / 4);
  return -Math.ceil(estimatedTokens * 1.25);
}

function getPlanAffectedSurfaces(candidate) {
  const decision = getDecision(candidate);
  const assessment = getAssessment(candidate, decision);
  if (["add", "update"].includes(decision.action)) return assessment?.affectedSurfaces || [];
  if (decision.action !== "retire") return [];
  const placementSurfaces = getCatalogStatus(candidate).rules
    .flatMap((rule) => (rule.placements || []).map((placement) => placement.surfaceId));
  return placementSurfaces.length ? placementSurfaces : assessment?.affectedSurfaces || [];
}

function renderCapacity() {
  const reports = getCapacityReports().filter((report) => report.kind === "combined");
  const draftCost = getPlanCandidates().reduce((sum, candidate) => sum + getPlanTokenValue(candidate), 0);
  elements["capacity-panel"].innerHTML = `
    <p class="eyebrow">Plan projection</p>
    <h3>Guidance capacity</h3>
    ${reports.map((report) => {
      const tokenDelta = getProjectedCapacityDelta(report);
      const projectedGuardedTokens = Math.max(0, report.guardedTokens + tokenDelta);
      const projectedHeadroomTokens = report.budgetTokens - projectedGuardedTokens;
      const utilizationPercent = Math.round((projectedGuardedTokens / report.budgetTokens) * 10000) / 100;
      const percent = Math.min(100, utilizationPercent);
      const fillClass = percent > 85 ? "danger" : percent > 65 ? "warning" : "";
      return `
        <div class="capacity-group">
          <div class="capacity-line"><span>${escapeHtml(report.name)}</span><strong>${formatNumber(projectedHeadroomTokens)} free</strong></div>
          <progress class="capacity-progress ${fillClass}" max="100" value="${percent}">${percent}%</progress>
          <div class="capacity-line"><span>${formatNumber(projectedGuardedTokens)} guarded</span><span>${utilizationPercent}%</span></div>
        </div>
      `;
    }).join("")}
    <div class="score-item"><span>Draft item estimate</span><strong>${formatNumber(draftCost)} tokens</strong></div>
    <p class="capacity-footnote">Projected from the current baseline and selected plan. Exact post-render capacity is produced during staged promotion preview.</p>
  `;
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
  const readiness = getPreviewReadiness();
  const planCandidates = readiness.planCandidates;
  const ready = readiness.ready;
  elements["approval-badge"].className = `status-badge ${ready ? "success" : "warning"}`;
  elements["approval-badge"].textContent = ready ? "Ready to export" : "Not ready";
  elements["preview-status"].textContent = ready ? "Ready" : "Draft";
  elements["preview-summary"].innerHTML = `
    <p class="eyebrow">Review state</p>
    <h3>Draft summary</h3>
    <dl class="summary-list">
      <div><dt>Snapshot</dt><dd>${escapeHtml(state.bundle.snapshots.upstream.currentCommit.slice(0, 8))}</dd></div>
      <div><dt>Mapped</dt><dd>${state.candidates.filter((candidate) => getCatalogStatus(candidate).key === "mapped").length}</dd></div>
      <div><dt>Not mapped</dt><dd>${state.candidates.filter((candidate) => getCatalogStatus(candidate).key === "unmapped").length}</dd></div>
      <div><dt>Plan items</dt><dd>${planCandidates.length}</dd></div>
      <div><dt>Approval</dt><dd>${escapeHtml(readiness.status)}</dd></div>
    </dl>
  `;
  if (elements["approver-name"].value !== state.session.approverName) {
    elements["approver-name"].value = state.session.approverName || "";
  }
  renderApprovalRequirements(readiness);
  elements["approve-export-button"].disabled = !ready;
  elements["preview-diff"].innerHTML = renderPreviewChanges(planCandidates);
  elements["preview-payload-diff"].innerHTML = renderPayloadChanges();
  renderRawPayload(buildApprovalPayload());
}

function renderRawPayload(payload) {
  const rawPayload = JSON.stringify(payload, null, 2);
  const lines = rawPayload.split("\n");
  const changes = getRawPayloadChanges(lines, payload.decisions);
  const hasChanges = changes.length > 0;

  rawPayloadChangeIndex = 0;
  rawPayloadChangeCount = changes.length;
  elements["preview-raw-heading"].hidden = !hasChanges;
  elements["raw-payload-empty"].hidden = hasChanges;
  elements["preview-json"].hidden = !hasChanges;
  elements["raw-change-tools"].hidden = !hasChanges;
  elements["raw-change-count"].textContent = `${rawPayloadChangeCount} added or updated record${rawPayloadChangeCount === 1 ? "" : "s"}`;

  if (!hasChanges) {
    elements["raw-payload-empty"].innerHTML = renderPreviewEmptyState(
      "json",
      "No Raw Payload Changes",
      "Add or update a Promotion Plan item to review its generated selection payload."
    );
    elements["preview-json"].scrollTop = 0;
    updateRawPayloadChangeNavigation();
    return;
  }

  const changedLines = new Map();
  changes.forEach((change, changeIndex) => {
    for (let lineIndex = change.start; lineIndex <= change.end; lineIndex += 1) changedLines.set(lineIndex, changeIndex);
  });
  const renderedLines = lines.map((line, lineIndex) => {
    const changeIndex = changedLines.get(lineIndex);
    const changed = changeIndex !== undefined;
    const changeAttribute = changed ? ` data-raw-change-index="${changeIndex}"` : "";
    return `<span class="raw-json-line${changed ? " raw-json-added" : ""}"${changeAttribute}><span class="raw-json-line-number" data-line-number="${lineIndex + 1}" aria-hidden="true"></span><span class="raw-json-line-marker" aria-hidden="true"></span><code>${escapeHtml(line)}</code></span>`;
  }).join("\n");
  elements["preview-json"].innerHTML = `<span class="highlight-width-track">${renderedLines}</span>`;
  if (elements["preview-json"].textContent !== rawPayload) throw new Error("raw payload rendering changed JSON content");
  navigateRawPayloadChange(0, "auto");
}

function getRawPayloadChanges(lines, decisions) {
  const changes = [];
  let inDecisions = false;
  let decisionIndex = 0;
  let start = null;
  lines.forEach((line, lineIndex) => {
    if (line === '  "decisions": [') {
      inDecisions = true;
      return;
    }
    if (!inDecisions) return;
    if (start === null && line === "    {") {
      start = lineIndex;
      return;
    }
    if (start !== null && /^    }[,]?$/.test(line)) {
      const decision = decisions[decisionIndex];
      if (decision?.inPlan && (["add", "update"].includes(decision.action) || decision.applicabilityOverride)) {
        changes.push({ start, end: lineIndex });
      }
      decisionIndex += 1;
      start = null;
      return;
    }
    if (start === null && /^  ][,]?$/.test(line)) inDecisions = false;
  });
  return changes;
}

function navigateRawPayloadChange(index, behavior = "smooth") {
  if (!rawPayloadChangeCount) return;
  rawPayloadChangeIndex = Math.max(0, Math.min(index, rawPayloadChangeCount - 1));
  const target = elements["preview-json"].querySelector(`[data-raw-change-index="${rawPayloadChangeIndex}"]`);
  const scrollTop = target.getBoundingClientRect().top - elements["preview-json"].getBoundingClientRect().top + elements["preview-json"].scrollTop;
  elements["preview-json"].scrollTo({
    top: Math.max(0, scrollTop),
    behavior
  });
  updateRawPayloadChangeNavigation();
}

function getRawPayloadChangeViewportPosition() {
  if (!rawPayloadChangeCount) return "none";
  const changeLines = elements["preview-json"].querySelectorAll(`[data-raw-change-index="${rawPayloadChangeIndex}"]`);
  if (!changeLines.length) return "none";
  const viewport = elements["preview-json"].getBoundingClientRect();
  const firstLine = changeLines[0].getBoundingClientRect();
  const lastLine = changeLines[changeLines.length - 1].getBoundingClientRect();
  if (lastLine.bottom < viewport.top) return "above";
  if (firstLine.top > viewport.bottom) return "below";
  return "visible";
}

function navigateRawPayloadDirection(direction) {
  const position = getRawPayloadChangeViewportPosition();
  const snapToCurrent = (direction < 0 && position === "above") || (direction > 0 && position === "below");
  navigateRawPayloadChange(rawPayloadChangeIndex + (snapToCurrent ? 0 : direction));
}

function updateRawPayloadChangeNavigation() {
  const position = getRawPayloadChangeViewportPosition();
  elements["raw-change-position"].textContent = rawPayloadChangeCount ? `${rawPayloadChangeIndex + 1} of ${rawPayloadChangeCount}` : "";
  elements["raw-previous-change"].disabled = !rawPayloadChangeCount || (rawPayloadChangeIndex === 0 && position !== "above");
  elements["raw-next-change"].disabled = !rawPayloadChangeCount || (rawPayloadChangeIndex === rawPayloadChangeCount - 1 && position !== "below");
}

function renderPreviewChanges(candidates) {
  if (!candidates.length) {
    return renderPreviewEmptyState(
      "git-pull-request-draft",
      "No Proposed Changes",
      "Add an available rule action to the promotion plan to review its line-level diff."
    );
  }
  const unresolved = candidates.filter((candidate) => !isPromotionAction(getDecision(candidate).action));
  const resolved = candidates.filter((candidate) => isPromotionAction(getDecision(candidate).action));
  const warning = unresolved.length ? `<div class="empty-state compact warning-state">${icon("warning")}<h3>${unresolved.length} Action${unresolved.length === 1 ? "" : "s"} Required</h3><p>Complete Rule Actions from the Promotion Plan before reviewing proposed changes.</p></div>` : "";
  return warning + resolved.map((candidate) => {
    const decision = getDecision(candidate);
    const currentText = getCurrentHostedText(candidate);
    const lines = decision.action === "add"
      ? splitDiffLines(decision.proposedText).map((text) => ({ type: "add", text }))
      : decision.action === "retire"
        ? splitDiffLines(currentText).map((text) => ({ type: "delete", text }))
        : diffTextLines(currentText, decision.proposedText);
    return renderRuleDiff(candidate, decision.action, lines);
  }).join("");
}

function renderRuleDiff(candidate, action, lines) {
  let oldLine = 0;
  let newLine = 0;
  let additions = 0;
  let deletions = 0;
  const renderedLines = lines.map((line) => {
    if (line.type !== "add") oldLine += 1;
    if (line.type !== "delete") newLine += 1;
    if (line.type === "add") additions += 1;
    if (line.type === "delete") deletions += 1;
    const oldNumber = line.type === "add" ? "" : oldLine;
    const newNumber = line.type === "delete" ? "" : newLine;
    const marker = line.type === "add" ? "+" : line.type === "delete" ? "-" : " ";
    const description = line.type === "add" ? `Added line ${newLine}` : line.type === "delete" ? `Removed line ${oldLine}` : `Unchanged line ${newLine}`;
    return `<div class="diff-line ${line.type}" aria-label="${description}"><span class="diff-line-number">${oldNumber}</span><span class="diff-line-number">${newNumber}</span><span class="diff-marker" aria-hidden="true">${marker}</span><code>${escapeHtml(line.text || " ")}</code></div>`;
  }).join("");
  const mappedRuleIds = candidate.assessment.targetHostedRuleId || "New Hosted rule";
  const sourceId = candidate.sourceType === "upstream" ? candidate.sourceId.toUpperCase() : candidate.id;
  return `
    <section class="preview-change" aria-label="${escapeHtml(candidate.id)} proposed ${escapeHtml(action)}">
      <div class="preview-change-heading"><div><strong>${escapeHtml(sourceId)}</strong><span>${escapeHtml(candidate.title)}</span></div><span class="recommendation-badge ${escapeHtml(action)}">${escapeHtml(formatRecommendation(action))}</span></div>
      <div class="diff-file-heading"><span>${escapeHtml(mappedRuleIds)}</span><span class="diff-stats"><span>+${additions}</span><span>-${deletions}</span></span></div>
      <div class="diff-lines scroll-surface"><div class="highlight-width-track">${renderedLines}</div></div>
    </section>
  `;
}

function renderPayloadChanges() {
  const changes = state.candidates.map((candidate) => {
    const current = getDecision(candidate);
    const baseline = defaultDecision(candidate);
    const before = {
      action: baseline.action,
      inPlan: baseline.inPlan,
      planMembership: { source: baseline.planMembershipSource, bulkOperationId: baseline.bulkOperationId },
      rationale: baseline.rationale,
      proposedText: baseline.proposedText,
      applicabilityOverride: null
    };
    const after = {
      action: current.action,
      inPlan: current.inPlan,
      planMembership: { source: current.planMembershipSource, bulkOperationId: current.bulkOperationId },
      rationale: current.rationale,
      proposedText: current.proposedText,
      applicabilityOverride: getApplicabilityOverride(candidate)
    };
    const changedKeys = Object.keys(after).filter((key) => JSON.stringify(before[key]) !== JSON.stringify(after[key]));
    if (!changedKeys.length) return null;
    return {
      candidate,
      before: Object.fromEntries(changedKeys.map((key) => [key, before[key]])),
      after: Object.fromEntries(changedKeys.map((key) => [key, after[key]]))
    };
  }).filter(Boolean);
  if (!changes.length) {
    return renderPreviewEmptyState(
      "diff",
      "No Payload Changes",
      "Add or update a Promotion Plan item to review its selection payload changes."
    );
  }
  return changes.map(({ candidate, before, after }) => {
    const beforeLines = JSON.stringify(before, null, 2).split("\n");
    const afterLines = JSON.stringify(after, null, 2).split("\n");
    return `
      <section class="payload-change" aria-label="${escapeHtml(candidate.id)} selection payload changes">
        <div class="payload-change-heading"><div><strong>${escapeHtml(candidate.id)}</strong><span>${escapeHtml(candidate.title)}</span></div></div>
        <div class="payload-columns">
          ${renderPayloadColumn("Default", beforeLines, "delete")}
          ${renderPayloadColumn("Current", afterLines, "add")}
        </div>
      </section>
    `;
  }).join("");
}

function renderPayloadColumn(label, lines, type) {
  const marker = type === "add" ? "+" : "-";
  return `
    <div class="payload-column ${type}">
      <div class="payload-column-heading">${label}</div>
      <div class="payload-code scroll-surface"><div class="highlight-width-track">${lines.map((line, index) => `<div class="payload-line"><span class="payload-line-number">${index + 1}</span><span class="payload-line-marker" aria-hidden="true">${marker}</span><code>${escapeHtml(line)}</code></div>`).join("")}</div></div>
    </div>
  `;
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
  const missingActionCount = planCandidates.filter((candidate) => !isPromotionAction(getDecision(candidate).action)).length;
  const missingRationaleCount = planCandidates.filter((candidate) => {
    const decision = getDecision(candidate);
    return !getAssessment(candidate, decision) || !decision.rationale.trim();
  }).length;
  const missingRationale = missingRationaleCount > 0;
  const approverName = String(state.session.approverName || "").trim();
  let status = "ready";
  if (planCandidates.length === 0) status = "no actions";
  else if (missingActionCount) status = "needs action";
  else if (missingRationale) status = "needs rationale";
  else if (!approverName) status = "needs approver";
  return {
    planCandidates,
    approverName,
    missingActionCount,
    missingRationaleCount,
    status,
    ready: planCandidates.length > 0 && missingActionCount === 0 && !missingRationale && Boolean(approverName)
  };
}

function renderApprovalRequirements(readiness) {
  const requirements = [
    ["Plan actions", readiness.planCandidates.length ? `${readiness.planCandidates.length} selected` : "None selected", readiness.planCandidates.length > 0],
    ["Rule actions", readiness.missingActionCount ? `${readiness.missingActionCount} missing` : readiness.planCandidates.length ? "Complete" : "None selected", readiness.planCandidates.length > 0 && readiness.missingActionCount === 0],
    ["Decision rationales", readiness.missingRationaleCount ? `${readiness.missingRationaleCount} missing` : "Complete", readiness.planCandidates.length > 0 && readiness.missingRationaleCount === 0],
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
      checkbox.setAttribute("aria-label", `${inPlan ? "Remove" : "Add"} ${candidate.id} ${inPlan ? "from" : "to"} promotion plan`);
    }
    const assessment = candidate && getAssessment(candidate, getDecision(candidate));
    const token = row.querySelector(".tree-cost");
    if (assessment && token) token.textContent = formatCandidateTokenValue(candidate, assessment);
  });
  syncCandidateTreeAggregates();
}

function syncCandidateTreeAggregates() {
  elements["candidate-list"].querySelectorAll("details.candidate-source-root, details.candidate-category").forEach((disclosure) => {
    const candidates = [...disclosure.querySelectorAll("[data-candidate-key]")]
      .map((row) => state.candidates.find((candidate) => candidate.key === row.dataset.candidateKey))
      .filter(Boolean);
    const decoration = getCandidateAggregateDecoration(candidates);
    disclosure.classList.toggle("candidate-aggregate-ready", decoration?.status === "ready");
    disclosure.classList.toggle("candidate-aggregate-needs-input", decoration?.status === "needs-input");
    const summary = disclosure.querySelector(":scope > summary");
    if (decoration) {
      summary.dataset.selectionStatus = decoration.status;
      setWorkbenchTooltip(summary, decoration.description);
    } else {
      delete summary.dataset.selectionStatus;
      setWorkbenchTooltip(summary, "");
    }
    const decorationIcon = summary.querySelector(".candidate-parent-decoration-icon");
    const decorationDescription = summary.querySelector(".candidate-decoration-description");
    if (decorationIcon) {
      decorationIcon.toggleAttribute("hidden", !decoration);
      setWorkbenchTooltip(decorationIcon, decoration?.description || "");
    }
    if (decorationDescription) decorationDescription.textContent = decoration?.description || "";
  });
}

function selectCandidate(key, rationaleReturnView = null) {
  state.activeKey = key;
  state.rationaleReturnView = rationaleReturnView;
  syncCandidateTreeRows();
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
}

function updateFilter(value) {
  state.queries[state.workspaceTab] = value;
  if (state.workspaceTab === "candidate-sources") {
    renderBulkActions();
    navigateCandidateSearch();
  }
  else {
    state.assessmentActiveKey = null;
    renderAssessmentResults();
  }
  refreshPresentation();
}

function selectAssessmentResult(key) {
  state.assessmentActiveKey = key;
  syncAssessmentResultRows();
  renderAssessmentResultDetail();
  refreshPresentation();
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
}

function setWorkspaceTab(tab) {
  if (!['candidate-sources', 'assessment-results'].includes(tab)) return;
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
  elements["search-input"].value = state.queries[tab];
  elements["search-input"].placeholder = tab === "candidate-sources"
    ? "Search sources, categories, or rules"
    : "Search excluded assessment results";
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
  return {
    schemaVersion: SESSION_SCHEMA_VERSION,
    kind: "hosted-rule-workbench-draft",
    sessionId: state.session.id,
    exportedAt: new Date().toISOString(),
    snapshots: state.session.snapshots,
    approverName: state.session.approverName || "",
    decisions: state.session.decisions,
    applicabilityOverrides: state.session.applicabilityOverrides,
    bulkOperations: state.session.bulkOperations
  };
}

function buildApprovalPayload() {
  return {
    schemaVersion: APPROVAL_PAYLOAD_SCHEMA_VERSION,
    kind: "hosted-rule-promotion-selection",
    sessionId: state.session.id,
    snapshots: state.session.snapshots,
    inapplicableCandidateCount: state.excludedCandidateCount,
    bulkOperations: state.session.bulkOperations,
    decisions: state.candidates.map((candidate) => {
      const decision = getDecision(candidate);
      const assessment = getAssessment(candidate, decision);
      return {
        sourceType: candidate.sourceType,
        sourceId: candidate.sourceId,
        candidateId: candidate.assessment.assessmentId,
        sourcePath: candidate.sourcePath,
        sourceRationale: candidate.sourceRationale || null,
        provenance: candidate.provenance,
        sourceContentSha256: candidate.hash,
        catalogStatus: getCatalogStatus(candidate).key,
        hostedRuleId: candidate.assessment.targetHostedRuleId,
        action: decision.action,
        inPlan: decision.inPlan,
        planMembership: {
          source: decision.planMembershipSource,
          bulkOperationId: decision.bulkOperationId
        },
        rationale: decision.rationale.trim(),
        proposedText: decision.proposedText,
        recommendation: assessment.recommendation,
        hostedCategory: assessment.hostedCategory,
        applicabilityOverride: getApplicabilityOverride(candidate)
      };
    })
  };
}

function exportDraft() {
  const payload = JSON.stringify(buildDraftExport(), null, 2) + "\n";
  downloadJson(payload, `hosted-rule-draft-${new Date().toISOString().replace(/[:.]/g, "-")}.json`);
  showToast("Draft exported");
}

function handleApproverInput(event) {
  state.session.approverName = event.target.value.slice(0, 120);
  state.session.updatedAt = new Date().toISOString();
  persistSession();
  renderPreview();
  setSaveIndicator(`Saved ${formatTime(state.session.updatedAt)}`);
  refreshPresentation();
}

async function approveAndExport() {
  const readiness = getPreviewReadiness();
  if (!readiness.ready) {
    showToast("Complete the selected rule rationale and approver name before exporting.", true);
    return;
  }
  elements["approve-export-button"].disabled = true;
  try {
    const approvedAt = new Date().toISOString();
    const payload = buildApprovalPayload();
    const payloadBytes = JSON.stringify(payload, null, 2) + "\n";
    const approvedPayloadSha256 = await sha256Hex(payloadBytes);
    const handoff = {
      schemaVersion: 1,
      kind: "hosted-rule-workbench-approval-handoff",
      createdAt: approvedAt,
      encoding: "utf-8",
      hashAlgorithm: "sha256-payload-bytes-v1",
      approvedPayloadSha256,
      approval: {
        state: "approved",
        approvedAt,
        approvedBy: {
          type: "manual",
          id: readiness.approverName,
          displayName: readiness.approverName
        },
        method: "hosted-rule-workbench"
      },
      payload
    };
    const exportBytes = JSON.stringify(handoff, null, 2) + "\n";
    downloadJson(exportBytes, `hosted-rule-approval-${approvedAt.replace(/[:.]/g, "-")}.json`);
    showToast(`Approved handoff exported (${approvedPayloadSha256.slice(0, 12)}...)`);
  } catch {
    showToast("Approval handoff could not be exported.", true);
  } finally {
    renderPreview();
  }
}

async function sha256Hex(content) {
  const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(content));
  return Array.from(new Uint8Array(digest), (byte) => byte.toString(16).padStart(2, "0")).join("");
}

async function importDraft(event) {
  const file = event.target.files?.[0];
  event.target.value = "";
  if (!file) return;
  try {
    const draft = JSON.parse(await file.text());
    if (draft.kind !== "hosted-rule-workbench-draft" || draft.sessionId !== state.session.id) {
      throw new Error("The draft belongs to a different source snapshot.");
    }
    if (draft.schemaVersion !== SESSION_SCHEMA_VERSION) {
      throw new Error("The draft version is not supported.");
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
      if (!candidate || (!candidate.assessment.hostedApplicable && !overriddenCandidateKeys.has(key)) || decision.sourceHash !== candidate.hash || !getAllowedActions(candidate).includes(decision.action) || !isValidPlanMembership(decision, key, draft.bulkOperations) || typeof decision.rationale !== "string" || decision.rationale.length > DECISION_RATIONALE_MAX_LENGTH) {
        throw new Error(`The draft decision for ${key} is invalid.`);
      }
    }
    for (const operation of draft.bulkOperations) {
      if (operation.candidateKeys.some((key) => draft.decisions[key]?.planMembershipSource !== "bulk"
        || draft.decisions[key]?.bulkOperationId !== operation.id
        || draft.decisions[key]?.sourceHash !== operation.candidateSourceHashes[key])) {
        throw new Error(`The draft bulk operation ${operation.id} is inconsistent with its decisions.`);
      }
    }
    state.session.approverName = String(draft.approverName || "").slice(0, 120);
    autofillApproverName();
    state.session.decisions = draft.decisions || {};
    state.session.applicabilityOverrides = draft.applicabilityOverrides || {};
    state.session.bulkOperations = draft.bulkOperations;
    refreshEffectiveCandidates();
    state.session.updatedAt = new Date().toISOString();
    await persistSession();
    renderAll();
    showToast("Draft imported");
  } catch (error) {
    showToast(error.message, true);
  }
}

async function copyPreview() {
  try {
    await navigator.clipboard.writeText(elements["preview-json"].textContent);
    showToast("Draft payload copied");
  } catch {
    showToast("Clipboard access was unavailable", true);
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
  const snapshot = structuredClone(state.session);
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
