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
- For iterative UX feedback, prototype suggested layout and interaction changes directly in the live browser DOM first. Positive prototype feedback such as "that looks good" approves only the current browser prototype and means UX iteration may continue. Do not edit source files, restage, or rerun validation until the maintainer explicitly requests implementation with language such as "let's implement that" or "update the code." After that explicit request, implement the accepted design in source and validate once.
- Ask clarification and approval questions through natural conversational dialogue. Do not use multiple-choice questions or question widgets.
- Treat a terminal with an active command as exclusively owned by that execution until it completes. Never issue another command into the same terminal; use a separate terminal for concurrent diagnostics.
- Before proposing or making an edit, restate the shared invariant or architectural behavior that is actually being fixed.
- Prefer fixes that generalize across all applicable reviews, prompts, contracts, or skills instead of fixes that only help the surfaced example.
- If a proposed fix only helps the current PR, resource, service, or example, stop and call out that it is likely drift.
- Do not introduce real resource or service names into shared policy or shared prompt wording unless the behavior truly depends on that concrete example.
- Prefer removing duplicated meaning over adding more wording when the same behavior already has an authoritative owner.
- Start prose in every Markdown bullet with a capital letter. If a bullet begins with inline code or another Markdown marker, preserve the literal or marker syntax, but capitalize the first visible prose word when applicable.

## Ownership Discipline

- Repo-wide ad hoc collaboration behavior belongs in this file.
- Formal review workflow behavior belongs in the shared review contracts, prompts, and skills.
- Shipped runtime guidance belongs only in files intentionally included by `installer/file-manifest.config`.
- Repo-only maintainer workflow guidance must stay outside the shipped payload by default.
- Hand-authored Interactive contracts own runtime rule wording and behavior; `tools/interactive-rule-catalog/rule-catalog.json` owns provenance and lifecycle history and must remain outside `installer/file-manifest.config`.

## Toolkit Ownership and Routing

- Use **Interactive Toolkit** for the existing VS Code-oriented runtime, installer, contracts, prompts, skills, and regression harness.
- Use **Hosted Toolkit** for the isolated GitHub Copilot code-review product designed under `hosted_copilot/`.
- Treat both toolkits as independently maintained and validated. The Interactive Toolkit is versioned, packaged, and released; the Hosted Toolkit is deployed directly from this repository into a target fork.
- Treat `docs/HOSTED_COPILOT_CODE_REVIEW_ARCHITECTURE.md` as the authority for the proposed Hosted Toolkit architecture while its runtime remains unimplemented.
- Treat current Hosted Toolkit work as a controlled experiment until the architecture's Experiment MVP acceptance criteria support an explicit adoption decision.
- Do not require deferred production generation, synchronization, regression, CI, or publication machinery merely to run the Hosted experiment.
- Do not run the Interactive Toolkit validator as a substitute for Hosted Toolkit validation on Hosted Toolkit-only changes.
- Use `tools/Validate-ChangedToolkits.ps1` for change-aware validation and use each profile validator directly only for complete validation of its owned toolkit.
- When both toolkits change, run both validators independently, preserve both results, and fail the combined check if either required validator fails.
- Do not let combined validation create a changelog, installer, deployment, or runtime dependency between the toolkits.
- Keep root `CHANGELOG.md` and `installer/VERSION` owned by the Interactive Toolkit; keep the unversioned Hosted Toolkit changelog at `hosted_copilot/CHANGELOG.md`.
- Treat explicitly designated shared configuration and dispatcher files as affecting both toolkits; treat unclassified paths as requiring an ownership decision rather than guessing.

## Interactive Toolkit Release Validation Safety

- Treat this repository as source-only during release validation.
- Never run `installer/install-copilot-setup.ps1 -Bootstrap` or `installer/install-copilot-setup.sh -bootstrap` as a release check. Bootstrap overwrites the persistent user-profile installer and belongs only to an explicitly requested contributor workflow.
- Stage release dry-run output in an external temporary directory, never inside this repository or the persistent user-profile installer.
- Use reserved version `0.0.1` for release dry runs and require successful checksum validation from both PowerShell and Bash-capable CI before release preparation.
- Verify the staged installer only through its standalone `-Version` command and require it to report `0.0.1`. Do not pass a repository target or install AI files during the dry run.
- Treat the active source checkout, persistent user-profile installer, and existing provider working copies as protected state. Do not change branches or write to any of them without explicit maintainer approval for that exact operation.

## Interactive Toolkit Teams Release Announcements

- Build release announcements from the published version's changelog section and verified release URL. Do not invent features or use unreleased notes.
- Write the complete announcement to `docs/teams_release.md`, replacing the previous generated announcement. Use Markdown so the maintainer can copy the rendered preview into Teams.
- Treat `docs/teams_release.md` as local generated output. Ensure `/docs/teams_release.md` is present in this clone's `.git/info/exclude`; do not add the generated file or its exclusion to the shared `.gitignore`.
- Never stage or commit `docs/teams_release.md`.
- Write for toolkit users and AzureRM contributors. Include only user-facing review, documentation, implementation, testing, and skill behavior from the published changelog.
- Exclude maintainer-only workflows, repository validation, regression-harness mechanics, CI behavior, release validation, checksums, provenance, and publication mechanics.
- Open with `**Released:** \`vX.Y.Z\` of the Terraform AzureRM AI-Assisted Development toolkit`.
- Follow the lead with two or three narrative paragraphs that explain the release's primary themes, practical impact, and important secondary theme. Use the explanatory maintainer voice rather than a terse release checklist.
- Add `**Other highlights in** \`vX.Y.Z\`**:**` followed by four to six concise bullets covering distinct supporting changes.
- End with `Release: [https://github.com/WodansSon/terraform-azurerm-ai-assisted-development/releases/tag/vX.Y.Z](https://github.com/WodansSon/terraform-azurerm-ai-assisted-development/releases/tag/vX.Y.Z)`.
- Prefer user and contributor outcomes over internal file, contract, prompt, schema, or workflow implementation details.

## Edit Gate

Before editing AI-toolkit files for a surfaced issue, identify all of the following:

- Whether the issue is system-wide, flow-specific, or one-off
- Which file is the authoritative owner of the behavior
- Which other files should only consume that behavior rather than redefine it

If those answers are not clear yet, continue diagnosis and do not patch.
