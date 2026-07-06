---
description: "Shared code review compliance contract used by /code-review-local-changes and /code-review-committed-changes."
---

# Code Review Compliance Contract

This file is the single source of truth for code review compliance in this repository.

## Consumers

Two independent review workflows MUST follow this contract:

- Consumer: `.github/prompts/code-review-local-changes.prompt.md`
  - Role: Auditor
  - Requires EOF Load: yes
  - Goal: review local workspace changes deterministically.
- Consumer: `.github/prompts/code-review-committed-changes.prompt.md`
  - Role: Auditor
  - Requires EOF Load: yes
  - Goal: review committed branch changes deterministically.

The prompts define the execution flow and output template.
This core contract defines the shared review rules, evidence hierarchy, finding classification, handoff model, coverage routing, and output semantics.
`azurerm-linter` execution and reporting are defined by `.github/instructions/review-linter-compliance-contract.instructions.md`.

## Canonical sources of truth (precedence)

Use these sources with the following roles:

- Workspace contributor guidance
  - Repo-level contributor documentation in common workspace locations such as `CONTRIBUTING.md` and `contributing/README.md`
  - .github/pull_request_template.md
  - README or subsystem documentation when directly relevant to touched files
- Workspace file-scoped instructions and skills
  - .github/instructions/**/*.instructions.md
  - .github/skills/**/SKILL.md
- Target-provider contributor guidance, when present in the workspace or explicitly fetched as evidence
  - contributing/topics/**/*.md
  - Especially acceptance testing, documentation, naming, schema, and PR guidance in hashicorp/terraform-provider-azurerm
- This contract
  - Authoritative for review methodology in this repository
  - Defines evidence rules, classification rules, and linter reporting requirements

Conflict resolution:

- This contract is authoritative for review process, finding classification, verification requirements, and linter section behavior.
- Current workspace contributor documentation is authoritative for repo-specific expectations.
- File-scoped instructions and loaded skills are authoritative for the files they govern.
- If older prompt wording conflicts with current contributor guidance or file-scoped instructions, follow the contributor guidance and this contract.
- If upstream provider guidance is used, it must not override explicit current-workspace guidance unless the workspace is the provider repo under review or the workspace guidance explicitly defers to upstream.

## Rule IDs

Rules are identified by stable IDs so both review prompts can reference the same requirement set without drifting.

ID format:
- REVIEW-<AREA>-<NNN>

Areas:
- EVID = evidence and verification guardrails
- CLASS = finding classification
- COVER = deterministic coverage routing and review order
- FILE = change-set coverage and file handling
- SCOPE = file-type-specific review coverage
- TEST = acceptance test review guidance
- OBS = observation-only design guidance
- OUT = required review output semantics

## Evidence hierarchy

When a review claim affects correctness, severity, or merge readiness, use this evidence order:

1. Changed files and the actual diff under review
2. Current workspace contributor guidance and file-scoped instructions
3. Current workspace implementation details, tests, and surrounding code
4. Tool output, including azurerm-linter
5. External references for semantics only, when workspace evidence is insufficient

If evidence is missing for a claim that would change severity or requested action, do not guess.

# Contract Rules

## Evidence and verification

### REVIEW-EVID-001: Do not guess when evidence is required
- Rule: If a compliance-relevant or correctness-relevant claim cannot be backed by available evidence, do not invent it.
- Reviewer behavior: downgrade to an Observation, ask for clarification, or explicitly state that evidence could not be proven.

### REVIEW-EVID-002: Verify display artifacts before flagging formatting or encoding issues
- Rule: Terminal wrapping, diff truncation, and chat rendering artifacts must be verified against actual file content before being reported as Issues.
- Reviewer behavior: use file reads to confirm the content before flagging syntax, formatting, encoding, or line-break corruption.

### REVIEW-EVID-003: Attribute policies to real sources
- Rule: Do not claim that a style or implementation rule is mandatory unless it is supported by a current contributor document, instruction file, skill, implementation pattern, or this contract.
- Reviewer behavior: avoid invented policy language such as "must" or "required" when the source only supports a preference.

### REVIEW-EVID-004: Discover contributor-guidance paths before claiming absence
- Rule: Do not assume repo-level contributor guidance always lives at `CONTRIBUTING.md`.
- Rule: Check common workspace locations such as `CONTRIBUTING.md` and `contributing/README.md` before claiming contributor guidance is absent.
- Rule: When reviewing a `terraform-provider-azurerm` style workspace, treat `contributing/README.md` as repo-level contributor guidance when present.

### REVIEW-EVID-005: Perform post-tool verification silently
- Rule: When tool output needs confirmation against current file content, diff context, or surrounding code, perform that verification silently.
- Rule: Do not narrate intermediate verification steps such as reading files, checking lines, confirming linter findings, or comparing tool output against workspace content.
- Rule: Reviews should present only the final evidence-backed conclusions, not the internal process used to reach them.

### REVIEW-EVID-006: Every invocation is a fresh audit run
- Rule: Every invocation of a code review prompt is a new audit run.
- Rule: Do not reuse prior git output, linter output, file classifications, or review conclusions from earlier turns in the conversation.
- Rule: A previous review in the conversation is not evidence for the current run.
- Rule: All review findings must be based on commands and file reads executed during the current invocation.
- Rule: If the required commands for the selected review type were not rerun in the current invocation, do not emit a normal review output.

### REVIEW-EVID-007: Describe only current-run facts
- Rule: Do not compare the current review invocation to earlier invocations in user-visible output.
- Rule: Do not use comparative carry-over wording such as `still`, `again`, `reloaded`, `same as before`, `remains`, or `continues` when describing current-run evidence unless directly quoting user input or tool output.
- Rule: State current-run facts directly from the evidence gathered in the current invocation.

### REVIEW-EVID-008: Do not reuse prior review body text
- Rule: Do not reuse, quote, paraphrase, or summarize a prior review body as the current review output, even when the reviewed change-set and findings are unchanged.
- Rule: Reconstruct the review body from current-run evidence and the current prompt/template requirements for every invocation.

### REVIEW-EVID-009: Do not use helper scripts for trivial deterministic checks
- Rule: For trivial deterministic facts that can be derived directly from the diff or file content, do not run ad hoc scripts, helper commands, or terminal calculations merely to prove them.
- Rule: Examples include string length checks, substring presence, obvious regex-shape checks, simple line counts, literal value comparisons, and other facts that can be reasoned from the reviewed content without external execution.
- Rule: Use direct file evidence and reviewer reasoning for those facts unless the user explicitly asks for executable validation.
- Reviewer behavior: do not create or run focused shell snippets, PowerShell expressions, WSL commands, or one-off scripts just to verify a trivial literal property during normal review flow.

### REVIEW-EVID-010: Do not invent prerequisite or validation scripts
- Rule: Do not invent, assume, or execute repo-local prerequisite scripts, validation wrappers, or helper entrypoints unless they are explicitly named by the active prompt, the shared contract, current workspace guidance, or the user.
- Rule: In review flow, a nonexistent or unstated script name such as a made-up `validate-*.ps1` helper is not valid evidence gathering.
- Reviewer behavior: if a needed validation path is not explicitly provided by the prompt or workspace guidance, use the approved direct evidence paths instead of creating or invoking a guessed script.

