[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$RepoDirectory,

    [Parameter(Mandatory = $true)]
    [ValidateRange(1, [int]::MaxValue)]
    [int]$PullRequest,

    [ValidatePattern('^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$')]
    [string]$SourceRepository,

    [Parameter(Mandatory = $true)]
    [ValidatePattern('^[A-Za-z0-9][A-Za-z0-9._-]*$')]
    [string]$RunId,

    [Parameter(Mandatory = $true)]
    [ValidateSet('Lite', 'Medium')]
    [string]$ReviewEffort,

    [string]$ControlBase = 'control-base',

    [string]$HostedBase = 'hosted-base',

    [string]$TestContentBase = 'test-content',

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

function Get-GitSingleValue {
    $output = @(Invoke-Git @args)
    if ($output.Count -ne 1) { throw "Expected one line from git $($args -join ' '); found $($output.Count)" }
    return ([string]$output[0]).Trim()
}

$resolvedRepoDirectory = [IO.Path]::GetFullPath($RepoDirectory)
$gitCommand = Get-Command git -ErrorAction SilentlyContinue
if ($null -eq $gitCommand) { throw 'git was not found on PATH' }
if (-not (Test-Path -LiteralPath $resolvedRepoDirectory -PathType Container) -or -not (Test-Path -LiteralPath (Join-Path $resolvedRepoDirectory '.git'))) {
    throw "RepoDirectory is not a Git repository root: $resolvedRepoDirectory"
}
if (-not [string]::IsNullOrWhiteSpace((Invoke-Git status --porcelain | Out-String))) {
    throw "RepoDirectory must have a clean working tree: $resolvedRepoDirectory"
}

$destinationRepository = Get-HostedReviewRepositoryFromRemote -RepoDirectory $resolvedRepoDirectory
$destinationMetadata = Invoke-HostedReviewGitHubApi -Endpoint "repos/$destinationRepository"
if ([string]::IsNullOrWhiteSpace($SourceRepository)) {
    $SourceRepository = if ([bool]$destinationMetadata.fork -and $null -ne $destinationMetadata.parent) {
        [string]$destinationMetadata.parent.full_name
    }
    else {
        [string]$destinationMetadata.full_name
    }
}

$canonicalRepository = 'hashicorp/terraform-provider-azurerm'
$sourceMetadata = Invoke-HostedReviewGitHubApi -Endpoint "repos/$SourceRepository"
$sourceUpstream = if ([string]$sourceMetadata.full_name -eq $canonicalRepository) {
    $canonicalRepository
}
elseif ($null -ne $sourceMetadata.source) {
    [string]$sourceMetadata.source.full_name
}
elseif ($null -ne $sourceMetadata.parent) {
    [string]$sourceMetadata.parent.full_name
}
else {
    $null
}
if (-not $canonicalRepository.Equals($sourceUpstream, [StringComparison]::OrdinalIgnoreCase)) {
    throw "SourceRepository must be HashiCorp's AzureRM provider or one of its forks: $SourceRepository"
}

$upstreamPullRequest = Invoke-HostedReviewGitHubApi -Endpoint "repos/$SourceRepository/pulls/$PullRequest"
$sourceFiles = New-Object 'System.Collections.Generic.List[object]'
$pageCount = [Math]::Max(1, [Math]::Ceiling([double]$upstreamPullRequest.changed_files / 100))
for ($page = 1; $page -le $pageCount; $page++) {
    foreach ($file in @(Invoke-HostedReviewGitHubApi -Endpoint "repos/$SourceRepository/pulls/$PullRequest/files?per_page=100&page=$page")) {
        $sourceFiles.Add($file)
    }
}
if ($sourceFiles.Count -ne [int]$upstreamPullRequest.changed_files) {
    throw "Upstream pull request file capture is incomplete; expected $($upstreamPullRequest.changed_files), found $($sourceFiles.Count)"
}
$forbiddenFiles = @($sourceFiles | Where-Object {
        ([string]$_.filename).Replace('\', '/') -match '^\.github(?:/|$)' -or
        ($null -ne $_.PSObject.Properties['previous_filename'] -and ([string]$_.previous_filename).Replace('\', '/') -match '^\.github(?:/|$)')
    })
if ($forbiddenFiles.Count -gt 0) {
    throw 'Imported pull request must not modify review customization or workflows under .github/'
}

$sourceBranch = "imported-pr/$($SourceRepository -replace '[^A-Za-z0-9._-]+', '-')-$PullRequest"
$null = Invoke-Git check-ref-format "refs/heads/$sourceBranch"
$testContentBaseCommit = Get-GitSingleValue rev-parse $TestContentBase
$tempRoot = Join-Path ([IO.Path]::GetTempPath()) ("hosted-pr-import-$([guid]::NewGuid().ToString('N'))")
$worktree = Join-Path $tempRoot 'source'
$patchPath = Join-Path $tempRoot 'upstream.diff'
New-Item -ItemType Directory -Path $tempRoot | Out-Null
try {
    $diff = Invoke-HostedReviewGitHubApi -Endpoint "repos/$SourceRepository/pulls/$PullRequest" -Accept 'application/vnd.github.v3.diff' -Raw
    if ([string]::IsNullOrWhiteSpace($diff)) { throw "Upstream pull request returned an empty diff: $($upstreamPullRequest.html_url)" }
    Set-Content -LiteralPath $patchPath -Value ($diff + "`n") -Encoding utf8NoBOM -NoNewline
    $null = Invoke-Git worktree add --detach $worktree $TestContentBase
    $applyOutput = @(& $gitCommand.Source -C $worktree apply --index --binary $patchPath 2>&1)
    if ($LASTEXITCODE -ne 0) { throw "Upstream pull request does not apply cleanly to $TestContentBase`: $((($applyOutput | Out-String).Trim()))" }
    $null = & $gitCommand.Source -C $worktree commit -m "Import $SourceRepository pull request #$PullRequest"
    if ($LASTEXITCODE -ne 0) { throw 'Failed to commit imported source change' }
    $sourceCommit = (& $gitCommand.Source -C $worktree rev-parse HEAD).Trim()

    $owner = $destinationRepository.Split('/')[0]
    $existingSourcePullRequests = @(Invoke-HostedReviewGitHubApi -Endpoint "repos/$destinationRepository/pulls?state=open&base=$TestContentBase&head=$owner`:$sourceBranch")
    if ($existingSourcePullRequests.Count -gt 1) { throw "Multiple open source pull requests use branch $sourceBranch" }
    $sourcePullRequest = if ($existingSourcePullRequests.Count -eq 1) { $existingSourcePullRequests[0] } else { $null }

    $mirrorResult = $null
    if ($Create) {
        $null = Assert-HostedReviewWritableFork -RepoDirectory $resolvedRepoDirectory
        if ($null -eq $sourcePullRequest) {
            if (@(Invoke-Git ls-remote --heads origin $sourceBranch).Count -gt 0) {
                throw "Source branch exists without an open pull request: $sourceBranch"
            }
            $null = Invoke-Git push origin "$sourceCommit`:refs/heads/$sourceBranch"
            $sourcePullRequest = Invoke-HostedReviewGitHubApi -Endpoint "repos/$destinationRepository/pulls" -Method POST -Fields @{
                title = "Import $SourceRepository PR #$PullRequest as test content"
                body = "Canonical test content imported from $($upstreamPullRequest.html_url).`n`nDo not merge."
                head = $sourceBranch
                base = $TestContentBase
            }
        }
        else {
            if ($sourcePullRequest.base.sha -ne $testContentBaseCommit) {
                throw "Existing source pull request #$($sourcePullRequest.number) is not based on the current $TestContentBase commit"
            }
            $null = Invoke-Git push "--force-with-lease=refs/heads/$sourceBranch`:$($sourcePullRequest.head.sha)" origin "$sourceCommit`:refs/heads/$sourceBranch"
            $sourcePullRequest = Invoke-HostedReviewGitHubApi -Endpoint "repos/$destinationRepository/pulls/$($sourcePullRequest.number)"
        }

        $provenance = [pscustomobject][ordered]@{
            type = 'imported_pull_request'
            repository = [string]$sourceMetadata.full_name
            pullRequest = $PullRequest
            url = [string]$upstreamPullRequest.html_url
            baseCommit = [string]$upstreamPullRequest.base.sha
            headCommit = [string]$upstreamPullRequest.head.sha
        }
        $pairOutput = @(& (Join-Path $PSScriptRoot 'New-ReviewPair.ps1') -RepoDirectory $resolvedRepoDirectory -SourcePullRequest ([int]$sourcePullRequest.number) -RunId $RunId -ReviewEffort $ReviewEffort -ControlBase $ControlBase -HostedBase $HostedBase -TestContentBase $TestContentBase -RegressionDirectory $RegressionDirectory -SourceProvenance $provenance -Create -OutputFormat Json 2>&1)
        if ($LASTEXITCODE -ne 0) { throw "Mirror pair creation failed: $((($pairOutput | Out-String).Trim()))" }
        $mirrorResult = ($pairOutput -join [Environment]::NewLine) | ConvertFrom-Json
    }

    $result = [ordered]@{
        success = $true
        mode = if ($Create) { [string]$mirrorResult.mode } else { 'validate' }
        upstreamPullRequest = [string]$upstreamPullRequest.html_url
        destinationRepository = $destinationRepository
        sourceBranch = $sourceBranch
        sourcePullRequest = if ($null -eq $sourcePullRequest) { $null } else { [int]$sourcePullRequest.number }
        sourceCommit = $sourceCommit
        changedFiles = @($sourceFiles | ForEach-Object { [string]$_.filename })
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
    Write-Output 'Hosted review pull request import'
    Write-Output "  Mode          : $($result.mode.ToUpperInvariant())"
    Write-Output "  Upstream      : $($result.upstreamPullRequest)"
    Write-Output "  Source branch : $sourceBranch"
    Write-Output "  Source PR     : $($result.sourcePullRequest)"
    if ($Create) {
        Write-Output "  Control PR    : #$($result.controlPullRequest)"
        Write-Output "  Hosted PR     : #$($result.hostedPullRequest)"
        Write-Output "  Pair record   : $($result.pairPath)"
    }
}
