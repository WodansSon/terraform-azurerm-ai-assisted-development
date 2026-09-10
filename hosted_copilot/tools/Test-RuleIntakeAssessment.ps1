[CmdletBinding()]
param(
    [ValidateSet('Text', 'Json')]
    [string]$OutputFormat = 'Text'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$validationOutputModulePath = Join-Path $PSScriptRoot '../../tools/ValidationOutput.psm1'
Import-Module -Name $validationOutputModulePath -Force

$assessmentPath = Join-Path $PSScriptRoot 'Invoke-RuleIntakeAssessment.ps1'
$baselinePublisherPath = Join-Path $PSScriptRoot 'Publish-RuleIntakeAssessmentBaseline.ps1'
$bundleSchemaPath = Join-Path $PSScriptRoot '../copilot-rule-catalog/rule-intake-review.schema.json'
$baselineSchemaPath = Join-Path $PSScriptRoot '../copilot-rule-catalog/rule-assessments/assessment-baseline.schema.json'
$repositoryRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
$tempRoot = Join-Path ([IO.Path]::GetTempPath()) ("hosted-rule-assessment-test-{0}" -f [Guid]::NewGuid().ToString('N'))
$results = New-Object 'System.Collections.Generic.List[object]'
$issues = New-Object 'System.Collections.Generic.List[string]'

function Add-TestResult {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][bool]$Passed,
        [Parameter(Mandatory = $true)][string]$Detail
    )

    $results.Add([pscustomobject]@{
        name = $Name
        status = if ($Passed) { 'passed' } else { 'failed' }
        detail = $Detail
    })
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

function Write-Bundle {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$SecondHash
    )

    $reports = @(
        New-CapacityReport -Name 'repository' -Kind 'file'
        New-CapacityReport -Name 'go' -Kind 'file'
        New-CapacityReport -Name 'test' -Kind 'file'
        New-CapacityReport -Name 'documentation' -Kind 'file'
        New-CapacityReport -Name 'skill' -Kind 'file'
        New-CapacityReport -Name 'go-combined' -Kind 'combined'
        New-CapacityReport -Name 'test-combined' -Kind 'combined'
        New-CapacityReport -Name 'documentation-combined' -Kind 'combined'
    )
    $candidates = @(
        [ordered]@{
            id = 'REVIEW-CLASS-001'
            title = 'Issues identify actual problems'
            contractPath = '.github/instructions/code-review-compliance-contract.instructions.md'
            sourceStatus = 'active'
            contentSha256 = 'd' * 64
            provenance = 'published-upstream-standard'
            evidence = @('fixture-evidence')
            sourceIds = @('fixture-source')
            ruleText = 'Report only evidence-backed defects as Issues.'
            state = 'new'
            requiresReview = $true
            changeReasons = @('no-ledger-decision')
            priorDecision = $null
            relatedHostedRules = @()
        },
        [ordered]@{
            id = 'REVIEW-CLASS-002'
            title = 'Observations are non-blocking'
            contractPath = '.github/instructions/code-review-compliance-contract.instructions.md'
            sourceStatus = 'active'
            contentSha256 = $SecondHash
            provenance = 'local-safeguard'
            evidence = @('fixture-evidence')
            sourceIds = @()
            ruleText = 'Keep non-blocking commentary outside the Issue set.'
            state = 'new'
            requiresReview = $true
            changeReasons = @('no-ledger-decision')
            priorDecision = $null
            relatedHostedRules = @()
        }
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
            maintainer = [ordered]@{ directoryPath = 'hosted_copilot/copilot-rule-catalog/maintainer-rules'; sourceSha256 = 'd' * 64 }
        }
        summary = [ordered]@{
            upstreamSourceCount = 0
            changedUpstreamCount = 0
            interactiveRuleCount = 2
            interactiveReviewCount = 2
            interactiveCurrentCount = 0
            interactiveStateCounts = [ordered]@{ new = 2; changed = 0; retired = 0; deferred = 0; current = 0 }
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
            reports = $reports
        }
        hostedRules = @()
        upstreamCandidates = @()
        interactiveCandidates = $candidates
        maintainerCandidates = @()
    }
    [IO.File]::WriteAllText($Path, ($bundle | ConvertTo-Json -Depth 20) + "`n", [Text.UTF8Encoding]::new($false))
}

