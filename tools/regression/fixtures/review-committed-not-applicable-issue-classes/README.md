# Sanitized Fixture: Committed Review Models Not-Applicable Issue Classes Explicitly This fixture is synthetic and benchmarks the structured completion-semantics rule that required issue classes can be satisfied either by explicit completion or by an explicit, evidence-backed not-applicable state. ## Scenario A committed-review run adds a new provider resource plus related docs. Some issue classes remain globally required by the matrix model, but one or more rows can justify a specific issue class as not applicable. The deterministic requirement is that those states appear in `notApplicableIssueClasses` rather than being implied only by prose. ## Simplified PR Shape ```text
PR Number: 32482
Changed files:
- internal/services/example/example_group_resource.go
- internal/services/example/example_mode_validation.go
- website/docs/r/example_group_resource.html.markdown
``` ## Expected Review Behavior A correct committed review should: - keep required issue classes explicit
- record row-level `notApplicableIssueClasses` where current-run evidence supports them
- record top-level `notApplicableIssueClasses` where current-run evidence supports them
- avoid treating missing completion as implicitly satisfied ## Expected Must-Catch Outcomes - `row-level-not-applicable-issue-classes`
- `top-level-not-applicable-issue-classes` ## Expected Must-Not-Flag Outcomes - `implicit-issue-class-state`
