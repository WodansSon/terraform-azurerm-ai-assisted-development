# PR Description Prompt Proposal

## Purpose

- Define a shipped prompt that runs inside `hashicorp/terraform-provider-azurerm` or a contributor's fork of that repository.
- Generate a suggested pull request title and a draft pull request body from the current branch diff.
- Keep the output aligned to the AzureRM contributor workflow instead of this source repository's local workflow.

## Status

- Implemented as the shipped `/draft-pr-description` workflow.
- This document remains the repo-only design record; runtime behavior is owned by the prompt, skill, contract, and schema listed below.
- The runtime files are intentionally included in `installer/file-manifest.config`.

## Proposed Name

- Preferred: `draft-pr-description`
- Acceptable: `prepare-pr-description`
- Avoid: `code-review-create-pr-description`

Reasoning:

- The behavior is authoring, not auditing.
- Keeping it separate from review prompts avoids mixing review-only workflow rules into a drafting flow.

## Proposed Runtime Architecture

Use one explicit prompt entrypoint backed by one workflow skill, one normative contract, and one structured handoff schema.

### Runtime Files

- `.github/prompts/draft-pr-description.prompt.md`
	- The only documented user-facing entrypoint: `/draft-pr-description`.
	- Owns fresh-run behavior, prerequisite loading, stage order, authorized read-only tool execution, exact hard-stop messages, schema validation, and final response rendering.
	- Must load the contract, skill, and schema to EOF before collecting change evidence.
- `.github/skills/pr-description/SKILL.md`
	- Owns the reusable method for resolving and classifying scope, applying the contract, drafting title and body content, making checklist and changelog decisions, and producing the structured handoff payload.
	- Must not redefine normative title, evidence, checklist, changelog, or output rules that belong in the contract.
	- Must not be documented as a second user entrypoint.
- `.github/instructions/pr-description-compliance-contract.instructions.md`
	- The single normative source for `PRDESC-*` rules.
	- Defines precedence, evidence requirements, scope and base resolution, classification, title selection, template preservation, checklist decisions, changelog decisions, issue search, failure behavior, and output semantics.
	- Declares both the prompt and skill as consumers with `Requires EOF Load: yes`.
- `.github/instructions/pr-description-draft.schema.json`
	- Defines the internal payload passed from the skill-owned drafting method to prompt-owned presentation.
	- Must include resolved base metadata, classified surfaces, the title and governing rule IDs, the complete draft body, checklist decisions, changelog decisions, evidence gaps, and related-issue search status and candidates.
	- The prompt must hard-stop before rendering if the payload does not conform to this schema.

### Ownership Boundaries

- The prompt owns invocation, orchestration, hard stops, payload validation, and presentation.
- The skill owns the reusable drafting procedure and emits a schema-conformant payload; it does not own final Markdown presentation.
- The contract owns all requirements that need stable rule IDs or must remain consistent across prompt and skill revisions.
- The schema owns payload shape only; it must not introduce policy defaults or duplicate contract prose.
- Upstream AzureRM files loaded from the resolved base remain the runtime repository-policy authorities described in `Canonical Sources Of Truth`.

Use the `PRDESC-<AREA>-<NNN>` rule ID format with these initial areas:

- `PRE` for preflight and repository eligibility.
- `BASE` for comparison-base resolution.
- `SCOPE` for change collection and surface classification.
- `EVID` for evidence and validation claims.
- `TITLE` for title selection and formatting.
- `BODY` for template preservation and body content.
- `CHECK` for checklist decisions.
- `CHANGELOG` for changelog eligibility and rendering.
- `ISSUE` for confirmed and potential issue handling.
- `OUT` for final output semantics.
- `FAIL` for exact hard-stop behavior.

### Intentionally Omitted Layers

- Do not add `ai-skill-routing-pr-description.instructions.md` in the first version. The explicit prompt already loads the skill and contract, and this workflow has no meaningful file-path `applyTo` scope. An unscoped router would add always-on instructions without improving determinism.
- Do not add a separate companion rule file. Stable rules belong in the compliance contract, while reusable procedure belongs in the skill.
- Do not split presentation into another skill. The five-section response is small enough for the prompt to render directly from the schema-conformant payload.
- Add companion guidance later only if worked examples become too large for the skill; any companion must defer authority to the contract.

