# UI Module for Terraform AzureRM Provider AI Setup
# STREAMLINED VERSION - Contains only functions actually used by main script and dependencies

# Note: CommonUtilities module is imported globally by the main script

# UI Module - User Interface and Display Functions
# STREAMLINED VERSION - Contains only functions actually used by main script and dependencies

#region Module Configuration

# Default version - should be overridden by caller
$script:DefaultVersion = "1.0.0"

#endregion Module Configuration

#region Helper Functions

function Write-Separator {
    <#
    .SYNOPSIS
    Display a separator line with consistent formatting

    .DESCRIPTION
    Displays a colored separator line for visual separation in UI output.
    Matches the bash script's print_separator() function behavior.

    .PARAMETER Length
    The length of the separator line. Defaults to 60 characters.

    .PARAMETER Color
    The color of the separator line. Defaults to Cyan.

    .PARAMETER Character
    The character to use for the separator. Defaults to "=".
    #>
    param(
        [int]$Length = 60,
        [string]$Color = "Cyan",
        [string]$Character = "="
    )

    Write-Host $($Character * $Length) -ForegroundColor $Color
}

function Write-Header {
    <#
    .SYNOPSIS
    Display the main application header
    #>
    param(
        [string]$Title = "Terraform AzureRM Provider - AI Infrastructure Installer",
        [string]$Version = $script:DefaultVersion
    )

    Write-Host ""
    Write-Separator
    Write-Host " $Title" -ForegroundColor Cyan
    Write-Host " Version: $Version" -ForegroundColor Cyan
    Write-Separator
    Write-Host ""
}

function Show-ValidationError {
    <#
    .SYNOPSIS
    Display validation errors with consistent formatting using error type switch
    #>
    param(
        [Parameter(Mandatory)]
        [ValidateSet('BranchValidation', 'EmptyLocalPath', 'LocalPathNotFound', 'WorkspaceValidation')]
        [string]$ErrorType,

        [string]$Branch,
        [string]$LocalPath,
        [string]$Reason
    )

    Write-Host ""
    Write-Separator
    Write-Host " Terraform AzureRM Provider - AI Infrastructure Installer" -ForegroundColor Cyan
    Write-Host " Version: $script:DefaultVersion" -ForegroundColor Cyan
    Write-Separator
    Write-Host ""

    switch ($ErrorType) {
        'BranchValidation' {
            Write-Host " Error:" -ForegroundColor Red -NoNewline
            Write-Host " Branch validation failed" -ForegroundColor Cyan
            Write-Host ""
            Write-Host " Branch: " -ForegroundColor Cyan -NoNewline
            Write-Host "$Branch" -ForegroundColor Yellow
            Write-Host ""
            Write-Host " The specified branch does not exist in the AI development repository." -ForegroundColor Cyan
            Write-Host ""
            Write-Host " Please verify the branch name and try again:" -ForegroundColor Cyan
            Write-Host "   -Contributor -Branch `"valid-branch-name`"" -ForegroundColor White
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
        'WorkspaceValidation' {
            Write-Host " Error:" -ForegroundColor Red -NoNewline
            Write-Host " Workspace validation failed" -ForegroundColor Cyan
            Write-Host ""
            Write-Host " Reason: " -ForegroundColor Cyan -NoNewline
            Write-Host "$Reason" -ForegroundColor Yellow
            Write-Host ""
            Write-Host " Please ensure you're running in a valid terraform-provider-azurerm repository:" -ForegroundColor Cyan
            Write-Host "   -RepoDirectory `"C:\path\to\terraform-provider-azurerm`"" -ForegroundColor White
        }
    }

    Write-Host ""
    Write-Host " For more help, run:" -ForegroundColor Cyan
    Write-Host "   .\install-copilot-setup.ps1 -Help" -ForegroundColor White
    Write-Host ""
}

function Format-AlignedLabel {
    <#
    .SYNOPSIS
    Format a label with dynamic spacing to align with other labels
    .DESCRIPTION
    Returns a formatted string with appropriate spacing to align labels in a list.
    Calculates the required padding based on the longest label provided to ensure
    consistent vertical alignment when displaying multiple label-value pairs.

    .PARAMETER Label
    The label text to format (without decorative characters like colons)

    .PARAMETER LongestLabel
    The longest label in the set (without decorative characters like colons or separators)
    Used as the baseline for calculating alignment spacing
    #>
    param(
        [Parameter(Mandatory)]
        [string]$Label,

        [Parameter(Mandatory)]
        [string]$LongestLabel
    )

    # Calculate required spacing for alignment - preserve leading/trailing spaces
    $requiredWidth = $LongestLabel.Length - $Label.Length
    if ($requiredWidth -lt 0) { $requiredWidth = 0 }

    return "$Label$(' ' * $requiredWidth)"
}

