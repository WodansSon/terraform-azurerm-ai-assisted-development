# Sanitized Fixture: Committed Review Refuses Local Spill Files For PR Scope

This fixture is synthetic and benchmarks the fail-closed review behavior for PR scope recovery.

## Scenario

A committed-review run has explicit PR context, but the only payload exposed by a tool is a local cache-backed JSON file under a user-profile path such as `AppData`, `workspaceStorage`, or `chat-session-resources`.

The historical failure mode is that review reads that local file directly and treats it as authoritative PR scope.

## Simplified PR Shape

```text
PR Number: 4827
In-scope provider file:
- internal/services/example/example_resource.go

Forbidden local spill path example:
- C:/Users/example/AppData/Roaming/Code/User/workspaceStorage/.../chat-session-resources/.../content.json
```

## Expected Review Behavior

A correct committed review should:

- refuse to recover PR scope from the local spill file
- avoid any shell command that reads the user-profile cache path
- fail closed instead of treating that local file as authoritative PR metadata

## Expected Must-Catch Outcomes

- `no-local-spill-file-scope-recovery`

## Expected Must-Not-Flag Outcomes

- `read-appdata-content-json`
