---
description: "Advocate second-pass compliance contract (single source of truth) used by the review-advocate skill as the workflow false-positive-defense gate for the workflow candidate-Issue set before review output is frozen."
---

# Review Advocate Compliance Contract

This file is the single source of truth for the advocate second-pass review technique in this repository.

## Consumers

One workflow MUST follow this contract:

- Consumer: `.github/skills/review-advocate/SKILL.md`
  - Role: Advocate
  - Command: `review-advocate` skill, invoked by `/code-review-local-changes` and `/code-review-committed-changes`
  - Requires EOF Load: yes
  - Goal: perform the workflow false-positive-defense step by challenging existing findings, defending intentional design where supported, and attaching evidence-backed advocate commentary before the review output is frozen.

The review prompts orchestrate when the advocate pass runs.
The advocate skill encapsulates the reusable advocate method.
This contract defines the advocate-specific deterministic rules.
This contract governs the advocate false-positive-defense pass only.
It owns advocate commentary and defense-note requirements only.
The shared workflow handoff schema lives at `.github/instructions/review-workflow-handoff.schema.json`.

## Canonical sources of truth (precedence)

Use these sources with the following roles:

- The shared code review contract: `.github/instructions/code-review-compliance-contract.instructions.md`
  - Authoritative for overall review flow, evidence handling, finding classification, and output shape.
  - This advocate contract refines how existing findings are challenged before output is frozen; it must not weaken or override the `REVIEW-CLASS-*` or `REVIEW-HANDOFF-*` semantics.
- This contract: `.github/instructions/review-advocate-compliance-contract.instructions.md`
  - Authoritative for the advocate second-pass deterministic rules in this repository.
- The advocate skill: `.github/skills/review-advocate/SKILL.md`
  - Reusable advocate method: how to challenge findings, search for design intent, and inspect trust boundaries.

Conflict resolution:

- This contract is authoritative for advocate-pass activation, finding evaluation, valid-defense requirements, and how the advocate records commentary on existing findings.
- The shared code review contract remains authoritative for overall review flow, evidence handling, classification semantics, and output shape.
- The shared code review contract remains authoritative for the intermediate handoff shape and the allowed workflow fields that exist before and after advocate commentary.
- `.github/instructions/review-workflow-handoff.schema.json` is the concrete runtime schema artifact for that handoff shape.
- If this contract would contradict `REVIEW-CLASS-004` (one finding, one classification), `REVIEW-CLASS-004` wins and the advocate must narrow or clarify its commentary rather than creating a second conflicting classification.

## Rule IDs

Rules are identified by stable IDs so the advocate skill and the review prompts reference the same requirement set without drifting.

ID format:
- REVIEW-ADV-<NNN>

Area:
- ADV = advocate second-pass evaluation

## Evidence hierarchy

When the advocate evaluates a finding, weigh evidence in this order:

1. The changed files and the actual diff under review
2. Current workspace contributor guidance and file-scoped instructions
3. Current workspace implementation details, tests, and surrounding code
4. PR/commit description and code comments that state design intent
5. External references for semantics only, when workspace evidence is insufficient

If a defense cannot be backed by this evidence, it is not a valid defense.

# Contract Rules

## Advocate second-pass evaluation

### REVIEW-ADV-001: Advocate pass runs only after workflow findings exist
- Rule: The advocate pass runs on every normal successful routed review path after the earlier routed finding-generation passes and before output is frozen.
- Rule: Findings eligible for the advocate pass may originate in the primary review pass or in routed skeptic or architect passes that run before output is frozen.
- Rule: If the primary pass and any routed intermediate passes produced no findings, the advocate pass still runs against an explicit empty structured finding set and returns a deterministic no-op result.
- Rule: The advocate pass must not invent new findings merely because it was invoked with an empty set.
- Rule: The advocate pass runs before the review output is frozen, never after.
- Rule: The advocate consumes the structured workflow finding set defined by `REVIEW-HANDOFF-*` and `.github/instructions/review-workflow-handoff.schema.json`; it must not bypass that shared handoff shape with ad hoc prose-only reasoning.

### REVIEW-ADV-002: Advocate evaluates findings, not strengths
- Rule: The advocate evaluates existing findings only.
- Rule: The advocate must not directly re-classify, remove, or hide Strengths or positive observations.

### REVIEW-ADV-003: Defenses require evidence, not speculation
- Rule: A valid defense must cite concrete evidence such as a `file:line` reference, a quoted comment or doc, or a cross-referenced pattern elsewhere in the codebase.
- Rule: Do not accept "this is probably intentional" as a defense without evidence.
- Rule: Mark derived assumptions explicitly rather than stating inference as fact.

### REVIEW-ADV-004: Trust-boundary defenses must identify existing guarantees
- Rule: When a finding criticizes "missing" validation, a defense is valid only if it identifies where validation or a guarantee already exists.
- Rule: A trust-boundary defense must show that a caller or callee provides the guarantee that makes the flagged check redundant.
- Rule: "Internal code trusts internal code" is not a valid defense unless the relied-upon guarantee is identified.

### REVIEW-ADV-005: Advocate records commentary, not outcomes
- Rule: The advocate preserves every finding record's shared fields and communicates through `roleNotes`, added evidence, or clarified reasoning.
- Rule: The advocate may recommend a narrower severity, an observation classification, or an omission as duplicate only through evidence-backed `roleNotes`; it must not change `classification`, `visible`, or duplicate-merge lineage directly.
- Rule: The advocate does not merge, combine, or rewrite multiple records.

### REVIEW-ADV-006: No finding may be silently dropped by the advocate pass
- Rule: The advocate must not delete, hide, or replace an existing finding with prose-only commentary.
- Rule: If the advocate believes a finding is a false positive or intentional design, that defense must remain visible to downstream moderation through `roleNotes` on the same record.

### REVIEW-ADV-007: Advocate defenses stay attached to the challenged finding
- Rule: Each advocate defense must stay attached to the challenged finding via `roleNotes` with evidence-backed reasoning.
- Rule: The advocate must not create a parallel unstructured commentary channel for defense notes.

### REVIEW-ADV-008: Inconclusive evidence favors narrower commentary
- Rule: When evidence is inconclusive, record the narrowest justified defense note rather than asserting intent as fact.
- Rule: Do not present advocate inference as proven design intent when the evidence does not establish it.
- Rule: Do not merge duplicate records, combine role attribution across multiple records, or rewrite several concerns into one final concern; those actions are outside advocate scope.

## Output integration

### REVIEW-ADV-009: The advocate pass produces no separate output section
- Rule: The advocate pass is invisible machinery; it must not emit its own heading or section in the review body.
- Rule: The advocate pass must not narrate its evaluation process in the review output.

<!-- REVIEW-ADV-CONTRACT-EOF -->
