[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$RepoDirectory,

    [Parameter(Mandatory = $true)]
    [ValidatePattern('^[A-Za-z0-9][A-Za-z0-9._-]*$')]
    [string]$CaseId,

    [Parameter(Mandatory = $true)]
    [ValidatePattern('^[A-Za-z0-9][A-Za-z0-9._-]*$')]
    [string]$RunId,

    [Parameter(Mandatory = $true)]
    [ValidateSet('Lite', 'Balanced')]
    [string]$ReviewEffort,

    [string]$ControlBase = 'control-base',

    [string]$HostedBase = 'hosted-base',

    [string]$TestContentBase = 'test-content',

    [string]$CasesDirectory = (Join-Path $PSScriptRoot '../regression/cases'),

    [string]$RegressionDirectory = (Join-Path $PSScriptRoot '../regression'),

    [switch]$Create,

    [ValidateSet('Text', 'Json')]
    [string]$OutputFormat = 'Text'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'Review.Common.psm1') -Force

function Invoke-Git {
    $arguments = @($args)
    $output = @(& $script:gitCommand.Source -C $script:resolvedRepoDirectory @arguments 2>&1)
    if ($LASTEXITCODE -ne 0) {
        throw "git $($arguments -join ' ') failed: $((($output | Out-String).Trim()))"
    }
    return $output
}

$resolvedRepoDirectory = [IO.Path]::GetFullPath($RepoDirectory)
$resolvedCasesDirectory = [IO.Path]::GetFullPath($CasesDirectory)
$gitCommand = Get-Command git -ErrorAction SilentlyContinue
if ($null -eq $gitCommand) { throw 'git was not found on PATH' }
if (-not (Test-Path -LiteralPath $resolvedRepoDirectory -PathType Container) -or -not (Test-Path -LiteralPath (Join-Path $resolvedRepoDirectory '.git'))) {
    throw "RepoDirectory is not a Git repository root: $resolvedRepoDirectory"
}
if (-not [string]::IsNullOrWhiteSpace((Invoke-Git status --porcelain | Out-String))) {
    throw "RepoDirectory must have a clean working tree: $resolvedRepoDirectory"
}

$repository = Get-HostedReviewRepositoryFromRemote -RepoDirectory $resolvedRepoDirectory
$casePaths = @(Get-ChildItem -LiteralPath $resolvedCasesDirectory -Filter 'case.json' -File -Recurse | Where-Object {
        (Get-Content -LiteralPath $_.FullName -Raw | ConvertFrom-Json).id -eq $CaseId
    })
