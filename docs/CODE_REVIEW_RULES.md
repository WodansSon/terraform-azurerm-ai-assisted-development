# Code Review Rule Reference

This document explains the rule IDs that appear in review output from this repository's Copilot review prompts.

## Why These IDs Appear

The review prompts use stable rule IDs so they can explain why a finding was reported without repeating the full contract text every time.

For example, a review might say:

`Scope Rules: REVIEW-SCOPE-005 was directly relevant because the change is under internal/**/*.go. REVIEW-SCOPE-001 was also relevant because the change affects user-visible source comments.`

That means:

- `REVIEW-SCOPE-005`: the prompt applied the Go and acceptance-test-specific review rules because the changed file path matched `internal/**/*.go`.
- `REVIEW-SCOPE-001`: the prompt also checked user-visible text quality because comments and other visible text are part of the review scope.

The IDs are there to make the review explainable and deterministic. They are references to the governing contract, not user actions you need to run manually.

## Where The Rules Live

There are eleven main contract files:

- Generic code review contract: `.github/instructions/code-review-compliance-contract.instructions.md`
- Generic review linter contract: `.github/instructions/review-linter-compliance-contract.instructions.md`
- Advocate second-pass contract: `.github/instructions/review-advocate-compliance-contract.instructions.md`
- Skeptic adversarial-pass contract: `.github/instructions/review-skeptic-compliance-contract.instructions.md`
- Architect direction-pass contract: `.github/instructions/review-architect-compliance-contract.instructions.md`
- Moderator synthesis-pass contract: `.github/instructions/review-moderator-compliance-contract.instructions.md`
- Presentation render contract: `.github/instructions/review-presentation-compliance-contract.instructions.md`
- PR description drafting contract: `.github/instructions/pr-description-compliance-contract.instructions.md`
- Docs review contract: `.github/instructions/docs-compliance-contract.instructions.md`
- Implementation contract: `.github/instructions/implementation-compliance-contract.instructions.md`
- Testing contract: `.github/instructions/testing-compliance-contract.instructions.md`

The prompts, skills, and routing instructions consume those contracts:

- `/code-review-local-changes`
- `/code-review-committed-changes`
- `/review-advocate`
- `/review-skeptic`
- `/review-architect`
- `/review-moderator`
- `/review-presentation`
- `/review-coordinator`
- `/code-review-docs`
- `/draft-pr-description`
- `/docs-writer`
- `/resource-implementation`
- `/acceptance-testing`

The `review-skeptic` and `review-architect` skills are workflow-governed intermediate passes.
The generic code review prompts invoke them after the primary review pass as governed intermediate passes.
They may add evidence-backed issues or observations inside the generic code-review workflow, but they do not emit standalone final review sections and any findings they add still flow through the shared moderation path.

The `review-advocate` skill is the workflow's false-positive-defense commentary pass.
The generic code review prompts invoke it when findings exist after the primary review pass and any routed skeptic or architect passes, and it records evidence-backed defense notes on those same findings instead of running a separate candidate-outcome state machine.

The `review-moderator` skill is the workflow's final moderation role.
The generic code review prompts route the full findings set through `review-moderator` after earlier finding-generation and commentary passes complete.

The `review-presentation` skill is the workflow's render-only presentation layer.
The generic code review prompts route the final frozen review data through `review-presentation` after moderation completes so both prompts share one output template.

The `review-coordinator` skill is the workflow's deterministic coverage-routing layer.
The generic code review prompts route authoritative changed-file scope through `review-coordinator` before standards loading and finding drafting so active-file bias cannot decide the first review anchor.
That routing layer now produces a schema-backed internal coverage matrix via `.github/instructions/review-coverage-matrix.schema.json`, names unchanged overlap rows by explicit file path, builds the matrix before standards loading, validates completion after scoped standards load, and must complete before any routed review role can start.
The matrix now also carries explicit `emittedRecordIds` and `issueClassToRecordIds` fields, and the coordinator owns a post-review linkage-validation phase so the workflow can hard-stop if a reviewer noticed a concern but failed to serialize it into the shared handoff record set before architect, skeptic, advocate, or moderator begin.

