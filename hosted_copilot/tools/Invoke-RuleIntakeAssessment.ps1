[CmdletBinding()]
param(
    [string]$RepositoryRoot = (Join-Path $PSScriptRoot '../..'),

    [string]$CollectorScriptPath = (Join-Path $PSScriptRoot 'New-RuleIntakeReview.ps1'),

    [string]$BundlePath,

    [string]$BaselinePath = (Join-Path $PSScriptRoot '../copilot-rule-catalog/rule-assessments/assessment-baseline.json'),

    [string]$OutputPath = (Join-Path ([IO.Path]::GetTempPath()) 'hosted-rule-workbench/assessed/rule-intake-review.json'),

    [string]$CachePath = (Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'terraform-azurerm-ai-assisted-development/hosted-rule-intake/assessment-cache.json'),

    [string]$Model = 'gpt-5.4',

    [ValidateSet('low', 'medium', 'high', 'xhigh')]
    [string]$ReasoningEffort = 'high',

    [ValidateRange(1, 50)]
    [int]$BatchSize = 20,

    [ValidateRange(1, 20)]
    [int]$UpstreamBatchSize = 5,

    [ValidateRange(0, 3)]
    [int]$MaxRetries = 1,

    [string]$EvaluatorCommand = 'copilot',

    [string]$EvaluatorScriptPath,

    [switch]$Force,

    [switch]$TrustEmbeddedAssessments,

    [ValidateSet('Text', 'Json')]
    [string]$OutputFormat = 'Text'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$validationOutputModulePath = Join-Path $PSScriptRoot '../../tools/ValidationOutput.psm1'
Import-Module -Name $validationOutputModulePath -Force

$resolvedRepositoryRoot = [IO.Path]::GetFullPath($RepositoryRoot)
$collectorPath = [IO.Path]::GetFullPath($CollectorScriptPath)
$catalogPath = Join-Path $PSScriptRoot '../copilot-rule-catalog/instruction-catalog.json'
$bundleSchemaPath = Join-Path $PSScriptRoot '../copilot-rule-catalog/rule-intake-review.schema.json'
$baselineSchemaPath = Join-Path $PSScriptRoot '../copilot-rule-catalog/rule-assessments/assessment-baseline.schema.json'
$resolvedBaselinePath = [IO.Path]::GetFullPath($BaselinePath)
$resolvedOutputPath = [IO.Path]::GetFullPath($OutputPath)
$resolvedCachePath = [IO.Path]::GetFullPath($CachePath)
$runDirectory = Join-Path ([IO.Path]::GetTempPath()) ("hosted-rule-assessment/{0}" -f [Guid]::NewGuid().ToString('N'))
$repositoryPrefix = $resolvedRepositoryRoot.TrimEnd([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar) + [IO.Path]::DirectorySeparatorChar

foreach ($generatedPath in @($resolvedOutputPath, $resolvedCachePath, $runDirectory)) {
    if ($generatedPath.StartsWith($repositoryPrefix, [StringComparison]::OrdinalIgnoreCase)) {
        throw "Generated assessment paths must be outside the source repository: $generatedPath"
    }
}

foreach ($requiredPath in @($collectorPath, $catalogPath, $bundleSchemaPath, $baselineSchemaPath)) {
    if (-not (Test-Path -LiteralPath $requiredPath -PathType Leaf)) {
        throw "Required assessment input was not found: $requiredPath"
    }
}

function Get-ContentSha256 {
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string]$Content
    )

    $bytes = [Text.Encoding]::UTF8.GetBytes($Content)
    return [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($bytes)).ToLowerInvariant()
}

function Get-CandidateSourceHash {
    param(
        [Parameter(Mandatory = $true)][string]$SourceType,
        [Parameter(Mandatory = $true)][object]$Candidate
    )

    if ($SourceType -eq 'upstream') {
        return [string]$Candidate.currentSha256
    }
    return [string]$Candidate.contentSha256
}

function Get-AssessmentIdentity {
    param(
        [Parameter(Mandatory = $true)][string]$SourceType,
        [Parameter(Mandatory = $true)][string]$Id
    )

    return "$SourceType`:$Id"
}

