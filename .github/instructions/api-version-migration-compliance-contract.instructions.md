---
applyTo: "internal/**/*.go"
description: "Shared API version migration compliance contract (single source of truth) used by the /update-api-version orchestrator prompt, which drives the resource-implementation skill for the code changes."
---

# API Version Migration Compliance Contract

This file is the single source of truth for ARM API version migration compliance in this repository.

It governs the invocation-driven flow that moves a Resource Provider to a newer Azure Resource Manager API version: readiness checks, scoped code migration, build validation, and a migration risk summary.

## Consumers

API version migration consumers MUST follow this contract:

- Consumer: `.github/prompts/update-api-version.prompt.md`
  - Role: Orchestrator
  - Command: `/update-api-version`
  - Requires EOF Load: yes
  - Goal: sequence the phase-gated flow, enforce the readiness and build gates, drive the `resource-implementation` skill for the scoped code changes, and stop after producing the migration risk summary for the engineer.

The scoped code changes themselves are performed by the `resource-implementation` skill (the implementation agent) under `.github/instructions/implementation-compliance-contract.instructions.md`.

## Canonical sources of truth (precedence)

Use these sources with the following roles:

- Current workspace contributor guidance
  - `.github/copilot-instructions.md`
- This contract
  - Authoritative for API version migration compliance, phase gating, precedence, core `APIMIG-*` rules, and this repository's migration-assistant design intent.
- Implementation compliance baseline for the code changes themselves
  - `.github/instructions/implementation-compliance-contract.instructions.md`
- Target-provider contributor guidance, when present in the workspace or explicitly fetched as evidence
  - `contributing/topics/guide-api-version.md`

Conflict resolution:

- This contract is authoritative for API version migration flow compliance in this repository.
- The implementation compliance contract remains authoritative for how the resulting Go code under `internal/**` is written; this contract adds the migration-flow gates on top of it.
- Current workspace contributor guidance is authoritative for repo-specific expectations that affect migration behavior, including terminal and build conventions.
- Target-provider contributor guidance is the baseline reference for the mechanical API version bump when workspace evidence is insufficient, but this contract may be stricter to keep the flow scoped and reviewable.
- If target-provider contributor guidance adds or tightens a standard, update this contract so coverage is preserved.
- If a companion migration guide differs from this contract, follow this contract and update the companion guide to re-align.

## Detailed companion guidance

These files provide worked examples, version-handling patterns, and migration heuristics. They are companion guidance, not an independent compliance layer:

- `.github/instructions/api-evolution-patterns.instructions.md`
- `.github/instructions/migration-guide.instructions.md`

## Rule IDs

Rules are identified by stable IDs so the skill, orchestrator prompt, and routing layer can reference the same requirements without drifting.

ID format:

- `APIMIG-<AREA>-<NNN>`

Areas:

- `READY` = SDK/API readiness gates
- `SCOPE` = migration scope and behavioral parity
- `BUILD` = build and format validation
- `RISK` = migration risk summary and breaking-change analysis
- `OWN` = engineer ownership boundary

## Evidence hierarchy

When a migration claim affects readiness, code mapping, risk severity, or the ownership boundary, use this evidence order:

1. Current workspace contributor guidance and this contract
2. The vendored or generated `go-azure-sdk` clients and models actually available in the workspace
3. Existing implementation patterns under `internal/**`, especially the same service package being migrated
4. Target-provider contributor guidance for the API version bump process when present
5. Azure service documentation for documented breaking changes and semantics only, not for inventing provider-only requirements

If evidence is missing for a behavior-changing claim, do not guess.

---

# Contract Rules

## Readiness

### APIMIG-READY-001: Verify the target API version is available before code changes
- Rule: Before editing any code, confirm the target ARM API version for the Resource Provider is available in the `go-azure-sdk` version vendored in the workspace.
- Rule: Treat the vendored SDK as the readiness source of truth; do not assume a newer API version is usable because it exists in swagger or upstream.
- **Provenance**: Published upstream standard.
- **Evidence**:
  - Upstream contributor guidance in `hashicorp/terraform-provider-azurerm/contributing/topics/guide-api-version.md` describes moving a resource provider to a newer ARM API version through the generated SDK stack
  - The vendored `go-azure-sdk` is the only workspace source of the target API version's client and model symbols, so migration code changes are not meaningful until that version is present there

