---
description: "Draft an AzureRM pull request title and copy-ready body from the complete current branch change-set."
---

# Draft AzureRM Pull Request Description

## Execution guardrails

### Fresh-run requirement

- Treat every invocation as a new drafting run.
- Do not reuse repository state, base resolution, diff output, searches, classifications, validation evidence, or draft content from an earlier turn.
- Execute the full procedure even when the user supplies no arguments.

### Repository-preserving operations

- The Git history inspection, repository inspection, pull request metadata, open pull request search, and open issue search operations required below are authorized by this prompt.
- A targeted fetch of only the selected `upstream/main` or `origin/main` remote-tracking ref is authorized when it uses `--no-tags`, `--no-recurse-submodules`, `--no-write-fetch-head`, and an explicit source-to-remote-tracking refspec. It may download objects and update that remote-tracking ref, but it must not modify local `main`, the current branch, `FETCH_HEAD`, the index, or working files.
- Do not pull, merge, rebase, commit, push, checkout, reset, clean, edit files, or otherwise change repository or branch state.
- Do not run tests automatically. Use test output only when it was explicitly gathered in the current invocation or is eligible existing pull request evidence under the contract.

### Command effect labels

- Before every terminal command batch, display the exact command or commands under one of these labels:
  - `[Read-only] {{PURPOSE}}`
  - `[Updates remote-tracking ref: {{FULL_REMOTE_TRACKING_REF}} only]`
- The labels describe repository effects. A `[Read-only]` `go run` fingerprint command may update the Go build cache outside the repository, but must not change repository refs, the index, or working files.
- Do not combine read-only inspection and the targeted fetch in one terminal batch.

### Efficient execution

- Batch independent reads and tool calls in the same response instead of issuing them serially.
- Reuse current-run evidence; do not rerun or reread an operation whose complete result is already available.
- Keep terminal commands small and single-purpose. Do not generate large ad hoc scripts to assemble the payload.
- Collect the complete changed-path inventory once, then request compact targeted patches instead of emitting and rereading an oversized repository-wide patch.
- Use the phases below as the normal model/tool boundaries and avoid adding intermediate rounds that do not resolve a concrete evidence dependency.

### Determinism

- Follow the loaded contract rather than prompt memory.
- Do not guess missing facts or emit alternate titles.
- Do not begin normal output until the structured payload is complete and schema-valid.
- Emit the normal response exactly once and add no text after its verification footer.

## Mandatory procedure

### Load prerequisites

- Load these three files concurrently:
  - `.github/instructions/pr-description-compliance-contract.instructions.md` to EOF.
  - `.github/skills/pr-description/SKILL.md` to EOF.
  - `.github/instructions/pr-description-draft.schema.json` to EOF.
- Verify `.github/skills/pr-description/scripts/pr-description-fingerprint.go` exists and is readable. Do not load its source into model context unless diagnosing the helper.
- Verify its final non-empty line is `<!-- PRDESC-CONTRACT-EOF -->`.
- Verify its final non-empty line is `<!-- PRDESC-SKILL-EOF -->`.
- If any prerequisite is absent, unreadable, or not fully loaded, hard-stop with exactly:
  - `Cannot run draft-pr-description: required workflow files are missing, incomplete, or stale. Confirm the PR description contract, skill, and schema are installed and readable to EOF.`

### Verify repository eligibility

- Apply `PRDESC-PRE-*`.
- Confirm the repository name is `terraform-provider-azurerm` and the expected AzureRM structure exists.
- Determine the current branch.
- If the repository is ineligible, hard-stop with exactly:
  - `Cannot run draft-pr-description: this prompt only supports hashicorp/terraform-provider-azurerm or a fork with the same repository name and expected AzureRM structure.`
- If the current branch is `main`, hard-stop with exactly:
  - `Cannot run draft-pr-description: the current branch is main. Switch to the candidate pull request branch and re-run this prompt.`

### Discover existing pull request evidence

