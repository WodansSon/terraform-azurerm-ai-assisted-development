[CmdletBinding()]
param(
    [ValidateSet('Text', 'Json')][string]$OutputFormat = 'Text'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repositoryRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))
$validationOutputPath = Join-Path $repositoryRoot 'tools/ValidationOutput.psm1'
Import-Module -Name $validationOutputPath -Force
Import-Module (Join-Path $PSScriptRoot '../modules/shared/HostedToolkit.Helpers.psm1') -Force
$normalProfile = Resolve-HostedLlmProfile -Profile normal
$runnerPath = Join-Path $repositoryRoot 'hosted_copilot/tools/internal/reconciliation/Invoke-RuleIssueAdjudication.ps1'
$exporterPath = Join-Path $repositoryRoot 'hosted_copilot/tools/internal/reconciliation/Export-WorkbenchRuleIssues.ps1'
$fixturePath = Join-Path $PSScriptRoot 'fixtures/rule-issue-adjudication-evaluator.ps1'
$inputSchemaPath = Join-Path $repositoryRoot 'hosted_copilot/copilot-rule-catalog/assessment-reconciliation/rule-issue-adjudication-input-v4.schema.json'
$draftSchemaPath = Join-Path $repositoryRoot 'hosted_copilot/copilot-rule-catalog/assessment-reconciliation/rule-issue-adjudication-draft-v4.schema.json'
$promptPath = Join-Path $repositoryRoot 'hosted_copilot/tools/assessment-reconciliation-prompts/RuleIssueAdjudication-v4.md'
$results = [Collections.Generic.List[object]]::new()
$issues = [Collections.Generic.List[string]]::new()
$root = Join-Path ([IO.Path]::GetTempPath()) ('hosted-rule-issue-adjudication-test-' + [Guid]::NewGuid().ToString('N'))
$null = New-Item -ItemType Directory -Path $root -Force
$hash = 'a' * 64

function Set-SavedFixtureProposal {
    param([object]$Component, [string]$CandidateKey, [string]$Text)

    $proposal = @($Component.editContext.proposals | Where-Object candidateKey -CEQ $CandidateKey)[0]
    $operation = @($Component.operations | Where-Object candidateKey -CEQ $CandidateKey)[0]
    $rule = @($Component.rules | Where-Object id -CEQ $operation.ruleId)[0]
    $proposal.proposedText = $Text
    $proposal.ruleTextSha256 = Get-Sha256 -Content $Text
    $operation.proposedText = $Text
    $rule.text = $Text
    $rule.contentSha256 = $proposal.ruleTextSha256
    $Component.componentId = 'saved:' + $rule.id
    $Component.editContext.candidateKey = $CandidateKey
    $Component.editContext.baselineText = $proposal.baselineText
    $Component.editContext.baselineSha256 = Get-Sha256 -Content ([string]$proposal.baselineText)
    $Component.editContext.appendText = if ($Text.StartsWith([string]$proposal.baselineText, [StringComparison]::Ordinal)) { $Text.Substring(([string]$proposal.baselineText).Length) } else { $null }
    $Component.editContext.evaluationContextSha256 = '0' * 64
    $Component.editContext.evaluationContextSha256 = Get-JsonSnapshotSha256 -Value $Component -Depth 100
}

if ($OutputFormat -eq 'Text') {
    Write-ValidationSectionHeader -Title 'Hosted Rule Issue adjudication'
}

function Add-TestResult {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][bool]$Passed,
        [Parameter(Mandatory = $true)][string]$Detail
    )

    $results.Add([pscustomobject]@{ name = $Name; status = if ($Passed) { 'passed' } else { 'failed' }; detail = $Detail })
    if (-not $Passed) { $issues.Add("$Name`: $Detail") }
}

function Write-TestProgress {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][string]$Detail
    )

    if ($OutputFormat -eq 'Text') {
        Write-Host (Format-ValidationStatusLine -Status 'running' -Name $Name -Detail $Detail -NameWidth 42)
    }
}

function New-ComponentInput {
    param(
        [Parameter(Mandatory = $true)][string]$Id,
        [Parameter(Mandatory = $true)][string]$ContentSha256,
        [switch]$Independent,
        [switch]$InvalidReference
    )

    $suffix = if ($Independent) { 'independent' } elseif ($InvalidReference) { 'invalid-reference' } else { 'protected' }
    return [ordered]@{
        '$schema' = 'rule-issue-adjudication-input-v4.schema.json'
        schemaVersion = 1
        kind = 'hosted-rule-issue-adjudication-input'
        componentId = "component:$suffix-$Id"
        sourceFiles = @([ordered]@{ sourceDefinitionId = 'maintainer-proposals'; sourceId = "SOURCE-$Id"; contentSha256 = $ContentSha256 })
        rules = @(
            [ordered]@{ id = 'IMPL-WF-000'; status = 'protected'; title = 'Protected'; text = 'Canonical text.'; contentSha256 = $hash; candidateKeys = @() },
            [ordered]@{ id = "IMPL-TEST-$Id"; status = 'proposed'; title = 'Proposal'; text = 'Candidate text.'; contentSha256 = $ContentSha256; candidateKeys = @("maintainer:SOURCE-$Id:A1") }
        )
        relationships = @([ordered]@{ id = "relationship-$Id"; sourceRuleId = "IMPL-TEST-$Id"; relatedRuleId = 'IMPL-WF-000'; relationship = 'equivalent'; rationale = 'Provisional relationship.'; candidateKey = "maintainer:SOURCE-$Id:A1" })
        operations = @([ordered]@{ candidateKey = "maintainer:SOURCE-$Id:A1"; ruleId = "IMPL-TEST-$Id"; action = 'exclude'; proposedText = 'Candidate text.'; retireHostedRuleIds = @() })
    }
}