## Finding classification

### REVIEW-CLASS-001: Issues are for actual problems only
- Rule: An Issue must be a real defect, regression, policy violation, missing requirement, or correctness risk with evidence.
- Rule: Do not place stylistic preferences or speculative concerns in Issues.

### REVIEW-CLASS-001A: Blocking classification requires concrete current-run harm
- Rule: Keep a concern in `ISSUES` only when current-run evidence proves a present defect, destructive behavior, policy violation, concrete state corruption risk, or another clearly blocking correctness failure.
- Rule: If current-run evidence proves only broader architectural risk, request-shape risk, uncertainty, or a non-blocking mismatch, classify that concern as an `OBSERVATION` unless another rule family explicitly says the concern is blocking by definition.

### REVIEW-CLASS-001B: Certain variant-ownership and lifecycle defects are blocking by definition
- Rule: For a variant-constrained managed surface, if current-run evidence shows that a generic identifier, generic ID validator, generic importer, or generic lookup path can admit or hydrate a foreign variant before a later discriminator check rejects it, that ownership-boundary concern is blocking by definition and must remain in `ISSUES`.
- Rule: For that same variant-constrained surface, if current-run evidence shows that a later lifecycle window such as delete can still mutate or destroy the foreign variant after read or update already applies a discriminator guard, that lifecycle-symmetry concern is blocking by definition and must remain in `ISSUES`.
- Rule: Do not downgrade either of those concrete foreign-variant admission or destruction paths to `OBSERVATIONS` merely because the current run did not execute a live foreign-variant fixture.

### REVIEW-CLASS-001C: Concrete optional-state drift on user-managed fields is blocking by definition
- Rule: When current-run evidence shows that a user-managed map or object field can round-trip undeclared API-added keys or values back into Terraform state through read or import, that optional-state-drift concern is blocking by definition and must remain in `ISSUES`.
- Rule: When current-run evidence shows that import verification already has to ignore a user-managed field because read or import cannot round-trip the configured value cleanly, treat that as blocking optional-state drift unless another current-run source proves the ignored field is intentionally non-user-managed.

### REVIEW-CLASS-002: Observations are non-blocking
- Rule: Observations capture design concerns, preferences, uncertainty, or follow-up ideas that are not clearly blocking.
- Rule: If the current implementation is acceptable under the available evidence, keep it out of Issues even if another design might be preferable.

### REVIEW-CLASS-002A: Evidence-backed non-blocking concerns must remain visible
- Rule: If a mandatory issue-class check or routed pass yields an evidence-backed non-blocking concern, that concern must appear in the final output under `OBSERVATIONS`.
- Rule: Do not omit such a concern solely because another issue already blocks merge, because the concern does not change the overall verdict, or because a shorter review would be more convenient.

### REVIEW-CLASS-002B: Update-shape and residual-state risks default to observations unless concrete harm is proven
- Rule: When current-run evidence shows an update-shape or residual-state risk such as a `PUT` versus `PATCH` mismatch, broader-than-expected update request shape, or omitted-field preservation concern, but does not prove a present destructive behavior, policy violation, or concrete state corruption path, classify that concern as an `OBSERVATION`.
- Rule: Do not drop that concern merely because stronger ownership, lifecycle, or import-drift issues already exist in the same review.

### REVIEW-CLASS-003: Strengths must be factual
- Rule: Strengths should call out concrete, evidenced positives.
- Rule: Do not use Strengths to pad the review with generic praise.

### REVIEW-CLASS-004: One finding, one classification
- Rule: The same underlying concern must not appear in both Observations and Issues.
- Rule: If severity is uncertain, choose the lower justified classification and explain why.

### REVIEW-CLASS-005: Fixes must be deterministic
- Rule: Each Issue should point to a single, concrete correction path.
- Rule: Do not present multiple alternative fixes unless the user explicitly asked for options.

### REVIEW-CLASS-006: Final moderation owner integration boundary
- Rule: The final moderation owner is the `review-moderator` skill (`.github/skills/review-moderator/SKILL.md`) and its dedicated contract (`.github/instructions/review-moderator-compliance-contract.instructions.md`).
- Rule: The advocate pass is the `review-advocate` skill (`.github/skills/review-advocate/SKILL.md`) and its dedicated contract (`.github/instructions/review-advocate-compliance-contract.instructions.md`); it adds commentary to the full findings set but does not own final visibility or final classification.
- Rule: When a review prompt runs the final moderation owner, the routed owner's rules govern how the full workflow findings set is merged, normalized, classified, retained, or omitted as duplicate for final visible output.
- Rule: The final moderation owner must not violate `REVIEW-CLASS-004`; every surviving concern still resolves to exactly one classification.
- Rule: This shared contract does not define the routed moderation owner's method or merge rules; review flows that do not run a final moderation owner are unaffected.

## Workflow handoff structure

### REVIEW-HANDOFF-001: Intermediate findings use one shared semantic shape
- Rule: Before output is frozen, the review workflow must treat routed-role findings as internal intermediate records rather than free-form unlabeled prose.
- Rule: Each intermediate record must conform to `.github/instructions/review-workflow-handoff.schema.json`.
- Rule: Each intermediate record must be able to express `id`, `roles`, `title`, `scope`, `severity`, `evidence`, `reasoning`, `confidence`, `classification`, and `visible`.
- Rule: `ruleReferences` is optional, but should be populated when a contract rule, instruction, or contributor-guidance source is part of the evidence chain.

### REVIEW-HANDOFF-002: Classification and visibility are workflow-owned fields
- Rule: The reviewer, architect, and skeptic passes may emit records classified as `issue` or `observation` based on current-run evidence.
- Rule: The advocate pass consumes the full finding set and communicates through `roleNotes`; it must not delete findings or replace them with a candidate-only state machine.
- Rule: The moderator pass consumes the full finding set, may merge genuine duplicates, and owns the final `classification` and `visible` values on surviving records.
- Rule: Final visible `ISSUES` and `OBSERVATIONS` sections are derived mechanically from moderated records where `visible=true`, grouped by their moderated `classification` values.

### REVIEW-HANDOFF-003: Routed passes may add or refine records, but must preserve shape
- Rule: The primary review pass, architect pass, and skeptic pass may add records or enrich existing records with evidence and reasoning, and later routed passes may annotate or normalize those records, but all passes must preserve the shared field set.
- Rule: Routed passes must not replace a structured intermediate record with an unlabeled prose note that loses `scope`, `evidence`, `classification`, or `visible`.
- Rule: When multiple passes touch the same concern, enrich one record rather than cloning duplicate records.
- Rule: When a record carries originating mandatory `issueClasses` lineage, routed passes must preserve that lineage unless a later moderator-owned genuine duplicate merge consolidates it under one survivor.

### REVIEW-HANDOFF-005: Roles communicate through schema updates, not free-form debate
- Rule: Routed roles communicate by adding evidence, reasoning, `roles`, `ruleReferences`, or `roleNotes` to the shared schema record, not by inventing a separate unstructured dialogue channel.
- Rule: If a role challenges an earlier finding, that challenge must be recorded inside the shared schema record rather than as disconnected prose.

