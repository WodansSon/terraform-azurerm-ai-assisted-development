[CmdletBinding()]
param(
    [ValidateSet('Text', 'Json')]
    [string]$OutputFormat = 'Text'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Import-Module (Join-Path $PSScriptRoot '../../../tools/ValidationOutput.psm1') -Force
Import-Module (Join-Path $PSScriptRoot '../modules/reconciliation/HierarchicalReconciliationState.psm1') -Force

$reconciliationRoot = Join-Path $PSScriptRoot '../../copilot-rule-catalog/assessment-reconciliation'
$cacheSchemaPath = Join-Path $reconciliationRoot 'hierarchical-reconciliation-cache.schema.json'
$runSchemaPath = Join-Path $reconciliationRoot 'hierarchical-reconciliation-run.schema.json'
$routingSchemaPath = Join-Path $reconciliationRoot 'assessment-reconciliation-routing.schema.json'
$routingPromptPath = Join-Path $PSScriptRoot '../assessment-reconciliation-prompts/AssessmentReconciliationRouting-v4.md'
$contractPath = Join-Path $reconciliationRoot 'assessment-reconciliation-v4.json'
$catalogPath = Join-Path $PSScriptRoot '../../copilot-rule-catalog/instruction-catalog.json'
$protectedRulesPath = Join-Path $PSScriptRoot '../../copilot-rule-catalog/protected-rules.json'
$executorModulePath = Join-Path $PSScriptRoot '../modules/reconciliation/ReconciliationStageExecutor.psm1'
$copilotAdapterPath = Join-Path $PSScriptRoot '../internal/reconciliation/Invoke-CopilotReconciliationStage.ps1'
$fakeEvaluatorPath = Join-Path $PSScriptRoot 'fixtures/hierarchical-reconciliation-evaluator.ps1'
$results = [Collections.Generic.List[object]]::new()
$issues = [Collections.Generic.List[string]]::new()

function Add-TestResult {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][bool]$Passed,
        [Parameter(Mandatory = $true)][string]$Detail
    )

    $results.Add([pscustomobject]@{ name = $Name; status = if ($Passed) { 'passed' } else { 'failed' }; detail = $Detail })
    if (-not $Passed) {
        $issues.Add("$Name`: $Detail")
    }
}

function Write-TestProgress {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][string]$Detail
    )

    if ($OutputFormat -eq 'Text') {
        Write-Host (Format-ValidationStatusLine -Status 'running' -Name $Name -Detail $Detail -NameWidth 42)
    }
}

function Test-JsonInstance {
    param(
        [Parameter(Mandatory = $true)][object]$Value,
        [Parameter(Mandatory = $true)][string]$SchemaPath
    )

    if (-not (Test-Path -LiteralPath $SchemaPath -PathType Leaf)) {
        return $false
    }
    try {
        return [bool](($Value | ConvertTo-Json -Depth 30) | Test-Json -SchemaFile $SchemaPath -ErrorAction Stop)
    }
    catch {
        return $false
    }
}

if ($OutputFormat -eq 'Text') {
    Write-ValidationSectionHeader -Title 'Hosted reconciliation stage executor'
}

