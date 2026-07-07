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
  - Authoritative for upstream advocate commentary that this contract must consume rather than recreate.
- The workflow handoff schema: `.github/instructions/review-workflow-handoff.schema.json`
  - Authoritative for the concrete runtime JSON shape the moderator consumes.
- This contract: `.github/instructions/review-moderator-compliance-contract.instructions.md`
  - Authoritative for the moderator synthesis-pass deterministic rules in this repository.
- The moderator skill: `.github/skills/review-moderator/SKILL.md`
  - Reusable moderation method: how to merge routed findings without re-running an independent review.

Conflict resolution:

- This contract is authoritative for moderator-pass synthesis, duplicate resolution, severity normalization, and final accepted-outcome selection in the routed workflow.
- Upstream reviewer, architect, skeptic, and advocate record content remains authoritative input to moderation; this contract must consume that full finding set rather than recreate it.
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
- Rule: The moderator must not replace a structured record with prose that loses `id`, `scope`, `evidence`, `reasoning`, `confidence`, `classification`, or `visible`.
- Rule: A routed prompt may invoke moderator with an explicit empty record set for the current run; that empty set is a valid schema-conformant moderation input and must be treated as a real finalization state, not as an implicit skip.

### REVIEW-MOD-002A: Moderator owns deterministic presentation hints for surviving findings
- Rule: For surviving moderated findings, the moderator must populate the `presentation` object on the shared handoff record whenever that finding will remain in a non-empty final `ISSUES` or `OBSERVATIONS` section and the required metadata can be stated deterministically from the finding and its evidence.
- Rule: If a surviving finding is intended to render as a structured finding card in the downstream presentation layer, the moderator owns the corresponding `presentation` hints for that card.
- Rule: For every surviving finding that will appear in non-empty final `ISSUES` or `OBSERVATIONS` sections, the moderator must provide a presentation-ready structured finding shape instead of relying on downstream fallback behavior.
- Rule: That presentation-ready shape must include `presentation.summary`, `presentation.reviewType`, `presentation.impact`, and `presentation.evidence` for each such surviving finding.
- Rule: `presentation.reviewType` should be set when the surviving finding clearly fits one of the supported renderer review types.
- Rule: `presentation.summary` should be set to the concise user-visible finding title that downstream presentation will render.
- Rule: When a surviving finding is intended to render in the compact titled-finding layout, the moderator must normalize `presentation.summary` to concise title case unless literal code identifiers, Terraform or Go identifiers, acronym casing, or quoted source wording must remain unchanged for correctness.
- Rule: That title-case normalization requirement still applies when downstream presentation uses compact emoji-only issue or observation title prefixes such as `🔥`, `🔴`, `🟡`, `🔵`, or `ℹ️`; dropping the textual severity label does not permit sentence-case prose summaries to pass through unchanged.
- Rule: In that compact titled-finding layout, treat ordinary summary words such as `uses`, `does not include`, `lets`, `drifts`, or `uses unproven` as candidates for title-case normalization unless they are part of a literal quoted phrase or identifier that must remain source-accurate.
- Rule: `presentation.impact` should be set when the surviving finding is intended to render in the compact titled-finding layout and the user-facing consequence can be stated deterministically from the finding and its evidence.
- Rule: `presentation.evidence` should be set when the surviving finding needs a preserved user-facing evidence block, including direct file references or line references, in the compact titled-finding layout.
- Rule: `presentation.evidence` in the compact titled-finding layout should preserve the core explanatory reasoning for why the referenced code is a concern; a bare list of file or line links is insufficient when the finding's meaning depends on behavior, state transitions, or contract mismatch.
- Rule: `presentation.suggestedChange` should be set when one narrow deterministic fix or next change is supported by the evidence.
- Rule: `presentation.correctedCode` may be set only when the moderator can provide a concrete corrected snippet without guessing surrounding semantics.
- Rule: `presentation.currentCode` may be set only when the moderator can identify the relevant current snippet deterministically from the finding evidence.
- Rule: `presentation.codeLanguage` may be set only when `presentation.correctedCode` is present.
- Rule: If a summary, impact summary, evidence block, suggested change, current code snippet, or corrected code snippet cannot be backed deterministically, leave the corresponding `presentation` field absent rather than inventing it, and do not keep that record in a non-empty final `ISSUES` or `OBSERVATIONS` section that requires structured presentation.
- Rule: Downstream prompts and the render-only presentation layer must not invent missing `presentation.summary`, `presentation.reviewType`, `presentation.impact`, `presentation.evidence`, `presentation.suggestedChange`, `presentation.currentCode`, `presentation.correctedCode`, or `presentation.codeLanguage` fields on behalf of the moderator.