### REVIEW-HANDOFF-006: Reviewer-to-handoff serialization is mandatory before routed roles
- Rule: If the primary review pass discovers an evidence-backed concern, that concern must exist as a schema-conformant `REVIEW-HANDOFF-*` record before `review-architect`, `review-skeptic`, `review-advocate`, or `review-moderator` begin.
- Rule: The workflow must fail closed if the reviewer analysis says a concern exists but no corresponding structured handoff record was emitted for it.
- Rule: Routed roles and the presentation layer are not responsible for recovering findings that the reviewer failed to serialize into the handoff record set.

### REVIEW-HANDOFF-006A: Mandatory issue-class concerns emit records immediately
- Rule: When a mandatory issue-class check yields an evidence-backed concern, the primary review pass must emit the corresponding schema-conformant `REVIEW-HANDOFF-*` record immediately rather than deferring serialization to a later bulk step.
- Rule: The primary review pass must update the applicable row-level and matrix-level linkage state for that emitted record before moving to the next mandatory issue-class check or control window.
- Rule: A mandatory issue-class concern must not exist only in reviewer memory or transient prose notes while the workflow continues auditing other checks.
- Rule: When a record is emitted for a mandatory issue-class concern, preserve the originating `issueClasses` value on that record so later workflow stages can validate concern-family survival mechanically.

### REVIEW-HANDOFF-004: The handoff shape is semantic, not transport-specific
- Rule: The workflow may represent the intermediate record as structured markdown, table-like text, or JSON-like state, but the semantic fields and statuses must remain stable.
- Rule: The intermediate record is workflow-internal and must not force a new reader-visible section in the final review body.

## Deterministic coverage routing

### REVIEW-COORD-001: Build a deterministic coverage matrix before findings
- Rule: After the selected review scope is resolved and changed files are classified, the workflow must build a deterministic coverage matrix before findings are drafted or frozen.
- Rule: The workflow must load `.github/instructions/review-coverage-matrix.schema.json` to EOF before building the matrix.
- Rule: The coverage matrix must enumerate the applicable implementation file families, required lifecycle/control windows, required overlap surfaces, and mandatory issue-class checks for the current run.
- Rule: The coverage matrix must have a structured internal representation that conforms to `.github/instructions/review-coverage-matrix.schema.json`; prose intent alone is insufficient.
- Rule: The coverage matrix is part of review methodology, not an optional reviewer aid.

### REVIEW-COORD-001A: Matrix build and matrix completion are separate phases
- Rule: The workflow must build the structured coverage matrix before findings are drafted, but it must not require final matrix completion before the applicable workspace standards and scoped guidance needed for standards-dependent issue-class checks have been loaded.
- Rule: Matrix construction happens before standards-dependent finding analysis; matrix completion validation happens after the relevant contributor guidance, file-scoped instructions, and contracts needed for the required issue-class checks are available.
- Rule: Findings and routed roles remain blocked until the later completion-validation phase succeeds.

### REVIEW-COORD-002: Changed implementation files use a fixed review order
- Rule: For changed implementation files under `internal/**/*.go`, the workflow must sort the applicable implementation files lexically before choosing a first review anchor.
- Rule: For each applicable resource, data source, list-resource, ephemeral-resource, or provider-function surface, inspect present lifecycle/control windows in this fixed order: `Importer`, `Create`, `Read`, `Update`, `Delete`, `CustomizeDiff`, explicit validation or mode or ownership helpers, then companion registration, tests, docs, and association surfaces when applicable.
- Rule: If a given window does not exist for that surface, record it as not applicable and continue with the next required window rather than changing the order.
- Rule: Freeform surrounding reads may happen only after the required control-window reads for the current matrix row are complete.

### REVIEW-COORD-003: New resources require overlap and ownership scans
- Rule: When review scope adds a brand-new resource under `internal/**/*.go`, the workflow must inspect overlapping pre-existing sibling surfaces that can manage the same remote object even when those sibling surfaces are unchanged in the diff.
- Rule: The required overlap set includes, when applicable, the new resource itself, existing resources that can overlap ownership, existing data sources or list resources that expose the same remote object shape, route or association or referencing surfaces, and explicit mode or ownership validation helpers.
- Rule: Overlap surfaces for new resources must be materialized as explicit file-path rows in the structured coverage matrix, not merely as inferred categories.
- Rule: Overlap surfaces must be added to the deterministic coverage matrix and inspected with the same fixed control-window order when those windows exist.

### REVIEW-COORD-003A: Variant-constrained ownership surfaces prioritize ownership and lifecycle first
- Rule: For a new or materially changed managed surface whose ownership is constrained to a discriminator, mode, subtype, or other remote-object variant, the first cold-review priority is ownership boundary and lifecycle symmetry, not secondary polish findings.
- Rule: Before treating metadata filtering, test-shape completeness, or similar secondary concerns as the lead finding, the workflow must first answer whether the surface can adopt foreign variants, mutate foreign variants, destroy foreign variants, and keep import or read or update or delete behavior symmetric for variant ownership.
- Rule: For a variant-constrained managed surface, the primary review pass must explicitly complete and record the outcome of the ownership-boundary and lifecycle-symmetry checks before freezing any later issue class on that same surface.
- Rule: If current-run evidence does not support an ownership-boundary or lifecycle-symmetry concern, the workflow must still justify that completion from the inspected importer, identifier validation, lookup, read, update, and delete paths rather than skipping straight to secondary findings.
- Rule: If the importer, ID validator, lookup helper, or read path accepts a generic identifier that can resolve to foreign variants outside the surface's intended ownership slice, treat that as an immediate trigger for ownership-boundary inspection rather than a downstream follow-up check.
- Rule: When current-run evidence on the managed surface itself shows that a generic identifier, importer, ID validator, lookup helper, or read path can resolve or hydrate an out-of-scope object into state, the workflow must materialize an ownership-boundary concern immediately at the justified classification; do not wait for an unchanged sibling overlap surface before emitting that record.
- Rule: A variant-constrained surface that uses a generic ID type, generic ID validator, or generic lookup helper and only checks the discriminator after the lookup or read has already resolved the remote object has already shown enough evidence for an ownership-boundary concern unless the earlier identifier or lookup path itself enforces the discriminator.
- Rule: When read or update contains a discriminator or subtype guard only after a generic ID or generic lookup path has already resolved the remote object, treat that as affirmative evidence that foreign variants can be admitted into the lifecycle and emit the ownership-boundary concern immediately.
- Rule: When the same variant-constrained surface can admit an out-of-scope object through import or read, but later lifecycle windows reject it, mutate it inconsistently, or still delete it, the workflow must materialize a distinct lifecycle-symmetry concern immediately before moving on to other issue classes on that surface such as update-shape-and-residual-state, optional-state-drift, minimum acceptance-matrix coverage, or docs-example correctness.
- Rule: When the same surface shows a read-time or update-time discriminator guard after generic resolution, inspect delete against that same path immediately. If delete still proceeds on the generic ID without the same guard, materialize the lifecycle-symmetry concern even when no explicit foreign-variant fixture exists in the current test suite.

