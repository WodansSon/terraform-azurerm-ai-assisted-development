---
description: "Shared PR description drafting compliance contract used by the draft-pr-description prompt and pr-description skill."
---

# PR Description Drafting Compliance Contract

## Consumers

- Consumer: `.github/prompts/draft-pr-description.prompt.md`
  - Role: orchestration, hard stops, payload validation, and presentation
  - Requires EOF Load: yes
- Consumer: `.github/skills/pr-description/SKILL.md`
  - Role: scope classification, evidence application, and draft payload production
  - Requires EOF Load: yes

## Canonical sources of truth (precedence)

- Explicit developer input for branch intent, issue references, breaking-change impact, and validation evidence
- Direct Git evidence from the validated current worktree
- Current branch diff, changed paths, commit messages, and non-ignored untracked files
- The current worktree's `.github/pull_request_template.md` for body shape and checklist wording
- This contract for stable AzureRM title, checklist, changelog, evidence, and output rules

Conflict resolution:

- Explicit branch or worktree input outranks the current checkout; otherwise direct Git owns branch identity.
- Direct Git outranks editor, workspace, source-control, and pull request metadata.
- Current changed-file evidence owns implementation, documentation, and test-existence claims.
- Explicit current-run validation output or developer-provided results own test-execution claims.
- The current template owns body shape; this contract owns how evidence fills that shape.
- The prompt owns exact hard-stop strings and presentation mechanics but must not weaken this contract.
- The skill owns drafting procedure but must not redefine this contract.
- The schema owns the lean handoff shape only and must not introduce policy defaults.

## Rule IDs

- `PRDESC-PRE-*`: fresh-run, repository, branch, and stability checks
- `PRDESC-BASE-*`: local comparison-base resolution
- `PRDESC-SCOPE-*`: change collection and surface classification
- `PRDESC-EVID-*`: evidence and validation claims
- `PRDESC-TITLE-*`: title selection and formatting
- `PRDESC-BODY-*`: template preservation and body content
- `PRDESC-CHECK-*`: checklist decisions
- `PRDESC-CHANGELOG-*`: changelog eligibility and rendering
- `PRDESC-ISSUE-*`: confirmed issue handling
- `PRDESC-OUT-*`: payload and final output semantics
- `PRDESC-FAIL-*`: required failure behavior

## Evidence hierarchy

- Highest: explicit developer input and successful current-run command output
- High: direct Git identity, changed paths, compact diff content, and untracked file content
- Medium: current branch commit messages and repository structure
- Template authority: the current worktree's pull request template
- Disallowed: stale editor branch metadata, guessed intent, assumed test execution, guessed issue linkage, and assumed breaking-change impact

## Preflight rules

### PRDESC-PRE-001: Start from current evidence

- Treat each invocation as a fresh run.
- Reuse complete evidence within the run and do not repeat commands or reads.
- **Provenance**: Local safeguard.
- **Evidence**:
  - A fresh local snapshot avoids stale drafts without requiring a repository audit

### PRDESC-PRE-002: Restrict drafting to AzureRM

- Require `terraform-provider-azurerm` or a fork with the same repository name, remotes, and expected provider structure.
- Reject `main` and empty change-sets.
- **Provenance**: Local safeguard.
- **Evidence**:
  - The title, template, checklist, and changelog rules are AzureRM-specific

### PRDESC-PRE-003: Trust direct Git branch evidence

- Use an explicit developer-supplied branch or worktree path when present.
- Otherwise use `git branch --show-current` from the validated current worktree.
- Treat conflicting editor, workspace, source-control, and pull request metadata as advisory and non-blocking.
- Do not search for another checkout unless the developer explicitly selected one.
- **Provenance**: Local safeguard.
- **Evidence**:
  - Editor metadata can lag behind an actual branch switch

### PRDESC-PRE-004: Preserve repository state and minimize rounds