### REVIEW-MOD-002B: Moderator owns final visibility
- Rule: The moderator owns whether a moderated record is visible in the final review by setting `visible=true` or `visible=false` on the shared handoff record.
- Rule: Final visible findings must carry `visible=true`.
- Rule: Records absorbed into a genuine duplicate merge must carry `visible=false` and `mergedInto=<surviving-record-id>`.
- Rule: Downstream prompts and the presentation layer must not override moderator-owned `visible` decisions.

### REVIEW-MOD-002C: Moderator owns visible issue and observation semantics
- Rule: For final `ISSUES` and `OBSERVATIONS`, the moderator is the sole owner of which concerns appear, whether they appear, and how surviving records are classified as `issue` or `observation`.
- Rule: Generic review prompts may transport moderator-owned visibility, classification, and presentation data into the presentation payload, but they must not add a second policy layer for concern selection, placement, or rich finding semantics.
- Rule: The render-only presentation layer may format the supplied payload, but it must not reinterpret moderator-owned visibility or classification decisions.

### REVIEW-MOD-003: Duplicate concerns merge into one strongest record
- Rule: When multiple workflow records describe the same underlying concern, the moderator must merge them into one record rather than repeat them.
- Rule: The merged record should preserve the strongest evidence, the narrowest defensible claim, and the combined `roles` attribution.
- Rule: Duplicate merging must not inflate the visible finding count.
- Rule: Records are not duplicates merely because they touch the same file, resource, or pull request.
- Rule: Distinct issue-class concerns, distinct lifecycle-window concerns, and distinct docs-versus-implementation concerns must remain separate records when their evidence or reasoning establishes different defects or different non-blocking risks.
- Rule: For variant-constrained managed surfaces, a foreign-variant admission concern (`ownership-overlap`) and a later foreign-variant lifecycle inconsistency concern (`mode-gating-symmetry`) are not duplicates and must remain separate even when the same generic ID or lookup path is part of both evidence chains.
- Rule: A `patch-residual-state` concern such as a `PUT` versus `PATCH` mismatch is not a duplicate of ownership, lifecycle-symmetry, or optional-state-drift concerns merely because the same update path or metadata field helps prove more than one review concern.
- Rule: A missing `acceptance-test-matrix` concern is not a duplicate of metadata-drift, import-symmetry, or docs-example findings merely because the same acceptance-test file supplies part of the evidence.
- Rule: Records with different mandatory `issueClasses` lineage must remain separate unless they are genuinely duplicate descriptions of the same single concern and the surviving record preserves the union of their `issueClasses` values.
- Rule: When records are merged as genuine duplicates, the absorbed records must carry `mergedInto=<surviving-record-id>` so downstream payload assembly can prove that those records were merged rather than silently dropped.

### REVIEW-MOD-004: Severity and wording normalization are evidence-bound
- Rule: The moderator may normalize severity or wording only when the evidence supports the change.
- Rule: When two plausible phrasings exist, prefer the narrower defensible claim over the broader speculative claim.
- Rule: A normalized record still resolves to exactly one final classification.

### REVIEW-MOD-004A: Critical versus high severity is determined by present destructive or catastrophic harm
- Rule: Use `critical` severity only when current-run evidence proves a present destructive, catastrophic, or severe trust-boundary failure, not merely a blocking correctness defect.
- Rule: `critical` severity is appropriate when the current run proves one or more of the following on a valid workflow path: irreversible delete or destroy behavior against the wrong remote object, concrete mutate-or-destroy behavior across a variant or ownership boundary, severe security-boundary failure with meaningful exposure, or another clearly catastrophic state-corruption path.
- Rule: Use `high` severity for proven blocking correctness defects that must be fixed before merge but do not meet that catastrophic or destructive bar.
- Rule: A concrete foreign-variant admission path without a separately proven foreign-variant mutate-or-destroy path is normally `high`, even though it remains a blocking `issue`.
- Rule: A concrete foreign-variant mutate-or-destroy path must be `critical` because the current run already proves destructive behavior across the ownership boundary.
- Rule: That destructive-path proof may be assembled across separate surviving findings when the current run proves late foreign-variant admission on the same generic identifier or lookup path and also proves an unconditional foreign-variant delete or mutate window on that path; the lifecycle-window finding must still normalize to `critical` even if its own prose states the destructive consequence conditionally.
- Rule: Blocking optional-state-drift and import round-trip defects are normally `high` unless the current run also proves catastrophic corruption or destructive side effects.

