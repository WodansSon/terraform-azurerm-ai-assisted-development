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

For legacy polling migrations under `internal/**/*.go`, also use:

- `.github/skills/custom-poller-migration/SKILL.md`

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
- For new resources, plan Resource Identity first and a corresponding list resource immediately after it unless there is a concrete upstream-supported exception.
- For ephemeral resources, use the service-local `*_ephemeral.go` pattern with `sdk.EphemeralResource`, `Open(...)`, and registration through `EphemeralResources()`.
- For provider-defined functions, use the `internal/provider/function/` pattern with `Metadata`, `Definition`, and `Run`.
- Make changes consistent with existing resources in the same service.

## Workflow (recommended)

- Find similar existing implementations:
   - Locate the closest resource(s) by service and complexity.
   - Mirror patterns for schema layout, expand/flatten, timeouts, and tests.

- Confirm API model structure before mapping fields:
   - Do not guess types or required properties.
   - When needed, inspect the Azure SDK model structs or the provider’s generated clients.

- New-resource workflow expectations:
   - Treat Resource Identity as mandatory for new resources.
   - Treat the list resource as mandatory for new resources by default.
   - Treat the primary resource docs and the list-resource docs as mandatory companions for new resources.
   - If no list API exists, do not silently omit the list resource; call out the exception path and the need for maintainer-reviewed `allow-without-list` or `list-not-supported` labeling.

- Existing-resource list-retrofit expectations:
   - When the task is to add list support to an existing resource, plan Resource Identity, the `*_resource_list.go` implementation, service registration, list-query tests, and list-resource docs together.
   - Do not treat registration, tests, or list-resource docs as optional follow-up work once the list-support retrofit is in scope.

- Ephemeral-resource workflow expectations:
   - Implement the object as `*_ephemeral.go` under the owning service package.
   - Register it through the service `EphemeralResources()` slice.
   - Plan the companion docs under `website/docs/ephemeral-resources/` and acceptance coverage in `*_ephemeral_test.go`.

- Provider-defined function workflow expectations:
   - Implement the function under `internal/provider/function/<name>.go`.
   - Expose its contract through `Definition(...)` and keep docs/tests aligned to that contract.
   - Plan the companion docs under `website/docs/functions/` and unit coverage under `internal/provider/function/*_test.go`.

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

- Polling migrations:
   - When the task involves replacing `pluginsdk.Retry()`, `pluginsdk.StateChangeConf`, or `WaitForStateContext()`, consult `custom-poller-migration` instead of inventing a one-off migration structure.
   - Preserve polling parity unless the user explicitly approves a behavior change.

- Tests:
   - Add or adjust tests when implementation behavior changes materially.
   - For new resources that add a list resource, plan a dedicated `*_resource_list_test.go` query-test path in addition to the resource lifecycle tests.
   - For acceptance-test-specific guidance, use the testing compliance contract and the `acceptance-testing` skill instead of treating this skill as the source of detailed acctest patterns.

- Documentation companions:
   - For new resources, plan the primary resource docs plus the corresponding list-resource docs under `website/docs/list-resources/`.
   - Do not treat list-resource docs as optional when the list resource itself is required.

## Output expectation

When asked to implement something, provide:

- A short plan (files to touch)
- The schema + CRUD mapping decisions
- The minimal set of code changes needed
- How you validated (build/tests)