The important architectural point is that these contract files are now the normative rule sources.

Companion guides under `.github/instructions/` still matter, but they are primarily there to provide worked patterns, heuristics, and examples that support the contracts. If a workflow cites a stable rule ID such as `REVIEW-*`, `PRDESC-*`, `DOCS-*`, `IMPL-*`, or `TEST-*`, the authority for that citation lives in a contract file, not in a companion guide.

In practice, that means:

- contract files define the stable rule IDs and the governing requirements
- prompts and skills consume those contracts during audits and authoring flows
- companion guides help the model apply those rules correctly without acting as a second authority layer

## How To Read A Rule ID

Rule IDs follow a stable format:

`PREFIX-AREA-NUMBER`

Examples:

- `REVIEW-SCOPE-005`
- `REVIEW-LINT-002C`
- `PRDESC-TITLE-001`
- `DOCS-ARG-001`
- `IMPL-PATCH-001`
- `TEST-PATTERN-002`

The parts mean:

- `REVIEW`, `PRDESC`, `DOCS`, `IMPL`, or `TEST`: which contract the rule came from
- `AREA`: the category of rule
- `NUMBER`: the specific rule inside that category

Some contract rules also include provenance labels to clarify where the rule came from:

- `Published upstream standard`: documented upstream
- `Inferred maintainer convention`: derived from factual maintainer review behavior
- `Local safeguard`: added by this repository to keep audits and edits deterministic

Those provenance notes matter because not every useful rule is written down in upstream contributor docs.

## `REVIEW-*` Rule Areas

These IDs come from `.github/instructions/code-review-compliance-contract.instructions.md` and are used by the generic code review prompts.

| Prefix | Meaning | What it usually tells the user |
| ------ | ------- | ------------------------------ |
| `REVIEW-EVID-*` | Evidence and verification | The review had to prove the claim from the diff, code, docs, or tool output instead of guessing |
| `REVIEW-CLASS-*` | Finding classification | Why something was reported as an Issue, Observation, or Strength |
| `REVIEW-COORD-*` | Deterministic coverage routing | Which files, lifecycle windows, overlap surfaces, and mandatory issue-class checks had to be inspected before findings could freeze |
| `REVIEW-HANDOFF-*` | Intermediate finding handoff | How routed review roles exchange immutable findings before final output is frozen |
| `REVIEW-FILE-*` | File handling and scope coverage | Which changed files had to be considered and how they were classified |
| `REVIEW-SCOPE-*` | File-type-specific review coverage | Which extra checks applied because of the file type or content |
| `REVIEW-TEST-*` | Acceptance-test review guidance | How embedded Terraform, ImportStep, or requires-import patterns were evaluated |
| `REVIEW-OBS-*` | Observation-only design guidance | Non-blocking design preferences that should not automatically become Issues |
| `REVIEW-LINT-*` | `azurerm-linter` behavior | How the linter should be run, interpreted, and surfaced in review output |
| `REVIEW-OUT-*` | Output semantics | How the final review should be structured and worded |

## Common `REVIEW-*` Examples

### `REVIEW-SCOPE-001`

This means the review checked user-visible text quality. It commonly applies to:

- Comments
- README changes
- Prompt text
- Installer help text
- End-user error messages

### `REVIEW-SCOPE-004`

This means the review applied AI-customization-file checks because the change touched files such as:

- `.github/prompts/**`
- `.github/instructions/**`
- `.github/skills/**`

It usually signals that the reviewer checked determinism, precedence, and alignment with shared contracts.

### `REVIEW-FILE-004`

This means the review applied the committed-review PR-scope rules.

In practice, the review should:

