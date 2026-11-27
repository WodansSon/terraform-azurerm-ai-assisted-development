<#
.SYNOPSIS
Plans or installs the Hosted Toolkit payload into a target repository.

.DESCRIPTION
Validates the Hosted deployment manifest, compares packaged files with a target repository, and reports the planned changes. Installation occurs only when Install is supplied, and protected collisions require Force.

.PARAMETER RepoDirectory
Specifies the required Git repository root that receives the Hosted Toolkit payload.

.PARAMETER ManifestPath
Specifies the Hosted package manifest. Defaults to `hosted_copilot/tools/config/package-manifest.json`.

.PARAMETER Install
Applies the validated deployment plan. When omitted, the command performs a read-only dry run.

.PARAMETER Force
Approves replacement of unowned collisions, modified installed files, or invalid installed-state records.

.PARAMETER OutputFormat
Selects human-readable text or machine-readable JSON output.

.PARAMETER Help
Displays curated Hosted command help and exits without deployment work.

.PARAMETER Detailed
Displays curated Hosted command help and exits without deployment work.

.EXAMPLE
pwsh -NoProfile -File ./hosted_copilot/tools/Install-HostedRules.ps1 -RepoDirectory C:\github\terraform-provider-azurerm
Plans deployment into the target repository without writing files.

.EXAMPLE
pwsh -NoProfile -File ./hosted_copilot/tools/Install-HostedRules.ps1 -RepoDirectory C:\github\terraform-provider-azurerm -Install
Installs the validated Hosted Toolkit payload into the target repository.

.EXAMPLE
pwsh -NoProfile -File ./hosted_copilot/tools/Install-HostedRules.ps1 -RepoDirectory C:\github\terraform-provider-azurerm -Install -Force
Installs while explicitly approving protected replacements reported by the deployment plan.

.NOTES
Dry run is the default. Installation validates repository boundaries, rejects symbolic-link and junction traversal, and verifies installed file hashes.

.LINK
https://github.com/WodansSon/terraform-azurerm-ai-assisted-development/blob/main/hosted_copilot/tools/README.md
#>
[CmdletBinding(DefaultParameterSetName = 'DryRun')]
param(
    [Parameter(Mandatory, ParameterSetName = 'DryRun')]
    [Parameter(Mandatory, ParameterSetName = 'Install')]
    [string]$RepoDirectory,

    [Parameter(ParameterSetName = 'DryRun')]
    [Parameter(ParameterSetName = 'Install')]
    [string]$ManifestPath = (Join-Path $PSScriptRoot 'config/package-manifest.json'),

    [Parameter(Mandatory, ParameterSetName = 'Install')]
    [switch]$Install,

    [Parameter(ParameterSetName = 'DryRun')]
    [Parameter(ParameterSetName = 'Install')]
    [switch]$Force,

    [Parameter(ParameterSetName = 'DryRun')]
    [Parameter(ParameterSetName = 'Install')]
    [ValidateSet('Text', 'Json')]
    [string]$OutputFormat = 'Text',

    [Parameter(Mandatory, ParameterSetName = 'Help')]
    [Alias('h')]
    [switch]$Help,

    [Parameter(Mandatory, ParameterSetName = 'Detailed')]
    [switch]$Detailed
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$commandHelpModulePath = Join-Path $PSScriptRoot 'modules/shared/HostedCommandHelp.psm1'
Import-Module -Name $commandHelpModulePath -Force
if ($Help -or $Detailed) {
    $helpParameterGroups = [ordered]@{
        'Deployment Options' = @('Install', 'Force')
        'Target And Package' = @('RepoDirectory', 'ManifestPath')
        'Output' = @('OutputFormat')
    }
    Show-HostedCommandHelp -ScriptPath $PSCommandPath -DisplayName 'Hosted Rules Installation Help' -ParameterGroups $helpParameterGroups
    return
}

$validationOutputModulePath = Join-Path $PSScriptRoot '../../tools/ValidationOutput.psm1'
Import-Module -Name $validationOutputModulePath -Force

$hostedRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$resolvedManifestPath = [System.IO.Path]::GetFullPath($ManifestPath)
$resolvedRepoDirectory = [System.IO.Path]::GetFullPath($RepoDirectory)
$mode = if ($Install) { 'install' } else { 'dry-run' }
$issues = New-Object 'System.Collections.Generic.List[string]'
$operations = New-Object 'System.Collections.Generic.List[object]'

if ($OutputFormat -eq 'Text') {
    Write-ValidationSectionHeader -Title 'Hosted Rules deployment'
    Write-Host (Format-ValidationStatusLine -Status 'running' -Name 'manifest-validation' -Detail 'Validating the deployment manifest and target repository boundaries')
}

function Test-PathWithinRoot {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,

        [Parameter(Mandatory = $true)]
        [string]$Root
    )

    $rootPrefix = $Root.TrimEnd([System.IO.Path]::DirectorySeparatorChar, [System.IO.Path]::AltDirectorySeparatorChar) + [System.IO.Path]::DirectorySeparatorChar
    return $Path.StartsWith($rootPrefix, [System.StringComparison]::OrdinalIgnoreCase)
}

