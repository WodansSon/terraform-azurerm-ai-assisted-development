[CmdletBinding()]
param(
    [ValidateSet('Text', 'Json')]
    [string]$OutputFormat = 'Text',

    [ValidateSet('Auto', 'Worktree', 'Branch', 'Combined')]
    [string]$ChangedRegressionScope = 'Auto',

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
$changelogTaxonomyScriptPath = Join-Path $PSScriptRoot 'validate-changelog-taxonomy.ps1'
$changelogConsistencyScriptPath = Join-Path $PSScriptRoot 'validate-changelog-consistency.ps1'
$architectureLayoutScriptPath = Join-Path $PSScriptRoot 'validate-architecture-layout.ps1'
$copiedMarkdownLinksScriptPath = Join-Path $PSScriptRoot 'validate-copied-markdown-links.ps1'
$contractsScriptPath = Join-Path $PSScriptRoot 'validate-contracts.ps1'
$driftScriptPath = Join-Path $PSScriptRoot 'check-upstream-contributor-drift.ps1'
$manifestPath = Join-Path $repoRoot 'installer/file-manifest.config'
$releaseBundleScriptPath = Join-Path $PSScriptRoot 'build-release-bundle_dry_run.ps1'
$runtimeLineEndingsScriptPath = Join-Path $PSScriptRoot 'validate-runtime-line-endings.ps1'
$regressionHarnessScriptPath = Join-Path $PSScriptRoot 'regression/run-regression-harness.ps1'
$projectReadyTestScriptPath = Join-Path $PSScriptRoot 'Test-PRReady.ps1'

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

        [switch]$Skipped,

        [switch]$RelayStatusOutput
    )

    if ($Skipped) {
        if ($OutputFormat -eq 'Text') {
            Write-Host (Format-StatusLine -Status 'skipped' -Name $Name -Detail 'SKIPPED')
        }

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

    if ($OutputFormat -eq 'Text') {
        Write-Host (Format-StatusLine -Status 'running' -Name $Name -Detail 'IN PROGRESS')
    }

    $started = Get-Date
    $outputLines = @()
    $exitCode = 0

    try {
        $global:LASTEXITCODE = 0
        $outputLines = @(& $Command 2>&1 | ForEach-Object {
            if ($RelayStatusOutput -and $OutputFormat -eq 'Text' -and ([string]$_) -match '^\[(RUNNING|PASSED|FAILED|SKIPPED)\]') {
                Write-Host ("  {0}" -f $_)
            }

            Write-Output $_
        })
        $exitCode = if ($null -ne $LASTEXITCODE) { $LASTEXITCODE } else { 0 }
    }
    catch {
        $outputLines = @($_)
        $exitCode = 1
    }

    $durationSeconds = [Math]::Round(((Get-Date) - $started).TotalSeconds, 2)
    $outputText = ($outputLines | Out-String).Trim()
    $status = if ($exitCode -eq 0) { 'passed' } else { 'failed' }

    if ($OutputFormat -eq 'Text') {
        Write-Host (Format-StatusLine -Status $status -Name $Name -Detail ("{0}s" -f $durationSeconds))
    }

    return [pscustomobject]@{
        name = $Name
        status = $status
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

function Write-TextSectionHeader {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Title
    )

    $separator = '-' * 51

    Write-Output ''
    Write-Output $separator
    Write-Output $Title.ToUpperInvariant()
    Write-Output $separator
}

function Format-StatusLine {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Status,

        [Parameter(Mandatory = $true)]
        [string]$Name,

        [Parameter(Mandatory = $true)]
        [string]$Detail
    )

    $statusLabel = "[{0}]" -f $Status.ToUpperInvariant()

    return ("{0,-11}{1,-30}: {2}" -f $statusLabel, $Name, $Detail)
}

