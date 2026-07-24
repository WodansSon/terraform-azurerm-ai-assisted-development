---
description: "Autonomous, phase-gated ARM API version bump for an AzureRM Resource Provider, driving the resource-implementation skill under the API version migration compliance contract."
---

# 🔁 Update API Version - AzureRM Resource Provider

This prompt is the explicit entry point for bumping a Resource Provider to a newer Azure Resource Manager API version. It owns phase order and the hard gates; the actual code changes are performed by the `resource-implementation` skill, and the migration-specific rules live in the API version migration compliance contract.

Invoke it explicitly, for example:

- `/update-api-version cdn/2024-09-01 cdn/2025-12-01`

where the first argument is `{{SERVICE}}/{{FROM_API_VERSION}}` and the second is `{{SERVICE}}/{{TARGET_API_VERSION}}`.

# 🚫 EXECUTION GUARDRAILS (READ FIRST)

## Scope and ownership
This flow covers readiness checks, scoped code migration, build validation, and a migration risk summary.
It does not choose which API version the provider should adopt, and it does not submit pull requests.
Keep the target API version choice, runtime verification, failure interpretation, the final risk call, and PR submission with the engineer.

## Invocation inputs
Expect the engineer to invoke this prompt with the Resource Provider plus the current and target ARM API versions, in the form `{{SERVICE}}/{{FROM_API_VERSION}} {{SERVICE}}/{{TARGET_API_VERSION}}`.
If the Resource Provider or either API version is missing, ask for the missing input before doing any code work.

## Determinism policy
- Follow the API version migration contract, not stale prompt memory.
- Do not guess SDK symbols, model shapes, or API behavior when evidence is missing.
- Do not skip past a failed gate.
- Do not perform unrelated refactors or feature work during the bump.

## Mandatory procedure

### 0) Load the contracts and the implementation skill
- Read and apply `.github/instructions/api-version-migration-compliance-contract.instructions.md` to EOF for the migration-flow rules.
- Read and apply `.github/instructions/implementation-compliance-contract.instructions.md` to EOF for the code changes themselves.
- Read and apply `.github/skills/resource-implementation/SKILL.md` to EOF; this skill is the implementation agent that performs the scoped code changes.
- EOF marker verification is mandatory for the migration contract:
  - `.github/instructions/api-version-migration-compliance-contract.instructions.md` -> `<!-- APIMIG-CONTRACT-EOF -->`
- If the migration contract is not fully loaded, hard-stop and output exactly this one line and nothing else:
  - `Cannot run update-api-version: migration contract not fully loaded. Load .github/instructions/api-version-migration-compliance-contract.instructions.md to EOF and re-run this prompt.`

### 1) Phase 1 - Readiness (gate)
- Resolve the Resource Provider and the current and target API versions from the invocation.
- Run the readiness checks: vendored-SDK availability (`APIMIG-READY-001`), the `hashicorp/pandora` fallback check when the SDK lacks the version, including enumerating pandora data workarounds from the `hashicorp/pandora` GitHub repository (read upstream via repository search or fetch, since that `dataworkarounds` path is not in this workspace) to determine whether any workaround is registered for the target Resource Provider, keyed on the pandora `serviceName` rather than the target API version, and noting per-workaround whether it also applies to the target version (`APIMIG-READY-002`, `APIMIG-RISK-004`), and pandora-result escalation (`APIMIG-READY-003`).
- Hard-stop before editing any code while readiness is unmet, and do not fabricate SDK symbols to proceed (`APIMIG-READY-003`).

### 2) Phase 2 - Scoped migration
- Have the `resource-implementation` skill apply the scoped code changes: SDK import paths, client construction, method calls, and model/field adjustments verified against the vendored SDK (`APIMIG-SCOPE-001`, `APIMIG-SCOPE-003`), while satisfying the implementation compliance contract for how the Go code is written.
- Preserve schema shape, behavior, and state semantics. Record any behavior change or suspected pre-existing bug for the risk summary and wait for engineer approval before changing provider behavior (`APIMIG-SCOPE-002`).

### 3) Phase 3 - Build validation (gate)
- Validate that the affected packages compile and are formatted using the Go toolchain through the WSL terminal per workspace conventions (`APIMIG-BUILD-001`).
- Resolve compile-time breakages from the SDK/model changes as part of the scoped migration.
- Once the build is clean, run `make fmt` and `make document-fix` through the WSL terminal to keep code formatting and generated documentation in sync; treat `make document-fix` as required and do not skip it or rationalize skipping it as a no-op, since an API version bump can change documented content and docs can reference the prior API version.
- Do not proceed to the risk summary until the build is clean.

### 4) Phase 4 - Risk summary (final deliverable)
- Produce the migration risk summary covering the scoped changes made, the documented-breaking-change check, and breaking-change classification held for engineer approval (`APIMIG-RISK-001`, `APIMIG-RISK-002`, `APIMIG-RISK-003`).
- Run the documented-breaking-change check via the Microsoft Learn MCP as a required blocking step, and record an explicit `found` / `none-found` / `did-not-run` status; carry `did-not-run` as an open item and never report an unavailable check as `none-found` (`APIMIG-RISK-002`).
- List any pandora data workarounds registered for the target Resource Provider as known-quirk risk items, noting for each whether it applies to the target API version, and do not treat the absence of a workaround for the Resource Provider as evidence the version is clean (`APIMIG-RISK-004`).
- Mark the migration `UNVERIFIED`, state that the build and documentation checks cannot confirm runtime behavioral parity (`APIMIG-RISK-001`), and return ownership of runtime verification, the final risk call, and PR submission to the engineer (`APIMIG-OWN-001`), then stop.

## Verification footer (assistant response only)
When this prompt completes the flow using the implementation skill, the assistant's final response must include this line:

Skill used: resource-implementation

Do not write this marker into repository files, and do not emit it in intermediate/progress updates.
