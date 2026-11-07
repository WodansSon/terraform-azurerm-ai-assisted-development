[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$Stage,
    [Parameter(Mandatory = $true)][string]$InputPath,
    [Parameter(Mandatory = $true)][string]$CatalogPath,
    [Parameter(Mandatory = $true)][string]$ProtectedRulesPath,
    [Parameter(Mandatory = $true)][string]$ContractPath,
    [Parameter(Mandatory = $true)][string]$SchemaPath,
    [Parameter(Mandatory = $true)][string]$PromptPath,
    [Parameter(Mandatory = $true)][string]$OutputPath,
    [Parameter(Mandatory = $true)][string]$EvaluatorCommand,
    [Parameter(Mandatory = $true)][string]$Model,
    [Parameter(Mandatory = $true)][string]$ReasoningEffort
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$input = Get-Content -LiteralPath $InputPath -Raw | ConvertFrom-Json -DateKind String
$outputDirectory = Split-Path -Parent $OutputPath
$callDirectory = Join-Path $outputDirectory 'calls'
$null = New-Item -ItemType Directory -Path $callDirectory -Force
$null = New-Item -ItemType File -Path (Join-Path $callDirectory ([guid]::NewGuid().ToString('N') + '.marker'))
function Assert-RetryCorrection {
    param([Parameter(Mandatory = $true)][string]$ExpectedDiagnostic)

    $retryContextPath = Join-Path $outputDirectory 'stage-retry-context.json'
    if (-not (Test-Path -LiteralPath $retryContextPath -PathType Leaf)) {
        throw 'Synthetic retry did not receive stage-retry-context.json.'
    }
    $retryContext = Get-Content -LiteralPath $retryContextPath -Raw | ConvertFrom-Json -DateKind String
    $retryPrompt = Get-Content -LiteralPath $PromptPath -Raw
    if ([string]$retryContext.kind -cne 'hosted-hierarchical-reconciliation-retry-context' -or
        [string]$retryContext.diagnostic -notlike "*$ExpectedDiagnostic*" -or
        $retryPrompt -notmatch '(?m)^## Trusted Retry Correction$' -or
        $retryPrompt -notlike "*$ExpectedDiagnostic*") {
        throw "Synthetic retry correction did not contain the expected diagnostic: $ExpectedDiagnostic"
    }
}
if ($env:RECONCILIATION_FAIL_ALL -eq '1') {
    throw 'Synthetic evaluator invocation during cache reuse.'
}
if ([string]$env:RECONCILIATION_FAIL_SHARD -ceq [string]$input.shardKey) {
    throw "Synthetic terminal failure for $($input.shardKey)."
}
if ([string]$env:RECONCILIATION_FAIL_ONCE_SHARD -ceq [string]$input.shardKey) {
    $retryMarker = Join-Path $outputDirectory 'failed-once.marker'
    if (-not (Test-Path -LiteralPath $retryMarker -PathType Leaf)) {
        $null = New-Item -ItemType File -Path $retryMarker
        throw "Synthetic first-attempt failure for $($input.shardKey)."
    }
    Assert-RetryCorrection -ExpectedDiagnostic 'Synthetic first-attempt failure'
}

if ($Stage -ceq 'routing') {
    $result = [ordered]@{ schemaVersion = 1; kind = 'hosted-assessment-routing-result'; shardKey = [string]$input.shardKey; groups = @() }
}
elseif ($Stage -ceq 'consolidation') {
    $result = [ordered]@{ schemaVersion = 1; kind = 'hosted-assessment-consolidation-result'; shardKey = [string]$input.shardKey; groups = @() }
}
else {
    $catalog = Get-Content -LiteralPath $CatalogPath -Raw | ConvertFrom-Json -DateKind String
    $recommendations = [Collections.Generic.List[object]]::new()
    $coverage = [Collections.Generic.List[object]]::new()
    foreach ($node in @($input.payload.components | ForEach-Object { @($_.nodes) } | Where-Object nodeType -CEQ 'assessment')) {
        $assessment = $node.original
        $reference = $node.sourceRef
        $draftKey = 'recommendation-{0}' -f ($recommendations.Count + 1)
        $mappedHostedRuleIds = @($assessment.mappedHostedRuleIds)
        $mappedHostedRuleId = if ($mappedHostedRuleIds.Count -gt 0) { [string]$mappedHostedRuleIds[0] } else { $null }
        $mappedRule = if ([string]::IsNullOrWhiteSpace([string]$mappedHostedRuleId)) { $null } else { @($catalog.rules | Where-Object { [string]$_.id -ceq [string]$mappedHostedRuleId })[0] }
        $recommendation = [ordered]@{
            draftKey = $draftKey
            recommendedAction = if ($null -ne $mappedRule) { 'no-change' } elseif ([bool]$assessment.hostedApplicable) { 'add' } else { 'exclude' }
            targetHostedId = if ($null -ne $mappedRule) { [string]$mappedRule.id } else { $null }
            idFamily = if ($null -ne $mappedRule) { $null } else { 'IMPL-SCHEMA' }
            title = [string]$assessment.title
            recommendedRuleText = if ($null -ne $mappedRule) { [string]$mappedRule.text } else { [string]$assessment.sourceMeaning }
            category = 'implementation'
            placement = if ($null -ne $mappedRule) { 'Evidence And Resource Type' } else { 'Schema And State' }
            rationale = [string]$assessment.selectionRationale
            needsReview = $false
            selectionFactors = $assessment.selectionFactors
            selectionRationale = [string]$assessment.selectionRationale
            memberAssessmentRefs = @($reference)
            memberMeaningCoverage = @([ordered]@{ assessmentRef = $reference; rationale = 'The recommendation preserves this assessment meaning.' })
            relatedHostedCoverage = @()
            retireHostedRuleIds = @()
        }
        if ($null -eq $mappedRule) {
            $recommendation.implementationModels = @('legacy', 'typed', 'framework')
        }
        $recommendations.Add($recommendation)
        $coverage.Add([ordered]@{
            assessmentRef = $reference
            disposition = if ([bool]$assessment.hostedApplicable) { 'recommended' } else { 'excluded' }
            rationale = if ([bool]$assessment.hostedApplicable) { $null } else { [string]$assessment.applicabilityRationale }
            recommendationDraftKeys = @($draftKey)
        })
    }
    $result = [ordered]@{ '$schema' = 'assessment-reconciliation-draft.schema.json'; schemaVersion = 1; recommendations = $recommendations.ToArray(); assessmentCoverage = $coverage.ToArray() }
    if ($env:RECONCILIATION_EMIT_UNSUPPORTED_COVERAGE_ONCE -eq '1') {
        $retryMarker = Join-Path $outputDirectory 'unsupported-coverage-emitted.marker'
        if (-not (Test-Path -LiteralPath $retryMarker -PathType Leaf)) {
            $null = New-Item -ItemType File -Path $retryMarker
            $recommendation = @($result.recommendations)[0]
            $recommendation.relatedHostedCoverage = @([ordered]@{
                    hostedRuleId = 'IMPL-HIER-000'
                    relationship = 'related'
                    rationale = 'Synthetic unsupported relationship for semantic validation.'
                    assessmentRefs = @($recommendation.memberAssessmentRefs)
                })
        }
            else {
                Assert-RetryCorrection -ExpectedDiagnostic 'not backed by assessment evidence'
            }
    }
    if ($env:RECONCILIATION_OMIT_ASSESSMENT_ONCE -eq '1') {
        $retryMarker = Join-Path $outputDirectory 'omitted-assessment-emitted.marker'
        if (-not (Test-Path -LiteralPath $retryMarker -PathType Leaf)) {
            $null = New-Item -ItemType File -Path $retryMarker
            $omittedDraftKey = [string]@($result.recommendations)[0].draftKey
            $result.recommendations = @($result.recommendations | Where-Object { [string]$_.draftKey -cne $omittedDraftKey })
            $result.assessmentCoverage = @($result.assessmentCoverage | Where-Object { @($_.recommendationDraftKeys) -cnotcontains $omittedDraftKey })
        }
        else {
            Assert-RetryCorrection -ExpectedDiagnostic 'omits recommendation membership'
        }
    }
    if ($env:RECONCILIATION_EMIT_DUPLICATE_COVERAGE_ONCE -eq '1') {
        $retryMarker = Join-Path $outputDirectory 'duplicate-coverage-emitted.marker'
        if (-not (Test-Path -LiteralPath $retryMarker -PathType Leaf)) {
            $null = New-Item -ItemType File -Path $retryMarker
            $recommendation = @($result.recommendations)[0]
            $firstCoverage = [ordered]@{
                hostedRuleId = 'IMPL-HIER-001'
                relationship = 'related'
                rationale = 'Synthetic duplicate relationship for semantic validation.'
                assessmentRefs = @($recommendation.memberAssessmentRefs)
            }
            $secondCoverage = [ordered]@{
                hostedRuleId = 'IMPL-HIER-001'
                relationship = 'partial-overlap'
                rationale = 'Synthetic conflicting duplicate relationship for semantic validation.'
                assessmentRefs = @($recommendation.memberAssessmentRefs)
            }
            $recommendation.relatedHostedCoverage = @($firstCoverage, $secondCoverage)
        }
        else {
            Assert-RetryCorrection -ExpectedDiagnostic 'duplicate related Hosted coverage'
        }
    }
    if ($env:RECONCILIATION_EMIT_MULTIPLE_CANONICAL_OWNERS_ONCE -eq '1') {
        $retryMarker = Join-Path $outputDirectory 'multiple-canonical-owners-emitted.marker'
        if (-not (Test-Path -LiteralPath $retryMarker -PathType Leaf)) {
            $null = New-Item -ItemType File -Path $retryMarker
            $mappedRecommendations = @($result.recommendations | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_.targetHostedId) })
            if ($mappedRecommendations.Count -lt 2) {
                throw 'Synthetic multiple-owner fixture requires two mapped recommendations in one synthesis batch.'
            }
            $primary = $mappedRecommendations[0]
            $secondary = $mappedRecommendations[1]
            $primary.memberAssessmentRefs = @($primary.memberAssessmentRefs) + @($secondary.memberAssessmentRefs)
            $primary.memberMeaningCoverage = @($primary.memberMeaningCoverage) + @($secondary.memberMeaningCoverage)
            $primary.retireHostedRuleIds = @([string]$secondary.targetHostedId)
            $secondaryDraftKey = [string]$secondary.draftKey
            $result.recommendations = @($result.recommendations | Where-Object { [string]$_.draftKey -cne $secondaryDraftKey })
            foreach ($assessmentCoverage in @($result.assessmentCoverage | Where-Object { @($_.recommendationDraftKeys) -ccontains $secondaryDraftKey })) {
                $assessmentCoverage.recommendationDraftKeys = @([string]$primary.draftKey)
            }
        }
        else {
            Assert-RetryCorrection -ExpectedDiagnostic 'assessments owned by different canonical Hosted rules'
        }
    }
}

$json = $result | ConvertTo-Json -Depth 100 -Compress
if ($env:RECONCILIATION_EMIT_UNDEFINED -eq '1') {
    $json = $json -replace '"implementationModels":\[[^\]]+\]', '"implementationModels":undefined'
}
[IO.File]::WriteAllText($OutputPath, ($json + "`n"), [Text.UTF8Encoding]::new($false))
