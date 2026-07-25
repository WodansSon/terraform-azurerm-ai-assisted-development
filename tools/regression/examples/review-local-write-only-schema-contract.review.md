# Code Review: invalid write-only schema relationships

## CHANGE SUMMARY

- **Files Changed**: 1 modified file
- **Type**: unstaged local changes
- **Scope**: adds a write-only sensitive field and its version trigger to an existing Plugin SDK resource

## FILES CHANGED

**Modified Files:**

- `internal/services/example/example_service_resource.go`

## PRIMARY CHANGES ANALYSIS

The change adds `password_wo` and `password_wo_version`. The reciprocal `RequiredWith` relationship is correct, but the write-only field targets the version trigger in `ConflictsWith`, and the trigger has no positive-integer validation.

## STANDARDS CHECK

- **Scope Rule**: `REVIEW-SCOPE-005`
- **Implementation Rule**: `IMPL-SCHEMA-017`
- **Guidance Applied**: implementation contract and schema-pattern companion

## AZURERM LINTER

- **Status**: No issues
- **Run Scope**: filtered local-diff scope
- **Issue Count**: 0

## ISSUES

### High: Correct the write-only field conflict target

`password_wo` both requires and conflicts with `password_wo_version`, so no valid write-only configuration can satisfy the schema. Its `ConflictsWith` must target the original `password` field, while the original field continues to conflict with `password_wo`, as required by `IMPL-SCHEMA-017`.

### Medium: Reject version trigger value zero

`password_wo_version` is missing `ValidateFunc: validation.IntAtLeast(1)`. Plugin SDK v2 persists an omitted optional integer as `0`, so accepting a configured zero prevents the trigger from tracking write-only updates reliably. Add the positive-integer validator required by `IMPL-SCHEMA-017`.

## OBSERVATIONS

- The reciprocal `RequiredWith` declarations are already correct and do not need changes.
- The fixture establishes the CRUD, state, lifecycle-test, and documentation paths as correct and unchanged.

## OVERALL ASSESSMENT

The write-only schema should not merge until the conflict target and version validation are corrected.
