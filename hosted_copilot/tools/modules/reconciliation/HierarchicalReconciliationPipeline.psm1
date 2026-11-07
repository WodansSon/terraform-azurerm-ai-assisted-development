Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Import-Module (Join-Path $PSScriptRoot 'HierarchicalReconciliation.psm1')
Import-Module (Join-Path $PSScriptRoot 'ReconciliationStageExecutor.psm1')

function Get-HierarchicalAssessmentReferenceKey {
    param([Parameter(Mandatory = $true)][object]$Reference)

    return [string]$Reference.sourceDefinitionId + [char]0 + [string]$Reference.sourceId + [char]0 + [string]$Reference.contentSha256 + [char]0 + [string]$Reference.assessmentId
}

function Assert-SynthesisRelatedCoverageEvidence {
    param(
        [Parameter(Mandatory = $true)][object]$Payload,
        [Parameter(Mandatory = $true)][object]$Result
    )

    $assessmentNodes = @{}
    foreach ($node in @($Payload.components | ForEach-Object { @($_.nodes) } | Where-Object nodeType -CEQ 'assessment')) {
        $assessmentKey = Get-HierarchicalAssessmentReferenceKey -Reference $node.sourceRef
        $assessmentNodes[$assessmentKey] = $node
    }
    $membershipByAssessment = @{}
    $recommendationsByKey = @{}
    foreach ($recommendation in @($Result.recommendations)) {
        $draftKey = [string]$recommendation.draftKey
        $recommendationsByKey[$draftKey] = $recommendation
        $memberKeys = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
        foreach ($reference in @($recommendation.memberAssessmentRefs)) {
            $assessmentKey = Get-HierarchicalAssessmentReferenceKey -Reference $reference
            if (-not $assessmentNodes.ContainsKey($assessmentKey)) {
                throw "Synthesis recommendation $draftKey references an assessment outside its shard."
            }
            if ($membershipByAssessment.ContainsKey($assessmentKey)) {
                throw "Synthesis recommendations contain duplicate assessment membership for $([string]$reference.sourceDefinitionId)/$([string]$reference.sourceId)/$([string]$reference.assessmentId)."
            }
            $membershipByAssessment[$assessmentKey] = $draftKey
            $null = $memberKeys.Add($assessmentKey)
        }
        $canonicalHostedRuleIds = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
        foreach ($assessmentKey in $memberKeys) {
            foreach ($hostedRuleId in @($assessmentNodes[$assessmentKey].original.mappedHostedRuleIds)) {
                $null = $canonicalHostedRuleIds.Add([string]$hostedRuleId)
            }
        }
        if ($canonicalHostedRuleIds.Count -gt 1) {
            throw "Synthesis recommendation $draftKey contains assessments owned by different canonical Hosted rules: $(@($canonicalHostedRuleIds | Sort-Object -CaseSensitive) -join ', ')."
        }
        $relatedHostedRuleIds = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
        foreach ($coverage in @($recommendation.relatedHostedCoverage)) {
            $hostedRuleId = [string]$coverage.hostedRuleId
            if (-not $relatedHostedRuleIds.Add($hostedRuleId)) {
                throw "Synthesis recommendation $draftKey contains duplicate related Hosted coverage for $hostedRuleId."
            }
            foreach ($reference in @($coverage.assessmentRefs)) {
                $assessmentKey = Get-HierarchicalAssessmentReferenceKey -Reference $reference
                if (-not $memberKeys.Contains($assessmentKey) -or -not $assessmentNodes.ContainsKey($assessmentKey)) {
                    throw "Synthesis recommendation $draftKey related coverage references a non-member assessment."
                }
                $sourceCoverage = @($assessmentNodes[$assessmentKey].original.relatedHostedCoverage | Where-Object { [string]$_.hostedRuleId -ceq $hostedRuleId })
                if ($sourceCoverage.Count -ne 1) {
                    throw "Synthesis recommendation $draftKey related coverage $hostedRuleId is not backed by assessment evidence for $([string]$reference.sourceDefinitionId)/$([string]$reference.sourceId)/$([string]$reference.assessmentId)."
                }
            }
        }
    }
    $coverageByAssessment = @{}
    foreach ($coverage in @($Result.assessmentCoverage)) {
        $reference = $coverage.assessmentRef
        $assessmentKey = Get-HierarchicalAssessmentReferenceKey -Reference $reference
        if (-not $assessmentNodes.ContainsKey($assessmentKey)) {
            throw 'Synthesis assessment coverage references an assessment outside its shard.'
        }
        if ($coverageByAssessment.ContainsKey($assessmentKey)) {
            throw "Synthesis contains duplicate assessment coverage for $([string]$reference.sourceDefinitionId)/$([string]$reference.sourceId)/$([string]$reference.assessmentId)."
        }
        $coverageDraftKeys = @($coverage.recommendationDraftKeys)
        if ($coverageDraftKeys.Count -ne 1 -or -not $recommendationsByKey.ContainsKey([string]$coverageDraftKeys[0])) {
            throw 'Synthesis assessment coverage must reference one known recommendation.'
        }
        if (-not $membershipByAssessment.ContainsKey($assessmentKey) -or [string]$membershipByAssessment[$assessmentKey] -cne [string]$coverageDraftKeys[0]) {
            throw 'Synthesis assessment coverage does not match recommendation membership.'
        }
        $coverageByAssessment[$assessmentKey] = $true
    }
    foreach ($assessmentKey in $assessmentNodes.Keys) {
        $sourceRef = $assessmentNodes[$assessmentKey].sourceRef
        $assessmentLabel = "$([string]$sourceRef.sourceDefinitionId)/$([string]$sourceRef.sourceId)/$([string]$sourceRef.assessmentId)"
        if (-not $membershipByAssessment.ContainsKey($assessmentKey)) {
            throw "Synthesis result omits recommendation membership for $assessmentLabel."
        }
        if (-not $coverageByAssessment.ContainsKey($assessmentKey)) {
            throw "Synthesis result omits assessment coverage for $assessmentLabel."
        }
    }
}

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
        [string]$PersistentCachePath,
        [Parameter(Mandatory = $true)][string]$CacheSchemaPath,
        [Parameter(Mandatory = $true)][string]$CatalogPath,
        [Parameter(Mandatory = $true)][string]$ProtectedRulesPath,
        [Parameter(Mandatory = $true)][string]$ContractPath,
        [string]$ContractAuthorityPath,
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
        [ValidateRange(1, [int]::MaxValue)][int]$StagePayloadBudgetBytes = 262144,
        [ValidateRange(1, [int]::MaxValue)][int]$EvaluatorPayloadBudgetBytes = 393216,
        [switch]$ShowProgress
    )

    $ledger = New-HierarchicalSemanticLedger -AssessmentBaseline $AssessmentBaseline -Catalog $Catalog -ProtectedCatalog $ProtectedCatalog
    $commonStageParameters = @{
        RunDirectory = $RunDirectory
        CachePath = $CachePath
        PersistentCachePath = $PersistentCachePath
        CacheSchemaPath = $CacheSchemaPath
        CatalogPath = $CatalogPath
        ProtectedRulesPath = $ProtectedRulesPath
        ContractPath = $ContractPath
        ContractAuthorityPath = $ContractAuthorityPath
        EvaluatorScriptPath = $EvaluatorScriptPath
        EvaluatorCommand = $EvaluatorCommand
        Model = $Model
        ReasoningEffort = $ReasoningEffort
        MaxRetries = $MaxRetries
        RetryDelayMilliseconds = $RetryDelayMilliseconds
        MaxParallelShards = $MaxParallelShards
        EvaluatorPayloadBudgetBytes = $EvaluatorPayloadBudgetBytes
        ShowProgress = $ShowProgress
    }

    $routingShards = @(New-ByteBoundRoutingShards -Ledger $ledger -MaxBytes $StagePayloadBudgetBytes)
    $routingRun = Invoke-ReconciliationStageSet @commonStageParameters -Stage 'routing' -Shards $routingShards -ResultSchemaPath $RoutingSchemaPath -PromptPath $RoutingPromptPath -InputLabel 'Assessments' -InputCount @($ledger.nodes | Where-Object nodeType -CEQ 'assessment').Count
    $routingSuggestions = @($routingRun.results | ForEach-Object { @($_.result.groups) })
    $localComponents = @(Merge-LocalRoutingSuggestions -Ledger $ledger -Suggestions $routingSuggestions)

    if ($ShowProgress) {
        Write-Host ''
    }
    $consolidationShards = @(New-ByteBoundConsolidationShards -Components $localComponents -MaxBytes $StagePayloadBudgetBytes)
    $consolidationRun = Invoke-ReconciliationStageSet @commonStageParameters -Stage 'consolidation' -Shards $consolidationShards -ResultSchemaPath $ConsolidationSchemaPath -PromptPath $ConsolidationPromptPath -InputLabel 'Assessment Groups' -InputCount $localComponents.Count
    $consolidationSuggestions = @($consolidationRun.results | ForEach-Object { @($_.result.groups) })
    $consolidatedComponents = @(Merge-ConsolidationSuggestions -Ledger $ledger -Components $localComponents -Suggestions $consolidationSuggestions)

    if ($ShowProgress) {
        Write-Host ''
    }
    $synthesisShards = @(New-RehydratedSynthesisBatches -Ledger $ledger -Components $consolidatedComponents -MaxBytes $StagePayloadBudgetBytes)
    $synthesisResultValidator = {
        param($Payload, $Result)

        Assert-SynthesisRelatedCoverageEvidence -Payload $Payload -Result $Result
    }
    $synthesisRun = Invoke-ReconciliationStageSet @commonStageParameters -Stage 'synthesis' -Shards $synthesisShards -ResultSchemaPath $SynthesisSchemaPath -PromptPath $SynthesisPromptPath -ResultValidator $synthesisResultValidator -InputLabel 'Assessment Groups' -InputCount $consolidatedComponents.Count
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
