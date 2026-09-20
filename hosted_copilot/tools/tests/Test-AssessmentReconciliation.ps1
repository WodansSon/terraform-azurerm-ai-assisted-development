[CmdletBinding()]
param(
    [ValidateSet('Text', 'Json')]
    [string]$OutputFormat = 'Text'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Import-Module (Join-Path $PSScriptRoot '../../../tools/ValidationOutput.psm1') -Force
Import-Module (Join-Path $PSScriptRoot '../modules/shared/SourceEvidenceValidation.psm1') -Force
Import-Module (Join-Path $PSScriptRoot '../modules/shared/HostedToolkit.Helpers.psm1') -Force

$repositoryRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))
$catalogRoot = Join-Path $repositoryRoot 'hosted_copilot/copilot-rule-catalog'
$reconciliationRoot = Join-Path $catalogRoot 'assessment-reconciliation'
$builderPath = Join-Path $PSScriptRoot '../internal/reconciliation/New-WorkbenchDisplay.ps1'
$runnerPath = Join-Path $PSScriptRoot '../internal/reconciliation/Invoke-AssessmentReconciliation.ps1'
$catalogPath = Join-Path $catalogRoot 'instruction-catalog.json'
$displaySchemaPath = Join-Path $reconciliationRoot 'workbench-display-v4.schema.json'
$tempRoot = Join-Path ([IO.Path]::GetTempPath()) ('hosted-assessment-reconciliation-test-' + [guid]::NewGuid().ToString('N'))
$generatedAt = '2026-09-16T12:00:00Z'
$contentSha256 = 'a' * 64
$results = [Collections.Generic.List[object]]::new()
$issues = [Collections.Generic.List[string]]::new()

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

function Write-TestProgress {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][string]$Detail
    )

    if ($OutputFormat -eq 'Text') {
        Write-Host (Format-ValidationStatusLine -Status 'running' -Name $Name -Detail $Detail)
    }
}

function Write-JsonFixture {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][object]$Value
    )

    [IO.File]::WriteAllText($Path, (($Value | ConvertTo-Json -Depth 50) + "`n"), [Text.UTF8Encoding]::new($false))
}

function Copy-JsonObject {
    param([Parameter(Mandatory = $true)][object]$Value)

    return ($Value | ConvertTo-Json -Depth 50 -Compress) | ConvertFrom-Json -DateKind String
}

function Test-JsonInstance {
    param(
        [Parameter(Mandatory = $true)][object]$Value,
        [Parameter(Mandatory = $true)][string]$SchemaPath
    )

    try {
        return [bool](($Value | ConvertTo-Json -Depth 50) | Test-Json -SchemaFile $SchemaPath -ErrorAction Stop)
    }
    catch {
        return $false
    }
}

function New-Assessment {
    param(
        [Parameter(Mandatory = $true)][string]$AssessmentId,
        [Parameter(Mandatory = $true)][string]$Title,
        [Parameter(Mandatory = $true)][bool]$HostedApplicable
    )

    return [ordered]@{
        assessmentId = $AssessmentId
        title = $Title
        sourceMeaning = "$Title meaning"
        impactDescription = "$Title impact"
        assessmentProvenance = [ordered]@{
            originSchemaVersion = 4
            status = 'evaluated'
            assessedAt = $generatedAt
            assessmentEvaluator = [ordered]@{ kind = 'llm'; identity = 'fixture'; model = 'fixture-model' }
        }
        hostedApplicable = $HostedApplicable
        applicabilityRationale = if ($HostedApplicable) { 'Applicable to Hosted review.' } else { 'Outside Hosted review scope.' }
        assessmentConfidence = [ordered]@{ level = 'high'; rationale = 'Fixture evidence is explicit.'; uncertainties = @() }
        selectionFactors = [ordered]@{ severity = 3; frequency = 3; breadth = 3; hostedDetectability = 3; evidenceStrength = 4; falsePositiveRisk = 1; redundancy = 1 }
        selectionRationale = 'Fixture selection rationale.'
        affectedSurfaces = @('implementation')
        sourceLocalProposedText = 'Validate the fixture behavior.'
        mappedHostedRuleIds = @()
        relatedHostedCoverage = @()
        existingCoverage = [ordered]@{ score = 0; rationale = 'No existing coverage.' }
        semanticReassessment = $null
    }
}

