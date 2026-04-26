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

## Rule provenance

Some rules in this contract come from published upstream standards, while others are inferred from repeated provider testing patterns or added locally to reduce drift.

Use the following provenance labels when a rule needs extra source clarity:

- `Published upstream standard`: explicitly documented by upstream contributor or provider testing guidance.
- `Inferred maintainer convention`: not clearly codified upstream, but supported by repeated provider test patterns or accepted maintainer guidance.
- `Local safeguard`: a repository-local rule added to reduce ambiguity, drift, or under-specified test coverage.

Provenance rollout is incremental. New rules and touched ambiguous rules should include provenance notes first; older rules may be backfilled over time.

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

### TEST-WF-002: Resource acceptance tests should cover the core lifecycle by default
- Rule: For resource acceptance tests, the default expected matrix is `basic`, `requiresImport`, `complete`, and `update`, plus import validation when import is supported.
- Rule: Only omit one of those scenarios when the resource behavior or provider pattern gives a concrete reason that the scenario is not applicable.
- **Provenance**: Published upstream standard.
- **Evidence**:
  - Upstream contributor guidance in `hashicorp/terraform-provider-azurerm/contributing/topics/reference-acceptance-testing.md` under `Which Tests are Required?`
  - Upstream contributor guidance in `hashicorp/terraform-provider-azurerm/contributing/topics/guide-new-resource.md` Step 6 and Step 7 examples

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

### TEST-PATTERN-003: Complete tests should cover the full supported shape when needed
- Rule: Include a `complete` acceptance test for resource scenarios so the broader supported configuration surface is exercised alongside `basic` and `update` coverage.
- Rule: Only omit `complete` coverage when there is concrete evidence that the resource shape does not warrant a distinct complete scenario.
- **Provenance**: Local safeguard.
- **Evidence**:
  - Existing guidance in `.github/instructions/testing-guidelines.instructions.md` listing `Complete Test` in the essential resource-test set
  - Existing provider test organization guidance in `.github/instructions/testing-guidelines.instructions.md` that orders success scenarios around `basic`, `update`, and related lifecycle coverage

### TEST-PATTERN-004: RequiresImport coverage is part of the default resource test matrix
- Rule: Include `requiresImport` coverage for resources by default, typically using `data.RequiresImportErrorStep` and a dedicated `requiresImport` config builder.
- Rule: Only omit `requiresImport` coverage when there is concrete evidence that the resource pattern makes it not applicable.
- **Provenance**: Published upstream standard.
- **Evidence**:
  - Upstream contributor guidance in `hashicorp/terraform-provider-azurerm/contributing/topics/reference-acceptance-testing.md` under `Which Tests are Required?`
  - Upstream contributor guidance in `hashicorp/terraform-provider-azurerm/contributing/topics/reference-acceptance-testing.md` under `Example - Resource - Requires Import`

### TEST-PATTERN-005: Do not add acctests for simple property validation when unit tests already cover it
- Rule: Do not add an acceptance test only to prove simple property validation behavior when that validation is already covered adequately by a unit test.
- Rule: Prefer unit tests for property-validator coverage unless there is concrete evidence that an acceptance test is needed to prove behavior not exercised at the unit-test level.
- **Provenance**: Inferred maintainer convention.
- **Evidence**:
  - Maintainer review guidance in `hashicorp/terraform-provider-azurerm` PR `#31957` comment `discussion_r3116940446`: `we don't normally add acctests for property validation and this is covered in the unit test already`
  - Existing testing guidance in `.github/instructions/testing-guidelines.instructions.md` already distinguishes targeted validation/error scenarios from broader lifecycle acceptance coverage

### TEST-PATTERN-006: Add acctests for CustomizeDiff logic so validation behavior is not left untested
- Rule: Add acceptance-test coverage for CustomizeDiff logic that enforces invalid field combinations, Azure-specific cross-field constraints, or other provider validation behavior that would otherwise be untested.
- Rule: Use targeted `ExpectError` acceptance scenarios for invalid CustomizeDiff paths, while relying on the broader `basic`, `update`, `complete`, and import scenarios for the corresponding success paths unless extra assertions are needed.
- **Provenance**: Local safeguard.
- **Evidence**:
  - Existing guidance in `.github/instructions/testing-guidelines.instructions.md` under `CustomizeDiff Testing` says invalid field combinations should be covered with acceptance tests and notes that success scenarios are usually covered by the broader lifecycle test set
  - Existing local testing guidance explains that CustomizeDiff prevents invalid Azure API calls and is therefore regression-prone if left unexercised

<!-- TESTING-CONTRACT-EOF -->
