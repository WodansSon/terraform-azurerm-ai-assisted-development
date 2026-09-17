[CmdletBinding()]
param(
    [string]$RepositoryRoot = (Join-Path $PSScriptRoot '../..'),

    [Parameter(Mandatory = $true)]
    [string[]]$AcceptedInventoryPaths,

    [string[]]$StagedInventoryPaths = @(),

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
        [Parameter(Mandatory = $true)][object]$AcceptedRecord,
        [object]$StagedRecord,
        [Parameter(Mandatory = $true)][bool]$HasStagedLane
    )

    if (-not $HasStagedLane) {
        return 'current'
    }
    if ($null -eq $StagedRecord -or [string]$StagedRecord.presence -ceq 'removed') {
        return 'removed'
    }
    if ([string]$AcceptedRecord.presence -ceq 'removed') {
        return 'reappeared'
    }
    if ([string]$AcceptedRecord.sourceLifecycle -cne [string]$StagedRecord.sourceLifecycle) {
        return 'source-lifecycle-changed'
    }
    if ([string]$AcceptedRecord.contentSha256 -cne [string]$StagedRecord.contentSha256) {
        return 'changed'
    }
    if ([string]$AcceptedRecord.location -cne [string]$StagedRecord.location) {
        return 'moved'
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
$baseline = $baselineInput.Value
$recommendationSnapshot = $recommendationInput.Value
$reviewContractSha256 = Get-AssessmentReconciliationReviewContractSha256 -Contract $reviewContractInput.Value -RepositoryRoot $resolvedRepositoryRoot

if ([string]$baseline.hostedCatalogSha256 -cne $catalogInput.Snapshot.Sha256 -or [string]$recommendationSnapshot.hostedCatalogSha256 -cne $catalogInput.Snapshot.Sha256) {
    throw 'Assessment reconciliation review inputs do not bind the supplied Hosted catalog'
}
if ([string]$recommendationSnapshot.assessmentBaselineSha256 -cne $baselineInput.Snapshot.Sha256) {
    throw 'Hosted rule change recommendations do not bind the supplied assessment baseline'
}
$baselineInventoryHashes = ConvertTo-OrdinalMap -Value $baseline.inventoryHashes
$recommendationInventoryHashes = ConvertTo-OrdinalMap -Value $recommendationSnapshot.inventoryHashes
$baselineInventoryJson = $baselineInventoryHashes | ConvertTo-Json -Compress
$recommendationInventoryJson = $recommendationInventoryHashes | ConvertTo-Json -Compress
if ($baselineInventoryJson -cne $recommendationInventoryJson) {
    throw 'Hosted rule change recommendations do not bind the assessment baseline inventories'
}

$acceptedRecords = @{}
$acceptedInventoryHashes = [ordered]@{}
foreach ($inventoryPath in $AcceptedInventoryPaths) {
    $inventoryInput = Read-JsonFile -Path ([IO.Path]::GetFullPath($inventoryPath)) -SchemaPath $inventorySchemaPath -Name 'Accepted source inventory'
    $inventory = $inventoryInput.Value
    if ($null -eq $inventory.acceptance) {
        throw "Assessment reconciliation review requires an accepted inventory: $inventoryPath"
    }
    Assert-SourceEvidenceAcceptedInventoryHistory -Inventory $inventory
    $sourceDefinitionId = [string]$inventory.sourceDefinitionId
    if ($acceptedInventoryHashes.Contains($sourceDefinitionId)) {
        throw "Assessment reconciliation review received duplicate accepted inventory lane: $sourceDefinitionId"
    }
    if (-not $baseline.inventoryHashes.PSObject.Properties[$sourceDefinitionId] -or [string]$baseline.inventoryHashes.$sourceDefinitionId -cne $inventoryInput.Snapshot.Sha256) {
        throw "Accepted inventory does not match the assessment baseline: $sourceDefinitionId"
    }
    $acceptedInventoryHashes[$sourceDefinitionId] = $inventoryInput.Snapshot.Sha256
    foreach ($record in @($inventory.records)) {
        $key = Get-SourceKey -SourceDefinitionId $sourceDefinitionId -SourceId ([string]$record.sourceId)
        if ($acceptedRecords.ContainsKey($key)) {
            throw "Accepted inventories contain duplicate source identity: $sourceDefinitionId/$($record.sourceId)"
        }
        $acceptedRecords[$key] = $record
    }
}
$acceptedInventoryHashes = ConvertTo-OrdinalMap -Value $acceptedInventoryHashes
if (($acceptedInventoryHashes | ConvertTo-Json -Compress) -cne $baselineInventoryJson) {
    throw 'Assessment reconciliation review requires every baseline inventory lane exactly once'
}

$stagedRecords = @{}
$stagedInventoryHashes = [ordered]@{}
$stagedLaneIds = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
foreach ($inventoryPath in $StagedInventoryPaths) {
    $inventoryInput = Read-JsonFile -Path ([IO.Path]::GetFullPath($inventoryPath)) -SchemaPath $inventorySchemaPath -Name 'Staged source inventory'
    $inventory = $inventoryInput.Value
    if ($null -ne $inventory.acceptance -or @($inventory.acceptedRevisions).Count -ne 0) {
        throw "Staged inventory cannot contain accepted state: $inventoryPath"
    }
    $sourceDefinitionId = [string]$inventory.sourceDefinitionId
    if (-not $stagedLaneIds.Add($sourceDefinitionId)) {
        throw "Assessment reconciliation review received duplicate staged inventory lane: $sourceDefinitionId"
    }
    if (-not $acceptedInventoryHashes.Contains($sourceDefinitionId)) {
        throw "Staged inventory has no accepted baseline lane: $sourceDefinitionId"
    }
    $stagedInventoryHashes[$sourceDefinitionId] = $inventoryInput.Snapshot.Sha256
    foreach ($record in @($inventory.records)) {
        $key = Get-SourceKey -SourceDefinitionId $sourceDefinitionId -SourceId ([string]$record.sourceId)
        if ($stagedRecords.ContainsKey($key)) {
            throw "Staged inventories contain duplicate source identity: $sourceDefinitionId/$($record.sourceId)"
        }
        $stagedRecords[$key] = $record
    }
}
$stagedInventoryHashes = ConvertTo-OrdinalMap -Value $stagedInventoryHashes

$recommendationsById = @{}
foreach ($recommendation in @($recommendationSnapshot.recommendations)) {
    $hostedId = [string]$recommendation.hostedId
    if ($recommendationsById.ContainsKey($hostedId)) {
        throw "Recommendation snapshot contains duplicate Hosted ID: $hostedId"
    }
    $recommendationsById[$hostedId] = $recommendation
}
$coverageByAssessment = @{}
foreach ($coverage in @($recommendationSnapshot.assessmentCoverage)) {
    $key = Get-AssessmentKey -Reference $coverage.assessmentRef
    if ($coverageByAssessment.ContainsKey($key)) {
        throw 'Recommendation snapshot contains duplicate assessment coverage'
    }
    $coverageByAssessment[$key] = $coverage
}

$presentations = [Collections.Generic.List[object]]::new()
$reviewStateCounts = [ordered]@{ recommended = 0; deferred = 0; excluded = 0 }
foreach ($entry in @($baseline.entries)) {
    $sourceKey = Get-SourceKey -SourceDefinitionId ([string]$entry.sourceRef.sourceDefinitionId) -SourceId ([string]$entry.sourceRef.sourceId)
    if (-not $acceptedRecords.ContainsKey($sourceKey) -or [string]$acceptedRecords[$sourceKey].contentSha256 -cne [string]$entry.sourceRef.contentSha256) {
        throw "Assessment baseline source does not resolve to accepted inventory evidence: $($entry.sourceRef.sourceDefinitionId)/$($entry.sourceRef.sourceId)"
    }
    $hasStagedLane = $stagedLaneIds.Contains([string]$entry.sourceRef.sourceDefinitionId)
    $stagedRecord = if ($stagedRecords.ContainsKey($sourceKey)) { $stagedRecords[$sourceKey] } else { $null }
    $sourceTransition = Get-SourceTransition -AcceptedRecord $acceptedRecords[$sourceKey] -StagedRecord $stagedRecord -HasStagedLane $hasStagedLane
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
    generatedAt = ConvertTo-SourceEvidenceUtcTimestamp -Value $GeneratedAt
    readOnly = $true
    refreshMode = 'regenerate-read-only-review'
    snapshots = [ordered]@{
        inventoryHashes = $acceptedInventoryHashes
        stagedInventoryHashes = $stagedInventoryHashes
        assessmentBaselineSha256 = $baselineInput.Snapshot.Sha256
        recommendationSnapshotSha256 = $recommendationInput.Snapshot.Sha256
        hostedCatalogSha256 = $catalogInput.Snapshot.Sha256
        reconciliationContractSha256 = [string]$recommendationSnapshot.reconciliationContractSha256
        reviewContractSha256 = $reviewContractSha256
    }
    summary = [ordered]@{
        sourceCount = @($baseline.entries).Count
        assessmentCount = $presentations.Count
        recommendationCount = @($recommendationSnapshot.recommendations).Count
        reviewStateCounts = $reviewStateCounts
    }
    recommendations = @($recommendationSnapshot.recommendations)
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
