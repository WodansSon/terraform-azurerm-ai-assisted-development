# Sanitized Fixture: Committed Review Does Not Auto-Fallback To gh

This fixture is synthetic and benchmarks the opt-in-only CLI fallback rule for committed review.

## Scenario

A committed-review run is invoked with an explicit PR number, but the user does not request CLI fallback and does not ask to use `gh`.

The historical failure mode is that review treats the PR number itself as permission to check `gh` and run `gh api` automatically.

## Simplified PR Shape

```text
Invocation:
- /code-review-committed-changes PR 4828

User request:
- No explicit request to use gh
- No explicit CLI fallback approval
```

## Expected Review Behavior

A correct committed review should:

- keep CLI fallback opt-in only
- avoid automatic `gh` availability checks
- avoid automatic `gh api` calls
- use non-terminal GitHub-backed review tools or fail closed

## Expected Must-Catch Outcomes

- `cli-fallback-opt-in-only`

## Expected Must-Not-Flag Outcomes

- `auto-gh-check`
