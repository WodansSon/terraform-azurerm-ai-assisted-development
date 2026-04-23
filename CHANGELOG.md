# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

### Changed

### Fixed

## [3.0.2] - 2026-04-23

### Added

- Added [Code Review Rule Reference](docs/CODE_REVIEW_RULES.md) so end users can decode `REVIEW-*`, `DOCS-*`, `IMPL-*`, and `TEST-*` citations used by the review prompts, skills, and contracts.
- Added a cross-platform PowerShell contract validator plus a dedicated GitHub Actions workflow that discovers contract instruction files, validates their structure and provenance metadata, and reports prompt/skill/companion consumers from the repository itself.
- Added an initial implementation compliance contract for `internal/**/*.go` so Go implementation work can use a real contract layer instead of relying on the `resource-implementation` skill as the sole authority.
- Added a dedicated testing compliance contract for `internal/**/*_test.go` so acceptance-test work can use a real contract layer instead of relying on the `acceptance-testing` skill as the sole authority.

### Changed

- Tightened acceptance-test review guidance so embedded Terraform inside `internal/**/*_test.go` raw strings must be checked against `terrafmt`-style formatting, including flagging tab-indented Terraform blocks instead of assuming `azurerm-linter` will catch those issues.
- Updated the `azurerm-linter` review flow and related documentation so JSON parsing is treated as stdout-only, stderr is suppressed using the native null-device syntax for the active shell on each OS, and the prompts rerun once without suppression when diagnostic output is needed to classify non-JSON results.
- Added an explicit docs wording rule that treats `Resource Group` as canonical Azure object capitalization in field prose, with provenance recorded as an inferred maintainer convention backed by PR review evidence.
- Introduced an incremental provenance model in the docs contract so ambiguous rules can be labeled as published upstream standards, inferred maintainer conventions, or local safeguards, and backfilled that metadata onto an initial set of docs rules.
- Continued the docs-contract provenance backfill across example and block-structure rules that exist primarily as repository safeguards for deterministic docs audits and rewrites.
- Tightened the contract validator so it now verifies declared consumer paths from each contract's `## Consumers` section and requires a terminal contract EOF marker comment as the last non-empty line.
- Standardized contract `## Consumers` sections on an explicit `Consumer:` bullet format and tightened the validator so contract-listed companion instruction files must point back to their contract.
- Added explicit per-consumer `Requires EOF Load: yes` metadata to the current contracts and tightened the validator so declared prompt and skill consumers marked that way must mention loading the contract to EOF.
- Updated the `resource-implementation` skill and Go routing instruction so they now consume the new implementation compliance contract as the authoritative implementation layer.
- Refactored the main implementation guide into explicit companion guidance for the implementation contract and taught the contract validator to discover companion instruction files from the implementation contract's dedicated companion-guidance section.
- Refactored the remaining implementation companion guides so they explicitly point back to the implementation compliance contract as the authoritative layer.
- Updated the `acceptance-testing` skill, test routing instruction, and testing guide so they now consume the new testing compliance contract as the authoritative testing layer.
- Removed the testing guide from the implementation companion set so test authority is no longer split between the implementation and testing contract models.

## [3.0.1] - 2026-04-16

### Changed