- Use read-only Git and file inspection only.
- Do not fetch, pull, merge, rebase, checkout, commit, push, reset, clean, edit files, or run tests.
- Display exact terminal commands under `[Read-only] {{PURPOSE}}`.
- Collect repository identity, branch, status, and local-base candidates in one fixed direct-Git batch, then collect the selected merge base, committed paths, working-tree paths, untracked paths, and commit subjects in one fixed direct-Git batch.
- Issue each fixed Git batch once as the prompt's exact one-line semicolon-separated command string. Do not first issue newline-separated commands, reformat a successful call, or retry a batch in alternate shell syntax.
- If a fixed Git batch returns incomplete output, hard-stop instead of improvising another command shape.
- Terminal batches may contain only the literal read-only Git commands required by the prompt. Do not generate PowerShell or shell variables, loops, conditionals, script blocks, here-strings, file reads, string replacement, JSON construction, or schema-validation programs.
- Use tool-native file reads and searches for template and implementation evidence.
- Build one complete Phase 2 read plan from the changed-path inventory, then read independent user-facing implementation, test, documentation, registration, Resource Identity, and List Resource evidence in one concurrent tool batch.
- Read a known changed file directly. Do not search for its path, enumerate test functions merely to prove changed test coverage, list its service directory, or split implementation, test, and documentation reads into successive rounds.
- Do not reload upstream contributor guides during drafting; this checked-in contract owns their stable drafting rules.
- **Provenance**: Local safeguard.
- **Evidence**:
  - Drafting is a developer shortcut and should not reproduce maintainer audit work

### PRDESC-PRE-005: Use a cheap stability guard

- Capture full `HEAD` and `git status --porcelain=v1 --untracked-files=all` during initial evidence collection.
- Immediately before rendering, collect those same two values once.
- Hard-stop when either value differs; do not restart the workflow automatically.
- Do not hash full diff or untracked-file contents solely to draft a pull request description.
- **Provenance**: Local safeguard.
- **Evidence**:
  - A branch and status guard catches common concurrent changes without two expensive full-content fingerprints

## Comparison-base rules

### PRDESC-BASE-001: Use an existing local base

- Select the first usable local ref in this order: `upstream/main`, `origin/main`, local `main`.
- Do not refresh remote-tracking refs during drafting.
- Record the selected ref and commit in the lean handoff.
- **Provenance**: Local safeguard.
- **Evidence**:
  - A local base is sufficient for a useful draft and avoids network latency or repository metadata changes

### PRDESC-BASE-002: Diff from the merge base

- Resolve the common ancestor between the selected local base and `HEAD`.
- Use it as the tracked change origin for committed, staged, and unstaged work.
- **Provenance**: Local safeguard.
- **Evidence**:
  - Merge-base scope isolates the current branch change-set

## Scope rules

### PRDESC-SCOPE-001: Collect the complete local change-set once

- Combine the selected-base-to-`HEAD` name/status inventory with the `HEAD`-to-working-tree name/status inventory.
- Include non-ignored untracked files from `git ls-files --others --exclude-standard`.
- Preserve added, modified, renamed, copied, deleted, and untracked status.
- Collect current branch commit subjects for explicit issue references and supporting context.
- **Provenance**: Local safeguard.
- **Evidence**:
  - The draft must include committed and local in-progress changes

### PRDESC-SCOPE-002: Read only material evidence

- Inspect compact implementation evidence for every independently user-facing changed surface, including title-driving new surfaces and title-subordinate changes to existing Resources, Data Sources, Actions, or provider behavior.
- Inspect only companion registration, tests, documentation, Resource Identity, List Resource, and security evidence needed for body or checklist decisions.
- Treat matching changed test paths as sufficient evidence that tests were authored. Read test content only when one material coverage claim cannot be resolved from paths and implementation evidence.
- Search only when the complete changed-path inventory does not identify the owning file or symbol. Do not search for an exact path already present in that inventory.
- Do not emit or reread one repository-wide patch.
- **Provenance**: Local safeguard.
- **Evidence**:
  - Targeted reads preserve drafting quality without turning the run into code review

### PRDESC-SCOPE-003: Keep companions subordinate

- Treat tests, documentation, registration, Resource Identity, required List Resource support, generated code, and vendored SDK changes as companions when they support one primary change.
- Do not classify a changed existing Terraform surface as a companion merely because a new surface outranks it for title selection. Preserve distinct user-facing enhancement or bug-fix behavior for the body, PR type, and changelog.
- Ignore generated and vendored paths for title dominance unless the PR primarily updates SDK, API, dependency, or generated code.
- **Provenance**: Published upstream standard.
- **Evidence**:
  - `https://github.com/hashicorp/terraform-provider-azurerm/tree/main/contributing/topics/guide-new-resource.md`
  - `https://github.com/hashicorp/terraform-provider-azurerm/tree/main/contributing/topics/guide-resource-identity.md`
  - `https://github.com/hashicorp/terraform-provider-azurerm/tree/main/contributing/topics/guide-list-resource.md`

### PRDESC-SCOPE-004: Stop on unrelated primary changes