function Get-ContextKey {
    param(
        [Parameter(Mandatory = $true)][string]$SourceType,
        [Parameter(Mandatory = $true)][string]$Id,
        [Parameter(Mandatory = $true)][string]$SourceHash,
        [Parameter(Mandatory = $true)][string]$HostedCatalogHash,
        [Parameter(Mandatory = $true)][string]$ContractHash,
        [Parameter(Mandatory = $true)][string]$EvaluatorModel,
        [Parameter(Mandatory = $true)][string]$Effort
    )

    return Get-ContentSha256 -Content (@($SourceType, $Id, $SourceHash, $HostedCatalogHash, $ContractHash, $EvaluatorModel, $Effort) -join "`n")
}

function Write-JsonAtomically {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][object]$Value,
        [int]$Depth = 40
    )

    $directory = Split-Path -Parent $Path
    if (-not (Test-Path -LiteralPath $directory -PathType Container)) {
        New-Item -ItemType Directory -Path $directory -Force | Out-Null
    }
    $temporaryPath = "$Path.$PID.tmp"
    try {
        $json = $Value | ConvertTo-Json -Depth $Depth
        [IO.File]::WriteAllText($temporaryPath, $json + "`n", [Text.UTF8Encoding]::new($false))
        Move-Item -LiteralPath $temporaryPath -Destination $Path -Force
    }
    finally {
        if (Test-Path -LiteralPath $temporaryPath -PathType Leaf) {
            Remove-Item -LiteralPath $temporaryPath -Force
        }
    }
}

function Get-EvaluatorJson {
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string]$Content
    )

    $trimmed = $Content.Trim()
    if ($trimmed.StartsWith('```json', [StringComparison]::OrdinalIgnoreCase) -and $trimmed.EndsWith('```', [StringComparison]::Ordinal)) {
        $trimmed = $trimmed.Substring(7, $trimmed.Length - 10).Trim()
    }
    elseif ($trimmed.StartsWith('```', [StringComparison]::Ordinal) -and $trimmed.EndsWith('```', [StringComparison]::Ordinal)) {
        $trimmed = $trimmed.Substring(3, $trimmed.Length - 6).Trim()
    }
    $arrayStart = $trimmed.IndexOf('[')
    $arrayEnd = $trimmed.LastIndexOf(']')
    if ($arrayStart -lt 0 -or $arrayEnd -lt $arrayStart) {
        throw 'Evaluator response does not contain a JSON array'
    }
    return $trimmed.Substring($arrayStart, $arrayEnd - $arrayStart + 1)
}

function Assert-ExactProperties {
    param(
        [Parameter(Mandatory = $true)][object]$Value,
        [Parameter(Mandatory = $true)][string[]]$Expected,
        [Parameter(Mandatory = $true)][string]$Context
    )

    $actual = @($Value.PSObject.Properties.Name | Sort-Object)
    if (Compare-Object -ReferenceObject @($Expected | Sort-Object) -DifferenceObject $actual) {
        throw "$Context has an unexpected property set"
    }
}

$factorNames = @('severity', 'frequency', 'breadth', 'hostedDetectability', 'evidenceStrength', 'falsePositiveRisk', 'redundancy')
$semanticAssessmentProperties = @(
    'hostedApplicable',
    'applicabilityRationale',
    'hostedCategory',
    'recommendation',
    'summary',
    'impactDescription',
    'currentHostedCoverage',
    'affectedSurfaces',
    'guardedTokenDelta',
    'proposedText',
    'selectionFactors',
    'selectionRationale'
)
$fullAssessmentProperties = @('status', 'sourceContentSha256', 'assessedAt', 'evaluator') + $semanticAssessmentProperties
$allowedCategories = @('repository', 'review-classification-and-evidence', 'implementation', 'testing', 'documentation', 'not-applicable')
$allowedRecommendations = @('add', 'update', 'retire', 'no-change', 'exclude', 'defer')
$allowedSurfaces = @('repository', 'implementation', 'testing', 'documentation', 'review-skill')

