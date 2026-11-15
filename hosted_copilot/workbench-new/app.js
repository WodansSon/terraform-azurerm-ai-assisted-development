"use strict";

(() => {
  const mobileDeviceDetected = window.matchMedia("(max-width: 767.98px)").matches || navigator.userAgentData?.mobile === true || /Android|iPhone|iPad|iPod|Mobile/i.test(navigator.userAgent);
  if (mobileDeviceDetected) document.documentElement.classList.add("mobile-unsupported");
  const state = { workspace: null, token: null, capabilities: {}, targetRepository: null, tab: "candidate-sources", view: "catalog",
    queries: { "candidate-sources": "", "assessment-results": "", "rule-issues": "" }, source: null, assessment: null,
    protectedRule: null, expansion: new Map(), drafts: new Map(), sorts: new Map(), planSort: { field: 'candidate', direction: 'ascending' },
    assistanceExpanded: true, brands: [], waitingPhrases: [], disclosures: new Map(), pending: false };
  const trees = new Map();
  const element = (tag, className = "", text = "") => {
    const node = document.createElement(tag);
    node.className = className;
    node.textContent = text;
    return node;
  };
  const icon = (name, family = "codicon") => {
    const graphic = document.createElementNS("http://www.w3.org/2000/svg", "svg");
    graphic.setAttribute("class", family);
    graphic.setAttribute("aria-hidden", "true");
    const use = document.createElementNS("http://www.w3.org/2000/svg", "use");
    use.setAttribute("href", `sprite/sprite.svg#${family}-${name}`);
    graphic.append(use);
    return graphic;
  };
  const status = (text, kind = "standard") => workbenchStatusBar.update("save", { text, kind, tooltip: text });
  async function closeWorkbench() {
    if (state.pending) {
      status("Wait for the current save to finish before closing Workbench", "error");
      return;
    }
    const closeButton = document.getElementById("close-button");
    closeButton.disabled = true;
    try {
      const response = await fetch("shutdown", { method: "POST", headers: { "X-Workbench-Operation-Token": state.token } });
      if (!response.ok) throw new Error(`Shutdown request failed with ${response.status}`);
      const result = await response.json();
      if (result?.status !== "closed" || result.listenerStopped !== true ||
          !["recorded", "not-recorded", "uncertain"].includes(result.audit?.persistence) ||
          typeof result.audit.correlationGuid !== "string" ||
          !/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/.test(result.audit.correlationGuid)) {
        throw new Error("Workbench shutdown could not be confirmed from the server response");
      }
      const main = element("main", "shutdown-state");
      main.innerHTML = `
        <div class="shutdown-brand-lockup">
          <svg class="shutdown-brand-icon" viewBox="0 0 16 16" aria-hidden="true"><path d="M5 2C3.89543 2 3 2.89543 3 4V6.00469C3 6.53494 2.99231 6.79889 2.91088 7.00209C2.84826 7.15835 2.71576 7.33309 2.2764 7.55276C2.10701 7.63745 2 7.81058 2 7.99997C2 8.18935 2.10699 8.36249 2.27638 8.44719C2.71569 8.66685 2.84809 8.84151 2.91076 8.99819C2.99233 9.20211 3 9.46732 3 10L3 12C3 13.1046 3.89543 14 5 14C5.27614 14 5.5 13.7761 5.5 13.5C5.5 13.2239 5.27614 13 5 13C4.44772 13 4 12.5523 4 12L4.00003 9.94145C4.00033 9.49235 4.00065 9.03033 3.83924 8.6268C3.74212 8.384 3.59654 8.17962 3.40072 8.00002C3.59646 7.82057 3.74199 7.61645 3.83912 7.37408C4.00065 6.971 4.00033 6.51001 4.00003 6.063L4 4C4 3.44772 4.44772 3 5 3C5.27614 3 5.5 2.77614 5.5 2.5C5.5 2.22386 5.27614 2 5 2ZM11 2C12.1046 2 13 2.89543 13 4V6.00469C13 6.53494 13.0077 6.79889 13.0891 7.00209C13.1517 7.15835 13.2842 7.33309 13.7236 7.55276C13.893 7.63745 14 7.81058 14 7.99997C14 8.18935 13.893 8.36249 13.7236 8.44719C13.2843 8.66685 13.1519 8.84151 13.0892 8.99819C13.0077 9.20211 13 9.46732 13 10V12C13 13.1046 12.1046 14 11 14C10.7239 14 10.5 13.7761 10.5 13.5C10.5 13.2239 10.7239 13 11 13C11.5523 13 12 12.5523 12 12L12 9.94145C11.9997 9.49235 11.9994 9.03033 12.1608 8.6268C12.2579 8.384 12.4035 8.17962 12.5993 8.00002C12.4035 7.82057 12.258 7.61645 12.1609 7.37408C11.9993 6.971 11.9997 6.51001 12 6.063L12 4C12 3.44772 11.5523 3 11 3C10.7239 3 10.5 2.77614 10.5 2.5C10.5 2.22386 10.7239 2 11 2Z"/></svg>
          <p class="shutdown-product-name">HOSTED COPILOT RULE MANAGER</p>
        </div>
        <h1>Workbench Closed</h1>
        <p>The local server has stopped. This tab can be closed.</p>`;
      if (result.audit.persistence !== "recorded") {
        const warning = element("div", "rule-issue-banner");
        warning.setAttribute("role", "alert");
        warning.innerHTML = '<svg class="codicon" viewBox="0 0 16 16" aria-hidden="true"><path d="M8 2L15 14H1Z" fill="none" stroke="currentColor"/><path d="M8 6V10M8 12V12.5" stroke="currentColor" stroke-linecap="round"/></svg>';
        const content = element("div");
        const uncertain = result.audit.persistence === "uncertain";
        content.append(
          element("strong", "shutdown-warning-label", uncertain ? "Event Log Recording Unconfirmed:" : "Event Log Entry Not Saved:"),
          document.createTextNode(uncertain ? " Shutdown completed, but its Event Log recording could not be confirmed. "
            : " Shutdown completed, but its Event Log entry was not recorded. "),
          element("strong", "shutdown-warning-label", "Correlation ID:"),
          document.createTextNode(" "),
          element("code", "", result.audit.correlationGuid));
        const dismiss = element("button", "rule-issue-banner-dismiss clickable");
        dismiss.type = "button";
        dismiss.setAttribute("aria-label", "Dismiss Event Log warning");
        dismiss.innerHTML = '<svg class="codicon" viewBox="0 0 16 16" aria-hidden="true"><path d="M4 4L12 12M12 4L4 12" fill="none" stroke="currentColor"/></svg>';
        dismiss.addEventListener("click", () => warning.remove());
        warning.append(content, dismiss);
        main.prepend(warning);
      }
      document.body.replaceChildren(main);
      document.title = "Workbench Closed";
    } catch (error) {
      closeButton.disabled = false;
      status(error.message, "error");
    }
  }
  function assistanceGraphic(kind) {
    const markup = {
      add: '<svg viewBox="0 0 20 20" aria-hidden="true"><path d="M10 2.5v15M2.5 10h15" fill="none" stroke="currentColor" stroke-width="1.2" stroke-linecap="round"/></svg>',
      globe: '<svg viewBox="0 0 20 20" aria-hidden="true"><circle cx="10" cy="10" r="7.5"/><ellipse cx="10" cy="10" rx="3.25" ry="7.5"/><path d="M2.5 10h15M4 5.5h12M4 14.5h12"/></svg>',
      send: '<svg viewBox="0 0 20 20" aria-hidden="true"><path d="M10 16V4m-5 5 5-5 5 5" fill="none" stroke="currentColor" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round"/></svg>',
    };
    const template = document.createElement("template");
    template.innerHTML = markup[kind];
    return template.content.firstElementChild;
  }
  function informationPanel(text, className = "", heading = "", iconName = null) {
    const root = element("div", `information-panel ${className}`);
    const graphic = icon(iconName || "info");
    if (!iconName) {
      graphic.setAttribute("class", "fluent-icon");
      graphic.querySelector("use").setAttribute("href", "sprite/sprite.svg#fluent-info-20-regular");
    }
    const paragraph = element("p");
    if (heading) paragraph.append(element("strong", "banner-heading", `${heading}:`), document.createTextNode(" "));
    paragraph.append(document.createTextNode(text));
    root.append(graphic, paragraph);
    return root;
  }
  const empty = (container, title, description = "", iconName = null) => {
    const box = element("div", "empty-state compact");
    if (iconName) box.append(icon(iconName));
    box.append(element("h3", "", title));
    if (description) box.append(element("p", "", description));
    container.replaceChildren(box);
  };

  function showSelectionEmpty(assessment = false) {
    const box = element("div", "empty-state");
    box.append(icon(assessment ? "checklist" : "tasklist"), element("h2", "", assessment ? "Select an Assessment Result" : "Select a Candidate"),
      element("p", "", assessment ? "The source rule, applicability decision, AI rationale, and Hosted coverage will appear here."
        : "The full source rule, AI evaluation, impact details, Hosted coverage, and maintainer actions will appear here."));
    document.getElementById(assessment ? "assessment-results-detail" : "assessment-panel").replaceChildren(box);
  }

  function showPane(kind, detail) {
    const assessment = kind === "assessment";
    if (!detail) {
      if (assessment) state.assessment = null;
      else { state.source = null; state.protectedRule = null; }
      showSelectionEmpty(assessment);
      syncSelection();
    }
    const panels = assessment ? ["assessment-results-list-panel", "assessment-results-detail"] : ["candidate-panel", "assessment-panel"];
    const buttons = assessment ? ["assessment-pane-assessments", "assessment-pane-details"] : ["candidate-pane-candidates", "candidate-pane-details"];
    panels.forEach((id, index) => { document.getElementById(id).hidden = index === 1 ? !detail : detail; });
    buttons.forEach((id, index) => {
      const selected = index === (detail ? 1 : 0);
      document.getElementById(id).classList.toggle("active", selected);
      document.getElementById(id).setAttribute("aria-selected", String(selected));
    });
    if (!detail) for (const tree of trees.values()) tree.view.refreshLayout();
    syncAssistance();
  }

  const treeColumns = [
    ["candidate", "Candidate", "Candidate"], ["state", "State", "Source State"], ["catalog", "Status", "Catalog Status"],
    ["impact", "Impact", "Impact"], ["cost", "Tokens", "Token Usage"], ["recommendation", "Recommended", "Recommendation"],
  ];
  const assessmentColumns = [
    ["candidate", "Candidate", "Candidate"], ["state", "State", "Source State"],
    ["recommendation", "Recommendation", "Recommendation"], ["override", "Override", "Override"],
  ];

  function sortButton(column, sort, section, plan = false) {
    const active = sort.field === column[0];
    const button = element("button", `candidate-sort-button clickable${active ? " active" : ""}`);
    button.type = "button";
    button.dataset.nativeSort = column[0];
    button.dataset.nativeSection = section;
    if (plan) button.dataset.nativePlanSort = "true";
    const next = active && sort.direction === "ascending" ? "descending" : "ascending";
    button.setAttribute("aria-label", `Sort by ${column[2]}, ${next}`);
    button.setAttribute("aria-pressed", String(active));
    button.title = column[2];
    button.append(element("span", "sort-label", column[1]));
    const indicator = element("span", "sort-indicator");
    indicator.setAttribute("aria-hidden", "true");
    indicator.append(icon(`chevron-${active && sort.direction === "ascending" ? "up" : "down"}`));
    button.append(indicator);
    return button;
  }

  function renderTreeHeader(node, assessment) {
    const header = element("div", assessment ? "assessment-results-header" : "candidate-list-header");
    header.dataset.treeDepth = String(node.depth);
    const sort = state.sorts.get(node.data.section) ?? { field: "candidate", direction: "ascending" };
    const columns = assessment ? assessmentColumns : treeColumns;
    if (!assessment) { const spacer = element("span"); spacer.setAttribute("aria-hidden", "true"); header.append(spacer); }
    header.append(sortButton(columns[0], sort, node.data.section));
    const summary = element("span", assessment ? "" : "candidate-list-header-summary");
    for (const column of columns.slice(1)) summary.append(sortButton(column, sort, node.data.section));
    header.append(summary);
    return header;
  }

  function catalogStatus(source, protectedRule = false) {
    if (protectedRule) return "Protected";
    if (!state.workspace.publishedCatalog) return "Unknown";
    return state.workspace.publishedCatalog.rules.some(rule => rule.canonicalSource?.sourceRuleId === source?.sourceRuleId) ? "Mapped" : "Not mapped";
  }

  function assessmentRecords() { return state.workspace.assessmentResults ?? state.workspace.assessments; }

  function sourceAssessments(source) { return assessmentRecords().filter(result => result.sourceVersionId === source?.sourceVersionId); }

  function categoryLabel(record, assessment) {
    const results = assessment ? [record] : sourceAssessments(record);
    const codes = [...new Set(results.flatMap(result => result.categories))];
    if (!results.length) return "Not Assessed";
    if (!codes.length) return results.every(result => !result.hostedApplicable) ? "Not Applicable" : "Uncategorized";
    if (codes.length > 1) return "Multiple Categories";
    return state.workspace.guidanceSurfaces?.find(surface => surface.code === codes[0])?.label || codes[0];
  }

  function assessmentImpact(record) {
    if (!record?.scorecard?.factors?.length) return null;
    const total = record.scorecard.factors.reduce((sum, factor) => sum + factor.value * factor.weight * (factor.contributionKind === "risk" ? -1 : 1), 0);
    return Math.max(0, total);
  }

  function sourceImpact(source) {
    const values = sourceAssessments(source).map(assessmentImpact).filter(value => value !== null);
    if (!values.length) return "--";
    const minimum = Math.min(...values);
    const maximum = Math.max(...values);
    return minimum === maximum ? String(minimum) : `${minimum}-${maximum}`;
  }

  function selectedSourceChange(source) { return state.workspace.changes.find(change => change.sourceVersionId === source.sourceVersionId); }

  function sourceProposal(source) {
    const saved = selectedSourceChange(source);
    const draft = state.drafts.get(source.sourceVersionId);
    const recommendation = recommendationFor(source);
    const current = state.workspace.analysis.status === "complete" && state.workspace.assessmentContext?.adopted &&
      ["sourcesMatchCurrent", "catalogMatchesCurrent", "protectionMatchesCurrent", "capacityMatchesCurrent"].every(field => state.workspace.analysis[field] === true);
    const synthesized = current && typeof recommendation?.suggestedWording === "string" && recommendation.suggestedWording.trim()
      ? recommendation.suggestedWording : null;
    const actionOnly = current && recommendation && ["retire", "no-change", "exclude", "defer"].includes(recommendation.action);
    const kind = draft ? "maintainer-draft" : saved ? "saved-maintainer-draft" : synthesized ? "reconciled-proposal" : actionOnly ? "reconciled-action" : "unavailable";
    return { kind, saved, draft, recommendation, synthesized, current,
      wording: draft?.wording ?? saved?.wording ?? synthesized ?? "",
      originalWording: saved?.wording ?? synthesized ?? "", rationale: draft?.rationale ?? saved?.rationale ?? "",
      revisionId: draft?.revisionId ?? saved?.revisionId ?? null,
      editable: Boolean(draft || saved),
    };
  }

  function phaseWarning(phase, heading, message) {
    const panel = informationPanel(message, `warning section-guidance ${phase}-warning`, heading, "warning-compact");
    panel.dataset.phaseWarning = phase;
    panel.setAttribute("role", "note");
    return panel;
  }

  function reconciliationNotice(source) {
    const current = state.workspace.analysis.status === "complete" && state.workspace.assessmentContext?.adopted &&
      ["sourcesMatchCurrent", "catalogMatchesCurrent", "protectionMatchesCurrent", "capacityMatchesCurrent"].every(field => state.workspace.analysis[field] === true);
    if (current && recommendationFor(source)) return null;
    if (current) return informationPanel("Reconciliation completed, but this source has no single synthesized recommendation in the current result. An absent recommendation is not a request to rerun the phase.", "section-guidance", "Reconciliation Complete");
    if (recommendationFor(source)) return phaseWarning("reconciliation", "Reconciliation Out of Date",
      "The recorded recommendation does not cover the current analysis inputs. Run reconciliation for the current captured sources, catalog, and protected rules before reviewing a synthesized proposal.");
    const evaluations = state.workspace.phaseEvaluations?.filter(evaluation => evaluation.taskCode === "reconciliation") ?? [];
    const failed = evaluations.length > 0 && evaluations.every(evaluation => ["failed", "cancelled"].includes(evaluation.outcome));
    const completed = evaluations.some(evaluation => evaluation.outcome === "complete");
    return phaseWarning("reconciliation", failed ? "Reconciliation Needs Rerun" : completed ? "Reconciliation Pending Adoption" : evaluations.length ? "Reconciliation Incomplete" : "Reconciliation Required",
      failed ? "Reconciliation has a failed or cancelled evaluation for these inputs. Complete or rerun that phase before reviewing synthesized recommendations."
        : completed ? "Completed reconciliation evaluations exist, but no current adopted recommendation set is available. Finish the current analysis, including any remaining reconciliation and adjudication, to adopt the results."
        : evaluations.length ? "Recorded evaluator output is not an adopted reconciliation for the current inputs. Complete reconciliation and the current analysis before reviewing synthesized recommendations."
          : "No completed reconciliation is available for these inputs. After source assessment and catalog baseline setup are complete, run reconciliation to produce synthesized recommendations.");
  }

  function relationshipReviewNotice(source, saved, wording) {
    const reviews = (state.workspace.relationshipReviews ?? []).filter(review => review.subjects.some(subject => subject.role === "changed" && subject.sourceRuleId === source.sourceRuleId));
    const exact = saved && reviews.filter(review => review.scopeCode === "saved-changes" &&
      review.catalogId === state.workspace.workingCatalog?.catalogId && review.protectedSnapshotId === state.workspace.currentProtectedSnapshot?.snapshotId &&
      review.subjects.some(subject => subject.role === "changed" && subject.revisionId === saved.revisionId && subject.wording === wording)).at(-1);
    if (exact?.outcome === "complete") {
      if (!exact.findings.length) return informationPanel("The recorded relationship review completed with no findings for this saved revision and catalog/protected-rule context. This is not Plan approval.", "section-guidance", "Relationship Review Complete");
      const result = document.createDocumentFragment();
      for (const finding of exact.findings) result.append(phaseWarning("relationship-review", "Relationships Need Review", `${finding.title}: ${finding.rationale}`));
      return result;
    }
    if (!saved) return phaseWarning("relationship-review", "Relationship Review Required",
      "Save the proposed wording as a SQL revision, then run relationship review against the current catalog and protected rules. No completed review covers this proposed wording.");
    if (wording !== saved.wording) return phaseWarning("relationship-review", "Relationship Review Out of Date",
      "The editor contains unsaved wording. Save it, then run relationship review for that exact revision; a review of older wording does not cover these edits.");
    if (exact && ["failed", "cancelled"].includes(exact.outcome)) return phaseWarning("relationship-review", "Relationship Review Needs Rerun",
      "The relationship-review evaluation for this revision failed or was cancelled. Run it again before treating its relationships as reviewed.");
    if (exact?.outcome === "running") return phaseWarning("relationship-review", "Relationship Review Incomplete",
      "Relationship review has no completed result for this saved revision. Complete the phase before treating its relationships as reviewed.");
    return phaseWarning("relationship-review", reviews.length ? "Relationship Review Out of Date" : "Relationship Review Required",
      reviews.length ? "Recorded reviews cover a different revision, review scope, or catalog/protected-rule context. Run relationship review for the current saved revision and inputs."
        : "Run relationship review for the current saved revision, published catalog, and protected rules. No completed result is recorded for this wording.");
  }

  function recommendationFor(source) {
    const assessments = state.workspace.assessments.filter(result => result.sourceVersionId === source.sourceVersionId);
    const ids = new Set(assessments.map(result => result.assessmentResultId));
    const groups = state.workspace.groups.filter(group => group.members.some(member => ids.has(member.assessmentResultId)));
    if (groups.length !== 1) return null;
    const operations = groups[0].operations.filter(operation => operation.role === "primary");
    return operations.length === 1 ? operations[0] : null;
  }

  function renderBulkActions() {
    const root = document.getElementById("bulk-actions");
    root.hidden = false;
    const visibleSources = state.workspace.sources.filter(source => [source.title, source.sourceId, source.content].some(value => String(value ?? "").toLowerCase().includes(state.queries["candidate-sources"].trim().toLowerCase())));
    document.getElementById("bulk-scope-count").textContent = `${visibleSources.length} Sources`;
    for (const [scope, countId] of [["add", "bulk-add-count"], ["update", "bulk-update-count"], ["actionable", "bulk-actionable-count"]]) {
      const count = visibleSources.filter(source => { const operation = recommendationFor(source); return operation && (scope === "actionable" ? ["add", "update", "retire", "restore"].includes(operation.action) : operation.action === scope); }).length;
      document.getElementById(countId).textContent = `${count} Candidate${count === 1 ? "" : "s"}`;
      const button = root.querySelector(`[data-bulk-scope="${scope}"]`);
      button.disabled = count === 0 || !state.capabilities.bulkPlan;
      button.title = count === 0 ? "No adopted recommendations match the current results" : "Atomic recommendation selection is not connected";
    }
    document.getElementById("bulk-undo").disabled = true;
    document.getElementById("bulk-actions-note").textContent = state.workspace.analysis.status === "complete" ? "" : "Reconciliation not complete.";
  }

  function syncAssistance() {
    const source = state.tab === "candidate-sources" ? state.workspace?.sources.find(item => item.sourceVersionId === state.source)
      : state.tab === "assessment-results" ? state.workspace?.sources.find(item => item.sourceVersionId === assessmentRecords().find(result => result.assessmentResultId === state.assessment)?.sourceVersionId) : null;
    const detail = document.getElementById(state.tab === "assessment-results" ? "assessment-results-detail" : "assessment-panel");
    const available = Boolean(source && state.view === "catalog" && !detail.hidden && !detail.closest('.workspace-tab-panel').hidden);
    const expanded = available && state.assistanceExpanded;
    const panel = document.getElementById("rule-assistance-panel");
    panel.hidden = !expanded;
    document.querySelector(".app-shell").classList.toggle("assist-sidebar-open", expanded);
    const toggle = document.getElementById("assist-panel-toggle");
    toggle.disabled = false;
    toggle.setAttribute("aria-expanded", String(expanded));
    toggle.setAttribute("aria-pressed", String(state.assistanceExpanded));
    toggle.setAttribute("aria-label", `${state.assistanceExpanded ? "Hide" : "Show"} AI assistance`);
    toggle.title = toggle.getAttribute("aria-label");
    toggle.replaceChildren(icon(state.assistanceExpanded ? "layout-sidebar-right" : "layout-sidebar-right-off"));
    if (!expanded) return;
    const content = document.getElementById("assist-sidebar-content");
    if (content.dataset.sourceVersion === String(source.sourceVersionId)) return;
    content.dataset.sourceVersion = String(source.sourceVersionId);
    const root = element("section", "rule-assistance");
    root.dataset.ruleAssistance = "";
    const header = element("div", "assist-header");
    header.append(element("span", "section-label", "AI Assistance:"));
    const actions = element("div", "assist-sidebar-heading-actions");
    const clear = element("button", "titlebar-icon clickable");
    clear.type = "button";
    clear.setAttribute("aria-label", "New chat");
    clear.disabled = true;
    clear.append(icon("add"));
    const close = element("button", "titlebar-icon clickable");
    close.type = "button";
    close.setAttribute("aria-label", "Close AI assistance");
    close.append(icon("close"));
    close.addEventListener("click", () => { state.assistanceExpanded = false; syncAssistance(); });
    actions.append(clear, close);
    header.append(actions);
    const body = element("div");
    body.id = "rule-assistance-body";
    body.dataset.assistBody = "";
    const note = informationPanel("This response is AI-generated. Please review it for accuracy and relevance before use. Native SQL chat storage is not initialized.", "section-guidance");
    const replies = element("div", "assist-chat-reply-window");
    const toolbar = element("div", "assist-chat-conversation-toolbar");
    const identity = element("span", "assist-chat-identity");
    identity.append(icon("copilot"), element("span", "", "Copilot ·"), element("em", "assist-chat-context-label", "Chat"));
    toolbar.append(identity);
    const transcript = element("div", "assist-chat-response scroll-surface");
    transcript.id = "rule-assistance-conversation";
    transcript.setAttribute("role", "region");
    transcript.setAttribute("aria-label", "AI assistance conversation");
    replies.append(toolbar, transcript);
    const composer = element("div", "assist-chat-composer");
    const context = element("span", "assist-chat-context");
    const addContext = element("button", "assist-chat-add-context");
    addContext.type = "button";
    addContext.disabled = true;
    addContext.setAttribute("aria-label", "Additional context is not available");
    addContext.append(assistanceGraphic("add"));
    context.append(addContext, assistanceGraphic("globe"), element("em", "assist-chat-context-label", source.sourceId));
    const input = element("textarea", "assist-goal scroll-surface");
    input.maxLength = 8000;
    input.setAttribute("aria-label", "Message AI about this rule");
    input.placeholder = "Chat with Copilot to describe what you want to accomplish with this rule...";
    input.disabled = true;
    input.title = "A versioned SQL chat-storage migration is required";
    const footer = element("div", "assist-chat-toolbar");
    const assignment = state.workspace.llmAssignments?.find(item => item.taskCode === "chat");
    const profile = element("span", "assist-chat-profile");
    const brand = state.brands.find(item => assignment?.model.startsWith(item.prefix));
    if (brand) {
      const graphic = icon("question");
      graphic.setAttribute("class", "llm-icon");
      graphic.querySelector("use").setAttribute("href", `sprite/sprite.svg#llm-${brand.icon}`);
      profile.append(graphic);
    }
    const modelName = assignment?.model === "gpt-6.1-sol" ? "GPT-6.1 Sol" : assignment?.model === "gpt-5.4" ? "GPT-5.4" : assignment?.model;
    const effort = assignment?.reasoningEffort;
    profile.append(document.createTextNode(assignment ? `${modelName}${effort ? ` · ${effort[0].toUpperCase()}${effort.slice(1)}` : ""}` : "Unavailable"));
    const send = element("button", "assist-chat-send");
    send.type = "button";
    send.disabled = true;
    send.setAttribute("aria-label", "Send request");
    send.title = "A versioned SQL chat-storage migration is required";
    send.append(assistanceGraphic("send"));
    footer.append(profile, send);
    composer.append(context, input, footer);
    body.append(note, replies, composer);
    root.append(header, body);
    content.replaceChildren(root);
  }

  function sourcePlanBlocker(source) {
    if (!state.capabilities.plan) return "SQL Plan commands are unavailable";
    if (!state.workspace.workingCatalog) return "A working catalog is required for Plan selection";
    if (source.presence !== "present") return "Only current sources can enter the Plan";
    if (state.drafts.has(source.sourceVersionId)) return "Save proposed wording before Plan selection";
    const change = selectedSourceChange(source);
    if (!change?.action) return "Save an explicit rule action before Plan selection";
    if (change.action !== "retire" && !change.placements?.length) return "Select a catalog placement before Plan selection";
    return null;
  }

  function selectSourceForPlan(source, selected) {
    const saved = selectedSourceChange(source);
    if (!saved) return;
    const placement = saved.placements?.[0];
    return changePlan({ changeId: saved.changeId, expectedRevisionId: saved.revisionId,
      expectedPlanVersionId: currentPlan()?.versionId ?? null, operation: selected ? "add" : "remove", action: saved.action,
      targetRuleVersionId: saved.targetRuleVersionId ?? null, surface: placement?.surface, sectionHeading: placement?.sectionHeading });
  }

  function sortedRecords(records, section, assessment, protectedRule) {
    const sort = state.sorts.get(section) ?? { field: "candidate", direction: "ascending" };
    const collator = new Intl.Collator(undefined, { numeric: true, sensitivity: "base" });
    const value = record => {
      const source = assessment ? state.workspace.sources.find(item => item.sourceVersionId === record.sourceVersionId) : record;
      if (sort.field === "candidate") return `${record.displayedId || record.sourceId || record.localResultKey} ${record.title}`;
      if (sort.field === "state") return protectedRule ? "Required" : source?.lifecycle || "Captured";
      if (sort.field === "catalog") return catalogStatus(source, protectedRule);
      if (sort.field === "impact") return assessment ? assessmentImpact(record) ?? -1 : Number.parseFloat(sourceImpact(source)) || -1;
      if (sort.field === "recommendation") return protectedRule ? "Immutable" : "Unknown";
      return "";
    };
    return [...records].sort((left, right) => {
      const compared = typeof value(left) === "number" ? value(left) - value(right) : collator.compare(value(left), value(right));
      return (sort.direction === "ascending" ? compared : -compared) || collator.compare(String(left.displayedId || left.sourceId || left.localResultKey), String(right.displayedId || right.sourceId || right.localResultKey));
    });
  }

  function detailBlock(label, value, code = false) {
    if (value === null || value === undefined || value === "") return null;
    const block = element("div", "section-block");
    block.append(element("span", "section-label", label));
    block.append(element(code ? "pre" : "div", code ? "evidence-box scroll-surface" : "subcontext-container", String(value)));
    return block;
  }

  function evidenceDisclosure(key, title, count, body) {
    const section = element("section", "section-block evidence-disclosure");
    section.dataset.evidenceDisclosure = key;
    const heading = element("div", "evidence-disclosure-heading");
    const label = element("span", "section-label evidence-disclosure-label", title);
    if (count !== null) label.append(element("span", "ui-badge count-badge type-compact", String(count)));
    const content = element("div", "evidence-disclosure-body");
    content.id = `evidence-${encodeURIComponent(key)}`;
    content.append(body);
    const toggle = element("button", "titlebar-icon clickable evidence-disclosure-toggle");
    toggle.type = "button";
    toggle.setAttribute("aria-controls", content.id);
    const update = () => {
      const expanded = state.disclosures.get(key) === true;
      content.hidden = !expanded;
      toggle.setAttribute("aria-expanded", String(expanded));
      toggle.setAttribute("aria-label", `${expanded ? "Collapse" : "Expand"} ${title === "Source Rules" ? "source rules" : "related Hosted coverage"}`);
      toggle.title = toggle.getAttribute("aria-label");
      toggle.replaceChildren(icon(expanded ? "chevron-up" : "chevron-down"));
    };
    toggle.addEventListener("click", () => { state.disclosures.set(key, !state.disclosures.get(key)); update(); });
    update();
    heading.append(label, toggle);
    section.append(heading, content);
    return section;
  }

  function sourceEvidence(source, records) {
    const root = element("div", "contributing-rules");
    const disclosure = element("details", "contributing-rule");
    disclosure.open = true;
    const summary = element("summary");
    const identity = element("span", "contributing-rule-identity");
    identity.append(element("strong", "rule-reference", source.sourceId), element("small", "", source.title));
    const badges = element("span", "contributing-rule-badges");
    badges.append(element("span", "ui-badge status-capsule status-badge neutral", state.workspace.sourceLanes.find(lane => lane.laneId === source.laneId)?.label || source.sourceDefinitionId), icon("chevron-down"));
    summary.append(identity, badges);
    const content = element("div", "contributing-rule-content");
    const location = element("div", "source-line");
    location.append(element("span", "", source.location || ""), element("span", "", source.contentSha256.slice(0, 12)));
    content.append(location, element("pre", "evidence-box scroll-surface", source.content));
    for (const record of records) {
      const meaning = element("div", "contributing-rule-meaning");
      meaning.append(element("strong", "", records.length === 1 ? "Source meaning" : record.title), element("p", "", record.sourceMeaning));
      content.append(meaning);
    }
    disclosure.append(summary, content);
    root.append(disclosure);
    const result = document.createDocumentFragment();
    result.append(informationPanel("These are the captured source requirements and their recorded assessment evidence. These references are evidence, not additional Hosted rules selected for the Promotion Plan.", "section-guidance"), root);
    return result;
  }

  function openScoringLegend(record, trigger) {
    if (document.querySelector('[data-scoring-legend-dialog]')) return;
    const contributions = record.scorecard.factors.map(factor => ({ ...factor,
      points: factor.value * factor.weight * (factor.contributionKind === "risk" ? -1 : 1) }));
    const valuePoints = contributions.filter(factor => factor.contributionKind === "value").reduce((sum, factor) => sum + factor.points, 0);
    const riskPoints = -contributions.filter(factor => factor.contributionKind === "risk").reduce((sum, factor) => sum + factor.points, 0);
    const priority = assessmentImpact(record);
    const maximum = contributions.reduce((sum, factor) => sum + factor.weight *
      (factor.contributionKind === "risk" ? -factor.minimumValue : factor.maximumValue), 0);
    const dialog = element("dialog", "modal-dialog");
    dialog.dataset.scoringLegendDialog = "";
    dialog.setAttribute("aria-labelledby", "scoring-legend-dialog-title");
    const heading = element("div", "modal-dialog-heading");
    const title = element("div", "modal-dialog-title");
    const label = element("h2", "", "Assessment Details Legend");
    label.id = "scoring-legend-dialog-title";
    title.append(icon("json"), label);
    const close = element("button", "titlebar-icon clickable");
    close.type = "button";
    close.dataset.dialogClose = "";
    close.dataset.scoringLegendClose = "";
    close.setAttribute("aria-label", "Close assessment details legend");
    close.title = "Close assessment details legend";
    close.append(icon("close"));
    close.addEventListener("click", () => dialog.close());
    heading.append(title, close);
    const content = element("div", "modal-dialog-content scroll-surface");
    const sections = element("div", "assessment-legend-sections");
    const section = (name, description, keyLabel = null, entries = []) => {
      const root = element("section", "assessment-legend-section");
      root.append(element("strong", "", name), element("p", "", description));
      if (keyLabel) {
        const key = element("div", "assessment-legend-key");
        key.append(element("strong", "", keyLabel));
        for (const [className, text] of entries) {
          const item = element("span");
          const swatch = element("i", `legend-swatch ${className}`);
          swatch.setAttribute("aria-hidden", "true");
          item.append(swatch, document.createTextNode(text));
          key.append(item);
        }
        root.append(key);
      }
      return root;
    };
    sections.append(section("Priority Score:", `A weighted score from 0 to ${maximum}. Higher means a stronger candidate to consider, not an instruction to add the rule.`, "Assessed Priority:",
      [["priority-low", "Low payoff"], ["priority-potential", "Potential value"], ["priority-promising", "Promising"], ["priority-strong", "Strong"]]),
    section("Token Cost:", "Estimated space your selected change adds (+) or frees (-)."),
    section("Token Headroom:", "Room left after your planned changes and the action selected here. Below zero means over budget."),
    element("hr", "assessment-legend-divider"),
    section("Rule Value:", "How much useful guidance this rule could add. Higher ratings mean a stronger reason to include it.", "Assessed Value:",
      [["value-low", "Low"], ["value-moderate", "Moderate"], ["value-high", "Strong"]]),
    section("Review Risk:", "What could reduce the rule's value: unhelpful review comments or guidance that is already covered. Higher ratings mean more concern.", "Assessed Risk:",
      [["risk-low", "Low"], ["risk-moderate", "Moderate"], ["risk-high", "High"]]));
    const breakdown = element("section", "assessment-legend-breakdown evidence-disclosure");
    const breakdownHeading = element("div", "evidence-disclosure-heading");
    breakdownHeading.append(element("strong", "", `Why does this rule have a priority score of ${priority}?`));
    const toggle = element("button", "titlebar-icon clickable evidence-disclosure-toggle");
    toggle.type = "button";
    toggle.dataset.assessmentScoreToggle = "";
    toggle.setAttribute("aria-controls", "assessment-score-breakdown");
    const body = element("div", "evidence-disclosure-body");
    body.id = "assessment-score-breakdown";
    body.hidden = true;
    const syncToggle = () => {
      toggle.setAttribute("aria-expanded", String(!body.hidden));
      toggle.setAttribute("aria-label", `${body.hidden ? "Expand" : "Collapse"} score breakdown`);
      toggle.title = toggle.getAttribute("aria-label");
      toggle.replaceChildren(icon(body.hidden ? "chevron-down" : "chevron-up"));
    };
    toggle.addEventListener("click", () => { body.hidden = !body.hidden; syncToggle(); });
    syncToggle();
    breakdownHeading.append(toggle);
    body.append(element("p", "", "A rating multiplied by its weight gives the points. Value adds points; risk and existing coverage subtract them."));
    const table = element("table", "assessment-legend-table");
    const head = element("thead");
    const header = element("tr");
    for (const text of ["Factor", "Rating", "Weight", "Points"]) { const cell = element("th", "", text); cell.scope = "col"; header.append(cell); }
    head.append(header);
    const rows = element("tbody");
    for (const factor of contributions) {
      const row = element("tr");
      const name = element("th", "", factor.label);
      name.scope = "row";
      row.append(name, element("td", "", String(factor.value)), element("td", "", String(factor.weight)),
        element("td", "", `${factor.points > 0 ? "+" : ""}${factor.points}`));
      rows.append(row);
    }
    table.append(head, rows);
    const total = valuePoints - riskPoints;
    body.append(table, element("p", "assessment-legend-total", total < 0
      ? `${valuePoints} value points - ${riskPoints} risk points = ${total}. The Priority Score has a minimum of 0.`
      : `${valuePoints} value points - ${riskPoints} risk points = ${priority} Priority Score`));
    breakdown.append(breakdownHeading, body);
    content.append(sections, breakdown);
    dialog.append(heading, content);
    dialog.addEventListener("close", () => { dialog.remove(); if (trigger.isConnected && !trigger.disabled) trigger.focus({ preventScroll: true }); }, { once: true });
    dialog.addEventListener("keydown", event => { if (event.key === "Escape") { event.preventDefault(); event.stopPropagation(); dialog.close(); } });
    dialog.addEventListener("click", event => {
      if (event.target !== dialog) return;
      const rect = dialog.getBoundingClientRect();
      if (event.clientX < rect.left || event.clientX > rect.right || event.clientY < rect.top || event.clientY > rect.bottom) dialog.close();
    });
    document.body.append(dialog);
    dialog.showModal();
    close.focus();
  }

  function assessmentEvidence(record) {
    const root = element("div", "section-block");
    root.dataset.assessmentEvidence = "";
    const heading = element("div", "assessment-details-heading");
    const title = element("div", "assessment-details-title-row");
    title.append(element("strong", "section-label", "Assessment Details:"));
    const legend = element("button", "titlebar-icon clickable scoring-legend-trigger");
    legend.type = "button";
    legend.dataset.scoringLegendOpen = "";
    legend.setAttribute("aria-label", "Show assessment details legend");
    legend.title = "Show assessment details legend";
    legend.append(icon("question"));
    legend.addEventListener("click", () => openScoringLegend(record, legend));
    title.append(legend);
    heading.append(title);
    root.append(heading);
    const context = informationPanel("Priority and factor scores describe the recorded source assessment; they do not validate maintainer-edited wording.", "assessment-context section-guidance", "Assessment");
    root.append(context);
    const scores = element("div", "score-strip");
    const capacity = guidanceProjection();
    for (const [label, value, className] of [["Priority Score:", String(assessmentImpact(record) ?? "--"), "impact"],
      ["Token Cost:", state.workspace.changes.some(change => change.sourceVersionId === record.sourceVersionId && change.action) ? "--" : "0", "cost"],
      ["Token Headroom:", capacity.available && capacity.emptyPlan ? capacity.headroom.toLocaleString("en-US") : "--", "efficiency"]]) {
      const score = element("div", `score-item ${className}`);
      score.append(element("span", "control-subtitle", label), element("strong", "", value));
      scores.append(score);
    }
    root.append(scores);
    const factors = element("div", "factor-groups");
    for (const [kind, label, badge] of [["value", "Rule Value:", "Adds to Impact"], ["risk", "Review Risk:", "Reduces Impact"]]) {
      const group = element("section", `factor-group ${kind === "risk" ? "penalty" : "value"}`);
      const groupHeading = element("div", "factor-group-heading");
      groupHeading.append(element("strong", "", label), element("span", `ui-badge status-capsule direction-badge ${kind === "risk" ? "negative" : "positive"}`, badge));
      const grid = element("div", "factor-grid");
      for (const factor of record.scorecard.factors.filter(item => item.contributionKind === kind)) {
        const strength = factor.value <= 2 ? "low" : factor.value === 3 ? "moderate" : "high";
        const line = element("div", `factor-line ${kind === "risk" ? `penalty risk-${strength}` : `value value-${strength}`}`);
        const copy = element("span", "factor-copy");
        copy.append(element("strong", "control-subtitle", `${factor.label}:`), element("small", "", factor.description));
        const progress = element("progress", "factor-meter");
        progress.max = factor.maximumValue;
        progress.value = factor.value;
        const value = element("span", "factor-value", String(factor.value));
        value.setAttribute("aria-label", `${factor.label} score`);
        line.append(copy, progress, value);
        grid.append(line);
      }
      group.append(groupHeading, grid);
      factors.append(group);
    }
    root.append(factors);
    return root;
  }

  function showDetail(record, kind = "source") {
    const assessment = kind === "assessment";
    const protectedRule = kind === "protected";
    const container = document.getElementById(assessment ? "assessment-results-detail" : "assessment-panel");
    const source = assessment ? state.workspace.sources.find(item => item.sourceVersionId === record.sourceVersionId) : record;
    if (assessment) state.assessment = record.assessmentResultId;
    else {
      state.source = protectedRule ? null : record.sourceVersionId;
      state.protectedRule = protectedRule ? record.ruleVersionId : null;
    }
    const identity = protectedRule ? record.displayedId : assessment ? record.localResultKey : record.sourceId;
    const header = element("div", "assessment-title");
    const heading = element("div");
    heading.append(element("div", "source-line detail-identity", `${protectedRule ? "Protected rule" : assessment ? "Assessment" : "Captured source"} / ${identity}`),
      element("h2", "detail-rule-title", record.title || source?.sourceId || "Captured source"));
    const metadata = element("div", "source-line");
    metadata.append(element("span", "", "1 source rule"), element("span", "", protectedRule ? record.surface : categoryLabel(record, assessment)));
    const lane = state.workspace.sourceLanes.find(item => item.laneId === source?.laneId);
    if (lane) metadata.append(element("span", "", lane.label));
    heading.append(metadata);
    header.append(heading);
    const headerActions = element("div", "detail-header-actions");
    const statuses = element("span", "assessment-title-statuses");
    if (!assessment && !protectedRule) {
      const lifecycle = record.lifecycle || "captured";
      statuses.append(element("span", `ui-badge status-capsule candidate-state ${lifecycle}`, lifecycle[0].toUpperCase() + lifecycle.slice(1)),
        element("span", "ui-badge status-capsule catalog-status", catalogStatus(record)));
    }
    if (assessment) {
      const stateBadge = element("span", `ui-badge status-capsule status-badge ${record.hostedApplicable ? "neutral" : "warning"}`,
        record.hostedApplicable ? "Applicable" : "Original Exclusion");
      statuses.append(stateBadge);
    }
    if (protectedRule) {
      const badges = element("div", "native-detail-badges");
      badges.append(element("span", "ui-badge status-capsule candidate-state required", "Required"),
        element("span", "ui-badge status-capsule catalog-status protected", "Protected"),
        element("span", "ui-badge status-capsule recommendation-badge immutable", "Immutable"));
      statuses.append(...badges.children);
    }
    const content = element("div", "assessment-content scroll-surface");
    const backToTop = element("button", "scroll-edge-button clickable detail-back-to-top");
    backToTop.type = "button";
    backToTop.dataset.detailBackToTop = "";
    backToTop.dataset.workbenchTooltip = "Back to top";
    backToTop.setAttribute("aria-label", "Back to top");
    backToTop.title = "Back to top";
    backToTop.disabled = true;
    backToTop.append(icon("chevron-up"));
    backToTop.addEventListener("click", () => content.scrollTo({ top: 0, behavior: "smooth" }));
    content.addEventListener("scroll", () => { backToTop.disabled = content.scrollTop <= 1; }, { passive: true });
    headerActions.append(statuses, backToTop);
    header.append(headerActions);
    if (protectedRule) {
      for (const [label, value, code] of [["Protected Instruction:", record.wording, true], ["Protection:", record.protectionReason],
        ["Surface:", record.surface], ["Provenance:", record.provenance], ["Authored Source:", record.sourcePath]]) {
        if (label === "Protection:") {
          content.append(informationPanel(value, "protected-rule-information section-guidance", "Protection", "lock"));
          continue;
        }
        const block = detailBlock(label, value, code);
        if (block) content.append(block);
      }
    } else {
      const records = assessment ? [record] : sourceAssessments(record);
      if (source) content.append(evidenceDisclosure(`${kind}:${identity}:sources`, "Source Rules", 1, sourceEvidence(source, records)));
      if (assessment) content.append(informationPanel("The AI assessment is read-only. Proposed wording and maintainer decisions do not alter this recorded result.", "section-guidance", "Original Assessment", "lock"));
      for (const result of records) {
        if (records.length === 1) content.append(assessmentEvidence(result));
        else {
          const disclosure = element("details", "contributing-rule");
          disclosure.append(element("summary", "clickable", result.title), assessmentEvidence(result));
          content.append(disclosure);
        }
      }
      if (assessment) {
        for (const [label, value] of [["Assessed Meaning:", record.sourceMeaning], ["Applicability:", record.applicabilityRationale],
          ["Confidence:", record.confidenceRationale], ["Existing Coverage:", record.existingCoverageRationale]]) {
          const block = detailBlock(label, value);
          if (block) content.append(block);
        }
      }
    }
    if (!assessment && !protectedRule) {
      const proposal = sourceProposal(record);
      const saved = proposal.saved;
      const draft = { wording: proposal.wording, rationale: proposal.rationale, revisionId: proposal.revisionId };
      const editor = element("section", "section-block hosted-rule-comparison");
      for (const rule of state.workspace.publishedCatalog?.rules.filter(item => item.canonicalSource?.sourceRuleId === record.sourceRuleId) ?? []) {
        const current = element("div", "current-hosted-rule");
        const currentHeading = element("div", "current-hosted-rule-heading");
        const currentLabel = element("span", "section-label", "Current Hosted Rule: ");
        currentLabel.append(element("strong", "rule-reference", rule.displayedId));
        const currentStatuses = element("span", "current-hosted-rule-statuses");
        currentStatuses.append(element("span", `ui-badge status-capsule catalog-status ${rule.lifecycle}`, rule.lifecycle[0].toUpperCase() + rule.lifecycle.slice(1)));
        currentHeading.append(currentLabel, currentStatuses);
        current.append(currentHeading, element("pre", "evidence-box scroll-surface", rule.wording));
        editor.append(current);
      }
      const editorHeading = element("div", "proposed-rule-heading");
      editor.dataset.proposalKind = proposal.kind;
      const label = element("label", "section-label", proposal.editable ? "Maintainer Draft:" : "Proposed Hosted Rule:");
      label.htmlFor = "native-proposed-wording";
      const input = element("textarea", "evidence-box proposed-rule scroll-surface");
      input.id = label.htmlFor;
      input.setAttribute("aria-label", proposal.editable ? "Maintainer draft wording" : "Proposed Hosted rule wording");
      input.value = draft.wording;
      input.maxLength = 200000;
      input.hidden = proposal.kind === "reconciled-action";
      input.disabled = proposal.kind === "unavailable";
      input.readOnly = !proposal.editable || !state.capabilities.save;
      const rationaleField = element("div", "rationale-field rationale-control-group");
      const rationaleHeading = element("div", "rationale-heading");
      const rationaleLabel = element("label", "control-subtitle", "Decision Rationale:");
      rationaleLabel.htmlFor = "native-change-rationale";
      rationaleLabel.id = "native-change-rationale-label";
      const rationale = element("textarea", "evidence-box scroll-surface");
      rationale.id = rationaleLabel.htmlFor;
      rationale.setAttribute("aria-labelledby", rationaleLabel.id);
      rationale.setAttribute("aria-describedby", "native-change-rationale-limit");
      rationale.placeholder = "Record why this proposed wording or action is appropriate.";
      rationale.value = draft.rationale;
      rationale.maxLength = 500;
      rationale.disabled = !state.capabilities.save || !proposal.editable;
      const counter = element("small", "rationale-limit", `${rationale.value.length} / 500 characters`);
      counter.id = "native-change-rationale-limit";
      const save = element("button", "titlebar-icon proposed-rule-save");
      save.type = "button";
      save.setAttribute("aria-label", proposal.editable ? "Save maintainer draft" : "Save proposed Hosted rule");
      save.title = proposal.kind === "unavailable" ? "No proposed Hosted rule is available"
        : proposal.editable ? "Save maintainer draft" : "Group proposals cannot be saved through the source-only command";
      save.append(icon("save"));
      const reset = element("button", "titlebar-icon clickable");
      reset.type = "button";
      reset.setAttribute("aria-label", saved ? "Reset draft to saved wording" : "Reset maintainer draft");
      reset.title = reset.getAttribute("aria-label");
      reset.append(icon("debug-restart"));
      const originalWording = proposal.originalWording;
      const explanation = element("div");
      explanation.dataset.proposedRuleExplanation = "";
      const relationshipPanel = element("div", "relationship-review-panel");
      relationshipPanel.dataset.relationshipReviewPanel = "";
      const refreshExplanation = () => {
        const recommendation = recommendationFor(record);
        const records = sourceAssessments(record);
        const edited = input.value !== (proposal.synthesized ?? originalWording);
        const label = proposal.kind === "reconciled-action" ? "Reconciliation Rationale" : proposal.synthesized ? edited ? "Original Assessment Rationale" : "Assessment Rationale"
          : records.length ? edited ? "Original Source Assessment Rationale" : "Source Assessment Rationale" : "Assessment Pending";
        const text = (proposal.synthesized || proposal.kind === "reconciled-action" ? recommendation?.rationale : null) || (records.length === 1 ? records[0].scorecard.rationale || records[0].applicabilityRationale : records.length
          ? "Multiple source assessments are recorded; a reconciled proposal rationale is not available for this source."
          : "No completed source assessment or reconciled recommendation is available for this source.");
        const panel = informationPanel(text, "assessment-explanation", label);
        panel.dataset.assessmentExplanation = "";
        explanation.replaceChildren(panel);
        if (proposal.kind === "unavailable") {
          relationshipPanel.replaceChildren();
          relationshipPanel.hidden = true;
          return;
        }
        relationshipPanel.hidden = false;
        relationshipPanel.replaceChildren(proposal.kind === "reconciled-action" ? phaseWarning("relationship-review", "Relationship Review Waiting for Catalog Change",
            "Record the reconciled catalog action through the group-bound change workflow before reviewing it. A source text editor cannot represent this action.")
            : relationshipReviewNotice(record, saved, input.value));
      };
      const updateSave = () => {
        save.disabled = !proposal.editable || !state.capabilities.save || state.pending || !input.value.trim() || !rationale.value.trim();
        reset.disabled = !proposal.editable || input.value === originalWording;
        counter.textContent = `${rationale.value.length} / 500 characters`;
        refreshExplanation();
      };
      const retainDraft = () => {
        state.drafts.set(record.sourceVersionId, { wording: input.value, rationale: rationale.value, revisionId: draft.revisionId });
        status("Unsaved changes", "warning");
        updateSave();
      };
      input.addEventListener("input", retainDraft);
      rationale.addEventListener("input", retainDraft);
      reset.addEventListener("click", () => { input.value = originalWording; retainDraft(); });
      updateSave();
      save.addEventListener("click", () => saveSource(record, { revisionId: draft.revisionId }, input.value, rationale.value));
      const editorActions = element("span", "proposed-rule-actions");
      editorActions.setAttribute("role", "group");
      editorActions.setAttribute("aria-label", "Proposed rule actions");
      editorActions.append(save, reset);
      editorHeading.append(label, editorActions);
      const inputLabel = element("label");
      inputLabel.append(input);
      editor.append(editorHeading, explanation, inputLabel, relationshipPanel);
      content.append(editor);
      const planControls = element("section", "section-block rule-actions");
      const actionLabel = element("span", "section-label", "Rule Actions: ");
      actionLabel.append(element("strong", "rule-reference", record.sourceId));
      planControls.append(actionLabel);
      const actionContext = !state.workspace.workingCatalog
        ? "No working catalog is loaded in this SQL workspace. Catalog-dependent actions are blocked."
        : !saved ? "Proposed wording does not yet have a saved SQL revision. Catalog-dependent actions are not ready."
          : "Action availability is bound to the saved SQL revision and working catalog.";
      planControls.append(informationPanel(actionContext, "rule-actions-guidance section-guidance"));
      const actionContent = element("div", "rule-actions-content");
      const actionOptions = element("fieldset", "action-options");
      actionOptions.append(element("legend", "sr-only", "Rule action"));
      const actionGroup = element("div", "control-group action-plan-group");
      actionGroup.append(actionOptions);
      actionContent.append(element("span", "control-subtitle", "Rule Action:"), actionGroup);
      planControls.append(actionContent);
      const choose = (id, labelText, values) => {
        const control = element("div", "control-group");
        const label = element("label", "control-subtitle", labelText);
        label.htmlFor = id;
        const select = element("select", "editable-text");
        select.id = id;
        for (const [value, text] of values) { const option = element("option", "", text); option.value = value; select.append(option); }
        control.append(label, select);
        actionContent.append(control);
        return select;
      };
      const action = { value: ["add", "update", "retire", "restore"].includes(saved?.action) ? saved.action : "" };
      for (const [value, text] of [["add", "Add"], ["update", "Update"], ["retire", "Retire"], ["restore", "Restore"]]) {
        const option = element("label", "action-option");
        const radio = element("input");
        radio.type = "radio";
        radio.name = "native-rule-action";
        radio.value = value;
        radio.checked = value === action.value;
        radio.disabled = !state.capabilities.plan || !saved || !state.workspace.workingCatalog;
        radio.title = !state.workspace.workingCatalog ? "Working catalog baseline is not loaded in SQL" : !saved ? "Save proposed wording first" : text;
        if (!radio.disabled) option.classList.add("clickable");
        option.classList.toggle("selected", radio.checked);
        radio.addEventListener("change", () => { action.value = value; updateAction(); updateDecisionSave(); });
        option.append(radio, element("span", "", text));
        actionOptions.append(option);
      }
      const target = choose("native-plan-target", "Target Rule:", [["", "Select a target rule"], ...(state.workspace.workingCatalog?.rules ?? []).map(rule => [String(rule.ruleVersionId), rule.displayedId])]);
      target.value = saved?.targetRuleVersionId ? String(saved.targetRuleVersionId) : "";
      const surfaces = state.workspace.workingCatalog?.surfaces ?? [];
      const surface = choose("native-plan-surface", "Surface:", surfaces.map(item => [item.code, item.title || item.code]));
      if (saved?.placements?.length) surface.value = saved.placements[0].surface;
      const section = choose("native-plan-section", "Section:", []);
      const updateSections = () => {
        section.replaceChildren();
        for (const heading of surfaces.find(item => item.code === surface.value)?.sections ?? []) { const option = element("option", "", heading); option.value = heading; section.append(option); }
      };
      const updateAction = () => {
        target.disabled = action.value === "add";
        surface.disabled = section.disabled = action.value === "retire";
        target.parentElement.hidden = !action.value || action.value === "add";
        surface.parentElement.hidden = section.parentElement.hidden = !action.value || action.value === "retire";
        for (const radio of actionOptions.querySelectorAll('input[type="radio"]')) radio.closest("label").classList.toggle("selected", radio.value === action.value);
      };
      surface.addEventListener("change", updateSections);
      updateSections();
      if (saved?.placements?.length) section.value = saved.placements[0].sectionHeading;
      updateAction();
      if (!state.capabilities.plan || !saved || !state.workspace.workingCatalog) {
        for (const control of [target, surface, section]) control.disabled = true;
      }
      const add = element("button", "titlebar-icon clickable rationale-save");
      add.type = "button";
      add.setAttribute("aria-label", "Save decision");
      add.append(icon("save"));
      const updateDecisionSave = () => { add.disabled = !state.capabilities.plan || !saved || !state.workspace.workingCatalog || !action.value || state.pending || state.drafts.has(record.sourceVersionId); };
      updateDecisionSave();
      if (add.disabled) add.title = !state.workspace.workingCatalog ? "Working catalog required" : "Save proposed wording before adding it to the Plan";
      add.addEventListener("click", () => changePlan({ changeId: saved.changeId, expectedRevisionId: saved.revisionId,
        expectedPlanVersionId: currentPlan()?.versionId ?? null, operation: "add", action: action.value,
        targetRuleVersionId: action.value === "add" ? null : Number(target.value), surface: surface.value, sectionHeading: section.value }));
      input.addEventListener("input", () => { add.disabled = true; });
      rationale.addEventListener("input", () => { add.disabled = true; });
      rationaleHeading.append(rationaleLabel, add);
      rationaleField.append(rationaleHeading, rationale, counter);
      actionContent.append(rationaleField);
      content.append(planControls);
    }
    container.replaceChildren(header, content);
    syncSelection();
    showPane(assessment ? "assessment" : "source", true);
  }

  async function saveSource(source, saved, wording, rationale) {
    if (state.pending) return;
    state.pending = true;
    status("Saving", "warning");
    try {
      const response = await fetch("api/changes", { method: "POST", headers: { "Content-Type": "application/json", "X-Workbench-Operation-Token": state.token },
        body: JSON.stringify({ sourceVersionId: source.sourceVersionId, expectedRevisionId: saved?.revisionId ?? null, wording, rationale }) });
      if (!response.ok) throw new Error(response.status === 409 ? "Saved wording changed; reload before saving" : "Save failed; wording remains unsaved");
      state.workspace = await response.json();
      state.drafts.delete(source.sourceVersionId);
      state.pending = false;
      render();
      showDetail(source);
      status("Saved to SQL");
    } catch (error) { status(error.message, "error"); }
    finally { state.pending = false; }
  }

  function syncSelection() {
    for (const row of document.querySelectorAll("[data-native-record]")) {
      const selected = row.dataset.nativeKind === "protected" ? Number(row.dataset.nativeRecord) === state.protectedRule
        : row.dataset.nativeKind === "assessment" ? Number(row.dataset.nativeRecord) === state.assessment
          : Number(row.dataset.nativeRecord) === state.source;
      row.classList.toggle("active", selected);
      if (selected) row.setAttribute("aria-current", "true"); else row.removeAttribute("aria-current");
    }
  }

  function renderMetrics() {
    const complete = state.workspace.analysis.status === "complete";
    const emptyCount = "0";
    const issueCount = complete ? String(state.workspace.findings.length) : emptyCount;
    const issueBadge = document.getElementById("rule-issues-tab-count");
    issueBadge.querySelector(".count-badge-value").textContent = issueCount;
    issueBadge.hidden = false;
    const target = state.targetRepository;
    if (target?.status === "validated") {
      const targetLabel = `${target.repository} ${target.branch}@${target.commit.slice(0, 8)}`;
      const behindBy = Number(target.behindBy) || 0;
      const aheadBy = Number(target.aheadBy) || 0;
      const syncIndicators = [];
      if (behindBy > 0) syncIndicators.push(`\u2193 ${behindBy}`);
      if (aheadBy > 0) syncIndicators.push(`\u2191 ${aheadBy}`);
      workbenchStatusBar.update("target", { text: targetLabel, tooltip: [targetLabel, ...syncIndicators].join(" | "),
        ariaLabel: `${targetLabel}.${behindBy > 0 ? ` ${behindBy} commits behind ${target.upstreamRepository} ${target.upstreamBranch}.` : ""}${aheadBy > 0 ? ` ${aheadBy} commits ahead.` : ""}`,
        kind: behindBy > 0 ? "warning" : "standard" });
    } else {
      const reason = target?.reason || "Promotion target could not be resolved";
      workbenchStatusBar.update("target", { text: "Target unavailable", tooltip: reason, ariaLabel: reason, kind: "error" });
    }
    const savedAt = state.workspace.changes.map(change => change.savedAt).sort().at(-1);
    workbenchStatusBar.update("save", { text: state.capabilities.save ? savedAt ? `Saved ${new Date(savedAt).toLocaleTimeString()}` : "No unsaved changes" : "Read-only",
      kind: state.capabilities.save ? "success" : "standard", icon: state.capabilities.save ? "check-compact" : "lock", tooltip: state.capabilities.save ? "Changes are saved explicitly to the local SQL database" : "SQL write commands are not available" });
    if (state.drafts.size) status("Unsaved changes", "warning");
    workbenchStatusBar.update("eligible", { text: String(state.workspace.sources.length), tooltip: "Captured SQL sources", ariaLabel: "Show captured SQL sources" });
    workbenchStatusBar.update("ruleIssues", { text: issueCount, hidden: false,
      tooltip: complete ? "Rule Issues" : "Adjudication not complete", ariaLabel: "Open rule issues" });
    workbenchStatusBar.update("excluded", { text: assessmentRecords().length ? String(assessmentRecords().filter(item => !item.hostedApplicable).length) : emptyCount,
      tooltip: "Original exclusions recorded by completed source assessments" });
    for (const [key, label] of [["mapped", "Mapped"], ["unmapped", "Not mapped"]]) workbenchStatusBar.update(key, {
      text: state.workspace.publishedCatalog ? String(state.workspace.sources.filter(source => catalogStatus(source) === label).length) : emptyCount,
      tooltip: state.workspace.publishedCatalog ? label : "No published catalog is selected" });
    const capacity = guidanceProjection();
    workbenchStatusBar.update("capacity", { text: capacity.available ? capacity.headroom.toLocaleString("en-US") : emptyCount,
      tooltip: capacity.available ? "Published guidance headroom under the selected SQL capacity policy" : "Published guidance usage is unavailable" });
    workbenchStatusBar.update("plan", { text: String(currentPlan()?.items.length ?? 0) });
    workbenchStatusBar.update("promotionApproval", { text: "Not ready", kind: "warning", tooltip: "An exact reviewed Plan and generated output are required" });
    workbenchStatusBar.update("validationIssues", { segments: { errors: { text: emptyCount }, warnings: { text: emptyCount } },
      tooltip: "Workflow validation has not run", ariaLabel: "Workflow validation has not run" });
    for (const [key, node] of workbenchStatusBar.nodes) {
      if (node instanceof HTMLButtonElement) node.disabled = !["eligible", "excluded", "ruleIssues", "plan", "promotionApproval"].includes(key) &&
        !(["mapped", "unmapped"].includes(key) && state.workspace.publishedCatalog) && !(key === "capacity" && capacity.available);
      if (node.dataset.workbenchTooltip) node.removeAttribute("title");
    }
  }

  function currentPlan() {
    const plans = (state.workspace.plans ?? []).filter(plan => plan.label === "Promotion Plan");
    return plans.length === 1 ? plans[0] : null;
  }

  async function changePlan(command) {
    if (state.pending) return;
    state.pending = true;
    try {
      const response = await fetch("api/plan", { method: "POST", headers: { "Content-Type": "application/json", "X-Workbench-Operation-Token": state.token }, body: JSON.stringify(command) });
      if (!response.ok) { const result = await response.json(); throw new Error(String(result.error || "Plan change failed").replaceAll("-", " ")); }
      state.workspace = await response.json();
      render();
      renderPlan();
      state.pending = false;
      status("Plan saved to SQL");
      const source = state.workspace.sources.find(item => item.sourceVersionId === state.source);
      if (source) showDetail(source);
    } catch (error) { status(error.message, "error"); }
    finally { state.pending = false; }
  }

  function renderTree(containerId, stickyId, records, assessment = false) {
    const container = document.getElementById(containerId);
    const query = state.queries[assessment ? "assessment-results" : "candidate-sources"].trim().toLowerCase();
    const protectedRules = assessment ? [] : (state.workspace.currentProtectedSnapshot?.rules ?? []).filter(rule =>
      [rule.displayedId, rule.title, rule.wording, rule.protectionReason, rule.provenance, rule.sourcePath].some(value => String(value ?? "").toLowerCase().includes(query)));
    if (!records.length && !protectedRules.length) {
      trees.get(containerId)?.view.destroy();
      trees.delete(containerId);
      if (assessment) empty(container, "No Assessment Results", query ? "No candidates match this outcome and search."
        : state.workspace.analysis.status !== "complete" ? "Assessment conclusions are not complete for the current inputs." : "No candidates match this outcome and search.");
      else empty(container, "No Candidates Available", query ? "No sources match the current search." : "No captured sources are available.");
      return;
    }
    if (!trees.has(containerId)) {
      const tree = { input: null, view: null };
      tree.view = new WorkbenchHierarchicalView.HierarchicalView({
        viewport: container,
        stickyContainer: document.getElementById(stickyId),
        adapter: {
          accumulateRoots: true,
          keepLastRowVisible: true,
          getDefaultRowHeight: () => Number.parseFloat(getComputedStyle(document.documentElement).getPropertyValue("--tree-row-height")),
          getInput: () => tree.input,
          buildNodes: input => {
            const roots = [];
            const parent = (id, kind, label, children) => ({ id, kind, expanded: state.expansion.get(id) ?? Boolean(input.query),
              data: { label, count: children.reduce((sum, child) => sum + (child.data.count ?? 1), 0) }, children });
            const leaves = (section, values, protectedRule = false) => [{
              id: `header:${section}`, kind: "header", expanded: true, data: { section, count: values.length },
              children: sortedRecords(values, section, assessment, protectedRule).map(record => ({
                id: protectedRule ? `protected:rule:${record.ruleVersionId}` : `record:${assessment ? record.assessmentResultId : record.sourceVersionId}`,
                kind: protectedRule ? "protected-leaf" : "leaf", stickyEligible: false, data: record,
              })),
            }];
            if (input.protectedRules.length) {
              const surfaces = [...new Set(input.protectedRules.map(rule => rule.surface))].sort();
              roots.push(parent("protected:overrides", "protected-root", "OVERRIDES", surfaces.map(surface =>
                parent(`protected:surface:${surface}`, "protected-folder", surface[0].toUpperCase() + surface.slice(1),
                  leaves(`protected:${surface}`, input.protectedRules.filter(rule => rule.surface === surface), true)))));
            }
            const order = { interactive: 0, contributor: 1, maintainer: 2 };
            for (const lane of [...state.workspace.sourceLanes].sort((left, right) => (order[left.code] ?? left.displayOrder + 3) - (order[right.code] ?? right.displayOrder + 3))) {
            const items = input.records;
            const members = items.filter(record => {
              const source = assessment ? state.workspace.sources.find(item => item.sourceVersionId === record.sourceVersionId) : record;
              return source?.laneId === lane.laneId;
            });
            if (!members.length) continue;
            const groups = new Map();
            for (const record of members) {
              const source = assessment ? state.workspace.sources.find(item => item.sourceVersionId === record.sourceVersionId) : record;
              const label = categoryLabel(record, assessment);
              if (!groups.has(label)) groups.set(label, []);
              groups.get(label).push(record);
            }
            const folders = [...groups].sort(([left], [right]) => left.localeCompare(right)).map(([label, values]) =>
              parent(`folder:${assessment ? "assessment" : "source"}:${lane.laneId}:${label}`, "folder", label, leaves(`${assessment ? "assessment" : "source"}:${lane.laneId}:${label}`, values)));
            const root = parent(`${assessment ? "assessment" : "source"}:lane:${lane.laneId}`, "source", lane.label, folders);
            root.data.count = members.length;
            if (lane.code === "contributor") {
              const sources = assessment ? members.map(record => state.workspace.sources.find(source => source.sourceVersionId === record.sourceVersionId)) : members;
              root.data.provenance = [...new Set(sources.filter(source => source?.originRepository && source.originRef && source.originCommit)
                .map(source => `${source.originRepository} \u00b7 ${source.originRef}@${source.originCommit.slice(0, 8)}`))];
            }
            roots.push(root);
            }
            return roots;
          },
          onExpandedChange: (node, expanded) => state.expansion.set(node.id, expanded),
          renderRow: node => {
            if (node.kind === "header") return renderTreeHeader(node, assessment);
            const leaf = node.kind === "leaf" || node.kind === "protected-leaf";
            const protectedRule = node.kind === "protected-leaf";
            const root = node.kind === "source" || node.kind === "protected-root";
            const button = element(leaf ? "div" : "button", leaf ? `${assessment ? "assessment-result-row" : "candidate-tree-row"} clickable${protectedRule ? " protected-rule-row" : ""}`
              : `hierarchical-parent-row ${root ? "candidate-source-row" : "candidate-folder-row"} clickable`);
            if (leaf) { button.setAttribute("role", "button"); button.tabIndex = 0; }
            else button.type = "button";
            if (leaf && !assessment && !protectedRule) {
              const checkbox = element("input");
              checkbox.type = "checkbox";
              checkbox.className = "clickable";
              checkbox.setAttribute("aria-label", `Include ${node.data.sourceId} in Promotion Plan`);
              const saved = selectedSourceChange(node.data);
              checkbox.checked = Boolean(saved && currentPlan()?.items.some(item => item.changeId === saved.changeId));
              const blocker = sourcePlanBlocker(node.data);
              checkbox.disabled = Boolean(blocker) || state.pending;
              checkbox.title = blocker || "Include in Promotion Plan";
              checkbox.addEventListener("click", event => event.stopPropagation());
              checkbox.addEventListener("change", () => selectSourceForPlan(node.data, checkbox.checked));
              button.append(checkbox);
            } else if (!assessment || !leaf) button.append(icon(protectedRule ? "lock" : node.kind === "protected-root" ? "shield" : "folder"));
            if (leaf) {
              button.dataset.nativeRecord = String(protectedRule ? node.data.ruleVersionId : assessment ? node.data.assessmentResultId : node.data.sourceVersionId);
              button.dataset.nativeKind = protectedRule ? "protected" : assessment ? "assessment" : "source";
              const copy = element("span", "candidate-tree-copy");
              copy.append(element("strong", "", protectedRule ? node.data.displayedId : assessment ? node.data.localResultKey : node.data.sourceId), element("small", "", node.data.title));
              const badges = element("span", assessment ? "assessment-result-summary" : "candidate-tree-summary");
              if (protectedRule) {
                badges.append(element("span", "ui-badge status-capsule candidate-lifecycle required", "Required"),
                  element("span", "ui-badge status-capsule catalog-status protected", "Protected"),
                  element("span", "tree-impact", "--"), element("span", "tree-cost", "--"),
                  element("span", "ui-badge status-capsule recommendation-badge immutable", "Immutable"));
              } else {
                const source = assessment ? state.workspace.sources.find(item => item.sourceVersionId === node.data.sourceVersionId) : node.data;
                const lifecycle = source?.lifecycle || "captured";
                badges.append(element("span", `ui-badge status-capsule candidate-lifecycle ${lifecycle}`, lifecycle[0].toUpperCase() + lifecycle.slice(1)));
                if (assessment) {
                  badges.append(element("span", "ui-badge status-capsule recommendation-badge", "Unknown"));
                  const override = element("span", "assessment-override-cell");
                  override.append(element("span", "ui-badge status-capsule status-badge neutral assessment-override-pill", "None"));
                  badges.append(override);
                } else {
                  badges.append(element("span", "ui-badge status-capsule catalog-status", catalogStatus(source)),
                    element("span", "tree-impact", sourceImpact(source)), element("span", "tree-cost", "--"),
                    element("span", "ui-badge status-capsule recommendation-badge", "Unknown"));
                }
              }
              button.append(copy, badges);
            } else {
              button.setAttribute("data-hierarchical-toggle", "");
              button.setAttribute("aria-expanded", String(node.expanded));
              const label = element("span", root ? "source-summary-label" : "candidate-parent-label");
              label.append(element("strong", "", node.data.label));
              for (const provenance of node.data.provenance ?? []) {
                const pill = element("span", "ui-badge status-capsule source-provenance-pill type-compact", provenance);
                pill.dataset.workbenchTooltip = provenance;
                label.append(pill);
              }
              const noun = node.kind === "protected-root" ? "Override" : node.kind === "protected-folder" ? "Rule" : assessment ? "Excluded" : "Source";
              button.append(label, element("span", "ui-badge count-badge type-compact", `${node.data.count} ${noun}${node.data.count === 1 || assessment ? "" : "s"}`));
            }
            return button;
          },
        },
      });
      trees.set(containerId, tree);
    }
    const tree = trees.get(containerId);
    tree.input = { records, protectedRules, query };
    tree.view.setInput(tree.input);
    syncSelection();
  }

  function render() {
    let assessmentState = document.getElementById("native-assessment-state");
    if (!assessmentState) {
      assessmentState = element("span", "ui-badge status-capsule status-badge warning");
      assessmentState.id = "native-assessment-state";
      document.getElementById("assessment-results-heading").after(assessmentState);
    }
    assessmentState.hidden = !assessmentRecords().length;
    assessmentState.textContent = state.workspace.assessmentContext?.adopted ? "Adopted" : "Partial Run";
    assessmentState.title = "Completed evaluator facts; overall-run completion and reconciliation are separate";
    const matches = (record, tab) => {
      const input = state.queries[tab].trim().toLowerCase();
      const filter = tab === "candidate-sources" ? input.match(/(?:^|\s)status:(mapped|unmapped)(?:\s|$)/)?.[1] : null;
      if (filter && catalogStatus(record) !== (filter === "mapped" ? "Mapped" : "Not mapped")) return false;
      const query = filter ? input.replace(/(?:^|\s)status:(mapped|unmapped)(?=\s|$)/, "").trim() : input;
      return [record.title, record.sourceId, record.content, record.sourceMeaning, record.location].some(value => String(value ?? "").toLowerCase().includes(query));
    };
    renderTree("candidate-list", "candidate-sticky-stack", state.workspace.sources.filter(record => matches(record, "candidate-sources")));
    renderTree("assessment-results-list", "assessment-sticky-stack", assessmentRecords().filter(record => !record.hostedApplicable && matches(record, "assessment-results")), true);
    const issues = document.getElementById("rule-issues-list");
    const findings = state.workspace.findings.filter(record => matches(record, "rule-issues"));
    const issuePager = document.getElementById("rule-issue-tab-pager");
    const noIssueTabs = !document.querySelector('#rule-issues-filters [role="tab"]');
    issuePager.hidden = noIssueTabs;
    issuePager.closest(".rule-issues-list-panel").toggleAttribute("data-empty-issue-tabs", noIssueTabs);
    issues.replaceChildren();
    if (!findings.length) empty(issues, "No Rule Issues", state.workspace.findings.length
      ? "No rule issues match the current filter and search." : "No rule issues are recorded for the current analysis.", "collection");
    if (!state.workspace.findings.length) empty(document.getElementById("rule-issues-detail"), "Rule Issue Details",
      "There are no issue details to display.", "list-selection");
    for (const finding of findings) {
      const button = element("button", "native-record-row clickable", finding.title);
      button.type = "button";
      button.addEventListener("click", () => {
        const detail = document.getElementById("rule-issues-detail");
        if (detail) detail.replaceChildren(element("h2", "", finding.title), informationPanel(finding.rationale, "", "Recorded Finding"));
      });
      issues.append(button);
    }
    renderMetrics();
    renderBulkActions();
  }

  function previewEmptyFile(title, message, iconName = "diff") {
    const file = element("section", "preview-review-file");
    const body = element("div", "preview-file-body");
    empty(body, title, message, iconName);
    body.firstElementChild.classList.add("preview-empty-state");
    file.append(body);
    return file;
  }

  function renderPreview() {
    document.getElementById("preview-review-toggle").disabled = true;
    document.getElementById("approve-export-button").disabled = true;
    const totals = element("span", "preview-change-summary");
    totals.append(element("b", "", "+0"), element("i", "", "-0"));
    const stat = element("span", "preview-diff-stat");
    stat.setAttribute("aria-label", "0 additions and 0 deletions");
    for (let index = 0; index < 5; index++) stat.append(element("i", "neutral"));
    document.getElementById("preview-review-context").replaceChildren(element("strong", "", "0 files changed"), totals, stat);
    empty(document.getElementById("preview-summary"), "No Promotion Items", "There are no promotion files to preview.", "ruby");
    const hasProtectedRules = Boolean(state.workspace.currentProtectedSnapshot?.rules?.length);
    const files = document.getElementById("preview-files");
    files.replaceChildren(
      previewEmptyFile("No Proposed Changes", "Add an available rule action to review its line-level diff."),
      previewEmptyFile("No Payload Changes", "Add or update a Promotion Plan item to review its selection payload changes."),
      previewEmptyFile("No Resulting Catalog", "Add, update, or retire a Promotion Plan item to review the resulting catalog mutations."),
      previewEmptyFile(hasProtectedRules ? "Protected File Content Unavailable" : "No Protected Rules",
        hasProtectedRules ? "The captured file content is not exposed by the current SQL read view." : "There are no protected rules to preview.",
        hasProtectedRules ? "lock" : "collection"),
    );
  }

  function initializePaneSplitter(owner, separator, widthProperty, initialWidth) {
    const readWidth = () => Number.parseFloat(getComputedStyle(owner).getPropertyValue(widthProperty));
    let idleTimer = 0;
    let hoverTimer = 0;
    let lastPoint = null;
    let keyboardInput = false;
    let drag = null;
    const clearHover = () => {
      clearTimeout(hoverTimer);
      delete separator.dataset.splitterHover;
    };
    const hideGrip = () => {
      clearTimeout(idleTimer);
      delete separator.dataset.splitterGripVisible;
    };
    const resizeTo = width => {
      if (!owner.clientWidth) return;
      const minimum = 240;
      const maximum = Math.max(minimum, owner.clientWidth - 320);
      const bounded = Math.round(Math.max(minimum, Math.min(maximum, width)));
      owner.style.setProperty(widthProperty, `${bounded}px`);
      separator.setAttribute("aria-valuemin", String(minimum));
      separator.setAttribute("aria-valuemax", String(maximum));
      separator.setAttribute("aria-valuenow", String(bounded));
      separator.setAttribute("aria-valuetext", `${bounded} pixels`);
    };
    const revealGrip = event => {
      if (event.buttons !== 0 || drag || !owner.getClientRects().length) return;
      if (lastPoint?.x === event.clientX && lastPoint?.y === event.clientY) return;
      lastPoint = { x: event.clientX, y: event.clientY };
      clearTimeout(idleTimer);
      separator.dataset.splitterGripVisible = "";
      idleTimer = setTimeout(hideGrip, 1200);
    };
    const finish = () => {
      const pointerId = drag?.pointerId;
      drag = null;
      hideGrip();
      clearHover();
      delete separator.dataset.splitterActive;
      delete document.documentElement.dataset.workbenchSplitterDragging;
      if (pointerId !== undefined && separator.hasPointerCapture(pointerId)) separator.releasePointerCapture(pointerId);
    };
    document.addEventListener("keydown", event => {
      keyboardInput = true;
      if (event.key === "Escape" && drag) finish();
    }, true);
    document.addEventListener("pointerdown", () => {
      keyboardInput = false;
      delete separator.dataset.splitterKeyboardFocus;
    }, true);
    owner.addEventListener("pointerenter", revealGrip);
    owner.addEventListener("pointermove", revealGrip);
    owner.addEventListener("pointerleave", event => {
      if (!owner.contains(event.relatedTarget) && !separator.contains(event.relatedTarget)) lastPoint = null;
    });
    separator.addEventListener("pointerenter", event => {
      revealGrip(event);
      clearHover();
      hoverTimer = setTimeout(() => {
        if (!drag && separator.matches(":hover")) separator.dataset.splitterHover = "";
      }, 300);
    });
    separator.addEventListener("pointerleave", clearHover);
    separator.addEventListener("focus", () => { if (keyboardInput) separator.dataset.splitterKeyboardFocus = ""; });
    separator.addEventListener("blur", () => { delete separator.dataset.splitterKeyboardFocus; });
    separator.addEventListener("keydown", event => {
      separator.dataset.splitterKeyboardFocus = "";
      if (!['ArrowLeft', 'ArrowRight', 'Home', 'End'].includes(event.key)) return;
      event.preventDefault();
      resizeTo(event.key === "Home" ? 240 : event.key === "End" ? owner.clientWidth - 320
        : readWidth() + (event.key === "ArrowRight" ? 16 : -16));
    });
    separator.addEventListener("pointerdown", event => {
      if (event.button !== 0) return;
      event.preventDefault();
      clearHover();
      hideGrip();
      drag = { pointerId: event.pointerId, x: event.clientX, width: readWidth() };
      separator.focus({ preventScroll: true });
      separator.setPointerCapture(event.pointerId);
      separator.dataset.splitterActive = "";
      document.documentElement.dataset.workbenchSplitterDragging = "";
    });
    separator.addEventListener("pointermove", event => {
      if (drag?.pointerId === event.pointerId) resizeTo(drag.width + event.clientX - drag.x);
    });
    for (const name of ["pointerup", "pointercancel", "lostpointercapture"]) separator.addEventListener(name, finish);
    separator.addEventListener("dblclick", () => resizeTo(initialWidth));
    window.addEventListener("blur", finish);
    new ResizeObserver(() => resizeTo(readWidth())).observe(owner);
    resizeTo(readWidth());
  }

  async function checkIconPaint() {
    const probe = icon("json");
    probe.classList.add("sr-only");
    document.body.append(probe);
    try {
      const deadline = performance.now() + 3000;
      while (performance.now() < deadline) {
        await new Promise(resolve => requestAnimationFrame(resolve));
        try { if (probe.querySelector("use").getBBox().width > 0) return; } catch {}
      }
      throw new Error("Workbench icons could not render");
    } finally { probe.remove(); }
  }

  async function start() {
    if (mobileDeviceDetected) { document.documentElement.dataset.nativeWorkbenchReady = "unsupported"; return; }
    document.title = "Workbench New - Native SQL";
    document.querySelector(".brand-block h1").textContent = "HOSTED COPILOT RULE MANAGER NEW";
    workbenchStatusBar.render();
    const [spriteResponse, brandResponse, phraseResponse] = await Promise.all([
      fetch("sprite/sprite.svg", { cache: "no-store" }), fetch("llm-brands.json", { cache: "no-store" }),
      fetch("assistance-waiting-phrases.json", { cache: "no-store" }),
    ]);
    if (!spriteResponse.ok || !brandResponse.ok || !phraseResponse.ok) throw new Error("Workbench presentation assets could not be loaded");
    registerWorkbenchIconSymbols(new DOMParser().parseFromString(await spriteResponse.text(), "image/svg+xml"));
    const brands = await brandResponse.json();
    const phrases = await phraseResponse.json();
    if (!Array.isArray(brands) || !brands.length || !brands.every(brand => typeof brand.prefix === "string" && typeof brand.icon === "string") ||
        !Array.isArray(phrases) || !phrases.length || !phrases.every(phrase => typeof phrase === "string" && phrase.trim())) throw new Error("Workbench AI presentation assets are invalid");
      state.brands = brands;
      state.waitingPhrases = phrases;
    document.querySelector(".workspace").classList.remove("icon-paint-pending");
    for (const control of document.querySelectorAll("button")) {
      const allowed = control.closest(".workspace-tabs, .candidate-pane-switch") || control.id === "close-button" || control.id === "assist-panel-toggle" || control.dataset.view || control.id === "return-catalog-button";
      if (!allowed) { control.disabled = true; control.title = "Pending native integration"; }
    }
    document.getElementById("draft-menu").hidden = true;
    document.querySelector('[data-view="catalog"]').setAttribute("aria-label", "Candidate Sources");
    document.querySelector(".search-field .sr-only").textContent = "Search captured sources";
    document.getElementById("search-input").setAttribute("aria-label", "Search captured sources");
    const configResponse = await fetch("runtime-config", { cache: "no-store" });
    if (!configResponse.ok) throw new Error("Native runtime is unavailable");
    const config = await configResponse.json();
    state.token = config.operationToken;
    state.capabilities = config.capabilities;
    state.targetRepository = config.targetRepository;
    const response = await fetch(config.workspaceEndpoint, { cache: "no-store", headers: { "X-Workbench-Operation-Token": state.token } });
    if (!response.ok) throw new Error("Selected SQL workspace could not be read");
    state.workspace = await response.json();
    render();
    initializePaneSplitter(document.querySelector(".rule-issues-layout"), document.getElementById("rule-issues-list-resizer"), "--rule-issues-list-width", 360);
    initializePaneSplitter(document.querySelector(".preview-layout"), document.getElementById("preview-tree-resizer"), "--preview-tree-width", 380);
    document.getElementById("assist-panel-toggle").addEventListener("click", () => { state.assistanceExpanded = !state.assistanceExpanded; syncAssistance(); });
    const splitter = document.getElementById("assist-sidebar-resizer");
    const setWidth = width => {
      const bounded = Math.round(Math.max(320, Math.min(680, document.documentElement.clientWidth - 400, width)));
      document.documentElement.style.setProperty("--assist-sidebar-width", `${bounded}px`);
      splitter.setAttribute("aria-valuenow", String(bounded));
    };
    splitter.addEventListener("keydown", event => {
      if (!["ArrowLeft", "ArrowRight", "Home", "End"].includes(event.key)) return;
      event.preventDefault();
      setWidth(event.key === "Home" ? 320 : event.key === "End" ? 680 : Number(splitter.getAttribute("aria-valuenow")) + (event.key === "ArrowLeft" ? 16 : -16));
    });
    splitter.addEventListener("pointerdown", event => {
      event.preventDefault();
      splitter.setPointerCapture(event.pointerId);
      const move = current => setWidth(document.documentElement.clientWidth - current.clientX);
      const end = () => { splitter.removeEventListener("pointermove", move); splitter.removeEventListener("pointerup", end); splitter.removeEventListener("pointercancel", end); };
      splitter.addEventListener("pointermove", move);
      splitter.addEventListener("pointerup", end);
      splitter.addEventListener("pointercancel", end);
    });
    document.getElementById("search-input").addEventListener("input", event => { state.queries[state.tab] = event.target.value; render(); });
    const switchView = view => {
      state.view = view;
      for (const control of document.querySelectorAll("[data-view]")) control.classList.toggle("active", control.dataset.view === view);
      for (const panel of document.querySelectorAll("[data-view-panel]")) panel.classList.toggle("active", panel.dataset.viewPanel === view);
      if (view === "plan") {
        renderPlan();
      } else if (view === "preview") {
        renderPreview();
      }
      if (view === "catalog") for (const tree of trees.values()) tree.view.refreshLayout();
      syncAssistance();
    };
    for (const control of document.querySelectorAll("[data-view]")) control.addEventListener("click", () => switchView(control.dataset.view));
    document.getElementById("return-catalog-button").addEventListener("click", () => switchView("catalog"));
    document.querySelector(".ide-statusbar").addEventListener("click", event => {
      const navigation = event.target.closest("[data-status-navigation]")?.dataset.statusNavigation;
      if (!navigation) return;
      if (navigation === "plan" || navigation === "capacity") return switchView("plan");
      if (navigation === "preview") return switchView("preview");
      switchView("catalog");
      const tab = navigation === "excluded" ? "assessment-results" : navigation === "issues" ? "rule-issues" : "candidate-sources";
      document.querySelector(`[data-workspace-tab="${tab}"]`).click();
      if (["eligible", "mapped", "unmapped"].includes(navigation)) {
        state.queries[tab] = navigation === "eligible" ? "" : `status:${navigation}`;
        document.getElementById("search-input").value = state.queries[tab];
        render();
      }
      showPane(tab === "assessment-results" ? "assessment" : "source", false);
    });
    for (const button of document.querySelectorAll("[data-workspace-tab]")) {
      button.addEventListener("click", () => {
        state.tab = button.dataset.workspaceTab;
        document.getElementById("search-input").value = state.queries[state.tab];
        const searchLabel = state.tab === "candidate-sources" ? "Search sources, categories, or rules" : state.tab === "assessment-results" ? "Search assessment results" : "Search rule issues";
        document.getElementById("search-input").placeholder = searchLabel;
        document.getElementById("search-input").setAttribute("aria-label", searchLabel);
        for (const tab of document.querySelectorAll("[data-workspace-tab]")) {
          const selected = tab === button;
          tab.classList.toggle("active", selected);
          tab.setAttribute("aria-selected", String(selected));
          const panel = document.getElementById(tab.getAttribute("aria-controls"));
          panel.hidden = !selected;
          panel.classList.toggle("active", selected);
        }
        for (const tree of trees.values()) tree.view.refreshLayout();
        syncAssistance();
      });
    }
    for (const button of document.querySelectorAll("[data-candidate-pane], [data-assessment-pane]")) {
      button.addEventListener("click", () => showPane(button.dataset.assessmentPane ? "assessment" : "source", (button.dataset.assessmentPane || button.dataset.candidatePane) === "details"));
    }
    document.addEventListener("keydown", event => {
      const row = event.target.closest('[data-native-record][role="button"]');
      if (row === event.target && (event.key === "Enter" || event.key === " ")) { event.preventDefault(); row.click(); }
    });
    document.addEventListener("click", event => {
      const sortControl = event.target.closest("[data-native-sort]");
      if (sortControl) {
        const plan = sortControl.dataset.nativePlanSort === "true";
        const key = sortControl.dataset.nativeSection;
        const current = plan ? state.planSort : state.sorts.get(key) ?? { field: "candidate", direction: "ascending" };
        const sort = { field: sortControl.dataset.nativeSort, direction: current.field === sortControl.dataset.nativeSort && current.direction === "ascending" ? "descending" : "ascending" };
        if (plan) { state.planSort = sort; renderPlan(); }
        else { state.sorts.set(key, sort); for (const tree of trees.values()) tree.view.refresh(); syncSelection(); }
        return;
      }
      const button = event.target.closest("[data-native-record]");
      if (!button) return;
      const kind = button.dataset.nativeKind;
      const records = kind === "protected" ? state.workspace.currentProtectedSnapshot?.rules ?? [] : kind === "assessment" ? assessmentRecords() : state.workspace.sources;
      const record = records.find(item => String(kind === "protected" ? item.ruleVersionId : kind === "assessment" ? item.assessmentResultId : item.sourceVersionId) === button.dataset.nativeRecord);
      if (record) showDetail(record, kind);
    });
    document.getElementById("close-button").addEventListener("click", closeWorkbench);
    await checkIconPaint();
    document.documentElement.dataset.nativeWorkbenchReady = "true";
  }

  function renderPlan() {
    const body = document.getElementById("plan-table-body");
    body.replaceChildren();
    const collator = new Intl.Collator(undefined, { numeric: true, sensitivity: "base" });
    const value = item => state.planSort.field === "candidate" ? item.sourceId : state.planSort.field === "source" ? item.sourceDefinitionId
      : state.planSort.field === "action" ? item.action : state.planSort.field === "readiness" ? item.needsReview ? "Saved wording changed" : "Review required" : "";
    const items = [...(currentPlan()?.items ?? [])].sort((left, right) => {
      const compared = collator.compare(String(value(left) ?? ""), String(value(right) ?? ""));
      return (state.planSort.direction === "ascending" ? compared : -compared) || collator.compare(left.sourceId, right.sourceId);
    });
    document.getElementById("empty-plan").hidden = items.length > 0;
    const columns = [["candidate", "Candidate", "Candidate"], ["source", "Source", "Source"], ["type", "Type", "Type"],
      ["action", "Action", "Action"], ["impact", "Impact", "Impact"], ["cost", "Draft Cost", "Draft Cost"], ["readiness", "Readiness", "Readiness"]];
    const header = element("tr");
    for (const column of columns) {
      const cell = element("th");
      cell.scope = "col";
      if (state.planSort.field === column[0]) cell.setAttribute("aria-sort", state.planSort.direction);
      cell.append(sortButton(column, state.planSort, "plan", true));
      header.append(cell);
    }
    const controls = element("th", "", "Controls");
    controls.scope = "col";
    header.append(controls);
    document.getElementById("plan-table-head").replaceChildren(header);
    for (const item of items) {
      const row = element("tr");
      for (const value of [item.sourceId, item.sourceDefinitionId, "Saved change", item.action || "Not selected", "--", "--", item.needsReview ? "Saved wording changed" : "Review required"]) row.append(element("td", "", value));
      const actions = element("td");
      const remove = element("button", "titlebar-icon clickable");
      remove.type = "button";
      remove.title = "Remove from Plan";
      remove.setAttribute("aria-label", `Remove ${item.sourceId} from Plan`);
      remove.append(icon("close"));
      remove.disabled = !state.capabilities.plan;
      remove.addEventListener("click", () => changePlan({ changeId: item.changeId,
        expectedRevisionId: state.workspace.changes.find(change => change.changeId === item.changeId)?.revisionId,
        expectedPlanVersionId: currentPlan().versionId, operation: "remove" }));
      actions.append(remove);
      row.append(actions);
      body.append(row);
    }
    renderCapacity();
  }

  function guidanceProjection() {
    const configuration = state.workspace.guidanceCapacity;
    const snapshot = state.workspace.publishedGuidance;
    const files = new Map((snapshot?.files ?? []).map(file => [file.bucketId, file]));
    const buckets = configuration.buckets.map(bucket => ({ ...bucket, current: files.get(bucket.bucketId)?.currentGuardedTokens ?? null }));
    const current = buckets.reduce((sum, bucket) => sum + (bucket.current ?? 0), 0);
    const budget = Math.min(configuration.policy.guidanceTokenBudget, buckets.reduce((sum, bucket) => sum + bucket.budgetTokens, 0));
    return { available: Boolean(snapshot?.available && buckets.every(bucket => bucket.current !== null)), current, budget,
      headroom: budget - current, buckets, emptyPlan: !(currentPlan()?.items.length) };
  }

  function capacityGroup(label, current, budget, overall = false) {
    const group = element("div", `capacity-group${overall ? " capacity-overall" : ""}`);
    const number = value => value.toLocaleString("en-US");
    const known = current !== null;
    const utilization = known ? Math.round(current / budget * 10000) / 100 : null;
    const top = element("div", "capacity-line");
    top.append(element("strong", "capacity-label", label), element("strong", "", known ? `${number(budget - current)} free` : "-- free"));
    const progress = element("progress", `capacity-progress${utilization > 85 ? " danger" : utilization > 65 ? " warning" : ""}`);
    progress.max = 100;
    progress.tabIndex = 0;
    if (known) progress.value = Math.min(100, utilization);
    progress.setAttribute("aria-label", known ? `${number(current)} current of ${number(budget)}` : `Usage unavailable; budget ${number(budget)}`);
    const bottom = element("div", "capacity-line");
    bottom.append(element("span", "", known ? `${number(current)} current + ${currentPlan()?.items.length ? "--" : "0"} draft` : `-- current of ${number(budget)}`),
      element("span", "", known ? `${utilization}%` : "--"));
    group.append(top, progress, bottom);
    return group;
  }

  function renderCapacity() {
    const panel = document.getElementById("capacity-panel");
    const projection = guidanceProjection();
    panel.replaceChildren(element("p", "eyebrow", "Plan projection"), element("h3", "", "Guidance Capacity"));
    panel.append(capacityGroup("Overall Hosted Guidance", projection.available ? projection.current : null, projection.budget, true));
    const estimate = element("div", "score-item");
    estimate.append(element("span", "", "Draft item estimate"), element("strong", "", projection.emptyPlan ? "0 tokens" : "-- tokens"));
    panel.append(estimate, element("span", "control-subtitle guidance-capacity-buckets", "Bucket Limits:"));
    for (const bucket of projection.buckets) panel.append(capacityGroup(bucket.label, bucket.current, bucket.budgetTokens));
    if (!state.workspace.publishedCatalog) {
      panel.append(element("p", "capacity-footnote", state.workspace.publishedGuidance?.available
        ? `Published repository catalog: ${state.workspace.publishedGuidance.catalogRuleCount} rules. This SQL workspace has not imported its baseline.`
        : "Published guidance files could not be read."));
    }
    if (!projection.emptyPlan) panel.append(element("p", "capacity-footnote", "Draft projection requires the exact rendered Plan output."));
  }

  start().catch(() => {
    status("SQL workspace unavailable");
    empty(document.getElementById("candidate-list"), "Selected workspace could not be loaded");
    document.documentElement.dataset.nativeWorkbenchReady = "failed";
  });
})();
