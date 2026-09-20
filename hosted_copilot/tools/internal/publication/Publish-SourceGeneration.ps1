[CmdletBinding()]
param(
    [string]$RepositoryRoot = (Join-Path $PSScriptRoot '../../../..'),

    [Parameter(Mandatory = $true)]
    [string]$WorkbenchBundlePath,

    [Parameter(Mandatory = $true)]
    [string]$PublicationRequestPath,

    [string]$ExpectedPublicationRequestSha256,

    [switch]$Publish,

    [ValidateSet('Text', 'Json')]
    [string]$OutputFormat = 'Text'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$helpersPath = Join-Path $PSScriptRoot '../../modules/shared/HostedToolkit.Helpers.psm1'
$sourceEvidencePath = Join-Path $PSScriptRoot '../../modules/shared/SourceEvidenceValidation.psm1'
$reconciliationValidationPath = Join-Path $PSScriptRoot '../../modules/reconciliation/AssessmentReconciliationValidation.psm1'
Import-Module -Name $sourceEvidencePath -Force
Import-Module -Name $reconciliationValidationPath -Force
Import-Module -Name $helpersPath -Force

function Read-JsonSnapshot {
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
    return [pscustomobject]@{
        Value = $snapshot.Content | ConvertFrom-Json -DateKind String
        Snapshot = $snapshot
    }
}

function Get-AssessmentKey {
    param([Parameter(Mandatory = $true)][object]$Reference)

    return [string]$Reference.sourceDefinitionId + [char]0 + [string]$Reference.sourceId + [char]0 + [string]$Reference.contentSha256 + [char]0 + [string]$Reference.assessmentId
}

$resolvedRepositoryRoot = [IO.Path]::GetFullPath($RepositoryRoot).TrimEnd([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar)
$catalogRoot = Join-Path $resolvedRepositoryRoot 'hosted_copilot/copilot-rule-catalog'
$reconciliationRoot = Join-Path $catalogRoot 'assessment-reconciliation'
$generationRoot = Join-Path $catalogRoot 'source-generations'
$inventorySchemaPath = Join-Path $catalogRoot 'source-inventories/source-inventory.schema.json'
$baselineSchemaPath = Join-Path $catalogRoot 'rule-assessments/source-assessment-baseline-v4.schema.json'
$recommendationSchemaPath = Join-Path $reconciliationRoot 'hosted-rule-change-recommendations.schema.json'
$hostedCatalogPath = Join-Path $catalogRoot 'instruction-catalog.json'
$assessmentContractPath = Join-Path $catalogRoot 'rule-assessments/source-assessment-v4.json'
$reconciliationContractPath = Join-Path $reconciliationRoot 'assessment-reconciliation-v4.json'
$reviewContractPath = Join-Path $reconciliationRoot 'assessment-reconciliation-review-v4.json'
$bundleInput = Read-JsonSnapshot -Path ([IO.Path]::GetFullPath($WorkbenchBundlePath)) -SchemaPath (Join-Path $reconciliationRoot 'assessment-reconciliation-review-v4.schema.json') -Name 'Workbench bundle'
$requestInput = Read-JsonSnapshot -Path ([IO.Path]::GetFullPath($PublicationRequestPath)) -SchemaPath (Join-Path $generationRoot 'publication-request.schema.json') -Name 'Publication request'
$bundle = $bundleInput.Value
$request = $requestInput.Value

$hostedCatalogSnapshot = Get-FileSnapshot -Path $hostedCatalogPath
if ([string]$bundle.snapshots.hostedCatalogSha256 -cne $hostedCatalogSnapshot.Sha256) {
    throw 'Workbench bundle Hosted catalog identity is stale'
}
$assessmentContract = (Get-FileSnapshot -Path $assessmentContractPath).Content | ConvertFrom-Json
$currentAssessmentContractSha256 = Get-SourceAssessmentContractSha256 -Contract $assessmentContract -RepositoryRoot $resolvedRepositoryRoot
if ([string]$bundle.assessmentBaseline.assessmentContractSha256 -cne $currentAssessmentContractSha256) {
    throw 'Workbench bundle source assessment contract identity is stale'
}
$currentRunConfigurationSha256 = Get-SourceAssessmentRunConfigurationSha256 -RunConfiguration $bundle.assessmentBaseline.runConfiguration
if ([string]$bundle.assessmentBaseline.assessmentRunConfigurationSha256 -cne $currentRunConfigurationSha256) {
    throw 'Workbench bundle source assessment run configuration identity is inconsistent'
}
$reconciliationContract = (Get-FileSnapshot -Path $reconciliationContractPath).Content | ConvertFrom-Json
$currentReconciliationContractSha256 = Get-HostedRuleChangeRecommendationsContractSha256 -Contract $reconciliationContract -RepositoryRoot $resolvedRepositoryRoot
if ([string]$bundle.snapshots.reconciliationContractSha256 -cne $currentReconciliationContractSha256 -or [string]$bundle.recommendationOutput.reconciliationContractSha256 -cne $currentReconciliationContractSha256) {
    throw 'Workbench bundle reconciliation contract identity is stale'
}
$reviewContract = (Get-FileSnapshot -Path $reviewContractPath).Content | ConvertFrom-Json
$currentReviewContractSha256 = Get-AssessmentReconciliationReviewContractSha256 -Contract $reviewContract -RepositoryRoot $resolvedRepositoryRoot
if ([string]$bundle.snapshots.reviewContractSha256 -cne $currentReviewContractSha256) {
    throw 'Workbench bundle review contract identity is stale'
}

if ([string]$request.workbenchBundleSha256 -cne $bundleInput.Snapshot.Sha256) {
    throw 'Publication request does not bind the exact Workbench bundle bytes'
}
if ($Publish -and [string]::IsNullOrWhiteSpace($ExpectedPublicationRequestSha256)) {
    throw 'Publish requires ExpectedPublicationRequestSha256 from a prior preview'
}
if (-not [string]::IsNullOrWhiteSpace($ExpectedPublicationRequestSha256) -and [string]$ExpectedPublicationRequestSha256 -cne $requestInput.Snapshot.Sha256) {
    throw "Publication request hash mismatch: expected $ExpectedPublicationRequestSha256, actual $($requestInput.Snapshot.Sha256)"
}

$expectedSourceDefinitionIds = @(Get-ExpectedSourceDefinitionIds -RepositoryRoot $resolvedRepositoryRoot)
[string[]]$actualSourceDefinitionIds = @($bundle.stagedInventories.PSObject.Properties.Name)
[Array]::Sort($actualSourceDefinitionIds, [StringComparer]::Ordinal)
if (@(Compare-Object $expectedSourceDefinitionIds $actualSourceDefinitionIds -SyncWindow 0).Count -ne 0) {
    throw "Workbench bundle must contain exactly the approved source lanes: $($expectedSourceDefinitionIds -join ', ')"
}
$inventoryHashes = [ordered]@{}
foreach ($sourceDefinitionId in $actualSourceDefinitionIds) {
    $inventory = $bundle.stagedInventories.PSObject.Properties[$sourceDefinitionId].Value
    if (-not (($inventory | ConvertTo-Json -Depth 40) | Test-Json -SchemaFile $inventorySchemaPath -ErrorAction Stop)) {
        throw "Workbench bundle inventory does not satisfy its schema: $sourceDefinitionId"
    }
    $sourceEvidence = Get-CurrentSourceDefinitionEvidence -RepositoryRoot $resolvedRepositoryRoot -SourceDefinitionId $sourceDefinitionId
    Assert-CurrentSourceInventory -Inventory $inventory -Evidence $sourceEvidence
    $runDefinition = @($bundle.assessmentBaseline.runConfiguration.sourceDefinitions | Where-Object { [string]$_.sourceDefinitionId -ceq $sourceDefinitionId })
    if ($runDefinition.Count -ne 1 -or
        [string]$runDefinition[0].sourceDefinitionSha256 -cne [string]$sourceEvidence.SourceDefinitionSha256 -or
        [string]$runDefinition[0].parserContractSha256 -cne [string]$sourceEvidence.ParserContractSha256 -or
        [string]$runDefinition[0].inventoryConfigurationSha256 -cne [string]$sourceEvidence.InventoryConfigurationSha256 -or
        [int]$runDefinition[0].assessmentBatchSize -ne [int]$sourceEvidence.AssessmentBatchSize -or
        [string]$runDefinition[0].assessmentCardinality -cne [string]$sourceEvidence.AssessmentCardinality) {
        throw "Workbench bundle assessment run configuration is stale: $sourceDefinitionId"
    }
    if ([string]$inventory.sourceDefinitionId -cne $sourceDefinitionId) {
        throw "Workbench bundle inventory key does not match sourceDefinitionId: $sourceDefinitionId"
    }
    $snapshotProperty = $bundle.snapshots.stagedInventoryHashes.PSObject.Properties[$sourceDefinitionId]
    if ($null -eq $snapshotProperty) {
        throw "Workbench bundle is missing staged inventory hash: $sourceDefinitionId"
    }
    $embeddedInventorySha256 = Get-JsonSnapshotSha256 -Value $inventory
    if ($embeddedInventorySha256 -cne [string]$snapshotProperty.Value) {
        throw "Workbench bundle embedded inventory does not match its snapshot hash: $sourceDefinitionId"
    }
    $inventoryHashes[$sourceDefinitionId] = $embeddedInventorySha256
}
if (@($bundle.snapshots.stagedInventoryHashes.PSObject.Properties).Count -ne $actualSourceDefinitionIds.Count) {
    throw 'Workbench bundle staged inventory hashes do not match its inventory lane set'
}

$baselineJson = $bundle.assessmentBaseline | ConvertTo-Json -Depth 40
if (-not ($baselineJson | Test-Json -SchemaFile $baselineSchemaPath -ErrorAction Stop)) {
    throw 'Workbench bundle assessment baseline does not satisfy its schema'
}
$embeddedBaselineSha256 = Get-JsonSnapshotSha256 -Value $bundle.assessmentBaseline
if ($embeddedBaselineSha256 -cne [string]$bundle.snapshots.assessmentBaselineSha256) {
    throw 'Workbench bundle embedded assessment baseline does not match its snapshot hash'
}
$recommendationJson = $bundle.recommendationOutput | ConvertTo-Json -Depth 40
if (-not ($recommendationJson | Test-Json -SchemaFile $recommendationSchemaPath -ErrorAction Stop)) {
    throw 'Workbench bundle recommendation output does not satisfy its schema'
}
if ([string]$bundle.recommendationOutput.assessmentBaselineSha256 -cne [string]$bundle.snapshots.assessmentBaselineSha256) {
    throw 'Workbench bundle recommendation output does not bind its assessment baseline'
}
if ([string]$bundle.recommendationOutput.hostedCatalogSha256 -cne [string]$bundle.snapshots.hostedCatalogSha256) {
    throw 'Workbench bundle recommendation output does not bind its Hosted catalog'
}
if (($null -eq $bundle.assessmentBaseline.priorSourceGenerationSha256 -and $null -ne $bundle.snapshots.acceptedSourceGenerationSha256) -or
    ($null -ne $bundle.assessmentBaseline.priorSourceGenerationSha256 -and [string]$bundle.assessmentBaseline.priorSourceGenerationSha256 -cne [string]$bundle.snapshots.acceptedSourceGenerationSha256)) {
    throw 'Workbench bundle assessment baseline does not bind its accepted source generation'
}
$baselineInventoryHashes = (ConvertTo-OrdinalMap -Value $bundle.assessmentBaseline.inventoryHashes) | ConvertTo-Json -Compress
$recommendationInventoryHashes = (ConvertTo-OrdinalMap -Value $bundle.recommendationOutput.inventoryHashes) | ConvertTo-Json -Compress
$bundleInventoryHashes = (ConvertTo-OrdinalMap -Value $inventoryHashes) | ConvertTo-Json -Compress
if ($baselineInventoryHashes -cne $bundleInventoryHashes -or $recommendationInventoryHashes -cne $bundleInventoryHashes) {
    throw 'Workbench bundle inventory hash bindings are inconsistent'
}

$expectedAssessmentKeys = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
foreach ($entry in @($bundle.assessmentBaseline.entries)) {
    foreach ($assessment in @($entry.assessments)) {
        $reference = [ordered]@{
            sourceDefinitionId = [string]$entry.sourceRef.sourceDefinitionId
            sourceId = [string]$entry.sourceRef.sourceId
            contentSha256 = [string]$entry.sourceRef.contentSha256
            assessmentId = [string]$assessment.assessmentId
        }
        if (-not $expectedAssessmentKeys.Add((Get-AssessmentKey -Reference $reference))) {
            throw 'Workbench bundle assessment baseline contains duplicate assessment identity'
        }
    }
}
$coveredAssessmentKeys = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
foreach ($coverage in @($bundle.recommendationOutput.assessmentCoverage)) {
    if (-not $coveredAssessmentKeys.Add((Get-AssessmentKey -Reference $coverage.assessmentRef))) {
        throw 'Workbench bundle recommendation output contains duplicate assessment coverage'
    }
}
if ($expectedAssessmentKeys.Count -ne $coveredAssessmentKeys.Count -or @($expectedAssessmentKeys | Where-Object { -not $coveredAssessmentKeys.Contains($_) }).Count -ne 0) {
    throw 'Workbench bundle recommendation output does not cover every baseline assessment exactly once'
}

$currentPath = Join-Path $generationRoot 'current.json'
$historyRoot = Join-Path $generationRoot 'history'
$expectedCurrentSha256 = if ($null -eq $bundle.snapshots.acceptedSourceGenerationSha256) { $null } else { [string]$bundle.snapshots.acceptedSourceGenerationSha256 }
$priorSourceGeneration = $bundle.acceptedSourceGeneration
if (($null -eq $priorSourceGeneration -and $null -ne $expectedCurrentSha256) -or ($null -ne $priorSourceGeneration -and $null -eq $expectedCurrentSha256)) {
    throw 'Workbench bundle accepted source generation does not match its snapshot identity'
}
if ($null -ne $priorSourceGeneration) {
    Assert-SourceGenerationIntegrity -SourceGeneration $priorSourceGeneration -RepositoryRoot $resolvedRepositoryRoot -ExpectedSha256 $expectedCurrentSha256
}
$acceptedAt = ConvertTo-UtcTimestamp -Value $request.acceptance.acceptedAt
$acceptedInventories = [ordered]@{}
foreach ($sourceDefinitionId in $actualSourceDefinitionIds) {
    $stagedInventory = $bundle.stagedInventories.PSObject.Properties[$sourceDefinitionId].Value
    $acceptedInventory = ($stagedInventory | ConvertTo-Json -Depth 40 -Compress) | ConvertFrom-Json -DateKind String
    $acceptedInventory.records = @(Get-SourceInventoryProjectionRecords -CurrentInventory $stagedInventory -PriorSourceGeneration $priorSourceGeneration -RemovedAt $acceptedAt)
    $acceptedInventory.collection.inventorySha256 = Get-SourceEvidenceRecordsSha256 -Records @($acceptedInventory.records)
    Assert-SourceInventoryIntegrity -Inventory $acceptedInventory
    $acceptedInventories[$sourceDefinitionId] = $acceptedInventory
}
$acceptedInventories = ConvertTo-OrdinalMap -Value $acceptedInventories
$baselineSourceKeys = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
foreach ($entry in @($bundle.assessmentBaseline.entries)) {
    $null = $baselineSourceKeys.Add("$([string]$entry.sourceRef.sourceDefinitionId):$([string]$entry.sourceRef.sourceId):$([string]$entry.sourceRef.contentSha256)")
}
foreach ($sourceDefinitionId in $actualSourceDefinitionIds) {
    foreach ($record in @($acceptedInventories[$sourceDefinitionId].records)) {
        $sourceKey = "$sourceDefinitionId`:$([string]$record.sourceId):$([string]$record.contentSha256)"
        if (-not $baselineSourceKeys.Remove($sourceKey)) {
            throw "Accepted source generation record does not have exact assessment baseline coverage: $sourceDefinitionId/$($record.sourceId)"
        }
    }
}
if ($baselineSourceKeys.Count -ne 0) {
    throw 'Assessment baseline contains source references outside the accepted inventory projection'
}
$generation = [ordered]@{
    '$schema' = 'source-generation.schema.json'
    schemaVersion = 1
    publishedAt = $acceptedAt
    previousSourceGenerationSha256 = $expectedCurrentSha256
    workbenchBundleSha256 = $bundleInput.Snapshot.Sha256
    publicationRequestSha256 = $requestInput.Snapshot.Sha256
    hostedCatalogSha256 = [string]$bundle.snapshots.hostedCatalogSha256
    acceptance = [ordered]@{
        acceptedAt = $acceptedAt
        acceptedBy = $request.acceptance.acceptedBy
        rationale = [string]$request.acceptance.rationale
    }
    inventories = $acceptedInventories
    assessmentBaseline = $bundle.assessmentBaseline
}
$generationBytes = [Text.UTF8Encoding]::new($false).GetBytes(($generation | ConvertTo-Json -Depth 60) + "`n")
$generationSha256 = Get-Sha256 -Bytes $generationBytes
$generationJson = [Text.UTF8Encoding]::new($false, $true).GetString($generationBytes)
$generatedSourceGeneration = $generationJson | ConvertFrom-Json -DateKind String
Assert-SourceGenerationIntegrity -SourceGeneration $generatedSourceGeneration -RepositoryRoot $resolvedRepositoryRoot -ExpectedSha256 $generationSha256

if ($Publish) {
    if (-not (Test-Path -LiteralPath $generationRoot -PathType Container)) {
        $null = New-Item -ItemType Directory -Path $generationRoot -Force
    }
    $lockPath = Join-Path $generationRoot 'current.json.lock'
    $lockStream = $null
    try {
        try {
            $lockStream = [IO.File]::Open($lockPath, [IO.FileMode]::OpenOrCreate, [IO.FileAccess]::Write, [IO.FileShare]::None)
        }
        catch [IO.IOException] {
            throw 'Source generation is already being published'
        }
        $actualCurrentSha256 = if (Test-Path -LiteralPath $currentPath -PathType Leaf) { Get-Sha256 -Path $currentPath } else { $null }
        if (($null -eq $expectedCurrentSha256 -and $null -ne $actualCurrentSha256) -or ($null -ne $expectedCurrentSha256 -and $actualCurrentSha256 -cne $expectedCurrentSha256)) {
            throw "Source generation precondition failed: expected $expectedCurrentSha256, actual $actualCurrentSha256"
        }
        $historyPath = Join-Path $historyRoot "$generationSha256.json"
        if (Test-Path -LiteralPath $historyPath -PathType Leaf) {
            if ((Get-Sha256 -Path $historyPath) -cne $generationSha256) {
                throw "Source generation history hash mismatch: $historyPath"
            }
        }
        else {
            if (-not (Test-Path -LiteralPath $historyRoot -PathType Container)) {
                $null = New-Item -ItemType Directory -Path $historyRoot -Force
            }
            $historyTemporaryPath = Join-Path $historyRoot ('.history.' + [guid]::NewGuid().ToString('N') + '.tmp')
            try {
                [IO.File]::WriteAllBytes($historyTemporaryPath, $generationBytes)
                if ((Get-Sha256 -Path $historyTemporaryPath) -cne $generationSha256) {
                    throw 'Temporary source generation history hash does not match generated bytes'
                }
                try {
                    [IO.File]::Move($historyTemporaryPath, $historyPath, $false)
                }
                catch [IO.IOException] {
                    if (-not (Test-Path -LiteralPath $historyPath -PathType Leaf) -or (Get-Sha256 -Path $historyPath) -cne $generationSha256) {
                        throw "Source generation history collision: $historyPath"
                    }
                }
            }
            finally {
                Remove-Item -LiteralPath $historyTemporaryPath -Force -ErrorAction SilentlyContinue
            }
        }
        $temporaryPath = Join-Path $generationRoot ('.current.' + [guid]::NewGuid().ToString('N') + '.tmp')
        try {
            [IO.File]::WriteAllBytes($temporaryPath, $generationBytes)
            $replacementCurrentSha256 = if (Test-Path -LiteralPath $currentPath -PathType Leaf) { Get-Sha256 -Path $currentPath } else { $null }
            if (($null -eq $expectedCurrentSha256 -and $null -ne $replacementCurrentSha256) -or ($null -ne $expectedCurrentSha256 -and $replacementCurrentSha256 -cne $expectedCurrentSha256)) {
                throw "Source generation precondition failed before replacement: expected $expectedCurrentSha256, actual $replacementCurrentSha256"
            }
            [IO.File]::Move($temporaryPath, $currentPath, $true)
        }
        finally {
            Remove-Item -LiteralPath $temporaryPath -Force -ErrorAction SilentlyContinue
        }
        if ((Get-Sha256 -Path $currentPath) -cne $generationSha256) {
            throw 'Published source generation hash does not match the previewed generation'
        }
    }
    finally {
        if ($null -ne $lockStream) {
            $lockStream.Dispose()
        }
    }
}

$result = [ordered]@{
    status = 'passed'
    mode = if ($Publish) { 'published' } else { 'preview' }
    publicationRequestSha256 = $requestInput.Snapshot.Sha256
    workbenchBundleSha256 = $bundleInput.Snapshot.Sha256
    previousSourceGenerationSha256 = $expectedCurrentSha256
    sourceGenerationSha256 = $generationSha256
    sourceDefinitionIds = $actualSourceDefinitionIds
    sourceCount = @($bundle.assessmentBaseline.entries).Count
    assessmentCount = $expectedAssessmentKeys.Count
}
if ($OutputFormat -eq 'Json') {
    $result | ConvertTo-Json -Depth 5
}
else {
    Write-Output "Source generation $($result.mode): $($result.sourceGenerationSha256)"
    Write-Output "Publication request SHA-256: $($result.publicationRequestSha256)"
    Write-Output "Workbench bundle SHA-256: $($result.workbenchBundleSha256)"
}