- Hard-stop when unrelated primary changes span service packages.
- Do not stop when multiple surfaces are required companions of one coherent primary implementation.
- **Provenance**: Local safeguard.
- **Evidence**:
  - One deterministic title cannot accurately represent unrelated primary changes

## Evidence rules

### PRDESC-EVID-001: Make only supported claims

- Support claims with changed paths, compact diffs, commit subjects, explicit developer input, current-run command output, or the current template.
- Use `Needs contributor input.` when a material fact cannot be proven.
- **Provenance**: Local safeguard.
- **Evidence**:
  - Conservative drafting prevents unsupported contributor claims

### PRDESC-EVID-002: Separate test existence from execution

- Determine whether matching tests exist from changed-file and compact test evidence.
- Claim tests passed only from successful current-run output or explicit developer-provided command and result evidence.
- Do not treat test files, comments, commit messages, or prior PR text as proof that tests ran.
- **Provenance**: Published upstream standard.
- **Evidence**:
  - `https://github.com/hashicorp/terraform-provider-azurerm/tree/main/contributing/topics/guide-opening-a-pr.md`

### PRDESC-EVID-003: Keep absent validation visible but non-blocking

- When no test result is available, leave execution-dependent checklist items unchecked.
- State briefly in `Testing` that tests were not run during drafting and summarize matching coverage only when changed-file evidence proves it exists.
- **Provenance**: Local safeguard.
- **Evidence**:
  - Draft generation must remain useful without automatically running acceptance tests

## Title rules

### PRDESC-TITLE-001: Select one title by fixed precedence

- Apply this order: new Resource plus same-name Data Source, new Resource, new standalone Data Source, new List Resource, new Action or provider feature, bug fix, enhancement, SDK/API/dependency update, contributor guidance, documentation, CI or maintenance.
- Supporting surfaces do not compete with the primary surface.
- **Provenance**: Inferred maintainer convention.
- **Evidence**:
  - Stable precedence makes the title repeatable

### PRDESC-TITLE-002: Use exact new-surface shapes

- Use ``New (Data Source|Resource) - `{{RESOURCE_NAME}}``` for one Terraform name introducing both surfaces.
- Treat `(Data Source|Resource)` as literal title text. Do not render `New Resource and Data Source -`, `New Data Source and Resource -`, or another natural-language variant.
- Use ``New Resource: `{{RESOURCE_NAME}}``` for a new Resource.
- Use ``New Data Source: `{{DATA_SOURCE_NAME}}``` for a standalone Data Source.
- Use ``New List Resource: `{{RESOURCE_NAME}}``` for List Resource support added to an existing Resource.
- Do not add `List Resource` to a new Resource title when it is a required companion.
- **Provenance**: Published upstream standard.
- **Evidence**:
  - `https://github.com/hashicorp/terraform-provider-azurerm/tree/main/contributing/topics/guide-opening-a-pr.md`

### PRDESC-TITLE-003: Make existing-surface titles concrete

- Name the affected Terraform surface and use concrete wording such as `add support for`, `improve validation for`, or `correctly populate`.
- Use `Data Source:`, `List Resource:`, `Contributing:`, or `Docs:` when needed for clarity.
- Do not use bracketed prefixes unless repository guidance requires them.
- **Provenance**: Published upstream standard.
- **Evidence**:
  - `https://github.com/hashicorp/terraform-provider-azurerm/tree/main/contributing/topics/guide-opening-a-pr.md`

### PRDESC-TITLE-004: Reject vague titles

- Reject titles equivalent to `fix bug`, `fixes #1234`, `new resource`, or `upgrade sdk`.
- **Provenance**: Published upstream standard.
- **Evidence**:
  - `https://github.com/hashicorp/terraform-provider-azurerm/tree/main/contributing/topics/guide-opening-a-pr.md`

## Body rules

### PRDESC-BODY-001: Preserve the current template

- Start from the current worktree's `.github/pull_request_template.md`.
- Preserve every template line verbatim unless that line is an evidence-populated response area, an example or claim placeholder being replaced, or a checklist marker changing only from `[ ]` to `[x]`.
- Do not rewrite, shorten, normalize, or repair template prose, links, URLs, comments, headings, checklist text, the Community Note, the rollback plan, or the final note.
- Replace examples and placeholders that could be mistaken for contributor claims.
- Before rendering, compare immutable template lines with the already-loaded template and restore any mismatch in memory.
- **Provenance**: Local safeguard.
- **Evidence**:
  - The checked-out template is the body the developer will submit against
  - `https://github.com/hashicorp/terraform-provider-azurerm/blob/main/.github/pull_request_template.md`

