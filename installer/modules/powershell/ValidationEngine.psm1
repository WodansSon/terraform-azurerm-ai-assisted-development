# ValidationEngine Module for Terraform AzureRM Provider AI Setup
# Handles comprehensive validation, dependency checking, and system requirements
# STREAMLINED VERSION - Contains only functions actually used by main script and dependencies

#region Private Functions

function Find-WorkspaceRoot {
    <#
    .SYNOPSIS
    Find the workspace root by looking for installer directory in current or parent directories
    #>
    param(
        [Parameter(Mandatory)]
        [string]$StartPath
    )

    $currentPath = $StartPath
    $maxDepth = 10  # Prevent infinite loops
    $depth = 0

    while ($depth -lt $maxDepth -and $currentPath) {
        # Look for installer directory (AI development repo marker)
        $installerPath = Join-Path $currentPath "installer"
        if (Test-Path $installerPath) {
            return $currentPath
        }

        # Move to parent directory
        $parentPath = Split-Path $currentPath -Parent
        if ($parentPath -eq $currentPath) {
            # Reached root directory
            break
        }
        $currentPath = $parentPath
        $depth++
    }

    return $null
}

function Test-PowerShellVersion {
    <#
    .SYNOPSIS
    Test if PowerShell version meets requirements
    #>

    $minimumVersion = [Version]"5.1"
    $currentVersion = $PSVersionTable.PSVersion

    return @{
        Valid = $currentVersion -ge $minimumVersion
        CurrentVersion = $currentVersion.ToString()
        MinimumVersion = $minimumVersion.ToString()
        Reason = if ($currentVersion -ge $minimumVersion) {
            "PowerShell version is supported"
        } else {
            "PowerShell $minimumVersion or later is required"
        }
    }
}

function Test-ExecutionPolicy {
    <#
    .SYNOPSIS
    Test if execution policy allows script execution
    #>

    # Check effective execution policy (not just CurrentUser scope)
    $effectivePolicy = Get-ExecutionPolicy
    $currentUserPolicy = Get-ExecutionPolicy -Scope CurrentUser
    $allowedPolicies = @("RemoteSigned", "Unrestricted", "Bypass", "Undefined")

    # Valid if either the effective policy is good, or CurrentUser is Undefined (inherits from higher scope)
    $isValid = ($effectivePolicy -in @("RemoteSigned", "Unrestricted", "Bypass")) -or
               ($currentUserPolicy -eq "Undefined" -and $effectivePolicy -in @("RemoteSigned", "Unrestricted", "Bypass"))

    return @{
        Valid = $isValid
        CurrentPolicy = $effectivePolicy.ToString()
        AllowedPolicies = $allowedPolicies
        Reason = if ($isValid) {
            "Execution policy allows script execution"
        } else {
            "Execution policy '$effectivePolicy' prevents script execution. Use: Set-ExecutionPolicy RemoteSigned -Scope CurrentUser"
        }
    }
}

function Test-RequiredCommand {
    <#
    .SYNOPSIS
    Test if required external commands are available
    #>

    $requiredCommands = @("git")
    $results = @{}
    $allValid = $true

    foreach ($command in $requiredCommands) {
        try {
            $commandInfo = Get-Command $command -ErrorAction Stop
            $results[$command] = @{
                Available = $true
                Version = ""
                Path = $commandInfo.Source
                Reason = "Command is available"
            }

            # Try to get version for git
            if ($command -eq "git") {
                try {
                    $version = git --version 2>$null
                    if ($version -match "git version (.+)") {
                        $results[$command].Version = $matches[1]
                    }
                }
                catch {
                    # Version detection failed, but command exists
                }
            }
        }
        catch {
            $results[$command] = @{
                Available = $false
                Version = ""
                Path = ""
                Reason = "Command not found in PATH"
            }
            $allValid = $false
        }
    }

    return @{
        Valid = $allValid
        Commands = $results
        Reason = if ($allValid) { "All required commands are available" } else { "Some required commands are missing" }
    }
}

