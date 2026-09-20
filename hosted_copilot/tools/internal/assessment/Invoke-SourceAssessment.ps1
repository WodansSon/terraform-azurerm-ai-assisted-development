[CmdletBinding()]
param(
    [string]$RepositoryRoot = (Join-Path $PSScriptRoot '../../../..'),

    [Parameter(Mandatory = $true)]
    [string[]]$InventoryPaths,

    [string[]]$PriorInventoryPaths = @(),

    [Parameter(Mandatory = $true)]
    [string]$OutputPath,

    [string]$HostedCatalogPath = (Join-Path $PSScriptRoot '../../../copilot-rule-catalog/instruction-catalog.json'),

    [string]$AssessmentContractPath = (Join-Path $PSScriptRoot '../../../copilot-rule-catalog/rule-assessments/source-assessment-v4.json'),

    [string]$BaselineBuilderPath = (Join-Path $PSScriptRoot 'New-SourceAssessmentBaseline.ps1'),

    [string]$EvaluatorCommand = 'copilot',

    [string]$EvaluatorScriptPath,

    [string]$Model = 'gpt-5.4',

    [ValidateSet('low', 'medium', 'high', 'xhigh')]
    [string]$ReasoningEffort = 'high',

    [ValidateRange(0, 3)]
    [int]$MaxRetries = 1,

    [ValidateRange(0, 60000)]
    [int]$RetryDelayMilliseconds = 1000,

    [ValidateRange(1024, 10485760)]
    [int]$EvaluatorPayloadBudgetBytes = 393216,

    [string]$CacheDirectory = (Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'hosted-workbench/assessment-cache'),

    [string]$ResumeRunDirectory,

    [object]$GeneratedAt = [DateTime]::UtcNow,

    [switch]$ShowProgress,

    [ValidateSet('Text', 'Json')]
    [string]$OutputFormat = 'Text'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$sourceEvidenceModulePath = Join-Path $PSScriptRoot '../../modules/shared/SourceEvidenceValidation.psm1'
Import-Module -Name $sourceEvidenceModulePath -Force
$validationOutputModulePath = Join-Path $PSScriptRoot '../../../../tools/ValidationOutput.psm1'
Import-Module -Name $validationOutputModulePath -Force

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

function Get-AssessmentSourceCacheIdentity {
    param(
        [Parameter(Mandatory = $true)][object]$SourceRecord,
        [Parameter(Mandatory = $true)][string]$AssessmentCardinality,
        [Parameter(Mandatory = $true)][string]$CatalogPath,
        [Parameter(Mandatory = $true)][string]$ContractPath,
        [Parameter(Mandatory = $true)][string]$DraftSchemaPath,
        [Parameter(Mandatory = $true)][string]$PromptPath,
        [Parameter(Mandatory = $true)][string]$Evaluator,
        [Parameter(Mandatory = $true)][string]$Model,
        [Parameter(Mandatory = $true)][string]$ReasoningEffort
    )

    return [ordered]@{
        sourceRecordSha256 = Get-SourceEvidenceContentSha256 -Content ($SourceRecord | ConvertTo-Json -Depth 40 -Compress)
        assessmentCardinality = $AssessmentCardinality
        hostedCatalogSha256 = Get-SourceEvidenceFileSha256 -Path $CatalogPath
        assessmentContractSha256 = Get-SourceEvidenceFileSha256 -Path $ContractPath
        draftSchemaSha256 = Get-SourceEvidenceFileSha256 -Path $DraftSchemaPath
        promptSha256 = Get-SourceEvidenceFileSha256 -Path $PromptPath
        evaluator = $Evaluator
        model = $Model
        reasoningEffort = $ReasoningEffort
    }
}

function Get-AssessmentSourceCacheKey {
    param([Parameter(Mandatory = $true)][object]$Identity)

    return Get-SourceEvidenceContentSha256 -Content ($Identity | ConvertTo-Json -Depth 10 -Compress)
}

function Test-AssessmentResponseEntry {
    param(
        [Parameter(Mandatory = $true)][object]$Entry,
        [Parameter(Mandatory = $true)][object]$ExpectedRecord,
        [Parameter(Mandatory = $true)][string]$Context,
        [Parameter(Mandatory = $true)][string]$AssessmentCardinality,
        [Parameter(Mandatory = $true)][Collections.Generic.HashSet[string]]$KnownHostedRuleIds,
        [Parameter(Mandatory = $true)][string]$DraftSchemaPath
    )

    $response = [ordered]@{
        '$schema' = 'source-assessment-draft.schema.json'
        schemaVersion = 1
        entries = @($Entry)
    }
    $responseJson = $response | ConvertTo-Json -Depth 40
    if (-not (Test-Json -Json $responseJson -SchemaFile $DraftSchemaPath -ErrorAction Stop)) {
        throw "Assessment response entry does not satisfy the source assessment draft: $Context"
    }
    $validatedResponse = $responseJson | ConvertFrom-Json
    Assert-BatchResponse -Response $validatedResponse -ExpectedRecords @($ExpectedRecord) -BatchId $Context -AssessmentCardinality $AssessmentCardinality -KnownHostedRuleIds $KnownHostedRuleIds
}

function Read-AssessmentSourceCache {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$ExpectedCacheKey,
        [Parameter(Mandatory = $true)][object]$ExpectedIdentity,
        [Parameter(Mandatory = $true)][object]$ExpectedRecord,
        [Parameter(Mandatory = $true)][string]$Context,
        [Parameter(Mandatory = $true)][string]$AssessmentCardinality,
        [Parameter(Mandatory = $true)][Collections.Generic.HashSet[string]]$KnownHostedRuleIds,
        [Parameter(Mandatory = $true)][string]$DraftSchemaPath,
        [switch]$ShowProgress
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        return $null
    }
    try {
        $entry = Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json
        $actualProperties = @($entry.PSObject.Properties.Name | Sort-Object)
        if (Compare-Object -ReferenceObject @('cacheKey', 'entry', 'identity', 'kind', 'schemaVersion') -DifferenceObject $actualProperties) {
            throw 'Source cache entry has an unexpected property set'
        }
        if ([int]$entry.schemaVersion -ne 1 -or [string]$entry.kind -cne 'hosted-source-assessment-source-cache' -or [string]$entry.cacheKey -cne $ExpectedCacheKey) {
            throw 'Source cache entry identity is invalid'
        }
        if (($entry.identity | ConvertTo-Json -Depth 10 -Compress) -cne ($ExpectedIdentity | ConvertTo-Json -Depth 10 -Compress)) {
            throw 'Source cache entry inputs do not match the current assessment'
        }
        Test-AssessmentResponseEntry -Entry $entry.entry -ExpectedRecord $ExpectedRecord -Context $Context -AssessmentCardinality $AssessmentCardinality -KnownHostedRuleIds $KnownHostedRuleIds -DraftSchemaPath $DraftSchemaPath
        return $entry.entry
    }
    catch {
        if ($ShowProgress) {
            Write-Host (Format-ValidationStatusLine -Status 'skipped' -Name 'source-assessment/cache' -Detail ("{0}; {1}" -f $Context, $_.Exception.Message) -NameWidth 42)
        }
        Remove-Item -LiteralPath $Path -Force -ErrorAction SilentlyContinue
        return $null
    }
}

