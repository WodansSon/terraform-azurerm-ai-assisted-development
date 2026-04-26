---
applyTo: "internal/**/*.go"
description: "Shared implementation compliance contract (single source of truth) used by the resource-implementation skill and Go implementation routing."
---

# Implementation Compliance Contract

This file is the single source of truth for Go implementation compliance in this repository.

## Consumers

Implementation consumers MUST follow this contract:

- Consumer: `.github/skills/resource-implementation/SKILL.md`
  - Role: Implementer
  - Command: `/resource-implementation`
  - Requires EOF Load: yes
  - Goal: implement or modify Terraform AzureRM provider resources and data sources under `internal/**` while applying `IMPL-*` rules.

- Consumer: `.github/instructions/ai-skill-routing-go.instructions.md`
  - Role: Router
  - Requires EOF Load: no
  - Goal: route `internal/**/*.go` work through the implementation contract and the resource-implementation skill.

## Canonical sources of truth (precedence)

Use these sources with the following roles:

- Current workspace contributor guidance
  - `.github/copilot-instructions.md`
- This contract
  - Authoritative for implementation compliance, precedence, and core `IMPL-*` rules in this repository.
- Target-provider contributor guidance, when present in the workspace or explicitly fetched as evidence
  - `contributing/README.md`
  - `contributing/topics/**/*.md`

Conflict resolution:

- This contract is authoritative for implementation compliance in this repository.
- Current workspace contributor guidance is authoritative for repo-specific expectations that affect implementation behavior.
- Target-provider contributor guidance is the baseline reference when workspace evidence is insufficient, but this contract may be stricter to reduce drift and ambiguity.
- If target-provider contributor guidance adds or tightens a standard, update this contract so coverage is preserved.
- If a companion implementation guide differs from this contract, follow this contract and update the companion guide to re-align.

## Detailed companion guidance

These files provide worked examples, implementation patterns, and specialized heuristics. They are companion guidance, not an independent compliance layer:

- `.github/instructions/implementation-guide.instructions.md`
- `.github/instructions/azure-patterns.instructions.md`
- `.github/instructions/schema-patterns.instructions.md`
- `.github/instructions/error-patterns.instructions.md`
- `.github/instructions/provider-guidelines.instructions.md`
- `.github/instructions/code-clarity-enforcement.instructions.md`

## Rule IDs

Rules are identified by stable IDs so the skill and routing layer can reference the same requirements without drifting.

ID format:
- `IMPL-<AREA>-<NNN>`

Areas:
- `EVID` = evidence and verification guardrails
- `WF` = implementation workflow expectations
- `SCHEMA` = schema design and field mapping
- `PATCH` = PATCH/residual-state handling
- `ERR` = error handling and diagnostics
- `TEST` = testing expectations
- `CODE` = code clarity and comment discipline

## Evidence hierarchy

When an implementation claim affects API shape, schema mapping, validation, or severity, use this evidence order:

1. Current workspace contributor guidance and this contract
2. Existing implementation patterns under `internal/**`, especially sibling resources and data sources in the same service
3. Generated or vendored SDK/client models used by the provider
4. Target-provider contributor guidance when present
5. Azure service documentation for semantics only, not for inventing provider-only requirements

If evidence is missing for a behavior-changing claim, do not guess.

---

# Contract Rules

## Evidence and verification

### IMPL-EVID-001: Do not guess API model structure
- Rule: Do not guess field types, required properties, enum values, or nested shapes when mapping provider schema to Azure SDK/client models.
- Rule: Verify those details from provider code, generated clients, SDK models, or other evidence in the hierarchy above before implementing them.

### IMPL-EVID-002: Use nearby implementations before inventing new patterns
- Rule: When working in a service area, use the closest same-service resource or data source as the primary pattern source for schema shape, CRUD structure, flatten/expand patterns, and timeouts.
- Rule: Do not introduce a new pattern when an existing service-local pattern already covers the problem acceptably.

## Workflow

### IMPL-WF-001: Prefer typed implementations for new work
- Rule: Prefer the typed `internal/sdk` implementation style for new resources and data sources.
- Rule: Use untyped patterns primarily for maintenance of existing untyped implementations unless there is a strong evidence-backed reason to do otherwise.
- **Provenance**: Published upstream standard.
- **Evidence**:
  - Upstream contributor guidance in `hashicorp/terraform-provider-azurerm/contributing/topics/best-practices.md` under `Typed vs. Untyped Resources`
  - Upstream contributor guidance there says new Data Sources and Resources should be added as typed implementations

## Schema and mapping

### IMPL-SCHEMA-001: Schema requirements must match real behavior
- Rule: `Required`, `Optional`, `Computed`, and validation behavior must reflect real API requirements and established provider conventions.
- Rule: Do not make a field required, optional, or validated more strictly without evidence.

### IMPL-SCHEMA-002: Common field ordering should follow provider conventions
- Rule: When common fields are present, prefer provider ordering patterns such as `name`, `resource_group_name`, and `location` first, with `tags` last.
- Rule: Keep changes consistent with nearby same-service implementations.
- **Provenance**: Published upstream standard.
- **Evidence**:
  - Upstream contributor guidance in `hashicorp/terraform-provider-azurerm/contributing/topics/guide-new-resource.md` says schema fields should place ID fields first, then `location`, with `tags` last
  - Upstream contributor guidance in `hashicorp/terraform-provider-azurerm/contributing/topics/guide-new-data-source.md` applies the same ordering pattern to typed data sources

