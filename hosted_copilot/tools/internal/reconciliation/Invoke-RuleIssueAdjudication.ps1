[CmdletBinding()]
param(
    [string]$RepositoryRoot = (Join-Path $PSScriptRoot '../../../..'),
    [Parameter(Mandatory = $true)][string[]]$ComponentPaths,
    [Parameter(Mandatory = $true)][string]$OutputPath,
    [string]$InputSchemaPath = (Join-Path $PSScriptRoot '../../../copilot-rule-catalog/assessment-reconciliation/rule-issue-adjudication-input-v4.schema.json'),
    [string]$DraftSchemaPath = (Join-Path $PSScriptRoot '../../../copilot-rule-catalog/assessment-reconciliation/rule-issue-adjudication-draft-v4.schema.json'),
    [string]$ContractSchemaPath = (Join-Path $PSScriptRoot '../../../copilot-rule-catalog/assessment-reconciliation/rule-issue-adjudication-contract.schema.json'),
    [string]$AdjudicationContractPath = (Join-Path $PSScriptRoot '../../../copilot-rule-catalog/assessment-reconciliation/rule-issue-adjudication-v4.json'),
    [string]$PromptPath = (Join-Path $PSScriptRoot '../../assessment-reconciliation-prompts/RuleIssueAdjudication-v4.md'),
    [string]$CatalogPath = (Join-Path $PSScriptRoot '../../../copilot-rule-catalog/instruction-catalog.json'),
    [string]$ProtectedRulesPath = (Join-Path $PSScriptRoot '../../../copilot-rule-catalog/protected-rules.json'),
    [string]$CacheSchemaPath = (Join-Path $PSScriptRoot '../../../copilot-rule-catalog/assessment-reconciliation/hierarchical-reconciliation-cache.schema.json'),
    [string]$RunSchemaPath = (Join-Path $PSScriptRoot '../../../copilot-rule-catalog/assessment-reconciliation/hierarchical-reconciliation-run.schema.json'),
    [string]$CacheDirectory = (Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'hosted-workbench/hierarchical-rule-issue-adjudication-cache'),
    [string]$ResumeRunDirectory,
    [string]$EvaluatorCommand = 'copilot',
    [string]$EvaluatorScriptPath,
    [ValidateNotNullOrEmpty()][string]$Model,
    [ValidateSet('low', 'medium', 'high', 'xhigh')][string]$ReasoningEffort,
    [ValidateRange(0, 3)][int]$MaxRetries = 1,
    [ValidateRange(1, 8)][int]$MaxParallelShards = 3,
    [ValidateRange(1, [int]::MaxValue)][int]$EvaluatorPayloadBudgetBytes = 393216,
    [ValidateSet('Text', 'Json')][string]$OutputFormat = 'Text',
    [switch]$Quiet
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$helpersPath = Join-Path $PSScriptRoot '../../modules/shared/HostedToolkit.Helpers.psm1'
$validationOutputPath = Join-Path $PSScriptRoot '../../../../tools/ValidationOutput.psm1'
$stateModulePath = Join-Path $PSScriptRoot '../../modules/reconciliation/HierarchicalReconciliationState.psm1'
$executorModulePath = Join-Path $PSScriptRoot '../../modules/reconciliation/ReconciliationStageExecutor.psm1'
$adjudicationModulePath = Join-Path $PSScriptRoot '../../modules/reconciliation/RuleIssueAdjudication.psm1'
$defaultEvaluatorScriptPath = Join-Path $PSScriptRoot 'Invoke-CopilotReconciliationStage.ps1'
Import-Module $helpersPath -Force
Import-Module $validationOutputPath -Force
Import-Module $stateModulePath -Force
Import-Module $executorModulePath -Force
Import-Module $adjudicationModulePath -Force

$llmProfile = Resolve-HostedLlmProfile -Profile normal -Model $Model -ReasoningEffort $ReasoningEffort
$Model = $llmProfile.model
$ReasoningEffort = $llmProfile.reasoningEffort

$stopwatch = [Diagnostics.Stopwatch]::StartNew()
$resolvedRepositoryRoot = [IO.Path]::GetFullPath($RepositoryRoot).TrimEnd([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar)
$repositoryPrefix = $resolvedRepositoryRoot + [IO.Path]::DirectorySeparatorChar
$resolvedOutputPath = [IO.Path]::GetFullPath($OutputPath)
$resolvedCacheDirectory = [IO.Path]::GetFullPath($CacheDirectory)
foreach ($externalPath in @($resolvedOutputPath, $resolvedCacheDirectory)) {
    if ($externalPath.StartsWith($repositoryPrefix, [StringComparison]::OrdinalIgnoreCase)) {
        throw 'Rule Issue adjudication output and cache paths must be outside the repository root'
    }
}
$resolvedResumeRunDirectory = if ([string]::IsNullOrWhiteSpace($ResumeRunDirectory)) { $null } else { [IO.Path]::GetFullPath($ResumeRunDirectory) }
if ($null -ne $resolvedResumeRunDirectory -and $resolvedResumeRunDirectory.StartsWith($repositoryPrefix, [StringComparison]::OrdinalIgnoreCase)) {
    throw 'ResumeRunDirectory must be outside the repository root'
}

$requiredPaths = [ordered]@{
    InputSchemaPath = [IO.Path]::GetFullPath($InputSchemaPath)
    DraftSchemaPath = [IO.Path]::GetFullPath($DraftSchemaPath)
    ContractSchemaPath = [IO.Path]::GetFullPath($ContractSchemaPath)
    AdjudicationContractPath = [IO.Path]::GetFullPath($AdjudicationContractPath)
    PromptPath = [IO.Path]::GetFullPath($PromptPath)
    CatalogPath = [IO.Path]::GetFullPath($CatalogPath)
    ProtectedRulesPath = [IO.Path]::GetFullPath($ProtectedRulesPath)
    CacheSchemaPath = [IO.Path]::GetFullPath($CacheSchemaPath)
    RunSchemaPath = [IO.Path]::GetFullPath($RunSchemaPath)
    SavedAssessmentSchemaPath = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../../copilot-rule-catalog/assessment-reconciliation/saved-rule-assessment.schema.json'))
}
foreach ($requiredPath in $requiredPaths.Values) {
    if (-not (Test-Path -LiteralPath $requiredPath -PathType Leaf)) {
        throw "Required Rule Issue adjudication file was not found: $requiredPath"
    }
}
$adjudicationContractJson = Get-Content -LiteralPath $requiredPaths.AdjudicationContractPath -Raw
if (-not ($adjudicationContractJson | Test-Json -SchemaFile $requiredPaths.ContractSchemaPath -ErrorAction Stop)) {
    throw 'Rule Issue adjudication contract does not satisfy its schema'
}
$resolvedComponentPaths = @($ComponentPaths | ForEach-Object { [IO.Path]::GetFullPath($_) })
if ($resolvedComponentPaths.Count -eq 0) {
    throw 'Rule Issue adjudication requires at least one component'
}

$components = [Collections.Generic.List[object]]::new()
$componentIds = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
foreach ($componentPath in $resolvedComponentPaths) {
    $componentJson = Get-Content -LiteralPath $componentPath -Raw
    if (-not ($componentJson | Test-Json -SchemaFile $requiredPaths.InputSchemaPath -ErrorAction Stop)) {
        throw "Rule Issue adjudication input does not satisfy its schema: $componentPath"
    }
    $component = $componentJson | ConvertFrom-Json -DateKind String
    if ($null -ne $component.PSObject.Properties['evaluationPhase']) { throw 'Partial adjudication phases are internal and cannot replace a complete component input' }
    if (-not $componentIds.Add([string]$component.componentId)) {
        throw "Rule Issue adjudication contains duplicate component ID: $($component.componentId)"
    }
    $components.Add($component)
}
$orderedComponents = @($components.ToArray() | Sort-Object -Property componentId -CaseSensitive)
$shards = @($orderedComponents | ForEach-Object {
    $payloadHash = Get-JsonSnapshotSha256 -Value $_
    [pscustomobject][ordered]@{ shardKey = "adjudication:$payloadHash"; payload = $_ }
})

$runId = [guid]::NewGuid().ToString('N')
$runDirectory = Join-Path ([IO.Path]::GetTempPath()) "hosted-rule-issue-adjudication/$runId"
$runRepositoryRoot = Join-Path $runDirectory 'repository'
$null = New-Item -ItemType Directory -Path $runRepositoryRoot -Force
$manifestPath = Join-Path $runDirectory 'hierarchical-reconciliation-run.json'
$runCachePath = Join-Path $runDirectory 'hierarchical-reconciliation-cache.json'
$persistentCachePath = Join-Path $resolvedCacheDirectory 'hierarchical-reconciliation-cache.json'
$runCreatedAt = ConvertTo-UtcTimestamp -Value ([DateTime]::UtcNow)

$adjudicationContract = $adjudicationContractJson | ConvertFrom-Json -DateKind String
$behaviorAuthority = [Collections.Generic.List[object]]::new()
foreach ($relativePath in @($adjudicationContract.behaviorFiles | Sort-Object -CaseSensitive)) {
    $sourcePath = [IO.Path]::GetFullPath((Join-Path $resolvedRepositoryRoot ([string]$relativePath)))
    if (-not $sourcePath.StartsWith($repositoryPrefix, [StringComparison]::OrdinalIgnoreCase)) {
        throw "Rule Issue adjudication behavior path escapes the repository root: $relativePath"
    }
    if (-not (Test-Path -LiteralPath $sourcePath -PathType Leaf)) {
        throw "Rule Issue adjudication behavior file was not found: $relativePath"
    }
    $snapshot = Get-FileSnapshot -Path $sourcePath
    $destinationPath = [IO.Path]::GetFullPath((Join-Path $runRepositoryRoot ([string]$relativePath)))
    $destinationDirectory = Split-Path -Parent $destinationPath
    if (-not (Test-Path -LiteralPath $destinationDirectory -PathType Container)) {
        $null = New-Item -ItemType Directory -Path $destinationDirectory -Force
    }
    [IO.File]::WriteAllBytes($destinationPath, $snapshot.Bytes)
    $behaviorAuthority.Add([ordered]@{ path = [string]$relativePath; contentSha256 = $snapshot.Sha256 })
}
foreach ($relativePath in @($adjudicationContract.presentationFiles | Sort-Object -CaseSensitive)) {
    $sourcePath = [IO.Path]::GetFullPath((Join-Path $resolvedRepositoryRoot ([string]$relativePath)))
    if (-not $sourcePath.StartsWith($repositoryPrefix, [StringComparison]::OrdinalIgnoreCase)) {
        throw "Rule Issue adjudication presentation path escapes the repository root: $relativePath"
    }
    if (-not (Test-Path -LiteralPath $sourcePath -PathType Leaf)) {
        throw "Rule Issue adjudication presentation file was not found: $relativePath"
    }
    $snapshot = Get-FileSnapshot -Path $sourcePath
    $destinationPath = [IO.Path]::GetFullPath((Join-Path $runRepositoryRoot ([string]$relativePath)))
    $destinationDirectory = Split-Path -Parent $destinationPath
    if (-not (Test-Path -LiteralPath $destinationDirectory -PathType Container)) {
        $null = New-Item -ItemType Directory -Path $destinationDirectory -Force
    }
    [IO.File]::WriteAllBytes($destinationPath, $snapshot.Bytes)
}

$evaluatorSourcePath = if ([string]::IsNullOrWhiteSpace($EvaluatorScriptPath)) { $defaultEvaluatorScriptPath } else { [IO.Path]::GetFullPath($EvaluatorScriptPath) }
if (-not (Test-Path -LiteralPath $evaluatorSourcePath -PathType Leaf)) {
    throw "Rule Issue adjudication evaluator was not found: $evaluatorSourcePath"
}
$evaluatorSnapshot = Get-FileSnapshot -Path $evaluatorSourcePath
$runEvaluatorPath = Join-Path $runDirectory 'evaluator.ps1'
[IO.File]::WriteAllBytes($runEvaluatorPath, $evaluatorSnapshot.Bytes)
$catalogSnapshot = Get-FileSnapshot -Path $requiredPaths.CatalogPath
$protectedRulesSnapshot = Get-FileSnapshot -Path $requiredPaths.ProtectedRulesPath
$contractSnapshot = Get-FileSnapshot -Path $requiredPaths.AdjudicationContractPath
$stageContractPath = Join-Path $runDirectory 'rule-issue-adjudication-authority.json'
Write-HierarchicalJsonAtomically -Path $stageContractPath -Value ([ordered]@{
    contractContentSha256 = $contractSnapshot.Sha256
    behaviorFiles = $behaviorAuthority.ToArray()
    savedRuleAssessmentSchema = Get-Content -LiteralPath $requiredPaths.SavedAssessmentSchemaPath -Raw | ConvertFrom-Json -Depth 100
})
$contractAuthoritySnapshot = Get-FileSnapshot -Path $stageContractPath
$authority = [ordered]@{
    inputSetSha256 = Get-JsonSnapshotSha256 -Value $orderedComponents
    catalogContentSha256 = $catalogSnapshot.Sha256
    protectedRulesContentSha256 = $protectedRulesSnapshot.Sha256
    contractContentSha256 = $contractAuthoritySnapshot.Sha256
    evaluator = 'script:' + $evaluatorSnapshot.Sha256 + ';command:' + $EvaluatorCommand
    model = $Model
    reasoningEffort = $ReasoningEffort
}

if ($null -ne $resolvedResumeRunDirectory) {
    $resumeManifestPath = Join-Path $resolvedResumeRunDirectory 'hierarchical-reconciliation-run.json'
    $resumeCachePath = Join-Path $resolvedResumeRunDirectory 'hierarchical-reconciliation-cache.json'
    $null = Read-HierarchicalReconciliationRunManifest -Path $resumeManifestPath -SchemaPath $requiredPaths.RunSchemaPath -ExpectedAuthority $authority
    if (-not (Test-Path -LiteralPath $resumeCachePath -PathType Leaf)) {
        throw 'Hierarchical Rule Issue adjudication resume cache was not found'
    }
    $null = Read-HierarchicalReconciliationCache -Path $resumeCachePath -SchemaPath $requiredPaths.CacheSchemaPath
    Copy-HierarchicalFileAtomically -SourcePath $resumeCachePath -DestinationPath $runCachePath
}
elseif (Test-Path -LiteralPath $persistentCachePath -PathType Leaf) {
    try {
        $null = Read-HierarchicalReconciliationCache -Path $persistentCachePath -SchemaPath $requiredPaths.CacheSchemaPath
        Copy-HierarchicalFileAtomically -SourcePath $persistentCachePath -DestinationPath $runCachePath
    }
    catch {
        Remove-Item -LiteralPath $persistentCachePath -Force -ErrorAction SilentlyContinue
        if (-not $Quiet) {
            Write-Host (Format-ValidationStatusLine -Status 'skipped' -Name 'rule-issue-adjudication/cache' -Detail $_.Exception.Message -NameWidth 42)
        }
    }
}
Write-HierarchicalReconciliationRunManifest -Path $manifestPath -SchemaPath $requiredPaths.RunSchemaPath -RunId $runId -CreatedAt $runCreatedAt -Authority $authority | Out-Null

$succeeded = $false
try {
    $resultValidator = {
        param($Component, $Draft)
        Test-RuleIssueAdjudicationDraft -Component $Component -Draft $Draft
    }
    $stageParameters = @{
        RunDirectory = $runDirectory; CachePath = $runCachePath; PersistentCachePath = $persistentCachePath; ReadPersistentCache = $true; CacheSchemaPath = $requiredPaths.CacheSchemaPath
        ResultSchemaPath = $requiredPaths.DraftSchemaPath; PromptPath = $requiredPaths.PromptPath
        CatalogPath = $requiredPaths.CatalogPath; ProtectedRulesPath = $requiredPaths.ProtectedRulesPath; ContractPath = $stageContractPath
        EvaluatorScriptPath = $runEvaluatorPath; ResultValidator = $resultValidator; EvaluatorCommand = $EvaluatorCommand
        Model = $Model; ReasoningEffort = $ReasoningEffort; MaxRetries = $MaxRetries; RetryDelayMilliseconds = 1000
        MaxParallelShards = $MaxParallelShards; EvaluatorPayloadBudgetBytes = $EvaluatorPayloadBudgetBytes
        InputLabel = 'Rule Issue Groups'; InputCount = $orderedComponents.Count; ShowProgress = (-not $Quiet)
    }
    $artifactBytes = $catalogSnapshot.Bytes.Length + $protectedRulesSnapshot.Bytes.Length + (Get-Item -LiteralPath $stageContractPath).Length + (Get-Item -LiteralPath $requiredPaths.PromptPath).Length + (Get-Item -LiteralPath $requiredPaths.DraftSchemaPath).Length
    $boundedDrafts = @{}
    $ordinaryShards = @()
    $stageEntries = [Collections.Generic.List[object]]::new()
    $stageResult = [pscustomobject]@{ results = @(); cachedCount = 0; evaluatedCount = 0 }
    foreach ($shard in $shards) {
        if ($null -ne $shard.payload.PSObject.Properties['editContext']) {
            $bounded = Invoke-BoundedSavedRuleAdjudication -Component $shard.payload -StageParameters $stageParameters -InputSchemaPath $requiredPaths.InputSchemaPath -ArtifactBytes $artifactBytes
            $boundedDrafts[[string]$shard.payload.componentId] = $bounded.draft
            $stageEntries.AddRange([object[]]@($bounded.results))
            $stageResult.cachedCount += $bounded.cachedCount
            $stageResult.evaluatedCount += $bounded.evaluatedCount
        }
        else { $ordinaryShards += $shard }
    }
    if ($ordinaryShards.Count -gt 0) {
        $ordinaryRun = Invoke-ReconciliationStageSet @stageParameters -Stage adjudication -Shards $ordinaryShards
        $stageEntries.AddRange([object[]]@($ordinaryRun.results))
        $stageResult.cachedCount += $ordinaryRun.cachedCount
        $stageResult.evaluatedCount += $ordinaryRun.evaluatedCount
    }
    $stageResult.results = $stageEntries.ToArray()
    $draftsByComponentId = @{}
    $completedDrafts = @($ordinaryShards | ForEach-Object { $key = $_.shardKey; @($stageResult.results | Where-Object shardKey -CEQ $key)[0].result }) + @($boundedDrafts.Values)
    foreach ($draft in $completedDrafts) {
        $componentId = [string]$draft.componentId
        if ($draftsByComponentId.ContainsKey($componentId)) {
            throw "Hierarchical Rule Issue adjudication produced duplicate component ID: $componentId"
        }
        $draftsByComponentId[$componentId] = $draft
    }
    $missingComponentIds = @($orderedComponents.componentId | Where-Object { -not $draftsByComponentId.ContainsKey([string]$_) })
    if ($missingComponentIds.Count -gt 0) {
        throw "Hierarchical Rule Issue adjudication omitted component: $($missingComponentIds[0])"
    }
    $resultSet = [ordered]@{
        schemaVersion = 1
        kind = 'hosted-rule-issue-adjudication-set'
        components = @($orderedComponents | ForEach-Object { $draftsByComponentId[[string]$_.componentId] })
    }
    Write-HierarchicalJsonAtomically -Path $resolvedOutputPath -Value $resultSet
    Write-HierarchicalReconciliationRunManifest -Path $manifestPath -SchemaPath $requiredPaths.RunSchemaPath -RunId $runId -CreatedAt $runCreatedAt -Authority $authority -StageResults @($stageResult.results) | Out-Null
    $succeeded = $true
}
catch {
    $failureMessage = [string]$_.Exception.Message
    try {
        if (Test-Path -LiteralPath $runCachePath -PathType Leaf) {
            $partialCache = Read-HierarchicalReconciliationCache -Path $runCachePath -SchemaPath $requiredPaths.CacheSchemaPath
            $completedStageResults = @(Get-HierarchicalCompletedStageResults -Cache $partialCache -RunDirectory $runDirectory)
            Write-HierarchicalReconciliationRunManifest -Path $manifestPath -SchemaPath $requiredPaths.RunSchemaPath -RunId $runId -CreatedAt $runCreatedAt -Authority $authority -StageResults $completedStageResults | Out-Null
        }
    }
    catch {
        $failureMessage += " Failed to finalize the retained run manifest: $($_.Exception.Message)"
    }
    throw "$failureMessage Run artifacts were retained at $runDirectory"
}
finally {
    if ($succeeded -and (Test-Path -LiteralPath $runDirectory -PathType Container)) {
        Remove-Item -LiteralPath $runDirectory -Recurse -Force
    }
}

$result = [ordered]@{
    status = 'passed'
    outputPath = $resolvedOutputPath
    componentCount = $orderedComponents.Count
    cachedComponentCount = [int]$stageResult.cachedCount
    evaluatedComponentCount = [int]$stageResult.evaluatedCount
    cacheDirectory = $resolvedCacheDirectory
    elapsed = Format-ElapsedDuration -Milliseconds ([long]$stopwatch.ElapsedMilliseconds)
}
if ($OutputFormat -eq 'Json') {
    $result | ConvertTo-Json -Compress
}
else {
    $result | Format-List | Out-String | Write-Output
}
