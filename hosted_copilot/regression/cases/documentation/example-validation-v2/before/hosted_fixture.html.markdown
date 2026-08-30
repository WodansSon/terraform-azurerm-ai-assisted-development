---
subcategory: "Hosted Fixture"
layout: "azurerm"
page_title: "Azure Resource Manager: azurerm_hosted_fixture"
description: |-
  Manages a Hosted Fixture.
---

# azurerm_hosted_fixture

Manages a Hosted Fixture.

## Example Usage

```hcl
resource "azurerm_hosted_fixture" "example" {
  account_tier = "Standard"
}
```

## Arguments Reference

The following arguments are supported:

* `account_tier` - (Required) The account tier. Possible values are `Standard`, `Premium`, and `Ultra`.

## Attributes Reference

In addition to the Arguments listed above - the following Attributes are exported:

* `id` - The ID of the Hosted Fixture.

## Import

A Hosted Fixture can be imported using the `resource id`, e.g.

```shell
terraform import azurerm_hosted_fixture.example /subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/example/providers/Microsoft.Example/hostedFixtures/example
```
