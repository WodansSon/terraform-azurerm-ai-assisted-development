[CmdletBinding()]
param(
    [string]$SourceCatalogPath = (Join-Path $PSScriptRoot '../../copilot-rule-catalog/instruction-catalog.json'),

    [string]$OutputPath = (Join-Path $PSScriptRoot '../../copilot-rule-catalog/instruction-catalog-v4.json'),

    [switch]$Write,

    [ValidateSet('Text', 'Json')]
    [string]$OutputFormat = 'Text'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$acceptedCatalogCommit = '97b08a2a80ed6ca23e7a6ce5d17b878f70c20bbc'
$sourceDefinitionId = 'contributor-guidance'
$migrationRationale = 'Migrated from the accepted legacy sourceIds catalog relationship.'
$resolvedSourceCatalogPath = [IO.Path]::GetFullPath($SourceCatalogPath)
$resolvedOutputPath = [IO.Path]::GetFullPath($OutputPath)
$catalogRoot = Split-Path -Parent $resolvedSourceCatalogPath
$sourceSchemaPath = Join-Path $catalogRoot 'instruction-catalog.schema.json'
$targetSchemaPath = Join-Path $catalogRoot 'instruction-catalog-v4.schema.json'
$helpersPath = Join-Path $PSScriptRoot '../modules/shared/HostedToolkit.Helpers.psm1'

Import-Module -Name $helpersPath -Force

foreach ($requiredPath in @($resolvedSourceCatalogPath, $sourceSchemaPath, $targetSchemaPath)) {
    if (-not (Test-Path -LiteralPath $requiredPath -PathType Leaf)) {
        throw "Required catalog transformation input was not found: $requiredPath"
    }
}

$sourceContent = Get-Content -LiteralPath $resolvedSourceCatalogPath -Raw
if (-not ($sourceContent | Test-Json -SchemaFile $sourceSchemaPath -ErrorAction Stop)) {
    throw 'Source instruction catalog schema validation failed'
}
$sourceCatalog = $sourceContent | ConvertFrom-Json -DateKind String

$git = Get-Command git -ErrorAction Stop
$acceptedCommitTimestamp = @(& $git.Source -C (Join-Path $PSScriptRoot '../../..') show -s --format=%cI $acceptedCatalogCommit)
if ($LASTEXITCODE -ne 0 -or $acceptedCommitTimestamp.Count -ne 1) {
    throw "Could not resolve accepted catalog commit timestamp: $acceptedCatalogCommit"
}
$acceptedAt = ConvertTo-UtcTimestamp -Value ([string]$acceptedCommitTimestamp[0])

$knownSourceIds = @{}
foreach ($source in @($sourceCatalog.sources)) {
    $sourceId = [string]$source.id
    if ($knownSourceIds.ContainsKey($sourceId)) {
        throw "Source catalog contains duplicate source ID: $sourceId"
    }
    $knownSourceIds[$sourceId] = $true
}

$transformedRules = [Collections.Generic.List[object]]::new()
$sourceRelationships = [Collections.Generic.List[object]]::new()
$relationshipKeys = @{}

foreach ($rule in @($sourceCatalog.rules)) {
    $transformedRule = [ordered]@{}
    foreach ($property in $rule.PSObject.Properties) {
        if ($property.Name -cne 'sourceIds') {
            $transformedRule[$property.Name] = $property.Value
        }
    }
    $transformedRules.Add($transformedRule)

    foreach ($legacySourceId in @($rule.sourceIds)) {
        $sourceId = [string]$legacySourceId
        if (-not $knownSourceIds.ContainsKey($sourceId)) {
            throw "Rule $($rule.id) references unknown legacy source ID: $sourceId"
        }
        $relationshipKey = "$sourceDefinitionId`0$sourceId`0$($rule.id)"
        if ($relationshipKeys.ContainsKey($relationshipKey)) {
            throw "Legacy catalog contains duplicate source relationship: $sourceId -> $($rule.id)"
        }
        $relationshipKeys[$relationshipKey] = $true
        $sourceRelationships.Add([ordered]@{
            sourceRef = [ordered]@{
                sourceDefinitionId = $sourceDefinitionId
                sourceId = $sourceId
            }
            hostedRuleId = [string]$rule.id
            status = 'active'
            relationshipKind = 'supports'
            assessmentEvidenceRefs = @()
            rationale = $migrationRationale
            acceptedAt = $acceptedAt
            history = @()
        })
    }
}

$targetCatalog = [ordered]@{}
foreach ($property in $sourceCatalog.PSObject.Properties) {
    switch -CaseSensitive ($property.Name) {
        '$schema' { $targetCatalog[$property.Name] = 'instruction-catalog-v4.schema.json' }
        'schemaVersion' { $targetCatalog[$property.Name] = 4 }
        'rules' { $targetCatalog[$property.Name] = $transformedRules.ToArray() }
        default { $targetCatalog[$property.Name] = $property.Value }
    }
}
$targetCatalog['sourceRelationships'] = $sourceRelationships.ToArray()

$targetJson = ($targetCatalog | ConvertTo-Json -Depth 100) + "`n"
if (-not ($targetJson | Test-Json -SchemaFile $targetSchemaPath -ErrorAction Stop)) {
    throw 'Transformed instruction catalog schema validation failed'
}

$expectedSha256 = Get-Sha256 -Content $targetJson
$fresh = $false
if (Test-Path -LiteralPath $resolvedOutputPath -PathType Leaf) {
    $fresh = (Get-FileHash -LiteralPath $resolvedOutputPath -Algorithm SHA256).Hash.ToLowerInvariant() -ceq $expectedSha256
}
if ($Write -and -not $fresh) {
    $outputDirectory = Split-Path -Parent $resolvedOutputPath
    if (-not (Test-Path -LiteralPath $outputDirectory -PathType Container)) {
        $null = New-Item -ItemType Directory -Path $outputDirectory -Force
    }
    [IO.File]::WriteAllText($resolvedOutputPath, $targetJson, [Text.UTF8Encoding]::new($false))
    $fresh = $true
}

$result = [ordered]@{
    status = if ($fresh) { 'fresh' } else { 'stale' }
    mode = if ($Write) { 'write' } else { 'check' }
    sourceCatalogPath = $resolvedSourceCatalogPath
    outputPath = $resolvedOutputPath
    acceptedCatalogCommit = $acceptedCatalogCommit
    acceptedAt = $acceptedAt
    ruleCount = $transformedRules.Count
    relationshipCount = $sourceRelationships.Count
    sha256 = $expectedSha256
}

if ($OutputFormat -eq 'Json') {
    $result | ConvertTo-Json -Depth 5
}
else {
    Write-Output 'Hosted version 4 catalog transformation'
    Write-Output "  Mode          : $($result.mode.ToUpperInvariant())"
    Write-Output "  Status        : $($result.status.ToUpperInvariant())"
    Write-Output "  Rules         : $($result.ruleCount)"
    Write-Output "  Relationships : $($result.relationshipCount)"
    Write-Output "  SHA-256       : $($result.sha256)"
}

if (-not $fresh) {
    throw 'Transformed Hosted version 4 catalog is stale; rerun with -Write after reviewing the transformation'
}
