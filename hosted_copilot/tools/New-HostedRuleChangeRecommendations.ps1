[CmdletBinding()]
param(
    [string]$RepositoryRoot = (Join-Path $PSScriptRoot '../..'),

    [Parameter(Mandatory = $true)]
    [string]$AssessmentBaselinePath,

    [Parameter(Mandatory = $true)]
    [string]$ReconciliationDraftPath,

    [Parameter(Mandatory = $true)]
    [string]$OutputPath,

    [string]$HostedCatalogPath = (Join-Path $PSScriptRoot '../copilot-rule-catalog/instruction-catalog.json'),

    [string]$ReconciliationContractPath = (Join-Path $PSScriptRoot '../copilot-rule-catalog/assessment-reconciliation/hosted-rule-change-recommendations-v1.json'),

    [string]$PromotionPlanPath,

    [object]$GeneratedAt = [DateTime]::UtcNow,

    [ValidateSet('Text', 'Json')]
    [string]$OutputFormat = 'Text'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$helpersPath = Join-Path $PSScriptRoot 'HostedToolkit.Helpers.psm1'
$sourceEvidencePath = Join-Path $PSScriptRoot 'SourceEvidenceValidation.psm1'
$reconciliationValidationPath = Join-Path $PSScriptRoot 'AssessmentReconciliationValidation.psm1'
Import-Module -Name $sourceEvidencePath -Force
Import-Module -Name $helpersPath -Force
Import-Module -Name $reconciliationValidationPath -Force

function Read-JsonFile {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$SchemaPath,
        [Parameter(Mandatory = $true)][string]$Name
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "$Name was not found: $Path"
    }
    $snapshot = Get-FileSnapshot -Path $Path
    try {
        $valid = Test-Json -Json $snapshot.Content -SchemaFile $SchemaPath -ErrorAction Stop
    }
    catch {
        throw "$Name does not satisfy its schema: $Path"
    }
    if (-not $valid) {
        throw "$Name does not satisfy its schema: $Path"
    }
    return [pscustomobject]@{
        Value = $snapshot.Content | ConvertFrom-Json -DateKind String
        Snapshot = $snapshot
    }
}

function Get-AssessmentKey {
    param([Parameter(Mandatory = $true)][object]$Reference)

    return [string]$Reference.sourceDefinitionId + [char]0 + [string]$Reference.sourceId + [char]0 + [string]$Reference.contentSha256 + [char]0 + [string]$Reference.assessmentId
}

function New-AssessmentReference {
    param(
        [Parameter(Mandatory = $true)][object]$Reference,
        [Parameter(Mandatory = $true)][string]$BaselineSha256
    )

    return [ordered]@{
        assessmentBaselineSha256 = $BaselineSha256
        sourceDefinitionId = [string]$Reference.sourceDefinitionId
        sourceId = [string]$Reference.sourceId
        contentSha256 = [string]$Reference.contentSha256
        assessmentId = [string]$Reference.assessmentId
    }
}

function Get-EstimatedTokens {
    param([Parameter(Mandatory = $true)][AllowEmptyString()][string]$Text)

    return [int][Math]::Ceiling($Text.Length / 4.0)
}

function Get-GuardedTokens {
    param([Parameter(Mandatory = $true)][AllowEmptyString()][string]$Text)

    return [int][Math]::Ceiling((Get-EstimatedTokens -Text $Text) * 1.25)
}

