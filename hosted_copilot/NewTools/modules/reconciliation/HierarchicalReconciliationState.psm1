Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Import-Module (Join-Path $PSScriptRoot '../shared/HostedToolkit.Helpers.psm1')

function Write-HierarchicalJsonAtomically {
    [CmdletBinding()]
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
        [IO.File]::WriteAllBytes($temporaryPath, (ConvertTo-JsonSnapshotBytes -Value $Value -Depth 100))
        [IO.File]::Move($temporaryPath, $Path, $true)
    }
    finally {
        Remove-Item -LiteralPath $temporaryPath -Force -ErrorAction SilentlyContinue
    }
}

function Copy-HierarchicalFileAtomically {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$SourcePath,
        [Parameter(Mandatory = $true)][string]$DestinationPath
    )

    $directory = Split-Path -Parent $DestinationPath
    if (-not (Test-Path -LiteralPath $directory -PathType Container)) {
        $null = New-Item -ItemType Directory -Path $directory -Force
    }
    $temporaryPath = Join-Path $directory ('.' + [IO.Path]::GetFileName($DestinationPath) + '.' + [guid]::NewGuid().ToString('N') + '.tmp')
    try {
        [IO.File]::WriteAllBytes($temporaryPath, [IO.File]::ReadAllBytes($SourcePath))
        [IO.File]::Move($temporaryPath, $DestinationPath, $true)
    }
    finally {
        Remove-Item -LiteralPath $temporaryPath -Force -ErrorAction SilentlyContinue
    }
}

function Test-HierarchicalJsonSchema {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Json,
        [Parameter(Mandatory = $true)][string]$SchemaPath,
        [Parameter(Mandatory = $true)][string]$Label
    )

    if ($Json -match '(?<=[\[:,])\s*undefined(?=\s*[,}\]])') {
        throw "$Label is not valid JSON: bare undefined is invalid; omit optional properties instead."
    }
    try {
        if (-not ($Json | Test-Json -SchemaFile $SchemaPath -ErrorAction Stop)) {
            throw "$Label does not satisfy its schema."
        }
    }
    catch {
        throw "$Label does not satisfy its schema: $($_.Exception.Message)"
    }
}

function New-ReconciliationStageCacheIdentity {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][ValidateSet('routing', 'consolidation', 'synthesis', 'adjudication')][string]$Stage,
        [Parameter(Mandatory = $true)][string]$ShardKey,
        [Parameter(Mandatory = $true)][ValidatePattern('^[0-9a-f]{64}$')][string]$PayloadSha256,
        [Parameter(Mandatory = $true)][ValidatePattern('^[0-9a-f]{64}$')][string]$CatalogContentSha256,
        [Parameter(Mandatory = $true)][ValidatePattern('^[0-9a-f]{64}$')][string]$ProtectedRulesContentSha256,
        [Parameter(Mandatory = $true)][ValidatePattern('^[0-9a-f]{64}$')][string]$ContractContentSha256,
        [Parameter(Mandatory = $true)][ValidatePattern('^[0-9a-f]{64}$')][string]$PromptContentSha256,
        [Parameter(Mandatory = $true)][ValidatePattern('^[0-9a-f]{64}$')][string]$SchemaContentSha256,
        [Parameter(Mandatory = $true)][string]$Evaluator,
        [Parameter(Mandatory = $true)][string]$Model,
        [Parameter(Mandatory = $true)][ValidateSet('low', 'medium', 'high', 'xhigh')][string]$ReasoningEffort
    )

    if ($ShardKey -cnotmatch ('^' + [regex]::Escape($Stage) + ':[0-9a-f]{64}$')) {
        throw "Stage `$Stage` cannot use shard key `$ShardKey`."
    }
    $identity = [ordered]@{
        payloadSha256 = $PayloadSha256
        catalogContentSha256 = $CatalogContentSha256
        protectedRulesContentSha256 = $ProtectedRulesContentSha256
        contractContentSha256 = $ContractContentSha256
        promptContentSha256 = $PromptContentSha256
        schemaContentSha256 = $SchemaContentSha256
        evaluator = $Evaluator
        model = $Model
        reasoningEffort = $ReasoningEffort
    }
    $cacheKey = Get-JsonSnapshotSha256 -Value ([ordered]@{ stage = $Stage; shardKey = $ShardKey; identity = $identity })
    return [pscustomobject][ordered]@{ stage = $Stage; shardKey = $ShardKey; cacheKey = $cacheKey; identity = $identity }
}