function Get-RetainedAssessmentEntries {
    param(
        [Parameter(Mandatory = $true)][string]$RetainedRunDirectory,
        [Parameter(Mandatory = $true)][string]$CurrentCatalogPath,
        [Parameter(Mandatory = $true)][string]$CurrentContractPath,
        [Parameter(Mandatory = $true)][string]$CurrentDraftSchemaPath,
        [Parameter(Mandatory = $true)][string]$CurrentPromptPath,
        [Parameter(Mandatory = $true)][Collections.Generic.HashSet[string]]$KnownHostedRuleIds
    )

    $retainedContractPath = Join-Path $RetainedRunDirectory 'repository/hosted_copilot/copilot-rule-catalog/rule-assessments/source-assessment-v4.json'
    if (-not (Test-Path -LiteralPath $retainedContractPath -PathType Leaf) -or (Get-SourceEvidenceFileSha256 -Path $CurrentContractPath) -cne (Get-SourceEvidenceFileSha256 -Path $retainedContractPath)) {
        return @{}
    }
    $entries = @{}
    foreach ($retainedBatchDirectory in @(Get-ChildItem -LiteralPath $RetainedRunDirectory -Directory)) {
        $batchPath = Join-Path $retainedBatchDirectory.FullName 'source-records.json'
        $responsePath = Join-Path $retainedBatchDirectory.FullName 'response.json'
        $pairs = @(
            @($CurrentCatalogPath, (Join-Path $retainedBatchDirectory.FullName 'hosted-instruction-catalog.json')),
            @($CurrentDraftSchemaPath, (Join-Path $retainedBatchDirectory.FullName 'source-assessment-draft.schema.json')),
            @($CurrentPromptPath, (Join-Path $retainedBatchDirectory.FullName 'SourceAssessment-v4.md'))
        )
        if (-not (Test-Path -LiteralPath $batchPath -PathType Leaf) -or -not (Test-Path -LiteralPath $responsePath -PathType Leaf)) {
            continue
        }
        if (@($pairs | Where-Object { -not (Test-Path -LiteralPath $_[1] -PathType Leaf) -or (Get-SourceEvidenceFileSha256 -Path $_[0]) -cne (Get-SourceEvidenceFileSha256 -Path $_[1]) }).Count -gt 0) {
            continue
        }
        try {
            $batch = Get-Content -LiteralPath $batchPath -Raw | ConvertFrom-Json
            $response = Get-Content -LiteralPath $responsePath -Raw | ConvertFrom-Json
            $recordsByKey = @{}
            foreach ($record in @($batch.records)) {
                $recordsByKey["$($record.sourceRef.sourceDefinitionId):$($record.sourceRef.sourceId)"] = $record
            }
            foreach ($entry in @($response.entries)) {
                $key = "$($entry.sourceRef.sourceDefinitionId):$($entry.sourceRef.sourceId)"
                if (-not $recordsByKey.ContainsKey($key) -or $entries.ContainsKey($key)) {
                    continue
                }
                try {
                    Test-AssessmentResponseEntry -Entry $entry -ExpectedRecord $recordsByKey[$key] -Context "retained $($retainedBatchDirectory.Name):$key" -AssessmentCardinality ([string]$batch.assessmentCardinality) -KnownHostedRuleIds $KnownHostedRuleIds -DraftSchemaPath $CurrentDraftSchemaPath
                    $entries[$key] = [pscustomobject]@{
                        Record = $recordsByKey[$key]
                        Entry = $entry
                        AssessmentCardinality = [string]$batch.assessmentCardinality
                    }
                }
                catch { }
            }
        }
        catch { }
    }
    return $entries
}

function Copy-RunInputFile {
    param(
        [Parameter(Mandatory = $true)][string]$SourcePath,
        [Parameter(Mandatory = $true)][string]$DestinationPath
    )

    $snapshot = Get-SourceEvidenceFileSnapshot -Path $SourcePath
    $destinationDirectory = Split-Path -Parent $DestinationPath
    if (-not (Test-Path -LiteralPath $destinationDirectory -PathType Container)) {
        $null = New-Item -ItemType Directory -Path $destinationDirectory -Force
    }
    [IO.File]::WriteAllBytes($DestinationPath, $snapshot.Bytes)
    return $DestinationPath
}

