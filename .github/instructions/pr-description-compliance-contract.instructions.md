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

- Explicit user-provided facts and current-run command output for contributor intent and validation evidence
- Authoritative existing pull request metadata for the current branch when available
- `.github/pull_request_template.md` from the resolved comparison-base revision for body shape and section order
- `contributing/topics/guide-opening-a-pr.md` from the resolved comparison-base revision for pull request title and submission guidance
- `contributing/topics/maintainer-merging.md` from the resolved comparison-base revision for changelog eligibility and formatting
- `contributing/topics/guide-new-resource.md` from the resolved comparison-base revision for new Resource expectations
- `contributing/topics/guide-resource-identity.md` from the resolved comparison-base revision for Resource Identity requirements and exception disclosure
- `contributing/topics/guide-list-resource.md` from the resolved comparison-base revision for List Resource requirements
- Current branch diff, working tree, commit messages, and non-ignored untracked files for change evidence
- This contract for deterministic drafting, fallback, and output requirements not owned by the runtime AzureRM sources

Conflict resolution:

- Repository policy from the resolved base revision outranks change evidence when deciding what the pull request should contain.
- Explicit current-run evidence outranks older pull request text when the two conflict.
- Existing pull request metadata supplements local evidence and must not hide unpushed committed, staged, unstaged, or untracked changes.
- The prompt owns exact hard-stop strings and presentation mechanics but must not weaken this contract.
- The skill owns procedure but must not redefine policy from this contract.
- The schema owns payload shape only and must not introduce policy defaults.

## Rule IDs

- `PRDESC-PRE-*`: fresh-run and repository eligibility
- `PRDESC-BASE-*`: comparison-base resolution
- `PRDESC-SCOPE-*`: change collection and surface classification
- `PRDESC-EVID-*`: evidence and validation claims
- `PRDESC-TITLE-*`: title selection and formatting
- `PRDESC-BODY-*`: template preservation and body content
- `PRDESC-CHECK-*`: checklist decisions
- `PRDESC-CHANGELOG-*`: changelog eligibility and rendering
- `PRDESC-ISSUE-*`: confirmed and potential issue handling
- `PRDESC-OUT-*`: payload and final output semantics
- `PRDESC-FAIL-*`: required failure behavior

## Evidence hierarchy

- Highest: explicit user input and successful command output gathered in the current invocation
- High: current diff content, changed paths, untracked file content, and authoritative current pull request metadata
- Medium: current branch commit messages and repository structure
- Policy authority: required base-revision template and contributor guidance
- Advisory only: open issue and pull request search results
- Disallowed: guessed intent, assumed test execution, assumed changelog eligibility, assumed issue linkage, and assumed breaking-change impact

## Preflight rules

### PRDESC-PRE-001: Start every invocation from current evidence

- Treat every invocation as a fresh run.
- Reload the contract, skill, and schema before collecting evidence.
- Rerun all required repository, base, diff, and search operations.
- Do not reuse prior-run scope, command output, classifications, title decisions, or draft content.
- **Provenance**: Local safeguard.
- **Evidence**:
  - Fresh evidence prevents a draft from omitting branch or worktree changes made after a prior invocation

### PRDESC-PRE-002: Restrict the workflow to AzureRM

- Require a checkout whose repository name is `terraform-provider-azurerm` and whose structure matches the AzureRM provider.
- Accept the canonical `hashicorp/terraform-provider-azurerm` repository and forks with the same repository name and expected structure.
- Do not generalize this workflow to other repositories.
- **Provenance**: Local safeguard.
- **Evidence**:
  - The title, template, changelog, Resource Identity, and List Resource rules are AzureRM-specific

### PRDESC-PRE-003: Require base-revision authorities

- Require these files in the resolved comparison-base revision:
  - `.github/pull_request_template.md`
  - `contributing/README.md`
  - `contributing/topics/guide-opening-a-pr.md`
  - `contributing/topics/maintainer-merging.md`
  - `contributing/topics/guide-new-resource.md`
  - `contributing/topics/guide-resource-identity.md`
  - `contributing/topics/guide-list-resource.md`
