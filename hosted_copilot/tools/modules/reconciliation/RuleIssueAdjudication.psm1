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
    $inputRelationshipIds = @($Component.relationships | ForEach-Object { [string]$_.id })
    $decisionIds = @($Draft.relationshipDecisions | ForEach-Object { [string]$_.relationshipId })
    if ($inputRelationshipIds.Count -ne $decisionIds.Count -or @($decisionIds | Where-Object { $_ -cnotin $inputRelationshipIds }).Count -gt 0 -or @($decisionIds | Sort-Object -Unique).Count -ne $decisionIds.Count) {
        throw 'Adjudication must decide every input relationship exactly once'
    }
    $isSavedEdit = $null -ne $Component.PSObject.Properties['editContext']
    $editProposals = @{}
    if ($isSavedEdit) {
        $context = $Component.editContext
        $baselineHash = [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData([Text.Encoding]::UTF8.GetBytes([string]$context.baselineText))).ToLowerInvariant()
        if ($baselineHash -cne [string]$context.baselineSha256) { throw 'Saved-edit baseline hash is invalid' }
        foreach ($proposal in @($context.proposals)) {
            $key = [string]$proposal.candidateKey
            if ($editProposals.ContainsKey($key)) { throw 'Saved-edit proposal identity is duplicated' }
            $inputOperations = @($Component.operations | Where-Object { [string]$_.candidateKey -ceq $key })
            if ($inputOperations.Count -ne 1 -or [string]$inputOperations[0].proposedText -cne [string]$proposal.proposedText) { throw 'Saved-edit proposal does not match its candidate operation' }
            $editProposals[$key] = $proposal
        }
        if ($editProposals.Count -ne @($Component.operations).Count -or -not $editProposals.ContainsKey([string]$context.candidateKey)) { throw 'Saved-edit proposals must account for every candidate operation' }
        $edited = $editProposals[[string]$context.candidateKey]
        if ([string]$edited.baselineText -cne [string]$context.baselineText) { throw 'Saved-edit baseline disagrees with its candidate baseline' }
        if ($null -ne $context.appendText -and [string]$edited.proposedText -cne ([string]$context.baselineText + [string]$context.appendText)) { throw 'Saved-edit addition does not reconstruct the proposal' }
        if ($null -eq $Draft.PSObject.Properties['scopeReview'] -or $null -eq $Draft.PSObject.Properties['evaluationContextSha256'] -or [string]$Draft.evaluationContextSha256 -cne [string]$context.evaluationContextSha256) { throw 'Saved-edit adjudication has missing or stale evaluation context' }
        if (-not ([string]$context.baselineText).Contains([string]$Draft.scopeReview.baselineQuote, [StringComparison]::Ordinal)) { throw 'Baseline quotation is not an exact span of the supplied edit baseline' }
        if (-not ([string]$edited.proposedText).Contains([string]$Draft.scopeReview.proposalQuote, [StringComparison]::Ordinal)) { throw 'Proposal quotation is not an exact span of the saved proposal' }
        $editedRuleId = [string]@($Component.operations | Where-Object { [string]$_.candidateKey -ceq [string]$context.candidateKey })[0].ruleId
        $ownerId = $Draft.scopeReview.ownerRuleId
        if ([string]$Draft.scopeReview.disposition -ceq 'route-to-existing-rule') {
            $owners = @($Component.rules | Where-Object { [string]$_.id -ceq [string]$ownerId -and [string]$_.status -in @('active', 'protected') })
            if ($owners.Count -ne 1 -or [string]$ownerId -ceq $editedRuleId) { throw 'Saved-edit scope owner must identify a distinct supplied existing rule' }
        }
        elseif ($null -ne $ownerId -and -not ([string]$Draft.scopeReview.disposition -ceq 'within-scope' -and [string]$ownerId -ceq $editedRuleId)) { throw 'Saved-edit scope disposition cannot assign a foreign owner' }
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
        if ($isSavedEdit) {
            $relationship = $relationshipById[[string]$decision.relationshipId]
            foreach ($pair in @(@{ id = [string]$relationship.sourceRuleId; field = 'sourceQuote' }, @{ id = [string]$relationship.relatedRuleId; field = 'relatedQuote' })) {
                $rule = @($Component.rules | Where-Object { [string]$_.id -ceq $pair.id })[0]
                if ($null -eq $decision.PSObject.Properties[$pair.field] -or [string]::IsNullOrWhiteSpace([string]$decision.($pair.field)) -or -not ([string]$rule.text).Contains([string]$decision.($pair.field), [StringComparison]::Ordinal)) { throw 'Saved-edit relationship quotation is not an exact span of its supplied rule' }
            }
        }
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
            if ($isSavedEdit) {
                $proposal = $editProposals[$candidateKey]
                if ([string]$operation.action -ceq 'retire') { throw 'Saved edits cannot introduce whole-rule retirement or consolidation' }
                if ($null -eq $operation.PSObject.Properties['textSource'] -or [string]$operation.textSource -notin @('baseline', 'proposal')) { throw 'Saved-edit operation is missing text provenance' }
                $expectedText = if ([string]$operation.textSource -ceq 'baseline') { [string]$proposal.baselineText } else { [string]$proposal.proposedText }
                if ([string]$operation.proposedText -cne $expectedText) { throw 'Saved-edit operation must preserve the complete supplied baseline or proposal' }
                if ((@($operation.retireHostedRuleIds | Sort-Object -CaseSensitive) -join "`0") -cne (@($proposal.retireHostedRuleIds | Sort-Object -CaseSensitive) -join "`0")) { throw 'Saved-edit operation cannot change the supplied retirement set' }
                if ([string]$candidateKey -ceq [string]$Component.editContext.candidateKey -and [string]$Draft.scopeReview.disposition -in @('route-to-existing-rule', 'suggest-new-rule') -and $null -ne $Component.editContext.appendText -and [string]$operation.proposedText -cne [string]$proposal.baselineText) { throw 'Out-of-scope additions must preserve the complete edit baseline' }
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
    if ($materialDecisionIds.Count -ne $usedRelationshipIds.Count -or @($materialDecisionIds | Where-Object { -not $usedRelationshipIds.Contains($_) }).Count -gt 0) {
        throw 'Every material relationship must appear in exactly one adjudicated issue'
    }
}

function ConvertTo-WorkbenchRuleIssues {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][object]$Component,
        [Parameter(Mandatory = $true)][object]$Draft
    )

    Test-RuleIssueAdjudicationDraft -Component $Component -Draft $Draft
    $rules = @{}
    foreach ($rule in @($Component.rules)) { $rules[[string]$rule.id] = $rule }
    $relationships = @{}
    foreach ($relationship in @($Component.relationships)) { $relationships[[string]$relationship.id] = $relationship }
    $decisions = @{}
    foreach ($decision in @($Draft.relationshipDecisions)) { $decisions[[string]$decision.relationshipId] = $decision }
    $kinds = @{ equivalent = 'duplicate'; 'partial-overlap' = 'overlap'; 'assessment-extends-hosted' = 'overlap'; 'assessment-narrows-hosted' = 'overlap'; conflicts = 'contradiction' }
    $labels = @{ 'protected-integrity' = 'Protected Integrity'; 'protected-conflict' = 'Protected Conflict'; 'protected-coverage' = 'Protected Coverage'; contradiction = 'Contradiction'; duplicate = 'Duplicate'; overlap = 'Overlap' }
    foreach ($issue in @($Draft.issues)) {
        $protectedIds = @($issue.ruleIds | Where-Object { [string]$rules[[string]$_].status -ceq 'protected' } | Sort-Object -CaseSensitive)
        $identity = @($issue.relationshipIds | Sort-Object -CaseSensitive)[0]
        $id = if ($protectedIds.Count -gt 0) { 'protected:' + ($protectedIds -join '+') + ':' + $identity } else { 'relationship:' + [string]$issue.anchorRuleId + ':' + $identity }
        $dispositions = @{}
        foreach ($entry in @($issue.ruleDispositions)) { $dispositions[[string]$entry.ruleId] = [string]$entry.disposition }
        $finalRules = @($issue.ruleIds | ForEach-Object {
            $rule = $rules[[string]$_]
            [ordered]@{ id = [string]$rule.id; status = [string]$rule.status; disposition = $dispositions[[string]$rule.id]; text = [string]$rule.text; candidateKeys = @($rule.candidateKeys) }
        })
        $finalRelationships = @($issue.relationshipIds | ForEach-Object {
            $relationship = $relationships[[string]$_]
            $decision = $decisions[[string]$_]
            [ordered]@{ sourceRuleId = [string]$relationship.sourceRuleId; relatedRuleId = [string]$relationship.relatedRuleId; relationship = [string]$decision.relationship; kind = $kinds[[string]$decision.relationship]; rationale = [string]$decision.rationale; candidateKey = [string]$relationship.candidateKey }
        } | Sort-Object -Property sourceRuleId, relatedRuleId, relationship, candidateKey)
        $operations = @($issue.recommendedMaintainerAction.operations | ForEach-Object {
            $operation = $_
            [ordered]@{ candidateKey = [string]$operation.candidateKey; ruleId = [string]$operation.ruleId; action = [string]$operation.action; proposedText = [string]$operation.proposedText; retireHostedRuleIds = @($operation.retireHostedRuleIds | Where-Object { [string]$_ -cne [string]$operation.ruleId } | Sort-Object -CaseSensitive -Unique) }
        } | Sort-Object -Property candidateKey)
        $candidateKeys = @($finalRules.candidateKeys + $finalRelationships.candidateKey + @($operations | ForEach-Object { $_.candidateKey }) | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) } | Sort-Object -CaseSensitive -Unique)
        [ordered]@{
            id = $id; classification = [string]$issue.classification; label = $labels[[string]$issue.classification]
            title = [string]$issue.title; bannerTitle = [string]$issue.bannerTitle; bannerMessage = [string]$issue.bannerMessage
            blocking = [bool]$issue.blocking; ruleIds = @($issue.ruleIds); protectedRuleIds = $protectedIds
            candidateKeys = $candidateKeys; rules = $finalRules; relationships = $finalRelationships
            assessmentSummary = [string]$issue.assessmentSummary; wording = $issue.wording
            recommendedMaintainerAction = [ordered]@{ summary = [string]$issue.recommendedMaintainerAction.summary; operations = $operations }
        }
    }
}

Export-ModuleMember -Function 'Test-RuleIssueAdjudicationDraft', 'ConvertTo-WorkbenchRuleIssues'
