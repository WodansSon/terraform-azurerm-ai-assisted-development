import test from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { createContext, runInContext } from "node:vm";

const source = readFileSync(new URL("../../workbench/app.js", import.meta.url), "utf8");

function client() {
  const context = createContext({
    structuredClone,
    document: { addEventListener() {} },
    window: { matchMedia: () => ({ matches: false }) },
    navigator: { userAgent: "Desktop" }
  });
  runInContext(source, context);
  return code => runInContext(code, context);
}

function editingControls() {
  const run = client();
  run(`
    const saved = { proposedText: "Saved wording", action: "update", rationale: "Saved rationale" };
    const editor = { value: saved.proposedText };
    const rationale = { value: saved.rationale, setAttribute() {} };
    const save = {};
    const undo = {};
    const restore = {};
    const decisionSave = {};
    const guidance = {};
    const retirement = {};
    const model = {};
    const radio = { dataset: { ruleAction: "update" }, checked: true, closest: () => ({}) };
    const fieldset = { querySelectorAll: () => [radio], setAttribute() {} };
    const controls = {
      '[data-decision-field="proposedText"]': editor,
      '[data-decision-field="rationale"]': rationale,
      '[data-proposed-text-save]': save,
      '[data-proposed-text-undo]': undo,
      '[data-proposed-text-reset]': restore,
      '[data-rationale-save]': decisionSave,
      '[data-rule-action]:checked': radio,
      '.action-options': fieldset,
      '.rule-actions-guidance p': guidance
    };
    elements["assessment-panel"] = {
      querySelector: selector => controls[selector] || null,
      querySelectorAll: selector => selector === "[data-rule-action]" ? [radio]
        : selector === "[data-retire-hosted-rule]" ? [retirement]
          : selector === "[data-implementation-model]" ? [model] : []
    };
    const candidate = { key: "example", recommendation: { ruleText: "Original wording" } };
    getActiveCandidate = () => candidate;
    getDecision = () => saved;
    defaultDecision = () => ({ proposedText: "Original wording", action: "no-change" });
    getAllowedActions = () => ["update"];
    getCatalogStatus = () => ({ key: "mapped" });
    hasHostedTextChange = () => true;
    syncAssessmentActionControls = () => {};
    syncAssessmentRationaleControls = () => { rationale.disabled = false; decisionSave.disabled = false; };
    syncImplementationModelControls = () => { model.disabled = false; };
    syncRelationshipReviewControls = () => {};
    renderPlan = () => {};
    renderPreview = () => {};
    renderAssessment = () => { editor.value = saved.proposedText; radio.dataset.ruleAction = saved.action; rationale.value = saved.rationale; };
    editor.focus = () => {};
  `);
  return run;
}

test("dirty wording locks dependent controls and unlocks them on return to saved wording", () => {
  const run = editingControls();
  run('editor.value = "Unsaved wording"; syncProposedRuleControls(candidate)');
  assert.equal(run("save.disabled"), false);
  for (const name of ["fieldset", "rationale", "decisionSave", "retirement", "model"]) {
    assert.equal(run(`${name}.disabled`), true, name);
  }
  assert.equal(run("guidance.textContent"), "Save or undo the wording changes before changing Rule Actions.");
  run("editor.value = saved.proposedText; syncProposedRuleControls(candidate)");
  for (const name of ["fieldset", "rationale", "decisionSave", "retirement", "model"]) {
    assert.equal(run(`${name}.disabled`), false, name);
  }
  assert.equal(run("guidance.textContent"), "Choose one action. Hosted catalog status determines which actions are available.");
});

test("Undo restores saved wording and action, clears only pending rationale, and does not write", async () => {
  const run = editingControls();
  run('editor.value = "Unsaved wording"; radio.dataset.ruleAction = "defer"; rationale.value = "Pending rationale"');
  await run('handleAssessmentClick({ target: { closest: selector => selector === "[data-proposed-text-undo]" ? {} : null } })');
  assert.equal(run("editor.value"), "Saved wording");
  assert.equal(run("radio.dataset.ruleAction"), "update");
  assert.equal(run("rationale.value"), "");
  assert.equal(run("saved.rationale"), "Saved rationale");
  assert.equal(run("undo.disabled"), true);
});

