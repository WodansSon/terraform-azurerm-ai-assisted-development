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

    [string]$Model = 'gpt-5.4',

    [ValidateSet('low', 'medium', 'high', 'xhigh')]
    [string]$ReasoningEffort = 'high',

    [ValidateRange(0, 3)]
    [int]$MaxRetries = 1,

    [ValidateRange(0, 60000)]
    [int]$RetryDelayMilliseconds = 1000,

    [object]$GeneratedAt = [DateTime]::UtcNow,

    [ValidateSet('Text', 'Json')]
    [string]$OutputFormat = 'Text'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$helpersPath = Join-Path $PSScriptRoot '../../modules/shared/HostedToolkit.Helpers.psm1'
Import-Module -Name $helpersPath -Force

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

$resolvedRepositoryRoot = [IO.Path]::GetFullPath($RepositoryRoot).TrimEnd([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar)
$resolvedOutputPath = [IO.Path]::GetFullPath($OutputPath)
$repositoryPrefix = $resolvedRepositoryRoot + [IO.Path]::DirectorySeparatorChar
if ($resolvedOutputPath.StartsWith($repositoryPrefix, [StringComparison]::OrdinalIgnoreCase)) {
    throw 'Hosted rule change recommendation output must be outside the repository root'
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

$responsePath = Join-Path $runDirectory 'assessment-reconciliation-draft.json'
$succeeded = $false
try {
    $lastError = $null
    for ($attempt = 1; $attempt -le ($MaxRetries + 1); $attempt++) {
        try {
            if ($OutputFormat -eq 'Text') {
                Write-Host ("[RUNNING]  assessment-reconciliation : attempt {0}" -f $attempt)
            }
            if ($null -ne $resolvedEvaluatorScriptPath) {
                $parameters = @{
                    BaselinePath = $snapshotBaselinePath
                    CatalogPath = $snapshotCatalogPath
                    ContractPath = $snapshotContractPath
                    SchemaPath = $draftSchemaPath
                    PromptPath = $promptPath
                    OutputPath = $responsePath
                    Model = $Model
                    ReasoningEffort = $ReasoningEffort
                }
                $evaluatorOutput = @(& pwsh -NoProfile -File $resolvedEvaluatorScriptPath @parameters 2>&1)
                if ($LASTEXITCODE -ne 0) {
                    throw "Evaluator script failed: $(($evaluatorOutput | Out-String).Trim())"
                }
            }
            else {
                $command = Get-Command $EvaluatorCommand -ErrorAction SilentlyContinue
                if ($null -eq $command) {
                    throw "Evaluator command was not found: $EvaluatorCommand"
                }
                $attemptPrompt = 'Read the complete assessment baseline, Hosted catalog, reconciliation contract, output schema, and prompt in the current directory. Write only the requested JSON object in your final response.'
                $evaluatorOutput = @(& $command.Source -C $runDirectory -p $attemptPrompt --no-color --stream off --no-custom-instructions --no-ask-user --disable-builtin-mcps --no-auto-update --disallow-temp-dir --model $Model --effort $ReasoningEffort --available-tools=view --output-format json 2>&1)
                if ($LASTEXITCODE -ne 0) {
                    throw "Copilot evaluator failed: $(($evaluatorOutput | Out-String).Trim())"
                }
                $assistantMessages = @($evaluatorOutput | ForEach-Object {
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
                [IO.File]::WriteAllText($responsePath, (Get-EvaluatorJson -Content ([string]$assistantMessage.content)) + "`n", [Text.UTF8Encoding]::new($false))
            }
            $responseJson = Get-Content -LiteralPath $responsePath -Raw
            if (-not ($responseJson | Test-Json -SchemaFile $draftSchemaPath -ErrorAction Stop)) {
                throw 'Evaluator response does not satisfy the assessment reconciliation draft schema'
            }
            $lastError = $null
            break
        }
        catch {
            $lastError = $_
            Remove-Item -LiteralPath $responsePath -Force -ErrorAction SilentlyContinue
            if ($attempt -le $MaxRetries -and $RetryDelayMilliseconds -gt 0) {
                Start-Sleep -Milliseconds ([int][Math]::Min(60000, $RetryDelayMilliseconds * [Math]::Pow(2, $attempt - 1)))
            }
        }
    }
    if ($null -ne $lastError) {
        throw "Assessment reconciliation failed after $($MaxRetries + 1) attempts: $($lastError.Exception.Message)"
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
    $snapshotBuilderPath = Join-Path $runRepositoryRoot 'hosted_copilot/tools/internal/reconciliation/New-WorkbenchDisplay.ps1'
    $builderOutput = @(& pwsh -NoProfile -File $snapshotBuilderPath @builderParameters 2>&1)
    if ($LASTEXITCODE -ne 0) {
        throw "Workbench display builder failed: $(($builderOutput | Out-String).Trim())"
    }
    $builderResult = ($builderOutput | Out-String) | ConvertFrom-Json
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
    status = 'passed'
    outputPath = $resolvedOutputPath
    candidateCount = [int]$builderResult.candidateCount
    recommendationCount = [int]$builderResult.recommendationCount
    evaluator = $evaluatorIdentity
    displaySha256 = [string]$builderResult.displaySha256
}
if ($OutputFormat -eq 'Json') {
    $result | ConvertTo-Json -Depth 5
}
else {
    Write-Output "Assessment reconciliation completed: $($result.candidateCount) candidates, $($result.recommendationCount) recommendations"
    Write-Output "Output: $($result.outputPath)"
    Write-Output "Display SHA-256: $($result.displaySha256)"
}
