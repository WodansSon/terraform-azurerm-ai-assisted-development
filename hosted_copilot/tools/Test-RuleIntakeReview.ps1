[CmdletBinding()]
param(
    [ValidateSet('Text', 'Json')]
    [string]$OutputFormat = 'Text'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$validationOutputModulePath = Join-Path $PSScriptRoot '../../tools/ValidationOutput.psm1'
Import-Module -Name $validationOutputModulePath -Force

$catalogRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../copilot-rule-catalog'))
$ledgerPath = Join-Path $catalogRoot 'interactive-intake-ledger.json'
$ledgerSchemaPath = Join-Path $catalogRoot 'interactive-intake-ledger.schema.json'
$planSchemaPath = Join-Path $catalogRoot 'promotion-plan.schema.json'
$receiptSchemaPath = Join-Path $catalogRoot 'promotion-receipt.schema.json'
$bundleSchemaPath = Join-Path $catalogRoot 'rule-intake-review.schema.json'
$bundleScriptPath = Join-Path $PSScriptRoot 'New-RuleIntakeReview.ps1'
$interactiveCatalogSchemaPath = Join-Path $PSScriptRoot '../../tools/interactive-rule-catalog/rule-catalog.schema.json'
$results = New-Object 'System.Collections.Generic.List[object]'
$issues = New-Object 'System.Collections.Generic.List[string]'

function Add-TestResult {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name,

        [Parameter(Mandatory = $true)]
        [bool]$Passed,

        [Parameter(Mandatory = $true)]
        [string]$Detail
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

function Test-JsonInstance {
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string]$Json,

        [Parameter(Mandatory = $true)]
        [string]$SchemaPath
    )

    try {
        return [bool]($Json | Test-Json -SchemaFile $SchemaPath -ErrorAction Stop)
    }
    catch {
        return $false
    }
}

function Copy-JsonObject {
    param([Parameter(Mandatory = $true)][object]$Value)

    return (($Value | ConvertTo-Json -Depth 30) | ConvertFrom-Json)
}

function Get-StringSha256 {
    param([Parameter(Mandatory = $true)][AllowEmptyString()][string]$Value)

    return [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData([Text.Encoding]::UTF8.GetBytes($Value))).ToLowerInvariant()
}

function Write-JsonFixture {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)]$Value
    )

    $directory = Split-Path -Parent $Path
    if (-not (Test-Path -LiteralPath $directory -PathType Container)) {
        $null = New-Item -ItemType Directory -Path $directory -Force
    }
    [IO.File]::WriteAllText($Path, ($Value | ConvertTo-Json -Depth 30) + "`n", [Text.UTF8Encoding]::new($false))
}

$hash = 'a' * 64
$otherHash = 'b' * 64
$gitHash = 'c' * 40
$timestamp = '2026-09-02T00:00:00Z'
$selectionFactors = [ordered]@{
    scoringStatus = 'scored'
    severity = 5
    frequency = 3
    breadth = 4
    hostedDetectability = 4
    evidenceStrength = 5
    falsePositiveRisk = 1
    redundancy = 0
}
$ledgerDecision = [ordered]@{
    sourceRuleId = 'IMPL-SCHEMA-099'
    sourceContractPath = '.github/instructions/implementation-compliance-contract.instructions.md'
    sourceContentSha256 = $hash
    sourceStatus = 'active'
    decision = 'included'
    rationale = 'The candidate prevents a high-impact state defect.'
    reviewedOn = '2026-09-02'
    hostedRuleIds = @('IMPL-SCHEMA-099')
    selectionFactors = $selectionFactors
    selectionRationale = 'The rule is broad, detectable, and supported by published evidence.'
    foundationalOverride = $null
}

