[CmdletBinding()]
param(
    [ValidateSet('Text', 'Json')]
    [string]$OutputFormat = 'Text'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$validationOutputModulePath = Join-Path $PSScriptRoot '../../../tools/ValidationOutput.psm1'
Import-Module -Name $validationOutputModulePath -Force

$hostedRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
$generatorPath = Join-Path $PSScriptRoot '../commands/catalog/Generate-Instructions.ps1'
$protectedGeneratorPath = Join-Path $PSScriptRoot '../commands/catalog/Generate-ProtectedRules.ps1'
$sourceCatalogPath = Join-Path $hostedRoot 'copilot-rule-catalog/instruction-catalog.json'
$sourceSchemaPath = Join-Path $hostedRoot 'copilot-rule-catalog/instruction-catalog.schema.json'
$sourceProtectedRulesPath = Join-Path $hostedRoot 'copilot-rule-catalog/protected-rules.json'
$sourceProtectedRulesSchemaPath = Join-Path $hostedRoot 'copilot-rule-catalog/protected-rules.schema.json'
$sourceProtectedRulesRoot = Join-Path $hostedRoot 'authored-rules/protected'
$results = New-Object 'System.Collections.Generic.List[object]'
$issues = New-Object 'System.Collections.Generic.List[string]'
$tempRoot = Join-Path ([IO.Path]::GetTempPath()) ("hosted-instruction-generation-{0}" -f [Guid]::NewGuid().ToString('N'))
$tempHostedRoot = Join-Path $tempRoot 'hosted_copilot'

if ($OutputFormat -eq 'Text') {
    Write-ValidationSectionHeader -Title 'Hosted instruction generation'
}

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

function Write-TestProgress {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][string]$Detail
    )

    if ($OutputFormat -eq 'Text') {
        Write-Host (Format-ValidationStatusLine -Status 'running' -Name $Name -Detail $Detail)
    }
}

function Invoke-Generator {
    param([switch]$Write)

    $arguments = @(
        '-NoProfile',
        '-File', $generatorPath,
        '-CatalogPath', (Join-Path $tempHostedRoot 'copilot-rule-catalog/instruction-catalog.json'),
        '-ProtectedRulesPath', (Join-Path $tempHostedRoot 'copilot-rule-catalog/protected-rules.json'),
        '-ProtectedRulesSourceRoot', (Join-Path $tempHostedRoot 'authored-rules/protected'),
        '-HostedRoot', $tempHostedRoot,
        '-OutputFormat', 'Json'
    )
    if ($Write) {
        $arguments += '-Write'
    }

    $global:LASTEXITCODE = 0
    $output = @(& pwsh @arguments 2>&1)
    $exitCode = if ($null -ne $LASTEXITCODE) { $LASTEXITCODE } else { 0 }
    $global:LASTEXITCODE = 0

    [pscustomobject]@{
        exitCode = $exitCode
        output = ($output | Out-String).Trim()
    }
}

function Invoke-ProtectedGenerator {
    $arguments = @(
        '-NoProfile',
        '-File', $protectedGeneratorPath,
        '-SourceRoot', (Join-Path $tempHostedRoot 'authored-rules/protected'),
        '-RepositoryRoot', $tempRoot,
        '-OutputPath', (Join-Path $tempHostedRoot 'copilot-rule-catalog/protected-rules.json'),
        '-Write',
        '-OutputFormat', 'Json'
    )
    $global:LASTEXITCODE = 0
    $output = @(& pwsh @arguments 2>&1)
    $exitCode = if ($null -ne $LASTEXITCODE) { $LASTEXITCODE } else { 0 }
    $global:LASTEXITCODE = 0
    return [pscustomobject]@{ exitCode = $exitCode; output = ($output | Out-String).Trim() }
}

