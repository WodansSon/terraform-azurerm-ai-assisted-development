Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-SavedRuleAssessmentProposals {
    param([object]$Component)

    @($Component.editContext.proposals | Where-Object {
        $_.candidateKey -ceq $Component.editContext.candidateKey -or
        ([string]$_.proposedText).Replace("`r`n", "`n") -cne ([string]$_.baselineText).Replace("`r`n", "`n")
    })
}

function Test-SavedRuleScopeReview {
    param([object]$Component, [string]$CandidateKey, [object]$ScopeReview)

    $proposals = @($Component.editContext.proposals | Where-Object candidateKey -CEQ $CandidateKey)
    $operations = @($Component.operations | Where-Object candidateKey -CEQ $CandidateKey)
    if ($proposals.Count -ne 1 -or $operations.Count -ne 1) { throw 'Saved-edit scope has unknown candidate ownership' }
    $proposal = $proposals[0]
    if ($null -eq $ScopeReview.PSObject.Properties['wordingStatus'] -or [string]$ScopeReview.wordingStatus -cnotin @('acceptable', 'needs-review') -or
        $null -eq $ScopeReview.PSObject.Properties['wordingRationale'] -or [string]::IsNullOrWhiteSpace([string]$ScopeReview.wordingRationale)) {
        throw 'Saved-edit scope review requires an explicit wording status and rationale'
    }
    if ([string]::IsNullOrWhiteSpace([string]$ScopeReview.baselineQuote) -or -not ([string]$proposal.baselineText).Contains([string]$ScopeReview.baselineQuote, [StringComparison]::Ordinal)) { throw 'Baseline quotation is not an exact span of the supplied edit baseline' }
    if ([string]::IsNullOrWhiteSpace([string]$ScopeReview.proposalQuote) -or -not ([string]$proposal.proposedText).Contains([string]$ScopeReview.proposalQuote, [StringComparison]::Ordinal)) { throw 'Proposal quotation is not an exact span of the saved proposal' }
    $ruleId = [string]$operations[0].ruleId
    $ownerId = $ScopeReview.ownerRuleId
    if ([string]$ScopeReview.disposition -ceq 'route-to-existing-rule') {
        $owners = @($Component.rules | Where-Object { [string]$_.id -ceq [string]$ownerId -and [string]$_.status -in @('active', 'protected') })
        if ($owners.Count -ne 1 -or [string]$ownerId -ceq $ruleId) { throw 'Saved-edit scope owner must identify a distinct supplied existing rule' }
    }
    elseif ($null -ne $ownerId -and -not ([string]$ScopeReview.disposition -ceq 'within-scope' -and [string]$ownerId -ceq $ruleId)) { throw 'Saved-edit scope disposition cannot assign a foreign owner' }
}

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
    $phase = if ($null -ne $Component.PSObject.Properties['evaluationPhase']) { [string]$Component.evaluationPhase } else { 'complete' }
    $draftPhase = if ($null -ne $Draft.PSObject.Properties['evaluationPhase']) { [string]$Draft.evaluationPhase } else { 'complete' }
    if ($draftPhase -cne $phase) { throw 'Adjudication changed the evaluation phase' }
    if ($phase -ceq 'relationships') {
        if ([string]$Draft.evaluationContextSha256 -cne [string]$Component.evaluationContextSha256 -or @($Draft.issues).Count -ne 0 -or $null -ne $Draft.PSObject.Properties['assessments'] -or $null -ne $Draft.PSObject.Properties['scopeReview']) {
            throw 'Relationship routing must preserve its context and return only relationship decisions'
        }
        foreach ($decision in @($Draft.relationshipDecisions)) {
            $relationship = @($Component.relationships | Where-Object id -CEQ $decision.relationshipId)[0]
            foreach ($pair in @(@{ id = $relationship.sourceRuleId; field = 'sourceQuote' }, @{ id = $relationship.relatedRuleId; field = 'relatedQuote' })) {
                $rule = @($Component.rules | Where-Object id -CEQ $pair.id)[0]
                if ($null -eq $decision.PSObject.Properties[$pair.field] -or [string]::IsNullOrWhiteSpace([string]$decision.($pair.field)) -or -not ([string]$rule.text).Contains([string]$decision.($pair.field), [StringComparison]::Ordinal)) {
                    throw 'Relationship routing requires exact quotations from both supplied rules'
                }
            }
        }
        return
    }
    if ($phase -in @('scope', 'assessment') -and (@($Draft.relationshipDecisions).Count -ne 0 -or @($Draft.issues).Count -ne 0)) { throw 'Scope and assessment batches cannot publish relationship or issue decisions' }
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
            $proposalHash = [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData([Text.Encoding]::UTF8.GetBytes([string]$proposal.proposedText))).ToLowerInvariant()
            if ($proposalHash -cne [string]$proposal.ruleTextSha256) { throw 'Saved-edit proposal hash is invalid' }
            $editProposals[$key] = $proposal
        }
        if ($editProposals.Count -ne @($Component.operations).Count -or -not $editProposals.ContainsKey([string]$context.candidateKey)) { throw 'Saved-edit proposals must account for every candidate operation' }
        $edited = $editProposals[[string]$context.candidateKey]
        if ([string]$edited.baselineText -cne [string]$context.baselineText) { throw 'Saved-edit baseline disagrees with its candidate baseline' }
        if ($null -ne $context.appendText -and [string]$edited.proposedText -cne ([string]$context.baselineText + [string]$context.appendText)) { throw 'Saved-edit addition does not reconstruct the proposal' }
        if ($null -eq $Draft.PSObject.Properties['evaluationContextSha256'] -or [string]$Draft.evaluationContextSha256 -cne [string]$context.evaluationContextSha256) { throw 'Saved-edit adjudication has missing or stale evaluation context' }
        $requiresScope = $phase -in @('complete', 'scope') -or ($phase -ceq 'issues' -and $null -ne $Component.PSObject.Properties['scopeReview'])
        if ($requiresScope) {
        if ($null -eq $Draft.PSObject.Properties['scopeReview']) { throw 'Saved-edit adjudication has no required scope review' }
        Test-SavedRuleScopeReview -Component $Component -CandidateKey $context.candidateKey -ScopeReview $Draft.scopeReview
        }
        elseif ($null -ne $Draft.PSObject.Properties['scopeReview']) { throw 'Saved-edit phase returned an unrelated scope review' }
        if ($phase -in @('scope', 'issues')) {
            if ($phase -ceq 'issues' -and $requiresScope) {
            foreach ($field in @('disposition', 'ownerRuleId', 'baselineQuote', 'proposalQuote', 'rationale', 'wordingStatus', 'wordingRationale')) {
                if ($Draft.scopeReview.$field -cne $Component.scopeReview.$field) { throw 'Issue synthesis changed the validated scope review' }
            }
            if ($phase -ceq 'issues') {
                $scopeKeys = @($Component.memberScopeReviews | ForEach-Object candidateKey)
                if ($scopeKeys.Count -ne $editProposals.Count -or @($scopeKeys | Sort-Object -CaseSensitive -Unique).Count -ne $editProposals.Count -or @($scopeKeys | Where-Object { -not $editProposals.ContainsKey([string]$_) }).Count -gt 0) { throw 'Issue synthesis requires one validated scope per candidate' }
                foreach ($member in $Component.memberScopeReviews) {
                    Test-SavedRuleScopeReview -Component $Component -CandidateKey $member.candidateKey -ScopeReview $member.scopeReview
                }
            }
            }
            if ($null -ne $Draft.PSObject.Properties['assessments']) { throw 'Scope and issue synthesis cannot replace validated assessments' }
        }
        else {
        $assessmentSources = @($context.assessmentContext.sources)
        $sourceKeys = @($assessmentSources | ForEach-Object { [string]$_.candidateKey })
        $assessmentProposalKeys = @(Get-SavedRuleAssessmentProposals -Component $Component | ForEach-Object candidateKey)
        if ($sourceKeys.Count -ne $assessmentProposalKeys.Count -or @($sourceKeys | Sort-Object -CaseSensitive -Unique).Count -ne $sourceKeys.Count -or @($sourceKeys | Where-Object { $_ -cnotin $assessmentProposalKeys }).Count -gt 0) { throw 'Saved-edit assessment evidence must cover every assessment target exactly once' }
        $catalogRules = @{}
        foreach ($catalogRule in @($context.assessmentContext.catalogRules)) {
            $id = [string]$catalogRule.id
            if ($catalogRules.ContainsKey($id) -or [string]$catalogRule.status -notin @('active', 'retired', 'protected')) { throw 'Saved-edit assessment catalog has invalid ownership' }
            $catalogRules[$id] = $catalogRule
        }
        $assessmentKeys = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
        $assessmentSchema = Join-Path $PSScriptRoot '../../../copilot-rule-catalog/assessment-reconciliation/saved-rule-assessment.schema.json'
        if ($null -eq $Draft.PSObject.Properties['assessments']) { throw 'Saved-edit adjudication must return complete assessments' }
        foreach ($assessment in @($Draft.assessments)) {
            if (-not (($assessment | ConvertTo-Json -Depth 100) | Test-Json -SchemaFile $assessmentSchema -ErrorAction Stop)) { throw 'Saved-edit assessment does not satisfy its contract' }
            $key = [string]$assessment.candidateKey
            if ($key -cnotin $assessmentProposalKeys -or -not $assessmentKeys.Add($key)) { throw 'Saved-edit assessment has unknown, unchanged comparison, or duplicate ownership' }
            if ([string]$assessment.ruleTextSha256 -cne [string]$editProposals[$key].ruleTextSha256) { throw 'Saved-edit assessment used stale proposal text' }
            if ([int]$assessment.existingCoverage.score -ne [int]$assessment.selectionFactors.redundancy) { throw 'Saved-edit assessment coverage score disagrees with its factors' }
            foreach ($field in @('summary', 'impactDescription', 'applicabilityRationale', 'selectionRationale')) {
                if ([string]::IsNullOrWhiteSpace([string]$assessment.$field)) { throw 'Saved-edit assessment explanation is empty' }
            }
            $operation = @($Component.operations | Where-Object { [string]$_.candidateKey -ceq $key })[0]
            $rule = @($Component.rules | Where-Object { [string]$_.id -ceq [string]$operation.ruleId })[0]
            $allowed = switch ([string]$rule.status) {
                active { @('update', 'no-change', 'retire', 'defer') }
                retired { @('restore', 'no-change', 'defer') }
                proposed { @('add', 'exclude', 'defer') }
                default { @() }
            }
            if ([string]$assessment.recommendation -notin $allowed) { throw 'Saved-edit assessment recommendation violates catalog ownership' }
            $coverageIds = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
            foreach ($coverage in @($assessment.relatedHostedCoverage)) {
                $id = [string]$coverage.hostedRuleId
                if (-not $catalogRules.ContainsKey($id) -or [string]$catalogRules[$id].status -ceq 'retired' -or -not $coverageIds.Add($id) -or [string]::IsNullOrWhiteSpace([string]$coverage.rationale)) { throw 'Saved-edit assessment has unknown, retired, or duplicate Hosted coverage' }
            }
        }
        if ($assessmentKeys.Count -ne $assessmentProposalKeys.Count) { throw 'Saved-edit adjudication did not reassess every assessment target' }
        }
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
                if ([string]$operation.action -ceq 'retire') { throw 'Saved edits cannot introduce whole-rule retirement' }
                if ($null -eq $operation.PSObject.Properties['textSource'] -or [string]$operation.textSource -notin @('baseline', 'proposal', 'suggestion')) { throw 'Saved-edit operation is missing text provenance' }
                if ([string]$operation.textSource -ceq 'suggestion') {
                    $intendedCandidate = ([pscustomobject]$Component.editContext).PSObject.Properties['intendedCandidateKey']
                    if ($null -eq $intendedCandidate -or
                        [string]$candidateKey -cne [string]$intendedCandidate.Value -or
                        [string]$operation.action -notin @('add', 'update', 'restore') -or
                        ([string]$proposal.proposedText).Replace("`r`n", "`n") -ceq ([string]$proposal.baselineText).Replace("`r`n", "`n") -or
                        [string]$issue.wording.status -cne 'selected' -or
                        [string]$issue.wording.sourceRuleId -cne [string]$operation.ruleId -or
                        [string]$issue.wording.text -cne [string]$operation.proposedText) {
                        throw 'A saved-edit suggestion must preserve the edited candidate as its selected mutation target'
                    }
                    if (([string]$proposal.proposedText).StartsWith([string]$proposal.baselineText, [StringComparison]::Ordinal) -and
                        -not ([string]$operation.proposedText).StartsWith([string]$proposal.baselineText, [StringComparison]::Ordinal)) {
                        throw 'An appended consolidation must retain the complete unchanged baseline'
                    }
                    if ($null -eq $operation.PSObject.Properties['preservation']) { throw 'A saved-edit suggestion requires complete obligation preservation evidence' }
                    $requiredPreservationIds = @([string]$operation.ruleId) + @($operation.retireHostedRuleIds)
                    $preservedIds = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
                    foreach ($preservation in @($operation.preservation)) {
                        $id = [string]$preservation.ruleId
                        if ($id -cnotin $requiredPreservationIds -or -not $preservedIds.Add($id)) { throw 'Consolidation preservation has unknown or duplicate ownership' }
                        $sourceRules = @($Component.rules | Where-Object id -CEQ $id)
                        if ($sourceRules.Count -ne 1) { throw 'Consolidation preservation requires one known source rule' }
                        $sourceProposals = @($Component.editContext.proposals | Where-Object { $_.candidateKey -cin @($sourceRules[0].candidateKeys) })
                        $sourceTexts = @($sourceProposals | ForEach-Object proposedText | Sort-Object -CaseSensitive -Unique)
                        if ($sourceTexts.Count -gt 1) { throw 'Consolidation cannot discard divergent proposals for one retired rule' }
                        $sourceText = if ($sourceTexts.Count -eq 1) { [string]$sourceTexts[0] } else { [string]$sourceRules[0].text }
                        if ([string]$preservation.sourceText -cne $sourceText -or
                            [string]::IsNullOrWhiteSpace([string]$preservation.mergedQuote) -or
                            -not ([string]$operation.proposedText).Contains([string]$preservation.mergedQuote, [StringComparison]::Ordinal) -or
                            [string]::IsNullOrWhiteSpace([string]$preservation.rationale)) {
                            throw 'Consolidation preservation must bind complete source text to literal merged wording and its meaning'
                        }
                    }
                    if ($preservedIds.Count -ne $requiredPreservationIds.Count) { throw 'Consolidation must account for the edited proposal and every proposed retirement' }
                }
                else {
                    $expectedText = if ([string]$operation.textSource -ceq 'baseline') { [string]$proposal.baselineText } else { [string]$proposal.proposedText }
                    if ([string]$operation.proposedText -cne $expectedText) { throw 'Saved-edit operation must preserve the complete supplied baseline or proposal' }
                    if ((@($operation.retireHostedRuleIds | Sort-Object -CaseSensitive) -join "`0") -cne (@($proposal.retireHostedRuleIds | Sort-Object -CaseSensitive) -join "`0")) { throw 'Saved-edit operation cannot change the supplied retirement set' }
                }
                if ($phase -ceq 'issues' -and [string]$operation.textSource -cne 'suggestion') {
                    $memberScope = @($Component.memberScopeReviews | Where-Object candidateKey -CEQ $candidateKey)[0].scopeReview
                    if ([string]$memberScope.disposition -in @('route-to-existing-rule', 'suggest-new-rule') -and [string]$operation.proposedText -cne [string]$proposal.baselineText) { throw 'Out-of-scope group members must preserve their complete baselines' }
                }
                if ([string]$operation.textSource -cne 'suggestion' -and [string]$candidateKey -ceq [string]$Component.editContext.candidateKey -and [string]$Draft.scopeReview.disposition -in @('route-to-existing-rule', 'suggest-new-rule') -and $null -ne $Component.editContext.appendText -and [string]$operation.proposedText -cne [string]$proposal.baselineText) { throw 'Out-of-scope additions must preserve the complete edit baseline' }
            }
            foreach ($retireRuleId in @($operation.retireHostedRuleIds)) {
                $retireRule = @($Component.rules | Where-Object { [string]$_.id -ceq [string]$retireRuleId })[0]
                if ($null -eq $retireRule -or [string]$retireRule.status -cne 'active' -or
                    -not $issueRuleIds.Contains([string]$retireRuleId) -or
                    [string]$retireRuleId -ceq [string]$operation.ruleId -or
                    [string]$dispositionByRuleId[[string]$retireRuleId] -cne 'retire') {
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

function New-SavedRuleAdjudicationPhaseInput {
    param(
        [object]$Component,
        [ValidateSet('scope', 'assessment', 'relationships', 'issues')][string]$Phase,
        [object[]]$Items,
        [object]$ScopeReview
    )

    $context = $Component.editContext
    $phaseInput = [ordered]@{
        '$schema' = $Component.'$schema'; schemaVersion = 1; kind = $Component.kind
        componentId = ''; evaluationPhase = $Phase
        sourceFiles = @($Component.sourceFiles); rules = @(); relationships = @(); operations = @()
    }
    if ($Phase -ceq 'relationships') {
        $ruleIds = @($Items | ForEach-Object { $_.sourceRuleId; $_.relatedRuleId })
        $phaseInput.rules = @($Component.rules | Where-Object { $_.id -cin $ruleIds })
        $phaseInput.relationships = @($Items)
        $phaseInput.componentId = 'saved-relationships:' + (Get-JsonSnapshotSha256 -Value @($Items.id | Sort-Object -CaseSensitive))
        $phaseInput.evaluationContextSha256 = Get-JsonSnapshotSha256 -Value $phaseInput -Depth 100
        return [pscustomobject]$phaseInput
    }
    if ($Phase -in @('scope', 'assessment')) {
        $proposals = @($Items | Sort-Object candidateKey -CaseSensitive)
        $candidateKey = [string]$proposals[0].candidateKey
        $ruleIds = @(if ($Phase -ceq 'scope') { $Component.rules | Where-Object { $_.status -in @('active', 'protected') } | ForEach-Object id })
    }
    else {
        $ruleIds = @($Items | ForEach-Object { $_.sourceRuleId; $_.relatedRuleId })
        $proposals = @($context.proposals | Where-Object {
            $key = $_.candidateKey
            @($Component.operations | Where-Object { $_.candidateKey -ceq $key -and $_.ruleId -cin $ruleIds }).Count -gt 0
        } | Sort-Object candidateKey -CaseSensitive)
        if ($proposals.Count -eq 0) { throw 'Saved-edit issue group has no candidate owner' }
        $candidateKey = [string]$proposals[0].candidateKey
        $phaseInput.relationships = @($Items)
        $phaseInput.memberScopeReviews = @($ScopeReview | Sort-Object candidateKey -CaseSensitive)
        $phaseInput.scopeReview = @($phaseInput.memberScopeReviews | Where-Object candidateKey -CEQ $candidateKey)[0].scopeReview
        $ruleIds += @($phaseInput.memberScopeReviews | ForEach-Object { $_.scopeReview.ownerRuleId } | Where-Object { $null -ne $_ })
    }
    $keys = @($proposals.candidateKey)
    $phaseInput.operations = @($Component.operations | Where-Object { $_.candidateKey -cin $keys })
    $ruleIds += @($phaseInput.operations | ForEach-Object { $_.ruleId; @($_.retireHostedRuleIds) })
    $phaseInput.rules = @($Component.rules | Where-Object { $_.id -cin $ruleIds })
    if ($Phase -ceq 'assessment') {
        $phaseInput.rules = @($phaseInput.rules | ForEach-Object {
            $rule = $_
            $operation = @($phaseInput.operations | Where-Object ruleId -CEQ $rule.id | Sort-Object candidateKey -CaseSensitive | Select-Object -First 1)
            $text = if ($operation.Count) { [string]$operation[0].proposedText } else { [string]$rule.text }
            [ordered]@{ id = $rule.id; status = $rule.status; title = $rule.title; text = $text; contentSha256 = Get-Sha256 -Content $text; candidateKeys = @($rule.candidateKeys) }
        })
    }
    $phaseInput.componentId = 'saved-' + $Phase + ':' + (Get-JsonSnapshotSha256 -Value $(if ($Phase -ceq 'issues') { @($Items.id | Sort-Object -CaseSensitive) } else { @($keys | Sort-Object -CaseSensitive) }))
    $primary = @($proposals | Where-Object candidateKey -CEQ $candidateKey)[0]
    $phaseInput.editContext = [ordered]@{
        candidateKey = $candidateKey; baselineText = $primary.baselineText
        baselineSha256 = Get-Sha256 -Content ([string]$primary.baselineText)
        appendText = if (([string]$primary.proposedText).StartsWith([string]$primary.baselineText, [StringComparison]::Ordinal)) { ([string]$primary.proposedText).Substring(([string]$primary.baselineText).Length) } else { $null }
        proposals = $proposals
    }
    $intendedCandidate = ([pscustomobject]$context).PSObject.Properties['intendedCandidateKey']
    if ($Phase -ceq 'issues' -and $null -ne $intendedCandidate) {
        $phaseInput.editContext.intendedCandidateKey = $intendedCandidate.Value
    }
    if ($Phase -ceq 'assessment') {
        $phaseInput.editContext.assessmentContext = [ordered]@{
            catalogRules = @($context.assessmentContext.catalogRules)
            sources = @($context.assessmentContext.sources | Where-Object { $_.candidateKey -cin $keys })
        }
    }
    $phaseInput.editContext.evaluationContextSha256 = Get-JsonSnapshotSha256 -Value $phaseInput -Depth 100
    return [pscustomobject]$phaseInput
}

function Invoke-SavedRuleAdjudicationPhase {
    param(
        [object]$Component,
        [ValidateSet('scope', 'assessment', 'relationships')][string]$Phase,
        [object[]]$Items,
        [Collections.IDictionary]$StageParameters,
        [string]$InputSchemaPath,
        [long]$ArtifactBytes
    )

    if ($Items.Count -eq 0) { return [pscustomobject]@{ results = @(); cachedCount = 0; evaluatedCount = 0 } }
    $units = @($Items | ForEach-Object {
        $payload = New-SavedRuleAdjudicationPhaseInput -Component $Component -Phase $Phase -Items @($_)
        if (-not (($payload | ConvertTo-Json -Depth 100) | Test-Json -SchemaFile $InputSchemaPath -ErrorAction Stop)) { throw 'Saved-edit semantic input does not satisfy its contract' }
        [pscustomobject]@{ shardKey = 'adjudication:' + (Get-JsonSnapshotSha256 -Value $payload -Depth 100); payload = $payload }
    })
    if ($Phase -ceq 'scope') { return Invoke-ReconciliationStageSet @StageParameters -Stage adjudication -Shards $units }
    $batchExecutor = {
        param($pending)
        $items = @($pending | ForEach-Object { if ($Phase -ceq 'assessment') { $_.payload.editContext.proposals } else { $_.payload.relationships } })
        $newPayload = { param($members) New-SavedRuleAdjudicationPhaseInput -Component $Component -Phase $Phase -Items $members }
        $measure = {
            param($payload)
            $shard = [pscustomobject]@{ shardKey = 'adjudication:' + (Get-JsonSnapshotSha256 -Value $payload -Depth 100); payload = $payload }
            Get-ReconciliationReservedPayloadBytes -StageInput (Get-ReconciliationStageInput -Stage adjudication -Shard $shard) -ArtifactBytes $ArtifactBytes
        }
        $getKey = { param($item) if ($Phase -ceq 'assessment') { $item.candidateKey } else { $item.id } }
        $batches = @(Split-ReconciliationPayloads -Items $items -MaxBytes $StageParameters.EvaluatorPayloadBudgetBytes -CollectionName $Phase -Stage adjudication -GetItemKey $getKey -NewPayload $newPayload -MeasurePayload $measure)
        foreach ($batch in $batches) {
            if (-not (($batch.payload | ConvertTo-Json -Depth 100) | Test-Json -SchemaFile $InputSchemaPath -ErrorAction Stop)) { throw 'Bounded saved-edit input does not satisfy its contract' }
        }
        $run = Invoke-ReconciliationStageSet @StageParameters -Stage adjudication -Shards $batches
        foreach ($unit in $pending) {
            $draft = [ordered]@{
                '$schema' = 'rule-issue-adjudication-draft-v4.schema.json'; schemaVersion = 1; kind = 'hosted-rule-issue-adjudication-draft'
                componentId = $unit.payload.componentId; evaluationPhase = $Phase; issues = @(); relationshipDecisions = @()
            }
            if ($Phase -ceq 'assessment') {
                $key = [string]$unit.payload.editContext.candidateKey
                $draft.evaluationContextSha256 = $unit.payload.editContext.evaluationContextSha256
                $draft.assessments = @($run.results | ForEach-Object { $_.result.assessments } | Where-Object candidateKey -CEQ $key)
            }
            else {
                $id = [string]$unit.payload.relationships[0].id
                $draft.evaluationContextSha256 = $unit.payload.evaluationContextSha256
                $draft.relationshipDecisions = @($run.results | ForEach-Object { $_.result.relationshipDecisions } | Where-Object relationshipId -CEQ $id)
            }
            [pscustomobject]@{ shardKey = $unit.shardKey; result = [pscustomobject]$draft }
        }
    }
    return Invoke-ReconciliationStageSet @StageParameters -Stage adjudication -Shards $units -BatchExecutor $batchExecutor
}

function Invoke-BoundedSavedRuleAdjudication {
    [CmdletBinding()]
    param(
        [object]$Component,
        [Collections.IDictionary]$StageParameters,
        [string]$InputSchemaPath,
        [long]$ArtifactBytes
    )

    Import-Module (Join-Path $PSScriptRoot 'HierarchicalReconciliation.psm1')
    Import-Module (Join-Path $PSScriptRoot 'ReconciliationStageExecutor.psm1')
    $entries = [Collections.Generic.List[object]]::new()
    $cachedCount = 0
    $evaluatedCount = 0
    $measure = {
        param($payload)
        $shard = [pscustomobject]@{ shardKey = 'adjudication:' + (Get-JsonSnapshotSha256 -Value $payload -Depth 100); payload = $payload }
        Get-ReconciliationReservedPayloadBytes -StageInput (Get-ReconciliationStageInput -Stage adjudication -Shard $shard) -ArtifactBytes $ArtifactBytes
    }
    $editedKey = [string]$Component.editContext.candidateKey
    $assessmentProposals = @(Get-SavedRuleAssessmentProposals -Component $Component)
    if ($assessmentProposals.Count -eq 1 -and (& $measure $Component) -le $StageParameters.EvaluatorPayloadBudgetBytes) {
        $payload = $Component | ConvertTo-Json -Depth 100 | ConvertFrom-Json -Depth 100 -DateKind String
        $payload.editContext.evaluationContextSha256 = ''
        $payload.editContext.evaluationContextSha256 = Get-JsonSnapshotSha256 -Value $payload -Depth 100
        $shard = [pscustomobject]@{ shardKey = 'adjudication:' + (Get-JsonSnapshotSha256 -Value $payload -Depth 100); payload = $payload }
        $run = Invoke-ReconciliationStageSet @StageParameters -Stage adjudication -Shards @($shard)
        $draft = $run.results[0].result | ConvertTo-Json -Depth 100 | ConvertFrom-Json -Depth 100 -DateKind String
        $draft.evaluationContextSha256 = $Component.editContext.evaluationContextSha256
        Test-RuleIssueAdjudicationDraft -Component $Component -Draft $draft
        return [pscustomobject]@{ draft = $draft; results = $run.results; cachedCount = $run.cachedCount; evaluatedCount = $run.evaluatedCount }
    }
    $phaseParameters = @{ Component = $Component; StageParameters = $StageParameters; InputSchemaPath = $InputSchemaPath; ArtifactBytes = $ArtifactBytes }
    $scopeRun = Invoke-SavedRuleAdjudicationPhase @phaseParameters -Phase scope -Items @($Component.editContext.proposals | Where-Object candidateKey -CEQ $editedKey)
    $assessmentRun = Invoke-SavedRuleAdjudicationPhase @phaseParameters -Phase assessment -Items $assessmentProposals
    $relationshipRun = Invoke-SavedRuleAdjudicationPhase @phaseParameters -Phase relationships -Items @($Component.relationships)
    foreach ($run in @($scopeRun, $assessmentRun, $relationshipRun)) {
        $entries.AddRange([object[]]@($run.results))
        $cachedCount += $run.cachedCount
        $evaluatedCount += $run.evaluatedCount
    }
    $assessments = @($assessmentRun.results | ForEach-Object { $_.result.assessments })
    $scopeReview = $scopeRun.results[0].result.scopeReview
    $scopeReviewsByKey = @{ $editedKey = $scopeReview }
    $decisions = @($relationshipRun.results | ForEach-Object { $_.result.relationshipDecisions })
    $decisionsById = @{}
    foreach ($decision in $decisions) { $decisionsById[[string]$decision.relationshipId] = $decision }
    $materialEdges = @($Component.relationships | Where-Object { $decisionsById[[string]$_.id].disposition -ceq 'issue' })
    $issueShards = @()
    if ($materialEdges.Count -gt 0) {
        $memberIds = @($materialEdges | ForEach-Object { $_.sourceRuleId; $_.relatedRuleId } | Sort-Object -CaseSensitive -Unique)
        $ledger = [pscustomobject]@{
            nodes = @($Component.rules | Where-Object { $_.id -cin $memberIds } | ForEach-Object { [pscustomobject]@{ nodeKey = $_.id; routingText = $_.text } })
            eligibleNodeKeys = $memberIds
        }
        $singletons = @(Merge-LocalRoutingSuggestions -Ledger $ledger)
        $componentKeysByRule = @{}
        foreach ($singleton in $singletons) { $componentKeysByRule[[string]$singleton.nodeKeys[0]] = $singleton.componentKey }
        $suggestions = @($materialEdges | ForEach-Object {
            [pscustomobject]@{ componentKeys = @($componentKeysByRule[[string]$_.sourceRuleId], $componentKeysByRule[[string]$_.relatedRuleId]); semanticSummary = $_.rationale }
        })
        $groups = @(Merge-ConsolidationSuggestions -Ledger $ledger -Components $singletons -Suggestions $suggestions)
        foreach ($group in $groups) {
            $edges = @($materialEdges | Where-Object { $_.sourceRuleId -cin $group.nodeKeys -and $_.relatedRuleId -cin $group.nodeKeys })
            $groupKeys = @($Component.operations | Where-Object { $_.ruleId -cin $group.nodeKeys } | ForEach-Object candidateKey)
            $missingScopes = @($Component.editContext.proposals | Where-Object { $_.candidateKey -cin $groupKeys -and -not $scopeReviewsByKey.ContainsKey([string]$_.candidateKey) })
            if ($missingScopes.Count -gt 0) {
                $memberScopeRun = Invoke-SavedRuleAdjudicationPhase @phaseParameters -Phase scope -Items $missingScopes
                $entries.AddRange([object[]]@($memberScopeRun.results))
                $cachedCount += $memberScopeRun.cachedCount
                $evaluatedCount += $memberScopeRun.evaluatedCount
                foreach ($proposal in $missingScopes) {
                    $scopeInput = New-SavedRuleAdjudicationPhaseInput -Component $Component -Phase scope -Items @($proposal)
                    $scopeReviewsByKey[[string]$proposal.candidateKey] = @($memberScopeRun.results | Where-Object { $_.result.componentId -ceq $scopeInput.componentId })[0].result.scopeReview
                }
            }
            $groupScopes = @($groupKeys | Sort-Object -CaseSensitive | ForEach-Object { [pscustomobject]@{ candidateKey = $_; scopeReview = $scopeReviewsByKey[[string]$_] } })
            $payload = New-SavedRuleAdjudicationPhaseInput -Component $Component -Phase issues -Items $edges -ScopeReview $groupScopes
            if (-not (($payload | ConvertTo-Json -Depth 100) | Test-Json -SchemaFile $InputSchemaPath -ErrorAction Stop)) { throw 'Saved-edit issue synthesis input does not satisfy its contract' }
            $bytes = & $measure $payload
            if ($bytes -gt $StageParameters.EvaluatorPayloadBudgetBytes) { throw "Saved-edit semantic issue group requires $bytes bytes after bounded routing and exceeds the evaluator payload budget of $($StageParameters.EvaluatorPayloadBudgetBytes) bytes; semantic issue groups are indivisible" }
            $issueShards += [pscustomobject]@{ shardKey = 'adjudication:' + (Get-JsonSnapshotSha256 -Value $payload -Depth 100); payload = $payload }
        }
    }
    $finalDecisions = @($decisions | Where-Object disposition -CEQ 'independent')
    $issues = @()
    if ($issueShards.Count -gt 0) {
        $issueRun = Invoke-ReconciliationStageSet @StageParameters -Stage adjudication -Shards $issueShards
        $entries.AddRange([object[]]@($issueRun.results))
        $cachedCount += $issueRun.cachedCount
        $evaluatedCount += $issueRun.evaluatedCount
        $finalDecisions += @($issueRun.results | ForEach-Object { $_.result.relationshipDecisions })
        $issues = @($issueRun.results | ForEach-Object { $_.result.issues })
    }
    $draft = [pscustomobject][ordered]@{
        '$schema' = 'rule-issue-adjudication-draft-v4.schema.json'; schemaVersion = 1; kind = 'hosted-rule-issue-adjudication-draft'
        componentId = $Component.componentId; evaluationContextSha256 = $Component.editContext.evaluationContextSha256
        scopeReview = $scopeReview; assessments = @($assessments | Sort-Object candidateKey -CaseSensitive)
        relationshipDecisions = @($finalDecisions | Sort-Object relationshipId -CaseSensitive); issues = $issues
    }
    if (-not (($draft | ConvertTo-Json -Depth 100) | Test-Json -SchemaFile $StageParameters.ResultSchemaPath -ErrorAction Stop)) { throw 'Merged saved-edit adjudication does not satisfy its contract' }
    Test-RuleIssueAdjudicationDraft -Component $Component -Draft $draft
    return [pscustomobject]@{ draft = $draft; results = $entries.ToArray(); cachedCount = $cachedCount; evaluatedCount = $evaluatedCount }
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

Export-ModuleMember -Function 'Get-SavedRuleAssessmentProposals', 'Test-RuleIssueAdjudicationDraft', 'ConvertTo-WorkbenchRuleIssues', 'Invoke-BoundedSavedRuleAdjudication'
