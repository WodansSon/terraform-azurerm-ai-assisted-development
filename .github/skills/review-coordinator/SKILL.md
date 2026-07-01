---
name: review-coordinator
description: Read-only workflow coordinator for code reviews — build a deterministic coverage matrix from authoritative changed-file scope, identify lifecycle/control windows and overlapping ownership surfaces, and require completion of mandatory issue-class checks before findings can freeze. Use when a code-review workflow must avoid active-file bias and keep review coverage order stable across reruns.
---

# Review Coordinator (deterministic coverage planner)

## Canonical sources of truth (contract-driven)

When running the review-coordinator pass, use `.github/instructions/code-review-compliance-contract.instructions.md` as the single source of truth for:

- the deterministic coverage-routing requirements
- the structured coverage-matrix requirements
- the fixed lifecycle/control-window order
- the overlap-surface rules for new resources
- the mandatory issue-class checks that must complete before findings freeze
- the `REVIEW-COORD-*` rule families

Also use `.github/instructions/review-coverage-matrix.schema.json` as the canonical runtime shape for the internal coverage matrix artifact.

Do not treat this skill as a second independent rule source. The skill describes the routing method; the shared review contract owns the deterministic rules.
Do not treat this skill as a reviewer, moderator, or adjudicator. It is read-only workflow machinery that identifies what must be inspected before findings can freeze.

## Mandatory: read the entire skill

Before applying this skill, read this file to EOF.

## Preflight checklist

Before running the review-coordinator pass, complete this checklist:

- [ ] I have read this skill to EOF.
- [ ] I have loaded `.github/instructions/code-review-compliance-contract.instructions.md` to EOF and applied the relevant `REVIEW-COORD-*` rules.
- [ ] I have loaded `.github/instructions/review-coverage-matrix.schema.json` to EOF.
- [ ] The prompt has already resolved authoritative changed-file scope for the current invocation.
- [ ] I am building a read-only coverage matrix, not classifying or freezing findings.

If preflight is incomplete, do not run the routing pass.

## Verification (assistant response only)

When (and only when) this skill is invoked, the assistant MUST append the following line to the end of the assistant's final response:

Skill used: review-coordinator

Rules:
- Do NOT write this marker into any repository file.
- If multiple skills are invoked, each skill should append its own `Skill used: ...` line.
- Do NOT emit the marker in intermediate/progress updates; only in the final response.

## Scope

This skill is the reusable deterministic coverage-routing technique orchestrated inside the code-review prompts:

- `.github/prompts/code-review-local-changes.prompt.md`
- `.github/prompts/code-review-committed-changes.prompt.md`

It runs after authoritative review scope is known and before findings are drafted. It does not classify issues, produce observations, or freeze outcomes. It has two workflow phases: an early build phase that constructs the structured matrix before standards loading, and a later validation phase that marks the matrix complete only after the relevant scoped standards are available.

The validation phase is the canonical mechanism that confirms coverage-matrix completion before findings or routed roles can proceed.

## Role

You are the **coverage coordinator** for the change-set. Your job is to:

- consume the authoritative changed-file scope
- identify the implementation file families that must be inspected
- identify the lifecycle/control windows that must be inspected in fixed order
- identify overlapping ownership surfaces for new resources
- identify the mandatory issue-class checks that must complete before findings can freeze
- produce a schema-conformant internal coverage matrix that later workflow steps can validate mechanically

## Workflow phases

### Build phase

The build phase runs before standards loading. It is responsible for:

- identifying required rows
- materializing unchanged overlap rows by explicit file path
- attaching fixed lifecycle/control-window ordering
- attaching required issue classes and explicit not-applicable issue-class containers
- building the structured matrix without freezing completion state prematurely

### Validation phase

The validation phase runs after the prompt has loaded the applicable workspace standards and scoped guidance. It is responsible for confirming that:

- every required row exists
- every required window is present in `completedWindows` or `notApplicableWindows`
- every required issue class is present in `completedIssueClasses` or `notApplicableIssueClasses`
- every top-level required issue class is present in `completedIssueClasses` or `notApplicableIssueClasses`
- unchanged overlap rows remain materialized as explicit file-path rows
- completion status is justified by current-run evidence

Routed roles cannot start until this validation phase succeeds.

Be mechanical, not interpretive. Prefer broader deterministic inclusion over omission when ambiguity remains.

