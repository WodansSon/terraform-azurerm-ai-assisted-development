# Sanitized Fixture: Acceptance-Testing ImportStep Coverage

This fixture is derived from a real historical acceptance-test guidance incident, but the final artifact is sanitized and does not retain live PR identity.

## Scenario

A maintainer asks `acceptance-testing` to repair lifecycle coverage in `internal/services/example/example_resource_test.go` after a resource change introduced validation behavior.

The current test drift does two things:

- It drops the default `requiresImport` coverage even though the resource still supports import
- It weakens the basic existence check from `ExistsInAzure(r)` to a lighter attribute-only assertion

The request is about restoring the expected acceptance-test shape, not inventing extra assertions on top of `ImportStep()`.

## Simplified Test Shape

```go
func TestAccExampleResource_basic(t *testing.T) {
    data := acceptance.BuildTestData(t, "azurerm_example_resource", "test")
    r := ExampleResource{}

    data.ResourceTest(t, r, []acceptance.TestStep{
        {
            Config: r.basic(data),
            Check: acceptance.ComposeTestCheckFunc(
                check.That(data.ResourceName).Key("name").Exists(),
            ),
        },
        data.ImportStep(),
    })
}
```

## Expected Guidance

A correct `acceptance-testing` response should:

- Load the testing contract rather than treating the problem as generic Go test cleanup
- Preserve default `requiresImport` expectations when the resource supports import
- Keep `check.That(data.ResourceName).ExistsInAzure(r)` as the primary basic existence check
- Keep `data.ImportStep()` for import validation without adding redundant assertions unless the case gives a concrete reason

## Expected Must-Catch Outcomes

- `requiresimport-regression`
- `weakened-basic-existence-check`

## Expected Must-Not-Flag Outcomes

- `redundant-importstep-assertions`
