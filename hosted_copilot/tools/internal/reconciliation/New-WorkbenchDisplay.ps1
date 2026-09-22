[CmdletBinding()]
param(
    [string]$RepositoryRoot = (Join-Path $PSScriptRoot '../../../..'),

    [Parameter(Mandatory = $true)]
    [string]$AssessmentBaselinePath,

    [Parameter(Mandatory = $true)]
    [string[]]$InventoryPaths,

    [Parameter(Mandatory = $true)]
    [string]$ReconciliationDraftPath,

    [Parameter(Mandatory = $true)]
    [string]$GuidanceCapacityPath,

    [Parameter(Mandatory = $true)]
    [string]$OutputPath,

    [string]$HostedCatalogPath = (Join-Path $PSScriptRoot '../../../copilot-rule-catalog/instruction-catalog.json'),

    [string]$ReconciliationContractPath = (Join-Path $PSScriptRoot '../../../copilot-rule-catalog/assessment-reconciliation/assessment-reconciliation-v4.json'),

    [object]$GeneratedAt = [DateTime]::UtcNow,

    [ValidateSet('Text', 'Json')]
    [string]$OutputFormat = 'Text',

    [switch]$AllowConflicts
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$helpersPath = Join-Path $PSScriptRoot '../../modules/shared/HostedToolkit.Helpers.psm1'
$sourceEvidencePath = Join-Path $PSScriptRoot '../../modules/shared/SourceEvidenceValidation.psm1'
Import-Module -Name $sourceEvidencePath -Force
Import-Module -Name $helpersPath -Force

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

function Get-DisplayAssessmentKey {
    param([Parameter(Mandatory = $true)][object]$Reference)

    $lane = switch ([string]$Reference.sourceDefinitionId) {
        'contributor-guidance' { 'contributor' }
        'interactive-toolkit' { 'interactive' }
        'maintainer-proposals' { 'maintainer' }
        default { throw "Unsupported source lane: $($Reference.sourceDefinitionId)" }
    }
    return $lane + ':' + [string]$Reference.sourceId + ':' + [string]$Reference.assessmentId
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
    throw 'Workbench display output must be outside the repository root'
}

$reconciliationRoot = Join-Path $resolvedRepositoryRoot 'hosted_copilot/copilot-rule-catalog/assessment-reconciliation'
$assessmentRoot = Join-Path $resolvedRepositoryRoot 'hosted_copilot/copilot-rule-catalog/rule-assessments'
$catalogRoot = Join-Path $resolvedRepositoryRoot 'hosted_copilot/copilot-rule-catalog'
$baselineInput = Read-JsonFile -Path ([IO.Path]::GetFullPath($AssessmentBaselinePath)) -SchemaPath (Join-Path $assessmentRoot 'source-assessment-baseline-v4.schema.json') -Name 'Source assessment baseline'
$draftInput = Read-JsonFile -Path ([IO.Path]::GetFullPath($ReconciliationDraftPath)) -SchemaPath (Join-Path $reconciliationRoot 'assessment-reconciliation-draft.schema.json') -Name 'Assessment reconciliation draft'
$catalogInput = Read-JsonFile -Path ([IO.Path]::GetFullPath($HostedCatalogPath)) -SchemaPath (Join-Path $catalogRoot 'instruction-catalog.schema.json') -Name 'Hosted instruction catalog'
$contractInput = Read-JsonFile -Path ([IO.Path]::GetFullPath($ReconciliationContractPath)) -SchemaPath (Join-Path $reconciliationRoot 'assessment-reconciliation-contract.schema.json') -Name 'Assessment reconciliation contract'
$guidanceCapacityInput = Read-JsonFile -Path ([IO.Path]::GetFullPath($GuidanceCapacityPath)) -SchemaPath (Join-Path $catalogRoot 'guidance-capacity.schema.json') -Name 'Guidance capacity'
$baseline = $baselineInput.Value
$draft = $draftInput.Value
$catalog = $catalogInput.Value
$contract = $contractInput.Value
if ([string]$baseline.hostedCatalogSha256 -cne $catalogInput.Snapshot.Sha256) {
    throw 'Source assessment set does not bind the supplied Hosted catalog'
}

$inventoryRecords = @{}
$inventoryHashes = [ordered]@{}
$inventorySchemaPath = Join-Path $catalogRoot 'source-inventories/source-inventory.schema.json'
foreach ($inventoryPath in $InventoryPaths) {
    $inventoryInput = Read-JsonFile -Path ([IO.Path]::GetFullPath($inventoryPath)) -SchemaPath $inventorySchemaPath -Name 'Source inventory'
    $inventory = $inventoryInput.Value
    $sourceDefinitionId = [string]$inventory.sourceDefinitionId
    if ($inventoryHashes.Contains($sourceDefinitionId)) {
        throw "Workbench display received duplicate inventory sourceDefinitionId: $sourceDefinitionId"
    }
    if (-not $baseline.inventoryHashes.PSObject.Properties[$sourceDefinitionId] -or [string]$baseline.inventoryHashes.$sourceDefinitionId -cne $inventoryInput.Snapshot.Sha256) {
        throw "Workbench display inventory does not match the assessment set: $sourceDefinitionId"
    }
    Assert-SourceInventoryIntegrity -Inventory $inventory
    $inventoryHashes[$sourceDefinitionId] = $inventoryInput.Snapshot.Sha256
    foreach ($record in @($inventory.records)) {
        $sourceKey = $sourceDefinitionId + [char]0 + [string]$record.sourceId
        if ($inventoryRecords.ContainsKey($sourceKey)) {
            throw "Source inventories contain duplicate source identity: $sourceDefinitionId/$($record.sourceId)"
        }
        $inventoryRecords[$sourceKey] = $record
    }
}
$inventoryHashes = ConvertTo-OrdinalMap -Value $inventoryHashes
if (($inventoryHashes | ConvertTo-Json -Compress) -cne ((ConvertTo-OrdinalMap -Value $baseline.inventoryHashes) | ConvertTo-Json -Compress)) {
    throw 'Workbench display requires every assessment-set inventory lane exactly once'
}

$catalogRules = @{}
$catalogLocations = @{}
$catalogEvidence = @{}
$occupiedHostedIds = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
foreach ($evidence in @($catalog.evidence)) {
    $catalogEvidence[[string]$evidence.id] = $evidence
}
foreach ($rule in @($catalog.rules)) {
    $catalogRules[[string]$rule.id] = $rule
    $null = $occupiedHostedIds.Add([string]$rule.id)
}
foreach ($surface in @($catalog.surfaces)) {
    foreach ($section in @($surface.sections)) {
        foreach ($hostedId in @($section.ruleIds)) {
            if (-not $catalogRules.ContainsKey([string]$hostedId)) {
                throw "Hosted catalog surface references unknown rule ID: $hostedId"
            }
            if ([string]$catalogRules[[string]$hostedId].status -cne 'active') {
                throw "Hosted catalog surface references non-active rule ID: $hostedId"
            }
            if ($catalogLocations.ContainsKey([string]$hostedId)) {
                throw "Active Hosted rule is placed more than once: $hostedId"
            }
            $catalogLocations[[string]$hostedId] = [ordered]@{ category = [string]$surface.id; placement = [string]$section.heading }
        }
    }
}
foreach ($rule in @($catalog.rules)) {
    if ([string]$rule.status -ceq 'active' -and -not $catalogLocations.ContainsKey([string]$rule.id)) {
        throw "Active Hosted rule is not placed: $($rule.id)"
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
        $assessments[$key] = [ordered]@{ reference = $reference; assessment = $assessment; entry = $entry }
    }
}
if ($assessments.Count -eq 0) {
    throw 'Source assessment baseline contains no assessments to reconcile'
}

$forcedExcludedDraftKeys = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
foreach ($recommendation in @($draft.recommendations)) {
    $containsUnclassifiedSource = $false
    foreach ($reference in @($recommendation.memberAssessmentRefs)) {
        $assessmentKey = Get-AssessmentKey -Reference $reference
        if (-not $assessments.ContainsKey($assessmentKey)) {
            continue
        }
        $member = $assessments[$assessmentKey]
        $sourceKey = [string]$reference.sourceDefinitionId + [char]0 + [string]$reference.sourceId
        $sourceRecord = if ($inventoryRecords.ContainsKey($sourceKey)) {
            $inventoryRecords[$sourceKey]
        }
        elseif ($null -ne $member.entry.priorSourceEvidence) {
            $member.entry.priorSourceEvidence.sourceRecord
        }
        else {
            $null
        }
        if ($null -ne $sourceRecord -and $sourceRecord.PSObject.Properties['provenance'] -and [string]$sourceRecord.provenance -ceq 'unclassified') {
            $containsUnclassifiedSource = $true
            break
        }
    }
    if (-not $containsUnclassifiedSource) {
        continue
    }

    $draftKey = [string]$recommendation.draftKey
    $category = [string]$recommendation.category
    $placement = [string]$recommendation.placement
    $allowedFamilies = @($contract.idAllocation.families | Where-Object {
        [string]$_.category -ceq $category -and [string]$_.placement -ceq $placement
    } | Sort-Object -Property idFamily)
    if ($allowedFamilies.Count -eq 0) {
        throw "Recommendation $draftKey cannot be excluded because its category and placement have no allowlisted Hosted ID family"
    }
    $allowedFamilyIds = @($allowedFamilies | ForEach-Object { [string]$_.idFamily })
    $idFamily = if ($null -ne $recommendation.idFamily -and [string]$recommendation.idFamily -in $allowedFamilyIds) {
        [string]$recommendation.idFamily
    }
    elseif ($null -ne $recommendation.targetHostedId -and [string]$recommendation.targetHostedId -match '^(.*)-[0-9]{3}[A-Z]?$' -and [string]$Matches[1] -in $allowedFamilyIds) {
        [string]$Matches[1]
    }
    else {
        $allowedFamilyIds[0]
    }
    $recommendation.recommendedAction = 'exclude'
    $recommendation.targetHostedId = $null
    $recommendation.idFamily = $idFamily
    $recommendation.needsReview = $true
    $recommendation.rationale = ([string]$recommendation.rationale).TrimEnd() + ' Source provenance is unclassified, so this recommendation is excluded until maintainers classify it.'
    if ($category -ceq 'implementation' -and -not $recommendation.PSObject.Properties['implementationModels']) {
        $recommendation | Add-Member -NotePropertyName implementationModels -NotePropertyValue @('legacy', 'typed', 'framework')
    }
    $null = $forcedExcludedDraftKeys.Add($draftKey)
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
    $meaningCoverageKeys = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    foreach ($coverage in @($recommendation.memberMeaningCoverage)) {
        $coverageKey = Get-AssessmentKey -Reference $coverage.assessmentRef
        if (-not $memberKeys.Contains($coverageKey)) {
            throw "Recommendation $draftKey meaning coverage references a non-member assessment"
        }
        if (-not $meaningCoverageKeys.Add($coverageKey)) {
            throw "Recommendation $draftKey repeats member meaning coverage"
        }
    }
    if ($meaningCoverageKeys.Count -ne $memberKeys.Count) {
        throw "Recommendation $draftKey must explain how its rule text preserves every member meaning"
    }

    $category = [string]$recommendation.category
    $placement = [string]$recommendation.placement
    $targetHostedId = if ($null -eq $recommendation.targetHostedId) { $null } else { [string]$recommendation.targetHostedId }
    $idFamily = if ($null -eq $recommendation.idFamily) { $null } else { [string]$recommendation.idFamily }
    $action = [string]$recommendation.recommendedAction
    $targetExists = $null -ne $targetHostedId -and $catalogRules.ContainsKey($targetHostedId)
    if ($action -in @('update', 'no-change') -and -not $targetExists) {
        throw "Recommendation $draftKey requires one exact existing Hosted target"
    }
    if ($action -in @('update', 'no-change') -and $catalogRules.ContainsKey($targetHostedId) -and [string]$catalogRules[$targetHostedId].status -cne 'active') {
        throw "Recommendation $draftKey cannot target retired Hosted rule $targetHostedId without an explicit Restore decision"
    }
    if ($action -in @('add', 'exclude') -and ($null -ne $targetHostedId -or $null -eq $idFamily)) {
        throw "Recommendation $draftKey must use an allowlisted Hosted ID family without a target"
    }
    if ($action -eq 'defer' -and (($null -eq $targetHostedId) -eq ($null -eq $idFamily))) {
        throw "Deferred recommendation $draftKey must identify exactly one existing target or new Hosted ID family"
    }
    if ($null -ne $targetHostedId) {
        $location = $catalogLocations[$targetHostedId]
        $targetCategory = [string]$location.category
        $targetPlacement = [string]$location.placement
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
    if ($draftKeys.Count -ne 1 -or -not $draftRecommendations.ContainsKey([string]$draftKeys[0])) {
        throw 'Assessment coverage must reference one known recommendation'
    }
    if (-not $membershipByAssessment.ContainsKey($assessmentKey) -or [string]$membershipByAssessment[$assessmentKey] -cne [string]$draftKeys[0]) {
        throw 'Assessment coverage and recommendation membership do not match'
    }
    if ($forcedExcludedDraftKeys.Contains([string]$draftKeys[0])) {
        $coverage.disposition = 'excluded'
        $coverage.rationale = 'Source provenance is unclassified; the recommendation is excluded until maintainers classify it.'
    }
    $recommendationAction = [string]$draftRecommendations[[string]$draftKeys[0]].recommendedAction
    $disposition = [string]$coverage.disposition
    if (($disposition -ceq 'recommended' -and $recommendationAction -notin @('add', 'update', 'no-change')) -or
        ($disposition -ceq 'deferred' -and $recommendationAction -cne 'defer') -or
        ($disposition -ceq 'excluded' -and $recommendationAction -cne 'exclude')) {
        throw 'Assessment coverage disposition does not match its recommendation action'
    }
}
$missingCoverage = @($assessments.Keys | Where-Object { -not $coverageByAssessment.ContainsKey($_) })
if ($missingCoverage.Count -ne 0) {
    throw "Assessment reconciliation does not cover every assessment: $($missingCoverage.Count) missing"
}

$orderedDraftRecommendations = @($draftRecommendations.Values | Sort-Object -Property @{ Expression = { [string]$_.category } }, @{ Expression = { [string]$_.placement } }, @{ Expression = { [string]$_.idFamily } }, @{ Expression = { [string]$_.targetHostedId } }, @{ Expression = { [string]$_.title } }, @{ Expression = { [string]$_.draftKey } })
$duplicateTargetGroups = @($orderedDraftRecommendations |
    Where-Object { $null -ne $_.targetHostedId } |
    Group-Object -Property { [string]$_.targetHostedId } |
    Where-Object { $_.Count -gt 1 } |
    Sort-Object -Property Name)
if ($duplicateTargetGroups.Count -gt 0 -and -not $AllowConflicts) {
    throw "More than one recommendation owns Hosted ID $($duplicateTargetGroups[0].Name)"
}
$conflictDraftKeys = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
$conflictIdByDraftKey = @{}
$reconciliationConflicts = [Collections.Generic.List[object]]::new()
foreach ($targetGroup in $duplicateTargetGroups) {
    $targetHostedId = [string]$targetGroup.Name
    $conflictId = "duplicate-target:$targetHostedId"
    $conflictRecommendations = [Collections.Generic.List[object]]::new()
    foreach ($recommendation in @($targetGroup.Group | Sort-Object -Property draftKey)) {
        $draftKey = [string]$recommendation.draftKey
        $null = $conflictDraftKeys.Add($draftKey)
        $conflictIdByDraftKey[$draftKey] = $conflictId
        $memberAssessments = [Collections.Generic.List[object]]::new()
        foreach ($reference in @($recommendation.memberAssessmentRefs)) {
            $assessmentKey = Get-AssessmentKey -Reference $reference
            $member = $assessments[$assessmentKey].assessment
            $memberAssessments.Add([ordered]@{
                key = Get-DisplayAssessmentKey -Reference $reference
                sourceDefinitionId = [string]$reference.sourceDefinitionId
                sourceId = [string]$reference.sourceId
                contentSha256 = [string]$reference.contentSha256
                assessmentId = [string]$reference.assessmentId
                title = [string]$member.title
                sourceMeaning = [string]$member.sourceMeaning
                impactDescription = [string]$member.impactDescription
                relatedHostedCoverage = @($member.relatedHostedCoverage | ForEach-Object {
                    [ordered]@{
                        hostedRuleId = [string]$_.hostedRuleId
                        relationship = [string]$_.relationship
                        rationale = [string]$_.rationale
                    }
                })
            })
        }
        $conflictRecommendations.Add([ordered]@{
            draftKey = $draftKey
            action = [string]$recommendation.recommendedAction
            title = [string]$recommendation.title
            ruleText = [string]$recommendation.recommendedRuleText
            category = [string]$recommendation.category
            placement = [string]$recommendation.placement
            rationale = [string]$recommendation.rationale
            needsReview = $true
            memberAssessments = $memberAssessments.ToArray()
            memberMeaningCoverage = @($recommendation.memberMeaningCoverage | ForEach-Object {
                [ordered]@{
                    assessmentKey = Get-DisplayAssessmentKey -Reference $_.assessmentRef
                    rationale = [string]$_.rationale
                }
            } | Sort-Object -Property assessmentKey)
        })
    }
    $reconciliationConflicts.Add([ordered]@{
        id = $conflictId
        kind = 'duplicate-target-ownership'
        targetHostedId = $targetHostedId
        existingRuleText = [string]$catalogRules[$targetHostedId].text
        validationError = "More than one recommendation owns Hosted ID $targetHostedId"
        recommendations = $conflictRecommendations.ToArray()
    })
}
$activeDraftRecommendations = $orderedDraftRecommendations
$hostedIdByDraftKey = @{}
foreach ($recommendation in $activeDraftRecommendations) {
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
        } while ($occupiedHostedIds.Contains($hostedId) -and $nextNumber -le 1000)
        if ($occupiedHostedIds.Contains($hostedId)) {
            throw "No Hosted IDs remain available in family $family"
        }
    }
    if (-not $occupiedHostedIds.Add($hostedId) -and $null -eq $recommendation.targetHostedId) {
        throw "Hosted ID allocation produced a duplicate ID: $hostedId"
    }
    if ($hostedIdByDraftKey.Values -contains $hostedId -and -not ($AllowConflicts -and $conflictDraftKeys.Contains($draftKey))) {
        throw "More than one recommendation owns Hosted ID $hostedId"
    }
    $hostedIdByDraftKey[$draftKey] = $hostedId
}

