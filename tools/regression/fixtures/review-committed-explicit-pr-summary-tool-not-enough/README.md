# Sanitized Fixture: Committed Review Requires PR-Files Scope, Not Summary Results

This fixture is synthetic and benchmarks the positive committed-review behavior for explicit PR scope recovery when earlier GitHub-backed results are only summaries.

## Scenario

A committed-review run is invoked with an explicit PR number.

One GitHub-backed path returns only PR-summary or issue-style metadata.
Another GitHub-backed path returns a browser-link result such as `Open on GitHub.com`.
The preferred direct non-CLI PR-files API path still remains available for resolving the authoritative changed-file set for that same explicit PR number.

The historical failure mode is that review mistakes those earlier summary-only outputs for either authoritative PR scope or proof that the remaining allowed retrieval paths are exhausted.

## Simplified PR Shape

```text
Invocation: /code-review-committed-changes PR 4829

In-scope provider file:
- internal/services/example/example_resource.go

Earlier GitHub-backed outputs:
- PR summary or issue-style metadata only
- browser-link result such as "Open on GitHub.com"

Preferred remaining non-CLI PR-files path:
- `https://api.github.com/repos/<owner>/<repo>/pulls/<number>/files`
```

## Expected Review Behavior

A correct committed review should:

- keep the explicit PR number as authoritative deterministic input
- treat PR-summary, issue-style, status, or browser-link results as insufficient for scope resolution
- continue with the preferred direct non-CLI PR-files API path for that same PR number
- resolve the authoritative PR changed-file set and continue the review normally
- avoid the fail-closed PR-scope message because allowed PR-files retrieval is not yet exhausted

## Expected Must-Catch Outcomes

- `summary-tool-not-authoritative-scope`
- `explicit-pr-continues-after-summary-results`

## Expected Must-Not-Flag Outcomes

- `premature-fail-closed-on-summary-results`
