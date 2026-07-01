# Sanitized Fixture: Docs Review For Ephemeral Resource Page Shape This fixture is synthetic and sanitized for regression benchmarking. ## Scenario An ephemeral-resource page modeled as `website/docs/ephemeral-resources/example_secret.html.markdown` is updated, but the page drifts toward ordinary resource-doc structure. The modeled page introduces three review-relevant problems: - The top-level heading uses the ordinary resource form instead of the ephemeral-resource title form
- The Terraform-version support note is missing
- The example uses a `resource` block instead of a Terraform `ephemeral` block ## Simplified Docs Shape ```markdown
# azurerm_example_secret Manages Example Secrets. ## Example Usage ```hcl
resource "azurerm_example_secret" "example" {}
```
``` ## Expected Review Behavior A correct docs review should: - Load and apply the docs contract
- Treat the page as an ephemeral-resource docs page under `website/docs/ephemeral-resources/`
- Require the ephemeral-resource title and Terraform 1.10 support note
- Require `ephemeral` query examples using Terraform `ephemeral` blocks
- Avoid requiring an ordinary managed-resource `Import` section ## Expected Must-Catch Outcomes - `ephemeral-doc-type-regression` ## Expected Must-Not-Flag Outcomes - `managed-resource-import-required`