$resolvedRepositoryRoot = [IO.Path]::GetFullPath($RepositoryRoot).TrimEnd([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar)
$repositoryPrefix = $resolvedRepositoryRoot + [IO.Path]::DirectorySeparatorChar
$resolvedOutputPath = [IO.Path]::GetFullPath($OutputPath)
if ($resolvedOutputPath.StartsWith($repositoryPrefix, [StringComparison]::OrdinalIgnoreCase)) {
    throw 'Hosted rule change recommendation output must be outside the repository root'
}

$reconciliationRoot = Join-Path $resolvedRepositoryRoot 'hosted_copilot/copilot-rule-catalog/assessment-reconciliation'
$assessmentRoot = Join-Path $resolvedRepositoryRoot 'hosted_copilot/copilot-rule-catalog/rule-assessments'
$catalogRoot = Join-Path $resolvedRepositoryRoot 'hosted_copilot/copilot-rule-catalog'
$baselineInput = Read-JsonFile -Path ([IO.Path]::GetFullPath($AssessmentBaselinePath)) -SchemaPath (Join-Path $assessmentRoot 'source-assessment-baseline.schema.json') -Name 'Source assessment baseline'
$draftInput = Read-JsonFile -Path ([IO.Path]::GetFullPath($ReconciliationDraftPath)) -SchemaPath (Join-Path $reconciliationRoot 'assessment-reconciliation-draft.schema.json') -Name 'Assessment reconciliation draft'
$catalogInput = Read-JsonFile -Path ([IO.Path]::GetFullPath($HostedCatalogPath)) -SchemaPath (Join-Path $catalogRoot 'instruction-catalog.schema.json') -Name 'Hosted instruction catalog'
$contractInput = Read-JsonFile -Path ([IO.Path]::GetFullPath($ReconciliationContractPath)) -SchemaPath (Join-Path $reconciliationRoot 'assessment-reconciliation-contract.schema.json') -Name 'Assessment reconciliation contract'
$baseline = $baselineInput.Value
$draft = $draftInput.Value
$catalog = $catalogInput.Value
$contract = $contractInput.Value
$reconciliationContractSha256 = Get-HostedRuleChangeRecommendationsContractSha256 -Contract $contract -RepositoryRoot $resolvedRepositoryRoot

$catalogRules = @{}
$catalogLocations = @{}
$reservedHostedIds = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
foreach ($rule in @($catalog.rules)) {
    $catalogRules[[string]$rule.id] = $rule
    $null = $reservedHostedIds.Add([string]$rule.id)
}
foreach ($surface in @($catalog.surfaces)) {
    foreach ($section in @($surface.sections)) {
        foreach ($hostedId in @($section.ruleIds)) {
            $catalogLocations[[string]$hostedId] = [ordered]@{ category = [string]$surface.id; placement = [string]$section.heading }
        }
    }
}

$pendingRules = @{}
$promotionPlanSha256 = $null
if (-not [string]::IsNullOrWhiteSpace($PromotionPlanPath)) {
    $promotionPlanInput = Read-JsonFile -Path ([IO.Path]::GetFullPath($PromotionPlanPath)) -SchemaPath (Join-Path $catalogRoot 'promotion-plan.schema.json') -Name 'Promotion Plan'
    $promotionPlanSha256 = $promotionPlanInput.Snapshot.Sha256
    foreach ($change in @($promotionPlanInput.Value.ruleChanges)) {
        $hostedId = [string]$change.hostedRuleId
        if ($pendingRules.ContainsKey($hostedId)) {
            throw "Promotion Plan contains duplicate Hosted ID ownership: $hostedId"
        }
        $pendingRules[$hostedId] = $change
        $null = $reservedHostedIds.Add($hostedId)
    }
}

$assessments = @{}
foreach ($entry in @($baseline.entries)) {
    foreach ($assessment in @($entry.assessments)) {
        $reference = [ordered]@{
            sourceDefinitionId = [string]$entry.sourceRef.sourceDefinitionId
            sourceId = [string]$entry.sourceRef.sourceId
            contentSha256 = [string]$entry.sourceRef.contentSha256
            assessmentId = [string]$assessment.assessmentId
        }
        $key = Get-AssessmentKey -Reference $reference
        if ($assessments.ContainsKey($key)) {
            throw "Source assessment baseline contains duplicate assessment identity: $($reference.sourceDefinitionId)/$($reference.sourceId)/$($reference.assessmentId)"
        }
        $assessments[$key] = [ordered]@{ reference = $reference; assessment = $assessment }
    }
}
if ($assessments.Count -eq 0) {
    throw 'Source assessment baseline contains no assessments to reconcile'
}

$draftRecommendations = @{}
$membershipByAssessment = @{}
foreach ($recommendation in @($draft.recommendations)) {
    $draftKey = [string]$recommendation.draftKey
    if ($draftRecommendations.ContainsKey($draftKey)) {
        throw "Assessment reconciliation draft contains duplicate draftKey: $draftKey"
    }
    $draftRecommendations[$draftKey] = $recommendation
    $memberKeys = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    foreach ($reference in @($recommendation.memberAssessmentRefs)) {
        $assessmentKey = Get-AssessmentKey -Reference $reference
        if (-not $assessments.ContainsKey($assessmentKey)) {
            throw "Hosted rule change recommendation references an unknown assessment: $draftKey"
        }
        if (-not $memberKeys.Add($assessmentKey)) {
            throw "Hosted rule change recommendation repeats an assessment: $draftKey"
        }
        if ($membershipByAssessment.ContainsKey($assessmentKey)) {
            throw "Assessment belongs to more than one generated recommendation: $draftKey"
        }
        $membershipByAssessment[$assessmentKey] = $draftKey
    }

    $category = [string]$recommendation.category
    $placement = [string]$recommendation.placement
    $targetHostedId = if ($null -eq $recommendation.targetHostedId) { $null } else { [string]$recommendation.targetHostedId }
    $idFamily = if ($null -eq $recommendation.idFamily) { $null } else { [string]$recommendation.idFamily }
    $action = [string]$recommendation.recommendedAction
    $targetExists = $null -ne $targetHostedId -and ($catalogRules.ContainsKey($targetHostedId) -or $pendingRules.ContainsKey($targetHostedId))
    if ($action -in @('update', 'no-change') -and -not $targetExists) {
        throw "Recommendation $draftKey requires one exact existing Hosted target"
    }
    if ($action -in @('update', 'no-change') -and $catalogRules.ContainsKey($targetHostedId) -and [string]$catalogRules[$targetHostedId].status -cne 'active') {
        throw "Recommendation $draftKey cannot target retired Hosted rule $targetHostedId without an explicit Restore decision"
    }
    if ($action -eq 'add' -and ($null -ne $targetHostedId -or $null -eq $idFamily)) {
        throw "Recommendation $draftKey must use an allowlisted Hosted ID family without a target"
    }
    if ($action -eq 'defer' -and (($null -eq $targetHostedId) -eq ($null -eq $idFamily))) {
        throw "Deferred recommendation $draftKey must identify exactly one existing target or new Hosted ID family"
    }
    if ($null -ne $targetHostedId) {
        $location = if ($catalogLocations.ContainsKey($targetHostedId)) { $catalogLocations[$targetHostedId] } else { $pendingRules[$targetHostedId] }
        $targetCategory = if ($catalogLocations.ContainsKey($targetHostedId)) { [string]$location.category } else { [string]$location.surfaceId }
        $targetPlacement = if ($catalogLocations.ContainsKey($targetHostedId)) { [string]$location.placement } else { [string]$location.sectionHeading }
        if ($category -cne $targetCategory -or $placement -cne $targetPlacement) {
            throw "Recommendation $draftKey placement does not match Hosted target $targetHostedId"
        }
    }
    else {
        $allowedFamily = @($contract.idAllocation.families | Where-Object { [string]$_.category -ceq $category -and [string]$_.placement -ceq $placement -and [string]$_.idFamily -ceq $idFamily })
        if ($allowedFamily.Count -ne 1) {
            throw "Recommendation $draftKey uses an ID family outside the configured Hosted category and placement"
        }
    }

    foreach ($coverage in @($recommendation.relatedHostedCoverage)) {
        if (-not $catalogRules.ContainsKey([string]$coverage.hostedRuleId)) {
            throw "Recommendation $draftKey references unknown related Hosted coverage: $($coverage.hostedRuleId)"
        }
        foreach ($reference in @($coverage.assessmentRefs)) {
            $coverageKey = Get-AssessmentKey -Reference $reference
            if (-not $memberKeys.Contains($coverageKey)) {
                throw "Recommendation $draftKey related coverage references a non-member assessment"
            }
            $sourceCoverage = @($assessments[$coverageKey].assessment.relatedHostedCoverage | Where-Object { [string]$_.hostedRuleId -ceq [string]$coverage.hostedRuleId })
            if ($sourceCoverage.Count -ne 1) {
                throw "Recommendation $draftKey related coverage is not backed by assessment evidence"
            }
        }
    }
}

$coverageByAssessment = @{}
foreach ($coverage in @($draft.assessmentCoverage)) {
    $assessmentKey = Get-AssessmentKey -Reference $coverage.assessmentRef
    if (-not $assessments.ContainsKey($assessmentKey)) {
        throw 'Assessment coverage references an unknown assessment'
    }
    if ($coverageByAssessment.ContainsKey($assessmentKey)) {
        throw 'Assessment reconciliation draft contains duplicate assessment coverage'
    }
    $coverageByAssessment[$assessmentKey] = $coverage
    $draftKeys = @($coverage.recommendationDraftKeys)
    if ([string]$coverage.disposition -ceq 'recommended') {
        if ($draftKeys.Count -ne 1 -or -not $draftRecommendations.ContainsKey([string]$draftKeys[0])) {
            throw 'Recommended assessment coverage must reference one known recommendation'
        }
        if (-not $membershipByAssessment.ContainsKey($assessmentKey) -or [string]$membershipByAssessment[$assessmentKey] -cne [string]$draftKeys[0]) {
            throw 'Assessment coverage and recommendation membership do not match'
        }
    }
    elseif ($membershipByAssessment.ContainsKey($assessmentKey)) {
        throw 'Deferred or excluded assessment coverage cannot belong to a recommendation'
    }
}
$missingCoverage = @($assessments.Keys | Where-Object { -not $coverageByAssessment.ContainsKey($_) })
if ($missingCoverage.Count -ne 0) {
    throw "Assessment reconciliation does not cover every assessment: $($missingCoverage.Count) missing"
}

$orderedDraftRecommendations = @($draftRecommendations.Values | Sort-Object -Property @{ Expression = { [string]$_.category } }, @{ Expression = { [string]$_.placement } }, @{ Expression = { [string]$_.idFamily } }, @{ Expression = { [string]$_.targetHostedId } }, @{ Expression = { [string]$_.title } }, @{ Expression = { [string]$_.draftKey } })
$hostedIdByDraftKey = @{}
foreach ($recommendation in $orderedDraftRecommendations) {
    $draftKey = [string]$recommendation.draftKey
    if ($null -ne $recommendation.targetHostedId) {
        $hostedId = [string]$recommendation.targetHostedId
    }
    else {
        $family = [string]$recommendation.idFamily
        $nextNumber = 1
        do {
            $hostedId = '{0}-{1}' -f $family, $nextNumber.ToString("D$([int]$contract.idAllocation.numericWidth)")
            $nextNumber++
        } while ($reservedHostedIds.Contains($hostedId) -and $nextNumber -le 1000)
        if ($reservedHostedIds.Contains($hostedId)) {
            throw "No Hosted IDs remain available in family $family"
        }
    }
    if (-not $reservedHostedIds.Add($hostedId) -and $null -eq $recommendation.targetHostedId) {
        throw "Hosted ID allocation produced a duplicate ID: $hostedId"
    }
    if ($hostedIdByDraftKey.Values -contains $hostedId) {
        throw "More than one recommendation owns Hosted ID $hostedId"
    }
    $hostedIdByDraftKey[$draftKey] = $hostedId
}

$recommendations = [Collections.Generic.List[object]]::new()
foreach ($recommendation in $orderedDraftRecommendations) {
    $draftKey = [string]$recommendation.draftKey
    $hostedId = [string]$hostedIdByDraftKey[$draftKey]
    $currentText = ''
    $idState = 'tentative'
    if ($catalogRules.ContainsKey($hostedId)) {
        $currentText = [string]$catalogRules[$hostedId].text
        $idState = 'existing'
    }
    elseif ($pendingRules.ContainsKey($hostedId)) {
        if ($pendingRules[$hostedId].PSObject.Properties['targetRule']) {
            $currentText = [string]$pendingRules[$hostedId].targetRule.text
        }
        $idState = 'durable'
    }
    $recommendedText = [string]$recommendation.recommendedRuleText
    if ([string]$recommendation.recommendedAction -ceq 'no-change' -and $recommendedText -cne $currentText) {
        throw "No Change recommendation $draftKey must preserve the exact current Hosted rule text"
    }
    if ([string]$recommendation.recommendedAction -ceq 'update' -and $recommendedText -ceq $currentText) {
        throw "Update recommendation $draftKey must change the Hosted rule text"
    }
    $recommendations.Add([ordered]@{
        hostedId = $hostedId
        idState = $idState
        recommendedAction = [string]$recommendation.recommendedAction
        title = [string]$recommendation.title
        recommendedRuleText = $recommendedText
        category = [string]$recommendation.category
        placement = [string]$recommendation.placement
        rationale = [string]$recommendation.rationale
        needsReview = [bool]$recommendation.needsReview
        memberAssessmentRefs = @($recommendation.memberAssessmentRefs | ForEach-Object { New-AssessmentReference -Reference $_ -BaselineSha256 $baselineInput.Snapshot.Sha256 })
        relatedHostedCoverage = @($recommendation.relatedHostedCoverage | ForEach-Object {
            [ordered]@{
                hostedRuleId = [string]$_.hostedRuleId
                relationship = [string]$_.relationship
                rationale = [string]$_.rationale
                assessmentRefs = @($_.assessmentRefs | ForEach-Object { New-AssessmentReference -Reference $_ -BaselineSha256 $baselineInput.Snapshot.Sha256 })
            }
        })
        tokenProjection = [ordered]@{
            estimatedTokenDelta = (Get-EstimatedTokens -Text $recommendedText) - (Get-EstimatedTokens -Text $currentText)
            guardedTokenDelta = (Get-GuardedTokens -Text $recommendedText) - (Get-GuardedTokens -Text $currentText)
        }
    })
}

$assessmentCoverage = @($draft.assessmentCoverage | ForEach-Object {
    $hostedIds = @($_.recommendationDraftKeys | ForEach-Object { [string]$hostedIdByDraftKey[[string]$_] })
    [ordered]@{
        assessmentRef = New-AssessmentReference -Reference $_.assessmentRef -BaselineSha256 $baselineInput.Snapshot.Sha256
        disposition = [string]$_.disposition
        rationale = $_.rationale
        hostedIds = $hostedIds
    }
} | Sort-Object -Property @{ Expression = { Get-AssessmentKey -Reference $_.assessmentRef } })

$snapshot = [ordered]@{
    '$schema' = 'hosted-rule-change-recommendations.schema.json'
    schemaVersion = 1
    generatedAt = ConvertTo-SourceEvidenceUtcTimestamp -Value $GeneratedAt
    inventoryHashes = ConvertTo-OrdinalMap -Value $baseline.inventoryHashes
    assessmentBaselineSha256 = $baselineInput.Snapshot.Sha256
    hostedCatalogSha256 = $catalogInput.Snapshot.Sha256
    reconciliationContractSha256 = $reconciliationContractSha256
    promotionPlanSha256 = $promotionPlanSha256
    parentRecommendationSnapshotSha256 = $null
    recommendations = @($recommendations | Sort-Object -Property hostedId)
    assessmentCoverage = $assessmentCoverage
}
$snapshotJson = $snapshot | ConvertTo-Json -Depth 40
if (-not ($snapshotJson | Test-Json -SchemaFile (Join-Path $reconciliationRoot 'hosted-rule-change-recommendations.schema.json') -ErrorAction Stop)) {
    throw 'Hosted rule change recommendations do not satisfy their schema'
}
$outputSnapshot = Write-JsonSnapshot -Path $resolvedOutputPath -Value $snapshot

$result = [ordered]@{
    status = 'passed'
    outputPath = $resolvedOutputPath
    recommendationCount = $snapshot.recommendations.Count
    assessmentCount = $snapshot.assessmentCoverage.Count
    recommendationSnapshotSha256 = $outputSnapshot.Sha256
    reconciliationContractSha256 = $reconciliationContractSha256
}
if ($OutputFormat -eq 'Json') {
    $result | ConvertTo-Json -Depth 5
}
else {
    Write-Output "Hosted rule change recommendations generated: $($result.recommendationCount) recommendations, $($result.assessmentCount) assessments"
    Write-Output "Output: $($result.outputPath)"
    Write-Output "Snapshot SHA-256: $($result.recommendationSnapshotSha256)"
}