function New-EmptyHierarchicalReconciliationCache {
    return [pscustomobject][ordered]@{
        '$schema' = 'hierarchical-reconciliation-cache.schema.json'
        schemaVersion = 2
        kind = 'hosted-hierarchical-reconciliation-cache'
        entries = @()
    }
}

function Read-HierarchicalReconciliationCache {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$SchemaPath
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        return New-EmptyHierarchicalReconciliationCache
    }
    $json = Get-Content -LiteralPath $Path -Raw
    try {
        $cache = $json | ConvertFrom-Json -DateKind String
    }
    catch {
        throw "Cache file `$Path` is incompatible with the hierarchical reconciliation cache: $($_.Exception.Message)"
    }
    if ([int]$cache.schemaVersion -ne 2 -or [string]$cache.kind -cne 'hosted-hierarchical-reconciliation-cache') {
        throw "Cache file `$Path` is incompatible with the hierarchical reconciliation cache schema version 2."
    }
    Test-HierarchicalJsonSchema -Json $json -SchemaPath $SchemaPath -Label 'Hierarchical reconciliation cache'
    $duplicates = @($cache.entries | Group-Object -Property cacheKey | Where-Object Count -gt 1)
    if ($duplicates.Count -gt 0) {
        throw "Hierarchical reconciliation cache contains duplicate cache key `$($duplicates[0].Name)`."
    }
    return $cache
}

function Get-HierarchicalCachedResult {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][object]$Cache,
        [Parameter(Mandatory = $true)][object]$StageIdentity,
        [Parameter(Mandatory = $true)][string]$ResultSchemaPath
    )

    $matches = @($Cache.entries | Where-Object { [string]$_.cacheKey -ceq [string]$StageIdentity.cacheKey })
    if ($matches.Count -eq 0) {
        return $null
    }
    if ($matches.Count -gt 1) {
        throw "Hierarchical reconciliation cache contains duplicate cache key `$($StageIdentity.cacheKey)`."
    }
    $entry = $matches[0]
    if ([string]$entry.stage -cne [string]$StageIdentity.stage -or
        [string]$entry.shardKey -cne [string]$StageIdentity.shardKey -or
        (Get-JsonSnapshotSha256 -Value $entry.identity) -cne (Get-JsonSnapshotSha256 -Value $StageIdentity.identity)) {
        return $null
    }
    Test-HierarchicalJsonSchema -Json ($entry.result | ConvertTo-Json -Depth 100) -SchemaPath $ResultSchemaPath -Label "Cached $($StageIdentity.stage) result"
    return $entry.result
}

function Set-HierarchicalCachedResult {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$SchemaPath,
        [Parameter(Mandatory = $true)][string]$ResultSchemaPath,
        [Parameter(Mandatory = $true)][object]$StageIdentity,
        [Parameter(Mandatory = $true)][object]$Result
    )

    Test-HierarchicalJsonSchema -Json ($Result | ConvertTo-Json -Depth 100) -SchemaPath $ResultSchemaPath -Label "$($StageIdentity.stage) result"
    return Invoke-WithExclusiveFileLock -Path ($Path + '.lock') -Operation {
        param($CachePath, $CacheSchemaPath, $Identity, $StageResult)

        $cache = Read-HierarchicalReconciliationCache -Path $CachePath -SchemaPath $CacheSchemaPath
        $entries = @($cache.entries | Where-Object { [string]$_.cacheKey -cne [string]$Identity.cacheKey })
        $cache.entries = @($entries + [ordered]@{
            stage = [string]$Identity.stage
            shardKey = [string]$Identity.shardKey
            cacheKey = [string]$Identity.cacheKey
            identity = $Identity.identity
            result = $StageResult
        } | Sort-Object -Property stage, shardKey, cacheKey -CaseSensitive)
        Test-HierarchicalJsonSchema -Json ($cache | ConvertTo-Json -Depth 100) -SchemaPath $CacheSchemaPath -Label 'Hierarchical reconciliation cache'
        Write-HierarchicalJsonAtomically -Path $CachePath -Value $cache
        return $cache
    } -ArgumentList @($Path, $SchemaPath, $StageIdentity, $Result)
}

