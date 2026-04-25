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

## Schema and mapping

### IMPL-SCHEMA-001: Schema requirements must match real behavior
- Rule: `Required`, `Optional`, `Computed`, and validation behavior must reflect real API requirements and established provider conventions.
- Rule: Do not make a field required, optional, or validated more strictly without evidence.

### IMPL-SCHEMA-002: Common field ordering should follow provider conventions
- Rule: When common fields are present, prefer provider ordering patterns such as `name`, `resource_group_name`, and `location` first, with `tags` last.
- Rule: Keep changes consistent with nearby same-service implementations.

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