### Implementation Change Set

When moving this proposal into runtime payload:

- Add the four runtime files above to `installer/file-manifest.config` under their matching sections.
- Add `/draft-pr-description` to the prompt tables and examples in `README.md` and `installer/README.md`.
- Update `docs/ARCHITECTURE.md` and `docs/AI_CUSTOMIZATION_ARCHITECTURE_STANDARD.md` to list the new prompt, skill, contract, and schema.
- Update `docs/CODE_REVIEW_RULES.md` to document the new `PRDESC-*` contract family even though the workflow authors rather than reviews a PR description.
- Add a user-visible `CHANGELOG.md` entry because the shipped toolkit gains a new prompt capability.
- Add adjudicated regression cases and runnable result artifacts before treating the implementation as complete.

Minimum regression coverage must include:

- New Resource plus mandatory List Resource.
- New Resource, Data Source, and mandatory List Resource sharing one Terraform name.
- Standalone List Resource for an existing Resource.
- Existing Resource enhancement and bug fix title precedence.
- Documentation-only and contributor-guidance-only changes.
- Mixed unrelated service-package changes that require a hard stop.
- Existing PR base metadata plus local unpushed changes.
- Missing required base-revision template or contributor guidance.
- Successful, skipped, missing, and stale validation evidence.
- Confirmed issue linkage, plausible advisory matches, no matches, and unavailable GitHub search.
- Schema-invalid skill payload and exact hard-stop output.
- Exact five-section output plus the required verification footer.

## Runtime Scope

- The prompt runs in the `hashicorp/terraform-provider-azurerm` repository where the contributor is preparing the pull request.
- The prompt should assume the current branch is the candidate pull request branch.
- The prompt should inspect committed, staged, unstaged, and non-ignored untracked changes relative to the resolved pull request base.
- The prompt should generate a suggested title plus a draft body, not open or update a pull request automatically unless a later workflow explicitly adds that capability.
- The first version should be AzureRM-specific and should not try to generalize across other repositories.

## Canonical Sources Of Truth

Use these runtime authorities by domain:

- PR body shape and section order: `.github/pull_request_template.md` from the resolved base revision.
- PR title requirements: `contributing/topics/guide-opening-a-pr.md` from the resolved base revision plus the explicit title rules in this proposal.
- Changelog eligibility and formatting: `contributing/topics/maintainer-merging.md` from the resolved base revision.
- New Resource, Resource Identity, and List Resource requirements: `contributing/topics/guide-new-resource.md`, `contributing/topics/guide-resource-identity.md`, and `contributing/topics/guide-list-resource.md` from the resolved base revision.
- Change evidence: the current branch diff, working tree, explicit current-run command output, user input, and authoritative existing PR metadata when available.

Change evidence can determine what happened, but it must not override contributor workflow policy.

## Deterministic Runtime Procedure

### Preflight

- Verify that the checkout is `hashicorp/terraform-provider-azurerm` or a fork with the same repository name and expected AzureRM structure.
- Require `.github/pull_request_template.md`, `contributing/README.md`, `contributing/topics/guide-opening-a-pr.md`, `contributing/topics/maintainer-merging.md`, `contributing/topics/guide-new-resource.md`, `contributing/topics/guide-resource-identity.md`, and `contributing/topics/guide-list-resource.md` in the resolved base revision.
- Hard-stop if the current branch is `main` or if no change exists relative to the resolved base.
- Do not pull, merge, rebase, commit, push, or otherwise change the contributor's worktree or branch.

### Base Resolution

Resolve the comparison base in this order:

1. The current base commit SHA from authoritative existing PR metadata for the current branch.
2. `upstream/main` when the `upstream` remote exists.
3. `origin/main` when it exists.
4. Local `main`.

