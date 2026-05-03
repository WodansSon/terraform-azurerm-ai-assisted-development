# Sanitized Fixture: Docs Review For Data Source Lookup Examples

This fixture is derived from a real docs-review pattern, but the final artifact is sanitized and does not retain live PR identity.

## Scenario

A data source page modeled as `website/docs/d/example_subnet.html.markdown` is updated to show a minimal lookup example for an existing object.

The modeled page uses identifying arguments only and does not declare the backing subnet, virtual network, or resource group on the same page.

## Simplified Docs Shape

```markdown
## Example Usage

```hcl
data "azurerm_subnet" "example" {
  name                 = "existing-subnet"
  virtual_network_name = "existing-virtual-network"
  resource_group_name  = "existing-resource-group"
}
```
```

## Expected Review Behavior

A correct docs review should:

- Load and apply the docs contract
- Treat `DOCS-EX-022` as authoritative for data source lookup examples
- Accept the example as a valid existing-object lookup pattern
- Avoid requiring backing-resource scaffolding just to make the example look like a resource example

## Expected Must-Catch Outcomes

- `datasource-lookup-standard-applied`

## Expected Must-Not-Flag Outcomes

- `resource-scaffolding-required`
