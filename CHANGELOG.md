# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

### Changed

- **User-Priority:**
  - **[Review]** - Committed review now resolves PR scope from GitHub-backed review tools by default, forbids local cache or spill-file recovery, and keeps GitHub CLI fallback opt-in only instead of turning a PR number into automatic `gh` prompts.
  - **[Review]** - Committed review now stays audit-only by default: it no longer invents prerequisite scripts, runs surprise tests, or uses helper calculations for trivial deterministic checks.
  - **[Review]** - Committed review now uses GitHub-backed fetches only for PR scope resolution and relies on normal repo-local inspection for in-scope files, including targeted read-only `git diff` and `git show` commands when needed.
  - **[Review]** - Committed review now handles singleton or get-only child resources through the maintainer-reviewed no-list exception path instead of raising plain missing-list-resource findings.
  - **[Docs]** - Moved the docs-writing pre-edit and post-edit workflow into the `docs-writer` skill so `documentation-guidelines` can stay focused on companion heuristics, templates, and note-formatting reference while the existing docs review prompt remains the explicit deterministic auditor.

- **Maintainer/Workflow:**
  - **[Implementation]** - Moved the implementation-session workflow into the `resource-implementation` skill and expanded it so it now guides implementation-model selection, framework-specific companion targets, and brand-new service wiring more explicitly.
  - **[Implementation]** - Tightened implementation guidance around provider-specific edge cases, including error-format anchors, enum-pointer boundaries, and current troubleshooting patterns.
  - **[Testing]** - Moved acceptance-test execution workflow, environment prerequisites, and failure-triage guidance into the `acceptance-testing` skill so `testing-guidelines` can stay focused on test patterns while preserving the existing routed workflow.
  - **[Internal]** - Updated the `changelog-maintenance` skill so it now explicitly tells maintainers to collapse patch-history bullets into outcome-level release notes and prune overlapping `Unreleased` entries before validating the changelog.
  - **[Internal]** - Added committed-review regression cases and sanitized fixtures for the exact failures found during prompt hardening: singleton no-list false positives, local-cache PR scope misuse, non-opt-in CLI fallback, forbidden test execution, and forbidden helper-script checks.

### Fixed

## [3.3.0] - 2026-05-07

### Added

- **Maintainer/Workflow:**
  - **[Implementation]** - Added the `custom-poller-migration` runtime skill and shipped it in the installer payload so legacy polling migrations can be handled as a first-class implementation workflow instead of remaining an unwired repo-local file.
  - **[Internal]** - Added an adjudicated implementation-guidance regression case for custom poller migration routing, so legacy polling migration prompts now benchmark whether both `resource-implementation` and `custom-poller-migration` are invoked together.
  - **[Internal]** - Added a repo-only `changelog-maintenance` skill and a lightweight changelog taxonomy validator so future changelog updates can be authored and checked consistently.

### Changed

- **Maintainer/Workflow:**
  - **[Skill Routing]** - Updated the Go implementation routing and the primary `resource-implementation` skill so legacy `pluginsdk.Retry()` and `pluginsdk.StateChangeConf` migrations now consult the dedicated `custom-poller-migration` guidance alongside the shared implementation contract.
  - **[Internal]** - Updated the pull request template so `Community Note` appears first, `Description` appears before `Summary`, and `Summary` now uses a level-two heading for consistency with the rest of the template.
  - **[Internal]** - Updated the maintainer checklist and the one-shot validator so changelog taxonomy guidance is documented and `Unreleased` entries are checked for approved prefixes.

### Fixed

## [3.2.2] - 2026-05-06

### Added

- **Maintainer/Workflow:**
  - **[Internal]** - Added an adjudicated resource-implementation regression case that covers the new-resource list-resource requirement, so new resource guidance does not omit mandatory Resource Identity, list-resource planning, and the maintainer-reviewed exception path.
  - **[Internal]** - Added an adjudicated local-review regression case that covers missing new-resource companion artifacts, so code review catches missing list-resource docs and other required companion files for new resources.
  - **[Internal]** - Added adjudicated docs-review and docs-writer regression cases for list-resource pages, so the docs workflow now enforces list-resource page structure and list query examples directly instead of treating those pages like ordinary resource docs.
  - **[Internal]** - Added adjudicated docs-review and implementation-guidance regression cases for Ephemeral Resources and provider-defined Functions, so the toolkit now treats those workflows as first-class doc and implementation types instead of letting them fall through resource-only guidance.
  - **[Internal]** - Added an adjudicated implementation-guidance regression case based on a real upstream list-support retrofit PR, so the toolkit now also tests the “existing resource gains list support” workflow instead of only the brand-new resource path.
  - **[Internal]** - Added an adjudicated committed-review regression case for vendored-heavy diffs, so generic review now benchmarks count-only vendor reporting plus the explicit vendored-heavy scope callout instead of letting vendored-file handling drift.

### Changed

- **User-Priority:**
  - **[Review]** - Updated the implementation contract and the local/committed code-review prompts so new-resource reviews also validate the required documentation companion for the list resource under `website/docs/list-resources/`.
  - **[Review]** - Updated the local and committed review workflow so files under `vendor/**` are reported as a skipped vendored-file count, not a path-by-path list, and vendored-only or vendored-heavy change-sets are called out explicitly while still being treated as non-actionable review scope instead of generating findings that ask contributors to edit vendored third-party content directly.
  - **[Docs]** - Updated the docs contract, docs-writer skill, docs-review prompt, and user-facing docs so `website/docs/list-resources/*.html.markdown` pages are treated as a first-class docs type with their own title, summary, section, and example rules.
  - **[Docs]** - Updated the docs contract, docs-writer skill, docs-review prompt, implementation/testing contracts, and generic code-review prompts so `website/docs/ephemeral-resources/*.html.markdown`, `website/docs/functions/*.html.markdown`, `*_ephemeral.go`, and `internal/provider/function/*.go` all have explicit toolkit standards.

- **Maintainer/Workflow:**
  - **[Implementation]** - Updated the implementation contract, implementation skill, acceptance-testing skill, implementation guide, and user-facing examples to reflect the new upstream workflow that all new resources must plan Resource Identity and a corresponding list resource unless the maintainer exception path is explicitly used.
  - **[Implementation]** - Updated the implementation guidance so retrofitting list support onto an existing resource explicitly requires the same companion set: identity, registration, list-query tests, and list-resource docs.

### Fixed

## [3.2.1] - 2026-05-03

### Added

- **Maintainer/Workflow:**
  - **[Internal]** - Added an adjudicated committed-review regression case that covers PR-authoritative scope selection, so branch-only commits are not treated as PR findings when explicit pull request context exists.
  - **[Internal]** - Added an adjudicated committed-review regression case that covers `DOCS-DEPR-*` handling for mixed Go-plus-reference-doc PRs, so legacy non-vNext fields are not incorrectly required in live docs when migration belongs in the upgrade guide.
  - **[Internal]** - Added an adjudicated docs-review regression case that covers the resource-versus-data-source example split, so data source examples are not incorrectly forced to declare backing resources when they are demonstrating existing-object lookups.
  - **[Internal]** - Added an adjudicated committed-review regression case that covers conflicting PR context, so mismatched environment and user-supplied PR numbers fail closed unless the user explicitly requests an override.

