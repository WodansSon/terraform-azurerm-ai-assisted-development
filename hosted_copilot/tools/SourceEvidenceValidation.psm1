Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$hostedToolkitHelpersPath = Join-Path $PSScriptRoot 'HostedToolkit.Helpers.psm1'
Import-Module -Name $hostedToolkitHelpersPath -Force

function ConvertTo-SourceEvidenceUtcDateTime {
    param([Parameter(Mandatory = $true)][object]$Value)

    try {
        if ($Value -is [datetimeoffset]) {
            return ([datetimeoffset]$Value).UtcDateTime
        }
        if ($Value -is [datetime]) {
            return ([datetime]$Value).ToUniversalTime()
        }
        return [datetimeoffset]::Parse(
            [string]$Value,
            [Globalization.CultureInfo]::InvariantCulture,
            [Globalization.DateTimeStyles]::AllowWhiteSpaces
        ).UtcDateTime
    }
    catch {
        throw "Invalid source evidence timestamp: $Value"
    }
}

function ConvertTo-SourceEvidenceUtcTimestamp {
    param([Parameter(Mandatory = $true)][object]$Value)

    return (ConvertTo-SourceEvidenceUtcDateTime -Value $Value).ToString('o', [Globalization.CultureInfo]::InvariantCulture)
}

function Get-SourceEvidenceContentSha256 {
    param([Parameter(Mandatory = $true)][AllowEmptyString()][string]$Content)

    return Get-Sha256 -Content $Content
}

function Get-SourceEvidenceFileSha256 {
    param([Parameter(Mandatory = $true)][string]$Path)

    return Get-Sha256 -Path $Path
}

function Get-SourceEvidenceFileSnapshot {
    param([Parameter(Mandatory = $true)][string]$Path)

    return Get-FileSnapshot -Path $Path
}

function Get-SourceEvidenceRetryDelayMilliseconds {
    param(
        [Parameter(Mandatory = $true)][ValidateRange(1, 20)][int]$Attempt,
        [Parameter(Mandatory = $true)][ValidateRange(0, 60000)][int]$BaseDelayMilliseconds,
        [ValidateRange(0, 300000)][int]$MaximumDelayMilliseconds = 30000,
        [ValidateRange(0, 300000)][int]$RetryAfterMilliseconds = 0
    )

    $exponentialDelay = [int][Math]::Min($MaximumDelayMilliseconds, $BaseDelayMilliseconds * [Math]::Pow(2, $Attempt - 1))
    return [int][Math]::Min($MaximumDelayMilliseconds, [Math]::Max($exponentialDelay, $RetryAfterMilliseconds))
}

function Invoke-SourceEvidenceWithRetry {
    param(
        [Parameter(Mandatory = $true)][scriptblock]$Action,
        [Parameter(Mandatory = $true)][string]$Operation,
        [ValidateRange(1, 20)][int]$MaximumAttempts = 3,
        [ValidateRange(0, 60000)][int]$BaseDelayMilliseconds = 1000,
        [ValidateRange(0, 300000)][int]$MaximumDelayMilliseconds = 30000,
        [scriptblock]$ShouldRetry = { param($Failure) $true },
        [scriptblock]$GetRetryAfterMilliseconds = { param($Failure) 0 }
    )

    for ($attempt = 1; $attempt -le $MaximumAttempts; $attempt++) {
        try {
            return & $Action
        }
        catch {
            $failure = $_
            if ($attempt -eq $MaximumAttempts -or -not (& $ShouldRetry $failure)) {
                throw
            }
            $retryAfterMilliseconds = [int](& $GetRetryAfterMilliseconds $failure)
            $delayMilliseconds = Get-SourceEvidenceRetryDelayMilliseconds -Attempt $attempt -BaseDelayMilliseconds $BaseDelayMilliseconds -MaximumDelayMilliseconds $MaximumDelayMilliseconds -RetryAfterMilliseconds $retryAfterMilliseconds
            if ($delayMilliseconds -gt 0) {
                Start-Sleep -Milliseconds $delayMilliseconds
            }
        }
    }
    throw "$Operation exhausted its retry attempts"
}

