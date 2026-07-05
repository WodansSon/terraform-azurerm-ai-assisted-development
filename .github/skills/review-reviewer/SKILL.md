---
name: review-reviewer
description: Primary review pass for code reviews — inspect the in-scope change-set, apply mandatory issue-class checks, emit schema-conformant handoff records, and freeze the pre-routed findings set for later review roles. Use when a code-review workflow needs the concrete reviewer behavior to live in a reusable skill instead of inside prompt Step 5.
---

# Review Reviewer (primary review pass)

## Canonical sources of truth (contract-driven)

When running the reviewer pass, use these sources in this order:

- `.github/instructions/code-review-compliance-contract.instructions.md`
  - authoritative for review flow, classification, evidence handling, handoff requirements, and mandatory issue-class behavior
- `.github/instructions/review-linter-compliance-contract.instructions.md`
  - authoritative when Step 4 produced linter scope or linter findings for provider Go or test files
- `.github/instructions/docs-compliance-contract.instructions.md`
  - authoritative for documentation compliance whenever `website/docs/**/*.html.markdown` files are in the current review scope
- `.github/instructions/testing-compliance-contract.instructions.md`
  - authoritative for testing compliance whenever `internal/**/*_test.go` files are in the current review scope
- `.github/instructions/review-coverage-matrix.schema.json`
  - authoritative for the coverage matrix shape and linkage-state containers the primary pass must keep current
- file-scoped instructions and companion guidance loaded for the in-scope files under `REVIEW-SCOPE-*`
  - authoritative for scoped implementation, docs, testing, and provider-specific expectations once the prompt has loaded them

Do not treat this skill as a second independent rule source. The contracts and scoped instructions own the rules; this skill owns the reusable reviewer method.
Do not treat this skill as a moderator, architect, skeptic, advocate, or presentation pass. It is the primary reviewer only.

## Mandatory: read the entire skill

Before applying this skill, read this file to EOF.

## Preflight checklist

Before running the reviewer pass, complete this checklist:

- [ ] I have read this skill to EOF.
- [ ] I have loaded `.github/instructions/code-review-compliance-contract.instructions.md` to EOF and applied the relevant `REVIEW-*` rules.
- [ ] I have the resolved review scope and a schema-conformant coverage matrix that has already passed the prompt-owned completion gate.
- [ ] If provider Go or test files are in scope, the linter applicability decision for this run is already known from the prompt's linter step.
- [ ] If `website/docs/**/*.html.markdown` files are in scope, I have loaded `.github/instructions/docs-compliance-contract.instructions.md` to EOF and am applying exact `DOCS-*` rules to those docs files.
- [ ] If `internal/**/*_test.go` files are in scope, I have loaded `.github/instructions/testing-compliance-contract.instructions.md` to EOF and am applying exact `TEST-*` rules to those test files.
- [ ] I am producing structured handoff records and updated linkage state, not final reader-visible review output.

If preflight is incomplete, do not run the reviewer pass.

## Verification (assistant response only)

When (and only when) this skill is invoked, the assistant MUST append the following line to the end of the assistant's final response:

Skill used: review-reviewer

Rules:
- Do NOT write this marker into any repository file.
- If multiple skills are invoked, each skill should append its own `Skill used: ...` line.
- Do NOT emit the marker in intermediate/progress updates; only in the final response.

## Scope

This skill is the reusable primary reviewer technique orchestrated inside:

- `.github/prompts/code-review-local-changes.prompt.md`
- `.github/prompts/code-review-committed-changes.prompt.md`

It runs after scope resolution, coverage-matrix build and validation, and the prompt-owned linter step when applicable.
It produces the frozen pre-routed findings set for later architect, skeptic, advocate, moderator, and presentation stages.

## Role

You are the **reviewer** for the change-set. Your job is to:

