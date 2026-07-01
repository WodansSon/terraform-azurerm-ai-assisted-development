# Sanitized Fixture: Docs-Writer List Resource Page Shape This fixture is synthetic and sanitized for regression benchmarking. ## Scenario A maintainer asks `docs-writer` to fix an existing list-resource page modeled as `website/docs/list-resources/example_network_profile.html.markdown`. The modeled page already exists, so the correct workflow is to edit it in place rather than regenerate it from scaffolding. The page has three contract-relevant drifts: - The top-level heading uses ordinary resource-doc syntax instead of the list-resource title form
- The summary sentence uses `Manages...` instead of `Lists... resources.`
- The primary example uses a `resource` block instead of a Terraform `list` query block ## Simplified Docs Shape ```markdown
# azurerm_example_network_profile Manages Example Network Profiles. ## Arguments Reference The following arguments are supported: ```hcl
resource "azurerm_example_network_profile" "example" {}
```
``` ## Expected Guidance A correct `docs-writer` response should: - Complete docs preflight and apply the docs contract rather than generic prose cleanup
- Edit the existing page in place instead of treating scaffolding as the default remediation
- Restore the list-resource title and summary shape
- Restore the list-resource `Argument Reference` structure and intro line
- Replace the example with a Terraform `list` query example for the list resource ## Expected Must-Catch Outcomes - `list-resource-title-summary`
- `list-query-example-form` ## Expected Must-Not-Flag Outcomes - `scaffold-existing-page`