function Get-SourceEvidenceRecordsSha256 {
    param([Parameter(Mandatory = $true)][object[]]$Records)

    $sorted = [Collections.Generic.List[object]]::new()
    foreach ($record in $Records) {
        $normalizedRecord = ($record | ConvertTo-Json -Depth 30 -Compress) | ConvertFrom-Json -DateKind String
        $sorted.Add((ConvertTo-SourceEvidenceCanonicalRecord -Record $normalizedRecord))
    }
    $sorted.Sort([Comparison[object]]{
        param($left, $right)
        return [StringComparer]::Ordinal.Compare([string]$left.sourceId, [string]$right.sourceId)
    })
    return Get-SourceEvidenceContentSha256 -Content ($sorted.ToArray() | ConvertTo-Json -Depth 30 -Compress)
}

function ConvertTo-SourceEvidenceCanonicalRecord {
    param([Parameter(Mandatory = $true)][object]$Record)

    $canonical = [ordered]@{}
    foreach ($property in $Record.PSObject.Properties) {
        if ($property.Name -ceq 'removedAt') {
            $canonical[$property.Name] = ConvertTo-SourceEvidenceUtcTimestamp -Value $property.Value
        }
        else {
            $canonical[$property.Name] = $property.Value
        }
    }
    return $canonical
}

