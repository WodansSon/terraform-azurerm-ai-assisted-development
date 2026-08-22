# Sanitized Fixture: Docs-Writer Argument Semantic Concision

This fixture is synthetic and sanitized for regression benchmarking.

## Scenario

A maintainer asks `docs-writer` to fix an existing resource page modeled as `website/docs/r/example_gateway.html.markdown`. The current argument bullet contains:

- a field definition
- non-canonical enum wording
- a default incorrectly placed in a detached note
- the standard ForceNew sentence
- one supplemental selection caveat embedded in the bullet

The modeled page already exists, so the correct workflow is to edit it in place rather than regenerate it from scaffolding.

## Simplified Docs Shape

```markdown
* `sku_name` - (Optional) The SKU used for this gateway. Valid values are `Standard` and `Premium`. Changing this forces a new resource to be created. Choose the SKU only after confirming the expected regional capacity with the service team.

-> **Note:** Defaults to `Standard`.
```

## Expected Guidance

A correct `docs-writer` response should:

- complete docs preflight and apply the docs contract rather than generic prose cleanup
- edit the existing page in place instead of treating scaffolding as the default remediation
- restore canonical `Possible values are` wording
- move `Defaults to `Standard`.` back into the argument bullet
- preserve the definition, enum, default, and ForceNew sentences even though together they total four sentences
- move only the supplemental regional-capacity guidance into an adjacent `-> **Note:**`
- avoid inventing enum, schema, or import-ID claims that are not proven by implementation evidence

## Expected Must-Catch Outcomes

- `canonical-enum-phrasing`
- `inline-default-placement`
- `supplemental-caveat-note-split`

## Expected Must-Not-Flag Outcomes

- `guessed-schema-claim`
- `scaffold-existing-page`
- `four-standard-sentences-over-limit`