- inspect the full in-scope change-set
- walk the deterministic coverage matrix in its established order
- apply the mandatory issue-class checks required by the shared review contract
- for variant-constrained managed surfaces, complete ownership-boundary and lifecycle-symmetry checks before freezing any later secondary concern on that same surface
- apply the docs compliance contract when docs files are in scope
- apply the testing compliance contract when acceptance-test files are in scope
- emit schema-conformant `REVIEW-HANDOFF-*` records immediately when evidence-backed concerns are found
- keep row-level and matrix-level linkage state current while the review is happening
- freeze a complete reviewer findings set for routed downstream roles

## The reviewer method

- **Consume scope and matrix, do not improvise route order** — use the resolved change-set and the validated coverage matrix as the review surface.
- **Walk required rows and control windows in matrix order** — inspect each required surface, overlap surface, and lifecycle or control window before freezing findings.
- **Apply mandatory issue-class checks deliberately** — for provider surfaces, execute the contract-owned issue-class families rather than relying on ad hoc intuition.
  - Use `REVIEW-COORD-003A`, `REVIEW-COORD-004`, and the related `REVIEW-HANDOFF-*` requirements from the shared contract to keep first-pass ownership checks, mandatory issue-class execution, and immediate record emission aligned, and stamp emitted records with the exact schema `issueClasses` tokens that apply.
  - For variant-constrained managed surfaces, inspect importer, ID validation, lookup, and read first to decide whether foreign variants can be accepted or hydrated into state. If they can, emit the ownership-boundary record immediately instead of continuing to secondary findings.
  - Treat a generic ID type, generic ID validator, or generic lookup helper plus a later read-time or update-time discriminator check as sufficient evidence that foreign variants can enter the lifecycle unless the earlier path already enforced the discriminator.
  - When that generic-resolution-plus-late-discriminator pattern is present, classify the `ownership-overlap` record as an `issue`, not an `observation`; this is a present ownership-boundary defect rather than a mere architectural risk.
  - After the ownership-boundary outcome is known, inspect update and delete against that same foreign-variant path. If later lifecycle windows reject, mutate inconsistently, or still delete the foreign variant, emit a separate lifecycle-symmetry record before moving on to metadata drift, update-shape, acceptance-matrix, or docs-example checks.
  - If read or update performs the discriminator guard only after generic resolution, verify that delete mirrors that guard; if it does not, emit the lifecycle-symmetry record even when the current tests do not include an explicit foreign-variant fixture.
  - When delete can still mutate or destroy the foreign variant after read or update already applies the discriminator guard, classify the `mode-gating-symmetry` record as an `issue`, not an `observation`.
  - After the ownership and lifecycle checks, inspect the update path for broader request-shape or residual-state risk. If current-run evidence shows a `PUT` versus `PATCH` mismatch or another broader update request shape that may preserve, replace, or broaden unspecified fields, emit a separate `patch-residual-state` concern instead of folding it into ownership, lifecycle, or metadata drift.
  - When current-run evidence proves only that broader update-shape or residual-state risk and not concrete destructive harm, classify the `patch-residual-state` record as an `observation`, not an `issue`.
  - For user-managed map or object arguments, inspect read and import round-tripping after the ownership and lifecycle checks. If helper logic can repopulate undeclared API-returned keys or values when prior configured state is absent, treat that as an `optional-state-drift` concern rather than folding it into a generic metadata note.
  - When an acceptance test already ignores a user-managed field during import verification, treat that import-ignore exception as affirmative evidence to inspect for `optional-state-drift`; do not assume the ignore is harmless without proving the field can still round-trip cleanly.
  - When current-run evidence shows that a user-managed map or object field can round-trip service-added or undeclared values back into state, classify the `optional-state-drift` record as an `issue`, not an `observation`.
  - Apply exact `DOCS-*` rules for in-scope docs files and exact `TEST-*` rules for in-scope test files instead of treating those files as generic support evidence only.
  - When changed reference docs are in scope alongside implementation or acceptance-test files, inspect changed examples for implementation-backed or acceptance-test-backed casing, field-key, map-key, value, or shape mismatches and emit a separate docs-example correctness record with the exact supporting `DOCS-*` rule instead of folding that evidence into a Go-only finding.
  - If the docs and a local acceptance test both show the same Terraform argument as a map or object literal, compare the keys directly and treat spelling/casing drift on that same argument as a docs-example correctness defect.
  - For brand-new managed resources with acceptance coverage, treat the absence of a distinct `complete` scenario as its own `acceptance-test-matrix` concern when the resource exposes optional metadata, multiple supported shapes, or other broader supported configuration beyond the narrow `basic` and `update` paths.
  - Do not treat category-specific, subtype-specific, or other narrower targeted scenarios as satisfying the required `complete` scenario when the broader supported shape still lacks one.
