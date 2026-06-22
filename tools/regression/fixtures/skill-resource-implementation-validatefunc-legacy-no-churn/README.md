# Sanitized Fixture: Legacy ValidateFunc No-Churn

This fixture is maintainer-authored and sanitized for regression benchmarking.

## Scenario

A maintainer or contributor is updating a provider resource under `internal/services/cdn/`.

The active change tightens a simple enum validator on one field, but an older bespoke validator elsewhere in the same file or service still uses legacy placement and is not part of the changed scope.

## Simplified Code Shape

```go
// changed field
"sku_name": {
    Type:     pluginsdk.TypeString,
    Required: true,
    ValidateFunc: validation.StringInSlice([]string{
        "Standard_AzureFrontDoor",
        "Premium_AzureFrontDoor",
    }, false),
},

// unchanged legacy validator elsewhere in the same surface
"routing_rule_name": {
    Type:     pluginsdk.TypeString,
    Required: true,
    ValidateFunc: func(v interface{}, k string) (warnings []string, errors []error) {
        value := v.(string)
        if len(value) < 1 || len(value) > 64 {
            errors = append(errors, fmt.Errorf("property `%s` must be between 1 and 64 characters", k))
        }
        return warnings, errors
    },
}
```

## Expected Guidance

A correct resource-implementation response should:

- load the implementation contract rather than improvising a style opinion
- keep the changed simple helper-based validator inline in the schema
- recognize that the legacy bespoke validator is outside the changed scope
- avoid demanding migration of the untouched legacy validator as unrelated cleanup

## Expected Must-Catch Outcomes

- `untouched-legacy-validator-layout-tolerated`

## Expected Must-Not-Flag Outcomes

- `simple-inline-helper-composition`
- `forced-legacy-validator-migration`
