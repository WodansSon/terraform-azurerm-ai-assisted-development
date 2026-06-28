# Creating a New Release

This document describes how to create a new release of the Terraform AzureRM AI-Assisted Development tools.

## Release Process

### 1. Finalize the `Unreleased` changelog entry on your branch

Before opening the release PR, make sure the current `## [Unreleased]` section in `CHANGELOG.md` reads like final release notes rather than patch-history notes and still follows the current grouped taxonomy structure.

When you are actually cutting the release, move those `Unreleased` notes into a new versioned changelog section with the header pattern `## [X.Y.Z] - YYYY-MM-DD`, using the same grouped taxonomy shape:

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
- commit that changelog-only release cut on `main` before creating the tag
- use the established commit-subject pattern `Prepare X.Y.Z changelog`, for example `Prepare X.Y.Z changelog`
- create and push the `vX.Y.Z` tag only after that changelog commit is present on `main`

### 2. Validate the branch before opening the PR

Before opening the release PR, run the normal maintainer validation flow from the branch:

```powershell
pwsh -NoProfile -File ./tools/validate-ai-toolkit.ps1
```

Recommended pre-PR maintainer smoke:

- run a bootstrap install from the working tree so the user-profile installer is refreshed from the branch
- confirm the branch still installs correctly through the bootstrap path
- build a release-shaped installer bundle locally with `tools/build-release-bundle_dry_run.ps1`
- run one install smoke from that dry-run bundle before cutting any public release

The bootstrap check confirms the contributor path, while the dry-run release bundle confirms the release-artifact path without publishing anything publicly.

Example dry-run bundle command:

```powershell
pwsh -NoProfile -File ./tools/build-release-bundle_dry_run.ps1 -Version 9.9.9 -OutputRoot "$env:TEMP\azurerm-ai-release-dry-run" -Force
```

Maintainer note:

- the standalone installer version commands (`-Version` in PowerShell and `--version` in Bash) read stamped bundle metadata rather than recomputing provenance at runtime
- a plain source checkout can therefore show `Unavailable` for the support metadata block, because those fields are stamped only during bootstrap or release-bundle assembly
- validate support output from the bootstrapped installer copy or the dry-run/release-shaped bundle, not from a raw source checkout

### 3. Open and merge the release PR to `main`

The normal workflow is PR-based.

- open a pull request with the finalized changelog and release-ready changes
- review and merge that PR into `main`
- do not tag the release from an unmerged feature branch

Release tags should be created from the merged `main` state.

### 4. Create and push the tag from `main`

After the release PR is merged, update your local `main` and create the release tag from that merged state:

```bash
git checkout main
git pull --ff-only origin main

# Create the tag (must follow v*.*.* pattern)
git tag -a v1.0.0 -m "Release v1.0.0"

# Push the tag to GitHub
git push origin v1.0.0
```

### 5. GitHub Actions Automatic Build

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

### 6. Verify the Release

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

### 7. Verify Release Provenance

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

## Testing a Release

Before creating an official release, build and test a local release-shaped bundle first:

```powershell
pwsh -NoProfile -File ./tools/build-release-bundle_dry_run.ps1 -Version 9.9.9 -OutputRoot "$env:TEMP\azurerm-ai-release-dry-run" -Force
```

That dry run:

- stages the same installer layout as the release workflow
- stamps `VERSION`, `commit`, and `aii.checksum`
- verifies the staged bundle checksum
- creates the same ZIP and TAR.GZ installer archives without publishing them

After the dry run succeeds, run one installer smoke from the staged bundle against a local `terraform-provider-azurerm` checkout.

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

- the bootstrap install is still the pre-release maintainer smoke for the contributor path
- the dry-run release bundle is the pre-release maintainer smoke for the release-artifact path
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
