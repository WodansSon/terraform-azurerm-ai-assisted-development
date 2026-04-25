---
name: resource-implementation
description: Implement or modify Terraform AzureRM provider resources/data sources following provider patterns (typed SDK, error formats, PATCH behavior). Use when adding support for a new Azure resource or changing schema/CRUD logic.
---

# AzureRM Resource Implementation (Provider Patterns)

## Canonical sources of truth (contract-driven)

When implementing or modifying provider code under `internal/**`, use `.github/instructions/implementation-compliance-contract.instructions.md` as the single source of truth for:

- canonical sources and precedence
- implementation compliance requirements
- `IMPL-*` rule families

Do not treat this skill as a second independent compliance source.

## Mandatory: read the entire skill

Before applying this skill, read this file to EOF.

## Preflight checklist

Before editing code with this skill, complete this checklist:

- [ ] I have read this skill to EOF.
- [ ] I have loaded `.github/instructions/implementation-compliance-contract.instructions.md` to EOF and applied the relevant `IMPL-*` rules.
- [ ] I have identified the closest same-service implementation pattern under `internal/**`.
- [ ] I have identified which companion guidance files I need for this task (schema, PATCH behavior, error handling, testing, or provider guidance).

If preflight is incomplete, do not proceed with implementation work.

## Companion guidance

Use these files for worked examples and specialized implementation guidance after loading the contract:

- `.github/instructions/implementation-guide.instructions.md`
- `.github/instructions/azure-patterns.instructions.md`
- `.github/instructions/schema-patterns.instructions.md`
- `.github/instructions/error-patterns.instructions.md`
- `.github/instructions/provider-guidelines.instructions.md`
- `.github/instructions/code-clarity-enforcement.instructions.md`

For acceptance-test-specific work under `internal/**/*_test.go`, use the testing compliance contract and the `acceptance-testing` skill instead of treating this skill as the test authority.

## Scope

Intended for use with the HashiCorp `terraform-provider-azurerm` repository (Go code under `internal/`).

Use this skill when implementing or modifying AzureRM provider code under `internal/`, especially when:

- adding a new resource/data source
- updating schema fields or validation
- working with Azure PATCH behavior / residual state
- wiring up CRUD operations and polling

## Verification (assistant response only)

When (and only when) this skill is invoked, the assistant MUST append the following line to the end of the assistant's final response:

Skill used: resource-implementation

Rules:
- Do NOT write this marker into any repository file (docs, code, generated files).
- If multiple skills are invoked, each skill should append its own `Skill used: ...` line.
- Do NOT emit the marker in intermediate/progress updates; only in the final response.

## Template tokens (placeholders)

When you need a placeholder in examples or guidance, always use the explicit token format `{{TOKEN_NAME}}`.

Rules:
- Use ALL-CAPS token names with underscores (for example `{{RESOURCE_NAME}}`, `{{API_VERSION}}`).
- Do not use ambiguous placeholders like `<name>` or `...`.
- Do not leave tokens in final repository output; tokens are for skill guidance/examples only.
- If any `{{...}}` token would appear in final output, replace it before responding.

## Default approach

- Prefer the **typed resource** implementation style (internal SDK framework) for new resources.
- Make changes consistent with existing resources in the same service.

## Workflow (recommended)

- Find similar existing implementations:
   - Locate the closest resource(s) by service and complexity.
   - Mirror patterns for schema layout, expand/flatten, timeouts, and tests.

- Confirm API model structure before mapping fields:
   - Do not guess types or required properties.
   - When needed, inspect the Azure SDK model structs or the provider’s generated clients.

- Schema design:
   - Required vs Optional must reflect real API requirements and provider conventions.
   - Treat `tags` consistently and keep it last.
   - Use consistent validation and error message formats.

- PATCH/residual state rules:
   - Omitted fields in PATCH often preserve prior values.
   - If disabling a feature, set explicit `enabled=false` (do not rely on omission).

- Error handling:
   - Use lowercase, descriptive error messages.
   - Wrap field names and important values in backticks.
   - Use `errors.New(...)` for static errors that do not need formatting or wrapping.
   - Use `fmt.Errorf(...)` when formatting values or wrapping an underlying error, and use `%+v` for the wrapped underlying error.

- Tests:
   - Add or adjust tests when implementation behavior changes materially.
   - For acceptance-test-specific guidance, use the testing compliance contract and the `acceptance-testing` skill instead of treating this skill as the source of detailed acctest patterns.

## Output expectation

When asked to implement something, provide:

- A short plan (files to touch)
- The schema + CRUD mapping decisions
- The minimal set of code changes needed
- How you validated (build/tests)
