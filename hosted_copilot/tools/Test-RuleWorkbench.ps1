[CmdletBinding()]
param(
    [ValidateSet('Text', 'Json')]
    [string]$OutputFormat = 'Text'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$validationOutputModulePath = Join-Path $PSScriptRoot '../../tools/ValidationOutput.psm1'
Import-Module -Name $validationOutputModulePath -Force

$repositoryRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
$workbenchRoot = Join-Path $PSScriptRoot '../workbench'
$launcherPath = Join-Path $PSScriptRoot 'Start-RuleWorkbench.ps1'
$bundleSchemaPath = Join-Path $PSScriptRoot '../copilot-rule-catalog/rule-intake-review.schema.json'
$results = New-Object 'System.Collections.Generic.List[object]'
$issues = New-Object 'System.Collections.Generic.List[string]'
$tempRoot = Join-Path ([IO.Path]::GetTempPath()) ("hosted-rule-workbench-test-" + [guid]::NewGuid().ToString('N'))

function Add-TestResult {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][bool]$Passed,
        [Parameter(Mandatory = $true)][string]$Detail
    )

    $results.Add([pscustomobject]@{
        name = $Name
        status = if ($Passed) { 'passed' } else { 'failed' }
        detail = $Detail
    })
    if (-not $Passed) {
        $issues.Add("$Name`: $Detail")
    }
}

function New-CapacityReport {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][string]$Kind
    )

    return [ordered]@{
        name = $Name
        kind = $Kind
        paths = @('fixture.md')
        characterCount = 100
        estimatedTokens = 25
        guardedTokens = 32
        budgetTokens = 1000
        budgetHeadroomTokens = 968
        utilizationPercent = 3.2
        withinBudget = $true
    }
}

