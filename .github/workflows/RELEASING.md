# Creating a New Release

This document describes how to create a new release of the Terraform AzureRM AI-Assisted Development tools.

## Release Process

The established release path has four distinct phases:

- **Pre-release checks** prove that the current `main` content is ready to release.
- **Release preparation** creates and obtains approval for the versioned changelog cut.
- **Publication** commits the approved changelog to `main` and pushes the version tag.
- **Post-release verification** validates the published release, assets, provenance, and installation path.

Do not collapse these phases into one checklist. In particular, pre-release checks happen before the changelog release cut, and pushing the version tag is the action that starts public release publication.

### Release validation boundary

This repository is the source of the AI infrastructure. Release validation MUST preserve these boundaries:

- Do not run `installer/install-copilot-setup.ps1 -Bootstrap` or `installer/install-copilot-setup.sh -bootstrap`. Bootstrap is a contributor workflow that overwrites the persistent user-profile installer; it is not a release validation step.
- Do not stage dry-run output anywhere inside this source repository or under the persistent user-profile installer. `tools/build-release-bundle_dry_run.ps1` defaults to an external temporary directory and rejects those protected roots.
- Run only the staged installer's standalone `-Version` command during the dry run. Do not pass `-RepoDirectory`, `-repo-directory`, or any installation target; the dry run does not install AI files.
- Do not checkout, pull, or otherwise change the active source-repository branch during release validation without explicit maintainer approval.

### 1. Confirm pre-release checks are complete

Before starting release preparation, confirm that the maintainer has completed the pre-release checks against the current `main` release candidate:

- the full one-shot validation passed
- a reserved-version `0.0.1` release bundle was built under an external temporary fake user directory
- the staged bundle checksum passed PowerShell validation and matched the Bash implementation
- the staged installer reported version `0.0.1`

The normal one-shot validation command is:

```powershell
pwsh -NoProfile -File ./tools/validate-ai-toolkit.ps1
```

The normal dry-run bundle command is:

```powershell
pwsh -NoProfile -File ./tools/build-release-bundle_dry_run.ps1 -Version 0.0.1 -OutputRoot "$env:TEMP\azurerm-ai-release-dry-run" -SkipWsl -Force
```

This Windows command validates the release-shaped package and checksum with PowerShell without invoking WSL. The non-Windows installer-validation jobs MUST pass `-RequireBash`, which recomputes the staged payload checksum with Bash and fails on an unavailable runtime, execution error, or mismatch. Do not consider the checksum gate complete unless both the Windows PowerShell job and a non-Windows Bash-required job pass for the release candidate.

Version `0.0.1` is the reserved dry-run sentinel: the project is already beyond the `0.x` release line, and it differs from the in-repo `0.0.0` placeholder so the dry run proves that version stamping occurred. The dry-run bundle confirms the release-artifact, checksum, and version-reporting paths without publishing anything publicly or modifying the source repository or persistent user-profile installer.

When assisting with a release, ask whether these checks are already complete. If the maintainer confirms that they are complete, do not rerun or restart the pre-release phase. Proceed to release-structure and changelog validation.

### 2. Validate the release structure and draft the changelog cut

Before editing the changelog:

- confirm the worktree is clean and local `main` matches `origin/main`
- confirm the intended version does not already have a local tag, remote tag, or GitHub release
- confirm the version increment matches the repository's versioning strategy
- validate the current changelog taxonomy and footer structure

Use:

```powershell
pwsh -NoProfile -File ./tools/validate-changelog-taxonomy.ps1
pwsh -NoProfile -File ./tools/validate-changelog-consistency.ps1
```

The dry-run checks in the previous phase validate the release candidate without changing `CHANGELOG.md`, creating a release commit, or publishing anything. After those checks pass, begin the actual release preparation by moving the current `Unreleased` notes into a new section with the header pattern `## [X.Y.Z] - YYYY-MM-DD`, using the same grouped taxonomy shape; make this versioned changelog cut before asking for release approval.

```markdown
## [1.0.0] - 2025-10-21

### Added

- **User-Priority:**
  - **[Docs]** - Initial release of AI-assisted development tools and maintainer documentation.
  - **[Installer]** - Installation scripts and installer bundles for Windows and Linux/macOS.

- **Maintainer/Workflow:**
  - **[Implementation]** - Initial instruction, prompt, and skill surfaces for provider development.

### Changed

- **User-Priority:**
  - **[Installer]** - Updated the installer to bundle all required modules.

### Fixed

- **User-Priority:**
  - **[Installer]** - Fixed line endings in bash scripts.
```

Maintainer conventions for the changelog cut:

