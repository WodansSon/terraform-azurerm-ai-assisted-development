[CmdletBinding()]
param(
    [ValidateSet('Text', 'Json')]
    [string]$OutputFormat = 'Text',

    [switch]$SkipChangelog,

    [switch]$ChangelogNotRequired,

    [string]$ChangelogReason,

    [switch]$SkipRegressionHarness,

    [switch]$SkipUpstreamDrift,

    [switch]$AllowCatalogIssues,

    [switch]$AllowDrift
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$contractsScriptPath = Join-Path $PSScriptRoot 'validate-contracts.ps1'
$driftScriptPath = Join-Path $PSScriptRoot 'check-upstream-contributor-drift.ps1'
$regressionHarnessScriptPath = Join-Path $PSScriptRoot 'regression/run-regression-harness.ps1'
$changelogPath = Join-Path $repoRoot 'CHANGELOG.md'

$npxCommand = Get-Command 'npx.cmd' -ErrorAction SilentlyContinue
if ($null -eq $npxCommand) {
    $npxCommand = Get-Command 'npx' -ErrorAction SilentlyContinue
}

$gitCommand = Get-Command 'git' -ErrorAction SilentlyContinue

function Invoke-ValidationStep {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name,

        [Parameter(Mandatory = $true)]
        [scriptblock]$Command,

        [string]$Detail,

        [switch]$Skipped
    )

    if ($Skipped) {
        return [pscustomobject]@{
            name = $Name
            status = 'skipped'
            success = $true
            exitCode = 0
            durationSeconds = 0
            detail = $Detail
            output = ''
        }
    }

    $started = Get-Date
    $outputLines = @()
    $exitCode = 0

    try {
        $global:LASTEXITCODE = 0
        $outputLines = & $Command 2>&1
        $exitCode = if ($null -ne $LASTEXITCODE) { $LASTEXITCODE } else { 0 }
    }
    catch {
        $outputLines = @($_)
        $exitCode = 1
    }

    $durationSeconds = [Math]::Round(((Get-Date) - $started).TotalSeconds, 2)
    $outputText = ($outputLines | Out-String).Trim()

    return [pscustomobject]@{
        name = $Name
        status = if ($exitCode -eq 0) { 'passed' } else { 'failed' }
        success = ($exitCode -eq 0)
        exitCode = $exitCode
        durationSeconds = $durationSeconds
        detail = $Detail
        output = $outputText
    }
}

