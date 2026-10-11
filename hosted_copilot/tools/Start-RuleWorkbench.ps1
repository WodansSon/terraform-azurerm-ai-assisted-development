[CmdletBinding()]
param(
    [ValidateRange(1024, 65535)]
    [int]$Port = 43143,

    [ValidateRange(1, 2147483647)]
    [int]$OwnerProcessId,

    [string]$SiteDirectory = (Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'hosted-workbench/site'),

    [string]$InventoryDirectory = (Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'terraform-azurerm-ai-assisted-development/hosted-rule-intake/inventories'),

    [string]$AssessmentCacheDirectory = (Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'hosted-workbench/assessment-cache'),

    [string]$ReconciliationCacheDirectory = (Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'hosted-workbench/reconciliation-cache'),

    [string]$ManualRelationshipCacheDirectory = (Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'hosted-workbench/manual-relationship-cache'),

    [string]$AssessmentResumeDirectory,

    [string]$ReconciliationResumeDirectory,

    [string]$Model = 'gpt-5.4',

    [ValidateSet('low', 'medium', 'high', 'xhigh')]
    [string]$AssessmentReasoningEffort = 'high',

    [ValidateRange(0, 3)]
    [int]$MaxRetries = 1,

    [ValidateRange(1, 8)]
    [int]$MaxParallelBatches = 3,

    [string]$EvaluatorCommand = 'copilot',

    [string]$RelationshipEvaluatorScriptPath,

    [switch]$Rebuild,

    [switch]$SkipGitHubAuthorization,

    [switch]$StageOnly,

    [switch]$NoLaunch,

    [ValidateSet('Text', 'Json')]
    [string]$OutputFormat = 'Text'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$validationOutputModulePath = Join-Path $PSScriptRoot '../../tools/ValidationOutput.psm1'
$sourceEvidenceModulePath = Join-Path $PSScriptRoot 'modules/shared/SourceEvidenceValidation.psm1'
$workbenchGitHubContextModulePath = Join-Path $PSScriptRoot 'modules/workbench/Workbench.GitHubContext.psm1'
Import-Module -Name $validationOutputModulePath -Force
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
$guidanceCapacityPath = Join-Path $PSScriptRoot 'internal/workbench/Get-GuidanceCapacity.ps1'
$resolvedSiteDirectory = [IO.Path]::GetFullPath($SiteDirectory)
$resolvedAssessmentCacheDirectory = [IO.Path]::GetFullPath($AssessmentCacheDirectory)
$resolvedReconciliationCacheDirectory = [IO.Path]::GetFullPath($ReconciliationCacheDirectory)
$resolvedManualRelationshipCacheDirectory = [IO.Path]::GetFullPath($ManualRelationshipCacheDirectory)
$resolvedRelationshipEvaluatorScriptPath = if ([string]::IsNullOrWhiteSpace($RelationshipEvaluatorScriptPath)) { $null } else { [IO.Path]::GetFullPath($RelationshipEvaluatorScriptPath) }
$resolvedAssessmentResumeDirectory = if ([string]::IsNullOrWhiteSpace($AssessmentResumeDirectory)) { $null } else { [IO.Path]::GetFullPath($AssessmentResumeDirectory) }
$resolvedReconciliationResumeDirectory = if ([string]::IsNullOrWhiteSpace($ReconciliationResumeDirectory)) { $null } else { [IO.Path]::GetFullPath($ReconciliationResumeDirectory) }
$assessmentRecoveryMode = if ($null -eq $resolvedAssessmentResumeDirectory) { 'NONE' } else { 'EXPLICIT' }
$reconciliationRecoveryMode = if ($null -eq $resolvedReconciliationResumeDirectory) { 'NONE' } else { 'EXPLICIT' }
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
$assessmentResult = $null
$ruleIssuesResult = $null
$workbenchPhase = 'INITIALIZATION'
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
        Complete-WorkbenchStage -Name $workbenchPhase
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
                Write-Host ("[RUNNING]  collect/{0,-21} : Building current source inventory" -f $sourceDefinitionId)
            }
            $collectionOutput = @(& $inventoryCollectorPath -RepositoryRoot $repositoryRoot -SourceDefinitionPath (Join-Path $catalogRoot "source-definitions/$sourceDefinitionId.json") -OutputPath $inventoryPath -OutputFormat Json 2>&1)
            if ($LASTEXITCODE -ne 0) {
                throw "Source inventory collection failed for $sourceDefinitionId`: $(($collectionOutput | Out-String).Trim())"
            }
            $currentInventoryPaths.Add($inventoryPath)
            $priorInventoryPath = Join-Path ([IO.Path]::GetFullPath($InventoryDirectory)) "$sourceDefinitionId.json"
            if (Test-Path -LiteralPath $priorInventoryPath -PathType Leaf) {
                $priorInventoryPaths.Add($priorInventoryPath)
            }
        }
        Complete-WorkbenchStage -Name $workbenchPhase

            $assessmentSetPath = Join-Path $runDirectory 'assessment-set.json'
            $script:workbenchPhase = 'SOURCE ASSESSMENT'
            if ($OutputFormat -eq 'Text') {
                Write-ValidationSectionHeader -Title 'Assessment Status' | Write-Host
                Write-Host (Format-ValidationStatusLine -Status 'running' -Name 'source-assessment' -Detail 'Evaluating current source inventories' -NameWidth 42)
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
            $assessmentOutput = @(& $sourceAssessmentPath @assessmentParameters 2>&1)
            if ($LASTEXITCODE -ne 0) {
                throw "Source assessment failed: $(($assessmentOutput | Out-String).Trim())"
            }
            $script:assessmentResult = ($assessmentOutput | Out-String) | ConvertFrom-Json
            Complete-WorkbenchStage -Name $workbenchPhase

            $capacityPath = Join-Path $runDirectory 'guidance-capacity.json'
            $script:workbenchPhase = 'GUIDANCE CAPACITY'
            $capacityOutput = @(& $guidanceCapacityPath -HostedRoot (Join-Path $repositoryRoot 'hosted_copilot') -OutputFormat Json 2>&1)
            if ($LASTEXITCODE -ne 0) {
                throw "Guidance capacity calculation failed: $(($capacityOutput | Out-String).Trim())"
            }
            [IO.File]::WriteAllText($capacityPath, (($capacityOutput | Out-String).Trim() + "`n"), [Text.UTF8Encoding]::new($false))
            Complete-WorkbenchStage -Name $workbenchPhase

            if ($OutputFormat -eq 'Text') {
                Write-ValidationSectionHeader -Title 'Reconciliation Status' | Write-Host
                Write-Host '[RUNNING]  assessment-reconciliation   : Consolidating assessments into the Workbench display'
            }
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
            if ($null -ne $resolvedReconciliationResumeDirectory) {
                $reconciliationParameters.ResumeRunDirectory = $resolvedReconciliationResumeDirectory
            }
            $reconciliationOutput = @(& $assessmentReconciliationPath @reconciliationParameters 2>&1)
            if ($LASTEXITCODE -ne 0) {
                throw "Assessment reconciliation failed: $(($reconciliationOutput | Out-String).Trim())"
            }
            $reconciledDisplayContent = Get-Content -LiteralPath $reconciledDisplayPath -Raw
            if (-not ($reconciledDisplayContent | Test-Json -SchemaFile $displaySchemaPath -ErrorAction Stop)) {
                throw 'Reconciled Workbench display does not satisfy its schema'
            }
            Complete-WorkbenchStage -Name $workbenchPhase
            $script:workbenchPhase = 'CANDIDATE PROJECTION'
            Complete-WorkbenchStage -Name $workbenchPhase

            $script:workbenchPhase = 'RULE ISSUES EXPORT'
            if ($OutputFormat -eq 'Text') {
                Write-Host (Format-ValidationStatusLine -Status 'running' -Name 'assessment-reconciliation/rule-issues' -Detail 'Adjudicating grouped Rule Issues' -NameWidth 42)
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
            $ruleIssuesOutput = @(& $ruleIssuesExporterPath @ruleIssuesParameters 2>&1)
            if ($LASTEXITCODE -ne 0) {
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
            if ($OutputFormat -eq 'Text') {
                Write-Host (Format-ValidationStatusLine -Status 'passed' -Name 'assessment-reconciliation/rule-issues' -Detail ("{0} grouped issues | {1} cached | {2} evaluated" -f @($reconciledRuleIssues.issues).Count, [int]$ruleIssuesResult.cachedComponentCount, [int]$ruleIssuesResult.evaluatedComponentCount) -NameWidth 42)
            }
            Complete-WorkbenchStage -Name $workbenchPhase

            $script:workbenchPhase = 'WORKBENCH DISPLAY'
            if ($OutputFormat -eq 'Text') {
                Write-ValidationSectionHeader -Title 'Display' | Write-Host
                Write-Host (Format-ValidationStatusLine -Status 'running' -Name 'workbench/display' -Detail 'Validating and publishing Workbench artifacts' -NameWidth 42)
            }
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
            if ($OutputFormat -eq 'Text') {
                Write-Host (Format-ValidationStatusLine -Status 'passed' -Name 'workbench/display' -Detail 'Candidate and Rule Issues artifacts published' -NameWidth 42)
            }
            Complete-WorkbenchStage -Name $workbenchPhase
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
        phase = $workbenchPhase
        error = $failureMessage
        assessmentCacheDirectory = $resolvedAssessmentCacheDirectory
        reconciliationCacheDirectory = $resolvedReconciliationCacheDirectory
        assessmentResumeDirectory = $resolvedAssessmentResumeDirectory
        reconciliationResumeDirectory = $resolvedReconciliationResumeDirectory
        assessmentRecoveryMode = $assessmentRecoveryMode
        reconciliationRecoveryMode = $reconciliationRecoveryMode
    }
    if ($OutputFormat -eq 'Json') {
        $failure | ConvertTo-Json -Depth 5
    }
    else {
        $failureStages = @($workbenchStages.ToArray()) + @([pscustomobject]@{ status = 'failed'; name = $failure.phase })
        Write-ValidationSectionHeader -Title 'Summary'
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
$assessmentSummary = if ($Rebuild) { 'REBUILT FROM CURRENT SOURCES' } else { 'REUSED VALIDATED DISPLAY' }
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
    reconciliationResumeDirectory = $resolvedReconciliationResumeDirectory
    assessmentRecoveryMode = $assessmentRecoveryMode
    reconciliationRecoveryMode = $reconciliationRecoveryMode
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

if ($StageOnly) {
    if ($OutputFormat -eq 'Json') {
        $result | ConvertTo-Json -Depth 5
    }
    else {
        Write-ValidationSectionHeader -Title 'Summary'
        Write-ValidationSummary -Fields ([ordered]@{
            Status = 'PASSED'
            Stages = $workbenchStages.Count
            Passed = $workbenchStages.Count
            Failed = 0
            'Discovered Candidates' = $result.discoveredCandidateCount
            'AI-Evaluated Candidates' = $result.evaluatedCandidateCount
            Assessment = $assessmentSummary
            'Assessment Cache' = $result.assessmentCacheDirectory
            'Reconciliation Cache' = $result.reconciliationCacheDirectory
            'Assessment Recovery' = $(if ($null -eq $result.assessmentResumeDirectory) { 'NONE' } else { "$($result.assessmentRecoveryMode): $($result.assessmentResumeDirectory)" })
            'Reconciliation Recovery' = $(if ($null -eq $result.reconciliationResumeDirectory) { 'NONE' } else { "$($result.reconciliationRecoveryMode): $($result.reconciliationResumeDirectory)" })
            Reconciliation = 'READY'
            'Rule Issues' = $result.ruleIssueCount
            'Protected Rule Issues' = $result.protectedRuleIssueCount
            'Blocking Rule Issues' = $result.blockingRuleIssueCount
            'Capacity Reports' = $result.capacityReportCount
            'Site Directory' = $result.siteDirectory
            Serving = $result.serving
        })
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
        [ValidateRange(1, 1048576)][int]$MaximumBytes = 131072
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
        Write-ValidationSectionHeader -Title 'Summary'
        Write-ValidationSummary -Fields ([ordered]@{
            Status = 'PASSED'
            Stages = $workbenchStages.Count
            Passed = $workbenchStages.Count
            Failed = 0
            URL = $url
            'Discovered Candidates' = $result.discoveredCandidateCount
            'AI-Evaluated Candidates' = $result.evaluatedCandidateCount
            Assessment = $assessmentSummary
            'Assessment Cache' = $result.assessmentCacheDirectory
            'Reconciliation Cache' = $result.reconciliationCacheDirectory
            'Assessment Recovery' = $(if ($null -eq $result.assessmentResumeDirectory) { 'NONE' } else { "$($result.assessmentRecoveryMode): $($result.assessmentResumeDirectory)" })
            'Reconciliation Recovery' = $(if ($null -eq $result.reconciliationResumeDirectory) { 'NONE' } else { "$($result.reconciliationRecoveryMode): $($result.reconciliationResumeDirectory)" })
            Reconciliation = 'READY'
            'Capacity Reports' = $result.capacityReportCount
            'Site Directory' = $resolvedSiteDirectory
            'Repository Writes' = 'DISABLED'
        })
        Write-ValidationSectionHeader -Title 'Workbench Stages'
        Write-ValidationTwoColumnTable -Rows $workbenchStages.ToArray() -FirstHeader 'Status' -FirstProperty 'status' -SecondHeader 'Stage' -SecondProperty 'name' -UppercaseFirst
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
                    if ($requestBytes.Length -lt 1 -or $requestBytes.Length -gt 65536) {
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
                    }
                    if ($null -ne $resolvedRelationshipEvaluatorScriptPath) {
                        $relationshipParameters.EvaluatorScriptPath = $resolvedRelationshipEvaluatorScriptPath
                    }
                    $relationshipOutput = @(& pwsh -NoProfile -File $manualRelationshipPath @relationshipParameters 2>&1)
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
