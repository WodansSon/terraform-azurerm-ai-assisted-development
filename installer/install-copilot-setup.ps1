# Main AI Infrastructure Installer for Terraform AzureRM Provider
# Version: see VERSION file
# Description: Interactive installer for AI-powered development infrastructure
# Platform: Cross-platform (Windows, macOS, Linux with PowerShell Core)

#requires -version 5.1

#region Script Configuration

# Installer version is centralized in the VERSION file
$script:InstallerVersion = "dev"

$versionPath = Join-Path $PSScriptRoot "VERSION"
if (Test-Path $versionPath) {
    $candidate = (Get-Content -Path $versionPath -Raw).Trim()
    if ($candidate -match '^(?:\d+\.\d+\.\d+|dev(?:-[0-9a-f]{7,40})?(?:-dirty)?)$') {
        $script:InstallerVersion = $candidate
    }
}

#endregion Script Configuration

#region Parameter Parsing and Validation

#region Variable Initialization

$Bootstrap = $false
$RepoDirectory = ""
$Contributor = $false
$Branch = ""
$LocalPath = ""
$DryRun = $false
$Verify = $false
$Clean = $false
$Help = $false

#endregion Variable Initialization

#region Early Helper Functions

# Simple error header for early parameter validation (before modules load)
function Show-EarlyErrorHeader {
    Write-Host ""
    Write-Host "============================================================" -ForegroundColor Cyan
    Write-Host " Terraform AzureRM Provider - AI Infrastructure Installer" -ForegroundColor Cyan
    Write-Host " Version: $script:InstallerVersion" -ForegroundColor Cyan
    Write-Host "============================================================" -ForegroundColor Cyan
    Write-Host ""
}

# Early validation error display (before modules are loaded)
function Show-EarlyValidationError {
    param(
        [Parameter(Mandatory)]
        [ValidateSet('BootstrapConflict', 'MutuallyExclusive', 'ContributorRequired', 'EmptyLocalPath', 'LocalPathNotFound')]
        [string]$ErrorType,

        [string]$LocalPath
    )

    Show-EarlyErrorHeader

    switch ($ErrorType) {
        'BootstrapConflict' {
            Write-Host " Error:" -ForegroundColor Red -NoNewline
            Write-Host " Cannot use -Branch or -LocalPath with -Bootstrap" -ForegroundColor Cyan
            Write-Host ""
            Write-Host " -Bootstrap always uses the current local branch" -ForegroundColor Cyan
            Write-Host " -Branch and -LocalPath are for updating from user profile" -ForegroundColor Cyan
        }
        'MutuallyExclusive' {
            Write-Host " Error:" -ForegroundColor Red -NoNewline
            Write-Host " Cannot specify both -Branch and -LocalPath" -ForegroundColor Cyan
            Write-Host ""
            Write-Host " Use -Branch to pull AI files from a published GitHub branch" -ForegroundColor Cyan
            Write-Host " Use -LocalPath to copy AI files from a local unpublished directory" -ForegroundColor Cyan
        }
        'ContributorRequired' {
            Write-Host " Error:" -ForegroundColor Red -NoNewline
            Write-Host " -Branch and -LocalPath require -Contributor flag" -ForegroundColor Cyan
            Write-Host ""
            Write-Host " These are contributor features for testing AI file changes:" -ForegroundColor Cyan
            Write-Host "   -Contributor -Branch <name>     Test published branch changes" -ForegroundColor White
            Write-Host "   -Contributor -LocalPath <path>  Test uncommitted local changes" -ForegroundColor White
        }
        'EmptyLocalPath' {
            Write-Host " Error:" -ForegroundColor Red -NoNewline
            Write-Host " -LocalPath parameter cannot be empty" -ForegroundColor Cyan
            Write-Host ""
            Write-Host " Please provide a valid local directory path:" -ForegroundColor Cyan
            Write-Host "   -LocalPath `"C:\path\to\terraform-azurerm-ai-assisted-development`"" -ForegroundColor White
        }
        'LocalPathNotFound' {
            Write-Host " Error:" -ForegroundColor Red -NoNewline
            Write-Host " -LocalPath directory does not exist" -ForegroundColor Cyan
            Write-Host ""
            Write-Host " Specified path: " -ForegroundColor Cyan -NoNewline
            Write-Host "$LocalPath" -ForegroundColor Yellow
            Write-Host ""
            Write-Host " Please verify the directory path exists:" -ForegroundColor Cyan
            Write-Host "   -LocalPath `"C:\path\to\terraform-azurerm-ai-assisted-development`"" -ForegroundColor White
        }
    }

    Write-Host ""
    Write-Host " For more help, run:" -ForegroundColor Cyan
    Write-Host "   .\install-copilot-setup.ps1 -Help" -ForegroundColor White
    Write-Host ""
}

