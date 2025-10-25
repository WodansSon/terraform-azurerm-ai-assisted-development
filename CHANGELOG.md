# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

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
- Enhanced error handling in validation engine
- Refactored installer scripts for better maintainability
- Updated README structure with improved section breaks and readability
- Reorganized instruction files to .github/instructions directory
- Enhanced markdownlint configuration for better documentation quality
- **Installation workflow**: Clarified two-step process (download/extract → install) for normal users vs bootstrap workflow for contributors
- **Parameter documentation**: Significantly improved descriptions for `-Contributor`/`-contributor` and `-LocalPath`/`-local-path` parameters
- **User experience**: Updated all documentation to clearly distinguish between normal user workflow (download release package) and contributor workflow (bootstrap from local clone)

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

[Unreleased]: https://github.com/WodansSon/terraform-azurerm-ai-assisted-development/compare/v1.0.0...HEAD
[1.0.0]: https://github.com/WodansSon/terraform-azurerm-ai-assisted-development/releases/tag/v1.0.0
