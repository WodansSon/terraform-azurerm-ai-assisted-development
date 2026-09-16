[CmdletBinding()]
param(
    [string]$RepositoryRoot = (Join-Path $PSScriptRoot '../..'),

    [Parameter(Mandatory = $true)]
    [string]$CandidatePath,

    [ValidateSet('Text', 'Json')]
    [string]$OutputFormat = 'Text'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$resolvedRepositoryRoot = [IO.Path]::GetFullPath($RepositoryRoot)
$resolvedCandidatePath = [IO.Path]::GetFullPath($CandidatePath)
$repositoryPrefix = $resolvedRepositoryRoot.TrimEnd([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar) + [IO.Path]::DirectorySeparatorChar
if ($resolvedCandidatePath.StartsWith($repositoryPrefix, [StringComparison]::OrdinalIgnoreCase)) {
    throw 'Accepted inventory candidate must be outside the repository root'
}

$inventoryDirectory = Join-Path $resolvedRepositoryRoot 'hosted_copilot/copilot-rule-catalog/source-inventories'
$schemaPath = Join-Path $inventoryDirectory 'source-inventory.schema.json'
if (-not (Test-Path -LiteralPath $resolvedCandidatePath -PathType Leaf)) {
    throw "Accepted inventory candidate was not found: $resolvedCandidatePath"
}
$candidateJson = Get-Content -LiteralPath $resolvedCandidatePath -Raw
if (-not (Test-Json -Json $candidateJson -SchemaFile $schemaPath -ErrorAction Stop)) {
    throw 'Accepted inventory candidate does not satisfy its schema'
}
$candidate = $candidateJson | ConvertFrom-Json
if ($null -eq $candidate.acceptance) {
    throw 'Accepted inventory candidate does not contain acceptance metadata'
}

$fileNames = @{
    'contributor-guidance' = 'contributor.json'
    'interactive-toolkit' = 'interactive.json'
    'maintainer-proposals' = 'maintainer.json'
}
if (-not $fileNames.ContainsKey([string]$candidate.sourceDefinitionId)) {
    throw "Unsupported accepted inventory source: $($candidate.sourceDefinitionId)"
}
$destinationPath = Join-Path $inventoryDirectory $fileNames[[string]$candidate.sourceDefinitionId]
$lockPath = "$destinationPath.lock"
$lockStream = $null
$temporaryPath = $null
try {
    if (-not (Test-Path -LiteralPath $inventoryDirectory -PathType Container)) {
        $null = New-Item -ItemType Directory -Path $inventoryDirectory -Force
    }
    try {
        $lockStream = [IO.File]::Open($lockPath, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::None)
    }
    catch {
        throw "Accepted inventory is already being applied: $destinationPath"
    }

    $expectedPreviousHash = $candidate.acceptance.previousAcceptedInventorySha256
    if (Test-Path -LiteralPath $destinationPath -PathType Leaf) {
        $actualPreviousHash = (Get-FileHash -LiteralPath $destinationPath -Algorithm SHA256).Hash.ToLowerInvariant()
        if ($null -eq $expectedPreviousHash -or $actualPreviousHash -cne [string]$expectedPreviousHash) {
            throw "Accepted inventory precondition failed: expected $expectedPreviousHash, actual $actualPreviousHash"
        }
    }
    elseif ($null -ne $expectedPreviousHash) {
        throw "Accepted inventory precondition failed: expected $expectedPreviousHash, actual missing"
    }

    $temporaryPath = Join-Path $inventoryDirectory ('.' + [IO.Path]::GetFileName($destinationPath) + '.' + [guid]::NewGuid().ToString('N') + '.tmp')
    [IO.File]::WriteAllText($temporaryPath, $candidateJson, [Text.UTF8Encoding]::new($false))
    [IO.File]::Move($temporaryPath, $destinationPath, $true)
}
finally {
    if ($null -ne $lockStream) {
        $lockStream.Dispose()
    }
    if ($null -ne $temporaryPath) {
        Remove-Item -LiteralPath $temporaryPath -Force -ErrorAction SilentlyContinue
    }
    Remove-Item -LiteralPath $lockPath -Force -ErrorAction SilentlyContinue
}

$result = [ordered]@{
    status = 'passed'
    sourceDefinitionId = [string]$candidate.sourceDefinitionId
    destinationPath = $destinationPath
    inventorySha256 = [string]$candidate.collection.inventorySha256
}
if ($OutputFormat -eq 'Json') {
    $result | ConvertTo-Json -Depth 5
}
else {
    Write-Output "Accepted inventory applied: $($result.sourceDefinitionId)"
    Write-Output "Destination: $($result.destinationPath)"
    Write-Output "Inventory SHA-256: $($result.inventorySha256)"
}