- use authoritative PR scope instead of drifting into unrelated branch-only commits
- treat an explicit PR number as a prompt to try a direct shell-native HTTPS PR-files request first
- prefer a JSON-returning HTTPS request shape for PR files, and never treat terminal spill banners or saved-output wrapper text as the JSON payload itself
- ignore summary-only PR metadata, browser links, and forbidden spill-file paths as non-authoritative initial scope, including saved-output artifacts under `workspaceStorage` or `chat-session-resources`; once authoritative PR scope is already established from an allowed source, a current-run transient transport artifact may still be used as a buffer without becoming a new source of truth
- avoid automatic `gh api` fallback and use `gh` only when the user explicitly asks for it
- fail closed with a specific file-availability error when authoritative PR scope names a non-deleted changed file that is missing from the local committed checkout, instead of degrading that condition into a generic coverage-matrix failure

### `REVIEW-SCOPE-005`

This means the review applied Go/provider-specific guidance because the change touched:

- `internal/**/*.go`
- `internal/**/*_test.go`

It is the rule that tells the auditor to load the scoped Go instructions and skills instead of relying only on the generic review contract.

### `REVIEW-COORD-*`

These rules explain how the review stays deterministic before findings are drafted.

In practice, they require the workflow to:

- build a deterministic coverage matrix before findings freeze
- represent that matrix as a schema-backed internal artifact rather than prose intent alone
- load the coverage-matrix schema explicitly before building the matrix
- sort changed implementation surfaces lexically instead of anchoring on the active editor file
- inspect lifecycle windows such as Importer, Create, Read, Update, Delete, and CustomizeDiff in a fixed order when those windows exist
- scan unchanged sibling ownership surfaces when a PR adds a new resource that can overlap an older management surface, and materialize those overlap surfaces as explicit file-path rows
- start new or materially changed variant-constrained ownership reviews with ownership-boundary and lifecycle-symmetry checks before secondary polish findings such as metadata filtering or test-shape completeness
- build the matrix early but validate standards-dependent completion only after the relevant scoped guidance is loaded
- model issue-class completion explicitly, including not-applicable issue classes, instead of inferring that state only from prose
- treat the router validation sub-phase as the canonical completion gate rather than relying on prompt prose alone
- block architect, skeptic, advocate, and moderator routing until the coverage matrix is complete
- fail closed if an evidence-backed concern was discovered but no structured handoff record ID was emitted for it before routed roles begin
- emit and link a structured handoff record immediately when a mandatory issue-class check yields an evidence-backed concern, instead of relying on later bulk serialization
- keep the shared review contract as the full authority for that immediate-emission and linkage-validation behavior, with prompts and the coordinator invoking the relevant rule IDs instead of restating the full rule text independently
- keep ownership-boundary, lifecycle-symmetry, PATCH-or-residual-state, and optional-state-drift concerns as separate findings when current-run evidence supports each one on the same new-resource PR
- classify mandatory issue-class concerns as `OBSERVATIONS` when the current run proves only broader risk or a non-blocking mismatch, and escalate them to `ISSUES` only when the evidence proves concrete blocking harm or another explicitly blocking rule applies
- complete mandatory issue-class checks, such as ownership overlap, destructive-path gating symmetry, PATCH or residual-state review, and omitted-config state-drift review, before final output is emitted
- treat the upstream minimum new-resource acceptance-test matrix as part of the mandatory issue-class review surface for brand-new managed resources with acceptance coverage, so missing `basic`, `requiresImport`, `complete`, or `update` scenarios cannot be silently dropped behind larger findings
- when changed reference docs are in scope, treat evidence-backed docs example correctness under exact `DOCS-*` rules as a mandatory issue class that must stay visible when current-run evidence proves a real docs problem
- surface any evidence-backed concern found in those required checks at the justified classification instead of silently dropping it just because another blocking issue was found first
- validate file-reference policy against the assistant-emitted markdown body the workflow owns, not against any later VS Code or Copilot client href rewriting
- for brand-new managed resources with acceptance coverage, explicitly inspect the upstream minimum resource test matrix of `basic`, `requiresImport`, `complete`, and `update`, and keep any missing minimum scenario visible at least as an observation unless current-run evidence shows that specific expectation does not apply