### Changed

- **User-Priority:**
  - **[Review]** - Tightened the committed-review prompt and shared review contract so committed review now prefers authoritative pull request scope when PR context exists, falling back to `origin/main...HEAD` only when no PR context is available or the user explicitly asks for a branch-wide committed review.
  - **[Review]** - Tightened committed-review docs handling so PR-scoped mixed reviews must use GitHub PR tools for authoritative PR scope and must honor `DOCS-DEPR-*` next-major deprecation policy for `website/docs/**/*.html.markdown` files instead of treating legacy non-vNext fields as required live-doc parity.
  - **[Review]** - Tightened committed-review docs handling further so docs Issues for `website/docs/**/*.html.markdown` files now require exact supporting `DOCS-*` rule IDs; unsupported generic docs-parity claims must be demoted or omitted.
  - **[Review]** - Clarified committed-review PR scope retrieval so explicit PR numbers may resolve the authoritative changed-file set through GitHub metadata or the GitHub pull request files API without assuming `gh` is installed.
  - **[Review]** - Tightened committed-review PR resolution so conflicting environment and user-supplied PR numbers now hard-stop by default instead of silently choosing a scope.
  - **[Review]** - Updated the conflicting-PR-context hard-stop text in committed review to use the same pirate-style voice as the other prompt-owned hard-stop messages.
  - **[Docs]** - Updated the docs contract, docs-review prompt, docs-writer skill, and user-facing docs to follow the clarified upstream example standard: resource examples must be self-contained, while data source examples may assume existing objects and should not add unnecessary backing-resource scaffolding.

### Fixed

## [3.2.0] - 2026-05-02

### Added

- **Maintainer/Workflow:**
  - **[Internal]** - Added a repo-only regression-harness foundation under `tools/regression/` plus supporting docs, JSON schemas, scoring weights, and a starter five-case corpus plan so prompt, instruction, and skill behavior can move toward objective, repeatable evaluation instead of ad hoc subjective checks.
  - **[Internal]** - Added initial regression-harness utility scripts to scaffold result templates and score case results against weighted benchmark criteria, along with a synthetic adjudicated smoke case and sample result fixture.
  - **[Internal]** - Added the first sanitized adjudicated real-world regression case for resource-implementation guidance, including a neutral fixture summary and a scored example result.
  - **[Internal]** - Added the first adjudicated review-side regression case for local Go review behavior, including a sanitized fixture, a sample human-readable review output, and a scored example result.
  - **[Internal]** - Added an adjudicated docs-review regression case plus a thin example runner script so benchmark cases can be previewed and scored together from a single command.
  - **[Internal]** - Added a single-case regression run orchestrator that resolves case aliases, creates per-run directories, generates a run manifest, and scaffolds result and review artifacts under `tools/regression/runs/`.
  - **[Internal]** - Added a regression run hydrator that copies adjudicated example artifacts into a scaffolded run, plus a cleanup script for generated `tools/regression/runs/` directories.
  - **[Internal]** - Added `-Case` alias support to the example runner and expanded the regression-harness docs so the scoring weights and pass-threshold knobs are explained explicitly.
  - **[Internal]** - Added contributor-facing HCL regression test authoring under `tools/regression/test/`, including the canonical `AccTest`/`test_case`/`rules` DSL, `new-regression-test.ps1`, `build-regression-test.ps1`, and `publish-regression-test.ps1`.
  - **[Internal]** - Added regression-harness schema validation, suite scoring, history snapshotting, history summarization, and committed-review/docs-writer/acceptance-testing adjudicated example coverage.
  - **[Internal]** - Added a one-shot repo-only maintainer validator at `tools/validate-ai-toolkit.ps1` so contract validation, markdown lint, regression-harness validation, and upstream contributor drift can run through a single entry point.
  - **[Internal]** - Added tracked upstream contributor baselines for building, debugging, FAQ, high-level overview, glossary, and running-the-tests guidance so the drift checker can validate those local reference points explicitly.

### Changed

- **Maintainer/Workflow:**
  - **[Internal]** - Tightened the one-shot AI toolkit validator so changelog handling is now an explicit maintainer decision instead of a path-based heuristic: update `CHANGELOG.md`, or pass an explicit `-ChangelogNotRequired -ChangelogReason "..."` waiver when no release-note entry is warranted.
  - **[Internal]** - Tightened the regression harness around deterministic run envelopes by snapshotting per-run case and weights inputs, recording repository snapshot and capture metadata, validating run manifests against schema, and validating result artifacts before scoring.
  - **[Internal]** - Renamed the regression test implementation surface to the public `new-regression-test.ps1`, `build-regression-test.ps1`, and `publish-regression-test.ps1` entry points, removing the old `acctest`-named implementation files and documenting the stricter unreleased HCL standard directly.
  - **[Internal]** - Updated the AI toolkit alignment checklist, maintainer skill, and CI workflows to use the shared one-shot maintainer validator, including CI-specific catalog-issue tolerance via `-AllowCatalogIssues`.
  - **[Internal]** - Expanded local AI guidance to incorporate the reviewed upstream contributor topics for provider build entry points, codebase overview and terminology, provider debugging escalation, acceptance-test invocation, and contributor merge-conflict guidance.

### Fixed

- **Maintainer/Workflow:**
  - **[Internal]** - Fixed the upstream contributor drift coverage gap so all tracked and explicitly referenced upstream contributor topics now resolve cleanly with `Changed Sources: 0`, `Catalog Issues: 0`, and `Rule Issues: 0`.


## [3.1.0] - 2026-04-26

### Added

- **Maintainer/Workflow:**
  - **[Internal]** - Added [AI Toolkit Alignment Checklist](docs/AI_TOOLKIT_ALIGNMENT_CHECKLIST.md) as a repo-maintainer reference for checking contract, consumer, manifest, documentation, and release alignment.
  - **[Internal]** - Added a repo-only `ai-toolkit-maintenance` skill for maintainers working on contract, manifest, checklist, changelog, and validation alignment in this repository.
  - **[Internal]** - Added a repo-only upstream contributor source map and drift-check script so local AI guidance can be reviewed against tracked HashiCorp contributor docs under `contributing/topics/` without shipping that maintenance tooling in the installer bundle.

### Changed