- after moving the release notes into the new versioned section, restore an empty `## [Unreleased]` section at the top with empty `### Added`, `### Changed`, and `### Fixed` headings
- update the footer reference block so the new release section has a `[X.Y.Z]` link entry and `[Unreleased]` compares from the newly latest released version
- preserve the approved release-note wording unless the maintainer explicitly asks for release-note edits
- validate the resulting taxonomy, release heading, footer links, and Markdown structure
- show the maintainer the actual changelog diff and ask for explicit approval
- do not commit, push, or tag until the maintainer approves the edited changelog

### 3. Commit the approved changelog cut directly to `main`

The established release procedure commits the changelog-only release cut directly to validated `main`. A `release/*` branch and release pull request are not required.

After the maintainer approves the changelog diff:

- confirm that `CHANGELOG.md` is the only changed file
- commit the approved cut on `main`
- use the exact established commit-subject pattern `Prepare X.Y.Z changelog`
- push `main`
- verify that local `main` and `origin/main` point to the same release-preparation commit

Example:

```powershell
git add -- CHANGELOG.md
git commit -m "Prepare X.Y.Z changelog"
git push origin main
```

Do not manually edit `installer/VERSION`. The release workflow stamps the bundled version from the tag.

### 4. Publish the release by pushing the tag

Pushing the version tag is the actual publication trigger. Create the annotated tag only after the approved changelog commit is present on both local and remote `main`.

Verify that the tag does not already exist, create it at the release-preparation commit, verify its target, and push it:

```bash
git checkout main
git pull --ff-only origin main

git tag -a vX.Y.Z -m "Release vX.Y.Z"
git rev-list -n 1 vX.Y.Z
git push origin vX.Y.Z
```

Do not move or recreate a published version tag. If the publication workflow fails, diagnose the workflow before deciding whether rollback is necessary.

### 5. GitHub Actions automatic publication

The GitHub Actions workflow (`.github/workflows/release.yml`) will automatically:

1. ✅ Extract changelog for this version
2. ✅ Create installer bundle directory structure
3. ✅ Stamp the bundled installer `VERSION` file from the release tag
4. ✅ Copy all installer files and modules
5. ✅ Create ZIP archive for Windows users
6. ✅ Create TAR.GZ archive for Linux/macOS users
7. ✅ Create full source archive
8. ✅ Generate SHA256 checksums
9. ✅ Generate GitHub artifact attestations for the release assets and checksum manifest
10. ✅ Create GitHub Release with all artifacts
11. ✅ Include installation and provenance verification instructions in release notes

Important distinction:

- the in-repo [installer/VERSION](../../installer/VERSION) file remains a placeholder during normal development
- the release workflow derives the real release version from the pushed `v*.*.*` tag
- that tag-derived version is written into the bundled installer `VERSION` file before the archives are created

That means maintainers do not manually edit `installer/VERSION` as part of the release process. The published release bundle is what gets the stamped release version.

### 6. Verify the published release

Visit: `https://github.com/WodansSon/terraform-azurerm-ai-assisted-development/releases`

Check that:
- [ ] Release was created successfully
- [ ] All assets are attached:
  - `terraform-azurerm-ai-installer.zip` (Windows, stable name for `releases/latest/download/`)
  - `terraform-azurerm-ai-installer.tar.gz` (Linux/macOS, stable name for `releases/latest/download/`)
  - `terraform-azurerm-ai-installer-v*.*.*.zip` (Windows, versioned)
  - `terraform-azurerm-ai-installer-v*.*.*.tar.gz` (Linux/macOS, versioned)
  - `terraform-azurerm-ai-assisted-development-v*.*.*.tar.gz` (Full source)
  - `checksums.txt`
- [ ] Artifact attestations exist for the release assets and `checksums.txt`
- [ ] Release notes include installation instructions
- [ ] Release notes include `gh attestation verify` examples
- [ ] Changelog is properly extracted

### 7. Verify release provenance

For a pinned asset, verify the attestation against the canonical repository and release workflow:

PowerShell:

```powershell
gh attestation verify "$env:TEMP\terraform-azurerm-ai-installer.zip" --repo WodansSon/terraform-azurerm-ai-assisted-development --signer-workflow WodansSon/terraform-azurerm-ai-assisted-development/.github/workflows/release.yml --source-ref refs/tags/vX.Y.Z
```

Bash:

```bash
gh attestation verify /tmp/terraform-azurerm-ai-installer.tar.gz \
  --repo WodansSon/terraform-azurerm-ai-assisted-development \
  --signer-workflow WodansSon/terraform-azurerm-ai-assisted-development/.github/workflows/release.yml \
  --source-ref refs/tags/vX.Y.Z
```

