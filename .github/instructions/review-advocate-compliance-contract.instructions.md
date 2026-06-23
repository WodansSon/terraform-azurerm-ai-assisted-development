---
description: "Advocate second-pass compliance contract (single source of truth) used by the review-advocate skill to challenge candidate Issues and filter false positives before review output is frozen."
---

# Review Advocate Compliance Contract

This file is the single source of truth for the advocate second-pass review technique in this repository.

## Consumers

One workflow MUST follow this contract:

- Consumer: `.github/skills/review-advocate/SKILL.md`
  - Role: Advocate
  - Command: `review-advocate` skill, invoked by `/code-review-local-changes` and `/code-review-committed-changes`
  - Requires EOF Load: yes
  - Goal: challenge candidate Issues, defend intentional design, and resolve each candidate to a deterministic outcome before output is frozen.

The review prompts orchestrate when the advocate pass runs.
The advocate skill encapsulates the reusable advocate method.
This contract defines the advocate-specific deterministic rules.

## Canonical sources of truth (precedence)

Use these sources with the following roles:

- The shared code review contract: `.github/instructions/code-review-compliance-contract.instructions.md`
  - Authoritative for overall review flow, evidence handling, finding classification, and output shape.
  - This advocate contract refines how candidate Issues are challenged before output is frozen; it must not weaken or override the `REVIEW-CLASS-*` semantics.
- This contract: `.github/instructions/review-advocate-compliance-contract.instructions.md`
  - Authoritative for the advocate second-pass deterministic rules in this repository.
- The advocate skill: `.github/skills/review-advocate/SKILL.md`
  - Reusable advocate method: how to challenge findings, search for design intent, and inspect trust boundaries.

Conflict resolution:

- This contract is authoritative for advocate-pass activation, candidate evaluation, valid-defense requirements, and the `Confirmed`, `Downgraded`, and `Dismissed` outcome mapping.
- The shared code review contract remains authoritative for overall review flow, evidence handling, classification semantics, and output shape.
- If this contract would contradict `REVIEW-CLASS-004` (one finding, one classification), `REVIEW-CLASS-004` wins and the outcome mapping in `REVIEW-ADV-005` must be read so that each candidate still resolves to exactly one classification.

## Rule IDs

Rules are identified by stable IDs so the advocate skill and the review prompts reference the same requirement set without drifting.

ID format:
- REVIEW-ADV-<NNN>

Area:
- ADV = advocate second-pass evaluation

## Evidence hierarchy

When the advocate evaluates a candidate Issue, weigh evidence in this order:

1. The changed files and the actual diff under review
2. Current workspace contributor guidance and file-scoped instructions
3. Current workspace implementation details, tests, and surrounding code
4. PR/commit description and code comments that state design intent
5. External references for semantics only, when workspace evidence is insufficient

If a defense cannot be backed by this evidence, it is not a valid defense.

# Contract Rules

## Advocate second-pass evaluation

### REVIEW-ADV-001: Advocate pass runs only after candidate Issues exist
- Rule: The advocate pass runs only after the primary review pass has produced one or more candidate Issues.
- Rule: If the primary pass produced no candidate Issues, the advocate pass does not run and changes nothing.
- Rule: The advocate pass runs before the review output is frozen, never after.

### REVIEW-ADV-002: Advocate evaluates candidate Issues, not strengths
- Rule: The advocate evaluates candidate Issues only.
- Rule: The advocate must not re-classify, weaken, or remove Strengths or positive observations.

### REVIEW-ADV-003: Defenses require evidence, not speculation
- Rule: A valid defense must cite concrete evidence such as a `file:line` reference, a quoted comment or doc, or a cross-referenced pattern elsewhere in the codebase.
- Rule: Do not accept "this is probably intentional" as a defense without evidence.
- Rule: Mark derived assumptions explicitly rather than stating inference as fact.

### REVIEW-ADV-004: Trust-boundary defenses must identify existing guarantees
- Rule: When a candidate Issue criticizes "missing" validation, a defense is valid only if it identifies where validation or a guarantee already exists.
- Rule: A trust-boundary defense must show that a caller or callee provides the guarantee that makes the flagged check redundant.
- Rule: "Internal code trusts internal code" is not a valid defense unless the relied-upon guarantee is identified.

### REVIEW-ADV-005: Deterministic outcome mapping
- Rule: Each candidate Issue must resolve to exactly one of three outcomes.
- Rule: `Confirmed` — no valid defense found. Keep in `### 🔴 **ISSUES**` at original or adjusted severity.
- Rule: `Downgraded` — partial valid defense found; the issue is less severe than first classified. Keep in `### 🔴 **ISSUES**` at reduced severity.
- Rule: `Dismissed` — strong evidence the finding is a false positive or intentional design. Move to `### 🟡 **OBSERVATIONS**` with a brief `[⚖️ ADVOCATE: <one-line defense>]` note.
- Rule: `Downgraded` is distinct from `Dismissed`; a downgraded finding stays in `ISSUES`, a dismissed finding moves to `OBSERVATIONS`.

### REVIEW-ADV-006: No candidate finding may be silently dropped
- Rule: Every candidate Issue must end as `Confirmed`, `Downgraded`, or `Dismissed`.
- Rule: The advocate must not delete or hide a candidate Issue without one of those outcomes.

### REVIEW-ADV-007: Dismissed findings move to Observations with rationale
- Rule: A dismissed finding must appear in `### 🟡 **OBSERVATIONS**`, not be removed entirely.
- Rule: Each dismissed finding must carry a brief `[⚖️ ADVOCATE: <one-line defense>]` annotation that states the evidence-backed reason.

### REVIEW-ADV-008: Inconclusive evidence chooses the lower justified classification
- Rule: When evidence is inconclusive, choose the lower justified classification rather than asserting intent as fact.
- Rule: Prefer `Downgraded` over `Confirmed`, and `Dismissed` over `Downgraded`, only when evidence supports it; otherwise keep the finding `Confirmed`.
- Rule: Do not present advocate inference as proven design intent when the evidence does not establish it.

## Output integration

### REVIEW-ADV-009: The advocate pass produces no separate output section
- Rule: The advocate pass is invisible machinery; it must not emit its own heading or section in the review body.
- Rule: The only reader-visible trace of the advocate pass is the `[⚖️ ADVOCATE: ...]` annotation on dismissed findings in `OBSERVATIONS`.
- Rule: The advocate pass must not narrate its evaluation process in the review output.

<!-- REVIEW-ADV-CONTRACT-EOF -->
