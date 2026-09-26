[CmdletBinding()]
param(
    [string]$RepositoryRoot = (Join-Path $PSScriptRoot '../../../..'),

    [Parameter(Mandatory = $true)]
    [string[]]$InventoryPaths,

    [string[]]$PriorInventoryPaths = @(),

    [Parameter(Mandatory = $true)]
    [string]$OutputPath,

    [string]$HostedCatalogPath = (Join-Path $PSScriptRoot '../../../copilot-rule-catalog/instruction-catalog.json'),

    [string]$ProtectedRulesPath = (Join-Path $PSScriptRoot '../../../copilot-rule-catalog/protected-rules.json'),

    [string]$AssessmentContractPath = (Join-Path $PSScriptRoot '../../../copilot-rule-catalog/rule-assessments/source-assessment-v4.json'),

    [string]$BaselineBuilderPath = (Join-Path $PSScriptRoot 'New-SourceAssessmentBaseline.ps1'),

    [string]$EvaluatorCommand = 'copilot',

    [string]$EvaluatorScriptPath,

    [string]$Model = 'gpt-5.4',

    [ValidateSet('low', 'medium', 'high', 'xhigh')]
    [string]$ReasoningEffort = 'high',

    [ValidateRange(0, 3)]
    [int]$MaxRetries = 1,

    [ValidateRange(1, 8)]
    [int]$MaxParallelBatches = 3,

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
$helpersModulePath = Join-Path $PSScriptRoot '../../modules/shared/HostedToolkit.Helpers.psm1'
Import-Module -Name $helpersModulePath -Force
$validationOutputModulePath = Join-Path $PSScriptRoot '../../../../tools/ValidationOutput.psm1'
Import-Module -Name $validationOutputModulePath -Force
$sourceAssessmentBootstrapBytesPerSecondPerWorker = 500
$sourceAssessmentStopwatch = [Diagnostics.Stopwatch]::StartNew()

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

function Read-AssessmentCacheLedger {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [switch]$ShowProgress
    )

    $entriesBySource = @{}
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        return $entriesBySource
    }
    try {
        $ledger = Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json -DateKind String
        if (Compare-Object -ReferenceObject @('entries', 'kind', 'schemaVersion') -DifferenceObject @($ledger.PSObject.Properties.Name | Sort-Object)) {
            throw 'Assessment cache ledger has an unexpected property set'
        }
        if ([int]$ledger.schemaVersion -ne 1 -or [string]$ledger.kind -cne 'hosted-source-assessment-cache') {
            throw 'Assessment cache ledger header is invalid'
        }
        foreach ($cacheEntry in @($ledger.entries)) {
            if (Compare-Object -ReferenceObject @('contentSha256', 'result', 'sourceDefinitionId', 'sourceId') -DifferenceObject @($cacheEntry.PSObject.Properties.Name | Sort-Object)) {
                throw 'Assessment cache ledger entry has an unexpected property set'
            }
            $sourceKey = "$([string]$cacheEntry.sourceDefinitionId):$([string]$cacheEntry.sourceId)"
            if ($entriesBySource.ContainsKey($sourceKey)) {
                throw "Assessment cache ledger contains duplicate source: $sourceKey"
            }
            $entriesBySource[$sourceKey] = $cacheEntry
        }
        return $entriesBySource
    }
    catch {
        if ($ShowProgress) {
            Write-Host (Format-ValidationStatusLine -Status 'skipped' -Name 'source-assessment/cache' -Detail $_.Exception.Message -NameWidth 42)
        }
        Remove-Item -LiteralPath $Path -Force -ErrorAction SilentlyContinue
        return @{}
    }
}