try {
    Write-TestProgress -Name 'fixture-preparation' -Detail 'Staging the catalog, schema, and generated instruction files'
    $catalogDirectory = Join-Path $tempHostedRoot 'copilot-rule-catalog'
    New-Item -ItemType Directory -Path $catalogDirectory -Force | Out-Null
    Copy-Item -LiteralPath $sourceCatalogPath -Destination (Join-Path $catalogDirectory 'instruction-catalog.json')
    Copy-Item -LiteralPath $sourceSchemaPath -Destination (Join-Path $catalogDirectory 'instruction-catalog.schema.json')
    Copy-Item -LiteralPath $sourceProtectedRulesPath -Destination (Join-Path $catalogDirectory 'protected-rules.json')
    Copy-Item -LiteralPath $sourceProtectedRulesSchemaPath -Destination (Join-Path $catalogDirectory 'protected-rules.schema.json')
    $tempProtectedRulesRoot = Join-Path $tempHostedRoot 'authored-rules/protected'
    New-Item -ItemType Directory -Path $tempProtectedRulesRoot -Force | Out-Null
    Copy-Item -Path (Join-Path $sourceProtectedRulesRoot '*.rules.md') -Destination $tempProtectedRulesRoot

    $catalog = Get-Content -LiteralPath $sourceCatalogPath -Raw | ConvertFrom-Json
    $protectedRules = Get-Content -LiteralPath $sourceProtectedRulesPath -Raw | ConvertFrom-Json
    foreach ($surface in @($catalog.surfaces)) {
        $sourcePath = Join-Path $hostedRoot ([string]$surface.outputPath)
        $targetPath = Join-Path $tempHostedRoot ([string]$surface.outputPath)
        New-Item -ItemType Directory -Path (Split-Path -Parent $targetPath) -Force | Out-Null
        Copy-Item -LiteralPath $sourcePath -Destination $targetPath
    }

    Write-TestProgress -Name 'baseline-generation' -Detail 'Checking committed instructions against the current catalog'
    $baseline = Invoke-Generator
    Add-TestResult -Name 'baseline-freshness' -Passed ($baseline.exitCode -eq 0) -Detail $(if ($baseline.exitCode -eq 0) { 'Current catalog reproduces all committed instruction files.' } else { $baseline.output })

    $implementationOutputPath = Join-Path $tempHostedRoot ([string]$catalog.surfaces[0].outputPath)
    $implementationOutput = Get-Content -LiteralPath $implementationOutputPath -Raw
    $modelRenderingPassed = $implementationOutput.Contains('- `[IMPL-WF-002B]` [legacy, typed]') -and
        $implementationOutput.Contains('- `[IMPL-SCHEMA-008]` [legacy, typed]') -and
        $implementationOutput.Contains('- `[IMPL-PATCH-001]` [legacy, typed]') -and
        $implementationOutput.Contains('- `[IMPL-SCHEMA-007]` [legacy, typed, framework]') -and
        $implementationOutput.Contains('- `[IMPL-WF-000]` Classify implementation code as legacy, typed, or framework before applying resource-type-specific rules or suggesting changes.') -and
        $implementationOutput.Contains('Use typed patterns for current ordinary resource and data source work, and framework patterns for framework-native or specialized surfaces.') -and
        -not $implementationOutput.Contains('- `[IMPL-WF-001A]`') -and
        $implementationOutput.Contains('## Protected Rules') -and
        $implementationOutput.Contains('## Evidence And Resource Type') -and
        -not $implementationOutput.Contains('# AzureRM Go Review Rules:')
    Add-TestResult -Name 'implementation-model-rendering' -Passed $modelRenderingPassed -Detail $(if ($modelRenderingPassed) { 'Generated implementation rules preserve model-specific applicability.' } else { 'Generated implementation model markers are missing or incorrect.' })

    Write-TestProgress -Name 'catalog-behavior' -Detail 'Validating model applicability and catalog-native rule origins'
    $tempCatalogPath = Join-Path $catalogDirectory 'instruction-catalog.json'
    $tempProtectedRulesPath = Join-Path $catalogDirectory 'protected-rules.json'
    $catalog.rules[0].origin = 'hosted-catalog-addition'
    $catalog | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $tempCatalogPath -Encoding utf8NoBOM
    $catalogAddition = Invoke-Generator
    Add-TestResult -Name 'catalog-addition-origin' -Passed ($catalogAddition.exitCode -eq 0) -Detail $(if ($catalogAddition.exitCode -eq 0) { 'Catalog-native rule origin passes schema validation without changing output.' } else { $catalogAddition.output })

    $missingMappingCatalog = $catalog | ConvertTo-Json -Depth 20 | ConvertFrom-Json
    $missingMappingCatalog.canonicalCandidateMappings.PSObject.Properties.Remove([string]$missingMappingCatalog.rules[0].id)
    $missingMappingCatalog | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $tempCatalogPath -Encoding utf8NoBOM
    $missingMapping = Invoke-Generator
    Add-TestResult -Name 'canonical-mapping-complete' -Passed ($missingMapping.exitCode -ne 0 -and $missingMapping.output -like '*must cover every catalog rule exactly*') -Detail $(if ($missingMapping.exitCode -ne 0) { 'A catalog rule without canonical source ownership fails closed.' } else { 'Missing canonical source ownership was accepted.' })

    $duplicateMappingCatalog = $catalog | ConvertTo-Json -Depth 20 | ConvertFrom-Json
    $firstRuleId = [string]$duplicateMappingCatalog.rules[0].id
    $secondRuleId = [string]$duplicateMappingCatalog.rules[1].id
    $duplicateMappingCatalog.canonicalCandidateMappings.$secondRuleId = $duplicateMappingCatalog.canonicalCandidateMappings.$firstRuleId
    $duplicateMappingCatalog | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $tempCatalogPath -Encoding utf8NoBOM
    $duplicateMapping = Invoke-Generator
    Add-TestResult -Name 'canonical-mapping-one-to-one' -Passed ($duplicateMapping.exitCode -ne 0 -and $duplicateMapping.output -like '*assigned to more than one catalog rule*') -Detail $(if ($duplicateMapping.exitCode -ne 0) { 'A canonical source candidate cannot own multiple catalog rules.' } else { 'Duplicate canonical source ownership was accepted.' })

    $implementationCatalogRuleId = [string]$catalog.surfaces[0].sections[0].ruleIds[0]
    $tempProtectedImplementationPath = Join-Path $tempProtectedRulesRoot 'implementation.rules.md'
    $protectedImplementationContent = [IO.File]::ReadAllText($tempProtectedImplementationPath)
    [IO.File]::WriteAllText($tempProtectedImplementationPath, $protectedImplementationContent.Replace('### IMPL-WF-000:', "### $implementationCatalogRuleId`:") , [Text.UTF8Encoding]::new($false))
    $collidingProjection = Invoke-ProtectedGenerator
    $protectedCollision = if ($collidingProjection.exitCode -eq 0) { Invoke-Generator } else { $collidingProjection }
    Add-TestResult -Name 'protected-rule-id-collision' -Passed ($protectedCollision.exitCode -ne 0 -and $protectedCollision.output -like '*defined by both lifecycle and protected sources*') -Detail $(if ($protectedCollision.exitCode -ne 0) { 'Protected rule IDs cannot collide with lifecycle-managed catalog rules.' } else { 'A protected rule reused a lifecycle-managed rule ID.' })

    [IO.File]::WriteAllText($tempProtectedImplementationPath, $protectedImplementationContent, [Text.UTF8Encoding]::new($false))
    $restoredProjection = Invoke-ProtectedGenerator
    if ($restoredProjection.exitCode -ne 0) {
        throw $restoredProjection.output
    }
    Add-TestResult -Name 'protected-rule-impact' -Passed ([int]$protectedRules.rules[0].impact -eq 100) -Detail 'Protected source compilation fixes impact at 100 without requiring an authored field.'

    $catalog | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $tempCatalogPath -Encoding utf8NoBOM

    Write-TestProgress -Name 'write-boundaries' -Detail 'Checking read-only stale detection, explicit writes, and schema enforcement'
    $firstOutputPath = Join-Path $tempHostedRoot ([string]$catalog.surfaces[0].outputPath)
    $beforeStaleHash = (Get-FileHash -LiteralPath $firstOutputPath -Algorithm SHA256).Hash
    $catalog.rules[0].text = "$($catalog.rules[0].text) Regression probe."
    $catalog | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $tempCatalogPath -Encoding utf8NoBOM
    $staleCheck = Invoke-Generator
    $afterStaleHash = (Get-FileHash -LiteralPath $firstOutputPath -Algorithm SHA256).Hash
    $staleReadOnlyPassed = $staleCheck.exitCode -ne 0 -and $beforeStaleHash -eq $afterStaleHash
    Add-TestResult -Name 'stale-check-read-only' -Passed $staleReadOnlyPassed -Detail $(if ($staleReadOnlyPassed) { 'Check mode detects stale output without modifying it.' } else { 'Check mode did not fail read-only for stale output.' })

    $writeResult = Invoke-Generator -Write
    $afterWriteHash = (Get-FileHash -LiteralPath $firstOutputPath -Algorithm SHA256).Hash
    $writePassed = $writeResult.exitCode -eq 0 -and $afterWriteHash -ne $beforeStaleHash
    Add-TestResult -Name 'explicit-write' -Passed $writePassed -Detail $(if ($writePassed) { 'Write mode updates stale generated output explicitly.' } else { $writeResult.output })

    $catalog.rules[0].PSObject.Properties.Remove('implementationModels')
    $catalog | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $tempCatalogPath -Encoding utf8NoBOM
    $missingModelMetadata = Invoke-Generator
    Add-TestResult -Name 'implementation-model-required' -Passed ($missingModelMetadata.exitCode -ne 0) -Detail $(if ($missingModelMetadata.exitCode -ne 0) { 'Implementation rules without model applicability fail schema validation.' } else { 'Implementation rule model applicability was not enforced.' })
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
    Write-ValidationSectionHeader -Title 'Hosted instruction generation test summary'
    Write-ValidationSummary -Fields ([ordered]@{
        Status = $result.status.ToUpperInvariant()
        Tests = $result.testCount
        'Issue Count' = $result.issueCount
    })
    Write-ValidationSectionHeader -Title 'Generation tests'
    Write-ValidationTwoColumnTable -Rows @($results.ToArray()) -FirstHeader 'status' -FirstProperty 'status' -SecondHeader 'test' -SecondProperty 'name' -UppercaseFirst
    if ($issues.Count -gt 0) {
        Write-ValidationSectionHeader -Title 'Failures'
        foreach ($issue in $issues) {
            Write-Output "  - $issue"
        }
    }
    Complete-ValidationTextOutput
}

if ($result.status -eq 'failed') {
    exit 1
}
