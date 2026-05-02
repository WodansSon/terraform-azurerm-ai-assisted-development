# Sanitized Fixture: Resource Implementation Validation

This fixture is derived from a real historical implementation-guidance incident, but the final artifact is sanitized and does not retain live PR identity.

## Scenario

A maintainer or contributor is updating a provider resource under `internal/services/cdn/`.

The change introduces two review-relevant behaviors:

- A configurable field is validated with a weak fallback validator even though a narrower accepted set is knowable from the implementation context
- A flatten or parse path wraps an already comprehensive parser error with redundant `flattening` context

## Simplified Code Shape

```go
"match_variable": {
    Type:         pluginsdk.TypeString,
    Required:     true,
    ValidateFunc: validation.StringIsNotEmpty,
}

...

id, err := parse.FrontDoorFirewallPolicyID(input)
if err != nil {
    return results, fmt.Errorf("flattening `cdn_frontdoor_firewall_policy_id`: %+v", err)
}
```

## Expected Guidance

A correct resource-implementation response should:

- Load the implementation contract rather than relying on generic Go instincts
- Prefer stronger validation when the accepted values are knowable
- Avoid blindly requiring a full SDK `PossibleValuesFor...` helper if the resource only accepts a narrower subset
- Return comprehensive parser errors directly when extra wrapping adds no meaningful information

## Expected Must-Catch Outcomes

- `fallback-validator-overuse`
- `redundant-parser-wrapper`

## Expected Must-Not-Flag Outcomes

- `blind-sdk-enum-usage`
- `parser-error-needs-more-context`
