# Sanitized Fixture: Committed Review PATCH And Optional State Drift

This fixture is synthetic and sanitized. It exists to prove that the generic committed review prompt does not swap between a blocking state-drift defect and a separate atypical request-shaping concern when both are present in the same new-resource pull request, and does not drop the non-blocking concern just because the blocking defect already determines the verdict.

## Scenario

The modeled committed change adds a new typed project-connection resource family:

- `internal/services/example/example_project_connection_resource.go`
- `internal/services/example/example_project_connection_resource_list.go`
- `internal/services/example/example_project_connection_resource_test.go`
- `website/docs/r/example_project_connection.html.markdown`
- `website/docs/r/example_project_connection_list.html.markdown`

## Simplified Change Shape

- The create path sends a full request body through a create SDK method that behaves like a PUT-style replace operation.
- The update path calls the same create-style helper even though the SDK also exposes a dedicated update path.
- The read path copies an API-returned `metadata` map back into Terraform state even when the schema marks `metadata` as `Optional` and the config omits it entirely.
- Current-run evidence does not prove that the create-versus-update helper choice loses a specific mutable field or is rejected by the service, so that part should survive in `OBSERVATIONS` as a non-blocking concern rather than being silently dropped.
- The list resource, tests, and docs are present so the review is not distracted by missing-companion artifacts.

## Expected Must-Catch Outcomes

- `patch-shape-concern-surfaced`
- `optional-field-omitted-config-state-drift`

## Expected Must-Not-Flag Outcomes

- `single-easy-finding-only`
