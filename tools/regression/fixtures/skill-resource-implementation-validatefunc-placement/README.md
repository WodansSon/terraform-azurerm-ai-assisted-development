# Sanitized Fixture: ValidateFunc Placement This fixture is maintainer-authored and sanitized for regression benchmarking. ## Scenario A maintainer or contributor is updating a provider resource under `internal/services/example/`. Elsewhere in the same service there are older validators that still use legacy placement, but those files are not part of the current change. The schema now contains three validation styles: - a short inline enum validator using `validation.StringInSlice(...)`
- a shared resource-ID validator using `commonids.Validate...`
- a long anonymous inline `ValidateFunc` closure with bespoke string checks for a routing-rule name ## Simplified Code Shape ```go
"sku_name": { Type: pluginsdk.TypeString, Required: true, ValidateFunc: validation.StringInSlice([]string{ "Standard_ExampleEdge", "Premium_ExampleEdge", }, false),
}, "example_endpoint_id": { Type: pluginsdk.TypeString, Required: true, ValidateFunc: commonids.ValidateExampleEndpointID,
}, "rule_name": { Type: pluginsdk.TypeString, Required: true, ValidateFunc: func(v interface{}, k string) (warnings []string, errors []error) { value := v.(string) if len(value) < 1 || len(value) > 64 { errors = append(errors, fmt.Errorf("property `%s` must be between 1 and 64 characters", k)) } if strings.Contains(value, " ") { errors = append(errors, fmt.Errorf("property `%s` cannot contain spaces", k)) } if strings.HasPrefix(value, "-") { errors = append(errors, fmt.Errorf("property `%s` cannot start with `-`", k)) } return warnings, errors },
}
``` ## Expected Guidance A correct resource-implementation response should: - load the implementation contract rather than improvising a style opinion
- keep the short helper-based validators inline in the schema
- recommend moving the bespoke anonymous closure into a file-specific validator under `validate/`, for example `validate/example_rule_name.go`
- recommend the matching unit test file, for example `validate/example_rule_name_test.go`
- avoid leaving the bespoke validator inline once it has crossed the readability threshold
- avoid demanding unrelated cleanup of untouched legacy validator files elsewhere in the service ## Expected Must-Catch Outcomes - `inline-anonymous-validator-overuse` ## Expected Must-Not-Flag Outcomes - `simple-inline-helper-composition`
- `invent-validate-package`
- `untouched-legacy-validator-layout`