# Function to get parameter suggestion without exiting
function Get-ParameterSuggestion {
    param([string]$param)

    # Handle bare dash edge case (only -- can be detected, - is caught by PowerShell runtime)
    if ($param -eq '--') {
        Write-Host " ERROR: Invalid parameter '$param' (incomplete parameter)" -ForegroundColor Red
        Write-Host ""
        Write-Host " Valid parameters:" -ForegroundColor Cyan
        Write-Host "   -Bootstrap, -Verify, -Clean, -Help, -Dry-Run, -RepoDirectory <path>"
        Write-Host "   -Branch <name>, -Contributor, -LocalPath <path>"
        Write-Host ""
        Write-Host " Examples:" -ForegroundColor Green
        Write-Host "   .\install-copilot-setup.ps1 -Help"
        Write-Host "   .\install-copilot-setup.ps1 -Bootstrap"
        Write-Host ""
        exit 1
    }

    $lowerParam = $param.ToLower()
    $suggestion = $null

    # Remove leading dashes for comparison
    $cleanParam = $lowerParam.TrimStart('-')

    # Prefix matching (higher priority)
    if ($cleanParam -match '^bo') { $suggestion = 'Bootstrap' }
    elseif ($cleanParam -match '^cl') { $suggestion = 'Clean' }
    elseif ($cleanParam -match '^ve') { $suggestion = 'Verify' }
    elseif ($cleanParam -match '^he') { $suggestion = 'Help' }
    elseif ($cleanParam -match '^dr') { $suggestion = 'Dry-Run' }
    elseif ($cleanParam -match '^re') { $suggestion = 'RepoDirectory' }
    elseif ($cleanParam -match '^co') { $suggestion = 'Contributor' }
    elseif ($cleanParam -match '^lo') { $suggestion = 'LocalPath' }
    elseif ($cleanParam -match '^br') { $suggestion = 'Branch' }
    # Fuzzy matching (lower priority)
    elseif ($cleanParam -like '*cle*') { $suggestion = 'Clean' }
    elseif ($cleanParam -like '*boo*') { $suggestion = 'Bootstrap' }
    elseif ($cleanParam -like '*ver*') { $suggestion = 'Verify' }
    elseif ($cleanParam -like '*hel*') { $suggestion = 'Help' }
    elseif ($cleanParam -like '*dry*') { $suggestion = 'Dry-Run' }
    elseif ($cleanParam -like '*repo*') { $suggestion = 'RepoDirectory' }
    elseif ($cleanParam -like '*cont*') { $suggestion = 'Contributor' }
    elseif ($cleanParam -like '*local*') { $suggestion = 'LocalPath' }
    elseif ($cleanParam -like '*source*') { $suggestion = 'LocalPath' }
    elseif ($cleanParam -like '*bra*') { $suggestion = 'Branch' }

    return $suggestion
}

