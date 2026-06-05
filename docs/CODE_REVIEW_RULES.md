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

There are four main contract files:

- Generic code review contract: `.github/instructions/code-review-compliance-contract.instructions.md`
- Docs review contract: `.github/instructions/docs-compliance-contract.instructions.md`
- Implementation contract: `.github/instructions/implementation-compliance-contract.instructions.md`
- Testing contract: `.github/instructions/testing-compliance-contract.instructions.md`

The prompts, skills, and routing instructions consume those contracts:

- `/code-review-local-changes`
- `/code-review-committed-changes`
- `/code-review-docs`
- `/docs-writer`
- `/resource-implementation`
- `/acceptance-testing`

The important architectural point is that these contract files are now the normative rule sources.

Companion guides under `.github/instructions/` still matter, but they are primarily there to provide worked patterns, heuristics, and examples that support the contracts. If a review cites a stable rule ID such as `REVIEW-*`, `DOCS-*`, `IMPL-*`, or `TEST-*`, the authority for that citation lives in a contract file, not in a companion guide.

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
- `DOCS-ARG-001`
- `IMPL-PATCH-001`
- `TEST-PATTERN-002`

The parts mean:

- `REVIEW`, `DOCS`, `IMPL`, or `TEST`: which contract the rule came from
- `AREA`: the category of rule
- `NUMBER`: the specific rule inside that category

Some contract rules also include provenance labels to clarify where the rule came from:

- `Published upstream standard`: documented upstream
- `Inferred maintainer convention`: derived from factual maintainer review behavior
- `Local safeguard`: added by this repository to keep audits and edits deterministic

Those provenance notes matter because not every useful rule is currently written down in upstream contributor docs.

## `REVIEW-*` Rule Areas

These IDs come from `.github/instructions/code-review-compliance-contract.instructions.md` and are used by the generic code review prompts.

| Prefix | Meaning | What it usually tells the user |
| ------ | ------- | ------------------------------ |
| `REVIEW-EVID-*` | Evidence and verification | The review had to prove the claim from the diff, code, docs, or tool output instead of guessing |
| `REVIEW-CLASS-*` | Finding classification | Why something was reported as an Issue, Observation, or Strength |
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
- treat an explicit PR number as a prompt to try the direct PR-files path first
- ignore summary-only PR metadata, browser links, and forbidden spill-file paths as non-authoritative scope
- use the single allowed `gh api` fallback only after the non-CLI PR-files paths are exhausted for that same PR number

### `REVIEW-SCOPE-005`

This means the review applied Go/provider-specific guidance because the change touched:

- `internal/**/*.go`
- `internal/**/*_test.go`

It is the rule that tells the auditor to load the scoped Go instructions and skills instead of relying only on the generic review contract.

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

These rules explain how `azurerm-linter` should be handled. If you see a `REVIEW-LINT-*` citation, it usually means the review is explaining one of these:

- Whether the linter was applicable
- The simplified baseline invocation model: one filtered JSON-mode run from the repo root
- Why the linter section is `Issues found`, `No issues`, `Not applicable`, or `Not run`
- How linter findings were turned into review Issues

The contract-first model matters here too: the linter execution policy, status mapping, and output-shape requirements now live in the shared review contract, while troubleshooting and companion docs explain the runtime behavior and known failure modes around those rules.

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

1. Identify the contract family: `REVIEW-*`, `DOCS-*`, `IMPL-*`, or `TEST-*`.
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
- `DOCS-*` IDs are documentation review contract rules.
- `IMPL-*` IDs are Go implementation contract rules.
- `TEST-*` IDs are acceptance-testing contract rules.
- The stable authority for those IDs lives in the contract files, not in companion guides.
- The area code tells you what kind of rule is being cited.
- The IDs are there to make reviews traceable, not cryptic.
