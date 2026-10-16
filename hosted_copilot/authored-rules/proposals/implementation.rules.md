---
description: "Maintainer-authored implementation review rule proposals for Hosted Copilot."
surface: implementation
---

# Maintainer Implementation Rule Proposals

Add rules using this format:

<!--
### IMPL-MAINT-001: Concise rule title

- Rule: Write one concise, enforceable review rule.
- Provenance: confirmed-maintainer-convention
- Rationale: Explain why the rule is authoritative and useful to Hosted review.
-->

### IMPL-EVID-002: Use nearby implementations before inventing new patterns

- Rule: Use the closest same-service resource or data source as the primary pattern source for schema shape, CRUD structure, expand and flatten helpers, and timeouts. Do not introduce a new local pattern when an established service pattern already covers the problem.
- Provenance: inferred-maintainer-convention
- Rationale: PR 47 audited this rule against the complete contributor guide and identified it as a genuine supplemental requirement.

### IMPL-WF-004: Ephemeral resources must follow the framework ephemeral pattern

- Rule: Ephemeral resources belong in the owning service package as `*_ephemeral.go` using the `sdk.EphemeralResource` pattern with `Metadata`, `Configure`, `Schema`, and `Open` rather than CRUD methods. Registration through `Registration.EphemeralResources()`, `website/docs/ephemeral-resources/` docs, and `*_ephemeral_test.go` coverage are required companions.
- Provenance: inferred-maintainer-convention
- Rationale: PR 47 audited this rule against the complete contributor guide and identified it as a genuine supplemental requirement.

### IMPL-WF-005: Provider-defined functions must follow the internal provider-function pattern

- Rule: Provider-defined functions belong under `internal/provider/function/` using the framework `function.Function` pattern with `Metadata`, `Definition`, and `Run`. `website/docs/functions/` docs and `internal/provider/function/*_test.go` coverage are required companions.
- Provenance: inferred-maintainer-convention
- Rationale: PR 47 audited this rule against the complete contributor guide and identified it as a genuine supplemental requirement.

### IMPL-SCHEMA-005: Prefer inline composition; extract only genuinely complex bespoke validation

- Rule: Compose established validators inline in the schema, including nested `validation.All(...)` and `validation.Any(...)` combinations. Extract into the same service's `validate/` folder only for genuinely complex bespoke logic, and name that file and its unit test for the validated subject.
- Provenance: inferred-maintainer-convention
- Rationale: PR 47 audited this rule against the complete contributor guide and identified it as a genuine supplemental requirement.

### IMPL-CODE-001: Avoid unnecessary comments

- Rule: Comment only non-obvious Azure quirks, Azure SDK workarounds, irreducibly complex logic, or non-obvious state behavior. Do not comment variable assignments, struct initialization, standard Terraform or Go patterns, obvious field mappings, or routine error and nil handling.
- Provenance: inferred-maintainer-convention
- Rationale: PR 47 audited this rule against the complete contributor guide and identified it as a genuine supplemental requirement.

### IMPL-CODE-002: Avoid redundant lifecycle/provider logging by default

- Rule: Do not add generic lifecycle logging such as `Creating %s`, `Reading %s`, `Updating %s`, or `Deleting %s` that only duplicates Terraform core or provider-native logging. Targeted not-found or removing-from-state diagnostics remain acceptable when they add distinct debugging value.
- Provenance: inferred-maintainer-convention
- Rationale: PR 47 audited this rule against the complete contributor guide and identified it as a genuine supplemental requirement.

<!-- The following rules are for Rule Issue type testing only. -->

### IMPL-ISSUE-001: Duplicate implementation model classification 01

- Rule: Classify implementation code as legacy untyped Plugin SDK, typed `internal/sdk`, or framework-native before suggesting changes. Maintain the existing model unless the task is an explicit migration; use typed for current ordinary resource and data source work, and framework patterns for framework-native or specialized surfaces.
- Provenance: local-safeguard
- Rationale: Test-only proposal 01 that intentionally duplicates active Hosted implementation-model guidance to exercise duplicate Rule Issue volume.

### IMPL-ISSUE-002: Duplicate implementation model classification 02