## The coverage-routing method

1. **Consume the authoritative scope, do not anchor on the active file** — start from the resolved review scope rather than the editor selection, PR title, or prior discussion.
2. **Filter and sort implementation surfaces** — collect in-scope implementation files under `internal/**/*.go`, classify them by surface type when possible, and sort them lexically before selecting a first review anchor.
3. **Build schema-conformant family rows** — represent each required surface as an explicit row in a coverage matrix that conforms to `.github/instructions/review-coverage-matrix.schema.json`.
4. **Prefer explicit code anchors over filename intuition** — group related files by service path plus explicit anchors such as shared ID parsers, shared validation helpers, shared registration entries, shared route or association references, and shared ownership or mode helpers. If family boundaries remain ambiguous after those checks, prefer broader inclusion in the matrix over omission.
5. **Attach fixed control-window order** — for each applicable row, require reads in this order when present: `Importer`, `Create`, `Read`, `Update`, `Delete`, `CustomizeDiff`, explicit validation or mode or ownership helpers, then companion registration, tests, docs, and association surfaces.
6. **Expand overlap coverage for new resources** — when the scope adds a brand-new resource, add overlapping sibling resources, data sources, list resources, route or association or referencing surfaces, and explicit mode or ownership validation helpers that can manage the same remote object, even if they are unchanged.
7. **Materialize overlap rows by file path** — every unchanged overlap surface must appear as its own explicit file-path row in the structured matrix; do not record overlap coverage only as a category-level note.
8. **Attach mandatory issue-class checks** — for provider surfaces, require ownership-overlap checks, import/read/update/delete mode-gating symmetry checks, destructive-path gating checks, poller terminal-failure checks, validator-to-doc parity checks, companion completeness checks, list-resource exception checks, and identity/list/docs/test companion checks.
9. **Build first, validate later** — use the build phase to create rows, overlap rows, required windows, required issue classes, and explicit `notApplicableIssueClasses` containers before standards loading. Use the later validation phase, after the prompt has loaded the relevant workspace standards and scoped guidance, to mark standards-dependent issue classes complete or not applicable.
10. **Validate completion mechanically** — use the validation phase as the explicit completion gate that confirms row existence, window coverage, issue-class coverage, overlap-row materialization, and evidence-backed not-applicable state before the matrix can be marked complete.
11. **Gate completion before routed roles** — mark the matrix complete only when every required row has either been inspected in the required order or has a current-run evidence-backed not-applicable justification. Routed roles must not start before that completion state is reached.

## Burden of proof

Coverage routing decisions must be mechanical and evidenced:

- use the changed-file scope, path shape, nearby helper names, and current workspace structure to identify required rows
- use the schema's row fields and completion fields explicitly rather than keeping the matrix only as prose intent
- use the later validation phase to complete standards-dependent issue classes only after the prompt has loaded the relevant contributor guidance, file-scoped instructions, or docs contract guidance
- represent non-applicable issue-class state explicitly in `notApplicableIssueClasses` at both the row and matrix levels rather than inferring it only from prose
- treat the validation phase as the canonical place where completion invariants are checked rather than as an informal follow-up reminder
- prefer explicit overlaps such as shared IDs, shared helpers, shared route associations, or documented management-boundary helpers over speculative architecture guesses
- when in doubt about whether a sibling surface overlaps ownership, include it in the matrix rather than omitting it
- if a required lifecycle window does not exist in a surface, record it as not applicable rather than silently skipping it

This skill does not prove defects. It proves only what the workflow must inspect before defect claims can be frozen.

## Outcomes

The coverage coordinator does not own findings. It produces only workflow-internal coverage state:

- **Coverage matrix built** — the prompt now has a schema-conformant matrix that names required files, windows, issue classes, and explicit not-applicable issue-class state.
- **Validation phase defined** — the prompt now has an explicit router-owned completion gate for row existence, coverage invariants, overlap-row materialization, and evidence-backed completion status.
- **Overlap surfaces identified** — unchanged sibling surfaces are explicitly included as file-path rows when new resources create ownership overlap risk.
- **Completion gate armed** — the rest of the workflow, including routed roles, cannot continue until the matrix is complete.

## Tone

Neutral and procedural. The best routing pass is one that makes repeated reviews walk the same surfaces in the same order regardless of which file happened to be open.