function Copy-RepositoryRunInput {
    param(
        [Parameter(Mandatory = $true)][string]$RelativePath,
        [Parameter(Mandatory = $true)][string]$SourceRoot,
        [Parameter(Mandatory = $true)][string]$DestinationRoot
    )

    $sourcePath = [IO.Path]::GetFullPath((Join-Path $SourceRoot $RelativePath))
    $destinationPath = [IO.Path]::GetFullPath((Join-Path $DestinationRoot $RelativePath))
    $null = Copy-RunInputFile -SourcePath $sourcePath -DestinationPath $destinationPath
    return $destinationPath
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

function Get-JsonUtf8ByteCount {
    param([Parameter(Mandatory = $true)][object]$Value)

    $json = ($Value | ConvertTo-Json -Depth 40) + "`n"
    return [Text.Encoding]::UTF8.GetByteCount($json)
}

function New-AssessmentBatchPacket {
    param(
        [Parameter(Mandatory = $true)][string]$BatchId,
        [Parameter(Mandatory = $true)][string]$SourceDefinitionId,
        [Parameter(Mandatory = $true)][string]$AssessmentCardinality,
        [Parameter(Mandatory = $true)][object[]]$Records
    )

    return [ordered]@{
        schemaVersion = 1
        batchId = $BatchId
        sourceDefinitionId = $SourceDefinitionId
        assessmentCardinality = $AssessmentCardinality
        sourceCount = $Records.Count
        records = $Records
    }
}

function New-EvaluatorAttemptPrompt {
    param([Parameter(Mandatory = $true)][int]$SourceCount)

    return @"
Read the source assessment contract, source record batch, Hosted instruction catalog, and output schema from the current batch directory before evaluating the batch.

Source assessment contract: SourceAssessment-v4.md
Source record batch: source-records.json
Hosted instruction catalog: hosted-instruction-catalog.json
Output schema: source-assessment-draft.schema.json

This batch contains exactly $SourceCount source records. Write only the requested JSON object in your final response.
"@
}

function Get-AssessmentBatchPayloadSizeBytes {
    param(
        [Parameter(Mandatory = $true)][object]$Packet,
        [Parameter(Mandatory = $true)][int]$StaticInputBytes
    )

    $attemptPrompt = New-EvaluatorAttemptPrompt -SourceCount @($Packet.records).Count
    return $StaticInputBytes + (Get-JsonUtf8ByteCount -Value $Packet) + [Text.Encoding]::UTF8.GetByteCount($attemptPrompt)
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
        [Parameter(Mandatory = $true)][string]$AssessmentCardinality,
        [Parameter(Mandatory = $true)][Collections.Generic.HashSet[string]]$KnownHostedRuleIds
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
        $priorSourceEvidence = $expectedByKey[$key].priorSourceEvidence
        foreach ($assessment in @($entry.assessments)) {
            foreach ($coverage in @($assessment.relatedHostedCoverage)) {
                $hostedRuleId = [string]$coverage.hostedRuleId
                if (-not $KnownHostedRuleIds.Contains($hostedRuleId)) {
                    throw "Evaluator response references unknown related Hosted coverage in $BatchId`: $key`: $hostedRuleId"
                }
            }
            if ($null -eq $priorSourceEvidence) {
                if ($null -ne $assessment.semanticReassessment) {
                    throw "Evaluator returned semantic reassessment without prior source evidence in $BatchId`: $key"
                }
            }
            else {
                if ($null -eq $assessment.semanticReassessment) {
                    throw "Evaluator omitted semantic reassessment for changed source evidence in $BatchId`: $key"
                }
                if ([string]$assessment.semanticReassessment.priorContentSha256 -cne [string]$priorSourceEvidence.sourceRef.contentSha256) {
                    throw "Evaluator changed the prior source hash in $BatchId`: $key"
                }
            }
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
$resolvedCacheDirectory = [IO.Path]::GetFullPath($CacheDirectory)
if ($resolvedCacheDirectory.StartsWith($repositoryPrefix, [StringComparison]::OrdinalIgnoreCase)) {
    throw 'CacheDirectory must be outside the repository root'
}
$resolvedResumeRunDirectory = $null
if (-not [string]::IsNullOrWhiteSpace($ResumeRunDirectory)) {
    $resolvedResumeRunDirectory = [IO.Path]::GetFullPath($ResumeRunDirectory)
    if ($resolvedResumeRunDirectory.StartsWith($repositoryPrefix, [StringComparison]::OrdinalIgnoreCase)) {
        throw 'ResumeRunDirectory must be outside the repository root'
    }
    if (-not (Test-Path -LiteralPath $resolvedResumeRunDirectory -PathType Container)) {
        throw "ResumeRunDirectory was not found: $resolvedResumeRunDirectory"
    }
}

$resolvedBuilderPath = [IO.Path]::GetFullPath($BaselineBuilderPath)
$resolvedCatalogPath = [IO.Path]::GetFullPath($HostedCatalogPath)
$resolvedContractPath = [IO.Path]::GetFullPath($AssessmentContractPath)
$inventorySchemaPath = Join-Path $resolvedRepositoryRoot 'hosted_copilot/copilot-rule-catalog/source-inventories/source-inventory.schema.json'
$definitionSchemaPath = Join-Path $resolvedRepositoryRoot 'hosted_copilot/copilot-rule-catalog/source-definitions/source-definition.schema.json'
$draftSchemaPath = Join-Path $resolvedRepositoryRoot 'hosted_copilot/copilot-rule-catalog/rule-assessments/source-assessment-draft.schema.json'
$promptPath = Join-Path $resolvedRepositoryRoot 'hosted_copilot/tools/assessment-prompts/SourceAssessment-v4.md'
$runDirectory = Join-Path ([IO.Path]::GetTempPath()) ('hosted-source-assessment/' + [guid]::NewGuid().ToString('N'))
$managedRunRootPrefix = [IO.Path]::GetFullPath((Join-Path ([IO.Path]::GetTempPath()) 'hosted-source-assessment')).TrimEnd([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar) + [IO.Path]::DirectorySeparatorChar
$runRepositoryRoot = Join-Path $runDirectory 'repository'
foreach ($requiredPath in @($resolvedBuilderPath, $resolvedCatalogPath, $resolvedContractPath, $inventorySchemaPath, $definitionSchemaPath, $draftSchemaPath, $promptPath)) {
    if (-not (Test-Path -LiteralPath $requiredPath -PathType Leaf)) {
        throw "Required source assessment input was not found: $requiredPath"
    }
}
$canonicalBuilderPath = [IO.Path]::GetFullPath((Join-Path $resolvedRepositoryRoot 'hosted_copilot/tools/internal/assessment/New-SourceAssessmentBaseline.ps1'))
if ($resolvedBuilderPath -cne $canonicalBuilderPath) {
    throw 'BaselineBuilderPath must identify the canonical contract-owned baseline builder'
}
$null = New-Item -ItemType Directory -Path $runRepositoryRoot -Force
$assessmentContract = Get-Content -LiteralPath $resolvedContractPath -Raw | ConvertFrom-Json
$assessmentContractSnapshotPath = Join-Path $runRepositoryRoot 'hosted_copilot/copilot-rule-catalog/rule-assessments/source-assessment-v4.json'
$null = Copy-RunInputFile -SourcePath $resolvedContractPath -DestinationPath $assessmentContractSnapshotPath
$repositoryInputs = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
foreach ($relativePath in @(
    'hosted_copilot/copilot-rule-catalog/rule-assessments/assessment-contract.schema.json',
    'hosted_copilot/copilot-rule-catalog/parser-contracts/parser-contract.schema.json',
    'hosted_copilot/copilot-rule-catalog/source-definitions/source-definition.schema.json',
    'hosted_copilot/copilot-rule-catalog/source-inventories/source-inventory.schema.json',
    'hosted_copilot/copilot-rule-catalog/instruction-catalog.schema.json'
) + @($assessmentContract.behaviorFiles)) {
    $null = $repositoryInputs.Add([string]$relativePath)
}
$expectedSourceDefinitionIds = @(Get-ExpectedSourceDefinitionIds -RepositoryRoot $resolvedRepositoryRoot)
foreach ($sourceDefinitionId in $expectedSourceDefinitionIds) {
    $definitionRelativePath = "hosted_copilot/copilot-rule-catalog/source-definitions/$sourceDefinitionId.json"
    $null = $repositoryInputs.Add($definitionRelativePath)
    $definition = Get-Content -LiteralPath (Join-Path $resolvedRepositoryRoot $definitionRelativePath) -Raw | ConvertFrom-Json
    $contractRelativePath = "hosted_copilot/copilot-rule-catalog/parser-contracts/$($definition.parser).json"
    $null = $repositoryInputs.Add($contractRelativePath)
    $parserContract = Get-Content -LiteralPath (Join-Path $resolvedRepositoryRoot $contractRelativePath) -Raw | ConvertFrom-Json
    foreach ($behaviorFile in @($parserContract.behaviorFiles)) {
        $null = $repositoryInputs.Add([string]$behaviorFile)
    }
}
foreach ($relativePath in $repositoryInputs) {
    $null = Copy-RepositoryRunInput -RelativePath $relativePath -SourceRoot $resolvedRepositoryRoot -DestinationRoot $runRepositoryRoot
}
$resolvedBuilderPath = Join-Path $runRepositoryRoot 'hosted_copilot/tools/internal/assessment/New-SourceAssessmentBaseline.ps1'
$resolvedCatalogPath = Copy-RunInputFile -SourcePath $resolvedCatalogPath -DestinationPath (Join-Path $runRepositoryRoot 'hosted_copilot/copilot-rule-catalog/instruction-catalog.json')
$resolvedContractPath = $assessmentContractSnapshotPath
$inventorySchemaPath = Join-Path $runRepositoryRoot 'hosted_copilot/copilot-rule-catalog/source-inventories/source-inventory.schema.json'
$definitionSchemaPath = Join-Path $runRepositoryRoot 'hosted_copilot/copilot-rule-catalog/source-definitions/source-definition.schema.json'
$draftSchemaPath = Join-Path $runRepositoryRoot 'hosted_copilot/copilot-rule-catalog/rule-assessments/source-assessment-draft.schema.json'
$catalogSchemaPath = Join-Path $runRepositoryRoot 'hosted_copilot/copilot-rule-catalog/instruction-catalog.schema.json'
$promptPath = Join-Path $runRepositoryRoot 'hosted_copilot/tools/assessment-prompts/SourceAssessment-v4.md'
$resolvedEvaluatorScriptPath = $null
$evaluatorIdentity = $EvaluatorCommand
if (-not [string]::IsNullOrWhiteSpace($EvaluatorScriptPath)) {
    $resolvedEvaluatorScriptPath = [IO.Path]::GetFullPath($EvaluatorScriptPath)
    if (-not (Test-Path -LiteralPath $resolvedEvaluatorScriptPath -PathType Leaf)) {
        throw "Evaluator script was not found: $resolvedEvaluatorScriptPath"
    }
    $evaluatorSnapshot = Get-SourceEvidenceFileSnapshot -Path $resolvedEvaluatorScriptPath
    $resolvedEvaluatorScriptPath = Join-Path $runDirectory 'evaluator.ps1'
    [IO.File]::WriteAllBytes($resolvedEvaluatorScriptPath, $evaluatorSnapshot.Bytes)
    $evaluatorIdentity = 'script:' + $evaluatorSnapshot.Sha256
}

$catalogJson = Get-Content -LiteralPath $resolvedCatalogPath -Raw
if (-not (Test-Json -Json $catalogJson -SchemaFile $catalogSchemaPath -ErrorAction Stop)) {
    throw "Hosted catalog does not satisfy its schema: $resolvedCatalogPath"
}
$catalog = $catalogJson | ConvertFrom-Json
$hostedRulesBySourceId = @{}
$knownHostedRuleIds = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
foreach ($rule in @($catalog.rules)) {
    $null = $knownHostedRuleIds.Add([string]$rule.id)
    foreach ($sourceId in @($rule.sourceIds)) {
        if (-not $hostedRulesBySourceId.ContainsKey([string]$sourceId)) {
            $hostedRulesBySourceId[[string]$sourceId] = [Collections.Generic.List[string]]::new()
        }
        $hostedRulesBySourceId[[string]$sourceId].Add([string]$rule.id)
    }
}
$lanes = [Collections.Generic.List[object]]::new()
$snapshotInventoryPaths = [Collections.Generic.List[string]]::new()
$snapshotPriorInventoryPaths = [Collections.Generic.List[string]]::new()
$priorInventories = @{}
foreach ($priorInventoryPath in $PriorInventoryPaths) {
    $priorSnapshot = Get-SourceEvidenceFileSnapshot -Path ([IO.Path]::GetFullPath($priorInventoryPath))
    if (-not (Test-Json -Json $priorSnapshot.Content -SchemaFile $inventorySchemaPath -ErrorAction Stop)) {
        throw "Prior source inventory does not satisfy its schema: $priorInventoryPath"
    }
    $priorInventory = $priorSnapshot.Content | ConvertFrom-Json -DateKind String
    Assert-SourceInventoryIntegrity -Inventory $priorInventory
    $priorSourceDefinitionId = [string]$priorInventory.sourceDefinitionId
    if ($priorInventories.ContainsKey($priorSourceDefinitionId)) {
        throw "Source assessment received duplicate prior inventory sourceDefinitionId: $priorSourceDefinitionId"
    }
    if ($priorSourceDefinitionId -notin $expectedSourceDefinitionIds) {
        throw "Source assessment received an unknown prior inventory sourceDefinitionId: $priorSourceDefinitionId"
    }
    $snapshotPriorInventoryPath = Join-Path $runDirectory "prior-inventories/$priorSourceDefinitionId.json"
    $snapshotPriorInventoryDirectory = Split-Path -Parent $snapshotPriorInventoryPath
    if (-not (Test-Path -LiteralPath $snapshotPriorInventoryDirectory -PathType Container)) {
        $null = New-Item -ItemType Directory -Path $snapshotPriorInventoryDirectory -Force
    }
    [IO.File]::WriteAllBytes($snapshotPriorInventoryPath, $priorSnapshot.Bytes)
    $snapshotPriorInventoryPaths.Add($snapshotPriorInventoryPath)
    $priorInventories[$priorSourceDefinitionId] = $priorInventory
}
foreach ($inventoryPath in $InventoryPaths) {
    $resolvedInventoryPath = [IO.Path]::GetFullPath($inventoryPath)
    $inventorySnapshot = Get-SourceEvidenceFileSnapshot -Path $resolvedInventoryPath
    $inventoryJson = $inventorySnapshot.Content
    if (-not (Test-Json -Json $inventoryJson -SchemaFile $inventorySchemaPath -ErrorAction Stop)) {
        throw "Source inventory does not satisfy its schema: $resolvedInventoryPath"
    }
    $inventory = $inventoryJson | ConvertFrom-Json -DateKind String
    $sourceDefinitionId = [string]$inventory.sourceDefinitionId
    if (@($lanes | Where-Object sourceDefinitionId -eq $sourceDefinitionId).Count -gt 0) {
        throw "Source assessment received duplicate inventory sourceDefinitionId: $sourceDefinitionId"
    }
    $snapshotInventoryPath = Join-Path $runDirectory "inventories/$sourceDefinitionId.json"
    $snapshotInventoryDirectory = Split-Path -Parent $snapshotInventoryPath
    if (-not (Test-Path -LiteralPath $snapshotInventoryDirectory -PathType Container)) {
        $null = New-Item -ItemType Directory -Path $snapshotInventoryDirectory -Force
    }
    [IO.File]::WriteAllBytes($snapshotInventoryPath, $inventorySnapshot.Bytes)
    $snapshotInventoryPaths.Add($snapshotInventoryPath)
    $definitionPath = Join-Path $runRepositoryRoot "hosted_copilot/copilot-rule-catalog/source-definitions/$sourceDefinitionId.json"
    $definitionJson = Get-Content -LiteralPath $definitionPath -Raw
    if (-not (Test-Json -Json $definitionJson -SchemaFile $definitionSchemaPath -ErrorAction Stop)) {
        throw "Source definition does not satisfy its schema: $definitionPath"
    }
    $definition = $definitionJson | ConvertFrom-Json
    $sourceEvidence = Get-CurrentSourceDefinitionEvidence -RepositoryRoot $runRepositoryRoot -SourceDefinitionId $sourceDefinitionId
    Assert-CurrentSourceInventory -Inventory $inventory -Evidence $sourceEvidence

    $priorInventory = if ($priorInventories.ContainsKey($sourceDefinitionId)) { $priorInventories[$sourceDefinitionId] } else { $null }
    $projectionRecords = @(Get-SourceInventoryProjectionRecords -CurrentInventory $inventory -PriorInventory $priorInventory -RemovedAt $GeneratedAt)
    $packetRecords = @($projectionRecords | ForEach-Object {
        $record = $_
        $mappedHostedRuleIds = [Collections.Generic.List[string]]::new()
        if ($sourceDefinitionId -ceq 'contributor-guidance' -and $hostedRulesBySourceId.ContainsKey([string]$record.sourceId)) {
            foreach ($hostedRuleId in $hostedRulesBySourceId[[string]$record.sourceId]) {
                $mappedHostedRuleIds.Add($hostedRuleId)
            }
        }
        [string[]]$uniqueMappedIds = @($mappedHostedRuleIds | Sort-Object -Unique)
        $priorSourceEvidence = if ($null -eq $priorInventory) {
            $null
        }
        else {
            Get-PriorSourceInventoryEvidence -PriorInventory $priorInventory -SourceId ([string]$record.sourceId) -CurrentRecord $record
        }
        [ordered]@{
            sourceRef = [ordered]@{
                sourceDefinitionId = $sourceDefinitionId
                sourceId = [string]$record.sourceId
                contentSha256 = [string]$record.contentSha256
            }
            sourceRecord = $record
            priorSourceEvidence = $priorSourceEvidence
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

$staticEvaluatorInputBytes = 0
foreach ($path in @($resolvedCatalogPath, $draftSchemaPath, $promptPath)) {
    $staticEvaluatorInputBytes += [IO.File]::ReadAllBytes($path).Length
}
$draftEntries = [Collections.Generic.List[object]]::new()
$cachedSourceCount = 0
$recoveredSourceCount = 0
$evaluatedSourceCount = 0
$sourceCacheMetadata = @{}
$retainedEntries = if ($null -ne $resolvedResumeRunDirectory) {
    Get-RetainedAssessmentEntries -RetainedRunDirectory $resolvedResumeRunDirectory -CurrentCatalogPath $resolvedCatalogPath -CurrentContractPath $resolvedContractPath -CurrentDraftSchemaPath $draftSchemaPath -CurrentPromptPath $promptPath -KnownHostedRuleIds $knownHostedRuleIds
}
else {
    @{}
}
$pendingLanes = [Collections.Generic.List[object]]::new()
foreach ($lane in $orderedLanes) {
    $pendingRecords = [Collections.Generic.List[object]]::new()
    foreach ($record in @($lane.records)) {
        $sourceKey = "$($record.sourceRef.sourceDefinitionId):$($record.sourceRef.sourceId)"
        $cacheIdentity = Get-AssessmentSourceCacheIdentity -SourceRecord $record -AssessmentCardinality ([string]$lane.assessmentCardinality) -CatalogPath $resolvedCatalogPath -ContractPath $resolvedContractPath -DraftSchemaPath $draftSchemaPath -PromptPath $promptPath -Evaluator $evaluatorIdentity -Model $Model -ReasoningEffort $ReasoningEffort
        $cacheKey = Get-AssessmentSourceCacheKey -Identity $cacheIdentity
        $cachePath = Join-Path $resolvedCacheDirectory "$cacheKey.json"
        $sourceCacheMetadata[$sourceKey] = [pscustomobject]@{ Identity = $cacheIdentity; Key = $cacheKey; Path = $cachePath; Record = $record; AssessmentCardinality = [string]$lane.assessmentCardinality }
        $entry = Read-AssessmentSourceCache -Path $cachePath -ExpectedCacheKey $cacheKey -ExpectedIdentity $cacheIdentity -ExpectedRecord $record -Context "cached $sourceKey" -AssessmentCardinality ([string]$lane.assessmentCardinality) -KnownHostedRuleIds $knownHostedRuleIds -DraftSchemaPath $draftSchemaPath -ShowProgress:($OutputFormat -eq 'Text' -or $ShowProgress)
        if ($null -ne $entry) {
            $draftEntries.Add($entry)
            $cachedSourceCount++
            continue
        }
        if ($retainedEntries.ContainsKey($sourceKey)) {
            $retained = $retainedEntries[$sourceKey]
            if ([string]$retained.AssessmentCardinality -ceq [string]$lane.assessmentCardinality -and ($retained.Record | ConvertTo-Json -Depth 40 -Compress) -ceq ($record | ConvertTo-Json -Depth 40 -Compress)) {
                Test-AssessmentResponseEntry -Entry $retained.Entry -ExpectedRecord $record -Context "recovered $sourceKey" -AssessmentCardinality ([string]$lane.assessmentCardinality) -KnownHostedRuleIds $knownHostedRuleIds -DraftSchemaPath $draftSchemaPath
                Write-JsonAtomically -Path $cachePath -Value ([ordered]@{
                    schemaVersion = 1
                    kind = 'hosted-source-assessment-source-cache'
                    cacheKey = $cacheKey
                    identity = $cacheIdentity
                    entry = $retained.Entry
                })
                $draftEntries.Add($retained.Entry)
                $recoveredSourceCount++
                continue
            }
        }
        $pendingRecords.Add($record)
    }
    if ($pendingRecords.Count -gt 0) {
        $pendingLanes.Add([ordered]@{
            sourceDefinitionId = [string]$lane.sourceDefinitionId
            assessmentBatchSize = [int]$lane.assessmentBatchSize
            assessmentCardinality = [string]$lane.assessmentCardinality
            records = $pendingRecords.ToArray()
        })
    }
}
if (($OutputFormat -eq 'Text' -or $ShowProgress) -and ($cachedSourceCount -gt 0 -or $recoveredSourceCount -gt 0)) {
    Write-Host (Format-ValidationStatusLine -Status 'passed' -Name 'source-assessment/reuse' -Detail ("{0} cached, {1} recovered, {2} require evaluation" -f $cachedSourceCount, $recoveredSourceCount, ($orderedLanes.records.Count - $cachedSourceCount - $recoveredSourceCount)) -NameWidth 42)
}
$batches = [Collections.Generic.List[object]]::new()
$nextBatchNumber = 1
foreach ($lane in $pendingLanes) {
    $currentRecords = [Collections.Generic.List[object]]::new()
    foreach ($record in @($lane.records)) {
        if ($currentRecords.Count -eq [int]$lane.assessmentBatchSize) {
            $batchId = '{0}-{1:D3}' -f $lane.sourceDefinitionId, $nextBatchNumber
            $packet = New-AssessmentBatchPacket -BatchId $batchId -SourceDefinitionId ([string]$lane.sourceDefinitionId) -AssessmentCardinality ([string]$lane.assessmentCardinality) -Records $currentRecords.ToArray()
            $batches.Add([ordered]@{ batchId = $batchId; packet = $packet; payloadSizeBytes = Get-AssessmentBatchPayloadSizeBytes -Packet $packet -StaticInputBytes $staticEvaluatorInputBytes })
            $nextBatchNumber++
            $currentRecords.Clear()
        }

        $candidateRecords = @($currentRecords.ToArray()) + @($record)
        $candidateBatchId = '{0}-{1:D3}' -f $lane.sourceDefinitionId, $nextBatchNumber
        $candidatePacket = New-AssessmentBatchPacket -BatchId $candidateBatchId -SourceDefinitionId ([string]$lane.sourceDefinitionId) -AssessmentCardinality ([string]$lane.assessmentCardinality) -Records $candidateRecords
        $candidatePayloadSizeBytes = Get-AssessmentBatchPayloadSizeBytes -Packet $candidatePacket -StaticInputBytes $staticEvaluatorInputBytes
        if ($candidatePayloadSizeBytes -gt $EvaluatorPayloadBudgetBytes) {
            if ($currentRecords.Count -eq 0) {
                throw "Source assessment record exceeds evaluator payload budget: source stream $($lane.sourceDefinitionId), source record $($record.sourceRef.sourceId), measured $candidatePayloadSizeBytes bytes, budget $EvaluatorPayloadBudgetBytes bytes; reduce or split the parser-owned source record before assessment"
            }
            $batchId = '{0}-{1:D3}' -f $lane.sourceDefinitionId, $nextBatchNumber
            $packet = New-AssessmentBatchPacket -BatchId $batchId -SourceDefinitionId ([string]$lane.sourceDefinitionId) -AssessmentCardinality ([string]$lane.assessmentCardinality) -Records $currentRecords.ToArray()
            $batches.Add([ordered]@{ batchId = $batchId; packet = $packet; payloadSizeBytes = Get-AssessmentBatchPayloadSizeBytes -Packet $packet -StaticInputBytes $staticEvaluatorInputBytes })
            $nextBatchNumber++
            $currentRecords.Clear()

            $candidateBatchId = '{0}-{1:D3}' -f $lane.sourceDefinitionId, $nextBatchNumber
            $candidatePacket = New-AssessmentBatchPacket -BatchId $candidateBatchId -SourceDefinitionId ([string]$lane.sourceDefinitionId) -AssessmentCardinality ([string]$lane.assessmentCardinality) -Records @($record)
            $candidatePayloadSizeBytes = Get-AssessmentBatchPayloadSizeBytes -Packet $candidatePacket -StaticInputBytes $staticEvaluatorInputBytes
            if ($candidatePayloadSizeBytes -gt $EvaluatorPayloadBudgetBytes) {
                throw "Source assessment record exceeds evaluator payload budget: source stream $($lane.sourceDefinitionId), source record $($record.sourceRef.sourceId), measured $candidatePayloadSizeBytes bytes, budget $EvaluatorPayloadBudgetBytes bytes; reduce or split the parser-owned source record before assessment"
            }
        }
        $currentRecords.Add($record)
    }
    if ($currentRecords.Count -gt 0) {
        $batchId = '{0}-{1:D3}' -f $lane.sourceDefinitionId, $nextBatchNumber
        $packet = New-AssessmentBatchPacket -BatchId $batchId -SourceDefinitionId ([string]$lane.sourceDefinitionId) -AssessmentCardinality ([string]$lane.assessmentCardinality) -Records $currentRecords.ToArray()
        $batches.Add([ordered]@{
            batchId = $batchId
            packet = $packet
            payloadSizeBytes = Get-AssessmentBatchPayloadSizeBytes -Packet $packet -StaticInputBytes $staticEvaluatorInputBytes
        })
        $nextBatchNumber++
    }
}

$evaluatedBatchCount = 0
$succeeded = $false
try {
    $null = New-Item -ItemType Directory -Path $runDirectory -Force
    foreach ($batch in $batches) {
        $batchId = [string]$batch.batchId
        $batchPacket = $batch.packet
        $batchDirectory = Join-Path $runDirectory $batchId
        $null = New-Item -ItemType Directory -Path $batchDirectory -Force
        $batchPath = Join-Path $batchDirectory 'source-records.json'
        $catalogPath = Join-Path $batchDirectory 'hosted-instruction-catalog.json'
        $schemaPath = Join-Path $batchDirectory 'source-assessment-draft.schema.json'
        $batchPromptPath = Join-Path $batchDirectory 'SourceAssessment-v4.md'
        $responsePath = Join-Path $batchDirectory 'response.json'
        Copy-Item -LiteralPath $resolvedCatalogPath -Destination $catalogPath
        Copy-Item -LiteralPath $draftSchemaPath -Destination $schemaPath
        Copy-Item -LiteralPath $promptPath -Destination $batchPromptPath
        Write-JsonAtomically -Path $batchPath -Value $batchPacket

        if ($OutputFormat -eq 'Text' -or $ShowProgress) {
            Write-Host (Format-ValidationStatusLine -Status 'running' -Name "source-assessment/$batchId" -Detail ("{0} sources, {1} payload bytes" -f @($batchPacket.records).Count, $batch.payloadSizeBytes) -NameWidth 42)
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
                    $attemptPrompt = New-EvaluatorAttemptPrompt -SourceCount @($batchPacket.records).Count
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
                try {
                    $validResponse = Test-Json -Json $responseJson -SchemaFile $draftSchemaPath -ErrorAction Stop
                }
                catch {
                    throw "Evaluator response does not satisfy the source assessment draft: $batchId"
                }
                if (-not $validResponse) {
                    throw "Evaluator response does not satisfy the source assessment draft: $batchId"
                }
                $response = $responseJson | ConvertFrom-Json
                Assert-BatchResponse -Response $response -ExpectedRecords @($batchPacket.records) -BatchId $batchId -AssessmentCardinality ([string]$batchPacket.assessmentCardinality) -KnownHostedRuleIds $knownHostedRuleIds
                $evaluatedBatchCount++
                $lastError = $null
                break
            }
            catch {
                $lastError = $_
                Remove-Item -LiteralPath $responsePath -Force -ErrorAction SilentlyContinue
                if ($attempt -le $MaxRetries) {
                    $delayMilliseconds = Get-SourceEvidenceRetryDelayMilliseconds -Attempt $attempt -BaseDelayMilliseconds $RetryDelayMilliseconds
                    if ($delayMilliseconds -gt 0) {
                        Start-Sleep -Milliseconds $delayMilliseconds
                    }
                }
            }
        }
        if ($null -ne $lastError) {
            throw "Source assessment $batchId failed after $($MaxRetries + 1) attempts: $($lastError.Exception.Message)"
        }
        foreach ($entry in @($response.entries)) {
            $sourceKey = "$($entry.sourceRef.sourceDefinitionId):$($entry.sourceRef.sourceId)"
            $cacheMetadata = $sourceCacheMetadata[$sourceKey]
            Write-JsonAtomically -Path $cacheMetadata.Path -Value ([ordered]@{
                schemaVersion = 1
                kind = 'hosted-source-assessment-source-cache'
                cacheKey = $cacheMetadata.Key
                identity = $cacheMetadata.Identity
                entry = $entry
            })
            $draftEntries.Add($entry)
            $evaluatedSourceCount++
        }
        if ($OutputFormat -eq 'Text' -or $ShowProgress) {
            Write-Host (Format-ValidationStatusLine -Status 'passed' -Name "source-assessment/$batchId" -Detail ("evaluated; {0} sources, {1} payload bytes" -f @($batchPacket.records).Count, $batch.payloadSizeBytes) -NameWidth 42)
        }
    }

    $draftPath = Join-Path $runDirectory 'source-assessment-draft.json'
    Write-JsonAtomically -Path $draftPath -Value ([ordered]@{
        '$schema' = 'source-assessment-draft.schema.json'
        schemaVersion = 1
        entries = @(Get-SortedObjects -Values $draftEntries.ToArray() -Key { param($entry) "$($entry.sourceRef.sourceDefinitionId):$($entry.sourceRef.sourceId)" })
    })
    $builderParameters = @{
        RepositoryRoot = $runRepositoryRoot
        InventoryPaths = $snapshotInventoryPaths.ToArray()
        AssessmentDraftPath = $draftPath
        HostedCatalogPath = $resolvedCatalogPath
        AssessmentContractPath = $resolvedContractPath
        OutputPath = $resolvedOutputPath
        Model = $Model
        ReasoningEffort = $ReasoningEffort
        EvaluatorPayloadBudgetBytes = $EvaluatorPayloadBudgetBytes
        Evaluator = $evaluatorIdentity
        GeneratedAt = $GeneratedAt
        OutputFormat = 'Json'
    }
    if ($snapshotPriorInventoryPaths.Count -gt 0) {
        $builderParameters.PriorInventoryPaths = $snapshotPriorInventoryPaths.ToArray()
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
    if ($succeeded -and $null -ne $resolvedResumeRunDirectory -and $resolvedResumeRunDirectory.StartsWith($managedRunRootPrefix, [StringComparison]::OrdinalIgnoreCase) -and (Test-Path -LiteralPath $resolvedResumeRunDirectory -PathType Container)) {
        Remove-Item -LiteralPath $resolvedResumeRunDirectory -Recurse -Force
    }
}

$result = [ordered]@{
    status = 'passed'
    outputPath = $resolvedOutputPath
    sourceCount = [int]$builderResult.sourceCount
    assessmentCount = [int]$builderResult.assessmentCount
    batchCount = $batches.Count
    cachedSourceCount = $cachedSourceCount
    recoveredSourceCount = $recoveredSourceCount
    evaluatedSourceCount = $evaluatedSourceCount
    evaluatedBatchCount = $evaluatedBatchCount
    cacheDirectory = $resolvedCacheDirectory
    baselineSha256 = [string]$builderResult.baselineSha256
    assessmentContractSha256 = [string]$builderResult.assessmentContractSha256
    assessmentRunConfigurationSha256 = [string]$builderResult.assessmentRunConfigurationSha256
}
if ($OutputFormat -eq 'Json') {
    $result | ConvertTo-Json -Depth 5
}
else {
    Write-Output "Source assessment completed: $($result.sourceCount) sources, $($result.assessmentCount) assessments; $($result.cachedSourceCount) cached, $($result.recoveredSourceCount) recovered, $($result.evaluatedSourceCount) evaluated across $($result.evaluatedBatchCount) batches"
    Write-Output "Output: $($result.outputPath)"
    Write-Output "Baseline SHA-256: $($result.baselineSha256)"
}
