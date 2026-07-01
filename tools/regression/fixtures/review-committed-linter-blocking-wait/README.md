# Sanitized Fixture: Committed Review Waits For Blocking azurerm-linter This fixture is synthetic and benchmarks the committed-review rule that `azurerm-linter` remains a blocking step even when the runtime returns control early. ## Scenario A committed review inspects a provider Go change with PR-scoped linting enabled. The modeled failure mode is that the runtime returns control while `azurerm-linter` is still running, and the review starts reading files, narrating the wait, or drafting findings from partial state. ## Simplified Change Shape ```text
Modified:
- internal/services/example/example_resource.go
- website/docs/r/example_resource.html.markdown
``` ## Expected Review Behavior A correct committed review should: - launch one PR-scoped `azurerm-linter` run
- keep that run as an outstanding blocking step until it completes
- avoid file reads, finding classification, and user-visible wait narration while the linter is still running
- classify the linter section only after that same completed run is classifiable ## Expected Must-Catch Outcomes - `linter-blocking-step-committed` ## Expected Must-Not-Flag Outcomes - `premature-review-continuation-committed`
- `linter-wait-narration-committed`
- `partial-linter-classification-committed`