- When selecting `upstream/main` or `origin/main`, refresh that remote-tracking ref with a read-only fetch when available.
- If the fetch fails, continue with the existing local remote-tracking ref and disclose that it may be stale in `Evidence Notes`.
- Compute the merge base between the selected base commit or ref and `HEAD`; use that merge-base commit for diff collection.

### Change Collection

- Use one diff from the merge-base commit to the working tree so committed, staged, and unstaged tracked changes are represented without double-counting.
- Use `git ls-files --others --exclude-standard` to identify non-ignored untracked files and inspect their contents separately.
- Preserve added, modified, renamed, copied, and deleted file status.
- Treat authoritative existing PR metadata as supplemental context for the base commit, PR number, explicit issue references, and existing contributor-provided evidence; do not let PR metadata replace local unpushed changes.
- Ignore generated and vendored files when choosing the dominant title surface unless the PR is specifically an SDK, API, dependency, or generated-code update.

### Classification And Drafting

- Classify changed files in lexical path order.
- Identify new and existing Resources, Data Sources, List Resources, Actions, Ephemeral Resources, Functions, provider features, SDK or API updates, documentation, contributor guidance, tests, and CI or maintenance changes.
- Treat tests, documentation, Resource Identity, registration, and mandatory List Resource changes as companion surfaces when they support the same primary implementation.
- Apply the title decision order defined in `Title Rules`.
- Render the complete PR body using the base-revision template and the exact body rules below.
- Search open PRs for each exact Terraform surface name before rendering the PR checklist.
- Search for potential related issues only after the title and body are drafted.
- Emit the five output sections in the order defined by `Proposed Output Contract` and do not add other top-level output.

## AzureRM-Specific Interpretation

- The AzureRM upstream repo owns the pull request workflow contract.
- This source repository should ship prompt logic that adapts to the consumer repo's files instead of hardcoding this repo's local PR title conventions.
- For AzureRM specifically, title generation should follow the contributor guidance in `guide-opening-a-pr.md`, not the bracket-prefix style used by this source repository's local template.
- For the changelog section specifically, recommendation logic should follow `maintainer-merging.md`.

## Title Rules

The first version should generate exactly one title suggestion. Alternative title suggestions can be added later if user feedback shows they would be useful.

Required behavior:

- Make the title concrete and change-focused.
- Prefer the same core wording that would make sense as the squash merge commit title.
- Prefer wording that could plausibly match the eventual changelog entry theme.
- Name the affected surface explicitly.
- Use the `Contributing:` title prefix when the primary change is under `contributing/**`; do not use it for changes outside that path.
- Treat a List Resource as an implied required companion when it is added with a new Resource; do not add `List Resource` to the title in that case.
- Use `New List Resource:` when adding List Resource support to an existing Resource.
- When the same Terraform name introduces both a new Resource and a new Data Source, use the exact prefix `New (Data Source|Resource) -` followed by the Terraform name in backticks.

Use this title decision order:

1. A new Resource and Data Source with the same Terraform name.
2. A new Resource, with its mandatory List Resource treated as implied.
3. A new standalone Data Source.
4. A new List Resource for an existing Resource.
5. A new Action, Ephemeral Resource, Function, or provider feature.
6. A user-facing bug fix.
7. A user-facing enhancement.
8. An SDK, API version, or dependency update.
9. Changes under `contributing/**`.
10. Documentation-only changes outside `contributing/**`.
11. CI or maintenance-only changes.

- Supporting tests, documentation, registration, Resource Identity, generated code, and vendored SDK changes do not compete with the primary surface for title ownership.
- When the diff contains unrelated primary changes across multiple service packages, stop and ask the contributor to identify the primary change or split the branch rather than guessing.

For AzureRM, preferred title patterns include:

