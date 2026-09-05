[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$RepoDirectory,

    [string]$ManifestPath = (Join-Path $PSScriptRoot 'package-manifest.json'),

    [switch]$Install,

    [switch]$Force,

    [ValidateSet('Text', 'Json')]
    [string]$OutputFormat = 'Text'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$hostedRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$resolvedManifestPath = [System.IO.Path]::GetFullPath($ManifestPath)
$resolvedRepoDirectory = [System.IO.Path]::GetFullPath($RepoDirectory)
$mode = if ($Install) { 'install' } else { 'dry-run' }
$issues = New-Object 'System.Collections.Generic.List[string]'
$operations = New-Object 'System.Collections.Generic.List[object]'

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
    Write-Output 'Hosted Toolkit deployment plan'
    Write-Output ("  Status       : {0}" -f $(if ($result.success) { 'READY' } else { 'BLOCKED' }))
    Write-Output ("  Mode         : {0}" -f $mode.ToUpperInvariant())
    Write-Output ("  Repository   : {0}" -f $resolvedRepoDirectory)
    Write-Output ("  Manifest     : {0}" -f $resolvedManifestPath)
    Write-Output ("  Commit       : {0}" -f $(if ($commit) { $commit } else { 'unavailable' }))
    Write-Output ''

    foreach ($operation in $operations) {
        Write-Output ("  [{0}] {1}" -f $operation.status.ToUpperInvariant(), $operation.targetPath)
    }

    if ($issues.Count -gt 0) {
        Write-Output ''
        foreach ($issue in $issues) {
            Write-Output ("  [BLOCKED] {0}" -f $issue)
        }
    }
}

if ($issues.Count -gt 0) {
    exit 1
}
