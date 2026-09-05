[CmdletBinding()]
param(
    [ValidateSet('Text', 'Json')]
    [string]$OutputFormat = 'Text'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$dispatcherPath = Join-Path $PSScriptRoot 'Validate-ChangedToolkits.ps1'
$validationOutputModulePath = Join-Path $PSScriptRoot 'ValidationOutput.psm1'
$issues = New-Object 'System.Collections.Generic.List[string]'
$results = New-Object 'System.Collections.Generic.List[object]'

$dispatcherContent = Get-Content -LiteralPath $dispatcherPath -Raw
$relayContractPresent = $dispatcherContent -match '\$childOutputFormat = if \(\$OutputFormat -eq ''Text''\)' -and
    $dispatcherContent -match '\^\\s\*\\\[\(RUNNING\|PASSED\|FAILED\|SKIPPED\)\\\]' -and
    $dispatcherContent -match 'Write-Host \(Add-ValidationIndent -Line \(\[string\]\$_\)\)' -and
    $dispatcherContent -match 'validator/\{0\}' -and
    $dispatcherContent -match '\$durationSeconds = \[Math\]::Round' -and
    $dispatcherContent -match 'Import-Module -Name \$validationOutputModulePath -Force' -and
    $dispatcherContent -notmatch 'function Write-TextSectionHeader' -and
    $dispatcherContent -notmatch 'function Format-StatusLine' -and
    $dispatcherContent -match "Write-ValidationSectionHeader -Title 'Changed Toolkit validation'" -and
    $dispatcherContent -match "Write-ValidationSectionHeader -Title 'Changed Toolkit validation summary'" -and
    $dispatcherContent -match "Write-ValidationSectionHeader -Title 'Classifications'" -and
    $dispatcherContent -match "Write-ValidationSectionHeader -Title 'Executions'" -and
    $dispatcherContent -match 'Write-ValidationSummary -Fields' -and
    $dispatcherContent -match 'Write-ValidationStatusTable -Rows .* -NameHeader ''VALIDATOR'' -NameWidth 24' -and
    $dispatcherContent -notmatch 'Write-ValidationStatusTable -Rows .* -TotalDuration' -and
    $dispatcherContent -match "Write-ValidationSectionHeader -Title 'Execution failures'" -and
    $dispatcherContent -match 'Write-ValidationTwoColumnTable -Rows' -and
    $dispatcherContent -match 'Complete-ValidationTextOutput'
if (-not $relayContractPresent) {
    $issues.Add('dispatcher text mode must relay child execution states and consume the shared validation presentation contract without local formatter copies')
}

if (-not (Test-Path -LiteralPath $validationOutputModulePath -PathType Leaf)) {
    $issues.Add('shared validation output module is missing')
}

$textOutput = @(& $dispatcherPath -PlanOnly -ChangedPaths 'hosted_copilot/CHANGELOG.md')
$classificationIndex = [Array]::IndexOf($textOutput, 'CLASSIFICATIONS')
$classificationSpacingPassed = $classificationIndex -ge 0 -and
    $classificationIndex + 3 -lt $textOutput.Count -and
    [string]$textOutput[$classificationIndex + 1] -eq ('-' * 51) -and
    [string]$textOutput[$classificationIndex + 2] -eq '' -and
    [string]$textOutput[$classificationIndex + 3] -match '^\s+OWNERSHIP\s+PATH$'
$textFormatPassed = $textOutput.Count -gt 0 -and
    [string]$textOutput[0] -eq '' -and
    [string]$textOutput[-1] -eq '' -and
    $textOutput -contains ('-' * 51) -and
    $textOutput -contains 'CHANGED TOOLKIT VALIDATION SUMMARY' -and
    $classificationSpacingPassed
if (-not $textFormatPassed) {
    $issues.Add('dispatcher text output must begin and end with blank lines, use standard section headers, and separate the classifications header from its table')
}

$cases = @(
    [pscustomobject]@{
        name = 'interactive-only'
        paths = @('installer/file-manifest.config')
        validators = @('Interactive Toolkit')
        repositoryChecks = $false
    },
    [pscustomobject]@{
        name = 'hosted-only'
        paths = @('hosted_copilot/CHANGELOG.md')
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
        paths = @('installer/file-manifest.config', 'hosted_copilot/CHANGELOG.md')
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
        name = 'shared-validation-output'
        paths = @('tools/ValidationOutput.psm1', 'tools/Test-ValidationOutput.ps1')
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
        name = 'codeowners'
        paths = @('.github/CODEOWNERS')
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
    Write-ValidationSectionHeader -Title 'Changed Toolkit routing test summary'
    Write-ValidationSummary -Fields ([ordered]@{
        Status = $summary.status.ToUpperInvariant()
        Cases = $summary.caseCount
        'Issue Count' = $summary.issueCount
    })

    Write-ValidationSectionHeader -Title 'Routing cases'
    Write-ValidationTwoColumnTable -Rows @($results.ToArray()) -FirstHeader 'status' -FirstProperty 'status' -SecondHeader 'case' -SecondProperty 'name' -UppercaseFirst

    if ($issues.Count -gt 0) {
        Write-ValidationSectionHeader -Title 'Issues'
        foreach ($issue in $issues) {
            Write-Output "  - $issue"
        }
    }
    Complete-ValidationTextOutput
}

if ($issues.Count -gt 0) {
    exit 1
}
