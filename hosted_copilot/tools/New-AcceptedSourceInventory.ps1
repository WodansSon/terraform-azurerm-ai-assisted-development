[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$StagedInventoryPath,

    [string]$CurrentAcceptedInventoryPath,

    [Parameter(Mandatory = $true)]
    [string]$OutputPath,

    [Parameter(Mandatory = $true)]
    [string]$AcceptedBy,

    [string]$Rationale,

    [datetime]$AcceptedAt = [DateTime]::UtcNow,

    [ValidateSet('Text', 'Json')]
    [string]$OutputFormat = 'Text'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repositoryRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..')).TrimEnd([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar)
$repositoryPrefix = $repositoryRoot + [IO.Path]::DirectorySeparatorChar
$schemaPath = Join-Path $PSScriptRoot '../copilot-rule-catalog/source-inventories/source-inventory.schema.json'
$resolvedStagedPath = [IO.Path]::GetFullPath($StagedInventoryPath)
$resolvedOutputPath = [IO.Path]::GetFullPath($OutputPath)
if ($resolvedOutputPath.StartsWith($repositoryPrefix, [StringComparison]::OrdinalIgnoreCase)) {
    throw 'Accepted inventory export must be written outside the repository root'
}
if ([string]::IsNullOrWhiteSpace($AcceptedBy)) {
    throw 'AcceptedBy cannot be empty'
}

function Get-FileSha256 {
    param([Parameter(Mandatory = $true)][string]$Path)

    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function Get-ContentSha256 {
    param([Parameter(Mandatory = $true)][AllowEmptyString()][string]$Content)

    $bytes = [Text.Encoding]::UTF8.GetBytes($Content)
    return [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($bytes)).ToLowerInvariant()
}

function Test-InventoryFile {
    param([Parameter(Mandatory = $true)][string]$Path)

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "Source inventory was not found: $Path"
    }
    $json = Get-Content -LiteralPath $Path -Raw
    if (-not (Test-Json -Json $json -SchemaFile $schemaPath -ErrorAction Stop)) {
        throw "Source inventory does not satisfy its schema: $Path"
    }
    return $json | ConvertFrom-Json
}

function Get-RecordsSha256 {
    param([Parameter(Mandatory = $true)][object[]]$Records)

    return Get-ContentSha256 -Content ($Records | ConvertTo-Json -Depth 30 -Compress)
}

function Get-SortedRecords {
    param([Parameter(Mandatory = $true)][object[]]$Records)

    $sorted = [Collections.Generic.List[object]]::new()
    foreach ($record in $Records) {
        $sorted.Add($record)
    }
    $sorted.Sort([Comparison[object]]{
        param($left, $right)
        return [StringComparer]::Ordinal.Compare([string]$left.sourceId, [string]$right.sourceId)
    })
    return $sorted.ToArray()
}

function Copy-JsonObject {
    param([Parameter(Mandatory = $true)][object]$Value)

    return ($Value | ConvertTo-Json -Depth 40 -Compress) | ConvertFrom-Json
}

function Write-JsonAtomically {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][object]$Value
    )

    $directory = Split-Path -Parent $Path
    if (-not (Test-Path -LiteralPath $directory -PathType Container)) {
        $null = New-Item -ItemType Directory -Path $directory -Force
    }
    $temporaryPath = Join-Path $directory ('.' + [IO.Path]::GetFileName($Path) + '.' + [guid]::NewGuid().ToString('N') + '.tmp')
    try {
        [IO.File]::WriteAllText($temporaryPath, (($Value | ConvertTo-Json -Depth 40) + "`n"), [Text.UTF8Encoding]::new($false))
        [IO.File]::Move($temporaryPath, $Path, $true)
    }
    finally {
        Remove-Item -LiteralPath $temporaryPath -Force -ErrorAction SilentlyContinue
    }
}