- **Maintainer/Workflow:**
  - **[Implementation]** - Clarified the error-patterns guide so static errors use `errors.New(...)`, while wrapped provider-facing errors explicitly prefer `%+v` over `%v`, `%s`, and `%w`.
  - **[Implementation]** - Tightened implementation-side error guidance so static errors use `errors.New(...)`, while `fmt.Errorf(...)` with `%+v` remains reserved for formatted messages and wrapped underlying errors.
  - **[Implementation]** - Added an implementation-side parser-error rule that says comprehensive resource ID parser errors should usually be returned directly instead of being wrapped with redundant parsing or flattening context.
  - **[Implementation]** - Added an implementation-side validation rule that treats generic fallback validators such as `validation.StringIsNotEmpty` and `validation.IntAtLeast(...)` as last-resort choices when stronger evidence-backed validation is available.
  - **[Implementation]** - Added an implementation-side enum-validation rule that prefers SDK `PossibleValuesFor...` helpers when they match the real accepted values, while allowing evidence-backed narrowing when a resource accepts only a subset.
  - **[Testing]** - Added selective provenance and evidence notes to the stricter lifecycle-coverage rules in the testing compliance contract so the most debatable `TEST-*` expectations are easier to justify and maintain.
  - **[Testing]** - Added a testing-contract rule, with inferred-maintainer-convention provenance, that simple property validation should usually stay in unit tests rather than being re-proven with acceptance tests.
  - **[Testing]** - Added a testing-contract rule, with provenance, that CustomizeDiff validation logic should receive targeted acceptance-test coverage so cross-field validation behavior is not left untested.
  - **[Testing]** - Replaced ordered lists in the `acceptance-testing` skill with flat bullets and clarified the maintainer checklist that CI/CD validation is sensitive to numbered-list formatting in AI-toolkit files.
  - **[Testing]** - Aligned the local acceptance-testing guidance with upstream HashiCorp contributor docs by restoring `requiresImport` as part of the default resource test matrix instead of treating it as merely conditional.
  - **[Internal]** - Tightened the AI toolkit alignment checklist so it now prescribes the standard authoring pattern for skills, prompts, and instructions: titled subsections plus bullets, with `MD029` history documented as the reason to avoid fragile ordered-list structures.
  - **[Internal]** - Extended the AI toolkit alignment checklist with explicit usage guidance for the repo-only `ai-toolkit-maintenance` skill so maintainers can invoke the alignment workflow directly.
  - **[Internal]** - Added a maintainer note to the AI toolkit alignment checklist that stale VS Code YAML diagnostics can persist after a fix, with a reload-window recovery step when file contents and workspace validators are already clean.
  - **[Internal]** - Updated the repo-only AI maintenance workflow so it tracks selected upstream HashiCorp contributor docs as review sources and checks for upstream drift before local rules are treated as current.
  - **[Internal]** - Extended the upstream contributor drift checker so it can report mapped local rule IDs, current provenance labels, and evidence blocks for provenance-backed rules instead of only reporting file-level drift.
  - **[Internal]** - Clarified that the upstream contributor drift checker is a deterministic detector rather than an AI semantic comparer, and updated the maintainer workflow to require AI-assisted semantic review after drift is detected.
  - **[Internal]** - Fixed a catalog-coverage blind spot by teaching the upstream drift checker to compare the live upstream contributor topic index against the manifest, so added, removed, renamed, merged, or newly untracked topic docs are reported explicitly.
  - **[Internal]** - Replaced the remaining hard-coded topic-policy and local rule-mapping model with dynamic explicit-reference discovery, so tracked-source baselines stay in the manifest while local topic-to-file and topic-to-rule relationships are derived only from exact upstream topic references already present in repo content.
  - **[Internal]** - Tightened that dynamic model further so the drift checker now treats heuristics as forbidden and only derives mappings from exact upstream-topic references and exact rule-evidence references already present in repository content.
  - **[Internal]** - Clarified the two-phase workflow so exact-reference aggregation only proves already-explicit local links, while uncovered, changed, renamed, or merged upstream docs still require AI semantic matching review after the deterministic drift pass.
  - **[Internal]** - Canonicalized local contributor-doc references against the remote HashiCorp contributor tree at `https://github.com/hashicorp/terraform-provider-azurerm/tree/main/contributing`, so the installer repo compares local guidance to the target repo's remote contributor-doc structure rather than to a fake local mirror.
  - **[Internal]** - Expanded the tracked upstream contributor source set to include API versioning, breaking changes, list resources, feature-block changes, resource and data source extensions, service packages, write-only attributes, resource identity, resource IDs, state migrations, and property naming guidance.
  - **[Internal]** - Expanded the local companion guidance to cover preview API exceptions, feature-block updates, list resources, service package scaffolding, resource ID precedence, inline-versus-resource decisions, resource identity, write-only attributes, state migration workflow, and upstream naming rules.
  - **[Internal]** - Clarified the repo-only `ai-toolkit-maintenance` skill so upstream drift checking is a first-class required step whenever upstream contributor alignment is in scope or the user asks whether the AI toolkit is up to date.
  - **[Internal]** - Moved the repo-only upstream contributor baseline file from `.github/upstream-contributor-alignment.json` to `tools/config/upstream-contributor.json` so the configuration lives with maintenance tooling support files rather than under `.github/`.
  - **[Internal]** - Backfilled additional rule-level provenance coverage so the upstream drift checker now reaches selected docs and implementation contract rules, not just the testing contract.
  - **[Internal]** - Added provenance-backed rule anchors to the Azure-patterns guide, schema-patterns guide, and repo-only maintainer skill so upstream source links now reach companion guidance and maintainer workflow rules as well as contracts.
  - **[Internal]** - Extended the drift checker JSON output to group mapped rules and rule issues by local file, making provenance review easier contract-by-contract and guide-by-guide.
  - **[Internal]** - Increased the review-time azurerm-linter timeout guidance to `300000` ms and clarified that review runs should keep following a timed-out-but-still-running linter session to completion instead of classifying it as `Not run` too early.
  - **[Internal]** - Replaced the remaining ordered-list sequences in the error-patterns guide with the standard title-plus-bullets pattern so the changed AI-toolkit guidance is structurally consistent.

### Fixed

## [3.0.2] - 2026-04-23

### Added

- **User-Priority:**
  - **[Review]** - Added [Code Review Rule Reference](docs/CODE_REVIEW_RULES.md) so end users can decode `REVIEW-*`, `DOCS-*`, `IMPL-*`, and `TEST-*` citations used by the review prompts, skills, and contracts.

- **Maintainer/Workflow:**
  - **[Implementation]** - Added an initial implementation compliance contract for `internal/**/*.go` so Go implementation work can use a real contract layer instead of relying on the `resource-implementation` skill as the sole authority.
  - **[Testing]** - Added a dedicated testing compliance contract for `internal/**/*_test.go` so acceptance-test work can use a real contract layer instead of relying on the `acceptance-testing` skill as the sole authority.
  - **[Internal]** - Added a cross-platform PowerShell contract validator plus a dedicated GitHub Actions workflow that discovers contract instruction files, validates their structure and provenance metadata, and reports prompt/skill/companion consumers from the repository itself.

### Changed

- **User-Priority:**
  - **[Review]** - Updated the `azurerm-linter` review flow and related documentation so JSON parsing is treated as stdout-only, stderr is suppressed using the native null-device syntax for the active shell on each OS, and the prompts rerun once without suppression when diagnostic output is needed to classify non-JSON results.
  - **[Docs]** - Added an explicit docs wording rule that treats `Resource Group` as canonical Azure object capitalization in field prose, with provenance recorded as an inferred maintainer convention backed by PR review evidence.
  - **[Docs]** - Introduced an incremental provenance model in the docs contract so ambiguous rules can be labeled as published upstream standards, inferred maintainer conventions, or local safeguards, and backfilled that metadata onto an initial set of docs rules.
  - **[Docs]** - Continued the docs-contract provenance backfill across example and block-structure rules that exist primarily as repository safeguards for deterministic docs audits and rewrites.