### APIMIG-READY-002: Check hashicorp/pandora when the vendored SDK lacks the target version
- Rule: If the target API version is not in the vendored `go-azure-sdk`, do not hard-stop immediately; first check the upstream `hashicorp/pandora` repository to determine whether it already contains definitions for the target Resource Provider and API version.
- Rule: Treat `hashicorp/pandora` as the upstream source that generates `go-azure-sdk`, so its presence or absence of the target version determines which handoff guidance applies.
- Rule: While checking pandora, also enumerate the pandora data workarounds registered in the `hashicorp/pandora` GitHub repository under `tools/importer-rest-api-specs/internal/components/apidefinitions/parser/dataworkarounds` (the registry in `workarounds.go` plus the per-service `workaround_*.go` files) to determine whether any workaround is registered for the target Resource Provider at all, keying the search on the pandora `serviceName` for that Resource Provider rather than on the target API version; for each workaround found for that Resource Provider, evaluate `IsApplicable(serviceName, apiVersion)` and record whether it also applies to the target API version, then carry the findings into the risk summary per `APIMIG-RISK-004`.
- Rule: Do not narrow the enumeration to only workarounds whose `IsApplicable` matches the target API version, because a workaround registered for the Resource Provider but scoped to other versions is still relevant evidence of a known data quirk for that Resource Provider; report it and note its version applicability rather than treating a non-matching version as "no workaround".
- Rule: This `dataworkarounds` path lives in `hashicorp/pandora`, not in the terraform-provider-azurerm workspace, so enumerate it by reading the upstream repository through GitHub repository search or fetch; do not expect it under the local workspace tree, and treat its absence from the workspace as expected rather than as evidence that the target version has no workarounds.
- Rule: Match on the pandora-internal `serviceName` used by those workarounds, which can differ from the azurerm service package name (for example pandora `SecurityInsights`, `MachineLearningServices`, `LoadTestService`, or `OperationalInsights`), rather than assuming the workaround file or azurerm directory name equals the service name.
- **Provenance**: Published upstream standard.
- **Evidence**:
  - The `hashicorp/go-azure-sdk` repository documents that its API packages are generated from the `hashicorp/pandora` data/tooling, so pandora is the upstream origin for a given ARM API version
  - Upstream contributor guidance in `hashicorp/terraform-provider-azurerm/contributing/topics/guide-api-version.md` describes moving a resource provider to a newer ARM API version through the generated SDK stack that originates from pandora
  - The `dataworkarounds` package is part of the `hashicorp/pandora` importer tooling, not the terraform-provider-azurerm repository, so it is not present in this workspace and must be enumerated from the upstream `hashicorp/pandora` repository directly
  - The pandora `dataworkarounds` interface (`interface.go`) and registry (`workarounds.go`) show each `workaround` implements `IsApplicable(serviceName, apiVersion)` and `Name()`, patching parsed API definitions to fix data-correctness issues such as wrong field types, missing models, LRO detection, and identity/discriminator shapes, scoped to specific service and API version pairs

### APIMIG-READY-003: Give escalation guidance based on the pandora result, do not fabricate symbols
- Rule: If `hashicorp/pandora` already contains the target Resource Provider and API version, stop before code migration and direct the engineer to wait for or advance the `go-azure-sdk` regeneration/release that vendors it, rather than editing code against symbols that are not yet in the workspace.
- Rule: If `hashicorp/pandora` does not contain the target API version, stop and suggest that the engineer add the API version definitions to `hashicorp/pandora` first, since that is the upstream prerequisite for the version reaching `go-azure-sdk`.
- Rule: In either case, do not fabricate SDK symbols to proceed and do not partially edit code while readiness is unmet.
- **Provenance**: Local safeguard.
- **Evidence**:
  - This repository scopes the migration assistant to readiness verification before any code edits, so an unmet readiness state is a stop, not a proceed
  - Because `go-azure-sdk` is generated from `hashicorp/pandora`, an API version missing from pandora cannot appear in the SDK until it is added upstream, so the correct handoff is to add it there
  - Proceeding past an unavailable SDK version would require guessing model shapes, which the evidence hierarchy prohibits

## Scope

### APIMIG-SCOPE-001: Keep changes scoped to the API version bump
- Rule: Limit code changes to what the API version migration requires: updated SDK import paths and client references, model and field adjustments, and formatting.
- Rule: Do not perform unrelated refactors, feature additions, or opportunistic cleanups in the same migration.
- **Provenance**: Local safeguard.
- **Evidence**:
  - This repository limits the migration flow to the API version bump and treats unrelated refactors and feature additions as out of scope
  - Keeping the change set scoped keeps the resulting diff easy to review, which is the purpose of this flow

