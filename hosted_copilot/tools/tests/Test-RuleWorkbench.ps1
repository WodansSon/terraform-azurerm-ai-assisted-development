[CmdletBinding()]
param(
    [string]$Run,

    [string[]]$Journey = @('all'),

    [switch]$Headed,

    [ValidateRange(0, 2000)]
    [int]$SlowMo = 0,

    [ValidateSet('Text', 'Json')]
    [string]$OutputFormat = 'Text',

    [switch]$FixNpmAudit,

    [switch]$AllowBreakingNpmFix,

    [switch]$ContinueAfterNpmAuditFailure
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$validationOutputModulePath = Join-Path $PSScriptRoot '../../../tools/ValidationOutput.psm1'
Import-Module -Name $validationOutputModulePath -Force

$repositoryRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))
$toolsRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$workbenchRoot = Join-Path $PSScriptRoot '../../workbench'
$iconRoot = Join-Path $workbenchRoot 'icons'
$codiconRoot = Join-Path $iconRoot 'codicons'
$octiconRoot = Join-Path $iconRoot 'octicons'
$fluentIconRoot = Join-Path $iconRoot 'fluent'
$llmIconRoot = Join-Path $iconRoot 'llms'
$iconGeneratorPath = Join-Path $PSScriptRoot '../internal/workbench/New-WorkbenchCodiconSprite.ps1'
$octiconGeneratorPath = Join-Path $PSScriptRoot '../internal/workbench/New-WorkbenchOcticonSprite.ps1'
$fluentIconGeneratorPath = Join-Path $PSScriptRoot '../internal/workbench/New-WorkbenchFluentIconSprite.ps1'
$llmIconGeneratorPath = Join-Path $PSScriptRoot '../internal/workbench/New-WorkbenchLlmIconSprite.ps1'
$iconPreviewPath = Join-Path $PSScriptRoot '../internal/workbench/WorkbenchIconPreview.ps1'
$iconPreviewRendererPath = Join-Path $PSScriptRoot '../Render-WorkbenchIconPreview.cjs'
$launcherPath = Join-Path $PSScriptRoot '../Start-RuleWorkbench.ps1'
$metadataEvaluatorPath = Join-Path $PSScriptRoot 'fixtures/copilot-metadata-evaluator.ps1'
$hostedGitHubHelpersPath = Join-Path $PSScriptRoot '../modules/shared/HostedGitHub.Helpers.psm1'
$workbenchGitHubContextPath = Join-Path $PSScriptRoot '../modules/workbench/Workbench.GitHubContext.psm1'
$loopbackServerPath = Join-Path $PSScriptRoot '../internal/workbench/Start-WorkbenchLoopbackServer.ps1'
$manualRelationshipPath = Join-Path $PSScriptRoot '../internal/reconciliation/Invoke-ManualRuleRelationship.ps1'
$manualRelationshipEvaluatorPath = Join-Path $PSScriptRoot 'fixtures/manual-relationship-evaluator.ps1'
$adjudicationEvaluatorPath = Join-Path $PSScriptRoot 'fixtures/rule-issue-adjudication-evaluator.ps1'
$workbenchRegressionRoot = Join-Path $PSScriptRoot '../../regression/workbench'
$behaviorManifestPath = Join-Path $workbenchRegressionRoot 'behavior-manifest.json'
$behaviorManifestSchemaPath = Join-Path $workbenchRegressionRoot '../../contracts/workbench/behavior-manifest.schema.json'
$playwrightRunnerPath = Join-Path $workbenchRegressionRoot 'playwright/run.cjs'
$layoutTestPath = Join-Path $workbenchRegressionRoot 'puppeteer/Test-RuleWorkbenchLayout.cjs'
$implementationContractPath = Join-Path $PSScriptRoot '../../docs/HOSTED_COPILOT_CODE_REVIEW_IMPLEMENTATION.md'
$nodePackageManifestPath = Join-Path $toolsRoot 'package.json'
$nodePackageLockPath = Join-Path $toolsRoot 'package-lock.json'
$nodeInstalledLockPath = Join-Path $toolsRoot 'node_modules/.package-lock.json'
$nodePackageLockRelativePath = 'hosted_copilot/tools/package-lock.json'
$npmSecurityScriptPath = Join-Path $repositoryRoot 'tools/Test-NpmSecurity.ps1'
$puppeteerCliRelativePath = if ($IsWindows) { 'node_modules/.bin/puppeteer.cmd' } else { 'node_modules/.bin/puppeteer' }
$puppeteerCliPath = Join-Path $toolsRoot $puppeteerCliRelativePath
$displaySchemaPath = Join-Path $PSScriptRoot '../../contracts/workbench/workbench-display-v4.schema.json'
$ruleIssuesSchemaPath = Join-Path $PSScriptRoot '../../contracts/workbench/workbench-rule-issues-v4.schema.json'
$results = New-Object 'System.Collections.Generic.List[object]'
$issues = New-Object 'System.Collections.Generic.List[string]'
$testStartTimes = @{}
$dependencyAuditFindings = New-Object 'System.Collections.Generic.List[object]'
$dependencyAuditCounts = $null
$dependencyAuditError = $null
$dependencyAuditInconclusive = $false
$dependencyAuditContinuation = $false
$failureAlreadyReported = $false
$npmFixApplied = $false
$npmFixRequiresBreaking = $false
$npmFixChanges = New-Object 'System.Collections.Generic.List[string]'
$tempRoot = Join-Path ([IO.Path]::GetTempPath()) ("hosted-rule-workbench-test-" + [guid]::NewGuid().ToString('N'))
$mandatoryTestNames = @('npm audit', 'npm-packages', 'run-selection')
$browserRuntimeTestNames = @('locked-browser-runtime', 'portable-icon-generation', 'browser-playwright-journeys', 'browser-viewport-layout', 'browser-framework-coverage')
$serverTestNames = @('loopback-host-validation', 'server-owned-runtime-config', 'browser-playwright-journeys', 'browser-viewport-layout', 'browser-framework-coverage', 'authenticated-server-shutdown')
$staticTestNames = @(
    'rule-assistance',
    'saved-rule-evaluation',
    'saved-rule-wording-review',
    'saved-rule-consolidation',
    'relationship-check-cancellation',
    'relationship-check-responsiveness',
    'fixture-display-valid',
    'assessment-factor-range',
    'local-icon-family-sprites',
    'portable-icon-generation',
    'browser-state-contract',
    'tooltip-sentence-case',
    'statusbar-tooltip-title-case',
    'browser-behavior-manifest',
    'browser-timestamp-normalization',
    'repository-identity-presentation',
    'promotion-plan-activity-badge',
    'row-keyboard-navigation',
    'assessment-results-audit',
    'assessment-results-sorting',
    'shared-presentation-utilities',
    'assessment-pane-navigation',
    'maintainer-applicability-override',
    'current-bundle-assessment-ownership',
    'dark-theme-contract',
    'global-typography-contract',
    'component-typography-consistency',
    'scrollbar-theme-contract',
    'ide-shell-contract',
    'preview-editor-layout',
    'preview-artifact-tree-stability',
    'contained-view-scrolling',
    'impact-factor-guidance',
    'detail-presentation-contract',
    'static-information-colors',
    'evaluated-source-tree',
    'contributor-document-children',
    'candidate-header-tooltips',
    'tree-leaf-direct-updates',
    'catalog-status-rule-actions',
    'bulk-plan-membership',
    'undo-updates-capacity-projection',
    'semantic-color-contract',
    'error-banner-style-contract',
    'clickable-cursor-affordance',
    'button-component-contract',
    'promotion-plan-attention-filter',
    'rule-issue-recommendation-staging',
    'rule-issue-tab-pagination',
    'promotion-plan-column-alignment',
    'promotion-plan-detail-routing',
    'promotion-plan-token-deltas',
    'protected-preview-files',
    'preview-approval-export',
    'preview-change-review',
    'raw-payload-change-navigation',
    'no-op-update-suppression',
    'mobile-unsupported-contract',
    'incremental-assessment-launch',
    'assistance-waiting-phrase-staging',
    'internal-stage-status-boundary',
    'loopback-read-only-server',
    'repository-staging-rejected'
)
$supportedFocusedRuns = @($mandatoryTestNames + $staticTestNames + $serverTestNames + $browserRuntimeTestNames | Where-Object { $_ -ne 'run-selection' } | Sort-Object -Unique)
$testScriptContent = Get-Content -LiteralPath $PSCommandPath -Raw
$declaredTestNames = @([regex]::Matches($testScriptContent, "Add-TestResult\s+-Name\s+'(?<name>[^']+)'") | ForEach-Object { [string]$_.Groups['name'].Value } | Sort-Object -Unique)
$missingFocusedRuns = @($declaredTestNames | Where-Object { $_ -ne 'run-selection' -and $_ -notin $supportedFocusedRuns })
$unknownFocusedRuns = @($supportedFocusedRuns | Where-Object { $_ -notin $declaredTestNames })
$journeyNames = @($Journey | ForEach-Object { @([string]$_ -split ',') } | ForEach-Object { $_.Trim() } | Where-Object { $_ } | Sort-Object -Unique)
$invalidJourneyNames = @($journeyNames | Where-Object { $_ -notmatch '^(all|[a-z0-9-]+)$' })
if ($journeyNames.Count -eq 0 -or $invalidJourneyNames.Count -gt 0) {
    throw "-Journey contains invalid names: $($invalidJourneyNames -join ', ')"
}
if ('all' -in $journeyNames -and $journeyNames.Count -gt 1) {
    throw '-Journey cannot combine `all` with named journeys'
}
$runAllJourneys = $journeyNames.Count -eq 1 -and $journeyNames[0] -eq 'all'

if (-not $runAllJourneys -and $Run -ne 'browser-playwright-journeys') {
    throw '-Journey requires -Run browser-playwright-journeys'
}

function Test-ShouldRun {
    param([Parameter(Mandatory = $true)][string]$Name)

    return [string]::IsNullOrWhiteSpace($Run) -or $Run -eq $Name -or $Name -in $mandatoryTestNames
}

function Start-TestResult {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [string]$RunningDetail = 'IN PROGRESS'
    )

    if (-not (Test-ShouldRun -Name $Name)) {
        return
    }
    $testStartTimes[$Name] = Get-Date
    if ($OutputFormat -eq 'Text') {
        Write-Host (Format-ValidationStatusLine -Status 'running' -Name $Name -Detail $RunningDetail)
    }
}

function Add-TestResult {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][bool]$Passed,
        [Parameter(Mandatory = $true)][string]$Detail,
        [string]$SuccessDetail
    )

    if (-not (Test-ShouldRun -Name $Name)) {
        return
    }
    $durationSeconds = 0
    if ($testStartTimes.ContainsKey($Name)) {
        $durationSeconds = ((Get-Date) - $testStartTimes[$Name]).TotalSeconds
        $testStartTimes.Remove($Name)
    }
    $status = if ($Passed) { 'passed' } else { 'failed' }
    $results.Add([pscustomobject]@{
        name = $Name
        status = $status
        detail = $Detail
    })
    if ($OutputFormat -eq 'Text') {
        $statusDetail = if ($Passed -and -not [string]::IsNullOrWhiteSpace($SuccessDetail)) { $SuccessDetail } else { Format-ValidationDuration -DurationSeconds $durationSeconds }
        Write-Host (Format-ValidationStatusLine -Status $status -Name $Name -Detail $statusDetail)
    }
    if (-not $Passed) {
        $issues.Add("$Name`: $Detail")
    }
}

function Test-NpmPackageGraphCurrent {
    param(
        [Parameter(Mandatory = $true)][string]$LockPath,
        [Parameter(Mandatory = $true)][string]$InstalledLockPath
    )

    if (-not (Test-Path -LiteralPath $LockPath -PathType Leaf) -or -not (Test-Path -LiteralPath $InstalledLockPath -PathType Leaf)) {
        return $false
    }

    try {
        $lock = Get-Content -LiteralPath $LockPath -Raw | ConvertFrom-Json -AsHashtable -ErrorAction Stop
        $installedLock = Get-Content -LiteralPath $InstalledLockPath -Raw | ConvertFrom-Json -AsHashtable -ErrorAction Stop
        if ($lock['lockfileVersion'] -ne $installedLock['lockfileVersion'] -or $null -eq $lock['packages'] -or $null -eq $installedLock['packages']) {
            return $false
        }
        foreach ($packagePath in @($installedLock['packages'].Keys)) {
            if (-not $lock['packages'].ContainsKey($packagePath)) {
                return $false
            }
        }
        foreach ($packagePath in @($lock['packages'].Keys | Where-Object { $_ -ne '' })) {
            if (-not $installedLock['packages'].ContainsKey($packagePath)) {
                if (-not [bool]$lock['packages'][$packagePath]['optional']) {
                    return $false
                }
                continue
            }
            if ([string]$lock['packages'][$packagePath]['version'] -cne [string]$installedLock['packages'][$packagePath]['version']) {
                return $false
            }
        }
        return $true
    }
    catch {
        return $false
    }
}

function New-WorkbenchDisplayFixture {
    param([Parameter(Mandatory = $true)][object]$Fixture)

    $candidates = [Collections.Generic.List[object]]::new()
    foreach ($sourceGroup in @(
        [pscustomobject]@{ Lane = 'contributor'; Items = @($Fixture.upstreamCandidates) },
        [pscustomobject]@{ Lane = 'interactive'; Items = @($Fixture.interactiveCandidates) },
        [pscustomobject]@{ Lane = 'maintainer'; Items = @($Fixture.maintainerCandidates) }
    )) {
        foreach ($sourceCandidate in $sourceGroup.Items) {
            foreach ($assessment in @($sourceCandidate.assessments)) {
                $source = [ordered]@{
                    lane = [string]$sourceGroup.Lane
                    id = [string]$sourceCandidate.id
                    title = [string]$sourceCandidate.title
                    location = [string]$(if ($sourceGroup.Lane -ceq 'contributor') { $sourceCandidate.referenceUrl } elseif ($sourceGroup.Lane -ceq 'interactive') { $sourceCandidate.contractPath } else { $sourceCandidate.sourcePath })
                    text = [string]$(if ($sourceGroup.Lane -ceq 'contributor') { $sourceCandidate.currentContent } else { $sourceCandidate.ruleText })
                    contentSha256 = [string]$(if ($sourceGroup.Lane -ceq 'contributor') { $sourceCandidate.currentSha256 } else { $sourceCandidate.contentSha256 })
                    provenance = [string]$(if ($sourceGroup.Lane -ceq 'contributor') { 'published-upstream-standard' } else { $sourceCandidate.provenance })
                    transition = if ([string]$assessment.candidateState -ceq 'new') { 'added' } else { [string]$assessment.candidateState }
                }
                if ($sourceGroup.Lane -ceq 'contributor') {
                    $source['priorText'] = [string]$sourceCandidate.baselineContent
                    $source['revision'] = [ordered]@{ repository = 'hashicorp/terraform-provider-azurerm'; configuredRef = 'main'; resolvedCommit = '2' * 40 }
                }
                if ($sourceCandidate.PSObject.Properties['surface']) { $source['surface'] = [string]$sourceCandidate.surface }
                if ($sourceCandidate.PSObject.Properties['rationale']) { $source['rationale'] = [string]$sourceCandidate.rationale }
                if ($sourceCandidate.PSObject.Properties['evidence']) { $source['evidence'] = @($sourceCandidate.evidence) }
                if ($sourceCandidate.PSObject.Properties['sourceIds']) { $source['sourceIds'] = @($sourceCandidate.sourceIds) }

                $reviewState = if (-not [bool]$assessment.hostedApplicable) { 'excluded' } elseif ([string]$assessment.recommendation -ceq 'defer') { 'deferred' } else { 'recommended' }
                $recommendation = $null
                if ($reviewState -in @('recommended', 'deferred', 'excluded')) {
                    $category = if ([string]$assessment.hostedCategory -in @('implementation', 'testing', 'documentation')) { [string]$assessment.hostedCategory } else { 'implementation' }
                    $placement = if ($category -ceq 'implementation') { 'Schema And State' } elseif ($category -ceq 'testing') { 'Assertions And Validation' } else { 'Examples And Imports' }
                    $sourceDefinitionId = if ($sourceGroup.Lane -ceq 'contributor') { 'contributor-guidance' } elseif ($sourceGroup.Lane -ceq 'interactive') { 'interactive-toolkit' } else { 'maintainer-proposals' }
                    $evidenceIds = @($(if ($category -ceq 'implementation') { 'implementation-contract' } elseif ($category -ceq 'testing') { 'testing-contract' } else { 'documentation-contract' }))
                    if ([string]$source.provenance -ceq 'local-safeguard') { $evidenceIds += 'hosted-architecture' }
                    if ([string]$source.provenance -ceq 'confirmed-maintainer-convention') { $evidenceIds += 'docs-list-marker-confirmation' }
                    $recommendation = [ordered]@{
                        action = [string]$assessment.recommendation
                        hostedId = [string]$assessment.proposedHostedRuleId
                        idState = if ($null -ne $assessment.targetHostedRuleId) { 'existing' } else { 'tentative' }
                        targetHostedId = $assessment.targetHostedRuleId
                        ruleText = [string]$assessment.proposedText
                        category = $category
                        placement = $placement
                        rationale = [string]$assessment.selectionRationale
                        needsReview = [bool]$sourceCandidate.requiresReview
                        relatedHostedCoverage = @()
                        retireHostedRuleIds = @()
                        guardedTokenDelta = [int]$assessment.guardedTokenDelta
                        provenance = @([string]$source.provenance)
                        evidenceIds = @($evidenceIds | Sort-Object -Unique)
                        sourceRelationships = @([ordered]@{ sourceDefinitionId = $sourceDefinitionId; sourceId = [string]$sourceCandidate.id; relationshipKind = 'included'; rationale = "Assessment $($assessment.assessmentId) is included in this recommendation." })
                    }
                    if ($category -ceq 'implementation' -and [string]$assessment.recommendation -in @('add', 'exclude')) { $recommendation['implementationModels'] = @('legacy', 'typed', 'framework') }
                }
                $displayAssessment = [ordered]@{
                    id = [string]$assessment.assessmentId
                    title = [string]$assessment.title
                    sourceMeaning = [string]$assessment.summary
                    impactDescription = [string]$assessment.impactDescription
                    hostedApplicable = [bool]$assessment.hostedApplicable
                    applicabilityRationale = [string]$assessment.applicabilityRationale
                    selectionFactors = $assessment.selectionFactors
                    selectionRationale = [string]$assessment.selectionRationale
                    confidence = [ordered]@{ level = 'high'; rationale = 'The offline fixture is deterministic.'; uncertainties = @() }
                    affectedSurfaces = @($assessment.affectedSurfaces)
                    existingCoverage = [ordered]@{ score = if ($null -ne $assessment.targetHostedRuleId) { 5 } else { 0 }; rationale = [string]$assessment.currentHostedCoverage }
                    relatedHostedCoverage = @()
                    evaluatedAt = [string]$assessment.assessedAt
                    evaluator = [string]$assessment.evaluator
                }
                $catalogMapping = if ($null -ne $assessment.targetHostedRuleId) {
                    $mappedRule = @($Fixture.hostedRules | Where-Object { [string]$_.id -ceq [string]$assessment.targetHostedRuleId })[0]
                    [ordered]@{ state = [string]$mappedRule.status; hostedRuleId = [string]$assessment.targetHostedRuleId }
                }
                else {
                    [ordered]@{ state = 'unmapped'; hostedRuleId = $null }
                }
                $candidates.Add([ordered]@{
                    source = $source
                    assessment = $displayAssessment
                    reviewState = $reviewState
                    recommendation = $recommendation
                    catalogMapping = $catalogMapping
                    members = @([ordered]@{ source = $source; assessment = $displayAssessment; meaningCoverageRationale = 'The recommendation preserves this fixture assessment meaning.'; catalogMapping = $catalogMapping })
                })
            }
        }
    }
    return [ordered]@{
        '$schema' = 'workbench-display-v4.schema.json'
        schemaVersion = 4
        kind = 'hosted-rule-workbench-display'
        generatedAt = [string]$Fixture.generatedAt
        readOnly = $true
        sourceFiles = @($candidates | ForEach-Object { [ordered]@{ sourceDefinitionId = [string]$_.source.lane; sourceId = [string]$_.source.id; contentSha256 = [string]$_.source.contentSha256 } } | Sort-Object -Property sourceDefinitionId, sourceId -Unique)
        reconciliation = [ordered]@{ status = 'ready' }
        candidates = $candidates.ToArray()
        catalog = [ordered]@{
            contentSha256 = 'b' * 64
            protectedRulesContentSha256 = 'c' * 64
            rules = @($Fixture.hostedRules | ForEach-Object {
                $projectedRule = [ordered]@{
                    id = [string]$_.id
                    origin = 'hosted-baseline-migration'
                    status = [string]$_.status
                    text = [string]$_.text
                    provenance = @('published-upstream-standard')
                    evidenceIds = @($(if ([string]$_.id -like 'IMPL-*') { 'implementation-contract' } else { 'documentation-contract' }))
                    canonicalCandidate = [ordered]@{ sourceDefinitionId = 'contributor-guidance'; sourceId = 'guide-new-resource'; assessmentId = [string]$_.id }
                    placements = @($_.placements)
                }
                if ([string]$_.id -like 'IMPL-*') { $projectedRule['implementationModels'] = @('legacy', 'typed', 'framework') }
                if ($_.PSObject.Properties['retirementReason']) { $projectedRule['retirementReason'] = [string]$_.retirementReason }
                if ($_.PSObject.Properties['lastPlacement']) { $projectedRule['lastPlacement'] = $_.lastPlacement }
                $projectedRule
            })
            protectedRules = @($Fixture.protectedRules)
            protectedRuleFiles = @($Fixture.protectedRuleFiles)
        }
        guidanceCapacity = $Fixture.guidanceCapacity
    }
}

function New-CapacityReport {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][string]$Kind
    )

    return [ordered]@{
        name = $Name
        kind = $Kind
        paths = @('fixture.md')
        characterCount = 100
        estimatedTokens = 25
        guardedTokens = 32
        budgetTokens = 1000
        budgetHeadroomTokens = 968
        utilizationPercent = 3.2
        withinBudget = $true
    }
}

function Test-PngFile {
    param([Parameter(Mandatory = $true)][string]$Path)

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        return $false
    }
    $bytes = [IO.File]::ReadAllBytes($Path)
    return $bytes.Length -ge 1000 -and [BitConverter]::ToString($bytes[0..7]) -eq '89-50-4E-47-0D-0A-1A-0A'
}

if ($OutputFormat -eq 'Text') {
    Write-ValidationSectionHeader -Title 'Hosted Rule Workbench tests'
}