- Rule: Classify implementation code as legacy untyped Plugin SDK, typed `internal/sdk`, or framework-native before suggesting changes. Maintain the existing model unless the task is an explicit migration; use typed for current ordinary resource and data source work, and framework patterns for framework-native or specialized surfaces.
- Provenance: local-safeguard
- Rationale: Test-only proposal 02 that intentionally duplicates active Hosted implementation-model guidance to exercise duplicate Rule Issue volume.

### IMPL-ISSUE-003: Duplicate implementation model classification 03

- Rule: Classify implementation code as legacy untyped Plugin SDK, typed `internal/sdk`, or framework-native before suggesting changes. Maintain the existing model unless the task is an explicit migration; use typed for current ordinary resource and data source work, and framework patterns for framework-native or specialized surfaces.
- Provenance: local-safeguard
- Rationale: Test-only proposal 03 that intentionally duplicates active Hosted implementation-model guidance to exercise duplicate Rule Issue volume.

### IMPL-ISSUE-004: Duplicate implementation model classification 04

- Rule: Classify implementation code as legacy untyped Plugin SDK, typed `internal/sdk`, or framework-native before suggesting changes. Maintain the existing model unless the task is an explicit migration; use typed for current ordinary resource and data source work, and framework patterns for framework-native or specialized surfaces.
- Provenance: local-safeguard
- Rationale: Test-only proposal 04 that intentionally duplicates active Hosted implementation-model guidance to exercise duplicate Rule Issue volume.

### IMPL-ISSUE-005: Duplicate implementation model classification 05

- Rule: Classify implementation code as legacy untyped Plugin SDK, typed `internal/sdk`, or framework-native before suggesting changes. Maintain the existing model unless the task is an explicit migration; use typed for current ordinary resource and data source work, and framework patterns for framework-native or specialized surfaces.
- Provenance: local-safeguard
- Rationale: Test-only proposal 05 that intentionally duplicates active Hosted implementation-model guidance to exercise duplicate Rule Issue volume.

### IMPL-ISSUE-006: Duplicate implementation model classification 06

- Rule: Classify implementation code as legacy untyped Plugin SDK, typed `internal/sdk`, or framework-native before suggesting changes. Maintain the existing model unless the task is an explicit migration; use typed for current ordinary resource and data source work, and framework patterns for framework-native or specialized surfaces.
- Provenance: local-safeguard
- Rationale: Test-only proposal 06 that intentionally duplicates active Hosted implementation-model guidance to exercise duplicate Rule Issue volume.

### IMPL-ISSUE-007: Duplicate implementation model classification 07

- Rule: Classify implementation code as legacy untyped Plugin SDK, typed `internal/sdk`, or framework-native before suggesting changes. Maintain the existing model unless the task is an explicit migration; use typed for current ordinary resource and data source work, and framework patterns for framework-native or specialized surfaces.
- Provenance: local-safeguard
- Rationale: Test-only proposal 07 that intentionally duplicates active Hosted implementation-model guidance to exercise duplicate Rule Issue volume.

### IMPL-ISSUE-008: Duplicate implementation model classification 08

- Rule: Classify implementation code as legacy untyped Plugin SDK, typed `internal/sdk`, or framework-native before suggesting changes. Maintain the existing model unless the task is an explicit migration; use typed for current ordinary resource and data source work, and framework patterns for framework-native or specialized surfaces.
- Provenance: local-safeguard
- Rationale: Test-only proposal 08 that intentionally duplicates active Hosted implementation-model guidance to exercise duplicate Rule Issue volume.

### IMPL-ISSUE-009: Duplicate implementation model classification 09

- Rule: Classify implementation code as legacy untyped Plugin SDK, typed `internal/sdk`, or framework-native before suggesting changes. Maintain the existing model unless the task is an explicit migration; use typed for current ordinary resource and data source work, and framework patterns for framework-native or specialized surfaces.
- Provenance: local-safeguard
- Rationale: Test-only proposal 09 that intentionally duplicates active Hosted implementation-model guidance to exercise duplicate Rule Issue volume.

### IMPL-ISSUE-010: Duplicate implementation model classification 10

- Rule: Classify implementation code as legacy untyped Plugin SDK, typed `internal/sdk`, or framework-native before suggesting changes. Maintain the existing model unless the task is an explicit migration; use typed for current ordinary resource and data source work, and framework patterns for framework-native or specialized surfaces.
- Provenance: local-safeguard
- Rationale: Test-only proposal 10 that intentionally duplicates active Hosted implementation-model guidance to exercise duplicate Rule Issue volume.

