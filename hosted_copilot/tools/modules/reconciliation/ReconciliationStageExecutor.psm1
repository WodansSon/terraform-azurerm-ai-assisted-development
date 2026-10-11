Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Import-Module (Join-Path $PSScriptRoot '../shared/HostedToolkit.Helpers.psm1')
Import-Module (Join-Path $PSScriptRoot 'HierarchicalReconciliationState.psm1')

function Invoke-ReconciliationStageSet {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][ValidateSet('routing', 'consolidation', 'synthesis', 'adjudication')][string]$Stage,
        [Parameter(Mandatory = $true)][object[]]$Shards,
        [Parameter(Mandatory = $true)][string]$RunDirectory,
        [Parameter(Mandatory = $true)][string]$CachePath,
        [Parameter(Mandatory = $true)][string]$CacheSchemaPath,
        [Parameter(Mandatory = $true)][string]$ResultSchemaPath,
        [Parameter(Mandatory = $true)][string]$PromptPath,
        [Parameter(Mandatory = $true)][string]$CatalogPath,
        [Parameter(Mandatory = $true)][string]$ProtectedRulesPath,
        [Parameter(Mandatory = $true)][string]$ContractPath,
        [Parameter(Mandatory = $true)][string]$EvaluatorScriptPath,
        [scriptblock]$ResultValidator,
        [string]$EvaluatorCommand = 'copilot',
        [Parameter(Mandatory = $true)][string]$Model,
        [Parameter(Mandatory = $true)][ValidateSet('low', 'medium', 'high', 'xhigh')][string]$ReasoningEffort,
        [ValidateRange(0, 3)][int]$MaxRetries = 1,
        [ValidateRange(0, 60000)][int]$RetryDelayMilliseconds = 1000,
        [ValidateRange(1, 8)][int]$MaxParallelShards = 3,
        [ValidateRange(1, [int]::MaxValue)][int]$EvaluatorPayloadBudgetBytes = 393216
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
    $contractSnapshot = Get-FileSnapshot -Path $resolvedPaths.ContractPath
    $evaluatorSnapshot = Get-FileSnapshot -Path $resolvedPaths.EvaluatorScriptPath
    $evaluatorIdentity = 'script:' + $evaluatorSnapshot.Sha256 + ';command:' + $EvaluatorCommand
    $cache = Read-HierarchicalReconciliationCache -Path $CachePath -SchemaPath $resolvedPaths.CacheSchemaPath
    $stageDirectory = Join-Path ([IO.Path]::GetFullPath($RunDirectory)) "stages/$Stage"
    $null = New-Item -ItemType Directory -Path $stageDirectory -Force

    $workByShardKey = @{}
    $orderedShardKeys = [Collections.Generic.List[string]]::new()
    foreach ($shard in @($Shards | Sort-Object -Property shardKey -CaseSensitive)) {
        $shardKey = [string]$shard.shardKey
        if ($shardKey -cnotmatch ('^' + [regex]::Escape($Stage) + ':[0-9a-f]{64}$')) {
            throw "Reconciliation stage `$Stage` received invalid shard key `$shardKey`."
        }
        if ($workByShardKey.ContainsKey($shardKey)) {
            throw "Reconciliation stage `$Stage` received duplicate shard key `$shardKey`."
        }
        $stageInput = [ordered]@{
            schemaVersion = 1
            kind = 'hosted-hierarchical-reconciliation-stage-input'
            stage = $Stage
            shardKey = $shardKey
            payload = $shard.payload
        }
        $identity = New-ReconciliationStageCacheIdentity -Stage $Stage -ShardKey $shardKey -PayloadSha256 (Get-JsonSnapshotSha256 -Value $stageInput) -CatalogContentSha256 $catalogSnapshot.Sha256 -ProtectedRulesContentSha256 $protectedRulesSnapshot.Sha256 -ContractContentSha256 $contractSnapshot.Sha256 -PromptContentSha256 $promptSnapshot.Sha256 -SchemaContentSha256 $resultSchemaSnapshot.Sha256 -Evaluator $evaluatorIdentity -Model $Model -ReasoningEffort $ReasoningEffort
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
        [IO.File]::WriteAllBytes($contractArtifactPath, $contractSnapshot.Bytes)
        [IO.File]::WriteAllBytes($schemaArtifactPath, $resultSchemaSnapshot.Bytes)
        [IO.File]::WriteAllBytes($promptArtifactPath, $promptSnapshot.Bytes)
        $payloadBytes = (Get-Item -LiteralPath $inputPath).Length + $catalogSnapshot.Bytes.Length + $protectedRulesSnapshot.Bytes.Length + $contractSnapshot.Bytes.Length + $promptSnapshot.Bytes.Length + $resultSchemaSnapshot.Bytes.Length
        if ($payloadBytes -gt $EvaluatorPayloadBudgetBytes) {
            throw "Reconciliation stage `$Stage` shard `$shardKey` requires $payloadBytes bytes and exceeds the evaluator payload budget of $EvaluatorPayloadBudgetBytes bytes."
        }
        $cachedResult = Get-HierarchicalCachedResult -Cache $cache -StageIdentity $identity -ResultSchemaPath $resolvedPaths.ResultSchemaPath
        if ($null -ne $cachedResult -and $null -ne $ResultValidator) {
            try {
                & $ResultValidator $shard.payload $cachedResult
            }
            catch {
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
            PayloadSizeBytes = [long]$payloadBytes
            CachedResult = $cachedResult
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
            $resultsByShardKey[$shardKey] = [pscustomobject][ordered]@{ stage = $Stage; shardKey = $shardKey; cacheKey = [string]$work.Identity.cacheKey; reused = $true; result = $work.CachedResult; directory = $work.Directory }
            $cachedCount++
        }
    }

    $pending = @($orderedShardKeys | Where-Object { -not $resultsByShardKey.ContainsKey($_) } | ForEach-Object { $workByShardKey[$_] })
    $errorsByShardKey = @{}
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
        $workerResults = @($pending | ForEach-Object -Parallel {
            $work = $_
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
                $output = @(& pwsh -NoProfile -File $using:workerEvaluatorScriptPath @parameters 2>&1)
                if ($LASTEXITCODE -ne 0) {
                    throw "Evaluator script exited with code $LASTEXITCODE`: $(($output | Out-String).Trim())"
                }
                [pscustomobject][ordered]@{ shardKey = $work.ShardKey; succeeded = $true; output = @($output | ForEach-Object { [string]$_ }); error = '' }
            }
            catch {
                [pscustomobject][ordered]@{ shardKey = $work.ShardKey; succeeded = $false; output = @($output | ForEach-Object { [string]$_ }); error = [string]$_.Exception.Message }
            }
        } -ThrottleLimit $MaxParallelShards)

        $retry = [Collections.Generic.List[object]]::new()
        foreach ($workerResult in $workerResults) {
            $shardKey = [string]$workerResult.shardKey
            $work = $workByShardKey[$shardKey]
            try {
                if (-not [bool]$workerResult.succeeded) {
                    throw [string]$workerResult.error
                }
                if (-not (Test-Path -LiteralPath $work.OutputPath -PathType Leaf)) {
                    throw ('Evaluator did not write a {0} result for shard `{1}`.' -f $Stage, $shardKey)
                }
                $resultJson = Get-Content -LiteralPath $work.OutputPath -Raw
                Test-HierarchicalJsonSchema -Json $resultJson -SchemaPath $resolvedPaths.ResultSchemaPath -Label ('{0} result for shard `{1}`' -f $Stage, $shardKey)
                $result = $resultJson | ConvertFrom-Json -DateKind String
                $resultShardKeyProperty = $result.PSObject.Properties['shardKey']
                if ($Stage -in @('routing', 'consolidation') -and ($null -eq $resultShardKeyProperty -or [string]$resultShardKeyProperty.Value -cne $shardKey)) {
                    $resultShardKey = if ($null -eq $resultShardKeyProperty) { '<missing>' } else { [string]$resultShardKeyProperty.Value }
                    throw ('{0} result shard key `{1}` does not match `{2}`.' -f $Stage, $resultShardKey, $shardKey)
                }
                if ($null -ne $ResultValidator) {
                    & $ResultValidator $work.Payload $result
                }
                $cache = Set-HierarchicalCachedResult -Path $CachePath -SchemaPath $resolvedPaths.CacheSchemaPath -ResultSchemaPath $resolvedPaths.ResultSchemaPath -StageIdentity $work.Identity -Result $result
                $resultsByShardKey[$shardKey] = [pscustomobject][ordered]@{ stage = $Stage; shardKey = $shardKey; cacheKey = [string]$work.Identity.cacheKey; reused = $false; result = $result; directory = $work.Directory }
                $errorsByShardKey.Remove($shardKey)
            }
            catch {
                $errorMessage = [string]$_.Exception.Message
                $errorsByShardKey[$shardKey] = $errorMessage
                $attemptDirectory = Join-Path $work.Directory ('attempts/attempt-{0:D3}' -f $attempt)
                $null = New-Item -ItemType Directory -Path $attemptDirectory -Force
                Write-HierarchicalJsonAtomically -Path (Join-Path $attemptDirectory 'failure.json') -Value ([ordered]@{ schemaVersion = 1; kind = 'hosted-hierarchical-reconciliation-stage-failure'; stage = $Stage; shardKey = $shardKey; attempt = $attempt; error = $errorMessage; output = @($workerResult.output) })
                Remove-Item -LiteralPath $work.OutputPath -Force -ErrorAction SilentlyContinue
                $retry.Add($work)
            }
        }
        $pending = @($retry.ToArray())
    }
    if ($pending.Count -gt 0) {
        $failureDetails = @($pending | Sort-Object -Property ShardKey -CaseSensitive | ForEach-Object { "$($_.ShardKey): $($errorsByShardKey[[string]$_.ShardKey])" })
        throw "Reconciliation stage `$Stage` failed after $($MaxRetries + 1) attempts: $($failureDetails -join '; ')"
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

Export-ModuleMember -Function 'Invoke-ReconciliationStageSet'
