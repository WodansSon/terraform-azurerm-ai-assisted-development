<picture>
  <source media="(prefers-color-scheme: dark)" srcset="../.github/architectureTitle-dark.png">
  <source media="(prefers-color-scheme: light)" srcset="../.github/architectureTitle-light.png">
  <img src="../.github/architectureTitle-light.png" alt="AI-Assisted Development Architecture" width="900" height="80">
</picture>

> **Comprehensive architectural overview of the AI-powered development infrastructure**

## System Architecture

```
┌──────────────────────────────────────────────────────────────────┐
│                      Developer Workspace                         │
│  ┌─────────────────────────────────────────────────────────────┐ │
│  │               VS Code with GitHub Copilot                   │ │
│  │  ┌───────────────────────────────────────────────────────┐  │ │
│  │  │   terraform-provider-azurerm Repository               │  │ │
│  │  │                                                       │  │ │
│  │  │   ├── internal/services/                              │  │ │
│  │  │   │   └── [Your Resource Code]                        │  │ │
│  │  │   └── website/docs/                                   │  │ │
│  │  │                                                       │  │ │
│  │  │   ┌────────────────────────────────────────────────┐  │  │ │
│  │  │   │   AI Infrustructure file install locations     │  │  │ │
│  │  │   │                                                │  │  │ │
│  │  │   │  ├──.github/                                   │  │  │ │
│  │  │   │  │  ├── copilot-instructions.md (Main)         │  │  │ │
│  │  │   │  │  ├── prompts/                               │  │  │ │
│  │  │   │  │  │   ├── code-review-local-changes...       │  │  │ │
│  │  │   │  │  │   ├── code-review-committed-changes...   │  │  │ │
│  │  │   │  │  │   └── code-review-docs.prompt.md         │  │  │ │
│  │  │   │  │  ├── skills/                                │  │  │ │
│  │  │   │  │  │   ├── acceptance-testing/SKILL.md        │  │  │ │
│  │  │   │  │  │   ├── custom-poller-migration/SKILL.md   │  │  │ │
│  │  │   │  │  │   ├── docs-writer/SKILL.md               │  │  │ │
│  │  │   │  │  │   └── resource-implementation/SKILL.md   │  │  │ │
│  │  │   │  │  └── instructions/                          │  │  │ │
│  │  │   │  │      ├── code-review-compliance-contract... │  │  │ │
│  │  │   │  │      ├── implementation-compliance-contr... │  │  │ │
│  │  │   │  │      ├── docs-compliance-contract...        │  │  │ │
│  │  │   │  │      ├── testing-compliance-contract...     │  │  │ │
│  │  │   │  │      ├── ai-skill-routing-*.instructions... │  │  │ │
│  │  │   │  │      └── [20 runtime instruction files]     │  │  │ │
│  │  │   │  └── .vscode/settings.json                     │  │  │ │
│  │  │   └────────────────────────────────────────────────┘  │  │ │
│  │  └───────────────────────────────────────────────────────┘  │ │
│  │                                                             │ │
│  │  ┌───────────────────────────────────────────────────────┐  │ │
│  │  │          VS Code GitHub Copilot AI Engine             │  │ │
│  │  │                                                       │  │ │
│  │  │  - Reads instruction files automatically              │  │ │
│  │  │  - Loads Agent Skills from .github/skills/            │  │ │
│  │  │  - Applies context-aware patterns                     │  │ │
│  │  │  - Generates code following HashiCorp standards       │  │ │
│  │  │  - Provides intelligent code reviews                  │  │ │
│  │  └───────────────────────────────────────────────────────┘  │ │
│  └─────────────────────────────────────────────────────────────┘ │
└──────────────────────────────────────────────────────────────────┘

┌──────────────────────────────────────────────────────────────────┐
│                  Installation & Distribution                     │
│  ┌─────────────────────────────────────────────────────────────┐ │
│  │  terraform-azurerm-ai-assisted-development Repository       │ │
│  │                                                             │ │
│  │  installer/                                                 │ │
│  │  ├── install-copilot-setup.ps1 (Windows)                    │ │
│  │  ├── install-copilot-setup.sh (Cross-platform)              │ │
│  │  ├── file-manifest.config                                   │ │
│  │  ├── aii/ (payload root - populated in bundles/bootstrap)   │ │
│  │  └── modules/                                               │ │
│  │      ├── powershell/                                        │ │
│  │      └── bash/                                              │ │
│  └─────────────────────────────────────────────────────────────┘ │
└──────────────────────────────────────────────────────────────────┘
```

