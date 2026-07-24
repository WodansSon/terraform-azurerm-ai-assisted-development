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

### Discover and freeze the execution boundary

- Apply `PRDESC-PRE-*`, especially `PRDESC-PRE-007`, before collecting pull request or branch evidence.
- Inspect the current terminal first under `[Read-only] Current environment and worktree discovery`:
  - Resolve the current `git` and `go` executables without assuming an operating system or shell.
  - When Git resolves, run `git rev-parse --show-toplevel` and use its canonical result for validation.
  - Resolve repository name and structure, remotes, checked-out branch, full `HEAD`, staged state, unstaged state, and non-ignored untracked count.
- Use the current worktree directly when repository identity, expected branch, Git, and Go all validate. This applies equally to native Windows, macOS, Linux, WSL, dev containers, Codespaces, SSH, and remote workspaces.
- Determine the expected branch from explicit user input first, then the active checkout or editor repository context. Never infer it from a candidate directory name. If the expected branch cannot be established, ask the developer to identify it before searching.
- If the current environment has a validated AzureRM worktree but lacks Go, preserve that worktree as the known source. Do not substitute another same-branch or same-`HEAD` clone when the known source has staged, unstaged, or untracked changes.
- Search only when the current environment has no suitable worktree:
  - Use explicit repository paths and configurable search roots supplied by the developer or workspace first.
  - Add only existing conventional roots in the current environment: `~/src`, `~/github`, `~/go/src`, and `/workspaces`.
  - Deduplicate canonical roots and search only for directories named `terraform-provider-azurerm` beneath those roots.
  - Do not scan the filesystem root, arbitrary drives, all mounts, or unrelated directory trees.
  - Display every exact bounded search command and root under `[Read-only] Bounded repository discovery`.
- Validate every candidate under `[Read-only] Repository candidate validation` by resolving its canonical top level, repository name and AzureRM structure, remotes, checked-out branch, full `HEAD`, staged state, unstaged state, untracked count, Git executable, and Go executable.
- When a source checkout is already known, compare full `HEAD` and dirty state. Same branch and `HEAD` do not make a clean candidate equivalent to a dirty source checkout.
- Select automatically only when exactly one candidate is trustworthy and it does not substitute for a known dirty source worktree.
- When multiple candidates are trustworthy, do not choose by path order, recency, branch name, or `HEAD`. Ask the developer to select one canonical worktree and show each candidate's environment, path, branch, full `HEAD`, and dirty-state summary.
- When no candidate is trustworthy, request an explicit repository path and explain which capability or identity check was missing. Do not guess.
- On native Windows, consider WSL only after current-terminal and bounded current-OS discovery cannot provide one boundary with both the suitable worktree and helper capability:
  - Discover registered distributions without assuming a name.
  - Verify Git and Go in the explicitly selected distribution.
  - Search its developer-supplied and conventional roots using the same bounded candidate rules, preferring a validated WSL-native worktree.
  - If the known Windows worktree contains the actual changes and WSL can access that same worktree, path translation may be offered as a fallback. Keep repository paths out of the fixed Bash command and preserve argument boundaries.
  - Do not assume `/mnt/c`, a drive letter, a mount point, or a mirror destination.
- If no environment can provide Git, Go, and one validated worktree containing the requested changes, hard-stop with exactly:
  - `Cannot run draft-pr-description: no execution environment provides Git, Go, and one validated terraform-provider-azurerm worktree for the requested branch. Select or provide the repository path that contains the changes, then re-run this prompt.`
- Confirm the selected branch is not `main`. If it is, hard-stop with exactly:
  - `Cannot run draft-pr-description: the current branch is main. Switch to the candidate pull request branch and re-run this prompt.`
- Freeze and record the selected execution environment, canonical worktree, selection method, Git and Go executables, repository name, branch, full `HEAD`, known source `HEAD` when available, working-tree state, candidate count, and bounded search roots in `repositoryState.executionBoundary`.
- Reuse that exact boundary for every remaining command. Do not collect pull request, base, diff, test, fingerprint, or payload evidence from another environment or checkout.

### Discover existing pull request evidence

- Collect repository identity, current branch, remotes, and working-tree status from the frozen boundary in one `[Read-only]` repository-inspection batch.
- Compute the initial `sha256-v1` repository-state fingerprint with the checked-in helper from `PRDESC-PRE-005` in a separate `[Read-only] Repository fingerprint` batch.
- In a current-terminal boundary, invoke `go run .github/skills/pr-description/scripts/pr-description-fingerprint.go --repository-root {{FROZEN_WORKTREE_ROOT}}` with the resolved Go executable.
- In a WSL boundary intentionally using the same mounted Windows worktree, pass the selected distribution and paths as separate PowerShell arguments; do not construct a Bash command by interpolating repository paths. Resolve and invoke with:
  - `$wslRepositoryRoot = (wsl.exe -d "$wslDistro" -- wslpath -a "$repositoryRoot").Trim()`
  - `wsl.exe -d "$wslDistro" --cd "$wslRepositoryRoot" -- bash -ic 'go run .github/skills/pr-description/scripts/pr-description-fingerprint.go --repository-root .'`
- Require `wslpath` to succeed and return a non-empty absolute path. Display the resolved, quoted arguments under the `[Read-only] Repository fingerprint` label before invoking the helper.
- When Git reports continuing index-refresh progress for a large repository under `/mnt/c`, keep waiting. Do not treat slow Windows-to-WSL filesystem synchronization as a helper portability failure or terminate a progressing command.
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