$staged = Test-InventoryFile -Path $resolvedStagedPath
if ($null -ne $staged.acceptance -or @($staged.acceptedRevisions).Count -ne 0) {
    throw 'Staged inventory must not contain acceptance metadata or accepted revision history'
}
$stagedRecords = @(Get-SortedRecords -Records @($staged.records))
if ((Get-RecordsSha256 -Records $stagedRecords) -cne [string]$staged.collection.inventorySha256) {
    throw 'Staged inventory record hash does not match collection.inventorySha256'
}

$current = $null
$previousAcceptedInventorySha256 = $null
if (-not [string]::IsNullOrWhiteSpace($CurrentAcceptedInventoryPath)) {
    $resolvedCurrentPath = [IO.Path]::GetFullPath($CurrentAcceptedInventoryPath)
    $current = Test-InventoryFile -Path $resolvedCurrentPath
    if ($null -eq $current.acceptance) {
        throw 'Current accepted inventory does not contain acceptance metadata'
    }
    if ([string]$current.sourceDefinitionId -cne [string]$staged.sourceDefinitionId) {
        throw 'Staged and accepted inventories have different sourceDefinitionId values'
    }
    $currentRecords = @(Get-SortedRecords -Records @($current.records))
    if ((Get-RecordsSha256 -Records $currentRecords) -cne [string]$current.collection.inventorySha256) {
        throw 'Current accepted inventory record hash does not match collection.inventorySha256'
    }
    $previousAcceptedInventorySha256 = Get-FileSha256 -Path $resolvedCurrentPath
}

$stagedById = @{}
foreach ($record in $stagedRecords) {
    if ($stagedById.ContainsKey([string]$record.sourceId)) {
        throw "Staged inventory contains duplicate source ID: $($record.sourceId)"
    }
    $stagedById[[string]$record.sourceId] = $record
}
$currentById = @{}
if ($null -ne $current) {
    foreach ($record in @($current.records)) {
        if ($currentById.ContainsKey([string]$record.sourceId)) {
            throw "Current accepted inventory contains duplicate source ID: $($record.sourceId)"
        }
        $currentById[[string]$record.sourceId] = $record
    }
}

[string[]]$allSourceIds = @($stagedById.Keys + $currentById.Keys | Select-Object -Unique)
[Array]::Sort($allSourceIds, [StringComparer]::Ordinal)
$acceptedRecords = [Collections.Generic.List[object]]::new()
$comparison = [Collections.Generic.List[object]]::new()
$acceptedAtText = $AcceptedAt.ToUniversalTime().ToString('o')
foreach ($sourceId in $allSourceIds) {
    $hasStaged = $stagedById.ContainsKey($sourceId)
    $hasCurrent = $currentById.ContainsKey($sourceId)
    $transitions = [Collections.Generic.List[string]]::new()
    if ($hasStaged) {
        $acceptedRecord = Copy-JsonObject -Value $stagedById[$sourceId]
        if (-not $hasCurrent) {
            $transitions.Add('added')
        }
        elseif ([string]$currentById[$sourceId].presence -ceq 'removed') {
            $transitions.Add('reappeared')
        }
        else {
            if ([string]$currentById[$sourceId].contentSha256 -cne [string]$acceptedRecord.contentSha256) {
                $transitions.Add('content-changed')
            }
            if ([string]$currentById[$sourceId].location -cne [string]$acceptedRecord.location) {
                $transitions.Add('moved')
            }
            if ([string]$currentById[$sourceId].sourceLifecycle -cne [string]$acceptedRecord.sourceLifecycle) {
                $transitions.Add('lifecycle-changed')
            }
            if ($transitions.Count -eq 0) {
                $transitions.Add('unchanged')
            }
        }
        $acceptedRecords.Add($acceptedRecord)
    }
    elseif ([string]$currentById[$sourceId].presence -ceq 'removed') {
        $acceptedRecords.Add((Copy-JsonObject -Value $currentById[$sourceId]))
        $transitions.Add('unchanged')
    }
    else {
        $removedRecord = Copy-JsonObject -Value $currentById[$sourceId]
        $removedRecord.presence = 'removed'
        $removedRecord | Add-Member -NotePropertyName removedAt -NotePropertyValue $acceptedAtText
        $acceptedRecords.Add($removedRecord)
        $transitions.Add('removed')
    }
    $comparison.Add([ordered]@{ sourceId = $sourceId; transitions = $transitions.ToArray() })
}

