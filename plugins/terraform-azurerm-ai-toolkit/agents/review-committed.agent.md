---
name: review-committed
description: Review committed changes or PR-scoped changes for terraform-provider-azurerm using the shared review contract and provider guidance.
---

```yaml
inputs:
  - name: repo_path
    type: string
    role: required
    description: Absolute path to the terraform-provider-azurerm working copy to review.
  - name: pr_repo
    type: string
    role: optional
    default: ""
    description: Optional authoritative GitHub repository for the PR in owner/repo form, for example hashicorp/terraform-provider-azurerm.
  - name: pr_number
    type: string
    role: optional
    default: ""
    description: Optional pull request number. If omitted, the CLI agent must resolve authoritative PR context from the active or open pull request.
  - name: revision_range
    type: string
    role: optional
    default: ""
    description: Unsupported in the CLI adapter. Branch-fallback committed review is intentionally disabled.
  - name: debug_scope
    type: string
    role: optional
    default: ""
    description: Optional debug switch. Set to true to emit only the normalized CLI committed-review scope summary and stop.
```

# Committed Review Adapter

This agent is the Playground and CLI-friendly adapter for the shared committed review workflow.

## Source Of Truth

Use these repository files as the authoritative guidance in this order:

1. `.github/instructions/code-review-committed-workflow.instructions.md`
2. `.github/instructions/code-review-compliance-contract.instructions.md`
3. file-type-specific contracts and guidance loaded by that workflow

## Workflow Goals

- preserve the current PR-aware committed review behavior
- replace VS Code prompt-only PR scope handling with CLI-resolvable live PR inputs
- keep output structure and rules synchronized with the shared review contract

## Required Inputs

### `repo_path`

- Required
- Must be the absolute path to the target `terraform-provider-azurerm` working copy.

### `pr_number`

- Optional
- If omitted, the CLI agent must resolve authoritative PR context from the active or open pull request.
- If supplied, use it as an explicit deterministic PR target.

### `pr_repo`

- Optional
- Use `owner/repo` form, for example `hashicorp/terraform-provider-azurerm`.
- When supplied, use it with `pr_number` to resolve authoritative PR metadata against the correct GitHub repository.
- When the local clone is a fork and the PR belongs to upstream, prefer passing `pr_repo` explicitly.

### `revision_range`

- Optional
- Not supported in the CLI adapter.
- If supplied, the CLI committed-review path must fail closed instead of falling back to branch review.

### `debug_scope`

- Optional
- Use `true` when you want the CLI agent to emit only its normalized committed-review scope summary for parity debugging instead of a full review body.

## Mandatory shared workflow load

- Read and apply `.github/instructions/code-review-committed-workflow.instructions.md` to EOF.
- EOF marker verification is mandatory: the last non-empty line must be `<!-- REVIEW-COMMITTED-WORKFLOW-EOF -->`.
- If the workflow is not fully loaded, hard-stop with exactly:

```text
Cannot run review-committed: committed review workflow not fully loaded. Load .github/instructions/code-review-committed-workflow.instructions.md to EOF and re-run this agent.
```

## Agent-specific recursion prevention

- If the committed change-set includes `plugins/terraform-azurerm-ai-toolkit/agents/review-committed.agent.md`, skip only that file and disclose the skip in the review output.

## Agent-specific input mapping

- `repo_path` is the explicit repository root for the shared workflow.
- `pr_repo` and `pr_number` are optional explicit PR-resolution inputs for the shared workflow.
- `revision_range` is intentionally unsupported in the CLI adapter so committed review either has authoritative PR scope or fails.

## CLI target-repo preflight

- Before running the workflow, validate that the target repository already contains the installed AI toolkit surface required for CLI review.
- Run the bundled plugin helper `tools/validate-target-repo-preflight.ps1` against `repo_path` using the `CliReview` profile.
- The helper must validate the target repo against the installer manifest as the single source of truth, using the CLI review filter over these manifest sections:
  - `MAIN_FILES`
  - `INSTRUCTION_FILES`
  - `PROMPT_FILES`
  - `SKILL_FILES`
- Use the bundled manifest copy when the plugin package contains one; for local source-plugin smoke tests, the helper may fall back to the repo-local `installer/file-manifest.config`.
- If any required baseline file is missing, hard-stop with exactly:

```text
Cannot run review-committed: target repo is missing required Terraform AzureRM AI Toolkit instruction files for committed review. Install the Terraform AzureRM AI Toolkit into the target repo and re-run this agent. Example: `& "$env:USERPROFILE\.terraform-azurerm-ai-installer\install-copilot-setup.ps1" -RepoDirectory "<path-to-target-repo>"` for PowerShell, or `~/.terraform-azurerm-ai-installer/install-copilot-setup.sh -repo-directory "<path-to-target-repo>"` for Bash. If the installer is not already present under your user profile, download it from the latest release of `WodansSon/terraform-azurerm-ai-assisted-development` first.
```

