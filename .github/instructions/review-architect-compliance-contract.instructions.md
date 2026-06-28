---
description: "Architect direction pass compliance contract (single source of truth) used by the review-architect skill as a workflow-governed intermediate pass to evaluate design fit and structural direction before review output is frozen."
---

# Review Architect Compliance Contract

This file is the single source of truth for the architect direction review technique in this repository.

## Consumers

One workflow MUST follow this contract:

- Consumer: `.github/skills/review-architect/SKILL.md`
  - Role: Architect
  - Command: `review-architect` skill, invocable as a governed workflow pass during `/code-review-local-changes` and `/code-review-committed-changes`, not as an independent final-output review stage
  - Requires EOF Load: yes
  - Goal: evaluate the change-set for design fit, schema and naming direction, and long-term maintainability, raising mandatory-source-backed Issues and otherwise recording direction as Observations before output is frozen.

The review prompts orchestrate when the architect pass runs.
The architect skill encapsulates the reusable direction method.
This contract defines the architect-specific deterministic rules.
Direct invocation does not grant the architect pass authority to freeze review output or emit a standalone final review section.
The shared workflow handoff schema lives at `.github/instructions/review-workflow-handoff.schema.json`.

## Canonical sources of truth (precedence)

Use these sources with the following roles:

- The shared code review contract: `.github/instructions/code-review-compliance-contract.instructions.md`
  - Authoritative for overall review flow, evidence handling, finding classification, and output shape.
  - This architect contract refines how design-direction findings are proposed before output is frozen; it must not weaken or override the `REVIEW-CLASS-*`, `REVIEW-EVID-*`, `REVIEW-OBS-*`, or `REVIEW-HANDOFF-*` semantics.
- The advocate contract: `.github/instructions/review-advocate-compliance-contract.instructions.md`
  - Authoritative for how candidate Issues, including architect-proposed candidates, are confirmed, downgraded, or dismissed before output is frozen.
- The skeptic contract: `.github/instructions/review-skeptic-compliance-contract.instructions.md`
  - The sibling adversarial panel pass; both the skeptic and architect passes feed their candidates to the advocate before output is frozen, and neither overrides the other.
- This contract: `.github/instructions/review-architect-compliance-contract.instructions.md`
  - Authoritative for the architect direction-pass deterministic rules in this repository.
- The architect skill: `.github/skills/review-architect/SKILL.md`
  - Reusable direction method: how to assess structural fit and design alignment with evidence.

Conflict resolution:

- This contract is authoritative for architect-pass activation, direction-coverage scope, and the bar a design concern must clear before it is raised as an Issue rather than an Observation.
- The shared code review contract remains authoritative for overall review flow, evidence handling, classification semantics, and output shape.
- The shared code review contract remains authoritative for the intermediate handoff shape used to carry architect output to later passes.
- `.github/instructions/review-workflow-handoff.schema.json` is the concrete runtime schema artifact for that handoff shape.
- The advocate contract remains authoritative for resolving every candidate Issue, including architect-proposed candidates, to exactly one outcome.
- If this contract would contradict `REVIEW-OBS-001` (design preference is observation-only by default) or `REVIEW-CLASS-004` (one finding, one classification), those shared rules win and each architect concern must still resolve to exactly one classification.

## Rule IDs

Rules are identified by stable IDs so the architect skill and the review prompts reference the same requirement set without drifting.

ID format:
- REVIEW-ARCH-<NNN>

Area:
- ARCH = architect direction-pass evaluation

## Evidence hierarchy

When the architect proposes a finding, weigh evidence in this order:

1. The changed files and the actual diff under review
2. Current workspace contributor guidance and file-scoped instructions
3. Current workspace implementation details, tests, and surrounding code
4. PR/commit description and code comments that state design intent
5. External references for semantics only, when workspace evidence is insufficient

If a design concern cannot be tied to this evidence, it stays an Observation rather than an Issue.

# Contract Rules

## Architect direction-pass evaluation

### REVIEW-ARCH-001: Architect evaluates direction, not line-level defects
- Rule: The architect pass evaluates structural fit, design direction, and maintainability across the change-set, not line-level correctness defects already owned by the primary audit and the skeptic pass.
- Rule: The architect pass is governed workflow machinery, not an independent review stage with its own frozen output behavior.
- Rule: The architect pass runs before the advocate pass and before the review output is frozen, never after.
- Rule: If the change-set is empty or out of scope under the shared contract, the architect pass does not run and changes nothing.

### REVIEW-ARCH-002: Observation is the default classification
- Rule: An architect-proposed design concern defaults to an Observation under `REVIEW-CLASS-002` and `REVIEW-OBS-001`.
- Rule: Every architect finding that stays in workflow scope must use the shared `REVIEW-HANDOFF-*` field shape with `status` set to `observation` or `candidate` as appropriate.
- Rule: The architect escalates a concern to an Issue only when a current workspace contributor document, instruction file, skill, or contract makes that design rule mandatory for the reviewed change.
- Rule: When escalating to an Issue, the architect must cite the exact governing rule or guidance source.

### REVIEW-ARCH-003: Direction coverage is explicit
- Rule: The architect must consider, where in scope, these direction areas: schema shape and field naming, argument grouping and singular-versus-plural naming, resource decomposition and singleton modeling, typed-versus-untyped implementation approach, cross-resource and cross-platform consistency, required companion artifacts such as Resource Identity, list resources, and ephemeral resources, and overall maintainability and diff readability.
- Rule: For provider Go changes under `internal/**`, apply the workspace-scoped guidance loaded per `REVIEW-SCOPE-005` rather than restating provider design rules from memory.
- Rule: The architect must not invent design policy that no contributor document, instruction file, skill, or contract supports, per `REVIEW-EVID-003`.

### REVIEW-ARCH-004: Mandatory-source requirement for architectural Issues
- Rule: An architectural Issue is valid only when it cites a mandatory source that the reviewed change violates.
- Rule: A design preference, stylistic improvement, or "a different shape might be better" concern without a mandatory source stays an Observation, per `REVIEW-OBS-001` and `REVIEW-OBS-002`.
- Rule: Do not use invented policy language such as "must" or "required" when the source only supports a preference.

### REVIEW-ARCH-005: Respect change-set scope boundaries
- Rule: The architect must not demand broad refactors that extend beyond the reviewed change-set.
- Rule: Larger structural direction that is out of scope for the current change is recorded as a follow-up Observation, not an Issue.
- Rule: The architect does not block a self-consistent, evidence-acceptable change merely because another architecture might be preferable, per `REVIEW-CLASS-002`.

### REVIEW-ARCH-006: Architect does not finalize outcomes
- Rule: The architect does not freeze severity or final classification; every architect-proposed candidate Issue is subject to the advocate pass under `REVIEW-ADV-*` before output is frozen.
- Rule: A concern that is uncertain in severity follows `REVIEW-CLASS-004` and resolves to exactly one classification.

## Output integration

### REVIEW-ARCH-007: The architect pass produces no separate output section
- Rule: The architect pass is invisible machinery; it must not emit its own heading or section in the review body.
- Rule: Architect-proposed findings appear in `### 🔴 **ISSUES**` or `### 🟡 **OBSERVATIONS**` like any other finding, with no architect-specific labeling.
- Rule: The architect pass must not narrate its evaluation process in the review output.

<!-- REVIEW-ARCH-CONTRACT-EOF -->
