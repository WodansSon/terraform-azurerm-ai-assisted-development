"use strict";

const DATABASE_NAME = "hosted-rule-workbench";
const DATABASE_VERSION = 1;
const ACTIVE_SESSION_KEY = "hosted-rule-workbench.active-session";
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
  workspaceTab: "candidate-sources",
  currentView: "catalog",
  queries: {
    "candidate-sources": "",
    "assessment-results": ""
  },
  candidateSorts: {}
};

const elements = {};
let databasePromise;
let persistencePromise = Promise.resolve();
let toastTimer;

const mobileDeviceDetected = window.matchMedia("(max-width: 767px)").matches || navigator.userAgentData?.mobile === true || /Android|iPhone|iPad|iPod|Mobile/i.test(navigator.userAgent);
if (mobileDeviceDetected) document.documentElement.classList.add("mobile-unsupported");

document.addEventListener("DOMContentLoaded", async () => {
  if (mobileDeviceDetected) return;
  captureElements();
  bindEvents();
  await loadBundle();
  refreshIcons();
});

function captureElements() {
  for (const id of [
    "snapshot-chip", "close-button", "export-button", "import-input", "catalog-count", "assessment-results-count", "plan-count",
    "preview-status", "save-indicator", "metrics-band", "search-input", "plan-action-count",
    "filter-count", "candidate-list", "assessment-panel", "candidate-sources-panel", "assessment-results-panel",
    "assessment-results-filter-count", "assessment-results-list", "assessment-results-detail",
    "return-catalog-button", "plan-table-body", "empty-plan", "capacity-panel", "approval-badge",
    "preview-summary", "preview-diff", "preview-payload-diff", "preview-json", "copy-preview-button", "approver-name", "approve-export-button", "toast"
  ]) {
    elements[id] = document.getElementById(id);
  }
}

function bindEvents() {
  document.querySelectorAll("[data-view]").forEach((button) => {
    button.addEventListener("click", () => switchView(button.dataset.view));
  });
  elements["return-catalog-button"].addEventListener("click", () => switchView("catalog"));
  elements["close-button"].addEventListener("click", closeWorkbench);
  elements["export-button"].addEventListener("click", exportDraft);
  elements["import-input"].addEventListener("change", importDraft);
  elements["search-input"].addEventListener("input", (event) => updateFilter(event.target.value));
  document.querySelectorAll("[data-workspace-tab]").forEach((button) => {
    button.addEventListener("click", () => setWorkspaceTab(button.dataset.workspaceTab));
  });
  elements["candidate-list"].addEventListener("click", (event) => {
    const sortButton = event.target.closest("[data-candidate-sort]");
    if (sortButton) {
      updateCandidateSort(sortButton);
      return;
    }
    if (event.target.closest('input[type="checkbox"], summary')) return;
    const row = event.target.closest("[data-candidate-key]");
    if (row) selectCandidate(row.dataset.candidateKey);
  });
  elements["candidate-list"].addEventListener("change", handleTreeSelection);
  elements["candidate-list"].addEventListener("keydown", (event) => {
    handleRowKeyboardNavigation(event, elements["candidate-list"], "candidateKey", selectCandidate);
  });
  elements["assessment-results-list"].addEventListener("click", (event) => {
    const row = event.target.closest("[data-assessment-key]");
    if (row) selectAssessmentResult(row.dataset.assessmentKey);
  });
  elements["assessment-results-list"].addEventListener("keydown", (event) => {
    handleRowKeyboardNavigation(event, elements["assessment-results-list"], "assessmentKey", selectAssessmentResult);
  });
  elements["assessment-results-detail"].addEventListener("click", handleApplicabilityOverrideClick);
  elements["assessment-results-detail"].addEventListener("input", handleApplicabilityOverrideInput);
  elements["assessment-panel"].addEventListener("input", handleAssessmentInput);
  elements["plan-table-body"].addEventListener("click", (event) => {
    const undo = event.target.closest("[data-plan-undo]");
    if (undo) {
      const candidate = state.candidates.find((item) => item.key === undo.dataset.planUndo);
      if (candidate) undoDecision(candidate);
      return;
    }
    const link = event.target.closest("[data-plan-candidate]");
    if (!link) return;
    selectCandidate(link.dataset.planCandidate);
    switchView("catalog");
  });
  elements["copy-preview-button"].addEventListener("click", copyPreview);
  elements["approver-name"].addEventListener("input", handleApproverInput);
  elements["approve-export-button"].addEventListener("click", approveAndExport);
}

