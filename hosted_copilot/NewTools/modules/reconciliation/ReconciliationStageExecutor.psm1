Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Import-Module (Join-Path $PSScriptRoot '../shared/HostedToolkit.Helpers.psm1')
Import-Module (Join-Path $PSScriptRoot 'HierarchicalReconciliationState.psm1')
Import-Module (Join-Path $PSScriptRoot 'ReconciliationStagePresentation.psm1')
$reconciliationRetryCorrectionReserveBytes = 16384
$reconciliationRetryDiagnosticMaxCharacters = 3072
$reconciliationRetryCorrectionTemplate = Get-Content -LiteralPath (Join-Path $PSScriptRoot '../../prompts/shared/RetryCorrection.md') -Raw

function Read-ReconciliationResponseDiagnostic {
    param([string]$Path, [string]$Stage)

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $null }
    try {
        if ((Get-Item -LiteralPath $Path).Length -gt 8192) { throw 'Diagnostic exceeds its metadata bound' }
        $source = Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json -DateKind String
        if ($source.schemaVersion -ne 1 -or $source.kind -cne 'hosted-stage-response-diagnostic' -or $source.stage -cne $Stage -or
            $source.phase -cnotin @('json-extraction', 'json-parse', 'schema-validation')) {
            throw 'Unexpected response diagnostic metadata'
        }
        $diagnostic = [ordered]@{
            phase = [string]$source.phase
            assistantCharacterCount = [int]$source.assistantCharacterCount
            extractedCharacterCount = [int]$source.extractedCharacterCount
            markdownFence = [bool]$source.markdownFence
        }
        foreach ($name in @('assistantJson', 'extractedJson')) {
            $shape = $source.$name
            $diagnostic[$name] = if ($null -eq $shape) { $null } else {
                [ordered]@{
                    valid = [bool]$shape.valid
                    valueKind = $(if ($null -ne $shape.valueKind) { [string][Text.Json.JsonValueKind]$shape.valueKind } else { $null })
                    lineNumber = $(if ($null -ne $shape.lineNumber) { [long]$shape.lineNumber } else { $null })
                    bytePositionInLine = $(if ($null -ne $shape.bytePositionInLine) { [long]$shape.bytePositionInLine } else { $null })
                }
            }
        }
        if ($null -ne $source.PSObject.Properties['schemaDiagnostic'] -and $null -ne $source.schemaDiagnostic) {
            $schemaErrors = [Collections.Generic.List[object]]::new()
            $keywords = @('type', 'required', 'additionalProperties', 'unevaluatedProperties', 'properties', 'propertyNames', 'patternProperties', 'const', 'enum', 'pattern', 'format', 'minLength', 'maxLength', 'minItems', 'maxItems', 'uniqueItems', 'items', 'prefixItems', 'contains', 'minContains', 'maxContains', 'minimum', 'maximum', 'exclusiveMinimum', 'exclusiveMaximum', 'multipleOf', 'minProperties', 'maxProperties', 'allOf', 'anyOf', 'oneOf', 'not', 'if', 'then', 'else', 'dependentRequired', 'dependentSchemas', '$ref', 'false')
            foreach ($failure in @($source.schemaDiagnostic.errors | Select-Object -First 16)) {
                if ([string]$failure.keyword -cin $keywords -and ([string]$failure.schemaPath).StartsWith('#', [StringComparison]::Ordinal) -and ([string]$failure.schemaPath).Length -le 256) {
                    $schemaErrors.Add([ordered]@{ keyword = [string]$failure.keyword; schemaPath = [string]$failure.schemaPath })
                }
            }
            $diagnostic.schemaDiagnostic = [ordered]@{ available = [bool]$source.schemaDiagnostic.available; errors = @($schemaErrors.ToArray()); truncated = [bool]$source.schemaDiagnostic.truncated }
        }
        return $diagnostic
    }
    catch { return [ordered]@{ phase = 'diagnostic-read'; readable = $false } }
}

function Get-ReconciliationStageInput {
    param([string]$Stage, [object]$Shard)

    return [ordered]@{
        schemaVersion = 1
        kind = 'hosted-hierarchical-reconciliation-stage-input'
        stage = $Stage
        shardKey = $Shard.shardKey
        payload = $Shard.payload
    }
}

function Get-ReconciliationReservedPayloadBytes {
    param([object]$StageInput, [long]$ArtifactBytes)

    return (ConvertTo-JsonSnapshotBytes -Value $StageInput -Depth 100).Length + $ArtifactBytes + $reconciliationRetryCorrectionReserveBytes
}