function New-SourceEntry {
    param(
        [Parameter(Mandatory = $true)][string]$SourceDefinitionId,
        [Parameter(Mandatory = $true)][string]$SourceId,
        [Parameter(Mandatory = $true)][string]$Title,
        [Parameter(Mandatory = $true)][bool]$HostedApplicable
    )

    return [ordered]@{
        sourceRef = [ordered]@{ sourceDefinitionId = $SourceDefinitionId; sourceId = $SourceId; contentSha256 = $contentSha256 }
        transition = 'current'
        priorSourceEvidence = $null
        assessments = @((New-Assessment -AssessmentId 'hosted-check' -Title $Title -HostedApplicable $HostedApplicable))
    }
}

function Get-AssessmentRef {
    param([Parameter(Mandatory = $true)][object]$Entry)

    return [ordered]@{
        sourceDefinitionId = [string]$Entry.sourceRef.sourceDefinitionId
        sourceId = [string]$Entry.sourceRef.sourceId
        contentSha256 = [string]$Entry.sourceRef.contentSha256
        assessmentId = [string]$Entry.assessments[0].assessmentId
    }
}

function Invoke-DisplayBuilder {
    param(
        [Parameter(Mandatory = $true)][object]$Draft,
        [Parameter(Mandatory = $true)][string]$Name,
        [string]$AssessmentSetPath = $script:assessmentSetPath,
        [string]$HostedCatalogPath = $script:catalogPath,
        [string[]]$InventoryPaths = $script:inventoryPaths
    )

    $draftPath = Join-Path $tempRoot "$Name-reconciliation.json"
    $outputPath = Join-Path $tempRoot "$Name-display.json"
    Write-JsonFixture -Path $draftPath -Value $Draft
    try {
        $output = @(& $builderPath -RepositoryRoot $repositoryRoot -AssessmentBaselinePath $AssessmentSetPath -InventoryPaths $InventoryPaths -ReconciliationDraftPath $draftPath -GuidanceCapacityPath $guidanceCapacityPath -OutputPath $outputPath -HostedCatalogPath $HostedCatalogPath -GeneratedAt $generatedAt -OutputFormat Json 2>&1)
        $exitCode = 0
    }
    catch {
        $output = @($_)
        $exitCode = 1
    }
    return [pscustomobject]@{ ExitCode = $exitCode; Output = ($output | Out-String).Trim(); OutputPath = $outputPath }
}

function New-CatalogBoundAssessmentSet {
    param(
        [Parameter(Mandatory = $true)][object]$AssessmentSet,
        [Parameter(Mandatory = $true)][string]$HostedCatalogPath,
        [Parameter(Mandatory = $true)][string]$Name
    )

    $copy = Copy-JsonObject -Value $AssessmentSet
    $copy.hostedCatalogSha256 = Get-Sha256 -Path $HostedCatalogPath
    $path = Join-Path $tempRoot "$Name-assessment-set.json"
    Write-JsonFixture -Path $path -Value $copy
    return $path
}

