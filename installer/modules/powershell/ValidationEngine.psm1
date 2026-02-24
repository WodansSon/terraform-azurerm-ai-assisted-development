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

function Test-GitRepository {
    <#
    .SYNOPSIS
    Test if current directory is a valid git repository with branch safety checks
    #>
    param(
        [bool]$AllowBootstrapOnSource = $false,
        [bool]$RequireOriginRemote = $false,
        [string]$WorkspacePath = ""
    )

    $results = @{
        Valid = $false
        IsGitRepo = $false
        HasOriginRemote = $false
        CurrentBranch = ""
        OriginRemoteUrl = ""
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

                # Get origin remote URL
                try {
                    $results.OriginRemoteUrl = git remote get-url origin 2>$null
                    $results.HasOriginRemote = $LASTEXITCODE -eq 0 -and $results.OriginRemoteUrl
                }
                catch {
                    $results.HasOriginRemote = $false
                }

                # CRITICAL SAFETY CHECK: Prevent running on source branch (unless bootstrap)
                $sourceBranches = @("main", "master")
                $isSourceBranch = $results.CurrentBranch -in $sourceBranches

                $results.Valid = $results.IsGitRepo -and (-not $isSourceBranch -or $AllowBootstrapOnSource) -and (-not $RequireOriginRemote -or $results.HasOriginRemote)

                if ($isSourceBranch -and -not $AllowBootstrapOnSource) {
                    $results.Reason = "SAFETY VIOLATION: Cannot run installer on source branch '$($results.CurrentBranch)'. Switch to a different branch to install AI infrastructure."
                }
                elseif ($RequireOriginRemote -and -not $results.HasOriginRemote) {
                    $results.Reason = "Git repository has no origin remote configured"
                }
                elseif ($results.Valid) {
                    if ($isSourceBranch -and $AllowBootstrapOnSource) {
                        $results.Reason = "Source branch - bootstrap operations allowed"
                    } elseif ($RequireOriginRemote) {
                        $results.Reason = "Valid git repository with origin remote configured"
                    } else {
                        $results.Reason = "Valid git repository"
                    }
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

    param()

    $results = @{
        OverallValid = $true
        PowerShell = Test-PowerShellVersion
        ExecutionPolicy = Test-ExecutionPolicy
        Commands = Test-RequiredCommand
    }

    # Check if any requirement failed
    $results.OverallValid = $results.PowerShell.Valid -and
                           $results.ExecutionPolicy.Valid -and
                           $results.Commands.Valid

    return $results
}

function Get-InstallerChecksum {
    param(
        [Parameter(Mandatory)]
        [string]$InstallerRoot
    )

    $manifestPath = Join-Path $InstallerRoot "file-manifest.config"
    $payloadRoot = Join-Path $InstallerRoot "aii"

    if (-not (Test-Path $manifestPath)) {
        return @{ Valid = $false; Reason = "Installer manifest not found" }
    }
    if (-not (Test-Path $payloadRoot)) {
        return @{ Valid = $false; Reason = "Installer payload not found" }
    }

    # IMPORTANT: This checksum algorithm must match the Bash/release implementation.
    # Bash behavior:
    # - Write manifest hash line first
    # - Then append payload file hash lines, with payload files sorted by path using LC_ALL=C
    # - Hash the resulting text (with \n newlines) including the trailing final newline
    # - sha256sum outputs lowercase hex

    $manifestHash = (Get-FileHash -Path $manifestPath -Algorithm SHA256).Hash.ToLowerInvariant()
    $lines = [System.Collections.Generic.List[string]]::new()
    $lines.Add("$manifestHash  file-manifest.config")

    $payloadFiles = Get-ChildItem -Path $payloadRoot -Recurse -File
    $payloadPaths = [System.Collections.Generic.List[string]]::new()
    foreach ($file in $payloadFiles) {
        $relPath = $file.FullName.Substring($payloadRoot.Length + 1) -replace "\\", "/"
        $payloadPaths.Add($relPath)
    }
    $payloadPaths.Sort([System.StringComparer]::Ordinal)

    $dirSep = [System.IO.Path]::DirectorySeparatorChar
    foreach ($relPath in $payloadPaths) {
        $fullPath = Join-Path $payloadRoot ($relPath -replace "/", [string]$dirSep)
        $fileHash = (Get-FileHash -Path $fullPath -Algorithm SHA256).Hash.ToLowerInvariant()
        $lines.Add("$fileHash  aii/$relPath")
    }

    $combined = ($lines -join "`n") + "`n"
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($combined)
    $sha256 = [System.Security.Cryptography.SHA256]::Create()
    $hashBytes = $sha256.ComputeHash($bytes)
    $overallHash = ($hashBytes | ForEach-Object { $_.ToString("x2") }) -join ""

    return @{ Valid = $true; Hash = $overallHash }
}

function Write-InstallerChecksum {
    param(
        [Parameter(Mandatory)]
        [string]$InstallerRoot,

        [string]$Version
    )

    $checksumPath = Join-Path $InstallerRoot "aii.checksum"
    $result = Get-InstallerChecksum -InstallerRoot $InstallerRoot
    if (-not $result.Valid) {
        return $result
    }

    if (-not $Version) {
        $versionPath = Join-Path $InstallerRoot "VERSION"
        if (Test-Path $versionPath) {
            $Version = (Get-Content -Path $versionPath -Raw).Trim()
        }
    }

    if (-not $Version) {
        $Version = "dev"
    }

    $timestamp = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
    @(
        "version=$Version",
        "timestamp=$timestamp",
        "hash=$($result.Hash)"
    ) | Set-Content -Path $checksumPath

    return @{ Valid = $true; Hash = $result.Hash; Path = $checksumPath }
}

function Test-InstallerChecksum {
    param(
        [Parameter(Mandatory)]
        [string]$InstallerRoot
    )

    $checksumPath = Join-Path $InstallerRoot "aii.checksum"
    if (-not (Test-Path $checksumPath)) {
        return @{ Valid = $false; Reason = "Installer checksum file not found" }
    }

    $hashLine = Get-Content -Path $checksumPath | Where-Object { $_ -match '^hash=' } | Select-Object -First 1
    if (-not $hashLine) {
        return @{ Valid = $false; Reason = "Installer checksum file missing hash" }
    }

    $expected = $hashLine.Substring(5).Trim()
    if (-not $expected) {
        return @{ Valid = $false; Reason = "Installer checksum hash is empty" }
    }

    # Normalize to lowercase to avoid case-only mismatches
    $expected = $expected.ToLowerInvariant()

    $computed = Get-InstallerChecksum -InstallerRoot $InstallerRoot
    if (-not $computed.Valid) {
        return @{ Valid = $false; Reason = $computed.Reason }
    }

    if ($expected -ne $computed.Hash) {
        return @{ Valid = $false; Reason = "Installer checksum mismatch"; Expected = $expected; Actual = $computed.Hash }
    }

    return @{ Valid = $true; Hash = $computed.Hash }
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
        [bool]$RequireProviderRepo = $false,

        [bool]$WarnOnUncommittedChanges = $true
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
    $results.Git = Test-GitRepository -AllowBootstrapOnSource $AllowBootstrapOnSource -RequireOriginRemote $RequireProviderRepo -WorkspacePath $gitPath

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
    if ($WarnOnUncommittedChanges -and $results.UncommittedChanges.HasUncommittedChanges) {
        Write-Warning "Target repository has uncommitted changes that may be overwritten"
    }

    return $results
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
        $validation = Test-PreInstallation -AllowBootstrapOnSource:$true -WarnOnUncommittedChanges:$false  # Allow verification on source

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

        # This installer uses an offline payload; verification does not require remote manifest checks.

        # Check main instructions file
        $instructionsFile = $Global:InstallerConfig.Files.Instructions.Target
        if (Test-Path $instructionsFile) {
            $results.Files += @{
                Path = $instructionsFile
                ItemType = "File"
                Status = "Present"
                Description = "Main Copilot instructions"
            }
            Write-Host "  [FOUND  ] $(Get-RelativePath $instructionsFile)" -ForegroundColor Green
        } else {
            $results.Files += @{
                Path = $instructionsFile
                ItemType = "File"
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
                ItemType = "Directory"
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
                        ItemType = "File"
                        Status = "Present"
                        Description = "Instruction file"
                    }
                    Write-Host "    [FOUND  ] $file" -ForegroundColor Green
                } else {
                    $results.Files += @{
                        Path = $file
                        ItemType = "File"
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
                ItemType = "Directory"
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
                ItemType = "Directory"
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
                        ItemType = "File"
                        Status = "Present"
                        Description = "Prompt file"
                    }
                    Write-Host "    [FOUND  ] $file" -ForegroundColor Green
                } else {
                    $results.Files += @{
                        Path = $file
                        ItemType = "File"
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
                ItemType = "Directory"
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
                ItemType = "Directory"
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
                        ItemType = "File"
                        Status = "Present"
                        Description = "Skill file"
                    }
                    Write-Host "    [FOUND  ] $file" -ForegroundColor Green
                } else {
                    $results.Files += @{
                        Path = $file
                        ItemType = "File"
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
                ItemType = "Directory"
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
                ItemType = "File"
                Status = "Present"
                Description = "AI infrastructure settings file"
            }
            Write-Host "  [FOUND  ] .vscode/settings.json" -ForegroundColor Green
            $filesPassed++
        } else {
            $results.Files += @{
                Path = ".vscode/settings.json"
                ItemType = "File"
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
                Write-IssuesBlock -Issues $results.Issues

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
        $directoriesChecked = @($results.Files | Where-Object { $_.ItemType -eq 'Directory' }).Count
        $filesCheckedTotal = @($results.Files | Where-Object { $_.ItemType -eq 'File' }).Count
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
        $details += "Files Verified: $filesCheckedTotal"
        $details += "Directories Verified: $directoriesChecked"
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
        Show-OperationSummary -OperationName "Verification" -Success $results.Success -Details $details
        Write-NextStepsBlock -Steps $nextSteps
        Show-SourceBranchWelcome

        return $results
    }
    finally {
        Pop-Location
    }
}

function Invoke-VerifyInstallerBundle {
    <#
    .SYNOPSIS
    Verifies the integrity of the local installer bundle (user profile/release extraction)

    .DESCRIPTION
    Checks for required installer files, bundled payload (aii/), and validates the payload checksum.
    This is a local self-check and does not verify installation into a target repository.

    .PARAMETER InstallerRoot
    The root directory containing the installer scripts (install-copilot-setup.ps1/.sh), modules, and aii/.
    #>
    param(
        [Parameter(Mandatory)]
        [string]$InstallerRoot
    )

    $results = @{
        Success = $true
        Issues = @()
        InstallerRoot = $InstallerRoot
    }

    Write-Host ""
    Write-Separator
    Write-Host " Installer Bundle Verification" -ForegroundColor Cyan
    Write-Separator
    Write-Host ""

    $requiredPaths = @(
        @{ Display = "file-manifest.config"; Path = (Join-Path $InstallerRoot "file-manifest.config"); Type = "File" },
        @{ Display = "install-copilot-setup.ps1"; Path = (Join-Path $InstallerRoot "install-copilot-setup.ps1"); Type = "File" },
        @{ Display = "install-copilot-setup.sh"; Path = (Join-Path $InstallerRoot "install-copilot-setup.sh"); Type = "File" },
        @{ Display = "modules/powershell"; Path = (Join-Path $InstallerRoot "modules\powershell"); Type = "Directory" },
        @{ Display = "modules/bash"; Path = (Join-Path $InstallerRoot "modules\bash"); Type = "Directory" },
        @{ Display = "aii/"; Path = (Join-Path $InstallerRoot "aii"); Type = "Directory" },
        @{ Display = "aii.checksum"; Path = (Join-Path $InstallerRoot "aii.checksum"); Type = "File" }
    )

    foreach ($item in $requiredPaths) {
        $exists = if ($item.Type -eq "Directory") {
            Test-Path -Path $item.Path -PathType Container
        } else {
            Test-Path -Path $item.Path -PathType Leaf
        }

        if ($exists) {
            Write-Host "  [FOUND  ] $($item.Display)" -ForegroundColor Green
        }
        else {
            $results.Success = $false
            $results.Issues += $item.Display
            Write-Host "  [MISSING] $($item.Display)" -ForegroundColor Red
        }
    }

    $checksum = Test-InstallerChecksum -InstallerRoot $InstallerRoot
    if (-not $checksum.Valid) {
        $results.Success = $false
        $results.Issues += "payload checksum validation failed: $($checksum.Reason)"
        Write-Host ""
        Write-Host " Payload checksum validation failed: $($checksum.Reason)" -ForegroundColor Yellow
    }

    $details = @(
        "Location: $InstallerRoot",
        "Issues Found: $($results.Issues.Count)"
    )

    $scriptPath = Join-Path $InstallerRoot 'install-copilot-setup.ps1'

    $nextSteps = if ($results.Success) {
        @(
            "1. Change directory to your installer bundle:",
            "     cd `"$InstallerRoot`"",
            "2. To verify a target repository: .\install-copilot-setup.ps1 -Verify -RepoDirectory `"<path-to-terraform-provider-azurerm>`"",
            "3. To install AI infrastructure: .\install-copilot-setup.ps1 -RepoDirectory `"<path-to-terraform-provider-azurerm>`""
        )
    }
    else {
        @(
            "  If using a release bundle: re-extract the latest bundle to your user profile",
            "  If contributing: re-run -Bootstrap from a local git clone",
            "  Then re-run: & `"$scriptPath`" -Verify"
        )
    }

    Show-OperationSummary -OperationName "Bundle Verification" -Success $results.Success -Details $details
    Write-NextStepsBlock -Steps $nextSteps
    Show-SourceBranchWelcome

    return $results
}

#endregion

# Export only the functions actually used by the main script and inter-module dependencies
Export-ModuleMember -Function @(
    'Test-WorkspaceValid',
    'Test-PreInstallation',
    'Test-InstallerChecksum',
    'Write-InstallerChecksum',
    'Invoke-VerifyInstallerBundle',
    'Invoke-VerifyWorkspace',
    'Test-IsAzureRMProviderRepo',
    'Test-UncommittedChange'
)
