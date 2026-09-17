[CmdletBinding()]
param(
    [string]$RepositoryRoot = (Join-Path $PSScriptRoot '../..'),

    [Parameter(Mandatory = $true)]
    [string[]]$InventoryPaths,

    [string]$PriorSourceGenerationPath,

    [Parameter(Mandatory = $true)]
    [string]$AssessmentBaselinePath,

    [Parameter(Mandatory = $true)]
    [string]$RecommendationSnapshotPath,

    [Parameter(Mandatory = $true)]
    [string]$OutputPath,

    [string]$HostedCatalogPath = (Join-Path $PSScriptRoot '../copilot-rule-catalog/instruction-catalog.json'),

    [string]$ReviewContractPath = (Join-Path $PSScriptRoot '../copilot-rule-catalog/assessment-reconciliation/assessment-reconciliation-review-v1.json'),

    [object]$GeneratedAt = [DateTime]::UtcNow,

    [ValidateSet('Text', 'Json')]
    [string]$OutputFormat = 'Text'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$sourceEvidencePath = Join-Path $PSScriptRoot 'SourceEvidenceValidation.psm1'
$helpersPath = Join-Path $PSScriptRoot 'HostedToolkit.Helpers.psm1'
$reconciliationValidationPath = Join-Path $PSScriptRoot 'AssessmentReconciliationValidation.psm1'
Import-Module -Name $sourceEvidencePath -Force
Import-Module -Name $helpersPath -Force
Import-Module -Name $reconciliationValidationPath -Force

function Read-JsonFile {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$SchemaPath,
        [Parameter(Mandatory = $true)][string]$Name
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "$Name was not found: $Path"
    }
    $snapshot = Get-FileSnapshot -Path $Path
    try {
        $valid = Test-Json -Json $snapshot.Content -SchemaFile $SchemaPath -ErrorAction Stop
    }
    catch {
        throw "$Name does not satisfy its schema: $Path"
    }
    if (-not $valid) {
        throw "$Name does not satisfy its schema: $Path"
    }
    return [pscustomobject]@{ Value = $snapshot.Content | ConvertFrom-Json -DateKind String; Snapshot = $snapshot }
}

function Get-AssessmentKey {
    param([Parameter(Mandatory = $true)][object]$Reference)

    return [string]$Reference.sourceDefinitionId + [char]0 + [string]$Reference.sourceId + [char]0 + [string]$Reference.contentSha256 + [char]0 + [string]$Reference.assessmentId
}

function Get-SourceKey {
    param(
        [Parameter(Mandatory = $true)][string]$SourceDefinitionId,
        [Parameter(Mandatory = $true)][string]$SourceId
    )

    return $SourceDefinitionId + [char]0 + $SourceId
}

function Get-SourceTransition {
    param(
        [Parameter(Mandatory = $true)][object]$CurrentRecord,
        [object]$PriorRecord
    )

    if ($null -eq $PriorRecord) {
        return 'added'
    }
    if ([string]$CurrentRecord.presence -ceq 'removed') {
        return $(if ([string]$PriorRecord.presence -ceq 'removed') { 'current' } else { 'removed' })
    }
    if ([string]$PriorRecord.presence -ceq 'removed') {
        return 'reappeared'
    }
    if ([string]$CurrentRecord.contentSha256 -cne [string]$PriorRecord.contentSha256) {
        return 'changed'
    }
    if ([string]$CurrentRecord.location -cne [string]$PriorRecord.location) {
        return 'moved'
    }
    if ([string]$CurrentRecord.sourceLifecycle -cne [string]$PriorRecord.sourceLifecycle) {
        return 'source-lifecycle-changed'
    }
    return 'current'
}