- ``azurerm_resource_name - add support for the `field_name` property``
- ``azurerm_resource_name - improve validation for the `field_name` property``
- ``azurerm_resource_name - correctly populate the `field_name` attribute``
- ``Data Source: azurerm_data_source_name - export the `field_name` attribute``
- ``List Resource: azurerm_resource_name - add support for filtering by `field_name```
- ``New Resource: `azurerm_resource_name```
- ``New (Data Source|Resource) - `azurerm_resource_name```
- ``New List Resource: `azurerm_resource_name```
- ``New Data Source: `azurerm_data_source_name```
- ``Docs: Fix incorrect import example for azurerm_resource_name``
- ``dependencies: service_name - update API version to `YYYY-MM-DD```
- ``Contributing: add list resource guidance for sub-resources``

The prompt should avoid titles like:

- ``fix bug``
- ``fixes #1234``
- ``new resource``
- ``upgrade sdk``
- overly broad property lists without naming the surface they belong to

The prompt should not use bracketed title prefixes such as `[BUG:]` or `[ENHANCEMENT:]` when running in AzureRM unless the consumer repository explicitly requires that format in its own runtime guidance.

## Body Rules

The body should be rendered against the pull request template loaded from the resolved base revision.

- Preserve every template heading, HTML comment, checklist item, and section in its original order for the first version.
- Do not add `Suggested PR Title`, `Why This Title`, `Evidence Notes`, or `Potential Related Issues` inside the copy-ready PR body.
- Replace example placeholders such as `Fixes #0000` and sample changelog entries; do not leave template examples that could be mistaken for contributor claims.

For AzureRM, the prompt should preserve the existing section structure and fill only sections it can support with evidence:

- `Community Note`: preserve as-is from the template.
- `Description`: explain what changed and why.
- `PR Checklist`: leave checklist state conservative unless direct evidence supports a checked item.
- `Changes to existing Resource / Data Source`: fill when the diff touches existing implementation surfaces.
- `Testing`: summarize only validation that can be supported by explicit evidence.
- `Change Log`: provide a suggested entry only when warranted under `maintainer-merging.md`.
- Keep all changelog output inside the template's `Change Log` section; do not add a separate maintainer-only recommendation block.
- `Related Issue(s)`: include only issue references explicitly supplied by the user, present in an existing PR body, or written as `#1234` or a full GitHub issue URL in a commit message. Otherwise write `No related issue confirmed.`
- `AI Assistance Disclosure`: always check the AI-assisted box because this prompt drafted the title and body, and state at minimum `AI was used to draft the PR title and description.`
- `Rollback Plan`: preserve the template's standard rollback text unless the user provides a more specific plan.
- `Changes to Security Controls`: write `No changes to security controls.` when the diff does not change access control, authentication, authorization, encryption, secret handling, or logging behavior. Use `Needs contributor input.` when the diff touches those areas but impact is not provable.

## Evidence Rules

The prompt must not invent facts.

Allowed evidence:

- Branch diff content
- Changed file paths
- Current repository template and contributor docs
- Explicit local command output gathered in the current run
- Explicit user-provided issue numbers or context

Disallowed evidence:

- Guessed intent not supported by code or user input
- Assumed test execution
- Assumed changelog eligibility
- Assumed issue linkage
- Assumed breaking-change impact

If evidence is missing, use the exact section-specific fallback defined in `Body Rules`. When no section-specific fallback exists, write `Needs contributor input.` and identify the missing fact in `Evidence Notes`.

- Do not treat a command mentioned in documentation, comments, commit messages, or an existing PR body as proof that it ran successfully.
- Current-run successful command output is required before claiming local validation passed.
- Existing PR testing evidence may be preserved only when it explicitly names the command and result and is not contradicted by the current diff.

## Changelog Decision Rules

The `Change Log` section should be based on `hashicorp/terraform-provider-azurerm/contributing/topics/maintainer-merging.md`.

Required interpretation:

- Contributors should not be told to update `CHANGELOG.md` directly as part of normal pull request preparation.
- The section in the pull request body should describe the recommended changelog entry, if any, for maintainers to use during merge.
- Not every pull request should produce a changelog entry.

For AzureRM, the prompt should recommend no changelog entry when the change is primarily:

- unit test only
- acceptance test only
- refactoring only
- documentation only
- deprecation only