function Invoke-Assessment {
    param(
        [Parameter(Mandatory = $true)][string]$InputPath,
        [Parameter(Mandatory = $true)][string]$OutputPath,
        [Parameter(Mandatory = $true)][string]$CachePath,
        [string]$BaselinePath = (Join-Path $tempRoot 'absent-baseline.json'),
        [int]$BatchSize = 1,
        [int]$MaxRetries = 0,
        [switch]$RepairMissingFields
    )

    $arguments = @('-NoProfile', '-File', $assessmentPath, '-BundlePath', $InputPath, '-OutputPath', $OutputPath, '-CachePath', $CachePath, '-EvaluatorScriptPath', $fakeEvaluatorPath, '-BatchSize', $BatchSize, '-MaxRetries', $MaxRetries, '-OutputFormat', 'Json')
    $arguments += @('-BaselinePath', $BaselinePath)
    if ($RepairMissingFields) {
        $arguments += '-RepairMissingFields'
    }
    $output = @(& pwsh @arguments 2>&1)
    if ($LASTEXITCODE -ne 0) {
        throw (($output | Out-String).Trim())
    }
    return (($output | Out-String) | ConvertFrom-Json)
}

try {
    New-Item -ItemType Directory -Path $tempRoot -Force | Out-Null
    $assessmentContent = Get-Content -LiteralPath $assessmentPath -Raw
    $constrainedEvaluatorValid = $assessmentContent -match '--available-tools=view' -and $assessmentContent -match '--output-format json' -and $assessmentContent -match '--disallow-temp-dir' -and $assessmentContent -match '-C \$batchDirectory' -and $assessmentContent -match '\$assistantMessage\.model -ne \$Model' -and $assessmentContent -match 'field-level migration of existing semantic assessments' -and $assessmentContent -notmatch '--allow-all|--allow-all-tools|--allow-all-paths|--yolo'
    Add-TestResult -Name 'copilot-evaluator-constrained' -Passed $constrainedEvaluatorValid -Detail 'Real Copilot assessment uses structured output and an isolated batch directory with only the read-only view tool exposed.'

    $bundlePath = Join-Path $tempRoot 'bundle.json'
    $changedBundlePath = Join-Path $tempRoot 'changed-bundle.json'
    $cachePath = Join-Path $tempRoot 'cache.json'
    $callLogPath = Join-Path $tempRoot 'calls.log'
    $fakeEvaluatorPath = Join-Path $tempRoot 'Fake-Evaluator.ps1'
    $fakeCollectorPath = Join-Path $tempRoot 'Fake-Collector.ps1'
    $fakeEvaluator = @'
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$BatchPath,
    [Parameter(Mandatory = $true)][string]$CatalogPath,
    [Parameter(Mandatory = $true)][string]$SchemaPath,
    [Parameter(Mandatory = $true)][string]$OutputPath,
    [Parameter(Mandatory = $true)][string]$Model,
    [Parameter(Mandatory = $true)][string]$ReasoningEffort
)
$batch = Get-Content -LiteralPath $BatchPath -Raw | ConvertFrom-Json
Add-Content -LiteralPath $env:FAKE_EVALUATOR_CALL_LOG -Value "$($batch.batchId):$($batch.sourceType):$($batch.candidateCount)"
if ($env:FAKE_EVALUATOR_ALWAYS_FAIL -eq '1') {
    [IO.File]::WriteAllText($OutputPath, "{invalid`n", [Text.UTF8Encoding]::new($false))
    return
}
if (-not [string]::IsNullOrWhiteSpace($env:FAKE_EVALUATOR_FAIL_ONCE) -and (Test-Path -LiteralPath $env:FAKE_EVALUATOR_FAIL_ONCE -PathType Leaf)) {
    Remove-Item -LiteralPath $env:FAKE_EVALUATOR_FAIL_ONCE -Force
    [IO.File]::WriteAllText($OutputPath, "{invalid`n", [Text.UTF8Encoding]::new($false))
    return
}
$records = if ($batch.mode -eq 'repair') {
    @($batch.candidates | ForEach-Object {
        $packet = $_
        [ordered]@{
            id = $packet.candidate.id
            repairs = @($packet.repairRequests | ForEach-Object {
                $request = $_
                $existing = @($packet.existingAssessments | Where-Object assessmentId -eq $request.assessmentId)[0]
                $proposedIdFamily = (($packet.candidate.id -replace '[^A-Za-z0-9]+', '-').ToUpperInvariant()).Trim('-')
                if ($proposedIdFamily.Length -gt 23) {
                    $proposedIdFamily = $proposedIdFamily.Substring(0, 23).TrimEnd('-')
                }
                [ordered]@{
                    assessmentId = $request.assessmentId
                    proposedHostedRuleId = if ([string]::IsNullOrWhiteSpace([string]$existing.targetHostedRuleId)) { "REPAIR-$proposedIdFamily-001" } else { [string]$existing.targetHostedRuleId }
                    proposedText = "Apply repaired $($request.assessmentId) guidance during Hosted review."
                    hostedCategory = 'review-classification-and-evidence'
                    affectedSurfaces = @('review-skill')
                }
            })
        }
    })
}
else {
    @($batch.candidates | ForEach-Object {
    $applicable = $_.id -ne 'REVIEW-CLASS-002'
    $proposedIdFamily = (($_.id -replace '[^A-Za-z0-9]+', '-').ToUpperInvariant()).Trim('-')
    if ($proposedIdFamily.Length -gt 23) {
        $proposedIdFamily = $proposedIdFamily.Substring(0, 23).TrimEnd('-')
    }
    $affectedSurfaces = @('review-skill')
    [ordered]@{
        id = $_.id
        assessments = @(
            [ordered]@{
                assessmentId = $_.id
                title = $_.title
                candidateState = $_.state
                targetHostedRuleId = $null
                proposedHostedRuleId = "CAND-$proposedIdFamily-001"
                hostedApplicable = $applicable
                applicabilityRationale = if ($applicable) { "Rule $($_.id) controls native Hosted review findings." } else { "Rule $($_.id) is workflow commentary outside native Hosted review." }
                hostedCategory = 'review-classification-and-evidence'
                recommendation = if ($applicable) { 'add' } else { 'exclude' }
                summary = "Candidate-specific assessment for $($_.id)."
                impactDescription = "Candidate $($_.id) has independently evaluated review impact."
                currentHostedCoverage = "Candidate $($_.id) was compared with the current Hosted catalog."
                affectedSurfaces = $affectedSurfaces
                guardedTokenDelta = if ($applicable) { 12 } else { 0 }
                proposedText = "Apply $($_.id) during Hosted review."
                selectionFactors = [ordered]@{
                    severity = if ($applicable) { 4 } else { 1 }
                    frequency = 3
                    breadth = if ($applicable) { 4 } else { 1 }
                    hostedDetectability = if ($applicable) { 5 } else { 0 }
                    evidenceStrength = 4
                    falsePositiveRisk = if ($applicable) { 1 } else { 4 }
                    redundancy = 1
                }
                selectionRationale = "Severity, frequency, breadth, detectability, evidence, false-positive risk, and redundancy were independently scored for $($_.id)."
            }
        )
    }
    })
}
[IO.File]::WriteAllText($OutputPath, ($records | ConvertTo-Json -Depth 12) + "`n", [Text.UTF8Encoding]::new($false))
'@
    [IO.File]::WriteAllText($fakeEvaluatorPath, $fakeEvaluator, [Text.UTF8Encoding]::new($false))
    $fakeCollector = @'
