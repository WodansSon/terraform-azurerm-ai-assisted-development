---
description: "Review Terraform AzureRM provider acceptance tests for lifecycle, harness, assertion, generation, configuration, and callback defects."
applyTo: "internal/**/*_test.go"
---

# AzureRM Acceptance-Test Review Rules:

Apply these rules only when changed lines introduce or expose an actionable test defect. Test files also load the shared Go rules; do not duplicate findings about general Go, schema, API, PATCH, identity, or error behavior.

## Evidence And Lifecycle:

- `[TEST-EVID-001]` Follow the nearest same-service acceptance pattern for naming, configuration helpers, assertions, and scenario shape. Flag a new local pattern only when an established provider pattern covers the same scenario.
- `[TEST-WF-002]` Resource acceptance coverage should include `basic`, `requiresImport`, `complete`, `update`, and `ImportStep()` when supported. Omission requires concrete evidence that a scenario is not applicable.
- `[TEST-WF-002A]` Optional prerequisites beyond global Azure authentication and locations belong in a receiver `preCheck(t *testing.T)` called by each affected test. Missing optional prerequisites should skip, not fail, and global checks must not be duplicated.
- `[TEST-WF-003]` A new list resource should have Terraform 1.14 query coverage that provisions multiple resources and exercises the base query plus a narrowed query when supported, unless the list resource has an approved exception.
- `[TEST-WF-004]` Ephemeral resource tests should use the service-local framework pattern, Terraform 1.10 gating, framework provider factories, and the `echo` provider when validating result payloads.
- `[TEST-WF-005]` Provider-defined function tests belong under `internal/provider/function`, use focused framework unit tests and Terraform 1.8 gating, and assert `provider::azurerm::...` output rather than using a resource lifecycle harness.

## Assertions And Validation:

- `[TEST-PATTERN-001]` A basic managed-resource test must prove the object exists in Azure, normally with `check.That(data.ResourceName).ExistsInAzure(r)`.
- `[TEST-PATTERN-002]` Prefer `data.ImportStep()` for broad post-create state validation. Add field assertions only for computed or edge behavior that import cannot prove.
- `[TEST-PATTERN-004]` Managed resources require dedicated `requiresImport` coverage by default, normally through `data.RequiresImportErrorStep`; omission requires evidence that import collision behavior is not applicable.
- `[TEST-PATTERN-005]` Do not add an acceptance test solely for simple property validation already covered by a unit test; require acceptance coverage only for lifecycle, Azure runtime, or provider behavior beyond the validator.
- `[TEST-PATTERN-006]` `CustomizeDiff` constraints need targeted acceptance coverage for invalid paths, normally with `ExpectError`; broader lifecycle scenarios can cover valid paths unless additional assertions are necessary.

## Generated And Embedded Content:

- `[TEST-PATTERN-007]` In `fmt.Sprintf`-based acceptance-test configuration helpers, pass one-use helper calls such as `r.template(data)` directly as arguments instead of assigning them to a local variable first. Introduce a local only when the value is reused or transformed.
- `[TEST-PATTERN-008]` Use one canonical helper type for each Terraform resource or data source across main, list, identity, and generated tests. Do not hand-edit generated identity tests or bridge naming drift with aliases or wrappers.
- `[TEST-PATTERN-010]` Embedded Terraform configuration must use two-space indentation and no tabs. Go formatting and Go tests do not detect invalid indentation inside raw strings.

## Feature Branches And Azure Setup:

- `[TEST-PATTERN-011]` When a provider feature changes CRUD, import, overwrite, or destroy behavior, add one focused acceptance scenario for the non-default branch when feasible. Prepare pre-existing remote state with the appropriate `CheckWithClient...` helper instead of a second Terraform resource targeting the same ID.
- `[TEST-PATTERN-012]` When a `CheckWithClientForResource`, `CheckWithClientWithoutResource`, or `CheckWithClient` callback invokes an Azure polling helper, wrap its callback context with `context.WithTimeout(...)` or `context.WithDeadline(...)` before polling. Use an operation-appropriate deadline and do not confuse quota failures with missing deadlines.

These rules are compact Hosted selections from the testing compliance contract. Shared Go behavior remains owned by the Go instructions.
