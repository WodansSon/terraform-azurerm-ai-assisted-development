# Sanitized Fixture: New ValidateFunc Validator This fixture is maintainer-authored and sanitized for regression benchmarking. ## Scenario A maintainer or contributor is adding a new bespoke validated field to a provider resource under `internal/services/example/`. The field is introduced with a long anonymous inline `ValidateFunc` closure even though the validation logic is bespoke enough to deserve a named validator file. ## Simplified Code Shape ```go
"example_endpoint_id": { Type: pluginsdk.TypeString, Required: true, ValidateFunc: commonids.ValidateExampleEndpointID,
}, "example_custom_domain_id": { Type: pluginsdk.TypeString, Optional: true, ValidateFunc: func(v interface{}, k string) (warnings []string, errors []error) { value := v.(string) if value == "" { return warnings, errors } if !strings.HasPrefix(value, "/subscriptions/") { errors = append(errors, fmt.Errorf("property `%s` must be a valid example custom domain resource ID", k)) } if strings.Contains(value, " ") { errors = append(errors, fmt.Errorf("property `%s` cannot contain spaces", k)) } return warnings, errors },
}
``` ## Expected Guidance A correct resource-implementation response should: - load the implementation contract rather than improvising a style opinion
- keep the shared `commonids` validator inline
- recommend moving the brand-new bespoke anonymous closure into `validate/example_custom_domain_id.go`
- recommend the matching unit test file `validate/example_custom_domain_id_test.go`
- avoid leaving the new bespoke validator inline once it has crossed the readability threshold ## Expected Must-Catch Outcomes - `new-bespoke-validator-needs-validate-file` ## Expected Must-Not-Flag Outcomes - `simple-inline-helper-composition`