- Load each required authority from the resolved base revision rather than trusting the candidate branch copy.
- **Provenance**: Published upstream standard.
- **Evidence**:
  - `https://github.com/hashicorp/terraform-provider-azurerm/tree/main/contributing/topics/guide-opening-a-pr.md`
  - `https://github.com/hashicorp/terraform-provider-azurerm/tree/main/contributing/topics/maintainer-merging.md`
  - `https://github.com/hashicorp/terraform-provider-azurerm/tree/main/contributing/topics/guide-new-resource.md`
  - `https://github.com/hashicorp/terraform-provider-azurerm/tree/main/contributing/topics/guide-resource-identity.md`
  - `https://github.com/hashicorp/terraform-provider-azurerm/tree/main/contributing/topics/guide-list-resource.md`

### PRDESC-PRE-004: Preserve repository state

- Use read-only inspection commands only.
- Do not pull, merge, rebase, commit, push, checkout, reset, clean, or modify files.
- A read-only fetch that refreshes the selected remote-tracking base ref is permitted.
- **Provenance**: Local safeguard.
- **Evidence**:
  - Drafting must not mutate the contributor's branch or worktree

## Comparison-base rules

### PRDESC-BASE-001: Resolve the base deterministically

- Select the comparison base in this order:
  - Current base commit SHA from authoritative existing pull request metadata for the current branch
  - `upstream/main` when the `upstream` remote and ref exist
  - `origin/main` when the `origin` remote and ref exist
  - Local `main`
- Do not choose a lower-priority source while a usable higher-priority source exists.
- **Provenance**: Local safeguard.
- **Evidence**:
  - Existing pull request metadata is the most direct statement of the branch's actual target

### PRDESC-BASE-002: Refresh remote-tracking bases conservatively

- When selecting `upstream/main` or `origin/main`, attempt a read-only fetch of that ref.
- If the fetch fails and the existing remote-tracking ref remains usable, continue with it.
- Record the failed refresh and possible staleness as an evidence gap.
- **Provenance**: Local safeguard.
- **Evidence**:
  - A failed network refresh should not prevent drafting when a local base is available, but staleness must be disclosed

### PRDESC-BASE-003: Diff from the merge base

- Compute the merge base between the selected base commit or ref and `HEAD`.
- Use the resulting commit as the single tracked-file diff origin.
- Preserve the selected source, selected commit, merge-base commit, and refresh status in the payload.
- **Provenance**: Local safeguard.
- **Evidence**:
  - Merge-base scope isolates candidate branch work without treating unrelated base advancement as contributor changes

## Scope rules

### PRDESC-SCOPE-001: Collect the complete in-progress change-set

- Use one diff from the merge-base commit to the working tree for committed, staged, and unstaged tracked changes.
- Use `git ls-files --others --exclude-standard` for non-ignored untracked files and inspect those files separately.
- Preserve added, modified, renamed, copied, and deleted statuses.
- Do not double-count staged or unstaged tracked changes.
- **Provenance**: Local safeguard.
- **Evidence**:
  - The draft must represent the branch state the contributor is preparing to submit, including local changes

### PRDESC-SCOPE-002: Classify surfaces in stable order

- Classify changed paths in lexical order.
- Recognize new and existing Resources, Data Sources, List Resources, Actions, Ephemeral Resources, Functions, provider features, SDK or API updates, documentation, contributor guidance, tests, CI, and maintenance changes.
- Record the Terraform name and service package when evidence supports them.
- **Provenance**: Inferred maintainer convention.
- **Evidence**:
  - Stable path and surface ordering makes title and changelog choices repeatable

### PRDESC-SCOPE-003: Keep companion surfaces subordinate

- Treat tests, documentation, Resource Identity, registration, required List Resource support, generated code, and vendored SDK changes as companion surfaces when they support the same primary implementation.
- Ignore generated and vendored files for dominant title selection unless the pull request primarily updates SDK, API, dependency, or generated code.
- **Provenance**: Published upstream standard.
- **Evidence**:
  - `https://github.com/hashicorp/terraform-provider-azurerm/tree/main/contributing/topics/guide-new-resource.md`
  - `https://github.com/hashicorp/terraform-provider-azurerm/tree/main/contributing/topics/guide-resource-identity.md`
  - `https://github.com/hashicorp/terraform-provider-azurerm/tree/main/contributing/topics/guide-list-resource.md`

### PRDESC-SCOPE-004: Stop on unrelated primary service changes

- When unrelated primary changes span multiple service packages, do not guess which one owns the title.
- Hard-stop and ask the contributor to identify the primary change or split the branch.
- Do not stop when multiple surfaces are required companions for one coherent primary implementation.
- **Provenance**: Local safeguard.
- **Evidence**:
  - One deterministic title cannot accurately represent unrelated primary changes