function Show-BranchDetection {
    <#
    .SYNOPSIS
    Display current branch detection with type-based formatting
    #>
    param(
        [string]$BranchName = "Unknown",

        [ValidateSet("source", "feature", "Unknown")]
        [string]$BranchType = "Unknown"
    )

    # Determine the branch label and longest label for proper alignment
    $branchLabel = switch ($BranchType) {
        "source"  { "SOURCE BRANCH DETECTED" }
        "feature" { "FEATURE BRANCH DETECTED" }
        default   { "BRANCH DETECTED" }
    }

    # Use the longest possible label for alignment
    $longestLabel = "FEATURE BRANCH DETECTED"  # This is the longest possible branch label

    # Display branch information with consistent alignment
    $formattedBranchLabel = Format-AlignedLabel -Label $branchLabel -LongestLabel $longestLabel
    Write-Host " ${formattedBranchLabel}: " -NoNewline -ForegroundColor Cyan
    Write-Host "$BranchName" -ForegroundColor Yellow

    # Dynamic workspace label with proper alignment and colors
    if ($Global:WorkspaceRoot) {
        $formattedWorkspaceLabel = Format-AlignedLabel -Label "WORKSPACE" -LongestLabel $longestLabel
        Write-Host " ${formattedWorkspaceLabel}: " -NoNewline -ForegroundColor Cyan
        Write-Host "$Global:WorkspaceRoot" -ForegroundColor Green
    }

    Write-Host ""
    Write-Separator
}

function Show-Help {
    <#
    .SYNOPSIS
    Display contextual help information based on branch type
    #>
    param(
        [string]$BranchType = "Unknown",
        [bool]$WorkspaceValid = $true,
        [string]$WorkspaceIssue = "",
        [bool]$FromUserProfile = $false,
        [string]$AttemptedCommand = ""
    )

    Write-Host ""
    Write-Host "DESCRIPTION:" -ForegroundColor Cyan
    Write-Host "  Interactive installer for AI-assisted development infrastructure that enhances"
    Write-Host "  GitHub Copilot with Terraform-specific knowledge, patterns, and best practices."
    Write-Host ""

    # Dynamic options and examples based on branch type
    switch ($BranchType) {
        "source" {
            Show-SourceBranchHelp
        }
        "feature" {
            Show-FeatureBranchHelp
        }
        default {
            Show-UnknownBranchHelp -WorkspaceValid $WorkspaceValid -WorkspaceIssue $WorkspaceIssue -FromUserProfile $FromUserProfile -AttemptedCommand $AttemptedCommand
        }
    }

    Write-Host "For more information, visit: https://github.com/WodansSon/terraform-azurerm-ai-assisted-development" -ForegroundColor Cyan
    Write-Host ""
}