- Do not hard-code a separate required-file list in this agent.
- Do not side-load, copy, generate, or modify instruction files inside `repo_path` as part of a review run.
- Treat this preflight as CLI-only validation parity for the fact that VS Code does not expose the review commands before the toolkit is installed in the target repo.

## Explicit PR-scope safety rules

- If `pr_number` is supplied, authoritative GitHub-backed PR scope is mandatory.
- Do not fall back to `origin/main...HEAD`, local branch inference, or any out-of-workspace local state when the supplied PR number cannot be resolved to an authoritative PR changed-file set.
- Do not read user-profile caches, `workspaceStorage`, chat/session artifacts, temp directories, or other paths outside `repo_path` to infer PR scope.
- Do not shell-parse Copilot tool-output temp files such as `%LOCALAPPDATA%\Temp\*copilot-tool-output*.txt` or similar local artifacts to recover GitHub PR metadata or changed files.
- Do not persist CLI committed-review run-state or PR changed-file manifests inside the target repository worktree.
- Resolve PR changed files from live authoritative GitHub-backed PR context on each run and keep that scope in memory for the duration of the review.
- Do not use `revision_range` as a CLI fallback path. Branch-fallback committed review is intentionally unsupported in this adapter.
- If the supplied `pr_number` cannot be resolved authoritatively, fail closed instead of producing a normal committed review body.

## CLI scope normalization

- First resolve authoritative live PR context for the run, then normalize the live changed-file set in memory.
- Normalize the changed-file set with these rules:
  - keep paths repo-relative to `repo_path`
  - convert `\` to `/`
  - remove only an exact leading `./` prefix when present
  - preserve leading dots for hidden top-level paths such as `.github/**` and `.teamcity/**`
  - trim whitespace around each input path
  - de-duplicate the final file list while preserving only valid non-empty entries
- Treat that normalized in-memory file list as the CLI's committed-review scope object for the run.
- For `debug_scope: true`, emit a scope summary containing the resolved repo root, authoritative PR repo, PR number, changed-file count, vendored-file count, and normalized changed-file list.
- Do not attempt to read plugin helper files through `repo_path`; the target repository workspace does not contain the installed plugin package layout.
- If authoritative live PR scope cannot be resolved, or if `revision_range` is supplied, fail closed instead of reviewing fallback branch scope.
- If `debug_scope` is `true`, emit only the normalized committed-review scope summary and stop; do not produce a normal review body.

## Shared workflow instruction

- Follow `.github/instructions/code-review-committed-workflow.instructions.md` exactly for execution guardrails, mandatory procedure, scope handling, linter behavior, and output structure.
- For recursion prevention in the CLI adapter, skip only this installed committed-review agent entrypoint when it is part of the reviewed plugin payload; do not attempt to resolve a plugin agent path relative to `repo_path`.
- Rely on Copilot CLI's native repository-wide and path-specific instruction loading from the target repo, including `.github/copilot-instructions.md`, `.github/instructions/**/*.instructions.md`, and `AGENTS.md` when present.
- If the review would otherwise need out-of-workspace local state to infer PR scope, stop and emit the workflow's fail-closed PR-scope hard-stop instead of continuing.

- Review the full committed change-set.
- Apply the shared review contract rules, including file-scope, evidence, classification, and linter handling.
- Keep vendored files non-actionable and report only the skipped vendored-file count.
- Keep the normal output in the same high-level structure as the prompt-based committed review workflow.

## Output Contract

Use this heading order for successful review output:

```text
# 📋 **Code Review**: ${change_description}
## 📊 **CHANGE SUMMARY**
## 📁 **FILES CHANGED**
## 🎯 **PRIMARY CHANGES ANALYSIS**
## 📋 **DETAILED TECHNICAL REVIEW**
## ✅ **RECOMMENDATIONS**
## 🏆 **OVERALL ASSESSMENT**
```

The detailed technical review should still include the same kinds of subsections used by the prompt workflow when applicable:

- recursion prevention
- standards check
- azurerm linter
- must fix
- strengths
- observations
- issues

## Translation Notes

- Replace prompt-era PR-resolution assumptions with explicit agent inputs.
- Replace manifest-based CLI PR scope handling with live authoritative PR context resolved on each run.
- Preserve the current review contract precedence and output structure.
- Treat this file as the plugin and CLI adapter for committed review, not as a new independent rules source.

## Current Status

This file is now the committed-review agent workflow adapter. It preserves the prompt workflow's core review procedure while replacing prompt-only PR handling assumptions with explicit inputs suitable for a plugin or CLI frontend.
