[CmdletBinding()]
param(
    [ValidateSet('Text', 'Json')]
    [string]$OutputFormat = 'Text'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repositoryRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))
$validationOutputModulePath = Join-Path $repositoryRoot 'tools/ValidationOutput.psm1'
Import-Module -Name $validationOutputModulePath -Force
$catalogRoot = Join-Path $repositoryRoot 'hosted_copilot/copilot-rule-catalog'
$reconciliationRoot = Join-Path $catalogRoot 'assessment-reconciliation'
$assessmentRoot = Join-Path $catalogRoot 'rule-assessments'
$results = [Collections.Generic.List[object]]::new()
$issues = [Collections.Generic.List[string]]::new()
$hash = 'a' * 64
$timestamp = '2026-09-19T12:00:00Z'

function Test-JsonInstance {
    param(
        [Parameter(Mandatory = $true)][object]$Value,
        [Parameter(Mandatory = $true)][string]$SchemaPath
    )

    try {
        return [bool](($Value | ConvertTo-Json -Depth 100) | Test-Json -SchemaFile $SchemaPath -ErrorAction Stop)
    }
    catch {
        return $false
    }
}

function Copy-JsonValue {
    param([Parameter(Mandatory = $true)][object]$Value)

    return ($Value | ConvertTo-Json -Depth 100 -Compress) | ConvertFrom-Json -DateKind String
}

function Add-TestResult {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][bool]$Passed,
        [Parameter(Mandatory = $true)][string]$Detail
    )

    $results.Add([pscustomobject]@{ name = $Name; status = if ($Passed) { 'passed' } else { 'failed' }; detail = $Detail })
    if (-not $Passed) {
        $issues.Add("$Name`: $Detail")
    }
}

