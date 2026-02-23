# FileOperations Module for Terraform AzureRM Provider AI Setup
# STREAMLINED VERSION - Contains only functions actually used by main script

# Note: CommonUtilities module is imported globally by the main script

#region Private Functions

function Assert-DirectoryExist {
    <#
    .SYNOPSIS
    Ensure a directory exists, creating it if necessary
    #>
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    if (-not (Test-Path $Path -PathType Container)) {
        try {
            New-Item -Path $Path -ItemType Directory -Force | Out-Null
            return $true
        }
        catch {
            Write-Error "Failed to create directory '$Path': $($_.Exception.Message)"
            return $false
        }
    }

    return $true
}

#endregion

#region Public Functions

function Copy-LocalAIFile {
    <#
    .SYNOPSIS
    Copy a single AI infrastructure file from local toolkit source
    #>
    param(
        [Parameter(Mandatory)]
        [string]$FilePath,

        [Parameter(Mandatory)]
        [string]$SourceFile,

        [Parameter(Mandatory)]
        [string]$WorkspaceRoot
    )

    $result = @{
        FilePath = $FilePath
        Success = $false
        Action = "None"
        Message = ""
        Size = 0
        DebugInfo = @{}
    }

    try {
        # Resolve the target file path
        $targetFilePath = Join-Path $WorkspaceRoot $FilePath
        $result.DebugInfo.WorkspaceRoot = $WorkspaceRoot
        $result.DebugInfo.SourceFile = $SourceFile
        $result.DebugInfo.TargetPath = $targetFilePath

        # Ensure target directory exists
        $targetDir = Split-Path $targetFilePath -Parent
        if (-not (Assert-DirectoryExist -Path $targetDir)) {
            $result.Message = "Failed to create target directory"
            return $result
        }

        # Copy the file
        Copy-Item -Path $SourceFile -Destination $targetFilePath -Force

        $result.Success = $true
        $result.Action = "Copied"
        $result.Message = "Copied successfully"

        if (Test-Path $targetFilePath) {
            $fileInfo = Get-Item $targetFilePath
            $result.Size = $fileInfo.Length
        }

    } catch {
        $result.Success = $false
        $result.Message = "Copy failed: $($_.Exception.Message)"
        $result.DebugInfo.ExceptionMessage = $_.Exception.Message
        $result.DebugInfo.ExceptionType = $_.Exception.GetType().FullName
    }

    return $result
}