### PRDESC-BODY-002: Explain what and why

- Describe the observable change, primary Terraform surfaces, material companion behavior, and evidence-supported reason.
- Include breaking impact and upgrade steps only when explicitly confirmed.
- **Provenance**: Published upstream standard.
- **Evidence**:
  - `https://github.com/hashicorp/terraform-provider-azurerm/tree/main/contributing/topics/guide-opening-a-pr.md`

### PRDESC-BODY-003: Fill standard sections conservatively

- Preserve the Community Note and rollback plan.
- Populate existing-surface, testing, changelog, related issue, and security sections from evidence.
- Write `No changes to security controls.` when compact evidence does not touch access control, authentication, authorization, encryption, secret handling, or logging behavior.
- **Provenance**: Local safeguard.
- **Evidence**:
  - Standard fallbacks keep the copy-ready body complete without invented claims

### PRDESC-BODY-004: Include minimal AI disclosure

- Check the template's `AI Assisted` option.
- State exactly `AI was used to draft the PR title and description.` unless the developer supplies broader wording.
- Do not claim AI generated implementation, tests, or documentation without explicit evidence.
- **Provenance**: Local safeguard.
- **Evidence**:
  - Invoking this workflow is direct AI assistance

## Checklist rules

### PRDESC-CHECK-001: Leave developer acknowledgements unchecked

- Leave contributor-guideline acknowledgement, duplicate PR review, and issue review unchecked.
- Do not run searches merely to check those items.
- **Provenance**: Local safeguard.
- **Evidence**:
  - Repository evidence cannot prove personal review or acknowledgement

### PRDESC-CHECK-002: Check description and documentation from content

- Check the meaningful-description item after the generated description names what changed and why.
- Check documentation items only when every applicable user-facing surface has matching changed documentation.
- **Provenance**: Published upstream standard.
- **Evidence**:
  - `https://github.com/hashicorp/terraform-provider-azurerm/tree/main/contributing/topics/guide-opening-a-pr.md`

### PRDESC-CHECK-003: Check authored tests separately from passing tests

- Check authored-test items when matching changed test coverage exists.
- Check test-passed items only under `PRDESC-EVID-002`.
- Do not leave a combined authored-tests-and-docs item unchecked solely because tests were not run when both changed surfaces exist.
- **Provenance**: Published upstream standard.
- **Evidence**:
  - `https://github.com/hashicorp/terraform-provider-azurerm/tree/main/contributing/topics/guide-opening-a-pr.md`

### PRDESC-CHECK-004: Set pull request type from classified behavior

- Check every applicable type among `Bug Fix`, `New Feature`, and `Enhancement`.
- Check `Breaking Change` only when explicitly confirmed.
- Always check `AI Assisted`.
- **Provenance**: Local safeguard.
- **Evidence**:
  - Type follows classified behavior while breaking impact requires explicit evidence

## Changelog rules

### PRDESC-CHANGELOG-001: Recommend body content, not a repository edit

- Put recommendations only in the template's `Change Log` section.
- Do not tell the contributor to edit `CHANGELOG.md`.
- Use `No changelog entry recommended.` for test-only, refactoring-only, documentation-only, or deprecation-only changes.
- **Provenance**: Published upstream standard.
- **Evidence**:
  - `https://github.com/hashicorp/terraform-provider-azurerm/tree/main/contributing/topics/maintainer-merging.md`

### PRDESC-CHANGELOG-002: Apply user-facing categories

- Classify new Resources, Data Sources, Actions, and List Resources as `FEATURES`.
- Classify new properties, functionality, and SDK/API upgrades as `ENHANCEMENTS`.
- Classify user-facing bug fixes as `BUG FIXES`.
- **Provenance**: Published upstream standard.
- **Evidence**:
  - `https://github.com/hashicorp/terraform-provider-azurerm/tree/main/contributing/topics/maintainer-merging.md`

### PRDESC-CHANGELOG-003: Render automation-ready entries

