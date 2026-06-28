# Review Workflow Roadmap

This document captures the intended evolution path for the review workflow so the current stabilization work stays aligned with the longer-term multi-agent goal.

## Recovery Command

If a future session starts without this context loaded, use the following instruction near the top of the conversation:

```text
Load and use docs/REVIEW_WORKFLOW_ROADMAP.md as the canonical review-workflow roadmap for this repository. Treat it as the source of truth for the stabilization plan, role boundaries, and future multi-agent migration goals.
```

Short form:

```text
Load docs/REVIEW_WORKFLOW_ROADMAP.md into working memory and use it as the canonical review-workflow roadmap.
```

## Current State

- The review prompt acts as the orchestration layer.
- The prompt currently controls execution order, role gating, and the final output shape.
- `review-advocate` already functions as a governed second-pass role through `.github/skills/review-advocate/SKILL.md` and its companion contract `.github/instructions/review-advocate-compliance-contract.instructions.md`.
- Additional routed roles now exist in the active single-workflow design: `review-architect` and `review-skeptic`.
- The workflow now has a concrete shared handoff schema at `.github/instructions/review-workflow-handoff.schema.json` so routed findings move through one stable JSON-backed transport.
- The generic review prompts now describe a final adjudication owner slot that is currently bound to `review-advocate`.
- `review-moderator` now exists as staged semantics through `.github/skills/review-moderator/SKILL.md` and `.github/instructions/review-moderator-compliance-contract.instructions.md`, but the generic review prompts do not yet route it.
- Initial regression coverage now exists for schema-preserving routed-role handoff and for the future duplicate-merge moderation behavior.

### Current Prompt Responsibilities

Today the prompt is carrying several responsibilities at once:

- scope discovery and review setup
- deciding whether a second-pass role is invoked
- deciding what evidence is shown to that role
- defining what that role may change, downgrade, or dismiss
- binding the current final adjudication owner
- defining the final user-visible review structure

That is acceptable for the current single-workflow design, but it is also the main reason future role growth must be handled carefully. If new roles are added without cleaner boundaries, the prompt becomes both the orchestration shell and the policy engine.

## Near-Term Direction

The immediate goal is to make the current single-workflow review pipeline correct, explicit, and stable before changing the execution model.

### Planned Sequence

1. Merge the role-addition PR `#30`, `Add review-skeptic and review-architect panel review skills`. That PR introduces the following review artifacts:
	- `.github/skills/review-architect/SKILL.md`
	- `.github/skills/review-skeptic/SKILL.md`
	- `.github/instructions/review-architect-compliance-contract.instructions.md`
	- `.github/instructions/review-skeptic-compliance-contract.instructions.md`
2. Complete the stabilization work that now already exists in staged form on this branch: shared handoff schema, staged moderator semantics, routed-role regression coverage, and prompt wording that separates the final adjudication owner slot from the specific role currently bound to it.
3. Run the stabilized single-workflow design for a period of time and refine it through regression coverage and real usage.
4. Rebind the final adjudication owner from `review-advocate` to `review-moderator` once the moderator rules and regression coverage are sufficient.
5. Revisit multi-agent execution only after the role model and handoff behavior are stable.

## Stabilization Goals

The follow-up stabilization work should aim for:

- explicit review roles with clear responsibilities
- clearer separation between orchestration and role behavior
- structured intermediate outputs and handoffs
- deterministic moderation and adjudication rules
- regression coverage around role interactions and final review quality

The stabilization phase should treat the current workflow as the canonical place to define review semantics. The future multi-agent system should inherit those semantics rather than redefine them.

## Target Role Model

The exact naming can still evolve, but the intended shape is:

- `reviewer`: primary pass over the change set; currently embodied by the main review prompt rather than a standalone role-specific skill file
- `review-architect`: structure, design, and maintainability concerns; currently represented by `.github/skills/review-architect/SKILL.md`
- `review-skeptic`: challenge assumptions, push on edge cases, surface weaknesses; currently represented by `.github/skills/review-skeptic/SKILL.md`
- `review-advocate`: current false-positive-defense and second-pass challenge role; currently represented by `.github/skills/review-advocate/SKILL.md`
- `moderator`: intended stable end-state synthesis and adjudication role; now represented in staged form by `.github/skills/review-moderator/SKILL.md`, but not yet routed by the generic prompts

