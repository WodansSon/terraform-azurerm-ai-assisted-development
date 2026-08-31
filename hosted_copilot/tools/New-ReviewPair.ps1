[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$RepoDirectory,

    [Parameter(Mandatory = $true)]
    [ValidateRange(1, [int]::MaxValue)]
    [int]$SourcePullRequest,

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

    [string]$Title,

    [string]$Body,

    [psobject]$SourceProvenance,

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

function Invoke-WorktreeGit {
    param(
        [Parameter(Mandatory = $true)][string]$Worktree,
        [Parameter(Mandatory = $true)][string[]]$Arguments
    )

    $output = @(& $script:gitCommand.Source -C $Worktree @Arguments 2>&1)
    if ($LASTEXITCODE -ne 0) {
        throw "git $($Arguments -join ' ') failed in mirror worktree: $((($output | Out-String).Trim()))"
    }
    return $output
}

function Get-GitSingleValue {
    $output = @(Invoke-Git @args)
    if ($output.Count -ne 1) { throw "Expected one line from git $($args -join ' '); found $($output.Count)" }
    return ([string]$output[0]).Trim()
}

function Test-GitPath {
    param([Parameter(Mandatory = $true)][string]$Ref, [Parameter(Mandatory = $true)][string]$Path)

    $null = & $script:gitCommand.Source -C $script:resolvedRepoDirectory cat-file -e "$Ref`:$Path" 2>$null
    $exists = $LASTEXITCODE -eq 0
    $global:LASTEXITCODE = 0
    return $exists
}

function Get-PatchHash {
    param([Parameter(Mandatory = $true)][string]$Patch)

    return [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData([Text.Encoding]::UTF8.GetBytes($Patch))).ToLowerInvariant()
}

function Get-PullRequestFiles {
    param(
        [Parameter(Mandatory = $true)][string]$Repository,
        [Parameter(Mandatory = $true)][int]$Number,
        [Parameter(Mandatory = $true)][int]$ExpectedCount
    )

    $result = New-Object 'System.Collections.Generic.List[object]'
    $pageCount = [Math]::Max(1, [Math]::Ceiling([double]$ExpectedCount / 100))
    for ($page = 1; $page -le $pageCount; $page++) {
        foreach ($file in @(Invoke-HostedReviewGitHubApi -Endpoint "repos/$Repository/pulls/$Number/files?per_page=100&page=$page")) {
            $result.Add($file)
        }
    }
    if ($result.Count -ne $ExpectedCount) {
        throw "Source pull request file capture is incomplete; expected $ExpectedCount, found $($result.Count)"
    }
    return @($result)
}

function New-MirrorCommit {
    param(
        [Parameter(Mandatory = $true)][string]$Worktree,
        [Parameter(Mandatory = $true)][string]$Base,
        [Parameter(Mandatory = $true)][string]$PatchPath,
        [Parameter(Mandatory = $true)][string]$Message
    )

    $null = Invoke-Git worktree add --detach $Worktree $Base
    $null = Invoke-WorktreeGit -Worktree $Worktree -Arguments @('apply', '--index', '--binary', $PatchPath)
    $stagedFiles = @(Invoke-WorktreeGit -Worktree $Worktree -Arguments @('diff', '--cached', '--name-only') | Sort-Object)
    if ($stagedFiles.Count -eq 0) { throw 'Source pull request patch produced no changes' }
    $null = Invoke-WorktreeGit -Worktree $Worktree -Arguments @('commit', '-m', $Message)
    return [pscustomobject]@{
        commit = ([string]@(Invoke-WorktreeGit -Worktree $Worktree -Arguments @('rev-parse', 'HEAD'))[0]).Trim()
        changedFiles = $stagedFiles
        patch = @(Invoke-WorktreeGit -Worktree $Worktree -Arguments @('diff', '--no-ext-diff', '--no-color', "$Base..HEAD")) -join "`n"
    }
}

$resolvedRepoDirectory = [IO.Path]::GetFullPath($RepoDirectory)
$resolvedRegressionDirectory = [IO.Path]::GetFullPath($RegressionDirectory)
$gitCommand = Get-Command git -ErrorAction SilentlyContinue
if ($null -eq $gitCommand) { throw 'git was not found on PATH' }
if (-not (Test-Path -LiteralPath $resolvedRepoDirectory -PathType Container) -or -not (Test-Path -LiteralPath (Join-Path $resolvedRepoDirectory '.git'))) {
    throw "RepoDirectory is not a Git repository root: $resolvedRepoDirectory"
}
if (-not [string]::IsNullOrWhiteSpace((Invoke-Git status --porcelain | Out-String))) {
    throw "RepoDirectory must have a clean working tree: $resolvedRepoDirectory"
}

$target = if ($Create) {
    Assert-HostedReviewWritableFork -RepoDirectory $resolvedRepoDirectory
}
else {
    [pscustomobject]@{ repository = Get-HostedReviewRepositoryFromRemote -RepoDirectory $resolvedRepoDirectory }
}
$repository = [string]$target.repository
$controlBaseCommit = Get-GitSingleValue rev-parse $ControlBase
$hostedBaseCommit = Get-GitSingleValue rev-parse $HostedBase
$testContentBaseCommit = Get-GitSingleValue rev-parse $TestContentBase
if ($testContentBaseCommit -ne $controlBaseCommit) {
    throw "$TestContentBase and $ControlBase must point at the same pinned commit"
}
if ((Get-GitSingleValue rev-parse "$HostedBase^") -ne $controlBaseCommit) {
    throw "$HostedBase must add exactly one Hosted overlay commit to $ControlBase"
}
if (Test-GitPath -Ref $ControlBase -Path '.github/hosted-copilot-installed-state.json') {
    throw "$ControlBase must not contain Hosted installed state"
}
if (-not (Test-GitPath -Ref $HostedBase -Path '.github/hosted-copilot-installed-state.json')) {
    throw "$HostedBase must contain Hosted installed state"
}
$hostedState = (@(Invoke-Git show "$HostedBase`:.github/hosted-copilot-installed-state.json") -join "`n") | ConvertFrom-Json

$source = Invoke-HostedReviewGitHubApi -Endpoint "repos/$repository/pulls/$SourcePullRequest"
if ($source.state -ne 'open') { throw "Source pull request #$SourcePullRequest must be open" }
if ($source.base.ref -ne $TestContentBase) {
    throw "Source pull request #$SourcePullRequest must target $TestContentBase, found $($source.base.ref)"
}
if (-not ([string]$source.head.repo.full_name).Equals($repository, [StringComparison]::OrdinalIgnoreCase)) {
    throw "Source pull request #$SourcePullRequest head must belong to $repository"
}
if ([string]$source.base.sha -ne $testContentBaseCommit) {
    throw "Source pull request #$SourcePullRequest is not based on the current $TestContentBase commit"
}
$sourceFiles = @(Get-PullRequestFiles -Repository $repository -Number $SourcePullRequest -ExpectedCount ([int]$source.changed_files))
$changedFiles = @($sourceFiles | ForEach-Object { ([string]$_.filename).Replace('\', '/') } | Sort-Object)
$forbiddenFiles = @($sourceFiles | Where-Object {
        ([string]$_.filename).Replace('\', '/') -match '^\.github(?:/|$)' -or
        ($null -ne $_.PSObject.Properties['previous_filename'] -and ([string]$_.previous_filename).Replace('\', '/') -match '^\.github(?:/|$)')
    })
if ($forbiddenFiles.Count -gt 0) {
    throw 'Source pull request must not modify review customization or workflows under .github/'
}

$changeId = "source-pr-$SourcePullRequest"
$controlHead = "control-review/$changeId/$RunId"
$hostedHead = "hosted-review/$changeId/$RunId"
foreach ($branch in @($controlHead, $hostedHead)) { $null = Invoke-Git check-ref-format "refs/heads/$branch" }
$pairPath = Join-Path $resolvedRegressionDirectory "raw/$changeId/$RunId.pair.json"
$existingPair = if (Test-Path -LiteralPath $pairPath -PathType Leaf) { Get-Content -LiteralPath $pairPath -Raw | ConvertFrom-Json } else { $null }
if ($null -ne $existingPair) {
    if ($existingPair.schemaVersion -ne 2 -or $existingPair.repository -ne $repository -or [int]$existingPair.source.pullRequest -ne $SourcePullRequest) {
        throw "Existing pair record does not match source pull request #${SourcePullRequest}: $pairPath"
    }
    if ($existingPair.control.head -ne $controlHead -or $existingPair.hosted.head -ne $hostedHead) {
        throw 'Existing pair record branch topology does not match the requested run'
    }
}
elseif (@(Invoke-Git ls-remote --heads origin $controlHead $hostedHead).Count -gt 0) {
    throw "Mirror branches already exist without a pair record for run $RunId"
}

$tempRoot = Join-Path ([IO.Path]::GetTempPath()) ("hosted-review-pair-$([guid]::NewGuid().ToString('N'))")
$controlWorktree = Join-Path $tempRoot 'control'
$hostedWorktree = Join-Path $tempRoot 'hosted'
$patchPath = Join-Path $tempRoot 'source.diff'
New-Item -ItemType Directory -Path $tempRoot | Out-Null
try {
    $sourceDiff = Invoke-HostedReviewGitHubApi -Endpoint "repos/$repository/pulls/$SourcePullRequest" -Accept 'application/vnd.github.v3.diff' -Raw
    if ([string]::IsNullOrWhiteSpace($sourceDiff)) { throw "Source pull request #$SourcePullRequest returned an empty diff" }
    Set-Content -LiteralPath $patchPath -Value ($sourceDiff + "`n") -Encoding utf8NoBOM -NoNewline
    $message = "Mirror source pull request #$SourcePullRequest"
    $controlMirror = New-MirrorCommit -Worktree $controlWorktree -Base $ControlBase -PatchPath $patchPath -Message $message
    $hostedMirror = New-MirrorCommit -Worktree $hostedWorktree -Base $HostedBase -PatchPath $patchPath -Message $message
    if ($controlMirror.patch -cne $hostedMirror.patch) { throw 'Control and Hosted mirror patches are not identical' }
    if (($controlMirror.changedFiles -join "`n") -ne ($hostedMirror.changedFiles -join "`n") -or ($controlMirror.changedFiles -join "`n") -ne ($changedFiles -join "`n")) {
        throw 'Control and Hosted mirror changed-file sets must match the source pull request'
    }
    $diffHash = Get-PatchHash -Patch $controlMirror.patch

    $controlPullRequest = $null
    $hostedPullRequest = $null
    $createdMirrorBranches = $false
    $mode = if ($null -eq $existingPair) { 'create' } else { 'synchronize' }
    if ($Create) {
        try {
            if ($null -eq $existingPair) {
                $null = Invoke-Git push --atomic origin "$($controlMirror.commit):refs/heads/$controlHead" "$($hostedMirror.commit):refs/heads/$hostedHead"
                $createdMirrorBranches = $true
                $effectiveTitle = if ([string]::IsNullOrWhiteSpace($Title)) { "Mirror source PR #$SourcePullRequest for Hosted review" } else { $Title }
                $effectiveBody = if ([string]::IsNullOrWhiteSpace($Body)) { "Controlled mirror of $($source.html_url).`n`nDo not merge." } else { $Body }
                $controlPullRequest = Invoke-HostedReviewGitHubApi -Endpoint "repos/$repository/pulls" -Method POST -Fields @{ title = $effectiveTitle; body = $effectiveBody; head = $controlHead; base = $ControlBase }
                $hostedPullRequest = Invoke-HostedReviewGitHubApi -Endpoint "repos/$repository/pulls" -Method POST -Fields @{ title = $effectiveTitle; body = $effectiveBody; head = $hostedHead; base = $HostedBase }
            }
            else {
                $controlPullRequest = Invoke-HostedReviewGitHubApi -Endpoint "repos/$repository/pulls/$($existingPair.control.pullRequest)"
                $hostedPullRequest = Invoke-HostedReviewGitHubApi -Endpoint "repos/$repository/pulls/$($existingPair.hosted.pullRequest)"
                foreach ($profile in @(@{ name = 'control'; pr = $controlPullRequest; head = $controlHead; base = $ControlBase }, @{ name = 'hosted'; pr = $hostedPullRequest; head = $hostedHead; base = $HostedBase })) {
                    if ($profile.pr.state -ne 'open' -or $profile.pr.head.ref -ne $profile.head -or $profile.pr.base.ref -ne $profile.base) {
                        throw "$($profile.name) mirror pull request topology no longer matches the pair record"
                    }
                }
                $null = Invoke-Git push --atomic "--force-with-lease=refs/heads/$controlHead`:$($existingPair.control.headCommit)" "--force-with-lease=refs/heads/$hostedHead`:$($existingPair.hosted.headCommit)" origin "$($controlMirror.commit):refs/heads/$controlHead" "$($hostedMirror.commit):refs/heads/$hostedHead"
            }
        }
        catch {
            if ($null -eq $existingPair) {
                foreach ($pullRequest in @($controlPullRequest, $hostedPullRequest)) {
                    if ($null -ne $pullRequest) {
                        try { $null = Invoke-HostedReviewGitHubApi -Endpoint "repos/$repository/pulls/$($pullRequest.number)" -Method PATCH -Fields @{ state = 'closed' } } catch {}
                    }
                }
                if ($createdMirrorBranches) {
                    try { $null = Invoke-Git push origin --delete $controlHead $hostedHead } catch {}
                }
            }
            throw
        }

        $pairDirectory = Split-Path -Parent $pairPath
        New-Item -ItemType Directory -Path $pairDirectory -Force | Out-Null
        [ordered]@{
            schemaVersion = 2
            sourceType = 'source_pull_request'
            repository = $repository
            caseId = $changeId
            runId = $RunId
            reviewEffort = $ReviewEffort
            diffHash = $diffHash
            changedFiles = $changedFiles
            sourceProvenance = if ($null -ne $SourceProvenance) { $SourceProvenance } elseif ($null -ne $existingPair) { $existingPair.sourceProvenance } else { $null }
            source = [ordered]@{ base = $TestContentBase; baseCommit = $testContentBaseCommit; head = [string]$source.head.ref; headCommit = [string]$source.head.sha; pullRequest = $SourcePullRequest; url = [string]$source.html_url }
            sourceCommit = [string]$hostedState.commit
            manifestHash = [string]$hostedState.manifestHash
            control = [ordered]@{ base = $ControlBase; baseCommit = $controlBaseCommit; head = $controlHead; headCommit = $controlMirror.commit; pullRequest = [int]$controlPullRequest.number; url = [string]$controlPullRequest.html_url }
            hosted = [ordered]@{ base = $HostedBase; baseCommit = $hostedBaseCommit; head = $hostedHead; headCommit = $hostedMirror.commit; pullRequest = [int]$hostedPullRequest.number; url = [string]$hostedPullRequest.html_url }
        } | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $pairPath -Encoding utf8NoBOM
    }

    $result = [ordered]@{
        success = $true
        mode = if ($Create) { $mode } else { 'validate' }
        repository = $repository
        sourcePullRequest = $SourcePullRequest
        sourceHead = [string]$source.head.ref
        sourceHeadCommit = [string]$source.head.sha
        changedFiles = $changedFiles
        controlHead = $controlHead
        hostedHead = $hostedHead
        controlPullRequest = if ($null -eq $controlPullRequest) { $null } else { [int]$controlPullRequest.number }
        hostedPullRequest = if ($null -eq $hostedPullRequest) { $null } else { [int]$hostedPullRequest.number }
        pairPath = if ($Create) { [IO.Path]::GetFullPath($pairPath) } else { $null }
        diffHash = $diffHash
    }
}
finally {
    foreach ($worktree in @($controlWorktree, $hostedWorktree)) {
        if (Test-Path -LiteralPath $worktree) { $null = & $gitCommand.Source -C $resolvedRepoDirectory worktree remove --force $worktree 2>$null }
    }
    Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
}

if ($OutputFormat -eq 'Json') {
    $result | ConvertTo-Json -Depth 8
}
else {
    Write-Output 'Hosted review pair'
    Write-Output "  Mode          : $($result.mode.ToUpperInvariant())"
    Write-Output "  Source PR     : #$SourcePullRequest"
    Write-Output "  Source head   : $($result.sourceHead)"
    Write-Output "  Control head  : $controlHead"
    Write-Output "  Hosted head   : $hostedHead"
    if ($Create) {
        Write-Output "  Control PR    : #$($result.controlPullRequest)"
        Write-Output "  Hosted PR     : #$($result.hostedPullRequest)"
        Write-Output "  Pair record   : $($result.pairPath)"
    }
}