$capacityReports = @('repository', 'go', 'test', 'documentation', 'skill', 'go-combined', 'test-combined', 'documentation-combined') | ForEach-Object {
    [ordered]@{
        name = $_
        kind = if ($_ -like '*-combined') { 'combined' } else { 'file' }
        paths = @("fixture/$_.md")
        characterCount = 400
        estimatedTokens = 100
        guardedTokens = 125
        budgetTokens = 1000
        budgetHeadroomTokens = 875
        utilizationPercent = 12.5
        withinBudget = $true
    }
}
$assessment = [ordered]@{
    id = 'validate-rule'
    title = 'Validate rule'
    sourceMeaning = 'The source requires deterministic validation.'
    impactDescription = 'The requirement prevents invalid Hosted behavior.'
    hostedApplicable = $true
    applicabilityRationale = 'The behavior can be reviewed from a pull request.'
    selectionFactors = [ordered]@{ severity = 3; frequency = 3; breadth = 3; hostedDetectability = 4; evidenceStrength = 4; falsePositiveRisk = 1; redundancy = 1 }
    selectionRationale = 'The behavior is broadly useful and directly reviewable.'
    confidence = [ordered]@{ level = 'high'; rationale = 'The source is explicit.'; uncertainties = @() }
    affectedSurfaces = @('implementation')
    sourceLocalProposedText = 'Validate the rule deterministically.'
    existingCoverage = [ordered]@{ score = 0; rationale = 'The catalog does not cover the rule.' }
    relatedHostedCoverage = @()
    evaluatedAt = $timestamp
    evaluator = 'fixture-model'
}
$recommendation = [ordered]@{
    action = 'add'
    hostedId = 'IMPL-TEST-001'
    idState = 'tentative'
    targetHostedId = $null
    ruleText = 'Validate the rule deterministically.'
    category = 'implementation'
    placement = 'Schema And State'
    rationale = 'The complete source meaning is not covered.'
    needsReview = $false
    assessmentKeys = @('maintainer:IMPL-TEST-901:validate-rule')
    guardedTokenDelta = 12
    provenance = @('local-safeguard')
    evidenceIds = @('implementation-contract', 'hosted-architecture')
    implementationModels = @('legacy', 'typed', 'framework')
    sourceRelationships = @([ordered]@{ sourceDefinitionId = 'maintainer-proposals'; sourceId = 'IMPL-TEST-901'; relationshipKind = 'included'; rationale = 'The assessment is included in this recommendation.' })
}
$display = [ordered]@{
    '$schema' = 'workbench-display-v4.schema.json'
    schemaVersion = 4
    kind = 'hosted-rule-workbench-display'
    generatedAt = $timestamp
    readOnly = $true
    inputFingerprint = $hash
    candidates = @([ordered]@{
        source = [ordered]@{
            lane = 'maintainer'
            id = 'IMPL-TEST-901'
            title = 'Validate rule'
            location = 'hosted_copilot/copilot-rule-catalog/maintainer-rules/implementation.rules.md'
            text = 'Validate the rule deterministically.'
            contentSha256 = $hash
            surface = 'implementation'
            provenance = 'local-safeguard'
            rationale = 'Protect deterministic behavior.'
            evidence = @()
            transition = 'added'
        }
        assessment = $assessment
        reviewState = 'recommended'
        recommendation = $recommendation
    })
    catalog = [ordered]@{
        contentSha256 = $hash
        rules = @(
            [ordered]@{
                id = 'IMPL-EVID-001'
                origin = 'hosted-baseline-migration'
                status = 'active'
                text = 'Verify Azure behavior from authoritative evidence.'
                provenance = @('inferred-maintainer-convention')
                evidenceIds = @('implementation-contract')
                implementationModels = @('legacy', 'typed', 'framework')
                placements = @([ordered]@{ surfaceId = 'implementation'; sectionHeading = 'Evidence And Implementation Model' })
            },
            [ordered]@{
                id = 'IMPL-EVID-002'
                origin = 'hosted-baseline-migration'
                status = 'retired'
                text = 'Retain retired rule history without rendering it.'
                provenance = @('inferred-maintainer-convention')
                evidenceIds = @('implementation-contract')
                implementationModels = @('legacy', 'typed', 'framework')
                placements = @()
                retirementReason = 'Superseded by a more precise rule.'
                lastPlacement = [ordered]@{ surfaceId = 'implementation'; sectionHeading = 'Evidence And Implementation Model' }
            }
        )
    }
    guidanceCapacity = [ordered]@{
        status = 'passed'
        estimator = 'character-quarter-estimate-25pct-v1'
        safetyMarginPercent = 25
        reportCount = 8
        reports = $capacityReports
    }
}
$displaySchemaPath = Join-Path $reconciliationRoot 'workbench-display-v4.schema.json'
Add-TestResult -Name 'display-valid' -Passed (Test-JsonInstance -Value $display -SchemaPath $displaySchemaPath) -Detail 'The v4 display contains only display-ready candidates, catalog projection, capacity, and one input fingerprint.'
$activeRuleWithoutPlacement = Copy-JsonValue -Value $display
$activeRuleWithoutPlacement.catalog.rules[0].placements = @()
Add-TestResult -Name 'active-rule-placement-required' -Passed (-not (Test-JsonInstance -Value $activeRuleWithoutPlacement -SchemaPath $displaySchemaPath)) -Detail 'Every active catalog rule requires one or more display placements.'
$retiredRuleWithPlacement = Copy-JsonValue -Value $display
$retiredRuleWithPlacement.catalog.rules[1].placements = @([ordered]@{ surfaceId = 'implementation'; sectionHeading = 'Evidence And Implementation Model' })
Add-TestResult -Name 'retired-rule-placement-rejected' -Passed (-not (Test-JsonInstance -Value $retiredRuleWithPlacement -SchemaPath $displaySchemaPath)) -Detail 'Retired catalog rules remain visible as history but cannot appear in an active surface.'
$retiredRuleWithoutHistory = Copy-JsonValue -Value $display
$retiredRuleWithoutHistory.catalog.rules[1].PSObject.Properties.Remove('lastPlacement')
Add-TestResult -Name 'retired-rule-history-required' -Passed (-not (Test-JsonInstance -Value $retiredRuleWithoutHistory -SchemaPath $displaySchemaPath)) -Detail 'A retired rule retains its last rendered location for Workbench history and Restore.'
$activeRuleWithHistory = Copy-JsonValue -Value $display
$activeRuleWithHistory.catalog.rules[0] | Add-Member -NotePropertyName lastPlacement -NotePropertyValue ([ordered]@{ surfaceId = 'implementation'; sectionHeading = 'Evidence And Implementation Model' })
Add-TestResult -Name 'active-rule-history-rejected' -Passed (-not (Test-JsonInstance -Value $activeRuleWithHistory -SchemaPath $displaySchemaPath)) -Detail 'An active rule uses current surface placement and cannot carry stale retirement placement.'
$displayWithGeneration = Copy-JsonValue -Value $display
$displayWithGeneration | Add-Member -NotePropertyName acceptedSourceGeneration -NotePropertyValue ([ordered]@{})
Add-TestResult -Name 'display-generation-rejected' -Passed (-not (Test-JsonInstance -Value $displayWithGeneration -SchemaPath $displaySchemaPath)) -Detail 'The v4 display rejects source-generation and publication authority.'
$excludedDisplay = Copy-JsonValue -Value $display
$excludedDisplay.candidates[0].reviewState = 'excluded'
$excludedDisplay.candidates[0].recommendation.action = 'exclude'
Add-TestResult -Name 'display-excluded-with-contingent-recommendation' -Passed (Test-JsonInstance -Value $excludedDisplay -SchemaPath $displaySchemaPath) -Detail 'Excluded assessments retain reconciliation-owned identity and metadata for an explicit applicability override.'
$excludedWithoutRecommendation = Copy-JsonValue -Value $excludedDisplay
$excludedWithoutRecommendation.candidates[0].recommendation = $null
Add-TestResult -Name 'display-recommendation-required' -Passed (-not (Test-JsonInstance -Value $excludedWithoutRecommendation -SchemaPath $displaySchemaPath)) -Detail 'No assessment can bypass reconciliation-owned identity and metadata.'

