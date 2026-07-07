# Sanitized Fixture: Resource Implementation Provider Function Workflow This fixture is synthetic and sanitized for regression benchmarking. ## Scenario A maintainer or contributor is adding a provider-defined function under `internal/provider/function/`. The change introduces two workflow-relevant drifts: - The implementation is being approached like a service resource instead of a provider-defined function with `Metadata`, `Definition`, and `Run`
- The contributor has not planned the required companion artifacts such as docs under `website/docs/functions/` and Terraform 1.8-gated unit tests under `internal/provider/function/*_test.go` ## Simplified Code Shape ```go
func resourceExampleResourceID() *pluginsdk.Resource { return &pluginsdk.Resource{ Read: resourceExampleRead, }
}
``` ## Expected Guidance A correct resource-implementation response should: - Load the implementation contract rather than relying on generic Go instincts
- Require the provider-defined function pattern under `internal/provider/function/`
- Require `Metadata`, `Definition`, and `Run`
- Require the companion docs under `website/docs/functions/` and Terraform 1.8-gated unit tests under `internal/provider/function/*_test.go` ## Expected Must-Catch Outcomes - `provider-function-pattern-required`
- `provider-function-companion-artifacts` ## Expected Must-Not-Flag Outcomes - `service-resource-pattern`
