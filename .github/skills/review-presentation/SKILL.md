
---
name: review-presentation
description: Render frozen code review data into the standard final review template without changing findings, severity, or classification. Use when a code-review workflow has already frozen its findings and needs deterministic final presentation.
---

# Review Presentation (render-only final output)

## Canonical sources of truth (contract-driven)

When running the presentation pass, use `.github/instructions/review-presentation-compliance-contract.instructions.md` as the single source of truth for:

- the output template and section order
- the expanded finding-card format, including priority mapping and review-type emoji mapping
- what the renderer may and may not change
- footer rendering and empty-state rendering
- the `REVIEW-PRESENT-*` rule families

Do not treat this skill as a second independent rule source. The skill describes the method; the contract owns the deterministic rules.
Do not treat this skill as a reviewer, moderator, or adjudicator. It is render-only workflow machinery.

## Mandatory: read the entire skill

Before applying this skill, read this file to EOF.

## Preflight checklist

Before running the presentation pass, complete this checklist:

- [ ] I have read this skill to EOF.
- [ ] I have loaded `.github/instructions/review-presentation-compliance-contract.instructions.md` to EOF and applied the relevant `REVIEW-PRESENT-*` rules.
- [ ] I have explicitly loaded `.github/instructions/review-presentation-input.schema.json` to EOF in the current run and am not inferring schema knowledge from the contract, prompt text, or earlier summaries.
- [ ] The findings set is already frozen and no more review reasoning remains to be done.

If preflight is incomplete, do not run the presentation pass.

## Verification (assistant response only)

This skill does not append its own `Skill used:` line.

Rules:
- Do NOT write any verification marker into repository files.
- Render the footer exactly from the supplied payload metadata.
- Do NOT add `Skill used: review-presentation` to the footer.

## Scope

This skill is the reusable final presentation technique orchestrated inside the generic code-review prompts:

- `.github/prompts/code-review-local-changes.prompt.md`
- `.github/prompts/code-review-committed-changes.prompt.md`

It runs after the findings set is frozen. It does not gather evidence, review code, classify findings, or modify verdicts. It only turns the supplied payload into the final review body.

## Role

You are the **renderer** for the review workflow. Your job is to:

- consume the frozen presentation payload
- render the standard section order and headings
- render contract-defined structured findings, including compact titled issue findings with severity-specific inline issue emojis, compact titled observation findings with the inline observation marker, emoji-prefixed `Impact`/`Evidence`/`Suggested Change` field labels, and expanded positive-feedback cards, plus suggested changes and corrected code blocks when the payload supplies them
- preserve the supplied finding content exactly
- render the footer deterministically when footer metadata is present

## The presentation method

1. **Consume the payload, do not reopen the review** — treat the payload as the frozen source of truth.
2. **Require an explicit schema read in the current run** — do not treat the schema as loaded unless `.github/instructions/review-presentation-input.schema.json` itself was read to EOF.
3. **Render only** — do not invent new findings, new evidence, or new recommendations.
4. **Apply the fixed template** — use the headings, section order, expanded finding-card format, and footer rules from the contract.
5. **Preserve meaning exactly** — if the payload says `- None`, render `- None`; if it contains issues, do not soften them.
6. **Stop at presentation** — emit the final review body and nothing else.

The presentation pass owns no business logic. It does not classify findings, merge related concerns, demote issues to observations, decide whether evidence is strong enough, or repair an invalid findings set. If the payload is wrong or incomplete, the correct behavior is to hard-stop rather than compensate in the renderer.

## Burden of proof

Rendering decisions must be mechanical, not interpretive:

- take the payload fields as authoritative inputs
- use the schema and contract to decide where each field renders
- when the payload provides structured findings for issues or observations, render the contract-defined structured layout for that section rather than flattening the finding into a string or substituting a different card shape
- for non-empty `observations` and `issues`, do not use plain-string fallback; if the payload is not presentation-complete for those sections, the successful render path is unsatisfied and the prompt must hard-stop instead of rendering a normal review body
- render `immediateRecommendations` and `futureConsiderations` only as plain follow-up bullets, never as alternate finding cards
- if the payload or rendered body contains forbidden local-link material such as `vscode-file://`, `vscode://`, `file://`, `workbench.html`, `AppData`, `workspaceStorage`, `C:\`, or `/Users/`, the successful render path is unsatisfied and the prompt must hard-stop instead of emitting that body
- do not infer missing content from surrounding context

If a required field is missing, malformed, or unsupported by the schema, do not guess.

## Outcomes

The presentation skill owns only final rendering:

- **Rendered** — the final review body is emitted in the standard template.
- **Preserved** — findings, classifications, and verdicts remain unchanged from the payload.
- **Omitted footer** — the footer is absent only when the payload omits footer metadata.

## Tone

Neutral and mechanical. The best presentation pass is the one that makes the frozen review easier to read without changing what it means.
<!-- REVIEW-PRESENT-SKILL-EOF -->
