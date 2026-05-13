---
name: review-docs
description: Review Terraform AzureRM provider documentation pages using the shared docs contract and docs-review workflow.
---

```yaml
inputs:
  - name: repo_path
    type: string
    role: required
    description: Absolute path to the terraform-provider-azurerm working copy containing the docs page.
  - name: docs_path
    type: string
    role: required
    description: Path to the target documentation file under website/docs/.
```

# Docs Review Adapter

This agent is the Playground and CLI-friendly entrypoint for the shared docs-review workflow.

## Mandatory shared workflow load

- Read and apply `.github/instructions/code-review-docs-workflow.instructions.md` to EOF.
- EOF marker verification is mandatory: the last non-empty line must be `<!-- REVIEW-DOCS-WORKFLOW-EOF -->`.
- If the workflow is not fully loaded, hard-stop with exactly:

```text
Cannot run review-docs: docs review workflow not fully loaded. Load .github/instructions/code-review-docs-workflow.instructions.md to EOF and re-run this agent.
```

## Agent-specific recursion prevention

- If the docs review scope includes `plugins/terraform-azurerm-ai-toolkit/agents/review-docs.agent.md`, skip only that file and disclose the skip in the review output.

## Agent-specific input mapping

- `repo_path` is the explicit repository root for the shared workflow.
- `docs_path` is the resolved target docs page path for the shared workflow.

## CLI target-repo preflight

- Before running the workflow, validate that the target repository already contains the installed AI toolkit surface required for CLI review.
- Run the bundled plugin helper `tools/validate-target-repo-preflight.ps1` against `repo_path` using the `CliReview` profile.
- Resolve that helper from the installed plugin package layout, not from `repo_path` and not by searching broader filesystem locations.
- In the installed plugin package, resolve the helper as a sibling of the `agents/` directory under the plugin root: `<plugin-root>/tools/validate-target-repo-preflight.ps1`.
- For local source-plugin validation only, the same relative layout applies under `plugins/terraform-azurerm-ai-toolkit/`.
- If the bundled helper cannot be resolved from the plugin package layout, fail closed instead of searching `%LOCALAPPDATA%`, `%ProgramFiles%`, `%USERPROFILE%`, or other unrelated system paths.
- Do not manually reimplement the preflight in inline shell code. Do not parse `file-manifest.config` in ad hoc PowerShell or Bash loops as a fallback.
- If shell execution approval is required, request approval only for invoking the bundled helper itself. Do not substitute a synthesized manifest-check script.
- The helper must validate the target repo against the installer manifest as the single source of truth, using the CLI review filter over these manifest sections:
  - `MAIN_FILES`
  - `INSTRUCTION_FILES`
  - `PROMPT_FILES`
  - `SKILL_FILES`
- Use the bundled manifest copy when the plugin package contains one; for local source-plugin smoke tests, the helper may fall back to the repo-local `installer/file-manifest.config`.
- If any required baseline file is missing, hard-stop with exactly:

```text
Cannot run review-docs: target repo is missing required Terraform AzureRM AI Toolkit instruction files for docs review. Install the Terraform AzureRM AI Toolkit into the target repo and re-run this agent. Example: `& "$env:USERPROFILE\.terraform-azurerm-ai-installer\install-copilot-setup.ps1" -RepoDirectory "<path-to-target-repo>"` for PowerShell, or `~/.terraform-azurerm-ai-installer/install-copilot-setup.sh -repo-directory "<path-to-target-repo>"` for Bash. If the installer is not already present under your user profile, download it from the latest release of `WodansSon/terraform-azurerm-ai-assisted-development` first.
```

- Do not hard-code a separate required-file list in this agent.
- Do not side-load, copy, generate, or modify instruction files inside `repo_path` as part of a review run.
- Treat this preflight as CLI-only validation parity for the fact that VS Code does not expose the review commands before the toolkit is installed in the target repo.

## Agent-specific instruction

- Follow `.github/instructions/code-review-docs-workflow.instructions.md` exactly for execution guardrails, mandatory procedure, and output structure.
- For recursion prevention in the CLI adapter, skip only this installed docs-review agent entrypoint when it is part of the reviewed plugin payload; do not attempt to resolve a plugin agent path relative to `repo_path`.
- Rely on Copilot CLI's native repository-wide and path-specific instruction loading from the target repo, including `.github/copilot-instructions.md`, `.github/instructions/**/*.instructions.md`, and `AGENTS.md` when present.