When a changelog entry is warranted, the prompt should classify it into one of the maintainer categories:

- `FEATURES`: new resources, data sources, actions, or list resources
- `ENHANCEMENTS`: new properties, new functionality, or SDK and API upgrades
- `BUG FIXES`: bug fixes

When a changelog entry is warranted, the prompt should prefix the suggested changelog line with the matching automation keyword:

- `FEATURES` -> `[FEATURE]`
- `ENHANCEMENTS` -> `[ENHANCEMENT]`
- `BUG FIXES` -> `[BUG]`

Formatting rules for the suggested entry:

- Use the maintainer automation format, not the final rendered `CHANGELOG.md` line format.
- Start the suggested line with the automation keyword such as `[BUG]`, `[ENHANCEMENT]`, or `[FEATURE]`.
- Follow the keyword with `* ` and then the changelog sentence.
- Start with lower-case wording after the surface name prefix.
- Do not end the sentence with a period.
- Use the full resource or data source name.
- Use complete sentence style such as `add support for`, `improve validation for`, or `correctly populate`.
- Use an Oxford comma when listing three or more properties.
- Do not append a `[GH-12345]` style placeholder in the draft body because the automation appends the GitHub pull request number.
- Emit one line per affected Terraform surface or independently classified user-facing change.
- Order entries by `[FEATURE]`, `[ENHANCEMENT]`, then `[BUG]`; within each keyword, order new Resource, Data Source, Action, List Resource, provider, dependency, then remaining full Terraform names lexically.

Use these feature shapes:

```text
[FEATURE] * **New Resource**: `azurerm_resource_name`
[FEATURE] * **New Data Source**: `azurerm_data_source_name`
[FEATURE] * **New Action**: `azurerm_action_name`
[FEATURE] * **New List Resource**: `azurerm_resource_name`
```

- A mandatory List Resource still receives its own feature changelog line even though it is implied by a new Resource in the PR title.
- When a breaking change is explicitly confirmed, check `Breaking Change`, require impact and upgrade steps in `Description`, and write `Breaking change; maintainer-managed changelog entry required.` instead of inventing an automation keyword.

Suggested rendering shape for AzureRM:

```markdown
## Change Log

[ENHANCEMENT] * `azurerm_resource_name` - add support for the `new_property` property
```

Suggested rendering when no entry is warranted:

```markdown
## Change Log

No changelog entry recommended.
```

## Checklist Rules

Checklist items should default to unchecked unless the prompt has explicit evidence.

- `I have followed the guidelines`: always leave unchecked because repository inspection cannot prove contributor acknowledgement.
- `I have checked to ensure there aren't other open Pull Requests`: check only when the open-PR search completed and found no other PR containing an exact changed Terraform surface name in its title or body.
- `I have checked if my changes close any open issues`: always leave unchecked because advisory issue search cannot prove the contributor reviewed whether an issue is fully resolved.
- `I have updated/added Documentation as required`: check only when the diff contains documentation for every new or changed user-facing Terraform surface; otherwise leave unchecked and identify each missing document in `Evidence Notes`.
- `I have used a meaningful PR title`: check after the generated title passes all `Title Rules`.
- `I have added an explanation of what my changes do and why`: check when `Description` states both the observable change and its evidence-supported reason.
- `I have written new tests ... & updated any relevant documentation`: check only when the diff contains applicable test coverage and documentation for every changed Resource or Data Source.
- `I have successfully run tests with my changes locally`: check only when the current run contains successful output for the relevant tests. A skipped acceptance test is not successful validation unless the required Azure environment variables were present.
- `For changes that include a state migration only`: check only for a state-migration-only diff and explicit user confirmation or authoritative existing PR evidence that the migration was manually tested between named provider versions; otherwise leave unchecked.
- `My submission includes Test coverage ... and the tests pass`: check only when applicable test files are present and current-run output proves the relevant tests passed.
- PR type: check every applicable one of `Bug Fix`, `New Feature`, and `Enhancement` from the changelog classification; check `Breaking Change` only when explicitly confirmed under `Changelog Decision Rules`.
- `AI Assisted`: always check because using this prompt is itself AI assistance.