try {
    Write-TestProgress -Name 'registered-evaluator-boundaries' -Detail 'Checking injection boundaries across the registered prompt set'
    $authority = Get-Content -LiteralPath (Join-Path $repositoryRoot 'hosted_copilot/copilot-rule-catalog/assessment-reconciliation/rule-issue-adjudication-v4.json') -Raw | ConvertFrom-Json
    $registeredPrompts = @($authority.behaviorFiles | Where-Object { $_ -like '*/assessment-reconciliation-prompts/*.md' })
    $boundariesValid = $registeredPrompts.Count -eq 2
    foreach ($relativePath in $registeredPrompts) {
        $content = Get-Content -LiteralPath (Join-Path $repositoryRoot $relativePath) -Raw
        $boundary = ($content -split '(?m)^## Boundaries\s*$', 2)[-1]
        foreach ($required in @('source', 'assessment', 'catalog', 'untrusted quoted data', 'prompt injection', 'tool requests', 'role changes', 'output-format changes', 'policy claims')) {
            if ($content -notmatch '(?m)^## Boundaries\s*$' -or -not $boundary.Contains($required, [StringComparison]::OrdinalIgnoreCase)) { $boundariesValid = $false }
        }
    }
    Add-TestResult -Name 'registered-evaluator-boundaries' -Passed $boundariesValid -Detail 'Both registered saved-edit evaluators reject quoted-data instruction and authority changes.'

    Write-TestProgress -Name 'saved-edit-zero-edge-adjudication' -Detail 'Adjudicating scope even when the checker has no relationships'
    $baseline = 'Examples must remain copy-pasteable, valid HCL, and functional. Resource examples must declare their dependencies.'
    $saved = New-ComponentInput -Id '003' -ContentSha256 $hash
    $saved.componentId = 'saved:fixture'
    $saved.rules = @($saved.rules[1])
    $saved.rules[0].text = $baseline + ' Additional maintainer wording.'
    $saved.relationships = @()
    $saved.operations[0].action = 'add'
    $saved.operations[0].proposedText = $saved.rules[0].text
    $saved.editContext = [ordered]@{
        candidateKey = $saved.operations[0].candidateKey; baselineText = $baseline
        baselineSha256 = [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData([Text.Encoding]::UTF8.GetBytes($baseline))).ToLowerInvariant()
        appendText = ' Additional maintainer wording.'; evaluationContextSha256 = 'd' * 64
        assessmentContext = [ordered]@{
            catalogRules = @()
            sources = @([ordered]@{ candidateKey = $saved.operations[0].candidateKey; category = 'implementation'; sourceRules = @([ordered]@{ id = 'SOURCE-003'; text = $baseline; meaning = $baseline }) })
        }
        proposals = @([ordered]@{ candidateKey = $saved.operations[0].candidateKey; inPlan = $false; baselineText = $baseline; proposedText = $saved.rules[0].text; ruleTextSha256 = [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData([Text.Encoding]::UTF8.GetBytes([string]$saved.rules[0].text))).ToLowerInvariant(); retireHostedRuleIds = @() })
    }
    $savedPath = Join-Path $root 'saved-zero.json'
    [IO.File]::WriteAllText($savedPath, ($saved | ConvertTo-Json -Depth 100))
    $savedParameters = @{ ComponentPaths = @($savedPath); OutputPath = (Join-Path $root 'saved-zero-result.json'); CacheDirectory = (Join-Path $root 'saved-cache'); EvaluatorScriptPath = $fixturePath; OutputFormat = 'Json'; Quiet = $true }
    $null = & $runnerPath @savedParameters
    $zero = Get-Content -LiteralPath $savedParameters.OutputPath -Raw | ConvertFrom-Json -Depth 100
    Add-TestResult -Name 'saved-edit-zero-edge-adjudication' -Passed ($zero.components[0].scopeReview.disposition -ceq 'within-scope' -and @($zero.components[0].relationshipDecisions).Count -eq 0 -and @($zero.components[0].issues).Count -eq 0) -Detail 'An explicit edit context permits a one-rule zero-edge scope decision.'
    $ordinary = ($saved | ConvertTo-Json -Depth 100) | ConvertFrom-Json -Depth 100
    $ordinary.PSObject.Properties.Remove('editContext')
    Add-TestResult -Name 'ordinary-component-keeps-required-edges' -Passed (-not (($ordinary | ConvertTo-Json -Depth 100) | Test-Json -SchemaFile $inputSchemaPath -ErrorAction SilentlyContinue)) -Detail 'The zero-edge exception does not weaken ordinary rebuild components.'

    Write-TestProgress -Name 'saved-edit-extractive-recommendation' -Detail 'Checking full-baseline recommendation and literal evidence provenance'
    $saved.rules += [ordered]@{ id = 'IMPL-OTHER-003'; status = 'active'; title = 'Independent fixture rule'; text = 'A distinct fixture obligation remains active.'; contentSha256 = $hash; candidateKeys = @() }
    $saved.relationships = @([ordered]@{ id = 'saved-edge'; sourceRuleId = 'IMPL-TEST-003'; relatedRuleId = 'IMPL-OTHER-003'; relationship = 'partial-overlap'; rationale = 'Provisional fixture relationship.'; candidateKey = $saved.operations[0].candidateKey })
    $saved.rules[0].text = $baseline + ' Grouped review is required.'
    $saved.operations[0].proposedText = $saved.rules[0].text
    $saved.editContext.appendText = ' Grouped review is required.'
    $saved.editContext.proposals[0].proposedText = $saved.rules[0].text
    $saved.editContext.proposals[0].ruleTextSha256 = [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData([Text.Encoding]::UTF8.GetBytes([string]$saved.rules[0].text))).ToLowerInvariant()
    [IO.File]::WriteAllText($savedPath, ($saved | ConvertTo-Json -Depth 100))
    $savedParameters.OutputPath = Join-Path $root 'saved-grouped-result.json'
    $null = & $runnerPath @savedParameters
    $grouped = Get-Content -LiteralPath $savedParameters.OutputPath -Raw | ConvertFrom-Json -Depth 100
    $validDraft = $grouped.components[0]
    Add-TestResult -Name 'saved-edit-extractive-recommendation' -Passed ($validDraft.issues[0].recommendedMaintainerAction.operations[0].proposedText -ceq $baseline -and $validDraft.issues[0].recommendedMaintainerAction.operations[0].textSource -ceq 'baseline') -Detail 'The recommendation preserves the complete reconciled baseline rather than its shorter historical summary.'
    Add-TestResult -Name 'saved-edit-complete-reassessment' -Passed (@($validDraft.assessments).Count -eq 1 -and $validDraft.assessments[0].ruleTextSha256 -ceq $saved.editContext.proposals[0].ruleTextSha256 -and $validDraft.assessments[0].selectionFactors.severity -eq 5 -and $validDraft.assessments[0].selectionFactors.redundancy -eq $validDraft.assessments[0].existingCoverage.score) -Detail 'The result includes independently refreshed scoring, rationale, recommendation, applicability, and coverage bound to the complete saved wording.'
    $componentObject = ($saved | ConvertTo-Json -Depth 100) | ConvertFrom-Json -Depth 100
    foreach ($case in @('stale-context', 'invented-quote', 'truncated-baseline', 'invented-obligation', 'silent-retirement', 'missing-assessment', 'stale-assessment', 'duplicate-assessment', 'foreign-assessment', 'invalid-score', 'coverage-score-mismatch', 'foreign-coverage', 'invalid-recommendation')) {
        $invalid = ($validDraft | ConvertTo-Json -Depth 100) | ConvertFrom-Json -Depth 100
        switch ($case) {
            'stale-context' { $invalid.evaluationContextSha256 = 'e' * 64 }
            'invented-quote' { $invalid.scopeReview.baselineQuote = 'An invented baseline quotation.' }
            'truncated-baseline' { $invalid.issues[0].recommendedMaintainerAction.operations[0].proposedText = 'Examples must be functional.' }
            'invented-obligation' { $invalid.issues[0].recommendedMaintainerAction.operations[0].proposedText += ' Every example must declare seventeen input variables.' }
            'silent-retirement' { $invalid.issues[0].recommendedMaintainerAction.operations[0].retireHostedRuleIds = @('IMPL-OTHER-003') }
            'missing-assessment' { $invalid.assessments = @() }
            'stale-assessment' { $invalid.assessments[0].ruleTextSha256 = 'e' * 64 }
            'duplicate-assessment' { $invalid.assessments = @($invalid.assessments[0], $invalid.assessments[0]) }
            'foreign-assessment' { $invalid.assessments[0].candidateKey = 'fixture:foreign:A1' }
            'invalid-score' { $invalid.assessments[0].selectionFactors.severity = 6 }
            'coverage-score-mismatch' { $invalid.assessments[0].existingCoverage.score = 4 }
            'foreign-coverage' { $invalid.assessments[0].relatedHostedCoverage = @([pscustomobject]@{ hostedRuleId = 'UNKNOWN-RULE-001'; relationship = 'related'; rationale = 'Synthetic foreign reference.' }) }
            'invalid-recommendation' { $invalid.assessments[0].recommendation = 'retire' }
        }
        $rejected = $false
        try { Test-RuleIssueAdjudicationDraft -Component $componentObject -Draft $invalid } catch { $rejected = $true }
        Add-TestResult -Name "saved-edit-rejects-$case" -Passed $rejected -Detail "Deterministic validation rejects $case."
    }

    Write-TestProgress -Name 'saved-edit-multiple-assessments' -Detail 'Binding independent assessment results to every supplied proposal'
    $multiple = ($saved | ConvertTo-Json -Depth 100) | ConvertFrom-Json -Depth 100
    $siblingKey = 'maintainer:SOURCE-004:A1'
    $siblingBaseline = 'Preserve a separately sourced sibling obligation.'
    $siblingProposal = $siblingBaseline + ' Additional sibling wording.'
    $siblingHash = [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData([Text.Encoding]::UTF8.GetBytes($siblingProposal))).ToLowerInvariant()
    $multiple.rules += [pscustomobject]@{ id = 'IMPL-TEST-004'; status = 'proposed'; title = 'Sibling proposal'; text = $siblingBaseline; contentSha256 = [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData([Text.Encoding]::UTF8.GetBytes($siblingBaseline))).ToLowerInvariant(); candidateKeys = @($siblingKey) }
    $multiple.operations += [pscustomobject]@{ candidateKey = $siblingKey; ruleId = 'IMPL-TEST-004'; action = 'add'; proposedText = $siblingProposal; retireHostedRuleIds = @() }
    $multiple.relationships += [pscustomobject]@{ id = 'saved-sibling-edge'; sourceRuleId = 'IMPL-TEST-003'; relatedRuleId = 'IMPL-TEST-004'; relationship = 'partial-overlap'; rationale = 'The fixture includes a separate connected sibling proposal.'; candidateKey = $multiple.editContext.candidateKey }
    $multiple.editContext.proposals += [pscustomobject]@{ candidateKey = $siblingKey; inPlan = $false; baselineText = $siblingBaseline; proposedText = $siblingProposal; ruleTextSha256 = $siblingHash; retireHostedRuleIds = @() }
    $multiple.editContext.assessmentContext.sources += [pscustomobject]@{ candidateKey = $siblingKey; category = 'implementation'; sourceRules = @([pscustomobject]@{ id = 'SOURCE-004'; text = $siblingBaseline; meaning = $siblingBaseline }) }
    $multiplePath = Join-Path $root 'saved-multiple.json'
    [IO.File]::WriteAllText($multiplePath, ($multiple | ConvertTo-Json -Depth 100))
    $multipleParameters = @{ ComponentPaths = @($multiplePath); OutputPath = (Join-Path $root 'saved-multiple-result.json'); CacheDirectory = (Join-Path $root 'saved-multiple-cache'); EvaluatorScriptPath = $fixturePath; OutputFormat = 'Json'; Quiet = $true }
    $null = & $runnerPath @multipleParameters
    $multipleResult = Get-Content -LiteralPath $multipleParameters.OutputPath -Raw | ConvertFrom-Json -Depth 100
    $multipleDraft = $multipleResult.components[0]
    $siblingAssessment = @($multipleDraft.assessments | Where-Object candidateKey -CEQ $siblingKey)
    Add-TestResult -Name 'saved-edit-multiple-assessments' -Passed (@($multipleDraft.assessments).Count -eq 2 -and $siblingAssessment.Count -eq 1 -and $siblingAssessment[0].ruleTextSha256 -ceq $siblingHash -and $multipleDraft.assessments[0].ruleTextSha256 -cne $siblingHash) -Detail 'Every proposal receives its own complete assessment bound to its exact proposed text, even when a sibling working rule still contains its baseline.'
    foreach ($case in @('missing-sibling-assessment', 'swapped-proposal-assessments')) {
        $invalid = ($multipleDraft | ConvertTo-Json -Depth 100) | ConvertFrom-Json -Depth 100
        if ($case -ceq 'missing-sibling-assessment') {
            $invalid.assessments = @($invalid.assessments | Where-Object candidateKey -CNE $siblingKey)
        } else {
            $firstHash = $invalid.assessments[0].ruleTextSha256
            $invalid.assessments[0].ruleTextSha256 = $invalid.assessments[1].ruleTextSha256
            $invalid.assessments[1].ruleTextSha256 = $firstHash
        }
        $rejected = $false
        try { Test-RuleIssueAdjudicationDraft -Component $multiple -Draft $invalid } catch { $rejected = $true }
        Add-TestResult -Name "saved-edit-rejects-$case" -Passed $rejected -Detail "Deterministic validation rejects $case without accepting a partially reassessed proposal set."
    }

    Write-TestProgress -Name 'saved-edit-byte-bounded-stages' -Detail 'Evaluating more than 2.8 MB with exact per-request budgets and cross-batch issue grouping'
    $large = ($multiple | ConvertTo-Json -Depth 100) | ConvertFrom-Json -Depth 100
    $large.componentId = 'saved:large-bounded-fixture'
    $large.relationships = @()
    $large.rules = @($large.rules | Where-Object { $_.id -ceq 'IMPL-TEST-003' })
    $large.operations = @($large.operations | Where-Object candidateKey -CEQ $large.editContext.candidateKey)
    $large.editContext.proposals = @($large.editContext.proposals | Where-Object candidateKey -CEQ $large.editContext.candidateKey)
    $large.editContext.assessmentContext.sources = @($large.editContext.assessmentContext.sources | Where-Object candidateKey -CEQ $large.editContext.candidateKey)
    $catalogText = 'Preserve the independent existing Hosted fixture obligation.'
    $large.editContext.assessmentContext.catalogRules = @([pscustomobject]@{
        id = 'IMPL-CATALOG-001'; status = 'active'; title = 'Existing Hosted fixture'; text = $catalogText
        contentSha256 = Get-Sha256 -Content $catalogText; candidateKeys = @()
    })
    $large.rules += $large.editContext.assessmentContext.catalogRules
    $largeText = $baseline + ' Additional maintainer wording.'
    $large.rules[0].text = $largeText
    $large.rules[0].contentSha256 = Get-Sha256 -Content $largeText
    $large.operations[0].proposedText = $largeText
    $large.editContext.proposals[0].proposedText = $largeText
    $large.editContext.proposals[0].ruleTextSha256 = Get-Sha256 -Content $largeText
    $large.editContext.appendText = ' Additional maintainer wording.'
    $largeSource = 'Synthetic original source evidence. ' * 1200
    $large.editContext.assessmentContext.sources[0].sourceRules[0].text = $largeSource
    for ($index = 1; $index -le 71; $index++) {
        $id = 'IMPL-SCALE-{0:D3}' -f $index
        $key = "maintainer:SCALE-${index}:A1"
        $text = if ($index -in @(1, 71)) { "Preserve the shared fixture obligation. Grouped review is required. Member $index." } else { "Preserve independent fixture obligation $index." }
        $textHash = Get-Sha256 -Content $text
        $large.rules += [pscustomobject]@{ id = $id; status = 'proposed'; title = "Scale fixture $index"; text = $text; contentSha256 = $textHash; candidateKeys = @($key) }
        $large.operations += [pscustomobject]@{ candidateKey = $key; ruleId = $id; action = 'add'; proposedText = $text; retireHostedRuleIds = @() }
        $large.editContext.proposals += [pscustomobject]@{ candidateKey = $key; inPlan = $false; baselineText = "$text Original baseline wording."; proposedText = $text; ruleTextSha256 = $textHash; retireHostedRuleIds = @() }
        $large.editContext.assessmentContext.sources += [pscustomobject]@{ candidateKey = $key; category = 'implementation'; sourceRules = @([pscustomobject]@{ id = "SCALE-$index"; text = $largeSource; meaning = $text }) }
        $large.sourceFiles += [pscustomobject]@{ sourceDefinitionId = 'maintainer-proposals'; sourceId = "SCALE-$index"; contentSha256 = Get-Sha256 -Content $largeSource }
        $large.relationships += [pscustomobject]@{ id = "scale-edge-$index"; sourceRuleId = 'IMPL-TEST-003'; relatedRuleId = $id; relationship = 'partial-overlap'; rationale = ('Provisional fixture evidence. ' * 700); candidateKey = $large.editContext.candidateKey }
    }
    $activeFixture = @($large.rules | Where-Object id -CEQ 'IMPL-SCALE-035')[0]
    $activeFixture.status = 'active'
    @($large.operations | Where-Object ruleId -CEQ $activeFixture.id)[0].action = 'update'
    $large.editContext.assessmentContext.catalogRules += ($activeFixture | ConvertTo-Json -Depth 100 | ConvertFrom-Json -Depth 100)
    Write-TestProgress -Name 'saved-edit-cold-single-target' -Detail 'Keeping 71 untouched comparisons out of fresh assessment on a cold cache'
    $cold = $large | ConvertTo-Json -Depth 100 | ConvertFrom-Json -Depth 100 -DateKind String
    foreach ($proposal in @($cold.editContext.proposals | Where-Object candidateKey -CNE $cold.editContext.candidateKey)) {
        $proposal.baselineText = $proposal.proposedText
    }
    $cold.editContext.assessmentContext.sources = @($cold.editContext.assessmentContext.sources | Where-Object candidateKey -CEQ $cold.editContext.candidateKey)
    $cold.relationships = @($cold.relationships | Where-Object id -CIN @('scale-edge-35', 'scale-edge-36'))
    foreach ($edge in $cold.relationships) { $edge.rationale = 'A complete unchanged rule is supplied as comparison context.' }
    $coldPath = Join-Path $root 'cold-single-target.json'
    $coldMetricsPath = Join-Path $root 'cold-single-target.jsonl'
    [IO.File]::WriteAllText($coldPath, ($cold | ConvertTo-Json -Depth 100))
    $coldParameters = @{
        ComponentPaths = @($coldPath); OutputPath = (Join-Path $root 'cold-single-target-result.json')
        CacheDirectory = (Join-Path $root 'cold-single-target-cache'); EvaluatorScriptPath = $fixturePath
        EvaluatorCommand = "fixture-log:$coldMetricsPath"; OutputFormat = 'Json'; Quiet = $true; MaxRetries = 0
    }
    $null = & $runnerPath @coldParameters
    $coldMetrics = @(Get-Content -LiteralPath $coldMetricsPath | ForEach-Object { $_ | ConvertFrom-Json })
    $coldResult = Get-Content -LiteralPath $coldParameters.OutputPath -Raw | ConvertFrom-Json -Depth 100
    Add-TestResult -Name 'saved-edit-cold-single-target' -Passed ($coldMetrics.Count -eq 1 -and $coldMetrics[0].phase -ceq 'complete' -and @($coldMetrics[0].candidates).Count -eq 1 -and $coldMetrics[0].candidates[0] -ceq $cold.editContext.candidateKey -and $coldMetrics[0].reservedBytes -le 393216 -and @($coldResult.components[0].assessments).Count -eq 1 -and @($coldResult.components[0].relationshipDecisions).Count -eq 2 -and @($cold.editContext.proposals).Count -eq 72) -Detail 'One cold bounded call completes scope, the changed-rule assessment, and every affected relationship without scoring 71 unchanged comparison proposals.'
    $invalidCold = $coldResult.components[0] | ConvertTo-Json -Depth 100 | ConvertFrom-Json -Depth 100
    $comparisonAssessment = $invalidCold.assessments[0] | ConvertTo-Json -Depth 100 | ConvertFrom-Json
    $comparisonAssessment.candidateKey = $cold.editContext.proposals[1].candidateKey
    $comparisonAssessment.ruleTextSha256 = $cold.editContext.proposals[1].ruleTextSha256
    $invalidCold.assessments += $comparisonAssessment
    $comparisonRejected = $false
    try { Test-RuleIssueAdjudicationDraft -Component $cold -Draft $invalidCold } catch { $comparisonRejected = $true }
    Add-TestResult -Name 'saved-edit-rejects-fresh-unchanged-assessment' -Passed $comparisonRejected -Detail 'Unchanged comparison evidence cannot be relabelled as a fresh assessment.'
    Write-TestProgress -Name 'saved-edit-native-inline-context' -Detail 'Exercising production CLI stdin, exact evidence, JSONL, and stderr boundaries without an AI call'
    $nativeMetricsPath = Join-Path $root 'native-inline-metrics.jsonl'
    $previousNativeMetricsPath = [Environment]::GetEnvironmentVariable('HOSTED_TEST_COPILOT_METRICS')
    try {
        [Environment]::SetEnvironmentVariable('HOSTED_TEST_COPILOT_METRICS', $nativeMetricsPath)
        $nativeCommand = Join-Path $PSScriptRoot 'fixtures/copilot-inline-evaluator.ps1'
        $nativeManualPath = Join-Path $root 'native-manual-request.json'
        [IO.File]::WriteAllText($nativeManualPath, ([ordered]@{
            candidateKey = $cold.editContext.candidateKey; category = 'implementation'; placement = 'Fixture'
            ruleId = 'IMPL-TEST-003'; ruleTextBase64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($largeText))
        } | ConvertTo-Json))
        $null = & (Join-Path $repositoryRoot 'hosted_copilot/tools/internal/reconciliation/Invoke-ManualRuleRelationship.ps1') `
            -RequestPath $nativeManualPath -OutputPath (Join-Path $root 'native-manual-result.json') `
            -RepositoryRoot $repositoryRoot -CacheDirectory (Join-Path $root 'native-manual-cache') -EvaluatorCommand $nativeCommand
        $nativeParameters = @{} + $coldParameters
        $null = $nativeParameters.Remove('EvaluatorScriptPath')
        $nativeParameters.EvaluatorCommand = $nativeCommand
        $nativeParameters.CacheDirectory = Join-Path $root 'native-adjudication-cache'
        $nativeParameters.OutputPath = Join-Path $root 'native-adjudication-result.json'
        $null = & $runnerPath @nativeParameters
    }
    finally {
        [Environment]::SetEnvironmentVariable('HOSTED_TEST_COPILOT_METRICS', $previousNativeMetricsPath)
    }
    $nativeMetrics = @(Get-Content -LiteralPath $nativeMetricsPath | ForEach-Object { $_ | ConvertFrom-Json })
    $nativeResult = Get-Content -LiteralPath $nativeParameters.OutputPath -Raw | ConvertFrom-Json -Depth 100
    Add-TestResult -Name 'saved-edit-native-inline-context' -Passed ($nativeMetrics.Count -eq 2 -and $nativeMetrics[0].manual -and -not $nativeMetrics[1].manual -and $nativeMetrics[0].fileCount -eq 2 -and $nativeMetrics[1].fileCount -eq 5 -and $nativeMetrics[1].bytes -le 393216 -and @($nativeMetrics[1].candidates).Count -eq 1 -and @($nativeMetrics | Where-Object { $_.model -cne $normalProfile.model -or $_.effort -cne $normalProfile.reasoningEffort }).Count -eq 0 -and @($nativeResult.components[0].assessments).Count -eq 1) -Detail 'Discovery and adjudication use full validated inline evidence with the resolved normal model and effort; stdout JSONL is isolated from legitimate stderr diagnostics.'
    Write-TestProgress -Name 'manual-schema-failure-diagnostics' -Detail 'Retaining safe schema details after native discovery input cleanup'
    $invalidManualCommand = Join-Path $root 'invalid-manual-cli.ps1'
    $invalidManualScript = @'