function Show-SourceBranchHelp {
    <#
    .SYNOPSIS
    Display help specific to source branch operations
    #>

    Write-Host "USAGE:" -ForegroundColor Cyan
    Write-Host "  .\install-copilot-setup.ps1 [OPTIONS]"
    Write-Host ""
    Write-Host "AVAILABLE OPTIONS:" -ForegroundColor Cyan
    Write-Host "  -Bootstrap        Copy installer to user profile (~\.terraform-azurerm-ai-installer\)"
    Write-Host "                    Run this from the source branch to set up for feature branch use"
    Write-Host "  -Verify           Check current workspace status and validate setup"
    Write-Host "  -Help             Show this help information"
    Write-Host ""
    Write-Host "EXAMPLES:" -ForegroundColor Cyan
    Write-Host "  Bootstrap installer (run from source branch):"
    Write-Host "    .\install-copilot-setup.ps1 -Bootstrap"
    Write-Host ""
    Write-Host "  Verify setup:"
    Write-Host "    .\install-copilot-setup.ps1 -Verify"
    Write-Host ""
    Write-Host "BOOTSTRAP WORKFLOW:" -ForegroundColor Cyan
    Write-Host "  1. Run -Bootstrap from source branch (main) to copy installer to user profile"
    Write-Host "  2. Switch to your feature branch: git checkout feature/your-branch-name"
    Write-Host "  3. Navigate to user profile: cd $(Get-CrossPlatformInstallerPath)"
    Write-Host "  4. Run installer: .\install-copilot-setup.ps1 -RepoDirectory `"/path/to/your/feature/branch`""
    Write-Host ""
}

function Show-FeatureBranchHelp {
    <#
    .SYNOPSIS
    Display help specific to feature branch operations
    #>

    Write-Host "USAGE:" -ForegroundColor Cyan
    Write-Host "  .\install-copilot-setup.ps1 [OPTIONS]"
    Write-Host ""

    Write-Host "AVAILABLE OPTIONS:" -ForegroundColor Cyan
    Write-Host "  -RepoDirectory    Repository path (path to your feature branch directory)"
    Write-Host "  -Branch           GitHub branch to pull AI files from (requires -Contributor, default: main)"
    Write-Host "  -LocalPath        Local directory to copy AI files from (requires -Contributor)"
    Write-Host "  -Contributor      Enable contributor mode for testing AI file changes"
    Write-Host "  -Dry-Run          Show what would be done without making changes"
    Write-Host "  -Verify           Check current workspace status and validate setup"
    Write-Host "  -Clean            Remove AI infrastructure from workspace"
    Write-Host "  -Help             Show this help information"
    Write-Host ""

    Write-Host "EXAMPLES:" -ForegroundColor Cyan
    Write-Host "  Install AI infrastructure (default - from main branch):"
    Write-Host "    cd $(Get-CrossPlatformInstallerPath)"
    Write-Host "    .\install-copilot-setup.ps1 -RepoDirectory `"/path/to/your/feature/branch`""
    Write-Host ""
    Write-Host "  Install from specific GitHub branch (contributor testing):"
    Write-Host "    .\install-copilot-setup.ps1 -Contributor -Branch feature/new-ai-files -RepoDirectory `"/path/to/repo`""
    Write-Host ""
    Write-Host "  Install from local uncommitted changes (contributor testing):"
    Write-Host "    .\install-copilot-setup.ps1 -Contributor -LocalPath `"/path/to/ai-installer-repo`" -RepoDirectory `"/path/to/repo`""
    Write-Host ""
    Write-Host "  Dry-Run (preview changes):"
    Write-Host "    cd $(Get-CrossPlatformInstallerPath)"
    Write-Host "    .\install-copilot-setup.ps1 -RepoDirectory `"/path/to/your/feature/branch`" -Dry-Run"
    Write-Host ""
    Write-Host "  Clean removal:"
    Write-Host "    cd $(Get-CrossPlatformInstallerPath)"
    Write-Host "    .\install-copilot-setup.ps1 -RepoDirectory `"/path/to/your/feature/branch`" -Clean"
    Write-Host ""

    Write-Host "WORKFLOW:" -ForegroundColor Cyan
    Write-Host "  1. Navigate to user profile installer directory: cd $(Get-CrossPlatformInstallerPath)"
    Write-Host "  2. Run installer with path to your feature branch"
    Write-Host "  3. Start developing with enhanced GitHub Copilot AI features"
    Write-Host "  4. Use -Clean to remove AI infrastructure when done"
    Write-Host ""
    Write-Host "CONTRIBUTOR WORKFLOW (Testing AI File Changes):" -ForegroundColor Cyan
    Write-Host "  Test uncommitted changes: Use -LocalPath to copy from your local AI repo"
    Write-Host "  Test published branch:    Use -Branch to pull from GitHub branch"
    Write-Host "  Test main branch:         Omit both flags to use default (main)"
    Write-Host ""
}