$recommendationsByDraftKey = @{}
foreach ($recommendation in $activeDraftRecommendations) {
    $draftKey = [string]$recommendation.draftKey
    $hostedId = [string]$hostedIdByDraftKey[$draftKey]
    $currentText = ''
    $idState = 'tentative'
    if ($catalogRules.ContainsKey($hostedId)) {
        $currentText = [string]$catalogRules[$hostedId].text
        $idState = 'existing'
    }
    $recommendedText = [string]$recommendation.recommendedRuleText
    if ([string]$recommendation.recommendedAction -ceq 'no-change' -and $recommendedText -cne $currentText) {
        throw "No Change recommendation $draftKey must preserve the exact current Hosted rule text"
    }
    if ([string]$recommendation.recommendedAction -ceq 'update' -and $recommendedText -ceq $currentText) {
        throw "Update recommendation $draftKey must change the Hosted rule text"
    }
    $provenance = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    $evidenceIds = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    $sourceRelationships = [Collections.Generic.List[object]]::new()
    $categoryEvidenceId = switch ([string]$recommendation.category) {
        'implementation' { 'implementation-contract' }
        'testing' { 'testing-contract' }
        'documentation' { 'documentation-contract' }
        default { throw "Recommendation $draftKey uses an unsupported category" }
    }
    if (-not $catalogEvidence.ContainsKey($categoryEvidenceId)) {
        throw "Recommendation $draftKey requires missing catalog evidence $categoryEvidenceId"
    }
    $null = $evidenceIds.Add($categoryEvidenceId)
    foreach ($reference in @($recommendation.memberAssessmentRefs)) {
        $assessmentKey = Get-AssessmentKey -Reference $reference
        $member = $assessments[$assessmentKey]
        $sourceKey = [string]$reference.sourceDefinitionId + [char]0 + [string]$reference.sourceId
        $sourceRecord = if ($inventoryRecords.ContainsKey($sourceKey)) {
            $inventoryRecords[$sourceKey]
        }
        elseif ($null -ne $member.entry.priorSourceEvidence) {
            $member.entry.priorSourceEvidence.sourceRecord
        }
        else {
            throw "Recommendation $draftKey cannot resolve member source evidence"
        }
        $sourceProvenance = if ($sourceRecord.PSObject.Properties['provenance']) { [string]$sourceRecord.provenance } else { 'published-upstream-standard' }
        if ($sourceProvenance -ceq 'unclassified') {
            if ([string]$recommendation.recommendedAction -cne 'exclude') {
                throw "Recommendation $draftKey contains unclassified source provenance without deterministic exclusion"
            }
            $null = $provenance.Add('local-safeguard')
            if (-not $catalogEvidence.ContainsKey('hosted-architecture')) {
                throw "Recommendation $draftKey requires missing catalog evidence hosted-architecture"
            }
            $null = $evidenceIds.Add('hosted-architecture')
        }
        else {
            $null = $provenance.Add($sourceProvenance)
        }
        if ($sourceRecord.PSObject.Properties['evidence']) {
            foreach ($evidenceId in @($sourceRecord.evidence)) {
                if ($catalogEvidence.ContainsKey([string]$evidenceId)) {
                    $null = $evidenceIds.Add([string]$evidenceId)
                }
            }
        }
        if ($sourceProvenance -ceq 'local-safeguard') {
            if (-not $catalogEvidence.ContainsKey('hosted-architecture')) {
                throw "Recommendation $draftKey requires missing catalog evidence hosted-architecture"
            }
            $null = $evidenceIds.Add('hosted-architecture')
        }
        $sourceRelationships.Add([ordered]@{
            sourceDefinitionId = [string]$reference.sourceDefinitionId
            sourceId = [string]$reference.sourceId
            relationshipKind = 'included'
            rationale = "Assessment $($reference.assessmentId) is included in this recommendation."
        })
    }
    if ($provenance.Contains('confirmed-maintainer-convention')) {
        $maintainerEvidence = @($evidenceIds | Where-Object { [string]$catalogEvidence[[string]$_].type -ceq 'maintainer-confirmation' })
        if ($maintainerEvidence.Count -eq 0) {
            throw "Recommendation $draftKey has confirmed maintainer provenance without registered maintainer-confirmation evidence"
        }
    }
    $displayRecommendation = [ordered]@{
        action = [string]$recommendation.recommendedAction
        hostedId = $hostedId
        idState = $idState
        targetHostedId = if ($null -eq $recommendation.targetHostedId) { $null } else { [string]$recommendation.targetHostedId }
        ruleText = $recommendedText
        category = [string]$recommendation.category
        placement = [string]$recommendation.placement
        rationale = [string]$recommendation.rationale
        needsReview = [bool]$recommendation.needsReview
        assessmentKeys = @($recommendation.memberAssessmentRefs | ForEach-Object { Get-DisplayAssessmentKey -Reference $_ } | Sort-Object -CaseSensitive)
        memberMeaningCoverage = @($recommendation.memberMeaningCoverage | ForEach-Object {
            [ordered]@{
                assessmentKey = Get-DisplayAssessmentKey -Reference $_.assessmentRef
                rationale = [string]$_.rationale
            }
        } | Sort-Object -Property assessmentKey)
        guardedTokenDelta = (Get-GuardedTokens -Text $recommendedText) - (Get-GuardedTokens -Text $currentText)
        provenance = @($provenance | Sort-Object -CaseSensitive)
        evidenceIds = @($evidenceIds | Sort-Object -CaseSensitive)
        sourceRelationships = @($sourceRelationships | Sort-Object -Property @{ Expression = { [string]$_.sourceDefinitionId } }, @{ Expression = { [string]$_.sourceId } })
    }
    if ($recommendation.PSObject.Properties['implementationModels']) {
        $displayRecommendation['implementationModels'] = @($recommendation.implementationModels | Sort-Object -CaseSensitive)
    }
    $recommendationsByDraftKey[$draftKey] = $displayRecommendation
}

