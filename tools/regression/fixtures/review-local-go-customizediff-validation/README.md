# Sanitized Fixture: Local Go Review For Validation Coverage

This fixture is derived from a real review pattern, but the final artifact is sanitized and does not retain live PR identity.

## Scenario

A local Go change updates resource validation behavior in a provider resource under `internal/services/network/`.

The change adds or tightens validation logic in the implementation, but the paired acceptance-test file does not add a targeted test that exercises the new invalid combination or validation path.

## Simplified Code Shape

```go
"sku_name": {
    Type:         pluginsdk.TypeString,
    Optional:     true,
    ValidateFunc: validation.StringIsNotEmpty,
}

CustomizeDiff: pluginsdk.CustomDiffWithAll(
    pluginsdk.CustomizeDiffShim(func(ctx context.Context, diff *pluginsdk.ResourceDiff, meta interface{}) error {
        if diff.Get("sku_name").(string) == "Premium" && !diff.Get("zone_redundant").(bool) {
            return fmt.Errorf("`zone_redundant` must be `true` for `Premium` SKU")
        }

        return nil
    }),
)
```

Test file shape:

```go
func TestAccExampleGateway_basic(t *testing.T) {
    // existing lifecycle coverage only
}
```

## Expected Review Behavior

A correct local code review should:

- activate the Go and test review scope rules
- recognize that implementation-side validation behavior changed
- flag the missing targeted acceptance-test coverage as the primary issue
- avoid turning generic `StringIsNotEmpty` usage into a separate issue unless the fixture evidence proves stronger validation is required for that field
- report azurerm-linter execution in its dedicated section

## Expected Must-Catch Outcomes

- `missing-validation-coverage`

## Expected Must-Not-Flag Outcomes

- `stringisnotempty-alone-without-context`