test("Restore saves one original baseline atomically, preserves unrelated work, and retains edits on failure", async () => {
  const run = client();
  run(`
    const candidate = { key: "example", hash: "source" };
    const editor = { value: "Pending wording", isConnected: true };
    const saved = {
      sourceHash: "source", proposedText: "Saved wording", action: "update", rationale: "Saved rationale",
      inPlan: true, planMembershipSource: "bulk", bulkOperationId: "batch", retireHostedRuleIds: [], implementationModels: []
    };
    const baseline = {
      ...saved, proposedText: "Original wording", action: "no-change", rationale: "",
      inPlan: false, planMembershipSource: null, bulkOperationId: null
    };
    const initial = {
      decisions: { example: saved, other: { proposedText: "Other saved wording" } },
      bulkOperations: [{ id: "batch", candidateKeys: ["example", "other"] }],
      applicabilityOverrides: { other: { rationale: "Other override" } }
    };
    state.session = structuredClone(initial);
    elements["assessment-panel"] = { querySelector: () => editor };
    getDecision = () => saved;
    defaultDecision = () => baseline;
    getAllowedActions = () => ["no-change", "update"];
    let written;
    let failure;
    persistSession = async (snapshot, guard) => { guard?.(); written = structuredClone(snapshot); };
    showToast = message => { failure = message; };
  `);
  assert.equal(await run('persistProposedRuleText(candidate, "Original wording", true)'), true);
  assert.equal(run("written.decisions.example.action"), "no-change");
  assert.equal(run("written.decisions.example.inPlan"), false);
  assert.equal(run("written.decisions.example.rationale"), "");
  assert.equal(run("written.decisions.other.proposedText"), "Other saved wording");
  assert.equal(run("written.applicabilityOverrides.other.rationale"), "Other override");
  assert.equal(run('written.bulkOperations[0].candidateKeys.join(",")'), "other");
  run('state.session = structuredClone(initial); persistSession = async () => { throw new Error("Synthetic failed write"); }');
  assert.equal(await run('persistProposedRuleText(candidate, "Original wording", true)'), false);
  assert.equal(run("state.session.decisions.example.proposedText"), "Saved wording");
  assert.equal(run("editor.value"), "Pending wording");
  assert.match(run("failure"), /not saved/);
});

test("shortcuts stay editor-scoped, leave native Undo alone, and intercept Save only when available", () => {
  const run = client();
  run(`
    const button = { disabled: false, clicks: 0, click() { this.clicks++; } };
    let selector;
    let prevented;
    elements["assessment-panel"] = { querySelector: value => { selector = value; return button; } };
    function press(key, field = "proposedText", modifiers = {}) {
      prevented = false;
      selector = null;
      handleAssessmentEditorKeydown({
        ctrlKey: true, key, ...modifiers,
        target: { matches: value => value === '[data-decision-field="' + field + '"]' },
        preventDefault() { prevented = true; }
      });
    }
  `);
  run('press("s")');
  assert.equal(run("selector"), "[data-proposed-text-save]");
  assert.equal(run("prevented"), true);
  run('button.disabled = true; press("s")');
  assert.equal(run("prevented"), false);
  run('button.disabled = false; press("s", "rationale")');
  assert.equal(run("selector"), "[data-rationale-save]");
  for (const key of ["z", "r", "u", "s"]) {
    run(`press("${key}", "unrelated")`);
    assert.equal(run("prevented"), false);
  }
  run('press("z")');
  assert.equal(run("prevented"), false);
  run('press("u")');
  assert.equal(run("selector"), "[data-proposed-text-undo]");
  run('press("r")');
  assert.equal(run("selector"), "[data-proposed-text-reset]");
  run('press("s", "proposedText", { altKey: true })');
  assert.equal(run("prevented"), false);
});