$candidates = [Collections.Generic.List[object]]::new()
foreach ($entry in @($baseline.entries)) {
    $sourceDefinitionId = [string]$entry.sourceRef.sourceDefinitionId
    $sourceKey = $sourceDefinitionId + [char]0 + [string]$entry.sourceRef.sourceId
    $sourceRecord = if ($inventoryRecords.ContainsKey($sourceKey)) {
        $inventoryRecords[$sourceKey]
    }
    elseif ($null -ne $entry.priorSourceEvidence -and [string]$entry.transition -ceq 'removed') {
        $entry.priorSourceEvidence.sourceRecord
    }
    else {
        throw "Workbench display cannot resolve source evidence: $sourceDefinitionId/$($entry.sourceRef.sourceId)"
    }
    if ([string]$sourceRecord.contentSha256 -cne [string]$entry.sourceRef.contentSha256) {
        throw "Workbench display source evidence does not match the assessment set: $sourceDefinitionId/$($entry.sourceRef.sourceId)"
    }
    $lane = switch ($sourceDefinitionId) {
        'contributor-guidance' { 'contributor' }
        'interactive-toolkit' { 'interactive' }
        'maintainer-proposals' { 'maintainer' }
        default { throw "Unsupported source lane: $sourceDefinitionId" }
    }
    $displaySource = [ordered]@{
        lane = $lane
        id = [string]$sourceRecord.sourceId
        title = [string]$sourceRecord.title
        location = [string]$sourceRecord.location
        text = [string]$sourceRecord.content
        contentSha256 = [string]$sourceRecord.contentSha256
        provenance = if ($sourceRecord.PSObject.Properties['provenance']) { [string]$sourceRecord.provenance } else { 'published-upstream-standard' }
        transition = [string]$entry.transition
    }
    if ($null -ne $entry.priorSourceEvidence -and [string]$entry.priorSourceEvidence.sourceRecord.content -cne [string]$sourceRecord.content) {
        $displaySource['priorText'] = [string]$entry.priorSourceEvidence.sourceRecord.content
    }
    if ($sourceRecord.PSObject.Properties['surface']) {
        $displaySource['surface'] = [string]$sourceRecord.surface
    }
    if ($sourceRecord.PSObject.Properties['rationale']) {
        $displaySource['rationale'] = [string]$sourceRecord.rationale
    }
    if ($sourceRecord.PSObject.Properties['evidence']) {
        $displaySource['evidence'] = @($sourceRecord.evidence)
    }
    if ($sourceRecord.PSObject.Properties['sourceIds']) {
        $displaySource['sourceIds'] = @($sourceRecord.sourceIds)
    }
    if ($sourceRecord.PSObject.Properties['resolvedCommit']) {
        $displaySource['revision'] = [ordered]@{ resolvedCommit = [string]$sourceRecord.resolvedCommit }
    }

    foreach ($assessment in @($entry.assessments)) {
        $reference = [ordered]@{
            sourceDefinitionId = $sourceDefinitionId
            sourceId = [string]$entry.sourceRef.sourceId
            contentSha256 = [string]$entry.sourceRef.contentSha256
            assessmentId = [string]$assessment.assessmentId
        }
        $assessmentKey = Get-AssessmentKey -Reference $reference
        $coverage = $coverageByAssessment[$assessmentKey]
        $draftKey = [string]$coverage.recommendationDraftKeys[0]
        $recommendation = $recommendationsByDraftKey[$draftKey]
        $forcedExcluded = $forcedExcludedDraftKeys.Contains($draftKey)
        $displayAssessment = [ordered]@{
            id = [string]$assessment.assessmentId
            title = [string]$assessment.title
            sourceMeaning = [string]$assessment.sourceMeaning
            impactDescription = [string]$assessment.impactDescription
            hostedApplicable = [bool]$assessment.hostedApplicable -and -not $forcedExcluded
            applicabilityRationale = if ($forcedExcluded) { ([string]$assessment.applicabilityRationale).TrimEnd() + ' Source provenance is unclassified, so a maintainer must contest this exclusion before promotion.' } else { [string]$assessment.applicabilityRationale }
            selectionFactors = $assessment.selectionFactors
            selectionRationale = [string]$assessment.selectionRationale
            confidence = $assessment.assessmentConfidence
            affectedSurfaces = @($assessment.affectedSurfaces)
            existingCoverage = $assessment.existingCoverage
            relatedHostedCoverage = @($assessment.relatedHostedCoverage)
            evaluatedAt = [string]$assessment.assessmentProvenance.assessedAt
            evaluator = [string]$assessment.assessmentProvenance.assessmentEvaluator.model
        }
        if (-not $displaySource.Contains('surface') -and @($assessment.affectedSurfaces).Count -eq 1 -and [string]$assessment.affectedSurfaces[0] -in @('implementation', 'testing', 'documentation')) {
            $displaySource['surface'] = [string]$assessment.affectedSurfaces[0]
        }
        $displayCandidate = [ordered]@{
            source = $displaySource
            assessment = $displayAssessment
            reviewState = [string]$coverage.disposition
            recommendation = $recommendation
        }
        if ($conflictIdByDraftKey.ContainsKey($draftKey)) {
            $displayCandidate['conflictId'] = [string]$conflictIdByDraftKey[$draftKey]
            $displayCandidate['conflictDraftKey'] = $draftKey
        }
        $candidates.Add($displayCandidate)
    }
}

