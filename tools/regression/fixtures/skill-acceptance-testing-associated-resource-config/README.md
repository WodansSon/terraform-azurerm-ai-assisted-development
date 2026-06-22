# Sanitized Fixture: Acceptance-Testing Prefers Complete Setup for Data Source Tests While Allowing Justified Narrower Helpers

This fixture is derived from a real contributor-guidance discussion, but the final artifact is sanitized and does not retain live upstream file contents.

## Scenario

A maintainer asks `acceptance-testing` to review data source acceptance-test config helpers after a contributor discussion about which associated resource helper a data source test should reuse.

The drift is about making the default clearer.
For ordinary data source setup, the associated resource `complete(data)` helper should be the default when it exists because data sources often expose computed fields from the fuller managed-resource shape.
That default should still allow narrower helpers for intentionally narrow scenarios.

## Simplified Test Shape

```go
func (d ExampleDataSource) basic(data acceptance.TestData) string {
    return fmt.Sprintf(`
%s

data "azurerm_example" "test" {
  name = azurerm_example.test.name
}
`, ExampleResource{}.basic(data))
}

func (d ExampleDataSource) narrowLookup(data acceptance.TestData) string {
    return fmt.Sprintf(`
%s

data "azurerm_example" "test" {
  name = azurerm_example.test.name
}
`, ExampleResource{}.basic(data))
}

func (d ExampleDataSource) withOptionalFields(data acceptance.TestData) string {
    return fmt.Sprintf(`
%s

data "azurerm_example" "test" {
  name = azurerm_example.test.name
}
`, ExampleResource{}.complete(data))
}
```

## Expected Guidance

A correct `acceptance-testing` response should:

- prefer `complete(data)` as the default associated resource helper for ordinary data source setup when that helper exists
- explain that a narrower helper like `basic(data)` is still valid for an intentionally narrow scenario
- allow a broader helper like `complete(data)` when the data source scenario genuinely depends on optional or fuller resource state
- reject turning the `complete(data)` preference into an absolute mandate for every data source test

## Expected Must-Catch Outcomes

- `prefer-complete-helper-by-default`
- `allow-narrower-helper-when-justified`

## Expected Must-Not-Flag Outcomes

- `complete-helper-is-an-absolute-mandate`
