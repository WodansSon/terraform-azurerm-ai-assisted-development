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

### PRDESC-PRE-002: Restrict drafting to AzureRM

- Require `terraform-provider-azurerm` or a fork with the same repository name, remotes, and expected provider structure.
- Reject `main` and empty change-sets.

### PRDESC-PRE-003: Trust direct Git branch evidence

- Use an explicit developer-supplied branch or worktree path when present.
- Otherwise use `git branch --show-current` from the validated current worktree.
- Treat conflicting editor, workspace, source-control, and pull request metadata as advisory and non-blocking.
- Do not search for another checkout unless the developer explicitly selected one.

### PRDESC-PRE-004: Preserve repository state and minimize rounds

- Use read-only Git and file inspection only.
- Do not fetch, pull, merge, rebase, checkout, commit, push, reset, clean, edit files, or run tests.
- Display exact terminal commands under `[Read-only] {{PURPOSE}}`.
- Collect repository identity, branch, status, and local-base candidates in one fixed direct-Git batch, then collect the selected merge base, committed paths, working-tree paths, untracked paths, and commit subjects in one fixed direct-Git batch.
- Keep those two batches as the ordinary path. Add the bounded local branch-boundary recovery under `PRDESC-BASE-003` only when the initial scope is implausibly broad enough to suggest that the named base includes incorporated upstream history.
- Issue each fixed Git batch once as the prompt's exact one-line semicolon-separated command string. Do not first issue newline-separated commands, reformat a successful call, or retry a batch in alternate shell syntax.
- If a fixed Git batch returns incomplete output, hard-stop instead of improvising another command shape.
- Terminal batches may contain only the literal read-only Git commands required by the prompt. Do not generate PowerShell or shell variables, loops, conditionals, script blocks, here-strings, file reads, string replacement, JSON construction, or schema-validation programs.
- Use tool-native file reads and searches for template and implementation evidence.
- Build one complete Phase 2 read plan from the changed-path inventory, then read independent user-facing implementation, test, documentation, registration, Resource Identity, and List Resource evidence in one concurrent tool batch.
- Read a known changed file directly. Do not search for its path, enumerate test functions merely to prove changed test coverage, list its service directory, or split implementation, test, and documentation reads into successive rounds.
- Do not reload upstream contributor guides during drafting; this checked-in contract owns their stable drafting rules.

### PRDESC-PRE-005: Use a cheap stability guard

- Capture full `HEAD` and `git status --porcelain=v1 --untracked-files=all` during initial evidence collection.
- Immediately before rendering, collect those same two values once.
- Hard-stop when either value differs; do not restart the workflow automatically.
- Do not hash full diff or untracked-file contents solely to draft a pull request description.

## Comparison-base rules

### PRDESC-BASE-001: Use an existing local base

- Select the first usable local ref in this order: `upstream/main`, `origin/main`, local `main`.
- Do not refresh remote-tracking refs during drafting.
- Record the selected ref and commit in the lean handoff.

### PRDESC-BASE-002: Diff from the merge base

- Resolve the common ancestor between the selected local base and `HEAD`.
- Use it as the tracked change origin for committed, staged, and unstaged work.

### PRDESC-BASE-003: Recover a stale named base from local branch history

- When the initial merge-base scope is implausibly broad across service packages, commit subjects, or unrelated path families, run one bounded local recovery pass to test whether the selected named main ref is stale.
- Treat breadth only as a recovery trigger. Multiple service packages are not proof of unrelated change intent and must never cause a hard stop by themselves.
- Collect compact first-parent commit metadata from the selected base to `HEAD` once. Use commit IDs, parent IDs, author and committer identities, and subjects only; do not fetch, inspect remote state, search GitHub, or emit per-commit patches.
- Derive exactly one candidate origin from that metadata. Prefer the second parent of the newest clear mainline integration merge in the contributor history; a clear integration merge has exactly two parents and a subject that explicitly identifies `upstream/main`, `origin/main`, or `main` as merged into the feature branch. This recovers the latest incorporated mainline snapshot while retaining contributor commits from both before and after the merge.
- When no clear mainline integration merge exists, derive the candidate from a clear contiguous contributor change stack at the branch tip and use the first parent of its oldest commit. Keep fixup, lint, documentation, generated, vendored, and dependency-sync commits in that stack when they support its apparent feature intent.
- Collect the complete scope from the selected candidate exactly once with the same fixed scope command shape. Do not test both merge-aware and linear candidates in one run.
- Accept the candidate only when it is an ancestor of `HEAD`, the recovered scope is non-empty, strictly removes incorporated history from the initial scope, and leaves a materially narrower contributor tip stack. Preserve staged, unstaged, and non-ignored untracked paths unchanged.
- Replace the selected base and merge base in the handoff with the accepted candidate commit. Do not carry the inflated named-base scope into title, body, checklist, changelog, or issue decisions.
- If commit metadata does not expose one clear tip boundary or the replacement scope is not strictly narrower, retain the original scope and continue to evidence-based coherence classification under `PRDESC-SCOPE-004`. Do not guess a boundary or run another recovery pass.