function Install-AllAIFile {
    <#
    .SYNOPSIS
    Install all AI infrastructure files

    .PARAMETER RequireProviderRepo
    Require that the workspace is a Terraform provider repository (not AI dev repo).
    Used when installing via -RepoDirectory to a target repository.

    .PARAMETER LocalSourcePath
    Local directory to copy AI files from instead of the bundled payload.
    Contributor feature for testing uncommitted changes.
    #>
    param(
        [string]$Branch = "main",
        [string]$WorkspaceRoot = $null,
        [hashtable]$ManifestConfig = $null,
        [bool]$RequireProviderRepo = $false,
        [string]$LocalSourcePath = ""
    )

    # CRITICAL: Use centralized pre-installation validation (replaces scattered safety checks)
    Write-Host "Validating installation prerequisites..." -ForegroundColor Cyan
    # This installer no longer downloads AI files from the network.
    # Source is always local: bundled payload (aii/) or -LocalPath.
    $validation = Test-PreInstallation -AllowBootstrapOnSource:$false -RequireProviderRepo:$RequireProviderRepo

    if (-not $validation.OverallValid) {
        Write-Host ""
        Write-Host "Pre-installation validation failed!" -ForegroundColor Red
        Write-Host ""

        # Show specific validation failures
        if (-not $validation.Git.Valid) {
            Write-Host "   Git Issue: $($validation.Git.Reason)" -ForegroundColor Yellow
        }
        if (-not $validation.Workspace.Valid -and -not $validation.Workspace.Skipped) {
            Write-Host "   Workspace Issue: $($validation.Workspace.Reason)" -ForegroundColor Yellow
        }
        if ($validation.RepositoryValidation -and -not $validation.RepositoryValidation.Valid) {
            Write-Host "   Repository Issue: $($validation.RepositoryValidation.Reason)" -ForegroundColor Yellow
        }
        if (-not $validation.SystemRequirements.OverallValid) {
            Write-Host "   System Requirements Issue:" -ForegroundColor Yellow
            if (-not $validation.SystemRequirements.PowerShell.Valid) {
                Write-Host "     - PowerShell: $($validation.SystemRequirements.PowerShell.Reason)" -ForegroundColor Yellow
            }
            if (-not $validation.SystemRequirements.ExecutionPolicy.Valid) {
                Write-Host "     - Execution Policy: $($validation.SystemRequirements.ExecutionPolicy.Reason)" -ForegroundColor Yellow
            }
            if (-not $validation.SystemRequirements.Commands.Valid) {
                Write-Host "     - Required Commands: Missing $(($validation.SystemRequirements.Commands.MissingCommands) -join ', ')" -ForegroundColor Yellow
            }
        }

        Write-Host ""
        Write-Host "Fix these issues and try again." -ForegroundColor Cyan

        return @{
            TotalFiles = 0
            Successful = 0
            Failed = 0
            Skipped = 0
            Files = @{}
            OverallSuccess = $false
            ValidationFailed = $true
            ValidationResults = $validation
            DebugInfo = @{
                StartTime = Get-Date
                Branch = $Branch
                FailureReason = "Pre-installation validation failed"
            }
        }
    }

    Write-Host "All prerequisites validated successfully!" -ForegroundColor Green
    Write-Host ""

    # CRITICAL SAFETY CHECK: Verify this is actually an AzureRM provider repository
    if (-not $validation.RepositoryValidation.Valid) {
        Write-Host ""
        Write-Host "SAFETY CHECK FAILED: Target directory is not a Terraform AzureRM provider repository!" -ForegroundColor Red
        Write-Host ""
        Write-Host "Reason: $($validation.RepositoryValidation.Reason)" -ForegroundColor Yellow
        Write-Host ""
        Write-Host "This installer should only be run on the terraform-provider-azurerm repository." -ForegroundColor Cyan
        Write-Host "Installing AI infrastructure files to the wrong repository could cause issues." -ForegroundColor Cyan
        Write-Host ""

        return @{
            TotalFiles = 0
            Successful = 0
            Failed = 0
            Skipped = 0
            Files = @{}
            OverallSuccess = $false
            ValidationFailed = $true
            ValidationResults = $validation
            DebugInfo = @{
                StartTime = Get-Date
                Branch = $Branch
                FailureReason = "Target is not AzureRM provider repository"
            }
        }
    }

    # CRITICAL SAFETY CHECK: Warn about uncommitted changes
    if ($validation.UncommittedChanges.HasUncommittedChanges) {
        Write-Host ""
        Write-Host "WARNING: Uncommitted Changes Detected!" -ForegroundColor Yellow
        Write-Host ""
        Write-Host "The target repository has uncommitted changes:" -ForegroundColor Cyan

        if ($validation.UncommittedChanges.ChangedFiles.Count -gt 0) {
            Write-Host "  Modified files: $($validation.UncommittedChanges.ChangedFiles.Count)" -ForegroundColor White

            # Show AI infrastructure files that will be affected
            $aiInfraChanges = $validation.UncommittedChanges.ChangedFiles | Where-Object { $_.IsAIInfrastructure }
            if ($aiInfraChanges.Count -gt 0) {
                Write-Host ""
                Write-Host "  AI Infrastructure files with changes (WILL BE OVERWRITTEN):" -ForegroundColor Red
                foreach ($file in $aiInfraChanges) {
                    Write-Host "    - $($file.Path) [$($file.Status)]" -ForegroundColor Red
                }
            }
        }

        Write-Host ""
        Write-Host "Installing will OVERWRITE these files with versions from the toolkit repository." -ForegroundColor Yellow
        Write-Host "Any uncommitted changes will be LOST unless you commit them first." -ForegroundColor Yellow
        Write-Host ""
        Write-Host "Recommended actions:" -ForegroundColor Cyan
        Write-Host "  1. Commit your changes: git add -A && git commit -m 'Save work before AI infrastructure update'" -ForegroundColor White
        Write-Host "  2. Or stash them: git stash" -ForegroundColor White
        Write-Host "  3. Then re-run this installer" -ForegroundColor White
        Write-Host ""

        Write-Host ""
        Write-Host "Proceeding with installation..." -ForegroundColor Yellow
        Write-Host ""
    }

    # Use provided manifest configuration or get it directly
    if ($ManifestConfig) {
        $manifestConfig = $ManifestConfig
    } else {
        # Fallback: require ConfigParser to be loaded in parent scope
        if (-not (Get-Command Get-ManifestConfig -ErrorAction SilentlyContinue)) {
            throw "ManifestConfig parameter required or Get-ManifestConfig must be available"
        }
        $manifestConfig = Get-ManifestConfig -Branch $Branch
    }
    $allFiles = @()
    # Only include infrastructure files, not bootstrap installer files
    # This matches the cleanup process logic
    if ($manifestConfig.Sections.MAIN_FILES) {
        $allFiles += $manifestConfig.Sections.MAIN_FILES
    }
    if ($manifestConfig.Sections.INSTRUCTION_FILES) {
        $allFiles += $manifestConfig.Sections.INSTRUCTION_FILES
    }
    if ($manifestConfig.Sections.PROMPT_FILES) {
        $allFiles += $manifestConfig.Sections.PROMPT_FILES
    }
    if ($manifestConfig.Sections.SKILL_FILES) {
        $allFiles += $manifestConfig.Sections.SKILL_FILES
    }
    if ($manifestConfig.Sections.UNIVERSAL_FILES) {
        $allFiles += $manifestConfig.Sections.UNIVERSAL_FILES
    }

    $results = @{
        TotalFiles = $allFiles.Count
        Successful = 0
        Failed = 0
        Skipped = 0
        Files = @{}
        OverallSuccess = $true
        DebugInfo = @{
            StartTime = Get-Date
            Branch = $Branch
            LocalSourcePath = $LocalSourcePath
            SourceMode = ""
            SourceRoot = ""
        }
    }

    # Determine source for AI files
    # Priority: LocalSourcePath (contributor) > bundled payload (aii/) (default)
    $sourceRoot = $null
    $sourceMode = $null

    # Check if LocalSourcePath parameter was explicitly provided
    $localPathWasProvided = $PSBoundParameters.ContainsKey('LocalSourcePath')

    if ($localPathWasProvided) {
        # Contributor feature: Use explicitly specified local path
        # Note: Path existence validation happens in main script PRIORITY 4 check

        # Validate it's actually the AI installer repo (has installer directory)
        $installerDir = Join-Path $LocalSourcePath "installer"
        if (-not (Test-Path $installerDir)) {
            Write-Host ""
            Write-Host "ERROR: Local path does not appear to be the AI installer repository" -ForegroundColor Red
            Write-Host "Expected to find 'installer' directory at: $installerDir" -ForegroundColor Yellow
            Write-Host ""
            $results.OverallSuccess = $false
            return $results
        }

        $sourceRoot = $LocalSourcePath
        $sourceMode = "local-path"
        Write-Host "Installing from local path: " -ForegroundColor Cyan -NoNewline
        Write-Host $LocalSourcePath -ForegroundColor White
    }
    else {
        $payloadRoot = if ($Global:ScriptRoot) { Join-Path $Global:ScriptRoot "aii" } else { $null }
        if ($payloadRoot -and (Test-Path $payloadRoot)) {
            $sourceRoot = $payloadRoot
            $sourceMode = "payload"
            Write-Host "Installing from bundled payload: " -ForegroundColor Cyan -NoNewline
            Write-Host $payloadRoot -ForegroundColor White
        } else {
            Write-Host ""
            Write-Host "ERROR: Bundled payload directory not found." -ForegroundColor Red
            if ($payloadRoot) {
                Write-Host "Expected payload at: $payloadRoot" -ForegroundColor Yellow
            }
            Write-Host ""
            Write-Host "Fix:" -ForegroundColor Yellow
            Write-Host "  - Extract the official release bundle into your user profile, OR" -ForegroundColor Yellow
            Write-Host "  - Re-run -Bootstrap from a git clone, OR" -ForegroundColor Yellow
            Write-Host "  - Use -LocalPath to install directly from a local working tree." -ForegroundColor Yellow
            Write-Host ""
            $results.OverallSuccess = $false
            return $results
        }
    }

    $results.DebugInfo.SourceMode = $sourceMode
    $results.DebugInfo.SourceRoot = $sourceRoot

    Write-Host "Preparing to install $($allFiles.Count) files..." -ForegroundColor Cyan
    Write-Host ""

    $fileIndex = 0
    foreach ($filePath in $allFiles) {
        $fileIndex++

        $sourceFile = Join-Path $sourceRoot $filePath
        if (-not (Test-Path $sourceFile)) {
            Write-Warning "Source file not found: $sourceFile"
            $results.Files[$filePath] = @{
                FilePath = $filePath
                Success = $false
                Action = "Skipped"
                Message = "Source file not found"
                Size = 0
                DebugInfo = @{
                    SourceFile = $sourceFile
                    SourceRoot = $sourceRoot
                    SourceMode = $sourceMode
                }
            }
            continue
        }

        $percentComplete = [math]::Round(($fileIndex / $allFiles.Count) * 100)
        # Dynamic padding to align closing brackets (1-digit=2 spaces, 2-digit=1 space, 3-digit=0 spaces)
        $progressPadding = if ($percentComplete -lt 10) { "  " } elseif ($percentComplete -lt 100) { " " } else { "" }
        $progressText = "[$percentComplete%$progressPadding]"

        Write-Host "  Copying " -ForegroundColor Cyan -NoNewline
        Write-Host $progressText -ForegroundColor Green -NoNewline
        Write-Host ": " -ForegroundColor Cyan -NoNewline
        Write-Host $filePath -ForegroundColor White

        $fileResult = Copy-LocalAIFile -FilePath $filePath -SourceFile $sourceFile -WorkspaceRoot $WorkspaceRoot
        $results.Files[$filePath] = $fileResult

        # Show error details if copy failed
        if (-not $fileResult.Success) {
            Write-Host "   ERROR: $($fileResult.Message)" -ForegroundColor Red
            if ($fileResult.DebugInfo.ExceptionMessage) {
                Write-Host "   DETAILS: $($fileResult.DebugInfo.ExceptionMessage)" -ForegroundColor Red
            }
        }

        switch ($fileResult.Action) {
            { $_ -in @("Copied") } { $results.Successful++ }
            { $_ -in @("Skipped") } { $results.Skipped++ }
            default {
                $results.Failed++
                $results.OverallSuccess = $false
            }
        }
    }

    # Show detailed debug summary
    $results.DebugInfo.EndTime = Get-Date
    if ($results.DebugInfo.StartTime -and $results.DebugInfo.EndTime) {
        $results.DebugInfo.TotalDuration = ($results.DebugInfo.EndTime - $results.DebugInfo.StartTime).TotalMilliseconds
    } else {
        $results.DebugInfo.TotalDuration = 0
    }

    # Calculate total size of all processed files
    $totalSize = 0
    foreach ($fileResult in $results.Files.Values) {
        if ($fileResult.Size -gt 0) {
            $totalSize += $fileResult.Size
        }
    }
    $results.DebugInfo.TotalSizeBytes = $totalSize

    return $results
}