function Assert-SemanticAssessment {
    param(
        [Parameter(Mandatory = $true)][object]$Assessment,
        [Parameter(Mandatory = $true)][string]$Context
    )

    Assert-ExactProperties -Value $Assessment -Expected $semanticAssessmentProperties -Context $Context
    foreach ($name in @('applicabilityRationale', 'summary', 'impactDescription', 'currentHostedCoverage', 'proposedText', 'selectionRationale')) {
        if ($Assessment.$name -isnot [string]) {
            throw "$Context property $name must be a string"
        }
    }
    foreach ($name in @('applicabilityRationale', 'summary', 'impactDescription', 'currentHostedCoverage', 'selectionRationale')) {
        if ([string]::IsNullOrWhiteSpace([string]$Assessment.$name)) {
            throw "$Context property $name must not be empty"
        }
    }
    if ($Assessment.hostedApplicable -isnot [bool]) {
        throw "$Context property hostedApplicable must be boolean"
    }
    if ([string]$Assessment.hostedCategory -notin $allowedCategories) {
        throw "$Context property hostedCategory is invalid"
    }
    if ([string]$Assessment.recommendation -notin $allowedRecommendations) {
        throw "$Context property recommendation is invalid"
    }
    if ($Assessment.guardedTokenDelta -isnot [long]) {
        throw "$Context property guardedTokenDelta must be an integer"
    }
    $surfaces = @($Assessment.affectedSurfaces)
    if (@($surfaces | Where-Object { $_ -notin $allowedSurfaces }).Count -gt 0 -or @($surfaces | Sort-Object -Unique).Count -ne $surfaces.Count) {
        throw "$Context property affectedSurfaces is invalid"
    }
    Assert-ExactProperties -Value $Assessment.selectionFactors -Expected $factorNames -Context "$Context selectionFactors"
    foreach ($factorName in $factorNames) {
        $factorValue = $Assessment.selectionFactors.$factorName
        if ($factorValue -isnot [long] -or $factorValue -lt 0 -or $factorValue -gt 5) {
            throw "$Context factor $factorName must be an integer from 0 through 5"
        }
    }
    if (-not $Assessment.hostedApplicable) {
        if ($Assessment.hostedCategory -ne 'not-applicable' -or $Assessment.recommendation -ne 'exclude' -or $surfaces.Count -ne 0 -or $Assessment.guardedTokenDelta -ne 0 -or $Assessment.proposedText -ne '') {
            throw "$Context does not satisfy the non-applicable assessment contract"
        }
    }
    elseif ($Assessment.hostedCategory -eq 'not-applicable' -or $surfaces.Count -eq 0) {
        throw "$Context does not satisfy the applicable assessment contract"
    }
}

function Assert-FullAssessment {
    param(
        [Parameter(Mandatory = $true)][object]$Assessment,
        [Parameter(Mandatory = $true)][string]$SourceHash,
        [Parameter(Mandatory = $true)][string]$Context
    )

    Assert-ExactProperties -Value $Assessment -Expected $fullAssessmentProperties -Context $Context
    if ($Assessment.status -ne 'evaluated' -or $Assessment.sourceContentSha256 -ne $SourceHash) {
        throw "$Context is not bound to the current candidate source"
    }
    if ([string]::IsNullOrWhiteSpace([string]$Assessment.evaluator) -or ([string]$Assessment.evaluator).ToLowerInvariant().Contains('fixture')) {
        throw "$Context evaluator is invalid"
    }
    $parsedTimestamp = [DateTimeOffset]::MinValue
    if (-not [DateTimeOffset]::TryParse([string]$Assessment.assessedAt, [ref]$parsedTimestamp)) {
        throw "$Context assessedAt is invalid"
    }
    $semantic = [ordered]@{}
    foreach ($propertyName in $semanticAssessmentProperties) {
        $semantic[$propertyName] = $Assessment.$propertyName
    }
    Assert-SemanticAssessment -Assessment ([pscustomobject]$semantic) -Context $Context
}

$promptContract = @'
Read the candidate batch, current Hosted instruction catalog, and assessment schema at the exact paths provided below. Assess every candidate in the batch against the current Hosted instruction catalog. This is a semantic maintenance review, not fixture generation.

Return only a raw JSON array with one object per candidate, in input order. Do not use Markdown fences or explanatory text. Each object must have exactly these properties:
- id
- assessment

