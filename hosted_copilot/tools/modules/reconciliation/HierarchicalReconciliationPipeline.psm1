Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Import-Module (Join-Path $PSScriptRoot 'HierarchicalReconciliation.psm1')
Import-Module (Join-Path $PSScriptRoot 'ReconciliationStageExecutor.psm1')

function Merge-HierarchicalReconciliationDrafts {
    param([Parameter(Mandatory = $true)][object[]]$Drafts)

    $recommendations = [Collections.Generic.List[object]]::new()
    $coverage = [Collections.Generic.List[object]]::new()
    $recommendationsByKey = @{}
    $membershipByAssessment = @{}
    $coveredAssessments = @{}
    foreach ($sourceDraft in $Drafts) {
        $draft = ($sourceDraft | ConvertTo-Json -Depth 100 -Compress) | ConvertFrom-Json -DateKind String
        $draftKeyMap = @{}
        foreach ($recommendation in @($draft.recommendations)) {
            $sourceDraftKey = [string]$recommendation.draftKey
            if ($draftKeyMap.ContainsKey($sourceDraftKey)) {
                throw "Synthesis draft contains duplicate draft key `$sourceDraftKey`."
            }
            $mergedDraftKey = 'recommendation-{0}' -f ($recommendations.Count + 1)
            $draftKeyMap[$sourceDraftKey] = $mergedDraftKey
            $recommendation.draftKey = $mergedDraftKey
            $recommendations.Add($recommendation)
            $recommendationsByKey[$mergedDraftKey] = $recommendation
            foreach ($assessmentRef in @($recommendation.memberAssessmentRefs)) {
                $assessmentKey = ($assessmentRef | ConvertTo-Json -Depth 20 -Compress)
                if ($membershipByAssessment.ContainsKey($assessmentKey)) {
                    throw "Synthesis recommendations contain duplicate assessment membership for `$assessmentKey`."
                }
                $membershipByAssessment[$assessmentKey] = $mergedDraftKey
            }
        }
        foreach ($assessmentCoverage in @($draft.assessmentCoverage)) {
            $assessmentKey = ($assessmentCoverage.assessmentRef | ConvertTo-Json -Depth 20 -Compress)
            if ($coveredAssessments.ContainsKey($assessmentKey)) {
                throw "Synthesis drafts contain duplicate assessment coverage for `$assessmentKey`."
            }
            $coveredAssessments[$assessmentKey] = $true
            $sourceCoverageDraftKeys = @($assessmentCoverage.recommendationDraftKeys)
            if ($sourceCoverageDraftKeys.Count -ne 1) {
                throw "Synthesis coverage for `$assessmentKey` must reference exactly one recommendation."
            }
            $assessmentCoverage.recommendationDraftKeys = @($sourceCoverageDraftKeys | ForEach-Object {
                $sourceDraftKey = [string]$_
                if (-not $draftKeyMap.ContainsKey($sourceDraftKey)) {
                    throw "Synthesis coverage references unknown draft key `$sourceDraftKey`."
                }
                $draftKeyMap[$sourceDraftKey]
            })
            $mergedCoverageDraftKey = [string]$assessmentCoverage.recommendationDraftKeys[0]
            if (-not $membershipByAssessment.ContainsKey($assessmentKey) -or [string]$membershipByAssessment[$assessmentKey] -cne $mergedCoverageDraftKey) {
                throw "Synthesis coverage for `$assessmentKey` does not match recommendation membership."
            }
            $action = [string]$recommendationsByKey[$mergedCoverageDraftKey].recommendedAction
            $disposition = [string]$assessmentCoverage.disposition
            if (($disposition -ceq 'recommended' -and $action -notin @('add', 'update', 'no-change', 'retire', 'restore')) -or
                ($disposition -ceq 'deferred' -and $action -cne 'defer') -or
                ($disposition -ceq 'excluded' -and $action -cne 'exclude')) {
                throw "Synthesis coverage disposition `$disposition` does not match recommendation action `$action` for `$assessmentKey`."
            }
            $coverage.Add($assessmentCoverage)
        }
    }
    $missingCoverage = @($membershipByAssessment.Keys | Where-Object { -not $coveredAssessments.ContainsKey($_) })
    if ($missingCoverage.Count -gt 0) {
        throw "Synthesis recommendations omit assessment coverage for `$($missingCoverage[0])`."
    }
    return [pscustomobject][ordered]@{
        '$schema' = 'assessment-reconciliation-draft.schema.json'
        schemaVersion = 1
        recommendations = $recommendations.ToArray()
        assessmentCoverage = $coverage.ToArray()
    }
}