$resolvedRepositoryRoot = [IO.Path]::GetFullPath($RepositoryRoot).TrimEnd([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar)
$repositoryPrefix = $resolvedRepositoryRoot + [IO.Path]::DirectorySeparatorChar
$resolvedOutputPath = [IO.Path]::GetFullPath($OutputPath)
if ($resolvedOutputPath.StartsWith($repositoryPrefix, [StringComparison]::OrdinalIgnoreCase)) {
    throw 'Assessment reconciliation review output must be outside the repository root'
}

$catalogRoot = Join-Path $resolvedRepositoryRoot 'hosted_copilot/copilot-rule-catalog'
$reconciliationRoot = Join-Path $catalogRoot 'assessment-reconciliation'
$inventorySchemaPath = Join-Path $catalogRoot 'source-inventories/source-inventory.schema.json'
$baselineInput = Read-JsonFile -Path ([IO.Path]::GetFullPath($AssessmentBaselinePath)) -SchemaPath (Join-Path $catalogRoot 'rule-assessments/source-assessment-baseline.schema.json') -Name 'Source assessment baseline'
$recommendationInput = Read-JsonFile -Path ([IO.Path]::GetFullPath($RecommendationSnapshotPath)) -SchemaPath (Join-Path $reconciliationRoot 'hosted-rule-change-recommendations.schema.json') -Name 'Hosted rule change recommendations'
$catalogInput = Read-JsonFile -Path ([IO.Path]::GetFullPath($HostedCatalogPath)) -SchemaPath (Join-Path $catalogRoot 'instruction-catalog.schema.json') -Name 'Hosted instruction catalog'
$reviewContractInput = Read-JsonFile -Path ([IO.Path]::GetFullPath($ReviewContractPath)) -SchemaPath (Join-Path $reconciliationRoot 'assessment-reconciliation-review-contract.schema.json') -Name 'Assessment reconciliation review contract'
$priorSourceGenerationInput = $null
if (-not [string]::IsNullOrWhiteSpace($PriorSourceGenerationPath)) {
    $priorSourceGenerationInput = Read-JsonFile -Path ([IO.Path]::GetFullPath($PriorSourceGenerationPath)) -SchemaPath (Join-Path $catalogRoot 'source-generations/source-generation.schema.json') -Name 'Prior source generation'
    Assert-SourceGenerationIntegrity -SourceGeneration $priorSourceGenerationInput.Value -RepositoryRoot $resolvedRepositoryRoot -ExpectedSha256 $priorSourceGenerationInput.Snapshot.Sha256
}
$baseline = $baselineInput.Value
$recommendationSnapshot = $recommendationInput.Value
$reviewContractSha256 = Get-AssessmentReconciliationReviewContractSha256 -Contract $reviewContractInput.Value -RepositoryRoot $resolvedRepositoryRoot

if ([string]$baseline.hostedCatalogSha256 -cne $catalogInput.Snapshot.Sha256 -or [string]$recommendationSnapshot.hostedCatalogSha256 -cne $catalogInput.Snapshot.Sha256) {
    throw 'Assessment reconciliation review inputs do not bind the supplied Hosted catalog'
}
if ([string]$recommendationSnapshot.assessmentBaselineSha256 -cne $baselineInput.Snapshot.Sha256) {
    throw 'Hosted rule change recommendations do not bind the supplied assessment baseline'
}
$expectedPriorSourceGenerationSha256 = if ($null -eq $priorSourceGenerationInput) { $null } else { $priorSourceGenerationInput.Snapshot.Sha256 }
if (($null -eq $baseline.priorSourceGenerationSha256 -and $null -ne $expectedPriorSourceGenerationSha256) -or
    ($null -ne $baseline.priorSourceGenerationSha256 -and [string]$baseline.priorSourceGenerationSha256 -cne [string]$expectedPriorSourceGenerationSha256)) {
    throw 'Source assessment baseline does not bind the supplied prior source generation'
}
$baselineInventoryHashes = ConvertTo-OrdinalMap -Value $baseline.inventoryHashes
$recommendationInventoryHashes = ConvertTo-OrdinalMap -Value $recommendationSnapshot.inventoryHashes
$baselineInventoryJson = $baselineInventoryHashes | ConvertTo-Json -Compress
$recommendationInventoryJson = $recommendationInventoryHashes | ConvertTo-Json -Compress
if ($baselineInventoryJson -cne $recommendationInventoryJson) {
    throw 'Hosted rule change recommendations do not bind the assessment baseline inventories'
}

$inventoryRecords = @{}
$inventoryHashes = [ordered]@{}
$inventories = [ordered]@{}
foreach ($inventoryPath in $InventoryPaths) {
    $inventoryInput = Read-JsonFile -Path ([IO.Path]::GetFullPath($inventoryPath)) -SchemaPath $inventorySchemaPath -Name 'Source inventory'
    $inventory = $inventoryInput.Value
    Assert-SourceInventoryIntegrity -Inventory $inventory
    $sourceDefinitionId = [string]$inventory.sourceDefinitionId
    if ($inventoryHashes.Contains($sourceDefinitionId)) {
        throw "Assessment reconciliation review received duplicate inventory lane: $sourceDefinitionId"
    }
    if (-not $baseline.inventoryHashes.PSObject.Properties[$sourceDefinitionId] -or [string]$baseline.inventoryHashes.$sourceDefinitionId -cne $inventoryInput.Snapshot.Sha256) {
        throw "Source inventory does not match the assessment baseline: $sourceDefinitionId"
    }
    $inventoryHashes[$sourceDefinitionId] = $inventoryInput.Snapshot.Sha256
    $inventories[$sourceDefinitionId] = $inventory
    $projectionRecords = @(Get-SourceInventoryProjectionRecords -CurrentInventory $inventory -PriorSourceGeneration $(if ($null -eq $priorSourceGenerationInput) { $null } else { $priorSourceGenerationInput.Value }) -RemovedAt $GeneratedAt)
    foreach ($record in $projectionRecords) {
        $key = Get-SourceKey -SourceDefinitionId $sourceDefinitionId -SourceId ([string]$record.sourceId)
        if ($inventoryRecords.ContainsKey($key)) {
            throw "Source inventories contain duplicate source identity: $sourceDefinitionId/$($record.sourceId)"
        }
        $inventoryRecords[$key] = $record
    }
}
$inventoryHashes = ConvertTo-OrdinalMap -Value $inventoryHashes
$inventories = ConvertTo-OrdinalMap -Value $inventories
if (($inventoryHashes | ConvertTo-Json -Compress) -cne $baselineInventoryJson) {
    throw 'Assessment reconciliation review requires every baseline inventory lane exactly once'
}

$knownAssessmentKeys = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
foreach ($entry in @($baseline.entries)) {
    foreach ($assessment in @($entry.assessments)) {
        $assessmentKey = Get-AssessmentKey -Reference ([ordered]@{
            sourceDefinitionId = [string]$entry.sourceRef.sourceDefinitionId
            sourceId = [string]$entry.sourceRef.sourceId
            contentSha256 = [string]$entry.sourceRef.contentSha256
            assessmentId = [string]$assessment.assessmentId
        })
        if (-not $knownAssessmentKeys.Add($assessmentKey)) {
            throw 'Assessment baseline contains duplicate assessment identity'
        }
    }
}
$recommendationsById = @{}
$membershipByAssessment = @{}
foreach ($recommendation in @($recommendationSnapshot.recommendations)) {
    $hostedId = [string]$recommendation.hostedId
    if ($recommendationsById.ContainsKey($hostedId)) {
        throw "Recommendation snapshot contains duplicate Hosted ID: $hostedId"
    }
    $recommendationsById[$hostedId] = $recommendation
    $memberKeys = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    foreach ($reference in @($recommendation.memberAssessmentRefs)) {
        if ([string]$reference.assessmentBaselineSha256 -cne $baselineInput.Snapshot.Sha256) {
            throw "Recommendation snapshot member does not bind the supplied assessment baseline: $hostedId"
        }
        $assessmentKey = Get-AssessmentKey -Reference $reference
        if (-not $knownAssessmentKeys.Contains($assessmentKey)) {
            throw "Recommendation snapshot references an unknown assessment: $hostedId"
        }
        if (-not $memberKeys.Add($assessmentKey)) {
            throw "Recommendation snapshot repeats an assessment: $hostedId"
        }
        if ($membershipByAssessment.ContainsKey($assessmentKey)) {
            throw "Assessment belongs to more than one recommendation: $hostedId"
        }
        $membershipByAssessment[$assessmentKey] = $hostedId
    }
}
$coverageByAssessment = @{}
foreach ($coverage in @($recommendationSnapshot.assessmentCoverage)) {
    if ([string]$coverage.assessmentRef.assessmentBaselineSha256 -cne $baselineInput.Snapshot.Sha256) {
        throw 'Recommendation snapshot coverage does not bind the supplied assessment baseline'
    }
    $key = Get-AssessmentKey -Reference $coverage.assessmentRef
    if ($coverageByAssessment.ContainsKey($key)) {
        throw 'Recommendation snapshot contains duplicate assessment coverage'
    }
    $coverageByAssessment[$key] = $coverage
    $hostedIds = @($coverage.hostedIds)
    if ([string]$coverage.disposition -ceq 'recommended') {
        if ($hostedIds.Count -ne 1 -or -not $recommendationsById.ContainsKey([string]$hostedIds[0])) {
            throw 'Recommended assessment coverage must reference one known recommendation'
        }
        if (-not $membershipByAssessment.ContainsKey($key) -or [string]$membershipByAssessment[$key] -cne [string]$hostedIds[0]) {
            throw 'Assessment coverage and recommendation membership do not match'
        }
    }
    else {
        if ($hostedIds.Count -ne 0) {
            throw 'Deferred or excluded assessment coverage cannot reference Hosted IDs'
        }
        if ($membershipByAssessment.ContainsKey($key)) {
            throw 'Deferred or excluded assessment coverage cannot belong to a recommendation'
        }
    }
}

$presentations = [Collections.Generic.List[object]]::new()
$reviewStateCounts = [ordered]@{ recommended = 0; deferred = 0; excluded = 0 }
foreach ($entry in @($baseline.entries)) {
    $sourceKey = Get-SourceKey -SourceDefinitionId ([string]$entry.sourceRef.sourceDefinitionId) -SourceId ([string]$entry.sourceRef.sourceId)
    if (-not $inventoryRecords.ContainsKey($sourceKey) -or [string]$inventoryRecords[$sourceKey].contentSha256 -cne [string]$entry.sourceRef.contentSha256) {
        throw "Assessment baseline source does not resolve to inventory evidence: $($entry.sourceRef.sourceDefinitionId)/$($entry.sourceRef.sourceId)"
    }
    $currentRecord = $inventoryRecords[$sourceKey]
    $priorRecord = $null
    if ($null -ne $priorSourceGenerationInput) {
        $priorInventoryProperty = $priorSourceGenerationInput.Value.inventories.PSObject.Properties[[string]$entry.sourceRef.sourceDefinitionId]
        if ($null -ne $priorInventoryProperty) {
            $priorRecord = @($priorInventoryProperty.Value.records | Where-Object { [string]$_.sourceId -ceq [string]$entry.sourceRef.sourceId }) | Select-Object -First 1
        }
    }
    $sourceTransition = Get-SourceTransition -CurrentRecord $currentRecord -PriorRecord $priorRecord
    foreach ($assessment in @($entry.assessments)) {
        $assessmentRef = [ordered]@{
            assessmentBaselineSha256 = $baselineInput.Snapshot.Sha256
            sourceDefinitionId = [string]$entry.sourceRef.sourceDefinitionId
            sourceId = [string]$entry.sourceRef.sourceId
            contentSha256 = [string]$entry.sourceRef.contentSha256
            assessmentId = [string]$assessment.assessmentId
        }
        $assessmentKey = Get-AssessmentKey -Reference $assessmentRef
        if (-not $coverageByAssessment.ContainsKey($assessmentKey)) {
            throw 'Recommendation snapshot does not cover every baseline assessment'
        }
        $coverage = $coverageByAssessment[$assessmentKey]
        $reviewState = [string]$coverage.disposition
        $reviewStateCounts[$reviewState]++
        $hostedCategory = 'unassigned'
        $hostedId = $null
        $guardedTokenDelta = 0
        $recommendation = if ($reviewState -ceq 'excluded') { 'exclude' } else { 'defer' }
        if ($reviewState -ceq 'recommended') {
            if (@($coverage.hostedIds).Count -ne 1 -or -not $recommendationsById.ContainsKey([string]$coverage.hostedIds[0])) {
                throw 'Recommended assessment coverage must resolve to one Hosted rule change recommendation'
            }
            $ownedRecommendation = $recommendationsById[[string]$coverage.hostedIds[0]]
            $hostedCategory = [string]$ownedRecommendation.category
            $hostedId = [string]$ownedRecommendation.hostedId
            $guardedTokenDelta = [int]$ownedRecommendation.tokenProjection.guardedTokenDelta
            $recommendation = [string]$ownedRecommendation.recommendedAction
        }
        $presentations.Add([ordered]@{
            assessmentRef = $assessmentRef
            sourceTransition = $sourceTransition
            reviewState = $reviewState
            hostedCategory = $hostedCategory
            hostedId = $hostedId
            guardedTokenDelta = $guardedTokenDelta
            recommendation = $recommendation
        })
    }
}
if ($presentations.Count -ne $coverageByAssessment.Count) {
    throw 'Recommendation snapshot coverage contains assessments absent from the baseline'
}

$review = [ordered]@{
    '$schema' = 'assessment-reconciliation-review.schema.json'
    schemaVersion = 4
    generatedAt = ConvertTo-UtcTimestamp -Value $GeneratedAt
    readOnly = $true
    refreshMode = 'regenerate-read-only-review'
    snapshots = [ordered]@{
        stagedInventoryHashes = $inventoryHashes
        acceptedSourceGenerationSha256 = $expectedPriorSourceGenerationSha256
        assessmentBaselineSha256 = $baselineInput.Snapshot.Sha256
        hostedCatalogSha256 = $catalogInput.Snapshot.Sha256
        reconciliationContractSha256 = [string]$recommendationSnapshot.reconciliationContractSha256
        reviewContractSha256 = $reviewContractSha256
    }
    acceptedSourceGeneration = if ($null -eq $priorSourceGenerationInput) { $null } else { $priorSourceGenerationInput.Value }
    stagedInventories = $inventories
    assessmentBaseline = $baseline
    recommendationOutput = $recommendationSnapshot
    summary = [ordered]@{
        sourceCount = @($baseline.entries).Count
        assessmentCount = $presentations.Count
        recommendationCount = @($recommendationSnapshot.recommendations).Count
        reviewStateCounts = $reviewStateCounts
    }
    assessmentPresentations = @($presentations | Sort-Object -Property @{ Expression = { Get-AssessmentKey -Reference $_.assessmentRef } })
}
$reviewJson = $review | ConvertTo-Json -Depth 40
if (-not ($reviewJson | Test-Json -SchemaFile (Join-Path $reconciliationRoot 'assessment-reconciliation-review.schema.json') -ErrorAction Stop)) {
    throw 'Assessment reconciliation review does not satisfy its schema'
}
$outputSnapshot = Write-JsonSnapshot -Path $resolvedOutputPath -Value $review

$result = [ordered]@{
    status = 'passed'
    outputPath = $resolvedOutputPath
    sourceCount = $review.summary.sourceCount
    assessmentCount = $review.summary.assessmentCount
    recommendationCount = $review.summary.recommendationCount
    reviewSha256 = $outputSnapshot.Sha256
}
if ($OutputFormat -eq 'Json') {
    $result | ConvertTo-Json -Depth 5
}
else {
    Write-Output "Assessment reconciliation review generated: $($result.sourceCount) sources, $($result.assessmentCount) assessments, $($result.recommendationCount) recommendations"
    Write-Output "Output: $($result.outputPath)"
    Write-Output "Review SHA-256: $($result.reviewSha256)"
}