function Show-UnknownBranchHelp {
    <#
    .SYNOPSIS
    Display generic help when branch type cannot be determined
    #>
    param(
        [bool]$WorkspaceValid = $true,
        [string]$WorkspaceIssue = "",
        [bool]$FromUserProfile = $false,
        [string]$AttemptedCommand = ""
    )

    # Show workspace issue if detected
    if (-not $WorkspaceValid -and $WorkspaceIssue) {
        Write-Host "WORKSPACE ISSUE DETECTED:" -ForegroundColor Cyan
        Write-Host "  $WorkspaceIssue" -ForegroundColor Yellow
        Write-Host ""
        Write-Host "SOLUTION:" -ForegroundColor Cyan

        if ($FromUserProfile) {
            # User is running from ~/.terraform-azurerm-ai-installer, they need -RepoDirectory
            Write-Host "  Use the -RepoDirectory parameter to specify your repository path:"
            $commandExample = if ($AttemptedCommand) { $AttemptedCommand } else { "-Help" }
            Write-Host "  .\install-copilot-setup.ps1 -RepoDirectory `"C:\path\to\terraform-provider-azurerm`" $commandExample"
        } else {
            # User is running from somewhere else, they need to navigate to a repo or use -RepoDirectory
            Write-Host "  Navigate to a terraform-provider-azurerm repository, or use the -RepoDirectory parameter:"
            $commandExample = if ($AttemptedCommand) { $AttemptedCommand } else { "-Help" }
            Write-Host "  .\install-copilot-setup.ps1 -RepoDirectory `"C:\path\to\terraform-provider-azurerm`" $commandExample"
        }

        Write-Host ""
        Write-Separator
        Write-Host ""
    }

    Write-Host "USAGE:" -ForegroundColor Cyan
    Write-Host "  .\install-copilot-setup.ps1 [OPTIONS]"
    Write-Host ""

    Write-Host "ALL OPTIONS:" -ForegroundColor Cyan
    Write-Host "  -Bootstrap        Copy installer to user profile (~\.terraform-azurerm-ai-installer\)"
    Write-Host "  -RepoDirectory    Repository path for git operations (when running from user profile)"
    Write-Host "  -Branch           GitHub branch to pull AI files from (requires -Contributor, default: main)"
    Write-Host "  -LocalPath        Local directory to copy AI files from (requires -Contributor)"
    Write-Host "  -Contributor      Enable contributor mode for testing AI file changes"
    Write-Host "  -Dry-Run          Show what would be done without making changes"
    Write-Host "  -Verify           Check current workspace status and validate setup"
    Write-Host "  -Clean            Remove AI infrastructure from workspace"
    Write-Host "  -Help             Show this help information"
    Write-Host ""

    Write-Host "EXAMPLES:" -ForegroundColor Cyan
    Write-Host "  Source Branch Operations:" -ForegroundColor DarkCyan
    Write-Host "    .\install-copilot-setup.ps1 -Bootstrap"
    Write-Host "    .\install-copilot-setup.ps1 -Verify"
    Write-Host ""
    Write-Host "  Feature Branch Operations:" -ForegroundColor DarkCyan
    Write-Host "    cd $(Get-CrossPlatformInstallerPath)"
    Write-Host "    .\install-copilot-setup.ps1 -RepoDirectory `"/path/to/your/feature/branch`""
    Write-Host "    .\install-copilot-setup.ps1 -RepoDirectory `"/path/to/your/feature/branch`" -Clean"
    Write-Host ""
    Write-Host "  Contributor Operations (Testing AI Changes):" -ForegroundColor DarkCyan
    Write-Host "    .\install-copilot-setup.ps1 -RepoDirectory `"/path/to/repo`" -Contributor -Branch feature/ai-updates"
    Write-Host "    .\install-copilot-setup.ps1 -RepoDirectory `"/path/to/repo`" -Contributor -LocalPath `"/path/to/ai-repo`""
    Write-Host ""

    Write-Host "BRANCH DETECTION:" -ForegroundColor Cyan
    Write-Host "  The installer automatically detects your branch type and shows appropriate options."
    Write-Host ""
}

function Show-InstallationResult {
    <#
    .SYNOPSIS
    Display installation results summary
    #>
    param(
        [Parameter(Mandatory)]
        [hashtable]$Results
    )

    if ($Results.OverallSuccess) {
        Write-Host "[SUCCESS] Successfully installed $($Results.Successful) files" -ForegroundColor Green
        if ($Results.Skipped -gt 0) {
            Write-Host "[INFO] Skipped $($Results.Skipped) files (already up-to-date)" -ForegroundColor Cyan
        }
    } else {
        Write-Host "[WARNING] Installation completed with some failures:" -ForegroundColor Yellow
        Write-Host "  Successful: $($Results.Successful)" -ForegroundColor Green
        Write-Host "  Failed    : $($Results.Failed)" -ForegroundColor Red
        Write-Host "  Skipped   : $($Results.Skipped)" -ForegroundColor Yellow
    }
}

