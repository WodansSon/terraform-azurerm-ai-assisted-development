Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

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

    return [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData([Text.Encoding]::UTF8.GetBytes($Content))).ToLowerInvariant()
}

function Get-SourceEvidenceFileSha256 {
    param([Parameter(Mandatory = $true)][string]$Path)

    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function Get-SourceEvidenceFileSnapshot {
    param([Parameter(Mandatory = $true)][string]$Path)

    $stream = [IO.File]::Open($Path, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::None)
    try {
        $buffer = [IO.MemoryStream]::new()
        try {
            $stream.CopyTo($buffer)
            [byte[]]$bytes = $buffer.ToArray()
        }
        finally {
            $buffer.Dispose()
        }
    }
    finally {
        $stream.Dispose()
    }

    $offset = if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) { 3 } else { 0 }
    return [pscustomobject]@{
        Bytes = $bytes
        Content = [Text.UTF8Encoding]::new($false, $true).GetString($bytes, $offset, $bytes.Length - $offset)
        Sha256 = [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($bytes)).ToLowerInvariant()
    }
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

function ConvertTo-SourceEvidenceCanonicalAcceptance {
    param([Parameter(Mandatory = $true)][object]$Acceptance)

    $canonical = [ordered]@{
        acceptedAt = ConvertTo-SourceEvidenceUtcTimestamp -Value $Acceptance.acceptedAt
        acceptedBy = [string]$Acceptance.acceptedBy
        stagedInventorySha256 = [string]$Acceptance.stagedInventorySha256
        previousAcceptedInventorySha256 = $Acceptance.previousAcceptedInventorySha256
    }
    if ($Acceptance.PSObject.Properties['rationale']) {
        $canonical.rationale = [string]$Acceptance.rationale
    }
    return $canonical
}

function ConvertTo-SourceEvidenceCanonicalRevision {
    param([Parameter(Mandatory = $true)][object]$Revision)

    return [ordered]@{
        '$schema' = [string]$Revision.'$schema'
        schemaVersion = [int]$Revision.schemaVersion
        sourceDefinitionId = [string]$Revision.sourceDefinitionId
        sourceDefinitionSha256 = [string]$Revision.sourceDefinitionSha256
        inventoryConfigurationSha256 = [string]$Revision.inventoryConfigurationSha256
        collectorVersion = [int]$Revision.collectorVersion
        parserId = [string]$Revision.parserId
        parserContractSha256 = [string]$Revision.parserContractSha256
        collectedAt = ConvertTo-SourceEvidenceUtcTimestamp -Value $Revision.collectedAt
        collection = $Revision.collection
        acceptance = ConvertTo-SourceEvidenceCanonicalAcceptance -Acceptance $Revision.acceptance
        records = @($Revision.records | ForEach-Object { ConvertTo-SourceEvidenceCanonicalRecord -Record $_ })
    }
}

function Get-SourceEvidenceAcceptedInventorySha256 {
    param(
        [Parameter(Mandatory = $true)][object]$Revision,
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][object[]]$PriorRevisions
    )

    $canonicalRevision = ConvertTo-SourceEvidenceCanonicalRevision -Revision $Revision
    $canonicalPriorRevisions = @($PriorRevisions | ForEach-Object { ConvertTo-SourceEvidenceCanonicalRevision -Revision $_ })

    $inventory = [ordered]@{
        '$schema' = $canonicalRevision.'$schema'
        schemaVersion = $canonicalRevision.schemaVersion
        sourceDefinitionId = $canonicalRevision.sourceDefinitionId
        sourceDefinitionSha256 = $canonicalRevision.sourceDefinitionSha256
        inventoryConfigurationSha256 = $canonicalRevision.inventoryConfigurationSha256
        collectorVersion = $canonicalRevision.collectorVersion
        parserId = $canonicalRevision.parserId
        parserContractSha256 = $canonicalRevision.parserContractSha256
        collectedAt = $canonicalRevision.collectedAt
        collection = $canonicalRevision.collection
        acceptance = $canonicalRevision.acceptance
        acceptedRevisions = $canonicalPriorRevisions
        records = $canonicalRevision.records
    }
    return Get-SourceEvidenceContentSha256 -Content (($inventory | ConvertTo-Json -Depth 40) + "`n")
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

    [string[]]$behaviorFiles = @($Contract.behaviorFiles)
    [string[]]$sortedFiles = @($behaviorFiles)
    [Array]::Sort($sortedFiles, [StringComparer]::Ordinal)
    if (@(Compare-Object $behaviorFiles $sortedFiles -SyncWindow 0).Count -ne 0) {
        throw "Parser contract behaviorFiles must use ordinal sort order: $($Contract.parserId)"
    }

    $builder = [Text.StringBuilder]::new()
    $null = $builder.Append([string]$Contract.parserId).Append([char]0).Append([string]$Contract.assessmentCardinality).Append([char]0)
    foreach ($relativePath in $sortedFiles) {
        Assert-SourceEvidenceRelativePath -Value $relativePath
        $fullPath = [IO.Path]::GetFullPath((Join-Path $RepositoryRoot $relativePath))
        if (-not (Test-Path -LiteralPath $fullPath -PathType Leaf)) {
            throw "Parser contract behavior file was not found: $relativePath"
        }
        $null = $builder.Append($relativePath).Append([char]0).Append((Get-SourceEvidenceFileSha256 -Path $fullPath)).Append([char]0)
    }
    return Get-SourceEvidenceContentSha256 -Content $builder.ToString()
}

