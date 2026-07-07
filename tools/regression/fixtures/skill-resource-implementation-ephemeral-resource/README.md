# Sanitized Fixture: Resource Implementation Ephemeral Resource Workflow This fixture is synthetic and sanitized for regression benchmarking. ## Scenario A maintainer or contributor is adding a provider ephemeral resource under `internal/services/example/`. The change introduces two workflow-relevant drifts: - The implementation is being approached like an ordinary CRUD resource instead of a framework ephemeral resource with `Open(...)`
- The contributor has not planned the required companion artifacts such as `EphemeralResources()` registration, docs under `website/docs/ephemeral-resources/`, and Terraform 1.10-gated tests ## Simplified Code Shape ```go
func resourceExampleSecretEphemeral() *pluginsdk.Resource { return &pluginsdk.Resource{ Create: resourceExampleSecretCreate, Read: resourceExampleSecretRead, }
}
``` ## Expected Guidance A correct resource-implementation response should: - Load the implementation contract rather than relying on generic Go instincts
- Require the `sdk.EphemeralResource` pattern with `Metadata`, `Configure`, `Schema`, and `Open`
- Require service registration through `EphemeralResources()`
- Require the companion docs under `website/docs/ephemeral-resources/` and Terraform 1.10-gated `*_ephemeral_test.go` coverage ## Expected Must-Catch Outcomes - `ephemeral-open-pattern-required`
- `ephemeral-companion-artifacts` ## Expected Must-Not-Flag Outcomes - `crud-resource-pattern`