function Write-AssessmentCacheLedger {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][object[]]$UpdatedEntries
    )

    return Invoke-WithExclusiveFileLock -Path ($Path + '.lock') -Operation {
        param($LedgerPath, $Updates)

        $entriesBySource = Read-AssessmentCacheLedger -Path $LedgerPath
        foreach ($cacheEntry in @($Updates)) {
            $sourceKey = "$([string]$cacheEntry.sourceDefinitionId):$([string]$cacheEntry.sourceId)"
            $entriesBySource[$sourceKey] = $cacheEntry
        }
        Write-JsonAtomically -Path $LedgerPath -Value ([ordered]@{
            schemaVersion = 1
            kind = 'hosted-source-assessment-cache'
            entries = @($entriesBySource.Values | Sort-Object -Property @{ Expression = { [string]$_.sourceDefinitionId } }, @{ Expression = { [string]$_.sourceId } })
        })
        return $entriesBySource
    } -ArgumentList @($Path, @($UpdatedEntries))
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
        [object]$CacheEntry,
        [Parameter(Mandatory = $true)][object]$ExpectedRecord,
        [Parameter(Mandatory = $true)][string]$Context,
        [Parameter(Mandatory = $true)][string]$AssessmentCardinality,
        [Parameter(Mandatory = $true)][Collections.Generic.HashSet[string]]$KnownHostedRuleIds,
        [Parameter(Mandatory = $true)][string]$DraftSchemaPath,
        [switch]$ShowProgress
    )

    if ($null -eq $CacheEntry) {
        return $null
    }
    try {
        if ([string]$CacheEntry.contentSha256 -cne [string]$ExpectedRecord.sourceRef.contentSha256) {
            throw 'Source cache entry content hash does not match'
        }
        Test-AssessmentResponseEntry -Entry $CacheEntry.result -ExpectedRecord $ExpectedRecord -Context $Context -AssessmentCardinality $AssessmentCardinality -KnownHostedRuleIds $KnownHostedRuleIds -DraftSchemaPath $DraftSchemaPath
        return $CacheEntry.result
    }
    catch {
        if ($ShowProgress) {
            Write-Host (Format-ValidationStatusLine -Status 'skipped' -Name 'source-assessment/cache' -Detail ("{0}; {1}" -f $Context, $_.Exception.Message) -NameWidth 42)
        }
        return $null
    }
}

