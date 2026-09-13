const { openWorkbench } = require("../helpers/workbench.cjs");

const behaviorIds = ["WB-UX-SEARCH-001"];

async function getSearchState(page) {
  return page.evaluate(() => {
    const roots = candidateHierarchicalView.model.roots.filter((node) => node.data.sourceType !== "overrides");
    const match = document.querySelector("#candidate-list .candidate-tree-row.search-match");
    const matchNode = candidateHierarchicalView.model.nodes.find((node) => node.data?.candidate?.key === match?.dataset.candidateKey);
    const scroller = document.querySelector("#candidate-list");
    const scrollerRect = scroller.getBoundingClientRect();
    const matchRect = match?.getBoundingClientRect();
    return {
      rootTypes: roots.map((root) => root.data.sourceType),
      openRootTypes: roots.filter((root) => root.expanded).map((root) => root.data.sourceType),
      matchKey: match?.dataset.candidateKey || null,
      matchVisible: Boolean(matchRect && matchRect.bottom > scrollerRect.top && matchRect.top < scrollerRect.bottom),
      openParentCount: matchNode ? [...function* () { for (let node = matchNode.parent; node; node = node.parent) if (node.children.length && node.expanded) yield node; }()].length : 0
    };
  });
}

async function run({ page, baseUrl, assert, playback }) {
  await openWorkbench(page, baseUrl);
  await playback.show(page, "Candidate search navigation");

  const initialRootTypes = await page.evaluate(() => candidateHierarchicalView.model.roots.map((root) => root.data.sourceType));
  assert(["interactive", "upstream", "maintainer"].every((type) => initialRootTypes.includes(type)), "initial tree does not contain all source roots");

  const interactiveCandidate = await page.evaluate(() => state.candidates.find((candidate) => candidate.sourceType === "interactive").id);
  await page.locator("#search-input").fill(interactiveCandidate);
  await page.waitForFunction(() => Boolean(document.querySelector("#candidate-list .candidate-tree-row.search-match")));
  const interactiveState = await getSearchState(page);
  assert(["interactive", "upstream", "maintainer"].every((type) => interactiveState.rootTypes.includes(type)), "Interactive search removed an unrelated source root");
  assert(interactiveState.openRootTypes.includes("interactive") && interactiveState.openParentCount >= 2, "Interactive search did not expand the matching source and category path");
  assert(interactiveState.matchVisible, "Interactive search result was not scrolled into view");

  await page.locator("#search-input").fill("guide-new-resource");
  await page.waitForFunction(() => document.querySelector("#candidate-list .candidate-tree-row.search-match")?.dataset.candidateKey?.startsWith("upstream:guide-new-resource:"));
  const contributorState = await getSearchState(page);
  assert(["interactive", "upstream", "maintainer"].every((type) => contributorState.rootTypes.includes(type)), "Contributor search removed an unrelated source root");
  assert(contributorState.openRootTypes.includes("upstream") && contributorState.openParentCount >= 2, "Contributor search did not expand the matching source and document path");
  assert(contributorState.matchVisible, "Contributor search result was not scrolled into view");

  await page.locator("#search-input").fill("");
  await page.waitForFunction(() => !document.querySelector("#candidate-list .candidate-tree-row.search-match"));
  const clearedRootTypes = await page.evaluate(() => candidateHierarchicalView.model.roots.map((root) => root.data.sourceType));
  assert(["interactive", "upstream", "maintainer"].every((type) => clearedRootTypes.includes(type)), "Clearing search changed the source-root set");
}

module.exports = { name: "candidate search navigation", behaviorIds, viewport: { width: 1440, height: 900 }, run };