### IMPL-SCHEMA-003: Generic fallback validators are last-resort, not the target state
- Rule: Treat generic validators such as `validation.StringIsNotEmpty` and `validation.IntAtLeast(...)` as fallback choices only when stronger evidence-backed validation cannot be determined.
- Rule: When evidence establishes real enums, ranges, naming constraints, ID formats, URI formats, or other concrete limits, encode that real validation instead of stopping at non-empty or minimum-only checks.
- Rule: Numeric arguments should define a real valid range when one is known, and string arguments should use pattern, enum, length, ID, or format validation when that behavior is knowable.
- **Provenance**: Published upstream standard.
- **Evidence**:
  - Upstream contributor guidance in `hashicorp/terraform-provider-azurerm/contributing/topics/schema-design-considerations.md` under `Validation` says string arguments must be validated, `StringNotEmpty` is only a minimum, and validation should ideally be more strict
  - Upstream contributor guidance there also says numeric arguments should specify a valid range
  - Upstream contributor guidance in `hashicorp/terraform-provider-azurerm/contributing/topics/guide-new-fields-to-resource.md` says `validation.StringIsNotEmpty` is the minimum only when a stronger validation pattern cannot be determined

### IMPL-SCHEMA-004: Prefer SDK PossibleValues helpers for enum validation unless the real accepted subset is narrower
- Rule: When the SDK package exposes a `PossibleValuesFor...` helper that matches the real accepted enum values for the field, prefer that helper inside `validation.StringInSlice(...)` instead of hardcoding the values manually.
- Rule: If the SDK helper returns values that are broader than what the specific resource, API path, or service behavior actually accepts, define the narrowed validation set from evidence instead of blindly using the full SDK helper output.
- Rule: Do not mix enum values from unrelated services or discriminator types into a field's validation list simply because they appear in the same SDK or provider tree.
- **Provenance**: Published upstream standard.
- **Evidence**:
  - Upstream contributor guidance in `hashicorp/terraform-provider-azurerm/contributing/topics/schema-design-considerations.md` under `Validation` says validation should use the real constraints of the argument rather than weaker or looser checks
  - Upstream contributor guidance in `hashicorp/terraform-provider-azurerm/contributing/topics/guide-new-fields-to-resource.md` says appropriate validation should be added for new properties and stronger patterns should be used when they can be determined

## PATCH and residual state

### IMPL-PATCH-001: Explicitly disable features in PATCH flows
- Rule: When Azure PATCH behavior preserves omitted values, do not rely on omission to disable a feature.
- Rule: Return complete structures with explicit disabled state where needed to clear residual state reliably.

## Error handling

### IMPL-ERR-001: Use provider-standard error wording
- Rule: Error messages should be lowercase, descriptive, and free of contractions.
- Rule: Wrap field names and important user-visible values in backticks.
- Rule: Use `%+v` for underlying errors when wrapping provider or SDK failures.
- Rule: Use `errors.New(...)` for static errors that do not wrap an underlying error and do not require formatting.
- **Provenance**: Published upstream standard.
- **Evidence**:
  - Upstream contributor guidance in `hashicorp/terraform-provider-azurerm/contributing/topics/reference-errors.md` for lowercase wrapped errors, `%+v`, and `errors.New(...)`
  - Upstream contributor guidance in `hashicorp/terraform-provider-azurerm/contributing/topics/guide-new-resource.md` requiring argument names in error messages to be wrapped in backticks

### IMPL-ERR-002: Do not wrap comprehensive ID parser errors with redundant context
- Rule: When a resource ID parser or validator already returns a comprehensive, user-facing error message, prefer returning that error directly instead of wrapping it with extra `parsing`, `flattening`, or field-name context.
- Rule: Add wrapping context only when it contributes materially new information that the parser error does not already provide.
- **Provenance**: Inferred maintainer convention.
- **Evidence**:
  - Maintainer review guidance in `hashicorp/terraform-provider-azurerm` PR `#31957` comment `discussion_r3137015087`: `since the id parser gives us a comprehensive error message, we don't need any other message with this`
  - The suggested maintainer change there replaces ``return results, fmt.Errorf("flattening `cdn_frontdoor_firewall_policy_id`: %+v", err)`` with `return results, err`

## Testing

### IMPL-TEST-001: Update tests when implementation behavior changes
- Rule: Add or adjust tests when schema behavior, resource behavior, or API mapping changes materially.
- Rule: Do not leave implementation changes untested when existing test patterns can cover them.

### IMPL-TEST-002: Prefer ImportStep plus existence checks when appropriate
- Rule: In acceptance tests, prefer `ImportStep()` for validation and `ExistsInAzure` for existence checks when that pattern fits the resource or data source.

## Code clarity

### IMPL-CODE-001: Avoid unnecessary comments
- Rule: Prefer self-documenting code.
- Rule: Add comments only when documenting non-obvious Azure quirks, SDK workarounds, or other behavior that cannot be made clear through code structure alone.

<!-- IMPLEMENTATION-CONTRACT-EOF -->
