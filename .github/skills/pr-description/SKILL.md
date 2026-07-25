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
- When stale-base recovery ran, the accepted local candidate origin and recovered net scope instead of the inflated named-main scope.
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
- Trust the prompt's accepted recovered scope, including a scope recovered from a mainline integration merge's second parent; do not reintroduce paths excluded as incorporated history.
- Identify each user-facing Terraform surface and service package.
- Consume the prompt's lightweight relationship graph and select one coherent primary surface or connected surface set.
- Treat directly evidenced cross-service consumers, shared provider or framework helpers, common abstractions, and dependent resources as one change intent regardless of package boundaries.
- Return control to the prompt for a hard stop only when two or more independent user-facing intents remain and no one title plus coherent description can represent them honestly. Never infer unrelated intent from package, path, file, or surface counts alone.
- Keep registration, tests, documentation, Resource Identity, List Resource, generated, and vendored changes subordinate when they support the primary change.
- Keep title-subordinate existing Resource, Data Source, Action, and provider changes eligible for body, PR type, and changelog treatment when their implementation evidence proves distinct user-facing behavior.
- Build one concise material behavior inventory for every independently user-facing surface. Capture management or query scope, meaningful lifecycle semantics, plan/read/import type or ownership guards, computed outputs whose purpose matters, list filters or enumeration scope, state normalization or drift-prevention behavior, and removal or disable transitions that actively clear API-retained values.
- Represent every material behavior with one or more atomic records containing its owning Terraform surface, exact lifecycle path or paths, behavior kind, and observable outcome. Keep retry, wait, validation, guard, clear, normalization, and other behavior kinds separate unless evidence proves each one for the same owner and path.
- Do not transfer behavior across related surfaces, shared helpers, or lifecycle paths. Combine surfaces or paths in one sentence only for the intersection of atomic records proven for every named surface and path.
- Consume compact evidence from changed custom request marshallers, payload builders, workaround clients, or equivalent update helpers when they decide whether configured values are omitted or actively cleared. Record only the observable clear behavior in the inventory.
- Preserve every independently configured retained-value family proven by the clear path; do not collapse several families into only the one observed by polling.
- Require changed enabling implementation evidence before classifying compatibility between a new surface and an existing consumer as changed behavior. Do not infer an enhancement from a new object flowing through an unchanged schema, ID, or association path.
- Classify proven corrections to premature lifecycle success, failed cleanup, valid operations that previously failed or hung, drift, or API-retained residual state as bug fixes on the owning existing surface. Keep polling, serialization, and client refactors subordinate when they do not prove a corrected user-facing failure mode.
- Exclude ordinary client construction, registration, helper names, SDK shims, generated code, and vendoring mechanics from that inventory unless they are independently user-facing. Do not exclude observable clear behavior merely because a custom marshaller, payload helper, or SDK workaround implements it.

### Select the title

- Apply `PRDESC-TITLE-*` once in fixed precedence.
- Produce exactly one title and one concise evidence-based explanation.
- Do not propose alternatives.

### Draft the template body

- Assemble the body by inserting evidence-backed responses into the exact current pull request template. Do not reconstruct immutable lines from memory or another familiar template.
- Preserve every immutable template line verbatim, including prose, links, URLs, comments, headings, checklist text, Community Note content, rollback text, and the final note.
- Before handoff, compare ordered URL tokens in immutable draft lines with the corresponding loaded template lines and restore every mismatch, including valid-looking replacement URLs.
- Change only evidence-populated response areas, example or claim placeholders, and checklist markers from `[ ]` to `[x]`.
- Describe what changed and why from compact implementation evidence.
- Before finalizing description or changelog wording, expand grouped subjects, lifecycle-path lists, and conjunctions into individual claims. Retain each claim only when one atomic record matches its owner, exact path, behavior kind, and observable outcome.
- Represent every item in the material behavior inventory once. Combine related behavior into compact prose and do not replace it with supporting plumbing detail.
- Keep changelog ownership one-to-one: render each existing Resource, Data Source, Action, or provider surface with distinct behavior on its own line, even when multiple surface kinds share one Terraform name.
- Keep existing-surface changelog owner tokens undecorated; only the Terraform name uses code formatting.
- Do not grade correctness, surface defects, prescribe fixes, speculate about missing tests, or narrate every schema field and CRUD operation.
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