### `REVIEW-SCOPE-005D`

This means the review checked whether newly added provider-side lifecycle logging is actually justified.

In practice, the review should:

- flag generic `Import check`, `Creating`, `Reading`, `Updating`, or `Deleting` logs when they only duplicate Terraform core or provider-native logging
- allow narrow not-found or removing-from-state diagnostics when they add distinct debugging value
- prefer SDK/framework-level solutions if consistent lifecycle logging is desired across many resources

### `REVIEW-SCOPE-005G`

This means the review checked two create-path behaviors that are easy to miss in provider Go code.

In practice, the review should:

- flag create-time `tf.ImportAsExistsError(...)` branches that ignore the `SkipImportCheckOnCreateAndAllowOverwritingExistingResources` feature gate
- flag callback-based create flows for resources with Resource Identity when the callback only sets the Terraform ID and does not also set identity data
- treat these as behavior issues, not stylistic preferences, because they can break configured overwrite-on-create behavior or leave Resource Identity incomplete after create

### `REVIEW-FILE-005`

This means the review recognized vendored third-party files under `vendor/**` as non-actionable scope.

In practice, the review should:

- disclose the count of vendored files skipped in the diff rather than listing each vendored path
- avoid raising Issues that tell a contributor to edit vendored files directly
- focus findings on the first actionable non-vendored source, such as dependency bumps, generation inputs, or service wiring
- say explicitly when a change-set is vendored-only or vendored-heavy so sparse actionable findings are easy to interpret

### `REVIEW-LINT-*`

These rules come from `.github/instructions/review-linter-compliance-contract.instructions.md` and explain how `azurerm-linter` should be handled. If you see a `REVIEW-LINT-*` citation, it usually means the review is explaining one of these:

- Whether the linter was applicable
- The simplified baseline invocation model: one filtered JSON-mode run from the repo root
- Why the linter section is `Issues found`, `No issues`, `Not applicable`, or `Not run`
- How linter findings were turned into review Issues

The contract-first model matters here too: the linter execution policy, status mapping, and output-shape requirements now live in the dedicated review linter contract, while troubleshooting and companion docs explain the runtime behavior and known failure modes around those rules.

## `REVIEW-ADV-*` Rule Area

These IDs come from `.github/instructions/review-advocate-compliance-contract.instructions.md` and are consumed by `/review-advocate`, which the generic code review prompts invoke as the workflow's false-positive-defense commentary pass when findings exist anywhere in the workflow finding set.

| Prefix | Meaning | What it usually tells the user |
| ------ | ------- | ------------------------------ |
| `REVIEW-ADV-*` | Advocate second-pass evaluation | How existing findings are challenged with evidence-backed defense commentary before review output is frozen |

In practice, `REVIEW-ADV-*` rules explain things such as:

- when the advocate pass is allowed to run
- which earlier passes are allowed to feed findings into the advocate pass
- what counts as a valid defense
- how trust-boundary defenses must be justified
- how advocate commentary stays attached to the same finding record through `roleNotes`
- why advocate commentary informs moderation without deleting the underlying finding directly

## `REVIEW-HANDOFF-*` Rule Area

These IDs come from `.github/instructions/code-review-compliance-contract.instructions.md` and govern the shared intermediate finding shape used between the primary review pass, routed intermediate passes, advocate commentary, and final moderation. The concrete runtime schema for that shape lives at `.github/instructions/review-workflow-handoff.schema.json`.

| Prefix | Meaning | What it usually tells the user |
| ------ | ------- | ------------------------------ |
| `REVIEW-HANDOFF-*` | Intermediate finding handoff | How the workflow preserves title, scope, evidence, reasoning, confidence, classification, and visibility while routed roles add or comment on findings |