# Function to check for parameter typos and suggest corrections
function Test-ParameterTypo {
    param([string]$param)

    # Handle bare dash edge case (only -- can be detected, - is caught by PowerShell runtime)
    if ($param -eq '--') {
        Write-Host " ERROR: Invalid parameter '$param' (incomplete parameter)" -ForegroundColor Red
        Write-Host ""
        Write-Host " Valid parameters:" -ForegroundColor Cyan
        Write-Host "   -Bootstrap, -Verify, -Clean, -Help, -Dry-Run, -RepoDirectory <path>"
        Write-Host "   -Branch <name>, -Contributor, -LocalPath <path>"
        Write-Host ""
        Write-Host " Examples:" -ForegroundColor Green
        Write-Host "   .\install-copilot-setup.ps1 -Help"
        Write-Host "   .\install-copilot-setup.ps1 -Bootstrap"
        Write-Host ""
        exit 1
    }

    # Use the new Get-ParameterSuggestion function
    $suggestion = Get-ParameterSuggestion $param

    if ($suggestion) {
        Write-Host " Error:" -ForegroundColor Red -NoNewline
        Write-Host " Failed to parse command-line argument:" -ForegroundColor Cyan
        Write-Host " Argument provided but not defined: " -ForegroundColor Cyan -NoNewline
        Write-Host "$param" -ForegroundColor Yellow
        Write-Host " Did you mean: " -ForegroundColor Cyan -NoNewline
        Write-Host "-$suggestion" -ForegroundColor Green -NoNewline
        Write-Host "?" -ForegroundColor Cyan
        Write-Host ""
        Write-Host " For more help on using this command, run:" -ForegroundColor Cyan
        Write-Host "   .\install-copilot-setup.ps1 -Help" -ForegroundColor White
        Write-Host ""
        exit 1
    }
}

#endregion Early Helper Functions

#region Argument Parsing

# Manual argument parsing (like bash version)
$i = 0
while ($i -lt $args.Count) {
    # Early detection of incomplete/bare dash parameters (only -- can be detected, - is caught by PowerShell)
    if ($args[$i] -eq '--') {
        Show-EarlyErrorHeader
        Write-Host " Error:" -ForegroundColor Red -NoNewline
        Write-Host " Invalid parameter '$($args[$i])' (incomplete parameter)" -ForegroundColor Cyan
        Write-Host ""
        Write-Host " Valid parameters:" -ForegroundColor Cyan
        Write-Host "   -Bootstrap, -Verify, -Clean, -Help, -Dry-Run, -RepoDirectory <path>" -ForegroundColor White
        Write-Host "   -Branch <name>, -Contributor, -LocalPath <path>" -ForegroundColor White
        Write-Host ""
        Write-Host " Examples:" -ForegroundColor Green
        Write-Host "   .\install-copilot-setup.ps1 -Help" -ForegroundColor White
        Write-Host "   .\install-copilot-setup.ps1 -Bootstrap" -ForegroundColor White
        Write-Host ""
        exit 1
    }

    switch ($args[$i].ToLower()) {
        '-bootstrap' {
            $Bootstrap = $true
            $i++
        }
        '-repodirectory' {
            if (($i + 1) -ge $args.Count -or $args[$i + 1].StartsWith('-')) {
                Write-Host ""
                Write-Host " ERROR: Option -RepoDirectory requires a directory path" -ForegroundColor Red
                Write-Host ""
                exit 1
            }
            $RepoDirectory = $args[$i + 1]
            $i += 2
        }
        '-branch' {
            if (($i + 1) -ge $args.Count -or $args[$i + 1].StartsWith('-')) {
                Write-Host ""
                Write-Host " ERROR: Option -Branch requires a branch name" -ForegroundColor Red
                Write-Host ""
                exit 1
            }
            $Branch = $args[$i + 1]
            $i += 2
        }
        '-localpath' {
            if (($i + 1) -ge $args.Count -or $args[$i + 1].StartsWith('-')) {
                Write-Host ""
                Write-Host " ERROR: Option -LocalPath requires a directory path" -ForegroundColor Red
                Write-Host ""
                exit 1
            }
            $LocalPath = $args[$i + 1]
            $i += 2
        }
        '-contributor' {
            $Contributor = $true
            $i++
        }
        '-dry-run' {
            $DryRun = $true
            $i++
        }
        '-verify' {
            $Verify = $true
            $i++
        }
        '-clean' {
            $Clean = $true
            $i++
        }
        '-help' {
            $Help = $true
            $i++
        }
        default {
            # Show header for error cases (happens before modules are loaded)
            Show-EarlyErrorHeader

            # Check for typos and if found, show suggestion and exit
            if ($args[$i].StartsWith('-')) {
                $suggestion = Get-ParameterSuggestion $args[$i]
                if ($suggestion) {
                    Write-Host " Error:" -ForegroundColor Red -NoNewline
                    Write-Host " Failed to parse command-line argument:" -ForegroundColor Cyan
                    Write-Host " Argument provided but not defined: " -ForegroundColor Cyan -NoNewline
                    Write-Host "$($args[$i])" -ForegroundColor Yellow
                    Write-Host " Did you mean: " -ForegroundColor Cyan -NoNewline
                    Write-Host "-${suggestion}" -ForegroundColor Green -NoNewline
                    Write-Host "?" -ForegroundColor Cyan
                    Write-Host ""
                    Write-Host " For more help on using this command, run:" -ForegroundColor Cyan
                    Write-Host "   .\install-copilot-setup.ps1 -Help" -ForegroundColor White
                    Write-Host ""
                    exit 1
                }
            }

            Write-Host " Error:" -ForegroundColor Red -NoNewline
            Write-Host " Failed to parse command-line argument:" -ForegroundColor Cyan
            Write-Host " Unknown option: " -ForegroundColor Cyan -NoNewline
            Write-Host "$($args[$i])" -ForegroundColor Yellow
            Write-Host ""
            Write-Host " For more help on using this command, run:" -ForegroundColor Cyan
            Write-Host "   .\install-copilot-setup.ps1 -Help" -ForegroundColor White
            Write-Host ""
            exit 1
        }
    }
}