function handleRowKeyboardNavigation(event, container, keyProperty, selectRow) {
  if (event.target.matches('input[type="checkbox"]')) return;
  const keyAttribute = keyProperty.replace(/[A-Z]/g, (letter) => `-${letter.toLowerCase()}`);
  const row = event.target.closest(`[data-${keyAttribute}]`);
  if (!row) return;
  if (event.key === "Enter" || event.key === " ") {
    event.preventDefault();
    selectRow(row.dataset[keyProperty]);
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
    state.session = existing?.schemaVersion === 3 ? existing : createSession(sessionId, bundle);
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
    state.excludedCandidateCount = assessedCandidates.filter(({ assessment }) => !assessment.hostedApplicable).length;
    refreshEffectiveCandidates();
    localStorage.setItem(ACTIVE_SESSION_KEY, sessionId);
    await persistSession();
    state.activeKey = null;
    state.assessmentActiveKey = null;
    renderAll();
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
        <span class="brand-mark" aria-hidden="true">HR</span>
        <p class="eyebrow">Hosted Rule Workbench</p>
        <h1>Workbench closed</h1>
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
  const upstream = bundle.upstreamCandidates.map((candidate) => ({
    key: `upstream:${candidate.id}`,
    id: candidate.id,
    sourceType: "upstream",
    sourceLabel: "Contributor guidance",
    category: getUpstreamCategory(candidate),
    title: candidate.title,
    state: candidate.state,
    requiresReview: candidate.requiresReview,
    provenance: "published-upstream-standard",
    sourcePath: candidate.referenceUrl,
    hash: candidate.currentSha256,
    text: candidate.currentContent,
    baselineText: candidate.baselineContent,
    priorDecision: null,
    assessment: candidate.assessment || null,
    relatedHostedRules: candidate.relatedHostedRules
  }));
  const interactive = bundle.interactiveCandidates.map((candidate) => ({
    key: `interactive:${candidate.id}`,
    id: candidate.id,
    sourceType: "interactive",
    sourceLabel: "Interactive rule",
    category: formatContractCategory(candidate.contractPath),
    title: candidate.title,
    state: candidate.state,
    requiresReview: candidate.requiresReview,
    provenance: candidate.provenance,
    sourcePath: candidate.contractPath,
    hash: candidate.contentSha256,
    text: candidate.ruleText || "Retired source rule",
    baselineText: null,
    priorDecision: candidate.priorDecision,
    assessment: candidate.assessment || null,
    relatedHostedRules: candidate.relatedHostedRules || []
  }));
  const maintainer = bundle.maintainerCandidates.map((candidate) => ({
    key: `maintainer:${candidate.id}`,
    id: candidate.id,
    sourceType: "maintainer",
    sourceLabel: "Maintainer proposal",
    category: capitalize(candidate.surface),
    title: candidate.title,
    state: candidate.state,
    requiresReview: candidate.requiresReview,
    provenance: candidate.provenance,
    sourcePath: candidate.sourcePath,
    sourceRationale: candidate.rationale,
    surface: candidate.surface,
    hash: candidate.contentSha256,
    text: candidate.ruleText,
    baselineText: null,
    priorDecision: null,
    assessment: candidate.assessment || null,
    relatedHostedRules: candidate.relatedHostedRules || []
  }));
  return [...interactive, ...upstream, ...maintainer];
}

function getSessionId(bundle) {
  const snapshots = bundle.snapshots;
  return [snapshots.hostedCatalogSha256, snapshots.interactive.currentCatalogSha256, snapshots.upstream.currentCommit, snapshots.maintainer.sourceSha256].join(":");
}

function createSession(id, bundle) {
  return {
    schemaVersion: 3,
    id,
    createdAt: new Date().toISOString(),
    updatedAt: new Date().toISOString(),
    snapshots: bundle.snapshots,
    approverName: "",
    decisions: {},
    applicabilityOverrides: {}
  };
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

function defaultDecision(candidate) {
  const assessment = candidate.assessment || getPriorAssessment(candidate);
  return {
    sourceHash: candidate.hash,
    action: "no-change",
    inPlan: false,
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
  if (!allowedActions.includes(saved.action) || typeof saved.inPlan !== "boolean") return defaultDecision(candidate);
  return {
    ...saved,
    proposedText,
    inPlan: saved.inPlan && isPromotionAction(saved.action),
    rationale: String(saved.rationale || "").slice(0, DECISION_RATIONALE_MAX_LENGTH),
    assessment: candidate.assessment || getPriorAssessment(candidate),
  };
}

function getCatalogStatus(candidate) {
  const activeRules = candidate.relatedHostedRules.filter((rule) => rule.status === "active");
  const retiredRules = candidate.relatedHostedRules.filter((rule) => rule.status === "retired");
  if (activeRules.length) return { key: "mapped", label: "Mapped", rules: activeRules };
  if (retiredRules.length) return { key: "retired", label: "Retired Mapping", rules: retiredRules };
  return { key: "unmapped", label: "Not Mapped", rules: [] };
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
  return getCatalogStatus(candidate).rules.map((rule) => rule.text).join("\n\n");
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
  state.session.decisions[candidate.key] = {
    ...maintainerDecision,
    ...changes,
    sourceHash: candidate.hash,
    updatedAt: new Date().toISOString()
  };
  state.session.updatedAt = new Date().toISOString();
  persistSession();
  syncCandidateTreeRows();
  renderDecisionOutputs();
}

function renderDecisionOutputs() {
  renderMetrics();
  renderPlan();
  renderCapacity();
  renderPreview();
  renderCounts();
  setSaveIndicator(`Saved ${formatTime(state.session.updatedAt)}`);
  refreshIcons();
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

function renderAll(shouldRenderAssessment = true) {
  if (!state.bundle || !state.session) return;
  renderSnapshot();
  renderMetrics();
  renderCandidateList();
  if (shouldRenderAssessment) renderAssessment();
  renderAssessmentResults();
  renderPlan();
  renderCapacity();
  renderPreview();
  renderCounts();
  setSaveIndicator(`Saved ${formatTime(state.session.updatedAt)}`);
  refreshIcons();
}

function renderSnapshot() {
  const upstream = state.bundle.snapshots.upstream;
  elements["snapshot-chip"].textContent = `${upstream.currentRef}@${upstream.currentCommit.slice(0, 8)}`;
  elements["snapshot-chip"].title = `${upstream.repository} ${upstream.currentCommit}`;
}

function renderMetrics() {
  const planCount = getPlanCandidates().length;
  const combined = getCapacityReports().find((report) => report.name === "test-combined");
  const metrics = [
    ["Hosted-capable inventory", state.candidates.length, `${state.excludedCandidateCount} inapplicable excluded`],
    ["Mapped", state.candidates.filter((candidate) => getCatalogStatus(candidate).key === "mapped").length, "Active Hosted mappings"],
    ["Not mapped", state.candidates.filter((candidate) => getCatalogStatus(candidate).key === "unmapped").length, "No Hosted mapping"],
    ["In plan", planCount, "Add, update, or retire"],
    ["Test headroom", formatNumber(combined.budgetHeadroomTokens), `${combined.utilizationPercent}% utilized`]
  ];
  elements["metrics-band"].innerHTML = metrics.map(([label, value, note]) => `
    <div class="metric">
      <span class="metric-label">${escapeHtml(label)}</span>
      <div class="metric-value">${escapeHtml(value)} <span class="metric-note">${escapeHtml(note)}</span></div>
    </div>
  `).join("");
}

function getFilteredCandidates() {
  const query = state.queries["candidate-sources"].trim().toLowerCase();
  return state.candidates.filter((candidate) => {
    if (!query) return true;
    return [candidate.id, candidate.title, candidate.sourcePath, candidate.text, candidate.category, candidate.sourceLabel]
      .some((value) => String(value || "").toLowerCase().includes(query));
  });
}

function renderCandidateList() {
  const filtered = getFilteredCandidates();
  elements["filter-count"].textContent = `${formatNumber(filtered.length)} evaluated`;
  if (!filtered.length) {
    const message = state.candidates.length ? "No candidates match this search." : "No AI-evaluated candidates are present in this bundle.";
    elements["candidate-list"].innerHTML = `<div class="empty-state compact"><h3>No candidates available</h3><p>${escapeHtml(message)}</p></div>`;
    return;
  }
  const sources = [
    ["interactive", "Interactive Toolkit"],
    ["upstream", "Contributor Guidance"],
    ["maintainer", "Maintainer Proposals"]
  ];
  elements["candidate-list"].innerHTML = `
    <div class="eligibility-note"><strong>${formatNumber(state.excludedCandidateCount)} inapplicable items excluded</strong><span>Workflow-only and non-review guidance is screened out before maintainer review.</span></div>
  ` + sources.map(([sourceType, label]) => {
    const candidates = filtered.filter((candidate) => candidate.sourceType === sourceType);
    if (!candidates.length) return "";
    const children = sourceType === "upstream"
      ? renderCandidateItems(`${sourceType}:all`, candidates, "contributor-candidates")
      : Object.entries(groupCandidatesByCategory(candidates)).sort(([left], [right]) => left.localeCompare(right)).map(([category, members]) => renderCandidateCategory(sourceType, category, members)).join("");
    return `
      <details class="candidate-source-root" ${state.queries["candidate-sources"] ? "open" : ""}>
        <summary><i data-lucide="folder" aria-hidden="true"></i><strong>${label}</strong><span>${candidates.length}</span></summary>
        ${children}
      </details>
    `;
  }).join("");
}

function renderCandidateCategory(sourceType, category, candidates) {
  const open = Boolean(state.queries["candidate-sources"]);
  const sectionKey = `${sourceType}:${category}`;
  return `
    <details class="candidate-category" data-source-type="${escapeHtml(sourceType)}" data-category="${escapeHtml(category)}" ${open ? "open" : ""}>
      <summary>
        <i data-lucide="folder" aria-hidden="true"></i>
        <strong>${escapeHtml(category)}</strong>
        <span>${candidates.length}</span>
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
    ["candidate", "Candidate", "Candidate"],
    ["state", "State", "Source State"],
    ["catalog", "Status", "Catalog Status"],
    ["impact", "Impact", "Impact"],
    ["cost", "Tokens", "Token Cost"],
    ["recommendation", "Recommended", "Recommendation"]
  ];
  const button = ([key, label, accessibleLabel]) => {
    const active = sort.field === key;
    const nextDirection = active && sort.direction === "ascending" ? "descending" : "ascending";
    return `<button class="candidate-sort-button ${active ? "active" : ""}" type="button" data-candidate-sort="${key}" data-candidate-section="${escapeHtml(sectionKey)}" aria-label="Sort by ${accessibleLabel}, ${nextDirection}" ${active ? 'aria-pressed="true"' : ""}><span>${label}</span>${active ? `<i data-lucide="chevron-${sort.direction === "ascending" ? "up" : "down"}" aria-hidden="true"></i>` : ""}</button>`;
  };
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
  refreshIcons();
}

function sortCandidates(candidates, sort) {
  const collator = new Intl.Collator(undefined, { numeric: true, sensitivity: "base" });
  const value = (candidate) => {
    const assessment = getAssessment(candidate, getDecision(candidate));
    if (sort.field === "candidate") return `${candidate.id} ${candidate.title}`;
    if (sort.field === "state") return candidate.state;
    if (sort.field === "catalog") return getCatalogStatus(candidate).label;
    if (sort.field === "impact") return calculateImpact(assessment.factors);
    if (sort.field === "cost") return assessment.guardedTokenDelta;
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
  return state.assessedCandidates.filter((candidate) => {
    if (candidate.assessment.hostedApplicable) return false;
    if (!query) return true;
    return [candidate.id, candidate.title, candidate.sourcePath, candidate.text, candidate.category, candidate.sourceLabel, candidate.assessment.applicabilityRationale]
      .some((value) => String(value || "").toLowerCase().includes(query));
  });
}

function renderAssessmentResults() {
  if (!state.assessedCandidates.length) return;
  const filtered = getFilteredAssessmentCandidates();
  elements["assessment-results-filter-count"].textContent = `${formatNumber(filtered.length)} excluded`;
  if (!filtered.length) {
    elements["assessment-results-list"].innerHTML = `<div class="empty-state compact"><h3>No assessment results</h3><p>No candidates match this outcome and search.</p></div>`;
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
      return `
        <details class="candidate-source-root" ${state.queries["assessment-results"] ? "open" : ""}>
          <summary><i data-lucide="folder" aria-hidden="true"></i><strong>${label}</strong><span>${candidates.length}</span></summary>
          <div class="candidate-category-items"><div class="assessment-results-header"><strong>Candidate</strong><span><strong>Outcome</strong><strong>Category</strong><strong>Recommendation</strong></span></div>${candidates.map(renderAssessmentResultRow).join("")}</div>
        </details>
      `;
    }).join("");
  }
  renderAssessmentResultDetail();
}

function renderAssessmentResultRow(candidate) {
  const assessment = candidate.assessment;
  const eligible = assessment.hostedApplicable;
  return `
    <div class="assessment-result-row ${candidate.key === state.assessmentActiveKey ? "active" : ""}" role="button" tabindex="0" data-assessment-key="${escapeHtml(candidate.key)}" ${candidate.key === state.assessmentActiveKey ? 'aria-current="true"' : ""}>
      <span class="candidate-tree-copy"><strong>${escapeHtml(candidate.id)}</strong><small>${escapeHtml(candidate.title)}</small></span>
      <span class="assessment-result-summary"><span class="status-badge ${eligible ? "success" : "warning"}">${eligible ? "Eligible" : "Excluded"}</span><span>${escapeHtml(formatHostedCategory(assessment.hostedCategory))}</span><span class="recommendation-badge ${escapeHtml(assessment.recommendation)}">${escapeHtml(formatRecommendation(assessment.recommendation))}</span></span>
    </div>
  `;
}

function renderAssessmentResultDetail() {
  const candidate = state.assessedCandidates.find((item) => item.key === state.assessmentActiveKey);
  if (!candidate) {
    elements["assessment-results-detail"].innerHTML = `<div class="empty-state"><i data-lucide="clipboard-check" aria-hidden="true"></i><h2>Select an assessment result</h2><p>The source rule, applicability decision, AI rationale, and Hosted coverage will appear here.</p></div>`;
    return;
  }
  const assessment = candidate.assessment;
  const eligible = assessment.hostedApplicable;
  const catalogStatus = getCatalogStatus(candidate);
  const mappedRules = catalogStatus.rules.length
    ? catalogStatus.rules.map((rule) => `<div class="overlap-item subcontext-container"><div><strong>${escapeHtml(rule.id)}</strong><span class="catalog-status ${escapeHtml(rule.status)}">${escapeHtml(capitalize(rule.status))}</span></div><p>${escapeHtml(rule.text)}</p></div>`).join("")
    : `<div class="overlap-item subcontext-container empty-mapping">No Hosted rule is mapped to this source candidate.</div>`;
  elements["assessment-results-detail"].innerHTML = `
    <div class="assessment-content">
      <div class="assessment-title">
        <div>
          <div class="source-line"><span>${escapeHtml(candidate.sourceLabel)}</span><span>/</span><span>${escapeHtml(candidate.id)}</span></div>
          <h2>${escapeHtml(candidate.title)}</h2>
          <div class="source-line"><span>${escapeHtml(candidate.sourcePath)}</span><span>${escapeHtml(candidate.hash.slice(0, 12))}</span></div>
        </div>
        <span class="status-badge ${eligible ? "success" : "warning"}">${eligible ? "Eligible" : "Excluded"}</span>
      </div>
      <div class="section-block"><span class="section-label">Source Rule:</span><pre class="evidence-box">${escapeHtml(candidate.text)}</pre>${candidate.sourceRationale ? `<div class="assessment-rationale proposal-rationale"><strong>Proposal rationale</strong><p>${escapeHtml(candidate.sourceRationale)}</p></div>` : ""}</div>
      <div class="section-block"><span class="section-label">Applicability Decision:</span><div class="ai-evaluation-summary subcontext-container"><div class="ai-evaluation-heading"><strong>${eligible ? "Eligible for candidate catalog" : "Excluded from candidate catalog"}</strong><span class="recommendation-badge ${escapeHtml(assessment.recommendation)}">Recommend ${escapeHtml(formatRecommendation(assessment.recommendation))}</span></div><p>${escapeHtml(assessment.applicabilityRationale)}</p></div></div>
      <div class="section-block"><span class="section-label">AI Evaluation:</span><h3>${escapeHtml(assessment.summary)}</h3><p class="coverage-summary">${escapeHtml(assessment.impactDescription)}</p>${renderPriorityAssessment(assessment)}</div>
      <div class="section-block"><span class="section-label">Hosted Catalog Status:</span><div class="catalog-status-heading"><strong>${catalogStatus.rules.length ? `${catalogStatus.rules.length} mapped rule${catalogStatus.rules.length === 1 ? "" : "s"}` : "No authoritative mapping"}</strong><span class="catalog-status ${catalogStatus.key}">${escapeHtml(catalogStatus.label)}</span></div><div class="overlap-list">${mappedRules}</div></div>
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
          <div class="override-record-heading"><strong>Provisional Override</strong><span class="status-badge warning">Reincluded</span></div>
          <p>${escapeHtml(override.rationale)}</p>
          <small>Recorded by @${escapeHtml(override.recordedBy.login)} on ${escapeHtml(formatTimestamp(override.recordedAt))}. The original AI exclusion remains in this audit.</small>
          <button class="button secondary" type="button" data-override-remove>Remove Override</button>
        </div>
        <div class="read-only-boundary"><i data-lucide="lock" aria-hidden="true"></i><span>The AI assessment is read-only. This provisional maintainer correction does not erase the original result.</span></div>
      </div>
    `;
  }
  const canOverride = identity?.status === "validated" && identity.isCodeOwner === true && Boolean(identity.login);
  const reason = canOverride ? "" : identity?.reason || "GitHub CLI authentication and Hosted CODEOWNER membership are required.";
  return `
    <div class="section-block maintainer-override" data-override-key="${escapeHtml(candidate.key)}">
      <span class="section-label">Maintainer Override:</span>
      <div class="override-summary subcontext-container">
        <div><strong>Disagree with this exclusion?</strong><p>Contest the AI applicability decision and record a separate provisional maintainer correction.</p>${reason ? `<small>${escapeHtml(reason)}</small>` : ""}</div>
        <button class="button secondary" type="button" data-override-open ${canOverride ? "" : "disabled"}><i data-lucide="message-square-warning" aria-hidden="true"></i>Contest Assessment</button>
      </div>
      <div class="override-form subcontext-container" hidden>
        <span class="control-subtitle">Corrected Outcome:</span>
        <label class="override-outcome"><input type="radio" name="corrected-outcome" value="eligible" checked><span>Eligible for Candidate Sources</span></label>
        <label class="override-rationale"><span class="control-subtitle">Override Rationale:</span><textarea maxlength="${OVERRIDE_RATIONALE_MAX_LENGTH}" aria-describedby="override-rationale-limit" placeholder="Briefly explain why the AI exclusion is incorrect."></textarea><small id="override-rationale-limit" class="rationale-limit">0 / ${OVERRIDE_RATIONALE_MAX_LENGTH} characters</small></label>
        <p class="override-audit-note">The original AI result remains in the assessment audit. This provisional override records the corrected outcome, rationale, authenticated maintainer, and timestamp.</p>
        <div class="override-actions"><button class="button secondary" type="button" data-override-cancel>Cancel</button><button class="button primary" type="button" data-override-apply disabled>Apply Override</button></div>
      </div>
      <div class="read-only-boundary"><i data-lucide="lock" aria-hidden="true"></i><span>The AI assessment is read-only. A maintainer override records a separate correction without erasing the original result.</span></div>
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
    delete state.session.applicabilityOverrides[candidate.key];
    state.session.updatedAt = new Date().toISOString();
    refreshEffectiveCandidates();
    await persistSession();
    renderAll(false);
    showToast("Provisional override removed");
    return;
  }
  if (!event.target.closest("[data-override-apply]")) return;
  const identity = globalThis.__HOSTED_RULE_WORKBENCH__?.maintainerIdentity;
  const rationale = section.querySelector("textarea").value.trim();
  if (identity?.status !== "validated" || identity.isCodeOwner !== true || !identity.login) {
    showToast(identity?.reason || "A validated Hosted CODEOWNER identity is required.", true);
    return;
  }
  if (!rationale) return;
  state.session.applicabilityOverrides[candidate.key] = {
    state: "provisional",
    sourceContentSha256: candidate.hash,
    originalHostedApplicable: false,
    effectiveHostedApplicable: true,
    rationale: rationale.slice(0, OVERRIDE_RATIONALE_MAX_LENGTH),
    recordedAt: new Date().toISOString(),
    recordedBy: { type: "github-cli", login: identity.login }
  };
  state.session.updatedAt = new Date().toISOString();
  refreshEffectiveCandidates();
  await persistSession();
  state.activeKey = candidate.key;
  renderAll(false);
  setWorkspaceTab("candidate-sources");
  selectCandidate(candidate.key);
  showToast("Candidate provisionally reincluded");
}

function renderCandidateTreeRow(candidate) {
  const decision = getDecision(candidate);
  const assessment = getAssessment(candidate, decision);
  const impact = calculateImpact(assessment.factors);
  const catalogStatus = getCatalogStatus(candidate);
  const inPlan = decision.inPlan;
  return `
    <div class="candidate-tree-row ${candidate.key === state.activeKey ? "active" : ""} ${inPlan ? "in-plan" : ""}" role="button" tabindex="0" data-candidate-key="${escapeHtml(candidate.key)}" ${candidate.key === state.activeKey ? 'aria-current="true"' : ""}>
      <input type="checkbox" data-decision-key="${escapeHtml(candidate.key)}" aria-label="Include ${escapeHtml(candidate.id)} action in promotion plan" title="${inPlan ? "Remove action from" : "Add action to"} promotion plan" ${inPlan ? "checked" : ""}>
      <span class="candidate-tree-copy"><strong>${escapeHtml(candidate.id)}</strong><small>${escapeHtml(candidate.title)}</small></span>
      <span class="candidate-tree-summary"><span class="candidate-lifecycle ${escapeHtml(candidate.state)}">${escapeHtml(capitalize(candidate.state))}</span><span class="catalog-status ${catalogStatus.key}">${escapeHtml(catalogStatus.label)}</span><span class="tree-impact">${impact}</span><span class="tree-cost">${formatSignedNumber(assessment.guardedTokenDelta)}</span><span class="recommendation-badge ${escapeHtml(assessment.recommendation)}">${escapeHtml(formatRecommendation(assessment.recommendation))}</span></span>
    </div>
  `;
}

function renderAssessment() {
  const candidate = getActiveCandidate();
  if (!candidate) return;
  const decision = getDecision(candidate);
  const assessment = getAssessment(candidate, decision);
  if (!assessment) {
    elements["assessment-panel"].innerHTML = `<div class="empty-state"><h2>AI assessment unavailable</h2><p>This candidate is not ready for maintainer review and should not appear in the evaluated candidate tree.</p></div>`;
    return;
  }
  const impact = assessment ? calculateImpact(assessment.factors) : null;
  const draftCost = assessment.guardedTokenDelta;
  const combined = getCapacityReports().find((report) => report.name === "test-combined");
  const projectedHeadroom = combined.budgetHeadroomTokens - draftCost;
  const catalogStatus = getCatalogStatus(candidate);
  const mappedRules = catalogStatus.rules.length
    ? catalogStatus.rules.map((rule) => {
      const placements = rule.placements?.length
        ? rule.placements.map((placement) => `${placement.surfaceId} / ${placement.sectionHeading}`).join("; ")
        : "Placement unavailable in source bundle";
      return `<div class="overlap-item subcontext-container"><div><strong>${escapeHtml(rule.id)}</strong><span class="catalog-status ${escapeHtml(rule.status)}">${escapeHtml(capitalize(rule.status))}</span></div><p>${escapeHtml(rule.text)}</p><small>${escapeHtml(placements)}</small></div>`;
    }).join("")
    : `<div class="overlap-item subcontext-container empty-mapping">No Hosted rule is mapped to this source candidate.</div>`;
  const allowedActions = getAllowedActions(candidate, decision.proposedText);
  const unchangedMappedRule = catalogStatus.key === "mapped" && !hasHostedTextChange(candidate, decision.proposedText);

  elements["assessment-panel"].innerHTML = `
    <div class="assessment-content">
      <div class="assessment-title">
        <div>
          <div class="source-line">
            <span>${escapeHtml(candidate.sourceLabel)}</span>
            <span>/</span>
            <span>${escapeHtml(candidate.id)}</span>
            <span class="candidate-state ${escapeHtml(candidate.state)}">${escapeHtml(capitalize(candidate.state))}</span>
          </div>
          <h2>${escapeHtml(candidate.title)}</h2>
          <div class="source-line"><span>${escapeHtml(candidate.sourcePath)}</span><span>${escapeHtml(candidate.hash.slice(0, 12))}</span></div>
        </div>
        <span class="decision-badge ${escapeHtml(decision.action)}">${escapeHtml(formatRecommendation(decision.action))}</span>
      </div>

      <div class="section-block">
        <span class="section-label">Source Rule:</span>
        <pre class="evidence-box">${escapeHtml(candidate.text)}</pre>
        ${candidate.sourceRationale ? `<div class="assessment-rationale proposal-rationale"><strong>Proposal rationale</strong><p>${escapeHtml(candidate.sourceRationale)}</p></div>` : ""}
      </div>

      <div class="section-block">
        <span class="section-label">Hosted Catalog Status:</span>
        <div class="catalog-status-heading"><strong>${catalogStatus.rules.length ? `${catalogStatus.rules.length} mapped rule${catalogStatus.rules.length === 1 ? "" : "s"}` : "No authoritative mapping"}</strong><span class="catalog-status ${catalogStatus.key}">${escapeHtml(catalogStatus.label)}</span></div>
        <div class="overlap-list">${mappedRules}</div>
      </div>

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
          <div class="score-item cost"><span>Token cost</span><strong>${formatSignedNumber(draftCost)}</strong></div>
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
        <pre class="evidence-box proposed-rule">${escapeHtml(assessment.proposedText || "No Hosted rule change proposed.")}</pre>
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
                <label class="action-option ${decision.action === action ? "selected" : ""}">
                  <input type="radio" name="rule-action" data-rule-action="${escapeHtml(action)}" value="${escapeHtml(action)}" ${decision.action === action ? "checked" : ""}>
                  <span>${escapeHtml(formatRecommendation(action))}</span>
                </label>
              `).join("")}
            </fieldset>
            <label class="plan-toggle ${isPromotionAction(decision.action) ? "" : "disabled"}">
              <input type="checkbox" data-plan-toggle ${decision.inPlan ? "checked" : ""} ${isPromotionAction(decision.action) ? "" : "disabled"}>
              <span>Include this ${escapeHtml(formatRecommendation(decision.action).toLowerCase())} action in the promotion plan</span>
            </label>
          </div>
          <div class="field-stack control-group rationale-control-group">
            <label><span class="control-subtitle">Decision Rationale:</span><textarea data-decision-field="rationale" maxlength="${DECISION_RATIONALE_MAX_LENGTH}" aria-describedby="decision-rationale-limit" placeholder="Record why this action is appropriate.">${escapeHtml(decision.rationale)}</textarea><small class="rationale-limit" id="decision-rationale-limit">${decision.rationale.length} / ${DECISION_RATIONALE_MAX_LENGTH} characters</small></label>
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
  if (!getDecision(candidate).inPlan) return;
  updateDecision(candidate, { inPlan: false });
  showToast("Action removed from plan.", false, {
    label: "Restore",
    handler: () => {
      updateDecision(candidate, { inPlan: true });
      showToast("Action restored to plan");
    }
  });
}

function handleAssessmentInput(event) {
  const candidate = getActiveCandidate();
  if (!candidate) return;
  if (event.target.dataset.ruleAction) {
    const action = event.target.dataset.ruleAction;
    updateDecision(candidate, { action, inPlan: isPromotionAction(action) });
    renderAssessment();
    return;
  }
  if (event.target.hasAttribute("data-plan-toggle")) {
    updateDecision(candidate, { inPlan: event.target.checked });
    renderAssessment();
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
    }
    if (event.target.dataset.decisionField === "proposedText") refreshAssessmentScores(candidate);
  }
}

