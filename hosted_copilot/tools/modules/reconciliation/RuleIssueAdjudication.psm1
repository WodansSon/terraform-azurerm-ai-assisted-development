Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Test-RuleIssueAdjudicationDraft {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][object]$Component,
        [Parameter(Mandatory = $true)][object]$Draft
    )

    if ([string]$Draft.componentId -cne [string]$Component.componentId) {
        throw 'Adjudication changed the component ID'
    }
    $inputRelationshipIds = @($Component.relationships.id | Sort-Object -CaseSensitive)
    $decisionIds = @($Draft.relationshipDecisions.relationshipId | Sort-Object -CaseSensitive)
    if (@(Compare-Object $inputRelationshipIds $decisionIds -SyncWindow 0).Count -ne 0 -or @($decisionIds | Sort-Object -Unique).Count -ne $decisionIds.Count) {
        throw 'Adjudication must decide every input relationship exactly once'
    }
    $knownRuleIds = [Collections.Generic.HashSet[string]]::new([string[]]@($Component.rules.id), [StringComparer]::Ordinal)
    $knownOperationKeys = [Collections.Generic.HashSet[string]]::new([string[]]@($Component.operations.candidateKey), [StringComparer]::Ordinal)
    $relationshipById = @{}
    foreach ($relationship in @($Component.relationships)) {
        $relationshipById[[string]$relationship.id] = $relationship
    }
    $decisionById = @{}
    foreach ($decision in @($Draft.relationshipDecisions)) {
        $decisionById[[string]$decision.relationshipId] = $decision
    }
    $usedRelationshipIds = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    foreach ($issue in @($Draft.issues)) {
        if (-not $knownRuleIds.Contains([string]$issue.anchorRuleId)) {
            throw 'Adjudication issue anchor must identify a known component rule'
        }
        $issueRuleIds = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
        foreach ($ruleId in @($issue.ruleIds)) {
            if (-not $knownRuleIds.Contains([string]$ruleId) -or -not $issueRuleIds.Add([string]$ruleId)) {
                throw 'Adjudication issue contains an unknown or duplicate rule ID'
            }
        }
        if (-not $issueRuleIds.Contains([string]$issue.anchorRuleId)) {
            throw 'Adjudication issue does not include its anchor rule'
        }
        $displayTextFields = [ordered]@{
            title = [string]$issue.title
            bannerTitle = [string]$issue.bannerTitle
            bannerMessage = [string]$issue.bannerMessage
            assessmentSummary = [string]$issue.assessmentSummary
            recommendedMaintainerAction = [string]$issue.recommendedMaintainerAction.summary
        }
        if ([string]$issue.wording.status -ceq 'unresolved') {
            $displayTextFields['wordingReason'] = [string]$issue.wording.reason
        }
        foreach ($field in $displayTextFields.GetEnumerator()) {
            foreach ($match in [regex]::Matches([string]$field.Value, '\b[A-Z]+(?:-[A-Z0-9]+)+-[0-9]{3}[A-Z]?\b')) {
                if (-not $issueRuleIds.Contains([string]$match.Value)) {
                    throw "Adjudication issue $($field.Key) references non-member rule ID $($match.Value)"
                }
            }
        }
        $dispositionRuleIds = @($issue.ruleDispositions.ruleId | Sort-Object -CaseSensitive)
        if (@(Compare-Object @($issue.ruleIds | Sort-Object -CaseSensitive) $dispositionRuleIds -SyncWindow 0).Count -ne 0 -or @($dispositionRuleIds | Sort-Object -Unique).Count -ne $dispositionRuleIds.Count) {
            throw 'Adjudication issue must assign one disposition to every member rule'
        }
        foreach ($relationshipId in @($issue.relationshipIds)) {
            if (-not $relationshipById.ContainsKey([string]$relationshipId) -or -not $usedRelationshipIds.Add([string]$relationshipId)) {
                throw 'Adjudication issue contains an unknown or duplicate relationship ID'
            }
            $decision = $decisionById[[string]$relationshipId]
            if ([string]$decision.disposition -cne 'issue') {
                throw 'Adjudication issue references an independent relationship'
            }
            $relationship = $relationshipById[[string]$relationshipId]
            if (-not $issueRuleIds.Contains([string]$relationship.sourceRuleId) -or -not $issueRuleIds.Contains([string]$relationship.relatedRuleId)) {
                throw 'Adjudication issue omits a relationship member rule'
            }
        }
        $dispositionByRuleId = @{}
        foreach ($entry in @($issue.ruleDispositions)) {
            $dispositionByRuleId[[string]$entry.ruleId] = [string]$entry.disposition
        }
        $candidateOperationByKey = @{}
        foreach ($operation in @($Component.operations)) {
            $candidateOperationByKey[[string]$operation.candidateKey] = $operation
        }
        $selectedOperations = @($issue.recommendedMaintainerAction.operations)
        $selectedCandidateKeys = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
        foreach ($operation in $selectedOperations) {
            $candidateKey = [string]$operation.candidateKey
            if (-not $knownOperationKeys.Contains($candidateKey) -or -not $selectedCandidateKeys.Add($candidateKey)) {
                throw 'Adjudication operation contains an unknown or duplicate candidate key'
            }
            $candidateOperation = $candidateOperationByKey[$candidateKey]
            if ([string]$operation.ruleId -cne [string]$candidateOperation.ruleId -or -not $issueRuleIds.Contains([string]$operation.ruleId)) {
                throw 'Adjudication operation changed candidate-owned rule identity or references a non-member rule'
            }
            $operationRule = @($Component.rules | Where-Object { [string]$_.id -ceq [string]$operation.ruleId })[0]
            $allowedActions = switch ([string]$operationRule.status) {
                'active' { @('update', 'retire', 'defer') }
                'retired' { @('restore', 'defer') }
                'proposed' { @('add', 'exclude', 'defer') }
                default { @() }
            }
            if ([string]$operation.action -notin $allowedActions) {
                throw "Adjudication action $($operation.action) is invalid for $($operation.ruleId) with status $($operationRule.status)"
            }
            foreach ($retireRuleId in @($operation.retireHostedRuleIds)) {
                $retireRule = @($Component.rules | Where-Object { [string]$_.id -ceq [string]$retireRuleId })[0]
                if ($null -eq $retireRule -or [string]$retireRule.status -cne 'active') {
                    throw 'Adjudication can retire only known active member rules'
                }
            }
            $expectedDisposition = switch ([string]$operation.action) {
                'add' { 'promote' }
                'restore' { 'promote' }
                'update' { 'replace' }
                'retire' { 'retire' }
                'exclude' { 'exclude' }
                'defer' { 'defer' }
            }
            if ([string]$dispositionByRuleId[[string]$operation.ruleId] -cne $expectedDisposition) {
                throw "Adjudication disposition for $($operation.ruleId) does not match selected action $($operation.action)"
            }
        }
        $protectedRules = @($Component.rules | Where-Object { [string]$_.id -in @($issue.ruleIds) -and [string]$_.status -ceq 'protected' })
        $protectedRuleIds = @($protectedRules | ForEach-Object { [string]$_.id })
        $protectedDispositions = @($issue.ruleDispositions | Where-Object { [string]$_.ruleId -in $protectedRuleIds -and [string]$_.disposition -cne 'keep' })
        if ($protectedDispositions.Count -gt 0) {
            throw 'Protected rules must have keep disposition'
        }
        if ($protectedRules.Count -gt 1) {
            if ([string]$issue.classification -cne 'protected-integrity' -or -not [bool]$issue.blocking -or [string]$issue.wording.status -cne 'unresolved') {
                throw 'Multiple protected rules require blocking protected-integrity adjudication with unresolved wording'
            }
        }
        elseif ($protectedRules.Count -eq 1) {
            if ([string]$issue.classification -notin @('protected-conflict', 'protected-coverage') -or [bool]$issue.blocking) {
                throw 'Single-protected-rule adjudication has an invalid classification or blocking state'
            }
            if ([string]$issue.wording.status -cne 'canonical' -or [string]$issue.wording.sourceRuleId -cne [string]$protectedRules[0].id -or [string]$issue.wording.text -cne [string]$protectedRules[0].text) {
                throw 'Single-protected-rule adjudication must preserve exact canonical wording'
            }
        }
        elseif ([string]$issue.classification -like 'protected-*') {
            throw 'Non-protected adjudication cannot use a protected classification'
        }
        if ([string]$issue.wording.status -ceq 'selected') {
            $matchingOperations = @($selectedOperations | Where-Object { [string]$_.ruleId -ceq [string]$issue.wording.sourceRuleId -and [string]$_.action -in @('add', 'update', 'restore') -and [string]$_.proposedText -ceq [string]$issue.wording.text })
            $member = @($Component.rules | Where-Object { [string]$_.id -ceq [string]$issue.wording.sourceRuleId })[0]
            $memberSuppliesWording = $null -ne $member -and [string]$member.text -ceq [string]$issue.wording.text -and [string]$dispositionByRuleId[[string]$member.id] -in @('keep', 'promote')
            if ($matchingOperations.Count -ne 1 -and -not $memberSuppliesWording) {
                throw 'Selected adjudication wording must match one final mutation or one exact retained member'
            }
            if ([string]$issue.wording.presentation -ceq 'member' -and -not $memberSuppliesWording) {
                throw 'Member-presented wording must match one retained or promoted member exactly'
            }
        }
        $issueRelationshipKinds = @($issue.relationshipIds | ForEach-Object { [string]$decisionById[[string]$_].relationship })
        $expectedClassification = if ($protectedRules.Count -gt 1) {
            'protected-integrity'
        }
        elseif ($protectedRules.Count -eq 1 -and 'conflicts' -in $issueRelationshipKinds) {
            'protected-conflict'
        }
        elseif ($protectedRules.Count -eq 1) {
            'protected-coverage'
        }
        elseif ('conflicts' -in $issueRelationshipKinds) {
            'contradiction'
        }
        elseif (@($issueRelationshipKinds | Where-Object { $_ -cne 'equivalent' }).Count -eq 0) {
            'duplicate'
        }
        else {
            'overlap'
        }
        if ([string]$issue.classification -cne $expectedClassification) {
            throw "Adjudication classification $($issue.classification) does not match relationship evidence $expectedClassification"
        }
    }
    $materialDecisionIds = @($Draft.relationshipDecisions | Where-Object { [string]$_.disposition -ceq 'issue' } | ForEach-Object { [string]$_.relationshipId } | Sort-Object -CaseSensitive)
    if (@(Compare-Object $materialDecisionIds @($usedRelationshipIds | Sort-Object -CaseSensitive) -SyncWindow 0).Count -ne 0) {
        throw 'Every material relationship must appear in exactly one adjudicated issue'
    }
}

Export-ModuleMember -Function 'Test-RuleIssueAdjudicationDraft'
