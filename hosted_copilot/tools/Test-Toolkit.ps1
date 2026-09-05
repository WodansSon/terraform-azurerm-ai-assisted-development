[CmdletBinding()]
param(
    [ValidateSet('Text', 'Json')]
    [string]$OutputFormat = 'Text',

    [switch]$SkipUpstreamDrift
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
$validationOutputModulePath = Join-Path $repoRoot 'tools/ValidationOutput.psm1'
Import-Module -Name $validationOutputModulePath -Force

$hostedRoot = Join-Path $repoRoot 'hosted_copilot'
$architecturePath = Join-Path $repoRoot 'docs/HOSTED_COPILOT_CODE_REVIEW_ARCHITECTURE.md'
$gitIgnorePath = Join-Path $repoRoot '.gitignore'
$changelogPath = Join-Path $hostedRoot 'CHANGELOG.md'
$forbiddenVersionPath = Join-Path $hostedRoot 'VERSION'
$packageManifestPath = Join-Path $PSScriptRoot 'package-manifest.json'
$installerPath = Join-Path $PSScriptRoot 'Install-Toolkit.ps1'
$interactiveManifestPath = Join-Path $repoRoot 'installer/file-manifest.config'
$hostedRuntimePath = Join-Path $hostedRoot '.github'
$repositoryInstructionsPath = Join-Path $hostedRuntimePath 'copilot-instructions.md'
$goInstructionsPath = Join-Path $hostedRuntimePath 'instructions/azurerm-go.instructions.md'
$testInstructionsPath = Join-Path $hostedRuntimePath 'instructions/azurerm-tests.instructions.md'
$documentationInstructionsPath = Join-Path $hostedRuntimePath 'instructions/azurerm-docs.instructions.md'
$reviewSkillPath = Join-Path $hostedRuntimePath 'skills/code-review/SKILL.md'
$userDocumentationPath = Join-Path $hostedRoot 'docs/HOSTED_COPILOT_CODE_REVIEW.md'
$experimentRunbookPath = Join-Path $hostedRoot 'docs/HOSTED_REVIEW_EXPERIMENT_RUNBOOK.md'
$regressionCasesPath = Join-Path $hostedRoot 'regression/cases'
$reviewResultSchemaPath = Join-Path $hostedRoot 'regression/schema/paired-review-result.schema.json'
$reviewCommonModulePath = Join-Path $PSScriptRoot 'Review.Common.psm1'
$reviewBaseInitializerPath = Join-Path $PSScriptRoot 'Initialize-ReviewBases.ps1'
$reviewPairCreatorPath = Join-Path $PSScriptRoot 'New-ReviewPair.ps1'
$reviewPullRequestImporterPath = Join-Path $PSScriptRoot 'Import-PullRequest.ps1'
$reviewTestCasePublisherPath = Join-Path $PSScriptRoot 'Publish-TestCase.ps1'
$reviewCapturePath = Join-Path $PSScriptRoot 'Capture-ReviewPair.ps1'
$reviewPairCloserPath = Join-Path $PSScriptRoot 'Close-ReviewPair.ps1'
$reviewResultValidatorPath = Join-Path $PSScriptRoot 'Test-ReviewResults.ps1'
$instructionCatalogPath = Join-Path $hostedRoot 'copilot-rule-catalog/instruction-catalog.json'
$instructionCatalogSchemaPath = Join-Path $hostedRoot 'copilot-rule-catalog/instruction-catalog.schema.json'
$intakeLedgerPath = Join-Path $hostedRoot 'copilot-rule-catalog/interactive-intake-ledger.json'
$intakeLedgerSchemaPath = Join-Path $hostedRoot 'copilot-rule-catalog/interactive-intake-ledger.schema.json'
$promotionPlanSchemaPath = Join-Path $hostedRoot 'copilot-rule-catalog/promotion-plan.schema.json'
$promotionReceiptSchemaPath = Join-Path $hostedRoot 'copilot-rule-catalog/promotion-receipt.schema.json'
$ruleIntakeBundleSchemaPath = Join-Path $hostedRoot 'copilot-rule-catalog/rule-intake-review.schema.json'
$assessmentBaselinePath = Join-Path $hostedRoot 'copilot-rule-catalog/rule-assessments/assessment-baseline.json'
$assessmentBaselineSchemaPath = Join-Path $hostedRoot 'copilot-rule-catalog/rule-assessments/assessment-baseline.schema.json'
$maintainerRulePaths = @('documentation.rules.md', 'implementation.rules.md', 'testing.rules.md') | ForEach-Object { Join-Path $hostedRoot "copilot-rule-catalog/maintainer-rules/$_" }
$promotionAuditPath = Join-Path $hostedRoot 'copilot-rule-catalog/audit'
$instructionGeneratorPath = Join-Path $PSScriptRoot 'Generate-Instructions.ps1'
$instructionGenerationTestPath = Join-Path $PSScriptRoot 'Test-InstructionGeneration.ps1'
$guidanceCapacityPath = Join-Path $PSScriptRoot 'Get-GuidanceCapacity.ps1'
$ruleIntakeBundlePath = Join-Path $PSScriptRoot 'New-RuleIntakeReview.ps1'
$ruleIntakeTestPath = Join-Path $PSScriptRoot 'Test-RuleIntakeReview.ps1'
$ruleIntakeAssessmentPath = Join-Path $PSScriptRoot 'Invoke-RuleIntakeAssessment.ps1'
$ruleIntakeAssessmentTestPath = Join-Path $PSScriptRoot 'Test-RuleIntakeAssessment.ps1'
$assessmentBaselinePublisherPath = Join-Path $PSScriptRoot 'Publish-RuleIntakeAssessmentBaseline.ps1'
$ruleWorkbenchLauncherPath = Join-Path $PSScriptRoot 'Start-RuleWorkbench.ps1'
$ruleWorkbenchTestPath = Join-Path $PSScriptRoot 'Test-RuleWorkbench.ps1'
$ruleWorkbenchIndexPath = Join-Path $hostedRoot 'workbench/index.html'
$ruleWorkbenchScriptPath = Join-Path $hostedRoot 'workbench/app.js'
$ruleWorkbenchStylesPath = Join-Path $hostedRoot 'workbench/styles.css'
$upstreamSourceValidatorPath = Join-Path $PSScriptRoot 'Test-UpstreamSources.ps1'
$tokenEstimator = 'character-quarter-estimate-25pct-v1'
$mermaidCliPackage = '@mermaid-js/mermaid-cli@11.16.0'
$puppeteerPackage = 'puppeteer@24.15.0'

$issues = New-Object 'System.Collections.Generic.List[string]'
$checks = New-Object 'System.Collections.Generic.List[object]'
$checkStartTimes = @{}
$tokenCapacityResult = $null

function Start-ValidationCheck {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name
    )

    $checkStartTimes[$Name] = Get-Date
    if ($OutputFormat -eq 'Text') {
        Write-Host (Format-ValidationStatusLine -Status 'running' -Name $Name -Detail 'IN PROGRESS')
    }
}

function Add-CheckResult {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name,

        [Parameter(Mandatory = $true)]
        [bool]$Passed,

        [Parameter(Mandatory = $true)]
        [string]$Detail
    )

    $durationSeconds = 0
    if ($checkStartTimes.ContainsKey($Name)) {
        $durationSeconds = [Math]::Round(((Get-Date) - $checkStartTimes[$Name]).TotalSeconds, 2)
        $checkStartTimes.Remove($Name)
    }

    $status = if ($Passed) { 'passed' } else { 'failed' }

    $checks.Add([pscustomobject]@{
        name = $Name
        status = $status
        success = $Passed
        durationSeconds = $durationSeconds
        detail = $Detail
    })

    if ($OutputFormat -eq 'Text') {
        Write-Host (Format-ValidationStatusLine -Status $status -Name $Name -Detail ("{0}s" -f $durationSeconds))
    }
}

function Add-SkippedCheck {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name,

        [Parameter(Mandatory = $true)]
        [string]$Detail
    )

    $checks.Add([pscustomobject]@{
        name = $Name
        status = 'skipped'
        success = $true
        durationSeconds = 0
        detail = $Detail
    })

    if ($OutputFormat -eq 'Text') {
        Write-Host (Format-ValidationStatusLine -Status 'skipped' -Name $Name -Detail 'NOT APPLICABLE')
    }
}

