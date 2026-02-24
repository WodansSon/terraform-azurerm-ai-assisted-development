<picture>
  <source media="(prefers-color-scheme: dark)" srcset="../.github/installerTitle-dark.png">
  <source media="(prefers-color-scheme: light)" srcset="../.github/installerTitle-light.png">
  <img src="../.github/installerTitle-light.png" alt="AI-Assisted Development Installer" width="900" height="80">
</picture>

**Intelligent setup tool for AI-powered Terraform AzureRM Provider development**

> [!IMPORTANT]
> **📦 Release-Based Installation**: This installer is now distributed as standalone release bundles.
> Download the latest version from [GitHub Releases](https://github.com/WodansSon/terraform-azurerm-ai-assisted-development/releases/latest) instead of cloning the repository.

This installer provides GitHub Copilot instructions, VS Code configurations, Agent Skills, and AI-powered development workflows for the Terraform AzureRM Provider repository.

## 🌍 Cross-Platform Support

The installer supports **Windows**, **macOS**, and **Linux** with flexible platform options:

- **PowerShell** (Cross-platform): Works on Windows and macOS
- **Bash** (Unix-like): Traditional option for macOS and Linux

### 🪟 Windows (PowerShell)
**Recommended for Windows environments:**
```powershell
.\install-copilot-setup.ps1 -Help
.\install-copilot-setup.ps1 -Bootstrap
.\install-copilot-setup.ps1 -RepoDirectory "C:\path\to\terraform-provider-azurerm"
```

> [!WARNING]
> If you encounter PowerShell execution policy errors, see [Windows PowerShell Execution Policy](#windows---powershell-execution-policy) section below.

### 🐧 macOS/Linux

**Option 1: PowerShell Core (Cross-Platform)**
```bash
# Install PowerShell Core
brew install powershell

# Run the installer
pwsh ./install-copilot-setup.ps1 -Help
pwsh ./install-copilot-setup.ps1 -Bootstrap
pwsh ./install-copilot-setup.ps1 -RepoDirectory "/path/to/terraform-provider-azurerm"
```

**Option 2: Bash (Traditional)**
```bash
./install-copilot-setup.sh -help
./install-copilot-setup.sh -bootstrap
./install-copilot-setup.sh -repo-directory "/path/to/terraform-provider-azurerm"
```

### 🔧 Installation Paths
- **Windows**: `%USERPROFILE%\.terraform-azurerm-ai-installer`
- **macOS/Linux**: `~/.terraform-azurerm-ai-installer`

### 🚀 Quick Start for macOS

If you're on macOS and want to use the PowerShell version:

```bash
# 1. Install PowerShell Core (one-time setup)
brew install powershell

# 2. Run the installer
pwsh ./install-copilot-setup.ps1 -Help
pwsh ./install-copilot-setup.ps1 -Bootstrap
```

## ✨ User Experience

The installer provides a **clean, professional output** focused on what matters:

- **📋 Clear progress indicators** - Section headers and completion status
- **🎯 Focused messaging** - Only essential information, no technical noise
- **✅ Success confirmations** - Clear indication when operations complete
- **📊 File operation tracking** - Detailed file copy/install status
- **🎨 Consistent formatting** - Identical output quality across Windows PowerShell and macOS/Linux Bash

**Example output (consistent across Windows PowerShell and macOS/Linux Bash):**
```
============================================================
 Terraform AzureRM Provider - AI Infrastructure Installer
 VERSION: 1.0.0
============================================================

 FEATURE BRANCH DETECTED: feature/my-changes
 WORKSPACE              : C:\path\to\terraform-azurerm-ai-assisted-development

============================================================
 Bootstrap - Copying Installer to User Profile
============================================================

Copying installer files from current repository...

   Copying: file-manifest.config      [OK]
   Copying: install-copilot-setup.ps1 [OK]
   Copying: install-copilot-setup.sh  [OK]
   Copying: ConfigParser.psm1         [OK]
   Copying: FileOperations.psm1       [OK]
   Copying: ValidationEngine.psm1     [OK]
   Copying: UI.psm1                   [OK]
   Copying: configparser.sh           [OK]
   Copying: fileoperations.sh         [OK]
   Copying: validationengine.sh       [OK]
   Copying: ui.sh                     [OK]

 Bootstrap completed successfully

============================================================
 BOOTSTRAP SUMMARY:
============================================================

DETAILS:
  Items Successful: 11
  Total Size      : 181.5 KB
  Location        : C:\Users\<username>\.terraform-azurerm-ai-installer
  Files Copied    : 11

NEXT STEPS:

  1. In your terraform-provider-azurerm working copy, switch to a feature branch:
     git checkout -b feature/your-branch-name

  2. Run the installer again and target your terraform-provider-azurerm repo directory:
     & "$env:USERPROFILE\.terraform-azurerm-ai-installer\install-copilot-setup.ps1" -RepoDirectory "<path-to-your-terraform-provider-azurerm>"
```

> [!NOTE]
> The `-RepoDirectory` (`-repo-directory` for Bash) parameter tells the installer where to find the git repository for branch detection when running from your user profile.

## 🚀 Getting Started

> [!IMPORTANT]
> **Critical: Correct Extraction Location**
>
> The installer **MUST** be extracted to your user profile directory:
> - **Windows**: `$env:USERPROFILE\.terraform-azurerm-ai-installer\`
> - **macOS/Linux**: `~/.terraform-azurerm-ai-installer/`
>
> **Do NOT run the installer from:**
> - Downloads folder
> - Desktop
> - Temporary directories
> - Arbitrary locations
>
> Running from incorrect locations will cause **directory traversal errors** and the installer will fail with errors like:
> ```
> A positional parameter cannot be found that accepts argument 'settings.json'
> ```
>
> The installer requires a specific directory structure to load modules and configuration files correctly.

### 🌍 Cross-Platform Quick Start

Choose your platform and follow the two-step process:

**Windows (PowerShell):**
```powershell
# Step 1: Download and extract to user profile (one-time setup)
Invoke-WebRequest -Uri "https://github.com/WodansSon/terraform-azurerm-ai-assisted-development/releases/latest/download/terraform-azurerm-ai-installer.zip" -OutFile "$env:TEMP\terraform-azurerm-ai-installer.zip"
Expand-Archive -Path "$env:TEMP\terraform-azurerm-ai-installer.zip" -DestinationPath "$env:USERPROFILE" -Force

# Step 2: Install AI infrastructure (from user profile)
& "$env:USERPROFILE\.terraform-azurerm-ai-installer\install-copilot-setup.ps1" -RepoDirectory "C:\path\to\terraform-provider-azurerm"
```

**macOS/Linux (Bash):**
```bash
# Step 1: Download and extract to user profile (one-time setup)
curl -L -o /tmp/terraform-azurerm-ai-installer.tar.gz "https://github.com/WodansSon/terraform-azurerm-ai-assisted-development/releases/latest/download/terraform-azurerm-ai-installer.tar.gz"
mkdir -p ~/.terraform-azurerm-ai-installer
tar -xzf /tmp/terraform-azurerm-ai-installer.tar.gz -C ~/.terraform-azurerm-ai-installer --strip-components=1

# Step 2: Install AI infrastructure (from user profile)
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

### 📁 Installation Location

The installer extracts to your user profile:
- **Windows**: `%USERPROFILE%\.terraform-azurerm-ai-installer`
- **macOS/Linux**: `~/.terraform-azurerm-ai-installer`

Once installed, you can run the installer from any directory on any branch by specifying the repo directory parameter (`-RepoDirectory` for PowerShell, `-repo-directory` for Bash).

> [!TIP]
> **For Contributors**: If you have the repository cloned locally, you can use `-Bootstrap` to copy from source instead of downloading the release bundle.

### 📋 Prerequisites

#### System Requirements

**For Windows:**
- Windows PowerShell 5.1+ or PowerShell Core 7+
- Git (standard installation)

**For macOS Users (PowerShell Option):**
- **PowerShell Core 7+** installed (via `brew install powershell`)
- Standard Unix tools (git, which are typically available)

**For macOS/Linux Users (Bash Option):**
- Bash shell environment
- Standard Unix tools (git, curl, which are typically available)

#### VS Code Extensions

Before using the AI-powered development features, ensure you have the following VS Code extensions installed:

#### Required Extensions
- **[GitHub Copilot](https://marketplace.visualstudio.com/items?itemName=GitHub.copilot)** - Core AI assistance and code generation
- **[GitHub Copilot Chat](https://marketplace.visualstudio.com/items?itemName=GitHub.copilot-chat)** - Interactive AI chat and slash commands

#### Recommended Configuration
For optimal performance and the best AI assistance experience:

- **LLM Model**: **Claude Sonnet 4.5** (optimal for Terraform and Go development)
- **Copilot Chat Model**: Set to `Claude Sonnet 4.5` in VS Code settings
- **Alternative**: GPT-4o (good alternative if Claude is unavailable)

#### Quick Setup
1. Install the required extensions from VS Code marketplace
2. Sign in to GitHub Copilot with your account
3. Configure `Claude Sonnet 4.5` as your preferred model:
   - Open VS Code Settings (`Ctrl+,`)
   - Search for "copilot chat model"
   - Select `Claude Sonnet 4.5` from the dropdown

> [!NOTE]
> `Claude Sonnet 4.5` provides superior understanding of Terraform patterns, Azure API specifics, and Go code generation compared to other models.

### First Time Setup

Download and extract the latest installer bundle directly to your user profile:

**Windows (PowerShell):**
```powershell
# Download the latest installer bundle
Invoke-WebRequest -Uri "https://github.com/WodansSon/terraform-azurerm-ai-assisted-development/releases/latest/download/terraform-azurerm-ai-installer.zip" -OutFile "$env:TEMP\terraform-azurerm-ai-installer.zip"

# Extract directly to user profile (recommended / official installation)
Expand-Archive -Path "$env:TEMP\terraform-azurerm-ai-installer.zip" -DestinationPath "$env:USERPROFILE\.terraform-azurerm-ai-installer" -Force

# Verify installation
& "$env:USERPROFILE\.terraform-azurerm-ai-installer\install-copilot-setup.ps1" -Help
```

**macOS/Linux (Bash):**
```bash
# Download the latest installer bundle
curl -L -o /tmp/terraform-azurerm-ai-installer.tar.gz "https://github.com/WodansSon/terraform-azurerm-ai-assisted-development/releases/latest/download/terraform-azurerm-ai-installer.tar.gz"

# Extract directly to user profile (recommended / official installation)
mkdir -p ~/.terraform-azurerm-ai-installer
tar -xzf /tmp/terraform-azurerm-ai-installer.tar.gz -C ~/.terraform-azurerm-ai-installer --strip-components=1

# Verify installation
~/.terraform-azurerm-ai-installer/install-copilot-setup.sh -help
```

> [!TIP]
> **For Contributors**: If you're contributing to this project and have the repository cloned locally, you can use the `-Bootstrap` command to copy from source:
> ```bash
> # From the cloned repository
> cd terraform-azurerm-ai-assisted-development/installer
> ./install-copilot-setup.sh -bootstrap  # or .\install-copilot-setup.ps1 -Bootstrap on Windows
> ```

### ⚠️ Platform-Specific Considerations

#### Windows - PowerShell Execution Policy

If you encounter execution policy errors on Windows, you have several options:

##### Option 1: Bypass for single execution (Recommended)
```powershell
# Run with execution policy bypass (safest for one-time use)
powershell -ExecutionPolicy Bypass -File .\installer\install-copilot-setup.ps1 -Help

# Or for the user profile installer
powershell -ExecutionPolicy Bypass -File "$env:USERPROFILE\.terraform-azurerm-ai-installer\install-copilot-setup.ps1"
```

##### Option 2: Unblock the downloaded files
```powershell
# Unblock all installer files
Get-ChildItem -Path .\installer -Recurse | Unblock-File
.\installer\install-copilot-setup.ps1 -Help
```

##### Option 3: Set execution policy for current user (Permanent)
```powershell
# Allow local scripts for current user
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
.\installer\install-copilot-setup.ps1 -Help
```

#### macOS/Linux - Script Permissions

If you encounter permission errors on macOS/Linux:

```bash
# Make scripts executable
chmod +x installer/*.sh

# Then run the installer
./install-copilot-setup.sh -help
```

## 🚀 Quick Start

### Two-Step Process (Any Platform)

**Step 1: Download and Extract to User Profile (One-time setup)**

Download the installer bundle and extract directly to your user profile:

**Windows:**
```powershell
# Download and extract to user profile
Invoke-WebRequest -Uri "https://github.com/WodansSon/terraform-azurerm-ai-assisted-development/releases/latest/download/terraform-azurerm-ai-installer.zip" -OutFile "$env:TEMP\terraform-azurerm-ai-installer.zip"
Expand-Archive -Path "$env:TEMP\terraform-azurerm-ai-installer.zip" -DestinationPath "$env:USERPROFILE\.terraform-azurerm-ai-installer" -Force

# Verify installation
& "$env:USERPROFILE\.terraform-azurerm-ai-installer\install-copilot-setup.ps1" -Help
```

> [!WARNING]
> **PowerShell Execution Policy**: If you get execution policy errors when running the installer, use:
> ```powershell
> powershell -ExecutionPolicy Bypass -File "$env:USERPROFILE\.terraform-azurerm-ai-installer\install-copilot-setup.ps1" -Help
> ```

**macOS/Linux:**
```bash
# Download and extract to user profile
curl -L -o /tmp/terraform-azurerm-ai-installer.tar.gz "https://github.com/WodansSon/terraform-azurerm-ai-assisted-development/releases/latest/download/terraform-azurerm-ai-installer.tar.gz"
mkdir -p ~/.terraform-azurerm-ai-installer
tar -xzf /tmp/terraform-azurerm-ai-installer.tar.gz -C ~/.terraform-azurerm-ai-installer --strip-components=1

# Verify installation
~/.terraform-azurerm-ai-installer/install-copilot-setup.sh -help
```

**Step 2: Install AI Infrastructure (Whenever you work on a feature branch)**

Navigate to your Terraform AzureRM Provider repository and run the installer:

**Windows:**
```powershell
# Navigate to your Terraform provider repository
cd C:\path\to\terraform-provider-azurerm

# Switch to your feature branch
git checkout -b feature/your-branch-name

# Install AI infrastructure from user profile
& "$env:USERPROFILE\.terraform-azurerm-ai-installer\install-copilot-setup.ps1" -RepoDirectory "C:\path\to\terraform-provider-azurerm"
```

**macOS/Linux:**
```bash
# Navigate to your Terraform provider repository
cd /path/to/terraform-provider-azurerm

# Switch to your feature branch
git checkout -b feature/your-branch-name

# Install AI infrastructure from user profile
~/.terraform-azurerm-ai-installer/install-copilot-setup.sh -repo-directory "/path/to/terraform-provider-azurerm"
```

> [!NOTE]
> The `-RepoDirectory` or `-repo-directory` (for Bash) parameter is required when running from your user profile to tell the installer where your AzureRM Provider git repository is located.

## 📋 What Gets Installed

The installer sets up a complete AI development environment:

### 📄 Core AI Instructions
- `.github/copilot-instructions.md` - Main Copilot configuration
- `.github/instructions/` - 13 specialized instruction files:
  - `implementation-guide.instructions.md` - Complete coding standards
  - `azure-patterns.instructions.md` - Azure-specific patterns
  - `testing-guidelines.instructions.md` - Testing requirements
  - `documentation-guidelines.instructions.md` - Doc standards
  - `error-patterns.instructions.md` - Error handling
  - `migration-guide.instructions.md` - Version migration
  - `provider-guidelines.instructions.md` - Provider patterns
  - `schema-patterns.instructions.md` - Schema design
  - `code-clarity-enforcement.instructions.md` - Code quality
  - `performance-optimization.instructions.md` - Performance
  - `security-compliance.instructions.md` - Security patterns
  - `troubleshooting-decision-trees.instructions.md` - Debugging
  - `api-evolution-patterns.instructions.md` - API versioning

### 🎨 Development Templates & AI Prompts
- `.github/prompts/` - AI prompt templates for common development tasks:

### 🧠 Agent Skills
- `.github/skills/` - Agent Skills for specialized Copilot workflows (invokable via slash commands like `/docs-writer`)

> [!TIP]
> The `docs-writer` skill supports a dry run/testing mode for docs scaffolding: when you ask for a test/dry run, it uses `-website-path website_scaffold_tmp` to avoid overwriting `website/docs/**`.

### ⚙️ VS Code Configuration
- `.vscode/settings.json` - Optimized VS Code settings for Terraform development
  - Go formatting and linting configurations
  - Terraform extension settings
  - Workspace-specific editor preferences

> [!NOTE]
> The `.vscode/settings.json` file contains **workspace-specific settings** that only apply to this repository. Your personal VS Code user settings will remain unchanged.

## How to Use Prompts

### **In GitHub Copilot Chat:**
Simply use slash commands to invoke the prompts directly:

| Slash Command | Prompt File | Description |
|---------------|-------------|-------------|
| `/code-review-local-changes` | `code-review-local-changes.prompt.md` | Review your uncommitted changes |
| `/code-review-committed-changes` | `code-review-committed-changes.prompt.md` | Review committed changes |
| `/code-review-docs` | `code-review-docs.prompt.md` | Review a `website/docs/**` page for docs standards + schema parity |

**Example Usage:**
```
/code-review-local-changes
/code-review-committed-changes
/code-review-docs
```

#### Available Prompts

| Prompt File | Purpose | Usage |
|-------------|---------|-------|
| `code-review-local-changes.prompt.md` | **Review uncommitted changes** with Terraform provider best practices | Use before committing to get expert feedback on your local changes |
| `code-review-committed-changes.prompt.md` | **Review committed changes** for pull request feedback | Use to review git commits with detailed technical analysis |
| `code-review-docs.prompt.md` | **Review a docs page** for required sections and schema parity | Open a file under `website/docs/**` and run to get patch-ready fixes |

## 🎛️ Command Reference

### Platform-Specific Commands

**Windows (PowerShell):**

| Command | Description | Available On |
|---------|-------------|--------------|
| `\.\install-copilot-setup.ps1 -Bootstrap` | **Copy installer to user profile from cloned repo** | When cloned locally |
| `& "$env:USERPROFILE\.terraform-azurerm-ai-installer\install-copilot-setup.ps1" -RepoDirectory "C:\path\to\terraform-provider-azurerm"` | **Install AI infrastructure** (run from anywhere after setup) | Feature branches |
| `& "$env:USERPROFILE\.terraform-azurerm-ai-installer\install-copilot-setup.ps1" -Verify -RepoDirectory "C:\path\to\terraform-provider-azurerm"` | **Check installation status** (run from anywhere after setup) | Any branch |
| `& "$env:USERPROFILE\.terraform-azurerm-ai-installer\install-copilot-setup.ps1" -Verify` | **Verify installer bundle** (self-check: manifest/modules/payload/checksum) | Any branch |
| `& "$env:USERPROFILE\.terraform-azurerm-ai-installer\install-copilot-setup.ps1" -Clean -RepoDirectory "C:\path\to\terraform-provider-azurerm"` | **Remove AI infrastructure** (run from anywhere after setup) | Feature branches |
| `& "$env:USERPROFILE\.terraform-azurerm-ai-installer\install-copilot-setup.ps1" -Help` | **Show detailed help** (run from anywhere after setup) | Any branch |

**macOS/Linux (Bash):**

| Command | Description | Available On |
|---------|-------------|--------------|
| `./install-copilot-setup.sh -bootstrap` | **Copy installer to user profile from cloned repo** | When cloned locally |
| `~/.terraform-azurerm-ai-installer/install-copilot-setup.sh -repo-directory "/path/to/terraform-provider-azurerm"` | **Install AI infrastructure** (run from anywhere after bootstrap) | Feature branches |
| `~/.terraform-azurerm-ai-installer/install-copilot-setup.sh -verify -repo-directory "/path/to/terraform-provider-azurerm"` | **Check installation status** (run from anywhere after bootstrap) | Any branch |
| `~/.terraform-azurerm-ai-installer/install-copilot-setup.sh -verify` | **Verify installer bundle** (self-check: manifest/modules/payload/checksum) | Any branch |
| `~/.terraform-azurerm-ai-installer/install-copilot-setup.sh -clean -repo-directory "/path/to/terraform-provider-azurerm"` | **Remove AI infrastructure** (run from anywhere after bootstrap) | Feature branches |
| `~/.terraform-azurerm-ai-installer/install-copilot-setup.sh -help` | **Show detailed help** (run from anywhere after bootstrap) | Any branch |

> [!NOTE]
> `-Verify` / `-verify` is **offline-only** and has two modes:
> - **Bundle self-check (no repo directory):** verifies the installer bundle itself (manifest/modules/payload/checksum).
> - **Target repo verification (with repo directory):** checks whether the AI infrastructure is present in the target repository.
> - `-Verify -RepoDirectory` / `-verify -repo-directory` hard-fails if the repo directory points at the installer source repository, to prevent false-positive verification.
> Verification summaries include both files and directories checked.
> Install, verify, and clean use the bundled payload (`aii/`) and local manifest only.
> No network downloads occur during these operations.
> Install and verify also validate the bundled payload checksum (`aii.checksum`). If it fails, re-extract the release bundle or re-run `-Bootstrap` (contributors only).
<!-- -->
> [!NOTE]
> Target installs require a `terraform-provider-azurerm` clone with an origin remote configured.
> The AI development repository is a source-only workspace and is not a valid install target.
> If the installer directory is incomplete (missing manifest or bundled payload), refresh your user-profile installer
> re-extract the latest release bundle, or re-run `-Bootstrap` from a local clone (contributors only) and try again.

### Parameters

**Windows (PowerShell):**

| Parameter | Description | Required When | Example |
|-----------|-------------|---------------|---------|
| `-RepoDirectory` | **Specify repository path** | **Install/Clean** from user profile, or to **verify a target repo** | `-RepoDirectory "C:\path\to\terraform-provider-azurerm"` |
| `-LocalPath` | **Copy AI files from a local directory** (source override; instead of bundled payload) | Contributor/dev installs | `-LocalPath "C:\dev\terraform-azurerm-ai-assisted-development"` |

**macOS/Linux (Bash):**

| Parameter | Description | Required When | Example |
|-----------|-------------|---------------|---------|
| `-repo-directory` | **Specify repository path** | **Install/Clean** from user profile, or to **verify a target repo** | `-repo-directory "/path/to/terraform-provider-azurerm"` |
| `-local-path` | **Copy AI files from a local directory** (source override; instead of bundled payload) | Contributor/dev installs | `-local-path "/path/to/terraform-azurerm-ai-assisted-development"` |

### 🚨 Important: Repository Directory Parameter

When running the installer **from your user profile** (after initial setup), you **MUST** specify the repository directory parameter for operations that target a repository (**install** and **clean**).

`-Verify` / `-verify` can also be run **without** a repo directory to perform an installer bundle self-check.

*Windows:*
```powershell
# ✅ CORRECT: Running from user profile with RepoDirectory
& "$env:USERPROFILE\.terraform-azurerm-ai-installer\install-copilot-setup.ps1" -RepoDirectory "C:\path\to\terraform-provider-azurerm"

# ✅ CORRECT: Verify the installer bundle (no RepoDirectory)
& "$env:USERPROFILE\.terraform-azurerm-ai-installer\install-copilot-setup.ps1" -Verify

# ❌ INCORRECT: Install/clean from user profile without RepoDirectory
& "$env:USERPROFILE\.terraform-azurerm-ai-installer\install-copilot-setup.ps1"
```

*macOS/Linux:*
```bash
# ✅ CORRECT: Running from user profile with -repo-directory
~/.terraform-azurerm-ai-installer/install-copilot-setup.sh -repo-directory "/Users/<username>/terraform-provider-azurerm"

# ✅ CORRECT: Verify the installer bundle (no -repo-directory)
~/.terraform-azurerm-ai-installer/install-copilot-setup.sh -verify

# ❌ INCORRECT: Install/clean from user profile without -repo-directory
~/.terraform-azurerm-ai-installer/install-copilot-setup.sh
```

**Why is this required?**
- The installer needs to know where your git repository is located
- Enables proper branch detection and workspace validation
- Ensures files are installed in the correct repository directory
- The target repository must be a `terraform-provider-azurerm` clone with an origin remote configured

**How did the installer get to your user profile?**

There are two ways to set up the installer in your user profile:

#### 🌐 **Option 1: Download Release Package (Recommended for Most Users)**
Download the pre-packaged installer bundle and extract it directly to your user profile. This is the **standard workflow** for most users:

**Windows:**
```powershell
# Download and extract the latest release to user profile
Invoke-WebRequest -Uri "https://github.com/WodansSon/terraform-azurerm-ai-assisted-development/releases/latest/download/terraform-azurerm-ai-installer.zip" -OutFile "$env:TEMP\terraform-azurerm-ai-installer.zip"
Expand-Archive -Path "$env:TEMP\terraform-azurerm-ai-installer.zip" -DestinationPath "$env:USERPROFILE\.terraform-azurerm-ai-installer" -Force

# Verify installation
& "$env:USERPROFILE\.terraform-azurerm-ai-installer\install-copilot-setup.ps1" -Help
```

**macOS/Linux:**
```bash
# Download and extract the latest release to user profile
curl -L -o /tmp/terraform-azurerm-ai-installer.tar.gz "https://github.com/WodansSon/terraform-azurerm-ai-assisted-development/releases/latest/download/terraform-azurerm-ai-installer.tar.gz"
mkdir -p ~/.terraform-azurerm-ai-installer
tar -xzf /tmp/terraform-azurerm-ai-installer.tar.gz -C ~/.terraform-azurerm-ai-installer --strip-components=1

# Verify installation
~/.terraform-azurerm-ai-installer/install-copilot-setup.sh -help
```

#### 🔧 **Option 2: Bootstrap from Local Clone (For Contributors)**
If you're **contributing to this AI infrastructure project** and have it cloned locally, you can use `-Bootstrap` to copy the installer to your user profile from your local repository:

> [!NOTE]
> **Recommended contributor workflow**: bootstrap from your local clone to refresh the installed bundle content, then run installs from your user profile as normal. If you are testing/iterating on local, uncommitted AI files (prompts/instructions/skills), you can use the `-LocalPath <your-clone>` (`-local-path <your-clone>` for Bash) parameter to override your bootstrapped/installed bundle files when installing the AI infrastructure files into your `terraform-provider-azurerm` branch/clone.
>
> For troubleshooting, see: [Installer Configuration Validation Failed / Payload Missing](../docs/TROUBLESHOOTING.md#installer-configuration-validation-failed--payload-missing).

**Windows:**
```powershell
# Clone the AI infrastructure repository (one-time)
git clone https://github.com/WodansSon/terraform-azurerm-ai-assisted-development.git
cd terraform-azurerm-ai-assisted-development/installer

# Bootstrap from your local clone
.\install-copilot-setup.ps1 -Bootstrap

# Now you can run from your user profile
& "$env:USERPROFILE\.terraform-azurerm-ai-installer\install-copilot-setup.ps1" -Help

# Install using files from your local clone (optional: local testing or contributor override)
.\install-copilot-setup.ps1 -LocalPath "C:\path\to\terraform-azurerm-ai-assisted-development" -RepoDirectory "C:\path\to\terraform-provider-azurerm"
```

**macOS/Linux:**
```bash
# Clone the AI infrastructure repository (one-time)
git clone https://github.com/WodansSon/terraform-azurerm-ai-assisted-development.git
cd terraform-azurerm-ai-assisted-development/installer

# Bootstrap from your local clone
./install-copilot-setup.sh -bootstrap

# Now you can run from your user profile
~/.terraform-azurerm-ai-installer/install-copilot-setup.sh -help

# Install using files from your local clone (optional: local testing or contributor override)
./install-copilot-setup.sh -local-path "/path/to/terraform-azurerm-ai-assisted-development" -repo-directory "/path/to/terraform-provider-azurerm"
```

**When to use each option:**
- **Option 1 (Download Release)**: 99% of users - You just want to use the AI infrastructure for Terraform development
- **Option 2 (Bootstrap)**: You're contributing to the AI infrastructure project itself and need to test local changes to the installer or instruction files

## 🌊 Workflow Overview

### Branch-Aware Architecture

The installer adapts its behavior based on your current Git branch:

#### 🔹 Source Branch (`main`)
- Contains the master AI infrastructure files
- **Bootstrap mode**: Copies installer to user profile for feature branch use
- **Verification**: Checks source files integrity
- **Protection**: Prevents accidental deletion of development files

#### 🔹 Feature Branches (any other branch)
- Target for AI infrastructure installation
- **Install mode**: Sets up complete AI development environment
- **Clean mode**: Removes AI infrastructure when needed
- **Verification**: Checks installed files status

### Typical Development Workflow

```mermaid
graph LR
  A[Install release Package] --> B[git checkout -b feature/xyz]
    B --> C[Run from user profile]
    C --> D[Develop with AI assistance]
    D --> E[-Clean]
    E --> F[Push Changes]
```

## 🏗️ Architecture

### Two-Silo Architecture

```
.terraform-azurerm-ai-installer/
├── install-copilot-setup.ps1      # Windows PowerShell installer
├── install-copilot-setup.sh       # macOS/Linux Bash installer
├── README.md                      # This file
├── file-manifest.config           # File configuration (shared)
└── modules/                       # Platform-specific modules
    ├── powershell/                # PowerShell modules (Windows)
    │   ├── ConfigParser.psm1      # Configuration management
    │   ├── FileOperations.psm1    # File installation/removal
    │   ├── ValidationEngine.psm1  # System validation
    │   └── UI.psm1                # User interface functions
    └── bash/                      # Bash modules (macOS/Linux)
        ├── configparser.sh        # Configuration management
        ├── fileoperations.sh      # File installation/removal
        ├── validationengine.sh    # System validation
        └── ui.sh                  # User interface functions
```

### Platform Detection & Execution Flow

```mermaid
graph TD
    A[User Chooses Platform] --> B{Which Platform?}
    B -->|Windows| C[Run install-copilot-setup.ps1]
    B -->|macOS/Linux| D[Run install-copilot-setup.sh]
    C --> E[PowerShell Module Loading]
    D --> F[Bash Module Loading]
    E --> G[AI Infrastructure Installation]
    F --> G
```

## 🔄 Automated Deprecation Management

The installer includes **intelligent deprecation management** that automatically maintains your AI development environment:

### ✨ Smart File Lifecycle Management

During each installation, the tool automatically:

- **🔍 Scans** existing instruction, prompt, and skill files in your workspace
- **📋 Compares** them against the local installer manifest (`file-manifest.config`)
- **🗑️ Removes** deprecated files that are no longer part of the AI infrastructure
- **✅ Preserves** current files that remain active

### 🎯 What Gets Managed

**Instruction Files** (`.github/instructions/`)
- `*.instructions.md` files for AI coding guidelines
- Automatic removal of outdated instruction patterns
- Ensures you always have the latest AI development guidance

**Prompt Files** (`.github/prompts/`)
- `*.prompt.md` files for AI interaction templates
- Removes obsolete prompt templates
- Keeps your prompt library current and effective

**Skill Files** (`.github/skills/`)
- `*/SKILL.md` files defining Agent Skills
- Removes obsolete skills that are no longer in the manifest
- Keeps the skill list synchronized with the toolkit

### 💡 How It Works

**Automatic During Installation:**
```powershell
# Windows - deprecation check runs automatically
.\install-copilot-setup.ps1 -RepoDirectory "C:\path\to\terraform-provider-azurerm"

# Output example:
# Checking for deprecated files...
#   Removed deprecated instruction file: old-pattern.instructions.md
#   Removed deprecated prompt file: legacy-prompt.prompt.md
#   Removed 2 deprecated file(s)
```

```bash
# macOS/Linux - deprecation check runs automatically
./install-copilot-setup.sh -repo-directory "/path/to/terraform-provider-azurerm"

# Output example:
# Checking for deprecated files...
#   Removed deprecated instruction file: old-pattern.instructions.md
#   Removed deprecated prompt file: legacy-prompt.prompt.md
#   Removed 2 deprecated file(s)
```

### 🛡️ Safety Features

- **Branch protection** - Only operates on feature branches, never on source branch
- **Manifest validation** - Only removes files not in the local installer manifest
- **Error handling** - Graceful handling of permission issues or file locks

### 🚀 Benefits

- **🎯 Always Current**: Your AI environment stays synchronized with the latest patterns
- **🧹 Clean Workspace**: No accumulation of obsolete AI guidance files
- **⚡ Zero Maintenance**: Fully automatic - no manual cleanup required
- **🔄 Version Sync**: Ensures your local environment matches the source branch requirements

## 🎯 AI Prompt Usage Patterns

### Quick Start with Prompts

Once the AI infrastructure is installed, you can leverage the powerful prompt templates for common development tasks:

#### 🔍 Code Review Workflow
```
# Review your current changes before committing
/code-review-local-changes

# Review specific committed changes
/code-review-committed-changes for commit abc123
```

### Advanced Prompt Techniques

#### 🎯 Context-Specific Usage
Combine slash commands with specific context for better results:

```
# Review specific Azure service implementation
/code-review-local-changes focusing on Azure CDN Front Door patterns

# Review changes with specific focus areas
/code-review-committed-changes and ensure Azure SDK integration follows best practices
```

#### 🔄 Iterative Development
Use slash commands in sequence for complete development workflows:

```
1. # Review your implementation patterns against Azure provider guidelines
2. # Make your code changes
3. /code-review-local-changes before committing
4. /code-review-committed-changes after committing for final review
```

#### 🎨 Custom Prompt Combinations
Combine multiple commands for complex tasks:

```
# Comprehensive development review
/code-review-local-changes AND ensure the code follows Azure patterns from .github/instructions/
```

## 🔍 Usage Examples

### Install AI Infrastructure

**Windows:**
```powershell
# After installing to user profile - run from anywhere
& "$env:USERPROFILE\.terraform-azurerm-ai-installer\install-copilot-setup.ps1" -RepoDirectory "C:\path\to\terraform-provider-azurerm"
```

**macOS/Linux:**
```bash
# After installing to user profile - run from anywhere
~/.terraform-azurerm-ai-installer/install-copilot-setup.sh -repo-directory "/path/to/terraform-provider-azurerm"
```

### Check Current AI Infrastructure File Status

**Windows:**
```powershell
# After installing to user profile - run from anywhere
& "$env:USERPROFILE\.terraform-azurerm-ai-installer\install-copilot-setup.ps1" -Verify -RepoDirectory "C:\path\to\terraform-provider-azurerm"
```

**macOS/Linux:**
```bash
# After installing to user profile - run from anywhere
~/.terraform-azurerm-ai-installer/install-copilot-setup.sh -verify -repo-directory "/path/to/terraform-provider-azurerm"
```

### Clean AI Infrastructure Files From Your Terraform Provider Feature Branch

**Windows:**
```powershell
# After installing to user profile - run from anywhere
& "$env:USERPROFILE\.terraform-azurerm-ai-installer\install-copilot-setup.ps1" -Clean -RepoDirectory "C:\path\to\terraform-provider-azurerm"

```

**macOS/Linux:**
```bash
# After installing to user profile - run from anywhere
~/.terraform-azurerm-ai-installer/install-copilot-setup.sh -clean -repo-directory "/path/to/terraform-provider-azurerm"

```

### Local Source Install (Contributor Override)

By default, the installer copies AI files from the **bundled offline payload** (`aii/`) shipped with the release/bootstrapped installer.
If you are a contributor and want to test AI instruction changes from a local working tree, use `-LocalPath` / `-local-path` to override the bundled payload.

**Windows:**
```powershell
& "$env:USERPROFILE\.terraform-azurerm-ai-installer\install-copilot-setup.ps1" -LocalPath "C:\dev\terraform-azurerm-ai-assisted-development" -RepoDirectory "C:\path\to\terraform-provider-azurerm"
```

**macOS/Linux:**
```bash
~/.terraform-azurerm-ai-installer/install-copilot-setup.sh -local-path ~/dev/terraform-azurerm-ai-assisted-development -repo-directory ~/terraform-provider-azurerm
```

> [!NOTE]
> `-Bootstrap` (`-bootstrap` for Bash) is a standalone command and does not accept `-LocalPath` (`-local-path` for Bash). Run bootstrap from your clone first, then run installs from your user profile with `-LocalPath` / `-local-path`.

### Using Bootstrap for Local Development

Bootstrap is a **one-time convenience setup** that copies the installer to your user profile. After bootstrapping, you can easily install AI infrastructure to whatever feature branch you're currently working on in your local HashiCorp terraform-provider-azurerm repository.

**Windows:**
```powershell
# One-time setup: Bootstrap from a git clone of this repository (recommended: run from `main`)
cd C:\path\to\terraform-azurerm-ai-assisted-development
.\installer\install-copilot-setup.ps1 -Bootstrap

# Then whenever you're working on a feature branch in your HashiCorp repo:
cd C:\path\to\terraform-provider-azurerm
git checkout -b feature/your-feature-branch

# Install AI infrastructure to your current branch
& "$env:USERPROFILE\.terraform-azurerm-ai-installer\install-copilot-setup.ps1" -RepoDirectory "C:\path\to\terraform-provider-azurerm"
```

**macOS/Linux:**
```bash
# One-time setup: Bootstrap from a git clone of this repository (recommended: run from `main`)
cd ~/terraform-azurerm-ai-assisted-development
./installer/install-copilot-setup.sh -bootstrap

# Then whenever you're working on a feature branch in your HashiCorp repo:
cd ~/terraform-provider-azurerm
git checkout -b feature/your-feature-branch

# Install AI infrastructure to your current branch
~/.terraform-azurerm-ai-installer/install-copilot-setup.sh -repo-directory ~/terraform-provider-azurerm
```

> [!TIP]
> Bootstrap once, then install to any feature branch you're working on. The installer always installs to whatever branch is currently checked out in the repository path you specify.

## 🛠️ Troubleshooting

### Common Issues

#### ❌ "Bootstrap can only be run from source branch"
**Solution**: Run bootstrap from a local git clone of this repository (repo root contains `.git`).

#### ❌ "Clean operation not available on source branch"
**Solution**: In your terraform-provider-azurerm working copy, switch to a feature branch before running clean/install operations.

#### ❌ "Error: -RepoDirectory / -repo-directory path does not exist"
**Solution**:
- Check the path spelling and ensure it exists
- Use an absolute path (e.g., `C:\path\to\terraform-provider-azurerm`)
- Ensure you have permissions to access the directory

#### ❌ "INVALID REPOSITORY: The specified directory does not appear to be a terraform-azurerm-ai-assisted-development repository"
**Solution**:
- Ensure you're pointing to the repository ROOT directory
- Verify the directory contains the `installer/` folder and repository files
- Example: `-RepoDirectory 'C:\path\to\terraform-azurerm-ai-assisted-development'`

#### ❌ Module import errors
**Solution**: Ensure you're running from the correct directory with all PowerShell modules present.

### Manual Recovery

If the installer becomes corrupted in your user profile:

```powershell
# Re-bootstrap from the repository
cd C:\path\to\terraform-azurerm-ai-assisted-development
.\installer\install-copilot-setup.ps1 -Bootstrap
```

```bash
# macOS/Linux
cd ~/terraform-azurerm-ai-assisted-development
./installer/install-copilot-setup.sh -bootstrap
```

This will refresh the installer copy in your user profile (`~/.terraform-azurerm-ai-installer`).

## 📄 License

This is a community-maintained project licensed under the Mozilla Public License 2.0 (MPL-2.0). See the [LICENSE](../LICENSE) file for details.

---

**Need help?** Run `.\install-copilot-setup.ps1 -Help` for interactive assistance.
