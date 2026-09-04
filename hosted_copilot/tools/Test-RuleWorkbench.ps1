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
    $browserContractValid = $indexContent -match 'Hosted Rule Workbench' -and $indexContent -match 'id="export-button"[\s\S]*for="import-input"[\s\S]*id="close-button"' -and $indexContent -notmatch 'Refresh candidates' -and $appContent -match 'indexedDB\.open' -and $appContent -match 'localStorage\.setItem' -and $appContent -match 'hosted-rule-workbench-draft'
    Add-TestResult -Name 'browser-state-contract' -Passed $browserContractValid -Detail 'The static Workbench includes persistent draft portability and places the explicit server shutdown control at the far right without a misleading bundle refresh action.'

    $keyboardNavigationValid = $appContent -match 'function handleRowKeyboardNavigation\(event, container, keyProperty, selectRow\)' -and $appContent -match 'event\.key !== "ArrowUp" && event\.key !== "ArrowDown"' -and $appContent -match 'candidateRow\.getClientRects\(\)\.length > 0' -and $appContent -match 'Math\.max\(0, Math\.min\(rows\.length - 1, currentIndex \+ offset\)\)' -and $appContent -match 'target\.focus\(\)' -and $appContent -match 'target\.scrollIntoView\(\{ block: "nearest" \}\)' -and $appContent -match 'event\.target\.matches\(''input\[type="checkbox"\]''\)' -and ([regex]::Matches($appContent, 'handleRowKeyboardNavigation\(event, elements\[').Count -eq 2) -and ([regex]::Matches($appContent, 'setAttribute\("aria-current", "true"\)').Count -eq 2) -and ([regex]::Matches($appContent, 'removeAttribute\("aria-current"\)').Count -eq 2)
    Add-TestResult -Name 'row-keyboard-navigation' -Passed $keyboardNavigationValid -Detail 'Up and Down Arrow move selection and focus across visible candidate or assessment rows without intercepting leaf checkboxes or collapsed-folder content.'

    $assessmentDetailMatch = [regex]::Match($appContent, 'function renderAssessmentResultDetail\(\) \{(?<body>[\s\S]*?)\n\}\n\nfunction renderCandidateTreeRow')
    $assessmentDetailBody = if ($assessmentDetailMatch.Success) { $assessmentDetailMatch.Groups['body'].Value } else { '' }
    $workspaceTabMatch = [regex]::Match($appContent, 'function setWorkspaceTab\(tab\) \{(?<body>[\s\S]*?)\n\}\n\nfunction handleTreeSelection')
    $workspaceTabBody = if ($workspaceTabMatch.Success) { $workspaceTabMatch.Groups['body'].Value } else { '' }
    $tabStateValid = $appContent -match 'queries:\s*\{\s*"candidate-sources": "",\s*"assessment-results": ""\s*\}' -and $appContent -match 'state\.queries\[state\.workspaceTab\] = value' -and $workspaceTabBody -match 'elements\["search-input"\]\.value = state\.queries\[tab\]' -and $workspaceTabBody -notmatch 'renderCandidateList|renderAssessmentResults'
    $assessmentResultsValid = $tabStateValid -and $indexContent -notmatch 'data-view="assessment-results"|assessment-results-search|data-assessment-mode|assessment-results-controls' -and ([regex]::Matches($indexContent, 'id="search-input"').Count -eq 1) -and $indexContent -match 'class="catalog-toolbar"[\s\S]*class="workspace-tabs" role="tablist"' -and $indexContent -match 'role="tab" aria-selected="true" aria-controls="candidate-sources-panel" data-workspace-tab="candidate-sources"' -and $indexContent -match 'role="tab" aria-selected="false" aria-controls="assessment-results-panel" data-workspace-tab="assessment-results"' -and $indexContent -match 'id="candidate-sources-panel" role="tabpanel"[\s\S]*class="catalog-layout"' -and $indexContent -match 'id="assessment-results-panel" role="tabpanel"[\s\S]*class="catalog-layout"' -and $appContent -notmatch 'assessmentQuery|assessmentMode|updateAssessmentFilter|setAssessmentMode' -and $appContent -match 'assessedCandidates:\s*\[\]' -and $appContent -match 'workspaceTab:\s*"candidate-sources"' -and $appContent -match 'state\.excludedCandidateCount = assessedCandidates\.filter\(\(\{ assessment \}\) => !assessment\.hostedApplicable\)\.length' -and $appContent -match 'refreshEffectiveCandidates\(\)' -and $appContent -match 'if \(candidate\.assessment\.hostedApplicable\) return false' -and $appContent -match 'elements\["assessment-results-count"\]\.textContent = formatNumber\(state\.excludedCandidateCount\)' -and $appContent -match 'candidate-category-items"><div class="assessment-results-header"' -and $appContent -notmatch 'assessment-results-list"\]\.innerHTML = `\s*<div class="assessment-results-header"' -and $appContent -match 'state\.workspaceTab === "candidate-sources"' -and $appContent -match 'Search excluded assessment results' -and $appContent -match 'Excluded from candidate catalog' -and $assessmentDetailBody -match 'renderApplicabilityOverride\(candidate\)' -and $assessmentDetailBody -notmatch 'data-rule-action|data-plan-toggle|getDecision\('
    Add-TestResult -Name 'assessment-results-audit' -Passed $assessmentResultsValid -Detail 'The shared toolbar swaps eligible and original AI-excluded workspaces; excluded counts and static headers are source-owned while provisional overrides remain visible in the audit.'

    $overrideContractValid = $appContent -match 'schemaVersion:\s*3' -and $appContent -match 'applicabilityOverrides:\s*\{\}' -and $appContent -match 'function getApplicabilityOverride' -and $appContent -match 'sourceContentSha256 !== candidate\.hash' -and $appContent -match 'originalHostedApplicable === false' -and $appContent -match 'effectiveHostedApplicable === true' -and $appContent -match 'function getEffectiveHostedApplicability' -and $appContent -match 'Maintainer Override:' -and $appContent -match 'data-override-open' -and $appContent -match 'data-override-apply' -and $appContent -match 'data-override-remove' -and $appContent -match 'recordedBy:\s*\{ type: "github-cli", login: identity\.login \}' -and $appContent -match 'applicabilityOverride: getApplicabilityOverride\(candidate\)' -and $appContent -match 'draft\.applicabilityOverrides' -and $appContent -match 'The AI assessment is read-only' -and $launcherContent -match 'gh -ErrorAction SilentlyContinue' -and $launcherContent -match 'api user --jq \.login' -and $launcherContent -match '''/hosted_copilot/''' -and $launcherContent -match 'maintainerIdentity = \$maintainerIdentity'
    Add-TestResult -Name 'maintainer-applicability-override' -Passed $overrideContractValid -Detail 'Authenticated Hosted CODEOWNERS can record reversible, source-bound provisional applicability corrections without mutating the original AI assessment.'

    $assessmentOwnershipValid = $appContent -match 'assessment:\s*candidate\.assessment \|\| getPriorAssessment\(candidate\)' -and $appContent -match 'const \{ assessment, \.\.\.maintainerDecision \} = current' -and $appContent -match 'state\.session\.decisions\[candidate\.key\] = \{\s*\.\.\.maintainerDecision,'
    Add-TestResult -Name 'current-bundle-assessment-ownership' -Passed $assessmentOwnershipValid -Detail 'Persisted maintainer decisions cannot override or re-export the assessment supplied by the current candidate bundle.'

    $darkThemeValid = $indexContent -match '<meta name="color-scheme" content="dark">' -and $stylesContent -match 'color-scheme: dark' -and $stylesContent -match '--paper: #0b1523' -and $stylesContent -match '--surface: rgba\(18, 33, 54, 0\.9\)' -and $stylesContent -match '--line: rgba\(142, 160, 208, 0\.18\)' -and $stylesContent -match '--line-strong: rgba\(142, 160, 208, 0\.35\)' -and $stylesContent -match '--accent: #68c6ff' -and $stylesContent -match '\.topbar\s*\{[^}]*border-bottom:\s*3px solid var\(--line-strong\)'
    Add-TestResult -Name 'dark-theme-contract' -Passed $darkThemeValid -Detail 'The Workbench uses navy surfaces, slate-blue structural lines, and cyan interaction accents.'

    $scrollbarThemeValid = $stylesContent -match 'scrollbar-color: var\(--scrollbar-thumb\) var\(--scrollbar-track\)' -and $stylesContent -match 'scrollbar-width: thin' -and $stylesContent -match '\*::\-webkit-scrollbar-thumb:hover' -and $stylesContent -match '--scrollbar-thumb-hover: #68c6ff'
    Add-TestResult -Name 'scrollbar-theme-contract' -Passed $scrollbarThemeValid -Detail 'Native scrollbars use the Workbench navy, slate-blue, and cyan palette.'

    $impactFactorsValid = $appContent -match 'AI Evaluation:' -and $appContent -match 'Assessment Details:' -and $appContent -match 'AI-adjudicated evidence' -and $appContent -match 'Recommend ' -and $appContent -match '<span>Token cost</span>' -and $appContent -notmatch 'Guarded token cost' -and $appContent -match 'Rule Value:' -and $appContent -match 'Review Risk:' -and $appContent -match 'Harm caused when this defect is missed' -and $appContent -match 'Chance of producing unsupported findings' -and $appContent -notmatch '<input type="range"' -and $appContent -notmatch 'data-decision-field="selectionRationale"' -and $stylesContent -match '\.factor-group\.value' -and $stylesContent -match '\.factor-group\.penalty' -and $stylesContent -match '\.factor-meter'
    Add-TestResult -Name 'impact-factor-guidance' -Passed $impactFactorsValid -Detail 'Pre-evaluated AI impact, cost, recommendation, factor evidence, and rationale are visible and read-only.'

    $detailLayoutValid = $stylesContent -match '#catalog-view\s*\{[^}]*max-width:\s*none' -and $stylesContent -match '#candidate-sources-panel \.catalog-layout\s*\{[^}]*grid-template-columns:\s*minmax\(460px, 0\.82fr\) minmax\(680px, 1\.18fr\)' -and $stylesContent -match '#candidate-sources-panel \.assessment-panel\s*\{[^}]*min-width:\s*min\(680px, 100%\)' -and $stylesContent -match '@media \(max-width: 1180px\)[\s\S]*#candidate-sources-panel \.assessment-panel\s*\{[^}]*min-width:\s*0'
    $sharedPresentationValid = $stylesContent -match 'body,\s*body \*\s*\{[^}]*font-family:\s*"IBM Plex Sans", sans-serif !important' -and $stylesContent -match '\.subcontext-container\s*\{[^}]*padding:\s*12px;[^}]*background:\s*var\(--blue-soft\);[^}]*border-left:\s*3px solid var\(--blue\)' -and $stylesContent -match '\.subcontext-container > p,\s*p\.subcontext-container\s*\{[^}]*color:\s*#c6d4ff;[^}]*font-size:\s*0\.8rem' -and $appContent -match 'overlap-item subcontext-container' -and $appContent -match 'ai-evaluation-summary subcontext-container' -and $appContent -match 'adjudication-text-box subcontext-container' -and $appContent -match 'evidence-summary-box subcontext-container'
    $actionControlsValid = $appContent -match 'DECISION_RATIONALE_MAX_LENGTH = 500' -and $appContent -match 'rule-actions-content subcontext-container' -and $appContent -match '<span class="control-subtitle">Rule Action:</span>\s*<div class="control-group action-plan-group">[\s\S]*?<fieldset class="action-options">[\s\S]*?<label class="plan-toggle' -and $appContent -match '<span class="control-subtitle">Decision Rationale:</span><textarea[^>]*maxlength="\$\{DECISION_RATIONALE_MAX_LENGTH\}"[^>]*aria-describedby="decision-rationale-limit"' -and $appContent -match 'rationale-limit.*DECISION_RATIONALE_MAX_LENGTH' -and $appContent -match 'decision\.rationale\.length > DECISION_RATIONALE_MAX_LENGTH' -and $stylesContent -match '\.field-stack textarea\s*\{[^}]*height:\s*84px;[^}]*max-height:\s*84px;[^}]*resize:\s*none;[^}]*overflow-y:\s*auto'
    $assessmentLegendValid = $appContent -notmatch 'impact / 100 tokens' -and $appContent -match '<span class="control-subtitle scoring-legend-title">Scoring Legend:</span>\s*<div class="scoring-legend subcontext-container">' -and $appContent -match 'Score Scale:</span><span>Scores run from 0 \(none\) through 5 \(very high\)' -and $appContent -match 'Existing Coverage:</span><span>0 means no current Hosted coverage; 5 means active Hosted rules already cover the behavior completely' -and $appContent -match 'direction-badge positive">Adds to Impact' -and $appContent -match 'direction-badge negative">Reduces Impact' -and $appContent -match 'risk-\$\{value <= 2 \? "low" : value === 3 \? "moderate" : "high"\}' -and $stylesContent -match '\.factor-line\.penalty\.risk-low \.factor-value\s*\{[^}]*color:\s*var\(--success\)' -and $stylesContent -match '\.scoring-legend-item\s*\{[^}]*grid-template-columns:\s*minmax\(0, 1fr\)'
    $detailPresentationValid = $detailLayoutValid -and $sharedPresentationValid -and $actionControlsValid -and $assessmentLegendValid -and $appContent -match 'candidate-state \$\{escapeHtml\(candidate\.state\)\}">\$\{escapeHtml\(capitalize\(candidate\.state\)\)\}' -and $appContent -match 'return value === "no-change" \? "No Change"' -and $stylesContent -match '\.decision-badge\.no-change,[\s\S]*\.recommendation-badge\.no-change\s*\{[^}]*border-color:\s*rgba\(142, 160, 208, 0\.72\)'
    Add-TestResult -Name 'detail-presentation-contract' -Passed $detailPresentationValid -Detail 'The eligible detail uses the approved full-width layout, unified status capsules and section headings, evidence boxes, summary hierarchy, native radios, and compact action spacing.'

    $staticInformationColorsValid = $stylesContent -match '\.stage-link\.active\s*\{[^}]*box-shadow:\s*3px 0 0 var\(--blue\) inset' -and $stylesContent -match '\.save-indicator\s*\{[^}]*color:\s*var\(--blue\)' -and $stylesContent -match '\.plan-count-control strong\s*\{[^}]*color:\s*var\(--blue\)' -and $stylesContent -match '\.candidate-source-root > summary\s*\{[^}]*color:\s*#c6d4ff' -and $stylesContent -match '\.tree-impact\s*\{[^}]*color:\s*var\(--blue\)' -and $stylesContent -match '\.ai-evaluation-summary\s*\{[^}]*background:\s*var\(--blue-soft\);[^}]*border-left:\s*4px solid var\(--blue\)' -and $stylesContent -match '\.score-item\.efficiency strong\s*\{[^}]*color:\s*#c6d4ff' -and $stylesContent -match '\.toast\s*\{[^}]*border-left:\s*4px solid var\(--blue\)'
    Add-TestResult -Name 'static-information-colors' -Passed $staticInformationColorsValid -Detail 'Current-view chrome, selection counts, impact values, efficiency, and headroom use slate blue rather than the cyan interaction accent.'

    $sourceTreeValid = $appContent -match 'candidate-source-root' -and $appContent -match 'candidate-category' -and $appContent -match '\["maintainer", "Maintainer Proposals"\]' -and $appContent -match 'key: `maintainer:\$\{candidate\.id\}`' -and $appContent -match 'Proposal rationale' -and $appContent -notmatch 'data-category-checkbox' -and $appContent -match 'data-decision-key' -and $appContent -notmatch 'reviewSet' -and $stylesContent -match '\.candidate-tree-row' -and $stylesContent -match '\.candidate-list-header' -and $stylesContent -match '\.candidate-category > summary\s*\{[^}]*grid-template-columns:\s*18px minmax\(0, 1fr\) auto'
    Add-TestResult -Name 'evaluated-source-tree' -Passed $sourceTreeValid -Detail 'Interactive, Contributor Guidance, and Maintainer Proposals candidates are grouped by source with promotion-plan checkboxes only on leaf candidates.'

    $contributorHierarchyValid = $appContent -match 'sourceType === "upstream"\s*\? renderCandidateItems\(`\$\{sourceType\}:all`, candidates, "contributor-candidates"\)' -and $appContent -match 'Object\.entries\(groupCandidatesByCategory\(candidates\)\)' -and $appContent -match 'function renderCandidateItems\(' -and $appContent -match 'function renderCandidateListHeader\(' -and $appContent -match 'data-candidate-sort=' -and $appContent -match '\["candidate", "Candidate", "Candidate"\]' -and $appContent -match '\["recommendation", "Recommended", "Recommendation"\]' -and $appContent -match 'chevron-\$\{sort\.direction === "ascending" \? "up" : "down"\}' -and $appContent -match 'return state\.candidateSorts\[sectionKey\] \|\| \{ field: "candidate", direction: "ascending" \}' -and $appContent -match 'button\.closest\("\.candidate-category-items"\)'
    Add-TestResult -Name 'contributor-direct-children' -Passed $contributorHierarchyValid -Detail 'Contributor Guidance rules render directly beneath their source root while Interactive Toolkit rules retain category folders.'

    $directTreeUpdatesValid = $appContent -match 'function syncCandidateTreeRows' -and $appContent -match 'function selectCandidate\(key\)\s*\{[^}]*syncCandidateTreeRows\(\)' -and $appContent -match 'function updateDecision\(candidate, changes\)[\s\S]*?syncCandidateTreeRows\(\);\s*renderDecisionOutputs\(\);\s*\}' -and $appContent -match 'function updateCandidateSort\(button\)[\s\S]*?group\.appendChild\(rowsByKey\.get\(candidate\.key\)\)'
    Add-TestResult -Name 'tree-leaf-direct-updates' -Passed $directTreeUpdatesValid -Detail 'Candidate and checkbox decisions update leaf DOM state without rebuilding or collapsing expanded source and category folders.'

    $ruleActionsValid = $indexContent -match 'id="plan-action-count">0 actions' -and $appContent -match 'function getCatalogStatus' -and $appContent -match 'function getAllowedActions' -and $appContent -match 'allowedActions\.map\(\(action\)' -and $appContent -match 'data-rule-action=' -and $appContent -match 'type="radio" name="rule-action"' -and $appContent -match 'data-plan-toggle' -and $appContent -match 'catalogStatus:\s*getCatalogStatus\(candidate\)\.key' -and $appContent -notmatch 'disposition' -and $appContent -match 'schemaVersion:\s*3,\s*kind: "hosted-rule-workbench-draft"'
    Add-TestResult -Name 'catalog-status-rule-actions' -Passed $ruleActionsValid -Detail 'Authoritative mappings are separate from source state; native radios expose only status-constrained actions, and plan membership remains an independent explicit choice.'

    $capacityProjectionValid = $appContent -match 'Plan projection' -and $appContent -match 'getProjectedCapacityDelta' -and $appContent -match 'projectedGuardedTokens' -and $appContent -match 'projectedHeadroomTokens' -and $appContent -match 'function renderDecisionOutputs\(\)[\s\S]*?renderPlan\(\);[\s\S]*?renderCapacity\(\);[\s\S]*?renderPreview\(\);[\s\S]*?renderCounts\(\);' -and $appContent -match 'Action restored to plan' -and $appContent -match 'getPlanCandidates\(\)' -and $stylesContent -match '\.toast\.visible\s*\{[^}]*pointer-events:\s*auto'
    Add-TestResult -Name 'undo-updates-capacity-projection' -Passed $capacityProjectionValid -Detail 'Action selection, plan membership, Undo, and Restore recompute guarded usage, headroom, utilization, and draft cost.'

    $semanticColorsValid = $stylesContent -match '\.recommendation-badge\s*\{[^}]*background:\s*#303b60;[^}]*border:\s*1px solid #7f91c4' -and $stylesContent -match '\.recommendation-badge\.add\s*\{[^}]*background:\s*#174638' -and $stylesContent -match '\.recommendation-badge\.exclude\s*\{[^}]*background:\s*#4a252b' -and $stylesContent -match '\.recommendation-badge\.defer\s*\{[^}]*background:\s*#493812' -and $stylesContent -match '\.candidate-lifecycle,\s*\.candidate-state\s*\{[^}]*border:\s*1px solid #7f91c4' -and $stylesContent -match '\.candidate-tree-row\.in-plan:not\(\.active\)\s*\{[^}]*background:\s*rgba\(97, 226, 148, 0\.06\)' -and $stylesContent -match '\.catalog-status\.mapped' -and $stylesContent -match '\.action-option\.selected' -and $stylesContent -match '\.plan-undo:hover\s*\{[^}]*background:\s*#31506b'
    Add-TestResult -Name 'semantic-color-contract' -Passed $semanticColorsValid -Detail 'Lifecycle, recommendation, catalog mapping, selected action, plan membership, and Undo states use readable semantic colors and visible borders.'

    $planColumnsValid = $indexContent -match '<col class="plan-column-actions">' -and $indexContent -match '<th>Actions</th>' -and $stylesContent -match '\.plan-table\s*\{[^}]*table-layout:\s*fixed' -and $stylesContent -match '\.plan-column-actions\s*\{[^}]*width:\s*88px' -and $stylesContent -match '\.plan-table th:last-child\s*\{[^}]*text-align:\s*center'
    Add-TestResult -Name 'promotion-plan-column-alignment' -Passed $planColumnsValid -Detail 'Promotion plan header and body share six fixed columns, including a centered Actions column covering Undo.'

    $approvalExportValid = $indexContent -match 'id="approver-name"' -and $indexContent -match 'id="approve-export-button"[^>]*disabled' -and $indexContent -match 'Approve &amp; Export' -and $appContent -match 'function getPreviewReadiness' -and $appContent -match 'function buildApprovalPayload' -and $appContent -match 'function approveAndExport' -and $appContent -match 'hosted-rule-workbench-approval-handoff' -and $appContent -match 'sha256-payload-bytes-v1' -and $appContent -match 'crypto\.subtle\.digest\("SHA-256"' -and $appContent -match 'approvedBy:\s*\{\s*type:\s*"manual"' -and $stylesContent -match '\.approval-controls'
    Add-TestResult -Name 'preview-approval-export' -Passed $approvalExportValid -Detail 'Preview requires selected-rule rationale and manual approver identity before exporting a SHA-256-bound immutable approval handoff.'

    $previewDiffValid = $indexContent -match 'id="preview-diff"' -and $indexContent -match 'id="preview-payload-diff"' -and $indexContent -match '<details class="preview-raw-payload">' -and $indexContent -match 'Raw Selection Payload' -and $appContent -match 'function renderPreviewChanges\(' -and $appContent -match 'decision\.action === "add"' -and $appContent -match 'decision\.action === "retire"' -and $appContent -match 'function diffTextLines\(' -and $appContent -match 'diff-line \$\{line\.type\}' -and $appContent -match 'function renderPayloadChanges\(' -and $appContent -match 'Object\.keys\(after\)\.filter' -and $appContent -match 'renderPayloadColumn\("Default", beforeLines, "delete"\)' -and $appContent -match 'renderPayloadColumn\("Current", afterLines, "add"\)' -and $stylesContent -match '\.diff-line\.add\s*\{[^}]*background:\s*rgba\(46, 160, 67, 0\.2\)' -and $stylesContent -match '\.diff-line\.delete\s*\{[^}]*background:\s*rgba\(248, 81, 73, 0\.2\)' -and $stylesContent -match '\.payload-columns\s*\{[^}]*grid-template-columns:\s*minmax\(0, 1fr\) minmax\(0, 1fr\)'
    Add-TestResult -Name 'preview-change-review' -Passed $previewDiffValid -Detail 'Preview renders every planned rule as an action-aware unified diff, compares changed selection fragments side by side, and keeps raw JSON as a collapsed audit fallback.'

    $noOpUpdateValid = $appContent -match 'function hasHostedTextChange\(' -and $appContent -match 'if \(hasHostedTextChange\(candidate, proposedText\)\) actions\.push\("update"\)' -and $appContent -match 'Current and proposed Hosted rule text are identical, so Update is unavailable\.' -and $appContent -match 'const allowedActions = getAllowedActions\(candidate, proposedText\)' -and $appContent -match 'inPlan: saved\.inPlan && isPromotionAction\(saved\.action\)'
    Add-TestResult -Name 'no-op-update-suppression' -Passed $noOpUpdateValid -Detail 'Mapped candidates expose Update only when proposed Hosted text differs, and stale no-op updates normalize out of the promotion plan.'

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
