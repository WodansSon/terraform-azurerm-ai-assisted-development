# Sanitized Fixture: PR Description Base And Evidence Matrix

This fixture is synthetic and sanitized. It models separate invocations of `draft-pr-description`.

## Pull Request Identity And Local Relation

- An open pull request has the same head repository and branch as the checkout. Separate runs model equal, locally ahead, locally behind, diverged, and unknown relations to its remote head.
- A merged pull request uses a different branch name but its final head commit equals local `HEAD`.
- A merged pull request contains local `HEAD` as an intermediate commit but accumulated later changes before merge.
- A prior pull request has similar paths and title but no verified identity or formally proven scope equivalence.

Only the active branch identity can select the pull request base. Exact final-head metadata can supply authoritative prior body evidence, while intermediate commit association and unproven scope similarity remain advisory.

## Existing Pull Request Base Plus Local Changes

Authoritative metadata provides a base commit. The branch also has an unstaged edit and a non-ignored untracked test file. The merge-base-to-working-tree scope includes both local changes as well as branch commits.

The prompt loads the template and contributor guidance from the selected base commit. It uses the common ancestor only to collect the candidate change-set.

## Execution-Boundary Discovery

- A suitable current terminal worktree resolves Git and Go, validates AzureRM repository identity and the expected checked-out branch, and is selected directly across native, WSL, container, Codespaces, SSH, and remote environments.
- An unsuitable current environment triggers a search of explicit configurable roots and existing `~/src`, `~/github`, `~/go/src`, and `/workspaces` roots only. Each candidate is validated through Git, remotes, AzureRM structure, expected branch, full `HEAD`, dirty state, and helper capability.
- One run has a dirty source checkout and a clean clone with the same branch and `HEAD`. The clean clone is not equivalent and cannot replace the source changes.
- One run has two trustworthy candidates. The workflow lists both environments, canonical roots, branches, full `HEAD` values, and dirty-state summaries and asks the developer to select one.
- One run has no trustworthy candidates. The workflow requests an explicit repository path and reports the failed capability or identity checks without scanning more broadly.
- Native Windows uses native Git and Go when suitable. A separate run lacks native helper capability, discovers an explicitly selected WSL distribution, validates Git and Go there, searches bounded WSL roots for a native checkout, and considers path translation only as a fallback for intentionally using the same mounted Windows worktree.
- Once selected, one canonical worktree and execution environment own repository inspection, initial and final fingerprints, pull request and base evidence, change collection, and payload generation.

## Repository State Stability

The initial fingerprint covers `HEAD`, staged tracked content, unstaged tracked content, and ordinal untracked path and byte-content hashes. Separate runs mutate each working-tree component while keeping `HEAD` unchanged.

Fingerprint collection invokes the checked-in `.github/skills/pr-description/scripts/pr-description-fingerprint.go` helper inside the frozen execution boundary. Native, WSL, container, Codespaces, SSH, and remote terminals use direct `go run` when Git and Go resolve there. Optional mounted-worktree translation inspects an explicitly selected WSL distribution and does not treat one non-interactive PATH miss as proof that Go is absent.

The helper resolves Git's absolute top-level worktree before hashing. An invocation from an interior directory produces the same fingerprint as the repository root and still detects root-level untracked files.

The mounted-worktree fallback passes the distro, Windows repository path, and translated WSL path as separate quoted PowerShell arguments. Repository paths are not interpolated into the fixed Bash helper command, including when a path contains spaces.

A large repository under `/mnt/c` can spend substantial time refreshing the Git index while Windows-to-WSL filesystem synchronization is active. Continuing progress means the command remains active and is not terminated or classified as a helper portability failure.

Initial and final fingerprints use the same frozen worktree and execution environment. The workflow does not compare digests produced by different checkouts, Git executables, or configurations.

The workflow does not generate PowerShell, Bash, or other inline fingerprint programs. The helper may update Go's build cache outside the repository but does not modify repository refs, the index, or working files.

The first mismatch discards all evidence and restarts once. A stable restarted run records matching fingerprints and `restartCount=1`. A second mismatch emits `Cannot run draft-pr-description: repository state changed repeatedly during evidence collection. Stop concurrent edits and re-run this prompt.` and does not render a draft.

## Targeted Base Refresh

Remote base refresh uses `--no-tags`, `--no-recurse-submodules`, `--no-write-fetch-head`, and an explicit `refs/heads/{{BASE_BRANCH}}:refs/remotes/{{REMOTE}}/{{BASE_BRANCH}}` refspec. It does not update `FETCH_HEAD`.

Every terminal batch displays its exact command under `[Read-only] {{PURPOSE}}` or `[Updates remote-tracking ref: {{FULL_REMOTE_TRACKING_REF}} only]`. The targeted fetch is never combined with inspection commands.

## Conditional Base Policy

Every run loads the pull request template, contributor index, opening guide, and changelog guide. New-resource, Resource Identity, and List Resource guides load only when classified paths make those policy areas applicable.

## Missing Base Authority

The selected base revision lacks `.github/pull_request_template.md` in one run. In another run that introduces a new Resource, it lacks `contributing/topics/guide-resource-identity.md`. Each run stops and names the applicable missing path exactly. An existing-surface-only run does not require the Resource Identity guide.

## Unrelated Service Packages

The branch changes primary managed Resources in two distinct synthetic service packages. The fixture paths use the corpus-approved example namespace, while the supplied classification evidence keeps the package identities distinct. Neither change is a companion of the other. Drafting stops before title selection.

## Validation Evidence

- One run observes a named current-run unit test complete successfully.
- One run observes an acceptance command exit successfully after all tests skip because required Azure environment variables are absent.
- One run has no validation output.
- One run has an older existing pull request claim that does not cover the current diff.

Only the first run checks applicable local validation. The remaining runs keep the checklist conservative and add concise evidence gaps.