### REVIEW-COORD-004: Provider reviews have mandatory issue-class checks
- Rule: For new or changed provider resources, data sources, or list resources under `internal/**/*.go`, the workflow must perform mandatory issue-class checks rather than relying on ad hoc reviewer heuristics alone.
- Rule: The mandatory issue-class families are ownership overlap, import or read or update or delete mode-gating symmetry, destructive-path gating, poller terminal-failure handling, validator-to-doc parity for blocking conditions, companion artifact completeness, list-resource exception handling, identity/list/docs/test companion coverage, update-shape-and-residual-state behavior, optional-state-drift behavior, and upstream-minimum acceptance-test matrix coverage for brand-new managed resources with acceptance tests.
- Rule: When the same review scope also includes changed reference docs under `website/docs/**/*.html.markdown`, the mandatory issue-class set also includes evidence-backed docs example correctness under exact `DOCS-*` support from the docs contract.
- Rule: For docs example correctness in generic review, acceptance-test-backed or implementation-backed Terraform HCL is sufficient local evidence for user-facing field-key, map-key, and casing parity when the docs Example is demonstrating that same user-facing configuration shape; do not require a separate API-layer proof before surfacing that mismatch.
- Rule: When changed docs and local acceptance-test-backed or implementation-backed HCL both show the same Terraform argument as a map or object literal, the review must compare those keys directly for spelling/casing parity and surface the mismatch as docs-example correctness when they differ.
- Rule: For variant-constrained managed surfaces, ownership-boundary and lifecycle-symmetry checks remain mandatory first-pass issue classes under `REVIEW-COORD-003A`, and later issue classes do not satisfy them.
- Rule: For user-managed map or object fields on changed provider surfaces, optional-state-drift is applicable when current-run evidence shows read or import can rehydrate API-added keys or values that were not declared in configuration, including cases where the implementation falls back to full API metadata when prior configured values are absent.
- Rule: For that same optional-state-drift issue class, an acceptance test that already needs to ignore a user-managed field during import verification is affirmative current-run evidence that the field may not round-trip cleanly and must be reviewed as a potential emitted concern rather than dismissed as a mere test quirk.
- Rule: For update-shape-and-residual-state behavior, `patch-residual-state` is applicable when current-run evidence shows that the update path uses a broader request method or shape than the surrounding provider or service pattern expects, including `PUT` versus `PATCH` mismatches, and that mismatch could preserve, replace, or broaden unspecified fields in ways the current run cannot fully prove safe.
- Rule: When current-run evidence proves only that broader request-shape or residual-state risk, emit `patch-residual-state` as an observation rather than suppressing it for lack of already-proven destructive harm.
- Rule: Treat the primary review pass as a broad serializer: when an applicable issue class yields an evidence-backed concern, emit that concern immediately as its own shared handoff record and keep it separate unless it is genuinely the same underlying concern as another emitted record.
- Rule: The primary review pass must not suppress, merge, downgrade, dismiss, or otherwise filter an evidence-backed concern merely because another concern appears stronger or more likely to determine the final verdict; downstream routed stages own that filtering work.
- Rule: If an applicable mandatory issue class does not yield a concern, the current run must still complete it with evidence-backed justification through the structured matrix state rather than leaving it implicit.

### REVIEW-COORD-005: Active-file bias is forbidden for initial routing
- Rule: The active editor file, search result ordering, or PR wording must not decide the initial review route for committed or local review.
- Rule: The active editor file may be used only as a convenience after the deterministic coverage matrix is built.
- Rule: If the active file belongs to a required matrix row, review it when that row's fixed order is reached rather than jumping to it early.

### REVIEW-COORD-005A: Family grouping prefers explicit code anchors over filename intuition
- Rule: When the workflow groups files into a resource family, it should prefer explicit code anchors over filename intuition alone.
- Rule: Relevant anchors include shared ID parsers, shared validation helpers, shared registration entries, shared route or association references, shared ownership or mode helpers, shared ARM ID types, and shared SDK client methods or resource paths that manage the same remote object.
- Rule: For a variant-constrained managed surface, an unchanged sibling resource, data source, or list resource is an overlap surface when it shares the same ARM ID type or the same SDK `Get`/`Create`/`Update`/`Delete` remote-object method family, even if the sibling surface is more generic than the changed resource.
- Rule: When those shared-ID or shared-method anchors exist, the overlap surface must be materialized as its own explicit file-path row in the matrix rather than left implicit in prose.
- Rule: If family boundaries remain ambiguous after checking those anchors, prefer broader inclusion in the coverage matrix over omission.

### REVIEW-COORD-006: Findings cannot freeze before coverage completion
- Rule: Findings, routed review-role passes, and final output must not freeze until the deterministic coverage matrix is complete.
- Rule: A coverage-matrix row is complete only when every required window is present in `completedWindows` or `notApplicableWindows`, and every required issue class is present in `completedIssueClasses` or `notApplicableIssueClasses`.
- Rule: A coverage matrix is complete only when every required row is complete, every top-level required issue class is present in `completedIssueClasses` or `notApplicableIssueClasses`, and all not-applicable states are justified by current-run evidence.
- Rule: A required issue class must not be marked `completed` if the reviewer found an evidence-backed concern in that class but failed to serialize it into the shared `REVIEW-HANDOFF-*` record set at the justified classification, including `observation` when the concern is non-blocking.
- Rule: A required issue class that found an evidence-backed concern must link that concern to at least one handoff record ID through `issueClassToRecordIds` before the issue class can be marked `completed`.
- Rule: Every handoff record ID referenced by a row-level `issueClassToRecordIds` entry must also appear in that row's `emittedRecordIds` and in the matrix-level `emittedRecordIds`.
- Rule: Before any routed role begins, the workflow must assert that every evidence-backed concern discovered in the primary review pass is represented by at least one emitted handoff record ID; if that assertion fails, the review must hard-stop.
- Rule: The primary review pass must keep `emittedRecordIds` and `issueClassToRecordIds` current as concerns are discovered so the later linkage-validation phase is validating already-emitted workflow state rather than reconstructing reviewer memory after the fact.
- Rule: Standards-dependent issue-class checks may be marked complete only after the relevant workspace standards and scoped guidance needed to evaluate them have been loaded in the current run.
- Rule: When a mandatory overlap surface or issue-class check has not been completed, the workflow must continue auditing rather than drafting or freezing findings.

### REVIEW-COORD-006A: Router validation sub-phase is the canonical completion gate
- Rule: The router's validation sub-phase is the canonical mechanism that confirms coverage-matrix completion before findings or routed roles can proceed.
- Rule: Prompts may orchestrate when that validation sub-phase runs, but they must not substitute looser prose-only completion checks for the router-owned validation step.
- Rule: If the router validation sub-phase cannot confirm the required row, window, issue-class, overlap-row, and evidence-backed completion invariants from current-run evidence, the workflow must hard-stop rather than continue to findings or routed roles.

