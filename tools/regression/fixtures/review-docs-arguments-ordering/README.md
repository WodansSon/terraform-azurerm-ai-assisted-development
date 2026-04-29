# Sanitized Fixture: Docs Review For Argument Wording And Note Shape

This fixture is derived from a real docs-review pattern, but the final artifact is sanitized and does not retain live PR identity.

## Scenario

A docs page under `website/docs/r/` is updated after a schema change.

The page introduces two review-relevant problems:

- argument wording drifts away from the contract's canonical phrasing
- note content that should remain inline in the argument bullet is pushed into a note block instead

## Simplified Docs Shape

```markdown
* `sku_name` - (Optional) Valid values are `Standard` and `Premium`.

~> **Note:** Defaults to `Standard`.
```

## Expected Review Behavior

A correct docs review should:

- load and apply the docs contract
- flag the wording drift from `Valid values are` to the canonical `Possible values are`
- flag that the default belongs in the field bullet rather than in a detached note block for this scenario
- avoid inventing schema or enum claims that are not supported by the available evidence

## Expected Must-Catch Outcomes

- `docs-ordering-or-wording-regression`

## Expected Must-Not-Flag Outcomes

- `guessed-schema-claim`
