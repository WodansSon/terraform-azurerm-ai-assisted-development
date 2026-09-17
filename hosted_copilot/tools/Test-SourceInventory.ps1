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
$helpersPath = Join-Path $PSScriptRoot 'HostedToolkit.Helpers.psm1'
Import-Module -Name $helpersPath -Force
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
        [string]$DefinitionPath = $definitionPath,
        [string]$RepositoryRoot = $repoRoot
    )

    $output = @(& pwsh -NoProfile -File $collectorPath -RepositoryRoot $RepositoryRoot -SourceDefinitionPath $DefinitionPath -OutputPath $OutputPath -OutputFormat Json 2>&1)
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

    $canonicalUtcTimestamp = ConvertTo-UtcTimestamp -Value '2026-09-15T14:30:00+02:00'
    $expectedCanonicalUtcTimestamp = [datetime]::new(2026, 9, 15, 12, 30, 0, [DateTimeKind]::Utc).ToString('o', [Globalization.CultureInfo]::InvariantCulture)
    Add-TestResult -Name 'canonical-utc-timestamp' -Passed ($canonicalUtcTimestamp -ceq $expectedCanonicalUtcTimestamp) -Detail 'Source evidence timestamps use one invariant UTC round-trip representation regardless of input offset.'
    Add-TestResult -Name 'invalid-timestamp-rejected' -Passed (Test-ThrowsLike -Action { ConvertTo-UtcTimestamp -Value 'not-a-timestamp' } -Pattern '*Invalid timestamp*') -Detail 'Invalid timestamps fail through the toolkit-wide helper rather than locale-dependent coercion.'
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

    $collectorTokens = $null
    $collectorParseErrors = $null
    $collectorAst = [Management.Automation.Language.Parser]::ParseFile($collectorPath, [ref]$collectorTokens, [ref]$collectorParseErrors)
    if (@($collectorParseErrors).Count -ne 0) {
        throw 'Source inventory collector could not be parsed for focused GraphQL retry validation'
    }
    $graphQlFunctionNames = @('Test-GitHubTransientFailure', 'Get-GitHubRetryAfterMilliseconds', 'Invoke-GitHubGraphQLRequest')
    $graphQlFunctionDefinitions = @($graphQlFunctionNames | ForEach-Object {
        $functionName = $_
        $functionAst = $collectorAst.Find({
                param($node)
                $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq $functionName
            }, $true)
        if ($null -eq $functionAst) {
            throw "Source inventory collector function was not found: $functionName"
        }
        $functionAst.Extent.Text
    })
    $graphQlRetryAttemptCount = & {
        param([string[]]$FunctionDefinitions)

        foreach ($functionDefinition in $FunctionDefinitions) {
            . ([scriptblock]::Create($functionDefinition))
        }
        $script:graphQlRetryAttempts = 0
        $MaximumRequestAttempts = 2
        $RetryDelayMilliseconds = 0
        function Invoke-GitHubGraphQLRequestOnce {
            $script:graphQlRetryAttempts++
            if ($script:graphQlRetryAttempts -eq 1) {
                return [pscustomobject]@{ errors = @([pscustomobject]@{ type = 'RATE_LIMITED'; message = 'Please retry this request' }) }
            }
            return [pscustomobject]@{ data = [pscustomobject]@{ repository = [pscustomobject]@{} } }
        }
        $null = Invoke-GitHubGraphQLRequest -Request ([ordered]@{ query = 'query { viewer { login } }' })
        return $script:graphQlRetryAttempts
    } $graphQlFunctionDefinitions
    Add-TestResult -Name 'graphql-body-error-retried' -Passed ($graphQlRetryAttemptCount -eq 2) -Detail 'A structured transient GraphQL error in an HTTP-success response remains inside the bounded retry boundary.'


    Add-TestResult -Name 'source-definition-schema' -Passed (Test-JsonInstance -Json (Get-Content -LiteralPath $definitionPath -Raw) -SchemaPath $definitionSchemaPath) -Detail 'Maintainer Proposals uses the strict shared source-definition schema.'
    Add-TestResult -Name 'parser-contract-schema' -Passed (Test-JsonInstance -Json (Get-Content -LiteralPath $contractPath -Raw) -SchemaPath $contractSchemaPath) -Detail 'The Maintainer Proposals parser contract has a strict versioned shape.'
    Add-TestResult -Name 'interactive-definition-schema' -Passed (Test-JsonInstance -Json (Get-Content -LiteralPath $interactiveDefinitionPath -Raw) -SchemaPath $definitionSchemaPath) -Detail 'Interactive Toolkit uses the strict shared source-definition schema.'
    Add-TestResult -Name 'interactive-contract-schema' -Passed (Test-JsonInstance -Json (Get-Content -LiteralPath $interactiveContractPath -Raw) -SchemaPath $contractSchemaPath) -Detail 'The Interactive Toolkit parser contract has a strict versioned shape.'
    Add-TestResult -Name 'contributor-definition-schema' -Passed (Test-JsonInstance -Json (Get-Content -LiteralPath $contributorDefinitionPath -Raw) -SchemaPath $definitionSchemaPath) -Detail 'Contributor Guidance uses the strict shared source-definition schema.'
    Add-TestResult -Name 'contributor-contract-schema' -Passed (Test-JsonInstance -Json (Get-Content -LiteralPath $contributorContractPath -Raw) -SchemaPath $contractSchemaPath) -Detail 'The Contributor Guidance parser contract has a strict versioned shape.'
    $requiredParserValidationFiles = @(
        'hosted_copilot/copilot-rule-catalog/parser-contracts/parser-contract.schema.json',
        'hosted_copilot/copilot-rule-catalog/source-definitions/source-definition.schema.json',
        'hosted_copilot/copilot-rule-catalog/source-inventories/source-inventory.schema.json'
    )
    $parserContracts = @($contractPath, $interactiveContractPath, $contributorContractPath) | ForEach-Object { Get-Content -LiteralPath $_ -Raw | ConvertFrom-Json }
    $missingParserValidationFiles = @($parserContracts | ForEach-Object { $contract = $_; $requiredParserValidationFiles | Where-Object { $_ -notin @($contract.behaviorFiles) } })
    $maintainerCatalogSchemaPath = 'hosted_copilot/copilot-rule-catalog/instruction-catalog.schema.json'
    Add-TestResult -Name 'parser-validation-dependencies' -Passed ($missingParserValidationFiles.Count -eq 0 -and $maintainerCatalogSchemaPath -in @($parserContracts[0].behaviorFiles)) -Detail 'Every parser behavior identity includes its definition, contract, inventory, and parser-specific validation schemas.'

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

    $snapshotRepositoryRoot = Join-Path $fixtureRoot 'snapshot-repository'
    $snapshotCatalogRoot = Join-Path $snapshotRepositoryRoot 'hosted_copilot/copilot-rule-catalog'
    $snapshotDefinitionRoot = Join-Path $snapshotCatalogRoot 'source-definitions'
    $snapshotInventoryRoot = Join-Path $snapshotCatalogRoot 'source-inventories'
    $snapshotContractRoot = Join-Path $snapshotCatalogRoot 'parser-contracts'
    $snapshotToolsRoot = Join-Path $snapshotRepositoryRoot 'hosted_copilot/tools'
    $snapshotParserRoot = Join-Path $snapshotToolsRoot 'source-parsers'
    $snapshotSourceRoot = Join-Path $snapshotRepositoryRoot 'fixtures/rules'
    $null = New-Item -ItemType Directory -Path $snapshotDefinitionRoot, $snapshotInventoryRoot, $snapshotContractRoot, $snapshotParserRoot, $snapshotSourceRoot -Force
    Copy-Item -LiteralPath $definitionSchemaPath -Destination $snapshotDefinitionRoot
    Copy-Item -LiteralPath $inventorySchemaPath -Destination $snapshotInventoryRoot
    Copy-Item -LiteralPath $contractSchemaPath -Destination $snapshotContractRoot
    Copy-Item -LiteralPath $contractPath -Destination $snapshotContractRoot
    Copy-Item -LiteralPath $collectorPath -Destination $snapshotToolsRoot
    Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'HostedToolkit.Helpers.psm1') -Destination $snapshotToolsRoot
    Copy-Item -LiteralPath $sourceEvidenceModulePath -Destination $snapshotToolsRoot
    Copy-Item -LiteralPath (Join-Path $catalogRoot 'instruction-catalog.json') -Destination $snapshotCatalogRoot
    Copy-Item -LiteralPath (Join-Path $catalogRoot 'instruction-catalog.schema.json') -Destination $snapshotCatalogRoot
    $snapshotDefinitionPath = Join-Path $snapshotDefinitionRoot 'maintainer-proposals.json'
    Write-JsonFixture -Path $snapshotDefinitionPath -Value ([ordered]@{
        '$schema' = 'source-definition.schema.json'
        schemaVersion = 1
        id = 'maintainer-proposals'
        displayName = 'Maintainer Proposals'
        root = [ordered]@{ kind = 'repository'; path = 'fixtures/rules' }
        files = @('*.rules.md')
        exclude = @()
        parser = 'maintainer-proposals-v2'
        assessmentBatchSize = 20
    })
    $snapshotSourcePath = Join-Path $snapshotSourceRoot 'implementation.rules.md'
    $snapshotSourceContent = "---`ndescription: `"Snapshot fixture.`"`nsurface: implementation`n---`n`n# Snapshot fixture`n`n### IMPL-SNAPSHOT-900: Snapshot rule`n`n- Rule: Preserve original source bytes.`n- Provenance: local-safeguard`n- Rationale: Parsing and hashing must use one source version.`n"
    $mutatedSourceContent = $snapshotSourceContent.Replace('Preserve original source bytes.', 'Use mutated source bytes.')
    [IO.File]::WriteAllText($snapshotSourcePath, $snapshotSourceContent, [Text.UTF8Encoding]::new($false))
    $snapshotMutationMarkerPath = Join-Path $fixtureRoot 'snapshot-mutation.marker'
    $snapshotParserContent = Get-Content -LiteralPath $parserModulePath -Raw
    $snapshotParserContent = $snapshotParserContent.Replace(
        '        $content = [IO.File]::ReadAllText($sourcePath).Replace("`r`n", "`n").Replace("`r", "`n")',
        @'
        if ($RepositoryRoot -like '*hosted-source-inventory-snapshot-*' -and -not (Test-Path -LiteralPath $env:SOURCE_INVENTORY_MUTATION_MARKER)) {
            [IO.File]::WriteAllText($env:SOURCE_INVENTORY_MUTATE_PATH, $env:SOURCE_INVENTORY_MUTATED_CONTENT, [Text.UTF8Encoding]::new($false))
            [IO.File]::WriteAllText($env:SOURCE_INVENTORY_MUTATION_MARKER, 'mutated', [Text.UTF8Encoding]::new($false))
        }
        $content = [IO.File]::ReadAllText($sourcePath).Replace("`r`n", "`n").Replace("`r", "`n")
'@.TrimEnd())
    [IO.File]::WriteAllText((Join-Path $snapshotParserRoot 'MaintainerProposalsV2.psm1'), $snapshotParserContent, [Text.UTF8Encoding]::new($false))
    $snapshotSourceSha256 = (Get-FileHash -LiteralPath $snapshotSourcePath -Algorithm SHA256).Hash.ToLowerInvariant()
    $snapshotRevisionIdentity = 'fixtures/rules/implementation.rules.md' + [char]0 + $snapshotSourceSha256 + [char]0
    $expectedSnapshotWorktreeSha256 = Get-StringSha256 -Value $snapshotRevisionIdentity
    $snapshotOutputPath = Join-Path $fixtureRoot 'snapshot-inventory.json'
    $env:SOURCE_INVENTORY_MUTATE_PATH = $snapshotSourcePath
    $env:SOURCE_INVENTORY_MUTATED_CONTENT = $mutatedSourceContent
    $env:SOURCE_INVENTORY_MUTATION_MARKER = $snapshotMutationMarkerPath
    try {
        $snapshotRun = Invoke-Collector -RepositoryRoot $snapshotRepositoryRoot -DefinitionPath $snapshotDefinitionPath -OutputPath $snapshotOutputPath
    }
    finally {
        Remove-Item Env:SOURCE_INVENTORY_MUTATE_PATH -ErrorAction SilentlyContinue
        Remove-Item Env:SOURCE_INVENTORY_MUTATED_CONTENT -ErrorAction SilentlyContinue
        Remove-Item Env:SOURCE_INVENTORY_MUTATION_MARKER -ErrorAction SilentlyContinue
    }
    $snapshotInventory = if ($snapshotRun.ExitCode -eq 0) { Get-Content -LiteralPath $snapshotOutputPath -Raw | ConvertFrom-Json } else { $null }
    $snapshotMutationObserved = (Test-Path -LiteralPath $snapshotMutationMarkerPath -PathType Leaf) -and [IO.File]::ReadAllText($snapshotSourcePath).Contains('Use mutated source bytes.')
    $snapshotEvidenceConsistent = $null -ne $snapshotInventory -and [string]$snapshotInventory.records[0].ruleText -ceq 'Preserve original source bytes.' -and [string]$snapshotInventory.collection.sourceRevision.worktreeSha256 -ceq $expectedSnapshotWorktreeSha256
    Add-TestResult -Name 'local-parser-snapshot-consistency' -Passed ($snapshotRun.ExitCode -eq 0 -and $snapshotMutationObserved -and $snapshotEvidenceConsistent) -Detail 'Parser-time mutation of the original local source cannot split inventory records from their mirrored worktree hash.'

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

    $inventory = Get-Content -LiteralPath $firstOutputPath -Raw | ConvertFrom-Json -DateKind String
    Add-TestResult -Name 'inventory-collection-only' -Passed ($null -eq $inventory.PSObject.Properties['acceptance'] -and $null -eq $inventory.PSObject.Properties['acceptedRevisions']) -Detail 'Staged inventory contains collection facts and records without per-lane acceptance or revision state.'

    $inventoryWithAcceptance = Copy-JsonObject -Value $inventory
    $inventoryWithAcceptance | Add-Member -NotePropertyName acceptance -NotePropertyValue $null
    $inventoryWithAcceptanceValid = Test-JsonInstance -Json ($inventoryWithAcceptance | ConvertTo-Json -Depth 30) -SchemaPath $inventorySchemaPath
    Add-TestResult -Name 'inventory-acceptance-fields-rejected' -Passed (-not $inventoryWithAcceptanceValid) -Detail 'The collection-only inventory schema rejects legacy per-lane acceptance fields.'

    $currentEvidence = Get-CurrentSourceDefinitionEvidence -RepositoryRoot $repoRoot -SourceDefinitionId 'maintainer-proposals'
    $displayOnlyEvidence = $currentEvidence | Select-Object *
    $displayOnlyEvidence.SourceDefinitionSha256 = 'e' * 64
    Add-TestResult -Name 'display-only-definition-change' -Passed (Test-DoesNotThrow -Action { Assert-CurrentSourceInventory -Inventory $inventory -Evidence $displayOnlyEvidence }) -Detail 'A changed audit-only source-definition hash does not invalidate collection facts when factual configuration is unchanged.'

    $staleConfigurationEvidence = $currentEvidence | Select-Object *
    $staleConfigurationEvidence.InventoryConfigurationSha256 = 'e' * 64
    Add-TestResult -Name 'inventory-configuration-drift-rejected' -Passed (Test-ThrowsLike -Action { Assert-CurrentSourceInventory -Inventory $inventory -Evidence $staleConfigurationEvidence } -Pattern '*configuration hash is stale*') -Detail 'A changed inventory-affecting configuration invalidates the staged inventory.'

    $staleParserEvidence = $currentEvidence | Select-Object *
    $staleParserEvidence.ParserContractSha256 = 'e' * 64
    Add-TestResult -Name 'parser-contract-drift-rejected' -Passed (Test-ThrowsLike -Action { Assert-CurrentSourceInventory -Inventory $inventory -Evidence $staleParserEvidence } -Pattern '*parser contract hash is stale*') -Detail 'A changed parser behavior contract invalidates the staged inventory.'

    $recordTampered = Copy-JsonObject -Value $inventory
    $recordTampered.records[0].content = [string]$recordTampered.records[0].content + ' Tampered.'
    Add-TestResult -Name 'inventory-record-tampering-rejected' -Passed (Test-ThrowsLike -Action { Assert-CurrentSourceInventory -Inventory $recordTampered -Evidence $currentEvidence } -Pattern '*record hash does not match*') -Detail 'Inventory validation independently rejects record content that no longer matches the collection hash.'

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