function Invoke-GitCommand {
    param(
        [Parameter(Mandatory = $true)]
        [string]$RepoRoot,

        [Parameter(Mandatory = $true)]
        [string[]]$Arguments,

        [switch]$AllowFailure
    )

    if ($null -eq $gitCommand) {
        return $null
    }

    $global:LASTEXITCODE = 0
    $output = @(& $gitCommand.Source -C $RepoRoot @Arguments 2>$null)
    $exitCode = if ($null -ne $LASTEXITCODE) { $LASTEXITCODE } else { 0 }
    $global:LASTEXITCODE = 0

    if ($exitCode -ne 0) {
        if ($AllowFailure) {
            return $null
        }

        throw ("git command failed ({0}): git -C {1} {2}" -f $exitCode, $RepoRoot, ($Arguments -join ' '))
    }

    return $output
}

function Get-ChangedRepositoryPaths {
    param([string]$RepoRoot)

    if ($null -eq $gitCommand) {
        return @()
    }

    $paths = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)

    $statusLines = @(Invoke-GitCommand -RepoRoot $RepoRoot -Arguments @('status', '--porcelain') -AllowFailure)
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

    $candidateRefs = @()
    if (-not [string]::IsNullOrWhiteSpace($env:GITHUB_BASE_REF)) {
        $candidateRefs += @("origin/$($env:GITHUB_BASE_REF)", $env:GITHUB_BASE_REF)
    }
    $candidateRefs += @('origin/main', 'upstream/main', 'main')
    $candidateRefs = @($candidateRefs | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -Unique)

    foreach ($candidateRef in $candidateRefs) {
        $verifiedRef = Invoke-GitCommand -RepoRoot $RepoRoot -Arguments @('rev-parse', '--verify', $candidateRef) -AllowFailure
        if ($null -eq $verifiedRef) {
            continue
        }

        $diffPaths = @(Invoke-GitCommand -RepoRoot $RepoRoot -Arguments @('diff', '--name-only', "$candidateRef...HEAD") -AllowFailure)
        if ($null -eq $diffPaths) {
            continue
        }

        foreach ($diffPath in $diffPaths) {
            if (-not [string]::IsNullOrWhiteSpace($diffPath)) {
                [void]$paths.Add($diffPath.Replace('\', '/'))
            }
        }

        break
    }

    return @($paths | Sort-Object)
}

function Get-WorktreeChangedPaths {
    param([string]$RepoRoot)

    if ($null -eq $gitCommand) {
        return @()
    }

    $paths = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
    $statusLines = @(Invoke-GitCommand -RepoRoot $RepoRoot -Arguments @('status', '--porcelain') -AllowFailure)

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

    return @($paths | Sort-Object)
}

function Get-BranchDiffPaths {
    param([string]$RepoRoot)

    if ($null -eq $gitCommand) {
        return @()
    }

    $paths = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)

    $candidateRefs = @()
    if (-not [string]::IsNullOrWhiteSpace($env:GITHUB_BASE_REF)) {
        $candidateRefs += @("origin/$($env:GITHUB_BASE_REF)", $env:GITHUB_BASE_REF)
    }
    $candidateRefs += @('origin/main', 'upstream/main', 'main')
    $candidateRefs = @($candidateRefs | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -Unique)

    foreach ($candidateRef in $candidateRefs) {
        $verifiedRef = Invoke-GitCommand -RepoRoot $RepoRoot -Arguments @('rev-parse', '--verify', $candidateRef) -AllowFailure
        if ($null -eq $verifiedRef) {
            continue
        }

        $diffPaths = @(Invoke-GitCommand -RepoRoot $RepoRoot -Arguments @('diff', '--name-only', "$candidateRef...HEAD") -AllowFailure)
        if ($null -eq $diffPaths) {
            continue
        }

        foreach ($diffPath in $diffPaths) {
            if (-not [string]::IsNullOrWhiteSpace($diffPath)) {
                [void]$paths.Add($diffPath.Replace('\', '/'))
            }
        }

        break
    }

    return @($paths | Sort-Object)
}

function Resolve-ChangedRegressionScopePaths {
    param(
        [Parameter(Mandatory = $true)]
        [string]$RepoRoot,

        [Parameter(Mandatory = $true)]
        [string]$Scope
    )

    $worktreePaths = @(Get-WorktreeChangedPaths -RepoRoot $RepoRoot)
    $branchPaths = @(Get-BranchDiffPaths -RepoRoot $RepoRoot)

    switch ($Scope) {
        'Worktree' {
            return [pscustomobject]@{ scope = 'worktree'; paths = $worktreePaths }
        }

        'Branch' {
            return [pscustomobject]@{ scope = 'branch'; paths = $branchPaths }
        }

        'Combined' {
            $combined = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
            foreach ($path in @($worktreePaths + $branchPaths)) {
                [void]$combined.Add($path)
            }

            return [pscustomobject]@{ scope = 'combined'; paths = @($combined | Sort-Object) }
        }

        'Auto' {
            if ($worktreePaths.Count -gt 0) {
                return [pscustomobject]@{ scope = 'worktree'; paths = $worktreePaths }
            }

            return [pscustomobject]@{ scope = 'branch'; paths = $branchPaths }
        }
    }

    throw "unsupported changed regression scope '$Scope'"
}

function Get-ChangedRegressionCases {
    param(
        [Parameter(Mandatory = $true)]
        [string]$RepoRoot,

        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [string[]]$ChangedPaths
    )

    $caseIds = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)

    foreach ($changedPath in $ChangedPaths) {
        if ($changedPath -match '^tools/regression/cases/(?<id>[^/]+)\.json$') {
            [void]$caseIds.Add($Matches['id'])
            continue
        }

        if ($changedPath -match '^tools/regression/fixtures/(?<id>[^/]+)/') {
            [void]$caseIds.Add($Matches['id'])
            continue
        }

        if ($changedPath -match '^tools/regression/examples/(?<id>[^/]+)\.(result\.json|review\.md)$') {
            [void]$caseIds.Add($Matches['id'])
            continue
        }
    }

    $changedCases = @()
    foreach ($caseId in @($caseIds | Sort-Object)) {
        $caseRelativePath = "tools/regression/cases/$caseId.json"
        $caseFullPath = Join-Path $RepoRoot ($caseRelativePath.Replace('/', '\'))
        $resultRelativePath = "tools/regression/examples/$caseId.result.json"
        $resultFullPath = Join-Path $RepoRoot ($resultRelativePath.Replace('/', '\'))
        $reviewRelativePath = "tools/regression/examples/$caseId.review.md"
        $reviewFullPath = Join-Path $RepoRoot ($reviewRelativePath.Replace('/', '\'))

        $caseStatus = $null
        $task = $null
        if (Test-Path -LiteralPath $caseFullPath) {
            $caseDefinition = Get-Content -LiteralPath $caseFullPath -Raw | ConvertFrom-Json
            $caseStatus = [string]$caseDefinition.caseStatus
            $task = [string]$caseDefinition.task
        }

        $changedCases += [pscustomobject]@{
            id = $caseId
            task = $task
            casePath = $caseRelativePath
            casePathExists = (Test-Path -LiteralPath $caseFullPath)
            caseStatus = $caseStatus
            resultPath = $resultRelativePath
            resultPathExists = (Test-Path -LiteralPath $resultFullPath)
            reviewPath = $reviewRelativePath
            reviewPathExists = (Test-Path -LiteralPath $reviewFullPath)
        }
    }

    return @($changedCases)
}

Push-Location $repoRoot
try {
    if ($OutputFormat -eq 'Text') {
        Write-TextSectionHeader -Title 'AI toolkit validation'
    }

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

    $steps += Invoke-ValidationStep -Name 'changelog-taxonomy' -Detail 'Validate approved taxonomy prefixes for bullets under the Unreleased changelog section.' -Skipped:$SkipChangelog -Command {
        & pwsh -NoProfile -File $changelogTaxonomyScriptPath
    }

    $steps += Invoke-ValidationStep -Name 'changelog-consistency' -Detail 'Validate release footer links and the Unreleased compare link against the changelog release headings.' -Skipped:$SkipChangelog -Command {
        & pwsh -NoProfile -File $changelogConsistencyScriptPath
    }

    $steps += Invoke-ValidationStep -Name 'runtime-line-endings' -Detail 'Require LF line endings in manifest-managed AI Markdown and JSON files.' -Command {
        & $runtimeLineEndingsScriptPath -RuntimeRoot $repoRoot -ManifestPath $manifestPath
    }

    $steps += Invoke-ValidationStep -Name 'contracts' -Detail 'Validate AI-toolkit contracts, companion guidance, and consumer wiring.' -Command {
        & pwsh -NoProfile -File $contractsScriptPath
    }

    $steps += Invoke-ValidationStep -Name 'project-ready-utility' -Detail 'Run deterministic argument, help, output, and error regression tests for the AzureRM project readiness utility.' -Command {
        & pwsh -NoProfile -File $projectReadyTestScriptPath
    }

    $steps += Invoke-ValidationStep -Name 'changed-regression-cases' -Detail 'Confirm branch-local regression case changes are runnable with adjudicated example results, not merely schema-valid.' -Command {
        $scopeResolution = Resolve-ChangedRegressionScopePaths -RepoRoot $repoRoot -Scope $ChangedRegressionScope
        $changedCases = @(Get-ChangedRegressionCases -RepoRoot $repoRoot -ChangedPaths $scopeResolution.paths)

        if ($changedCases.Count -eq 0) {
            Write-Output ("No {0}-scoped regression case changes detected." -f $scopeResolution.scope)
            return
        }

        $errors = New-Object 'System.Collections.Generic.List[string]'
        foreach ($changedCase in $changedCases) {
            if (-not $changedCase.casePathExists) {
                $errors.Add("changed regression artifacts reference missing case file '$($changedCase.casePath)'")
                continue
            }

            if ($changedCase.caseStatus -ne 'adjudicated') {
                $errors.Add("changed regression case '$($changedCase.id)' is '$($changedCase.caseStatus)'; expected 'adjudicated' so the regression suite can score it")
            }

            if (-not $changedCase.resultPathExists) {
                $errors.Add("changed regression case '$($changedCase.id)' is missing adjudicated example result '$($changedCase.resultPath)'")
            }
        }

        if ($errors.Count -gt 0) {
            throw ($errors -join [Environment]::NewLine)
        }

        Write-Output ("Changed regression scope: {0}" -f $scopeResolution.scope)
        foreach ($changedCase in $changedCases) {
            Write-Output ("{0}: task={1}; status={2}; exampleResult={3}" -f $changedCase.id, $changedCase.task, $changedCase.caseStatus, $changedCase.resultPath)
        }
    }

    $steps += Invoke-ValidationStep -Name 'markdown' -Detail 'Lint .github, docs, and CHANGELOG markdown using the repo markdownlint configuration.' -Command {
        if ($null -eq $npxCommand) {
            throw 'npx was not found on PATH'
        }

        & $npxCommand.Source -y markdownlint-cli2 '.github/**/*.md' 'docs/**/*.md' 'CHANGELOG.md' --config '.github/.markdownlint.json'
    }

    $steps += Invoke-ValidationStep -Name 'architecture-layout' -Detail 'Validate the System Architecture diagram row width, right edge, and border padding.' -Command {
        & pwsh -NoProfile -File $architectureLayoutScriptPath
    }

    $steps += Invoke-ValidationStep -Name 'release-boundaries' -Detail 'Validate that release dry-run output defaults outside the AI source repository and rejects source-tree or persistent-installer roots.' -Command {
        $defaultOutput = @(& pwsh -NoProfile -File $releaseBundleScriptPath -Version '0.0.0-validation' -ValidateOutputRootOnly 2>&1)
        if ($LASTEXITCODE -ne 0) {
            throw "default release output boundary validation failed: $($defaultOutput -join [Environment]::NewLine)"
        }

        $sourceProbePath = Join-Path $repoRoot '.release-boundary-validation-probe'
        if (Test-Path -LiteralPath $sourceProbePath) {
            throw "release boundary probe path already exists: $sourceProbePath"
        }

        $sourceOutput = @(& pwsh -NoProfile -File $releaseBundleScriptPath -Version '0.0.0-validation' -OutputRoot $sourceProbePath -ValidateOutputRootOnly 2>&1)
        if ($LASTEXITCODE -eq 0 -or ($sourceOutput | Out-String) -notmatch 'outside the AI source repository') {
            throw 'release bundle builder did not reject an OutputRoot inside the AI source repository'
        }
        if (Test-Path -LiteralPath $sourceProbePath) {
            throw "release boundary validation wrote inside the AI source repository: $sourceProbePath"
        }

        $persistentInstallerRoot = Join-Path ([Environment]::GetFolderPath([Environment+SpecialFolder]::UserProfile)) '.terraform-azurerm-ai-installer'
        $profileOutput = @(& pwsh -NoProfile -File $releaseBundleScriptPath -Version '0.0.0-validation' -OutputRoot $persistentInstallerRoot -ValidateOutputRootOnly 2>&1)
        if ($LASTEXITCODE -eq 0 -or ($profileOutput | Out-String) -notmatch 'must not use the persistent user-profile installer') {
            throw 'release bundle builder did not reject the persistent user-profile installer as OutputRoot'
        }

        $global:LASTEXITCODE = 0
    }

    $steps += Invoke-ValidationStep -Name 'copied-markdown-links' -Detail 'Validate that links copied from the pull request template remain valid outside their source file.' -Command {
        & pwsh -NoProfile -File $copiedMarkdownLinksScriptPath
    }

    $steps += Invoke-ValidationStep -Name 'regression-harness' -Detail 'Run the regression harness validation, suite scoring, and history snapshot flow.' -Skipped:$SkipRegressionHarness -RelayStatusOutput -Command {
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

    $steps += Invoke-ValidationStep -Name 'upstream-drift' -Detail 'Check tracked upstream contributor guidance drift and explicit topic coverage.' -Skipped:$SkipUpstreamDrift -RelayStatusOutput -Command {
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
            changelogConsistencyStatus = @($steps | Where-Object { $_.name -eq 'changelog-consistency' })[0].status
            changedRegressionCasesStatus = @($steps | Where-Object { $_.name -eq 'changed-regression-cases' })[0].status
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
        Write-TextSectionHeader -Title 'AI toolkit validation summary'
        Write-Output "  Overall Status   : $($summary.overallStatus.ToUpperInvariant())"
        Write-Output "  Repository Root  : $repoRoot"

        Write-TextSectionHeader -Title 'Validation steps'
        Write-Output ("  {0,-32} {1,-10} {2,10}" -f 'STEP', 'STATUS', 'DURATION')
        Write-Output ("  {0,-32} {1,-10} {2,10}" -f ('-' * 32), ('-' * 10), ('-' * 10))
        foreach ($step in $steps) {
            Write-Output ("  {0,-32} {1,-10} {2,10}" -f $step.name, $step.status.ToUpperInvariant(), ("{0}s" -f $step.durationSeconds))
        }

        Write-TextSectionHeader -Title 'Highlights'
        if ($null -ne $summary.highlights.changelogStatus) {
            Write-Output "  Changelog Status         : $($summary.highlights.changelogStatus.ToUpperInvariant())"
        }
        $changelogTaxonomyStep = @($steps | Where-Object { $_.name -eq 'changelog-taxonomy' })[0]
        if ($null -ne $changelogTaxonomyStep) {
            Write-Output "  Changelog Taxonomy       : $($changelogTaxonomyStep.status.ToUpperInvariant())"
        }
        if ($null -ne $summary.highlights.changelogConsistencyStatus) {
            Write-Output "  Changelog Consistency    : $($summary.highlights.changelogConsistencyStatus.ToUpperInvariant())"
        }
        if ($null -ne $summary.highlights.changedRegressionCasesStatus) {
            Write-Output "  Changed Regression Cases : $($summary.highlights.changedRegressionCasesStatus.ToUpperInvariant())"
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
            Write-TextSectionHeader -Title 'Failures'
            foreach ($failedStep in @($steps | Where-Object { -not $_.success })) {
                Write-Output ("  {0}" -f (Format-StatusLine -Status 'failed' -Name $failedStep.name -Detail ("exit code {0}" -f $failedStep.exitCode)))
                if (-not [string]::IsNullOrWhiteSpace($failedStep.detail)) {
                    Write-Output "    $($failedStep.detail)"
                }
                if (-not [string]::IsNullOrWhiteSpace($failedStep.output)) {
                    Write-Output $failedStep.output
                }
            }
        }

        Write-Output ''
    }

    if (-not $overallSuccess) {
        exit 1
    }
}
finally {
    Pop-Location
}