function Assert-SourceEvidenceRelativePath {
    param([Parameter(Mandatory = $true)][string]$Value)

    if ([IO.Path]::IsPathRooted($Value) -or $Value.Contains('\') -or @($Value -split '/' | Where-Object { $_ -in @('', '.', '..') }).Count -ne 0) {
        throw "Behavior file is not repository-relative: $Value"
    }
}

function Get-SourceEvidenceParserContractSha256 {
    param(
        [Parameter(Mandatory = $true)][object]$Contract,
        [Parameter(Mandatory = $true)][string]$RepositoryRoot
    )

    return Get-BehaviorManifestSha256 -IdentityValues @([string]$Contract.parserId, [string]$Contract.assessmentCardinality) -BehaviorFiles @($Contract.behaviorFiles) -RepositoryRoot $RepositoryRoot -ManifestName "Parser contract $($Contract.parserId)"
}

function Get-SourceAssessmentContractSha256 {
    param(
        [Parameter(Mandatory = $true)][object]$Contract,
        [Parameter(Mandatory = $true)][string]$RepositoryRoot
    )

    return Get-BehaviorManifestSha256 -IdentityValues @([string]$Contract.contractId) -BehaviorFiles @($Contract.behaviorFiles) -RepositoryRoot $RepositoryRoot -ManifestName "Assessment contract $($Contract.contractId)"
}

function Get-CurrentSourceDefinitionEvidence {
    param(
        [Parameter(Mandatory = $true)][string]$RepositoryRoot,
        [Parameter(Mandatory = $true)][string]$SourceDefinitionId
    )

    $catalogRoot = Join-Path $RepositoryRoot 'hosted_copilot/copilot-rule-catalog'
    $definitionRoot = Join-Path $catalogRoot 'source-definitions'
    $definitionPath = Join-Path $definitionRoot "$SourceDefinitionId.json"
    $definitionSchemaPath = Join-Path $definitionRoot 'source-definition.schema.json'
    $contractRoot = Join-Path $catalogRoot 'parser-contracts'
    $contractSchemaPath = Join-Path $contractRoot 'parser-contract.schema.json'
    foreach ($requiredPath in @($definitionPath, $definitionSchemaPath, $contractSchemaPath)) {
        if (-not (Test-Path -LiteralPath $requiredPath -PathType Leaf)) {
            throw "Required source evidence input was not found: $requiredPath"
        }
    }

    $definitionJson = Get-Content -LiteralPath $definitionPath -Raw
    if (-not (Test-Json -Json $definitionJson -SchemaFile $definitionSchemaPath -ErrorAction Stop)) {
        throw "Source definition does not satisfy its schema: $definitionPath"
    }
    $definition = $definitionJson | ConvertFrom-Json
    if ([string]$definition.id -cne $SourceDefinitionId) {
        throw "Source definition ID does not match its file name: $SourceDefinitionId"
    }

    $contractPath = Join-Path $contractRoot "$($definition.parser).json"
    if (-not (Test-Path -LiteralPath $contractPath -PathType Leaf)) {
        throw "Parser contract was not found: $contractPath"
    }
    $contractJson = Get-Content -LiteralPath $contractPath -Raw
    if (-not (Test-Json -Json $contractJson -SchemaFile $contractSchemaPath -ErrorAction Stop)) {
        throw "Parser contract does not satisfy its schema: $contractPath"
    }
    $contract = $contractJson | ConvertFrom-Json
    if ([string]$contract.parserId -cne [string]$definition.parser) {
        throw "Parser contract ID does not match the source definition: $SourceDefinitionId"
    }
    $parserContractSha256 = Get-SourceEvidenceParserContractSha256 -Contract $contract -RepositoryRoot $RepositoryRoot

    $configuration = [ordered]@{
        sourceDefinitionId = [string]$definition.id
        root = $definition.root
        files = @($definition.files)
        exclude = @($definition.exclude)
        parserId = [string]$definition.parser
        parserContractSha256 = $parserContractSha256
    }

    return [pscustomobject]@{
        SourceDefinitionId = $SourceDefinitionId
        SourceDefinitionSha256 = Get-SourceEvidenceFileSha256 -Path $definitionPath
        ParserId = [string]$definition.parser
        ParserContractSha256 = $parserContractSha256
        InventoryConfigurationSha256 = Get-SourceEvidenceContentSha256 -Content ($configuration | ConvertTo-Json -Depth 10 -Compress)
        AssessmentBatchSize = [int]$definition.assessmentBatchSize
        AssessmentCardinality = [string]$contract.assessmentCardinality
    }
}

function Get-ExpectedSourceDefinitionIds {
    param([Parameter(Mandatory = $true)][string]$RepositoryRoot)

    $definitionRoot = Join-Path $RepositoryRoot 'hosted_copilot/copilot-rule-catalog/source-definitions'
    $setPath = Join-Path $definitionRoot 'source-definition-set.json'
    $setSchemaPath = Join-Path $definitionRoot 'source-definition-set.schema.json'
    foreach ($requiredPath in @($setPath, $setSchemaPath)) {
        if (-not (Test-Path -LiteralPath $requiredPath -PathType Leaf)) {
            throw "Required source definition set input was not found: $requiredPath"
        }
    }
    $setJson = Get-Content -LiteralPath $setPath -Raw
    if (-not (Test-Json -Json $setJson -SchemaFile $setSchemaPath -ErrorAction Stop)) {
        throw "Source definition set does not satisfy its schema: $setPath"
    }
    $set = $setJson | ConvertFrom-Json
    [string[]]$ids = @($set.sourceDefinitionIds)
    [string[]]$sortedIds = @($ids)
    [Array]::Sort($sortedIds, [StringComparer]::Ordinal)
    if (@(Compare-Object $ids $sortedIds -SyncWindow 0).Count -ne 0) {
        throw 'Source definition set IDs must use ordinal sort order'
    }
    foreach ($id in $ids) {
        $definitionPath = Join-Path $definitionRoot "$id.json"
        if (-not (Test-Path -LiteralPath $definitionPath -PathType Leaf)) {
            throw "Approved source definition was not found: $id"
        }
    }
    return $ids
}

function Get-SourceAssessmentRunConfigurationSha256 {
    param([Parameter(Mandatory = $true)][object]$RunConfiguration)

    $sourceDefinitions = [Collections.Generic.List[object]]::new()
    foreach ($definition in @($RunConfiguration.sourceDefinitions)) {
        $sourceDefinitions.Add([ordered]@{
            sourceDefinitionId = [string]$definition.sourceDefinitionId
            parserContractSha256 = [string]$definition.parserContractSha256
            inventoryConfigurationSha256 = [string]$definition.inventoryConfigurationSha256
            assessmentBatchSize = [int]$definition.assessmentBatchSize
            assessmentCardinality = [string]$definition.assessmentCardinality
        })
    }
    $sourceDefinitions.Sort([Comparison[object]]{
        param($left, $right)
        return [StringComparer]::Ordinal.Compare([string]$left.sourceDefinitionId, [string]$right.sourceDefinitionId)
    })
    $identity = [ordered]@{
        mode = [string]$RunConfiguration.mode
        model = [string]$RunConfiguration.model
        reasoningEffort = [string]$RunConfiguration.reasoningEffort
        evaluator = [string]$RunConfiguration.evaluator
        evaluatorPayloadBudgetBytes = [int]$RunConfiguration.evaluatorPayloadBudgetBytes
        sourceDefinitions = $sourceDefinitions.ToArray()
    }
    return Get-SourceEvidenceContentSha256 -Content ($identity | ConvertTo-Json -Depth 10 -Compress)
}

function Get-PriorSourceGenerationEvidence {
    param(
        [Parameter(Mandatory = $true)][object]$SourceGeneration,
        [Parameter(Mandatory = $true)][string]$SourceDefinitionId,
        [Parameter(Mandatory = $true)][string]$SourceId,
        [Parameter(Mandatory = $true)][string]$CurrentContentSha256
    )

    $inventoryProperty = $SourceGeneration.inventories.PSObject.Properties[$SourceDefinitionId]
    if ($null -eq $inventoryProperty) {
        return $null
    }
    $priorRecords = @($inventoryProperty.Value.records | Where-Object { [string]$_.sourceId -ceq $SourceId })
    if ($priorRecords.Count -eq 0 -or [string]$priorRecords[0].contentSha256 -ceq $CurrentContentSha256) {
        return $null
    }
    if ($priorRecords.Count -ne 1) {
        throw "Prior source generation contains duplicate source IDs: $SourceDefinitionId`:$SourceId"
    }
    $priorRecord = $priorRecords[0]
    return [ordered]@{
        sourceRef = [ordered]@{
            sourceDefinitionId = $SourceDefinitionId
            sourceId = $SourceId
            contentSha256 = [string]$priorRecord.contentSha256
        }
        sourceRecord = $priorRecord
        acceptedAt = ConvertTo-SourceEvidenceUtcTimestamp -Value $SourceGeneration.acceptance.acceptedAt
        inventorySha256 = [string]$inventoryProperty.Value.collection.inventorySha256
    }
}

function Assert-SourceInventoryIntegrity {
    param([Parameter(Mandatory = $true)][object]$Inventory)

    $sourceDefinitionId = [string]$Inventory.sourceDefinitionId
    $currentSourceIds = @{}
    foreach ($record in @($Inventory.records)) {
        $currentSourceId = [string]$record.sourceId
        if ($currentSourceIds.ContainsKey($currentSourceId)) {
            throw "Source inventory contains duplicate source IDs: $currentSourceId"
        }
        $currentSourceIds[$currentSourceId] = $true
    }
    $recordsSha256 = Get-SourceEvidenceRecordsSha256 -Records @($Inventory.records)
    if ($recordsSha256 -cne [string]$Inventory.collection.inventorySha256) {
        throw "Source inventory record hash does not match collection.inventorySha256: $sourceDefinitionId"
    }
}

function Assert-CurrentSourceInventory {
    param(
        [Parameter(Mandatory = $true)][object]$Inventory,
        [Parameter(Mandatory = $true)][object]$Evidence
    )

    $sourceDefinitionId = [string]$Inventory.sourceDefinitionId
    if ($sourceDefinitionId -cne [string]$Evidence.SourceDefinitionId) {
        throw "Source inventory definition ID mismatch: $sourceDefinitionId"
    }
    if ([string]$Inventory.parserId -cne [string]$Evidence.ParserId) {
        throw "Source inventory parser does not match its source definition: $sourceDefinitionId"
    }
    if ([string]$Inventory.parserContractSha256 -cne [string]$Evidence.ParserContractSha256) {
        throw "Source inventory parser contract hash is stale: $sourceDefinitionId"
    }
    if ([string]$Inventory.inventoryConfigurationSha256 -cne [string]$Evidence.InventoryConfigurationSha256) {
        throw "Source inventory configuration hash is stale: $sourceDefinitionId"
    }
    Assert-SourceInventoryIntegrity -Inventory $Inventory
}

Export-ModuleMember -Function ConvertTo-SourceEvidenceUtcDateTime, ConvertTo-SourceEvidenceUtcTimestamp, Get-SourceEvidenceContentSha256, Get-SourceEvidenceFileSha256, Get-SourceEvidenceFileSnapshot, Get-SourceEvidenceRetryDelayMilliseconds, Invoke-SourceEvidenceWithRetry, Get-SourceEvidenceRecordsSha256, Get-SourceEvidenceParserContractSha256, Get-SourceAssessmentContractSha256, Get-CurrentSourceDefinitionEvidence, Get-ExpectedSourceDefinitionIds, Get-SourceAssessmentRunConfigurationSha256, Get-PriorSourceGenerationEvidence, Assert-SourceInventoryIntegrity, Assert-CurrentSourceInventory