$fingerprintBuilder = [Text.StringBuilder]::new()
$null = $fingerprintBuilder.Append($catalogInput.Snapshot.Sha256).Append([char]0)
foreach ($inventoryHash in $inventoryHashes.GetEnumerator()) {
    $null = $fingerprintBuilder.Append([string]$inventoryHash.Key).Append([char]0).Append([string]$inventoryHash.Value).Append([char]0)
}
$inputFingerprint = Get-Sha256 -Content $fingerprintBuilder.ToString()

$catalogProjection = @($catalog.rules | ForEach-Object {
    $hostedId = [string]$_.id
    $placements = [Collections.Generic.List[object]]::new()
    if ($catalogLocations.ContainsKey($hostedId)) {
        $placements.Add([ordered]@{
            surfaceId = [string]$catalogLocations[$hostedId].category
            sectionHeading = [string]$catalogLocations[$hostedId].placement
        })
    }
    $projectedRule = [ordered]@{
        id = $hostedId
        origin = [string]$_.origin
        status = [string]$_.status
        text = [string]$_.text
        provenance = @($_.provenance)
        evidenceIds = @($_.evidenceIds)
        placements = $placements.ToArray()
    }
    foreach ($propertyName in @('implementationModels', 'documentationGap', 'selectionFactors', 'selectionRationale')) {
        if ($_.PSObject.Properties[$propertyName]) {
            $projectedRule[$propertyName] = $_.$propertyName
        }
    }
    if ([string]$_.status -ceq 'retired') {
        $projectedRule['retirementReason'] = [string]$_.retirementReason
        $projectedRule['lastPlacement'] = $_.lastPlacement
    }
    $projectedRule
})