function Remove-AIFile {
    <#
    .SYNOPSIS
    Remove a single AI infrastructure file
    #>
    param(
        [Parameter(Mandatory)]
        [string]$FilePath,

        [string]$WorkspaceRoot = ""
    )

    # Resolve file path relative to workspace root if provided
    $resolvedFilePath = if ($WorkspaceRoot -and -not [System.IO.Path]::IsPathRooted($FilePath)) {
        Join-Path $WorkspaceRoot $FilePath
    } else {
        $FilePath
    }

    $result = @{
        FilePath = $resolvedFilePath
        Success = $false
        Action = "None"
        Message = ""
    }

    try {
        if (-not (Test-Path $resolvedFilePath)) {
            $result.Action = "Not Found"
            $result.Success = $true
            $result.Message = "File does not exist"
            return $result
        }

        # Remove file
        Remove-Item -Path $resolvedFilePath -Force -ErrorAction Stop

        $result.Action = "Removed"
        $result.Success = $true
        $result.Message = "File successfully removed"
    }
    catch {
        $result.Message = "Failed to remove file: $($_.Exception.Message)"
    }

    return $result
}

function Remove-AllAIFile {
    <#
    .SYNOPSIS
    Remove all AI infrastructure files and clean up
    #>
    param(
        [string]$Branch = "main",
        [string]$WorkspaceRoot = "",
        [hashtable]$ManifestConfig = $null
    )

    # Use provided manifest configuration or get it directly
    if ($ManifestConfig) {
        $manifestConfig = $ManifestConfig
    } else {
        # Fallback: require ConfigParser to be loaded in parent scope
        if (-not (Get-Command Get-ManifestConfig -ErrorAction SilentlyContinue)) {
            throw "ManifestConfig parameter required or Get-ManifestConfig must be available"
        }
        $manifestConfig = Get-ManifestConfig -Branch $Branch
    }
    $allFiles = @()
    # Only include infrastructure files, not bootstrap installer files
    # This matches the installation process logic
    if ($manifestConfig.Sections.MAIN_FILES) {
        $allFiles += $manifestConfig.Sections.MAIN_FILES
    }
    if ($manifestConfig.Sections.INSTRUCTION_FILES) {
        $allFiles += $manifestConfig.Sections.INSTRUCTION_FILES
    }
    if ($manifestConfig.Sections.PROMPT_FILES) {
        $allFiles += $manifestConfig.Sections.PROMPT_FILES
    }
    if ($manifestConfig.Sections.SKILL_FILES) {
        $allFiles += $manifestConfig.Sections.SKILL_FILES
    }
    if ($manifestConfig.Sections.UNIVERSAL_FILES) {
        $allFiles += $manifestConfig.Sections.UNIVERSAL_FILES
    }

    # Dynamically determine directories to check based on manifest file paths
    $directoriesToCheck = @()
    $uniqueDirectories = @{}

    foreach ($filePath in $allFiles) {
        $directory = Split-Path $filePath -Parent
        if ($directory -and -not $uniqueDirectories.ContainsKey($directory)) {
            # Only allow cleanup of specific AI infrastructure directories
            # This prevents accidental removal of important repository directories
            $allowedForCleanup = $false

            # AI directories that are safe to clean up
            $aiDirectories = @(
                ".github/instructions",
                ".github/prompts",
                ".github/skills"
            )

            # Normalize path separators for cross-platform compatibility
            $normalizedDirectory = $directory -replace '\\', '/'

            foreach ($aiDir in $aiDirectories) {
                if ($normalizedDirectory -eq $aiDir -or $normalizedDirectory.StartsWith("$aiDir/")) {
                    $allowedForCleanup = $true
                    break
                }
            }

            if ($allowedForCleanup) {
                $uniqueDirectories[$directory] = $true
                $directoriesToCheck += $directory

                # Also include the parent AI directory (e.g. `.github/skills`) so it can be removed
                # after child directories are deleted and it becomes empty.
                foreach ($aiDir in $aiDirectories) {
                    if ($normalizedDirectory.StartsWith("$aiDir/")) {
                        if (-not $uniqueDirectories.ContainsKey($aiDir)) {
                            $uniqueDirectories[$aiDir] = $true
                            $directoriesToCheck += $aiDir
                        }
                    }
                }
            }
        }
    }

    # Sort directories by depth (deepest first) for proper cleanup order
    # This ensures subdirectories are cleaned before parent directories
    $directoriesToCheck = $directoriesToCheck | Sort-Object { ($_ -split '[/\\]').Count } -Descending | Sort-Object

    # Calculate total work for accurate progress tracking
    $totalWork = $allFiles.Count + $directoriesToCheck.Count
    $workCompleted = 0

    # Calculate the longest filename for perfect status alignment
    $maxFileNameLength = 0
    $maxDirNameLength = 0

    foreach ($filePath in $allFiles) {
        $fileName = Split-Path $filePath -Leaf
        if ($fileName.Length -gt $maxFileNameLength) {
            $maxFileNameLength = $fileName.Length
        }
    }

    foreach ($dir in $directoriesToCheck) {
        $dirName = Split-Path $dir -Leaf
        if ($dirName.Length -gt $maxDirNameLength) {
            $maxDirNameLength = $dirName.Length
        }
    }

    # Use the longer of the two for universal alignment
    $maxNameLength = [math]::Max($maxFileNameLength, $maxDirNameLength)

    $results = @{
        TotalFiles = $allFiles.Count
        Removed = 0
        NotFound = 0
        Failed = 0
        Files = @{}
        Directories = @{}
        Success = $true
        FilesRemoved = 0
        DirectoriesCleaned = 0
        Issues = @()
    }

    # Pre-scan: Check if any AI files actually exist
    Write-Host "Scanning for AI infrastructure files..." -ForegroundColor Cyan
    $existingFiles = @()
    $existingDirectories = @()

    foreach ($filePath in $allFiles) {
        $fullPath = Join-Path $WorkspaceRoot $filePath
        if (Test-Path $fullPath) {
            $existingFiles += $filePath
        }
    }

    foreach ($dirPath in $directoriesToCheck) {
        $fullDirPath = Join-Path $WorkspaceRoot $dirPath
        if (Test-Path $fullDirPath) {
            $existingDirectories += $dirPath
        }
    }

    # Ensure deepest directories are removed first (parents last)
    $existingDirectories = $existingDirectories | Sort-Object { ($_ -split '[/\\]').Count } -Descending

    # If nothing exists, show clean message and exit early
    if ($existingFiles.Count -eq 0 -and $existingDirectories.Count -eq 0) {
        Write-Host ""
        Write-Host " No AI infrastructure files found to remove." -ForegroundColor Green
        Write-Host " Workspace is already clean!" -ForegroundColor Green

        return @{
            Success = $true
            Issues = @()
            FilesRemoved = 0
            DirectoriesCleaned = 0
            TotalFiles = $allFiles.Count
            Removed = 0
            NotFound = $allFiles.Count
            Failed = 0
            Files = @{}
            Directories = @{}
            CleanWorkspace = $true
        }
    }

    # Show what was found
    Write-Host "Found $($existingFiles.Count) AI files and $($existingDirectories.Count) directories to remove." -ForegroundColor Yellow
    Write-Host ""

    Write-Host "Removing AI Infrastructure Files" -ForegroundColor Cyan
    Write-Separator

    # Remove files (only process existing ones)
    $fileIndex = 0
    $totalWork = $existingFiles.Count + $existingDirectories.Count
    $workCompleted = 0

    # Calculate padding for clean display (only for existing files)
    $maxNameLength = 0
    foreach ($filePath in $existingFiles) {
        $fileName = Split-Path $filePath -Leaf
        if ($fileName.Length -gt $maxNameLength) {
            $maxNameLength = $fileName.Length
        }
    }

    # Also check directory names for padding
    foreach ($dirPath in $existingDirectories) {
        $dirName = Split-Path $dirPath -Leaf
        if ($dirName.Length -gt $maxNameLength) {
            $maxNameLength = $dirName.Length
        }
    }

    foreach ($filePath in $existingFiles) {
        $fileIndex++
        $workCompleted++
        $percentComplete = [math]::Round(($workCompleted / $totalWork) * 100)

        # Extract just the filename for cleaner display
        $fileName = Split-Path $filePath -Leaf

        # Calculate padding needed to align status indicators
        $fileNamePadding = " " * ($maxNameLength - $fileName.Length)

        # Pad "Removing File" to match "Removing Directory" length for perfect alignment
        # Dynamic padding to align closing brackets (1-digit=2 spaces, 2-digit=1 space, 3-digit=0 spaces)
        $progressPadding = if ($percentComplete -lt 10) { "  " } elseif ($percentComplete -lt 100) { " " } else { "" }
        $progressText = "[$percentComplete%$progressPadding]"
        Write-Host "  Removing File      " -ForegroundColor Cyan -NoNewline
        Write-Host $progressText -ForegroundColor Green -NoNewline
        Write-Host ": " -ForegroundColor Cyan -NoNewline
        Write-Host "$fileName$fileNamePadding " -ForegroundColor White -NoNewline

        $fileResult = Remove-AIFile -FilePath $filePath -WorkspaceRoot $WorkspaceRoot
        $results.Files[$filePath] = $fileResult

        switch ($fileResult.Action) {
            "Removed" {
                $results.Removed++
                $results.FilesRemoved++
                Write-Host "[OK]" -ForegroundColor Green
            }
            "Not Found" {
                $results.NotFound++
                Write-Host "[NOT FOUND]" -ForegroundColor Yellow
            }
            default {
                $results.Failed++
                $results.Success = $false
                Write-Host "[FAILED]" -ForegroundColor Red
                if ($fileResult.Message) {
                    $results.Issues += "Failed to remove ${filePath}: $($fileResult.Message)"
                }
            }
        }
    }

    # Remove empty directories (only process existing ones)
    $dirIndex = 0
    foreach ($dir in $existingDirectories) {
        $dirIndex++
        $workCompleted++
        $percentComplete = [math]::Round(($workCompleted / $totalWork) * 100)

        # Extract just the directory name for cleaner display
        $dirName = Split-Path $dir -Leaf

        # Calculate padding needed to align status indicators (same as files)
        $dirNamePadding = " " * ($maxNameLength - $dirName.Length)

        # "Removing Directory" is the longest operation name, so no padding needed
        # Dynamic padding to align closing brackets (1-digit=2 spaces, 2-digit=1 space, 3-digit=0 spaces)
        $progressPadding = if ($percentComplete -lt 10) { "  " } elseif ($percentComplete -lt 100) { " " } else { "" }
        $progressText = "[$percentComplete%$progressPadding]"
        Write-Host "  Removing Directory " -ForegroundColor Cyan -NoNewline
        Write-Host $progressText -ForegroundColor Green -NoNewline
        Write-Host ": " -ForegroundColor Cyan -NoNewline
        Write-Host "$dirName$dirNamePadding " -ForegroundColor White -NoNewline

        # Resolve directory path relative to workspace root if provided
        $resolvedDirPath = if ($WorkspaceRoot -and -not [System.IO.Path]::IsPathRooted($dir)) {
            Join-Path $WorkspaceRoot $dir
        } else {
            $dir
        }

        $dirResult = @{
            Path = $resolvedDirPath
            Action = "None"
            Success = $true
            Message = ""
        }

        if (Test-Path $resolvedDirPath -PathType Container) {
            # Check if directory is empty first
            $dirContents = Get-ChildItem $resolvedDirPath -Force
            if ($dirContents.Count -eq 0) {
                try {
                    Remove-Item -Path $resolvedDirPath -Force -ErrorAction Stop
                    $dirResult.Action = "Removed"
                    $dirResult.Message = "Empty directory removed"
                    $results.DirectoriesCleaned++
                    Write-Host "[OK]" -ForegroundColor Green
                }
                catch {
                    $dirResult.Action = "Failed"
                    $dirResult.Success = $false
                    $dirResult.Message = "Failed to remove directory: $($_.Exception.Message)"
                    $results.Success = $false
                    $results.Issues += "Failed to remove directory ${resolvedDirPath}: $($_.Exception.Message)"
                    Write-Host "[FAILED]" -ForegroundColor Red
                }
            } else {
                $dirResult.Action = "Not Empty"
                $dirResult.Message = "Directory contains other files"
                Write-Host "[NOT EMPTY]" -ForegroundColor Yellow
            }
        } else {
            $dirResult.Action = "Not Found"
            $dirResult.Message = "Directory does not exist"
            Write-Host "[NOT FOUND]" -ForegroundColor Yellow
        }

        $results.Directories[$resolvedDirPath] = $dirResult
    }

    Write-Host ""
    Write-Host "Completed AI infrastructure removal." -ForegroundColor Green

    return $results
}

