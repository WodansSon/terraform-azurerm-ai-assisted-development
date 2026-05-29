# Sanitized Fixture: Committed Review Prefers Direct PR-Files API First

This fixture is synthetic and benchmarks the explicit-PR direct-API-first rule for committed review.

## Scenario

A committed-review run is invoked with an explicit PR number.

The preferred direct non-CLI GitHub PR-files API path for that exact PR number is available.

The historical failure mode is that review starts with active or viewed PR metadata tools, hits summary-only output or a forbidden spill-file transport, and detours into fail-closed behavior even though the direct PR-files API path should have been tried first.

## Simplified PR Shape

```text
Invocation:
- /code-review-committed-changes PR 4828

User request:
- Explicit PR number only
```

## Expected Review Behavior

A correct committed review should:

- try the preferred direct non-CLI GitHub PR-files API path first
- avoid starting explicit-PR scope resolution with summary-only PR metadata tools
- avoid detouring into spill-file-driven fail-closed behavior while the direct PR-files path remains available

## Expected Must-Catch Outcomes

- `direct-pr-files-api-first-choice`

## Expected Must-Not-Flag Outcomes

- `metadata-tools-before-direct-pr-files-api`