function Get-TextMatchValue {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Text,

        [Parameter(Mandatory = $true)]
        [string]$Pattern
    )

    $match = [regex]::Match($Text, $Pattern, [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
    if (-not $match.Success) {
        return $null
    }

    return $match.Groups[1].Value
}

function Get-ChangedRepositoryPaths {
    param([string]$RepoRoot)

    if ($null -eq $gitCommand) {
        return @()
    }

    $paths = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)

    try {
        $statusLines = @(& $gitCommand.Source -C $RepoRoot status --porcelain)
        foreach ($statusLine in $statusLines) {
            if ([string]::IsNullOrWhiteSpace($statusLine) -or $statusLine.Length -lt 4) {
                continue
            }

            $pathValue = $statusLine.Substring(3).Trim()
            if ($pathValue -match ' -> ') {
                $pathValue = ($pathValue -split ' -> ')[-1]
            }

            if (-not [string]::IsNullOrWhiteSpace($pathValue)) {
                [void]$paths.Add($pathValue.Replace('\', '/'))
            }
        }
    }
    catch {
    }

    $candidateRefs = @()
    if (-not [string]::IsNullOrWhiteSpace($env:GITHUB_BASE_REF)) {
        $candidateRefs += @("origin/$($env:GITHUB_BASE_REF)", $env:GITHUB_BASE_REF)
    }
    $candidateRefs += @('origin/main', 'upstream/main', 'main')
    $candidateRefs = @($candidateRefs | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -Unique)

    foreach ($candidateRef in $candidateRefs) {
        try {
            & $gitCommand.Source -C $RepoRoot rev-parse --verify $candidateRef *> $null
            $diffPaths = @(& $gitCommand.Source -C $RepoRoot diff --name-only "$candidateRef...HEAD")
            foreach ($diffPath in $diffPaths) {
                if (-not [string]::IsNullOrWhiteSpace($diffPath)) {
                    [void]$paths.Add($diffPath.Replace('\', '/'))
                }
            }
            break
        }
        catch {
        }
    }

    return @($paths | Sort-Object)
}

function Test-PathMatchesAnyPattern {
    param(
        [string]$Path,
        [string[]]$Patterns
    )

    foreach ($pattern in $Patterns) {
        if ($Path -like $pattern) {
            return $true
        }
    }

    return $false
}

Push-Location $repoRoot
try {
    $steps = @()

    $steps += Invoke-ValidationStep -Name 'changelog' -Detail 'Confirm the current branch has an explicit changelog decision: either CHANGELOG.md is updated or a maintainer explicitly marks the branch as changelog-not-required.' -Skipped:$SkipChangelog -Command {
        if ($null -eq $gitCommand) {
            Write-Output 'git not found on PATH; changelog alignment could not be evaluated'
            return
        }

        $changedPaths = @(Get-ChangedRepositoryPaths -RepoRoot $repoRoot)
        if ($changedPaths.Count -eq 0) {
            Write-Output 'No branch changes detected; changelog validation is not applicable.'
            return
        }

        if ($changedPaths -contains 'CHANGELOG.md') {
            Write-Output 'CHANGELOG.md is updated for the current branch.'
            return
        }

        if ($ChangelogNotRequired) {
            if ([string]::IsNullOrWhiteSpace($ChangelogReason)) {
                throw 'ChangelogNotRequired was specified without ChangelogReason'
            }

            Write-Output ("Explicit changelog waiver recorded for current branch changes: {0}" -f $ChangelogReason.Trim())
            return
        }

        throw 'CHANGELOG.md is not updated for the current branch. Update CHANGELOG.md or rerun with -ChangelogNotRequired -ChangelogReason "<reason>".'
    }

    $steps += Invoke-ValidationStep -Name 'contracts' -Detail 'Validate AI-toolkit contracts, companion guidance, and consumer wiring.' -Command {
        & pwsh -NoProfile -File $contractsScriptPath
    }

    $steps += Invoke-ValidationStep -Name 'markdown' -Detail 'Lint .github, docs, and CHANGELOG markdown using the repo markdownlint configuration.' -Command {
        if ($null -eq $npxCommand) {
            throw 'npx was not found on PATH'
        }

        & $npxCommand.Source -y markdownlint-cli2 '.github/**/*.md' 'docs/**/*.md' 'CHANGELOG.md' --config '.github/.markdownlint.json'
    }

    $steps += Invoke-ValidationStep -Name 'regression-harness' -Detail 'Run the regression harness validation, suite scoring, and history snapshot flow.' -Skipped:$SkipRegressionHarness -Command {
        & pwsh -NoProfile -File $regressionHarnessScriptPath
    }

    $driftArguments = @(
        '-NoProfile',
        '-File',
        $driftScriptPath,
        '-OutputFormat',
        'Text'
    )
    if (-not $AllowDrift -and -not $AllowCatalogIssues) {
        $driftArguments += '-FailOnDrift'
    }

    $steps += Invoke-ValidationStep -Name 'upstream-drift' -Detail 'Check tracked upstream contributor guidance drift and explicit topic coverage.' -Skipped:$SkipUpstreamDrift -Command {
        & pwsh @driftArguments
    }

    $driftStep = @($steps | Where-Object { $_.name -eq 'upstream-drift' })[0]
    if ($driftStep.status -ne 'skipped') {
        $driftChangedSources = [int](Get-TextMatchValue -Text $driftStep.output -Pattern 'Changed:\s*([0-9]+)')
        $driftCatalogIssues = [int](Get-TextMatchValue -Text $driftStep.output -Pattern 'Catalog Issues:\s*([0-9]+)')
        $driftRuleIssues = [int](Get-TextMatchValue -Text $driftStep.output -Pattern 'Rule Issues:\s*([0-9]+)')

        $hasBlockingDrift = $driftChangedSources -gt 0 -or $driftRuleIssues -gt 0
        if (-not $AllowCatalogIssues) {
            $hasBlockingDrift = $hasBlockingDrift -or $driftCatalogIssues -gt 0
        }

        if (-not $AllowDrift -and $hasBlockingDrift) {
            $driftStep.status = 'failed'
            $driftStep.success = $false
            $driftStep.exitCode = 1
            if ($AllowCatalogIssues -and $driftCatalogIssues -gt 0 -and -not ($driftChangedSources -gt 0 -or $driftRuleIssues -gt 0)) {
                $driftStep.detail = 'Check tracked upstream contributor guidance drift and explicit topic coverage. Changed sources and rule issues are clean; unresolved catalog coverage still requires separate maintainer review.'
            }
            else {
                $driftStep.detail = 'Check tracked upstream contributor guidance drift and explicit topic coverage. Unresolved drift requires maintainer review.'
            }
        }
    }

    $overallSuccess = @($steps | Where-Object { -not $_.success }).Count -eq 0
    $regressionStep = @($steps | Where-Object { $_.name -eq 'regression-harness' })[0]

    $summary = [ordered]@{
        overallStatus = if ($overallSuccess) { 'passed' } else { 'failed' }
        repoRoot = $repoRoot
        steps = $steps
        highlights = [ordered]@{
            changelogStatus = @($steps | Where-Object { $_.name -eq 'changelog' })[0].status
            regressionCasesSelected = if ($regressionStep.status -eq 'passed') { Get-TextMatchValue -Text $regressionStep.output -Pattern 'Cases Selected\s*:\s*([0-9]+)' } else { $null }
            regressionCasesScored = if ($regressionStep.status -eq 'passed') { Get-TextMatchValue -Text $regressionStep.output -Pattern 'Cases Scored\s*:\s*([0-9]+)' } else { $null }
            upstreamChangedSources = if ($driftStep.status -ne 'skipped') { Get-TextMatchValue -Text $driftStep.output -Pattern 'Changed:\s*([0-9]+)' } else { $null }
            upstreamCatalogIssues = if ($driftStep.status -ne 'skipped') { Get-TextMatchValue -Text $driftStep.output -Pattern 'Catalog Issues:\s*([0-9]+)' } else { $null }
            upstreamRuleIssues = if ($driftStep.status -ne 'skipped') { Get-TextMatchValue -Text $driftStep.output -Pattern 'Rule Issues:\s*([0-9]+)' } else { $null }
        }
    }

    if ($OutputFormat -eq 'Json') {
        $summary | ConvertTo-Json -Depth 10
    }
    else {
        Write-Output "AI toolkit validation summary"
        Write-Output "  Overall Status   : $($summary.overallStatus)"
        Write-Output "  Repository Root  : $repoRoot"
        Write-Output ""
        Write-Output "Validation steps"
        foreach ($step in $steps) {
            Write-Output "  $($step.name): $($step.status) ($($step.durationSeconds)s)"
            if (-not [string]::IsNullOrWhiteSpace($step.detail)) {
                Write-Output "    $($step.detail)"
            }
        }

        Write-Output ""
        Write-Output "Highlights"
        if ($null -ne $summary.highlights.changelogStatus) {
            Write-Output "  Changelog Status         : $($summary.highlights.changelogStatus)"
        }
        if ($null -ne $summary.highlights.regressionCasesSelected) {
            Write-Output "  Regression Cases Selected : $($summary.highlights.regressionCasesSelected)"
        }
        if ($null -ne $summary.highlights.regressionCasesScored) {
            Write-Output "  Regression Cases Scored   : $($summary.highlights.regressionCasesScored)"
        }
        if ($null -ne $summary.highlights.upstreamChangedSources) {
            Write-Output "  Upstream Changed Sources  : $($summary.highlights.upstreamChangedSources)"
        }
        if ($null -ne $summary.highlights.upstreamCatalogIssues) {
            Write-Output "  Upstream Catalog Issues   : $($summary.highlights.upstreamCatalogIssues)"
        }
        if ($null -ne $summary.highlights.upstreamRuleIssues) {
            Write-Output "  Upstream Rule Issues      : $($summary.highlights.upstreamRuleIssues)"
        }

        if (-not $overallSuccess) {
            Write-Output ""
            Write-Output "Failures"
            foreach ($failedStep in @($steps | Where-Object { -not $_.success })) {
                Write-Output "  [$($failedStep.name)] exit=$($failedStep.exitCode)"
                if (-not [string]::IsNullOrWhiteSpace($failedStep.output)) {
                    Write-Output $failedStep.output
                }
            }
        }
    }

    if (-not $overallSuccess) {
        exit 1
    }
}
finally {
    Pop-Location
}
