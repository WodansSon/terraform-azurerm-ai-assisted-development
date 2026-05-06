# Sanitized Fixture: Docs Review For List Resource Page Shape

This fixture is derived from a real docs-review pattern, but the final artifact is sanitized and does not retain live PR identity.

## Scenario

A list-resource page modeled as `website/docs/list-resources/example_network_profile.html.markdown` is updated, but the page drifts toward ordinary resource-doc structure.

The modeled page introduces three review-relevant problems:

- The top-level heading uses the ordinary resource form instead of the list-resource title form
- The summary sentence uses resource-style wording instead of list-resource wording
- The example uses a `resource` block instead of a Terraform `list` query block

## Simplified Docs Shape

```markdown
# azurerm_example_network_profile

Manages Example Network Profiles.

## Arguments Reference

The following arguments are supported:

```hcl
resource "azurerm_example_network_profile" "example" {}
```
```

## Expected Review Behavior

A correct docs review should:

- Load and apply the docs contract
- Treat the page as a list-resource docs page under `website/docs/list-resources/`
- Require the list-resource title and summary shape
- Require list query examples using Terraform `list` blocks
- Avoid applying ordinary resource-example self-containedness fixes to the page

## Expected Must-Catch Outcomes

- `list-resource-doc-type-regression`

## Expected Must-Not-Flag Outcomes

- `resource-self-containedness-required`
