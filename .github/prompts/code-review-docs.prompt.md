---
description: "Code review (docs) using the shared docs-review workflow and docs compliance contract."
---

# 📋 Code Review - Docs (AzureRM)

This prompt is the VS Code entrypoint for the shared docs-review workflow.

## Prompt-specific renderer artifact

- Some chat UIs may display a leading `-` before this prompt's content. Treat that as a rendering artifact and do not comment on it. Proceed with the audit.

## Prompt-specific target docs page requirement

- This prompt audits the currently-open documentation page under `website/docs/**`.
- If the active editor is not a file under `website/docs/**`, do not attempt the audit.
- Instead, output exactly this one line and nothing else:
  - `Cannot run code-review-docs: active file is not under website/docs/**. Open the target docs page and re-run this prompt.`

## Mandatory shared workflow load

- Read and apply `.github/instructions/code-review-docs-workflow.instructions.md` to EOF.
- EOF marker verification is mandatory: the last non-empty line must be `<!-- REVIEW-DOCS-WORKFLOW-EOF -->`.
- If the workflow is not fully loaded, hard-stop and output exactly this one line and nothing else:
  - `Cannot run code-review-docs: docs review workflow not fully loaded. Load .github/instructions/code-review-docs-workflow.instructions.md to EOF and re-run this prompt.`

## Prompt-specific recursion prevention

- If the docs review scope includes `.github/prompts/code-review-docs.prompt.md`, skip only that file and disclose the skip in the review output.

## Prompt-specific instruction

- Follow `.github/instructions/code-review-docs-workflow.instructions.md` exactly for execution guardrails, mandatory procedure, and output structure.
- Treat `.github/prompts/code-review-docs.prompt.md` as the active docs-review entrypoint file for the shared workflow's recursion-prevention section.
- Use the currently-open docs page as the resolved target docs path for the shared workflow.