function Show-CleanupReminder {
    <#
    .SYNOPSIS
    Display reminder to clean up AI infrastructure before committing
    #>
    param(
        [Parameter(Mandatory)]
        [string]$WorkspacePath
    )

    Write-Separator -Length 60
    Write-Host " IMPORTANT: Remember to clean up before committing!" -ForegroundColor Yellow
    Write-Separator -Length 60
    Write-Host ""
    Write-Host "The AI infrastructure files are for LOCAL development only." -ForegroundColor Cyan
    Write-Host "They should NOT be committed to the terraform-provider-azurerm repository." -ForegroundColor Cyan
    Write-Host ""
    Write-Host "Before committing your code changes, run:" -ForegroundColor White
    Write-Host ""
    Write-Host "  .\install-copilot-setup.ps1 -RepoDirectory `"$WorkspacePath`" -Clean" -ForegroundColor Green
    Write-Host ""
    Write-Host "This will remove all AI infrastructure files from your working directory." -ForegroundColor Cyan
    Write-Host ""
}

function Show-SourceBranchWelcome {
    <#
    .SYNOPSIS
    Display streamlined welcome message for source branch users
    #>
    param(
        [Parameter(Mandatory)]
        [string]$BranchName
    )

    Write-Host " WELCOME TO AI-ASSISTED TERRAFORM AZURERM DEVELOPMENT" -ForegroundColor Green
    Write-Host ""
}

function Show-BootstrapNextStep {
    <#
    .SYNOPSIS
    Display next steps after successful bootstrap operation

    .DESCRIPTION
    Shows the user what to do next after the installer files have been
    successfully copied to their user profile.
    #>
    param(
        [string]$TargetDirectory = (Join-Path (Get-UserHomeDirectory) ".terraform-azurerm-ai-installer")
    )

    Write-Host "NEXT STEPS:" -ForegroundColor "Cyan"
    Write-Host ""
    Write-Host "  1. Switch to your feature branch:" -ForegroundColor "Cyan"
    Write-Host "     git checkout feature/your-branch-name" -ForegroundColor "White"
    Write-Host ""
    Write-Host "  2. Run the installer from your user profile:" -ForegroundColor "Cyan"
    Write-Host "     cd $(Get-CrossPlatformInstallerPath)" -ForegroundColor "White"
    Write-Host "     .\install-copilot-setup.ps1 -RepoDirectory `"<path-to-your-terraform-provider-azurerm>`"" -ForegroundColor "White"
    Write-Host ""
}

function Show-AIInstallerNotFoundError {
    <#
    .SYNOPSIS
    Display error message when AIinstaller directory is not found

    .DESCRIPTION
    Shows a helpful error message when bootstrap fails because the AIinstaller
    directory is not found in the current repository. Provides clear steps
    for resolution. Uses standardized UI formatting.
    #>

    # Use standardized operation summary with failure details
    $details = @(
        "Issue: installer directory not found in current repository",
        "Requirement: Bootstrap must be run from source branch (main)",
        "Resolution: Switch to source branch and run bootstrap again"
    )

    Show-OperationSummary -OperationName "Bootstrap" -Success $false -DryRun $false `
        -ItemsProcessed 0 -ItemsSuccessful 0 -ItemsFailed 1 `
        -Details $details

    Write-Host ""
    Write-Host "RESOLUTION STEPS:" -ForegroundColor Cyan
    Write-Host "  1. Switch to the source branch: " -ForegroundColor Cyan -NoNewline
    Write-Host "git checkout main" -ForegroundColor White
    Write-Host "  2. Ensure you're in the correct repository: " -ForegroundColor Cyan -NoNewline
    Write-Host "terraform-azurerm-ai-assisted-development" -ForegroundColor White
    Write-Host "  3. Run bootstrap again from the source branch" -ForegroundColor Cyan
    Write-Host ""
}

