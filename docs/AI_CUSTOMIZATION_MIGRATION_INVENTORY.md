# AI Customization Migration Inventory

This document is the actionable follow-up to `docs/AI_CUSTOMIZATION_ARCHITECTURE_STANDARD.md`.

**Purpose:**

- classify the current runtime prompts and companion guides file by file
- identify what should stay where it is versus what should move to skills, contracts, or other layers
- define migration candidates without changing runtime behavior yet
- preserve current functionality and determinism by making regression constraints explicit

This is a repo-only maintainer document. It is not runtime payload and must not be added to `installer/file-manifest.config`.

## Working Rules

- Keep current runtime entrypoints stable until parity is validated.
- Do not remove or repurpose user-facing prompts early.
- Move reusable multi-step workflow logic to skills, not to hidden prompt orchestration.
- Keep normative rules in contract files.
- Treat companion guides as pattern guides, not as workflow engines.

## Runtime Prompt Inventory

| File | Current role | Keep as prompt? | Workflow logic that can move behind it | Regression constraint | Recommended next action |
| --- | --- | --- | --- | --- | --- |
| `.github/prompts/code-review-local-changes.prompt.md` | Explicit user-facing entrypoint for local diff review with deterministic output, hard stops, and linter execution policy | Yes | Shared review execution logic that is not local-scope-specific can gradually move into review skills or shared contract-backed helpers; keep local-scope selection logic at the entrypoint until parity is proven | High risk: prompt owns deterministic output shape and exact hard-stop behavior | Keep prompt stable; identify shared review logic for extraction without changing current output |
| `.github/prompts/code-review-committed-changes.prompt.md` | Explicit user-facing entrypoint for committed or PR-scoped review with deterministic output and authoritative-scope handling | Yes | Shared review logic and common report-generation behavior can gradually move behind the prompt; PR-scope resolution and linter behavior are now increasingly contract-backed even though prompt-owned hard-stop and output text still remain compatibility-sensitive | High risk: prompt still owns exact failure text and output shape | Keep prompt stable; continue shrinking repeated execution prose while leaving prompt-owned hard-stop and output contracts intact |
| `.github/prompts/code-review-docs.prompt.md` | Explicit user-facing entrypoint for docs review and schema-parity audit of the active docs page | Yes | Reusable docs-audit procedures can move behind the prompt into docs-focused skills or shared guidance, but prompt-level entry semantics should remain stable | High risk: prompt owns active-file checks, exact hard-stop text, and fixed output template | Keep prompt stable; move only reusable audit internals, not the prompt contract |

Prompt conclusions:

- The three current review prompts should remain as compatibility entrypoints in the near term.
- Prompt count should not increase.
- If review UX is simplified later, it should happen by adding a simpler front door while keeping these prompts as compatibility aliases until parity is proven.

## Runtime Companion Guide Inventory

| File | Current role | Target disposition | What should stay | What should move or shrink | Regression risk | Recommended next action |
| --- | --- | --- | --- | --- | --- | --- |
| `.github/instructions/implementation-guide.instructions.md` | Broad implementation companion guide with templates, heuristics, and workflow content | Keep, but split conceptually into core patterns versus workflow playbooks | Core typed/untyped/framework pattern guidance, implementation model identification, worked examples that directly support code generation | Large workflow checklists, AI-coaching sections, and procedural playbooks that belong in `resource-implementation` | High: heavily referenced and central to current behavior | Preserve core patterns; plan extraction of workflow-heavy sections into `resource-implementation` over time |
| `.github/instructions/azure-patterns.instructions.md` | Azure-specific implementation patterns and heuristics | Keep as companion guide | PATCH behavior, `GetRawConfig()` guidance, Azure-specific schema and residual-state patterns | Decorative framing and any checklist-like procedures that are better expressed in skills or slimmer companion text | Medium | Keep as a specialized pattern guide; trim only after mapping duplicate workflow logic |
| `.github/instructions/code-clarity-enforcement.instructions.md` | Comment discipline, decision heuristics, and implementation-quality guidance | Keep as companion guide, but slim | Comment policy, code-clarity heuristics, focused decision trees | Performance/session metrics and AI-optimization coaching sections that are not core code-clarity rules | Medium | Keep the decision logic; plan removal or relocation of low-signal AI-coaching sections |
| `.github/instructions/error-patterns.instructions.md` | Provider-standard error wording and debugging heuristics | Keep as companion guide, but narrow scope | Error wording patterns for typed and untyped implementations | Review-specific console-wrapping material and any content that belongs in review guidance rather than implementation guidance | Medium | Keep error semantics; evaluate moving review-artifact guidance out of this file |
| `.github/instructions/schema-patterns.instructions.md` | Schema design and validation patterns | Keep as companion guide | Schema-shape guidance, validation heuristics, AzureRM schema examples | Decorative or repetitive framing if present; procedural checklists that belong in skills | Low to medium | Keep mostly intact; trim duplication only after a duplication audit |
| `.github/instructions/testing-guidelines.instructions.md` | Testing patterns plus execution and environment guidance | Keep, but strongly slim toward pattern guidance | Evidence-backed testing heuristics and AzureRM-specific test patterns | Step-by-step test workflow and operational procedure content that belongs in `acceptance-testing` | High: overlaps with acceptance-testing workflow | Preserve rules and patterns; move multi-step test procedure content into `acceptance-testing` |
| `.github/instructions/documentation-guidelines.instructions.md` | Docs companion guide with heuristics, templates, and audit reminders | Keep, but strongly slim toward companion heuristics | AzureRM-specific docs heuristics, templates, and companion notes that help `docs-writer` | Procedural audit flow and repeated checklist material that belongs in `docs-writer` or the docs prompt | High: overlaps with docs-writer workflow | Preserve heuristics/templates; move task workflow and repeated audit steps out over time |
| `.github/instructions/provider-guidelines.instructions.md` | Broad provider-wide AzureRM implementation heuristics | Re-evaluate as a standalone guide | Any unique provider-wide heuristics that are not already captured elsewhere | Overlapping implementation guidance that duplicates `implementation-guide` and `azure-patterns` | Medium | Audit uniqueness; likely merge or reduce if it does not carry unique high-signal guidance |
| `.github/instructions/security-compliance.instructions.md` | Security and compliance patterns for provider work | Keep as companion guide, but narrow | Provider-relevant input validation, credential handling, and security-sensitive implementation reminders | Generic secure-coding material that is not specific to this provider workflow | Medium | Keep only provider-relevant security guidance; trim generic content later |
| `.github/instructions/api-evolution-patterns.instructions.md` | API versioning, compatibility, and migration patterns | Keep as companion guide | Stable-versus-preview API rules, compatibility heuristics, evolution patterns | Large migration playbooks that overlap `migration-guide` or skills | Low to medium | Keep as a domain guide; deduplicate only where overlap with `migration-guide` is proven |
| `.github/instructions/migration-guide.instructions.md` | Implementation transition and upgrade guidance | Keep as companion guide, but narrow | Migration decision support for typed versus untyped and breaking-change-sensitive work | Step-by-step migration workflows that are better expressed in skills | Medium | Keep the decision matrix; move long migration procedures to skills when added |
| `.github/instructions/performance-optimization.instructions.md` | Performance and scalability guidance | Keep as companion guide | Provider-relevant API efficiency and resource management patterns | Broad observability or operational advice that is not directly tied to code-generation decisions | Low to medium | Keep as a narrow pattern guide; trim generic material later |
| `.github/instructions/troubleshooting-decision-trees.instructions.md` | Troubleshooting workflows and debugging procedures | Keep for now, but strong candidate for future skill support | Concise troubleshooting reference patterns and upstream debug references | Step-by-step debugging workflows that are fundamentally procedural and skill-like | Medium to high | Keep as a reference for now; plan a future troubleshooting skill before shrinking aggressively |