function Test-InternetConnectivity {
    <#
    .SYNOPSIS
    Test internet connectivity to required endpoints
    #>

    $testUrls = @(
        "https://api.github.com",
        "https://raw.githubusercontent.com"
    )

    $results = @{
        Connected = $false
        TestedEndpoints = @{}
        Reason = ""
    }

    $successCount = 0

    foreach ($url in $testUrls) {
        try {
            # Disable progress bar to prevent console flashing
            $ProgressPreference = 'SilentlyContinue'
            $response = Invoke-WebRequest -Uri $url -Method Head -TimeoutSec 10 -UseBasicParsing
            $results.TestedEndpoints[$url] = @{
                Success = $true
                StatusCode = $response.StatusCode
                ResponseTime = 0
            }
            $successCount++
        }
        catch {
            $results.TestedEndpoints[$url] = @{
                Success = $false
                StatusCode = 0
                Error = $_.Exception.Message
            }
        }
        finally {
            # Restore progress preference
            $ProgressPreference = 'Continue'
        }
    }

    $results.Connected = $successCount -gt 0
    $results.Reason = if ($results.Connected) {
        "Internet connectivity verified ($successCount/$($testUrls.Count) endpoints reachable)"
    } else {
        "No internet connectivity detected. Check network connection and firewall settings."
    }

    return $results
}

function Test-GitRepository {
    <#
    .SYNOPSIS
    Test if current directory is a valid git repository with branch safety checks
    #>
    param(
        [bool]$AllowBootstrapOnSource = $false,
        [string]$WorkspacePath = ""
    )

    $results = @{
        Valid = $false
        IsGitRepo = $false
        HasRemote = $false
        CurrentBranch = ""
        RemoteUrl = ""
        Reason = ""
    }

    try {
        # Save current location and switch to workspace if provided
        $originalLocation = Get-Location

        if ($WorkspacePath -and (Test-Path $WorkspacePath)) {
            Set-Location $WorkspacePath
        }

        try {
            # Test if we're in a git repository
            $null = git status --porcelain 2>$null
            $results.IsGitRepo = $LASTEXITCODE -eq 0

            if ($results.IsGitRepo) {
                # Get current branch
                try {
                    $results.CurrentBranch = git branch --show-current 2>$null
                    if (-not $results.CurrentBranch -or $results.CurrentBranch.Trim() -eq "") {
                        $results.CurrentBranch = "Unknown"
                    }
                }
                catch {
                    $results.CurrentBranch = "Unknown"
                }

                # Get remote URL
                try {
                    $results.RemoteUrl = git remote get-url origin 2>$null
                    $results.HasRemote = $LASTEXITCODE -eq 0 -and $results.RemoteUrl
                }
                catch {
                    $results.HasRemote = $false
                }

                # CRITICAL SAFETY CHECK: Prevent running on source branch (unless bootstrap)
                $sourceBranches = @("main", "master")
                $isSourceBranch = $results.CurrentBranch -in $sourceBranches

                $results.Valid = $results.IsGitRepo -and $results.HasRemote -and (-not $isSourceBranch -or $AllowBootstrapOnSource)

                if ($isSourceBranch -and -not $AllowBootstrapOnSource) {
                    $results.Reason = "SAFETY VIOLATION: Cannot run installer on source branch '$($results.CurrentBranch)'. Switch to a different branch to install AI infrastructure."
                }
                elseif ($results.Valid) {
                    if ($isSourceBranch -and $AllowBootstrapOnSource) {
                        $results.Reason = "Source branch - bootstrap operations allowed"
                    } else {
                        $results.Reason = "Valid git repository with remote origin"
                    }
                }
                elseif (-not $results.HasRemote) {
                    $results.Reason = "Git repository has no remote origin configured"
                }
            }
            else {
                $results.Reason = "Not a git repository"
            }
        }
        finally {
            # Always restore original location
            if ($originalLocation) {
                Set-Location $originalLocation
            }
        }
    }
    catch {
        $results.Reason = "Error checking git repository: $($_.Exception.Message)"
    }

    return $results
}

function Get-RelativePath {
    <#
    .SYNOPSIS
    Get relative path from workspace root, handling both existing and non-existing paths
    #>
    param(
        [string]$Path,
        [string]$WorkspaceRoot = (Get-Location).Path
    )

    try {
        # For existing paths, use Resolve-Path
        if (Test-Path $Path) {
            $relativePath = Resolve-Path $Path -Relative
            # Normalize to forward slashes for consistent cross-platform display
            return $relativePath -replace '\\', '/'
        }

        # For non-existing paths, manually construct relative path
        $absolutePath = if ([System.IO.Path]::IsPathRooted($Path)) { $Path } else { Join-Path $WorkspaceRoot $Path }
        $relativePath = [System.IO.Path]::GetRelativePath($WorkspaceRoot, $absolutePath)

        # Normalize to forward slashes for consistent cross-platform display
        return $relativePath -replace '\\', '/'
    }
    catch {
        # Fallback: just return the filename or last part of the path
        return Split-Path $Path -Leaf
    }
}

