# Contributing To The Terraform AzureRM AI Toolkit Plugin

This guide is for contributors maintaining the plugin source in [WodansSon/terraform-azurerm-ai-assisted-development](https://github.com/WodansSon/terraform-azurerm-ai-assisted-development).

Unlike [plugins/terraform-azurerm-ai-toolkit/README.md](https://github.com/WodansSon/terraform-azurerm-ai-assisted-development/blob/main/plugins/terraform-azurerm-ai-toolkit/README.md), this file is repo-only guidance. The export flow bundles the plugin README, not this contributor guide, so maintainer-only details belong here.

## What Ships

The staged plugin export copies these inputs from [plugins/terraform-azurerm-ai-toolkit](https://github.com/WodansSon/terraform-azurerm-ai-assisted-development/tree/main/plugins/terraform-azurerm-ai-toolkit):

- `.claude-plugin/`
- `agency.json`
- `README.md`
- `agents/`
- `tools/resolve-committed-review-scope.ps1`
- `tools/validate-target-repo-preflight.ps1`

Keep [plugins/terraform-azurerm-ai-toolkit/README.md](https://github.com/WodansSon/terraform-azurerm-ai-assisted-development/blob/main/plugins/terraform-azurerm-ai-toolkit/README.md) focused on released plugin behavior for Agency and GitHub Copilot CLI users.

## Shared Source Of Truth

The shipped plugin runtime should continue to consume shared guidance from:

- `.github/instructions/`
- `.github/skills/`

For CLI target-repo preflight, the plugin should derive its validation surface from `installer/file-manifest.config` as the single authored source of truth, using a CLI-specific filter rather than a second hand-maintained manifest.

Do not fork provider rules into the plugin directory unless a generated export flow requires copied files.

## Repo-Only Maintainer Inputs

These sources support contributor validation and maintenance workflows, but they are not part of the shipped plugin runtime:

- `tools/regression/`
- `tools/validate-ai-toolkit.ps1`

Use these for regression coverage, bundle validation, and repo-side quality checks rather than as plugin payload inputs.

## Local Copilot CLI Validation

You can validate the plugin locally with GitHub Copilot CLI without publishing it to Agency first.

Recommended flow:

- run the one-command contributor helper:
  - `pwsh -NoProfile -File ./tools/playground-plugin/test-staged-plugin.ps1`
- or launch a fresh Copilot CLI session automatically after reinstalling the staged plugin:
  - `pwsh -NoProfile -File ./tools/playground-plugin/test-staged-plugin.ps1 -StartCli`
- verify the installed plugin agents appear in `/agent`
- run at least one real review through the installed CLI plugin

This helper is the preferred contributor validation path because it exports the staged plugin, uninstalls any existing copy, refreshes the local marketplace registration, and reinstalls the staged package using the same marketplace-style install flow contributors are trying to validate.

## Repository Helpers

- `tools/playground-plugin/validate-plugin.ps1`
- `tools/playground-plugin/export-plugin.ps1`
- `tools/playground-plugin/test-staged-plugin.ps1`

These are repository-side helpers for validating and synchronizing the plugin-facing adapter surface. They are not part of the shipped plugin payload unless explicitly exported.

### Staged Plugin Install Validation

If you want a plugin-install validation path that is closer to how a published package will behave, create a clean staged plugin tree first and install from that staged output instead of from the live working copy.

Recommended flow from the repository root:

- stage a clean standalone plugin tree:
  - `pwsh -NoProfile -File ./tools/playground-plugin/export-plugin.ps1 -Clean`
- optionally also create a zip for inspection:
  - `pwsh -NoProfile -File ./tools/playground-plugin/export-plugin.ps1 -Clean -Zip`
- install the staged plugin into Copilot CLI:
  - `copilot plugin install ./plugins/terraform-azurerm-ai-toolkit/export/staged/terraform-azurerm-ai-toolkit`

This staged install is closer to a marketplace-style plugin install because the installed source is a clean exported plugin tree rather than the actively edited working directory.

### Local Marketplace Install Validation

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

### One-Command Contributor Validation Helper

If you intend to publish or update this plugin in the Agency Playground repository, run this helper first before opening or updating the Playground-side PR.

What it does automatically:

- exports the clean staged plugin and marketplace root
- checks whether `terraform-azurerm-ai-toolkit` is already installed and uninstalls it if present
- checks whether `terraform-azurerm-ai-toolkit-local` is already registered and removes it if present
- re-adds the local marketplace root
- reinstalls the staged plugin using `terraform-azurerm-ai-toolkit@terraform-azurerm-ai-toolkit-local`

Optional:

- add `-StartCli` if you want the helper to launch a fresh `copilot` session after reinstalling the plugin for a quick `/agent` verification
- do not use the `-StartCli` session for target-repo review validation; for actual review validation, exit and launch `copilot` from the target repo root

Recommended pre-publication check:

- run `pwsh -NoProfile -File ./tools/playground-plugin/test-staged-plugin.ps1`
- change directory into the target repo workspace and start `copilot` from that repo root
- verify the installed plugin agents appear in `/agent`
- run at least one real review through the installed CLI plugin before pushing plugin changes to the Agency Playground repository

### Example Staged Release Smoke Test

From the toolkit repository root, stage and reinstall the local marketplace copy of the plugin:

```powershell
pwsh -NoProfile -File .\tools\playground-plugin\test-staged-plugin.ps1
```

Then change directory into the target provider repository workspace and start Copilot CLI from that repo root:

```powershell
Set-Location C:\path\to\terraform-provider-azurerm
copilot
```

Inside the Copilot CLI session, verify the installed agents:

```text
/agent
```

Select `review-committed`, then provide this minimal input:

```text
repo_path: C:\path\to\terraform-provider-azurerm
Review the committed changes.
```

If you are validating against a PR in an upstream repository from a forked clone, provide the PR target explicitly:

```text
repo_path: C:\path\to\terraform-provider-azurerm
pr_repo: hashicorp/terraform-provider-azurerm
pr_number: <current_pr_number>
Review the committed changes.
```

## Maintainer-Only Debugging

The `debug_scope` input is maintainer-only and should not be documented in the shipped plugin README.

Use it when the CLI committed review and the VS Code prompt appear to be reviewing different change-sets. The committed-review agent should emit only the normalized live scope summary so you can compare the target repo root, authoritative PR repo, PR number, changed-file count, vendored-file count, and changed-file list before trusting the review output.

Example committed-review debug input:

```text
repo_path: <local clone path of the repo being reviewed>
debug_scope: true
Summarize the normalized committed-review scope and stop.
```

## Release Preparation

The checked-in plugin manifest is development-oriented.

- `.claude-plugin/plugin.json` keeps a local development version (`0.0.0-dev`)
- release automation stamps the plugin manifest version from the release tag
- release automation stamps `author.name` and `author.email` from repository release metadata variables

The released plugin metadata should match the version of the VS Code bundle released from the same tag.
