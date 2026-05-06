# Sanitized Fixture: Committed Review For Vendored-Heavy Scope

This fixture is synthetic and intentionally benchmarks a local safeguard rather than an upstream contributor rule.

## Scenario

A pull request updates an SDK dependency and regenerates vendored files, leaving only a small non-vendored control-surface change in the actionable review scope.

The historical failure mode is that generic review either:

- enumerates every vendored path and buries the useful findings in noise, or
- tells the contributor to edit vendored files directly even though the actionable source is the dependency or generation input.

## Simplified Change Shape

```text
Modified:
- go.mod
- go.sum
- internal/services/example/client/client.go

Vendored churn:
- vendor/github.com/hashicorp/go-azure-sdk/resource-manager/example/2026-01-01/widgets/client.go
- vendor/github.com/hashicorp/go-azure-sdk/resource-manager/example/2026-01-01/widgets/model_widget.go
- vendor/modules.txt
```

## Expected Review Behavior

A correct committed review should:

- disclose only the count of skipped vendored files, not list every vendored path
- explicitly say the diff is vendored-heavy so sparse actionable findings are easy to interpret
- avoid raising findings that tell the contributor to edit files under `vendor/**` directly
- focus any actionable commentary on the non-vendored control surface instead

## Expected Must-Catch Outcomes

- `vendored-heavy-scope-callout`

## Expected Must-Not-Flag Outcomes

- `edit-vendored-files-directly`