function Read-HierarchicalReconciliationRunManifest {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$SchemaPath,
        [Parameter(Mandatory = $true)][object]$ExpectedAuthority
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "Hierarchical reconciliation run manifest was not found: $Path"
    }
    $json = Get-Content -LiteralPath $Path -Raw
    try {
        $manifest = $json | ConvertFrom-Json -DateKind String
    }
    catch {
        throw "Run manifest `$Path` is incompatible with hierarchical reconciliation: $($_.Exception.Message)"
    }
    if ([int]$manifest.schemaVersion -ne 2 -or [string]$manifest.kind -cne 'hosted-hierarchical-reconciliation-run') {
        throw "Run manifest `$Path` is incompatible with hierarchical reconciliation schema version 2."
    }
    Test-HierarchicalJsonSchema -Json $json -SchemaPath $SchemaPath -Label 'Hierarchical reconciliation run manifest'
    if ((Get-JsonSnapshotSha256 -Value $manifest.authority) -cne (Get-JsonSnapshotSha256 -Value $ExpectedAuthority)) {
        throw 'Hierarchical reconciliation run manifest authority does not match the current run.'
    }
    return $manifest
}

function Get-HierarchicalCompletedStageResults {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][object]$Cache,
        [Parameter(Mandatory = $true)][string]$RunDirectory
    )

    return @($Cache.entries | Sort-Object -Property stage, shardKey -CaseSensitive | ForEach-Object {
        $shardHash = ([string]$_.shardKey).Substring(([string]$_.shardKey).IndexOf(':') + 1)
        $relativePath = "stages/$([string]$_.stage)/$shardHash/stage-result.json"
        if (Test-Path -LiteralPath (Join-Path $RunDirectory $relativePath) -PathType Leaf) {
            [pscustomobject][ordered]@{ stage = [string]$_.stage; shardKey = [string]$_.shardKey; cacheKey = [string]$_.cacheKey; resultRelativePath = $relativePath }
        }
    })
}

function Write-HierarchicalReconciliationRunManifest {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$SchemaPath,
        [Parameter(Mandatory = $true)][string]$RunId,
        [Parameter(Mandatory = $true)][string]$CreatedAt,
        [Parameter(Mandatory = $true)][object]$Authority,
        [object[]]$StageResults = @()
    )

    $manifest = [ordered]@{
        '$schema' = 'hierarchical-reconciliation-run.schema.json'
        schemaVersion = 2
        kind = 'hosted-hierarchical-reconciliation-run'
        runId = $RunId
        createdAt = $CreatedAt
        authority = $Authority
        stages = @($StageResults | Sort-Object -Property stage, shardKey -CaseSensitive | ForEach-Object {
            $resultRelativePath = if ($null -ne $_.PSObject.Properties['resultRelativePath']) {
                [string]$_.resultRelativePath
            }
            else {
                $shardHash = ([string]$_.shardKey).Substring(([string]$_.shardKey).IndexOf(':') + 1)
                "stages/$([string]$_.stage)/$shardHash/stage-result.json"
            }
            [ordered]@{ stage = [string]$_.stage; shardKey = [string]$_.shardKey; cacheKey = [string]$_.cacheKey; status = 'completed'; resultRelativePath = $resultRelativePath }
        })
    }
    Test-HierarchicalJsonSchema -Json ($manifest | ConvertTo-Json -Depth 100) -SchemaPath $SchemaPath -Label 'Hierarchical reconciliation run manifest'
    Write-HierarchicalJsonAtomically -Path $Path -Value $manifest
    return $manifest
}

Export-ModuleMember -Function @(
    'Write-HierarchicalJsonAtomically',
    'Copy-HierarchicalFileAtomically',
    'Test-HierarchicalJsonSchema',
    'New-ReconciliationStageCacheIdentity',
    'Read-HierarchicalReconciliationCache',
    'Get-HierarchicalCachedResult',
    'Set-HierarchicalCachedResult',
    'Read-HierarchicalReconciliationRunManifest',
    'Get-HierarchicalCompletedStageResults',
    'Write-HierarchicalReconciliationRunManifest'
)
