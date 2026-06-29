---
description: "Skeptic adversarial pass compliance contract (single source of truth) used by the review-skeptic skill as a workflow-governed intermediate pass to surface additional evidence-backed candidate Issues before review output is frozen."
---

# Review Skeptic Compliance Contract

This file is the single source of truth for the skeptic adversarial review technique in this repository.

## Consumers

One workflow MUST follow this contract:

- Consumer: `.github/skills/review-skeptic/SKILL.md`
  - Role: Skeptic
  - Command: `review-skeptic` skill, invocable as a governed workflow pass during `/code-review-local-changes` and `/code-review-committed-changes`, not as an independent final-output review stage
  - Requires EOF Load: yes
  - Goal: surface additional evidence-backed candidate Issues the primary audit may have missed, then pass them into the workflow's adjudication step before output is frozen.

The review prompts orchestrate when the skeptic pass runs.
The skeptic skill encapsulates the reusable adversarial method.
This contract defines the skeptic-specific deterministic rules.
Direct invocation does not grant the skeptic pass authority to freeze review output or emit a standalone final review section.
The shared workflow handoff schema lives at `.github/instructions/review-workflow-handoff.schema.json`.

## Canonical sources of truth (precedence)

Use these sources with the following roles:

- The shared code review contract: `.github/instructions/code-review-compliance-contract.instructions.md`
  - Authoritative for overall review flow, evidence handling, finding classification, and output shape.
  - This skeptic contract refines how additional candidate Issues are proposed before output is frozen; it must not weaken or override the `REVIEW-CLASS-*`, `REVIEW-EVID-*`, or `REVIEW-HANDOFF-*` semantics.
- The workflow handoff schema: `.github/instructions/review-workflow-handoff.schema.json`
  - Authoritative for the concrete runtime JSON shape the skeptic consumes and emits in workflow scope.
- This contract: `.github/instructions/review-skeptic-compliance-contract.instructions.md`
  - Authoritative for the skeptic adversarial-pass deterministic rules in this repository.
- The skeptic skill: `.github/skills/review-skeptic/SKILL.md`
  - Reusable adversarial method: how to attack the change-set for missed defects with evidence.

Conflict resolution:

- This contract is authoritative for skeptic-pass activation, attack-surface coverage, and the evidence bar a skeptic-proposed candidate must clear before it joins the candidate Issue set.
- The shared code review contract remains authoritative for overall review flow, evidence handling, classification semantics, and output shape.
- The shared code review contract remains authoritative for the intermediate handoff shape used to carry skeptic output to later passes.
- `.github/instructions/review-workflow-handoff.schema.json` is the concrete runtime schema artifact for that handoff shape.
- If this contract would contradict `REVIEW-CLASS-004` (one finding, one classification), `REVIEW-CLASS-004` wins and each skeptic-proposed concern must still resolve to exactly one classification.

## Rule IDs

Rules are identified by stable IDs so the skeptic skill and the review prompts reference the same requirement set without drifting.

ID format:
- REVIEW-SKEP-<NNN>

Area:
- SKEP = skeptic adversarial-pass evaluation

## Evidence hierarchy

When the skeptic proposes a candidate Issue, weigh evidence in this order:

1. The changed files and the actual diff under review
2. Current workspace contributor guidance and file-scoped instructions
3. Current workspace implementation details, tests, and surrounding code
4. Tool output, including azurerm-linter
5. External references for semantics only, when workspace evidence is insufficient

If a proposed candidate cannot be backed by this evidence, it is not a valid candidate Issue.

# Contract Rules

## Skeptic adversarial-pass evaluation

### REVIEW-SKEP-001: Skeptic pass augments, never replaces, the primary audit
- Rule: The skeptic pass adds candidate Issues to the primary review pass; it does not restate, replace, or re-run the primary audit.
- Rule: The skeptic pass is governed workflow machinery, not an independent review stage with its own frozen output behavior.
- Rule: The skeptic pass runs before the review output is frozen, never after.
- Rule: If the change-set is empty or out of scope under the shared contract, the skeptic pass does not run and changes nothing.

### REVIEW-SKEP-002: Skeptic proposes candidate Issues only from evidence
- Rule: Every skeptic-proposed candidate Issue must cite concrete evidence such as a `file:line` reference, a quoted line of code, tool output, or a cross-referenced pattern elsewhere in the codebase.
- Rule: Every skeptic finding that stays in workflow scope must use the shared `REVIEW-HANDOFF-*` field shape with `status` set to `candidate` or `observation` as appropriate.
- Rule: A concern that cannot meet the evidence hierarchy is demoted to an Observation or dropped per `REVIEW-EVID-001`; it must not be asserted as an Issue.
- Rule: Mark derived assumptions explicitly rather than stating inference as fact.

### REVIEW-SKEP-003: Adversarial attack surface is explicit
- Rule: The skeptic must consider, at minimum, these attack classes against the change-set: correctness and logic errors, error handling and nil or zero-value handling, concurrency and ordering, input validation and trust boundaries, resource lifecycle and residual state, security exposure, and test-coverage gaps for behavior-changing branches.
- Rule: For provider Go changes under `internal/**`, apply the workspace-scoped guidance loaded per `REVIEW-SCOPE-005` rather than restating Azure semantics; treat PATCH residual state, "None"-style default handling, `CustomizeDiff` placement, and cross-implementation consistency as known attack vectors.
- Rule: The skeptic must not invent policy that no contributor document, instruction file, skill, or contract supports, per `REVIEW-EVID-003`.

### REVIEW-SKEP-004: Candidate Issues must name a concrete failure scenario
- Rule: Each skeptic-proposed candidate Issue must describe the specific way the change breaks, not a vague worry.
- Rule: A candidate Issue must connect its evidence to an observable failure, regression, policy violation, or missing requirement.
- Rule: If the skeptic cannot articulate a concrete failure path from the evidence, the concern is an Observation, not an Issue.

### REVIEW-SKEP-005: Skeptic does not finalize outcomes
- Rule: The skeptic does not freeze severity or final classification; every skeptic-proposed candidate Issue is subject to workflow adjudication before output is frozen.
- Rule: The skeptic must not mark its own candidates as immune from adjudication.
- Rule: A skeptic-proposed candidate that is dismissed during workflow adjudication follows the shared workflow outcome mapping, the same as any other candidate Issue.

### REVIEW-SKEP-006: No duplicate or redundant candidates
- Rule: The skeptic must not restate a candidate Issue already raised by the primary audit; it may strengthen an existing candidate with additional evidence instead.
- Rule: The skeptic adds only net-new candidate Issues or net-new evidence, never duplicates that inflate the finding count.

### REVIEW-SKEP-007: One concern, one classification
- Rule: A skeptic-proposed concern must not appear in both Observations and Issues, per `REVIEW-CLASS-004`.
- Rule: If severity is uncertain, the skeptic chooses the lower justified classification and lets workflow adjudication resolve it.

## Output integration

### REVIEW-SKEP-008: The skeptic pass produces no separate output section
- Rule: The skeptic pass is invisible machinery; it must not emit its own heading or section in the review body.
- Rule: Skeptic-proposed candidates that survive adjudication appear in `### 🔴 **ISSUES**` or `### 🟡 **OBSERVATIONS**` like any other finding, with no skeptic-specific labeling.
- Rule: The skeptic pass must not narrate its attack process in the review output.

<!-- REVIEW-SKEP-CONTRACT-EOF -->
