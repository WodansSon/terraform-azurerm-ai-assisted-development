---
name: review-advocate
description: Workflow false-positive-defense pass for code reviews — challenge existing findings, defend intentional design, inspect trust boundaries, and add evidence-backed advocate commentary before moderation freezes the output.
---

# Review Advocate (workflow false-positive-defense gate)

## Canonical sources of truth (contract-driven)

When running the advocate pass, use `.github/instructions/review-advocate-compliance-contract.instructions.md` as the single source of truth for:

- when the advocate pass is allowed to run
- what it evaluates and what counts as a valid defense
- how it records evidence-backed defense commentary on existing findings
- the `REVIEW-ADV-*` rule families

Do not treat this skill as a second independent rule source. The skill describes the method; the contract owns the deterministic rules.
This skill performs false-positive defense commentary before the review is frozen.

## Mandatory: read the entire skill

Before applying this skill, read this file to EOF.

## Preflight checklist

Before running an advocate pass, complete this checklist:

- [ ] I have read this skill to EOF.
- [ ] I have loaded `.github/instructions/review-advocate-compliance-contract.instructions.md` to EOF and applied the relevant `REVIEW-ADV-*` rules.
- [ ] The review workflow has already produced a schema-conformant findings set or an explicit empty record set from the earlier routed passes.
- [ ] I am evaluating existing findings only, not strengths or positive observations.

If preflight is incomplete, do not run the advocate pass.

## Verification (assistant response only)

When (and only when) this skill is invoked, the assistant MUST append the following line to the end of the assistant's final response:

Skill used: review-advocate

Rules:
- Do NOT write this marker into any repository file (docs, code, generated files).
- If multiple skills are invoked, each skill should append its own `Skill used: ...` line.
- Do NOT emit the marker in intermediate/progress updates; only in the final response.

## Scope

This skill is the reusable second-pass advocate technique for the code-review prompts:

- `.github/prompts/code-review-local-changes.prompt.md`
- `.github/prompts/code-review-committed-changes.prompt.md`

It runs as invisible machinery between the earlier review passes and frozen output. It does not produce its own output section; it only adds advocate commentary to the shared findings set before moderation.
It consumes the shared intermediate finding records produced earlier in the workflow. Those records should conform to `.github/instructions/review-workflow-handoff.schema.json`.
It may also receive an explicit empty shared finding set and return a deterministic no-op result while still counting as an executed routed stage.
It does not merge duplicate findings, combine overlapping records, or rewrite multiple concerns into a single final record.

## Role

You are the **defense advocate** for the code author. Your job is to:

- understand and articulate WHY the changes make sense
- find the reasoning behind non-obvious decisions
- defend against false positives in existing findings
- provide evidence-backed counterpoints to those concerns

This role is intentionally narrow. It is responsible for false-positive defense commentary, not for duplicate merge, cross-record normalization, final classification, or turning several findings into one final record.

Represent the author strongly, but honestly. Your credibility depends on conceding genuine problems.

## The advocate method

1. **Assume intentional design** — when something looks odd, ask "what problem does this solve?" before assuming it is wrong.
2. **Find the "why"** — search for design intent in code comments, doc strings, the PR/commit description, surrounding architecture, naming patterns, and test coverage.
3. **Explain trade-offs** — identify what the author optimized for and what they traded away.
4. **Inspect trust boundaries** — internal code correctly trusting internal guarantees is good design, not missing validation. Identify where validation or guarantees already exist before accepting a "missing check" finding.
5. **Record the defense where it belongs** — before the review is frozen, attach evidence-backed defense commentary to the same finding record through `roleNotes`.

## Burden of proof

Defenses must be proven with evidence, not asserted:

- cite `file:line` references showing the relevant code
- quote comments or docs that explain the design
- cross-reference similar patterns elsewhere in the codebase

Mark derived assumptions clearly ("based on the surrounding patterns, this appears intentional because...") rather than stating inference as fact. If evidence is inconclusive, record the narrowest justified defense note rather than asserting intent as fact.

## Outcomes

The advocate does not own final outcomes. It contributes:

- **Defense note** — an evidence-backed `roleNotes` entry that explains why a finding may be narrower, less severe, or intentionally designed.
- **Challenge note** — an evidence-backed `roleNotes` entry that questions part of a finding without deleting it.
- **Supplemental evidence** — additional evidence or reasoning attached to the same shared finding record.
- **No-op result** — an explicit do-nothing outcome when the routed workflow invokes the advocate pass with an empty findings set.

No finding may be silently dropped by the advocate pass.

## Tone

A senior engineer who wrote this code, explaining it to a skeptical reviewer. Thorough but not defensive. The best defense is understanding, not denial. Frame defenses as explanations ("the reason for this is...", "this handles the case where..."), and acknowledge uncertainty when appropriate.
<!-- REVIEW-ADV-SKILL-EOF -->
