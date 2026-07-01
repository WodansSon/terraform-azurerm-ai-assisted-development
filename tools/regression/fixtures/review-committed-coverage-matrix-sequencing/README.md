# Sanitized Fixture: Committed Review Splits Matrix Build And Validation This fixture is synthetic and benchmarks the sequencing rule that the deterministic coverage matrix is built before standards loading but validated complete only after the relevant scoped guidance is available. ## Scenario A committed-review run adds a new provider resource plus related docs. The router can identify the overlap rows and lifecycle windows immediately, but some issue-class checks depend on implementation guidance and docs-contract guidance that the prompt loads later. ## Simplified PR Shape ```text
PR Number: 32482
Changed files:
- internal/services/example/example_group_resource.go
- internal/services/example/example_mode_validation.go
- website/docs/r/example_group_resource.html.markdown Late-needed standards:
- implementation guidance for companion and mode-gating expectations
- docs contract guidance for validator-to-doc parity expectations
``` ## Expected Review Behavior A correct committed review should: - load `review-coverage-matrix.schema.json` explicitly
- build the structured matrix before standards loading
- load implementation guidance and docs contract guidance next
- validate matrix completion only after those standards are available
- block routed analysis until that later validation succeeds ## Expected Must-Catch Outcomes - `matrix-built-before-standards`
- `matrix-validated-after-standards` ## Expected Must-Not-Flag Outcomes - `pre-standards-completion-deadlock`