function Test-IsAzureRMProviderRepo {
    <#
    .SYNOPSIS
    Validate that the target directory is the AI development repository or Terraform AzureRM provider repository

    .PARAMETER Path
    Path to validate

    .PARAMETER RequireProviderRepo
    If true, only accept actual Terraform provider repositories (reject AI dev repo).
    Used when installing to a target repository via -RepoDirectory.
    #>
    param(
        [Parameter(Mandatory)]
        [string]$Path,

        [Parameter(Mandatory=$false)]
        [switch]$RequireProviderRepo
    )

    $markers = @{
        Installer = Join-Path $Path "installer"
        Instructions = Join-Path $Path ".github/instructions"
        GoMod = Join-Path $Path "go.mod"
        InternalServices = Join-Path $Path "internal/services"
        ProviderFile = Join-Path $Path "internal/provider/provider.go"
    }

    $results = @{
        Valid = $false
        IsAIDevRepo = $false
        IsAzureRMProvider = $false
        Markers = @{}
        Reason = ""
    }

    # Check if this is the AI development repository
    if ((Test-Path $markers.Installer) -and (Test-Path $markers.Instructions)) {
        $results.Markers.Installer = $true
        $results.Markers.Instructions = $true
        $results.IsAIDevRepo = $true

        # If we require a provider repo, reject AI dev repo
        if ($RequireProviderRepo) {
            $results.Valid = $false
            $results.Reason = "Target directory is the AI development repository, not a Terraform provider repository. Use -RepoDirectory to point to your terraform-provider-azurerm working copy."
            return $results
        }

        $results.Valid = $true
        return $results
    }

    # Check if this is the Terraform AzureRM provider repository
    # Check if go.mod exists
    if (-not (Test-Path $markers.GoMod)) {
        $results.Reason = "Not a valid repository - missing installer/ and .github/instructions/ directories, or go.mod file"
        return $results
    }

    # Read go.mod and check for azurerm provider module
    try {
        $goModContent = Get-Content $markers.GoMod -Raw
        if ($goModContent -match "module github\.com/hashicorp/terraform-provider-azurerm") {
            $results.Markers.GoMod = $true
            $results.IsAzureRMProvider = $true
        } else {
            $results.Markers.GoMod = $false
            $results.Reason = "go.mod exists but does not declare terraform-provider-azurerm module"
            return $results
        }
    }
    catch {
        $results.Reason = "Could not read go.mod file"
        return $results
    }

    # Check for internal/services directory (unique to provider structure)
    if (Test-Path $markers.InternalServices) {
        $results.Markers.InternalServices = $true
    } else {
        $results.Markers.InternalServices = $false
        $results.Reason = "Missing internal/services directory structure"
        return $results
    }

    # Check for provider file
    if (Test-Path $markers.ProviderFile) {
        $results.Markers.ProviderFile = $true
    } else {
        $results.Markers.ProviderFile = $false
        $results.Reason = "Missing internal/provider/provider.go file"
        return $results
    }

    # All checks passed
    $results.Valid = $true
    $results.Reason = "Validated as Terraform AzureRM provider repository"
    return $results
}

function Test-UncommittedChange {
    <#
    .SYNOPSIS
    Check if the target repository has uncommitted changes that could be overwritten
    #>
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    $results = @{
        HasUncommittedChanges = $false
        ChangedFiles = @()
        UntrackedFiles = @()
        IsGitRepo = $false
        Reason = ""
    }

    # Check if it's a git repository
    $gitDir = Join-Path $Path ".git"
    if (-not (Test-Path $gitDir)) {
        $results.Reason = "Not a git repository"
        return $results
    }

    $results.IsGitRepo = $true

    try {
        # Get git status
        $status = git -C $Path status --porcelain 2>$null

        if ($LASTEXITCODE -ne 0) {
            $results.Reason = "Could not get git status"
            return $results
        }

        if ([string]::IsNullOrWhiteSpace($status)) {
            $results.Reason = "No uncommitted changes"
            return $results
        }

        # Parse status output
        $statusLines = $status -split "`n" | Where-Object { $_ -match '\S' }

        foreach ($line in $statusLines) {
            $statusCode = $line.Substring(0, 2)
            $filePath = $line.Substring(3).Trim()

            # Check if file is in .github/ directory (AI infrastructure)
            $isAIInfra = $filePath -match '^\.github/(instructions|prompts|copilot-instructions\.md)'

            if ($statusCode -match '^\?\?') {
                # Untracked file
                $results.UntrackedFiles += @{
                    Path = $filePath
                    IsAIInfrastructure = $isAIInfra
                }
            } else {
                # Modified/Staged file
                $results.ChangedFiles += @{
                    Path = $filePath
                    Status = $statusCode.Trim()
                    IsAIInfrastructure = $isAIInfra
                }
            }
        }

        # Check if ANY AI infrastructure files have uncommitted changes
        $aiInfraChanges = ($results.ChangedFiles | Where-Object { $_.IsAIInfrastructure }).Count

        if ($aiInfraChanges -gt 0 -or $results.ChangedFiles.Count -gt 0) {
            $results.HasUncommittedChanges = $true
            $results.Reason = "Found $($results.ChangedFiles.Count) modified files, $aiInfraChanges affecting AI infrastructure"
        } else {
            $results.Reason = "Only untracked files found (no modified files)"
        }

    }
    catch {
        $results.Reason = "Error checking git status: $($_.Exception.Message)"
    }

    return $results
}

