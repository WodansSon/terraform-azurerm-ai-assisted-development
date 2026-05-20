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
- For new resources, treat Resource Identity as mandatory and treat the corresponding list resource as mandatory unless the documented maintainer exception path is explicitly used.
- For ephemeral resources, use the service-local `*_ephemeral.go` pattern with `sdk.EphemeralResource`, `Open(...)`, and registration through `EphemeralResources()`.
- For provider-defined functions, use the `internal/provider/function/` pattern with `Metadata`, `Definition`, and `Run`.
- Make changes consistent with existing resources in the same service.

## Quick implementation anchors

Keep these compact patterns in working memory during implementation sessions:

```go
// Typed resource quick template
type ServiceNameResourceModel struct {
   Name          string            `tfschema:"name"`
   ResourceGroup string            `tfschema:"resource_group_name"`
   Location      string            `tfschema:"location"`
   Tags          map[string]string `tfschema:"tags"`
   Id            string            `tfschema:"id"`
}

// PATCH operation quick pattern
func ExpandFeature(input []interface{}) *azuretype.Feature {
   result := &azuretype.Feature{
      Enabled: pointer.To(false),
   }
   if len(input) > 0 && input[0] != nil {
      result.Enabled = pointer.To(true)
   }
   return result
}

// Static error pattern
return errors.New("unexpected empty response")

// Wrapped error pattern
return fmt.Errorf("creating %s: %+v", id, err)
```

## Workflow (recommended)

- Find similar existing implementations:
   - Locate the closest resource(s) by service and complexity.
   - Mirror patterns for schema layout, expand/flatten, timeouts, and tests.

- Confirm API model structure before mapping fields:
   - Do not guess types or required properties.
   - When needed, inspect the Azure SDK model structs or the provider’s generated clients.

- New-resource workflow expectations:
   - Treat Resource Identity as mandatory for new resources.
   - If current resource-identity generator caveats or unsupported identity shapes mean Resource Identity genuinely cannot be implemented, explain that in the PR instead of silently omitting it.
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
   - Reuse shared validators first, keep short helper composition inline, and for new or materially updated bespoke `ValidateFunc` logic move it into the same service's `validate/` folder as a file-specific validator with matching unit coverage instead of relying on long anonymous inline closures.
   - Do not spend scope churning untouched legacy validator placement unless the task is already modifying that validator.

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

## Surface-specific targets

Keep the implementation targets aligned to the surface type. Do not assume all framework-style work uses the same client, registration, test, or documentation targets.

- Ordinary resource or data source:
   - implementation target: service-local resource or data source file under `internal/services/<service>/`
   - registration target: service `registration.go` through the ordinary `DataSources()`, `Resources()`, `SupportedDataSources()`, or `SupportedResources()` methods already used by that service
   - client target: usually the service-local `client/client.go` plus `internal/clients/client.go` only when the Azure API dependency requires new client wiring
   - docs target: `website/docs/r/` or `website/docs/d/`
   - test target: the ordinary `*_resource_test.go` or `*_data_source_test.go` path

- List resource:
   - implementation target: `*_resource_list.go`
   - registration target: service `registration.go` through `ListResources()`
   - client target: normally reuse the parent service client and the parent resource's Azure client wiring; do not assume a new `internal/clients/client.go` entry is required unless the list implementation needs a new Azure client
   - docs target: `website/docs/list-resources/`
   - test target: `*_resource_list_test.go`

- Ephemeral resource:
   - implementation target: `*_ephemeral.go`
   - registration target: service `registration.go` through `EphemeralResources()`
   - client target: usually reuse the owning service's client wiring rather than inventing a separate client shape just because the surface is ephemeral
   - docs target: `website/docs/ephemeral-resources/`
   - test target: `*_ephemeral_test.go`

- Provider-defined function:
   - implementation target: `internal/provider/function/<name>.go`
   - registration target: the provider-function surface, not service-package `registration.go`
   - client target: do not assume `internal/clients/client.go` or a service-local `client/client.go` applies; many provider-defined functions rely on provider-level helpers or parsers instead of service client wiring
   - docs target: `website/docs/functions/`
   - test target: `internal/provider/function/*_test.go`

