# Sanitized Fixture: Docs-Writer Argument Note Shape

This fixture is derived from a real historical docs-remediation request, but the final artifact is sanitized and does not retain live PR identity.

## Scenario

A maintainer asks `docs-writer` to fix an existing resource page modeled as `website/docs/r/example_gateway.html.markdown`.

The fixture content for this benchmark lives under `tools/regression/fixtures/`; the `website/docs/...` path is the modeled changed-file path used to preserve realistic docs-writer routing and rule activation.

The current page has two contract-relevant drifts:

- The argument bullet uses `Valid values are` instead of the canonical `Possible values are` phrasing
- The default value was moved into a detached note block even though it belongs inline in the argument bullet for this case

The modeled page already exists, so the correct workflow is to edit it in place rather than regenerate it from scaffolding.

## Simplified Docs Shape

```markdown
* `sku_name` - (Required) Valid values are `Standard_AzureFrontDoor` and `Premium_AzureFrontDoor`.

-> **Note:** Defaults to `Standard_AzureFrontDoor`.
```

## Expected Guidance

A correct `docs-writer` response should:

- Complete docs preflight and apply the docs contract rather than generic prose cleanup
- Edit the existing page in place instead of treating scaffolding as the default remediation
- Restore canonical `Possible values are` wording
- Move the default value back inline in the argument bullet for this scenario
- Avoid inventing enum, schema, or import-ID claims that are not proven by implementation evidence

## Expected Must-Catch Outcomes

- `canonical-enum-phrasing`
- `inline-default-placement`

## Expected Must-Not-Flag Outcomes

- `guessed-schema-claim`
- `scaffold-existing-page`