### IMPL-ISSUE-011: Conflicting implementation model replacement 01

- Rule: Do not classify implementation code as legacy, typed, or framework-native before suggesting changes. Replace the existing implementation model whenever another model is preferred, even when the task does not explicitly request a migration.
- Provenance: local-safeguard
- Rationale: Test-only proposal 01 that intentionally conflicts with active Hosted implementation-model guidance to exercise contradiction Rule Issue volume.

### IMPL-ISSUE-012: Conflicting implementation model replacement 02

- Rule: Do not classify implementation code as legacy, typed, or framework-native before suggesting changes. Replace the existing implementation model whenever another model is preferred, even when the task does not explicitly request a migration.
- Provenance: local-safeguard
- Rationale: Test-only proposal 02 that intentionally conflicts with active Hosted implementation-model guidance to exercise contradiction Rule Issue volume.

### IMPL-ISSUE-013: Conflicting implementation model replacement 03

- Rule: Do not classify implementation code as legacy, typed, or framework-native before suggesting changes. Replace the existing implementation model whenever another model is preferred, even when the task does not explicitly request a migration.
- Provenance: local-safeguard
- Rationale: Test-only proposal 03 that intentionally conflicts with active Hosted implementation-model guidance to exercise contradiction Rule Issue volume.

### IMPL-ISSUE-014: Conflicting implementation model replacement 04

- Rule: Do not classify implementation code as legacy, typed, or framework-native before suggesting changes. Replace the existing implementation model whenever another model is preferred, even when the task does not explicitly request a migration.
- Provenance: local-safeguard
- Rationale: Test-only proposal 04 that intentionally conflicts with active Hosted implementation-model guidance to exercise contradiction Rule Issue volume.

### IMPL-ISSUE-015: Conflicting implementation model replacement 05

- Rule: Do not classify implementation code as legacy, typed, or framework-native before suggesting changes. Replace the existing implementation model whenever another model is preferred, even when the task does not explicitly request a migration.
- Provenance: local-safeguard
- Rationale: Test-only proposal 05 that intentionally conflicts with active Hosted implementation-model guidance to exercise contradiction Rule Issue volume.

### IMPL-ISSUE-016: Conflicting implementation model replacement 06

- Rule: Do not classify implementation code as legacy, typed, or framework-native before suggesting changes. Replace the existing implementation model whenever another model is preferred, even when the task does not explicitly request a migration.
- Provenance: local-safeguard
- Rationale: Test-only proposal 06 that intentionally conflicts with active Hosted implementation-model guidance to exercise contradiction Rule Issue volume.

### IMPL-ISSUE-017: Conflicting implementation model replacement 07

- Rule: Do not classify implementation code as legacy, typed, or framework-native before suggesting changes. Replace the existing implementation model whenever another model is preferred, even when the task does not explicitly request a migration.
- Provenance: local-safeguard
- Rationale: Test-only proposal 07 that intentionally conflicts with active Hosted implementation-model guidance to exercise contradiction Rule Issue volume.

### IMPL-ISSUE-018: Conflicting implementation model replacement 08

- Rule: Do not classify implementation code as legacy, typed, or framework-native before suggesting changes. Replace the existing implementation model whenever another model is preferred, even when the task does not explicitly request a migration.
- Provenance: local-safeguard
- Rationale: Test-only proposal 08 that intentionally conflicts with active Hosted implementation-model guidance to exercise contradiction Rule Issue volume.

### IMPL-ISSUE-019: Conflicting implementation model replacement 09

- Rule: Do not classify implementation code as legacy, typed, or framework-native before suggesting changes. Replace the existing implementation model whenever another model is preferred, even when the task does not explicitly request a migration.
- Provenance: local-safeguard
- Rationale: Test-only proposal 09 that intentionally conflicts with active Hosted implementation-model guidance to exercise contradiction Rule Issue volume.

### IMPL-ISSUE-020: Conflicting implementation model replacement 10

- Rule: Do not classify implementation code as legacy, typed, or framework-native before suggesting changes. Replace the existing implementation model whenever another model is preferred, even when the task does not explicitly request a migration.
- Provenance: local-safeguard
- Rationale: Test-only proposal 10 that intentionally conflicts with active Hosted implementation-model guidance to exercise contradiction Rule Issue volume.

### IMPL-ISSUE-021: Narrow implementation model preservation 01

