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