function Get-RetainedAssessmentEntries {
    param(
        [Parameter(Mandatory = $true)][string]$RetainedRunDirectory,
        [Parameter(Mandatory = $true)][string]$CurrentDraftSchemaPath,
        [Parameter(Mandatory = $true)][Collections.Generic.HashSet[string]]$KnownHostedRuleIds
    )

    $entries = @{}
    foreach ($retainedBatchDirectory in @(Get-ChildItem -LiteralPath $RetainedRunDirectory -Directory)) {
        $batchPath = Join-Path $retainedBatchDirectory.FullName 'source-records.json'
        $responsePath = Join-Path $retainedBatchDirectory.FullName 'response.json'
        if (-not (Test-Path -LiteralPath $batchPath -PathType Leaf) -or -not (Test-Path -LiteralPath $responsePath -PathType Leaf)) {
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
Read the source assessment contract, source record batch, Hosted instruction catalog, protected rules catalog, and output schema from the current batch directory before evaluating the batch.

Source assessment contract: SourceAssessment-v4.md
Source record batch: source-records.json
Hosted instruction catalog: hosted-instruction-catalog.json
Protected rules catalog: protected-rules.json
Output schema: source-assessment-draft.schema.json

This batch contains exactly $SourceCount source records. Write only the requested JSON object in your final response.
When a source record contains `requiredAssessmentIds`, include every listed ID exactly once in that entry's assessments.
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
        $assessmentIds = @($entry.assessments | ForEach-Object { [string]$_.assessmentId })
        $requiredAssessmentIds = if ($expectedByKey[$key].PSObject.Properties['requiredAssessmentIds']) { @($expectedByKey[$key].requiredAssessmentIds) } else { @() }
        foreach ($requiredAssessmentId in $requiredAssessmentIds) {
            if ([string]$requiredAssessmentId -notin $assessmentIds) {
                throw "Evaluator omitted required assessment ID in $BatchId`: $key`: $requiredAssessmentId"
            }
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
$resolvedResumeRunDirectory = if ([string]::IsNullOrWhiteSpace($ResumeRunDirectory)) { $null } else { [IO.Path]::GetFullPath($ResumeRunDirectory) }
if ($null -ne $resolvedResumeRunDirectory) {
    if ($resolvedResumeRunDirectory.StartsWith($repositoryPrefix, [StringComparison]::OrdinalIgnoreCase)) {
        throw 'ResumeRunDirectory must be outside the repository root'
    }
    if (-not (Test-Path -LiteralPath $resolvedResumeRunDirectory -PathType Container)) {
        throw "ResumeRunDirectory was not found: $resolvedResumeRunDirectory"
    }
}

$resolvedBuilderPath = [IO.Path]::GetFullPath($BaselineBuilderPath)
$resolvedCatalogPath = [IO.Path]::GetFullPath($HostedCatalogPath)
$resolvedProtectedRulesPath = [IO.Path]::GetFullPath($ProtectedRulesPath)
$resolvedContractPath = [IO.Path]::GetFullPath($AssessmentContractPath)
$inventorySchemaPath = Join-Path $resolvedRepositoryRoot 'hosted_copilot/copilot-rule-catalog/source-inventories/source-inventory.schema.json'
$definitionSchemaPath = Join-Path $resolvedRepositoryRoot 'hosted_copilot/copilot-rule-catalog/source-definitions/source-definition.schema.json'
$draftSchemaPath = Join-Path $resolvedRepositoryRoot 'hosted_copilot/copilot-rule-catalog/rule-assessments/source-assessment-draft.schema.json'
$promptPath = Join-Path $resolvedRepositoryRoot 'hosted_copilot/tools/assessment-prompts/SourceAssessment-v4.md'
$runDirectory = Join-Path ([IO.Path]::GetTempPath()) ('hosted-source-assessment/' + [guid]::NewGuid().ToString('N'))
$managedRunRootPrefix = [IO.Path]::GetFullPath((Join-Path ([IO.Path]::GetTempPath()) 'hosted-source-assessment')).TrimEnd([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar) + [IO.Path]::DirectorySeparatorChar
$runRepositoryRoot = Join-Path $runDirectory 'repository'
foreach ($requiredPath in @($resolvedBuilderPath, $resolvedCatalogPath, $resolvedProtectedRulesPath, $resolvedContractPath, $inventorySchemaPath, $definitionSchemaPath, $draftSchemaPath, $promptPath)) {
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
    'hosted_copilot/copilot-rule-catalog/instruction-catalog.schema.json',
    'hosted_copilot/copilot-rule-catalog/protected-rules.schema.json'
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
$resolvedProtectedRulesPath = Copy-RunInputFile -SourcePath $resolvedProtectedRulesPath -DestinationPath (Join-Path $runRepositoryRoot 'hosted_copilot/copilot-rule-catalog/protected-rules.json')
$resolvedContractPath = $assessmentContractSnapshotPath
$inventorySchemaPath = Join-Path $runRepositoryRoot 'hosted_copilot/copilot-rule-catalog/source-inventories/source-inventory.schema.json'
$definitionSchemaPath = Join-Path $runRepositoryRoot 'hosted_copilot/copilot-rule-catalog/source-definitions/source-definition.schema.json'
$draftSchemaPath = Join-Path $runRepositoryRoot 'hosted_copilot/copilot-rule-catalog/rule-assessments/source-assessment-draft.schema.json'
$catalogSchemaPath = Join-Path $runRepositoryRoot 'hosted_copilot/copilot-rule-catalog/instruction-catalog.schema.json'
$protectedRulesSchemaPath = Join-Path $runRepositoryRoot 'hosted_copilot/copilot-rule-catalog/protected-rules.schema.json'
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
$protectedRulesJson = Get-Content -LiteralPath $resolvedProtectedRulesPath -Raw
if (-not (Test-Json -Json $protectedRulesJson -SchemaFile $protectedRulesSchemaPath -ErrorAction Stop)) {
    throw "Protected rules catalog does not satisfy its schema: $resolvedProtectedRulesPath"
}
$protectedRules = $protectedRulesJson | ConvertFrom-Json
$knownHostedRuleIds = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
foreach ($rule in @($catalog.rules)) {
    $null = $knownHostedRuleIds.Add([string]$rule.id)
}
foreach ($rule in @($protectedRules.rules)) {
    if (-not $knownHostedRuleIds.Add([string]$rule.id)) {
        throw "Protected rule ID collides with lifecycle-managed catalog rule: $($rule.id)"
    }
}
$canonicalMappingsBySource = @{}
foreach ($mappingProperty in @($catalog.canonicalCandidateMappings.PSObject.Properties)) {
    $mapping = $mappingProperty.Value
    $sourceKey = [string]$mapping.sourceDefinitionId + [char]0 + [string]$mapping.sourceId
    if (-not $canonicalMappingsBySource.ContainsKey($sourceKey)) {
        $canonicalMappingsBySource[$sourceKey] = [Collections.Generic.List[object]]::new()
    }
    $canonicalMappingsBySource[$sourceKey].Add([pscustomobject]@{
        HostedRuleId = [string]$mappingProperty.Name
        AssessmentId = if ($mapping.PSObject.Properties['assessmentId']) { [string]$mapping.assessmentId } else { $null }
    })
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
        $sourceKey = $sourceDefinitionId + [char]0 + [string]$record.sourceId
        [string[]]$mappedHostedRuleIds = if ($canonicalMappingsBySource.ContainsKey($sourceKey)) {
            @($canonicalMappingsBySource[$sourceKey] | ForEach-Object { $_.HostedRuleId } | Sort-Object -Unique)
        }
        else {
            @()
        }
        $priorSourceEvidence = if ($null -eq $priorInventory) {
            $null
        }
        else {
            Get-PriorSourceInventoryEvidence -PriorInventory $priorInventory -SourceId ([string]$record.sourceId) -CurrentRecord $record
        }
        $packetRecord = [ordered]@{
            sourceRef = [ordered]@{
                sourceDefinitionId = $sourceDefinitionId
                sourceId = [string]$record.sourceId
                contentSha256 = [string]$record.contentSha256
            }
            sourceRecord = $record
            priorSourceEvidence = $priorSourceEvidence
            mappedHostedRuleIds = $mappedHostedRuleIds
        }
        [string[]]$requiredAssessmentIds = if ($canonicalMappingsBySource.ContainsKey($sourceKey)) {
            @($canonicalMappingsBySource[$sourceKey] | Where-Object { $null -ne $_.AssessmentId } | ForEach-Object { [string]$_.AssessmentId } | Sort-Object -Unique)
        }
        else {
            @()
        }
        if (@($requiredAssessmentIds).Count -gt 0) {
            $packetRecord['requiredAssessmentIds'] = $requiredAssessmentIds
        }
        $packetRecord
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
foreach ($path in @($resolvedCatalogPath, $resolvedProtectedRulesPath, $draftSchemaPath, $promptPath)) {
    $staticEvaluatorInputBytes += [IO.File]::ReadAllBytes($path).Length
}
$draftEntries = [Collections.Generic.List[object]]::new()
$cachedSourceCount = 0
$recoveredSourceCount = 0
$evaluatedSourceCount = 0
$sourceCachePath = Join-Path $resolvedCacheDirectory 'assessment-cache.json'
$sourceCacheEntries = Invoke-WithExclusiveFileLock -Path ($sourceCachePath + '.lock') -Operation {
    param($LedgerPath, $ReportSkipped)

    Read-AssessmentCacheLedger -Path $LedgerPath -ShowProgress:$ReportSkipped
} -ArgumentList @($sourceCachePath, ($OutputFormat -eq 'Text' -or $ShowProgress))
$retainedEntries = if ($null -eq $resolvedResumeRunDirectory) {
    @{}
}
else {
    Get-RetainedAssessmentEntries -RetainedRunDirectory $resolvedResumeRunDirectory -CurrentDraftSchemaPath $draftSchemaPath -KnownHostedRuleIds $knownHostedRuleIds
}
if ($null -ne $resolvedResumeRunDirectory -and $retainedEntries.Count -eq 0) {
    throw 'Assessment recovery directory is incompatible with the current run. Rerun without -AssessmentResumeDirectory to use validated cache entries.'
}
$pendingLanes = [Collections.Generic.List[object]]::new()
foreach ($lane in $orderedLanes) {
    $pendingRecords = [Collections.Generic.List[object]]::new()
    foreach ($record in @($lane.records)) {
        $sourceKey = "$($record.sourceRef.sourceDefinitionId):$($record.sourceRef.sourceId)"
        $cacheEntry = if ($sourceCacheEntries.ContainsKey($sourceKey)) { $sourceCacheEntries[$sourceKey] } else { $null }
        $entry = Read-AssessmentSourceCache -CacheEntry $cacheEntry -ExpectedRecord $record -Context "cached $sourceKey" -AssessmentCardinality ([string]$lane.assessmentCardinality) -KnownHostedRuleIds $knownHostedRuleIds -DraftSchemaPath $draftSchemaPath -ShowProgress:($OutputFormat -eq 'Text' -or $ShowProgress)
        if ($null -ne $entry) {
            $draftEntries.Add($entry)
            $cachedSourceCount++
            continue
        }
        if ($retainedEntries.ContainsKey($sourceKey)) {
            $retained = $retainedEntries[$sourceKey]
            if ([string]$retained.AssessmentCardinality -ceq [string]$lane.assessmentCardinality -and [string]$retained.Record.sourceRef.contentSha256 -ceq [string]$record.sourceRef.contentSha256) {
                Test-AssessmentResponseEntry -Entry $retained.Entry -ExpectedRecord $record -Context "recovered $sourceKey" -AssessmentCardinality ([string]$lane.assessmentCardinality) -KnownHostedRuleIds $knownHostedRuleIds -DraftSchemaPath $draftSchemaPath
                $cacheUpdate = [ordered]@{ sourceDefinitionId = [string]$record.sourceRef.sourceDefinitionId; sourceId = [string]$record.sourceRef.sourceId; contentSha256 = [string]$record.sourceRef.contentSha256; result = $retained.Entry }
                $sourceCacheEntries = Write-AssessmentCacheLedger -Path $sourceCachePath -UpdatedEntries @($cacheUpdate)
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

if ($OutputFormat -eq 'Text' -or $ShowProgress) {
    [long]$pendingPayloadBytes = 0
    foreach ($batch in $batches) {
        $pendingPayloadBytes += [long]$batch.payloadSizeBytes
    }
    $totalSourceCount = [int]$orderedLanes.records.Count
    $pendingSourceCount = $totalSourceCount - $cachedSourceCount - $recoveredSourceCount
    $initialEstimate = Get-EstimatedRemainingMilliseconds -CompletedPayloadBytes 0 -CompletedElapsedMilliseconds 0 -RemainingPayloadBytes $pendingPayloadBytes -MaxParallelBatches $MaxParallelBatches -BootstrapBytesPerSecondPerWorker $sourceAssessmentBootstrapBytesPerSecondPerWorker
    Write-Host ''
    Write-Host ("  Sources   : {0} total | {1} cached | {2} recovered | {3} pending" -f $totalSourceCount, $cachedSourceCount, $recoveredSourceCount, $pendingSourceCount)
    Write-Host ("  Batches   : {0} pending" -f $batches.Count)
    Write-Host ("  Workers   : {0}" -f $MaxParallelBatches)
    Write-Host ("  Payload   : {0}" -f (Format-ByteSize -Bytes $pendingPayloadBytes))
    Write-Host ("  Estimated : {0}" -f (Format-ElapsedDuration -Milliseconds $initialEstimate))
    Write-Host ''
}

$evaluatorCommandPath = $null
if ([string]::IsNullOrWhiteSpace($EvaluatorScriptPath)) {
    $command = Get-Command $EvaluatorCommand -ErrorAction SilentlyContinue
    if ($null -eq $command) {
        throw "Evaluator command was not found: $EvaluatorCommand"
    }
    $evaluatorCommandPath = $command.Source
}

$evaluatedBatchCount = 0
$succeeded = $false
try {
    $null = New-Item -ItemType Directory -Path $runDirectory -Force
    $preparedBatches = [Collections.Generic.List[object]]::new()
    $batchById = @{}
    foreach ($batch in $batches) {
        $batchNumber = $preparedBatches.Count + 1
        $batchId = [string]$batch.batchId
        $batchPacket = $batch.packet
        $batchDirectory = Join-Path $runDirectory $batchId
        $null = New-Item -ItemType Directory -Path $batchDirectory -Force
        $batchPath = Join-Path $batchDirectory 'source-records.json'
        $catalogPath = Join-Path $batchDirectory 'hosted-instruction-catalog.json'
        $protectedRulesPath = Join-Path $batchDirectory 'protected-rules.json'
        $schemaPath = Join-Path $batchDirectory 'source-assessment-draft.schema.json'
        $batchPromptPath = Join-Path $batchDirectory 'SourceAssessment-v4.md'
        $responsePath = Join-Path $batchDirectory 'response.json'
        Copy-Item -LiteralPath $resolvedCatalogPath -Destination $catalogPath
        Copy-Item -LiteralPath $resolvedProtectedRulesPath -Destination $protectedRulesPath
        Copy-Item -LiteralPath $draftSchemaPath -Destination $schemaPath
        Copy-Item -LiteralPath $promptPath -Destination $batchPromptPath
        Write-JsonAtomically -Path $batchPath -Value $batchPacket
        $prepared = [pscustomobject]@{
            BatchNumber = $batchNumber
            BatchCount = $batches.Count
            BatchId = $batchId
            Packet = $batchPacket
            PayloadSizeBytes = [int]$batch.payloadSizeBytes
            Directory = $batchDirectory
            BatchPath = $batchPath
            CatalogPath = $catalogPath
            ProtectedRulesPath = $protectedRulesPath
            SchemaPath = $schemaPath
            PromptPath = $batchPromptPath
            ResponsePath = $responsePath
            AttemptPrompt = New-EvaluatorAttemptPrompt -SourceCount @($batchPacket.records).Count
        }
        $preparedBatches.Add($prepared)
        $batchById[$batchId] = $prepared
    }

    $validatedResponses = @{}
    $failureByBatch = @{}
    $completedBatchIds = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    [long]$completedPayloadBytes = 0
    [long]$completedElapsedMilliseconds = 0
    $pendingBatches = @($preparedBatches)
    for ($attempt = 1; $attempt -le ($MaxRetries + 1) -and $pendingBatches.Count -gt 0; $attempt++) {
        if ($attempt -gt 1 -and $RetryDelayMilliseconds -gt 0) {
            $delayMilliseconds = Get-SourceEvidenceRetryDelayMilliseconds -Attempt ($attempt - 1) -BaseDelayMilliseconds $RetryDelayMilliseconds
            if ($delayMilliseconds -gt 0) {
                Start-Sleep -Milliseconds $delayMilliseconds
            }
        }
        $retryBatches = [Collections.Generic.List[object]]::new()
        $workerEvaluatorScriptPath = $resolvedEvaluatorScriptPath
        $workerEvaluatorCommandPath = $evaluatorCommandPath
        $workerModel = $Model
        $workerReasoningEffort = $ReasoningEffort
        $workerAttempt = $attempt
        $workerAttemptCount = $MaxRetries + 1
        $pendingBatches | ForEach-Object -Parallel {
            $batch = $_
            [pscustomobject]@{
                Kind = 'started'
                BatchNumber = [int]$batch.BatchNumber
                BatchCount = [int]$batch.BatchCount
                BatchId = [string]$batch.BatchId
                SourceCount = @($batch.Packet.records).Count
                PayloadSizeBytes = [int]$batch.PayloadSizeBytes
                Attempt = $using:workerAttempt
                AttemptCount = $using:workerAttemptCount
            }
            $stopwatch = [Diagnostics.Stopwatch]::StartNew()
            $evaluatorOutput = @()
            $evaluatorExitCode = 0
            $failureKind = 'execution'
            try {
                if ($null -ne $using:workerEvaluatorScriptPath) {
                    $evaluatorOutput = @(& pwsh -NoProfile -File $using:workerEvaluatorScriptPath -BatchPath $batch.BatchPath -CatalogPath $batch.CatalogPath -SchemaPath $batch.SchemaPath -PromptPath $batch.PromptPath -OutputPath $batch.ResponsePath -Model $using:workerModel -ReasoningEffort $using:workerReasoningEffort 2>&1)
                    if ($LASTEXITCODE -ne 0) {
                        throw "Evaluator script failed: $(($evaluatorOutput | Out-String).Trim())"
                    }
                }
                else {
                    $evaluatorOutput = @(& $using:workerEvaluatorCommandPath -C $batch.Directory -p $batch.AttemptPrompt --no-color --stream off --no-custom-instructions --no-ask-user --disable-builtin-mcps --no-auto-update --disallow-temp-dir --model $using:workerModel --effort $using:workerReasoningEffort --available-tools=view --output-format json 2>&1)
                    $evaluatorExitCode = $LASTEXITCODE
                    if ($evaluatorExitCode -ne 0) {
                        $failureKind = 'copilot-exit'
                        throw "Copilot evaluator exited with code $evaluatorExitCode"
                    }
                }
                [pscustomobject]@{
                    Kind = 'completed'
                    BatchId = [string]$batch.BatchId
                    Succeeded = $true
                    ElapsedMilliseconds = [long]$stopwatch.ElapsedMilliseconds
                    ExitCode = 0
                    FailureKind = ''
                    Output = @($evaluatorOutput | ForEach-Object { [string]$_ })
                    Error = ''
                }
            }
            catch {
                [pscustomobject]@{
                    Kind = 'completed'
                    BatchId = [string]$batch.BatchId
                    Succeeded = $false
                    ElapsedMilliseconds = [long]$stopwatch.ElapsedMilliseconds
                    ExitCode = [int]$evaluatorExitCode
                    FailureKind = $failureKind
                    Output = @($evaluatorOutput | ForEach-Object { [string]$_ })
                    Error = [string]$_.Exception.Message
                }
            }
        } -ThrottleLimit $MaxParallelBatches | ForEach-Object {
            $workerResult = $_
            $batch = $batchById[[string]$workerResult.BatchId]
            if ([string]$workerResult.Kind -ceq 'started') {
                if (($OutputFormat -eq 'Text' -or $ShowProgress) -and [int]$workerResult.Attempt -eq 1) {
                    Write-Host (Format-ValidationStatusLine -Status 'running' -Name "source-assessment $($workerResult.BatchNumber)/$($workerResult.BatchCount)" -Detail ("{0} ({1} sources)" -f $workerResult.BatchId, $workerResult.SourceCount) -NameWidth 42)
                }
                return
            }
            try {
                if (-not [bool]$workerResult.Succeeded) {
                    if ([string]$workerResult.FailureKind -ceq 'copilot-exit') {
                        throw (Get-EvaluatorFailureMessage -EvaluatorName 'Copilot evaluator' -ExitCode ([int]$workerResult.ExitCode) -Output @($workerResult.Output))
                    }
                    throw [string]$workerResult.Error
                }
                if ($null -eq $resolvedEvaluatorScriptPath) {
                    $assistantMessages = [Collections.Generic.List[object]]::new()
                    foreach ($eventLine in @($workerResult.Output)) {
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
                    [IO.File]::WriteAllText($batch.ResponsePath, $evaluatorJson + "`n", [Text.UTF8Encoding]::new($false))
                }
                $responseJson = Get-Content -LiteralPath $batch.ResponsePath -Raw
                try {
                    $validResponse = Test-Json -Json $responseJson -SchemaFile $draftSchemaPath -ErrorAction Stop
                }
                catch {
                    throw "Evaluator response does not satisfy the source assessment draft: $($batch.BatchId)"
                }
                if (-not $validResponse) {
                    throw "Evaluator response does not satisfy the source assessment draft: $($batch.BatchId)"
                }
                $response = $responseJson | ConvertFrom-Json
                Assert-BatchResponse -Response $response -ExpectedRecords @($batch.Packet.records) -BatchId $batch.BatchId -AssessmentCardinality ([string]$batch.Packet.assessmentCardinality) -KnownHostedRuleIds $knownHostedRuleIds
                $cacheUpdates = [Collections.Generic.List[object]]::new()
                foreach ($entry in @($response.entries)) {
                    $cacheUpdates.Add([ordered]@{ sourceDefinitionId = [string]$entry.sourceRef.sourceDefinitionId; sourceId = [string]$entry.sourceRef.sourceId; contentSha256 = [string]$entry.sourceRef.contentSha256; result = $entry })
                }
                $sourceCacheEntries = Write-AssessmentCacheLedger -Path $sourceCachePath -UpdatedEntries $cacheUpdates.ToArray()
                $validatedResponses[$batch.BatchId] = $response
                $failureByBatch.Remove($batch.BatchId)
                $evaluatedBatchCount++
                $null = $completedBatchIds.Add([string]$batch.BatchId)
                $completedPayloadBytes += [long]$batch.PayloadSizeBytes
                $completedElapsedMilliseconds += [long]$workerResult.ElapsedMilliseconds
                [long]$remainingPayloadBytes = 0
                foreach ($remainingBatch in @($preparedBatches | Where-Object { -not $completedBatchIds.Contains([string]$_.BatchId) })) {
                    $remainingPayloadBytes += [long]$remainingBatch.PayloadSizeBytes
                }
                $estimatedRemainingMilliseconds = Get-EstimatedRemainingMilliseconds -CompletedPayloadBytes $completedPayloadBytes -CompletedElapsedMilliseconds $completedElapsedMilliseconds -RemainingPayloadBytes $remainingPayloadBytes -MaxParallelBatches $MaxParallelBatches -BootstrapBytesPerSecondPerWorker $sourceAssessmentBootstrapBytesPerSecondPerWorker
                if ($OutputFormat -eq 'Text' -or $ShowProgress) {
                    Write-Host (Format-ValidationStatusLine -Status 'passed' -Name "source-assessment $($batch.BatchNumber)/$($batch.BatchCount)" -Detail ("Total Elapsed {0} : [Batch: {1}] : [Remaining: {2}]" -f (Format-ElapsedDuration -Milliseconds ([long]$sourceAssessmentStopwatch.ElapsedMilliseconds)), (Format-ElapsedDuration -Milliseconds ([long]$workerResult.ElapsedMilliseconds)), (Format-ElapsedDuration -Milliseconds $estimatedRemainingMilliseconds)) -NameWidth 42)
                }
            }
            catch {
                Remove-Item -LiteralPath $batch.ResponsePath -Force -ErrorAction SilentlyContinue
                $failureByBatch[$batch.BatchId] = [string]$_.Exception.Message
                $retryBatches.Add($batch)
                if ($OutputFormat -eq 'Text' -or $ShowProgress) {
                    foreach ($diagnosticLine in @(Format-IndentedDiagnostic -Label ("[ERROR] Batch {0}/{1}:" -f $batch.BatchNumber, $batch.BatchCount) -Message ([string]$_.Exception.Message))) {
                        Write-Host $diagnosticLine
                    }
                    $completedPayloadBytes += [long]$batch.PayloadSizeBytes
                    $completedElapsedMilliseconds += [long]$workerResult.ElapsedMilliseconds
                    [long]$remainingPayloadBytes = 0
                    foreach ($remainingBatch in @($preparedBatches | Where-Object { -not $completedBatchIds.Contains([string]$_.BatchId) })) {
                        $remainingPayloadBytes += [long]$remainingBatch.PayloadSizeBytes
                    }
                    $estimatedRemainingMilliseconds = Get-EstimatedRemainingMilliseconds -CompletedPayloadBytes $completedPayloadBytes -CompletedElapsedMilliseconds $completedElapsedMilliseconds -RemainingPayloadBytes $remainingPayloadBytes -MaxParallelBatches $MaxParallelBatches -BootstrapBytesPerSecondPerWorker $sourceAssessmentBootstrapBytesPerSecondPerWorker
                    $failureStatus = if ($attempt -le $MaxRetries) { 'retrying' } else { 'failed' }
                    $failureDetail = if ($attempt -le $MaxRetries) {
                        "Total Elapsed {0} : [Batch: {1}] : [Remaining: {2}]" -f (Format-ElapsedDuration -Milliseconds ([long]$sourceAssessmentStopwatch.ElapsedMilliseconds)), (Format-ElapsedDuration -Milliseconds ([long]$workerResult.ElapsedMilliseconds)), (Format-ElapsedDuration -Milliseconds $estimatedRemainingMilliseconds)
                    }
                    else {
                        "Total Elapsed {0} : [Batch: {1}]" -f (Format-ElapsedDuration -Milliseconds ([long]$sourceAssessmentStopwatch.ElapsedMilliseconds)), (Format-ElapsedDuration -Milliseconds ([long]$workerResult.ElapsedMilliseconds))
                    }
                    Write-Host (Format-ValidationStatusLine -Status $failureStatus -Name "source-assessment $($batch.BatchNumber)/$($batch.BatchCount)" -Detail $failureDetail -NameWidth 42)
                }
            }
        }
        $pendingBatches = @($retryBatches)
    }
    if ($pendingBatches.Count -gt 0) {
        $failedBatch = @($preparedBatches | Where-Object { $failureByBatch.ContainsKey($_.BatchId) })[0]
        throw "Source assessment $($failedBatch.BatchId) failed after $($MaxRetries + 1) attempts: $($failureByBatch[$failedBatch.BatchId])"
    }

    foreach ($batch in $preparedBatches) {
        $response = $validatedResponses[$batch.BatchId]
        foreach ($entry in @($response.entries)) {
            $draftEntries.Add($entry)
            $evaluatedSourceCount++
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
        ProtectedRulesPath = $resolvedProtectedRulesPath
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
