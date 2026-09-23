[CmdletBinding()]
param(
    [string]$RepositoryRoot = (Join-Path $PSScriptRoot '../../../..'),

    [Parameter(Mandatory = $true)]
    [string]$AssessmentBaselinePath,

    [Parameter(Mandatory = $true)]
    [string[]]$InventoryPaths,

    [Parameter(Mandatory = $true)]
    [string]$GuidanceCapacityPath,

    [Parameter(Mandatory = $true)]
    [string]$OutputPath,

    [string]$HostedCatalogPath = (Join-Path $PSScriptRoot '../../../copilot-rule-catalog/instruction-catalog.json'),

    [string]$ReconciliationContractPath = (Join-Path $PSScriptRoot '../../../copilot-rule-catalog/assessment-reconciliation/assessment-reconciliation-v4.json'),

    [string]$BuilderPath = (Join-Path $PSScriptRoot 'New-WorkbenchDisplay.ps1'),

    [string]$EvaluatorCommand = 'copilot',

    [string]$EvaluatorScriptPath,

    [string]$ResumeRunDirectory,

    [string]$CacheDirectory = (Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'hosted-workbench/reconciliation-cache'),

    [string]$Model = 'gpt-5.4',

    [ValidateSet('low', 'medium', 'high', 'xhigh')]
    [string]$ReasoningEffort = 'high',

    [ValidateRange(0, 3)]
    [int]$MaxRetries = 1,

    [ValidateRange(0, 60000)]
    [int]$RetryDelayMilliseconds = 1000,

    [ValidateRange(1, 8)]
    [int]$MaxParallelBatches = 3,

    [object]$GeneratedAt = [DateTime]::UtcNow,

    [ValidateSet('Text', 'Json')]
    [string]$OutputFormat = 'Text',

    [switch]$Quiet
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$helpersPath = Join-Path $PSScriptRoot '../../modules/shared/HostedToolkit.Helpers.psm1'
Import-Module -Name $helpersPath -Force
$reconciliationBootstrapBytesPerSecondPerWorker = 650
$reconciliationStopwatch = [Diagnostics.Stopwatch]::StartNew()

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

function Get-EvaluatorJson {
    param([Parameter(Mandatory = $true)][AllowEmptyString()][string]$Content)

    $trimmed = $Content.Trim()
    if ($trimmed.StartsWith('```json', [StringComparison]::OrdinalIgnoreCase) -and $trimmed.EndsWith('```', [StringComparison]::Ordinal)) {
        $trimmed = $trimmed.Substring(7, $trimmed.Length - 10).Trim()
    }
    elseif ($trimmed.StartsWith('```', [StringComparison]::Ordinal) -and $trimmed.EndsWith('```', [StringComparison]::Ordinal)) {
        $trimmed = $trimmed.Substring(3, $trimmed.Length - 6).Trim()
    }
    $objectStart = $trimmed.IndexOf('{')
    $objectEnd = $trimmed.LastIndexOf('}')
    if ($objectStart -lt 0 -or $objectEnd -lt $objectStart) {
        throw 'Evaluator response does not contain a JSON object'
    }
    return $trimmed.Substring($objectStart, $objectEnd - $objectStart + 1)
}

function Test-EvaluatorDraftJson {
    param(
        [Parameter(Mandatory = $true)][string]$Json,
        [Parameter(Mandatory = $true)][string]$SchemaPath,
        [Parameter(Mandatory = $true)][int]$BatchNumber
    )

    try {
        $valid = Test-Json -Json $Json -SchemaFile $SchemaPath -ErrorAction Stop
    }
    catch {
        $exception = $_.Exception
        while ($null -ne $exception.InnerException) {
            $exception = $exception.InnerException
        }
        $parserDetail = [string]$exception.Message
        if ($Json -match '(?<=[\[:,])\s*undefined(?=\s*[,}\]])') {
            throw "Evaluator response for batch $BatchNumber is not valid JSON: bare undefined is invalid; omit optional properties instead ($parserDetail)"
        }
        if ([string]$_.FullyQualifiedErrorId -like 'InvalidJson*') {
            throw "Evaluator response for batch $BatchNumber is not valid JSON: $parserDetail"
        }
        throw "Evaluator response for batch $BatchNumber does not satisfy the reconciliation schema: $parserDetail"
    }
    if (-not $valid) {
        throw "Evaluator response for batch $BatchNumber does not satisfy the reconciliation schema"
    }
}

function Get-ReconciliationBaselineIdentityJson {
    param([Parameter(Mandatory = $true)][string]$Path)

    $baseline = Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json -DateKind String
    $baseline.PSObject.Properties.Remove('generatedAt')
    $baseline.PSObject.Properties.Remove('inventoryHashes')
    $baseline.PSObject.Properties.Remove('priorInventoryHashes')
    foreach ($entry in @($baseline.entries)) {
        if ($null -ne $entry.priorSourceEvidence) {
            $entry.priorSourceEvidence.PSObject.Properties.Remove('observedAt')
            $entry.priorSourceEvidence.PSObject.Properties.Remove('inventorySha256')
        }
        foreach ($assessment in @($entry.assessments)) {
            $assessment.assessmentProvenance.PSObject.Properties.Remove('assessedAt')
        }
    }
    return $baseline | ConvertTo-Json -Depth 100 -Compress
}

function Write-JsonAtomically {
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
        [IO.File]::WriteAllText($temporaryPath, (($Value | ConvertTo-Json -Depth 100) + "`n"), [Text.UTF8Encoding]::new($false))
        [IO.File]::Move($temporaryPath, $Path, $true)
    }
    finally {
        Remove-Item -LiteralPath $temporaryPath -Force -ErrorAction SilentlyContinue
    }
}

function Save-ReconciliationAttemptFailure {
    param(
        [Parameter(Mandatory = $true)][object]$Batch,
        [Parameter(Mandatory = $true)][int]$Attempt,
        [Parameter(Mandatory = $true)][string]$ErrorMessage,
        [Parameter(Mandatory = $true)][string]$ResponsePath
    )

    $attemptDirectory = Join-Path $Batch.Directory ('attempts/attempt-{0:D3}' -f $Attempt)
    $null = New-Item -ItemType Directory -Path $attemptDirectory -Force
    if (Test-Path -LiteralPath $ResponsePath -PathType Leaf) {
        [IO.File]::WriteAllBytes((Join-Path $attemptDirectory 'assessment-reconciliation-draft.json'), [IO.File]::ReadAllBytes($ResponsePath))
    }
    $failure = [ordered]@{
        schemaVersion = 1
        kind = 'hosted-assessment-reconciliation-attempt-failure'
        batchNumber = [int]$Batch.Number
        sourceDefinitionId = [string]$Batch.SourceDefinitionId
        attempt = $Attempt
        failedAt = ConvertTo-UtcTimestamp -Value ([DateTime]::UtcNow)
        validationError = $ErrorMessage
    }
    [IO.File]::WriteAllText((Join-Path $attemptDirectory 'failure.json'), (($failure | ConvertTo-Json) + "`n"), [Text.UTF8Encoding]::new($false))
}

