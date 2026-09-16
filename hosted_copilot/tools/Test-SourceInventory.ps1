[CmdletBinding()]
param(
    [ValidateSet('Text', 'Json')]
    [string]$OutputFormat = 'Text'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$validationOutputModulePath = Join-Path $PSScriptRoot '../../tools/ValidationOutput.psm1'
Import-Module -Name $validationOutputModulePath -Force

$repoRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
$sourceEvidenceModulePath = Join-Path $PSScriptRoot 'SourceEvidenceValidation.psm1'
Import-Module -Name $sourceEvidenceModulePath -Force
$catalogRoot = Join-Path $repoRoot 'hosted_copilot/copilot-rule-catalog'
$definitionPath = Join-Path $catalogRoot 'source-definitions/maintainer-proposals.json'
$interactiveDefinitionPath = Join-Path $catalogRoot 'source-definitions/interactive-toolkit.json'
$contributorDefinitionPath = Join-Path $catalogRoot 'source-definitions/contributor-guidance.json'
$definitionSchemaPath = Join-Path $catalogRoot 'source-definitions/source-definition.schema.json'
$inventorySchemaPath = Join-Path $catalogRoot 'source-inventories/source-inventory.schema.json'
$contractPath = Join-Path $catalogRoot 'parser-contracts/maintainer-proposals-v2.json'
$interactiveContractPath = Join-Path $catalogRoot 'parser-contracts/interactive-toolkit-v2.json'
$contributorContractPath = Join-Path $catalogRoot 'parser-contracts/contributor-guidance-v2.json'
$contractSchemaPath = Join-Path $catalogRoot 'parser-contracts/parser-contract.schema.json'
$collectorPath = Join-Path $PSScriptRoot 'New-SourceInventory.ps1'
$acceptanceExporterPath = Join-Path $PSScriptRoot 'New-AcceptedSourceInventory.ps1'
$acceptanceApplyPath = Join-Path $PSScriptRoot 'Apply-AcceptedSourceInventory.ps1'
$parserModulePath = Join-Path $PSScriptRoot 'source-parsers/MaintainerProposalsV2.psm1'
$interactiveParserModulePath = Join-Path $PSScriptRoot 'source-parsers/InteractiveToolkitV2.psm1'
$contributorParserModulePath = Join-Path $PSScriptRoot 'source-parsers/ContributorGuidanceV2.psm1'
$interactiveCatalogPath = Join-Path $repoRoot 'tools/interactive-rule-catalog/rule-catalog.json'
$maintainerRoot = Join-Path $catalogRoot 'maintainer-rules'
$results = [Collections.Generic.List[object]]::new()
$issues = [Collections.Generic.List[string]]::new()

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

function Test-JsonInstance {
    param(
        [Parameter(Mandatory = $true)][AllowEmptyString()][string]$Json,
        [Parameter(Mandatory = $true)][string]$SchemaPath
    )

    try {
        return [bool](Test-Json -Json $Json -SchemaFile $SchemaPath -ErrorAction Stop)
    }
    catch {
        return $false
    }
}

function Get-StringSha256 {
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string]$Value
    )

    $bytes = [Text.Encoding]::UTF8.GetBytes($Value)
    return [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($bytes)).ToLowerInvariant()
}

function Write-JsonFixture {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)]$Value
    )

    [IO.File]::WriteAllText($Path, (($Value | ConvertTo-Json -Depth 20) + "`n"), [Text.UTF8Encoding]::new($false))
}

function Copy-JsonObject {
    param([Parameter(Mandatory = $true)][object]$Value)

    return ($Value | ConvertTo-Json -Depth 40 -Compress) | ConvertFrom-Json -DateKind String
}

function Invoke-Collector {
    param(
        [Parameter(Mandatory = $true)][string]$OutputPath,
        [string]$DefinitionPath = $definitionPath
    )

    $output = @(& pwsh -NoProfile -File $collectorPath -RepositoryRoot $repoRoot -SourceDefinitionPath $DefinitionPath -OutputPath $OutputPath -OutputFormat Json 2>&1)
    return [pscustomobject]@{ ExitCode = $LASTEXITCODE; Output = ($output | Out-String).Trim() }
}

function Test-ThrowsLike {
    param(
        [Parameter(Mandatory = $true)][scriptblock]$Action,
        [Parameter(Mandatory = $true)][string]$Pattern
    )

    try {
        & $Action
        return $false
    }
    catch {
        return $_.Exception.Message -like $Pattern
    }
}

function Test-DoesNotThrow {
    param([Parameter(Mandatory = $true)][scriptblock]$Action)

    try {
        & $Action
        return $true
    }
    catch {
        return $false
    }
}

function Write-ProposalFixture {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Surface,
        [Parameter(Mandatory = $true)][string]$Body
    )

    $content = "---`ndescription: `"Fixture proposals.`"`nsurface: $Surface`n---`n`n# Fixture proposals`n`n$Body`n"
    [IO.File]::WriteAllText($Path, $content, [Text.UTF8Encoding]::new($false))
}

