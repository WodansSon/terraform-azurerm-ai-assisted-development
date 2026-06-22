# Sanitized Fixture: Acceptance-Testing Helper Struct Naming Stays Canonical Across Test Variants

This fixture is derived from a real historical acceptance-test guidance incident, but the final artifact is sanitized and does not retain live upstream file contents.

## Scenario

A maintainer asks `acceptance-testing` to fix helper-struct naming drift after acceptance tests and generated identity tests stopped using the same canonical helper type.

Different test variants for the same Terraform surface started using different helper types, while the generated identity test still instantiated a separate `SomethingIdentityResource` helper.

That drift caused `go generate` to rewrite the generated identity file and made Generation Check fail.

## Simplified Test Shape

```go
func TestAccExampleResource_basic(t *testing.T) {
    data := acceptance.BuildTestData(t, "azurerm_example_resource", "test")
    r := ExampleResource{}

    data.ResourceTest(t, r, []acceptance.TestStep{
        {
            Config: r.basic(data),
            Check: acceptance.ComposeTestCheckFunc(
                check.That(data.ResourceName).ExistsInAzure(r),
            ),
        },
    })
}

func TestAccExampleResource_listQuery(t *testing.T) {
    data := acceptance.BuildTestData(t, "azurerm_example_resource", "test")
    r := ExampleListResource{}

    data.ResourceTest(t, r, []acceptance.TestStep{
        {
            Config: r.basic(data),
        },
    })
}

func TestAccExampleDataSource_basic(t *testing.T) {
    data := acceptance.BuildTestData(t, "azurerm_example", "test")
    d := ExampleLookupDataSource{}

    data.DataSourceTest(t, []acceptance.TestStep{
        {
            Config: d.basic(data),
        },
    })
}

func TestAccExampleResourceIdentity_generated(t *testing.T) {
    data := acceptance.BuildTestData(t, "azurerm_example_resource", "test")
    r := ExampleIdentityResource{}

    data.ResourceTest(t, r, []acceptance.TestStep{
        {
            Config: r.basic(data),
        },
    })
}
```

## Expected Guidance

A correct `acceptance-testing` response should:

- keep one canonical helper struct name aligned to the Terraform surface across all test variants for that surface
- preserve the established canonical helper type when the surface already has one
- prefer `ToCamel(x)Resource` for new resource surfaces and `ToCamel(x)DataSource` for new data source surfaces that do not yet have an established helper type
- reject alternate helper names introduced only because a test lives in a different handwritten file such as a list test or identity-related test
- require generated identity tests under `*_identity_gen_test.go` to instantiate that same helper type directly
- reject separate `SomethingIdentityResource` helpers, alias types, adapters, or wrapper structs as a fix
- explain that stable helper naming across all acceptance tests and generated identity tests is needed so `go generate` produces no diff and Generation Check stays green

## Durable Task Example

Durable Task is the concrete example for why this rule exists:

- canonical helper types for the Terraform surfaces were names like `DurableTaskHubResource` and `DurableTaskRetentionPolicyResource`
- other test variants drifted toward alternate helper naming instead of reusing those canonical types
- generated identity tests still instantiated `DurableTaskHubIdentityResource` and `DurableTaskRetentionPolicyIdentityResource`
- that mismatch caused generated files to churn until the generated identity tests were updated to use the canonical helper type directly

## Expected Must-Catch Outcomes

- `helper-struct-name-generator-drift`
- `canonical-helper-drift-across-variants`
- `generated-identity-helper-type-drift`

## Expected Must-Not-Flag Outcomes

- `adapter-bridge-acceptable`
- `independent-identity-helper-name`
- `forced-rename-established-helper-to-goal-pattern`