## Evidence rules

### PRDESC-EVID-001: Make only supported claims

- Support claims with branch diff content, changed paths, required base-revision authorities, explicit current-run command output, authoritative existing pull request metadata, commit messages, or explicit user input.
- Use the section-specific fallback when evidence is missing.
- Otherwise write `Needs contributor input.` and add a concise evidence gap.
- **Provenance**: Local safeguard.
- **Evidence**:
  - Conservative drafting prevents the prompt from representing unverified work as completed

### PRDESC-EVID-002: Require current-run validation output

- Do not treat commands mentioned in documentation, comments, commit messages, or pull request text as proof they ran.
- Claim local validation passed only when the current invocation observes successful output for the named command.
- Preserve existing pull request testing evidence only when it names the command and result and is not contradicted by the current diff.
- **Provenance**: Published upstream standard.
- **Evidence**:
  - `https://github.com/hashicorp/terraform-provider-azurerm/tree/main/contributing/topics/guide-opening-a-pr.md`

### PRDESC-EVID-003: Distinguish skipped acceptance tests from success

- Do not treat a skipped acceptance test as successful validation unless the required Azure environment variables were present and the test actually ran.
- Report skipped, missing, stale, or contradicted evidence in evidence gaps.
- **Provenance**: Local safeguard.
- **Evidence**:
  - A successful process exit can conceal an acceptance-test skip

## Title rules

### PRDESC-TITLE-001: Select one title by fixed precedence

- Generate exactly one suggested title.
- Apply this decision order:
  - New Resource and Data Source sharing the same Terraform name
  - New Resource, with its required List Resource treated as implied
  - New standalone Data Source
  - New List Resource for an existing Resource
  - New Action, Ephemeral Resource, Function, or provider feature
  - User-facing bug fix
  - User-facing enhancement
  - SDK, API version, or dependency update
  - Contributor guidance under `contributing/**`
  - Documentation-only change outside `contributing/**`
  - CI or maintenance-only change
- Supporting and companion surfaces do not compete with the primary surface.
- **Provenance**: Inferred maintainer convention.
- **Evidence**:
  - The ordering follows AzureRM's surface-oriented contribution and changelog model

### PRDESC-TITLE-002: Use exact new-surface title shapes

- Use ``New (Data Source|Resource) - `{{RESOURCE_NAME}}``` when one Terraform name introduces both a Resource and Data Source.
- Use ``New Resource: `{{RESOURCE_NAME}}``` for a new Resource.
- Use ``New Data Source: `{{DATA_SOURCE_NAME}}``` for a standalone new Data Source.
- Use ``New List Resource: `{{RESOURCE_NAME}}``` for List Resource support added to an existing Resource.
- Do not add `List Resource` to a new Resource title when the List Resource is its required companion.
- **Provenance**: Published upstream standard.
- **Evidence**:
  - `https://github.com/hashicorp/terraform-provider-azurerm/tree/main/contributing/topics/guide-opening-a-pr.md`
  - `https://github.com/hashicorp/terraform-provider-azurerm/tree/main/contributing/topics/guide-list-resource.md`

### PRDESC-TITLE-003: Make existing-surface titles concrete

- Name the affected Terraform surface explicitly.
- Prefer change-focused wording that can also serve as a squash-merge or changelog theme.
- Use concrete forms such as `add support for`, `improve validation for`, and `correctly populate`.
- Prefix existing Data Source changes with `Data Source:` and existing List Resource changes with `List Resource:` when needed for clarity.
- Use `Contributing:` only when the primary change is under `contributing/**`.
- Use `Docs:` for documentation-only changes outside `contributing/**`.
- Do not use bracketed title prefixes unless the resolved-base repository guidance explicitly requires them.
- **Provenance**: Published upstream standard.
- **Evidence**:
  - `https://github.com/hashicorp/terraform-provider-azurerm/tree/main/contributing/topics/guide-opening-a-pr.md`

### PRDESC-TITLE-004: Reject vague title forms

- Do not use titles equivalent to `fix bug`, `fixes #1234`, `new resource`, or `upgrade sdk`.
- Do not use broad property lists without naming their owning surface.
- Mark the meaningful-title checklist item only after the selected title satisfies all applicable title rules.
- **Provenance**: Published upstream standard.
- **Evidence**:
  - `https://github.com/hashicorp/terraform-provider-azurerm/tree/main/contributing/topics/guide-opening-a-pr.md`

