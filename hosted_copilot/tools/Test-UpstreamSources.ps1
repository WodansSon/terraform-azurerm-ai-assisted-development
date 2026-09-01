[CmdletBinding()]
param(
    [string]$CatalogPath = (Join-Path $PSScriptRoot '../copilot-rule-catalog/instruction-catalog.json'),

    [switch]$FailOnDrift,

    [ValidateSet('Text', 'Json')]
    [string]$OutputFormat = 'Text'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$validationOutputModulePath = Join-Path $PSScriptRoot '../../tools/ValidationOutput.psm1'
Import-Module -Name $validationOutputModulePath -Force

$resolvedCatalogPath = [IO.Path]::GetFullPath($CatalogPath)
$schemaPath = Join-Path (Split-Path -Parent $resolvedCatalogPath) 'instruction-catalog.schema.json'
if (-not (Test-Path -LiteralPath $resolvedCatalogPath -PathType Leaf)) {
    throw "Instruction catalog was not found: $resolvedCatalogPath"
}
if (-not (Test-Path -LiteralPath $schemaPath -PathType Leaf)) {
    throw "Instruction catalog schema was not found: $schemaPath"
}

$catalogContent = Get-Content -LiteralPath $resolvedCatalogPath -Raw
if (-not ($catalogContent | Test-Json -SchemaFile $schemaPath)) {
    throw 'Instruction catalog schema validation failed'
}
$catalog = $catalogContent | ConvertFrom-Json

$activeSourceIds = @($catalog.rules | Where-Object status -eq 'active' | ForEach-Object { $_.sourceIds } | Sort-Object -Unique)
$sourceResults = @()
foreach ($source in @($catalog.sources | Where-Object { $_.id -in $activeSourceIds })) {
    try {
        $content = (Invoke-WebRequest -UseBasicParsing -Uri $source.rawUrl).Content
        $bytes = [Text.Encoding]::UTF8.GetBytes($content)
        $currentHash = [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($bytes)).ToLowerInvariant()
        $status = if ($currentHash -eq $source.baselineSha256) { 'unchanged' } else { 'changed' }
        $sourceResults += [pscustomobject]@{
            id = [string]$source.id
            title = [string]$source.title
            referenceUrl = [string]$source.referenceUrl
            baselineSha256 = [string]$source.baselineSha256
            currentSha256 = $currentHash
            status = $status
            affectedRuleIds = @($catalog.rules | Where-Object { $_.status -eq 'active' -and $_.sourceIds -contains $source.id } | ForEach-Object { [string]$_.id } | Sort-Object)
        }
    }
    catch {
        $sourceResults += [pscustomobject]@{
            id = [string]$source.id
            title = [string]$source.title
            referenceUrl = [string]$source.referenceUrl
            baselineSha256 = [string]$source.baselineSha256
            currentSha256 = $null
            status = 'fetch-failed'
            affectedRuleIds = @($catalog.rules | Where-Object { $_.status -eq 'active' -and $_.sourceIds -contains $source.id } | ForEach-Object { [string]$_.id } | Sort-Object)
            error = $_.Exception.Message
        }
    }
}

$changedSources = @($sourceResults | Where-Object status -eq 'changed')
$failedSources = @($sourceResults | Where-Object status -eq 'fetch-failed')
$result = [ordered]@{
    success = $changedSources.Count -eq 0 -and $failedSources.Count -eq 0
    comparisonMode = 'raw-content-sha256'
    performsSemanticComparison = $false
    updatesCatalog = $false
    semanticReviewRequired = $changedSources.Count -gt 0
    lastSemanticReview = [string]$catalog.lastSemanticReview
    sourceCount = $sourceResults.Count
    changedCount = $changedSources.Count
    failedCount = $failedSources.Count
    sources = $sourceResults
}

if ($OutputFormat -eq 'Json') {
    $result | ConvertTo-Json -Depth 8
}
else {
    Write-ValidationSectionHeader -Title 'Hosted upstream source drift validation summary'
    Write-ValidationSummary -Fields ([ordered]@{
        Status = $(if ($result.success) { 'PASSED' } else { 'FAILED' })
        'Sources Checked' = $result.sourceCount
        Changed = $result.changedCount
        'Fetch Failed' = $result.failedCount
        'Updates Catalog' = $result.updatesCatalog
    })
    if (@($sourceResults | Where-Object status -ne 'unchanged').Count -gt 0) {
        Write-ValidationSectionHeader -Title 'Source issues'
    }
    foreach ($source in @($sourceResults | Where-Object status -ne 'unchanged')) {
        Write-Output (Format-ValidationStatusLine -Status $source.status -Name $source.id -Detail $source.referenceUrl)
        Write-Output "    Affected rules: $($source.affectedRuleIds -join ', ')"
    }
    Complete-ValidationTextOutput
}

if ($FailOnDrift -and -not $result.success) {
    throw 'Hosted upstream source drift requires semantic maintainer review; the catalog was not modified'
}
