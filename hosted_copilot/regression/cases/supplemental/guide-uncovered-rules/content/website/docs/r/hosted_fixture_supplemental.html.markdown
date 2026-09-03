---
subcategory: "Base"
layout: "azurerm"
page_title: "Azure Resource Manager: azurerm_hosted_fixture_supplemental"
description: |-
  Manages a Supplemental Fixture.
---

# azurerm_hosted_fixture_supplemental

Manages a Supplemental Fixture.

## Example Usage

```hcl
resource "azurerm_resource_group" "example" {
  name     = "example-resources"
  location = "West Europe"
}

resource "azurerm_hosted_fixture_supplemental" "example" {
  name                = "example-fixture"
  resource_group_name = azurerm_resource_group.example.name
  retention_days      = 30
  tier                = "Premium"

  zones {
    value = "1"
  }
}
```

## Arguments Reference

The following arguments are supported:

* `name` - (Required) The name which should be used for this Supplemental Fixture. Changing this forces a new resource to be created.

* `resource_group_name` - (Required) The name of the resource group in which the Supplemental Fixture should exist. Changing this forces a new resource to be created.

---

* `retention_days` - (Optional) The number of days data is retained for. Possible values range between `1` and `365`. Defaults to `7`.

* `tier` - (Optional) The service tier of this Supplemental Fixture. Possible values are `Basic`, `Premium`, and `Standard`. Defaults to `Standard`.

* `zones` - (Optional) A `zones` block as defined above. Changing this forces a new resource to be created.

~> **Note:** The argument `retention_days` can only exceed `90` when `tier` is set to `Premium`.

~> **Note:** Setting `tier` to a value other than `Premium` limits `retention_days` to `90` or fewer.

-> **Note:** More information on availability zone placement is available in the [availability zone documentation](https://learn.microsoft.com/en-us/azure/reliability/availability-zones-overview).

---

A `zones` block supports the following:

* `value` - (Required) The availability zone to place this Supplemental Fixture in. Changing this forces a new resource to be created.

## Attributes Reference

In addition to the Arguments listed above - the following Attributes are exported:

* `name` - The name of this Supplemental Fixture.

* `resource_group_name` - The name of the resource group this Supplemental Fixture belongs to.

* `id` - The ID of this Supplemental Fixture.

## Timeouts

The `timeouts` block allows you to specify [timeouts](https://developer.hashicorp.com/terraform/language/resources/configure#define-operation-timeouts) for certain actions:

* `create` - (Defaults to 30 minutes) Used when creating the Supplemental Fixture.
* `read` - (Defaults to 5 minutes) Used when retrieving the Supplemental Fixture.
* `delete` - (Defaults to 30 minutes) Used when deleting the Supplemental Fixture.

## Import

Supplemental Fixtures can be imported using the `resource id`, e.g.

```shell
terraform import azurerm_hosted_fixture_supplemental.example /subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/example-resources/providers/Microsoft.HostedFixture/supplementalFixtures/example-fixture
```
