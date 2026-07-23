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

## Repository State Stability

The initial fingerprint covers `HEAD`, staged tracked content, unstaged tracked content, and ordinal untracked path and byte-content hashes. Separate runs mutate each working-tree component while keeping `HEAD` unchanged.

Fingerprint collection invokes the checked-in `.github/skills/pr-description/scripts/pr-description-fingerprint.go` helper. Windows, macOS, Linux, and Remote-WSL runs use direct `go run` when Go resolves in the current environment. A local Windows run without direct Go inspects an explicitly selected WSL distribution's interactive shell, translates the repository root with `wslpath`, and invokes the same helper through `wsl.exe`. A non-interactive PATH miss alone does not prove WSL Go is absent.

Initial and final fingerprints use the same direct or WSL execution environment. The workflow does not compare digests produced by different Git executables or configurations.

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