$candidateKey = 'maintainer:IMPL-TEST-901:validate-rule'
$draft = [ordered]@{
    '$schema' = 'workbench-draft-v4.schema.json'
    schemaVersion = 4
    kind = 'hosted-rule-workbench-draft'
    inputFingerprint = $hash
    createdAt = $timestamp
    updatedAt = $timestamp
    approverName = 'Maintainer'
    decisions = [ordered]@{
        $candidateKey = [ordered]@{
            action = $null
            selected = $false
            selectionSource = 'none'
            bulkOperationId = $null
            rationale = ''
            proposedHostedRuleId = $null
            proposedText = ''
            sourceContentSha256 = $hash
            updatedAt = $timestamp
        }
    }
    applicabilityOverrides = [ordered]@{}
    bulkOperations = @()
}
$draftSchemaPath = Join-Path $reconciliationRoot 'workbench-draft-v4.schema.json'
Add-TestResult -Name 'draft-valid' -Passed (Test-JsonInstance -Value $draft -SchemaPath $draftSchemaPath) -Detail 'The local draft preserves incomplete decisions without becoming approval authority.'
$draftWithApproval = Copy-JsonValue -Value $draft
$draftWithApproval | Add-Member -NotePropertyName approvedAt -NotePropertyValue $timestamp
Add-TestResult -Name 'draft-approval-rejected' -Passed (-not (Test-JsonInstance -Value $draftWithApproval -SchemaPath $draftSchemaPath)) -Detail 'The local draft cannot carry approval.'
$draftWithBundleHash = Copy-JsonValue -Value $draft
$draftWithBundleHash | Add-Member -NotePropertyName workbenchBundleSha256 -NotePropertyValue $hash
Add-TestResult -Name 'draft-bundle-hash-rejected' -Passed (-not (Test-JsonInstance -Value $draftWithBundleHash -SchemaPath $draftSchemaPath)) -Detail 'The local draft uses one input fingerprint instead of a bundle transaction identity.'

$approved = [ordered]@{
    '$schema' = 'approved-rules-v4.schema.json'
    schemaVersion = 4
    kind = 'hosted-approved-rules'
    catalogContentSha256 = $hash
    approvedAt = $timestamp
    approvedBy = [ordered]@{ type = 'manual'; id = 'maintainer'; displayName = 'Maintainer' }
    mutations = @([ordered]@{
        action = 'add'
        rationale = 'Approve the reviewed rule.'
        rule = [ordered]@{
            id = 'IMPL-TEST-001'
            origin = 'hosted-catalog-addition'
            status = 'active'
            text = 'Validate the rule deterministically.'
            provenance = @('local-safeguard')
            evidenceIds = @('implementation-contract')
            implementationModels = @('typed')
        }
        placements = @([ordered]@{ surfaceId = 'implementation'; sectionHeading = 'Schema And State' })
        sourceRelationships = @([ordered]@{
            sourceDefinitionId = 'maintainer-proposals'
            sourceId = 'IMPL-TEST-901'
            relationshipKind = 'supports'
            rationale = 'The proposal supports the accepted rule.'
        })
    })
}
$approvedSchemaPath = Join-Path $reconciliationRoot 'approved-rules-v4.schema.json'
Add-TestResult -Name 'approved-rules-valid' -Passed (Test-JsonInstance -Value $approved -SchemaPath $approvedSchemaPath) -Detail 'The approved-rules file contains one catalog precondition, attribution, complete mutations, placements, and relationships.'
$approvedWithNoChange = Copy-JsonValue -Value $approved
$approvedWithNoChange.mutations[0].action = 'no-change'
Add-TestResult -Name 'approved-rules-nonmutation-rejected' -Passed (-not (Test-JsonInstance -Value $approvedWithNoChange -SchemaPath $approvedSchemaPath)) -Detail 'No Change, Defer, and Exclude cannot enter approved catalog mutations.'
$approvedWithPayload = Copy-JsonValue -Value $approved
$approvedWithPayload | Add-Member -NotePropertyName previewPayload -NotePropertyValue '{}'
Add-TestResult -Name 'approved-rules-envelope-rejected' -Passed (-not (Test-JsonInstance -Value $approvedWithPayload -SchemaPath $approvedSchemaPath)) -Detail 'The approved-rules file is the payload and rejects a duplicate embedded approval envelope.'