function Invoke-HierarchicalReconciliationPipeline {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][object]$AssessmentBaseline,
        [Parameter(Mandatory = $true)][object]$Catalog,
        [Parameter(Mandatory = $true)][object]$ProtectedCatalog,
        [Parameter(Mandatory = $true)][string]$RunDirectory,
        [Parameter(Mandatory = $true)][string]$CachePath,
        [Parameter(Mandatory = $true)][string]$CacheSchemaPath,
        [Parameter(Mandatory = $true)][string]$CatalogPath,
        [Parameter(Mandatory = $true)][string]$ProtectedRulesPath,
        [Parameter(Mandatory = $true)][string]$ContractPath,
        [Parameter(Mandatory = $true)][string]$RoutingSchemaPath,
        [Parameter(Mandatory = $true)][string]$RoutingPromptPath,
        [Parameter(Mandatory = $true)][string]$ConsolidationSchemaPath,
        [Parameter(Mandatory = $true)][string]$ConsolidationPromptPath,
        [Parameter(Mandatory = $true)][string]$SynthesisSchemaPath,
        [Parameter(Mandatory = $true)][string]$SynthesisPromptPath,
        [Parameter(Mandatory = $true)][string]$EvaluatorScriptPath,
        [string]$EvaluatorCommand = 'copilot',
        [Parameter(Mandatory = $true)][string]$Model,
        [Parameter(Mandatory = $true)][ValidateSet('low', 'medium', 'high', 'xhigh')][string]$ReasoningEffort,
        [ValidateRange(0, 3)][int]$MaxRetries = 1,
        [ValidateRange(0, 60000)][int]$RetryDelayMilliseconds = 1000,
        [ValidateRange(1, 8)][int]$MaxParallelShards = 3,
        [ValidateRange(1, [int]::MaxValue)][int]$StagePayloadBudgetBytes = 196608,
        [ValidateRange(1, [int]::MaxValue)][int]$EvaluatorPayloadBudgetBytes = 393216
    )

    $ledger = New-HierarchicalSemanticLedger -AssessmentBaseline $AssessmentBaseline -Catalog $Catalog -ProtectedCatalog $ProtectedCatalog
    $commonStageParameters = @{
        RunDirectory = $RunDirectory
        CachePath = $CachePath
        CacheSchemaPath = $CacheSchemaPath
        CatalogPath = $CatalogPath
        ProtectedRulesPath = $ProtectedRulesPath
        ContractPath = $ContractPath
        EvaluatorScriptPath = $EvaluatorScriptPath
        EvaluatorCommand = $EvaluatorCommand
        Model = $Model
        ReasoningEffort = $ReasoningEffort
        MaxRetries = $MaxRetries
        RetryDelayMilliseconds = $RetryDelayMilliseconds
        MaxParallelShards = $MaxParallelShards
        EvaluatorPayloadBudgetBytes = $EvaluatorPayloadBudgetBytes
    }

    $routingShards = @(New-ByteBoundRoutingShards -Ledger $ledger -MaxBytes $StagePayloadBudgetBytes)
    $routingRun = Invoke-ReconciliationStageSet @commonStageParameters -Stage 'routing' -Shards $routingShards -ResultSchemaPath $RoutingSchemaPath -PromptPath $RoutingPromptPath
    $routingSuggestions = @($routingRun.results | ForEach-Object { @($_.result.groups) })
    $localComponents = @(Merge-LocalRoutingSuggestions -Ledger $ledger -Suggestions $routingSuggestions)

    $consolidationShards = @(New-ByteBoundConsolidationShards -Components $localComponents -MaxBytes $StagePayloadBudgetBytes)
    $consolidationRun = Invoke-ReconciliationStageSet @commonStageParameters -Stage 'consolidation' -Shards $consolidationShards -ResultSchemaPath $ConsolidationSchemaPath -PromptPath $ConsolidationPromptPath
    $consolidationSuggestions = @($consolidationRun.results | ForEach-Object { @($_.result.groups) })
    $consolidatedComponents = @(Merge-ConsolidationSuggestions -Ledger $ledger -Components $localComponents -Suggestions $consolidationSuggestions)

    $synthesisShards = @(New-RehydratedSynthesisBatches -Ledger $ledger -Components $consolidatedComponents -MaxBytes $StagePayloadBudgetBytes)
    $synthesisRun = Invoke-ReconciliationStageSet @commonStageParameters -Stage 'synthesis' -Shards $synthesisShards -ResultSchemaPath $SynthesisSchemaPath -PromptPath $SynthesisPromptPath
    $drafts = @($synthesisRun.results | ForEach-Object { $_.result })
    $draft = Merge-HierarchicalReconciliationDrafts -Drafts $drafts

    return [pscustomobject][ordered]@{
        draft = $draft
        ledger = $ledger
        components = $consolidatedComponents
        stages = [pscustomobject][ordered]@{
            routing = $routingRun
            consolidation = $consolidationRun
            synthesis = $synthesisRun
        }
        shardCount = $routingRun.shardCount + $consolidationRun.shardCount + $synthesisRun.shardCount
        cachedShardCount = $routingRun.cachedCount + $consolidationRun.cachedCount + $synthesisRun.cachedCount
        evaluatedShardCount = $routingRun.evaluatedCount + $consolidationRun.evaluatedCount + $synthesisRun.evaluatedCount
    }
}

Export-ModuleMember -Function @(
    'Invoke-HierarchicalReconciliationPipeline'
)