## Body rules

### PRDESC-BODY-001: Preserve the resolved-base template

- Render the complete pull request body from `.github/pull_request_template.md` loaded from the selected base commit.
- Preserve every heading, HTML comment, checklist item, and section in its original order.
- Replace examples and placeholders that could be mistaken for contributor claims.
- Do not add prompt-only title reasoning, evidence notes, or potential issue tables inside the copy-ready body.
- **Provenance**: Local safeguard.
- **Evidence**:
  - The resolved-base template is the repository-owned body contract for the target pull request

### PRDESC-BODY-002: Fill description from evidence

- Explain both the observable change and its evidence-supported reason.
- For explicitly confirmed breaking changes, include impact and upgrade steps.
- Do not infer intent that is absent from the diff, pull request metadata, commit messages, or user input.
- **Provenance**: Published upstream standard.
- **Evidence**:
  - `https://github.com/hashicorp/terraform-provider-azurerm/tree/main/contributing/topics/guide-opening-a-pr.md`

### PRDESC-BODY-003: Preserve standard sections conservatively

- Preserve `Community Note` as supplied by the template.
- Fill `Changes to existing Resource / Data Source` only for existing implementation surfaces.
- Summarize only supported validation in `Testing`.
- Preserve the standard `Rollback Plan` unless the user provides a more specific plan.
- Write `No changes to security controls.` when the diff does not affect access control, authentication, authorization, encryption, secret handling, or logging behavior.
- Write `Needs contributor input.` for `Changes to Security Controls` when those areas are touched but impact is not provable.
- **Provenance**: Local safeguard.
- **Evidence**:
  - These fallbacks distinguish verified absence from unresolved contributor intent

### PRDESC-BODY-004: Disclose AI assistance

- Always check the template's AI-assisted option because this workflow drafts the title and body.
- State at minimum `AI was used to draft the PR title and description.`
- **Provenance**: Local safeguard.
- **Evidence**:
  - Invocation of this workflow is direct AI assistance

### PRDESC-BODY-005: Explain Resource Identity exceptions

- For a new Resource without Resource Identity or its required List Resource, require evidence that an upstream-documented exception applies.
- Explain the supported reason in the Description and record any unresolved exception evidence as a gap.
- Do not represent a missing mandatory companion as complete without that explanation.
- **Provenance**: Published upstream standard.
- **Evidence**:
  - `https://github.com/hashicorp/terraform-provider-azurerm/tree/main/contributing/topics/guide-resource-identity.md`
  - `https://github.com/hashicorp/terraform-provider-azurerm/tree/main/contributing/topics/guide-list-resource.md`

## Checklist rules

### PRDESC-CHECK-001: Default checklist claims to unchecked

- Leave checklist items unchecked unless the current invocation has direct evidence for completion.
- Always leave contributor acknowledgement of following guidelines unchecked.
- Always leave confirmation that the contributor checked whether changes close open issues unchecked.
- **Provenance**: Local safeguard.
- **Evidence**:
  - Repository inspection cannot prove contributor acknowledgement or review

### PRDESC-CHECK-002: Check search-dependent items only after successful search

- Check the open-pull-request item only when the search completed and found no open pull request containing an exact changed Terraform surface name in its title or body.
- Leave it unchecked when matches exist or search is unavailable.
- Record matches or unavailable search as evidence notes.
- **Provenance**: Local safeguard.
- **Evidence**:
  - Search completion and exact-name absence are the only observable support for this item

### PRDESC-CHECK-003: Check documentation coverage only when complete

- Check documentation-required items only when the diff contains documentation for every new or changed user-facing Terraform surface.
- Identify each missing document as an evidence gap.
- **Provenance**: Published upstream standard.
- **Evidence**:
  - `https://github.com/hashicorp/terraform-provider-azurerm/tree/main/contributing/topics/guide-opening-a-pr.md`
  - `https://github.com/hashicorp/terraform-provider-azurerm/tree/main/contributing/topics/guide-new-resource.md`

### PRDESC-CHECK-004: Check test claims only from applicable passing evidence

- Check local-test and test-coverage items only when applicable tests exist and current-run output proves the relevant tests passed.
- Apply `PRDESC-EVID-003` to acceptance tests.
- Check the combined tests-and-documentation item only when both are complete for every changed Resource or Data Source.
- **Provenance**: Published upstream standard.
- **Evidence**:
  - `https://github.com/hashicorp/terraform-provider-azurerm/tree/main/contributing/topics/guide-opening-a-pr.md`

