# Creating a New Release

This document describes how to create a new release of the Terraform AzureRM AI-Assisted Development tools.

## Release Process

### 1. Update the CHANGELOG.md

Add a new section at the top of `CHANGELOG.md` with the version number and changes:

```markdown
## [1.0.0] - 2025-10-21

### Added
- Initial release of AI-assisted development tools
- Installation scripts for Windows and Linux/macOS
- Comprehensive instruction files for provider development

### Changed
- Updated installer to bundle all required modules

### Fixed
- Fixed line endings in bash scripts
```

### 2. Commit the CHANGELOG

```bash
git add CHANGELOG.md
git commit -m "Prepare release v1.0.0"
git push origin main
```

### 3. Create and Push the Tag

```bash
# Create the tag (must follow v*.*.* pattern)
git tag -a v1.0.0 -m "Release v1.0.0"

# Push the tag to GitHub
git push origin v1.0.0
```

### 4. GitHub Actions Automatic Build

The GitHub Actions workflow (`.github/workflows/release.yml`) will automatically:

1. ✅ Extract changelog for this version
2. ✅ Create installer bundle directory structure
3. ✅ Copy all installer files and modules
4. ✅ Create ZIP archive for Windows users
5. ✅ Create TAR.GZ archive for Linux/macOS users
6. ✅ Create full source archive
7. ✅ Generate SHA256 checksums
8. ✅ Create GitHub Release with all artifacts
9. ✅ Include installation instructions in release notes

### 5. Verify the Release

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
- [ ] Release notes include installation instructions
- [ ] Changelog is properly extracted

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

## Testing a Release

Before creating an official release, you can test locally:

```bash
# Create a test tag
git tag -a v0.0.1-test -m "Test release"

# Push to test the workflow
git push origin v0.0.1-test

# Delete test release and tag after verification
git push --delete origin v0.0.1-test
git tag -d v0.0.1-test
```

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

1. ✅ Test installation on Windows
2. ✅ Test installation on Linux/macOS
3. ✅ Update README if needed
4. ✅ Announce release (if applicable)
5. ✅ Monitor for issues

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