function Assert-PathHasNoReparsePoints {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,

        [Parameter(Mandatory = $true)]
        [string]$Root
    )

    $relativePath = [System.IO.Path]::GetRelativePath($Root, $Path)
    $currentPath = $Root
    foreach ($segment in $relativePath.Split([System.IO.Path]::DirectorySeparatorChar, [System.IO.Path]::AltDirectorySeparatorChar)) {
        if ([string]::IsNullOrWhiteSpace($segment)) {
            continue
        }
        $currentPath = Join-Path $currentPath $segment
        if (-not (Test-Path -LiteralPath $currentPath)) {
            continue
        }
        $item = Get-Item -LiteralPath $currentPath -Force
        if (($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
            throw "Path traverses a symbolic link or junction: $currentPath"
        }
    }
}

function Get-Sha256Hash {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function Get-RelativeManifestPath {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    if ([string]::IsNullOrWhiteSpace($Path) -or [System.IO.Path]::IsPathRooted($Path)) {
        throw "Manifest path must be a non-empty relative path: $Path"
    }

    return $Path.Replace('/', [System.IO.Path]::DirectorySeparatorChar)
}

if (-not (Test-Path -LiteralPath $resolvedRepoDirectory -PathType Container)) {
    throw "RepoDirectory was not found: $resolvedRepoDirectory"
}

if (-not (Test-Path -LiteralPath (Join-Path $resolvedRepoDirectory '.git'))) {
    throw "RepoDirectory is not a Git repository root: $resolvedRepoDirectory"
}

if (-not (Test-Path -LiteralPath $resolvedManifestPath -PathType Leaf)) {
    throw "ManifestPath was not found: $resolvedManifestPath"
}

$manifestConfig = Get-Content -LiteralPath $resolvedManifestPath -Raw | ConvertFrom-Json
if ($manifestConfig.schemaVersion -ne 1) {
    throw "Unsupported manifest schemaVersion: $($manifestConfig.schemaVersion)"
}
if ([string]::IsNullOrWhiteSpace([string]$manifestConfig.packageIdentity)) {
    throw 'Manifest packageIdentity must not be empty'
}
if (@($manifestConfig.files).Count -eq 0) {
    throw 'Manifest files must not be empty'
}

$installedStateRelativePath = Get-RelativeManifestPath -Path ([string]$manifestConfig.installedStatePath)
$installedStatePath = [System.IO.Path]::GetFullPath((Join-Path $resolvedRepoDirectory $installedStateRelativePath))
if (-not (Test-PathWithinRoot -Path $installedStatePath -Root $resolvedRepoDirectory)) {
    throw "installedStatePath escapes RepoDirectory: $($manifestConfig.installedStatePath)"
}
Assert-PathHasNoReparsePoints -Path $installedStatePath -Root $resolvedRepoDirectory

$installedState = $null
$installedFiles = @{}
$stateCollision = $false
if (Test-Path -LiteralPath $installedStatePath -PathType Leaf) {
    try {
        $installedState = Get-Content -LiteralPath $installedStatePath -Raw | ConvertFrom-Json
        if ($installedState.packageIdentity -ne $manifestConfig.packageIdentity) {
            $stateCollision = $true
        }
        else {
            foreach ($file in @($installedState.files)) {
                $installedFiles[[string]$file.targetPath] = [string]$file.hash
            }
        }
    }
    catch {
        $stateCollision = $true
    }
}

$seenPaths = @{}
if ($OutputFormat -eq 'Text') {
    Write-Host (Format-ValidationStatusLine -Status 'running' -Name 'deployment-planning' -Detail 'Comparing packaged files with the target repository')
}
foreach ($file in @($manifestConfig.files)) {
    if ($file -isnot [string]) {
        throw 'Manifest files entries must be relative path strings'
    }
    $relativePath = ([string]$file).Replace('\', '/')
    if ($seenPaths.ContainsKey($relativePath)) {
        throw "Manifest contains duplicate path: $relativePath"
    }
    $seenPaths[$relativePath] = $true

    $resolvedRelativePath = Get-RelativeManifestPath -Path $relativePath
    $sourcePath = [System.IO.Path]::GetFullPath((Join-Path $hostedRoot $resolvedRelativePath))
    $targetPath = [System.IO.Path]::GetFullPath((Join-Path $resolvedRepoDirectory $resolvedRelativePath))

    if (-not (Test-PathWithinRoot -Path $sourcePath -Root $hostedRoot)) {
        throw "Manifest path escapes hosted_copilot: $relativePath"
    }
    if (-not (Test-PathWithinRoot -Path $targetPath -Root $resolvedRepoDirectory)) {
        throw "Manifest path escapes RepoDirectory: $relativePath"
    }
    Assert-PathHasNoReparsePoints -Path $sourcePath -Root $hostedRoot
    Assert-PathHasNoReparsePoints -Path $targetPath -Root $resolvedRepoDirectory
    if (-not (Test-Path -LiteralPath $sourcePath -PathType Leaf)) {
        throw "Manifest source file was not found: $relativePath"
    }

    $sourceHash = Get-Sha256Hash -Path $sourcePath

    $targetHash = $null
    $status = 'addition'
    $requiresForce = $false
    if (Test-Path -LiteralPath $targetPath -PathType Leaf) {
        $targetHash = Get-Sha256Hash -Path $targetPath
        if ($targetHash -eq $sourceHash) {
            $status = 'unchanged'
        }
        elseif ($installedFiles.ContainsKey($relativePath)) {
            if ($targetHash -eq $installedFiles[$relativePath]) {
                $status = 'update'
            }
            else {
                $status = 'owned-modification'
                $requiresForce = $true
            }
        }
        else {
            $status = 'unowned-collision'
            $requiresForce = $true
        }
    }

    if ($requiresForce -and -not $Force) {
        $issues.Add("$status requires explicit -Force approval: $relativePath")
    }

    $operations.Add([pscustomobject]@{
        sourcePath = $relativePath
        targetPath = $relativePath
        hash = $sourceHash
        targetHash = $targetHash
        status = $status
        requiresForce = $requiresForce
    })
}

if ($stateCollision -and -not $Force) {
    $issues.Add("Replacing an invalid or foreign installed-state record requires explicit -Force approval: $installedStatePath")
}

$commit = $null
$gitCommand = Get-Command git -ErrorAction SilentlyContinue
if ($null -ne $gitCommand) {
    $commitOutput = @(& $gitCommand.Source -C $hostedRoot rev-parse HEAD 2>$null)
    if ($LASTEXITCODE -eq 0 -and $commitOutput.Count -gt 0) {
        $commit = ([string]$commitOutput[0]).Trim().ToLowerInvariant()
    }
    $global:LASTEXITCODE = 0
}

if ($Install -and $issues.Count -eq 0) {
    if ($OutputFormat -eq 'Text') {
        Write-Host (Format-ValidationStatusLine -Status 'running' -Name 'deployment-apply' -Detail 'Installing planned files and verifying hashes')
    }
    foreach ($operation in $operations) {
        if ($operation.status -eq 'unchanged') {
            continue
        }

        $sourcePath = [System.IO.Path]::GetFullPath((Join-Path $hostedRoot (Get-RelativeManifestPath -Path $operation.sourcePath)))
        $targetPath = [System.IO.Path]::GetFullPath((Join-Path $resolvedRepoDirectory (Get-RelativeManifestPath -Path $operation.targetPath)))
        $targetDirectory = Split-Path -Parent $targetPath
        if (-not (Test-Path -LiteralPath $targetDirectory)) {
            $null = New-Item -ItemType Directory -Path $targetDirectory -Force
        }
        Assert-PathHasNoReparsePoints -Path $sourcePath -Root $hostedRoot
        Assert-PathHasNoReparsePoints -Path $targetPath -Root $resolvedRepoDirectory

        Copy-Item -LiteralPath $sourcePath -Destination $targetPath -Force
        $installedHash = Get-Sha256Hash -Path $targetPath
        if ($installedHash -ne $operation.hash) {
            throw "Installed file hash verification failed: $($operation.targetPath)"
        }
    }

    $stateDirectory = Split-Path -Parent $installedStatePath
    if (-not (Test-Path -LiteralPath $stateDirectory)) {
        $null = New-Item -ItemType Directory -Path $stateDirectory -Force
    }
    Assert-PathHasNoReparsePoints -Path $installedStatePath -Root $resolvedRepoDirectory

    $stateConfig = [ordered]@{
        schemaVersion = 1
        packageIdentity = [string]$manifestConfig.packageIdentity
        commit = $commit
        manifestHash = Get-Sha256Hash -Path $resolvedManifestPath
        files = @($operations | ForEach-Object {
            [ordered]@{
                targetPath = $_.targetPath
                hash = $_.hash
            }
        })
    }
    $stateConfig | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $installedStatePath -Encoding utf8
}

$result = [ordered]@{
    success = ($issues.Count -eq 0)
    mode = $mode
    repoDirectory = $resolvedRepoDirectory
    manifestPath = $resolvedManifestPath
    packageIdentity = [string]$manifestConfig.packageIdentity
    installedStatePath = $installedStatePath
    commit = $commit
    operations = @($operations.ToArray())
    issueCount = $issues.Count
    issues = @($issues.ToArray())
}

if ($OutputFormat -eq 'Json') {
    $result | ConvertTo-Json -Depth 8
}
else {
    Write-ValidationSectionHeader -Title 'Hosted Rules deployment summary'
    Write-ValidationSummary -Fields ([ordered]@{
        Status = $(if ($result.success) { 'PASSED' } else { 'FAILED' })
        Mode = $mode.ToUpperInvariant()
        Operations = $operations.Count
        'Issue Count' = $issues.Count
        Repository = $resolvedRepoDirectory
        Manifest = $resolvedManifestPath
        Commit = $(if ($commit) { $commit } else { 'unavailable' })
    })
    Write-ValidationSectionHeader -Title 'Deployment operations'
    $operationNameWidth = Get-ValidationNameWidth -Names @($operations.targetPath) -MinimumWidth 30
    foreach ($operation in $operations) {
        Write-Output (Format-ValidationStatusLine -Status $operation.status -Name $operation.targetPath -Detail $(if ($operation.requiresForce) { 'REQUIRES FORCE' } else { 'READY' }) -NameWidth $operationNameWidth)
    }
    if ($issues.Count -gt 0) {
        Write-ValidationSectionHeader -Title 'Failures'
        foreach ($issue in $issues) {
            Write-Output "  - $issue"
        }
    }
    Complete-ValidationTextOutput
}

if ($issues.Count -gt 0) {
    exit 1
}