Companion-guide conclusions:

- `implementation-guide`, `testing-guidelines`, and `documentation-guidelines` are the highest-value candidates for workflow extraction into skills while preserving current runtime behavior.
- `provider-guidelines` is the strongest merge-or-reduce candidate because its header suggests broad overlap with other implementation companions.
- `troubleshooting-decision-trees` is the strongest candidate for a future dedicated workflow skill, but not before such a skill exists.

## Existing Skill Fit

Current runtime skills already map well to the desired architecture:

| Skill | Current fit | Likely future load |
| --- | --- | --- |
| `.github/skills/resource-implementation/SKILL.md` | Strong fit for multi-step implementation workflow | Absorb more procedural implementation workflow currently embedded in companion guides |
| `.github/skills/custom-poller-migration/SKILL.md` | Strong fit for a narrow specialized migration workflow | Keep as a focused specialist skill |
| `.github/skills/acceptance-testing/SKILL.md` | Strong fit for test workflow behavior | Absorb more execution procedure content from `testing-guidelines` |
| `.github/skills/docs-writer/SKILL.md` | Strong fit for docs authoring and review workflow | Absorb more procedural content from `documentation-guidelines` and docs review supporting text |

Skill conclusion:

- The repository already has the right primitive for reusable workflow logic.
- Near-term migration should favor enriching or better routing these skills rather than creating more prompts.

## No-Regression Migration Sequence

### Step 1: Preserve entrypoints

- Keep all three review prompts as current user-facing entrypoints.
- Do not remove any prompt during the first migration pass.

### Step 2: Preserve contracts

- Leave normative rules in contract files.
- Do not move compliance-critical text into skills unless the contract still remains authoritative.

### Step 3: Extract workflow logic only where a receiving skill already exists

- `implementation-guide` -> `resource-implementation`
- `testing-guidelines` -> `acceptance-testing`
- `documentation-guidelines` -> `docs-writer`

### Step 4: Delay prompt simplification until parity evidence exists

- Do not collapse review prompts into a single entrypoint until regression coverage proves equivalence.
- If a simpler front door is added later, keep the current prompts as compatibility aliases until maintainers intentionally retire them.

## Suggested First Runtime Migration Candidates

These are the lowest-risk runtime modernization targets after the current architecture and inventory docs:

- `testing-guidelines.instructions.md`
	- clear overlap with an existing workflow skill
	- lower user-facing risk than touching review prompts

- `documentation-guidelines.instructions.md`
	- clear overlap with an existing workflow skill
	- docs workflow already has a dedicated skill and prompt surface

- `implementation-guide.instructions.md`
	- highest value, but also highest runtime sensitivity
	- should be done only after the repository is comfortable with the extraction pattern from testing/docs

## Deferred Items

- Review prompt consolidation
- New review agent or single review front door
- Standalone troubleshooting skill
- Provider-guidelines merge or retirement
- Broad style-only cleanup across all companion guides

These should wait until at least one runtime extraction has been completed without regressions.
