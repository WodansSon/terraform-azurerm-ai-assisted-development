<picture>
  <source media="(prefers-color-scheme: dark)" srcset="../.github/architectureTitle-dark.png">
  <source media="(prefers-color-scheme: light)" srcset="../.github/architectureTitle-light.png">
  <img src="../.github/architectureTitle-light.png" alt="AI-Assisted Development Architecture" width="900" height="80">
</picture>

> **Comprehensive architectural overview of the AI-powered development infrastructure**

## System Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                      Developer Workspace                        │
│  ┌────────────────────────────────────────────────────────────┐ │
│  │               VS Code with GitHub Copilot                  │ │
│  │  ┌──────────────────────────────────────────────────────┐  │ │
│  │  │   terraform-provider-azurerm Repository              │  │ │
│  │  │                                                      │  │ │
│  │  │   ├── internal/services/                             │  │ │
│  │  │   │   └── [Your Resource Code]                       │  │ │
│  │  │   └── website/docs/                                  │  │ │
│  │  │                                                      │  │ │
│  │  │   ┌───────────────────────────────────────────────┐  │  │ │
│  │  │   │   AI Infrustructure file install locations    │  │  │ │
│  │  │   │                                               │  │  │ │
│  │  │   │  ├──.github/                                  │  │  │ │
│  │  │   │  │  ├── copilot-instructions.md (Main)        │  │  │ │
│  │  │   │  │  ├── prompts/                              │  │  │ │
│  │  │   │  │  │   ├── code-review-local-changes...      │  │  │ │
│  │  │   │  │  │   ├── code-review-committed-changes...  │  │  │ │
│  │  │   │  │  │   └── docs-schema-audit.prompt.md       │  │  │ │
│  │  │   │  │  ├── skills/                               │  │  │ │
│  │  │   │  │  │   ├── azurerm-docs-writer/SKILL.md      │  │  │ │
│  │  │   │  │  │   └── [other skill files]               │  │  │ │
│  │  │   │  │  └── instructions/                         │  │  │ │
│  │  │   │  │      ├── api-evolution-patterns.md         │  │  │ │
│  │  │   │  │      ├── azure-patterns.md                 │  │  │ │
│  │  │   │  │      ├── testing-guidelines.md             │  │  │ │
│  │  │   │  │      └── [12+ more instruction files]      │  │  │ │
│  │  │   │  └── .vscode/settings.json                    │  │  │ │
│  │  │   └───────────────────────────────────────────────┘  │  │ │
│  │  └──────────────────────────────────────────────────────┘  │ │
│  │                                                            │ │
│  │  ┌──────────────────────────────────────────────────────┐  │ │
│  │  │          VS Code GitHub Copilot AI Engine            │  │ │
│  │  │                                                      │  │ │
│  │  │  - Reads instruction files automatically             │  │ │
│  │  │  - Loads Agent Skills from .github/skills/           │  │ │
│  │  │  - Applies context-aware patterns                    │  │ │
│  │  │  - Generates code following HashiCorp standards      │  │ │
│  │  │  - Provides intelligent code reviews                 │  │ │
│  │  └──────────────────────────────────────────────────────┘  │ │
│  └────────────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────┐
│                  Installation & Distribution                    │
│  ┌────────────────────────────────────────────────────────────┐ │
│  │  terraform-azurerm-ai-assisted-development Repository      │ │
│  │                                                            │ │
│  │  installer/                                                │ │
│  │  ├── install-copilot-setup.ps1 (Windows)                   │ │
│  │  ├── install-copilot-setup.sh (Cross-platform)             │ │
│  │  ├── file-manifest.config                                  │ │
│  │  └── modules/                                              │ │
│  │      ├── powershell/                                       │ │
│  │      └── bash/                                             │ │
│  └────────────────────────────────────────────────────────────┘ │
└─────────────────────────────────────────────────────────────────┘
```

## Installation Flow

### Option 1: Release Bundle (Recommended - No Repo Clone Needed)

```
┌───────────────────────────────────────────────────────────┐
│ Download Installer Bundle from GitHub Releases (Latest)   │
└────────────────────────────┬──────────────────────────────┘
                             │
                             ▼
┌───────────────────────────────────────────────────────────┐
│  Extract to User Profile (One-Time)                       │
│  - Windows: %USERPROFILE%\.terraform-azurerm-ai-installer │
│  - MacOS/Unix: ~/.terraform-azurerm-ai-installer          │
└────────────────────────────┬──────────────────────────────┘
                             │
                             ▼
┌───────────────────────────────────────────────────────────┐
│  Run Installer with Target Repository                     │
│  PowerShell: -RepoDirectory "path"                        │
│  Bash: -repo-directory "path"                             │
└────────────────────────────┬──────────────────────────────┘
                             │
                             ▼
