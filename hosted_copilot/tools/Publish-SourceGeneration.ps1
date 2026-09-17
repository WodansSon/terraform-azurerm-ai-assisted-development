[CmdletBinding()]
param(
    [string]$RepositoryRoot = (Join-Path $PSScriptRoot '../..'),

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

$helpersPath = Join-Path $PSScriptRoot 'HostedToolkit.Helpers.psm1'
$sourceEvidencePath = Join-Path $PSScriptRoot 'SourceEvidenceValidation.psm1'
Import-Module -Name $sourceEvidencePath -Force
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
$baselineSchemaPath = Join-Path $catalogRoot 'rule-assessments/source-assessment-baseline.schema.json'
$recommendationSchemaPath = Join-Path $reconciliationRoot 'hosted-rule-change-recommendations.schema.json'
$bundleInput = Read-JsonSnapshot -Path ([IO.Path]::GetFullPath($WorkbenchBundlePath)) -SchemaPath (Join-Path $reconciliationRoot 'assessment-reconciliation-review.schema.json') -Name 'Workbench bundle'
$requestInput = Read-JsonSnapshot -Path ([IO.Path]::GetFullPath($PublicationRequestPath)) -SchemaPath (Join-Path $generationRoot 'publication-request.schema.json') -Name 'Publication request'
$bundle = $bundleInput.Value
$request = $requestInput.Value

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
    Assert-SourceInventoryIntegrity -Inventory $inventory
    if ([string]$inventory.sourceDefinitionId -cne $sourceDefinitionId) {
        throw "Workbench bundle inventory key does not match sourceDefinitionId: $sourceDefinitionId"
    }
    $snapshotProperty = $bundle.snapshots.stagedInventoryHashes.PSObject.Properties[$sourceDefinitionId]
    if ($null -eq $snapshotProperty) {
        throw "Workbench bundle is missing staged inventory hash: $sourceDefinitionId"
    }
    $inventoryHashes[$sourceDefinitionId] = [string]$snapshotProperty.Value
}
if (@($bundle.snapshots.stagedInventoryHashes.PSObject.Properties).Count -ne $actualSourceDefinitionIds.Count) {
    throw 'Workbench bundle staged inventory hashes do not match its inventory lane set'
}

$baselineJson = $bundle.assessmentBaseline | ConvertTo-Json -Depth 40
if (-not ($baselineJson | Test-Json -SchemaFile $baselineSchemaPath -ErrorAction Stop)) {
    throw 'Workbench bundle assessment baseline does not satisfy its schema'
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
$generation = [ordered]@{
    '$schema' = 'source-generation.schema.json'
    schemaVersion = 1
    publishedAt = ConvertTo-SourceEvidenceUtcTimestamp -Value $request.acceptance.acceptedAt
    previousSourceGenerationSha256 = $expectedCurrentSha256
    workbenchBundleSha256 = $bundleInput.Snapshot.Sha256
    publicationRequestSha256 = $requestInput.Snapshot.Sha256
    hostedCatalogSha256 = [string]$bundle.snapshots.hostedCatalogSha256
    acceptance = $request.acceptance
    inventories = ConvertTo-OrdinalMap -Value $bundle.stagedInventories
    assessmentBaseline = $bundle.assessmentBaseline
}
$generationBytes = [Text.UTF8Encoding]::new($false).GetBytes(($generation | ConvertTo-Json -Depth 60) + "`n")
$generationSha256 = Get-Sha256 -Bytes $generationBytes
$generationJson = [Text.UTF8Encoding]::new($false, $true).GetString($generationBytes)
if (-not ($generationJson | Test-Json -SchemaFile (Join-Path $generationRoot 'source-generation.schema.json') -ErrorAction Stop)) {
    throw 'Generated source generation does not satisfy its schema'
}

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
            [IO.File]::WriteAllBytes($historyPath, $generationBytes)
        }
        $temporaryPath = Join-Path $generationRoot ('.current.' + [guid]::NewGuid().ToString('N') + '.tmp')
        try {
            [IO.File]::WriteAllBytes($temporaryPath, $generationBytes)
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
