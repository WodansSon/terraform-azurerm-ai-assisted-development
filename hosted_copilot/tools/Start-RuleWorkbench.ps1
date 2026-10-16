<#
.SYNOPSIS
Launches or rebuilds the Hosted Rule Workbench.

.DESCRIPTION
Serves the last validated Workbench artifacts by default. Rebuild mode collects current sources, evaluates cache misses, reconciles assessments, and atomically stages a new display. Force mode performs a rebuild without reading assessment or reconciliation caches.

.PARAMETER Port
Specifies the loopback port used by the Workbench server.

.PARAMETER OwnerProcessId
Specifies a process whose exit should stop the Workbench server.

.PARAMETER SiteDirectory
Specifies the external directory that receives staged Workbench assets and validated artifacts. Defaults to `%LOCALAPPDATA%\hosted-workbench\site`.

.PARAMETER InventoryDirectory
Specifies the external directory that stores collected source inventories. Defaults to `%LOCALAPPDATA%\terraform-azurerm-ai-assisted-development\hosted-rule-intake\inventories`.

.PARAMETER AssessmentCacheDirectory
Specifies the external directory that stores validated source-assessment cache entries. Defaults to `%LOCALAPPDATA%\hosted-workbench\assessment-cache`.

.PARAMETER ReconciliationCacheDirectory
Specifies the external directory that stores validated hierarchical reconciliation cache entries. Defaults to `%LOCALAPPDATA%\hosted-workbench\reconciliation-cache`.

.PARAMETER ManualRelationshipCacheDirectory
Specifies the external directory that stores manual relationship-evaluation cache entries. Defaults to `%LOCALAPPDATA%\hosted-workbench\manual-relationship-cache`.

.PARAMETER AssessmentResumeDirectory
Specifies an exact-authority retained source-assessment run to resume during an ordinary rebuild.

.PARAMETER Model
Specifies the Copilot model requested for source assessment and reconciliation.

.PARAMETER AssessmentReasoningEffort
Specifies the reasoning effort requested for source assessment and reconciliation.

.PARAMETER MaxRetries
Specifies how many times a failed evaluator batch may be retried.

.PARAMETER MaxParallelBatches
Specifies the maximum number of evaluator batches or shards that may run concurrently.

.PARAMETER EvaluatorCommand
Specifies the Copilot evaluator executable.

.PARAMETER RelationshipEvaluatorScriptPath
Specifies an optional evaluator adapter used for manual relationship checks.

.PARAMETER AdjudicationEvaluatorScriptPath
Specifies an optional evaluator adapter used for saved-rule group adjudication.

.PARAMETER Rebuild
Collects current sources and rebuilds the staged Workbench artifacts while reusing compatible cache entries.

.PARAMETER Force
Requires Rebuild and bypasses assessment and reconciliation cache reads while still persisting validated replacements.

.PARAMETER SkipGitHubAuthorization
Skips authenticated GitHub identity and fork authorization for supported local diagnostics.

.PARAMETER StageOnly
Stages validated assets and artifacts without starting the local server.

.PARAMETER NoLaunch
Starts the local server without opening a browser.

.PARAMETER OutputFormat
Selects human-readable text or machine-readable JSON output.

.PARAMETER Help
Displays curated Hosted command help and exits without operational side effects.

.PARAMETER Detailed
Displays curated Hosted command help and exits without operational side effects.

.EXAMPLE
pwsh -NoProfile -File ./hosted_copilot/tools/Start-RuleWorkbench.ps1
Serves the last jointly validated Workbench display and Rule Issues artifacts.

.EXAMPLE
pwsh -NoProfile -File ./hosted_copilot/tools/Start-RuleWorkbench.ps1 -Rebuild
Collects current sources and rebuilds while reusing compatible semantic caches.

.EXAMPLE
pwsh -NoProfile -File ./hosted_copilot/tools/Start-RuleWorkbench.ps1 -Rebuild -Force
Performs a complete uncached assessment and reconciliation rebuild.

.NOTES
Ordinary launch performs no source collection or semantic evaluation. Site, inventory, and cache directories must remain outside the source repository.