- **Emit handoff records immediately** — when an evidence-backed concern is found, create or enrich a schema-conformant `REVIEW-HANDOFF-*` record at once and update `emittedRecordIds` plus `issueClassToRecordIds` before moving on.
  - Use the exact schema token `ownership-overlap` for foreign-variant ownership-boundary concerns, `mode-gating-symmetry` for lifecycle-window inconsistency concerns, `patch-residual-state` for update-shape or residual-state concerns, `optional-state-drift` for omitted-config drift concerns, `acceptance-test-matrix` for missing minimum new-resource lifecycle coverage, and `docs-example-correctness` for exact `DOCS-*` example mismatches.
- **Keep distinct concerns separate** — when multiple issue classes find different concerns, preserve each one as its own record unless they are genuinely the same underlying concern.
  - Do not let one stronger concern satisfy a second applicable mandatory issue class, and do not collapse mixed implementation-versus-docs concerns when the current run supports separate records.
  - Ownership-boundary, lifecycle-symmetry, patch-residual-state, optional-state-drift, docs-example correctness, and missing-complete-scenario concerns should remain separate when the current run supports each of them, even if one metadata or import symptom appears earlier in the same file family.
- **Freeze the reviewer output for routed roles** — hand off a complete findings set plus updated linkage state; do not perform advocate, moderator, or presentation work here.

## Burden of proof

Reviewer findings must be proven with evidence, not asserted:

- cite the changed files, surrounding code, tests, or docs that show the concern
- preserve the shared handoff fields for `id`, `roles`, `title`, `scope`, `severity`, `evidence`, `reasoning`, `confidence`, `classification`, and `visible`
- keep `emittedRecordIds` and `issueClassToRecordIds` current as concerns are discovered rather than reconstructing them later
- preserve evidence-backed non-blocking concerns as `observation` records instead of dropping them because another issue is stronger
- on variant-constrained surfaces, follow the contract-owned first-pass ownership and lifecycle requirements before treating later secondary findings as the lead result
- apply exact `DOCS-*` and `TEST-*` rules only after the prompt has loaded the relevant docs and testing contracts for the current run
- preserve separate records whenever the shared review contract and loaded scoped contracts make those concerns independently applicable
- when a changed docs example and a changed implementation path both have evidence-backed defects, preserve both records rather than letting the implementation defect absorb the docs-example concern

If evidence is inconclusive, choose the lower justified classification under the shared review contract rather than overstating the concern.

## Outcomes

The reviewer pass does not own final rendering or final moderation. It produces:

- **Observation record** — a schema-conformant non-blocking reviewer finding with `classification=observation` and `visible=true`
- **Issue record** — a schema-conformant reviewer finding with `classification=issue` and `visible=true`
- **Updated linkage state** — row-level and matrix-level `emittedRecordIds` and `issueClassToRecordIds` that prove the reviewer serialized its findings as it worked
- **Frozen reviewer findings set** — the complete current-run reviewer output handed to later routed roles

## Tone

Concrete, evidence-first, and disciplined. The best reviewer pass is broad enough to catch the whole change-set and strict enough to serialize every real concern without collapsing unrelated issue classes together.
<!-- REVIEW-REVIEWER-SKILL-EOF -->