[CmdletBinding()]
param(
    [string]$RepositoryRoot,
    [Parameter(Mandatory = $true)][string]$OutputPath,
    [ValidateSet('Text', 'Json')][string]$OutputFormat = 'Text'
)
$outputDirectory = Split-Path -Parent $OutputPath
if (-not (Test-Path -LiteralPath $outputDirectory -PathType Container)) {
    New-Item -ItemType Directory -Path $outputDirectory -Force | Out-Null
}
Copy-Item -LiteralPath $env:FAKE_COLLECTOR_BUNDLE -Destination $OutputPath -Force
if ($OutputFormat -eq 'Json') {
    Get-Content -LiteralPath $OutputPath -Raw
}
else {
    Write-Output 'Fake collector wrote the requested bundle.'
}
'@
    [IO.File]::WriteAllText($fakeCollectorPath, $fakeCollector, [Text.UTF8Encoding]::new($false))
    $env:FAKE_EVALUATOR_CALL_LOG = $callLogPath
    $env:FAKE_EVALUATOR_FAIL_ONCE = ''
    $env:FAKE_EVALUATOR_ALWAYS_FAIL = ''
    $env:FAKE_COLLECTOR_BUNDLE = $bundlePath

    Write-Bundle -Path $bundlePath -SecondHash ('e' * 64)
    $firstOutputPath = Join-Path $tempRoot 'first-assessed.json'
    $first = Invoke-Assessment -InputPath $bundlePath -OutputPath $firstOutputPath -CachePath $cachePath
    $firstCalls = @(Get-Content -LiteralPath $callLogPath)
    $firstBundleContent = Get-Content -LiteralPath $firstOutputPath -Raw
    Add-TestResult -Name 'initial-assessment-batches' -Passed ($first.candidateCount -eq 2 -and $first.evaluatedCount -eq 2 -and $first.cacheHitCount -eq 0 -and $first.batchCount -eq 2 -and $firstCalls.Count -eq 2) -Detail 'Initial cache misses are assessed in bounded batches through the injected evaluator.'
    Add-TestResult -Name 'assessed-bundle-schema-valid' -Passed ([bool]($firstBundleContent | Test-Json -SchemaFile $bundleSchemaPath -ErrorAction Stop)) -Detail 'The merged assessment output satisfies the complete read-only bundle schema.'

    $baselineRoot = Join-Path $tempRoot 'baseline'
    New-Item -ItemType Directory -Path $baselineRoot -Force | Out-Null
    $baselinePath = Join-Path $baselineRoot 'assessment-baseline.json'
    $baselinePreviewOutput = @(& pwsh -NoProfile -File $baselinePublisherPath -BundlePath $firstOutputPath -BaselinePath $baselinePath -OutputFormat Json 2>&1)
    $baselinePreviewExitCode = $LASTEXITCODE
    $baselinePreview = if ($baselinePreviewExitCode -eq 0) { ($baselinePreviewOutput | Out-String) | ConvertFrom-Json } else { $null }
    Add-TestResult -Name 'baseline-publication-preview-read-only' -Passed ($baselinePreviewExitCode -eq 0 -and -not $baselinePreview.published -and $baselinePreview.entryCount -eq 2 -and -not (Test-Path -LiteralPath $baselinePath)) -Detail 'Baseline publication validates and previews assessed records without writing unless Publish is explicit.'

    $baselinePublishOutput = @(& pwsh -NoProfile -File $baselinePublisherPath -BundlePath $firstOutputPath -BaselinePath $baselinePath -Publish -OutputFormat Json 2>&1)
    $baselinePublishExitCode = $LASTEXITCODE
    $baselinePublish = if ($baselinePublishExitCode -eq 0) { ($baselinePublishOutput | Out-String) | ConvertFrom-Json } else { $null }
    $baselineContent = if (Test-Path -LiteralPath $baselinePath -PathType Leaf) { Get-Content -LiteralPath $baselinePath -Raw } else { '' }
    Add-TestResult -Name 'baseline-publication-valid' -Passed ($baselinePublishExitCode -eq 0 -and $baselinePublish.published -and $baselinePublish.entryCount -eq 2 -and [bool]($baselineContent | Test-Json -SchemaFile $baselineSchemaPath -ErrorAction Stop)) -Detail 'Explicit publication writes a compact schema-valid source- and catalog-bound assessment baseline.'

    $baselineReuseLogPath = Join-Path $baselineRoot 'reuse-calls.log'
    $env:FAKE_EVALUATOR_CALL_LOG = $baselineReuseLogPath
    $baselineReuse = Invoke-Assessment -InputPath $bundlePath -OutputPath (Join-Path $baselineRoot 'reused.json') -CachePath (Join-Path $baselineRoot 'empty-cache.json') -BaselinePath $baselinePath
    $baselineReuseCalls = @(if (Test-Path -LiteralPath $baselineReuseLogPath -PathType Leaf) { Get-Content -LiteralPath $baselineReuseLogPath })
    Add-TestResult -Name 'fresh-machine-reuses-baseline' -Passed ($baselineReuse.baselineHitCount -eq 2 -and $baselineReuse.cacheHitCount -eq 0 -and $baselineReuse.evaluatedCount -eq 0 -and $baselineReuse.batchCount -eq 0 -and $baselineReuseCalls.Count -eq 0) -Detail 'A machine with no local cache receives every unchanged assessment from the committed baseline without invoking an evaluator.'

    $repairRoot = Join-Path $tempRoot 'field-repair'
    New-Item -ItemType Directory -Path $repairRoot -Force | Out-Null
    $legacyBaselinePath = Join-Path $repairRoot 'legacy-baseline.json'
    $legacyBaseline = $baselineContent | ConvertFrom-Json
    $legacyAssessment = @($legacyBaseline.entries | Where-Object id -eq 'REVIEW-CLASS-002')[0].assessments[0]
    $preservedSelectionRationale = [string]$legacyAssessment.selectionRationale
    $legacyAssessment.proposedHostedRuleId = $null
    $legacyAssessment.proposedText = ''
    $legacyAssessment.hostedCategory = 'not-applicable'
    $legacyAssessment.affectedSurfaces = @()
    [IO.File]::WriteAllText($legacyBaselinePath, ($legacyBaseline | ConvertTo-Json -Depth 30) + "`n", [Text.UTF8Encoding]::new($false))
    $repairLogPath = Join-Path $repairRoot 'calls.log'
    $repairOutputPath = Join-Path $repairRoot 'repaired.json'
    $env:FAKE_EVALUATOR_CALL_LOG = $repairLogPath
    $repair = Invoke-Assessment -InputPath $bundlePath -OutputPath $repairOutputPath -CachePath (Join-Path $repairRoot 'cache.json') -BaselinePath $legacyBaselinePath -BatchSize 20 -RepairMissingFields
    $repairedBundleContent = Get-Content -LiteralPath $repairOutputPath -Raw
    $repairedBundle = $repairedBundleContent | ConvertFrom-Json
    $repairedAssessment = @($repairedBundle.interactiveCandidates | Where-Object id -eq 'REVIEW-CLASS-002')[0].assessments[0]
    $repairCalls = @(Get-Content -LiteralPath $repairLogPath)
    $smartRepairPassed = $repair.repairCandidateCount -eq 1 -and
        $repair.repairedCount -eq 1 -and
        $repair.evaluatedCount -eq 0 -and
        $repair.repairBatchCount -eq 1 -and
        $repair.fullBatchCount -eq 0 -and
        $repair.baselineHitCount -eq 1 -and
        $repairCalls.Count -eq 1 -and
        $repairedAssessment.recommendation -eq 'exclude' -and
        $repairedAssessment.selectionRationale -eq $preservedSelectionRationale -and
        -not [string]::IsNullOrWhiteSpace([string]$repairedAssessment.proposedHostedRuleId) -and
        -not [string]::IsNullOrWhiteSpace([string]$repairedAssessment.proposedText) -and
        [bool]($repairedBundleContent | Test-Json -SchemaFile $bundleSchemaPath -ErrorAction Stop)
    Add-TestResult -Name 'missing-fields-repaired-only' -Passed $smartRepairPassed -Detail 'Smart assessment repairs only missing proposal fields, preserves existing semantic judgments, reuses complete baseline records, and performs no full reassessment.'

    $invalidCacheRecoveryPassed = $true
    foreach ($invalidCacheCase in @(
        [pscustomobject]@{ name = 'legacy'; content = '{"schemaVersion":1,"entries":[]}' },
        [pscustomobject]@{ name = 'malformed'; content = '{invalid' }
    )) {
        $invalidCachePath = Join-Path $baselineRoot "$($invalidCacheCase.name)-cache.json"
        $invalidCacheLogPath = Join-Path $baselineRoot "$($invalidCacheCase.name)-cache-calls.log"
        [IO.File]::WriteAllText($invalidCachePath, $invalidCacheCase.content, [Text.UTF8Encoding]::new($false))
        $env:FAKE_EVALUATOR_CALL_LOG = $invalidCacheLogPath
        try {
            $invalidCacheReuse = Invoke-Assessment -InputPath $bundlePath -OutputPath (Join-Path $baselineRoot "$($invalidCacheCase.name)-cache-reused.json") -CachePath $invalidCachePath -BaselinePath $baselinePath
            $recoveredCache = Get-Content -LiteralPath $invalidCachePath -Raw | ConvertFrom-Json
            $invalidCacheCalls = @(if (Test-Path -LiteralPath $invalidCacheLogPath -PathType Leaf) { Get-Content -LiteralPath $invalidCacheLogPath })
            $invalidCacheRecoveryPassed = $invalidCacheRecoveryPassed -and $invalidCacheReuse.cacheReset -and $invalidCacheReuse.baselineHitCount -eq 2 -and $invalidCacheReuse.evaluatedCount -eq 0 -and $invalidCacheReuse.batchCount -eq 0 -and $invalidCacheCalls.Count -eq 0 -and $recoveredCache.schemaVersion -eq 2 -and @($recoveredCache.entries).Count -eq 0
        }
        catch {
            $invalidCacheRecoveryPassed = $false
        }
    }
    Add-TestResult -Name 'invalid-local-cache-recovered' -Passed $invalidCacheRecoveryPassed -Detail 'Legacy and malformed disposable caches are atomically reset before the committed baseline is reused without invoking an evaluator.'

    $env:FAKE_EVALUATOR_CALL_LOG = $callLogPath
    $cachedOutputPath = Join-Path $tempRoot 'cached-assessed.json'
    $cached = Invoke-Assessment -InputPath $bundlePath -OutputPath $cachedOutputPath -CachePath $cachePath
    $cachedCalls = @(Get-Content -LiteralPath $callLogPath)
    Add-TestResult -Name 'unchanged-assessments-reused' -Passed ($cached.cacheHitCount -eq 2 -and $cached.evaluatedCount -eq 0 -and $cached.batchCount -eq 0 -and $cachedCalls.Count -eq 2) -Detail 'Unchanged source, catalog, evaluator contract, model, and reasoning settings reuse all cached assessments.'

    $collectorRoot = Join-Path $tempRoot 'collector'
    New-Item -ItemType Directory -Path $collectorRoot -Force | Out-Null
    $collectorOutputPath = Join-Path $collectorRoot 'assessed.json'
    $collectorCachePath = Join-Path $collectorRoot 'cache.json'
    $collectorLogPath = Join-Path $collectorRoot 'calls.log'
    $env:FAKE_EVALUATOR_CALL_LOG = $collectorLogPath
    $collectorOutput = @(& pwsh -NoProfile -File $assessmentPath -CollectorScriptPath $fakeCollectorPath -BaselinePath (Join-Path $tempRoot 'absent-baseline.json') -OutputPath $collectorOutputPath -CachePath $collectorCachePath -EvaluatorScriptPath $fakeEvaluatorPath -BatchSize 2 -OutputFormat Json 2>&1)
    $collectorExitCode = $LASTEXITCODE
    $collectorResult = if ($collectorExitCode -eq 0) { ($collectorOutput | Out-String) | ConvertFrom-Json } else { $null }
    Add-TestResult -Name 'collector-file-handoff' -Passed ($collectorExitCode -eq 0 -and $collectorResult.evaluatedCount -eq 2 -and $collectorResult.batchCount -eq 1 -and (Test-Path -LiteralPath $collectorOutputPath -PathType Leaf)) -Detail 'Default collection writes and reads a temporary bundle file instead of transporting large JSON through stdout.'

    $mixedRoot = Join-Path $tempRoot 'mixed-source'
    New-Item -ItemType Directory -Path $mixedRoot -Force | Out-Null
    $mixedBundlePath = Join-Path $mixedRoot 'bundle.json'
    $mixedBundle = Get-Content -LiteralPath $bundlePath -Raw | ConvertFrom-Json
    $mixedBundle.upstreamCandidates = @([pscustomobject]@{
        id = 'reference-documentation-standards'
        title = 'Documentation Standards'
        referenceUrl = 'https://example.invalid/documentation-standards'
        baselineSha256 = '1' * 64
        currentSha256 = '2' * 64
        state = 'changed'
        requiresReview = $true
        affectedHostedRuleIds = @()
        relatedHostedRules = @()
        baselineContent = 'Old guidance.'
        currentContent = 'Current guidance.'
    })
    $mixedBundle.maintainerCandidates = @([pscustomobject]@{
        id = 'DOCS-MAINT-001'
        title = 'Maintainer proposal'
        sourcePath = 'hosted_copilot/copilot-rule-catalog/maintainer-rules/documentation.rules.md'
        surface = 'documentation'
        sourceStatus = 'active'
        contentSha256 = '3' * 64
        provenance = 'confirmed-maintainer-convention'
        rationale = 'The maintainer confirmed this documentation review requirement.'
        ruleText = 'Flag documentation that omits a required maintainer convention.'
        state = 'new'
        requiresReview = $true
        relatedHostedRules = @()
    })
    $mixedBundle.summary.upstreamSourceCount = 1
    $mixedBundle.summary.changedUpstreamCount = 1
    $mixedBundle.summary.maintainerRuleCount = 1
    $mixedBundle.summary.maintainerReviewCount = 1
    $mixedBundle.summary.maintainerStateCounts.new = 1
    [IO.File]::WriteAllText($mixedBundlePath, ($mixedBundle | ConvertTo-Json -Depth 20) + "`n", [Text.UTF8Encoding]::new($false))
    $mixedLogPath = Join-Path $mixedRoot 'calls.log'
    $env:FAKE_EVALUATOR_CALL_LOG = $mixedLogPath
    $mixedAssessedPath = Join-Path $mixedRoot 'assessed.json'
    $mixedResult = Invoke-Assessment -InputPath $mixedBundlePath -OutputPath $mixedAssessedPath -CachePath (Join-Path $mixedRoot 'cache.json') -BatchSize 50
    $mixedCalls = @(Get-Content -LiteralPath $mixedLogPath)
    Add-TestResult -Name 'source-types-batched-separately' -Passed ($mixedResult.evaluatedCount -eq 4 -and $mixedResult.batchCount -eq 3 -and $mixedCalls.Count -eq 3 -and $mixedCalls[0] -match ':interactive:2$' -and $mixedCalls[1] -match ':maintainer:1$' -and $mixedCalls[2] -match ':upstream:1$') -Detail 'Interactive, maintainer, and upstream candidates remain in separate evaluator batches even when the configured batch size could contain all three source types.'
    $mixedBaselineOutput = @(& pwsh -NoProfile -File $baselinePublisherPath -BundlePath $mixedAssessedPath -BaselinePath (Join-Path $mixedRoot 'baseline.json') -OutputFormat Json 2>&1)
    $mixedBaselineResult = if ($LASTEXITCODE -eq 0) { ($mixedBaselineOutput | Out-String) | ConvertFrom-Json } else { $null }
    Add-TestResult -Name 'maintainer-baseline-publication' -Passed ($null -ne $mixedBaselineResult -and $mixedBaselineResult.maintainerCount -eq 1 -and $mixedBaselineResult.entryCount -eq 4) -Detail 'Baseline publication generates a hash-bound maintainer assessment entry from the assessed bundle.'

    $emptyUpstreamBundlePath = Join-Path $mixedRoot 'empty-upstream-assessed.json'
    $emptyUpstreamBundle = Get-Content -LiteralPath $mixedAssessedPath -Raw | ConvertFrom-Json
    $emptyUpstreamBundle.upstreamCandidates[0].assessments = @()
    [IO.File]::WriteAllText($emptyUpstreamBundlePath, ($emptyUpstreamBundle | ConvertTo-Json -Depth 30) + "`n", [Text.UTF8Encoding]::new($false))
    $emptyUpstreamBaselinePath = Join-Path $mixedRoot 'empty-upstream-baseline.json'
    $emptyUpstreamPublishOutput = @(& pwsh -NoProfile -File $baselinePublisherPath -BundlePath $emptyUpstreamBundlePath -BaselinePath $emptyUpstreamBaselinePath -Publish -OutputFormat Json 2>&1)
    $emptyUpstreamPublishExitCode = $LASTEXITCODE
    $emptyUpstreamLogPath = Join-Path $mixedRoot 'empty-upstream-calls.log'
    $env:FAKE_EVALUATOR_CALL_LOG = $emptyUpstreamLogPath
    $emptyUpstreamReuse = if ($emptyUpstreamPublishExitCode -eq 0) { Invoke-Assessment -InputPath $mixedBundlePath -OutputPath (Join-Path $mixedRoot 'empty-upstream-reused.json') -CachePath (Join-Path $mixedRoot 'empty-upstream-cache.json') -BaselinePath $emptyUpstreamBaselinePath -BatchSize 50 } else { $null }
    $emptyUpstreamCalls = @(if (Test-Path -LiteralPath $emptyUpstreamLogPath -PathType Leaf) { Get-Content -LiteralPath $emptyUpstreamLogPath })
    Add-TestResult -Name 'empty-upstream-assessment-reused' -Passed ($emptyUpstreamPublishExitCode -eq 0 -and $emptyUpstreamReuse.baselineHitCount -eq 4 -and $emptyUpstreamReuse.evaluatedCount -eq 0 -and $emptyUpstreamReuse.batchCount -eq 0 -and $emptyUpstreamCalls.Count -eq 0) -Detail 'A schema-valid upstream source with no enforceable rules remains a resolved empty assessment set and does not invoke the evaluator.'

    $env:FAKE_EVALUATOR_CALL_LOG = $callLogPath
    Write-Bundle -Path $changedBundlePath -SecondHash ('f' * 64)
    $changedOutputPath = Join-Path $tempRoot 'changed-assessed.json'
    $changed = Invoke-Assessment -InputPath $changedBundlePath -OutputPath $changedOutputPath -CachePath $cachePath
    $changedCalls = @(Get-Content -LiteralPath $callLogPath)
    Add-TestResult -Name 'changed-rule-reassessed-only' -Passed ($changed.cacheHitCount -eq 1 -and $changed.evaluatedCount -eq 1 -and $changed.batchCount -eq 1 -and $changedCalls.Count -eq 3) -Detail 'Changing one source-content hash invalidates and reassesses only that candidate.'

    $baselineChangedLogPath = Join-Path $baselineRoot 'changed-calls.log'
    $env:FAKE_EVALUATOR_CALL_LOG = $baselineChangedLogPath
    $baselineChanged = Invoke-Assessment -InputPath $changedBundlePath -OutputPath (Join-Path $baselineRoot 'changed.json') -CachePath (Join-Path $baselineRoot 'changed-empty-cache.json') -BaselinePath $baselinePath
    $baselineChangedCalls = @(Get-Content -LiteralPath $baselineChangedLogPath)
    Add-TestResult -Name 'changed-rule-invalidates-baseline-entry' -Passed ($baselineChanged.baselineHitCount -eq 1 -and $baselineChanged.evaluatedCount -eq 1 -and $baselineChanged.batchCount -eq 1 -and $baselineChangedCalls.Count -eq 1) -Detail 'A changed source hash invalidates only its shared baseline entry and preserves every unchanged baseline assessment.'

    $retryRoot = Join-Path $tempRoot 'retry'
    New-Item -ItemType Directory -Path $retryRoot -Force | Out-Null
    $retryCachePath = Join-Path $retryRoot 'cache.json'
    $retryOutputPath = Join-Path $retryRoot 'assessed.json'
    $retryLogPath = Join-Path $retryRoot 'calls.log'
    $failOncePath = Join-Path $retryRoot 'fail-once.flag'
    [IO.File]::WriteAllText($failOncePath, 'fail once', [Text.UTF8Encoding]::new($false))
    $env:FAKE_EVALUATOR_CALL_LOG = $retryLogPath
    $env:FAKE_EVALUATOR_FAIL_ONCE = $failOncePath
    $retry = Invoke-Assessment -InputPath $bundlePath -OutputPath $retryOutputPath -CachePath $retryCachePath -BatchSize 2 -MaxRetries 1
    $retryCalls = @(Get-Content -LiteralPath $retryLogPath)
    Add-TestResult -Name 'malformed-output-retried' -Passed ($retry.evaluatedCount -eq 2 -and $retry.batchCount -eq 1 -and $retryCalls.Count -eq 2 -and -not (Test-Path -LiteralPath $failOncePath)) -Detail 'Malformed evaluator JSON is rejected and retried within the configured bound.'

    $failureRoot = Join-Path $tempRoot 'failure'
    New-Item -ItemType Directory -Path $failureRoot -Force | Out-Null
    $failureOutputPath = Join-Path $failureRoot 'assessed.json'
    $failureCachePath = Join-Path $failureRoot 'cache.json'
    $failureLogPath = Join-Path $failureRoot 'calls.log'
    $env:FAKE_EVALUATOR_CALL_LOG = $failureLogPath
    $env:FAKE_EVALUATOR_FAIL_ONCE = ''
    $env:FAKE_EVALUATOR_ALWAYS_FAIL = '1'
    $failureOutput = @(& pwsh -NoProfile -File $assessmentPath -BundlePath $bundlePath -BaselinePath (Join-Path $tempRoot 'absent-baseline.json') -OutputPath $failureOutputPath -CachePath $failureCachePath -EvaluatorScriptPath $fakeEvaluatorPath -BatchSize 2 -MaxRetries 1 -OutputFormat Json 2>&1)
    $failureExitCode = $LASTEXITCODE
    $failureCalls = @(Get-Content -LiteralPath $failureLogPath)
    Add-TestResult -Name 'malformed-output-fails-closed' -Passed ($failureExitCode -ne 0 -and $failureCalls.Count -eq 2 -and -not (Test-Path -LiteralPath $failureOutputPath)) -Detail 'Persistently malformed evaluator output exhausts bounded retries and does not write a final bundle.'

    $env:FAKE_EVALUATOR_CALL_LOG = $callLogPath
    $env:FAKE_EVALUATOR_FAIL_ONCE = ''
    $env:FAKE_EVALUATOR_ALWAYS_FAIL = ''
    $repositoryOutputPath = Join-Path $repositoryRoot 'hosted_copilot/tools/rejected-assessment.json'
    $rejectedOutput = @(& pwsh -NoProfile -File $assessmentPath -BundlePath $bundlePath -OutputPath $repositoryOutputPath -CachePath $cachePath -EvaluatorScriptPath $fakeEvaluatorPath -OutputFormat Json 2>&1)
    Add-TestResult -Name 'repository-output-rejected' -Passed ($LASTEXITCODE -ne 0 -and -not (Test-Path -LiteralPath $repositoryOutputPath)) -Detail 'Generated assessment bundles cannot be written inside the source repository.'
}
catch {
    $issues.Add($_.Exception.Message)
}
finally {
    Remove-Item Env:FAKE_EVALUATOR_CALL_LOG -ErrorAction SilentlyContinue
    Remove-Item Env:FAKE_EVALUATOR_FAIL_ONCE -ErrorAction SilentlyContinue
    Remove-Item Env:FAKE_EVALUATOR_ALWAYS_FAIL -ErrorAction SilentlyContinue
    Remove-Item Env:FAKE_COLLECTOR_BUNDLE -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
}

$result = [ordered]@{
    status = if ($issues.Count -eq 0) { 'passed' } else { 'failed' }
    testCount = $results.Count
    issueCount = $issues.Count
    tests = $results.ToArray()
    issues = $issues.ToArray()
}

if ($OutputFormat -eq 'Json') {
    $result | ConvertTo-Json -Depth 6
}
else {
    Write-ValidationSectionHeader -Title 'Hosted rule intake assessment test summary'
    Write-ValidationSummary -Fields ([ordered]@{
        Status = $result.status.ToUpperInvariant()
        Tests = $result.testCount
        'Issue Count' = $result.issueCount
    })
    Write-ValidationSectionHeader -Title 'Assessment tests'
    Write-ValidationTwoColumnTable -Rows @($results.ToArray()) -FirstHeader 'status' -FirstProperty 'status' -SecondHeader 'test' -SecondProperty 'name' -UppercaseFirst
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
