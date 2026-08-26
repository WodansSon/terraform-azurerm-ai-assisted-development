[CmdletBinding()]
param(
    [ValidateSet('Text', 'Json')]
    [string]$OutputFormat = 'Text'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$dispatcherPath = Join-Path $PSScriptRoot 'Validate-ChangedToolkits.ps1'
$issues = New-Object 'System.Collections.Generic.List[string]'
$results = New-Object 'System.Collections.Generic.List[object]'

$cases = @(
    [pscustomobject]@{
        name = 'interactive-only'
        paths = @('installer/file-manifest.config')
        validators = @('Interactive Toolkit')
        repositoryChecks = $false
    },
    [pscustomobject]@{
        name = 'hosted-only'
        paths = @('hosted_copilot/tools/hosted-copilot/CHANGELOG.md')
        validators = @('Hosted Toolkit')
        repositoryChecks = $false
    },
    [pscustomobject]@{
        name = 'hosted-architecture'
        paths = @('docs/HOSTED_COPILOT_CODE_REVIEW_ARCHITECTURE.md')
        validators = @('Hosted Toolkit')
        repositoryChecks = $false
    },
    [pscustomobject]@{
        name = 'mixed'
        paths = @('installer/file-manifest.config', 'hosted_copilot/tools/hosted-copilot/CHANGELOG.md')
        validators = @('Interactive Toolkit', 'Hosted Toolkit')
        repositoryChecks = $false
    },
    [pscustomobject]@{
        name = 'shared'
        paths = @('.github/.markdownlint.json')
        validators = @('Interactive Toolkit', 'Hosted Toolkit')
        repositoryChecks = $true
    },
    [pscustomobject]@{
        name = 'repository-maintenance'
        paths = @('AGENTS.md')
        validators = @()
        repositoryChecks = $true
    },
    [pscustomobject]@{
        name = 'repository-maintenance-skills'
        paths = @(
            '.github/skills/ai-toolkit-maintenance/SKILL.md',
            '.github/skills/changelog-maintenance/SKILL.md'
        )
        validators = @()
        repositoryChecks = $true
    }
)

foreach ($case in $cases) {
    $json = & $dispatcherPath -OutputFormat Json -PlanOnly -ChangedPaths $case.paths
    $result = $json | ConvertFrom-Json
    $actualValidators = @($result.requiredValidators)
    $expectedValidators = @($case.validators)
    $validatorsMatch = ($actualValidators.Count -eq $expectedValidators.Count) -and (($actualValidators -join '|') -eq ($expectedValidators -join '|'))
    $repositoryChecksMatch = [bool]$result.repositoryChecksRequired -eq [bool]$case.repositoryChecks
    $passed = $result.status -eq 'planned' -and $validatorsMatch -and $repositoryChecksMatch -and $result.unknownPaths.Count -eq 0

    if (-not $passed) {
        $issues.Add(("{0}: expected validators [{1}] and repositoryChecks={2}, found validators [{3}], repositoryChecks={4}, status={5}" -f $case.name, ($expectedValidators -join ', '), $case.repositoryChecks, ($actualValidators -join ', '), $result.repositoryChecksRequired, $result.status))
    }

    $results.Add([pscustomobject]@{
        name = $case.name
        status = if ($passed) { 'passed' } else { 'failed' }
        validators = $actualValidators
        repositoryChecks = [bool]$result.repositoryChecksRequired
    })
}

$global:LASTEXITCODE = 0
$unknownJson = @(& pwsh -NoProfile -File $dispatcherPath -OutputFormat Json -PlanOnly -ChangedPaths 'unclassified/example.txt' 2>&1)
$unknownExitCode = if ($null -ne $LASTEXITCODE) { $LASTEXITCODE } else { 0 }
$unknownResult = ($unknownJson | Out-String).Trim() | ConvertFrom-Json
$unknownPassed = $unknownExitCode -ne 0 -and $unknownResult.status -eq 'failed' -and $unknownResult.unknownPaths.Count -eq 1

if (-not $unknownPassed) {
    $issues.Add("unknown: expected a failed plan with one unclassified path, found exitCode=$unknownExitCode, status=$($unknownResult.status), unknownPaths=$($unknownResult.unknownPaths.Count)")
}

$results.Add([pscustomobject]@{
    name = 'unknown'
    status = if ($unknownPassed) { 'passed' } else { 'failed' }
    validators = @($unknownResult.requiredValidators)
    repositoryChecks = [bool]$unknownResult.repositoryChecksRequired
})

$summary = [ordered]@{
    status = if ($issues.Count -eq 0) { 'passed' } else { 'failed' }
    caseCount = $results.Count
    results = @($results.ToArray())
    issueCount = $issues.Count
    issues = @($issues.ToArray())
}

if ($OutputFormat -eq 'Json') {
    $summary | ConvertTo-Json -Depth 10
}
else {
    Write-Output 'Changed Toolkit routing test summary'
    Write-Output ("  Status     : {0}" -f $summary.status.ToUpperInvariant())
    Write-Output ("  Cases      : {0}" -f $summary.caseCount)
    Write-Output ("  Issue Count: {0}" -f $summary.issueCount)
    Write-Output ''

    foreach ($result in $results) {
        Write-Output ("  [{0}] {1}" -f $result.status.ToUpperInvariant(), $result.name)
    }

    if ($issues.Count -gt 0) {
        Write-Output ''
        Write-Output 'Issues'
        foreach ($issue in $issues) {
            Write-Output "  - $issue"
        }
    }
}

if ($issues.Count -gt 0) {
    exit 1
}