### REVIEW-COORD-006B: Router owns post-review handoff-linkage validation before routed roles
- Rule: After the primary review pass has drafted its frozen current-run findings set and before any routed role begins, the workflow must invoke a router-owned post-review linkage-validation sub-phase.
- Rule: That router-owned linkage-validation sub-phase is the canonical mechanism that confirms reviewer-to-handoff synchronization, including `emittedRecordIds` and `issueClassToRecordIds`, before routed roles can proceed.
- Rule: Prompts may orchestrate when that linkage-validation sub-phase runs, but they must not replace it with a prompt-only bookkeeping assertion.
- Rule: If the router-owned linkage-validation sub-phase cannot confirm that every evidence-backed concern discovered in the primary review pass is represented by at least one emitted handoff record ID, the workflow must hard-stop rather than continue to architect, skeptic, advocate, or moderator.
- Rule: For variant-constrained ownership reviews whose current-run evidence supports separate ownership-boundary, lifecycle-symmetry, update-shape-and-residual-state, and optional-state-drift concerns, linkage validation must confirm those concerns remain separate records at the justified classifications rather than a collapsed prose summary.
- Rule: For variant-constrained managed-surface reviews whose current-run evidence makes ownership-boundary, lifecycle-symmetry, update-shape-and-residual-state, optional-state-drift, minimum acceptance-matrix coverage, or docs-example correctness applicable, linkage validation must confirm each applicable issue class ended as a separate emitted record or an evidence-backed completed/non-applicable state rather than disappearing into a partial subset of findings.
- Rule: When current-run evidence for the update path includes a `PUT` versus `PATCH` mismatch or another broader request-shape residual-state risk, linkage validation must not accept `patch-residual-state` as implicitly covered by ownership, lifecycle, optional-state-drift, or acceptance-matrix concerns; it must end as its own emitted record or an evidence-backed non-applicable state.
- Rule: When current-run evidence for a user-managed map or object field includes import-ignore exceptions or implementation helpers that repopulate undeclared API-returned values, linkage validation must not accept `optional-state-drift` as implicitly covered by another metadata, docs, or acceptance-matrix concern; it must end as its own emitted record or an evidence-backed non-applicable state.

### REVIEW-COORD-007: Routed roles start only after coverage completion
- Rule: The routed review roles `review-architect`, `review-skeptic`, `review-advocate`, and `review-moderator` must not start until the deterministic coverage matrix is complete.
- Rule: Partial primary-pass findings or partially populated intermediate records must not be handed to routed roles before matrix completion.
- Rule: If the coverage matrix cannot be completed from current-run evidence, the prompt must hard-stop instead of starting routed roles on a partial audit.

## Change-set coverage and file handling

### REVIEW-FILE-001: Review the full change-set in scope
- Rule: Every changed file reported by the selected diff scope must be considered.
- Rule: Do not silently skip files.

### REVIEW-FILE-002: Classify changed files accurately
- Rule: Added, modified, deleted, staged, and untracked files must be counted and described accurately.
- Rule: Do not misclassify deleted files as modified files, or untracked files as tracked additions.

### REVIEW-FILE-003: Self-review recursion prevention is explicit
- Rule: If the active review prompt file itself is part of the reviewed change-set, skip only that specific file.
- Rule: The skip must be disclosed explicitly in the review output.

### REVIEW-FILE-003A: Local review scope should prefer the active local diff
- Rule: Local review should use the unstaged tracked diff as the primary review scope when it is non-empty.
- Rule: If the unstaged tracked diff is empty, local review should fall back to the staged tracked diff.
- Rule: If `git status --porcelain=v1` shows untracked files, inspect each reviewed untracked file directly from the workspace rather than treating untracked presence as a reason to skip review.
- Rule: If there are no tracked, staged, or untracked changes, local review must hard-stop instead of emitting an empty review body.

Local review scope decision table:

| Condition | Required action |
| --- | --- |
| Unstaged tracked diff is non-empty | Use the unstaged diff as the primary scope |
| Unstaged tracked diff is empty and staged tracked diff is non-empty | Fall back to the staged diff |
| Untracked files are present | Inspect each reviewed untracked file directly from the workspace |
| No tracked, staged, or untracked changes exist | Hard-stop rather than emitting a normal review |

### REVIEW-FILE-004: Committed review scope must prefer authoritative PR context
- Rule: When authoritative pull request metadata exists, committed review must use that pull request changed-file set and diff as the authoritative review scope and must not drift into unrelated branch-only commits.
- Rule: Deterministic pull request identifiers from user input or environment context are valid PR-scoped inputs. When an explicit PR number is available, the first choice is a direct shell-native HTTPS request for that same PR number to `https://api.github.com/repos/<owner>/<repo>/pulls/<number>/files`, using pagination when needed and without relying on the local `gh` binary. Otherwise use active or viewed PR context first, then any remaining allowed non-CLI GitHub-backed PR-files path.
- Rule: The preferred direct shell-native HTTPS request should use a JSON-returning request shape, for example a shell-native REST request that yields JSON directly rather than formatted web-response text. When the authoritative response is larger than the inline tool transport can carry comfortably, reduce it in-process to the fields needed for scope resolution or write a current-run transient JSON artifact from that already-authoritative response instead of trying to parse terminal wrapper text.
- Rule: PR summaries, issue-style or status metadata, browser links such as `Open on GitHub.com`, forbidden spill-file transports, and local cache or user-profile paths are never authoritative initial PR file scope. This includes tool-produced saved-output artifacts under paths such as `AppData`, `workspaceStorage`, `chat-session-resources`, `content.json`, or `content.txt` when they are being offered as the starting source of truth for PR file scope. Ignore them, continue with the next allowed GitHub-backed PR-files path, and never use `read_file` or shell commands against pre-existing or tool-spilled local artifacts to reconstruct authoritative PR scope.
- Rule: After authoritative PR scope has already been established from an allowed source, the current run may generate a transient local transport artifact from that already-authoritative dataset when needed for size or tool-shape reasons, as long as the workflow does not treat that artifact itself as a new authoritative source and the artifact is used only as a transport buffer for the current run.
- Rule: Tool-generated wrapper text such as "output too large" notices, saved-output banners, or other transport metadata is never part of the authoritative PR-files payload and must not be parsed as if it were the JSON response body.
- Rule: Do not use local `gh api` as an automatic fallback for PR file retrieval. Use `gh` only when the user explicitly asks to use `gh`. If the direct shell-native HTTPS request and the remaining allowed non-CLI GitHub-backed PR-files paths do not yield authoritative PR scope, fail closed for lack of authoritative PR scope. Fall back to `origin/main...HEAD` only when no authoritative pull request metadata exists or when the user explicitly requests a branch-wide committed review.
- Rule: If explicit user-supplied PR context and environment PR context conflict, committed review must fail closed unless the user explicitly says the supplied PR should override the active or viewed PR context. After the authoritative PR changed-file set is resolved, inspect committed content using repo-local evidence such as the committed diff, `git show`, and targeted file reads rather than repeated remote PR-content fetches.
- Rule: After authoritative PR scope is resolved, committed review must verify that every non-deleted scoped file needed for deterministic review coverage is inspectable from repo-local committed evidence before coverage-matrix build or standards loading continues.
- Rule: If authoritative PR scope includes a non-deleted changed file that is missing from the local committed checkout or otherwise not inspectable from repo-local committed evidence, fail closed with a file-availability error; do not silently skip that file and do not degrade the condition into a generic coverage-matrix-incomplete result.