## Scope rules

### PRDESC-SCOPE-001: Collect the complete local change-set once

- Combine the selected-base-to-`HEAD` name/status inventory with the `HEAD`-to-working-tree name/status inventory.
- Include non-ignored untracked files from `git ls-files --others --exclude-standard`.
- Preserve added, modified, renamed, copied, deleted, and untracked status.
- Collect current branch commit subjects for explicit issue references and supporting context.

### PRDESC-SCOPE-002: Read only material evidence

- Inspect compact implementation evidence for every independently user-facing changed surface, including title-driving new surfaces and title-subordinate changes to existing Resources, Data Sources, Actions, or provider behavior.
- For each such surface, collect enough compact schema and lifecycle evidence to identify its material behavior inventory: management or query scope, meaningful create/read/update/delete semantics, plan/read/import type or ownership guards, computed outputs whose purpose matters, list filters or enumeration scope, state normalization or drift-prevention behavior, and removal or disable transitions that must actively clear API-retained values.
- Record every material behavior as one or more atomic claims containing the owning Terraform surface, exact applicable lifecycle path or paths, behavior kind, and observable outcome. Use concrete lifecycle paths such as plan, import, create, read, update, delete, or list; do not use a broader operation family when changed evidence proves only a subset.
- Keep retry, wait, validation, guard, clear, normalization, and other behavior kinds independent unless changed evidence proves that the same owner and lifecycle path perform each behavior. A shared helper or related change intent does not transfer one surface's behavior to another surface or to another lifecycle path.
- Record the exact lifecycle paths covered by each ownership or type guard. An importer-only guard proves protected import or adoption, a create guard proves protected creation, and a Data Source read guard proves protected querying; none alone proves that every lifecycle operation rejects the object.
- When a changed custom request marshaller, payload builder, workaround client, or equivalent update helper decides whether configured values are omitted or actively cleared, inspect its compact comment and clear-path logic as material behavior evidence. Keep those implementation mechanics out of the drafted body and changelog.
- For claimed compatibility between a new surface and an existing consumer, require changed implementation evidence on the existing surface that enables the compatibility. A new object flowing through an unchanged ID, schema, or association path does not make pre-existing compatibility a changed behavior.
- Treat that inventory as description evidence, not review evidence. Do not assess whether the behavior is correct, identify missing implementation, prescribe changes, or narrate every schema field and CRUD call.
- Inspect only companion registration, tests, documentation, Resource Identity, List Resource, and security evidence needed for body or checklist decisions.
- Treat matching changed test paths as sufficient evidence that tests were authored. Read test content only when one material coverage claim cannot be resolved from paths and implementation evidence.
- Search only when the complete changed-path inventory does not identify the owning file or symbol. Do not search for an exact path already present in that inventory.
- Do not emit or reread one repository-wide patch.

### PRDESC-SCOPE-003: Keep companions subordinate

- Treat tests, documentation, registration, Resource Identity, required List Resource support, generated code, and vendored SDK changes as companions when they support one primary change.
- Do not classify a changed existing Terraform surface as a companion merely because a new surface outranks it for title selection. Preserve distinct user-facing enhancement or bug-fix behavior for the body, PR type, and changelog.
- Ignore generated and vendored paths for title dominance unless the PR primarily updates SDK, API, dependency, or generated code.

### PRDESC-SCOPE-004: Stop on unrelated primary changes

