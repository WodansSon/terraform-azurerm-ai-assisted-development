# Sanitized Fixture: Local Review For New Resource Companion Coverage

This fixture is derived from a real new-resource review pattern, but the final artifact is sanitized and does not retain live PR identity.

## Scenario

A local change adds a brand-new resource under `internal/services/example/` and registers it, but the change does not include the rest of the now-mandatory companion workflow.

The historical failure mode is that review focuses only on the base resource implementation and misses the missing companion artifacts.

## Simplified Change Shape

```text
Added:
- internal/services/example/example_resource.go
- internal/services/example/registration.go

Missing:
- internal/services/example/example_resource_list.go
- internal/services/example/example_resource_list_test.go
- website/docs/list-resources/example.html.markdown
```

## Expected Review Behavior

A correct local code review should:

- Activate the Go implementation review scope rules
- Apply the new-resource workflow requirements from the implementation and testing guidance
- Flag the missing companion artifacts as a review issue
- Explicitly mention the missing list-resource docs under `website/docs/list-resources/`
- Avoid treating the docs as optional when no explicit maintainer-reviewed exception path is present

## Expected Must-Catch Outcomes

- `missing-new-resource-companions`

## Expected Must-Not-Flag Outcomes

- `list-resource-docs-optional`
