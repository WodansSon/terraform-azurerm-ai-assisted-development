# Sanitized Fixture: Committed Review Keeps Multi-Issue Accuracy On A New Service PR

This fixture is derived from a real committed-review miss pattern, but the final artifact is sanitized and does not retain live PR identity.

## Scenario

A committed review covers a new service package with multiple new resources, list resources, tests, and docs.

The change introduces three merge-blocking issues plus one design-risk observation:

1. One resource update path clears a field through a special-case PUT branch and returns immediately, which silently skips concurrent changes to other updatable fields.
2. A brand-new public cross-resource ID field is introduced as `scheduler_id` even though provider naming rules require the full referenced resource name, e.g. `durable_task_scheduler_id`.
3. The new resources add repeated generic lifecycle logging such as `Import check`, `Creating`, `Reading`, `Updating`, and `Deleting`.
4. A retention-policy schema allows duplicate or ambiguous state-specific entries, but the fixture does not provide implementation-backed evidence for the service-side precedence semantics, so that point should remain a non-blocking observation.

The historical failure mode is that review collapses onto the easy lifecycle-logging issue and misses the update-path defect and the public naming issue entirely.

## Simplified Change Shape

```text
Changed files:
- internal/services/example/example_scheduler_resource.go
- internal/services/example/example_hub_resource.go
- internal/services/example/example_retention_policy_resource.go
- internal/services/example/example_hub_resource_list.go
- website/docs/r/example_hub.html.markdown
- website/docs/r/example_retention_policy.html.markdown

Merge-blocking issues in scope:
- update branch returns early and skips concurrent field changes
- new public cross-resource ID field uses shortened name `scheduler_id`
- repeated generic lifecycle logging in new resources

Non-blocking observation in scope:
- duplicate or ambiguous retention-policy entries are not validated at plan time
```

## Expected Review Behavior

A correct committed review should:

- apply the full Go implementation and testing guidance set before classifying findings
- catch the early-return update-path bug as a blocking issue
- catch the shortened new public cross-resource ID field name as a blocking issue
- catch the repeated generic lifecycle logging as a blocking issue
- keep the retention-policy ambiguity concern as a non-blocking observation when service-side precedence is not implementation-backed
- avoid collapsing the review to helper-style churn while missing the real defects

## Expected Must-Catch Outcomes

- `durabletask-update-branch-skips-concurrent-changes`
- `durabletask-cross-resource-id-name-too-short`
- `durabletask-generic-lifecycle-logging`
- `retention-policy-duplicate-state-risk-observation`

## Expected Must-Not-Flag Outcomes

- `template-helper-style-as-main-issue`
