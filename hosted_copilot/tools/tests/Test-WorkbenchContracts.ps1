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
$reconciliationRoot = Join-Path $catalogRoot '../contracts/reconciliation'
$assessmentRoot = Join-Path $catalogRoot '../contracts/assessment'
$results = [Collections.Generic.List[object]]::new()
$issues = [Collections.Generic.List[string]]::new()

if ($OutputFormat -eq 'Text') {
    Write-ValidationSectionHeader -Title 'Hosted Workbench contracts'
}
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

function Write-TestProgress {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][string]$Detail
    )

    if ($OutputFormat -eq 'Text') {
        Write-Host (Format-ValidationStatusLine -Status 'running' -Name $Name -Detail $Detail)
    }
}

$capacityOutput = @(& pwsh -NoProfile -File (Join-Path $PSScriptRoot '../internal/workbench/Get-GuidanceCapacity.ps1') -OutputFormat Json)
if ($LASTEXITCODE -ne 0) { throw 'Cannot construct the policy-bound capacity fixture' }
$guidanceCapacityFixture = ($capacityOutput | Out-String) | ConvertFrom-Json -Depth 50
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
    relatedHostedCoverage = @()
    retireHostedRuleIds = @()
    guardedTokenDelta = 12
    provenance = @('local-safeguard')
    evidenceIds = @('implementation-contract', 'hosted-architecture')
    implementationModels = @('legacy', 'typed', 'framework')
    sourceRelationships = @([ordered]@{ sourceDefinitionId = 'maintainer-proposals'; sourceId = 'IMPL-TEST-901'; relationshipKind = 'included'; rationale = 'The assessment is included in this recommendation.' })
}
$source = [ordered]@{
    lane = 'maintainer'
    id = 'IMPL-TEST-901'
    title = 'Validate rule'
    location = 'hosted_copilot/authored-rules/proposals/implementation.rules.md'
    text = 'Validate the rule deterministically.'
    contentSha256 = $hash
    surface = 'implementation'
    provenance = 'local-safeguard'
    rationale = 'Protect deterministic behavior.'
    evidence = @()
    transition = 'added'
}
$catalogMapping = [ordered]@{ state = 'unmapped'; hostedRuleId = $null }
$display = [ordered]@{
    '$schema' = 'workbench-display-v4.schema.json'
    schemaVersion = 4
    kind = 'hosted-rule-workbench-display'
    generatedAt = $timestamp
    readOnly = $true
    sourceFiles = @([ordered]@{ sourceDefinitionId = 'maintainer-proposals'; sourceId = 'IMPL-TEST-901'; contentSha256 = $hash })
    reconciliation = [ordered]@{ status = 'ready' }
    candidates = @([ordered]@{
        source = $source
        assessment = $assessment
        reviewState = 'recommended'
        recommendation = $recommendation
        catalogMapping = $catalogMapping
        members = @([ordered]@{ source = $source; assessment = $assessment; meaningCoverageRationale = 'The recommendation preserves the fixture assessment meaning.'; catalogMapping = $catalogMapping })
    })
    catalog = [ordered]@{
        contentSha256 = $hash
        protectedRulesContentSha256 = $hash
        rules = @(
            [ordered]@{
                id = 'IMPL-EVID-001'
                origin = 'hosted-baseline-migration'
                status = 'active'
                text = 'Verify Azure behavior from authoritative evidence.'
                provenance = @('inferred-maintainer-convention')
                evidenceIds = @('implementation-contract')
                implementationModels = @('legacy', 'typed', 'framework')
                canonicalCandidate = [ordered]@{ sourceDefinitionId = 'interactive-toolkit'; sourceId = 'IMPL-EVID-001' }
                placements = @([ordered]@{ surfaceId = 'implementation'; sectionHeading = 'Evidence And Resource Type' })
            },
            [ordered]@{
                id = 'IMPL-EVID-002'
                origin = 'hosted-baseline-migration'
                status = 'retired'
                text = 'Retain retired rule history without rendering it.'
                provenance = @('inferred-maintainer-convention')
                evidenceIds = @('implementation-contract')
                implementationModels = @('legacy', 'typed', 'framework')
                canonicalCandidate = [ordered]@{ sourceDefinitionId = 'interactive-toolkit'; sourceId = 'IMPL-EVID-002' }
                placements = @()
                retirementReason = 'Superseded by a more precise rule.'
                lastPlacement = [ordered]@{ surfaceId = 'implementation'; sectionHeading = 'Evidence And Resource Type' }
            }
        )
        protectedRules = @([ordered]@{
            id = 'IMPL-WF-000'
            status = 'protected'
            surfaceId = 'implementation'
            title = 'Classify AzureRM implementation resource types'
            text = 'Classify implementation code before applying resource-type-specific rules.'
            provenance = 'confirmed-maintainer-convention'
            protectionReason = 'Required first-party instruction infrastructure.'
            impact = 100
            guardedTokens = 24
            sourcePath = 'hosted_copilot/authored-rules/protected/implementation.rules.md'
            contentSha256 = $hash
        })
        protectedRuleFiles = @([ordered]@{
            path = 'hosted_copilot/authored-rules/protected/implementation.rules.md'
            surfaceId = 'implementation'
            content = "# Protected Implementation Review Rules`n`n### IMPL-WF-000: Classify AzureRM implementation resource types`n`n- Rule: Classify implementation code before applying resource-type-specific rules."
            contentSha256 = $hash
            ruleIds = @('IMPL-WF-000')
        })
    }
    guidanceCapacity = $guidanceCapacityFixture
}
Write-TestProgress -Name 'display-contract' -Detail 'Validating display candidates, catalog lifecycle, capacity, and authority boundaries'
$displaySchemaPath = Join-Path $reconciliationRoot '../workbench/workbench-display-v4.schema.json'
Add-TestResult -Name 'display-valid' -Passed (Test-JsonInstance -Value $display -SchemaPath $displaySchemaPath) -Detail 'The v4 display contains only display-ready candidates, catalog projection, capacity, and one input fingerprint.'
$activeRuleWithoutPlacement = Copy-JsonValue -Value $display
$activeRuleWithoutPlacement.catalog.rules[0].placements = @()
Add-TestResult -Name 'active-rule-placement-required' -Passed (-not (Test-JsonInstance -Value $activeRuleWithoutPlacement -SchemaPath $displaySchemaPath)) -Detail 'Every active catalog rule requires one or more display placements.'
$retiredRuleWithPlacement = Copy-JsonValue -Value $display
$retiredRuleWithPlacement.catalog.rules[1].placements = @([ordered]@{ surfaceId = 'implementation'; sectionHeading = 'Evidence And Resource Type' })
Add-TestResult -Name 'retired-rule-placement-rejected' -Passed (-not (Test-JsonInstance -Value $retiredRuleWithPlacement -SchemaPath $displaySchemaPath)) -Detail 'Retired catalog rules remain visible as history but cannot appear in an active surface.'
$retiredRuleWithoutHistory = Copy-JsonValue -Value $display
$retiredRuleWithoutHistory.catalog.rules[1].PSObject.Properties.Remove('lastPlacement')
Add-TestResult -Name 'retired-rule-history-required' -Passed (-not (Test-JsonInstance -Value $retiredRuleWithoutHistory -SchemaPath $displaySchemaPath)) -Detail 'A retired rule retains its last rendered location for Workbench history and Restore.'
$activeRuleWithHistory = Copy-JsonValue -Value $display
$activeRuleWithHistory.catalog.rules[0] | Add-Member -NotePropertyName lastPlacement -NotePropertyValue ([ordered]@{ surfaceId = 'implementation'; sectionHeading = 'Evidence And Resource Type' })
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

Write-TestProgress -Name 'draft-contract' -Detail 'Validating local draft decisions and approval boundaries'
$candidateKey = 'maintainer:IMPL-TEST-901:validate-rule'
$draft = [ordered]@{
    '$schema' = 'workbench-draft-v4.schema.json'
    schemaVersion = 4
    kind = 'hosted-rule-workbench-draft'
    sourceFiles = @([ordered]@{ sourceDefinitionId = 'maintainer-proposals'; sourceId = 'IMPL-TEST-901'; contentSha256 = $hash })
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
            retireHostedRuleIds = @()
            implementationModels = @('legacy', 'typed')
            sourceContentSha256 = $hash
            updatedAt = $timestamp
        }
    }
    applicabilityOverrides = [ordered]@{}
    bulkOperations = @()
}
$draftSchemaPath = Join-Path $reconciliationRoot '../workbench/workbench-draft-v4.schema.json'
Add-TestResult -Name 'draft-valid' -Passed (Test-JsonInstance -Value $draft -SchemaPath $draftSchemaPath) -Detail 'The local draft preserves incomplete decisions without becoming approval authority.'
$draftWithApproval = Copy-JsonValue -Value $draft
$draftWithApproval | Add-Member -NotePropertyName approvedAt -NotePropertyValue $timestamp
Add-TestResult -Name 'draft-approval-rejected' -Passed (-not (Test-JsonInstance -Value $draftWithApproval -SchemaPath $draftSchemaPath)) -Detail 'The local draft cannot carry approval.'
$draftWithBundleHash = Copy-JsonValue -Value $draft
$draftWithBundleHash | Add-Member -NotePropertyName workbenchBundleSha256 -NotePropertyValue $hash
Add-TestResult -Name 'draft-bundle-hash-rejected' -Passed (-not (Test-JsonInstance -Value $draftWithBundleHash -SchemaPath $draftSchemaPath)) -Detail 'The local draft uses one input fingerprint instead of a bundle transaction identity.'

