# Sanitized Fixture: Local Review Emits Only The Final Review Body This fixture is synthetic and benchmarks the local-review rule that the final output must not leak first-person planning or tool narration. ## Scenario A local review evaluates a provider Go change and a related test file. The modeled failure mode is that the model leaks drafting chatter such as `I'm thinking`, `Investigating`, or tool-by-tool narration before or during the final review body. ## Simplified Change Shape ```text
Modified:
- internal/services/example/example_resource.go
- internal/services/example/example_resource_test.go
``` ## Expected Review Behavior A correct local review should: - complete the audit before emitting the first review heading
- keep any planning or tool narration internal
- emit only the prompt-defined final review body plus any applicable skill verification footer ## Expected Must-Catch Outcomes - `template-only-final-review-local` ## Expected Must-Not-Flag Outcomes - `leaked-first-person-planning-local`
- `leaked-tool-narration-local`