- After material evidence is read, build one lightweight relationship graph across changed user-facing surfaces using shared symbols or helpers, direct call sites, common schema or lifecycle behavior, registration and ownership links, companion tests and documentation, commit subjects, and one explainable user outcome.
- Treat cross-service dependencies, shared provider or framework helpers, common abstractions, and resources consumed by other resources as related when direct evidence connects them to one behavior intent.
- Hard-stop only when the graph leaves two or more independent user-facing change intents that cannot be represented honestly by one deterministic title and one coherent description.
- Do not hard-stop from service-package count, path count, file count, or title-surface count alone.
- Do not stop when several Resources, Data Sources, Actions, provider behaviors, shared helpers, or service packages form one connected change intent. Preserve every independently user-facing surface in the body, PR type, and changelog under `PRDESC-SCOPE-003`.

## Evidence rules

### PRDESC-EVID-001: Make only supported claims

- Support claims with changed paths, compact diffs, commit subjects, explicit developer input, current-run command output, or the current template.
- Use `Needs contributor input.` when a material fact cannot be proven.

### PRDESC-EVID-002: Separate test existence from execution

- Determine whether matching tests exist from changed-file and compact test evidence.
- Claim tests passed only from successful current-run output or explicit developer-provided command and result evidence.
- Do not treat test files, comments, commit messages, or prior PR text as proof that tests ran.

### PRDESC-EVID-003: Keep absent validation visible but non-blocking

- When no test result is available, leave execution-dependent checklist items unchecked.
- State briefly in `Testing` that tests were not run during drafting and summarize matching coverage only when changed-file evidence proves it exists.

## Title rules

### PRDESC-TITLE-001: Select one title by fixed precedence

- Apply this order: new Resource plus same-name Data Source, new Resource, new standalone Data Source, new List Resource, new Action or provider feature, bug fix, enhancement, SDK/API/dependency update, contributor guidance, documentation, CI or maintenance.
- Supporting surfaces do not compete with the primary surface.

### PRDESC-TITLE-002: Use exact new-surface shapes

- Use ``New (Data Source|Resource) - `{{RESOURCE_NAME}}``` for one Terraform name introducing both surfaces.
- Treat `(Data Source|Resource)` as literal title text. Do not render `New Resource and Data Source -`, `New Data Source and Resource -`, or another natural-language variant.
- Use ``New Resource: `{{RESOURCE_NAME}}``` for a new Resource.
- Use ``New Data Source: `{{DATA_SOURCE_NAME}}``` for a standalone Data Source.
- Use ``New List Resource: `{{RESOURCE_NAME}}``` for List Resource support added to an existing Resource.
- Do not add `List Resource` to a new Resource title when it is a required companion.

### PRDESC-TITLE-003: Make existing-surface titles concrete

- Name the affected Terraform surface and use concrete wording such as `add support for`, `improve validation for`, or `correctly populate`.
- Use `Data Source:`, `List Resource:`, `Contributing:`, or `Docs:` when needed for clarity.
- Do not use bracketed prefixes unless repository guidance requires them.

### PRDESC-TITLE-004: Reject vague titles

- Reject titles equivalent to `fix bug`, `fixes #1234`, `new resource`, or `upgrade sdk`.

## Body rules

### PRDESC-BODY-001: Preserve the current template

- Start from the current worktree's `.github/pull_request_template.md`.
- Assemble the body by inserting evidence-backed responses into the loaded template skeleton. Do not reconstruct immutable template lines from memory or substitute familiar template wording from another checkout.
- Preserve every template line verbatim unless that line is an evidence-populated response area, an example or claim placeholder being replaced, or a checklist marker changing only from `[ ]` to `[x]`.
- Do not rewrite, shorten, normalize, or repair template prose, links, URLs, comments, headings, checklist text, the Community Note, the rollback plan, or the final note.
- Replace examples and placeholders that could be mistaken for contributor claims.
- Before rendering, compare immutable template lines with the already-loaded template and restore any mismatch in memory.
- Compare ordered URL tokens in immutable draft lines with the corresponding loaded template lines and restore every mismatch before rendering, including a valid-looking replacement URL.

### PRDESC-BODY-002: Explain what and why

