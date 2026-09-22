[CmdletBinding()]
param(
    [ValidateRange(1024, 65535)]
    [int]$Port = 43143,

    [ValidateRange(1, 2147483647)]
    [int]$OwnerProcessId,

    [string]$SiteDirectory = (Join-Path ([IO.Path]::GetTempPath()) 'hosted-rule-workbench/site'),

    [string]$DisplayPath,

    [string]$InventoryDirectory = (Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'terraform-azurerm-ai-assisted-development/hosted-rule-intake/inventories'),

    [string]$AssessmentCacheDirectory = (Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'hosted-workbench/assessment-cache'),

    [string]$ReconciliationCacheDirectory = (Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'hosted-workbench/reconciliation-cache'),

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

    [switch]$StageOnly,

    [switch]$NoLaunch,

    [ValidateSet('Text', 'Json')]
    [string]$OutputFormat = 'Text'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$validationOutputModulePath = Join-Path $PSScriptRoot '../../tools/ValidationOutput.psm1'
Import-Module -Name $validationOutputModulePath -Force

$repositoryRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
$workbenchSource = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../workbench'))
$workbenchIconSource = Join-Path $workbenchSource 'icons'
$catalogRoot = Join-Path $PSScriptRoot '../copilot-rule-catalog'
$displaySchemaPath = Join-Path $catalogRoot 'assessment-reconciliation/workbench-display-v4.schema.json'
$sourceDefinitionSetPath = Join-Path $catalogRoot 'source-definitions/source-definition-set.json'
$inventoryCollectorPath = Join-Path $PSScriptRoot 'internal/collection/New-SourceInventory.ps1'
$sourceAssessmentPath = Join-Path $PSScriptRoot 'internal/assessment/Invoke-SourceAssessment.ps1'
$assessmentReconciliationPath = Join-Path $PSScriptRoot 'internal/reconciliation/Invoke-AssessmentReconciliation.ps1'
$guidanceCapacityPath = Join-Path $PSScriptRoot 'internal/workbench/Get-GuidanceCapacity.ps1'
$resolvedSiteDirectory = [IO.Path]::GetFullPath($SiteDirectory)
$resolvedAssessmentCacheDirectory = [IO.Path]::GetFullPath($AssessmentCacheDirectory)
$resolvedReconciliationCacheDirectory = [IO.Path]::GetFullPath($ReconciliationCacheDirectory)
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

foreach ($requiredPath in @($workbenchSource, $workbenchIconSource, $displaySchemaPath, $sourceDefinitionSetPath, $inventoryCollectorPath, $sourceAssessmentPath, $assessmentReconciliationPath, $guidanceCapacityPath)) {
    if (-not (Test-Path -LiteralPath $requiredPath)) {
        throw "Required Workbench source was not found: $requiredPath"
    }
}

function Find-AutomaticAssessmentRecoveryDirectory {
    param(
        [Parameter(Mandatory = $true)][string]$ManagedRoot,
        [Parameter(Mandatory = $true)][string]$CurrentContractPath
    )

    if (-not (Test-Path -LiteralPath $ManagedRoot -PathType Container)) {
        return $null
    }
    $currentContractHash = (Get-FileHash -LiteralPath $CurrentContractPath -Algorithm SHA256).Hash
    foreach ($candidate in @(Get-ChildItem -LiteralPath $ManagedRoot -Directory | Sort-Object LastWriteTime -Descending)) {
        $retainedContractPath = Join-Path $candidate.FullName 'repository/hosted_copilot/copilot-rule-catalog/rule-assessments/source-assessment-v4.json'
        if (-not (Test-Path -LiteralPath $retainedContractPath -PathType Leaf) -or (Get-FileHash -LiteralPath $retainedContractPath -Algorithm SHA256).Hash -cne $currentContractHash) {
            continue
        }
        $reusableBatch = @(Get-ChildItem -LiteralPath $candidate.FullName -Directory | Where-Object {
            (Test-Path -LiteralPath (Join-Path $_.FullName 'source-records.json') -PathType Leaf) -and
                (Test-Path -LiteralPath (Join-Path $_.FullName 'response.json') -PathType Leaf)
        } | Select-Object -First 1)
        if ($reusableBatch.Count -eq 1) {
            return $candidate.FullName
        }
    }
    return $null
}

function Find-AutomaticReconciliationRecoveryDirectory {
    param(
        [Parameter(Mandatory = $true)][string]$ManagedRoot,
        [Parameter(Mandatory = $true)][string]$Evaluator,
        [Parameter(Mandatory = $true)][string]$Model,
        [Parameter(Mandatory = $true)][string]$ReasoningEffort
    )

    if (-not (Test-Path -LiteralPath $ManagedRoot -PathType Container)) {
        return $null
    }
    foreach ($candidate in @(Get-ChildItem -LiteralPath $ManagedRoot -Directory | Sort-Object LastWriteTime -Descending)) {
        $configurationMatches = $false
        $configurationPath = Join-Path $candidate.FullName 'reconciliation-run.json'
        $baselinePath = Join-Path $candidate.FullName 'source-assessment-baseline.json'
        try {
            if (Test-Path -LiteralPath $configurationPath -PathType Leaf) {
                $configuration = Get-Content -LiteralPath $configurationPath -Raw | ConvertFrom-Json
                $configurationMatches = [string]$configuration.evaluator -ceq $Evaluator -and [string]$configuration.model -ceq $Model -and [string]$configuration.reasoningEffort -ceq $ReasoningEffort
            }
            elseif (Test-Path -LiteralPath $baselinePath -PathType Leaf) {
                $baseline = Get-Content -LiteralPath $baselinePath -Raw | ConvertFrom-Json
                $configurationMatches = [string]$baseline.runConfiguration.evaluator -ceq $Evaluator -and [string]$baseline.runConfiguration.model -ceq $Model -and [string]$baseline.runConfiguration.reasoningEffort -ceq $ReasoningEffort
            }
        }
        catch {
            $configurationMatches = $false
        }
        if (-not $configurationMatches) {
            continue
        }
        $reusableBatch = @(Get-ChildItem -LiteralPath (Join-Path $candidate.FullName 'batches') -Directory -ErrorAction SilentlyContinue | Where-Object {
            (Test-Path -LiteralPath (Join-Path $_.FullName 'source-assessment-baseline.json') -PathType Leaf) -and
                (Test-Path -LiteralPath (Join-Path $_.FullName 'assessment-reconciliation-draft.json') -PathType Leaf)
        } | Select-Object -First 1)
        if ($reusableBatch.Count -eq 1) {
            return $candidate.FullName
        }
    }
    return $null
}

if (-not (Test-Path -LiteralPath $resolvedSiteDirectory -PathType Container)) {
    New-Item -ItemType Directory -Path $resolvedSiteDirectory -Force | Out-Null
}

$ownedAssetNames = @('index.html', 'app.js', 'hierarchical-view.js', 'styles.css', 'favicon.svg')
foreach ($assetName in $ownedAssetNames) {
    Copy-Item -LiteralPath (Join-Path $workbenchSource $assetName) -Destination (Join-Path $resolvedSiteDirectory $assetName) -Force
}
Copy-Item -LiteralPath $workbenchIconSource -Destination $resolvedSiteDirectory -Recurse -Force

$shutdownTokenBytes = New-Object byte[] 32
[Security.Cryptography.RandomNumberGenerator]::Fill($shutdownTokenBytes)
$shutdownToken = [Convert]::ToHexString($shutdownTokenBytes).ToLowerInvariant()
$maintainerIdentity = [ordered]@{
    status = 'unavailable'
    login = $null
    isCodeOwner = $false
    reason = 'GitHub CLI authentication is required for CODEOWNER-only Workbench actions.'
}
$targetRepository = [ordered]@{
    status = 'unavailable'
    repository = $null
    branch = $null
    commit = $null
    upstreamRepository = $null
    upstreamBranch = $null
    aheadBy = $null
    behindBy = $null
    reason = 'GitHub CLI authentication is required to resolve the promotion target.'
}
$ghCommand = Get-Command gh -ErrorAction SilentlyContinue
if ($null -ne $ghCommand) {
    $loginOutput = @(& $ghCommand.Source api user --jq .login 2>$null)
    if ($LASTEXITCODE -eq 0 -and -not [string]::IsNullOrWhiteSpace(($loginOutput | Out-String))) {
        $login = ($loginOutput | Select-Object -First 1).Trim()
        $codeOwnersPath = Join-Path $repositoryRoot '.github/CODEOWNERS'
        $applicableOwners = @()
        if (Test-Path -LiteralPath $codeOwnersPath -PathType Leaf) {
            foreach ($line in Get-Content -LiteralPath $codeOwnersPath) {
                $trimmed = $line.Trim()
                if ([string]::IsNullOrWhiteSpace($trimmed) -or $trimmed.StartsWith('#')) { continue }
                $parts = @($trimmed -split '\s+' | Where-Object { $_ })
                if ($parts.Count -ge 2 -and $parts[0] -in @('*', '/hosted_copilot/')) {
                    $applicableOwners = @($parts[1..($parts.Count - 1)])
                }
            }
        }
        $isCodeOwner = $applicableOwners -contains "@$login"
        $maintainerIdentity = [ordered]@{
            status = if ($isCodeOwner) { 'validated' } else { 'unauthorized' }
            login = $login
            isCodeOwner = $isCodeOwner
            reason = if ($isCodeOwner) { $null } else { 'The authenticated GitHub user is not a CODEOWNER for Hosted Toolkit changes.' }
        }

        $repositoryName = "$login/terraform-provider-azurerm"
        $repositoryOutput = @(& $ghCommand.Source api "repos/$repositoryName" 2>$null)
        if ($LASTEXITCODE -eq 0) {
            $repository = ($repositoryOutput | Out-String) | ConvertFrom-Json
            $branch = [string]$repository.default_branch
            $commitOutput = @(& $ghCommand.Source api "repos/$repositoryName/commits/$branch" --jq .sha 2>$null)
            $commit = ($commitOutput | Select-Object -First 1).Trim()
            if ($LASTEXITCODE -eq 0 -and $repository.fork -eq $true -and $repository.parent.full_name -eq 'hashicorp/terraform-provider-azurerm' -and $commit -match '^[0-9a-f]{40}$') {
                $upstreamRepository = [string]$repository.parent.full_name
                $upstreamBranch = [string]$repository.parent.default_branch
                $comparisonOutput = @(& $ghCommand.Source api "repos/$upstreamRepository/compare/$upstreamBranch...$login`:$branch" 2>$null)
                $comparison = if ($LASTEXITCODE -eq 0) { ($comparisonOutput | Out-String) | ConvertFrom-Json } else { $null }
                $targetRepository = [ordered]@{
                    status = 'validated'
                    repository = [string]$repository.full_name
                    branch = $branch
                    commit = $commit
                    upstreamRepository = $upstreamRepository
                    upstreamBranch = $upstreamBranch
                    aheadBy = if ($null -ne $comparison) { [int]$comparison.ahead_by } else { $null }
                    behindBy = if ($null -ne $comparison) { [int]$comparison.behind_by } else { $null }
                    reason = $null
                }
            }
            else {
                $targetRepository.reason = "The authenticated user's terraform-provider-azurerm repository is not a valid fork promotion target."
            }
        }
        else {
            $targetRepository.reason = "The authenticated user's terraform-provider-azurerm fork could not be resolved."
        }
    }
}
$shutdownConfig = [ordered]@{
    shutdownToken = $shutdownToken
    maintainerIdentity = $maintainerIdentity
    targetRepository = $targetRepository
} | ConvertTo-Json -Compress
[IO.File]::WriteAllText((Join-Path $resolvedSiteDirectory 'shutdown-config.js'), "globalThis.__HOSTED_RULE_WORKBENCH__ = $shutdownConfig;`n", [Text.UTF8Encoding]::new($false))

$stagedDisplayPath = Join-Path $resolvedSiteDirectory 'workbench-display.json'
$resolvedDisplayPath = if ([string]::IsNullOrWhiteSpace($DisplayPath)) { $null } else { [IO.Path]::GetFullPath($DisplayPath) }
if ($null -eq $resolvedDisplayPath -and $null -eq $resolvedAssessmentResumeDirectory) {
    $assessmentRecoveryRoot = Join-Path ([IO.Path]::GetTempPath()) 'hosted-source-assessment'
    $resolvedAssessmentResumeDirectory = Find-AutomaticAssessmentRecoveryDirectory -ManagedRoot $assessmentRecoveryRoot -CurrentContractPath (Join-Path $catalogRoot 'rule-assessments/source-assessment-v4.json')
    if ($null -ne $resolvedAssessmentResumeDirectory) {
        $assessmentRecoveryMode = 'AUTO'
    }
}
if ($null -eq $resolvedDisplayPath -and $null -eq $resolvedReconciliationResumeDirectory) {
    $reconciliationRecoveryRoot = Join-Path ([IO.Path]::GetTempPath()) 'hosted-assessment-reconciliation'
    $resolvedReconciliationResumeDirectory = Find-AutomaticReconciliationRecoveryDirectory -ManagedRoot $reconciliationRecoveryRoot -Evaluator $EvaluatorCommand -Model $Model -ReasoningEffort $AssessmentReasoningEffort
    if ($null -ne $resolvedReconciliationResumeDirectory) {
        $reconciliationRecoveryMode = 'AUTO'
    }
}
$assessmentResult = $null
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
    if ($null -eq $resolvedDisplayPath) {
        Remove-Item -LiteralPath $stagedDisplayPath -Force -ErrorAction SilentlyContinue
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
            Copy-FileAtomically -SourcePath $reconciledDisplayPath -DestinationPath $stagedDisplayPath
            Complete-WorkbenchStage -Name $workbenchPhase
            foreach ($inventoryPath in $currentInventoryPaths) {
                Copy-FileAtomically -SourcePath $inventoryPath -DestinationPath (Join-Path ([IO.Path]::GetFullPath($InventoryDirectory)) ([IO.Path]::GetFileName($inventoryPath)))
            }
        }
        finally {
            Remove-Item -LiteralPath $runDirectory -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
    else {
        $script:workbenchPhase = 'PREBUILT DISPLAY STAGING'
        if (-not (Test-Path -LiteralPath $resolvedDisplayPath -PathType Leaf)) {
            throw "DisplayPath was not found: $resolvedDisplayPath"
        }
        $displayContent = Get-Content -LiteralPath $resolvedDisplayPath -Raw
        if (-not ($displayContent | Test-Json -SchemaFile $displaySchemaPath -ErrorAction Stop)) {
            throw 'DisplayPath does not satisfy the Workbench display schema'
        }
        [IO.File]::WriteAllText($stagedDisplayPath, $displayContent.TrimEnd() + "`n", [Text.UTF8Encoding]::new($false))
        Complete-WorkbenchStage -Name $workbenchPhase
    }

    $script:workbenchPhase = 'DISPLAY VALIDATION'
    $content = Get-Content -LiteralPath $stagedDisplayPath -Raw
    if (-not ($content | Test-Json -SchemaFile $displaySchemaPath -ErrorAction Stop)) {
        throw 'Staged Workbench display does not satisfy its schema'
    }
    Complete-WorkbenchStage -Name $workbenchPhase
    return ($content | ConvertFrom-Json)
}

if ($OutputFormat -eq 'Text') {
    Write-ValidationSectionHeader -Title 'Hosted Rule Workbench'
    Write-ValidationSummary -Fields ([ordered]@{
        'Cache Directory' = $resolvedAssessmentCacheDirectory
        'Reconciliation Cache' = $resolvedReconciliationCacheDirectory
        'Assessment Recovery' = $(if ($null -eq $resolvedAssessmentResumeDirectory) { 'NONE' } else { "$assessmentRecoveryMode`: $resolvedAssessmentResumeDirectory" })
        'Reconciliation Recovery' = $(if ($null -eq $resolvedReconciliationResumeDirectory) { 'NONE' } else { "$reconciliationRecoveryMode`: $resolvedReconciliationResumeDirectory" })
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
        Write-ValidationSectionHeader -Title 'Hosted Rule Workbench Summary'
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
$url = "http://127.0.0.1:$Port/"
$result = [ordered]@{
    status = 'ready'
    url = $url
    siteDirectory = $resolvedSiteDirectory
    displayPath = $stagedDisplayPath
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
    reconciliationConflictCount = @($stagedDisplay.reconciliation.conflicts).Count
    capacityReportCount = @($stagedDisplay.guidanceCapacity.reports).Count
    assessment = $assessmentResult
    readOnly = $true
    allowedMethods = @('GET', 'HEAD')
    shutdownEndpoint = 'POST /shutdown'
    serving = -not $StageOnly
}

if ($StageOnly) {
    if ($OutputFormat -eq 'Json') {
        $result | ConvertTo-Json -Depth 5
    }
    else {
        Write-ValidationSectionHeader -Title 'Hosted Rule Workbench Summary'
        Write-ValidationSummary -Fields ([ordered]@{
            Status = 'PASSED'
            Stages = $workbenchStages.Count
            Passed = $workbenchStages.Count
            Failed = 0
            'Discovered Candidates' = $result.discoveredCandidateCount
            'AI-Evaluated Candidates' = $result.evaluatedCandidateCount
            Assessment = $(if ($null -eq $resolvedDisplayPath) { 'COMPLETED ABOVE' } else { 'PREBUILT DISPLAY' })
            'Assessment Cache' = $result.assessmentCacheDirectory
            'Reconciliation Cache' = $result.reconciliationCacheDirectory
            'Assessment Recovery' = $(if ($null -eq $result.assessmentResumeDirectory) { 'NONE' } else { "$($result.assessmentRecoveryMode): $($result.assessmentResumeDirectory)" })
            'Reconciliation Recovery' = $(if ($null -eq $result.reconciliationResumeDirectory) { 'NONE' } else { "$($result.reconciliationRecoveryMode): $($result.reconciliationResumeDirectory)" })
            Reconciliation = $(if ($result.reconciliationStatus -ceq 'blocked') { "BLOCKED ($($result.reconciliationConflictCount) conflicts)" } else { 'READY' })
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
        Write-ValidationSectionHeader -Title 'Hosted Rule Workbench Summary'
        Write-ValidationSummary -Fields ([ordered]@{
            Status = 'PASSED'
            Stages = $workbenchStages.Count
            Passed = $workbenchStages.Count
            Failed = 0
            URL = $url
            'Discovered Candidates' = $result.discoveredCandidateCount
            'AI-Evaluated Candidates' = $result.evaluatedCandidateCount
            Assessment = $(if ($null -eq $resolvedDisplayPath) { 'COMPLETED ABOVE' } else { 'PREBUILT DISPLAY' })
            'Assessment Cache' = $result.assessmentCacheDirectory
            'Reconciliation Cache' = $result.reconciliationCacheDirectory
            'Assessment Recovery' = $(if ($null -eq $result.assessmentResumeDirectory) { 'NONE' } else { "$($result.assessmentRecoveryMode): $($result.assessmentResumeDirectory)" })
            'Reconciliation Recovery' = $(if ($null -eq $result.reconciliationResumeDirectory) { 'NONE' } else { "$($result.reconciliationRecoveryMode): $($result.reconciliationResumeDirectory)" })
            Reconciliation = $(if ($result.reconciliationStatus -ceq 'blocked') { "BLOCKED ($($result.reconciliationConflictCount) conflicts)" } else { 'READY' })
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
            $reader = [IO.StreamReader]::new($stream, [Text.Encoding]::ASCII, $false, 1024, $true)
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
