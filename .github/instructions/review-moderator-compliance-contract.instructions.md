---
description: "Moderator synthesis pass compliance contract (single source of truth) used by the review-moderator skill as the final moderation role for merging workflow findings in the generic code review workflow."
---

# Review Moderator Compliance Contract

This file is the single source of truth for the moderator synthesis review technique in this repository.

## Consumers

One workflow MUST follow this contract:

- Consumer: `.github/skills/review-moderator/SKILL.md`
  - Role: Moderator
  - Command: `review-moderator` skill, invoked as the governed final moderation pass after reviewer, architect, skeptic, and advocate records exist
  - Requires EOF Load: yes
  - Goal: merge schema-conformant workflow findings, deduplicate overlaps, normalize severity and wording, and produce the final merged-and-normalized moderated finding set for downstream presentation, including an explicit deterministic empty-result freeze when no findings survive into moderation.

The generic code review prompts orchestrate this contract.
The moderator skill encapsulates the reusable moderation method.
This contract defines the moderator-specific deterministic rules.
The shared workflow handoff schema lives at `.github/instructions/review-workflow-handoff.schema.json`.

## Canonical sources of truth (precedence)

Use these sources with the following roles:

- The shared code review contract: `.github/instructions/code-review-compliance-contract.instructions.md`
  - Authoritative for overall review flow, evidence handling, finding classification, output shape, and the `REVIEW-HANDOFF-*` handoff semantics.
  - This moderator contract refines how schema-conformant workflow findings are merged and normalized in the routed workflow; it must not weaken or override the shared output-shape or handoff rules.
- The advocate contract: `.github/instructions/review-advocate-compliance-contract.instructions.md`
  - Authoritative for upstream candidate-level `Confirmed`, `Downgraded`, and `Dismissed` status outcomes that this contract must consume rather than recreate.
- The workflow handoff schema: `.github/instructions/review-workflow-handoff.schema.json`
  - Authoritative for the concrete runtime JSON shape the moderator consumes.
- This contract: `.github/instructions/review-moderator-compliance-contract.instructions.md`
  - Authoritative for the moderator synthesis-pass deterministic rules in this repository.
- The moderator skill: `.github/skills/review-moderator/SKILL.md`
  - Reusable moderation method: how to merge routed findings without re-running an independent review.

Conflict resolution:

- This contract is authoritative for moderator-pass synthesis, duplicate resolution, severity normalization, and final accepted-outcome selection in the routed workflow.
- Upstream candidate-level `Confirmed`, `Downgraded`, and `Dismissed` status outcomes remain authoritative inputs to moderation; this contract must consume those outcomes rather than recreate them.
- The shared code review contract remains authoritative for scope resolution, evidence handling, output shape, and the schema-backed handoff record itself.
- If this contract would contradict `REVIEW-CLASS-004` (one finding, one classification), `REVIEW-CLASS-004` wins and each moderated concern must still resolve to exactly one classification.

## Rule IDs

Rules are identified by stable IDs so the moderator skill and the routed prompts reference the same requirement set without drifting.

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
- Rule: The moderator may request that a weaker claim be narrowed, merged, or phrased more precisely based on stronger evidence already in the workflow.
- Rule: The moderator must also support the explicit empty-record-set case and freeze that case as a deterministic zero-findings outcome rather than leaving the workflow without a final moderation owner.

### REVIEW-MOD-002: Moderator consumes the shared handoff schema
- Rule: Every finding the moderator reads or emits in workflow scope must conform to `.github/instructions/review-workflow-handoff.schema.json`.
- Rule: The moderator may enrich `roles`, `ruleReferences`, `roleNotes`, and `presentation`, but it must preserve the record identity and the shared core fields.
- Rule: The moderator must not replace a structured record with prose that loses `id`, `scope`, `evidence`, `reasoning`, `confidence`, or `status`.
- Rule: A routed prompt may invoke moderator with an explicit empty record set for the current run; that empty set is a valid schema-conformant moderation input and must be treated as a real finalization state, not as an implicit skip.