$display = [ordered]@{
    '$schema' = 'workbench-display-v4.schema.json'
    schemaVersion = 4
    kind = 'hosted-rule-workbench-display'
    generatedAt = ConvertTo-UtcTimestamp -Value $GeneratedAt
    readOnly = $true
    inputFingerprint = $inputFingerprint
    reconciliation = [ordered]@{
        status = if ($reconciliationConflicts.Count -gt 0) { 'blocked' } else { 'ready' }
        conflicts = $reconciliationConflicts.ToArray()
    }
    candidates = @($candidates | Sort-Object -Property @{ Expression = { [string]$_.source.lane + [char]0 + [string]$_.source.id + [char]0 + [string]$_.assessment.id } })
    catalog = [ordered]@{
        contentSha256 = $catalogInput.Snapshot.Sha256
        rules = $catalogProjection
    }
    guidanceCapacity = $guidanceCapacityInput.Value
}
$displayJson = $display | ConvertTo-Json -Depth 40
$schemaErrors = @()
$displayValid = $displayJson | Test-Json -SchemaFile (Join-Path $reconciliationRoot 'workbench-display-v4.schema.json') -ErrorAction SilentlyContinue -ErrorVariable schemaErrors
if (-not $displayValid) {
    $schemaDetail = @($schemaErrors | ForEach-Object { $_.Exception.Message } | Sort-Object -Unique) -join '; '
    throw "Workbench display does not satisfy its schema: $schemaDetail"
}
$outputSnapshot = Write-JsonSnapshot -Path $resolvedOutputPath -Value $display

$result = [ordered]@{
    status = if ($reconciliationConflicts.Count -gt 0) { 'blocked' } else { 'passed' }
    outputPath = $resolvedOutputPath
    candidateCount = $display.candidates.Count
    recommendationCount = $recommendationsByDraftKey.Count
    conflictCount = $reconciliationConflicts.Count
    displaySha256 = $outputSnapshot.Sha256
}
if ($OutputFormat -eq 'Json') {
    $result | ConvertTo-Json -Depth 5
}
else {
    Write-Output "Workbench display generated with status $($result.status): $($result.candidateCount) candidates, $($result.recommendationCount) recommendations, $($result.conflictCount) conflicts"
    Write-Output "Output: $($result.outputPath)"
    Write-Output "Display SHA-256: $($result.displaySha256)"
}
