Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-SourceEvidenceContentSha256 {
    param([Parameter(Mandatory = $true)][AllowEmptyString()][string]$Content)

    return [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData([Text.Encoding]::UTF8.GetBytes($Content))).ToLowerInvariant()
}

function Get-SourceEvidenceFileSha256 {
    param([Parameter(Mandatory = $true)][string]$Path)

    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function Get-SourceEvidenceRecordsSha256 {
    param([Parameter(Mandatory = $true)][object[]]$Records)

    $sorted = [Collections.Generic.List[object]]::new()
    foreach ($record in $Records) {
        $sorted.Add($record)
    }
    $sorted.Sort([Comparison[object]]{
        param($left, $right)
        return [StringComparer]::Ordinal.Compare([string]$left.sourceId, [string]$right.sourceId)
    })
    return Get-SourceEvidenceContentSha256 -Content ($sorted.ToArray() | ConvertTo-Json -Depth 30 -Compress)
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
    [string[]]$ids = @(Get-ChildItem -LiteralPath $definitionRoot -Filter '*.json' -File | Where-Object Name -ne 'source-definition.schema.json' | ForEach-Object { $_.BaseName })
    [Array]::Sort($ids, [StringComparer]::Ordinal)
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
        sourceDefinitions = $sourceDefinitions.ToArray()
    }
    return Get-SourceEvidenceContentSha256 -Content ($identity | ConvertTo-Json -Depth 10 -Compress)
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
    $recordsSha256 = Get-SourceEvidenceRecordsSha256 -Records @($Inventory.records)
    if ($recordsSha256 -cne [string]$Inventory.collection.inventorySha256) {
        throw "Accepted inventory record hash does not match collection.inventorySha256: $sourceDefinitionId"
    }
}

Export-ModuleMember -Function Get-SourceEvidenceContentSha256, Get-SourceEvidenceFileSha256, Get-SourceEvidenceRecordsSha256, Get-SourceEvidenceParserContractSha256, Get-SourceAssessmentContractSha256, Get-CurrentSourceDefinitionEvidence, Get-ExpectedSourceDefinitionIds, Get-SourceAssessmentRunConfigurationSha256, Assert-CurrentAcceptedSourceInventory