try {
    if ($AllowBreakingNpmFix -and -not $FixNpmAudit) {
        Add-TestResult -Name 'run-selection' -Passed $false -Detail '-AllowBreakingNpmFix requires -FixNpmAudit'
    }
    elseif ($ContinueAfterNpmAuditFailure -and [string]::IsNullOrWhiteSpace($Run)) {
        Add-TestResult -Name 'run-selection' -Passed $false -Detail '-ContinueAfterNpmAuditFailure requires a focused -Run and is not available for the complete Workbench suite'
    }
    elseif ($ContinueAfterNpmAuditFailure -and $FixNpmAudit) {
        Add-TestResult -Name 'run-selection' -Passed $false -Detail '-ContinueAfterNpmAuditFailure cannot be combined with -FixNpmAudit'
    }
    elseif ($FixNpmAudit -and -not [string]::IsNullOrWhiteSpace($Run)) {
        Add-TestResult -Name 'run-selection' -Passed $false -Detail '-FixNpmAudit is available only for the complete Workbench suite'
    }
    elseif ($missingFocusedRuns.Count -gt 0 -or $unknownFocusedRuns.Count -gt 0) {
        Add-TestResult -Name 'run-selection' -Passed $false -Detail "Focused-run catalog is out of sync: missing=$($missingFocusedRuns -join ', '); unknown=$($unknownFocusedRuns -join ', ')"
    }
    elseif ($Headed -and $Run -ne 'browser-playwright-journeys') {
        Add-TestResult -Name 'run-selection' -Passed $false -Detail '-Headed requires -Run browser-playwright-journeys'
    }
    elseif (-not [string]::IsNullOrWhiteSpace($Run) -and $Run -notin $supportedFocusedRuns) {
        $supportedTestList = ($supportedFocusedRuns | ForEach-Object { "      - '$_'" }) -join "`n"
        Add-TestResult -Name 'run-selection' -Passed $false -Detail "Requested Workbench test '$Run' is not supported.`n`n    SUPPORTED TESTS:`n`n$supportedTestList"
    }
    else {
    New-Item -ItemType Directory -Path $tempRoot -Force | Out-Null
    $nodePackageConfig = Get-Content -LiteralPath $nodePackageManifestPath -Raw | ConvertFrom-Json
    $npmCommandName = if ($IsWindows) { 'npm.cmd' } else { 'npm' }
    $npmCommand = Get-Command $npmCommandName -ErrorAction Stop
    Start-TestResult -Name 'npm audit'
    $npmSecurityArguments = @('-NoProfile', '-File', $npmSecurityScriptPath, '-LockPath', $nodePackageLockRelativePath, '-OutputFormat', 'Json')
    if ($FixNpmAudit) { $npmSecurityArguments += '-Fix' }
    if ($AllowBreakingNpmFix) { $npmSecurityArguments += '-AllowBreakingFix' }
    $auditOutput = @(& pwsh @npmSecurityArguments 2>&1)
    $auditExitCode = $LASTEXITCODE
    $auditResult = try { ($auditOutput | Out-String) | ConvertFrom-Json } catch { $null }
    $matchingAuditReports = @(if ($null -ne $auditResult) { $auditResult.reports | Where-Object { $_.lockPath -eq $nodePackageLockRelativePath } })
    $hostedAuditReport = if ($matchingAuditReports.Count -gt 0) { $matchingAuditReports[0] } else { $null }
    $auditPassed = $auditExitCode -eq 0 -and $null -ne $hostedAuditReport -and $hostedAuditReport.status -eq 'passed'
    $auditFailures = @(if ($null -ne $auditResult) { $auditResult.failures })
    $expectedIncompleteAuditFailure = "$nodePackageLockRelativePath`: npm audit did not return a complete vulnerability report"
    $dependencyAuditInconclusive = -not [string]::IsNullOrWhiteSpace($Run) -and
        $null -ne $auditResult -and
        $null -eq $hostedAuditReport -and
        $auditFailures.Count -eq 1 -and
        [string]$auditFailures[0] -ceq $expectedIncompleteAuditFailure
    if ($null -ne $hostedAuditReport) {
        $dependencyAuditCounts = $hostedAuditReport.counts
        foreach ($finding in @($hostedAuditReport.findings)) { $dependencyAuditFindings.Add($finding) }
        foreach ($change in @($hostedAuditReport.remediationChanges)) { $npmFixChanges.Add($change) }
        $npmFixApplied = [bool]$hostedAuditReport.remediationApplied
        $npmFixRequiresBreaking = [bool]$hostedAuditReport.requiresBreakingFix
    }
    if (-not $auditPassed) {
        $dependencyAuditError = if ($null -ne $auditResult -and @($auditResult.failures).Count -gt 0) { @($auditResult.failures) -join '; ' } else { 'Shared npm security validation did not return a passing Hosted lockfile report' }
    }
    $dependencyAuditContinuation = $ContinueAfterNpmAuditFailure -and -not $auditPassed -and -not $dependencyAuditInconclusive
    $auditDetail = if ($dependencyAuditInconclusive) {
        "$dependencyAuditError; focused validation is continuing with the existing locked dependency graph"
    }
    elseif ($dependencyAuditContinuation) {
        "$dependencyAuditError; focused validation is continuing without dependency installation and remains unverified"
    }
    elseif (-not $auditPassed) {
        "$dependencyAuditError; dependency installation blocked"
    }
    elseif ($npmFixApplied) {
        'Remediated the lockfile and passed the shared npm audit at the low threshold'
    }
    else {
        "Lockfile passed the shared npm audit at the low threshold: critical=$($dependencyAuditCounts.critical), high=$($dependencyAuditCounts.high), moderate=$($dependencyAuditCounts.moderate), low=$($dependencyAuditCounts.low)"
    }
    Add-TestResult -Name 'npm audit' -Passed ($auditPassed -or $dependencyAuditInconclusive) -Detail $auditDetail
    if (-not $auditPassed -and -not $dependencyAuditInconclusive -and -not $dependencyAuditContinuation) {
        $failureAlreadyReported = $true
        throw 'npm audit failed before dependency installation'
    }
    $dependencyRunningDetail = if ($auditPassed) { 'VERIFYING AUDITED LOCKFILE' } else { 'VERIFYING INSTALLED LOCKFILE GRAPH' }
    Start-TestResult -Name 'npm-packages' -RunningDetail $dependencyRunningDetail
    $dependencyOutput = @()
    $dependencyExitCode = 0
    $packageGraphCurrent = Test-NpmPackageGraphCurrent -LockPath $nodePackageLockPath -InstalledLockPath $nodeInstalledLockPath
    if (-not $packageGraphCurrent -and ($dependencyAuditInconclusive -or $dependencyAuditContinuation)) {
        $dependencyExitCode = 1
        $dependencyOutput = @('npm audit did not pass and the installed package graph does not match the lockfile; dependency installation and focused execution are blocked')
    }
    elseif (-not $packageGraphCurrent) {
        $dependencyOutput = @(& $npmCommand.Source ci --prefix $toolsRoot --ignore-scripts --no-audit --no-fund 2>&1)
        $dependencyExitCode = $LASTEXITCODE
    }
    $lockedDependencyValid = $dependencyExitCode -eq 0 -and (Test-NpmPackageGraphCurrent -LockPath $nodePackageLockPath -InstalledLockPath $nodeInstalledLockPath) -and (Test-Path -LiteralPath (Join-Path $toolsRoot 'node_modules/puppeteer/package.json') -PathType Leaf) -and (Test-Path -LiteralPath (Join-Path $toolsRoot 'node_modules/@playwright/test/package.json') -PathType Leaf)
    $lockedDependencySuccessDetail = if ($auditPassed) { 'CURRENT (MATCHES AUDITED LOCKFILE)' } else { 'CURRENT (MATCHES LOCKFILE; UNVERIFIED)' }
    $lockedDependencyDetail = if ($lockedDependencyValid) {
        "Installed packages match the lockfile for Playwright $($nodePackageConfig.devDependencies.'@playwright/test') and Puppeteer $($nodePackageConfig.devDependencies.puppeteer)."
    }
    else {
        ($dependencyOutput | Out-String).Trim()
    }
    Add-TestResult -Name 'npm-packages' -Passed $lockedDependencyValid -SuccessDetail $lockedDependencySuccessDetail -Detail $lockedDependencyDetail
    if (-not $lockedDependencyValid) {
        throw 'locked browser validation dependencies could not be installed'
    }
    if ([string]::IsNullOrWhiteSpace($Run) -or $Run -in $browserRuntimeTestNames) {
        Start-TestResult -Name 'locked-browser-runtime'
        $browserInstallOutput = New-Object 'System.Collections.Generic.List[string]'
        $browserInstallPassed = Test-Path -LiteralPath $puppeteerCliPath -PathType Leaf
        if ($browserInstallPassed -and -not $auditPassed) {
            $output = @(& $puppeteerCliPath browsers list 2>&1)
            foreach ($line in $output) { $browserInstallOutput.Add([string]$line) }
            $browserInstallPassed = $LASTEXITCODE -eq 0 -and
                @($output | Where-Object { [string]$_ -match '^chrome@' }).Count -gt 0 -and
                @($output | Where-Object { [string]$_ -match '^chrome-headless-shell@' }).Count -gt 0
        }
        elseif ($browserInstallPassed) {
            foreach ($browserName in @('chrome', 'chrome-headless-shell')) {
                if (-not $browserInstallPassed) {
                    break
                }
                $output = @(& $puppeteerCliPath browsers install $browserName 2>&1)
                foreach ($line in $output) { $browserInstallOutput.Add([string]$line) }
                $browserInstallPassed = $LASTEXITCODE -eq 0
            }
        }
        $browserRuntimeDetail = if ($browserInstallPassed -and $auditPassed) {
            'Installed the Puppeteer-pinned Chrome and Chrome Headless Shell runtimes through the locked local CLI.'
        }
        elseif ($browserInstallPassed) {
            'Verified existing Chrome and Chrome Headless Shell runtimes without installation after npm audit did not pass.'
        }
        else {
            ($browserInstallOutput | Out-String).Trim()
        }
        Add-TestResult -Name 'locked-browser-runtime' -Passed $browserInstallPassed -Detail $browserRuntimeDetail
        if (-not $browserInstallPassed) {
            throw 'locked browser runtimes could not be installed'
        }
    }
    $displayPath = Join-Path $tempRoot 'workbench-display.json'
    $ruleIssuesPath = Join-Path $tempRoot 'workbench-rule-issues.json'
    $capacityOutput = @(& pwsh -NoProfile -File (Join-Path $toolsRoot 'internal/workbench/Get-GuidanceCapacity.ps1') -OutputFormat Json)
    if ($LASTEXITCODE -ne 0) { throw 'Cannot construct the policy-bound Workbench capacity fixture' }
    $capacityFixture = ($capacityOutput | Out-String) | ConvertFrom-Json -Depth 50
    $fixture = [ordered]@{
        generatedAt = '2026-09-03T00:00:00Z'
        guidanceCapacity = $capacityFixture
        hostedRules = @(
            [ordered]@{ id = 'IMPL-PATCH-001'; status = 'active'; text = 'If PATCH preserves omitted properties, removal must send an explicit clearing value.'; placements = @([ordered]@{ surfaceId = 'implementation'; sectionHeading = 'Azure API Semantics' }) },
            [ordered]@{ id = 'DOCS-IMP-002'; status = 'active'; text = 'Resource documentation must include a shell-fenced Terraform import command.'; placements = @([ordered]@{ surfaceId = 'documentation'; sectionHeading = 'Examples And Imports' }) }
        )
        protectedRules = @([ordered]@{
            id = 'IMPL-WF-000'
            status = 'protected'
            surfaceId = 'implementation'
            title = 'Classify AzureRM implementation resource types'
            text = 'Classify implementation code as legacy, typed, or framework before applying resource-type-specific rules. Legacy implementations use function-built `*pluginsdk.Resource` values and `*pluginsdk.ResourceData` callbacks. Typed implementations use receiver-based `internal/sdk` resource or data-source contracts. Framework implementations use Terraform Plugin Framework interfaces and request/response types, including list resources, ephemeral resources, and provider-defined functions. Preserve the existing resource type unless the change explicitly migrates it.'
            provenance = 'confirmed-maintainer-convention'
            protectionReason = 'Required first-party instruction infrastructure.'
            impact = 100
            guardedTokens = 150
            sourcePath = 'hosted_copilot/authored-rules/protected/implementation.rules.md'
            contentSha256 = 'f' * 64
        })
        protectedRuleFiles = @([ordered]@{
            path = 'hosted_copilot/authored-rules/protected/implementation.rules.md'
            surfaceId = 'implementation'
            content = "# Protected Implementation Review Rules`n`n### IMPL-WF-000: Classify AzureRM implementation resource types`n`n- Rule: Classify implementation code before applying resource-type-specific rules."
            contentSha256 = 'e' * 64
            ruleIds = @('IMPL-WF-000')
        })
        upstreamCandidates = @(
            [ordered]@{
                id = 'guide-new-resource'
                title = 'Guide: New Resource'
                referenceUrl = 'https://example.invalid/guide-new-resource'
                baselineSha256 = '1' * 64
                currentSha256 = '2' * 64
                state = 'changed'
                requiresReview = $true
                affectedHostedRuleIds = @('DOCS-IMP-002')
                relatedHostedRules = @([ordered]@{ id = 'DOCS-IMP-002'; status = 'active'; text = 'Resource documentation must include a shell-fenced Terraform import command.'; placements = @([ordered]@{ surfaceId = 'documentation'; sectionHeading = 'Examples And Imports' }) })
                baselineContent = 'Previous contributor guidance.'
                currentContent = 'Current contributor guidance includes PUT clearing behavior and companion resource requirements.'
                assessments = @(
                    [ordered]@{
                        assessmentId = 'IMPL-PATCH-001'
                        title = 'Prefer PUT when removal must clear remote values'
                        candidateState = 'changed'
                        targetHostedRuleId = 'IMPL-PATCH-001'
                        proposedHostedRuleId = 'IMPL-PATCH-001'
                        status = 'evaluated'
                        sourceContentSha256 = '2' * 64
                        assessedAt = '2026-09-03T00:00:00Z'
                        evaluator = 'offline-fixture'
                        hostedApplicable = $true
                        applicabilityRationale = 'The rule governs detectable update semantics.'
                        hostedCategory = 'implementation'
                        recommendation = 'update'
                        summary = 'Update the existing PATCH safeguard with PUT preference.'
                        impactDescription = 'Prevents stale remote values after Terraform removal.'
                        currentHostedCoverage = 'IMPL-PATCH-001 is the single semantic update target.'
                        affectedSurfaces = @('implementation')
                        guardedTokenDelta = 40
                        proposedText = 'Prefer PUT when removal must clear a remote value. If PATCH is required, send an explicit clearing value instead of omitting the property.'
                        selectionFactors = [ordered]@{ severity = 4; frequency = 3; breadth = 4; hostedDetectability = 5; evidenceStrength = 5; falsePositiveRisk = 1; redundancy = 1 }
                        selectionRationale = 'The update preserves the existing safeguard and adds explicit operation guidance.'
                    },
                    [ordered]@{
                        assessmentId = 'resource-identity-list-resource'
                        title = 'Require Resource Identity and List Resource companions'
                        candidateState = 'new'
                        targetHostedRuleId = $null
                        proposedHostedRuleId = 'REVIEW-REPO-001'
                        status = 'evaluated'
                        sourceContentSha256 = '2' * 64
                        assessedAt = '2026-09-03T00:00:00Z'
                        evaluator = 'offline-fixture'
                        hostedApplicable = $true
                        applicabilityRationale = 'The requirement applies to every new resource.'
                        hostedCategory = 'repository'
                        recommendation = 'add'
                        summary = 'Add missing companion-resource coverage.'
                        impactDescription = 'Prevents incomplete new resource implementations.'
                        currentHostedCoverage = 'No active Hosted rule requires both companion surfaces.'
                        affectedSurfaces = @('repository', 'implementation')
                        guardedTokenDelta = 73
                        proposedText = 'When a pull request adds a Resource, require Resource Identity and a List Resource unless an approved exception is documented.'
                        selectionFactors = [ordered]@{ severity = 4; frequency = 3; breadth = 5; hostedDetectability = 4; evidenceStrength = 5; falsePositiveRisk = 2; redundancy = 1 }
                        selectionRationale = 'The uncovered requirement is broad, evidence-backed, and directly reviewable.'
                    },
                    [ordered]@{
                        assessmentId = 'DOCS-IMP-002'
                        title = 'Preserve the resource import command requirement'
                        candidateState = 'current'
                        targetHostedRuleId = 'DOCS-IMP-002'
                        proposedHostedRuleId = 'DOCS-IMP-002'
                        status = 'evaluated'
                        sourceContentSha256 = '2' * 64
                        assessedAt = '2026-09-03T00:00:00Z'
                        evaluator = 'offline-fixture'
                        hostedApplicable = $true
                        applicabilityRationale = 'The existing documentation rule remains applicable.'
                        hostedCategory = 'documentation'
                        recommendation = 'no-change'
                        summary = 'Existing import guidance remains current.'
                        impactDescription = 'No catalog change is required.'
                        currentHostedCoverage = 'DOCS-IMP-002 already covers this requirement.'
                        affectedSurfaces = @('documentation')
                        guardedTokenDelta = 0
                        proposedText = 'Resource documentation must include a shell-fenced Terraform import command.'
                        selectionFactors = [ordered]@{ severity = 2; frequency = 3; breadth = 4; hostedDetectability = 5; evidenceStrength = 5; falsePositiveRisk = 1; redundancy = 5 }
                        selectionRationale = 'Existing Hosted coverage is complete, so no change is warranted.'
                    }
                )
            }
        )
        interactiveCandidates = @(
            [ordered]@{
                id = 'REVIEW-CLASS-001'
                title = 'Issues are for actual problems only'
                contractPath = '.github/instructions/code-review-compliance-contract.instructions.md'
                sourceStatus = 'active'
                contentSha256 = 'd' * 64
                provenance = 'published-upstream-standard'
                evidence = @('fixture-evidence')
                sourceIds = @('fixture-source')
                ruleText = 'An Issue must identify a real defect supported by evidence.'
                state = 'new'
                requiresReview = $true
                changeReasons = @('new-rule')
                priorDecision = $null
                relatedHostedRules = @()
                assessments = @(
                    [ordered]@{
                        assessmentId = 'REVIEW-CLASS-001'
                        title = 'Issues are for actual problems only'
                        candidateState = 'new'
                        targetHostedRuleId = $null
                        proposedHostedRuleId = 'REVIEW-EVID-001'
                        status = 'evaluated'
                        sourceContentSha256 = 'd' * 64
                        assessedAt = '2026-09-03T00:00:00Z'
                        evaluator = 'offline-fixture'
                        hostedApplicable = $true
                        applicabilityRationale = 'The rule governs evidence-backed findings produced by the Hosted review agent.'
                        hostedCategory = 'review-classification-and-evidence'
                        recommendation = 'add'
                        summary = 'High impact, low cost'
                        impactDescription = 'Prevents unsupported review findings across review surfaces.'
                        currentHostedCoverage = 'No materially equivalent Hosted rule is mapped.'
                        affectedSurfaces = @('review-skill')
                        guardedTokenDelta = 19
                        proposedText = 'Report only evidence-backed defects as Issues.'
                        selectionFactors = [ordered]@{
                            severity = 5
                            frequency = 3
                            breadth = 4
                            hostedDetectability = 4
                            evidenceStrength = 5
                            falsePositiveRisk = 1
                            redundancy = 1
                        }
                        selectionRationale = 'The safeguard is broadly applicable, evidence-backed, and inexpensive.'
                    }
                )
            }
        )
        maintainerCandidates = @()
    }
    $maintainerAssessment = $fixture.interactiveCandidates[0].assessments[0] | ConvertTo-Json -Depth 20 | ConvertFrom-Json
    $maintainerAssessment.assessmentId = 'DOCS-MAINT-001'
    $maintainerAssessment.title = 'Maintainer proposal'
    $maintainerAssessment.sourceContentSha256 = 'f' * 64
    $maintainerAssessment.hostedCategory = 'documentation'
    $maintainerAssessment.proposedHostedRuleId = 'DOCS-CAND-001'
    $maintainerAssessment.proposedText = 'Flag documentation that omits a required maintainer convention.'
    $excludedAssessmentAlpha = $fixture.interactiveCandidates[0].assessments[0] | ConvertTo-Json -Depth 20 | ConvertFrom-Json
    $excludedAssessmentAlpha.assessmentId = 'IMPL-EXCL-001'
    $excludedAssessmentAlpha.title = 'Excluded assessment alpha'
    $excludedAssessmentAlpha.hostedApplicable = $false
    $excludedAssessmentAlpha.applicabilityRationale = 'The source behavior is outside the current Hosted review boundary.'
    $excludedAssessmentAlpha.recommendation = 'exclude'
    $excludedAssessmentAlpha.proposedHostedRuleId = 'IMPL-EXCL-001'
    $excludedAssessmentAlpha.hostedCategory = 'implementation'
    $excludedAssessmentAlpha.sourceContentSha256 = '3' * 64
    $excludedAssessmentAlpha.summary = 'Excluded behavior remains available for maintainer audit.'
    $excludedAssessmentAlpha.impactDescription = 'The assessment is preserved without entering Candidate Sources.'
    $excludedAssessmentAlpha.currentHostedCoverage = 'No Hosted rule is required for this excluded behavior.'
    $excludedAssessmentAlpha.affectedSurfaces = @('implementation')
    $excludedAssessmentAlpha.guardedTokenDelta = 0
    $excludedAssessmentAlpha.proposedText = 'Review the excluded behavior only when a maintainer explicitly contests the applicability decision.'
    $excludedAssessmentAlpha.selectionRationale = 'The evidence is complete, but the behavior is outside the current Hosted review boundary.'
    $excludedAssessmentBravo = $excludedAssessmentAlpha | ConvertTo-Json -Depth 20 | ConvertFrom-Json
    $excludedAssessmentBravo.assessmentId = 'IMPL-EXCL-002'
    $excludedAssessmentBravo.title = 'Excluded assessment bravo'
    $excludedAssessmentBravo.proposedHostedRuleId = 'IMPL-EXCL-002'
    $excludedAssessmentBravo.sourceContentSha256 = '4' * 64
    $excludedAssessmentBravo.applicabilityRationale = 'This second excluded result provides deterministic sorting evidence.'
    $excludedAssessmentBravo.proposedText = 'Keep the second excluded assessment available for deterministic audit ordering.'
    $excludedInteractiveAlpha = $fixture.interactiveCandidates[0] | ConvertTo-Json -Depth 20 | ConvertFrom-Json
    $excludedInteractiveAlpha.id = 'IMPL-EXCL-001'
    $excludedInteractiveAlpha.title = 'Excluded assessment alpha'
    $excludedInteractiveAlpha.contentSha256 = '3' * 64
    $excludedInteractiveAlpha.ruleText = 'Review excluded behavior after a maintainer records an explicit override rationale.'
    $excludedInteractiveAlpha.assessments = @($excludedAssessmentAlpha)
    $excludedInteractiveBravo = $fixture.interactiveCandidates[0] | ConvertTo-Json -Depth 20 | ConvertFrom-Json
    $excludedInteractiveBravo.id = 'IMPL-EXCL-002'
    $excludedInteractiveBravo.title = 'Excluded assessment bravo'
    $excludedInteractiveBravo.contentSha256 = '4' * 64
    $excludedInteractiveBravo.ruleText = 'Keep a second excluded behavior available for deterministic assessment sorting.'
    $excludedInteractiveBravo.assessments = @($excludedAssessmentBravo)
    $fixture.interactiveCandidates += @($excludedInteractiveAlpha, $excludedInteractiveBravo)
    $fixture.maintainerCandidates = @([ordered]@{
        id = 'DOCS-MAINT-001'
        title = 'Maintainer proposal'
        sourcePath = 'hosted_copilot/authored-rules/proposals/documentation.rules.md'
        surface = 'documentation'
        sourceStatus = 'active'
        contentSha256 = 'f' * 64
        provenance = 'confirmed-maintainer-convention'
        rationale = 'The maintainer confirmed this documentation review requirement.'
        ruleText = 'Flag documentation that omits a required maintainer convention.'
        state = 'new'
        requiresReview = $true
        relatedHostedRules = @()
        assessments = @($maintainerAssessment)
    })
    $display = New-WorkbenchDisplayFixture -Fixture $fixture
    foreach ($candidate in @($display.candidates | Where-Object { $_.catalogMapping.state -ceq 'active' })) {
        $mappedId = [string]$candidate.catalogMapping.hostedRuleId
        if ($mappedId -cnotin @($candidate.recommendation.relatedHostedCoverage | ForEach-Object { [string]$_.hostedRuleId })) {
            $candidate.recommendation.relatedHostedCoverage += @([ordered]@{
                hostedRuleId = $mappedId
                relationship = 'equivalent'
                rationale = 'The mapped Hosted rule covers its own reconciled baseline.'
            })
        }
    }
    $display.catalog.contentSha256 = (Get-FileHash -LiteralPath (Join-Path $repositoryRoot 'hosted_copilot/copilot-rule-catalog/instruction-catalog.json') -Algorithm SHA256).Hash.ToLowerInvariant()
    $display.catalog.protectedRulesContentSha256 = (Get-FileHash -LiteralPath (Join-Path $repositoryRoot 'hosted_copilot/copilot-rule-catalog/protected-rules.json') -Algorithm SHA256).Hash.ToLowerInvariant()
    $displayJson = $display | ConvertTo-Json -Depth 30
    [IO.File]::WriteAllText($displayPath, $displayJson + "`n", [Text.UTF8Encoding]::new($false))
    Add-TestResult -Name 'fixture-display-valid' -Passed ([bool]($displayJson | Test-Json -SchemaFile $displaySchemaPath -ErrorAction Stop)) -Detail 'The offline Workbench display satisfies the v4 display schema.'

    $issueCandidate = @($display.candidates | Where-Object { $null -ne $_.recommendation } | Select-Object -First 1)[0]
    $issueCandidateKey = "$([string]$issueCandidate.source.lane):$([string]$issueCandidate.source.id):$([string]$issueCandidate.assessment.id)"
    $issueSourceRuleId = [string]$issueCandidate.recommendation.hostedId
    $issueRelatedRule = @($display.catalog.rules | Where-Object { [string]$_.id -cne $issueSourceRuleId } | Select-Object -First 1)[0]
    $ruleIssuesFixture = [ordered]@{
        '$schema' = 'workbench-rule-issues-v4.schema.json'
        schemaVersion = 4
        kind = 'hosted-rule-workbench-rule-issues'
        generatedAt = [string]$display.generatedAt
        readOnly = $true
        sourceFiles = @($display.sourceFiles)
        issues = @([ordered]@{
            id = "relationship:$issueSourceRuleId`:fixture"
            classification = 'duplicate'
            label = 'Duplicate'
            title = "$issueSourceRuleId duplicates $([string]$issueRelatedRule.id)"
            bannerTitle = 'Fixture duplicate guidance'
            bannerMessage = 'The proposed fixture wording duplicates an active hosted rule.'
            blocking = $false
            ruleIds = @($issueSourceRuleId, [string]$issueRelatedRule.id)
            protectedRuleIds = @()
            candidateKeys = @($issueCandidateKey)
            rules = @(
                [ordered]@{ id = $issueSourceRuleId; status = 'proposed'; disposition = 'exclude'; text = [string]$issueCandidate.recommendation.ruleText; candidateKeys = @($issueCandidateKey) },
                [ordered]@{ id = [string]$issueRelatedRule.id; status = [string]$issueRelatedRule.status; disposition = 'keep'; text = [string]$issueRelatedRule.text; candidateKeys = @() }
            )
            relationships = @([ordered]@{ sourceRuleId = $issueSourceRuleId; relatedRuleId = [string]$issueRelatedRule.id; relationship = 'equivalent'; kind = 'duplicate'; rationale = 'The fixture rules express the same enforceable obligation.'; candidateKey = $issueCandidateKey })
            assessmentSummary = 'The proposed fixture rule duplicates existing hosted guidance.'
            wording = [ordered]@{ status = 'selected'; label = 'Suggested Consolidated Wording'; presentation = 'member'; text = [string]$issueRelatedRule.text; sourceRuleId = [string]$issueRelatedRule.id }
            recommendedMaintainerAction = [ordered]@{
                summary = "Keep $([string]$issueRelatedRule.id) and exclude $issueSourceRuleId."
                operations = @([ordered]@{ candidateKey = $issueCandidateKey; ruleId = $issueSourceRuleId; action = 'exclude'; proposedText = [string]$issueCandidate.recommendation.ruleText; retireHostedRuleIds = @() })
            }
        })
    }
    $ruleIssuesJson = $ruleIssuesFixture | ConvertTo-Json -Depth 30
    if (-not ($ruleIssuesJson | Test-Json -SchemaFile $ruleIssuesSchemaPath -ErrorAction Stop)) {
        throw 'The offline Workbench Rule Issues fixture does not satisfy the v4 schema'
    }
    [IO.File]::WriteAllText($ruleIssuesPath, $ruleIssuesJson + "`n", [Text.UTF8Encoding]::new($false))

    $invalidAssessmentDisplay = $displayJson | ConvertFrom-Json
    $invalidAssessmentDisplay.candidates[0].assessment.selectionFactors.severity = 6
    $invalidAssessmentJson = $invalidAssessmentDisplay | ConvertTo-Json -Depth 30
    Add-TestResult -Name 'assessment-factor-range' -Passed (-not [bool]($invalidAssessmentJson | Test-Json -SchemaFile $displaySchemaPath -ErrorAction SilentlyContinue)) -Detail 'AI assessment factors outside the supported zero-through-five range are rejected.'

    $indexContent = Get-Content -LiteralPath (Join-Path $workbenchRoot 'index.html') -Raw
    $appContent = Get-Content -LiteralPath (Join-Path $workbenchRoot 'app.js') -Raw
    $hierarchicalViewContent = Get-Content -LiteralPath (Join-Path $workbenchRoot 'hierarchical-view.js') -Raw
    $statusbarContent = Get-Content -LiteralPath (Join-Path $workbenchRoot 'statusbar.js') -Raw
    $stylesContent = Get-Content -LiteralPath (Join-Path $workbenchRoot 'styles.css') -Raw
    $faviconContent = Get-Content -LiteralPath (Join-Path $workbenchRoot 'favicon.svg') -Raw
    $generatedSpriteContent = Get-Content -LiteralPath (Join-Path $codiconRoot 'sprite.svg') -Raw
    $spriteContent = $generatedSpriteContent -replace '(?s)\s*<symbol id="codicon-discard-all".*?</symbol>', '' -replace '(?s)\s*<symbol id="codicon-chat-sparkle-error".*?</symbol>', ''
    $attributionContent = Get-Content -LiteralPath (Join-Path $codiconRoot 'ATTRIBUTION.md') -Raw
    $octiconSpriteContent = Get-Content -LiteralPath (Join-Path $octiconRoot 'sprite.svg') -Raw
    $octiconAttributionContent = Get-Content -LiteralPath (Join-Path $octiconRoot 'ATTRIBUTION.md') -Raw
    $fluentIconSpriteContent = Get-Content -LiteralPath (Join-Path $fluentIconRoot 'sprite.svg') -Raw
    $fluentIconAttributionContent = Get-Content -LiteralPath (Join-Path $fluentIconRoot 'ATTRIBUTION.md') -Raw
    $llmIconSpriteContent = Get-Content -LiteralPath (Join-Path $llmIconRoot 'sprite.svg') -Raw
    $llmIconAttributionContent = Get-Content -LiteralPath (Join-Path $llmIconRoot 'ATTRIBUTION.md') -Raw
    $iconGeneratorContent = Get-Content -LiteralPath $iconGeneratorPath -Raw
    $octiconGeneratorContent = Get-Content -LiteralPath $octiconGeneratorPath -Raw
    $fluentIconGeneratorContent = Get-Content -LiteralPath $fluentIconGeneratorPath -Raw
    $llmIconGeneratorContent = Get-Content -LiteralPath $llmIconGeneratorPath -Raw
    $iconPreviewContent = Get-Content -LiteralPath $iconPreviewPath -Raw
    $iconPreviewRendererContent = Get-Content -LiteralPath $iconPreviewRendererPath -Raw
    $launcherContent = Get-Content -LiteralPath $launcherPath -Raw
    $hostedGitHubHelpersContent = Get-Content -LiteralPath $hostedGitHubHelpersPath -Raw
    $workbenchGitHubContextContent = Get-Content -LiteralPath $workbenchGitHubContextPath -Raw
    $codiconSourceCount = @(Get-ChildItem -LiteralPath $codiconRoot -Filter '*.svg' -File | Where-Object { $_.Name -notin @('sprite.svg', 'preview.svg') }).Count
    $octiconSourceCount = @(Get-ChildItem -LiteralPath $octiconRoot -Filter '*.svg' -File | Where-Object { $_.Name -notin @('sprite.svg', 'preview.svg') }).Count
    $fluentIconSourceNames = @(Get-ChildItem -LiteralPath $fluentIconRoot -Filter '*.svg' -File | Where-Object { $_.Name -notin @('sprite.svg', 'preview.svg') } | ForEach-Object { $_.BaseName } | Sort-Object)
    $fluentIconSourceCount = $fluentIconSourceNames.Count
    $fluentIconSymbolNames = @([regex]::Matches($fluentIconSpriteContent, '<symbol id="fluent-(?<name>[^"]+)"') | ForEach-Object { [string]$_.Groups['name'].Value } | Sort-Object)
    $fluentIconCoreMatch = [regex]::Match($appContent, 'const CORE_FLUENT_ICON_NAMES = new Set\(\[(?<names>[\s\S]*?)\]\);')
    $fluentIconCoreNames = @([regex]::Matches($fluentIconCoreMatch.Groups['names'].Value, '"(?<name>[a-z0-9-]+)"') | ForEach-Object { [string]$_.Groups['name'].Value } | Sort-Object)
    $fluentIconConsumerNames = @([regex]::Matches($appContent, 'fluentIcon\("(?<name>[a-z0-9-]+)"') | ForEach-Object { [string]$_.Groups['name'].Value } | Sort-Object -Unique)
    $fluentIconPairGroups = @($fluentIconSourceNames | Group-Object { $_ -replace '-(regular|filled)$', '' })
    $fluentIconRuntimeNames = @(
        'arrow-undo-20-filled',
        'arrow-routing-20-regular',
        'arrow-split-20-regular',
        'checkmark-circle-20-filled',
        'gauge-16-regular',
        'info-20-regular',
        'link-dismiss-16-filled',
        'link-multiple-16-filled',
        'warning-20-regular'
    ) | Sort-Object
    $codiconContractValid = $codiconSourceCount -eq [regex]::Matches($generatedSpriteContent, '<symbol id="codicon-').Count
    $copilotIconNames = @(
        'copilot', 'copilot-blocked', 'copilot-compact', 'copilot-dot', 'copilot-dot-compact',
        'copilot-error', 'copilot-in-progress', 'copilot-large', 'copilot-not-connected',
        'copilot-snooze', 'copilot-success', 'copilot-unavailable', 'copilot-warning', 'copilot-warning-large'
    )
    foreach ($copilotIconName in $copilotIconNames) {
        $copilotSource = [xml](Get-Content -LiteralPath (Join-Path $codiconRoot "$copilotIconName.svg") -Raw)
        $expectedViewBox = if ($copilotIconName.EndsWith('-compact')) { '0 0 12 12' } elseif ($copilotIconName.EndsWith('-large')) { '0 0 50 50' } else { '0 0 16 16' }
        $codiconContractValid = $codiconContractValid -and
            $copilotSource.svg.viewBox -ceq $expectedViewBox -and
            $generatedSpriteContent.Contains("<symbol id=`"codicon-$copilotIconName`" viewBox=`"$expectedViewBox`">") -and
            $iconGeneratorContent.Contains("'$copilotIconName'")
    }
    $contextIconNames = @(
        'edit', 'edit-code', 'edit-compact', 'edit-session', 'edit-sparkle',
        'terminal', 'terminal-bash', 'terminal-cmd', 'terminal-compact', 'terminal-debian',
        'terminal-git-bash', 'terminal-linux', 'terminal-powershell', 'terminal-secure',
        'terminal-tmux', 'terminal-ubuntu', 'tools'
    )
    foreach ($contextIconName in $contextIconNames) {
        $contextIconSource = [xml](Get-Content -LiteralPath (Join-Path $codiconRoot "$contextIconName.svg") -Raw)
        $expectedViewBox = if ($contextIconName.EndsWith('-compact')) { '0 0 12 12' } elseif ($contextIconName -ceq 'terminal') { '0 0 24 24' } else { '0 0 16 16' }
        $codiconContractValid = $codiconContractValid -and
            $contextIconSource.svg.viewBox -ceq $expectedViewBox -and
            $generatedSpriteContent.Contains("<symbol id=`"codicon-$contextIconName`" viewBox=`"$expectedViewBox`">") -and
            $iconGeneratorContent.Contains("'$contextIconName'")
    }
    $layoutIconNames = @(
        'layout', 'layout-activitybar-left', 'layout-activitybar-right', 'layout-centered',
        'layout-density-compact', 'layout-density-default', 'layout-menubar', 'layout-panel',
        'layout-panel-center', 'layout-panel-dock', 'layout-panel-justify', 'layout-panel-left',
        'layout-panel-off', 'layout-panel-right', 'layout-sidebar-left', 'layout-sidebar-left-dock',
        'layout-sidebar-left-off', 'layout-sidebar-right', 'layout-sidebar-right-dock',
        'layout-sidebar-right-off', 'layout-statusbar'
    )
    foreach ($layoutIconName in $layoutIconNames) {
        $layoutIconSource = (Get-Content -LiteralPath (Join-Path $codiconRoot "$layoutIconName.svg") -Raw).Trim()
        $layoutIconDocument = [xml]$layoutIconSource
        $layoutIconContent = [regex]::Match($layoutIconSource, '^<svg[^>]*>(?<content>[\s\S]*)</svg>$').Groups['content'].Value.Trim()
        $codiconContractValid = $codiconContractValid -and
            $layoutIconDocument.svg.viewBox -ceq '0 0 16 16' -and
            $generatedSpriteContent.Contains("<symbol id=`"codicon-$layoutIconName`" viewBox=`"0 0 16 16`">$layoutIconContent</symbol>") -and
            $iconGeneratorContent.Contains("'$layoutIconName'")
    }
    $codiconContractValid = $codiconContractValid -and $spriteContent -match 'id="codicon-discard"' -and $spriteContent -match 'id="codicon-git-commit"' -and $spriteContent -match 'id="codicon-git-branch-compact"' -and $spriteContent -match 'id="codicon-git-branch-conflicts"' -and $spriteContent -match 'id="codicon-git-pull-request-error"' -and $spriteContent -match 'id="codicon-json"' -and $spriteContent -match 'id="codicon-collection"' -and $spriteContent -match 'id="codicon-collection-small"' -and $spriteContent -match 'id="codicon-new-session"' -and $spriteContent -match 'id="codicon-open-preview"'
    $codiconContractValid = $codiconContractValid -and $spriteContent -match 'id="codicon-check-compact"' -and $spriteContent -match 'id="codicon-circle-slash-compact"' -and $spriteContent -match 'id="codicon-debug-disconnect-compact"' -and $spriteContent -match 'id="codicon-checklist-compact"' -and $spriteContent -match 'id="codicon-shield-compact"' -and $spriteContent -match 'id="codicon-warning-compact"' -and $spriteContent -match 'id="codicon-chevron-right-compact"' -and $spriteContent -match 'id="codicon-chevron-down-compact"' -and $spriteContent -match 'id="codicon-fold-up"' -and $spriteContent -match 'id="codicon-diff-modified"' -and $spriteContent -match 'id="codicon-arrow-circle-down"' -and $spriteContent -match 'id="codicon-arrow-circle-left"' -and $spriteContent -match 'id="codicon-arrow-circle-right"' -and $spriteContent -match 'id="codicon-arrow-circle-up"' -and $spriteContent -match 'id="codicon-arrow-circle-up-sparkle"' -and $spriteContent -match 'id="codicon-close"' -and $spriteContent -match 'id="codicon-close-small"' -and $spriteContent -match 'id="codicon-close-compact"' -and $spriteContent -match 'id="codicon-pass"' -and $spriteContent -match 'id="codicon-pass-compact"' -and $spriteContent -match 'id="codicon-git-stash-apply"' -and $spriteContent -match 'id="codicon-kebab-vertical"' -and $spriteContent -match 'id="codicon-layers"'
    $codiconContractValid = $codiconContractValid -and $spriteContent -match 'id="codicon-folder-opened"' -and $spriteContent -match 'id="codicon-folder-opened-compact"' -and $spriteContent -match 'id="codicon-folder-library"' -and $spriteContent -match 'id="codicon-folder-compact"' -and $spriteContent -match 'id="codicon-folder-active"' -and $spriteContent -match 'id="codicon-file-symlink-directory"' -and $spriteContent -match 'id="codicon-remote"' -and $spriteContent -match 'id="codicon-remote-compact"' -and $spriteContent -match 'id="codicon-workspace-untrusted"' -and $spriteContent -match 'id="codicon-workspace-unknown"'
    $codiconContractValid = $codiconContractValid -and $spriteContent -match '1c47ab36a4bb845c437866405c2fa67b8ca0fe36' -and $attributionContent -match 'Creative Commons Attribution 4\.0 International'
    $codiconContractValid = $codiconContractValid -and $iconGeneratorContent -match '\.\./\.\./\.\./workbench/icons' -and $iconGeneratorContent -match 'Get-Content -LiteralPath \$sourcePath -Raw' -and $iconGeneratorContent -match "'fold-up'" -and $iconGeneratorContent -match "'diff-modified'" -and $iconGeneratorContent -match "'arrow-circle-up'" -and $iconGeneratorContent -match "'arrow-circle-up-sparkle'" -and $iconGeneratorContent -match "'remote'" -and $iconGeneratorContent -match "'remote-compact'" -and $iconGeneratorContent -match "'warning-compact'" -and $iconGeneratorContent -notmatch 'Invoke-WebRequest|Invoke-RestMethod|https://raw'
    $codiconContractValid = $codiconContractValid -and (Get-FileHash -Algorithm SHA256 -LiteralPath (Join-Path $codiconRoot 'warning-compact.svg')).Hash -ceq 'D007D0454B990CEA5CA463B5FFA60B8BCD475636B72C654311B09193C1A1E0CD'
    $codiconContractValid = $codiconContractValid -and $launcherContent -match 'workbenchIconSource' -and $launcherContent -match 'Copy-Item -LiteralPath \$workbenchIconSource -Destination \$resolvedSiteDirectory -Recurse -Force'
    $codiconContractValid = $codiconContractValid -and $indexContent -notmatch 'cdn\.jsdelivr|data-lucide|lucide\.min\.js' -and $appContent -notmatch 'data-lucide|window\.lucide|refreshIcons' -and $appContent -match 'function icon\(name\)' -and $appContent -match 'icons/codicons/sprite\.svg#codicon-\$\{name\}' -and $appContent -match 'data-detail-back-to-top[\s\S]*?icon\("arrow-circle-up"\)'
    $codiconContractValid = $codiconContractValid -and $stylesContent -match '\.detail-back-to-top\s*\{[^}]*width:\s*26px;[^}]*height:\s*26px;[^}]*color:\s*var\(--accent-bright\);[^}]*background:\s*transparent;[^}]*border:\s*0;[^}]*border-radius:\s*0' -and $stylesContent -match '\.detail-back-to-top > \.codicon\s*\{[^}]*width:\s*26px;[^}]*height:\s*26px'
    $codiconContractValid = $codiconContractValid -and $indexContent -match 'icons/codicons/sprite\.svg#codicon-json' -and $statusbarContent -match 'icon: "git-branch-compact"' -and $statusbarContent -match 'icon: "check-compact"' -and $statusbarContent -match 'icon: "collection"' -and $statusbarContent -match 'icon: "circle-slash-compact"' -and $statusbarContent -match 'icon: "new-session"' -and $statusbarContent -match 'icon: "shield-compact"'
    $codiconContractValid = $codiconContractValid -and $appContent -match 'octicon\("copy"\)' -and $appContent -match '\$\{octicon\(iconName\)\}' -and $indexContent -match 'data-view="catalog"[\s\S]*?codicon-collection' -and $indexContent -match 'data-view="plan"[\s\S]*?codicon-new-session' -and $indexContent -match 'data-view="preview"[\s\S]*?codicon-open-preview' -and $appContent -match 'icon\("discard"\)'
    $chatSparkleErrorContractValid = (Test-Path -LiteralPath (Join-Path $codiconRoot 'chat-sparkle-error.svg') -PathType Leaf) -and $generatedSpriteContent -match 'id="codicon-chat-sparkle-error"' -and $iconGeneratorContent -match "'chat-sparkle-error'"
    $discardAllContractValid = (Test-Path -LiteralPath (Join-Path $codiconRoot 'discard-all.svg') -PathType Leaf) -and ([regex]::Matches($generatedSpriteContent, '<symbol id="codicon-').Count -eq $codiconSourceCount) -and $generatedSpriteContent -match 'id="codicon-discard-all"' -and $attributionContent -match '`discard-all\.svg` is a local derivative of `discard\.svg`' -and $iconGeneratorContent -match "'discard-all'"
    $diffModifiedContractValid = (Test-Path -LiteralPath (Join-Path $codiconRoot 'diff-modified.svg') -PathType Leaf) -and $generatedSpriteContent -match 'id="codicon-diff-modified"' -and $appContent -match 'codicon-diff-modified'
    $collectionIssuesContractValid = (Test-Path -LiteralPath (Join-Path $codiconRoot 'collection-issues-compact.svg') -PathType Leaf) -and
        $generatedSpriteContent -match '<symbol id="codicon-collection-issues-compact" viewBox="0 0 16 16">' -and
        $iconGeneratorContent -match "'collection-issues-compact'" -and
        $attributionContent -match '`collection-issues-compact\.svg` is a local derivative of `collection\.svg`' -and
        $statusbarContent -match 'key: "ruleIssues",[^}]*icon: "collection-issues-compact"' -and
        $statusbarContent -notmatch 'key: "ruleIssues",[^}]*iconFamily: "fluent"' -and
        $statusbarContent -match 'key: "eligible",[^}]*icon: "collection"' -and
        $statusbarContent -match 'key: "warnings",[^}]*icon: "warning-compact"'
    $codiconContractValid = $codiconContractValid -and $chatSparkleErrorContractValid -and $discardAllContractValid -and $diffModifiedContractValid -and $collectionIssuesContractValid
    $standaloneIconContractValid = @(Get-ChildItem -LiteralPath $iconRoot -File).Count -eq 0
    $octiconContractValid = $standaloneIconContractValid -and $octiconSourceCount -eq [regex]::Matches($octiconSpriteContent, '<symbol id="octicon-').Count -and $octiconSpriteContent -match 'id="octicon-code-review-16"' -and $octiconSpriteContent -match 'id="octicon-file-diff-16"' -and $octiconSpriteContent -match 'id="octicon-file-directory-fill-16"' -and $octiconSpriteContent -match 'id="octicon-file-directory-open-fill-16"' -and $octiconSpriteContent -match 'id="octicon-filter-16"' -and $octiconSpriteContent -match 'id="octicon-people-16"' -and $octiconSpriteContent -match 'id="octicon-shield-lock-16"' -and $octiconSpriteContent -match 'id="octicon-square-16"' -and $octiconSpriteContent -match 'id="octicon-diff-added-16"' -and $octiconSpriteContent -match 'id="octicon-diff-removed-16"' -and $octiconSpriteContent -match 'id="octicon-fold-16"' -and $octiconSpriteContent -match 'id="octicon-fold-up-16"' -and $octiconSpriteContent -match 'id="octicon-fold-down-16"' -and $octiconSpriteContent -match 'id="octicon-unfold-16"' -and $octiconSpriteContent -match 'id="octicon-comment-ai-16"' -and $octiconSpriteContent -match '6220ff87f3ddd923b05ffdac7e2d9cb714213205' -and $octiconAttributionContent -match 'GitHub''s Primer Octicons' -and $octiconAttributionContent -match 'MIT License' -and (Get-Content -LiteralPath (Join-Path $octiconRoot 'LICENSE.txt') -Raw) -match 'MIT License' -and $octiconGeneratorContent -match '\.\./\.\./\.\./workbench/icons/octicons' -and $octiconGeneratorContent -match 'Get-Content -LiteralPath \$sourcePath -Raw' -and $octiconGeneratorContent -notmatch 'Invoke-WebRequest|Invoke-RestMethod|https://raw' -and $appContent -match 'function octicon\(name\)' -and $appContent -match 'gap\.direction === "up" \? "fold-up" : gap\.direction === "down" \? "fold-down" : "unfold"' -and $appContent -match '\$\{octicon\(iconName\)\}' -and $stylesContent -match '\.codicon,\s*\.octicon\s*\{'
    $fluentIconContractValid = $fluentIconSourceCount -eq 750 -and $fluentIconSymbolNames.Count -eq 9 -and $fluentIconPairGroups.Count -eq 375 -and $fluentIconCoreMatch.Success -and $fluentIconCoreNames.Count -eq 142 -and @(Compare-Object $fluentIconRuntimeNames $fluentIconSymbolNames).Count -eq 0 -and @($fluentIconPairGroups | Where-Object { $_.Count -ne 2 }).Count -eq 0 -and @($fluentIconCoreNames | Where-Object { $_ -notin $fluentIconSourceNames }).Count -eq 0 -and @($fluentIconRuntimeNames | Where-Object { $_ -notin $fluentIconSourceNames }).Count -eq 0 -and @($fluentIconConsumerNames | Where-Object { $_ -notin $fluentIconRuntimeNames }).Count -eq 0
    foreach ($fluentIconFamily in @('checkmark-circle', 'dismiss-circle', 'error-circle', 'important', 'info', 'question-circle', 'warning', 'shield-checkmark', 'shield-dismiss', 'shield-error', 'shield-question', 'shield-task', 'document-add', 'document-bullet-list', 'document-checkmark', 'document-dismiss', 'document-edit', 'document-error', 'document-lock', 'document-search', 'document-sync', 'document-text', 'approvals-app', 'arrow-sync-circle', 'book-information', 'bot-sparkle', 'brain-circuit', 'certificate', 'clipboard-checkmark', 'clipboard-task-list-ltr', 'data-usage', 'gauge', 'history', 'lightbulb', 'person-feedback', 'target-arrow', 'arrow-routing', 'arrow-routing-rectangle-multiple', 'arrow-split', 'flow', 'flowchart', 'link-multiple', 'connected', 'group-list', 'shape-intersect', 'merge', 'stack', 'stack-arrow-forward', 'gavel', 'gavel-prohibited', 'scales', 'checkbox-checked-sync', 'flag-checkered', 'ribbon', 'ribbon-off', 'person-edit', 'archive', 'archive-arrow-back', 'arrow-undo', 'arrow-redo', 'arrow-sync-checkmark', 'arrow-sync-dismiss', 're-order', 'document-copy', 'document-arrow-right', 'clipboard-search', 'clipboard-text-ltr', 'text-quote', 'database-search', 'task-list-square-sparkle', 'wand')) {
        $fluentIconContractValid = $fluentIconContractValid -and "$fluentIconFamily-20-regular" -in $fluentIconSourceNames -and "$fluentIconFamily-20-filled" -in $fluentIconSourceNames
    }
    $fluentIconContractValid = $fluentIconContractValid -and $fluentIconSpriteContent -match 'a347af95478f989038cccbf085978865264c048a' -and $fluentIconAttributionContent -match 'Microsoft Fluent UI System Icons' -and $fluentIconAttributionContent -match 'regular and filled variants' -and $fluentIconAttributionContent -match 'MIT License' -and $fluentIconAttributionContent -match 'a347af95478f989038cccbf085978865264c048a' -and $fluentIconGeneratorContent -match '\.\./\.\./\.\./workbench/icons/fluent' -and $fluentIconGeneratorContent -match 'Get-Content -LiteralPath \$sourcePath -Raw' -and $fluentIconGeneratorContent -match 'New-WorkbenchIconPreview' -and $fluentIconGeneratorContent -match 'SymbolMarkup' -and $fluentIconGeneratorContent -notmatch 'Invoke-WebRequest|Invoke-RestMethod|https://raw' -and $appContent -match 'const CORE_FLUENT_ICON_NAMES = new Set' -and $appContent -match 'function fluentIcon\(name' -and $appContent -match 'icons/fluent/sprite\.svg#fluent-\$\{name\}' -and $appContent -match 'icons/fluent/sprite\.svg", "fluent-info-20-regular' -and $statusbarContent -match 'icon: "link-multiple-16-filled"[\s\S]*?iconFamily: "fluent"' -and $statusbarContent -match 'icon: "link-dismiss-16-filled"[\s\S]*?iconFamily: "fluent"' -and $statusbarContent -match 'icon: "gauge-16-regular"[\s\S]*?iconFamily: "fluent"' -and $statusbarContent -match 'icons/fluent/sprite\.svg#fluent-\$\{name\}' -and $stylesContent -match '\.fluent-icon\s*\{'
    $fluentIconContractValid = $fluentIconContractValid -and $appContent -match 'function renderRuleActionResolutionInformationIcon\(' -and $appContent -match 'class="rule-action-resolution-information-heading">Information<' -and $appContent -match 'class="rule-action-resolution-information-body">' -and $appContent -match 'fluentIcon\("warning-20-regular"\)' -and $appContent -match 'fluentIcon\("arrow-undo-20-filled"\)' -and $stylesContent -match '\.modal-dialog-warning \.modal-dialog-heading\s*\{[^}]*var\(--gold-soft\)[^}]*var\(--warning-action-border\)' -and $stylesContent -match '--rule-action-information-background-start:\s*#244f69' -and $stylesContent -match '--rule-action-information-background-end:\s*#1b3d53' -and $stylesContent -match '--rule-action-information-frame:\s*#79bbe6' -and $stylesContent -match '--rule-action-information-foreground:\s*#e7f5ff' -and $stylesContent -match '--rule-action-information-heading-start:\s*#062f6d' -and $stylesContent -match '--rule-action-information-heading-middle:\s*#2f73bc' -and $stylesContent -match '--rule-action-information-heading-end:\s*#79bbe6' -and $stylesContent -match '--rule-action-information-divider-highlight:\s*#e7efff' -and $stylesContent -match '--rule-action-information-icon-background:\s*#3f91c2' -and $stylesContent -match '--rule-action-information-icon-foreground:\s*#ffffff' -and $stylesContent -match '\.rule-action-resolution-information\s*\{[^}]*linear-gradient\(var\(--rule-action-information-background-start\), var\(--rule-action-information-background-end\)\)[^}]*var\(--rule-action-information-frame\)[^}]*border-radius:\s*0 0 8px 8px' -and $stylesContent -match '\.rule-action-resolution-information-heading\s*\{[^}]*100% 1px no-repeat,[^}]*32%[^}]*68%' -and $stylesContent -match '\.rule-action-resolution-information-body\s*\{[^}]*grid-template-columns:\s*20px minmax\(0, 1fr\)[^}]*gap:\s*10px'
    $iconPreviewsValid = $iconGeneratorContent -match 'New-WorkbenchIconPreview' -and $octiconGeneratorContent -match 'New-WorkbenchIconPreview' -and $fluentIconGeneratorContent -match 'New-WorkbenchIconPreview' -and $iconPreviewContent -match 'fill="#f0f6fc"' -and $iconPreviewContent -match 'Render-WorkbenchIconPreview\.cjs' -and $iconPreviewContent -match 'Get-Command node' -and $iconPreviewContent -notmatch 'Start-Process|Microsoft Edge|msedge' -and $iconPreviewRendererContent -match 'require\("puppeteer"\)' -and $iconPreviewRendererContent -match 'headless:\s*true' -and (Test-PngFile -Path (Join-Path $codiconRoot 'preview.png')) -and (Test-PngFile -Path (Join-Path $octiconRoot 'preview.png')) -and (Test-PngFile -Path (Join-Path $fluentIconRoot 'preview.png'))
    $llmIconSources = @(Get-ChildItem -LiteralPath $llmIconRoot -Filter '*.svg' -File | Where-Object { $_.Name -notin @('sprite.svg', 'preview.svg') } | Sort-Object Name)
    $llmIconSourceNames = @($llmIconSources | ForEach-Object BaseName)
    $llmIconDocument = [xml]$llmIconSpriteContent
    $llmIconSymbols = @($llmIconDocument.svg.symbol)
    $llmIconSymbolNames = @($llmIconSymbols | ForEach-Object { $_.GetAttribute('id') -replace '^llm-', '' } | Sort-Object)
    $llmBrandMap = Get-Content -LiteralPath (Join-Path $workbenchRoot 'llm-brands.json') -Raw | ConvertFrom-Json -NoEnumerate
    $llmRuntimeIconNames = @($llmBrandMap.icon | Sort-Object -Unique -CaseSensitive)
    $llmIconContractValid = $llmIconSourceNames.Count -eq 340 -and $llmIconSymbols.Count -eq $llmRuntimeIconNames.Count -and
        @(Compare-Object $llmRuntimeIconNames $llmIconSymbolNames -CaseSensitive).Count -eq 0 -and
        @($llmRuntimeIconNames | Where-Object { $_ -cnotin $llmIconSourceNames }).Count -eq 0 -and
        @($llmIconSourceNames | Where-Object { $_ -cnotmatch '^[a-z0-9]+$' }).Count -eq 0 -and
        $llmIconSpriteContent -match '8a1b2821bb768c484fe8da20c5e1838b6bf551a9' -and
        $llmIconAttributionContent -match 'Lobe Icons' -and $llmIconAttributionContent -match 'MIT License' -and
        $llmIconAttributionContent -match '8a1b2821bb768c484fe8da20c5e1838b6bf551a9' -and
        (Get-Content -LiteralPath (Join-Path $llmIconRoot 'LICENSE.txt') -Raw) -match 'MIT License' -and
        $llmIconGeneratorContent -match 'New-WorkbenchIconPreview' -and
        $iconPreviewContent -match 'color="#f0f6fc"' -and
        $llmIconGeneratorContent -notmatch 'Invoke-WebRequest|Invoke-RestMethod|https://raw' -and
        $appContent -match 'function llmIcon\(name\)' -and $appContent -match 'function renderLlmModelIcon\(model\)' -and
        $appContent.Contains('${renderLlmModelIcon(profile?.model)}') -and $appContent -match 'icon\("question"\)' -and
        $appContent -match 'icons/llms/sprite\.svg#llm-\$\{name\}' -and
        $appContent.Contains('new Set(llmBrandMap.map') -and $appContent -match 'codicon-question' -and
        $spriteContent -match 'id="codicon-question"' -and
        $llmIconGeneratorContent -match 'SymbolMarkup \$symbols' -and
        $appContent -notmatch 'icons/openai\.svg|assist-gpt-icon' -and
        $stylesContent -match '\.llm-icon\s*\{[^}]*width:\s*12px;[^}]*height:\s*12px;[^}]*fill:\s*currentColor;[^}]*stroke:\s*none' -and
        (Test-PngFile -Path (Join-Path $llmIconRoot 'preview.png'))
    foreach ($source in $llmIconSources) {
        if ($source.BaseName -cnotin $llmRuntimeIconNames) { continue }
        $sourceDocument = [xml](Get-Content -LiteralPath $source.FullName -Raw)
        $symbol = $llmIconSymbols | Where-Object { $_.GetAttribute('id') -ceq "llm-$($source.BaseName)" }
        $llmIconContractValid = $llmIconContractValid -and $sourceDocument.DocumentElement.InnerXml -ceq $symbol.InnerXml
        foreach ($attributeName in @('viewBox', 'fill', 'fill-rule')) {
            $llmIconContractValid = $llmIconContractValid -and
                $sourceDocument.DocumentElement.GetAttribute($attributeName) -ceq $symbol.GetAttribute($attributeName)
        }
        $expectedFilter = if ($sourceDocument.DocumentElement.GetAttribute('style').Contains('filter:grayscale(100%)')) { 'grayscale(100%)' } else { '' }
        $llmIconContractValid = $llmIconContractValid -and $symbol.GetAttribute('filter') -ceq $expectedFilter
    }
    $llmIconIds = @($llmIconDocument.SelectNodes('//*[@id]') | ForEach-Object { $_.GetAttribute('id') })
    $llmIconContractValid = $llmIconContractValid -and @($llmIconIds | Sort-Object -Unique).Count -eq $llmIconIds.Count
    foreach ($attribute in $llmIconDocument.SelectNodes('//@*')) {
        foreach ($reference in [regex]::Matches($attribute.Value, 'url\(#(?<id>[^)]+)\)')) {
            $llmIconContractValid = $llmIconContractValid -and $llmIconIds -ccontains $reference.Groups['id'].Value
        }
    }
    $iconFamiliesValid = $codiconContractValid -and $octiconContractValid -and $fluentIconContractValid -and $llmIconContractValid -and $iconPreviewsValid
    Add-TestResult -Name 'local-icon-family-sprites' -Passed $iconFamiliesValid -Detail 'Pinned icon families remain separate; the LLM runtime sprite matches the branding map, its full 340-icon preview is retained, the unknown-brand symbol belongs to Codicons, and mapped artwork and fragment references are preserved.'

    if (Test-ShouldRun -Name 'portable-icon-generation') {
        Start-TestResult -Name 'portable-icon-generation'
        $iconGenerationRoot = Join-Path $tempRoot 'icon-generation'
        $generatedCodiconRoot = Join-Path $iconGenerationRoot 'codicons'
        $generatedOcticonRoot = Join-Path $iconGenerationRoot 'octicons'
        $generatedFluentIconRoot = Join-Path $iconGenerationRoot 'fluent'
        $generatedLlmIconRoot = Join-Path $iconGenerationRoot 'llms'
        New-Item -ItemType Directory -Path $iconGenerationRoot -Force | Out-Null
        Copy-Item -LiteralPath $codiconRoot -Destination $generatedCodiconRoot -Recurse
        Copy-Item -LiteralPath $octiconRoot -Destination $generatedOcticonRoot -Recurse
        Copy-Item -LiteralPath $fluentIconRoot -Destination $generatedFluentIconRoot -Recurse
        Copy-Item -LiteralPath $llmIconRoot -Destination $generatedLlmIconRoot -Recurse
        Remove-Item -LiteralPath (Join-Path $generatedLlmIconRoot 'sprite.svg'), (Join-Path $generatedLlmIconRoot 'preview.png') -Force
        Remove-Item -LiteralPath (Join-Path $generatedCodiconRoot 'sprite.svg'), (Join-Path $generatedCodiconRoot 'preview.png'), (Join-Path $generatedOcticonRoot 'sprite.svg'), (Join-Path $generatedOcticonRoot 'preview.png'), (Join-Path $generatedFluentIconRoot 'sprite.svg'), (Join-Path $generatedFluentIconRoot 'preview.png') -Force -ErrorAction SilentlyContinue
        $codiconGenerationOutput = @(& pwsh -NoProfile -File $iconGeneratorPath -IconDirectory $generatedCodiconRoot 2>&1)
        $codiconGenerationExitCode = if ($null -ne $LASTEXITCODE) { $LASTEXITCODE } else { 0 }
        $octiconGenerationOutput = @(& pwsh -NoProfile -File $octiconGeneratorPath -IconDirectory $generatedOcticonRoot 2>&1)
        $octiconGenerationExitCode = if ($null -ne $LASTEXITCODE) { $LASTEXITCODE } else { 0 }
        $fluentIconGenerationOutput = @(& pwsh -NoProfile -File $fluentIconGeneratorPath -IconDirectory $generatedFluentIconRoot 2>&1)
        $fluentIconGenerationExitCode = if ($null -ne $LASTEXITCODE) { $LASTEXITCODE } else { 0 }
        $llmIconGenerationOutput = @(& pwsh -NoProfile -File $llmIconGeneratorPath -IconDirectory $generatedLlmIconRoot 2>&1)
        $llmIconGenerationExitCode = if ($null -ne $LASTEXITCODE) { $LASTEXITCODE } else { 0 }
        $generatedCodiconSprite = if (Test-Path -LiteralPath (Join-Path $generatedCodiconRoot 'sprite.svg') -PathType Leaf) { Get-Content -LiteralPath (Join-Path $generatedCodiconRoot 'sprite.svg') -Raw } else { '' }
        $generatedOcticonSprite = if (Test-Path -LiteralPath (Join-Path $generatedOcticonRoot 'sprite.svg') -PathType Leaf) { Get-Content -LiteralPath (Join-Path $generatedOcticonRoot 'sprite.svg') -Raw } else { '' }
        $generatedFluentIconSprite = if (Test-Path -LiteralPath (Join-Path $generatedFluentIconRoot 'sprite.svg') -PathType Leaf) { Get-Content -LiteralPath (Join-Path $generatedFluentIconRoot 'sprite.svg') -Raw } else { '' }
        $generatedLlmIconSprite = if (Test-Path -LiteralPath (Join-Path $generatedLlmIconRoot 'sprite.svg') -PathType Leaf) { Get-Content -LiteralPath (Join-Path $generatedLlmIconRoot 'sprite.svg') -Raw } else { '' }
        $portableIconGenerationValid = $codiconGenerationExitCode -eq 0 -and $octiconGenerationExitCode -eq 0 -and $fluentIconGenerationExitCode -eq 0 -and $llmIconGenerationExitCode -eq 0 -and
            [regex]::Matches($generatedCodiconSprite, '<symbol id="codicon-').Count -eq $codiconSourceCount -and
            [regex]::Matches($generatedOcticonSprite, '<symbol id="octicon-').Count -eq $octiconSourceCount -and
            [regex]::Matches($generatedFluentIconSprite, '<symbol id="fluent-').Count -eq $fluentIconRuntimeNames.Count -and
            $generatedLlmIconSprite -ceq $llmIconSpriteContent -and
            (Test-PngFile -Path (Join-Path $generatedLlmIconRoot 'preview.png')) -and
            (Test-PngFile -Path (Join-Path $generatedCodiconRoot 'preview.png')) -and
            (Test-PngFile -Path (Join-Path $generatedOcticonRoot 'preview.png')) -and
            (Test-PngFile -Path (Join-Path $generatedFluentIconRoot 'preview.png')) -and
            -not (Test-Path -LiteralPath (Join-Path $generatedCodiconRoot 'preview.svg')) -and
            -not (Test-Path -LiteralPath (Join-Path $generatedOcticonRoot 'preview.svg')) -and
            -not (Test-Path -LiteralPath (Join-Path $generatedFluentIconRoot 'preview.svg')) -and
            -not (Test-Path -LiteralPath (Join-Path $generatedLlmIconRoot 'preview.svg'))
        Remove-Item -LiteralPath (Join-Path $generatedLlmIconRoot 'LICENSE.txt') -Force
        $missingLlmLicenseOutput = @(& pwsh -NoProfile -File $llmIconGeneratorPath -IconDirectory $generatedLlmIconRoot 2>&1)
        $missingLlmLicenseExitCode = $LASTEXITCODE
        Copy-Item -LiteralPath (Join-Path $llmIconRoot 'LICENSE.txt') -Destination $generatedLlmIconRoot
        Remove-Item -LiteralPath (Join-Path $generatedLlmIconRoot 'openai.svg') -Force
        $missingLlmSourceOutput = @(& pwsh -NoProfile -File $llmIconGeneratorPath -IconDirectory $generatedLlmIconRoot 2>&1)
        $missingLlmSourceExitCode = $LASTEXITCODE
        Copy-Item -LiteralPath (Join-Path $llmIconRoot 'openai.svg') -Destination $generatedLlmIconRoot
        foreach ($invalidMapping in @(
            @(@{ prefix = 'gpt-'; icon = 'notvendored' }),
            @(@{ prefix = 'gpt-'; icon = 'openai' }, @{ prefix = 'gpt-'; icon = 'claude' }),
            @(@{ prefix = 'gpt-'; icon = 'openai' }, @{ prefix = 'gpt-6-'; icon = 'openai' })
        )) {
            $invalidMapPath = Join-Path $iconGenerationRoot 'invalid-llm-brands.json'
            [IO.File]::WriteAllText($invalidMapPath, (ConvertTo-Json -InputObject $invalidMapping -Depth 4))
            $invalidMapOutput = @(& pwsh -NoProfile -File $llmIconGeneratorPath -IconDirectory $generatedLlmIconRoot -BrandMapPath $invalidMapPath 2>&1)
            $portableIconGenerationValid = $portableIconGenerationValid -and $LASTEXITCODE -ne 0 -and ($invalidMapOutput -join "`n") -match 'branding map contains'
        }
        $portableIconGenerationValid = $portableIconGenerationValid -and $missingLlmLicenseExitCode -ne 0 -and
            ($missingLlmLicenseOutput -join "`n") -match 'LLM icon license is missing' -and $missingLlmSourceExitCode -ne 0 -and
            ($missingLlmSourceOutput -join "`n") -match "LLM icon 'openai' is missing"
        $iconGenerationDetail = if ($portableIconGenerationValid) {
            'Regenerated all four icon-family sprites and PNG inventories in temporary directories; LLM generation is deterministic and explicitly rejects missing licenses and required source glyphs.'
        }
        else {
            "Codicon exit $codiconGenerationExitCode`: $(($codiconGenerationOutput | Out-String).Trim()); Octicon exit $octiconGenerationExitCode`: $(($octiconGenerationOutput | Out-String).Trim()); Fluent exit $fluentIconGenerationExitCode`: $(($fluentIconGenerationOutput | Out-String).Trim()); LLM exit $llmIconGenerationExitCode`: $(($llmIconGenerationOutput | Out-String).Trim()); Missing LLM license exit $missingLlmLicenseExitCode`: $($missingLlmLicenseOutput -join ' '); Missing LLM source exit $missingLlmSourceExitCode`: $($missingLlmSourceOutput -join ' ')"
        }
        Add-TestResult -Name 'portable-icon-generation' -Passed $portableIconGenerationValid -Detail $iconGenerationDetail
    }

    $browserContractValid = $indexContent -match '<title>Hosted Copilot Rule Manager</title>' -and $indexContent -match '<h1>HOSTED COPILOT RULE MANAGER</h1>' -and $indexContent -match 'class="title-draft-menu" id="draft-menu"[\s\S]*id="export-button"[\s\S]*for="import-input"[\s\S]*id="close-button"' -and $indexContent -match '<script src="statusbar\.js" defer></script>[\s\S]*<script src="app\.js" defer></script>' -and $indexContent -match 'class="ide-statusbar type-compact" aria-label="Workbench status"[\s\S]*class="status-cluster status-left"></div>[\s\S]*class="status-cluster status-right"></div>' -and $indexContent -notmatch 'id="status-target"|id="status-mapped"|id="status-headroom"|id="metrics-band"|Refresh candidates' -and $statusbarContent -match 'const STATUS_BAR_ENTRIES = Object\.freeze' -and $statusbarContent -match 'class WorkbenchStatusBarService' -and $statusbarContent -match 'key: "promotionApproval"[\s\S]*tooltip: "Promotion Approval Status"[\s\S]*kind: "warning"' -and $statusbarContent -match 'const workbenchStatusBar = new WorkbenchStatusBarService' -and $appContent -match 'workbenchStatusBar\.render\(\)' -and $appContent -match 'WORKBENCH_DISPLAY_SCHEMA_VERSION = 4' -and $appContent -match 'display\.schemaVersion !== WORKBENCH_DISPLAY_SCHEMA_VERSION' -and $appContent -match 'normalizeDisplayCandidates\(display\)' -and $appContent -match 'indexedDB\.open' -and $appContent -match 'localStorage\.setItem' -and $appContent -match 'hosted-rule-workbench-draft' -and $appContent -match 'async function preloadIconSprites\(\)' -and $appContent -match 'await preloadIconSprites\(\)' -and $appContent -match 'workbenchStatusBar\.update\("target"' -and $appContent -match 'workbenchStatusBar\.update\("mapped"' -and $appContent -notmatch 'elements\["metrics-band"\]\.innerHTML' -and $launcherContent -match "'statusbar\.js'"
    $shutdownPresentationValid = $appContent -match '<div class="shutdown-brand-lockup">\s*<svg class="shutdown-brand-icon" viewBox="0 0 16 16" aria-hidden="true"><path d="' -and $appContent -match '<p class="shutdown-product-name">HOSTED COPILOT RULE MANAGER</p>' -and $appContent -match '<h1>Workbench Closed</h1>' -and $appContent -notmatch '<span class="brand-mark" aria-hidden="true">HR</span>'
    $shutdownPresentationValid = $shutdownPresentationValid -and $stylesContent -match '\.shutdown-state\s*\{[^}]*justify-items:\s*center;[^}]*text-align:\s*center' -and $stylesContent -match '\.shutdown-brand-lockup\s*\{[^}]*display:\s*flex;[^}]*align-items:\s*center;[^}]*justify-content:\s*center' -and $stylesContent -match '\.shutdown-brand-icon\s*\{[^}]*width:\s*28px;[^}]*height:\s*28px;[^}]*color:\s*#ffff00;[^}]*fill:\s*currentColor' -and $stylesContent -match '\.shutdown-state \.shutdown-product-name\s*\{[^}]*font-size:\s*20px !important;[^}]*font-weight:\s*600 !important' -and $stylesContent -match 'html\.theme-hosted-dark body \.shutdown-state > h1\s*\{[^}]*font-size:\s*16px !important;[^}]*font-weight:\s*600 !important'
    $browserContractValid = $browserContractValid -and $shutdownPresentationValid
    Add-TestResult -Name 'browser-state-contract' -Passed $browserContractValid -Detail 'The IDE shell keeps draft portability in a compact title-bar menu, places shutdown at the far right, and renders the validated fork promotion target plus operational state directly into the status bar.'

    $savedStatusTooltipLiterals = @([regex]::Matches($appContent, 'setSaveIndicator\([^\r\n]*\btooltip:\s*"([^"]+)"') | ForEach-Object { $_.Groups[1].Value })
    $statusbarTooltipLiterals = @([regex]::Matches($statusbarContent, 'tooltip:\s*"([^"]+)"') | ForEach-Object { $_.Groups[1].Value }) + $savedStatusTooltipLiterals
    $tooltipLiterals = foreach ($content in @($indexContent, $appContent)) {
        foreach ($pattern in @('data-workbench-tooltip="([^"$<{]+)"', 'setWorkbenchTooltip\([^,]+,\s*"([^"$<{]+)"\)', 'tooltip:\s*"([^"$<{]+)"')) {
            foreach ($match in [regex]::Matches($content, $pattern)) {
                $label = $match.Groups[1].Value.Trim()
                if ($label -notin $savedStatusTooltipLiterals) { $label }
            }
        }
    }
    $tooltipProperNames = @('AI', 'AzureRM', 'CODEOWNER', 'Copilot', 'GitHub', 'Hosted', 'Workbench')
    $tooltipCaseViolations = @(foreach ($tooltipLiteral in @($tooltipLiterals | Sort-Object -Unique)) {
        if ($tooltipLiteral -ceq 'Hosted Copilot Rule Manager') {
            continue
        }
        $tooltipWords = @([regex]::Matches($tooltipLiteral, '[A-Za-z][A-Za-z''-]*') | ForEach-Object Value)
        if ($tooltipWords.Count -lt 2) {
            continue
        }
        $unexpectedCapitalization = @($tooltipWords[1..($tooltipWords.Count - 1)] | Where-Object {
                $_[0] -cmatch '[A-Z]' -and $_ -notin $tooltipProperNames -and $_ -cnotmatch '^[A-Z0-9]+$'
            })
        if ($unexpectedCapitalization.Count -gt 0) {
            "$tooltipLiteral ($($unexpectedCapitalization -join ', '))"
        }
    })
    Add-TestResult -Name 'tooltip-sentence-case' -Passed ($tooltipCaseViolations.Count -eq 0) -Detail $(if ($tooltipCaseViolations.Count -eq 0) { 'Authored non-status Workbench tooltips use sentence case while preserving product names and acronyms.' } else { "Unexpected tooltip capitalization: $($tooltipCaseViolations -join '; ')" })

    $statusbarTooltipCaseViolations = @(foreach ($label in $statusbarTooltipLiterals) {
        if (@([regex]::Matches($label, '[A-Za-z][A-Za-z''-]*') | Where-Object { $_.Value[0] -cmatch '[a-z]' }).Count -gt 0) {
            $label
        }
    })
    $statusbarTooltipCaseValid = $statusbarTooltipCaseViolations.Count -eq 0 -and
        $statusbarContent -cmatch 'key: "validationIssues"[\s\S]*?tooltip: "No Problems"[\s\S]*?key: "save"' -and
        $appContent -cmatch 'return `Rule Issues:' -and
        $appContent -cmatch '`Validation Issues:.*"Error".*"Warning"' -and
        $appContent -notmatch 'setSaveIndicator\("Checking relationships'
    Add-TestResult -Name 'statusbar-tooltip-title-case' -Passed $statusbarTooltipCaseValid -Detail $(if ($statusbarTooltipCaseValid) { 'Status-bar descriptions use Title Case, keep saved-edit Validation Issues separate from Rule Issues, and leave active validation to its local panel.' } else { "Status-bar tooltip contract failed. Unexpected casing: $($statusbarTooltipCaseViolations -join '; ')" })

    $timestampNormalizationValid = $appContent -match 'function toUtcTimestamp\(value = new Date\(\)\)' -and
        $appContent -match 'return date\.toISOString\(\)\.replace\(/Z\$/, "0000Z"\)' -and
        $appContent -match 'function normalizeSessionTimestamps\(session\)' -and
        $appContent -match 'const snapshot = normalizeSessionTimestamps\(state\.session\)' -and
        $appContent -match 'buildApprovedMutation\(candidate\)' -and
        $appContent -notmatch 'new Date\(\)\.toISOString\(\)'
    Add-TestResult -Name 'browser-timestamp-normalization' -Passed $timestampNormalizationValid -Detail 'Workbench persistence and exports use one browser canonicalizer that matches the PowerShell seven-digit UTC wire format.'

    $repositoryIdentityValid = $launcherContent -match 'modules/workbench/Workbench\.GitHubContext\.psm1' -and
        $launcherContent -match 'Get-HostedWorkbenchGitHubContext -RepositoryRoot \$repositoryRoot -SkipGitHubAuthorization:\$SkipGitHubAuthorization' -and
        $workbenchGitHubContextContent -match 'Import-Module \(Join-Path \$PSScriptRoot ''\.\./shared/HostedGitHub\.Helpers\.psm1''\) -Force' -and
        $workbenchGitHubContextContent -match 'function Get-HostedWorkbenchGitHubContext' -and
        $workbenchGitHubContextContent -match 'Get-HostedToolkitCodeOwners -CodeOwnersPath \$codeOwnersPath' -and
        $workbenchGitHubContextContent -match 'Get-HostedGitHubForkTarget -Login \$login' -and
        $workbenchGitHubContextContent -match "status = 'validated'" -and
        $hostedGitHubHelpersContent -match 'function Invoke-HostedGitHubApi' -and
        $hostedGitHubHelpersContent -match 'RedirectStandardOutput = \$true' -and
        $hostedGitHubHelpersContent -match 'RedirectStandardError = \$true' -and
        $hostedGitHubHelpersContent -match 'function Get-HostedToolkitCodeOwners' -and
        $hostedGitHubHelpersContent -match 'function Get-HostedGitHubForkTarget' -and
        $hostedGitHubHelpersContent -match "CanonicalRepository = 'hashicorp/terraform-provider-azurerm'" -and
        $appContent -match 'workbenchStatusBar\.update\("target", \{' -and
        $appContent -match 'tooltip: \[targetLabel, \.\.\.syncIndicators\]\.join\(" \| "\)' -and
        $appContent -match 'revision\?\.repository && revision\?\.configuredRef && shortCommit' -and
        $appContent -match '\$\{revision\.repository\} · \$\{revision\.configuredRef\}@\$\{shortCommit\}' -and
        $appContent -match 'data-workbench-tooltip="\$\{escapeHtml\(provenanceLabel\)\}"' -and
        $appContent -match 'function showWorkbenchTooltip\(item, anchorX' -and
        $appContent -match 'function getWorkbenchTooltipOwner\(target\)' -and
        $appContent -match 'function isWorkbenchTooltipDisabled\(owner\)' -and
        $appContent -match 'owner && !isWorkbenchTooltipDisabled\(owner\)' -and
        $appContent -match 'WORKBENCH_TOOLTIP_DELAY_MS = 500' -and
        $appContent -match 'document\.addEventListener\("pointerdown", handleWorkbenchTooltipPointerDown\)' -and
        $appContent -match 'workbenchTooltip\.showTimer = window\.setTimeout' -and
        $appContent -notmatch 'target\.querySelector\?\.\("\[data-truncation-tooltip\]"\)' -and
        $stylesContent -match '\.source-provenance-pill\s*\{[^}]*color:\s*var\(--success\);[^}]*border:\s*1px solid var\(--success\)' -and
        $stylesContent -match '\.status-surface-tooltip\.visible\s*\{[^}]*animation:\s*workbench-tooltip-fade-in 100ms linear' -and
        $stylesContent -match '@keyframes workbench-tooltip-fade-in'
    Add-TestResult -Name 'repository-identity-presentation' -Passed $repositoryIdentityValid -Detail 'The status bar identifies and safely truncates the writable AzureRM fork, uses amber only when it is behind, and exposes compact nonzero sync arrows through its parent-owned tooltip; both Contributor Guidance roots retain aligned green provenance pills.'

    $planActivityBadgeValid = $indexContent -match 'id="promotion-plan-stage"[^>]*title="Promotion Plan \(0\)"[^>]*aria-label="Promotion Plan \(0\)"' -and $indexContent -match 'class="stage-count-badge" id="plan-activity-count" aria-hidden="true" hidden' -and $appContent -match 'const planCount = getPlanCandidates\(\)\.length' -and $appContent -match 'workbenchStatusBar\.update\("plan", \{ text: formatNumber\(planCount\) \}\)' -and $appContent -match 'planCount > 999 \? "999\+" : formatNumber\(planCount\)' -and $appContent -match 'elements\["plan-activity-count"\]\.hidden = planCount === 0' -and $appContent -match 'const planLabel = `Promotion Plan \(\$\{formatNumber\(planCount\)\}\)`' -and $stylesContent -match '--activity-badge-background:\s*#307e9f' -and $stylesContent -match '--activity-badge-foreground:\s*#ffffff' -and $stylesContent -match '\.stage-count-badge\s*\{[^}]*right:\s*4px;[^}]*bottom:\s*5px;[^}]*min-width:\s*16px;[^}]*height:\s*16px;[^}]*color:\s*var\(--activity-badge-foreground\);[^}]*background:\s*var\(--activity-badge-background\);[^}]*border:\s*0;[^}]*border-radius:\s*999px' -and $stylesContent -match 'html\.theme-hosted-dark body \.stage-count-badge\s*\{[^}]*font-size:\s*10px !important;[^}]*font-weight:\s*600 !important;[^}]*line-height:\s*14px !important'
    $planActivityBadgeValid = $indexContent -match 'id="promotion-plan-stage"[^>]*data-workbench-tooltip="Open promotion plan \(0\)"[^>]*aria-label="Promotion Plan \(0\)"' -and
        $appContent -match 'planCount > 999 \? "999\+" : formatNumber\(planCount\)' -and
        $appContent -match 'setWorkbenchTooltip\(elements\["promotion-plan-stage"\], `Open promotion plan \(\$\{formatNumber\(planCount\)\}\)`\)' -and
        $stylesContent -match '\.stage-count-badge\s*\{[^}]*border-radius:\s*999px'
    Add-TestResult -Name 'promotion-plan-activity-badge' -Passed $planActivityBadgeValid -Detail 'The Promotion Plan rail badge hides at zero, displays exact counts through 999, expands left as a semibold pill, abbreviates larger counts to 999+, and preserves the exact localized count in the footer and accessibility text.'

    $keyboardNavigationValid = $appContent -match 'function handleRowKeyboardNavigation\(event, container, keyProperty, selectRow, activateRow = null\)' -and $appContent -match 'activateRow\?\.\(\)' -and $appContent -match 'event\.key !== "ArrowUp" && event\.key !== "ArrowDown"' -and $appContent -match 'candidateRow\.getClientRects\(\)\.length > 0' -and $appContent -match 'Math\.max\(0, Math\.min\(rows\.length - 1, currentIndex \+ offset\)\)' -and $appContent -match 'target\.focus\(\)' -and $appContent -match 'target\.scrollIntoView\(\{ block: "nearest" \}\)' -and $appContent -match 'event\.target\.matches\(''input\[type="checkbox"\]''\)' -and $appContent -match 'selectCandidate, \(\) => showCandidatePane\("details"\)' -and ([regex]::Matches($appContent, 'handleRowKeyboardNavigation\(event, elements\[').Count -eq 2) -and ([regex]::Matches($appContent, 'setAttribute\("aria-current", "true"\)').Count -eq 2) -and ([regex]::Matches($appContent, 'removeAttribute\("aria-current"\)').Count -eq 2)
    Add-TestResult -Name 'row-keyboard-navigation' -Passed $keyboardNavigationValid -Detail 'Arrow keys move candidate and assessment selection in place; Enter or Space opens the full-width Details view without intercepting leaf checkboxes or collapsed folders.'

    $assessmentDetailMatch = [regex]::Match($appContent, 'function renderAssessmentResultDetail\(\) \{(?<body>[\s\S]*?)\n\}\n\nfunction renderCandidateTreeRow')
    $assessmentDetailBody = if ($assessmentDetailMatch.Success) { $assessmentDetailMatch.Groups['body'].Value } else { '' }
    $workspaceTabMatch = [regex]::Match($appContent, 'function setWorkspaceTab\(tab\) \{(?<body>[\s\S]*?)\n\}\n\nfunction handleTreeSelection')
    $workspaceTabBody = if ($workspaceTabMatch.Success) { $workspaceTabMatch.Groups['body'].Value } else { '' }
    $tabStateValid = $appContent -match 'queries:\s*\{\s*"candidate-sources": "",\s*"assessment-results": "",\s*"rule-issues": ""\s*\}' -and $appContent -match 'state\.queries\[state\.workspaceTab\] = value' -and $workspaceTabBody -match 'elements\["search-input"\]\.value = state\.queries\[tab\]' -and $workspaceTabBody -notmatch 'renderCandidateList|renderAssessmentResults'
    $assessmentResultsValid = $tabStateValid -and $indexContent -notmatch 'data-view="assessment-results"|assessment-results-search|data-assessment-mode|assessment-results-controls' -and ([regex]::Matches($indexContent, 'id="search-input"').Count -eq 1) -and $indexContent -match 'class="catalog-toolbar"[\s\S]*class="workspace-tabs" role="tablist"' -and $indexContent -match 'role="tab" aria-selected="true" aria-controls="candidate-sources-panel" data-workspace-tab="candidate-sources"' -and $indexContent -match 'role="tab" aria-selected="false" aria-controls="assessment-results-panel" data-workspace-tab="assessment-results"' -and $indexContent -match 'id="candidate-sources-panel" role="tabpanel"[\s\S]*class="catalog-layout"' -and $indexContent -match 'id="assessment-results-panel" role="tabpanel"[\s\S]*class="catalog-layout"' -and $appContent -notmatch 'assessmentQuery|assessmentMode|updateAssessmentFilter|setAssessmentMode' -and $appContent -match 'assessedCandidates:\s*\[\]' -and $appContent -match 'workspaceTab:\s*"candidate-sources"' -and $appContent -match 'state\.excludedCandidateCount = assessedCandidates\.filter\(\(\{ assessment \}\) => !assessment\.hostedApplicable\)\.length' -and $appContent -match 'refreshEffectiveCandidates\(\)' -and $appContent -match 'if \(candidate\.assessment\.hostedApplicable\) return false' -and $appContent -match 'elements\["assessment-results-count"\]\.textContent = formatNumber\(state\.excludedCandidateCount\)' -and $appContent -match 'candidate-category-items"><div class="assessment-results-header"' -and $appContent -notmatch 'assessment-results-list"\]\.innerHTML = `\s*<div class="assessment-results-header"' -and $appContent -match 'state\.workspaceTab === "candidate-sources"' -and $appContent -match 'Search excluded assessment results' -and $appContent -match 'Excluded from candidate catalog' -and $assessmentDetailBody -match 'renderApplicabilityOverride\(candidate\)' -and $assessmentDetailBody -notmatch 'data-rule-action|data-plan-toggle|getDecision\('
    $assessmentResultsValid = $tabStateValid -and $indexContent -match 'data-workspace-tab="candidate-sources"' -and $indexContent -match 'data-workspace-tab="assessment-results"' -and $indexContent -notmatch 'id="assessment-results-count"|id="filter-count"|id="assessment-results-filter-count"|plan-count-control|plan-action-count|eligibility-note' -and $appContent -match 'state\.assessedCandidates\.filter\(\(candidate\) => !candidate\.assessment\.hostedApplicable\)' -and $appContent -notmatch 'elements\["assessment-results-count"\]|elements\["filter-count"\]|elements\["assessment-results-filter-count"\]|elements\["plan-action-count"\]|eligibility-note' -and $appContent -match 'candidate-overrides-root' -and $appContent -match 'renderApplicabilityOverride\(candidate\)' -and $appContent -match 'data-assessment-override-toggle=' -and $appContent -match 'data-assessment-override-remove=' -and $appContent -match 'function syncAssessmentOverrideDisclosures\(' -and $appContent -match 'class="override-rationale"[\s\S]*?<textarea readonly>' -and $appContent -match 'data-override-remove aria-label="Remove Override" title="Remove Override"' -and $stylesContent -match '\.assessment-results-header > span,\s*\.assessment-result-summary\s*\{[^}]*grid-template-columns:\s*84px 116px 156px 110px' -and $stylesContent -match '\.assessment-override-inline\s*\{[^}]*border-left:\s*2px solid var\(--gold\)'
    $assessmentResultsValid = $tabStateValid -and
        $indexContent -notmatch 'data-workspace-tab="conflicts"|id="conflict-list"|id="conflict-detail"' -and
        $appContent -match 'candidate-overrides-root' -and
        $appContent -match 'const category = candidate\.assessment\.hostedCategory' -and
        $appContent -match 'kind: "category"' -and
        $appContent -match 'renderApplicabilityOverride\(candidate\)' -and
        $appContent -match 'candidate-tree-copy"><strong>\$\{escapeHtml\(getEffectiveHostedRuleId\(candidate\)\)\}' -and
        $assessmentDetailBody -match 'detail-identity"[^\n]*getEffectiveHostedRuleId\(candidate\)' -and
        $assessmentDetailBody -match 'Proposed Hosted Rule:[\s\S]*assessment\.proposedHostedRuleId[\s\S]*Generated[\s\S]*assessment\.proposedText' -and
        $appContent -match 'data-assessment-override-toggle=' -and
        $appContent -match 'data-assessment-override-remove=' -and
        $appContent -match 'data-override-remove aria-label="Remove Override" data-workbench-tooltip="Remove override"' -and
        $appContent -match 'data-override-apply aria-label="Apply Override" data-workbench-tooltip="Apply override" disabled>\$\{icon\("git-stash-apply"\)\}' -and
        $appContent -match 'data-override-cancel aria-label="Cancel Override" data-workbench-tooltip="Cancel override">\$\{icon\("close"\)\}' -and
        $appContent -notmatch 'class="override-actions"' -and
        $stylesContent -match '\.override-inline-actions\s*\{[^}]*display:\s*flex;[^}]*gap:\s*4px' -and
        $stylesContent -match '\.factor-line\.penalty\.risk-high \.factor-meter::\-webkit-progress-value\s*\{[^}]*background:\s*var\(--red\)' -and
        $stylesContent -match '\.factor-line\.penalty\.risk-high \.factor-meter::\-moz-progress-bar\s*\{[^}]*background:\s*var\(--red\)' -and
        $stylesContent -match '\.factor-line\.penalty\.risk-moderate \.factor-meter::\-webkit-progress-value\s*\{[^}]*background:\s*var\(--gold\)' -and
        $stylesContent -match '\.factor-line\.penalty\.risk-high \.factor-value\s*\{[^}]*color:\s*var\(--red\)' -and
        $stylesContent -match '\.assessment-override-inline\s*\{[^}]*border-left:\s*2px solid var\(--gold\)'
    $assessmentResultsValid = $tabStateValid -and
        $appContent -match 'function buildAssessmentTreeNodes\(' -and
        $appContent -match 'state\.assessedCandidates\.filter\(\(candidate\) => !candidate\.assessment\.hostedApplicable\)' -and
        $appContent -match 'function renderAssessmentHierarchyRow\(' -and
        $appContent -match 'data-assessment-override-detail=' -and
        $appContent -match 'function openAssessmentOverride\(key\)' -and
        $appContent -match 'data-override-jump=' -and
        $appContent -match '>Contested</button>' -and
        $appContent -match '>Maintainer Included</button>' -and
        $appContent -match 'renderApplicabilityOverride\(candidate\)' -and
        $appContent -notmatch 'assessmentOverrideExpandedKey|kind: "detail"|data-assessment-override-toggle=|data-assessment-override-remove=' -and
        $stylesContent -match '\.status-badge\.excluded\s*\{[^}]*background:\s*#4a252b;[^}]*border-color:\s*#d85d65' -and
        $stylesContent -match '\.detail-header-actions\s*\{[^}]*width:\s*max-content;[^}]*max-width:\s*50%'
    Add-TestResult -Name 'assessment-results-audit' -Passed $assessmentResultsValid -Detail 'Assessment Results retains every original AI exclusion, routes contested state to source-bound Details, and distinguishes original outcome, maintainer inclusion, and catalog status.'

    $assessmentSortingValid = $appContent -match 'assessmentSorts:\s*\{\}' -and $appContent -match 'event\.target\.closest\("\[data-assessment-sort\]"\)' -and $appContent -match 'function renderAssessmentResultsHeader\(sectionKey\)' -and $appContent -match '\["candidate", "Candidate", "Candidate"' -and $appContent -match '\["state", "State", "Source State"' -and $appContent -notmatch '\["outcome", "Outcome", "Outcome"|sort\.field === "outcome"' -and $appContent -match '\["category", "Category", "Category"' -and $appContent -match '\["recommendation", "Recommendation", "Recommendation"' -and $appContent -match '\["override", "Override", "Override"' -and $appContent -match 'if \(sort\.field === "state"\) return candidate\.state' -and $appContent -match 'return getApplicabilityOverride\(candidate\) \? "contested" : "none"' -and $appContent -match 'candidate-lifecycle \$\{escapeHtml\(candidate\.state\)\}' -and $appContent -match 'renderSortButton\(column, sort, \{ "assessment-sort": column\[0\], "assessment-section": sectionKey \}\)' -and $appContent -match 'function getAssessmentSort\(sectionKey\)' -and $appContent -match 'return state\.assessmentSorts\[sectionKey\] \|\| \{ field: "candidate", direction: "ascending" \}' -and $appContent -match 'function updateAssessmentSort\(button\)' -and $appContent -match 'group\.appendChild\(rowsByKey\.get\(candidate\.key\)\)' -and $appContent -match 'group\.appendChild\(panel\)' -and $appContent -match 'function sortAssessmentCandidates\(candidates, sort\)' -and $stylesContent -match '\.candidate-sort-button\s*\{[^}]*display:\s*flex;[^}]*justify-content:\s*center;[^}]*gap:\s*8px' -and $stylesContent -match '\.candidate-sort-button > \.sort-indicator\s*\{[^}]*flex:\s*0 0 16px;[^}]*visibility:\s*hidden' -and $stylesContent -match '\.candidate-sort-button\.active > \.sort-indicator\s*\{[^}]*visibility:\s*visible' -and $stylesContent -match ':is\(\.candidate-list-header, \.assessment-results-header\) > \.candidate-sort-button\s*\{[^}]*justify-content:\s*flex-start'
    $assessmentSortingValid = $appContent -match 'assessmentSorts:\s*\{\}' -and
        $appContent -match 'function renderAssessmentResultsHeader\(sectionKey\)' -and
        $appContent -match '\["candidate", "Candidate", "Candidate"' -and
        $appContent -match '\["state", "State", "Source State"' -and
        $appContent -notmatch '\["category", "Category", "Category"' -and
        $appContent -match '\["recommendation", "Recommendation", "Recommendation"' -and
        $appContent -match '\["override", "Override", "Override"' -and
        $appContent -match 'sortAssessmentCandidates\(members, getAssessmentSort\(sectionKey\)\)' -and
        $appContent -match 'function updateAssessmentSort\(button\)' -and
        $appContent -match 'assessmentHierarchicalView\.refresh\(\)' -and
        $appContent -match 'function sortAssessmentCandidates\(candidates, sort\)' -and
        $stylesContent -match '\.candidate-sort-button\.active > \.sort-indicator\s*\{[^}]*visibility:\s*visible'
    Add-TestResult -Name 'assessment-results-sorting' -Passed $assessmentSortingValid -Detail 'Each Assessment Results category folder independently sorts Candidate, State, Recommendation, and Override without repeating category in every leaf row.'

    $sharedPresentationUtilitiesValid =
        $appContent -match 'function renderCandidateCountBadge\(count, singular, decoration\)' -and
        $appContent -match 'class="status-badge neutral count-badge type-compact"\$\{tooltip\}' -and
        $appContent -match 'renderCandidateCountBadge\(overrideCandidates\.length, "Override", overrideDecoration\)' -and
        $appContent -match 'renderCandidateCountBadge\(candidates\.length, "Candidate", decoration\)' -and
        $appContent -match 'function renderSourceSummaryLabel\(' -and
        $appContent -match 'function formatCountLabel\(count, singular\)' -and
        $appContent -match '\$\{formatNumber\(candidates\.length\)\} Excluded' -and
        $stylesContent -match '\.status-badge\.neutral\s*\{[^}]*color:\s*var\(--muted\);[^}]*background:\s*var\(--surface-quiet\);[^}]*border-color:\s*var\(--line-strong\)' -and
        $stylesContent -match '\.status-badge\.count-badge\s*\{[^}]*color:\s*#ffffff;[^}]*background:\s*#007acc;[^}]*border-color:\s*#007acc' -and
        $stylesContent -match 'html\.theme-hosted-dark :is\(\.status-badge, \.candidate-state, \.candidate-lifecycle, \.decision-badge, \.recommendation-badge, \.catalog-status\)\s*\{[^}]*font-weight:\s*600 !important;[^}]*text-transform:\s*capitalize' -and
        $stylesContent -match '\.catalog-status\.unmapped\s*\{[^}]*color:\s*var\(--muted\);[^}]*background:\s*var\(--surface-quiet\);[^}]*border-color:\s*var\(--line-strong\)' -and
        $stylesContent -match '\.candidate-source-root > summary\s*\{[^}]*color:\s*var\(--ink\)' -and
        $stylesContent -match '\.candidate-source-root > summary > \.source-summary-label > strong\s*\{[^}]*text-transform:\s*uppercase' -and
        $stylesContent -match '\.panel-heading,\s*\.candidate-list-header,\s*\.assessment-results-header,\s*\.plan-table th,\s*\.payload-column-heading\s*\{[^}]*background:\s*var\(--surface\);[^}]*border-color:\s*var\(--line\)' -and
        $appContent -match 'window\.addEventListener\("resize", scheduleTruncationTooltips\)' -and
        $appContent -match 'function scheduleTruncationTooltips\(\)' -and
        $appContent -match 'function syncTruncationTooltips\(\)' -and
        $appContent -match 'getComputedStyle\(node\)\.textOverflow !== "ellipsis"' -and
        $appContent -match 'node\.setAttribute\("data-truncation-tooltip", ""\)' -and
        $appContent -notmatch 'MutationObserver'
    $sharedPresentationUtilitiesValid =
        $appContent -match 'function renderCandidateCountBadge\(count, singular, decoration\)' -and
        $appContent -match 'function renderSourceSummaryLabel\(' -and
        $appContent -match 'function formatCountLabel\(count, singular\)' -and
        $appContent -match '\$\{formatNumber\(candidates\.length\)\} Excluded' -and
        $stylesContent -match '\.status-badge\.count-badge\s*\{[^}]*background:\s*#007acc' -and
        $stylesContent -match '\.hierarchical-parent-row\s*\{[^}]*background:\s*var\(--surface\)' -and
        $stylesContent -match '\.candidate-source-row > \.source-summary-label > strong\s*\{[^}]*text-transform:\s*uppercase' -and
        $stylesContent -match '\.panel-heading,\s*\.candidate-list-header,\s*\.assessment-results-header,\s*\.plan-table th,\s*\.payload-column-heading\s*\{[^}]*background:\s*var\(--surface\)' -and
        $appContent -match 'function syncTruncationTooltips\(\)' -and
        $appContent -notmatch 'MutationObserver'
    Add-TestResult -Name 'shared-presentation-utilities' -Passed $sharedPresentationUtilitiesValid -Detail 'Sortable list headers, neutral count pills, dark data headers, and truncation tooltips are shared presentation behaviors rather than view-specific exceptions.'

    $assessmentPaneValid = $indexContent -match 'class="candidate-pane-switch assessment-pane-switch" role="tablist" aria-label="Assessment workspace"' -and $indexContent -match 'data-assessment-pane="assessments"' -and $indexContent -match 'data-assessment-pane="details"' -and $indexContent -match 'id="assessment-results-list-panel" role="tabpanel"' -and $indexContent -match 'id="assessment-results-detail" role="tabpanel"[^>]*hidden' -and $stylesContent -match '#assessment-results-panel \.catalog-layout\s*\{[^}]*grid-template-columns:\s*minmax\(0, 1fr\)' -and $stylesContent -match '#assessment-results-panel\.workspace-tab-panel\.active\s*\{[^}]*display:\s*grid;[^}]*grid-template-rows:\s*auto minmax\(0, 1fr\)' -and $stylesContent -match '#assessment-results-detail\s*\{[^}]*display:\s*grid;[^}]*grid-template-rows:\s*auto minmax\(0, 1fr\);[^}]*overflow:\s*hidden' -and $stylesContent -match ':is\(#candidate-sources-panel \.assessment-panel, #assessment-results-detail\) > \.assessment-content\s*\{[^}]*overflow-y:\s*auto' -and $appContent -match 'assessmentPane:\s*"assessments"' -and $appContent -match 'state\.assessmentPane = "assessments";\s*renderAll\(\);[\s\S]*?showAssessmentPane\("assessments"\)' -and $appContent -match 'selectAssessmentResult\(row\.dataset\.assessmentKey\);\s*showAssessmentPane\("details"\)' -and $appContent -match 'selectAssessmentResult, \(\) => showAssessmentPane\("details"\)' -and $appContent -match 'function syncAssessmentResultRows\(' -and $appContent -match 'row\.dataset\.assessmentKey === state\.assessmentActiveKey' -and $appContent -match 'function showAssessmentPane\(pane\)' -and $appContent -match 'const activePane = pane === "details" \? "details" : "assessments"'
    Add-TestResult -Name 'assessment-pane-navigation' -Passed $assessmentPaneValid -Detail 'Assessment Results always exposes full-width Assessments and Details tabs, initializes without a selection, opens Details on row activation, and synchronizes the selected-row highlight from one state owner.'

    $overrideContractValid = $appContent -match 'SESSION_SCHEMA_VERSION = 7' -and $appContent -match 'applicabilityOverrides:\s*\{\}' -and $appContent -match 'function getApplicabilityOverride' -and $appContent -match 'sourceContentSha256 !== candidate\.hash' -and $appContent -match 'originalHostedApplicable === false' -and $appContent -match 'effectiveHostedApplicable === true' -and $appContent -match 'function getEffectiveHostedApplicability' -and $appContent -match 'Maintainer Override:' -and $appContent -match 'data-override-open' -and $appContent -match 'data-override-apply' -and $appContent -match 'data-override-remove' -and $appContent -match 'recordedBy:\s*\{ type: "github-cli", login: identity\.login \}' -and $appContent -match 'applicabilityOverride: getApplicabilityOverride\(candidate\)' -and $appContent -match 'draft\.applicabilityOverrides' -and $appContent -match 'The AI assessment is read-only' -and $workbenchGitHubContextContent -match 'Invoke-HostedGitHubApi -Endpoint user -Jq ''\.login''' -and $workbenchGitHubContextContent -match 'Join-Path \$RepositoryRoot ''\.github/CODEOWNERS''' -and $launcherContent -match 'maintainerIdentity = \$maintainerIdentity'
    $overrideContractValid = $overrideContractValid -and $appContent -match 'function updateOverrideLifecycle\(' -and $appContent -match 'repairOverridePlanMembership\(\)' -and $appContent -match 'updateOverrideLifecycle\(candidate, override, \{ \.\.\.defaultDecision\(candidate\), \.\.\.createPlanMembership\("override"\) \}\)' -and $appContent -match 'updateOverrideLifecycle\(candidate, null, null\)'
    $overrideContractValid = $overrideContractValid -and $appContent -match 'class="button warning-action clickable"[^>]*data-override-open' -and $appContent -match '\$\{icon\("chat-sparkle-error"\)\}Contest Assessment' -and $stylesContent -match '--warning-action-background:\s*#352a05' -and $stylesContent -match '--warning-action-background-hover:\s*#453b19' -and $stylesContent -match '--warning-action-border:\s*#b89500' -and $stylesContent -match '--warning-action-foreground:\s*#ffffff' -and $stylesContent -match '\.button\.warning-action\s*\{[^}]*color:\s*var\(--warning-action-foreground\);[^}]*background:\s*var\(--warning-action-background\);[^}]*border-color:\s*var\(--warning-action-border\)' -and $stylesContent -match '\.button\.warning-action:hover\s*\{[^}]*color:\s*var\(--warning-action-foreground\);[^}]*background:\s*var\(--warning-action-background-hover\);[^}]*border-color:\s*var\(--warning-action-border\)'
    Add-TestResult -Name 'maintainer-applicability-override' -Passed $overrideContractValid -Detail 'Authenticated Hosted CODEOWNERS can atomically move an exclusion into Overrides and the plan, while removal returns it to active exclusions without mutating the AI assessment.'

    $assessmentOwnershipValid = $appContent -match 'assessment:\s*candidate\.assessment \|\| getPriorAssessment\(candidate\)' -and $appContent -match 'function saveDecision\(candidate, decision\)[\s\S]*?const \{ assessment, \.\.\.maintainerDecision \} = decision' -and $appContent -match 'state\.session\.decisions\[candidate\.key\] = \{\s*\.\.\.maintainerDecision,'
    Add-TestResult -Name 'current-bundle-assessment-ownership' -Passed $assessmentOwnershipValid -Detail 'Persisted maintainer decisions cannot override or re-export the assessment supplied by the current candidate bundle.'

    $darkThemeValid = $indexContent -match '<html lang="en" class="theme-hosted-dark">' -and $indexContent -match '<meta name="color-scheme" content="dark">' -and $indexContent -match '<link rel="icon" href="favicon\.svg" type="image/svg\+xml">' -and $indexContent -notmatch 'fonts\.googleapis|fonts\.gstatic|IBM Plex' -and $faviconContent -match 'viewBox="0 0 16 16"' -and $faviconContent -match 'fill="#ffff00"' -and $faviconContent -match 'stroke="#ffff00"' -and $faviconContent -match 'stroke-width="0\.6"' -and $stylesContent -match 'html\.theme-hosted-dark\s*\{[^}]*--paper: #121314' -and $stylesContent -notmatch '(?m)^:root\s*\{' -and $stylesContent -match 'color-scheme: dark' -and $stylesContent -match '--surface: #191a1b' -and $stylesContent -match '--context-header: #0f1c2d' -and $stylesContent -match '--line: #2a2b2c' -and $stylesContent -match '--line-strong: #333536' -and $stylesContent -match '--accent: #3994bc' -and $stylesContent -match 'html\.theme-hosted-dark body,\s*html\.theme-hosted-dark body \*\s*\{[^}]*font-family:\s*"Segoe UI", Tahoma, sans-serif !important' -and $stylesContent -match 'font-family:\s*Consolas, "Courier New", monospace !important' -and $stylesContent -match '\.brand-block svg\s*\{[^}]*color:\s*#ffff00;[^}]*stroke:\s*#ffff00;[^}]*stroke-width:\s*0\.6px'
    Add-TestResult -Name 'dark-theme-contract' -Passed $darkThemeValid -Detail 'The product-owned Hosted dark theme uses its current IDE shell palette and typography while retaining yellow braces as its product accent.'

    $globalTypographyValid = $stylesContent -match '--font-size-default:\s*14px' -and $stylesContent -match '--line-height-default:\s*20px' -and $stylesContent -match '--font-size-ui:\s*13px' -and $stylesContent -match '--line-height-ui:\s*18px' -and $stylesContent -match '--font-size-compact:\s*12px' -and $stylesContent -match '--line-height-compact:\s*16px' -and $stylesContent -match 'html\.theme-hosted-dark \.type-ui,\s*html\.theme-hosted-dark \.type-ui \*\s*\{[^}]*font-size:\s*var\(--font-size-ui\) !important;[^}]*line-height:\s*var\(--line-height-ui\) !important' -and $stylesContent -match 'html\.theme-hosted-dark \.type-editor,\s*html\.theme-hosted-dark \.type-editor \*\s*\{[^}]*font-size:\s*var\(--font-size-default\) !important;[^}]*line-height:\s*var\(--line-height-default\) !important' -and $stylesContent -match 'html\.theme-hosted-dark \.type-compact,\s*html\.theme-hosted-dark \.type-compact \*\s*\{[^}]*font-size:\s*var\(--font-size-compact\) !important;[^}]*line-height:\s*var\(--line-height-compact\) !important' -and $indexContent -match 'candidate-list type-ui' -and $indexContent -match 'plan-table type-ui' -and $indexContent -match 'preview-summary type-ui' -and $indexContent -match 'preview-code type-editor' -and $indexContent -match 'ide-statusbar type-compact'
    $globalTypographyValid = $globalTypographyValid -and $stylesContent -match '--font-size-detail-title:\s*20px' -and $stylesContent -match '--line-height-detail-title:\s*24px' -and $stylesContent -match 'html\.theme-hosted-dark body \.detail-rule-title\s*\{[^}]*font-size:\s*var\(--font-size-detail-title\) !important;[^}]*font-weight:\s*600 !important;[^}]*line-height:\s*var\(--line-height-detail-title\) !important' -and $stylesContent -match 'html\.theme-hosted-dark body :is\(\.detail-identity, \.detail-identity > span, \.section-label, \.control-subtitle\)\s*\{[^}]*font-size:\s*var\(--font-size-default\) !important;[^}]*font-weight:\s*600 !important;[^}]*line-height:\s*var\(--line-height-default\) !important'
    $globalTypographyValid = $stylesContent -match '--font-size-default:\s*14px' -and
        $stylesContent -match '--line-height-default:\s*20px' -and
        $stylesContent -match '--font-size-compact:\s*12px' -and
        $stylesContent -match '--line-height-compact:\s*16px' -and
        $indexContent -match 'candidate-list scroll-surface type-ui' -and
        $indexContent -match 'preview-summary scroll-surface type-ui' -and
        $indexContent -match 'preview-code scroll-surface type-editor' -and
        $stylesContent -match 'html\.theme-hosted-dark body \.status-surface-tooltip\s*\{[^}]*font-size:\s*var\(--font-size-default\) !important;[^}]*line-height:\s*var\(--line-height-default\) !important'
    Add-TestResult -Name 'global-typography-contract' -Passed $globalTypographyValid -Detail 'The Hosted theme enforces one 14/20 regular default, one 12/16 regular compact class, and one 14/20 semibold emphasis rule across supported viewports.'

    $componentConsistencyValid = $stylesContent -match '#candidate-panel > \.panel-heading\s*\{[^}]*padding-block:\s*8px' -and $stylesContent -match 'html\.theme-hosted-dark :is\(\.status-badge, \.candidate-state, \.candidate-lifecycle, \.decision-badge, \.recommendation-badge, \.catalog-status\)\s*\{[^}]*font-size:\s*var\(--font-size-compact\) !important;[^}]*font-weight:\s*600 !important;[^}]*line-height:\s*var\(--line-height-compact\) !important' -and $stylesContent -match 'html\.theme-hosted-dark body \.plan-table \.candidate-link\s*\{[^}]*font-size:\s*var\(--font-size-ui\) !important;[^}]*font-weight:\s*600 !important;[^}]*line-height:\s*var\(--line-height-ui\) !important' -and $stylesContent -match '\.diff-file-heading\s*\{[^}]*color:\s*#e6edf3;[^}]*border-bottom:\s*1px solid var\(--line\)'
    $componentConsistencyValid = $stylesContent -match '#candidate-panel > \.panel-heading\s*\{[^}]*padding-block:\s*8px' -and $stylesContent -match 'html\.theme-hosted-dark :is\(\.status-badge, \.candidate-state, \.candidate-lifecycle, \.decision-badge, \.recommendation-badge, \.catalog-status\)\s*\{[^}]*font-size:\s*var\(--font-size-compact\) !important;[^}]*font-weight:\s*600 !important;[^}]*line-height:\s*var\(--line-height-compact\) !important' -and $stylesContent -match 'html\.theme-hosted-dark body :is\(\.candidate-tree-copy strong, \.plan-table \.candidate-link\)\s*\{[^}]*color:\s*var\(--accent-bright\) !important;[^}]*font-size:\s*var\(--font-size-default\) !important;[^}]*font-weight:\s*600 !important;[^}]*line-height:\s*var\(--line-height-default\) !important' -and $stylesContent -match 'html\.theme-hosted-dark body :is\(\.candidate-tree-copy small, \.plan-candidate-title\)\s*\{[^}]*color:\s*var\(--ink\) !important;[^}]*font-size:\s*var\(--font-size-default\) !important;[^}]*font-weight:\s*400 !important;[^}]*line-height:\s*var\(--line-height-default\) !important' -and $stylesContent -match '\.diff-file-heading\s*\{[^}]*color:\s*#e6edf3;[^}]*border-bottom:\s*1px solid var\(--line\)'
    $componentConsistencyValid = $componentConsistencyValid -and ([regex]::Matches($appContent, 'class="source-line detail-identity"').Count -eq 3) -and ([regex]::Matches($appContent, 'class="detail-rule-title"').Count -eq 3) -and $stylesContent -match '\.assessment-title > div\s*\{[^}]*min-width:\s*0' -and $stylesContent -match '\.detail-identity\s*\{[^}]*color:\s*var\(--accent-bright\);[^}]*text-transform:\s*uppercase' -and $stylesContent -match '\.section-label\s*\{[^}]*text-transform:\s*uppercase'
    Add-TestResult -Name 'component-typography-consistency' -Passed $componentConsistencyValid -Detail 'Candidate Sources, Assessment Results, and Promotion Plan share one 14/20 blue-ID and neutral-title hierarchy; semantic pills remain semibold inside compact surfaces, and Preview section labels retain one heading treatment.'

    $scrollbarThemeValid = $stylesContent -match '@property --workbench-scrollbar-thumb' -and $stylesContent -match '\.scroll-surface\s*\{[^}]*scrollbar-color:\s*var\(--workbench-scrollbar-thumb\) var\(--scrollbar-track\);[^}]*transition:\s*--workbench-scrollbar-thumb 360ms ease-out' -and $stylesContent -match '\.scroll-surface:is\(:hover, :focus-within\)\s*\{[^}]*transition-duration:\s*180ms' -and $stylesContent -match '\.scroll-surface::\-webkit-scrollbar-thumb\s*\{[^}]*border-radius:\s*0' -and $stylesContent -match '\.scroll-surface::\-webkit-scrollbar-button' -and $stylesContent -match '--scrollbar-track: transparent' -and $indexContent -match 'candidate-list scroll-surface type-ui'
    Add-TestResult -Name 'scrollbar-theme-contract' -Passed $scrollbarThemeValid -Detail 'Every scroll surface uses an idle-hidden, flat, arrowless thumb with keyboard visibility and asymmetric reveal and hide timing.'

    $ideShellValid = $indexContent -match 'data-lucide="braces"' -and $indexContent -match 'data-lucide="git-fork"' -and $indexContent -match 'class="stage-link active clickable"[^>]*title="Eligible candidates"' -and $indexContent -match '<h2 id="candidate-heading">Candidate Sources:</h2>' -and $indexContent -match '<h2 id="assessment-results-heading">Assessment Results:</h2>' -and $indexContent -match '<h2>Promotion Plan:</h2>' -and $indexContent -match '<h2>Promotion Preview:</h2>' -and $indexContent -notmatch 'Maintainer review|Read-only assessment audit|Selected changes|preview-editor-icon' -and $stylesContent -match '@media \(min-width: 768px\)[\s\S]*?grid-template-columns:\s*48px minmax\(0, 1fr\);[\s\S]*?grid-template-rows:\s*35px minmax\(0, 1fr\) 22px' -and $stylesContent -match '\.topbar\s*\{[^}]*grid-template-columns:\s*auto 1fr' -and $stylesContent -match '\.brand-block\s*\{[^}]*grid-column:\s*1;[^}]*margin-left:\s*8px' -and $stylesContent -match '\.topbar-actions\s*\{[^}]*grid-column:\s*2' -and $stylesContent -match '#candidate-panel > \.panel-heading,[\s\S]*?#preview-view > \.page-heading\s*\{[^}]*min-height:\s*48px' -and $stylesContent -match '#candidate-panel > \.panel-heading h2,[\s\S]*?#preview-view > \.page-heading h2\s*\{[^}]*font-size:\s*16px !important;[^}]*font-weight:\s*600 !important;[^}]*line-height:\s*22px !important;[^}]*text-transform:\s*uppercase' -and $stylesContent -match '#plan-view > \.page-heading,[\s\S]*?#preview-view > \.page-heading\s*\{[^}]*margin-bottom:\s*6px' -and $stylesContent -match '\.stage-link\.active::before\s*\{[^}]*background:\s*var\(--ink\)' -and $stylesContent -match '\.status-left \.status-item:first-child svg\s*\{[^}]*width:\s*12px;[^}]*padding:\s*2px;[^}]*overflow:\s*visible' -and $stylesContent -notmatch '\.status-right \.status-item:nth-child' -and $stylesContent -match '\.catalog-toolbar\s*\{[^}]*min-height:\s*34px;[^}]*background:\s*var\(--paper\);[^}]*border:\s*0' -and $stylesContent -match '\.search-field\s*\{[^}]*height:\s*26px;[^}]*border-radius:\s*2px' -and $stylesContent -match '\.search-field:focus-within\s*\{[^}]*border-color:\s*var\(--line\)' -and $stylesContent -match '\.workspace-tab\.active::before\s*\{[^}]*background:\s*var\(--accent\)'
    $codiconShellValid = $indexContent -match 'class="brand-icon codicon"[^>]*>[\s\S]*?icons/codicons/sprite\.svg#codicon-json' -and $indexContent -match 'icons/codicons/sprite\.svg#codicon-git-branch-compact' -and $indexContent -match 'class="stage-link active clickable"[^>]*title="Eligible candidates"' -and $indexContent -match '<h2 id="candidate-heading">Candidate Sources:</h2>' -and $indexContent -match '<h2 id="assessment-results-heading">Assessment Results:</h2>' -and $indexContent -match '<h2>Promotion Plan:</h2>' -and $indexContent -match '<h2>Promotion Preview:</h2>' -and $stylesContent -match '@media \(min-width: 768px\)[\s\S]*?grid-template-columns:\s*48px minmax\(0, 1fr\);[\s\S]*?grid-template-rows:\s*35px minmax\(0, 1fr\) 22px' -and $stylesContent -match '\.stage-link\.active::before\s*\{[^}]*background:\s*var\(--ink\)' -and $stylesContent -match '\.status-left \.status-item:first-child svg\s*\{[^}]*width:\s*13px;[^}]*height:\s*13px' -and $stylesContent -match '\.workspace-tab\s*\{[^}]*text-transform:\s*uppercase' -and $stylesContent -match '\.candidate-pane-tab\s*\{[^}]*text-transform:\s*uppercase'
    $codiconShellValid = $indexContent -match 'class="brand-icon codicon"' -and
        $indexContent -match 'class="stage-link active clickable"[^>]*data-workbench-tooltip="Show eligible candidates"' -and
        $indexContent -match '<h2 id="candidate-heading">Candidate Sources:</h2>' -and
        $stylesContent -match '@media \(min-width: 768px\)[\s\S]*?grid-template-columns:\s*48px minmax\(0, 1fr\);[\s\S]*?grid-template-rows:\s*var\(--topbar-height\) minmax\(0, 1fr\) var\(--status-bar-height\)'
    Add-TestResult -Name 'ide-shell-contract' -Passed ($ideShellValid -or $codiconShellValid) -Detail 'The source-backed IDE shell uses compact title, activity, editor-tab, search, and status surfaces with icon-first controls and exact approved dimensions.'

    $ideShellValid = $ideShellValid -and $indexContent -notmatch 'data-lucide="list-tree"|data-lucide="panel-right"|data-lucide="clipboard-list"' -and $stylesContent -match '\.catalog-toolbar\s*\{[^}]*min-height:\s*40px;[^}]*padding:\s*4px 0' -and $stylesContent -match '\.search-field\s*\{[^}]*height:\s*32px;[^}]*min-height:\s*32px' -and $stylesContent -match '\.workspace-tabs\s*\{[^}]*background:\s*var\(--paper\);[^}]*border:\s*0;[^}]*border-bottom:\s*1px solid var\(--line\)' -and $stylesContent -match '\.workspace-tab\s*\{[^}]*margin-right:\s*1px;[^}]*background:\s*var\(--surface\);[^}]*border:\s*1px solid var\(--line\);[^}]*border-bottom:\s*0' -and $stylesContent -match '\.workspace-tab\.active::before\s*\{[^}]*inset:\s*auto 0 0' -and $stylesContent -match '\.candidate-pane-switch\s*\{[^}]*background:\s*var\(--paper\)' -and $stylesContent -match '\.candidate-pane-tab\s*\{[^}]*background:\s*var\(--surface\);[^}]*text-transform:\s*uppercase' -and $stylesContent -match '\.candidate-pane-tab\.active\s*\{[^}]*background:\s*var\(--paper\);[^}]*box-shadow:\s*inset 0 -1px var\(--accent\)' -and $stylesContent -match '@media \(min-width: 1400px\)[\s\S]*?grid-template-columns:\s*18px minmax\(280px, 640px\) auto;[\s\S]*?justify-content:\s*start' -and $stylesContent -match '@media \(min-width: 1180px\)[\s\S]*?\.assessment-results-header,[\s\S]*?grid-template-columns:\s*minmax\(280px, 640px\) auto'

    $previewEditorValid = $indexContent -match '<h2>Promotion Preview:</h2>' -and $indexContent -notmatch 'preview-sidebar-title|preview-review-scope' -and $indexContent -match 'id="preview-review-toolbar"[\s\S]*?class="preview-layout"' -and $indexContent -match 'id="preview-tree-resizer"[^>]*role="slider"[^>]*aria-orientation="vertical"' -and $indexContent -match 'class="button review clickable"[^>]*id="preview-review-toggle"[^>]*>Review Changes</button>' -and $indexContent -match 'id="preview-review-popover"[^>]*hidden' -and $appContent -match 'function renderPreviewArtifactGroup\(' -and $appContent -match 'data-preview-artifact-scope=' -and $appContent -match 'previewExpandedScopes' -and $stylesContent -match '#preview-view \.preview-layout\s*\{[^}]*--preview-tree-width:\s*380px;[^}]*grid-template-columns:\s*var\(--preview-tree-width\) minmax\(0, 1fr\)' -and $stylesContent -match '#preview-view \.preview-summary\s*\{[^}]*height:\s*100%;[^}]*border-right:\s*1px solid #30363d' -and $stylesContent -match '\.preview-review-toolbar\s*\{[^}]*position:\s*relative' -and $stylesContent -match '\.preview-file-heading-wrapper\s*\{[^}]*position:\s*sticky;[^}]*top:\s*-2px' -and $stylesContent -match '\.preview-review-popover\s*\{[^}]*position:\s*absolute'
    Add-TestResult -Name 'preview-editor-layout' -Passed $previewEditorValid -Detail 'Preview separates its review toolbar, resizable artifact tree, contained diff scroller, sticky file-header wrappers, and Review Changes approval popover.'

    $previewArtifactTreeValid = $appContent -match 'function renderPreviewFileTree\(\)[\s\S]*?let tree = elements\["preview-summary"\]\.querySelector\("\.preview-artifact-tree"\)[\s\S]*?tree\.innerHTML = groups;[\s\S]*?applyPreviewFileFilter' -and
        $appContent -match 'function renderPreviewIconBuffer\(' -and
        $appContent -match 'if \(!files\.length\) return "";' -and
        $appContent -match 'renderPreviewIconBuffer\("chevron-right", "chevron-down", expanded, "preview-chevron-buffer"\)' -and
        $appContent -match 'renderPreviewIconBuffer\("file-directory-fill", "file-directory-open-fill", expanded, "preview-folder-buffer"\)' -and
        $appContent -match 'function applyPreviewFileFilter\(' -and
        $appContent -match 'requestAnimationFrame\(\(\) => \{[\s\S]*?buffer\.dataset\.state = expanded \? "open" : "closed";[\s\S]*?\.hidden = !expanded;' -and
        $stylesContent -match '\.preview-icon-buffer\s*\{[^}]*position:\s*relative;[^}]*width:\s*16px;[^}]*height:\s*16px' -and
        $stylesContent -match '\.preview-icon-buffer > \.octicon\s*\{[^}]*position:\s*absolute;[^}]*opacity:\s*0;[^}]*will-change:\s*opacity' -and
        $stylesContent -match '\.preview-icon-buffer\[data-state="closed"\] > \.buffer-closed,[\s\S]*?opacity:\s*1'
    Add-TestResult -Name 'preview-artifact-tree-stability' -Passed $previewArtifactTreeValid -Detail 'Preview omits empty artifact folders, preserves the search control while refreshing the nav, and swaps prepainted folder-state icons without replacing tree nodes.'

    $containedViewsValid = $stylesContent -match '@media \(min-width: 901px\)' -and $stylesContent -match 'html,\s*body\s*\{[^}]*height:\s*100%;[^}]*overflow:\s*hidden' -and $stylesContent -match '\.app-shell\s*\{[^}]*position:\s*fixed;[^}]*inset:\s*0;[^}]*height:\s*100vh;[^}]*overflow:\s*hidden' -and $stylesContent -match '\.workspace\s*\{[^}]*min-height:\s*0;[^}]*overflow:\s*hidden' -and $stylesContent -match '#catalog-view\.view\.active\s*\{[^}]*grid-template-rows:\s*auto auto auto minmax\(0, 1fr\)' -and $stylesContent -match '#candidate-sources-panel \.candidate-list,[\s\S]*?#assessment-results-panel \.candidate-list\s*\{[^}]*max-height:\s*none;[^}]*overflow-y:\s*auto' -and $stylesContent -match ':is\(#candidate-sources-panel \.assessment-panel, #assessment-results-detail\) > \.assessment-content\s*\{[^}]*overflow-y:\s*auto' -and $stylesContent -match '#preview-view\.view\.active\s*\{[^}]*grid-template-rows:\s*auto 60px minmax\(0, 1fr\)' -and $stylesContent -match '#plan-view \.plan-table-wrap,[\s\S]*?#preview-view \.preview-code\s*\{[^}]*overflow:\s*auto' -and $stylesContent -match '#plan-view \.plan-table th\s*\{[^}]*position:\s*sticky'
    Add-TestResult -Name 'contained-view-scrolling' -Passed $containedViewsValid -Detail 'Desktop stages keep navigation, headers, tabs, Draft Summary, and Plan Projection static while their owned tree, form, table, and review surfaces scroll independently.'

    $impactFactorsValid = $appContent -notmatch 'AI Evaluation:|AI Adjudication Rationale:' -and $appContent -match 'Assessment Details:' -and $appContent -match 'AI-adjudicated evidence' -and $appContent -match 'Recommend ' -and $appContent -match '<span>Token cost</span>' -and $appContent -notmatch 'Guarded token cost' -and $appContent -match 'Rule Value:' -and $appContent -match 'Review Risk:' -and $appContent -match 'Harm caused when this defect is missed' -and $appContent -match 'Chance of producing unsupported findings' -and $appContent -notmatch '<input type="range"' -and $appContent -notmatch 'data-decision-field="selectionRationale"' -and $stylesContent -match '\.factor-group\.value' -and $stylesContent -match '\.factor-group\.penalty' -and $stylesContent -match '\.factor-meter'
    Add-TestResult -Name 'impact-factor-guidance' -Passed $impactFactorsValid -Detail 'Pre-evaluated AI impact, cost, recommendation, factor evidence, and rationale are visible and read-only.'

    $detailLayoutValid = $stylesContent -match '#catalog-view\s*\{[^}]*max-width:\s*none' -and $stylesContent -match '#candidate-sources-panel \.catalog-layout\s*\{[^}]*grid-template-columns:\s*minmax\(0, 1fr\)' -and $stylesContent -match '#candidate-sources-panel \.assessment-panel\s*\{[^}]*min-width:\s*0' -and $indexContent -match 'class="candidate-pane-switch" role="tablist" aria-label="Candidate workspace"' -and $indexContent -match 'data-candidate-pane="candidates"' -and $indexContent -match 'data-candidate-pane="details" disabled' -and $appContent -match 'function showCandidatePane\(pane\)' -and $appContent -match 'elements\["candidate-panel"\]\.hidden = detailsActive' -and $appContent -match 'elements\["assessment-panel"\]\.hidden = !detailsActive' -and $stylesContent -match '\.candidate-pane-tab\.active'
    $sharedPresentationValid = $stylesContent -match 'html\.theme-hosted-dark body,\s*html\.theme-hosted-dark body \*\s*\{[^}]*font-family:\s*var\(--font-family-ui\) !important' -and $stylesContent -match '\.empty-state svg\s*\{[^}]*color:\s*var\(--info-foreground\)' -and $stylesContent -match '\.subcontext-container\s*\{[^}]*padding:\s*12px;[^}]*background:\s*var\(--blue-soft\);[^}]*border-left:\s*3px solid var\(--blue\)' -and $stylesContent -match '\.subcontext-container > p,\s*p\.subcontext-container\s*\{[^}]*color:\s*#c6d4ff;[^}]*font-size:\s*0\.8rem' -and $appContent -match 'className: "assessment-explanation"' -and $appContent -match 'class="current-hosted-rule"' -and $appContent -match 'class="evidence-box scroll-surface"'
    $actionControlsValid = $appContent -match 'DECISION_RATIONALE_MAX_LENGTH = 500' -and $appContent -match 'class="rule-actions-content"' -and $appContent -notmatch 'rule-actions-content subcontext-container|rule-action-header' -and $appContent -match 'Rule Actions: <strong class="rule-reference">\$\{escapeHtml\(displayId\)\}</strong>' -and $appContent -match '<span class="control-subtitle">Rule Action:</span>\s*<div class="control-group action-plan-group">[\s\S]*?<fieldset class="action-options">' -and $appContent -notmatch 'data-plan-toggle|class="plan-toggle'
    $actionControlsValid = $actionControlsValid -and $appContent -match '<div class="rationale-heading"><span class="control-subtitle" id="decision-rationale-label">Decision Rationale:</span><button class="titlebar-icon clickable rationale-save"[^>]*data-rationale-save[^>]*aria-label=' -and $appContent -match '<label><textarea[^>]*maxlength="\$\{DECISION_RATIONALE_MAX_LENGTH\}"[^>]*aria-labelledby="decision-rationale-label"[^>]*aria-describedby="decision-rationale-limit"'
    $actionControlsValid = $actionControlsValid -and $appContent -match 'rationale-limit.*DECISION_RATIONALE_MAX_LENGTH' -and $appContent -match 'decision\.rationale\.length > DECISION_RATIONALE_MAX_LENGTH' -and $stylesContent -match '\.field-stack textarea\s*\{[^}]*height:\s*84px;[^}]*max-height:\s*84px;[^}]*resize:\s*none;[^}]*overflow-y:\s*auto' -and $stylesContent -match '\.rationale-heading\s*\{[^}]*display:\s*flex;[^}]*align-items:\s*center;[^}]*justify-content:\s*flex-end' -and $stylesContent -match '\.rationale-heading \.rationale-save svg\s*\{[^}]*transform:\s*translateY\(2px\)' -and $stylesContent.Contains('.titlebar-icon:is(:disabled, [aria-disabled="true"], .disabled)') -and $stylesContent -notmatch '\.rationale-actions' -and $stylesContent -match '\.assessment-title-statuses\s*\{[^}]*width:\s*270px;[^}]*flex:\s*0 0 270px;[^}]*justify-content:\s*flex-end'
    $assessmentLegendValid = $appContent -notmatch 'impact / 100 tokens' -and $appContent -match 'data-scoring-legend-open' -and $appContent -match '<dialog class="modal-dialog"' -and $appContent -match 'Score Scale:</span><span>Scores run from 0 \(none\) through 5 \(very high\)' -and $appContent -match 'Existing Coverage:</span><span>0 means no current Hosted coverage; 5 means active Hosted rules already cover the behavior completely' -and $appContent -match 'direction-badge positive">Adds to Impact' -and $appContent -match 'direction-badge negative">Reduces Impact' -and $appContent -match 'risk-\$\{value <= 2 \? "low" : value === 3 \? "moderate" : "high"\}' -and $stylesContent -match '\.factor-line\.penalty\.risk-low \.factor-value\s*\{[^}]*color:\s*var\(--success\)' -and $stylesContent -match '\.scoring-legend-item\s*\{[^}]*grid-template-columns:\s*minmax\(0, 1fr\)'
    $detailPresentationValid = $detailLayoutValid -and $sharedPresentationValid -and $actionControlsValid -and $assessmentLegendValid -and $appContent -match 'candidate-state \$\{escapeHtml\(candidate\.state\)\}">\$\{escapeHtml\(capitalize\(candidate\.state\)\)\}' -and $appContent -match 'return value === "no-change" \? "No Change"' -and $stylesContent -match '\.decision-badge\.no-change,[\s\S]*\.recommendation-badge\.no-change\s*\{[^}]*border-color:\s*rgba\(142, 160, 208, 0\.72\)'
    $detailLayoutValid = $stylesContent -match '#catalog-view\s*\{[^}]*max-width:\s*none' -and $stylesContent -match '#candidate-sources-panel \.catalog-layout\s*\{[^}]*grid-template-columns:\s*minmax\(0, 1fr\)' -and $stylesContent -match '\.candidate-pane-switch\s*\{[^}]*height:\s*34px;[^}]*background:\s*var\(--paper\);[^}]*border-bottom:\s*1px solid var\(--line\)' -and $stylesContent -match '\.candidate-pane-tab\s*\{[^}]*height:\s*34px;[^}]*background:\s*var\(--surface\);[^}]*border-radius:\s*0;[^}]*text-transform:\s*uppercase' -and $stylesContent -match '\.candidate-pane-tab\.active\s*\{[^}]*background:\s*var\(--paper\);[^}]*box-shadow:\s*inset 0 -1px var\(--accent\)' -and $indexContent -match 'data-candidate-pane="details"' -and $indexContent -notmatch 'data-candidate-pane="details" disabled' -and $appContent -match 'function showCandidatePane\(pane\)' -and $appContent -match 'const activePane = pane === "details" \? "details" : "candidates"' -and $appContent -match 'if \(!candidate\) \{[\s\S]*?<h2>Select a Candidate</h2>'
    $detailPresentationValid = $detailLayoutValid -and $sharedPresentationValid -and $actionControlsValid -and $assessmentLegendValid -and $appContent -match 'candidate-state \$\{escapeHtml\(candidate\.state\)\}' -and $appContent -match 'return value === "no-change" \? "No Change"'
    $detailPresentationValid = $detailPresentationValid -and $appContent -match 'if \(!candidate\) \{[\s\S]*?icon\("tasklist"\)[\s\S]*?<h2>Select a Candidate</h2>[\s\S]*?refreshPresentation\(\);\s*return;' -and $stylesContent -match '--info-foreground:\s*#3a94bc' -and $stylesContent -match '--warning-foreground:\s*#e5ba7d' -and $stylesContent -match '\.empty-state svg\s*\{[^}]*color:\s*var\(--info-foreground\)' -and $stylesContent -match '\.empty-state\.warning-state svg\s*\{[^}]*color:\s*var\(--warning-foreground\)' -and $stylesContent -match 'html\.theme-hosted-dark body \.empty-state > :is\(h2, h3\)\s*\{[^}]*font-size:\s*18px !important;[^}]*font-weight:\s*600 !important;[^}]*line-height:\s*24px !important'
    $detailPresentationValid = $detailPresentationValid -and $appContent -match 'function renderCatalogStatusBadge\(catalogStatus\)' -and $appContent -match 'function renderCurrentHostedRules\(catalogStatus, assessment\)' -and $appContent -match 'if \(!catalogStatus\.rules\.length\) return ""' -and ([regex]::Matches($appContent, 'renderCatalogStatusBadge\(catalogStatus\)').Count -eq 3) -and ([regex]::Matches($appContent, 'renderCurrentHostedRules\(catalogStatus').Count -eq 3) -and $appContent -match 'Current Hosted Rule:' -and $appContent -match 'label: "Retired"' -and $appContent -notmatch 'Mapped Hosted Rules:|Contributing Rules \(|Retired Mapping|Hosted Catalog Status:|No authoritative mapping|No Hosted rule is mapped to this source candidate'
    $detailPresentationValid = $detailPresentationValid -and
        $appContent -match 'function renderEvidenceDisclosure\(' -and $appContent -match 'aria-controls="\$\{escapeHtml\(id\)\}" aria-expanded="\$\{expanded\}"' -and
        $appContent -match 'function renderRelatedHostedCoverage\(' -and $appContent -match 'item\.hostedRuleId' -and $appContent -match 'item\.rationale' -and
        $appContent -match 'renderAssessmentExplanation\(candidate, assessment\)' -and
        $appContent -match 'function renderInformationPanel\(content, \{ iconMarkup = fluentIcon\("info-20-regular"\)' -and
        $appContent -match 'className: "assessment-context section-guidance"' -and
        $appContent -match 'className: "rule-actions-guidance section-guidance"' -and
        $appContent -match 'iconMarkup: icon\("lock"\)' -and
        $appContent -notmatch 'read-only-boundary' -and
        $stylesContent -notmatch '\.read-only-boundary' -and
        $stylesContent -match '\.information-panel \.fluent-icon,\s*\.information-panel > \.codicon\s*\{[^}]*width:\s*20px;[^}]*height:\s*20px;[^}]*color:\s*var\(--information-icon\)' -and
        $stylesContent -match '\.section-guidance\s*\{[^}]*margin:\s*0 0 12px' -and
        $appContent -match 'Resource types apply only to implementation rules\.' -and
        $appContent -match 'class="evidence-box scroll-surface" data-decision-field="rationale"' -and
        $stylesContent -match '\.field-stack textarea:not\(\.evidence-box\)' -and
        $stylesContent -match '\.evidence-disclosure-label\s*\{[^}]*align-items:\s*baseline;[^}]*gap:\s*8px' -and
        $stylesContent -match '\.evidence-disclosure-label > \.count-badge\s*\{[^}]*min-height:\s*18px;[^}]*height:\s*18px;[^}]*padding:\s*0 6px' -and
        $stylesContent -match '\.current-hosted-rule\s*\{[^}]*padding-bottom:\s*12px'
    $detailPresentationValid = $detailPresentationValid -and
        $appContent -notmatch 'wording\.presentation === "member"' -and
        $appContent -match 'renderRuleReferences\(issue\.bannerMessage, issue\.ruleIds, "rule-issue-banner-reference"\)' -and
        $appContent -match '<span class="section-label rule-issue-assessment-label">Assessment:</span>\s*<section class="rule-issue-assessment">' -and
        $stylesContent -match '--error-foreground:\s*#f6d1d3' -and
        $stylesContent -match '\.rule-issue-banner\s*\{[^}]*border:\s*1px solid var\(--warning-action-border\);[^}]*border-radius:\s*4px' -and
        $stylesContent -match '\.rule-issue-banner\.contradiction\s*\{[^}]*color:\s*var\(--error-foreground\);[^}]*background:\s*var\(--error-background\);[^}]*border:\s*1px solid var\(--error-border\)' -and
        $stylesContent -match '\.rule-issue-banner > \.codicon\s*\{[^}]*transform:\s*translateY\(2px\)' -and
        $stylesContent -match '\.rule-issue-banner-reference\s*\{[^}]*color:\s*inherit;[^}]*font-weight:\s*600 !important' -and
        $stylesContent -match '\.rule-issue-assessment\s*\{[^}]*margin-top:\s*8px;[^}]*background:\s*var\(--surface-quiet\);[^}]*border-left:\s*4px solid var\(--accent\)' -and
        $stylesContent -match '\.rule-issue-assessment-label\s*\{[^}]*display:\s*block;[^}]*margin-top:\s*16px'
    Add-TestResult -Name 'detail-presentation-contract' -Passed $detailPresentationValid -Detail 'Candidates and Details use connected full-width tabs; empty Details renders its selection illustration and prompt, while selected details retain the approved evidence and control presentation.'

    $staticInformationColorsValid = $stylesContent -match '--ink: #bfbfbf' -and $stylesContent -match '--muted: #8c8c8c' -and $stylesContent -match '\.stage-link\s*\{[^}]*color:\s*var\(--muted\)' -and $stylesContent -match '\.stage-link\.active\s*\{[^}]*color:\s*var\(--ink\);[^}]*background:\s*rgba\(255, 255, 255, 0\.13\)' -and $stylesContent -match '\.stage-link\.active::before\s*\{[^}]*background:\s*var\(--ink\)' -and $stylesContent -match '\.save-indicator\s*\{[^}]*color:\s*#89d185' -and $stylesContent -match '\.tree-impact\s*\{[^}]*color:\s*var\(--blue\)' -and $stylesContent -match '\.toast\s*\{[^}]*background:\s*#202122;[^}]*border:\s*1px solid var\(--line\);[^}]*border-radius:\s*4px'
    Add-TestResult -Name 'static-information-colors' -Passed $staticInformationColorsValid -Detail 'Shell state uses Hosted dark theme active and inactive neutrals, autosave remains green, and Workbench domain values retain their semantic colors.'

    $sourceTreeValid = $appContent -match 'candidate-source-root' -and $appContent -match 'candidate-category' -and $appContent -match '\["maintainer", "Maintainer Proposals"\]' -and $appContent -match 'key: `maintainer:\$\{candidate\.id\}:\$\{assessment\.assessmentId\}`' -and $appContent -match 'Proposal rationale' -and $appContent -notmatch 'data-category-checkbox' -and $appContent -match 'data-decision-key' -and $appContent -notmatch 'reviewSet' -and $stylesContent -match '\.candidate-tree-row' -and $stylesContent -match '\.candidate-list-header' -and $stylesContent -match '\.candidate-category > summary\s*\{[^}]*grid-template-columns:\s*18px minmax\(0, 1fr\) auto'
    $sourceTreeValid = $sourceTreeValid -and $appContent -match 'function getCandidateDecoration\(' -and $appContent -match 'getPlanReadiness\(candidate\)\.ready' -and $appContent -match 'function getCandidateAggregateDecoration\(' -and $appContent -match 'status: needsInput \? "needs-input" : "ready"' -and $appContent -match 'function syncCandidateTreeAggregates\(' -and $appContent -match 'candidate-decoration-description sr-only' -and $appContent -match 'codicon-diff-modified'
    $sourceTreeValid = $appContent -match 'function buildCandidateTreeNodes\(' -and
        $appContent -match '\["maintainer", "Maintainer Proposals"\]' -and
        $appContent -match 'kind: "source"' -and
        $appContent -match 'kind: "folder"' -and
        $appContent -match 'function renderCandidateHierarchyRow\(' -and
        $appContent -match 'function getCandidateDecoration\(' -and
        $appContent -match 'function getCandidateAggregateDecoration\(' -and
        $appContent -match 'status: needsInput \? "needs-input" : "ready"' -and
        $appContent -match 'function syncCandidateTreeAggregates\(' -and
        $appContent -match 'candidate-decoration-description sr-only' -and
        $stylesContent -match '\.candidate-source-row\s*\{' -and
        $stylesContent -match '\.candidate-folder-row\s*\{'
    Add-TestResult -Name 'evaluated-source-tree' -Passed $sourceTreeValid -Detail 'Interactive, Contributor Guidance, and Maintainer Proposals candidates are grouped by source; selected leaf readiness propagates through ancestors with accessible descriptions and needs-input precedence.'

    $contributorHierarchyValid = $appContent -match 'function groupCandidatesBySource\(' -and $appContent -match 'function renderContributorDocument\(' -and $appContent -match 'data-source-id="\$\{escapeHtml\(source\.sourceId\)\}"' -and $appContent -match 'class="candidate-parent-label"><strong>\$\{escapeHtml\(source\.sourceTitle\)\}</strong>' -and $appContent -match 'renderCandidateItems\(sectionKey, candidates, "contributor-candidates"\)' -and $appContent -match '\["candidate", "Candidate", "Candidate",' -and $stylesContent -match '\.contributor-document > summary > \.candidate-parent-label > strong,[\s\S]*?\.contributor-document \.candidate-tree-copy > strong\s*\{[^}]*text-overflow:\s*ellipsis;[^}]*white-space:\s*nowrap' -and $stylesContent -match '\.contributor-document > summary > \.candidate-parent-label > strong\s*\{[^}]*flex:\s*1 1 auto;[^}]*text-align:\s*left'
    $contributorHierarchyValid = $appContent -match 'function renderContributorDocument\(' -and
        $appContent -match 'data-source-id="\$\{escapeHtml\(source\.sourceId\)\}"' -and
        $appContent -match 'class="candidate-parent-label"><strong>\$\{escapeHtml\(source\.sourceTitle\)\}</strong>' -and
        $stylesContent -match '\.candidate-parent-label > strong,\s*\.candidate-tree-copy > strong\s*\{[^}]*text-overflow:\s*ellipsis;[^}]*white-space:\s*nowrap'
    $contributorHierarchyValid = $appContent -match 'function groupCandidatesBySource\(' -and
        $appContent -match 'sourceType === "upstream" \? groupCandidatesBySource\(candidates\)' -and
        $appContent -match 'sourceType === "upstream" \? members\[0\]\.sourceTitle : groupKey' -and
        $appContent -match 'extraClass: sourceType === "upstream" \? "contributor-document" : ""' -and
        $appContent -match 'children: buildCandidateLeafNodes\(sectionKey, candidates, override\)' -and
        $stylesContent -match '\.candidate-parent-label > strong,\s*\.candidate-tree-copy > strong\s*\{[^}]*text-overflow:\s*ellipsis'
    Add-TestResult -Name 'contributor-document-children' -Passed $contributorHierarchyValid -Detail 'Contributor Guidance documents are non-actionable parents whose independently assessed rule candidates retain shared sortable rows.'

    $candidateHeaderTooltipsValid = $appContent -match '\["candidate", "Candidate", "Candidate", "Source rule ID and title\."\]' -and $appContent -match '\["impact", "Impact", "Impact", "Priority score balancing rule value and review risk\."\]' -and $appContent -match '\["cost", "Tokens", "Token Usage", "Unsigned values show current guarded-token usage\. Signed values show the estimated change if the recommended action is promoted\."\]' -and $appContent -match '\["recommendation", "Recommended", "Recommendation", "AI-recommended action for maintainer review\."\]' -and $appContent -match 'title="\$\{escapeHtml\(help\)\}"' -and $appContent -match 'function getCandidateTokenValue\(' -and $appContent -match 'function formatCandidateTokenValue\(' -and $appContent -match 'if \(sort\.field === "cost"\) return getCandidateTokenValue\(candidate, assessment\)'
    $candidateHeaderTooltipsValid = $appContent -match '\["impact", "Impact", "Impact", "Priority score balancing rule value and review risk\."\]' -and
        $appContent -match 'data-workbench-tooltip="\$\{escapeHtml\(help\)\}"' -and
        $appContent -match 'aria-label="Sort by \$\{escapeHtml\(accessibleLabel\)\}, \$\{nextDirection\}"' -and
        $appContent -match 'function getCandidateTokenValue\('
    Add-TestResult -Name 'candidate-header-tooltips' -Passed $candidateHeaderTooltipsValid -Detail 'Candidate headers preserve concise definitions; Tokens uses unsigned current usage and signed recommended deltas consistently in display and sorting.'

    $directTreeUpdatesValid = $appContent -match 'function syncCandidateTreeRows' -and $appContent -match 'function selectCandidate\(key, rationaleReturnView = null\)\s*\{[^}]*syncCandidateTreeRows\(\)' -and $appContent -match 'function updateDecision\(candidate, changes\)[\s\S]*?saveDecision\(candidate,' -and $appContent -match 'function saveDecision\(candidate, decision\)[\s\S]*?syncCandidateTreeRows\(\);\s*renderBulkActions\(\);\s*syncAssessmentPlanToggle\(candidate\);\s*renderDecisionOutputs\(\);\s*\}' -and $appContent -match 'function syncAssessmentPlanToggle\(candidate\)' -and $appContent -match 'control\.checked = getDecision\(candidate\)\.inPlan' -and $appContent -match 'function handleTreeSelection\(event\)[\s\S]*?updateDecision\(candidate,[^;]+;\s*selectCandidate\(candidate\.key\);\s*\}' -and $appContent -match 'function updateCandidateSort\(button\)[\s\S]*?group\.appendChild\(rowsByKey\.get\(candidate\.key\)\)'
    $directTreeUpdatesValid = $directTreeUpdatesValid -and $appContent -match 'function removePlanMembership\(candidate\) \{\s*const \{ assessment, \.\.\.maintainerDecision \} = getDecision\(candidate\);\s*removeCandidateFromBulkOperations\(candidate\.key\);\s*saveDecision\(candidate, \{ \.\.\.maintainerDecision, \.\.\.createPlanMembership\(\) \}\);' -and $appContent -match 'if \(candidateCheckbox\.checked\) \{\s*updateDecision\(candidate, \{ inPlan: true \}\)' -and $appContent -match 'else \{\s*removePlanMembership\(candidate\)' -and $appContent -match 'updateDecision\(candidate, \{ action \}\);\s*syncAssessmentActionControls\(candidate\)' -and $appContent -match 'function syncAssessmentActionControls\(candidate\)' -and $appContent -match 'control\.closest\("\.action-option"\)\?\.classList\.toggle\("selected", selected\)' -and $appContent -match 'badge\.textContent = formatRecommendation\(decision\.action\)' -and $appContent -match 'if \(event\.target\.hasAttribute\("data-plan-toggle"\)\) \{\s*if \(event\.target\.checked\) updateDecision\(candidate, \{ inPlan: true \}\);\s*else removePlanMembership\(candidate\);\s*return;' -and $appContent -match 'Include this candidate in the promotion plan' -and $appContent -notmatch 'Remove and reset|Remove candidate and reset its decision'
    $directTreeUpdatesValid = $appContent -match 'function syncCandidateTreeRows' -and
        $appContent -match 'function selectCandidate\(key, rationaleReturnView = null\)\s*\{[^}]*syncCandidateTreeRows\(\)' -and
        $appContent -match 'function saveDecision\(candidate, decision\)[\s\S]*?syncCandidateTreeRows\(\);\s*renderBulkActions\(\);\s*renderDecisionOutputs\(\);' -and
        $appContent -notmatch 'syncAssessmentPlanToggle|data-plan-toggle|Include this candidate in the promotion plan' -and
        $appContent -match 'function updateCandidateSort\(button\)[\s\S]*?candidateHierarchicalView\.refresh\(\)' -and
        $hierarchicalViewContent -match 'target\.checked = source\.checked' -and
        $hierarchicalViewContent -match 'const existing = new Map\(Array\.from\(this\.rowsContainer\.children\)' -and
        $hierarchicalViewContent -match 'patchNode\(row, rendered\)'
    Add-TestResult -Name 'tree-leaf-direct-updates' -Passed $directTreeUpdatesValid -Detail 'Tree membership shortcuts update in place without replacing scroll, focus, selection, or expanded folders; Details derives membership from a saved action and explicit Undo retains the full-reset lifecycle.'

    $ruleActionsValid = $indexContent -notmatch 'plan-count-control|plan-action-count' -and
        $appContent -notmatch 'elements\["plan-action-count"\]|data-plan-toggle|Include this candidate in the promotion plan' -and
        $appContent -match 'function getCatalogStatus' -and
        $appContent -match 'candidate\.catalogMapping\.state === "active"' -and
        $appContent -match 'candidate\.catalogMapping\.state === "retired"' -and
        $appContent -notmatch 'relatedHostedRules|isPromotionOwner' -and
        $appContent -match 'function getAllowedActions' -and
        $appContent -match 'allowedActions\.map\(\(action\)' -and
        $appContent -match 'type="radio" name="rule-action"' -and
        $appContent -match 'syncAssessmentActionControls\(candidate, action\)' -and
        $appContent -match 'if \(action === "no-change"\)[\s\S]*?saveDecision\(candidate, null\);[\s\S]*?renderAssessment\(\);' -and
        $appContent -match 'decision\.action === "no-change" \? "disabled" : ""' -and
        $appContent -notmatch 'updateDecision\(candidate, \{ action \}\)' -and
        $appContent -match 'createPlanMembership\(isPromotionAction\(action\) \? "manual" : "none"\)' -and
        $appContent -match 'if \(!rationale\)[\s\S]*?saveDecision\(candidate, null\)' -and
        $appContent -match 'SESSION_SCHEMA_VERSION = 4' -and
        $appContent -match '\$schema: "workbench-draft-v4\.schema\.json"'
    $ruleActionsValid = $appContent -match 'function getCatalogStatus' -and
        $appContent -match 'function getAllowedActions' -and
        $appContent -match 'data-decision-field="proposedText"' -and
        $appContent -match 'data-retire-hosted-rule=' -and
        $appContent -match 'candidate\.recommendation\.retireHostedRuleIds' -and
        $appContent -match 'function isActionableDecision\(' -and
        $appContent -match 'createPlanMembership\(isPromotionAction\(action\) \|\| retireHostedRuleIds\.length \? "manual" : "none"\)' -and
        $appContent -match 'SESSION_SCHEMA_VERSION = 7' -and
        $appContent -match 'WORKBENCH_DRAFT_SCHEMA_VERSION = 4' -and
        $appContent -match 'Rule Actions: <strong class="rule-reference">\$\{escapeHtml\(displayId\)\}</strong>' -and
        $appContent -notmatch 'proposed-hosted-rule-id|rule-action-header|rule-actions-content subcontext-container' -and
        $appContent -notmatch 'recommendedRetirementRuleIds|relatedHostedRules|isPromotionOwner|data-decision-field="proposedHostedRuleId"'
    Add-TestResult -Name 'catalog-status-rule-actions' -Passed $ruleActionsValid -Detail 'Catalog-owned mapping controls lifecycle actions and immutable identity; Rule Actions uses one generated-ID heading and unboxed controls, and related coverage cannot infer ownership.'

    $bulkActionsValid = $indexContent -match 'class="bulk-actions" id="bulk-actions"' -and $indexContent -match 'data-bulk-scope="add"' -and $indexContent -match 'data-bulk-scope="update"' -and $indexContent -match 'data-bulk-scope="actionable"' -and $indexContent -match 'data-bulk-undo' -and $appContent -match 'bulkOperations:\s*\[\]' -and $appContent -match 'function createPlanMembership\(' -and $appContent -match 'function isValidPlanMembership\(' -and $appContent -match 'function getBulkActionCandidates\(' -and $appContent -match 'return !decision\.inPlan' -and $appContent -match 'function applyBulkSelection\(' -and $appContent -match 'createPlanMembership\("bulk", operation\.id\)' -and $appContent -match 'function undoBulkOperation\(' -and $appContent -match 'decision\?\.planMembershipSource !== "bulk" \|\| decision\.bulkOperationId !== operation\.id' -and $appContent -match 'promotesManualMembership' -and $appContent -match 'removeCandidateFromBulkOperations\(candidate\.key\)' -and $appContent -match 'source:\s*decision\.planMembershipSource' -and $appContent -match 'bulkOperations:\s*state\.session\.bulkOperations' -and $appContent -match 'draft\.bulkOperations' -and $stylesContent -match '\.bulk-actions-menu\s*\{' -and $stylesContent -match '\.plan-membership-badge\s*\{'
    $bulkActionsValid = $bulkActionsValid -and $appContent -match 'addEventListener\("mouseleave", handleBulkActionsMouseLeave\)' -and $appContent -match 'function renderBulkSelectionOutputs\(\) \{\s*syncCandidateTreeRows\(\);\s*renderBulkActions\(\);\s*renderAssessment\(\);\s*renderDecisionOutputs\(\);\s*\}' -and ([regex]::Matches($appContent, 'renderBulkSelectionOutputs\(\)').Count -eq 3) -and $appContent -match 'function saveDecision\(candidate, decision\)[\s\S]*?syncCandidateTreeRows\(\);\s*renderBulkActions\(\);\s*syncAssessmentPlanToggle\(candidate\);' -and $appContent -notmatch 'renderAllPreservingCandidateDisclosures' -and $appContent -match 'data-source-type="overrides"' -and $appContent -match 'data-source-type="\$\{escapeHtml\(sourceType\)\}"'
    $bulkActionsValid = $bulkActionsValid -and $indexContent -match 'id="bulk-actions-note"' -and $appContent -match 'function getValidatedCodeOwnerIdentity\(' -and $appContent -match 'button\.disabled = !identity \|\| count === 0' -and $appContent -match 'if \(state\.session\.decisions\[candidate\.key\]\) return false' -and $appContent -match 'function getBulkDecisionRationale\(' -and $appContent -match 'action: assessment\.recommendation' -and $appContent -match 'rationale: getBulkDecisionRationale\(candidate, assessment\.recommendation\)'
    $bulkActionsValid = $bulkActionsValid -and $appContent -match 'action: recommendationScope' -and $appContent -match 'candidateKeys: candidates\.map' -and $appContent -notmatch 'candidateSourceHashes: Object\.fromEntries' -and $appContent -notmatch 'operation\.recordedBy\?\.type === "github-cli"'
    $bulkActionsValid = $bulkActionsValid -and $stylesContent -match '\.bulk-actions-menu::before\s*\{[^}]*top:\s*-5px;[^}]*height:\s*5px;[^}]*content:\s*""' -and $stylesContent -match '\.bulk-actions-menu button:disabled\s*\{[^}]*cursor:\s*default !important'
    $bulkActionsValid = $indexContent -match 'class="bulk-actions" id="bulk-actions"' -and
        $appContent -match 'bulkOperations:\s*\[\]' -and
        $appContent -match 'function applyBulkSelection\(' -and
        $appContent -match 'createPlanMembership\("bulk", operation\.id\)' -and
        $appContent -match 'function undoBulkOperation\(' -and
        $appContent -match 'function renderBulkSelectionOutputs\(\) \{\s*syncCandidateTreeRows\(\);' -and
        $appContent -match 'const overrideRootId = "candidate:source:overrides"' -and
        $appContent -match 'const sourceId = `candidate:source:\$\{sourceType\}`' -and
        $appContent -match 'action: recommendationScope' -and
        $appContent -match 'candidateKeys: candidates\.map'
    Add-TestResult -Name 'bulk-plan-membership' -Passed $bulkActionsValid -Detail 'CODEOWNER-only Bulk Actions create complete recommendation-aligned decisions with deterministic rationale and actor/hash provenance, preserve manual decisions, promote subsequent edits to manual ownership, and undo only entries still owned by the matching operation.'

    $capacityProjectionValid = $appContent -match 'Plan projection' -and $appContent -match 'const GUIDANCE_CAPACITY_BUCKETS = \[' -and $appContent -match 'function getGuidanceCapacityProjection\(' -and $appContent -match 'function getActionCapacityBucketNames\(' -and $appContent -match 'projectedGuardedTokens: currentGuardedTokens \+ draftDeltaTokens' -and $appContent -match 'projectedHeadroomTokens: budgetTokens - currentGuardedTokens - draftDeltaTokens' -and $appContent -match 'data-workbench-tooltip="\$\{escapeHtml\(projectedLabel\)\}"' -and $appContent -match 'aria-label="\$\{escapeHtml\(projectedLabel\)\}"' -and $appContent -match 'function renderDecisionOutputs\(\)[\s\S]*?renderPlan\(\);[\s\S]*?renderCapacity\(\);[\s\S]*?renderPreview\(\);[\s\S]*?renderCounts\(\);' -and $appContent -match 'function resetCandidate\(' -and $appContent -match 'removeCandidateFromBulkOperations\(candidate\.key\)' -and $appContent -match 'updateOverrideLifecycle\(candidate, null, null\)' -and $appContent -match 'saveDecision\(candidate, null\)' -and $appContent -match 'clearCandidateSelection\(candidate\)' -and $appContent -match 'function showToast\(message, error = false\)' -and $appContent -match 'if \(!error\) toastTimer = setTimeout\(dismissNotification, 8000\)' -and $appContent -notmatch 'showToast\([^\n]+, false, \{' -and $indexContent -match 'id="toast-close"[^>]*aria-label="Dismiss Notification"' -and $stylesContent -match '\.toast\.visible\s*\{[^}]*pointer-events:\s*auto'
    $capacityProjectionValid = $capacityProjectionValid -and $stylesContent -match '\.toast\s*\{[^}]*bottom:\s*26px'
    Add-TestResult -Name 'undo-updates-capacity-projection' -Passed $capacityProjectionValid -Detail 'Explicit Undo clears decision, membership, selection, Preview, and any provisional override atomically; membership-only uncheck preserves the decision and unresolved items contribute no capacity delta.'

    $semanticColorsValid = $stylesContent -match '\.recommendation-badge\s*\{[^}]*background:\s*#303b60;[^}]*border:\s*1px solid #7f91c4' -and $stylesContent -match '\.recommendation-badge\.add\s*\{[^}]*background:\s*#174638' -and $stylesContent -match '\.recommendation-badge\.exclude\s*\{[^}]*background:\s*#4a252b' -and $stylesContent -match '\.recommendation-badge\.defer\s*\{[^}]*background:\s*#493812' -and $stylesContent -match '\.candidate-lifecycle,\s*\.candidate-state\s*\{[^}]*border:\s*1px solid #7f91c4' -and $stylesContent -match '\.candidate-tree-row\.in-plan:not\(\.active\)\s*\{[^}]*background:\s*rgba\(97, 226, 148, 0\.06\)' -and $stylesContent -match '\.catalog-status\.mapped' -and $stylesContent -match '\.action-option\.selected' -and $stylesContent -match '\.plan-undo:hover\s*\{[^}]*background:\s*#31506b'
    $semanticColorsValid = $semanticColorsValid -and $stylesContent -match '--added-resource:\s*#78a680' -and $stylesContent -match '--modified-resource:\s*#e2c08d' -and $stylesContent -match '\.candidate-parent-decoration-icon\s*\{[^}]*margin-left:\s*auto' -and $stylesContent -match '\.candidate-tree-copy\s*\{[^}]*grid-template-columns:\s*minmax\(0, 1fr\) 16px' -and $stylesContent -match 'candidate-decoration-needs-input[\s\S]*color:\s*var\(--modified-resource\) !important'
    $semanticColorsValid = $stylesContent -match '--added-resource:\s*#78a680' -and
        $stylesContent -match '--modified-resource:\s*#e2c08d' -and
        $stylesContent -match '\.hierarchical-parent-row\.candidate-aggregate-ready[\s\S]*?color:\s*var\(--added-resource\)' -and
        $stylesContent -match '\.hierarchical-parent-row\.candidate-aggregate-needs-input[\s\S]*?color:\s*var\(--modified-resource\)' -and
        $stylesContent -match '\.candidate-parent-decoration-icon\s*\{[^}]*margin-left:\s*auto' -and
        $stylesContent -match '\.candidate-tree-copy\s*\{[^}]*grid-template-columns:\s*minmax\(0, 1fr\) 16px'
    Add-TestResult -Name 'semantic-color-contract' -Passed $semanticColorsValid -Detail 'Lifecycle, recommendation, catalog mapping, selected action, plan membership, and Undo states use readable semantic colors and visible borders.'

    $errorBannerStyleValid = $stylesContent -match '\.error-banner\s*\{[^}]*display:\s*grid;[^}]*grid-template-columns:\s*20px minmax\(0, 1fr\) 24px;[^}]*min-height:\s*36px' -and
        $stylesContent -match '\.error-banner\s*\{[^}]*color:\s*var\(--error-foreground\);[^}]*background:\s*var\(--error-background\);[^}]*border:\s*1px solid var\(--error-border\)' -and
        $stylesContent -match '\.error-banner\s*\{[^}]*font-size:\s*var\(--font-size-default\);[^}]*line-height:\s*var\(--line-height-default\)' -and
        $stylesContent -match '\.error-banner\[hidden\]\s*\{[^}]*display:\s*none' -and
        $stylesContent -match '\.error-banner > \.error-banner-icon\s*\{[^}]*width:\s*20px;[^}]*height:\s*20px;[^}]*color:\s*inherit;[^}]*fill:\s*currentColor' -and
        $stylesContent -match '\.error-banner-message\s*\{[^}]*min-width:\s*0;[^}]*overflow-wrap:\s*anywhere' -and
        $stylesContent -match '\.error-banner-dismiss\s*\{[^}]*width:\s*24px;[^}]*height:\s*24px;[^}]*color:\s*inherit;[^}]*background:\s*transparent;[^}]*border:\s*0' -and
        $stylesContent -match '\.error-banner-dismiss:hover\s*\{[^}]*background:\s*var\(--accent-soft\)' -and
        $stylesContent -match '\.error-banner-dismiss :is\(\.codicon, \.fluent-icon\)\s*\{[^}]*width:\s*16px;[^}]*height:\s*16px'
    Add-TestResult -Name 'error-banner-style-contract' -Passed $errorBannerStyleValid -Detail 'Reusable error banners use a compact icon/message/dismiss layout, shared pink error tokens, wrapping text, hidden-state support, and the existing dismiss hover treatment.'

    $clickableAffordanceValid = $stylesContent -match '\.clickable\s*\{\s*cursor:\s*pointer !important' -and
        $stylesContent -match '\.clickable:disabled,[\s\S]*?cursor:\s*default !important' -and
        $indexContent -match '<body class="static-surface">' -and
        $indexContent -match 'class="editable-text" id="search-input"' -and
        $indexContent -match 'class="editable-text" id="approver-name"' -and
        $appContent -match '<input class="editable-text" type="search" placeholder="Filter preview files"' -and
        $stylesContent -match '\.static-surface\s*\{\s*cursor:\s*default' -and
        $stylesContent -match '\.editable-text:not\(\[readonly\]\):not\(:disabled\),[\s\S]*?\.static-surface textarea:not\(\[readonly\]\):not\(:disabled\),[\s\S]*?cursor:\s*text' -and
        $indexContent -match 'class="button review clickable"[^>]*id="preview-review-toggle"' -and
        $appContent -match 'preview-file-tree-item clickable' -and
        $appContent -match 'preview-context-expand clickable' -and
        $appContent -match 'hierarchical-parent-row[^"]*clickable' -and
        $appContent -match 'assessment-result-row clickable' -and
        $appContent -match 'candidate-tree-row clickable' -and
        $appContent -match 'action-option clickable' -and
        $appContent -match 'plan-detail-link clickable'
    Add-TestResult -Name 'clickable-cursor-affordance' -Passed $clickableAffordanceValid -Detail 'Static Workbench content retains the normal arrow, editable text controls use the text cursor, and available command, navigation, disclosure, row, and option controls use the pointer cursor.'

    $buttonComponentValid = $indexContent -match '<span class="button-label">Export Draft</span>' -and
        $indexContent -match '<span class="button-label">Import Draft</span>' -and
        $indexContent -match 'class="button review clickable"[^>]*id="preview-review-toggle"[^>]*>Review Changes</button>' -and
        $indexContent -match 'class="button primary clickable"[^>]*id="approve-export-button"' -and
        $stylesContent -match '\.button\s*\{[^}]*--button-background:[^}]*--button-hover-background:[^}]*--button-foreground:[^}]*border-radius:\s*6px' -and
        $stylesContent -match '\.button:hover:not\(:disabled\):not\(\[aria-disabled="true"\]\)\s*\{[^}]*background:\s*var\(--button-hover-background\)' -and
        $stylesContent -match '\.button :is\(\.codicon, \.octicon\)\s*\{[^}]*color:\s*inherit;[^}]*fill:\s*currentColor' -and
        $stylesContent -match '\.button\.primary\s*\{[^}]*--button-background:\s*#1f6284;[^}]*--button-hover-background:\s*var\(--accent-deep\);[^}]*--button-border:\s*#78b9d4;[^}]*--button-hover-border:\s*#9bd6eb' -and
        $stylesContent -match '\.button\.review\s*\{[^}]*--button-background:\s*#196c2e;[^}]*--button-hover-background:\s*#238636;[^}]*--button-border:\s*#93ba9d;[^}]*--button-hover-border:\s*#b9d8bf' -and
        $stylesContent -match '\.button:disabled,[\s\S]*?color:\s*var\(--disabled-foreground\);[\s\S]*?background:\s*var\(--disabled-background\);[\s\S]*?border-color:\s*var\(--disabled-border\);[\s\S]*?opacity:\s*1'
    $buttonComponentValid = $buttonComponentValid -and
        $stylesContent -notmatch '\.button\.secondary' -and
        $stylesContent -notmatch '\.rule-issue-plan-action:disabled' -and
        $stylesContent -notmatch '\.title-draft-popover \.button:hover' -and
        $stylesContent -match '\.title-draft-popover \.button\s*\{[^}]*--button-background:\s*transparent;[^}]*--button-hover-background:\s*rgba\(255, 255, 255, 0\.06\)'
    Add-TestResult -Name 'button-component-contract' -Passed $buttonComponentValid -Detail 'Text command buttons use Title Case, shared 6px geometry, explicit base and hover palettes, inherited icon color, and hard disabled colors.'

    $planColumnsValid = $indexContent -match '<col class="plan-column-source">\s*<col class="plan-column-action">' -and $indexContent -match '<th>Source</th>\s*<th>Action</th>' -and $indexContent -match '<th>Controls</th>' -and $appContent -match '<td class="plan-source">' -and $appContent -match '<td class="plan-action">' -and $appContent -match '<tr class="plan-candidate-row clickable"[^>]*tabindex="0"[^>]*data-plan-row=' -and $appContent -match '<span class="candidate-link">' -and $appContent -notmatch '<button class="candidate-link' -and $appContent -match 'function handlePlanRowKeyboardNavigation\(' -and $stylesContent -match '\.plan-candidate-row:hover td,[\s\S]*?background:\s*var\(--accent-soft\)' -and $stylesContent -match '\.plan-table\s*\{[^}]*table-layout:\s*fixed' -and $stylesContent -match '\.plan-table th\s*\{[^}]*white-space:\s*nowrap' -and $stylesContent -match '@media \(max-width: 1180px\)[\s\S]*?\.plan-table\s*\{\s*min-width:\s*900px' -and $stylesContent -match '\.plan-table th:last-child\s*\{[^}]*text-align:\s*center'
    $planColumnsValid = $indexContent -match '<col class="plan-column-source">\s*<col class="plan-column-type">\s*<col class="plan-column-action">' -and $appContent -match 'function renderPlanHeader\(' -and $appContent -match '\["type", "Type", "Type", "How the candidate entered the promotion plan\."\]' -and $appContent -match 'renderSortButton\(column, state\.planSort, \{ "plan-sort": column\[0\] \}\)' -and $appContent -match '<td class="plan-source"><span class="status-badge neutral plan-source-pill type-compact">\$\{escapeHtml\(formatTitleCase\(candidate\.sourceLabel\)\)\}</span></td>' -and $appContent -match '<td class="plan-type"><span class="status-badge neutral plan-membership-badge">' -and $appContent -match '<tr class="plan-candidate-row clickable"[^>]*tabindex="0"[^>]*data-plan-row=' -and $appContent -match '<span class="candidate-link">' -and $appContent -match '<span class="plan-candidate-title">' -and $appContent -match 'function handlePlanRowKeyboardNavigation\(' -and $stylesContent -match '\.plan-source-pill\s*\{[^}]*display:\s*inline-flex;[^}]*white-space:\s*nowrap' -and $stylesContent -match '\.plan-column-type\s*\{[^}]*width:\s*90px' -and $stylesContent -match '\.plan-table :is\(th, td\):not\(:first-child\):not\(:last-child\)\s*\{[^}]*text-align:\s*center' -and $stylesContent -match '\.plan-table :is\(th, td\):last-child\s*\{[^}]*text-align:\s*left' -and $stylesContent -match '\.plan-table th:first-child \.candidate-sort-button\s*\{[^}]*justify-content:\s*flex-start;[^}]*text-align:\s*left' -and $stylesContent -match '\.plan-candidate-row:hover td,[\s\S]*?background:\s*var\(--accent-soft\)' -and $stylesContent -match '\.plan-table\s*\{[^}]*min-width:\s*1000px;[^}]*table-layout:\s*fixed' -and $stylesContent -match '@media \(max-width: 1180px\)[\s\S]*?\.plan-table\s*\{\s*min-width:\s*900px'
    Add-TestResult -Name 'promotion-plan-column-alignment' -Passed $planColumnsValid -Detail 'Promotion Plan separates Source and sortable Type into eight aligned columns while retaining shared hover, focus, pointer, and keyboard behavior.'

    $planAttentionFilterValid = $indexContent -match 'id="return-catalog-button"[\s\S]*?class="plan-attention-filter"[\s\S]*?id="plan-attention-filter"[\s\S]*?codicon-git-pull-request-draft[\s\S]*?id="plan-attention-count"[\s\S]*?id="plan-undo-menu"' -and
        $appContent -match 'planAttentionOnly: false' -and
        $appContent -match 'attentionCandidates = allPlanCandidates\.filter\(\(candidate\) => !getPlanReadiness\(candidate\)\.ready\)' -and
        $appContent -match 'if \(!attentionCandidates\.length\) state\.planAttentionOnly = false' -and
        $appContent -match 'elements\["plan-attention-filter"\]\.disabled = attentionCandidates\.length === 0' -and
        $appContent -match 'state\.planAttentionOnly \? attentionCandidates : allPlanCandidates' -and
        $appContent -match 'Show all promotion plan items' -and
        $appContent -match 'Show only promotion plan items needing attention' -and
        $stylesContent -match '\.plan-attention-filter\s*\{[^}]*position:\s*relative;[^}]*width:\s*34px;[^}]*height:\s*34px' -and
        $stylesContent -match '#plan-attention-filter\[aria-pressed="true"\]\s*\{[^}]*color:\s*var\(--warning-foreground\)' -and
        $stylesContent -match '#plan-attention-filter > svg\s*\{[^}]*transform:\s*translate\(-2px, -2px\)' -and
        $stylesContent -match '#plan-attention-count\s*\{[^}]*right:\s*0;[^}]*bottom:\s*0'
    Add-TestResult -Name 'promotion-plan-attention-filter' -Passed $planAttentionFilterValid -Detail 'Promotion Plan filters incomplete items through a standard header icon with an offset count, amber active state, dynamic tooltip, and disabled zero state.'

    $ruleIssueTabPaginationValid = $indexContent -match 'id="rule-issue-tab-pager"[\s\S]*?id="rule-issues-previous"[\s\S]*?Previous Issues[\s\S]*?transform="rotate\(180 8 8\)"[\s\S]*?id="rule-issue-tab-viewport"[\s\S]*?id="rule-issues-filters"[\s\S]*?id="rule-issues-next"[\s\S]*?Next Issues' -and
        $appContent -match 'ruleIssueTabPage: 0' -and
        $appContent -match 'function getRuleIssueTabPages\(' -and
        $appContent -match 'function renderRuleIssueTabPagination\(' -and
        $appContent -match 'totalWidth <= pager\.clientWidth \+ 0\.5' -and
        $appContent -match 'renderRuleIssueTabPagination\(true\)' -and
        $appContent -match 'state\.ruleIssueTabPage = selectedPage >= 0 \? selectedPage : 0' -and
        $appContent -match 'previous\.disabled = state\.ruleIssueTabPage === 0' -and
        $appContent -match 'next\.disabled = state\.ruleIssueTabPage === pages\.length - 1' -and
        $stylesContent -match '\.rule-issue-tab-pager\.paging\s*\{[^}]*grid-template-columns:\s*28px minmax\(0, 1fr\) 28px' -and
        $stylesContent -match '\.rule-issue-tab-page-hidden\s*\{[^}]*display:\s*none !important' -and
        $stylesContent -match '\.rule-issue-tab-scroll-button:disabled,[\s\S]*?opacity:\s*0\.38' -and
        $stylesContent -match '\.rule-issue-tab-scroll-button\[hidden\]\s*\{[^}]*display:\s*none !important'
    Add-TestResult -Name 'rule-issue-tab-pagination' -Passed $ruleIssueTabPaginationValid -Detail 'Rule Issue type tabs page only complete labels and counts, reveal the selected type or default to the first page, expose durable Previous and Next controls with edge states, and hide paging when all tabs fit.'

    $ruleIssueRecommendationStagingValid = $appContent -match 'const activeRuleIssueRecommendations = new Set\(\)' -and
        $appContent -match 'async function stageRuleIssueRecommendation\(issue\)' -and
        $appContent -match 'activeRuleIssueRecommendations\.add\(issue\.id\)' -and
        $appContent -match 'for \(const \{ candidate, operation \} of candidateOperations\)' -and
        $appContent -match 'notify: false, commit: false, proposals' -and
        $appContent -match 'evaluations\.push\(evaluation\)' -and
        $appContent -match 'const nextSession = structuredClone\(state\.session\)' -and
        $appContent -match 'await persistSession\(nextSession, assertCurrent\)' -and
        $appContent -match 'const label = checking \? "Checking Relationships"' -and
        $appContent -match 'activeRuleIssueRecommendations\.delete\(issue\.id\)'
    Add-TestResult -Name 'rule-issue-recommendation-staging' -Passed $ruleIssueRecommendationStagingValid -Detail 'Rule Issue recommendations disable their action while every changed proposed text is reconciled and commit decisions only after all exact-text checks succeed.'

    $planDetailValid = $appContent -match 'data-plan-detail=' -and $appContent -match 'Complete required fields for' -and $appContent -match 'function openPlanCandidate\(' -and $appContent -match 'selectCandidate\(key, "plan"\)' -and $appContent -match 'row\.closest\("details\.candidate-category"\)' -and $appContent -match 'row\.closest\("details\.candidate-source-root"\)' -and $appContent -match 'row\.scrollIntoView' -and $appContent -match 'field\?\.focus'
    $planDetailValid = $planDetailValid -and $appContent -match 'data-rationale-save' -and $appContent -notmatch '<span>Save</span>' -and $appContent -match 'Save decision rationale and return to Promotion Plan' -and $appContent -match 'Save and return to Promotion Plan' -and $appContent -match 'save\.disabled = !value\.trim\(\)' -and $appContent -match 'await persistencePromise' -and $appContent -match 'if \(returnToPlan\)[\s\S]*?switchView\("plan"\)' -and $stylesContent -match '\.plan-detail-link:focus-visible' -and $stylesContent -match '\.rationale-heading'
    $planDetailValid = $planDetailValid -and $appContent -match 'data-plan-action=' -and $appContent -match 'openPlanCandidate\(action\.dataset\.planAction, "action"\)' -and $appContent -match 'focusTarget === "action"' -and $appContent -match 'function scrollCandidateDetailTargetIntoView\(' -and ([regex]::Matches($appContent, 'scrollCandidateDetailTargetIntoView\(').Count -eq 3) -and $appContent -match 'control\?\.focus' -and $appContent -match 'class="assessment-title-statuses"' -and $stylesContent -match '#candidate-sources-panel \.assessment-panel\s*\{[^}]*display:\s*grid;[^}]*grid-template-rows:\s*auto minmax\(0, 1fr\);[^}]*overflow:\s*hidden' -and $stylesContent -match ':is\(#candidate-sources-panel \.assessment-panel, #assessment-results-detail\) > \.assessment-content\s*\{[^}]*overflow-y:\s*auto'
    $planDetailValid = $appContent -match 'data-plan-detail=' -and
        $appContent -match 'data-plan-action=' -and
        $appContent -match 'function revealCandidateInTree\(' -and
        $appContent -match 'function openPlanCandidate\(' -and
        $appContent -match 'revealCandidateInTree\(key\)' -and
        $appContent -match 'focusTarget === "action"' -and
        $appContent -match 'focusTarget === "rationale"' -and
        $appContent -match 'control\?\.focus' -and
        $appContent -match 'field\?\.focus' -and
        $appContent -match 'data-rationale-save' -and
        $appContent -match 'if \(returnToPlan\)[\s\S]*?switchView\("plan"\)'
    Add-TestResult -Name 'promotion-plan-detail-routing' -Passed $planDetailValid -Detail 'Needs action opens and focuses Rule Actions while persistent rule identity remains fixed above the contained Details scroller; Needs rationale focuses Decision Rationale; Save returns plan-origin edits after persistence.'

    $planTokenDeltaValid = $appContent -match 'function getAssessmentTokenValue\(' -and $appContent -match '!getApplicabilityOverride\(candidate\) \|\| assessment\.guardedTokenDelta !== 0' -and $appContent -match 'function getActionTokenDelta\(' -and $appContent -match 'if \(!isPromotionAction\(action\)\) return 0' -and $appContent -match 'if \(action === "retire"\) return -estimateGuardedTokens\(getCurrentHostedText\(candidate\)\)' -and $appContent -match 'if \(action === "update"\) return proposedTokens - estimateGuardedTokens\(getCurrentHostedText\(candidate\)\)' -and $appContent -match 'function getCandidateTokenValue\(' -and $appContent -match 'function getPlanTokenValue\(' -and $appContent -match 'function getPlanTokenDisplay\(' -and $appContent -match 'return formatSignedNumber\(getPlanTokenValue\(candidate\)\)' -and $appContent -match 'function getPlanTokenDelta\(' -and $appContent -match 'return getActionTokenDelta\(candidate, decision\.action, decision\)' -and $appContent -match 'function getActionCapacityBucketNames\(' -and $appContent -match '<td class="mono">\$\{cost\}</td>' -and $appContent -match 'token\.textContent = formatCandidateTokenValue\(candidate, assessment\)' -and $appContent -match 'draftDeltaTokens: deltasByName\[bucket\.reportName\]'
    Add-TestResult -Name 'promotion-plan-token-deltas' -Passed $planTokenDeltaValid -Detail 'Token displays and Draft Item Estimate reuse signed action-aware values, including maintained proposed-text estimates for unresolved overrides, while capacity projections wait for an explicit action and Retire retains negative savings.'

    $approvalExportValid = $indexContent -match 'id="approver-name"' -and $indexContent -match 'id="approval-requirements"[^>]*aria-label="Approval Requirements"' -and $indexContent -match 'id="approve-export-button"[^>]*disabled' -and $indexContent -match 'Approve &amp; Export' -and $appContent -match 'function autofillApproverName\(' -and $appContent -match '__HOSTED_RULE_WORKBENCH__\?\.maintainerIdentity\?\.login' -and $appContent -match 'function renderApprovalRequirements\(' -and $appContent -match '\["Decision rationales"' -and $appContent -match '\["Catalog mutations"' -and $appContent -match '\["GitHub identity"' -and $appContent -match 'function getPreviewReadiness' -and $appContent -match 'mutationCount > 0' -and $appContent -match 'status = "no catalog mutations"' -and $appContent -match 'function buildApprovedRules' -and $appContent -match 'function buildApprovedMutation' -and $appContent -match 'function approveAndExport' -and $appContent -match '\$schema: "approved-rules-v4\.schema\.json"' -and $appContent -match 'kind: "hosted-approved-rules"' -and $appContent -match 'catalogContentSha256: state\.bundle\.catalog\.contentSha256' -and $appContent -notmatch 'hosted-rule-workbench-approval-handoff|sha256-payload-bytes-v1|crypto\.subtle\.digest\("SHA-256"' -and $stylesContent -match '\.approval-requirements'
    $approvalExportValid = $approvalExportValid -and $appContent -match '\["Rule actions", readiness\.missingActionCount' -and $appContent -match 'missingActionCount === 0' -and $appContent -match 'status = "needs action"'
    $approvalExportValid = $approvalExportValid -and $appContent -match 'APPROVED_RULES_SCHEMA_VERSION = 4'
    Add-TestResult -Name 'preview-approval-export' -Passed $approvalExportValid -Detail 'Preview explains plan, action, rationale, catalog mutation, and identity gates and blocks export until the approval contains at least one schema-valid catalog mutation.'

    $previewDiffValid = $indexContent -match 'id="preview-diff"' -and
        $indexContent -match 'id="preview-payload-diff"' -and
        $indexContent -match 'id="preview-json"' -and
        $indexContent -match 'id="preview-review-toolbar"[\s\S]*?class="preview-layout"' -and
        $indexContent -match 'id="preview-tree-resizer"[^>]*role="slider"' -and
        $indexContent -notmatch 'preview-split-labels' -and
        $appContent -match 'function buildPreviewFiles\(' -and
        $appContent -match 'function createPreviewFile\(' -and
        $appContent -match 'function renderPreviewFiles\(' -and
        $appContent -match 'function renderPreviewFile\(' -and
        $appContent -match 'function renderPreviewTopHunk\(' -and
        $appContent -match 'displayPath: scope \? `\$\{PREVIEW_SCOPE_LABELS\[scope\]\.toUpperCase\(\)\}/\$\{path\.split\("/"\)\.at\(-1\)\}` : path' -and
        $appContent -match 'data-preview-file-display-path=' -and
        $appContent -match 'class="preview-file-heading-wrapper"' -and
        $appContent -match 'data-preview-lines-toggle' -and
        $appContent -match 'function setPreviewLinesExpanded\(' -and
        $appContent -match 'function expandAllPreviewLines\(' -and
        $appContent -match 'function collapseAllPreviewLines\(' -and
        $appContent -match 'setPreviewLinesExpanded\(file, true\)' -and
        $appContent -match 'toggle\.innerHTML = octicon\(expanded \? "fold" : "unfold"\)' -and
        $appContent -match 'function renderPreviewDiffStat\(' -and
        $appContent -match 'const additionBlocks = Math\.floor\(5 \* additions / total\)' -and
        $appContent -match 'const deletionBlocks = Math\.floor\(5 \* deletions / total\)' -and
        $appContent -match '\? "delete" : "neutral"' -and
        $appContent -match 'octicon\("kebab-horizontal"\)' -and
        $appContent -match 'const iconName = status === "modified" \? "file-diff" : `file-\$\{status\}`' -and
        $appContent -match 'octicon\(`file-directory-\$\{expanded \? "open-" : ""\}fill`\)' -and
        $appContent -match 'octicon\("square"\)' -and
        $appContent -match 'octicon\("checkbox-fill"\)' -and
        $appContent -match 'octicon-shield-lock-16' -and
        $appContent -match 'function updatePreviewSelectedFile\(' -and
        $appContent -match 'function setPreviewFileCollapsed\(' -and
        $appContent -match 'function handlePreviewFileNavigation\(event\)[\s\S]*?previewSelectedFilePath = path;[\s\S]*?file\.scrollIntoView\(\{ block: "start", behavior: "auto" \}\)' -and
        $appContent -notmatch 'function syncPreviewTreeFileDisclosure\(' -and
        $appContent -match 'if \(viewed\.checked && !file\.querySelector\("\.preview-file-body"\)\.hidden\) setPreviewFileCollapsed\(file, true\)' -and
        $stylesContent -match '#preview-view \.preview-layout\s*\{[^}]*--preview-tree-width:\s*380px;[^}]*grid-template-columns:\s*var\(--preview-tree-width\) minmax\(0, 1fr\)' -and
        $stylesContent -match '\.preview-review-toolbar\s*\{[^}]*min-height:\s*60px' -and
        $stylesContent -match '\.preview-file-heading-wrapper\s*\{[^}]*position:\s*sticky;[^}]*top:\s*-2px;[^}]*height:\s*42px' -and
        $stylesContent -match '\.preview-file-heading\s*\{[^}]*position:\s*relative;[^}]*height:\s*42px' -and
        $stylesContent -match '\.preview-tree-resizer\s*\{[^}]*width:\s*5px;[^}]*cursor:\s*col-resize' -and
        $stylesContent -match '\.preview-review-file\.selected\s*\{[^}]*box-shadow:\s*0 0 0 2px #1f6feb' -and
        $stylesContent -match '\.preview-viewed\s*\{[^}]*width:\s*77px;[^}]*height:\s*28px' -and
        $stylesContent -match '\.preview-split-row\s*\{[^}]*grid-template-columns:\s*minmax\(0, 1fr\) minmax\(0, 1fr\)' -and
        $stylesContent -match '\.preview-diff-cell\s*\{[^}]*grid-template-columns:\s*44px minmax\(0, 1fr\)' -and
        $stylesContent -match '\.preview-diff-cell code\s*\{[^}]*white-space:\s*pre-wrap' -and
        $stylesContent -match ':is\(#preview-diff, #preview-payload-diff, #preview-json, #preview-protected\)\s*\{[^}]*gap:\s*16px' -and
        $stylesContent -match '#preview-view #preview-diff\s*\{[^}]*padding-top:\s*16px' -and
        $stylesContent -match '\.preview-diff-stat i\.delete\s*\{[^}]*background-image:\s*repeating-linear-gradient' -and
        $stylesContent -match '\.preview-diff-stat i\.neutral\s*\{[^}]*background:\s*rgba\(101, 108, 118, 0\.2\)' -and
        $stylesContent -match '\.preview-diff-cell\.add\s*\{[^}]*background:\s*#0f2d20' -and
        $stylesContent -match '\.preview-diff-cell\.delete\s*\{[^}]*background:\s*#3c1e23'
    Add-TestResult -Name 'preview-change-review' -Passed $previewDiffValid -Detail 'Preview renders one authenticated GitHub-style continuous split-file review with virtual artifact paths, status-aware tree icons, graphical totals, CODEOWNERS headers, explicit selection, and independent Viewed and disclosure state.'

    $rawPayloadNavigationValid = $appContent -match 'PREVIEW_CONTEXT_LINE_COUNT = 2' -and $appContent -match 'PREVIEW_DIRECTIONAL_EXPAND_COUNT = 10' -and $appContent -match 'createPreviewFile\("approval/approved-rules\.json"' -and $appContent -match 'function createContextualPreviewRows\(' -and $appContent -match 'direction: start === 0 \? "up" : index === rows\.length \? "down" : "all"' -and $appContent -match 'const selectedRows = direction === "all"' -and $appContent -match 'gap\.direction === "up" \? "fold-up" : gap\.direction === "down" \? "fold-down" : "unfold"' -and $stylesContent -match '\.preview-context-gap\s*\{[^}]*grid-template-columns:\s*44px minmax\(0, 1fr\)' -and $stylesContent -match '\.preview-context-expand\s*\{[^}]*width:\s*44px'
    Add-TestResult -Name 'raw-payload-change-navigation' -Passed $rawPayloadNavigationValid -Detail 'Resulting Catalog renders as one contextual full-file split diff with two context lines and exact local Octicon expansion controls.'

    $protectedPreviewValid = $appContent -match 'protected:\s*"Protected rules"' -and $appContent -match 'catalog\.protectedRuleFiles\.map' -and $appContent -match 'reference:\s*true' -and $appContent -match 'function renderPreviewReferenceFile\(' -and $appContent -match 'class="ui-badge status-capsule preview-reference-status"' -and $appContent -match 'class="preview-reference-row"' -and $appContent -match 'class="preview-reference-line-number"' -and $appContent -match 'const changedFiles = files\.filter\(\(file\) => !file\.reference\)' -and $appContent -match 'scope === "protected" && files\.length === 0' -and $indexContent -match 'class="preview-protected-rules" id="preview-protected-section" hidden' -and $stylesContent -match '--informational-foreground:\s*#c6d4ff' -and $stylesContent -match '\.preview-tree-file-icon\.protected,[\s\S]*color:\s*var\(--red\)' -and $stylesContent -match '\.preview-reference-status\s*\{[^}]*color:\s*var\(--gold\);[^}]*background:\s*var\(--gold-soft\)' -and $stylesContent -match '\.preview-reference-row\s*\{[^}]*grid-template-columns:\s*52px minmax\(0, 1fr\)' -and $stylesContent -match '\.preview-reference-row > code\s*\{[^}]*padding:\s*0 16px;[^}]*color:\s*var\(--informational-foreground\);[^}]*white-space:\s*pre-wrap'
    Add-TestResult -Name 'protected-preview-files' -Passed $protectedPreviewValid -Detail 'Preview renders exact rule-bearing protected instruction files as collapsed read-only references excluded from mutation accounting.'

    $noOpUpdateValid = $appContent -match 'function hasHostedTextChange\(' -and $appContent -match 'if \(hasHostedTextChange\(candidate, proposedText\)\) actions\.push\("update"\)' -and $appContent -match 'Current and proposed Hosted rule text are identical, so Update is unavailable\.' -and $appContent -match 'function isCurrentMappedNoChangeNoOp\(' -and $appContent -match 'function repairNoOpPlanMembership\(' -and $appContent -match 'changes\.inPlan === true && !canSelectCandidateForPlan' -and $appContent -match 'candidate-plan-unavailable'
    Add-TestResult -Name 'no-op-update-suppression' -Passed $noOpUpdateValid -Detail 'Current mapped No Change candidates omit no-op action and membership controls while preserving explicit promotion overrides.'

    $mobileUnsupportedValid = $indexContent -match 'class="unsupported-brand-lockup"[\s\S]*icons/codicons/sprite\.svg#codicon-json[\s\S]*class="unsupported-product-name">HOSTED COPILOT RULE MANAGER</p>' -and $indexContent -match 'Mobile devices are not supported' -and $indexContent -notmatch 'class="unsupported-mark"[^>]*>HR</span>' -and $appContent -match 'matchMedia\("\(max-width: 767\.98px\)"\)\.matches' -and $appContent -match 'userAgentData\?\.mobile' -and $appContent -match 'mobile-unsupported' -and $stylesContent -match '@media \(max-width: 767\.98px\)' -and $stylesContent -match '\.unsupported-brand-icon\s*\{[^}]*color:\s*#ffff00' -and $stylesContent -match 'html\.mobile-unsupported \.unsupported-device'
    Add-TestResult -Name 'mobile-unsupported-contract' -Passed $mobileUnsupportedValid -Detail 'Mobile detection replaces the Workbench with a laptop-or-desktop requirement.'

    $reuseSiteDirectory = Join-Path $tempRoot 'display-reuse-site'
    $null = New-Item -ItemType Directory -Path $reuseSiteDirectory -Force
    Copy-Item -LiteralPath $displayPath -Destination (Join-Path $reuseSiteDirectory 'workbench-display.json')
    Copy-Item -LiteralPath $ruleIssuesPath -Destination (Join-Path $reuseSiteDirectory 'workbench-rule-issues.json')
    $reuseStopwatch = [Diagnostics.Stopwatch]::StartNew()
    $reuseOutput = @(& pwsh -NoProfile -File $launcherPath -SiteDirectory $reuseSiteDirectory -EvaluatorCommand $metadataEvaluatorPath -SkipGitHubAuthorization -StageOnly -NoLaunch -OutputFormat Json 2>&1)
    $reuseExitCode = $LASTEXITCODE
    $reuseStopwatch.Stop()
    $reuseResult = if ($reuseExitCode -eq 0) { ($reuseOutput | Out-String) | ConvertFrom-Json } else { $null }

    $invalidForceOutput = @(& pwsh -NoProfile -File $launcherPath -SiteDirectory $reuseSiteDirectory -SkipGitHubAuthorization -StageOnly -NoLaunch -Force -OutputFormat Json 2>&1)
    $invalidForceExitCode = $LASTEXITCODE

    $mismatchedSiteDirectory = Join-Path $tempRoot 'display-mismatch-site'
    $null = New-Item -ItemType Directory -Path $mismatchedSiteDirectory -Force
    Copy-Item -LiteralPath $displayPath -Destination (Join-Path $mismatchedSiteDirectory 'workbench-display.json')
    $mismatchedRuleIssues = $ruleIssuesJson | ConvertFrom-Json
    $mismatchedRuleIssues.sourceFiles[0].contentSha256 = '0' * 64
    [IO.File]::WriteAllText((Join-Path $mismatchedSiteDirectory 'workbench-rule-issues.json'), (($mismatchedRuleIssues | ConvertTo-Json -Depth 30) + "`n"), [Text.UTF8Encoding]::new($false))
    $mismatchOutput = @(& pwsh -NoProfile -File $launcherPath -SiteDirectory $mismatchedSiteDirectory -EvaluatorCommand $metadataEvaluatorPath -SkipGitHubAuthorization -StageOnly -NoLaunch -OutputFormat Json 2>&1)
    $mismatchExitCode = $LASTEXITCODE

    $incompleteSiteDirectory = Join-Path $tempRoot 'display-incomplete-site'
    $null = New-Item -ItemType Directory -Path $incompleteSiteDirectory -Force
    Copy-Item -LiteralPath $displayPath -Destination (Join-Path $incompleteSiteDirectory 'workbench-display.json')
    $incompleteOutput = @(& pwsh -NoProfile -File $launcherPath -SiteDirectory $incompleteSiteDirectory -EvaluatorCommand $metadataEvaluatorPath -SkipGitHubAuthorization -StageOnly -NoLaunch -OutputFormat Json 2>&1)
    $incompleteExitCode = $LASTEXITCODE

    $assessmentLaunchValid = $launcherContent -match 'New-SourceInventory\.ps1' -and
        $launcherContent -match 'Invoke-SourceAssessment\.ps1' -and
        $launcherContent -match 'Invoke-AssessmentReconciliation\.ps1' -and
        $launcherContent -match 'Get-GuidanceCapacity\.ps1' -and
        $launcherContent -match 'PriorInventoryPaths = \$priorInventoryPaths\.ToArray\(\)' -and
        $launcherContent -match "AssessmentCacheDirectory = \(Join-Path \(\[Environment\]::GetFolderPath\('LocalApplicationData'\)\) 'hosted-workbench/assessment-cache'\)" -and
        $launcherContent -match 'CacheDirectory = \$resolvedAssessmentCacheDirectory' -and
        $launcherContent -match 'ResumeRunDirectory = \$resolvedAssessmentResumeDirectory' -and
        $launcherContent -match '\[switch\]\$Force' -and
        $launcherContent -match '\$assessmentParameters\.Force = \$true' -and
        $launcherContent -match '\$reconciliationParameters\.Force = \$true' -and
        $launcherContent -match 'Force requires Rebuild\.' -and
        $launcherContent -notmatch 'ReconciliationResumeDirectory' -and
        $launcherContent -notmatch 'Find-Automatic.*Recovery|RecoveryRunDirectories' -and
        $launcherContent -match '\[ValidateRange\(1, 8\)\]\s*\[int\]\$MaxParallelBatches = 3' -and
        $launcherContent -match 'MaxParallelBatches = \$MaxParallelBatches' -and
        $launcherContent -match "Write-ValidationSectionHeader -Title 'Source Assessment'" -and
        $launcherContent -match "Write-ValidationSectionHeader -Title 'Hosted Guidance Token Capacity'" -and
        $launcherContent -match "'Checking token usage and safety headroom'" -and
        $launcherContent -match "guidance files and \{1\} combined scopes fit within safety-adjusted token limits" -and
        $launcherContent -notmatch "Write-ValidationSectionHeader -Title 'Assessment Status'" -and
        $launcherContent -notmatch "Write-ValidationSectionHeader -Title 'Reconciliation Status'" -and
        $launcherContent -notmatch "-Status '(?:running|passed)' -Name 'source-assessment'" -and
        $launcherContent -match "-Status 'passed' -Name 'guidance-capacity'" -and
        $launcherContent -match '-Status ''passed'' -Name "source-collection/\$sourceDefinitionId"' -and
        $launcherContent -match 'ShowProgress = \$OutputFormat -eq ''Text''' -and
        $launcherContent -match '\$script:workbenchPhase = ''RULE ISSUE ADJUDICATION''' -and
        $launcherContent -match "Write-ValidationSectionHeader -Title 'Rule Issue Adjudication'" -and
        $launcherContent -match "Write-ValidationSectionHeader -Title 'Rule Issue Adjudication Summary'" -and
        $launcherContent -notmatch "-Name 'assessment-reconciliation/rule-issues'" -and
        $launcherContent -match "'Batches'.*componentCount.*cachedComponentCount.*evaluatedComponentCount" -and
        $launcherContent -match "'Elapsed'.*Format-ElapsedDuration.*ruleIssuesStopwatch" -and
        $launcherContent -match "Write-ValidationSectionHeader -Title 'Workbench UI Artifact Publication'" -and
        $launcherContent -match "'Artifacts', 2" -and
        $launcherContent -match "-Status 'running' -Name 'workbench/display'" -and
        $launcherContent -match "-Status 'passed' -Name 'workbench/display'.*Format-ElapsedDuration.*publicationStopwatch" -and
        [regex]::Matches($launcherContent, "Write-ValidationSectionHeader -Title 'Workbench Summary'").Count -eq 3 -and
        $launcherContent -notmatch "Write-ValidationSectionHeader -Title 'Summary'" -and
        $launcherContent -match "Write-Output ''\s+Write-Output 'Press Ctrl\+C to stop the Workbench\.'" -and
        $launcherContent -match '\$workbenchSummaryFields = \[ordered\]@' -and
        [regex]::Matches($launcherContent, 'Write-ValidationSummary -Fields \$workbenchSummaryFields').Count -eq 2 -and
        $launcherContent -match 'Mode = if \(\$StageOnly\) \{ ''STAGE ONLY'' \} else \{ ''SERVER'' \}' -and
        $launcherContent -match 'Server = if \(\$StageOnly\) \{ ''Not started'' \} else \{ "Running at \$url" \}' -and
        $launcherContent -notmatch "'Discovered Candidates' =|'AI-Evaluated Candidates' =|'Assessment Cache' =|'Reconciliation Cache' =|'Assessment Recovery' =" -and
        $launcherContent -notmatch '\$script:workbenchPhase = ''RULE ISSUES EXPORT''' -and
        $launcherContent -match '\$reconciledDisplayPath = Join-Path \$runDirectory ''workbench-display\.json''' -and
        $launcherContent -match 'Copy-FileAtomically -SourcePath \$reconciledDisplayPath -DestinationPath \$stagedDisplayPath' -and
        $launcherContent -notmatch 'OutputPath = \$stagedDisplayPath' -and
        $launcherContent -match '\[switch\]\$Rebuild' -and
        $launcherContent -match 'if \(-not \$Rebuild\)' -and
        $launcherContent -match 'Get-HostedWorkbenchGitHubContext -RepositoryRoot \$repositoryRoot -SkipGitHubAuthorization:\$SkipGitHubAuthorization' -and
        $launcherContent -match 'Staged Workbench display and Rule Issues source files do not match' -and
        $launcherContent -notmatch 'Get-WorkbenchInputFingerprint|REUSED_FRESH_DISPLAY|REFRESHED_CHANGED_INPUTS|stagedInputFingerprint' -and
        $launcherContent -match '''REBUILT_CURRENT_SOURCES''' -and
        $launcherContent -match '''REUSED_VALIDATED_DISPLAY''' -and
        $launcherContent -notmatch '\$DisplayPath|Remove-Item -LiteralPath \$stagedDisplayPath'
    $assessmentLaunchValid = $assessmentLaunchValid -and $launcherContent -match "SiteDirectory = \(Join-Path \(\[Environment\]::GetFolderPath\('LocalApplicationData'\)\) 'hosted-workbench/site'\)" -and $launcherContent -match "ReconciliationCacheDirectory = \(Join-Path \(\[Environment\]::GetFolderPath\('LocalApplicationData'\)\) 'hosted-workbench/reconciliation-cache'\)" -and $launcherContent -match 'CacheDirectory = \$resolvedReconciliationCacheDirectory'
    $assessmentLaunchValid = $assessmentLaunchValid -and
        $reuseExitCode -eq 0 -and
        [string]$reuseResult.displayBuildMode -ceq 'REUSED_VALIDATED_DISPLAY' -and
        [int]$reuseResult.discoveredCandidateCount -eq @($display.candidates).Count -and
        $reuseStopwatch.Elapsed.TotalSeconds -lt 30 -and
        $invalidForceExitCode -ne 0 -and
        ($invalidForceOutput | Out-String) -match 'Force requires Rebuild' -and
        $mismatchExitCode -ne 0 -and
        ($mismatchOutput | Out-String) -match 'display and Rule Issues source files do not match' -and
        $incompleteExitCode -ne 0 -and
        ($incompleteOutput | Out-String) -match 'Run Start-RuleWorkbench\.ps1 -Rebuild to create one'
    Add-TestResult -Name 'incremental-assessment-launch' -Passed $assessmentLaunchValid -Detail 'Ordinary launch reuses the staged display, Rebuild reuses exact semantic caches, and Rebuild with Force bypasses cache reads while preserving atomic publication.'
    $waitingPhraseStagingValid = $reuseExitCode -eq 0 -and
        [string]$reuseResult.displayBuildMode -ceq 'REUSED_VALIDATED_DISPLAY' -and
        (Test-Path -LiteralPath (Join-Path $reuseSiteDirectory 'assistance-waiting-phrases.json')) -and
        (Get-FileHash -LiteralPath (Join-Path $reuseSiteDirectory 'assistance-waiting-phrases.json')).Hash -eq (Get-FileHash -LiteralPath (Join-Path $workbenchRoot 'assistance-waiting-phrases.json')).Hash
    Add-TestResult -Name 'assistance-waiting-phrase-staging' -Passed $waitingPhraseStagingValid -Detail 'Ordinary source launch stages the exact waiting-phrase catalog while reusing the validated display without a semantic rebuild.'

    if (Test-ShouldRun -Name 'loopback-read-only-server') {
        $serverEntryPointContents = @($launcherContent, (Get-Content -LiteralPath $loopbackServerPath -Raw))
        $serverContractValid = $launcherContent -match '\[Net\.IPAddress\]::Loopback' -and $launcherContent -match '\$allowedHosts = @\("127\.0\.0\.1:\$Port", "localhost:\$Port"\)' -and $launcherContent -match "StatusCode 421 -StatusText 'Misdirected Request'" -and $launcherContent -match 'RandomNumberGenerator.*Fill' -and $launcherContent -match 'CryptographicOperations.*FixedTimeEquals' -and $launcherContent.Contains('$requestUri.AbsolutePath -eq ''/runtime-config''') -and $launcherContent.Contains('$requestUri.AbsolutePath -eq ''/shutdown''') -and $launcherContent.Contains('$requestUri.AbsolutePath -eq ''/reconcile-rule''') -and $launcherContent -match 'X-Workbench-Shutdown-Token' -and $launcherContent -match 'X-Workbench-Operation-Token' -and $appContent -match 'fetch\("/runtime-config", \{ cache: "no-store", signal \}\)' -and $launcherContent -match "script-src 'self'; style-src 'self'; font-src 'self'; connect-src 'self'" -and (@($serverEntryPointContents | Where-Object { -not $_.Contains('-ClientSocket $client.Client') -or -not $_.Contains('catch [OperationCanceledException]') }).Count -eq 0)
        Add-TestResult -Name 'loopback-read-only-server' -Passed $serverContractValid -Detail 'The loopback server remains repository-read-only, rejects misdirected requests, serves server-owned runtime authority, and exposes only token-authenticated shutdown and scoped relationship operations.'
    }

    if (Test-ShouldRun -Name 'internal-stage-status-boundary') {
        $internalStageStatusValid = @('collectionSucceeded', 'assessmentSucceeded', 'capacitySucceeded', 'reconciliationSucceeded', 'ruleIssuesSucceeded' | Where-Object { $launcherContent -notmatch "\`$$($_) = \`$\?" }).Count -eq 0 -and
            $launcherContent -notmatch "-Status '(?:running|passed)' -Name 'source-assessment'" -and
            $launcherContent -match "-Status 'running' -Name 'guidance-capacity'" -and
            $launcherContent -match "-Status 'passed' -Name 'guidance-capacity'" -and
            $launcherContent -notmatch "-Name 'assessment-reconciliation/rule-issues'" -and
            $launcherContent -notmatch "-Name 'assessment-reconciliation' -Detail 'Consolidating assessments into the Workbench display'"
        Add-TestResult -Name 'internal-stage-status-boundary' -Passed $internalStageStatusValid -Detail 'In-process PowerShell stages use immediate invocation status, generic executors own batch lifecycle rows, and launcher-owned aggregate phases avoid redundant parent wrappers.'
    }

    $behaviorManifestValid = $true
    if ([string]::IsNullOrWhiteSpace($Run) -or $Run -in @('browser-behavior-manifest', 'browser-playwright-journeys', 'browser-framework-coverage')) {
        $behaviorManifestContent = Get-Content -LiteralPath $behaviorManifestPath -Raw
        $behaviorManifest = $behaviorManifestContent | ConvertFrom-Json
        $behaviorIds = @($behaviorManifest.behaviors | ForEach-Object { [string]$_.id })
        $journeyPaths = @($behaviorManifest.behaviors | ForEach-Object { Join-Path $workbenchRegressionRoot ([string]$_.journey) } | Sort-Object -Unique)
        $implementationContractContent = Get-Content -LiteralPath $implementationContractPath -Raw
        $behaviorManifestValid = [bool]($behaviorManifestContent | Test-Json -SchemaFile $behaviorManifestSchemaPath -ErrorAction Stop) -and @($behaviorIds | Sort-Object -Unique).Count -eq $behaviorIds.Count -and @($journeyPaths | Where-Object { -not (Test-Path -LiteralPath $_ -PathType Leaf) }).Count -eq 0 -and @($behaviorIds | Where-Object { $implementationContractContent -notmatch [regex]::Escape($_) }).Count -eq 0
        if (Test-ShouldRun -Name 'browser-behavior-manifest') {
            Start-TestResult -Name 'browser-behavior-manifest'
            Add-TestResult -Name 'browser-behavior-manifest' -Passed $behaviorManifestValid -Detail "Mapped $($behaviorIds.Count) authoritative Workbench behavior IDs to $($journeyPaths.Count) Playwright journeys."
        }
        if (-not $behaviorManifestValid) {
            throw 'Workbench browser behavior manifest is invalid'
        }
    }
    if (Test-ShouldRun -Name 'relationship-check-cancellation') {
        Start-TestResult -Name 'relationship-check-cancellation'
        Import-Module (Join-Path $toolsRoot 'modules/workbench/SavedRuleEvaluation.psm1')
        $markerPath = Join-Path $tempRoot 'cancellation-worker.json'
        $cancelledOutputPath = Join-Path $tempRoot 'cancelled-output.json'
        $cancellationListener = [Net.Sockets.TcpListener]::new([Net.IPAddress]::Loopback, 0)
        $cancellationListener.Start()
        $cancellationPort = ([Net.IPEndPoint]$cancellationListener.LocalEndpoint).Port
        $disconnectJob = Start-Job -ScriptBlock {
            param($Port, $MarkerPath)
            $peer = [Net.Sockets.TcpClient]::new()
            try {
                $peer.Connect('127.0.0.1', $Port)
                $deadline = [DateTimeOffset]::UtcNow.AddSeconds(15)
                while (-not (Test-Path -LiteralPath $MarkerPath)) {
                    if ([DateTimeOffset]::UtcNow -gt $deadline) { throw 'Cancellation fixture did not start' }
                    Start-Sleep -Milliseconds 50
                }
            }
            finally { $peer.Dispose() }
        } -ArgumentList $cancellationPort, $markerPath
        $cancellationClient = $null
        try {
            $accept = $cancellationListener.AcceptTcpClientAsync()
            if (-not $accept.Wait(15000)) { throw 'Cancellation fixture did not connect' }
            $cancellationClient = $accept.GetAwaiter().GetResult()
            $cancelled = $false
            $timer = [Diagnostics.Stopwatch]::StartNew()
            try {
                Invoke-SavedRuleEvaluationProcess -ScriptPath (Join-Path $PSScriptRoot 'fixtures/cancellable-workbench-worker.ps1') -Parameters @{
                    MarkerPath = $markerPath; OutputPath = $cancelledOutputPath
                } -ClientSocket $cancellationClient.Client
            }
            catch [OperationCanceledException] { $cancelled = $true }
            $workerIds = Get-Content -LiteralPath $markerPath -Raw | ConvertFrom-Json
            $deadline = [DateTimeOffset]::UtcNow.AddSeconds(5)
            do {
                $remaining = @(Get-Process -Id $workerIds.worker, $workerIds.child -ErrorAction SilentlyContinue)
                if ($remaining.Count) { Start-Sleep -Milliseconds 50 }
            } while ($remaining.Count -and [DateTimeOffset]::UtcNow -lt $deadline)
            $cancellationPassed = $cancelled -and $timer.Elapsed.TotalSeconds -lt 15 -and $remaining.Count -eq 0 -and
                -not (Test-Path -LiteralPath $cancelledOutputPath)
            Add-TestResult -Name 'relationship-check-cancellation' -Passed $cancellationPassed -Detail 'Disconnecting the request cancels the native worker and its child process promptly, without publishing a result.'
        }
        finally {
            if ($null -ne $cancellationClient) { $cancellationClient.Dispose() }
            $cancellationListener.Stop()
            if ($disconnectJob.State -eq 'Running') { Stop-Job -Job $disconnectJob }
            Remove-Job -Job $disconnectJob -Force
            if (Test-Path -LiteralPath $markerPath) {
                $workerIds = Get-Content -LiteralPath $markerPath -Raw | ConvertFrom-Json
                foreach ($workerId in @($workerIds.worker, $workerIds.child)) {
                    $worker = Get-Process -Id $workerId -ErrorAction SilentlyContinue
                    if ($null -ne $worker) { $worker.Kill($true); $worker.WaitForExit(); $worker.Dispose() }
                }
            }
        }
    }
    if (Test-ShouldRun -Name 'relationship-check-responsiveness') {
        Start-TestResult -Name 'relationship-check-responsiveness' -RunningDetail 'Checking assets, authorization, evaluator serialization, cancellation, and shutdown during real HTTP validation'
        & pwsh -NoProfile -File (Join-Path $PSScriptRoot 'Test-WorkbenchServerResponsiveness.ps1') -DisplayPath $displayPath -RuleIssuesPath $ruleIssuesPath -TemporaryDirectory (Join-Path $tempRoot 'responsive-server') -Quiet:($OutputFormat -eq 'Json') -IndentLevel 1
        Add-TestResult -Name 'relationship-check-responsiveness' -Passed ($LASTEXITCODE -eq 0) -Detail 'Production and internal launchers serve GET/HEAD during held, production-shaped saved-rule requests while preserving serialized evaluators, validated responses, error reporting, disconnect cancellation, and shutdown cleanup.'
    }
    if (Test-ShouldRun -Name 'saved-rule-wording-review') {
        Start-TestResult -Name 'saved-rule-wording-review' -RunningDetail 'Checking independent wording acceptance, strict output, phase preservation, and registered prompt boundaries'
        Import-Module (Join-Path $toolsRoot 'modules/shared/HostedToolkit.Helpers.psm1')
        Import-Module (Join-Path $toolsRoot 'modules/reconciliation/RuleIssueAdjudication.psm1')
        $schemaRoot = Join-Path $repositoryRoot 'hosted_copilot/contracts/reconciliation'
        $baseline = 'Examples must use the documented arguments.'
        $text = $baseline + ' An unrelated non-rule sentence.'
        $key = 'maintainer:SOURCE-001:A1'
        $hash = 'a' * 64
        $component = [ordered]@{
            '$schema' = 'rule-issue-adjudication-input-v4.schema.json'; schemaVersion = 1; kind = 'hosted-rule-issue-adjudication-input'
            componentId = 'saved:WORDING-TEST-001'; evaluationPhase = 'scope'
            sourceFiles = @([ordered]@{ sourceDefinitionId = 'maintainer-proposals'; sourceId = 'SOURCE-001'; contentSha256 = $hash })
            rules = @([ordered]@{ id = 'WORDING-TEST-001'; status = 'proposed'; title = 'Wording fixture'; text = $text; contentSha256 = Get-Sha256 -Content $text; candidateKeys = @($key) })
            relationships = @()
            operations = @([ordered]@{ candidateKey = $key; ruleId = 'WORDING-TEST-001'; action = 'add'; proposedText = $text; retireHostedRuleIds = @() })
            editContext = [ordered]@{
                candidateKey = $key; baselineText = $baseline; baselineSha256 = Get-Sha256 -Content $baseline
                appendText = $text.Substring($baseline.Length); evaluationContextSha256 = $hash
                proposals = @([ordered]@{ candidateKey = $key; inPlan = $false; baselineText = $baseline; proposedText = $text; ruleTextSha256 = Get-Sha256 -Content $text; retireHostedRuleIds = @() })
            }
        } | ConvertTo-Json -Depth 100 | ConvertFrom-Json -Depth 100
        $draft = [ordered]@{
            '$schema' = 'rule-issue-adjudication-draft-v4.schema.json'; schemaVersion = 1; kind = 'hosted-rule-issue-adjudication-draft'
            componentId = $component.componentId; evaluationPhase = 'scope'; evaluationContextSha256 = $hash
            scopeReview = [ordered]@{
                disposition = 'within-scope'; ownerRuleId = $null; baselineQuote = $baseline; proposalQuote = $text
                rationale = 'The addition creates no distinct enforceable obligation.'
                wordingStatus = 'needs-review'; wordingRationale = 'Remove the unrelated non-rule sentence before acceptance.'
            }
            relationshipDecisions = @(); issues = @()
        } | ConvertTo-Json -Depth 100 | ConvertFrom-Json -Depth 100
        $inputSchema = Join-Path $schemaRoot 'rule-issue-adjudication-input-v4.schema.json'
        $draftSchema = Join-Path $schemaRoot 'rule-issue-adjudication-draft-v4.schema.json'
        $wordingContractPassed = ($component | ConvertTo-Json -Depth 100) | Test-Json -SchemaFile $inputSchema -ErrorAction Stop
        foreach ($status in @('acceptable', 'needs-review')) {
            $draft.scopeReview.wordingStatus = $status
            $wordingContractPassed = $wordingContractPassed -and (($draft | ConvertTo-Json -Depth 100) | Test-Json -SchemaFile $draftSchema -ErrorAction Stop)
            Test-RuleIssueAdjudicationDraft -Component $component -Draft $draft
        }
        $rejections = 0
        foreach ($case in @('missing-status', 'invalid-status', 'missing-rationale', 'empty-rationale', 'blank-rationale')) {
            $invalid = $draft | ConvertTo-Json -Depth 100 | ConvertFrom-Json -Depth 100
            switch ($case) {
                'missing-status' { $invalid.scopeReview.PSObject.Properties.Remove('wordingStatus') }
                'invalid-status' { $invalid.scopeReview.wordingStatus = 'unspecified' }
                'missing-rationale' { $invalid.scopeReview.PSObject.Properties.Remove('wordingRationale') }
                'empty-rationale' { $invalid.scopeReview.wordingRationale = '' }
                'blank-rationale' { $invalid.scopeReview.wordingRationale = ' ' }
            }
            try { Test-RuleIssueAdjudicationDraft -Component $component -Draft $invalid }
            catch {
                if ($_.Exception.Message -notlike '*explicit wording status and rationale*') { throw }
                $rejections++
            }
        }
        $component.evaluationPhase = 'issues'
        $component | Add-Member -NotePropertyName scopeReview -NotePropertyValue ($draft.scopeReview | ConvertTo-Json | ConvertFrom-Json)
        $component | Add-Member -NotePropertyName memberScopeReviews -NotePropertyValue @([pscustomobject]@{ candidateKey = $key; scopeReview = $component.scopeReview })
        $draft.evaluationPhase = 'issues'
        $wordingContractPassed = $wordingContractPassed -and (($component | ConvertTo-Json -Depth 100) | Test-Json -SchemaFile $inputSchema -ErrorAction Stop)
        Test-RuleIssueAdjudicationDraft -Component $component -Draft $draft
        foreach ($field in @('wordingStatus', 'wordingRationale')) {
            $invalid = $draft | ConvertTo-Json -Depth 100 | ConvertFrom-Json -Depth 100
            if ($field -ceq 'wordingStatus') { $invalid.scopeReview.wordingStatus = 'acceptable' }
            else { $invalid.scopeReview.wordingRationale = 'A different decision.' }
            try { Test-RuleIssueAdjudicationDraft -Component $component -Draft $invalid }
            catch {
                if ($_.Exception.Message -notlike '*changed the validated scope review*') { throw }
                $rejections++
            }
        }
        $authority = Get-Content -LiteralPath (Join-Path $schemaRoot 'rule-issue-adjudication-v4.json') -Raw | ConvertFrom-Json
        $prompts = @($authority.behaviorFiles | Where-Object { $_ -like '*/prompts/reconciliation/*.md' })
        $wordingContractPassed = $wordingContractPassed -and $prompts.Count -eq 2
        foreach ($relativePath in $prompts) {
            $content = Get-Content -LiteralPath (Join-Path $repositoryRoot $relativePath) -Raw
            $boundary = ($content -split '(?m)^## Boundaries\s*$', 2)[-1]
            foreach ($required in @('source', 'assessment', 'catalog', 'untrusted quoted data', 'prompt injection', 'tool requests', 'role changes', 'output-format changes', 'policy claims')) {
                $wordingContractPassed = $wordingContractPassed -and $content -match '(?m)^## Boundaries\s*$' -and $boundary.Contains($required, [StringComparison]::OrdinalIgnoreCase)
            }
        }
        $prompt = Get-Content -LiteralPath (Join-Path $toolsRoot 'prompts/reconciliation/RuleIssueAdjudication-v4.md') -Raw
        $wordingContractPassed = $wordingContractPassed -and $prompt.Contains('scopeReview.wordingStatus', [StringComparison]::Ordinal) -and
            $prompt.Contains('wordingRationale', [StringComparison]::Ordinal) -and $rejections -eq 7
        Add-TestResult -Name 'saved-rule-wording-review' -Passed $wordingContractPassed -Detail 'Within-scope wording may independently need correction; missing or invalid decisions and issue-phase rewrites are rejected. All registered evaluator prompts retain quoted-data injection boundaries.'
    }
    if (Test-ShouldRun -Name 'saved-rule-consolidation') {
        Start-TestResult -Name 'saved-rule-consolidation' -RunningDetail 'Checking intended target ownership, complete preservation, retirement boundaries, and extractive provenance'
        Import-Module (Join-Path $toolsRoot 'modules/shared/HostedToolkit.Helpers.psm1')
        Import-Module (Join-Path $toolsRoot 'modules/reconciliation/RuleIssueAdjudication.psm1')
        $baseline = 'Examples must remain functional and self-contained.'
        $proposal = $baseline + ' Secrets shoud use variables.'
        $peerText = 'Examples must not hard-code secrets; use input variables for secret values.'
        $merged = $baseline + ' Examples must not hard-code secrets; use input variables for secret values.'
        $target = 'maintainer:z-target:Z1'
        $peer = 'maintainer:a-peer:A1'
        $targetId = 'MERGE-TARGET-001'
        $peerId = 'MERGE-PEER-001'
        $hash = 'a' * 64
        $scope = [ordered]@{
            disposition = 'within-scope'; ownerRuleId = $null; baselineQuote = $peerText; proposalQuote = $peerText
            rationale = 'The unchanged comparison retains its original scope.'
            wordingStatus = 'acceptable'; wordingRationale = 'The comparison expresses a complete obligation.'
        }
        $component = [ordered]@{
            '$schema' = 'rule-issue-adjudication-input-v4.schema.json'; schemaVersion = 1; kind = 'hosted-rule-issue-adjudication-input'
            componentId = 'saved:consolidation'; evaluationPhase = 'issues'
            sourceFiles = @([ordered]@{ sourceDefinitionId = 'maintainer-proposals'; sourceId = 'SOURCE-001'; contentSha256 = $hash })
            rules = @(
                [ordered]@{ id = $targetId; status = 'active'; title = 'Target'; text = $baseline; contentSha256 = Get-Sha256 -Content $baseline; candidateKeys = @($target) }
                [ordered]@{ id = $peerId; status = 'active'; title = 'Comparison'; text = $peerText; contentSha256 = Get-Sha256 -Content $peerText; candidateKeys = @($peer) }
            )
            relationships = @([ordered]@{ id = 'edge:merge'; sourceRuleId = $targetId; relatedRuleId = $peerId; relationship = 'partial-overlap'; rationale = 'The proposed addition overlaps the comparison.'; candidateKey = $target })
            operations = @(
                [ordered]@{ candidateKey = $target; ruleId = $targetId; action = 'update'; proposedText = $proposal; retireHostedRuleIds = @() }
                [ordered]@{ candidateKey = $peer; ruleId = $peerId; action = 'no-change'; proposedText = $peerText; retireHostedRuleIds = @() }
            )
            editContext = [ordered]@{
                candidateKey = $peer; intendedCandidateKey = $target
                baselineText = $peerText; baselineSha256 = Get-Sha256 -Content $peerText
                appendText = ''; evaluationContextSha256 = $hash
                proposals = @(
                    [ordered]@{ candidateKey = $target; inPlan = $false; baselineText = $baseline; proposedText = $proposal; ruleTextSha256 = Get-Sha256 -Content $proposal; retireHostedRuleIds = @() }
                    [ordered]@{ candidateKey = $peer; inPlan = $false; baselineText = $peerText; proposedText = $peerText; ruleTextSha256 = Get-Sha256 -Content $peerText; retireHostedRuleIds = @() }
                )
            }
            scopeReview = $scope
            memberScopeReviews = @(
                [ordered]@{ candidateKey = $peer; scopeReview = $scope }
                [ordered]@{ candidateKey = $target; scopeReview = [ordered]@{
                    disposition = 'within-scope'; ownerRuleId = $null; baselineQuote = $baseline; proposalQuote = $proposal
                    rationale = 'The proposed combination keeps the intended target.'
                    wordingStatus = 'needs-review'; wordingRationale = 'Correct the spelling and preserve the stronger secret-handling requirement.'
                } }
            )
        } | ConvertTo-Json -Depth 100 | ConvertFrom-Json -Depth 100
        $component = & (Get-Module RuleIssueAdjudication) {
            param($inputComponent)
            New-SavedRuleAdjudicationPhaseInput -Component $inputComponent -Phase issues -Items @($inputComponent.relationships) -ScopeReview @($inputComponent.memberScopeReviews)
        } $component
        $draft = [ordered]@{
            '$schema' = 'rule-issue-adjudication-draft-v4.schema.json'; schemaVersion = 1; kind = 'hosted-rule-issue-adjudication-draft'
            componentId = $component.componentId; evaluationPhase = 'issues'; evaluationContextSha256 = $component.editContext.evaluationContextSha256
            scopeReview = $scope
            relationshipDecisions = @([ordered]@{
                relationshipId = 'edge:merge'; disposition = 'issue'; relationship = 'partial-overlap'
                rationale = 'The complete combined rule covers the existing requirement.'
                sourceQuote = $baseline; relatedQuote = $peerText
            })
            issues = @([ordered]@{
                classification = 'overlap'; anchorRuleId = $targetId; ruleIds = @($targetId, $peerId); relationshipIds = @('edge:merge')
                title = 'Combine the complete compatible obligations'; bannerTitle = 'Review the Complete Consolidation'
                bannerMessage = 'Accept corrected wording and the covered retirement together.'
                blocking = $false; assessmentSummary = 'The intended target retains its complete baseline and the comparison obligation.'
                ruleDispositions = @([ordered]@{ ruleId = $targetId; disposition = 'replace' }, [ordered]@{ ruleId = $peerId; disposition = 'retire' })
                wording = [ordered]@{ status = 'selected'; label = 'Suggested Consolidated Wording'; presentation = 'section'; text = $merged; sourceRuleId = $targetId }
                recommendedMaintainerAction = [ordered]@{
                    summary = 'Correct the intended combined rule and retire the fully covered comparison.'
                    operations = @([ordered]@{
                        candidateKey = $target; ruleId = $targetId; action = 'update'; textSource = 'suggestion'
                        proposedText = $merged; retireHostedRuleIds = @($peerId)
                        preservation = @(
                            [ordered]@{ ruleId = $targetId; sourceText = $proposal; mergedQuote = $merged; rationale = 'Retains the complete functional and self-contained baseline and corrects the intended secret-handling addition without weakening it.' }
                            [ordered]@{ ruleId = $peerId; sourceText = $peerText; mergedQuote = $peerText; rationale = 'Retains the prohibition on hard-coded secrets and the mandatory input-variable replacement.' }
                        )
                    })
                }
            })
        } | ConvertTo-Json -Depth 100 | ConvertFrom-Json -Depth 100
        $schemaRoot = Join-Path $repositoryRoot 'hosted_copilot/contracts/reconciliation'
        if (-not (($component | ConvertTo-Json -Depth 100) | Test-Json -SchemaFile (Join-Path $schemaRoot 'rule-issue-adjudication-input-v4.schema.json') -ErrorAction Stop) -or
            -not (($draft | ConvertTo-Json -Depth 100) | Test-Json -SchemaFile (Join-Path $schemaRoot 'rule-issue-adjudication-draft-v4.schema.json') -ErrorAction Stop)) { throw 'Consolidation fixtures must satisfy the production schemas' }
        Test-RuleIssueAdjudicationDraft -Component $component -Draft $draft
        $cases = @('missing-intent', 'foreign-intent', 'missing-preservation', 'missing-target', 'missing-peer', 'duplicate-preservation', 'truncated-source', 'invented-quote', 'blank-rationale', 'truncated-baseline', 'self-retirement', 'unknown-retirement', 'protected-retirement', 'unpaired-retirement', 'non-member-retirement', 'duplicate-retirement', 'extractive-invention', 'unchanged-target')
        $rejections = 0
        foreach ($case in $cases) {
            $inputCopy = $component | ConvertTo-Json -Depth 100 | ConvertFrom-Json -Depth 100
            $draftCopy = $draft | ConvertTo-Json -Depth 100 | ConvertFrom-Json -Depth 100
            $operation = $draftCopy.issues[0].recommendedMaintainerAction.operations[0]
            switch ($case) {
                'missing-intent' { $inputCopy.editContext.PSObject.Properties.Remove('intendedCandidateKey') }
                'foreign-intent' { $inputCopy.editContext.intendedCandidateKey = $peer }
                'missing-preservation' { $operation.PSObject.Properties.Remove('preservation') }
                'missing-target' { $operation.preservation = @($operation.preservation[1]) }
                'missing-peer' { $operation.preservation = @($operation.preservation[0]) }
                'duplicate-preservation' { $operation.preservation = @($operation.preservation[0], $operation.preservation[0]) }
                'truncated-source' { $operation.preservation[0].sourceText = $baseline }
                'invented-quote' { $operation.preservation[1].mergedQuote = 'This wording is absent.' }
                'blank-rationale' { $operation.preservation[1].rationale = ' ' }
                'truncated-baseline' { $operation.proposedText = $peerText; $draftCopy.issues[0].wording.text = $peerText }
                'self-retirement' { $operation.retireHostedRuleIds = @($targetId) }
                'unknown-retirement' { $operation.retireHostedRuleIds = @('FOREIGN-RULE-001') }
                'protected-retirement' { $inputCopy.rules[1].status = 'protected' }
                'unpaired-retirement' { $draftCopy.issues[0].ruleDispositions[1].disposition = 'keep' }
                'non-member-retirement' {
                    $inputCopy.rules += [pscustomobject]@{
                        id = 'FOREIGN-RULE-001'; status = 'active'; title = 'Foreign comparison'
                        text = $peerText; contentSha256 = Get-Sha256 -Content $peerText; candidateKeys = @()
                    }
                    $operation.retireHostedRuleIds = @('FOREIGN-RULE-001')
                    $operation.preservation[1].ruleId = 'FOREIGN-RULE-001'
                }
                'duplicate-retirement' { $operation.retireHostedRuleIds = @($peerId, $peerId) }
                'extractive-invention' { $operation.textSource = 'proposal' }
                'unchanged-target' {
                    @($inputCopy.editContext.proposals | Where-Object candidateKey -CEQ $target)[0].baselineText = $proposal
                    $inputCopy.memberScopeReviews[1].scopeReview.baselineQuote = $proposal
                }
            }
            try { Test-RuleIssueAdjudicationDraft -Component $inputCopy -Draft $draftCopy }
            catch {
                if ($_.Exception.Message -notmatch 'saved-edit|consolidation|adjudication can retire|appended consolidation') { throw }
                $rejections++
            }
        }
        Add-TestResult -Name 'saved-rule-consolidation' -Passed ($rejections -eq $cases.Count) -Detail "Corrected existing-target consolidation passed with a different lexical routing anchor; $rejections invalid ownership, preservation, retirement, and provenance cases were rejected."
    }
    if (Test-ShouldRun -Name 'rule-assistance') {
        Start-TestResult -Name 'rule-assistance' -RunningDetail 'Checking grounded assistance, strict CLI transport, input limits, and both HTTP lifecycle paths'
        & pwsh -NoProfile -File (Join-Path $PSScriptRoot 'Test-RuleAssistance.ps1') -DisplayPath $displayPath -RuleIssuesPath $ruleIssuesPath -TemporaryDirectory (Join-Path $tempRoot 'rule-assistance') -Quiet:($OutputFormat -eq 'Json') -IndentLevel 1
        if ($LASTEXITCODE -ne 0) { throw 'Rule assistance regression failed' }
        Add-TestResult -Name 'rule-assistance' -Passed $true -Detail 'Synthetic CLI and HTTP fixtures preserve complete catalog context, model isolation, strict output, bounded history, cancellation, responsiveness, and cleanup.'
    }
    if (Test-ShouldRun -Name 'saved-rule-evaluation') {
        Start-TestResult -Name 'saved-rule-evaluation' -RunningDetail 'Running the source-owned checker, grouped adjudicator, and deterministic saved-edit validation'
        Import-Module (Join-Path $toolsRoot 'modules/workbench/SavedRuleEvaluation.psm1')
        $savedRunner = Join-Path $toolsRoot 'internal/reconciliation/Invoke-SavedRuleEvaluation.ps1'
        $authorityParameters = @{
            RepositoryRoot = $repositoryRoot; DisplayPath = $displayPath; RuleIssuesPath = $ruleIssuesPath
            RelationshipEvaluatorScriptPath = $manualRelationshipEvaluatorPath
            AdjudicationEvaluatorScriptPath = $adjudicationEvaluatorPath
        }
        $editedCandidate = @($display.candidates | Where-Object { $_.recommendation.hostedId -ceq 'REVIEW-REPO-001' })[0]
        $editedKey = "$($editedCandidate.source.lane):$($editedCandidate.source.id):$($editedCandidate.assessment.id)"
        $proposals = @($display.candidates | ForEach-Object {
            [ordered]@{
                candidateKey = "$($_.source.lane):$($_.source.id):$($_.assessment.id)"
                sourceHash = [string]$_.source.contentSha256; action = 'no-change'; inPlan = $false
                proposedTextBase64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes([string]$_.recommendation.ruleText))
                retireHostedRuleIds = @()
            }
        })
        $request = [ordered]@{
            schemaVersion = 2; requestId = [Guid]::NewGuid().ToString('D')
            authoritySha256 = Get-SavedRuleAuthoritySha256 @authorityParameters
            candidateKey = $editedKey
            ruleTextBase64 = ''; sourceFiles = @($display.sourceFiles); proposals = $proposals; priorRelationships = @()
        }
        $savedRequestPath = Join-Path $tempRoot 'saved-request.json'
        $savedParameters = @{
            RepositoryRoot = $repositoryRoot; DisplayPath = $displayPath; RuleIssuesPath = $ruleIssuesPath
            RequestPath = $savedRequestPath; CacheDirectory = (Join-Path $tempRoot 'saved-rule-cache')
            EvaluatorScriptPath = $manualRelationshipEvaluatorPath; AdjudicationEvaluatorScriptPath = $adjudicationEvaluatorPath
        }
        [IO.File]::WriteAllText($savedRequestPath, '{"invalid":"synthetic launcher regression"}')
        $productionParameters = @{} + $savedParameters
        $productionParameters.EvaluatorScriptPath = ''
        $productionParameters.AdjudicationEvaluatorScriptPath = ''
        $productionParameters.OutputPath = Join-Path $tempRoot 'saved-native-invalid-result.json'
        $nativeDiagnostic = ''
        $nativeTimer = [Diagnostics.Stopwatch]::StartNew()
        try { Invoke-SavedRuleEvaluationProcess -ScriptPath $savedRunner -Parameters $productionParameters }
        catch { $nativeDiagnostic = [string]$_.Exception.Message }
        $nativeLaunchPassed = $nativeTimer.Elapsed.TotalSeconds -lt 10 -and $nativeDiagnostic -like '*Saved-rule request has an unexpected property set*' -and -not (Test-Path -LiteralPath $productionParameters.OutputPath)
        $null = $productionParameters.Remove('DisplayPath')
        $missingParameterDiagnostic = ''
        try { Invoke-SavedRuleEvaluationProcess -ScriptPath $savedRunner -Parameters $productionParameters }
        catch { $missingParameterDiagnostic = [string]$_.Exception.Message }
        $nativeLaunchPassed = $nativeLaunchPassed -and $missingParameterDiagnostic -like '*missing mandatory parameters*DisplayPath*'
        $unchangedCandidate = @($display.candidates | Where-Object { $_.catalogMapping.state -ceq 'active' } | Select-Object -First 1)[0]
        $unchangedKey = "$($unchangedCandidate.source.lane):$($unchangedCandidate.source.id):$($unchangedCandidate.assessment.id)"
        $unchangedId = [string]$unchangedCandidate.catalogMapping.hostedRuleId
        $unchangedText = [string]@($display.catalog.rules | Where-Object { $_.id -ceq $unchangedId })[0].text
        $unchangedParameters = @{} + $savedParameters
        $null = $unchangedParameters.Remove('EvaluatorScriptPath')
        $null = $unchangedParameters.Remove('AdjudicationEvaluatorScriptPath')
        $unchangedParameters.EvaluatorCommand = 'hosted-no-op-evaluator-must-not-run'
        $unchangedParameters.CacheDirectory = Join-Path $tempRoot 'saved-no-op-cold-cache'
        $unchangedParameters.OutputPath = Join-Path $tempRoot 'saved-no-op-result.json'
        $unchangedAuthorityParameters = @{} + $authorityParameters
        $unchangedAuthorityParameters.RelationshipEvaluatorScriptPath = ''
        $unchangedAuthorityParameters.AdjudicationEvaluatorScriptPath = ''
        $unchangedAuthorityParameters.EvaluatorCommand = $unchangedParameters.EvaluatorCommand
        $unchangedRequest = ($request | ConvertTo-Json -Depth 100) | ConvertFrom-Json -Depth 100
        $unchangedRequest.candidateKey = $unchangedKey
        $unchangedRequest.authoritySha256 = Get-SavedRuleAuthoritySha256 @unchangedAuthorityParameters
        $unchangedRequest.ruleTextBase64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($unchangedText))
        @($unchangedRequest.proposals | Where-Object { $_.candidateKey -ceq $unchangedKey })[0].proposedTextBase64 = $unchangedRequest.ruleTextBase64
        [IO.File]::WriteAllText($savedRequestPath, ($unchangedRequest | ConvertTo-Json -Depth 100))
        $null = Invoke-SavedRuleEvaluationProcess -ScriptPath $savedRunner -Parameters $unchangedParameters
        $unchangedResult = Get-Content -LiteralPath $unchangedParameters.OutputPath -Raw | ConvertFrom-Json -Depth 100 -DateKind String
        $baselineIssues = Get-Content -LiteralPath $ruleIssuesPath -Raw | ConvertFrom-Json -Depth 100 -DateKind String
        $noOpPassed = $unchangedResult.schemaVersion -eq 4 -and $unchangedResult.scopeReview.wordingStatus -ceq 'acceptable' -and
            $unchangedResult.evaluationMode -ceq 'unchanged' -and @($unchangedResult.assessments).Count -eq 0 -and
            @($unchangedResult.coveredProposals).Count -eq 1 -and $unchangedResult.coveredProposals[0].candidateKey -ceq $unchangedKey -and
            ($unchangedResult.ruleIssues | ConvertTo-Json -Depth 100 -Compress) -ceq ($baselineIssues | ConvertTo-Json -Depth 100 -Compress) -and
            -not (Test-Path -LiteralPath $unchangedParameters.CacheDirectory)
        $otherProposal = @($unchangedRequest.proposals | Where-Object {
            $key = $_.candidateKey
            $owner = @($display.candidates | Where-Object { "$($_.source.lane):$($_.source.id):$($_.assessment.id)" -ceq $key })[0]
            $id = if ($null -ne $owner.catalogMapping.hostedRuleId) { $owner.catalogMapping.hostedRuleId } else { $owner.recommendation.hostedId }
            $id -cne $unchangedId
        } | Select-Object -First 1)[0]
        $otherText = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($otherProposal.proposedTextBase64))
        $otherProposal.proposedTextBase64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($otherText + ' Another candidate has genuinely changed.'))
        [IO.File]::WriteAllText($savedRequestPath, ($unchangedRequest | ConvertTo-Json -Depth 100))
        $unchangedParameters.OutputPath = Join-Path $tempRoot 'saved-no-op-other-edit-result.json'
        $null = Invoke-SavedRuleEvaluationProcess -ScriptPath $savedRunner -Parameters $unchangedParameters
        $otherEditResult = Get-Content -LiteralPath $unchangedParameters.OutputPath -Raw | ConvertFrom-Json -Depth 100 -DateKind String
        $noOpPassed = $noOpPassed -and $otherEditResult.evaluationMode -ceq 'unchanged' -and
            @($otherEditResult.assessments).Count -eq 0 -and -not (Test-Path -LiteralPath $unchangedParameters.CacheDirectory)
        $noOpRejections = 0
        foreach ($invalidCase in @('authority', 'source', 'snapshot', 'ownership')) {
            $invalidNoOp = ($unchangedRequest | ConvertTo-Json -Depth 100) | ConvertFrom-Json -Depth 100
            switch ($invalidCase) {
                'authority' { $invalidNoOp.authoritySha256 = 'e' * 64; $expectedDiagnostic = '*authority changed*' }
                'source' { $invalidNoOp.sourceFiles[0].contentSha256 = 'e' * 64; $expectedDiagnostic = '*source snapshot*' }
                'snapshot' { $invalidNoOp.proposals = @($invalidNoOp.proposals | Where-Object candidateKey -CEQ $unchangedKey); $expectedDiagnostic = '*complete current proposal snapshot*' }
                'ownership' {
                    $invalidNoOp.priorRelationships = @([ordered]@{
                        candidateKey = $unchangedKey; sourceRuleId = $unchangedId; relatedRuleId = $unchangedId
                        relationship = 'partial-overlap'; rationale = 'Synthetic invalid no-op ownership.'
                    })
                    $expectedDiagnostic = '*provisional relationship has invalid ownership*'
                }
            }
            [IO.File]::WriteAllText($savedRequestPath, ($invalidNoOp | ConvertTo-Json -Depth 100))
            $unchangedParameters.OutputPath = Join-Path $tempRoot "saved-no-op-invalid-$invalidCase.json"
            try { $null = & $savedRunner @unchangedParameters }
            catch {
                if ($_.Exception.Message -notlike $expectedDiagnostic) { throw }
                if (-not (Test-Path -LiteralPath $unchangedParameters.OutputPath)) { $noOpRejections++ }
            }
        }
        $noOpPassed = $noOpPassed -and $noOpRejections -eq 4
        $savedResults = @()
        foreach ($suffix in @(' Additional maintainer wording.', ' Grouped review is required.', ' Scope routing is required.', ' Wording review fixture.')) {
            $text = [string]$editedCandidate.recommendation.ruleText + $suffix
            $encoded = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($text))
            $request.ruleTextBase64 = $encoded
            @($request.proposals | Where-Object { $_.candidateKey -ceq $editedKey })[0].proposedTextBase64 = $encoded
            [IO.File]::WriteAllText($savedRequestPath, ($request | ConvertTo-Json -Depth 100))
            $savedParameters.OutputPath = Join-Path $tempRoot ("saved-result-$($savedResults.Count).json")
            $null = & $savedRunner @savedParameters
            $savedResults += Get-Content -LiteralPath $savedParameters.OutputPath -Raw | ConvertFrom-Json -Depth 100
        }
        $retirementRequest = ($request | ConvertTo-Json -Depth 100) | ConvertFrom-Json -Depth 100
        $retirementProposal = @($retirementRequest.proposals | Where-Object candidateKey -CEQ $editedKey)[0]
        $retirementProposal.inPlan = $true
        $retirementProposal.action = 'add'
        $retirementProposal.proposedTextBase64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes(
            [string]$editedCandidate.recommendation.ruleText + ' The maintainer explicitly requests this combined requirement.'))
        $retirementRequest.ruleTextBase64 = $retirementProposal.proposedTextBase64
        $retirementProposal.retireHostedRuleIds = @('IMPL-PATCH-001')
        [IO.File]::WriteAllText($savedRequestPath, ($retirementRequest | ConvertTo-Json -Depth 100))
        $savedParameters.OutputPath = Join-Path $tempRoot 'saved-explicit-retirement.json'
        $null = & $savedRunner @savedParameters
        $retirementResult = Get-Content -LiteralPath $savedParameters.OutputPath -Raw | ConvertFrom-Json -Depth 100
        $retirementPassed = 'IMPL-PATCH-001' -cin @($retirementResult.affectedRuleIds) -and
            @($retirementResult.ruleIssues.issues).Count -eq 0 -and
            @($retirementResult.coveredProposals | Where-Object candidateKey -CEQ $editedKey)[0].retireHostedRuleIds[0] -ceq 'IMPL-PATCH-001'
        $advisoryDisplay = $display | ConvertTo-Json -Depth 100 | ConvertFrom-Json -Depth 100
        @($advisoryDisplay.candidates | Where-Object { $_.recommendation.hostedId -ceq 'REVIEW-REPO-001' })[0].recommendation.retireHostedRuleIds = @('IMPL-PATCH-001')
        $advisoryDisplayPath = Join-Path $tempRoot 'saved-advisory-retirement-display.json'
        [IO.File]::WriteAllText($advisoryDisplayPath, ($advisoryDisplay | ConvertTo-Json -Depth 100))
        $advisoryParameters = @{} + $savedParameters
        $advisoryParameters.DisplayPath = $advisoryDisplayPath
        $advisoryParameters.OutputPath = Join-Path $tempRoot 'saved-advisory-retirement.json'
        $advisoryAuthority = @{} + $authorityParameters
        $advisoryAuthority.DisplayPath = $advisoryDisplayPath
        $advisoryRequest = $retirementRequest | ConvertTo-Json -Depth 100 | ConvertFrom-Json -Depth 100
        @($advisoryRequest.proposals | Where-Object candidateKey -CEQ $editedKey)[0].inPlan = $false
        $advisoryRequest.authoritySha256 = Get-SavedRuleAuthoritySha256 @advisoryAuthority
        [IO.File]::WriteAllText($savedRequestPath, ($advisoryRequest | ConvertTo-Json -Depth 100))
        $null = & $savedRunner @advisoryParameters
        $advisoryResult = Get-Content -LiteralPath $advisoryParameters.OutputPath -Raw | ConvertFrom-Json -Depth 100
        $retirementPassed = $retirementPassed -and -not @($advisoryResult.coveredProposals | Where-Object candidateKey -CEQ $editedKey)[0].inPlan
        $retirementRejections = 0
        foreach ($case in @('unknown', 'protected', 'self', 'duplicate', 'not-in-plan', 'conflicting-mutation')) {
            $invalid = ($retirementRequest | ConvertTo-Json -Depth 100) | ConvertFrom-Json -Depth 100
            $root = @($invalid.proposals | Where-Object candidateKey -CEQ $editedKey)[0]
            switch ($case) {
                'unknown' { $root.retireHostedRuleIds = @('MISSING-RULE-001') }
                'protected' { $root.retireHostedRuleIds = @([string]$display.catalog.protectedRules[0].id) }
                'self' { $root.retireHostedRuleIds = @([string]$editedCandidate.recommendation.hostedId) }
                'duplicate' { $root.retireHostedRuleIds = @('IMPL-PATCH-001', 'IMPL-PATCH-001') }
                'not-in-plan' { $root.inPlan = $false }
                'conflicting-mutation' {
                    $peerCandidate = @($display.candidates | Where-Object { $_.catalogMapping.hostedRuleId -ceq 'IMPL-PATCH-001' })[0]
                    $peerKey = "$($peerCandidate.source.lane):$($peerCandidate.source.id):$($peerCandidate.assessment.id)"
                    $peerProposal = @($invalid.proposals | Where-Object candidateKey -CEQ $peerKey)[0]
                    $peerProposal.inPlan = $true
                    $peerProposal.action = 'update'
                }
            }
            [IO.File]::WriteAllText($savedRequestPath, ($invalid | ConvertTo-Json -Depth 100))
            $savedParameters.OutputPath = Join-Path $tempRoot "saved-invalid-retirement-$case.json"
            try { $null = & $savedRunner @savedParameters }
            catch {
                if ($_.Exception.Message -notmatch 'retirements require|duplicate retirements|conflicting planned mutation') { throw }
                if (-not (Test-Path -LiteralPath $savedParameters.OutputPath)) { $retirementRejections++ }
            }
        }
        $retirementPassed = $retirementPassed -and $retirementRejections -eq 6
        $stale = ($request | ConvertTo-Json -Depth 100) | ConvertFrom-Json -Depth 100
        $stale.sourceFiles[0].contentSha256 = 'e' * 64
        [IO.File]::WriteAllText($savedRequestPath, ($stale | ConvertTo-Json -Depth 100))
        $staleRejected = $false
        try { $null = & $savedRunner @savedParameters } catch { $staleRejected = $_.Exception.Message -like '*source snapshot*' }
        $editedId = if ($null -ne $editedCandidate.catalogMapping.hostedRuleId) { [string]$editedCandidate.catalogMapping.hostedRuleId } else { [string]$editedCandidate.recommendation.hostedId }
        $invalidOwnershipCases = @(
            @{ candidateKey = 'fixture:unknown:unknown'; sourceRuleId = $editedId; relatedRuleId = 'IMPL-PATCH-001' },
            @{ candidateKey = $editedKey; sourceRuleId = 'IMPL-PATCH-001'; relatedRuleId = $editedId },
            @{ candidateKey = $editedKey; sourceRuleId = $editedId; relatedRuleId = 'MISSING-RULE-001' },
            @{ candidateKey = $editedKey; sourceRuleId = $editedId; relatedRuleId = $editedId }
        )
        $ownershipRejections = 0
        foreach ($invalidEdge in $invalidOwnershipCases) {
            $invalidRequest = ($request | ConvertTo-Json -Depth 100) | ConvertFrom-Json -Depth 100
            $invalidRequest.priorRelationships = @([ordered]@{
                candidateKey = $invalidEdge.candidateKey; sourceRuleId = $invalidEdge.sourceRuleId
                relatedRuleId = $invalidEdge.relatedRuleId; relationship = 'partial-overlap'
                rationale = 'Synthetic invalid ownership regression.'
            })
            [IO.File]::WriteAllText($savedRequestPath, ($invalidRequest | ConvertTo-Json -Depth 100))
            $savedParameters.OutputPath = Join-Path $tempRoot ("saved-invalid-$ownershipRejections.json")
            $rejected = $false
            try { $null = & $savedRunner @savedParameters }
            catch {
                if ($_.Exception.Message -notlike '*provisional relationship has invalid ownership*') { throw }
                $rejected = $true
            }
            if ($rejected -and -not (Test-Path -LiteralPath $savedParameters.OutputPath)) { $ownershipRejections++ }
        }
        $selfCoverageCount = @($display.candidates | Where-Object {
            $id = if ($null -ne $_.catalogMapping.hostedRuleId) { [string]$_.catalogMapping.hostedRuleId } else { [string]$_.recommendation.hostedId }
            $id -cin @($_.recommendation.relatedHostedCoverage | ForEach-Object { [string]$_.hostedRuleId })
        }).Count
        $groupedOperations = @($savedResults[1].ruleIssues.issues[0].recommendedMaintainerAction.operations)
        $baselineRecommendationsValid = $groupedOperations.Count -gt 0 -and @($groupedOperations | Where-Object {
            $operation = $_
            $owner = @($display.candidates | Where-Object { "$($_.source.lane):$($_.source.id):$($_.assessment.id)" -ceq [string]$operation.candidateKey })
            $owner.Count -ne 1 -or [string]$operation.proposedText -cne [string]$owner[0].recommendation.ruleText
        }).Count -eq 0
        $savedPassed = $retirementPassed -and @($savedResults[0].ruleIssues.issues).Count -eq 0 -and
            @($savedResults | Where-Object { $_.schemaVersion -ne 4 -or @($_.assessments).Count -ne 1 -or $_.assessments[0].candidateKey -cne $editedKey -or $_.assessments[0].selectionFactors.severity -ne 5 -or $_.assessments[0].selectionRationale -cne 'The refreshed assessment evaluates the complete saved wording and its current source evidence.' }).Count -eq 0 -and
            @($savedResults[1].ruleIssues.issues).Count -gt 0 -and
            $baselineRecommendationsValid -and $editedId -cin @($savedResults[1].ruleIssues.issues[0].ruleIds) -and
            [string]$savedResults[2].scopeReview.disposition -ceq 'route-to-existing-rule' -and $staleRejected -and
            $savedResults[3].scopeReview.disposition -ceq 'within-scope' -and $savedResults[3].scopeReview.wordingStatus -ceq 'needs-review' -and
            $savedResults[3].scopeReview.wordingRationale -ceq 'The unrelated fixture sentence must be removed before accepting the wording.' -and
            @($savedResults[3].ruleIssues.issues).Count -eq 0 -and
            $selfCoverageCount -gt 0 -and $ownershipRejections -eq $invalidOwnershipCases.Count -and $nativeLaunchPassed -and $noOpPassed
        Add-TestResult -Name 'saved-rule-evaluation' -Passed $savedPassed -Detail 'Cold no-op requests retain baseline evidence without evaluation; genuine edits retain scope, wording, grouped adjudication, and native launch coverage. Explicit valid retirements are evaluated, baseline advisory retirements remain loadable without Plan membership, and six invalid or conflicting retirement requests are rejected alongside invalid authority, source, snapshot, and ownership.'
    }
    if ([string]::IsNullOrWhiteSpace($Run) -or $Run -in $serverTestNames) {
    $portProbe = [Net.Sockets.TcpListener]::new([Net.IPAddress]::Loopback, 0)
    $portProbe.Start()
    $shutdownPort = ([Net.IPEndPoint]$portProbe.LocalEndpoint).Port
    $portProbe.Stop()
    $shutdownSiteDirectory = Join-Path $tempRoot 'shutdown-site'
    $null = New-Item -ItemType Directory -Path $shutdownSiteDirectory -Force
    foreach ($assetName in @('index.html', 'app.js', 'assistance-waiting-phrases.json', 'llm-brands.json', 'hierarchical-view.js', 'statusbar.js', 'styles.css', 'favicon.svg')) {
        Copy-Item -LiteralPath (Join-Path $workbenchRoot $assetName) -Destination (Join-Path $shutdownSiteDirectory $assetName)
    }
    Copy-Item -LiteralPath (Join-Path $workbenchRoot 'icons') -Destination $shutdownSiteDirectory -Recurse
    Copy-Item -LiteralPath $displayPath -Destination (Join-Path $shutdownSiteDirectory 'workbench-display.json')
    Copy-Item -LiteralPath $ruleIssuesPath -Destination (Join-Path $shutdownSiteDirectory 'workbench-rule-issues.json')
    $shutdownToken = 'a' * 64
    $operationToken = 'b' * 64
    $shutdownConfig = [ordered]@{
        shutdownToken = $shutdownToken
        operationToken = $operationToken
        maintainerIdentity = [ordered]@{ status = 'unavailable'; login = $null; isCodeOwner = $false; reason = 'Fixture identity.' }
        targetRepository = [ordered]@{ status = 'unavailable'; repository = $null; branch = $null; commit = $null; upstreamRepository = $null; upstreamBranch = $null; aheadBy = $null; behindBy = $null; reason = 'Fixture target.' }
    } | ConvertTo-Json -Compress
    [IO.File]::WriteAllText((Join-Path $shutdownSiteDirectory 'shutdown-config.js'), "globalThis.__HOSTED_RULE_WORKBENCH__ = $shutdownConfig;`n", [Text.UTF8Encoding]::new($false))
    $serverJob = Start-Job -ScriptBlock {
        param($ServerPath, $SiteDirectory, $Port, $ShutdownToken, $OperationToken, $RepositoryRoot, $ManualRelationshipPath, $RelationshipEvaluatorScriptPath, $ManualRelationshipCacheDirectory, $AdjudicationEvaluatorScriptPath, $MetadataEvaluatorPath)
        & pwsh -NoProfile -File $ServerPath -SiteDirectory $SiteDirectory -Port $Port -ShutdownToken $ShutdownToken -OperationToken $OperationToken -RepositoryRoot $RepositoryRoot -ManualRelationshipPath $ManualRelationshipPath -ManualRelationshipCacheDirectory $ManualRelationshipCacheDirectory -RelationshipEvaluatorScriptPath $RelationshipEvaluatorScriptPath -AdjudicationEvaluatorScriptPath $AdjudicationEvaluatorScriptPath -EvaluatorCommand $MetadataEvaluatorPath -NoLaunch
    } -ArgumentList $loopbackServerPath, $shutdownSiteDirectory, $shutdownPort, $shutdownToken, $operationToken, $repositoryRoot, $manualRelationshipPath, $manualRelationshipEvaluatorPath, (Join-Path $tempRoot 'manual-relationship-cache'), $adjudicationEvaluatorPath, $metadataEvaluatorPath
    try {
        $shutdownUrl = "http://127.0.0.1:$shutdownPort"
        $deadline = [DateTimeOffset]::UtcNow.AddSeconds(30)
        $serverReady = $false
        while (-not $serverReady -and [DateTimeOffset]::UtcNow -lt $deadline) {
            try {
                $serverReady = (Invoke-WebRequest -Uri "$shutdownUrl/" -Method Get -SkipHttpErrorCheck).StatusCode -eq 200
            }
            catch { }
        }
        if (-not $serverReady) {
            $serverOutput = (Receive-Job -Job $serverJob -Keep | Out-String).Trim()
            throw "loopback test server did not become ready$(if ($serverOutput) { ": $serverOutput" })"
        }
        $stagedConfigPath = Join-Path $shutdownSiteDirectory 'shutdown-config.js'
        $stagedConfigContent = Get-Content -LiteralPath $stagedConfigPath -Raw
        $staleConfigContent = $stagedConfigContent.Replace($shutdownToken, ('c' * 64)).Replace($operationToken, ('d' * 64))
        [IO.File]::WriteAllText($stagedConfigPath, $staleConfigContent, [Text.UTF8Encoding]::new($false))
        $runtimeConfigResponse = Invoke-WebRequest -Uri "$shutdownUrl/runtime-config" -Method Get -SkipHttpErrorCheck
        $runtimeConfig = if ($runtimeConfigResponse.StatusCode -eq 200) { $runtimeConfigResponse.Content | ConvertFrom-Json -DateKind String } else { $null }
        $runtimeConfigValid = $null -ne $runtimeConfig -and
            [string]$runtimeConfig.shutdownToken -ceq $shutdownToken -and
            [string]$runtimeConfig.operationToken -ceq $operationToken -and
            [string]$runtimeConfig.shutdownToken -cne ('c' * 64) -and
            [string]$runtimeConfig.operationToken -cne ('d' * 64)
        if (Test-ShouldRun -Name 'server-owned-runtime-config') {
            Start-TestResult -Name 'server-owned-runtime-config'
            Add-TestResult -Name 'server-owned-runtime-config' -Passed $runtimeConfigValid -Detail 'The running server retains authoritative operation tokens even when another launch rewrites the staged config file.'
        }
        if (-not $runtimeConfigValid) {
            throw 'Loopback server runtime configuration did not preserve its launch authority'
        }
        if (Test-ShouldRun -Name 'loopback-host-validation') {
            Start-TestResult -Name 'loopback-host-validation'
            $misdirectedRequest = Invoke-WebRequest -Uri "$shutdownUrl/shutdown-config.js" -Headers @{ Host = 'attacker.example' } -SkipHttpErrorCheck
            $hostValidationValid = $misdirectedRequest.StatusCode -eq 421 -and $misdirectedRequest.Content -eq 'Misdirected Request'
            Add-TestResult -Name 'loopback-host-validation' -Passed $hostValidationValid -Detail 'An unrecognized Host cannot read staged Workbench files or the per-launch shutdown token through DNS rebinding.'
        }
        $nodeExecutable = (Get-Command node -ErrorAction Stop).Source
        $shutdownToken = [string]$runtimeConfig.shutdownToken
        $operationToken = [string]$runtimeConfig.operationToken
        if (Test-ShouldRun -Name 'authenticated-server-shutdown') {
            Start-TestResult -Name 'authenticated-server-shutdown'
            $unauthorizedShutdown = Invoke-WebRequest -Uri "$shutdownUrl/shutdown" -Method Post -SkipHttpErrorCheck
            $unauthorizedRelationship = Invoke-WebRequest -Uri "$shutdownUrl/reconcile-rule" -Method Post -ContentType 'application/json' -Body '{"payloadBase64":"e30="}' -SkipHttpErrorCheck
            $unrelatedPost = Invoke-WebRequest -Uri "$shutdownUrl/" -Method Post -Headers @{ 'X-Workbench-Shutdown-Token' = $shutdownToken } -SkipHttpErrorCheck
        }
        $playwrightResult = $null
        $layoutTestResult = $null
        if ([string]::IsNullOrWhiteSpace($Run) -or $Run -in @('browser-viewport-layout', 'browser-framework-coverage')) {
            if (Test-ShouldRun -Name 'browser-viewport-layout') { Start-TestResult -Name 'browser-viewport-layout' }
            $layoutTestOutput = @(& $nodeExecutable $layoutTestPath $shutdownUrl 2>&1)
            $layoutTestExitCode = $LASTEXITCODE
            $layoutTestResult = if ($layoutTestExitCode -eq 0) { ($layoutTestOutput | Out-String) | ConvertFrom-Json } else { $null }
            $layoutValid = $layoutTestExitCode -eq 0 -and $layoutTestResult.status -eq 'passed' -and $layoutTestResult.viewportCount -eq 9 -and $layoutTestResult.assertionCount -gt 0
            if (Test-ShouldRun -Name 'browser-viewport-layout') {
                Add-TestResult -Name 'browser-viewport-layout' -Passed $layoutValid -Detail $(if ($layoutTestExitCode -eq 0) { 'Browser geometry preserves mobile rejection and contained Candidate Details, Assessment Details, Plan, and Preview scrolling across every breakpoint boundary.' } else { ($layoutTestOutput | Out-String).Trim() })
            }
        }
        if ([string]::IsNullOrWhiteSpace($Run) -or $Run -in @('browser-playwright-journeys', 'browser-framework-coverage')) {
            if (Test-ShouldRun -Name 'browser-playwright-journeys') { Start-TestResult -Name 'browser-playwright-journeys' }
            $playwrightResultPath = Join-Path $tempRoot 'playwright-result.json'
            $playwrightArguments = @($playwrightRunnerPath, $shutdownUrl, '--result-file', $playwrightResultPath)
            if (-not $runAllJourneys) {
                foreach ($journeyName in $journeyNames) {
                    $playwrightArguments += @('--journey', $journeyName)
                }
            }
            if ($Headed) {
                $playwrightArguments += @('--headed', '--transition-delay', '1000')
            }
            if ($SlowMo -gt 0) {
                $playwrightArguments += @('--slow-mo', [string]$SlowMo)
            }
            if ($OutputFormat -eq 'Text') {
                $playwrightArguments += '--progress'
            }
            $selectedBehaviors = if ($runAllJourneys) {
                @($behaviorManifest.behaviors)
            }
            else {
                @($behaviorManifest.behaviors | Where-Object { [IO.Path]::GetFileNameWithoutExtension([IO.Path]::GetFileNameWithoutExtension([string]$_.journey)) -in $journeyNames })
            }
            $selectedJourneyCount = @($selectedBehaviors | ForEach-Object { [string]$_.journey } | Sort-Object -Unique).Count
            $playwrightOutput = @(& $nodeExecutable @playwrightArguments 2>&1 | ForEach-Object {
                if ($OutputFormat -eq 'Text') { Write-Host ([string]$_) }
                $_
            })
            $playwrightExitCode = $LASTEXITCODE
            $playwrightFailureLine = @($playwrightOutput | ForEach-Object { [string]$_ } | Where-Object { $_ -match '^Error:\s+' } | Select-Object -Last 1)
            $playwrightFailureDetail = if ($playwrightFailureLine.Count -gt 0) {
                $playwrightFailureLine[0] -replace '^Error:\s*', ''
            }
            else {
                "Playwright runner exited with code $playwrightExitCode; see the journey output above."
            }
            $playwrightResult = if ($playwrightExitCode -eq 0 -and (Test-Path -LiteralPath $playwrightResultPath -PathType Leaf)) { Get-Content -LiteralPath $playwrightResultPath -Raw | ConvertFrom-Json } else { $null }
            $selectedBehaviorIds = @($selectedBehaviors | ForEach-Object { [string]$_.id } | Sort-Object)
            $executedBehaviorIds = if ($null -ne $playwrightResult) {
                @($playwrightResult.executedBehaviorIds | ForEach-Object { [string]$_ } | Sort-Object)
            }
            else {
                @()
            }
            $behaviorExecutionValid = (@($selectedBehaviorIds) -join [char]0) -ceq (@($executedBehaviorIds) -join [char]0)
            $expectedPlaywrightMode = if ($Headed) { 'headed' } else { 'headless' }
            $playwrightValid = $playwrightExitCode -eq 0 -and $playwrightResult.status -eq 'passed' -and $playwrightResult.harness -eq 'playwright' -and $playwrightResult.mode -eq $expectedPlaywrightMode -and $playwrightResult.journeyCount -eq $selectedJourneyCount -and $playwrightResult.behaviorCount -eq $selectedBehaviors.Count -and $behaviorExecutionValid -and $playwrightResult.assertionCount -gt 0
            if ($runAllJourneys) {
                $playwrightValid = $playwrightValid -and $playwrightResult.viewportAssertionCount -gt 0 -and $playwrightResult.viewportCount -eq 9 -and $playwrightResult.shutdownVerified
            }
            if (Test-ShouldRun -Name 'browser-playwright-journeys') {
                Add-TestResult -Name 'browser-playwright-journeys' -Passed $playwrightValid -Detail $(if ($playwrightExitCode -eq 0) { "Passed $($playwrightResult.assertionCount) assertions across $($playwrightResult.journeyCount) Playwright journeys covering $($playwrightResult.behaviorCount) executed behavior IDs." } else { $playwrightFailureDetail })
            }
        }
        if (Test-ShouldRun -Name 'browser-framework-coverage') {
            $browserCoverageValid = $playwrightValid -and $layoutValid -and $null -ne $playwrightResult -and $null -ne $layoutTestResult -and $playwrightResult.viewportCount -eq $layoutTestResult.viewportCount -and $playwrightResult.viewportAssertionCount -eq $layoutTestResult.assertionCount
            $browserCoverageDetail = if ($browserCoverageValid) {
                "Playwright and Puppeteer each passed $($layoutTestResult.assertionCount) current-behavior assertions across $($layoutTestResult.viewportCount) viewport boundaries."
            }
            else {
                'Playwright and Puppeteer coverage could not be matched because one or both prerequisite browser suites failed.'
            }
            Add-TestResult -Name 'browser-framework-coverage' -Passed $browserCoverageValid -Detail $browserCoverageDetail
        }
        $uiShutdownVerified = $null -ne $playwrightResult -and $playwrightResult.shutdownVerified
        if ($uiShutdownVerified) {
            $completedJob = Wait-Job -Job $serverJob -Timeout 10
            $shutdownComplete = $null -ne $completedJob -and $serverJob.State -eq 'Completed'
        }
        else {
            $authorizedShutdown = Invoke-WebRequest -Uri "$shutdownUrl/shutdown" -Method Post -Headers @{ 'X-Workbench-Shutdown-Token' = $shutdownToken } -SkipHttpErrorCheck
            $completedJob = Wait-Job -Job $serverJob -Timeout 10
            $shutdownComplete = $authorizedShutdown.StatusCode -eq 200 -and $null -ne $completedJob -and $serverJob.State -eq 'Completed'
        }
        if (Test-ShouldRun -Name 'authenticated-server-shutdown') {
            $shutdownLifecycleValid = $unauthorizedShutdown.StatusCode -eq 403 -and $unauthorizedRelationship.StatusCode -eq 403 -and $unrelatedPost.StatusCode -eq 405 -and $shutdownComplete
            Add-TestResult -Name 'authenticated-server-shutdown' -Passed $shutdownLifecycleValid -Detail 'Per-launch tokens protect shutdown and scoped relationship operations; unauthorized and unrelated POST requests remain rejected.'
        }
        elseif (-not $shutdownComplete) {
            throw 'Focused Workbench validation could not stop its owned server cleanly'
        }
    }
    finally {
        if ($serverJob.State -notin @('Completed', 'Failed', 'Stopped')) {
            Stop-Job -Job $serverJob
        }
        Remove-Job -Job $serverJob -Force
    }
    }

    if (Test-ShouldRun -Name 'repository-staging-rejected') {
        $repositorySiteDirectory = Join-Path $repositoryRoot 'hosted_copilot/workbench/staged-test'
        Start-TestResult -Name 'repository-staging-rejected'
        $null = @(& pwsh -NoProfile -File $launcherPath -SiteDirectory $repositorySiteDirectory -StageOnly -NoLaunch -OutputFormat Json 2>&1)
        $repositoryStagingRejected = $LASTEXITCODE -ne 0 -and -not (Test-Path -LiteralPath $repositorySiteDirectory)
        Add-TestResult -Name 'repository-staging-rejected' -Passed $repositoryStagingRejected -Detail 'The launcher rejects generated staging output inside the source repository.'
    }
    }
}
catch {
    if (-not $failureAlreadyReported) {
        $issues.Add($_.Exception.Message)
    }
    if ($OutputFormat -eq 'Text' -and -not $failureAlreadyReported) {
        Write-Host (Format-ValidationStatusLine -Status 'failed' -Name 'workbench-test-run' -Detail $_.Exception.Message)
    }
}
finally {
    Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
}