### REVIEW-MOD-002A: Moderator owns deterministic presentation hints for surviving findings
- Rule: For surviving moderated findings, the moderator may populate the optional `presentation` object on the shared handoff record when that metadata can be stated deterministically from the finding and its evidence.
- Rule: If a surviving finding is intended to render as a structured finding card in the downstream presentation layer, the moderator owns the corresponding `presentation` hints for that card.
- Rule: `presentation.reviewType` should be set when the surviving finding clearly fits one of the supported renderer review types.
- Rule: `presentation.suggestedChange` should be set when one narrow deterministic fix or next change is supported by the evidence.
- Rule: `presentation.correctedCode` may be set only when the moderator can provide a concrete corrected snippet without guessing surrounding semantics.
- Rule: `presentation.currentCode` may be set only when the moderator can identify the relevant current snippet deterministically from the finding evidence.
- Rule: `presentation.codeLanguage` may be set only when `presentation.correctedCode` is present.
- Rule: If a suggested change, current code snippet, or corrected code snippet cannot be backed deterministically, leave the corresponding `presentation` field absent rather than inventing it.
- Rule: Downstream prompts and the render-only presentation layer must not invent missing `presentation.reviewType`, `presentation.suggestedChange`, `presentation.currentCode`, `presentation.correctedCode`, or `presentation.codeLanguage` fields on behalf of the moderator.

### REVIEW-MOD-003: Duplicate concerns merge into one strongest record
- Rule: When multiple workflow records describe the same underlying concern, the moderator must merge them into one record rather than repeat them.
- Rule: The merged record should preserve the strongest evidence, the narrowest defensible claim, and the combined `roles` attribution.
- Rule: Duplicate merging must not inflate the visible finding count.

### REVIEW-MOD-004: Severity and wording normalization are evidence-bound
- Rule: The moderator may normalize severity or wording only when the evidence supports the change.
- Rule: When two plausible phrasings exist, prefer the narrower defensible claim over the broader speculative claim.
- Rule: A normalized record still resolves to exactly one final classification.

### REVIEW-MOD-004A: Moderator does not reopen advocate-owned defense outcomes
- Rule: When the workflow includes already-adjudicated records, the moderator must treat `confirmed`, `downgraded`, and `dismissed` as upstream status outcomes rather than re-litigating them.
- Rule: The moderator may decide which records survive duplicate merge and how surviving records are normalized for final presentation, but it must not invent a second false-positive-defense pass under moderator authority.

### REVIEW-MOD-004B: Presentation hints are evidence-bound
- Rule: The moderator may normalize or add `presentation.reviewType`, `presentation.suggestedChange`, `presentation.currentCode`, or `presentation.correctedCode` only when the finding evidence supports the change.
- Rule: The moderator must not attach optimistic remediation prose or corrected code that goes beyond the proven defect.

### REVIEW-MOD-005: Final synthesis stays inside the downstream output contract
- Rule: The moderator may decide the final merged-and-normalized moderated finding set from the workflow records it received, but it must not render or restructure the final reader-visible review body.
- Rule: The moderator must not add a new reader-visible section that the prompt or downstream presentation renderer did not authorize.
- Rule: Scope resolution, stage ordering, and final section names remain outside moderator authority even when moderation is enabled.
- Rule: When the moderator receives an explicit empty record set, it must finalize that run as a deterministic empty moderated result rather than treating the absence of findings as a skipped moderation stage.

### REVIEW-MOD-006: Moderator routing must stay explicit
- Rule: Only a prompt that explicitly routes the moderator pass may claim that `review-moderator` ran.
- Rule: Generic code review prompts that route moderator must do so after candidate-level adjudication and before final output is frozen.

## Output integration

### REVIEW-MOD-007: Moderator output is final synthesis, not role narration
- Rule: The moderator must not narrate its internal merge or conflict-resolution process in the final review body.
- Rule: Any reader-visible trace of moderator behavior must come through the final normalized finding set or an explicit verification marker authorized by the routed prompt.

### REVIEW-MOD-008: Moderator output may prepare the render-only presentation layer
- Rule: The moderator may enrich surviving workflow findings with deterministic `presentation` hints so the downstream render-only presentation layer can emit the richer legacy review hierarchy without the prompts inventing display semantics ad hoc.
- Rule: Those hints must remain subordinate to the shared handoff record and must not become a second classification system.

<!-- REVIEW-MOD-CONTRACT-EOF -->
