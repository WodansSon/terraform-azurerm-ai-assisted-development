[CmdletBinding()]
param(
    [string]$RepositoryRoot = (Join-Path $PSScriptRoot '../..'),

    [Parameter(Mandatory = $true)]
    [string]$CandidatePath,

    [Parameter(Mandatory = $true)]
    [ValidatePattern('^[0-9a-f]{64}$')]
    [string]$ExpectedCandidateSha256,

    [ValidateSet('Text', 'Json')]
    [string]$OutputFormat = 'Text'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$sourceEvidenceModulePath = Join-Path $PSScriptRoot 'SourceEvidenceValidation.psm1'
Import-Module -Name $sourceEvidenceModulePath -Force

function Get-RevisionProjection {
    param([Parameter(Mandatory = $true)][object]$Inventory)

    return [ordered]@{
        '$schema' = [string]$Inventory.'$schema'
        schemaVersion = [int]$Inventory.schemaVersion
        sourceDefinitionId = [string]$Inventory.sourceDefinitionId
        sourceDefinitionSha256 = [string]$Inventory.sourceDefinitionSha256
        inventoryConfigurationSha256 = [string]$Inventory.inventoryConfigurationSha256
        collectorVersion = [int]$Inventory.collectorVersion
        parserId = [string]$Inventory.parserId
        parserContractSha256 = [string]$Inventory.parserContractSha256
        collectedAt = [string]$Inventory.collectedAt
        collection = $Inventory.collection
        acceptance = $Inventory.acceptance
        records = @($Inventory.records)
    }
}

function Get-CanonicalJson {
    param([Parameter(Mandatory = $true)][object]$Value)

    return $Value | ConvertTo-Json -Depth 40 -Compress
}

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
$candidateSnapshot = Get-SourceEvidenceFileSnapshot -Path $resolvedCandidatePath
$candidateBytes = $candidateSnapshot.Bytes
$actualCandidateSha256 = $candidateSnapshot.Sha256
if ($actualCandidateSha256 -cne $ExpectedCandidateSha256) {
    throw "Accepted inventory candidate hash mismatch: expected $ExpectedCandidateSha256, actual $actualCandidateSha256"
}
$candidateJson = $candidateSnapshot.Content
if (-not (Test-Json -Json $candidateJson -SchemaFile $schemaPath -ErrorAction Stop)) {
    throw 'Accepted inventory candidate does not satisfy its schema'
}
$candidate = $candidateJson | ConvertFrom-Json -DateKind String
if ($null -eq $candidate.acceptance) {
    throw 'Accepted inventory candidate does not contain acceptance metadata'
}
$candidateSourceDefinitionId = [string]$candidate.sourceDefinitionId
$approvedSourceDefinitionIds = @(Get-ExpectedSourceDefinitionIds -RepositoryRoot $resolvedRepositoryRoot)
if (-not ($approvedSourceDefinitionIds -ccontains $candidateSourceDefinitionId)) {
    throw "Accepted inventory source is not approved: $candidateSourceDefinitionId"
}
$sourceEvidence = Get-CurrentSourceDefinitionEvidence -RepositoryRoot $resolvedRepositoryRoot -SourceDefinitionId $candidateSourceDefinitionId
Assert-CurrentAcceptedSourceInventory -Inventory $candidate -Evidence $sourceEvidence
foreach ($revision in @($candidate.acceptedRevisions)) {
    if ([string]$revision.sourceDefinitionId -cne [string]$candidate.sourceDefinitionId) {
        throw 'Accepted inventory candidate history contains a different source definition'
    }
    $revisionRecordsSha256 = Get-SourceEvidenceRecordsSha256 -Records @($revision.records)
    if ($revisionRecordsSha256 -cne [string]$revision.collection.inventorySha256) {
        throw "Accepted inventory candidate history record hash mismatch: $($revision.acceptance.acceptedAt)"
    }
}

$fileNames = @{
    'contributor-guidance' = 'contributor.json'
    'interactive-toolkit' = 'interactive.json'
    'maintainer-proposals' = 'maintainer.json'
}
if (-not $fileNames.ContainsKey($candidateSourceDefinitionId)) {
    throw "Accepted inventory source has no canonical destination: $candidateSourceDefinitionId"
}
$destinationPath = Join-Path $inventoryDirectory $fileNames[$candidateSourceDefinitionId]
$lockPath = "$destinationPath.lock"
$lockStream = $null
$temporaryPath = $null
$destinationExisted = $false
$lockedDestinationSha256 = $null
try {
    if (-not (Test-Path -LiteralPath $inventoryDirectory -PathType Container)) {
        $null = New-Item -ItemType Directory -Path $inventoryDirectory -Force
    }
    try {
        $lockStream = [IO.File]::Open($lockPath, [IO.FileMode]::OpenOrCreate, [IO.FileAccess]::Write, [IO.FileShare]::None)
    }
    catch {
        throw "Accepted inventory is already being applied: $destinationPath"
    }

    $expectedPreviousHash = $candidate.acceptance.previousAcceptedInventorySha256
    if (Test-Path -LiteralPath $destinationPath -PathType Leaf) {
        $destinationExisted = $true
        $currentBytes = [IO.File]::ReadAllBytes($destinationPath)
        $lockedDestinationSha256 = [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($currentBytes)).ToLowerInvariant()
        if ($null -eq $expectedPreviousHash -or $lockedDestinationSha256 -cne [string]$expectedPreviousHash) {
            throw "Accepted inventory precondition failed: expected $expectedPreviousHash, actual $lockedDestinationSha256"
        }
        $currentOffset = if ($currentBytes.Length -ge 3 -and $currentBytes[0] -eq 0xEF -and $currentBytes[1] -eq 0xBB -and $currentBytes[2] -eq 0xBF) { 3 } else { 0 }
        $current = [Text.UTF8Encoding]::new($false, $true).GetString($currentBytes, $currentOffset, $currentBytes.Length - $currentOffset) | ConvertFrom-Json -DateKind String
        if (@($candidate.acceptedRevisions).Count -ne (@($current.acceptedRevisions).Count + 1)) {
            throw 'Accepted inventory candidate history does not append exactly one canonical revision'
        }
        for ($index = 0; $index -lt @($current.acceptedRevisions).Count; $index++) {
            if ((Get-CanonicalJson -Value $candidate.acceptedRevisions[$index]) -cne (Get-CanonicalJson -Value $current.acceptedRevisions[$index])) {
                throw "Accepted inventory candidate rewrites historical revision at index $index"
            }
        }
        $lastRevision = @($candidate.acceptedRevisions)[@($candidate.acceptedRevisions).Count - 1]
        if ((Get-CanonicalJson -Value $lastRevision) -cne (Get-CanonicalJson -Value (Get-RevisionProjection -Inventory $current))) {
            throw 'Accepted inventory candidate history does not append the exact canonical projection'
        }
    }
    elseif ($null -ne $expectedPreviousHash) {
        throw "Accepted inventory precondition failed: expected $expectedPreviousHash, actual missing"
    }
    elseif (@($candidate.acceptedRevisions).Count -ne 0) {
        throw 'Initial accepted inventory candidate cannot contain prior revisions'
    }

    $temporaryPath = Join-Path $inventoryDirectory ('.' + [IO.Path]::GetFileName($destinationPath) + '.' + [guid]::NewGuid().ToString('N') + '.tmp')
    [IO.File]::WriteAllBytes($temporaryPath, $candidateBytes)
    if ($destinationExisted) {
        if (-not (Test-Path -LiteralPath $destinationPath -PathType Leaf)) {
            throw "Accepted inventory precondition changed before replacement: expected $lockedDestinationSha256, actual missing"
        }
        $immediateDestinationSha256 = Get-SourceEvidenceFileSha256 -Path $destinationPath
        if ($immediateDestinationSha256 -cne $lockedDestinationSha256) {
            throw "Accepted inventory precondition changed before replacement: expected $lockedDestinationSha256, actual $immediateDestinationSha256"
        }
    }
    elseif (Test-Path -LiteralPath $destinationPath) {
        throw 'Accepted inventory precondition changed before replacement: expected missing, actual present'
    }
    [IO.File]::Move($temporaryPath, $destinationPath, $true)
    $appliedSha256 = Get-SourceEvidenceFileSha256 -Path $destinationPath
    if ($appliedSha256 -cne $actualCandidateSha256) {
        throw "Accepted inventory replacement hash mismatch: expected $actualCandidateSha256, actual $appliedSha256"
    }
}
finally {
    if ($null -ne $lockStream) {
        $lockStream.Dispose()
    }
    if ($null -ne $temporaryPath) {
        Remove-Item -LiteralPath $temporaryPath -Force -ErrorAction SilentlyContinue
    }
}

$result = [ordered]@{
    status = 'passed'
    sourceDefinitionId = [string]$candidate.sourceDefinitionId
    destinationPath = $destinationPath
    candidateSha256 = $actualCandidateSha256
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
