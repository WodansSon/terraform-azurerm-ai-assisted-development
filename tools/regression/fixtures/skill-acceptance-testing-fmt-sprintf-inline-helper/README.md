# Sanitized Fixture: Acceptance-Testing Inlines One-Use fmt.Sprintf Helper Arguments

This fixture is derived from a real historical acceptance-test guidance incident, but the final artifact is sanitized and does not retain live upstream file contents.

## Scenario

A maintainer asks `acceptance-testing` to clean up Terraform config helper functions in an acceptance-test file.

The current drift includes two helpers that assign a local only to pass it straight into `fmt.Sprintf(...)`, plus one helper where the local is reused and should remain a local.

## Simplified Test Shape

```go
func (r ExampleResource) basic(data acceptance.TestData) string {
    template := r.template(data)
    return fmt.Sprintf(`
%s

resource "azurerm_example_resource" "test" {
  name = "acctest-%d"
}
`, template, data.RandomInteger)
}

func (r ExampleResource) requiresImport(data acceptance.TestData) string {
    config := r.basic(data)
    return fmt.Sprintf(`
%s

resource "azurerm_example_resource" "import" {
  name = azurerm_example_resource.test.name
}
`, config)
}

func (r ExampleResource) complete(data acceptance.TestData) string {
    template := r.template(data)
    extraName := fmt.Sprintf("acctest-extra-%d", data.RandomInteger)
    return fmt.Sprintf(`
%s

resource "azurerm_example_resource" "extra" {
  name = %q
}
`, template, extraName)
}
```

## Expected Guidance

A correct `acceptance-testing` response should:

- inline one-use helper calls like `r.template(data)` or `r.basic(data)` directly into `fmt.Sprintf(...)`
- remove single-use locals that only forward values once into the format call
- keep a local when the helper result is reused or materially improves readability
- avoid over-correcting the reused `template` local in the `complete` helper

## Expected Must-Catch Outcomes

- `single-use-template-local-forwarded`
- `single-use-basic-local-forwarded`

## Expected Must-Not-Flag Outcomes

- `reused-helper-local-must-inline`
