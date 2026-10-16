"use strict";

const STATUS_BAR_ENTRY_KINDS = ["standard", "success", "warning", "error"];

const STATUS_BAR_ENTRIES = Object.freeze([
  {
    key: "target",
    alignment: "left",
    element: "span",
    id: "target-chip",
    valueId: "status-target",
    value: "Resolving target",
    icon: "git-branch-compact",
    tooltip: "Promotion target",
    classes: ["target-chip"],
    truncationOwner: true
  },
  {
    key: "save",
    alignment: "left",
    element: "span",
    valueId: "save-indicator",
    value: "Draft not loaded",
    icon: "check-compact",
    tooltip: "Draft autosave state",
    classes: ["save-indicator"]
  },
  {
    key: "ruleIssues",
    alignment: "right",
    id: "rule-issues-status",
    valueId: "rule-issues-status-count",
    value: "0",
    icon: "warning-compact",
    tooltip: "Rule issues",
    ariaLabel: "Open rule issues",
    navigation: "issues",
    classes: ["rule-issues-status"],
    hidden: true
  },
  {
    key: "eligible",
    alignment: "right",
    valueId: "catalog-count",
    value: "0",
    icon: "collection",
    tooltip: "Eligible candidates",
    ariaLabel: "Show eligible candidates",
    navigation: "eligible"
  },
  {
    key: "excluded",
    alignment: "right",
    valueId: "status-excluded",
    value: "0",
    icon: "circle-slash-compact",
    tooltip: "Excluded assessments",
    ariaLabel: "Show excluded assessments",
    navigation: "excluded"
  },
  {
    key: "mapped",
    alignment: "right",
    valueId: "status-mapped",
    value: "0",
    icon: "link-multiple-16-filled",
    iconFamily: "fluent",
    tooltip: "Mapped Hosted rules",
    ariaLabel: "Show mapped Hosted rules",
    navigation: "mapped"
  },
  {
    key: "unmapped",
    alignment: "right",
    valueId: "status-unmapped",
    value: "0",
    icon: "link-dismiss-16-filled",
    iconFamily: "fluent",
    tooltip: "Not mapped",
    ariaLabel: "Show not mapped candidates",
    navigation: "unmapped"
  },
  {
    key: "plan",
    alignment: "right",
    valueId: "plan-count",
    value: "0",
    icon: "new-session",
    tooltip: "Promotion plan items",
    ariaLabel: "Open Promotion Plan",
    navigation: "plan"
  },
  {
    key: "capacity",
    alignment: "right",
    valueId: "status-headroom",
    value: "0",
    icon: "gauge-16-regular",
    iconFamily: "fluent",
    tooltip: "Hosted guidance headroom",
    ariaLabel: "Show Hosted guidance headroom",
    navigation: "capacity"
  },
  {
    key: "promotionApproval",
    alignment: "right",
    valueId: "preview-status",
    value: "Draft",
    icon: "shield-compact",
    tooltip: "Promotion approval status",
    ariaLabel: "Open Promotion Preview",
    navigation: "preview",
    classes: ["promotion-approval-status"],
    kind: "warning"
  }
]);

function createStatusBarIcon(name, family = "codicon") {
  if (!["codicon", "fluent"].includes(family)) throw new Error(`Unsupported status bar icon family: ${family}`);
  const svg = document.createElementNS("http://www.w3.org/2000/svg", "svg");
  svg.classList.add(family === "fluent" ? "fluent-icon" : "codicon");
  svg.setAttribute("aria-hidden", "true");
  const use = document.createElementNS("http://www.w3.org/2000/svg", "use");
  use.setAttribute("href", family === "fluent"
    ? `icons/fluent/sprite.svg#fluent-${name}`
    : `icons/codicons/sprite.svg#codicon-${name}`);
  svg.appendChild(use);
  return svg;
}

class WorkbenchStatusBarService {
  constructor(entries) {
    this.entries = entries;
    this.nodes = new Map();
  }

  render() {
    const containers = {
      left: document.querySelector(".status-left"),
      right: document.querySelector(".status-right")
    };
    if (!containers.left || !containers.right) throw new Error("Workbench status bar containers are unavailable");
    containers.left.replaceChildren();
    containers.right.replaceChildren();
    this.nodes.clear();

    for (const entry of this.entries) {
      if (this.nodes.has(entry.key)) throw new Error(`Duplicate Workbench status bar entry: ${entry.key}`);
      const node = document.createElement(entry.element || "button");
      if (node instanceof HTMLButtonElement) node.type = "button";
      node.classList.add("status-item", ...(entry.classes || []));
      if (node instanceof HTMLButtonElement) node.classList.add("clickable");
      if (entry.id) node.id = entry.id;
      if (entry.tooltip) node.dataset.workbenchTooltip = entry.tooltip;
      if (entry.ariaLabel) node.setAttribute("aria-label", entry.ariaLabel);
      if (entry.navigation) node.dataset.statusNavigation = entry.navigation;
      if (entry.truncationOwner) node.dataset.truncationOwner = "";
      node.hidden = Boolean(entry.hidden);
      node.appendChild(createStatusBarIcon(entry.icon, entry.iconFamily));
      const value = document.createElement("span");
      value.id = entry.valueId;
      value.textContent = entry.value;
      node.appendChild(value);
      containers[entry.alignment].appendChild(node);
      this.nodes.set(entry.key, node);
      this.update(entry.key, { kind: entry.kind || "standard" });
    }
  }

  update(key, update) {
    const node = this.nodes.get(key);
    if (!node) throw new Error(`Unknown Workbench status bar entry: ${key}`);
    const definition = this.entries.find((entry) => entry.key === key);
    if (Object.hasOwn(update, "text")) node.querySelector(`#${definition.valueId}`).textContent = String(update.text);
    if (Object.hasOwn(update, "tooltip")) {
      if (update.tooltip) node.dataset.workbenchTooltip = String(update.tooltip);
      else delete node.dataset.workbenchTooltip;
    }
    if (Object.hasOwn(update, "ariaLabel")) {
      if (update.ariaLabel) node.setAttribute("aria-label", String(update.ariaLabel));
      else node.removeAttribute("aria-label");
    }
    if (Object.hasOwn(update, "hidden")) node.hidden = Boolean(update.hidden);
    if (Object.hasOwn(update, "kind")) {
      if (!STATUS_BAR_ENTRY_KINDS.includes(update.kind)) throw new Error(`Unsupported Workbench status bar entry kind: ${update.kind}`);
      for (const kind of STATUS_BAR_ENTRY_KINDS) node.classList.remove(`${kind}-kind`);
      if (update.kind !== "standard") node.classList.add(`${update.kind}-kind`);
    }
    return node;
  }

  getEntry(key) {
    return this.nodes.get(key);
  }
}

const workbenchStatusBar = new WorkbenchStatusBarService(STATUS_BAR_ENTRIES);