### APIMIG-SCOPE-002: Preserve behavioral parity and do not silently fix latent issues
- Rule: Preserve existing provider behavior, schema shape, and state semantics across the version bump unless the API change strictly requires a change.
- Rule: If the newer API version changes behavior or appears to expose a pre-existing bug, document it in the risk summary and wait for engineer approval before changing provider behavior.
- **Provenance**: Inferred maintainer convention.
- **Evidence**:
  - The `custom-poller-migration` skill in `.github/skills/custom-poller-migration/SKILL.md` establishes the repository convention that scoped migrations preserve parity and do not silently fix legacy bugs found during migration
  - This repository keeps behavior-change interpretation and the final risk call with the engineer, so suspected behavior changes are reported rather than silently applied

### APIMIG-SCOPE-003: Do not guess new API model shapes
- Rule: Do not guess field types, renamed properties, enum values, or nested shapes introduced by the target API version.
- Rule: Verify those details from the vendored `go-azure-sdk` models and clients before mapping them.
- **Provenance**: Inferred maintainer convention.
- **Evidence**:
  - The implementation compliance contract rule `IMPL-EVID-001` in `.github/instructions/implementation-compliance-contract.instructions.md` requires verifying API model structure from SDK/client evidence rather than guessing
  - Model shapes frequently change across ARM API versions, so unverified mappings risk silent state or behavior drift

## Build

### APIMIG-BUILD-001: Validate compile and formatting before the risk summary
- Rule: After applying scoped changes, validate that the affected packages compile and are formatted using the Go toolchain, and treat build success as a required gate before producing the risk summary.
- Rule: Run Go toolchain build and format commands through the WSL terminal per workspace terminal conventions rather than treating build success as an optional signal.
- Rule: After the build is clean, run `make fmt` and `make document-fix` through the WSL terminal to keep code formatting and generated documentation in sync.
- Rule: Treat `make document-fix` as a required, non-skippable step of this gate; do not skip it, and do not rationalize skipping it as a no-op on the assumption that no schema or docs surface changed, because an API version bump can change documented content and provider documentation can reference the prior API version.
- **Provenance**: Inferred maintainer convention.
- **Evidence**:
  - Current workspace contributor guidance in `.github/copilot-instructions.md` states Go toolchain commands in this repository should be run through the WSL terminal
  - This repository treats a clean build as the captured confidence signal that gates the risk summary before review
  - `make fmt` and `make document-fix` are the target provider's Makefile targets for normalizing code formatting and regenerating documentation, so running them keeps the migration change set consistent with the formatting and docs the repository expects
  - An API version migration can change documented content and provider documentation can carry the prior API version, so skipping `make document-fix` as an assumed no-op can leave stale documentation in the change set

## Risk

### APIMIG-RISK-001: Produce a migration risk summary before handoff
- Rule: Before handing back to the engineer, produce a migration risk summary that includes the scoped code changes made, model or behavior differences observed, and residual risk to Terraform state or user experience.
- Rule: Present the risk summary as review input, not as a claim that the migration is verified end to end.
- Rule: State explicitly that a clean build and the documentation check cannot confirm runtime behavioral parity, and mark the migration `UNVERIFIED` because compile-time and documentation checks cannot observe runtime service behavior.
- Rule: In the summary, call out the specific runtime risks this bump carries, including changed API semantics, altered defaults, and changed long-running-operation or poller behavior, that a clean build alone cannot clear.
- **Provenance**: Local safeguard.
- **Evidence**:
  - This repository requires a short migration risk summary covering the scoped code changes as the flow's final deliverable
  - The migration report is an assistant deliverable, while the final risk call stays with the engineer
  - Compile-time validation and first-party documentation checks cannot observe runtime service behavior, so behavioral breaking changes introduced by an API version bump remain unproven at the end of this flow

### APIMIG-RISK-002: Check documented breaking changes for the target API version via the Microsoft Learn MCP (blocking, tri-state)
- Rule: Treat the documented-breaking-change check as a required blocking step of the risk summary: do not emit the risk summary until this check has been attempted and its result recorded, and use the Microsoft Learn MCP tools (`microsoft_docs_search`, then `microsoft_docs_fetch` on the most relevant pages) as the first-party source for breaking changes between the current and target API version.
- Rule: Record the result as an explicit tri-state and surface it in the risk summary: `documented-breaking-changes: found` (list each as a risk item), `documented-breaking-changes: none-found` (state that absence is not a guarantee), or `documented-breaking-changes: did-not-run` (state the Microsoft Learn MCP was unavailable or the check could not complete).
- Rule: When the status is `did-not-run`, carry it as an explicit open item in the risk summary and keep the migration `UNVERIFIED`; never present an unavailable or skipped check as `none-found`, and never imply the version is clean because the check did not complete.
- Rule: Do not assert the absence of breaking changes as a guarantee even on a completed `none-found` result, because first-party documentation does not necessarily cover every service-side behavior change.
- **Provenance**: Local safeguard.
- **Evidence**:
  - This repository includes a first-party documentation check for breaking changes documented in the target API as part of the summary, and the Microsoft Learn MCP is the available first-party documentation retrieval surface in this workspace
  - Making the check blocking with an explicit tri-state prevents a silently-skipped scan from being reported as a clean result, mirroring the unavailable-source asymmetry in `APIMIG-RISK-004`
  - This flow does not guarantee detection of every service-side behavior change, so documented breaking changes are recorded as explicit risk items and their absence is never asserted as a guarantee