In this roadmap, `reviewer` refers to one logical primary review role. The local-changes and committed-changes review prompts are two different scope-acquisition entrypoints for that same role. Their difference is how they gather the code under review, not the semantics of the reviewer itself.

One likely outcome of the stabilization phase is to separate the current advocate behavior into distinct skeptic and moderator responsibilities.

### Expected Ownership By Role

#### Reviewer

Primary ownership:

- find concrete bugs, regressions, and missing validation
- identify behavior changes and likely user impact
- collect initial evidence and candidate findings

Should not own:

- final deduplication
- final downgrade or dismissal authority for disputed findings
- final formatting of the merged review if other roles participate

#### Review Architect

Primary ownership:

- structural coherence of the change
- design and maintainability concerns
- layering, abstraction, ownership, and workflow fit
- whether the implementation shape matches repo conventions and intended architecture

Should not own:

- broad policy veto over findings from other roles
- speculative bug reporting without evidence

#### Review Skeptic

Primary ownership:

- challenge assumptions in the initial review
- push on edge cases, omitted scenarios, and weak reasoning
- surface cases where a candidate finding may be incomplete or under-argued

Should not own:

- final dismissal authority by itself
- reformatting the final review

#### Review Advocate

Primary ownership in the current design:

- challenge false positives
- defend intentional design where evidence supports it
- downgrade or dismiss weak candidate findings when allowed by the workflow rules

Likely future direction:

- narrow this role toward false-positive defense only
- move final synthesis duties into a dedicated moderator role

#### Moderator

Primary ownership:

- merge outputs from the reviewer roles
- deduplicate overlapping findings
- normalize severity and wording
- decide the final accepted, downgraded, or dismissed outcome set
- produce the final user-visible review artifact

Should not own:

- generating a completely new independent review pass as a substitute for role outputs
- inventing evidence that was not surfaced by the prior stages

### Likely Stable End-State Role Split

The likely stable semantic split is:

- `reviewer`: first-pass findings
- `review-architect`: structure and design lens
- `review-skeptic`: edge-case and challenge lens
- `moderator`: final adjudication and output normalization

If `review-advocate` remains as a separate role, it should be treated as a specialized false-positive defender rather than as the permanent home for every second-pass responsibility.

Explicitly, the intended stable end-state role lineup is:

- `reviewer`
- `review-architect`
- `review-skeptic`
- `moderator`

`review-advocate` should be treated as transitional unless it is deliberately retained as a narrow false-positive-defense role with responsibilities distinct from `moderator`.

For avoidance of doubt after a reset:

- `review-advocate` = existing second-pass false-positive-defense role
- `review-architect` = new structure and maintainability role introduced by PR `#30`
- `review-skeptic` = new challenge and edge-case role introduced by PR `#30`
- `moderator` = intended future synthesis and adjudication role, now defined in staged form but not yet routed by generic prompts

## Ownership Boundaries And Allowed Actions

The current stabilization work should make the following questions explicit for each role:

- what inputs the role receives
- what outputs the role must produce
- whether it may add new findings
- whether it may only challenge or classify existing findings
- whether it may dismiss findings outright or only recommend dismissal
- whether it may change severity
- whether it may alter wording versus only annotate decisions

These boundaries should be documented in role definitions or companion contracts rather than left implicit in prompt prose.

## Structured Handoff Model

The future multi-agent design will only be tractable if the current single-workflow design already has a stable handoff shape.

At minimum, each role output should be compatible with a structure that can express:

- finding title
- file or scope
- severity
- evidence
- reasoning
- confidence
- status such as candidate, confirmed, downgraded, or dismissed
- optional contract or rule reference

The exact syntax can evolve, but the semantic fields should stabilize early.

During the stabilization phase, the semantic schema matters more than the final transport format. The workflow may begin with a structured markdown shape, a table-like shape, or a JSON-like block, but every role should emit the same fields consistently and deterministically.

The current concrete runtime schema for that transport now lives at `.github/instructions/review-workflow-handoff.schema.json`.

If the single-workflow version uses structured intermediate outputs now, the future multi-agent cutover becomes mostly a transport change:

- sequential execution can become parallel execution
- local role invocation can become subagent invocation
- same-role semantics can be reused with minimal rewriting