Committed review scope decision table:

| Condition | Required action |
| --- | --- |
| Explicit PR number is supplied | Try the preferred direct shell-native HTTPS PR-files request for that PR number first |
| A GitHub-backed result is only summary metadata, a browser link, or a forbidden spill-file path such as a `workspaceStorage`/`chat-session-resources` saved artifact being offered as initial PR scope | Ignore it and continue to the next allowed GitHub-backed PR-files path |
| The direct shell-native HTTPS request and remaining non-CLI GitHub-backed PR-files paths are exhausted | Fail closed for lack of authoritative PR scope; do not auto-fallback to `gh` |
| No authoritative PR context exists, or the user explicitly requests branch-wide committed review | Fall back to `origin/main...HEAD` branch diff scope |
| Explicit user-supplied PR context conflicts with environment PR context and there is no explicit override | Fail closed |

### REVIEW-FILE-005: Vendored third-party files are non-actionable review scope
- Rule: Files under `vendor/**` are non-actionable for normal code review because contributors are not expected to hand-edit or directly remediate vendored third-party content in this workflow.
- Rule: Vendor files must still be identified when they appear in the selected diff scope, but they should be excluded from actionable findings unless a current workspace instruction explicitly says otherwise.
- Rule: Do not raise Issues that tell contributors to edit vendored files directly.
- Rule: When a correctness concern appears to originate from vendored content, review the first actionable non-vendored source that controls or introduces that vendored change instead, such as dependency/version updates, generation inputs, or service client wiring.
- Reviewer behavior: disclose the count of vendored files skipped as non-actionable scope rather than silently omitting them or enumerating each vendored path in the review body.
- Reviewer behavior: when the selected diff scope is entirely vendored files, say so explicitly in the review output so the reader understands the actionable review surface is limited.
- Reviewer behavior: when vendored files make up the majority of the selected diff scope, say so explicitly in the review output so sparse actionable findings are not ambiguous.

## File-type-specific review coverage

### REVIEW-SCOPE-001: Always review user-visible content quality
- Rule: For any changed user-visible text, review spelling, grammar, command accuracy, naming consistency, and professional but community-friendly tone.
- Rule: Do not treat visible text quality as out of scope just because the file is not code.

### REVIEW-SCOPE-002: Review command examples and snippets for plausibility
- Rule: When changed content includes commands, flags, paths, or usage examples, review them for internal consistency with the repository's current behavior and terminology.
- Rule: If full execution is not possible, assess the examples against workspace evidence and note any unverified assumptions.

### REVIEW-SCOPE-003: Installer and script changes must consider cross-platform drift
- Rule: When PowerShell, Bash, installer entrypoints, or shared installer manifests change, review for cross-platform behavior drift.
- Rule: If a user-visible behavior or message changes in one installer path, check whether the corresponding PowerShell and Bash paths remain aligned when the workspace guidance expects parity.
- Rule: Pay particular attention to bootstrap versus release-bundle messaging, shared manifest usage, and command-line help examples.

### REVIEW-SCOPE-004: Prompt, instruction, and skill changes must review determinism and alignment
- Rule: When `.github/prompts/**`, `.github/instructions/**`, `.github/skills/**`, or related customization files change, review for determinism, source precedence, and rule alignment.
- Rule: Check for duplicated normative rules when a shared contract exists, stale embedded policy that can drift, broken recursion-prevention logic, and unstable or contradictory output-shape requirements.
- Rule: Exact hard-stop text, verification markers, and other deliberately stable user-facing strings must be preserved unless there is an intentional reason to change them.

### REVIEW-SCOPE-004A: Reference docs under website/docs defer to the docs compliance contract
- Rule: When the review scope includes files under `website/docs/**/*.html.markdown`, load and apply `.github/instructions/docs-compliance-contract.instructions.md` and `.github/instructions/documentation-guidelines.instructions.md` for those files.
- Rule: For those files, the `DOCS-*` rules are the canonical documentation compliance rules.
- Rule: The generic code review contract continues to govern overall review flow, evidence handling, classification, and output shape.
- Rule: The docs-writer verification footer and docs-only prompt output contract do not apply to `/code-review-local-changes` or `/code-review-committed-changes`.
- Rule: Do not extend `DOCS-*` rules to non-reference docs such as `README.md`, `docs/*.md`, or other markdown files unless a future contract explicitly does so.
- Rule: For reference docs in committed or local review scope, `DOCS-DEPR-*` remains authoritative for next-major deprecations even when implementation evidence shows a legacy non-vNext field still exists on a transitional code path.
- Rule: Do not raise a docs-parity Issue solely because a legacy field is still accepted on a non-vNext path when the docs contract and docs guidance require that field to stay out of current reference docs and place migration guidance in an upgrade guide.
- Rule: Any docs Issue raised for files under `website/docs/**/*.html.markdown` must cite at least one exact supporting `DOCS-*` rule ID.
- Rule: If no exact `DOCS-*` rule supports a proposed docs claim, do not raise it as an Issue in generic review; demote it to an Observation or omit it.

### REVIEW-SCOPE-005: Go implementation and acceptance-test files defer to scoped guidance
- Rule: When the review scope includes `internal/**/*.go` or `internal/**/*_test.go`, load and apply the applicable file-scoped instructions and skills.
- Rule: For `internal/**/*.go` review scope, the minimum implementation guidance set is `.github/instructions/implementation-compliance-contract.instructions.md`, `.github/instructions/implementation-guide.instructions.md`, `.github/instructions/schema-patterns.instructions.md`, `.github/instructions/azure-patterns.instructions.md`, and `.github/instructions/code-clarity-enforcement.instructions.md`.
- Rule: For `internal/**/*_test.go` review scope, also load `.github/instructions/testing-compliance-contract.instructions.md` and `.github/instructions/testing-guidelines.instructions.md`.
- Rule: Use those sources as the primary checklist for provider implementation and acceptance-test concerns rather than relying on stale prompt summaries.

### REVIEW-SCOPE-005A: New resources must include required companion artifacts
- Rule: When the review scope adds a brand-new resource under `internal/**/*.go`, review whether the required companion artifacts are present or explicitly justified.
- Rule: For new resources, treat missing Resource Identity support, missing list resources, missing list-resource query tests, and missing list-resource docs as reviewable issues unless the change explicitly uses the maintainer-reviewed upstream exception path.
- Rule: For the documentation companion, expect the corresponding list-resource doc page under `website/docs/list-resources/` when the new resource requires a list resource.
- Rule: Do not treat upstream exception labels such as `allow-without-list` or `list-not-supported` as implicit; the review should only accept the omission when the exception is explicitly justified in the change context.