#endregion

#region Public Functions

function Test-WorkspaceValid {
    <#
    .SYNOPSIS
    Test if current directory is a valid Terraform AzureRM workspace
    #>
    param(
        [string]$WorkspacePath = ""
    )

    # Smart workspace detection - use provided path or find from current location
    if ($WorkspacePath) {
        # Check if the provided workspace path exists
        if (-not (Test-Path $WorkspacePath)) {
            $results = @{
                Valid = $false
                Path = $null
                CurrentPath = $WorkspacePath
                IsAzureRMProvider = $false
                IsAIDevRepo = $false
                Reason = "Could not locate workspace root (no installer directory or go.mod found in current path or parent directories)"
            }
            return $results
        }

        # When WorkspacePath is provided, check if it's already the workspace root
        $installerInProvidedPath = Join-Path $WorkspacePath "installer"
        $goModInProvidedPath = Join-Path $WorkspacePath "go.mod"
        if ((Test-Path $installerInProvidedPath) -or (Test-Path $goModInProvidedPath)) {
            $workspaceRoot = $WorkspacePath
        } else {
            # If not, search from the provided path
            $workspaceRoot = Find-WorkspaceRoot -StartPath $WorkspacePath
        }
        # Use FullName property for DirectoryInfo objects from Get-Item
        $itemResult = Get-Item $WorkspacePath
        $currentPath = @{ Path = $itemResult.FullName }
    } else {
        $currentPath = Get-Location
        $workspaceRoot = Find-WorkspaceRoot -StartPath $currentPath.Path
    }

    $results = @{
        Valid = $false
        Path = $workspaceRoot
        CurrentPath = $currentPath.Path
        IsAzureRMProvider = $false
        IsAIDevRepo = $false
        HasGoMod = $false
        HasMainGo = $false
        Reason = ""
    }

    if (-not $workspaceRoot) {
        $results.Reason = "Could not locate workspace root (no installer directory or go.mod found in current path or parent directories)"
        return $results
    }

    # Check for installer directory (AI development repo)
    $installerPath = Join-Path $workspaceRoot "installer"
    $instructionsPath = Join-Path $workspaceRoot ".github/instructions"
    $hasInstaller = Test-Path $installerPath
    $hasInstructions = Test-Path $instructionsPath

    # Check for go.mod file in workspace root (Terraform provider repo)
    $goModPath = Join-Path $workspaceRoot "go.mod"
    $results.HasGoMod = Test-Path $goModPath

    # Check for main.go file in workspace root
    $mainGoPath = Join-Path $workspaceRoot "main.go"
    $results.HasMainGo = Test-Path $mainGoPath

    # Determine repo type
    if ($hasInstaller -and $hasInstructions) {
        $results.IsAIDevRepo = $true
        $results.Valid = $true
        $results.Reason = "Valid AI development repository workspace"
        return $results
    }

    # Check if this is the terraform-provider-azurerm repository
    if ($results.HasGoMod) {
        try {
            $goModContent = Get-Content $goModPath -Raw
            $results.IsAzureRMProvider = $goModContent -match "terraform-provider-azurerm"
        }
        catch {
            $results.IsAzureRMProvider = $false
        }
    }

    # Determine validity for provider repo
    $results.Valid = $results.HasGoMod -and $results.HasMainGo -and $results.IsAzureRMProvider

    if ($results.Valid) {
        $results.Reason = "Valid Terraform AzureRM provider workspace"
    }
    elseif (-not $results.HasGoMod) {
        $results.Reason = "Not a valid repository (missing installer/ and .github/instructions/ directories, or go.mod file)"
    }
    elseif (-not $results.HasMainGo) {
        $results.Reason = "Not a Go application (missing main.go file)"
    }
    elseif (-not $results.IsAzureRMProvider) {
        $results.Reason = "Not the Terraform AzureRM provider repository"
    }
    else {
        $results.Reason = "Workspace validation failed"
    }

    return $results
}