## Installation Flow

### Option 1: Release Bundle (Recommended - No Repo Clone Needed)

```
┌─────────────────────────────────────────────────────────────┐
│ Download Installer Bundle from GitHub Releases (Latest)     │
└────────────────────────────┬────────────────────────────────┘
                             │
                             ▼
┌─────────────────────────────────────────────────────────────┐
│  Extract to User Profile (One-Time)                         │
│  - Windows: %USERPROFILE%\.terraform-azurerm-ai-installer   │
│  - MacOS/Unix: ~/.terraform-azurerm-ai-installer            │
└────────────────────────────┬────────────────────────────────┘
                             │
                             ▼
┌─────────────────────────────────────────────────────────────┐
│  Run Installer with Target Repository                       │
│  PowerShell: -RepoDirectory "path"                          │
│  Bash: -repo-directory "path"                               │
└────────────────────────────┬────────────────────────────────┘
                             │
                             ▼
┌─────────────────────────────────────────────────────────────┐
│  Installer Copies AI Files from Bundled Payload             │
│  (offline, no GitHub/raw downloads at runtime):             │
│                                                             │
│  ├── .github/copilot-instructions.md                        │
│  ├── .github/prompts/                                       │
│  │   ├── code-review-local-changes.prompt.md                │
│  │   ├── code-review-committed-changes.prompt.md            │
│  │   └── code-review-docs.prompt.md                         │
│  ├── .github/skills/                                        │
│  │   └── */SKILL.md                                         │
│  ├── .github/instructions/                                  │
│  │   ├── code-review-compliance-contract.instructions.md    │
│  │   ├── implementation-compliance-contract.instructions.md │
│  │   ├── docs-compliance-contract.instructions.md           │
│  │   ├── testing-compliance-contract.instructions.md        │
│  │   ├── ai-skill-routing-*.instructions.md                 │
│  │   └── [20 instruction files total]                       │
│  ├── .github/skills/                                        │
│  │   ├── acceptance-testing/SKILL.md                        │
│  │   ├── custom-poller-migration/SKILL.md                   │
│  │   ├── docs-writer/SKILL.md                               │
│  │   └── resource-implementation/SKILL.md                   │
│  └── .vscode/settings.json                                  │
└────────────────────────────┬────────────────────────────────┘
                             │
                             ▼
┌─────────────────────────────────────────────────────────────┐
│  Success: GitHub Copilot Ready!                             │
│  - Files copied from local payload                          │
│  - AI development environment active                        │
└─────────────────────────────────────────────────────────────┘
```

### Option 2: Bootstrap from Cloned Repo

```
┌──────────────────────────────────────────────────────────────┐
│  Clone Repository (Contributors)                             │
│  - git checkout branch                                       │
└────────────────────────────┬─────────────────────────────────┘
                             │
                             ▼
┌──────────────────────────────────────────────────────────────┐
│  Run Bootstrap from Cloned Repo Branch                       │
│  PowerShell: -Bootstrap                                      │
│  Bash: -bootstrap                                            │
└────────────────────────────┬─────────────────────────────────┘
                             │
                             ▼
┌──────────────────────────────────────────────────────────────┐
│  Copies Installer from Source Repo to User Profile           │
│  - Windows: %USERPROFILE%\.terraform-azurerm-ai-installer    │
│  - MacOS/Unix: ~/.terraform-azurerm-ai-installer             │
│                                                              │
│  installer/                                                  │
│  ├── install-copilot-setup.ps1 (Windows)                     │
│  ├── install-copilot-setup.sh (Cross-platform)               │
│  ├── file-manifest.config                                    │
│  ├── aii/ (offline payload built from manifest)              │
│  └── modules/                                                │
│      ├── powershell/                                         │
│      └── bash/                                               │
└────────────────────────────┬─────────────────────────────────┘
                             │
                             ▼
┌──────────────────────────────────────────────────────────────┐
│  Run Installer from User Profile with Target Repository      │
│  Same execution location as Option 1 (payload is local).     │
│  -LocalPath / -local-path is a contributor override to       │
│  source AI files from a working tree instead of the payload. │
└──────────────────────────────────────────────────────────────┘
```


#### Source Model Summary

