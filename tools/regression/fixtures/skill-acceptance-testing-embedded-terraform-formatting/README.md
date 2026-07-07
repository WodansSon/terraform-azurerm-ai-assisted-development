# Sanitized Fixture: Acceptance-Testing Fixes Embedded Terraform Heredoc Indentation Drift This fixture is synthetic and sanitized for regression benchmarking. ## Scenario A maintainer asks `acceptance-testing` to repair an acceptance-test helper in a `*_test.go` file after CI rejected the embedded Terraform formatting. The Terraform heredoc uses tabs for indentation and also mixes tabs and spaces inside a configuration line so the block can look aligned in an editor with Terraform-sized tab rendering even though the repository formatting checks still reject it. ## Simplified Test Shape ```go
func (r ExampleResource) basic(data acceptance.TestData) string { return fmt.Sprintf(`
resource "azurerm_example_resource" "test" {
<TAB>name = "acctest-example-%d"
<TAB>resource_group_name = azurerm_example_resource_group.test.name location<TAB><TAB> = azurerm_example_resource_group.test.location <TAB>tags = {
<TAB> environment = "acctest"
<TAB>}
}
`, data.RandomInteger)
}
``` ## Expected Guidance A correct `acceptance-testing` response should: - require two-space indentation for Terraform configuration lines inside the embedded heredoc
- reject tabs and mixed tabs-plus-spaces inside embedded Terraform indentation, even when the current editor renders the block as if it were aligned
- preserve the surrounding heredoc shape instead of rewriting unrelated Go helper structure
- point to the companion `Embedded Terraform Formatting` examples when indentation is ambiguous because of tab rendering
- avoid treating ordinary Go indentation outside the heredoc as the formatting problem ## Expected Must-Catch Outcomes - `embedded-terraform-two-space-indentation`
- `mixed-indentation-hidden-by-tab-rendering` ## Expected Must-Not-Flag Outcomes - `normal-go-indentation-outside-heredoc`
