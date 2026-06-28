---
description: "Moderator synthesis pass compliance contract (single source of truth) used by the review-moderator skill as the planned final moderation role for merging workflow findings once explicit moderator routing is enabled."
---

# Review Moderator Compliance Contract

This file is the single source of truth for the moderator synthesis review technique in this repository.

## Consumers

One workflow MUST follow this contract:

- Consumer: `.github/skills/review-moderator/SKILL.md`
  - Role: Moderator
  - Command: `review-moderator` skill, planned as a governed workflow pass after reviewer, architect, skeptic, and advocate records exist, but not yet invoked by the generic code review prompts
  - Requires EOF Load: yes
  - Goal: merge schema-conformant workflow findings, deduplicate overlaps, normalize severity and wording, and produce the final accepted outcome set inside the prompt-owned review template once explicit moderator routing is enabled.

The current generic code review prompts do not yet orchestrate this contract.
The moderator skill encapsulates the reusable moderation method.
This contract defines the moderator-specific deterministic rules.
The shared workflow handoff schema lives at `.github/instructions/review-workflow-handoff.schema.json`.

## Canonical sources of truth (precedence)

Use these sources with the following roles:

- The shared code review contract: `.github/instructions/code-review-compliance-contract.instructions.md`
  - Authoritative for overall review flow, evidence handling, finding classification, output shape, and the `REVIEW-HANDOFF-*` handoff semantics.
  - This moderator contract refines how schema-conformant workflow findings are merged and normalized once explicit moderator routing exists; it must not weaken or override the shared output-shape or handoff rules.
- The advocate contract: `.github/instructions/review-advocate-compliance-contract.instructions.md`
  - Authoritative for the current transitional false-positive-defense gate and its `Confirmed`, `Downgraded`, and `Dismissed` outcome mapping.
- The workflow handoff schema: `.github/instructions/review-workflow-handoff.schema.json`
  - Authoritative for the concrete runtime JSON shape the moderator consumes.
- This contract: `.github/instructions/review-moderator-compliance-contract.instructions.md`
  - Authoritative for the planned moderator synthesis-pass deterministic rules in this repository.
- The moderator skill: `.github/skills/review-moderator/SKILL.md`
  - Reusable moderation method: how to merge routed findings without re-running an independent review.

Conflict resolution:

- This contract is authoritative for planned moderator-pass synthesis, duplicate resolution, severity normalization, and final accepted-outcome selection once the moderator pass is actually invoked.
- The shared code review contract remains authoritative for scope resolution, evidence handling, output shape, and the schema-backed handoff record itself.
- The advocate contract remains authoritative for the current false-positive-defense behavior until the workflow explicitly routes a moderator pass and reassigns responsibilities.
- If this contract would contradict `REVIEW-CLASS-004` (one finding, one classification), `REVIEW-CLASS-004` wins and each moderated concern must still resolve to exactly one classification.

## Rule IDs

Rules are identified by stable IDs so the moderator skill and any future routed prompts reference the same requirement set without drifting.

ID format:
- REVIEW-MOD-<NNN>

Area:
- MOD = moderator synthesis-pass evaluation

## Evidence hierarchy

When the moderator evaluates workflow findings, weigh evidence in this order:

1. The schema-conformant workflow records produced by earlier passes
2. The changed files and actual diff under review
3. Current workspace contributor guidance and file-scoped instructions
4. Current workspace implementation details, tests, and surrounding code
5. PR or commit description and code comments that state design intent
6. External references for semantics only, when workspace evidence is insufficient

If a moderation decision cannot be backed by this evidence, prefer the narrower justified claim rather than inventing a new outcome.

# Contract Rules

## Moderator synthesis-pass evaluation

### REVIEW-MOD-001: Moderator synthesizes existing workflow findings, not a new independent review
- Rule: The moderator consumes schema-conformant workflow records from earlier passes; it does not replace them with a new independent audit.
- Rule: The moderator must not invent new evidence-free issues that were never surfaced into the workflow candidate set.
- Rule: The moderator may request that a weaker claim be narrowed, merged, downgraded, or dismissed based on stronger evidence already in the workflow.

### REVIEW-MOD-002: Moderator consumes the shared handoff schema
- Rule: Every finding the moderator reads or emits in workflow scope must conform to `.github/instructions/review-workflow-handoff.schema.json`.
- Rule: The moderator may enrich `roles`, `ruleReferences`, and `roleNotes`, but it must preserve the record identity and the shared core fields.
- Rule: The moderator must not replace a structured record with prose that loses `id`, `scope`, `evidence`, `reasoning`, `confidence`, or `status`.

### REVIEW-MOD-003: Duplicate concerns merge into one strongest record
- Rule: When multiple workflow records describe the same underlying concern, the moderator must merge them into one record rather than repeat them.
- Rule: The merged record should preserve the strongest evidence, the narrowest defensible claim, and the combined `roles` attribution.
- Rule: Duplicate merging must not inflate the visible finding count.

### REVIEW-MOD-004: Severity and wording normalization are evidence-bound
- Rule: The moderator may normalize severity or wording only when the evidence supports the change.
- Rule: When two plausible phrasings exist, prefer the narrower defensible claim over the broader speculative claim.
- Rule: A normalized record still resolves to exactly one final classification.

### REVIEW-MOD-005: Final synthesis stays inside the prompt-owned output contract
- Rule: The moderator may decide the final accepted, downgraded, dismissed, or merged outcome set, but it must stay inside the prompt-owned visible output structure.
- Rule: The moderator must not add a new reader-visible section that the prompt did not authorize.
- Rule: Scope resolution, stage ordering, and final section names remain prompt-owned even when moderation is enabled.

### REVIEW-MOD-006: Current workflow status must stay explicit
- Rule: Until a prompt explicitly routes the moderator pass, no workflow may claim that `review-moderator` ran.
- Rule: Staged moderator artifacts may exist before moderator routing, but their presence alone does not change the active execution model.

## Output integration

### REVIEW-MOD-007: Moderator output is final synthesis, not role narration
- Rule: The moderator must not narrate its internal merge or conflict-resolution process in the final review body.
- Rule: Any future reader-visible trace of moderator behavior must come through the final normalized finding set or an explicit verification marker authorized by the routed prompt.

<!-- REVIEW-MOD-CONTRACT-EOF -->
