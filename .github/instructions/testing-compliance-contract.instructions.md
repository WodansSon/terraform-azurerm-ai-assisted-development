---
applyTo: "internal/**/*_test.go"
description: "Shared testing compliance contract (single source of truth) used by the acceptance-testing skill and test routing."
---

# Testing Compliance Contract

This file is the single source of truth for test implementation compliance in this repository.

## Consumers

Testing consumers MUST follow this contract:

- Consumer: `.github/skills/acceptance-testing/SKILL.md`
  - Role: Implementer
  - Command: `/acceptance-testing`
  - Requires EOF Load: yes
  - Goal: write or troubleshoot acceptance tests under `internal/**/*_test.go` while applying `TEST-*` rules.

- Consumer: `.github/instructions/ai-skill-routing-tests.instructions.md`
  - Role: Router
  - Requires EOF Load: no
  - Goal: route acceptance-test work through the testing contract and acceptance-testing skill.

## Canonical sources of truth (precedence)

Use these sources with the following roles:

- Current workspace contributor guidance
  - `.github/copilot-instructions.md`
- This contract
  - Authoritative for testing compliance, precedence, and core `TEST-*` rules in this repository.
- Target-provider contributor guidance, when present in the workspace or explicitly fetched as evidence
  - `contributing/README.md`
  - `contributing/topics/**/*.md`

Conflict resolution:

- This contract is authoritative for test implementation compliance in this repository.
- Current workspace contributor guidance is authoritative for repo-specific expectations that affect test behavior or execution safety.
- Target-provider contributor guidance is the baseline reference when workspace evidence is insufficient, but this contract may be stricter to reduce drift and ambiguity.
- If target-provider contributor guidance adds or tightens a testing standard, update this contract so coverage is preserved.
- If a companion testing guide differs from this contract, follow this contract and update the companion guide to re-align.

## Detailed companion guidance

These files provide worked examples, testing patterns, and specialized heuristics. They are companion guidance, not an independent compliance layer:

- `.github/instructions/testing-guidelines.instructions.md`

## Rule IDs

Rules are identified by stable IDs so the skill and routing layer can reference the same requirements without drifting.

ID format:
- `TEST-<AREA>-<NNN>`

Areas:
- `EVID` = evidence and verification guardrails
- `WF` = testing workflow expectations
- `RUN` = safe test execution guidance
- `PATTERN` = acceptance test patterns and assertions

## Evidence hierarchy

When a testing claim affects required test shape, execution safety, or assertion strategy, use this evidence order:

1. Current workspace contributor guidance and this contract
2. Existing nearby `_test.go` implementations under `internal/**`, especially same-service tests
3. Provider implementation behavior under test when assertion strategy depends on schema or CRUD behavior
4. Target-provider contributor guidance when present

If evidence is missing for a behavior-changing testing claim, do not guess.

---

# Contract Rules

## Evidence and verification

### TEST-EVID-001: Do not invent acceptance patterns
- Rule: Do not invent new acceptance-test structure when an existing provider test pattern already covers the scenario.
- Rule: Use nearby same-service tests as the primary pattern source for test naming, configuration helpers, assertion style, and scenario selection.

## Workflow

### TEST-WF-001: Prefer narrow, scenario-focused test updates
- Rule: Add only the smallest set of acceptance-test scenarios needed to validate the changed behavior.
- Rule: Do not add broad or redundant test coverage when existing `basic`, `requiresImport`, `update`, or import patterns already cover the behavior acceptably.

## Execution safety

### TEST-RUN-001: Treat acceptance tests as real Azure activity
- Rule: Acceptance tests create real Azure resources and may incur cost.
- Rule: Prefer narrow test runs and avoid recommending full-suite runs when a single targeted `-run` scope will validate the change.

## Test patterns

### TEST-PATTERN-001: Basic acceptance tests should prove existence
- Rule: In a basic acceptance test, the primary check should prove the object exists in Azure, typically via `check.That(data.ResourceName).ExistsInAzure(r)` when that pattern fits.

### TEST-PATTERN-002: Prefer ImportStep for broad validation
- Rule: Prefer `data.ImportStep()` for broad post-create validation when import is supported.
- Rule: Add extra assertions only when import cannot validate the behavior you need to prove.

### TEST-PATTERN-003: Add requiresImport coverage only when it adds value
- Rule: Add `requiresImport` coverage when the resource pattern and provider conventions make it relevant.
- Rule: Do not add `requiresImport` mechanically when it does not improve confidence in the changed behavior.

<!-- TESTING-CONTRACT-EOF -->
