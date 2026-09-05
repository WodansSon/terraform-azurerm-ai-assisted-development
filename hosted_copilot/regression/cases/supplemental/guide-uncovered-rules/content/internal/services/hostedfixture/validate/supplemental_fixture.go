// Copyright IBM Corp. 2014, 2025
// SPDX-License-Identifier: MPL-2.0

package validate

import (
	"github.com/hashicorp/terraform-plugin-sdk/v2/helper/schema"
	"github.com/hashicorp/terraform-plugin-sdk/v2/helper/validation"
)

func SupplementalFixtureName(i interface{}, k string) ([]string, []error) {
	return validation.StringIsNotEmpty(i, k)
}

func SupplementalFixtureResourceGroupName(i interface{}, k string) ([]string, []error) {
	return validation.StringIsNotEmpty(i, k)
}

func SupplementalFixtureRetentionDays(i interface{}, k string) ([]string, []error) {
	return validation.IntBetween(1, 365)(i, k)
}

func SupplementalFixtureTier(i interface{}, k string) ([]string, []error) {
	return validation.StringInSlice([]string{
		"Basic",
		"Premium",
		"Standard",
	}, false)(i, k)
}

var _ schema.SchemaValidateFunc = SupplementalFixtureTier
