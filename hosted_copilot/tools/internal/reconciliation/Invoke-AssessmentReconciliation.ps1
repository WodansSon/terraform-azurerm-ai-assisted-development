[CmdletBinding()]
param(
    [string]$RepositoryRoot = (Join-Path $PSScriptRoot '../../../..'),
    [Parameter(Mandatory = $true)][string]$AssessmentBaselinePath,
    [Parameter(Mandatory = $true)][string[]]$InventoryPaths,
    [Parameter(Mandatory = $true)][string]$GuidanceCapacityPath,
    [Parameter(Mandatory = $true)][string]$OutputPath,
    [string]$HostedCatalogPath = (Join-Path $PSScriptRoot '../../../copilot-rule-catalog/instruction-catalog.json'),
    [string]$ProtectedRulesPath = (Join-Path $PSScriptRoot '../../../copilot-rule-catalog/protected-rules.json'),
    [string]$ReconciliationContractPath = (Join-Path $PSScriptRoot '../../../contracts/reconciliation/assessment-reconciliation-v4.json'),
    [string]$BuilderPath = (Join-Path $PSScriptRoot 'New-WorkbenchDisplay.ps1'),
    [string]$EvaluatorCommand = 'copilot',
    [string]$EvaluatorScriptPath,
    [string]$ResumeRunDirectory,
    [string]$CacheDirectory = (Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'hosted-workbench/reconciliation-cache'),
    [ValidateNotNullOrEmpty()][string]$Model,
    [ValidateSet('low', 'medium', 'high', 'xhigh')][string]$ReasoningEffort,
    [ValidateRange(0, 3)][int]$MaxRetries = 1,
    [ValidateRange(0, 60000)][int]$RetryDelayMilliseconds = 1000,
    [ValidateRange(1, 8)][int]$MaxParallelBatches = 3,
    [ValidateRange(1, [int]::MaxValue)][int]$StagePayloadBudgetBytes = 262144,
    [ValidateRange(1, [int]::MaxValue)][int]$EvaluatorPayloadBudgetBytes = 393216,
    [object]$GeneratedAt = [DateTime]::UtcNow,
    [ValidateSet('Text', 'Json')][string]$OutputFormat = 'Text',
    [switch]$Force,
    [switch]$Quiet
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Import-Module (Join-Path $PSScriptRoot '../../modules/shared/HostedToolkit.Helpers.psm1') -Force
Import-Module (Join-Path $PSScriptRoot '../../../../tools/ValidationOutput.psm1') -Force

$llmProfile = Resolve-HostedLlmProfile -Profile normal -Model $Model -ReasoningEffort $ReasoningEffort
$Model = $llmProfile.model
$ReasoningEffort = $llmProfile.reasoningEffort

function Copy-InputSnapshot {
    param(
        [Parameter(Mandatory = $true)][string]$SourcePath,
        [Parameter(Mandatory = $true)][string]$DestinationPath
    )

    $snapshot = Get-FileSnapshot -Path $SourcePath
    $directory = Split-Path -Parent $DestinationPath
    if (-not (Test-Path -LiteralPath $directory -PathType Container)) {
        $null = New-Item -ItemType Directory -Path $directory -Force
    }
    [IO.File]::WriteAllBytes($DestinationPath, $snapshot.Bytes)
    return $snapshot
}

$resolvedRepositoryRoot = [IO.Path]::GetFullPath($RepositoryRoot).TrimEnd([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar)
$repositoryPrefix = $resolvedRepositoryRoot + [IO.Path]::DirectorySeparatorChar
$resolvedOutputPath = [IO.Path]::GetFullPath($OutputPath)
if ($resolvedOutputPath.StartsWith($repositoryPrefix, [StringComparison]::OrdinalIgnoreCase)) {
    throw 'Hosted rule change recommendation output must be outside the repository root.'
}
$resolvedCacheDirectory = [IO.Path]::GetFullPath($CacheDirectory)
if ($resolvedCacheDirectory.StartsWith($repositoryPrefix, [StringComparison]::OrdinalIgnoreCase)) {
    throw 'CacheDirectory must be outside the repository root.'
}
$resolvedResumeRunDirectory = if ([string]::IsNullOrWhiteSpace($ResumeRunDirectory)) { $null } else { [IO.Path]::GetFullPath($ResumeRunDirectory) }
if ($Force -and $null -ne $resolvedResumeRunDirectory) {
    throw 'Force cannot be combined with ResumeRunDirectory.'
}
if ($null -ne $resolvedResumeRunDirectory -and $resolvedResumeRunDirectory.StartsWith($repositoryPrefix, [StringComparison]::OrdinalIgnoreCase)) {
    throw 'ResumeRunDirectory must be outside the repository root.'
}

$resolvedBaselinePath = [IO.Path]::GetFullPath($AssessmentBaselinePath)
$resolvedCatalogPath = [IO.Path]::GetFullPath($HostedCatalogPath)
$resolvedProtectedRulesPath = [IO.Path]::GetFullPath($ProtectedRulesPath)
$resolvedContractPath = [IO.Path]::GetFullPath($ReconciliationContractPath)
$resolvedBuilderPath = [IO.Path]::GetFullPath($BuilderPath)
$canonicalBuilderPath = [IO.Path]::GetFullPath((Join-Path $resolvedRepositoryRoot 'hosted_copilot/tools/internal/reconciliation/New-WorkbenchDisplay.ps1'))
if ($resolvedBuilderPath -cne $canonicalBuilderPath) {
    throw 'BuilderPath must identify the canonical contract-owned recommendation builder.'
}
foreach ($requiredPath in @($resolvedBaselinePath, $resolvedCatalogPath, $resolvedProtectedRulesPath, $resolvedContractPath, $resolvedBuilderPath)) {
    if (-not (Test-Path -LiteralPath $requiredPath -PathType Leaf)) {
        throw "Required assessment reconciliation input was not found: $requiredPath"
    }
}

$runId = [guid]::NewGuid().ToString('N')
$runDirectory = Join-Path ([IO.Path]::GetTempPath()) "hosted-assessment-reconciliation/$runId"
$runRepositoryRoot = Join-Path $runDirectory 'repository'
$null = New-Item -ItemType Directory -Path $runRepositoryRoot -Force
$contractSnapshot = Get-FileSnapshot -Path $resolvedContractPath
$contract = $contractSnapshot.Content | ConvertFrom-Json -DateKind String
$behaviorAuthority = [Collections.Generic.List[object]]::new()
foreach ($relativePath in @($contract.behaviorFiles | Sort-Object -CaseSensitive)) {
    $sourcePath = [IO.Path]::GetFullPath((Join-Path $resolvedRepositoryRoot ([string]$relativePath)))
    $destinationPath = [IO.Path]::GetFullPath((Join-Path $runRepositoryRoot ([string]$relativePath)))
    $snapshot = Copy-InputSnapshot -SourcePath $sourcePath -DestinationPath $destinationPath
    $behaviorAuthority.Add([ordered]@{ path = [string]$relativePath; contentSha256 = $snapshot.Sha256 })
}
foreach ($relativePath in @($contract.presentationFiles | Sort-Object -CaseSensitive)) {
    $sourcePath = [IO.Path]::GetFullPath((Join-Path $resolvedRepositoryRoot ([string]$relativePath)))
    $destinationPath = [IO.Path]::GetFullPath((Join-Path $runRepositoryRoot ([string]$relativePath)))
    $null = Copy-InputSnapshot -SourcePath $sourcePath -DestinationPath $destinationPath
}
$snapshotContractPath = Join-Path $runRepositoryRoot 'hosted_copilot/contracts/reconciliation/assessment-reconciliation-v4.json'
$null = Copy-InputSnapshot -SourcePath $resolvedContractPath -DestinationPath $snapshotContractPath
$snapshotBaselinePath = Join-Path $runDirectory 'source-assessment-baseline.json'
$baselineSnapshot = Copy-InputSnapshot -SourcePath $resolvedBaselinePath -DestinationPath $snapshotBaselinePath
$snapshotCatalogPath = Join-Path $runRepositoryRoot 'hosted_copilot/copilot-rule-catalog/instruction-catalog.json'
$catalogSnapshot = Copy-InputSnapshot -SourcePath $resolvedCatalogPath -DestinationPath $snapshotCatalogPath
$snapshotProtectedRulesPath = Join-Path $runRepositoryRoot 'hosted_copilot/copilot-rule-catalog/protected-rules.json'
$protectedRulesSnapshot = Copy-InputSnapshot -SourcePath $resolvedProtectedRulesPath -DestinationPath $snapshotProtectedRulesPath
$snapshotProtectedRulesSchemaPath = Join-Path $runRepositoryRoot 'hosted_copilot/contracts/catalog/protected-rules.schema.json'
$null = Copy-InputSnapshot -SourcePath (Join-Path $resolvedRepositoryRoot 'hosted_copilot/contracts/catalog/protected-rules.schema.json') -DestinationPath $snapshotProtectedRulesSchemaPath
$protectedRules = $protectedRulesSnapshot.Content | ConvertFrom-Json -DateKind String
foreach ($relativePath in @($protectedRules.rules | ForEach-Object { [string]$_.sourcePath } | Sort-Object -Unique)) {
    $sourcePath = [IO.Path]::GetFullPath((Join-Path $resolvedRepositoryRoot $relativePath))
    if (-not $sourcePath.StartsWith($repositoryPrefix, [StringComparison]::OrdinalIgnoreCase)) {
        throw "Protected rule source path escapes the repository root: $relativePath"
    }
    $null = Copy-InputSnapshot -SourcePath $sourcePath -DestinationPath ([IO.Path]::GetFullPath((Join-Path $runRepositoryRoot $relativePath)))
}
$snapshotInventoryPaths = [Collections.Generic.List[string]]::new()
foreach ($inventoryPath in $InventoryPaths) {
    $inventory = Get-Content -LiteralPath ([IO.Path]::GetFullPath($inventoryPath)) -Raw | ConvertFrom-Json -DateKind String
    $snapshotInventoryPath = Join-Path $runDirectory "inventories/$([string]$inventory.sourceDefinitionId).json"
    $null = Copy-InputSnapshot -SourcePath ([IO.Path]::GetFullPath($inventoryPath)) -DestinationPath $snapshotInventoryPath
    $snapshotInventoryPaths.Add($snapshotInventoryPath)
}
$snapshotGuidanceCapacityPath = Join-Path $runDirectory 'guidance-capacity.json'
$null = Copy-InputSnapshot -SourcePath ([IO.Path]::GetFullPath($GuidanceCapacityPath)) -DestinationPath $snapshotGuidanceCapacityPath

$baselineSchemaPath = Join-Path $runRepositoryRoot 'hosted_copilot/contracts/assessment/source-assessment-baseline-v4.schema.json'
$catalogSchemaPath = Join-Path $runRepositoryRoot 'hosted_copilot/contracts/catalog/instruction-catalog.schema.json'
$protectedRulesSchemaPath = Join-Path $runRepositoryRoot 'hosted_copilot/contracts/catalog/protected-rules.schema.json'
$contractSchemaPath = Join-Path $runRepositoryRoot 'hosted_copilot/contracts/reconciliation/assessment-reconciliation-contract.schema.json'
$draftSchemaPath = Join-Path $runRepositoryRoot 'hosted_copilot/contracts/reconciliation/assessment-reconciliation-draft.schema.json'
$cacheSchemaPath = Join-Path $runRepositoryRoot 'hosted_copilot/contracts/reconciliation/hierarchical-reconciliation-cache.schema.json'
$runSchemaPath = Join-Path $runRepositoryRoot 'hosted_copilot/contracts/reconciliation/hierarchical-reconciliation-run.schema.json'
foreach ($validation in @(
    @{ Json = $baselineSnapshot.Content; Schema = $baselineSchemaPath; Label = 'Source assessment baseline' },
    @{ Json = $catalogSnapshot.Content; Schema = $catalogSchemaPath; Label = 'Hosted instruction catalog' },
    @{ Json = $protectedRulesSnapshot.Content; Schema = $protectedRulesSchemaPath; Label = 'Protected rules catalog' },
    @{ Json = $contractSnapshot.Content; Schema = $contractSchemaPath; Label = 'Assessment reconciliation contract' }
)) {
    if (-not ($validation.Json | Test-Json -SchemaFile $validation.Schema -ErrorAction Stop)) {
        throw "$($validation.Label) does not satisfy its schema."
    }
}
$baseline = $baselineSnapshot.Content | ConvertFrom-Json -DateKind String
$catalog = $catalogSnapshot.Content | ConvertFrom-Json -DateKind String
if ([string]$baseline.hostedCatalogSha256 -cne $catalogSnapshot.Sha256) {
    throw 'Source assessment baseline does not bind the supplied Hosted instruction catalog.'
}
if ([string]$baseline.protectedRulesContentSha256 -cne $protectedRulesSnapshot.Sha256) {
    throw 'Source assessment baseline does not bind the supplied protected rules catalog.'
}

$snapshotPipelinePath = Join-Path $runRepositoryRoot 'hosted_copilot/tools/modules/reconciliation/HierarchicalReconciliationPipeline.psm1'
$snapshotExecutorPath = Join-Path $runRepositoryRoot 'hosted_copilot/tools/modules/reconciliation/ReconciliationStageExecutor.psm1'
$snapshotStatePath = Join-Path $runRepositoryRoot 'hosted_copilot/tools/modules/reconciliation/HierarchicalReconciliationState.psm1'
Import-Module $snapshotStatePath -Force
Import-Module $snapshotPipelinePath -Force
Import-Module $snapshotExecutorPath -Force
$contractAuthorityPath = Join-Path $runDirectory 'assessment-reconciliation-authority.json'
Write-HierarchicalJsonAtomically -Path $contractAuthorityPath -Value ([ordered]@{ contractContentSha256 = $contractSnapshot.Sha256; behaviorFiles = $behaviorAuthority.ToArray() })
$contractAuthoritySnapshot = Get-FileSnapshot -Path $contractAuthorityPath
$resolvedEvaluatorScriptPath = if ([string]::IsNullOrWhiteSpace($EvaluatorScriptPath)) {
    Join-Path $runRepositoryRoot 'hosted_copilot/tools/internal/reconciliation/Invoke-CopilotReconciliationStage.ps1'
}
else {
    $evaluatorSnapshot = Get-FileSnapshot -Path ([IO.Path]::GetFullPath($EvaluatorScriptPath))
    $evaluatorPath = Join-Path $runDirectory 'evaluator.ps1'
    [IO.File]::WriteAllBytes($evaluatorPath, $evaluatorSnapshot.Bytes)
    $evaluatorPath
}
$evaluatorSnapshot = Get-FileSnapshot -Path $resolvedEvaluatorScriptPath
$evaluatorIdentity = 'script:' + $evaluatorSnapshot.Sha256 + ';command:' + $EvaluatorCommand
$authority = [ordered]@{
    inputSetSha256 = $baselineSnapshot.Sha256
    catalogContentSha256 = $catalogSnapshot.Sha256
    protectedRulesContentSha256 = $protectedRulesSnapshot.Sha256
    contractContentSha256 = $contractAuthoritySnapshot.Sha256
    evaluator = $evaluatorIdentity
    model = $Model
    reasoningEffort = $ReasoningEffort
}
$manifestPath = Join-Path $runDirectory 'hierarchical-reconciliation-run.json'
$runCachePath = Join-Path $runDirectory 'hierarchical-reconciliation-cache.json'
$persistentCachePath = Join-Path $resolvedCacheDirectory 'hierarchical-reconciliation-cache.json'
$runCreatedAt = ConvertTo-UtcTimestamp -Value ([DateTime]::UtcNow)
if ($null -ne $resolvedResumeRunDirectory) {
    $resumeManifestPath = Join-Path $resolvedResumeRunDirectory 'hierarchical-reconciliation-run.json'
    $resumeCachePath = Join-Path $resolvedResumeRunDirectory 'hierarchical-reconciliation-cache.json'
    $null = Read-HierarchicalReconciliationRunManifest -Path $resumeManifestPath -SchemaPath $runSchemaPath -ExpectedAuthority $authority
    if (-not (Test-Path -LiteralPath $resumeCachePath -PathType Leaf)) {
        throw 'Hierarchical reconciliation resume cache was not found.'
    }
    $null = Read-HierarchicalReconciliationCache -Path $resumeCachePath -SchemaPath $cacheSchemaPath
    Copy-HierarchicalFileAtomically -SourcePath $resumeCachePath -DestinationPath $runCachePath
}
elseif (-not $Force -and (Test-Path -LiteralPath $persistentCachePath -PathType Leaf)) {
    try {
        $null = Read-HierarchicalReconciliationCache -Path $persistentCachePath -SchemaPath $cacheSchemaPath
        Copy-HierarchicalFileAtomically -SourcePath $persistentCachePath -DestinationPath $runCachePath
    }
    catch {
        Remove-Item -LiteralPath $persistentCachePath -Force -ErrorAction SilentlyContinue
        if (-not $Quiet) {
            Write-Host (Format-ValidationStatusLine -Status 'skipped' -Name 'assessment-reconciliation/cache' -Detail $_.Exception.Message -NameWidth 42)
        }
    }
}
Write-HierarchicalReconciliationRunManifest -Path $manifestPath -SchemaPath $runSchemaPath -RunId $runId -CreatedAt $runCreatedAt -Authority $authority | Out-Null

$succeeded = $false
try {
    if (-not $Quiet) {
        Write-ValidationSectionHeader -Title 'Hierarchical Reconciliation' | Write-Host
    }
    $hierarchyStopwatch = [Diagnostics.Stopwatch]::StartNew()
    $pipelineResult = Invoke-HierarchicalReconciliationPipeline -AssessmentBaseline $baseline -Catalog $catalog -ProtectedCatalog $protectedRules -RunDirectory $runDirectory -CachePath $runCachePath -PersistentCachePath $persistentCachePath -CacheSchemaPath $cacheSchemaPath -CatalogPath $snapshotCatalogPath -ProtectedRulesPath $snapshotProtectedRulesPath -ContractPath $snapshotContractPath -ContractAuthorityPath $contractAuthorityPath -RoutingSchemaPath (Join-Path $runRepositoryRoot 'hosted_copilot/contracts/reconciliation/assessment-reconciliation-routing.schema.json') -RoutingPromptPath (Join-Path $runRepositoryRoot 'hosted_copilot/tools/prompts/reconciliation/AssessmentReconciliationRouting-v4.md') -ConsolidationSchemaPath (Join-Path $runRepositoryRoot 'hosted_copilot/contracts/reconciliation/assessment-reconciliation-consolidation.schema.json') -ConsolidationPromptPath (Join-Path $runRepositoryRoot 'hosted_copilot/tools/prompts/reconciliation/AssessmentReconciliationConsolidation-v4.md') -SynthesisSchemaPath $draftSchemaPath -SynthesisPromptPath (Join-Path $runRepositoryRoot 'hosted_copilot/tools/prompts/reconciliation/AssessmentReconciliation-v4.md') -EvaluatorScriptPath $resolvedEvaluatorScriptPath -EvaluatorCommand $EvaluatorCommand -Model $Model -ReasoningEffort $ReasoningEffort -MaxRetries $MaxRetries -RetryDelayMilliseconds $RetryDelayMilliseconds -MaxParallelShards $MaxParallelBatches -StagePayloadBudgetBytes $StagePayloadBudgetBytes -EvaluatorPayloadBudgetBytes $EvaluatorPayloadBudgetBytes -ShowProgress:(-not $Quiet)
    $hierarchyStopwatch.Stop()
    if (-not $Quiet) {
        Write-ValidationSectionHeader -Title 'Hierarchical Reconciliation Summary' | Write-Host
        Write-Host ("  {0,-17}: {1} total" -f 'Stages', 3)
        Write-Host ("  {0,-17}: {1} total | {2} cached | {3} evaluated" -f 'Batches', $pipelineResult.shardCount, $pipelineResult.cachedShardCount, $pipelineResult.evaluatedShardCount)
        Write-Host ("  {0,-17}: {1}" -f 'Elapsed', (Format-ElapsedDuration -Milliseconds ([long]$hierarchyStopwatch.ElapsedMilliseconds)))
    }
    $responsePath = Join-Path $runDirectory 'assessment-reconciliation-draft.json'
    Write-HierarchicalJsonAtomically -Path $responsePath -Value $pipelineResult.draft
    if (-not ((Get-Content -LiteralPath $responsePath -Raw) | Test-Json -SchemaFile $draftSchemaPath -ErrorAction Stop)) {
        throw 'Merged assessment reconciliation draft does not satisfy its schema.'
    }

    if (-not $Quiet) {
        [long]$displayPayloadBytes = 0
        foreach ($displayInputPath in @($responsePath, $snapshotBaselinePath, $snapshotGuidanceCapacityPath, $snapshotCatalogPath, $snapshotProtectedRulesPath, $snapshotContractPath) + @($snapshotInventoryPaths.ToArray())) {
            $displayPayloadBytes += (Get-Item -LiteralPath $displayInputPath).Length
        }
        Write-ValidationSectionHeader -Title 'Display Projection' | Write-Host
        Write-Host ("  {0,-17}: {1} total" -f 'Recommendations', @($pipelineResult.draft.recommendations).Count)
        Write-Host ("  {0,-17}: {1} total" -f 'Assessments', @($pipelineResult.draft.assessmentCoverage).Count)
        Write-Host ("  {0,-17}: {1}" -f 'Payload', (Format-ByteSize -Bytes $displayPayloadBytes))
        Write-Host ''
        Write-Host (Format-ValidationStatusLine -Status 'running' -Name 'assessment-reconciliation/display' -Detail 'Building candidate projection' -NameWidth 42)
    }
    $snapshotBuilderPath = Join-Path $runRepositoryRoot 'hosted_copilot/tools/internal/reconciliation/New-WorkbenchDisplay.ps1'
    $displayStopwatch = [Diagnostics.Stopwatch]::StartNew()
    $builderOutput = @(& $snapshotBuilderPath -RepositoryRoot $runRepositoryRoot -AssessmentBaselinePath $snapshotBaselinePath -InventoryPaths $snapshotInventoryPaths.ToArray() -ReconciliationDraftPath $responsePath -GuidanceCapacityPath $snapshotGuidanceCapacityPath -OutputPath $resolvedOutputPath -HostedCatalogPath $snapshotCatalogPath -ProtectedRulesPath $snapshotProtectedRulesPath -ReconciliationContractPath $snapshotContractPath -GeneratedAt $GeneratedAt -OutputFormat Json 2>&1)
    $displayStopwatch.Stop()
    $builderResult = ($builderOutput | Out-String) | ConvertFrom-Json -DateKind String
    if (-not $Quiet) {
        Write-Host (Format-ValidationStatusLine -Status 'passed' -Name 'assessment-reconciliation/display' -Detail ("Candidate projection built : [Elapsed: {0}]" -f (Format-ElapsedDuration -Milliseconds ([long]$displayStopwatch.ElapsedMilliseconds))) -NameWidth 42)
    }

    $allStageResults = @($pipelineResult.stages.routing.results) + @($pipelineResult.stages.consolidation.results) + @($pipelineResult.stages.synthesis.results)
    Write-HierarchicalReconciliationRunManifest -Path $manifestPath -SchemaPath $runSchemaPath -RunId $runId -CreatedAt $runCreatedAt -Authority $authority -StageResults $allStageResults | Out-Null
    Copy-HierarchicalFileAtomically -SourcePath $runCachePath -DestinationPath $persistentCachePath
    $succeeded = $true
}
catch {
    $failureMessage = [string]$_.Exception.Message
    try {
        if (Test-Path -LiteralPath $runCachePath -PathType Leaf) {
            $partialCache = Read-HierarchicalReconciliationCache -Path $runCachePath -SchemaPath $cacheSchemaPath
            $completedStageResults = @(Get-HierarchicalCompletedStageResults -Cache $partialCache -RunDirectory $runDirectory)
            Write-HierarchicalReconciliationRunManifest -Path $manifestPath -SchemaPath $runSchemaPath -RunId $runId -CreatedAt $runCreatedAt -Authority $authority -StageResults $completedStageResults | Out-Null
        }
    }
    catch {
        $failureMessage += " Failed to finalize the retained run manifest: $($_.Exception.Message)"
    }
    throw "$failureMessage Hierarchical reconciliation run artifacts were retained at $runDirectory"
}
finally {
    if ($succeeded -and (Test-Path -LiteralPath $runDirectory -PathType Container)) {
        Remove-Item -LiteralPath $runDirectory -Recurse -Force
    }
}

$result = [ordered]@{
    status = [string]$builderResult.status
    outputPath = $resolvedOutputPath
    shardCount = [int]$pipelineResult.shardCount
    cachedShardCount = [int]$pipelineResult.cachedShardCount
    evaluatedShardCount = [int]$pipelineResult.evaluatedShardCount
    candidateCount = [int]$builderResult.candidateCount
    recommendationCount = [int]$builderResult.recommendationCount
    evaluator = $evaluatorIdentity
    cacheDirectory = $resolvedCacheDirectory
    cacheMode = if ($Force) { 'force-refresh' } else { 'reuse' }
    displaySha256 = [string]$builderResult.displaySha256
}
if ($OutputFormat -eq 'Json') {
    $result | ConvertTo-Json -Depth 5
}
else {
    Write-Output "Assessment reconciliation completed with status $($result.status): $($result.candidateCount) candidates, $($result.recommendationCount) recommendations across $($result.shardCount) hierarchical shards"
    Write-Output "Output: $($result.outputPath)"
    Write-Output "Display SHA-256: $($result.displaySha256)"
}