In practice, `REVIEW-HANDOFF-*` rules explain things such as:

- which semantic fields every intermediate finding must preserve
- how `classification`, `visible`, and duplicate-merge lineage survive across routed passes
- why routed roles should enrich one record instead of cloning duplicate findings
- why the workflow can change transport later without redefining role semantics
- where the concrete JSON schema artifact for the handoff record lives in the installed toolkit

## `REVIEW-SKEP-*` Rule Area

These IDs come from `.github/instructions/review-skeptic-compliance-contract.instructions.md` and are consumed by `/review-skeptic` as a workflow-governed intermediate pass inside the generic code review prompts.

| Prefix | Meaning | What it usually tells the user |
| ------ | ------- | ------------------------------ |
| `REVIEW-SKEP-*` | Skeptic adversarial-pass evaluation | How the workflow stress-tests a change-set for missed defects before moderation freezes output |

In practice, `REVIEW-SKEP-*` rules explain things such as:

- when the skeptic pass is allowed to run
- which attack surfaces it must examine
- what evidence a skeptic-proposed issue must carry
- why skeptic output stays invisible until the normal review sections are finalized

## `REVIEW-ARCH-*` Rule Area

These IDs come from `.github/instructions/review-architect-compliance-contract.instructions.md` and are consumed by `/review-architect` as a workflow-governed intermediate pass inside the generic code review prompts.

| Prefix | Meaning | What it usually tells the user |
| ------ | ------- | ------------------------------ |
| `REVIEW-ARCH-*` | Architect direction-pass evaluation | How the workflow evaluates design fit, schema direction, and maintainability before final moderation freezes output |

In practice, `REVIEW-ARCH-*` rules explain things such as:

- when the architect pass is allowed to run
- which design-direction areas it must examine
- why most architect feedback is an Observation unless a mandatory source is violated
- why architect output stays invisible until the normal review sections are finalized

## `REVIEW-MOD-*` Rule Area

These IDs come from `.github/instructions/review-moderator-compliance-contract.instructions.md` and describe the moderator synthesis role that merges schema-conformant workflow findings after earlier passes have attached their findings and commentary.

| Prefix | Meaning | What it usually tells the user |
| ------ | ------- | ------------------------------ |
| `REVIEW-MOD-*` | Moderator synthesis-pass evaluation | How the moderator role merges, normalizes, and finalizes routed findings without re-running an independent review |

In practice, `REVIEW-MOD-*` rules explain things such as:

- how duplicate findings should merge into one strongest record
- how schema-backed workflow records should survive into final moderation
- how moderator routing consumes advocate commentary without reopening a second defense pass
- why moderator output stays upstream of final rendering rather than adding a separate reader-visible section

## `REVIEW-PRES-*` Rule Area

These IDs come from `.github/instructions/review-presentation-compliance-contract.instructions.md` and are consumed by `/review-presentation`, which the generic code review prompts invoke as the render-only final step after moderation freezes the review data.

| Prefix | Meaning | What it usually tells the user |
| ------ | ------- | ------------------------------ |
| `REVIEW-PRES-*` | Review presentation rendering | How the final review body is rendered from frozen data without changing findings |

In practice, `REVIEW-PRES-*` rules explain things such as:

- why local and committed review share one final output template
- which section order and heading text are fixed by the presentation layer
- why the renderer must not add, remove, or reinterpret findings
- why structured issue and observation findings can render as titled list items with separate `Impact` and `Evidence` blocks once moderator-owned presentation hints exist
- how footer lines such as `Preflight complete: yes` and `Skill used: ...` are rendered deterministically

## `PRDESC-*` Rule Areas

These IDs come from `.github/instructions/pr-description-compliance-contract.instructions.md` and are used by `/draft-pr-description` to author, rather than review, an AzureRM pull request title and body.

