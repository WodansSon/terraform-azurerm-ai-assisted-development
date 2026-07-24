---
name: pr-description
description: "Draft an AzureRM pull request title and copy-ready body from a compact current-branch evidence set."
user-invocable: false
---

# PR Description Drafting Method

## Scope

Use this skill only when routed by `.github/prompts/draft-pr-description.prompt.md` inside `terraform-provider-azurerm` or a fork with the same repository name and expected structure.

This skill turns one compact local evidence set into one draft. It does not perform repository discovery, GitHub searches, network refreshes, policy reloads, tests, or final presentation.

## Required sources

- Read `.github/instructions/pr-description-compliance-contract.instructions.md` to EOF.
- Verify its final non-empty line is `<!-- PRDESC-CONTRACT-EOF -->`.
- Read `.github/instructions/pr-description-draft.schema.json` to EOF.
- Use only evidence collected by the current prompt invocation.
- Apply relevant `PRDESC-*` rules from the contract.

## Input handoff

Consume:

- Canonical worktree, direct Git branch, full `HEAD`, selected local base, and merge base.
- Complete changed-path inventory and non-ignored untracked paths.
- Current branch commit subjects.
- The current worktree's pull request template.
- Compact implementation evidence for every independently user-facing changed surface, including title-subordinate existing surfaces.
- Matching registration, test, documentation, Resource Identity, List Resource, and security evidence when applicable.
- Explicit developer-provided facts and validation results.

Do not run tools, rediscover the repository, or request audit-only evidence.
Do not request exact-path searches or test-function inventories when the prompt already supplied matching changed paths.

## Drafting procedure

### Classify the change-set

- Normalize changed paths to added, modified, renamed, copied, deleted, or untracked.
- Identify each user-facing Terraform surface and service package.
- Select one coherent primary surface or related surface set.
- Keep registration, tests, documentation, Resource Identity, List Resource, generated, and vendored changes subordinate when they support the primary change.
- Keep title-subordinate existing Resource, Data Source, Action, and provider changes eligible for body, PR type, and changelog treatment when their implementation evidence proves distinct user-facing behavior.
- Return control to the prompt for the unrelated-primary-change hard stop.

### Select the title

- Apply `PRDESC-TITLE-*` once in fixed precedence.
- Produce exactly one title and one concise evidence-based explanation.
- Do not propose alternatives.

### Draft the template body

- Start from the exact current pull request template.
- Preserve every immutable template line verbatim, including prose, links, URLs, comments, headings, checklist text, Community Note content, rollback text, and the final note.
- Change only evidence-populated response areas, example or claim placeholders, and checklist markers from `[ ]` to `[x]`.
- Describe what changed and why from compact implementation evidence.
- Populate existing-surface, testing, changelog, related issue, security, rollback, and type sections under the contract.
- Include only explicit issue references from developer input or current-branch commit subjects.
- Include the minimal AI disclosure required by `PRDESC-BODY-004`.

### Decide checklist states

- Leave personal acknowledgements, duplicate PR review, and issue review unchecked.
- Check description and documentation items when content evidence proves them complete.
- Check authored-test items when matching changed tests exist, independently of whether tests ran.
- Check test-passed items only from explicit successful results.
- Check applicable PR types from classified behavior and always check `AI Assisted`.

### Build evidence notes

- Include only concise facts the developer should review before pasting, such as missing applicable docs or tests, absent test execution, unresolved security impact, or explicit input still required.
- Do not include process narration, unavailable searches, stale remote refs, or internal classification detail.
- Use an empty array when no unresolved notes remain.

## Output handoff

Emit one object conforming to `.github/instructions/pr-description-draft.schema.json`:

- Use `schemaVersion=2.0`.
- Include `repository`, `title`, `whyThisTitle`, `draftBody`, and `evidenceNotes`.
- Use repo-relative paths only inside generated body content.
- Do not render the four-section user response.

Return the payload to the prompt for one stability check, in-memory schema conformance check, and presentation. Do not ask the prompt to reconstruct or serialize the payload through a terminal command.

<!-- PRDESC-SKILL-EOF -->
