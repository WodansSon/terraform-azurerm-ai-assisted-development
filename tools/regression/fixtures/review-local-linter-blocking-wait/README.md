# Sanitized Fixture: Local Review Waits For Blocking azurerm-linter This fixture is synthetic and benchmarks the local-review rule that `azurerm-linter` remains a blocking step even when the runtime returns control early. ## Scenario A local review inspects a provider Go change and runs filtered local-diff linting. The modeled failure mode is that the runtime returns control while `azurerm-linter` is still running, and the review starts reading files, narrating the wait, or drafting findings from partial state. ## Simplified Change Shape ```text
Modified:
- internal/services/example/example_resource.go
- internal/services/example/example_resource_test.go
``` ## Expected Review Behavior A correct local review should: - launch one filtered `azurerm-linter` run
- keep that run as an outstanding blocking step until it completes
- avoid file reads, finding classification, and user-visible wait narration while the linter is still running
- classify the linter section only after that same completed run is classifiable ## Expected Must-Catch Outcomes - `linter-blocking-step-local` ## Expected Must-Not-Flag Outcomes - `premature-review-continuation-local`
- `linter-wait-narration-local`
- `partial-linter-classification-local`
