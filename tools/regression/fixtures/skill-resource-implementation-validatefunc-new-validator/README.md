# Sanitized Fixture: New ValidateFunc Validator

This fixture is maintainer-authored and sanitized for regression benchmarking.

## Scenario

A maintainer or contributor is adding a new validated field to a provider resource under `internal/services/example/`. The field is introduced with a long anonymous `ValidateFunc` closure that implements custom parsing, normalization, duplicate detection, and multi-stage error handling that cannot remain clear through established helper composition.

## Simplified Code Shape

```go
"example_endpoint_id": {
    Type:         pluginsdk.TypeString,
    Required:     true,
    ValidateFunc: commonids.ValidateExampleEndpointID,
},

"routing_expression": {
    Type:     pluginsdk.TypeString,
    Required: true,
    ValidateFunc: func(v interface{}, k string) (warnings []string, errors []error) {
        segments := strings.Split(v.(string), ":")
        if len(segments) != 3 {
            errors = append(errors, fmt.Errorf("property `%s` must contain exactly three segments", k))
            return warnings, errors
        }

        seen := make(map[string]struct{})
        for _, segment := range segments {
            normalized := strings.ToLower(strings.TrimSpace(segment))
            if normalized == "" {
                errors = append(errors, fmt.Errorf("property `%s` cannot contain empty segments", k))
                continue
            }
            if _, exists := seen[normalized]; exists {
                errors = append(errors, fmt.Errorf("property `%s` cannot contain duplicate segments", k))
            }
            seen[normalized] = struct{}{}
        }

        return warnings, errors
    },
},
```

## Expected Guidance

A correct resource-implementation response should:

- load the implementation contract rather than improvising a style opinion
- keep the shared `commonids` validator inline
- move the genuinely complex anonymous parser into `validate/routing_expression.go`
- add the matching unit test file `validate/routing_expression_test.go`
- avoid generalizing the exception into a requirement to extract established helper composition

## Expected Must-Catch Outcomes

- `new-bespoke-validator-needs-validate-file`

## Expected Must-Not-Flag Outcomes

- `established-inline-helper-composition`