$fixtureRoot = Join-Path ([IO.Path]::GetTempPath()) ('hosted-source-inventory-' + [guid]::NewGuid().ToString('N'))
try {
    $null = New-Item -ItemType Directory -Path $fixtureRoot -Force
    $firstOutputPath = Join-Path $fixtureRoot 'maintainer-first.json'
    $secondOutputPath = Join-Path $fixtureRoot 'maintainer-second.json'
    $interactiveFirstOutputPath = Join-Path $fixtureRoot 'interactive-first.json'
    $interactiveSecondOutputPath = Join-Path $fixtureRoot 'interactive-second.json'

    $canonicalUtcTimestamp = ConvertTo-SourceEvidenceUtcTimestamp -Value '2026-09-15T14:30:00+02:00'
    $expectedCanonicalUtcTimestamp = [datetime]::new(2026, 9, 15, 12, 30, 0, [DateTimeKind]::Utc).ToString('o', [Globalization.CultureInfo]::InvariantCulture)
    Add-TestResult -Name 'canonical-utc-timestamp' -Passed ($canonicalUtcTimestamp -ceq $expectedCanonicalUtcTimestamp) -Detail 'Source evidence timestamps use one invariant UTC round-trip representation regardless of input offset.'
    Add-TestResult -Name 'invalid-source-timestamp-rejected' -Passed (Test-ThrowsLike -Action { ConvertTo-SourceEvidenceUtcTimestamp -Value 'not-a-timestamp' } -Pattern '*Invalid source evidence timestamp*') -Detail 'Invalid source evidence timestamps fail through the shared parser rather than locale-dependent coercion.'
    $retryAttemptCount = 0
    $retryResult = Invoke-SourceEvidenceWithRetry -Operation 'test transient operation' -MaximumAttempts 3 -BaseDelayMilliseconds 0 -Action {
        $script:retryAttemptCount++
        if ($script:retryAttemptCount -lt 3) {
            throw [TimeoutException]::new('transient')
        }
        return 'completed'
    }
    Add-TestResult -Name 'bounded-retry-recovers' -Passed ($retryResult -ceq 'completed' -and $retryAttemptCount -eq 3) -Detail 'The shared retry executor recovers within its exact attempt bound without changing operation input.'
    $exhaustedAttemptCount = 0
    $retryExhausted = Test-ThrowsLike -Action {
        Invoke-SourceEvidenceWithRetry -Operation 'test exhausted operation' -MaximumAttempts 2 -BaseDelayMilliseconds 0 -Action {
            $script:exhaustedAttemptCount++
            throw [TimeoutException]::new('transient')
        }
    } -Pattern '*transient*'
    Add-TestResult -Name 'bounded-retry-exhausts' -Passed ($retryExhausted -and $exhaustedAttemptCount -eq 2) -Detail 'The shared retry executor stops after the configured maximum attempts.'

    $initialAcceptedAt = '2026-09-15T14:00:00+02:00'
    $secondAcceptedAt = '2026-09-15T08:00:00-05:00'
    $thirdAcceptedAt = '2026-09-15T14:00:00Z'
    $nonIncreasingAcceptedAt = '2026-09-15T15:00:00+02:00'
    $expectedInitialAcceptedAt = [datetime]::new(2026, 9, 15, 12, 0, 0, [DateTimeKind]::Utc).ToString('o', [Globalization.CultureInfo]::InvariantCulture)
    $expectedSecondAcceptedAt = [datetime]::new(2026, 9, 15, 13, 0, 0, [DateTimeKind]::Utc).ToString('o', [Globalization.CultureInfo]::InvariantCulture)
    $expectedThirdAcceptedAt = [datetime]::new(2026, 9, 15, 14, 0, 0, [DateTimeKind]::Utc).ToString('o', [Globalization.CultureInfo]::InvariantCulture)

    Add-TestResult -Name 'source-definition-schema' -Passed (Test-JsonInstance -Json (Get-Content -LiteralPath $definitionPath -Raw) -SchemaPath $definitionSchemaPath) -Detail 'Maintainer Proposals uses the strict shared source-definition schema.'
    Add-TestResult -Name 'parser-contract-schema' -Passed (Test-JsonInstance -Json (Get-Content -LiteralPath $contractPath -Raw) -SchemaPath $contractSchemaPath) -Detail 'The Maintainer Proposals parser contract has a strict versioned shape.'
    Add-TestResult -Name 'interactive-definition-schema' -Passed (Test-JsonInstance -Json (Get-Content -LiteralPath $interactiveDefinitionPath -Raw) -SchemaPath $definitionSchemaPath) -Detail 'Interactive Toolkit uses the strict shared source-definition schema.'
    Add-TestResult -Name 'interactive-contract-schema' -Passed (Test-JsonInstance -Json (Get-Content -LiteralPath $interactiveContractPath -Raw) -SchemaPath $contractSchemaPath) -Detail 'The Interactive Toolkit parser contract has a strict versioned shape.'
    Add-TestResult -Name 'contributor-definition-schema' -Passed (Test-JsonInstance -Json (Get-Content -LiteralPath $contributorDefinitionPath -Raw) -SchemaPath $definitionSchemaPath) -Detail 'Contributor Guidance uses the strict shared source-definition schema.'
    Add-TestResult -Name 'contributor-contract-schema' -Passed (Test-JsonInstance -Json (Get-Content -LiteralPath $contributorContractPath -Raw) -SchemaPath $contractSchemaPath) -Detail 'The Contributor Guidance parser contract has a strict versioned shape.'

    $interactiveCatalog = Get-Content -LiteralPath $interactiveCatalogPath -Raw | ConvertFrom-Json
    $interactiveContractSourcePaths = @($interactiveCatalog.rules.contractPath | Sort-Object -Unique | ForEach-Object { Join-Path $repoRoot $_ })
    $protectedPaths = @($definitionPath, $interactiveDefinitionPath, $contributorDefinitionPath, $definitionSchemaPath, $inventorySchemaPath, $contractPath, $interactiveContractPath, $contributorContractPath, $contractSchemaPath, $parserModulePath, $interactiveParserModulePath, $contributorParserModulePath, $interactiveCatalogPath) + @(Get-ChildItem -LiteralPath $maintainerRoot -Filter '*.rules.md' -File | Select-Object -ExpandProperty FullName) + $interactiveContractSourcePaths
    $hashesBefore = @($protectedPaths | ForEach-Object { (Get-FileHash -LiteralPath $_ -Algorithm SHA256).Hash })
    $firstRun = Invoke-Collector -OutputPath $firstOutputPath
    $secondRun = Invoke-Collector -OutputPath $secondOutputPath
    $interactiveFirstRun = Invoke-Collector -OutputPath $interactiveFirstOutputPath -DefinitionPath $interactiveDefinitionPath
    $interactiveSecondRun = Invoke-Collector -OutputPath $interactiveSecondOutputPath -DefinitionPath $interactiveDefinitionPath
    $hashesAfter = @($protectedPaths | ForEach-Object { (Get-FileHash -LiteralPath $_ -Algorithm SHA256).Hash })

    $firstInventory = if ($firstRun.ExitCode -eq 0) { Get-Content -LiteralPath $firstOutputPath -Raw | ConvertFrom-Json } else { $null }
    $secondInventory = if ($secondRun.ExitCode -eq 0) { Get-Content -LiteralPath $secondOutputPath -Raw | ConvertFrom-Json } else { $null }
    $interactiveFirstInventory = if ($interactiveFirstRun.ExitCode -eq 0) { Get-Content -LiteralPath $interactiveFirstOutputPath -Raw | ConvertFrom-Json } else { $null }
    $interactiveSecondInventory = if ($interactiveSecondRun.ExitCode -eq 0) { Get-Content -LiteralPath $interactiveSecondOutputPath -Raw | ConvertFrom-Json } else { $null }
    Add-TestResult -Name 'real-inventory-generated' -Passed ($firstRun.ExitCode -eq 0 -and $secondRun.ExitCode -eq 0) -Detail 'The collector generates staged inventories for the real Maintainer Proposal corpus.'
    Add-TestResult -Name 'real-inventory-schema' -Passed ($null -ne $firstInventory -and (Test-JsonInstance -Json (Get-Content -LiteralPath $firstOutputPath -Raw) -SchemaPath $inventorySchemaPath)) -Detail 'The staged inventory satisfies the strict inventory schema.'
    Add-TestResult -Name 'real-inventory-count' -Passed ($null -ne $firstInventory -and @($firstInventory.records).Count -eq 38 -and @($firstInventory.records.sourceId | Sort-Object -Unique).Count -eq 38) -Detail 'The initial migration corpus contains exactly 38 unique live proposal IDs.'
    $currentMaintainerEvidence = Get-CurrentSourceDefinitionEvidence -RepositoryRoot $repoRoot -SourceDefinitionId 'maintainer-proposals'
    Add-TestResult -Name 'generated-parser-hash-binding' -Passed ($null -ne $firstInventory -and [string]$firstInventory.parserContractSha256 -ceq [string]$currentMaintainerEvidence.ParserContractSha256) -Detail 'Generated inventory stores the automatically calculated hash of its exact parser behavior contract.'
    Add-TestResult -Name 'inventory-deterministic' -Passed ($null -ne $firstInventory -and $null -ne $secondInventory -and $firstInventory.collection.inventorySha256 -ceq $secondInventory.collection.inventorySha256 -and $firstInventory.inventoryConfigurationSha256 -ceq $secondInventory.inventoryConfigurationSha256) -Detail 'Repeated collection produces identical factual and configuration hashes.'
    Add-TestResult -Name 'inventory-source-only' -Passed ($null -ne $firstInventory -and @($firstInventory.records | Where-Object { $_.PSObject.Properties['state'] -or $_.PSObject.Properties['requiresReview'] -or $_.PSObject.Properties['relatedHostedRules'] }).Count -eq 0) -Detail 'Inventory records contain source facts without candidate or Hosted decision state.'
    Add-TestResult -Name 'interactive-inventory-generated' -Passed ($interactiveFirstRun.ExitCode -eq 0 -and $interactiveSecondRun.ExitCode -eq 0) -Detail 'The collector generates staged inventories for the real Interactive Toolkit catalog.'
    Add-TestResult -Name 'interactive-inventory-schema' -Passed ($null -ne $interactiveFirstInventory -and (Test-JsonInstance -Json (Get-Content -LiteralPath $interactiveFirstOutputPath -Raw) -SchemaPath $inventorySchemaPath)) -Detail 'The Interactive staged inventory satisfies the strict shared inventory schema.'
    Add-TestResult -Name 'interactive-inventory-count' -Passed ($null -ne $interactiveFirstInventory -and @($interactiveFirstInventory.records).Count -eq 349 -and @($interactiveFirstInventory.records.sourceId | Sort-Object -Unique).Count -eq 349) -Detail 'The Interactive inventory contains exactly all 349 unique catalog rule IDs.'
    Add-TestResult -Name 'interactive-inventory-deterministic' -Passed ($null -ne $interactiveFirstInventory -and $null -ne $interactiveSecondInventory -and $interactiveFirstInventory.collection.inventorySha256 -ceq $interactiveSecondInventory.collection.inventorySha256 -and $interactiveFirstInventory.inventoryConfigurationSha256 -ceq $interactiveSecondInventory.inventoryConfigurationSha256 -and $interactiveFirstInventory.collection.sourceRevision.worktreeSha256 -ceq $interactiveSecondInventory.collection.sourceRevision.worktreeSha256) -Detail 'Repeated Interactive collection produces identical factual, configuration, and source-revision hashes.'
    Add-TestResult -Name 'interactive-inventory-source-only' -Passed ($null -ne $interactiveFirstInventory -and @($interactiveFirstInventory.records | Where-Object { $_.PSObject.Properties['state'] -or $_.PSObject.Properties['requiresReview'] -or $_.PSObject.Properties['hostedRuleIds'] -or $_.PSObject.Properties['relatedHostedRules'] }).Count -eq 0) -Detail 'Interactive records contain source facts without ledger decisions or Hosted candidate state.'
    Import-Module $contributorParserModulePath -Force
    $contributorDocuments = @(
        [pscustomobject]@{ RelativePath = 'README.md'; Content = "# Contributor Guide`n`nOverview.`n" },
        [pscustomobject]@{ RelativePath = 'topics/guide-new-resource.md'; Content = "# Guide: New Resource`n`nRules.`n" }
    )
    $contributorRecords = @(Get-ContributorGuidanceInventoryRecords -Documents $contributorDocuments -Repository 'hashicorp/terraform-provider-azurerm' -ResolvedCommit ('a' * 40) -RootPath 'contributing')
    Add-TestResult -Name 'contributor-parser-records' -Passed ($contributorRecords.Count -eq 2 -and [string]$contributorRecords[0].sourceId -ceq 'contributing-readme' -and [string]$contributorRecords[1].sourceId -ceq 'guide-new-resource') -Detail 'Contributor documents retain legacy-compatible deterministic source IDs.'
    Add-TestResult -Name 'contributor-parser-pinned-evidence' -Passed (@($contributorRecords | Where-Object { $_.resolvedCommit -cne ('a' * 40) -or $_.referenceUrl -notlike "https://github.com/hashicorp/terraform-provider-azurerm/blob/$('a' * 40)/*" }).Count -eq 0) -Detail 'Contributor records bind content and references to one immutable commit.'
    Add-TestResult -Name 'inventory-read-only' -Passed (@(Compare-Object $hashesBefore $hashesAfter).Count -eq 0) -Detail 'Both local collectors leave source definitions, parser contracts, schemas, catalogs, contracts, and Maintainer Proposals unchanged.'

    $insideRepositoryOutput = Join-Path $repoRoot '.source-inventory-boundary-test.json'
    $boundaryRun = Invoke-Collector -OutputPath $insideRepositoryOutput
    Add-TestResult -Name 'repository-output-rejected' -Passed ($boundaryRun.ExitCode -ne 0 -and -not (Test-Path -LiteralPath $insideRepositoryOutput)) -Detail 'Staged inventory output cannot be written inside the repository.'

    $definitionFixtureRoot = Join-Path $fixtureRoot 'source-definitions'
    $null = New-Item -ItemType Directory -Path $definitionFixtureRoot -Force
    Copy-Item -LiteralPath $definitionSchemaPath -Destination $definitionFixtureRoot
    $filteredDefinitionPath = Join-Path $definitionFixtureRoot 'filtered.json'
    Write-JsonFixture -Path $filteredDefinitionPath -Value ([ordered]@{
        '$schema' = 'source-definition.schema.json'
        schemaVersion = 1
        id = 'maintainer-proposals'
        displayName = 'Maintainer Proposals'
        root = [ordered]@{ kind = 'repository'; path = 'hosted_copilot/copilot-rule-catalog/maintainer-rules' }
        files = @('**/*.rules.md')
        exclude = @('implementation.rules.md')
        parser = 'maintainer-proposals-v2'
        assessmentBatchSize = 20
    })
    $filteredOutputPath = Join-Path $fixtureRoot 'maintainer-filtered.json'
    $filteredRun = Invoke-Collector -OutputPath $filteredOutputPath -DefinitionPath $filteredDefinitionPath
    $filteredInventory = if ($filteredRun.ExitCode -eq 0) { Get-Content -LiteralPath $filteredOutputPath -Raw | ConvertFrom-Json } else { $null }
    Add-TestResult -Name 'exclude-pattern-wins' -Passed ($filteredRun.ExitCode -eq 0 -and @($filteredInventory.records).Count -gt 0 -and @($filteredInventory.records | Where-Object surface -eq 'implementation').Count -eq 0) -Detail 'A matching exclusion removes files after inclusion using case-sensitive path semantics.'

    $escapingDefinitionPath = Join-Path $definitionFixtureRoot 'escaping.json'
    Write-JsonFixture -Path $escapingDefinitionPath -Value ([ordered]@{
        '$schema' = 'source-definition.schema.json'
        schemaVersion = 1
        id = 'maintainer-proposals'
        displayName = 'Maintainer Proposals'
        root = [ordered]@{ kind = 'repository'; path = '../' }
        files = @('**/*.rules.md')
        exclude = @()
        parser = 'maintainer-proposals-v2'
        assessmentBatchSize = 20
    })
    $escapingRun = Invoke-Collector -OutputPath (Join-Path $fixtureRoot 'escaping-output.json') -DefinitionPath $escapingDefinitionPath
    Add-TestResult -Name 'root-traversal-rejected' -Passed ($escapingRun.ExitCode -ne 0 -and $escapingRun.Output -like '*dot segment*') -Detail 'Repository roots cannot contain parent traversal.'

    Import-Module $parserModulePath -Force
    $parserFixtureRoot = Join-Path $fixtureRoot 'parser-fixtures'
    $null = New-Item -ItemType Directory -Path $parserFixtureRoot -Force
    $duplicateOne = Join-Path $parserFixtureRoot 'duplicate-one.rules.md'
    $duplicateTwo = Join-Path $parserFixtureRoot 'duplicate-two.rules.md'
    $duplicateBody = "### IMPL-MAINT-900: Duplicate rule`n`n- Rule: Reject duplicate rule IDs.`n- Provenance: local-safeguard`n- Rationale: Duplicate IDs are ambiguous."
    Write-ProposalFixture -Path $duplicateOne -Surface 'implementation' -Body $duplicateBody
    Write-ProposalFixture -Path $duplicateTwo -Surface 'implementation' -Body $duplicateBody
    Add-TestResult -Name 'duplicate-id-rejected' -Passed (Test-ThrowsLike -Action { Get-MaintainerProposalInventoryRecords -SourcePaths @($duplicateOne, $duplicateTwo) -RepositoryRoot $fixtureRoot } -Pattern '*Duplicate maintainer rule ID*') -Detail 'Duplicate IDs across files fail closed.'

    $invalidProvenancePath = Join-Path $parserFixtureRoot 'invalid-provenance.rules.md'
    Write-ProposalFixture -Path $invalidProvenancePath -Surface 'implementation' -Body "### IMPL-MAINT-901: Invalid provenance`n`n- Rule: Reject unsupported provenance.`n- Provenance: published-upstream-standard`n- Rationale: Maintainer proposals cannot claim upstream ownership."
    Add-TestResult -Name 'invalid-provenance-rejected' -Passed (Test-ThrowsLike -Action { Get-MaintainerProposalInventoryRecords -SourcePaths @($invalidProvenancePath) -RepositoryRoot $fixtureRoot } -Pattern '*unsupported provenance*') -Detail 'Maintainer Proposals accept only their allowlisted provenance values.'

    $retiredPath = Join-Path $parserFixtureRoot 'retired.rules.md'
    Write-ProposalFixture -Path $retiredPath -Surface 'implementation' -Body "### IMPL-MAINT-902: Retired proposal`n`n- Rule: Reject an unbound retired proposal.`n- Provenance: local-safeguard`n- Rationale: Retirement requires an existing Hosted rule.`n- Status: retired"
    Add-TestResult -Name 'retired-mapping-required' -Passed (Test-ThrowsLike -Action { Get-MaintainerProposalInventoryRecords -SourcePaths @($retiredPath) -RepositoryRoot $fixtureRoot } -Pattern '*does not map to a Hosted rule*') -Detail 'Retired Maintainer Proposals must resolve to an existing Hosted rule.'

    $acceptedFixtureRoot = Join-Path $fixtureRoot 'accepted-lifecycle'
    $isolatedRepositoryRoot = Join-Path $acceptedFixtureRoot 'repository'
    $isolatedCatalogRoot = Join-Path $isolatedRepositoryRoot 'hosted_copilot/copilot-rule-catalog'
    $isolatedInventoryRoot = Join-Path $isolatedCatalogRoot 'source-inventories'
    $isolatedDefinitionRoot = Join-Path $isolatedCatalogRoot 'source-definitions'
    $isolatedContractRoot = Join-Path $isolatedCatalogRoot 'parser-contracts'
    $isolatedToolsRoot = Join-Path $isolatedRepositoryRoot 'hosted_copilot/tools'
    $isolatedParserRoot = Join-Path $isolatedToolsRoot 'source-parsers'
    $null = New-Item -ItemType Directory -Path $isolatedInventoryRoot, $isolatedDefinitionRoot, $isolatedContractRoot, $isolatedParserRoot -Force
    Copy-Item -LiteralPath $inventorySchemaPath -Destination $isolatedInventoryRoot
    Copy-Item -LiteralPath $definitionSchemaPath -Destination $isolatedDefinitionRoot
    Copy-Item -LiteralPath $definitionPath -Destination $isolatedDefinitionRoot
    Copy-Item -LiteralPath $contributorDefinitionPath -Destination $isolatedDefinitionRoot
    Copy-Item -LiteralPath (Join-Path $catalogRoot 'source-definitions/source-definition-set.schema.json') -Destination $isolatedDefinitionRoot
    Copy-Item -LiteralPath $contractSchemaPath -Destination $isolatedContractRoot
    Copy-Item -LiteralPath $contractPath -Destination $isolatedContractRoot
    Copy-Item -LiteralPath $collectorPath -Destination $isolatedToolsRoot
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'SourceEvidenceValidation.psm1') -Destination $isolatedToolsRoot
    Copy-Item -LiteralPath $parserModulePath -Destination $isolatedParserRoot
    $acceptedOnePath = Join-Path $acceptedFixtureRoot 'accepted-one.json'
    $acceptedTwoPath = Join-Path $acceptedFixtureRoot 'accepted-two.json'
    $acceptedThreePath = Join-Path $acceptedFixtureRoot 'accepted-three.json'
    $stagedTwoPath = Join-Path $acceptedFixtureRoot 'staged-two.json'

    $initialAcceptanceOutput = @(& pwsh -NoProfile -File $acceptanceExporterPath -StagedInventoryPath $firstOutputPath -OutputPath $acceptedOnePath -AcceptedBy 'test-maintainer' -AcceptedAt $initialAcceptedAt -OutputFormat Json 2>&1)
    $initialAcceptanceExitCode = $LASTEXITCODE
    $initialAcceptanceResult = if ($initialAcceptanceExitCode -eq 0) { ($initialAcceptanceOutput | Out-String) | ConvertFrom-Json } else { $null }
    $acceptedOne = if ($initialAcceptanceExitCode -eq 0) { Get-Content -LiteralPath $acceptedOnePath -Raw | ConvertFrom-Json -DateKind String } else { $null }
    Add-TestResult -Name 'initial-acceptance-export' -Passed ($initialAcceptanceExitCode -eq 0 -and $initialAcceptanceResult.transitionCounts.added -eq 38 -and @($acceptedOne.acceptedRevisions).Count -eq 0 -and $acceptedOne.acceptance.previousAcceptedInventorySha256 -eq $null -and [string]$acceptedOne.acceptance.acceptedAt -ceq $expectedInitialAcceptedAt) -Detail 'Initial acceptance exports all staged records with canonical UTC acceptance metadata and no invented prior history.'

    $currentEvidence = Get-CurrentSourceDefinitionEvidence -RepositoryRoot $repoRoot -SourceDefinitionId 'maintainer-proposals'
    $displayOnlyEvidence = $currentEvidence | Select-Object *
    $displayOnlyEvidence.SourceDefinitionSha256 = 'e' * 64
    Add-TestResult -Name 'display-only-definition-change' -Passed (Test-DoesNotThrow -Action { Assert-CurrentAcceptedSourceInventory -Inventory $acceptedOne -Evidence $displayOnlyEvidence }) -Detail 'A changed audit-only source-definition hash does not invalidate an accepted inventory when its factual configuration is unchanged.'

    $staleConfigurationEvidence = $currentEvidence | Select-Object *
    $staleConfigurationEvidence.InventoryConfigurationSha256 = 'e' * 64
    Add-TestResult -Name 'inventory-configuration-drift-rejected' -Passed (Test-ThrowsLike -Action { Assert-CurrentAcceptedSourceInventory -Inventory $acceptedOne -Evidence $staleConfigurationEvidence } -Pattern '*configuration hash is stale*') -Detail 'A changed inventory-affecting configuration still invalidates accepted evidence.'

    $staleParserEvidence = $currentEvidence | Select-Object *
    $staleParserEvidence.ParserContractSha256 = 'e' * 64
    Add-TestResult -Name 'parser-contract-drift-rejected' -Passed (Test-ThrowsLike -Action { Assert-CurrentAcceptedSourceInventory -Inventory $acceptedOne -Evidence $staleParserEvidence } -Pattern '*parser contract hash is stale*') -Detail 'Accepted inventory is rejected when current parser behavior no longer matches its automatically recorded contract hash.'

    $repositoryAcceptancePath = Join-Path $repoRoot '.accepted-inventory-boundary-test.json'
    $repositoryAcceptanceOutput = @(& pwsh -NoProfile -File $acceptanceExporterPath -StagedInventoryPath $firstOutputPath -OutputPath $repositoryAcceptancePath -AcceptedBy 'test-maintainer' -OutputFormat Json 2>&1)
    $repositoryAcceptanceExitCode = $LASTEXITCODE
    Add-TestResult -Name 'acceptance-export-boundary' -Passed ($repositoryAcceptanceExitCode -ne 0 -and -not (Test-Path -LiteralPath $repositoryAcceptancePath)) -Detail 'Accepted inventory export cannot write inside the repository.'

    $isolatedDefinitionSetPath = Join-Path $isolatedDefinitionRoot 'source-definition-set.json'
    Write-JsonFixture -Path $isolatedDefinitionSetPath -Value ([ordered]@{
        '$schema' = 'source-definition-set.schema.json'
        schemaVersion = 1
        sourceDefinitionIds = @('contributor-guidance')
    })
    $unapprovedApplyOutput = @(& pwsh -NoProfile -File $acceptanceApplyPath -RepositoryRoot $isolatedRepositoryRoot -CandidatePath $acceptedOnePath -ExpectedCandidateSha256 $initialAcceptanceResult.candidateSha256 -OutputFormat Json 2>&1)
    $unapprovedApplyExitCode = $LASTEXITCODE
    Add-TestResult -Name 'unapproved-source-apply-rejected' -Passed ($unapprovedApplyExitCode -ne 0 -and ($unapprovedApplyOutput | Out-String) -like '*source is not approved*') -Detail 'Apply consumes the explicit approved source-definition set rather than its destination filename map as participation authority.'
    Write-JsonFixture -Path $isolatedDefinitionSetPath -Value ([ordered]@{
        '$schema' = 'source-definition-set.schema.json'
        schemaVersion = 1
        sourceDefinitionIds = @('maintainer-proposals')
    })

    $firstApplyOutput = @(& pwsh -NoProfile -File $acceptanceApplyPath -RepositoryRoot $isolatedRepositoryRoot -CandidatePath $acceptedOnePath -ExpectedCandidateSha256 $initialAcceptanceResult.candidateSha256 -OutputFormat Json 2>&1)
    $firstApplyExitCode = $LASTEXITCODE
    $canonicalAcceptedPath = Join-Path $isolatedInventoryRoot 'maintainer.json'
    Add-TestResult -Name 'initial-acceptance-apply' -Passed ($firstApplyExitCode -eq 0 -and (Test-Path -LiteralPath $canonicalAcceptedPath -PathType Leaf)) -Detail 'The explicit apply command writes only the canonical source-specific inventory path.'
    $canonicalAcceptedSha256 = if (Test-Path -LiteralPath $canonicalAcceptedPath -PathType Leaf) { (Get-FileHash -LiteralPath $canonicalAcceptedPath -Algorithm SHA256).Hash.ToLowerInvariant() } else { $null }
    Add-TestResult -Name 'accepted-candidate-bytes-preserved' -Passed ($firstApplyExitCode -eq 0 -and $canonicalAcceptedSha256 -ceq [string]$initialAcceptanceResult.candidateSha256) -Detail 'Apply writes the exact reviewed candidate bytes without JSON re-encoding or byte-order changes.'

    $canonicalLockPath = "$canonicalAcceptedPath.lock"
    [IO.File]::WriteAllText($canonicalLockPath, 'owned-by-another-apply', [Text.UTF8Encoding]::new($false))
    $contendedApplyOutput = @(& pwsh -NoProfile -File $acceptanceApplyPath -RepositoryRoot $isolatedRepositoryRoot -CandidatePath $acceptedOnePath -ExpectedCandidateSha256 $initialAcceptanceResult.candidateSha256 -OutputFormat Json 2>&1)
    $contendedApplyExitCode = $LASTEXITCODE
    $contendedLockPreserved = Test-Path -LiteralPath $canonicalLockPath -PathType Leaf
    Remove-Item -LiteralPath $canonicalLockPath -Force
    Add-TestResult -Name 'contended-lock-ownership-preserved' -Passed ($contendedApplyExitCode -ne 0 -and $contendedLockPreserved -and ($contendedApplyOutput | Out-String) -like '*already being applied*') -Detail "A writer that cannot acquire the sidecar lock leaves the current lock owner's file intact."

    $stagedTwo = Get-Content -LiteralPath $firstOutputPath -Raw | ConvertFrom-Json
    $stagedTwo.records[0].content = [string]$stagedTwo.records[0].content + "`nChanged."
    $stagedTwo.records[0].contentSha256 = Get-StringSha256 -Value ([string]$stagedTwo.records[0].content)
    $stagedTwo.records = @($stagedTwo.records | Select-Object -SkipLast 1)
    $stagedTwo.collection.inventorySha256 = Get-StringSha256 -Value ($stagedTwo.records | ConvertTo-Json -Depth 30 -Compress)
    Write-JsonFixture -Path $stagedTwoPath -Value $stagedTwo

    $secondAcceptanceOutput = @(& pwsh -NoProfile -File $acceptanceExporterPath -StagedInventoryPath $stagedTwoPath -CurrentAcceptedInventoryPath $canonicalAcceptedPath -OutputPath $acceptedTwoPath -AcceptedBy 'test-maintainer' -AcceptedAt $secondAcceptedAt -OutputFormat Json 2>&1)
    $secondAcceptanceExitCode = $LASTEXITCODE
    $secondAcceptanceResult = if ($secondAcceptanceExitCode -eq 0) { ($secondAcceptanceOutput | Out-String) | ConvertFrom-Json } else { $null }
    $acceptedTwo = if ($secondAcceptanceExitCode -eq 0) { Get-Content -LiteralPath $acceptedTwoPath -Raw | ConvertFrom-Json -DateKind String } else { $null }
    Add-TestResult -Name 'acceptance-transition-classification' -Passed ($secondAcceptanceExitCode -eq 0 -and $secondAcceptanceResult.transitionCounts.'content-changed' -eq 1 -and $secondAcceptanceResult.transitionCounts.removed -eq 1) -Detail 'Acceptance classifies changed content and complete-collection removals explicitly.'
    Add-TestResult -Name 'acceptance-tombstone-history' -Passed ($null -ne $acceptedTwo -and @($acceptedTwo.records | Where-Object presence -eq 'removed').Count -eq 1 -and @($acceptedTwo.acceptedRevisions).Count -eq 1 -and [string]$acceptedTwo.acceptance.acceptedAt -ceq $expectedSecondAcceptedAt -and [string]$acceptedTwo.acceptedRevisions[0].acceptance.acceptedAt -ceq $expectedInitialAcceptedAt) -Detail 'Removal preserves last-known evidence and one complete prior accepted projection with canonical UTC timestamps.'

    $byteTamperedPath = Join-Path $acceptedFixtureRoot 'accepted-two-byte-tampered.json'
    Copy-Item -LiteralPath $acceptedTwoPath -Destination $byteTamperedPath
    [IO.File]::AppendAllText($byteTamperedPath, " `n", [Text.UTF8Encoding]::new($false))
    $byteTamperedOutput = @(& pwsh -NoProfile -File $acceptanceApplyPath -RepositoryRoot $isolatedRepositoryRoot -CandidatePath $byteTamperedPath -ExpectedCandidateSha256 $secondAcceptanceResult.candidateSha256 -OutputFormat Json 2>&1)
    $byteTamperedExitCode = $LASTEXITCODE
    Add-TestResult -Name 'candidate-byte-tampering-rejected' -Passed ($byteTamperedExitCode -ne 0 -and ($byteTamperedOutput | Out-String) -like '*candidate hash mismatch*') -Detail 'Apply rejects candidate bytes that differ from the explicitly reviewed export hash.'

    $recordTamperedPath = Join-Path $acceptedFixtureRoot 'accepted-two-record-tampered.json'
    $recordTampered = Get-Content -LiteralPath $acceptedTwoPath -Raw | ConvertFrom-Json
    $recordTampered.records[0].content = [string]$recordTampered.records[0].content + ' Tampered.'
    Write-JsonFixture -Path $recordTamperedPath -Value $recordTampered
    $recordTamperedSha256 = (Get-FileHash -LiteralPath $recordTamperedPath -Algorithm SHA256).Hash.ToLowerInvariant()
    $recordTamperedOutput = @(& pwsh -NoProfile -File $acceptanceApplyPath -RepositoryRoot $isolatedRepositoryRoot -CandidatePath $recordTamperedPath -ExpectedCandidateSha256 $recordTamperedSha256 -OutputFormat Json 2>&1)
    $recordTamperedExitCode = $LASTEXITCODE
    Add-TestResult -Name 'candidate-record-tampering-rejected' -Passed ($recordTamperedExitCode -ne 0 -and ($recordTamperedOutput | Out-String) -like '*record hash does not match*') -Detail 'Apply independently recalculates accepted record hashes even when candidate bytes were explicitly supplied.'

    $duplicateCurrentPath = Join-Path $acceptedFixtureRoot 'accepted-two-duplicate-current.json'
    $duplicateCurrent = Get-Content -LiteralPath $acceptedTwoPath -Raw | ConvertFrom-Json -DateKind String
    $duplicateCurrent.records = @($duplicateCurrent.records) + @($duplicateCurrent.records[0])
    $duplicateCurrent.collection.inventorySha256 = Get-SourceEvidenceRecordsSha256 -Records @($duplicateCurrent.records)
    Write-JsonFixture -Path $duplicateCurrentPath -Value $duplicateCurrent
    $duplicateCurrentSha256 = (Get-FileHash -LiteralPath $duplicateCurrentPath -Algorithm SHA256).Hash.ToLowerInvariant()
    $duplicateCurrentOutput = @(& pwsh -NoProfile -File $acceptanceApplyPath -RepositoryRoot $isolatedRepositoryRoot -CandidatePath $duplicateCurrentPath -ExpectedCandidateSha256 $duplicateCurrentSha256 -OutputFormat Json 2>&1)
    $duplicateCurrentExitCode = $LASTEXITCODE
    Add-TestResult -Name 'duplicate-current-source-id-rejected' -Passed ($duplicateCurrentExitCode -ne 0 -and ($duplicateCurrentOutput | Out-String) -like '*duplicate source IDs*') -Detail 'Apply rejects duplicate IDs in the current projection even when the candidate record hash is internally consistent.'

    $historyTamperedPath = Join-Path $acceptedFixtureRoot 'accepted-two-history-tampered.json'
    $historyTampered = Get-Content -LiteralPath $acceptedTwoPath -Raw | ConvertFrom-Json
    $historyTampered.acceptedRevisions[0].acceptance.acceptedBy = 'rewritten-maintainer'
    Write-JsonFixture -Path $historyTamperedPath -Value $historyTampered
    $historyTamperedSha256 = (Get-FileHash -LiteralPath $historyTamperedPath -Algorithm SHA256).Hash.ToLowerInvariant()
    $historyTamperedOutput = @(& pwsh -NoProfile -File $acceptanceApplyPath -RepositoryRoot $isolatedRepositoryRoot -CandidatePath $historyTamperedPath -ExpectedCandidateSha256 $historyTamperedSha256 -OutputFormat Json 2>&1)
    $historyTamperedExitCode = $LASTEXITCODE
    Add-TestResult -Name 'candidate-history-rewrite-rejected' -Passed ($historyTamperedExitCode -ne 0 -and ($historyTamperedOutput | Out-String) -like '*revision chain hash mismatch*') -Detail "Apply rejects a candidate whose appended revision rewrites authenticated history. Output: $(($historyTamperedOutput | Out-String).Trim())"

    $secondApplyOutput = @(& pwsh -NoProfile -File $acceptanceApplyPath -RepositoryRoot $isolatedRepositoryRoot -CandidatePath $acceptedTwoPath -ExpectedCandidateSha256 $secondAcceptanceResult.candidateSha256 -OutputFormat Json 2>&1)
    $secondApplyExitCode = $LASTEXITCODE

    $nonIncreasingOutput = @(& pwsh -NoProfile -File $acceptanceExporterPath -StagedInventoryPath $stagedTwoPath -CurrentAcceptedInventoryPath $canonicalAcceptedPath -OutputPath (Join-Path $acceptedFixtureRoot 'non-increasing.json') -AcceptedBy 'test-maintainer' -AcceptedAt $nonIncreasingAcceptedAt -OutputFormat Json 2>&1)
    $nonIncreasingExitCode = $LASTEXITCODE
    Add-TestResult -Name 'non-increasing-acceptance-rejected' -Passed ($secondApplyExitCode -eq 0 -and $nonIncreasingExitCode -ne 0 -and ($nonIncreasingOutput | Out-String) -like '*AcceptedAt must be later*') -Detail 'Acceptance events must advance monotonically and cannot reuse or move behind the current timestamp.'

    $thirdAcceptanceOutput = @(& pwsh -NoProfile -File $acceptanceExporterPath -StagedInventoryPath $stagedTwoPath -CurrentAcceptedInventoryPath $canonicalAcceptedPath -OutputPath $acceptedThreePath -AcceptedBy 'test-maintainer' -AcceptedAt $thirdAcceptedAt -OutputFormat Json 2>&1)
    $thirdAcceptanceExitCode = $LASTEXITCODE
    $acceptedThree = if ($thirdAcceptanceExitCode -eq 0) { Get-Content -LiteralPath $acceptedThreePath -Raw | ConvertFrom-Json -DateKind String } else { $null }
    $allAcceptanceTimestampsCanonical = $null -ne $acceptedThree -and [string]$acceptedThree.acceptance.acceptedAt -ceq $expectedThirdAcceptedAt -and [string]$acceptedThree.acceptedRevisions[0].acceptance.acceptedAt -ceq $expectedInitialAcceptedAt -and [string]$acceptedThree.acceptedRevisions[1].acceptance.acceptedAt -ceq $expectedSecondAcceptedAt
    Add-TestResult -Name 'accepted-history-timestamps-canonical' -Passed ($thirdAcceptanceExitCode -eq 0 -and $allAcceptanceTimestampsCanonical) -Detail 'Raw timestamps with `Z`, positive offsets, and negative offsets persist as one invariant UTC representation across current and historical acceptance records.'
    $reorderedHistory = if ($null -ne $acceptedThree) { Copy-JsonObject -Value $acceptedThree } else { $null }
    if ($null -ne $reorderedHistory) {
        $reorderedHistory.acceptedRevisions = @($reorderedHistory.acceptedRevisions[1], $reorderedHistory.acceptedRevisions[0])
    }
    Add-TestResult -Name 'reordered-acceptance-history-rejected' -Passed ($thirdAcceptanceExitCode -eq 0 -and (Test-ThrowsLike -Action { Assert-SourceEvidenceAcceptedInventoryHistory -Inventory $reorderedHistory } -Pattern '*revision*')) -Detail 'Reordering individually valid accepted revisions cannot change which evidence is treated as the immediate predecessor.'

    $duplicatedHistory = if ($null -ne $acceptedThree) { Copy-JsonObject -Value $acceptedThree } else { $null }
    if ($null -ne $duplicatedHistory) {
        $duplicatedHistory.acceptedRevisions = @($duplicatedHistory.acceptedRevisions[0], $duplicatedHistory.acceptedRevisions[0])
    }
    Add-TestResult -Name 'duplicated-acceptance-history-rejected' -Passed ($thirdAcceptanceExitCode -eq 0 -and (Test-ThrowsLike -Action { Assert-SourceEvidenceAcceptedInventoryHistory -Inventory $duplicatedHistory } -Pattern '*revision*')) -Detail 'Duplicating an otherwise valid accepted revision breaks the authenticated append chain.'

    $staleApplyOutput = @(& pwsh -NoProfile -File $acceptanceApplyPath -RepositoryRoot $isolatedRepositoryRoot -CandidatePath $acceptedOnePath -ExpectedCandidateSha256 $initialAcceptanceResult.candidateSha256 -OutputFormat Json 2>&1)
    $staleApplyExitCode = $LASTEXITCODE
    Add-TestResult -Name 'acceptance-compare-and-swap' -Passed ($secondApplyExitCode -eq 0 -and $staleApplyExitCode -ne 0 -and ($staleApplyOutput | Out-String) -like '*precondition failed*') -Detail "Apply accepts the matching prior hash and rejects stale candidates without writing. Second apply: $(($secondApplyOutput | Out-String).Trim()); stale apply: $(($staleApplyOutput | Out-String).Trim())"
}
catch {
    $issues.Add($_.Exception.Message)
}
finally {
    if (Test-Path -LiteralPath $fixtureRoot) {
        Remove-Item -LiteralPath $fixtureRoot -Recurse -Force
    }
}

$result = [ordered]@{
    status = if ($issues.Count -eq 0) { 'passed' } else { 'failed' }
    testCount = $results.Count
    issueCount = $issues.Count
    tests = $results.ToArray()
    issues = $issues.ToArray()
}

if ($OutputFormat -eq 'Json') {
    $result | ConvertTo-Json -Depth 8
}
else {
    Write-ValidationSectionHeader -Title 'Hosted source inventory test summary'
    Write-ValidationSummary -Fields ([ordered]@{
        Status = $result.status.ToUpperInvariant()
        Tests = $result.testCount
        Issues = $result.issueCount
    })
    Write-Output ''
    Write-ValidationTwoColumnTable -Rows @($result.tests) -FirstHeader 'Status' -FirstProperty 'status' -SecondHeader 'Test' -SecondProperty 'name' -FirstWidth 10 -UppercaseFirst
    if ($issues.Count -gt 0) {
        Write-Output ''
        Write-Output 'Failures:'
        foreach ($issue in $issues) {
            Write-Output "- $issue"
        }
    }
    Write-Host ''
}

if ($issues.Count -gt 0) {
    exit 1
}