- Before drafting, reduce the compact evidence to one concise behavior inventory for each independently user-facing changed surface.
- Draft description claims only from the atomic owner, lifecycle-path, behavior-kind, and observable-outcome records collected under `PRDESC-SCOPE-002`. Before finalizing a sentence, expand conjunctions and grouped subjects into their individual claims and verify that each expanded claim has a matching evidence record.
- Represent every inventory item once in the description when it changes what users can configure, manage, query, observe in state, import, or rely on to prevent drift or cross-type ownership mistakes.
- Preserve lifecycle-path specificity for every behavior. Use import, create, read, update, or delete wording supported by changed evidence; do not generalize a create-only retry to all operations or an importer-only guard to all management.
- Preserve surface attribution when combining related behavior into compact prose. A shared sentence may group surfaces or lifecycle paths only for the intersection of atomic claims proven for every named surface and path; render non-shared retries, waits, validations, guards, clearing, normalization, or outcomes as separately attributed clauses or sentences.
- When changed update behavior actively clears a removed or disabled value that the API would otherwise retain, state that observable removal behavior compactly. Do not replace it with the SDK serialization, custom client, request payload, or polling mechanism used to implement it.
- When compact evidence proves active clearing for multiple independently configured retained-value families, name each family compactly. Do not mention only the family observed by polling while omitting another family cleared by the same update path.
- Do not claim newly added compatibility, support, or association behavior for an existing surface when the changed implementation only affects another behavior and the compatibility already follows from an unchanged schema or ID path.
- Prioritize observable behavior over plumbing. Do not let client construction, registration, helper reuse, SDK shims, generated code, or vendoring displace a material schema, lifecycle, list-scope, import, computed-output, validation, or state behavior. Mention plumbing only when it is itself the user-facing change or is necessary to explain availability.
- Keep the description proportional: combine related behaviors into compact prose rather than listing every field or implementation step.
- Describe what changed and why without grading correctness, reporting defects, proposing fixes, or speculating about missing tests. This workflow drafts the pull request; it does not perform code review.
- Include breaking impact and upgrade steps only when explicitly confirmed.

### PRDESC-BODY-003: Fill standard sections conservatively

- Preserve the Community Note and rollback plan.
- Populate existing-surface, testing, changelog, related issue, and security sections from evidence.
- Write `No changes to security controls.` when compact evidence does not touch access control, authentication, authorization, encryption, secret handling, or logging behavior.

### PRDESC-BODY-004: Include minimal AI disclosure

- Check the template's `AI Assisted` option.
- State exactly `AI was used to draft the PR title and description.` unless the developer supplies broader wording.
- Do not claim AI generated implementation, tests, or documentation without explicit evidence.

## Checklist rules

### PRDESC-CHECK-001: Leave developer acknowledgements unchecked

- Leave contributor-guideline acknowledgement, duplicate PR review, and issue review unchecked.
- Do not run searches merely to check those items.

### PRDESC-CHECK-002: Check description and documentation from content

- Check the meaningful-description item after the generated description names what changed and why.
- Check documentation items only when every applicable user-facing surface has matching changed documentation.

### PRDESC-CHECK-003: Check authored tests separately from passing tests

- Check authored-test items when matching changed test coverage exists.
- Check test-passed items only under `PRDESC-EVID-002`.
- Do not leave a combined authored-tests-and-docs item unchecked solely because tests were not run when both changed surfaces exist.

### PRDESC-CHECK-004: Set pull request type from classified behavior

- Check every applicable type among `Bug Fix`, `New Feature`, and `Enhancement`.
- Check `Breaking Change` only when explicitly confirmed.
- Always check `AI Assisted`.

## Changelog rules

### PRDESC-CHANGELOG-001: Recommend body content, not a repository edit

- Put recommendations only in the template's `Change Log` section.
- Do not tell the contributor to edit `CHANGELOG.md`.
- Use `No changelog entry recommended.` for test-only, refactoring-only, documentation-only, or deprecation-only changes.

### PRDESC-CHANGELOG-002: Apply user-facing categories

- Classify new Resources, Data Sources, Actions, and List Resources as `FEATURES`.
- Classify new properties, functionality, and SDK/API upgrades as `ENHANCEMENTS`.
- Classify user-facing bug fixes as `BUG FIXES`.
- Classify a changed existing surface as a bug fix when compact evidence proves that it corrects premature lifecycle success, failed cleanup, a valid operation that previously failed or hung, drift, or API-retained residual state. Do not downgrade that correction to an enhancement merely because polling, serialization, or client code implements it.
- Keep polling, serialization, and client refactors subordinate when compact evidence does not prove a corrected user-facing failure mode.