### APIMIG-RISK-003: Classify provider-facing changes against the breaking-change guideline
- Rule: In the risk summary, classify every resulting provider schema or behavior change against the breaking-change guardrails and flag each match as a breaking-change review item, including property renames, stricter validation, default changes, type changes, Optional-to-Required shifts, and removal of `Computed` behavior.
- Rule: When an API version bump alters defaults or behavior for existing resources, treat it as a breaking-change review item held for engineer approval and point to the major-release feature-flag and migration handling rather than silently shipping a minor-release breaking change.
- **Provenance**: Published upstream standard.
- **Evidence**:
  - Upstream contributor guidance in `hashicorp/terraform-provider-azurerm/contributing/topics/guide-breaking-changes.md`, tracked in `tools/config/upstream-contributor.json` under the `breaking-changes-and-deprecations` domain, is the primary source for breaking-change handling and feature-flag staging
  - Companion guidance in `.github/instructions/migration-guide.instructions.md` under `Breaking Change Guardrails` enumerates the schema and behavior change classes to treat as breaking unless proven otherwise
  - Companion guidance in `.github/instructions/api-evolution-patterns.instructions.md` states an API version change that alters defaults or behavior for existing resources is a breaking-change review item that must be coordinated with major-release feature-flag and migration guidance

### APIMIG-RISK-004: Surface pandora data workarounds as an asymmetric risk signal
- Rule: In the risk summary, list every pandora data workaround registered for the target Resource Provider (matched by pandora `serviceName`, by `Name()` and the correctness issue it patches), reading them from the `hashicorp/pandora` GitHub repository rather than the local workspace, and for each note whether `IsApplicable(serviceName, apiVersion)` also applies to the target API version; treat each as a known upstream data quirk for that Resource Provider that can change model shape, LRO/poller behavior, or field typing, held as an open runtime-risk item per the `UNVERIFIED` status in `APIMIG-RISK-001`.
- Rule: Frame the check as "does a workaround exist for this Resource Provider", not "does a workaround match this exact target version"; a workaround registered for the Resource Provider but scoped to other API versions is still a reportable quirk, and must not be reported as "no workaround" merely because it does not apply to the target version.
- Rule: Treat the workaround signal as one-directional: workarounds registered for the Resource Provider are positive evidence of a known quirk, but the absence of any workaround for the Resource Provider must not be described as evidence that the target version is clean, and must not clear the `UNVERIFIED` status.
- Rule: Distinguish a genuine no-match result from an unavailable-source result: if the `hashicorp/pandora` `dataworkarounds` package could not be enumerated at all (for example the upstream repository was not reachable, or the path was looked for only in the local workspace where it does not exist), report that enumeration did not run rather than reporting zero matching workarounds, and never present that unavailability as evidence of a clean version.
- Rule: For newer target API versions especially, note that data-workaround coverage can lag the API version, so an absent workaround more likely means one has not been added yet than that the version needs none.
- **Provenance**: Local safeguard.
- **Evidence**:
  - The pandora `dataworkarounds` package README describes these as short-term, reactive patches added after data-correctness issues are found, so their presence is meaningful but their absence does not prove a version is free of data issues
  - The `dataworkarounds` package is not vendored into the terraform-provider-azurerm workspace, so a failed or workspace-only lookup means the source was not consulted, which is different from a confirmed no-match against the upstream `hashicorp/pandora` repository
  - This asymmetry mirrors `APIMIG-RISK-002`, which records documented breaking changes as explicit risk items and forbids asserting the absence of breaking changes as a guarantee

## Ownership

### APIMIG-OWN-001: Preserve the engineer ownership boundary
- Rule: Keep the target API version choice, runtime verification, failure interpretation, final risk call, and PR submission with the engineer.
- Rule: Do not submit pull requests, choose which API versions the provider should adopt, or replace maintainer review as part of this flow.
- **Provenance**: Local safeguard.
- **Evidence**:
  - This repository assigns the target API version choice, runtime verification, failure interpretation, final risk call, and PR submission to the engineer
  - Submitting pull requests automatically and replacing maintainer review are out of scope for this flow

<!-- APIMIG-CONTRACT-EOF -->
