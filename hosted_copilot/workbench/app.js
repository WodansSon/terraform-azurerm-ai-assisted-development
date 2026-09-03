"use strict";

const DATABASE_NAME = "hosted-rule-workbench";
const DATABASE_VERSION = 1;
const ACTIVE_SESSION_KEY = "hosted-rule-workbench.active-session";
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
  candidates: [],
  excludedCandidateCount: 0,
  activeKey: null,
  currentView: "catalog",
  query: ""
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
  await loadBundle(false);
  refreshIcons();
});

function captureElements() {
  for (const id of [
    "snapshot-chip", "refresh-button", "export-button", "import-input", "catalog-count", "plan-count",
    "preview-status", "save-indicator", "metrics-band", "search-input", "review-set-count", "review-selected-button",
    "filter-count", "candidate-list", "assessment-panel",
    "return-catalog-button", "plan-table-body", "empty-plan", "capacity-panel", "approval-badge",
    "preview-summary", "preview-json", "copy-preview-button", "toast"
  ]) {
    elements[id] = document.getElementById(id);
  }
}

function bindEvents() {
  document.querySelectorAll("[data-view]").forEach((button) => {
    button.addEventListener("click", () => switchView(button.dataset.view));
  });
  elements["return-catalog-button"].addEventListener("click", () => switchView("catalog"));
  elements["refresh-button"].addEventListener("click", () => loadBundle(true));
  elements["export-button"].addEventListener("click", exportDraft);
  elements["import-input"].addEventListener("change", importDraft);
  elements["search-input"].addEventListener("input", (event) => updateFilter(event.target.value));
  elements["review-selected-button"].addEventListener("click", reviewSelectedCandidates);
  elements["candidate-list"].addEventListener("click", (event) => {
    if (event.target.closest('input[type="checkbox"], summary')) return;
    const row = event.target.closest("[data-candidate-key]");
    if (row) selectCandidate(row.dataset.candidateKey);
  });
  elements["candidate-list"].addEventListener("change", handleTreeSelection);
  elements["candidate-list"].addEventListener("keydown", (event) => {
    if (event.target.matches('input[type="checkbox"]')) return;
    const row = event.target.closest("[data-candidate-key]");
    if (row && (event.key === "Enter" || event.key === " ")) {
      event.preventDefault();
      selectCandidate(row.dataset.candidateKey);
    }
  });
  elements["assessment-panel"].addEventListener("click", handleAssessmentClick);
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
}