function New-ReconciliationBatchBaselines {
    param(
        [Parameter(Mandatory = $true)][object]$Baseline,
        [Parameter(Mandatory = $true)][string]$Directory
    )

    $batches = [Collections.Generic.List[object]]::new()
    foreach ($sourceDefinition in @($Baseline.runConfiguration.sourceDefinitions)) {
        $sourceDefinitionId = [string]$sourceDefinition.sourceDefinitionId
        $batchSize = [int]$sourceDefinition.assessmentBatchSize
        if ($batchSize -lt 1) {
            throw "Assessment reconciliation source stream $sourceDefinitionId has an invalid assessmentBatchSize"
        }
        $sourceEntries = @($Baseline.entries | Where-Object {
            [string]$_.sourceRef.sourceDefinitionId -ceq $sourceDefinitionId -and @($_.assessments).Count -gt 0
        })
        for ($start = 0; $start -lt $sourceEntries.Count; $start += $batchSize) {
            $entryCount = [Math]::Min($batchSize, $sourceEntries.Count - $start)
            $batchEntries = @($sourceEntries[$start..($start + $entryCount - 1)])
            $batchBaseline = ($Baseline | ConvertTo-Json -Depth 100 -Compress) | ConvertFrom-Json -DateKind String
            $batchBaseline.entries = $batchEntries
            $batchNumber = $batches.Count + 1
            $batchDirectory = Join-Path $Directory ('batch-{0:D3}' -f $batchNumber)
            $null = New-Item -ItemType Directory -Path $batchDirectory -Force
            $batchBaselinePath = Join-Path $batchDirectory 'source-assessment-baseline.json'
            [IO.File]::WriteAllText($batchBaselinePath, (($batchBaseline | ConvertTo-Json -Depth 100) + "`n"), [Text.UTF8Encoding]::new($false))
            $batches.Add([pscustomobject]@{
                Number = $batchNumber
                SourceDefinitionId = $sourceDefinitionId
                BatchSize = $batchSize
                EntryCount = $entryCount
                AssessmentCount = @($batchEntries.assessments).Count
                Directory = $batchDirectory
                BaselinePath = $batchBaselinePath
            })
        }
    }
    if ($batches.Count -eq 0) {
        throw 'Assessment reconciliation requires at least one assessment'
    }
    return $batches.ToArray()
}