if ($casePaths.Count -ne 1) { throw "CaseId must resolve to exactly one regression case: $CaseId" }
$caseRoot = Split-Path -Parent $casePaths[0].FullName
$case = Get-Content -LiteralPath $casePaths[0].FullName -Raw | ConvertFrom-Json
$contentRoot = [IO.Path]::GetFullPath((Join-Path $caseRoot ([string]$case.contentRoot)))
$caseRootPrefix = $caseRoot.TrimEnd([IO.Path]::DirectorySeparatorChar) + [IO.Path]::DirectorySeparatorChar
if (-not $contentRoot.StartsWith($caseRootPrefix, [StringComparison]::OrdinalIgnoreCase)) {
    throw "Case contentRoot escapes its case directory: $contentRoot"
}
$contentFiles = @(Get-ChildItem -LiteralPath $contentRoot -File -Recurse | Sort-Object FullName)
if ($contentFiles.Count -eq 0) { throw "Case contentRoot is empty: $contentRoot" }
$contentPaths = @($contentFiles | ForEach-Object {
        $relativePath = [IO.Path]::GetRelativePath($contentRoot, $_.FullName).Replace('\', '/')
        if ($relativePath -match '^\.github(?:/|$)') { throw "Case content must not modify review customization or workflows: $relativePath" }
        $relativePath
    })

$sourceBranch = "test-case/$CaseId"
$null = Invoke-Git check-ref-format "refs/heads/$sourceBranch"
$tempRoot = Join-Path ([IO.Path]::GetTempPath()) ("hosted-test-case-$([guid]::NewGuid().ToString('N'))")
$worktree = Join-Path $tempRoot 'source'
New-Item -ItemType Directory -Path $tempRoot | Out-Null
try {
    $null = Invoke-Git worktree add --detach $worktree $TestContentBase
    foreach ($contentFile in $contentFiles) {
        $relativePath = [IO.Path]::GetRelativePath($contentRoot, $contentFile.FullName).Replace('\', '/')
        $destination = Join-Path $worktree ($relativePath.Replace('/', [IO.Path]::DirectorySeparatorChar))
        $destinationDirectory = Split-Path -Parent $destination
        if (-not (Test-Path -LiteralPath $destinationDirectory)) { New-Item -ItemType Directory -Path $destinationDirectory -Force | Out-Null }
        Copy-Item -LiteralPath $contentFile.FullName -Destination $destination -Force
    }
    $null = & $gitCommand.Source -C $worktree add -f -- @($contentPaths)
    if ($LASTEXITCODE -ne 0) { throw 'Failed to stage test-case content' }
    $stagedFiles = @(& $gitCommand.Source -C $worktree diff --cached --name-only | Sort-Object)
    if (($stagedFiles -join "`n") -ne (($contentPaths | Sort-Object) -join "`n")) {
        throw 'Every test-case content file must produce exactly one source PR change'
    }
    $null = & $gitCommand.Source -C $worktree commit -m "Publish $CaseId test content"
    if ($LASTEXITCODE -ne 0) { throw 'Failed to commit test-case source content' }
    $sourceCommit = (& $gitCommand.Source -C $worktree rev-parse HEAD).Trim()

    $owner = $repository.Split('/')[0]
    $existingSourcePullRequests = @(Invoke-HostedReviewGitHubApi -Endpoint "repos/$repository/pulls?state=open&base=$TestContentBase&head=$owner`:$sourceBranch")
    if ($existingSourcePullRequests.Count -gt 1) { throw "Multiple open source pull requests use branch $sourceBranch" }
    $sourcePullRequest = if ($existingSourcePullRequests.Count -eq 1) { $existingSourcePullRequests[0] } else { $null }
    $mirrorResult = $null
    if ($Create) {
        $null = Assert-HostedReviewWritableFork -RepoDirectory $resolvedRepoDirectory
        if ($null -eq $sourcePullRequest) {
            if (@(Invoke-Git ls-remote --heads origin $sourceBranch).Count -gt 0) { throw "Source branch exists without an open pull request: $sourceBranch" }
            $null = Invoke-Git push origin "$sourceCommit`:refs/heads/$sourceBranch"
            $sourcePullRequest = Invoke-HostedReviewGitHubApi -Endpoint "repos/$repository/pulls" -Method POST -Fields @{
                title = "Publish $CaseId test content"
                body = "Canonical synthetic test content for paired Hosted review.`n`nDo not merge."
                head = $sourceBranch
                base = $TestContentBase
            }
        }
        else {
            $null = Invoke-Git push "--force-with-lease=refs/heads/$sourceBranch`:$($sourcePullRequest.head.sha)" origin "$sourceCommit`:refs/heads/$sourceBranch"
            $sourcePullRequest = Invoke-HostedReviewGitHubApi -Endpoint "repos/$repository/pulls/$($sourcePullRequest.number)"
        }

        $provenance = [pscustomobject][ordered]@{ type = 'synthetic_case'; caseId = $CaseId }
        $pairOutput = @(& (Join-Path $PSScriptRoot 'New-ReviewPair.ps1') -RepoDirectory $resolvedRepoDirectory -SourcePullRequest ([int]$sourcePullRequest.number) -RunId $RunId -ReviewEffort $ReviewEffort -ControlBase $ControlBase -HostedBase $HostedBase -TestContentBase $TestContentBase -RegressionDirectory $RegressionDirectory -SourceProvenance $provenance -Create -OutputFormat Json 2>&1)
        if ($LASTEXITCODE -ne 0) { throw "Mirror pair creation failed: $((($pairOutput | Out-String).Trim()))" }
        $mirrorResult = ($pairOutput -join [Environment]::NewLine) | ConvertFrom-Json
    }

    $result = [ordered]@{
        success = $true
        mode = if ($Create) { [string]$mirrorResult.mode } else { 'validate' }
        repository = $repository
        caseId = $CaseId
        sourceBranch = $sourceBranch
        sourcePullRequest = if ($null -eq $sourcePullRequest) { $null } else { [int]$sourcePullRequest.number }
        changedFiles = $contentPaths
        controlPullRequest = if ($null -eq $mirrorResult) { $null } else { [int]$mirrorResult.controlPullRequest }
        hostedPullRequest = if ($null -eq $mirrorResult) { $null } else { [int]$mirrorResult.hostedPullRequest }
        pairPath = if ($null -eq $mirrorResult) { $null } else { [string]$mirrorResult.pairPath }
    }
}
finally {
    if (Test-Path -LiteralPath $worktree) { $null = & $gitCommand.Source -C $resolvedRepoDirectory worktree remove --force $worktree 2>$null }
    Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
}

if ($OutputFormat -eq 'Json') {
    $result | ConvertTo-Json -Depth 8
}
else {
    Write-Output 'Hosted review test case'
    Write-Output "  Mode          : $($result.mode.ToUpperInvariant())"
    Write-Output "  Case          : $CaseId"
    Write-Output "  Source branch : $sourceBranch"
    Write-Output "  Source PR     : $($result.sourcePullRequest)"
    if ($Create) {
        Write-Output "  Control PR    : #$($result.controlPullRequest)"
        Write-Output "  Hosted PR     : #$($result.hostedPullRequest)"
        Write-Output "  Pair record   : $($result.pairPath)"
    }
}