function Add-ValidationIssue {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name,

        [Parameter(Mandatory = $true)]
        [string]$Issue
    )

    $issues.Add($Issue)
    Add-CheckResult -Name $Name -Passed $false -Detail $Issue
}

function Get-Sha256Hash {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

$runtimeStarted = (Test-Path -LiteralPath $hostedRuntimePath) -or (Test-Path -LiteralPath $packageManifestPath)
$phase = if ($runtimeStarted) { 'runtime' } else { 'design' }
$purpose = 'experiment-support'
$deploymentModel = 'source-checkout'

if ($OutputFormat -eq 'Text') {
    Write-ValidationSectionHeader -Title 'Hosted toolkit validation'
    Write-Output ("  Purpose     : {0}" -f $purpose.ToUpperInvariant())
    Write-Output ("  Deployment  : {0}" -f $deploymentModel.ToUpperInvariant())
    Write-Output ("  Phase       : {0}" -f $phase.ToUpperInvariant())
    Write-Output ("  Token Guard : {0}" -f $tokenEstimator.ToUpperInvariant())
    Write-Output ''
}

Start-ValidationCheck -Name 'architecture'
if (Test-Path -LiteralPath $architecturePath) {
    Add-CheckResult -Name 'architecture' -Passed $true -Detail 'Hosted Toolkit architecture document exists.'
}
else {
    Add-ValidationIssue -Name 'architecture' -Issue "Hosted Toolkit architecture document was not found at $architecturePath"
}

Start-ValidationCheck -Name 'changelog'
if (Test-Path -LiteralPath $changelogPath) {
    $changelogContent = Get-Content -LiteralPath $changelogPath -Raw
    $unreleasedMatch = [regex]::Match($changelogContent, '(?ms)^## \[Unreleased\]\s*(?<body>.*?)(?=^## \[|\z)')
    $requiredSections = @('Added', 'Changed', 'Fixed')
    $missingSections = @()

    if (-not $unreleasedMatch.Success) {
        $missingSections = $requiredSections
    }
    else {
        $unreleasedBody = $unreleasedMatch.Groups['body'].Value
        foreach ($section in $requiredSections) {
            if ($unreleasedBody -notmatch "(?m)^### $section\s*$") {
                $missingSections += $section
            }
        }
    }

    if ($missingSections.Count -eq 0) {
        Add-CheckResult -Name 'changelog' -Passed $true -Detail 'Hosted Toolkit changelog contains Unreleased Added, Changed, and Fixed sections.'
    }
    else {
        Add-ValidationIssue -Name 'changelog' -Issue ("Hosted Toolkit changelog is missing required Unreleased sections: {0}" -f ($missingSections -join ', '))
    }
}
else {
    Add-ValidationIssue -Name 'changelog' -Issue "Hosted Toolkit changelog was not found at $changelogPath"
}

Start-ValidationCheck -Name 'deployment-model'
if (Test-Path -LiteralPath $forbiddenVersionPath) {
    Add-ValidationIssue -Name 'deployment-model' -Issue 'Hosted Toolkit is deployed directly from this source repository and must not define hosted_copilot/VERSION'
}
else {
    Add-CheckResult -Name 'deployment-model' -Passed $true -Detail 'Hosted Toolkit uses direct source deployment without a separate version file or release bundle.'
}

$manifestConfig = $null
if (Test-Path -LiteralPath $packageManifestPath) {
    Start-ValidationCheck -Name 'package-manifest'
    try {
        $manifestConfig = Get-Content -LiteralPath $packageManifestPath -Raw | ConvertFrom-Json
        if ($manifestConfig.schemaVersion -ne 1) {
            throw "unsupported schemaVersion $($manifestConfig.schemaVersion)"
        }
        if ([string]::IsNullOrWhiteSpace([string]$manifestConfig.packageIdentity)) {
            throw 'packageIdentity is empty'
        }
        if ([string]::IsNullOrWhiteSpace([string]$manifestConfig.installedStatePath)) {
            throw 'installedStatePath is empty'
        }
        if (@($manifestConfig.files).Count -eq 0) {
            throw 'files is empty'
        }
        foreach ($file in @($manifestConfig.files)) {
            if ($file -isnot [string] -or [string]::IsNullOrWhiteSpace([string]$file)) {
                throw 'each files entry must be a non-empty relative path string'
            }
        }
        Add-CheckResult -Name 'package-manifest' -Passed $true -Detail 'Hosted Toolkit package manifest schema is valid.'
    }
    catch {
        Add-ValidationIssue -Name 'package-manifest' -Issue "Hosted Toolkit package manifest is not valid JSON: $($_.Exception.Message)"
    }
}
elseif ($runtimeStarted) {
    Start-ValidationCheck -Name 'package-manifest'
    Add-ValidationIssue -Name 'package-manifest' -Issue 'Hosted Toolkit runtime assets exist, but hosted_copilot/tools/package-manifest.json is missing'
}
else {
    Add-SkippedCheck -Name 'package-manifest' -Detail 'No package manifest is required during the design phase.'
}

if ($runtimeStarted) {
    Start-ValidationCheck -Name 'runtime-layout'
    $requiredRuntimePaths = @(
        $repositoryInstructionsPath,
        $goInstructionsPath,
        $testInstructionsPath,
        $documentationInstructionsPath,
        $reviewSkillPath,
        $userDocumentationPath,
        $experimentRunbookPath,
        $installerPath,
        $reviewResultSchemaPath,
        $reviewCommonModulePath,
        $reviewBaseInitializerPath,
        $reviewPairCreatorPath,
        $reviewPullRequestImporterPath,
        $reviewTestCasePublisherPath,
        $reviewCapturePath,
        $reviewPairCloserPath,
        $reviewResultValidatorPath,
        $instructionCatalogPath,
        $instructionCatalogSchemaPath,
        $intakeLedgerPath,
        $intakeLedgerSchemaPath,
        $promotionPlanSchemaPath,
        $promotionReceiptSchemaPath,
        $ruleIntakeBundleSchemaPath,
        $assessmentBaselinePath,
        $assessmentBaselineSchemaPath,
        $instructionGeneratorPath,
        $instructionGenerationTestPath,
        $guidanceCapacityPath,
        $ruleIntakeBundlePath,
        $ruleIntakeTestPath,
        $ruleIntakeAssessmentPath,
        $ruleIntakeAssessmentTestPath,
        $assessmentBaselinePublisherPath,
        $ruleWorkbenchLauncherPath,
        $ruleWorkbenchTestPath,
        $ruleWorkbenchIndexPath,
        $ruleWorkbenchScriptPath,
        $ruleWorkbenchStylesPath,
        $upstreamSourceValidatorPath
    )
    $missingRuntimePaths = @($requiredRuntimePaths | Where-Object { -not (Test-Path -LiteralPath $_ -PathType Leaf) })
    if ($missingRuntimePaths.Count -eq 0) {
        Add-CheckResult -Name 'runtime-layout' -Passed $true -Detail 'Hosted runtime, installer, and user documentation paths exist.'
    }
    else {
        Add-ValidationIssue -Name 'runtime-layout' -Issue ("Required Hosted runtime paths are missing: {0}" -f ($missingRuntimePaths -join ', '))
    }

    Start-ValidationCheck -Name 'lifecycle-tools'
    $lifecycleIssues = New-Object 'System.Collections.Generic.List[string]'
    $lifecyclePaths = @($reviewCommonModulePath, $reviewBaseInitializerPath, $reviewPairCreatorPath, $reviewPullRequestImporterPath, $reviewTestCasePublisherPath, $reviewCapturePath, $reviewPairCloserPath, $ruleIntakeAssessmentPath, $assessmentBaselinePublisherPath)
    foreach ($lifecyclePath in $lifecyclePaths) {
        if (-not (Test-Path -LiteralPath $lifecyclePath -PathType Leaf)) {
            $lifecycleIssues.Add("lifecycle command is missing: $lifecyclePath")
            continue
        }
        $tokens = $null
        $parseErrors = $null
        [System.Management.Automation.Language.Parser]::ParseFile($lifecyclePath, [ref]$tokens, [ref]$parseErrors) | Out-Null
        if ($parseErrors.Count -gt 0) {
            $lifecycleIssues.Add("lifecycle command does not parse: $lifecyclePath")
        }
    }
    $reviewEffortCommandPaths = @($reviewPairCreatorPath, $reviewPullRequestImporterPath, $reviewTestCasePublisherPath, $reviewCapturePath)
    foreach ($reviewEffortCommandPath in $reviewEffortCommandPaths) {
        try {
            $reviewEffortParameter = (Get-Command -Name $reviewEffortCommandPath -CommandType ExternalScript).Parameters['ReviewEffort']
            $reviewEffortValidateSets = @($reviewEffortParameter.Attributes | Where-Object { $_ -is [System.Management.Automation.ValidateSetAttribute] })
            $reviewEffortValues = @($reviewEffortValidateSets.ValidValues | Sort-Object -Unique)
            if ($reviewEffortValidateSets.Count -ne 1 -or ($reviewEffortValues -join ',') -ne 'Balanced,Lite') {
                throw "expected Lite and Balanced, found $($reviewEffortValues -join ', ')"
            }
        }
        catch {
            $lifecycleIssues.Add("$(Split-Path -Leaf $reviewEffortCommandPath) must accept exactly the Lite and Balanced review effort levels: $($_.Exception.Message)")
        }
    }
    if (Test-Path -LiteralPath $reviewBaseInitializerPath -PathType Leaf) {
        $initializerContent = Get-Content -LiteralPath $reviewBaseInitializerPath -Raw
        if ($initializerContent -notmatch '\[switch\]\$Initialize' -or $initializerContent -notmatch '\[switch\]\$Push' -or $initializerContent -notmatch '\$TestContentBase' -or $initializerContent -notmatch 'Assert-HostedReviewWritableFork') {
            $lifecycleIssues.Add('base initialization must own control, Hosted, and test-content bases behind explicit mutation and writable-fork guards')
        }
    }
    if (Test-Path -LiteralPath $reviewPairCreatorPath -PathType Leaf) {
        $creatorContent = Get-Content -LiteralPath $reviewPairCreatorPath -Raw
        if ($creatorContent -notmatch '\[switch\]\$Create' -or $creatorContent -notmatch '\$SourcePullRequest' -or $creatorContent -notmatch '\$TestContentBase' -or $creatorContent -notmatch 'control-review/' -or $creatorContent -notmatch 'hosted-review/' -or $creatorContent -notmatch 'push --atomic' -or $creatorContent -notmatch 'Assert-HostedReviewWritableFork') {
            $lifecycleIssues.Add('pair creation must mirror one test-content source PR into guarded atomic Control and Hosted review heads')
        }
        try {
            $creatorTokens = $null
            $creatorParseErrors = $null
            $creatorAst = [System.Management.Automation.Language.Parser]::ParseFile($reviewPairCreatorPath, [ref]$creatorTokens, [ref]$creatorParseErrors)
            $pullRequestFilesFunction = $creatorAst.Find({
                    param($node)
                    $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq 'Get-PullRequestFiles'
                }, $true)
            if ($null -eq $pullRequestFilesFunction) {
                throw 'Get-PullRequestFiles was not found'
            }
            $capturedFiles = @(& {
                    param($functionDefinition)

                    function Invoke-HostedReviewGitHubApi {
                        return @(
                            [pscustomobject]@{ filename = 'first.go' },
                            [pscustomobject]@{ filename = 'second.go' }
                        )
                    }

                    . ([scriptblock]::Create($functionDefinition))
                    Get-PullRequestFiles -Repository 'owner/repository' -Number 1 -ExpectedCount 2
                } $pullRequestFilesFunction.Extent.Text)
            if ($capturedFiles.Count -ne 2 -or $capturedFiles[0].filename -ne 'first.go' -or $capturedFiles[1].filename -ne 'second.go') {
                throw 'Get-PullRequestFiles did not preserve the mocked file collection'
            }
        }
        catch {
            $lifecycleIssues.Add("pair creation must return captured pull request files as a cross-platform object array: $($_.Exception.Message)")
        }
    }
    if (Test-Path -LiteralPath $reviewPullRequestImporterPath -PathType Leaf) {
        $importerContent = Get-Content -LiteralPath $reviewPullRequestImporterPath -Raw
        if ($importerContent -notmatch '\$PullRequest' -or $importerContent -notmatch '\$SourceRepository' -or $importerContent -notmatch '\$TestContentBase' -or $importerContent -notmatch 'New-ReviewPair\.ps1' -or $importerContent -notmatch 'application/vnd\.github\.v3\.diff') {
            $lifecycleIssues.Add('pull request import must materialize an upstream diff as a test-content source PR and delegate mirror creation')
        }
    }
    if (Test-Path -LiteralPath $reviewTestCasePublisherPath -PathType Leaf) {
        $publisherContent = Get-Content -LiteralPath $reviewTestCasePublisherPath -Raw
        if ($publisherContent -notmatch '\$CaseId' -or $publisherContent -notmatch 'contentRoot' -or $publisherContent -notmatch '\$TestContentBase' -or $publisherContent -notmatch 'New-ReviewPair\.ps1') {
            $lifecycleIssues.Add('test-case publishing must materialize a content tree as a test-content source PR and delegate mirror creation')
        }
    }
    if (Test-Path -LiteralPath $reviewPairCloserPath -PathType Leaf) {
        $closerContent = Get-Content -LiteralPath $reviewPairCloserPath -Raw
        if ($closerContent -notmatch '\[switch\]\$Close' -or $closerContent -notmatch 'AllowMissingCapture' -or $closerContent -notmatch 'Assert-HostedReviewWritableFork') {
            $lifecycleIssues.Add('pair cleanup must require Close, preserve its missing-capture override, and enforce the writable-fork guard')
        }
    }
    if (Test-Path -LiteralPath $reviewCommonModulePath -PathType Leaf) {
        $moduleContent = Get-Content -LiteralPath $reviewCommonModulePath -Raw
        if ($moduleContent -notmatch 'hashicorp/terraform-provider-azurerm' -or $moduleContent -notmatch 'Export-ModuleMember') {
            $lifecycleIssues.Add('lifecycle module must enforce canonical provider lineage and export an explicit public surface')
        }
    }
    if ($lifecycleIssues.Count -eq 0) {
        Add-CheckResult -Name 'lifecycle-tools' -Passed $true -Detail 'Hosted experiment lifecycle commands parse and preserve explicit mutation and cleanup gates.'
    }
    else {
        Add-ValidationIssue -Name 'lifecycle-tools' -Issue ($lifecycleIssues -join '; ')
    }

    Start-ValidationCheck -Name 'instruction-frontmatter'
    $instructionExpectations = @(
        @{ Path = $goInstructionsPath; ApplyTo = 'internal/**/*.go'; Name = 'Go' },
        @{ Path = $testInstructionsPath; ApplyTo = 'internal/**/*_test.go'; Name = 'Test' },
        @{ Path = $documentationInstructionsPath; ApplyTo = 'website/docs/**/*.html.markdown'; Name = 'Documentation' }
    )
    $frontmatterIssues = New-Object 'System.Collections.Generic.List[string]'
    foreach ($expectation in $instructionExpectations) {
        if (-not (Test-Path -LiteralPath $expectation.Path -PathType Leaf)) {
            $frontmatterIssues.Add("$($expectation.Name) instructions are missing")
            continue
        }
        $instructionContent = Get-Content -LiteralPath $expectation.Path -Raw
        if ($instructionContent -notmatch '(?s)\A---\r?\n(?<frontmatter>.*?)\r?\n---\r?\n') {
            $frontmatterIssues.Add("$($expectation.Name) instruction frontmatter is invalid")
            continue
        }
        $frontmatter = $matches['frontmatter']
        $escapedApplyTo = [regex]::Escape($expectation.ApplyTo)
        if ($frontmatter -notmatch '(?m)^description:\s*".+"\s*$' -or $frontmatter -notmatch "(?m)^applyTo:\s*`"$escapedApplyTo`"\s*$") {
            $frontmatterIssues.Add("$($expectation.Name) instructions do not define description and applyTo $($expectation.ApplyTo)")
        }
    }
    if ($frontmatterIssues.Count -eq 0) {
        Add-CheckResult -Name 'instruction-frontmatter' -Passed $true -Detail 'Go, test, and documentation instructions use their exact applyTo patterns and define descriptions.'
    }
    else {
        Add-ValidationIssue -Name 'instruction-frontmatter' -Issue ($frontmatterIssues -join '; ')
    }

    Start-ValidationCheck -Name 'instruction-boundaries'
    if ((Test-Path -LiteralPath $goInstructionsPath -PathType Leaf) -and (Test-Path -LiteralPath $testInstructionsPath -PathType Leaf)) {
        $goInstructionContent = Get-Content -LiteralPath $goInstructionsPath -Raw
        $testInstructionContent = Get-Content -LiteralPath $testInstructionsPath -Raw
        $goRuleIds = @([regex]::Matches($goInstructionContent, '\[(?<id>IMPL-[A-Z0-9-]+)\]') | ForEach-Object { $_.Groups['id'].Value })
        $testRuleIds = @([regex]::Matches($testInstructionContent, '\[(?<id>TEST-[A-Z0-9-]+)\]') | ForEach-Object { $_.Groups['id'].Value })
        $duplicateRuleIds = @((@($goRuleIds) + @($testRuleIds)) | Group-Object | Where-Object Count -gt 1)
        $boundaryIssues = New-Object 'System.Collections.Generic.List[string]'
        if ($testInstructionContent -match '\[IMPL-') {
            $boundaryIssues.Add('test instructions contain shared IMPL rule IDs')
        }
        if ($goInstructionContent -match '\[TEST-') {
            $boundaryIssues.Add('Go instructions contain test-specific TEST rule IDs')
        }
        if ($duplicateRuleIds.Count -gt 0) {
            $boundaryIssues.Add("duplicate stable rule IDs: $(@($duplicateRuleIds.Name) -join ', ')")
        }
        if ($goRuleIds.Count -eq 0 -or $testRuleIds.Count -eq 0) {
            $boundaryIssues.Add('Go or test instructions do not define stable rules')
        }

        if ($boundaryIssues.Count -eq 0) {
            Add-CheckResult -Name 'instruction-boundaries' -Passed $true -Detail "Go and test rule namespaces are exclusive and contain $($goRuleIds.Count + $testRuleIds.Count) unique stable IDs."
        }
        else {
            Add-ValidationIssue -Name 'instruction-boundaries' -Issue ($boundaryIssues -join '; ')
        }
    }
    else {
        Add-ValidationIssue -Name 'instruction-boundaries' -Issue 'Instruction boundary validation requires Go and test instructions'
    }

    Start-ValidationCheck -Name 'instruction-catalog'
    try {
        $generationOutput = @(& pwsh -NoProfile -File $instructionGeneratorPath -OutputFormat Json 2>&1)
        if ($LASTEXITCODE -ne 0) {
            throw (($generationOutput | Out-String).Trim())
        }
        $generationResult = ($generationOutput | Out-String) | ConvertFrom-Json
        if (-not $generationResult.success) {
            throw 'instruction generator reported stale outputs'
        }
        Add-CheckResult -Name 'instruction-catalog' -Passed $true -Detail "Validated $($generationResult.activeRuleCount) active normalized rules and byte-identical generated instructions."
    }
    catch {
        Add-ValidationIssue -Name 'instruction-catalog' -Issue "Hosted instruction catalog or generated outputs are invalid: $($_.Exception.Message)"
    }

    Start-ValidationCheck -Name 'instruction-generation-tests'
    try {
        $generationTestOutput = @(& pwsh -NoProfile -File $instructionGenerationTestPath -OutputFormat Json 2>&1)
        if ($LASTEXITCODE -ne 0) {
            throw (($generationTestOutput | Out-String).Trim())
        }
        $generationTestResult = ($generationTestOutput | Out-String) | ConvertFrom-Json
        if ($generationTestResult.status -ne 'passed') {
            throw 'instruction generation regression suite reported failures'
        }
        Add-CheckResult -Name 'instruction-generation-tests' -Passed $true -Detail "Passed $($generationTestResult.testCount) deterministic generation behavior tests."
    }
    catch {
        Add-ValidationIssue -Name 'instruction-generation-tests' -Issue "Hosted instruction generation regression failed: $($_.Exception.Message)"
    }

    Start-ValidationCheck -Name 'rule-intake-contracts'
    try {
        $ledgerContent = Get-Content -LiteralPath $intakeLedgerPath -Raw
        if (-not ($ledgerContent | Test-Json -SchemaFile $intakeLedgerSchemaPath -ErrorAction Stop)) {
            throw 'Interactive intake ledger schema validation failed'
        }
        $ledger = $ledgerContent | ConvertFrom-Json
        $duplicateDecisionIds = @($ledger.decisions | Group-Object sourceRuleId | Where-Object Count -gt 1)
        if ($duplicateDecisionIds.Count -gt 0) {
            throw "Interactive intake ledger contains duplicate source rule IDs: $(@($duplicateDecisionIds.Name) -join ', ')"
        }

        $hostedRuleIds = @((Get-Content -LiteralPath $instructionCatalogPath -Raw | ConvertFrom-Json).rules | ForEach-Object { [string]$_.id })
        $unknownHostedRuleIds = @($ledger.decisions | ForEach-Object { $_.hostedRuleIds } | Where-Object { $_ -notin $hostedRuleIds } | Sort-Object -Unique)
        if ($unknownHostedRuleIds.Count -gt 0) {
            throw "Interactive intake ledger references unknown Hosted rule IDs: $($unknownHostedRuleIds -join ', ')"
        }

        $intakeTestOutput = @(& pwsh -NoProfile -File $ruleIntakeTestPath -OutputFormat Json 2>&1)
        if ($LASTEXITCODE -ne 0) {
            throw (($intakeTestOutput | Out-String).Trim())
        }
        $intakeTestResult = ($intakeTestOutput | Out-String) | ConvertFrom-Json
        if ($intakeTestResult.status -ne 'passed') {
            throw 'rule intake regression suite reported failures'
        }
        $missingMaintainerRulePaths = @($maintainerRulePaths | Where-Object { -not (Test-Path -LiteralPath $_ -PathType Leaf) })
        if ($missingMaintainerRulePaths.Count -gt 0) {
            throw "Maintainer rule sources are missing: $($missingMaintainerRulePaths -join ', ')"
        }
        $deployedMaintainerRulePaths = @($manifestConfig.files | Where-Object { $_ -like 'copilot-rule-catalog/maintainer-rules/*' })
        if ($deployedMaintainerRulePaths.Count -gt 0) {
            throw "Maintainer rule sources must not be deployed: $($deployedMaintainerRulePaths -join ', ')"
        }

        $receiptCount = 0
        $receiptPlanHashes = New-Object 'System.Collections.Generic.List[string]'
        if (Test-Path -LiteralPath $promotionAuditPath -PathType Container) {
            foreach ($receiptPath in @(Get-ChildItem -LiteralPath $promotionAuditPath -Filter '*.json' -File)) {
                $receiptContent = Get-Content -LiteralPath $receiptPath.FullName -Raw
                if (-not ($receiptContent | Test-Json -SchemaFile $promotionReceiptSchemaPath -ErrorAction Stop)) {
                    throw "Promotion receipt schema validation failed: $($receiptPath.Name)"
                }
                $receipt = $receiptContent | ConvertFrom-Json
                $expectedSuffix = "-$($receipt.planSha256).json"
                if (-not $receiptPath.Name.EndsWith($expectedSuffix, [StringComparison]::Ordinal)) {
                    throw "Promotion receipt filename does not end with its plan hash: $($receiptPath.Name)"
                }
                $receiptPlanHashes.Add([string]$receipt.planSha256)
                $receiptCount++
            }
        }
        $duplicateReceiptHashes = @($receiptPlanHashes | Group-Object | Where-Object Count -gt 1)
        if ($duplicateReceiptHashes.Count -gt 0) {
            throw "Promotion audit contains duplicate plan hashes: $(@($duplicateReceiptHashes.Name) -join ', ')"
        }

        Add-CheckResult -Name 'rule-intake-contracts' -Passed $true -Detail "Validated the source-pinned ledger, three source-only Maintainer Proposal files, $($intakeTestResult.testCount) contract tests, and $receiptCount append-only promotion receipts without comparing Interactive freshness."
    }
    catch {
        Add-ValidationIssue -Name 'rule-intake-contracts' -Issue "Hosted rule intake contracts are invalid: $($_.Exception.Message)"
    }

    Start-ValidationCheck -Name 'rule-intake-assessment'
    try {
        $assessmentBaselineContent = Get-Content -LiteralPath $assessmentBaselinePath -Raw
        if (-not ($assessmentBaselineContent | Test-Json -SchemaFile $assessmentBaselineSchemaPath -ErrorAction Stop)) {
            throw 'committed assessment baseline schema validation failed'
        }
        $assessmentBaseline = $assessmentBaselineContent | ConvertFrom-Json
        $instructionCatalogSha256 = (Get-FileHash -LiteralPath $instructionCatalogPath -Algorithm SHA256).Hash.ToLowerInvariant()
        if ($assessmentBaseline.hostedCatalogSha256 -ne $instructionCatalogSha256) {
            throw 'committed assessment baseline does not target the current Hosted instruction catalog'
        }
        $baselineIdentities = @($assessmentBaseline.entries | ForEach-Object { "$($_.sourceType):$($_.id)" })
        if (@($baselineIdentities | Sort-Object -Unique).Count -ne $baselineIdentities.Count) {
            throw 'committed assessment baseline contains duplicate candidate identities'
        }
        $staleBaselineEntries = @($assessmentBaseline.entries | Where-Object { $_.sourceContentSha256 -ne $_.assessment.sourceContentSha256 })
        if ($staleBaselineEntries.Count -gt 0) {
            throw 'committed assessment baseline contains source-hash mismatches'
        }

        $assessmentTestOutput = @(& pwsh -NoProfile -File $ruleIntakeAssessmentTestPath -OutputFormat Json 2>&1)
        if ($LASTEXITCODE -ne 0) {
            throw (($assessmentTestOutput | Out-String).Trim())
        }
        $assessmentTestResult = ($assessmentTestOutput | Out-String) | ConvertFrom-Json
        if ($assessmentTestResult.status -ne 'passed') {
            throw 'rule intake assessment regression suite reported failures'
        }
        Add-CheckResult -Name 'rule-intake-assessment' -Passed $true -Detail "Validated $($assessmentBaseline.entries.Count) committed baseline entries and passed $($assessmentTestResult.testCount) publication, shared reuse, incremental cache, changed-rule invalidation, evaluator retry, schema, and output-boundary tests without model calls."
    }
    catch {
        Add-ValidationIssue -Name 'rule-intake-assessment' -Issue "Hosted rule intake assessment validation failed: $($_.Exception.Message)"
    }

    Start-ValidationCheck -Name 'rule-workbench'
    try {
        $workbenchTestOutput = @(& pwsh -NoProfile -File $ruleWorkbenchTestPath -OutputFormat Json 2>&1)
        if ($LASTEXITCODE -ne 0) {
            throw (($workbenchTestOutput | Out-String).Trim())
        }
        $workbenchTestResult = ($workbenchTestOutput | Out-String) | ConvertFrom-Json
        if ($workbenchTestResult.status -ne 'passed') {
            throw 'rule Workbench regression suite reported failures'
        }
        Add-CheckResult -Name 'rule-workbench' -Passed $true -Detail "Passed $($workbenchTestResult.testCount) static Workbench, browser-state, external-staging, and loopback read-only server tests."
    }
    catch {
        Add-ValidationIssue -Name 'rule-workbench' -Issue "Hosted Rule Workbench validation failed: $($_.Exception.Message)"
    }

    if ($SkipUpstreamDrift) {
        Add-SkippedCheck -Name 'upstream-sources' -Detail 'Hosted upstream source drift validation was explicitly skipped.'
    }
    else {
        Start-ValidationCheck -Name 'upstream-sources'
        try {
            $catalogHashBeforeDriftCheck = Get-Sha256Hash -Path $instructionCatalogPath
            $upstreamOutput = @(& pwsh -NoProfile -File $upstreamSourceValidatorPath -FailOnDrift -OutputFormat Json 2>&1)
            $catalogHashAfterDriftCheck = Get-Sha256Hash -Path $instructionCatalogPath
            if ($LASTEXITCODE -ne 0) {
                throw (($upstreamOutput | Out-String).Trim())
            }
            $upstreamResult = ($upstreamOutput | Out-String) | ConvertFrom-Json
            if (-not $upstreamResult.success -or $upstreamResult.updatesCatalog -or $catalogHashBeforeDriftCheck -ne $catalogHashAfterDriftCheck) {
                throw 'upstream source validator did not preserve its read-only success contract'
            }
            $catalogSourceIds = @((Get-Content -LiteralPath $instructionCatalogPath -Raw | ConvertFrom-Json).sources | ForEach-Object { [string]$_.id } | Sort-Object)
            $checkedSourceIds = @($upstreamResult.sources | ForEach-Object { [string]$_.id } | Sort-Object)
            if (@(Compare-Object -ReferenceObject $catalogSourceIds -DifferenceObject $checkedSourceIds).Count -gt 0) {
                throw 'upstream source validator did not check every Hosted catalog source'
            }
            Add-CheckResult -Name 'upstream-sources' -Passed $true -Detail "Validated all $($upstreamResult.sourceCount) Hosted-owned contributor sources and $($upstreamResult.discoveredTopicCount) discovered topics with zero drift and no catalog mutation."
        }
        catch {
            Add-ValidationIssue -Name 'upstream-sources' -Issue "Hosted upstream source validation failed: $($_.Exception.Message)"
        }
    }

    Start-ValidationCheck -Name 'skill-metadata'
    if (Test-Path -LiteralPath $reviewSkillPath -PathType Leaf) {
        $skillContent = Get-Content -LiteralPath $reviewSkillPath -Raw
        $skillMetadataValid = $skillContent -match '(?s)\A---\r?\n(?<frontmatter>.*?)\r?\n---\r?\n'
        if ($skillMetadataValid) {
            $skillFrontmatter = $matches['frontmatter']
            $skillMetadataValid = $skillFrontmatter -match '(?m)^name:\s*code-review\s*$' -and $skillFrontmatter -match '(?m)^description:\s*".*review.*"\s*$'
        }
        if ($skillMetadataValid) {
            Add-CheckResult -Name 'skill-metadata' -Passed $true -Detail 'Review skill metadata has the required name and review-focused description.'
        }
        else {
            Add-ValidationIssue -Name 'skill-metadata' -Issue 'Review skill metadata must define name code-review and a review-focused description'
        }
    }
    else {
        Add-ValidationIssue -Name 'skill-metadata' -Issue "Review skill was not found at $reviewSkillPath"
    }

    if ($null -ne $manifestConfig) {
        Start-ValidationCheck -Name 'manifest-coverage'
        $requiredOwnedPaths = @(
            Get-ChildItem -LiteralPath $hostedRuntimePath -Recurse -File | ForEach-Object {
                [System.IO.Path]::GetRelativePath($hostedRoot, $_.FullName).Replace('\', '/')
            }
        ) + @('docs/HOSTED_COPILOT_CODE_REVIEW.md')
        $manifestPaths = @($manifestConfig.files | ForEach-Object { ([string]$_).Replace('\', '/') })
        $missingOwnedPaths = @($requiredOwnedPaths | Where-Object { $_ -notin $manifestPaths })
        $unexpectedOwnedPaths = @($manifestPaths | Where-Object { $_ -notin $requiredOwnedPaths })
        $duplicatePaths = @($manifestPaths | Group-Object | Where-Object Count -gt 1)
        if ($missingOwnedPaths.Count -eq 0 -and $unexpectedOwnedPaths.Count -eq 0 -and $duplicatePaths.Count -eq 0) {
            Add-CheckResult -Name 'manifest-coverage' -Passed $true -Detail "Manifest owns all $($requiredOwnedPaths.Count) deployable runtime and user-documentation files."
        }
        else {
            Add-ValidationIssue -Name 'manifest-coverage' -Issue ("Manifest coverage mismatch: missing={0}; unexpected={1}; duplicatePaths={2}" -f ($missingOwnedPaths -join ', '), ($unexpectedOwnedPaths -join ', '), $duplicatePaths.Count)
        }

        Start-ValidationCheck -Name 'manifest-sources'
        $sourceIssues = New-Object 'System.Collections.Generic.List[string]'
        foreach ($file in @($manifestConfig.files)) {
            $manifestRelativePath = ([string]$file).Replace('/', [System.IO.Path]::DirectorySeparatorChar)
            $sourcePath = [System.IO.Path]::GetFullPath((Join-Path $hostedRoot $manifestRelativePath))
            $hostedPrefix = $hostedRoot.TrimEnd([System.IO.Path]::DirectorySeparatorChar) + [System.IO.Path]::DirectorySeparatorChar
            if (-not $sourcePath.StartsWith($hostedPrefix, [System.StringComparison]::OrdinalIgnoreCase)) {
                $sourceIssues.Add("manifest path escapes hosted_copilot: $file")
                continue
            }
            if (-not (Test-Path -LiteralPath $sourcePath -PathType Leaf)) {
                $sourceIssues.Add("manifest source file is missing: $file")
                continue
            }
            $null = Get-Sha256Hash -Path $sourcePath
        }
        if ($sourceIssues.Count -eq 0) {
            Add-CheckResult -Name 'manifest-sources' -Passed $true -Detail 'Every manifest path is contained, present, and hashable at deployment time.'
        }
        else {
            Add-ValidationIssue -Name 'manifest-sources' -Issue ($sourceIssues -join '; ')
        }
    }
    else {
        Add-SkippedCheck -Name 'manifest-coverage' -Detail 'Manifest coverage requires a valid package manifest.'
        Add-SkippedCheck -Name 'manifest-sources' -Detail 'Manifest source validation requires a valid package manifest.'
    }

    Start-ValidationCheck -Name 'guidance-budgets'
    if ((Test-Path -LiteralPath $repositoryInstructionsPath) -and (Test-Path -LiteralPath $goInstructionsPath) -and (Test-Path -LiteralPath $testInstructionsPath) -and (Test-Path -LiteralPath $documentationInstructionsPath) -and (Test-Path -LiteralPath $reviewSkillPath)) {
        try {
            $capacityOutput = @(& pwsh -NoProfile -File $guidanceCapacityPath -HostedRoot $hostedRoot -OutputFormat Json 2>&1)
            if ($LASTEXITCODE -ne 0) {
                throw (($capacityOutput | Out-String).Trim())
            }
            $tokenCapacityResult = ($capacityOutput | Out-String) | ConvertFrom-Json
            $expectedCapacityNames = @('repository', 'go', 'test', 'documentation', 'skill', 'go-combined', 'test-combined', 'documentation-combined') | Sort-Object
            $actualCapacityNames = @($tokenCapacityResult.reports | ForEach-Object { [string]$_.name } | Sort-Object)
            if ($tokenCapacityResult.status -ne 'passed' -or $tokenCapacityResult.estimator -ne $tokenEstimator -or @(Compare-Object $expectedCapacityNames $actualCapacityNames).Count -gt 0) {
                throw 'guidance capacity command returned an invalid report set'
            }
            foreach ($report in @($tokenCapacityResult.reports)) {
                if ($report.budgetHeadroomTokens -ne ($report.budgetTokens - $report.guardedTokens) -or $report.withinBudget -ne ($report.guardedTokens -le $report.budgetTokens)) {
                    throw "guidance capacity arithmetic is invalid for $($report.name)"
                }
            }
            $capacityDetails = @($tokenCapacityResult.reports | ForEach-Object { "$($_.name)=$($_.guardedTokens)/$($_.budgetTokens)/$($_.budgetHeadroomTokens)" })
            $budgetDetail = "$tokenEstimator guarded/budget/headroom tokens: $($capacityDetails -join '; ')"
            Add-CheckResult -Name 'guidance-budgets' -Passed $true -Detail $budgetDetail
        }
        catch {
            Add-ValidationIssue -Name 'guidance-budgets' -Issue "Hosted guidance capacity validation failed: $($_.Exception.Message)"
        }
    }
    else {
        Add-ValidationIssue -Name 'guidance-budgets' -Issue 'Hosted guidance budgets require all runtime guidance files'
    }

    Start-ValidationCheck -Name 'installer-dry-run'
    if ((Test-Path -LiteralPath $installerPath -PathType Leaf) -and $null -ne $manifestConfig) {
        $tempRepo = Join-Path ([System.IO.Path]::GetTempPath()) ("hosted-toolkit-validation-" + [guid]::NewGuid().ToString('N'))
        try {
            $null = New-Item -ItemType Directory -Path $tempRepo
            $gitCommand = Get-Command git -ErrorAction SilentlyContinue
            if ($null -eq $gitCommand) {
                throw 'git was not found on PATH'
            }
            & $gitCommand.Source -C $tempRepo init --quiet
            if ($LASTEXITCODE -ne 0) {
                throw 'temporary Git repository initialization failed'
            }
            $dryRunOutput = @(& pwsh -NoProfile -File $installerPath -RepoDirectory $tempRepo -OutputFormat Json 2>&1)
            if ($LASTEXITCODE -ne 0) {
                throw (($dryRunOutput | Out-String).Trim())
            }
            $dryRunResult = ($dryRunOutput | Out-String) | ConvertFrom-Json
            if (-not $dryRunResult.success -or $dryRunResult.mode -ne 'dry-run') {
                throw 'installer did not report a successful dry run'
            }
            if (@(Get-ChildItem -LiteralPath $tempRepo -Force | Where-Object Name -ne '.git').Count -ne 0) {
                throw 'installer dry run wrote files to the target repository'
            }
            Add-CheckResult -Name 'installer-dry-run' -Passed $true -Detail 'Installer dry run planned Hosted additions without writing to a temporary target.'
        }
        catch {
            Add-ValidationIssue -Name 'installer-dry-run' -Issue "Hosted installer dry run failed: $($_.Exception.Message)"
        }
        finally {
            if (Test-Path -LiteralPath $tempRepo) {
                Remove-Item -LiteralPath $tempRepo -Recurse -Force
            }
            $global:LASTEXITCODE = 0
        }
    }
    else {
        Add-ValidationIssue -Name 'installer-dry-run' -Issue 'Installer dry-run validation requires the installer and a valid package manifest'
    }

    Start-ValidationCheck -Name 'regression-cases'
    try {
        if (-not (Test-Path -LiteralPath $regressionCasesPath -PathType Container)) {
            throw "regression cases directory is missing: $regressionCasesPath"
        }

        $caseConfigPaths = @(Get-ChildItem -LiteralPath $regressionCasesPath -Filter 'case.json' -Recurse -File)
        if ($caseConfigPaths.Count -eq 0) {
            throw 'no regression case.json files were found'
        }

        $surfaceInstructionPaths = @{
            documentation = $documentationInstructionsPath
            implementation = $goInstructionsPath
            testing = $testInstructionsPath
        }
        $caseIds = @{}
        $expectedFindingCount = 0
        $caseFileCount = 0

        foreach ($caseConfigPath in $caseConfigPaths) {
            $caseRoot = Split-Path -Parent $caseConfigPath.FullName
            $caseConfig = Get-Content -LiteralPath $caseConfigPath.FullName -Raw | ConvertFrom-Json
            $caseId = [string]$caseConfig.id

            if ($caseConfig.schemaVersion -ne 1 -or [string]::IsNullOrWhiteSpace($caseId)) {
                throw "case schemaVersion or id is invalid: $($caseConfigPath.FullName)"
            }
            if ($caseIds.ContainsKey($caseId)) {
                throw "duplicate regression case id: $caseId"
            }
            $caseIds[$caseId] = $true

            foreach ($legacyProperty in @('surface', 'targetPath', 'contentPath', 'beforePath', 'afterPath')) {
                if ($null -ne $caseConfig.PSObject.Properties[$legacyProperty]) {
                    throw "case $caseId must use contentRoot instead of legacy property $legacyProperty"
                }
            }
            foreach ($legacyDirectoryName in @('before', 'after')) {
                $legacyDirectory = Join-Path $caseRoot $legacyDirectoryName
                if (Test-Path -LiteralPath $legacyDirectory -PathType Container) {
                    throw "case $caseId contains legacy directory: $legacyDirectoryName"
                }
            }
            $contentRoot = [System.IO.Path]::GetFullPath((Join-Path $caseRoot ([string]$caseConfig.contentRoot)))
            $caseRootPrefix = $caseRoot.TrimEnd([System.IO.Path]::DirectorySeparatorChar) + [System.IO.Path]::DirectorySeparatorChar
            if (-not $contentRoot.StartsWith($caseRootPrefix, [System.StringComparison]::OrdinalIgnoreCase)) {
                throw "case $caseId contentRoot escapes its case directory"
            }
            if (-not (Test-Path -LiteralPath $contentRoot -PathType Container)) {
                throw "case $caseId contentRoot is missing"
            }
            $contentFiles = @(Get-ChildItem -LiteralPath $contentRoot -File -Recurse)
            if ($contentFiles.Count -eq 0) {
                throw "case $caseId contentRoot is empty"
            }
            $contentByPath = @{}
            foreach ($contentFile in $contentFiles) {
                $relativePath = [System.IO.Path]::GetRelativePath($contentRoot, $contentFile.FullName).Replace('\', '/')
                if ($relativePath -match '^\.github(?:/|$)') {
                    throw "case $caseId must not modify review customization or workflows: $relativePath"
                }
                $contentByPath[$relativePath] = $contentFile.FullName
            }

            $expectedFindings = @($caseConfig.expectedFindings)
            if ($expectedFindings.Count -eq 0) {
                throw "case $caseId expectedFindings is empty"
            }

            foreach ($expectedFinding in $expectedFindings) {
                $ruleId = [string]$expectedFinding.ruleId
                $findingPath = ([string]$expectedFinding.path).Replace('\', '/')
                $matchText = [string]$expectedFinding.match
                if ([string]::IsNullOrWhiteSpace($ruleId) -or [string]::IsNullOrWhiteSpace($findingPath) -or [string]::IsNullOrWhiteSpace($matchText) -or [string]::IsNullOrWhiteSpace([string]$expectedFinding.reason)) {
                    throw "case $caseId contains an incomplete expected finding"
                }
                if (-not $contentByPath.ContainsKey($findingPath)) {
                    throw "case $caseId expected finding path is not present below contentRoot: $findingPath"
                }
                $surface = if ($findingPath -match '^website/docs/.+\.html\.markdown$') {
                    'documentation'
                }
                elseif ($findingPath -match '^internal/.+_test\.go$') {
                    'testing'
                }
                elseif ($findingPath -match '^internal/.+\.go$') {
                    'implementation'
                }
                else {
                    throw "case $caseId cannot derive a review surface for expected finding path: $findingPath"
                }
                $ruleContent = Get-Content -LiteralPath $surfaceInstructionPaths[$surface] -Raw
                if (-not $ruleContent.Contains("[$ruleId]")) {
                    throw "case $caseId references unknown Hosted $surface rule $ruleId"
                }
                $content = Get-Content -LiteralPath $contentByPath[$findingPath] -Raw
                if (-not $content.Contains($matchText)) {
                    throw "case $caseId expected match must appear in ${findingPath}: $matchText"
                }
            }

            $expectedFindingCount += $expectedFindings.Count
            $caseFileCount += $contentFiles.Count
        }

        Add-CheckResult -Name 'regression-cases' -Passed $true -Detail "Discovered $($caseConfigPaths.Count) regression cases with $caseFileCount content files and $expectedFindingCount expected findings."
    }
    catch {
        Add-ValidationIssue -Name 'regression-cases' -Issue "Controlled regression cases are invalid: $($_.Exception.Message)"
    }

    Start-ValidationCheck -Name 'review-results'
    try {
        $reviewResultSchema = Get-Content -LiteralPath $reviewResultSchemaPath -Raw | ConvertFrom-Json
        $schemaReviewEffortValues = @($reviewResultSchema.'$defs'.profileResult.properties.reviewEffort.enum | Sort-Object -Unique)
        if (($schemaReviewEffortValues -join ',') -ne 'Balanced,Lite') {
            throw "paired review result schema must accept exactly Lite and Balanced review effort levels, found $($schemaReviewEffortValues -join ', ')"
        }
        $global:LASTEXITCODE = 0
        $reviewResultOutput = @(& $reviewResultValidatorPath -OutputFormat Json 2>&1)
        $reviewResultExitCode = if ($null -ne $LASTEXITCODE) { $LASTEXITCODE } else { 0 }
        if ($reviewResultExitCode -ne 0) {
            throw (($reviewResultOutput | Out-String).Trim())
        }
        $reviewResult = ($reviewResultOutput -join [Environment]::NewLine) | ConvertFrom-Json
        Add-CheckResult -Name 'review-results' -Passed $true -Detail "Validated $($reviewResult.resultCount) local paired review result records."
    }
    catch {
        Add-ValidationIssue -Name 'review-results' -Issue "Local paired review results are invalid: $($_.Exception.Message)"
    }

    Start-ValidationCheck -Name 'result-artifact-boundary'
    try {
        if (-not (Test-Path -LiteralPath $gitIgnorePath -PathType Leaf)) {
            throw '.gitignore is missing'
        }
        $gitIgnoreLines = @(Get-Content -LiteralPath $gitIgnorePath)
        $requiredIgnoreRules = @(
            'hosted_copilot/regression/raw/',
            'hosted_copilot/regression/results/'
        )
        $missingIgnoreRules = @($requiredIgnoreRules | Where-Object { $_ -notin $gitIgnoreLines })
        if ($missingIgnoreRules.Count -gt 0) {
            throw "missing ignore rules: $($missingIgnoreRules -join ', ')"
        }

        $gitCommand = Get-Command git -ErrorAction SilentlyContinue
        if ($null -eq $gitCommand) {
            throw 'git was not found on PATH'
        }
        $trackedArtifacts = @(& $gitCommand.Source -C $repoRoot ls-files -- 'hosted_copilot/regression/raw/**' 'hosted_copilot/regression/results/**')
        if ($LASTEXITCODE -ne 0) {
            throw 'git could not inspect tracked Hosted result artifacts'
        }
        if ($trackedArtifacts.Count -gt 0) {
            throw "generated result artifacts are tracked: $($trackedArtifacts -join ', ')"
        }
        Add-CheckResult -Name 'result-artifact-boundary' -Passed $true -Detail 'Raw captures and adjudicated result records are ignored and absent from tracked source.'
    }
    catch {
        Add-ValidationIssue -Name 'result-artifact-boundary' -Issue "Hosted result artifact boundary is invalid: $($_.Exception.Message)"
    }
}
else {
    foreach ($runtimeCheck in @('runtime-layout', 'lifecycle-tools', 'instruction-frontmatter', 'instruction-boundaries', 'instruction-catalog', 'instruction-generation-tests', 'rule-intake-contracts', 'rule-intake-assessment', 'rule-workbench', 'upstream-sources', 'skill-metadata', 'manifest-coverage', 'manifest-sources', 'guidance-budgets', 'installer-dry-run', 'regression-cases', 'review-results', 'result-artifact-boundary')) {
        Add-SkippedCheck -Name $runtimeCheck -Detail 'Runtime validation is not applicable during the design phase.'
    }
}

Start-ValidationCheck -Name 'isolation'
if (Test-Path -LiteralPath $interactiveManifestPath) {
    $interactiveManifestReferences = @(Get-Content -LiteralPath $interactiveManifestPath | Where-Object { $_ -match 'hosted_copilot' })
    if ($interactiveManifestReferences.Count -eq 0) {
        Add-CheckResult -Name 'isolation' -Passed $true -Detail 'Interactive Toolkit manifest does not reference Hosted Toolkit paths.'
    }
    else {
        Add-ValidationIssue -Name 'isolation' -Issue 'Interactive Toolkit manifest must not include Hosted Toolkit paths'
    }
}
else {
    Add-ValidationIssue -Name 'isolation' -Issue "Interactive Toolkit manifest was not found at $interactiveManifestPath"
}

if (Test-Path -LiteralPath $architecturePath) {
    Start-ValidationCheck -Name 'architecture-style'
    $architectureLines = Get-Content -LiteralPath $architecturePath
    $badHeadings = @($architectureLines | Where-Object { $_ -cmatch '^#{1,6}\s+.*[^:]$' })
    $badBullets = @($architectureLines | Where-Object { $_ -cmatch '^\s*-\s+[a-z]' })
    $badLabels = @($architectureLines | Where-Object { $_ -cmatch '^[A-Za-z\[].*:$' })

    if ($badHeadings.Count -eq 0 -and $badBullets.Count -eq 0 -and $badLabels.Count -eq 0) {
        Add-CheckResult -Name 'architecture-style' -Passed $true -Detail 'Architecture headings, labels, and bullet capitalization follow repository conventions.'
    }
    else {
        Add-ValidationIssue -Name 'architecture-style' -Issue ("Architecture style issues: headings={0}, lowercase bullets={1}, unbolded labels={2}" -f $badHeadings.Count, $badBullets.Count, $badLabels.Count)
    }
}
else {
    Add-SkippedCheck -Name 'architecture-style' -Detail 'Architecture style validation requires the architecture document.'
}

$npxCommand = Get-Command 'npx.cmd' -ErrorAction SilentlyContinue
if ($null -eq $npxCommand) {
    $npxCommand = Get-Command 'npx' -ErrorAction SilentlyContinue
}

if ($null -eq $npxCommand) {
    Start-ValidationCheck -Name 'markdown'
    Add-ValidationIssue -Name 'markdown' -Issue 'npx was not found on PATH'
}
else {
    Start-ValidationCheck -Name 'markdown'
    Push-Location $repoRoot
    try {
        $global:LASTEXITCODE = 0
        $markdownOutput = @(& $npxCommand.Source -y --prefer-offline markdownlint-cli2 'hosted_copilot/**/*.md' 'docs/HOSTED_COPILOT_CODE_REVIEW_ARCHITECTURE.md' --config '.github/.markdownlint.json' 2>&1)
        $markdownExitCode = if ($null -ne $LASTEXITCODE) { $LASTEXITCODE } else { 0 }
    }
    finally {
        Pop-Location
    }

    if ($markdownExitCode -eq 0) {
        Add-CheckResult -Name 'markdown' -Passed $true -Detail 'Hosted Toolkit Markdown passed markdownlint.'
    }
    else {
        Add-ValidationIssue -Name 'markdown' -Issue ("Hosted Toolkit Markdown failed markdownlint: {0}" -f (($markdownOutput | Out-String).Trim()))
    }
}

if ($null -eq $npxCommand) {
    Start-ValidationCheck -Name 'mermaid'
    Add-ValidationIssue -Name 'mermaid' -Issue 'npx was not found on PATH'
}
else {
    Start-ValidationCheck -Name 'mermaid'
    $mermaidTempPath = Join-Path ([System.IO.Path]::GetTempPath()) ("hosted-mermaid-validation-{0}" -f [Guid]::NewGuid().ToString('N'))

    try {
        New-Item -ItemType Directory -Path $mermaidTempPath | Out-Null
        $puppeteerConfigPath = Join-Path $mermaidTempPath 'puppeteer-config.json'
        $useLinuxCiPuppeteerConfig = $IsLinux -and $env:CI -eq 'true'
        if ($useLinuxCiPuppeteerConfig) {
            @{ args = @('--no-sandbox', '--disable-setuid-sandbox') } | ConvertTo-Json | Set-Content -LiteralPath $puppeteerConfigPath -Encoding utf8NoBOM
        }
        $markdownPaths = @(
            Get-ChildItem -LiteralPath $hostedRoot -Filter '*.md' -File -Recurse
            Get-Item -LiteralPath $architecturePath
        )
        $mermaidBlockCount = 0

        foreach ($markdownPath in $markdownPaths) {
            $markdownContent = Get-Content -LiteralPath $markdownPath.FullName -Raw
            $mermaidMatches = [regex]::Matches($markdownContent, '(?ms)^```mermaid\s*\r?\n(.*?)^```\s*$')

            foreach ($mermaidMatch in $mermaidMatches) {
                $mermaidBlockCount++
                $inputPath = Join-Path $mermaidTempPath ("diagram-{0}.mmd" -f $mermaidBlockCount)
                $outputPath = Join-Path $mermaidTempPath ("diagram-{0}.svg" -f $mermaidBlockCount)
                Set-Content -LiteralPath $inputPath -Value $mermaidMatch.Groups[1].Value -Encoding utf8NoBOM

                $global:LASTEXITCODE = 0
                $mermaidArguments = @('-y', '--prefer-offline', '-p', $mermaidCliPackage, '-p', $puppeteerPackage, 'mmdc', '-i', $inputPath, '-o', $outputPath, '-b', 'transparent')
                if ($useLinuxCiPuppeteerConfig) {
                    $mermaidArguments += @('--puppeteerConfigFile', $puppeteerConfigPath)
                }
                $mermaidOutput = @(& $npxCommand.Source @mermaidArguments 2>&1)
                $mermaidExitCode = if ($null -ne $LASTEXITCODE) { $LASTEXITCODE } else { 0 }
                if ($mermaidExitCode -ne 0) {
                    throw "Mermaid rendering failed for $($markdownPath.FullName): $((($mermaidOutput | Out-String).Trim()))"
                }
                if (-not (Test-Path -LiteralPath $outputPath) -or (Get-Item -LiteralPath $outputPath).Length -eq 0) {
                    throw "Mermaid rendering produced no SVG content for $($markdownPath.FullName)"
                }
            }
        }

        Add-CheckResult -Name 'mermaid' -Passed $true -Detail "Rendered $mermaidBlockCount Mermaid diagrams with $mermaidCliPackage and $puppeteerPackage."
    }
    catch {
        Add-ValidationIssue -Name 'mermaid' -Issue "Hosted Toolkit Mermaid validation failed: $($_.Exception.Message)"
    }
    finally {
        Remove-Item -LiteralPath $mermaidTempPath -Recurse -Force -ErrorAction SilentlyContinue
    }
}

$result = [ordered]@{
    status = if ($issues.Count -eq 0) { 'passed' } else { 'failed' }
    purpose = $purpose
    deploymentModel = $deploymentModel
    phase = $phase
    tokenEstimator = $tokenEstimator
    guidanceCapacity = $tokenCapacityResult
    repoRoot = $repoRoot
    hostedRoot = $hostedRoot
    checks = @($checks.ToArray())
    issueCount = $issues.Count
    issues = @($issues.ToArray())
}

if ($OutputFormat -eq 'Json') {
    $result | ConvertTo-Json -Depth 10
}
else {
    Write-ValidationSectionHeader -Title 'Hosted toolkit validation summary'
    Write-ValidationSummary -Fields ([ordered]@{
        Status = $result.status.ToUpperInvariant()
        Purpose = $result.purpose.ToUpperInvariant()
        Deployment = $result.deploymentModel.ToUpperInvariant()
        Phase = $result.phase.ToUpperInvariant()
        'Token Guard' = $result.tokenEstimator.ToUpperInvariant()
        'Hosted Root' = $result.hostedRoot
        'Issue Count' = $result.issueCount
    })

    Write-ValidationSectionHeader -Title 'Validation checks'
    Write-ValidationStatusTable -Rows $checks.ToArray()

    if ($issues.Count -gt 0) {
        Write-ValidationSectionHeader -Title 'Failures'
        foreach ($check in @($checks | Where-Object { -not $_.success })) {
            Write-Output ("  {0}" -f (Format-ValidationStatusLine -Status 'failed' -Name $check.name -Detail $check.detail))
        }
    }

    Complete-ValidationTextOutput
}

if ($issues.Count -gt 0) {
    exit 1
}
