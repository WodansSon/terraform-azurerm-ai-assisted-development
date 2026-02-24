---
name: acceptance-testing
description: Write and troubleshoot terraform-provider-azurerm acceptance tests safely and consistently (BuildTestData, ExistsInAzure, ImportStep, requiresImport). Use when adding or fixing TestAcc* tests.
---

# AzureRM Acceptance Testing (TestAcc)

## Verification (assistant response only)

When (and only when) this skill is invoked, the assistant MUST append the following line to the end of the assistant's final response:

Skill used: acceptance-testing

Rules:
- Do NOT write this marker into any repository file (docs, code, generated files).
- If multiple skills are invoked, each skill should append its own `Skill used: ...` line.
- Do NOT emit the marker in intermediate/progress updates; only in the final response.

## Template tokens (placeholders)

When you need a placeholder in examples or guidance, always use the explicit token format `{{TOKEN_NAME}}`.

Rules:
- Use ALL-CAPS token names with underscores (for example `{{RESOURCE_NAME}}`, `{{TEST_NAME}}`).
- Do not use ambiguous placeholders like `<name>` or `...`.
- Do not leave tokens in final repository output; tokens are for skill guidance/examples only.
- If any `{{...}}` token would appear in final output, replace it before responding.

## Safety first

Intended for use with the HashiCorp `terraform-provider-azurerm` repository (acceptance test framework under `internal/`).

Acceptance tests create real Azure resources and can incur cost.

Before running tests:

- Confirm credentials are configured.
- Prefer narrow test runs (single test) over running the full suite.
- Ensure cleanup/destroy behavior is covered.

## Core patterns to follow

1. Use the acceptance test framework conventions
   - `data := acceptance.BuildTestData(t, "azurerm_x", "test")`
   - `r := SomeResource{}`

2. Basic test should validate existence
   - Primary check should be `check.That(data.ResourceName).ExistsInAzure(r)`.

3. Prefer ImportStep
   - `data.ImportStep()` typically provides broad field validation.
   - Add extra checks only for computed/edge behavior that import cannot verify.

4. RequiresImport test
   - Add `requiresImport` coverage when appropriate using `data.RequiresImportErrorStep`.

## Troubleshooting workflow

When a test fails:

1. Read the error carefully and identify if it is:
   - auth/environment related
   - eventual consistency / polling
   - schema mismatch
   - cleanup/destroy

2. Re-run only the failing test
   - Use the smallest `-run` scope possible.

3. If the failure is a state mismatch
   - Check expand/flatten symmetry.
   - Confirm ForceNew vs Update behavior.
   - Confirm PATCH behavior (omitted vs explicitly disabled fields).

## Output expectation

When asked to write tests, produce:

- A minimal `basic` TestAcc
- Import validation via `ImportStep()`
- Any required negative cases (`requiresImport`, update scenarios) only when they add value
