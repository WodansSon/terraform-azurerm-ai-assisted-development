const { openWorkbench } = require("../helpers/workbench.cjs");

const behaviorIds = [
  "WB-UX-PREVIEW-001",
  "WB-UX-PREVIEW-002",
  "WB-UX-PREVIEW-003",
  "WB-UX-PREVIEW-004",
  "WB-UX-PREVIEW-005",
  "WB-UX-PREVIEW-006",
  "WB-UX-PREVIEW-007",
  "WB-UX-PREVIEW-008",
  "WB-UX-PREVIEW-009",
  "WB-UX-PREVIEW-010",
  "WB-UX-PREVIEW-011",
  "WB-UX-PREVIEW-012",
  "WB-UX-PREVIEW-013",
  "WB-UX-PREVIEW-014",
  "WB-UX-PREVIEW-015",
  "WB-UX-PREVIEW-016"
];

async function inspectApprovalRequirements(page) {
  return page.evaluate(() => {
    const metadata = globalThis.__HOSTED_RULE_WORKBENCH__;
    const originalIdentity = metadata.maintainerIdentity;
    const originalName = state.session.approverName;
    const originalDecision = getDecision;
    const originalSort = state.planSort;
    try {
      state.session.approverName = "Synthetic unrelated typed name";
      const baseline = getPreviewReadiness();
      const approvedBy = buildApprovedRules().approvedBy;
      const failures = [
        { status: "unavailable", login: null, isCodeOwner: false, reason: "Synthetic missing identity" },
        { status: "validated", login: "fixture-nonowner", isCodeOwner: false, reason: "Synthetic non-owner" },
        { status: "unavailable", login: "fixture-codeowner", isCodeOwner: true, reason: "Synthetic unverified identity" }
      ].map((identity) => {
        metadata.maintainerIdentity = identity;
        const readiness = getPreviewReadiness();
        return !readiness.ready && !readiness.approvalIdentity && buildApprovedRules() === null
          && getApprovalRequirements(readiness).find((item) => item.id === "identity").status === "failed";
      });
      metadata.maintainerIdentity = originalIdentity;
      const missing = { ...baseline, missingAssessmentCount: 1, ready: false };
      const missingRequirement = getApprovalRequirements(missing).find((item) => item.id === "assessments");
      const emptyRequirement = getApprovalRequirements({ ...baseline, planCandidates: [], missingAssessmentCount: 0 })
        .find((item) => item.id === "assessments");
      renderApprovalRequirements(missing);
      const error = document.querySelector('[data-approval-requirement="assessments"]');
      const description = document.getElementById(error.getAttribute("aria-describedby"));
      const fakeMissing = getApprovalRepairTarget("assessments", missing);
      const identity = document.querySelector('[data-approval-requirement="identity"]');
      const result = {
        noEditor: !document.getElementById("approver-name"),
        verifiedAttribution: approvedBy.type === "github-authenticated"
          && approvedBy.id === originalIdentity.login && approvedBy.displayName === originalIdentity.login,
        typedNameIgnored: baseline.approvalIdentity.login === originalIdentity.login,
        unauthorizedBlocked: failures.every(Boolean),
        rebuildHardError: missingRequirement.status === "failed" && missingRequirement.value === "Not available",
        emptyPlanNotHardError: emptyRequirement.status === "passed",
        rebuildNotNavigation: error.tagName !== "BUTTON" && !error.hasAttribute("data-approval-target") && fakeMissing === null,
        errorRed: getComputedStyle(error.querySelector("strong")).color === "rgb(255, 107, 107)"
          && getComputedStyle(error.querySelector("svg")).color === "rgb(255, 107, 107)",
        circledError: error.querySelector("use").getAttribute("href").endsWith("#codicon-error"),
        accessibleRecovery: error.tabIndex === 0 && description.textContent.includes("-Rebuild")
          && error.dataset.workbenchTooltip === description.textContent,
        identityWithoutAt: identity.querySelector("strong").textContent === originalIdentity.login,
        warningButtons: [...document.querySelectorAll("#approval-requirements .pending")]
          .every((row) => row.tagName === "BUTTON" && row.hasAttribute("data-approval-target")),
        passedNoninteractive: !document.querySelector("#approval-requirements button.passed")
      };
      state.planSort = { field: "candidate", direction: "ascending" };
      const ordered = sortPlanCandidates(baseline.planCandidates, state.planSort);
      if (ordered.length < 2) throw new Error("Readiness navigation fixture requires two complete Plan candidates");
      const overrides = new Map(ordered.slice(0, 2).map((candidate) => [candidate.key, { ...originalDecision(candidate), rationale: "" }]));
      getDecision = (candidate) => overrides.get(candidate.key) || originalDecision(candidate);
      const rationales = getApprovalRepairTarget("rationales", { ...baseline, planCandidates: [...ordered].reverse() });
      result.firstMissingRationale = rationales.candidate.key === ordered[0].key && rationales.selector.includes("rationale");
      overrides.forEach((decision) => { decision.action = ""; });
      const actions = getApprovalRepairTarget("rule-actions", { ...baseline, planCandidates: [...ordered].reverse() });
      result.firstMissingAction = actions.candidate.key === ordered[0].key && actions.selector.includes("action-options");
      result.noIdentityRepairShortcut = getApprovalRepairTarget("identity", baseline) === null;
      return result;
    } finally {
      getDecision = originalDecision;
      state.planSort = originalSort;
      metadata.maintainerIdentity = originalIdentity;
      state.session.approverName = originalName;
      renderPreview();
    }
  });
}