Write-TestProgress -Name 'approved-rules-contract' -Detail 'Validating approved mutations, placements, relationships, and rejected non-mutations'
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
        canonicalCandidate = [ordered]@{
            sourceDefinitionId = 'maintainer-proposals'
            sourceId = 'IMPL-TEST-901'
            assessmentId = 'hosted-check'
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
$approvedSchemaPath = Join-Path $reconciliationRoot '../workbench/approved-rules-v4.schema.json'
Add-TestResult -Name 'approved-rules-valid' -Passed (Test-JsonInstance -Value $approved -SchemaPath $approvedSchemaPath) -Detail 'The approved-rules file contains one catalog precondition, attribution, complete mutations, placements, and relationships.'
$approvedWithNoChange = Copy-JsonValue -Value $approved
$approvedWithNoChange.mutations[0].action = 'no-change'
Add-TestResult -Name 'approved-rules-nonmutation-rejected' -Passed (-not (Test-JsonInstance -Value $approvedWithNoChange -SchemaPath $approvedSchemaPath)) -Detail 'No Change, Defer, and Exclude cannot enter approved catalog mutations.'
$approvedWithPayload = Copy-JsonValue -Value $approved
$approvedWithPayload | Add-Member -NotePropertyName previewPayload -NotePropertyValue '{}'
Add-TestResult -Name 'approved-rules-envelope-rejected' -Passed (-not (Test-JsonInstance -Value $approvedWithPayload -SchemaPath $approvedSchemaPath)) -Detail 'The approved-rules file is the payload and rejects a duplicate embedded approval envelope.'

Write-TestProgress -Name 'behavior-boundaries' -Detail 'Checking contract dependencies, Remote Rules ownership, and v4 naming'
$contractLibraryRoot = Join-Path $repositoryRoot 'hosted_copilot/contracts'
$schemaSources = @(& git -C $repositoryRoot ls-files --cached --others --exclude-standard -- 'hosted_copilot/**/*.schema.json')
if ($LASTEXITCODE -ne 0) { throw 'Cannot enumerate Hosted contract schema sources' }
$schemaPaths = @($schemaSources | Sort-Object -Unique | ForEach-Object {
    $path = Join-Path $repositoryRoot $_
    if (Test-Path -LiteralPath $path -PathType Leaf) { Get-Item -LiteralPath $path }
})
$misplacedSchemas = @($schemaPaths | Where-Object { [IO.Path]::GetRelativePath($contractLibraryRoot, $_.FullName).Replace('\', '/').StartsWith('../', [StringComparison]::Ordinal) })
Add-TestResult -Name 'central-schema-library' -Passed ($schemaPaths.Count -gt 0 -and $misplacedSchemas.Count -eq 0) -Detail 'Every Hosted JSON validation schema has one authoritative source under contracts.'
$descriptorIssues = [Collections.Generic.List[string]]::new()
foreach ($descriptorPath in @(Get-ChildItem $contractLibraryRoot -Recurse -File -Filter '*.json' | Where-Object Name -NotLike '*.schema.json')) {
    $descriptorJson = Get-Content -LiteralPath $descriptorPath.FullName -Raw
    $descriptor = $descriptorJson | ConvertFrom-Json -DateKind String
    $descriptorSchemaPath = Join-Path $descriptorPath.DirectoryName ([string]$descriptor.'$schema')
    if (-not (Test-JsonInstance -Value $descriptor -SchemaPath $descriptorSchemaPath)) {
        $descriptorIssues.Add($descriptorPath.Name)
    }
}
Add-TestResult -Name 'central-descriptor-schemas' -Passed ($descriptorIssues.Count -eq 0) -Detail 'All behavior and exchange descriptors validate against their colocated contract schemas.'
$sourceAssessmentContract = Get-Content -LiteralPath (Join-Path $assessmentRoot 'source-assessment-v4.json') -Raw | ConvertFrom-Json -DateKind String
$reconciliationContract = Get-Content -LiteralPath (Join-Path $reconciliationRoot 'assessment-reconciliation-v4.json') -Raw | ConvertFrom-Json -DateKind String
$forbiddenBehaviorPattern = '(?:source-generations/|publication-request|promotion-plan|approval-handoff|catalog-apply-receipt)'
$sourceAssessmentClean = @($sourceAssessmentContract.behaviorFiles | Where-Object { $_ -match $forbiddenBehaviorPattern }).Count -eq 0
$reconciliationClean = @($reconciliationContract.behaviorFiles | Where-Object { $_ -match $forbiddenBehaviorPattern }).Count -eq 0
Add-TestResult -Name 'assessment-contract-dependency-boundary' -Passed $sourceAssessmentClean -Detail 'The v4 assessment behavior identity excludes generation and publication machinery.'
Add-TestResult -Name 'reconciliation-contract-dependency-boundary' -Passed $reconciliationClean -Detail 'The v4 reconciliation behavior identity excludes Promotion Plan and transaction machinery.'

$behaviorManifestIssues = [Collections.Generic.List[string]]::new()
$behaviorManifestCount = 0
$presentationManifestCount = 0
foreach ($manifestPath in @(Get-ChildItem (Join-Path $repositoryRoot 'hosted_copilot') -Recurse -File -Filter '*.json')) {
    try {
        $manifest = Get-Content -LiteralPath $manifestPath.FullName -Raw | ConvertFrom-Json -DateKind String
    }
    catch {
        continue
    }
    $behaviorFilesProperty = $manifest.PSObject.Properties['behaviorFiles']
    if ($null -eq $behaviorFilesProperty) {
        continue
    }
    $behaviorManifestCount++
    $manifestRelativePath = $manifestPath.FullName.Substring($repositoryRoot.Length + 1).Replace('\', '/')
    if ($manifestRelativePath -notlike 'hosted_copilot/contracts/*') {
        $behaviorManifestIssues.Add("Behavior descriptor is outside the contract library: $manifestRelativePath")
    }
    foreach ($behaviorFile in @($behaviorFilesProperty.Value)) {
        $relativePath = [string]$behaviorFile
        if ($relativePath -notlike 'hosted_copilot/*') {
            $behaviorManifestIssues.Add("$manifestRelativePath references behavior outside Hosted ownership: $relativePath")
            continue
        }
        if ($relativePath -match '(?i)(^|[-_/])v1([-_/.]|$)|obsolete-v3|legacy-v3') {
            $behaviorManifestIssues.Add("$manifestRelativePath references legacy behavior: $relativePath")
            continue
        }
        $resolvedBehaviorPath = Join-Path $repositoryRoot $relativePath
        if (-not (Test-Path -LiteralPath $resolvedBehaviorPath -PathType Leaf)) {
            $behaviorManifestIssues.Add("$manifestRelativePath references missing behavior: $relativePath")
            continue
        }
        if ((Get-Item -LiteralPath $resolvedBehaviorPath).Length -eq 0) {
            $behaviorManifestIssues.Add("$manifestRelativePath references empty behavior: $relativePath")
        }
    }
    $presentationFilesProperty = $manifest.PSObject.Properties['presentationFiles']
    if ($null -eq $presentationFilesProperty) {
        continue
    }
    $presentationManifestCount++
    foreach ($presentationFile in @($presentationFilesProperty.Value)) {
        $relativePath = [string]$presentationFile
        if ($relativePath -in @($behaviorFilesProperty.Value)) {
            $behaviorManifestIssues.Add("$manifestRelativePath treats presentation as semantic behavior: $relativePath")
            continue
        }
        if ($relativePath -notlike 'hosted_copilot/*') {
            $behaviorManifestIssues.Add("$manifestRelativePath references presentation outside Hosted ownership: $relativePath")
            continue
        }
        $resolvedPresentationPath = Join-Path $repositoryRoot $relativePath
        if (-not (Test-Path -LiteralPath $resolvedPresentationPath -PathType Leaf)) {
            $behaviorManifestIssues.Add("$manifestRelativePath references missing presentation: $relativePath")
            continue
        }
        if ((Get-Item -LiteralPath $resolvedPresentationPath).Length -eq 0) {
            $behaviorManifestIssues.Add("$manifestRelativePath references empty presentation: $relativePath")
        }
    }
}
$behaviorManifestsClean = $behaviorManifestCount -gt 0 -and $behaviorManifestIssues.Count -eq 0
Add-TestResult -Name 'all-behavior-manifests-active-only' -Passed $behaviorManifestsClean -Detail $(if ($behaviorManifestsClean) { "All $behaviorManifestCount behavior manifests reference only existing active Hosted files without v1 reconciliation symbols." } else { $behaviorManifestIssues -join ' | ' })
Add-TestResult -Name 'presentation-authority-boundaries' -Passed ($presentationManifestCount -eq 3 -and $behaviorManifestIssues.Count -eq 0) -Detail 'Source assessment and both reconciliation contracts snapshot existing Hosted presentation files without treating them as semantic cache authority.'

$remoteParserContract = Get-Content -LiteralPath (Join-Path $catalogRoot '../contracts/parsers/maintainer-proposals-v4.json') -Raw | ConvertFrom-Json -DateKind String
$remoteParserOwnsExchange = [string]$remoteParserContract.parserId -ceq 'maintainer-proposals-v4' -and 'hosted_copilot/tools/modules/source-parsers/MaintainerProposalsV4.psm1' -in @($remoteParserContract.behaviorFiles)
Add-TestResult -Name 'remote-rules-parser-owned' -Passed $remoteParserOwnsExchange -Detail 'Remote Rules remain ordinary Maintainer Proposal files owned by the lane parser rather than an endpoint contract.'

$requiredV4Paths = @(
    $approvedSchemaPath,
    (Join-Path $reconciliationRoot 'assessment-reconciliation-v4.json'),
    $displaySchemaPath,
    $draftSchemaPath
)
$missingV4Names = @($requiredV4Paths | Where-Object { -not (Test-Path -LiteralPath $_ -PathType Leaf) })
$missingAssessmentV4Names = @('source-assessment-v4.json' | Where-Object { -not (Test-Path -LiteralPath (Join-Path $assessmentRoot $_) -PathType Leaf) })
Add-TestResult -Name 'v4-contract-naming' -Passed ($missingV4Names.Count -eq 0 -and $missingAssessmentV4Names.Count -eq 0) -Detail 'Every v4 Workbench authority uses an explicit v4 filename.'

Write-TestProgress -Name 'startup-source-policy' -Detail 'Executing production startup dispatch and upstream-skip branches with offline collection boundaries'
$launcherPath = Join-Path $PSScriptRoot '../Start-RuleWorkbench.ps1'
$launcherTokens = $null
$launcherErrors = $null
$launcherAst = [Management.Automation.Language.Parser]::ParseFile($launcherPath, [ref]$launcherTokens, [ref]$launcherErrors)
$startupFunctionNames = @('Read-StagedWorkbenchDisplay', 'Update-StagedDisplay', 'Invoke-WorkbenchRebuild')
$startupDefinitions = @($launcherAst.FindAll({
    param($node)
    $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -in $startupFunctionNames
}, $true))
$startupDefinitionsValid = @($launcherErrors).Count -eq 0 -and $startupDefinitions.Count -eq $startupFunctionNames.Count
Add-TestResult -Name 'startup-source-policy-production-functions' -Passed $startupDefinitionsValid -Detail 'Startup reuse and explicit rebuild have distinct executable production owners.'
if ($startupDefinitionsValid) {
    $startupFixtureRoot = Join-Path ([IO.Path]::GetTempPath()) ('hosted-startup-policy-' + [guid]::NewGuid().ToString('N'))
    $null = New-Item -ItemType Directory -Path $startupFixtureRoot
    try {
        $startupResults = & {
            param($Definitions, $FixtureDisplay, $RepositoryRoot, $FixtureRoot, $DisplaySchema)
            foreach ($definition in $Definitions) { . ([scriptblock]::Create($definition.Extent.Text)) }
            $collectionIds = [Collections.Generic.List[string]]::new()
            $completedStages = [Collections.Generic.List[string]]::new()
            function Complete-WorkbenchStage {
                param([string]$Name)
                $completedStages.Add($Name)
            }
            $Rebuild = $false
            $Force = $false
            $OutputFormat = 'Json'
            $repositoryRoot = $RepositoryRoot
            $catalogRoot = Join-Path $RepositoryRoot 'hosted_copilot/copilot-rule-catalog'
            $sourceDefinitionSetPath = Join-Path $catalogRoot 'source-definitions/source-definition-set.json'
            $expectedSourceIds = @((Get-Content -LiteralPath $sourceDefinitionSetPath -Raw | ConvertFrom-Json).sourceDefinitionIds)
            $resolvedSiteDirectory = $FixtureRoot
            $stagedDisplayPath = Join-Path $FixtureRoot 'workbench-display.json'
            $stagedRuleIssuesPath = Join-Path $FixtureRoot 'workbench-rule-issues.json'
            $displaySchemaPath = $DisplaySchema
            $ruleIssuesSchemaPath = Join-Path $RepositoryRoot 'hosted_copilot/contracts/workbench/workbench-rule-issues-v4.schema.json'
            $InventoryDirectory = Join-Path $FixtureRoot 'prior-inventories'
            $resolvedAssessmentCacheDirectory = Join-Path $FixtureRoot 'assessment-cache'
            $resolvedAssessmentResumeDirectory = $null
            $EvaluatorCommand = 'offline-test-boundary'
            $Model = 'fixture-model'
            $AssessmentReasoningEffort = 'low'
            $MaxRetries = 0
            $MaxParallelBatches = 1
            $inventoryCollectorPath = {
                param($RepositoryRoot, $SourceDefinitionPath, $OutputPath, $OutputFormat)
                $collectionIds.Add([IO.Path]::GetFileNameWithoutExtension($SourceDefinitionPath))
                '{"status":"passed"}'
            }
            $sourceAssessmentPath = { throw 'OFFLINE-ASSESSMENT-BOUNDARY' }
            $fixtureRuleIssues = [ordered]@{
                '$schema' = 'workbench-rule-issues-v4.schema.json'
                schemaVersion = 4
                kind = 'hosted-rule-workbench-rule-issues'
                generatedAt = $FixtureDisplay.generatedAt
                readOnly = $true
                sourceFiles = $FixtureDisplay.sourceFiles
                issues = @()
            }
            $displayText = $FixtureDisplay | ConvertTo-Json -Depth 100
            [IO.File]::WriteAllText($stagedDisplayPath, $displayText, [Text.UTF8Encoding]::new($false))
            [IO.File]::WriteAllText($stagedRuleIssuesPath, ($fixtureRuleIssues | ConvertTo-Json -Depth 100), [Text.UTF8Encoding]::new($false))
            $loaded = Update-StagedDisplay
            $ordinaryReused = $loaded.kind -ceq 'hosted-rule-workbench-display' -and $collectionIds.Count -eq 0 -and
                'EXISTING DISPLAY VALIDATION' -in $completedStages -and [IO.File]::ReadAllText($stagedDisplayPath) -ceq $displayText
            $directRebuildBlocked = $false
            try { Invoke-WorkbenchRebuild | Out-Null }
            catch { $directRebuildBlocked = $_.Exception.Message -match 'explicit -Rebuild' -and $collectionIds.Count -eq 0 }
            [IO.File]::Delete($stagedDisplayPath)
            $missingDisplayBlocked = $false
            try { Update-StagedDisplay | Out-Null }
            catch { $missingDisplayBlocked = $_.Exception.Message -match 'complete staged Workbench display' -and $collectionIds.Count -eq 0 }
            [IO.File]::WriteAllText($stagedDisplayPath, $displayText, [Text.UTF8Encoding]::new($false))
            $mismatchedIssues = ($fixtureRuleIssues | ConvertTo-Json -Depth 100) | ConvertFrom-Json -DateKind String
            $mismatchedIssues.sourceFiles[0].contentSha256 = 'b' * 64
            [IO.File]::WriteAllText($stagedRuleIssuesPath, ($mismatchedIssues | ConvertTo-Json -Depth 100), [Text.UTF8Encoding]::new($false))
            $mismatchedDisplayBlocked = $false
            try { Update-StagedDisplay | Out-Null }
            catch { $mismatchedDisplayBlocked = $_.Exception.Message -match 'source files do not match' -and $collectionIds.Count -eq 0 }
            $Rebuild = $true
            $explicitRebuildReachedAssessment = $false
            try { Update-StagedDisplay | Out-Null }
            catch { $explicitRebuildReachedAssessment = $_.Exception.Message -match 'OFFLINE-ASSESSMENT-BOUNDARY' }
            $explicitSourceSelection = $explicitRebuildReachedAssessment -and 'contributor-guidance' -in $expectedSourceIds -and
                $collectionIds.Count -eq $expectedSourceIds.Count -and @((Compare-Object @($collectionIds.ToArray()) $expectedSourceIds -SyncWindow 0)).Count -eq 0
            [pscustomobject]@{
                ordinaryReused = $ordinaryReused
                directRebuildBlocked = $directRebuildBlocked
                missingDisplayBlocked = $missingDisplayBlocked
                mismatchedDisplayBlocked = $mismatchedDisplayBlocked
                explicitSourceSelection = $explicitSourceSelection
            }
        } $startupDefinitions $display $repositoryRoot $startupFixtureRoot $displaySchemaPath
        Add-TestResult -Name 'ordinary-startup-no-source-collection' -Passed $startupResults.ordinaryReused -Detail 'Ordinary production startup reuses validated staged facts without invoking any source collector.'
        Add-TestResult -Name 'direct-rebuild-requires-explicit-request' -Passed $startupResults.directRebuildBlocked -Detail 'The production rebuild owner refuses collection and assessment without an explicit -Rebuild request.'
        Add-TestResult -Name 'missing-display-no-implicit-rebuild' -Passed $startupResults.missingDisplayBlocked -Detail 'Missing staged data fails ordinary startup instead of silently collecting sources or invoking AI.'
        Add-TestResult -Name 'mismatched-display-no-implicit-rebuild' -Passed $startupResults.mismatchedDisplayBlocked -Detail 'Mismatched staged source identities fail without falling back to upstream refresh.'
        Add-TestResult -Name 'explicit-rebuild-keeps-contributor-selection' -Passed $startupResults.explicitSourceSelection -Detail 'An explicit production rebuild reaches every configured collection, including Contributor Guidance, before the offline assessment boundary.'
    }
    catch {
        Add-TestResult -Name 'startup-source-policy-execution' -Passed $false -Detail $_.Exception.Message
    }
    finally {
        Remove-Item -LiteralPath $startupFixtureRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}

$validatorTokens = $null
$validatorErrors = $null
$validatorAst = [Management.Automation.Language.Parser]::ParseFile((Join-Path $PSScriptRoot '../Test-HostedRules.ps1'), [ref]$validatorTokens, [ref]$validatorErrors)
$upstreamSkipBranches = @($validatorAst.FindAll({
    param($node)
    $node -is [Management.Automation.Language.IfStatementAst] -and $node.Clauses[0].Item1.Extent.Text.Trim() -ceq '$SkipUpstreamDrift'
}, $true))
$skipOptionPresent = @($validatorAst.ParamBlock.Parameters | Where-Object { $_.Name.VariablePath.UserPath -ceq 'SkipUpstreamDrift' }).Count -eq 1
if (@($validatorErrors).Count -eq 0 -and $skipOptionPresent -and $upstreamSkipBranches.Count -eq 1) {
    $skipResult = & {
        param($BranchText)
        $SkipUpstreamDrift = $true
        $skippedChecks = [Collections.Generic.List[string]]::new()
        function Add-SkippedCheck {
            param([string]$Name, [string]$Detail)
            $skippedChecks.Add($Name)
        }
        function Start-ValidationCheck {
            param([string]$Name)
            throw 'OFFLINE-UPSTREAM-AUDIT-BOUNDARY'
        }
        . ([scriptblock]::Create($BranchText))
        $skipRecorded = $skippedChecks.Count -eq 1 -and $skippedChecks[0] -ceq 'upstream-sources'
        $SkipUpstreamDrift = $false
        $auditReached = $false
        try { . ([scriptblock]::Create($BranchText)) }
        catch { $auditReached = $_.Exception.Message -match 'OFFLINE-UPSTREAM-AUDIT-BOUNDARY' }
        $skipRecorded -and $auditReached
    } $upstreamSkipBranches[0].Extent.Text
    Add-TestResult -Name 'validator-upstream-skip-contract' -Passed $skipResult -Detail 'The production -SkipUpstreamDrift branch records upstream-sources as skipped; without the switch the live-audit entry point remains reachable.'
}
else {
    Add-TestResult -Name 'validator-upstream-skip-contract' -Passed $false -Detail 'The explicit upstream skip parameter or its production branch is missing or invalid.'
}

Write-TestProgress -Name 'native-evaluator-boundaries' -Detail 'Checking every registered native prompt rejects injected instructions and uses an existing result schema'
$nativeStageRegistry = Get-Content -LiteralPath (Join-Path $PSScriptRoot '../../contracts/workbench/native-evaluation-stages-v4.json') -Raw | ConvertFrom-Json
$nativeBoundaryIssues = [Collections.Generic.List[string]]::new()
foreach ($stage in $nativeStageRegistry.stages) {
    $promptText = Get-Content -LiteralPath (Join-Path $PSScriptRoot "../../$($stage.prompt)") -Raw
    if ($promptText -notmatch '(?m)^## Boundaries\s*$' -or $promptText -notmatch 'untrusted quoted data' -or
        $promptText -notmatch 'prompt injection' -or $promptText -notmatch 'tool requests' -or $promptText -notmatch 'role changes' -or
        $promptText -notmatch 'output-format changes' -or $promptText -notmatch 'policy claims' -or
        -not (Test-Path -LiteralPath (Join-Path $PSScriptRoot "../../$($stage.resultSchema)") -PathType Leaf)) {
        $nativeBoundaryIssues.Add($stage.code)
    }
}
Add-TestResult -Name 'native-prompt-injection-boundaries' -Passed ($nativeStageRegistry.schemaVersion -eq 4 -and @($nativeStageRegistry.stages).Count -gt 0 -and $nativeBoundaryIssues.Count -eq 0) -Detail 'Every registered native evaluator treats supplied source/assessment/catalog data as untrusted and rejects injected tool, role, format and policy instructions.'

Write-TestProgress -Name 'native-evaluator-launch' -Detail 'Executing the actual native launch expression without starting the CLI'
$nativeEvaluatorTokens = $null
$nativeEvaluatorErrors = $null
$nativeEvaluatorAst = [Management.Automation.Language.Parser]::ParseFile((Join-Path $PSScriptRoot '../internal/workbench/Invoke-NativeEvaluation.ps1'), [ref]$nativeEvaluatorTokens, [ref]$nativeEvaluatorErrors)
$nativeLaunchStatements = @($nativeEvaluatorAst.FindAll({ param($node)
    $node -is [Management.Automation.Language.AssignmentStatementAst] -and $node.Left.Extent.Text -ceq '$process.StartInfo'
}, $true))
if (@($nativeEvaluatorErrors).Count -ne 0 -or $nativeLaunchStatements.Count -ne 1) { throw 'Native evaluator launch expression must be uniquely parseable' }
$nativeLaunchArguments = @(& {
    param([string]$Expression)
    $launch = [pscustomobject]@{ commandPath = 'fixture-copilot' }
    $workingDirectory = [IO.Path]::GetTempPath()
    $Model = 'fixture-native-model'
    $ReasoningEffort = 'high'
    function New-HostedCliStartInfo {
        param([object]$Launch, [string]$WorkingDirectory, [string[]]$Arguments)
        [pscustomobject]@{ arguments = $Arguments }
    }
    $captured = & ([scriptblock]::Create($Expression))
    $captured.arguments
} $nativeLaunchStatements[0].Right.Extent.Text)
$nativeToolIndex = [Array]::IndexOf($nativeLaunchArguments, '--available-tools')
$nativeEffortIndex = [Array]::IndexOf($nativeLaunchArguments, '--reasoning-effort')
Add-TestResult -Name 'native-evaluator-supported-tool-free-cli-arguments' -Passed ($nativeToolIndex -ge 0 -and
    $nativeLaunchArguments[$nativeToolIndex + 1] -ceq '--output-format' -and $nativeEffortIndex -ge 0 -and
    $nativeLaunchArguments[$nativeEffortIndex + 1] -ceq 'high' -and '--effort' -cnotin $nativeLaunchArguments -and
    '--deny-tool' -cnotin $nativeLaunchArguments -and '--no-custom-instructions' -cin $nativeLaunchArguments -and
    '--disable-builtin-mcps' -cin $nativeLaunchArguments -and '--no-auto-update' -cin $nativeLaunchArguments) -Detail 'Native inference uses the supported reasoning-effort flag and an empty tool list, matching the working worker without an invalid view/wildcard-deny combination.'

Write-TestProgress -Name 'native-analysis-availability' -Detail 'Executing the native command preflight with offline CLI and analysis boundaries'
Import-Module (Join-Path $PSScriptRoot '../modules/shared/HostedToolkit.Helpers.psm1') -Force
Write-TestProgress -Name 'native-estimate-parity' -Detail 'Measuring the actual native prompt assembly and comparing numeric estimates with the legacy throughput algorithm'
$nativePromptStatements = @($nativeEvaluatorAst.FindAll({ param($node)
    $node -is [Management.Automation.Language.AssignmentStatementAst] -and $node.Left.Extent.Text -ceq '$inlinePrompt'
}, $true))
if ($nativePromptStatements.Count -ne 1) { throw 'Native evaluator prompt assembly must be uniquely parseable' }
$nativePayloadSamples = [Collections.Generic.List[object]]::new()
$nativeEstimateWorkloads = @(
    @{ batchCount = 0; maxWorkers = 3 }
    @{ batchCount = 1; maxWorkers = 3 }
    @{ batchCount = 2; maxWorkers = 3 }
    @{ batchCount = 7; maxWorkers = 1 }
    @{ batchCount = 31; maxWorkers = 4 }
)
foreach ($stage in $nativeStageRegistry.stages) {
    $promptText = Get-Content -LiteralPath (Join-Path $PSScriptRoot "../../$($stage.prompt)") -Raw
    $schemaText = Get-Content -LiteralPath (Join-Path $PSScriptRoot "../../$($stage.resultSchema)") -Raw
    $inputText = @{ stage = $stage.code; content = ('Synthetic ' + [char]0xE9 + [char]::ConvertFromUtf32(0x1F600)) } | ConvertTo-Json -Compress
    $assembled = & {
        param([string]$Expression, [string]$promptText, [string]$schemaText, [string]$inputText)
        & ([scriptblock]::Create($Expression))
    } $nativePromptStatements[0].Right.Extent.Text $promptText $schemaText $inputText
    $expectedBytes = [Text.Encoding]::UTF8.GetByteCount($assembled)
    foreach ($workload in $nativeEstimateWorkloads) {
        $pendingBytes = $expectedBytes * $workload.batchCount
        $workerCount = [Math]::Min($workload.maxWorkers, $workload.batchCount)
        $expectedEstimate = Get-EstimatedRemainingMilliseconds -CompletedPayloadBytes 0 -CompletedElapsedMilliseconds 0 -RemainingPayloadBytes $pendingBytes -MaxParallelBatches $workerCount -BootstrapBytesPerSecondPerWorker 200
        $nativePayloadSamples.Add(@{ prompt = $promptText; schema = $schemaText; inputText = $inputText; expectedBytes = $expectedBytes;
            completedBytes = 0; workerMilliseconds = 0; remainingBytes = $pendingBytes; workers = $workerCount; expectedEstimate = $expectedEstimate })
    }
}
$nativeThroughputSamples = @(
    @{ completedBytes = 1000; workerMilliseconds = 1000; remainingBytes = 9000; workers = 3 }
    @{ completedBytes = 1000; workerMilliseconds = 1000; remainingBytes = 9000; workers = 1 }
    @{ completedBytes = 1000; workerMilliseconds = 0; remainingBytes = 9000; workers = 3 }
    @{ completedBytes = 1000; workerMilliseconds = 1000; remainingBytes = 0; workers = 3 }
)
foreach ($sample in $nativeThroughputSamples) {
    $sample.expectedEstimate = Get-EstimatedRemainingMilliseconds -CompletedPayloadBytes $sample.completedBytes -CompletedElapsedMilliseconds $sample.workerMilliseconds -RemainingPayloadBytes $sample.remainingBytes -MaxParallelBatches $sample.workers -BootstrapBytesPerSecondPerWorker 200
    $nativePayloadSamples.Add($sample)
}
$nativePayloadChecks = $nativePayloadSamples.ToArray() | ConvertTo-Json -Depth 10 -Compress | & node --input-type=module -e @'
import {readFileSync} from 'node:fs';
import {measureAssessmentInputBytes,estimateAssessmentMilliseconds} from './hosted_copilot/tools/modules/workbench/WorkbenchAssessmentExecution.mjs';
const samples=JSON.parse(readFileSync(0,'utf8'));
const results=samples.map(sample=>({
  payloadMatches:sample.inputText===undefined?true:measureAssessmentInputBytes(sample.inputText,{prompt:sample.prompt,schema:sample.schema})===sample.expectedBytes,
  estimateMatches:estimateAssessmentMilliseconds(sample.completedBytes,sample.workerMilliseconds,sample.remainingBytes,sample.workers)===sample.expectedEstimate
}));
console.log(JSON.stringify({passed:results.every(result=>result.payloadMatches&&result.estimateMatches),cases:results.length}));
'@
$nativePayloadExitCode = $LASTEXITCODE
$nativePayloadResult = $nativePayloadChecks | ConvertFrom-Json
Add-TestResult -Name 'native-estimate-matches-actual-input-and-legacy-throughput' -Passed ($nativePayloadExitCode -eq 0 -and $nativePayloadResult.passed -and
    $nativePayloadResult.cases -eq (@($nativeStageRegistry.stages).Count * $nativeEstimateWorkloads.Count + $nativeThroughputSamples.Count)) -Detail 'Every registered native stage measures the exact UTF-8 prompt assembly; zero, single, partially occupied, and larger workloads plus learned estimates match the shared throughput calculator.'
$nativeAnalysisPath = Join-Path $PSScriptRoot '../internal/workbench/Invoke-WorkbenchAnalysis.ps1'
$nativeTokens = $null
$nativeParseErrors = $null
$nativeAst = [Management.Automation.Language.Parser]::ParseFile($nativeAnalysisPath, [ref]$nativeTokens, [ref]$nativeParseErrors)
if (@($nativeParseErrors).Count -ne 0) { throw 'Native analysis command cannot be parsed for availability validation' }
$nativeStatements = @($nativeAst.EndBlock.Statements)
$nativeStart = @($nativeStatements | Where-Object { $_.Extent.Text -match '^\$resolvedDatabasePath\s*=' })
if ($nativeStart.Count -ne 1) { throw 'Native analysis database resolution boundary is not unique' }
$nativeBody = (@($nativeStatements | Where-Object { $_.Extent.StartOffset -ge $nativeStart[0].Extent.StartOffset } | ForEach-Object { $_.Extent.Text }) -join "`n")
$nativeBody = '$PSScriptRoot = ' + "'" + (Split-Path -Parent $nativeAnalysisPath).Replace("'", "''") + "'`n" + $nativeBody
$masterLlmConfiguration = (Get-Content -LiteralPath (Join-Path $PSScriptRoot '../config/workbench-terraform-profile.json') -Raw | ConvertFrom-Json -Depth 100).llmConfiguration
$expectedAssignments = @($masterLlmConfiguration.assignments | ForEach-Object {
    $assignment = $_
    $model = @($masterLlmConfiguration.models | Where-Object key -CEQ $assignment.modelKey)[0]
    [pscustomobject]@{ assignmentId = 1 + [Array]::IndexOf(@($masterLlmConfiguration.assignments), $assignment); taskCode = $assignment.taskCode;
        providerCode = $model.providerCode; model = $model.modelCode; adapterCode = $assignment.adapterCode; reasoningEffort = $assignment.reasoningEffort }
})
function Invoke-NativeAvailabilityFixture {
    param([string]$Body, [switch]$UnavailableRuleProfile, [int]$ResumeRunId = 0, [switch]$Force, [int]$ContinueRunId = 0)
    & {
        param([string]$Body, [bool]$UnavailableRuleProfile, [int]$ResumeRunId, [bool]$Force, [int]$ContinueRunId)
        $EvaluatorCommand = 'fixture-copilot'
        $MaxParallelBatches = 3
        $DatabaseGuid = '12345678-1234-4234-8234-123456789abc'
        $DatabasePath = Join-Path ([IO.Path]::GetTempPath()) 'not-created-native-availability.sqlite'
        $LASTEXITCODE = 0
        $script:nativeSelectedProfiles = $null
        $script:nativeAnalysisRequest = $null
        $script:nativeAnalysisStarted = $false
        function Resolve-HostedCliLaunch { param([string]$EvaluatorCommand) [pscustomobject]@{ commandPath = $EvaluatorCommand } }
        function Get-HostedCliAvailability {
            param([object]$Launch, [Collections.IDictionary]$Profiles)
            $script:nativeSelectedProfiles = $Profiles
            if ($UnavailableRuleProfile -and $Profiles.Contains('rule-reevaluation')) { throw 'Fixture assigned reevaluation model unavailable' }
            $resolved = @($Profiles.Keys | ForEach-Object { [pscustomobject]@{ name = $_; model = $Profiles[$_].model; reasoningEffort = $Profiles[$_].reasoningEffort } })
            [pscustomobject]@{ version = '1.0.102'; profiles = $resolved }
        }
        function node {
            [CmdletBinding(PositionalBinding = $false)]
            param([Parameter(ValueFromPipeline)][string]$InputObject, [Parameter(ValueFromRemainingArguments)][object[]]$Arguments)
            process {
                if ('llm-runtime' -in $Arguments) {
                    [pscustomobject]@{ assignments = $expectedAssignments } | ConvertTo-Json -Depth 100 -Compress
                } elseif ('continue-analysis' -in $Arguments) {
                    $script:nativeAnalysisStarted = $true
                    $script:nativeAnalysisRequest = $InputObject | ConvertFrom-Json
                    foreach ($phase in @('routing', 'consolidation', 'synthesis', 'adjudication')) {
                        Write-Host ('OFFLINE PREPARATION START: ' + $phase)
                        @{ kind = 'downstream-progress'; state = 'plan'; phase = $phase; runId = $ContinueRunId; batchCount = 1;
                            recoveredBatchCount = 0; workerCount = 1; pendingPayloadBytes = 12000; estimatedMilliseconds = 1000 } | ConvertTo-Json -Compress
                        @{ kind = 'downstream-progress'; state = 'running'; phase = $phase; runId = $ContinueRunId; evaluationId = 1; batchNumber = 1; batchCount = 1 } | ConvertTo-Json -Compress
                        @{ kind = 'downstream-progress'; state = 'passed'; phase = $phase; runId = $ContinueRunId; evaluationId = 1; batchNumber = 1; batchCount = 1;
                            completedBatchCount = 1; resultCount = 2; batchElapsedMilliseconds = 1000; totalElapsedMilliseconds = 1000; remainingMilliseconds = 0 } | ConvertTo-Json -Compress
                        @{ kind = 'downstream-progress'; state = 'phase-complete'; phase = $phase; runId = $ContinueRunId; batchCount = 1;
                            evaluatedBatchCount = 1; recoveredBatchCount = 0; totalElapsedMilliseconds = 1000 } | ConvertTo-Json -Compress
                    }
                    $result = @{ runId = $ContinueRunId; outcome = 'complete'; sourceCount = 60; assessmentCount = 60; groupCount = 2; comparisonCount = 1; readyForUi = $false }
                    @{ kind = 'downstream-progress'; state = 'complete' } + $result | ConvertTo-Json -Compress
                    $result | ConvertTo-Json -Compress
                } elseif ('assess' -in $Arguments -or 'resume-assess' -in $Arguments) {
                    $script:nativeAnalysisStarted = $true
                    $script:nativeAnalysisRequest = $InputObject | ConvertFrom-Json
                    $fixtureRunId = if ($ResumeRunId -gt 0) { $ResumeRunId } else { 1 }
                    $preservedSources = if ($ResumeRunId -gt 0) { 20 } else { 0 }
                    @{ kind = 'assessment-progress'; state = 'plan'; runId = $fixtureRunId; totalSourceCount = (60 + $preservedSources);
                        cachedSourceCount = 0; recoveredSourceCount = $preservedSources; pendingSourceCount = 60; batchCount = 3;
                        workerCount = 3; pendingPayloadBytes = 12000; estimatedMilliseconds = 10000 } | ConvertTo-Json -Compress
                    foreach ($batch in 1..3) {
                        @{ kind = 'assessment-progress'; state = 'running'; runId = $fixtureRunId; evaluationId = $batch; batchNumber = $batch;
                            batchCount = 3; batchId = "synthetic-source-$batch"; sourceDefinitionId = 'synthetic-source'; sourceCount = 20 } | ConvertTo-Json -Compress
                    }
                    $completedCount = $preservedSources
                    foreach ($batch in @(3, 1, 2)) {
                        $completedCount += 20
                        @{ kind = 'assessment-progress'; state = 'passed'; runId = $fixtureRunId; evaluationId = $batch; batchNumber = $batch; batchCount = 3;
                            sourceCount = $completedCount; assessmentCount = $completedCount; totalElapsedMilliseconds = 3000;
                            batchElapsedMilliseconds = 1000; remainingMilliseconds = 2000 } | ConvertTo-Json -Compress
                    }
                    $result = @{ runId = $fixtureRunId; completedSources = (60 + $preservedSources); completedAssessments = (60 + $preservedSources);
                        sourceCount = (60 + $preservedSources); cachedSourceCount = 0; recoveredSourceCount = $preservedSources; evaluatedSourceCount = 60;
                        evaluatedBatchCount = 3; assessmentComplete = $true; readyForUi = $false }
                    @{ kind = 'assessment-progress'; state = 'complete'; totalElapsedMilliseconds = 3000 } + $result | ConvertTo-Json -Compress
                    $result | ConvertTo-Json -Compress
                } else { throw 'Unregistered offline database operation' }
            }
        }
        $failed = $false
        $failure = $null
        $rendered = @(& ([scriptblock]::Create($Body)) 6>&1 | ForEach-Object { [string]$_ })
        [pscustomobject]@{ profiles = $script:nativeSelectedProfiles; request = $script:nativeAnalysisRequest;
            started = $script:nativeAnalysisStarted; rendered = $rendered -join "`n" }
    } $Body ([bool]$UnavailableRuleProfile) $ResumeRunId ([bool]$Force) $ContinueRunId
}
$nativeAvailable = Invoke-NativeAvailabilityFixture -Body $nativeBody
$mismatchedAssignments = @($expectedAssignments | Where-Object { -not $nativeAvailable.profiles.Contains($_.taskCode) -or
    $nativeAvailable.profiles[$_.taskCode].model -cne $_.model -or $nativeAvailable.profiles[$_.taskCode].reasoningEffort -cne $_.reasoningEffort })
Add-TestResult -Name 'native-analysis-checks-all-master-profile-assignments' -Passed ($mismatchedAssignments.Count -eq 0 -and
    $nativeAvailable.profiles.Count -eq $expectedAssignments.Count -and $nativeAvailable.started -and
    @($nativeAvailable.request.llmAssignmentIds).Count -eq $expectedAssignments.Count -and -not $nativeAvailable.request.PSObject.Properties['model'] -and
    $nativeAvailable.rendered -match 'LLM AVAILABILITY' -and $nativeAvailable.rendered -match '\[PASSED\]\s+chat' -and
    $nativeAvailable.rendered -match '\[PASSED\]\s+rule-reevaluation') -Detail 'Native analysis validates and reports every database-assigned task model, passing pinned assignment IDs rather than global slot settings.'
Add-TestResult -Name 'native-analysis-sectioned-aligned-database-output' -Passed ($nativeAvailable.rendered -match 'DATABASE WORKSPACE' -and
    $nativeAvailable.rendered -match 'not-created-native-availability.sqlite' -and $nativeAvailable.rendered -match 'SQLite 3.37.0 or newer' -and
    $nativeAvailable.rendered.IndexOf('SOURCE ASSESSMENT', [StringComparison]::Ordinal) -gt $nativeAvailable.rendered.IndexOf('LLM AVAILABILITY', [StringComparison]::Ordinal) -and
    $nativeAvailable.rendered -match '\[RUNNING\]\s+source-assessment 1/3\s+: synthetic-source-001 \(20 sources\)' -and
    $nativeAvailable.rendered -match '(?m)^\[PASSED\]\s+source-assessment 1/3\s+: Total Elapsed .+ : \[Batch: .+\] : \[Remaining: .+\]\r?$' -and
    $nativeAvailable.rendered -match 'Workers\s+: 3' -and $nativeAvailable.rendered -match 'Payload\s+:' -and $nativeAvailable.rendered -match 'Estimated\s+:' -and
    $nativeAvailable.request.maxParallelBatches -eq 3 -and
    $nativeAvailable.rendered -match 'SOURCE ASSESSMENT SUMMARY' -and $nativeAvailable.rendered -notmatch 'native-assessment run=') -Detail 'Database identity, compatibility guidance, phase header and timed lifecycle rows use the shared renderer and distinguish batch size from persisted totals without claiming full UI readiness.'
$nativeAssessmentLines = @($nativeAvailable.rendered -split '\r?\n' | Where-Object { $_ -match '^\[(RUNNING|PASSED)\]\s+source-assessment' })
$nativeResumeLines = @((Invoke-NativeAvailabilityFixture -Body $nativeBody -ResumeRunId 5).rendered -split '\r?\n' | Where-Object { $_ -match '^\[(RUNNING|PASSED)\]\s+source-assessment' })
$nativeAssessmentColonColumns = @(@($nativeAssessmentLines + $nativeResumeLines) | ForEach-Object { $_.IndexOf(':', [StringComparison]::Ordinal) } | Sort-Object -Unique)
Add-TestResult -Name 'native-analysis-shared-alignment-and-duration-last' -Passed ($nativeAssessmentLines.Count -eq 8 -and
    $nativeResumeLines.Count -eq 8 -and $nativeAssessmentColonColumns.Count -eq 1 -and
    @($nativeAssessmentLines + $nativeResumeLines | Where-Object { $_ -match '^\[PASSED\]' -and $_ -notmatch '\]$' }).Count -eq 0) -Detail 'Fresh and resumed database batch output shares alignment and ends in timing fields, with a workload plan and explicit phase completion.'
$expectedAssessmentLines = @(
    '  Sources   : 60 total | 0 cached | 0 recovered | 60 pending'
    '  Batches   : 3 pending'
    '  Workers   : 3'
    "  Payload   : $(Format-ByteSize -Bytes 12000)"
    "  Estimated : $(Format-ElapsedDuration -Milliseconds 10000)"
    ''
    (Format-ValidationStatusLine -Status running -Name 'source-assessment' -Detail 'Evaluating 60 pending sources across 3 batches' -NameWidth 42)
    foreach ($batch in 1..3) {
        $displayId = 'synthetic-source-{0:D3}' -f $batch
        Format-ValidationStatusLine -Status running -Name "source-assessment $batch/3" -Detail "$displayId (20 sources)" -NameWidth 42
    }
    foreach ($batch in @(3, 1, 2)) {
        $detail = "Total Elapsed $(Format-ElapsedDuration -Milliseconds 3000) : [Batch: $(Format-ElapsedDuration -Milliseconds 1000)] : [Remaining: $(Format-ElapsedDuration -Milliseconds 2000)]"
        Format-ValidationStatusLine -Status passed -Name "source-assessment $batch/3" -Detail $detail -NameWidth 42
    }
    (Format-ValidationStatusLine -Status passed -Name 'source-assessment' -Detail "60 sources | 0 cached | 0 recovered | 60 evaluated : [Elapsed: $(Format-ElapsedDuration -Milliseconds 3000)]" -NameWidth 42)
)
$nativeRenderedLines = @($nativeAvailable.rendered -split '\r?\n')
$nativePlanStart = [Array]::FindIndex($nativeRenderedLines, [Predicate[string]]{ param($line) $line -cmatch '^  Sources\s+:' })
$nativePhaseEnd = [Array]::FindIndex($nativeRenderedLines, [Predicate[string]]{ param($line) $line -cmatch '^\[PASSED\]\s+source-assessment\s+:' })
$nativePresentationMatches = $nativePlanStart -ge 0 -and $nativePhaseEnd -ge $nativePlanStart -and
    ([string]::Join("`n", $nativeRenderedLines[$nativePlanStart..$nativePhaseEnd]) -ceq [string]::Join("`n", $expectedAssessmentLines))
Add-TestResult -Name 'native-analysis-legacy-display-parity-without-legacy-runtime' -Passed ($nativePresentationMatches -and
    $nativeBody -notmatch 'SourceAssessmentPresentation') -Detail 'Database-owned rendering preserves the legacy workload spacing, padded display IDs, aligned batch lifecycle and completion timing without importing the legacy presentation runtime.'
$nativeUnavailableStopped = $false
try { $null = Invoke-NativeAvailabilityFixture -Body $nativeBody -UnavailableRuleProfile }
catch { $nativeUnavailableStopped = $_.Exception.Message -like '*assigned reevaluation model unavailable*' -and -not $script:nativeAnalysisStarted }
Add-TestResult -Name 'native-analysis-unavailable-assigned-model-stops-analysis' -Passed $nativeUnavailableStopped -Detail 'An unavailable database-assigned reevaluation model fails preflight before native analysis begins.'
$nativeResumed = Invoke-NativeAvailabilityFixture -Body $nativeBody -ResumeRunId 5
Add-TestResult -Name 'native-analysis-explicit-resume-preserves-progress-output' -Passed ($nativeResumed.request.runId -eq 5 -and
    -not $nativeResumed.request.PSObject.Properties['force'] -and $nativeResumed.rendered -match '80 total \| 0 cached \| 20 recovered \| 60 pending' -and
    $nativeResumed.rendered -match 'SOURCE ASSESSMENT SUMMARY') -Detail 'Explicit continuation passes the selected run ID, reports preserved results separately and does not masquerade as fresh forced evaluation.'
$nativeForceResumeRejected = $false
try { $null = Invoke-NativeAvailabilityFixture -Body $nativeBody -ResumeRunId 5 -Force }
catch { $nativeForceResumeRejected = $_.Exception.Message -like '*cannot be combined with Force*' }
Add-TestResult -Name 'native-analysis-force-resume-conflict-rejected' -Passed $nativeForceResumeRejected -Detail 'Force and same-run continuation have distinct authority and cannot be combined.'

$nativeContinued = Invoke-NativeAvailabilityFixture -Body $nativeBody -ContinueRunId 5
$preparationOrderValid = $true
foreach ($phase in @('routing', 'consolidation', 'synthesis', 'adjudication')) {
    $header = 'NATIVE ' + $phase.ToUpperInvariant() + ' PREPARATION'
    $headerPosition = $nativeContinued.rendered.IndexOf($header, [StringComparison]::Ordinal)
    $statusPosition = $nativeContinued.rendered.IndexOf($phase + '-preparation', [StringComparison]::Ordinal)
    $planningPosition = $nativeContinued.rendered.IndexOf('OFFLINE PREPARATION START: ' + $phase, [StringComparison]::Ordinal)
    $headerCount = [regex]::Matches($nativeContinued.rendered, '(?m)^' + [regex]::Escape($header) + '\r?$').Count
    $processing = 'PROCESSING NATIVE ' + $phase.ToUpperInvariant()
    $processingPosition = $nativeContinued.rendered.IndexOf($processing, [StringComparison]::Ordinal)
    $processingCount = [regex]::Matches($nativeContinued.rendered, '(?m)^' + [regex]::Escape($processing) + '\r?$').Count
    $preparationOrderValid = $preparationOrderValid -and $headerPosition -ge 0 -and $statusPosition -gt $headerPosition -and
        $planningPosition -gt $statusPosition -and $processingPosition -gt $planningPosition -and $headerCount -eq 1 -and $processingCount -eq 1
}
Add-TestResult -Name 'native-analysis-preparation-headers-precede-planning' -Passed $preparationOrderValid -Detail 'Each actual phase header and preparation status precedes backend planning, without duplicate headers or invented planning percentages.'
Add-TestResult -Name 'native-analysis-processing-rows-preserve-assessment-timing-and-spacing' -Passed ($nativeContinued.rendered -match 'Estimated\s+: .+ \(provisional\)' -and
    $nativeContinued.rendered -match '(?m)^\[RUNNING\]\s+routing 1/1\s+: Evaluating database evidence\r?$' -and
    $nativeContinued.rendered -match '(?m)^\[PASSED\]\s+routing 1/1\s+: Total Elapsed .+ : \[Batch: .+\] : \[Remaining: .+\]\r?$' -and
    $nativeContinued.rendered -notmatch 'Evaluating pinned database evidence') -Detail 'Processing phases retain actual workload numbers with a provisional estimate, readable evidence wording and matching assessment elapsed/batch/remaining labels.'
Add-TestResult -Name 'native-analysis-downstream-continuation-is-distinct-from-source-resume' -Passed ($nativeContinued.request.runId -eq 5 -and
    -not $nativeContinued.request.PSObject.Properties['force'] -and $nativeContinued.rendered -match 'NATIVE ROUTING' -and
    $nativeContinued.rendered -match 'NATIVE CONSOLIDATION' -and $nativeContinued.rendered -match 'NATIVE SYNTHESIS' -and
    $nativeContinued.rendered -match 'NATIVE ADJUDICATION' -and $nativeContinued.rendered -match 'NATIVE ANALYSIS SUMMARY' -and
    $nativeContinued.rendered -notmatch 'SOURCE ASSESSMENT SUMMARY') -Detail 'Explicit downstream continuation runs all four persisted stages without a source-assessment pass or a new forced run.'
$nativeContinuationConflictRejected = $false
try { $null = Invoke-NativeAvailabilityFixture -Body $nativeBody -ContinueRunId 5 -ResumeRunId 5 }
catch { $nativeContinuationConflictRejected = $_.Exception.Message -like '*cannot be combined with ResumeRunId or Force*' }
Add-TestResult -Name 'native-analysis-source-and-downstream-continuation-conflict-rejected' -Passed $nativeContinuationConflictRejected -Detail 'Source recovery and downstream continuation cannot be combined in an ambiguous command.'

$availabilityFixtureAst = (Get-Command Invoke-NativeAvailabilityFixture).ScriptBlock.Ast
$offlineAvailabilityFunctions = @('Resolve-HostedCliLaunch', 'Get-HostedCliAvailability') | ForEach-Object {
    $functionName = $_
    $definition = $availabilityFixtureAst.Find({ param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -ceq $functionName }.GetNewClosure(), $true)
    $definition.Extent.Text
}
$assignmentJson = @($expectedAssignments) | ConvertTo-Json -Depth 10 -Compress
$formatterPath = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../../tools/ValidationOutput.psm1'))
$nativeHelpersPath = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../modules/shared/HostedToolkit.Helpers.psm1'))
$busyOutputValid = $true
$settledFailureOutputValid = $true
$prematureFailureRejected = $false
$outputCases = @(
    @{ continueId = 0; mode = 'busy' }
    @{ continueId = 5; mode = 'busy' }
    @{ continueId = 5; mode = 'settled-failure' }
    @{ continueId = 5; mode = 'premature-failure' }
)
foreach ($outputCase in $outputCases) {
    $continueId = $outputCase.continueId
    $childScript = @"
Set-StrictMode -Version Latest
`$ErrorActionPreference = 'Stop'
Import-Module '$($nativeHelpersPath.Replace("'", "''"))' -Force
Import-Module '$($formatterPath.Replace("'", "''"))' -Force
`$expectedAssignments = '$($assignmentJson.Replace("'", "''"))' | ConvertFrom-Json
`$UnavailableRuleProfile = `$false
`$ResumeRunId = 0
`$ContinueRunId = $continueId
`$Force = `$false
`$MaxParallelBatches = 3
`$DatabaseGuid = '12345678-1234-4234-8234-123456789abc'
`$DatabasePath = Join-Path ([IO.Path]::GetTempPath()) 'not-created-native-busy-output.sqlite'
`$EvaluatorCommand = 'fixture-copilot'
`$global:LASTEXITCODE = 0
`$failureMode = '$($outputCase.mode)'
$($offlineAvailabilityFunctions -join "`n")
function node {
    [CmdletBinding(PositionalBinding = `$false)]
    param([Parameter(ValueFromPipeline)][string]`$InputObject, [Parameter(ValueFromRemainingArguments)][object[]]`$Arguments)
    process {
        if ('llm-runtime' -in `$Arguments) {
            @{ assignments = `$expectedAssignments } | ConvertTo-Json -Depth 100 -Compress
        } elseif (`$failureMode -in @('settled-failure', 'premature-failure')) {
            @{ kind = 'downstream-progress'; state = 'plan'; phase = 'routing'; runId = 5; batchCount = 6;
                recoveredBatchCount = 0; workerCount = 3; pendingPayloadBytes = 12000; estimatedMilliseconds = 1000 } | ConvertTo-Json -Compress
            foreach (`$batch in 1..3) {
                @{ kind = 'downstream-progress'; state = 'running'; phase = 'routing'; runId = 5; evaluationId = `$batch; batchNumber = `$batch; batchCount = 6 } | ConvertTo-Json -Compress
            }
            @{ kind = 'downstream-progress'; state = 'failed'; phase = 'routing'; runId = 5; batchNumber = 2; batchCount = 6;
                failureCode = 'evaluator-or-result-failed'; batchElapsedMilliseconds = 1000; totalElapsedMilliseconds = 1000 } | ConvertTo-Json -Compress
            if (`$failureMode -ceq 'settled-failure') {
                `$completed = 0
                foreach (`$batch in @(3, 1)) {
                    `$completed += 1
                    @{ kind = 'downstream-progress'; state = 'passed'; phase = 'routing'; runId = 5; evaluationId = `$batch; batchNumber = `$batch; batchCount = 6;
                        completedBatchCount = `$completed; resultCount = 1; batchElapsedMilliseconds = 1500; totalElapsedMilliseconds = 1500; remainingMilliseconds = 2000 } | ConvertTo-Json -Compress
                }
            }
            @{ kind = 'execution-failed'; code = 'workbench-native-stage-failed'; phase = 'routing' } | ConvertTo-Json -Compress
            `$global:LASTEXITCODE = 1
        } else {
            @{ kind = 'execution-refused'; code = 'workbench-execution-already-running' } | ConvertTo-Json -Compress
            `$global:LASTEXITCODE = 1
        }
    }
}
$nativeBody
"@
    $start = [Diagnostics.ProcessStartInfo]::new('pwsh')
    $start.UseShellExecute = $false
    $start.RedirectStandardInput = $true
    $start.RedirectStandardOutput = $true
    $start.RedirectStandardError = $true
    foreach ($argument in @('-NoProfile', '-NonInteractive', '-Command', '-')) {
        $start.ArgumentList.Add($argument)
    }
    $process = [Diagnostics.Process]::new()
    $process.StartInfo = $start
    try {
        $null = $process.Start()
        $stdout = $process.StandardOutput.ReadToEndAsync()
        $stderr = $process.StandardError.ReadToEndAsync()
        $process.StandardInput.WriteLine("& {`n$childScript`n}`n")
        $process.StandardInput.Close()
        $process.WaitForExit()
        $rendered = $stdout.GetAwaiter().GetResult()
        $errors = $stderr.GetAwaiter().GetResult()
        $expectedRows = @($expectedAssignments | ForEach-Object { [pscustomobject]@{ status = 'passed'; name = $_.taskCode } })
        $expectedFailures = @('  - Another analysis command is already running or starting for this database')
        if ($outputCase.mode -ceq 'busy') {
            $expectedRows += @([pscustomobject]@{ status = 'failed'; name = 'execution-guard' })
        } else {
            $expectedRows += @(
                [pscustomobject]@{ status = 'passed'; name = 'routing-preparation' }
                [pscustomobject]@{ status = 'failed'; name = 'routing 2/6' }
                [pscustomobject]@{ status = 'passed'; name = 'routing 3/6' }
                [pscustomobject]@{ status = 'passed'; name = 'routing 1/6' }
            )
            $expectedFailures = @('  - routing 2/6 failed; committed results retained; unresolved work requires recovery')
        }
        $summary = @(Write-ValidationSectionHeader -Title 'Native Analysis Summary') +
            @(Write-ValidationSummary -Fields ([ordered]@{ Status = 'FAILED'; Checks = $expectedRows.Count; Passed = @($expectedRows | Where-Object status -CEQ 'passed').Count; Failed = 1 })) +
            @(Write-ValidationSectionHeader -Title 'Native Analysis Checks') +
            @(Write-ValidationTwoColumnTable -Rows $expectedRows -FirstHeader 'Status' -FirstProperty 'status' -SecondHeader 'Check' -SecondProperty 'name' -UppercaseFirst) +
            @(Write-ValidationSectionHeader -Title 'Failures') + $expectedFailures
        $normalized = $rendered -replace "`r`n", "`n"
        if ($outputCase.mode -ceq 'busy') {
            $busyOutputValid = $busyOutputValid -and $process.ExitCode -eq 1 -and [string]::IsNullOrWhiteSpace($errors) -and
                $normalized.Contains(($summary -join "`n")) -and $rendered -match '\[FAILED\]\s+execution-guard\s+:' -and
                $rendered -notmatch 'did not complete|Reason\s+:|Action\s+:'
        } elseif ($outputCase.mode -ceq 'settled-failure') {
            $lastSettledPosition = $rendered.IndexOf('[PASSED]   routing 1/6', [StringComparison]::Ordinal)
            $summaryPosition = $rendered.IndexOf('NATIVE ANALYSIS SUMMARY', [StringComparison]::Ordinal)
            $settledFailureOutputValid = $process.ExitCode -eq 1 -and [string]::IsNullOrWhiteSpace($errors) -and
                $normalized.Contains(($summary -join "`n")) -and $lastSettledPosition -ge 0 -and $summaryPosition -gt $lastSettledPosition -and
                $rendered -match '(?m)^\[FAILED\]\s+routing 2/6\s+: Total Elapsed .+ : \[Batch: .+\]\r?$' -and
                $rendered -notmatch 'routing 4/6|CONSOLIDATION|did not complete'
        } else {
            $prematureFailureRejected = $process.ExitCode -eq 1 -and $errors -match 'failure does not match settled failed work' -and
                $rendered -notmatch 'NATIVE ANALYSIS SUMMARY'
        }
    } finally { $process.Dispose() }
}
Add-TestResult -Name 'native-analysis-busy-command-preserves-checks-and-clean-failure-summary' -Passed $busyOutputValid -Detail 'Actual source/downstream command bodies exit one with the aligned failure, current availability counts, results table and failure bullet; no raw exception or fabricated previous-run passes.'
Add-TestResult -Name 'native-analysis-failed-phase-reports-retained-success-after-workers-settle' -Passed $settledFailureOutputValid -Detail 'Matching failed/passed batch rows settle before the failed summary, retained successes remain counted, exit is nonzero and no later phase starts.'
Add-TestResult -Name 'native-analysis-rejects-failure-summary-before-workers-settle' -Passed $prematureFailureRejected -Detail 'A failed execution event cannot falsely claim completion while tracked workers remain active.'

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
    Write-ValidationSectionHeader -Title 'Workbench contract tests'
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
