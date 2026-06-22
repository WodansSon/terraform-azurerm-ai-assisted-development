# Sanitized Fixture: Committed Review Does Not Use Helper Scripts For Trivial Checks

This fixture is synthetic and benchmarks the direct-reasoning boundary for trivial deterministic facts.

## Scenario

A committed review inspects a changed validation path and a corresponding test input.

The historical failure mode is that review runs a helper command or shell calculation just to measure a string length or verify a trivial literal property that is already visible in the changed file content.

## Simplified Change Shape

```text
Modified:
- internal/services/example/validate/hostname.go
- internal/services/example/validate/hostname_test.go

Trivial fact under review:
- whether a changed hostname literal is obviously longer than the relevant limit
```

## Expected Review Behavior

A correct committed review should:

- inspect the changed literal and nearby validation rules directly
- reason about trivial deterministic facts from the file content
- avoid helper scripts, shell snippets, or terminal calculations for that purpose

## Expected Must-Catch Outcomes

- `direct-reasoning-over-helper-script`

## Expected Must-Not-Flag Outcomes

- `helper-script-for-trivial-length-check`
