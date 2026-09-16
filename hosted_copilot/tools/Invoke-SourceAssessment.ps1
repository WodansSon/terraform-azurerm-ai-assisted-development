[CmdletBinding()]
param(
    [string]$RepositoryRoot = (Join-Path $PSScriptRoot '../..'),

    [Parameter(Mandatory = $true)]
    [string[]]$InventoryPaths,

    [Parameter(Mandatory = $true)]
    [string]$OutputPath,

    [string]$HostedCatalogPath = (Join-Path $PSScriptRoot '../copilot-rule-catalog/instruction-catalog.json'),

    [string]$AssessmentContractPath = (Join-Path $PSScriptRoot '../copilot-rule-catalog/rule-assessments/source-assessment-v2.json'),

    [string]$BaselineBuilderPath = (Join-Path $PSScriptRoot 'New-SourceAssessmentBaseline.ps1'),

    [string]$EvaluatorCommand = 'copilot',

    [string]$EvaluatorScriptPath,

    [string]$Model = 'gpt-5.4',

    [ValidateSet('low', 'medium', 'high', 'xhigh')]
    [string]$ReasoningEffort = 'high',

    [ValidateRange(0, 3)]
    [int]$MaxRetries = 1,

    [datetime]$GeneratedAt = [DateTime]::UtcNow,

    [ValidateSet('Text', 'Json')]
    [string]$OutputFormat = 'Text'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$sourceEvidenceModulePath = Join-Path $PSScriptRoot 'SourceEvidenceValidation.psm1'
Import-Module -Name $sourceEvidenceModulePath -Force

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

function Get-EvaluatorJson {
    param([Parameter(Mandatory = $true)][AllowEmptyString()][string]$Content)

    $trimmed = $Content.Trim()
    if ($trimmed.StartsWith('```json', [StringComparison]::OrdinalIgnoreCase) -and $trimmed.EndsWith('```', [StringComparison]::Ordinal)) {
        $trimmed = $trimmed.Substring(7, $trimmed.Length - 10).Trim()
    }
    elseif ($trimmed.StartsWith('```', [StringComparison]::Ordinal) -and $trimmed.EndsWith('```', [StringComparison]::Ordinal)) {
        $trimmed = $trimmed.Substring(3, $trimmed.Length - 6).Trim()
    }
    $objectStart = $trimmed.IndexOf('{')
    $objectEnd = $trimmed.LastIndexOf('}')
    if ($objectStart -lt 0 -or $objectEnd -lt $objectStart) {
        throw 'Evaluator response does not contain a JSON object'
    }
    return $trimmed.Substring($objectStart, $objectEnd - $objectStart + 1)
}

function Get-SortedObjects {
    param(
        [Parameter(Mandatory = $true)][object[]]$Values,
        [Parameter(Mandatory = $true)][scriptblock]$Key
    )

    $sorted = [Collections.Generic.List[object]]::new()
    foreach ($value in $Values) {
        $sorted.Add($value)
    }
    $sorted.Sort([Comparison[object]]{
        param($left, $right)
        return [StringComparer]::Ordinal.Compare([string](& $Key $left), [string](& $Key $right))
    })
    return $sorted.ToArray()
}

function Assert-BatchResponse {
    param(
        [Parameter(Mandatory = $true)][object]$Response,
        [Parameter(Mandatory = $true)][object[]]$ExpectedRecords,
        [Parameter(Mandatory = $true)][string]$BatchId,
        [Parameter(Mandatory = $true)][string]$AssessmentCardinality
    )

    $actualProperties = @($Response.PSObject.Properties.Name | Sort-Object)
    if (Compare-Object -ReferenceObject @('$schema', 'entries', 'schemaVersion') -DifferenceObject $actualProperties) {
        throw "Evaluator response for $BatchId has an unexpected property set"
    }
    $entries = @($Response.entries)
    if ($entries.Count -ne $ExpectedRecords.Count) {
        throw "Evaluator returned $($entries.Count) entries for $($ExpectedRecords.Count) source records in $BatchId"
    }

    $expectedByKey = @{}
    foreach ($record in $ExpectedRecords) {
        $key = "$($record.sourceRef.sourceDefinitionId):$($record.sourceRef.sourceId)"
        $expectedByKey[$key] = $record
    }
    $seen = @{}
    foreach ($entry in $entries) {
        $entryProperties = @($entry.PSObject.Properties.Name | Sort-Object)
        if (Compare-Object -ReferenceObject @('assessments', 'sourceRef') -DifferenceObject $entryProperties) {
            throw "Evaluator entry in $BatchId has an unexpected property set"
        }
        $sourceRefProperties = @($entry.sourceRef.PSObject.Properties.Name | Sort-Object)
        if (Compare-Object -ReferenceObject @('contentSha256', 'sourceDefinitionId', 'sourceId') -DifferenceObject $sourceRefProperties) {
            throw "Evaluator sourceRef in $BatchId has an unexpected property set"
        }
        $key = "$($entry.sourceRef.sourceDefinitionId):$($entry.sourceRef.sourceId)"
        if ($seen.ContainsKey($key)) {
            throw "Evaluator returned duplicate source reference in $BatchId`: $key"
        }
        if (-not $expectedByKey.ContainsKey($key)) {
            throw "Evaluator returned unknown source reference in $BatchId`: $key"
        }
        if ([string]$entry.sourceRef.contentSha256 -cne [string]$expectedByKey[$key].sourceRef.contentSha256) {
            throw "Evaluator changed the source hash in $BatchId`: $key"
        }
        if ($AssessmentCardinality -ceq 'exactly-one' -and @($entry.assessments).Count -ne 1) {
            throw "Evaluator must return exactly one assessment for $key in $BatchId"
        }
        foreach ($assessment in @($entry.assessments)) {
            [string[]]$expectedMappedHostedRuleIds = @($expectedByKey[$key].mappedHostedRuleIds | Sort-Object -Unique)
            [string[]]$actualMappedHostedRuleIds = @($assessment.mappedHostedRuleIds | Sort-Object -Unique)
            if (@(Compare-Object $expectedMappedHostedRuleIds $actualMappedHostedRuleIds -SyncWindow 0).Count -ne 0) {
                throw "Evaluator changed the accepted Hosted mapping set in $BatchId`: $key"
            }
            $assessment.mappedHostedRuleIds = $expectedMappedHostedRuleIds
        }
        $seen[$key] = $true
    }
}

$resolvedRepositoryRoot = [IO.Path]::GetFullPath($RepositoryRoot).TrimEnd([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar)
$repositoryPrefix = $resolvedRepositoryRoot + [IO.Path]::DirectorySeparatorChar
$resolvedOutputPath = [IO.Path]::GetFullPath($OutputPath)
if ($resolvedOutputPath.StartsWith($repositoryPrefix, [StringComparison]::OrdinalIgnoreCase)) {
    throw 'Source assessment output must be outside the repository root'
}

$resolvedBuilderPath = [IO.Path]::GetFullPath($BaselineBuilderPath)
$resolvedCatalogPath = [IO.Path]::GetFullPath($HostedCatalogPath)
$resolvedContractPath = [IO.Path]::GetFullPath($AssessmentContractPath)
$inventorySchemaPath = Join-Path $resolvedRepositoryRoot 'hosted_copilot/copilot-rule-catalog/source-inventories/source-inventory.schema.json'
$definitionSchemaPath = Join-Path $resolvedRepositoryRoot 'hosted_copilot/copilot-rule-catalog/source-definitions/source-definition.schema.json'
$draftSchemaPath = Join-Path $resolvedRepositoryRoot 'hosted_copilot/copilot-rule-catalog/rule-assessments/source-assessment-draft.schema.json'
$catalogSchemaPath = Join-Path (Split-Path -Parent $resolvedCatalogPath) 'instruction-catalog.schema.json'
$promptPath = Join-Path $resolvedRepositoryRoot 'hosted_copilot/tools/assessment-prompts/SourceAssessmentV2.md'
$ledgerPath = Join-Path $resolvedRepositoryRoot 'hosted_copilot/copilot-rule-catalog/interactive-intake-ledger.json'
$runDirectory = Join-Path ([IO.Path]::GetTempPath()) ('hosted-source-assessment/' + [guid]::NewGuid().ToString('N'))
foreach ($requiredPath in @($resolvedBuilderPath, $resolvedCatalogPath, $resolvedContractPath, $inventorySchemaPath, $definitionSchemaPath, $draftSchemaPath, $promptPath)) {
    if (-not (Test-Path -LiteralPath $requiredPath -PathType Leaf)) {
        throw "Required source assessment input was not found: $requiredPath"
    }
}
$resolvedEvaluatorScriptPath = $null
$evaluatorIdentity = $EvaluatorCommand
if (-not [string]::IsNullOrWhiteSpace($EvaluatorScriptPath)) {
    $resolvedEvaluatorScriptPath = [IO.Path]::GetFullPath($EvaluatorScriptPath)
    if (-not (Test-Path -LiteralPath $resolvedEvaluatorScriptPath -PathType Leaf)) {
        throw "Evaluator script was not found: $resolvedEvaluatorScriptPath"
    }
    $evaluatorIdentity = 'script:' + (Get-FileHash -LiteralPath $resolvedEvaluatorScriptPath -Algorithm SHA256).Hash.ToLowerInvariant()
}

$catalogJson = Get-Content -LiteralPath $resolvedCatalogPath -Raw
if (-not (Test-Json -Json $catalogJson -SchemaFile $catalogSchemaPath -ErrorAction Stop)) {
    throw "Hosted catalog does not satisfy its schema: $resolvedCatalogPath"
}
$catalog = $catalogJson | ConvertFrom-Json
$hostedRulesBySourceId = @{}
foreach ($rule in @($catalog.rules)) {
    foreach ($sourceId in @($rule.sourceIds)) {
        if (-not $hostedRulesBySourceId.ContainsKey([string]$sourceId)) {
            $hostedRulesBySourceId[[string]$sourceId] = [Collections.Generic.List[string]]::new()
        }
        $hostedRulesBySourceId[[string]$sourceId].Add([string]$rule.id)
    }
}
$lanes = [Collections.Generic.List[object]]::new()
$expectedSourceDefinitionIds = @(Get-ExpectedSourceDefinitionIds -RepositoryRoot $resolvedRepositoryRoot)
foreach ($inventoryPath in $InventoryPaths) {
    $resolvedInventoryPath = [IO.Path]::GetFullPath($inventoryPath)
    $inventoryJson = Get-Content -LiteralPath $resolvedInventoryPath -Raw
    if (-not (Test-Json -Json $inventoryJson -SchemaFile $inventorySchemaPath -ErrorAction Stop)) {
        throw "Source inventory does not satisfy its schema: $resolvedInventoryPath"
    }
    $inventory = $inventoryJson | ConvertFrom-Json
    if ($null -eq $inventory.acceptance) {
        throw "Source assessment requires an accepted inventory: $resolvedInventoryPath"
    }
    $sourceDefinitionId = [string]$inventory.sourceDefinitionId
    if (@($lanes | Where-Object sourceDefinitionId -eq $sourceDefinitionId).Count -gt 0) {
        throw "Source assessment received duplicate inventory sourceDefinitionId: $sourceDefinitionId"
    }
    $definitionPath = Join-Path $resolvedRepositoryRoot "hosted_copilot/copilot-rule-catalog/source-definitions/$sourceDefinitionId.json"
    $definitionJson = Get-Content -LiteralPath $definitionPath -Raw
    if (-not (Test-Json -Json $definitionJson -SchemaFile $definitionSchemaPath -ErrorAction Stop)) {
        throw "Source definition does not satisfy its schema: $definitionPath"
    }
    $definition = $definitionJson | ConvertFrom-Json
    $sourceEvidence = Get-CurrentSourceDefinitionEvidence -RepositoryRoot $resolvedRepositoryRoot -SourceDefinitionId $sourceDefinitionId
    Assert-CurrentAcceptedSourceInventory -Inventory $inventory -Evidence $sourceEvidence

    $packetRecords = @($inventory.records | ForEach-Object {
        $record = $_
        $mappedHostedRuleIds = [Collections.Generic.List[string]]::new()
        if ($sourceDefinitionId -ceq 'contributor-guidance' -and $hostedRulesBySourceId.ContainsKey([string]$record.sourceId)) {
            foreach ($hostedRuleId in $hostedRulesBySourceId[[string]$record.sourceId]) {
                $mappedHostedRuleIds.Add($hostedRuleId)
            }
        }
        [string[]]$uniqueMappedIds = @($mappedHostedRuleIds | Sort-Object -Unique)
        [ordered]@{
            sourceRef = [ordered]@{
                sourceDefinitionId = $sourceDefinitionId
                sourceId = [string]$record.sourceId
                contentSha256 = [string]$record.contentSha256
            }
            sourceRecord = $record
            mappedHostedRuleIds = $uniqueMappedIds
        }
    })
    $lanes.Add([ordered]@{
        sourceDefinitionId = $sourceDefinitionId
        inventoryPath = $resolvedInventoryPath
        assessmentBatchSize = [int]$definition.assessmentBatchSize
        assessmentCardinality = [string]$sourceEvidence.AssessmentCardinality
        records = @(Get-SortedObjects -Values $packetRecords -Key { param($record) $record.sourceRef.sourceId })
    })
}
$orderedLanes = @(Get-SortedObjects -Values $lanes.ToArray() -Key { param($lane) $lane.sourceDefinitionId })
[string[]]$actualSourceDefinitionIds = @($orderedLanes.sourceDefinitionId)
if (@(Compare-Object $expectedSourceDefinitionIds $actualSourceDefinitionIds -SyncWindow 0).Count -ne 0) {
    throw "Source assessment requires exactly the approved source lanes: $($expectedSourceDefinitionIds -join ', ')"
}

$batches = [Collections.Generic.List[object]]::new()
foreach ($lane in $orderedLanes) {
    $records = @($lane.records)
    for ($offset = 0; $offset -lt $records.Count; $offset += $lane.assessmentBatchSize) {
        $lastIndex = [Math]::Min($offset + $lane.assessmentBatchSize - 1, $records.Count - 1)
        $batches.Add([ordered]@{
            sourceDefinitionId = [string]$lane.sourceDefinitionId
            assessmentCardinality = [string]$lane.assessmentCardinality
            records = @($records[$offset..$lastIndex])
        })
    }
}

$draftEntries = [Collections.Generic.List[object]]::new()
$succeeded = $false
try {
    $null = New-Item -ItemType Directory -Path $runDirectory -Force
    $batchNumber = 0
    foreach ($batch in $batches) {
        $batchNumber++
        $batchId = '{0}-{1:D3}' -f $batch.sourceDefinitionId, $batchNumber
        $batchDirectory = Join-Path $runDirectory $batchId
        $null = New-Item -ItemType Directory -Path $batchDirectory -Force
        $batchPath = Join-Path $batchDirectory 'source-records.json'
        $catalogPath = Join-Path $batchDirectory 'hosted-instruction-catalog.json'
        $schemaPath = Join-Path $batchDirectory 'source-assessment-draft.schema.json'
        $batchPromptPath = Join-Path $batchDirectory 'SourceAssessmentV2.md'
        $responsePath = Join-Path $batchDirectory 'response.json'
        Copy-Item -LiteralPath $resolvedCatalogPath -Destination $catalogPath
        Copy-Item -LiteralPath $draftSchemaPath -Destination $schemaPath
        Copy-Item -LiteralPath $promptPath -Destination $batchPromptPath
        Write-JsonAtomically -Path $batchPath -Value ([ordered]@{
            schemaVersion = 1
            batchId = $batchId
            sourceDefinitionId = [string]$batch.sourceDefinitionId
            assessmentCardinality = [string]$batch.assessmentCardinality
            sourceCount = @($batch.records).Count
            records = @($batch.records)
        })

        if ($OutputFormat -eq 'Text') {
            Write-Host ("[RUNNING]  source-assessment/{0,-24} : {1} sources" -f $batchId, @($batch.records).Count)
        }
        $response = $null
        $lastError = $null
        for ($attempt = 1; $attempt -le ($MaxRetries + 1); $attempt++) {
            try {
                if (-not [string]::IsNullOrWhiteSpace($EvaluatorScriptPath)) {
                    $evaluatorOutput = @(& pwsh -NoProfile -File $resolvedEvaluatorScriptPath -BatchPath $batchPath -CatalogPath $catalogPath -SchemaPath $schemaPath -PromptPath $batchPromptPath -OutputPath $responsePath -Model $Model -ReasoningEffort $ReasoningEffort 2>&1)
                    if ($LASTEXITCODE -ne 0) {
                        throw "Evaluator script failed: $(($evaluatorOutput | Out-String).Trim())"
                    }
                }
                else {
                    $command = Get-Command $EvaluatorCommand -ErrorAction SilentlyContinue
                    if ($null -eq $command) {
                        throw "Evaluator command was not found: $EvaluatorCommand"
                    }
                    $attemptPrompt = @"
Read the source assessment contract, source record batch, Hosted instruction catalog, and output schema at the exact paths below before evaluating the batch.

Source assessment contract: $batchPromptPath
Source record batch: $batchPath
Hosted instruction catalog: $catalogPath
Output schema: $schemaPath

This batch contains exactly $(@($batch.records).Count) source records. This is attempt $attempt of $($MaxRetries + 1). Write only the requested JSON object in your final response.
"@
                    $evaluatorOutput = @(& $command.Source -C $batchDirectory -p $attemptPrompt --no-color --stream off --no-custom-instructions --no-ask-user --disable-builtin-mcps --no-auto-update --disallow-temp-dir --model $Model --effort $ReasoningEffort --available-tools=view --output-format json 2>&1)
                    if ($LASTEXITCODE -ne 0) {
                        throw "Copilot evaluator failed: $(($evaluatorOutput | Out-String).Trim())"
                    }
                    $assistantMessages = [Collections.Generic.List[object]]::new()
                    foreach ($eventLine in $evaluatorOutput) {
                        $eventText = ([string]$eventLine).Trim()
                        if ([string]::IsNullOrWhiteSpace($eventText)) {
                            continue
                        }
                        try {
                            $event = $eventText | ConvertFrom-Json
                        }
                        catch {
                            throw "Copilot evaluator returned a non-JSONL event: $eventText"
                        }
                        if ($event.type -eq 'assistant.message' -and -not [string]::IsNullOrWhiteSpace([string]$event.data.content)) {
                            $assistantMessages.Add($event.data)
                        }
                    }
                    if ($assistantMessages.Count -eq 0) {
                        throw 'Copilot evaluator did not return an assistant message'
                    }
                    $assistantMessage = $assistantMessages[$assistantMessages.Count - 1]
                    if ([string]$assistantMessage.model -cne $Model) {
                        throw "Copilot evaluator used model $($assistantMessage.model) instead of $Model"
                    }
                    $evaluatorJson = Get-EvaluatorJson -Content ([string]$assistantMessage.content)
                    [IO.File]::WriteAllText($responsePath, $evaluatorJson + "`n", [Text.UTF8Encoding]::new($false))
                }

                $responseJson = Get-Content -LiteralPath $responsePath -Raw
                if (-not (Test-Json -Json $responseJson -SchemaFile $draftSchemaPath -ErrorAction Stop)) {
                    throw "Evaluator response does not satisfy the source assessment draft envelope: $batchId"
                }
                $response = $responseJson | ConvertFrom-Json
                Assert-BatchResponse -Response $response -ExpectedRecords @($batch.records) -BatchId $batchId -AssessmentCardinality $batch.assessmentCardinality
                $lastError = $null
                break
            }
            catch {
                $lastError = $_
                Remove-Item -LiteralPath $responsePath -Force -ErrorAction SilentlyContinue
            }
        }
        if ($null -ne $lastError) {
            throw "Source assessment $batchId failed after $($MaxRetries + 1) attempts: $($lastError.Exception.Message)"
        }
        foreach ($entry in @($response.entries)) {
            $draftEntries.Add($entry)
        }
        if ($OutputFormat -eq 'Text') {
            Write-Host ("[PASSED]   source-assessment/{0,-24} : {1} sources" -f $batchId, @($batch.records).Count)
        }
    }

    $draftPath = Join-Path $runDirectory 'source-assessment-draft.json'
    Write-JsonAtomically -Path $draftPath -Value ([ordered]@{
        '$schema' = 'source-assessment-draft.schema.json'
        schemaVersion = 1
        entries = @(Get-SortedObjects -Values $draftEntries.ToArray() -Key { param($entry) "$($entry.sourceRef.sourceDefinitionId):$($entry.sourceRef.sourceId)" })
    })
    $builderParameters = @{
        RepositoryRoot = $resolvedRepositoryRoot
        InventoryPaths = $InventoryPaths
        AssessmentDraftPath = $draftPath
        HostedCatalogPath = $resolvedCatalogPath
        AssessmentContractPath = $resolvedContractPath
        OutputPath = $resolvedOutputPath
        Model = $Model
        ReasoningEffort = $ReasoningEffort
        Evaluator = $evaluatorIdentity
        GeneratedAt = $GeneratedAt
        OutputFormat = 'Json'
    }
    try {
        $builderOutput = @(& $resolvedBuilderPath @builderParameters 2>&1)
    }
    catch {
        throw "Source assessment baseline builder failed: $($_.Exception.Message)"
    }
    $builderResult = ($builderOutput | Out-String) | ConvertFrom-Json
    $succeeded = $true
}
catch {
    throw "$($_.Exception.Message) Source assessment run artifacts were retained at $runDirectory"
}
finally {
    if ($succeeded -and (Test-Path -LiteralPath $runDirectory -PathType Container)) {
        Remove-Item -LiteralPath $runDirectory -Recurse -Force
    }
}

$result = [ordered]@{
    status = 'passed'
    outputPath = $resolvedOutputPath
    sourceCount = [int]$builderResult.sourceCount
    assessmentCount = [int]$builderResult.assessmentCount
    batchCount = $batches.Count
    baselineSha256 = [string]$builderResult.baselineSha256
    assessmentContractSha256 = [string]$builderResult.assessmentContractSha256
    assessmentRunConfigurationSha256 = [string]$builderResult.assessmentRunConfigurationSha256
}
if ($OutputFormat -eq 'Json') {
    $result | ConvertTo-Json -Depth 5
}
else {
    Write-Output "Source assessment completed: $($result.sourceCount) sources, $($result.assessmentCount) assessments, $($result.batchCount) batches"
    Write-Output "Output: $($result.outputPath)"
    Write-Output "Baseline SHA-256: $($result.baselineSha256)"
}