function refreshAssessmentScores(candidate) {
  const decision = getDecision(candidate);
  const assessment = getAssessment(candidate, decision);
  const impact = calculateImpact(assessment.factors);
  const cost = assessment.guardedTokenDelta;
  const efficiency = cost > 0 ? ((impact * 100) / cost).toFixed(1) : "n/a";
  const scoreValues = elements["assessment-panel"].querySelectorAll(".score-item strong");
  if (scoreValues.length === 3) {
    scoreValues[0].textContent = impact;
    scoreValues[1].textContent = cost;
    scoreValues[2].textContent = efficiency;
  }
}

function renderPlan() {
  const planCandidates = getPlanCandidates();
  elements["empty-plan"].hidden = planCandidates.length > 0;
  elements["plan-table-body"].innerHTML = planCandidates.map((candidate) => {
    const decision = getDecision(candidate);
    const assessment = getAssessment(candidate, decision);
    const impact = assessment ? calculateImpact(assessment.factors) : null;
    const cost = assessment?.guardedTokenDelta || 0;
    const ready = assessment && decision.rationale.trim();
    const readiness = ready ? "Ready" : assessment ? "Needs detail" : "Needs AI assessment";
    return `
      <tr>
        <td><button class="candidate-link" type="button" data-plan-candidate="${escapeHtml(candidate.key)}">${escapeHtml(candidate.id)}</button><br>${escapeHtml(candidate.title)}</td>
        <td><span class="recommendation-badge ${escapeHtml(decision.action)}">${escapeHtml(formatRecommendation(decision.action))}</span><br>${escapeHtml(candidate.sourceLabel)}</td>
        <td class="mono">${impact}</td>
        <td class="mono">${cost}</td>
        <td><span class="status-badge ${ready ? "success" : "warning"}">${readiness}</span></td>
        <td class="plan-actions"><button class="plan-undo" type="button" data-plan-undo="${escapeHtml(candidate.key)}" aria-label="Undo decision and remove from promotion plan" title="Undo decision and remove from promotion plan">Undo</button></td>
      </tr>
    `;
  }).join("");
}

