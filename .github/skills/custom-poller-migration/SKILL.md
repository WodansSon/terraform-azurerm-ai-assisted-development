---
name: custom-poller-migration
description: Assist in migrating legacy pluginsdk.Retry() and pluginsdk.StateChangeConf.WaitForStateContext() logic to custom pollers.
---

# Custom Poller Migration

## Canonical sources of truth (contract-driven)

When migrating polling logic under `internal/**`, use `.github/instructions/implementation-compliance-contract.instructions.md` as the single source of truth for:

- canonical sources and precedence
- implementation compliance requirements
- relevant `IMPL-*` rule families

Do not treat this skill as a second independent compliance source.

This skill is a specialist companion to `.github/skills/resource-implementation/SKILL.md`, not a replacement for it.

## Mandatory: read the entire skill

Before applying this skill, read this file to EOF.

## Preflight checklist

Before editing polling logic with this skill, complete this checklist:

- [ ] I have read this skill to EOF.
- [ ] I have loaded `.github/instructions/implementation-compliance-contract.instructions.md` to EOF and applied the relevant `IMPL-*` rules.
- [ ] I have confirmed the task is a polling migration rather than a normal CRUD/schema change.
- [ ] I have identified the exact legacy polling behavior that must be preserved.

If preflight is incomplete, do not proceed with implementation work.

## Scope

Use this skill when the task under `internal/**/*.go` involves migrating or replacing legacy polling logic, especially when you encounter:

- `pluginsdk.Retry()`
- `pluginsdk.StateChangeConf`
- `WaitForStateContext()`
- legacy polling loops that should become `pollers.PollerType`

## Verification (assistant response only)

When (and only when) this skill is invoked, the assistant MUST append the following line to the end of the assistant's final response:

Skill used: custom-poller-migration

Rules:
- Do NOT write this marker into repository files.
- If multiple skills are invoked, each skill should append its own `Skill used: ...` line.
- Do NOT emit the marker in intermediate/progress updates; only in the final response.

## Identification

You will typically encounter two legacy polling patterns.

### Legacy `pluginsdk.Retry()`

This loop repeatedly runs a function until it succeeds or hits a non-retryable error, often checking specific HTTP failure conditions.

```go
err = pluginsdk.Retry(d.Timeout(pluginsdk.TimeoutCreate), func() *pluginsdk.RetryError {
  resp, err := client.CreateOrUpdate(ctx, id, params)
  if err != nil {
    if response.WasBadRequest(resp.HttpResponse) {
      return pluginsdk.RetryableError(err)
    }
    return pluginsdk.NonRetryableError(err)
  }
  return nil
})
```

### Legacy `pluginsdk.StateChangeConf`

This structure polls an API via `Refresh` until the returned state enters the configured `Target` set, remaining in a `Pending` state otherwise.

```go
stateConf := &pluginsdk.StateChangeConf{
  Pending: []string{"404"},
  Target:  []string{"200"},
  Refresh: func() (interface{}, string, error) {
    resp, err := client.Get(ctx, id)
    if err != nil {
      if response.WasNotFound(resp.HttpResponse) {
        return resp, strconv.Itoa(resp.HttpResponse.StatusCode), nil
      }
      return nil, "0", fmt.Errorf("polling for %s: %+v", id, err)
    }
    return resp, strconv.Itoa(resp.HttpResponse.StatusCode), nil
  },
}
if _, err := stateConf.WaitForStateContext(ctx); err != nil {
  return err
}
```

## Migration expectations

- Preserve behavioral parity with the legacy implementation.
- Match the existing polling interval, success states, pending states, and terminal error conditions exactly.
- Do not silently fix legacy polling bugs just because you found them during migration.
- If the legacy behavior appears wrong, document it in the implementation plan and wait for user approval before changing provider behavior.

## Implementing a custom poller

A custom poller must implement `pollers.PollerType`, specifically `Poll(ctx context.Context) (*pollers.PollResult, error)`.

Place the poller in a `custompollers` package under the relevant service when that matches the existing provider pattern.

### Structure example

```go
package custompollers

import (
  "context"
  "fmt"
  "net/http"
  "time"

  "github.com/hashicorp/go-azure-sdk/sdk/client/pollers"
)

var _ pollers.PollerType = &examplePoller{}

type examplePoller struct {
  client *service.Client
  id     service.IdType
}

func NewExamplePoller(cli *service.Client, id service.IdType) *examplePoller {
  return &examplePoller{
    client: cli,
    id:     id,
  }
}
```

### Poll implementation example

Never use a package-level shared `pollers.PollResult` variable. Always return a fresh `pollers.PollResult{}` directly to avoid concurrency bugs.

```go
func (p examplePoller) Poll(ctx context.Context) (*pollers.PollResult, error) {
  resp, err := p.client.Get(ctx, p.id)
  if err != nil {
    if response.WasNotFound(resp.HttpResponse) {
      return &pollers.PollResult{
        Status:       pollers.PollingStatusInProgress,
        PollInterval: 10 * time.Second,
      }, nil
    }
    return nil, fmt.Errorf("checking state: %+v", err)
  }

  if resp.StatusCode == http.StatusOK {
    return &pollers.PollResult{
      Status:       pollers.PollingStatusSucceeded,
      PollInterval: 10 * time.Second,
    }, nil
  }

  return nil, fmt.Errorf("unexpected status code %d", resp.StatusCode)
}
```

## Integration

Replace the old polling block with the custom poller.

### Direct invocation

```go
poller := custompollers.NewExamplePoller(client, id)
if err := pollers.PollUntilDone(ctx, poller); err != nil {
  return fmt.Errorf("waiting for state: %+v", err)
}
```

### Operations that already expose `resp.Poller`

```go
resp, err := client.CreateOrUpdate(ctx, id, params)
if err != nil {
  return fmt.Errorf("creating resource: %+v", err)
}

if err := resp.Poller.PollUntilDone(ctx); err != nil {
  return fmt.Errorf("waiting for completion: %+v", err)
}
```

## Output expectation

When asked to perform a polling migration, provide:

- the legacy polling behavior being replaced
- the exact parity requirements that must be preserved
- the custom poller structure you will introduce
- the integration point that replaces the old polling block
- how you validated that the migration preserved behavior