try {
    $null = New-Item -ItemType Directory -Path $tempRoot -Force
    if ($OutputFormat -eq 'Text') {
        Write-ValidationSectionHeader -Title 'Hosted assessment reconciliation'
    }

    $runnerContent = Get-Content -LiteralPath $runnerPath -Raw
    $reconciliationInputUnbounded = $runnerContent -notmatch 'EvaluatorPayloadBudgetBytes|Get-PayloadSizeBytes|payload exceeds evaluator budget'
    Add-TestResult -Name 'reconciliation-input-not-guidance-budget' -Passed $reconciliationInputUnbounded -Detail 'Reconciliation input size is not conflated with final Hosted guidance token-capacity enforcement.'

    Write-TestProgress -Name 'fixture-validation' -Detail 'Preparing source lanes, assessment set, reconciliation response, catalog, and capacity'

    $entries = @(
        (New-SourceEntry -SourceDefinitionId 'contributor-guidance' -SourceId 'guide-new-resource' -Title 'Contributor guidance' -HostedApplicable $true),
        (New-SourceEntry -SourceDefinitionId 'interactive-toolkit' -SourceId 'IMPL-SCHEMA-901' -Title 'Interactive rule' -HostedApplicable $true),
        (New-SourceEntry -SourceDefinitionId 'maintainer-proposals' -SourceId 'DOCS-SOURCE-901' -Title 'Maintainer source rule' -HostedApplicable $false)
    )
    $records = [ordered]@{
        'contributor-guidance' = [ordered]@{ sourceId = 'guide-new-resource'; presence = 'present'; sourceLifecycle = 'active'; location = 'contributing/topics/new-resource.md'; contentSha256 = $contentSha256; content = 'Contributor source content.'; title = 'Contributor guidance'; repository = 'hashicorp/terraform-provider-azurerm'; resolvedCommit = 'a' * 40; referenceUrl = "https://github.com/hashicorp/terraform-provider-azurerm/blob/$('a' * 40)/contributing/topics/new-resource.md" }
        'interactive-toolkit' = [ordered]@{ sourceId = 'IMPL-SCHEMA-901'; presence = 'present'; sourceLifecycle = 'active'; location = '.github/instructions/implementation-compliance-contract.instructions.md'; contentSha256 = $contentSha256; content = 'Interactive source content.'; title = 'Interactive rule'; contractPath = '.github/instructions/implementation-compliance-contract.instructions.md'; provenance = 'local-safeguard'; evidence = @(); sourceIds = @() }
        'maintainer-proposals' = [ordered]@{ sourceId = 'DOCS-SOURCE-901'; presence = 'present'; sourceLifecycle = 'active'; location = 'hosted_copilot/copilot-rule-catalog/maintainer-rules/documentation.rules.md'; contentSha256 = $contentSha256; content = 'Maintainer source content.'; title = 'Maintainer source rule'; surface = 'documentation'; ruleText = 'Document the source behavior.'; provenance = 'local-safeguard'; rationale = 'Fixture rationale.'; evidence = @() }
    }
    $inventoryPathList = [Collections.Generic.List[string]]::new()
    $inventoryHashes = [ordered]@{}
    foreach ($sourceDefinitionId in @('contributor-guidance', 'interactive-toolkit', 'maintainer-proposals')) {
        $sourceEvidence = Get-CurrentSourceDefinitionEvidence -RepositoryRoot $repositoryRoot -SourceDefinitionId $sourceDefinitionId
        $sourceRevision = if ($sourceDefinitionId -ceq 'contributor-guidance') {
            [ordered]@{ kind = 'github-commit'; configuredRef = 'main'; overrideUsed = $false; resolvedCommit = 'a' * 40 }
        }
        else {
            [ordered]@{ kind = 'repository-worktree'; resolvedCommit = $null; worktreeDirty = $false; worktreeSha256 = $contentSha256 }
        }
        $inventory = [ordered]@{
            '$schema' = 'source-inventory.schema.json'
            schemaVersion = 1
            sourceDefinitionId = $sourceDefinitionId
            sourceDefinitionSha256 = [string]$sourceEvidence.SourceDefinitionSha256
            inventoryConfigurationSha256 = [string]$sourceEvidence.InventoryConfigurationSha256
            collectorVersion = 1
            parserId = [string]$sourceEvidence.ParserId
            parserContractSha256 = [string]$sourceEvidence.ParserContractSha256
            collectedAt = $generatedAt
            collection = [ordered]@{ complete = $true; sourceRevision = $sourceRevision; inventorySha256 = Get-SourceEvidenceRecordsSha256 -Records @($records[$sourceDefinitionId]) }
            records = @($records[$sourceDefinitionId])
        }
        $inventoryPath = Join-Path $tempRoot "$sourceDefinitionId-inventory.json"
        Write-JsonFixture -Path $inventoryPath -Value $inventory
        $inventoryPathList.Add($inventoryPath)
        $inventoryHashes[$sourceDefinitionId] = Get-Sha256 -Path $inventoryPath
    }
    [string[]]$inventoryPaths = $inventoryPathList.ToArray()

    $capacityReports = @('repository', 'go', 'test', 'documentation', 'skill', 'go-combined', 'test-combined', 'documentation-combined') | ForEach-Object {
        [ordered]@{ name = $_; kind = if ($_ -like '*-combined') { 'combined' } else { 'file' }; paths = @("fixture/$_.md"); characterCount = 400; estimatedTokens = 100; guardedTokens = 125; budgetTokens = 1000; budgetHeadroomTokens = 875; utilizationPercent = 12.5; withinBudget = $true }
    }
    $guidanceCapacityPath = Join-Path $tempRoot 'guidance-capacity.json'
    Write-JsonFixture -Path $guidanceCapacityPath -Value ([ordered]@{ status = 'passed'; estimator = 'character-quarter-estimate-25pct-v1'; safetyMarginPercent = 25; reportCount = 8; reports = $capacityReports })

    $sourceDefinitions = @('contributor-guidance', 'interactive-toolkit', 'maintainer-proposals') | ForEach-Object {
        $sourceEvidence = Get-CurrentSourceDefinitionEvidence -RepositoryRoot $repositoryRoot -SourceDefinitionId $_
        [ordered]@{ sourceDefinitionId = $_; sourceDefinitionSha256 = [string]$sourceEvidence.SourceDefinitionSha256; parserContractSha256 = [string]$sourceEvidence.ParserContractSha256; inventoryConfigurationSha256 = [string]$sourceEvidence.InventoryConfigurationSha256; assessmentBatchSize = [int]$sourceEvidence.AssessmentBatchSize; assessmentCardinality = [string]$sourceEvidence.AssessmentCardinality }
    }
    $runConfiguration = [ordered]@{ mode = 'evaluated'; model = 'fixture-model'; reasoningEffort = 'high'; evaluator = 'fixture'; evaluatorPayloadBudgetBytes = 393216; sourceDefinitions = $sourceDefinitions }
    $assessmentContract = Get-Content -LiteralPath (Join-Path $catalogRoot 'rule-assessments/source-assessment-v4.json') -Raw | ConvertFrom-Json -DateKind String
    $assessmentSet = [ordered]@{
        '$schema' = 'source-assessment-baseline-v4.schema.json'
        schemaVersion = 4
        generatedAt = $generatedAt
        inventoryHashes = $inventoryHashes
        priorInventoryHashes = [ordered]@{}
        hostedCatalogSha256 = Get-Sha256 -Path $catalogPath
        assessmentContractSha256 = Get-SourceAssessmentContractSha256 -Contract $assessmentContract -RepositoryRoot $repositoryRoot
        assessmentRunConfigurationSha256 = Get-SourceAssessmentRunConfigurationSha256 -RunConfiguration $runConfiguration
        runConfiguration = $runConfiguration
        entries = $entries
    }
    $assessmentSetPath = Join-Path $tempRoot 'assessment-set.json'
    Write-JsonFixture -Path $assessmentSetPath -Value $assessmentSet
    Add-TestResult -Name 'three-lane-assessment-set' -Passed (Test-JsonInstance -Value $assessmentSet -SchemaPath (Join-Path $catalogRoot 'rule-assessments/source-assessment-baseline-v4.schema.json')) -Detail 'The fixture contains one valid assessment from each source lane.'

    $contributorRef = Get-AssessmentRef -Entry $entries[0]
    $interactiveRef = Get-AssessmentRef -Entry $entries[1]
    $maintainerRef = Get-AssessmentRef -Entry $entries[2]
    $draft = [ordered]@{
        '$schema' = 'assessment-reconciliation-draft.schema.json'
        schemaVersion = 1
        recommendations = @(
            [ordered]@{ draftKey = 'recommendation-1'; recommendedAction = 'add'; targetHostedId = $null; idFamily = 'IMPL-SCHEMA'; title = 'Validate imported schema behavior'; recommendedRuleText = 'Validate imported schema behavior against the provider implementation.'; category = 'implementation'; placement = 'Schema And State'; rationale = 'Two assessments describe one enforceable Hosted behavior.'; needsReview = $false; memberAssessmentRefs = @($contributorRef, $interactiveRef); relatedHostedCoverage = @(); implementationModels = @('legacy', 'typed', 'framework') },
            [ordered]@{ draftKey = 'recommendation-2'; recommendedAction = 'exclude'; targetHostedId = $null; idFamily = 'DOCS-EX'; title = 'Exclude maintainer source rule'; recommendedRuleText = 'Document the source behavior.'; category = 'documentation'; placement = 'Examples And Imports'; rationale = 'The assessment is outside Hosted review scope unless a maintainer overrides applicability.'; needsReview = $false; memberAssessmentRefs = @($maintainerRef); relatedHostedCoverage = @() }
        )
        assessmentCoverage = @(
            [ordered]@{ assessmentRef = $contributorRef; disposition = 'recommended'; rationale = $null; recommendationDraftKeys = @('recommendation-1') },
            [ordered]@{ assessmentRef = $interactiveRef; disposition = 'recommended'; rationale = $null; recommendationDraftKeys = @('recommendation-1') },
            [ordered]@{ assessmentRef = $maintainerRef; disposition = 'excluded'; rationale = 'Outside Hosted review scope.'; recommendationDraftKeys = @('recommendation-2') }
        )
    }
    Add-TestResult -Name 'reconciliation-response-schema' -Passed (Test-JsonInstance -Value $draft -SchemaPath (Join-Path $reconciliationRoot 'assessment-reconciliation-draft.schema.json')) -Detail 'The evaluator response has strict recommendations and exhaustive coverage.'
    $missingImplementationModels = Copy-JsonObject -Value $draft
    $missingImplementationModels.recommendations[0].PSObject.Properties.Remove('implementationModels')
    Add-TestResult -Name 'implementation-model-scope-required' -Passed (-not (Test-JsonInstance -Value $missingImplementationModels -SchemaPath (Join-Path $reconciliationRoot 'assessment-reconciliation-draft.schema.json'))) -Detail 'An implementation Add cannot reach trusted ID allocation without explicit implementation model scope.'

    Write-TestProgress -Name 'display-production' -Detail 'Building display candidates, catalog projection, capacity, and fingerprint'

    $firstRun = Invoke-DisplayBuilder -Draft $draft -Name 'canonical'
    if ($firstRun.ExitCode -ne 0) {
        throw "Direct Workbench display build failed: $($firstRun.Output)"
    }
    $firstResult = $firstRun.Output | ConvertFrom-Json -DateKind String
    $display = Get-Content -LiteralPath $firstRun.OutputPath -Raw | ConvertFrom-Json -DateKind String
    Add-TestResult -Name 'display-schema' -Passed (Test-JsonInstance -Value $display -SchemaPath $displaySchemaPath) -Detail 'The producer emits the strict v4 display contract.'
    Add-TestResult -Name 'display-reported-hash' -Passed ([string]$firstResult.displaySha256 -ceq (Get-Sha256 -Path $firstRun.OutputPath)) -Detail 'The producer reports the exact display-byte hash.'
    Add-TestResult -Name 'complete-candidate-coverage' -Passed (@($display.candidates).Count -eq 3) -Detail 'Every assessment becomes one display candidate.'
    $recommended = @($display.candidates | Where-Object reviewState -eq 'recommended')
    $excluded = @($display.candidates | Where-Object reviewState -eq 'excluded')
    Add-TestResult -Name 'recommendation-presentation' -Passed ($recommended.Count -eq 2 -and @($recommended | Where-Object { [string]$_.recommendation.ruleText -cne 'Validate imported schema behavior against the provider implementation.' }).Count -eq 0) -Detail 'Recommendation action, identity, wording, and membership remain available to the UI.'
    $approvalMetadata = $recommended[0].recommendation
    $approvalMetadataValid = (@($approvalMetadata.provenance | Sort-Object) -join ',') -ceq 'local-safeguard,published-upstream-standard' -and (@($approvalMetadata.evidenceIds | Sort-Object) -join ',') -ceq 'hosted-architecture,implementation-contract' -and (@($approvalMetadata.implementationModels | Sort-Object) -join ',') -ceq 'framework,legacy,typed' -and @($approvalMetadata.sourceRelationships).Count -eq 2
    Add-TestResult -Name 'approval-metadata-derived' -Passed $approvalMetadataValid -Detail 'The producer derives registered evidence, source provenance, implementation model scope, and source relationships from exact recommendation members.'
    $projectedCatalogRule = @($display.catalog.rules | Where-Object { [string]$_.id -ceq 'IMPL-EVID-001' })[0]
    $catalogMetadataValid = [string]$projectedCatalogRule.origin -ceq 'hosted-baseline-migration' -and @($projectedCatalogRule.provenance).Count -gt 0 -and @($projectedCatalogRule.evidenceIds).Count -gt 0 -and @($projectedCatalogRule.implementationModels).Count -gt 0
    Add-TestResult -Name 'complete-catalog-rule-projection' -Passed $catalogMetadataValid -Detail 'Existing catalog rules retain the complete metadata required for Update, Retire, and Restore mutations.'
    Add-TestResult -Name 'excluded-candidate-visible' -Passed ($excluded.Count -eq 1 -and [string]$excluded[0].recommendation.action -ceq 'exclude' -and [string]$excluded[0].recommendation.hostedId -like 'DOCS-EX-*') -Detail 'Excluded assessments remain visible with contingent reconciliation-owned identity and metadata.'
    $obsoleteDisplayProperties = @(@('snapshots', 'acceptedSourceGeneration', 'stagedInventories', 'assessmentBaseline', 'recommendationOutput') | Where-Object { $display.PSObject.Properties[$_] })
    Add-TestResult -Name 'display-excludes-transaction-state' -Passed ($obsoleteDisplayProperties.Count -eq 0) -Detail 'The display excludes generation and transaction state.'

    Write-TestProgress -Name 'retired-rule-lifecycle' -Detail 'Validating tombstone projection, historical placement, and invalid lifecycle combinations'

    $retiredCatalog = Copy-JsonObject -Value (Get-Content -LiteralPath $catalogPath -Raw | ConvertFrom-Json -DateKind String)
    $surface = $retiredCatalog.surfaces[0]
    $section = $surface.sections[0]
    $retiredId = [string]$section.ruleIds[0]
    $retiredRule = @($retiredCatalog.rules | Where-Object { [string]$_.id -ceq $retiredId })[0]
    $lastPlacement = [ordered]@{ surfaceId = [string]$surface.id; sectionHeading = [string]$section.heading }
    $section.ruleIds = @($section.ruleIds | Where-Object { [string]$_ -cne $retiredId })
    $retiredRule.status = 'retired'
    $retiredRule | Add-Member -NotePropertyName retirementReason -NotePropertyValue 'Superseded by a more precise rule.'
    $retiredRule | Add-Member -NotePropertyName lastPlacement -NotePropertyValue $lastPlacement
    $retiredCatalogPath = Join-Path $tempRoot 'retired-catalog.json'
    Write-JsonFixture -Path $retiredCatalogPath -Value $retiredCatalog
    $retiredAssessmentSetPath = New-CatalogBoundAssessmentSet -AssessmentSet $assessmentSet -HostedCatalogPath $retiredCatalogPath -Name 'retired'
    $retiredRun = Invoke-DisplayBuilder -Draft $draft -Name 'retired' -AssessmentSetPath $retiredAssessmentSetPath -HostedCatalogPath $retiredCatalogPath
    $retiredDisplay = if ($retiredRun.ExitCode -eq 0) { Get-Content -LiteralPath $retiredRun.OutputPath -Raw | ConvertFrom-Json -DateKind String } else { $null }
    $projectedTombstone = if ($null -ne $retiredDisplay) { @($retiredDisplay.catalog.rules | Where-Object { [string]$_.id -ceq $retiredId })[0] } else { $null }
    $tombstoneValid = $retiredRun.ExitCode -eq 0 -and [string]$projectedTombstone.id -ceq $retiredId -and [string]$projectedTombstone.status -ceq 'retired' -and @($projectedTombstone.placements).Count -eq 0 -and [string]$projectedTombstone.retirementReason -ceq 'Superseded by a more precise rule.' -and [string]$projectedTombstone.lastPlacement.surfaceId -ceq [string]$lastPlacement.surfaceId -and [string]$projectedTombstone.lastPlacement.sectionHeading -ceq [string]$lastPlacement.sectionHeading
    Add-TestResult -Name 'retired-tombstone-projection' -Passed $tombstoneValid -Detail $(if ($tombstoneValid) { 'A retired rule retains its immutable ID, wording, reason, and last placement without an active placement.' } else { $retiredRun.Output })

    $activeUnplacedCatalog = Copy-JsonObject -Value $retiredCatalog
    $activeUnplacedRule = @($activeUnplacedCatalog.rules | Where-Object { [string]$_.id -ceq $retiredId })[0]
    $activeUnplacedRule.status = 'active'
    $activeUnplacedRule.PSObject.Properties.Remove('retirementReason')
    $activeUnplacedRule.PSObject.Properties.Remove('lastPlacement')
    $activeUnplacedCatalogPath = Join-Path $tempRoot 'active-unplaced-catalog.json'
    Write-JsonFixture -Path $activeUnplacedCatalogPath -Value $activeUnplacedCatalog
    $activeUnplacedAssessmentSetPath = New-CatalogBoundAssessmentSet -AssessmentSet $assessmentSet -HostedCatalogPath $activeUnplacedCatalogPath -Name 'active-unplaced'
    $activeUnplacedRun = Invoke-DisplayBuilder -Draft $draft -Name 'active-unplaced' -AssessmentSetPath $activeUnplacedAssessmentSetPath -HostedCatalogPath $activeUnplacedCatalogPath
    Add-TestResult -Name 'active-unplaced-rejected' -Passed ($activeUnplacedRun.ExitCode -ne 0 -and $activeUnplacedRun.Output -like '*Active Hosted rule is not placed*') -Detail 'An active rule cannot disappear from generated surfaces.'

    $retiredPlacedCatalog = Copy-JsonObject -Value $retiredCatalog
    $retiredPlacedCatalog.surfaces[0].sections[0].ruleIds = @($retiredId) + @($retiredPlacedCatalog.surfaces[0].sections[0].ruleIds)
    $retiredPlacedCatalogPath = Join-Path $tempRoot 'retired-placed-catalog.json'
    Write-JsonFixture -Path $retiredPlacedCatalogPath -Value $retiredPlacedCatalog
    $retiredPlacedAssessmentSetPath = New-CatalogBoundAssessmentSet -AssessmentSet $assessmentSet -HostedCatalogPath $retiredPlacedCatalogPath -Name 'retired-placed'
    $retiredPlacedRun = Invoke-DisplayBuilder -Draft $draft -Name 'retired-placed' -AssessmentSetPath $retiredPlacedAssessmentSetPath -HostedCatalogPath $retiredPlacedCatalogPath
    Add-TestResult -Name 'retired-placed-rejected' -Passed ($retiredPlacedRun.ExitCode -ne 0 -and $retiredPlacedRun.Output -like '*surface references non-active rule ID*') -Detail 'A retired rule cannot remain in an active generated surface.'

    Write-TestProgress -Name 'validation-boundaries' -Detail 'Checking deterministic output, exhaustive coverage, ownership, and inventory binding'

    $secondRun = Invoke-DisplayBuilder -Draft $draft -Name 'canonical-two'
    Add-TestResult -Name 'deterministic-display' -Passed ($secondRun.ExitCode -eq 0 -and (Get-Sha256 -Path $firstRun.OutputPath) -ceq (Get-Sha256 -Path $secondRun.OutputPath)) -Detail 'Equivalent inputs produce byte-identical displays.'
    $missingCoverage = Copy-JsonObject -Value $draft
    $missingCoverage.assessmentCoverage = @($missingCoverage.assessmentCoverage | Select-Object -First 2)
    $missingCoverageRun = Invoke-DisplayBuilder -Draft $missingCoverage -Name 'missing-coverage'
    Add-TestResult -Name 'exhaustive-coverage-required' -Passed ($missingCoverageRun.ExitCode -ne 0 -and $missingCoverageRun.Output -like '*does not cover every assessment*') -Detail 'Reconciliation cannot omit an assessment.'
    $duplicateMembership = Copy-JsonObject -Value $draft
    $secondRecommendation = Copy-JsonObject -Value $duplicateMembership.recommendations[0]
    $secondRecommendation.draftKey = 'recommendation-3'
    $duplicateMembership.recommendations = @($duplicateMembership.recommendations[0], $duplicateMembership.recommendations[1], $secondRecommendation)
    $duplicateRun = Invoke-DisplayBuilder -Draft $duplicateMembership -Name 'duplicate-membership'
    Add-TestResult -Name 'duplicate-membership-rejected' -Passed ($duplicateRun.ExitCode -ne 0 -and $duplicateRun.Output -like '*more than one generated recommendation*') -Detail 'One assessment cannot belong to multiple recommendations.'

    $tamperedInventory = Get-Content -LiteralPath $inventoryPaths[1] -Raw | ConvertFrom-Json -DateKind String
    $tamperedInventory.collectedAt = '2026-09-16T13:00:00Z'
    $tamperedInventoryPath = Join-Path $tempRoot 'tampered-inventory.json'
    Write-JsonFixture -Path $tamperedInventoryPath -Value $tamperedInventory
    [string[]]$tamperedInventoryPaths = @($inventoryPaths[0], $tamperedInventoryPath, $inventoryPaths[2])
    $tamperedRun = Invoke-DisplayBuilder -Draft $draft -Name 'tampered-inventory' -InventoryPaths $tamperedInventoryPaths
    Add-TestResult -Name 'assessment-inventory-binding' -Passed ($tamperedRun.ExitCode -ne 0 -and $tamperedRun.Output -like '*does not match the assessment set*') -Detail 'Display inputs must be the exact assessed inventory bytes.'

    $unclassifiedInventory = Get-Content -LiteralPath $inventoryPaths[1] -Raw | ConvertFrom-Json -DateKind String
    $unclassifiedInventory.records[0].provenance = 'unclassified'
    $unclassifiedInventory.collection.inventorySha256 = Get-SourceEvidenceRecordsSha256 -Records @($unclassifiedInventory.records)
    $unclassifiedInventoryPath = Join-Path $tempRoot 'unclassified-inventory.json'
    Write-JsonFixture -Path $unclassifiedInventoryPath -Value $unclassifiedInventory
    $unclassifiedAssessmentSet = Copy-JsonObject -Value $assessmentSet
    $unclassifiedAssessmentSet.inventoryHashes.'interactive-toolkit' = Get-Sha256 -Path $unclassifiedInventoryPath
    $unclassifiedAssessmentSetPath = Join-Path $tempRoot 'unclassified-assessment-set.json'
    Write-JsonFixture -Path $unclassifiedAssessmentSetPath -Value $unclassifiedAssessmentSet
    [string[]]$unclassifiedInventoryPaths = @($inventoryPaths[0], $unclassifiedInventoryPath, $inventoryPaths[2])
    $unclassifiedRun = Invoke-DisplayBuilder -Draft $draft -Name 'unclassified' -AssessmentSetPath $unclassifiedAssessmentSetPath -InventoryPaths $unclassifiedInventoryPaths
    Add-TestResult -Name 'unclassified-provenance-rejected' -Passed ($unclassifiedRun.ExitCode -ne 0 -and $unclassifiedRun.Output -like '*contains unclassified source provenance*') -Detail 'The producer refuses approval metadata it cannot classify from trusted source evidence.'
}
catch {
    $issues.Add($_.Exception.Message)
}
finally {
    Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
}

$status = if ($issues.Count -eq 0) { 'passed' } else { 'failed' }
$summary = [ordered]@{ status = $status; testCount = $results.Count; issueCount = $issues.Count; tests = $results.ToArray(); issues = $issues.ToArray() }
if ($OutputFormat -eq 'Json') {
    $summary | ConvertTo-Json -Depth 8
}
else {
    Write-ValidationSectionHeader -Title 'Hosted assessment reconciliation test summary'
    Write-ValidationSummary -Fields ([ordered]@{ Status = $status.ToUpperInvariant(); Tests = $results.Count; Issues = $issues.Count })
    Write-ValidationSectionHeader -Title 'Assessment reconciliation tests'
    Write-ValidationTwoColumnTable -Rows @($results | ForEach-Object { [pscustomobject]@{ Status = $_.status; Test = $_.name } }) -FirstHeader 'Status' -FirstProperty 'Status' -SecondHeader 'Test' -SecondProperty 'Test' -UppercaseFirst
    if ($issues.Count -gt 0) {
        Write-ValidationSectionHeader -Title 'Failures'
        foreach ($issue in $issues) {
            Write-Output "  - $issue"
        }
    }
    Complete-ValidationTextOutput
}
if ($status -ne 'passed') {
    exit 1
}
