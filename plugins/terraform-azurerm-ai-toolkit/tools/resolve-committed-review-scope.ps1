[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$RepoRoot,

    [string]$PrRepo = '',

    [string]$PrNumber = '',

    [string]$RevisionRange = '',

    [string[]]$ChangedFile = @(),

    [ValidateSet('Json', 'Text')]
    [string]$OutputFormat = 'Json'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Invoke-GitCommand {
    param(
        [Parameter(Mandatory)]
        [string[]]$Arguments
    )

    $output = & git @Arguments 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "git command failed: git $($Arguments -join ' ')`n$($output -join "`n")"
    }

    return @($output | ForEach-Object { "$_" })
}

function Normalize-RepoRelativePath {
    param(
        [Parameter(Mandatory)]
        [string]$Path,
        [Parameter(Mandatory)]
        [string]$ResolvedRepoRoot
    )

    if ([System.IO.Path]::IsPathRooted($Path)) {
        return [System.IO.Path]::GetRelativePath($ResolvedRepoRoot, [System.IO.Path]::GetFullPath($Path)).Replace('\', '/')
    }

    $normalizedPath = $Path.Replace('\', '/')
    if ($normalizedPath.StartsWith('./')) {
        return $normalizedPath.Substring(2)
    }

    return $normalizedPath
}

function Get-NormalizedChangedFiles {
    param(
        [AllowEmptyCollection()]
        [string[]]$InputFiles = @(),
        [Parameter(Mandatory)]
        [string]$ResolvedRepoRoot
    )

    $normalizedFiles = New-Object 'System.Collections.Generic.List[string]'
    foreach ($file in $InputFiles) {
        if ([string]::IsNullOrWhiteSpace($file)) {
            continue
        }

        foreach ($filePart in ($file -split ',')) {
            $trimmedFilePart = $filePart.Trim()
            if (-not [string]::IsNullOrWhiteSpace($trimmedFilePart)) {
                $normalizedFiles.Add((Normalize-RepoRelativePath -Path $trimmedFilePart -ResolvedRepoRoot $ResolvedRepoRoot))
            }
        }
    }

    return @($normalizedFiles | Select-Object -Unique)
}

$resolvedRepoRoot = [System.IO.Path]::GetFullPath($RepoRoot)
if (-not (Test-Path -LiteralPath $resolvedRepoRoot)) {
    throw "Repo root was not found at $resolvedRepoRoot"
}

$gitRoot = [string](Invoke-GitCommand -Arguments @('-C', $resolvedRepoRoot, 'rev-parse', '--show-toplevel') | Select-Object -First 1)
$resolvedGitRoot = [System.IO.Path]::GetFullPath($gitRoot)
$currentBranch = [string](Invoke-GitCommand -Arguments @('-C', $resolvedGitRoot, 'branch', '--show-current') | Select-Object -First 1)

$normalizedFiles = @(Get-NormalizedChangedFiles -InputFiles $ChangedFile -ResolvedRepoRoot $resolvedGitRoot)
$scopeSource = 'authoritative-pr'
$statusSource = 'authoritative-pr-live'
$addedCount = $null
$modifiedCount = $null
$deletedCount = $null
$unclassifiedCount = 0

if ([string]::IsNullOrWhiteSpace($PrNumber)) {
    throw 'Cannot resolve committed review scope: CLI committed review requires authoritative live PR context or an explicit pr_number. Branch fallback is not supported.'
}

if (-not [string]::IsNullOrWhiteSpace($RevisionRange)) {
    throw 'Cannot resolve committed review scope: revision_range is not supported for the CLI committed-review path. Use review-local for branch or worktree audits.'
}

if ($normalizedFiles.Count -eq 0) {
    throw 'Cannot resolve committed review scope: authoritative live PR scope must supply the changed-file set directly for this run.'
}

$unclassifiedCount = $normalizedFiles.Count

$vendoredFiles = @($normalizedFiles | Where-Object { $_ -like 'vendor/*' })

$result = [ordered]@{
    repoRoot = $resolvedGitRoot
    currentBranch = if ([string]::IsNullOrWhiteSpace($currentBranch)) { 'n/a' } else { $currentBranch }
    scopeSource = $scopeSource
    prRepo = if ([string]::IsNullOrWhiteSpace($PrRepo)) { $null } else { $PrRepo }
    prNumber = if ([string]::IsNullOrWhiteSpace($PrNumber)) { $null } else { $PrNumber }
    revisionRange = $null
    changedFileCount = $normalizedFiles.Count
    vendoredFileCount = $vendoredFiles.Count
    statusSource = $statusSource
    fileCounts = [ordered]@{
        added = $addedCount
        modified = $modifiedCount
        deleted = $deletedCount
        unclassified = $unclassifiedCount
    }
    changedFiles = $normalizedFiles
}

if ($OutputFormat -eq 'Json') {
    ($result | ConvertTo-Json -Depth 6) + "`n" | Write-Output
    return
}

Write-Output ("Repo Root: {0}" -f $result.repoRoot)
Write-Output ("Current Branch: {0}" -f $result.currentBranch)
Write-Output ("Scope Source: {0}" -f $result.scopeSource)
Write-Output ("PR Repo: {0}" -f $(if ($result.prRepo) { $result.prRepo } else { 'n/a' }))
Write-Output ("PR Number: {0}" -f $(if ($result.prNumber) { $result.prNumber } else { 'n/a' }))
Write-Output ("Revision Range: {0}" -f $(if ($result.revisionRange) { $result.revisionRange } else { 'n/a' }))
Write-Output ("Changed File Count: {0}" -f $result.changedFileCount)
Write-Output ("Vendored File Count: {0}" -f $result.vendoredFileCount)
Write-Output ("Status Source: {0}" -f $result.statusSource)
$displayAdded = if ($null -eq $result.fileCounts.added) { 'n/a' } else { $result.fileCounts.added }
$displayModified = if ($null -eq $result.fileCounts.modified) { 'n/a' } else { $result.fileCounts.modified }
$displayDeleted = if ($null -eq $result.fileCounts.deleted) { 'n/a' } else { $result.fileCounts.deleted }
Write-Output ("File Counts: added={0}, modified={1}, deleted={2}, unclassified={3}" -f $displayAdded, $displayModified, $displayDeleted, $result.fileCounts.unclassified)
Write-Output 'Changed Files:'
foreach ($file in $result.changedFiles) {
    Write-Output ("  - {0}" -f $file)
}
