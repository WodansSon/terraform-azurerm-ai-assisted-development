---
name: review-architect
description: Design-direction workflow-governed review pass for code reviews — assess structural fit, schema and naming direction, and long-term maintainability, raising mandatory-source-backed Issues and otherwise recording direction as Observations before review output is frozen. Use when a code-review workflow should be checked for design fit.
---

# Review Architect (design-direction pass)

## Canonical sources of truth (contract-driven)

When running the architect pass, use `.github/instructions/review-architect-compliance-contract.instructions.md` as the single source of truth for:

- when the architect pass is allowed to run
- the direction areas it must consider
- when a design concern is an Issue versus an Observation
- the `REVIEW-ARCH-*` rule families

Do not treat this skill as a second independent rule source. The skill describes the method; the contract owns the deterministic rules.
Do not treat this skill as an independent final review stage. It is governed invisible workflow machinery that can add architect findings to an in-flight review, but it cannot freeze or publish final review output on its own.

The architect proposes findings only. It never finalizes outcomes: every architect-proposed candidate Issue is adjudicated by the advocate pass under `.github/instructions/review-advocate-compliance-contract.instructions.md` before output is frozen.

## Mandatory: read the entire skill

Before applying this skill, read this file to EOF.

## Preflight checklist

Before running an architect pass, complete this checklist:

- [ ] I have read this skill to EOF.
- [ ] I have loaded `.github/instructions/review-architect-compliance-contract.instructions.md` to EOF and applied the relevant `REVIEW-ARCH-*` rules.
- [ ] The primary review pass has gathered the change-set and its evidence, and the review workflow has routed this governed architect pass (otherwise this skill does not run).
- [ ] I am evaluating design direction and structural fit, not line-level correctness defects.

If preflight is incomplete, do not run the architect pass.

## Verification (assistant response only)

When (and only when) this skill is invoked, the assistant MUST append the following line to the end of the assistant's final response:

Skill used: review-architect

Rules:
- Do NOT write this marker into any repository file (docs, code, generated files).
- If multiple skills are invoked, each skill should append its own `Skill used: ...` line.
- Do NOT emit the marker in intermediate/progress updates; only in the final response.

## Scope

This skill is the reusable design-direction technique orchestrated inside the code-review prompts:

- `.github/prompts/code-review-local-changes.prompt.md`
- `.github/prompts/code-review-committed-changes.prompt.md`

It runs as invisible machinery between the primary review pass and the advocate pass. It does not produce its own output section; it only adds findings that, after advocate adjudication, land in `### 🔴 **ISSUES**` and `### 🟡 **OBSERVATIONS**` per the shared and advocate contracts.
When the architect adds a finding, it should do so through the shared intermediate finding shape rather than a one-off prose note.

## Role

You are the **architect** for the change-set. Your job is to:

- evaluate whether the change fits the provider's established design direction
- assess schema shape, field naming, and resource modeling against workspace guidance
- weigh long-term maintainability and diff readability
- separate mandatory design rules from preferences

Be principled, but restrained. Most design feedback is an Observation; an Issue requires a mandatory source the change violates.

## The architect method

1. **Work at altitude** — evaluate direction and structural fit across the change-set, not line-level defects already owned by the primary audit and the skeptic pass.
2. **Walk the direction areas** — per `REVIEW-ARCH-003`: schema shape and field naming, argument grouping and singular-versus-plural naming, resource decomposition and singleton modeling, typed-versus-untyped approach, cross-resource and cross-platform consistency, required companion artifacts such as Resource Identity, list resources, and ephemeral resources, and overall maintainability.
3. **Apply scoped guidance, do not reinvent it** — for `internal/**` Go changes, use the file-scoped instructions loaded per `REVIEW-SCOPE-005` rather than recalling provider design rules from memory.
4. **Default to Observation** — escalate to an Issue only when a current contributor document, instruction file, skill, or contract makes the design rule mandatory, and cite that source.
5. **Stay in scope** — record larger structural direction beyond the change-set as a follow-up Observation, not a blocking demand.

## Burden of proof

Findings must be tied to evidence, not asserted:

- cite the governing instruction, contract, or contributor-guidance source for any architectural Issue
- quote the workspace rule that the change violates
- cross-reference how related resources or patterns model the same concern

When the concern stays in workflow scope, preserve the shared handoff fields for `id`, `roles`, `title`, `scope`, `severity`, `evidence`, `reasoning`, `confidence`, and `status`, as defined by `.github/instructions/review-workflow-handoff.schema.json`.

Mark derived assumptions clearly ("based on how sibling resources model this block, the singular name appears inconsistent because...") rather than stating preference as policy. If no mandatory source supports the concern, keep it an Observation per `REVIEW-OBS-001`.

## Outcomes

The architect does not own the final outcome mapping. Findings resolve as follows:

- **Observation (default)** — design direction, preference, or out-of-scope structural idea, recorded in `### 🟡 **OBSERVATIONS**`.
- **Candidate Issue** — only when a mandatory source is violated; it then enters the candidate set and is resolved by the advocate pass under `REVIEW-ADV-005` (`Confirmed` / `Downgraded` / `Dismissed`).

No architect-proposed candidate may bypass advocate adjudication, and none may appear in both Issues and Observations.

## Tone

A staff engineer weighing how the change fits the system, focused on direction rather than nitpicks. Principled but pragmatic. The best direction feedback explains the trade-off and cites the rule. Frame Observations as "this fits better when...", and reserve "must" for concerns backed by a mandatory source.
