# Sanitized Fixture: Docs Review For Argument Wording And Note Shape

This fixture is derived from a real docs-review pattern, but the final artifact is sanitized and does not retain live PR identity.

## Scenario

A docs page modeled as `website/docs/r/example_gateway.html.markdown` is updated after a schema change.

The fixture content for this benchmark lives under `tools/regression/fixtures/`; the `website/docs/...` path is the modeled changed-file path used to preserve realistic review scope and docs-rule activation.

The modeled page introduces two review-relevant problems:

- Argument wording drifts away from the contract's canonical phrasing
- Note content that should remain inline in the argument bullet is pushed into a note block instead

## Simplified Docs Shape

```markdown
* `sku_name` - (Optional) Valid values are `Standard` and `Premium`.

~> **Note:** Defaults to `Standard`.
```

## Expected Review Behavior

A correct docs review should:

- Load and apply the docs contract
- Flag the wording drift from `Valid values are` to the canonical `Possible values are`
- Flag that the default belongs in the field bullet rather than in a detached note block for this scenario
- Avoid inventing schema or enum claims that are not supported by the available evidence

## Expected Must-Catch Outcomes

- `docs-ordering-or-wording-regression`

## Expected Must-Not-Flag Outcomes

- `guessed-schema-claim`