function Set-ReconciliationRetryCorrection {
    param(
        [Parameter(Mandatory = $true)][string]$PromptPath,
        [Parameter(Mandatory = $true)][byte[]]$BasePromptBytes,
        [Parameter(Mandatory = $true)][string]$ContextPath,
        [Parameter(Mandatory = $true)][string]$Stage,
        [Parameter(Mandatory = $true)][string]$ShardKey,
        [Parameter(Mandatory = $true)][int]$FailedAttempt,
        [Parameter(Mandatory = $true)][string]$ErrorMessage
    )

    $diagnostic = ($ErrorMessage -replace '\s+', ' ').Trim()
    if ($diagnostic.Length -gt $reconciliationRetryDiagnosticMaxCharacters) {
        $diagnostic = $diagnostic.Substring(0, $reconciliationRetryDiagnosticMaxCharacters) + ' [truncated; full diagnostic retained in the attempt failure artifact]'
    }
    $context = [ordered]@{
        schemaVersion = 1
        kind = 'hosted-hierarchical-reconciliation-retry-context'
        stage = $Stage
        shardKey = $ShardKey
        failedAttempt = $FailedAttempt
        diagnostic = $diagnostic
    }
    Write-HierarchicalJsonAtomically -Path $ContextPath -Value $context
    $contextJson = $context | ConvertTo-Json -Depth 10 -Compress
    $basePrompt = [Text.UTF8Encoding]::new($false).GetString($BasePromptBytes).TrimEnd()
    $correction = "`n`n" + $reconciliationRetryCorrectionTemplate.Replace('{{VALIDATION_CONTEXT}}', $contextJson)
    $correctedPromptBytes = [Text.UTF8Encoding]::new($false).GetBytes($basePrompt + $correction + "`n")
    if (($correctedPromptBytes.Length - $BasePromptBytes.Length) -gt $reconciliationRetryCorrectionReserveBytes) {
        throw "Reconciliation retry correction exceeds its reserved evaluator payload budget of $reconciliationRetryCorrectionReserveBytes bytes."
    }
    [IO.File]::WriteAllBytes($PromptPath, $correctedPromptBytes)
}

