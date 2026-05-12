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

### 3.5. Verify release metadata variables

Before pushing the release tag, ensure these repository variables are configured for the workflow:

- `PLAYGROUND_PLUGIN_AUTHOR_NAME`
- `PLAYGROUND_PLUGIN_AUTHOR_EMAIL`

These values are used to stamp the Playground plugin manifest during release packaging.

Use repository variables rather than secrets here. The stamped author name and email are public release metadata that ship inside the released source archive, so secrets do not provide a practical confidentiality benefit.

### 4. GitHub Actions Automatic Build

The GitHub Actions workflow (`.github/workflows/release.yml`) will automatically:

- ✅ Extract changelog for this version
- ✅ Stamp the Playground plugin manifest version from the release tag
- ✅ Stamp the Playground plugin manifest author metadata from repository variables
- ✅ Verify the stamped Playground plugin manifest values
- ✅ Materialize the generated Playground plugin payload
- ✅ Create installer bundle directory structure
- ✅ Copy all installer files and modules
- ✅ Create ZIP archive for Windows users
- ✅ Create TAR.GZ archive for Linux/macOS users
- ✅ Create a versioned Playground plugin publication package
- ✅ Create full source archive
- ✅ Generate SHA256 checksums
- ✅ Generate GitHub artifact attestations for the release assets and checksum manifest
- ✅ Create GitHub Release with all artifacts
- ✅ Include installation and provenance verification instructions in release notes

### 5. Verify the Release

Visit: `https://github.com/WodansSon/terraform-azurerm-ai-assisted-development/releases`

Check that:
- [ ] Release was created successfully
- [ ] All assets are attached:
  - `terraform-azurerm-ai-installer.zip` (Windows, stable name for `releases/latest/download/`)
  - `terraform-azurerm-ai-installer.tar.gz` (Linux/macOS, stable name for `releases/latest/download/`)
  - `terraform-azurerm-ai-installer-v*.*.*.zip` (Windows, versioned)
  - `terraform-azurerm-ai-installer-v*.*.*.tar.gz` (Linux/macOS, versioned)
  - `terraform-azurerm-ai-toolkit-playground-v*.*.*.zip` (Playground publication package)
  - `terraform-azurerm-ai-assisted-development-v*.*.*.tar.gz` (Full source)
  - `checksums.txt`
- [ ] Artifact attestations exist for the release assets and `checksums.txt`
- [ ] Release notes include installation instructions
- [ ] Release notes include the manual Playground publication package handoff
- [ ] Release notes include `gh attestation verify` examples
- [ ] Changelog is properly extracted

### 6. Verify Release Provenance

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

### Playground Publication Package

- **`terraform-azurerm-ai-toolkit-playground-v*.*.*.zip`**
  - Contains a `plugins/terraform-azurerm-ai-toolkit/` tree ready for manual import into a personal user branch in `agency-microsoft/playground`
  - Includes the stamped plugin manifest, agents, README, and committed-review scope helper under the plugin directory
  - Intended for contributor publication, not end-user installation

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

### Local Copilot CLI Smoke Test For The Plugin

Before publishing the Playground package, you can verify that GitHub Copilot CLI loads this repository's local plugin adapter directly from disk.

Use this flow from the repository root:

```powershell
pwsh -NoProfile -File ./tools/playground-plugin/validate-plugin.ps1
copilot --plugin-dir .\plugins\terraform-azurerm-ai-toolkit --allow-all-tools
```

Inside the interactive Copilot CLI session:

```text
/env
/agent
```

What to verify:

- `/env` should report that a plugin is loaded for the session.
- `/agent` should show these plugin agents:
  - `review-local`
  - `review-committed`
  - `review-docs`

After confirming the agents are present, select one of them in `/agent` and run a real smoke-test prompt with explicit inputs.

Example local-review smoke test:

```text
repo_path: C:\github.com\WodansSon\terraform-azurerm-ai-assisted-development
diff_scope: worktree
Review the current local changes.
```

Deterministic plugin verification versus ordinary prompt behavior:

