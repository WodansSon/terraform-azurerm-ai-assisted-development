const { openWorkbench } = require("../helpers/workbench.cjs");

const behaviorIds = [
  "WB-UX-STICKY-001",
  "WB-UX-STICKY-002",
  "WB-UX-STICKY-003",
  "WB-UX-STICKY-004",
  "WB-UX-STICKY-005",
  "WB-UX-STICKY-006",
  "WB-UX-STICKY-007",
  "WB-UX-STICKY-008"
];

async function settle(page) {
  await page.evaluate(() => new Promise((resolve) => requestAnimationFrame(() => requestAnimationFrame(resolve))));
}

async function run({ page, baseUrl, assert, playback }) {
  await openWorkbench(page, baseUrl);
  await playback.show(page, "Candidate tree sticky context");

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
    const folder = [...targetSource.folders].sort((left, right) => right.data.candidates.length - left.data.candidates.length)[0];
    const sibling = targetSource.folders.find((node) => node.id !== folder.id);
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
}

module.exports = { name: "candidate sticky context", behaviorIds, viewport: { width: 1440, height: 900 }, run };
