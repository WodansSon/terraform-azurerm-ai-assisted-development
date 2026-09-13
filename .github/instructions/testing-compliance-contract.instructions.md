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

### TEST-WF-002A: Use resource-specific `preCheck` helpers for optional prerequisites
- Rule: When an acceptance test has prerequisites beyond the global Azure auth and location requirements, add a receiver method named `preCheck(t *testing.T)` on the test helper struct and call it near the start of each affected `TestAcc...`.
- Rule: Use `t.Skip(...)` or `t.Skipf(...)` for optional or environment-specific prerequisites that are not universally available, rather than failing the test with `t.Fatalf(...)`.
- Rule: Keep `preCheck` close to the tests that call it, commonly after the `TestAcc...` functions and before the `Exists` or `Destroy` helpers.
- Rule: Do not duplicate the framework's global Azure-auth pre-check inside resource-specific `preCheck` helpers.

### TEST-WF-003: New resources with list resources should include list query coverage
- Rule: When adding a new resource that includes a list resource, add list-resource acceptance coverage using Terraform 1.14 query tests.
- Rule: The list-resource test should provision multiple resources, exercise the base list query, and cover at least one narrowed query path when the list configuration supports it.
- Rule: Only omit list-resource acceptance coverage when the list resource itself is legitimately omitted under the maintainer-reviewed exception path.

### TEST-WF-004: Ephemeral resource tests should use the framework ephemeral test pattern
- Rule: Acceptance tests for provider ephemeral resources should use the service-local `*_ephemeral_test.go` pattern with `acceptance.BuildTestData(t, "ephemeral.azurerm_<name>", ...)`.
- Rule: Ephemeral-resource acceptance tests should gate on Terraform 1.10 support and use the framework provider factories required by the upstream ephemeral pattern.
- Rule: When the test needs to assert the ephemeral result payload, prefer the `echo` provider pattern with config-state checks rather than inventing a custom assertion mechanism.

### TEST-WF-005: Provider-defined functions should use focused framework unit tests
- Rule: Provider-defined function tests should live under `internal/provider/function/*_test.go` and use `resource.UnitTest` with framework provider factories.
- Rule: Provider-defined function tests should gate on Terraform 1.8 support and prove outputs from `provider::azurerm::<name>(...)` calls rather than inventing a resource-style lifecycle harness.

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
- Rule: Do not treat category-specific, subtype-specific, or otherwise narrower targeted scenarios as satisfying `complete` coverage when the resource still exposes a broader supported shape.
- Rule: When a new managed resource exposes optional metadata, optional blocks, or multiple supported shapes beyond the narrow success path, that broader shape normally warrants a distinct `complete` scenario.

### TEST-PATTERN-004: RequiresImport coverage is part of the default resource test matrix
- Rule: Include `requiresImport` coverage for resources by default, typically using `data.RequiresImportErrorStep` and a dedicated `requiresImport` config builder.
- Rule: Only omit `requiresImport` coverage when there is concrete evidence that the resource pattern makes it not applicable.

### TEST-PATTERN-005: Do not add acctests for simple property validation when unit tests already cover it
- Rule: Do not add an acceptance test only to prove simple property validation behavior when that validation is already covered adequately by a unit test.
- Rule: Prefer unit tests for property-validator coverage unless there is concrete evidence that an acceptance test is needed to prove behavior not exercised at the unit-test level.

### TEST-PATTERN-006: Add acctests for CustomizeDiff logic so validation behavior is not left untested
- Rule: Add acceptance-test coverage for CustomizeDiff logic that enforces invalid field combinations, Azure-specific cross-field constraints, or other provider validation behavior that would otherwise be untested.
- Rule: Use targeted `ExpectError` acceptance scenarios for invalid CustomizeDiff paths, while relying on the broader `basic`, `update`, `complete`, and import scenarios for the corresponding success paths unless extra assertions are needed.

### TEST-PATTERN-007: Inline one-use helper arguments in fmt.Sprintf-based config builders
- Rule: In acceptance-test helper functions that return `fmt.Sprintf(...)` configuration strings, do not assign one-use helper results such as `template := r.template(data)` or `config := r.basic(data)` to a local variable only to pass them immediately into `fmt.Sprintf(...)`.
- Rule: Pass those one-use helper calls directly as `fmt.Sprintf(...)` arguments instead, for example `r.template(data)` or `r.basic(data)` inline.
- Rule: Only introduce a local variable for a nested helper result when it is reused, materially improves readability, or is needed for additional transformation before formatting.

