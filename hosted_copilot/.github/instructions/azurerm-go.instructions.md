---
description: "Review Terraform AzureRM provider Go implementation for Azure API, schema, state, lifecycle, identity, and error-handling defects."
applyTo: "internal/**/*.go"
---

# AzureRM Go Review Rules:

Apply these rules only when changed lines introduce or expose an actionable defect. Classify the target as legacy untyped Plugin SDK, typed `internal/sdk`, or framework-native before applying model-specific rules. Maintain the existing model unless the change is an explicit migration, and verify Azure API claims against generated SDK models.

## Evidence And Implementation Model:

- `[IMPL-EVID-001]` [legacy, typed, framework] Do not infer Azure field types, required properties, enum values, or PATCH semantics. Verify them against generated SDK models and the selected API version.
- `[IMPL-WF-001A]` [legacy, typed, framework] Classify implementation code as legacy untyped Plugin SDK, typed `internal/sdk`, or framework-native before suggesting changes. Maintain the existing model unless the task is an explicit migration; use typed for current ordinary resource and data source work, and framework patterns for framework-native or specialized surfaces.

## Create And Import Behavior:

- `[IMPL-WF-002B]` [legacy, typed] A create-time import-as-exists check must honor `SkipImportCheckOnCreateAndAllowOverwritingExistingResources`; when the feature is enabled, existing remote resources must not trigger `ImportAsExistsError`.
- `[IMPL-WF-002C]` [legacy, typed] When Resource Identity is supported, callback-based create flows must set both the resource ID and identity before returning. Do not defer required identity population until Read.

## Schema And State:

- `[IMPL-SCHEMA-001]` [legacy, typed, framework] Required, optional, computed, ForceNew, defaults, conflicts, and validation must match actual API and lifecycle behavior. Flag schema declarations that permit invalid requests, reject valid configuration, or cannot round-trip state.
- `[IMPL-SCHEMA-004]` [legacy, typed] Prefer generated SDK `PossibleValuesFor...()` helpers for enum validation when they represent the accepted set. A narrower validator requires service-specific evidence.
- `[IMPL-SCHEMA-006]` [legacy, typed, framework] Parse Azure-returned resource IDs with the shared typed parser and write the parser's canonical `.ID()` form to Terraform state. Do not persist raw API ID casing when a parser exists.
- `[IMPL-SCHEMA-007]` [legacy, typed, framework] Do not expose preview-only Azure properties as stable schema before GA unless the provider's explicit feature-gate policy permits them.
- `[IMPL-SCHEMA-008]` [legacy, typed] When Azure uses a `None`, `Off`, or equivalent sentinel for omission, keep that sentinel out of user-facing validation, expand omitted configuration to the API sentinel, and flatten the sentinel back to omitted state.
- `[IMPL-SCHEMA-010]` [legacy, typed] An optional `TypeList` block whose nested fields are all optional must enforce a non-empty configured item when an empty block would produce an invalid or meaningless request.
- `[IMPL-SCHEMA-013]` [legacy, typed] `CustomizeDiff` validation for optional or unknown values must inspect `GetRawConfig()`, distinguish null from configured zero values, and check `IsKnown()` before traversing collections.
- `[IMPL-SCHEMA-017]` [legacy, typed] Write-only attributes must use symmetric schema relationships and a positive version trigger so secret rotation is intentional, state-safe, and not driven by perpetual unknown values.

## Azure Update Semantics:

- `[IMPL-PATCH-001]` [legacy, typed] If Azure PATCH preserves omitted properties, removing Terraform configuration must expand an explicit disabled, empty, or sentinel value that clears the remote feature. Returning `nil` is a defect when SDK serialization would omit the field and preserve stale Azure state.

## Errors:

- `[IMPL-ERR-001]` [legacy, typed, framework] Provider errors must be lowercase, add the operation and resource context needed to diagnose the failure, wrap field names and values in backticks, avoid contractions and terminal punctuation, and use `%+v` for underlying errors. Use `errors.New(...)` for static messages that do not wrap an error or require formatting; use `fmt.Errorf(...)` only when formatting values or wrapping context.
- `[IMPL-ERR-002]` [legacy, typed, framework] Return already comprehensive typed resource ID parser errors directly. Wrap them only when the additional context materially improves diagnosis.

These rules are compact Hosted selections from the implementation compliance contract. Test lifecycle and acceptance-test conventions are deferred to the test supplement so test files do not load duplicate rule meaning.