- Updated the generic local and committed review prompts plus the shared review contract to prefer [`azurerm-linter`](https://github.com/QixiaLu/azurerm-linter) JSON output, report the linter version in the review output, and require [`azurerm-linter v0.2.0`](https://github.com/QixiaLu/azurerm-linter/releases/tag/v0.2.0) or newer for JSON-mode review.
- Clarified the workspace terminal guidance so [`azurerm-linter`](https://github.com/QixiaLu/azurerm-linter) is treated as a standalone local CLI instead of a Go toolchain command, and hardened the review prompts/contract to require native local linter execution from the repo root instead of WSL-prefixed or cross-shell-wrapped invocations.
- Updated the review prompt output guidance so normalized `### 🎯 **MUST FIX**` linter findings prefer compact Markdown file links like `CHECKID [file:line](repo/relative/path#Lline): message` when deterministic repo-relative paths are available, matching the clickable file-reference style used elsewhere in the review.
- Tightened the fresh-run review rules so repeated code-review invocations must describe only current-run evidence, with no carry-over wording or execution-progress narration before the final review headings.
- Tightened the fresh-run review rules so successful reruns must emit the full current review template even when the reviewed diff and findings are unchanged, instead of short-circuiting to prior review text or delta-only summaries.

### Fixed

- Fixed installed review behavior in `terraform-provider-azurerm` workspaces by discovering repo-level contributor guidance from common target-repo paths, forcing fresh review reruns instead of reusing prior review state, hard-stopping with deterministic fresh-run failure messages, suppressing narrated post-linter verification steps, and rendering azurerm-linter findings in a dedicated `### 🎯 **MUST FIX**` section instead of malformed inline list output.

## [3.0.0] - 2026-04-13

### Added

- Added a dedicated `azurerm-linter` execution/reporting capability to the generic local and committed review prompts, with explicit `Issues found` / `No issues` / `Not applicable` / `Not run` status reporting and a shared compliance contract to keep the flow deterministic.
- Added committed-review and local-review linter flow support around repo-root resolution, direct filtered execution, PR-scoped committed review, explicit run-scope reporting, and reviewer-facing linter output fields.
- Added explicit `azurerm-linter` handling for no-work results, flag/usage parse errors, slow executions, missing local installs, and PR-number discovery failures so the review prompts classify results deterministically instead of silently skipping or misreporting the tool.
- Added structured `azurerm-linter` issue surfacing rules so findings appear both in the dedicated linter execution subsection and in the main review `ISSUES` section.
- Added linter-specific prompt/contract guidance for command authorization, immediate execution, repo-root resolution via `git rev-parse --show-toplevel`, longer sync timeouts, and local-install-only expectations.
- Added a narrow VS Code user-setting override example for auto-approving the harmless repo-root lookup command used by the linter flow.
- Added deterministic committed-review PR-number discovery rules and explicit rerun guidance such as `/code-review-committed-changes PR 12345` when the linter cannot determine PR context automatically.
- Added release-note/documentation caveats that the prompt-side `azurerm-linter` flow assumes a recent upstream `azurerm-linter` binary, with the current dependency called out explicitly as [QixiaLu/azurerm-linter#50](https://github.com/QixiaLu/azurerm-linter/pull/50), so behavior may differ until the corresponding upstream changes are merged and installed locally.
- Added GitHub artifact attestations to the installer release workflow and documented how users should verify official pinned release assets with `gh attestation verify`, introducing a provenance-based release trust model alongside the existing checksum-based integrity checks.
- Added explicit documentation for the expected successful attestation verification pattern, including the normal case where multiple matching attestations appear because the stable-name and versioned release assets share the same digest.
- Added explicit PowerShell and Bash `gh attestation verify` examples that show the correct stable-name archive path to verify for each shell.
- Added explicit end-user guidance that `gh attestation verify` must be run against the downloaded release archive with GitHub CLI authenticated to `github.com`, including recovery steps for the common `HTTP 401: Bad credentials` failure mode.

### Changed

- Tightened the docs compliance contract so data source arguments, attributes, and nested fields must stay short and only explain what the field is, without field-level note blocks; aligned `.github/instructions/documentation-guidelines.instructions.md`, `.github/skills/docs-writer/SKILL.md`, and `.github/prompts/code-review-docs.prompt.md` to enforce the same rule consistently.
- Tightened the shared code review contract with explicit file-type coverage rules so local and committed reviews continue to check installer cross-platform drift, prompt/instruction/skill determinism and alignment, manifest consistency, and user-visible text quality instead of only applying generic evidence rules.
- Taught the generic local and committed review flows to defer `website/docs/**/*.html.markdown` compliance to the shared docs compliance contract, so mixed code-and-docs reviews can cite `DOCS-*` rules without importing docs-writer footer behavior into the generic review prompts.
- Fixed installer packaging by adding `.github/instructions/code-review-compliance-contract.instructions.md` to `installer/file-manifest.config`, ensuring bootstrap and installed payloads include the shared review contract required by the updated code review prompts.
- Clarified the installer trust model in the docs: attestations and checksums protect artifact provenance and integrity only when users verify against the canonical pinned repository/workflow identity, and they do not remove the need for users to trust the real canonical repo as their starting point.
- Promoted the installer trust-model guidance into a visible README installation section so users see the canonical repo/workflow trust boundary before the download and extraction commands.
- Hardened the PowerShell validation workflows so they install `PSScriptAnalyzer` through a cross-platform repository bootstrap path that prefers `Install-PSResource`/`PSGallery` and falls back to `Install-Module`, avoiding runner-specific failures when the legacy NuGet package-provider bootstrap is unavailable.

## [2.0.8] - 2026-03-26

### Fixed

- Aligned the shared docs compliance contract and companion documentation guidance with HashiCorp's preferred `*_enabled` wording so both resources and data sources use statement phrasing (`Whether ... is enabled.`), with resource docs keeping a separate `Defaults to ...` sentence when applicable; clarified that data source summary-sentence restrictions are separate from Attributes Reference wording restrictions; and tightened argument guidance so core semantics like `Possible values are ...` and `Defaults to ...` stay in the bullet by default instead of being pushed into notes.

## [2.0.7] - 2026-03-18

### Changed

- Tightened the shared docs compliance contract so it is the authoritative compliance layer for docs work, added explicit rules to cover the upstream contributor documentation standards (including frontmatter placement/content, doc path naming, summary sentence placement, and `hcl` code-fence requirements), and refactored `.github/instructions/documentation-guidelines.instructions.md` into companion guidance that points back to the contract instead of duplicating normative rules.

## [2.0.6] - 2026-03-16

### Changed

- Tightened the shared docs compliance contract with deterministic rules for intra-section block reference direction (`as defined above` vs `as defined below`), mandatory block subsection separators in `Arguments Reference` and `Attributes Reference`, and canonical resource-name usage in resource `Attributes Reference`, `Timeouts`, and `Import` prose.

### Fixed

- Fixed flaky macOS PowerShell validation in CI by using the hosted runner's existing `pwsh` when available, falling back to Homebrew installation only when PowerShell is missing.

## [2.0.5] - 2026-03-09

### Changed

- Hardened `/code-review-docs` determinism rules to avoid run-to-run "guessing" (no A/B options; patch-ready snippets must be fully specified).
- Expanded `/code-review-docs` docs-quality checks (timeouts readability, import example ID shape validation, `hcl` code fences, and page-self-contained example reference scans).
- Moved docs compliance rules into a shared docs compliance contract and refactored `/code-review-docs` + `/docs-writer` to reference stable `DOCS-*` IDs instead of duplicating large rule blocks.
- Added new hard-compliance docs contract rules for note de-duplication, argument bullet length caps, net-new `depends_on` restrictions, and legacy (non-vNext) field exclusion (`DOCS-NOTE-008`, `DOCS-ARG-011`, `DOCS-EX-017`, `DOCS-DEPR-002`).
- Aligned `/docs-writer` with `/code-review-docs` by adding concrete evidence-extraction procedures for `CustomizeDiff` call-chain tracing and Importer/ID-shape derivation (follow parser → ID type → formatter; do not guess without evidence).
- Updated `/code-review-docs` and `/docs-writer` guidance to consistently treat next-major deprecations as vNext surface area (do not require legacy fields for docs parity).
- Standardized example naming guidance: name-like values should use `example-`/`existing-` prefixes where feasible (nit-level), and recommend deterministic type-derived names when schema/`ValidateFunc` evidence proves the derived value is valid.
- Prevented duplicated `/code-review-docs` headings by requiring atomic output buffering (assemble the full 9-heading review internally, then emit once).
- Aligned `.github/instructions/documentation-guidelines.instructions.md` with the shared docs contract to avoid conflicting precedence/examples.
- Clarified scaffolding usage: docs scaffolding is a writer workflow (skill) for brand-new docs pages or explicit scaffold/dry-run requests; `/code-review-docs` remains audit-only.
- Prohibited `/code-review-docs` from suggesting or invoking repo tooling (scaffold/validators/linters); audits are derived from static workspace evidence only.
- Updated `/code-review-local-changes` and `/code-review-committed-changes` to flag string enum boolean toggles (`Enabled`/`Disabled`, `On`/`Off`, with optional `None` tri-state) and prefer boolean `*_enabled` for new schema surface area; added matching guidance to schema patterns.

### Fixed

- Fixed repeated audit findings by requiring `/code-review-docs` to emit fully patch-ready ordering fixes (including full corrected nested block snippets) and a self-check mapping each Issue to a specific snippet.
- Fixed a docs regression where "Example ..." sections could be converted to prose to satisfy self-containment, leading to inconsistent outcomes. Example sections now remain copy/pasteable Terraform and fixes expand examples to be page-self-contained.
- Fixed common doc-quality regressions by enforcing canonical enum phrasing and mandatory legacy-phrase rewrites (for example `Valid values are` -> `Possible values are`) and treating example naming conventions as patch-ready low-priority nits.
- Fixed `/docs-writer` enum wording guidance to match the shared docs compliance contract (`DOCS-WORD-002`).
- Fixed docs security guidance so hard-coded secrets in examples are flagged and replaced with context-appropriate `var.<name>` references (variable block optional).

## [2.0.4] - 2026-02-24

### Fixed
- Fixed Bash installer bundle checksum verification to hash the manifest+payload listing bytes directly (preserves the trailing newline), matching the release and PowerShell implementations. This prevents checksum mismatches on Linux/WSL.

## [2.0.3] - 2026-02-24

### Fixed
- Fixed installer bundle checksum validation on non-Windows PowerShell by including hidden dot-directories (for example `.github/`, `.vscode/`) when computing the payload hash. This prevents false checksum mismatches in release verification.

## [2.0.2] - 2026-02-24

### Fixed
- Fixed release bundle generation so `aii.checksum` is computed from the exact bytes being validated (preserves the trailing newline in the hashed manifest+payload listing). This prevents installer payload checksum validation failures when running from extracted release bundles.

## [2.0.1] - 2026-02-24

### Fixed
- Fixed a checksum validation regression on Windows where release bundles stamped on Linux/macOS could fail `aii.checksum` verification due to PowerShell/Bash algorithm drift (PowerShell checksum computation now matches the Bash implementation).

## [2.0.0] - 2026-02-24

### Added
- Added a GitHub pull request template at `.github/pull_request_template.md` to standardize PR titles, scope, testing, changelog updates, and AI assistance disclosure.

### Changed
- **BREAKING**: this release intentionally does not provide backward compatibility for renamed commands/behavior.
- **BREAKING**: simplified installer CLI:
  - Removed `-Contributor` / `-contributor`
  - Removed `-Branch` / `-branch`
  - `-LocalPath` / `-local-path` is now the only source override (default source is bundled payload `aii/`)
- Set `installer/VERSION` to `0.0.0` to make it clear that it is a placeholder for source checkouts (release bundles are stamped from the tag).
- `-Bootstrap` / `-bootstrap` is now a standalone command (no other parameters accepted) and must be run from a git clone (repo root contains `.git`). Official installation is via the release bundle.
- Bash installer no longer references legacy AzureRM-provider repo layouts/branches (removed `exp/terraform_copilot` and `.github/AIinstaller` fallbacks); bootstrap guidance now consistently points to `./installer/install-copilot-setup.sh`.
- Standardized installer help/examples to refer to the terraform-provider-azurerm working copy directory (rather than legacy "feature branch directory" phrasing) and removed incorrect guidance that bootstrap must run from `main`.
- Installer help output (`-Help` / `-help`) now consistently describes `-RepoDirectory` / `-repo-directory` as pointing to a terraform-provider-azurerm working copy, and avoids showing "attempted command" notes when the user explicitly requests help.
- Renamed the Agent Skills slash commands to remove the `azurerm-` prefix: `/azurerm-docs-writer`, `/azurerm-resource-implementation`, and `/azurerm-acceptance-testing` are now `/docs-writer`, `/resource-implementation`, and `/acceptance-testing`.
- Renamed the docs prompt `/docs-schema-audit` (file: `.github/prompts/docs-schema-audit.prompt.md`) to `/code-review-docs` (file: `.github/prompts/code-review-docs.prompt.md`) to group review prompts consistently.
- Updated `/code-review-docs` to explicitly extract and report cross-field constraints from both the Terraform schema (for example `ConflictsWith`, `ExactlyOneOf`) and diff-time validation (`CustomizeDiff`).
- Updated `/code-review-docs` to also extract and report implicit behavior constraints from expand/flatten logic (for example feature enablement toggled by block presence, or hardcoded API values not exposed in schema).
- Updated `/code-review-docs` output to include a "required notes coverage" checklist and to require explicit reporting of detected notes and conditional constraints (or an explicit "none found").
- Updated `/code-review-docs` to validate note content for correctness (notes describing constraints must match the extracted schema/diff-time/implicit behavior rules).
- Strengthened `/code-review-docs` and `/docs-writer` instructions so full parity/ordering/notes checks run even when the user provides minimal prompts.
- Aligned `## Arguments Reference` ordering rules in `/code-review-docs` with provider standards (`name`, `resource_group_name`, `location`, then required alphabetical, then optional alphabetical, `tags` last).
- Clarified `## Attributes Reference` ordering to be strictly `id` first, then remaining attributes alphabetical (no special-casing `tags`, `name`, `resource_group_name`, or `location`).
- Updated `/docs-writer` to automatically add missing `~> **Note:**` blocks for schema and `CustomizeDiff` conditional requirements when updating docs.
- Standardized `ForceNew` argument wording to use the generic sentence: `Changing this forces a new resource to be created.`.
- Expanded `CONTRIBUTING.md` to provide more detailed contribution and validation guidance, including PowerShell/Bash parity expectations to avoid installer drift.
- Removed `-Dry-Run` / `-dry-run` from the installer to keep the workflow focused on install/clean/verify.
- Removed legacy remote download scaffolding; installs now copy from the bundled payload or `-LocalPath` only.
- Installer now validates a bundled payload checksum on install/verify to prevent mixed-state runs; bootstrap and release bundles generate `aii.checksum`.
- `-Verify` / `-verify` now has two modes:
  - Without `-RepoDirectory` / `-repo-directory` (typically from the user-profile installer directory), it performs an **installer bundle self-check** (manifest/modules/payload/checksum).
  - With `-RepoDirectory` / `-repo-directory`, it verifies AI infrastructure presence in the **target repository**.
- `-Verify -RepoDirectory` (and the equivalent Bash form) now hard-fails if the repo directory points at the installer source repository, to prevent false-positive verification.

### Upgrade Notes (from 1.x)
- `-Contributor` / `-contributor`, `-Branch` / `-branch`, and `-Dry-Run` / `-dry-run` were removed.
  - To test local/uncommitted AI changes or install offline, use `-LocalPath` / `-local-path`.
  - Default source is the bundled offline payload (`aii/`) shipped with the release/bootstrapped installer.
- `-Bootstrap` / `-bootstrap` is now standalone (no extra flags). Previous usage like `-Bootstrap -Contributor` becomes just `-Bootstrap`.
- Installs still target a terraform-provider-azurerm working copy via `-RepoDirectory` / `-repo-directory` (validated via `go.mod` module identity and repo structure).

### Fixed
- Fixed a regression where `/code-review-docs` could miss conditional requirements that should be documented as `~> **Note:**` blocks (from schema cross-field constraints and diff-time validation), by making extraction and coverage reporting non-optional.
- When running the installer directly from a git clone with placeholder `installer/VERSION` (`0.0.0`), the displayed version now matches bootstrap-stamped versions (`dev-<git sha>` with optional `-dirty`).
- Installer installs no longer require internet connectivity (offline payload by default).
- Clarified bootstrap summary labels to distinguish installer files vs payload files (PowerShell and Bash).
- Removed unused installer helpers/exports in PowerShell and Bash modules to reduce dead code.
- Installer summaries now include `Source`, `Manifest`, and `Command` details to make it explicit which files were attempted from which location/ref.
- Release bundles and bootstrapped installs now include an offline payload (`aii/`) so installs do not fetch AI files from GitHub.
- Bash repository validation for `-repo-directory` now requires the terraform-provider-azurerm `go.mod` module declaration (reduces false positives from substring matches).
- `-verify` is offline-only and no longer depends on GitHub connectivity or remote manifest validation.
- Unified PowerShell/Bash early validation and error output to reduce cross-platform drift (for example, `-RepoDirectory` / `-repo-directory` now fails fast when the target path does not exist).

## [1.0.5] - 2026-02-18

### Fixed
- Release bundles now set executable permissions on the bundled Bash installer scripts (with a `chmod +x` fallback note for environments that drop execute bits).

## [1.0.4] - 2026-02-18

### Changed
- Updated the `.github/prompts/docs-review.prompt.md` prompt to reflect proposed upstream contributor documentation standards (based on [hashicorp/terraform-provider-azurerm PR #31772](https://github.com/hashicorp/terraform-provider-azurerm/pull/31772)) for nested block field ordering (arguments and attributes) and ForceNew wording guidance.
- Updated the `/docs-writer` skill to enforce nested block field ordering and align ForceNew wording guidance (legacy vs descriptive phrasing), while keeping the skill under the 500-line limit.
- Removed empty `##` spacer headings from README files to avoid bogus headings and keep GitHub Markdown rendering consistent.
- Centralized the installer version into `installer/VERSION` (PowerShell + Bash now read from that file) and updated the release workflow to write the tagged version into the bundled installer.
- Updated `-Bootstrap` to stamp a contributor-friendly version in the user profile installer (`dev-<git sha>` with optional `-dirty`) to clearly indicate a local, bootstrapped build.

## [1.0.3] - 2026-02-17

### Changed
- Clarified the `/docs-writer` skill final checklist to explicitly restate canonical `## Arguments Reference` argument ordering.
- Audited and clarified the `/docs-writer` skill instructions to remove duplicated/contradictory rules and improve example clarity.
- GitHub Release notes now correctly include the version-specific `CHANGELOG.md` section (previously blank due to extraction logic).
- Standardized GitHub Release notes headings to plain text (removed emojis).

## [1.0.2] - 2026-02-15

### Added
- Agent Skill files under `.github/skills/` (for example `/docs-writer`) are now distributed by the installer.

### Changed
- Installer now installs, verifies, and cleans `.github/skills` alongside instructions and prompts, including automated deprecation removal based on the manifest.
- CI markdownlint configuration now disables `MD007` (unordered list indentation) to avoid false positives with HashiCorp-style indentation.

### Fixed
- Fixed markdownlint failures in `.github/skills/docs-writer/SKILL.md` (for example `MD029` ordered list numbering).

## [1.0.1] - 2026-02-12

### Added
- Release assets with stable (unversioned) filenames to support `releases/latest/download/*` install URLs:
  - `terraform-azurerm-ai-installer.zip`
  - `terraform-azurerm-ai-installer.tar.gz`
- New optional documentation audit prompt:
  - `.github/prompts/docs-review.prompt.md`

### Changed
- Documentation now clearly distinguishes installing the latest release (`releases/latest/download/...`) from pinning a specific version (`releases/download/vX.Y.Z/...`)

## [1.0.0] - 2025-10-22

### Added
- Initial public release of the Terraform AzureRM AI-Assisted Development toolkit
- Cross-platform installer (PowerShell and Bash)
- Comprehensive Copilot instructions for Terraform AzureRM Provider development
- 12+ instruction modules covering Azure patterns, testing, security, and more
- Code review prompts for local and committed changes
- VS Code integration and configuration
- Bootstrap mode for automatic detection of terraform-provider-azurerm repository
- Release process automation with GitHub Actions workflow
- Release documentation and procedures (RELEASING.md)
- **Contributor mode** (`-Contributor`/`-contributor`) for working with local AI dev repo changes before pushing
- **Local source path** (`-LocalPath`/`-local-path`) parameter for testing uncommitted changes from local AI dev repository
- **Repository directory** (`-RepoDirectory`/`-repo-directory`) parameter requirement when running from user profile for proper git repository detection

### Changed
- Improved installer validation messages for better clarity and user feedback
- Enhanced error handling in validation engine with consolidated error functions
- Refactored installer scripts for better maintainability with region-based organization
- Updated README structure with improved section breaks and readability
- Reorganized instruction files to .github/instructions directory
- Enhanced markdownlint configuration for better documentation quality
- **Installation workflow**: Clarified two-step process (download/extract → install) for normal users vs bootstrap workflow for contributors
- **Parameter documentation**: Significantly improved descriptions for `-Contributor`/`-contributor` and `-LocalPath`/`-local-path` parameters
- **User experience**: Updated all documentation to clearly distinguish between normal user workflow (download release package) and contributor workflow (bootstrap from local clone)
- **Version control**: Centralized version management with single update point (`$script:InstallerVersion` in PowerShell, `INSTALLER_VERSION` in Bash)
- **Installation source clarity**: Updated messages to clearly show source (GitHub branch, local path) and action (Installing, Downloading)
- **Help system**: Context-aware help display based on execution location (source branch vs user profile)
- **Help completeness**: Added all contributor options to help display with explicit requirement indicators
- **Validation improvements**:
  - Consolidated 5 error types into reusable `Show-EarlyValidationError` function (PowerShell) and `show_early_validation_error` (Bash)
  - Early validation for empty and non-existent `-LocalPath`/`-local-path` parameters
  - Fail-fast architecture with consistent error formatting
- **Output formatting**: Consistent spacing between output sections across all UI functions
- **Bootstrap reliability**: Fixed branch detection to use current git branch instead of defaulting to empty string
- **Bash color support**: Moved color definitions before module loading for proper error message display

### Fixed
- ShellCheck exclusions for bash scripts to prevent false positives
- Markdownlint configuration compatibility with cli2
- Validation workflow to properly skip section headers in manifest checks
- Function call references in installer scripts
- Duplicate function definitions in bash UI module
- Release workflow to correctly bundle installer files with proper directory structure
- Corrected release installation instructions to use hidden directory `.terraform-azurerm-ai-installer`
- Fixed installation paths to properly reference nested `terraform-azurerm-ai-installer` directory structure
- Clarified that `-Bootstrap` flag is only needed for contributors, not end users
- PowerShell 5.1 compatibility: Fixed "positional parameter" error by using nested `Join-Path` calls instead of three-argument syntax
- Removed confusing automatic verification after `-Clean` operation that reported cleaned files as "MISSING"
- **CRITICAL**: Updated bash installer to use correct directory name `.terraform-azurerm-ai-installer` instead of old `.terraform-ai-installer` (bash installer was completely broken)
- **Error messaging improvements**: Added `-Branch` and `-LocalPath` / `-local-path` detection to `attempted_command` variable in both PowerShell and Bash installers for better contextual error messages
- **PowerShell help system bug**: Fixed `Show-UnknownBranchHelp` function missing `$AttemptedCommand` parameter, which prevented proper command-specific error guidance
- **Documentation consistency**: Updated all references to user profile installer directory to use correct path `~/.terraform-azurerm-ai-installer` (with leading dot for hidden directory)
- **Bootstrap branch detection**: Fixed `-Bootstrap` failing with "Branch '' does not exist" error by properly detecting current git branch
- **LocalPath file resolution**: Removed incorrect path stripping logic that caused file lookups to fail
- **Success counting**: Fixed "Copied" action not being counted as successful in `-LocalPath` installations
- **PowerShell edge cases**: Graceful handling of `-` and `--` parameters consumed by PowerShell runtime
- **Bash empty parameter**: Fixed empty `-local-path ""` validation to properly detect and reject empty strings
- **Bash color codes**: Fixed literal color code text appearing in early validation errors

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

[Unreleased]: https://github.com/WodansSon/terraform-azurerm-ai-assisted-development/compare/v3.0.1...HEAD
[3.0.1]: https://github.com/WodansSon/terraform-azurerm-ai-assisted-development/releases/tag/v3.0.1
[3.0.0]: https://github.com/WodansSon/terraform-azurerm-ai-assisted-development/releases/tag/v3.0.0
[1.0.5]: https://github.com/WodansSon/terraform-azurerm-ai-assisted-development/releases/tag/v1.0.5
[1.0.4]: https://github.com/WodansSon/terraform-azurerm-ai-assisted-development/releases/tag/v1.0.4
[1.0.3]: https://github.com/WodansSon/terraform-azurerm-ai-assisted-development/releases/tag/v1.0.3
[1.0.2]: https://github.com/WodansSon/terraform-azurerm-ai-assisted-development/releases/tag/v1.0.2
[1.0.1]: https://github.com/WodansSon/terraform-azurerm-ai-assisted-development/releases/tag/v1.0.1
[1.0.0]: https://github.com/WodansSon/terraform-azurerm-ai-assisted-development/releases/tag/v1.0.0
