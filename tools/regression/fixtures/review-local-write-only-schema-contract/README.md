# Synthetic Fixture: Local Review For Write-Only Schema Relationships

This fixture is synthetic and sanitized for regression benchmarking.

## Scenario

A local Go change adds a write-only counterpart for an existing sensitive field and pairs it with a version trigger. The `RequiredWith` relationship is already symmetric, but the write-only field conflicts with the required trigger instead of the original sensitive field, and the trigger accepts a configured value of `0`.

The resource's create, update, and read paths already use `pluginsdk.GetWriteOnly(...)` and preserve the version trigger correctly. Existing lifecycle tests and documentation already cover those paths. Only the changed schema below is material to this case.

## Simplified Code Shape

```go
"password": {
	Type:          pluginsdk.TypeString,
	Optional:      true,
	Sensitive:     true,
	ConflictsWith: []string{"password_wo"},
},

"password_wo": {
	Type:          pluginsdk.TypeString,
	Optional:      true,
	WriteOnly:     true,
	RequiredWith:  []string{"password_wo_version"},
	ConflictsWith: []string{"password_wo_version"},
},

"password_wo_version": {
	Type:         pluginsdk.TypeInt,
	Optional:     true,
	RequiredWith: []string{"password_wo"},
},
```

## Expected Review Behavior

A correct local code review should:

- load the implementation contract and schema companion for the changed `internal/**/*.go` file
- cite `IMPL-SCHEMA-017`
- flag `password_wo` for conflicting with `password_wo_version`, which it also requires
- require `password_wo` to conflict with the original `password` field instead
- require `validation.IntAtLeast(1)` on `password_wo_version`
- leave the already symmetric `RequiredWith` relationship alone
- avoid inventing CRUD, state, test, or documentation findings outside the established schema-only defect
- report `azurerm-linter` execution in its dedicated section

## Expected Must-Catch Outcomes

- `write-only-conflicts-with-version-trigger`
- `write-only-version-allows-zero`

## Expected Must-Not-Flag Outcomes

- `symmetric-requiredwith-is-correct`
- `correct-lifecycle-handling-outside-schema-diff`
