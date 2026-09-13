[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$RepoDirectory,

    [Parameter(Mandatory = $true)]
    [ValidatePattern('^[0-9a-f]{40}$')]
    [string]$PinnedCommit,

    [string]$ControlBase = 'control-base',

    [string]$HostedBase = 'hosted-base',

    [string]$TestContentBase = 'test-content',

    [string]$InstallerPath = (Join-Path $PSScriptRoot 'Install-Toolkit.ps1'),

    [switch]$Initialize,

    [switch]$Push,

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
    if ($output.Count -ne 1) {
        throw "Expected one line from git $($args -join ' '); found $($output.Count)"
    }
    return ([string]$output[0]).Trim()
}

function Test-GitPath {
    param(
        [Parameter(Mandatory = $true)][string]$Ref,
        [Parameter(Mandatory = $true)][string]$Path
    )

    $null = & $script:gitCommand.Source -C $script:resolvedRepoDirectory cat-file -e "$Ref`:$Path" 2>$null
    $exists = $LASTEXITCODE -eq 0
    $global:LASTEXITCODE = 0
    return $exists
}

$resolvedRepoDirectory = [IO.Path]::GetFullPath($RepoDirectory)
$resolvedInstallerPath = [IO.Path]::GetFullPath($InstallerPath)
$gitCommand = Get-Command git -ErrorAction SilentlyContinue
if ($null -eq $gitCommand) { throw 'git was not found on PATH' }
if (-not (Test-Path -LiteralPath $resolvedRepoDirectory -PathType Container) -or -not (Test-Path -LiteralPath (Join-Path $resolvedRepoDirectory '.git'))) {
    throw "RepoDirectory is not a Git repository root: $resolvedRepoDirectory"
}
if (-not (Test-Path -LiteralPath $resolvedInstallerPath -PathType Leaf)) {
    throw "InstallerPath was not found: $resolvedInstallerPath"
}
if (-not [string]::IsNullOrWhiteSpace((Invoke-Git status --porcelain | Out-String))) {
    throw "RepoDirectory must have a clean working tree: $resolvedRepoDirectory"
}
$null = Invoke-Git cat-file -e "$PinnedCommit^{commit}"
$null = Invoke-Git check-ref-format "refs/heads/$ControlBase"
$null = Invoke-Git check-ref-format "refs/heads/$HostedBase"
$null = Invoke-Git check-ref-format "refs/heads/$TestContentBase"

$target = if ($Initialize -or $Push) {
    Assert-HostedReviewWritableFork -RepoDirectory $resolvedRepoDirectory
}
else {
    [pscustomobject]@{ repository = Get-HostedReviewRepositoryFromRemote -RepoDirectory $resolvedRepoDirectory }
}

$localBranches = @(Invoke-Git for-each-ref --format='%(refname:short)' refs/heads)
$baseNames = @($ControlBase, $HostedBase, $TestContentBase)
$existingBases = @($baseNames | Where-Object { $_ -in $localBranches })
$legacyBasePair = $existingBases.Count -eq 2 -and $ControlBase -in $existingBases -and $HostedBase -in $existingBases
if ($existingBases.Count -notin @(0, 2, 3) -or ($existingBases.Count -eq 2 -and -not $legacyBasePair)) {
    throw "Persistent base state is incomplete; expected $($baseNames -join ', ')"
}
if ($Push -and -not $Initialize -and $existingBases.Count -eq 0) {
    throw '-Push requires existing persistent bases or -Initialize'
}

