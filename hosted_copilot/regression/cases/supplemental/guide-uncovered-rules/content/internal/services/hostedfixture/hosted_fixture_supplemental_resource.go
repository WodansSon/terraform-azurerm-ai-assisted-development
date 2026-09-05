// Copyright IBM Corp. 2014, 2025
// SPDX-License-Identifier: MPL-2.0

package hostedfixture

import (
	"context"
	"fmt"
	"log"
	"time"

	"github.com/hashicorp/go-azure-helpers/lang/pointer"
	"github.com/hashicorp/go-azure-helpers/lang/response"
	"github.com/hashicorp/terraform-provider-azurerm/internal/sdk"
	"github.com/hashicorp/terraform-provider-azurerm/internal/services/hostedfixture/validate"
	"github.com/hashicorp/terraform-provider-azurerm/internal/tf/pluginsdk"
)

type SupplementalFixtureResource struct{}

type SupplementalFixtureResourceModel struct {
	Name              string   `tfschema:"name"`
	ResourceGroupName string   `tfschema:"resource_group_name"`
	RetentionDays     int64    `tfschema:"retention_days"`
	Tier              string   `tfschema:"tier"`
	Zones             []string `tfschema:"zones"`
}

func (r SupplementalFixtureResource) ModelObject() interface{} {
	return &SupplementalFixtureResourceModel{}
}

func (r SupplementalFixtureResource) ResourceType() string {
	return "azurerm_hosted_fixture_supplemental"
}

func (r SupplementalFixtureResource) Arguments() map[string]*pluginsdk.Schema {
	return map[string]*pluginsdk.Schema{
		"name": {
			Type:         pluginsdk.TypeString,
			Required:     true,
			ForceNew:     true,
			ValidateFunc: validate.SupplementalFixtureName,
		},

		"resource_group_name": {
			Type:         pluginsdk.TypeString,
			Required:     true,
			ForceNew:     true,
			ValidateFunc: validate.SupplementalFixtureResourceGroupName,
		},

		"retention_days": {
			Type:         pluginsdk.TypeInt,
			Optional:     true,
			Default:      7,
			ValidateFunc: validate.SupplementalFixtureRetentionDays,
		},

		"tier": {
			Type:         pluginsdk.TypeString,
			Optional:     true,
			Default:      "Standard",
			ValidateFunc: validate.SupplementalFixtureTier,
		},

		"zones": {
			Type:     pluginsdk.TypeList,
			Optional: true,
			ForceNew: true,
			Elem: &pluginsdk.Schema{
				Type: pluginsdk.TypeString,
			},
		},
	}
}

func (r SupplementalFixtureResource) Attributes() map[string]*pluginsdk.Schema {
	return map[string]*pluginsdk.Schema{}
}

func (r SupplementalFixtureResource) Create() sdk.ResourceFunc {
	return sdk.ResourceFunc{
		Timeout: 30 * time.Minute,
		Func: func(ctx context.Context, metadata sdk.ResourceMetaData) error {
			client := metadata.Client.HostedFixture.SupplementalClient
			subscriptionId := metadata.Client.Account.SubscriptionId

			// Decode the Terraform configuration into the model struct.
			var config SupplementalFixtureResourceModel
			if err := metadata.Decode(&config); err != nil {
				return fmt.Errorf("decoding: %+v", err)
			}

			id := NewSupplementalFixtureID(subscriptionId, config.ResourceGroupName, config.Name)

			log.Printf("[INFO] Creating %s", id)

			existing, err := client.Get(ctx, id)
			if err != nil && !response.WasNotFound(existing.HttpResponse) {
				return fmt.Errorf("checking for presence of existing %s: %+v", id, err)
			}
			if !response.WasNotFound(existing.HttpResponse) {
				return metadata.ResourceRequiresImport(r.ResourceType(), id)
			}

			// Build the payload that will be sent to the Azure API.
			payload := SupplementalFixture{
				Properties: &SupplementalFixtureProperties{
					RetentionDays: pointer.To(config.RetentionDays),
					Tier:          pointer.To(config.Tier),
					Zones:         pointer.To(config.Zones),
				},
			}

			if err := client.CreateThenPoll(ctx, id, payload); err != nil {
				return fmt.Errorf("creating %s: %+v", id, err)
			}

			metadata.SetID(id)

			return nil
		},
	}
}

func (r SupplementalFixtureResource) Read() sdk.ResourceFunc {
	return sdk.ResourceFunc{
		Timeout: 5 * time.Minute,
		Func: func(ctx context.Context, metadata sdk.ResourceMetaData) error {
			client := metadata.Client.HostedFixture.SupplementalClient

			id, err := ParseSupplementalFixtureID(metadata.ResourceData.Id())
			if err != nil {
				return err
			}

			log.Printf("[INFO] Reading %s", id)

			resp, err := client.Get(ctx, *id)
			if err != nil {
				if response.WasNotFound(resp.HttpResponse) {
					return metadata.MarkAsGone(id)
				}

				return fmt.Errorf("retrieving %s: %+v", *id, err)
			}

			// Map the API response back onto the Terraform model.
			state := SupplementalFixtureResourceModel{
				Name:              id.SupplementalFixtureName,
				ResourceGroupName: id.ResourceGroupName,
			}

			if model := resp.Model; model != nil {
				if props := model.Properties; props != nil {
					state.RetentionDays = pointer.From(props.RetentionDays)
					state.Tier = pointer.From(props.Tier)
					state.Zones = pointer.From(props.Zones)
				}
			}

			return metadata.Encode(&state)
		},
	}
}

func (r SupplementalFixtureResource) Delete() sdk.ResourceFunc {
	return sdk.ResourceFunc{
		Timeout: 30 * time.Minute,
		Func: func(ctx context.Context, metadata sdk.ResourceMetaData) error {
			client := metadata.Client.HostedFixture.SupplementalClient

			id, err := ParseSupplementalFixtureID(metadata.ResourceData.Id())
			if err != nil {
				return err
			}

			log.Printf("[INFO] Deleting %s", id)

			if err := client.DeleteThenPoll(ctx, *id); err != nil {
				return fmt.Errorf("deleting %s: %+v", *id, err)
			}

			return nil
		},
	}
}