function Show-BootstrapViolation {
    <#
    .SYNOPSIS
    Display error message when bootstrap is attempted from user profile

    .DESCRIPTION
    Shows a helpful error message when bootstrap is attempted from the user profile
    directory instead of the source repository. Provides clear steps for resolution.
    #>
    param(
        [Parameter(Mandatory)]
        [string]$ScriptDirectory
    )

    Write-Host ""
    Write-Host " BOOTSTRAP VIOLATION: Cannot run bootstrap from user profile directory" -ForegroundColor Red
    Write-Host ""
    Write-Host " Bootstrap must be run from the source AI development repository." -ForegroundColor Yellow
    Write-Host " You are currently running from: '$ScriptDirectory'" -ForegroundColor Yellow
    Write-Host ""
    Write-Separator
    Write-Host ""
    Write-Host "SOLUTION:" -ForegroundColor Cyan
    Write-Host "  1. Navigate to the main branch:" -ForegroundColor Cyan
    Write-Host "    cd `"<path-to-your-terraform-azurerm-ai-assisted-development>`"" -ForegroundColor White
    Write-Host "    git checkout main" -ForegroundColor White
    Write-Host ""
    Write-Host "  2. Then run bootstrap from there:" -ForegroundColor Cyan
    Write-Host "    .\installer\install-copilot-setup.ps1 -Bootstrap" -ForegroundColor White
    Write-Host ""
}

function Show-SafetyViolation {
    <#
    .SYNOPSIS
    Display safety violation message for source branch operations

    .DESCRIPTION
    Shows a standardized safety violation message when operations are attempted
    on the source branch that should only be performed on feature branches.
    #>
    param(
        [string]$BranchName = "main",
        [string]$Operation = "operation",
        [switch]$FromUserProfile
    )

    Write-Host " SAFETY VIOLATION: Cannot perform operations on source branch" -ForegroundColor Red
    Write-Separator
    Write-Host ""

    if ($FromUserProfile) {
        Write-Host " The -RepoDirectory points to the source branch '$BranchName'." -ForegroundColor Yellow
    } else {
        Write-Host " You are currently in the source branch '$BranchName'." -ForegroundColor Yellow
    }

    Write-Host " Operations other than -Verify, -Help, and -Bootstrap are not allowed on the source branch." -ForegroundColor Yellow
    Write-Host ""
    Write-Host "SOLUTION:" -ForegroundColor Cyan
    Write-Host "  Switch to a feature branch in your target repository:" -ForegroundColor DarkCyan

    if ($FromUserProfile) {
        Write-Host "    cd `"<path-to-your-terraform-provider-azurerm>`"" -ForegroundColor Gray
    } else {
        Write-Host "    cd `"$Global:WorkspaceRoot`"" -ForegroundColor Gray
    }

    Write-Host "    git checkout -b feature/your-branch-name" -ForegroundColor Gray
    Write-Host ""

    if ($FromUserProfile) {
        Write-Host "  Then run the installer from your user profile:" -ForegroundColor DarkCyan
        Write-Host "    cd $(Get-CrossPlatformInstallerPath)" -ForegroundColor Gray
        Write-Host "    .\install-copilot-setup.ps1 -RepoDirectory `"<path-to-your-terraform-provider-azurerm>`"" -ForegroundColor Gray
        Write-Host ""
    }
}

function Show-AIDevRepoViolation {
    <#
    .SYNOPSIS
    Display safety violation when attempting to install into AI development repository

    .DESCRIPTION
    Shows error message when -RepoDirectory points to the AI development repository
    instead of the terraform-provider-azurerm repository.
    #>
    param(
        [string]$WorkspaceRoot
    )

    Write-Host ""
    Write-Host "============================================================" -ForegroundColor Red
    Write-Host " SAFETY VIOLATION: Cannot install into AI Development Repository" -ForegroundColor Red
    Write-Host "============================================================" -ForegroundColor Red
    Write-Host ""
    Write-Host " The -RepoDirectory points to the AI development repository:" -ForegroundColor Yellow
    Write-Host " $WorkspaceRoot" -ForegroundColor Cyan
    Write-Host ""
    Write-Host " This repository contains the source files. Use -RepoDirectory to point" -ForegroundColor Yellow
    Write-Host " to your terraform-provider-azurerm working copy instead." -ForegroundColor Yellow
    Write-Host ""
    Write-Host "SOLUTION:" -ForegroundColor Green
    Write-Host "  Clone or navigate to your terraform-provider-azurerm repository:" -ForegroundColor White
    Write-Host "    cd `"<path-to-your-terraform-provider-azurerm>`"" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  Then run the installer from your user profile:" -ForegroundColor White
    Write-Host "    cd `"$(Join-Path (Get-UserHomeDirectory) '.terraform-azurerm-ai-installer')`"" -ForegroundColor Cyan
    Write-Host "    .\install-copilot-setup.ps1 -RepoDirectory `"<path-to-your-terraform-provider-azurerm>`"" -ForegroundColor Cyan
    Write-Host ""
}

function Show-ContributorModeViolation {
    <#
    .SYNOPSIS
    Display safety violation for Contributor mode on source branch

    .DESCRIPTION
    Shows a standardized error message when -Contributor mode is used
    on the source branch (main/master) of the AI development repository.
    #>
    param(
        [string]$BranchName = "main"
    )

    Write-Host ""
    Write-Host "============================================================" -ForegroundColor Red
    Write-Host " SAFETY VIOLATION: Cannot use -Contributor mode on source branch" -ForegroundColor Red
    Write-Host "============================================================" -ForegroundColor Red
    Write-Host ""
    Write-Host " You are on the '$BranchName' branch of the AI development repository." -ForegroundColor Yellow
    Write-Host " -Contributor mode is for testing changes on feature branches only." -ForegroundColor Yellow
    Write-Host ""
    Write-Host "SOLUTION:" -ForegroundColor Green
    Write-Host "  1. Create a feature branch for your changes:" -ForegroundColor White
    Write-Host "     git checkout -b feature/your-feature-name" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  2. Make your changes to the AI infrastructure files" -ForegroundColor White
    Write-Host ""
    Write-Host "  3. Test with -Contributor -LocalPath:" -ForegroundColor White
    Write-Host "     .\install-copilot-setup.ps1 -Contributor -LocalPath `".`" -RepoDirectory `"<path-to-your-terraform-provider-azurerm>`"" -ForegroundColor Cyan
    Write-Host ""
}

