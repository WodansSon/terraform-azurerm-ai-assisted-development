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
.\install-copilot-setup.ps1 -Bootstrap
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

### Branch Validation Failed (Contributors)

This happens when the installer tries to validate or pull files from a **GitHub branch** that does not exist remotely.

In contributor workflows, the most common ways to trigger this are:
- You used `-Contributor -Branch "feature/my-branch"` but that branch only exists locally (or the name is misspelled) and has not been pushed to GitHub.
- You are testing local/uncommitted AI file changes but did not use `-Contributor -LocalPath <your clone>`, so the installer falls back to pulling AI files from GitHub (remote) and will fail if the requested branch does not exist.

**Fix options:**
- **Preferred**: use `-Contributor -LocalPath <your clone>` for bootstrap + install when testing local changes.
- **Alternative**: push the branch and re-run using `-Contributor -Branch`.

> [!IMPORTANT]
> The commands below assume the installer in your user profile is up-to-date (v2.0.0+).
> If you have an older `~/.terraform-azurerm-ai-installer` / `%USERPROFILE%\.terraform-azurerm-ai-installer` from a previous release, step (2) may fail or behave differently.
> Always run step (1) first (or re-extract the latest release bundle) before running the installer from your user profile.

**Solution (PowerShell):**
```powershell
# Keep execution consistent with release installs:
# 1) Refresh the user-profile installer from your local AI dev repo (your dev branch)
& "C:\path\to\terraform-azurerm-ai-assisted-development\installer\install-copilot-setup.ps1" -Bootstrap -Contributor -LocalPath "C:\path\to\terraform-azurerm-ai-assisted-development"

# 2) Run the freshly bootstrapped installer from your user profile, sourcing AI files from your working tree
#    (Do not run this step unless you just ran step (1), or you may be running an older installer.)
cd "$env:USERPROFILE\.terraform-azurerm-ai-installer"
.\install-copilot-setup.ps1 -Contributor -LocalPath "C:\path\to\terraform-azurerm-ai-assisted-development" -RepoDirectory "C:\path\to\terraform-provider-azurerm"
```

**Solution (Bash):**
```bash
# Keep execution consistent with release installs:
# 1) Refresh the user-profile installer from your local AI dev repo (your dev branch)
"/path/to/terraform-azurerm-ai-assisted-development/installer/install-copilot-setup.sh" -bootstrap -contributor -local-path "/path/to/terraform-azurerm-ai-assisted-development"

# 2) Run the freshly bootstrapped installer from your user profile, sourcing AI files from your working tree
#    (Do not run this step unless you just ran step (1), or you may be running an older installer.)
cd ~/.terraform-azurerm-ai-installer
./install-copilot-setup.sh -contributor -local-path "/path/to/terraform-azurerm-ai-assisted-development" -repo-directory "/path/to/terraform-provider-azurerm"
```

---

### Manifest File Mismatch (Verify)

This happens when `-Verify` / `-verify` detects that the **local installer manifest** (`file-manifest.config` next to the installer you are running) does not match the **remote manifest** from GitHub.

**Common causes:**
- You have an older `~/.terraform-azurerm-ai-installer` / `%USERPROFILE%\.terraform-azurerm-ai-installer` from a previous release.
- You updated your local clone but did not re-bootstrap the user-profile installer.

**Fix:** refresh your installer, then run verify again.

**Windows (PowerShell):**
```powershell
# Re-extract the latest release bundle (recommended), or re-bootstrap from a local clone.

# Then verify against your target repo:
& "$env:USERPROFILE\.terraform-azurerm-ai-installer\install-copilot-setup.ps1" -Verify -RepoDirectory "C:\path\to\terraform-provider-azurerm"
```

**macOS/Linux (Bash):**
```bash
# Re-extract the latest release bundle (recommended), or re-bootstrap from a local clone.

# Then verify against your target repo:
~/.terraform-azurerm-ai-installer/install-copilot-setup.sh -verify -repo-directory "/path/to/terraform-provider-azurerm"
```

> [!NOTE]
> If the installer cannot reach GitHub (for example DNS/firewall/proxy restrictions), it will warn that it cannot validate the remote manifest and will continue verification using the local manifest.
>
> If you are intentionally testing uncommitted local AI dev repo changes using `-Contributor -LocalPath` / `-contributor -local-path`, remote manifest validation is skipped by design.

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
./install-copilot-setup.sh -bootstrap
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

**Cause**: The docs-writer skill has a **testing/dry run mode** to avoid overwriting real docs. It can trigger when your prompt includes phrases like: `test`, `testing`, `dry run`, `scaffold-only`, or `generate into scratch`.

**Fix**:
- If you want normal behavior, explicitly say you are **not** doing a dry run and ask it to scaffold to the real website root (`-website-path website`).
- If you intended a dry run, keep using the scratch output and diff it against the real docs:
   - Resource: `git diff --no-index website_scaffold_tmp/docs/r/<name>.html.markdown website/docs/r/<name>.html.markdown`
   - Data source: `git diff --no-index website_scaffold_tmp/docs/d/<name>.html.markdown website/docs/d/<name>.html.markdown`

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
bash install-copilot-setup.sh -bootstrap
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
# PowerShell
.\install-copilot-setup.ps1 -Verbose

# Bash
./install-copilot-setup.sh -verbose
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
# Windows
.\install-copilot-setup.ps1 -Bootstrap -Force

# macOS/Linux
./install-copilot-setup.sh -bootstrap -force
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
