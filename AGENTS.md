# Maintainer Workspace Guardrails

This file is maintainer-only workspace guidance for this repository.

It must not be added to `installer/file-manifest.config` unless maintainers intentionally decide to ship it.

## Purpose

Use these rules during ad hoc chat, diagnosis, and design discussion in this repository.

These rules govern maintainer collaboration behavior before any formal review workflow or code edit begins.

## Ad Hoc Triage Rules

- Treat surfaced PR, resource, or service issues as evidence, not as the target fix, unless the user explicitly asks for a one-off fix.
- Assume the first question is whether the problem is system-wide, flow-specific, or truly one-off.
- Treat `vscode-file://...AppData...workbench.html` links in pasted Copilot review output as a likely runtime/editor link-rewrite artifact first, not as automatic proof that the workflow payload itself emitted forbidden local paths.
- Before proposing workflow-contract or prompt fixes for pasted editor-local links, distinguish between runtime-rendered link rewriting and actual payload/body path generation defects.
- When evaluating generated PR-description output during live testing, assess factual support, surface and lifecycle attribution, scope completeness, and HashiCorp template and changelog compliance. Do not turn that evaluation into an independent code review, adjudicate implementation correctness, or reconstruct historical behavior beyond what is necessary to identify unsupported or misattributed draft claims.
- Do not convert diagnosis or wording discussion into code edits unless the user explicitly asks to make the change.
- Ask clarification and approval questions through natural conversational dialogue. Do not use multiple-choice questions or question widgets.
- Treat a terminal with an active command as exclusively owned by that execution until it completes. Never issue another command into the same terminal; use a separate terminal for concurrent diagnostics.
- Before proposing or making an edit, restate the shared invariant or architectural behavior that is actually being fixed.
- Prefer fixes that generalize across all applicable reviews, prompts, contracts, or skills instead of fixes that only help the surfaced example.
- If a proposed fix only helps the current PR, resource, service, or example, stop and call out that it is likely drift.
- Do not introduce real resource or service names into shared policy or shared prompt wording unless the behavior truly depends on that concrete example.
- Prefer removing duplicated meaning over adding more wording when the same behavior already has an authoritative owner.

## Ownership Discipline

- Repo-wide ad hoc collaboration behavior belongs in this file.
- Formal review workflow behavior belongs in the shared review contracts, prompts, and skills.
- Shipped runtime guidance belongs only in files intentionally included by `installer/file-manifest.config`.
- Repo-only maintainer workflow guidance must stay outside the shipped payload by default.

## Release Validation Safety

- Treat this repository as source-only during release validation.
- Never run `installer/install-copilot-setup.ps1 -Bootstrap` or `installer/install-copilot-setup.sh -bootstrap` as a release check. Bootstrap overwrites the persistent user-profile installer and belongs only to an explicitly requested contributor workflow.
- Stage release dry-run output in an external temporary directory, never inside this repository or the persistent user-profile installer.
- Use reserved version `0.0.1` for release dry runs and require successful checksum validation from both PowerShell and Bash-capable CI before release preparation.
- Verify the staged installer only through its standalone `-Version` command and require it to report `0.0.1`. Do not pass a repository target or install AI files during the dry run.
- Treat the active source checkout, persistent user-profile installer, and existing provider working copies as protected state. Do not change branches or write to any of them without explicit maintainer approval for that exact operation.

## Edit Gate

Before editing AI-toolkit files for a surfaced issue, identify all of the following:

- whether the issue is system-wide, flow-specific, or one-off
- which file is the authoritative owner of the behavior
- which other files should only consume that behavior rather than redefine it

If those answers are not clear yet, continue diagnosis and do not patch.
