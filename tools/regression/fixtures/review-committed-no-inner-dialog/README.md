# Sanitized Fixture: Committed Review Emits Only The Final Review Body This fixture is synthetic and benchmarks the committed-review rule that the final output must not leak first-person planning or tool narration. ## Scenario A committed review evaluates a provider Go change plus a docs file. The modeled failure mode is that the model leaks drafting chatter such as `I'm thinking`, `Investigating`, or tool-by-tool narration before or during the final review body. ## Simplified Change Shape ```text
Modified:
- internal/services/example/example_resource.go
- website/docs/r/example_resource.html.markdown
``` ## Expected Review Behavior A correct committed review should: - complete the audit before emitting the first review heading
- keep any planning or tool narration internal
- emit only the prompt-defined final review body plus any applicable skill verification footer ## Expected Must-Catch Outcomes - `template-only-final-review` ## Expected Must-Not-Flag Outcomes - `leaked-first-person-planning`
- `leaked-tool-narration`
