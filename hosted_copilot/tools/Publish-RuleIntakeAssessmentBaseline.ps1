[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$BundlePath,

    [string]$BaselinePath = (Join-Path $PSScriptRoot '../copilot-rule-catalog/rule-assessments/assessment-baseline.json'),

    [switch]$Publish,

    [ValidateSet('Text', 'Json')]
    [string]$OutputFormat = 'Text'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$validationOutputModulePath = Join-Path $PSScriptRoot '../../tools/ValidationOutput.psm1'
Import-Module -Name $validationOutputModulePath -Force

$bundleSchemaPath = Join-Path $PSScriptRoot '../copilot-rule-catalog/rule-intake-review.schema.json'
$baselineSchemaPath = Join-Path $PSScriptRoot '../copilot-rule-catalog/rule-assessments/assessment-baseline.schema.json'
$resolvedBundlePath = [IO.Path]::GetFullPath($BundlePath)
$resolvedBaselinePath = [IO.Path]::GetFullPath($BaselinePath)

foreach ($requiredPath in @($resolvedBundlePath, $bundleSchemaPath, $baselineSchemaPath)) {
    if (-not (Test-Path -LiteralPath $requiredPath -PathType Leaf)) {
        throw "Required assessment baseline input was not found: $requiredPath"
    }
}

function Get-ContentSha256 {
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string]$Content
    )

    $bytes = [Text.Encoding]::UTF8.GetBytes($Content)
    return [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($bytes)).ToLowerInvariant()
}

$bundleContent = Get-Content -LiteralPath $resolvedBundlePath -Raw
if (-not ($bundleContent | Test-Json -SchemaFile $bundleSchemaPath -ErrorAction Stop)) {
    throw 'Assessment bundle does not satisfy the rule intake review schema'
}
$bundle = $bundleContent | ConvertFrom-Json

$entries = New-Object 'System.Collections.Generic.List[object]'
$identities = @{}
foreach ($source in @(
    [pscustomobject]@{ sourceType = 'interactive'; candidates = @($bundle.interactiveCandidates); hashProperty = 'contentSha256' },
    [pscustomobject]@{ sourceType = 'upstream'; candidates = @($bundle.upstreamCandidates); hashProperty = 'currentSha256' }
)) {
    foreach ($candidate in $source.candidates) {
        $identity = "$($source.sourceType):$($candidate.id)"
        if ($identities.ContainsKey($identity)) {
            throw "Assessment bundle contains duplicate candidate identity: $identity"
        }
        $identities[$identity] = $true
        if (-not $candidate.PSObject.Properties['assessment'] -or $null -eq $candidate.assessment) {
            throw "Assessment bundle candidate is not evaluated: $identity"
        }
        $sourceHash = [string]$candidate.($source.hashProperty)
        if ([string]$candidate.assessment.sourceContentSha256 -ne $sourceHash) {
            throw "Assessment bundle candidate has a stale assessment: $identity"
        }
        $entries.Add([pscustomobject][ordered]@{
            sourceType = $source.sourceType
            id = [string]$candidate.id
            sourceContentSha256 = $sourceHash
            assessment = $candidate.assessment
        })
    }
}

$baseline = [ordered]@{
    '$schema' = 'assessment-baseline.schema.json'
    schemaVersion = 1
    generatedAt = [DateTimeOffset]::UtcNow.ToString('o')
    hostedCatalogSha256 = [string]$bundle.snapshots.hostedCatalogSha256
    sourceBundleSha256 = Get-ContentSha256 -Content $bundleContent
    entries = $entries.ToArray()
}
$baselineJson = $baseline | ConvertTo-Json -Depth 30
if (-not ($baselineJson | Test-Json -SchemaFile $baselineSchemaPath -ErrorAction Stop)) {
    throw 'Generated assessment baseline does not satisfy its schema'
}

if ($Publish) {
    $baselineDirectory = Split-Path -Parent $resolvedBaselinePath
    if (-not (Test-Path -LiteralPath $baselineDirectory -PathType Container)) {
        New-Item -ItemType Directory -Path $baselineDirectory -Force | Out-Null
    }
    $temporaryPath = "$resolvedBaselinePath.$PID.tmp"
    try {
        [IO.File]::WriteAllText($temporaryPath, $baselineJson + "`n", [Text.UTF8Encoding]::new($false))
        Move-Item -LiteralPath $temporaryPath -Destination $resolvedBaselinePath -Force
    }
    finally {
        if (Test-Path -LiteralPath $temporaryPath -PathType Leaf) {
            Remove-Item -LiteralPath $temporaryPath -Force
        }
    }
}

$result = [ordered]@{
    status = 'passed'
    published = [bool]$Publish
    baselinePath = $resolvedBaselinePath
    entryCount = $entries.Count
    interactiveCount = @($entries.ToArray() | Where-Object sourceType -eq 'interactive').Count
    upstreamCount = @($entries.ToArray() | Where-Object sourceType -eq 'upstream').Count
    hostedCatalogSha256 = $baseline.hostedCatalogSha256
    sourceBundleSha256 = $baseline.sourceBundleSha256
}

if ($OutputFormat -eq 'Json') {
    $result | ConvertTo-Json -Depth 5
}
else {
    Write-ValidationSectionHeader -Title 'Hosted rule assessment baseline'
    Write-ValidationSummary -Fields ([ordered]@{
        Status = $result.status.ToUpperInvariant()
        Published = $result.published
        Entries = $result.entryCount
        Interactive = $result.interactiveCount
        Upstream = $result.upstreamCount
        'Hosted Catalog SHA-256' = $result.hostedCatalogSha256
        'Source Bundle SHA-256' = $result.sourceBundleSha256
        'Baseline Path' = $result.baselinePath
    })
    Complete-ValidationTextOutput
}