try {
    $ledgerJson = Get-Content -LiteralPath $ledgerPath -Raw
    Add-TestResult -Name 'empty-ledger-valid' -Passed (Test-JsonInstance -Json $ledgerJson -SchemaPath $ledgerSchemaPath) -Detail 'The source-pinned empty intake ledger validates.'

    $ledgerWithDecision = [ordered]@{
        '$schema' = 'interactive-intake-ledger.schema.json'
        schemaVersion = 1
        sourceSnapshot = [ordered]@{
            catalogPath = 'tools/interactive-rule-catalog/rule-catalog.json'
            catalogSha256 = $hash
            capturedOn = '2026-09-02'
            ruleCount = 349
        }
        decisions = @($ledgerDecision)
    }
    $validLedgerJson = $ledgerWithDecision | ConvertTo-Json -Depth 30
    Add-TestResult -Name 'ledger-decision-valid' -Passed (Test-JsonInstance -Json $validLedgerJson -SchemaPath $ledgerSchemaPath) -Detail 'A fully attributed included decision validates.'

    $missingHostedMapping = Copy-JsonObject -Value $ledgerWithDecision
    $missingHostedMapping.decisions[0].hostedRuleIds = @()
    Add-TestResult -Name 'included-requires-hosted-mapping' -Passed (-not (Test-JsonInstance -Json ($missingHostedMapping | ConvertTo-Json -Depth 30) -SchemaPath $ledgerSchemaPath)) -Detail 'Included decisions without a Hosted rule mapping are rejected.'

    $invalidFactor = Copy-JsonObject -Value $ledgerWithDecision
    $invalidFactor.decisions[0].selectionFactors.severity = 6
    Add-TestResult -Name 'selection-factor-range' -Passed (-not (Test-JsonInstance -Json ($invalidFactor | ConvertTo-Json -Depth 30) -SchemaPath $ledgerSchemaPath)) -Detail 'Selection factors outside the zero-to-five range are rejected.'

    $targetRule = [ordered]@{
        id = 'IMPL-SCHEMA-099'
        origin = 'hosted-catalog-addition'
        status = 'active'
        text = 'Reject state mappings that cannot round-trip through the selected implementation model.'
        provenance = @('published-upstream-standard')
        sourceIds = @('schema-design-considerations')
        evidenceIds = @('implementation-contract')
        implementationModels = @('legacy', 'typed', 'framework')
        documentationGap = $false
        selectionFactors = $selectionFactors
        selectionRationale = 'The rule is broad, detectable, and supported by published evidence.'
        foundationalOverride = $null
    }
    $validPlan = [ordered]@{
        '$schema' = 'promotion-plan.schema.json'
        schemaVersion = 1
        planId = [Guid]::NewGuid().ToString()
        createdAt = $timestamp
        encoding = 'utf-8'
        hashAlgorithm = 'sha256-file-bytes-v1'
        preconditions = [ordered]@{
            branch = 'feat/hosted-copilot-review'
            headCommit = $gitHash
            catalogSha256 = $hash
            ledgerSha256 = $otherHash
            generatedOutputs = @([ordered]@{ path = 'hosted_copilot/.github/instructions/azurerm-go.instructions.md'; sha256 = $hash })
            sourceSnapshots = @([ordered]@{ kind = 'interactive-rule'; id = 'IMPL-SCHEMA-099'; sha256 = $hash })
        }
        ruleChanges = @([ordered]@{
            action = 'add'
            hostedRuleId = 'IMPL-SCHEMA-099'
            surfaceId = 'implementation'
            sectionHeading = 'Schema And State'
            sourceRefs = @('interactive:IMPL-SCHEMA-099')
            rationale = 'Add the approved state round-trip requirement.'
            targetRule = $targetRule
        })
        ledgerChanges = @($ledgerDecision)
        sourceBaselineChanges = @()
        regressionChanges = @([ordered]@{
            operation = 'add'
            path = 'hosted_copilot/regression/cases/implementation/state-round-trip/case.json'
            content = '{}'
            sha256 = $hash
        })
        preview = [ordered]@{
            generatedAt = $timestamp
            files = @([ordered]@{
                path = 'hosted_copilot/.github/instructions/azurerm-go.instructions.md'
                operation = 'update'
                beforeSha256 = $hash
                afterSha256 = $otherHash
                diff = '+ approved rule'
            })
            tokenReports = @([ordered]@{
                name = 'go-combined'
                estimatedTokens = 2100
                guardedTokens = 2625
                budgetTokens = 25000
                budgetHeadroomTokens = 22375
                utilizationPercent = 10.5
                estimatedTokenDelta = 74
                guardedTokenDelta = 91
            })
            validationStatus = 'passed'
            validationChecks = @('schema', 'generation', 'budget', 'regression')
        }
        approval = [ordered]@{
            state = 'approved'
            approvedAt = $timestamp
            approvedBy = [ordered]@{ type = 'manual'; id = 'maintainer'; displayName = 'Maintainer' }
            method = 'hosted-rule-workbench'
        }
    }
    $validPlanJson = $validPlan | ConvertTo-Json -Depth 30
    Add-TestResult -Name 'promotion-plan-valid' -Passed (Test-JsonInstance -Json $validPlanJson -SchemaPath $planSchemaPath) -Detail 'An approved staged promotion plan validates.'

    $invalidAddOrigin = Copy-JsonObject -Value $validPlan
    $invalidAddOrigin.ruleChanges[0].targetRule.origin = 'hosted-baseline-migration'
    Add-TestResult -Name 'addition-origin-required' -Passed (-not (Test-JsonInstance -Json ($invalidAddOrigin | ConvertTo-Json -Depth 30) -SchemaPath $planSchemaPath)) -Detail 'New rules cannot claim the migration-baseline origin.'

    $baselineRuleUpdate = Copy-JsonObject -Value $validPlan
    $baselineRuleUpdate.ruleChanges[0].action = 'update'
    $baselineRuleUpdate.ruleChanges[0].targetRule.origin = 'hosted-baseline-migration'
    Add-TestResult -Name 'update-preserves-origin' -Passed (Test-JsonInstance -Json ($baselineRuleUpdate | ConvertTo-Json -Depth 30) -SchemaPath $planSchemaPath) -Detail 'Updates can preserve the origin of a migrated baseline rule.'

    $pathTraversal = Copy-JsonObject -Value $validPlan
    $pathTraversal.regressionChanges[0].path = '../outside.json'
    Add-TestResult -Name 'plan-path-containment' -Passed (-not (Test-JsonInstance -Json ($pathTraversal | ConvertTo-Json -Depth 30) -SchemaPath $planSchemaPath)) -Detail 'Promotion content paths cannot escape the repository.'

    $validReceipt = [ordered]@{
        '$schema' = 'promotion-receipt.schema.json'
        schemaVersion = 1
        receiptId = [Guid]::NewGuid().ToString()
        planSha256 = $hash
        promotedAt = $timestamp
        approval = [ordered]@{
            approvedAt = $timestamp
            approvedBy = [ordered]@{ type = 'manual'; id = 'maintainer'; displayName = 'Maintainer' }
            method = 'hosted-rule-workbench'
        }
        appliedBy = [ordered]@{ type = 'git-config'; id = 'maintainer@example.com'; displayName = 'Maintainer' }
        sourceSnapshots = @([ordered]@{ kind = 'interactive-rule'; id = 'IMPL-SCHEMA-099'; sha256 = $hash })
        decisions = @([ordered]@{
            sourceRef = 'interactive:IMPL-SCHEMA-099'
            action = 'add'
            hostedRuleIds = @('IMPL-SCHEMA-099')
            sectionPlacement = 'implementation/Schema And State'
            selectionFactors = $selectionFactors
            selectionRationale = 'The rule is broad, detectable, and supported by published evidence.'
            foundationalOverride = $null
        })
        fileChanges = @([ordered]@{
            path = 'hosted_copilot/.github/instructions/azurerm-go.instructions.md'
            operation = 'update'
            beforeSha256 = $hash
            afterSha256 = $otherHash
        })
        tokenReports = @([ordered]@{
            name = 'go-combined'
            beforeGuardedTokens = 2534
            afterGuardedTokens = 2625
            budgetTokens = 25000
            budgetHeadroomTokens = 22375
            utilizationPercent = 10.5
        })
        regressionAssets = @('hosted_copilot/regression/cases/implementation/state-round-trip/case.json')
        validations = @([ordered]@{ name = 'Hosted Toolkit'; status = 'passed'; completedAt = $timestamp })
        outcome = 'success'
    }
    $validReceiptJson = $validReceipt | ConvertTo-Json -Depth 30
    Add-TestResult -Name 'promotion-receipt-valid' -Passed (Test-JsonInstance -Json $validReceiptJson -SchemaPath $receiptSchemaPath) -Detail 'A successful append-only promotion receipt validates.'

    $failedReceipt = Copy-JsonObject -Value $validReceipt
    $failedReceipt.outcome = 'failed'
    Add-TestResult -Name 'receipt-success-only' -Passed (-not (Test-JsonInstance -Json ($failedReceipt | ConvertTo-Json -Depth 30) -SchemaPath $receiptSchemaPath)) -Detail 'Failed promotions cannot be recorded as successful receipts.'

    $fixtureRoot = Join-Path ([IO.Path]::GetTempPath()) ("hosted-rule-intake-bundle-" + [guid]::NewGuid().ToString('N'))
    try {
        $fixtureCatalogRoot = Join-Path $fixtureRoot 'hosted_copilot/copilot-rule-catalog'
        $fixtureInteractiveCatalogRoot = Join-Path $fixtureRoot 'tools/interactive-rule-catalog'
        $fixtureContractPath = Join-Path $fixtureRoot '.github/instructions/implementation-compliance-contract.instructions.md'
        $fixtureBaselineRoot = Join-Path $fixtureRoot 'upstream-baseline'
        $fixtureCurrentRoot = Join-Path $fixtureRoot 'upstream-current'
        $fixtureBaselinePath = Join-Path $fixtureBaselineRoot 'contributing/README.md'
        $fixtureCurrentPath = Join-Path $fixtureCurrentRoot 'contributing/README.md'
        $fixtureRuntimeRoot = Join-Path $fixtureRoot 'hosted_copilot/.github'
        foreach ($directory in @($fixtureCatalogRoot, $fixtureInteractiveCatalogRoot, (Split-Path -Parent $fixtureContractPath), (Split-Path -Parent $fixtureBaselinePath), (Split-Path -Parent $fixtureCurrentPath), (Join-Path $fixtureRuntimeRoot 'instructions'), (Join-Path $fixtureRuntimeRoot 'skills/code-review'))) {
            $null = New-Item -ItemType Directory -Path $directory -Force
        }
        Copy-Item -LiteralPath (Join-Path $catalogRoot 'instruction-catalog.schema.json') -Destination $fixtureCatalogRoot
        Copy-Item -LiteralPath $ledgerSchemaPath -Destination $fixtureCatalogRoot
        Copy-Item -LiteralPath $bundleSchemaPath -Destination $fixtureCatalogRoot
        Copy-Item -LiteralPath $interactiveCatalogSchemaPath -Destination $fixtureInteractiveCatalogRoot

        $baselineContent = "# Contributor fixture`n"
        $currentContent = "# Contributor fixture`n`nChanged guidance.`n"
        [IO.File]::WriteAllText($fixtureBaselinePath, $baselineContent, [Text.UTF8Encoding]::new($false))
        [IO.File]::WriteAllText($fixtureCurrentPath, $currentContent, [Text.UTF8Encoding]::new($false))
        foreach ($runtimePath in @('copilot-instructions.md', 'instructions/azurerm-go.instructions.md', 'instructions/azurerm-tests.instructions.md', 'instructions/azurerm-docs.instructions.md', 'skills/code-review/SKILL.md')) {
            $content = "# Fixture $runtimePath`n"
            [IO.File]::WriteAllText((Join-Path $fixtureRuntimeRoot $runtimePath), $content, [Text.UTF8Encoding]::new($false))
        }

        $ruleBlocks = [ordered]@{
            'IMPL-TEST-001' = "### IMPL-TEST-001: New candidate`n`n- Rule: Review the new candidate."
            'IMPL-TEST-002' = "### IMPL-TEST-002: Changed candidate`n`n- Rule: Review the changed candidate."
            'IMPL-TEST-004' = "### IMPL-TEST-004: Deferred candidate`n`n- Rule: Review the deferred candidate."
            'IMPL-TEST-005' = "### IMPL-TEST-005: Current candidate`n`n- Rule: Review the current candidate."
        }
        $contractContent = "---`napplyTo: `"internal/**/*.go`"`n---`n`n# Fixture Contract`n`n## Rules`n`n" + (($ruleBlocks.Values) -join "`n`n") + "`n`n<!-- IMPL-CONTRACT-EOF -->`n"
        [IO.File]::WriteAllText($fixtureContractPath, $contractContent, [Text.UTF8Encoding]::new($false))

        $fixtureInteractiveRules = @(
            [ordered]@{ id = 'IMPL-TEST-001'; title = 'New candidate'; contractPath = '.github/instructions/implementation-compliance-contract.instructions.md'; status = 'active'; contentSha256 = Get-StringSha256 $ruleBlocks['IMPL-TEST-001']; provenance = 'unclassified'; evidence = @(); sourceIds = @() },
            [ordered]@{ id = 'IMPL-TEST-002'; title = 'Changed candidate'; contractPath = '.github/instructions/implementation-compliance-contract.instructions.md'; status = 'active'; contentSha256 = Get-StringSha256 $ruleBlocks['IMPL-TEST-002']; provenance = 'inferred-maintainer-convention'; evidence = @('Fixture evidence'); sourceIds = @() },
            [ordered]@{ id = 'IMPL-TEST-003'; title = 'Retired candidate'; contractPath = '.github/instructions/implementation-compliance-contract.instructions.md'; status = 'retired'; contentSha256 = Get-StringSha256 'retired fixture rule'; provenance = 'local-safeguard'; evidence = @('Fixture evidence'); sourceIds = @(); retiredOn = '2026-09-02'; lifecycleReason = 'Fixture retirement' },
            [ordered]@{ id = 'IMPL-TEST-004'; title = 'Deferred candidate'; contractPath = '.github/instructions/implementation-compliance-contract.instructions.md'; status = 'active'; contentSha256 = Get-StringSha256 $ruleBlocks['IMPL-TEST-004']; provenance = 'local-safeguard'; evidence = @('Fixture evidence'); sourceIds = @() },
            [ordered]@{ id = 'IMPL-TEST-005'; title = 'Current candidate'; contractPath = '.github/instructions/implementation-compliance-contract.instructions.md'; status = 'active'; contentSha256 = Get-StringSha256 $ruleBlocks['IMPL-TEST-005']; provenance = 'inferred-maintainer-convention'; evidence = @('Fixture evidence'); sourceIds = @() }
        )
        $fixtureInteractiveCatalogPath = Join-Path $fixtureInteractiveCatalogRoot 'rule-catalog.json'
        Write-JsonFixture -Path $fixtureInteractiveCatalogPath -Value ([ordered]@{
            '$schema' = 'rule-catalog.schema.json'
            schemaVersion = 1
            catalogedOn = '2026-09-02'
            description = 'Offline rule intake refresh fixture.'
            rules = $fixtureInteractiveRules
        })
        $fixtureInteractiveCatalogHash = (Get-FileHash -LiteralPath $fixtureInteractiveCatalogPath -Algorithm SHA256).Hash.ToLowerInvariant()

        $notApplicableFactors = [ordered]@{ scoringStatus = 'not-applicable' }
        $fixtureLedgerPath = Join-Path $fixtureCatalogRoot 'interactive-intake-ledger.json'
        Write-JsonFixture -Path $fixtureLedgerPath -Value ([ordered]@{
            '$schema' = 'interactive-intake-ledger.schema.json'
            schemaVersion = 1
            sourceSnapshot = [ordered]@{ catalogPath = 'tools/interactive-rule-catalog/rule-catalog.json'; catalogSha256 = $fixtureInteractiveCatalogHash; capturedOn = '2026-09-02'; ruleCount = 5 }
            decisions = @(
                [ordered]@{ sourceRuleId = 'IMPL-TEST-002'; sourceContractPath = '.github/instructions/implementation-compliance-contract.instructions.md'; sourceContentSha256 = $otherHash; sourceStatus = 'active'; decision = 'excluded'; rationale = 'Prior changed fixture decision.'; reviewedOn = '2026-09-02'; hostedRuleIds = @(); selectionFactors = $notApplicableFactors; selectionRationale = 'Changed fixture.'; foundationalOverride = $null },
                [ordered]@{ sourceRuleId = 'IMPL-TEST-003'; sourceContractPath = '.github/instructions/implementation-compliance-contract.instructions.md'; sourceContentSha256 = Get-StringSha256 'retired fixture rule'; sourceStatus = 'active'; decision = 'excluded'; rationale = 'Prior active fixture decision.'; reviewedOn = '2026-09-02'; hostedRuleIds = @(); selectionFactors = $notApplicableFactors; selectionRationale = 'Retired fixture.'; foundationalOverride = $null },
                [ordered]@{ sourceRuleId = 'IMPL-TEST-004'; sourceContractPath = '.github/instructions/implementation-compliance-contract.instructions.md'; sourceContentSha256 = Get-StringSha256 $ruleBlocks['IMPL-TEST-004']; sourceStatus = 'active'; decision = 'deferred'; rationale = 'Fixture remains deferred.'; reviewedOn = '2026-09-02'; hostedRuleIds = @(); selectionFactors = $notApplicableFactors; selectionRationale = 'Deferred fixture.'; foundationalOverride = $null },
                [ordered]@{ sourceRuleId = 'IMPL-TEST-005'; sourceContractPath = '.github/instructions/implementation-compliance-contract.instructions.md'; sourceContentSha256 = Get-StringSha256 $ruleBlocks['IMPL-TEST-005']; sourceStatus = 'active'; decision = 'equivalent'; rationale = 'Fixture matches Hosted behavior.'; reviewedOn = '2026-09-02'; hostedRuleIds = @('IMPL-TEST-005'); selectionFactors = $notApplicableFactors; selectionRationale = 'Current fixture.'; foundationalOverride = $null }
            )
        })

        $fixtureHostedCatalogPath = Join-Path $fixtureCatalogRoot 'instruction-catalog.json'
        Write-JsonFixture -Path $fixtureHostedCatalogPath -Value ([ordered]@{
            '$schema' = 'instruction-catalog.schema.json'
            schemaVersion = 1
            lastSemanticReview = '2026-09-02'
            upstreamSnapshot = [ordered]@{ repository = 'hashicorp/terraform-provider-azurerm'; baselineCommit = '1' * 40; currentRef = 'main' }
            ruleDefaults = [ordered]@{ requirementLevel = 'mandatory'; enforcementMethod = 'model-based'; documentationGap = $false }
            sources = @([ordered]@{ id = 'contributing-readme'; title = 'Contributor fixture'; rawUrl = 'https://raw.githubusercontent.com/hashicorp/terraform-provider-azurerm/main/contributing/README.md'; referenceUrl = 'https://github.com/hashicorp/terraform-provider-azurerm/blob/main/contributing/README.md'; baselineSha256 = Get-StringSha256 $baselineContent })
            evidence = @([ordered]@{ id = 'implementation-contract'; type = 'source-contract'; description = 'Fixture implementation evidence.'; reference = '.github/instructions/implementation-compliance-contract.instructions.md' })
            surfaces = @([ordered]@{ id = 'implementation'; outputPath = '.github/instructions/fixture.instructions.md'; description = 'Fixture instructions.'; applyTo = 'internal/**/*.go'; title = 'Fixture'; introduction = 'Fixture introduction.'; sections = @([ordered]@{ heading = 'Fixture'; ruleIds = @('IMPL-TEST-005') }); closing = 'Fixture closing.' })
            rules = @([ordered]@{ id = 'IMPL-TEST-005'; origin = 'hosted-baseline-migration'; status = 'active'; text = 'Review the current Hosted fixture.'; provenance = @('inferred-maintainer-convention'); sourceIds = @('contributing-readme'); evidenceIds = @('implementation-contract'); implementationModels = @('legacy', 'typed', 'framework') })
        })

        $bundleOutputPath = Join-Path $fixtureRoot 'output/rule-intake-review.json'
        $protectedPaths = @($fixtureHostedCatalogPath, $fixtureLedgerPath, $fixtureInteractiveCatalogPath, $fixtureContractPath)
        $hashesBefore = @($protectedPaths | ForEach-Object { (Get-FileHash -LiteralPath $_ -Algorithm SHA256).Hash })
        $bundleOutput = @(& pwsh -NoProfile -File $bundleScriptPath -RepositoryRoot $fixtureRoot -HostedCatalogPath $fixtureHostedCatalogPath -IntakeLedgerPath $fixtureLedgerPath -InteractiveCatalogPath $fixtureInteractiveCatalogPath -UpstreamBaselineDirectory $fixtureBaselineRoot -UpstreamCurrentDirectory $fixtureCurrentRoot -UpstreamCurrentCommit ('2' * 40) -OutputPath $bundleOutputPath -OutputFormat Json 2>&1)
        $bundleExitCode = $LASTEXITCODE
        $hashesAfter = @($protectedPaths | ForEach-Object { (Get-FileHash -LiteralPath $_ -Algorithm SHA256).Hash })
        $bundleJson = if ($bundleExitCode -eq 0) { ($bundleOutput | Out-String).Trim() } else { '' }
        $bundle = if ($bundleExitCode -eq 0) { $bundleJson | ConvertFrom-Json } else { $null }

        $bundleValidationDetail = if ($bundleExitCode -eq 0) { 'An offline candidate refresh produces a schema-valid bundle.' } else { "Candidate bundle command failed: $(($bundleOutput | Out-String).Trim())" }
        Add-TestResult -Name 'candidate-bundle-valid' -Passed ($bundleExitCode -eq 0 -and (Test-JsonInstance -Json $bundleJson -SchemaPath $bundleSchemaPath)) -Detail $bundleValidationDetail
        Add-TestResult -Name 'candidate-bundle-read-only' -Passed ($bundleExitCode -eq 0 -and (@(Compare-Object $hashesBefore $hashesAfter).Count -eq 0)) -Detail 'Refreshing candidates does not modify either toolkit source.'
        $capacityNames = if ($bundleExitCode -eq 0) { @($bundle.guidanceCapacity.reports | ForEach-Object { [string]$_.name } | Sort-Object) } else { @() }
        $expectedCapacityNames = @('repository', 'go', 'test', 'documentation', 'skill', 'go-combined', 'test-combined', 'documentation-combined') | Sort-Object
        $capacityArithmeticValid = $bundleExitCode -eq 0 -and @($bundle.guidanceCapacity.reports | Where-Object { $_.budgetHeadroomTokens -ne ($_.budgetTokens - $_.guardedTokens) }).Count -eq 0
        Add-TestResult -Name 'candidate-bundle-capacity' -Passed ($bundleExitCode -eq 0 -and @(Compare-Object $expectedCapacityNames $capacityNames).Count -eq 0 -and $capacityArithmeticValid) -Detail 'Candidate bundles expose all eight structured capacity reports with valid budget headroom.'
        Add-TestResult -Name 'upstream-change-classified' -Passed ($bundleExitCode -eq 0 -and $bundle.summary.changedUpstreamCount -eq 1 -and $bundle.upstreamCandidates[0].state -eq 'changed') -Detail 'Changed upstream content is reopened for semantic review.'
        $upstreamMappedRule = if ($bundleExitCode -eq 0) { @($bundle.upstreamCandidates[0].relatedHostedRules)[0] } else { $null }
        Add-TestResult -Name 'upstream-hosted-mapping-complete' -Passed ($null -ne $upstreamMappedRule -and $upstreamMappedRule.id -eq 'IMPL-TEST-005' -and $upstreamMappedRule.text -eq 'Review the current Hosted fixture.' -and $upstreamMappedRule.placements[0].surfaceId -eq 'implementation') -Detail 'Upstream candidates include exact mapped Hosted rule identity, text, status, and placement.'
        $statesById = @{}
        if ($bundleExitCode -eq 0) {
            foreach ($candidate in @($bundle.interactiveCandidates)) { $statesById[[string]$candidate.id] = [string]$candidate.state }
        }
        $allRefreshStates = $statesById['IMPL-TEST-001'] -eq 'new' -and $statesById['IMPL-TEST-002'] -eq 'changed' -and $statesById['IMPL-TEST-003'] -eq 'retired' -and $statesById['IMPL-TEST-004'] -eq 'deferred' -and $statesById['IMPL-TEST-005'] -eq 'current'
        Add-TestResult -Name 'interactive-refresh-states' -Passed ($bundleExitCode -eq 0 -and $allRefreshStates) -Detail 'Refresh classifies new, changed, retired, deferred, and current Interactive rules.'
        $newCandidate = if ($bundleExitCode -eq 0) { @($bundle.interactiveCandidates | Where-Object id -eq 'IMPL-TEST-001')[0] } else { $null }
        Add-TestResult -Name 'exact-contract-rule-text' -Passed ($null -ne $newCandidate -and $newCandidate.ruleText -ceq $ruleBlocks['IMPL-TEST-001']) -Detail 'Candidate evidence contains the exact normalized contract rule block.'
    }
    finally {
        if (Test-Path -LiteralPath $fixtureRoot) {
            Remove-Item -LiteralPath $fixtureRoot -Recurse -Force
        }
    }
}
catch {
    $issues.Add($_.Exception.Message)
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
    Write-ValidationSectionHeader -Title 'Hosted rule intake contract test summary'
    Write-ValidationSummary -Fields ([ordered]@{
        Status = $result.status.ToUpperInvariant()
        Tests = $result.testCount
        'Issue Count' = $result.issueCount
    })
    Write-ValidationSectionHeader -Title 'Contract tests'
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
