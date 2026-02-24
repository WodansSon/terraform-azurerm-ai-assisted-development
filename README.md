<picture>
  <source media="(prefers-color-scheme: dark)" srcset=".github/mainTitle-dark.png">
  <source media="(prefers-color-scheme: light)" srcset=".github/mainTitle-light.png">
  <img src=".github/mainTitle-light.png" alt="Terraform AzureRM AI-Assisted Development" width="900" height="80">
</picture>

<big><strong>AI-Powered Development Tools for the Terraform AzureRM Provider</strong></big>

> **🎯 Mission**: Supercharge your Terraform AzureRM Provider development with AI-powered "Vibe Coding" - Generate Resources, Tests, and Documentation that follow HashiCorp's standards automatically.

[![License: MPL 2.0](https://img.shields.io/badge/License-MPL%202.0-brightgreen.svg)](https://opensource.org/licenses/MPL-2.0)
[![Community Maintained](https://img.shields.io/badge/Community-Maintained-blue.svg)](https://github.com/WodansSon/terraform-azurerm-ai-assisted-development)
[![PowerShell](https://img.shields.io/badge/PowerShell-5391FE.svg?logo=powershell&logoColor=white)](https://docs.microsoft.com/powershell/)
[![Bash](https://img.shields.io/badge/Bash-4EAA25.svg?logo=gnu-bash&logoColor=white)](https://www.gnu.org/software/bash/)
[![Platform: Windows](https://img.shields.io/badge/Platform-Windows-0078D6.svg?logo=windows)](https://www.microsoft.com/windows)
[![Platform: macOS](https://img.shields.io/badge/Platform-macOS-000000.svg?logo=apple)](https://www.apple.com/macos)
[![Platform: Linux](https://img.shields.io/badge/Platform-Linux-FCC624.svg?logo=linux&logoColor=black)](https://www.linux.org/)

## 🌟 What Is This?

This is a **community-maintained AI enhancement** for developers working on the [Terraform AzureRM Provider](https://github.com/hashicorp/terraform-provider-azurerm). It provides:

- ✅ **AI-Powered Code Generation** - Generate Azure resources following HashiCorp patterns
- ✅ **Intelligent Code Review** - Automated reviews using provider-specific guidelines
- ✅ **Test Generation** - Create comprehensive acceptance tests automatically
- ✅ **Documentation Generation** - Generate docs that match provider standards (including nested block ordering and ForceNew phrasing)
- ✅ **Best Practice Enforcement** - Real-time guidance on Azure API integration

### 🎯 Who Is This For?

- **Contributing to terraform-provider-azurerm**: Speed up your contributions with AI assistance
- **Learning provider development**: Get real-time guidance on HashiCorp patterns
- **Building custom providers**: Learn proven patterns from the AzureRM provider
- **Code reviews**: Automated checks against provider standards


### 📖 Origin Story

This project originated from [PR #29907](https://github.com/hashicorp/terraform-provider-azurerm/pull/29907) submitted to the HashiCorp Terraform AzureRM Provider repository on `June 19, 2025`. To help move the merge forward and make these AI-powered development tools more accessible to the community, the installation infrastructure was moved to this standalone repository on `October 19, 2025`. The tools and patterns here are designed to work seamlessly with the official provider repository while being maintained independently.


## 🚀 Quick Start

### Prerequisites

**Required VS Code Extensions:**
- [GitHub Copilot](https://marketplace.visualstudio.com/items?itemName=GitHub.copilot) - AI code generation
- [GitHub Copilot Chat](https://marketplace.visualstudio.com/items?itemName=GitHub.copilot-chat) - Interactive AI assistance
- [HashiCorp Terraform](https://marketplace.visualstudio.com/items?itemName=HashiCorp.terraform) - Terraform support
- [Go](https://marketplace.visualstudio.com/items?itemName=golang.Go) - Go language support

### Installation

> [!IMPORTANT]
> **The installer MUST be extracted to your user profile directory** (`$env:USERPROFILE\.terraform-azurerm-ai-installer\` on `Windows` or `~/.terraform-azurerm-ai-installer/` on `macOS`/`Linux`). Running from other locations (like Downloads or Desktop) will cause directory traversal errors. See [Troubleshooting](docs/TROUBLESHOOTING.md#positional-parameter-error-windows) for details.

**Choose your platform:**

#### Windows (PowerShell)
```powershell
# Download and extract installer directly to user profile
Invoke-WebRequest -Uri "https://github.com/WodansSon/terraform-azurerm-ai-assisted-development/releases/latest/download/terraform-azurerm-ai-installer.zip" -OutFile "$env:TEMP\terraform-azurerm-ai-installer.zip"
Expand-Archive -Path "$env:TEMP\terraform-azurerm-ai-installer.zip" -DestinationPath "$env:USERPROFILE" -Force

# Verify installation
& "$env:USERPROFILE\.terraform-azurerm-ai-installer\install-copilot-setup.ps1" -Help
```

#### macOS/Linux (Bash)
```bash
# Download and extract installer directly to user profile
curl -L -o /tmp/terraform-azurerm-ai-installer.tar.gz "https://github.com/WodansSon/terraform-azurerm-ai-assisted-development/releases/latest/download/terraform-azurerm-ai-installer.tar.gz"
mkdir -p ~/.terraform-azurerm-ai-installer
tar -xzf /tmp/terraform-azurerm-ai-installer.tar.gz -C ~/.terraform-azurerm-ai-installer --strip-components=1

# Verify installation
~/.terraform-azurerm-ai-installer/install-copilot-setup.sh -help
```

> [!NOTE]
> **About `-Verify` / `-verify`:** verification has two modes:
> - **Bundle self-check (no repo directory):** when run from the user-profile installer directory *without* `-RepoDirectory` / `-repo-directory`, it verifies the installer bundle itself (manifest/modules/payload/checksum).
> - **Target repo verification:** when run *with* `-RepoDirectory` / `-repo-directory`, it checks whether the target repository has all required AI files.
> - `-Verify -RepoDirectory` / `-verify -repo-directory` hard-fails if the repo directory points at the installer source repository, to prevent false-positive verification.
> - If it reports **"Manifest file mismatch"**, your local installer manifest is out of date (or from a different release/branch).
>   Re-extract the latest release bundle (recommended), or re-run `-Bootstrap` from a local git clone (contributors only), then run verify again.
> - `-Verify` is offline-only and checks against the local `file-manifest.config` and bundled payload in the installer directory.
> - Verification summaries include both files and directories checked.
<!-- -->
> [!NOTE]
> **Offline-only operations**: install, verify, and clean use the bundled payload (`aii/`) and local manifest. No network downloads occur during these operations.
> Install and verify also validate the bundled payload checksum (`aii.checksum`). If it fails, re-extract the release bundle or re-run `-Bootstrap`.
<!-- -->
> [!NOTE]
> Target installs require a `terraform-provider-azurerm` clone with an origin remote configured.
> The AI development repository is a source-only workspace and is not a valid install target.
<!-- -->
> [!NOTE]
> **Install a specific version (pinning)**: replace `latest/download` with a tagged release URL (`download/vX.Y.Z`).
>
> The version is the `vX.Y.Z` segment in the URL path. The filename can be either the stable (unversioned) asset name or the versioned asset name.
>
> - Example pinned URL (stable filename):
>   - `https://github.com/WodansSon/terraform-azurerm-ai-assisted-development/releases/download/v1.0.1/terraform-azurerm-ai-installer.tar.gz`
> - Example pinned URL (versioned filename):
>   - `https://github.com/WodansSon/terraform-azurerm-ai-assisted-development/releases/download/v1.0.1/terraform-azurerm-ai-installer-v1.0.1.tar.gz`
<!-- -->
> [!TIP]
> **For Contributors**: If you're contributing to this AI infrastructure project itself and have the repository cloned locally, the most reliable workflow is:
> 1) **From your local clone**, run Bootstrap to refresh the user-profile installer, then
> 2) run installs from your user profile using `-LocalPath` / `-local-path` to source AI files from your working tree.
> ```bash
> # Step 1 (Bootstrap) - run from your local clone
> cd terraform-azurerm-ai-assisted-development/installer
> ./install-copilot-setup.sh -bootstrap
> # PowerShell:
> #   cd terraform-azurerm-ai-assisted-development\installer
> #   .\install-copilot-setup.ps1 -Bootstrap
>
> # Step 2 (Install) - run from your user profile, sourcing AI files from your working tree
> # PowerShell:
> #   cd "$env:USERPROFILE\.terraform-azurerm-ai-installer"
> #   .\install-copilot-setup.ps1 -LocalPath "C:\path\to\terraform-azurerm-ai-assisted-development" -RepoDirectory "C:\path\to\terraform-provider-azurerm"
> # Bash:
> #   cd ~/.terraform-azurerm-ai-installer
> #   ./install-copilot-setup.sh -local-path "/path/to/terraform-azurerm-ai-assisted-development" -repo-directory "/path/to/terraform-provider-azurerm"
> ```
>
> **Why use Bootstrap instead of the release package?**
> - Tests your uncommitted changes to instruction files, installer scripts, and prompts
> - Copies your local working copy to the user profile installer location
> - Perfect for testing improvements before submitting a PR
>
> Normal users should use the release package download (above) - Bootstrap is only for contributors working on the AI infrastructure itself.

### What the Installer Does

- 🔧 **Installs AI instruction files** to your target repository's `.github/` directory
- 🔧 **Installs Agent Skills** to your target repository's `.github/skills/` directory (invocable via slash commands like `/docs-writer`)
- 🔧 **Configures workspace settings** in `.vscode/settings.json` for AI assistance
- 🔧 **Works per-repository** - each repo gets its own AI infrastructure
- 🔧 **Non-invasive** - doesn't modify your personal VS Code settings

For detailed installation options, see **[installer/README.md](installer/README.md)**


## ⚠️ Important: Development Workflow

**These AI infrastructure files are TEMPORARY development aids and should NOT be committed to the terraform-provider-azurerm repository.**

### Recommended Workflow

```powershell
# 1. Install AI infrastructure on your feature branch
cd ~/.terraform-azurerm-ai-installer
.\install-copilot-setup.ps1 -RepoDirectory "C:\path\to\terraform-provider-azurerm"

# 2. Develop with AI assistance
# (Work on your feature, use GitHub Copilot, get AI guidance)

# 3. BEFORE committing your code changes
.\install-copilot-setup.ps1 -RepoDirectory "C:\path\to\terraform-provider-azurerm" -Clean

# 4. Now commit only your actual code changes
cd C:\path\to\terraform-provider-azurerm
git add <your-files>
git commit -m "Your feature changes"
git push
```

### Why Clean Before Committing?

- ✅ Keeps the terraform-provider-azurerm repo clean
- ✅ Prevents accidental commits of AI instruction files
- ✅ Maintains HashiCorp's repository structure
- ✅ AI files are for YOUR local development only

**📌 Remember**: The AI infrastructure files live in `.github/` directory and other locations. They're meant to enhance your local development experience, not to be pushed to HashiCorp's repository.


## 💡 Usage Examples

### Generate a New Azure Resource
```
AI Chat: "Create a new Azure CDN Front Door Profile resource using typed implementation"
```

### Review Your Changes
```
/code-review-local-changes
```

### Generate Tests
```
AI Chat: "Create comprehensive acceptance tests for azurerm_cdn_frontdoor_profile"
```

### Generate Documentation
```
AI Chat: "Create documentation following provider standards for azurerm_cdn_frontdoor_profile"
```


## 🎬 See It In Action

### AI-Powered Resource Generation

Watch as GitHub Copilot generates complete Azure resources following HashiCorp standards:

```go
// Just describe what you want, and Copilot generates the implementation
// Example: "Create an azurerm_cdn_frontdoor_profile resource with typed SDK"

type CdnFrontDoorProfileResource struct{}

var _ sdk.Resource = CdnFrontDoorProfileResource{}

func (r CdnFrontDoorProfileResource) ResourceType() string {
    return "azurerm_cdn_frontdoor_profile"
}

func (r CdnFrontDoorProfileResource) ModelObject() interface{} {
    return &CdnFrontDoorProfileModel{}
}

func (r CdnFrontDoorProfileResource) Arguments() map[string]*pluginsdk.Schema {
    return map[string]*pluginsdk.Schema{ /* Complete schema */ }
}

func (r CdnFrontDoorProfileResource) Create() sdk.ResourceFunc {
    return sdk.ResourceFunc{
        Timeout: 30 * time.Minute,
        Func: func(ctx context.Context, metadata sdk.ResourceMetaData) error {
            // Typed resource implementation
            var model CdnFrontDoorProfileModel
            if err := metadata.Decode(&model); err != nil {
                return fmt.Errorf("decoding: %+v", err)
            }
            // ... implementation
        },
    }
}
```

**What You Get:**
- ✅ Complete CRUD operations following HashiCorp patterns
- ✅ Proper error handling with formatted errors
- ✅ Schema with correct types and validation
- ✅ Timeout configurations
- ✅ State management with metadata
- ✅ Azure API integration patterns

### Intelligent Code Reviews

Get instant feedback on your changes:

```
You: /code-review-local-changes

Copilot: Analyzing your changes...

✅ Schema design follows provider patterns
✅ Error handling uses fmt.Errorf with wrapping
✅ CRUD operations properly structured
⚠️  Consider adding validation for 'sku' field
⚠️  CustomizeDiff may be needed for 'tags'
```

### Test Generation Made Easy

```
You: "Generate acceptance tests for this resource"

Copilot generates:
- Basic test configuration
- Complete test cases
- Check functions with proper validations
- Import tests
- Update scenarios
```

### Real-Time Best Practice Guidance

As you type, Copilot suggests:
- Correct Azure SDK usage patterns
- Proper state management
- Error handling patterns
- Schema design improvements
- Documentation formatting


## 📚 What's Included?

### 🎓 Instruction Files (Comprehensive Guidelines)

| File | Purpose |
|------|---------|
| **implementation-guide** | Complete Go implementation patterns for typed and untyped resources |
| **azure-patterns** | Azure-specific PATCH operations, CustomizeDiff patterns |
| **testing-guidelines** | Test execution protocols and acceptance testing patterns |
| **documentation-guidelines** | Resource and data source documentation standards |
| **schema-patterns** | Schema design patterns and validation standards |
| **error-patterns** | Error handling patterns and debugging guidelines |
| **code-clarity-enforcement** | Code quality and comment policy standards |
| **provider-guidelines** | Azure Resource Manager integration best practices |
| **migration-guide** | Migration patterns and upgrade procedures |
| **api-evolution-patterns** | API evolution and versioning patterns |
| **security-compliance** | Security and compliance patterns |
| **performance-optimization** | Performance patterns and efficiency guidelines |
| **troubleshooting-decision-trees** | Diagnostic workflows and common issues |

### 🤖 AI Prompts

- **/code-review-local-changes** - Review uncommitted changes for compliance
- **/code-review-committed-changes** - Review commits and PRs for standards
- **/code-review-docs** - Review a `website/docs/**` page for docs standards + schema parity

### 🧠 Agent Skills

- **/docs-writer** - Write/update AzureRM provider docs in HashiCorp style (schema-aware; supports dry-run scaffolding into `website_scaffold_tmp`)
- **/resource-implementation** - Implement/update AzureRM provider resources using provider patterns
- **/acceptance-testing** - Write/troubleshoot AzureRM provider acceptance tests

### ⚙️ Configuration Templates

- VS Code settings optimized for AI-assisted development
- Copilot configuration for context-aware code generation


## 🎯 Key Features

### 🧠 Context-Aware AI

The instruction system provides AI with deep understanding of:
- ✅ HashiCorp's coding standards and patterns
- ✅ Azure API integration requirements
- ✅ Terraform Plugin SDK patterns
- ✅ Provider-specific best practices
- ✅ Testing and documentation standards

### 🔄 Continuous Learning

Instructions are based on actual HashiCorp provider patterns:
- Extracted from production code
- Validated against merged PRs
- Updated with new patterns
- Community-driven improvements

### 🛡️ Quality Enforcement

Automated checks for:
- Comment policy (zero tolerance for unnecessary comments)
- Error handling patterns
- Schema design standards
- CustomizeDiff validation
- Azure API integration


## 🤝 Contributing

This is a community project! Contributions are welcome:

1. **Report issues** - Found a bug or have a suggestion?
2. **Improve instructions** - Know a better pattern?
3. **Add examples** - Share your experience
4. **Test and provide feedback** - Help make it better
5. **Local source testing** - Test your AI instruction changes before publishing by installing from your working tree using `-LocalPath` / `-local-path` ([see installer docs](installer/README.md))

See [CONTRIBUTING.md](CONTRIBUTING.md) for guidelines.


## 📖 Documentation

- **[Installation Guide](installer/README.md)** - Detailed setup instructions
- **[Usage Examples](docs/EXAMPLES.md)** - Real-world usage scenarios
- **[Troubleshooting](docs/TROUBLESHOOTING.md)** - Common issues and solutions


## ⚖️ License

This project is licensed under the **Mozilla Public License 2.0 (MPL-2.0)** - the same license as the Terraform AzureRM Provider.

See [LICENSE](LICENSE) for details.


## 🙏 Acknowledgments

- **HashiCorp Team** - For building an amazing Terraform provider ecosystem
- **terraform-provider-azurerm contributors** - For establishing the patterns we codify
- **GitHub Copilot** - For making AI-assisted development possible


## 📣 Disclaimer

**This is a community-maintained project and is NOT officially supported by HashiCorp.**

This tool is designed to assist developers working with the [official Terraform AzureRM Provider](https://github.com/hashicorp/terraform-provider-azurerm) by providing AI-powered development assistance based on established provider patterns.


## 🔗 Related Projects

- [Terraform AzureRM Provider](https://github.com/hashicorp/terraform-provider-azurerm) - The official provider
- [Terraform Plugin SDK](https://github.com/hashicorp/terraform-plugin-sdk) - Plugin development framework
- [GitHub Copilot](https://github.com/features/copilot) - AI pair programmer


## 📞 Support

- **GitHub Issues**: [Report bugs or request features](https://github.com/WodansSon/terraform-azurerm-ai-assisted-development/issues)
- **Discussions**: [Ask questions and share experiences](https://github.com/WodansSon/terraform-azurerm-ai-assisted-development/discussions)


**Made with ❤️ by the Terraform community**