- Default source: bundled offline payload in `aii/` next to the installer you are running.
- Override source: `-LocalPath` / `-local-path` (copies from a local working tree; useful for contributors).
- Runtime network access: not required (after you have the release bundle or have bootstrapped from a clone).

## GitHub Copilot Integration

### How Instructions Are Applied

```
┌──────────────────────────────────────────────────────────────────────┐
│  1. Developer Opens File in VS Code                                  │
│     internal/services/cdn/cdn_frontdoor_profile_resource.go          │
└────────────────────────────┬─────────────────────────────────────────┘
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
└────────────────────────────┬─────────────────────────────────────────┘
                             │
                             ▼
┌──────────────────────────────────────────────────────────────────────┐
│  3. Developer Types or Prompts Copilot                               │
│     "Create PATCH update operation for this resource"                │
└────────────────────────────┬─────────────────────────────────────────┘
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
.github/copilot-instructions.md (Root runtime guidance)
│
├── Workspace-First Knowledge Policy
├── Risk-Based Safety Guidelines
├── Partnership Standards
└── Core Development Patterns
    │
    ▼
instructions/*.instructions.md (Specialized - Applied by file pattern)
│
├── *-compliance-contract.instructions.md
│   └── Shared rule authority and stable rule IDs
│
├── ai-skill-routing-*.instructions.md
│   └── File-type routing into runtime skills
│
├── implementation/docs/testing companion guides
│   └── Examples, heuristics, and companion patterns
│
└── [20 runtime instruction files in total]
    │
    ▼
skills/*/SKILL.md (On-demand - Applied when invoked via /<skill>)
│
├── Runtime skills shipped to target repos
│   ├── acceptance-testing
│   ├── custom-poller-migration
│   ├── docs-writer
│   └── resource-implementation
│
└── Repo-only maintainer skills in this repository
  ├── ai-toolkit-maintenance
  └── changelog-maintenance
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
│   ├── .markdownlint.json
│   ├── copilot-instructions.md
│   ├── instructions/
│   │   ├── ai-skill-routing-docs.instructions.md
│   │   ├── ai-skill-routing-resource-implementation.instructions.md
│   │   ├── ai-skill-routing-tests.instructions.md
│   │   ├── api-evolution-patterns.instructions.md
│   │   ├── azure-patterns.instructions.md
│   │   ├── code-clarity-enforcement.instructions.md
│   │   ├── code-review-compliance-contract.instructions.md
│   │   ├── docs-compliance-contract.instructions.md
│   │   ├── documentation-guidelines.instructions.md
│   │   ├── error-patterns.instructions.md
│   │   ├── implementation-compliance-contract.instructions.md
│   │   ├── implementation-guide.instructions.md
│   │   ├── migration-guide.instructions.md
│   │   ├── performance-optimization.instructions.md
│   │   ├── provider-guidelines.instructions.md
│   │   ├── schema-patterns.instructions.md
│   │   ├── security-compliance.instructions.md
│   │   ├── testing-compliance-contract.instructions.md
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
│   │   └── code-review-docs.prompt.md
│   │
│   ├── skills/
│   │   ├── acceptance-testing/SKILL.md
│   │   ├── ai-toolkit-maintenance/SKILL.md
│   │   ├── changelog-maintenance/SKILL.md
│   │   ├── custom-poller-migration/SKILL.md
│   │   ├── resource-implementation/SKILL.md
│   │   └── docs-writer/SKILL.md
│   │
│   ├── workflows/
│   │   ├── contracts-validation.yml
│   │   ├── docs-validation.yml
│   │   ├── installer-validation.yml
│   │   ├── regression-harness-validation.yml
│   │   ├── release.yml
│   │   └── validate.yml
│   │
│   └── pull_request_template.md
│
├── installer/
│   ├── aii/
│   ├── file-manifest.config
│   ├── install-copilot-setup.ps1
│   ├── install-copilot-setup.sh
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
│   ├── README.md
│   └── VERSION
│
├── docs/
│   ├── AI_CUSTOMIZATION_ARCHITECTURE_STANDARD.md
│   ├── AI_CUSTOMIZATION_MIGRATION_INVENTORY.md
│   ├── AI_REGRESSION_HARNESS.md
│   ├── AI_TOOLKIT_ALIGNMENT_CHECKLIST.md
│   ├── ARCHITECTURE.md
│   ├── CODE_REVIEW_RULES.md
│   ├── EXAMPLES.md
│   └── TROUBLESHOOTING.md
│
├── tools/
│   ├── check-upstream-contributor-drift.ps1
│   ├── validate-ai-toolkit.ps1
│   ├── validate-changelog-taxonomy.ps1
│   ├── validate-contracts.ps1
│   ├── verify-bundle-checksum.ps1
│   ├── config/
│   ├── BashAnalyzer/
│   ├── PSAnalyzer/
│   └── regression/
│       ├── cases/
│       ├── config/
│       ├── examples/
│       ├── fixtures/
│       ├── results/
│       ├── runs/
│       ├── schema/
│       ├── build-regression-test.ps1
│       ├── run-regression-harness.ps1
│       ├── run-regression-suite.ps1
│       ├── scaffold-regression-spec.ps1
│       ├── scaffold-regression-result.ps1
│       └── score-regression-case.ps1
│
├── .vscode/
│   └── settings.json
│
├── README.md
├── CHANGELOG.md
├── CONTRIBUTING.md
└── LICENSE
```

