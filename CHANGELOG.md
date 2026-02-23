# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added
- Added a GitHub pull request template at `.github/pull_request_template.md` to standardize PR titles, scope, testing, changelog updates, and AI assistance disclosure.

### Changed
- **BREAKING (planned release: `2.0.0`)**: this release intentionally does not provide backward compatibility for renamed commands/behavior.
- **BREAKING (planned release: `2.0.0`)**: simplified installer CLI:
  - Removed `-Contributor` / `-contributor`
  - Removed `-Branch` / `-branch`
  - `-LocalPath` / `-local-path` is now the only source override (default source is bundled payload `aii/`)
- Set `installer/VERSION` to `0.0.0` to make it clear that it is a placeholder for source checkouts (release bundles are stamped from the tag).
- `-Bootstrap` / `-bootstrap` is now a standalone command (no other parameters accepted) and must be run from a git clone (repo root contains `.git`). Official installation is via the release bundle.
- Bash installer no longer references legacy AzureRM-provider repo layouts/branches (removed `exp/terraform_copilot` and `.github/AIinstaller` fallbacks); bootstrap guidance now consistently points to `./installer/install-copilot-setup.sh`.
- Standardized installer help/examples to refer to the terraform-provider-azurerm working copy directory (rather than legacy "feature branch directory" phrasing) and removed incorrect guidance that bootstrap must run from `main`.
- Installer help output (`-Help` / `-help`) now consistently describes `-RepoDirectory` / `-repo-directory` as pointing to a terraform-provider-azurerm working copy, and avoids showing "attempted command" notes when the user explicitly requests help.
- Renamed the Agent Skills slash commands to remove the `azurerm-` prefix: `/azurerm-docs-writer`, `/azurerm-resource-implementation`, and `/azurerm-acceptance-testing` are now `/docs-writer`, `/resource-implementation`, and `/acceptance-testing`.
- Renamed the docs prompt `/docs-schema-audit` (file: `.github/prompts/docs-schema-audit.prompt.md`) to `/docs-review` (file: `.github/prompts/docs-review.prompt.md`) to better match end-user expectations.
- Updated `/docs-review` to explicitly extract and report cross-field constraints from both the Terraform schema (for example `ConflictsWith`, `ExactlyOneOf`) and diff-time validation (`CustomizeDiff`).
- Updated `/docs-review` to also extract and report implicit behavior constraints from expand/flatten logic (for example feature enablement toggled by block presence, or hardcoded API values not exposed in schema).
- Updated `/docs-review` output to include a "required notes coverage" checklist and to require explicit reporting of detected notes and conditional constraints (or an explicit "none found").
- Updated `/docs-review` to validate note content for correctness (notes describing constraints must match the extracted schema/diff-time/implicit behavior rules).
- Strengthened `/docs-review` and `/docs-writer` instructions so full parity/ordering/notes checks run even when the user provides minimal prompts.
- Aligned `## Arguments Reference` ordering rules in `/docs-review` with provider standards (`name`, `resource_group_name`, `location`, then required alphabetical, then optional alphabetical, `tags` last).
- Clarified `## Attributes Reference` ordering to be strictly `id` first, then remaining attributes alphabetical (no special-casing `tags`, `name`, `resource_group_name`, or `location`).
- Updated `/docs-writer` to automatically add missing `~> **Note:**` blocks for schema and `CustomizeDiff` conditional requirements when updating docs.
- Standardized `ForceNew` argument wording to use the generic sentence: `Changing this forces a new resource to be created.`.
- Expanded `CONTRIBUTING.md` to provide more detailed contribution and validation guidance, including PowerShell/Bash parity expectations to avoid installer drift.
- Removed `-Dry-Run` / `-dry-run` from the installer to keep the workflow focused on install/clean/verify.
- Removed legacy remote download scaffolding; installs now copy from the bundled payload or `-LocalPath` only.
- Installer now validates a bundled payload checksum on install/verify to prevent mixed-state runs; bootstrap and release bundles generate `aii.checksum`.

### Upgrade Notes (from 1.x)
- `-Contributor` / `-contributor`, `-Branch` / `-branch`, and `-Dry-Run` / `-dry-run` were removed.
  - To test local/uncommitted AI changes or install offline, use `-LocalPath` / `-local-path`.
  - Default source is the bundled offline payload (`aii/`) shipped with the release/bootstrapped installer.
- `-Bootstrap` / `-bootstrap` is now standalone (no extra flags). Previous usage like `-Bootstrap -Contributor` becomes just `-Bootstrap`.
- Installs still target a terraform-provider-azurerm working copy via `-RepoDirectory` / `-repo-directory` (validated via `go.mod` module identity and repo structure).

### Fixed
- Fixed a regression where `/docs-review` could miss conditional requirements that should be documented as `~> **Note:**` blocks (from schema cross-field constraints and diff-time validation), by making extraction and coverage reporting non-optional.
- When running the installer directly from a git clone with placeholder `installer/VERSION` (`0.0.0`), the displayed version now matches bootstrap-stamped versions (`dev-<git sha>` with optional `-dirty`).
- Installer installs no longer require internet connectivity (offline payload by default).
- Clarified bootstrap summary labels to distinguish installer files vs payload files (PowerShell and Bash).
- Removed unused installer helpers/exports in PowerShell and Bash modules to reduce dead code.
- Installer summaries now include `Source`, `Manifest`, and `Command` details to make it explicit which files were attempted from which location/ref.
- Release bundles and bootstrapped installs now include an offline payload (`aii/`) so installs do not fetch AI files from GitHub.
- Bash repository validation for `-repo-directory` now requires the terraform-provider-azurerm `go.mod` module declaration (reduces false positives from substring matches).
- `-verify` is offline-only and no longer depends on GitHub connectivity or remote manifest validation.

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

[Unreleased]: https://github.com/WodansSon/terraform-azurerm-ai-assisted-development/compare/v1.0.5...HEAD
[1.0.5]: https://github.com/WodansSon/terraform-azurerm-ai-assisted-development/releases/tag/v1.0.5
[1.0.4]: https://github.com/WodansSon/terraform-azurerm-ai-assisted-development/releases/tag/v1.0.4
[1.0.3]: https://github.com/WodansSon/terraform-azurerm-ai-assisted-development/releases/tag/v1.0.3
[1.0.2]: https://github.com/WodansSon/terraform-azurerm-ai-assisted-development/releases/tag/v1.0.2
[1.0.1]: https://github.com/WodansSon/terraform-azurerm-ai-assisted-development/releases/tag/v1.0.1
[1.0.0]: https://github.com/WodansSon/terraform-azurerm-ai-assisted-development/releases/tag/v1.0.0