function Remove-DeprecatedFile {
    <#
    .SYNOPSIS
    Removes files that were previously installed but are no longer in the manifest
    #>
    param(
        [Parameter(Mandatory)]
        [hashtable]$ManifestConfig,

        [Parameter(Mandatory)]
        [string]$WorkspaceRoot,

        [bool]$Quiet = $false
    )

    $deprecatedFiles = @()

    $instructionManifest = @($ManifestConfig.Sections.INSTRUCTION_FILES | ForEach-Object { Split-Path $_ -Leaf })
    $promptManifest = @($ManifestConfig.Sections.PROMPT_FILES | ForEach-Object { Split-Path $_ -Leaf })
    $skillManifest = @($ManifestConfig.Sections.SKILL_FILES)

    # Check for deprecated instruction files
    $instructionsDir = Join-Path $WorkspaceRoot ".github\instructions"
    if (Test-Path $instructionsDir -PathType Container) {
        $existingFiles = Get-ChildItem $instructionsDir -File | Where-Object { $_.Name -like "*.instructions.md" }

        foreach ($existingFile in $existingFiles) {
            if ($existingFile.Name -notin $instructionManifest) {
                $deprecatedFiles += @{
                    Path = $existingFile.FullName
                    Type = "Instruction"
                    Name = $existingFile.Name
                    RelativePath = $existingFile.FullName.Replace($WorkspaceRoot, "").TrimStart('\').TrimStart('/')
                }
            }
        }
    }

    # Check for deprecated prompt files
    $promptsDir = Join-Path $WorkspaceRoot ".github\prompts"
    if (Test-Path $promptsDir -PathType Container) {
        $existingPrompts = Get-ChildItem $promptsDir -File | Where-Object { $_.Name -like "*.prompt.md" }

        foreach ($existingPrompt in $existingPrompts) {
            if ($existingPrompt.Name -notin $promptManifest) {
                $deprecatedFiles += @{
                    Path = $existingPrompt.FullName
                    Type = "Prompt"
                    Name = $existingPrompt.Name
                    RelativePath = $existingPrompt.FullName.Replace($WorkspaceRoot, "").TrimStart('\').TrimStart('/')
                }
            }
        }
    }

    # Check for deprecated skill files
    $skillsDir = Join-Path $WorkspaceRoot ".github\skills"
    if ((Test-Path $skillsDir -PathType Container) -and ($skillManifest.Count -gt 0)) {
        $existingSkills = Get-ChildItem $skillsDir -Recurse -File | Where-Object { $_.Name -eq "SKILL.md" }

        foreach ($existingSkill in $existingSkills) {
            $relativePath = $existingSkill.FullName.Replace($WorkspaceRoot, "").TrimStart('\').TrimStart('/') -replace "\\", "/"
            if ($relativePath -notin $skillManifest) {
                $deprecatedFiles += @{
                    Path = $existingSkill.FullName
                    Type = "Skill"
                    Name = "SKILL.md"
                    RelativePath = $relativePath
                }
            }
        }
    }

    if ($deprecatedFiles.Count -gt 0) {
        if (-not $Quiet) {
            Write-Host ""
            Write-Host "Found deprecated files (no longer in manifest):" -ForegroundColor Yellow
            foreach ($file in $deprecatedFiles) {
                Write-Host "  [$($file.Type)] $($file.RelativePath)" -ForegroundColor Gray
            }
        }

        # Automatically remove deprecated files without prompting
        $removedCount = 0
        foreach ($file in $deprecatedFiles) {
            try {
                Remove-Item -Path $file.Path -Force
                if (-not $Quiet) {
                    Write-Host "  Removed: $($file.RelativePath)" -ForegroundColor Green
                }
                $removedCount++
            }
            catch {
                if (-not $Quiet) {
                    Write-Host "  Failed to remove: $($file.RelativePath) - $($_.Exception.Message)" -ForegroundColor Red
                }
            }
        }
        if (-not $Quiet) {
            Write-Host ""
            Write-Host "Removed $removedCount deprecated files." -ForegroundColor Green
        }
    } elseif (-not $Quiet) {
        Write-Host "No deprecated files found." -ForegroundColor Green
    }

    return $deprecatedFiles
}

function Test-BootstrapPrerequisite {
    <#
    .SYNOPSIS
    Validates that bootstrap operation is allowed under current conditions

    .PARAMETER CurrentBranch
    Current git branch name (not currently used but kept for API compatibility)

    .PARAMETER BranchType
    Type of branch (source/feature/unknown) (not currently used but kept for API compatibility)

    .PARAMETER ScriptDirectory
    Directory where the script is located

    .RETURNS
    $true if validation passes, $false if validation fails
    #>
    param(
        [string]$CurrentBranch = "unknown",

        [string]$BranchType = "unknown",

        [Parameter(Mandatory)]
        [string]$ScriptDirectory
    )

    # Rule 1: Must NOT be running from user profile directory
    $userProfileInstallerPath = Join-Path (Get-UserHomeDirectory) ".terraform-azurerm-ai-installer"
    if ($ScriptDirectory -like "*$userProfileInstallerPath*") {
        Show-BootstrapViolation -ScriptDirectory $ScriptDirectory
        return $false
    }

    return $true
}

function Invoke-Bootstrap {
    <#
    .SYNOPSIS
    Copy installer files to user profile for feature branch use

    .PARAMETER CurrentBranch
    Current git branch name

    .PARAMETER BranchType
    Type of branch (source/feature/unknown)
    #>
    param(
        [string]$CurrentBranch = "unknown",
        [string]$BranchType = "unknown"
    )

    try {
        # Validate bootstrap prerequisites before proceeding
        if (-not (Test-BootstrapPrerequisite -CurrentBranch $CurrentBranch -BranchType $BranchType -ScriptDirectory $Global:ScriptRoot)) {
            return @{
                Success = $false
            }
        }

        # Show operation title (main header already displayed by caller)
        Write-Host " Bootstrap - Copying Installer to User Profile" -ForegroundColor Cyan
        Write-Separator

        # Create target directory
        $targetDirectory = Join-Path (Get-UserHomeDirectory) ".terraform-azurerm-ai-installer"
        if (-not (Test-Path $targetDirectory)) {
            New-Item -ItemType Directory -Path $targetDirectory -Force | Out-Null
        }

        # Files to bootstrap - access directly from manifest config to avoid verify validation issues
        $filesToBootstrap = $Global:ManifestConfig.Sections.INSTALLER_FILES_BOOTSTRAP

        # CRITICAL: Always include the manifest file in bootstrap - it's required for user profile operations
        $manifestFile = "file-manifest.config"
        $manifestFileFullPath = "installer/$manifestFile"
        if (($filesToBootstrap | Where-Object { $_ -like "*$manifestFile" }).Count -eq 0) {
            $filesToBootstrap += $manifestFileFullPath
        }

        # Statistics
        $statistics = @{
            "Files Copied" = 0
            "Files Failed" = 0
            "Total Size" = 0
        }

        # Bootstrap is only supported when running from a git clone of this repository (repo root contains .git).
        # It copies the installer files from the current working tree into the user profile installer directory.
        $aiInstallerSourcePath = Join-Path $Global:WorkspaceRoot "installer"

        if (Test-Path $aiInstallerSourcePath) {
            Write-Host ""
            Write-Host "Copying installer files from current repository..." -ForegroundColor Cyan
            Write-Host ""

            # Calculate maximum filename length for alignment
            $maxFileNameLength = 0
            foreach ($file in $filesToBootstrap) {
                $fileName = Split-Path $file -Leaf
                if ($fileName.Length -gt $maxFileNameLength) {
                    $maxFileNameLength = $fileName.Length
                }
            }

            # Copy files locally from source repository
            foreach ($file in $filesToBootstrap) {
                try {
                    # Handle full repository paths vs relative installer paths
                    if ($file.StartsWith('installer/')) {
                        # This is a full repository path - use it directly from workspace root
                        $sourcePath = Join-Path $Global:WorkspaceRoot $file
                    } else {
                        # This is a relative path - join with installer directory
                        $sourcePath = Join-Path $aiInstallerSourcePath $file
                    }

                    $fileName = Split-Path $file -Leaf

                    # Determine target path based on file type and maintain directory structure
                    if ($fileName.EndsWith('.psm1')) {
                        # PowerShell modules go in modules/powershell/ subdirectory
                        $modulesDir = Join-Path $targetDirectory "modules\powershell"
                        if (-not (Test-Path $modulesDir)) {
                            New-Item -ItemType Directory -Path $modulesDir -Force | Out-Null
                        }
                        $targetPath = Join-Path $modulesDir $fileName
                    } elseif ($fileName.EndsWith('.sh')) {
                        # Bash modules and scripts go in modules/bash/ subdirectory or root for main scripts
                        if ($file -like "*modules/bash/*") {
                            $modulesDir = Join-Path $targetDirectory "modules\bash"
                            if (-not (Test-Path $modulesDir)) {
                                New-Item -ItemType Directory -Path $modulesDir -Force | Out-Null
                            }
                            $targetPath = Join-Path $modulesDir $fileName
                        } else {
                            # Main bash script goes in root directory
                            $targetPath = Join-Path $targetDirectory $fileName
                        }
                    } else {
                        # Other files (PowerShell script, config files like file-manifest.config) go directly in target directory
                        $targetPath = Join-Path $targetDirectory $fileName
                    }

                    Write-Host "   Copying: " -ForegroundColor Cyan -NoNewline
                    Write-Host "$($fileName.PadRight($maxFileNameLength))" -ForegroundColor White -NoNewline

                    if (Test-Path $sourcePath) {
                        Copy-Item $sourcePath $targetPath -Force

                        if (Test-Path $targetPath) {
                            $fileSize = (Get-Item $targetPath).Length
                            $statistics["Files Copied"]++
                            $statistics["Total Size"] += $fileSize

                            Write-Host " [OK]" -ForegroundColor "Green"
                        } else {
                            Write-Host " [FAILED]" -ForegroundColor "Red"
                            $statistics["Files Failed"]++
                        }
                    } else {
                        Write-Host " [SOURCE NOT FOUND]" -ForegroundColor "Red"
                        $statistics["Files Failed"]++
                    }
                }
                catch {
                    Write-Host " [ERROR] ($($_.Exception.Message))" -ForegroundColor "Red"
                    $statistics["Files Failed"]++
                }
            }

            # Build the offline payload (aii/) in the bootstrapped installer directory.
            # This keeps the user-profile installer fully self-contained and avoids any network downloads.
            Write-Host ""
            Write-Host "Staging offline payload (aii/) from current repository..." -ForegroundColor Cyan
            Write-Host ""

            $payloadRoot = Join-Path $targetDirectory "aii"
            if (-not (Test-Path $payloadRoot)) {
                New-Item -ItemType Directory -Path $payloadRoot -Force | Out-Null
            }

            $payloadFiles = @()
            foreach ($section in @("MAIN_FILES", "INSTRUCTION_FILES", "PROMPT_FILES", "SKILL_FILES", "UNIVERSAL_FILES")) {
                if ($Global:ManifestConfig.Sections.ContainsKey($section) -and $Global:ManifestConfig.Sections[$section]) {
                    $payloadFiles += $Global:ManifestConfig.Sections[$section]
                }
            }

            $payloadCopied = 0
            $payloadFailed = 0
            $payloadBytes = 0

            foreach ($relPath in $payloadFiles) {
                try {
                    $sourceFile = Join-Path $Global:WorkspaceRoot $relPath
                    $destFile = Join-Path $payloadRoot $relPath
                    $destDir = Split-Path $destFile -Parent

                    if (-not (Test-Path $sourceFile)) {
                        $payloadFailed++
                        continue
                    }

                    if (-not (Test-Path $destDir)) {
                        New-Item -ItemType Directory -Path $destDir -Force | Out-Null
                    }

                    Copy-Item -Path $sourceFile -Destination $destFile -Force
                    $payloadCopied++
                    $payloadBytes += (Get-Item $destFile).Length
                }
                catch {
                    $payloadFailed++
                }
            }

            $statistics["Payload Files Copied"] = $payloadCopied
            $statistics["Payload Files Failed"] = $payloadFailed
            $statistics["Total Size"] += $payloadBytes
        } else {
            # installer directory not found in current repository
            Show-AIInstallerNotFoundError
            exit 1
        }

        $bootstrapVersion = "dev"
        try {
            $sha = (git -C $Global:WorkspaceRoot rev-parse --short HEAD 2>$null).Trim()
            if ($sha) {
                $bootstrapVersion = "dev-$sha"
            }
            $dirty = git -C $Global:WorkspaceRoot status --porcelain 2>$null
            if ($dirty) {
                $bootstrapVersion = "$bootstrapVersion-dirty"
            }
        }
        catch {
        }

        try {
            $versionFilePath = Join-Path $targetDirectory "VERSION"
            Set-Content -Path $versionFilePath -Value $bootstrapVersion -NoNewline -Force
        }
        catch {
        }

        $checksumResult = Write-InstallerChecksum -InstallerRoot $targetDirectory -Version $bootstrapVersion
        if (-not $checksumResult.Valid) {
            $details = @(
                "Checksum error: $($checksumResult.Reason)"
            )
            Show-OperationSummary -OperationName "Bootstrap" -Success $false -Details $details
            return @{ Success = $false; Statistics = $statistics }
        }

        # Prepare details for centralized summary
        $details = @()
        $totalSizeKB = [math]::Round($statistics["Total Size"] / 1KB, 1)

        if ($statistics["Files Copied"] -gt 0) {
            $details += "Installer Files Copied: $($statistics["Files Copied"])"
        }
        if ($statistics.ContainsKey("Payload Files Copied") -and $statistics["Payload Files Copied"] -gt 0) {
            $details += "Payload Files Copied (aii/): $($statistics["Payload Files Copied"])"
        }
        $details += "Total Size (installer + payload): $totalSizeKB KB"
        $details += "Location: $targetDirectory"

        if ($statistics["Files Failed"] -eq 0) {
            # Use centralized success reporting
            Show-OperationSummary -OperationName "Bootstrap" -Success $true -Details $details

            # Show next steps using UI module function
            Show-BootstrapNextStep

            # Show welcome message after successful bootstrap
            Show-SourceBranchWelcome -BranchName $CurrentBranch

            return @{
                Success = $true
                TargetDirectory = $targetDirectory
                Statistics = $statistics
            }
        } else {
            # Use centralized failure reporting
            Show-OperationSummary -OperationName "Bootstrap" -Success $false -Details $details

            return @{
                Success = $false
                Statistics = $statistics
            }
        }
    }
    catch {
        Show-OperationSummary -OperationName "Bootstrap" -Success $false `
            -Details @("Error: $($_.Exception.Message)")
        return @{
            Success = $false
            Error = $_.Exception.Message
        }
    }
}

function Invoke-CleanWorkspace {
    <#
    .SYNOPSIS
    High-level clean workspace operation with complete UI experience

    .PARAMETER WorkspaceRoot
    Root directory of the workspace

    .PARAMETER FromUserProfile
    Indicates if the operation is running from user profile (with -RepoDirectory)

    .PARAMETER CurrentBranch
    Current branch name for summary display

    .PARAMETER BranchType
    Type of branch (source/feature/unknown) for summary display
    #>
    param(
        [string]$WorkspaceRoot,
        [bool]$FromUserProfile = $false,
        [string]$CurrentBranch = "unknown",
        [string]$BranchType = "unknown"
    )

    # CRITICAL: Clean operations are FORBIDDEN on source branches for safety
    # This applies regardless of whether -RepoDirectory is used or not
    $validation = Test-PreInstallation -AllowBootstrapOnSource:$false

    if (-not $validation.OverallValid -and $validation.Git.Reason -like "*SAFETY VIOLATION*") {
        # Use standardized safety violation UI for all cases
        Show-SafetyViolation -BranchName $validation.Git.CurrentBranch -Operation "Clean" -FromUserProfile:$FromUserProfile
        exit 1
    }

    Write-Host " Clean Workspace" -ForegroundColor Cyan
    Write-Separator
    Write-Host ""

    # Use the FileOperations module to properly remove all AI files
    try {
        $result = Remove-AllAIFile -WorkspaceRoot $WorkspaceRoot

        if ($result.Success) {
            # Use Show-OperationSummary for consistent format
            $details = @(
                "Branch Type: $BranchType",
                "Target Branch: $CurrentBranch",
                "Operation Type: Live cleanup",
                "Files Removed: $($result.FilesRemoved)",
                "Directories Cleaned: $($result.DirectoriesCleaned)",
                "Location: $WorkspaceRoot"
            )

            Show-OperationSummary -OperationName "Cleanup" -Success $true -Details $details
            Write-Host ""
        } else {
            Write-Host ""
            Write-Host "Clean Operation Encountered Issues:" -ForegroundColor Cyan
            foreach ($issue in $result.Issues) {
                Write-Host "  - $issue" -ForegroundColor Red
            }
            Write-Host ""
        }

        return $result
    }
    catch {
        Write-Host "Failed to clean workspace: $($_.Exception.Message)" -ForegroundColor Red
        return @{ Success = $false; Issues = @($_.Exception.Message) }
    }
}

function Invoke-InstallInfrastructure {
    <#
    .SYNOPSIS
    High-level install infrastructure operation with complete UI experience

    .PARAMETER WorkspaceRoot
    Root directory of the workspace

    .PARAMETER ManifestConfig
    Manifest configuration object

    .PARAMETER TargetBranch
    Target repository branch name for summary display

    .PARAMETER RequireProviderRepo
    Require that the workspace is a Terraform provider repository (not AI dev repo).
    Set to true when installing via -RepoDirectory to a target repository.

    .PARAMETER LocalSourcePath
    Local directory to copy AI files from instead of the bundled payload.
    #>
    param(
        [string]$WorkspaceRoot,
        [hashtable]$ManifestConfig,
        [string]$TargetBranch = "Unknown",
        [bool]$RequireProviderRepo = $false,
        [string]$LocalSourcePath = ""
    )

    Write-Host " Installing AI Infrastructure" -ForegroundColor Cyan
    Write-Separator
    Write-Host ""

    # Step 1: Clean up deprecated files first (automatic part of installation)
    Write-Host "Checking for deprecated files..." -ForegroundColor Cyan
    $deprecatedFiles = Remove-DeprecatedFile -ManifestConfig $ManifestConfig -WorkspaceRoot $WorkspaceRoot -Quiet $true

    if ($deprecatedFiles.Count -gt 0) {
        Write-Host "  Removed $($deprecatedFiles.Count) deprecated files" -ForegroundColor Green
    } else {
        Write-Host "  No deprecated files found" -ForegroundColor Cyan
    }
    Write-Host ""

    # Step 2: Install/update current files
    Write-Host "Installing current AI infrastructure files..." -ForegroundColor Cyan

    # Use the FileOperations module to actually install files
    try {
        $branchToUse = "main"

        # Build Install-AllAIFile parameters - only include LocalSourcePath if it's not empty
        $installParams = @{
            WorkspaceRoot = $WorkspaceRoot
            ManifestConfig = $ManifestConfig
            RequireProviderRepo = $RequireProviderRepo
            Branch = $branchToUse
        }

        # Only add LocalSourcePath if it was explicitly provided and is not empty
        if ($LocalSourcePath) {
            $installParams['LocalSourcePath'] = $LocalSourcePath
        }

        $result = Install-AllAIFile @installParams

        if ($result.OverallSuccess) {
            # Use the superior completion summary function
            $nextSteps = @()
            if ($result.Skipped -gt 0) {
                $nextSteps += "Review skipped files (already up-to-date)"
            }
            $nextSteps += "Start using GitHub Copilot with your new AI-assisted infrastructure"
            $nextSteps += "Check the .github/instructions/ folder for detailed guidelines"

            # Get branch information for completion summary - use target branch passed in
            $currentBranch = if ($TargetBranch -and $TargetBranch -ne "Unknown") {
                $TargetBranch
            } else {
                "Unknown"
            }

            # Determine branch type based on TARGET branch, not source repository
            $branchType = if ($currentBranch -eq "main") {
                "source"
            } elseif ($currentBranch -eq "Unknown") {
                "Unknown"
            } else {
                "feature"
            }

            # Prepare comprehensive details for installation summary using ordered hashtable
            $details = [ordered]@{}
            $details["Branch Type"] = $branchType
            $details["Target Branch"] = $currentBranch

            # Source/manifest context
            $sourceValue = if ($LocalSourcePath) { $LocalSourcePath } elseif ($result.DebugInfo -and $result.DebugInfo.SourceRoot) { $result.DebugInfo.SourceRoot } else { "" }
            if ($sourceValue) {
                $details["Source"] = $sourceValue
            }

            $manifestValue = $Global:InstallerManifestPath
            if ($manifestValue -and $Global:InstallerManifestHash) {
                $manifestValue = "$manifestValue ($($Global:InstallerManifestHash.Substring(0,8)))"
            }
            if ($manifestValue) {
                $details["Manifest"] = $manifestValue
            }

            if ($Global:InstallerCommandLine) {
                $details["Command"] = $Global:InstallerCommandLine
            }
            if ($result.Successful -gt 0) {
                $details["Files Installed"] = $result.Successful
            }

            # Calculate total size if available in debug info
            if ($result.DebugInfo -and $result.DebugInfo.TotalSizeBytes) {
                $totalSizeKB = [math]::Round($result.DebugInfo.TotalSizeBytes / 1KB, 1)
                $details["Total Size"] = "$totalSizeKB KB"
            }

            # Add failure/skip counts if any
            if ($result.Failed -gt 0) {
                $details["Files Failed"] = $result.Failed
            }
            if ($result.Skipped -gt 0) {
                $details["Files Skipped"] = $result.Skipped
            }

            # Location always goes at the bottom
            $details["Location"] = $WorkspaceRoot

            # Convert hashtable to string array format expected by Show-OperationSummary
            $detailsArray = @()
            foreach ($key in $details.Keys) {
                $detailsArray += "$key`: $($details[$key])"
            }

            Show-OperationSummary -OperationName "Installation" -Success $true -Details $detailsArray

            # Show cleanup reminder after successful installation
            Show-CleanupReminder -WorkspacePath $WorkspaceRoot
        } else {
            Show-InstallationResult -Results $result

            # Show cleanup reminder after successful installation
            if ($result.OverallSuccess) {
                Show-CleanupReminder -WorkspacePath $WorkspaceRoot
            }
        }

        return @{ Success = $result.OverallSuccess; Details = $result }
    }
    catch {
        Write-Host "Installation failed: $($_.Exception.Message)" -ForegroundColor Red
        return @{ Success = $false; Error = $_.Exception.Message }
    }
}

#endregion

#region Export Module Members

Export-ModuleMember -Function @(
    'Copy-LocalAIFile',
    'Install-AllAIFile',
    'Remove-AIFile',
    'Remove-AllAIFile',
    'Remove-DeprecatedFile',
    'Invoke-Bootstrap',
    'Invoke-CleanWorkspace',
    'Invoke-InstallInfrastructure'
)

#endregion