### PRDESC-CHECK-005: Handle state migration and pull request type explicitly

- Check the state-migration-only item only for a state-migration-only diff plus explicit user confirmation or authoritative existing pull request evidence naming tested provider versions.
- Check every applicable pull request type among `Bug Fix`, `New Feature`, and `Enhancement` from the changelog classification.
- Check `Breaking Change` only when explicitly confirmed.
- Always check `AI Assisted`.
- **Provenance**: Local safeguard.
- **Evidence**:
  - Pull request type is derived from classified behavior; migration execution and breaking impact require explicit evidence

## Changelog rules

### PRDESC-CHANGELOG-001: Keep changelog work in the pull request body

- Do not tell contributors to edit `CHANGELOG.md` as part of normal pull request preparation.
- Put any recommendation only in the template's `Change Log` section.
- Use `No changelog entry recommended.` when no entry is warranted.
- **Provenance**: Published upstream standard.
- **Evidence**:
  - `https://github.com/hashicorp/terraform-provider-azurerm/tree/main/contributing/topics/maintainer-merging.md`

### PRDESC-CHANGELOG-002: Apply eligibility categories

- Recommend no entry for unit-test-only, acceptance-test-only, refactoring-only, documentation-only, or deprecation-only changes.
- Classify new Resources, Data Sources, Actions, and List Resources as `FEATURES`.
- Classify new properties, new functionality, and SDK or API upgrades as `ENHANCEMENTS`.
- Classify user-facing bug fixes as `BUG FIXES`.
- **Provenance**: Published upstream standard.
- **Evidence**:
  - `https://github.com/hashicorp/terraform-provider-azurerm/tree/main/contributing/topics/maintainer-merging.md`

### PRDESC-CHANGELOG-003: Render automation-ready entries

- Map `FEATURES` to `[FEATURE]`, `ENHANCEMENTS` to `[ENHANCEMENT]`, and `BUG FIXES` to `[BUG]`.
- Start each entry with the keyword followed by `* `.
- Use the full Resource or Data Source name and lower-case change wording after its surface prefix.
- Do not end the sentence with a period.
- Do not append a pull request number placeholder.
- Use one line per independently classified user-facing surface or change.
- Use the Oxford comma for lists of three or more properties.
- **Provenance**: Published upstream standard.
- **Evidence**:
  - `https://github.com/hashicorp/terraform-provider-azurerm/tree/main/contributing/topics/maintainer-merging.md`

### PRDESC-CHANGELOG-004: Preserve feature companions and stable ordering

- Give a required List Resource its own `[FEATURE] * **New List Resource**` entry even when implied by the new Resource title.
- Order entries by `[FEATURE]`, `[ENHANCEMENT]`, then `[BUG]`.
- Within each keyword, order new Resource, Data Source, Action, List Resource, provider, dependency, then remaining full Terraform names lexically.
- **Provenance**: Published upstream standard.
- **Evidence**:
  - `https://github.com/hashicorp/terraform-provider-azurerm/tree/main/contributing/topics/maintainer-merging.md`
  - `https://github.com/hashicorp/terraform-provider-azurerm/tree/main/contributing/topics/guide-list-resource.md`

### PRDESC-CHANGELOG-005: Do not invent breaking-change automation

- When a breaking change is explicitly confirmed, write `Breaking change; maintainer-managed changelog entry required.`
- Require impact and upgrade steps in Description.
- Do not invent an automation keyword for a breaking change.
- **Provenance**: Published upstream standard.
- **Evidence**:
  - `https://github.com/hashicorp/terraform-provider-azurerm/tree/main/contributing/topics/maintainer-merging.md`

## Issue rules

### PRDESC-ISSUE-001: Add confirmed issue links only from authoritative evidence

- Include a related issue only when explicitly supplied by the user, present in authoritative existing pull request text, or written as `#{{ISSUE_NUMBER}}` or a full GitHub issue URL in a branch commit message.
- Otherwise write `No related issue confirmed.` in the body.
- Do not promote advisory search results into `Fixes`, `Closes`, or `Resolves` references.
- **Provenance**: Local safeguard.
- **Evidence**:
  - Search similarity does not prove that a change fully resolves an issue

### PRDESC-ISSUE-002: Build potential-issue terms deterministically