The assessment object must have exactly these properties:
- hostedApplicable (boolean)
- applicabilityRationale (non-empty string)
- hostedCategory (repository, review-classification-and-evidence, implementation, testing, documentation, or not-applicable)
- recommendation (add, update, retire, no-change, exclude, or defer)
- summary (candidate-specific non-empty string)
- impactDescription (candidate-specific non-empty string)
- currentHostedCoverage (candidate-specific non-empty string)
- affectedSurfaces (unique values from repository, implementation, testing, documentation, review-skill)
- guardedTokenDelta (integer)
- proposedText (string)
- selectionFactors (severity, frequency, breadth, hostedDetectability, evidenceStrength, falsePositiveRisk, and redundancy; each an integer from 0 through 5)
- selectionRationale (non-empty string explaining why every factor value supports the recommendation)

Compare exact rule meaning, evidence, and failure condition against all current Hosted rules. Do not assign uniform or default factors. Do not invent evidence. A non-applicable candidate must use hostedCategory=not-applicable, recommendation=exclude, affectedSurfaces=[], guardedTokenDelta=0, and proposedText="". Use guardedTokenDelta=0 for no-change, exclude, and defer. Proposed add or update wording must be concise, enforceable Hosted review guidance. The candidate ID must exactly match the input.
'@
$schemaContent = Get-Content -LiteralPath $bundleSchemaPath -Raw
$evaluatorContractHash = Get-ContentSha256 -Content ($promptContract + "`n" + (Get-ContentSha256 -Content $schemaContent))
$evaluatorName = "github-copilot-cli/$Model"

if ([string]::IsNullOrWhiteSpace($BundlePath)) {
    $collectedBundlePath = Join-Path $runDirectory 'collected-rule-intake-review.json'
    $collectorOutput = @(& pwsh -NoProfile -File $collectorPath -RepositoryRoot $resolvedRepositoryRoot -OutputPath $collectedBundlePath -OutputFormat Text 2>&1)
    if ($LASTEXITCODE -ne 0) {
        throw "Rule intake collection failed: $(($collectorOutput | Out-String).Trim())"
    }
    if (-not (Test-Path -LiteralPath $collectedBundlePath -PathType Leaf)) {
        throw "Rule intake collection did not write its expected bundle: $collectedBundlePath"
    }
    $bundleContent = Get-Content -LiteralPath $collectedBundlePath -Raw
}
else {
    $resolvedBundlePath = [IO.Path]::GetFullPath($BundlePath)
    if (-not (Test-Path -LiteralPath $resolvedBundlePath -PathType Leaf)) {
        throw "BundlePath was not found: $resolvedBundlePath"
    }
    $bundleContent = Get-Content -LiteralPath $resolvedBundlePath -Raw
}

if (-not ($bundleContent | Test-Json -SchemaFile $bundleSchemaPath -ErrorAction Stop)) {
    throw 'Input bundle does not satisfy the rule intake review schema'
}
$bundle = $bundleContent | ConvertFrom-Json
$hostedCatalogHash = [string]$bundle.snapshots.hostedCatalogSha256

$baselineByIdentity = @{}
$baselineCatalogMatches = $false
if (Test-Path -LiteralPath $resolvedBaselinePath -PathType Leaf) {
    $baselineContent = Get-Content -LiteralPath $resolvedBaselinePath -Raw
    if (-not ($baselineContent | Test-Json -SchemaFile $baselineSchemaPath -ErrorAction Stop)) {
        throw "Assessment baseline does not satisfy its schema: $resolvedBaselinePath"
    }
    $baseline = $baselineContent | ConvertFrom-Json
    $baselineCatalogMatches = [string]$baseline.hostedCatalogSha256 -eq $hostedCatalogHash
    if ($baselineCatalogMatches) {
        foreach ($entry in @($baseline.entries)) {
            $identity = Get-AssessmentIdentity -SourceType ([string]$entry.sourceType) -Id ([string]$entry.id)
            if ($baselineByIdentity.ContainsKey($identity)) {
                throw "Assessment baseline contains duplicate candidate identity: $identity"
            }
            if ([string]$entry.assessment.sourceContentSha256 -ne [string]$entry.sourceContentSha256) {
                throw "Assessment baseline entry has a stale embedded assessment: $identity"
            }
            $baselineByIdentity[$identity] = $entry
        }
    }
}

$cacheEntries = New-Object 'System.Collections.Generic.List[object]'
if (Test-Path -LiteralPath $resolvedCachePath -PathType Leaf) {
    $cache = Get-Content -LiteralPath $resolvedCachePath -Raw | ConvertFrom-Json
    if ($cache.schemaVersion -ne 1 -or $null -eq $cache.entries) {
        throw "Assessment cache is invalid: $resolvedCachePath"
    }
    foreach ($entry in @($cache.entries)) {
        $cacheEntries.Add($entry)
    }
}

