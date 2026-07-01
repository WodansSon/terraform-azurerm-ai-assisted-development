# Sanitized Fixture: Committed Review Flags Shortened New Cross-Resource ID Fields This fixture is synthetic and benchmarks naming review for new public cross-resource ID fields. ## Scenario A committed-review run covers a brand-new resource, its list companion, and its docs. The new public surface exposes a field called `scheduler_id`, but that field actually stores the ID of another Terraform-managed resource whose full provider-facing name would require a field such as `durable_task_scheduler_id`. The modeled failure mode is that review accepts the shortened field name because it is readable, even though doing so bakes a naming exception into the new schema, list resource, tests, and docs from day one. ## Simplified Change Shape ```text
Added or modified:
- internal/services/example/example_resource.go
- internal/services/example/example_resource_list.go
- website/docs/r/example_resource.html.markdown New public field:
- scheduler_id Expected provider naming pattern:
- durable_task_scheduler_id
``` ## Expected Review Behavior A correct committed review should: - recognize that the new field stores another Terraform-managed resource ID
- apply provider naming rules for cross-resource ID fields
- flag the shortened field name as a new public naming issue
- make clear that a brand-new surface should not ship with a day-one naming exception ## Expected Must-Catch Outcomes - `new-cross-resource-id-field-name-too-short` ## Expected Must-Not-Flag Outcomes - `accept-shortened-day-one-id-name`
