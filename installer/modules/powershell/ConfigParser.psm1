# ConfigParser Module for Terraform AzureRM Provider AI Setup
# Handles configuration file parsing, validation, and management
# STREAMLINED VERSION - Contains only functions actually used by main script

# Note: CommonUtilities module is imported globally by the main script

#region Public Functions

function Get-ManifestConfig {
    <#
    .SYNOPSIS
    Parse the file manifest configuration and return structured data

    .PARAMETER ManifestPath
    Path to the manifest file. Defaults to file-manifest.config in the AIinstaller directory

    .PARAMETER Branch
    Git branch for remote URLs
    #>
    param(
        [string]$ManifestPath,
        [string]$Branch = "main"
    )

    # Find manifest file if not specified
    if (-not $ManifestPath) {
        # Try to find manifest file in multiple locations
        $possiblePaths = @(
            # User profile installer directory (when running from bootstrapped copy)
            (Join-Path (Get-UserHomeDirectory) ".terraform-azurerm-ai-installer" | Join-Path -ChildPath "file-manifest.config"),
            # Current script directory (when running from user profile)
            (Join-Path (Split-Path $PSScriptRoot -Parent) "file-manifest.config"),
            # Original repository structure (when running from source)
            (Join-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) "file-manifest.config")
        )

        $ManifestPath = $null
        foreach ($path in $possiblePaths) {
            if (Test-Path $path) {
                $ManifestPath = $path
                break
            }
        }

        if (-not $ManifestPath) {
            # Fallback to old behavior
            $scriptRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent
            $ManifestPath = Join-Path $scriptRoot "file-manifest.config"
        }
    }

    if (-not (Test-Path $ManifestPath)) {
        throw "Manifest file not found: $ManifestPath"
    }

    $manifest = @{
        Branch = $Branch
        BaseUrl = "https://raw.githubusercontent.com/WodansSon/terraform-azurerm-ai-assisted-development/$Branch"
        Sections = @{}
    }

    # Validate branch exists by checking if file-manifest.config is accessible
    try {
        $testUrl = "$($manifest.BaseUrl)/installer/file-manifest.config"
        $null = Invoke-WebRequest -Uri $testUrl -Method Head -UseBasicParsing -ErrorAction Stop
    }
    catch {
        throw "Branch '$Branch' does not exist in the terraform-azurerm-ai-assisted-development repository. Please specify a valid branch name."
    }

    $currentSection = $null
    $content = Get-Content $ManifestPath

    foreach ($line in $content) {
        $line = $line.Trim()

        # Skip empty lines and comments
        if (-not $line -or $line.StartsWith('#')) {
            continue
        }

        # Check for section headers
        if ($line.StartsWith('[') -and $line.EndsWith(']')) {
            $currentSection = $line.Substring(1, $line.Length - 2)
            $manifest.Sections[$currentSection] = @()
            continue
        }

        # Add files to current section
        if ($currentSection -and $line) {
            $manifest.Sections[$currentSection] += $line
        }
    }

    return $manifest
}

function Get-InstallerConfig {
    <#
    .SYNOPSIS
    Get the complete installer configuration with all file mappings and targets

    .PARAMETER WorkspaceRoot
    The root directory of the workspace

    .PARAMETER ManifestConfig
    The manifest configuration from Get-ManifestConfig

    .PARAMETER Branch
    Git branch to use for source repository (defaults to main)
    #>
    param(
        [Parameter(Mandatory)]
        [string]$WorkspaceRoot,

        [Parameter(Mandatory)]
        [hashtable]$ManifestConfig,

        [string]$Branch = "main"
    )

    # DOWNLOAD SOURCE: Use specified branch for downloading AI files
    # DOWNLOAD TARGET: Copy files to the local workspace directory (regardless of local branch)

    $version = "dev"
    $versionPath = Join-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) "VERSION"
    if (Test-Path $versionPath) {
        $candidate = (Get-Content -Path $versionPath -Raw).Trim()
        if ($candidate -match '^(?:\d+\.\d+\.\d+|dev(?:-[0-9a-f]{7,40})?(?:-dirty)?)$') {
            $version = $candidate
        }
    }

    return @{
        Version = $version
        Branch = $Branch
        SourceRepository = "https://raw.githubusercontent.com/WodansSon/terraform-azurerm-ai-assisted-development/$Branch"
        Files = @{
            Instructions = @{
                Source = ".github/copilot-instructions.md"
                Target = (Join-Path $WorkspaceRoot ".github/copilot-instructions.md")
                Description = "Main Copilot instructions for AI-powered development"
            }
            InstructionFiles = @{
                Target = (Join-Path $WorkspaceRoot ".github/instructions")
                Description = "Detailed implementation guidelines and patterns"
                Files = $ManifestConfig.Sections.INSTRUCTION_FILES
            }
            PromptFiles = @{
                Target = (Join-Path $WorkspaceRoot ".github/prompts")
                Description = "AI prompt templates for development workflows"
                Files = $ManifestConfig.Sections.PROMPT_FILES
            }
            SkillFiles = @{
                Target = (Join-Path $WorkspaceRoot ".github/skills")
                Description = "Agent Skills for specialized Copilot workflows"
                Files = $ManifestConfig.Sections.SKILL_FILES
            }
            UniversalFiles = @{
                Target = (Join-Path $WorkspaceRoot ".vscode")
                Description = "Platform-independent configuration files"
                Files = $ManifestConfig.Sections.UNIVERSAL_FILES
            }
        }
    }
}

#endregion

# Export only the functions actually used by the main script
Export-ModuleMember -Function @(
    'Get-ManifestConfig',
    'Get-InstallerConfig'
)