function Get-SourceAssessmentContractSha256 {
    param(
        [Parameter(Mandatory = $true)][object]$Contract,
        [Parameter(Mandatory = $true)][string]$RepositoryRoot
    )

    [string[]]$behaviorFiles = @($Contract.behaviorFiles)
    [string[]]$sortedFiles = @($behaviorFiles)
    [Array]::Sort($sortedFiles, [StringComparer]::Ordinal)
    if (@(Compare-Object $behaviorFiles $sortedFiles -SyncWindow 0).Count -ne 0) {
        throw "Assessment contract behaviorFiles must use ordinal sort order: $($Contract.contractId)"
    }

    $builder = [Text.StringBuilder]::new()
    $null = $builder.Append([string]$Contract.contractId).Append([char]0)
    foreach ($relativePath in $sortedFiles) {
        Assert-SourceEvidenceRelativePath -Value $relativePath
        $fullPath = [IO.Path]::GetFullPath((Join-Path $RepositoryRoot $relativePath))
        if (-not (Test-Path -LiteralPath $fullPath -PathType Leaf)) {
            throw "Assessment contract behavior file was not found: $relativePath"
        }
        $null = $builder.Append($relativePath).Append([char]0).Append((Get-SourceEvidenceFileSha256 -Path $fullPath)).Append([char]0)
    }
    return Get-SourceEvidenceContentSha256 -Content $builder.ToString()
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

function Get-PriorAcceptedSourceEvidence {
    param(
        [Parameter(Mandatory = $true)][object]$Inventory,
        [Parameter(Mandatory = $true)][string]$SourceId,
        [Parameter(Mandatory = $true)][string]$CurrentContentSha256
    )

    $revisions = @($Inventory.acceptedRevisions)
    for ($index = $revisions.Count - 1; $index -ge 0; $index--) {
        $revision = $revisions[$index]
        $priorRecords = @($revision.records | Where-Object { [string]$_.sourceId -ceq $SourceId })
        if ($priorRecords.Count -eq 0) {
            continue
        }
        if ($priorRecords.Count -ne 1) {
            throw "Accepted inventory revision contains duplicate source IDs: $SourceId"
        }
        $priorRecord = $priorRecords[0]
        if ([string]$priorRecord.contentSha256 -ceq $CurrentContentSha256) {
            return $null
        }
        return [ordered]@{
            sourceRef = [ordered]@{
                sourceDefinitionId = [string]$Inventory.sourceDefinitionId
                sourceId = $SourceId
                contentSha256 = [string]$priorRecord.contentSha256
            }
            sourceRecord = $priorRecord
            acceptedAt = ConvertTo-SourceEvidenceUtcTimestamp -Value $revision.acceptance.acceptedAt
            inventorySha256 = [string]$revision.collection.inventorySha256
        }
    }
    return $null
}

function Assert-SourceEvidenceAcceptedInventoryHistory {
    param([Parameter(Mandatory = $true)][object]$Inventory)

    $sourceDefinitionId = [string]$Inventory.sourceDefinitionId
    $priorRevisions = [Collections.Generic.List[object]]::new()
    $previousAcceptedAt = $null
    $previousRevisionSha256 = $null
    foreach ($revision in @($Inventory.acceptedRevisions)) {
        if ([string]$revision.sourceDefinitionId -cne $sourceDefinitionId) {
            throw "Accepted inventory revision contains a different source definition: $sourceDefinitionId"
        }
        $revisionSourceIds = @{}
        foreach ($record in @($revision.records)) {
            $revisionSourceId = [string]$record.sourceId
            if ($revisionSourceIds.ContainsKey($revisionSourceId)) {
                throw "Accepted inventory revision contains duplicate source IDs: $revisionSourceId"
            }
            $revisionSourceIds[$revisionSourceId] = $true
        }
        $revisionRecordsSha256 = Get-SourceEvidenceRecordsSha256 -Records @($revision.records)
        if ($revisionRecordsSha256 -cne [string]$revision.collection.inventorySha256) {
            throw "Accepted inventory revision record hash mismatch: $($revision.acceptance.acceptedAt)"
        }
        $acceptedAt = ConvertTo-SourceEvidenceUtcDateTime -Value $revision.acceptance.acceptedAt
        if ($null -ne $previousAcceptedAt -and $acceptedAt -le $previousAcceptedAt) {
            throw "Accepted inventory revision times are not strictly increasing: $sourceDefinitionId"
        }
        $expectedPreviousSha256 = $revision.acceptance.previousAcceptedInventorySha256
        if (($null -eq $previousRevisionSha256 -and $null -ne $expectedPreviousSha256) -or ($null -ne $previousRevisionSha256 -and [string]$expectedPreviousSha256 -cne $previousRevisionSha256)) {
            throw "Accepted inventory revision chain hash mismatch: $($revision.acceptance.acceptedAt)"
        }
        $previousRevisionSha256 = Get-SourceEvidenceAcceptedInventorySha256 -Revision $revision -PriorRevisions $priorRevisions.ToArray()
        $priorRevisions.Add($revision)
        $previousAcceptedAt = $acceptedAt
    }
    $currentAcceptedAt = ConvertTo-SourceEvidenceUtcDateTime -Value $Inventory.acceptance.acceptedAt
    if ($null -ne $previousAcceptedAt -and $currentAcceptedAt -le $previousAcceptedAt) {
        throw "Accepted inventory revision times are not strictly increasing: $sourceDefinitionId"
    }
    $currentExpectedPreviousSha256 = $Inventory.acceptance.previousAcceptedInventorySha256
    if (($null -eq $previousRevisionSha256 -and $null -ne $currentExpectedPreviousSha256) -or ($null -ne $previousRevisionSha256 -and [string]$currentExpectedPreviousSha256 -cne $previousRevisionSha256)) {
        throw "Accepted inventory revision chain hash mismatch: $($Inventory.acceptance.acceptedAt), expected $currentExpectedPreviousSha256, reconstructed $previousRevisionSha256"
    }
}

function Assert-CurrentAcceptedSourceInventory {
    param(
        [Parameter(Mandatory = $true)][object]$Inventory,
        [Parameter(Mandatory = $true)][object]$Evidence
    )

    $sourceDefinitionId = [string]$Inventory.sourceDefinitionId
    if ($null -eq $Inventory.acceptance) {
        throw "Source inventory is not accepted: $sourceDefinitionId"
    }
    if ($sourceDefinitionId -cne [string]$Evidence.SourceDefinitionId) {
        throw "Source inventory definition ID mismatch: $sourceDefinitionId"
    }
    if ([string]$Inventory.parserId -cne [string]$Evidence.ParserId) {
        throw "Accepted inventory parser does not match its source definition: $sourceDefinitionId"
    }
    if ([string]$Inventory.parserContractSha256 -cne [string]$Evidence.ParserContractSha256) {
        throw "Accepted inventory parser contract hash is stale: $sourceDefinitionId"
    }
    if ([string]$Inventory.inventoryConfigurationSha256 -cne [string]$Evidence.InventoryConfigurationSha256) {
        throw "Accepted inventory configuration hash is stale: $sourceDefinitionId"
    }
    $currentSourceIds = @{}
    foreach ($record in @($Inventory.records)) {
        $currentSourceId = [string]$record.sourceId
        if ($currentSourceIds.ContainsKey($currentSourceId)) {
            throw "Accepted inventory contains duplicate source IDs: $currentSourceId"
        }
        $currentSourceIds[$currentSourceId] = $true
    }
    $recordsSha256 = Get-SourceEvidenceRecordsSha256 -Records @($Inventory.records)
    if ($recordsSha256 -cne [string]$Inventory.collection.inventorySha256) {
        throw "Accepted inventory record hash does not match collection.inventorySha256: $sourceDefinitionId"
    }
    Assert-SourceEvidenceAcceptedInventoryHistory -Inventory $Inventory
}

Export-ModuleMember -Function ConvertTo-SourceEvidenceUtcDateTime, ConvertTo-SourceEvidenceUtcTimestamp, Get-SourceEvidenceContentSha256, Get-SourceEvidenceFileSha256, Get-SourceEvidenceFileSnapshot, Get-SourceEvidenceRetryDelayMilliseconds, Invoke-SourceEvidenceWithRetry, Get-SourceEvidenceRecordsSha256, Get-SourceEvidenceAcceptedInventorySha256, Get-SourceEvidenceParserContractSha256, Get-SourceAssessmentContractSha256, Get-CurrentSourceDefinitionEvidence, Get-ExpectedSourceDefinitionIds, Get-SourceAssessmentRunConfigurationSha256, Get-PriorAcceptedSourceEvidence, Assert-SourceEvidenceAcceptedInventoryHistory, Assert-CurrentAcceptedSourceInventory