- **Maintainer/Workflow:**
  - **[Implementation]** - Updated the `resource-implementation` skill and Go routing instruction so they now consume the new implementation compliance contract as the authoritative implementation layer.
  - **[Implementation]** - Refactored the main implementation guide into explicit companion guidance for the implementation contract and taught the contract validator to discover companion instruction files from the implementation contract's dedicated companion-guidance section.
  - **[Implementation]** - Refactored the remaining implementation companion guides so they explicitly point back to the implementation compliance contract as the authoritative layer.
  - **[Testing]** - Tightened acceptance-test review guidance so embedded Terraform inside `internal/**/*_test.go` raw strings must be checked against `terrafmt`-style formatting, including flagging tab-indented Terraform blocks instead of assuming `azurerm-linter` will catch those issues.
  - **[Testing]** - Updated the `acceptance-testing` skill, test routing instruction, and testing guide so they now consume the new testing compliance contract as the authoritative testing layer.
  - **[Testing]** - Removed the testing guide from the implementation companion set so test authority is no longer split between the implementation and testing contract models.
  - **[Internal]** - Tightened the contract validator so it now verifies declared consumer paths from each contract's `## Consumers` section and requires a terminal contract EOF marker comment as the last non-empty line.
  - **[Internal]** - Standardized contract `## Consumers` sections on an explicit `Consumer:` bullet format and tightened the validator so contract-listed companion instruction files must point back to their contract.
  - **[Internal]** - Added explicit per-consumer `Requires EOF Load: yes` metadata to the current contracts and tightened the validator so declared prompt and skill consumers marked that way must mention loading the contract to EOF.

## [3.0.1] - 2026-04-16

### Changed

