# Sanitized Fixture: Local Review Catches Embedded Terraform Formatting Drift In Acceptance Tests This fixture is synthetic and sanitized for regression benchmarking. ## Scenario A local change updates an acceptance-test helper under `internal/services/example/`. The embedded Terraform configuration in the Go heredoc uses tabs at the start of multiple configuration lines and also mixes tabs and spaces inside one line so the block can look aligned in the editor while still violating the repository formatting rule. ## Simplified Code Shape ```go
func (r ExampleResource) basic(data acceptance.TestData) string { return fmt.Sprintf(`
resource "azurerm_example_resource" "test" {
<TAB>name = "acctest-example-%d"
<TAB>resource_group_name = azurerm_example_resource_group.test.name location<TAB><TAB> = azurerm_example_resource_group.test.location <TAB>tags = {
<TAB> environment = "acctest"
<TAB>}
}
`, data.RandomInteger)
}
``` ## Expected Review Behavior A correct local code review should: - activate the Go and acceptance-test review scope rules
- inspect the embedded Terraform string instead of treating the file as ordinary Go-only scope
- flag the mixed indentation in the embedded Terraform block as an issue even if the current tab width makes the block look aligned
- keep the issue scoped to the embedded Terraform heredoc rather than complaining about ordinary Go indentation outside the string
- keep the final overall assessment aligned with the final unresolved issue state instead of mixing a blocking verdict with later prose that says the local state is clean
- report azurerm-linter execution in its dedicated section without pretending that linter success clears the embedded Terraform formatting issue ## Expected Must-Catch Outcomes - `embedded-terraform-mixed-indentation-issue`
- `overall-assessment-aligns-with-final-issues` ## Expected Must-Not-Flag Outcomes - `normal-go-indentation-outside-heredoc`
- `test-execution-required-to-prove-formatting`
- `stale-blocking-verdict-after-fix`