function Show-BootstrapGitError {
    <#
    .SYNOPSIS
    Display error when Bootstrap cannot detect git branch

    .DESCRIPTION
    Shows a standardized error message when -Bootstrap fails to detect
    the current git branch, which is required for copying installer files.
    #>
    param(
        [string]$WorkspaceRoot
    )

    Write-Host ""
    Write-Host " ERROR: Bootstrap requires a valid git repository with a current branch" -ForegroundColor Red
    Write-Host " Could not detect current git branch in: $WorkspaceRoot" -ForegroundColor Red
    Write-Host ""
    Write-Host " Bootstrap copies the current branch's installer files to your user profile." -ForegroundColor Cyan
    Write-Host " Ensure you are in a valid git repository with a checked-out branch." -ForegroundColor Cyan
    Write-Host ""
}

function Show-WorkspaceValidationError {
    <#
    .SYNOPSIS
    Display workspace validation error message

    .DESCRIPTION
    Shows a standardized workspace validation error message when the workspace
    is not a valid terraform-provider-azurerm repository.
    #>
    param(
        [string]$Reason = "Unknown validation error",
        [switch]$FromUserProfile
    )

    Write-Host ""
    Write-Host " WORKSPACE VALIDATION FAILED: $Reason" -ForegroundColor Red
    Write-Host ""
    # Context-aware error message based on how the script was invoked
    if ($FromUserProfile) {
        Write-Host " Running from user profile directory ($(Get-CrossPlatformInstallerPath))" -ForegroundColor Yellow
        Write-Host " Please use -RepoDirectory to point to a valid terraform-provider-azurerm repository:" -ForegroundColor Yellow
        Write-Host "   .\install-copilot-setup.ps1 -RepoDirectory `"<path-to-terraform-provider-azurerm>`"" -ForegroundColor Gray
    } else {
        Write-Host " This script must be run from the terraform-azurerm-ai-assisted-development repository." -ForegroundColor Yellow
        Write-Host " After bootstrap, run from user profile ($(Get-CrossPlatformInstallerPath)) with -RepoDirectory." -ForegroundColor Yellow
    }
    Write-Host ""
    Write-Separator
}

function Show-OperationSummary {
    <#
    .SYNOPSIS
    Centralized operation summary display for consistent success/failure reporting

    .DESCRIPTION
    Provides a standardized way to report operation outcomes across all installer functions.
    This ensures consistent formatting and messaging for long-term maintenance.

    .PARAMETER OperationName
    The name of the operation being summarized (e.g., "Installation", "Cleanup", "Bootstrap")

    .PARAMETER Success
    Whether the operation was successful

    .PARAMETER ItemsProcessed
    Total number of items processed

    .PARAMETER ItemsSuccessful
    Number of items processed successfully

    .PARAMETER ItemsFailed
    Number of items that failed processing

    .PARAMETER DryRun
    Whether this was a dry run operation
    #>
    param(
        [Parameter(Mandatory)]
        [string]$OperationName,

        [Parameter(Mandatory)]
        [bool]$Success,

        [int]$ItemsProcessed = 0,
        [int]$ItemsSuccessful = 0,
        [int]$ItemsFailed = 0,

        [bool]$DryRun = $false,

        [string[]]$Details = @(),

        [string[]]$NextSteps = @()
    )

    Write-Host ""

    # Show operation completion with consistent formatting for all operations
    $statusText = if ($Success) { "completed successfully" } else { "failed" }
    $completionMessage = if ($DryRun) {
        " $($OperationName) $statusText (dry run)"
    } else {
        " $($OperationName) $statusText"
    }
    Write-Host $completionMessage -ForegroundColor $(if ($Success) { "Green" } else { "Red" })
    Write-Host ""

    # Initialize details hashtable with ordered preservation
    $detailsHash = [ordered]@{}
    $detailsOrder = @()

    # First, process the passed Details array to preserve their order
    foreach ($detail in $Details) {
        if ($detail -match '^([^:]+):\s*(.+)$') {
            $key = $matches[1].Trim()
            $value = $matches[2].Trim()
            $detailsHash[$key] = $value
            $detailsOrder += $key
        }
    }

    # Add standard metrics only if they're not already in the details
    if ($ItemsSuccessful -gt 0 -and -not $detailsHash.Contains("Items Successful")) {
        $detailsHash["Items Successful"] = $ItemsSuccessful
        $detailsOrder += "Items Successful"
    }
    if ($ItemsFailed -gt 0 -and -not $detailsHash.Contains("Items Failed")) {
        $detailsHash["Items Failed"] = $ItemsFailed
        $detailsOrder += "Items Failed"
    }
    if ($ItemsProcessed -gt 0 -and $ItemsProcessed -ne $ItemsSuccessful -and -not $detailsHash.Contains("Items Processed")) {
        $detailsHash["Items Processed"] = $ItemsProcessed
        $detailsOrder += "Items Processed"
    }

    # Display details using consistent UI formatting
    if ($detailsHash.Count -gt 0) {
        Write-Separator -Color Cyan
        Write-Host " $($OperationName.ToUpper()) SUMMARY:" -ForegroundColor Cyan
        Write-Separator -Color Cyan
        Write-Host ""
        Write-Host "DETAILS:" -ForegroundColor Cyan

        # Find the longest key for proper alignment (following UI standards)
        $longestKey = ($detailsHash.Keys | Sort-Object Length -Descending | Select-Object -First 1)

        # Display each detail with consistent alignment using Format-AlignedLabel
        # Use the preserved order from detailsOrder to maintain the original sequence
        foreach ($key in $detailsOrder) {
            $value = $detailsHash[$key]
            $formattedLabel = Format-AlignedLabel -Label $key -LongestLabel $longestKey

            # Write key with consistent formatting
            Write-Host "  ${formattedLabel}: " -ForegroundColor Cyan -NoNewline

            # Determine value color based on content
            if ($value -match '^\d+$' -or $value -match '^\d+(\.\d+)?\s*(KB|MB|GB|TB|B)$') {
                # Numbers and file sizes in green
                Write-Host $value -ForegroundColor Green
            } else {
                # Text values in yellow
                Write-Host $value -ForegroundColor Yellow
            }
        }
    }

    # Display next steps if provided
    if ($NextSteps.Count -gt 0) {
        Write-Host ""
        Write-Host "NEXT STEPS:" -ForegroundColor Cyan
        Write-Host ""
        foreach ($step in $NextSteps) {
            Write-Host $step -ForegroundColor Gray
        }
        Write-Host ""
    }

    # End with blank line (following output paradigm)
    Write-Host ""
}

#endregion

# Export only the functions actually used by the main script
Export-ModuleMember -Function @(
    'Write-Separator',
    'Write-Header',
    'Format-AlignedLabel',
    'Show-BranchDetection',
    'Show-Help',
    'Show-SourceBranchHelp',
    'Show-SourceBranchWelcome',
    'Show-SafetyViolation',
    'Show-AIDevRepoViolation',
    'Show-ContributorModeViolation',
    'Show-WorkspaceValidationError',
    'Show-BootstrapNextStep',
    'Show-AIInstallerNotFoundError',
    'Show-ValidationError',
    'Show-BootstrapViolation',
    'Show-BootstrapGitError',
    'Show-OperationSummary',
    'Show-InstallationResult',
    'Show-CleanupReminder'
)