$sha256 = 'a' * 64
$identity = [ordered]@{
    payloadSha256 = $sha256
    catalogContentSha256 = $sha256
    protectedRulesContentSha256 = $sha256
    contractContentSha256 = $sha256
    promptContentSha256 = $sha256
    schemaContentSha256 = $sha256
    evaluator = 'script:fixture'
    model = 'fixture-model'
    reasoningEffort = 'high'
}
$validCache = [ordered]@{
    '$schema' = 'hierarchical-reconciliation-cache.schema.json'
    schemaVersion = 2
    kind = 'hosted-hierarchical-reconciliation-cache'
    entries = @(
        [ordered]@{
            stage = 'routing'
            shardKey = "routing:$sha256"
            cacheKey = $sha256
            identity = $identity
            result = [ordered]@{ schemaVersion = 1; kind = 'hosted-assessment-routing-result'; shardKey = "routing:$sha256"; groups = @() }
        }
    )
}
$legacyCache = [ordered]@{
    schemaVersion = 1
    kind = 'hosted-assessment-reconciliation-cache'
    entries = @()
}
$validRun = [ordered]@{
    '$schema' = 'hierarchical-reconciliation-run.schema.json'
    schemaVersion = 2
    kind = 'hosted-hierarchical-reconciliation-run'
    runId = 'a' * 32
    createdAt = '2026-10-11T12:00:00Z'
    authority = [ordered]@{
        inputSetSha256 = $sha256
        catalogContentSha256 = $sha256
        protectedRulesContentSha256 = $sha256
        contractContentSha256 = $sha256
        evaluator = 'script:fixture'
        model = 'fixture-model'
        reasoningEffort = 'high'
    }
    stages = @(
        [ordered]@{
            stage = 'routing'
            shardKey = "routing:$sha256"
            cacheKey = $sha256
            status = 'completed'
            resultRelativePath = 'stages/routing/routing-result.json'
        }
    )
}

Write-TestProgress -Name 'hierarchical-cache-contract-files' -Detail 'Checking the v2 cache schema, run schema, and dedicated executor module'
$contractFilesPresent = (Test-Path -LiteralPath $cacheSchemaPath -PathType Leaf) -and
    (Test-Path -LiteralPath $runSchemaPath -PathType Leaf) -and
    (Test-Path -LiteralPath $executorModulePath -PathType Leaf)
Add-TestResult -Name 'hierarchical-cache-contract-files' -Passed $contractFilesPresent -Detail 'The v2 cache schema, v2 run-manifest schema, and dedicated stage-executor module exist.'
Write-TestProgress -Name 'hierarchical-cache-v2-valid' -Detail 'Validating one stage-scoped hierarchical cache object'
Add-TestResult -Name 'hierarchical-cache-v2-valid' -Passed (Test-JsonInstance -Value $validCache -SchemaPath $cacheSchemaPath) -Detail 'A stage-scoped v2 hierarchical cache object satisfies the cache schema.'
Write-TestProgress -Name 'legacy-cache-v1-rejected' -Detail 'Rejecting the legacy source-lane cache kind and schema version'
Add-TestResult -Name 'legacy-cache-v1-rejected' -Passed (-not (Test-JsonInstance -Value $legacyCache -SchemaPath $cacheSchemaPath)) -Detail 'The legacy source-lane reconciliation cache kind and schema version are invalid under the hierarchical cache contract.'
Write-TestProgress -Name 'hierarchical-run-v2-valid' -Detail 'Validating one authority-bound hierarchical run manifest'
Add-TestResult -Name 'hierarchical-run-v2-valid' -Passed (Test-JsonInstance -Value $validRun -SchemaPath $runSchemaPath) -Detail 'A v2 hierarchical run manifest binds authority and completed stage artifacts.'