### TEST-PATTERN-008: Acctest helper struct names must stay canonical across all test variants
- Rule: In acceptance test files under `internal/services/**`, helper struct names for a given Terraform resource or data source must use the canonical generated pattern based on the Terraform name.
- Rule: For each Terraform resource or data source surface, use one canonical helper type and keep it stable across all related acceptance test files.
- Rule: If the surface already has an established canonical helper type, preserve and reuse that same type across all related acceptance tests and generated identity tests.
- Rule: For new surfaces that do not yet have an established canonical helper type, prefer `ToCamel(x)Resource` for resources and `ToCamel(x)DataSource` for data sources.
- Rule: That canonical helper type should stay the same across all acceptance test variants for the same Terraform surface, including the main resource test file, list-test files, identity-related tests, and any other acceptance test file that instantiates the helper.
- Rule: Generated identity tests under `*_identity_gen_test.go` must use that same canonical helper type directly.
- Rule: For new surfaces that use generated identity tests, the canonical helper type must match the helper name emitted by the resource-identity generator for that Terraform resource name unless the shared generator itself is intentionally being changed.
- Rule: Before finalizing helper-type names for a new resource with Resource Identity support, run the narrow `go generate` command for that resource to verify the generated helper-name casing and prevent `*_resource_identity_gen_test.go` drift.
- Rule: When a surface already has an established canonical helper type in hand-written acceptance tests, preserve that helper type across all related tests and ensure generated identity tests align with it. Do not introduce alternate helper names for branding or file-local convenience.
- Rule: Do not preserve Azure product branding or alternate casing in acceptance-test helper names if that causes `go generate` to rewrite `*_resource_identity_gen_test.go`.
- Rule: If there is a mismatch between hand-written acceptance tests and generated identity tests, resolve it by aligning the canonical helper type or by making an intentional shared generator change. Do not hand-edit the generated identity test.
- Rule: Do not introduce variant-specific helper types such as `SomethingIdentityResource` or other alternate names merely because the test lives in a different file or generated identity file.
- Rule: Do not rely on adapter methods, alias types, or wrapper structs to bridge helper-type drift to generated identity tests.
- Rule: Keep helper-type naming stable across all acceptance tests and generated identity tests so `go generate` produces no diff and Generation Check stays green.

### TEST-PATTERN-009: Data source tests should prefer the associated resource complete config by default
- Rule: When a data source acceptance test needs managed resources as setup and the associated resource exposes a `complete(data)` helper, prefer that helper as the default setup shape.
- Rule: Use `basic(data)` or another scenario-specific associated resource helper instead when no `complete(data)` helper exists, when the test is intentionally narrow, or when `complete(data)` would introduce unrelated setup, noise, or coupling.
- Rule: Do not infer that every data source test must use `complete(data)`; the default preference does not remove author choice for scenario-specific setup.
- Rule: Do not rewrite a data source test away from `complete(data)` or another broader helper when the scenario genuinely depends on the fuller associated resource shape.

### TEST-PATTERN-010: Embedded Terraform in acceptance tests must use repository-valid indentation
- Rule: In embedded Terraform configuration blocks inside `*_test.go` files, indent configuration lines with two spaces and never tabs.
- Rule: When editing Terraform heredocs in acceptance tests, preserve the surrounding file's Terraform formatting and treat tab-indented configuration lines as invalid, since they can fail the repository's acceptance-test formatting checks.
- Rule: Do not rely on Go linting or Go test execution to detect formatting issues inside embedded Terraform configuration strings.

### TEST-PATTERN-011: Provider feature-flagged CRUD branch coverage
- Rule: When a provider-level `features` setting changes create, update, delete, import, overwrite, or destroy semantics, add targeted acceptance-test coverage for the non-default branch when feasible.
- Rule: Prefer one focused acceptance test for the shared branch behavior rather than duplicating equivalent coverage across every sibling resource, unless the resources have materially different behavior.
- Rule: When exercising that branch requires a pre-existing remote object, use existing client callback patterns such as `CheckWithClientForResource`, `CheckWithClientWithoutResource`, or `CheckWithClient`, as appropriate, to prepare the remote object outside Terraform before applying the feature-enabled configuration.
- Rule: Do not model this scenario by introducing a second Terraform-managed resource with the same remote ID merely to trigger the branch, unless the resource pattern specifically requires that shape.

### TEST-PATTERN-012: Callback-based Azure pollers need explicit deadlines in acceptance setup helpers
- Rule: When `CheckWithClientForResource(...)`, `CheckWithClientWithoutResource(...)`, or `CheckWithClient(...)` callbacks call Azure polling helpers such as `CreateOrUpdateThenPoll(...)`, `CreateOrReplaceThenPoll(...)`, `UpdateThenPoll(...)`, or `DeleteThenPoll(...)`, do not pass the provided callback `ctx` directly into the poller.
- Rule: First wrap the callback `ctx` with `context.WithTimeout(...)` or `context.WithDeadline(...)` before calling the poller.
- Rule: Use a timeout appropriate for the setup or mutation operation, commonly 15 to 60 minutes for Azure LRO-style acceptance-test setup.
- Rule: Treat quota-sensitive failures separately from missing-deadline failures; if a service has hard subscription quotas or low service limits, prefer sequential acceptance execution patterns or runner-level `-parallel=1` rather than misclassifying those failures as context-deadline issues.

<!-- TESTING-CONTRACT-EOF -->
