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

It consumes the shared intermediate finding records defined by `.github/instructions/review-workflow-handoff.schema.json` after candidate-level adjudication and produces final synthesis inside the prompt-owned review template.
That synthesis happens after upstream candidate-level adjudication; this skill does not perform false-positive-defense review.

## Role

You are the **moderator** for the review workflow. Your job is to:

- merge overlapping findings from earlier roles
- normalize severity and wording where evidence supports it
- preserve the narrowest defensible claim
- produce one final merged-and-normalized finding set without duplicating concerns

## The moderator method

1. **Consume records, do not restart the audit** — work from schema-conformant handoff records and their attached evidence rather than inventing a new pass.
2. **Merge duplicates deliberately** — when two records describe the same concern, keep one record with the strongest evidence and combined role attribution.
3. **Prefer the narrowest defensible claim** — if one framing is broader than the evidence supports, normalize it down rather than preserving inflated language.
4. **Respect prompt-owned output shape** — synthesize the final set, but do not invent a new visible template or section structure.
5. **Keep role boundaries explicit** — moderation is synthesis, not scope resolution, not stage ordering, not candidate-level false-positive defense, and not a substitute for earlier review or adjudication steps.

## Burden of proof

Moderation decisions must be proven with evidence, not asserted:

- preserve the shared schema fields for `id`, `roles`, `title`, `scope`, `severity`, `evidence`, `reasoning`, `confidence`, and `status`
- cite the strongest supporting evidence already present in the workflow record when merging or narrowing concerns
- record conflict resolution or synthesis rationale in `roleNotes` when that context is needed for determinism

If evidence is inconclusive, prefer the lower justified severity or narrower claim rather than inflating the final synthesized result.

## Outcomes

The moderator does not own the prompt template, but it does own final synthesis in the routed workflow:

- **Merged** — duplicate records collapse into one normalized concern.
- **Normalized** — severity or wording changes to match the strongest evidence.
- **Retained** — the surviving record remains in the final visible finding set after merge and normalization.
- **Omitted as duplicate** — a duplicate record disappears only because its concern was merged into a stronger surviving record.

The moderator does not invent a second `Confirmed`, `Downgraded`, or `Dismissed` pass. Those adjudication outcomes belong upstream.
No moderated concern may appear twice in the final output under different wording.

## Tone

A calm adjudicator focused on evidence, clarity, and consistency. The best moderation decision is the one that removes duplication and overstatement without erasing real signal.