- Collect repository root, repository identity, current branch, remotes, and working-tree status in one `[Read-only]` repository-inspection batch.
- Compute the initial `sha256-v1` repository-state fingerprint with the checked-in helper from `PRDESC-PRE-005` in a separate `[Read-only] Repository fingerprint` batch.
- Prefer `go run .github/skills/pr-description/scripts/pr-description-fingerprint.go --repository-root {{REPOSITORY_ROOT}}` when `go` resolves in the current terminal.
- On local Windows only, if direct Go is unavailable, inspect registered WSL distributions and the selected distribution's interactive Go environment. Resolve the repository path with `wslpath`, then invoke the helper with:
  - `wsl.exe -d {{WSL_DISTRO}} --cd {{WSL_REPOSITORY_ROOT}} -- bash -ic 'go run .github/skills/pr-description/scripts/pr-description-fingerprint.go --repository-root .'`
- If neither direct Go nor Go in an explicitly inspected WSL distribution is available, hard-stop with exactly:
  - `Cannot run draft-pr-description: the repository fingerprint helper requires Go in the current environment or an explicitly selected WSL distribution. Install Go or reopen the repository in its Go-enabled environment, then re-run this prompt.`
- Apply `PRDESC-PR-*` in one discovery batch:
  - Inspect active pull request metadata.
  - When active metadata is absent or does not match the checkout, search for an open pull request with the exact head repository and branch.
  - When no active branch identity is proven, query pull requests associated with the exact current `HEAD` commit across all states when the available GitHub tool or API supports commit association.
- Fetch full metadata only for identity candidates and classify their trust before using their body, references, testing text, or target base.
- Treat unavailable commit-association lookup as unavailable evidence, not as proof that no historical pull request exists.
- Record the initial fingerprint for the final repository-stability check without emitting its staged, unstaged, or untracked component inputs into model context.

### Resolve the comparison base

- Apply `PRDESC-BASE-*` in exact priority order.
- Use `active-branch-identity` pull request base metadata when available.
- Otherwise inspect `upstream/main`, then `origin/main`, then local `main`.
- When selecting a remote-tracking ref, explain that the workflow is refreshing only the remote-tracking comparison reference and will not checkout, merge, rebase, reset, commit, modify local `main`, or change working files.
- Before fetching, display `[Updates remote-tracking ref: refs/remotes/{{REMOTE}}/{{BASE_BRANCH}} only]` followed by the fully resolved fetch command.
- Attempt the authorized targeted fetch using exactly `git fetch --no-tags --no-recurse-submodules --no-write-fetch-head {{REMOTE}} refs/heads/{{BASE_BRANCH}}:refs/remotes/{{REMOTE}}/{{BASE_BRANCH}}`.
- Resolve the selected commit and find its common ancestor with `HEAD`.
- Describe common-ancestor inspection as finding where the branch diverged for comparison; state that no merge is performed and no files or branches are modified.
- If no base or common ancestor can be resolved, hard-stop with exactly:
  - `Cannot run draft-pr-description: no comparison base could be resolved. Configure upstream/main, provide a usable origin/main, or identify the pull request base ref, then re-run this prompt.`

### Load core base-revision authorities

- Load the template, `contributing/README.md`, opening guide, and changelog guide required by `PRDESC-PRE-003` concurrently from the selected base commit.
- Do not substitute candidate-branch copies for missing base-revision files.
- If a required file is missing, hard-stop with exactly this form, replacing the placeholder with the repo-relative path:
  - `Cannot run draft-pr-description: required base-revision source is missing: {{MISSING_PATH}}.`

### Collect the complete change-set

- Apply `PRDESC-SCOPE-001`.
- Gather one common-ancestor-to-working-tree tracked path-and-status inventory.
- Gather non-ignored untracked paths with `git ls-files --others --exclude-standard` and inspect their contents.
- Gather current branch commit messages from the common ancestor through `HEAD` for explicit issue references and supporting context.
- If the complete tracked and untracked scope is empty, hard-stop with exactly:
  - `Cannot run draft-pr-description: no changes were found relative to the resolved comparison base.`

### Classify paths and load specialized policy

- Route the current-run evidence through `.github/skills/pr-description/SKILL.md`.
- Apply `PRDESC-SCOPE-*` to every changed path and stop before drafting when unrelated primary changes span service packages.
- On that conflict, hard-stop with exactly:
  - `Cannot run draft-pr-description: unrelated primary changes span multiple service packages. Identify the primary change or split the branch, then re-run this prompt.`