async function loadBundle(cacheBusted) {
  setSaveIndicator("Loading bundle");
  elements["refresh-button"].disabled = true;
  try {
    const suffix = cacheBusted ? `?refresh=${Date.now()}` : "";
    const response = await fetch(`rule-intake-review.json${suffix}`, { cache: "no-store" });
    if (!response.ok) throw new Error(`Bundle request failed with ${response.status}`);
    const bundle = await response.json();
    validateBundle(bundle);
    state.bundle = bundle;
    const discoveredCandidates = normalizeCandidates(bundle);
    const sessionId = getSessionId(bundle);
    const existing = await readSession(sessionId);
    state.session = existing || createSession(sessionId, bundle);
    if (!Array.isArray(state.session.reviewSet)) state.session.reviewSet = [];
    const assessedCandidates = discoveredCandidates.map((candidate) => ({ candidate, assessment: getAssessment(candidate, getDecision(candidate)) }));
    const evaluatedCount = assessedCandidates.filter(({ assessment }) => assessment).length;
    if (evaluatedCount !== discoveredCandidates.length) {
      throw new Error(`AI assessment bundle is incomplete: ${evaluatedCount} of ${discoveredCandidates.length} candidates are evaluated.`);
    }
    state.excludedCandidateCount = assessedCandidates.filter(({ assessment }) => !assessment.hostedApplicable).length;
    state.candidates = assessedCandidates
      .filter(({ assessment }) => assessment.hostedApplicable)
      .map(({ candidate, assessment }) => ({
        ...candidate,
        category: candidate.sourceType === "upstream" ? getUpstreamCategory(candidate) : formatHostedCategory(assessment.hostedCategory)
      }));
    localStorage.setItem(ACTIVE_SESSION_KEY, sessionId);
    await persistSession();
    state.activeKey = null;
    renderAll();
    showToast(cacheBusted ? "Candidate bundle refreshed" : "Workbench draft loaded");
  } catch (error) {
    renderFatalError(error);
  } finally {
    elements["refresh-button"].disabled = false;
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
    relatedHostedRules: candidate.affectedHostedRuleIds.map((id) => ({ id, text: "Mapped Hosted rule", placements: [] }))
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
  return [...interactive, ...upstream];
}

function getSessionId(bundle) {
  const snapshots = bundle.snapshots;
  return [snapshots.hostedCatalogSha256, snapshots.interactive.currentCatalogSha256, snapshots.upstream.currentCommit].join(":");
}

function createSession(id, bundle) {
  return {
    id,
    createdAt: new Date().toISOString(),
    updatedAt: new Date().toISOString(),
    snapshots: bundle.snapshots,
    reviewSet: [],
    decisions: {}
  };
}

function defaultDecision(candidate) {
  const assessment = candidate.assessment || getPriorAssessment(candidate);
  return {
    sourceHash: candidate.hash,
    disposition: "pending",
    rationale: "",
    proposedText: assessment?.proposedText || (candidate.sourceType === "interactive" ? extractRuleBody(candidate.text) : ""),
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
  if (Object.prototype.hasOwnProperty.call(saved, "assessment")) return saved;
  return { ...saved, assessment: getPriorAssessment(candidate) };
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
  state.session.decisions[candidate.key] = {
    ...current,
    ...changes,
    sourceHash: candidate.hash,
    updatedAt: new Date().toISOString()
  };
  state.session.updatedAt = new Date().toISOString();
  persistSession();
  renderAll(false);
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
  const reviewed = state.candidates.filter((candidate) => getDecision(candidate).disposition !== "pending").length;
  const included = getIncludedCandidates().length;
  const combined = getCapacityReports().find((report) => report.name === "test-combined");
  const metrics = [
    ["Hosted-capable inventory", state.candidates.length, `${state.excludedCandidateCount} inapplicable excluded`],
    ["Review set", state.session.reviewSet.length, "Selected with tree checkboxes"],
    ["Decided", reviewed, `${reviewed} of ${state.candidates.length} reviewed`],
    ["In plan", included, "Proposed additions or updates"],
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
  const query = state.query.trim().toLowerCase();
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
    ["upstream", "Contributor Guidance"]
  ];
  elements["candidate-list"].innerHTML = `
    <div class="eligibility-note"><strong>${formatNumber(state.excludedCandidateCount)} inapplicable items excluded</strong><span>Workflow-only and non-review guidance is screened out before maintainer review.</span></div>
    <div class="candidate-list-header">
      <span aria-hidden="true"></span>
      <strong>Candidate</strong>
      <span class="candidate-list-header-summary">
        <strong>Source state</strong>
        <strong>Impact</strong>
        <strong>Token cost</strong>
        <strong>Recommendation</strong>
      </span>
    </div>
  ` + sources.map(([sourceType, label]) => {
    const candidates = filtered.filter((candidate) => candidate.sourceType === sourceType);
    if (!candidates.length) return "";
    const categories = groupCandidatesByCategory(candidates);
    return `
      <details class="candidate-source-root" ${state.query ? "open" : ""}>
        <summary><i data-lucide="folder" aria-hidden="true"></i><strong>${label}</strong><span>${candidates.length}</span></summary>
        ${Object.entries(categories).sort(([left], [right]) => left.localeCompare(right)).map(([category, members]) => renderCandidateCategory(sourceType, category, members)).join("")}
      </details>
    `;
  }).join("");
}

function renderCandidateCategory(sourceType, category, candidates) {
  const open = Boolean(state.query);
  return `
    <details class="candidate-category" data-source-type="${escapeHtml(sourceType)}" data-category="${escapeHtml(category)}" ${open ? "open" : ""}>
      <summary>
        <i data-lucide="folder" aria-hidden="true"></i>
        <strong>${escapeHtml(category)}</strong>
        <span>${candidates.length}</span>
      </summary>
      <div class="candidate-category-items">
        ${candidates.map(renderCandidateTreeRow).join("")}
      </div>
    </details>
  `;
}

function renderCandidateTreeRow(candidate) {
  const assessment = getAssessment(candidate, getDecision(candidate));
  const impact = calculateImpact(assessment.factors);
  const selected = state.session.reviewSet.includes(candidate.key);
  return `
    <div class="candidate-tree-row ${candidate.key === state.activeKey ? "active" : ""} ${selected ? "review-selected" : ""}" role="button" tabindex="0" data-candidate-key="${escapeHtml(candidate.key)}">
      <input type="checkbox" data-review-key="${escapeHtml(candidate.key)}" aria-label="Select ${escapeHtml(candidate.id)} for review" ${selected ? "checked" : ""}>
      <span class="candidate-tree-copy"><strong>${escapeHtml(candidate.id)}</strong><small>${escapeHtml(candidate.title)}</small></span>
      <span class="candidate-tree-summary"><span class="candidate-lifecycle ${escapeHtml(candidate.state)}">${escapeHtml(capitalize(candidate.state))}</span><span class="tree-impact">${impact}</span><span class="tree-cost">${formatSignedNumber(assessment.guardedTokenDelta)}</span><span class="recommendation-badge ${escapeHtml(assessment.recommendation)}">${escapeHtml(formatRecommendation(assessment.recommendation))}</span></span>
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
  const efficiency = draftCost > 0 ? ((impact * 100) / draftCost).toFixed(1) : null;
  const combined = getCapacityReports().find((report) => report.name === "test-combined");
  const projectedHeadroom = combined.budgetHeadroomTokens - draftCost;
  const overlaps = candidate.relatedHostedRules.length
    ? candidate.relatedHostedRules.map((rule) => `<div class="overlap-item"><strong>${escapeHtml(rule.id)}</strong><br>${escapeHtml(rule.text)}</div>`).join("")
    : `<div class="overlap-item">No mapped Hosted rule</div>`;

  elements["assessment-panel"].innerHTML = `
    <div class="assessment-content">
      <div class="assessment-title">
        <div>
          <div class="source-line">
            <span>${escapeHtml(candidate.sourceLabel)}</span>
            <span>/</span>
            <span>${escapeHtml(candidate.id)}</span>
            <span class="candidate-state ${escapeHtml(candidate.state)}">${escapeHtml(candidate.state)}</span>
          </div>
          <h2>${escapeHtml(candidate.title)}</h2>
          <div class="source-line"><span>${escapeHtml(candidate.sourcePath)}</span><span>${escapeHtml(candidate.hash.slice(0, 12))}</span></div>
        </div>
        <span class="decision-badge ${escapeHtml(decision.disposition)}">${escapeHtml(decision.disposition)}</span>
      </div>

      <div class="section-block">
        <span class="section-label">Source rule</span>
        <pre class="evidence-box">${escapeHtml(candidate.text)}</pre>
      </div>

      <div class="section-block">
        <span class="section-label">AI evaluation</span>
        <div class="ai-evaluation-summary">
          <div class="ai-evaluation-heading">
            <span class="recommendation-badge ${escapeHtml(assessment.recommendation)}">Recommend ${escapeHtml(assessment.recommendation)}</span>
            <strong>${escapeHtml(assessment.summary)}</strong>
          </div>
          <p>${escapeHtml(assessment.impactDescription || assessment.rationale)}</p>
        </div>
        <div class="score-strip">
          <div class="score-item impact"><span>Priority score</span><strong>${impact}</strong></div>
          <div class="score-item cost"><span>Token cost</span><strong>${formatSignedNumber(draftCost)}</strong></div>
          <div class="score-item efficiency"><span>Headroom after</span><strong>${formatNumber(projectedHeadroom)}</strong></div>
        </div>
        ${renderPriorityAssessment(assessment, efficiency)}
      </div>

      <div class="section-block">
        <span class="section-label">Current Hosted coverage</span>
        <p class="coverage-summary">${escapeHtml(assessment.currentHostedCoverage)}</p>
        <div class="overlap-list">${overlaps}</div>
      </div>

      <div class="section-block">
        <span class="section-label">Proposed Hosted rule</span>
        <pre class="evidence-box proposed-rule">${escapeHtml(assessment.proposedText || "No Hosted rule change proposed.")}</pre>
      </div>

      <div class="section-block field-stack">
        <label>Decision rationale<textarea data-decision-field="rationale" placeholder="Record why this recommendation was accepted, rejected, or deferred.">${escapeHtml(decision.rationale)}</textarea></label>
        <div class="decision-control ${decision.disposition !== "pending" ? "has-decision" : ""}" role="group" aria-label="Candidate decision">${renderDecisionActions(assessment.recommendation, decision.disposition)}</div>
      </div>
    </div>
  `;
}

function decisionButton(value, label, current, accessibleLabel) {
  return `<button type="button" class="${value} ${value === current ? "active" : ""}" data-disposition="${value}" aria-label="${accessibleLabel}" title="${accessibleLabel}">${label}</button>`;
}

function renderDecisionActions(recommendation, current) {
  const actions = {
    add: [["included", "Add", "Add rule to Hosted guidance"], ["deferred", "Defer", "Defer rule for later investigation"], ["excluded", "Exclude", "Exclude rule from Hosted guidance"]],
    update: [["included", "Update", "Update Hosted guidance"], ["equivalent", "Keep", "Keep current Hosted guidance"], ["deferred", "Defer", "Defer update for later investigation"]],
    retire: [["included", "Remove", "Remove rule from Hosted guidance"], ["equivalent", "Keep", "Keep current Hosted guidance"], ["deferred", "Defer", "Defer retirement for later investigation"]],
    "no-change": [["equivalent", "Keep", "Keep current Hosted guidance"], ["pending", "Reassess", "Request another AI assessment"], ["deferred", "Defer", "Defer rule for later investigation"]],
    exclude: [["included", "Add", "Add rule to Hosted guidance"], ["deferred", "Defer", "Defer rule for later investigation"], ["excluded", "Exclude", "Exclude rule from Hosted guidance"]],
    defer: [["included", "Add", "Add rule to Hosted guidance"], ["deferred", "Defer", "Defer rule for later investigation"], ["excluded", "Exclude", "Exclude rule from Hosted guidance"]]
  };
  return actions[recommendation].map(([value, label, accessibleLabel]) => decisionButton(value, label, current, accessibleLabel)).join("");
}

function renderPriorityAssessment(assessment, efficiency) {
  return `
    <div class="assessment-details-heading">
      <div><strong>Assessment details</strong><p>AI-adjudicated evidence. Maintainers can review these values but cannot edit them.</p></div>
      <span>${escapeHtml(efficiency || "n/a")} impact / 100 tokens</span>
    </div>
    <div class="factor-groups">
      <section class="factor-group value">
        <div class="factor-group-heading"><strong>Rule value</strong><span>Adds to impact</span></div>
        <div class="factor-grid">
          ${FACTORS.filter(([, , , kind]) => kind === "value").map(([name, label, description, kind]) => factorReadout(label, description, kind, assessment.factors[name])).join("")}
        </div>
      </section>
      <section class="factor-group penalty">
        <div class="factor-group-heading"><strong>Review risk</strong><span>Reduces impact</span></div>
        <div class="factor-grid">
          ${FACTORS.filter(([, , , kind]) => kind === "penalty").map(([name, label, description, kind]) => factorReadout(label, description, kind, assessment.factors[name])).join("")}
        </div>
      </section>
    </div>
    <div class="assessment-rationale"><strong>AI adjudication rationale</strong><p>${escapeHtml(assessment.rationale)}</p></div>
  `;
}

function factorReadout(label, description, kind, value) {
  return `
    <div class="factor-line ${kind}">
      <span class="factor-copy"><strong>${escapeHtml(label)}</strong><small>${escapeHtml(description)}</small></span>
      <progress class="factor-meter" max="5" value="${Number(value)}">${Number(value)} of 5</progress>
      <span class="factor-value" aria-label="${escapeHtml(label)} score">${Number(value)}</span>
    </div>
  `;
}

function handleAssessmentClick(event) {
  const button = event.target.closest("[data-disposition]");
  if (!button) return;
  const candidate = getActiveCandidate();
  if (candidate) {
    updateDecision(candidate, { disposition: button.dataset.disposition });
    renderAssessment();
  }
}

function undoDecision(candidate) {
  const previousDisposition = getDecision(candidate).disposition;
  if (previousDisposition === "pending") return;
  updateDecision(candidate, { disposition: "pending" });
  showToast("Decision undone. Candidate returned to undecided.", false, {
    label: "Restore",
    handler: () => {
      updateDecision(candidate, { disposition: previousDisposition });
      showToast("Decision restored");
    }
  });
}

function handleAssessmentInput(event) {
  const candidate = getActiveCandidate();
  if (!candidate) return;
  if (event.target.dataset.decisionField) {
    updateDecision(candidate, { [event.target.dataset.decisionField]: event.target.value });
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
  const included = getIncludedCandidates();
  elements["empty-plan"].hidden = included.length > 0;
  elements["plan-table-body"].innerHTML = included.map((candidate) => {
    const decision = getDecision(candidate);
    const assessment = getAssessment(candidate, decision);
    const impact = assessment ? calculateImpact(assessment.factors) : null;
    const cost = assessment?.guardedTokenDelta || 0;
    const ready = assessment && decision.rationale.trim();
    const readiness = ready ? "Ready" : assessment ? "Needs detail" : "Needs AI assessment";
    return `
      <tr>
        <td><button class="candidate-link" type="button" data-plan-candidate="${escapeHtml(candidate.key)}">${escapeHtml(candidate.id)}</button><br>${escapeHtml(candidate.title)}</td>
        <td>${escapeHtml(candidate.sourceLabel)}</td>
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
  const draftCost = getIncludedCandidates().reduce((sum, candidate) => sum + getAssessment(candidate, getDecision(candidate)).guardedTokenDelta, 0);
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
  return getIncludedCandidates().reduce((sum, candidate) => {
    const assessment = getAssessment(candidate, getDecision(candidate));
    return assessment.affectedSurfaces.some((surface) => reportSurfaces.has(surface)) ? sum + assessment.guardedTokenDelta : sum;
  }, 0);
}

function renderPreview() {
  const included = getIncludedCandidates();
  const decided = state.candidates.filter((candidate) => getDecision(candidate).disposition !== "pending").length;
  const ready = included.length > 0 && included.every((candidate) => {
    const decision = getDecision(candidate);
    return getAssessment(candidate, decision) && decision.rationale.trim();
  });
  elements["approval-badge"].className = `status-badge ${ready ? "success" : "warning"}`;
  elements["approval-badge"].textContent = ready ? "Ready to stage" : "Not staged";
  elements["preview-status"].textContent = ready ? "Ready" : "Draft";
  elements["preview-summary"].innerHTML = `
    <p class="eyebrow">Review state</p>
    <h3>Draft summary</h3>
    <dl class="summary-list">
      <div><dt>Snapshot</dt><dd>${escapeHtml(state.bundle.snapshots.upstream.currentCommit.slice(0, 8))}</dd></div>
      <div><dt>Decisions</dt><dd>${decided}</dd></div>
      <div><dt>Pending</dt><dd>${state.candidates.length - decided}</dd></div>
      <div><dt>Plan items</dt><dd>${included.length}</dd></div>
      <div><dt>Stage status</dt><dd>${ready ? "ready" : "incomplete"}</dd></div>
    </dl>
  `;
  elements["preview-json"].textContent = JSON.stringify(buildDraftExport(), null, 2);
}

function renderCounts() {
  elements["catalog-count"].textContent = formatNumber(state.candidates.length);
  elements["plan-count"].textContent = formatNumber(getIncludedCandidates().length);
  elements["review-set-count"].textContent = `${formatNumber(state.session.reviewSet.length)} selected`;
  elements["review-selected-button"].disabled = state.session.reviewSet.length === 0;
}

function getIncludedCandidates() {
  return state.candidates.filter((candidate) => getDecision(candidate).disposition === "included");
}

function getCapacityReports() {
  return state.bundle.guidanceCapacity.reports;
}

function getActiveCandidate() {
  return state.candidates.find((candidate) => candidate.key === state.activeKey) || null;
}

function selectCandidate(key) {
  state.activeKey = key;
  renderCandidateList();
  renderAssessment();
  refreshIcons();
}

function updateFilter(value) {
  state.query = value;
  renderCandidateList();
  refreshIcons();
}

function handleTreeSelection(event) {
  const candidateCheckbox = event.target.closest("[data-review-key]");
  if (candidateCheckbox) updateReviewSet([candidateCheckbox.dataset.reviewKey], candidateCheckbox.checked);
}

function updateReviewSet(keys, selected) {
  const reviewSet = new Set(state.session.reviewSet);
  for (const key of keys) selected ? reviewSet.add(key) : reviewSet.delete(key);
  state.session.reviewSet = [...reviewSet].filter((key) => state.candidates.some((candidate) => candidate.key === key));
  state.session.updatedAt = new Date().toISOString();
  persistSession();
  renderCandidateList();
  renderMetrics();
  renderCounts();
  refreshIcons();
}

function reviewSelectedCandidates() {
  const first = state.session.reviewSet.find((key) => state.candidates.some((candidate) => candidate.key === key));
  if (!first) return;
  selectCandidate(first);
  showToast(`${state.session.reviewSet.length} candidates in review set`);
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
    schemaVersion: 1,
    kind: "hosted-rule-workbench-draft",
    sessionId: state.session.id,
    exportedAt: new Date().toISOString(),
    snapshots: state.session.snapshots,
    reviewSet: state.session.reviewSet,
    decisions: state.session.decisions
  };
}

function exportDraft() {
  const payload = JSON.stringify(buildDraftExport(), null, 2) + "\n";
  downloadJson(payload, `hosted-rule-draft-${new Date().toISOString().replace(/[:.]/g, "-")}.json`);
  showToast("Draft exported");
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
    state.session.reviewSet = Array.isArray(draft.reviewSet) ? draft.reviewSet : [];
    state.session.decisions = draft.decisions || {};
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
  return value === "no-change" ? "No change" : capitalize(value);
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
