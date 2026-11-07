const { openWorkbench, revealCandidate } = require("../helpers/workbench.cjs");

const behaviorIds = ["WB-UX-CANDIDATE-007"];

async function run({ page, baseUrl, assert, playback }) {
  await openWorkbench(page, baseUrl);
  const expected = await page.evaluate(() => {
    const candidate = state.candidates.find((item) => item.members.length > 0);
    if (!candidate) throw new Error("A parent candidate with contributing members is required");
    return {
      candidateKey: candidate.key,
      memberCount: candidate.members.length,
      firstMemberId: candidate.members[0].source.id,
      firstMemberText: candidate.members[0].source.text,
      firstMeaningRationale: candidate.members[0].meaningCoverageRationale
    };
  });

  await playback.show(page, "Parent candidate · contributing rule evidence");
  await revealCandidate(page, expected.candidateKey);
  await page.locator(`[data-candidate-key="${expected.candidateKey}"] .candidate-tree-copy`).click();
  await page.waitForFunction(() => document.querySelector("#assessment-panel .detail-identity")?.textContent.toLowerCase().includes("synthesized recommendation"));

  const panel = page.locator("#assessment-panel");
  assert(await panel.locator(".contributing-rule").count() === expected.memberCount, "Parent candidate does not render every contributing rule");
  assert((await panel.locator(".contributing-rule").first().textContent()).includes(expected.firstMemberId), "Contributing rule identity is missing");
  assert((await panel.locator(".contributing-rule .evidence-box").first().textContent()).trim() === expected.firstMemberText.trim(), "Contributing source text is not preserved");
  assert((await panel.locator(".contributing-rule-meaning").last().textContent()).includes(expected.firstMeaningRationale), "Parent meaning-preservation rationale is missing");
}

module.exports = { name: "Parent candidate members", behaviorIds, viewport: { width: 1280, height: 900 }, run };
