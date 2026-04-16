<picture>
  <source media="(prefers-color-scheme: dark)" srcset="../.github/troubleshootingTitle-dark.png">
  <source media="(prefers-color-scheme: light)" srcset="../.github/troubleshootingTitle-light.png">
  <img src="../.github/troubleshootingTitle-light.png" alt="AI-Assisted Development Troubleshooting" width="900" height="80">
</picture>

> **Solutions and diagnostics for common issues in AI-powered development workflows**
##
Common issues and solutions for the Terraform AzureRM AI-Assisted Development toolkit.

## Table of Contents

- [Installation Issues](#installation-issues)
- [Copilot Not Using Instructions](#copilot-not-using-instructions)
- [Performance Issues](#performance-issues)
- [Code Generation Issues](#code-generation-issues)
- [Platform-Specific Issues](#platform-specific-issues)

---

## Installation Issues

### PowerShell Execution Policy Error (Windows)

**Error**:
```
install-copilot-setup.ps1 cannot be loaded because running scripts is disabled on this system
```

**Solution**:
```powershell
# Option 1: Bypass for this session
Set-ExecutionPolicy -ExecutionPolicy Bypass -Scope Process

# Option 2: Set for current user (recommended)
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser

# Then run the installer
& "$env:USERPROFILE\.terraform-azurerm-ai-installer\install-copilot-setup.ps1" -Help
```

---

### Installer Can't Find Repository

**Error**:
```
Error: Could not locate terraform-provider-azurerm repository
```

**Solution**:
```powershell
# Specify the repository path explicitly
.\install-copilot-setup.ps1 -RepoDirectory "C:\path\to\terraform-provider-azurerm"
```

---

### Origin Remote Not Configured

**Error**:
```
Git repository has no origin remote configured
```

**Cause**:
The target directory is not a cloned `terraform-provider-azurerm` repository, or the `origin` remote was removed.

**Solution**:
```bash
# Option 1: clone the official repo (recommended)
git clone https://github.com/hashicorp/terraform-provider-azurerm.git

# Option 2: add an origin remote to your existing clone
git remote add origin https://github.com/hashicorp/terraform-provider-azurerm.git
```

---

### AI Development Repo Is Not a Target

**Error**:
```
Target directory is the AI development repository, not a Terraform provider repository
```

**Cause**:
The AI-assisted development repo is a source workspace only. It is not a valid install target.

**Solution**:
```powershell
# Install into your terraform-provider-azurerm working copy instead
& "$env:USERPROFILE\.terraform-azurerm-ai-installer\install-copilot-setup.ps1" -RepoDirectory "C:\path\to\terraform-provider-azurerm"
```

---

### Installer Configuration Validation Failed / Payload Missing

This happens when the installer cannot load the required local files (manifest and/or the bundled offline payload).

Common causes:
- The installer directory is incomplete (missing `file-manifest.config`, missing `modules/`, or missing `aii/`).
- The release bundle was not extracted correctly into the expected user profile directory.
- You are running a stale user-profile installer that predates the offline payload model.

**Fix options:**
- **Recommended**: re-extract the latest release bundle into your user profile directory.
- **Contributor/dev**: run `-Bootstrap` / `-bootstrap` from a git clone to refresh your user-profile installer (this also stages the payload).
- **Override**: use `-LocalPath` / `-local-path` to source AI files from a local working tree instead of the bundled payload.

> [!IMPORTANT]
> The commands below assume the installer in your user profile is up-to-date (v2.0.0+).
> If you have an older `~/.terraform-azurerm-ai-installer` / `%USERPROFILE%\.terraform-azurerm-ai-installer` from a previous release, step (2) may fail or behave differently.
> Always run step (1) first (or re-extract the latest release bundle) before running the installer from your user profile.

**Solution (PowerShell):**
```powershell
# 1) (Preferred) Re-extract the latest release bundle into your user profile.
#    OR (Contributor) refresh the user-profile installer from your local clone.
& "C:\path\to\terraform-azurerm-ai-assisted-development\installer\install-copilot-setup.ps1" -Bootstrap

# 2) Run the installer from your user profile.
#    Default behavior uses the bundled payload (aii/); no -LocalPath is required.
cd "$env:USERPROFILE\.terraform-azurerm-ai-installer"
.\install-copilot-setup.ps1 -RepoDirectory "C:\path\to\terraform-provider-azurerm"

# Optional contributor override (source from working tree instead of payload):
# .\install-copilot-setup.ps1 -LocalPath "C:\path\to\terraform-azurerm-ai-assisted-development" -RepoDirectory "C:\path\to\terraform-provider-azurerm"
```

**Solution (Bash):**
```bash
# 1) (Preferred) Re-extract the latest release bundle into your user profile.
#    OR (Contributor) refresh the user-profile installer from your local clone.
"/path/to/terraform-azurerm-ai-assisted-development/installer/install-copilot-setup.sh" -bootstrap

# 2) Run the installer from your user profile.
#    Default behavior uses the bundled payload (aii/); no -local-path is required.
cd ~/.terraform-azurerm-ai-installer
./install-copilot-setup.sh -repo-directory "/path/to/terraform-provider-azurerm"

# Optional contributor override (source from working tree instead of payload):
# ./install-copilot-setup.sh -local-path "/path/to/terraform-azurerm-ai-assisted-development" -repo-directory "/path/to/terraform-provider-azurerm"
```

---

### Installer Payload Checksum Failed

**Error**:
```
Installer payload checksum validation failed
```

**Cause**:
The installer payload (`aii/`) and manifest are out of sync (stale or modified installer directory).

**Fix options:**
- **Recommended**: re-extract the latest release bundle into your user profile directory.
- **Contributor/dev**: re-run `-Bootstrap` / `-bootstrap` from a git clone to refresh the user-profile installer.

**Important**:
- `aii.checksum` verifies extracted bundle integrity.
- It does not prove that the downloaded release asset came from the official repository release workflow.

---

### How Do I Verify That I Downloaded an Official Release Asset?

Use GitHub artifact attestations for the downloaded release asset before extraction:

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

What each layer means:
- GitHub attestation verification: proves the release asset was produced by the canonical release workflow for this repository and tag.
- `checksums.txt`: verifies the downloaded release asset bytes match the published digest.
- `aii.checksum`: verifies the extracted installer bundle contents are internally consistent.

How to run it correctly:
- Run `gh attestation verify` against the downloaded archive file, not the extracted installer directory.
- Ensure GitHub CLI is authenticated to `github.com` before verifying.
- On Windows PowerShell, verify the same stable-name `.zip` file you passed to `Expand-Archive`.
- On Bash, verify the same archive file you downloaded with `curl`.

What success looks like:
- The digest for the local archive loads successfully.
- GitHub loads one or more attestations from the API.
- The command ends with `Verification succeeded!`.
- The matching attestations show `.github/workflows/release.yml@refs/tags/vX.Y.Z` as the build and signer workflow.
- Multiple matching attestations can be expected when the stable-name and versioned release assets have the same digest.

**Trust model limits**:
- Attestation verification is only meaningful if you verify against the canonical signer identity: `WodansSon/terraform-azurerm-ai-assisted-development` and `.github/workflows/release.yml`.
- A spoofed or cloned repository can publish its own docs, checksums, and attestations for its own identity.
- That means end users still need to know they started from the canonical repository before trusting the verification command.

If attestation verification fails:
- Do not extract or run the installer.
- Re-download the pinned asset from the canonical release page.
- Confirm that the repository owner, workflow path, and tag match the expected release.

---

### `gh attestation verify` Returns `HTTP 401: Bad credentials`

**Symptoms**:
- The release archive path is correct and the digest loads successfully
- `gh attestation verify` fails while loading attestations from the GitHub API with `HTTP 401: Bad credentials`

**Cause**:
- GitHub CLI is not authenticated correctly to `github.com`, or
- a stale `GH_TOKEN` / `GITHUB_TOKEN` environment variable is overriding your normal `gh` login

**Fixes**:
- Check your current GitHub CLI authentication state:

```bash
gh auth status
```

- In PowerShell, clear any overriding auth environment variables for the current shell:

```powershell
Remove-Item Env:GH_TOKEN -ErrorAction SilentlyContinue
Remove-Item Env:GITHUB_TOKEN -ErrorAction SilentlyContinue
```

- Reauthenticate GitHub CLI to `github.com`:

```bash
gh auth login -h github.com -w
```

- Rerun `gh attestation verify` against the downloaded archive file.


### Verify Shows Missing Files After Clean

`-Verify` / `-verify` has two modes:

- **Bundle self-check (no repo directory):** verifies the installer bundle in your user profile (manifest/modules/payload/checksum).
- **Target repo verification (with repo directory):** checks whether the AI infrastructure is present in the target repository.

`-Verify -RepoDirectory` / `-verify -repo-directory` hard-fails if the repo directory points at the installer source repository, to prevent false-positive verification.

After running `-Clean` / `-clean`, missing files and directories are expected.

If you want to confirm cleanup, check that:
- `.github/instructions/`, `.github/prompts/`, and `.github/skills/` are removed when empty.
- `.vscode/` remains (repository-standard), but `.vscode/settings.json` is removed.

---

### Permission Denied (macOS/Linux)

**Error**:
```
Permission denied: ./install-copilot-setup.sh
```

**Solution**:
```bash
# Make the script executable
chmod +x install-copilot-setup.sh

# Then run it
./install-copilot-setup.sh -help
```

---

### Positional Parameter Error (Windows)

**Error**:
```
A positional parameter cannot be found that accepts argument 'settings.json'
```

**Cause**:
The installer **must** be extracted to your user profile directory (`$env:USERPROFILE\.terraform-azurerm-ai-installer\` on Windows or `~/.terraform-azurerm-ai-installer/` on macOS/Linux). Running the installer from arbitrary directories (like Downloads or Desktop) can cause directory traversal errors because the installer expects a specific directory structure.

**Solution**:
```powershell
# Windows - Extract to the correct location
Invoke-WebRequest -Uri "https://github.com/WodansSon/terraform-azurerm-ai-assisted-development/releases/latest/download/terraform-azurerm-ai-installer.zip" -OutFile "$env:TEMP\terraform-azurerm-ai-installer.zip"
Expand-Archive -Path "$env:TEMP\terraform-azurerm-ai-installer.zip" -DestinationPath "$env:USERPROFILE" -Force

# Then run from the correct location
& "$env:USERPROFILE\.terraform-azurerm-ai-installer\install-copilot-setup.ps1" -RepoDirectory "C:\path\to\terraform-provider-azurerm"
```

> [!NOTE]
> **Install a specific version (pinning)**: replace `latest/download` with a tagged release URL (`download/vX.Y.Z`).
>
> The version is the `vX.Y.Z` segment in the URL path. The filename can be either the stable (unversioned) asset name or the versioned asset name.
>
> - Example pinned URL (stable filename):
>   - `https://github.com/WodansSon/terraform-azurerm-ai-assisted-development/releases/download/v1.0.1/terraform-azurerm-ai-installer.zip`
> - Example pinned URL (versioned filename):
>   - `https://github.com/WodansSon/terraform-azurerm-ai-assisted-development/releases/download/v1.0.1/terraform-azurerm-ai-installer-v1.0.1.zip`

```bash
# macOS/Linux - Extract to the correct location
curl -L -o /tmp/terraform-azurerm-ai-installer.tar.gz "https://github.com/WodansSon/terraform-azurerm-ai-assisted-development/releases/latest/download/terraform-azurerm-ai-installer.tar.gz"
tar -xzf /tmp/terraform-azurerm-ai-installer.tar.gz -C ~/

# Then run from the correct location
~/.terraform-azurerm-ai-installer/install-copilot-setup.sh -repo-directory "/path/to/terraform-provider-azurerm"
```

> [!NOTE]
> **Install a specific version (pinning)**: replace `latest/download` with a tagged release URL (`download/vX.Y.Z`).
>
> The version is the `vX.Y.Z` segment in the URL path. The filename can be either the stable (unversioned) asset name or the versioned asset name.
>
> - Example pinned URL (stable filename):
>   - `https://github.com/WodansSon/terraform-azurerm-ai-assisted-development/releases/download/v1.0.1/terraform-azurerm-ai-installer.tar.gz`
> - Example pinned URL (versioned filename):
>   - `https://github.com/WodansSon/terraform-azurerm-ai-assisted-development/releases/download/v1.0.1/terraform-azurerm-ai-installer-v1.0.1.tar.gz`

**Why This Matters**:
- The installer needs a clean, isolated directory structure
- Running from arbitrary locations can cause file conflicts
- Module loading depends on predictable relative paths
- The user profile location ensures consistent behavior across runs

---

### Files Already Exist Warning

**Warning**:
```
Warning: Files already exist in target directory. Creating backup...
```

**What It Means**:
You have existing Copilot instructions. The installer creates backups automatically.

**To Review Backups**:
- Windows: `%USERPROFILE%\.vscode\copilot\backups\`
- macOS/Linux: `~/.vscode/copilot/backups/`

---

## Copilot Not Using Instructions

### Instructions Not Loading

**Symptoms**:
- Copilot generates code that doesn't follow provider patterns
- No mention of HashiCorp standards in responses
- Generic Go code instead of Terraform-specific

**Check 1**: Verify Installation
```powershell
# Windows
dir $env:USERPROFILE\.vscode\copilot\instructions

# macOS/Linux
ls -la ~/.vscode/copilot/instructions
```

You should see multiple `.instructions.md` files.

**Check 2**: Restart VS Code
Close and reopen VS Code completely (not just reload window).

**Check 3**: Verify Workspace
Make sure you're in a workspace that contains Go files in the `internal/` directory.

**Check 4**: Check GitHub Copilot Settings
1. Open VS Code Settings
2. Search for "Copilot"
3. Ensure "GitHub > Copilot: Enable" is checked

---

### Instructions Not Applied to Specific Files

**Issue**: Instructions work in some files but not others

**Solution**: Check the `applyTo` pattern in `copilot-instructions.md`:
```yaml
---
applyTo: "internal/**/*.go"
---
```

This applies instructions only to Go files in the `internal/` directory.

---

### Copilot Gives Generic Answers

**Problem**: Copilot isn't using workspace-specific knowledge

**Solutions**:

1. **Be explicit in your prompts**:
   ```
   ❌ "Create a resource"
   ✅ "Create a resource following terraform-provider-azurerm patterns"
   ```

2. **Reference the instructions**:
   ```
   ✅ "Use the typed SDK implementation pattern from the instructions"
   ```

3. **Open relevant files**:
   - Open examples of similar resources
   - Open instruction files from `.github/instructions/` directory
   - Open skill files from `.github/skills/` directory
   - Copilot uses open files for context

---

### `/code-review-docs` Keeps Finding the Same Issues After Applying Fixes

**Symptoms**:
- You run `/code-review-docs`, apply the suggested patch-ready fixes, then rerun and see the same Issues again
- The prompt output varies run-to-run (for example it suggests different "fix strategies")

**Checks**:
1. **Confirm the active editor is the doc page** under `website/docs/**` (not a prompt file).
2. **Update your installed AI files**:
   - Normal users: re-extract the latest release bundle to your user profile installer directory
   - Contributors: re-run `-Bootstrap` from a git clone to refresh the user-profile installer
3. **Reinstall into the target repo** (from your user profile installer directory), then rerun `/code-review-docs`.
4. **Restart VS Code** to ensure updated prompts/skills are loaded.

---

### `/code-review-committed-changes` Reports That No Valid PR Could Be Determined

**Symptoms**:
- You run `/code-review-committed-changes` and the linter subsection reports `Not run`
- The summary says no valid PR could be determined for the branch changes

**Cause**:
- The committed review prompt now prefers PR-scoped linter execution.
- Copilot did not have explicit PR context for the current branch, and no PR number was supplied in the command invocation.

**Fixes**:
- **Create or open a draft PR** for the branch, then rerun `/code-review-committed-changes`.
- **Pass the PR number explicitly** when you run the committed review prompt:

```text
/code-review-committed-changes PR 12345
```

- **Confirm the linter is installed locally** if the section still reports `Not run` for availability reasons:

```bash
go install github.com/qixialu/azurerm-linter@latest
```

**Notes**:
- `/code-review-local-changes` does not require PR context and continues to use local-diff linting.
- The committed review prompt does not guess PR numbers from branch names or git history.
- The prompt-side linter flow requires a local `v0.2.0` or newer `azurerm-linter` binary from the [QixiaLu/azurerm-linter](https://github.com/QixiaLu/azurerm-linter) repo for JSON-mode review. The expected review-time command is the plain local CLI from the repo root on every platform, including Windows, and it should not be rewritten through WSL or another shell wrapper.

---

### Review Prompts Still Ask Approval for `git rev-parse --show-toplevel`

**Symptoms**:
- `/code-review-local-changes` or `/code-review-committed-changes` still prompts for approval before running the repo-root lookup command
- The command shown is `git rev-parse --show-toplevel`

**Cause**:
- Terminal approval is controlled by VS Code/Copilot security settings.
- Prompt text can reduce agent narration, but it cannot override terminal approval by itself.

**Optional fix**:
Add a narrow allowlist entry to your VS Code user `settings.json`:

```jsonc
"chat.tools.terminal.autoApprove": {
   "/^git rev-parse --show-toplevel$/": true
}
```

This auto-approves only the read-only repo-root command used by the review prompts.

**Notes**:
- This does not broadly approve `git` commands.
- Organization policy or other approval settings can still override local settings.
- If you want to approve more commands, add them deliberately and narrowly.

---

## Performance Issues

### Copilot Slow to Respond

**Causes**:
- Large workspace with many files
- Too many open tabs
- Network latency

**Solutions**:

1. **Close unused tabs**: Keep only relevant files open

2. **Use workspace search scope**:
   ```
   Configure .vscode/settings.json:
   {
     "search.exclude": {
       "**/vendor": true,
       "**/examples": true
     }
   }
   ```

3. **Clear Copilot cache**:
   - Open Command Palette (Ctrl+Shift+P / Cmd+Shift+P)
   - Run "GitHub Copilot: Clear Cache"

---

### High Memory Usage

**Issue**: VS Code using excessive memory

**Solutions**:

1. **Limit file watchers**:
   ```json
   {
     "files.watcherExclude": {
       "**/.git/**": true,
       "**/vendor/**": true,
       "**/node_modules/**": true
     }
   }
   ```

2. **Disable extensions temporarily**: Test with only Copilot enabled

---

## Code Generation Issues

### Generated Code Doesn't Compile

**Common Causes**:

1. **Missing imports**: Add them manually or use Go extension's organize imports
2. **Wrong package name**: Ensure file is in correct directory
3. **Type mismatches**: Review Azure SDK types being used

**Solution Pattern**:
```go
// Ask Copilot to fix:
"Fix the compilation errors in this function following provider patterns"
```

---

### Generated Tests Fail

**Common Issues**:

1. **Test data not random**:
   ```go
   // Ensure using acceptance.BuildTestData
   data := acceptance.BuildTestData(t, "azurerm_resource_name", "test")
   ```

2. **Missing test dependencies**:
   ```go
   // Check requires block
   data.ResourceTest(t, r, []acceptance.TestStep{
       {
           Config: r.basic(data),
           Check: acceptance.ComposeTestCheckFunc(
               check.That(data.ResourceName).ExistsInAzure(r),
           ),
       },
   })
   ```

3. **Resource cleanup issues**: Ensure proper destroy checks

---

### Inconsistent Code Style

**Issue**: Generated code doesn't match provider style

**Solutions**:

1. **Run formatter**:
   ```bash
   gofmt -w internal/services/yourservice/
   ```

2. **Ask for specific patterns**:
   ```
   "Refactor this to match the pattern used in azurerm_cdn_profile"
   ```

---

### Docs scaffolding outputs to `website_scaffold_tmp`

**Symptom**: After using `/docs-writer` (or the website scaffold tool), the generated docs land under `website_scaffold_tmp/docs/...` instead of `website/docs/...`.

**Cause**: You are in a scaffold/dry-run workflow (or explicitly requested scratch output). The docs-writer skill can scaffold into `website_scaffold_tmp` to avoid overwriting real docs.

**Fix**:
- If you are updating an existing docs page and want normal behavior, ask it to **edit the existing docs file in place** and avoid requesting scaffolding/dry-run output.
- If you intended a dry run, keep using the scratch output and diff it against the real docs:
   - Resource: `git diff --no-index website_scaffold_tmp/docs/r/<name>.html.markdown website/docs/r/<name>.html.markdown`
   - Data source: `git diff --no-index website_scaffold_tmp/docs/d/<name>.html.markdown website/docs/d/<name>.html.markdown`
- If you are creating a brand-new docs page and want the real page created under `website/docs/**`, explicitly say you are **not** doing a dry run and ask it to scaffold/create the docs page in the real website root.

---

## Platform-Specific Issues

### Windows: Path Length Limitations

**Error**:
```
The specified path is too long
```

**Solution**:
1. Enable long path support:
   ```powershell
   # Run as Administrator
   New-ItemProperty -Path "HKLM:\SYSTEM\CurrentControlSet\Control\FileSystem" -Name "LongPathsEnabled" -Value 1 -PropertyType DWORD -Force
   ```

2. Or use shorter workspace paths

---

### macOS: Gatekeeper Blocking Script

**Error**:
```
"install-copilot-setup.sh" cannot be opened because it is from an unidentified developer
```

**Solution**:
```bash
# Remove quarantine attribute
xattr -d com.apple.quarantine install-copilot-setup.sh

# Or run with explicit bypass
bash ./install-copilot-setup.sh -bootstrap
```

---

### Linux: Missing Dependencies

**Error**: Command not found during installation

**Solution**:
```bash
# Ubuntu/Debian
sudo apt-get update
sudo apt-get install curl jq

# RHEL/CentOS
sudo yum install curl jq

# Arch
sudo pacman -S curl jq
```

---

## Still Having Issues?

### 1. Enable Debug Logging

**VS Code**:
1. Open Settings (Ctrl+, / Cmd+,)
2. Search for "Copilot Log"
3. Set "GitHub > Copilot: Log Level" to "debug"
4. Check Output panel > GitHub Copilot

**Installer**:
```powershell
# Optional: PowerShell script-level tracing (very verbose)
# Set-PSDebug -Trace 1; .\install-copilot-setup.ps1 -Help; Set-PSDebug -Off
```

```bash
# Optional: Bash script-level tracing (very verbose)
# bash -x ./install-copilot-setup.sh -help
```

---

### 2. Check GitHub Copilot Status

1. Click Copilot icon in VS Code status bar
2. Check for error messages
3. Try "Sign out and sign in again"

---

### 3. Verify Extension Versions

Ensure you have compatible versions:
- **GitHub Copilot**: v1.140.0 or later
- **GitHub Copilot Chat**: v0.12.0 or later

Update extensions if needed.

---

### 4. Get Help

If none of these solutions work:

1. **Check existing issues**: [GitHub Issues](https://github.com/WodansSon/terraform-azurerm-ai-assisted-development/issues)

2. **Create a new issue**: Include:
   - OS and version
   - VS Code version
   - Copilot extension versions
   - Full error message
   - Steps to reproduce

3. **Join discussions**: [GitHub Discussions](https://github.com/WodansSon/terraform-azurerm-ai-assisted-development/discussions)

---

## Useful Commands

### Reinstall Everything
```powershell
# Windows (recommended): clean then install
cd "$env:USERPROFILE\.terraform-azurerm-ai-installer"
.\install-copilot-setup.ps1 -Clean -RepoDirectory "C:\path\to\terraform-provider-azurerm"
.\install-copilot-setup.ps1 -RepoDirectory "C:\path\to\terraform-provider-azurerm"

# macOS/Linux (recommended): clean then install
cd ~/.terraform-azurerm-ai-installer
./install-copilot-setup.sh -clean -repo-directory "/path/to/terraform-provider-azurerm"
./install-copilot-setup.sh -repo-directory "/path/to/terraform-provider-azurerm"

# If you are developing the installer itself, refresh the user-profile installer first:
#   PowerShell: & "C:\path\to\terraform-azurerm-ai-assisted-development\installer\install-copilot-setup.ps1" -Bootstrap
#   Bash: /path/to/terraform-azurerm-ai-assisted-development/installer/install-copilot-setup.sh -bootstrap
```

### Uninstall
```powershell
# Windows
Remove-Item -Recurse -Force "$env:USERPROFILE\.vscode\copilot\instructions"

# macOS/Linux
rm -rf ~/.vscode/copilot/instructions
```

### Check Installation
```powershell
# Windows
Get-ChildItem -Recurse "$env:USERPROFILE\.vscode\copilot\instructions"

# macOS/Linux
find ~/.vscode/copilot/instructions -type f
```

---

**Need more help? Open an issue or start a discussion!** 🚀
