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
            maintainer = [ordered]@{ directoryPath = 'hosted_copilot/copilot-rule-catalog/maintainer-rules'; sourceSha256 = 'e' * 64 }
        }
        summary = [ordered]@{
            upstreamSourceCount = 0
            changedUpstreamCount = 0
            interactiveRuleCount = 1
            interactiveReviewCount = 1
            interactiveCurrentCount = 0
            interactiveStateCounts = [ordered]@{ new = 1; changed = 0; retired = 0; deferred = 0; current = 0 }
            maintainerRuleCount = 0
            maintainerReviewCount = 0
            maintainerCurrentCount = 0
            maintainerStateCounts = [ordered]@{ new = 0; changed = 0; retired = 0; current = 0 }
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
        maintainerCandidates = @()
    }
    $maintainerAssessment = $bundle.interactiveCandidates[0].assessment | ConvertTo-Json -Depth 20 | ConvertFrom-Json
    $maintainerAssessment.sourceContentSha256 = 'f' * 64
    $maintainerAssessment.hostedCategory = 'documentation'
    $maintainerAssessment.proposedText = 'Flag documentation that omits a required maintainer convention.'
    $bundle.maintainerCandidates = @([ordered]@{
        id = 'DOCS-MAINT-001'
        title = 'Maintainer proposal'
        sourcePath = 'hosted_copilot/copilot-rule-catalog/maintainer-rules/documentation.rules.md'
        surface = 'documentation'
        sourceStatus = 'active'
        contentSha256 = 'f' * 64
        provenance = 'confirmed-maintainer-convention'
        rationale = 'The maintainer confirmed this documentation review requirement.'
        ruleText = 'Flag documentation that omits a required maintainer convention.'
        state = 'new'
        requiresReview = $true
        relatedHostedRules = @()
        assessment = $maintainerAssessment
    })
    $bundle.summary.maintainerRuleCount = 1
    $bundle.summary.maintainerReviewCount = 1
    $bundle.summary.maintainerStateCounts.new = 1
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
    $stagedPaths = @('index.html', 'app.js', 'styles.css', 'shutdown-config.js', 'rule-intake-review.json') | ForEach-Object { Join-Path $siteDirectory $_ }
    Add-TestResult -Name 'external-staging-valid' -Passed ($stageExitCode -eq 0 -and @($stagedPaths | Where-Object { -not (Test-Path -LiteralPath $_ -PathType Leaf) }).Count -eq 0 -and $stageResult.discoveredCandidateCount -eq 2 -and $stageResult.evaluatedCandidateCount -eq 2 -and $stageResult.capacityReportCount -eq 8) -Detail $(if ($stageExitCode -eq 0) { 'The launcher stages all static assets and reports discovered and AI-evaluated candidates separately.' } else { ($stageOutput | Out-String).Trim() })
    Add-TestResult -Name 'source-bundle-read-only' -Passed ($bundleHashBefore -eq $bundleHashAfter) -Detail 'Workbench staging does not modify its source bundle.'

    $fakeAssessmentPath = Join-Path $tempRoot 'fake-assessment.ps1'
    $escapedBundlePath = $bundlePath.Replace("'", "''")
    [IO.File]::WriteAllText($fakeAssessmentPath, @"
[CmdletBinding()]
param(
    [string]`$RepositoryRoot,
    [string]`$OutputPath,
    [string]`$CachePath,
    [string]`$BaselinePath,
    [string]`$Model,
    [string]`$ReasoningEffort,
    [int]`$BatchSize,
    [int]`$UpstreamBatchSize,
    [int]`$MaxRetries,
    [string]`$EvaluatorCommand,
    [switch]`$Force,
    [string]`$OutputFormat
)
Copy-Item -LiteralPath '$escapedBundlePath' -Destination `$OutputPath -Force
[ordered]@{ status = 'passed'; candidateCount = 2; cacheHitCount = 1; baselineHitCount = 1; seededCount = 0; evaluatedCount = 0; batchCount = 0; applicableCount = 2; inapplicableCount = 0; model = `$Model; reasoningEffort = `$ReasoningEffort; repositoryWrites = `$false } | ConvertTo-Json
"@, [Text.UTF8Encoding]::new($false))
    $jsonAssessmentSiteDirectory = Join-Path $tempRoot 'json-assessment-site'
    $jsonAssessmentOutput = @(& pwsh -NoProfile -File $launcherPath -SiteDirectory $jsonAssessmentSiteDirectory -AssessmentScriptPath $fakeAssessmentPath -StageOnly -NoLaunch -OutputFormat Json 2>&1)
    $jsonAssessmentExitCode = $LASTEXITCODE
    $jsonAssessmentResult = if ($jsonAssessmentExitCode -eq 0) { ($jsonAssessmentOutput | Out-String) | ConvertFrom-Json } else { $null }
    Add-TestResult -Name 'json-assessment-launch' -Passed ($jsonAssessmentExitCode -eq 0 -and $jsonAssessmentResult.discoveredCandidateCount -eq 2 -and $jsonAssessmentResult.assessment.cacheHitCount -eq 1 -and $jsonAssessmentResult.assessment.baselineHitCount -eq 1) -Detail $(if ($jsonAssessmentExitCode -eq 0) { 'JSON mode executes assessment without a prebuilt bundle and returns one machine-readable launcher result.' } else { ($jsonAssessmentOutput | Out-String).Trim() })

    $indexContent = Get-Content -LiteralPath (Join-Path $workbenchRoot 'index.html') -Raw
    $appContent = Get-Content -LiteralPath (Join-Path $workbenchRoot 'app.js') -Raw
    $stylesContent = Get-Content -LiteralPath (Join-Path $workbenchRoot 'styles.css') -Raw
    $launcherContent = Get-Content -LiteralPath $launcherPath -Raw
    $browserContractValid = $indexContent -match 'Hosted Rule Workbench' -and $indexContent -match 'class="title-draft-menu" id="draft-menu"[\s\S]*id="export-button"[\s\S]*for="import-input"[\s\S]*id="close-button"' -and $indexContent -match 'class="ide-statusbar type-compact" aria-label="Workbench status"' -and $indexContent -match 'id="status-snapshot"' -and $indexContent -match 'id="status-mapped"' -and $indexContent -match 'id="status-headroom"' -and $indexContent -notmatch 'id="metrics-band"|Refresh candidates' -and $appContent -match 'indexedDB\.open' -and $appContent -match 'localStorage\.setItem' -and $appContent -match 'hosted-rule-workbench-draft' -and $appContent -match 'elements\["status-snapshot"\]\.textContent' -and $appContent -match 'elements\["status-mapped"\]\.textContent' -and $appContent -notmatch 'elements\["metrics-band"\]\.innerHTML'
    Add-TestResult -Name 'browser-state-contract' -Passed $browserContractValid -Detail 'The IDE shell keeps draft portability in a compact title-bar menu, places shutdown at the far right, and renders operational state directly into the status bar.'

    $keyboardNavigationValid = $appContent -match 'function handleRowKeyboardNavigation\(event, container, keyProperty, selectRow, activateRow = null\)' -and $appContent -match 'activateRow\?\.\(\)' -and $appContent -match 'event\.key !== "ArrowUp" && event\.key !== "ArrowDown"' -and $appContent -match 'candidateRow\.getClientRects\(\)\.length > 0' -and $appContent -match 'Math\.max\(0, Math\.min\(rows\.length - 1, currentIndex \+ offset\)\)' -and $appContent -match 'target\.focus\(\)' -and $appContent -match 'target\.scrollIntoView\(\{ block: "nearest" \}\)' -and $appContent -match 'event\.target\.matches\(''input\[type="checkbox"\]''\)' -and $appContent -match 'selectCandidate, \(\) => showCandidatePane\("details"\)' -and ([regex]::Matches($appContent, 'handleRowKeyboardNavigation\(event, elements\[').Count -eq 2) -and ([regex]::Matches($appContent, 'setAttribute\("aria-current", "true"\)').Count -eq 2) -and ([regex]::Matches($appContent, 'removeAttribute\("aria-current"\)').Count -eq 2)
    Add-TestResult -Name 'row-keyboard-navigation' -Passed $keyboardNavigationValid -Detail 'Arrow keys move candidate selection in place; Enter or Space opens the full-width Details view without intercepting leaf checkboxes or collapsed folders.'

    $assessmentDetailMatch = [regex]::Match($appContent, 'function renderAssessmentResultDetail\(\) \{(?<body>[\s\S]*?)\n\}\n\nfunction renderCandidateTreeRow')
    $assessmentDetailBody = if ($assessmentDetailMatch.Success) { $assessmentDetailMatch.Groups['body'].Value } else { '' }
    $workspaceTabMatch = [regex]::Match($appContent, 'function setWorkspaceTab\(tab\) \{(?<body>[\s\S]*?)\n\}\n\nfunction handleTreeSelection')
    $workspaceTabBody = if ($workspaceTabMatch.Success) { $workspaceTabMatch.Groups['body'].Value } else { '' }
    $tabStateValid = $appContent -match 'queries:\s*\{\s*"candidate-sources": "",\s*"assessment-results": ""\s*\}' -and $appContent -match 'state\.queries\[state\.workspaceTab\] = value' -and $workspaceTabBody -match 'elements\["search-input"\]\.value = state\.queries\[tab\]' -and $workspaceTabBody -notmatch 'renderCandidateList|renderAssessmentResults'
    $assessmentResultsValid = $tabStateValid -and $indexContent -notmatch 'data-view="assessment-results"|assessment-results-search|data-assessment-mode|assessment-results-controls' -and ([regex]::Matches($indexContent, 'id="search-input"').Count -eq 1) -and $indexContent -match 'class="catalog-toolbar"[\s\S]*class="workspace-tabs" role="tablist"' -and $indexContent -match 'role="tab" aria-selected="true" aria-controls="candidate-sources-panel" data-workspace-tab="candidate-sources"' -and $indexContent -match 'role="tab" aria-selected="false" aria-controls="assessment-results-panel" data-workspace-tab="assessment-results"' -and $indexContent -match 'id="candidate-sources-panel" role="tabpanel"[\s\S]*class="catalog-layout"' -and $indexContent -match 'id="assessment-results-panel" role="tabpanel"[\s\S]*class="catalog-layout"' -and $appContent -notmatch 'assessmentQuery|assessmentMode|updateAssessmentFilter|setAssessmentMode' -and $appContent -match 'assessedCandidates:\s*\[\]' -and $appContent -match 'workspaceTab:\s*"candidate-sources"' -and $appContent -match 'state\.excludedCandidateCount = assessedCandidates\.filter\(\(\{ assessment \}\) => !assessment\.hostedApplicable\)\.length' -and $appContent -match 'refreshEffectiveCandidates\(\)' -and $appContent -match 'if \(candidate\.assessment\.hostedApplicable\) return false' -and $appContent -match 'elements\["assessment-results-count"\]\.textContent = formatNumber\(state\.excludedCandidateCount\)' -and $appContent -match 'candidate-category-items"><div class="assessment-results-header"' -and $appContent -notmatch 'assessment-results-list"\]\.innerHTML = `\s*<div class="assessment-results-header"' -and $appContent -match 'state\.workspaceTab === "candidate-sources"' -and $appContent -match 'Search excluded assessment results' -and $appContent -match 'Excluded from candidate catalog' -and $assessmentDetailBody -match 'renderApplicabilityOverride\(candidate\)' -and $assessmentDetailBody -notmatch 'data-rule-action|data-plan-toggle|getDecision\('
    $assessmentResultsValid = $tabStateValid -and $indexContent -match 'data-workspace-tab="candidate-sources"' -and $indexContent -match 'data-workspace-tab="assessment-results"' -and $indexContent -notmatch 'id="assessment-results-count"|id="filter-count"|id="assessment-results-filter-count"|plan-count-control|plan-action-count|eligibility-note' -and $appContent -match 'function getActiveExcludedCandidates\(' -and $appContent -match '!candidate\.assessment\.hostedApplicable && !getApplicabilityOverride\(candidate\)' -and $appContent -match 'return getActiveExcludedCandidates\(\)\.filter' -and $appContent -notmatch 'elements\["assessment-results-count"\]|elements\["filter-count"\]|elements\["assessment-results-filter-count"\]|elements\["plan-action-count"\]|eligibility-note' -and $appContent -match 'candidate-overrides-root' -and $appContent -match 'renderApplicabilityOverride\(candidate\)' -and $stylesContent -match '\.assessment-results-header > span,\s*\.assessment-result-summary\s*\{[^}]*grid-template-columns:\s*84px 116px 140px'
    Add-TestResult -Name 'assessment-results-audit' -Passed $assessmentResultsValid -Detail 'Assessment Results lists active AI exclusions, while provisional overrides move into one Overrides group and retain their source-bound audit record.'

    $assessmentSortingValid = $appContent -match 'assessmentSorts:\s*\{\}' -and $appContent -match 'event\.target\.closest\("\[data-assessment-sort\]"\)' -and $appContent -match 'function renderAssessmentResultsHeader\(sectionKey\)' -and $appContent -match '\["candidate", "Candidate", "Candidate"' -and $appContent -match '\["state", "State", "Source State"' -and $appContent -notmatch '\["outcome", "Outcome", "Outcome"|sort\.field === "outcome"' -and $appContent -match '\["category", "Category", "Category"' -and $appContent -match '\["recommendation", "Recommendation", "Recommendation"' -and $appContent -match 'if \(sort\.field === "state"\) return candidate\.state' -and $appContent -match 'candidate-lifecycle \$\{escapeHtml\(candidate\.state\)\}' -and $appContent -match 'data-assessment-sort="\$\{key\}"' -and $appContent -match 'function getAssessmentSort\(sectionKey\)' -and $appContent -match 'return state\.assessmentSorts\[sectionKey\] \|\| \{ field: "candidate", direction: "ascending" \}' -and $appContent -match 'function updateAssessmentSort\(button\)' -and $appContent -match 'group\.appendChild\(rowsByKey\.get\(candidate\.key\)\)' -and $appContent -match 'function sortAssessmentCandidates\(candidates, sort\)' -and $stylesContent -match '\.candidate-sort-button\s*\{[^}]*grid-template-columns:\s*16px minmax\(0, 1fr\) 16px' -and $stylesContent -match ':is\(\.candidate-list-header, \.assessment-results-header\) > \.candidate-sort-button\s*\{[^}]*grid-template-columns:\s*minmax\(0, 1fr\) 16px'
    Add-TestResult -Name 'assessment-results-sorting' -Passed $assessmentSortingValid -Detail 'Each Assessment Results source group independently sorts Candidate, State, Category, and Recommendation with native buttons and a visible direction chevron.'

    $sharedPresentationUtilitiesValid = ([regex]::Matches($appContent, 'class="status-badge neutral type-compact"').Count -ge 4) -and $stylesContent -match '\.status-badge\.neutral\s*\{[^}]*color:\s*var\(--muted\);[^}]*background:\s*var\(--surface-quiet\);[^}]*border-color:\s*var\(--line-strong\)' -and $stylesContent -match '\.panel-heading,\s*\.candidate-list-header,\s*\.assessment-results-header,\s*\.plan-table th,\s*\.payload-column-heading\s*\{[^}]*background:\s*var\(--surface\);[^}]*border-color:\s*var\(--line\)' -and $appContent -match 'window\.addEventListener\("resize", scheduleTruncationTooltips\)' -and $appContent -match 'function scheduleTruncationTooltips\(\)' -and $appContent -match 'function syncTruncationTooltips\(\)' -and $appContent -match 'getComputedStyle\(node\)\.textOverflow !== "ellipsis"' -and $appContent -match 'node\.setAttribute\("data-truncation-tooltip", ""\)' -and $appContent -notmatch 'MutationObserver'
    Add-TestResult -Name 'shared-presentation-utilities' -Passed $sharedPresentationUtilitiesValid -Detail 'Sortable list headers, neutral count pills, dark data headers, and truncation tooltips are shared presentation behaviors rather than view-specific exceptions.'

    $assessmentPaneValid = $indexContent -match 'class="candidate-pane-switch assessment-pane-switch" role="tablist" aria-label="Assessment workspace"' -and $indexContent -match 'data-assessment-pane="assessments"' -and $indexContent -match 'data-assessment-pane="details"' -and $indexContent -match 'id="assessment-results-list-panel" role="tabpanel"' -and $indexContent -match 'id="assessment-results-detail" role="tabpanel"[^>]*hidden' -and $stylesContent -match '#assessment-results-panel \.catalog-layout\s*\{[^}]*grid-template-columns:\s*minmax\(0, 1fr\)' -and $stylesContent -match '#assessment-results-panel\.workspace-tab-panel\.active\s*\{[^}]*display:\s*grid;[^}]*grid-template-rows:\s*auto minmax\(0, 1fr\)' -and $appContent -match 'assessmentPane:\s*"assessments"' -and $appContent -match 'state\.assessmentPane = "assessments";\s*renderAll\(\);[\s\S]*?showAssessmentPane\("assessments"\)' -and $appContent -match 'selectAssessmentResult\(row\.dataset\.assessmentKey\);\s*showAssessmentPane\("details"\)' -and $appContent -match 'selectAssessmentResult, \(\) => showAssessmentPane\("details"\)' -and $appContent -match 'function syncAssessmentResultRows\(' -and $appContent -match 'row\.dataset\.assessmentKey === state\.assessmentActiveKey' -and $appContent -match 'function showAssessmentPane\(pane\)' -and $appContent -match 'const activePane = pane === "details" \? "details" : "assessments"'
    Add-TestResult -Name 'assessment-pane-navigation' -Passed $assessmentPaneValid -Detail 'Assessment Results always exposes full-width Assessments and Details tabs, initializes without a selection, opens Details on row activation, and synchronizes the selected-row highlight from one state owner.'

    $overrideContractValid = $appContent -match 'schemaVersion:\s*3' -and $appContent -match 'applicabilityOverrides:\s*\{\}' -and $appContent -match 'function getApplicabilityOverride' -and $appContent -match 'sourceContentSha256 !== candidate\.hash' -and $appContent -match 'originalHostedApplicable === false' -and $appContent -match 'effectiveHostedApplicable === true' -and $appContent -match 'function getEffectiveHostedApplicability' -and $appContent -match 'Maintainer Override:' -and $appContent -match 'data-override-open' -and $appContent -match 'data-override-apply' -and $appContent -match 'data-override-remove' -and $appContent -match 'recordedBy:\s*\{ type: "github-cli", login: identity\.login \}' -and $appContent -match 'applicabilityOverride: getApplicabilityOverride\(candidate\)' -and $appContent -match 'draft\.applicabilityOverrides' -and $appContent -match 'The AI assessment is read-only' -and $launcherContent -match 'gh -ErrorAction SilentlyContinue' -and $launcherContent -match 'api user --jq \.login' -and $launcherContent -match '''/hosted_copilot/''' -and $launcherContent -match 'maintainerIdentity = \$maintainerIdentity'
    $overrideContractValid = $overrideContractValid -and $appContent -match 'function updateOverrideLifecycle\(' -and $appContent -match 'repairOverridePlanMembership\(\)' -and $appContent -match 'updateOverrideLifecycle\(candidate, override, \{ \.\.\.defaultDecision\(candidate\), inPlan: true \}\)' -and $appContent -match 'updateOverrideLifecycle\(candidate, null, null\)'
    Add-TestResult -Name 'maintainer-applicability-override' -Passed $overrideContractValid -Detail 'Authenticated Hosted CODEOWNERS can atomically move an exclusion into Overrides and the plan, while removal returns it to active exclusions without mutating the AI assessment.'

    $assessmentOwnershipValid = $appContent -match 'assessment:\s*candidate\.assessment \|\| getPriorAssessment\(candidate\)' -and $appContent -match 'function saveDecision\(candidate, decision\)[\s\S]*?const \{ assessment, \.\.\.maintainerDecision \} = decision' -and $appContent -match 'state\.session\.decisions\[candidate\.key\] = \{\s*\.\.\.maintainerDecision,'
    Add-TestResult -Name 'current-bundle-assessment-ownership' -Passed $assessmentOwnershipValid -Detail 'Persisted maintainer decisions cannot override or re-export the assessment supplied by the current candidate bundle.'

    $darkThemeValid = $indexContent -match '<html lang="en" class="theme-hosted-dark">' -and $indexContent -match '<meta name="color-scheme" content="dark">' -and $indexContent -notmatch 'fonts\.googleapis|fonts\.gstatic|IBM Plex' -and $stylesContent -match 'html\.theme-hosted-dark\s*\{[^}]*--paper: #121314' -and $stylesContent -notmatch '(?m)^:root\s*\{' -and $stylesContent -match 'color-scheme: dark' -and $stylesContent -match '--surface: #191a1b' -and $stylesContent -match '--line: #2a2b2c' -and $stylesContent -match '--line-strong: #333536' -and $stylesContent -match '--accent: #3994bc' -and $stylesContent -match 'html\.theme-hosted-dark body,\s*html\.theme-hosted-dark body \*\s*\{[^}]*font-family:\s*"Segoe UI", Tahoma, sans-serif !important' -and $stylesContent -match 'font-family:\s*Consolas, "Courier New", monospace !important' -and $stylesContent -match '\.brand-block svg\s*\{[^}]*color:\s*#dcdcaa'
    Add-TestResult -Name 'dark-theme-contract' -Passed $darkThemeValid -Detail 'The product-owned Hosted dark theme uses its current IDE shell palette and typography while retaining yellow braces as its product accent.'

    $globalTypographyValid = $stylesContent -match '--font-size-default: 14px' -and $stylesContent -match '--font-size-compact: 12px' -and $stylesContent -match '--line-height-default: 20px' -and $stylesContent -match '--line-height-compact: 16px' -and $stylesContent -match 'html\.theme-hosted-dark body,\s*html\.theme-hosted-dark body \*\s*\{[^}]*font-size:\s*var\(--font-size-default\) !important;[^}]*font-weight:\s*400 !important;[^}]*line-height:\s*var\(--line-height-default\) !important' -and $stylesContent -match 'html\.theme-hosted-dark \.type-compact,\s*html\.theme-hosted-dark \.type-compact \*\s*\{[^}]*font-size:\s*var\(--font-size-compact\) !important;[^}]*font-weight:\s*400 !important;[^}]*line-height:\s*var\(--line-height-compact\) !important' -and $stylesContent -match 'html\.theme-hosted-dark body :is\(h1, h2, h3, strong, b, th, legend, \.type-emphasis\)\s*\{[^}]*font-size:\s*var\(--font-size-default\) !important;[^}]*font-weight:\s*600 !important' -and $indexContent -match 'candidate-list type-compact' -and $indexContent -match 'plan-table type-compact' -and $indexContent -match 'preview-summary type-compact' -and $indexContent -match 'preview-code type-compact' -and $indexContent -match 'ide-statusbar type-compact'
    Add-TestResult -Name 'global-typography-contract' -Passed $globalTypographyValid -Detail 'The Hosted theme enforces one 14/20 regular default, one 12/16 regular compact class, and one 14/20 semibold emphasis rule across supported viewports.'

    $scrollbarThemeValid = $stylesContent -match 'scrollbar-color: var\(--scrollbar-thumb\) var\(--scrollbar-track\)' -and $stylesContent -match 'scrollbar-width: thin' -and $stylesContent -match '\*::\-webkit-scrollbar-thumb:hover' -and $stylesContent -match '--scrollbar-track: transparent' -and $stylesContent -match '--scrollbar-thumb: rgba\(168, 169, 170, 0\.52\)' -and $stylesContent -match '--scrollbar-thumb-hover: rgba\(168, 169, 170, 0\.56\)'
    Add-TestResult -Name 'scrollbar-theme-contract' -Passed $scrollbarThemeValid -Detail 'Native scrollbars use the Hosted dark theme transparent track and neutral slider colors.'

    $ideShellValid = $indexContent -match 'data-lucide="braces"' -and $indexContent -match 'data-lucide="git-fork"' -and $indexContent -match 'class="stage-link active clickable"[^>]*title="Eligible candidates"' -and $stylesContent -match '@media \(min-width: 768px\)[\s\S]*?grid-template-columns:\s*48px minmax\(0, 1fr\);[\s\S]*?grid-template-rows:\s*35px minmax\(0, 1fr\) 22px' -and $stylesContent -match '\.stage-link\.active::before\s*\{[^}]*background:\s*var\(--ink\)' -and $stylesContent -match '\.status-left \.status-item:first-child svg\s*\{[^}]*width:\s*12px;[^}]*padding:\s*2px;[^}]*overflow:\s*visible' -and $stylesContent -notmatch '\.status-right \.status-item:nth-child' -and $stylesContent -match '\.catalog-toolbar\s*\{[^}]*min-height:\s*34px;[^}]*background:\s*var\(--paper\);[^}]*border:\s*0' -and $stylesContent -match '\.search-field\s*\{[^}]*height:\s*26px;[^}]*border-radius:\s*2px' -and $stylesContent -match '\.search-field:focus-within\s*\{[^}]*border-color:\s*var\(--line\)' -and $stylesContent -match '\.workspace-tab\.active::before\s*\{[^}]*background:\s*var\(--accent\)'
    Add-TestResult -Name 'ide-shell-contract' -Passed $ideShellValid -Detail 'The source-backed IDE shell uses compact title, activity, editor-tab, search, and status surfaces with icon-first controls and exact approved dimensions.'

    $previewEditorValid = $indexContent -match 'class="preview-editor-icon" data-lucide="file-diff"' -and $indexContent -match 'class="preview-sidebar-title">[\s\S]*data-lucide="shield-check"[\s\S]*<span>Approval</span>' -and $stylesContent -match '#preview-view \.page-heading\s*\{[^}]*height:\s*35px' -and $stylesContent -match '#preview-view \.preview-layout\s*\{[^}]*grid-template-columns:\s*280px minmax\(0, 1fr\)' -and $stylesContent -match '#preview-view \.preview-summary\s*\{[^}]*height:\s*100%;[^}]*align-self:\s*stretch;[^}]*background:\s*var\(--surface\)' -and $stylesContent -match '#approval-badge,\s*#preview-summary\s*\{[^}]*display:\s*none' -and $stylesContent -match '#preview-view \.preview-code\s*\{[^}]*background:\s*var\(--paper\);[^}]*border:\s*0'
    Add-TestResult -Name 'preview-editor-layout' -Passed $previewEditorValid -Detail 'Preview uses a compact editor header, full-height Approval properties pane, and unframed scrollable change-review editor.'

    $containedViewsValid = $stylesContent -match '@media \(min-width: 901px\)' -and $stylesContent -match '\.app-shell\s*\{[^}]*height:\s*100vh;[^}]*overflow:\s*hidden' -and $stylesContent -match '\.workspace\s*\{[^}]*min-height:\s*0;[^}]*overflow:\s*hidden' -and $stylesContent -match '#catalog-view\.view\.active\s*\{[^}]*grid-template-rows:\s*auto auto auto minmax\(0, 1fr\)' -and $stylesContent -match '#candidate-sources-panel \.candidate-list,[\s\S]*?#assessment-results-panel \.candidate-list\s*\{[^}]*max-height:\s*none;[^}]*overflow-y:\s*auto' -and $stylesContent -match '#candidate-sources-panel \.assessment-panel,[\s\S]*?#assessment-results-panel \.assessment-panel\s*\{[^}]*overflow-y:\s*auto' -and $stylesContent -match '#plan-view\.view\.active,[\s\S]*?#preview-view\.view\.active\s*\{[^}]*grid-template-rows:\s*auto minmax\(0, 1fr\)' -and $stylesContent -match '#plan-view \.plan-table-wrap,[\s\S]*?#preview-view \.preview-code\s*\{[^}]*overflow:\s*auto' -and $stylesContent -match '#plan-view \.plan-table th\s*\{[^}]*position:\s*sticky'
    Add-TestResult -Name 'contained-view-scrolling' -Passed $containedViewsValid -Detail 'Desktop stages keep navigation, headers, tabs, Draft Summary, and Plan Projection static while their owned tree, form, table, and review surfaces scroll independently.'

    $impactFactorsValid = $appContent -match 'AI Evaluation:' -and $appContent -match 'Assessment Details:' -and $appContent -match 'AI-adjudicated evidence' -and $appContent -match 'Recommend ' -and $appContent -match '<span>Token cost</span>' -and $appContent -notmatch 'Guarded token cost' -and $appContent -match 'Rule Value:' -and $appContent -match 'Review Risk:' -and $appContent -match 'Harm caused when this defect is missed' -and $appContent -match 'Chance of producing unsupported findings' -and $appContent -notmatch '<input type="range"' -and $appContent -notmatch 'data-decision-field="selectionRationale"' -and $stylesContent -match '\.factor-group\.value' -and $stylesContent -match '\.factor-group\.penalty' -and $stylesContent -match '\.factor-meter'
    Add-TestResult -Name 'impact-factor-guidance' -Passed $impactFactorsValid -Detail 'Pre-evaluated AI impact, cost, recommendation, factor evidence, and rationale are visible and read-only.'

    $detailLayoutValid = $stylesContent -match '#catalog-view\s*\{[^}]*max-width:\s*none' -and $stylesContent -match '#candidate-sources-panel \.catalog-layout\s*\{[^}]*grid-template-columns:\s*minmax\(0, 1fr\)' -and $stylesContent -match '#candidate-sources-panel \.assessment-panel\s*\{[^}]*min-width:\s*0' -and $indexContent -match 'class="candidate-pane-switch" role="tablist" aria-label="Candidate workspace"' -and $indexContent -match 'data-candidate-pane="candidates"' -and $indexContent -match 'data-candidate-pane="details" disabled' -and $appContent -match 'function showCandidatePane\(pane\)' -and $appContent -match 'elements\["candidate-panel"\]\.hidden = detailsActive' -and $appContent -match 'elements\["assessment-panel"\]\.hidden = !detailsActive' -and $stylesContent -match '\.candidate-pane-tab\.active'
    $sharedPresentationValid = $stylesContent -match 'html\.theme-hosted-dark body,\s*html\.theme-hosted-dark body \*\s*\{[^}]*font-family:\s*"Segoe UI", Tahoma, sans-serif !important' -and $stylesContent -match '\.empty-state svg\s*\{[^}]*color:\s*var\(--ink\)' -and $stylesContent -match '\.subcontext-container\s*\{[^}]*padding:\s*12px;[^}]*background:\s*var\(--blue-soft\);[^}]*border-left:\s*3px solid var\(--blue\)' -and $stylesContent -match '\.subcontext-container > p,\s*p\.subcontext-container\s*\{[^}]*color:\s*#c6d4ff;[^}]*font-size:\s*0\.8rem' -and $appContent -match 'overlap-item subcontext-container' -and $appContent -match 'ai-evaluation-summary subcontext-container' -and $appContent -match 'adjudication-text-box subcontext-container' -and $appContent -match 'evidence-summary-box subcontext-container'
    $actionControlsValid = $appContent -match 'DECISION_RATIONALE_MAX_LENGTH = 500' -and $appContent -match 'rule-actions-content subcontext-container' -and $appContent -match '<span class="control-subtitle">Rule Action:</span>\s*<div class="control-group action-plan-group">[\s\S]*?<fieldset class="action-options">[\s\S]*?<label class="plan-toggle' -and $appContent -match '<span class="control-subtitle">Decision Rationale:</span><textarea[^>]*maxlength="\$\{DECISION_RATIONALE_MAX_LENGTH\}"[^>]*aria-describedby="decision-rationale-limit"' -and $appContent -match 'rationale-limit.*DECISION_RATIONALE_MAX_LENGTH' -and $appContent -match 'decision\.rationale\.length > DECISION_RATIONALE_MAX_LENGTH' -and $stylesContent -match '\.field-stack textarea\s*\{[^}]*height:\s*84px;[^}]*max-height:\s*84px;[^}]*resize:\s*none;[^}]*overflow-y:\s*auto'
    $assessmentLegendValid = $appContent -notmatch 'impact / 100 tokens' -and $appContent -match '<span class="control-subtitle scoring-legend-title">Scoring Legend:</span>\s*<div class="scoring-legend subcontext-container">' -and $appContent -match 'Score Scale:</span><span>Scores run from 0 \(none\) through 5 \(very high\)' -and $appContent -match 'Existing Coverage:</span><span>0 means no current Hosted coverage; 5 means active Hosted rules already cover the behavior completely' -and $appContent -match 'direction-badge positive">Adds to Impact' -and $appContent -match 'direction-badge negative">Reduces Impact' -and $appContent -match 'risk-\$\{value <= 2 \? "low" : value === 3 \? "moderate" : "high"\}' -and $stylesContent -match '\.factor-line\.penalty\.risk-low \.factor-value\s*\{[^}]*color:\s*var\(--success\)' -and $stylesContent -match '\.scoring-legend-item\s*\{[^}]*grid-template-columns:\s*minmax\(0, 1fr\)'
    $detailPresentationValid = $detailLayoutValid -and $sharedPresentationValid -and $actionControlsValid -and $assessmentLegendValid -and $appContent -match 'candidate-state \$\{escapeHtml\(candidate\.state\)\}">\$\{escapeHtml\(capitalize\(candidate\.state\)\)\}' -and $appContent -match 'return value === "no-change" \? "No Change"' -and $stylesContent -match '\.decision-badge\.no-change,[\s\S]*\.recommendation-badge\.no-change\s*\{[^}]*border-color:\s*rgba\(142, 160, 208, 0\.72\)'
    $detailLayoutValid = $stylesContent -match '#catalog-view\s*\{[^}]*max-width:\s*none' -and $stylesContent -match '#candidate-sources-panel \.catalog-layout\s*\{[^}]*grid-template-columns:\s*minmax\(0, 1fr\)' -and $stylesContent -match '\.candidate-pane-switch\s*\{[^}]*height:\s*34px;[^}]*border-bottom:\s*1px solid var\(--line\)' -and $stylesContent -match '\.candidate-pane-tab\s*\{[^}]*height:\s*34px;[^}]*border-radius:\s*0' -and $stylesContent -match '\.candidate-pane-tab\.active\s*\{[^}]*box-shadow:\s*inset 0 -1px var\(--accent\)' -and $indexContent -match 'data-candidate-pane="details"' -and $indexContent -notmatch 'data-candidate-pane="details" disabled' -and $appContent -match 'function showCandidatePane\(pane\)' -and $appContent -match 'const activePane = pane === "details" \? "details" : "candidates"' -and $appContent -match 'if \(!candidate\) \{[\s\S]*?<h2>Select a candidate</h2>'
    $detailPresentationValid = $detailLayoutValid -and $sharedPresentationValid -and $actionControlsValid -and $assessmentLegendValid -and $appContent -match 'candidate-state \$\{escapeHtml\(candidate\.state\)\}' -and $appContent -match 'return value === "no-change" \? "No Change"'
    $detailPresentationValid = $detailPresentationValid -and $appContent -match 'if \(!candidate\) \{[\s\S]*?mouse-pointer-square-dashed[\s\S]*?refreshIcons\(\);\s*return;'
    Add-TestResult -Name 'detail-presentation-contract' -Passed $detailPresentationValid -Detail 'Candidates and Details use connected full-width tabs; empty Details renders its selection illustration and prompt, while selected details retain the approved evidence and control presentation.'

    $staticInformationColorsValid = $stylesContent -match '--ink: #bfbfbf' -and $stylesContent -match '--muted: #8c8c8c' -and $stylesContent -match '\.stage-link\s*\{[^}]*color:\s*var\(--muted\)' -and $stylesContent -match '\.stage-link\.active\s*\{[^}]*color:\s*var\(--ink\);[^}]*background:\s*rgba\(255, 255, 255, 0\.13\)' -and $stylesContent -match '\.stage-link\.active::before\s*\{[^}]*background:\s*var\(--ink\)' -and $stylesContent -match '\.save-indicator\s*\{[^}]*color:\s*#89d185' -and $stylesContent -match '\.tree-impact\s*\{[^}]*color:\s*var\(--blue\)' -and $stylesContent -match '\.toast\s*\{[^}]*border-left:\s*4px solid var\(--blue\)'
    Add-TestResult -Name 'static-information-colors' -Passed $staticInformationColorsValid -Detail 'Shell state uses Hosted dark theme active and inactive neutrals, autosave remains green, and Workbench domain values retain their semantic colors.'

    $sourceTreeValid = $appContent -match 'candidate-source-root' -and $appContent -match 'candidate-category' -and $appContent -match '\["maintainer", "Maintainer Proposals"\]' -and $appContent -match 'key: `maintainer:\$\{candidate\.id\}`' -and $appContent -match 'Proposal rationale' -and $appContent -notmatch 'data-category-checkbox' -and $appContent -match 'data-decision-key' -and $appContent -notmatch 'reviewSet' -and $stylesContent -match '\.candidate-tree-row' -and $stylesContent -match '\.candidate-list-header' -and $stylesContent -match '\.candidate-category > summary\s*\{[^}]*grid-template-columns:\s*18px minmax\(0, 1fr\) auto'
    Add-TestResult -Name 'evaluated-source-tree' -Passed $sourceTreeValid -Detail 'Interactive, Contributor Guidance, and Maintainer Proposals candidates are grouped by source with promotion-plan checkboxes only on leaf candidates.'

    $contributorHierarchyValid = $appContent -match 'sourceType === "upstream"\s*\? renderCandidateItems\(`\$\{sourceType\}:all`, candidates, "contributor-candidates"\)' -and $appContent -match 'Object\.entries\(groupCandidatesByCategory\(candidates\)\)' -and $appContent -match 'function renderCandidateItems\(' -and $appContent -match 'function renderCandidateListHeader\(' -and $appContent -match 'data-candidate-sort=' -and $appContent -match '\["candidate", "Candidate", "Candidate",' -and $appContent -match '\["recommendation", "Recommended", "Recommendation",' -and $appContent -match 'chevron-\$\{sort\.direction === "ascending" \? "up" : "down"\}' -and $appContent -match 'return state\.candidateSorts\[sectionKey\] \|\| \{ field: "candidate", direction: "ascending" \}' -and $appContent -match 'button\.closest\("\.candidate-category-items"\)'
    Add-TestResult -Name 'contributor-direct-children' -Passed $contributorHierarchyValid -Detail 'Contributor Guidance rules render directly beneath their source root while Interactive Toolkit rules retain category folders.'

    $candidateHeaderTooltipsValid = $appContent -match '\["candidate", "Candidate", "Candidate", "Source rule ID and title\."\]' -and $appContent -match '\["impact", "Impact", "Impact", "Priority score balancing rule value and review risk\."\]' -and $appContent -match '\["cost", "Tokens", "Token Usage", "Unsigned values show current guarded-token usage\. Signed values show the estimated change if the recommended action is promoted\."\]' -and $appContent -match '\["recommendation", "Recommended", "Recommendation", "AI-recommended action for maintainer review\."\]' -and $appContent -match 'title="\$\{escapeHtml\(help\)\}"' -and $appContent -match 'function getCandidateTokenValue\(' -and $appContent -match 'function formatCandidateTokenValue\(' -and $appContent -match 'if \(sort\.field === "cost"\) return getCandidateTokenValue\(candidate, assessment\)'
    Add-TestResult -Name 'candidate-header-tooltips' -Passed $candidateHeaderTooltipsValid -Detail 'Candidate headers preserve concise definitions; Tokens uses unsigned current usage and signed recommended deltas consistently in display and sorting.'

    $directTreeUpdatesValid = $appContent -match 'function syncCandidateTreeRows' -and $appContent -match 'function selectCandidate\(key, rationaleReturnView = null\)\s*\{[^}]*syncCandidateTreeRows\(\)' -and $appContent -match 'function updateDecision\(candidate, changes\)[\s\S]*?saveDecision\(candidate,' -and $appContent -match 'function saveDecision\(candidate, decision\)[\s\S]*?syncCandidateTreeRows\(\);\s*renderDecisionOutputs\(\);\s*\}' -and $appContent -match 'function handleTreeSelection\(event\)[\s\S]*?updateDecision\(candidate,[^;]+;\s*selectCandidate\(candidate\.key\);\s*\}' -and $appContent -match 'function updateCandidateSort\(button\)[\s\S]*?group\.appendChild\(rowsByKey\.get\(candidate\.key\)\)'
    $directTreeUpdatesValid = $directTreeUpdatesValid -and $appContent -match 'if \(candidateCheckbox\.checked\) \{\s*updateDecision\(candidate, \{ inPlan: true \}\)' -and $appContent -match 'else \{\s*undoDecision\(candidate\)' -and $appContent -match 'updateDecision\(candidate, \{ action \}\)' -and $appContent -match 'Include this candidate in the promotion plan'
    Add-TestResult -Name 'tree-leaf-direct-updates' -Passed $directTreeUpdatesValid -Detail 'Every candidate uses the same membership-only checkbox flow; action selection remains explicit, and unchecking performs the shared complete reset.'

    $ruleActionsValid = $indexContent -notmatch 'plan-count-control|plan-action-count' -and $appContent -notmatch 'elements\["plan-action-count"\]' -and $appContent -match 'function getCatalogStatus' -and $appContent -match 'function getAllowedActions' -and $appContent -match 'allowedActions\.map\(\(action\)' -and $appContent -match 'data-rule-action=' -and $appContent -match 'type="radio" name="rule-action"' -and $appContent -match 'data-plan-toggle' -and $appContent -match 'catalogStatus:\s*getCatalogStatus\(candidate\)\.key' -and $appContent -notmatch 'disposition' -and $appContent -match 'schemaVersion:\s*3,\s*kind: "hosted-rule-workbench-draft"'
    Add-TestResult -Name 'catalog-status-rule-actions' -Passed $ruleActionsValid -Detail 'Authoritative mappings are separate from source state; native radios expose only status-constrained actions, and plan membership remains an independent explicit choice.'

    $capacityProjectionValid = $appContent -match 'Plan projection' -and $appContent -match 'getProjectedCapacityDelta' -and $appContent -match 'projectedGuardedTokens' -and $appContent -match 'projectedHeadroomTokens' -and $appContent -match 'function renderDecisionOutputs\(\)[\s\S]*?renderPlan\(\);[\s\S]*?renderCapacity\(\);[\s\S]*?renderPreview\(\);[\s\S]*?renderCounts\(\);' -and $appContent -match 'const decisionSnapshot = structuredClone\(savedDecision\)' -and $appContent -match 'saveDecision\(candidate, null\)' -and $appContent -match 'saveDecision\(candidate, decisionSnapshot\)' -and $appContent -match 'delete state\.session\.decisions\[candidate\.key\]' -and $appContent -match 'Action restored to plan' -and $appContent -match 'getPlanCandidates\(\)' -and $stylesContent -match '\.toast\.visible\s*\{[^}]*pointer-events:\s*auto'
    $capacityProjectionValid = $appContent -match 'function resetCandidate\(' -and $appContent -match 'function clearCandidateSelection\(' -and $appContent -match 'const overrideSnapshot = override \? structuredClone\(override\) : null' -and $appContent -match 'updateOverrideLifecycle\(candidate, overrideSnapshot, decisionSnapshot\)' -and $appContent -match 'saveDecision\(candidate, decisionSnapshot\)' -and $appContent -match 'if \(\["add", "update"\]\.includes\(decision\.action\)\)' -and $appContent -match 'if \(decision\.action !== "retire"\) return 0'
    Add-TestResult -Name 'undo-updates-capacity-projection' -Passed $capacityProjectionValid -Detail 'Undo and uncheck clear decision, membership, selection, Preview, and any provisional override atomically; Restore reinstates both snapshots and unresolved items contribute no capacity delta.'

    $semanticColorsValid = $stylesContent -match '\.recommendation-badge\s*\{[^}]*background:\s*#303b60;[^}]*border:\s*1px solid #7f91c4' -and $stylesContent -match '\.recommendation-badge\.add\s*\{[^}]*background:\s*#174638' -and $stylesContent -match '\.recommendation-badge\.exclude\s*\{[^}]*background:\s*#4a252b' -and $stylesContent -match '\.recommendation-badge\.defer\s*\{[^}]*background:\s*#493812' -and $stylesContent -match '\.candidate-lifecycle,\s*\.candidate-state\s*\{[^}]*border:\s*1px solid #7f91c4' -and $stylesContent -match '\.candidate-tree-row\.in-plan:not\(\.active\)\s*\{[^}]*background:\s*rgba\(97, 226, 148, 0\.06\)' -and $stylesContent -match '\.catalog-status\.mapped' -and $stylesContent -match '\.action-option\.selected' -and $stylesContent -match '\.plan-undo:hover\s*\{[^}]*background:\s*#31506b'
    Add-TestResult -Name 'semantic-color-contract' -Passed $semanticColorsValid -Detail 'Lifecycle, recommendation, catalog mapping, selected action, plan membership, and Undo states use readable semantic colors and visible borders.'

    $clickableAffordanceValid = $stylesContent -match '\.clickable\s*\{\s*cursor:\s*pointer !important' -and $stylesContent -match '\.clickable:disabled,[\s\S]*?cursor:\s*not-allowed !important' -and $indexContent -match 'stage-link active clickable' -and $indexContent -match '<summary class="clickable">Raw Selection Payload</summary>' -and $appContent -match 'assessment-result-row clickable' -and $appContent -match 'candidate-tree-row clickable' -and $appContent -match 'action-option clickable' -and $appContent -match 'plan-detail-link clickable'
    Add-TestResult -Name 'clickable-cursor-affordance' -Passed $clickableAffordanceValid -Detail 'Static and generated command, navigation, disclosure, row, and option controls share an explicit pointer cursor while disabled controls retain a not-allowed cursor.'

    $planColumnsValid = $indexContent -match '<col class="plan-column-source">\s*<col class="plan-column-action">' -and $indexContent -match '<th>Source</th>\s*<th>Action</th>' -and $indexContent -match '<th>Controls</th>' -and $appContent -match '<td class="plan-source">' -and $appContent -match '<td class="plan-action">' -and $appContent -match '<tr class="plan-candidate-row clickable"[^>]*tabindex="0"[^>]*data-plan-row=' -and $appContent -match '<span class="candidate-link">' -and $appContent -notmatch '<button class="candidate-link' -and $appContent -match 'function handlePlanRowKeyboardNavigation\(' -and $stylesContent -match '\.plan-candidate-row:hover td,[\s\S]*?background:\s*var\(--accent-soft\)' -and $stylesContent -match '\.plan-table\s*\{[^}]*table-layout:\s*fixed' -and $stylesContent -match '\.plan-table th\s*\{[^}]*white-space:\s*nowrap' -and $stylesContent -match '@media \(max-width: 1180px\)[\s\S]*?\.plan-table\s*\{\s*min-width:\s*900px' -and $stylesContent -match '\.plan-table th:last-child\s*\{[^}]*text-align:\s*center'
    Add-TestResult -Name 'promotion-plan-column-alignment' -Passed $planColumnsValid -Detail 'Promotion plan separates seven readable columns and makes each row pointer- and keyboard-navigable with Candidate Sources-style hover and focus states.'

    $planDetailValid = $appContent -match 'data-plan-detail=' -and $appContent -match 'Enter decision rationale for' -and $appContent -match 'function openPlanCandidate\(' -and $appContent -match 'selectCandidate\(key, "plan"\)' -and $appContent -match 'row\.closest\("details\.candidate-category"\)' -and $appContent -match 'row\.closest\("details\.candidate-source-root"\)' -and $appContent -match 'row\.scrollIntoView' -and $appContent -match 'field\?\.scrollIntoView' -and $appContent -match 'field\?\.focus' -and $appContent -match 'data-rationale-save' -and $appContent -match '<span>Save</span>' -and $appContent -match 'Save decision rationale and return to Promotion Plan' -and $appContent -match 'save\.disabled = !value\.trim\(\)' -and $appContent -match 'await persistencePromise' -and $appContent -match 'if \(returnToPlan\)[\s\S]*?switchView\("plan"\)' -and $stylesContent -match '\.plan-detail-link:focus-visible' -and $stylesContent -match '\.rationale-actions'
    $planDetailValid = $planDetailValid -and $appContent -match 'data-plan-action=' -and $appContent -match 'openPlanCandidate\(action\.dataset\.planAction, "action"\)' -and $appContent -match 'focusTarget === "action"' -and $appContent -match 'actions\?\.scrollIntoView' -and $appContent -match 'control\?\.focus'
    Add-TestResult -Name 'promotion-plan-detail-routing' -Passed $planDetailValid -Detail 'Needs action opens and focuses Rule Actions; Needs rationale focuses Decision Rationale; Save returns plan-origin edits after persistence.'

    $planTokenDeltaValid = $appContent -match 'function getAssessmentTokenValue\(' -and $appContent -match '!getApplicabilityOverride\(candidate\) \|\| assessment\.guardedTokenDelta !== 0' -and $appContent -match 'estimateGuardedTokens\(decision\.proposedText \|\| candidate\.text\)' -and $appContent -match 'function getCandidateTokenValue\(' -and $appContent -match 'if \(getApplicabilityOverride\(candidate\)\)' -and $appContent -match 'function getPlanTokenDisplay\(' -and $appContent -match 'return `\$\{formatNumber\(getAssessmentTokenValue\(candidate, assessment, decision\)\)\} est\.`' -and $appContent -match 'function getPlanTokenDelta\(' -and $appContent -match 'getAssessmentTokenValue\(candidate, assessment, decision\)' -and $appContent -match 'return -Math\.ceil\(estimatedTokens \* 1\.25\)' -and $appContent -match 'function getPlanAffectedSurfaces\(' -and $appContent -match 'placementSurfaces\.length \? placementSurfaces : assessment\?\.affectedSurfaces' -and $appContent -match '<td class="mono">\$\{cost\}</td>' -and $appContent -match 'token\.textContent = formatCandidateTokenValue\(candidate, assessment\)' -and $appContent -match 'sum \+ getPlanTokenDelta\(candidate\)'
    Add-TestResult -Name 'promotion-plan-token-deltas' -Passed $planTokenDeltaValid -Detail 'Token displays and projections use signed action-aware values, estimate maintained proposed text when an overridden exclusion has no AI delta, and retain negative Retire savings.'

    $approvalExportValid = $indexContent -match 'id="approver-name"' -and $indexContent -match 'id="approval-requirements"[^>]*aria-label="Approval requirements"' -and $indexContent -match 'id="approve-export-button"[^>]*disabled' -and $indexContent -match 'Approve &amp; Export' -and $appContent -match 'function autofillApproverName\(' -and $appContent -match '__HOSTED_RULE_WORKBENCH__\?\.maintainerIdentity\?\.login' -and $appContent -match 'function renderApprovalRequirements\(' -and $appContent -match '\["Decision rationales"' -and $appContent -match '\["GitHub identity"' -and $appContent -match 'function getPreviewReadiness' -and $appContent -match 'function buildApprovalPayload' -and $appContent -match 'function approveAndExport' -and $appContent -match 'hosted-rule-workbench-approval-handoff' -and $appContent -match 'sha256-payload-bytes-v1' -and $appContent -match 'crypto\.subtle\.digest\("SHA-256"' -and $appContent -match 'approvedBy:\s*\{\s*type:\s*"manual"' -and $stylesContent -match '\.approval-requirements'
    $approvalExportValid = $approvalExportValid -and $appContent -match '\["Rule actions", readiness\.missingActionCount' -and $appContent -match 'missingActionCount === 0' -and $appContent -match 'status = "needs action"'
    Add-TestResult -Name 'preview-approval-export' -Passed $approvalExportValid -Detail 'Preview explains plan, action, rationale, and identity gates and blocks export until every selected candidate has an explicit promotion action and rationale.'

    $previewDiffValid = $indexContent -match 'id="preview-diff"' -and $indexContent -match 'id="preview-payload-diff"' -and $indexContent -match '<details class="preview-raw-payload">' -and $indexContent -match 'Raw Selection Payload' -and $appContent -match 'function renderPreviewChanges\(' -and $appContent -match 'decision\.action === "add"' -and $appContent -match 'decision\.action === "retire"' -and $appContent -match 'function diffTextLines\(' -and $appContent -match 'diff-line \$\{line\.type\}' -and $appContent -match 'function renderPayloadChanges\(' -and $appContent -match 'Object\.keys\(after\)\.filter' -and $appContent -match 'renderPayloadColumn\("Default", beforeLines, "delete"\)' -and $appContent -match 'renderPayloadColumn\("Current", afterLines, "add"\)' -and $appContent -match 'class="highlight-width-track"' -and $stylesContent -match '\.highlight-width-track\s*\{[^}]*width:\s*max-content;[^}]*min-width:\s*100%' -and $stylesContent -match '\.diff-line\.add\s*\{[^}]*background:\s*rgba\(46, 160, 67, 0\.2\)' -and $stylesContent -match '\.diff-line\.delete\s*\{[^}]*background:\s*rgba\(248, 81, 73, 0\.2\)' -and $stylesContent -match '\.payload-columns\s*\{[^}]*grid-template-columns:\s*minmax\(0, 1fr\) minmax\(0, 1fr\)'
    Add-TestResult -Name 'preview-change-review' -Passed $previewDiffValid -Detail 'Preview renders every planned rule as an action-aware unified diff, compares changed selection fragments side by side, and extends semantic highlights through horizontally overflowed content.'

    $rawPayloadNavigationValid = $indexContent -match 'id="raw-change-tools"[^>]*hidden' -and $indexContent -match 'id="raw-previous-change"' -and $indexContent -match 'id="raw-next-change"' -and $indexContent -match 'id="raw-change-position"[^>]*aria-live="polite"' -and $appContent -match 'function renderRawPayload\(' -and $appContent -match '\["add", "update"\]\.includes\(decision\.action\) \|\| decision\.applicabilityOverride' -and $appContent -match 'data-raw-change-index=' -and $appContent -match 'preview-json"\]\.textContent !== rawPayload' -and $appContent -match 'function navigateRawPayloadChange\(' -and $stylesContent -match '\.raw-json-line\.raw-json-added\s*\{[^}]*background:\s*rgba\(46, 160, 67, 0\.2\)' -and $stylesContent -match '\.raw-json-line\.raw-json-added \.raw-json-line-marker::before\s*\{[^}]*content:\s*"\+"'
    Add-TestResult -Name 'raw-payload-change-navigation' -Passed $rawPayloadNavigationValid -Detail 'Raw selection JSON highlights and navigates complete in-plan Add, Update, and applicability-override records while preserving copyable payload text.'

    $noOpUpdateValid = $appContent -match 'function hasHostedTextChange\(' -and $appContent -match 'if \(hasHostedTextChange\(candidate, proposedText\)\) actions\.push\("update"\)' -and $appContent -match 'Current and proposed Hosted rule text are identical, so Update is unavailable\.' -and $appContent -match 'const allowedActions = getAllowedActions\(candidate, proposedText\)' -and $appContent -match 'inPlan: saved\.inPlan && isPromotionAction\(saved\.action\)'
    $noOpUpdateValid = $appContent -match 'function hasHostedTextChange\(' -and $appContent -match 'if \(hasHostedTextChange\(candidate, proposedText\)\) actions\.push\("update"\)' -and $appContent -match 'Current and proposed Hosted rule text are identical, so Update is unavailable\.' -and $appContent -match 'inPlan: saved\.inPlan,' -and $appContent -match 'const unresolved = candidates\.filter\(\(candidate\) => !isPromotionAction' -and $appContent -match 'Complete Rule Actions from the Promotion Plan'
    Add-TestResult -Name 'no-op-update-suppression' -Passed $noOpUpdateValid -Detail 'Mapped candidates expose Update only for text changes; independent unresolved membership is retained but cannot render or approve as a proposed change.'

    $mobileUnsupportedValid = $indexContent -match 'Mobile devices are not supported' -and $appContent -match 'matchMedia\("\(max-width: 767px\)"\)\.matches' -and $appContent -match 'userAgentData\?\.mobile' -and $appContent -match 'mobile-unsupported' -and $stylesContent -match '@media \(max-width: 767px\)' -and $stylesContent -match 'html\.mobile-unsupported \.unsupported-device'
    Add-TestResult -Name 'mobile-unsupported-contract' -Passed $mobileUnsupportedValid -Detail 'Mobile detection replaces the Workbench with a laptop-or-desktop requirement.'

    $assessmentLaunchValid = $launcherContent -match 'Invoke-RuleIntakeAssessment\.ps1' -and $launcherContent -match '\$null -eq \$resolvedBundlePath' -and $launcherContent -match '''-CachePath'', \$AssessmentCachePath' -and $launcherContent -match '''-BaselinePath'', \$AssessmentBaselinePath' -and $launcherContent -match '''-Model'', \$AssessmentModel' -and $launcherContent -match '\$assessmentOutputFormat = if \(\$OutputFormat -eq ''Text''\) \{ ''Text'' \} else \{ ''Json'' \}' -and $launcherContent -match "Write-Host '\[RUNNING\].*assessment" -and $launcherContent -match '& pwsh @assessmentArguments 2>&1 \| ForEach-Object \{ Write-Host \$_ \}' -and $launcherContent -match "Write-Host '\[PASSED\].*assessment" -and $launcherContent -match 'Rule intake assessment failed'
    Add-TestResult -Name 'incremental-assessment-launch' -Passed $assessmentLaunchValid -Detail 'Text launches visibly complete candidate assessment before Workbench staging, JSON launches remain machine-readable, and an explicit BundlePath remains a model-free staging path.'

    $serverContractValid = $launcherContent -match '\[Net\.IPAddress\]::Loopback' -and $launcherContent -match 'RandomNumberGenerator.*Fill' -and $launcherContent -match 'CryptographicOperations.*FixedTimeEquals' -and $launcherContent.Contains('$requestUri.AbsolutePath -eq ''/shutdown''') -and $launcherContent -match 'X-Workbench-Shutdown-Token' -and $stageResult.readOnly -and (@($stageResult.allowedMethods) -join ',') -eq 'GET,HEAD' -and $stageResult.shutdownEndpoint -eq 'POST /shutdown'
    Add-TestResult -Name 'loopback-read-only-server' -Passed $serverContractValid -Detail 'The server binds to loopback, serves static GET and HEAD requests, and exposes only a token-authenticated process shutdown lifecycle endpoint.'

    $portProbe = [Net.Sockets.TcpListener]::new([Net.IPAddress]::Loopback, 0)
    $portProbe.Start()
    $shutdownPort = ([Net.IPEndPoint]$portProbe.LocalEndpoint).Port
    $portProbe.Stop()
    $shutdownSiteDirectory = Join-Path $tempRoot 'shutdown-site'
    $serverJob = Start-Job -ScriptBlock {
        param($LauncherPath, $SiteDirectory, $FixtureBundlePath, $Port)
        & pwsh -NoProfile -File $LauncherPath -SiteDirectory $SiteDirectory -BundlePath $FixtureBundlePath -Port $Port -NoLaunch -OutputFormat Json
    } -ArgumentList $launcherPath, $shutdownSiteDirectory, $bundlePath, $shutdownPort
    try {
        $shutdownUrl = "http://127.0.0.1:$shutdownPort"
        $deadline = [DateTimeOffset]::UtcNow.AddSeconds(10)
        $serverReady = $false
        while (-not $serverReady -and [DateTimeOffset]::UtcNow -lt $deadline) {
            try {
                $serverReady = (Invoke-WebRequest -Uri "$shutdownUrl/" -Method Get -SkipHttpErrorCheck).StatusCode -eq 200
            }
            catch { }
        }
        if (-not $serverReady) {
            throw 'loopback test server did not become ready'
        }
        $shutdownConfigContent = Get-Content -LiteralPath (Join-Path $shutdownSiteDirectory 'shutdown-config.js') -Raw
        if ($shutdownConfigContent -notmatch '"shutdownToken":"(?<token>[0-9a-f]{64})"') {
            throw 'staged shutdown token was not found'
        }
        $shutdownToken = [string]$Matches['token']
        $unauthorizedShutdown = Invoke-WebRequest -Uri "$shutdownUrl/shutdown" -Method Post -SkipHttpErrorCheck
        $unrelatedPost = Invoke-WebRequest -Uri "$shutdownUrl/" -Method Post -Headers @{ 'X-Workbench-Shutdown-Token' = $shutdownToken } -SkipHttpErrorCheck
        $authorizedShutdown = Invoke-WebRequest -Uri "$shutdownUrl/shutdown" -Method Post -Headers @{ 'X-Workbench-Shutdown-Token' = $shutdownToken } -SkipHttpErrorCheck
        $completedJob = Wait-Job -Job $serverJob -Timeout 10
        $shutdownLifecycleValid = $unauthorizedShutdown.StatusCode -eq 403 -and $unrelatedPost.StatusCode -eq 405 -and $authorizedShutdown.StatusCode -eq 200 -and $null -ne $completedJob -and $serverJob.State -eq 'Completed'
        Add-TestResult -Name 'authenticated-server-shutdown' -Passed $shutdownLifecycleValid -Detail 'Only the per-launch token can stop the loopback server; unauthorized shutdown and unrelated POST requests remain rejected.'
    }
    finally {
        if ($serverJob.State -notin @('Completed', 'Failed', 'Stopped')) {
            Stop-Job -Job $serverJob
        }
        Remove-Job -Job $serverJob -Force
    }

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