# POWERSHELL LIMITATION: Handle edge case where PowerShell consumes arguments before our script sees them
# PowerShell treats both '-' and '--' as special parameter markers and removes them from $args
# If $args is empty but no parameters were set, user likely passed:
#   - Nothing (show help - user-friendly default behavior)
#   - A single dash '-' (PowerShell consumed it)
#   - A double dash '--' (PowerShell consumed it)
# In all cases, showing help is the appropriate response
if ($args.Count -eq 0 -and -not ($Bootstrap -or $RepoDirectory -or $Contributor -or $Branch -or $LocalPath -or $DryRun -or $Verify -or $Clean -or $Help)) {
    $Help = $true
}

#endregion Argument Parsing

#region Parameter Validation

# PRIORITY 1: Validate -Bootstrap conflicts first (fail fast on foundational operation)
if ($Bootstrap -and ($Branch -or $LocalPath)) {
    Show-EarlyValidationError -ErrorType 'BootstrapConflict'
    exit 1
}

# PRIORITY 2: Validate mutually exclusive parameters
if ($Branch -and $LocalPath) {
    Show-EarlyValidationError -ErrorType 'MutuallyExclusive'
    exit 1
}

# PRIORITY 3: Validate -Branch and -LocalPath require -Contributor flag
if (($Branch -or $LocalPath) -and -not $Contributor) {
    Show-EarlyValidationError -ErrorType 'ContributorRequired'
    exit 1
}

# PRIORITY 4: Validate -LocalPath is not empty and exists when provided
# Check if parameter was actually passed by looking at the argument list
$localPathArgIndex = -1
for ($idx = 0; $idx -lt $args.Count; $idx++) {
    if ($args[$idx] -eq '-localpath') {
        $localPathArgIndex = $idx
        break
    }
}

if ($localPathArgIndex -ge 0) {
    # -LocalPath was explicitly provided, validate it's not empty
    if ([string]::IsNullOrWhiteSpace($LocalPath)) {
        Show-EarlyValidationError -ErrorType 'EmptyLocalPath'
        exit 1
    }

    # Validate path exists
    if (-not (Test-Path $LocalPath)) {
        Show-EarlyValidationError -ErrorType 'LocalPathNotFound' -LocalPath $LocalPath
        exit 1
    }
}

#endregion Parameter Validation

#endregion Parameter Parsing and Validation

#region Cross-Platform Utilities

function Get-UserHomeDirectory {
    # Cross-platform home directory detection
    if ($IsWindows -or $env:OS -eq "Windows_NT" -or (-not $PSVersionTable.Platform)) {
        # Windows (including PowerShell 5.1 which doesn't have $IsWindows)
        return $env:USERPROFILE
    } else {
        # macOS and Linux
        return $env:HOME
    }
}

#endregion Cross-Platform Utilities

#region Module Loading

function Get-ModulesPath {
    param([string]$ScriptDirectory)

    # Simple logic: modules are always in the same relative location
    $ModulesPath = Join-Path $ScriptDirectory "modules\powershell"

    # If not found, try from workspace root (for direct repo execution)
    if (-not (Test-Path $ModulesPath)) {
        $currentPath = $ScriptDirectory
        while ($currentPath -and $currentPath -ne (Split-Path $currentPath -Parent)) {
            # Look for installer directory marker (AI development repo)
            if (Test-Path (Join-Path $currentPath "installer")) {
                $ModulesPath = Join-Path $currentPath "installer\modules\powershell"
                break
            }
            $currentPath = Split-Path $currentPath -Parent
        }
    }

    return $ModulesPath
}