function Test-SystemRequirement {
    <#
    .SYNOPSIS
    Test all system requirements for the AI installer
    #>

    $results = @{
        OverallValid = $true
        PowerShell = Test-PowerShellVersion
        ExecutionPolicy = Test-ExecutionPolicy
        Commands = Test-RequiredCommand
        Internet = Test-InternetConnectivity
    }

    # Check if any requirement failed
    $results.OverallValid = $results.PowerShell.Valid -and
                           $results.ExecutionPolicy.Valid -and
                           $results.Commands.Valid -and
                           $results.Internet.Connected

    return $results
}

function Test-PreInstallation {
    <#
    .SYNOPSIS
    Run comprehensive pre-installation validation

    .PARAMETER AllowBootstrapOnSource
    Allow bootstrap operations on source branch

    .PARAMETER RequireProviderRepo
    Require that the workspace is a Terraform provider repository (not AI dev repo).
    Used when installing via -RepoDirectory to a target repository.
    #>
    param(
        [bool]$AllowBootstrapOnSource = $false,
        [bool]$RequireProviderRepo = $false
    )

    $results = @{
        OverallValid = $true
        Git = $null
        Workspace = $null
        SystemRequirements = $null
        Timestamp = Get-Date
    }

    # CRITICAL: Check Git first for branch safety
    # Use the workspace root for git operations if available
    $gitPath = if ($Global:WorkspaceRoot) { $Global:WorkspaceRoot } else { (Get-Location).Path }
    $results.Git = Test-GitRepository -AllowBootstrapOnSource $AllowBootstrapOnSource -WorkspacePath $gitPath

    # If Git validation fails due to branch safety, short-circuit other validations
    # This prevents running unnecessary tests when we know we can't proceed
    if (-not $results.Git.Valid -and $results.Git.Reason -like "*SAFETY VIOLATION*") {
        $results.OverallValid = $false

        # Still run system requirements (these are always safe to check)
        $results.SystemRequirements = Test-SystemRequirement

        # Skip workspace and detailed checks due to safety violation
        $results.Workspace = @{
            Valid = $false
            Reason = "Skipped due to Git branch safety violation"
            Skipped = $true
        }

        return $results
    }

    # Continue with full validation if Git is safe
    $results.Workspace = Test-WorkspaceValid -WorkspacePath $Global:WorkspaceRoot
    $results.SystemRequirements = Test-SystemRequirement

    # CRITICAL SAFETY CHECKS: Verify target repository and uncommitted changes
    # If RequireProviderRepo is true, reject AI dev repo (used when installing via -RepoDirectory)
    if ($RequireProviderRepo) {
        $results.RepositoryValidation = Test-IsAzureRMProviderRepo -Path $Global:WorkspaceRoot -RequireProviderRepo
    } else {
        $results.RepositoryValidation = Test-IsAzureRMProviderRepo -Path $Global:WorkspaceRoot
    }
    $results.UncommittedChanges = Test-UncommittedChange -Path $Global:WorkspaceRoot    # Check overall validity - Git validation (including branch safety) is critical
    $results.OverallValid = $results.Git.Valid -and
                           $results.Workspace.Valid -and
                           $results.SystemRequirements.OverallValid -and
                           $results.RepositoryValidation.Valid

    # If there are uncommitted changes, warn but don't fail validation
    # The main script should handle this and prompt the user
    if ($results.UncommittedChanges.HasUncommittedChanges) {
        Write-Warning "Target repository has uncommitted changes that may be overwritten"
    }

    return $results
}

function Test-SourceRepository {
    <#
    .SYNOPSIS
    Determines if we're running on the source repository vs a target repository

    .DESCRIPTION
    Checks various indicators to determine if this is the source repository where
    AI infrastructure files are maintained vs a target repository where they
    would be installed.

    .OUTPUTS
    Boolean - True if this is the source repository, False if target

    .NOTES
    CRITICAL FUNCTION: This provides essential source repository protection.
    The logic here determines whether files should be copied locally or downloaded
    remotely, preventing accidental overwriting of source files.
    #>

    # Check if we're on a source branch (main, master)
    try {
        Push-Location $Global:WorkspaceRoot
        $currentBranch = git rev-parse --abbrev-ref HEAD 2>$null
        $sourceBranches = @("main", "master")
        if ($currentBranch -in $sourceBranches) {
            return $true
        }
    } catch {
        # Git not available or not in a git repo
    } finally {
        Pop-Location
    }

    # Since toolkit is now separate, source detection is only branch-based
    # The presence of .github directories in target repo doesn't mean it's source
    return $false
}