- **User-Priority:**
  - **[Review]** - Updated the generic local and committed review prompts plus the shared review contract to prefer [`azurerm-linter`](https://github.com/QixiaLu/azurerm-linter) JSON output, report the linter version in the review output, and require [`azurerm-linter v0.2.0`](https://github.com/QixiaLu/azurerm-linter/releases/tag/v0.2.0) or newer for JSON-mode review.
  - **[Review]** - Clarified the workspace terminal guidance so [`azurerm-linter`](https://github.com/QixiaLu/azurerm-linter) is treated as a standalone local CLI instead of a Go toolchain command, and hardened the review prompts/contract to require native local linter execution from the repo root instead of WSL-prefixed or cross-shell-wrapped invocations.
  - **[Review]** - Updated the review prompt output guidance so normalized `### 🎯 **MUST FIX**` linter findings prefer compact Markdown file links like `CHECKID [file:line](repo/relative/path#Lline): message` when deterministic repo-relative paths are available, matching the clickable file-reference style used elsewhere in the review.
  - **[Review]** - Tightened the fresh-run review rules so repeated code-review invocations must describe only current-run evidence, with no carry-over wording or execution-progress narration before the final review headings.
  - **[Review]** - Tightened the fresh-run review rules so successful reruns must emit the full current review template even when the reviewed diff and findings are unchanged, instead of short-circuiting to prior review text or delta-only summaries.

### Fixed

- **User-Priority:**
  - **[Review]** - Fixed installed review behavior in `terraform-provider-azurerm` workspaces by discovering repo-level contributor guidance from common target-repo paths, forcing fresh review reruns instead of reusing prior review state, hard-stopping with deterministic fresh-run failure messages, suppressing narrated post-linter verification steps, and rendering azurerm-linter findings in a dedicated `### 🎯 **MUST FIX**` section instead of malformed inline list output.

## [3.0.0] - 2026-04-13

### Added

- **User-Priority:**
  - **[Review]** - Added a dedicated `azurerm-linter` execution/reporting capability to the generic local and committed review prompts, with explicit `Issues found` / `No issues` / `Not applicable` / `Not run` status reporting and a shared compliance contract to keep the flow deterministic.
  - **[Review]** - Added committed-review and local-review linter flow support around repo-root resolution, direct filtered execution, PR-scoped committed review, explicit run-scope reporting, and reviewer-facing linter output fields.
  - **[Review]** - Added explicit `azurerm-linter` handling for no-work results, flag/usage parse errors, slow executions, missing local installs, and PR-number discovery failures so the review prompts classify results deterministically instead of silently skipping or misreporting the tool.
  - **[Review]** - Added structured `azurerm-linter` issue surfacing rules so findings appear both in the dedicated linter execution subsection and in the main review `ISSUES` section.
  - **[Review]** - Added linter-specific prompt/contract guidance for command authorization, immediate execution, repo-root resolution via `git rev-parse --show-toplevel`, longer sync timeouts, and local-install-only expectations.
  - **[Review]** - Added a narrow VS Code user-setting override example for auto-approving the harmless repo-root lookup command used by the linter flow.
  - **[Review]** - Added deterministic committed-review PR-number discovery rules and explicit rerun guidance such as `/code-review-committed-changes PR 12345` when the linter cannot determine PR context automatically.
  - **[Review]** - Added release-note/documentation caveats that the prompt-side `azurerm-linter` flow assumes a recent upstream `azurerm-linter` binary, with the current dependency called out explicitly as [QixiaLu/azurerm-linter#50](https://github.com/QixiaLu/azurerm-linter/pull/50), so behavior may differ until the corresponding upstream changes are merged and installed locally.
  - **[Installer]** - Added GitHub artifact attestations to the installer release workflow and documented how users should verify official pinned release assets with `gh attestation verify`, introducing a provenance-based release trust model alongside the existing checksum-based integrity checks.
  - **[Installer]** - Added explicit documentation for the expected successful attestation verification pattern, including the normal case where multiple matching attestations appear because the stable-name and versioned release assets share the same digest.
  - **[Installer]** - Added explicit PowerShell and Bash `gh attestation verify` examples that show the correct stable-name archive path to verify for each shell.
  - **[Installer]** - Added explicit end-user guidance that `gh attestation verify` must be run against the downloaded release archive with GitHub CLI authenticated to `github.com`, including recovery steps for the common `HTTP 401: Bad credentials` failure mode.

### Changed

- **User-Priority:**
  - **[Review]** - Tightened the shared code review contract with explicit file-type coverage rules so local and committed reviews continue to check installer cross-platform drift, prompt/instruction/skill determinism and alignment, manifest consistency, and user-visible text quality instead of only applying generic evidence rules.
  - **[Review]** - Taught the generic local and committed review flows to defer `website/docs/**/*.html.markdown` compliance to the shared docs compliance contract, so mixed code-and-docs reviews can cite `DOCS-*` rules without importing docs-writer footer behavior into the generic review prompts.
  - **[Docs]** - Tightened the docs compliance contract so data source arguments, attributes, and nested fields must stay short and only explain what the field is, without field-level note blocks; aligned `.github/instructions/documentation-guidelines.instructions.md`, `.github/skills/docs-writer/SKILL.md`, and `.github/prompts/code-review-docs.prompt.md` to enforce the same rule consistently.
  - **[Installer]** - Fixed installer packaging by adding `.github/instructions/code-review-compliance-contract.instructions.md` to `installer/file-manifest.config`, ensuring bootstrap and installed payloads include the shared review contract required by the updated code review prompts.
  - **[Installer]** - Clarified the installer trust model in the docs: attestations and checksums protect artifact provenance and integrity only when users verify against the canonical pinned repository/workflow identity, and they do not remove the need for users to trust the real canonical repo as their starting point.
  - **[Installer]** - Promoted the installer trust-model guidance into a visible README installation section so users see the canonical repo/workflow trust boundary before the download and extraction commands.
  - **[Installer]** - Hardened the PowerShell validation workflows so they install `PSScriptAnalyzer` through a cross-platform repository bootstrap path that prefers `Install-PSResource`/`PSGallery` and falls back to `Install-Module`, avoiding runner-specific failures when the legacy NuGet package-provider bootstrap is unavailable.

### Fixed

- **User-Priority:**
  - **[Review]** - Fixed a regression where `/code-review-docs` could miss conditional requirements that should be documented as `~> **Note:**` blocks (from schema cross-field constraints and diff-time validation), by making extraction and coverage reporting non-optional.
  - **[Installer]** - When running the installer directly from a git clone with placeholder `installer/VERSION` (`0.0.0`), the displayed version now matches bootstrap-stamped versions (`dev-<git sha>` with optional `-dirty`).
  - **[Installer]** - Installer installs no longer require internet connectivity (offline payload by default).
  - **[Installer]** - Clarified bootstrap summary labels to distinguish installer files vs payload files (PowerShell and Bash).
  - **[Installer]** - Removed unused installer helpers/exports in PowerShell and Bash modules to reduce dead code.
  - **[Installer]** - Installer summaries now include `Source`, `Manifest`, and `Command` details to make it explicit which files were attempted from which location/ref.
  - **[Installer]** - Release bundles and bootstrapped installs now include an offline payload (`aii/`) so installs do not fetch AI files from GitHub.
  - **[Installer]** - Bash repository validation for `-repo-directory` now requires the terraform-provider-azurerm `go.mod` module declaration (reduces false positives from substring matches).
  - **[Installer]** - `-verify` is offline-only and no longer depends on GitHub connectivity or remote manifest validation.
  - **[Installer]** - Unified PowerShell/Bash early validation and error output to reduce cross-platform drift (for example, `-RepoDirectory` / `-repo-directory` now fails fast when the target path does not exist).

## [2.0.8] - 2026-03-26

### Fixed

- **User-Priority:**
  - **[Docs]** - Aligned the shared docs compliance contract and companion documentation guidance with HashiCorp's preferred `*_enabled` wording so both resources and data sources use statement phrasing (`Whether ... is enabled.`), with resource docs keeping a separate `Defaults to ...` sentence when applicable; clarified that data source summary-sentence restrictions are separate from Attributes Reference wording restrictions; and tightened argument guidance so core semantics like `Possible values are ...` and `Defaults to ...` stay in the bullet by default instead of being pushed into notes.

## [2.0.7] - 2026-03-18

### Changed

- **User-Priority:**
  - **[Docs]** - Tightened the shared docs compliance contract so it is the authoritative compliance layer for docs work, added explicit rules to cover the upstream contributor documentation standards (including frontmatter placement/content, doc path naming, summary sentence placement, and `hcl` code-fence requirements), and refactored `.github/instructions/documentation-guidelines.instructions.md` into companion guidance that points back to the contract instead of duplicating normative rules.

## [2.0.6] - 2026-03-16

### Changed

- **User-Priority:**
  - **[Docs]** - Tightened the shared docs compliance contract with deterministic rules for intra-section block reference direction (`as defined above` vs `as defined below`), mandatory block subsection separators in `Arguments Reference` and `Attributes Reference`, and canonical resource-name usage in resource `Attributes Reference`, `Timeouts`, and `Import` prose.

### Fixed

- **Maintainer/Workflow:**
  - **[Internal]** - Fixed flaky macOS PowerShell validation in CI by using the hosted runner's existing `pwsh` when available, falling back to Homebrew installation only when PowerShell is missing.

## [2.0.5] - 2026-03-09

### Changed

- **User-Priority:**
  - **[Review]** - Hardened `/code-review-docs` determinism rules to avoid run-to-run "guessing" (no A/B options; patch-ready snippets must be fully specified).
  - **[Review]** - Prevented duplicated `/code-review-docs` headings by requiring atomic output buffering (assemble the full 9-heading review internally, then emit once).
  - **[Review]** - Clarified scaffolding usage: docs scaffolding is a writer workflow (skill) for brand-new docs pages or explicit scaffold/dry-run requests; `/code-review-docs` remains audit-only.
  - **[Review]** - Prohibited `/code-review-docs` from suggesting or invoking repo tooling (scaffold/validators/linters); audits are derived from static workspace evidence only.
  - **[Review]** - Updated `/code-review-local-changes` and `/code-review-committed-changes` to flag string enum boolean toggles (`Enabled`/`Disabled`, `On`/`Off`, with optional `None` tri-state) and prefer boolean `*_enabled` for new schema surface area; added matching guidance to schema patterns.
  - **[Docs]** - Expanded `/code-review-docs` docs-quality checks (timeouts readability, import example ID shape validation, `hcl` code fences, and page-self-contained example reference scans).
  - **[Docs]** - Moved docs compliance rules into a shared docs compliance contract and refactored `/code-review-docs` + `/docs-writer` to reference stable `DOCS-*` IDs instead of duplicating large rule blocks.
  - **[Docs]** - Added new hard-compliance docs contract rules for note de-duplication, argument bullet length caps, net-new `depends_on` restrictions, and legacy (non-vNext) field exclusion (`DOCS-NOTE-008`, `DOCS-ARG-011`, `DOCS-EX-017`, `DOCS-DEPR-002`).
  - **[Docs]** - Aligned `/docs-writer` with `/code-review-docs` by adding concrete evidence-extraction procedures for `CustomizeDiff` call-chain tracing and Importer/ID-shape derivation (follow parser → ID type → formatter; do not guess without evidence).
  - **[Docs]** - Updated `/code-review-docs` and `/docs-writer` guidance to consistently treat next-major deprecations as vNext surface area (do not require legacy fields for docs parity).
  - **[Docs]** - Standardized example naming guidance: name-like values should use `example-`/`existing-` prefixes where feasible (nit-level), and recommend deterministic type-derived names when schema/`ValidateFunc` evidence proves the derived value is valid.
  - **[Docs]** - Aligned `.github/instructions/documentation-guidelines.instructions.md` with the shared docs contract to avoid conflicting precedence/examples.

### Fixed

- **User-Priority:**
  - **[Review]** - Fixed repeated audit findings by requiring `/code-review-docs` to emit fully patch-ready ordering fixes (including full corrected nested block snippets) and a self-check mapping each Issue to a specific snippet.
  - **[Docs]** - Fixed a docs regression where "Example ..." sections could be converted to prose to satisfy self-containment, leading to inconsistent outcomes. Example sections now remain copy/pasteable Terraform and fixes expand examples to be page-self-contained.
  - **[Docs]** - Fixed common doc-quality regressions by enforcing canonical enum phrasing and mandatory legacy-phrase rewrites (for example `Valid values are` -> `Possible values are`) and treating example naming conventions as patch-ready low-priority nits.
  - **[Docs]** - Fixed `/docs-writer` enum wording guidance to match the shared docs compliance contract (`DOCS-WORD-002`).
  - **[Docs]** - Fixed docs security guidance so hard-coded secrets in examples are flagged and replaced with context-appropriate `var.<name>` references (variable block optional).

## [2.0.4] - 2026-02-24

### Fixed

- **User-Priority:**
  - **[Installer]** - Fixed Bash installer bundle checksum verification to hash the manifest+payload listing bytes directly (preserves the trailing newline), matching the release and PowerShell implementations. This prevents checksum mismatches on Linux/WSL.

## [2.0.3] - 2026-02-24

### Fixed

- **User-Priority:**
  - **[Installer]** - Fixed installer bundle checksum validation on non-Windows PowerShell by including hidden dot-directories (for example `.github/`, `.vscode/`) when computing the payload hash. This prevents false checksum mismatches in release verification.

## [2.0.2] - 2026-02-24

### Fixed

- **User-Priority:**
  - **[Installer]** - Fixed release bundle generation so `aii.checksum` is computed from the exact bytes being validated (preserves the trailing newline in the hashed manifest+payload listing). This prevents installer payload checksum validation failures when running from extracted release bundles.

## [2.0.1] - 2026-02-24

### Fixed

- **User-Priority:**
  - **[Installer]** - Fixed a checksum validation regression on Windows where release bundles stamped on Linux/macOS could fail `aii.checksum` verification due to PowerShell/Bash algorithm drift (PowerShell checksum computation now matches the Bash implementation).

## [2.0.0] - 2026-02-24

### Added

- **Maintainer/Workflow:**
  - **[Internal]** - Added a GitHub pull request template at `.github/pull_request_template.md` to standardize PR titles, scope, testing, changelog updates, and AI assistance disclosure.

### Changed

- **User-Priority:**
  - **[Review]** - Renamed the docs prompt `/docs-schema-audit` (file: `.github/prompts/docs-schema-audit.prompt.md`) to `/code-review-docs` (file: `.github/prompts/code-review-docs.prompt.md`) to group review prompts consistently.
  - **[Review]** - Updated `/code-review-docs` to explicitly extract and report cross-field constraints from both the Terraform schema (for example `ConflictsWith`, `ExactlyOneOf`) and diff-time validation (`CustomizeDiff`).
  - **[Review]** - Updated `/code-review-docs` to also extract and report implicit behavior constraints from expand/flatten logic (for example feature enablement toggled by block presence, or hardcoded API values not exposed in schema).
  - **[Review]** - Updated `/code-review-docs` output to include a "required notes coverage" checklist and to require explicit reporting of detected notes and conditional constraints (or an explicit "none found").
  - **[Review]** - Updated `/code-review-docs` to validate note content for correctness (notes describing constraints must match the extracted schema/diff-time/implicit behavior rules).
  - **[Docs]** - Strengthened `/code-review-docs` and `/docs-writer` instructions so full parity/ordering/notes checks run even when the user provides minimal prompts.
  - **[Docs]** - Aligned `## Arguments Reference` ordering rules in `/code-review-docs` with provider standards (`name`, `resource_group_name`, `location`, then required alphabetical, then optional alphabetical, `tags` last).
  - **[Docs]** - Clarified `## Attributes Reference` ordering to be strictly `id` first, then remaining attributes alphabetical (no special-casing `tags`, `name`, `resource_group_name`, or `location`).
  - **[Docs]** - Updated `/docs-writer` to automatically add missing `~> **Note:**` blocks for schema and `CustomizeDiff` conditional requirements when updating docs.
  - **[Docs]** - Standardized `ForceNew` argument wording to use the generic sentence: `Changing this forces a new resource to be created.`.
  - **[Installer]** - **BREAKING**: this release intentionally does not provide backward compatibility for renamed commands/behavior.
  - **[Installer]** - **BREAKING**: simplified installer CLI:
    - Removed `-Contributor` / `-contributor`
    - Removed `-Branch` / `-branch`
    - `-LocalPath` / `-local-path` is now the only source override (default source is bundled payload `aii/`)
  - **[Installer]** - Set `installer/VERSION` to `0.0.0` to make it clear that it is a placeholder for source checkouts (release bundles are stamped from the tag).
  - **[Installer]** - `-Bootstrap` / `-bootstrap` is now a standalone command (no other parameters accepted) and must be run from a git clone (repo root contains `.git`). Official installation is via the release bundle.
  - **[Installer]** - Bash installer no longer references legacy AzureRM-provider repo layouts/branches (removed `exp/terraform_copilot` and `.github/AIinstaller` fallbacks); bootstrap guidance now consistently points to `./installer/install-copilot-setup.sh`.
  - **[Installer]** - Standardized installer help/examples to refer to the terraform-provider-azurerm working copy directory (rather than legacy "feature branch directory" phrasing) and removed incorrect guidance that bootstrap must run from `main`.
  - **[Installer]** - Installer help output (`-Help` / `-help`) now consistently describes `-RepoDirectory` / `-repo-directory` as pointing to a terraform-provider-azurerm working copy, and avoids showing "attempted command" notes when the user explicitly requests help.
  - **[Installer]** - Removed `-Dry-Run` / `-dry-run` from the installer to keep the workflow focused on install/clean/verify.
  - **[Installer]** - Removed legacy remote download scaffolding; installs now copy from the bundled payload or `-LocalPath` only.
  - **[Installer]** - Installer now validates a bundled payload checksum on install/verify to prevent mixed-state runs; bootstrap and release bundles generate `aii.checksum`.
  - **[Installer]** - `-Verify` / `-verify` now has two modes:
    - Without `-RepoDirectory` / `-repo-directory` (typically from the user-profile installer directory), it performs an **installer bundle self-check** (manifest/modules/payload/checksum).
    - With `-RepoDirectory` / `-repo-directory`, it verifies AI infrastructure presence in the **target repository**.
  - **[Installer]** - `-Verify -RepoDirectory` (and the equivalent Bash form) now hard-fails if the repo directory points at the installer source repository, to prevent false-positive verification.

- **Maintainer/Workflow:**
  - **[Skill Routing]** - Renamed the Agent Skills slash commands to remove the `azurerm-` prefix: `/azurerm-docs-writer`, `/azurerm-resource-implementation`, and `/azurerm-acceptance-testing` are now `/docs-writer`, `/resource-implementation`, and `/acceptance-testing`.
  - **[Internal]** - Expanded `CONTRIBUTING.md` to provide more detailed contribution and validation guidance, including PowerShell/Bash parity expectations to avoid installer drift.

### Upgrade Notes (from 1.x)
- `-Contributor` / `-contributor`, `-Branch` / `-branch`, and `-Dry-Run` / `-dry-run` were removed.
  - To test local/uncommitted AI changes or install offline, use `-LocalPath` / `-local-path`.
  - Default source is the bundled offline payload (`aii/`) shipped with the release/bootstrapped installer.
- `-Bootstrap` / `-bootstrap` is now standalone (no extra flags). Previous usage like `-Bootstrap -Contributor` becomes just `-Bootstrap`.
- Installs still target a terraform-provider-azurerm working copy via `-RepoDirectory` / `-repo-directory` (validated via `go.mod` module identity and repo structure).

### Fixed

- **User-Priority:**
  - **[Review]** - Fixed a regression where `/code-review-docs` could miss conditional requirements that should be documented as `~> **Note:**` blocks (from schema cross-field constraints and diff-time validation), by making extraction and coverage reporting non-optional.
  - **[Installer]** - When running the installer directly from a git clone with placeholder `installer/VERSION` (`0.0.0`), the displayed version now matches bootstrap-stamped versions (`dev-<git sha>` with optional `-dirty`).
  - **[Installer]** - Installer installs no longer require internet connectivity (offline payload by default).
  - **[Installer]** - Clarified bootstrap summary labels to distinguish installer files vs payload files (PowerShell and Bash).
  - **[Installer]** - Removed unused installer helpers/exports in PowerShell and Bash modules to reduce dead code.
  - **[Installer]** - Installer summaries now include `Source`, `Manifest`, and `Command` details to make it explicit which files were attempted from which location/ref.
  - **[Installer]** - Release bundles and bootstrapped installs now include an offline payload (`aii/`) so installs do not fetch AI files from GitHub.
  - **[Installer]** - Bash repository validation for `-repo-directory` now requires the terraform-provider-azurerm `go.mod` module declaration (reduces false positives from substring matches).
  - **[Installer]** - `-verify` is offline-only and no longer depends on GitHub connectivity or remote manifest validation.
  - **[Installer]** - Unified PowerShell/Bash early validation and error output to reduce cross-platform drift (for example, `-RepoDirectory` / `-repo-directory` now fails fast when the target path does not exist).

## [1.0.5] - 2026-02-18

### Fixed

- **User-Priority:**
  - **[Installer]** - Release bundles now set executable permissions on the bundled Bash installer scripts (with a `chmod +x` fallback note for environments that drop execute bits).

## [1.0.4] - 2026-02-18

### Changed

- **User-Priority:**
  - **[Docs]** - Updated the `.github/prompts/docs-review.prompt.md` prompt to reflect proposed upstream contributor documentation standards (based on [hashicorp/terraform-provider-azurerm PR #31772](https://github.com/hashicorp/terraform-provider-azurerm/pull/31772)) for nested block field ordering (arguments and attributes) and ForceNew wording guidance.
  - **[Docs]** - Updated the `/docs-writer` skill to enforce nested block field ordering and align ForceNew wording guidance (legacy vs descriptive phrasing), while keeping the skill under the 500-line limit.
  - **[Docs]** - Removed empty `##` spacer headings from README files to avoid bogus headings and keep GitHub Markdown rendering consistent.
  - **[Installer]** - Centralized the installer version into `installer/VERSION` (PowerShell + Bash now read from that file) and updated the release workflow to write the tagged version into the bundled installer.
  - **[Installer]** - Updated `-Bootstrap` to stamp a contributor-friendly version in the user profile installer (`dev-<git sha>` with optional `-dirty`) to clearly indicate a local, bootstrapped build.

## [1.0.3] - 2026-02-17

### Changed

- **User-Priority:**
  - **[Docs]** - Clarified the `/docs-writer` skill final checklist to explicitly restate canonical `## Arguments Reference` argument ordering.
  - **[Docs]** - Audited and clarified the `/docs-writer` skill instructions to remove duplicated/contradictory rules and improve example clarity.
  - **[Docs]** - GitHub Release notes now correctly include the version-specific `CHANGELOG.md` section (previously blank due to extraction logic).
  - **[Docs]** - Standardized GitHub Release notes headings to plain text (removed emojis).

## [1.0.2] - 2026-02-15

### Added

- **User-Priority:**
  - **[Installer]** - Agent Skill files under `.github/skills/` (for example `/docs-writer`) are now distributed by the installer.

### Changed

- **User-Priority:**
  - **[Installer]** - Installer now installs, verifies, and cleans `.github/skills` alongside instructions and prompts, including automated deprecation removal based on the manifest.

- **Maintainer/Workflow:**
  - **[Internal]** - CI markdownlint configuration now disables `MD007` (unordered list indentation) to avoid false positives with HashiCorp-style indentation.

### Fixed

- **User-Priority:**
  - **[Docs]** - Fixed markdownlint failures in `.github/skills/docs-writer/SKILL.md` (for example `MD029` ordered list numbering).

## [1.0.1] - 2026-02-12

### Added

- **User-Priority:**
  - **[Review]** - New optional documentation audit prompt:
    - `.github/prompts/docs-review.prompt.md`
  - **[Installer]** - Release assets with stable (unversioned) filenames to support `releases/latest/download/*` install URLs:
    - `terraform-azurerm-ai-installer.zip`
    - `terraform-azurerm-ai-installer.tar.gz`

### Changed

- **User-Priority:**
  - **[Installer]** - Documentation now clearly distinguishes installing the latest release (`releases/latest/download/...`) from pinning a specific version (`releases/download/vX.Y.Z/...`)

## [1.0.0] - 2025-10-22

### Added

- **User-Priority:**
  - **[Review]** - Code review prompts for local and committed changes
  - **[Docs]** - Release documentation and procedures (RELEASING.md)
  - **[Installer]** - Initial public release of the Terraform AzureRM AI-Assisted Development toolkit
  - **[Installer]** - Cross-platform installer (PowerShell and Bash)
  - **[Installer]** - VS Code integration and configuration
  - **[Installer]** - Bootstrap mode for automatic detection of terraform-provider-azurerm repository
  - **[Installer]** - **Contributor mode** (`-Contributor`/`-contributor`) for working with local AI dev repo changes before pushing
  - **[Installer]** - **Local source path** (`-LocalPath`/`-local-path`) parameter for testing uncommitted changes from local AI dev repository
  - **[Installer]** - **Repository directory** (`-RepoDirectory`/`-repo-directory`) parameter requirement when running from user profile for proper git repository detection

- **Maintainer/Workflow:**
  - **[Implementation]** - Comprehensive Copilot instructions for Terraform AzureRM Provider development
  - **[Implementation]** - 12+ instruction modules covering Azure patterns, testing, security, and more
  - **[Internal]** - Release process automation with GitHub Actions workflow

### Changed

- **User-Priority:**
  - **[Docs]** - Updated README structure with improved section breaks and readability
  - **[Docs]** - **Parameter documentation**: Significantly improved descriptions for `-Contributor`/`-contributor` and `-LocalPath`/`-local-path` parameters
  - **[Docs]** - **User experience**: Updated all documentation to clearly distinguish between normal user workflow (download release package) and contributor workflow (bootstrap from local clone)
  - **[Installer]** - Improved installer validation messages for better clarity and user feedback
  - **[Installer]** - Enhanced error handling in validation engine with consolidated error functions
  - **[Installer]** - Refactored installer scripts for better maintainability with region-based organization
  - **[Installer]** - **Installation workflow**: Clarified two-step process (download/extract → install) for normal users vs bootstrap workflow for contributors
  - **[Installer]** - **Version control**: Centralized version management with single update point (`$script:InstallerVersion` in PowerShell, `INSTALLER_VERSION` in Bash)
  - **[Installer]** - **Installation source clarity**: Updated messages to clearly show source (GitHub branch, local path) and action (Installing, Downloading)
  - **[Installer]** - **Help system**: Context-aware help display based on execution location (source branch vs user profile)
  - **[Installer]** - **Help completeness**: Added all contributor options to help display with explicit requirement indicators
  - **[Installer]** - **Validation improvements**:
    - Consolidated 5 error types into reusable `Show-EarlyValidationError` function (PowerShell) and `show_early_validation_error` (Bash)
    - Early validation for empty and non-existent `-LocalPath`/`-local-path` parameters
    - Fail-fast architecture with consistent error formatting
  - **[Installer]** - **Output formatting**: Consistent spacing between output sections across all UI functions
  - **[Installer]** - **Bootstrap reliability**: Fixed branch detection to use current git branch instead of defaulting to empty string
  - **[Installer]** - **Bash color support**: Moved color definitions before module loading for proper error message display

- **Maintainer/Workflow:**
  - **[Implementation]** - Reorganized instruction files to .github/instructions directory
  - **[Internal]** - Enhanced markdownlint configuration for better documentation quality

### Fixed

- **User-Priority:**
  - **[Installer]** - ShellCheck exclusions for bash scripts to prevent false positives
  - **[Installer]** - Markdownlint configuration compatibility with cli2
  - **[Installer]** - Validation workflow to properly skip section headers in manifest checks
  - **[Installer]** - Function call references in installer scripts
  - **[Installer]** - Duplicate function definitions in bash UI module
  - **[Installer]** - Release workflow to correctly bundle installer files with proper directory structure
  - **[Installer]** - Corrected release installation instructions to use hidden directory `.terraform-azurerm-ai-installer`
  - **[Installer]** - Fixed installation paths to properly reference nested `terraform-azurerm-ai-installer` directory structure
  - **[Installer]** - Clarified that `-Bootstrap` flag is only needed for contributors, not end users
  - **[Installer]** - PowerShell 5.1 compatibility: Fixed "positional parameter" error by using nested `Join-Path` calls instead of three-argument syntax
  - **[Installer]** - Removed confusing automatic verification after `-Clean` operation that reported cleaned files as "MISSING"
  - **[Installer]** - **CRITICAL**: Updated bash installer to use correct directory name `.terraform-azurerm-ai-installer` instead of old `.terraform-ai-installer` (bash installer was completely broken)
  - **[Installer]** - **Error messaging improvements**: Added `-Branch` and `-LocalPath` / `-local-path` detection to `attempted_command` variable in both PowerShell and Bash installers for better contextual error messages
  - **[Installer]** - **PowerShell help system bug**: Fixed `Show-UnknownBranchHelp` function missing `$AttemptedCommand` parameter, which prevented proper command-specific error guidance
  - **[Installer]** - **Documentation consistency**: Updated all references to user profile installer directory to use correct path `~/.terraform-azurerm-ai-installer` (with leading dot for hidden directory)
  - **[Installer]** - **Bootstrap branch detection**: Fixed `-Bootstrap` failing with "Branch '' does not exist" error by properly detecting current git branch
  - **[Installer]** - **LocalPath file resolution**: Removed incorrect path stripping logic that caused file lookups to fail
  - **[Installer]** - **Success counting**: Fixed "Copied" action not being counted as successful in `-LocalPath` installations
  - **[Installer]** - **PowerShell edge cases**: Graceful handling of `-` and `--` parameters consumed by PowerShell runtime
  - **[Installer]** - **Bash empty parameter**: Fixed empty `-local-path ""` validation to properly detect and reject empty strings
  - **[Installer]** - **Bash color codes**: Fixed literal color code text appearing in early validation errors

### Documentation
- Complete README with installation instructions and feature overview
- Detailed installer documentation with troubleshooting guides
- Contributing guidelines for community contributions
- Reference to original HashiCorp PR #29907
- Theme-aware headers for all README files (automatic light/dark mode support)
- Descriptive subtitles for architecture, examples, and troubleshooting documentation
- **Critical installation requirement**: Added prominent warnings that installer must be extracted to user profile directory
- **Troubleshooting guide**: Added "Positional Parameter Error" section explaining directory traversal issues
- **Installation examples**: Updated all installation examples to show correct extraction to user profile directory
- **Contributor mode documentation**: Added comprehensive explanation of contributor mode workflow with clear examples
- **Parameter reference tables**: Enhanced with detailed descriptions, use cases, and examples for all installer parameters
- **Installation workflow clarity**: Documented the distinction between "Option 1: Download Release Package" (99% of users) vs "Option 2: Bootstrap from Local Clone" (contributors only)
- **Repository directory requirement**: Added detailed section explaining when and why `-RepoDirectory`/`-repo-directory` parameter is required
- **Contributing section**: Added bullet point about contributor mode availability with link to installer documentation
- **Architecture documentation**: Fixed PowerShell module ordering to match actual alphabetical directory structure

### Infrastructure
- Set up GitHub repository with proper description and topics
- Added MPL 2.0 license
- Created initial project structure

---

## Version History Notes

### Origin
This project was originally submitted as [PR #29907](https://github.com/hashicorp/terraform-provider-azurerm/pull/29907) to the HashiCorp Terraform AzureRM Provider repository on `June 19, 2025`. To help move the merge forward and make these AI-powered development tools more accessible to the community, the installation infrastructure was moved to this standalone repository on `October 19, 2025`.

### Versioning Strategy
- **Major version (X.0.0)**: Breaking changes to installer or instruction structure
- **Minor version (0.X.0)**: New features, new instruction modules, significant enhancements
- **Patch version (0.0.X)**: Bug fixes, documentation updates, minor improvements

[Unreleased]: https://github.com/WodansSon/terraform-azurerm-ai-assisted-development/compare/v3.3.0...HEAD
[3.3.0]: https://github.com/WodansSon/terraform-azurerm-ai-assisted-development/releases/tag/v3.3.0
[3.0.1]: https://github.com/WodansSon/terraform-azurerm-ai-assisted-development/releases/tag/v3.0.1
[3.0.0]: https://github.com/WodansSon/terraform-azurerm-ai-assisted-development/releases/tag/v3.0.0
[1.0.5]: https://github.com/WodansSon/terraform-azurerm-ai-assisted-development/releases/tag/v1.0.5
[1.0.4]: https://github.com/WodansSon/terraform-azurerm-ai-assisted-development/releases/tag/v1.0.4
[1.0.3]: https://github.com/WodansSon/terraform-azurerm-ai-assisted-development/releases/tag/v1.0.3
[1.0.2]: https://github.com/WodansSon/terraform-azurerm-ai-assisted-development/releases/tag/v1.0.2
[1.0.1]: https://github.com/WodansSon/terraform-azurerm-ai-assisted-development/releases/tag/v1.0.1
[1.0.0]: https://github.com/WodansSon/terraform-azurerm-ai-assisted-development/releases/tag/v1.0.0