### REVIEW-MOD-004B: Moderator consumes advocate commentary without inventing a second advocate pass
- Rule: When the workflow includes advocate `roleNotes`, the moderator must treat them as upstream commentary inputs rather than inventing a second false-positive-defense pass.
- Rule: The moderator may decide which records survive duplicate merge and how surviving records are normalized or classified for final presentation, but it must not erase advocate commentary from surviving records.

### REVIEW-MOD-004BA: Surviving findings map mechanically by classification and visibility
- Rule: For surviving non-duplicate records, the moderator must set `classification=issue` or `classification=observation` explicitly.
- Rule: The moderator must keep a surviving record classified as an `issue` when current-run evidence proves a concrete foreign-variant admission path or a concrete foreign-variant destroy or mutate path on a variant-constrained managed surface.
- Rule: When current-run evidence proves a concrete foreign-variant destroy or mutate path on a variant-constrained managed surface, the moderator must normalize that surviving `issue` to `critical` severity.
- Rule: When current-run evidence proves late foreign-variant admission in one surviving finding and a later unconditional delete or mutate window in another surviving finding on the same generic identifier or lookup path, the moderator must treat that pair as sufficient proof for `critical` severity on the lifecycle-window finding.
- Rule: When current-run evidence proves a concrete foreign-variant admission path on a variant-constrained managed surface but does not separately prove destroy or mutate behavior, the moderator should normally keep that surviving `issue` at `high` severity.
- Rule: When multiple visible `issue` records survive moderation, the moderator must order them for final presentation by descending severity: `critical`, then `high`, then `medium`, then `low`.
- Rule: Within the same severity tier, the moderator should preserve the existing deterministic surviving-record order unless another explicit contract rule requires a different ordering.
- Rule: The moderator must keep a surviving `patch-residual-state` record classified as an `observation` when current-run evidence proves only broader request-shape or residual-state risk, including `PUT` versus `PATCH` mismatches, and does not prove concrete destructive harm.
- Rule: The moderator must not set `visible=false` on a surviving non-duplicate record merely because another surviving record is stronger, richer, or already carries structured presentation hints.
- Rule: A record may disappear from the final visible set only because it was merged as a genuine duplicate into a stronger surviving record, or because the moderator received an explicit empty record set.

### REVIEW-MOD-004C: Presentation hints are evidence-bound
- Rule: The moderator may normalize or add `presentation.summary`, `presentation.reviewType`, `presentation.impact`, `presentation.evidence`, `presentation.suggestedChange`, `presentation.currentCode`, or `presentation.correctedCode` only when the finding evidence supports the change.
- Rule: The moderator must not attach optimistic remediation prose or corrected code that goes beyond the proven defect.
- Rule: The moderator must preserve any `issueClasses` lineage on surviving records, and when genuine duplicates merge, the surviving record must preserve the union of the absorbed records' `issueClasses` values.

### REVIEW-MOD-005: Final synthesis stays inside the downstream output contract
- Rule: The moderator may decide the final merged-and-normalized moderated finding set from the workflow records it received, but it must not render or restructure the final reader-visible review body.
- Rule: The moderator must not add a new reader-visible section that the prompt or downstream presentation renderer did not authorize.
- Rule: Scope resolution, stage ordering, and final section names remain outside moderator authority even when moderation is enabled.
- Rule: When the moderator receives an explicit empty record set, it must finalize that run as a deterministic empty moderated result rather than treating the absence of findings as a skipped moderation stage.

### REVIEW-MOD-006: Moderator routing must stay explicit
- Rule: Only a prompt that explicitly routes the moderator pass may claim that `review-moderator` ran.
- Rule: Generic code review prompts that route moderator must do so after earlier finding-generation and commentary passes and before final output is frozen.

## Output integration

### REVIEW-MOD-007: Moderator output is final synthesis, not role narration
- Rule: The moderator must not narrate its internal merge or conflict-resolution process in the final review body.
- Rule: Any reader-visible trace of moderator behavior must come through the final normalized finding set or an explicit verification marker authorized by the routed prompt.

### REVIEW-MOD-008: Moderator output may prepare the render-only presentation layer
- Rule: The moderator may enrich surviving workflow findings with deterministic `presentation` hints so the downstream render-only presentation layer can emit the richer legacy review hierarchy without the prompts inventing display semantics ad hoc.
- Rule: Those hints must remain subordinate to the shared handoff record and must not become a second classification system.

<!-- REVIEW-MOD-CONTRACT-EOF -->