- If the session startup or `/env` reports `1 plugin` and `/agent` lists the three review agents above, you are exercising the local plugin adapter rather than only the repository prompt/instruction files.
- If you start Copilot CLI without `--plugin-dir .\plugins\terraform-azurerm-ai-toolkit`, the repository instructions may still load, but the plugin-specific review agents should not appear.
- Treat the presence of those three agents as the deterministic proof that the plugin adapter is loaded.

Current limitation observed on this branch:

- Interactive mode works for local plugin smoke testing.
- Non-interactive prompt mode with `-p --agent review-local` did not resolve the plugin agent in the current Copilot CLI build, so use interactive mode for contributor verification.

### Clean Staged Install Test For The Plugin

If you want to test a plugin install that is closer to the package shape later imported into Playground, stage a clean standalone plugin tree first and install from that staged output.

Use this flow from the repository root:

```powershell
pwsh -NoProfile -File ./tools/playground-plugin/export-plugin.ps1 -Clean
copilot plugin install ./plugins/terraform-azurerm-ai-toolkit/export/staged/terraform-azurerm-ai-toolkit
```

Optional zip generation for inspection:

```powershell
pwsh -NoProfile -File ./tools/playground-plugin/export-plugin.ps1 -Clean -Zip
```

Why this helps:

- it installs from a clean exported plugin tree instead of the live working copy
- it is closer to the plugin directory shape later packaged for manual Playground publication
- it reduces the chance that local repository-only files or transient edits affect the install test

### Local Marketplace Install Test For The Plugin

Because direct local plugin installs are deprecated in Copilot CLI, the preferred longer-term smoke test is a local marketplace install backed by the staged plugin export.

Use this flow from the repository root:

```powershell
pwsh -NoProfile -File ./tools/playground-plugin/export-plugin.ps1 -Clean
copilot plugin marketplace add ./plugins/terraform-azurerm-ai-toolkit/export/staged
copilot plugin install terraform-azurerm-ai-toolkit@terraform-azurerm-ai-toolkit-local
```

Why this is closer to the real release path:

- it uses `plugin@marketplace` syntax instead of deprecated direct-path install syntax
- it resolves plugin metadata through a marketplace manifest
- it still avoids requiring a public Agency publication for routine contributor testing

### One-Command Contributor Smoke Test

For contributor testing, prefer the helper below instead of manually remembering the staged export and marketplace refresh sequence:

```powershell
pwsh -NoProfile -File ./tools/playground-plugin/test-staged-plugin.ps1
```

If you intend to publish or update the plugin in the Agency Playground repository, treat this helper and a real CLI smoke test as the required pre-publication check before pushing the plugin update to your Playground branch or opening the Playground PR.

That helper automatically:

- stages the clean plugin export
- uninstalls any existing local `terraform-azurerm-ai-toolkit` plugin install when present
- removes any existing `terraform-azurerm-ai-toolkit-local` marketplace registration when present
- re-adds the staged local marketplace
- reinstalls the plugin through `plugin@marketplace` syntax

Optional:

```powershell
pwsh -NoProfile -File ./tools/playground-plugin/test-staged-plugin.ps1 -StartCli
```

Use `-StartCli` when you want the helper to immediately open a fresh Copilot CLI session after the marketplace reinstall completes.

Recommended pre-publication flow:

1. Run `pwsh -NoProfile -File ./tools/playground-plugin/test-staged-plugin.ps1 -StartCli`.
2. In the fresh CLI session, confirm the plugin agents appear in `/agent`.
3. Run at least one real review smoke test through the installed CLI plugin.
4. Only then push the plugin package update to the Agency Playground repository or open/update the Playground PR.

Smoke-test guidance:

