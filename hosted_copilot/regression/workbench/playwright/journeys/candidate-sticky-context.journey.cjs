const { openWorkbench } = require("../helpers/workbench.cjs");

const behaviorIds = [
  "WB-UX-STICKY-001",
  "WB-UX-STICKY-002",
  "WB-UX-STICKY-003",
  "WB-UX-STICKY-004",
  "WB-UX-STICKY-005",
  "WB-UX-STICKY-006",
  "WB-UX-STICKY-007",
  "WB-UX-STICKY-008",
  "WB-UX-STICKY-009",
  "WB-UX-STICKY-010",
  "WB-UX-STICKY-011"
];

async function settle(page) {
  await page.evaluate(() => new Promise((resolve) => requestAnimationFrame(() => requestAnimationFrame(resolve))));
}

async function run({ page, baseUrl, assert, playback }) {
  await openWorkbench(page, baseUrl);
  await playback.show(page, "Candidate tree sticky context");

  const initialParentState = await page.evaluate(() => {
    const sessionSnapshot = structuredClone(state.session);
    const candidate = state.assessedCandidates.find((item) => !item.assessment.hostedApplicable) || state.candidates[0];
    try {
      state.session.applicabilityOverrides[candidate.key] = {
        state: "provisional",
        sourceContentSha256: candidate.hash,
        originalHostedApplicable: false,
        effectiveHostedApplicable: true,
        rationale: "Playwright initial parent-state probe.",
        recordedAt: new Date().toISOString(),
        recordedBy: { type: "github-cli", login: "fixture-codeowner" }
      };
      refreshEffectiveCandidates();
      renderCandidateList();
      const overrideRoot = candidateHierarchicalView.model.nodesById.get("candidate:source:overrides");
      const parents = [];
      const visit = (node) => {
        if (["source", "folder"].includes(node.kind)) parents.push(node);
        node.children.forEach(visit);
      };
      visit(overrideRoot);
      return {
        allCollapsed: parents.every((node) => !node.expanded),
        noVisibleChildren: candidateHierarchicalView.model.visibleNodes.every((node) => node.parentId !== overrideRoot.id)
      };
    } finally {
      state.session = sessionSnapshot;
      refreshEffectiveCandidates();
      renderCandidateList();
    }
  });
  assert(initialParentState.allCollapsed && initialParentState.noVisibleChildren, "Candidate Sources parents do not start fully collapsed when Overrides is present");

  const initial = await page.evaluate(() => {
    const scroller = document.querySelector("#candidate-list");
    const rect = scroller.getBoundingClientRect();
    const getTargetSources = () => candidateHierarchicalView.model.roots
      .filter((node) => node.data.sourceType !== "overrides")
      .map((source) => ({ source, folders: source.children.filter((node) => node.kind === "folder" && node.data.candidates.length) }));
    let targetSources = getTargetSources();
    let targetSource = targetSources.find(({ folders }) => folders.length > 1);
    let siblingProbeKeys = [];
    if (!targetSource) {
      const seedSource = targetSources.find(({ source, folders }) => source.data.sourceType !== "upstream" && folders.length === 1);
      const seed = seedSource.folders[0].data.candidates[0];
      const sortProbe = structuredClone(seed);
      const siblingProbe = structuredClone(seed);
      sortProbe.key = `${seed.key}:sort-probe`;
      sortProbe.id = `${seed.id}-sort-probe`;
      sortProbe.title = `${seed.title} Sort Probe`;
      siblingProbe.key = `${seed.key}:sibling-folder-probe`;
      siblingProbe.id = `${seed.id}-sibling-folder-probe`;
      siblingProbe.title = `${seed.title} Sibling Folder Probe`;
      siblingProbe.category = `${seed.category} Sibling Probe`;
      siblingProbeKeys = [sortProbe.key, siblingProbe.key];
      state.candidates.push(sortProbe, siblingProbe);
      renderCandidateList();
      targetSources = getTargetSources();
      targetSource = targetSources.find(({ folders }) => folders.length > 1);
    }
    const folder = [...targetSource.folders.slice(0, -1)].sort((left, right) => right.data.candidates.length - left.data.candidates.length)[0];
    const sibling = targetSource.folders[targetSource.folders.indexOf(folder) + 1];
    return {
      allCollapsed: candidateHierarchicalView.model.nodes
        .filter((node) => ["source", "folder"].includes(node.kind))
        .every((node) => !node.expanded),
      geometry: { top: rect.top, bottom: rect.bottom, width: rect.width, clientWidth: scroller.clientWidth },
      gutter: getComputedStyle(scroller).scrollbarGutter,
      sourceId: targetSource.source.id,
      folderId: folder.id,
      headerId: folder.children[0].id,
      leafId: folder.children[0].children[Math.min(10, folder.children[0].children.length - 1)].id,
      siblingId: sibling.id,
      siblingProbeKeys
    };
  });
  assert(initial.allCollapsed, "one or more candidate source or folder nodes start expanded");

  await page.locator(`#candidate-list [data-node-id="${initial.sourceId}"]`).click();
  await page.locator(`#candidate-list [data-node-id="${initial.folderId}"]`).click();
  await page.evaluate(({ sourceId, folderId, headerId, leafId, siblingId }) => {
    const scroller = document.querySelector("#candidate-list");
    const leaf = candidateHierarchicalView.model.nodesById.get(leafId);
    const sibling = candidateHierarchicalView.model.nodesById.get(siblingId);
    const stickyHeight = [sourceId, folderId, headerId]
      .map((id) => candidateHierarchicalView.model.nodesById.get(id).rowHeight)
      .reduce((total, height) => total + height, 0);
    scroller.scrollTop = Math.max(1, Math.min(leaf.layoutTop - stickyHeight, sibling.layoutTop - stickyHeight - 2));
  }, initial);
  await settle(page);
  await page.evaluate((leafId) => {
    const scroller = document.querySelector("#candidate-list");
    const target = document.querySelector(`#candidate-list [data-node-id="${CSS.escape(leafId)}"]`);
    const stack = document.querySelector("#candidate-sticky-stack");
    scroller.scrollTop += target.getBoundingClientRect().top - stack.getBoundingClientRect().bottom;
  }, initial.leafId);
  await settle(page);

  const sticky = await page.evaluate(({ sourceId, folderId, headerId }) => {
    const scroller = document.querySelector("#candidate-list");
    const stack = document.querySelector("#candidate-sticky-stack");
    const expectedIds = [sourceId, folderId, headerId];
    const rows = expectedIds.map((id) => document.querySelector(`#candidate-sticky-stack [data-node-id="${CSS.escape(id)}"]`));
    const naturalRows = expectedIds.map((id) => document.querySelector(`#candidate-list [data-node-id="${CSS.escape(id)}"]`));
    const stackBottom = Math.max(...rows.map((row) => row.getBoundingClientRect().bottom));
    const firstLeaf = [...document.querySelectorAll("#candidate-list [data-candidate-key]")]
      .find((row) => row.getBoundingClientRect().bottom > stackBottom);
    const firstLeafRect = firstLeaf?.getBoundingClientRect();
    const orderBefore = candidateHierarchicalView.model.nodesById.get(headerId).children.map((node) => node.id);
    const scrollTopBefore = scroller.scrollTop;
    rows[2].querySelector('[data-candidate-sort="candidate"]').click();
    return new Promise((resolve) => requestAnimationFrame(() => requestAnimationFrame(() => {
      const nextHeader = candidateHierarchicalView.model.nodesById.get(headerId);
      const nextRows = expectedIds.map((id) => document.querySelector(`#candidate-sticky-stack [data-node-id="${CSS.escape(id)}"]`));
      resolve({
        ids: nextRows.map((row) => row?.dataset.nodeId),
        opaque: nextRows.every((row) => getComputedStyle(row).backgroundColor !== "rgba(0, 0, 0, 0)"),
        contiguous: nextRows.slice(1).every((row, index) => Math.abs(row.getBoundingClientRect().top - nextRows[index].getBoundingClientRect().bottom) < 1),
        naturalInert: naturalRows.every((row) => row.inert),
        firstLeafKey: firstLeaf?.dataset.candidateKey,
        firstLeafTop: firstLeafRect?.top,
        firstLeafBottom: firstLeafRect?.bottom,
        stackBottom,
        stackHeight: stack.getBoundingClientRect().height,
        scrollPaddingTop: getComputedStyle(scroller).scrollPaddingTop,
        scrollSnapType: getComputedStyle(scroller).scrollSnapType,
        changedOrder: orderBefore.join("|") !== nextHeader.children.map((node) => node.id).join("|"),
        scrollTopBefore,
        scrollTopAfter: scroller.scrollTop,
        sourceExpanded: candidateHierarchicalView.model.nodesById.get(sourceId).expanded,
        folderExpanded: candidateHierarchicalView.model.nodesById.get(folderId).expanded,
        naturalHeaderCount: document.querySelectorAll(`#candidate-list [data-node-id="${CSS.escape(headerId)}"]`).length
      });
    })));
  }, initial);

  assert(sticky.ids.join("|") === [initial.sourceId, initial.folderId, initial.headerId].join("|"), "sticky source, folder, and column context is incomplete");
  assert(sticky.opaque && sticky.contiguous, "sticky ancestry contains transparency, gaps, or overlap");
  assert(sticky.naturalInert, "natural counterparts remain interactive while sticky copies own focus");
  if (sticky.firstLeafTop !== undefined) assert(sticky.firstLeafTop >= sticky.stackBottom - 1, "candidate row settles above sticky ancestry");
  assert(sticky.scrollSnapType === "none" && Math.abs(parseFloat(sticky.scrollPaddingTop) - sticky.stackHeight) <= 1, "candidate scrolling does not reserve stable sticky ancestry");
  assert(sticky.changedOrder, "candidate sort did not reorder the open folder");
  assert(Math.abs(sticky.scrollTopAfter - sticky.scrollTopBefore) < 0.1 && sticky.sourceExpanded && sticky.folderExpanded, "candidate sort changed tree position or disclosure state");
  assert(sticky.naturalHeaderCount === 1, "folder renders duplicate natural column headers");

  const handoff = await page.evaluate(async ({ sourceId, folderId, headerId, siblingId }) => {
    const scroller = document.querySelector("#candidate-list");
    const stack = document.querySelector("#candidate-sticky-stack");
    const previousScrollTop = scroller.scrollTop;
    const settle = () => new Promise((resolve) => requestAnimationFrame(() => requestAnimationFrame(resolve)));
    const maximumScrollTop = scroller.scrollHeight - scroller.clientHeight;
    let transition = null;
    for (let scrollTop = 0; scrollTop <= maximumScrollTop; scrollTop += 40) {
      const current = candidateHierarchicalView.stickyController.calculate(scrollTop);
      let targetScrollTop = Math.round((scrollTop + 100) / 40) * 40;
      if (Math.abs(targetScrollTop - scrollTop) < 1) targetScrollTop += 40;
      targetScrollTop = Math.min(targetScrollTop, maximumScrollTop);
      const next = candidateHierarchicalView.stickyController.calculate(targetScrollTop);
      const currentIds = current.map((entry) => entry.nodeId);
      const nextIds = next.map((entry) => entry.nodeId);
      if (currentIds.includes(folderId) && currentIds.includes(headerId) && nextIds.includes(siblingId) && !nextIds.includes(headerId)) {
        transition = { scrollTop, targetScrollTop };
        break;
      }
    }
    if (!transition) return { transitionFound: false };
    scroller.scrollTop = transition.scrollTop;
    await settle();
    const poolRows = [...stack.children];
    const poolUses = poolRows.flatMap((row) => [...row.querySelectorAll("svg use")]);
    const outgoingHeader = stack.querySelector(`[data-node-id="${CSS.escape(headerId)}"]`);
    scroller.scrollTop = transition.targetScrollTop;
    await settle();
    const incomingRow = stack.querySelector(`[data-node-id="${CSS.escape(siblingId)}"]`);
    const nextPoolRows = [...stack.children];
    const nextPoolUses = nextPoolRows.flatMap((row) => [...row.querySelectorAll("svg use")]);
    const result = {
      transitionFound: true,
      poolSize: nextPoolRows.length,
      poolRowsStable: poolRows.length === nextPoolRows.length && poolRows.every((row) => nextPoolRows.includes(row)),
      poolUsesStable: poolUses.length === nextPoolUses.length && poolUses.every((use) => nextPoolUses.includes(use)),
      incomingVisible: Boolean(incomingRow),
      outgoingHeaderClass: outgoingHeader?.className || null,
      outgoingHeaderTop: parseFloat(outgoingHeader?.style.top || "NaN"),
      stackHeight: stack.getBoundingClientRect().height
    };
    scroller.scrollTop = previousScrollTop;
    await settle();
    return result;
  }, initial);
  assert(handoff.transitionFound, "candidate child-boundary handoff fixture has no one-wheel transition");
  assert(handoff.poolSize === 7, "candidate sticky renderer pool is not bounded to seven rows");
  assert(handoff.poolRowsStable, "candidate child-boundary handoff replaces a prewarmed row renderer");
  assert(handoff.poolUsesStable, "candidate child-boundary handoff replaces a prewarmed SVG renderer");
  assert(handoff.incomingVisible, "candidate child-boundary handoff does not render the incoming folder");
  assert(handoff.outgoingHeaderClass?.includes("hierarchical-view-sticky-pool-row") && handoff.outgoingHeaderTop >= handoff.stackHeight - 1, `candidate child-boundary handoff parks its sort header over a visible sticky row (${handoff.outgoingHeaderClass}, top ${handoff.outgoingHeaderTop}, stack ${handoff.stackHeight})`);

  const grid = await page.evaluate(async () => {
    const scroller = document.querySelector("#candidate-list");
    const moduloGrid = (value) => Math.abs(value % 40) < 1 || Math.abs(value % 40 - 40) < 1;
    const rowHeightsAligned = candidateHierarchicalView.model.nodes.every((node) => moduloGrid(node.rowHeight));
    const layoutAligned = candidateHierarchicalView.layout.entries.every((entry) => moduloGrid(entry.top) && moduloGrid(entry.height));
    const terminalRangeAligned = moduloGrid(scroller.scrollHeight - scroller.clientHeight);
    const scrollTopBefore = scroller.scrollTop;
    const delta = 100;
    const rawTarget = scrollTopBefore + delta;
    let expectedScrollTop = Math.round(rawTarget / 40) * 40;
    if (Math.abs(expectedScrollTop - scrollTopBefore) < 1) expectedScrollTop += 40;
    expectedScrollTop = Math.max(0, Math.min(expectedScrollTop, scroller.scrollHeight - scroller.clientHeight));
    const allowed = scroller.dispatchEvent(new WheelEvent("wheel", { bubbles: true, cancelable: true, deltaY: delta }));
    await new Promise((resolve) => requestAnimationFrame(() => requestAnimationFrame(resolve)));
    const scrollTopAfter = scroller.scrollTop;
    scroller.scrollTop = scrollTopBefore;
    return {
      rowHeightsAligned,
      layoutAligned,
      terminalRangeAligned,
      prevented: !allowed,
      expectedScrollTop,
      scrollTopAfter,
      appliedDelta: scrollTopAfter - scrollTopBefore
    };
  });
  assert(grid.rowHeightsAligned && grid.layoutAligned && grid.terminalRangeAligned, "candidate hierarchy does not stay on the 40px scroll grid");
  assert(grid.prevented && Math.abs(grid.scrollTopAfter - grid.expectedScrollTop) < 1 && Math.abs(grid.appliedDelta) >= 80, "coarse candidate wheel input does not preserve speed on a grid-aligned destination");

  await page.locator(`#candidate-sticky-stack [data-node-id="${initial.folderId}"]`).click();
  await settle(page);
  const folderClosed = await page.evaluate(({ folderId, headerId }) => ({
    expanded: candidateHierarchicalView.model.nodesById.get(folderId).expanded,
    headerVisible: Boolean(document.querySelector(`#candidate-sticky-stack [data-node-id="${CSS.escape(headerId)}"]`))
  }), initial);
  assert(!folderClosed.expanded && !folderClosed.headerVisible, "collapsed folder leaves stale sticky column content");

  await page.locator(`#candidate-list [data-node-id="${initial.sourceId}"]`).click();
  await settle(page);
  const sourceClosed = await page.evaluate(({ sourceId, folderId, headerId }) => ({
    expanded: candidateHierarchicalView.model.nodesById.get(sourceId).expanded,
    childVisible: [folderId, headerId].some((id) => document.querySelector(`#candidate-sticky-stack [data-node-id="${CSS.escape(id)}"]`))
  }), initial);
  assert(!sourceClosed.expanded && !sourceClosed.childVisible, "collapsed source leaves stale sticky child content");

  const siblingExpansion = await page.evaluate(async ({ sourceId, siblingId }) => {
    const source = candidateHierarchicalView.model.nodesById.get(sourceId);
    source.expanded = true;
    candidateExpansionState.set(sourceId, true);
    candidateHierarchicalView.model.flatten();
    candidateHierarchicalView.layout.recalculate();
    candidateHierarchicalView.renderNaturalRows();
    const sibling = candidateHierarchicalView.model.nodesById.get(siblingId);
    const scroller = document.querySelector("#candidate-list");
    scroller.scrollTop = Math.max(0, sibling.layoutTop - scroller.clientHeight / 2);
    await new Promise((resolve) => requestAnimationFrame(() => requestAnimationFrame(resolve)));
    const row = document.querySelector(`#candidate-list [data-node-id="${CSS.escape(siblingId)}"]`);
    const scrollTopBefore = scroller.scrollTop;
    const topBefore = row.getBoundingClientRect().top;
    row.click();
    await new Promise((resolve) => requestAnimationFrame(() => requestAnimationFrame(resolve)));
    return {
      expanded: candidateHierarchicalView.model.nodesById.get(siblingId).expanded,
      scrollDelta: scroller.scrollTop - scrollTopBefore,
      topDelta: document.querySelector(`#candidate-list [data-node-id="${CSS.escape(siblingId)}"]`).getBoundingClientRect().top - topBefore,
      snapType: getComputedStyle(scroller).scrollSnapType
    };
  }, initial);
  assert(siblingExpansion.expanded, "sibling candidate folder did not expand");
  assert(Math.abs(siblingExpansion.scrollDelta) < 0.1 && Math.abs(siblingExpansion.topDelta) < 0.1, "opening a sibling candidate folder moved the tree instead of expanding downward");
  assert(siblingExpansion.snapType === "none", "candidate disclosure changed continuous scrolling");

  if (initial.siblingProbeKeys.length) {
    await page.evaluate((keys) => {
      state.candidates = state.candidates.filter((candidate) => !keys.includes(candidate.key));
      renderCandidateList();
    }, initial.siblingProbeKeys);
  }

  const finalGeometry = await page.evaluate(() => {
    const scroller = document.querySelector("#candidate-list");
    const rect = scroller.getBoundingClientRect();
    return { top: rect.top, bottom: rect.bottom, width: rect.width, clientWidth: scroller.clientWidth };
  });
  assert(initial.gutter === "stable" && JSON.stringify(finalGeometry) === JSON.stringify(initial.geometry), "candidate disclosure changes scrollbar viewport geometry");

  await page.locator('[data-workspace-tab="assessment-results"]').click();
  const assessmentGrid = await page.evaluate(async () => {
    let probeKey = null;
    if (!getFilteredAssessmentCandidates().length) {
      const probe = structuredClone(state.assessedCandidates[0]);
      probe.key = `${probe.key}:assessment-grid-probe`;
      probe.assessment.hostedApplicable = false;
      probe.assessment.recommendation = "exclude";
      probeKey = probe.key;
      state.assessedCandidates.push(probe);
      renderAssessmentResults();
    }
    const source = assessmentHierarchicalView.model.roots.find((node) => node.children.length);
    if (!source.expanded) document.querySelector(`#assessment-results-list [data-node-id="${CSS.escape(source.id)}"]`)?.click();
    await new Promise((resolve) => requestAnimationFrame(() => requestAnimationFrame(resolve)));
    const header = source.children.find((node) => node.kind === "header");
    const inspect = () => {
      const modelAligned = assessmentHierarchicalView.model.nodes
        .filter((node) => node.kind === "leaf")
        .every((node) => node.rowHeight === 40);
      const rows = [...document.querySelectorAll("#assessment-results-list [data-assessment-key]")];
      const renderedAligned = rows.length > 0 && rows.every((row) => Math.abs(row.getBoundingClientRect().height - 40) < 1);
      const contentContained = rows.every((row) => {
        const rowRect = row.getBoundingClientRect();
        return [...row.children].every((child) => {
          const childRect = child.getBoundingClientRect();
          return childRect.top >= rowRect.top - 1 && childRect.bottom <= rowRect.bottom + 1;
        });
      });
      return { modelAligned, renderedAligned, contentContained };
    };
    const before = inspect();
    document.querySelector(`#assessment-results-list [data-node-id="${CSS.escape(header.id)}"] [data-assessment-sort="candidate"]`)?.click();
    await new Promise((resolve) => requestAnimationFrame(() => requestAnimationFrame(resolve)));
    const after = inspect();
    if (probeKey) {
      state.assessedCandidates = state.assessedCandidates.filter((candidate) => candidate.key !== probeKey);
      renderAssessmentResults();
    }
    return { before, after };
  });
  assert(assessmentGrid.before.modelAligned && assessmentGrid.before.renderedAligned && assessmentGrid.before.contentContained, "Assessment Results does not use contained 40px leaf rows");
  assert(assessmentGrid.after.modelAligned && assessmentGrid.after.renderedAligned && assessmentGrid.after.contentContained, "Assessment Results sorting does not preserve contained 40px leaf rows");
}

module.exports = { name: "candidate sticky context", behaviorIds, viewport: { width: 1440, height: 900 }, run };
