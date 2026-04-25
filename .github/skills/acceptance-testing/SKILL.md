---
name: acceptance-testing
description: Write and troubleshoot terraform-provider-azurerm acceptance tests safely and consistently (BuildTestData, ExistsInAzure, ImportStep, requiresImport). Use when adding or fixing TestAcc* tests.
---

# AzureRM Acceptance Testing (TestAcc)

## Canonical sources of truth (contract-driven)

When writing or troubleshooting acceptance tests under `internal/**/*_test.go`, use `.github/instructions/testing-compliance-contract.instructions.md` as the single source of truth for:

- canonical sources and precedence
- testing compliance requirements
- `TEST-*` rule families

Do not treat this skill as a second independent compliance source.

## Mandatory: read the entire skill

Before applying this skill, read this file to EOF.

## Preflight checklist

Before editing tests with this skill, complete this checklist:

- [ ] I have read this skill to EOF.
- [ ] I have loaded `.github/instructions/testing-compliance-contract.instructions.md` to EOF and applied the relevant `TEST-*` rules.
- [ ] I have identified the closest same-service `_test.go` pattern under `internal/**`.
- [ ] I have identified whether the task needs companion testing guidance from `.github/instructions/testing-guidelines.instructions.md`.

If preflight is incomplete, do not proceed with acceptance-test work.

## Companion guidance

Use this file for worked examples and specialized testing guidance after loading the contract:

- `.github/instructions/testing-guidelines.instructions.md`

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

- Acceptance test framework conventions:
   - `data := acceptance.BuildTestData(t, "azurerm_x", "test")`
   - `r := SomeResource{}`

- Default resource test matrix should cover the core lifecycle:
   - At a minimum, plan for `basic`, `update`, `complete`, and import validation for resource acceptance tests.
   - Only omit one of those when the resource behavior or provider pattern makes it genuinely not applicable.

- Basic tests should validate existence:
   - Primary check should be `check.That(data.ResourceName).ExistsInAzure(r)`.

- Prefer ImportStep:
   - `data.ImportStep()` typically provides broad field validation.
   - Add extra checks only for computed/edge behavior that import cannot verify.

- RequiresImport tests:
   - Add `requiresImport` coverage when appropriate using `data.RequiresImportErrorStep`.

- Do not add acctests for simple property validation by default:
   - If a property validator is already covered adequately by a unit test, do not add an acceptance test only to re-prove that validation.
   - Add an acceptance validation test only when it proves behavior that unit coverage does not, such as broader lifecycle behavior or Azure-specific runtime constraints.

- Add acctests for CustomizeDiff logic:
   - Add targeted acceptance-test coverage for CustomizeDiff validation paths so invalid field combinations and Azure-specific cross-field constraints are not left untested.
   - Prefer `ExpectError` scenarios for the invalid paths, while letting the broader `basic`, `update`, `complete`, and import flows cover the corresponding success paths unless extra assertions are needed.

## Troubleshooting workflow

When a test fails:

- Read the error carefully and identify if it is:
   - auth/environment related
   - eventual consistency / polling
   - schema mismatch
   - cleanup/destroy

- Re-run only the failing test:
   - Use the smallest `-run` scope possible.

- If the failure is a state mismatch:
   - Check expand/flatten symmetry.
   - Confirm ForceNew vs Update behavior.
   - Confirm PATCH behavior (omitted vs explicitly disabled fields).

## Output expectation

When asked to write tests, produce:

- A `basic` TestAcc
- An `update` TestAcc
- A `complete` TestAcc
- Import validation via `ImportStep()`
- `requiresImport` coverage when the resource pattern makes it relevant
