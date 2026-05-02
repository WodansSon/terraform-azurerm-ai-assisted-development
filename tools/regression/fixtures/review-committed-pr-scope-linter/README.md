# Sanitized Fixture: Committed Review PR-Scoped Linter Reporting

This fixture is derived from a real committed-review pattern, but the final artifact is sanitized and does not retain live PR identity.

## Scenario

A committed review runs against an explicit pull request context with a known PR number and a bounded diff.

The changed provider Go file is modeled as `internal/services/example/example_resource.go`.

The benchmarked behavior is not about a deep implementation bug. It is about whether the review correctly reports the committed-review linter execution path for the PR-scoped diff instead of guessing or fabricating scope details.

## Simplified PR Shape

```text
PR Number: 4821
Changed Files:
- internal/services/example/example_resource.go
```

## Expected Review Behavior

A correct committed review should:

- Recognize that explicit PR context exists and keep the review in committed-review mode
- Report that `azurerm-linter` was run for the PR-scoped diff rather than a local-diff or full-repo scope
- Include the required `AZURERM LINTER` reporting section in the human-readable review body
- Avoid inventing a pull request number from branch naming or diff text when the fixture does not supply one

## Expected Must-Catch Outcomes

- `linter-scope-reporting`

## Expected Must-Not-Flag Outcomes

- `invented-pr-number`