### PRDESC-CHANGELOG-003: Render automation-ready entries

- Map `FEATURES` to `[FEATURE]`, `ENHANCEMENTS` to `[ENHANCEMENT]`, and `BUG FIXES` to `[BUG]`.
- Start each line with the keyword followed by `* `, name full Terraform surfaces, use lower-case change wording, omit a final period, and use the Oxford comma.
- Render new surfaces exactly as `[FEATURE] * **New Resource**: `{{RESOURCE_NAME}}``, `[FEATURE] * **New Data Source**: `{{DATA_SOURCE_NAME}}``, `[FEATURE] * **New Action**: `{{ACTION_NAME}}``, or `[FEATURE] * **New List Resource**: `{{RESOURCE_NAME}}``.
- Give each new Resource, Data Source, Action, and required List Resource its own feature line, including when multiple surfaces share one Terraform name.
- Give each changed existing Resource, Data Source, Action, or provider surface its own changelog line when it has distinct user-facing behavior. Never combine Resource and Data Source behavior on one line merely because they share one Terraform name.
- Render an existing Data Source owner as `Data Source: `{{DATA_SOURCE_NAME}}`` and an existing Resource owner as `{{RESOURCE_NAME}}`. Describe only behavior owned by the named surface on that line.
- Render existing-surface owner tokens exactly as plain Markdown text with only the Terraform name in code formatting. Do not wrap `Data Source: `{{DATA_SOURCE_NAME}}`` or `{{RESOURCE_NAME}}` in bold, italics, links, or additional decoration.
- Derive each existing-surface changelog line only from atomic claims owned by that surface. Name the exact lifecycle paths and behavior kinds supported by those records; never transfer a retry, wait, validation, guard, clear, normalization, or outcome from a related surface or operation into the line.

### PRDESC-CHANGELOG-004: Do not invent breaking automation

- For an explicitly confirmed breaking change, render `Breaking change; maintainer-managed changelog entry required.`

### PRDESC-CHANGELOG-005: Keep companion implementation subordinate

- Do not give polling, SDK shim, registration, Resource Identity, generated-code, vendoring, test, or documentation work an independent changelog line when it only supports a primary user-facing change.
- Include a companion change only when compact evidence proves distinct user-facing behavior not already represented by the primary surface entries.
- Preserve one entry for each title-subordinate existing Resource, Data Source, Action, or provider change whose implementation evidence proves distinct user-facing enhancement or bug-fix behavior.

## Issue rules

### PRDESC-ISSUE-001: Include only confirmed references

- Include related issues only from explicit developer input or `#{{ISSUE_NUMBER}}` or full GitHub issue URLs in current-branch commit messages.
- Otherwise write `No related issue confirmed.`
- Do not search for or infer potential issues during drafting.

## Output rules

### PRDESC-OUT-001: Emit one lean payload

- Emit one object conforming to `.github/instructions/pr-description-draft.schema.json`.
- Include repository identity, one title, one title explanation, the complete body, and concise evidence notes.

### PRDESC-OUT-002: Render four sections

- Render `Suggested PR Title`, `Why This Title`, `Draft PR Body`, and `Evidence Notes` in that order.
- Put the title in a text code block and the complete body in one Markdown code block.
- Do not render potential issue search results or process narration.

### PRDESC-OUT-003: End with the verification footer

- End with exactly `Preflight complete: yes` and `Skill used: pr-description`.
- Emit nothing after the footer.

## Failure rules

### PRDESC-FAIL-001: Stop on ineligible repository state

- Hard-stop for the wrong repository, missing AzureRM structure, `main`, or an empty change-set.

### PRDESC-FAIL-002: Stop when no local comparison base exists

- Hard-stop when `upstream/main`, `origin/main`, and local `main` are all unusable or no merge base exists.

### PRDESC-FAIL-003: Stop on unrelated primary changes

- Apply `PRDESC-SCOPE-004` before drafting.

### PRDESC-FAIL-004: Stop on repository changes during drafting

- Stop when final `HEAD` or porcelain status differs from initial evidence.
- Do not discard and restart automatically.

### PRDESC-FAIL-005: Stop on invalid handoff

- Do not render partial output when the lean payload fails schema validation.

<!-- PRDESC-CONTRACT-EOF -->
