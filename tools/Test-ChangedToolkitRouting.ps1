[CmdletBinding()]
param(
    [ValidateSet('Text', 'Json')]
    [string]$OutputFormat = 'Text'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$dispatcherPath = Join-Path $PSScriptRoot 'Validate-ChangedToolkits.ps1'
$workflowPath = Join-Path $PSScriptRoot '../.github/workflows/contracts-validation.yml'
$validationOutputModulePath = Join-Path $PSScriptRoot 'ValidationOutput.psm1'
$agentsPath = Join-Path $PSScriptRoot '../AGENTS.md'
$toolkitMaintenanceSkillPath = Join-Path $PSScriptRoot '../.github/skills/ai-toolkit-maintenance/SKILL.md'
$changelogMaintenanceSkillPath = Join-Path $PSScriptRoot '../.github/skills/changelog-maintenance/SKILL.md'
$npmSecurityPath = Join-Path $PSScriptRoot 'Test-NpmSecurity.ps1'
$interactiveValidationPath = Join-Path $PSScriptRoot 'validate-ai-toolkit.ps1'
$hostedWorkbenchTestPath = Join-Path $PSScriptRoot '../hosted_copilot/tools/tests/Test-RuleWorkbench.ps1'
$interactiveManifestPath = Join-Path $PSScriptRoot '../installer/file-manifest.config'
$hostedManifestPath = Join-Path $PSScriptRoot '../hosted_copilot/tools/package-manifest.json'
$releaseBuilderPath = Join-Path $PSScriptRoot 'build-release-bundle_dry_run.ps1'
$issues = New-Object 'System.Collections.Generic.List[string]'
$results = New-Object 'System.Collections.Generic.List[object]'

$dispatcherContent = Get-Content -LiteralPath $dispatcherPath -Raw
$workflowContent = Get-Content -LiteralPath $workflowPath -Raw
$agentsContent = Get-Content -LiteralPath $agentsPath -Raw
$toolkitMaintenanceSkillContent = Get-Content -LiteralPath $toolkitMaintenanceSkillPath -Raw
$changelogMaintenanceSkillContent = Get-Content -LiteralPath $changelogMaintenanceSkillPath -Raw
$npmSecurityContent = Get-Content -LiteralPath $npmSecurityPath -Raw
$interactiveValidationContent = Get-Content -LiteralPath $interactiveValidationPath -Raw
$hostedWorkbenchTestContent = Get-Content -LiteralPath $hostedWorkbenchTestPath -Raw
$interactiveManifestContent = Get-Content -LiteralPath $interactiveManifestPath -Raw
$releaseBuilderContent = Get-Content -LiteralPath $releaseBuilderPath -Raw
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
    $dispatcherContent -match '\[switch\]\$SkipHostedUpstreamDrift' -and
    $dispatcherContent -match 'if \(\$SkipHostedUpstreamDrift\) \{ \$hostedArguments \+= ''-SkipUpstreamDrift'' \}' -and
    $dispatcherContent -match 'Invoke-ProfileValidator -Name ''Hosted Toolkit'' -Path \$hostedValidatorPath -Arguments \$hostedArguments' -and
    $dispatcherContent -match 'Complete-ValidationTextOutput'
if (-not $relayContractPresent) {
    $issues.Add('dispatcher text mode must relay child execution states and consume the shared validation presentation contract without local formatter copies')
}

$ciDriftRoutingPresent = [regex]::Matches($workflowContent, 'Validate-ChangedToolkits\.ps1[^\r\n]*-SkipInteractiveUpstreamDrift[^\r\n]*-SkipHostedUpstreamDrift').Count -eq 1 -and
    $workflowContent -match 'ChangedPaths\s*=\s*\$changedPaths' -and
    $workflowContent -match 'SkipInteractiveRegressionHarness\s*=\s*\$true' -and
    $workflowContent -match 'SkipInteractiveUpstreamDrift\s*=\s*\$true' -and
    $workflowContent -match 'SkipHostedUpstreamDrift\s*=\s*\$true' -and
    $workflowContent -match 'Validate-ChangedToolkits\.ps1 @validationParameters' -and
    [regex]::Matches($workflowContent, 'Validate-InteractiveToolkit\.ps1[^\r\n]*-SkipUpstreamDrift').Count -eq 1 -and
    [regex]::Matches($workflowContent, 'hosted_copilot/tools/Test-HostedRules\.ps1[^\r\n]*-SkipUpstreamDrift').Count -eq 1
if (-not $ciDriftRoutingPresent) {
    $issues.Add('required CI must skip both live upstream drift audits in pull-request, push, and workflow-dispatch validation paths')
}

$productBoundaryPresent = $agentsContent -match 'Only the Interactive Toolkit may build a versioned release bundle, archive, or published release' -and
    $agentsContent -match 'Hosted Workbench assessment or display bundle as ephemeral local workflow data' -and
    $agentsContent -match 'Do not invoke Interactive review agents or workflows' -and
    $toolkitMaintenanceSkillContent -match '(?m)^## Scope-First Routing$' -and
    $toolkitMaintenanceSkillContent -match 'hosted_copilot/\.github/\*\*.*Hosted deployment payload' -and
    $toolkitMaintenanceSkillContent -match 'Use `Test-HostedRules\.ps1` for complete Hosted validation' -and
    $toolkitMaintenanceSkillContent -match 'Normal Hosted validation must not read the live Interactive catalog' -and
    $toolkitMaintenanceSkillContent -match 'Only Interactive maintenance may create versioned release bundles' -and
    $changelogMaintenanceSkillContent -match 'For Hosted-only work, read and edit only `hosted_copilot/CHANGELOG\.md`' -and
    $changelogMaintenanceSkillContent -match 'do not load root `CHANGELOG\.md` or run Interactive release preparation' -and
    $npmSecurityContent -match '\[string\[\]\]\$LockPath' -and
    $interactiveValidationContent -match "'-LockPath',\s*'tools/npm-validation/package-lock\.json'" -and
    $hostedWorkbenchTestContent.Contains("'-LockPath', `$nodePackageLockRelativePath")
if (-not $productBoundaryPresent) {
    $issues.Add('shared maintainer guidance and npm validation must preserve independent Interactive release and Hosted local-source workflows')
}

$interactiveReleaseIsolated = $interactiveManifestContent -notmatch '(?m)^\s*hosted_copilot/' -and
    $releaseBuilderContent -match 'Interactive release manifest contains Hosted Toolkit paths'
if (-not $interactiveReleaseIsolated) {
    $issues.Add('Interactive release packaging must reject every Hosted Toolkit path')
}
$results.Add([pscustomobject]@{
    name = 'interactive-release-excludes-hosted'
    status = if ($interactiveReleaseIsolated) { 'passed' } else { 'failed' }
    validators = @('Interactive Toolkit')
    repositoryChecks = $true
})

$hostedOverlayIsolated = $false
try {
    $hostedManifest = Get-Content -LiteralPath $hostedManifestPath -Raw | ConvertFrom-Json -ErrorAction Stop
    $hostedOverlayIsolated = [string]$hostedManifest.packageIdentity -ceq 'terraform-azurerm-hosted-copilot' -and
        [string]$hostedManifest.installedStatePath -ceq '.github/hosted-copilot-installed-state.json' -and
        @($hostedManifest.files).Count -gt 0 -and
        @($hostedManifest.files | Where-Object { [string]$_ -like 'hosted_copilot/*' -or ([string]$_ -notlike '.github/*' -and [string]$_ -cne 'docs/HOSTED_COPILOT_CODE_REVIEW.md') }).Count -eq 0
}
catch {
    $hostedOverlayIsolated = $false
}
if (-not $hostedOverlayIsolated) {
    $issues.Add('Hosted deployment manifest must contain only target-relative Hosted overlay paths')
}
$results.Add([pscustomobject]@{
    name = 'hosted-overlay-isolated'
    status = if ($hostedOverlayIsolated) { 'passed' } else { 'failed' }
    validators = @('Hosted Toolkit')
    repositoryChecks = $true
})

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
        name = 'interactive-runtime-instructions'
        paths = @('.github/copilot-instructions.md')
        validators = @('Interactive Toolkit')
        repositoryChecks = $false
        ownership = 'interactive'
        pattern = '.github/**'
    },
    [pscustomobject]@{
        name = 'hosted-only'
        paths = @('hosted_copilot/CHANGELOG.md')
        validators = @('Hosted Toolkit')
        repositoryChecks = $false
    },
    [pscustomobject]@{
        name = 'hosted-deployment-instructions'
        paths = @('hosted_copilot/.github/copilot-instructions.md')
        validators = @('Hosted Toolkit')
        repositoryChecks = $false
        ownership = 'hosted'
        pattern = 'hosted_copilot/.github/**'
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
        name = 'shared-npm-security'
        paths = @('tools/Test-NpmSecurity.ps1', 'tools/npm-validation/package-lock.json')
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
    $expectedOwnership = if ($case.PSObject.Properties['ownership']) { [string]$case.ownership } else { '<not constrained>' }
    $expectedPattern = if ($case.PSObject.Properties['pattern']) { [string]$case.pattern } else { '<not constrained>' }
    $ownershipMatch = $expectedOwnership -ceq '<not constrained>' -or ([string]$result.classifications[0].ownership -ceq $expectedOwnership -and [string]$result.classifications[0].pattern -ceq $expectedPattern)
    $passed = $result.status -eq 'planned' -and $validatorsMatch -and $repositoryChecksMatch -and $ownershipMatch -and $result.unknownPaths.Count -eq 0

    if (-not $passed) {
        $issues.Add(("{0}: expected validators [{1}], repositoryChecks={2}, ownership={3}, and pattern={4}; found validators [{5}], repositoryChecks={6}, ownership={7}, pattern={8}, status={9}" -f $case.name, ($expectedValidators -join ', '), $case.repositoryChecks, $expectedOwnership, $expectedPattern, ($actualValidators -join ', '), $result.repositoryChecksRequired, $result.classifications[0].ownership, $result.classifications[0].pattern, $result.status))
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
    name = 'unclassified-path-fails-closed'
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