### REVIEW-SCOPE-005B: Ephemeral resources and provider-defined functions must include their companions
- Rule: When the review scope adds a new `*_ephemeral.go` implementation, review whether the required companion artifacts are present: service registration, docs under `website/docs/ephemeral-resources/`, and Terraform 1.10-gated tests under `*_ephemeral_test.go`.
- Rule: When the review scope adds a new provider-defined function under `internal/provider/function/`, review whether the required companion artifacts are present: docs under `website/docs/functions/` and Terraform 1.8-gated unit tests under `internal/provider/function/*_test.go`.
- Rule: Treat missing companion docs or tests for new ephemeral resources and provider-defined functions as reviewable issues.

### REVIEW-SCOPE-005C: Singleton or get-only resources need exception-aware list review
- Rule: When a brand-new resource appears to be singleton or backed only by a get/read API with no meaningful list API, do not raise a generic missing-list-resource Issue without considering the maintainer-reviewed exception path.
- Rule: Treat singleton-child implementation evidence as valid justification input even when the PR text is brief. Examples include a fixed child-resource name or path segment, a synthetic ID type representing a singleton child endpoint, CRUD methods that operate on a parent ID plus a fixed child path, or provider semantics that model only one instance per parent.
- Rule: The existence of a generated SDK list method alone is not sufficient evidence that a meaningful list resource is required when stronger implementation evidence shows the Terraform resource represents a singleton child configuration object.
- Rule: If the change context or implementation evidence shows that no meaningful list API exists, that the resource is singleton, or that the omission is using the maintainer-reviewed exception path, do not raise a normal missing-list-resource Issue; record the situation as an Observation or concise note instead.
- Rule: In that Observation or note, mention that the omission should be covered by the documented maintainer-reviewed exception path such as `allow-without-list` or `list-not-supported`.
- Rule: If the available implementation evidence suggests singleton or get-only behavior but the change context does not explicitly justify omitting the list resource, keep the finding as an Issue, but use exception-aware wording that tells the contributor to document the reason in the PR and use the maintainer-reviewed exception path instead of silently omitting the list resource.

### REVIEW-SCOPE-005D: Generic lifecycle/provider logging is reviewable when it adds no unique value
- Rule: When `internal/**/*.go` changes add generic resource lifecycle/provider logging such as `Import check`, `Creating`, `Reading`, `Updating`, or `Deleting`, treat those additions as reviewable issues when they only duplicate Terraform core or provider-native logging.
- Rule: Do not require removal of targeted not-found or removing-from-state diagnostics when they are part of established provider behavior and add distinct debugging value.
- Rule: If a contributor wants broad lifecycle logging consistency, treat SDK/framework-level implementation as the preferred direction instead of ad hoc per-resource logging.

### REVIEW-SCOPE-005E: New cross-resource ID fields must follow provider naming rules
- Rule: When `internal/**/*.go` changes add a brand-new public schema field that stores another Terraform-managed resource ID, review whether that field uses the full referenced resource name without the `azurerm_` prefix, followed by `_id`.
- Rule: For a brand-new public surface, treat shortened or ambiguous cross-resource ID field names as reviewable issues unless the change context includes a clear, evidence-backed naming exception.
- Rule: Do not accept a day-one naming exception for a new cross-resource ID field merely because a shorter name feels convenient.

### REVIEW-SCOPE-005F: Update paths must not silently skip concurrent field changes
- Rule: When `internal/**/*.go` update logic handles one changed field through an early-return branch or a mutually exclusive update path, review whether other updatable fields can change in the same plan and be silently skipped.
- Rule: Treat that as a reviewable issue when an update branch returns after handling one change while other changed fields remain unapplied, unless the branch is proven to perform a complete replacement that includes all dirty updatable fields.
- Rule: Do not assume that a special-case PUT or PATCH branch is safe merely because it solves one field-specific API behavior; review whether it still preserves the full set of concurrent user changes.

### REVIEW-SCOPE-005G: Create-time import guards and callback identity setup are reviewable
- Rule: When `internal/**/*.go` create logic probes for an existing resource and returns `tf.ImportAsExistsError(...)`, review whether that branch honors `SkipImportCheckOnCreateAndAllowOverwritingExistingResources`.
- Rule: When `internal/**/*.go` create logic uses callback-based `...CreateCallbackThenPoll(...)` flows for a resource that supports Resource Identity, review whether the callback sets both the Terraform ID and identity through `sdk.SetIDAndIdentityCallback(...)` or an equivalent callback.
- Rule: Treat an unconditional import-as-exists path or a callback-based create flow that omits ID-plus-identity setup as a reviewable issue because those patterns break configured overwrite behavior or leave Resource Identity unset during create.

### REVIEW-SCOPE-005H: Provider feature-flagged CRUD branch coverage is reviewable
- Rule: When `internal/**/*.go` changes modify behavior behind a provider-level `features` setting and that setting changes create, update, delete, import, overwrite, or destroy semantics, review whether targeted coverage exists for the changed non-default branch or whether there is a concrete reason that such coverage is not practical.
- Rule: Do not treat the code-side feature guard alone as sufficient when the changed branch is materially behavior-affecting and meaningfully testable with the existing harness.
- Rule: For pre-existing remote object scenarios, treat `CheckWithClientForResource`, `CheckWithClientWithoutResource`, and `CheckWithClient`, as appropriate, as valid acceptance setup mechanisms.

### REVIEW-SCOPE-006: Manifest and bundle changes must match shipped content expectations
- Rule: When file manifests, release-bundle lists, or installer packaging inputs change, review whether the changed entries remain consistent with the repository structure and the expected shipped assets.
- Rule: Treat missing or mismatched prompt, instruction, skill, or installer entries as reviewable issues when the manifest is intended to distribute them.

## Acceptance-test review guidance

### REVIEW-TEST-000: Code review is not a test-execution workflow
- Rule: Normal code review is audit-only and does not execute unit tests, acceptance tests, `go test`, `runTests`, `TF_ACC` runs, or other test commands unless the user explicitly asks for test execution as part of the review.
- Rule: Review may inspect changed test files, test structure, test naming, and embedded Terraform, but should not run tests merely to improve confidence, reduce residual risk language, or validate a suspected issue during ordinary review flow.
- Rule: If a reviewer believes running tests would help, that belongs in a follow-up suggestion or a separate user-approved validation step, not the default review procedure.

### REVIEW-TEST-001: ImportStep guidance is evidence-based, not absolute
- Rule: Treat ImportStep as strong evidence that configured state is validated, but not as a blanket prohibition on all additional checks.
- Rule: Additional explicit checks are acceptable when they verify behavior that ImportStep does not cover.

### REVIEW-TEST-002: RequiresImport patterns follow current contributor guidance
- Rule: Evaluate requires-import tests against the active contributor guidance and the resource's actual behavior.
- Rule: Do not report a requires-import pattern as wrong solely because it differs from an older prompt preference.

### REVIEW-TEST-002A: New managed resources should cover the upstream minimum resource test matrix
- Rule: When review scope adds a brand-new managed resource or materially new managed mode with acceptance coverage, inspect whether the suite includes the upstream minimum resource scenarios: `basic`, `requiresImport`, `complete`, and `update`.
- Rule: When the current-run evidence shows that one of those minimum scenarios is missing, treat that gap as a reviewable concern instead of silently skipping it.
- Rule: Absence of any upstream-minimum resource scenario should remain visible at least as an `OBSERVATION` for new managed resources unless current-run evidence shows that specific expectation does not apply or the scenario is genuinely impractical.
- Rule: Give extra weight to a missing `complete` scenario when the resource exposes optional, metadata-bearing, or category-dependent shape, because that broader supported surface is otherwise left under-proven even when narrower `basic`, `requiresImport`, or `update` slices exist.

