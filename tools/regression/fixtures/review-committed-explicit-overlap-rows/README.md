# Sanitized Fixture: Committed Review Names Explicit Overlap Rows This fixture is synthetic and benchmarks the stronger determinism requirement that unchanged overlap surfaces be materialized as explicit file-path rows in the review coverage matrix. ## Scenario A committed-review run adds a new group-managed example resource and related docs. The key risk is not merely that overlap exists, but that reruns could omit unchanged sibling surfaces unless the router names them explicitly in the coverage plan. ## Simplified PR Shape ```text
PR Number: 32482
Changed files:
- internal/services/example/example_group_resource.go
- internal/services/example/example_mode_validation.go
- website/docs/r/example_group_resource.html.markdown Required unchanged overlap rows:
- internal/services/example/example_item_resource.go
- internal/services/example/example_set_resource.go
- internal/services/example/example_route_resource.go
``` ## Expected Review Behavior A correct committed review should: - build a structured coverage matrix before standards loading and findings
- name unchanged overlap rows by explicit file path
- avoid routed-role analysis that starts from a partial or implicit overlap set ## Expected Must-Catch Outcomes - `explicit-overlap-file-rows`
- `routed-roles-after-coverage` ## Expected Must-Not-Flag Outcomes - `implicit-overlap-only`
