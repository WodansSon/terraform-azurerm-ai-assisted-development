# Terraform AzureRM AI Toolkit Plugin

This plugin packages the Terraform AzureRM AI Toolkit review experience for Agency Playground and GitHub Copilot CLI. It gives you portable `review-local`, `review-committed`, and `review-docs` agents for auditing `terraform-provider-azurerm` changes with the same standards, contracts, and workflow guidance used by the VS Code toolkit.

It is built from the shared instructions and skills in the [WodansSon/terraform-azurerm-ai-assisted-development](https://github.com/WodansSon/terraform-azurerm-ai-assisted-development) repository, so the plugin stays aligned with the core Terraform AzureRM AI Toolkit while remaining optimized for Agency and CLI usage, including target-repo preflight checks, PR-aware review entrypoints, and portable review workflows.

## IMPORTANT: Target Repo Prerequisite

**This plugin is installed through Agency. Before running `review-local`, `review-committed`, or `review-docs` against a target repository, install the Terraform AzureRM AI Toolkit into that target repo first.**

### Install The Toolkit Into The Target Repo

The steps below install the Terraform AzureRM AI Toolkit files into the `terraform-provider-azurerm` repository you want to review. They do not install the Agency plugin itself.

You can either install the latest toolkit release using stable URLs or pin a specific version by replacing `latest/download` with `download/vX.Y.Z`.

**Option A (recommended): install the latest toolkit release**

**Windows (PowerShell):**

```powershell
# Download and extract installer to your user profile
Invoke-WebRequest -Uri "https://github.com/WodansSon/terraform-azurerm-ai-assisted-development/releases/latest/download/terraform-azurerm-ai-installer.zip" -OutFile "$env:TEMP\terraform-azurerm-ai-installer.zip"
Expand-Archive -Path "$env:TEMP\terraform-azurerm-ai-installer.zip" -DestinationPath "$env:USERPROFILE" -Force

# Run installer pointing to your terraform-provider-azurerm repository
& "$env:USERPROFILE\.terraform-azurerm-ai-installer\install-copilot-setup.ps1" -RepoDirectory "C:\path\to\terraform-provider-azurerm"
```

**macOS/Linux (Bash):**

```bash
# Download and extract installer to your user profile
curl -L -o /tmp/terraform-azurerm-ai-installer.tar.gz "https://github.com/WodansSon/terraform-azurerm-ai-assisted-development/releases/latest/download/terraform-azurerm-ai-installer.tar.gz"
mkdir -p ~/.terraform-azurerm-ai-installer
tar -xzf /tmp/terraform-azurerm-ai-installer.tar.gz -C ~/.terraform-azurerm-ai-installer --strip-components=1

# Run installer pointing to your terraform-provider-azurerm repository
~/.terraform-azurerm-ai-installer/install-copilot-setup.sh -repo-directory "/path/to/terraform-provider-azurerm"
```

**This plugin is a workflow adapter, not a target-repo bootstrapper. The review agents fail fast if the required toolkit files are missing, and they do not side-load, copy, or write installer payload files into the target repo during a review run.**

## Included Agents

- `review-local` reviews uncommitted local changes in a target `terraform-provider-azurerm` repository.
- `review-committed` reviews committed or PR-scoped changes in a target `terraform-provider-azurerm` repository.
- `review-docs` reviews Terraform AzureRM documentation pages in a target repository.

## Run The Review Agents

Before running `review-local`, `review-committed`, or `review-docs`:

- change directory into the target repo workspace and start `copilot` from that repo root
- type `/agent` and select the review agent you want to run
- provide `repo_path` explicitly so the agent resolves target-repo preflight validation and review scope against the intended repository
- for `review-committed`, provide `pr_repo` when the local clone is a fork and the PR belongs to an upstream repository
- for `review-committed`, provide `pr_number` when you want to pin the review to a specific PR explicitly

### Example committed-review input:

```text
repo_path: <local clone path of the repo being reviewed>
Review the committed changes.
```

### Example committed-review input with an explicit PR target:

```text
repo_path: <local clone path of the repo being reviewed>
pr_repo: <authoritative github repo for the pr, for example hashicorp/terraform-provider-azurerm>
pr_number: <current_pr_number>
Review the committed changes.
```

`repo_path` is still required even when you launch Copilot CLI from the target repo root. The agent uses it as the explicit repository root for target-repo preflight validation and committed-review scope resolution.

### Example local-review input:

```text
repo_path: <local clone path of the repo being reviewed>
diff_scope: worktree
Review the current local changes.
```

### Example docs-review input:

```text
repo_path: <local clone path of the repo being reviewed>
docs_path: website/docs/<path-to-doc>.html.markdown
Review this docs page.
```