function Invoke-VerifyWorkspace {
    <#
    .SYNOPSIS
    Verifies the presence of AI infrastructure files in the workspace

    .DESCRIPTION
    Checks for all required AI infrastructure files including:
    - Main copilot instructions
    - Detailed instruction files
    - Prompts directory
    - VS Code settings

    .PARAMETER BranchType
    The type of branch (source, feature, Unknown) for dynamic spacing calculation

    .PARAMETER AfterClean
    Indicates if verification is running after a -Clean operation
    When true, missing files are considered SUCCESS (proper cleanup)

    .OUTPUTS
    Returns verification results and displays status to console

    .NOTES
    This function maintains source repository awareness and provides different
    behavior for source vs target repositories.
    #>
    param(
        [ValidateSet("source", "feature", "Unknown")]
        [string]$BranchType = "feature",

        [switch]$AfterClean
    )

    # Use the dynamically determined workspace root
    $workspaceRoot = $Global:WorkspaceRoot

    if (-not $workspaceRoot) {
        Write-Error "Workspace root is not initialized. Ensure -RepoDirectory is specified or script is run from a valid workspace."
        return @{
            Success = $false
            Files = @()
            Issues = @("Workspace root not initialized")
        }
    }

    Push-Location $workspaceRoot

    try {
        # CRITICAL: Use centralized validation (replaces Test-SourceRepository)
        $validation = Test-PreInstallation -AllowBootstrapOnSource:$true  # Allow verification on source

        $results = @{
            Success = $validation.OverallValid
            Files = @()
            Issues = @()
            IsSourceRepo = ($validation.Git.CurrentBranch -in @("main", "master"))
            ValidationResults = $validation
        }

        # If basic validation failed, show that first
        if (-not $validation.OverallValid) {
            Write-Host " Workspace validation failed!" -ForegroundColor Red
            Write-Host ""
            if (-not $validation.Git.Valid) {
                $results.Issues += "Git validation failed: $($validation.Git.Reason)"
                Write-Host "   Git Issue: $($validation.Git.Reason)" -ForegroundColor Red
            }
            if (-not $validation.Workspace.Valid -and -not $validation.Workspace.Skipped) {
                $results.Issues += "Workspace validation failed: $($validation.Workspace.Reason)"
                Write-Host "   Workspace Issue: $($validation.Workspace.Reason)" -ForegroundColor Red
            }
            if (-not $validation.SystemRequirements.OverallValid) {
                $results.Issues += "System requirements not met"
                Write-Host "   System Issue: Missing requirements" -ForegroundColor Red
            }
            Write-Host ""
            return $results
        }

        Write-Host " Workspace Verification" -ForegroundColor Cyan
        Write-Separator
        Write-Host ""

        # Fail fast if the local installer manifest does not match the remote manifest.
        # This prevents misleading verification results when a stale user-profile installer is present.
        try {
            $localManifestPath = Join-Path $Global:ScriptRoot "file-manifest.config"
            $remoteManifestUrl = "$($Global:ManifestConfig.BaseUrl)/installer/file-manifest.config"

            if (Test-Path $localManifestPath -and $remoteManifestUrl) {
                $localManifest = (Get-Content -Path $localManifestPath -Raw) -replace "`r`n", "`n" -replace "`r", "`n"
                $remoteManifest = (Invoke-WebRequest -Uri $remoteManifestUrl -UseBasicParsing -ErrorAction Stop).Content
                $remoteManifest = $remoteManifest -replace "`r`n", "`n" -replace "`r", "`n"

                if ($localManifest -ne $remoteManifest) {
                    Write-Host " Manifest file mismatch" -ForegroundColor Red
                    Write-Host ""
                    Write-Host " Local manifest: $(Get-RelativePath $localManifestPath)" -ForegroundColor Cyan
                    Write-Host " Remote manifest: $remoteManifestUrl" -ForegroundColor Cyan
                    Write-Host ""
                    Write-Host " The local installer manifest does not match the remote manifest." -ForegroundColor Cyan
                    Write-Host " This usually means your installer is out of date." -ForegroundColor Cyan
                    Write-Host ""
                    Write-Host " FIX: Refresh the installer/manifest (re-run Bootstrap or re-extract the latest release bundle), then run -Verify again." -ForegroundColor Yellow
                    Write-Host ""

                    $results.Success = $false
                    $results.Issues += "file-manifest.config mismatch"
                    return $results
                }
            }
        }
        catch {
            # If remote manifest cannot be fetched (offline/firewall), do not block verification.
            Write-Host " NOTE: Could not validate remote manifest; continuing verification" -ForegroundColor Yellow
        }

        # Check main instructions file
        $instructionsFile = $Global:InstallerConfig.Files.Instructions.Target
        if (Test-Path $instructionsFile) {
            $results.Files += @{
                Path = $instructionsFile
                Status = "Present"
                Description = "Main Copilot instructions"
            }
            Write-Host "  [FOUND  ] $(Get-RelativePath $instructionsFile)" -ForegroundColor Green
        } else {
            $results.Files += @{
                Path = $instructionsFile
                Status = "Missing"
                Description = "Main Copilot instructions"
            }
            $results.Issues += ".github/copilot-instructions.md"
            Write-Host "  [MISSING] $(Get-RelativePath $instructionsFile)" -ForegroundColor Red
        }

        # Check instructions directory
        $instructionsDir = $Global:InstallerConfig.Files.InstructionFiles.Target
        if (Test-Path $instructionsDir -PathType Container) {
            $results.Files += @{
                Path = $instructionsDir
                Status = "Present"
                Description = "Instructions directory"
            }
            Write-Host "  [FOUND  ] $(Get-RelativePath $instructionsDir)/" -ForegroundColor Green

            # Check specific instruction files
            $requiredFiles = $Global:InstallerConfig.Files.InstructionFiles.Files

            foreach ($file in $requiredFiles) {
                # Handle full repository paths vs relative paths
                if ($file.StartsWith('.github/')) {
                    # This is a full repository path - use it directly from workspace root
                    $filePath = Join-Path $Global:WorkspaceRoot $file
                } else {
                    # This is a relative path - join with target directory
                    $filePath = Join-Path $instructionsDir $file
                }

                if (Test-Path $filePath) {
                    $results.Files += @{
                        Path = $file
                        Status = "Present"
                        Description = "Instruction file"
                    }
                    Write-Host "    [FOUND  ] $file" -ForegroundColor Green
                } else {
                    $results.Files += @{
                        Path = $file
                        Status = "Missing"
                        Description = "Instruction file"
                    }
                    Write-Host "    [MISSING] $file" -ForegroundColor Red
                    $results.Issues += $file
                }
            }
        } else {
            $results.Files += @{
                Path = $instructionsDir
                Status = "Missing"
                Description = "Instructions directory"
            }
            $results.Issues += ".github/instructions"
            Write-Host "  [MISSING] $(Get-RelativePath $instructionsDir)/" -ForegroundColor Red
        }

        # Check prompts directory
        $promptsDir = $Global:InstallerConfig.Files.PromptFiles.Target
        if (Test-Path $promptsDir -PathType Container) {
            $results.Files += @{
                Path = $promptsDir
                Status = "Present"
                Description = "Prompts directory"
            }
            Write-Host "  [FOUND  ] $(Get-RelativePath $promptsDir)/" -ForegroundColor Green

            # Check specific prompt files
            $requiredPrompts = $Global:InstallerConfig.Files.PromptFiles.Files

            foreach ($file in $requiredPrompts) {
                # Handle full repository paths vs relative paths
                if ($file.StartsWith('.github/')) {
                    # This is a full repository path - use it directly from workspace root
                    $filePath = Join-Path $Global:WorkspaceRoot $file
                } else {
                    # This is a relative path - join with target directory
                    $filePath = Join-Path $promptsDir $file
                }

                if (Test-Path $filePath) {
                    $results.Files += @{
                        Path = $file
                        Status = "Present"
                        Description = "Prompt file"
                    }
                    Write-Host "    [FOUND  ] $file" -ForegroundColor Green
                } else {
                    $results.Files += @{
                        Path = $file
                        Status = "Missing"
                        Description = "Prompt file"
                    }
                    Write-Host "    [MISSING] $file" -ForegroundColor Red
                    $results.Issues += $file
                }
            }
        } else {
            $results.Files += @{
                Path = $promptsDir
                Status = "Missing"
                Description = "Prompts directory"
            }
            $results.Issues += ".github/prompts"
            Write-Host "  [MISSING] $(Get-RelativePath $promptsDir)/" -ForegroundColor Red
        }

        # Check skills directory
        $skillsDir = $Global:InstallerConfig.Files.SkillFiles.Target
        if (Test-Path $skillsDir -PathType Container) {
            $results.Files += @{
                Path = $skillsDir
                Status = "Present"
                Description = "Skills directory"
            }
            Write-Host "  [FOUND  ] $(Get-RelativePath $skillsDir)/" -ForegroundColor Green

            # Check specific skill files
            $requiredSkills = $Global:InstallerConfig.Files.SkillFiles.Files

            foreach ($file in $requiredSkills) {
                $filePath = Join-Path $Global:WorkspaceRoot $file

                if (Test-Path $filePath) {
                    $results.Files += @{
                        Path = $file
                        Status = "Present"
                        Description = "Skill file"
                    }
                    Write-Host "    [FOUND  ] $file" -ForegroundColor Green
                } else {
                    $results.Files += @{
                        Path = $file
                        Status = "Missing"
                        Description = "Skill file"
                    }
                    Write-Host "    [MISSING] $file" -ForegroundColor Red
                    $results.Issues += $file
                }
            }
        } else {
            $results.Files += @{
                Path = $skillsDir
                Status = "Missing"
                Description = "Skills directory"
            }
            $results.Issues += ".github/skills"
            Write-Host "  [MISSING] $(Get-RelativePath $skillsDir)/" -ForegroundColor Red
        }

        # Check .vscode/settings.json
        $settingsFile = Join-Path (Join-Path $workspaceRoot ".vscode") "settings.json"
        $filesChecked++
        if (Test-Path $settingsFile) {
            $results.Files += @{
                Path = ".vscode/settings.json"
                Status = "Present"
                Description = "AI infrastructure settings file"
            }
            Write-Host "  [FOUND  ] .vscode/settings.json" -ForegroundColor Green
            $filesPassed++
        } else {
            $results.Files += @{
                Path = ".vscode/settings.json"
                Status = "Not Present"
                Description = "AI infrastructure not installed"
            }
            Write-Host "  [MISSING] .vscode/settings.json" -ForegroundColor Red
            $filesFailed++
            $results.Issues += ".vscode/settings.json"
            $allGood = $false
        }

        # Show results summary - context-aware based on operation
        if ($results.Issues.Count -gt 0) {
            if ($AfterClean) {
                # After -Clean, missing files are EXPECTED and GOOD
                $results.Success = $true
                Write-Host ""
                Write-Host " AI infrastructure files successfully removed!" -ForegroundColor Green
                Write-Host " Workspace is clean and ready for commit." -ForegroundColor Cyan
            } else {
                # During normal -Verify, missing files indicate not installed
                $results.Success = $false
                Write-Host ""
                Write-Host " Some AI infrastructure files are missing!" -ForegroundColor Red
                Write-Host ""
                Write-Host " Issues Found:" -ForegroundColor Yellow
                Write-Host ""
                foreach ($item in $results.Issues) {
                    Write-Host "  - $item" -ForegroundColor Red
                }

                if (-not $results.IsSourceRepo) {
                    Write-Host ""
                    Write-Host " TIP: To install missing files, run the installer without -Verify" -ForegroundColor Cyan
                }
            }
        } else {
            # All files present
            if ($AfterClean) {
                # After -Clean, finding files is BAD (cleanup failed)
                $results.Success = $false
                Write-Host ""
                Write-Host " WARNING: AI infrastructure files still present after cleanup!" -ForegroundColor Red
                Write-Host " Some files may not have been removed properly." -ForegroundColor Red
            } else {
                # During normal -Verify, having files is GOOD
                $results.Success = $true
                Write-Host ""
                Write-Host " All AI infrastructure files are present!" -ForegroundColor Green
            }
        }

        # Prepare details for centralized summary
        $details = @()
        $totalItemsChecked = $results.Files.Count
        $issuesFound = $results.Issues.Count
        $itemsSuccessful = $totalItemsChecked - $issuesFound

        # Determine branch type based on current branch (same logic as installation)
        $currentBranch = $validation.Git.CurrentBranch
        $sourceBranches = @("main", "master")
        $branchType = if ($currentBranch -in $sourceBranches) {
            "source"
        } elseif ($currentBranch -eq "Unknown") {
            "Unknown"
        } else {
            "feature"
        }

        $details += "Branch Type: $branchType"
        $details += "Target Branch: $currentBranch"
        $details += "Files Verified: $totalItemsChecked"
        $details += "Issues Found: $issuesFound"
        $details += "Location: $workspaceRoot"

        # Define next steps
        $nextSteps = @(
            "Run installation if components are missing",
            "Use -Clean option to remove installation if needed"
        )

        # Use centralized success reporting
        # Success determination depends on context:
        # - AfterClean: Success = issues found (files removed)
        # - Normal verify: Success = no issues (files present)
        Show-OperationSummary -OperationName "Verification" -Success $results.Success -DryRun $false -Details $details -NextSteps $nextSteps

        return $results
    }
    finally {
        Pop-Location
    }
}

#endregion

# Export only the functions actually used by the main script and inter-module dependencies
Export-ModuleMember -Function @(
    'Test-WorkspaceValid',
    'Test-PreInstallation',
    'Invoke-VerifyWorkspace',
    'Test-SourceRepository',
    'Test-IsAzureRMProviderRepo',
    'Test-UncommittedChange'
)
