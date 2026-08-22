# Sanitized Fixture: Committed Validator Placement Review

This fixture is synthetic and sanitized for regression benchmarking.

## Scenario

A committed Go change under `internal/services/example/` introduces two validators:

- `path_match` composes established helpers through nested `validation.All(...)` and `validation.Any(...)`
- `routing_expression` uses a long anonymous closure with custom parsing, normalization, duplicate detection, and multi-stage errors

## Simplified Code Shape

```go
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

## Expected Review Behavior

A correct committed review should:

- load file-scoped implementation guidance and apply `IMPL-SCHEMA-005`
- preserve the readable nested helper composition for `path_match`
- avoid asking for a wrapper function, validate file, or wrapper-only unit test for `path_match`
- flag `routing_expression` as genuinely complex custom logic that belongs in `validate/routing_expression.go`
- require matching focused unit coverage for the extracted complex validator

## Expected Must-Catch Outcomes

- `complex-inline-validator-needs-validate-file`

## Expected Must-Not-Flag Outcomes

- `nested-helper-composition-needs-wrapper`