function Invoke-ReconciliationStageSet {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][ValidateSet('routing', 'consolidation', 'synthesis', 'adjudication')][string]$Stage,
        [Parameter(Mandatory = $true)][object[]]$Shards,
        [Parameter(Mandatory = $true)][string]$RunDirectory,
        [Parameter(Mandatory = $true)][string]$CachePath,
        [string]$PersistentCachePath,
        [switch]$ReadPersistentCache,
        [Parameter(Mandatory = $true)][string]$CacheSchemaPath,
        [Parameter(Mandatory = $true)][string]$ResultSchemaPath,
        [Parameter(Mandatory = $true)][string]$PromptPath,
        [Parameter(Mandatory = $true)][string]$CatalogPath,
        [Parameter(Mandatory = $true)][string]$ProtectedRulesPath,
        [Parameter(Mandatory = $true)][string]$ContractPath,
        [string]$ContractAuthorityPath,
        [Parameter(Mandatory = $true)][string]$EvaluatorScriptPath,
        [scriptblock]$ResultValidator,
        [scriptblock]$BatchExecutor,
        [string]$EvaluatorCommand = 'copilot',
        [Parameter(Mandatory = $true)][string]$Model,
        [Parameter(Mandatory = $true)][ValidateSet('low', 'medium', 'high', 'xhigh')][string]$ReasoningEffort,
        [ValidateRange(0, 3)][int]$MaxRetries = 1,
        [ValidateRange(0, 60000)][int]$RetryDelayMilliseconds = 1000,
        [ValidateRange(1, 8)][int]$MaxParallelShards = 3,
        [ValidateRange(1, [int]::MaxValue)][int]$EvaluatorPayloadBudgetBytes = 393216,
        [ValidateSet('Assessments', 'Assessment Groups', 'Rule Issue Groups', 'Rules')][string]$InputLabel = 'Assessment Groups',
        [ValidateRange(0, [int]::MaxValue)][int]$InputCount = 0,
        [switch]$ShowProgress
    )

    if ($Shards.Count -eq 0) {
        throw "Reconciliation stage `$Stage` requires at least one shard."
    }
    $resolvedPaths = @{}
    foreach ($pathName in @('CacheSchemaPath', 'ResultSchemaPath', 'PromptPath', 'CatalogPath', 'ProtectedRulesPath', 'ContractPath', 'EvaluatorScriptPath')) {
        $resolvedPath = [IO.Path]::GetFullPath([string](Get-Variable -Name $pathName -ValueOnly))
        if (-not (Test-Path -LiteralPath $resolvedPath -PathType Leaf)) {
            throw "Reconciliation stage `$Stage` input was not found: $resolvedPath"
        }
        $resolvedPaths[$pathName] = $resolvedPath
    }

    $resultSchemaSnapshot = Get-FileSnapshot -Path $resolvedPaths.ResultSchemaPath
    $promptSnapshot = Get-FileSnapshot -Path $resolvedPaths.PromptPath
    $catalogSnapshot = Get-FileSnapshot -Path $resolvedPaths.CatalogPath
    $protectedRulesSnapshot = Get-FileSnapshot -Path $resolvedPaths.ProtectedRulesPath
    $contractArtifactSnapshot = Get-FileSnapshot -Path $resolvedPaths.ContractPath
    $resolvedContractAuthorityPath = if ([string]::IsNullOrWhiteSpace($ContractAuthorityPath)) { $resolvedPaths.ContractPath } else { [IO.Path]::GetFullPath($ContractAuthorityPath) }
    if (-not (Test-Path -LiteralPath $resolvedContractAuthorityPath -PathType Leaf)) {
        throw "Reconciliation stage `$Stage` contract authority was not found: $resolvedContractAuthorityPath"
    }
    $contractAuthoritySnapshot = Get-FileSnapshot -Path $resolvedContractAuthorityPath
    $evaluatorSnapshot = Get-FileSnapshot -Path $resolvedPaths.EvaluatorScriptPath
    $evaluatorIdentity = 'script:' + $evaluatorSnapshot.Sha256 + ';command:' + $EvaluatorCommand
    $resolvedPersistentCachePath = if ([string]::IsNullOrWhiteSpace($PersistentCachePath)) { $null } else { [IO.Path]::GetFullPath($PersistentCachePath) }
    $cache = Read-HierarchicalReconciliationCache -Path $CachePath -SchemaPath $resolvedPaths.CacheSchemaPath
    $persistentCache = if ($ReadPersistentCache -and $null -ne $resolvedPersistentCachePath -and $resolvedPersistentCachePath -cne [IO.Path]::GetFullPath($CachePath)) {
        Read-HierarchicalReconciliationCache -Path $resolvedPersistentCachePath -SchemaPath $resolvedPaths.CacheSchemaPath
    } else { $null }
    $stageDirectory = Join-Path ([IO.Path]::GetFullPath($RunDirectory)) "stages/$Stage"
    $null = New-Item -ItemType Directory -Path $stageDirectory -Force

    $workByShardKey = @{}
    $orderedShardKeys = [Collections.Generic.List[string]]::new()
    $shardNumber = 0
    foreach ($shard in @($Shards | Sort-Object -Property shardKey -CaseSensitive)) {
        $shardNumber++
        $shardKey = [string]$shard.shardKey
        if ($shardKey -cnotmatch ('^' + [regex]::Escape($Stage) + ':[0-9a-f]{64}$')) {
            throw "Reconciliation stage `$Stage` received invalid shard key `$shardKey`."
        }
        if ($workByShardKey.ContainsKey($shardKey)) {
            throw "Reconciliation stage `$Stage` received duplicate shard key `$shardKey`."
        }
        $stageInput = Get-ReconciliationStageInput -Stage $Stage -Shard $shard
        $identity = New-ReconciliationStageCacheIdentity -Stage $Stage -ShardKey $shardKey -PayloadSha256 (Get-JsonSnapshotSha256 -Value $stageInput) -CatalogContentSha256 $catalogSnapshot.Sha256 -ProtectedRulesContentSha256 $protectedRulesSnapshot.Sha256 -ContractContentSha256 $contractAuthoritySnapshot.Sha256 -PromptContentSha256 $promptSnapshot.Sha256 -SchemaContentSha256 $resultSchemaSnapshot.Sha256 -Evaluator $evaluatorIdentity -Model $Model -ReasoningEffort $ReasoningEffort
        $shardDirectory = Join-Path $stageDirectory $shardKey.Substring($shardKey.IndexOf(':') + 1)
        $null = New-Item -ItemType Directory -Path $shardDirectory -Force
        $inputPath = Join-Path $shardDirectory 'stage-input.json'
        $outputPath = Join-Path $shardDirectory 'stage-result.json'
        $catalogArtifactPath = Join-Path $shardDirectory 'instruction-catalog.json'
        $protectedRulesArtifactPath = Join-Path $shardDirectory 'protected-rules.json'
        $contractArtifactPath = Join-Path $shardDirectory 'stage-contract.json'
        $schemaArtifactPath = Join-Path $shardDirectory 'stage-result.schema.json'
        $promptArtifactPath = Join-Path $shardDirectory 'stage-prompt.md'
        Write-HierarchicalJsonAtomically -Path $inputPath -Value $stageInput
        [IO.File]::WriteAllBytes($catalogArtifactPath, $catalogSnapshot.Bytes)
        [IO.File]::WriteAllBytes($protectedRulesArtifactPath, $protectedRulesSnapshot.Bytes)
        [IO.File]::WriteAllBytes($contractArtifactPath, $contractArtifactSnapshot.Bytes)
        [IO.File]::WriteAllBytes($schemaArtifactPath, $resultSchemaSnapshot.Bytes)
        [IO.File]::WriteAllBytes($promptArtifactPath, $promptSnapshot.Bytes)
        $artifactBytes = $catalogSnapshot.Bytes.Length + $protectedRulesSnapshot.Bytes.Length + $contractArtifactSnapshot.Bytes.Length + $promptSnapshot.Bytes.Length + $resultSchemaSnapshot.Bytes.Length
        $reservedPayloadBytes = Get-ReconciliationReservedPayloadBytes -StageInput $stageInput -ArtifactBytes $artifactBytes
        $payloadBytes = $reservedPayloadBytes - $reconciliationRetryCorrectionReserveBytes
        if ($reservedPayloadBytes -gt $EvaluatorPayloadBudgetBytes) {
            throw ('Reconciliation stage `{0}` shard `{1}` requires {2} bytes and exceeds the evaluator payload budget of {3} bytes including retry-correction capacity.' -f $Stage, $shardKey, $reservedPayloadBytes, $EvaluatorPayloadBudgetBytes)
        }
        $cachedValidationError = ''
        $cachedResult = Get-HierarchicalCachedResult -Cache $cache -StageIdentity $identity -ResultSchemaPath $resolvedPaths.ResultSchemaPath
        if ($null -eq $cachedResult -and $null -ne $persistentCache) {
            $cachedResult = Get-HierarchicalCachedResult -Cache $persistentCache -StageIdentity $identity -ResultSchemaPath $resolvedPaths.ResultSchemaPath
        }
        if ($null -ne $cachedResult -and $null -ne $ResultValidator) {
            try {
                & $ResultValidator $shard.payload $cachedResult
            }
            catch {
                $cachedValidationError = [string]$_.Exception.Message
                $cachedResult = $null
            }
        }
        $work = [pscustomobject][ordered]@{
            Stage = $Stage
            ShardKey = $shardKey
            Payload = $shard.payload
            Identity = $identity
            Directory = $shardDirectory
            InputPath = $inputPath
            OutputPath = $outputPath
            CatalogPath = $catalogArtifactPath
            ProtectedRulesPath = $protectedRulesArtifactPath
            ContractPath = $contractArtifactPath
            SchemaPath = $schemaArtifactPath
            PromptPath = $promptArtifactPath
            RetryContextPath = Join-Path $shardDirectory 'stage-retry-context.json'
            PayloadSizeBytes = [long]$payloadBytes
            CachedResult = $cachedResult
            ShardNumber = $shardNumber
            ShardCount = $Shards.Count
        }
        if (-not [string]::IsNullOrWhiteSpace($cachedValidationError)) {
            Set-ReconciliationRetryCorrection -PromptPath $work.PromptPath -BasePromptBytes $promptSnapshot.Bytes -ContextPath $work.RetryContextPath -Stage $Stage -ShardKey $shardKey -FailedAttempt 0 -ErrorMessage $cachedValidationError
        }
        $workByShardKey[$shardKey] = $work
        $orderedShardKeys.Add($shardKey)
    }

    $resultsByShardKey = @{}
    $cachedCount = 0
    foreach ($shardKey in $orderedShardKeys) {
        $work = $workByShardKey[$shardKey]
        if ($null -ne $work.CachedResult) {
            Write-HierarchicalJsonAtomically -Path $work.OutputPath -Value $work.CachedResult
            if ([string]$work.Identity.cacheKey -cnotin @($cache.entries | ForEach-Object cacheKey)) {
                $cache = Set-HierarchicalCachedResult -Path $CachePath -SchemaPath $resolvedPaths.CacheSchemaPath -ResultSchemaPath $resolvedPaths.ResultSchemaPath -StageIdentity $work.Identity -Result $work.CachedResult
            }
            if ($null -ne $persistentCache -and [string]$work.Identity.cacheKey -cnotin @($persistentCache.entries | ForEach-Object cacheKey)) {
                $persistentCache = Set-HierarchicalCachedResult -Path $resolvedPersistentCachePath -SchemaPath $resolvedPaths.CacheSchemaPath -ResultSchemaPath $resolvedPaths.ResultSchemaPath -StageIdentity $work.Identity -Result $work.CachedResult
            }
            $resultsByShardKey[$shardKey] = [pscustomobject][ordered]@{ stage = $Stage; shardKey = $shardKey; cacheKey = [string]$work.Identity.cacheKey; reused = $true; result = $work.CachedResult; directory = $work.Directory }
            $cachedCount++
        }
    }

    $pending = @($orderedShardKeys | Where-Object { -not $resultsByShardKey.ContainsKey($_) } | ForEach-Object { $workByShardKey[$_] })
    if ($null -ne $BatchExecutor -and $pending.Count -gt 0) {
        $projected = @(& $BatchExecutor @($pending | ForEach-Object { [pscustomobject]@{ shardKey = $_.ShardKey; payload = $_.Payload } }))
        $projectedKeys = @($projected | ForEach-Object shardKey)
        $pendingKeys = @($pending | ForEach-Object ShardKey)
        if ($projected.Count -ne $pending.Count -or @($projectedKeys | Sort-Object -CaseSensitive -Unique).Count -ne $pending.Count -or @($projectedKeys | Where-Object { $_ -cnotin $pendingKeys }).Count -gt 0) {
            throw 'Batched evaluation must return every uncached semantic item exactly once'
        }
        foreach ($item in $projected) {
            $work = $workByShardKey[[string]$item.shardKey]
            Test-HierarchicalJsonSchema -Json ($item.result | ConvertTo-Json -Depth 100) -SchemaPath $resolvedPaths.ResultSchemaPath -Label 'Projected semantic item result'
            if ($null -ne $ResultValidator) { & $ResultValidator $work.Payload $item.result }
        }
        foreach ($item in $projected) {
            $work = $workByShardKey[[string]$item.shardKey]
            Write-HierarchicalJsonAtomically -Path $work.OutputPath -Value $item.result
            $null = Set-HierarchicalCachedResult -Path $CachePath -SchemaPath $resolvedPaths.CacheSchemaPath -ResultSchemaPath $resolvedPaths.ResultSchemaPath -StageIdentity $work.Identity -Result $item.result
            if ($null -ne $resolvedPersistentCachePath -and $resolvedPersistentCachePath -cne [IO.Path]::GetFullPath($CachePath)) {
                $null = Set-HierarchicalCachedResult -Path $resolvedPersistentCachePath -SchemaPath $resolvedPaths.CacheSchemaPath -ResultSchemaPath $resolvedPaths.ResultSchemaPath -StageIdentity $work.Identity -Result $item.result
            }
            $resultsByShardKey[$work.ShardKey] = [pscustomobject][ordered]@{ stage = $Stage; shardKey = $work.ShardKey; cacheKey = [string]$work.Identity.cacheKey; reused = $false; result = $item.result; directory = $work.Directory }
        }
        $pending = @()
    }
    $stagePresentation = Get-ReconciliationStagePresentation -Stage $Stage
    $bootstrapBytesPerSecondPerWorker = [int]$stagePresentation.bootstrapBytesPerSecondPerWorker
    if ($ShowProgress) {
        [long]$pendingPayloadBytes = 0
        foreach ($work in $pending) {
            $pendingPayloadBytes += [long]$work.PayloadSizeBytes
        }
        $effectiveWorkerCount = [Math]::Min($MaxParallelShards, $pending.Count)
        $initialEstimate = Get-EstimatedRemainingMilliseconds -CompletedPayloadBytes 0 -CompletedElapsedMilliseconds 0 -RemainingPayloadBytes $pendingPayloadBytes -MaxParallelBatches $effectiveWorkerCount -BootstrapBytesPerSecondPerWorker $bootstrapBytesPerSecondPerWorker
        Write-ReconciliationStagePlan -DisplayName ([string]$stagePresentation.displayName) -InputLabel $InputLabel -InputCount $InputCount -BatchCount $orderedShardKeys.Count -CachedCount $cachedCount -PendingCount $pending.Count -WorkerCount $effectiveWorkerCount -PendingPayloadBytes $pendingPayloadBytes -EstimatedMilliseconds $initialEstimate
    }
    $errorsByShardKey = @{}
    $failureAttemptsByShardKey = @{}
    $stageStopwatch = [Diagnostics.Stopwatch]::StartNew()
    $stageWork = @($pending)
    $completedShardKeys = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    [long]$completedPayloadBytes = 0
    [long]$completedElapsedMilliseconds = 0
    for ($attempt = 1; $attempt -le ($MaxRetries + 1) -and $pending.Count -gt 0; $attempt++) {
        if ($attempt -gt 1 -and $RetryDelayMilliseconds -gt 0) {
            Start-Sleep -Milliseconds ([int][Math]::Min(60000, $RetryDelayMilliseconds * [Math]::Pow(2, $attempt - 2)))
        }
        $workerEvaluatorScriptPath = $resolvedPaths.EvaluatorScriptPath
        $workerStage = $Stage
        $workerEvaluatorCommand = $EvaluatorCommand
        $workerModel = $Model
        $workerReasoningEffort = $ReasoningEffort
        $workerAttempt = $attempt
        $workerAttemptCount = $MaxRetries + 1
        $retry = [Collections.Generic.List[object]]::new()
        $pending | ForEach-Object -Parallel {
            $work = $_
            [pscustomobject][ordered]@{
                Kind = 'started'
                ShardKey = $work.ShardKey
                ShardNumber = [int]$work.ShardNumber
                ShardCount = [int]$work.ShardCount
                PayloadSizeBytes = [long]$work.PayloadSizeBytes
                Attempt = $using:workerAttempt
                AttemptCount = $using:workerAttemptCount
            }
            $stopwatch = [Diagnostics.Stopwatch]::StartNew()
            $output = @()
            try {
                $parameters = @{
                    Stage = $using:workerStage
                    InputPath = $work.InputPath
                    CatalogPath = $work.CatalogPath
                    ProtectedRulesPath = $work.ProtectedRulesPath
                    ContractPath = $work.ContractPath
                    SchemaPath = $work.SchemaPath
                    PromptPath = $work.PromptPath
                    OutputPath = $work.OutputPath
                    EvaluatorCommand = $using:workerEvaluatorCommand
                    Model = $using:workerModel
                    ReasoningEffort = $using:workerReasoningEffort
                }
                $output = @(& pwsh -NoProfile -NonInteractive -File $using:workerEvaluatorScriptPath @parameters 2>&1)
                if ($LASTEXITCODE -ne 0) {
                    throw "Evaluator script exited with code $LASTEXITCODE`: $(($output | Out-String).Trim())"
                }
                [pscustomobject][ordered]@{ Kind = 'completed'; ShardKey = $work.ShardKey; Succeeded = $true; ElapsedMilliseconds = [long]$stopwatch.ElapsedMilliseconds; Output = @($output | ForEach-Object { [string]$_ }); Error = '' }
            }
            catch {
                [pscustomobject][ordered]@{ Kind = 'completed'; ShardKey = $work.ShardKey; Succeeded = $false; ElapsedMilliseconds = [long]$stopwatch.ElapsedMilliseconds; Output = @($output | ForEach-Object { [string]$_ }); Error = [string]$_.Exception.Message }
            }
        } -ThrottleLimit $MaxParallelShards | ForEach-Object {
            $workerEvent = $_
            if ([string]$workerEvent.Kind -ceq 'started') {
                if ($ShowProgress -and [int]$workerEvent.Attempt -eq 1) {
                    Write-ReconciliationBatchStarted -Stage $Stage -WorkerEvent $workerEvent
                }
                return
            }
            $workerResult = $workerEvent
            $shardKey = [string]$workerResult.ShardKey
            $work = $workByShardKey[$shardKey]
            $failurePhase = 'evaluator'
            try {
                if (-not [bool]$workerResult.Succeeded) {
                    throw [string]$workerResult.Error
                }
                if (-not (Test-Path -LiteralPath $work.OutputPath -PathType Leaf)) {
                    throw ('Evaluator did not write a {0} result for shard `{1}`.' -f $Stage, $shardKey)
                }
                $failurePhase = 'schema-validation'
                $resultJson = Get-Content -LiteralPath $work.OutputPath -Raw
                Test-HierarchicalJsonSchema -Json $resultJson -SchemaPath $resolvedPaths.ResultSchemaPath -Label ('{0} result for shard `{1}`' -f $Stage, $shardKey)
                $result = $resultJson | ConvertFrom-Json -DateKind String
                $resultShardKeyProperty = $result.PSObject.Properties['shardKey']
                if ($Stage -in @('routing', 'consolidation') -and ($null -eq $resultShardKeyProperty -or [string]$resultShardKeyProperty.Value -cne $shardKey)) {
                    $resultShardKey = if ($null -eq $resultShardKeyProperty) { '<missing>' } else { [string]$resultShardKeyProperty.Value }
                    throw ('{0} result shard key `{1}` does not match `{2}`.' -f $Stage, $resultShardKey, $shardKey)
                }
                if ($null -ne $ResultValidator) {
                    $failurePhase = 'semantic-validation'
                    & $ResultValidator $work.Payload $result
                }
                $failurePhase = 'cache-publication'
                $null = Set-HierarchicalCachedResult -Path $CachePath -SchemaPath $resolvedPaths.CacheSchemaPath -ResultSchemaPath $resolvedPaths.ResultSchemaPath -StageIdentity $work.Identity -Result $result
                if ($null -ne $resolvedPersistentCachePath -and $resolvedPersistentCachePath -cne [IO.Path]::GetFullPath($CachePath)) {
                    $null = Set-HierarchicalCachedResult -Path $resolvedPersistentCachePath -SchemaPath $resolvedPaths.CacheSchemaPath -ResultSchemaPath $resolvedPaths.ResultSchemaPath -StageIdentity $work.Identity -Result $result
                }
                $resultsByShardKey[$shardKey] = [pscustomobject][ordered]@{ stage = $Stage; shardKey = $shardKey; cacheKey = [string]$work.Identity.cacheKey; reused = $false; result = $result; directory = $work.Directory }
                $errorsByShardKey.Remove($shardKey)
                $null = $completedShardKeys.Add($shardKey)
                $completedPayloadBytes += [long]$work.PayloadSizeBytes
                $completedElapsedMilliseconds += [long]$workerResult.ElapsedMilliseconds
                [long]$remainingPayloadBytes = 0
                foreach ($remainingWork in @($stageWork | Where-Object { -not $completedShardKeys.Contains([string]$_.ShardKey) })) {
                    $remainingPayloadBytes += [long]$remainingWork.PayloadSizeBytes
                }
                $estimatedRemainingMilliseconds = Get-EstimatedRemainingMilliseconds -CompletedPayloadBytes $completedPayloadBytes -CompletedElapsedMilliseconds $completedElapsedMilliseconds -RemainingPayloadBytes $remainingPayloadBytes -MaxParallelBatches $MaxParallelShards -BootstrapBytesPerSecondPerWorker $bootstrapBytesPerSecondPerWorker
                if ($ShowProgress) {
                    Write-ReconciliationBatchPassed -Stage $Stage -Work $work -TotalElapsedMilliseconds ([long]$stageStopwatch.ElapsedMilliseconds) -BatchElapsedMilliseconds ([long]$workerResult.ElapsedMilliseconds) -RemainingMilliseconds $estimatedRemainingMilliseconds
                }
            }
            catch {
                $errorMessage = [string]$_.Exception.Message
                $validationDiagnostic = $null
                $exceptionDiagnostic = $_.Exception.GetBaseException().Data['StageDiagnostic']
                if ($null -ne $exceptionDiagnostic -and $exceptionDiagnostic.kind -ceq 'preservation-ownership' -and
                    $exceptionDiagnostic.reason -cin @('unknown-owner', 'duplicate-owner')) {
                    $validationDiagnostic = [ordered]@{
                        kind = 'preservation-ownership'
                        reason = [string]$exceptionDiagnostic.reason
                        entryIndex = [int]$exceptionDiagnostic.entryIndex
                        expectedOwnerCount = [int]$exceptionDiagnostic.expectedOwnerCount
                    }
                }
                elseif ($null -ne $exceptionDiagnostic -and $exceptionDiagnostic.kind -ceq 'preservation-evidence') {
                    $checks = @($exceptionDiagnostic.failedChecks | Where-Object { $_ -cin @('source-text-mismatch', 'missing-merged-quote', 'nonliteral-merged-quote', 'missing-rationale') } | Sort-Object -CaseSensitive -Unique)
                    if ($checks.Count -gt 0) {
                        $validationDiagnostic = [ordered]@{ kind = 'preservation-evidence'; entryIndex = [int]$exceptionDiagnostic.entryIndex; failedChecks = $checks }
                    }
                }
                $responseDiagnosticPath = "$($work.OutputPath).diagnostic.json"
                $responseDiagnostic = Read-ReconciliationResponseDiagnostic -Path $responseDiagnosticPath -Stage $Stage
                if ($null -ne $responseDiagnostic -and $responseDiagnostic.phase -cne 'diagnostic-read') {
                    $failurePhase = [string]$responseDiagnostic.phase
                }
                if (-not $failureAttemptsByShardKey.ContainsKey($shardKey)) {
                    $failureAttemptsByShardKey[$shardKey] = [Collections.Generic.List[string]]::new()
                }
                $failureAttemptsByShardKey[$shardKey].Add("attempt $attempt [$failurePhase]")
                $errorsByShardKey[$shardKey] = $errorMessage
                $attemptDirectory = Join-Path $work.Directory ('attempts/attempt-{0:D3}' -f $attempt)
                $null = New-Item -ItemType Directory -Path $attemptDirectory -Force
                Write-HierarchicalJsonAtomically -Path (Join-Path $attemptDirectory 'failure.json') -Value ([ordered]@{
                    schemaVersion = 1
                    kind = 'hosted-hierarchical-reconciliation-stage-failure'
                    stage = $Stage
                    shardKey = $shardKey
                    attempt = $attempt
                    phase = $failurePhase
                    error = $errorMessage
                    output = @($workerResult.Output)
                    responseDiagnostic = $responseDiagnostic
                    validationDiagnostic = $validationDiagnostic
                })
                Remove-Item -LiteralPath $responseDiagnosticPath -Force -ErrorAction SilentlyContinue
                Remove-Item -LiteralPath $work.OutputPath -Force -ErrorAction SilentlyContinue
                if ($attempt -le $MaxRetries) {
                    Set-ReconciliationRetryCorrection -PromptPath $work.PromptPath -BasePromptBytes $promptSnapshot.Bytes -ContextPath $work.RetryContextPath -Stage $Stage -ShardKey $shardKey -FailedAttempt $attempt -ErrorMessage $errorMessage
                }
                $retry.Add($work)
                $completedPayloadBytes += [long]$work.PayloadSizeBytes
                $completedElapsedMilliseconds += [long]$workerResult.ElapsedMilliseconds
                [long]$remainingPayloadBytes = 0
                foreach ($remainingWork in @($stageWork | Where-Object { -not $completedShardKeys.Contains([string]$_.ShardKey) })) {
                    $remainingPayloadBytes += [long]$remainingWork.PayloadSizeBytes
                }
                $estimatedRemainingMilliseconds = Get-EstimatedRemainingMilliseconds -CompletedPayloadBytes $completedPayloadBytes -CompletedElapsedMilliseconds $completedElapsedMilliseconds -RemainingPayloadBytes $remainingPayloadBytes -MaxParallelBatches $MaxParallelShards -BootstrapBytesPerSecondPerWorker $bootstrapBytesPerSecondPerWorker
                if ($ShowProgress) {
                    Write-ReconciliationBatchFailure -Stage $Stage -Work $work -ErrorMessage $errorMessage -CanRetry ($attempt -le $MaxRetries) -TotalElapsedMilliseconds ([long]$stageStopwatch.ElapsedMilliseconds) -BatchElapsedMilliseconds ([long]$workerResult.ElapsedMilliseconds) -RemainingMilliseconds $estimatedRemainingMilliseconds
                }
            }
        }
        $pending = @($retry.ToArray())
    }
    if ($pending.Count -gt 0) {
        $failureDetails = @($pending | Sort-Object -Property ShardKey -CaseSensitive | ForEach-Object {
            $history = $failureAttemptsByShardKey[[string]$_.ShardKey] -join ', '
            "$($_.ShardKey): $($errorsByShardKey[[string]$_.ShardKey]) (attempt history: $history)"
        })
        throw ('Reconciliation stage `{0}` failed after {1} attempts: {2}' -f $Stage, ($MaxRetries + 1), ($failureDetails -join '; '))
    }

    $orderedResults = @($orderedShardKeys | ForEach-Object { $resultsByShardKey[$_] })
    return [pscustomobject][ordered]@{
        stage = $Stage
        shardCount = $orderedResults.Count
        cachedCount = $cachedCount
        evaluatedCount = $orderedResults.Count - $cachedCount
        results = $orderedResults
    }
}

Export-ModuleMember -Function 'Invoke-ReconciliationStageSet', 'Get-ReconciliationStageInput', 'Get-ReconciliationReservedPayloadBytes', 'Read-ReconciliationResponseDiagnostic'