$null = [Console]::In.ReadToEnd()
    $modelIndex = [Array]::IndexOf($args, '--model')
    [ordered]@{ type = 'assistant.message'; data = [ordered]@{ model = [string]$args[$modelIndex + 1]; content = '{"synthetic":"SYNTHETIC_SENSITIVE_VALUE"}' } } | ConvertTo-Json -Compress
'@
    [IO.File]::WriteAllText($invalidManualCommand, $invalidManualScript)
    $manualFailureMessage = ''
    $manualFailureDirectory = ''
    $manualDiagnosticPassed = $false
    try {
        try {
            $null = & (Join-Path $repositoryRoot 'hosted_copilot/tools/internal/reconciliation/Invoke-ManualRuleRelationship.ps1') `
                -RequestPath $nativeManualPath -OutputPath (Join-Path $root 'invalid-manual-result.json') `
                -RepositoryRoot $repositoryRoot -CacheDirectory (Join-Path $root 'invalid-manual-cache') -EvaluatorCommand $invalidManualCommand
        }
        catch { $manualFailureMessage = [string]$_.Exception.Message }
        $marker = 'Diagnostic metadata retained at '
        $offset = $manualFailureMessage.IndexOf($marker, [StringComparison]::Ordinal)
        if ($offset -ge 0) {
            $manualFailureDirectory = $manualFailureMessage.Substring($offset + $marker.Length)
            $failureJson = Get-Content -LiteralPath (Join-Path $manualFailureDirectory 'failure.json') -Raw
            $failure = $failureJson | ConvertFrom-Json -DateKind String
            $runId = [IO.Path]::GetFileName($manualFailureDirectory).Substring('hosted-manual-rule-failure-'.Length)
            $manualDiagnosticPassed = $failure.phase -ceq 'schema-validation' -and $failure.responseDiagnostic.schemaDiagnostic.available -and
                'required' -cin @($failure.responseDiagnostic.schemaDiagnostic.errors | ForEach-Object keyword) -and
                $manualFailureMessage.Contains('failed schema keywords:') -and -not $failureJson.Contains('SYNTHETIC_SENSITIVE_VALUE') -and
                -not (Test-Path -LiteralPath (Join-Path ([IO.Path]::GetTempPath()) "hosted-manual-rule-$runId")) -and
                -not (Test-Path -LiteralPath (Join-Path $root 'invalid-manual-result.json')) -and
                @(Get-ChildItem -LiteralPath $manualFailureDirectory -File).Count -eq 1
        }
    }
    finally {
        if (-not [string]::IsNullOrWhiteSpace($manualFailureDirectory) -and
            [IO.Path]::GetFileName($manualFailureDirectory) -match '^hosted-manual-rule-failure-[0-9a-f]{32}$') {
            Remove-Item -LiteralPath $manualFailureDirectory -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
    Add-TestResult -Name 'manual-schema-failure-diagnostics' -Passed $manualDiagnosticPassed -Detail 'Native manual discovery preserves schema keywords and schema-owned paths, deletes raw inputs, and never publishes or caches the invalid response.'
    $largePath = Join-Path $root 'large-component.json'
    [IO.File]::WriteAllText($largePath, ($large | ConvertTo-Json -Depth 100))
    $metricsPath = Join-Path $root 'large-metrics.jsonl'
    $largeParameters = @{
        ComponentPaths = @($largePath); OutputPath = (Join-Path $root 'large-result.json')
        CacheDirectory = (Join-Path $root 'large-cache'); EvaluatorScriptPath = $fixturePath
        EvaluatorCommand = "fixture-log:$metricsPath"; OutputFormat = 'Json'; Quiet = $true; MaxParallelShards = 1; MaxRetries = 0
    }
    $largeRun = & $runnerPath @largeParameters | ConvertFrom-Json
    $largeResult = Get-Content -LiteralPath $largeParameters.OutputPath -Raw | ConvertFrom-Json -Depth 100
    $metrics = @(Get-Content -LiteralPath $metricsPath | ForEach-Object { $_ | ConvertFrom-Json })
    $assessmentMetrics = @($metrics | Where-Object phase -CEQ assessment)
    $relationshipMetrics = @($metrics | Where-Object phase -CEQ relationships)
    $coveredKeys = @($assessmentMetrics | ForEach-Object candidates)
    Add-TestResult -Name 'saved-edit-byte-bounded-stages' -Passed ((Get-Item -LiteralPath $largePath).Length -gt 2800000 -and $assessmentMetrics.Count -gt 1 -and $relationshipMetrics.Count -gt 1 -and @($metrics | Where-Object reservedBytes -GT 393216).Count -eq 0) -Detail 'A multi-megabyte saved-edit component uses multiple assessment and relationship requests; every actual serialized evaluator request, artifacts, and retry reserve fit the unchanged 393216-byte budget.'
    Add-TestResult -Name 'saved-edit-source-and-proposal-completeness' -Passed ($coveredKeys.Count -eq 72 -and @($coveredKeys | Sort-Object -CaseSensitive -Unique).Count -eq 72 -and ($assessmentMetrics.sourceCharacters | Measure-Object -Sum).Sum -eq ($largeSource.Length * 72) -and @($largeResult.components[0].assessments).Count -eq 72 -and @($largeResult.components[0].relationshipDecisions).Count -eq 71) -Detail 'Every complete source text and exact proposal is assessed once; merged results cover every proposal and provisional relationship.'
    $largeIssues = @($largeResult.components[0].issues)
    Add-TestResult -Name 'saved-edit-cross-batch-grouping' -Passed ($largeIssues.Count -eq 1 -and @($largeIssues[0].relationshipIds).Count -eq 2 -and 'scale-edge-1' -cin $largeIssues[0].relationshipIds -and 'scale-edge-71' -cin $largeIssues[0].relationshipIds) -Detail 'Material relationships from separated routing batches produce one coherent three-rule issue, not two pairwise issues.'
    $largeParameters.OutputPath = Join-Path $root 'large-cached-result.json'
    $largeCached = & $runnerPath @largeParameters | ConvertFrom-Json
    Add-TestResult -Name 'saved-edit-bounded-cache' -Passed ([int]$largeCached.evaluatedComponentCount -eq 0 -and [int]$largeCached.cachedComponentCount -eq [int]$largeRun.evaluatedComponentCount -and @(Get-Content -LiteralPath $metricsPath).Count -eq $metrics.Count) -Detail 'All bounded phase results reuse the existing authority-bound shard cache without another evaluator invocation.'
    Write-TestProgress -Name 'saved-edit-incremental-cache' -Detail 'Changing active and proposed wording without reevaluating unchanged assessments or pair decisions'
    $incremental = ($large | ConvertTo-Json -Depth 100) | ConvertFrom-Json -Depth 100
    $incrementalKey = 'maintainer:SCALE-35:A1'
    $incrementalText = @($incremental.editContext.proposals | Where-Object candidateKey -CEQ $incrementalKey)[0].proposedText + (' Additional exact saved wording.' * 300)
    Set-SavedFixtureProposal -Component $incremental -CandidateKey $incrementalKey -Text $incrementalText
    [IO.File]::WriteAllText($largePath, ($incremental | ConvertTo-Json -Depth 100))
    $largeParameters.OutputPath = Join-Path $root 'large-active-edit-result.json'
    $beforeCalls = @(Get-Content -LiteralPath $metricsPath).Count
    $activeEditRun = & $runnerPath @largeParameters | ConvertFrom-Json
    $activeEdit = Get-Content -LiteralPath $largeParameters.OutputPath -Raw | ConvertFrom-Json -Depth 100
    $editMetrics = @(Get-Content -LiteralPath $metricsPath | Select-Object -Skip $beforeCalls | ForEach-Object { $_ | ConvertFrom-Json })
    $assessedKeys = @($editMetrics | Where-Object phase -CEQ assessment | ForEach-Object candidates)
    $comparedIds = @($editMetrics | Where-Object phase -CEQ relationships | ForEach-Object relationships)
    Add-TestResult -Name 'saved-edit-active-wording-reuses-unaffected-items' -Passed ($assessedKeys.Count -eq 1 -and $assessedKeys[0] -ceq $incrementalKey -and $comparedIds.Count -eq 1 -and $comparedIds[0] -ceq 'scale-edge-35' -and @($editMetrics | Where-Object phase -CEQ issues).Count -eq 0 -and [int]$activeEditRun.cachedComponentCount -gt 100) -Detail 'An active rule edit reevaluates only its assessment and affected pair, not other assessments against the unmodified catalog; dependent scope checks run, while an unchanged issue group is reused.'
    Add-TestResult -Name 'saved-edit-incremental-complete-current-binding' -Passed (@($activeEdit.components[0].assessments).Count -eq 72 -and @($activeEdit.components[0].relationshipDecisions).Count -eq 71 -and $activeEdit.components[0].evaluationContextSha256 -ceq $incremental.editContext.evaluationContextSha256 -and @($activeEdit.components[0].assessments | Where-Object candidateKey -CEQ $incrementalKey)[0].ruleTextSha256 -ceq (Get-Sha256 -Content $incrementalText)) -Detail 'Reused and fresh semantic results compose into a complete result bound to the current whole draft and exact changed wording.'
    $proposedKey = 'maintainer:SCALE-36:A1'
    $proposedText = @($incremental.editContext.proposals | Where-Object candidateKey -CEQ $proposedKey)[0].proposedText + ' Changed proposed wording.'
    Set-SavedFixtureProposal -Component $incremental -CandidateKey $proposedKey -Text $proposedText
    [IO.File]::WriteAllText($largePath, ($incremental | ConvertTo-Json -Depth 100))
    $largeParameters.OutputPath = Join-Path $root 'large-proposed-edit-result.json'
    $beforeCalls = @(Get-Content -LiteralPath $metricsPath).Count
    $null = & $runnerPath @largeParameters
    $editMetrics = @(Get-Content -LiteralPath $metricsPath | Select-Object -Skip $beforeCalls | ForEach-Object { $_ | ConvertFrom-Json })
    Add-TestResult -Name 'saved-edit-only-dirty-items-reach-evaluator' -Passed ($editMetrics.Count -eq 3 -and @($editMetrics | Where-Object phase -CEQ assessment | ForEach-Object candidates).Count -eq 1 -and @($editMetrics | Where-Object phase -CEQ assessment)[0].candidates[0] -ceq $proposedKey -and @($editMetrics | Where-Object phase -CEQ relationships)[0].relationships[0] -ceq 'scale-edge-36' -and @($editMetrics | Where-Object phase -CEQ scope)[0].scopeCandidate -ceq $proposedKey) -Detail 'Switching the edited candidate reevaluates exactly one scope, one assessment, and one affected pair; unchanged members of old batches and unrelated connected issues never reach the evaluator.'
    $materialKey = 'maintainer:SCALE-71:A1'
    $materialText = @($incremental.editContext.proposals | Where-Object candidateKey -CEQ $materialKey)[0].proposedText + ' Changed grouped wording.'
    Set-SavedFixtureProposal -Component $incremental -CandidateKey $materialKey -Text $materialText
    [IO.File]::WriteAllText($largePath, ($incremental | ConvertTo-Json -Depth 100))
    $largeParameters.OutputPath = Join-Path $root 'large-material-edit-result.json'
    $beforeCalls = @(Get-Content -LiteralPath $metricsPath).Count
    $null = & $runnerPath @largeParameters
    $editMetrics = @(Get-Content -LiteralPath $metricsPath | Select-Object -Skip $beforeCalls | ForEach-Object { $_ | ConvertFrom-Json })
    $materialResult = Get-Content -LiteralPath $largeParameters.OutputPath -Raw | ConvertFrom-Json -Depth 100
    Add-TestResult -Name 'saved-edit-dirty-group-reuses-unchanged-routing' -Passed ($editMetrics.Count -eq 4 -and @($editMetrics | Where-Object phase -CEQ issues).Count -eq 1 -and @($editMetrics | Where-Object phase -CEQ relationships | ForEach-Object relationships).Count -eq 1 -and @($editMetrics | Where-Object phase -CEQ relationships)[0].relationships[0] -ceq 'scale-edge-71' -and @($materialResult.components[0].issues[0].relationshipIds).Count -eq 2) -Detail 'Changing a material member refreshes only its scope, assessment, pair, and affected connected issue, while preserving the cached decision for the other edge in that group.'
    $rebound = ($large | ConvertTo-Json -Depth 100) | ConvertFrom-Json -Depth 100
    $rebound.editContext.evaluationContextSha256 = 'f' * 64
    [IO.File]::WriteAllText($largePath, ($rebound | ConvertTo-Json -Depth 100))
    $largeParameters.OutputPath = Join-Path $root 'large-rebound-result.json'
    $beforeCalls = @(Get-Content -LiteralPath $metricsPath).Count
    $reboundRun = & $runnerPath @largeParameters | ConvertFrom-Json
    $reboundResult = Get-Content -LiteralPath $largeParameters.OutputPath -Raw | ConvertFrom-Json -Depth 100
    Add-TestResult -Name 'saved-edit-global-binding-does-not-flush-semantic-cache' -Passed ([int]$reboundRun.evaluatedComponentCount -eq 0 -and @(Get-Content -LiteralPath $metricsPath).Count -eq $beforeCalls -and $reboundResult.components[0].evaluationContextSha256 -ceq $rebound.editContext.evaluationContextSha256) -Detail 'Restoring exact prior semantic inputs under a different complete-draft binding reuses all validated results while publishing only the current binding.'
    [IO.File]::WriteAllText($largePath, ($large | ConvertTo-Json -Depth 100))
    $largeParameters.CacheDirectory = Join-Path $root 'large-failure-cache'
    $largeParameters.OutputPath = Join-Path $root 'large-failed-result.json'
    [IO.File]::WriteAllText($metricsPath + '.fail-phase', 'issues')
    $retainedRun = $null
    $failedAtomically = $false
    try { $null = & $runnerPath @largeParameters } catch {
        $failedAtomically = $_.Exception.Message -like '*Synthetic issues evaluator failure*' -and -not (Test-Path -LiteralPath $largeParameters.OutputPath)
        if ($_.Exception.Message -match 'Run artifacts were retained at ([^\r\n]+)$') { $retainedRun = $Matches[1] }
    }
    Add-TestResult -Name 'saved-edit-bounded-failure-is-atomic' -Passed ($failedAtomically -and $null -ne $retainedRun) -Detail 'A failed final synthesis publishes no partial result and retains completed bounded work for resume.'
    Remove-Item -LiteralPath ($metricsPath + '.fail-phase') -Force
    $largeParameters.OutputPath = Join-Path $root 'large-automatic-retry-result.json'
    $beforeCalls = @(Get-Content -LiteralPath $metricsPath).Count
    $automaticRetry = & $runnerPath @largeParameters | ConvertFrom-Json
    $retryMetrics = @(Get-Content -LiteralPath $metricsPath | Select-Object -Skip $beforeCalls | ForEach-Object { $_ | ConvertFrom-Json })
    Add-TestResult -Name 'saved-edit-failed-check-retries-only-unfinished-work' -Passed ([int]$automaticRetry.evaluatedComponentCount -eq 1 -and [int]$automaticRetry.cachedComponentCount -gt 100 -and $retryMetrics.Count -eq 1 -and $retryMetrics[0].phase -ceq 'issues') -Detail 'An ordinary retry without a resume parameter reuses individually persisted successful work after a failed final stage and evaluates only the unfinished issue group.'
    if ($null -ne $retainedRun) {
        $largeParameters.ResumeRunDirectory = $retainedRun
        try {
            $resumed = & $runnerPath @largeParameters | ConvertFrom-Json
            Add-TestResult -Name 'saved-edit-bounded-resume' -Passed ([int]$resumed.evaluatedComponentCount -eq 0 -and [int]$resumed.cachedComponentCount -gt 1) -Detail 'Explicit resume validates the complete original authority and merges the retained run with current matching persistent results, including the group completed by an ordinary retry.'
        }
        finally { Remove-Item -LiteralPath $retainedRun -Recurse -Force }
    }

    $componentPaths = [Collections.Generic.List[string]]::new()
    foreach ($definition in @(@{ Id = '001'; Independent = $false }, @{ Id = '002'; Independent = $true })) {
        $path = Join-Path $root "$($definition.Id).json"
        [IO.File]::WriteAllText($path, (((New-ComponentInput -Id $definition.Id -ContentSha256 $hash -Independent:$definition.Independent) | ConvertTo-Json -Depth 30) + "`n"), [Text.UTF8Encoding]::new($false))
        $componentPaths.Add($path)
    }
    $parameters = @{
        ComponentPaths = $componentPaths.ToArray()
        OutputPath = Join-Path $root 'first.json'
        CacheDirectory = Join-Path $root 'cache'
        EvaluatorScriptPath = $fixturePath
        InputSchemaPath = $inputSchemaPath
        DraftSchemaPath = $draftSchemaPath
        PromptPath = $promptPath
        OutputFormat = 'Json'
        Quiet = $true
    }
    Write-TestProgress -Name 'first-run-evaluates-components' -Detail 'Evaluating every uncached Rule Issue component'
    $first = & $runnerPath @parameters | ConvertFrom-Json
    $firstSet = Get-Content -LiteralPath $parameters.OutputPath -Raw | ConvertFrom-Json -Depth 100
    Add-TestResult -Name 'first-run-evaluates-components' -Passed ([int]$first.evaluatedComponentCount -eq 2 -and [int]$first.cachedComponentCount -eq 0) -Detail 'The first run evaluates every uncached component.'
    Write-TestProgress -Name 'hierarchical-adjudication-cache' -Detail 'Checking v2 adjudication shards and legacy cache exclusion'
    $hierarchicalCachePath = Join-Path $parameters.CacheDirectory 'hierarchical-reconciliation-cache.json'
    $hierarchicalCache = Get-Content -LiteralPath $hierarchicalCachePath -Raw | ConvertFrom-Json -DateKind String
    $hierarchicalCacheValid = [int]$hierarchicalCache.schemaVersion -eq 2 -and
        [string]$hierarchicalCache.kind -ceq 'hosted-hierarchical-reconciliation-cache' -and
        @($hierarchicalCache.entries).Count -eq 2 -and
        @($hierarchicalCache.entries | Where-Object { [string]$_.stage -cne 'adjudication' -or [string]$_.shardKey -cnotmatch '^adjudication:[0-9a-f]{64}$' }).Count -eq 0 -and
        -not (Test-Path -LiteralPath (Join-Path $parameters.CacheDirectory 'rule-issue-adjudication-cache.json') -PathType Leaf)
    Add-TestResult -Name 'hierarchical-adjudication-cache' -Passed $hierarchicalCacheValid -Detail 'Rule Issue components use only v2 adjudication shards and never create the legacy component ledger.'
    Write-TestProgress -Name 'independent-component-produces-no-issue' -Detail 'Checking rejection of a provisional relationship'
    Add-TestResult -Name 'independent-component-produces-no-issue' -Passed (@($firstSet.components | Where-Object componentId -like '*independent*' | ForEach-Object { @($_.issues).Count })[0] -eq 0) -Detail 'AI can reject every provisional edge without producing a Rule Issue.'
    Write-TestProgress -Name 'protected-canonical-wording' -Detail 'Checking immutable protected wording'
    $protectedIssue = @($firstSet.components | Where-Object componentId -like '*protected*')[0].issues[0]
    Add-TestResult -Name 'protected-canonical-wording' -Passed ([string]$protectedIssue.wording.status -ceq 'canonical' -and [string]$protectedIssue.wording.text -ceq 'Canonical text.') -Detail 'Protected adjudication preserves exact canonical wording.'

    Write-TestProgress -Name 'second-run-reuses-components' -Detail 'Reusing unchanged adjudication shards'
    $parameters.OutputPath = Join-Path $root 'second.json'
    $second = & $runnerPath @parameters | ConvertFrom-Json
    Add-TestResult -Name 'second-run-reuses-components' -Passed ([int]$second.cachedComponentCount -eq 2 -and [int]$second.evaluatedComponentCount -eq 0) -Detail 'Unchanged component source and rule hashes reuse cached adjudication.'

    Write-TestProgress -Name 'changed-component-reevaluates-only-itself' -Detail 'Invalidating only the changed component shard'
    $changed = New-ComponentInput -Id '001' -ContentSha256 ('b' * 64)
    [IO.File]::WriteAllText($componentPaths[0], (($changed | ConvertTo-Json -Depth 30) + "`n"), [Text.UTF8Encoding]::new($false))
    $parameters.OutputPath = Join-Path $root 'third.json'
    $third = & $runnerPath @parameters | ConvertFrom-Json
    Add-TestResult -Name 'changed-component-reevaluates-only-itself' -Passed ([int]$third.cachedComponentCount -eq 1 -and [int]$third.evaluatedComponentCount -eq 1) -Detail 'A changed direct source hash invalidates only its component adjudication.'

    Write-TestProgress -Name 'behavior-change-invalidates-cache' -Detail 'Binding cache authority to every declared behavior file'
    $authorityRepositoryRoot = Join-Path $root 'authority-repository'
    $null = New-Item -ItemType Directory -Path $authorityRepositoryRoot -Force
    $authorityBehaviorPath = Join-Path $authorityRepositoryRoot 'behavior.ps1'
    $authorityPresentationPath = Join-Path $authorityRepositoryRoot 'presentation.psm1'
    [IO.File]::WriteAllText($authorityBehaviorPath, "'first'`n", [Text.UTF8Encoding]::new($false))
    [IO.File]::WriteAllText($authorityPresentationPath, "'first presentation'`n", [Text.UTF8Encoding]::new($false))
    $authorityContractPath = Join-Path $root 'rule-issue-adjudication-v4.json'
    $authorityContract = [ordered]@{ '$schema' = 'rule-issue-adjudication-contract.schema.json'; schemaVersion = 1; contractId = 'rule-issue-adjudication-v4'; behaviorFiles = @('behavior.ps1'); presentationFiles = @('presentation.psm1') }
    [IO.File]::WriteAllText($authorityContractPath, (($authorityContract | ConvertTo-Json -Depth 10) + "`n"), [Text.UTF8Encoding]::new($false))
    $authorityParameters = @{} + $parameters
    $authorityParameters.RepositoryRoot = $authorityRepositoryRoot
    $authorityParameters.AdjudicationContractPath = $authorityContractPath
    $authorityParameters.ContractSchemaPath = Join-Path $repositoryRoot 'hosted_copilot/copilot-rule-catalog/assessment-reconciliation/rule-issue-adjudication-contract.schema.json'
    $authorityParameters.CacheDirectory = Join-Path $root 'authority-cache'
    $authorityParameters.OutputPath = Join-Path $root 'authority-first.json'
    $authorityFirst = & $runnerPath @authorityParameters | ConvertFrom-Json
    $authorityParameters.OutputPath = Join-Path $root 'authority-second.json'
    $authoritySecond = & $runnerPath @authorityParameters | ConvertFrom-Json
    [IO.File]::WriteAllText($authorityPresentationPath, "'second presentation'`n", [Text.UTF8Encoding]::new($false))
    $authorityParameters.OutputPath = Join-Path $root 'authority-presentation.json'
    $authorityPresentation = & $runnerPath @authorityParameters | ConvertFrom-Json
    [IO.File]::WriteAllText($authorityBehaviorPath, "'second'`n", [Text.UTF8Encoding]::new($false))
    $authorityParameters.OutputPath = Join-Path $root 'authority-behavior.json'
    $authorityBehavior = & $runnerPath @authorityParameters | ConvertFrom-Json
    $behaviorAuthorityValid = [int]$authorityFirst.evaluatedComponentCount -eq 2 -and
        [int]$authoritySecond.cachedComponentCount -eq 2 -and
        [int]$authorityPresentation.cachedComponentCount -eq 2 -and
        [int]$authorityPresentation.evaluatedComponentCount -eq 0 -and
        [int]$authorityBehavior.cachedComponentCount -eq 0 -and
        [int]$authorityBehavior.evaluatedComponentCount -eq 2
    Add-TestResult -Name 'behavior-change-invalidates-cache' -Passed $behaviorAuthorityValid -Detail 'Presentation-only changes preserve adjudication cache reuse while declared semantic behavior changes invalidate every shard.'

    Write-TestProgress -Name 'non-member-rule-reference-rejected' -Detail 'Rejecting visible references to non-member rule IDs'
    $invalidReferencePath = Join-Path $root 'invalid-reference.json'
    [IO.File]::WriteAllText($invalidReferencePath, (((New-ComponentInput -Id '003' -ContentSha256 $hash -InvalidReference) | ConvertTo-Json -Depth 30) + "`n"), [Text.UTF8Encoding]::new($false))
    $invalidReferenceParameters = @{
        ComponentPaths = @($invalidReferencePath)
        OutputPath = Join-Path $root 'invalid-reference-result.json'
        CacheDirectory = Join-Path $root 'invalid-reference-cache'
        EvaluatorScriptPath = $fixturePath
        InputSchemaPath = $inputSchemaPath
        DraftSchemaPath = $draftSchemaPath
        PromptPath = $promptPath
        MaxRetries = 0
        OutputFormat = 'Json'
        Quiet = $true
    }
    $invalidReferenceRejected = $false
    try {
        & $runnerPath @invalidReferenceParameters | Out-Null
    }
    catch {
        $invalidReferenceRejected = [string]$_.Exception.Message -match 'non-member rule ID IMPL-FAKE-999'
    }
    Add-TestResult -Name 'non-member-rule-reference-rejected' -Passed $invalidReferenceRejected -Detail 'Visible AI-authored issue prose cannot reference a rule ID outside that issue membership.'

    Write-TestProgress -Name 'exporter-uses-reconciliation-authority' -Detail 'Checking provisional relationship ownership'
    $exporterText = Get-Content -LiteralPath $exporterPath -Raw
    $authorityBoundary = $exporterText -match 'candidate\.recommendation\.relatedHostedCoverage' -and $exporterText -match 'Candidate\.members' -and $exporterText -notmatch 'candidate\.assessment\.relatedHostedCoverage' -and $exporterText -notmatch '\$actionable\s*='
    Add-TestResult -Name 'exporter-uses-reconciliation-authority' -Passed $authorityBoundary -Detail 'The exporter builds provisional edges from reconciliation output and contains no action-based semantic heuristic.'

}
catch {
    Add-TestResult -Name 'unexpected-exception' -Passed $false -Detail $_.Exception.Message
}
finally {
    Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
}

$result = [ordered]@{
    status = if ($issues.Count -eq 0) { 'passed' } else { 'failed' }
    testCount = $results.Count
    issueCount = $issues.Count
    tests = $results.ToArray()
    issues = $issues.ToArray()
}
if ($OutputFormat -eq 'Json') {
    $result | ConvertTo-Json -Depth 10
}
else {
    Write-ValidationSectionHeader -Title 'Hosted Rule Issue adjudication test summary'
    Write-ValidationSummary -Fields ([ordered]@{ Status = $result.status.ToUpperInvariant(); Tests = $result.testCount; Issues = $result.issueCount })
    Write-ValidationSectionHeader -Title 'Rule Issue adjudication tests'
    Write-ValidationTwoColumnTable -Rows @($results | ForEach-Object { [pscustomobject]@{ Status = $_.status; Test = $_.name } }) -FirstHeader 'Status' -FirstProperty 'Status' -SecondHeader 'Test' -SecondProperty 'Test' -UppercaseFirst
    if ($issues.Count -gt 0) {
        Write-ValidationSectionHeader -Title 'Failures'
        foreach ($issue in $issues) {
            Write-Output "  - $issue"
        }
    }
    Complete-ValidationTextOutput
}
if ($issues.Count -gt 0) { exit 1 }
