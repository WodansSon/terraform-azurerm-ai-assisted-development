# Sanitized Fixture: Committed Review Uses Router Validation Sub-Phase As Canonical Gate This fixture is synthetic and benchmarks the hardening step where the router skill owns an explicit validation sub-phase that acts as the canonical completion gate before findings or routed roles can proceed. ## Scenario A committed-review run adds a new provider resource plus related docs. The deterministic matrix already exists, but the workflow must make it explicit that completion is confirmed by the router validation sub-phase rather than by looser prompt prose. ## Simplified PR Shape ```text
PR Number: 32482
Changed files:
- internal/services/example/example_group_resource.go
- internal/services/example/example_mode_validation.go
- website/docs/r/example_group_resource.html.markdown
``` ## Expected Review Behavior A correct committed review should: - build the matrix earlier in the workflow
- use the already-loaded router skill's validation sub-phase after standards loading
- treat that validation sub-phase as the canonical completion gate
- avoid implying that a separate validator surface is required already ## Expected Must-Catch Outcomes - `router-validation-subphase-canonical`
- `no-prose-only-completion-check` ## Expected Must-Not-Flag Outcomes - `separate-validator-required-now`
