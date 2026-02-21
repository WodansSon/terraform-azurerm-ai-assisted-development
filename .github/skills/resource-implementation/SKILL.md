---
name: resource-implementation
description: Implement or modify Terraform AzureRM provider resources/data sources following provider patterns (typed SDK, error formats, PATCH behavior). Use when adding support for a new Azure resource or changing schema/CRUD logic.
---

# AzureRM Resource Implementation (Provider Patterns)

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

1. Find similar existing implementations
   - Locate the closest resource(s) by service and complexity.
   - Mirror patterns for schema layout, expand/flatten, timeouts, and tests.

2. Confirm API model structure before mapping fields
   - Do not guess types or required properties.
   - When needed, inspect the Azure SDK model structs or the provider’s generated clients.

3. Schema design
   - Required vs Optional must reflect real API requirements and provider conventions.
   - Treat `tags` consistently and keep it last.
   - Use consistent validation and error message formats.

4. PATCH/residual state rules
   - Omitted fields in PATCH often preserve prior values.
   - If disabling a feature, set explicit `enabled=false` (do not rely on omission).

5. Error handling
   - Use lowercase, descriptive error messages.
   - Wrap field names and important values in backticks.
   - Use `%+v` for underlying errors.

6. Tests
   - Add/adjust acceptance tests where appropriate.
   - Prefer `ImportStep()` for validation plus `ExistsInAzure` for existence.

## Output expectation

When asked to implement something, provide:

- A short plan (files to touch)
- The schema + CRUD mapping decisions
- The minimal set of code changes needed
- How you validated (build/tests)