$sourceAssessmentContract = Get-Content -LiteralPath (Join-Path $assessmentRoot 'source-assessment-v4.json') -Raw | ConvertFrom-Json -DateKind String
$reconciliationContract = Get-Content -LiteralPath (Join-Path $reconciliationRoot 'assessment-reconciliation-v4.json') -Raw | ConvertFrom-Json -DateKind String
$forbiddenBehaviorPattern = '(?:source-generations/|publication-request|promotion-plan|approval-handoff|catalog-apply-receipt)'
$sourceAssessmentClean = @($sourceAssessmentContract.behaviorFiles | Where-Object { $_ -match $forbiddenBehaviorPattern }).Count -eq 0
$reconciliationClean = @($reconciliationContract.behaviorFiles | Where-Object { $_ -match $forbiddenBehaviorPattern }).Count -eq 0
Add-TestResult -Name 'assessment-contract-dependency-boundary' -Passed $sourceAssessmentClean -Detail 'The v4 assessment behavior identity excludes generation and publication machinery.'
Add-TestResult -Name 'reconciliation-contract-dependency-boundary' -Passed $reconciliationClean -Detail 'The v4 reconciliation behavior identity excludes Promotion Plan and transaction machinery.'

$remoteParserContract = Get-Content -LiteralPath (Join-Path $catalogRoot 'parser-contracts/maintainer-proposals-v4.json') -Raw | ConvertFrom-Json -DateKind String
$remoteParserOwnsExchange = [string]$remoteParserContract.parserId -ceq 'maintainer-proposals-v4' -and 'hosted_copilot/tools/modules/source-parsers/MaintainerProposalsV4.psm1' -in @($remoteParserContract.behaviorFiles)
Add-TestResult -Name 'remote-rules-parser-owned' -Passed $remoteParserOwnsExchange -Detail 'Remote Rules remain ordinary Maintainer Proposal files owned by the lane parser rather than an endpoint contract.'

$requiredV4Names = @(
    'approved-rules-v4.schema.json',
    'assessment-reconciliation-v4.json',
    'workbench-display-v4.schema.json',
    'workbench-draft-v4.schema.json'
)
$missingV4Names = @($requiredV4Names | Where-Object { -not (Test-Path -LiteralPath (Join-Path $reconciliationRoot $_) -PathType Leaf) })
$missingAssessmentV4Names = @('source-assessment-v4.json' | Where-Object { -not (Test-Path -LiteralPath (Join-Path $assessmentRoot $_) -PathType Leaf) })
Add-TestResult -Name 'v4-contract-naming' -Passed ($missingV4Names.Count -eq 0 -and $missingAssessmentV4Names.Count -eq 0) -Detail 'Every v4 Workbench authority uses an explicit v4 filename.'

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
    Write-ValidationSectionHeader -Title 'Hosted Workbench contract test summary'
    Write-ValidationSummary -Fields ([ordered]@{
        Status = $result.status.ToUpperInvariant()
        Tests = $result.testCount
        Issues = $result.issueCount
    })
    Write-Output ''
    Write-ValidationTwoColumnTable -Rows @($result.tests) -FirstHeader 'Status' -FirstProperty 'status' -SecondHeader 'Test' -SecondProperty 'name' -FirstWidth 10 -UppercaseFirst
    if ($issues.Count -gt 0) {
        Write-ValidationSectionHeader -Title 'Failures'
        foreach ($issue in $issues) {
            Write-Output "  - $issue"
        }
    }
    Complete-ValidationTextOutput
}

if ($issues.Count -gt 0) {
    exit 1
}
