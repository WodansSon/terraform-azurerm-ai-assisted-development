# Regression Test

This directory stores contributor-facing HCL test specs for the regression harness.

Terraform contributors should be able to read this directory as the harness equivalent of an acceptance-test surface: author one HCL test spec here, then let the scaffolding tools generate the internal JSON and Markdown artifacts.

The accepted blocks, fields, and enum values for this DSL are codified in `tools/regression/test/TestSpecDefinition.ps1`.

The canonical form uses real nested HCL inside `test_case { config { ... } }`.

## Minimal Shape

```hcl
AccTest "example-case" "basic" {
  title       = "Example benchmark title"

  test_case {
    task        = "resource-implementation"
    source_kind = "real-pr"
    case_status = "planned"
    notes       = "Optional scope notes."

    changed_files = [
      "internal/services/example/example_resource.go",
    ]

    config {
      resource "azurerm_example_resource" "test" {
        name = "example"
      }
    }
  }

  rules {
    description           = "Plain-language scenario description."
    notes                 = "Optional maintainer notes."
    include_sample_output = false

    must_catch {
      description = "Prefer stronger validation when the accepted values are knowable."
      severity    = "medium"
      file        = "internal/services/example/example_resource.go"
    }

    must_not_flag {
      description = "Do not invent unsupported schema constraints."
    }
  }
}
```

## Shape Notes

- `AccTest "case-id" "run-name"` is the canonical top-level block for this DSL.
- `test_case` holds the benchmark metadata and the test configuration in one normal HCL section instead of hanging them off a synthetic runner block.
- The second top-level label carries the run name, so the inner `test_case` and `rules` blocks stay unlabeled.
- `config` lives under `test_case` and holds real nested HCL blocks instead of wrapping Terraform configuration in a string attribute.
- `rules` describes what that named config should or should not trigger in the harness result.

## Build Flow

1. Create a template with `new-regression-test.ps1` or write the HCL test manually.
2. Materialize the internal harness artifacts with `build-regression-test.ps1 -SpecPath ...`.
3. Review and refine the generated drafts.
4. Promote the reviewed drafts with `publish-regression-test.ps1`.