function Import-RequiredModule {
    param([string]$ModulesPath)

    # Define all required modules in dependency order
    $modules = @(
        "CommonUtilities",
        "ConfigParser",
        "UI",
        "ValidationEngine",
        "FileOperations"
    )

    # Load each module cleanly
    foreach ($module in $modules) {
        $modulePath = Join-Path $ModulesPath "$module.psm1"

        if (-not (Test-Path $modulePath)) {
            throw "Required module '$module' not found at: $modulePath"
        }

        try {
            Remove-Module $module -Force -ErrorAction SilentlyContinue
            Import-Module $modulePath -Force -DisableNameChecking -Global -ErrorAction Stop
        }
        catch {
            throw "Failed to import module '$module': $_"
        }
    }

    # Verify critical functions are available
    $requiredFunctions = @("Get-ManifestConfig", "Get-InstallerConfig", "Write-Header", "Invoke-VerifyWorkspace")
    foreach ($func in $requiredFunctions) {
        if (-not (Get-Command $func -ErrorAction SilentlyContinue)) {
            throw "Required function '$func' not available after module loading"
        }
    }
}

# Get script directory with robust detection
$ScriptDirectory = if ($PSScriptRoot) {
    $PSScriptRoot
} elseif ($MyInvocation.MyCommand.Path) {
    Split-Path $MyInvocation.MyCommand.Path -Parent
} else {
    # Fallback: assume we're in the AIinstaller directory
    Get-Location | ForEach-Object { $_.Path }
}

# Load modules with clear error handling
try {
    $ModulesPath = Get-ModulesPath -ScriptDirectory $ScriptDirectory
    Import-RequiredModule -ModulesPath $ModulesPath
}
catch {
    Write-Host " FATAL ERROR: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host " Cannot continue without required modules." -ForegroundColor Red
    exit 1
}

# Initialize workspace root after module loading
# Note: Using script-scoped globals for workspace state management
$Global:WorkspaceRoot = $null
$Global:ScriptRoot = $null

# Configuration will be loaded on-demand in functions that need it
$Global:ManifestConfig = $null
$Global:InstallerConfig = $null

#endregion Module Loading

#region Workspace Detection

function Get-WorkspaceRoot {
    param([string]$RepoDirectory, [string]$ScriptDirectory)

    # If RepoDirectory is provided, use it (validation happens later)
    if ($RepoDirectory) {
        return $RepoDirectory
    }

    # When running from installer directory, find the repository root
    # Start from script directory and walk up to find installer directory marker
    $currentPath = $ScriptDirectory
    while ($currentPath -and $currentPath -ne (Split-Path $currentPath -Parent)) {
        # Look for installer directory (AI development repo marker)
        if (Test-Path (Join-Path $currentPath "installer")) {
            return $currentPath
        }
        $currentPath = Split-Path $currentPath -Parent
    }

    # Fallback: use current directory
    # This allows fast-fail workspace validation to handle invalid directories
    return Get-Location
}

#endregion Workspace Detection

#region Main Execution