try {
    New-Item -ItemType Directory -Path $tempRoot -Force | Out-Null
    $bundlePath = Join-Path $tempRoot 'rule-intake-review.json'
    $capacityReports = @(
        New-CapacityReport -Name 'repository' -Kind 'file'
        New-CapacityReport -Name 'go' -Kind 'file'
        New-CapacityReport -Name 'test' -Kind 'file'
        New-CapacityReport -Name 'documentation' -Kind 'file'
        New-CapacityReport -Name 'skill' -Kind 'file'
        New-CapacityReport -Name 'go-combined' -Kind 'combined'
        New-CapacityReport -Name 'test-combined' -Kind 'combined'
        New-CapacityReport -Name 'documentation-combined' -Kind 'combined'
    )
    $bundle = [ordered]@{
        '$schema' = 'rule-intake-review.schema.json'
        schemaVersion = 1
        generatedAt = '2026-09-03T00:00:00Z'
        readOnly = $true
        refreshMode = 'regenerate-read-only-bundle'
        snapshots = [ordered]@{
            hostedCatalogSha256 = 'a' * 64
            intakeLedgerSha256 = 'b' * 64
            upstream = [ordered]@{ repository = 'hashicorp/terraform-provider-azurerm'; baselineCommit = '1' * 40; currentRef = 'main'; currentCommit = '2' * 40 }
            interactive = [ordered]@{ catalogPath = 'tools/interactive-rule-catalog/rule-catalog.json'; previousCatalogSha256 = 'c' * 64; currentCatalogSha256 = 'c' * 64; catalogChanged = $false }
        }
        summary = [ordered]@{
            upstreamSourceCount = 0
            changedUpstreamCount = 0
            interactiveRuleCount = 1
            interactiveReviewCount = 1
            interactiveCurrentCount = 0
            interactiveStateCounts = [ordered]@{ new = 1; changed = 0; retired = 0; deferred = 0; current = 0 }
        }
        guidanceCapacity = [ordered]@{
            status = 'passed'
            estimator = 'character-quarter-estimate-25pct-v1'
            safetyMarginPercent = 25
            reportCount = 8
            reports = $capacityReports
        }
        upstreamCandidates = @()
        interactiveCandidates = @(
            [ordered]@{
                id = 'REVIEW-CLASS-001'
                title = 'Issues are for actual problems only'
                contractPath = '.github/instructions/code-review-compliance-contract.instructions.md'
                sourceStatus = 'active'
                contentSha256 = 'd' * 64
                provenance = 'published-upstream-standard'
                evidence = @('fixture-evidence')
                sourceIds = @('fixture-source')
                ruleText = 'An Issue must identify a real defect supported by evidence.'
                state = 'new'
                requiresReview = $true
                changeReasons = @('new-rule')
                priorDecision = $null
                relatedHostedRules = @()
                assessment = [ordered]@{
                    status = 'evaluated'
                    sourceContentSha256 = 'd' * 64
                    assessedAt = '2026-09-03T00:00:00Z'
                    evaluator = 'offline-fixture'
                    hostedApplicable = $true
                    applicabilityRationale = 'The rule governs evidence-backed findings produced by the Hosted review agent.'
                    hostedCategory = 'review-classification-and-evidence'
                    recommendation = 'add'
                    summary = 'High impact, low cost'
                    impactDescription = 'Prevents unsupported review findings across review surfaces.'
                    currentHostedCoverage = 'No materially equivalent Hosted rule is mapped.'
                    affectedSurfaces = @('review-skill')
                    guardedTokenDelta = 19
                    proposedText = 'Report only evidence-backed defects as Issues.'
                    selectionFactors = [ordered]@{
                        severity = 5
                        frequency = 3
                        breadth = 4
                        hostedDetectability = 4
                        evidenceStrength = 5
                        falsePositiveRisk = 1
                        redundancy = 1
                    }
                    selectionRationale = 'The safeguard is broadly applicable, evidence-backed, and inexpensive.'
                }
            }
        )
    }
    $bundleJson = $bundle | ConvertTo-Json -Depth 20
    [IO.File]::WriteAllText($bundlePath, $bundleJson + "`n", [Text.UTF8Encoding]::new($false))
    Add-TestResult -Name 'fixture-bundle-valid' -Passed ([bool]($bundleJson | Test-Json -SchemaFile $bundleSchemaPath -ErrorAction Stop)) -Detail 'The offline Workbench bundle satisfies the candidate review schema.'

    $invalidAssessmentBundle = $bundleJson | ConvertFrom-Json
    $invalidAssessmentBundle.interactiveCandidates[0].assessment.selectionFactors.severity = 6
    $invalidAssessmentJson = $invalidAssessmentBundle | ConvertTo-Json -Depth 20
    Add-TestResult -Name 'assessment-factor-range' -Passed (-not [bool]($invalidAssessmentJson | Test-Json -SchemaFile $bundleSchemaPath -ErrorAction SilentlyContinue)) -Detail 'AI assessment factors outside the supported zero-through-five range are rejected.'

    $siteDirectory = Join-Path $tempRoot 'site'
    $bundleHashBefore = (Get-FileHash -LiteralPath $bundlePath -Algorithm SHA256).Hash
    $stageOutput = @(& pwsh -NoProfile -File $launcherPath -SiteDirectory $siteDirectory -BundlePath $bundlePath -StageOnly -NoLaunch -OutputFormat Json 2>&1)
    $stageExitCode = $LASTEXITCODE
    $stageResult = if ($stageExitCode -eq 0) { ($stageOutput | Out-String) | ConvertFrom-Json } else { $null }
    $bundleHashAfter = (Get-FileHash -LiteralPath $bundlePath -Algorithm SHA256).Hash
    $stagedPaths = @('index.html', 'app.js', 'styles.css', 'rule-intake-review.json') | ForEach-Object { Join-Path $siteDirectory $_ }
    Add-TestResult -Name 'external-staging-valid' -Passed ($stageExitCode -eq 0 -and @($stagedPaths | Where-Object { -not (Test-Path -LiteralPath $_ -PathType Leaf) }).Count -eq 0 -and $stageResult.discoveredCandidateCount -eq 1 -and $stageResult.evaluatedCandidateCount -eq 1 -and $stageResult.capacityReportCount -eq 8) -Detail $(if ($stageExitCode -eq 0) { 'The launcher stages all static assets and reports discovered and AI-evaluated candidates separately.' } else { ($stageOutput | Out-String).Trim() })
    Add-TestResult -Name 'source-bundle-read-only' -Passed ($bundleHashBefore -eq $bundleHashAfter) -Detail 'Workbench staging does not modify its source bundle.'

    $indexContent = Get-Content -LiteralPath (Join-Path $workbenchRoot 'index.html') -Raw
    $appContent = Get-Content -LiteralPath (Join-Path $workbenchRoot 'app.js') -Raw
    $stylesContent = Get-Content -LiteralPath (Join-Path $workbenchRoot 'styles.css') -Raw
    $browserContractValid = $indexContent -match 'Hosted Rule Workbench' -and $indexContent -match 'Refresh candidates' -and $appContent -match 'indexedDB\.open' -and $appContent -match 'localStorage\.setItem' -and $appContent -match 'hosted-rule-workbench-draft'
    Add-TestResult -Name 'browser-state-contract' -Passed $browserContractValid -Detail 'The static Workbench includes persistent drafts, refresh, and portability contracts.'

    $darkThemeValid = $indexContent -match '<meta name="color-scheme" content="dark">' -and $stylesContent -match 'color-scheme: dark' -and $stylesContent -match '--paper: #0b1523' -and $stylesContent -match '--surface: rgba\(18, 33, 54, 0\.9\)' -and $stylesContent -match '--accent: #68c6ff'
    Add-TestResult -Name 'dark-theme-contract' -Passed $darkThemeValid -Detail 'The Workbench uses the required leadership-report navy and cyan dark palette.'

    $scrollbarThemeValid = $stylesContent -match 'scrollbar-color: var\(--scrollbar-thumb\) var\(--scrollbar-track\)' -and $stylesContent -match 'scrollbar-width: thin' -and $stylesContent -match '\*::\-webkit-scrollbar-thumb:hover' -and $stylesContent -match '--scrollbar-thumb-hover: #68c6ff'
    Add-TestResult -Name 'scrollbar-theme-contract' -Passed $scrollbarThemeValid -Detail 'Native scrollbars use the Workbench navy, slate-blue, and cyan palette.'

    $impactFactorsValid = $appContent -match 'AI evaluation' -and $appContent -match 'Assessment details' -and $appContent -match 'AI-adjudicated evidence' -and $appContent -match 'Recommend ' -and $appContent -match '<span>Token cost</span>' -and $appContent -notmatch 'Guarded token cost' -and $appContent -match 'Rule value' -and $appContent -match 'Review risk' -and $appContent -match 'Harm caused when this defect is missed' -and $appContent -match 'Chance of producing unsupported findings' -and $appContent -notmatch '<input type="range"' -and $appContent -notmatch 'data-decision-field="selectionRationale"' -and $stylesContent -match '\.factor-group\.value' -and $stylesContent -match '\.factor-group\.penalty' -and $stylesContent -match '\.factor-meter'
    Add-TestResult -Name 'impact-factor-guidance' -Passed $impactFactorsValid -Detail 'Pre-evaluated AI impact, cost, recommendation, factor evidence, and rationale are visible and read-only.'

    $sourceTreeValid = $appContent -match 'candidate-source-root' -and $appContent -match 'candidate-category' -and $appContent -notmatch 'data-category-checkbox' -and $appContent -match 'data-review-key' -and $appContent -match 'reviewSet' -and $stylesContent -match '\.candidate-tree-row' -and $stylesContent -match '\.candidate-list-header' -and $stylesContent -match '\.candidate-category > summary\s*\{[^}]*grid-template-columns:\s*18px minmax\(0, 1fr\) auto'
    Add-TestResult -Name 'evaluated-source-tree' -Passed $sourceTreeValid -Detail 'Hosted-applicable candidates are grouped by navigation-only folders with selection controls only on leaf candidates.'

    $maintainerActionsValid = $appContent -match 'renderDecisionActions' -and $appContent -match 'add: \[\["included", "Add"[^\r\n]+\["deferred", "Defer"[^\r\n]+\["excluded", "Exclude"' -and $appContent -match '"Update", "Update Hosted guidance"' -and $appContent -match '"Remove", "Remove rule from Hosted guidance"' -and $appContent -match '"Keep", "Keep current Hosted guidance"' -and $appContent -notmatch 'data-decision-undo' -and $appContent -match 'data-plan-undo'
    Add-TestResult -Name 'maintainer-action-verbs' -Passed $maintainerActionsValid -Detail 'The right pane uses recommendation-aware verbs without duplicate Undo; Promotion plan rows provide the recovery action.'

    $capacityProjectionValid = $appContent -match 'Plan projection' -and $appContent -match 'getProjectedCapacityDelta' -and $appContent -match 'projectedGuardedTokens' -and $appContent -match 'projectedHeadroomTokens' -and $appContent -match 'renderAll\(false\)' -and $appContent -match 'Decision restored' -and $stylesContent -match '\.toast\.visible\s*\{[^}]*pointer-events:\s*auto'
    Add-TestResult -Name 'undo-updates-capacity-projection' -Passed $capacityProjectionValid -Detail 'Undo and Restore recompute projected guarded usage, headroom, utilization, and draft cost from the current plan.'

    $semanticColorsValid = $stylesContent -match '\.recommendation-badge\s*\{[^}]*background:\s*#303b60;[^}]*border:\s*1px solid #7f91c4' -and $stylesContent -match '\.recommendation-badge\.add\s*\{[^}]*background:\s*#174638' -and $stylesContent -match '\.recommendation-badge\.exclude\s*\{[^}]*background:\s*#4a252b' -and $stylesContent -match '\.recommendation-badge\.defer\s*\{[^}]*background:\s*#493812' -and $stylesContent -match '\.candidate-lifecycle,\s*\.candidate-state\s*\{[^}]*border:\s*1px solid #7f91c4' -and $stylesContent -match '\.decision-control button\.included:hover,[^{]+\{[^}]*background:\s*#215f4b' -and $stylesContent -match '\.decision-control button\.excluded:hover,[^{]+\{[^}]*background:\s*#663139' -and $stylesContent -match '\.decision-control button\.deferred:hover,[^{]+\{[^}]*background:\s*#66501b' -and $stylesContent -match '\.decision-control button\.included\.active\s*\{[^}]*box-shadow:' -and $stylesContent -match '\.decision-control button\.included\.active:hover,[^{]+\{[^}]*background:\s*#2c765e' -and $stylesContent -match '\.plan-undo:hover\s*\{[^}]*background:\s*#31506b' -and $stylesContent -match '#review-selected-button:disabled[^{]*\{[^}]*background:\s*#172437;[^}]*border-color:\s*#34465d;[^}]*opacity:\s*1' -and $stylesContent -match '\.eligibility-note\s*\{[^}]*background:\s*var\(--note-paper\);[^}]*border:\s*1px solid var\(--note-border\)'
    Add-TestResult -Name 'semantic-color-contract' -Passed $semanticColorsValid -Detail 'Lifecycle, recommendation, action, Undo, disabled command, and informational note states use opaque fills, readable text, and visible semantic borders.'

    $planColumnsValid = $indexContent -match '<col class="plan-column-actions">' -and $indexContent -match '<th>Actions</th>' -and $stylesContent -match '\.plan-table\s*\{[^}]*table-layout:\s*fixed' -and $stylesContent -match '\.plan-column-actions\s*\{[^}]*width:\s*88px' -and $stylesContent -match '\.plan-table th:last-child\s*\{[^}]*text-align:\s*center'
    Add-TestResult -Name 'promotion-plan-column-alignment' -Passed $planColumnsValid -Detail 'Promotion plan header and body share six fixed columns, including a centered Actions column covering Undo.'

    $mobileUnsupportedValid = $indexContent -match 'Mobile devices are not supported' -and $appContent -match 'matchMedia\("\(max-width: 767px\)"\)\.matches' -and $appContent -match 'userAgentData\?\.mobile' -and $appContent -match 'mobile-unsupported' -and $stylesContent -match '@media \(max-width: 767px\)' -and $stylesContent -match 'html\.mobile-unsupported \.unsupported-device'
    Add-TestResult -Name 'mobile-unsupported-contract' -Passed $mobileUnsupportedValid -Detail 'Mobile detection replaces the Workbench with a laptop-or-desktop requirement.'

    $launcherContent = Get-Content -LiteralPath $launcherPath -Raw
    $serverContractValid = $launcherContent -match '\[Net\.IPAddress\]::Loopback' -and $launcherContent.Contains('$method -notin @(''GET'', ''HEAD'')') -and $launcherContent -match '405' -and $stageResult.readOnly -and (@($stageResult.allowedMethods) -join ',') -eq 'GET,HEAD'
    Add-TestResult -Name 'loopback-read-only-server' -Passed $serverContractValid -Detail 'The server binds to loopback and permits only GET and HEAD static requests.'

    $repositorySiteDirectory = Join-Path $repositoryRoot 'hosted_copilot/workbench/staged-test'
    $rejectedOutput = @(& pwsh -NoProfile -File $launcherPath -SiteDirectory $repositorySiteDirectory -BundlePath $bundlePath -StageOnly -NoLaunch -OutputFormat Json 2>&1)
    $repositoryStagingRejected = $LASTEXITCODE -ne 0 -and -not (Test-Path -LiteralPath $repositorySiteDirectory)
    Add-TestResult -Name 'repository-staging-rejected' -Passed $repositoryStagingRejected -Detail 'The launcher rejects generated staging output inside the source repository.'
}
catch {
    $issues.Add($_.Exception.Message)
}
finally {
    Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
}

$result = [ordered]@{
    status = if ($issues.Count -eq 0) { 'passed' } else { 'failed' }
    testCount = $results.Count
    issueCount = $issues.Count
    tests = $results.ToArray()
    issues = $issues.ToArray()
}

if ($OutputFormat -eq 'Json') {
    $result | ConvertTo-Json -Depth 6
}
else {
    Write-ValidationSectionHeader -Title 'Hosted Rule Workbench test summary'
    Write-ValidationSummary -Fields ([ordered]@{
        Status = $result.status.ToUpperInvariant()
        Tests = $result.testCount
        'Issue Count' = $result.issueCount
    })
    Write-ValidationSectionHeader -Title 'Workbench tests'
    Write-ValidationTwoColumnTable -Rows @($results.ToArray()) -FirstHeader 'status' -FirstProperty 'status' -SecondHeader 'test' -SecondProperty 'name' -UppercaseFirst
    if ($issues.Count -gt 0) {
        Write-ValidationSectionHeader -Title 'Issues'
        foreach ($issue in $issues) {
            Write-Output "  - $issue"
        }
    }
    Complete-ValidationTextOutput
}

if ($result.status -eq 'failed') {
    exit 1
}