$cacheByContextKey = @{}
foreach ($entry in $cacheEntries.ToArray()) {
    if (-not [string]::IsNullOrWhiteSpace([string]$entry.contextKey)) {
        $cacheByContextKey[[string]$entry.contextKey] = $entry
    }
}

$candidateRecords = New-Object 'System.Collections.Generic.List[object]'
foreach ($source in @(
    [pscustomobject]@{ sourceType = 'interactive'; candidates = @($bundle.interactiveCandidates) },
    [pscustomobject]@{ sourceType = 'maintainer'; candidates = @($bundle.maintainerCandidates) },
    [pscustomobject]@{ sourceType = 'upstream'; candidates = @($bundle.upstreamCandidates) }
)) {
    foreach ($candidate in $source.candidates) {
        $sourceHash = Get-CandidateSourceHash -SourceType $source.sourceType -Candidate $candidate
        $contextKey = Get-ContextKey -SourceType $source.sourceType -Id ([string]$candidate.id) -SourceHash $sourceHash -HostedCatalogHash $hostedCatalogHash -ContractHash $evaluatorContractHash -EvaluatorModel $Model -Effort $ReasoningEffort
        $candidateRecords.Add([pscustomobject]@{
            sourceType = $source.sourceType
            candidate = $candidate
            sourceHash = $sourceHash
            contextKey = $contextKey
            identity = Get-AssessmentIdentity -SourceType $source.sourceType -Id ([string]$candidate.id)
        })
    }
}

$assessmentsByIdentity = @{}
$cacheHitCount = 0
$baselineHitCount = 0
$seededCount = 0
$pending = New-Object 'System.Collections.Generic.List[object]'
foreach ($record in $candidateRecords.ToArray()) {
    $assessment = $null
    if (-not $Force -and $cacheByContextKey.ContainsKey($record.contextKey)) {
        $assessment = $cacheByContextKey[$record.contextKey].assessment
        Assert-FullAssessment -Assessment $assessment -SourceHash $record.sourceHash -Context "Cached assessment $($record.identity)"
        $cacheHitCount++
    }
    elseif (-not $Force -and $baselineByIdentity.ContainsKey($record.identity)) {
        $baselineEntry = $baselineByIdentity[$record.identity]
        if ([string]$baselineEntry.sourceContentSha256 -eq $record.sourceHash) {
            $assessment = $baselineEntry.assessment
            Assert-FullAssessment -Assessment $assessment -SourceHash $record.sourceHash -Context "Baseline assessment $($record.identity)"
            $baselineHitCount++
        }
    }
    elseif (-not $Force -and $TrustEmbeddedAssessments -and $record.candidate.PSObject.Properties['assessment'] -and $null -ne $record.candidate.assessment) {
        $assessment = $record.candidate.assessment
        Assert-FullAssessment -Assessment $assessment -SourceHash $record.sourceHash -Context "Embedded assessment $($record.identity)"
        $cacheEntries.Add([pscustomobject]@{
            contextKey = $record.contextKey
            sourceType = $record.sourceType
            id = [string]$record.candidate.id
            sourceContentSha256 = $record.sourceHash
            hostedCatalogSha256 = $hostedCatalogHash
            evaluatorContractSha256 = $evaluatorContractHash
            model = $Model
            reasoningEffort = $ReasoningEffort
            assessment = $assessment
        })
        $seededCount++
    }

    if ($null -eq $assessment) {
        $pending.Add($record)
    }
    else {
        $assessmentsByIdentity[$record.identity] = $assessment
    }
}

if (-not (Test-Path -LiteralPath $runDirectory -PathType Container)) {
    New-Item -ItemType Directory -Path $runDirectory -Force | Out-Null
}

if ($seededCount -gt 0) {
    $activeContextKeys = @($candidateRecords.ToArray().contextKey)
    $compactedEntries = @($cacheEntries | Where-Object { $_.contextKey -in $activeContextKeys } | Group-Object contextKey | ForEach-Object { $_.Group[-1] })
    $cacheEntries = New-Object 'System.Collections.Generic.List[object]'
    foreach ($entry in $compactedEntries) {
        $cacheEntries.Add($entry)
    }
    Write-JsonAtomically -Path $resolvedCachePath -Value ([ordered]@{
        schemaVersion = 1
        updatedAt = [DateTimeOffset]::UtcNow.ToString('o')
        entries = $cacheEntries.ToArray()
    })
}