$result = [ordered]@{
    status = if ($issues.Count -eq 0) { 'passed' } else { 'failed' }
    testCount = $results.Count
    passedCount = @($results | Where-Object status -eq 'passed').Count
    failedCount = @($results | Where-Object status -eq 'failed').Count
    issueCount = $issues.Count
    tests = $results.ToArray()
    issues = $issues.ToArray()
    dependencyAudit = [ordered]@{
        threshold = 'low'
        counts = $dependencyAuditCounts
        findings = $dependencyAuditFindings.ToArray()
        error = $dependencyAuditError
        inconclusive = $dependencyAuditInconclusive
        continuedAfterFailure = $dependencyAuditContinuation
        remediationApplied = $npmFixApplied
        remediationChanges = $npmFixChanges.ToArray()
        requiresBreakingFix = $npmFixRequiresBreaking
        installationBlocked = -not $npmFixApplied -and ($dependencyAuditFindings.Count -gt 0 -or $null -ne $dependencyAuditError)
    }
}

if ($OutputFormat -eq 'Json') {
    $result | ConvertTo-Json -Depth 8
}
else {
    Write-ValidationSectionHeader -Title 'Hosted Rule Workbench test summary'
    Write-ValidationSummary -Fields ([ordered]@{
        Status = $result.status.ToUpperInvariant()
        Tests = $result.testCount
        Passed = $result.passedCount
        Failed = $result.failedCount
    })
    if ($npmFixApplied) {
        Write-ValidationSectionHeader -Title 'Dependency remediation'
        Write-ValidationSummary -Fields ([ordered]@{
            Status = 'APPLIED'
            Audit = 'PASSED'
            Changes = $npmFixChanges.Count
        })
        foreach ($change in $npmFixChanges) {
            Write-Output "  - $change"
        }
    }
    elseif ($dependencyAuditFindings.Count -gt 0) {
        Write-ValidationSectionHeader -Title 'Dependency security'
        Write-ValidationSummary -Fields ([ordered]@{
            Threshold = 'LOW'
            Critical = $dependencyAuditCounts.critical
            High = $dependencyAuditCounts.high
            Installation = 'BLOCKED'
            FunctionalTests = if ($dependencyAuditContinuation) { 'CONTINUED (UNVERIFIED)' } else { 'BLOCKED' }
        })
        Write-ValidationSectionHeader -Title 'Vulnerabilities'
        foreach ($finding in $dependencyAuditFindings) {
            Write-ValidationSummary -Fields ([ordered]@{
                Package = $finding.package
                Severity = $finding.severity
                Advisory = $finding.advisory
                Affected = $finding.affectedRange
                Dependency = $finding.dependencyPath
                Fix = $finding.remediation
            })
            Write-Output ''
        }
        Write-ValidationSectionHeader -Title 'Action required'
        Write-Output '  1. Run: pwsh -NoProfile -File ./hosted_copilot/tools/tests/Test-RuleWorkbench.ps1 -FixNpmAudit'
        Write-Output '  2. Review the resulting package.json and package-lock.json diff.'
        Write-Output '  3. If only a breaking fix remains, review it before adding -AllowBreakingNpmFix.'
        Write-Output '  4. Complete validation remains blocked until the staged graph passes audit.'
    }
    elseif ($dependencyAuditInconclusive) {
        Write-ValidationSectionHeader -Title 'Dependency security'
        Write-ValidationSummary -Fields ([ordered]@{
            Threshold = 'LOW'
            Audit = 'INCONCLUSIVE'
            Installation = 'BLOCKED'
            FunctionalTests = 'CONTINUED'
            Error = $dependencyAuditError
        })
    }
    elseif ($null -ne $dependencyAuditError) {
        Write-ValidationSectionHeader -Title 'Dependency security'
        Write-ValidationSummary -Fields ([ordered]@{
            Threshold = 'LOW'
            Audit = 'FAILED'
            Installation = 'BLOCKED'
            Error = $dependencyAuditError
        })
    }
    if ($issues.Count -gt 0) {
        Write-ValidationSectionHeader -Title 'Failures'
        foreach ($issue in $issues) {
            Write-Output "  - $issue"
        }
    }
    Complete-ValidationTextOutput
}

if ($result.status -eq 'failed') {
    exit 1
}