function renderCapacity() {
  const reports = getCapacityReports().filter((report) => report.kind === "combined");
  const draftCost = getPlanCandidates().reduce((sum, candidate) => sum + getAssessment(candidate, getDecision(candidate)).guardedTokenDelta, 0);
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
    const assessment = getAssessment(candidate, getDecision(candidate));
    return assessment.affectedSurfaces.some((surface) => reportSurfaces.has(surface)) ? sum + assessment.guardedTokenDelta : sum;
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
  elements["approve-export-button"].disabled = !ready;
  elements["preview-diff"].innerHTML = renderPreviewChanges(planCandidates);
  elements["preview-payload-diff"].innerHTML = renderPayloadChanges();
  elements["preview-json"].textContent = JSON.stringify(buildApprovalPayload(), null, 2);
}

function renderPreviewChanges(candidates) {
  if (!candidates.length) {
    return `<div class="empty-state compact"><i data-lucide="git-pull-request-draft" aria-hidden="true"></i><h3>No proposed changes</h3><p>Add an available rule action to the promotion plan to review its line-level diff.</p></div>`;
  }
  return candidates.map((candidate) => {
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
  const mappedRuleIds = getCatalogStatus(candidate).rules.map((rule) => rule.id).join(", ") || "New Hosted rule";
  return `
    <section class="preview-change" aria-label="${escapeHtml(candidate.id)} proposed ${escapeHtml(action)}">
      <div class="preview-change-heading"><div><strong>${escapeHtml(candidate.id)}</strong><span>${escapeHtml(candidate.title)}</span></div><span class="recommendation-badge ${escapeHtml(action)}">${escapeHtml(formatRecommendation(action))}</span></div>
      <div class="diff-file-heading"><span>${escapeHtml(mappedRuleIds)}</span><span class="diff-stats"><span>+${additions}</span><span>-${deletions}</span></span></div>
      <div class="diff-lines">${renderedLines}</div>
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
      rationale: baseline.rationale,
      proposedText: baseline.proposedText,
      applicabilityOverride: null
    };
    const after = {
      action: current.action,
      inPlan: current.inPlan,
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
  if (!changes.length) return `<div class="payload-empty">No selection payload changes.</div>`;
  return changes.map(({ candidate, before, after }) => {
    const beforeLines = JSON.stringify(before, null, 2).split("\n");
    const afterLines = JSON.stringify(after, null, 2).split("\n");
    return `
      <section class="payload-change" aria-label="${escapeHtml(candidate.id)} selection payload changes">
        <div class="payload-change-heading"><strong>${escapeHtml(candidate.id)}</strong><span>${escapeHtml(candidate.title)}</span></div>
        <div class="payload-columns">
          ${renderPayloadColumn("Default", beforeLines, "delete")}
          ${renderPayloadColumn("Current", afterLines, "add")}
        </div>
      </section>
    `;
  }).join("");
}

function renderPayloadColumn(label, lines, type) {
  return `
    <div class="payload-column ${type}">
      <div class="payload-column-heading">${label}</div>
      <div class="payload-code">${lines.map((line, index) => `<div class="payload-line"><span>${index + 1}</span><code>${escapeHtml(line)}</code></div>`).join("")}</div>
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
  const missingRationale = planCandidates.some((candidate) => {
    const decision = getDecision(candidate);
    return !getAssessment(candidate, decision) || !decision.rationale.trim();
  });
  const approverName = String(state.session.approverName || "").trim();
  let status = "ready";
  if (planCandidates.length === 0) status = "no actions";
  else if (missingRationale) status = "needs rationale";
  else if (!approverName) status = "needs approver";
  return {
    planCandidates,
    approverName,
    status,
    ready: planCandidates.length > 0 && !missingRationale && Boolean(approverName)
  };
}

function renderCounts() {
  elements["catalog-count"].textContent = formatNumber(state.candidates.length);
  elements["assessment-results-count"].textContent = formatNumber(state.excludedCandidateCount);
  elements["plan-count"].textContent = formatNumber(getPlanCandidates().length);
  elements["plan-action-count"].textContent = `${formatNumber(getPlanCandidates().length)} actions`;
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
    const checkbox = row.querySelector("[data-decision-key]");
    if (checkbox) {
      checkbox.checked = inPlan;
      checkbox.title = `${inPlan ? "Remove action from" : "Add action to"} promotion plan`;
    }
  });
}