$resolvedRepositoryRoot = [IO.Path]::GetFullPath($RepositoryRoot).TrimEnd([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar)
$resolvedOutputPath = [IO.Path]::GetFullPath($OutputPath)
$repositoryPrefix = $resolvedRepositoryRoot + [IO.Path]::DirectorySeparatorChar
if ($resolvedOutputPath.StartsWith($repositoryPrefix, [StringComparison]::OrdinalIgnoreCase)) {
    throw 'Hosted rule change recommendation output must be outside the repository root'
}
$resolvedCacheDirectory = [IO.Path]::GetFullPath($CacheDirectory)
if ($resolvedCacheDirectory.StartsWith($repositoryPrefix, [StringComparison]::OrdinalIgnoreCase)) {
    throw 'CacheDirectory must be outside the repository root'
}
$resolvedResumeRunDirectory = if ([string]::IsNullOrWhiteSpace($ResumeRunDirectory)) { $null } else { [IO.Path]::GetFullPath($ResumeRunDirectory) }
if ($null -ne $resolvedResumeRunDirectory) {
    if ($resolvedResumeRunDirectory.StartsWith($repositoryPrefix, [StringComparison]::OrdinalIgnoreCase)) {
        throw 'ResumeRunDirectory must be outside the repository root'
    }
    if (-not (Test-Path -LiteralPath $resolvedResumeRunDirectory -PathType Container)) {
        throw "ResumeRunDirectory was not found: $resolvedResumeRunDirectory"
    }
}

$resolvedBaselinePath = [IO.Path]::GetFullPath($AssessmentBaselinePath)
$resolvedCatalogPath = [IO.Path]::GetFullPath($HostedCatalogPath)
$resolvedContractPath = [IO.Path]::GetFullPath($ReconciliationContractPath)
$resolvedBuilderPath = [IO.Path]::GetFullPath($BuilderPath)
$canonicalBuilderPath = [IO.Path]::GetFullPath((Join-Path $resolvedRepositoryRoot 'hosted_copilot/tools/internal/reconciliation/New-WorkbenchDisplay.ps1'))
if ($resolvedBuilderPath -cne $canonicalBuilderPath) {
    throw 'BuilderPath must identify the canonical contract-owned recommendation builder'
}
foreach ($requiredPath in @($resolvedBaselinePath, $resolvedCatalogPath, $resolvedContractPath, $resolvedBuilderPath)) {
    if (-not (Test-Path -LiteralPath $requiredPath -PathType Leaf)) {
        throw "Required assessment reconciliation input was not found: $requiredPath"
    }
}

$runDirectory = Join-Path ([IO.Path]::GetTempPath()) ('hosted-assessment-reconciliation/' + [guid]::NewGuid().ToString('N'))
$runRepositoryRoot = Join-Path $runDirectory 'repository'
$null = New-Item -ItemType Directory -Path $runRepositoryRoot -Force
$contractSnapshot = Get-FileSnapshot -Path $resolvedContractPath
$contract = $contractSnapshot.Content | ConvertFrom-Json
foreach ($relativePath in @($contract.behaviorFiles)) {
    $sourcePath = [IO.Path]::GetFullPath((Join-Path $resolvedRepositoryRoot ([string]$relativePath)))
    $destinationPath = [IO.Path]::GetFullPath((Join-Path $runRepositoryRoot ([string]$relativePath)))
    $null = Copy-InputSnapshot -SourcePath $sourcePath -DestinationPath $destinationPath
}
$snapshotContractPath = Join-Path $runRepositoryRoot 'hosted_copilot/copilot-rule-catalog/assessment-reconciliation/assessment-reconciliation-v4.json'
$snapshotContractDirectory = Split-Path -Parent $snapshotContractPath
if (-not (Test-Path -LiteralPath $snapshotContractDirectory -PathType Container)) {
    $null = New-Item -ItemType Directory -Path $snapshotContractDirectory -Force
}
[IO.File]::WriteAllBytes($snapshotContractPath, $contractSnapshot.Bytes)
$snapshotBaselinePath = Join-Path $runDirectory 'source-assessment-baseline.json'
$baselineSnapshot = Copy-InputSnapshot -SourcePath $resolvedBaselinePath -DestinationPath $snapshotBaselinePath
$snapshotCatalogPath = Join-Path $runRepositoryRoot 'hosted_copilot/copilot-rule-catalog/instruction-catalog.json'
$catalogSnapshot = Copy-InputSnapshot -SourcePath $resolvedCatalogPath -DestinationPath $snapshotCatalogPath
$snapshotInventoryPaths = [Collections.Generic.List[string]]::new()
foreach ($inventoryPath in $InventoryPaths) {
    $resolvedInventoryPath = [IO.Path]::GetFullPath($inventoryPath)
    $inventory = Get-Content -LiteralPath $resolvedInventoryPath -Raw | ConvertFrom-Json -DateKind String
    $snapshotInventoryPath = Join-Path $runDirectory "inventories/$([string]$inventory.sourceDefinitionId).json"
    $null = Copy-InputSnapshot -SourcePath $resolvedInventoryPath -DestinationPath $snapshotInventoryPath
    $snapshotInventoryPaths.Add($snapshotInventoryPath)
}
$snapshotGuidanceCapacityPath = Join-Path $runDirectory 'guidance-capacity.json'
$null = Copy-InputSnapshot -SourcePath ([IO.Path]::GetFullPath($GuidanceCapacityPath)) -DestinationPath $snapshotGuidanceCapacityPath

$baselineSchemaPath = Join-Path $runRepositoryRoot 'hosted_copilot/copilot-rule-catalog/rule-assessments/source-assessment-baseline-v4.schema.json'
$catalogSchemaPath = Join-Path $runRepositoryRoot 'hosted_copilot/copilot-rule-catalog/instruction-catalog.schema.json'
$contractSchemaPath = Join-Path $runRepositoryRoot 'hosted_copilot/copilot-rule-catalog/assessment-reconciliation/assessment-reconciliation-contract.schema.json'
$draftSchemaPath = Join-Path $runRepositoryRoot 'hosted_copilot/copilot-rule-catalog/assessment-reconciliation/assessment-reconciliation-draft.schema.json'
$promptPath = Join-Path $runRepositoryRoot 'hosted_copilot/tools/assessment-reconciliation-prompts/AssessmentReconciliation-v4.md'
if (-not ($baselineSnapshot.Content | Test-Json -SchemaFile $baselineSchemaPath -ErrorAction Stop)) {
    throw 'Source assessment baseline does not satisfy its schema'
}
if (-not ($catalogSnapshot.Content | Test-Json -SchemaFile $catalogSchemaPath -ErrorAction Stop)) {
    throw 'Hosted instruction catalog does not satisfy its schema'
}
if (-not ($contractSnapshot.Content | Test-Json -SchemaFile $contractSchemaPath -ErrorAction Stop)) {
    throw 'Assessment reconciliation contract does not satisfy its schema'
}
$baseline = $baselineSnapshot.Content | ConvertFrom-Json
if ([string]$baseline.hostedCatalogSha256 -cne $catalogSnapshot.Sha256) {
    throw 'Source assessment baseline does not bind the supplied Hosted instruction catalog'
}
$definitionSetPath = Join-Path $runRepositoryRoot 'hosted_copilot/copilot-rule-catalog/source-definitions/source-definition-set.json'
$definitionSetSchemaPath = Join-Path $runRepositoryRoot 'hosted_copilot/copilot-rule-catalog/source-definitions/source-definition-set.schema.json'
$definitionSetJson = Get-Content -LiteralPath $definitionSetPath -Raw
if (-not ($definitionSetJson | Test-Json -SchemaFile $definitionSetSchemaPath -ErrorAction Stop)) {
    throw 'Source definition set does not satisfy its schema'
}
$definitionSet = $definitionSetJson | ConvertFrom-Json
[string[]]$expectedSourceIds = @($definitionSet.sourceDefinitionIds)
[string[]]$baselineSourceIds = @($baseline.inventoryHashes.PSObject.Properties.Name)
[Array]::Sort($baselineSourceIds, [StringComparer]::Ordinal)
if (@(Compare-Object $expectedSourceIds $baselineSourceIds -SyncWindow 0).Count -ne 0) {
    throw "Assessment reconciliation requires exactly the approved source lanes: $($expectedSourceIds -join ', ')"
}

$resolvedEvaluatorScriptPath = $null
$evaluatorIdentity = $EvaluatorCommand
if (-not [string]::IsNullOrWhiteSpace($EvaluatorScriptPath)) {
    $evaluatorSnapshot = Get-FileSnapshot -Path ([IO.Path]::GetFullPath($EvaluatorScriptPath))
    $resolvedEvaluatorScriptPath = Join-Path $runDirectory 'evaluator.ps1'
    [IO.File]::WriteAllBytes($resolvedEvaluatorScriptPath, $evaluatorSnapshot.Bytes)
    $evaluatorIdentity = 'script:' + $evaluatorSnapshot.Sha256
}
$reconciliationRunConfiguration = [ordered]@{
    schemaVersion = 1
    kind = 'hosted-assessment-reconciliation-run'
    evaluator = $evaluatorIdentity
    model = $Model
    reasoningEffort = $ReasoningEffort
}
[IO.File]::WriteAllText((Join-Path $runDirectory 'reconciliation-run.json'), (($reconciliationRunConfiguration | ConvertTo-Json) + "`n"), [Text.UTF8Encoding]::new($false))

$snapshotBuilderPath = Join-Path $runRepositoryRoot 'hosted_copilot/tools/internal/reconciliation/New-WorkbenchDisplay.ps1'
$responsePath = Join-Path $runDirectory 'assessment-reconciliation-draft.json'
$batchRoot = Join-Path $runDirectory 'batches'
$reconciliationBatches = @(New-ReconciliationBatchBaselines -Baseline $baseline -Directory $batchRoot)
$mergedRecommendations = [Collections.Generic.List[object]]::new()
$mergedCoverage = [Collections.Generic.List[object]]::new()
$succeeded = $false
try {
    foreach ($batch in $reconciliationBatches) {
        $batchCatalogPath = Join-Path $batch.Directory 'instruction-catalog.json'
        $batchContractPath = Join-Path $batch.Directory 'assessment-reconciliation-v4.json'
        $batchSchemaPath = Join-Path $batch.Directory 'assessment-reconciliation-draft.schema.json'
        $batchPromptPath = Join-Path $batch.Directory 'AssessmentReconciliation-v4.md'
        [IO.File]::WriteAllBytes($batchCatalogPath, [IO.File]::ReadAllBytes($snapshotCatalogPath))
        [IO.File]::WriteAllBytes($batchContractPath, [IO.File]::ReadAllBytes($snapshotContractPath))
        [IO.File]::WriteAllBytes($batchSchemaPath, [IO.File]::ReadAllBytes($draftSchemaPath))
        [IO.File]::WriteAllBytes($batchPromptPath, [IO.File]::ReadAllBytes($promptPath))
        $batch | Add-Member -NotePropertyName PayloadSizeBytes -NotePropertyValue ([long]((Get-Item -LiteralPath $batch.BaselinePath).Length + (Get-Item -LiteralPath $batchCatalogPath).Length + (Get-Item -LiteralPath $batchContractPath).Length + (Get-Item -LiteralPath $batchSchemaPath).Length + (Get-Item -LiteralPath $batchPromptPath).Length)) -Force
    }

    $batchByNumber = @{}
    foreach ($batch in $reconciliationBatches) {
        $batchByNumber[[int]$batch.Number] = $batch
    }
    $validatedDrafts = @{}
    $batchErrors = @{}
    $cachedBatchCount = 0
    $reusedBatchCount = 0
    $cacheMetadataByBatch = @{}
    foreach ($batch in $reconciliationBatches) {
        $cacheIdentity = [ordered]@{
            schemaVersion = 1
            sourceDefinitionId = [string]$batch.SourceDefinitionId
            baselineIdentitySha256 = Get-Sha256 -Content (Get-ReconciliationBaselineIdentityJson -Path $batch.BaselinePath)
            hostedCatalogSha256 = Get-Sha256 -Path $snapshotCatalogPath
            reconciliationContractSha256 = Get-Sha256 -Path $snapshotContractPath
            draftSchemaSha256 = Get-Sha256 -Path $draftSchemaPath
            promptSha256 = Get-Sha256 -Path $promptPath
            evaluator = $evaluatorIdentity
            model = $Model
            reasoningEffort = $ReasoningEffort
        }
        $cacheKey = Get-Sha256 -Content ($cacheIdentity | ConvertTo-Json -Compress)
        $cachePath = Join-Path $resolvedCacheDirectory "$cacheKey.json"
        $cacheMetadataByBatch[[int]$batch.Number] = [pscustomobject]@{ Identity = $cacheIdentity; Key = $cacheKey; Path = $cachePath }
        if (-not (Test-Path -LiteralPath $cachePath -PathType Leaf)) {
            continue
        }

        $batchResponsePath = Join-Path $batch.Directory 'assessment-reconciliation-draft.json'
        $batchDisplayPath = Join-Path $batch.Directory 'workbench-display.json'
        try {
            $cacheEntry = Get-Content -LiteralPath $cachePath -Raw | ConvertFrom-Json -DateKind String
            $actualProperties = @($cacheEntry.PSObject.Properties.Name | Sort-Object)
            if (Compare-Object -ReferenceObject @('cacheKey', 'draft', 'identity', 'kind', 'schemaVersion') -DifferenceObject $actualProperties) {
                throw 'cached reconciliation entry has an unexpected property set'
            }
            if ([int]$cacheEntry.schemaVersion -ne 1 -or [string]$cacheEntry.kind -cne 'hosted-assessment-reconciliation-batch-cache' -or [string]$cacheEntry.cacheKey -cne $cacheKey -or
                ($cacheEntry.identity | ConvertTo-Json -Compress) -cne ($cacheIdentity | ConvertTo-Json -Compress)) {
                throw 'cached reconciliation identity does not match'
            }
            [IO.File]::WriteAllText($batchResponsePath, (($cacheEntry.draft | ConvertTo-Json -Depth 100) + "`n"), [Text.UTF8Encoding]::new($false))
            if (-not ((Get-Content -LiteralPath $batchResponsePath -Raw) | Test-Json -SchemaFile $draftSchemaPath -ErrorAction Stop)) {
                throw 'cached reconciliation draft does not satisfy its schema'
            }
            $batchBuilderParameters = @{
                RepositoryRoot = $runRepositoryRoot
                AssessmentBaselinePath = $batch.BaselinePath
                InventoryPaths = $snapshotInventoryPaths.ToArray()
                ReconciliationDraftPath = $batchResponsePath
                GuidanceCapacityPath = $snapshotGuidanceCapacityPath
                OutputPath = $batchDisplayPath
                HostedCatalogPath = $snapshotCatalogPath
                ReconciliationContractPath = $snapshotContractPath
                GeneratedAt = $GeneratedAt
                OutputFormat = 'Json'
            }
            $null = @(& $snapshotBuilderPath @batchBuilderParameters 2>&1)
            $validatedDrafts[[int]$batch.Number] = Get-Content -LiteralPath $batchResponsePath -Raw | ConvertFrom-Json -DateKind String
            $cachedBatchCount++
            $reusedBatchCount++
        }
        catch {
            Remove-Item -LiteralPath $cachePath, $batchResponsePath, $batchDisplayPath -Force -ErrorAction SilentlyContinue
            if (-not $Quiet) {
                Write-Host (Format-ValidationStatusLine -Status 'skipped' -Name ("assessment-reconciliation {0}/{1}" -f $batch.Number, $reconciliationBatches.Count) -Detail ("{0} cache rejected" -f $batch.SourceDefinitionId) -NameWidth 42)
                foreach ($diagnosticLine in @(Format-IndentedDiagnostic -Message ([string]$_.Exception.Message))) {
                    Write-Host $diagnosticLine
                }
            }
        }
    }
    if ($null -ne $resolvedResumeRunDirectory) {
        $recoveryRunDirectory = $resolvedResumeRunDirectory
        $retainedConfigurationPath = Join-Path $recoveryRunDirectory 'reconciliation-run.json'
        $retainedBaselinePath = Join-Path $recoveryRunDirectory 'source-assessment-baseline.json'
        $resumeConfigurationValid = if (Test-Path -LiteralPath $retainedConfigurationPath -PathType Leaf) {
            $retainedConfiguration = Get-Content -LiteralPath $retainedConfigurationPath -Raw | ConvertFrom-Json
            ($retainedConfiguration | ConvertTo-Json -Compress) -ceq ($reconciliationRunConfiguration | ConvertTo-Json -Compress)
        }
        elseif (Test-Path -LiteralPath $retainedBaselinePath -PathType Leaf) {
            $retainedBaseline = Get-Content -LiteralPath $retainedBaselinePath -Raw | ConvertFrom-Json
            [string]$retainedBaseline.runConfiguration.evaluator -ceq $evaluatorIdentity -and
                [string]$retainedBaseline.runConfiguration.model -ceq $Model -and
                [string]$retainedBaseline.runConfiguration.reasoningEffort -ceq $ReasoningEffort
        }
        else {
            $false
        }
        if (-not $resumeConfigurationValid) {
            throw 'Reconciliation recovery directory is incompatible with the current run. Rerun without -ReconciliationResumeDirectory to use validated cache entries.'
        }

        foreach ($batch in $reconciliationBatches) {
            if ($validatedDrafts.ContainsKey([int]$batch.Number)) {
                continue
            }
            $retainedBatchDirectory = Join-Path $recoveryRunDirectory ('batches/batch-{0:D3}' -f $batch.Number)
            $retainedBaselinePath = Join-Path $retainedBatchDirectory 'source-assessment-baseline.json'
            $retainedResponsePath = Join-Path $retainedBatchDirectory 'assessment-reconciliation-draft.json'
            $retainedStaticPairs = @(
                @((Join-Path $batch.Directory 'instruction-catalog.json'), (Join-Path $retainedBatchDirectory 'instruction-catalog.json')),
                @((Join-Path $batch.Directory 'assessment-reconciliation-v4.json'), (Join-Path $retainedBatchDirectory 'assessment-reconciliation-v4.json')),
                @((Join-Path $batch.Directory 'assessment-reconciliation-draft.schema.json'), (Join-Path $retainedBatchDirectory 'assessment-reconciliation-draft.schema.json')),
                @((Join-Path $batch.Directory 'AssessmentReconciliation-v4.md'), (Join-Path $retainedBatchDirectory 'AssessmentReconciliation-v4.md'))
            )
            if (-not (Test-Path -LiteralPath $retainedResponsePath -PathType Leaf) -or
                -not (Test-Path -LiteralPath $retainedBaselinePath -PathType Leaf) -or
                @($retainedStaticPairs | Where-Object { -not (Test-Path -LiteralPath $_[1] -PathType Leaf) -or (Get-FileHash -LiteralPath $_[0] -Algorithm SHA256).Hash -cne (Get-FileHash -LiteralPath $_[1] -Algorithm SHA256).Hash }).Count -gt 0 -or
                (Get-ReconciliationBaselineIdentityJson -Path $batch.BaselinePath) -cne (Get-ReconciliationBaselineIdentityJson -Path $retainedBaselinePath)) {
                continue
            }

            $batchResponsePath = Join-Path $batch.Directory 'assessment-reconciliation-draft.json'
            $batchDisplayPath = Join-Path $batch.Directory 'workbench-display.json'
            try {
                [IO.File]::WriteAllBytes($batchResponsePath, [IO.File]::ReadAllBytes($retainedResponsePath))
                $batchBuilderParameters = @{
                    RepositoryRoot = $runRepositoryRoot
                    AssessmentBaselinePath = $batch.BaselinePath
                    InventoryPaths = $snapshotInventoryPaths.ToArray()
                    ReconciliationDraftPath = $batchResponsePath
                    GuidanceCapacityPath = $snapshotGuidanceCapacityPath
                    OutputPath = $batchDisplayPath
                    HostedCatalogPath = $snapshotCatalogPath
                    ReconciliationContractPath = $snapshotContractPath
                    GeneratedAt = $GeneratedAt
                    OutputFormat = 'Json'
                }
                $null = @(& $snapshotBuilderPath @batchBuilderParameters 2>&1)
                $validatedDrafts[[int]$batch.Number] = Get-Content -LiteralPath $batchResponsePath -Raw | ConvertFrom-Json -DateKind String
                $cacheMetadata = $cacheMetadataByBatch[[int]$batch.Number]
                Write-JsonAtomically -Path $cacheMetadata.Path -Value ([ordered]@{
                    schemaVersion = 1
                    kind = 'hosted-assessment-reconciliation-batch-cache'
                    cacheKey = $cacheMetadata.Key
                    identity = $cacheMetadata.Identity
                    draft = $validatedDrafts[[int]$batch.Number]
                })
                $reusedBatchCount++
            }
            catch {
                Remove-Item -LiteralPath $batchResponsePath, $batchDisplayPath -Force -ErrorAction SilentlyContinue
                if (-not $Quiet) {
                    Write-Host (Format-ValidationStatusLine -Status 'skipped' -Name ("assessment-reconciliation {0}/{1}" -f $batch.Number, $reconciliationBatches.Count) -Detail ("{0} recovery rejected" -f $batch.SourceDefinitionId) -NameWidth 42)
                    foreach ($diagnosticLine in @(Format-IndentedDiagnostic -Message ([string]$_.Exception.Message))) {
                        Write-Host $diagnosticLine
                    }
                }
            }
        }
    }
    $pendingBatches = @($reconciliationBatches | Where-Object { -not $validatedDrafts.ContainsKey([int]$_.Number) })
    if (-not $Quiet) {
        [long]$pendingPayloadBytes = 0
        $pendingAssessmentCount = 0
        foreach ($pendingBatch in $pendingBatches) {
            $pendingPayloadBytes += [long]$pendingBatch.PayloadSizeBytes
            $pendingAssessmentCount += [int]$pendingBatch.AssessmentCount
        }
        $totalAssessmentCount = @($reconciliationBatches | Measure-Object -Property AssessmentCount -Sum)[0].Sum
        $initialEstimate = Get-EstimatedRemainingMilliseconds -CompletedPayloadBytes 0 -CompletedElapsedMilliseconds 0 -RemainingPayloadBytes $pendingPayloadBytes -MaxParallelBatches $MaxParallelBatches -BootstrapBytesPerSecondPerWorker $reconciliationBootstrapBytesPerSecondPerWorker
        Write-Host ''
        Write-Host ("  Assessments : {0} total | {1} pending" -f $totalAssessmentCount, $pendingAssessmentCount)
        Write-Host ("  Batches     : {0} total | {1} cached | {2} recovered | {3} pending" -f $reconciliationBatches.Count, $cachedBatchCount, ($reusedBatchCount - $cachedBatchCount), $pendingBatches.Count)
        Write-Host ("  Workers     : {0}" -f $MaxParallelBatches)
        Write-Host ("  Payload     : {0}" -f (Format-ByteSize -Bytes $pendingPayloadBytes))
        Write-Host ("  Estimated   : {0}" -f (Format-ElapsedDuration -Milliseconds $initialEstimate))
        Write-Host ''
    }
    $evaluatorCommandPath = $null
    if ($pendingBatches.Count -gt 0 -and $null -eq $resolvedEvaluatorScriptPath) {
        $command = Get-Command $EvaluatorCommand -ErrorAction SilentlyContinue
        if ($null -eq $command) {
            throw "Evaluator command was not found: $EvaluatorCommand"
        }
        $evaluatorCommandPath = $command.Source
    }
    for ($attempt = 1; $attempt -le ($MaxRetries + 1) -and $pendingBatches.Count -gt 0; $attempt++) {
        if ($attempt -gt 1 -and $RetryDelayMilliseconds -gt 0) {
            Start-Sleep -Milliseconds ([int][Math]::Min(60000, $RetryDelayMilliseconds * [Math]::Pow(2, $attempt - 2)))
        }
        $retryBatches = [Collections.Generic.List[object]]::new()
        $workerEvaluatorScriptPath = $resolvedEvaluatorScriptPath
        $workerEvaluatorCommandPath = $evaluatorCommandPath
        $workerModel = $Model
        $workerReasoningEffort = $ReasoningEffort
        $workerAttempt = $attempt
        $workerAttemptCount = $MaxRetries + 1
        if ($attempt -eq 1) {
            $completedBatchNumbers = [Collections.Generic.HashSet[int]]::new()
            [long]$completedPayloadBytes = 0
            [long]$completedElapsedMilliseconds = 0
        }
        $pendingBatches | ForEach-Object -Parallel {
            $batch = $_
            [pscustomobject]@{
                Kind = 'started'
                Number = [int]$batch.Number
                SourceDefinitionId = [string]$batch.SourceDefinitionId
                EntryCount = [int]$batch.EntryCount
                AssessmentCount = [int]$batch.AssessmentCount
                Attempt = $using:workerAttempt
                AttemptCount = $using:workerAttemptCount
            }
            $stopwatch = [Diagnostics.Stopwatch]::StartNew()
            $evaluatorOutput = @()
            $evaluatorExitCode = 0
            $failureKind = 'execution'
            try {
                $batchResponsePath = Join-Path $batch.Directory 'assessment-reconciliation-draft.json'
                if ($null -ne $using:workerEvaluatorScriptPath) {
                    $parameters = @{
                        BaselinePath = $batch.BaselinePath
                        CatalogPath = Join-Path $batch.Directory 'instruction-catalog.json'
                        ContractPath = Join-Path $batch.Directory 'assessment-reconciliation-v4.json'
                        SchemaPath = Join-Path $batch.Directory 'assessment-reconciliation-draft.schema.json'
                        PromptPath = Join-Path $batch.Directory 'AssessmentReconciliation-v4.md'
                        OutputPath = $batchResponsePath
                        Model = $using:workerModel
                        ReasoningEffort = $using:workerReasoningEffort
                    }
                    $evaluatorOutput = @(& pwsh -NoProfile -File $using:workerEvaluatorScriptPath @parameters 2>&1)
                    if ($LASTEXITCODE -ne 0) {
                        throw "Evaluator script failed: $(($evaluatorOutput | Out-String).Trim())"
                    }
                }
                else {
                    $attemptPrompt = 'Read source-assessment-baseline.json, instruction-catalog.json, assessment-reconciliation-v4.json, assessment-reconciliation-draft.schema.json, and AssessmentReconciliation-v4.md in the current directory. The baseline is one complete source-defined reconciliation batch. Cover every assessment in that batch exactly once and write only the requested JSON object in your final response.'
                    $evaluatorOutput = @(& $using:workerEvaluatorCommandPath -C $batch.Directory -p $attemptPrompt --no-color --stream off --no-custom-instructions --no-ask-user --disable-builtin-mcps --no-auto-update --disallow-temp-dir --model $using:workerModel --effort $using:workerReasoningEffort --available-tools=view --output-format json 2>&1)
                    $evaluatorExitCode = $LASTEXITCODE
                    if ($evaluatorExitCode -ne 0) {
                        $failureKind = 'copilot-exit'
                        throw "Copilot evaluator exited with code $evaluatorExitCode"
                    }
                }
                [pscustomobject]@{
                    Kind = 'completed'
                    Number = [int]$batch.Number
                    Succeeded = $true
                    ElapsedMilliseconds = [long]$stopwatch.ElapsedMilliseconds
                    ExitCode = 0
                    FailureKind = ''
                    Output = @($evaluatorOutput | ForEach-Object { [string]$_ })
                    Error = ''
                }
            }
            catch {
                [pscustomobject]@{
                    Kind = 'completed'
                    Number = [int]$batch.Number
                    Succeeded = $false
                    ElapsedMilliseconds = [long]$stopwatch.ElapsedMilliseconds
                    ExitCode = [int]$evaluatorExitCode
                    FailureKind = $failureKind
                    Output = @($evaluatorOutput | ForEach-Object { [string]$_ })
                    Error = [string]$_.Exception.Message
                }
            }
        } -ThrottleLimit $MaxParallelBatches | ForEach-Object {
            $workerResult = $_
            $batch = $batchByNumber[[int]$workerResult.Number]
            if ([string]$workerResult.Kind -ceq 'started') {
                if (-not $Quiet -and [int]$workerResult.Attempt -eq 1) {
                    Write-Host (Format-ValidationStatusLine -Status 'running' -Name ("assessment-reconciliation {0}/{1}" -f $workerResult.Number, $reconciliationBatches.Count) -Detail ("{0} ({1} assessments)" -f $workerResult.SourceDefinitionId, $workerResult.AssessmentCount) -NameWidth 42)
                }
                return
            }

            $batchResponsePath = Join-Path $batch.Directory 'assessment-reconciliation-draft.json'
            $batchDisplayPath = Join-Path $batch.Directory 'workbench-display.json'
            try {
                if (-not [bool]$workerResult.Succeeded) {
                    if ([string]$workerResult.FailureKind -ceq 'copilot-exit') {
                        throw (Get-EvaluatorFailureMessage -EvaluatorName 'Copilot evaluator' -ExitCode ([int]$workerResult.ExitCode) -Output @($workerResult.Output))
                    }
                    throw [string]$workerResult.Error
                }
                if ($null -eq $resolvedEvaluatorScriptPath) {
                    $assistantMessages = @($workerResult.Output | ForEach-Object {
                        $line = ([string]$_).Trim()
                        if (-not [string]::IsNullOrWhiteSpace($line)) {
                            try { $event = $line | ConvertFrom-Json } catch { throw "Copilot evaluator returned a non-JSONL event: $line" }
                            if ($event.type -eq 'assistant.message' -and -not [string]::IsNullOrWhiteSpace([string]$event.data.content)) { $event.data }
                        }
                    })
                    if ($assistantMessages.Count -eq 0) {
                        throw 'Copilot evaluator did not return an assistant message'
                    }
                    $assistantMessage = $assistantMessages[-1]
                    if ([string]$assistantMessage.model -cne $Model) {
                        throw "Copilot evaluator used model $($assistantMessage.model) instead of $Model"
                    }
                    [IO.File]::WriteAllText($batchResponsePath, (Get-EvaluatorJson -Content ([string]$assistantMessage.content)) + "`n", [Text.UTF8Encoding]::new($false))
                }
                $batchResponseJson = Get-Content -LiteralPath $batchResponsePath -Raw
                Test-EvaluatorDraftJson -Json $batchResponseJson -SchemaPath $draftSchemaPath -BatchNumber ([int]$batch.Number)
                $batchBuilderParameters = @{
                    RepositoryRoot = $runRepositoryRoot
                    AssessmentBaselinePath = $batch.BaselinePath
                    InventoryPaths = $snapshotInventoryPaths.ToArray()
                    ReconciliationDraftPath = $batchResponsePath
                    GuidanceCapacityPath = $snapshotGuidanceCapacityPath
                    OutputPath = $batchDisplayPath
                    HostedCatalogPath = $snapshotCatalogPath
                    ReconciliationContractPath = $snapshotContractPath
                    GeneratedAt = $GeneratedAt
                    OutputFormat = 'Json'
                }
                try {
                    $null = @(& $snapshotBuilderPath @batchBuilderParameters 2>&1)
                }
                catch {
                    throw "Batch reconciliation validation failed: $($_.Exception.Message)"
                }
                $validatedDrafts[[int]$batch.Number] = Get-Content -LiteralPath $batchResponsePath -Raw | ConvertFrom-Json -DateKind String
                $cacheMetadata = $cacheMetadataByBatch[[int]$batch.Number]
                Write-JsonAtomically -Path $cacheMetadata.Path -Value ([ordered]@{
                    schemaVersion = 1
                    kind = 'hosted-assessment-reconciliation-batch-cache'
                    cacheKey = $cacheMetadata.Key
                    identity = $cacheMetadata.Identity
                    draft = $validatedDrafts[[int]$batch.Number]
                })
                $batchErrors.Remove([int]$batch.Number)
                $null = $completedBatchNumbers.Add([int]$batch.Number)
                $completedPayloadBytes += [long]$batch.PayloadSizeBytes
                $completedElapsedMilliseconds += [long]$workerResult.ElapsedMilliseconds
                [long]$remainingPayloadBytes = 0
                foreach ($remainingBatch in @($reconciliationBatches | Where-Object { -not $validatedDrafts.ContainsKey([int]$_.Number) })) {
                    $remainingPayloadBytes += [long]$remainingBatch.PayloadSizeBytes
                }
                $estimatedRemainingMilliseconds = Get-EstimatedRemainingMilliseconds -CompletedPayloadBytes $completedPayloadBytes -CompletedElapsedMilliseconds $completedElapsedMilliseconds -RemainingPayloadBytes $remainingPayloadBytes -MaxParallelBatches $MaxParallelBatches -BootstrapBytesPerSecondPerWorker $reconciliationBootstrapBytesPerSecondPerWorker
                if (-not $Quiet) {
                    Write-Host (Format-ValidationStatusLine -Status 'passed' -Name ("assessment-reconciliation {0}/{1}" -f $batch.Number, $reconciliationBatches.Count) -Detail ("Total Elapsed {0} : [Batch: {1}] : [Remaining: {2}]" -f (Format-ElapsedDuration -Milliseconds ([long]$reconciliationStopwatch.ElapsedMilliseconds)), (Format-ElapsedDuration -Milliseconds ([long]$workerResult.ElapsedMilliseconds)), (Format-ElapsedDuration -Milliseconds $estimatedRemainingMilliseconds)) -NameWidth 42)
                }
            }
            catch {
                Save-ReconciliationAttemptFailure -Batch $batch -Attempt $attempt -ErrorMessage ([string]$_.Exception.Message) -ResponsePath $batchResponsePath
                Remove-Item -LiteralPath $batchResponsePath, $batchDisplayPath -Force -ErrorAction SilentlyContinue
                $batchErrors[[int]$batch.Number] = [string]$_.Exception.Message
                $retryBatches.Add($batch)
                if (-not $Quiet) {
                    foreach ($diagnosticLine in @(Format-IndentedDiagnostic -Label ("[ERROR] Batch {0}/{1}:" -f $batch.Number, $reconciliationBatches.Count) -Message ([string]$_.Exception.Message))) {
                        Write-Host $diagnosticLine
                    }
                    $completedPayloadBytes += [long]$batch.PayloadSizeBytes
                    $completedElapsedMilliseconds += [long]$workerResult.ElapsedMilliseconds
                    [long]$remainingPayloadBytes = 0
                    foreach ($remainingBatch in @($reconciliationBatches | Where-Object { -not $validatedDrafts.ContainsKey([int]$_.Number) })) {
                        $remainingPayloadBytes += [long]$remainingBatch.PayloadSizeBytes
                    }
                    $estimatedRemainingMilliseconds = Get-EstimatedRemainingMilliseconds -CompletedPayloadBytes $completedPayloadBytes -CompletedElapsedMilliseconds $completedElapsedMilliseconds -RemainingPayloadBytes $remainingPayloadBytes -MaxParallelBatches $MaxParallelBatches -BootstrapBytesPerSecondPerWorker $reconciliationBootstrapBytesPerSecondPerWorker
                    $failureStatus = if ($attempt -le $MaxRetries) { 'retrying' } else { 'failed' }
                    $failureDetail = if ($attempt -le $MaxRetries) {
                        "Total Elapsed {0} : [Batch: {1}] : [Remaining: {2}]" -f (Format-ElapsedDuration -Milliseconds ([long]$reconciliationStopwatch.ElapsedMilliseconds)), (Format-ElapsedDuration -Milliseconds ([long]$workerResult.ElapsedMilliseconds)), (Format-ElapsedDuration -Milliseconds $estimatedRemainingMilliseconds)
                    }
                    else {
                        "Total Elapsed {0} : [Batch: {1}]" -f (Format-ElapsedDuration -Milliseconds ([long]$reconciliationStopwatch.ElapsedMilliseconds)), (Format-ElapsedDuration -Milliseconds ([long]$workerResult.ElapsedMilliseconds))
                    }
                    Write-Host (Format-ValidationStatusLine -Status $failureStatus -Name ("assessment-reconciliation {0}/{1}" -f $batch.Number, $reconciliationBatches.Count) -Detail $failureDetail -NameWidth 42)
                }
            }
        }
        $pendingBatches = @($retryBatches.ToArray())
    }
    if ($pendingBatches.Count -gt 0) {
        $failureDetails = @($pendingBatches | Sort-Object Number | ForEach-Object { "batch $($_.Number) $($_.SourceDefinitionId): $($batchErrors[[int]$_.Number])" })
        throw "Assessment reconciliation failed after $($MaxRetries + 1) attempts: $($failureDetails -join '; ')"
    }

    foreach ($batch in @($reconciliationBatches | Sort-Object Number)) {
        $batchDraft = $validatedDrafts[[int]$batch.Number]
        $draftKeyMap = @{}
        foreach ($recommendation in @($batchDraft.recommendations)) {
            $sourceDraftKey = [string]$recommendation.draftKey
            $mergedDraftKey = 'recommendation-{0}' -f ($mergedRecommendations.Count + 1)
            $draftKeyMap[$sourceDraftKey] = $mergedDraftKey
            $recommendation.draftKey = $mergedDraftKey
            $mergedRecommendations.Add($recommendation)
        }
        foreach ($coverage in @($batchDraft.assessmentCoverage)) {
            $coverage.recommendationDraftKeys = @($coverage.recommendationDraftKeys | ForEach-Object {
                $sourceDraftKey = [string]$_
                if (-not $draftKeyMap.ContainsKey($sourceDraftKey)) {
                    throw "Assessment reconciliation batch references unknown draft key $sourceDraftKey"
                }
                $draftKeyMap[$sourceDraftKey]
            })
            $mergedCoverage.Add($coverage)
        }
    }

    $mergedDraft = [ordered]@{
        '$schema' = 'assessment-reconciliation-draft.schema.json'
        schemaVersion = 1
        recommendations = $mergedRecommendations.ToArray()
        assessmentCoverage = $mergedCoverage.ToArray()
    }
    [IO.File]::WriteAllText($responsePath, (($mergedDraft | ConvertTo-Json -Depth 100) + "`n"), [Text.UTF8Encoding]::new($false))
    if (-not ((Get-Content -LiteralPath $responsePath -Raw) | Test-Json -SchemaFile $draftSchemaPath -ErrorAction Stop)) {
        throw 'Merged assessment reconciliation draft does not satisfy its schema'
    }

    if (-not $Quiet) {
        Write-Host (Format-ValidationStatusLine -Status 'running' -Name 'assessment-reconciliation/display' -Detail 'building Workbench display' -NameWidth 42)
    }
    $builderParameters = @{
        RepositoryRoot = $runRepositoryRoot
        AssessmentBaselinePath = $snapshotBaselinePath
        InventoryPaths = $snapshotInventoryPaths.ToArray()
        ReconciliationDraftPath = $responsePath
        GuidanceCapacityPath = $snapshotGuidanceCapacityPath
        OutputPath = $resolvedOutputPath
        HostedCatalogPath = $snapshotCatalogPath
        ReconciliationContractPath = $snapshotContractPath
        GeneratedAt = $GeneratedAt
        OutputFormat = 'Json'
    }
    try {
        $builderOutput = @(& $snapshotBuilderPath @builderParameters 2>&1)
    }
    catch {
        throw "Workbench display builder failed: $($_.Exception.Message)"
    }
    $builderResult = ($builderOutput | Out-String) | ConvertFrom-Json
    if (-not $Quiet) {
        Write-Host (Format-ValidationStatusLine -Status 'passed' -Name 'assessment-reconciliation/display' -Detail 'Workbench display built' -NameWidth 42)
    }
    $succeeded = $true
}
catch {
    throw "$($_.Exception.Message) Assessment reconciliation run artifacts were retained at $runDirectory"
}
finally {
    if ($succeeded -and (Test-Path -LiteralPath $runDirectory -PathType Container)) {
        Remove-Item -LiteralPath $runDirectory -Recurse -Force
    }
}

$result = [ordered]@{
    status = [string]$builderResult.status
    outputPath = $resolvedOutputPath
    batchCount = $reconciliationBatches.Count
    cachedBatchCount = $cachedBatchCount
    reusedBatchCount = $reusedBatchCount
    evaluatedBatchCount = $reconciliationBatches.Count - $reusedBatchCount
    candidateCount = [int]$builderResult.candidateCount
    recommendationCount = [int]$builderResult.recommendationCount
    evaluator = $evaluatorIdentity
    cacheDirectory = $resolvedCacheDirectory
    displaySha256 = [string]$builderResult.displaySha256
}
if ($OutputFormat -eq 'Json') {
    $result | ConvertTo-Json -Depth 5
}
else {
    Write-Output "Assessment reconciliation completed with status $($result.status): $($result.candidateCount) candidates, $($result.recommendationCount) recommendations"
    Write-Output "Output: $($result.outputPath)"
    Write-Output "Display SHA-256: $($result.displaySha256)"
}
