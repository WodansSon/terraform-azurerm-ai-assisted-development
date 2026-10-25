const { openWorkbench } = require("../helpers/workbench.cjs");

const behaviorIds = ["WB-UX-DETAILS-001"];

async function verifyDetailLayout(panel, assert, context) {
  const snapshot = await panel.evaluate((node) => {
    const audit = node.id === "assessment-results-detail";
    const sources = node.querySelector('[data-evidence-kind="sources"]');
    const coverage = node.querySelector('[data-evidence-kind="coverage"]');
    const evidence = node.querySelector("[data-assessment-evidence]");
    const heading = evidence?.querySelector(".assessment-details-heading");
    const info = evidence?.querySelector(".information-panel.assessment-context");
    const strip = evidence?.querySelector(".score-strip");
    const factors = evidence?.querySelector(".factor-groups");
    const order = [sources, ...(audit ? [coverage] : []), heading, info, strip, factors, node.querySelector(".proposed-rule-heading")];
    const actions = node.querySelector(".rule-actions");
    const editors = [...node.querySelectorAll("textarea.evidence-box")];
    const metrics = [...(strip?.querySelectorAll(".score-item") || [])];
    return {
      order: order.every((item, index) => item && (!index || order[index - 1].compareDocumentPosition(item) & Node.DOCUMENT_POSITION_FOLLOWING)),
      assistance: !node.querySelector("[data-rule-assistance]") && Boolean(document.querySelector("#rule-assistance-panel [data-rule-assistance]")),
      guidance: heading.nextElementSibling === info && info.nextElementSibling === strip && !info.querySelector("button"),
      metrics: metrics.map((item) => item.querySelector("span").textContent).join("|") === "Priority Score:|Token Cost:|Token Headroom:"
        && getComputedStyle(strip).gap === "12px" && metrics.every((item) => getComputedStyle(item).borderTopStyle === "solid"),
      rationale: node.querySelector("[data-assessment-explanation] strong")?.textContent === "Assessment rationale:",
      controls: audit ? !actions && !node.querySelector("[data-decision-field]")
        : Boolean(actions?.querySelector(".rule-actions-content") && actions.querySelector(".rule-actions-guidance")
          && editors.length === 2 && editors.every((editor) => editor.classList.contains("evidence-box"))),
      coverage: audit ? Boolean(coverage) : !coverage,
      noRelationshipChecks: !node.querySelector("[data-manual-relationship-progress], [data-maintainer-resolution], [data-relationship-review-actions]")
    };
  });
  for (const [name, passed] of Object.entries(snapshot)) assert(passed, `${context} violates the shared Details layout: ${name}`);
}

async function run({ page, baseUrl, assert }) {
  await openWorkbench(page, baseUrl);
  await page.evaluate(() => {
    const candidate = state.candidates.find((item) => item.assessment.hostedApplicable);
    selectCandidate(candidate.key);
    showCandidatePane("details");
  });
  await verifyDetailLayout(page.locator("#assessment-panel"), assert, "Candidate Details");
  await page.evaluate(() => {
    const excluded = state.assessedCandidates.find((item) => !item.assessment.hostedApplicable && !getApplicabilityOverride(item));
    if (!excluded) throw new Error("Details layout requires an excluded assessment fixture.");
    setWorkspaceTab("assessment-results");
    selectAssessmentResult(excluded.key);
    showAssessmentPane("details");
  });
  await verifyDetailLayout(page.locator("#assessment-results-detail"), assert, "Assessment Results");
  return { behaviorIds };
}

module.exports = { behaviorIds, run };