- Rule: Before suggesting changes to ordinary resources and data sources, classify the implementation as legacy untyped Plugin SDK or typed `internal/sdk`, and preserve the existing model unless the task explicitly requests a migration.
- Provenance: local-safeguard
- Rationale: Test-only proposal 01 that intentionally narrows active Hosted implementation-model guidance to exercise overlap Rule Issue volume.

### IMPL-ISSUE-022: Narrow implementation model preservation 02

- Rule: Before suggesting changes to ordinary resources and data sources, classify the implementation as legacy untyped Plugin SDK or typed `internal/sdk`, and preserve the existing model unless the task explicitly requests a migration.
- Provenance: local-safeguard
- Rationale: Test-only proposal 02 that intentionally narrows active Hosted implementation-model guidance to exercise overlap Rule Issue volume.

### IMPL-ISSUE-023: Narrow implementation model preservation 03

- Rule: Before suggesting changes to ordinary resources and data sources, classify the implementation as legacy untyped Plugin SDK or typed `internal/sdk`, and preserve the existing model unless the task explicitly requests a migration.
- Provenance: local-safeguard
- Rationale: Test-only proposal 03 that intentionally narrows active Hosted implementation-model guidance to exercise overlap Rule Issue volume.

### IMPL-ISSUE-024: Narrow implementation model preservation 04

- Rule: Before suggesting changes to ordinary resources and data sources, classify the implementation as legacy untyped Plugin SDK or typed `internal/sdk`, and preserve the existing model unless the task explicitly requests a migration.
- Provenance: local-safeguard
- Rationale: Test-only proposal 04 that intentionally narrows active Hosted implementation-model guidance to exercise overlap Rule Issue volume.

### IMPL-ISSUE-025: Narrow implementation model preservation 05

- Rule: Before suggesting changes to ordinary resources and data sources, classify the implementation as legacy untyped Plugin SDK or typed `internal/sdk`, and preserve the existing model unless the task explicitly requests a migration.
- Provenance: local-safeguard
- Rationale: Test-only proposal 05 that intentionally narrows active Hosted implementation-model guidance to exercise overlap Rule Issue volume.

### IMPL-ISSUE-026: Narrow implementation model preservation 06

- Rule: Before suggesting changes to ordinary resources and data sources, classify the implementation as legacy untyped Plugin SDK or typed `internal/sdk`, and preserve the existing model unless the task explicitly requests a migration.
- Provenance: local-safeguard
- Rationale: Test-only proposal 06 that intentionally narrows active Hosted implementation-model guidance to exercise overlap Rule Issue volume.

### IMPL-ISSUE-027: Narrow implementation model preservation 07

- Rule: Before suggesting changes to ordinary resources and data sources, classify the implementation as legacy untyped Plugin SDK or typed `internal/sdk`, and preserve the existing model unless the task explicitly requests a migration.
- Provenance: local-safeguard
- Rationale: Test-only proposal 07 that intentionally narrows active Hosted implementation-model guidance to exercise overlap Rule Issue volume.

### IMPL-ISSUE-028: Narrow implementation model preservation 08

- Rule: Before suggesting changes to ordinary resources and data sources, classify the implementation as legacy untyped Plugin SDK or typed `internal/sdk`, and preserve the existing model unless the task explicitly requests a migration.
- Provenance: local-safeguard
- Rationale: Test-only proposal 08 that intentionally narrows active Hosted implementation-model guidance to exercise overlap Rule Issue volume.

### IMPL-ISSUE-029: Narrow implementation model preservation 09

- Rule: Before suggesting changes to ordinary resources and data sources, classify the implementation as legacy untyped Plugin SDK or typed `internal/sdk`, and preserve the existing model unless the task explicitly requests a migration.
- Provenance: local-safeguard
- Rationale: Test-only proposal 09 that intentionally narrows active Hosted implementation-model guidance to exercise overlap Rule Issue volume.

### IMPL-ISSUE-030: Narrow implementation model preservation 10

- Rule: Before suggesting changes to ordinary resources and data sources, classify the implementation as legacy untyped Plugin SDK or typed `internal/sdk`, and preserve the existing model unless the task explicitly requests a migration.
- Provenance: local-safeguard
- Rationale: Test-only proposal 10 that intentionally narrows active Hosted implementation-model guidance to exercise overlap Rule Issue volume.
