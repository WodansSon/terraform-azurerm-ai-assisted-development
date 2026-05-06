# Sanitized Fixture: Docs Review For Function Page Shape

This fixture is derived from a real docs-review pattern, but the final artifact is sanitized and does not retain live PR identity.

## Scenario

A function page modeled as `website/docs/functions/example_parse_resource_id.html.markdown` is updated, but the page drifts toward ordinary resource-doc structure.

The modeled page introduces three review-relevant problems:

- The top-level heading uses the ordinary resource form instead of the function title form
- The provider-defined function runtime-support note is missing
- The example does not call the function through `provider::azurerm::...`

## Simplified Docs Shape

```markdown
# azurerm_example_parse_resource_id

Manages Example Parse Resource IDs.

## Arguments Reference

The following arguments are supported:

```hcl
data "azurerm_client_config" "example" {}
```
```

## Expected Review Behavior

A correct docs review should:

- Load and apply the docs contract
- Treat the page as a function docs page under `website/docs/functions/`
- Require the function title and provider-defined function runtime-support note
- Require `provider::azurerm::<name>(...)` examples and the `Signature` / `Arguments` structure
- Avoid treating a provider block in a function example as automatically invalid

## Expected Must-Catch Outcomes

- `function-doc-type-regression`

## Expected Must-Not-Flag Outcomes

- `provider-block-prohibited`