async function run({ page, baseUrl, assert }) {
  await page.emulateMedia({ reducedMotion: "no-preference" });
  await openWorkbench(page, baseUrl);
  assert(await page.evaluate(() => !matchMedia("(prefers-reduced-motion: reduce)").matches), "Preview journey requires normal motion");
  const pairedLines = await page.evaluate(() => {
    const file = createPreviewFile("paired-lines.txt", "Paired line changes", ["Before", "", "Old tail"], ["After", "", "New tail"]);
    const unchanged = createPreviewFile("unchanged.txt", "Unchanged", ["Same", ""], ["Same", ""]);
    return {
      additions: file.additions, deletions: file.deletions,
      blankContext: !file.rows[1].changed && file.rows[1].oldLine === 2 && file.rows[1].newLine === 2,
      unchanged: unchanged.additions === 0 && unchanged.deletions === 0
    };
  });
  assert(pairedLines.additions === 2 && pairedLines.deletions === 2 && pairedLines.blankContext && pairedLines.unchanged,
    "Shared diff counted paired blank context or unchanged wording as added and removed lines");
  const fixture = await page.evaluate(async () => {
    globalThis.__previewReviewSessionSnapshot = structuredClone(state.session);
    const selected = state.candidates.filter((candidate) => {
      const decision = defaultDecision(candidate);
      return getAllowedActions(candidate, decision.proposedText).some((action) => isPromotionAction(action));
    }).slice(0, 4);
    for (const candidate of selected) {
      const decision = defaultDecision(candidate);
      const allowed = getAllowedActions(candidate, decision.proposedText);
      const action = allowed.includes(candidate.assessment.recommendation) && isPromotionAction(candidate.assessment.recommendation)
        ? candidate.assessment.recommendation
        : allowed.find((item) => isPromotionAction(item));
      state.session.decisions[candidate.key] = {
        ...decision,
        action,
        rationale: `Review ${candidate.id} in the promotion preview.`,
        ...createPlanMembership("manual"),
        sourceHash: candidate.hash,
        updatedAt: new Date().toISOString()
      };
    }
    state.session.approverName = "fixture-codeowner";
    state.session.updatedAt = new Date().toISOString();
    refreshEffectiveCandidates();
    await persistSession();
    renderAll();
    switchView("preview");
    return {
      selectedCount: selected.length,
      mutations: buildApprovedRules().mutations.map((mutation) => ({
        action: mutation.action,
        status: mutation.rule.status,
        retirementReason: mutation.rule.retirementReason,
        lastPlacement: mutation.rule.lastPlacement,
        placementCount: mutation.placements.length
      }))
    };
  });
  assert(fixture.selectedCount === 4, "Preview fixture did not create four reviewable plan items");
  const retireMutation = fixture.mutations.find((mutation) => mutation.action === "retire");
  assert(retireMutation?.status === "retired" && retireMutation.retirementReason && retireMutation.lastPlacement && retireMutation.placementCount === 0, "Approved Retire mutation does not preserve retirement history while clearing active placement");

  const approvalStatus = await page.evaluate(() => {
    let owner = document.querySelector("#preview-status").closest(".status-item");
    const originalRuleIssueBundle = state.ruleIssueBundle;
    const originalRuleIssues = state.ruleIssues;
    const blockedColor = getComputedStyle(owner).color;
    const blockedWidth = owner.getBoundingClientRect().width;
    const expectedBlockedColor = getComputedStyle(document.documentElement).getPropertyValue("--red").trim();
    const expectedWidth = Number.parseFloat(getComputedStyle(document.documentElement).getPropertyValue("--status-promotion-approval-width"));
    const blockedRequirement = [...document.querySelectorAll("#approval-requirements .approval-requirement")]
      .find((row) => row.querySelector("span")?.textContent === "Rule Issues");
    const blockedValid = owner.classList.contains("error-kind")
      && document.querySelector("#preview-status").textContent === "Blocked"
      && document.querySelector("#approve-export-button").disabled
      && document.querySelector("#approval-badge").textContent === "Blocked by Rule Issues"
      && owner.dataset.workbenchTooltip === "Promotion Approval Status"
      && blockedRequirement?.querySelector("strong")?.textContent === `${getOpenRuleIssues().length} pending`
      && blockedRequirement?.querySelector("use")?.getAttribute("href").endsWith("#codicon-warning");
    const blockedDetails = {
      className: owner.className, badge: document.querySelector("#approval-badge").textContent,
      tooltip: owner.dataset.workbenchTooltip, requirement: blockedRequirement?.querySelector("strong")?.textContent,
      icon: blockedRequirement?.querySelector("use")?.getAttribute("href")
    };
    state.ruleIssueBundle = { ...originalRuleIssueBundle, issues: [] };
    validateRuleIssueBundle(state.ruleIssueBundle);
    state.ruleIssues = structuredClone(state.ruleIssueBundle.issues);
    renderPreview();
    owner = document.querySelector("#preview-status").closest(".status-item");
    const readyColor = getComputedStyle(owner).color;
    const readyWidth = owner.getBoundingClientRect().width;
    const expectedReadyColor = getComputedStyle(document.documentElement).getPropertyValue("--success").trim();
    const readyValid = owner.classList.contains("success-kind")
      && document.querySelector("#preview-status").textContent === "Ready"
      && !document.querySelector("#approve-export-button").disabled;
    const readyDetails = getPreviewReadiness();
    const approvalIdentity = globalThis.__HOSTED_RULE_WORKBENCH__.maintainerIdentity;
    globalThis.__HOSTED_RULE_WORKBENCH__.maintainerIdentity = {
      status: "unavailable", login: null, isCodeOwner: false, reason: "Synthetic unavailable identity"
    };
    renderPreview();
    owner = document.querySelector("#preview-status").closest(".status-item");
    const draftColor = getComputedStyle(owner).color;
    const draftWidth = owner.getBoundingClientRect().width;
    const expectedDraftColor = getComputedStyle(document.documentElement).getPropertyValue("--warning-foreground").trim();
    const draftValid = owner.classList.contains("warning-kind") && document.querySelector("#preview-status").textContent === "Draft";
    globalThis.__HOSTED_RULE_WORKBENCH__.maintainerIdentity = approvalIdentity;
    state.ruleIssueBundle = originalRuleIssueBundle;
    state.ruleIssues = originalRuleIssues;
    renderPreview();
    return {
      blockedValid,
      blockedDetails,
      readyDetails: Object.fromEntries(Object.entries(readyDetails).filter(([key]) => key !== "planCandidates")),
      blockedColor,
      blockedWidth,
      expectedBlockedColor,
      expectedWidth,
      readyValid,
      readyColor,
      readyWidth,
      expectedReadyColor,
      draftValid,
      draftColor,
      draftWidth,
      expectedDraftColor
    };
  });
  assert(approvalStatus.blockedValid && approvalStatus.blockedColor === "rgb(255, 107, 107)" && approvalStatus.expectedBlockedColor === "#ff6b6b", `Blocked Preview status does not expose pending Rule Issues in red (${JSON.stringify(approvalStatus)})`);
  assert(approvalStatus.readyValid && approvalStatus.readyColor === "rgb(97, 226, 148)" && approvalStatus.expectedReadyColor === "#61e294", `Ready Preview status is not green (${JSON.stringify(approvalStatus)})`);
  assert(approvalStatus.draftValid && approvalStatus.draftColor === "rgb(229, 186, 125)" && approvalStatus.expectedDraftColor === "#e5ba7d", `Draft Preview status is not amber (${JSON.stringify(approvalStatus)})`);
  assert(approvalStatus.expectedWidth === 72 && [approvalStatus.blockedWidth, approvalStatus.readyWidth, approvalStatus.draftWidth].every((width) => width === approvalStatus.expectedWidth), `Promotion approval status geometry changed between Blocked, Ready, and Draft (${JSON.stringify(approvalStatus)})`);

  const approvalRequirements = await inspectApprovalRequirements(page);
  assert(Object.values(approvalRequirements).every(Boolean), `Approval identity or three-state requirements regressed: ${JSON.stringify(approvalRequirements)}`);

  const expectedIssue = await page.evaluate(() => getApprovalRepairTarget("rule-issues").issue.id);
  await page.locator("#preview-review-toggle").click();
  await page.locator('[data-approval-target="rule-issues"]').focus();
  await page.keyboard.press("Enter");
  await page.waitForFunction((id) => state.workspaceTab === "rule-issues" && state.activeRuleIssueKey === id
    && document.activeElement?.dataset.ruleIssueKey === id, expectedIssue);
  assert(await page.locator("#preview-review-popover").isHidden(), "Warning navigation did not close Review Changes");
  await page.locator('[data-view="preview"]').click();
  await page.locator("#preview-review-toggle").click();
  assert(await page.locator('[data-approval-target="rule-issues"]').isVisible(), "Correction buttons did not survive view navigation");
  await page.locator("#preview-review-close").click();

  const wordingProbe = await page.evaluate(() => {
    const candidate = sortPlanCandidates(getPlanCandidates(), state.planSort)[0];
    setWorkspaceTab("candidate-sources");
    selectCandidate(candidate.key);
    switchView("catalog");
    showCandidatePane("details");
    return { key: candidate.key, original: getDecision(candidate).proposedText, session: JSON.stringify(state.session) };
  });
  const draftWording = `${wordingProbe.original} Synthetic unsaved wording for navigation coverage.`;
  await page.locator('#assessment-panel [data-decision-field="proposedText"]').fill(draftWording);
  await page.locator('[data-view="preview"]').click();
  await page.locator("#preview-review-toggle").click();
  await page.locator('[data-approval-target="rule-issues"]').click();
  assert(await page.locator("#preview-review-popover").isVisible(), "A different warning discarded unsaved wording or navigated without guarding it");
  await page.locator('[data-approval-target="wording"]').click();
  assert(await page.locator('#assessment-panel [data-decision-field="proposedText"]').inputValue() === draftWording,
    "Unsaved-wording correction navigation lost the editor buffer");
  const wordingPreserved = await page.evaluate((probe) => state.activeKey === probe.key
    && document.activeElement?.dataset.decisionField === "proposedText" && JSON.stringify(state.session) === probe.session, wordingProbe);
  assert(wordingPreserved, "Correction navigation changed saved decisions or failed to focus the unsaved editor");
  await page.locator('#assessment-panel [data-decision-field="proposedText"]').fill(wordingProbe.original);
  await page.locator('[data-view="preview"]').click();

  const reviewModel = await page.evaluate(() => {
    const layout = document.querySelector("#preview-view .preview-layout");
    const view = document.querySelector("#preview-view");
    const toolbar = document.querySelector(".preview-review-toolbar");
    const scroller = document.querySelector("#preview-code");
    const splitter = document.querySelector("#preview-tree-resizer");
    const files = [...document.querySelectorAll(".preview-code [data-preview-file-path]")];
    const fileModels = Object.values(previewFilesByScope).flat();
    const changedFileModels = fileModels.filter((file) => !file.reference);
    const first = files[0];
    const rows = [...document.querySelectorAll(".preview-split-row")];
    const gaps = files.slice(0, -1).map((file, index) => Math.round(files[index + 1].getBoundingClientRect().top - file.getBoundingClientRect().bottom));
    const treeIcons = Object.entries(previewFilesByScope).flatMap(([scope, scopeFiles]) => scopeFiles.filter((file) => !file.reference).map((file) => {
      const button = document.querySelector(`[data-preview-artifact-file-scope="${scope}"][data-preview-file-jump="${CSS.escape(file.path)}"]`);
      const status = file.additions > 0 && file.deletions === 0 ? "added" : file.deletions > 0 && file.additions === 0 ? "removed" : "modified";
      return {
        expected: `#octicon-file-${status === "modified" ? "diff" : status}-16`,
        href: button?.querySelector(":scope > .octicon use")?.getAttribute("href")
      };
    }));
    const folderIcons = [...document.querySelectorAll("[data-preview-artifact-scope]")].map((button) => button.querySelector(".preview-folder-buffer .buffer-open use")?.getAttribute("href"));
    const treeStatuses = [...document.querySelectorAll(".preview-tree-file-icon:not(.protected)")].map((icon) => ({ label: icon.getAttribute("aria-label"), color: getComputedStyle(icon).color }));
    const protectedTreeIcons = [...document.querySelectorAll('.preview-tree-file-icon.protected use')].map((use) => use.getAttribute("href"));
    const displayPaths = files.map((file) => ({
      internal: file.dataset.previewFilePath,
      display: file.dataset.previewFileDisplayPath,
      heading: file.querySelector(".preview-file-path").textContent,
      copy: file.querySelector("[data-preview-copy-path]").dataset.previewCopyPath
    }));
    const firstGap = Math.round(first.getBoundingClientRect().top - scroller.getBoundingClientRect().top);
    const fileHierarchy = files.map((file) => ({
      children: [...file.children].map((child) => child.className),
      bodyInsideHeader: Boolean(file.querySelector(".preview-file-heading-wrapper .preview-file-body"))
    }));
    const toolbarDiffstat = [...document.querySelectorAll("#preview-review-context > .preview-diff-stat i")].map((cell) => cell.className);
    return {
      scopeControlAbsent: !document.querySelector("#preview-review-scope"),
      sidebarHeadingAbsent: !document.querySelector(".preview-sidebar-title"),
      parentCount: document.querySelectorAll("[data-preview-artifact-scope]").length,
      sidebarFiles: document.querySelectorAll("#preview-summary [data-preview-file-jump]").length,
      fileCount: files.length,
      proposedFiles: document.querySelectorAll(".preview-proposed-review [data-preview-file-path]").length,
      payloadFiles: document.querySelectorAll(".payload-review [data-preview-file-path]").length,
      rawFiles: document.querySelectorAll(".preview-raw-payload [data-preview-file-path]").length,
      protectedFiles: document.querySelectorAll(".preview-protected-rules [data-preview-file-path]").length,
      columns: getComputedStyle(layout).gridTemplateColumns,
      viewChildren: [...view.children].map((child) => child.className),
      layoutChildren: [...layout.children].map((child) => child.className),
      codeChildren: [...scroller.children].map((child) => child.className),
      codeOverflow: getComputedStyle(scroller).overflow,
      codeContainment: getComputedStyle(scroller).contain,
      splitLabels: document.querySelectorAll(".preview-split-labels").length,
      lineNumberWidth: first?.querySelector(".preview-line-number")?.getBoundingClientRect().width || 0,
      splitColumns: rows[0] ? getComputedStyle(rows[0]).gridTemplateColumns.split(" ").map(parseFloat) : [],
      withinViewport: files.every((file) => file.getBoundingClientRect().right <= innerWidth),
      noHorizontalOverflow: files.every((file) => file.querySelector(".preview-file-body").scrollWidth === file.querySelector(".preview-file-body").clientWidth),
      allSectionsVisible: [...document.querySelectorAll(".preview-proposed-review, .payload-review, .preview-raw-payload, .preview-protected-rules")].every((section) => !section.hidden),
      uniformGaps: gaps.every((gap) => gap === 16),
      firstGap,
      sectionBordersAbsent: [...document.querySelectorAll(".preview-proposed-review, .payload-review, .preview-raw-payload")].every((section) => getComputedStyle(section).borderTopWidth === "0px"),
      topHunks: [...document.querySelectorAll(".preview-hunk-header use")].map((use) => use.getAttribute("href")),
      treeIcons,
      treeStatuses,
      protectedTreeIcons,
      folderIcons,
      displayPaths,
      fileHierarchy,
      toolbarHeight: toolbar.getBoundingClientRect().height,
      fileHeaderHeights: [...new Set(files.map((file) => file.querySelector(".preview-file-heading").getBoundingClientRect().height))],
      codeownerShields: document.querySelectorAll('.preview-review-status-icon use[href$="#octicon-shield-lock-16"]').length,
      viewedControls: [...document.querySelectorAll(".preview-viewed")].map((control) => ({ width: control.getBoundingClientRect().width, height: control.getBoundingClientRect().height })),
      toolbarText: document.querySelector("#preview-review-context").textContent.trim().replace(/\s+/g, " "),
      expectedToolbarText: `${changedFileModels.length} files changed+${changedFileModels.reduce((sum, file) => sum + file.additions, 0)}-${changedFileModels.reduce((sum, file) => sum + file.deletions, 0)}`,
      toolbarDiffstat,
      splitter: {
        role: splitter.getAttribute("role"),
        orientation: splitter.getAttribute("aria-orientation"),
        minimum: splitter.getAttribute("aria-valuemin"),
        maximum: splitter.getAttribute("aria-valuemax"),
        current: splitter.getAttribute("aria-valuenow"),
        width: splitter.getBoundingClientRect().width
      },
      initialExpansion: Object.fromEntries([...document.querySelectorAll("[data-preview-artifact-scope]")]
        .map((button) => [button.dataset.previewArtifactScope, button.getAttribute("aria-expanded") === "true"]))
    };
  });
  assert(reviewModel.scopeControlAbsent && reviewModel.sidebarHeadingAbsent && reviewModel.parentCount === 4, "Preview still exposes obsolete scope or sidebar-heading controls");
  assert(reviewModel.fileCount === 10 && reviewModel.sidebarFiles === 10 && reviewModel.proposedFiles === 4 && reviewModel.payloadFiles === 4 && reviewModel.rawFiles === 1 && reviewModel.protectedFiles === 1 && reviewModel.allSectionsVisible, `Preview does not preserve nine changed files plus one protected reference (${JSON.stringify(reviewModel)})`);
  assert(reviewModel.lineNumberWidth === 44 && reviewModel.splitLabels === 0 && reviewModel.withinViewport && reviewModel.noHorizontalOverflow, "Preview does not use GitHub split-diff geometry with wrapped content");
  assert(reviewModel.splitColumns.length === 2 && Math.abs(reviewModel.splitColumns[0] - reviewModel.splitColumns[1]) <= 1, "Preview split panes are not equal width");
  assert(reviewModel.firstGap === 16 && reviewModel.uniformGaps && reviewModel.sectionBordersAbsent, "Preview file spacing changes at the leading or artifact boundaries");
  assert(reviewModel.topHunks.length === 8 && reviewModel.topHunks.every((icon) => icon.endsWith("#octicon-kebab-horizontal-16")), "Top-file hunks do not use the local kebab-horizontal Octicon");
  assert(reviewModel.treeIcons.length === 9 && reviewModel.treeIcons.every((icon) => icon.href?.endsWith(icon.expected)), "Preview tree files do not use status-aware authenticated file icons");
  assert(reviewModel.treeStatuses.every((item) => ["Added", "Removed", "Modified"].includes(item.label)) && new Set(reviewModel.treeStatuses.map((item) => item.color)).size === 3, "Preview tree status icons do not retain distinct accessible states and colors");
  assert(reviewModel.protectedTreeIcons.length === 1 && reviewModel.protectedTreeIcons[0].endsWith("#octicon-shield-lock-16"), "Preview tree does not distinguish the protected reference file");
  assert(reviewModel.folderIcons.length === 4 && reviewModel.folderIcons.every((icon) => icon.endsWith("#octicon-file-directory-open-fill-16")), "Preview tree folders do not use the authenticated open-directory icon");
  assert(reviewModel.displayPaths.every((item) => item.display === item.heading && item.display === item.copy && item.display !== item.internal && /^[A-Z ]+\//.test(item.display)), "Preview file headers do not expose virtual artifact paths while preserving internal navigation identity");
  assert(reviewModel.fileHierarchy.every((item) => item.children.join(",") === "preview-file-heading-wrapper,preview-file-body" && !item.bodyInsideHeader), "Preview file cards do not own sibling sticky-header and diff-body containers");
  assert(reviewModel.viewChildren.join(",") === "page-heading,preview-review-toolbar,preview-layout" && reviewModel.layoutChildren.join(",") === "preview-summary scroll-surface type-ui,preview-tree-resizer,preview-code scroll-surface type-editor" && !reviewModel.codeChildren.includes("preview-review-toolbar"), "Preview toolbar, tree, and diff scroller do not retain independent layer ownership");
  assert(reviewModel.codeOverflow === "auto" && reviewModel.codeContainment === "paint", "Preview diff flow is not isolated inside its owned scroll surface");
  assert(Math.abs(reviewModel.toolbarHeight - 60) < 0.001 && reviewModel.fileHeaderHeights.length > 0
    && reviewModel.fileHeaderHeights.every(height => Math.abs(height - 42) < 0.001),
    `Preview toolbar or sticky file headers do not match authenticated GitHub geometry (toolbar=${reviewModel.toolbarHeight}, headers=${JSON.stringify(reviewModel.fileHeaderHeights)})`);
  assert(reviewModel.codeownerShields === 10 && reviewModel.viewedControls.length === 9 && reviewModel.viewedControls.every((control) => control.width === 77 && control.height === 28),
    `Preview file headers do not retain changed-file CODEOWNERS controls and the protected reference shield (shields=${reviewModel.codeownerShields}, controls=${JSON.stringify(reviewModel.viewedControls)})`);
  const expectedInitialExpansion = { proposed: true, payload: true, raw: true, protected: true };
  assert(reviewModel.toolbarText === reviewModel.expectedToolbarText && reviewModel.toolbarDiffstat.length === 5 && reviewModel.toolbarDiffstat.includes("add") && reviewModel.toolbarDiffstat.includes("neutral") && JSON.stringify(reviewModel.initialExpansion) === JSON.stringify(expectedInitialExpansion), `Preview toolbar totals, diffstat, or initial tree expansion are not synchronized to changed and protected files (${JSON.stringify(reviewModel)})`);
  assert(reviewModel.splitter.role === "slider" && reviewModel.splitter.orientation === "vertical" && reviewModel.splitter.minimum === "296" && Number(reviewModel.splitter.maximum) >= Number(reviewModel.splitter.current) && reviewModel.splitter.width === 5, "Preview changed-file tree does not expose an accessible five-pixel splitter");

  const emptyProtectedScope = await page.evaluate(() => {
    const protectedRuleFiles = state.bundle.catalog.protectedRuleFiles;
    state.bundle.catalog.protectedRuleFiles = [];
    renderPreview();
    const result = {
      folderAbsent: !document.querySelector('[data-preview-artifact-group="protected"]'),
      treeFileAbsent: !document.querySelector('[data-preview-artifact-file-scope="protected"]'),
      sectionHidden: elements["preview-protected-section"].hidden,
      sectionEmpty: elements["preview-protected"].children.length === 0
    };
    state.bundle.catalog.protectedRuleFiles = protectedRuleFiles;
    renderPreview();
    return result;
  });
  assert(emptyProtectedScope.folderAbsent && emptyProtectedScope.treeFileAbsent && emptyProtectedScope.sectionHidden && emptyProtectedScope.sectionEmpty, `Empty Protected Rules scope remains visible (${JSON.stringify(emptyProtectedScope)})`);

  const firstFile = page.locator(".preview-proposed-review [data-preview-file-path]").first();
  await firstFile.locator("[data-preview-file-collapse]").click();
  assert(await firstFile.locator(".preview-file-body").isHidden(), "File collapse control does not hide the diff body");
  await firstFile.locator("[data-preview-file-collapse]").click();
  await firstFile.locator(".preview-viewed").click();
  const viewedCollapsed = await firstFile.evaluate((element) => ({
    viewed: element.classList.contains("viewed"),
    hidden: element.querySelector(".preview-file-body").hidden,
    expanded: element.querySelector("[data-preview-file-collapse]").getAttribute("aria-expanded"),
    chevron: element.querySelector("[data-preview-file-collapse] use")?.getAttribute("href"),
    pressed: element.querySelector(".preview-viewed").getAttribute("aria-pressed"),
    squareVisible: getComputedStyle(element.querySelector(".preview-viewed > .octicon:first-of-type")).display !== "none",
    checkedVisible: getComputedStyle(element.querySelector(".preview-viewed > .octicon:nth-of-type(2)")).display !== "none"
  }));
  assert(viewedCollapsed.viewed && viewedCollapsed.hidden && viewedCollapsed.expanded === "false" && viewedCollapsed.chevron.endsWith("#octicon-chevron-right-16") && viewedCollapsed.pressed === "true" && !viewedCollapsed.squareVisible && viewedCollapsed.checkedVisible, "Checking Viewed does not collapse an expanded file with the authenticated selected state");
  await firstFile.locator("[data-preview-file-collapse]").click();
  assert(await firstFile.evaluate((element) => element.classList.contains("viewed") && !element.querySelector(".preview-file-body").hidden && element.querySelector("[data-preview-file-collapse] use").getAttribute("href").endsWith("#octicon-chevron-down-16")), "Chevron does not reopen a Viewed file independently");
  await firstFile.locator(".preview-viewed").click();
  assert(await firstFile.evaluate((element) => !element.classList.contains("viewed") && !element.querySelector(".preview-file-body").hidden), "Unchecking Viewed changes the current disclosure state");
  await firstFile.locator("[data-preview-file-collapse]").click();
  await firstFile.locator(".preview-viewed").click();
  assert(await firstFile.evaluate((element) => element.classList.contains("viewed") && element.querySelector(".preview-file-body").hidden), "Checking Viewed changes an already collapsed file incorrectly");
  await firstFile.locator(".preview-viewed").click();
  assert(await firstFile.locator(".preview-file-body").isHidden(), "Unchecking Viewed expands a collapsed file");
  await firstFile.locator("[data-preview-file-collapse]").click();
  await firstFile.locator(".preview-viewed").click();
  const firstFilePath = await firstFile.getAttribute("data-preview-file-path");
  const firstTreeItem = page.locator(`[data-preview-file-jump="${firstFilePath}"]`);
  assert(await firstFile.evaluate((element) => element.classList.contains("viewed") && element.querySelector(".preview-file-body").hidden) && await firstTreeItem.getAttribute("aria-expanded") === null, "Viewed does not leave the file collapsed with navigation-only tree semantics");
  await firstTreeItem.click();
  assert(await firstFile.evaluate((element) => element.classList.contains("viewed") && element.querySelector(".preview-file-body").hidden), "Tree navigation changes a collapsed Viewed file card");
  await firstFile.locator("[data-preview-file-collapse]").click();
  await firstTreeItem.click();
  assert(await firstFile.evaluate((element) => element.classList.contains("viewed") && !element.querySelector(".preview-file-body").hidden), "Tree navigation changes an expanded Viewed file card");
  await firstFile.locator(".preview-viewed").click();

  const parentDisclosure = await page.evaluate(async () => {
    const scroller = document.querySelector("#preview-code");
    const parent = document.querySelector('[data-preview-artifact-scope="payload"]');
    const selected = document.querySelector("[data-preview-file-jump].active")?.dataset.previewFileJump;
    scroller.scrollTop = 120;
    const before = { scrollTop: scroller.scrollTop, selected, payload: parent.getAttribute("aria-expanded"), proposed: document.querySelector('[data-preview-artifact-scope="proposed"]').getAttribute("aria-expanded"), raw: document.querySelector('[data-preview-artifact-scope="raw"]').getAttribute("aria-expanded") };
    parent.click();
    await new Promise(requestAnimationFrame);
    const collapsed = { scrollTop: scroller.scrollTop, selected: document.querySelector("[data-preview-file-jump].active")?.dataset.previewFileJump, expanded: document.querySelector('[data-preview-artifact-scope="payload"]').getAttribute("aria-expanded"), activeParents: document.querySelectorAll("[data-preview-artifact-scope].active").length };
    document.querySelector('[data-preview-artifact-scope="payload"]').click();
    await new Promise(requestAnimationFrame);
    const expanded = { scrollTop: scroller.scrollTop, selected: document.querySelector("[data-preview-file-jump].active")?.dataset.previewFileJump, expanded: document.querySelector('[data-preview-artifact-scope="payload"]').getAttribute("aria-expanded"), proposed: document.querySelector('[data-preview-artifact-scope="proposed"]').getAttribute("aria-expanded"), raw: document.querySelector('[data-preview-artifact-scope="raw"]').getAttribute("aria-expanded") };
    return { before, collapsed, expanded };
  });
  assert(parentDisclosure.collapsed.expanded !== parentDisclosure.before.payload && parentDisclosure.expanded.expanded === parentDisclosure.before.payload, `Artifact parent does not independently toggle and restore its children (${JSON.stringify(parentDisclosure)})`);
  assert(parentDisclosure.before.scrollTop === parentDisclosure.collapsed.scrollTop && parentDisclosure.collapsed.scrollTop === parentDisclosure.expanded.scrollTop, "Artifact parent changes the review scroll position");
  assert(parentDisclosure.before.selected === parentDisclosure.collapsed.selected && parentDisclosure.collapsed.selected === parentDisclosure.expanded.selected && parentDisclosure.collapsed.activeParents === 0, "Artifact parent changes or duplicates file selection");
  assert(parentDisclosure.before.proposed === parentDisclosure.expanded.proposed && parentDisclosure.before.raw === parentDisclosure.expanded.raw, "Artifact parent changes sibling expansion state");

  const selectedPath = await page.evaluate(() => previewFilesByScope.payload[1].path);
  await page.locator(`[data-preview-file-jump="${selectedPath}"]`).click();
  await page.waitForFunction((path) => {
    const file = document.querySelector(`[data-preview-file-path="${CSS.escape(path)}"]`);
    const scroller = document.querySelector("#preview-code");
    return file && Math.abs(file.getBoundingClientRect().top - scroller.getBoundingClientRect().top - parseFloat(getComputedStyle(file).scrollMarginTop)) <= 1;
  }, selectedPath);
  const persistentSelection = await page.evaluate(async (path) => {
    const scroller = document.querySelector("#preview-code");
    const rawFile = document.querySelector('[data-preview-file-path="approval/approved-rules.json"]');
    const selectedAfterClick = document.querySelector("[data-preview-file-jump].active")?.dataset.previewFileJump;
    rawFile.scrollIntoView({ block: "start", behavior: "auto" });
    scroller.scrollTop += 180;
    await new Promise((resolve) => requestAnimationFrame(() => requestAnimationFrame(resolve)));
    return {
      selectedAfterClick,
      selectedAfterScroll: document.querySelector("[data-preview-file-jump].active")?.dataset.previewFileJump,
      activeCount: document.querySelectorAll("[data-preview-file-jump].active").length,
      activeParents: document.querySelectorAll("[data-preview-artifact-scope].active").length,
      rawSticky: Math.abs(rawFile.querySelector(".preview-file-heading-wrapper").getBoundingClientRect().top - document.querySelector("#preview-code").getBoundingClientRect().top + 2) <= 1,
      visibleFiles: document.querySelectorAll(".preview-code [data-preview-file-path]").length,
      expected: path
    };
  }, selectedPath);
  assert(persistentSelection.selectedAfterClick === selectedPath && persistentSelection.selectedAfterScroll === selectedPath && persistentSelection.activeCount === 1 && persistentSelection.activeParents === 0, "Preview tree selection does not remain on the last explicitly selected file");
  assert(persistentSelection.rawSticky && persistentSelection.visibleFiles === 10, "Continuous review does not keep the current file header sticky while all changed and protected files remain mounted");

  const raw = await page.evaluate(() => {
    const file = document.querySelector(".preview-raw-payload [data-preview-file-path]");
    const controls = [...file.querySelectorAll("[data-preview-context-direction]")];
    return {
      fileCount: document.querySelectorAll(".preview-raw-payload [data-preview-file-path]").length,
      path: file.dataset.previewFilePath,
      displayPath: file.dataset.previewFileDisplayPath,
      nestedSections: file.querySelectorAll("details").length,
      controls: controls.map((button) => ({ label: button.getAttribute("aria-label"), icon: button.querySelector("use")?.getAttribute("href") })),
      gapCount: file.querySelectorAll("[data-preview-context-gap]").length,
      contextLineCount: PREVIEW_CONTEXT_LINE_COUNT,
      expanderWidth: controls[0].getBoundingClientRect().width,
      lineNumberWidth: file.querySelector(".preview-line-number").getBoundingClientRect().width,
      splitLabels: file.querySelectorAll(".preview-split-labels").length,
      linesToggle: {
        label: file.querySelector("[data-preview-lines-toggle]").getAttribute("aria-label"),
        pressed: file.querySelector("[data-preview-lines-toggle]").getAttribute("aria-pressed"),
        icon: file.querySelector("[data-preview-lines-toggle] use").getAttribute("href")
      }
    };
  });
  assert(raw.fileCount === 1 && raw.path === "approval/approved-rules.json" && raw.nestedSections === 0, "Raw review is not one complete approved-rules.json file");
  assert(raw.contextLineCount === 2 && raw.gapCount > 0 && raw.splitLabels === 0, "Raw review does not collapse unchanged ranges around two context lines");
  assert(raw.expanderWidth === raw.lineNumberWidth, "Raw context expander does not match the line-number gutter width");
  assert(raw.controls.some((control) => control.label === "Expand Up" && control.icon.endsWith("#octicon-fold-up-16")), "Raw review does not use the local Fold Up Octicon");
  const expectedControlIcons = { "Expand Up": "#octicon-fold-up-16", "Expand All": "#octicon-unfold-16", "Expand Down": "#octicon-fold-down-16" };
  assert(raw.controls.every((control) => control.icon.endsWith(expectedControlIcons[control.label])), "Raw review does not use the correct local Octicon for each available expansion direction");
  assert(raw.linesToggle.label === `Expand all lines: ${raw.displayPath}` && raw.linesToggle.pressed === "false" && raw.linesToggle.icon.endsWith("#octicon-unfold-16"), "Approved Rules review does not start with the file-level Expand all lines override");

  const directionalExpansion = await page.evaluate(async () => {
    const file = document.querySelector(".preview-raw-payload [data-preview-file-path]");
    const button = document.querySelector('[data-preview-context-direction="up"]');
    const gap = button.closest("[data-preview-context-gap]");
    const before = gap.querySelector("template").content.children.length;
    button.click();
    await new Promise((resolve) => requestAnimationFrame(() => requestAnimationFrame(resolve)));
    const linesToggle = file.querySelector("[data-preview-lines-toggle]");
    const expanded = {
      remaining: gap.querySelector("template").content.children.length,
      label: linesToggle.getAttribute("aria-label"),
      pressed: linesToggle.getAttribute("aria-pressed"),
      icon: linesToggle.querySelector("use").getAttribute("href")
    };
    linesToggle.click();
    return {
      before,
      expanded,
      restored: {
        gaps: file.querySelectorAll("[data-preview-context-gap]").length,
        label: linesToggle.getAttribute("aria-label"),
        pressed: linesToggle.getAttribute("aria-pressed"),
        icon: linesToggle.querySelector("use").getAttribute("href")
      }
    };
  });
  assert(directionalExpansion.before - directionalExpansion.expanded.remaining === Math.min(10, directionalExpansion.before), "Fold Up does not reveal the expected directional line count");
  assert(directionalExpansion.expanded.label === `Collapse all lines: ${raw.displayPath}` && directionalExpansion.expanded.pressed === "true" && directionalExpansion.expanded.icon.endsWith("#octicon-fold-16"), "Inline context expansion does not switch the file-level override to Collapse all lines");
  assert(directionalExpansion.restored.gaps === raw.gapCount && directionalExpansion.restored.label === raw.linesToggle.label && directionalExpansion.restored.pressed === "false" && directionalExpansion.restored.icon.endsWith("#octicon-unfold-16"), "File-level Collapse all lines does not restore the canonical compact view and Expand all lines state");

  await page.locator("#preview-review-toggle").click();
  const review = await page.evaluate(() => ({
    visible: !document.querySelector("#preview-review-popover").hidden,
    approval: Boolean(document.querySelector("#preview-review-popover #approve-export-button")),
    approver: Boolean(document.querySelector("#preview-review-popover #approver-name")),
    identity: document.querySelector('[data-approval-requirement="identity"] strong')?.textContent
  }));
  assert(review.visible && review.approval && !review.approver && review.identity === "fixture-codeowner", "Review changes does not expose the verified-identity approval workflow");
  const reviewLayout = await page.evaluate(() => {
    const popover = document.getElementById("preview-review-popover");
    const header = popover.querySelector(".preview-review-popover-heading");
    const requirements = document.getElementById("approval-requirements");
    const footer = popover.querySelector(".preview-approval-actions");
    const button = document.getElementById("approve-export-button");
    const popoverBounds = popover.getBoundingClientRect();
    const headerBounds = header.getBoundingClientRect();
    const title = header.querySelector("strong").getBoundingClientRect();
    const close = header.querySelector("button").getBoundingClientRect();
    const balanced = (bounds) => Math.abs((bounds.top - popoverBounds.top) - (headerBounds.bottom - bounds.bottom)) < 1;
    const ownsDivider = () => {
      const style = getComputedStyle(footer);
      return style.borderTopStyle === "solid" && parseFloat(style.borderTopWidth) > 0
        && style.borderTopColor === getComputedStyle(requirements.lastElementChild).borderTopColor
        && parseFloat(getComputedStyle(requirements.lastElementChild).borderBottomWidth) === 0;
    };
    const originalGap = footer.getBoundingClientRect().top - requirements.getBoundingClientRect().bottom;
    const originalWidth = button.getBoundingClientRect().width;
    const originalDisabled = button.disabled;
    const extraRequirement = requirements.lastElementChild.cloneNode(true);
    let independentOfRowCount;
    requirements.appendChild(extraRequirement);
    try {
      independentOfRowCount = ownsDivider()
        && Math.abs((footer.getBoundingClientRect().top - requirements.getBoundingClientRect().bottom) - originalGap) < 1;
    } finally {
      extraRequirement.remove();
    }
    return {
      titleBalanced: balanced(title),
      closeBalanced: balanced(close),
      commonCenter: Math.abs((title.top + title.bottom) / 2 - (close.top + close.bottom) / 2) < 1,
      footerOwnsButton: footer.contains(button) && requirements.nextElementSibling === footer,
      footerOwnsDivider: ownsDivider(),
      independentOfRowCount,
      restoredGap: Math.abs((footer.getBoundingClientRect().top - requirements.getBoundingClientRect().bottom) - originalGap) < 1,
      buttonUnchanged: button.disabled === originalDisabled && Math.abs(button.getBoundingClientRect().width - originalWidth) < 1
    };
  });
  assert(reviewLayout.titleBalanced && reviewLayout.closeBalanced && reviewLayout.commonCenter,
    "Review Changes title and close icon do not have balanced vertical spacing");
  assert(reviewLayout.footerOwnsButton && reviewLayout.footerOwnsDivider && reviewLayout.independentOfRowCount
    && reviewLayout.restoredGap && reviewLayout.buttonUnchanged,
    "Approval action footer does not own a stable top divider independently of the requirement rows");
  await page.evaluate(() => renderPreview());
  assert(await page.locator("#preview-review-popover").isVisible(), "Ordinary Preview rendering dismissed Review Changes");
  await page.locator(".preview-review-popover-heading strong").click();
  assert(await page.locator("#preview-review-popover").isVisible(), "An inside click dismissed Review Changes");
  await page.mouse.move(8, 8);
  assert(await page.locator("#preview-review-popover").isVisible(), "Pointer leave dismissed Review Changes");
  await page.locator(".preview-review-popover-heading").hover();
  await page.mouse.wheel(0, 80);
  assert(await page.locator("#preview-review-popover").isVisible(), "Scrolling inside Review Changes dismissed it");
  await page.evaluate(async () => {
    document.getElementById("preview-code").scrollTop = 0;
    await new Promise((resolve) => requestAnimationFrame(() => requestAnimationFrame(resolve)));
  });
  assert(await page.locator("#preview-review-popover").isVisible(), "Programmatic diff scrolling dismissed Review Changes");
  const outsideCollapse = page.locator("#preview-code [data-preview-file-collapse]").first();
  const originalExpanded = await outsideCollapse.getAttribute("aria-expanded");
  await outsideCollapse.click();
  assert(await page.locator("#preview-review-popover").isHidden(), "An outside click did not dismiss Review Changes");
  assert(await outsideCollapse.getAttribute("aria-expanded") !== originalExpanded,
    "Outside dismissal swallowed the diff collapse action");
  await outsideCollapse.click();
  assert(await outsideCollapse.getAttribute("aria-expanded") === originalExpanded,
    "The outside-click regression did not restore the original diff state");
  await page.locator("#preview-review-toggle").click();
  const scrollPoint = await page.evaluate(() => {
    const scroller = document.getElementById("preview-code");
    scroller.scrollTop = 0;
    const bounds = scroller.getBoundingClientRect();
    return { x: bounds.left + 20, y: Math.min(bounds.bottom - 24, innerHeight - 40) };
  });
  await page.mouse.move(scrollPoint.x, scrollPoint.y);
  assert(await page.locator("#preview-review-popover").isVisible(), "Pointer movement outside dismissed Review Changes");
  await page.mouse.wheel(0, 180);
  await page.waitForFunction(() => document.getElementById("preview-code").scrollTop > 0);
  assert(await page.locator("#preview-review-popover").isHidden(), "Outside wheel scrolling did not dismiss Review Changes");
  await page.locator("#preview-review-toggle").click();
  const originalTabIndex = await page.locator("#preview-code").getAttribute("tabindex");
  await page.locator("#preview-code").evaluate((node) => { node.tabIndex = 0; node.focus({ preventScroll: true }); });
  await page.keyboard.press("PageDown");
  assert(await page.locator("#preview-review-popover").isHidden(), "Outside keyboard scrolling did not dismiss Review Changes");
  await page.locator("#preview-code").evaluate((node, value) => {
    if (value === null) node.removeAttribute("tabindex");
    else node.setAttribute("tabindex", value);
  }, originalTabIndex);
  await page.locator("#preview-review-toggle").click();
  await page.keyboard.press("Escape");
  assert(await page.locator("#preview-review-popover").isHidden(), "Escape did not dismiss Review Changes");
  await page.locator("#preview-review-toggle").click();
  await page.locator("#preview-review-close").click();
  assert(await page.locator("#preview-review-popover").isHidden(), "The close icon did not dismiss Review Changes");

  const virtualization = await page.evaluate(async () => {
    disconnectPreviewBodyVirtualizer();
    const cloneFile = (file, scope, index) => ({
      ...structuredClone(file),
      path: `${scope}/virtual-${String(index + 1).padStart(3, "0")}-${file.path.split("/").at(-1)}`,
      displayPath: `${PREVIEW_SCOPE_LABELS[scope].toUpperCase()}/virtual-${String(index + 1).padStart(3, "0")}-${file.path.split("/").at(-1)}`
    });
    previewFilesByScope = {
      proposed: Array.from({ length: 40 }, (_, index) => cloneFile(previewFilesByScope.proposed[index % previewFilesByScope.proposed.length], "proposed", index)),
      payload: Array.from({ length: 40 }, (_, index) => cloneFile(previewFilesByScope.payload[index % previewFilesByScope.payload.length], "payload", index)),
      raw: previewFilesByScope.raw.map((file, index) => cloneFile(file, "raw", index)),
      protected: previewFilesByScope.protected
    };
    elements["preview-diff"].innerHTML = renderPreviewFiles(previewFilesByScope.proposed, "", "");
    elements["preview-payload-diff"].innerHTML = renderPreviewFiles(previewFilesByScope.payload, "", "");
    elements["preview-json"].innerHTML = renderPreviewFiles(previewFilesByScope.raw, "", "");
    renderPreviewReview();
    const scroller = elements["preview-code"];
    const fullScrollHeight = scroller.scrollHeight;
    const fullNodeCount = scroller.querySelectorAll("*").length;
    initializePreviewBodyVirtualizer();
    const virtualizedCount = scroller.querySelectorAll('[data-preview-virtualized="true"]').length;
    const mountedNodeCount = scroller.querySelectorAll("*").length;
    const farPath = previewFilesByScope.payload.at(-1).path;
    elements["preview-summary"].querySelector(`[data-preview-file-jump="${CSS.escape(farPath)}"]`).click();
    const farFile = scroller.querySelector(`[data-preview-file-path="${CSS.escape(farPath)}"]`);
    const farHydratedImmediately = farFile.querySelector(".preview-file-body").dataset.previewVirtualized !== "true";
    await new Promise((resolve) => requestAnimationFrame(() => requestAnimationFrame(resolve)));
    const farHydrated = farFile.querySelector(".preview-file-body").dataset.previewVirtualized !== "true";
    const scrollHeightAfterNavigation = scroller.scrollHeight;
    elements["preview-tree-resizer"].dispatchEvent(new KeyboardEvent("keydown", { key: "ArrowRight", bubbles: true }));
    await new Promise((resolve) => requestAnimationFrame(() => requestAnimationFrame(resolve)));
    const virtualizedAfterResize = scroller.querySelectorAll('[data-preview-virtualized="true"]').length;
    const renderedFileCount = scroller.querySelectorAll("[data-preview-file-path]").length;
    const fileCount = Object.values(previewFilesByScope).flat().length;
    renderPreview();
    return {
      fileCount,
      renderedFileCount,
      fullScrollHeight,
      virtualizedScrollHeight: scrollHeightAfterNavigation,
      fullNodeCount,
      mountedNodeCount,
      virtualizedCount,
      farHydratedImmediately,
      farHydrated,
      virtualizedAfterResize
    };
  });
  assert(virtualization.renderedFileCount === virtualization.fileCount && virtualization.virtualizedCount > 0 && virtualization.mountedNodeCount < virtualization.fullNodeCount, `Large Preview did not virtualize off-screen file bodies (${JSON.stringify(virtualization)})`);
  assert(virtualization.virtualizedScrollHeight === virtualization.fullScrollHeight && virtualization.farHydratedImmediately
    && virtualization.farHydrated, `Virtualized Preview did not preserve exact scroll geometry or hydrate file navigation (${JSON.stringify(virtualization)})`);
  assert(virtualization.virtualizedAfterResize > 0, `Preview virtualization did not recover after keyboard splitter resizing (${JSON.stringify(virtualization)})`);

  await page.setViewportSize({ width: 768, height: 900 });
  const narrow = await page.evaluate(() => {
    const sidebar = document.querySelector("#preview-view .preview-summary").getBoundingClientRect();
    const preview = document.querySelector("#preview-view .preview-code").getBoundingClientRect();
    const layout = document.querySelector("#preview-view .preview-layout");
    return {
      columns: getComputedStyle(layout).gridTemplateColumns,
      stacked: sidebar.bottom <= preview.top + 1,
      contained: layout.scrollWidth === layout.clientWidth
    };
  });
  assert(narrow.stacked && narrow.contained, "Narrow Preview does not stack the file navigator above a contained review surface");

  await page.evaluate(async () => {
    state.session = globalThis.__previewReviewSessionSnapshot;
    delete globalThis.__previewReviewSessionSnapshot;
    refreshEffectiveCandidates();
    await persistSession();
    renderAll();
    switchView("catalog");
  });
}

module.exports = { name: "promotion preview review", behaviorIds, viewport: { width: 1440, height: 900 }, run };