- Load only the specialized new-resource, Resource Identity, and List Resource guides that `PRDESC-PRE-003` requires for the classified paths, in one concurrent read batch.
- Inspect compact targeted patches for every primary or materially changed user-facing surface plus only the companion evidence needed for registration, Resource Identity, List Resource, documentation, tests, security, and changelog decisions.

### Draft title and changelog decisions

- Have the `pr-description` skill apply `PRDESC-TITLE-*` and `PRDESC-CHANGELOG-*` first.
- Preserve base-revision changelog authority and strict automation-ready entry validation.
- Require category and automation keyword agreement, at least one entry for `recommended`, zero entries for `not-recommended` and `breaking-input-required`, and the contract-owned exact fallback text.
- Do not render user-visible output yet.

### Perform targeted searches

- Apply `PRDESC-CHECK-002` and search open pull requests with no more than its two exact-surface queries.
- Run every applicable duplicate-pull-request query concurrently.
- Treat unavailable open pull request search as an evidence gap and leave its checklist item unchecked.
- Apply `PRDESC-ISSUE-002` through `PRDESC-ISSUE-004` and issue no more than four high-signal open-issue queries.
- Run every applicable issue query concurrently in one batch.
- Search open issues only; exclude pull requests.
- Keep the search advisory and non-blocking.
- Return successful no-match or unavailable status explicitly.

### Draft the body and decisions

- Have the `pr-description` skill apply `PRDESC-PR-*`, `PRDESC-EVID-*`, `PRDESC-BODY-*`, and `PRDESC-CHECK-*` using the completed title, changelog, duplicate, and issue evidence.
- Produce one title, one evidence-based title explanation, the complete template-preserving body, checklist decisions, changelog decision, structured pull request evidence, and evidence gaps.
- Preserve authoritative confirmed references under `PRDESC-PR-004`; keep commit-association-only references outside the copy-ready body.
- Populate `existingPullRequest.confirmedReferences` only from the identity-trusted pull request before conflict resolution, and populate `relatedIssues.confirmedReferences` with the final body-approved references from all authoritative sources.
- Do not render user-visible output yet.

### Validate the structured payload

- Have the `pr-description` skill finish the handoff required by `PRDESC-OUT-001`.
- Recompute the complete `sha256-v1` repository-state fingerprint with the same checked-in helper, Go invocation path, and Git execution environment immediately before payload validation, under `[Read-only] Repository fingerprint`.
- If it differs from the initial fingerprint, discard all collected evidence and restart the complete procedure once with a new initial fingerprint.
- On the restarted run, if the final fingerprint differs again, hard-stop with exactly:
  - `Cannot run draft-pr-description: repository state changed repeatedly during evidence collection. Stop concurrent edits and re-run this prompt.`
- Record the equal initial and final fingerprints, `stable=true`, and restart count in `repositoryState`.
- Validate the entire payload against `.github/instructions/pr-description-draft.schema.json` before rendering.
- If validation fails, hard-stop with exactly:
  - `Cannot run draft-pr-description: pr-description produced a schema-invalid draft payload. Refresh the workflow files and re-run this prompt.`

## Output format

- Apply `PRDESC-OUT-002` and `PRDESC-OUT-003` exactly.
- Render only this shape:

  ````markdown
  ## Suggested PR Title

  ```text
  {{TITLE}}
  ```

  ## Why This Title

  {{ONE_EVIDENCE_BASED_SENTENCE}}

  ## Draft PR Body

  ```markdown
  {{COMPLETE_COPY_READY_BODY}}
  ```

  ## Evidence Notes

  {{EVIDENCE_GAP_BULLETS_OR_EXACT_EMPTY_SENTENCE}}

  ## Potential Related Issues

  {{ISSUE_TABLE_OR_EXACT_NO_RESULTS_OR_UNAVAILABLE_SENTENCE}}

  Preflight complete: yes
  Skill used: pr-description
  ````

- Use the exact table header `Issue | Title | Why it may relate` when candidates exist.
- Render `No unresolved evidence gaps.` when the payload has no evidence gaps.
- Render `No potential related issues found.` after a successful search with no candidates.
- Render `Potential related issue search unavailable.` when search is unavailable.
- Do not emit any text after `Skill used: pr-description`.