function Main {
    <#
    .SYNOPSIS
    Main entry point for the installer
    #>

     try {
        # Step 1: Initialize workspace and validate it's a proper terraform-provider-azurerm repo
        $Global:WorkspaceRoot = Get-WorkspaceRoot -RepoDirectory $RepoDirectory -ScriptDirectory $ScriptDirectory
        $Global:ScriptRoot = $ScriptDirectory

        # Step 2: Early workspace validation before doing anything else
        $workspaceValidation = Test-WorkspaceValid -WorkspacePath $Global:WorkspaceRoot

        # Step 3: Determine effective branch for manifest config
        # -Bootstrap always uses current branch, otherwise use -Branch parameter or default to "main"
        $effectiveBranch = "main"  # Default fallback

        if ($Bootstrap) {
            # Bootstrap mode: Always use current git branch (required)
            try {
                $detectedBranch = git branch --show-current 2>$null
                if ($detectedBranch -and $detectedBranch.Trim() -ne "") {
                    $effectiveBranch = $detectedBranch.Trim()
                }
                else {
                    throw "Could not detect current git branch"
                }
            }
            catch {
                Show-BootstrapGitError -WorkspaceRoot $Global:WorkspaceRoot
                exit 1
            }
        }
        elseif ($Branch) {
            # User provided -Branch parameter (contributor mode)
            $effectiveBranch = $Branch
        }
        # else: use default "main"        # Step 4: Initialize global configuration
        if ($workspaceValidation.Valid) {
            # Manifest is always in the same directory as the script
            # - When running from source repo: repo/installer/file-manifest.config
            # - When running after bootstrap: ~/.terraform-azurerm-ai-installer/file-manifest.config
            $manifestPath = Join-Path $ScriptDirectory "file-manifest.config"

            try {
                $Global:ManifestConfig = Get-ManifestConfig -ManifestPath $manifestPath -Branch $effectiveBranch
            }
            catch {
                Show-ValidationError -ErrorType 'BranchValidation' -Branch $effectiveBranch
                exit 1
            }

            $Global:InstallerConfig = Get-InstallerConfig -WorkspaceRoot $Global:WorkspaceRoot -ManifestConfig $Global:ManifestConfig -Branch $Global:ManifestConfig.Branch
        } else {
            # Invalid workspace - provide minimal configuration for UI display
            $Global:InstallerConfig = @{ Version = $script:InstallerVersion }
            $Global:ManifestConfig = @{}
        }

        # Step 5: Get branch information for UI display and safety checks
        try {
            $currentBranch = git branch --show-current 2>$null
            if (-not $currentBranch -or $currentBranch.Trim() -eq "") {
                $currentBranch = "Unknown"
            }
        }
        catch {
            $currentBranch = "Unknown"
        }

        # Step 4: Get branch information for UI display and safety checks
        if ($RepoDirectory) {
            # Get current branch of the target repository (only if workspace exists)
            $originalLocation = Get-Location
            $currentBranch = "Unknown"
            try {
                if (Test-Path $Global:WorkspaceRoot) {
                    Set-Location $Global:WorkspaceRoot
                    $currentBranch = git branch --show-current 2>$null
                    if (-not $currentBranch -or $currentBranch.Trim() -eq "") {
                        $currentBranch = "Unknown"
                    }
                }
            }
            catch {
                $currentBranch = "Unknown"
            }
            finally {
                if (Test-Path $originalLocation) {
                    Set-Location $originalLocation
                }
            }
        } else {
            # Not using -RepoDirectory, get branch info from current location
            try {
                $currentBranch = git branch --show-current 2>$null
                if (-not $currentBranch -or $currentBranch.Trim() -eq "") {
                    $currentBranch = "Unknown"
                }
            }
            catch {
                $currentBranch = "Unknown"
            }
        }

        # Check if current branch is a source branch (main, master)
        # Source branches are protected from AI infrastructure installation for safety
        $sourceBranches = @("main", "master")
        $isSourceRepo = ($currentBranch -in $sourceBranches)
        $branchType = if ($isSourceRepo) { "source" } else {
            if ($currentBranch -eq "Unknown") { "Unknown" } else { "feature" }
        }

        # CONSISTENT PATTERN: Every operation gets the same header and branch detection
        Write-Header -Title "Terraform AzureRM Provider - AI Infrastructure Installer" -Version $Global:InstallerConfig.Version
        Show-BranchDetection -BranchName $currentBranch -BranchType $branchType

        # SAFETY CHECK 1 - Block operations targeting AI dev repo when using -RepoDirectory (except Verify, Help, Bootstrap)
        if ($RepoDirectory -and -not ($Verify -or $Help -or $Bootstrap)) {
            # Quick check: Is target directory the AI dev repo?
            $repoCheck = Test-IsAzureRMProviderRepo -Path $Global:WorkspaceRoot -RequireProviderRepo
            if (-not $repoCheck.Valid -and $repoCheck.IsAIDevRepo) {
                Show-AIDevRepoViolation -WorkspaceRoot $Global:WorkspaceRoot
                exit 1
            }
        }

        # SAFETY CHECK 2 - Block operations on source branch when using -RepoDirectory (except Verify, Help, Bootstrap)
        if ($RepoDirectory) {
            if ($currentBranch -in $sourceBranches -and -not ($Verify -or $Help -or $Bootstrap)) {
                Show-SafetyViolation -BranchName $currentBranch -Operation "Install" -FromUserProfile
                exit 1
            }
        }

        # SAFETY CHECK 3 - Block -Contributor mode when running from source repo on main branch
        if ($Contributor -and $isSourceRepo -and -not $RepoDirectory) {
            Show-ContributorModeViolation -BranchName $currentBranch
            exit 1
        }

        # Detect if we're running from user profile directory (needed for all help contexts)
        $currentDir = Get-Location
        $userProfileInstallerDir = Join-Path (Get-UserHomeDirectory) ".terraform-azurerm-ai-installer"
        $isFromUserProfile = $currentDir.Path -eq $userProfileInstallerDir -or [bool]$RepoDirectory

        # Detect what command was attempted (for better error messages)
        $attemptedCommand = ""
        if ($Bootstrap) { $attemptedCommand = "-Bootstrap" }
        elseif ($Verify) { $attemptedCommand = "-Verify" }
        elseif ($Clean) { $attemptedCommand = "-Clean" }
        elseif ($Help) { $attemptedCommand = "-Help" }
        elseif ($DryRun) { $attemptedCommand = "-Dry-Run" }
        elseif ($LocalPath) { $attemptedCommand = "-LocalPath `"$LocalPath`"" }
        elseif ($Branch) { $attemptedCommand = "-Branch `"$Branch`"" }
        elseif ($RepoDirectory -and -not ($Help -or $Verify -or $Bootstrap -or $Clean)) {
            $attemptedCommand = "-RepoDirectory `"$RepoDirectory`""
        }

        # Simple parameter handling
        if ($Help) {
            Show-Help -BranchType $branchType -WorkspaceValid $workspaceValidation.Valid -WorkspaceIssue $workspaceValidation.Reason -FromUserProfile $isFromUserProfile -AttemptedCommand $attemptedCommand
            return
        }

        # For all other operations, workspace must be valid
        if (-not $workspaceValidation.Valid) {
            Show-WorkspaceValidationError -Reason $workspaceValidation.Reason -FromUserProfile:$isFromUserProfile

            # Show help menu for guidance
            Show-Help -BranchType $branchType -WorkspaceValid $false -WorkspaceIssue $workspaceValidation.Reason -FromUserProfile $isFromUserProfile -AttemptedCommand $attemptedCommand
            exit 1
        }

        if ($Verify) {
            Invoke-VerifyWorkspace -BranchType $branchType | Out-Null
            return
        }

        if ($Bootstrap) {
            $result = Invoke-Bootstrap -CurrentBranch $currentBranch -BranchType $branchType
            if ($result.Success) {
                exit 0
            } else {
                exit 1
            }
        }

        if ($Clean) {
            $cleanResult = Invoke-CleanWorkspace -DryRun $DryRun -WorkspaceRoot $Global:WorkspaceRoot -CurrentBranch $currentBranch -BranchType $branchType -FromUserProfile:([bool]$RepoDirectory)

            # Return clean result without automatic verification
            # The clean operation provides its own success/failure messaging
            if ($cleanResult.Success) {
                exit 0
            } else {
                exit 1
            }
        }

        # Installation path (when -RepoDirectory is provided and not other specific operations)
        if ($RepoDirectory -and -not ($Help -or $Verify -or $Bootstrap -or $Clean)) {
            # Proceed with installation - require that target is a Terraform provider repo
            Invoke-InstallInfrastructure -DryRun $DryRun -WorkspaceRoot $Global:WorkspaceRoot -ManifestConfig $Global:ManifestConfig -TargetBranch $currentBranch -RequireProviderRepo $true -SourceBranch $Branch -LocalSourcePath $LocalPath | Out-Null
            return
        }

        # Default: show source branch help only (no welcome message for help display)
        Show-SourceBranchHelp
        return
    }
    catch {
        Write-Host ""
        Write-Host " ERROR: $($_.Exception.Message)" -ForegroundColor Red
        Write-Host ""
        exit 1
    }
}

#endregion Main Execution

# Execute main function
Main
