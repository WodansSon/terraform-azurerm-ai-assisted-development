[CmdletBinding()]
param(
    [string]$RepositoryRoot = (Join-Path $PSScriptRoot '../..'),

    [Parameter(Mandatory = $true)]
    [string[]]$InventoryPaths,

    [Parameter(Mandatory = $true)]
    [string]$AssessmentDraftPath,

    [string]$HostedCatalogPath = (Join-Path $PSScriptRoot '../copilot-rule-catalog/instruction-catalog.json'),

    [string]$AssessmentContractPath = (Join-Path $PSScriptRoot '../copilot-rule-catalog/rule-assessments/source-assessment-v2.json'),

    [Parameter(Mandatory = $true)]
    [string]$OutputPath,

    [string]$Model = 'gpt-5.4',

    [ValidateSet('low', 'medium', 'high', 'xhigh')]
    [string]$ReasoningEffort = 'high',

    [ValidateRange(1024, 10485760)]
    [int]$EvaluatorPayloadBudgetBytes = 393216,

    [string]$Evaluator = 'copilot',

    [object]$GeneratedAt = [DateTime]::UtcNow,

    [ValidateSet('Text', 'Json')]
    [string]$OutputFormat = 'Text'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$sourceEvidenceModulePath = Join-Path $PSScriptRoot 'SourceEvidenceValidation.psm1'
Import-Module -Name $sourceEvidenceModulePath -Force
$helpersPath = Join-Path $PSScriptRoot 'HostedToolkit.Helpers.psm1'
Import-Module -Name $helpersPath -Force

function Test-JsonFile {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$SchemaPath
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "Required assessment input was not found: $Path"
    }
    $snapshot = Get-FileSnapshot -Path $Path
    try {
        $valid = Test-Json -Json $snapshot.Content -SchemaFile $SchemaPath -ErrorAction Stop
    }
    catch {
        throw "Assessment input does not satisfy its schema: $Path"
    }
    if (-not $valid) {
        throw "Assessment input does not satisfy its schema: $Path"
    }
    return [pscustomobject]@{
        Value = $snapshot.Content | ConvertFrom-Json -DateKind String
        Snapshot = $snapshot
    }
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

$resolvedRepositoryRoot = [IO.Path]::GetFullPath($RepositoryRoot).TrimEnd([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar)
$repositoryPrefix = $resolvedRepositoryRoot + [IO.Path]::DirectorySeparatorChar
$resolvedOutputPath = [IO.Path]::GetFullPath($OutputPath)
if ($resolvedOutputPath.StartsWith($repositoryPrefix, [StringComparison]::OrdinalIgnoreCase)) {
    throw 'Source assessment baseline output must be outside the repository root'
}
if ([string]::IsNullOrWhiteSpace($Model) -or [string]::IsNullOrWhiteSpace($Evaluator)) {
    throw 'Model and Evaluator cannot be empty'
}

$assessmentRoot = Join-Path $resolvedRepositoryRoot 'hosted_copilot/copilot-rule-catalog/rule-assessments'
$inventorySchemaPath = Join-Path $resolvedRepositoryRoot 'hosted_copilot/copilot-rule-catalog/source-inventories/source-inventory.schema.json'
$definitionSchemaPath = Join-Path $resolvedRepositoryRoot 'hosted_copilot/copilot-rule-catalog/source-definitions/source-definition.schema.json'
$baselineSchemaPath = Join-Path $assessmentRoot 'source-assessment-baseline.schema.json'
$draftSchemaPath = Join-Path $assessmentRoot 'source-assessment-draft.schema.json'
$contractSchemaPath = Join-Path $assessmentRoot 'assessment-contract.schema.json'
$catalogSchemaPath = Join-Path (Split-Path -Parent ([IO.Path]::GetFullPath($HostedCatalogPath))) 'instruction-catalog.schema.json'
$contractInput = Test-JsonFile -Path ([IO.Path]::GetFullPath($AssessmentContractPath)) -SchemaPath $contractSchemaPath
$contract = $contractInput.Value
$assessmentContractSha256 = Get-SourceAssessmentContractSha256 -Contract $contract -RepositoryRoot $resolvedRepositoryRoot
$hostedCatalogInput = Test-JsonFile -Path ([IO.Path]::GetFullPath($HostedCatalogPath)) -SchemaPath $catalogSchemaPath
$hostedCatalog = $hostedCatalogInput.Value
$knownHostedRuleIds = @{}
$hostedRulesByContributorSourceId = @{}
foreach ($rule in @($hostedCatalog.rules)) {
    $knownHostedRuleIds[[string]$rule.id] = $true
    foreach ($sourceId in @($rule.sourceIds)) {
        if (-not $hostedRulesByContributorSourceId.ContainsKey([string]$sourceId)) {
            $hostedRulesByContributorSourceId[[string]$sourceId] = [Collections.Generic.List[string]]::new()
        }
        $hostedRulesByContributorSourceId[[string]$sourceId].Add([string]$rule.id)
    }
}
$draftInput = Test-JsonFile -Path ([IO.Path]::GetFullPath($AssessmentDraftPath)) -SchemaPath $draftSchemaPath
$draft = $draftInput.Value

$inventoryHashes = [ordered]@{}
$inventoryRecords = @{}
$priorSourceEvidenceByKey = @{}
$assessmentCardinalityBySourceDefinition = @{}
$runSourceDefinitions = [Collections.Generic.List[object]]::new()
$expectedSourceDefinitionIds = @(Get-ExpectedSourceDefinitionIds -RepositoryRoot $resolvedRepositoryRoot)
foreach ($inventoryPath in $InventoryPaths) {
    $resolvedInventoryPath = [IO.Path]::GetFullPath($inventoryPath)
    $inventoryInput = Test-JsonFile -Path $resolvedInventoryPath -SchemaPath $inventorySchemaPath
    $inventory = $inventoryInput.Value
    if ($null -eq $inventory.acceptance) {
        throw "Assessment requires an accepted inventory: $resolvedInventoryPath"
    }
    $sourceDefinitionId = [string]$inventory.sourceDefinitionId
    if ($inventoryHashes.Contains($sourceDefinitionId)) {
        throw "Assessment received duplicate inventory sourceDefinitionId: $sourceDefinitionId"
    }
    $sourceEvidence = Get-CurrentSourceDefinitionEvidence -RepositoryRoot $resolvedRepositoryRoot -SourceDefinitionId $sourceDefinitionId
    Assert-CurrentAcceptedSourceInventory -Inventory $inventory -Evidence $sourceEvidence
    $assessmentCardinalityBySourceDefinition[$sourceDefinitionId] = [string]$sourceEvidence.AssessmentCardinality
    $inventoryHashes[$sourceDefinitionId] = $inventoryInput.Snapshot.Sha256
    $runSourceDefinitions.Add([ordered]@{
        sourceDefinitionId = $sourceDefinitionId
        sourceDefinitionSha256 = [string]$sourceEvidence.SourceDefinitionSha256
        parserContractSha256 = [string]$sourceEvidence.ParserContractSha256
        inventoryConfigurationSha256 = [string]$sourceEvidence.InventoryConfigurationSha256
        assessmentBatchSize = [int]$sourceEvidence.AssessmentBatchSize
        assessmentCardinality = [string]$sourceEvidence.AssessmentCardinality
    })

    foreach ($record in @($inventory.records)) {
        $key = "$sourceDefinitionId`:$($record.sourceId)"
        $priorSourceEvidenceByKey[$key] = Get-PriorAcceptedSourceEvidence -Inventory $inventory -SourceId ([string]$record.sourceId) -CurrentContentSha256 ([string]$record.contentSha256)
        if ($inventoryRecords.ContainsKey($key)) {
            throw "Accepted inventories contain duplicate source reference: $key"
        }
        $inventoryRecords[$key] = $record
    }
}

$sortedRunDefinitions = @(Get-SortedObjects -Values $runSourceDefinitions.ToArray() -Key { param($definition) $definition.sourceDefinitionId })
[string[]]$actualSourceDefinitionIds = @($sortedRunDefinitions.sourceDefinitionId)
if (@(Compare-Object $expectedSourceDefinitionIds $actualSourceDefinitionIds -SyncWindow 0).Count -ne 0) {
    throw "Source assessment requires exactly the approved source lanes: $($expectedSourceDefinitionIds -join ', ')"
}
$runConfiguration = [ordered]@{
    mode = 'evaluated'
    model = $Model
    reasoningEffort = $ReasoningEffort
    evaluator = $Evaluator
    evaluatorPayloadBudgetBytes = $EvaluatorPayloadBudgetBytes
    sourceDefinitions = $sortedRunDefinitions
}
$assessmentRunConfigurationSha256 = Get-SourceAssessmentRunConfigurationSha256 -RunConfiguration $runConfiguration

$draftEntries = @(Get-SortedObjects -Values @($draft.entries) -Key { param($entry) "$($entry.sourceRef.sourceDefinitionId):$($entry.sourceRef.sourceId)" })
$draftBySourceRef = @{}
foreach ($entry in $draftEntries) {
    $sourceDefinitionId = [string]$entry.sourceRef.sourceDefinitionId
    $sourceId = [string]$entry.sourceRef.sourceId
    $key = "$sourceDefinitionId`:$sourceId"
    if ($draftBySourceRef.ContainsKey($key)) {
        throw "Assessment draft contains duplicate source reference: $key"
    }
    if (-not $inventoryRecords.ContainsKey($key)) {
        throw "Assessment draft references a source absent from accepted inventories: $key"
    }
    if ([string]$entry.sourceRef.contentSha256 -cne [string]$inventoryRecords[$key].contentSha256) {
        throw "Assessment draft source hash does not match accepted inventory: $key"
    }
    if ($assessmentCardinalityBySourceDefinition[$sourceDefinitionId] -ceq 'exactly-one' -and @($entry.assessments).Count -ne 1) {
        throw "Assessment draft must contain exactly one assessment for $key"
    }
    [string[]]$mappedHostedRuleIds = @()
    if ($sourceDefinitionId -ceq 'contributor-guidance' -and $hostedRulesByContributorSourceId.ContainsKey($sourceId)) {
        $mappedHostedRuleIds = @($hostedRulesByContributorSourceId[$sourceId] | Sort-Object -Unique)
    }

    $assessmentIds = @{}
    foreach ($assessment in @($entry.assessments)) {
        $assessmentId = [string]$assessment.assessmentId
        if ($assessmentIds.ContainsKey($assessmentId)) {
            throw "Assessment draft contains duplicate assessmentId for $key`: $assessmentId"
        }
        $assessmentIds[$assessmentId] = $true
        if ($assessment.PSObject.Properties['assessmentProvenance']) {
            throw "Source assessment draft cannot emit assessment provenance for $key`: $assessmentId"
        }
        if ([string]$assessment.assessmentConfidence.level -ceq 'not-assessed') {
            throw "Source assessment draft must evaluate confidence for $key`: $assessmentId"
        }
        if ($null -eq $assessment.existingCoverage.score) {
            throw "Source assessment draft must score existing coverage for $key`: $assessmentId"
        }
        $priorSourceEvidence = $priorSourceEvidenceByKey[$key]
        if ($null -eq $priorSourceEvidence) {
            if ($null -ne $assessment.semanticReassessment) {
                throw "Assessment draft contains semantic reassessment without prior source evidence: $key`: $assessmentId"
            }
        }
        else {
            if ($null -eq $assessment.semanticReassessment) {
                throw "Assessment draft must classify changed source evidence: $key`: $assessmentId"
            }
            if ([string]$assessment.semanticReassessment.priorContentSha256 -cne [string]$priorSourceEvidence.sourceRef.contentSha256) {
                throw "Assessment draft prior source hash mismatch: $key`: $assessmentId"
            }
        }
        $relatedHostedRuleIds = @{}
        foreach ($coverage in @($assessment.relatedHostedCoverage)) {
            $hostedRuleId = [string]$coverage.hostedRuleId
            if (-not $knownHostedRuleIds.ContainsKey($hostedRuleId)) {
                throw "Assessment draft references unknown related Hosted coverage: $hostedRuleId"
            }
            if ($relatedHostedRuleIds.ContainsKey($hostedRuleId)) {
                throw "Assessment draft repeats related Hosted coverage for $key`: $hostedRuleId"
            }
            $relatedHostedRuleIds[$hostedRuleId] = $true
        }
        $assessment | Add-Member -NotePropertyName mappedHostedRuleIds -NotePropertyValue $mappedHostedRuleIds
        $assessment | Add-Member -NotePropertyName assessmentProvenance -NotePropertyValue ([pscustomobject][ordered]@{
            originSchemaVersion = 4
            status = 'evaluated'
            assessedAt = ConvertTo-SourceEvidenceUtcTimestamp -Value $GeneratedAt
            assessmentEvaluator = [ordered]@{
                kind = 'llm'
                identity = $Evaluator
                model = $Model
            }
        })
    }
    $entry | Add-Member -NotePropertyName priorSourceEvidence -NotePropertyValue $priorSourceEvidenceByKey[$key]
    $draftBySourceRef[$key] = $entry
}

$missingSourceRefs = @($inventoryRecords.Keys | Where-Object { -not $draftBySourceRef.ContainsKey($_) })
if ($missingSourceRefs.Count -gt 0) {
    [Array]::Sort($missingSourceRefs, [StringComparer]::Ordinal)
    throw "Assessment draft does not cover every accepted inventory record: $($missingSourceRefs -join ', ')"
}

$baseline = [ordered]@{
    '$schema' = 'source-assessment-baseline.schema.json'
    schemaVersion = 4
    generatedAt = ConvertTo-SourceEvidenceUtcTimestamp -Value $GeneratedAt
    inventoryHashes = $inventoryHashes
    hostedCatalogSha256 = $hostedCatalogInput.Snapshot.Sha256
    assessmentContractSha256 = $assessmentContractSha256
    assessmentRunConfigurationSha256 = $assessmentRunConfigurationSha256
    runConfiguration = $runConfiguration
    entries = $draftEntries
}
$baselineJson = $baseline | ConvertTo-Json -Depth 40
if (-not (Test-Json -Json $baselineJson -SchemaFile $baselineSchemaPath -ErrorAction Stop)) {
    throw 'Source assessment baseline does not satisfy its schema'
}
Write-JsonAtomically -Path $resolvedOutputPath -Value $baseline

$result = [ordered]@{
    status = 'passed'
    outputPath = $resolvedOutputPath
    sourceCount = $baseline.entries.Count
    assessmentCount = [int](@($baseline.entries | ForEach-Object { @($_.assessments).Count } | Measure-Object -Sum)[0].Sum)
    baselineSha256 = Get-Sha256 -Path $resolvedOutputPath
    assessmentContractSha256 = $assessmentContractSha256
    assessmentRunConfigurationSha256 = $assessmentRunConfigurationSha256
}
if ($OutputFormat -eq 'Json') {
    $result | ConvertTo-Json -Depth 5
}
else {
    Write-Output "Source assessment baseline generated: $($result.sourceCount) sources, $($result.assessmentCount) assessments"
    Write-Output "Output: $($result.outputPath)"
    Write-Output "Baseline SHA-256: $($result.baselineSha256)"
}