$acceptedRecords = @(Get-SortedRecords -Records $acceptedRecords.ToArray())
$acceptedRevisions = [Collections.Generic.List[object]]::new()
if ($null -ne $current) {
    foreach ($revision in @($current.acceptedRevisions)) {
        $acceptedRevisions.Add($revision)
    }
    $acceptedRevisions.Add([ordered]@{
        '$schema' = [string]$current.'$schema'
        schemaVersion = [int]$current.schemaVersion
        sourceDefinitionId = [string]$current.sourceDefinitionId
        sourceDefinitionSha256 = [string]$current.sourceDefinitionSha256
        inventoryConfigurationSha256 = [string]$current.inventoryConfigurationSha256
        collectorVersion = [int]$current.collectorVersion
        parserId = [string]$current.parserId
        parserContractSha256 = [string]$current.parserContractSha256
        collectedAt = [string]$current.collectedAt
        collection = $current.collection
        acceptance = $current.acceptance
        records = @($current.records)
    })
}

$acceptance = [ordered]@{
    acceptedAt = $acceptedAtText
    acceptedBy = $AcceptedBy
    stagedInventorySha256 = Get-FileSha256 -Path $resolvedStagedPath
    previousAcceptedInventorySha256 = $previousAcceptedInventorySha256
}
if (-not [string]::IsNullOrWhiteSpace($Rationale)) {
    $acceptance.rationale = $Rationale
}

$accepted = [ordered]@{
    '$schema' = [string]$staged.'$schema'
    schemaVersion = [int]$staged.schemaVersion
    sourceDefinitionId = [string]$staged.sourceDefinitionId
    sourceDefinitionSha256 = [string]$staged.sourceDefinitionSha256
    inventoryConfigurationSha256 = [string]$staged.inventoryConfigurationSha256
    collectorVersion = [int]$staged.collectorVersion
    parserId = [string]$staged.parserId
    parserContractSha256 = [string]$staged.parserContractSha256
    collectedAt = [string]$staged.collectedAt
    collection = [ordered]@{
        complete = $true
        sourceRevision = $staged.collection.sourceRevision
        inventorySha256 = Get-RecordsSha256 -Records $acceptedRecords
    }
    acceptance = $acceptance
    acceptedRevisions = @($acceptedRevisions.ToArray())
    records = $acceptedRecords
}
$acceptedJson = $accepted | ConvertTo-Json -Depth 40
if (-not (Test-Json -Json $acceptedJson -SchemaFile $schemaPath -ErrorAction Stop)) {
    throw 'Accepted inventory export does not satisfy its schema'
}
Write-JsonAtomically -Path $resolvedOutputPath -Value $accepted

$transitionCounts = [ordered]@{}
foreach ($transition in @('unchanged', 'added', 'content-changed', 'moved', 'lifecycle-changed', 'removed', 'reappeared')) {
    $transitionCounts[$transition] = @($comparison | Where-Object { $_.transitions -contains $transition }).Count
}
$result = [ordered]@{
    status = 'passed'
    sourceDefinitionId = [string]$accepted.sourceDefinitionId
    outputPath = $resolvedOutputPath
    recordCount = $acceptedRecords.Count
    transitionCounts = $transitionCounts
    comparison = $comparison.ToArray()
}
if ($OutputFormat -eq 'Json') {
    $result | ConvertTo-Json -Depth 10
}
else {
    Write-Output "Accepted inventory exported: $($result.sourceDefinitionId) ($($result.recordCount) records)"
    Write-Output "Output: $($result.outputPath)"
    Write-Output "Transitions: $(@($transitionCounts.GetEnumerator() | ForEach-Object { "$($_.Key)=$($_.Value)" }) -join ', ')"
}
