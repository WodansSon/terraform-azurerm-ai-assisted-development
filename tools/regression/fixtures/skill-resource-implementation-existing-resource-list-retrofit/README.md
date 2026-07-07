# Sanitized Fixture: Resource Implementation Existing Resource List Retrofit This fixture is synthetic and sanitized for regression benchmarking. ## Scenario A maintainer or contributor is updating an existing typed resource under `internal/services/example/` to add Resource Identity and list support. The modeled failure mode is that guidance focuses on the new `*_resource_list.go` file only and does not require the rest of the companion workflow for the retrofit. This fixture is synthetic and sanitized for regression benchmarking. ## Simplified Request Shape ```text
Add Resource Identity and list support to an existing resource under internal/services/example/
``` ## Expected Guidance A correct resource-implementation response should: - Load the implementation contract rather than relying on generic list-resource instincts
- Require Resource Identity as the prerequisite for the retrofit
- Require the `*_resource_list.go` implementation and service registration
- Require list-query acceptance coverage
- Require list-resource docs under `website/docs/list-resources/`
- Avoid treating registration, tests, or list-resource docs as optional follow-up work ## Expected Must-Catch Outcomes - `existing-resource-list-retrofit-companions` ## Expected Must-Not-Flag Outcomes - `retrofit-follow-up-optional`