If the structure is not defined now, the eventual multi-agent cutover will require both an execution-model rewrite and a role-semantics rewrite at the same time.

## Moderator Decision Rules

The moderator layer should eventually be governed by explicit rules such as:

- preserve only findings with adequate evidence
- merge duplicates rather than repeat them
- dismiss findings that are contradicted by stronger evidence
- downgrade findings that identify a real concern but overstate severity
- prefer the narrowest defensible claim over the broadest speculative claim
- preserve the final review template and required markers

These rules should be regression-tested once they are formalized.

An initial staged benchmark for duplicate-merge behavior now exists so this moderator-specific responsibility can be validated before moderator routing is enabled.

## Design Principle For The Current Workflow

The current single-workflow design should be built as if it were already preparing for multi-agent execution.

That means:

- define role semantics clearly now
- define what each role may inspect, change, or dismiss
- define a stable intermediate output shape now
- keep execution-model assumptions separate from role semantics

If that is done well, a future multi-agent migration becomes mostly a runtime orchestration change rather than a full redesign.

### What Should Stay In The Prompt

The prompt should continue to own:

- workflow entrypoint behavior
- scope resolution rules
- invocation order or stage ordering
- required final output sections and formatting
- high-level role sequencing rules
- the binding of the current final adjudication owner

### What Should Move Out Of The Prompt Over Time

As the workflow matures, role-specific behavior should increasingly live in role-owned guidance rather than in a single large prompt. In particular:

- role responsibilities
- permitted role actions
- role-specific decision heuristics
- role-specific output expectations

That separation reduces the chance that the orchestration prompt becomes the single fragile source of truth for every role.

## Artifact Ownership

To keep the architecture understandable after resets or future refactors, the repository should treat artifact ownership as follows:

- the review prompt owns orchestration, execution order, scope rules, the current final adjudication owner binding, and the required final visible output shape
- role-specific skill or agent files own role behavior, role heuristics, and role-local expectations
- companion contracts or instruction files own hard rules, allowed actions, and non-negotiable policy constraints

In other words, the prompt should decide when roles run and what the final output must look like, while role definitions and contracts should decide how each role behaves and what it is permitted to do.

## Future End State

The long-term goal is a true multi-agent or subagent review workflow with parallel role execution and a moderation step.

That future design is expected to include:

- multiple role-specific reviewer executions
- optional per-role model selection when supported by the runtime host
- structured outputs from each role
- a moderator or adjudicator that merges, filters, and normalizes the final findings

### Desired Migration Property

The desired future change is:

- same roles
- same permissions
- same handoff structure
- same review semantics
- different execution model

That is the key design constraint for the stabilization phase.

## Multi-Agent Cutover Criteria

Do not cut over to multi-agent execution until the current workflow has all of the following:

- stable role definitions
- stable handoff schema
- reliable regression coverage
- acceptable false-positive behavior
- consistent final review formatting

Additional cutover criteria should include:

- role ownership is understandable without reading the entire prompt
- moderator behavior is deterministic enough to benchmark
- handoff payloads are stable enough to be produced and consumed by separate executors
- the current design has enough observability to compare single-workflow and multi-agent results

The desired cutover is a transport and runtime upgrade, not a simultaneous rewrite of role behavior.

## Practical Rollout Plan

### State Check Before Using This Plan

Before acting on the rollout phases in a fresh or reset session, check the current repository state for PR `#30`, `Add review-skeptic and review-architect panel review skills`.

Use the current branch contents and git history to decide which phase applies:

- If PR `#30` is still open or its artifacts are not present on the current branch, treat **Phase 1** as still pending.
- If PR `#30` is already merged and the following artifacts exist on the current branch, treat **Phase 1** as complete and begin from **Phase 2**:
	- `.github/skills/review-architect/SKILL.md`
	- `.github/skills/review-skeptic/SKILL.md`
	- `.github/instructions/review-architect-compliance-contract.instructions.md`
	- `.github/instructions/review-skeptic-compliance-contract.instructions.md`

Do not assume the roadmap is at the same time-state as when it was first written. Always anchor the next step to the actual git state of the repository.

If the current branch also contains the following staged artifacts, treat **Phase 2** as already partially implemented:

- `.github/instructions/review-workflow-handoff.schema.json`
- `.github/instructions/review-moderator-compliance-contract.instructions.md`
- `.github/skills/review-moderator/SKILL.md`
- `tools/regression/cases/review-local-handoff-schema-preserved-through-advocate.json`
- `tools/regression/cases/review-local-moderator-duplicate-merge-ready.json`

### Phase 1: Merge Current Role PR

- land PR `#30`, which adds `review-architect` and `review-skeptic` plus their companion contract files
- confirm that `review-architect` and `review-skeptic` are directionally correct as role additions
- avoid broad execution-model changes in the same PR

### Phase 2: Stabilization PR

- split advocate responsibilities where needed
- clarify skeptic versus moderator versus architect ownership
- define or tighten structured handoff expectations
- reduce prompt ambiguity around role permissions
- add regression coverage for role interactions and outcome classification

This stabilization PR is also the explicit reconciliation point between the existing `review-advocate` behavior and the new `review-skeptic` role introduced by PR `#30`. The cleanup should not treat those as independent changes.

The stabilization work should therefore ensure that:

- `review-advocate`, `review-skeptic`, and the intended `moderator` role do not retain overlapping responsibilities by accident
- contract rules are not duplicated across role-specific artifacts without an intentional reason
- challenge, downgrade, dismissal, and synthesis responsibilities are assigned to one clear owner each
- the resulting role split is a clean consolidation rather than an additive layering of partially redundant second-pass behaviors

The branch is already partway through this phase now:

- the shared handoff schema is defined and shipped
- the current final adjudication owner slot is abstracted in prompt wording and still bound to advocate
- moderator semantics are staged but not yet routed
- initial regression coverage exists for schema-preserving handoff and future duplicate-merge moderation behavior

#### Phase 2 Implementation Checklist

The stabilization PR should aim to leave the current workflow in a state where every role is understandable and testable without needing multi-agent execution.

##### A. Clarify Role Definitions

- define the canonical responsibility of `reviewer`
- define the canonical responsibility of `review-architect`
- define the canonical responsibility of `review-skeptic`
- define whether `review-advocate` remains a separate role or is partially or fully replaced by `moderator`
- document which role owns final synthesis

##### B. Split Advocate And Moderator Semantics

- separate false-positive defense behavior from final moderation behavior
- decide whether dismissal authority belongs to advocate, moderator, or both under different conditions
- decide whether severity changes are recommendations or authoritative decisions at each stage
- ensure the final synthesis stage is not overloaded with reviewer responsibilities

##### C. Define Role Inputs

- define what the first-pass reviewer receives
- define what downstream roles receive: raw diff, candidate findings, or both
- define whether downstream roles may inspect the full evidence set or only prior-stage summaries
- define whether downstream roles can introduce new findings or only challenge existing ones

##### D. Define Structured Intermediate Outputs

- choose a stable intermediate finding shape
- ensure every role can emit findings in that shape
- ensure every role can also emit explicit non-finding decisions such as confirmed, downgraded, or dismissed
- ensure rule or contract citations fit naturally into the structure when available

##### E. Tighten Orchestration Rules In The Prompt

- define when each role runs
- define whether roles run only when candidate findings exist or also in zero-finding cases
- define the execution order clearly
- define what final output sections the orchestrating prompt must always preserve
- reduce any prompt language that mixes orchestration with role-specific policy if that policy can be moved elsewhere
- isolate the final adjudication owner binding so the advocate-to-moderator cutover is a narrow routing change rather than a broad prompt rewrite

##### F. Define Moderator Rules Explicitly

- define duplicate-merge behavior
- define conflict-resolution behavior when roles disagree
- define what level of evidence is needed to keep a finding
- define downgrade rules
- define dismissal rules
- define the final formatting and ordering rules for the visible review output

##### G. Add Regression Coverage

- add cases for duplicate findings across roles
- add cases for valid findings that should survive challenge
- add cases for weak findings that should be downgraded or dismissed
- add cases for moderator conflict resolution
- add cases for required final formatting and markers

##### H. Define Success Criteria For Stabilization

The stabilization PR should be considered successful only if:

- the routed roles use one stable handoff structure
- the active final adjudication owner is explicit
- moderator semantics are benchmarkable before routing changes
- duplicate handling and final synthesis behavior are deterministic enough to compare across runs
- the future cutover from advocate to moderator is a narrow binding change rather than a second semantics rewrite