- Brand-new service package:
   - implementation targets: service-local `registration.go`, service-local `client/client.go`, the relevant implementation files, and the provider-level service/client registration surfaces
   - provider registration target: the relevant handwritten supported-service slices in `internal/provider/services.go`; do not invent a generic `SupportedFrameworkServices()` path
   - client target: both the service-local client definition and the required import, struct-field, and build-path updates in `internal/clients/client.go`
   - PR companion targets: include the generated labeler, TeamCity, and allowed-subcategory outputs when upstream workflow regenerates them from the handwritten metadata and registration changes

## Implementation checklist

Use this as the procedural implementation workflow:

- Analyze request:
   - identify the Azure service and resource type
   - check whether the resource or data source already exists
   - determine the implementation model before suggesting code

- Set up structure:
   - locate the service directory and nearby implementation pattern
   - identify required files such as resource, tests, utilities, docs, and registration changes
   - verify whether client or service registration changes are required
   - if this work introduces a brand-new service package, update the service-local `registration.go` so the new service is wired into the correct methods for the chosen surfaces instead of treating registration as one generic block; that can include `DataSources()`, `Resources()`, `SupportedDataSources()`, `SupportedResources()`, `FrameworkResources()`, `FrameworkDataSources()`, `EphemeralResources()`, and `ListResources()` as applicable
   - if this work introduces a brand-new service package, also register the service in the correct handwritten provider-level slice or slices inside `internal/provider/services.go`, in practice `SupportedTypedServices()` and/or `SupportedUntypedServices()` based on the service registration interfaces in use
   - if this work introduces a brand-new service package, define the service-local `client/client.go`, then update `internal/clients/client.go` in the correct places for that service: imports, the `Client` struct field, and the `Build(...)` registration path; do not treat `internal/clients/client.go` as a single insertion point
   - if this work changes the supported service definitions for a brand-new service package, make sure the handwritten source metadata that drives generated outputs is correct: `AssociatedGitHubLabel()`, `Name()`, `WebsiteCategories()`, the relevant supported-service slices in `internal/provider/services.go`, and the service client wiring in `internal/clients/client.go`
   - if this work introduces or changes a brand-new service package in the target provider repo, ensure the generated companion artifacts are also updated and included in the PR according to the upstream workflow; that can include `.github/labeler-issue-triage.yml`, `.github/labeler-pull-request-triage.yml`, `.teamcity/components/generated/services.kt`, and `website/allowed-subcategories`
   - treat those generated files as required PR companions derived from the source metadata and service registration changes above, not as disconnected one-off edits

- Implement core logic:
   - define model or schema with the required Azure properties
   - implement create, read, update, and delete or the framework-specific equivalent for the chosen model
   - keep nil handling, residual-state behavior, and ID handling aligned to nearby patterns

- Add validation and error handling:
   - implement ID validation or parser usage
   - add `CustomizeDiff` only when evidence-backed Azure constraints require it
   - use provider-standard error formatting
   - add appropriate timeout behavior

- Create tests:
   - add the core lifecycle or framework-specific coverage required by the chosen model
   - add `requiresImport` coverage when applicable
   - add list-resource, ephemeral-resource, or provider-function companion tests when the workflow requires them

- Write documentation:
   - add or update the docs page that matches the implementation surface: `website/docs/r/`, `website/docs/d/`, `website/docs/list-resources/`, `website/docs/ephemeral-resources/`, or `website/docs/functions/`
   - add the list-resource docs page when list support is required
   - add the ephemeral-resource or provider-function docs page when that surface is in scope
   - keep import documentation aligned to implementation evidence when the doc type supports import instructions

## Output expectation

When asked to implement something, provide:

- A short plan (files to touch)
- The schema + CRUD mapping decisions
- The minimal set of code changes needed
- How you validated (build/tests)