| Prefix | Meaning | What it usually tells the user |
| ------ | ------- | ------------------------------ |
| `PRDESC-PRE-*` | Preflight, repository eligibility, and stability | Why direct Git selected the branch, commands stayed read-only, or a changing checkout stopped drafting |
| `PRDESC-BASE-*` | Local comparison-base resolution | How existing `upstream/main`, `origin/main`, or local `main` determined the common ancestor without a fetch |
| `PRDESC-SCOPE-*` | Change collection and classification | Which committed, staged, unstaged, and untracked files contributed to the draft and which surfaces were title-driving, title-subordinate user-facing changes, or implementation companions |
| `PRDESC-EVID-*` | Evidence and validation claims | Why test, intent, issue, or completion claims were included, omitted, or left for contributor input |
| `PRDESC-TITLE-*` | Title selection | Why one AzureRM title shape won under the fixed surface and change-type precedence |
| `PRDESC-BODY-*` | Template-preserving body drafting | How immutable template prose, URLs, comments, headings, and checklist text stayed verbatim while designated response areas were populated conservatively |
| `PRDESC-CHECK-*` | Checklist decisions | Why each template checklist item stayed unchecked or was supported as complete |
| `PRDESC-CHANGELOG-*` | Changelog decisions | Whether maintainer automation-ready feature, enhancement, and bug-fix lines were warranted while implementation-only companions stayed subordinate |
| `PRDESC-ISSUE-*` | Confirmed issues | How explicit developer or current-branch commit references enter the body without a search |
| `PRDESC-OUT-*` | Handoff and output | How the lean schema-backed payload becomes the exact four-section response and verification footer |
| `PRDESC-FAIL-*` | Hard stops | Which ineligible repository, missing local base, ambiguous scope, changed state, or invalid payload prevents rendering |

The hidden `pr-description` skill owns the reusable drafting procedure and emits the lean schema-version `2.0` handoff defined by `.github/instructions/pr-description-draft.schema.json`; the prompt owns fixed direct-Git evidence collection, exact hard stops, the final `HEAD` and status comparison, in-memory schema conformance, and presentation. The normal path intentionally omits generated terminal programs, fetches, GitHub searches, policy reloads, full-content fingerprints, and alternate-environment discovery. Neither consumer redefines the contract rules.

## `DOCS-*` Rule Areas

These IDs come from `.github/instructions/docs-compliance-contract.instructions.md` and are primarily used by `/code-review-docs` and `/docs-writer` for `website/docs/**/*.html.markdown` pages.

| Prefix | Meaning | What it usually tells the user |
| ------ | ------- | ------------------------------ |
| `DOCS-EVID-*` | Evidence guardrails | The docs audit refused to guess values, imports, or constraints without code evidence |
| `DOCS-OBS-*` | Observation-only guidance | Non-blocking docs or schema-design suggestions |
| `DOCS-FM-*` | Frontmatter | YAML frontmatter requirements such as `page_title`, `layout`, and `subcategory` |
| `DOCS-STRUCT-*` | Document structure | Required sections, section ordering, and doc-type structure for resource, data source, list-resource, ephemeral-resource, and function pages |
| `DOCS-FMT-*` | Formatting | Backticks, intro lines, and code-fence conventions |
| `DOCS-IMP-*` | Import docs | Import wording and example correctness |
| `DOCS-SHAPE-*` | Schema shape parity | Whether docs reflect blocks, maps, lists, and nested structures correctly |
| `DOCS-EX-*` | Example code | Example correctness, resource self-containedness, data source lookup behavior, list-resource query behavior, ephemeral-resource usage, function-call usage, naming, and Terraform syntax |
| `DOCS-NOTE-*` | Notes | Required note blocks, note severity, formatting, and de-duplication |
| `DOCS-ARG-*` | Arguments Reference | Field coverage, ordering, defaults, and validation wording |
| `DOCS-ATTR-*` | Attributes Reference | Computed field coverage and ordering |
| `DOCS-WORD-*` | Wording | Canonical phrasing such as ForceNew and enum wording |
| `DOCS-TIMEOUT-*` | Timeouts | Timeouts formatting and readability |
| `DOCS-LINK-*` | Links | Link correctness and hygiene |
| `DOCS-SEC-*` | Security | Secret exposure or unsafe examples |
| `DOCS-DEPR-*` | Deprecation handling | Next-major and deprecated-surface rules |

