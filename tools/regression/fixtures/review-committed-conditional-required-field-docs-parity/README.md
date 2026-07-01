# Sanitized Fixture: Committed Review Catches Conditional Required-Field Docs Parity Gaps This fixture is synthetic and benchmarks validator-to-doc parity for conditional required fields. ## Scenario A committed review includes a docs page and the companion validator logic in scope. The validator requires `duration_value` when `duration_mode` is either `AlwaysOverride` or `OverrideWhenMissing`. The docs page still describes `duration_value`, but does not state that this field becomes required for those specific mode values. ## Simplified PR Shape ```text
Changed files:
- internal/services/example/example_rule_definition_validation.go
- website/docs/r/example_batch_resource.html.markdown
- internal/services/example/example_batch_resource.go Conditional requirement in scope:
- duration_value is required when duration_mode is AlwaysOverride
- duration_value is required when duration_mode is OverrideWhenMissing
``` ## Expected Review Behavior A correct committed review should: - apply validator-to-doc parity checking because the validator and docs page are both in scope
- flag the missing conditional requirement note for `duration_value`
- cite the concrete `duration_mode` values that trigger the requirement
- avoid treating the docs as complete just because the field itself is mentioned somewhere on the page ## Expected Must-Catch Outcomes - `conditional-required-field-docs-mismatch` ## Expected Must-Not-Flag Outcomes - `field-described-therefore-complete`