┌───────────────────────────────────────────────────────────┐
│  Installer Downloads AI Files via GitHub                  │
│  raw URLs to Target Repo :                                │
│                                                           │
│  ├── .github/copilot-instructions.md                      │
│  ├── .github/prompts/                                     │
│  │   ├── code-review-local-changes.prompt.md              │
│  │   ├── code-review-committed-changes.prompt.md          │
│  │   └── docs-schema-audit.prompt.md                      │
│  ├── .github/skills/                                      │
│  │   └── */SKILL.md                                       │
│  ├── .github/instructions/                                │
│  │   ├── api-evolution-patterns.md                        │
│  │   ├── azure-patterns.md                                │
│  │   ├── testing-guidelines.md                            │
│  │   └── [13 instruction files total]                     │
│  └── .vscode/settings.json                                │
└────────────────────────────┬──────────────────────────────┘
                             │
                             ▼
┌───────────────────────────────────────────────────────────┐
│  Success: GitHub Copilot Ready!                           │
│  - Files installed from GitHub                            │
│  - AI development environment active                      │
└───────────────────────────────────────────────────────────┘
```

### Option 2: Bootstrap from Cloned Repo (Contributors Only)

```
┌───────────────────────────────────────────────────────────┐
│  Clone Repository (Contributors)                          │
│  - git checkout branch                                    │
└────────────────────────────┬──────────────────────────────┘
                             │
                             ▼
┌───────────────────────────────────────────────────────────┐
│  Run Bootstrap from Cloned Repo Branch                    │
│  PowerShell: -Bootstrap                                   │
│  Bash: -bootstrap                                         │
└────────────────────────────┬──────────────────────────────┘
                             │
                             ▼
┌───────────────────────────────────────────────────────────┐
│  Copies Installer from Source Repo to User Profile        │
│  - Windows: %USERPROFILE%\.terraform-azurerm-ai-installer │
│  - MacOS/Unix: ~/.terraform-azurerm-ai-installer          │
│                                                           │
│  installer/                                               │
│  ├── install-copilot-setup.ps1 (Windows)                  │
│  ├── install-copilot-setup.sh (Cross-platform)            │
│  ├── file-manifest.config                                 │
│  └── modules/                                             │
│      ├── powershell/                                      │
│      └── bash/                                            │
└────────────────────────────┬──────────────────────────────┘
                             │
                             ▼
┌───────────────────────────────────────────────────────────┐
│  Run Installer from User Profile with Target Repository   │
│  Same flow as Option 1 from here                          │
└───────────────────────────────────────────────────────────┘
```

## GitHub Copilot Integration

### How Instructions Are Applied

```
┌──────────────────────────────────────────────────────────────────────┐
│  1. Developer Opens File in VS Code                                  │
│     internal/services/cdn/cdn_frontdoor_profile_resource.go          │
└────────────────────────┬─────────────────────────────────────────────┘
                         │
                         ▼
┌──────────────────────────────────────────────────────────────────────┐
│  2. Copilot Loads Applicable Instructions                            │
│                                                                      │
│     Matches file pattern: internal/**/*.go                           │
│     Loads: copilot-instructions.md                                   │
│     Loads: .github/instructions/azure-patterns.instructions.md       │
│     Loads: .github/instructions/implementation-guide.instructions.md │
│     Loads: .github/instructions/error-patterns.instructions.md       │
│     Loads: .github/skills/*/SKILL.md (when invoked)                  │
└────────────────────────┬─────────────────────────────────────────────┘
                         │
                         ▼
┌──────────────────────────────────────────────────────────────────────┐
│  3. Developer Types or Prompts Copilot                               │
│     "Create PATCH update operation for this resource"                │
└────────────────────────┬─────────────────────────────────────────────┘
                         │
                         ▼
┌──────────────────────────────────────────────────────────────────────┐
│  4. Copilot Generates Code Using Instructions                        │
│                                                                      │
│     - Uses fmt.Errorf with %+v (error-patterns)                      │
│     - Implements PATCH pattern (azure-patterns)                      │
│     - Adds proper timeouts (implementation-guide)                    │
│     - Includes metadata tracking (implementation-guide)              │
│     - Uses skill rules when invoked (skills)                         │
│     - Follows HashiCorp code style (copilot-instructions)            │
└──────────────────────────────────────────────────────────────────────┘
```

### Instruction File Hierarchy

```
copilot-instructions.md (Root - Applied to ALL files)
│
├── Workspace-First Knowledge Policy
├── Risk-Based Safety Guidelines
├── Partnership Standards
└── Core Development Patterns
    │
    ▼
instructions/*.instructions.md (Specialized - Applied by file pattern)
│
├── api-evolution-patterns.md
│   └── Breaking change detection
│   └── Version compatibility
│
├── azure-patterns.md
│   └── Azure API patterns (PUT/PATCH/POST)
│   └── Async operations & polling
│
├── testing-guidelines.md
│   └── ImportStep() patterns
│   └── Acceptance test structure
│
└── [11 more specialized files...]
    │
    ▼
skills/*/SKILL.md (On-demand - Applied when invoked via /<skill>)
│
├── azurerm-docs-writer
├── azurerm-resource-implementation
└── azurerm-acceptance-testing
```

### Context Awareness Flow

```
Developer Action  ->  Copilot Processing  ->  Output with Instructions Applied
────────────────     ──────────────────       ─────────────────────────────────
Write test        ->  Loads testing-      ->  Generates test using
function             guidelines.md            - ImportStep() pattern
                                              - ExistsInAzure() only
                                              - No redundant checks

