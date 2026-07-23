---
name: pr-description
description: "Draft an AzureRM pull request title and body from the complete current branch change-set. Used by the draft-pr-description prompt for scope classification, evidence decisions, checklist and changelog handling, and structured handoff production."
user-invocable: false
---

# PR Description Drafting Method

## Scope

Use this skill only when routed by `.github/prompts/draft-pr-description.prompt.md` inside `terraform-provider-azurerm` or a fork with the same repository name and expected structure.

This skill owns the reusable drafting procedure. It does not own normative drafting policy, exact hard-stop strings, schema validation, or final Markdown presentation.

## Required sources

Before applying the method:

- Read `.github/instructions/pr-description-compliance-contract.instructions.md` to EOF.
- Verify its final non-empty line is `<!-- PRDESC-CONTRACT-EOF -->`.
- Read `.github/instructions/pr-description-draft.schema.json` to EOF.
- Use only evidence collected by the current prompt invocation.
- Apply every relevant `PRDESC-*` rule from the contract rather than restating policy from memory.

## Input handoff

Consume the current-run evidence assembled by the prompt:

- Resolved base source, selected commit, merge-base commit, and refresh status
- Required base-revision template and contributor guidance
- Complete tracked diff from merge base to working tree
- Non-ignored untracked paths and inspected contents
- Current branch commit messages
- Authoritative existing pull request metadata when available
- Current-run validation output when explicitly gathered
- Explicit user-provided facts
- Open pull request search status and results

Do not run mutating commands or modify repository files.

## Drafting procedure

### Build the changed-file inventory

- Normalize tracked diff statuses to `added`, `modified`, `renamed`, `copied`, or `deleted`.
- Add non-ignored untracked files with `status=untracked` and `source=untracked`.
- Preserve prior paths for renames and copies.
- Order the inventory lexically by current path, then previous path.

### Classify changed surfaces

- Apply `PRDESC-SCOPE-*` in lexical path order.
- Identify the Terraform name and service package from implementation, registration, test, and documentation evidence.
- Mark one coherent title-owning surface or surface set as primary.
- Mark tests, docs, registration, Resource Identity, required List Resource support, generated code, and vendored SDK files as companions when they serve that primary change.
- Preserve separate classified surfaces for companion List Resources and Resource Identity so checklist and changelog decisions can inspect them.
- Return control to the prompt for the `PRDESC-SCOPE-004` hard stop when unrelated primary service-package changes remain.

### Select and explain the title

- Apply `PRDESC-TITLE-001` in its fixed decision order.
- Apply the exact title shape from `PRDESC-TITLE-002` when a new surface pattern matches.
- Otherwise apply `PRDESC-TITLE-003` and `PRDESC-TITLE-004`.
- Record every governing title rule ID.
- Produce one sentence explaining the selected primary surface, change type, and companion treatment from observed evidence.

### Draft the template body

- Start from the exact resolved-base pull request template.
- Apply `PRDESC-BODY-*` without reordering or deleting template content.
- Replace example issue and changelog placeholders.
- Fill only claims supported by `PRDESC-EVID-*`.
- Preserve confirmed issue references only under `PRDESC-ISSUE-001`.
- Explain documented Resource Identity or List Resource exceptions when applicable.
- Keep prompt-only title reasoning, evidence notes, and advisory issue candidates outside the body.

### Decide each checklist item

- Create one `checklistDecisions` record for every checklist item in the resolved-base template.
- Apply `PRDESC-CHECK-*` to choose `checked` conservatively.
- Record a concise evidence-based reason and governing rule IDs for each decision.
- Apply open pull request search results before deciding the duplicate-pull-request item.
- Render the selected states back into the complete body without changing checklist wording.

### Decide changelog content

- Apply `PRDESC-CHANGELOG-*` using the resolved-base `maintainer-merging.md` authority.
- Build zero or more ordered automation-ready entries.
- Set `renderedContent` to the exact content inserted into the template's `Change Log` section.
- Preserve a required List Resource as its own feature entry even when it is implied in the title.
- Do not instruct the contributor to edit `CHANGELOG.md`.

### Build evidence gaps

- Add only unresolved or cautionary items that matter to the contributor.
- Include missing issue confirmation, missing applicable docs or tests, absent current-run validation, stale base refresh, unresolved Resource Identity or List Resource exceptions, and unavailable searches when applicable.
- Keep each gap concise and do not duplicate information already fully resolved in the body.
- Use an empty array when no gaps remain.

### Add potential related issue results

- Consume the prompt's post-draft issue search results.
- Apply `PRDESC-ISSUE-002` through `PRDESC-ISSUE-004` for filtering, ranking, and status.
- Preserve at most five candidates with issue number, title, canonical issue URL, match reason, and match kind.
- Keep advisory candidates out of confirmed references and the copy-ready body.

## Output handoff

Emit one object conforming to `.github/instructions/pr-description-draft.schema.json`.

- Use `schemaVersion=1.0`.
- Include every required top-level property.
- Use repo-relative paths only.
- Preserve deterministic ordering for changed files, surfaces, checklist records, changelog entries, evidence gaps, and issue candidates.
- Include only `PRDESC-*` rule IDs that directly governed each decision.
- Do not render the five-section user response.
- Do not add policy fields that the schema does not define.

Return the payload to the prompt for schema validation and presentation.

<!-- PRDESC-SKILL-EOF -->
