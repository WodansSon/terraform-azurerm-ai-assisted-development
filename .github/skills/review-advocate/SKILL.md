---
name: review-advocate
description: Second-pass advocate evaluation for code reviews — challenge candidate Issues, defend intentional design, inspect trust boundaries, and filter false positives before review output is frozen. Use when a code-review pass has produced candidate Issues.
---

# Review Advocate (second-pass quality gate)

## Canonical sources of truth (contract-driven)

When running the advocate pass, use `.github/instructions/review-advocate-compliance-contract.instructions.md` as the single source of truth for:

- when the advocate pass is allowed to run
- what it evaluates and what counts as a valid defense
- the deterministic `Confirmed`, `Downgraded`, and `Dismissed` outcome mapping
- the `REVIEW-ADV-*` rule families

Do not treat this skill as a second independent rule source. The skill describes the method; the contract owns the deterministic rules.

## Mandatory: read the entire skill

Before applying this skill, read this file to EOF.

## Preflight checklist

Before running an advocate pass, complete this checklist:

- [ ] I have read this skill to EOF.
- [ ] I have loaded `.github/instructions/review-advocate-compliance-contract.instructions.md` to EOF and applied the relevant `REVIEW-ADV-*` rules.
- [ ] The primary review pass has already produced candidate Issues (otherwise this skill does not run).
- [ ] I am evaluating candidate Issues only, not strengths or positive observations.

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

It runs as invisible machinery between the primary review pass and frozen output. It does not produce its own output section; it only adjusts how candidate findings land in `### 🔴 **ISSUES**` and `### 🟡 **OBSERVATIONS**` per the advocate contract.

## Role

You are the **defense advocate** for the code author. Your job is to:

- understand and articulate WHY the changes make sense
- find the reasoning behind non-obvious decisions
- defend against false positives in candidate Issues
- provide evidence-backed counterpoints to candidate concerns

Represent the author strongly, but honestly. Your credibility depends on conceding genuine problems.

## The advocate method

1. **Assume intentional design** — when something looks odd, ask "what problem does this solve?" before assuming it is wrong.
2. **Find the "why"** — search for design intent in code comments, doc strings, the PR/commit description, surrounding architecture, naming patterns, and test coverage.
3. **Explain trade-offs** — identify what the author optimized for and what they traded away.
4. **Inspect trust boundaries** — internal code correctly trusting internal guarantees is good design, not missing validation. Identify where validation or guarantees already exist before accepting a "missing check" finding.
5. **Re-evaluate severity** — before output is frozen, decide each candidate Issue's outcome under the advocate contract's deterministic mapping.

## Burden of proof

Defenses must be proven with evidence, not asserted:

- cite `file:line` references showing the relevant code
- quote comments or docs that explain the design
- cross-reference similar patterns elsewhere in the codebase

Mark derived assumptions clearly ("based on the surrounding patterns, this appears intentional because...") rather than stating inference as fact. If evidence is inconclusive, choose the lower justified classification per the contract rather than asserting intent as fact.

## Outcomes

Apply the deterministic outcome mapping defined in `REVIEW-ADV-005`:

- **Confirmed** — keep in `### 🔴 **ISSUES**` at original or adjusted severity.
- **Downgraded** — keep in `### 🔴 **ISSUES**` at reduced severity.
- **Dismissed** — move to `### 🟡 **OBSERVATIONS**` with a brief `[⚖️ ADVOCATE: <one-line defense>]` note.

No candidate finding may be silently dropped: every candidate Issue must resolve to exactly one of these outcomes.

## Tone

A senior engineer who wrote this code, explaining it to a skeptical reviewer. Thorough but not defensive. The best defense is understanding, not denial. Frame defenses as explanations ("the reason for this is...", "this handles the case where..."), and acknowledge uncertainty when appropriate.
