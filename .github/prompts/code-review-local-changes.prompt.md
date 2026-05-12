---
description: "Code review for local changes using the shared review contract and local-review workflow."
---

# 📋 Code Review - Local Changes

This prompt is the VS Code entrypoint for the shared local-review workflow.

## Mandatory shared workflow load

- Read and apply `.github/instructions/code-review-local-workflow.instructions.md` to EOF.
- EOF marker verification is mandatory: the last non-empty line must be `<!-- REVIEW-LOCAL-WORKFLOW-EOF -->`.
- If the workflow is not fully loaded, hard-stop and output exactly this one line and nothing else:
  - `Cannot run code-review-local-changes: local review workflow not fully loaded. Load .github/instructions/code-review-local-workflow.instructions.md to EOF and re-run this prompt.`

## Prompt-specific recursion prevention

- If the local change-set includes `.github/prompts/code-review-local-changes.prompt.md`, skip only that file and disclose the skip in the review output.

## Prompt-specific instruction

- Follow `.github/instructions/code-review-local-workflow.instructions.md` exactly for execution guardrails, mandatory procedure, and output structure.
- Treat `.github/prompts/code-review-local-changes.prompt.md` as the active local-review entrypoint file for the shared workflow's recursion-prevention section.
