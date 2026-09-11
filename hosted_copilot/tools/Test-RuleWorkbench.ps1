[CmdletBinding()]
param(
    [string]$Run,

    [ValidateSet('Text', 'Json')]
    [string]$OutputFormat = 'Text'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$validationOutputModulePath = Join-Path $PSScriptRoot '../../tools/ValidationOutput.psm1'
Import-Module -Name $validationOutputModulePath -Force

$repositoryRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
$workbenchRoot = Join-Path $PSScriptRoot '../workbench'
$iconRoot = Join-Path $workbenchRoot 'icons'
$codiconRoot = Join-Path $iconRoot 'codicons'
$octiconRoot = Join-Path $iconRoot 'octicons'
$iconGeneratorPath = Join-Path $PSScriptRoot 'New-WorkbenchCodiconSprite.ps1'
$octiconGeneratorPath = Join-Path $PSScriptRoot 'New-WorkbenchOcticonSprite.ps1'
$iconPreviewPath = Join-Path $PSScriptRoot 'WorkbenchIconPreview.ps1'
$iconPreviewRendererPath = Join-Path $PSScriptRoot 'Render-WorkbenchIconPreview.cjs'
$launcherPath = Join-Path $PSScriptRoot 'Start-RuleWorkbench.ps1'
$workbenchRegressionRoot = Join-Path $PSScriptRoot '../regression/workbench'
$behaviorManifestPath = Join-Path $workbenchRegressionRoot 'behavior-manifest.json'
$behaviorManifestSchemaPath = Join-Path $workbenchRegressionRoot 'behavior-manifest.schema.json'
$playwrightRunnerPath = Join-Path $workbenchRegressionRoot 'playwright/run.cjs'
$layoutTestPath = Join-Path $workbenchRegressionRoot 'puppeteer/Test-RuleWorkbenchLayout.cjs'
$headedPlaybackPath = Join-Path $PSScriptRoot 'Test-RuleWorkbenchHeaded.ps1'
$implementationContractPath = Join-Path $PSScriptRoot '../docs/HOSTED_COPILOT_CODE_REVIEW_IMPLEMENTATION.md'
$nodePackageManifestPath = Join-Path $PSScriptRoot 'package.json'
$nodePackageLockPath = Join-Path $PSScriptRoot 'package-lock.json'
$bundleSchemaPath = Join-Path $PSScriptRoot '../copilot-rule-catalog/rule-intake-review.schema.json'
$results = New-Object 'System.Collections.Generic.List[object]'
$issues = New-Object 'System.Collections.Generic.List[string]'
$testStartTimes = @{}
$tempRoot = Join-Path ([IO.Path]::GetTempPath()) ("hosted-rule-workbench-test-" + [guid]::NewGuid().ToString('N'))
$supportedFocusedRuns = @('loopback-host-validation', 'browser-behavior-manifest', 'browser-playwright-journeys', 'browser-viewport-layout', 'browser-framework-coverage', 'authenticated-server-shutdown')

function Test-ShouldRun {
    param([Parameter(Mandatory = $true)][string]$Name)

    return [string]::IsNullOrWhiteSpace($Run) -or $Run -eq $Name
}

function Start-TestResult {
    param(
        [Parameter(Mandatory = $true)][string]$Name
    )

    $testStartTimes[$Name] = Get-Date
    if ($OutputFormat -eq 'Text') {
        Write-Host (Format-ValidationStatusLine -Status 'running' -Name $Name -Detail 'IN PROGRESS')
    }
}

function Add-TestResult {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][bool]$Passed,
        [Parameter(Mandatory = $true)][string]$Detail
    )

    $durationSeconds = 0
    if ($testStartTimes.ContainsKey($Name)) {
        $durationSeconds = [Math]::Round(((Get-Date) - $testStartTimes[$Name]).TotalSeconds, 2)
        $testStartTimes.Remove($Name)
    }
    $status = if ($Passed) { 'passed' } else { 'failed' }
    $results.Add([pscustomobject]@{
        name = $Name
        status = $status
        detail = $Detail
    })
    if ($OutputFormat -eq 'Text') {
        Write-Host (Format-ValidationStatusLine -Status $status -Name $Name -Detail ("{0}s" -f $durationSeconds))
    }
    if (-not $Passed) {
        $issues.Add("$Name`: $Detail")
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
    if (-not [string]::IsNullOrWhiteSpace($Run) -and $Run -notin $supportedFocusedRuns) {
        $supportedRunList = ($supportedFocusedRuns | ForEach-Object { "      - '$_'" }) -join "`n"
        Add-TestResult -Name 'run-selection' -Passed $false -Detail "Requested Workbench test suite '$Run' is not supported.`n`n    SUPPORTED SUITES:`n`n$supportedRunList"
    }
    else {
    New-Item -ItemType Directory -Path $tempRoot -Force | Out-Null
    $nodePackageConfig = Get-Content -LiteralPath $nodePackageManifestPath -Raw | ConvertFrom-Json
    $nodeLockConfig = Get-Content -LiteralPath $nodePackageLockPath -Raw | ConvertFrom-Json -AsHashtable
    $directDependencies = @($nodePackageConfig.devDependencies.PSObject.Properties)
    $lockIntegrityValid = $nodeLockConfig['lockfileVersion'] -eq 3 -and $directDependencies.Count -gt 0
    foreach ($dependency in $directDependencies) {
        $lockedVersion = [string]$nodeLockConfig['packages']['']['devDependencies'][$dependency.Name]
        $lockedPackage = $nodeLockConfig['packages']["node_modules/$($dependency.Name)"]
        $lockIntegrityValid = $lockIntegrityValid -and $lockedVersion -eq [string]$dependency.Value -and -not [string]::IsNullOrWhiteSpace([string]$lockedPackage['integrity'])
    }
    if (-not $lockIntegrityValid) {
        throw 'Node validation dependencies are not fully covered by the versioned integrity lock'
    }
    if ([string]::IsNullOrWhiteSpace($Run)) {
        $npmCommandName = if ($IsWindows) { 'npm.cmd' } else { 'npm' }
        $npmCommand = Get-Command $npmCommandName -ErrorAction Stop
        Start-TestResult -Name 'locked-browser-dependencies'
        $dependencyOutput = @(& $npmCommand.Source ci --prefix $PSScriptRoot --no-audit --no-fund 2>&1)
        $dependencyExitCode = $LASTEXITCODE
        $lockedDependencyValid = $dependencyExitCode -eq 0 -and (Test-Path -LiteralPath $nodePackageLockPath -PathType Leaf) -and (Test-Path -LiteralPath (Join-Path $PSScriptRoot 'node_modules/puppeteer/package.json') -PathType Leaf) -and (Test-Path -LiteralPath (Join-Path $PSScriptRoot 'node_modules/@playwright/test/package.json') -PathType Leaf)
        Add-TestResult -Name 'locked-browser-dependencies' -Passed $lockedDependencyValid -Detail $(if ($lockedDependencyValid) { "Installed integrity-locked Playwright $($nodePackageConfig.devDependencies.'@playwright/test') and Puppeteer $($nodePackageConfig.devDependencies.puppeteer) browser test graphs." } else { ($dependencyOutput | Out-String).Trim() })
        if (-not $lockedDependencyValid) {
            throw 'locked browser validation dependencies could not be installed'
        }
    }
    else {
        $requiredBrowserPackages = if ($Run -eq 'browser-playwright-journeys') {
            @('@playwright/test', 'puppeteer')
        }
        elseif ($Run -in @('browser-viewport-layout', 'browser-framework-coverage')) {
            @('puppeteer')
        }
        else {
            @()
        }
        foreach ($packageName in $requiredBrowserPackages) {
            $installedPackagePath = Join-Path $PSScriptRoot "node_modules/$packageName/package.json"
            if (-not (Test-Path -LiteralPath $installedPackagePath -PathType Leaf)) {
                throw "Focused browser validation requires installed package '$packageName'; run the complete Workbench suite once to install locked dependencies"
            }
            $installedPackage = Get-Content -LiteralPath $installedPackagePath -Raw | ConvertFrom-Json
            if ([string]$installedPackage.version -ne [string]$nodePackageConfig.devDependencies.$packageName) {
                throw "Focused browser validation requires locked $packageName version $($nodePackageConfig.devDependencies.$packageName), found $($installedPackage.version)"
            }
        }
    }
    $bundlePath = Join-Path $tempRoot 'rule-intake-review.json'
    $capacityReports = @(
        New-CapacityReport -Name 'repository' -Kind 'file'
        New-CapacityReport -Name 'go' -Kind 'file'
        New-CapacityReport -Name 'test' -Kind 'file'
        New-CapacityReport -Name 'documentation' -Kind 'file'
        New-CapacityReport -Name 'skill' -Kind 'file'
        New-CapacityReport -Name 'go-combined' -Kind 'combined'
        New-CapacityReport -Name 'test-combined' -Kind 'combined'
        New-CapacityReport -Name 'documentation-combined' -Kind 'combined'
    )
    $bundle = [ordered]@{
        '$schema' = 'rule-intake-review.schema.json'
        schemaVersion = 3
        generatedAt = '2026-09-03T00:00:00Z'
        readOnly = $true
        refreshMode = 'regenerate-read-only-bundle'
        snapshots = [ordered]@{
            hostedCatalogSha256 = 'a' * 64
            intakeLedgerSha256 = 'b' * 64
            upstream = [ordered]@{ repository = 'hashicorp/terraform-provider-azurerm'; baselineCommit = '1' * 40; currentRef = 'main'; currentCommit = '2' * 40 }
            interactive = [ordered]@{ catalogPath = 'tools/interactive-rule-catalog/rule-catalog.json'; previousCatalogSha256 = 'c' * 64; currentCatalogSha256 = 'c' * 64; catalogChanged = $false }
            maintainer = [ordered]@{ directoryPath = 'hosted_copilot/copilot-rule-catalog/maintainer-rules'; sourceSha256 = 'e' * 64 }
        }
        summary = [ordered]@{
            upstreamSourceCount = 0
            changedUpstreamCount = 0
            interactiveRuleCount = 1
            interactiveReviewCount = 1
            interactiveCurrentCount = 0
            interactiveStateCounts = [ordered]@{ new = 1; changed = 0; retired = 0; deferred = 0; current = 0 }
            maintainerRuleCount = 0
            maintainerReviewCount = 0
            maintainerCurrentCount = 0
            maintainerStateCounts = [ordered]@{ new = 0; changed = 0; retired = 0; current = 0 }
        }
        guidanceCapacity = [ordered]@{
            status = 'passed'
            estimator = 'character-quarter-estimate-25pct-v1'
            safetyMarginPercent = 25
            reportCount = 8
            reports = $capacityReports
        }
        hostedRules = @(
            [ordered]@{ id = 'IMPL-PATCH-001'; status = 'active'; text = 'If PATCH preserves omitted properties, removal must send an explicit clearing value.'; placements = @([ordered]@{ surfaceId = 'implementation'; sectionHeading = 'Azure API Semantics' }) },
            [ordered]@{ id = 'DOCS-IMP-002'; status = 'active'; text = 'Resource documentation must include a shell-fenced Terraform import command.'; placements = @([ordered]@{ surfaceId = 'documentation'; sectionHeading = 'Examples And Imports' }) }
        )
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
    $maintainerAssessment = $bundle.interactiveCandidates[0].assessments[0] | ConvertTo-Json -Depth 20 | ConvertFrom-Json
    $maintainerAssessment.assessmentId = 'DOCS-MAINT-001'
    $maintainerAssessment.title = 'Maintainer proposal'
    $maintainerAssessment.sourceContentSha256 = 'f' * 64
    $maintainerAssessment.hostedCategory = 'documentation'
    $maintainerAssessment.proposedHostedRuleId = 'DOCS-CAND-001'
    $maintainerAssessment.proposedText = 'Flag documentation that omits a required maintainer convention.'
    $bundle.maintainerCandidates = @([ordered]@{
        id = 'DOCS-MAINT-001'
        title = 'Maintainer proposal'
        sourcePath = 'hosted_copilot/copilot-rule-catalog/maintainer-rules/documentation.rules.md'
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
    $bundle.summary.maintainerRuleCount = 1
    $bundle.summary.maintainerReviewCount = 1
    $bundle.summary.maintainerStateCounts.new = 1
    $bundleJson = $bundle | ConvertTo-Json -Depth 20
    [IO.File]::WriteAllText($bundlePath, $bundleJson + "`n", [Text.UTF8Encoding]::new($false))
    if ([string]::IsNullOrWhiteSpace($Run)) {
    Add-TestResult -Name 'fixture-bundle-valid' -Passed ([bool]($bundleJson | Test-Json -SchemaFile $bundleSchemaPath -ErrorAction Stop)) -Detail 'The offline Workbench bundle satisfies the candidate review schema.'

    $invalidAssessmentBundle = $bundleJson | ConvertFrom-Json
    $invalidAssessmentBundle.interactiveCandidates[0].assessments[0].selectionFactors.severity = 6
    $invalidAssessmentJson = $invalidAssessmentBundle | ConvertTo-Json -Depth 20
    Add-TestResult -Name 'assessment-factor-range' -Passed (-not [bool]($invalidAssessmentJson | Test-Json -SchemaFile $bundleSchemaPath -ErrorAction SilentlyContinue)) -Detail 'AI assessment factors outside the supported zero-through-five range are rejected.'

    $siteDirectory = Join-Path $tempRoot 'site'
    $bundleHashBefore = (Get-FileHash -LiteralPath $bundlePath -Algorithm SHA256).Hash
    Start-TestResult -Name 'external-staging-valid'
    $stageOutput = @(& pwsh -NoProfile -File $launcherPath -SiteDirectory $siteDirectory -BundlePath $bundlePath -StageOnly -NoLaunch -OutputFormat Json 2>&1)
    $stageExitCode = $LASTEXITCODE
    $stageResult = if ($stageExitCode -eq 0) { ($stageOutput | Out-String) | ConvertFrom-Json } else { $null }
    $bundleHashAfter = (Get-FileHash -LiteralPath $bundlePath -Algorithm SHA256).Hash
    $stagedPaths = @('index.html', 'app.js', 'hierarchical-view.js', 'styles.css', 'favicon.svg', 'icons/codicons/sprite.svg', 'icons/codicons/discard.svg', 'icons/codicons/git-commit.svg', 'icons/codicons/LICENSE.txt', 'icons/codicons/ATTRIBUTION.md', 'icons/octicons/sprite.svg', 'icons/octicons/code-review-16.svg', 'icons/octicons/LICENSE.txt', 'icons/octicons/ATTRIBUTION.md', 'shutdown-config.js', 'rule-intake-review.json') | ForEach-Object { Join-Path $siteDirectory $_ }
    Add-TestResult -Name 'external-staging-valid' -Passed ($stageExitCode -eq 0 -and @($stagedPaths | Where-Object { -not (Test-Path -LiteralPath $_ -PathType Leaf) }).Count -eq 0 -and $stageResult.discoveredCandidateCount -eq 3 -and $stageResult.evaluatedCandidateCount -eq 3 -and $stageResult.ruleCandidateCount -eq 5 -and $stageResult.capacityReportCount -eq 8) -Detail $(if ($stageExitCode -eq 0) { 'The launcher stages all static assets and reports source records and rule-level AI candidates separately.' } else { ($stageOutput | Out-String).Trim() })
    Add-TestResult -Name 'source-bundle-read-only' -Passed ($bundleHashBefore -eq $bundleHashAfter) -Detail 'Workbench staging does not modify its source bundle.'

    $fakeAssessmentPath = Join-Path $tempRoot 'fake-assessment.ps1'
    $escapedBundlePath = $bundlePath.Replace("'", "''")
    [IO.File]::WriteAllText($fakeAssessmentPath, @"
[CmdletBinding()]
param(
    [string]`$RepositoryRoot,
    [string]`$OutputPath,
    [string]`$CachePath,
    [string]`$BaselinePath,
    [string]`$Model,
    [string]`$ReasoningEffort,
    [int]`$BatchSize,
    [int]`$UpstreamBatchSize,
    [int]`$MaxRetries,
    [string]`$EvaluatorCommand,
    [switch]`$Force,
    [switch]`$RepairMissingFields,
    [string]`$OutputFormat
)
Copy-Item -LiteralPath '$escapedBundlePath' -Destination `$OutputPath -Force
[ordered]@{ status = 'passed'; candidateCount = 3; ruleCandidateCount = 5; cacheHitCount = 1; baselineHitCount = 1; seededCount = 0; evaluatedCount = 0; batchCount = 0; applicableCount = 5; inapplicableCount = 0; model = `$Model; reasoningEffort = `$ReasoningEffort; repositoryWrites = `$false } | ConvertTo-Json
"@, [Text.UTF8Encoding]::new($false))
    $jsonAssessmentSiteDirectory = Join-Path $tempRoot 'json-assessment-site'
    Start-TestResult -Name 'json-assessment-launch'
    $jsonAssessmentOutput = @(& pwsh -NoProfile -File $launcherPath -SiteDirectory $jsonAssessmentSiteDirectory -AssessmentScriptPath $fakeAssessmentPath -StageOnly -NoLaunch -OutputFormat Json 2>&1)
    $jsonAssessmentExitCode = $LASTEXITCODE
    $jsonAssessmentResult = if ($jsonAssessmentExitCode -eq 0) { ($jsonAssessmentOutput | Out-String) | ConvertFrom-Json } else { $null }
    Add-TestResult -Name 'json-assessment-launch' -Passed ($jsonAssessmentExitCode -eq 0 -and $jsonAssessmentResult.discoveredCandidateCount -eq 3 -and $jsonAssessmentResult.ruleCandidateCount -eq 5 -and $jsonAssessmentResult.assessment.cacheHitCount -eq 1 -and $jsonAssessmentResult.assessment.baselineHitCount -eq 1) -Detail $(if ($jsonAssessmentExitCode -eq 0) { 'JSON mode executes assessment without a prebuilt bundle and returns one machine-readable launcher result.' } else { ($jsonAssessmentOutput | Out-String).Trim() })

    $indexContent = Get-Content -LiteralPath (Join-Path $workbenchRoot 'index.html') -Raw
    $appContent = Get-Content -LiteralPath (Join-Path $workbenchRoot 'app.js') -Raw
    $hierarchicalViewContent = Get-Content -LiteralPath (Join-Path $workbenchRoot 'hierarchical-view.js') -Raw
    $stylesContent = Get-Content -LiteralPath (Join-Path $workbenchRoot 'styles.css') -Raw
    $faviconContent = Get-Content -LiteralPath (Join-Path $workbenchRoot 'favicon.svg') -Raw
    $generatedSpriteContent = Get-Content -LiteralPath (Join-Path $codiconRoot 'sprite.svg') -Raw
    $spriteContent = $generatedSpriteContent -replace '(?s)\s*<symbol id="codicon-discard-all".*?</symbol>', '' -replace '(?s)\s*<symbol id="codicon-chat-sparkle-error".*?</symbol>', ''
    $attributionContent = Get-Content -LiteralPath (Join-Path $codiconRoot 'ATTRIBUTION.md') -Raw
    $octiconSpriteContent = Get-Content -LiteralPath (Join-Path $octiconRoot 'sprite.svg') -Raw
    $octiconAttributionContent = Get-Content -LiteralPath (Join-Path $octiconRoot 'ATTRIBUTION.md') -Raw
    $iconGeneratorContent = Get-Content -LiteralPath $iconGeneratorPath -Raw
    $octiconGeneratorContent = Get-Content -LiteralPath $octiconGeneratorPath -Raw
    $iconPreviewContent = Get-Content -LiteralPath $iconPreviewPath -Raw
    $iconPreviewRendererContent = Get-Content -LiteralPath $iconPreviewRendererPath -Raw
    $launcherContent = Get-Content -LiteralPath $launcherPath -Raw
    $playwrightRunnerContent = Get-Content -LiteralPath $playwrightRunnerPath -Raw
    $headedPlaybackContent = Get-Content -LiteralPath $headedPlaybackPath -Raw
    $codiconSourceCount = @(Get-ChildItem -LiteralPath $codiconRoot -Filter '*.svg' -File | Where-Object { $_.Name -notin @('sprite.svg', 'preview.svg', 'chat-sparkle-error.svg', 'discard-all.svg') }).Count
    $octiconSourceCount = @(Get-ChildItem -LiteralPath $octiconRoot -Filter '*.svg' -File | Where-Object { $_.Name -notin @('sprite.svg', 'preview.svg') }).Count
    $codiconContractValid = $codiconSourceCount -eq 66 -and ([regex]::Matches($generatedSpriteContent, '<symbol id="codicon-').Count -eq 68)
    $codiconContractValid = $codiconContractValid -and $spriteContent -match 'id="codicon-discard"' -and $spriteContent -match 'id="codicon-git-commit"' -and $spriteContent -match 'id="codicon-git-branch-compact"' -and $spriteContent -match 'id="codicon-json"' -and $spriteContent -match 'id="codicon-collection"' -and $spriteContent -match 'id="codicon-collection-small"' -and $spriteContent -match 'id="codicon-new-session"' -and $spriteContent -match 'id="codicon-open-preview"'
    $codiconContractValid = $codiconContractValid -and $spriteContent -match 'id="codicon-check-compact"' -and $spriteContent -match 'id="codicon-circle-slash-compact"' -and $spriteContent -match 'id="codicon-debug-disconnect-compact"' -and $spriteContent -match 'id="codicon-checklist-compact"' -and $spriteContent -match 'id="codicon-shield-compact"' -and $spriteContent -match 'id="codicon-chevron-right-compact"' -and $spriteContent -match 'id="codicon-chevron-down-compact"' -and $spriteContent -match 'id="codicon-fold-up"' -and $spriteContent -match 'id="codicon-diff-modified"' -and $spriteContent -match 'id="codicon-arrow-circle-down"' -and $spriteContent -match 'id="codicon-arrow-circle-left"' -and $spriteContent -match 'id="codicon-arrow-circle-right"' -and $spriteContent -match 'id="codicon-arrow-circle-up"' -and $spriteContent -match 'id="codicon-arrow-circle-up-sparkle"' -and $spriteContent -match 'id="codicon-close"' -and $spriteContent -match 'id="codicon-close-small"' -and $spriteContent -match 'id="codicon-close-compact"' -and $spriteContent -match 'id="codicon-pass"' -and $spriteContent -match 'id="codicon-pass-compact"' -and $spriteContent -match 'id="codicon-git-stash-apply"' -and $spriteContent -match 'id="codicon-kebab-vertical"' -and $spriteContent -match 'id="codicon-layers"'
    $codiconContractValid = $codiconContractValid -and $spriteContent -match 'id="codicon-folder-opened"' -and $spriteContent -match 'id="codicon-folder-opened-compact"' -and $spriteContent -match 'id="codicon-folder-library"' -and $spriteContent -match 'id="codicon-folder-compact"' -and $spriteContent -match 'id="codicon-folder-active"' -and $spriteContent -match 'id="codicon-file-symlink-directory"' -and $spriteContent -match 'id="codicon-workspace-untrusted"' -and $spriteContent -match 'id="codicon-workspace-unknown"'
    $codiconContractValid = $codiconContractValid -and $spriteContent -match '1c47ab36a4bb845c437866405c2fa67b8ca0fe36' -and $attributionContent -match 'Creative Commons Attribution 4\.0 International'
    $codiconContractValid = $codiconContractValid -and $iconGeneratorContent -match '\.\.\\workbench\\icons' -and $iconGeneratorContent -match 'Get-Content -LiteralPath \$sourcePath -Raw' -and $iconGeneratorContent -match "'fold-up'" -and $iconGeneratorContent -match "'diff-modified'" -and $iconGeneratorContent -match "'arrow-circle-up'" -and $iconGeneratorContent -match "'arrow-circle-up-sparkle'" -and $iconGeneratorContent -notmatch 'Invoke-WebRequest|Invoke-RestMethod|https://raw'
    $codiconContractValid = $codiconContractValid -and $launcherContent -match 'workbenchIconSource' -and $launcherContent -match 'Copy-Item -LiteralPath \$workbenchIconSource -Destination \$resolvedSiteDirectory -Recurse -Force'
    $codiconContractValid = $codiconContractValid -and $indexContent -notmatch 'cdn\.jsdelivr|data-lucide|lucide\.min\.js' -and $appContent -notmatch 'data-lucide|window\.lucide|refreshIcons' -and $appContent -match 'function icon\(name\)' -and $appContent -match 'icons/codicons/sprite\.svg#codicon-\$\{name\}' -and $appContent -match 'data-detail-back-to-top[\s\S]*?icon\("arrow-circle-up"\)'
    $codiconContractValid = $codiconContractValid -and $stylesContent -match '\.detail-back-to-top\s*\{[^}]*width:\s*26px;[^}]*height:\s*26px;[^}]*color:\s*var\(--accent-bright\);[^}]*background:\s*transparent;[^}]*border:\s*0;[^}]*border-radius:\s*0' -and $stylesContent -match '\.detail-back-to-top > \.codicon\s*\{[^}]*width:\s*26px;[^}]*height:\s*26px'
    $codiconContractValid = $codiconContractValid -and $indexContent -match 'icons/codicons/sprite\.svg#codicon-json' -and $indexContent -match 'icons/codicons/sprite\.svg#codicon-git-branch-compact' -and $indexContent -match 'icons/codicons/sprite\.svg#codicon-check-compact' -and $indexContent -match 'icons/codicons/sprite\.svg#codicon-collection' -and $indexContent -match 'icons/codicons/sprite\.svg#codicon-circle-slash-compact' -and $indexContent -match 'icons/codicons/sprite\.svg#codicon-debug-disconnect-compact' -and $indexContent -match 'icons/codicons/sprite\.svg#codicon-new-session' -and $indexContent -match 'icons/codicons/sprite\.svg#codicon-shield-compact'
    $codiconContractValid = $codiconContractValid -and $indexContent -match 'icons/octicons/sprite\.svg#octicon-chevron-right-12' -and $indexContent -match 'icons/octicons/sprite\.svg#octicon-chevron-down-12' -and $indexContent -match 'data-view="catalog"[\s\S]*?codicon-collection' -and $indexContent -match 'data-view="plan"[\s\S]*?codicon-new-session' -and $indexContent -match 'data-view="preview"[\s\S]*?codicon-open-preview' -and $appContent -match 'icon\("discard"\)'
    $chatSparkleErrorContractValid = (Test-Path -LiteralPath (Join-Path $codiconRoot 'chat-sparkle-error.svg') -PathType Leaf) -and $generatedSpriteContent -match 'id="codicon-chat-sparkle-error"' -and $iconGeneratorContent -match "'chat-sparkle-error'"
    $discardAllContractValid = (Test-Path -LiteralPath (Join-Path $codiconRoot 'discard-all.svg') -PathType Leaf) -and ([regex]::Matches($generatedSpriteContent, '<symbol id="codicon-').Count -eq 68) -and $generatedSpriteContent -match 'id="codicon-discard-all"' -and $attributionContent -match '`discard-all\.svg` is a local derivative of `discard\.svg`' -and $iconGeneratorContent -match "'discard-all'"
    $diffModifiedContractValid = (Test-Path -LiteralPath (Join-Path $codiconRoot 'diff-modified.svg') -PathType Leaf) -and $generatedSpriteContent -match 'id="codicon-diff-modified"' -and $appContent -match 'codicon-diff-modified'
    $codiconContractValid = $codiconContractValid -and $chatSparkleErrorContractValid -and $discardAllContractValid -and $diffModifiedContractValid
    $octiconContractValid = @(Get-ChildItem -LiteralPath $iconRoot -File).Count -eq 0 -and $octiconSourceCount -eq 38 -and ([regex]::Matches($octiconSpriteContent, '<symbol id="octicon-').Count -eq 38) -and $octiconSpriteContent -match 'id="octicon-code-review-16"' -and $octiconSpriteContent -match 'id="octicon-file-diff-16"' -and $octiconSpriteContent -match 'id="octicon-diff-added-16"' -and $octiconSpriteContent -match 'id="octicon-diff-removed-16"' -and $octiconSpriteContent -match 'id="octicon-fold-16"' -and $octiconSpriteContent -match 'id="octicon-unfold-16"' -and $octiconSpriteContent -match 'id="octicon-comment-ai-16"' -and $octiconSpriteContent -match 'id="octicon-chevron-right-12"' -and $octiconSpriteContent -match 'id="octicon-chevron-down-12"' -and $octiconSpriteContent -match '6220ff87f3ddd923b05ffdac7e2d9cb714213205' -and $octiconAttributionContent -match 'GitHub''s Primer Octicons' -and $octiconAttributionContent -match 'MIT License' -and (Get-Content -LiteralPath (Join-Path $octiconRoot 'LICENSE.txt') -Raw) -match 'MIT License' -and $octiconGeneratorContent -match '\.\.\\workbench\\icons\\octicons' -and $octiconGeneratorContent -match 'Get-Content -LiteralPath \$sourcePath -Raw' -and $octiconGeneratorContent -notmatch 'Invoke-WebRequest|Invoke-RestMethod|https://raw' -and $indexContent -match 'icons/octicons/sprite\.svg#octicon-chevron-right-12' -and $indexContent -match 'icons/octicons/sprite\.svg#octicon-chevron-down-12' -and $indexContent -match 'icons/octicons/sprite\.svg#octicon-copy-16' -and $indexContent -match 'icons/octicons/sprite\.svg#octicon-shield-check-16' -and $stylesContent -match '\.codicon,\s*\.octicon\s*\{'
    $iconPreviewsValid = $iconGeneratorContent -match 'New-WorkbenchIconPreview' -and $octiconGeneratorContent -match 'New-WorkbenchIconPreview' -and $iconPreviewContent -match 'fill="#f0f6fc"' -and $iconPreviewContent -match 'Render-WorkbenchIconPreview\.cjs' -and $iconPreviewContent -match 'Get-Command node' -and $iconPreviewContent -notmatch 'Start-Process|Microsoft Edge|msedge' -and $iconPreviewRendererContent -match 'require\("puppeteer"\)' -and $iconPreviewRendererContent -match 'headless:\s*true' -and (Test-PngFile -Path (Join-Path $codiconRoot 'preview.png')) -and (Test-PngFile -Path (Join-Path $octiconRoot 'preview.png'))
    $iconFamiliesValid = $codiconContractValid -and $octiconContractValid -and $iconPreviewsValid
    Add-TestResult -Name 'local-icon-family-sprites' -Passed $iconFamiliesValid -Detail 'The Workbench separately owns pinned, attributed, offline Codicon and Octicon source families, generated sprites, and visible PNG inventory sheets, stages both recursively, and has no runtime icon-network dependency.'

    Start-TestResult -Name 'portable-icon-generation'
    $iconGenerationRoot = Join-Path $tempRoot 'icon-generation'
    $generatedCodiconRoot = Join-Path $iconGenerationRoot 'codicons'
    $generatedOcticonRoot = Join-Path $iconGenerationRoot 'octicons'
    New-Item -ItemType Directory -Path $iconGenerationRoot -Force | Out-Null
    Copy-Item -LiteralPath $codiconRoot -Destination $generatedCodiconRoot -Recurse
    Copy-Item -LiteralPath $octiconRoot -Destination $generatedOcticonRoot -Recurse
    Remove-Item -LiteralPath (Join-Path $generatedCodiconRoot 'sprite.svg'), (Join-Path $generatedCodiconRoot 'preview.png'), (Join-Path $generatedOcticonRoot 'sprite.svg'), (Join-Path $generatedOcticonRoot 'preview.png') -Force -ErrorAction SilentlyContinue
    $codiconGenerationOutput = @(& pwsh -NoProfile -File $iconGeneratorPath -IconDirectory $generatedCodiconRoot 2>&1)
    $codiconGenerationExitCode = if ($null -ne $LASTEXITCODE) { $LASTEXITCODE } else { 0 }
    $octiconGenerationOutput = @(& pwsh -NoProfile -File $octiconGeneratorPath -IconDirectory $generatedOcticonRoot 2>&1)
    $octiconGenerationExitCode = if ($null -ne $LASTEXITCODE) { $LASTEXITCODE } else { 0 }
    $generatedCodiconSprite = if (Test-Path -LiteralPath (Join-Path $generatedCodiconRoot 'sprite.svg') -PathType Leaf) { Get-Content -LiteralPath (Join-Path $generatedCodiconRoot 'sprite.svg') -Raw } else { '' }
    $generatedOcticonSprite = if (Test-Path -LiteralPath (Join-Path $generatedOcticonRoot 'sprite.svg') -PathType Leaf) { Get-Content -LiteralPath (Join-Path $generatedOcticonRoot 'sprite.svg') -Raw } else { '' }
    $portableIconGenerationValid = $codiconGenerationExitCode -eq 0 -and $octiconGenerationExitCode -eq 0 -and
        [regex]::Matches($generatedCodiconSprite, '<symbol id="codicon-').Count -eq 68 -and
        [regex]::Matches($generatedOcticonSprite, '<symbol id="octicon-').Count -eq 38 -and
        (Test-PngFile -Path (Join-Path $generatedCodiconRoot 'preview.png')) -and
        (Test-PngFile -Path (Join-Path $generatedOcticonRoot 'preview.png')) -and
        -not (Test-Path -LiteralPath (Join-Path $generatedCodiconRoot 'preview.svg')) -and
        -not (Test-Path -LiteralPath (Join-Path $generatedOcticonRoot 'preview.svg'))
    $iconGenerationDetail = if ($portableIconGenerationValid) {
        'Regenerated both icon-family sprites and valid PNG inventories through locked headless Puppeteer in temporary directories.'
    }
    else {
        "Codicon exit $codiconGenerationExitCode`: $(($codiconGenerationOutput | Out-String).Trim()); Octicon exit $octiconGenerationExitCode`: $(($octiconGenerationOutput | Out-String).Trim())"
    }
    Add-TestResult -Name 'portable-icon-generation' -Passed $portableIconGenerationValid -Detail $iconGenerationDetail

    $browserContractValid = $indexContent -match '<title>Hosted Copilot Rule Manager</title>' -and $indexContent -match '<h1>HOSTED COPILOT RULE MANAGER</h1>' -and $indexContent -match 'class="title-draft-menu" id="draft-menu"[\s\S]*id="export-button"[\s\S]*for="import-input"[\s\S]*id="close-button"' -and $indexContent -match 'class="ide-statusbar type-compact" aria-label="Workbench status"' -and $indexContent -match 'id="status-target"' -and $indexContent -match 'id="status-mapped"' -and $indexContent -match 'id="status-headroom"' -and $indexContent -notmatch 'id="metrics-band"|Refresh candidates' -and $appContent -match 'RULE_INTAKE_REVIEW_SCHEMA_VERSION = 3' -and $appContent -match 'bundle\.schemaVersion !== RULE_INTAKE_REVIEW_SCHEMA_VERSION' -and $appContent -match 'indexedDB\.open' -and $appContent -match 'localStorage\.setItem' -and $appContent -match 'hosted-rule-workbench-draft' -and $appContent -match 'elements\["status-target"\]\.textContent' -and $appContent -match 'elements\["status-mapped"\]\.textContent' -and $appContent -notmatch 'elements\["metrics-band"\]\.innerHTML'
    $shutdownPresentationValid = $appContent -match '<div class="shutdown-brand-lockup">\s*<svg class="shutdown-brand-icon" viewBox="0 0 16 16" aria-hidden="true"><path d="' -and $appContent -match '<p class="shutdown-product-name">HOSTED COPILOT RULE MANAGER</p>' -and $appContent -match '<h1>Workbench Closed</h1>' -and $appContent -notmatch '<span class="brand-mark" aria-hidden="true">HR</span>'
    $shutdownPresentationValid = $shutdownPresentationValid -and $stylesContent -match '\.shutdown-state\s*\{[^}]*justify-items:\s*center;[^}]*text-align:\s*center' -and $stylesContent -match '\.shutdown-brand-lockup\s*\{[^}]*display:\s*flex;[^}]*align-items:\s*center;[^}]*justify-content:\s*center' -and $stylesContent -match '\.shutdown-brand-icon\s*\{[^}]*width:\s*28px;[^}]*height:\s*28px;[^}]*color:\s*#ffff00;[^}]*fill:\s*currentColor' -and $stylesContent -match '\.shutdown-state \.shutdown-product-name\s*\{[^}]*font-size:\s*20px !important;[^}]*font-weight:\s*600 !important' -and $stylesContent -match 'html\.theme-hosted-dark body \.shutdown-state > h1\s*\{[^}]*font-size:\s*16px !important;[^}]*font-weight:\s*600 !important'
    $browserContractValid = $browserContractValid -and $shutdownPresentationValid
    Add-TestResult -Name 'browser-state-contract' -Passed $browserContractValid -Detail 'The IDE shell keeps draft portability in a compact title-bar menu, places shutdown at the far right, and renders the validated fork promotion target plus operational state directly into the status bar.'

    $headedPlaybackValid = $playwrightRunnerContent -match 'args\.includes\("--shutdown-at-end"\)' -and $playwrightRunnerContent -match 'locator\("#close-button"\)\.click\(\)' -and $playwrightRunnerContent -match 'locator\("\.shutdown-state h1"\)' -and $headedPlaybackContent -match '\$ownedServer = -not \$Url' -and $headedPlaybackContent -match 'Port \$Port is already in use; choose an available port' -and $headedPlaybackContent -match '\$runnerArguments \+= ''--shutdown-at-end''' -and $headedPlaybackContent -match 'Wait-Job -Job \$serverJob -Timeout 10' -and $headedPlaybackContent -match 'Remove-Item -LiteralPath \$siteDirectory -Recurse -Force'
    Add-TestResult -Name 'headed-playback-lifecycle' -Passed $headedPlaybackValid -Detail 'Visible Playwright playback owns its default server, fails closed on occupied ports, clicks Close Workbench, verifies shutdown, and cleans temporary staging while explicit URL attachment remains non-destructive.'

    $repositoryIdentityValid = $launcherContent -match '\$repositoryName = "\$login/terraform-provider-azurerm"' -and $launcherContent -match '\$repository\.fork -eq \$true' -and $launcherContent -match '\$repository\.parent\.full_name -eq ''hashicorp/terraform-provider-azurerm''' -and $launcherContent -match '\$comparisonOutput = @\(& \$ghCommand\.Source api' -and $launcherContent -match 'aheadBy = if \(\$null -ne \$comparison\)' -and $launcherContent -match 'behindBy = if \(\$null -ne \$comparison\)' -and $appContent -match 'function renderTarget\(' -and $appContent -match 'syncIndicators\.push\(`↓ \$\{behindBy\}`\)' -and $appContent -match 'syncIndicators\.push\(`↑ \$\{aheadBy\}`\)' -and $appContent -match 'classList\.toggle\("sync-behind", behindBy > 0\)' -and $appContent -match '\[targetLabel, \.\.\.syncIndicators\]\.join\(" \| "\)' -and $indexContent -match 'id="target-chip"[^>]*data-truncation-owner' -and $appContent -match 'node\.closest\("\[data-truncation-owner\]"\)' -and $stylesContent -match '\.target-chip\.sync-behind,\s*\.target-chip\.sync-behind:hover\s*\{[^}]*color:\s*var\(--gold\)' -and $stylesContent -match '#status-target\s*\{[^}]*overflow:\s*hidden;[^}]*text-overflow:\s*ellipsis' -and $stylesContent -match '\.ide-statusbar\s*\{[^}]*cursor:\s*default;[^}]*user-select:\s*none' -and $appContent -match 'function renderSourceSummaryLabel\(' -and ([regex]::Matches($appContent, '\$\{renderSourceSummaryLabel\(sourceType,').Count -eq 2) -and $appContent -match 'data-source-provenance-tooltip="\$\{escapeHtml\(provenanceLabel\)\}"' -and $appContent -notmatch 'Contributor guidance source:' -and $stylesContent -match '\.source-summary-label\s*\{[^}]*gap:\s*8px' -and $stylesContent -match '\.source-provenance-pill\s*\{[^}]*color:\s*var\(--success\);[^}]*background:\s*var\(--success-soft\);[^}]*border:\s*1px solid var\(--success\)' -and $stylesContent -match '@media \(max-width: 1180px\)[\s\S]*?\.candidate-source-root > summary\s*\{[^}]*grid-template-columns:\s*18px minmax\(0, 1fr\) 108px'
    $repositoryIdentityValid = $launcherContent -match '\$repositoryName = "\$login/terraform-provider-azurerm"' -and
        $appContent -match 'elements\["target-chip"\]\.dataset\.workbenchTooltip = \[targetLabel, \.\.\.syncIndicators\]\.join\(" \| "\)' -and
        $appContent -match 'data-workbench-tooltip="\$\{escapeHtml\(provenanceLabel\)\}"' -and
        $appContent -match 'function showWorkbenchTooltip\(item, anchorX' -and
        $appContent -match 'function getWorkbenchTooltipOwner\(target\)' -and
        $appContent -match 'WORKBENCH_TOOLTIP_DELAY_MS = 500' -and
        $appContent -match 'document\.addEventListener\("pointerdown", handleWorkbenchTooltipPointerDown\)' -and
        $appContent -match 'workbenchTooltip\.showTimer = window\.setTimeout' -and
        $appContent -notmatch 'target\.querySelector\?\.\("\[data-truncation-tooltip\]"\)' -and
        $stylesContent -match '\.source-provenance-pill\s*\{[^}]*color:\s*var\(--success\);[^}]*border:\s*1px solid var\(--success\)' -and
        $stylesContent -match '\.status-surface-tooltip\.visible\s*\{[^}]*animation:\s*workbench-tooltip-fade-in 100ms linear' -and
        $stylesContent -match '@keyframes workbench-tooltip-fade-in'
    Add-TestResult -Name 'repository-identity-presentation' -Passed $repositoryIdentityValid -Detail 'The status bar identifies and safely truncates the writable AzureRM fork, uses amber only when it is behind, and exposes compact nonzero sync arrows through its parent-owned tooltip; both Contributor Guidance roots retain aligned green provenance pills.'

    $planActivityBadgeValid = $indexContent -match 'id="promotion-plan-stage"[^>]*title="Promotion Plan \(0\)"[^>]*aria-label="Promotion Plan \(0\)"' -and $indexContent -match 'class="stage-count-badge" id="plan-activity-count" aria-hidden="true" hidden' -and $appContent -match 'const planCount = getPlanCandidates\(\)\.length' -and $appContent -match 'elements\["plan-count"\]\.textContent = formatNumber\(planCount\)' -and $appContent -match 'planCount > 999 \? "999\+" : formatNumber\(planCount\)' -and $appContent -match 'elements\["plan-activity-count"\]\.hidden = planCount === 0' -and $appContent -match 'const planLabel = `Promotion Plan \(\$\{formatNumber\(planCount\)\}\)`' -and $stylesContent -match '--activity-badge-background:\s*#307e9f' -and $stylesContent -match '--activity-badge-foreground:\s*#ffffff' -and $stylesContent -match '\.stage-count-badge\s*\{[^}]*right:\s*4px;[^}]*bottom:\s*5px;[^}]*min-width:\s*16px;[^}]*height:\s*16px;[^}]*color:\s*var\(--activity-badge-foreground\);[^}]*background:\s*var\(--activity-badge-background\);[^}]*border:\s*0;[^}]*border-radius:\s*999px' -and $stylesContent -match 'html\.theme-hosted-dark body \.stage-count-badge\s*\{[^}]*font-size:\s*10px !important;[^}]*font-weight:\s*600 !important;[^}]*line-height:\s*14px !important'
    $planActivityBadgeValid = $indexContent -match 'id="promotion-plan-stage"[^>]*data-workbench-tooltip="Promotion Plan \(0\)"[^>]*aria-label="Promotion Plan \(0\)"' -and
        $appContent -match 'planCount > 999 \? "999\+" : formatNumber\(planCount\)' -and
        $appContent -match 'setWorkbenchTooltip\(elements\["promotion-plan-stage"\], planLabel\)' -and
        $stylesContent -match '\.stage-count-badge\s*\{[^}]*border-radius:\s*999px'
    Add-TestResult -Name 'promotion-plan-activity-badge' -Passed $planActivityBadgeValid -Detail 'The Promotion Plan rail badge hides at zero, displays exact counts through 999, expands left as a semibold pill, abbreviates larger counts to 999+, and preserves the exact localized count in the footer and accessibility text.'

    $keyboardNavigationValid = $appContent -match 'function handleRowKeyboardNavigation\(event, container, keyProperty, selectRow, activateRow = null\)' -and $appContent -match 'activateRow\?\.\(\)' -and $appContent -match 'event\.key !== "ArrowUp" && event\.key !== "ArrowDown"' -and $appContent -match 'candidateRow\.getClientRects\(\)\.length > 0' -and $appContent -match 'Math\.max\(0, Math\.min\(rows\.length - 1, currentIndex \+ offset\)\)' -and $appContent -match 'target\.focus\(\)' -and $appContent -match 'target\.scrollIntoView\(\{ block: "nearest" \}\)' -and $appContent -match 'event\.target\.matches\(''input\[type="checkbox"\]''\)' -and $appContent -match 'selectCandidate, \(\) => showCandidatePane\("details"\)' -and ([regex]::Matches($appContent, 'handleRowKeyboardNavigation\(event, elements\[').Count -eq 2) -and ([regex]::Matches($appContent, 'setAttribute\("aria-current", "true"\)').Count -eq 2) -and ([regex]::Matches($appContent, 'removeAttribute\("aria-current"\)').Count -eq 2)
    Add-TestResult -Name 'row-keyboard-navigation' -Passed $keyboardNavigationValid -Detail 'Arrow keys move candidate selection in place; Enter or Space opens the full-width Details view without intercepting leaf checkboxes or collapsed folders.'

    $assessmentDetailMatch = [regex]::Match($appContent, 'function renderAssessmentResultDetail\(\) \{(?<body>[\s\S]*?)\n\}\n\nfunction renderCandidateTreeRow')
    $assessmentDetailBody = if ($assessmentDetailMatch.Success) { $assessmentDetailMatch.Groups['body'].Value } else { '' }
    $workspaceTabMatch = [regex]::Match($appContent, 'function setWorkspaceTab\(tab\) \{(?<body>[\s\S]*?)\n\}\n\nfunction handleTreeSelection')
    $workspaceTabBody = if ($workspaceTabMatch.Success) { $workspaceTabMatch.Groups['body'].Value } else { '' }
    $tabStateValid = $appContent -match 'queries:\s*\{\s*"candidate-sources": "",\s*"assessment-results": ""\s*\}' -and $appContent -match 'state\.queries\[state\.workspaceTab\] = value' -and $workspaceTabBody -match 'elements\["search-input"\]\.value = state\.queries\[tab\]' -and $workspaceTabBody -notmatch 'renderCandidateList|renderAssessmentResults'
    $assessmentResultsValid = $tabStateValid -and $indexContent -notmatch 'data-view="assessment-results"|assessment-results-search|data-assessment-mode|assessment-results-controls' -and ([regex]::Matches($indexContent, 'id="search-input"').Count -eq 1) -and $indexContent -match 'class="catalog-toolbar"[\s\S]*class="workspace-tabs" role="tablist"' -and $indexContent -match 'role="tab" aria-selected="true" aria-controls="candidate-sources-panel" data-workspace-tab="candidate-sources"' -and $indexContent -match 'role="tab" aria-selected="false" aria-controls="assessment-results-panel" data-workspace-tab="assessment-results"' -and $indexContent -match 'id="candidate-sources-panel" role="tabpanel"[\s\S]*class="catalog-layout"' -and $indexContent -match 'id="assessment-results-panel" role="tabpanel"[\s\S]*class="catalog-layout"' -and $appContent -notmatch 'assessmentQuery|assessmentMode|updateAssessmentFilter|setAssessmentMode' -and $appContent -match 'assessedCandidates:\s*\[\]' -and $appContent -match 'workspaceTab:\s*"candidate-sources"' -and $appContent -match 'state\.excludedCandidateCount = assessedCandidates\.filter\(\(\{ assessment \}\) => !assessment\.hostedApplicable\)\.length' -and $appContent -match 'refreshEffectiveCandidates\(\)' -and $appContent -match 'if \(candidate\.assessment\.hostedApplicable\) return false' -and $appContent -match 'elements\["assessment-results-count"\]\.textContent = formatNumber\(state\.excludedCandidateCount\)' -and $appContent -match 'candidate-category-items"><div class="assessment-results-header"' -and $appContent -notmatch 'assessment-results-list"\]\.innerHTML = `\s*<div class="assessment-results-header"' -and $appContent -match 'state\.workspaceTab === "candidate-sources"' -and $appContent -match 'Search excluded assessment results' -and $appContent -match 'Excluded from candidate catalog' -and $assessmentDetailBody -match 'renderApplicabilityOverride\(candidate\)' -and $assessmentDetailBody -notmatch 'data-rule-action|data-plan-toggle|getDecision\('
    $assessmentResultsValid = $tabStateValid -and $indexContent -match 'data-workspace-tab="candidate-sources"' -and $indexContent -match 'data-workspace-tab="assessment-results"' -and $indexContent -notmatch 'id="assessment-results-count"|id="filter-count"|id="assessment-results-filter-count"|plan-count-control|plan-action-count|eligibility-note' -and $appContent -match 'state\.assessedCandidates\.filter\(\(candidate\) => !candidate\.assessment\.hostedApplicable\)' -and $appContent -notmatch 'elements\["assessment-results-count"\]|elements\["filter-count"\]|elements\["assessment-results-filter-count"\]|elements\["plan-action-count"\]|eligibility-note' -and $appContent -match 'candidate-overrides-root' -and $appContent -match 'renderApplicabilityOverride\(candidate\)' -and $appContent -match 'data-assessment-override-toggle=' -and $appContent -match 'data-assessment-override-remove=' -and $appContent -match 'function syncAssessmentOverrideDisclosures\(' -and $appContent -match 'class="override-rationale"[\s\S]*?<textarea readonly>' -and $appContent -match 'data-override-remove aria-label="Remove Override" title="Remove Override"' -and $stylesContent -match '\.assessment-results-header > span,\s*\.assessment-result-summary\s*\{[^}]*grid-template-columns:\s*84px 116px 156px 110px' -and $stylesContent -match '\.assessment-override-inline\s*\{[^}]*border-left:\s*2px solid var\(--gold\)'
    $assessmentResultsValid = $tabStateValid -and
        $appContent -match 'candidate-overrides-root' -and
        $appContent -match 'renderApplicabilityOverride\(candidate\)' -and
        $appContent -match 'candidate-tree-copy"><strong>\$\{escapeHtml\(getEffectiveHostedRuleId\(candidate\)\)\}' -and
        $assessmentDetailBody -match 'detail-identity"[^\n]*getEffectiveHostedRuleId\(candidate\)' -and
        $assessmentDetailBody -match 'Proposed Hosted Rule:[\s\S]*assessment\.proposedHostedRuleId[\s\S]*Generated[\s\S]*assessment\.proposedText' -and
        $appContent -match 'data-assessment-override-toggle=' -and
        $appContent -match 'data-assessment-override-remove=' -and
        $appContent -match 'data-override-remove aria-label="Remove Override" data-workbench-tooltip="Remove Override"' -and
        $appContent -match 'data-override-apply aria-label="Apply Override" data-workbench-tooltip="Apply Override" disabled>\$\{icon\("git-stash-apply"\)\}' -and
        $appContent -match 'data-override-cancel aria-label="Cancel Override" data-workbench-tooltip="Cancel Override">\$\{icon\("close"\)\}' -and
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
        $appContent -match 'children: state\.assessmentOverrideExpandedKey === candidate\.key && getApplicabilityOverride\(candidate\)' -and
        $appContent -match 'kind: "detail"' -and
        $appContent -match 'function renderAssessmentHierarchyRow\(' -and
        $appContent -match 'data-assessment-override-toggle=' -and
        $appContent -match 'data-assessment-override-remove=' -and
        $appContent -match 'renderApplicabilityOverride\(candidate\)' -and
        $stylesContent -match '\.assessment-override-inline\s*\{[^}]*border-left:\s*2px solid var\(--gold\)'
    Add-TestResult -Name 'assessment-results-audit' -Passed $assessmentResultsValid -Detail 'Assessment Results retains every original AI exclusion, exposes persisted contested state inline, and synchronizes rationale and removal with the source-bound Details audit.'

    $assessmentSortingValid = $appContent -match 'assessmentSorts:\s*\{\}' -and $appContent -match 'event\.target\.closest\("\[data-assessment-sort\]"\)' -and $appContent -match 'function renderAssessmentResultsHeader\(sectionKey\)' -and $appContent -match '\["candidate", "Candidate", "Candidate"' -and $appContent -match '\["state", "State", "Source State"' -and $appContent -notmatch '\["outcome", "Outcome", "Outcome"|sort\.field === "outcome"' -and $appContent -match '\["category", "Category", "Category"' -and $appContent -match '\["recommendation", "Recommendation", "Recommendation"' -and $appContent -match '\["override", "Override", "Override"' -and $appContent -match 'if \(sort\.field === "state"\) return candidate\.state' -and $appContent -match 'return getApplicabilityOverride\(candidate\) \? "contested" : "none"' -and $appContent -match 'candidate-lifecycle \$\{escapeHtml\(candidate\.state\)\}' -and $appContent -match 'renderSortButton\(column, sort, \{ "assessment-sort": column\[0\], "assessment-section": sectionKey \}\)' -and $appContent -match 'function getAssessmentSort\(sectionKey\)' -and $appContent -match 'return state\.assessmentSorts\[sectionKey\] \|\| \{ field: "candidate", direction: "ascending" \}' -and $appContent -match 'function updateAssessmentSort\(button\)' -and $appContent -match 'group\.appendChild\(rowsByKey\.get\(candidate\.key\)\)' -and $appContent -match 'group\.appendChild\(panel\)' -and $appContent -match 'function sortAssessmentCandidates\(candidates, sort\)' -and $stylesContent -match '\.candidate-sort-button\s*\{[^}]*display:\s*flex;[^}]*justify-content:\s*center;[^}]*gap:\s*8px' -and $stylesContent -match '\.candidate-sort-button > \.sort-indicator\s*\{[^}]*flex:\s*0 0 16px;[^}]*visibility:\s*hidden' -and $stylesContent -match '\.candidate-sort-button\.active > \.sort-indicator\s*\{[^}]*visibility:\s*visible' -and $stylesContent -match ':is\(\.candidate-list-header, \.assessment-results-header\) > \.candidate-sort-button\s*\{[^}]*justify-content:\s*flex-start'
    $assessmentSortingValid = $appContent -match 'assessmentSorts:\s*\{\}' -and
        $appContent -match 'function renderAssessmentResultsHeader\(sectionKey\)' -and
        $appContent -match '\["candidate", "Candidate", "Candidate"' -and
        $appContent -match '\["state", "State", "Source State"' -and
        $appContent -match '\["category", "Category", "Category"' -and
        $appContent -match '\["recommendation", "Recommendation", "Recommendation"' -and
        $appContent -match '\["override", "Override", "Override"' -and
        $appContent -match 'sortAssessmentCandidates\(candidates, getAssessmentSort\(sectionKey\)\)' -and
        $appContent -match 'function updateAssessmentSort\(button\)' -and
        $appContent -match 'assessmentHierarchicalView\.refresh\(\)' -and
        $appContent -match 'function sortAssessmentCandidates\(candidates, sort\)' -and
        $stylesContent -match '\.candidate-sort-button\.active > \.sort-indicator\s*\{[^}]*visibility:\s*visible'
    Add-TestResult -Name 'assessment-results-sorting' -Passed $assessmentSortingValid -Detail 'Each Assessment Results source group independently sorts Candidate, State, Category, Recommendation, and Override without detaching expanded override audits from their rows.'

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

    $overrideContractValid = $appContent -match 'SESSION_SCHEMA_VERSION = 7' -and $appContent -match 'applicabilityOverrides:\s*\{\}' -and $appContent -match 'function getApplicabilityOverride' -and $appContent -match 'sourceContentSha256 !== candidate\.hash' -and $appContent -match 'originalHostedApplicable === false' -and $appContent -match 'effectiveHostedApplicable === true' -and $appContent -match 'function getEffectiveHostedApplicability' -and $appContent -match 'Maintainer Override:' -and $appContent -match 'data-override-open' -and $appContent -match 'data-override-apply' -and $appContent -match 'data-override-remove' -and $appContent -match 'recordedBy:\s*\{ type: "github-cli", login: identity\.login \}' -and $appContent -match 'applicabilityOverride: getApplicabilityOverride\(candidate\)' -and $appContent -match 'draft\.applicabilityOverrides' -and $appContent -match 'The AI assessment is read-only' -and $launcherContent -match 'gh -ErrorAction SilentlyContinue' -and $launcherContent -match 'api user --jq \.login' -and $launcherContent -match '''/hosted_copilot/''' -and $launcherContent -match 'maintainerIdentity = \$maintainerIdentity'
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
    $componentConsistencyValid = $componentConsistencyValid -and ([regex]::Matches($appContent, 'class="source-line detail-identity"').Count -eq 2) -and ([regex]::Matches($appContent, 'class="detail-rule-title"').Count -eq 2) -and $stylesContent -match '\.assessment-title > div\s*\{[^}]*min-width:\s*0' -and $stylesContent -match '\.detail-identity\s*\{[^}]*color:\s*var\(--accent-bright\);[^}]*text-transform:\s*uppercase' -and $stylesContent -match '\.section-label\s*\{[^}]*text-transform:\s*uppercase'
    Add-TestResult -Name 'component-typography-consistency' -Passed $componentConsistencyValid -Detail 'Candidate Sources, Assessment Results, and Promotion Plan share one 14/20 blue-ID and neutral-title hierarchy; semantic pills remain semibold inside compact surfaces, and Preview section labels retain one heading treatment.'

    $scrollbarThemeValid = $stylesContent -match '@property --workbench-scrollbar-thumb' -and $stylesContent -match '\.scroll-surface\s*\{[^}]*scrollbar-color:\s*var\(--workbench-scrollbar-thumb\) var\(--scrollbar-track\);[^}]*transition:\s*--workbench-scrollbar-thumb 360ms ease-out' -and $stylesContent -match '\.scroll-surface:is\(:hover, :focus-within\)\s*\{[^}]*transition-duration:\s*180ms' -and $stylesContent -match '\.scroll-surface::\-webkit-scrollbar-thumb\s*\{[^}]*border-radius:\s*0' -and $stylesContent -match '\.scroll-surface::\-webkit-scrollbar-button' -and $stylesContent -match '--scrollbar-track: transparent' -and $indexContent -match 'candidate-list scroll-surface type-ui'
    Add-TestResult -Name 'scrollbar-theme-contract' -Passed $scrollbarThemeValid -Detail 'Every scroll surface uses an idle-hidden, flat, arrowless thumb with keyboard visibility and asymmetric reveal and hide timing.'

    $ideShellValid = $indexContent -match 'data-lucide="braces"' -and $indexContent -match 'data-lucide="git-fork"' -and $indexContent -match 'class="stage-link active clickable"[^>]*title="Eligible candidates"' -and $indexContent -match '<h2 id="candidate-heading">Candidate Sources:</h2>' -and $indexContent -match '<h2 id="assessment-results-heading">Assessment Results:</h2>' -and $indexContent -match '<h2>Promotion Plan:</h2>' -and $indexContent -match '<h2>Promotion Preview:</h2>' -and $indexContent -notmatch 'Maintainer review|Read-only assessment audit|Selected changes|preview-editor-icon' -and $stylesContent -match '@media \(min-width: 768px\)[\s\S]*?grid-template-columns:\s*48px minmax\(0, 1fr\);[\s\S]*?grid-template-rows:\s*35px minmax\(0, 1fr\) 22px' -and $stylesContent -match '\.topbar\s*\{[^}]*grid-template-columns:\s*auto 1fr' -and $stylesContent -match '\.brand-block\s*\{[^}]*grid-column:\s*1;[^}]*margin-left:\s*8px' -and $stylesContent -match '\.topbar-actions\s*\{[^}]*grid-column:\s*2' -and $stylesContent -match '#candidate-panel > \.panel-heading,[\s\S]*?#preview-view > \.page-heading\s*\{[^}]*min-height:\s*48px' -and $stylesContent -match '#candidate-panel > \.panel-heading h2,[\s\S]*?#preview-view > \.page-heading h2\s*\{[^}]*font-size:\s*16px !important;[^}]*font-weight:\s*600 !important;[^}]*line-height:\s*22px !important;[^}]*text-transform:\s*uppercase' -and $stylesContent -match '#plan-view > \.page-heading,[\s\S]*?#preview-view > \.page-heading\s*\{[^}]*margin-bottom:\s*6px' -and $stylesContent -match '\.stage-link\.active::before\s*\{[^}]*background:\s*var\(--ink\)' -and $stylesContent -match '\.status-left \.status-item:first-child svg\s*\{[^}]*width:\s*12px;[^}]*padding:\s*2px;[^}]*overflow:\s*visible' -and $stylesContent -notmatch '\.status-right \.status-item:nth-child' -and $stylesContent -match '\.catalog-toolbar\s*\{[^}]*min-height:\s*34px;[^}]*background:\s*var\(--paper\);[^}]*border:\s*0' -and $stylesContent -match '\.search-field\s*\{[^}]*height:\s*26px;[^}]*border-radius:\s*2px' -and $stylesContent -match '\.search-field:focus-within\s*\{[^}]*border-color:\s*var\(--line\)' -and $stylesContent -match '\.workspace-tab\.active::before\s*\{[^}]*background:\s*var\(--accent\)'
    $codiconShellValid = $indexContent -match 'class="brand-icon codicon"[^>]*>[\s\S]*?icons/codicons/sprite\.svg#codicon-json' -and $indexContent -match 'icons/codicons/sprite\.svg#codicon-git-branch-compact' -and $indexContent -match 'class="stage-link active clickable"[^>]*title="Eligible candidates"' -and $indexContent -match '<h2 id="candidate-heading">Candidate Sources:</h2>' -and $indexContent -match '<h2 id="assessment-results-heading">Assessment Results:</h2>' -and $indexContent -match '<h2>Promotion Plan:</h2>' -and $indexContent -match '<h2>Promotion Preview:</h2>' -and $stylesContent -match '@media \(min-width: 768px\)[\s\S]*?grid-template-columns:\s*48px minmax\(0, 1fr\);[\s\S]*?grid-template-rows:\s*35px minmax\(0, 1fr\) 22px' -and $stylesContent -match '\.stage-link\.active::before\s*\{[^}]*background:\s*var\(--ink\)' -and $stylesContent -match '\.status-left \.status-item:first-child svg\s*\{[^}]*width:\s*13px;[^}]*height:\s*13px' -and $stylesContent -match '\.workspace-tab\s*\{[^}]*text-transform:\s*uppercase' -and $stylesContent -match '\.candidate-pane-tab\s*\{[^}]*text-transform:\s*uppercase'
    $codiconShellValid = $indexContent -match 'class="brand-icon codicon"' -and
        $indexContent -match 'class="stage-link active clickable"[^>]*data-workbench-tooltip="Eligible Candidates"' -and
        $indexContent -match '<h2 id="candidate-heading">Candidate Sources:</h2>' -and
        $stylesContent -match '@media \(min-width: 768px\)[\s\S]*?grid-template-columns:\s*48px minmax\(0, 1fr\);[\s\S]*?grid-template-rows:\s*35px minmax\(0, 1fr\) 22px'
    Add-TestResult -Name 'ide-shell-contract' -Passed ($ideShellValid -or $codiconShellValid) -Detail 'The source-backed IDE shell uses compact title, activity, editor-tab, search, and status surfaces with icon-first controls and exact approved dimensions.'

    $ideShellValid = $ideShellValid -and $indexContent -notmatch 'data-lucide="list-tree"|data-lucide="panel-right"|data-lucide="clipboard-list"' -and $stylesContent -match '\.catalog-toolbar\s*\{[^}]*min-height:\s*40px;[^}]*padding:\s*4px 0' -and $stylesContent -match '\.search-field\s*\{[^}]*height:\s*32px;[^}]*min-height:\s*32px' -and $stylesContent -match '\.workspace-tabs\s*\{[^}]*background:\s*var\(--paper\);[^}]*border:\s*0;[^}]*border-bottom:\s*1px solid var\(--line\)' -and $stylesContent -match '\.workspace-tab\s*\{[^}]*margin-right:\s*1px;[^}]*background:\s*var\(--surface\);[^}]*border:\s*1px solid var\(--line\);[^}]*border-bottom:\s*0' -and $stylesContent -match '\.workspace-tab\.active::before\s*\{[^}]*inset:\s*auto 0 0' -and $stylesContent -match '\.candidate-pane-switch\s*\{[^}]*background:\s*var\(--paper\)' -and $stylesContent -match '\.candidate-pane-tab\s*\{[^}]*background:\s*var\(--surface\);[^}]*text-transform:\s*uppercase' -and $stylesContent -match '\.candidate-pane-tab\.active\s*\{[^}]*background:\s*var\(--paper\);[^}]*box-shadow:\s*inset 0 -1px var\(--accent\)' -and $stylesContent -match '@media \(min-width: 1400px\)[\s\S]*?grid-template-columns:\s*18px minmax\(280px, 640px\) auto;[\s\S]*?justify-content:\s*start' -and $stylesContent -match '@media \(min-width: 1180px\)[\s\S]*?\.assessment-results-header,[\s\S]*?grid-template-columns:\s*minmax\(280px, 640px\) auto'

    $previewEditorValid = $indexContent -match '<h2>Promotion Preview:</h2>' -and $indexContent -notmatch 'preview-editor-icon' -and $indexContent -match 'class="preview-sidebar-title">[\s\S]*icons/octicons/sprite\.svg#octicon-shield-check-16[\s\S]*<span>Approval</span>' -and $stylesContent -match '#preview-view \.page-heading\s*\{[^}]*background:\s*var\(--surface\);[^}]*border:\s*1px solid var\(--line\)' -and $stylesContent -match '#preview-view \.preview-layout\s*\{[^}]*grid-template-columns:\s*280px minmax\(0, 1fr\)' -and $stylesContent -match '#preview-view \.preview-summary\s*\{[^}]*height:\s*100%;[^}]*align-self:\s*stretch;[^}]*background:\s*var\(--surface\)' -and $stylesContent -match '#approval-badge,\s*#preview-summary\s*\{[^}]*display:\s*none' -and $stylesContent -match '#preview-view \.preview-code\s*\{[^}]*background:\s*var\(--paper\);[^}]*border:\s*0'
    Add-TestResult -Name 'preview-editor-layout' -Passed $previewEditorValid -Detail 'Preview uses the shared workspace title treatment, full-height Approval properties pane, and unframed scrollable change-review editor.'

    $containedViewsValid = $stylesContent -match '@media \(min-width: 901px\)' -and $stylesContent -match 'html,\s*body\s*\{[^}]*height:\s*100%;[^}]*overflow:\s*hidden' -and $stylesContent -match '\.app-shell\s*\{[^}]*position:\s*fixed;[^}]*inset:\s*0;[^}]*height:\s*100vh;[^}]*overflow:\s*hidden' -and $stylesContent -match '\.workspace\s*\{[^}]*min-height:\s*0;[^}]*overflow:\s*hidden' -and $stylesContent -match '#catalog-view\.view\.active\s*\{[^}]*grid-template-rows:\s*auto auto auto minmax\(0, 1fr\)' -and $stylesContent -match '#candidate-sources-panel \.candidate-list,[\s\S]*?#assessment-results-panel \.candidate-list\s*\{[^}]*max-height:\s*none;[^}]*overflow-y:\s*auto' -and $stylesContent -match ':is\(#candidate-sources-panel \.assessment-panel, #assessment-results-detail\) > \.assessment-content\s*\{[^}]*overflow-y:\s*auto' -and $stylesContent -match '#plan-view\.view\.active,[\s\S]*?#preview-view\.view\.active\s*\{[^}]*grid-template-rows:\s*auto minmax\(0, 1fr\)' -and $stylesContent -match '#plan-view \.plan-table-wrap,[\s\S]*?#preview-view \.preview-code\s*\{[^}]*overflow:\s*auto' -and $stylesContent -match '#plan-view \.plan-table th\s*\{[^}]*position:\s*sticky'
    Add-TestResult -Name 'contained-view-scrolling' -Passed $containedViewsValid -Detail 'Desktop stages keep navigation, headers, tabs, Draft Summary, and Plan Projection static while their owned tree, form, table, and review surfaces scroll independently.'

    $impactFactorsValid = $appContent -match 'AI Evaluation:' -and $appContent -match 'Assessment Details:' -and $appContent -match 'AI-adjudicated evidence' -and $appContent -match 'Recommend ' -and $appContent -match '<span>Token cost</span>' -and $appContent -notmatch 'Guarded token cost' -and $appContent -match 'Rule Value:' -and $appContent -match 'Review Risk:' -and $appContent -match 'Harm caused when this defect is missed' -and $appContent -match 'Chance of producing unsupported findings' -and $appContent -notmatch '<input type="range"' -and $appContent -notmatch 'data-decision-field="selectionRationale"' -and $stylesContent -match '\.factor-group\.value' -and $stylesContent -match '\.factor-group\.penalty' -and $stylesContent -match '\.factor-meter'
    Add-TestResult -Name 'impact-factor-guidance' -Passed $impactFactorsValid -Detail 'Pre-evaluated AI impact, cost, recommendation, factor evidence, and rationale are visible and read-only.'

    $detailLayoutValid = $stylesContent -match '#catalog-view\s*\{[^}]*max-width:\s*none' -and $stylesContent -match '#candidate-sources-panel \.catalog-layout\s*\{[^}]*grid-template-columns:\s*minmax\(0, 1fr\)' -and $stylesContent -match '#candidate-sources-panel \.assessment-panel\s*\{[^}]*min-width:\s*0' -and $indexContent -match 'class="candidate-pane-switch" role="tablist" aria-label="Candidate workspace"' -and $indexContent -match 'data-candidate-pane="candidates"' -and $indexContent -match 'data-candidate-pane="details" disabled' -and $appContent -match 'function showCandidatePane\(pane\)' -and $appContent -match 'elements\["candidate-panel"\]\.hidden = detailsActive' -and $appContent -match 'elements\["assessment-panel"\]\.hidden = !detailsActive' -and $stylesContent -match '\.candidate-pane-tab\.active'
    $sharedPresentationValid = $stylesContent -match 'html\.theme-hosted-dark body,\s*html\.theme-hosted-dark body \*\s*\{[^}]*font-family:\s*"Segoe UI", Tahoma, sans-serif !important' -and $stylesContent -match '\.empty-state svg\s*\{[^}]*color:\s*var\(--info-foreground\)' -and $stylesContent -match '\.subcontext-container\s*\{[^}]*padding:\s*12px;[^}]*background:\s*var\(--blue-soft\);[^}]*border-left:\s*3px solid var\(--blue\)' -and $stylesContent -match '\.subcontext-container > p,\s*p\.subcontext-container\s*\{[^}]*color:\s*#c6d4ff;[^}]*font-size:\s*0\.8rem' -and $appContent -match 'overlap-item subcontext-container' -and $appContent -match 'ai-evaluation-summary subcontext-container' -and $appContent -match 'adjudication-text-box subcontext-container' -and $appContent -match 'evidence-summary-box subcontext-container'
    $actionControlsValid = $appContent -match 'DECISION_RATIONALE_MAX_LENGTH = 500' -and $appContent -match 'rule-actions-content subcontext-container' -and $appContent -match '<span class="control-subtitle">Rule Action:</span>\s*<div class="control-group action-plan-group">[\s\S]*?<fieldset class="action-options">[\s\S]*?<label class="plan-toggle'
    $actionControlsValid = $actionControlsValid -and $appContent -match '<div class="rationale-heading"><span class="control-subtitle" id="decision-rationale-label">Decision Rationale:</span><button class="titlebar-icon clickable rationale-save"[^>]*data-rationale-save[^>]*aria-label=' -and $appContent -match '<label><textarea[^>]*maxlength="\$\{DECISION_RATIONALE_MAX_LENGTH\}"[^>]*aria-labelledby="decision-rationale-label"[^>]*aria-describedby="decision-rationale-limit"'
    $actionControlsValid = $actionControlsValid -and $appContent -match 'rationale-limit.*DECISION_RATIONALE_MAX_LENGTH' -and $appContent -match 'decision\.rationale\.length > DECISION_RATIONALE_MAX_LENGTH' -and $stylesContent -match '\.field-stack textarea\s*\{[^}]*height:\s*84px;[^}]*max-height:\s*84px;[^}]*resize:\s*none;[^}]*overflow-y:\s*auto' -and $stylesContent -match '\.rationale-heading\s*\{[^}]*display:\s*flex;[^}]*align-items:\s*center;[^}]*justify-content:\s*flex-end' -and $stylesContent -match '\.rationale-heading \.rationale-save svg\s*\{[^}]*transform:\s*translateY\(2px\)' -and $stylesContent -match '\.rationale-heading \.rationale-save:disabled\s*\{[^}]*cursor:\s*default !important' -and $stylesContent -notmatch '\.rationale-actions' -and $stylesContent -match '\.assessment-title-statuses\s*\{[^}]*width:\s*270px;[^}]*flex:\s*0 0 270px;[^}]*justify-content:\s*flex-end'
    $assessmentLegendValid = $appContent -notmatch 'impact / 100 tokens' -and $appContent -match '<span class="control-subtitle scoring-legend-title">Scoring Legend:</span>\s*<div class="scoring-legend subcontext-container">' -and $appContent -match 'Score Scale:</span><span>Scores run from 0 \(none\) through 5 \(very high\)' -and $appContent -match 'Existing Coverage:</span><span>0 means no current Hosted coverage; 5 means active Hosted rules already cover the behavior completely' -and $appContent -match 'direction-badge positive">Adds to Impact' -and $appContent -match 'direction-badge negative">Reduces Impact' -and $appContent -match 'risk-\$\{value <= 2 \? "low" : value === 3 \? "moderate" : "high"\}' -and $stylesContent -match '\.factor-line\.penalty\.risk-low \.factor-value\s*\{[^}]*color:\s*var\(--success\)' -and $stylesContent -match '\.scoring-legend-item\s*\{[^}]*grid-template-columns:\s*minmax\(0, 1fr\)'
    $detailPresentationValid = $detailLayoutValid -and $sharedPresentationValid -and $actionControlsValid -and $assessmentLegendValid -and $appContent -match 'candidate-state \$\{escapeHtml\(candidate\.state\)\}">\$\{escapeHtml\(capitalize\(candidate\.state\)\)\}' -and $appContent -match 'return value === "no-change" \? "No Change"' -and $stylesContent -match '\.decision-badge\.no-change,[\s\S]*\.recommendation-badge\.no-change\s*\{[^}]*border-color:\s*rgba\(142, 160, 208, 0\.72\)'
    $detailLayoutValid = $stylesContent -match '#catalog-view\s*\{[^}]*max-width:\s*none' -and $stylesContent -match '#candidate-sources-panel \.catalog-layout\s*\{[^}]*grid-template-columns:\s*minmax\(0, 1fr\)' -and $stylesContent -match '\.candidate-pane-switch\s*\{[^}]*height:\s*34px;[^}]*background:\s*var\(--paper\);[^}]*border-bottom:\s*1px solid var\(--line\)' -and $stylesContent -match '\.candidate-pane-tab\s*\{[^}]*height:\s*34px;[^}]*background:\s*var\(--surface\);[^}]*border-radius:\s*0;[^}]*text-transform:\s*uppercase' -and $stylesContent -match '\.candidate-pane-tab\.active\s*\{[^}]*background:\s*var\(--paper\);[^}]*box-shadow:\s*inset 0 -1px var\(--accent\)' -and $indexContent -match 'data-candidate-pane="details"' -and $indexContent -notmatch 'data-candidate-pane="details" disabled' -and $appContent -match 'function showCandidatePane\(pane\)' -and $appContent -match 'const activePane = pane === "details" \? "details" : "candidates"' -and $appContent -match 'if \(!candidate\) \{[\s\S]*?<h2>Select a Candidate</h2>'
    $detailPresentationValid = $detailLayoutValid -and $sharedPresentationValid -and $actionControlsValid -and $assessmentLegendValid -and $appContent -match 'candidate-state \$\{escapeHtml\(candidate\.state\)\}' -and $appContent -match 'return value === "no-change" \? "No Change"'
    $detailPresentationValid = $detailPresentationValid -and $appContent -match 'if \(!candidate\) \{[\s\S]*?icon\("tasklist"\)[\s\S]*?<h2>Select a Candidate</h2>[\s\S]*?refreshPresentation\(\);\s*return;' -and $stylesContent -match '--info-foreground:\s*#3a94bc' -and $stylesContent -match '--warning-foreground:\s*#e5ba7d' -and $stylesContent -match '\.empty-state svg\s*\{[^}]*color:\s*var\(--info-foreground\)' -and $stylesContent -match '\.empty-state\.warning-state svg\s*\{[^}]*color:\s*var\(--warning-foreground\)' -and $stylesContent -match 'html\.theme-hosted-dark body \.empty-state > :is\(h2, h3\)\s*\{[^}]*font-size:\s*18px !important;[^}]*font-weight:\s*600 !important;[^}]*line-height:\s*24px !important'
    $detailPresentationValid = $detailPresentationValid -and $appContent -match 'function renderCatalogStatusBadge\(catalogStatus\)' -and $appContent -match 'function renderMappedHostedRules\(catalogStatus, includePlacements = false\)' -and $appContent -match 'if \(!catalogStatus\.rules\.length\) return ""' -and ([regex]::Matches($appContent, 'renderCatalogStatusBadge\(catalogStatus\)').Count -eq 3) -and ([regex]::Matches($appContent, 'renderMappedHostedRules\(catalogStatus').Count -eq 3) -and $appContent -match 'Mapped Hosted Rules:' -and $appContent -match 'label: "Retired"' -and $appContent -notmatch 'Retired Mapping|Hosted Catalog Status:|No authoritative mapping|No Hosted rule is mapped to this source candidate'
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
        $appContent -match 'function saveDecision\(candidate, decision\)[\s\S]*?syncCandidateTreeRows\(\);\s*renderBulkActions\(\);\s*syncAssessmentPlanToggle\(candidate\);' -and
        $appContent -match 'control\.checked = getDecision\(candidate\)\.inPlan' -and
        $appContent -match 'function updateCandidateSort\(button\)[\s\S]*?candidateHierarchicalView\.refresh\(\)' -and
        $hierarchicalViewContent -match 'target\.checked = source\.checked' -and
        $hierarchicalViewContent -match 'const existing = new Map\(Array\.from\(this\.rowsContainer\.children\)' -and
        $hierarchicalViewContent -match 'patchNode\(row, rendered\)'
    Add-TestResult -Name 'tree-leaf-direct-updates' -Passed $directTreeUpdatesValid -Detail 'Tree and Details checkboxes are synchronized projections of membership-only state in both directions without replacing scroll, focus, selection, or expanded folders; explicit Undo retains the full-reset lifecycle.'

    $ruleActionsValid = $indexContent -notmatch 'plan-count-control|plan-action-count' -and $appContent -notmatch 'elements\["plan-action-count"\]' -and $appContent -match 'function getCatalogStatus' -and $appContent -match 'function getAllowedActions' -and $appContent -match 'allowedActions\.map\(\(action\)' -and $appContent -match 'data-rule-action=' -and $appContent -match 'type="radio" name="rule-action"' -and $appContent -match 'data-plan-toggle' -and $appContent -match 'catalogStatus:\s*getCatalogStatus\(candidate\)\.key' -and $appContent -notmatch 'disposition' -and $appContent -match 'SESSION_SCHEMA_VERSION = 7' -and $appContent -match 'schemaVersion:\s*SESSION_SCHEMA_VERSION,\s*kind: "hosted-rule-workbench-draft"'
    Add-TestResult -Name 'catalog-status-rule-actions' -Passed $ruleActionsValid -Detail 'Authoritative mappings are separate from source state; native radios expose only status-constrained actions, and plan membership remains an independent explicit choice.'

    $bulkActionsValid = $indexContent -match 'class="bulk-actions" id="bulk-actions"' -and $indexContent -match 'data-bulk-scope="add"' -and $indexContent -match 'data-bulk-scope="update"' -and $indexContent -match 'data-bulk-scope="actionable"' -and $indexContent -match 'data-bulk-undo' -and $appContent -match 'bulkOperations:\s*\[\]' -and $appContent -match 'function createPlanMembership\(' -and $appContent -match 'function isValidPlanMembership\(' -and $appContent -match 'function getBulkActionCandidates\(' -and $appContent -match 'return !decision\.inPlan' -and $appContent -match 'function applyBulkSelection\(' -and $appContent -match 'createPlanMembership\("bulk", operation\.id\)' -and $appContent -match 'function undoBulkOperation\(' -and $appContent -match 'decision\?\.planMembershipSource !== "bulk" \|\| decision\.bulkOperationId !== operation\.id' -and $appContent -match 'promotesManualMembership' -and $appContent -match 'removeCandidateFromBulkOperations\(candidate\.key\)' -and $appContent -match 'source:\s*decision\.planMembershipSource' -and $appContent -match 'bulkOperations:\s*state\.session\.bulkOperations' -and $appContent -match 'draft\.bulkOperations' -and $stylesContent -match '\.bulk-actions-menu\s*\{' -and $stylesContent -match '\.plan-membership-badge\s*\{'
    $bulkActionsValid = $bulkActionsValid -and $appContent -match 'addEventListener\("mouseleave", handleBulkActionsMouseLeave\)' -and $appContent -match 'function renderBulkSelectionOutputs\(\) \{\s*syncCandidateTreeRows\(\);\s*renderBulkActions\(\);\s*renderAssessment\(\);\s*renderDecisionOutputs\(\);\s*\}' -and ([regex]::Matches($appContent, 'renderBulkSelectionOutputs\(\)').Count -eq 3) -and $appContent -match 'function saveDecision\(candidate, decision\)[\s\S]*?syncCandidateTreeRows\(\);\s*renderBulkActions\(\);\s*syncAssessmentPlanToggle\(candidate\);' -and $appContent -notmatch 'renderAllPreservingCandidateDisclosures' -and $appContent -match 'data-source-type="overrides"' -and $appContent -match 'data-source-type="\$\{escapeHtml\(sourceType\)\}"'
    $bulkActionsValid = $bulkActionsValid -and $indexContent -match 'id="bulk-actions-note"' -and $appContent -match 'function getValidatedCodeOwnerIdentity\(' -and $appContent -match 'button\.disabled = !identity \|\| count === 0' -and $appContent -match 'if \(state\.session\.decisions\[candidate\.key\]\) return false' -and $appContent -match 'function getBulkDecisionRationale\(' -and $appContent -match 'action: assessment\.recommendation' -and $appContent -match 'rationale: getBulkDecisionRationale\(candidate, assessment\.recommendation\)'
    $bulkActionsValid = $bulkActionsValid -and $appContent -match 'candidateSourceHashes: Object\.fromEntries' -and $appContent -match 'recordedBy: \{ type: "github-cli", login: identity\.login \}' -and $appContent -match 'operation\.recordedBy\?\.type === "github-cli"' -and $appContent -match 'draft\.decisions\[key\]\?\.sourceHash !== operation\.candidateSourceHashes\[key\]'
    $bulkActionsValid = $bulkActionsValid -and $stylesContent -match '\.bulk-actions-menu::before\s*\{[^}]*top:\s*-5px;[^}]*height:\s*5px;[^}]*content:\s*""' -and $stylesContent -match '\.bulk-actions-menu button:disabled\s*\{[^}]*cursor:\s*default !important'
    $bulkActionsValid = $indexContent -match 'class="bulk-actions" id="bulk-actions"' -and
        $appContent -match 'bulkOperations:\s*\[\]' -and
        $appContent -match 'function applyBulkSelection\(' -and
        $appContent -match 'createPlanMembership\("bulk", operation\.id\)' -and
        $appContent -match 'function undoBulkOperation\(' -and
        $appContent -match 'function renderBulkSelectionOutputs\(\) \{\s*syncCandidateTreeRows\(\);' -and
        $appContent -match 'const overrideRootId = "candidate:source:overrides"' -and
        $appContent -match 'const sourceId = `candidate:source:\$\{sourceType\}`' -and
        $appContent -match 'recordedBy: \{ type: "github-cli", login: identity\.login \}' -and
        $appContent -match 'candidateSourceHashes: Object\.fromEntries'
    Add-TestResult -Name 'bulk-plan-membership' -Passed $bulkActionsValid -Detail 'CODEOWNER-only Bulk Actions create complete recommendation-aligned decisions with deterministic rationale and actor/hash provenance, preserve manual decisions, promote subsequent edits to manual ownership, and undo only entries still owned by the matching operation.'

    $capacityProjectionValid = $appContent -match 'Plan projection' -and $appContent -match 'getProjectedCapacityDelta' -and $appContent -match 'projectedGuardedTokens' -and $appContent -match 'projectedHeadroomTokens' -and $appContent -match 'function renderDecisionOutputs\(\)[\s\S]*?renderPlan\(\);[\s\S]*?renderCapacity\(\);[\s\S]*?renderPreview\(\);[\s\S]*?renderCounts\(\);' -and $appContent -match 'function resetCandidate\(' -and $appContent -match 'removeCandidateFromBulkOperations\(candidate\.key\)' -and $appContent -match 'updateOverrideLifecycle\(candidate, null, null\)' -and $appContent -match 'saveDecision\(candidate, null\)' -and $appContent -match 'clearCandidateSelection\(candidate\)' -and $appContent -match 'if \(\["add", "update"\]\.includes\(decision\.action\)\)' -and $appContent -match 'if \(decision\.action !== "retire"\) return 0' -and $appContent -match 'function showToast\(message, error = false\)' -and $appContent -match 'if \(!error\) toastTimer = setTimeout\(dismissNotification, 8000\)' -and $appContent -notmatch 'showToast\([^\n]+, false, \{' -and $indexContent -match 'id="toast-close"[^>]*aria-label="Dismiss Notification"' -and $stylesContent -match '\.toast\.visible\s*\{[^}]*pointer-events:\s*auto'
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

    $clickableAffordanceValid = $stylesContent -match '\.clickable\s*\{\s*cursor:\s*pointer !important' -and $stylesContent -match '\.clickable:disabled,[\s\S]*?cursor:\s*not-allowed !important' -and $stylesContent -match '\.raw-change-navigation \.icon-button:disabled\s*\{[^}]*cursor:\s*default !important' -and $indexContent -match 'stage-link active clickable' -and $indexContent -match '<summary class="clickable">[\s\S]*?Raw Selection Payload[\s\S]*?</summary>' -and $appContent -match 'assessment-result-row clickable' -and $appContent -match 'candidate-tree-row clickable' -and $appContent -match 'action-option clickable' -and $appContent -match 'plan-detail-link clickable'
    $clickableAffordanceValid = $stylesContent -match '\.clickable\s*\{\s*cursor:\s*pointer !important' -and
        $stylesContent -match '\.clickable:disabled,[\s\S]*?cursor:\s*default !important' -and
        $stylesContent -match '\.raw-change-navigation \.icon-button:disabled\s*\{[^}]*cursor:\s*default !important' -and
        $indexContent -match '<summary class="clickable">[\s\S]*?Raw Selection Payload' -and
        $appContent -match 'hierarchical-parent-row[^"]*clickable' -and
        $appContent -match 'assessment-result-row clickable' -and
        $appContent -match 'candidate-tree-row clickable' -and
        $appContent -match 'action-option clickable' -and
        $appContent -match 'plan-detail-link clickable'
    Add-TestResult -Name 'clickable-cursor-affordance' -Passed $clickableAffordanceValid -Detail 'Static and generated command, navigation, disclosure, row, and option controls share an explicit pointer cursor while unavailable commands retain the normal arrow.'

    $planColumnsValid = $indexContent -match '<col class="plan-column-source">\s*<col class="plan-column-action">' -and $indexContent -match '<th>Source</th>\s*<th>Action</th>' -and $indexContent -match '<th>Controls</th>' -and $appContent -match '<td class="plan-source">' -and $appContent -match '<td class="plan-action">' -and $appContent -match '<tr class="plan-candidate-row clickable"[^>]*tabindex="0"[^>]*data-plan-row=' -and $appContent -match '<span class="candidate-link">' -and $appContent -notmatch '<button class="candidate-link' -and $appContent -match 'function handlePlanRowKeyboardNavigation\(' -and $stylesContent -match '\.plan-candidate-row:hover td,[\s\S]*?background:\s*var\(--accent-soft\)' -and $stylesContent -match '\.plan-table\s*\{[^}]*table-layout:\s*fixed' -and $stylesContent -match '\.plan-table th\s*\{[^}]*white-space:\s*nowrap' -and $stylesContent -match '@media \(max-width: 1180px\)[\s\S]*?\.plan-table\s*\{\s*min-width:\s*900px' -and $stylesContent -match '\.plan-table th:last-child\s*\{[^}]*text-align:\s*center'
    $planColumnsValid = $indexContent -match '<col class="plan-column-source">\s*<col class="plan-column-type">\s*<col class="plan-column-action">' -and $appContent -match 'function renderPlanHeader\(' -and $appContent -match '\["type", "Type", "Type", "How the candidate entered the promotion plan\."\]' -and $appContent -match 'renderSortButton\(column, state\.planSort, \{ "plan-sort": column\[0\] \}\)' -and $appContent -match '<td class="plan-source">\$\{escapeHtml\(formatTitleCase\(candidate\.sourceLabel\)\)\}</td>' -and $appContent -match '<td class="plan-type"><span class="status-badge neutral plan-membership-badge">' -and $appContent -match '<tr class="plan-candidate-row clickable"[^>]*tabindex="0"[^>]*data-plan-row=' -and $appContent -match '<span class="candidate-link">' -and $appContent -match '<span class="plan-candidate-title">' -and $appContent -match 'function handlePlanRowKeyboardNavigation\(' -and $stylesContent -match '\.plan-column-type\s*\{[^}]*width:\s*90px' -and $stylesContent -match '\.plan-table :is\(th, td\):not\(:first-child\):not\(:last-child\)\s*\{[^}]*text-align:\s*center' -and $stylesContent -match '\.plan-table :is\(th, td\):last-child\s*\{[^}]*text-align:\s*left' -and $stylesContent -match '\.plan-table th:first-child \.candidate-sort-button\s*\{[^}]*justify-content:\s*flex-start;[^}]*text-align:\s*left' -and $stylesContent -match '\.plan-candidate-row:hover td,[\s\S]*?background:\s*var\(--accent-soft\)' -and $stylesContent -match '\.plan-table\s*\{[^}]*min-width:\s*1000px;[^}]*table-layout:\s*fixed' -and $stylesContent -match '@media \(max-width: 1180px\)[\s\S]*?\.plan-table\s*\{\s*min-width:\s*900px'
    Add-TestResult -Name 'promotion-plan-column-alignment' -Passed $planColumnsValid -Detail 'Promotion Plan separates Source and sortable Type into eight aligned columns while retaining shared hover, focus, pointer, and keyboard behavior.'

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

    $planTokenDeltaValid = $appContent -match 'function getAssessmentTokenValue\(' -and $appContent -match '!getApplicabilityOverride\(candidate\) \|\| assessment\.guardedTokenDelta !== 0' -and $appContent -match 'estimateGuardedTokens\(decision\.proposedText \|\| candidate\.text\)' -and $appContent -match 'function getCandidateTokenValue\(' -and $appContent -match 'if \(getApplicabilityOverride\(candidate\)\)' -and $appContent -match 'function getPlanTokenValue\(' -and $appContent -match 'function getPlanTokenDisplay\(' -and $appContent -match 'return formatSignedNumber\(getPlanTokenValue\(candidate\)\)' -and $appContent -match 'function getPlanTokenDelta\(' -and $appContent -match 'getAssessmentTokenValue\(candidate, assessment, decision\)' -and $appContent -match 'return -Math\.ceil\(estimatedTokens \* 1\.25\)' -and $appContent -match 'function getPlanAffectedSurfaces\(' -and $appContent -match 'placementSurfaces\.length \? placementSurfaces : assessment\?\.affectedSurfaces' -and $appContent -match '<td class="mono">\$\{cost\}</td>' -and $appContent -match 'token\.textContent = formatCandidateTokenValue\(candidate, assessment\)' -and $appContent -match 'sum \+ getPlanTokenValue\(candidate\)'
    Add-TestResult -Name 'promotion-plan-token-deltas' -Passed $planTokenDeltaValid -Detail 'Token displays and Draft Item Estimate reuse signed action-aware values, including maintained proposed-text estimates for unresolved overrides, while capacity projections wait for an explicit action and Retire retains negative savings.'

    $approvalExportValid = $indexContent -match 'id="approver-name"' -and $indexContent -match 'id="approval-requirements"[^>]*aria-label="Approval requirements"' -and $indexContent -match 'id="approve-export-button"[^>]*disabled' -and $indexContent -match 'Approve &amp; Export' -and $appContent -match 'function autofillApproverName\(' -and $appContent -match '__HOSTED_RULE_WORKBENCH__\?\.maintainerIdentity\?\.login' -and $appContent -match 'function renderApprovalRequirements\(' -and $appContent -match '\["Decision rationales"' -and $appContent -match '\["GitHub identity"' -and $appContent -match 'function getPreviewReadiness' -and $appContent -match 'function buildApprovalPayload' -and $appContent -match 'function approveAndExport' -and $appContent -match 'hosted-rule-workbench-approval-handoff' -and $appContent -match 'sha256-payload-bytes-v1' -and $appContent -match 'crypto\.subtle\.digest\("SHA-256"' -and $appContent -match 'approvedBy:\s*\{\s*type:\s*"manual"' -and $stylesContent -match '\.approval-requirements'
    $approvalExportValid = $approvalExportValid -and $appContent -match '\["Rule actions", readiness\.missingActionCount' -and $appContent -match 'missingActionCount === 0' -and $appContent -match 'status = "needs action"'
    $approvalExportValid = $approvalExportValid -and $appContent -match 'APPROVAL_PAYLOAD_SCHEMA_VERSION = 7'
    Add-TestResult -Name 'preview-approval-export' -Passed $approvalExportValid -Detail 'Preview explains plan, action, rationale, and identity gates and blocks export until every selected candidate has an explicit promotion action and rationale.'

    $previewDiffValid = $indexContent -match 'id="preview-diff"' -and $indexContent -match 'id="preview-payload-diff"' -and $indexContent -match '<details class="preview-raw-payload preview-review-disclosure"' -and $indexContent -match 'Raw Selection Payload' -and $appContent -match 'function renderPreviewChanges\(' -and $appContent -match 'decision\.action === "add"' -and $appContent -match 'decision\.action === "retire"' -and $appContent -match 'function diffTextLines\(' -and $appContent -match 'diff-line \$\{line\.type\}' -and $appContent -match 'function renderPayloadChanges\(' -and $appContent -match 'Object\.keys\(after\)\.filter' -and $appContent -match 'renderPayloadColumn\("Default", beforeLines, "delete"\)' -and $appContent -match 'renderPayloadColumn\("Current", afterLines, "add"\)' -and $appContent -match 'class="payload-line-number"' -and $appContent -match 'class="payload-line-marker"' -and $appContent -match 'class="highlight-width-track"' -and $stylesContent -match '\.highlight-width-track\s*\{[^}]*width:\s*max-content;[^}]*min-width:\s*100%' -and $stylesContent -match '\.diff-line\.add\s*\{[^}]*background:\s*rgb\(14, 42, 31\)' -and $stylesContent -match '\.diff-line\.delete\s*\{[^}]*background:\s*rgb\(54, 26, 33\)' -and $stylesContent -match '\.payload-column\.add \.payload-line\s*\{[^}]*background:\s*rgb\(14, 42, 31\)' -and $stylesContent -match '\.payload-column\.delete \.payload-line\s*\{[^}]*background:\s*rgb\(54, 26, 33\)' -and $stylesContent -match '\.payload-columns\s*\{[^}]*grid-template-columns:\s*minmax\(0, 1fr\) minmax\(0, 1fr\)'
    $previewDiffValid = $previewDiffValid -and $appContent -match 'function renderPreviewEmptyState\(' -and $appContent -match '"diff",\s*"No Payload Changes"' -and $appContent -match '"json",\s*"No Raw Payload Changes"' -and $indexContent -match 'id="preview-raw-heading"' -and $indexContent -match 'id="raw-payload-empty"[^>]*hidden' -and $appContent -match 'elements\["preview-raw-heading"\]\.hidden = !hasChanges' -and $appContent -match 'elements\["raw-payload-empty"\]\.hidden = hasChanges' -and $appContent -match 'elements\["preview-json"\]\.hidden = !hasChanges' -and $stylesContent -match '\.preview-empty-state\s*\{[^}]*min-height:\s*190px' -and $stylesContent -match '#preview-view \.preview-empty-state\s*\{[^}]*background:\s*var\(--paper\)'
    Add-TestResult -Name 'preview-change-review' -Passed $previewDiffValid -Detail 'Preview renders action-aware diffs and side-by-side payload changes, while all zero-change review panes share graphic, title, guidance, and background treatment and Raw suppresses inactive JSON controls.'

    $rawPayloadNavigationValid = $indexContent -match 'id="raw-change-tools"[^>]*hidden' -and $indexContent -match 'id="raw-previous-change"' -and $indexContent -match 'id="raw-next-change"' -and $indexContent -match 'id="raw-change-position"[^>]*aria-live="polite"' -and $indexContent -match 'disclosure-chevron-closed[\s\S]*octicon-chevron-right-12' -and $indexContent -match 'disclosure-chevron-open[\s\S]*octicon-chevron-down-12' -and $appContent -match 'function renderRawPayload\(' -and $appContent -match '\["add", "update"\]\.includes\(decision\.action\) \|\| decision\.applicabilityOverride' -and $appContent -match 'data-raw-change-index=' -and $appContent -match 'preview-json"\]\.textContent !== rawPayload' -and $appContent -match 'function navigateRawPayloadChange\(' -and $appContent -match 'function getRawPayloadChangeViewportPosition\(' -and $appContent -match 'function navigateRawPayloadDirection\(' -and $appContent -match 'addEventListener\("scroll", updateRawPayloadChangeNavigation\)' -and $stylesContent -match '\.raw-json-line\.raw-json-added\s*\{[^}]*background:\s*rgba\(46, 160, 67, 0\.2\)' -and $stylesContent -match '\.raw-json-line\.raw-json-added \.raw-json-line-marker::before\s*\{[^}]*content:\s*"\+"' -and $stylesContent -match '\.disclosure-chevron\s*\{[^}]*color:\s*var\(--muted\)'
    Add-TestResult -Name 'raw-payload-change-navigation' -Passed $rawPayloadNavigationValid -Detail 'Raw selection JSON highlights and navigates complete in-plan Add, Update, and applicability-override records while preserving copyable payload text.'

    $noOpUpdateValid = $appContent -match 'function hasHostedTextChange\(' -and $appContent -match 'if \(hasHostedTextChange\(candidate, proposedText\)\) actions\.push\("update"\)' -and $appContent -match 'Current and proposed Hosted rule text are identical, so Update is unavailable\.' -and $appContent -match 'const allowedActions = getAllowedActions\(candidate, proposedText\)' -and $appContent -match 'inPlan: saved\.inPlan && isPromotionAction\(saved\.action\)'
    $noOpUpdateValid = $appContent -match 'function hasHostedTextChange\(' -and $appContent -match 'if \(hasHostedTextChange\(candidate, proposedText\)\) actions\.push\("update"\)' -and $appContent -match 'Current and proposed Hosted rule text are identical, so Update is unavailable\.' -and $appContent -match 'inPlan: saved\.inPlan,' -and $appContent -match 'const unresolved = candidates\.filter\(\(candidate\) => !isPromotionAction' -and $appContent -match 'Complete Rule Actions from the Promotion Plan'
    Add-TestResult -Name 'no-op-update-suppression' -Passed $noOpUpdateValid -Detail 'Mapped candidates expose Update only for text changes; independent unresolved membership is retained but cannot render or approve as a proposed change.'

    $mobileUnsupportedValid = $indexContent -match 'class="unsupported-brand-lockup"[\s\S]*icons/codicons/sprite\.svg#codicon-json[\s\S]*class="unsupported-product-name">HOSTED COPILOT RULE MANAGER</p>' -and $indexContent -match 'Mobile devices are not supported' -and $indexContent -notmatch 'class="unsupported-mark"[^>]*>HR</span>' -and $appContent -match 'matchMedia\("\(max-width: 767\.98px\)"\)\.matches' -and $appContent -match 'userAgentData\?\.mobile' -and $appContent -match 'mobile-unsupported' -and $stylesContent -match '@media \(max-width: 767\.98px\)' -and $stylesContent -match '\.unsupported-brand-icon\s*\{[^}]*color:\s*#ffff00' -and $stylesContent -match 'html\.mobile-unsupported \.unsupported-device'
    Add-TestResult -Name 'mobile-unsupported-contract' -Passed $mobileUnsupportedValid -Detail 'Mobile detection replaces the Workbench with a laptop-or-desktop requirement.'

    $assessmentLaunchValid = $launcherContent -match 'Invoke-RuleIntakeAssessment\.ps1' -and $launcherContent -match '\$null -eq \$resolvedBundlePath' -and $launcherContent -match '''-CachePath'', \$AssessmentCachePath' -and $launcherContent -match '''-BaselinePath'', \$AssessmentBaselinePath' -and $launcherContent -match '''-Model'', \$AssessmentModel' -and $launcherContent -match '\$assessmentOutputFormat = if \(\$OutputFormat -eq ''Text''\) \{ ''Text'' \} else \{ ''Json'' \}' -and $launcherContent -match "Write-Host '\[RUNNING\].*assessment" -and $launcherContent -match '& pwsh @assessmentArguments 2>&1 \| ForEach-Object \{ Write-Host \$_ \}' -and $launcherContent -match "Write-Host '\[PASSED\].*assessment" -and $launcherContent -match 'Rule intake assessment failed'
    Add-TestResult -Name 'incremental-assessment-launch' -Passed $assessmentLaunchValid -Detail 'Text launches visibly complete candidate assessment before Workbench staging, JSON launches remain machine-readable, and an explicit BundlePath remains a model-free staging path.'

    $serverContractValid = $launcherContent -match '\[Net\.IPAddress\]::Loopback' -and $launcherContent -match '\$allowedHosts = @\("127\.0\.0\.1:\$Port", "localhost:\$Port"\)' -and $launcherContent -match "StatusCode 421 -StatusText 'Misdirected Request'" -and $launcherContent -match 'RandomNumberGenerator.*Fill' -and $launcherContent -match 'CryptographicOperations.*FixedTimeEquals' -and $launcherContent.Contains('$requestUri.AbsolutePath -eq ''/shutdown''') -and $launcherContent -match 'X-Workbench-Shutdown-Token' -and $launcherContent -match "script-src 'self'; style-src 'self'; font-src 'self'; connect-src 'self'" -and $stageResult.readOnly -and (@($stageResult.allowedMethods) -join ',') -eq 'GET,HEAD' -and $stageResult.shutdownEndpoint -eq 'POST /shutdown'
    Add-TestResult -Name 'loopback-read-only-server' -Passed $serverContractValid -Detail 'The server binds to loopback, rejects non-loopback Host values, serves only local runtime assets through GET and HEAD, and exposes one token-authenticated shutdown endpoint.'
    }

    $portProbe = [Net.Sockets.TcpListener]::new([Net.IPAddress]::Loopback, 0)
    $portProbe.Start()
    $shutdownPort = ([Net.IPEndPoint]$portProbe.LocalEndpoint).Port
    $portProbe.Stop()
    $shutdownSiteDirectory = Join-Path $tempRoot 'shutdown-site'
    $serverJob = Start-Job -ScriptBlock {
        param($LauncherPath, $SiteDirectory, $FixtureBundlePath, $Port)
        & pwsh -NoProfile -File $LauncherPath -SiteDirectory $SiteDirectory -BundlePath $FixtureBundlePath -Port $Port -NoLaunch -OutputFormat Json
    } -ArgumentList $launcherPath, $shutdownSiteDirectory, $bundlePath, $shutdownPort
    try {
        $shutdownUrl = "http://127.0.0.1:$shutdownPort"
        $deadline = [DateTimeOffset]::UtcNow.AddSeconds(10)
        $serverReady = $false
        while (-not $serverReady -and [DateTimeOffset]::UtcNow -lt $deadline) {
            try {
                $serverReady = (Invoke-WebRequest -Uri "$shutdownUrl/" -Method Get -SkipHttpErrorCheck).StatusCode -eq 200
            }
            catch { }
        }
        if (-not $serverReady) {
            throw 'loopback test server did not become ready'
        }
        if (Test-ShouldRun -Name 'loopback-host-validation') {
            Start-TestResult -Name 'loopback-host-validation'
            $misdirectedRequest = Invoke-WebRequest -Uri "$shutdownUrl/shutdown-config.js" -Headers @{ Host = 'attacker.example' } -SkipHttpErrorCheck
            $hostValidationValid = $misdirectedRequest.StatusCode -eq 421 -and $misdirectedRequest.Content -eq 'Misdirected Request'
            Add-TestResult -Name 'loopback-host-validation' -Passed $hostValidationValid -Detail 'An unrecognized Host cannot read staged Workbench files or the per-launch shutdown token through DNS rebinding.'
        }
        $nodeExecutable = (Get-Command node -ErrorAction Stop).Source
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
        if (-not $behaviorManifestValid -and ([string]::IsNullOrWhiteSpace($Run) -or $Run -in @('browser-playwright-journeys', 'browser-framework-coverage'))) {
            throw 'Workbench browser behavior manifest is invalid'
        }
        if ([string]::IsNullOrWhiteSpace($Run) -or $Run -in @('browser-playwright-journeys', 'browser-framework-coverage')) {
            if (Test-ShouldRun -Name 'browser-playwright-journeys') { Start-TestResult -Name 'browser-playwright-journeys' }
            $playwrightOutput = @(& $nodeExecutable $playwrightRunnerPath $shutdownUrl 2>&1)
            $playwrightExitCode = $LASTEXITCODE
            $playwrightResult = if ($playwrightExitCode -eq 0) { ($playwrightOutput | Out-String) | ConvertFrom-Json } else { $null }
            $playwrightValid = $playwrightExitCode -eq 0 -and $playwrightResult.status -eq 'passed' -and $playwrightResult.harness -eq 'playwright' -and $playwrightResult.journeyCount -eq $journeyPaths.Count -and $playwrightResult.behaviorCount -eq $behaviorIds.Count -and $playwrightResult.assertionCount -gt 0 -and $playwrightResult.viewportAssertionCount -gt 0 -and $playwrightResult.viewportCount -eq 9
            if (Test-ShouldRun -Name 'browser-playwright-journeys') {
                Add-TestResult -Name 'browser-playwright-journeys' -Passed $playwrightValid -Detail $(if ($playwrightExitCode -eq 0) { "Passed $($playwrightResult.assertionCount) assertions across $($playwrightResult.journeyCount) Playwright journeys covering $($playwrightResult.behaviorCount) behavior IDs." } else { ($playwrightOutput | Out-String).Trim() })
            }
        }
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
        if (Test-ShouldRun -Name 'browser-framework-coverage') {
            $browserCoverageValid = $playwrightValid -and $layoutValid -and $playwrightResult.viewportCount -eq $layoutTestResult.viewportCount -and $playwrightResult.viewportAssertionCount -eq $layoutTestResult.assertionCount
            Add-TestResult -Name 'browser-framework-coverage' -Passed $browserCoverageValid -Detail "Playwright and Puppeteer each passed $($layoutTestResult.assertionCount) current-behavior assertions across $($layoutTestResult.viewportCount) viewport boundaries."
        }
        $shutdownConfigContent = Get-Content -LiteralPath (Join-Path $shutdownSiteDirectory 'shutdown-config.js') -Raw
        if ($shutdownConfigContent -notmatch '"shutdownToken":"(?<token>[0-9a-f]{64})"') {
            throw 'staged shutdown token was not found'
        }
        $shutdownToken = [string]$Matches['token']
        if (Test-ShouldRun -Name 'authenticated-server-shutdown') {
            Start-TestResult -Name 'authenticated-server-shutdown'
            $unauthorizedShutdown = Invoke-WebRequest -Uri "$shutdownUrl/shutdown" -Method Post -SkipHttpErrorCheck
            $unrelatedPost = Invoke-WebRequest -Uri "$shutdownUrl/" -Method Post -Headers @{ 'X-Workbench-Shutdown-Token' = $shutdownToken } -SkipHttpErrorCheck
        }
        $authorizedShutdown = Invoke-WebRequest -Uri "$shutdownUrl/shutdown" -Method Post -Headers @{ 'X-Workbench-Shutdown-Token' = $shutdownToken } -SkipHttpErrorCheck
        $completedJob = Wait-Job -Job $serverJob -Timeout 10
        if (Test-ShouldRun -Name 'authenticated-server-shutdown') {
            $shutdownLifecycleValid = $unauthorizedShutdown.StatusCode -eq 403 -and $unrelatedPost.StatusCode -eq 405 -and $authorizedShutdown.StatusCode -eq 200 -and $null -ne $completedJob -and $serverJob.State -eq 'Completed'
            Add-TestResult -Name 'authenticated-server-shutdown' -Passed $shutdownLifecycleValid -Detail 'Only the per-launch token can stop the loopback server; unauthorized shutdown and unrelated POST requests remain rejected.'
        }
        elseif ($authorizedShutdown.StatusCode -ne 200 -or $null -eq $completedJob -or $serverJob.State -ne 'Completed') {
            throw 'Focused Workbench validation could not stop its owned server cleanly'
        }
    }
    finally {
        if ($serverJob.State -notin @('Completed', 'Failed', 'Stopped')) {
            Stop-Job -Job $serverJob
        }
        Remove-Job -Job $serverJob -Force
    }

    if ([string]::IsNullOrWhiteSpace($Run)) {
        $repositorySiteDirectory = Join-Path $repositoryRoot 'hosted_copilot/workbench/staged-test'
        Start-TestResult -Name 'repository-staging-rejected'
        $rejectedOutput = @(& pwsh -NoProfile -File $launcherPath -SiteDirectory $repositorySiteDirectory -BundlePath $bundlePath -StageOnly -NoLaunch -OutputFormat Json 2>&1)
        $repositoryStagingRejected = $LASTEXITCODE -ne 0 -and -not (Test-Path -LiteralPath $repositorySiteDirectory)
        Add-TestResult -Name 'repository-staging-rejected' -Passed $repositoryStagingRejected -Detail 'The launcher rejects generated staging output inside the source repository.'
    }
    }
}
catch {
    $issues.Add($_.Exception.Message)
    if ($OutputFormat -eq 'Text') {
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
}

if ($OutputFormat -eq 'Json') {
    $result | ConvertTo-Json -Depth 6
}
else {
    Write-ValidationSectionHeader -Title 'Hosted Rule Workbench test summary'
    Write-ValidationSummary -Fields ([ordered]@{
        Status = $result.status.ToUpperInvariant()
        Tests = $result.testCount
        Passed = $result.passedCount
        Failed = $result.failedCount
    })
    if ($issues.Count -gt 0) {
        Write-ValidationSectionHeader -Title 'Issues'
        foreach ($issue in $issues) {
            Write-Output "  - $issue"
        }
    }
    Complete-ValidationTextOutput
}

if ($result.status -eq 'failed') {
    exit 1
}