The prompt may add short evidence notes below a checklist-adjacent section, but it should not fabricate completed work.

## Diff And Scope Rules

- Always use the resolved comparison base and change collection procedure defined in `Deterministic Runtime Procedure`.
- Include committed, staged, unstaged, and non-ignored untracked changes so the draft reflects the full in-progress branch state the contributor is preparing to submit.
- If a pull request already exists and authoritative pull request metadata is available, the prompt may use that metadata to preserve explicit issue links and contributor-provided validation evidence.
- The prompt should summarize touched surfaces before drafting the title so the title is anchored to the dominant user-facing change.
- If the branch contains unrelated primary changes across multiple service packages, apply the hard-stop behavior defined in `Title Rules`.

## Potential Related Issues

- Build search terms in this order: every exact changed Terraform surface name in lexical order; the property named in the generated title; then up to nine other added or behaviorally changed schema property names in lexical order, excluding generic names such as `id`, `name`, `location`, and `tags`; then up to three changed error-message fragments in lexical order.
- Search open issues in `hashicorp/terraform-provider-azurerm` using quoted exact terms. Search each Terraform surface name alone, each property name paired with the service package name, and each error fragment paired with the primary Terraform surface name.
- Exclude pull requests and deduplicate results across search queries.
- Add a `Potential Related Issues` section after the draft PR body and evidence notes.
- For each candidate, include the issue number, title, link, and a brief reason it may relate to the change.
- Treat every result as advisory and require the developer to validate whether the change fully addresses the issue.
- Do not automatically add `Fixes`, `Closes`, or `Resolves` references to the draft PR body.
- Include a candidate only when it contains an exact Terraform surface name or at least two exact property, service, behavior, or error identifiers from the diff.
- Rank exact surface-name matches first, then property matches, then behavior or error matches; break ties by issue number ascending.
- Return at most five candidates using this exact table shape: `Issue | Title | Why it may relate`.
- If no plausible matches are found, state `No potential related issues found.`
- If GitHub issue search is unavailable, state `Potential related issue search unavailable.` and continue generating the title and body.

## Failure Behavior

If a required runtime source is missing:

- Wrong repository or missing AzureRM structure: hard-stop and explain that the prompt only supports `terraform-provider-azurerm`.
- Missing PR template or required contributor guidance in the resolved base: hard-stop and name the missing file.
- Missing comparison base: hard-stop and ask the contributor to configure the upstream remote or identify the base ref.
- Empty diff: hard-stop and state that no PR description can be drafted because no changes were found.

## Proposed Output Contract

The prompt should return these top-level parts in order:

1. `Suggested PR Title`
2. `Why This Title`
3. `Draft PR Body`
4. `Evidence Notes`
5. `Potential Related Issues`

Formatting requirements:

- Render each top-level part as an exact level-two Markdown heading, for example `## Suggested PR Title`.
- Put the single suggested title in a plain-text code block.
- Keep `Why This Title` to one evidence-based sentence.
- Put the complete copy-ready PR body in one `markdown` code block.
- Render `Evidence Notes` as concise bullets, or `No unresolved evidence gaps.` when empty.
- Render `Potential Related Issues` as the required table, the no-results sentence, or the unavailable sentence.
- After `Potential Related Issues`, append this exact verification footer and no other text:

```text
Preflight complete: yes
Skill used: pr-description
```

- Do not emit alternate titles, draft commentary, or any text after the verification footer.

`Evidence Notes` should be brief and should call out any unresolved contributor-input gaps, such as:

- missing issue numbers
- no observed local test evidence
- uncertain changelog eligibility because the branch mixes user-facing and maintenance-only changes

## Non-Goals

- Running acceptance tests automatically as part of drafting
- Marking checklist items complete without evidence
- Editing `CHANGELOG.md` in the consumer repository
- Automatically adding issue-closing references to the draft PR body
- Opening or updating the pull request automatically in the first version
- Replacing the code-review prompts
