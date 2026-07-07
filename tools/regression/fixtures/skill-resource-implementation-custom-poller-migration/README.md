# Sanitized Fixture: Resource Implementation Custom Poller Migration Routing This fixture is synthetic and is intentionally validating a local toolkit routing behavior. ## Scenario A maintainer or contributor is replacing legacy polling logic under `internal/services/example/`. The code currently uses `pluginsdk.StateChangeConf` and `WaitForStateContext()` to poll until a `404` becomes `200`, and the contributor asks for help migrating that logic to the current provider polling approach. The modeled failure mode is that generic implementation guidance treats this like ordinary CRUD cleanup and does not invoke the specialist custom-poller migration guidance. ## Simplified Code Shape ```go
stateConf := &pluginsdk.StateChangeConf{ Pending: []string{"404"}, Target: []string{"200"}, Refresh: func() (interface{}, string, error) { resp, err := client.Get(ctx, id) if err != nil { if response.WasNotFound(resp.HttpResponse) { return resp, "404", nil } return nil, "0", fmt.Errorf("polling for %s: %+v", id, err) } return resp, "200", nil },
}
if _, err := stateConf.WaitForStateContext(ctx); err != nil { return err
}
``` ## Expected Guidance A correct resource-implementation response should: - load the implementation contract and the custom-poller migration skill
- require a `pollers.PollerType`-based migration instead of leaving the legacy polling structure in place
- preserve the legacy polling parity unless the user explicitly approves a behavior change
- include both `Skill used: resource-implementation` and `Skill used: custom-poller-migration` in the final response markers ## Expected Must-Catch Outcomes - `custom-poller-pattern-required`
- `preserve-polling-parity` ## Expected Must-Not-Flag Outcomes - `crud-only-guidance`