$controlBaseCommit = $null
$hostedBaseCommit = $null
$testContentBaseCommit = $null
$installedSourceCommit = $null
$manifestHash = $null
$basesExisted = $existingBases.Count -eq 3
if ($basesExisted -or $legacyBasePair) {
    $controlBaseCommit = Get-GitSingleValue rev-parse $ControlBase
    $hostedBaseCommit = Get-GitSingleValue rev-parse $HostedBase
    if ($controlBaseCommit -ne $PinnedCommit) {
        throw "$ControlBase must point exactly at pinned commit $PinnedCommit"
    }
    if ((Get-GitSingleValue merge-base $ControlBase $HostedBase) -ne $controlBaseCommit) {
        throw "$HostedBase must descend from $ControlBase"
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
    $state = (@(Invoke-Git show "$HostedBase`:.github/hosted-copilot-installed-state.json") -join "`n") | ConvertFrom-Json
    $installedSourceCommit = [string]$state.commit
    $manifestHash = [string]$state.manifestHash
    if ($basesExisted) {
        $testContentBaseCommit = Get-GitSingleValue rev-parse $TestContentBase
        if ($testContentBaseCommit -ne $PinnedCommit) {
            throw "$TestContentBase must point exactly at pinned commit $PinnedCommit"
        }
    }
    elseif (-not $Initialize) {
        throw "Persistent authoring base $TestContentBase is missing; close legacy test-content/* run branches, then rerun with -Initialize"
    }
    else {
        $conflictingLocalRefs = @(Invoke-Git for-each-ref --format='%(refname:short)' "refs/heads/$TestContentBase/")
        $conflictingRemoteRefs = @(Invoke-Git ls-remote --heads origin "refs/heads/$TestContentBase/*")
        if ($conflictingLocalRefs.Count -gt 0 -or $conflictingRemoteRefs.Count -gt 0) {
            throw "Cannot create persistent $TestContentBase while legacy $TestContentBase/* run branches exist"
        }
        $null = Invoke-Git branch $TestContentBase $PinnedCommit
        $testContentBaseCommit = $PinnedCommit
        $basesExisted = $true
    }
    if ($Push) {
        $null = Invoke-Git push --set-upstream origin $ControlBase $HostedBase $TestContentBase
    }
}
elseif ($Initialize) {
    $tempRoot = Join-Path ([IO.Path]::GetTempPath()) ("hosted-review-base-$([guid]::NewGuid().ToString('N'))")
    New-Item -ItemType Directory -Path $tempRoot | Out-Null
    try {
        $null = Invoke-Git worktree add --detach $tempRoot $PinnedCommit
        $installOutput = @(& $resolvedInstallerPath -RepoDirectory $tempRoot -Install -OutputFormat Json 2>&1)
        if ($LASTEXITCODE -ne 0) {
            throw "Hosted overlay installation failed: $((($installOutput | Out-String).Trim()))"
        }
        $install = ($installOutput -join [Environment]::NewLine) | ConvertFrom-Json
        $installedPaths = @($install.operations.targetPath) + '.github/hosted-copilot-installed-state.json'
        $null = & $gitCommand.Source -C $tempRoot add -f -- @($installedPaths)
        if ($LASTEXITCODE -ne 0) { throw 'Failed to stage Hosted overlay files' }
        $null = & $gitCommand.Source -C $tempRoot commit -m 'Install Hosted Copilot review overlay'
        if ($LASTEXITCODE -ne 0) { throw 'Failed to commit Hosted overlay files' }
        $hostedBaseCommit = (& $gitCommand.Source -C $tempRoot rev-parse HEAD).Trim()
        $state = Get-Content -LiteralPath (Join-Path $tempRoot '.github/hosted-copilot-installed-state.json') -Raw | ConvertFrom-Json
        $installedSourceCommit = [string]$state.commit
        $manifestHash = [string]$state.manifestHash
        $controlBaseCommit = $PinnedCommit

        $null = Invoke-Git branch $ControlBase $controlBaseCommit
        $null = Invoke-Git branch $HostedBase $hostedBaseCommit
        $null = Invoke-Git branch $TestContentBase $PinnedCommit
        $testContentBaseCommit = $PinnedCommit
        if ($Push) {
            if (@(Invoke-Git ls-remote --heads origin $ControlBase $HostedBase $TestContentBase).Count -gt 0) {
                throw "Remote base branches already exist: $($baseNames -join ', ')"
            }
            $null = Invoke-Git push --atomic --set-upstream origin $ControlBase $HostedBase $TestContentBase
        }
    }
    catch {
        foreach ($branch in $baseNames) {
            if ($branch -in @(Invoke-Git for-each-ref --format='%(refname:short)' refs/heads)) {
                $null = Invoke-Git branch -D $branch
            }
        }
        throw
    }
    finally {
        if (Test-Path -LiteralPath $tempRoot) {
            $null = & $gitCommand.Source -C $resolvedRepoDirectory worktree remove --force $tempRoot 2>$null
            Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

$result = [ordered]@{
    success = $true
    mode = if ($basesExisted) { 'verify' } elseif ($Initialize) { 'initialize' } else { 'plan' }
    repository = [string]$target.repository
    repositoryDirectory = $resolvedRepoDirectory
    pinnedCommit = $PinnedCommit
    controlBase = $ControlBase
    hostedBase = $HostedBase
    testContentBase = $TestContentBase
    controlBaseCommit = $controlBaseCommit
    hostedBaseCommit = $hostedBaseCommit
    testContentBaseCommit = $testContentBaseCommit
    installedSourceCommit = $installedSourceCommit
    manifestHash = $manifestHash
    pushed = [bool]$Push
}

if ($OutputFormat -eq 'Json') {
    $result | ConvertTo-Json -Depth 6
}
else {
    Write-Output 'Hosted review base initialization'
    Write-Output "  Mode          : $($result.mode.ToUpperInvariant())"
    Write-Output "  Repository    : $($result.repository)"
    Write-Output "  Pinned commit : $PinnedCommit"
    Write-Output "  Control base  : $ControlBase"
    Write-Output "  Hosted base   : $HostedBase"
    Write-Output "  Content base  : $TestContentBase"
    if ($null -ne $controlBaseCommit) {
        Write-Output "  Control commit: $controlBaseCommit"
        Write-Output "  Hosted commit : $hostedBaseCommit"
        Write-Output "  Content commit: $testContentBaseCommit"
        Write-Output "  Pushed        : $([bool]$Push)"
    }
}
