[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][ValidateSet('adjudication')][string]$Stage,
    [Parameter(Mandatory = $true)][string]$InputPath,
    [Parameter(Mandatory = $true)][string]$CatalogPath,
    [Parameter(Mandatory = $true)][string]$ProtectedRulesPath,
    [Parameter(Mandatory = $true)][string]$ContractPath,
    [Parameter(Mandatory = $true)][string]$SchemaPath,
    [Parameter(Mandatory = $true)][string]$PromptPath,
    [Parameter(Mandatory = $true)][string]$OutputPath,
    [Parameter(Mandatory = $true)][string]$EvaluatorCommand,
    [Parameter(Mandatory = $true)][string]$Model,
    [Parameter(Mandatory = $true)][string]$ReasoningEffort
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$stageInput = Get-Content -LiteralPath $InputPath -Raw | ConvertFrom-Json -DateKind String
$request = $stageInput.payload
$phase = if ($null -ne $request.PSObject.Properties['evaluationPhase']) { [string]$request.evaluationPhase } else { 'complete' }
$metricsPath = if ($EvaluatorCommand.StartsWith('fixture-log:', [StringComparison]::Ordinal)) { $EvaluatorCommand.Substring('fixture-log:'.Length) } else { [Environment]::GetEnvironmentVariable('HOSTED_WORKBENCH_TEST_ADJUDICATION_METRICS') }
if (-not [string]::IsNullOrWhiteSpace($metricsPath)) {
    $reservedBytes = (@($InputPath, $CatalogPath, $ProtectedRulesPath, $ContractPath, $SchemaPath, $PromptPath) | ForEach-Object { (Get-Item -LiteralPath $_).Length } | Measure-Object -Sum).Sum + 16384
    $metrics = [ordered]@{
        phase = $phase; reservedBytes = $reservedBytes
        model = $Model; effort = $ReasoningEffort
        candidates = @(if ($phase -in @('assessment', 'complete')) { $request.editContext.assessmentContext.sources.candidateKey })
        relationships = @(if ($phase -in @('relationships', 'complete')) { $request.relationships.id })
        scopeCandidate = if ($phase -in @('scope', 'complete')) { [string]$request.editContext.candidateKey } else { $null }
        sourceCharacters = if ($phase -in @('assessment', 'complete')) { (@($request.editContext.assessmentContext.sources | ForEach-Object sourceRules) | ForEach-Object { ([string]$_.text).Length } | Measure-Object -Sum).Sum } else { 0 }
    }
    [IO.File]::AppendAllText($metricsPath, ($metrics | ConvertTo-Json -Compress -Depth 10) + "`n")
    $failureControlPath = $metricsPath + '.fail-phase'
    if ((Test-Path -LiteralPath $failureControlPath) -and (Get-Content -LiteralPath $failureControlPath -Raw).Trim() -ceq $phase) { throw "Synthetic $phase evaluator failure" }
}
if ($phase -ceq 'relationships') {
    $result = [ordered]@{
        '$schema' = 'rule-issue-adjudication-draft-v4.schema.json'; schemaVersion = 1; kind = 'hosted-rule-issue-adjudication-draft'
        componentId = $request.componentId; evaluationPhase = $phase; evaluationContextSha256 = $request.evaluationContextSha256; issues = @()
        relationshipDecisions = @($request.relationships | ForEach-Object {
            $edge = $_
            $source = @($request.rules | Where-Object id -CEQ $edge.sourceRuleId)[0]
            $related = @($request.rules | Where-Object id -CEQ $edge.relatedRuleId)[0]
            $material = ([string]$source.text + [string]$related.text).Contains('Grouped review is required.', [StringComparison]::Ordinal)
            [ordered]@{
                relationshipId = $edge.id; disposition = if ($material) { 'issue' } else { 'independent' }
                relationship = if ($material) { $edge.relationship } else { 'none' }
                rationale = 'The bounded fixture compares both complete exact rule texts.'
                sourceQuote = $source.text; relatedQuote = $related.text
            }
        })
    }
    $json = $result | ConvertTo-Json -Depth 100
    if (-not ($json | Test-Json -SchemaFile $SchemaPath -ErrorAction Stop)) { throw 'Bounded relationship fixture does not satisfy its schema' }
    [IO.File]::WriteAllText($OutputPath, $json + "`n", [Text.UTF8Encoding]::new($false))
    return
}
if ($null -ne $request.PSObject.Properties['editContext']) {
    $context = $request.editContext
    $proposal = @($context.proposals | Where-Object candidateKey -CEQ $context.candidateKey)[0]
    $operation = @($request.operations | Where-Object candidateKey -CEQ $context.candidateKey)[0]
    $rule = @($request.rules | Where-Object id -CEQ $operation.ruleId)[0]
    $grouped = $phase -ceq 'issues' -or ([string]$proposal.proposedText).Contains('Grouped review is required.', [StringComparison]::Ordinal)
    $routed = ([string]$proposal.proposedText).Contains('Scope routing is required.', [StringComparison]::Ordinal)
    $wordingReview = ([string]$proposal.proposedText).Contains('Wording review fixture.', [StringComparison]::Ordinal)
    $owner = if ($routed -and $phase -in @('scope', 'complete')) { @($request.rules | Where-Object { $_.id -cne $rule.id -and $_.status -in @('active', 'protected') })[0].id } else { $null }
    $decisions = @($request.relationships | ForEach-Object {
        $edge = $_
        [ordered]@{
            relationshipId = [string]$edge.id; disposition = if ($grouped) { 'issue' } else { 'independent' }
            relationship = if ($grouped) { [string]$edge.relationship } else { 'none' }
            rationale = 'The deterministic saved-edit fixture supplies this comparison outcome.'
            sourceQuote = [string]@($request.rules | Where-Object id -CEQ $edge.sourceRuleId)[0].text
            relatedQuote = [string]@($request.rules | Where-Object id -CEQ $edge.relatedRuleId)[0].text
        }
    })
    $issues = @()
    if ($grouped -and $decisions.Count -gt 0) {
        $memberIds = @($request.relationships | ForEach-Object { [string]$_.sourceRuleId; [string]$_.relatedRuleId } | Sort-Object -CaseSensitive -Unique)
        $protected = @($request.rules | Where-Object { $_.id -cin $memberIds -and $_.status -ceq 'protected' })
        $action = switch ($rule.status) { active { 'update' }; retired { 'restore' }; proposed { 'add' } }
        $issues = @([ordered]@{
            anchorRuleId = [string]$rule.id; classification = if ($protected.Count -gt 0) { 'protected-coverage' } else { 'overlap' }
            title = 'Saved-edit fixture group'; bannerTitle = 'Saved Edit Requires Grouped Review'
            bannerMessage = 'The saved-edit fixture returns one complete grouped recommendation.'
            blocking = $false; ruleIds = $memberIds; relationshipIds = @($request.relationships.id)
            ruleDispositions = @($memberIds | ForEach-Object { [ordered]@{ ruleId = $_; disposition = if ($_ -ceq $rule.id) { if ($action -ceq 'update') { 'replace' } else { 'promote' } } else { 'keep' } } })
            assessmentSummary = 'The recommendation preserves the complete reconciled baseline without adding retirement.'
            wording = if ($protected.Count -gt 0) { [ordered]@{ status = 'canonical'; label = 'Canonical Protected Wording'; presentation = 'section'; text = [string]$protected[0].text; sourceRuleId = [string]$protected[0].id } } else { [ordered]@{ status = 'selected'; label = 'Suggested Consolidated Wording'; presentation = 'section'; text = [string]$proposal.baselineText; sourceRuleId = [string]$rule.id } }
            recommendedMaintainerAction = [ordered]@{
                summary = 'Use the complete baseline and preserve the other independent rule.'
                operations = @([ordered]@{ candidateKey = [string]$context.candidateKey; ruleId = [string]$rule.id; action = $action; proposedText = [string]$proposal.baselineText; textSource = 'baseline'; retireHostedRuleIds = @($proposal.retireHostedRuleIds) })
            }
        })
    }
    $result = [ordered]@{
        '$schema' = 'rule-issue-adjudication-draft-v4.schema.json'; schemaVersion = 1; kind = 'hosted-rule-issue-adjudication-draft'
        componentId = [string]$request.componentId; evaluationContextSha256 = [string]$context.evaluationContextSha256
        scopeReview = if ($phase -ceq 'issues') { if ($null -ne $request.PSObject.Properties['scopeReview']) { $request.scopeReview } else { $null } } else { [ordered]@{
            disposition = if ($routed) { 'route-to-existing-rule' } else { 'within-scope' }; ownerRuleId = $owner
            baselineQuote = [string]$context.baselineText; proposalQuote = [string]$proposal.proposedText
            rationale = if ($routed) { 'The fixture routes the separate obligation to its supplied existing owner without moving it.' } else { 'The saved-edit fixture preserves the baseline scope.' }
            wordingStatus = if ($wordingReview) { 'needs-review' } else { 'acceptable' }
            wordingRationale = if ($wordingReview) { 'The unrelated fixture sentence must be removed before accepting the wording.' } else { 'The complete fixture wording expresses an enforceable obligation.' }
        } }
        assessments = @(if ($phase -in @('assessment', 'complete')) { $context.proposals | Where-Object { $_.candidateKey -cin @($context.assessmentContext.sources.candidateKey) } | ForEach-Object {
            $item = $_
            $itemOperation = @($request.operations | Where-Object candidateKey -CEQ $item.candidateKey)[0]
            $itemRule = @($request.rules | Where-Object id -CEQ $itemOperation.ruleId)[0]
            $coverage = @($context.assessmentContext.catalogRules | Where-Object { $_.status -in @('active', 'protected') -and $_.id -cne $itemRule.id } | Select-Object -First 1 | ForEach-Object {
                [ordered]@{ hostedRuleId = $_.id; relationship = 'related'; rationale = 'The refreshed fixture identifies a distinct existing obligation.' }
            })
            [ordered]@{
                candidateKey = [string]$item.candidateKey; ruleTextSha256 = [string]$item.ruleTextSha256
                summary = 'The complete saved wording is reassessed.'
                impactDescription = 'The refreshed fixture describes the saved proposal rather than the initial assessment.'
                hostedApplicable = $true; applicabilityRationale = 'The saved obligation is observable in a Hosted review.'
                selectionFactors = [ordered]@{ severity = 5; frequency = 4; breadth = 3; hostedDetectability = 5; evidenceStrength = 5; falsePositiveRisk = 0; redundancy = 1 }
                selectionRationale = 'The refreshed assessment evaluates the complete saved wording and its current source evidence.'
                existingCoverage = [ordered]@{ score = 1; rationale = 'Existing Hosted guidance supplies limited coverage of this saved proposal.' }
                relatedHostedCoverage = $coverage
                recommendation = switch ($itemRule.status) { active { 'update' }; retired { 'defer' }; proposed { 'add' } }
            }
        } })
        relationshipDecisions = $decisions; issues = $issues
    }
    if ($phase -cne 'complete') { $result.evaluationPhase = $phase }
    if ($phase -in @('scope', 'issues')) { $result.Remove('assessments') }
    if ($phase -ceq 'assessment' -or ($phase -ceq 'issues' -and $null -eq $request.PSObject.Properties['scopeReview'])) { $result.Remove('scopeReview') }
    $json = $result | ConvertTo-Json -Depth 100
    if (-not ($json | Test-Json -SchemaFile $SchemaPath -ErrorAction Stop)) { throw 'Saved-edit fixture adjudication does not satisfy its schema' }
    [IO.File]::WriteAllText($OutputPath, $json + "`n", [Text.UTF8Encoding]::new($false))
    return
}
$independent = [string]$request.componentId -like '*independent*'
$invalidReference = [string]$request.componentId -like '*invalid-reference*'
$decisions = @($request.relationships | ForEach-Object {
    [ordered]@{
        relationshipId = [string]$_.id
        disposition = if ($independent) { 'independent' } else { 'issue' }
        relationship = if ($independent) { 'none' } else { [string]$_.relationship }
        rationale = if ($independent) { 'The exact obligations can coexist independently.' } else { 'The exact obligations require one maintainer decision.' }
    }
})
$issues = @()
if (-not $independent) {
    $protectedRules = @($request.rules | Where-Object status -eq 'protected')
    $hasConflict = @($decisions | Where-Object relationship -eq 'conflicts').Count -gt 0
    $hasEquivalent = @($decisions | Where-Object relationship -eq 'equivalent').Count -gt 0
    $classification = if ($protectedRules.Count -gt 1) { 'protected-integrity' } elseif ($protectedRules.Count -eq 1 -and $hasConflict) { 'protected-conflict' } elseif ($protectedRules.Count -eq 1) { 'protected-coverage' } elseif ($hasConflict) { 'contradiction' } elseif ($hasEquivalent) { 'duplicate' } else { 'overlap' }
    $dispositions = @($request.rules | ForEach-Object {
        $rule = $_
        $operation = @($request.operations | Where-Object ruleId -eq $rule.id | Select-Object -First 1)
        $disposition = if ($rule.status -eq 'protected') {
            'keep'
        }
        elseif ($operation.Count -eq 0) {
            'review'
        }
        else {
            switch ([string]$operation[0].action) {
                'add' { 'promote' }
                'restore' { 'promote' }
                'update' { 'replace' }
                default { [string]$operation[0].action }
            }
        }
        [ordered]@{ ruleId = [string]$rule.id; disposition = $disposition }
    })
    $promotionOperations = @($request.operations | Where-Object action -in @('add', 'update', 'restore'))
    $wording = if ($protectedRules.Count -eq 1) {
        [ordered]@{ status = 'canonical'; label = 'Canonical Protected Wording'; presentation = 'section'; text = [string]$protectedRules[0].text; sourceRuleId = [string]$protectedRules[0].id }
    }
    elseif ($promotionOperations.Count -eq 1) {
        $operation = $promotionOperations[0]
        $member = @($request.rules | Where-Object id -eq $operation.ruleId)[0]
        [ordered]@{ status = 'selected'; label = 'Suggested Consolidated Wording'; presentation = $(if ([string]$member.text -ceq [string]$operation.proposedText) { 'member' } else { 'section' }); text = [string]$operation.proposedText; sourceRuleId = [string]$operation.ruleId }
    }
    else {
        [ordered]@{ status = 'unresolved'; label = 'Consolidated Wording Unresolved'; presentation = 'section'; reason = 'No single final wording was selected.' }
    }
    $issues = @([ordered]@{
        anchorRuleId = [string]$request.rules[0].id
        classification = $classification
        title = 'Fixture relationship group'
        bannerTitle = 'Fixture Rule Issue'
        bannerMessage = 'Fixture relationships require one maintainer decision.'
        blocking = $protectedRules.Count -gt 1
        ruleIds = @($request.rules.id)
        relationshipIds = @($request.relationships.id)
        ruleDispositions = $dispositions
        assessmentSummary = if ($invalidReference) { 'IMPL-FAKE-999 must remain the owner.' } else { 'The fixture rules require one coherent maintainer decision.' }
        wording = $wording
        recommendedMaintainerAction = [ordered]@{ summary = 'Review the fixture operations.'; operations = @($request.operations | Where-Object action -ne 'no-change') }
    })
}
$result = [ordered]@{
    '$schema' = 'rule-issue-adjudication-draft-v4.schema.json'
    schemaVersion = 1
    kind = 'hosted-rule-issue-adjudication-draft'
    componentId = [string]$request.componentId
    relationshipDecisions = $decisions
    issues = $issues
}
$json = $result | ConvertTo-Json -Depth 100
if (-not ($json | Test-Json -SchemaFile $SchemaPath -ErrorAction Stop)) {
    throw 'Fixture adjudication does not satisfy its schema'
}
[IO.File]::WriteAllText($OutputPath, $json + "`n", [Text.UTF8Encoding]::new($false))