### REVIEW-TEST-003: Embedded Terraform in acceptance tests must use repository-valid formatting
- Rule: When reviewing files under `internal/**/*_test.go`, inspect embedded Terraform configuration strings, including raw string literals used to define acceptance-test configuration.
- Rule: For `*_test.go` files containing embedded Terraform configuration, flag Terraform configuration lines whose indentation is not two spaces, including tab-indented lines and mixed tab-and-space indentation.
- Rule: In acceptance-test Terraform blocks, expect two-space indentation for configuration lines and do not accept tabs anywhere in Terraform configuration indentation.
- Rule: Scope this rule only to embedded Terraform blocks inside Go acceptance-test strings; do not treat tabs in normal Go source as a formatting issue.
- Rule: Do not assume `azurerm-linter` will catch formatting problems inside embedded Terraform strings.

## Observation-only design guidance

### REVIEW-OBS-001: Boolean toggle schema preference is observation-only by default
- Rule: If a string enum behaves like a boolean toggle, prefer a boolean *_enabled shape for new schema design.
- Rule: This is an Observation unless current workspace guidance makes it a mandatory rule for the reviewed change.

### REVIEW-OBS-002: StringIsNotEmpty alone is not automatically an Issue
- Rule: A TypeString field using only validation.StringIsNotEmpty is not, by itself, sufficient evidence for an Issue.
- Rule: Escalate only when current guidance or clear implementation context shows stronger validation is both feasible and required.

## Output semantics

### REVIEW-OUT-001: Reviews must be evidence-forward
- Rule: Findings should cite the affected file(s), behavior, and why the concern matters.
- Rule: Do not rely on generic labels without explanation.

### REVIEW-OUT-002: Hard-stop messages are prompt-owned
- Rule: No-changes messages and other humorous hard-stop text belong to the prompt, not the contract.
- Rule: The prompts may keep their pirate-style hard-stop messages without changing this contract.

### REVIEW-OUT-003: Missing evidence must be disclosed plainly
- Rule: When a conclusion cannot be proven, say so directly in the review rather than compensating with invented certainty.

### REVIEW-OUT-005: Successful fresh runs must emit the full current template
- Rule: If the mandatory procedure succeeds for the selected review type, emit the full current routed review template.
- Rule: When the selected review type routes `review-presentation`, the final successful review body must follow `.github/instructions/review-presentation-compliance-contract.instructions.md`.
- Rule: When the selected review type does not route `review-presentation`, the final successful review body must follow the prompt-defined template for that workflow.
- Rule: For routed committed and local review, a normal successful review body is valid only when both conditions hold: the evidence and findings were gathered in a fresh run under the current contracts, and the final rendered body exactly matches the current `review-presentation` contract.
- Rule: If either condition fails, the workflow must fail closed and must not emit a normal review body.
- Rule: Do not short-circuit to a previous review, a delta-only summary, or wording such as `same findings as before` or `no change from the last review`.
- Rule: This applies even when the reviewed code, linter findings, or conclusions are unchanged from an earlier invocation.
- Rule: Current routed template/layout requirements are part of the output contract and must be honored on every successful fresh run.

### REVIEW-OUT-006: Freeze the review before emitting final output
- Rule: Complete evidence gathering, silent verification, file coverage checks, linter classification, and finding classification before emitting the first character of the normal review output.
- Rule: Treat the findings set as frozen before writing the review body. Do not continue investigating, reopen scope, or append newly discovered findings after the normal review output has started.
- Rule: If additional verification or one more read becomes necessary while drafting, stop drafting silently, finish that verification, refreeze the findings set, and then emit one complete review body.
- Rule: Do not use user-visible self-correction or second-pass wording inside the normal review output, such as `one more thing`, `actually`, `updating this review`, `adding another issue`, or similar mid-review amendments.

### REVIEW-OUT-007: Skill verification footer is allowed when skills were actually used
- Rule: For normal successful routed committed and local review, the final review output must append a verification footer after the prompt's last review section.
- Rule: That verification footer is part of the normal successful output contract, not extra narration.
- Rule: For routed committed and local review, the verification footer must contain `Preflight complete: yes` followed by one `Skill used: <name>` line for each actually used skill.
- Rule: A render-only presentation skill may own footer rendering without adding its own `Skill used:` line, as long as it preserves the actual routed review-skill set supplied by the prompt.
- Rule: Do not infer skill use from file type alone or from loading contracts or instruction files; emit `Skill used:` lines only for skills that were actually loaded and used.
- Rule: If the review body states that a skill was loaded or used, the verification footer should include the matching `Skill used:` line.

### REVIEW-OUT-007A: Normal successful routed reviews use one canonical stage sequence
- Rule: For routed committed and local review, the normal successful stage sequence is `review-coordinator`, `review-reviewer`, `review-architect`, `review-skeptic`, `review-advocate`, `review-moderator`, then `review-presentation`, in that exact order.
- Rule: After preflight succeeds, the prompt must invoke those stages in that exact order and must not skip a later stage merely because an earlier stage appears to have no findings or no visible delta.
- Rule: When a routed stage has no findings or no additional work, the prompt must still invoke it with the appropriate explicit empty or no-op payload for that stage rather than skipping the stage.
- Rule: Preflight hard-stops remain allowed before the routed stage sequence begins; once the normal successful routed path starts, missing stages are invalid.

### REVIEW-OUT-007B: Verification footer must be backed by an execution ledger
- Rule: When a routed review emits a verification footer, the workflow must maintain a current-run execution ledger containing `requiredStages` and `executedStages`.
- Rule: For the normal successful routed path, `requiredStages` and `executedStages` must match exactly in content and order before the final review body may be emitted.
- Rule: `verificationFooter.skillsUsed` must be derived mechanically from `executedStages`, preserving order and excluding only the render-only `review-presentation` stage.
- Rule: If `requiredStages` and `executedStages` do not match exactly, the workflow must hard-stop instead of emitting a normal review body.

### REVIEW-OUT-008: Overall assessment must align with the final issues state
- Rule: The `OVERALL ASSESSMENT` section must be derived from the final frozen `ISSUES` section and must not carry forward stale defects that were cleared before the review body was emitted.
- Rule: If the final `ISSUES` section contains exactly `- None`, the `OVERALL ASSESSMENT` section must not say `Not ready to merge`, must not describe unresolved defects, and must recommend merge-readiness consistent with the issue-free state.
- Rule: If the final `ISSUES` section contains one or more issues, the `OVERALL ASSESSMENT` section must not say the change is ready to merge and must summarize only the unresolved issues that still appear in the final `ISSUES` section.
- Rule: Do not mix a clean final issue state with contradictory verdict text such as `Not ready to merge` followed by prose that says local validation is clean and only rerun is needed.

<!-- REVIEW-CONTRACT-EOF -->