$assessmentBatches = New-Object 'System.Collections.Generic.List[object]'
foreach ($sourceType in @('interactive', 'maintainer', 'upstream')) {
    $sourcePending = @($pending.ToArray() | Where-Object sourceType -eq $sourceType)
    $sourceBatchSize = if ($sourceType -eq 'upstream') { $UpstreamBatchSize } else { $BatchSize }
    for ($sourceOffset = 0; $sourceOffset -lt $sourcePending.Count; $sourceOffset += $sourceBatchSize) {
        $sourceLastIndex = [Math]::Min($sourceOffset + $sourceBatchSize - 1, $sourcePending.Count - 1)
        $assessmentBatches.Add([pscustomobject]@{
            sourceType = $sourceType
            records = @($sourcePending[$sourceOffset..$sourceLastIndex])
        })
    }
}

[int]$batchCount = $assessmentBatches.Count
$evaluatedCount = 0
try {
    for ($batchIndex = 0; $batchIndex -lt $assessmentBatches.Count; $batchIndex++) {
        [int]$batchNumber = $batchIndex + 1
        $batch = $assessmentBatches[$batchIndex]
        $batchRecords = @($batch.records)
        $batchId = 'batch-{0:D3}' -f $batchNumber
        $batchDirectory = Join-Path $runDirectory $batchId
        New-Item -ItemType Directory -Path $batchDirectory -Force | Out-Null
        $batchPath = Join-Path $batchDirectory 'candidates.json'
        $responsePath = Join-Path $batchDirectory 'response.json'
        $batchCatalogPath = Join-Path $batchDirectory 'hosted-instruction-catalog.json'
        $batchSchemaPath = Join-Path $batchDirectory 'assessment-schema.json'
        Copy-Item -LiteralPath $catalogPath -Destination $batchCatalogPath -Force
        Copy-Item -LiteralPath $bundleSchemaPath -Destination $batchSchemaPath -Force
        $packetCandidates = @($batchRecords | ForEach-Object { $_.candidate | Select-Object * -ExcludeProperty assessment })
        Write-JsonAtomically -Path $batchPath -Value ([ordered]@{
            batchId = $batchId
            sourceType = $batch.sourceType
            candidateCount = $batchRecords.Count
            hostedCatalogSha256 = $hostedCatalogHash
            candidates = $packetCandidates
        })

        if ($OutputFormat -eq 'Text') {
            Write-Host ("[RUNNING]  assessment/{0,-19} : {1} candidates" -f $batchId, $batchRecords.Count)
        }

        $semanticRecords = $null
        $lastError = $null
        for ($attempt = 1; $attempt -le ($MaxRetries + 1); $attempt++) {
            try {
                if (-not [string]::IsNullOrWhiteSpace($EvaluatorScriptPath)) {
                    $resolvedEvaluatorScriptPath = [IO.Path]::GetFullPath($EvaluatorScriptPath)
                    $evaluatorOutput = @(& pwsh -NoProfile -File $resolvedEvaluatorScriptPath -BatchPath $batchPath -CatalogPath $batchCatalogPath -SchemaPath $batchSchemaPath -OutputPath $responsePath -Model $Model -ReasoningEffort $ReasoningEffort 2>&1)
                    if ($LASTEXITCODE -ne 0) {
                        throw "Evaluator script failed: $(($evaluatorOutput | Out-String).Trim())"
                    }
                }
                else {
                    $command = Get-Command $EvaluatorCommand -ErrorAction SilentlyContinue
                    if ($null -eq $command) {
                        throw "Evaluator command was not found: $EvaluatorCommand"
                    }
                    $attemptPrompt = @"
$promptContract

Candidate batch path: $batchPath
Hosted instruction catalog path: $batchCatalogPath
Assessment schema path: $batchSchemaPath

This batch contains exactly $($batchRecords.Count) candidates. Read all three files before assessing. This is attempt $attempt of $($MaxRetries + 1).
"@
                    $evaluatorOutput = @(& $command.Source -C $batchDirectory -p $attemptPrompt --no-color --stream off --no-custom-instructions --no-ask-user --disable-builtin-mcps --no-auto-update --disallow-temp-dir --model $Model --effort $ReasoningEffort --available-tools=view --output-format json 2>&1)
                    if ($LASTEXITCODE -ne 0) {
                        throw "Copilot evaluator failed: $(($evaluatorOutput | Out-String).Trim())"
                    }
                    $assistantMessages = New-Object 'System.Collections.Generic.List[object]'
                    foreach ($eventLine in $evaluatorOutput) {
                        $eventText = ([string]$eventLine).Trim()
                        if ([string]::IsNullOrWhiteSpace($eventText)) {
                            continue
                        }
                        try {
                            $event = $eventText | ConvertFrom-Json
                        }
                        catch {
                            throw "Copilot evaluator returned a non-JSONL event: $eventText"
                        }
                        if ($event.type -eq 'assistant.message' -and -not [string]::IsNullOrWhiteSpace([string]$event.data.content)) {
                            $assistantMessages.Add($event.data)
                        }
                    }
                    if ($assistantMessages.Count -eq 0) {
                        throw 'Copilot evaluator did not return an assistant message'
                    }
                    $assistantMessage = $assistantMessages[$assistantMessages.Count - 1]
                    if ([string]$assistantMessage.model -ne $Model) {
                        throw "Copilot evaluator used model $($assistantMessage.model) instead of $Model"
                    }
                    $evaluatorJson = Get-EvaluatorJson -Content ([string]$assistantMessage.content)
                    [IO.File]::WriteAllText($responsePath, $evaluatorJson + "`n", [Text.UTF8Encoding]::new($false))
                }

                $semanticRecords = @(Get-Content -LiteralPath $responsePath -Raw | ConvertFrom-Json)
                if ($semanticRecords.Count -ne $batchRecords.Count) {
                    throw "Evaluator returned $($semanticRecords.Count) records for $($batchRecords.Count) candidates"
                }
                $recordsById = @{}
                foreach ($semanticRecord in $semanticRecords) {
                    Assert-ExactProperties -Value $semanticRecord -Expected @('id', 'assessment') -Context "Evaluator record in $batchId"
                    $id = [string]$semanticRecord.id
                    if ($recordsById.ContainsKey($id)) {
                        throw "Evaluator returned duplicate candidate $id in $batchId"
                    }
                    Assert-SemanticAssessment -Assessment $semanticRecord.assessment -Context "Evaluator assessment $id"
                    $recordsById[$id] = $semanticRecord
                }
                foreach ($batchRecord in $batchRecords) {
                    if (-not $recordsById.ContainsKey([string]$batchRecord.candidate.id)) {
                        throw "Evaluator omitted candidate $($batchRecord.candidate.id) in $batchId"
                    }
                }
                break
            }
            catch {
                $lastError = $_
                $semanticRecords = $null
                if ($attempt -gt $MaxRetries) {
                    throw "Assessment $batchId failed after $attempt attempts: $($lastError.Exception.Message)"
                }
            }
        }

        $assessedAt = [DateTimeOffset]::UtcNow.ToString('o')
        $recordsById = @{}
        foreach ($semanticRecord in $semanticRecords) {
            $recordsById[[string]$semanticRecord.id] = $semanticRecord
        }
        foreach ($batchRecord in $batchRecords) {
            $semanticAssessment = $recordsById[[string]$batchRecord.candidate.id].assessment
            $assessment = [ordered]@{
                status = 'evaluated'
                sourceContentSha256 = $batchRecord.sourceHash
                assessedAt = $assessedAt
                evaluator = $evaluatorName
            }
            foreach ($propertyName in $semanticAssessmentProperties) {
                $assessment[$propertyName] = $semanticAssessment.$propertyName
            }
            $assessmentObject = [pscustomobject]$assessment
            Assert-FullAssessment -Assessment $assessmentObject -SourceHash $batchRecord.sourceHash -Context "Generated assessment $($batchRecord.identity)"
            $assessmentsByIdentity[$batchRecord.identity] = $assessmentObject
            $cacheEntries.Add([pscustomobject]@{
                contextKey = $batchRecord.contextKey
                sourceType = $batchRecord.sourceType
                id = [string]$batchRecord.candidate.id
                sourceContentSha256 = $batchRecord.sourceHash
                hostedCatalogSha256 = $hostedCatalogHash
                evaluatorContractSha256 = $evaluatorContractHash
                model = $Model
                reasoningEffort = $ReasoningEffort
                assessment = $assessmentObject
            })
            $evaluatedCount++
        }

        $activeContextKeys = @($candidateRecords.ToArray().contextKey)
        $compactedEntries = @($cacheEntries | Where-Object { $_.contextKey -in $activeContextKeys } | Group-Object contextKey | ForEach-Object { $_.Group[-1] })
        $cacheEntries = New-Object 'System.Collections.Generic.List[object]'
        foreach ($entry in $compactedEntries) {
            $cacheEntries.Add($entry)
        }
        Write-JsonAtomically -Path $resolvedCachePath -Value ([ordered]@{
            schemaVersion = 1
            updatedAt = [DateTimeOffset]::UtcNow.ToString('o')
            entries = $cacheEntries.ToArray()
        })
        if ($OutputFormat -eq 'Text') {
            Write-Host ("[PASSED]   assessment/{0,-19} : {1} candidates" -f $batchId, $batchRecords.Count)
        }
    }

    foreach ($record in $candidateRecords.ToArray()) {
        if (-not $assessmentsByIdentity.ContainsKey($record.identity)) {
            throw "Assessment is missing after evaluation: $($record.identity)"
        }
        $record.candidate | Add-Member -NotePropertyName assessment -NotePropertyValue $assessmentsByIdentity[$record.identity] -Force
    }

    $resultJson = $bundle | ConvertTo-Json -Depth 60
    if (-not ($resultJson | Test-Json -SchemaFile $bundleSchemaPath -ErrorAction Stop)) {
        throw 'Assessed rule intake bundle schema validation failed'
    }
    $outputDirectory = Split-Path -Parent $resolvedOutputPath
    if (-not (Test-Path -LiteralPath $outputDirectory -PathType Container)) {
        New-Item -ItemType Directory -Path $outputDirectory -Force | Out-Null
    }
    [IO.File]::WriteAllText($resolvedOutputPath, $resultJson + "`n", [Text.UTF8Encoding]::new($false))

    $allCandidates = @($bundle.interactiveCandidates) + @($bundle.maintainerCandidates) + @($bundle.upstreamCandidates)
    $summary = [ordered]@{
        status = 'passed'
        outputPath = $resolvedOutputPath
        cachePath = $resolvedCachePath
        candidateCount = $allCandidates.Count
        cacheHitCount = $cacheHitCount
        baselineHitCount = $baselineHitCount
        seededCount = $seededCount
        evaluatedCount = $evaluatedCount
        batchCount = $batchCount
        applicableCount = @($allCandidates | Where-Object { $_.assessment.hostedApplicable }).Count
        inapplicableCount = @($allCandidates | Where-Object { -not $_.assessment.hostedApplicable }).Count
        model = $Model
        reasoningEffort = $ReasoningEffort
        evaluatorContractSha256 = $evaluatorContractHash
        repositoryWrites = $false
    }

    if ($OutputFormat -eq 'Json') {
        $summary | ConvertTo-Json -Depth 5
    }
    else {
        Write-ValidationSectionHeader -Title 'Hosted rule intake assessment'
        Write-ValidationSummary -Fields ([ordered]@{
            Status = $summary.status.ToUpperInvariant()
            Candidates = $summary.candidateCount
            'Cache Hits' = $summary.cacheHitCount
            'Baseline Hits' = $summary.baselineHitCount
            Seeded = $summary.seededCount
            Evaluated = $summary.evaluatedCount
            Batches = $summary.batchCount
            Applicable = $summary.applicableCount
            Inapplicable = $summary.inapplicableCount
            Model = $summary.model
            'Reasoning Effort' = $summary.reasoningEffort
            'Output Path' = $summary.outputPath
            'Cache Path' = $summary.cachePath
            'Updates Repository' = $false
        })
        Complete-ValidationTextOutput
    }
}
catch {
    throw "$($_.Exception.Message) Assessment run artifacts were retained at $runDirectory`n$($_.ScriptStackTrace)"
}
finally {
    if ($? -and (Test-Path -LiteralPath $runDirectory -PathType Container)) {
        Remove-Item -LiteralPath $runDirectory -Recurse -Force
    }
}