function selectCandidate(key) {
  state.activeKey = key;
  syncCandidateTreeRows();
  renderAssessment();
  refreshIcons();
}

function updateFilter(value) {
  state.queries[state.workspaceTab] = value;
  if (state.workspaceTab === "candidate-sources") {
    renderCandidateList();
  }
  else {
    state.assessmentActiveKey = null;
    renderAssessmentResults();
  }
  refreshIcons();
}

function selectAssessmentResult(key) {
  state.assessmentActiveKey = key;
  elements["assessment-results-list"].querySelectorAll("[data-assessment-key]").forEach((row) => {
    const active = row.dataset.assessmentKey === key;
    row.classList.toggle("active", active);
    if (active) row.setAttribute("aria-current", "true");
    else row.removeAttribute("aria-current");
  });
  renderAssessmentResultDetail();
  refreshIcons();
}

function setWorkspaceTab(tab) {
  if (!['candidate-sources', 'assessment-results'].includes(tab)) return;
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
  refreshIcons();
}

function handleTreeSelection(event) {
  const candidateCheckbox = event.target.closest("[data-decision-key]");
  if (!candidateCheckbox) return;
  const candidate = state.candidates.find((item) => item.key === candidateCheckbox.dataset.decisionKey);
  if (!candidate) return;
  const decision = getDecision(candidate);
  const action = candidateCheckbox.checked && !isPromotionAction(decision.action)
    ? getDefaultPlanAction(candidate, getAssessment(candidate, decision)?.recommendation)
    : decision.action;
  updateDecision(candidate, { action, inPlan: candidateCheckbox.checked && isPromotionAction(action) });
  if (candidate.key === state.activeKey) renderAssessment();
}

