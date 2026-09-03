// Copyright IBM Corp. 2014, 2025
// SPDX-License-Identifier: MPL-2.0

package hostedfixture_test

import (
	"context"
	"fmt"
	"testing"

	"github.com/hashicorp/go-azure-helpers/lang/pointer"
	"github.com/hashicorp/terraform-provider-azurerm/internal/acceptance"
	"github.com/hashicorp/terraform-provider-azurerm/internal/acceptance/check"
	"github.com/hashicorp/terraform-provider-azurerm/internal/clients"
	"github.com/hashicorp/terraform-provider-azurerm/internal/tf/pluginsdk"
)

type SupplementalFixtureResource struct{}

func TestAccSupplementalFixture_basic(t *testing.T) {
	data := acceptance.BuildTestData(t, "azurerm_hosted_fixture_supplemental", "test")
	r := SupplementalFixtureResource{}

	data.ResourceTest(t, r, []acceptance.TestStep{
		{
			Config: r.basic(data),
			Check: acceptance.ComposeTestCheckFunc(
				check.That(data.ResourceName).ExistsInAzure(r),
			),
		},
		data.ImportStep(),
	})
}

func TestAccSupplementalFixture_complete(t *testing.T) {
	data := acceptance.BuildTestData(t, "azurerm_hosted_fixture_supplemental", "test")
	r := SupplementalFixtureResource{}

	data.ResourceTest(t, r, []acceptance.TestStep{
		{
			Config: r.complete(data),
			Check: acceptance.ComposeTestCheckFunc(
				check.That(data.ResourceName).ExistsInAzure(r),
			),
		},
		data.ImportStep(),
	})
}

func TestAccSupplementalFixture_requiresImport(t *testing.T) {
	data := acceptance.BuildTestData(t, "azurerm_hosted_fixture_supplemental", "test")
	r := SupplementalFixtureResource{}

	data.ResourceTest(t, r, []acceptance.TestStep{
		{
			Config: r.basic(data),
			Check: acceptance.ComposeTestCheckFunc(
				check.That(data.ResourceName).ExistsInAzure(r),
			),
		},
		data.RequiresImportErrorStep(r.requiresImport),
	})
}

func TestAccSupplementalFixture_update(t *testing.T) {
	data := acceptance.BuildTestData(t, "azurerm_hosted_fixture_supplemental", "test")
	r := SupplementalFixtureResource{}

	data.ResourceTest(t, r, []acceptance.TestStep{
		{
			Config: r.basic(data),
			Check: acceptance.ComposeTestCheckFunc(
				check.That(data.ResourceName).ExistsInAzure(r),
			),
		},
		data.ImportStep(),
		{
			Config: r.complete(data),
			Check: acceptance.ComposeTestCheckFunc(
				check.That(data.ResourceName).ExistsInAzure(r),
			),
		},
		data.ImportStep(),
	})
}

func (r SupplementalFixtureResource) Exists(ctx context.Context, client *clients.Client, state *pluginsdk.InstanceState) (*bool, error) {
	id, err := ParseSupplementalFixtureID(state.ID)
	if err != nil {
		return nil, err
	}

	resp, err := client.HostedFixture.SupplementalClient.Get(ctx, *id)
	if err != nil {
		return nil, fmt.Errorf("retrieving %s: %+v", *id, err)
	}

	return pointer.To(resp.Model != nil), nil
}

func (r SupplementalFixtureResource) basic(data acceptance.TestData) string {
	template := r.template(data)

	return fmt.Sprintf(`
%s

resource "azurerm_hosted_fixture_supplemental" "test" {
  name                = "acctestsf-%[2]d"
  resource_group_name = azurerm_resource_group.test.name
}
`, template, data.RandomInteger)
}

func (r SupplementalFixtureResource) complete(data acceptance.TestData) string {
	return fmt.Sprintf(`
%s

resource "azurerm_hosted_fixture_supplemental" "test" {
  name                = "acctestsf-%[2]d"
  resource_group_name = azurerm_resource_group.test.name
  retention_days      = 30
  tier                = "Premium"
  zones               = ["1", "2"]
}
`, r.template(data), data.RandomInteger)
}

func (r SupplementalFixtureResource) requiresImport(data acceptance.TestData) string {
	return fmt.Sprintf(`
%s

resource "azurerm_hosted_fixture_supplemental" "import" {
  name                = azurerm_hosted_fixture_supplemental.test.name
  resource_group_name = azurerm_hosted_fixture_supplemental.test.resource_group_name
}
`, r.basic(data))
}

func (r SupplementalFixtureResource) template(data acceptance.TestData) string {
	return fmt.Sprintf(`
provider "azurerm" {
  features {}
}

resource "azurerm_resource_group" "test" {
  name     = "acctestRG-sf-%[1]d"
  location = "%[2]s"
}
`, data.RandomInteger, data.Locations.Primary)
}
