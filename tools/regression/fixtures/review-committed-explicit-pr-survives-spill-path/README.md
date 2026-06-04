# Sanitized Fixture: Committed Review Keeps Explicit PR Scope After A Spill Path

This fixture is synthetic and benchmarks the positive committed-review behavior for explicit PR scope recovery.

## Scenario

A committed-review run is invoked with an explicit PR number.

One GitHub-backed PR metadata path exposes only a forbidden local spill-file transport under a user-profile path such as `AppData`, `workspaceStorage`, or `chat-session-resources`.

Another allowed non-CLI GitHub-backed path still remains available for resolving the authoritative changed-file set for that same explicit PR number.

The historical failure mode is that review treats the first forbidden spill path as proof that authoritative PR scope is unavailable and emits the fail-closed message too early.

## Simplified PR Shape

```text
Invocation: /code-review-committed-changes PR 4827

In-scope provider file:
- internal/services/example/example_resource.go

Forbidden local spill path example from one tool:
- C:/Users/example/AppData/Roaming/Code/User/workspaceStorage/.../chat-session-resources/.../content.json

Another allowed non-CLI GitHub-backed PR metadata path is still available.
```

## Expected Review Behavior

A correct committed review should:

- keep the explicit PR number as authoritative deterministic input
- ignore the forbidden spill-file path from the first PR metadata tool
- continue with the next allowed non-CLI GitHub-backed PR metadata path for that same PR number
- resolve the authoritative PR changed-file set and continue the review normally
- avoid the fail-closed PR-scope message because allowed GitHub-backed scope resolution is not yet exhausted

## Expected Must-Catch Outcomes

- `explicit-pr-number-remains-authoritative`
- `spill-path-ignored-but-review-continues`

## Expected Must-Not-Flag Outcomes

- `premature-fail-closed-on-explicit-pr`
- `read-appdata-content-json`