Implement PATCH   ->  Loads azure-        ->  Generates PATCH with
operation            patterns.md              - GET existing state
                                              - Build update payload
                                              - Proper error wrapping

Add schema field  ->  Loads schema-       ->  Generates schema with
                     patterns.md              - Correct type
                                              - Validation functions
                                              - Required/Optional/Computed

Write docs        ->  Loads               ->  Generates docs with
                     documentation-           - Proper frontmatter
                     guidelines.md            - Example usage
                                              - Argument reference
                                              - Skill rules when invoked (skills)
```

## File Organization

### Repository Structure

```
terraform-azurerm-ai-assisted-development/
│
├── .github/
│   ├── instructions/
│   │   ├── api-evolution-patterns.instructions.md
│   │   ├── azure-patterns.instructions.md
│   │   ├── code-clarity-enforcement.instructions.md
│   │   ├── documentation-guidelines.instructions.md
│   │   ├── error-patterns.instructions.md
│   │   ├── implementation-guide.instructions.md
│   │   ├── migration-guide.instructions.md
│   │   ├── performance-optimization.instructions.md
│   │   ├── provider-guidelines.instructions.md
│   │   ├── schema-patterns.instructions.md
│   │   ├── security-compliance.instructions.md
│   │   ├── testing-guidelines.instructions.md
│   │   └── troubleshooting-decision-trees.instructions.md
│   │
│   ├── ISSUE_TEMPLATE/
│   │   ├── bug_report.md
│   │   ├── feature_request.md
│   │   └── instruction_improvement.md
│   │
│   ├── prompts/
│   │   ├── code-review-local-changes.prompt.md
│   │   ├── code-review-committed-changes.prompt.md
│   │   └── docs-schema-audit.prompt.md
│   │
│   ├── skills/
│   │   ├── azurerm-acceptance-testing/SKILL.md
│   │   ├── azurerm-resource-implementation/SKILL.md
│   │   └── azurerm-docs-writer/SKILL.md
│   │
│   ├── workflows/
│   │   ├── validate.yml    # CI for installers & instructions
│   │   └── release.yml     # Automated releases
│   │
│   └── copilot-instructions.md
│
├── installer/
│   ├── install-copilot-setup.ps1    # Cross-platform PowerShell
│   ├── install-copilot-setup.sh     # Traditional Bash
│   ├── file-manifest.config         # Files to copy
│   │
│   ├── modules/
│   │   ├── powershell/
│   │   │   ├── CommonUtilities.psm1
│   │   │   ├── ConfigParser.psm1
│   │   │   ├── FileOperations.psm1
│   │   │   ├── UI.psm1
│   │   │   └── ValidationEngine.psm1
│   │   │
│   │   └── bash/
│   │       ├── configparser.sh
│   │       ├── fileoperations.sh
│   │       ├── ui.sh
│   │       └── validationengine.sh
│   │
│   └── README.md
│
├── .vscode
│   └── settings.json
│
├── docs/
│   ├── EXAMPLES.md
│   ├── TROUBLESHOOTING.md
│   └── ARCHITECTURE.md (this file)
│
├── copilot-instructions.md
├── README.md
├── CHANGELOG.md
├── CONTRIBUTING.md
└── LICENSE
```

## Design Principles

### 1. Workspace-First Approach
- Instructions are loaded from the workspace, not hardcoded
- Context-aware suggestions based on file type and location
- Allows for custom overrides and extensions

### 2. Modular Instruction Files
- Each instruction file focuses on specific domain
- Files can be independently updated
- `applyTo` patterns ensure correct context

### 3. Cross-Platform Compatibility
- PowerShell Core works on all platforms
- Traditional Bash for Unix-like systems
- Consistent experience regardless of OS

### 4. Non-Intrusive Installation
- Backs up existing configuration
- Can be easily uninstalled
- Doesn't modify original repository structure

### 5. Community-Driven
- Open source and forkable
- Encourages contributions
- Maintained separately from HashiCorp repos

---

**Related Documentation:**
- [README](../README.md)
- [Examples](EXAMPLES.md)
- [Troubleshooting](TROUBLESHOOTING.md)
- [Contributing](../CONTRIBUTING.md)
