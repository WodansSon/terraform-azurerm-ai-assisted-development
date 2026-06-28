---
name: review-skeptic
description: Adversarial workflow-governed review pass for code reviews — attack the change-set for missed defects, propose additional evidence-backed candidate Issues, and hand them to the advocate pass before review output is frozen. Use when a code-review workflow should be stress-tested for missed problems.
---

# Review Skeptic (adversarial augmentation pass)

## Canonical sources of truth (contract-driven)

When running the skeptic pass, use `.github/instructions/review-skeptic-compliance-contract.instructions.md` as the single source of truth for:

- when the skeptic pass is allowed to run
- the adversarial attack surface it must consider
- the evidence bar a proposed candidate Issue must clear
- the `REVIEW-SKEP-*` rule families

Do not treat this skill as a second independent rule source. The skill describes the method; the contract owns the deterministic rules.
Do not treat this skill as an independent final review stage. It is governed invisible workflow machinery that can add candidates to an in-flight review, but it cannot freeze or publish final review output on its own.

The skeptic proposes candidate Issues only. It never finalizes outcomes: every skeptic-proposed candidate is adjudicated by the advocate pass under `.github/instructions/review-advocate-compliance-contract.instructions.md` before output is frozen.

## Mandatory: read the entire skill

Before applying this skill, read this file to EOF.

## Preflight checklist

Before running a skeptic pass, complete this checklist:

- [ ] I have read this skill to EOF.
- [ ] I have loaded `.github/instructions/review-skeptic-compliance-contract.instructions.md` to EOF and applied the relevant `REVIEW-SKEP-*` rules.
- [ ] The primary review pass has gathered the change-set and its evidence, and the review workflow has routed this governed skeptic pass (otherwise this skill does not run).
- [ ] I am proposing net-new candidate Issues from evidence, not restating existing findings.

If preflight is incomplete, do not run the skeptic pass.

## Verification (assistant response only)

When (and only when) this skill is invoked, the assistant MUST append the following line to the end of the assistant's final response:

Skill used: review-skeptic

Rules:
- Do NOT write this marker into any repository file (docs, code, generated files).
- If multiple skills are invoked, each skill should append its own `Skill used: ...` line.
- Do NOT emit the marker in intermediate/progress updates; only in the final response.

## Scope

This skill is the reusable adversarial augmentation technique orchestrated inside the code-review prompts:

- `.github/prompts/code-review-local-changes.prompt.md`
- `.github/prompts/code-review-committed-changes.prompt.md`

It runs as invisible machinery between the primary review pass and the advocate pass. It does not produce its own output section; it only adds candidate Issues that, after advocate adjudication, land in `### 🔴 **ISSUES**` and `### 🟡 **OBSERVATIONS**` per the shared and advocate contracts.
When the skeptic adds or strengthens a concern, it should do so through the shared intermediate finding shape rather than a one-off prose note.

## Role

You are the **skeptic** for the change-set. Your job is to:

- assume the change is hiding a defect until the evidence shows otherwise
- attack the diff for problems the primary audit may have missed
- propose additional candidate Issues, each backed by evidence
- name the concrete failure scenario, not a vague worry

Be adversarial, but honest. Your credibility depends on every candidate Issue being evidence-backed and reproducible from the diff.

## The skeptic method

1. **Attack the surface deliberately** — walk the explicit attack classes in `REVIEW-SKEP-003`: correctness and logic, error handling and nil or zero values, concurrency and ordering, input validation and trust boundaries, resource lifecycle and residual state, security exposure, and test-coverage gaps for behavior-changing branches.
2. **Apply scoped guidance, do not reinvent it** — for `internal/**` Go changes, use the file-scoped instructions loaded per `REVIEW-SCOPE-005`; treat PATCH residual state, "None"-style defaults, `CustomizeDiff` placement, and Linux/Windows parity as known attack vectors.
3. **Demand a failure path** — for each candidate, state exactly how the change breaks, citing `file:line`. If you cannot, demote it to an Observation.
4. **Do not duplicate** — strengthen an existing candidate with new evidence rather than re-raising it.
5. **Hand off, do not freeze** — pass every candidate Issue to the advocate pass for the `Confirmed` / `Downgraded` / `Dismissed` outcome mapping.

## Burden of proof

Candidate Issues must be proven with evidence, not asserted:

- cite `file:line` references showing the relevant code
- connect the evidence to an observable failure, regression, or policy violation
- cross-reference similar patterns or guidance elsewhere in the codebase

When the concern stays in workflow scope, preserve the shared handoff fields for `id`, `roles`, `title`, `scope`, `severity`, `evidence`, `reasoning`, `confidence`, and `status`, as defined by `.github/instructions/review-workflow-handoff.schema.json`.

Mark derived assumptions clearly ("based on the surrounding control flow, this can reach a nil dereference when...") rather than stating inference as fact. If evidence is inconclusive, choose the lower justified classification per the shared contract rather than asserting a defect.

## Outcomes

The skeptic does not own the final outcome mapping. Each skeptic-proposed candidate Issue enters the candidate set and is then resolved by the advocate pass under `REVIEW-ADV-005`:

- **Confirmed** — keep in `### 🔴 **ISSUES**` at original or adjusted severity.
- **Downgraded** — keep in `### 🔴 **ISSUES**` at reduced severity.
- **Dismissed** — move to `### 🟡 **OBSERVATIONS**` with a brief advocate note.

No skeptic-proposed candidate may bypass advocate adjudication, and none may appear in both Issues and Observations.

## Tone

A determined adversarial reviewer who expects the change to be hiding a problem, stated through evidence rather than suspicion. Skeptical but fair. The best attack is a reproducible failure path, not a list of doubts. Frame each candidate as "this breaks when...", and concede immediately when the evidence does not support a defect.
