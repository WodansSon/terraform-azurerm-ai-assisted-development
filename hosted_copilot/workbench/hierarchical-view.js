(() => {
  "use strict";

  const BOUNDARY_EPSILON = 1;
  const MAX_STICKY_ROW_COUNT = 7;

  function syncAttributes(target, source) {
    Array.from(target.attributes).forEach((attribute) => {
      if (attribute.name !== "style" && !source.hasAttribute(attribute.name)) target.removeAttribute(attribute.name);
    });
    Array.from(source.attributes).forEach((attribute) => {
      if (attribute.name !== "style" && target.getAttribute(attribute.name) !== attribute.value) {
        target.setAttribute(attribute.name, attribute.value);
      }
    });
    if (target.tagName === "INPUT" && ["checkbox", "radio"].includes(target.type)) {
      target.checked = source.checked;
      target.indeterminate = source.indeterminate;
    }
  }

  function patchNode(target, source) {
    const replace = target.nodeType !== source.nodeType
      || target.nodeType === Node.ELEMENT_NODE && (target.tagName !== source.tagName || target.namespaceURI !== source.namespaceURI);
    if (replace) {
      target.replaceWith(source.cloneNode(true));
      return;
    }
    if (target.nodeType === Node.TEXT_NODE) {
      if (target.nodeValue !== source.nodeValue) target.nodeValue = source.nodeValue;
      return;
    }
    if (target.nodeType !== Node.ELEMENT_NODE) return;
    syncAttributes(target, source);
    const targetChildren = Array.from(target.childNodes);
    const sourceChildren = Array.from(source.childNodes);
    const commonLength = Math.min(targetChildren.length, sourceChildren.length);
    for (let index = 0; index < commonLength; index += 1) patchNode(targetChildren[index], sourceChildren[index]);
    for (let index = targetChildren.length - 1; index >= sourceChildren.length; index -= 1) targetChildren[index].remove();
    for (let index = commonLength; index < sourceChildren.length; index += 1) {
      target.appendChild(sourceChildren[index].cloneNode(true));
    }
  }

  function normalizeNodes(nodes, parent = null, depth = 0, result = []) {
    nodes.forEach((source, childIndex) => {
      const node = {
        ...source,
        children: [],
        childIndex,
        depth,
        expanded: source.expanded !== false,
        parent,
        parentId: parent?.id || null,
        rowHeight: source.rowHeight || 40,
        stickyEligible: source.stickyEligible !== false && source.kind !== "leaf" && source.kind !== "detail"
      };
      result.push(node);
      node.children = normalizeNodes(source.children || [], node, depth + 1, result);
    });
    return nodes.map((source) => result.find((node) => node.id === source.id));
  }

  class HierarchicalViewModel {
    constructor(nodes = []) {
      this.setNodes(nodes);
    }

    setNodes(nodes) {
      const allNodes = [];
      this.roots = normalizeNodes(nodes, null, 0, allNodes);
      this.nodes = allNodes;
      this.nodesById = new Map(allNodes.map((node) => [node.id, node]));
      this.flatten();
    }

    flatten() {
      const visibleNodes = [];
      const visit = (node) => {
        node.visibleIndex = visibleNodes.length;
        node.subtreeStartIndex = node.visibleIndex;
        visibleNodes.push(node);
        if (node.expanded) node.children.forEach(visit);
        node.subtreeEndIndex = visibleNodes.length - 1;
      };
      this.roots.forEach(visit);
      this.visibleNodes = visibleNodes;
      return visibleNodes;
    }

    setExpanded(nodeId, expanded) {
      const node = this.nodesById.get(nodeId);
      if (!node || !node.children.length || node.expanded === expanded) return false;
      node.expanded = expanded;
      this.flatten();
      return true;
    }

    toggle(nodeId) {
      const node = this.nodesById.get(nodeId);
      return node ? this.setExpanded(nodeId, !node.expanded) : false;
    }
  }

  class HierarchicalViewLayout {
    constructor(model) {
      this.model = model;
      this.recalculate();
    }

    recalculate() {
      let top = 0;
      this.entries = this.model.visibleNodes.map((node, index) => {
        const entry = { node, index, top, height: node.rowHeight };
        node.visibleIndex = index;
        node.layoutTop = top;
        top += node.rowHeight;
        return entry;
      });
      this.totalHeight = top;
      return this.entries;
    }

    updateHeight(nodeId, height) {
      const node = this.model.nodesById.get(nodeId);
      if (!node || height <= 0 || Math.abs(node.rowHeight - height) < BOUNDARY_EPSILON) return false;
      node.rowHeight = height;
      this.recalculate();
      return true;
    }

    indexAt(position) {
      if (!this.entries.length) return -1;
      let low = 0;
      let high = this.entries.length - 1;
      while (low <= high) {
        const middle = Math.floor((low + high) / 2);
        const entry = this.entries[middle];
        if (position < entry.top) high = middle - 1;
        else if (position >= entry.top + entry.height) low = middle + 1;
        else return middle;
      }
      return Math.min(this.entries.length - 1, Math.max(0, low));
    }
  }

  function getCurrentRootIndex(stickyNodes) {
    for (let index = stickyNodes.length - 1; index >= 0; index -= 1) {
      if (stickyNodes[index].depth === 0) return index;
    }
    return -1;
  }

  function getStickyTransitionPosition(stickyNodes, incoming, accumulateRoots) {
    if (!stickyNodes.length) return 0;
    if (incoming.depth === 0) {
      if (!accumulateRoots) return 0;
      const roots = stickyNodes.filter((node) => node.depth === 0);
      if (roots.some((node) => node.id === incoming.id)) return null;
      return roots.reduce((position, node) => position + node.rowHeight, 0);
    }

    const currentRootIndex = getCurrentRootIndex(stickyNodes);
    if (currentRootIndex < 0) return null;
    let incomingRoot = incoming;
    while (incomingRoot.parent) incomingRoot = incomingRoot.parent;
    if (incomingRoot.id !== stickyNodes[currentRootIndex].id) return null;

    const descendants = stickyNodes.slice(currentRootIndex + 1);
    const replacementIndex = descendants.findIndex((node) => node.depth >= incoming.depth);
    const targetIndex = replacementIndex < 0 ? stickyNodes.length : currentRootIndex + 1 + replacementIndex;
    return stickyNodes.slice(0, targetIndex).reduce((position, node) => position + node.rowHeight, 0);
  }

  function transitionStickyMembership(stickyNodes, incoming, accumulateRoots) {
    if (incoming.depth === 0) {
      if (!accumulateRoots) return [incoming];
      const roots = stickyNodes.filter((node) => node.depth === 0);
      if (roots.some((node) => node.id === incoming.id)) return stickyNodes;
      return [...roots, incoming];
    }

    const currentRootIndex = getCurrentRootIndex(stickyNodes);
    if (currentRootIndex < 0) return stickyNodes;
    const currentRoot = stickyNodes[currentRootIndex];
    let incomingRoot = incoming;
    while (incomingRoot.parent) incomingRoot = incomingRoot.parent;
    if (incomingRoot.id !== currentRoot.id) return stickyNodes;

    const rootPrefix = stickyNodes.slice(0, currentRootIndex + 1);
    const descendants = stickyNodes.slice(currentRootIndex + 1);
    const sameDepthIndex = descendants.findIndex((node) => node.depth === incoming.depth);
    if (sameDepthIndex >= 0) return [...rootPrefix, ...descendants.slice(0, sameDepthIndex), incoming];
    const shallowerIndex = descendants.findIndex((node) => node.depth > incoming.depth);
    if (shallowerIndex >= 0) return [...rootPrefix, ...descendants.slice(0, shallowerIndex), incoming];
    return [...stickyNodes, incoming];
  }

  class HierarchicalStickyController {
    constructor(view) {
      this.view = view;
      this.state = [];
    }

    getHeight(stickyNodes, end = stickyNodes.length) {
      return stickyNodes.slice(0, end).reduce((height, node) => height + node.rowHeight, 0);
    }

    settleCascade(stickyNodes, incoming, minimumSlot, scrollTop) {
      if (incoming.layoutTop > scrollTop + this.getHeight(stickyNodes) + BOUNDARY_EPSILON) {
        return { destination: -1, entered: false, settled: false, stickyNodes };
      }
      let destination = stickyNodes.length;
      while (destination > minimumSlot && incoming.layoutTop <= scrollTop + this.getHeight(stickyNodes, destination - 1) + BOUNDARY_EPSILON) {
        destination -= 1;
      }
      const settled = destination === minimumSlot;
      let nextStickyNodes = destination === stickyNodes.length
        ? [...stickyNodes, incoming]
        : [...stickyNodes.slice(0, destination), incoming, ...stickyNodes.slice(destination + 1)];
      if (settled) nextStickyNodes = nextStickyNodes.slice(0, destination + 1);
      return { destination, entered: true, settled, stickyNodes: nextStickyNodes };
    }

    settleSemantic(stickyNodes, incoming, minimumSlot, scrollTop) {
      if (!stickyNodes.length) {
        if (incoming.layoutTop > scrollTop + BOUNDARY_EPSILON) {
          return { destination: -1, entered: false, settled: false, stickyNodes };
        }
        return { destination: 0, entered: true, settled: true, stickyNodes: [incoming] };
      }
      const bottomIndex = stickyNodes.length - 1;
      const bottom = stickyNodes[bottomIndex];
      let destination = incoming.depth > bottom.depth ? stickyNodes.length : bottomIndex;
      if (incoming.layoutTop > scrollTop + this.getHeight(stickyNodes, destination) + BOUNDARY_EPSILON) {
        return { destination: -1, entered: false, settled: false, stickyNodes };
      }
      while (destination > minimumSlot && incoming.layoutTop <= scrollTop + this.getHeight(stickyNodes, destination - 1) + BOUNDARY_EPSILON) {
        destination -= 1;
      }
      return {
        destination,
        entered: true,
        settled: destination === minimumSlot,
        stickyNodes: destination === stickyNodes.length ? [...stickyNodes, incoming] : [...stickyNodes.slice(0, destination), incoming]
      };
    }

    settleIncoming(stickyNodes, incoming, minimumSlot, scrollTop) {
      let incomingRoot = incoming;
      while (incomingRoot.parent) incomingRoot = incomingRoot.parent;
      const cascade = this.view.adapter.shouldCascadeTransition?.({ incoming, incomingRoot, stickyNodes }) === true;
      if (incoming.depth === 0 && this.view.adapter.accumulateRoots === true && !cascade) {
        const roots = stickyNodes.filter((node) => node.depth === 0);
        const existingIndex = roots.findIndex((node) => node.id === incoming.id);
        if (existingIndex >= 0) {
          return { destination: existingIndex, entered: true, settled: true, stickyNodes };
        }
        if (incoming.layoutTop > scrollTop + this.getHeight(roots) + BOUNDARY_EPSILON) {
          return { destination: -1, entered: false, settled: false, stickyNodes };
        }
        return { destination: roots.length, entered: true, settled: true, stickyNodes: [...roots, incoming] };
      }
      return cascade
        ? this.settleCascade(stickyNodes, incoming, minimumSlot, scrollTop)
        : this.settleSemantic(stickyNodes, incoming, minimumSlot, scrollTop);
    }

    resolveChildren(parent, stickyNodes, parentSlot, scrollTop) {
      if (!parent.expanded) return { blocked: false, stickyNodes };
      const minimumSlot = parentSlot + 1;
      for (const child of parent.children.filter((node) => node.stickyEligible)) {
        const transition = this.settleIncoming(stickyNodes, child, minimumSlot, scrollTop);
        if (!transition.entered) return { blocked: true, stickyNodes };
        stickyNodes = transition.stickyNodes;
        const descendants = this.resolveChildren(child, stickyNodes, transition.destination, scrollTop);
        stickyNodes = descendants.stickyNodes;
        if (descendants.blocked) return descendants;
        if (!transition.settled) return { blocked: true, stickyNodes };
      }
      return { blocked: false, stickyNodes };
    }

    calculate(scrollTop) {
      if (scrollTop <= 0) return [];
      let stickyNodes = [];
      let accumulatedRoots = 0;
      for (const root of this.view.model.roots) {
        const minimumSlot = this.view.adapter.accumulateRoots === true ? accumulatedRoots : 0;
        const transition = this.settleIncoming(stickyNodes, root, minimumSlot, scrollTop);
        if (!transition.entered) break;
        stickyNodes = transition.stickyNodes;
        const descendants = this.resolveChildren(root, stickyNodes, transition.destination, scrollTop);
        stickyNodes = descendants.stickyNodes;
        if (descendants.blocked) break;
        if (!transition.settled) break;
        if (this.view.adapter.accumulateRoots === true) accumulatedRoots += 1;
      }
      return stickyNodes.slice(0, MAX_STICKY_ROW_COUNT).map((node, stickySlot) => ({
        node,
        nodeId: node.id,
        treeDepth: node.depth,
        stickySlot,
        height: node.rowHeight,
        position: Math.max(
          stickyNodes.slice(0, stickySlot).reduce((top, stickyNode) => top + stickyNode.rowHeight, 0),
          node.layoutTop - scrollTop
        )
      }));
    }

    getRequiredScrollTop() {
      let requiredScrollTop = 0;
      let stickyNodes = [];
      for (const entry of this.view.layout.entries) {
        const node = entry.node;
        if (!node.stickyEligible) continue;
        const transitionPosition = getStickyTransitionPosition(stickyNodes, node, this.view.adapter.accumulateRoots === true);
        if (transitionPosition === null) continue;
        requiredScrollTop = Math.max(requiredScrollTop, entry.top - transitionPosition);
        stickyNodes = transitionStickyMembership(stickyNodes, node, this.view.adapter.accumulateRoots === true);
      }
      return { requiredScrollTop, terminalNodes: stickyNodes };
    }

    update() {
      const nextState = this.calculate(this.view.viewport.scrollTop);
      const unchanged = nextState.length === this.state.length
        && nextState.every((entry, index) => entry.node === this.state[index].node && entry.nodeId === this.state[index].nodeId && entry.position === this.state[index].position && entry.height === this.state[index].height);
      if (unchanged) return;
      this.state = nextState;
      this.view.renderStickyState(nextState);
    }
  }

  class HierarchicalView {
    constructor({ adapter, stickyContainer, viewport }) {
      this.adapter = adapter;
      this.stickyContainer = stickyContainer;
      this.viewport = viewport;
      this.rowsContainer = document.createElement("div");
      this.rowsContainer.className = "hierarchical-view-rows";
      this.viewport.replaceChildren(this.rowsContainer);
      this.stickyController = new HierarchicalStickyController(this);
      this.handleScroll = () => this.stickyController.update();
      this.handleClick = (event) => this.onClick(event);
      this.handleKeyDown = (event) => this.onKeyDown(event);
      this.handleWheel = (event) => this.onStickyWheel(event);
      this.viewport.addEventListener("scroll", this.handleScroll, { passive: true });
      this.viewport.addEventListener("click", this.handleClick);
      this.viewport.addEventListener("keydown", this.handleKeyDown);
      this.stickyContainer.addEventListener("click", this.handleClick);
      this.stickyContainer.addEventListener("keydown", this.handleKeyDown);
      this.stickyContainer.addEventListener("wheel", this.handleWheel, { passive: false });
    }

    setInput(input, { preserveScroll = true } = {}) {
      const scrollTop = preserveScroll ? this.viewport.scrollTop : 0;
      this.model = new HierarchicalViewModel(this.adapter.buildNodes(input));
      this.layout = new HierarchicalViewLayout(this.model);
      this.renderNaturalRows();
      this.viewport.scrollTop = scrollTop;
      this.stickyController.update();
      if (!this.stickyController.state.length) this.renderStickyState([]);
    }

    refresh({ preserveScroll = true } = {}) {
      this.setInput(this.adapter.getInput(), { preserveScroll });
    }

    refreshLayout() {
      this.syncStickyWidth();
      this.syncContentHeight();
      this.stickyController.update();
    }

    renderNaturalRows(measureDynamicRows = true) {
      const existing = new Map(Array.from(this.rowsContainer.children).map((row) => [row.dataset.nodeId, row]));
      const desired = this.layout.entries.map((entry) => {
        let row = existing.get(entry.node.id);
        const rendered = this.adapter.renderRow(entry.node, "natural");
        if (row && row.tagName === rendered.tagName && row.namespaceURI === rendered.namespaceURI) {
          patchNode(row, rendered);
        } else if (row) {
          row.replaceWith(rendered);
          row = rendered;
        } else {
          row = rendered;
        }
        row.hierarchicalNode = entry.node;
        row.classList.add("hierarchical-view-row");
        row.dataset.nodeId = entry.node.id;
        row.dataset.treeDepth = String(entry.node.depth);
        row.style.top = `${entry.top}px`;
        const toggle = row.matches("[data-hierarchical-toggle]") ? row : row.querySelector("[data-hierarchical-toggle]");
        if (toggle) toggle.setAttribute("aria-expanded", String(entry.node.expanded));
        if (entry.node.dynamicHeight && measureDynamicRows) {
          row.style.removeProperty("height");
          row.style.minHeight = `${entry.height}px`;
        } else {
          row.style.removeProperty("min-height");
          row.style.height = `${entry.height}px`;
        }
        return row;
      });
      this.syncContentHeight();
      const desiredRows = new Set(desired);
      Array.from(this.rowsContainer.children).forEach((row) => {
        if (!desiredRows.has(row)) row.remove();
      });
      desired.forEach((row, index) => {
        const current = this.rowsContainer.children[index];
        if (current !== row) this.rowsContainer.insertBefore(row, current || null);
      });
      this.syncStickyWidth();
      if (!measureDynamicRows) return;
      let changed = false;
      this.rowsContainer.querySelectorAll(".hierarchical-view-row[data-node-id]").forEach((row) => {
        const node = this.model.nodesById.get(row.dataset.nodeId);
        if (node?.dynamicHeight) changed = this.layout.updateHeight(node.id, row.offsetHeight) || changed;
      });
      if (changed) this.renderNaturalRows(false);
    }

    getPrewarmedStickyState() {
      let longestPath = [];
      const visit = (node, path) => {
        if (!node.stickyEligible) return;
        const nextPath = [...path, node];
        if (nextPath.length > longestPath.length) longestPath = nextPath;
        if (node.expanded) node.children.forEach((child) => visit(child, nextPath));
      };
      this.model.roots.forEach((root) => visit(root, []));
      let position = 0;
      return longestPath.slice(0, MAX_STICKY_ROW_COUNT).map((node, stickySlot) => {
        const entry = {
          node,
          nodeId: node.id,
          treeDepth: node.depth,
          stickySlot,
          height: node.rowHeight,
          position
        };
        position += node.rowHeight;
        return entry;
      });
    }

    syncStickyWidth() {
      const viewportWidth = this.viewport.getBoundingClientRect().width;
      const rowsWidth = this.rowsContainer.getBoundingClientRect().width;
      if (viewportWidth <= 0 || rowsWidth <= 0) return;
      this.stickyContainer.style.right = `${Math.max(0, viewportWidth - rowsWidth)}px`;
    }

    syncContentHeight() {
      let contentHeight = this.layout.totalHeight;
      const lastEntry = this.layout.entries.at(-1);
      const terminal = this.stickyController.getRequiredScrollTop();
      let requiredScrollTop = terminal.requiredScrollTop;
      if (this.adapter.keepLastRowVisible && lastEntry) {
        const stickyHeight = terminal.terminalNodes.reduce((height, node) => height + node.rowHeight, 0);
        requiredScrollTop = Math.max(requiredScrollTop, lastEntry.top - stickyHeight);
      }
      contentHeight = Math.max(contentHeight, this.viewport.clientHeight + Math.max(0, requiredScrollTop));
      this.rowsContainer.style.height = `${contentHeight}px`;
    }

    renderStickyState(inputState) {
      const state = inputState;
      if (!state.length) {
        this.stickyContainer.hidden = false;
        this.stickyContainer.style.visibility = "hidden";
        this.reconcileStickyRows(this.getPrewarmedStickyState(), []);
        this.stickyContainer.style.height = "0px";
        this.renderedStickyState = [];
        return;
      }
      this.stickyContainer.hidden = false;
      this.stickyContainer.style.visibility = "visible";
      this.reconcileStickyRows(state, state);
      const height = state.reduce((bottom, entry) => Math.max(bottom, entry.position + entry.height), 0);
      this.stickyContainer.style.height = `${height}px`;
      this.renderedStickyState = state;
    }

    syncNaturalFocusOwnership(state) {
      const stickyNodeIds = new Set(state.map((entry) => entry.nodeId));
      Array.from(this.rowsContainer.children).forEach((row) => {
        row.toggleAttribute("inert", stickyNodeIds.has(row.dataset.nodeId));
      });
    }

    reconcileStickyRows(state, interactiveState = state) {
      const focused = this.stickyContainer.contains(document.activeElement) ? document.activeElement : null;
      const focusedRow = focused?.closest(".hierarchical-view-sticky-row");
      const focusedNodeId = focusedRow?.dataset.nodeId || null;
      const focusedSlot = Number.parseInt(focusedRow?.dataset.stickySlot || "0", 10);
      const existing = new Map(Array.from(this.stickyContainer.children).map((row) => [row.dataset.nodeId, row]));
      const desired = state.map((entry) => {
        let row = existing.get(entry.nodeId);
        const rendered = this.adapter.renderRow(entry.node, "sticky");
        if (row && row.tagName === rendered.tagName && row.namespaceURI === rendered.namespaceURI) {
          patchNode(row, rendered);
        } else {
          row = rendered;
        }
        row.hierarchicalNode = entry.node;
        row.classList.add("hierarchical-view-sticky-row");
        row.dataset.nodeId = entry.nodeId;
        row.dataset.treeDepth = String(entry.treeDepth);
        row.dataset.stickySlot = String(entry.stickySlot);
        if (row.style.top !== `${entry.position}px`) row.style.top = `${entry.position}px`;
        if (row.style.height !== `${entry.height}px`) row.style.height = `${entry.height}px`;
        const toggle = row.matches("[data-hierarchical-toggle]") ? row : row.querySelector("[data-hierarchical-toggle]");
        if (toggle && toggle.getAttribute("aria-expanded") !== String(entry.node.expanded)) {
          toggle.setAttribute("aria-expanded", String(entry.node.expanded));
        }
        return row;
      });
      const desiredRows = new Set(desired);
      Array.from(this.stickyContainer.children).forEach((row) => {
        if (!desiredRows.has(row)) row.remove();
      });
      desired.forEach((row, index) => {
        const current = this.stickyContainer.children[index];
        if (current !== row) this.stickyContainer.insertBefore(row, current || null);
      });
      this.syncNaturalFocusOwnership(interactiveState);
      if (!focusedNodeId || interactiveState.some((entry) => entry.nodeId === focusedNodeId)) return;
      const replacementEntry = interactiveState[Math.min(focusedSlot, interactiveState.length - 1)];
      const replacementRow = replacementEntry ? desired.find((row) => row.dataset.nodeId === replacementEntry.nodeId) : null;
      let focusTarget = replacementRow;
      if (focused?.dataset.candidateSort) {
        focusTarget = replacementRow?.querySelector(`[data-candidate-sort="${CSS.escape(focused.dataset.candidateSort)}"]`);
      } else if (focused?.dataset.assessmentSort) {
        focusTarget = replacementRow?.querySelector(`[data-assessment-sort="${CSS.escape(focused.dataset.assessmentSort)}"]`);
      }
      if (!focusTarget) {
        const naturalRow = this.rowsContainer.querySelector(`[data-node-id="${CSS.escape(focusedNodeId)}"]`);
        focusTarget = naturalRow?.matches("button, [tabindex]") ? naturalRow : naturalRow?.querySelector("button, [tabindex]");
      }
      focusTarget?.focus({ preventScroll: true });
    }

    onClick(event) {
      const row = event.target.closest("[data-node-id]");
      if (!row) return;
      const node = this.model.nodesById.get(row.dataset.nodeId);
      if (!node) return;
      const toggle = event.target.closest("[data-hierarchical-toggle]");
      if (toggle && node.children.length) {
        event.preventDefault();
        const scrollTop = this.viewport.scrollTop;
        const stickyEntry = this.stickyController.state.find((entry) => entry.nodeId === node.id);
        const collapseAnchor = node.expanded && stickyEntry ? Math.max(0, node.layoutTop - stickyEntry.position) : scrollTop;
        this.model.toggle(node.id);
        this.adapter.onExpandedChange?.(node, node.expanded);
        this.layout.recalculate();
        this.renderNaturalRows();
        this.viewport.scrollTop = collapseAnchor;
        this.stickyController.update();
        if (!this.stickyController.state.length) this.renderStickyState([]);
        return;
      }
      this.adapter.handleAction?.(node, event, row.closest(".hierarchical-view-sticky-row") ? "sticky" : "natural");
    }

    onKeyDown(event) {
      if (event.key !== "ArrowLeft" && event.key !== "ArrowRight") return;
      const row = event.target.closest("[data-node-id]");
      if (!row) return;
      const node = this.model.nodesById.get(row.dataset.nodeId);
      if (!node?.children.length) return;
      if (event.key === "ArrowLeft" && node.expanded || event.key === "ArrowRight" && !node.expanded) {
        event.preventDefault();
        const toggle = row.matches("[data-hierarchical-toggle]") ? row : row.querySelector("[data-hierarchical-toggle]");
        toggle?.click();
      }
    }

    onStickyWheel(event) {
      if (!event.deltaY) return;
      const multiplier = event.deltaMode === WheelEvent.DOM_DELTA_LINE ? 16 : event.deltaMode === WheelEvent.DOM_DELTA_PAGE ? this.viewport.clientHeight : 1;
      this.viewport.scrollTop += event.deltaY * multiplier;
      event.preventDefault();
    }

    destroy() {
      this.viewport.removeEventListener("scroll", this.handleScroll);
      this.viewport.removeEventListener("click", this.handleClick);
      this.viewport.removeEventListener("keydown", this.handleKeyDown);
      this.stickyContainer.removeEventListener("click", this.handleClick);
      this.stickyContainer.removeEventListener("keydown", this.handleKeyDown);
      this.stickyContainer.removeEventListener("wheel", this.handleWheel);
      this.viewport.replaceChildren();
      this.stickyContainer.replaceChildren();
      this.stickyContainer.style.removeProperty("height");
      this.stickyContainer.style.removeProperty("right");
      this.stickyContainer.style.removeProperty("visibility");
      this.stickyContainer.hidden = true;
    }
  }

  globalThis.WorkbenchHierarchicalView = {
    HierarchicalView,
    HierarchicalViewLayout,
    HierarchicalViewModel,
    transitionStickyMembership
  };
})();
