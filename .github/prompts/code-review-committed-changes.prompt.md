---
description: "Code review for committed changes using the shared review contract and a dedicated azurerm-linter section."
---

# 📋 Code Review - Committed Changes

This prompt is the VS Code entrypoint for the shared committed-review workflow.

## Mandatory shared workflow load

- Read and apply `.github/instructions/code-review-committed-workflow.instructions.md` to EOF.
- EOF marker verification is mandatory: the last non-empty line must be `<!-- REVIEW-COMMITTED-WORKFLOW-EOF -->`.
- If the workflow is not fully loaded, hard-stop and output exactly this one line and nothing else:
  - `Cannot run code-review-committed-changes: committed review workflow not fully loaded. Load .github/instructions/code-review-committed-workflow.instructions.md to EOF and re-run this prompt.`

## Prompt-specific recursion prevention

- If the committed change-set includes `.github/prompts/code-review-committed-changes.prompt.md`, skip only that file and disclose the skip in the review output.

## Prompt-specific instruction

- Follow `.github/instructions/code-review-committed-workflow.instructions.md` exactly for execution guardrails, mandatory procedure, and output structure.
- Treat `.github/prompts/code-review-committed-changes.prompt.md` as the active committed-review entrypoint file for the shared workflow's recursion-prevention section.
- For PR-scoped review in the prompt path, prefer GitHub-native pull request tools or environment PR metadata over raw HTTP or raw diff-fetch approaches whenever they are available.
- Do not emit user-facing status narration about switching PR-scope sources or fetching PR metadata; perform those steps silently and emit only the final review body or an explicit hard-stop when required.
- Do not ask to run ad hoc shell or PowerShell probes just to inspect external PR payload structure, enumerate top-level fields, or derive bookkeeping counts when authoritative PR metadata already exists.
