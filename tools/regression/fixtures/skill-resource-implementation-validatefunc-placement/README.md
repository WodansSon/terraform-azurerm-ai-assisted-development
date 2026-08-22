# Sanitized Fixture: ValidateFunc Placement

This fixture is maintainer-authored and sanitized for regression benchmarking.

## Scenario

A maintainer or contributor is updating a provider resource under `internal/services/example/`. Elsewhere in the same service there are older validators that still use legacy placement, but those files are not part of the current change.

The changed schema contains four validation styles:

- an inline enum validator using `validation.StringInSlice(...)`
- a shared resource-ID validator using `commonids.Validate...`
- understandable nested composition using `validation.All(...)` and `validation.Any(...)`
- a long anonymous `ValidateFunc` closure implementing a genuinely complex custom parser

## Simplified Code Shape

```go
"sku_name": {
    Type:     pluginsdk.TypeString,
    Required: true,
    ValidateFunc: validation.StringInSlice([]string{
        "Standard_ExampleEdge",
        "Premium_ExampleEdge",
    }, false),
},

"example_endpoint_id": {
    Type:         pluginsdk.TypeString,
    Required:     true,
    ValidateFunc: commonids.ValidateExampleEndpointID,
},

"path_match": {
    Type:     pluginsdk.TypeString,
    Required: true,
    ValidateFunc: validation.All(
        validation.StringIsNotEmpty,
        validation.Any(
            validation.StringDoesNotStartWithOneOf("/"),
            validation.StringInSlice([]string{"/"}, false),
        ),
    ),
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
- keep the enum, shared ID validator, and nested established-helper composition inline
- avoid creating a wrapper function, validate file, or wrapper-only unit test for `path_match`
- move the genuinely complex anonymous parser into `validate/routing_expression.go`
- add the matching unit test file `validate/routing_expression_test.go`
- avoid demanding unrelated cleanup of untouched legacy validator files elsewhere in the service

## Expected Must-Catch Outcomes

- `inline-anonymous-validator-overuse`

## Expected Must-Not-Flag Outcomes

- `nested-inline-helper-composition`
- `invent-validate-package`
- `untouched-legacy-validator-layout`
