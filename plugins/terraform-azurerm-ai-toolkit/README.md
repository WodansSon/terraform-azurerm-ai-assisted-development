# Terraform AzureRM AI Toolkit Plugin

This directory is the first-pass Playground plugin and CLI adapter scaffold for this repository.

It is intentionally thin. The authoritative provider standards and workflow guidance remain in the shared source files under `.github/instructions/` and `.github/skills/`.

## Purpose

- package a Playground-compatible plugin shape beside the existing VS Code installer workflow
- keep review workflows portable by expressing them as agents instead of prompt-only entrypoints
- let the plugin frontend inherit updates from the shared contracts and skills in this repository

## Current Scope

This scaffold currently includes:

- plugin metadata in `.claude-plugin/plugin.json`
- engine and category targeting in `agency.json`
- translated local, committed, and docs review agents under `agents/`
- a CLI committed-review scope normalizer under `tools/resolve-committed-review-scope.ps1`
- a manifest-driven target-repo preflight helper under `tools/validate-target-repo-preflight.ps1`
- a local validation helper under `tools/playground-plugin/`

This scaffold does not yet include:

- Playground-specific signing or integrity manifests
- runtime MCP configuration

## Release Stamping

The checked-in plugin manifest is development-oriented.

- `.claude-plugin/plugin.json` keeps a local development version (`0.0.0-dev`)
- release automation stamps the plugin manifest version from the release tag
- release automation stamps `author.name` and `author.email` from repository release metadata variables

The released plugin metadata should match the version of the VS Code bundle released from the same tag.

## Shared Source Of Truth

The plugin should continue to consume shared guidance from:

- `.github/instructions/`
- `.github/skills/`
- `tools/regression/`

For CLI target-repo preflight, the plugin should derive its validation surface from `installer/file-manifest.config` as the single authored source of truth, using a CLI-specific filter rather than a second hand-maintained manifest.

Do not fork provider rules into this plugin directory unless a generated export flow requires copied files.

## Initial Agents

- `agents/review-local.agent.md`
- `agents/review-committed.agent.md`
- `agents/review-docs.agent.md`

- `review-local.agent.md` is the first translated agent workflow for the plugin and CLI frontend.
- `review-committed.agent.md` and `review-docs.agent.md` are now translated review workflow adapters for the plugin and CLI frontend.

## Local Copilot CLI Smoke Test

You can smoke test this plugin locally with GitHub Copilot CLI without publishing it to Playground first.

Recommended flow:

- validate the plugin scaffold:
	- `pwsh -NoProfile -File ./tools/playground-plugin/validate-plugin.ps1`
- start a Copilot CLI session with the local plugin directory loaded:
	- `copilot --plugin-dir .\plugins\terraform-azurerm-ai-toolkit`
- verify the agent is available from inside the session:
	- `/agent`

You can also install the local plugin into Copilot CLI for repeated testing:

- `copilot plugin install .\plugins\terraform-azurerm-ai-toolkit`
- `copilot plugin list`

After local install, verify the agent is available in a new session with `/agent` before running it.

## Local Helpers

- `tools/playground-plugin/validate-plugin.ps1`
- `tools/playground-plugin/export-plugin.ps1`
- `tools/playground-plugin/test-staged-plugin.ps1`

These are repository-side helpers for validating and eventually synchronizing the plugin-facing adapter surface. They are repo-only tooling and are not part of the installed VS Code runtime payload.

### Staged Plugin Install Test

If you want a plugin-install test that is closer to how a published package will behave, create a clean staged plugin tree first and install from that staged output instead of from the live working copy.

Recommended flow from the repository root:

- stage a clean standalone plugin tree:
	- `pwsh -NoProfile -File ./tools/playground-plugin/export-plugin.ps1 -Clean`
- optionally also create a zip for inspection:
	- `pwsh -NoProfile -File ./tools/playground-plugin/export-plugin.ps1 -Clean -Zip`
- install the staged plugin into Copilot CLI:
	- `copilot plugin install ./plugins/terraform-azurerm-ai-toolkit/export/staged/terraform-azurerm-ai-toolkit`

This staged install is closer to a marketplace-style plugin install because the installed source is a clean exported plugin tree rather than the actively edited working directory.

### Local Marketplace Install Test

If you want a future-safe install path that more closely mirrors marketplace consumption, use the staged export as a local marketplace root and install with `plugin@marketplace` syntax.

Recommended flow from the repository root:

- stage the clean plugin and local marketplace manifest:
	- `pwsh -NoProfile -File ./tools/playground-plugin/export-plugin.ps1 -Clean`
- register the local marketplace root:
	- `copilot plugin marketplace add ./plugins/terraform-azurerm-ai-toolkit/export/staged`
- install using marketplace syntax:
	- `copilot plugin install terraform-azurerm-ai-toolkit@terraform-azurerm-ai-toolkit-local`

Why this is preferable:

- it follows the CLI direction toward marketplace installs instead of deprecated direct local installs
- it still uses a clean exported plugin tree rather than the live working copy
- it more closely mirrors the eventual Agency marketplace consumption path without requiring a public release