function switchView(view) {
  state.currentView = view;
  document.querySelectorAll("[data-view]").forEach((button) => button.classList.toggle("active", button.dataset.view === view));
  document.querySelectorAll("[data-view-panel]").forEach((panel) => panel.classList.toggle("active", panel.dataset.viewPanel === view));
  if (view === "plan") {
    renderPlan();
    renderCapacity();
  }
  if (view === "preview") renderPreview();
  refreshIcons();
}

function buildDraftExport() {
  return {
    schemaVersion: 3,
    kind: "hosted-rule-workbench-draft",
    sessionId: state.session.id,
    exportedAt: new Date().toISOString(),
    snapshots: state.session.snapshots,
    approverName: state.session.approverName || "",
    decisions: state.session.decisions,
    applicabilityOverrides: state.session.applicabilityOverrides
  };
}

function buildApprovalPayload() {
  return {
    schemaVersion: 2,
    kind: "hosted-rule-promotion-selection",
    sessionId: state.session.id,
    snapshots: state.session.snapshots,
    inapplicableCandidateCount: state.excludedCandidateCount,
    decisions: state.candidates.map((candidate) => {
      const decision = getDecision(candidate);
      const assessment = getAssessment(candidate, decision);
      return {
        sourceType: candidate.sourceType,
        id: candidate.id,
        sourcePath: candidate.sourcePath,
        sourceRationale: candidate.sourceRationale || null,
        provenance: candidate.provenance,
        sourceContentSha256: candidate.hash,
        catalogStatus: getCatalogStatus(candidate).key,
        mappedHostedRuleIds: getCatalogStatus(candidate).rules.map((rule) => rule.id),
        action: decision.action,
        inPlan: decision.inPlan,
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
  refreshIcons();
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
    if (draft.schemaVersion !== 3) {
      throw new Error("The draft version is not supported.");
    }
    if (!draft.decisions || typeof draft.decisions !== "object" || Array.isArray(draft.decisions)) {
      throw new Error("The draft decisions are invalid.");
    }
    if (!draft.applicabilityOverrides || typeof draft.applicabilityOverrides !== "object" || Array.isArray(draft.applicabilityOverrides)) {
      throw new Error("The draft applicability overrides are invalid.");
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
      if (!candidate || (!candidate.assessment.hostedApplicable && !overriddenCandidateKeys.has(key)) || decision.sourceHash !== candidate.hash || !getAllowedActions(candidate).includes(decision.action) || typeof decision.inPlan !== "boolean" || typeof decision.rationale !== "string" || decision.rationale.length > DECISION_RATIONALE_MAX_LENGTH) {
        throw new Error(`The draft decision for ${key} is invalid.`);
      }
    }
    state.session.approverName = String(draft.approverName || "").slice(0, 120);
    state.session.decisions = draft.decisions || {};
    state.session.applicabilityOverrides = draft.applicabilityOverrides || {};
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
  elements["metrics-band"].innerHTML = "";
  elements["candidate-list"].innerHTML = "";
  elements["assessment-panel"].innerHTML = `<div class="empty-state"><h2>Workbench could not load</h2><p>${escapeHtml(error.message)}</p></div>`;
  setSaveIndicator("Bundle unavailable");
  showToast(error.message, true);
}

function showToast(message, error = false, action = null) {
  clearTimeout(toastTimer);
  const text = document.createElement("span");
  text.textContent = message;
  elements.toast.replaceChildren(text);
  if (action) {
    const button = document.createElement("button");
    button.type = "button";
    button.textContent = action.label;
    button.addEventListener("click", action.handler, { once: true });
    elements.toast.append(button);
  }
  elements.toast.classList.toggle("error", error);
  elements.toast.classList.add("visible");
  toastTimer = setTimeout(() => elements.toast.classList.remove("visible"), 2800);
}

function refreshIcons() {
  if (window.lucide) window.lucide.createIcons({ attrs: { "stroke-width": 1.8 } });
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