- When practical, run `copilot` from the target repository root you are validating.
- For `review-local` and `review-committed`, always provide `repo_path` explicitly so the agent resolves scope against the intended repository.
- When the local checkout is a fork but the PR belongs to an upstream repository, provide `pr_repo: <owner/repo>` explicitly so the CLI resolves PR scope against the authoritative GitHub repository instead of the local fork owner.
- Do not hard-code a specific PR number in the contributor instructions; use the current PR you are validating, or use `review-local` against a known local diff.
- If `review-committed` with an explicit `pr_number` cannot prove it is using that PR's authoritative GitHub changed-file set, treat that run as failed and do not trust fallback output.
- The CLI `review-committed` adapter does not support branch fallback or `revision_range`; use `review-local` for branch/worktree audits and reserve `review-committed` for authoritative PR-scoped review.
- If the CLI tries to reopen `%LOCALAPPDATA%\Temp\*copilot-tool-output*.txt` or similar temp files to extract PR changed files, treat that run as failed; the changed-file list must come directly from the authoritative GitHub PR result.
- If the CLI asks to read user-profile caches, `workspaceStorage`, or other out-of-workspace local state to infer PR scope, deny that path and treat the run as failed rather than letting the review drift onto ambiguous local state.

The normal committed-review prompt can usually be just:

```text
repo_path: <local clone path of the repo being reviewed>
Review the committed changes.
```

If live PR context is ambiguous, pin the target explicitly:

```text
repo_path: <local clone path of the repo being reviewed>
pr_repo: <authoritative github repo for the pr, for example hashicorp/terraform-provider-azurerm>
pr_number: <current_pr_number>
Review the committed changes.
```

Example committed-review smoke test input:

```text
repo_path: <local clone path of the repo being reviewed>
Review the committed changes.
```

Example committed-review scope debug input:

```text
repo_path: <local clone path of the repo being reviewed>
debug_scope: true
Summarize the normalized committed-review scope and stop.
```

Use `debug_scope: true` when the CLI committed-review agent appears to disagree with the VS Code prompt about the review scope. The CLI agent should emit only its normalized live scope summary so you can compare the repo root, authoritative PR repo, PR number, changed-file count, vendored-file count, and changed-file list before trusting the review body.

Optional explicit form when you want to pin every field:

```text
repo_path: <local clone path of the repo being reviewed>
pr_repo: <authoritative github repo for the pr, for example hashicorp/terraform-provider-azurerm>
pr_number: <current_pr_number>
Review the committed changes.
```

Example local-review smoke test input:

```text
repo_path: <local clone path of the repo being reviewed>
diff_scope: worktree
Review the current local changes.
```

## Troubleshooting

### Release workflow failed

- Check GitHub Actions tab
- Review workflow logs
- Common issues:
   - Missing files in `installer/` directory
   - CHANGELOG.md format issues
   - Permissions issues

### Release created but assets missing

- Check workflow completed successfully
- Verify all build steps passed
- Re-run the workflow if needed

## Post-Release Tasks

After creating a release:

- ✅ Test installation on Windows
- ✅ Test installation on Linux/macOS
- ✅ Download `terraform-azurerm-ai-toolkit-playground-v*.*.*.zip`
- ✅ Check out your personal Playground user branch (`users/<alias>/<feature-name>`)
- ✅ Extract the package from the Playground repository root so it restores `plugins/terraform-azurerm-ai-toolkit/`
- ✅ Run Playground validation, marketplace sync preview, and any required integrity/security checks
- ✅ Commit and push the user branch update
- ✅ Open a PR from your user branch to `main` in `agency-microsoft/playground`
- ✅ Update README if needed
- ✅ Announce release (if applicable)
- ✅ Monitor for issues

### Manual Playground Publication Checklist

After the release is published in this repository:

- Download `terraform-azurerm-ai-toolkit-playground-vX.Y.Z.zip` from the release page.
- Open your local `agency-microsoft/playground` clone.
- Create or switch to your user branch:

```bash
git checkout -b users/<your-alias>/publish-terraform-azurerm-ai-toolkit-vX.Y.Z
```

- Extract the package from the Playground repository root so the files land under `plugins/terraform-azurerm-ai-toolkit/`.
- Run the Playground-side checks expected by that repository, for example:

```bash
python scripts/sync-marketplace.py --preview
python scripts/security_scanner.py plugins/terraform-azurerm-ai-toolkit --verbose
```

- Generate or refresh `INTEGRITY.json` if you decide to include integrity attestation in the Playground plugin submission.
- Commit the plugin update, push the branch, and open a PR to `main`.

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