### One-Command Contributor Smoke Test

If you do not want to remember the staged export, uninstall, marketplace refresh, and reinstall sequence, use the one-command helper:

- `pwsh -NoProfile -File ./tools/playground-plugin/test-staged-plugin.ps1`

If you intend to publish or update this plugin in the Agency Playground repository, run this helper first and smoke test the installed CLI plugin before opening or updating the Playground-side PR.

What it does automatically:

- exports the clean staged plugin and marketplace root
- checks whether `terraform-azurerm-ai-toolkit` is already installed and uninstalls it if present
- checks whether `terraform-azurerm-ai-toolkit-local` is already registered and removes it if present
- re-adds the local marketplace root
- reinstalls the staged plugin using `terraform-azurerm-ai-toolkit@terraform-azurerm-ai-toolkit-local`

Optional:

- add `-StartCli` if you want the helper to launch a fresh `copilot` session after reinstalling the plugin

Recommended pre-publication check:

- run `pwsh -NoProfile -File ./tools/playground-plugin/test-staged-plugin.ps1 -StartCli`
- verify the installed plugin agents appear in `/agent`
- run at least one real review smoke test through the installed CLI plugin before pushing plugin changes to the Agency Playground repository

Recommended installed-plugin smoke test shape:

- if you are validating against a target provider repository, start `copilot` from that target repo root when practical
- for native CLI instruction loading, ensure the target repo already contains the toolkit-installed `.github/copilot-instructions.md` and `.github/instructions/**/*.instructions.md` files, or an equivalent local instruction-dir configuration
- the CLI review agents now fail fast if those required target-repo instruction files are missing; they do not side-load or write installer payload files into the target repo during a review run
- when invoking `review-local` or `review-committed`, always include `repo_path` explicitly so the agent resolves scope against the intended target repository
- when the local clone is a fork but the PR belongs to an upstream repo, include `pr_repo: <owner/repo>` explicitly so the CLI resolves PR scope against the correct GitHub repository
- avoid hard-coding a long-lived PR number in contributor docs; use the current PR you are validating, or use `review-local` against a known local diff
- if `review-committed` with an explicit `pr_number` cannot prove it is using that PR's authoritative GitHub changed-file set, treat that run as failed and do not trust fallback review output
- the CLI `review-committed` adapter does not support branch fallback or `revision_range`; use `review-local` for branch/worktree audits and use `review-committed` only for authoritative PR-scoped review
- if the CLI tries to reopen `%LOCALAPPDATA%\Temp\*copilot-tool-output*.txt` or similar temp files to extract PR changed files, treat that run as failed; the changed-file list must come directly from the authoritative GitHub PR result
- if the CLI asks to read user-profile caches, `workspaceStorage`, or other out-of-workspace local state to infer PR scope, deny that path and treat the run as failed rather than allowing ambiguous fallback context

The normal committed-review prompt can usually be just:

```text
repo_path: <local clone path of the repo being reviewed>
Review the committed changes.
```

If live PR context is ambiguous, pin the target explicitly:

```text
repo_path: <local clone path of the repo being reviewed>
pr_repo: <authoritative github repo for the pr, for example hashicorp/terraform-provider-azurerm>
pr_number: <current_pr_number>
Review the committed changes.
```

That means the normal user flow is:

1. Open Copilot CLI from the target repo when practical.
2. Choose `review-committed`.
3. Paste `repo_path` and, when needed, explicit `pr_repo` and `pr_number`.

Example committed-review smoke test input:

```text
repo_path: <local clone path of the repo being reviewed>
Review the committed changes.
```

Example committed-review scope debug input:

```text
repo_path: <local clone path of the repo being reviewed>
debug_scope: true
Summarize the normalized committed-review scope and stop.
```

Use `debug_scope: true` when the CLI review and the VS Code prompt appear to be reviewing different change-sets. The CLI agent should emit only the normalized live scope summary so you can compare the target repo root, authoritative PR repo, PR number, changed-file count, vendored-file count, and changed-file list before trusting the review output.

Optional explicit form when you want to pin every field:

```text
repo_path: <local clone path of the repo being reviewed>
pr_repo: <authoritative github repo for the pr, for example hashicorp/terraform-provider-azurerm>
pr_number: <current_pr_number>
Review the committed changes.
```

Example local-review smoke test input:

```text
repo_path: <local clone path of the repo being reviewed>
diff_scope: worktree
Review the current local changes.
```

## Native CLI Instructions

GitHub Copilot CLI now supports repository-wide and path-specific instruction files natively.

This plugin no longer ships a custom instruction-catalog or parity-resolver layer for `.github/copilot-instructions.md` and `.github/instructions/**/*.instructions.md`.

The intended model is:

- run Copilot CLI from the target repository when practical
- let Copilot CLI load the target repo's `.github/copilot-instructions.md`, `.github/instructions/**/*.instructions.md`, and `AGENTS.md` files natively
- keep this plugin focused on workflow entrypoints and live CLI PR-scope resolution
