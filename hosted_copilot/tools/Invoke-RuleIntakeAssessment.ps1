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

    [switch]$RepairMissingFields,

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

$hostedCatalog = Get-Content -LiteralPath $catalogPath -Raw | ConvertFrom-Json
$activeHostedRuleIds = @($hostedCatalog.rules | Where-Object status -eq 'active' | ForEach-Object { [string]$_.id })
$knownHostedRuleIds = @($hostedCatalog.rules | ForEach-Object { [string]$_.id })
$hostedRulesById = @{}
foreach ($rule in @($hostedCatalog.rules)) {
    $hostedRulesById[[string]$rule.id] = $rule
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

function Get-ProposalOwnerKey {
    param(
        [Parameter(Mandatory = $true)][string]$SourceType,
        [Parameter(Mandatory = $true)][string]$CandidateId,
        [Parameter(Mandatory = $true)][string]$AssessmentId
    )

    return "$SourceType`:$CandidateId`:$AssessmentId"
}

function Add-AssessmentProposalReservations {
    param(
        [Parameter(Mandatory = $true)][hashtable]$Owners,
        [Parameter(Mandatory = $true)][string]$SourceType,
        [Parameter(Mandatory = $true)][string]$CandidateId,
        [Parameter(Mandatory = $true)][AllowNull()][AllowEmptyCollection()][object[]]$Assessments,
        [switch]$ValidateOnly
    )

    $pendingOwners = @{}
    foreach ($assessment in $Assessments) {
        $proposedHostedRuleId = [string]$assessment.proposedHostedRuleId
        $targetHostedRuleId = [string]$assessment.targetHostedRuleId
        if ([string]::IsNullOrWhiteSpace($proposedHostedRuleId) -or $proposedHostedRuleId -eq $targetHostedRuleId) {
            continue
        }
        $ownerKey = Get-ProposalOwnerKey -SourceType $SourceType -CandidateId $CandidateId -AssessmentId ([string]$assessment.assessmentId)
        if (($Owners.ContainsKey($proposedHostedRuleId) -and $Owners[$proposedHostedRuleId] -ne $ownerKey) -or ($pendingOwners.ContainsKey($proposedHostedRuleId) -and $pendingOwners[$proposedHostedRuleId] -ne $ownerKey)) {
            return $false
        }
        $pendingOwners[$proposedHostedRuleId] = $ownerKey
    }
    if (-not $ValidateOnly) {
        foreach ($entry in $pendingOwners.GetEnumerator()) {
            $Owners[$entry.Key] = $entry.Value
        }
    }
    return $true
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
    'assessmentId',
    'title',
    'candidateState',
    'targetHostedRuleId',
    'proposedHostedRuleId',
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
$repairAssessmentProperties = @('assessmentId', 'proposedHostedRuleId', 'proposedText', 'hostedCategory', 'affectedSurfaces')
$fullAssessmentProperties = @('status', 'sourceContentSha256', 'assessedAt', 'evaluator') + $semanticAssessmentProperties
$allowedCategories = @('repository', 'review-classification-and-evidence', 'implementation', 'testing', 'documentation')
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
    if ([string]::IsNullOrWhiteSpace([string]$Assessment.assessmentId) -or [string]$Assessment.assessmentId -notmatch '^[A-Za-z][A-Za-z0-9-]*$') {
        throw "$Context property assessmentId is invalid"
    }
    if ([string]::IsNullOrWhiteSpace([string]$Assessment.title)) {
        throw "$Context property title must not be empty"
    }
    if ([string]$Assessment.candidateState -notin @('new', 'changed', 'retired', 'deferred', 'current')) {
        throw "$Context property candidateState is invalid"
    }
    $targetHostedRuleId = [string]$Assessment.targetHostedRuleId
    if ($Assessment.recommendation -in @('update', 'retire')) {
        if ([string]::IsNullOrWhiteSpace($targetHostedRuleId) -or $targetHostedRuleId -notin $activeHostedRuleIds) {
            throw "$Context property targetHostedRuleId must identify one active Hosted rule for $($Assessment.recommendation)"
        }
    }
    elseif ($Assessment.recommendation -eq 'add' -and -not [string]::IsNullOrWhiteSpace($targetHostedRuleId)) {
        throw "$Context property targetHostedRuleId must be null for add"
    }
    elseif (-not [string]::IsNullOrWhiteSpace($targetHostedRuleId) -and $targetHostedRuleId -notin $knownHostedRuleIds) {
        throw "$Context property targetHostedRuleId does not identify a Hosted rule"
    }
    $proposedHostedRuleId = [string]$Assessment.proposedHostedRuleId
    if ([string]::IsNullOrWhiteSpace($proposedHostedRuleId) -or $proposedHostedRuleId.Length -gt 32 -or $proposedHostedRuleId -notmatch '^[A-Z]+(?:-[A-Z0-9]+)+-[0-9]{3}[A-Z]?$') {
        throw "$Context property proposedHostedRuleId must contain a valid Hosted rule ID"
    }
    if ($proposedHostedRuleId -in $knownHostedRuleIds -and $proposedHostedRuleId -ne $targetHostedRuleId) {
        throw "$Context property proposedHostedRuleId collides with an existing Hosted rule"
    }
    if (-not [string]::IsNullOrWhiteSpace($targetHostedRuleId) -and $proposedHostedRuleId -ne $targetHostedRuleId -and $Assessment.recommendation -notin @('update', 'retire')) {
        throw "$Context property proposedHostedRuleId can differ from targetHostedRuleId only for update or retire"
    }
    if ([string]::IsNullOrWhiteSpace([string]$Assessment.proposedText)) {
        throw "$Context property proposedText must contain the complete proposed Hosted rule"
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
    if ($surfaces.Count -eq 0) {
        throw "$Context must identify at least one affected surface for the proposed Hosted rule"
    }
    if (-not $Assessment.hostedApplicable) {
        if ($Assessment.recommendation -ne 'exclude' -or $Assessment.guardedTokenDelta -ne 0) {
            throw "$Context does not satisfy the non-applicable assessment contract"
        }
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

function Assert-SemanticAssessmentSet {
    param(
        [Parameter(Mandatory = $true)][AllowNull()][AllowEmptyCollection()][object[]]$Assessments,
        [Parameter(Mandatory = $true)][string]$SourceType,
        [Parameter(Mandatory = $true)][string]$Context,
        [switch]$Full,
        [string]$SourceHash
    )

    $assessmentCount = @($Assessments).Count
    if ($SourceType -ne 'upstream' -and $assessmentCount -ne 1) {
        throw "$Context must contain exactly one rule-level assessment for $SourceType input"
    }
    $assessmentIds = @{}
    $targetIds = @{}
    foreach ($assessment in $Assessments) {
        if ($Full) {
            Assert-FullAssessment -Assessment $assessment -SourceHash $SourceHash -Context "$Context assessment $($assessment.assessmentId)"
        }
        else {
            Assert-SemanticAssessment -Assessment $assessment -Context "$Context assessment $($assessment.assessmentId)"
        }
        $assessmentId = [string]$assessment.assessmentId
        if ($assessmentIds.ContainsKey($assessmentId)) {
            throw "$Context contains duplicate assessmentId $assessmentId"
        }
        $assessmentIds[$assessmentId] = $true
        $targetHostedRuleId = [string]$assessment.targetHostedRuleId
        if (-not [string]::IsNullOrWhiteSpace($targetHostedRuleId)) {
            if ($targetIds.ContainsKey($targetHostedRuleId)) {
                throw "$Context contains duplicate targetHostedRuleId $targetHostedRuleId"
            }
            $targetIds[$targetHostedRuleId] = $true
        }
    }
}

function Get-AssessmentRepairFields {
    param(
        [Parameter(Mandatory = $true)][object]$Assessment
    )

    $fields = New-Object 'System.Collections.Generic.List[string]'
    $targetHostedRuleId = [string]$Assessment.targetHostedRuleId
    $proposedHostedRuleId = [string]$Assessment.proposedHostedRuleId
    if ([string]::IsNullOrWhiteSpace($proposedHostedRuleId) -or $proposedHostedRuleId.Length -gt 32 -or $proposedHostedRuleId -notmatch '^[A-Z]+(?:-[A-Z0-9]+)+-[0-9]{3}[A-Z]?$' -or ($proposedHostedRuleId -in $knownHostedRuleIds -and $proposedHostedRuleId -ne $targetHostedRuleId)) {
        $fields.Add('proposedHostedRuleId')
    }
    if ([string]::IsNullOrWhiteSpace([string]$Assessment.proposedText)) {
        $fields.Add('proposedText')
    }
    if ([string]$Assessment.hostedCategory -notin $allowedCategories) {
        $fields.Add('hostedCategory')
    }
    $surfaces = @($Assessment.affectedSurfaces)
    if ($surfaces.Count -eq 0 -or @($surfaces | Where-Object { $_ -notin $allowedSurfaces }).Count -gt 0 -or @($surfaces | Sort-Object -Unique).Count -ne $surfaces.Count) {
        $fields.Add('affectedSurfaces')
    }
    return $fields.ToArray()
}

function Assert-RepairableAssessmentSet {
    param(
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][object[]]$Assessments,
        [Parameter(Mandatory = $true)][string]$SourceType,
        [Parameter(Mandatory = $true)][string]$SourceHash,
        [Parameter(Mandatory = $true)][string]$Context
    )

    $validationAssessments = @($Assessments | ForEach-Object {
        $assessment = $_ | ConvertTo-Json -Depth 20 | ConvertFrom-Json
        $repairFields = @(Get-AssessmentRepairFields -Assessment $assessment)
        if ('proposedHostedRuleId' -in $repairFields) {
            $replacementId = if (-not [string]::IsNullOrWhiteSpace([string]$assessment.targetHostedRuleId)) { [string]$assessment.targetHostedRuleId } else { 'REPAIR-TEMP-999' }
            $assessment | Add-Member -NotePropertyName proposedHostedRuleId -NotePropertyValue $replacementId -Force
        }
        if ('proposedText' -in $repairFields) {
            $assessment | Add-Member -NotePropertyName proposedText -NotePropertyValue 'Temporary complete Hosted rule used only for repair validation.' -Force
        }
        if ('hostedCategory' -in $repairFields) {
            $assessment | Add-Member -NotePropertyName hostedCategory -NotePropertyValue 'repository' -Force
        }
        if ('affectedSurfaces' -in $repairFields) {
            $assessment | Add-Member -NotePropertyName affectedSurfaces -NotePropertyValue @('repository') -Force
        }
        $assessment
    })
    Assert-SemanticAssessmentSet -Assessments $validationAssessments -SourceType $SourceType -SourceHash $SourceHash -Context $Context -Full
}

function Get-DeterministicallyRepairedAssessments {
    param(
        [Parameter(Mandatory = $true)][AllowNull()][AllowEmptyCollection()][object[]]$Assessments
    )

    return @($Assessments | ForEach-Object {
        $assessment = $_ | ConvertTo-Json -Depth 20 | ConvertFrom-Json
        $targetHostedRuleId = [string]$assessment.targetHostedRuleId
        if (-not [string]::IsNullOrWhiteSpace($targetHostedRuleId)) {
            if ([string]::IsNullOrWhiteSpace([string]$assessment.proposedHostedRuleId)) {
                $assessment | Add-Member -NotePropertyName proposedHostedRuleId -NotePropertyValue $targetHostedRuleId -Force
            }
            if ([string]::IsNullOrWhiteSpace([string]$assessment.proposedText) -and $hostedRulesById.ContainsKey($targetHostedRuleId)) {
                $assessment | Add-Member -NotePropertyName proposedText -NotePropertyValue ([string]$hostedRulesById[$targetHostedRuleId].text) -Force
            }
        }
        $assessment
    })
}

$promptContract = @'
Read the candidate batch, current Hosted instruction catalog, and assessment schema at the exact paths provided below. Assess every candidate in the batch against the current Hosted instruction catalog. This is a semantic maintenance review, not fixture generation.

Return only a raw JSON array with one object per candidate, in input order. Do not use Markdown fences or explanatory text. Each object must have exactly these properties:
- id
- assessments

The assessments array must contain one object for every independently enforceable rule represented by the source. For upstream contributor documents, decompose the complete current document into separate rule candidates, including every existing Hosted rule that cites the document and every uncovered requirement. If an upstream document contains no independently enforceable review rule, return an empty assessments array; do not fabricate an exclusion candidate merely to represent the source review. Interactive and maintainer inputs must return exactly one assessment. Each assessment object must have exactly these properties:
- assessmentId
- title
- candidateState
- targetHostedRuleId
- proposedHostedRuleId
- hostedApplicable (boolean)
- applicabilityRationale (non-empty string)
- hostedCategory (repository, review-classification-and-evidence, implementation, testing, or documentation)
- recommendation (add, update, retire, no-change, exclude, or defer)
- summary (candidate-specific non-empty string)
- impactDescription (candidate-specific non-empty string)
- currentHostedCoverage (candidate-specific non-empty string)
- affectedSurfaces (unique values from repository, implementation, testing, documentation, review-skill)
- guardedTokenDelta (integer)
- proposedText (string)
- selectionFactors (severity, frequency, breadth, hostedDetectability, evidenceStrength, falsePositiveRisk, and redundancy; each an integer from 0 through 5)
- selectionRationale (non-empty string explaining why every factor value supports the recommendation)

Use a stable assessmentId containing only letters, digits, and hyphens. For an existing Hosted rule, use its exact rule ID as assessmentId and targetHostedRuleId. For a new rule, use a concise lowercase semantic slug as assessmentId and null targetHostedRuleId. Every assessment must propose one complete Hosted rule independently from its recommendation: provide concise enforceable proposedText, a real hostedCategory, at least one affectedSurface, and a semantically meaningful proposedHostedRuleId that is at most 32 characters and matches `^[A-Z]+(?:-[A-Z0-9]+)+-[0-9]{3}[A-Z]?$`. When targetHostedRuleId is present, proposedHostedRuleId must default to that target ID; use a different unused ID only when the semantic proposal intentionally renames an updated or retired target. When targetHostedRuleId is null, generate an unused proposedHostedRuleId even for no-change, exclude, or defer so a later maintainer override starts from a complete proposal. Proposed IDs must not reuse any active or retired catalog ID unless they identify that assessment's exact targetHostedRuleId. Set candidateState to changed for an update, new for an add, retired for a retirement, deferred for a deferred decision, and current when an existing rule does not change. Update and retire must identify exactly one active targetHostedRuleId. Add must use null targetHostedRuleId. No-change may identify an existing target or use null when no catalog rule is involved. An update proposedText must be the complete replacement rule and preserve every still-valid safeguard from the target rule. Compare exact rule meaning, evidence, and failure condition against all current Hosted rules. Do not assign uniform or default factors. Do not invent evidence. A non-applicable candidate must use recommendation=exclude and guardedTokenDelta=0, but must still preserve its complete proposed Hosted rule, best-fit Hosted category, and affected surfaces for maintainer review. Use guardedTokenDelta=0 for no-change, exclude, and defer. The source record ID must exactly match the input.
'@
$repairPromptContract = @'
Read the candidate repair batch and current Hosted instruction catalog at the exact paths provided below. Repair only the explicitly requested assessment fields. This is a field-level migration of existing semantic assessments, not a reassessment.

Return only a raw JSON array with one object per candidate, in input order. Each object must contain exactly `id` and `repairs`. Each repair must contain exactly `assessmentId`, `proposedHostedRuleId`, `proposedText`, `hostedCategory`, and `affectedSurfaces`.

Preserve the existing recommendation, applicability decision, factors, rationale, target identity, and every other assessment field. Use the existing assessment and source evidence to supply a concise, complete, enforceable proposed Hosted rule. `hostedCategory` must be repository, review-classification-and-evidence, implementation, testing, or documentation. `affectedSurfaces` must contain one or more unique values from repository, implementation, testing, documentation, or review-skill. `proposedHostedRuleId` must be at most 32 characters and match `^[A-Z]+(?:-[A-Z0-9]+)+-[0-9]{3}[A-Z]?$`. When targetHostedRuleId exists, proposedHostedRuleId must equal it unless the existing assessment explicitly requires a rename. Otherwise generate an unused ID that does not appear in `reservedHostedRuleIds`. Return a repair for every requested assessment and no others. The source record ID and assessmentId values must match the packet exactly.
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
$baseline = $null
if (Test-Path -LiteralPath $resolvedBaselinePath -PathType Leaf) {
    $baselineContent = Get-Content -LiteralPath $resolvedBaselinePath -Raw
    $baselineSchemaValid = $false
    try {
        $baselineSchemaValid = [bool]($baselineContent | Test-Json -SchemaFile $baselineSchemaPath -ErrorAction Stop)
    }
    catch {
        if (-not $RepairMissingFields) {
            throw
        }
    }
    if (-not $baselineSchemaValid -and -not $RepairMissingFields) {
        throw "Assessment baseline does not satisfy its schema: $resolvedBaselinePath"
    }
    $baseline = $baselineContent | ConvertFrom-Json
    if ($null -eq $baseline.PSObject.Properties['hostedCatalogSha256'] -or $null -eq $baseline.PSObject.Properties['entries']) {
        throw "Assessment baseline does not contain the repairable baseline envelope: $resolvedBaselinePath"
    }
    $baselineCatalogMatches = [string]$baseline.hostedCatalogSha256 -eq $hostedCatalogHash
    if ($baselineCatalogMatches) {
        foreach ($entry in @($baseline.entries)) {
            $identity = Get-AssessmentIdentity -SourceType ([string]$entry.sourceType) -Id ([string]$entry.id)
            if ($baselineByIdentity.ContainsKey($identity)) {
                throw "Assessment baseline contains duplicate candidate identity: $identity"
            }
            $entryAssessments = @($entry.assessments)
            if (@($entryAssessments | Where-Object { [string]$_.sourceContentSha256 -ne [string]$entry.sourceContentSha256 }).Count -gt 0) {
                throw "Assessment baseline entry has a stale embedded assessment: $identity"
            }
            $baselineByIdentity[$identity] = $entry
        }
    }
}

$proposedHostedRuleIdOwners = @{}
foreach ($knownHostedRuleId in $knownHostedRuleIds) {
    $proposedHostedRuleIdOwners[$knownHostedRuleId] = "catalog:$knownHostedRuleId"
}
if ($null -ne $baseline) {
    foreach ($baselineEntry in @($baseline.entries)) {
        $null = Add-AssessmentProposalReservations -Owners $proposedHostedRuleIdOwners -SourceType ([string]$baselineEntry.sourceType) -CandidateId ([string]$baselineEntry.id) -Assessments @($baselineEntry.assessments)
    }
}

$cacheEntries = New-Object 'System.Collections.Generic.List[object]'
$cacheReset = $false
if (Test-Path -LiteralPath $resolvedCachePath -PathType Leaf) {
    $cache = $null
    try {
        $cache = Get-Content -LiteralPath $resolvedCachePath -Raw | ConvertFrom-Json -ErrorAction Stop
    }
    catch {
        $cacheReset = $true
    }

    $cacheIsCurrent = -not $cacheReset -and
        $null -ne $cache -and
        $null -ne $cache.PSObject.Properties['schemaVersion'] -and
        [string]$cache.schemaVersion -eq '2' -and
        $null -ne $cache.PSObject.Properties['entries'] -and
        $null -ne $cache.entries
    if ($cacheIsCurrent) {
        foreach ($entry in @($cache.entries)) {
            if ($null -eq $entry -or $null -eq $entry.PSObject.Properties['contextKey']) {
                $cacheIsCurrent = $false
                break
            }
        }
    }

    if ($cacheIsCurrent) {
        foreach ($entry in @($cache.entries)) {
            $cacheEntries.Add($entry)
        }
    }
    else {
        $cacheReset = $true
        Write-JsonAtomically -Path $resolvedCachePath -Value ([ordered]@{
            schemaVersion = 2
            updatedAt = [DateTimeOffset]::UtcNow.ToString('o')
            entries = @()
        })
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

$assessmentSetsByIdentity = @{}
$cacheHitCount = 0
$baselineHitCount = 0
$repairHitCount = 0
$deterministicRepairCount = 0
$seededCount = 0
$pending = New-Object 'System.Collections.Generic.List[object]'
$repairPending = New-Object 'System.Collections.Generic.List[object]'
foreach ($record in $candidateRecords.ToArray()) {
    $assessments = $null
    $assessmentSetResolved = $false
    if (-not $Force -and $cacheByContextKey.ContainsKey($record.contextKey)) {
        $cacheEntry = $cacheByContextKey[$record.contextKey]
        if ($cacheEntry.PSObject.Properties['assessments']) {
            $assessments = @($cacheEntry.assessments)
            Assert-SemanticAssessmentSet -Assessments $assessments -SourceType $record.sourceType -SourceHash $record.sourceHash -Context "Cached assessments $($record.identity)" -Full
            if (Add-AssessmentProposalReservations -Owners $proposedHostedRuleIdOwners -SourceType $record.sourceType -CandidateId ([string]$record.candidate.id) -Assessments $assessments) {
                $cacheHitCount++
                $assessmentSetResolved = $true
            }
            else {
                $assessments = $null
            }
        }
    }
    if (-not $assessmentSetResolved -and -not $Force -and $baselineByIdentity.ContainsKey($record.identity)) {
        $baselineEntry = $baselineByIdentity[$record.identity]
        if ([string]$baselineEntry.sourceContentSha256 -eq $record.sourceHash) {
            $assessments = if ($RepairMissingFields) { @(Get-DeterministicallyRepairedAssessments -Assessments @($baselineEntry.assessments)) } else { @($baselineEntry.assessments) }
            $repairRequests = @($assessments | ForEach-Object {
                $fields = @(Get-AssessmentRepairFields -Assessment $_)
                if ($fields.Count -gt 0) {
                    [pscustomobject][ordered]@{
                        assessmentId = [string]$_.assessmentId
                        fields = $fields
                    }
                }
            })
            if ($RepairMissingFields -and $repairRequests.Count -gt 0) {
                Assert-RepairableAssessmentSet -Assessments $assessments -SourceType $record.sourceType -SourceHash $record.sourceHash -Context "Repairable baseline assessments $($record.identity)"
                $record | Add-Member -NotePropertyName repairAssessments -NotePropertyValue $assessments -Force
                $record | Add-Member -NotePropertyName repairRequests -NotePropertyValue $repairRequests -Force
                $repairPending.Add($record)
                $assessments = $null
                $repairHitCount++
            }
            else {
                Assert-SemanticAssessmentSet -Assessments $assessments -SourceType $record.sourceType -SourceHash $record.sourceHash -Context "Baseline assessments $($record.identity)" -Full
                if (-not (Add-AssessmentProposalReservations -Owners $proposedHostedRuleIdOwners -SourceType $record.sourceType -CandidateId ([string]$record.candidate.id) -Assessments $assessments)) {
                    throw "Baseline assessments $($record.identity) contain a colliding proposed Hosted rule ID"
                }
                $baselineHitCount++
                $assessmentSetResolved = $true
                if ($RepairMissingFields -and (@($baselineEntry.assessments | ForEach-Object { @(Get-AssessmentRepairFields -Assessment $_) }).Count -gt 0)) {
                    $deterministicRepairCount++
                }
            }
        }
    }
    if (-not $assessmentSetResolved -and -not $record.PSObject.Properties['repairAssessments'] -and -not $Force -and $TrustEmbeddedAssessments -and $record.candidate.PSObject.Properties['assessments']) {
        $assessments = @($record.candidate.assessments)
        Assert-SemanticAssessmentSet -Assessments $assessments -SourceType $record.sourceType -SourceHash $record.sourceHash -Context "Embedded assessments $($record.identity)" -Full
        $cacheEntries.Add([pscustomobject]@{
            contextKey = $record.contextKey
            sourceType = $record.sourceType
            id = [string]$record.candidate.id
            sourceContentSha256 = $record.sourceHash
            hostedCatalogSha256 = $hostedCatalogHash
            evaluatorContractSha256 = $evaluatorContractHash
            model = $Model
            reasoningEffort = $ReasoningEffort
            assessments = $assessments
        })
        $seededCount++
        $assessmentSetResolved = $true
    }

    if (-not $assessmentSetResolved -and -not $record.PSObject.Properties['repairAssessments']) {
        $pending.Add($record)
    }
    else {
        $assessmentSetsByIdentity[$record.identity] = $assessments
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
        schemaVersion = 2
        updatedAt = [DateTimeOffset]::UtcNow.ToString('o')
        entries = $cacheEntries.ToArray()
    })
}

$assessmentBatches = New-Object 'System.Collections.Generic.List[object]'
foreach ($sourceType in @('interactive', 'maintainer', 'upstream')) {
    $sourceRepairPending = @($repairPending.ToArray() | Where-Object sourceType -eq $sourceType)
    $sourceRepairBatchSize = if ($sourceType -eq 'upstream') { $UpstreamBatchSize } else { $BatchSize }
    for ($sourceOffset = 0; $sourceOffset -lt $sourceRepairPending.Count; $sourceOffset += $sourceRepairBatchSize) {
        $sourceLastIndex = [Math]::Min($sourceOffset + $sourceRepairBatchSize - 1, $sourceRepairPending.Count - 1)
        $assessmentBatches.Add([pscustomobject]@{
            mode = 'repair'
            sourceType = $sourceType
            records = @($sourceRepairPending[$sourceOffset..$sourceLastIndex])
        })
    }
    $sourcePending = @($pending.ToArray() | Where-Object sourceType -eq $sourceType)
    $sourceBatchSize = if ($sourceType -eq 'upstream') { $UpstreamBatchSize } else { $BatchSize }
    for ($sourceOffset = 0; $sourceOffset -lt $sourcePending.Count; $sourceOffset += $sourceBatchSize) {
        $sourceLastIndex = [Math]::Min($sourceOffset + $sourceBatchSize - 1, $sourcePending.Count - 1)
        $assessmentBatches.Add([pscustomobject]@{
            mode = 'full'
            sourceType = $sourceType
            records = @($sourcePending[$sourceOffset..$sourceLastIndex])
        })
    }
}

[int]$batchCount = $assessmentBatches.Count
$evaluatedCount = 0
$repairedCount = 0
try {
    for ($batchIndex = 0; $batchIndex -lt $assessmentBatches.Count; $batchIndex++) {
        [int]$batchNumber = $batchIndex + 1
        $batch = $assessmentBatches[$batchIndex]
        $batchRecords = @($batch.records)
        $batchId = '{0}-{1:D3}' -f $batch.mode, $batchNumber
        $batchDirectory = Join-Path $runDirectory $batchId
        New-Item -ItemType Directory -Path $batchDirectory -Force | Out-Null
        $batchPath = Join-Path $batchDirectory 'candidates.json'
        $responsePath = Join-Path $batchDirectory 'response.json'
        $batchCatalogPath = Join-Path $batchDirectory 'hosted-instruction-catalog.json'
        $batchSchemaPath = Join-Path $batchDirectory 'assessment-schema.json'
        Copy-Item -LiteralPath $catalogPath -Destination $batchCatalogPath -Force
        Copy-Item -LiteralPath $bundleSchemaPath -Destination $batchSchemaPath -Force
        $packetCandidates = if ($batch.mode -eq 'repair') {
            @($batchRecords | ForEach-Object {
                [pscustomobject][ordered]@{
                    candidate = $_.candidate | Select-Object * -ExcludeProperty assessment, assessments
                    existingAssessments = @($_.repairAssessments)
                    repairRequests = @($_.repairRequests)
                }
            })
        }
        else {
            @($batchRecords | ForEach-Object { $_.candidate | Select-Object * -ExcludeProperty assessment, assessments })
        }
        Write-JsonAtomically -Path $batchPath -Value ([ordered]@{
            batchId = $batchId
            mode = $batch.mode
            sourceType = $batch.sourceType
            candidateCount = $batchRecords.Count
            hostedCatalogSha256 = $hostedCatalogHash
            reservedHostedRuleIds = @($proposedHostedRuleIdOwners.Keys | Sort-Object)
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
                    $batchPromptContract = if ($batch.mode -eq 'repair') { $repairPromptContract } else { $promptContract }
                    $attemptPrompt = @"
$batchPromptContract

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
                    $expectedRecordProperties = if ($batch.mode -eq 'repair') { @('id', 'repairs') } else { @('id', 'assessments') }
                    Assert-ExactProperties -Value $semanticRecord -Expected $expectedRecordProperties -Context "Evaluator record in $batchId"
                    $id = [string]$semanticRecord.id
                    if ($recordsById.ContainsKey($id)) {
                        throw "Evaluator returned duplicate candidate $id in $batchId"
                    }
                    if ($batch.mode -eq 'repair') {
                        $batchRecord = @($batchRecords | Where-Object { [string]$_.candidate.id -eq $id })[0]
                        if ($null -eq $batchRecord) {
                            throw "Evaluator returned unknown repair candidate $id in $batchId"
                        }
                        $repairRequestsById = @{}
                        foreach ($repairRequest in @($batchRecord.repairRequests)) {
                            $repairRequestsById[[string]$repairRequest.assessmentId] = $repairRequest
                        }
                        $seenRepairIds = @{}
                        foreach ($repair in @($semanticRecord.repairs)) {
                            Assert-ExactProperties -Value $repair -Expected $repairAssessmentProperties -Context "Evaluator repair $id in $batchId"
                            $assessmentId = [string]$repair.assessmentId
                            if (-not $repairRequestsById.ContainsKey($assessmentId) -or $seenRepairIds.ContainsKey($assessmentId)) {
                                throw "Evaluator returned an unknown or duplicate assessment repair $id/$assessmentId in $batchId"
                            }
                            $seenRepairIds[$assessmentId] = $true
                        }
                        if ($seenRepairIds.Count -ne $repairRequestsById.Count) {
                            throw "Evaluator omitted one or more assessment repairs for $id in $batchId"
                        }
                    }
                    else {
                        Assert-SemanticAssessmentSet -Assessments @($semanticRecord.assessments) -SourceType ([string]$batch.sourceType) -Context "Evaluator assessments $id"
                    }
                    $recordsById[$id] = $semanticRecord
                }
                foreach ($batchRecord in $batchRecords) {
                    if (-not $recordsById.ContainsKey([string]$batchRecord.candidate.id)) {
                        throw "Evaluator omitted candidate $($batchRecord.candidate.id) in $batchId"
                    }
                }
                $attemptProposalOwners = @{}
                foreach ($entry in $proposedHostedRuleIdOwners.GetEnumerator()) {
                    $attemptProposalOwners[$entry.Key] = $entry.Value
                }
                foreach ($batchRecord in $batchRecords) {
                    if ($batch.mode -eq 'repair') {
                        $repairsById = @{}
                        foreach ($repair in @($recordsById[[string]$batchRecord.candidate.id].repairs)) {
                            $repairsById[[string]$repair.assessmentId] = $repair
                        }
                        $proposalAssessments = @($batchRecord.repairAssessments | ForEach-Object {
                            $assessmentId = [string]$_.assessmentId
                            [pscustomobject]@{
                                assessmentId = $assessmentId
                                targetHostedRuleId = $_.targetHostedRuleId
                                proposedHostedRuleId = $repairsById[$assessmentId].proposedHostedRuleId
                            }
                        })
                    }
                    else {
                        $proposalAssessments = @($recordsById[[string]$batchRecord.candidate.id].assessments)
                    }
                    if (-not (Add-AssessmentProposalReservations -Owners $attemptProposalOwners -SourceType $batchRecord.sourceType -CandidateId ([string]$batchRecord.candidate.id) -Assessments $proposalAssessments)) {
                        throw "Evaluator returned a colliding proposed Hosted rule ID for $($batchRecord.identity) in $batchId"
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
            if ($batch.mode -eq 'repair') {
                $repairsById = @{}
                foreach ($repair in @($recordsById[[string]$batchRecord.candidate.id].repairs)) {
                    $repairsById[[string]$repair.assessmentId] = $repair
                }
                $repairRequestsById = @{}
                foreach ($repairRequest in @($batchRecord.repairRequests)) {
                    $repairRequestsById[[string]$repairRequest.assessmentId] = $repairRequest
                }
                $assessmentSet = @($batchRecord.repairAssessments | ForEach-Object {
                    $assessment = $_ | ConvertTo-Json -Depth 20 | ConvertFrom-Json
                    $assessmentId = [string]$assessment.assessmentId
                    if ($repairRequestsById.ContainsKey($assessmentId)) {
                        $repair = $repairsById[$assessmentId]
                        foreach ($field in @($repairRequestsById[$assessmentId].fields)) {
                            if ($field -eq 'affectedSurfaces') {
                                $assessment.affectedSurfaces = [string[]]@($repair.affectedSurfaces)
                                continue
                            }
                            $value = $repair.$field
                            if ($assessment.PSObject.Properties[$field]) {
                                $assessment.$field = $value
                            }
                            else {
                                $assessment | Add-Member -NotePropertyName $field -NotePropertyValue $value
                            }
                        }
                        $assessment.assessedAt = $assessedAt
                        $assessment.evaluator = $evaluatorName
                    }
                    $assessment
                })
                $repairedCount++
            }
            else {
                $assessmentSet = @($recordsById[[string]$batchRecord.candidate.id].assessments | ForEach-Object {
                    $semanticAssessment = $_
                    $assessment = [ordered]@{
                        status = 'evaluated'
                        sourceContentSha256 = $batchRecord.sourceHash
                        assessedAt = $assessedAt
                        evaluator = $evaluatorName
                    }
                    foreach ($propertyName in $semanticAssessmentProperties) {
                        $assessment[$propertyName] = $semanticAssessment.$propertyName
                    }
                    [pscustomobject]$assessment
                })
                $evaluatedCount++
            }
            Assert-SemanticAssessmentSet -Assessments $assessmentSet -SourceType $batchRecord.sourceType -SourceHash $batchRecord.sourceHash -Context "Generated assessments $($batchRecord.identity)" -Full
            if (-not (Add-AssessmentProposalReservations -Owners $proposedHostedRuleIdOwners -SourceType $batchRecord.sourceType -CandidateId ([string]$batchRecord.candidate.id) -Assessments $assessmentSet)) {
                throw "Generated assessments $($batchRecord.identity) contain a colliding proposed Hosted rule ID"
            }
            $assessmentSetsByIdentity[$batchRecord.identity] = $assessmentSet
            $cacheEntries.Add([pscustomobject]@{
                contextKey = $batchRecord.contextKey
                sourceType = $batchRecord.sourceType
                id = [string]$batchRecord.candidate.id
                sourceContentSha256 = $batchRecord.sourceHash
                hostedCatalogSha256 = $hostedCatalogHash
                evaluatorContractSha256 = $evaluatorContractHash
                model = $Model
                reasoningEffort = $ReasoningEffort
                assessments = $assessmentSet
            })
        }

        $activeContextKeys = @($candidateRecords.ToArray().contextKey)
        $compactedEntries = @($cacheEntries | Where-Object { $_.contextKey -in $activeContextKeys } | Group-Object contextKey | ForEach-Object { $_.Group[-1] })
        $cacheEntries = New-Object 'System.Collections.Generic.List[object]'
        foreach ($entry in $compactedEntries) {
            $cacheEntries.Add($entry)
        }
        Write-JsonAtomically -Path $resolvedCachePath -Value ([ordered]@{
            schemaVersion = 2
            updatedAt = [DateTimeOffset]::UtcNow.ToString('o')
            entries = $cacheEntries.ToArray()
        })
        if ($OutputFormat -eq 'Text') {
            Write-Host ("[PASSED]   assessment/{0,-19} : {1} candidates" -f $batchId, $batchRecords.Count)
        }
    }

    foreach ($record in $candidateRecords.ToArray()) {
        if (-not $assessmentSetsByIdentity.ContainsKey($record.identity)) {
            throw "Assessment is missing after evaluation: $($record.identity)"
        }
        $record.candidate.PSObject.Properties.Remove('assessment')
        $record.candidate | Add-Member -NotePropertyName assessments -NotePropertyValue @($assessmentSetsByIdentity[$record.identity]) -Force
    }

    $proposedHostedRuleIds = @{}
    foreach ($record in $candidateRecords.ToArray()) {
        foreach ($assessment in @($record.candidate.assessments)) {
            $proposedHostedRuleId = [string]$assessment.proposedHostedRuleId
            $targetHostedRuleId = [string]$assessment.targetHostedRuleId
            if ($proposedHostedRuleId -eq $targetHostedRuleId) {
                continue
            }
            if ($proposedHostedRuleIds.ContainsKey($proposedHostedRuleId)) {
                throw "Proposed Hosted rule ID $proposedHostedRuleId is assigned to both $($proposedHostedRuleIds[$proposedHostedRuleId]) and $($record.identity)"
            }
            $proposedHostedRuleIds[$proposedHostedRuleId] = $record.identity
        }
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
    $allRuleAssessments = @($allCandidates | ForEach-Object { @($_.assessments) })
    $summary = [ordered]@{
        status = 'passed'
        outputPath = $resolvedOutputPath
        cachePath = $resolvedCachePath
        candidateCount = $allCandidates.Count
        cacheReset = $cacheReset
        cacheHitCount = $cacheHitCount
        baselineHitCount = $baselineHitCount
        repairCandidateCount = $repairHitCount
        deterministicRepairCount = $deterministicRepairCount
        repairedCount = $repairedCount
        seededCount = $seededCount
        evaluatedCount = $evaluatedCount
        batchCount = $batchCount
        repairBatchCount = @($assessmentBatches | Where-Object mode -eq 'repair').Count
        fullBatchCount = @($assessmentBatches | Where-Object mode -eq 'full').Count
        ruleCandidateCount = $allRuleAssessments.Count
        applicableCount = @($allRuleAssessments | Where-Object hostedApplicable).Count
        inapplicableCount = @($allRuleAssessments | Where-Object { -not $_.hostedApplicable }).Count
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
            'Rule Candidates' = $summary.ruleCandidateCount
            'Cache Reset' = $summary.cacheReset
            'Cache Hits' = $summary.cacheHitCount
            'Baseline Hits' = $summary.baselineHitCount
            'Repair Candidates' = $summary.repairCandidateCount
            'Deterministic Repairs' = $summary.deterministicRepairCount
            'Semantic Repairs' = $summary.repairedCount
            Seeded = $summary.seededCount
            Evaluated = $summary.evaluatedCount
            Batches = $summary.batchCount
            'Repair Batches' = $summary.repairBatchCount
            'Full Batches' = $summary.fullBatchCount
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