## `IMPL-*` Rule Areas

These IDs come from `.github/instructions/implementation-compliance-contract.instructions.md` and are primarily used by the implementation contract, Go routing, and the `resource-implementation` skill for `internal/**/*.go` work.

| Prefix | Meaning | What it usually tells the user |
| ------ | ------- | ------------------------------ |
| `IMPL-EVID-*` | Evidence and verification | The implementation guidance had to be grounded in provider code, SDK/client models, or nearby implementations instead of guessing |
| `IMPL-WF-*` | Workflow | Which high-level implementation approach should be preferred, such as typed resources for new work, framework ephemeral resources, and provider-defined functions |
| `IMPL-SCHEMA-*` | Schema and mapping | How schema shape, field ordering, and field requirements should align with real provider behavior |
| `IMPL-PATCH-*` | PATCH and residual state | How Azure PATCH behavior should be handled so omitted fields do not leave stale state behind |
| `IMPL-ERR-*` | Error handling | How provider-standard error wording and wrapping should be applied |
| `IMPL-TEST-*` | Testing expectations | When implementation changes should carry test updates or rely on common acceptance-test patterns |
| `IMPL-CODE-*` | Code clarity | Comment discipline and self-documenting code expectations |

## `TEST-*` Rule Areas

These IDs come from `.github/instructions/testing-compliance-contract.instructions.md` and are primarily used by the testing contract, test routing, and the `acceptance-testing` skill for `internal/**/*_test.go` work.

| Prefix | Meaning | What it usually tells the user |
| ------ | ------- | ------------------------------ |
| `TEST-EVID-*` | Evidence and verification | The testing guidance had to follow existing provider test patterns instead of inventing new structures |
| `TEST-WF-*` | Workflow | How much test coverage should be added and how focused the scenario should be, including list-resource, ephemeral-resource, and provider-function patterns |
| `TEST-RUN-*` | Execution safety | Acceptance tests create real Azure resources and should be run narrowly and intentionally |
| `TEST-PATTERN-*` | Acceptance test patterns | How `ExistsInAzure`, `ImportStep()`, `requiresImport`-style coverage, and canonical helper naming for generated identity tests should be used |

## How To Use These Citations As A Reader

When a review includes rule IDs, the quickest way to read them is:

1. Identify the contract family: `REVIEW-*`, `PRDESC-*`, `DOCS-*`, `IMPL-*`, or `TEST-*`.
2. Read the area code: for example `SCOPE`, `LINT`, `ARG`, or `EX`.
3. Treat the citation as the reason the prompt applied a specific rule, not as extra output noise.

If the review feels unclear, look up the exact rule in the contract file and read the matching section heading.

## When This Matters Most

This reference is most useful when:

- A review says a specific rule was directly relevant
- You want to understand why a prompt checked something that was not obvious from the diff alone
- You want to challenge a finding and verify whether the cited contract rule really applies
- You are updating the prompts or contracts and want the output to stay understandable to end users

## Short Version

- `REVIEW-*` IDs are generic code review contract rules.
- `REVIEW-ADV-*` IDs are advocate second-pass contract rules consumed by `/review-advocate`.
- `DOCS-*` IDs are documentation review contract rules.
- `IMPL-*` IDs are Go implementation contract rules.
- `TEST-*` IDs are acceptance-testing contract rules.
- The stable authority for those IDs lives in the contract files, not in companion guides.
- The area code tells you what kind of rule is being cited.
- The IDs are there to make reviews traceable, not cryptic.