### Runtime Payload Vs. Repo-Only Maintenance

The repository contains both shipped runtime guidance and repo-only maintainer tooling.

- Runtime payload is defined by `installer/file-manifest.config` and installed into target repositories.
- Runtime payload currently includes `.github/copilot-instructions.md`, `.github/instructions/**`, `.github/prompts/**`, four shipped runtime skills under `.github/skills/`, and `.vscode/settings.json`.
- Repo-only maintenance surfaces stay in this repository and are not installed into target repos.
- Repo-only surfaces include maintainer skills such as `ai-toolkit-maintenance` and `changelog-maintenance`, the `docs/` architecture and alignment references, and the validation and regression tooling under `tools/`.

### Validation And Regression Surfaces

The current repository architecture includes deterministic validation and benchmark tooling alongside the runtime payload:

- `tools/validate-ai-toolkit.ps1`: one-shot maintainer validation for changelog, contracts, markdown, regression harness, and upstream drift.
- `tools/validate-contracts.ps1`: contract structure and consumer wiring validation.
- `tools/check-upstream-contributor-drift.ps1`: deterministic upstream contributor drift detection.
- `tools/regression/`: adjudicated benchmark cases, fixtures, expected examples, scoring, run hydration, and history snapshots for prompt and contract regressions.
- `docs/AI_REGRESSION_HARNESS.md`: the benchmark model and scoring philosophy behind the regression suite.

### Prompt Files (high-level)

The prompt files under `.github/prompts/` are invoked via slash commands in GitHub Copilot Chat.

Docs components (quick links):
- Contract: `.github/instructions/docs-compliance-contract.instructions.md`
- Auditor prompt: `.github/prompts/code-review-docs.prompt.md`
- Writer skill: `.github/skills/docs-writer/SKILL.md`
- Rule reference: `docs/CODE_REVIEW_RULES.md`

- `/code-review-local-changes`: reviews local workspace changes and uses local-diff linting.
- `/code-review-committed-changes`: reviews committed branch changes against `origin/main`, prefers authoritative PR scope when available, and uses PR-scoped linting. When PR context is not already available, users can pass a PR number explicitly, for example `/code-review-committed-changes PR 12345`.
- `/code-review-docs`: deterministic docs review for `website/docs/**` pages (enforces `hcl` code fences in Terraform examples, self-contained resource examples, existing-object lookup data source examples, list-resource query examples, ephemeral-resource doc shape, function doc shape, import example ID shape validation, and human-readable timeout defaults).
- Rule citations such as `REVIEW-SCOPE-005` and `DOCS-EX-003` are explained in `docs/CODE_REVIEW_RULES.md`.

### Docs governance (contract, prompt, skill)

This repository intentionally separates docs *rules* from docs *workflows*:

- **Contract (rules)**: `.github/instructions/docs-compliance-contract.instructions.md`
  - Single source of truth for docs compliance rules (`DOCS-*` IDs), precedence, and evidence guardrails.
- **Prompt (auditor)**: `.github/prompts/code-review-docs.prompt.md`
  - Audit-only validation of the currently-open `website/docs/**` page.
  - Does not run repo tooling; derives findings from static workspace evidence.
- **Skill (writer)**: `.github/skills/docs-writer/SKILL.md`
  - Applies the contract to write/update docs.
  - Uses docs scaffolding only for brand-new docs pages (or when explicitly requested as a scaffold/dry-run baseline).

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
