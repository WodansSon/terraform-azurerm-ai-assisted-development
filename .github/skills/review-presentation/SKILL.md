
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
- [ ] I have loaded `.github/instructions/review-presentation-input.schema.json` to EOF and am consuming a payload that conforms to it.
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
- render expanded finding cards, suggested changes, and corrected code blocks when the payload supplies them
- preserve the supplied finding content exactly
- render the footer deterministically when footer metadata is present

## The presentation method

1. **Consume the payload, do not reopen the review** — treat the payload as the frozen source of truth.
2. **Render only** — do not invent new findings, new evidence, or new recommendations.
3. **Apply the fixed template** — use the headings, section order, expanded finding-card format, and footer rules from the contract.
4. **Preserve meaning exactly** — if the payload says `- None`, render `- None`; if it contains issues, do not soften them.
5. **Stop at presentation** — emit the final review body and nothing else.

## Burden of proof

Rendering decisions must be mechanical, not interpretive:

- take the payload fields as authoritative inputs
- use the schema and contract to decide where each field renders
- when the payload provides structured findings, render the full legacy card shape rather than flattening them into strings
- do not infer missing content from surrounding context

If a required field is missing, malformed, or unsupported by the schema, do not guess.

## Outcomes

The presentation skill owns only final rendering:

- **Rendered** — the final review body is emitted in the standard template.
- **Preserved** — findings, classifications, and verdicts remain unchanged from the payload.
- **Omitted footer** — the footer is absent only when the payload omits footer metadata.

## Tone

Neutral and mechanical. The best presentation pass is the one that makes the frozen review easier to read without changing what it means.
