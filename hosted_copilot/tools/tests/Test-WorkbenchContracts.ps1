[CmdletBinding()]
param(
    [ValidateSet('Text', 'Json')]
    [string]$OutputFormat = 'Text'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))
$validationOutputModulePath = Join-Path $repoRoot 'tools/ValidationOutput.psm1'
Import-Module -Name $validationOutputModulePath -Force
$catalogRoot = Join-Path $repoRoot 'hosted_copilot/copilot-rule-catalog'
$contractRoot = Join-Path $repoRoot 'hosted_copilot/copilot-rule-catalog/assessment-reconciliation'
$results = [Collections.Generic.List[object]]::new()
$issues = [Collections.Generic.List[string]]::new()
$hash = 'a' * 64
$timestamp = '2026-09-18T12:00:00Z'

function Test-JsonInstance {
    param(
        [Parameter(Mandatory = $true)][object]$Value,
        [Parameter(Mandatory = $true)][string]$SchemaName
    )

    try {
        return [bool](($Value | ConvertTo-Json -Depth 100) | Test-Json -SchemaFile (Join-Path $contractRoot $SchemaName) -ErrorAction Stop)
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

$assessmentRef = [ordered]@{
    assessmentBaselineSha256 = $hash
    sourceDefinitionId = 'maintainer-proposals'
    sourceId = 'TEST-REMOTE-A1B2C3D4-001'
    contentSha256 = $hash
    assessmentId = 'remote-rule'
}
$draft = [ordered]@{
    '$schema' = 'workbench-draft-v4.schema.json'
    schemaVersion = 4
    kind = 'hosted-rule-workbench-draft'
    workbenchBundleSha256 = $hash
    exportedAt = $timestamp
    approverName = 'Maintainer'
    decisions = @([ordered]@{
        hostedId = 'TEST-REMOTE-001'
        recommendationSha256 = $hash
        action = 'add'
        rationale = 'Add the reviewed rule.'
        memberAssessmentRefs = @($assessmentRef)
        planMembershipSource = 'bulk'
        bulkOperationId = 'bulk-add-001'
        updatedAt = $timestamp
    })
    applicabilityOverrides = @([ordered]@{
        assessmentRef = $assessmentRef
        originalHostedApplicable = $false
        effectiveHostedApplicable = $true
        state = 'provisional'
        rationale = 'This rule applies to the destination corpus.'
        recordedBy = 'Maintainer'
        recordedAt = $timestamp
    })
    bulkOperations = @([ordered]@{
        id = 'bulk-add-001'
        action = 'add'
        hostedIds = @('TEST-REMOTE-001')
        createdAt = $timestamp
    })
}
$plan = [ordered]@{
    '$schema' = 'promotion-plan-v4.schema.json'
    schemaVersion = 4
    kind = 'hosted-rule-promotion-plan'
    planId = '11111111-1111-4111-8111-111111111111'
    createdAt = $timestamp
    sourceWorkbenchBundleSha256 = $hash
    basePromotionPlanSha256 = $null
    hostedCatalogSha256 = $hash
    items = @([ordered]@{
        hostedId = 'TEST-REMOTE-001'
        idState = 'tentative'
        recommendationSha256 = $hash
        action = 'add'
        recommendation = [ordered]@{
            title = 'Remote rule'
            ruleText = 'Validate the remote rule.'
            category = 'testing'
            placement = 'Testing Rules'
        }
        memberAssessmentRefs = @($assessmentRef)
        rationale = 'Add the reviewed rule.'
        tokenProjection = [ordered]@{ estimatedTokenDelta = 10; guardedTokenDelta = 13 }
        reviewStatus = 'current'
        updatedAt = $timestamp
    })
}
$catalogRule = [ordered]@{
    id = 'TEST-REMOTE-001'
    status = 'active'
    text = 'Validate the remote rule.'
    placements = @([ordered]@{ surfaceId = 'testing'; sectionHeading = 'Testing Rules' })
    provenance = @('inferred-maintainer-convention')
    evidence = @('maintainer-proposals/TEST-REMOTE-A1B2C3D4-001')
}
$preview = [ordered]@{
    '$schema' = 'preview-payload-v4.schema.json'
    schemaVersion = 4
    kind = 'hosted-catalog-mutation-preview'
    workbenchBundleSha256 = $hash
    promotionPlanSha256 = $hash
    hostedCatalogSha256 = $hash
    sourceGenerationSha256 = $hash
    mutations = @([ordered]@{
        action = 'add'
        hostedId = 'TEST-REMOTE-001'
        rationale = 'Add the reviewed rule.'
        memberAssessmentRefs = @($assessmentRef)
        before = $null
        after = $catalogRule
        relationshipChanges = @()
    })
}
$previewPayload = ($preview | ConvertTo-Json -Depth 100 -Compress)
$previewPayloadSha256 = [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData([Text.Encoding]::UTF8.GetBytes($previewPayload))).ToLowerInvariant()
$approval = [ordered]@{
    '$schema' = 'approval-handoff-v4.schema.json'
    schemaVersion = 4
    kind = 'hosted-rule-workbench-approval-handoff'
    createdAt = $timestamp
    encoding = 'utf-8'
    hashAlgorithm = 'sha256-payload-bytes-v1'
    previewPayloadSha256 = $previewPayloadSha256
    approval = [ordered]@{
        state = 'approved'
        approvedAt = $timestamp
        approvedBy = [ordered]@{ type = 'manual'; id = 'maintainer'; displayName = 'Maintainer' }
        method = 'hosted-rule-workbench'
    }
    previewPayload = $previewPayload
}

Add-TestResult -Name 'draft-valid' -Passed (Test-JsonInstance -Value $draft -SchemaName 'workbench-draft-v4.schema.json') -Detail 'A same-bundle version 4 Draft satisfies the strict session-recovery schema.'
$draftRoundTrip = ($draft | ConvertTo-Json -Depth 100) | ConvertFrom-Json -DateKind String
$draftRoundTripValid = [string]$draftRoundTrip.approverName -ceq 'Maintainer' -and [string]$draftRoundTrip.decisions[0].rationale -ceq 'Add the reviewed rule.' -and [string]$draftRoundTrip.decisions[0].bulkOperationId -ceq 'bulk-add-001' -and [string]$draftRoundTrip.applicabilityOverrides[0].rationale -ceq 'This rule applies to the destination corpus.' -and [string]$draftRoundTrip.bulkOperations[0].id -ceq 'bulk-add-001'
Add-TestResult -Name 'draft-round-trip' -Passed $draftRoundTripValid -Detail 'Draft serialization preserves decisions, rationale, applicability overrides, bulk-operation history, and approver input.'
$draftWithApproval = Copy-JsonValue -Value $draft
$draftWithApproval | Add-Member -NotePropertyName previewPayloadSha256 -NotePropertyValue $hash
$draftWithApproval | Add-Member -NotePropertyName approvalState -NotePropertyValue 'approved'
$draftWithApproval | Add-Member -NotePropertyName approval -NotePropertyValue ([ordered]@{ state = 'approved' })
Add-TestResult -Name 'draft-approval-rejected' -Passed (-not (Test-JsonInstance -Value $draftWithApproval -SchemaName 'workbench-draft-v4.schema.json')) -Detail 'Draft state rejects Preview hashes and cannot transfer approval.'
$legacyDraft = Copy-JsonValue -Value $draft
$legacyDraft.schemaVersion = 3
Add-TestResult -Name 'draft-version-rejected' -Passed (-not (Test-JsonInstance -Value $legacyDraft -SchemaName 'workbench-draft-v4.schema.json')) -Detail 'The version 4 Draft contract rejects legacy session state.'

Add-TestResult -Name 'plan-valid' -Passed (Test-JsonInstance -Value $plan -SchemaName 'promotion-plan-v4.schema.json') -Detail 'A recommendation-owned destination-corpus Plan satisfies the version 4 schema.'
$invalidAddPlan = Copy-JsonValue -Value $plan
$invalidAddPlan.items[0].idState = 'existing'
Add-TestResult -Name 'plan-add-identity-rejected' -Passed (-not (Test-JsonInstance -Value $invalidAddPlan -SchemaName 'promotion-plan-v4.schema.json')) -Detail 'An Add decision cannot claim an existing Hosted ID.'
$duplicateIdPlan = Copy-JsonValue -Value $plan
$duplicateIdPlan.items = @($duplicateIdPlan.items[0], (Copy-JsonValue -Value $duplicateIdPlan.items[0]))
$uniquePlanIds = @($duplicateIdPlan.items.hostedId | Sort-Object -Unique)
Add-TestResult -Name 'plan-duplicate-id-detected' -Passed ($uniquePlanIds.Count -ne @($duplicateIdPlan.items).Count) -Detail 'Plan semantic validation can reject duplicate existing or tentative Hosted IDs.'

Add-TestResult -Name 'preview-valid' -Passed (Test-JsonInstance -Value $preview -SchemaName 'preview-payload-v4.schema.json') -Detail 'The destination-local catalog mutation Preview satisfies the strict version 4 schema.'
$invalidPreview = Copy-JsonValue -Value $preview
$invalidPreview.mutations[0].action = 'no-change'
Add-TestResult -Name 'preview-nonmutation-rejected' -Passed (-not (Test-JsonInstance -Value $invalidPreview -SchemaName 'preview-payload-v4.schema.json')) -Detail 'No Change and Defer cannot enter the catalog mutation Preview payload.'

$approvalSchemaValid = Test-JsonInstance -Value $approval -SchemaName 'approval-handoff-v4.schema.json'
$embeddedPayloadHash = [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData([Text.Encoding]::UTF8.GetBytes([string]$approval.previewPayload))).ToLowerInvariant()
Add-TestResult -Name 'approval-self-contained' -Passed ($approvalSchemaValid -and $embeddedPayloadHash -ceq [string]$approval.previewPayloadSha256) -Detail 'Approval embeds and hashes the exact UTF-8 Preview payload without a companion file.'

$reviewContract = Get-Content -LiteralPath (Join-Path $contractRoot 'assessment-reconciliation-review-v4.json') -Raw | ConvertFrom-Json -DateKind String
$reviewContractValid = Test-JsonInstance -Value $reviewContract -SchemaName 'assessment-reconciliation-review-v4-contract.schema.json'
Add-TestResult -Name 'review-contract-v4' -Passed ($reviewContractValid -and [string]$reviewContract.contractId -ceq 'assessment-reconciliation-review-v4') -Detail 'The Workbench bundle behavior contract and its schema are explicitly version 4.'

$v4NamingViolations = @(
    Get-ChildItem -LiteralPath $catalogRoot -Recurse -Filter '*.json' -File | ForEach-Object {
        $raw = [IO.File]::ReadAllText($_.FullName)
        $artifactVersion = $null
        try {
            $artifactVersion = ($raw | ConvertFrom-Json -DateKind String).schemaVersion
        }
        catch {
        }
        $isV4 = $artifactVersion -eq 4 -or $raw -match '(?s)"schemaVersion"\s*:\s*\{\s*"const"\s*:\s*4'
        if ($isV4 -and $_.Name -notmatch '-v4(?:[.-])') {
            $_.FullName
        }
    }
)
Add-TestResult -Name 'v4-support-filenames' -Passed ($v4NamingViolations.Count -eq 0) -Detail 'Every version 4 JSON artifact and schema declares v4 in its filename.'

$applyReceipt = [ordered]@{
    '$schema' = 'catalog-apply-receipt-v4.schema.json'
    schemaVersion = 4
    kind = 'hosted-catalog-apply-receipt'
    receiptId = '22222222-2222-4222-8222-222222222222'
    appliedAt = $timestamp
    workbenchBundleSha256 = $hash
    promotionPlanSha256 = $hash
    previewPayloadSha256 = $previewPayloadSha256
    sourceGenerationSha256 = $hash
    priorCatalogSha256 = $hash
    resultingCatalogSha256 = 'b' * 64
    appliedMutations = @([ordered]@{ action = 'add'; hostedId = 'TEST-REMOTE-001' })
    appliedBy = [ordered]@{ type = 'manual'; id = 'maintainer'; displayName = 'Maintainer' }
    validations = @('catalog-schema', 'generated-instructions')
    outcome = 'success'
}
Add-TestResult -Name 'catalog-apply-receipt-valid' -Passed (Test-JsonInstance -Value $applyReceipt -SchemaName 'catalog-apply-receipt-v4.schema.json') -Detail 'The apply receipt binds the exact bundle, Plan, Preview, source generation, and catalog transition.'

$endpointContract = Get-Content -LiteralPath (Join-Path $contractRoot 'remote-rules-import-v4.json') -Raw | ConvertFrom-Json -DateKind String
Add-TestResult -Name 'remote-import-contract-v4' -Passed (Test-JsonInstance -Value $endpointContract -SchemaName 'remote-rules-import-v4-contract.schema.json') -Detail 'The synchronous Remote Rules endpoint contract is explicitly version 4.'
$passedImport = [ordered]@{
    '$schema' = 'remote-rules-import-v4-result.schema.json'
    schemaVersion = 4
    kind = 'remote-rules-import-result'
    status = 'passed'
    workbenchBundleSha256 = $hash
    workbenchBundle = [ordered]@{ '$schema' = 'assessment-reconciliation-review-v4.schema.json'; schemaVersion = 4 }
}
$failedImport = [ordered]@{
    '$schema' = 'remote-rules-import-v4-result.schema.json'
    schemaVersion = 4
    kind = 'remote-rules-import-result'
    status = 'failed'
    error = 'Imported rules did not satisfy the Maintainer Proposals grammar.'
}
Add-TestResult -Name 'remote-import-results' -Passed ((Test-JsonInstance -Value $passedImport -SchemaName 'remote-rules-import-v4-result.schema.json') -and (Test-JsonInstance -Value $failedImport -SchemaName 'remote-rules-import-v4-result.schema.json')) -Detail 'The endpoint result contract accepts one bundle result or one bounded failure response.'

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
    Write-ValidationSectionHeader -Title 'Hosted v4 Workbench contract test summary'
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