- Build terms in this order:
  - Exact changed Terraform surface names in lexical order
  - Property named in the generated title
  - Up to nine other added or behaviorally changed schema properties in lexical order, excluding `id`, `name`, `location`, and `tags`
  - Up to three changed error-message fragments in lexical order
- Search open issues in `hashicorp/terraform-provider-azurerm` with quoted exact terms.
- Search each surface alone, each property with the service package, and each error fragment with the primary surface.
- **Provenance**: Local safeguard.
- **Evidence**:
  - Ordered exact terms make advisory searches repeatable and constrain noise

### PRDESC-ISSUE-003: Filter and rank advisory candidates

- Exclude pull requests and deduplicate issue results.
- Include a candidate only when it contains an exact Terraform surface name or at least two exact property, service, behavior, or error identifiers from the diff.
- Rank exact surface matches first, property matches second, and behavior or error matches third; break ties by issue number ascending.
- Return at most five candidates.
- **Provenance**: Local safeguard.
- **Evidence**:
  - Multi-identifier filtering limits plausible but weakly related issue matches

### PRDESC-ISSUE-004: Keep issue search non-blocking

- Render `No potential related issues found.` after a successful search with no plausible matches.
- Render `Potential related issue search unavailable.` when search cannot run.
- Continue drafting when potential-issue search is unavailable.
- **Provenance**: Local safeguard.
- **Evidence**:
  - Advisory search availability must not block a locally evidenced pull request draft

## Output rules

### PRDESC-OUT-001: Emit a schema-conformant internal payload

- The skill must emit one payload conforming to `.github/instructions/pr-description-draft.schema.json`.
- Include resolved base metadata, changed files, classified surfaces, title and governing rule IDs, complete body, checklist decisions, changelog decision, evidence gaps, and issue-search status and candidates.
- The prompt must validate the payload before presentation.
- **Provenance**: Local safeguard.
- **Evidence**:
  - A structured handoff prevents drafting procedure and presentation from silently diverging

### PRDESC-OUT-002: Render exactly five top-level sections

- Render these exact level-two headings in order:
  - `Suggested PR Title`
  - `Why This Title`
  - `Draft PR Body`
  - `Evidence Notes`
  - `Potential Related Issues`
- Put the one title in a plain-text code block.
- Keep `Why This Title` to one evidence-based sentence.
- Put the complete copy-ready body in one `markdown` code block.
- Render evidence gaps as concise bullets or `No unresolved evidence gaps.`.
- Render potential issues as `Issue | Title | Why it may relate`, the no-results sentence, or the unavailable sentence.
- **Provenance**: Local safeguard.
- **Evidence**:
  - Stable output separates copy-ready content from advisory evidence and issue candidates

### PRDESC-OUT-003: End with the verification footer

- After `Potential Related Issues`, append these exact lines:

  ```text
  Preflight complete: yes
  Skill used: pr-description
  ```

- Emit no alternate titles, draft commentary, or text after the footer.
- **Provenance**: Local safeguard.
- **Evidence**:
  - The footer gives observable proof that the required workflow loaded and ran

## Failure rules

### PRDESC-FAIL-001: Hard-stop on ineligible repository state

- Hard-stop for the wrong repository, a missing AzureRM structure, the `main` branch, or an empty complete change-set.
- Name a missing required base-revision authority exactly.
- **Provenance**: Local safeguard.
- **Evidence**:
  - These states cannot produce an eligible, evidence-based candidate pull request draft

### PRDESC-FAIL-002: Hard-stop when no comparison base exists

- Hard-stop when none of the ordered base sources can be resolved or a merge base cannot be computed.
- Ask the contributor to configure `upstream`, provide a usable `origin/main`, or identify the base ref.
- **Provenance**: Local safeguard.
- **Evidence**:
  - Scope cannot be classified without a deterministic comparison origin

### PRDESC-FAIL-003: Hard-stop on unrelated primary changes

- Apply `PRDESC-SCOPE-004` before title or body rendering.
- Name the conflicting service packages or primary surfaces when evidence supports them.
- **Provenance**: Local safeguard.
- **Evidence**:
  - The prompt must not conceal branch-splitting or primary-change ambiguity

### PRDESC-FAIL-004: Hard-stop on invalid structured handoff

- Do not render any normal output when the skill payload fails schema validation.
- Use the prompt-owned exact schema-invalid hard-stop string.
- **Provenance**: Local safeguard.
- **Evidence**:
  - Rendering a malformed handoff would bypass required evidence and decision fields

<!-- PRDESC-CONTRACT-EOF -->