- Map `FEATURES` to `[FEATURE]`, `ENHANCEMENTS` to `[ENHANCEMENT]`, and `BUG FIXES` to `[BUG]`.
- Start each line with the keyword followed by `* `, name full Terraform surfaces, use lower-case change wording, omit a final period, and use the Oxford comma.
- Render new surfaces exactly as `[FEATURE] * **New Resource**: `{{RESOURCE_NAME}}``, `[FEATURE] * **New Data Source**: `{{DATA_SOURCE_NAME}}``, `[FEATURE] * **New Action**: `{{ACTION_NAME}}``, or `[FEATURE] * **New List Resource**: `{{RESOURCE_NAME}}``.
- Give each new Resource, Data Source, Action, and required List Resource its own feature line, including when multiple surfaces share one Terraform name.
- **Provenance**: Published upstream standard.
- **Evidence**:
  - `https://github.com/hashicorp/terraform-provider-azurerm/tree/main/contributing/topics/maintainer-merging.md`

### PRDESC-CHANGELOG-004: Do not invent breaking automation

- For an explicitly confirmed breaking change, render `Breaking change; maintainer-managed changelog entry required.`
- **Provenance**: Published upstream standard.
- **Evidence**:
  - `https://github.com/hashicorp/terraform-provider-azurerm/tree/main/contributing/topics/maintainer-merging.md`

### PRDESC-CHANGELOG-005: Keep companion implementation subordinate

- Do not give polling, SDK shim, registration, Resource Identity, generated-code, vendoring, test, or documentation work an independent changelog line when it only supports a primary user-facing change.
- Include a companion change only when compact evidence proves distinct user-facing behavior not already represented by the primary surface entries.
- Preserve one entry for each title-subordinate existing Resource, Data Source, Action, or provider change whose implementation evidence proves distinct user-facing enhancement or bug-fix behavior.
- **Provenance**: Local safeguard.
- **Evidence**:
  - Changelog recommendations should describe independently visible user behavior rather than implementation mechanics

## Issue rules

### PRDESC-ISSUE-001: Include only confirmed references

- Include related issues only from explicit developer input or `#{{ISSUE_NUMBER}}` or full GitHub issue URLs in current-branch commit messages.
- Otherwise write `No related issue confirmed.`
- Do not search for or infer potential issues during drafting.
- **Provenance**: Local safeguard.
- **Evidence**:
  - Search similarity does not prove issue resolution and is unnecessary for a drafting shortcut

## Output rules

### PRDESC-OUT-001: Emit one lean payload

- Emit one object conforming to `.github/instructions/pr-description-draft.schema.json`.
- Include repository identity, one title, one title explanation, the complete body, and concise evidence notes.
- **Provenance**: Local safeguard.
- **Evidence**:
  - A small payload preserves deterministic presentation without carrying audit-only state

### PRDESC-OUT-002: Render four sections

- Render `Suggested PR Title`, `Why This Title`, `Draft PR Body`, and `Evidence Notes` in that order.
- Put the title in a text code block and the complete body in one Markdown code block.
- Do not render potential issue search results or process narration.
- **Provenance**: Local safeguard.
- **Evidence**:
  - The output stays focused on content the developer can use

### PRDESC-OUT-003: End with the verification footer

- End with exactly `Preflight complete: yes` and `Skill used: pr-description`.
- Emit nothing after the footer.
- **Provenance**: Local safeguard.
- **Evidence**:
  - The footer proves the routed workflow completed

## Failure rules

### PRDESC-FAIL-001: Stop on ineligible repository state

- Hard-stop for the wrong repository, missing AzureRM structure, `main`, or an empty change-set.
- **Provenance**: Local safeguard.
- **Evidence**:
  - These states cannot produce an eligible branch draft

### PRDESC-FAIL-002: Stop when no local comparison base exists

- Hard-stop when `upstream/main`, `origin/main`, and local `main` are all unusable or no merge base exists.
- **Provenance**: Local safeguard.
- **Evidence**:
  - Scope cannot be classified without a local comparison origin

### PRDESC-FAIL-003: Stop on unrelated primary changes

- Apply `PRDESC-SCOPE-004` before drafting.
- **Provenance**: Local safeguard.
- **Evidence**:
  - The workflow must not hide branch-splitting ambiguity

### PRDESC-FAIL-004: Stop on repository changes during drafting

- Stop when final `HEAD` or porcelain status differs from initial evidence.
- Do not discard and restart automatically.
- **Provenance**: Local safeguard.
- **Evidence**:
  - A changed local snapshot should be retried by the developer rather than doubling workflow time

### PRDESC-FAIL-005: Stop on invalid handoff

- Do not render partial output when the lean payload fails schema validation.
- **Provenance**: Local safeguard.
- **Evidence**:
  - Validation prevents malformed copy-ready output

<!-- PRDESC-CONTRACT-EOF -->