.LINK
https://github.com/WodansSon/terraform-azurerm-ai-assisted-development/blob/main/hosted_copilot/tools/README.md
#>
[CmdletBinding(DefaultParameterSetName = 'Default')]
param(
    [Parameter(ParameterSetName = 'Default')]
    [Parameter(ParameterSetName = 'Force')]
    [ValidateRange(1024, 65535)]
    [int]$Port = 43143,

    [Parameter(ParameterSetName = 'Default')]
    [Parameter(ParameterSetName = 'Force')]
    [ValidateRange(1, 2147483647)]
    [int]$OwnerProcessId,

    [Parameter(ParameterSetName = 'Default')]
    [Parameter(ParameterSetName = 'Force')]
    [string]$SiteDirectory = (Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'hosted-workbench/site'),

    [Parameter(ParameterSetName = 'Default')]
    [Parameter(ParameterSetName = 'Force')]
    [string]$InventoryDirectory = (Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'terraform-azurerm-ai-assisted-development/hosted-rule-intake/inventories'),

    [Parameter(ParameterSetName = 'Default')]
    [Parameter(ParameterSetName = 'Force')]
    [string]$AssessmentCacheDirectory = (Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'hosted-workbench/assessment-cache'),

    [Parameter(ParameterSetName = 'Default')]
    [Parameter(ParameterSetName = 'Force')]
    [string]$ReconciliationCacheDirectory = (Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'hosted-workbench/reconciliation-cache'),

    [Parameter(ParameterSetName = 'Default')]
    [Parameter(ParameterSetName = 'Force')]
    [string]$ManualRelationshipCacheDirectory = (Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'hosted-workbench/manual-relationship-cache'),

    [Parameter(ParameterSetName = 'Default')]
    [string]$AssessmentResumeDirectory,

    [Parameter(ParameterSetName = 'Default')]
    [Parameter(ParameterSetName = 'Force')]
    [string]$Model = 'gpt-5.4',

    [Parameter(ParameterSetName = 'Default')]
    [Parameter(ParameterSetName = 'Force')]
    [ValidateSet('low', 'medium', 'high', 'xhigh')]
    [string]$AssessmentReasoningEffort = 'high',

    [Parameter(ParameterSetName = 'Default')]
    [Parameter(ParameterSetName = 'Force')]
    [ValidateRange(0, 3)]
    [int]$MaxRetries = 1,

    [Parameter(ParameterSetName = 'Default')]
    [Parameter(ParameterSetName = 'Force')]
    [ValidateRange(1, 8)]
    [int]$MaxParallelBatches = 3,

    [Parameter(ParameterSetName = 'Default')]
    [Parameter(ParameterSetName = 'Force')]
    [string]$EvaluatorCommand = 'copilot',

    [Parameter(ParameterSetName = 'Default')]
    [Parameter(ParameterSetName = 'Force')]
    [string]$RelationshipEvaluatorScriptPath,

    [Parameter(ParameterSetName = 'Default')]
    [Parameter(ParameterSetName = 'Force')]
    [string]$AdjudicationEvaluatorScriptPath,

    [Parameter(ParameterSetName = 'Default')]
    [Parameter(ParameterSetName = 'Force')]
    [switch]$Rebuild,

    [Parameter(Mandatory, ParameterSetName = 'Force')]
    [switch]$Force,

    [Parameter(ParameterSetName = 'Default')]
    [Parameter(ParameterSetName = 'Force')]
    [switch]$SkipGitHubAuthorization,

    [Parameter(ParameterSetName = 'Default')]
    [Parameter(ParameterSetName = 'Force')]
    [switch]$StageOnly,

    [Parameter(ParameterSetName = 'Default')]
    [Parameter(ParameterSetName = 'Force')]
    [switch]$NoLaunch,

    [Parameter(ParameterSetName = 'Default')]
    [Parameter(ParameterSetName = 'Force')]
    [ValidateSet('Text', 'Json')]
    [string]$OutputFormat = 'Text',

    [Parameter(Mandatory, ParameterSetName = 'Help')]
    [Alias('h')]
    [switch]$Help,

    [Parameter(Mandatory, ParameterSetName = 'Detailed')]
    [switch]$Detailed
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$commandHelpModulePath = Join-Path $PSScriptRoot 'modules/shared/HostedCommandHelp.psm1'
Import-Module -Name $commandHelpModulePath -Force
if ($Help -or $Detailed) {
    $helpParameterGroups = [ordered]@{
        'Workflow Options' = @('Rebuild', 'Force', 'StageOnly', 'NoLaunch')
        'Server And Output' = @('Port', 'OwnerProcessId', 'OutputFormat')
        'Evaluation' = @('Model', 'AssessmentReasoningEffort', 'MaxRetries', 'MaxParallelBatches', 'EvaluatorCommand', 'RelationshipEvaluatorScriptPath', 'AdjudicationEvaluatorScriptPath')
        'Storage And Recovery' = @('SiteDirectory', 'InventoryDirectory', 'AssessmentCacheDirectory', 'ReconciliationCacheDirectory', 'ManualRelationshipCacheDirectory', 'AssessmentResumeDirectory')
        'Authorization' = @('SkipGitHubAuthorization')
    }
    Show-HostedCommandHelp -ScriptPath $PSCommandPath -DisplayName 'Hosted Rule Workbench Help' -ParameterGroups $helpParameterGroups
    return
}
if ($Force -and -not $Rebuild) {
    throw 'Force requires Rebuild.'
}

$validationOutputModulePath = Join-Path $PSScriptRoot '../../tools/ValidationOutput.psm1'
$hostedToolkitHelpersModulePath = Join-Path $PSScriptRoot 'modules/shared/HostedToolkit.Helpers.psm1'
$sourceEvidenceModulePath = Join-Path $PSScriptRoot 'modules/shared/SourceEvidenceValidation.psm1'
$workbenchGitHubContextModulePath = Join-Path $PSScriptRoot 'modules/workbench/Workbench.GitHubContext.psm1'
Import-Module -Name $validationOutputModulePath -Force
Import-Module -Name $hostedToolkitHelpersModulePath -Force
Import-Module -Name $sourceEvidenceModulePath -Force
Import-Module -Name $workbenchGitHubContextModulePath -Force

$repositoryRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
$workbenchSource = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../workbench'))
$workbenchIconSource = Join-Path $workbenchSource 'icons'
$catalogRoot = Join-Path $PSScriptRoot '../copilot-rule-catalog'
$hostedCatalogPath = Join-Path $catalogRoot 'instruction-catalog.json'
$protectedRulesPath = Join-Path $catalogRoot 'protected-rules.json'
$displaySchemaPath = Join-Path $catalogRoot 'assessment-reconciliation/workbench-display-v4.schema.json'
$ruleIssuesSchemaPath = Join-Path $catalogRoot 'assessment-reconciliation/workbench-rule-issues-v4.schema.json'
$sourceDefinitionSetPath = Join-Path $catalogRoot 'source-definitions/source-definition-set.json'
$inventoryCollectorPath = Join-Path $PSScriptRoot 'internal/collection/New-SourceInventory.ps1'
$sourceAssessmentPath = Join-Path $PSScriptRoot 'internal/assessment/Invoke-SourceAssessment.ps1'
$assessmentReconciliationPath = Join-Path $PSScriptRoot 'internal/reconciliation/Invoke-AssessmentReconciliation.ps1'
$ruleIssuesExporterPath = Join-Path $PSScriptRoot 'internal/reconciliation/Export-WorkbenchRuleIssues.ps1'
$manualRelationshipPath = Join-Path $PSScriptRoot 'internal/reconciliation/Invoke-ManualRuleRelationship.ps1'
$savedRuleEvaluationPath = Join-Path $PSScriptRoot 'internal/reconciliation/Invoke-SavedRuleEvaluation.ps1'
Import-Module (Join-Path $PSScriptRoot 'modules/workbench/SavedRuleEvaluation.psm1')
$guidanceCapacityPath = Join-Path $PSScriptRoot 'internal/workbench/Get-GuidanceCapacity.ps1'
$resolvedSiteDirectory = [IO.Path]::GetFullPath($SiteDirectory)
$resolvedAssessmentCacheDirectory = [IO.Path]::GetFullPath($AssessmentCacheDirectory)
$resolvedReconciliationCacheDirectory = [IO.Path]::GetFullPath($ReconciliationCacheDirectory)
$resolvedManualRelationshipCacheDirectory = [IO.Path]::GetFullPath($ManualRelationshipCacheDirectory)
$resolvedRelationshipEvaluatorScriptPath = if ([string]::IsNullOrWhiteSpace($RelationshipEvaluatorScriptPath)) { $null } else { [IO.Path]::GetFullPath($RelationshipEvaluatorScriptPath) }
$resolvedAssessmentResumeDirectory = if ([string]::IsNullOrWhiteSpace($AssessmentResumeDirectory)) { $null } else { [IO.Path]::GetFullPath($AssessmentResumeDirectory) }
$assessmentRecoveryMode = if ($null -eq $resolvedAssessmentResumeDirectory) { 'NONE' } else { 'EXPLICIT' }
$cacheMode = if ($Force) { 'FORCE-REFRESH' } else { 'REUSE' }
$repositoryPrefix = $repositoryRoot.TrimEnd([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar) + [IO.Path]::DirectorySeparatorChar
if ($resolvedSiteDirectory.StartsWith($repositoryPrefix, [StringComparison]::OrdinalIgnoreCase)) {
    throw 'SiteDirectory must be outside the source repository'
}
if ($resolvedAssessmentCacheDirectory.StartsWith($repositoryPrefix, [StringComparison]::OrdinalIgnoreCase)) {
    throw 'AssessmentCacheDirectory must be outside the source repository'
}
if ($resolvedReconciliationCacheDirectory.StartsWith($repositoryPrefix, [StringComparison]::OrdinalIgnoreCase)) {
    throw 'ReconciliationCacheDirectory must be outside the source repository'
}
if ($resolvedManualRelationshipCacheDirectory.StartsWith($repositoryPrefix, [StringComparison]::OrdinalIgnoreCase)) {
    throw 'ManualRelationshipCacheDirectory must be outside the source repository'
}
if ($null -ne $resolvedRelationshipEvaluatorScriptPath -and -not (Test-Path -LiteralPath $resolvedRelationshipEvaluatorScriptPath -PathType Leaf)) {
    throw "RelationshipEvaluatorScriptPath was not found: $resolvedRelationshipEvaluatorScriptPath"
}

foreach ($requiredPath in @($workbenchSource, $workbenchIconSource, $hostedCatalogPath, $protectedRulesPath, $displaySchemaPath, $ruleIssuesSchemaPath, $sourceDefinitionSetPath, $inventoryCollectorPath, $sourceAssessmentPath, $assessmentReconciliationPath, $ruleIssuesExporterPath, $manualRelationshipPath, $guidanceCapacityPath)) {
    if (-not (Test-Path -LiteralPath $requiredPath)) {
        throw "Required Workbench source was not found: $requiredPath"
    }
}

if (-not (Test-Path -LiteralPath $resolvedSiteDirectory -PathType Container)) {
    New-Item -ItemType Directory -Path $resolvedSiteDirectory -Force | Out-Null
}

$ownedAssetNames = @('index.html', 'app.js', 'hierarchical-view.js', 'statusbar.js', 'styles.css', 'favicon.svg')
foreach ($assetName in $ownedAssetNames) {
    Copy-Item -LiteralPath (Join-Path $workbenchSource $assetName) -Destination (Join-Path $resolvedSiteDirectory $assetName) -Force
}
Copy-Item -LiteralPath $workbenchIconSource -Destination $resolvedSiteDirectory -Recurse -Force

$shutdownTokenBytes = New-Object byte[] 32
[Security.Cryptography.RandomNumberGenerator]::Fill($shutdownTokenBytes)
$shutdownToken = [Convert]::ToHexString($shutdownTokenBytes).ToLowerInvariant()
$operationTokenBytes = New-Object byte[] 32
[Security.Cryptography.RandomNumberGenerator]::Fill($operationTokenBytes)
$operationToken = [Convert]::ToHexString($operationTokenBytes).ToLowerInvariant()
$githubContext = Get-HostedWorkbenchGitHubContext -RepositoryRoot $repositoryRoot -SkipGitHubAuthorization:$SkipGitHubAuthorization
$maintainerIdentity = $githubContext.maintainerIdentity
$targetRepository = $githubContext.targetRepository
$shutdownConfig = [ordered]@{
    shutdownToken = $shutdownToken
    operationToken = $operationToken
    maintainerIdentity = $maintainerIdentity
    targetRepository = $targetRepository
} | ConvertTo-Json -Compress
[IO.File]::WriteAllText((Join-Path $resolvedSiteDirectory 'shutdown-config.js'), "globalThis.__HOSTED_RULE_WORKBENCH__ = $shutdownConfig;`n", [Text.UTF8Encoding]::new($false))
$runtimeConfigBytes = [Text.Encoding]::UTF8.GetBytes($shutdownConfig)

$stagedDisplayPath = Join-Path $resolvedSiteDirectory 'workbench-display.json'
$stagedRuleIssuesPath = Join-Path $resolvedSiteDirectory 'workbench-rule-issues.json'
$savedAuthorityParameters = @{
    RepositoryRoot = $repositoryRoot; DisplayPath = $stagedDisplayPath; RuleIssuesPath = $stagedRuleIssuesPath
    EvaluatorCommand = $EvaluatorCommand; Model = $Model; ReasoningEffort = $AssessmentReasoningEffort
    RelationshipEvaluatorScriptPath = $resolvedRelationshipEvaluatorScriptPath
    AdjudicationEvaluatorScriptPath = $AdjudicationEvaluatorScriptPath
}
$assessmentResult = $null
$ruleIssuesResult = $null
$script:workbenchPhase = 'INITIALIZATION'
$workbenchStages = [Collections.Generic.List[object]]::new()

function Complete-WorkbenchStage {
    param([Parameter(Mandatory = $true)][string]$Name)

    $script:workbenchStages.Add([pscustomobject]@{ status = 'passed'; name = $Name })
}

function Copy-FileAtomically {
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

function Update-StagedDisplay {
    if (-not $Rebuild) {
        $script:workbenchPhase = 'EXISTING DISPLAY VALIDATION'
        if (-not (Test-Path -LiteralPath $stagedDisplayPath -PathType Leaf) -or -not (Test-Path -LiteralPath $stagedRuleIssuesPath -PathType Leaf)) {
            throw "A complete staged Workbench display was not found in $resolvedSiteDirectory. Run Start-RuleWorkbench.ps1 -Rebuild to create one."
        }
        $stagedDisplayContent = Get-Content -LiteralPath $stagedDisplayPath -Raw
        $stagedRuleIssuesContent = Get-Content -LiteralPath $stagedRuleIssuesPath -Raw
        if (-not ($stagedDisplayContent | Test-Json -SchemaFile $displaySchemaPath -ErrorAction Stop)) {
            throw 'Staged Workbench display does not satisfy its schema'
        }
        if (-not ($stagedRuleIssuesContent | Test-Json -SchemaFile $ruleIssuesSchemaPath -ErrorAction Stop)) {
            throw 'Staged Workbench Rule Issues do not satisfy their schema'
        }
        $validatedDisplay = $stagedDisplayContent | ConvertFrom-Json -DateKind String
        $validatedRuleIssues = $stagedRuleIssuesContent | ConvertFrom-Json -DateKind String
        $displaySourceFiles = @($validatedDisplay.sourceFiles | ForEach-Object { "$($_.sourceDefinitionId)`0$($_.sourceId)`0$($_.contentSha256)" } | Sort-Object -CaseSensitive)
        $ruleIssueSourceFiles = @($validatedRuleIssues.sourceFiles | ForEach-Object { "$($_.sourceDefinitionId)`0$($_.sourceId)`0$($_.contentSha256)" } | Sort-Object -CaseSensitive)
        if (@(Compare-Object $displaySourceFiles $ruleIssueSourceFiles -SyncWindow 0).Count -ne 0) {
            throw 'Staged Workbench display and Rule Issues source files do not match'
        }
        Complete-WorkbenchStage -Name $script:workbenchPhase
        return $validatedDisplay
    }

    $runDirectory = Join-Path ([IO.Path]::GetTempPath()) ('hosted-rule-workbench/run-' + [guid]::NewGuid().ToString('N'))
    $currentInventoryDirectory = Join-Path $runDirectory 'inventories'
    $null = New-Item -ItemType Directory -Path $currentInventoryDirectory -Force
    try {
        if ($OutputFormat -eq 'Text') {
            Write-ValidationSectionHeader -Title 'Source Collection' | Write-Host
        }
        $script:workbenchPhase = 'SOURCE COLLECTION'
        $sourceDefinitionSet = Get-Content -LiteralPath $sourceDefinitionSetPath -Raw | ConvertFrom-Json
        $currentInventoryPaths = [Collections.Generic.List[string]]::new()
        $priorInventoryPaths = [Collections.Generic.List[string]]::new()
        foreach ($sourceDefinitionId in @($sourceDefinitionSet.sourceDefinitionIds)) {
            $inventoryPath = Join-Path $currentInventoryDirectory "$sourceDefinitionId.json"
            if ($OutputFormat -eq 'Text') {
                Write-Host (Format-ValidationStatusLine -Status 'running' -Name "source-collection/$sourceDefinitionId" -Detail 'Building current source inventory' -NameWidth 42)
            }
            $collectionOutput = @(& $inventoryCollectorPath -RepositoryRoot $repositoryRoot -SourceDefinitionPath (Join-Path $catalogRoot "source-definitions/$sourceDefinitionId.json") -OutputPath $inventoryPath -OutputFormat Json 2>&1)
            $collectionSucceeded = $?
            if (-not $collectionSucceeded) {
                throw "Source inventory collection failed for $sourceDefinitionId`: $(($collectionOutput | Out-String).Trim())"
            }
            if ($OutputFormat -eq 'Text') {
                Write-Host (Format-ValidationStatusLine -Status 'passed' -Name "source-collection/$sourceDefinitionId" -Detail 'Current source inventory built' -NameWidth 42)
            }
            $currentInventoryPaths.Add($inventoryPath)
            $priorInventoryPath = Join-Path ([IO.Path]::GetFullPath($InventoryDirectory)) "$sourceDefinitionId.json"
            if (Test-Path -LiteralPath $priorInventoryPath -PathType Leaf) {
                $priorInventoryPaths.Add($priorInventoryPath)
            }
        }
        Complete-WorkbenchStage -Name $script:workbenchPhase

            $assessmentSetPath = Join-Path $runDirectory 'assessment-set.json'
            $script:workbenchPhase = 'SOURCE ASSESSMENT'
            if ($OutputFormat -eq 'Text') {
                Write-ValidationSectionHeader -Title 'Source Assessment' | Write-Host
            }
            $assessmentParameters = @{
                RepositoryRoot = $repositoryRoot
                InventoryPaths = $currentInventoryPaths.ToArray()
                PriorInventoryPaths = $priorInventoryPaths.ToArray()
                OutputPath = $assessmentSetPath
                EvaluatorCommand = $EvaluatorCommand
                Model = $Model
                ReasoningEffort = $AssessmentReasoningEffort
                MaxRetries = $MaxRetries
                MaxParallelBatches = $MaxParallelBatches
                CacheDirectory = $resolvedAssessmentCacheDirectory
                ShowProgress = $OutputFormat -eq 'Text'
                OutputFormat = 'Json'
            }
            if ($null -ne $resolvedAssessmentResumeDirectory) {
                $assessmentParameters.ResumeRunDirectory = $resolvedAssessmentResumeDirectory
            }
            if ($Force) {
                $assessmentParameters.Force = $true
            }
            $assessmentOutput = @(& $sourceAssessmentPath @assessmentParameters 2>&1)
            $assessmentSucceeded = $?
            if (-not $assessmentSucceeded) {
                throw "Source assessment failed: $(($assessmentOutput | Out-String).Trim())"
            }
            $script:assessmentResult = ($assessmentOutput | Out-String) | ConvertFrom-Json
            Complete-WorkbenchStage -Name $script:workbenchPhase

            $capacityPath = Join-Path $runDirectory 'guidance-capacity.json'
            $script:workbenchPhase = 'HOSTED GUIDANCE TOKEN CAPACITY'
            if ($OutputFormat -eq 'Text') {
                Write-ValidationSectionHeader -Title 'Hosted Guidance Token Capacity' | Write-Host
                Write-Host (Format-ValidationStatusLine -Status 'running' -Name 'guidance-capacity' -Detail 'Checking token usage and safety headroom' -NameWidth 42)
            }
            $capacityOutput = @(& $guidanceCapacityPath -HostedRoot (Join-Path $repositoryRoot 'hosted_copilot') -OutputFormat Json 2>&1)
            $capacitySucceeded = $?
            if (-not $capacitySucceeded) {
                throw "Guidance capacity calculation failed: $(($capacityOutput | Out-String).Trim())"
            }
            $capacityContent = ($capacityOutput | Out-String).Trim()
            [IO.File]::WriteAllText($capacityPath, ($capacityContent + "`n"), [Text.UTF8Encoding]::new($false))
            if ($OutputFormat -eq 'Text') {
                $capacityResult = $capacityContent | ConvertFrom-Json -DateKind String
                $guidanceFileCount = @($capacityResult.reports | Where-Object { [string]$_.kind -ceq 'file' }).Count
                $combinedScopeCount = @($capacityResult.reports | Where-Object { [string]$_.kind -ceq 'combined' }).Count
                Write-Host (Format-ValidationStatusLine -Status 'passed' -Name 'guidance-capacity' -Detail ("{0} guidance files and {1} combined scopes fit within safety-adjusted token limits" -f $guidanceFileCount, $combinedScopeCount) -NameWidth 42)
            }
            Complete-WorkbenchStage -Name $script:workbenchPhase

            $script:workbenchPhase = 'ASSESSMENT RECONCILIATION'
            $reconciledDisplayPath = Join-Path $runDirectory 'workbench-display.json'
            $reconciliationParameters = @{
                RepositoryRoot = $repositoryRoot
                AssessmentBaselinePath = $assessmentSetPath
                InventoryPaths = $currentInventoryPaths.ToArray()
                GuidanceCapacityPath = $capacityPath
                OutputPath = $reconciledDisplayPath
                EvaluatorCommand = $EvaluatorCommand
                Model = $Model
                ReasoningEffort = $AssessmentReasoningEffort
                MaxRetries = $MaxRetries
                MaxParallelBatches = $MaxParallelBatches
                CacheDirectory = $resolvedReconciliationCacheDirectory
                OutputFormat = 'Json'
            }
            if ($Force) {
                $reconciliationParameters.Force = $true
            }
            $reconciliationOutput = @(& $assessmentReconciliationPath @reconciliationParameters 2>&1)
            $reconciliationSucceeded = $?
            if (-not $reconciliationSucceeded) {
                throw "Assessment reconciliation failed: $(($reconciliationOutput | Out-String).Trim())"
            }
            $reconciledDisplayContent = Get-Content -LiteralPath $reconciledDisplayPath -Raw
            if (-not ($reconciledDisplayContent | Test-Json -SchemaFile $displaySchemaPath -ErrorAction Stop)) {
                throw 'Reconciled Workbench display does not satisfy its schema'
            }
            Complete-WorkbenchStage -Name $script:workbenchPhase
            $script:workbenchPhase = 'CANDIDATE PROJECTION'
            Complete-WorkbenchStage -Name $script:workbenchPhase

            $script:workbenchPhase = 'RULE ISSUE ADJUDICATION'
            if ($OutputFormat -eq 'Text') {
                Write-ValidationSectionHeader -Title 'Rule Issue Adjudication' | Write-Host
            }
            $reconciledRuleIssuesPath = Join-Path $runDirectory 'workbench-rule-issues.json'
            $ruleIssuesParameters = @{
                RepositoryRoot = $repositoryRoot
                DisplayPath = $reconciledDisplayPath
                OutputPath = $reconciledRuleIssuesPath
                DisplaySchemaPath = $displaySchemaPath
                RuleIssuesSchemaPath = $ruleIssuesSchemaPath
                EvaluatorCommand = $EvaluatorCommand
                Model = $Model
                ReasoningEffort = $AssessmentReasoningEffort
                MaxRetries = $MaxRetries
                MaxParallelShards = $MaxParallelBatches
                OutputFormat = 'Json'
                ShowProgress = $OutputFormat -eq 'Text'
            }
            $ruleIssuesStopwatch = [Diagnostics.Stopwatch]::StartNew()
            $ruleIssuesOutput = @(& $ruleIssuesExporterPath @ruleIssuesParameters 2>&1)
            $ruleIssuesSucceeded = $?
            if (-not $ruleIssuesSucceeded) {
                throw "Rule Issues export failed: $(($ruleIssuesOutput | Out-String).Trim())"
            }
            $script:ruleIssuesResult = ($ruleIssuesOutput | Out-String) | ConvertFrom-Json
            $reconciledRuleIssuesContent = Get-Content -LiteralPath $reconciledRuleIssuesPath -Raw
            if (-not ($reconciledRuleIssuesContent | Test-Json -SchemaFile $ruleIssuesSchemaPath -ErrorAction Stop)) {
                throw 'Reconciled Workbench Rule Issues do not satisfy their schema'
            }
            $reconciledDisplay = $reconciledDisplayContent | ConvertFrom-Json -DateKind String
            $reconciledRuleIssues = $reconciledRuleIssuesContent | ConvertFrom-Json -DateKind String
            $displaySourceFiles = @($reconciledDisplay.sourceFiles | ForEach-Object { "$($_.sourceDefinitionId)`0$($_.sourceId)`0$($_.contentSha256)" } | Sort-Object -CaseSensitive)
            $ruleIssueSourceFiles = @($reconciledRuleIssues.sourceFiles | ForEach-Object { "$($_.sourceDefinitionId)`0$($_.sourceId)`0$($_.contentSha256)" } | Sort-Object -CaseSensitive)
            if (@(Compare-Object $displaySourceFiles $ruleIssueSourceFiles -SyncWindow 0).Count -ne 0) {
                throw 'Workbench display and Rule Issues source files do not match'
            }
            $ruleIssuesStopwatch.Stop()
            if ($OutputFormat -eq 'Text') {
                Write-ValidationSectionHeader -Title 'Rule Issue Adjudication Summary' | Write-Host
                Write-Host ("  {0,-17}: {1} grouped" -f 'Rule Issues', @($reconciledRuleIssues.issues).Count)
                Write-Host ("  {0,-17}: {1} total | {2} cached | {3} evaluated" -f 'Batches', [int]$ruleIssuesResult.componentCount, [int]$ruleIssuesResult.cachedComponentCount, [int]$ruleIssuesResult.evaluatedComponentCount)
                Write-Host ("  {0,-17}: {1}" -f 'Elapsed', (Format-ElapsedDuration -Milliseconds ([long]$ruleIssuesStopwatch.ElapsedMilliseconds)))
            }
            Complete-WorkbenchStage -Name $script:workbenchPhase

            $script:workbenchPhase = 'WORKBENCH DISPLAY'
            if ($OutputFormat -eq 'Text') {
                Write-ValidationSectionHeader -Title 'Workbench UI Artifact Publication' | Write-Host
                Write-Host ("  {0,-17}: {1} total" -f 'Artifacts', 2)
                Write-Host ''
                Write-Host (Format-ValidationStatusLine -Status 'running' -Name 'workbench/display' -Detail 'Validating and publishing Workbench artifacts' -NameWidth 42)
            }
            $publicationStopwatch = [Diagnostics.Stopwatch]::StartNew()
            if (-not ($reconciledDisplayContent | Test-Json -SchemaFile $displaySchemaPath -ErrorAction Stop)) {
                throw 'Staged Workbench display does not satisfy its schema'
            }
            if (-not ($reconciledRuleIssuesContent | Test-Json -SchemaFile $ruleIssuesSchemaPath -ErrorAction Stop)) {
                throw 'Staged Workbench Rule Issues do not satisfy their schema'
            }
            foreach ($inventoryPath in $currentInventoryPaths) {
                Copy-FileAtomically -SourcePath $inventoryPath -DestinationPath (Join-Path ([IO.Path]::GetFullPath($InventoryDirectory)) ([IO.Path]::GetFileName($inventoryPath)))
            }
            Copy-FileAtomically -SourcePath $reconciledRuleIssuesPath -DestinationPath $stagedRuleIssuesPath
            Copy-FileAtomically -SourcePath $reconciledDisplayPath -DestinationPath $stagedDisplayPath
            $publicationStopwatch.Stop()
            if ($OutputFormat -eq 'Text') {
                Write-Host (Format-ValidationStatusLine -Status 'passed' -Name 'workbench/display' -Detail ("Candidate and Rule Issues artifacts published : [Elapsed: {0}]" -f (Format-ElapsedDuration -Milliseconds ([long]$publicationStopwatch.ElapsedMilliseconds))) -NameWidth 42)
            }
            Complete-WorkbenchStage -Name $script:workbenchPhase
        return ($reconciledDisplayContent | ConvertFrom-Json)
    }
    finally {
        Remove-Item -LiteralPath $runDirectory -Recurse -Force -ErrorAction SilentlyContinue
    }
}

if ($OutputFormat -eq 'Text') {
    Write-ValidationSectionHeader -Title 'Hosted Rule Workbench'
    Write-ValidationSummary -Fields ([ordered]@{
        'Cache Directory' = $resolvedAssessmentCacheDirectory
        'Reconciliation Cache' = $resolvedReconciliationCacheDirectory
    })
}
try {
    $stagedDisplay = Update-StagedDisplay
}
catch {
    $failureMessage = ($_.Exception.Message -replace '\s+', ' ').Trim()
    $failure = [ordered]@{
        status = 'failed'
        phase = $script:workbenchPhase
        error = $failureMessage
        assessmentCacheDirectory = $resolvedAssessmentCacheDirectory
        reconciliationCacheDirectory = $resolvedReconciliationCacheDirectory
        assessmentResumeDirectory = $resolvedAssessmentResumeDirectory
        assessmentRecoveryMode = $assessmentRecoveryMode
        cacheMode = $cacheMode
    }
    if ($OutputFormat -eq 'Json') {
        $failure | ConvertTo-Json -Depth 5
    }
    else {
        $failureStages = @($workbenchStages.ToArray()) + @([pscustomobject]@{ status = 'failed'; name = $failure.phase })
        Write-ValidationSectionHeader -Title 'Workbench Summary'
        Write-ValidationSummary -Fields ([ordered]@{
            Status = 'FAILED'
            Stages = $failureStages.Count
            Passed = @($failureStages | Where-Object status -eq 'passed').Count
            Failed = 1
        })
        Write-ValidationSectionHeader -Title 'Workbench Stages'
        Write-ValidationTwoColumnTable -Rows $failureStages -FirstHeader 'Status' -FirstProperty 'status' -SecondHeader 'Stage' -SecondProperty 'name' -UppercaseFirst
        Write-ValidationSectionHeader -Title 'Failures'
        Write-Output ("  - {0}: {1}" -f $failure.phase, $failure.error)
        Complete-ValidationTextOutput
    }
    exit 1
}
$stagedCandidates = @($stagedDisplay.candidates)
$stagedRuleIssues = Get-Content -LiteralPath $stagedRuleIssuesPath -Raw | ConvertFrom-Json -DateKind String
$url = "http://127.0.0.1:$Port/"
$result = [ordered]@{
    status = 'ready'
    url = $url
    siteDirectory = $resolvedSiteDirectory
    displayPath = $stagedDisplayPath
    ruleIssuesPath = $stagedRuleIssuesPath
    ruleIssueCount = @($stagedRuleIssues.issues).Count
    protectedRuleIssueCount = @($stagedRuleIssues.issues | Where-Object { @($_.protectedRuleIds).Count -gt 0 }).Count
    blockingRuleIssueCount = @($stagedRuleIssues.issues | Where-Object blocking).Count
    assessmentCacheDirectory = $resolvedAssessmentCacheDirectory
    reconciliationCacheDirectory = $resolvedReconciliationCacheDirectory
    assessmentResumeDirectory = $resolvedAssessmentResumeDirectory
    assessmentRecoveryMode = $assessmentRecoveryMode
    cacheMode = $cacheMode
    discoveredCandidateCount = $stagedCandidates.Count
    evaluatedCandidateCount = $stagedCandidates.Count
    ruleCandidateCount = $stagedCandidates.Count
    reconciliationStatus = [string]$stagedDisplay.reconciliation.status
    capacityReportCount = @($stagedDisplay.guidanceCapacity.reports).Count
    assessment = $assessmentResult
    displayBuildMode = if ($Rebuild) { 'REBUILT_CURRENT_SOURCES' } else { 'REUSED_VALIDATED_DISPLAY' }
    readOnly = $true
    allowedMethods = @('GET', 'HEAD', 'POST')
    shutdownEndpoint = 'POST /shutdown'
    relationshipEndpoint = 'POST /reconcile-rule'
    serving = -not $StageOnly
}
$workbenchSummaryFields = [ordered]@{
    Status = 'PASSED'
    Mode = if ($StageOnly) { 'STAGE ONLY' } else { 'SERVER' }
    Stages = "{0}/{0} passed" -f $workbenchStages.Count
    Candidates = "{0} evaluated" -f $result.evaluatedCandidateCount
    'Rule Issues' = "{0} total | {1} protected | {2} blocking" -f $result.ruleIssueCount, $result.protectedRuleIssueCount, $result.blockingRuleIssueCount
    Assessment = if ($Force) { 'Forced rebuild from current sources' } elseif ($Rebuild) { 'Rebuilt from current sources' } else { 'Reused validated display' }
    'Cache Mode' = if ($Force) { 'Force refresh' } else { 'Reuse compatible results' }
    Capacity = "{0} reports" -f $result.capacityReportCount
    'Workbench Site' = $result.siteDirectory
    Server = if ($StageOnly) { 'Not started' } else { "Running at $url" }
}

if ($StageOnly) {
    if ($OutputFormat -eq 'Json') {
        $result | ConvertTo-Json -Depth 5
    }
    else {
        Write-ValidationSectionHeader -Title 'Workbench Summary'
        Write-ValidationSummary -Fields $workbenchSummaryFields
        Write-ValidationSectionHeader -Title 'Workbench Stages'
        Write-ValidationTwoColumnTable -Rows $workbenchStages.ToArray() -FirstHeader 'Status' -FirstProperty 'status' -SecondHeader 'Stage' -SecondProperty 'name' -UppercaseFirst
        Complete-ValidationTextOutput
    }
    return
}

function Write-HttpResponse {
    param(
        [Parameter(Mandatory = $true)][IO.Stream]$Stream,
        [Parameter(Mandatory = $true)][int]$StatusCode,
        [Parameter(Mandatory = $true)][string]$StatusText,
        [Parameter(Mandatory = $true)][string]$ContentType,
        [Parameter(Mandatory = $true)][byte[]]$Body,
        [Parameter(Mandatory = $true)][bool]$IncludeBody
    )

    $headers = @(
        "HTTP/1.1 $StatusCode $StatusText",
        "Content-Type: $ContentType",
        "Content-Length: $($Body.Length)",
        'Cache-Control: no-store',
        "Content-Security-Policy: default-src 'self'; script-src 'self'; style-src 'self'; font-src 'self'; connect-src 'self'; img-src 'self' data:; object-src 'none'; base-uri 'none'; frame-ancestors 'none'",
        'X-Content-Type-Options: nosniff',
        'Referrer-Policy: no-referrer',
        'Connection: close',
        '',
        ''
    ) -join "`r`n"
    $headerBytes = [Text.Encoding]::ASCII.GetBytes($headers)
    $Stream.Write($headerBytes, 0, $headerBytes.Length)
    if ($IncludeBody -and $Body.Length -gt 0) {
        $Stream.Write($Body, 0, $Body.Length)
    }
    $Stream.Flush()
}

function Test-ShutdownToken {
    param(
        [AllowNull()][string]$Candidate,
        [Parameter(Mandatory = $true)][string]$Expected
    )

    if ([string]::IsNullOrWhiteSpace($Candidate) -or $Candidate.Length -ne $Expected.Length) {
        return $false
    }
    $candidateBytes = [Text.Encoding]::ASCII.GetBytes($Candidate)
    $expectedBytes = [Text.Encoding]::ASCII.GetBytes($Expected)
    return [Security.Cryptography.CryptographicOperations]::FixedTimeEquals($candidateBytes, $expectedBytes)
}

function Read-HttpRequestBody {
    param(
        [Parameter(Mandatory = $true)][IO.StreamReader]$Reader,
        [Parameter(Mandatory = $true)][hashtable]$Headers,
        [ValidateRange(1, 16777216)][int]$MaximumBytes = 16777216
    )

    $contentLengthValue = [string]$Headers['Content-Length']
    $contentLength = 0
    if (-not [int]::TryParse($contentLengthValue, [ref]$contentLength) -or $contentLength -lt 1 -or $contentLength -gt $MaximumBytes) {
        throw 'Request body length is invalid'
    }
    $buffer = New-Object char[] $contentLength
    $offset = 0
    while ($offset -lt $contentLength) {
        $read = $Reader.ReadBlock($buffer, $offset, $contentLength - $offset)
        if ($read -le 0) {
            throw 'Request body ended before Content-Length bytes were read'
        }
        $offset += $read
    }
    return -join $buffer
}

$listener = [Net.Sockets.TcpListener]::new([Net.IPAddress]::Loopback, $Port)
$allowedHosts = @("127.0.0.1:$Port", "localhost:$Port")
try {
    $listener.Start()
    if (-not $NoLaunch) {
        Start-Process $url
    }
    if ($OutputFormat -eq 'Json') {
        $result | ConvertTo-Json -Depth 5
    }
    else {
        Write-ValidationSectionHeader -Title 'Workbench Summary'
        Write-ValidationSummary -Fields $workbenchSummaryFields
        Write-ValidationSectionHeader -Title 'Workbench Stages'
        Write-ValidationTwoColumnTable -Rows $workbenchStages.ToArray() -FirstHeader 'Status' -FirstProperty 'status' -SecondHeader 'Stage' -SecondProperty 'name' -UppercaseFirst
        Write-Output ''
        Write-Output 'Press Ctrl+C to stop the Workbench.'
        Complete-ValidationTextOutput
    }

    $shutdownRequested = $false
    while (-not $shutdownRequested) {
        if ($OwnerProcessId -and -not (Get-Process -Id $OwnerProcessId -ErrorAction SilentlyContinue)) {
            break
        }
        $acceptTask = $listener.AcceptTcpClientAsync()
        while (-not $acceptTask.Wait(250)) {
            if ($OwnerProcessId -and -not (Get-Process -Id $OwnerProcessId -ErrorAction SilentlyContinue)) {
                $shutdownRequested = $true
                break
            }
        }
        if ($shutdownRequested) {
            break
        }
        $client = $acceptTask.GetAwaiter().GetResult()
        $stream = $null
        try {
            $stream = $client.GetStream()
            $reader = [IO.StreamReader]::new($stream, [Text.Encoding]::UTF8, $false, 1024, $true)
            $requestLine = $reader.ReadLine()
            if ([string]::IsNullOrWhiteSpace($requestLine)) {
                continue
            }
            $requestHeaders = @{}
            while ($true) {
                $headerLine = $reader.ReadLine()
                if ([string]::IsNullOrEmpty($headerLine)) {
                    break
                }
                if ($headerLine -match '^(?<name>[^:]+):\s*(?<value>.*)$') {
                    $requestHeaders[[string]$Matches['name']] = [string]$Matches['value']
                }
            }

            if ($requestLine -notmatch '^(?<method>[A-Z]+) (?<target>\S+) HTTP/1\.[01]$') {
                Write-HttpResponse -Stream $stream -StatusCode 400 -StatusText 'Bad Request' -ContentType 'text/plain; charset=utf-8' -Body ([Text.Encoding]::UTF8.GetBytes('Bad Request')) -IncludeBody $true
                continue
            }

            $method = [string]$Matches['method']
            $requestUri = [Uri]("http://127.0.0.1$($Matches['target'])")
            $requestHost = [string]$requestHeaders['Host']
            if ([string]::IsNullOrWhiteSpace($requestHost) -or $requestHost.Trim() -notin $allowedHosts) {
                Write-HttpResponse -Stream $stream -StatusCode 421 -StatusText 'Misdirected Request' -ContentType 'text/plain; charset=utf-8' -Body ([Text.Encoding]::UTF8.GetBytes('Misdirected Request')) -IncludeBody $true
                continue
            }
            if ($method -in @('GET', 'HEAD') -and $requestUri.AbsolutePath -eq '/runtime-config') {
                $runtimeConfig = $shutdownConfig | ConvertFrom-Json
                $runtimeConfig | Add-Member -NotePropertyName savedRuleAuthoritySha256 -NotePropertyValue (Get-SavedRuleAuthoritySha256 @savedAuthorityParameters)
                $runtimeConfigBytes = [Text.Encoding]::UTF8.GetBytes(($runtimeConfig | ConvertTo-Json -Depth 20 -Compress))
                Write-HttpResponse -Stream $stream -StatusCode 200 -StatusText 'OK' -ContentType 'application/json; charset=utf-8' -Body $runtimeConfigBytes -IncludeBody ($method -eq 'GET')
                continue
            }
            if ($method -eq 'POST' -and $requestUri.AbsolutePath -eq '/shutdown') {
                $providedToken = [string]$requestHeaders['X-Workbench-Shutdown-Token']
                if (-not (Test-ShutdownToken -Candidate $providedToken -Expected $shutdownToken)) {
                    Write-HttpResponse -Stream $stream -StatusCode 403 -StatusText 'Forbidden' -ContentType 'text/plain; charset=utf-8' -Body ([Text.Encoding]::UTF8.GetBytes('Forbidden')) -IncludeBody $true
                    continue
                }
                $shutdownBody = [Text.Encoding]::UTF8.GetBytes('{"status":"shutting-down"}')
                Write-HttpResponse -Stream $stream -StatusCode 200 -StatusText 'OK' -ContentType 'application/json; charset=utf-8' -Body $shutdownBody -IncludeBody $true
                $shutdownRequested = $true
                continue
            }

            if ($method -eq 'POST' -and $requestUri.AbsolutePath -eq '/reconcile-rule') {
                $providedToken = [string]$requestHeaders['X-Workbench-Operation-Token']
                if (-not (Test-ShutdownToken -Candidate $providedToken -Expected $operationToken)) {
                    Write-HttpResponse -Stream $stream -StatusCode 403 -StatusText 'Forbidden' -ContentType 'text/plain; charset=utf-8' -Body ([Text.Encoding]::UTF8.GetBytes('Forbidden')) -IncludeBody $true
                    continue
                }
                $requestPath = Join-Path ([IO.Path]::GetTempPath()) "hosted-rule-request-$([Guid]::NewGuid().ToString('N')).json"
                $outputPath = Join-Path ([IO.Path]::GetTempPath()) "hosted-rule-result-$([Guid]::NewGuid().ToString('N')).json"
                try {
                    $requestBody = Read-HttpRequestBody -Reader $reader -Headers $requestHeaders
                    $requestEnvelope = $requestBody | ConvertFrom-Json
                    if (Compare-Object -ReferenceObject @('payloadBase64') -DifferenceObject @($requestEnvelope.PSObject.Properties.Name)) {
                        throw 'Request envelope has an unexpected property set'
                    }
                    $requestBytes = [Convert]::FromBase64String([string]$requestEnvelope.payloadBase64)
                    if ($requestBytes.Length -lt 1 -or $requestBytes.Length -gt 8388608) {
                        throw 'Decoded request payload length is invalid'
                    }
                    $null = [Text.UTF8Encoding]::new($false, $true).GetString($requestBytes)
                    [IO.File]::WriteAllBytes($requestPath, $requestBytes)
                    $relationshipParameters = @{
                        RequestPath = $requestPath
                        OutputPath = $outputPath
                        RepositoryRoot = $repositoryRoot
                        CacheDirectory = $resolvedManualRelationshipCacheDirectory
                        EvaluatorCommand = $EvaluatorCommand
                        Model = $Model
                        ReasoningEffort = $AssessmentReasoningEffort
                        DisplayPath = $stagedDisplayPath
                        RuleIssuesPath = $stagedRuleIssuesPath
                        AdjudicationEvaluatorScriptPath = $AdjudicationEvaluatorScriptPath
                    }
                    if ($null -ne $resolvedRelationshipEvaluatorScriptPath) {
                        $relationshipParameters.EvaluatorScriptPath = $resolvedRelationshipEvaluatorScriptPath
                    }
                    $relationshipOutput = @(& pwsh -NoProfile -File $savedRuleEvaluationPath @relationshipParameters 2>&1)
                    if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $outputPath -PathType Leaf)) {
                        throw "Scoped relationship evaluator failed: $(($relationshipOutput | Out-String).Trim())"
                    }
                    $responseBody = [IO.File]::ReadAllBytes($outputPath)
                    Write-HttpResponse -Stream $stream -StatusCode 200 -StatusText 'OK' -ContentType 'application/json; charset=utf-8' -Body $responseBody -IncludeBody $true
                }
                catch {
                    Write-Warning "Scoped relationship check failed: $($_.Exception.Message)"
                    Write-HttpResponse -Stream $stream -StatusCode 500 -StatusText 'Internal Server Error' -ContentType 'application/json; charset=utf-8' -Body ([Text.Encoding]::UTF8.GetBytes('{"error":"Scoped relationship check failed"}')) -IncludeBody $true
                }
                finally {
                    Remove-Item -LiteralPath $requestPath, $outputPath -Force -ErrorAction SilentlyContinue
                }
                continue
            }

            if ($method -notin @('GET', 'HEAD')) {
                Write-HttpResponse -Stream $stream -StatusCode 405 -StatusText 'Method Not Allowed' -ContentType 'text/plain; charset=utf-8' -Body ([Text.Encoding]::UTF8.GetBytes('Method Not Allowed')) -IncludeBody $true
                continue
            }

            $relativePath = [Uri]::UnescapeDataString($requestUri.AbsolutePath).TrimStart('/')
            if ([string]::IsNullOrWhiteSpace($relativePath)) {
                $relativePath = 'index.html'
            }
            $requestedPath = [IO.Path]::GetFullPath((Join-Path $resolvedSiteDirectory $relativePath.Replace('/', [IO.Path]::DirectorySeparatorChar)))
            $sitePrefix = $resolvedSiteDirectory.TrimEnd([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar) + [IO.Path]::DirectorySeparatorChar
            if (-not $requestedPath.StartsWith($sitePrefix, [StringComparison]::OrdinalIgnoreCase) -or -not (Test-Path -LiteralPath $requestedPath -PathType Leaf)) {
                Write-HttpResponse -Stream $stream -StatusCode 404 -StatusText 'Not Found' -ContentType 'text/plain; charset=utf-8' -Body ([Text.Encoding]::UTF8.GetBytes('Not Found')) -IncludeBody ($method -eq 'GET')
                continue
            }

            $contentType = switch ([IO.Path]::GetExtension($requestedPath).ToLowerInvariant()) {
                '.html' { 'text/html; charset=utf-8' }
                '.js' { 'text/javascript; charset=utf-8' }
                '.css' { 'text/css; charset=utf-8' }
                '.svg' { 'image/svg+xml' }
                '.json' { 'application/json; charset=utf-8' }
                default { 'application/octet-stream' }
            }
            $body = [IO.File]::ReadAllBytes($requestedPath)
            Write-HttpResponse -Stream $stream -StatusCode 200 -StatusText 'OK' -ContentType $contentType -Body $body -IncludeBody ($method -eq 'GET')
        }
        catch {
            if ($null -ne $stream -and $stream.CanWrite) {
                try {
                    Write-HttpResponse -Stream $stream -StatusCode 500 -StatusText 'Internal Server Error' -ContentType 'text/plain; charset=utf-8' -Body ([Text.Encoding]::UTF8.GetBytes('Internal Server Error')) -IncludeBody $true
                }
                catch { }
            }
        }
        finally {
            $client.Dispose()
        }
    }
}
finally {
    $listener.Stop()
}
