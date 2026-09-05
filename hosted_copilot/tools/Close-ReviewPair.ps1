[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$RepoDirectory,

    [Parameter(Mandatory = $true)]
    [string]$PairPath,

    [switch]$Close,

    [switch]$AllowMissingCapture,

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
$resolvedPairPath = [IO.Path]::GetFullPath($PairPath)
$gitCommand = Get-Command git -ErrorAction SilentlyContinue
if ($null -eq $gitCommand) { throw 'git was not found on PATH' }
if (-not (Test-Path -LiteralPath $resolvedRepoDirectory -PathType Container) -or -not (Test-Path -LiteralPath (Join-Path $resolvedRepoDirectory '.git'))) {
    throw "RepoDirectory is not a Git repository root: $resolvedRepoDirectory"
}
if (-not (Test-Path -LiteralPath $resolvedPairPath -PathType Leaf)) {
    throw "PairPath was not found: $resolvedPairPath"
}
if (-not [string]::IsNullOrWhiteSpace((Invoke-Git status --porcelain | Out-String))) {
    throw "RepoDirectory must have a clean working tree: $resolvedRepoDirectory"
}

$pair = Get-Content -LiteralPath $resolvedPairPath -Raw | ConvertFrom-Json
if ($pair.schemaVersion -notin @(1, 2)) { throw "Unsupported pair record schemaVersion: $($pair.schemaVersion)" }
$repository = [string]$pair.repository
$originRepository = Get-HostedReviewRepositoryFromRemote -RepoDirectory $resolvedRepoDirectory
if (-not $repository.Equals($originRepository, [StringComparison]::OrdinalIgnoreCase)) {
    throw "Pair record repository $repository does not match RepoDirectory origin $originRepository"
}
if ($Close) {
    $target = Assert-HostedReviewWritableFork -RepoDirectory $resolvedRepoDirectory
    if (-not $repository.Equals([string]$target.repository, [StringComparison]::OrdinalIgnoreCase)) {
        throw "Writable fork guard resolved $($target.repository), not pair repository $repository"
    }
}
$controlHead = [string]$pair.control.head
$hostedHead = [string]$pair.hosted.head
$controlBase = [string]$pair.control.base
$hostedBase = [string]$pair.hosted.base
if ($controlHead -eq $controlBase -or $controlHead -eq $hostedBase -or $hostedHead -eq $controlBase -or $hostedHead -eq $hostedBase) {
    throw 'Pair record attempts to delete a persistent base branch'
}
if ($controlHead -eq $hostedHead) { throw 'Control and Hosted head branches must differ' }

$capturePath = Join-Path (Split-Path -Parent $resolvedPairPath) "$($pair.runId).json"
if (-not $AllowMissingCapture -and -not (Test-Path -LiteralPath $capturePath -PathType Leaf)) {
    throw "Capture evidence is missing; run Capture-ReviewPair.ps1 -PairPath first: $capturePath"
}

$profiles = @(
    [pscustomobject]@{ name = 'control'; config = $pair.control },
    [pscustomobject]@{ name = 'hosted'; config = $pair.hosted }
)
foreach ($profile in $profiles) {
    $pullRequest = Invoke-HostedReviewGitHubApi -Endpoint "repos/$repository/pulls/$($profile.config.pullRequest)"
    if ($pullRequest.head.ref -ne $profile.config.head -or $pullRequest.base.ref -ne $profile.config.base) {
        throw "$($profile.name) pull request topology no longer matches the pair record"
    }
}

if ($Close) {
    foreach ($profile in $profiles) {
        $pullRequest = Invoke-HostedReviewGitHubApi -Endpoint "repos/$repository/pulls/$($profile.config.pullRequest)"
        if ($pullRequest.state -ne 'closed') {
            $null = Invoke-HostedReviewGitHubApi -Endpoint "repos/$repository/pulls/$($profile.config.pullRequest)" -Method PATCH -Fields @{ state = 'closed' }
        }
    }
    $remoteRefs = @(Invoke-Git ls-remote --heads origin $controlHead $hostedHead)
    foreach ($head in @($controlHead, $hostedHead)) {
        if (@($remoteRefs | Where-Object { $_ -match "refs/heads/$([regex]::Escape($head))$" }).Count -gt 0) {
            $null = Invoke-Git push origin --delete $head
        }
    }
    $localBranches = @(Invoke-Git for-each-ref --format='%(refname:short)' refs/heads)
    foreach ($head in @($controlHead, $hostedHead)) {
        if ($head -in $localBranches) {
            $null = Invoke-Git branch -D $head
        }
    }
}

$deletedHeads = @()
if ($Close) {
    $deletedHeads = @($controlHead, $hostedHead)
}
$result = [ordered]@{
    success = $true
    mode = if ($Close) { 'close' } else { 'validate' }
    repository = $repository
    caseId = [string]$pair.caseId
    runId = [string]$pair.runId
    capturePath = [IO.Path]::GetFullPath($capturePath)
    capturePresent = Test-Path -LiteralPath $capturePath -PathType Leaf
    controlPullRequest = [int]$pair.control.pullRequest
    hostedPullRequest = [int]$pair.hosted.pullRequest
    deletedHeads = [object[]]$deletedHeads
    protectedBases = @($controlBase, $hostedBase)
}

if ($OutputFormat -eq 'Json') {
    $result | ConvertTo-Json -Depth 6
}
else {
    Write-Output 'Hosted review pair cleanup'
    Write-Output "  Mode          : $($result.mode.ToUpperInvariant())"
    Write-Output "  Case          : $($result.caseId)"
    Write-Output "  Run           : $($result.runId)"
    Write-Output "  Capture       : $($result.capturePresent)"
    Write-Output "  Control PR    : #$($result.controlPullRequest)"
    Write-Output "  Hosted PR     : #$($result.hostedPullRequest)"
    if ($Close) {
        Write-Output "  Deleted heads : $($result.deletedHeads -join ', ')"
    }
}
