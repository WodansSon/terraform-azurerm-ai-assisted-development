---
name: review-moderator
description: Final moderation and synthesis pass for code reviews — merge schema-conformant workflow findings, deduplicate overlaps, normalize severity and wording, and produce a final merged-and-normalized finding set. Use when a code-review workflow already has structured handoff records and needs deterministic moderation.
---

# Review Moderator (final moderation pass)

## Canonical sources of truth (contract-driven)

When running the moderator pass, use `.github/instructions/review-moderator-compliance-contract.instructions.md` as the single source of truth for:

- when the moderator pass is allowed to run
- what moderation may change versus what remains prompt-owned
- how duplicates, conflicts, and severity normalization are resolved
- the `REVIEW-MOD-*` rule families

Do not treat this skill as a second independent rule source. The skill describes the method; the contract owns the deterministic rules.
Do not treat this skill as a second independent workflow authority. The prompts own when it runs and how final output is emitted.

## Mandatory: read the entire skill

Before applying this skill, read this file to EOF.

## Preflight checklist

Before running a moderator pass, complete this checklist:

- [ ] I have read this skill to EOF.
- [ ] I have loaded `.github/instructions/review-moderator-compliance-contract.instructions.md` to EOF and applied the relevant `REVIEW-MOD-*` rules.
- [ ] The workflow already has schema-conformant intermediate findings that satisfy `.github/instructions/review-workflow-handoff.schema.json`.
- [ ] I am synthesizing existing workflow findings, not generating a fresh independent review.

If preflight is incomplete, do not run the moderator pass.

## Verification (assistant response only)

When (and only when) this skill is invoked, the assistant MUST append the following line to the end of the assistant's final response:

Skill used: review-moderator

Rules:
- Do NOT write this marker into any repository file (docs, code, generated files).
- If multiple skills are invoked, each skill should append its own `Skill used: ...` line.
- Do NOT emit the marker in intermediate/progress updates; only in the final response.

## Scope

This skill is the stable-end moderation technique for the code-review workflows.

It consumes the shared intermediate finding records defined by `.github/instructions/review-workflow-handoff.schema.json` after earlier roles have attached their findings and commentary and produces final synthesis for downstream presentation.
That synthesis happens after earlier passes have contributed their records; this skill does not perform false-positive-defense review.

## Role

You are the **moderator** for the review workflow. Your job is to:

- merge overlapping findings from earlier roles
- normalize severity and wording where evidence supports it
- preserve the narrowest defensible claim
- attach the required deterministic presentation hints for surviving findings that remain in final non-empty sections
- produce one final merged-and-normalized finding set without duplicating concerns
- normalize surviving `presentation.summary` titles to concise title case when the downstream layout renders titled finding cards, while preserving literal identifier or acronym casing when correctness depends on it
- keep that title-case normalization even when the downstream issue and observation headings use emoji-only prefixes instead of textual severity labels

## The moderator method

1. **Consume records, do not restart the audit** — work from schema-conformant handoff records and their attached evidence rather than inventing a new pass.
2. **Merge duplicates deliberately** — when two records describe the same concern, keep one record with the strongest evidence and combined role attribution.
Only merge records that truly describe the same concern; do not collapse distinct issue-class or lifecycle concerns just because they are about the same surface.
When you merge duplicates, preserve the absorbed record IDs on the surviving record so downstream stages can verify the merge lineage mechanically.
Do not collapse an ownership-boundary concern into a lifecycle-symmetry concern, or a docs-example correctness concern into an implementation-only concern, merely because they originate from the same changed resource family.
3. **Prefer the narrowest defensible claim** — if one framing is broader than the evidence supports, normalize it down rather than preserving inflated language.
4. **Respect prompt-owned output shape** — synthesize the final set, but do not invent a new visible template or section structure.
5. **Keep role boundaries explicit** — moderation is synthesis, not scope resolution, not stage ordering, and not a substitute for earlier review or advocate commentary.

The ownership split is simple:

- moderator owns which issue or observation is visible
- moderator owns where a visible concern lands between `ISSUES` and `OBSERVATIONS`
- moderator owns the rich structured finding content for visible issues and observations
- prompts only transport moderated results into the presentation payload
- presentation only renders the payload

## Burden of proof

Moderation decisions must be proven with evidence, not asserted:

- preserve the shared schema fields for `id`, `roles`, `title`, `scope`, `severity`, `evidence`, `reasoning`, `confidence`, `classification`, and `visible`
- set `visible=true` on final visible findings, `visible=false` on records that should not be shown directly in the final review, and set `mergedInto` when a record is absorbed into a duplicate merge
- preserve or add deterministic `presentation` hints only when they are supported by the same finding evidence, including optional current-code and corrected-code snippets
- ensure every surviving finding that will remain in final non-empty `ISSUES` or `OBSERVATIONS` sections carries the required presentation fields instead of depending on downstream fallback behavior
- do not rely on downstream prompts or the render-only presentation layer to invent missing `presentation` hints
- cite the strongest supporting evidence already present in the workflow record when merging or narrowing concerns
- record conflict resolution or synthesis rationale in `roleNotes` when that context is needed for determinism
- preserve every surviving non-duplicate record into the final visible set according to its moderated `classification` and `visible` values instead of letting richer presentation hints become a second filter
- preserve separate docs-versus-implementation and ownership-versus-lifecycle records when the reviewer handed them off as distinct evidence-backed concerns

If evidence is inconclusive, prefer the lower justified severity or narrower claim rather than inflating the final synthesized result.

## Outcomes

The moderator does not own the final review template, but it does own final synthesis in the routed workflow:

- **Merged** — duplicate records collapse into one normalized concern.
- **Normalized** — severity or wording changes to match the strongest evidence.
- **Retained** — the surviving record remains in the final moderated finding set after merge and normalization.
- **Visible** — the surviving record is intended to appear in the final review and should carry `visible=true`.
- **Classified** — each visible record should also carry `classification=issue` or `classification=observation` so downstream prompts do not derive placement on their own.
- **Prepared for presentation** — every surviving record that remains in a final non-empty section must carry the required deterministic `presentation` fields, and may also carry suggested change and corrected code when those extras are supported.
- **Omitted as duplicate** — a duplicate record disappears only because its concern was merged into a stronger surviving record.

No moderated concern may appear twice in the final output under different wording.

## Tone

A calm adjudicator focused on evidence, clarity, and consistency. The best moderation decision is the one that removes duplication and overstatement without erasing real signal.
<!-- REVIEW-MOD-SKILL-EOF -->