Use this as the publisher-authenticity check.

Expected success pattern:
- The local archive digest loads successfully.
- GitHub loads one or more attestations for that digest.
- The command ends with `Verification succeeded!`.
- Matching attestations reference `.github/workflows/release.yml@refs/tags/vX.Y.Z`.
- Multiple matches can be expected when the stable-name and versioned assets share the same digest.

`checksums.txt` and `aii.checksum` remain useful integrity checks, but they are not substitutes for provenance verification.

## Release Assets Explained

### Installer Bundles (Recommended)

**For End Users:**

- **`terraform-azurerm-ai-installer.zip`** - Windows bundle (stable name)
  - Intended for `releases/latest/download/terraform-azurerm-ai-installer.zip`

- **`terraform-azurerm-ai-installer.tar.gz`** - Linux/macOS bundle (stable name)
  - Intended for `releases/latest/download/terraform-azurerm-ai-installer.tar.gz`

- **`terraform-azurerm-ai-installer-v*.*.*.zip`** - Windows bundle
  - Contains: `install-copilot-setup.ps1`, modules, config
  - Ready to extract and run

- **`terraform-azurerm-ai-installer-v*.*.*.tar.gz`** - Linux/macOS bundle
  - Contains: `install-copilot-setup.sh`, modules, config
  - Ready to extract and run

### Full Source Archive

**For Advanced Users:**

- **`terraform-azurerm-ai-assisted-development-v*.*.*.tar.gz`**
  - Complete repository snapshot
  - Includes: instructions, prompts, installer, documentation
  - For users who want to browse all files or contribute

## Version Numbering

Follow [Semantic Versioning](https://semver.org/):

- **MAJOR.MINOR.PATCH** (e.g., `v1.2.3`)
- **MAJOR**: Breaking changes (v1.0.0 → v2.0.0)
- **MINOR**: New features, backward compatible (v1.0.0 → v1.1.0)
- **PATCH**: Bug fixes, backward compatible (v1.0.0 → v1.0.1)

The release tag is also the source of truth for installer bundle version stamping.

## Pre-Release Bundle Check Reference

This is the detailed reference for the dry-run bundle check in pre-release phase 1. Complete it before starting the changelog release cut:

```powershell
pwsh -NoProfile -File ./tools/build-release-bundle_dry_run.ps1 -Version 0.0.1 -OutputRoot "$env:TEMP\azurerm-ai-release-dry-run" -Force
```

That dry run:

- stages the same installer layout as the release workflow
- stamps `VERSION`, `commit`, and `aii.checksum`
- verifies the staged bundle checksum
- runs the staged PowerShell installer with `-Version` and requires it to report `0.0.1`
- creates the same ZIP and TAR.GZ installer archives without publishing them

Checksum and version reporting are the only purposes of this pre-release dry run. It is complete only when PowerShell validation succeeds, the Bash-computed hash matches, and the staged installer reports `0.0.1`. Use `-RequireBashChecksum` on a Bash-capable environment to make that cross-check mandatory; on Windows without a permitted Bash runtime, use `-SkipWsl` and rely on the required non-Windows CI job for the Bash half.

Use a throwaway test tag only if you specifically need to validate the GitHub release workflow itself rather than the bundle contents.

## Troubleshooting

### Release workflow failed

1. Check GitHub Actions tab
2. Review workflow logs
3. Common issues:
   - Missing files in `installer/` directory
   - CHANGELOG.md format issues
   - Permissions issues

### Release created but assets missing

1. Check workflow completed successfully
2. Verify all build steps passed
3. Re-run the workflow if needed

## Post-Release Tasks

After creating a release:

1. ✅ Download the real release bundle assets
2. ✅ Run a release-bundle install smoke on Windows
3. ✅ Run a release-bundle install smoke on Linux/macOS
4. ✅ Update README if needed
5. ✅ Announce release (if applicable)
6. ✅ Monitor for issues

Important distinction:

- bootstrap is a contributor-only workflow and is excluded from release validation because it overwrites the persistent user-profile installer
- the externally staged reserved `0.0.1` bundle is the pre-release checksum and version-reporting smoke for the release-artifact path on PowerShell and Bash
- the published release-bundle install smoke remains a post-release verification step against the real public artifact

## Rollback Process

If a release has critical issues:

```bash
# Delete the GitHub release (UI or API)
# Delete the tag
git push --delete origin v1.0.0
git tag -d v1.0.0

# Create a new patch release with fixes
git tag -a v1.0.1 -m "Release v1.0.1 - Critical fixes"
git push origin v1.0.1
```