$cacheBehaviorValid = $false
$legacyCacheReadRejected = $false
$resumeBehaviorValid = $false
$stageInvocationContract = $false
$stageExecutionAndReuseValid = $false
$stageRetryIsolationValid = $false
$stageFailureRetentionValid = $false
$stagePayloadBudgetValid = $false
if (Test-Path -LiteralPath $executorModulePath -PathType Leaf) {
    Import-Module $executorModulePath -Force
    Write-TestProgress -Name 'hierarchical-cache-identity-and-reuse' -Detail 'Checking exact stage identity, cache reuse, and hash invalidation'
    $stageIdentity = New-ReconciliationStageCacheIdentity -Stage 'routing' -ShardKey "routing:$sha256" -PayloadSha256 $sha256 -CatalogContentSha256 $sha256 -ProtectedRulesContentSha256 $sha256 -ContractContentSha256 $sha256 -PromptContentSha256 $sha256 -SchemaContentSha256 $sha256 -Evaluator 'script:fixture' -Model 'fixture-model' -ReasoningEffort 'high'
    $validCache.entries[0].cacheKey = [string]$stageIdentity.cacheKey
    $validCache.entries[0].identity = $stageIdentity.identity
    $tempRoot = Join-Path ([IO.Path]::GetTempPath()) ('hosted-reconciliation-stage-executor-test-' + [guid]::NewGuid().ToString('N'))
    $null = New-Item -ItemType Directory -Path $tempRoot -Force
    try {
        $cachePath = Join-Path $tempRoot 'hierarchical-cache.json'
        $legacyCachePath = Join-Path $tempRoot 'legacy-cache.json'
        $runPath = Join-Path $tempRoot 'hierarchical-run.json'
        [IO.File]::WriteAllText($cachePath, (($validCache | ConvertTo-Json -Depth 30) + "`n"), [Text.UTF8Encoding]::new($false))
        [IO.File]::WriteAllText($legacyCachePath, (($legacyCache | ConvertTo-Json -Depth 30) + "`n"), [Text.UTF8Encoding]::new($false))
        [IO.File]::WriteAllText($runPath, (($validRun | ConvertTo-Json -Depth 30) + "`n"), [Text.UTF8Encoding]::new($false))
        $cache = Read-HierarchicalReconciliationCache -Path $cachePath -SchemaPath $cacheSchemaPath
        $cachedResult = Get-HierarchicalCachedResult -Cache $cache -StageIdentity $stageIdentity -ResultSchemaPath (Join-Path $reconciliationRoot 'assessment-reconciliation-routing.schema.json')
        $changedIdentity = New-ReconciliationStageCacheIdentity -Stage 'routing' -ShardKey "routing:$sha256" -PayloadSha256 $sha256 -CatalogContentSha256 $sha256 -ProtectedRulesContentSha256 $sha256 -ContractContentSha256 $sha256 -PromptContentSha256 ('b' * 64) -SchemaContentSha256 $sha256 -Evaluator 'script:fixture' -Model 'fixture-model' -ReasoningEffort 'high'
        $wrongStageIdentity = New-ReconciliationStageCacheIdentity -Stage 'consolidation' -ShardKey "consolidation:$sha256" -PayloadSha256 $sha256 -CatalogContentSha256 $sha256 -ProtectedRulesContentSha256 $sha256 -ContractContentSha256 $sha256 -PromptContentSha256 $sha256 -SchemaContentSha256 $sha256 -Evaluator 'script:fixture' -Model 'fixture-model' -ReasoningEffort 'high'
        $cacheBehaviorValid = [string]$stageIdentity.cacheKey -match '^[0-9a-f]{64}$' -and
            $null -ne $cachedResult -and
            $null -eq (Get-HierarchicalCachedResult -Cache $cache -StageIdentity $changedIdentity -ResultSchemaPath (Join-Path $reconciliationRoot 'assessment-reconciliation-routing.schema.json')) -and
            $null -eq (Get-HierarchicalCachedResult -Cache $cache -StageIdentity $wrongStageIdentity -ResultSchemaPath (Join-Path $reconciliationRoot 'assessment-reconciliation-consolidation.schema.json'))
        Write-TestProgress -Name 'legacy-cache-read-rejected' -Detail 'Reading a legacy cache and requiring an incompatibility failure'
        try {
            $null = Read-HierarchicalReconciliationCache -Path $legacyCachePath -SchemaPath $cacheSchemaPath
        }
        catch {
            $legacyCacheReadRejected = $_.Exception.Message -like '*incompatible*hierarchical reconciliation cache*'
        }
        Write-TestProgress -Name 'hierarchical-resume-authority' -Detail 'Reading a v2 resume manifest with exact current-run authority'
        $run = Read-HierarchicalReconciliationRunManifest -Path $runPath -SchemaPath $runSchemaPath -ExpectedAuthority $validRun.authority
        $resumeBehaviorValid = [string]$run.runId -ceq ('a' * 32)

        Write-TestProgress -Name 'hierarchical-stage-invocation' -Detail 'Evaluating two routing shards through one generic stage executor'
        $stageCommand = Get-Command Invoke-ReconciliationStageSet -ErrorAction SilentlyContinue
        $stageInvocationContract = $null -ne $stageCommand
        if ($stageInvocationContract) {
            $firstShardHash = 'b' * 64
            $secondShardHash = 'c' * 64
            $shards = @(
                [pscustomobject][ordered]@{ shardKey = "routing:$firstShardHash"; byteCount = 20; payload = [ordered]@{ nodes = @() } },
                [pscustomobject][ordered]@{ shardKey = "routing:$secondShardHash"; byteCount = 20; payload = [ordered]@{ nodes = @() } }
            )
            $stageCachePath = Join-Path $tempRoot 'stage-cache.json'
            $stageRunDirectory = Join-Path $tempRoot 'stage-run'
            $stageParameters = @{
                Stage = 'routing'
                Shards = $shards
                RunDirectory = $stageRunDirectory
                CachePath = $stageCachePath
                CacheSchemaPath = $cacheSchemaPath
                ResultSchemaPath = $routingSchemaPath
                PromptPath = $routingPromptPath
                CatalogPath = $catalogPath
                ProtectedRulesPath = $protectedRulesPath
                ContractPath = $contractPath
                EvaluatorScriptPath = $fakeEvaluatorPath
                Model = 'fixture-model'
                ReasoningEffort = 'high'
                MaxRetries = 0
                RetryDelayMilliseconds = 0
                MaxParallelShards = 2
            }
            $firstStageRun = Invoke-ReconciliationStageSet @stageParameters
            $env:RECONCILIATION_FAIL_ALL = '1'
            try {
                $secondStageRun = Invoke-ReconciliationStageSet @stageParameters
            }
            finally {
                Remove-Item Env:RECONCILIATION_FAIL_ALL -ErrorAction SilentlyContinue
            }
            $writtenStageCache = Read-HierarchicalReconciliationCache -Path $stageCachePath -SchemaPath $cacheSchemaPath
            $stageExecutionAndReuseValid = [int]$firstStageRun.shardCount -eq 2 -and
                [int]$firstStageRun.evaluatedCount -eq 2 -and
                [int]$firstStageRun.cachedCount -eq 0 -and
                [int]$secondStageRun.shardCount -eq 2 -and
                [int]$secondStageRun.evaluatedCount -eq 0 -and
                [int]$secondStageRun.cachedCount -eq 2 -and
                @($secondStageRun.results).Count -eq 2 -and
                @($writtenStageCache.entries).Count -eq 2

            Write-TestProgress -Name 'hierarchical-stage-retry-isolation' -Detail 'Retrying one failed routing shard without rerunning its successful sibling'
            $retryStageParameters = @{} + $stageParameters
            $retryStageParameters.CachePath = Join-Path $tempRoot 'retry-stage-cache.json'
            $retryStageParameters.RunDirectory = Join-Path $tempRoot 'retry-stage-run'
            $retryStageParameters.MaxRetries = 1
            $env:RECONCILIATION_FAIL_ONCE_SHARD = "routing:$secondShardHash"
            try {
                $retryStageRun = Invoke-ReconciliationStageSet @retryStageParameters
            }
            finally {
                Remove-Item Env:RECONCILIATION_FAIL_ONCE_SHARD -ErrorAction SilentlyContinue
            }
            $firstRetryShardDirectory = Join-Path $retryStageParameters.RunDirectory "stages/routing/$firstShardHash"
            $secondRetryShardDirectory = Join-Path $retryStageParameters.RunDirectory "stages/routing/$secondShardHash"
            $retryStageCache = Read-HierarchicalReconciliationCache -Path $retryStageParameters.CachePath -SchemaPath $cacheSchemaPath
            $stageRetryIsolationValid = [int]$retryStageRun.evaluatedCount -eq 2 -and
                @(Get-ChildItem -LiteralPath (Join-Path $firstRetryShardDirectory 'calls') -Filter '*.marker').Count -eq 1 -and
                @(Get-ChildItem -LiteralPath (Join-Path $secondRetryShardDirectory 'calls') -Filter '*.marker').Count -eq 2 -and
                (Test-Path -LiteralPath (Join-Path $secondRetryShardDirectory 'attempts/attempt-001/failure.json') -PathType Leaf) -and
                @($retryStageCache.entries).Count -eq 2

            Write-TestProgress -Name 'hierarchical-stage-failure-retention' -Detail 'Retaining successful sibling state and every terminally failed attempt'
            $failureStageParameters = @{} + $stageParameters
            $failureStageParameters.CachePath = Join-Path $tempRoot 'failure-stage-cache.json'
            $failureStageParameters.RunDirectory = Join-Path $tempRoot 'failure-stage-run'
            $failureStageParameters.MaxRetries = 1
            $failureError = ''
            $env:RECONCILIATION_FAIL_SHARD = "routing:$secondShardHash"
            try {
                $null = Invoke-ReconciliationStageSet @failureStageParameters
            }
            catch {
                $failureError = [string]$_.Exception.Message
            }
            finally {
                Remove-Item Env:RECONCILIATION_FAIL_SHARD -ErrorAction SilentlyContinue
            }
            $firstFailureShardDirectory = Join-Path $failureStageParameters.RunDirectory "stages/routing/$firstShardHash"
            $secondFailureShardDirectory = Join-Path $failureStageParameters.RunDirectory "stages/routing/$secondShardHash"
            $failureStageCache = Read-HierarchicalReconciliationCache -Path $failureStageParameters.CachePath -SchemaPath $cacheSchemaPath
            $stageFailureRetentionValid = $failureError -like "*routing:$secondShardHash*Synthetic terminal failure*" -and
                @($failureStageCache.entries).Count -eq 1 -and
                (Test-Path -LiteralPath (Join-Path $firstFailureShardDirectory 'stage-result.json') -PathType Leaf) -and
                (Test-Path -LiteralPath (Join-Path $secondFailureShardDirectory 'attempts/attempt-001/failure.json') -PathType Leaf) -and
                (Test-Path -LiteralPath (Join-Path $secondFailureShardDirectory 'attempts/attempt-002/failure.json') -PathType Leaf)

            Write-TestProgress -Name 'hierarchical-stage-payload-budget' -Detail 'Rejecting a shard whose complete evaluator envelope exceeds the hard byte budget'
            $budgetStageParameters = @{} + $stageParameters
            $budgetStageParameters.CachePath = Join-Path $tempRoot 'budget-stage-cache.json'
            $budgetStageParameters.RunDirectory = Join-Path $tempRoot 'budget-stage-run'
            $budgetStageParameters.EvaluatorPayloadBudgetBytes = 1
            try {
                $null = Invoke-ReconciliationStageSet @budgetStageParameters
            }
            catch {
                $stagePayloadBudgetValid = $_.Exception.Message -like '*requires*bytes and exceeds the evaluator payload budget of 1 bytes*'
            }
        }
    }
    finally {
        Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}
Add-TestResult -Name 'hierarchical-cache-identity-and-reuse' -Passed $cacheBehaviorValid -Detail 'Cache reuse requires an exact stage, shard, payload, authority, prompt, schema, evaluator, model, and reasoning identity.'
Add-TestResult -Name 'legacy-cache-read-rejected' -Passed $legacyCacheReadRejected -Detail 'Reading a legacy cache fails with an explicit incompatible hierarchical-cache diagnostic instead of migrating or reusing it.'
Add-TestResult -Name 'hierarchical-resume-authority' -Passed $resumeBehaviorValid -Detail 'A v2 resume manifest is accepted only through the hierarchical run schema and exact authority binding.'
Add-TestResult -Name 'hierarchical-stage-invocation' -Passed $stageInvocationContract -Detail 'One generic stage executor owns bounded shard evaluation for routing, consolidation, and synthesis.'
Write-TestProgress -Name 'hierarchical-stage-cache-reuse' -Detail 'Re-running identical routing shards and requiring zero evaluator calls'
Add-TestResult -Name 'hierarchical-stage-cache-reuse' -Passed $stageExecutionAndReuseValid -Detail 'Two routing shards evaluate once, persist as v2 cache entries, and reuse without a second evaluator call.'
Add-TestResult -Name 'hierarchical-stage-retry-isolation' -Passed $stageRetryIsolationValid -Detail 'Only the failed routing shard retries while its successful sibling evaluates once and both final results enter the v2 cache.'
Add-TestResult -Name 'hierarchical-stage-failure-retention' -Passed $stageFailureRetentionValid -Detail 'Terminal failure retains the successful sibling cache/result and one diagnostic artifact for every failed attempt.'
Add-TestResult -Name 'hierarchical-stage-payload-budget' -Passed $stagePayloadBudgetValid -Detail 'The executor measures the complete shard envelope and fails before evaluation when it exceeds the configured byte budget.'
Write-TestProgress -Name 'copilot-stage-adapter-contract' -Detail 'Checking isolated Copilot invocation, model binding, and JSON result extraction'
$copilotAdapterContract = $false
if (Test-Path -LiteralPath $copilotAdapterPath -PathType Leaf) {
    $copilotAdapterContent = Get-Content -LiteralPath $copilotAdapterPath -Raw
    $copilotAdapterContract = $copilotAdapterContent -match '--no-custom-instructions' -and
        $copilotAdapterContent -match '--disable-builtin-mcps' -and
        $copilotAdapterContent -match '--no-ask-user' -and
        $copilotAdapterContent -match '--disallow-temp-dir' -and
        $copilotAdapterContent -match "'--output-format',\s*'json'" -and
        $copilotAdapterContent -match '\$assistantMessage\.model' -and
        $copilotAdapterContent -match '\[IO\.File\]::WriteAllText\(\$OutputPath'
}
Add-TestResult -Name 'copilot-stage-adapter-contract' -Passed $copilotAdapterContract -Detail 'The production adapter isolates Copilot, verifies the configured model, extracts assistant JSON, and writes only the requested stage result.'

$status = if ($issues.Count -eq 0) { 'passed' } else { 'failed' }
$summary = [ordered]@{ status = $status; testCount = $results.Count; issueCount = $issues.Count; tests = $results.ToArray(); issues = $issues.ToArray() }
if ($OutputFormat -eq 'Json') {
    $summary | ConvertTo-Json -Depth 8
}
else {
    Write-ValidationSectionHeader -Title 'Hosted reconciliation stage executor test summary'
    Write-ValidationSummary -Fields ([ordered]@{ Status = $status.ToUpperInvariant(); Tests = $results.Count; Issues = $issues.Count })
    Write-ValidationSectionHeader -Title 'Reconciliation stage executor tests'
    Write-ValidationTwoColumnTable -Rows @($results | ForEach-Object { [pscustomobject]@{ Status = $_.status; Test = $_.name } }) -FirstHeader 'Status' -FirstProperty 'Status' -SecondHeader 'Test' -SecondProperty 'Test' -UppercaseFirst
    if ($issues.Count -gt 0) {
        Write-ValidationSectionHeader -Title 'Failures'
        foreach ($issue in $issues) {
            Write-Output "  - $issue"
        }
    }
    Complete-ValidationTextOutput
}
if ($status -ne 'passed') {
    exit 1
}
