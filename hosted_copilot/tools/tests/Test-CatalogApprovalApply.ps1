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
$applyPath = Join-Path $PSScriptRoot '../commands/catalog/Apply-HostedRuleApproval.ps1'
$generatorPath = Join-Path $PSScriptRoot '../commands/catalog/Generate-Instructions.ps1'
$protectedGeneratorPath = Join-Path $PSScriptRoot '../commands/catalog/Generate-ProtectedRules.ps1'
$sourceCatalogRoot = Join-Path $hostedRoot 'copilot-rule-catalog'
$sourceProtectedRulesRoot = Join-Path $hostedRoot 'authored-rules/protected'
$results = [Collections.Generic.List[object]]::new()
$issues = [Collections.Generic.List[string]]::new()
$tempRoot = Join-Path ([IO.Path]::GetTempPath()) ('hosted-catalog-approval-test-' + [guid]::NewGuid().ToString('N'))

if ($OutputFormat -eq 'Text') {
    Write-ValidationSectionHeader -Title 'Hosted catalog approval apply'
}

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

function Write-TestProgress {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][string]$Detail
    )

    if ($OutputFormat -eq 'Text') {
        Write-Host (Format-ValidationStatusLine -Status 'running' -Name $Name -Detail $Detail)
    }
}

function Get-Sha256 {
    param([Parameter(Mandatory = $true)][string]$Path)

    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function Write-JsonFixture {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][object]$Value
    )

    [IO.File]::WriteAllText($Path, (($Value | ConvertTo-Json -Depth 100) + "`n"), [Text.UTF8Encoding]::new($false))
}

function New-TestHostedRoot {
    param([Parameter(Mandatory = $true)][string]$Name)

    $repositoryRoot = Join-Path $tempRoot $Name
    $root = Join-Path $repositoryRoot 'hosted_copilot'
    $catalogRoot = Join-Path $root 'copilot-rule-catalog'
    $approvalRoot = Join-Path $catalogRoot 'assessment-reconciliation'
    New-Item -ItemType Directory -Path $approvalRoot -Force | Out-Null
    Copy-Item -LiteralPath (Join-Path $sourceCatalogRoot 'instruction-catalog.json') -Destination (Join-Path $catalogRoot 'instruction-catalog.json')
    Copy-Item -LiteralPath (Join-Path $sourceCatalogRoot 'instruction-catalog.schema.json') -Destination (Join-Path $catalogRoot 'instruction-catalog.schema.json')
    Copy-Item -LiteralPath (Join-Path $sourceCatalogRoot 'protected-rules.schema.json') -Destination (Join-Path $catalogRoot 'protected-rules.schema.json')
    $protectedRulesRoot = Join-Path $root 'authored-rules/protected'
    New-Item -ItemType Directory -Path $protectedRulesRoot -Force | Out-Null
    Copy-Item -Path (Join-Path $sourceProtectedRulesRoot '*.rules.md') -Destination $protectedRulesRoot
    $protectedGenerationOutput = @(& pwsh -NoProfile -File $protectedGeneratorPath -SourceRoot $protectedRulesRoot -RepositoryRoot $repositoryRoot -OutputPath (Join-Path $catalogRoot 'protected-rules.json') -Write -OutputFormat Json 2>&1)
    if ($LASTEXITCODE -ne 0) {
        throw (($protectedGenerationOutput | Out-String).Trim())
    }
    Copy-Item -LiteralPath (Join-Path $sourceCatalogRoot 'assessment-reconciliation/approved-rules-v4.schema.json') -Destination (Join-Path $approvalRoot 'approved-rules-v4.schema.json')
    $catalog = Get-Content -LiteralPath (Join-Path $catalogRoot 'instruction-catalog.json') -Raw | ConvertFrom-Json -DateKind String
    foreach ($surface in @($catalog.surfaces)) {
        $sourcePath = Join-Path $hostedRoot ([string]$surface.outputPath)
        $targetPath = Join-Path $root ([string]$surface.outputPath)
        New-Item -ItemType Directory -Path (Split-Path -Parent $targetPath) -Force | Out-Null
        Copy-Item -LiteralPath $sourcePath -Destination $targetPath
    }
    return $root
}

function New-Approval {
    param(
        [Parameter(Mandatory = $true)][string]$HostedFixtureRoot,
        [string]$CatalogSha256 = (Get-Sha256 -Path (Join-Path $HostedFixtureRoot 'copilot-rule-catalog/instruction-catalog.json'))
    )

    return [ordered]@{
        '$schema' = 'approved-rules-v4.schema.json'
        schemaVersion = 4
        kind = 'hosted-approved-rules'
        catalogContentSha256 = $CatalogSha256
        approvedAt = '2026-09-23T12:00:00.0000000Z'
        approvedBy = [ordered]@{
            type = 'manual'
            id = 'fixture-maintainer'
            displayName = 'Fixture Maintainer'
        }
        mutations = @([ordered]@{
            action = 'add'
            rationale = 'Approve the fixture implementation rule.'
            rule = [ordered]@{
                id = 'IMPL-WF-999'
                origin = 'hosted-catalog-addition'
                status = 'active'
                text = 'Apply the fixture lifecycle safeguard to legacy and typed resources.'
                provenance = @('local-safeguard')
                evidenceIds = @('implementation-contract', 'hosted-architecture')
                implementationModels = @('legacy', 'typed')
                selectionFactors = [ordered]@{
                    scoringStatus = 'scored'
                    severity = 4
                    frequency = 3
                    breadth = 3
                    hostedDetectability = 5
                    evidenceStrength = 4
                    falsePositiveRisk = 1
                    redundancy = 1
                }
                selectionRationale = 'The fixture rule is focused and directly reviewable.'
            }
            canonicalCandidate = [ordered]@{
                sourceDefinitionId = 'maintainer-proposals'
                sourceId = 'IMPL-WF-999'
                assessmentId = 'fixture-lifecycle'
            }
            placements = @([ordered]@{
                surfaceId = 'implementation'
                sectionHeading = 'Create And Import Behavior'
            })
            sourceRelationships = @([ordered]@{
                sourceDefinitionId = 'maintainer-proposals'
                sourceId = 'IMPL-WF-999'
                relationshipKind = 'supports'
                rationale = 'The proposal supports the approved fixture rule.'
            })
        })
    }
}

function Invoke-Apply {
    param(
        [Parameter(Mandatory = $true)][string]$HostedFixtureRoot,
        [Parameter(Mandatory = $true)][string]$ApprovalPath,
        [int]$FailAfterReplace = 0
    )

    $previousFailureInjection = $env:HOSTED_CATALOG_APPLY_TEST_FAIL_AFTER_REPLACE
    try {
        if ($FailAfterReplace -gt 0) {
            $env:HOSTED_CATALOG_APPLY_TEST_FAIL_AFTER_REPLACE = [string]$FailAfterReplace
        }
        else {
            Remove-Item Env:HOSTED_CATALOG_APPLY_TEST_FAIL_AFTER_REPLACE -ErrorAction SilentlyContinue
        }
        $global:LASTEXITCODE = 0
        $output = @(& pwsh -NoProfile -File $applyPath -ApprovalPath $ApprovalPath -CatalogPath (Join-Path $HostedFixtureRoot 'copilot-rule-catalog/instruction-catalog.json') -ProtectedRulesPath (Join-Path $HostedFixtureRoot 'copilot-rule-catalog/protected-rules.json') -ProtectedRulesSourceRoot (Join-Path $HostedFixtureRoot 'authored-rules/protected') -HostedRoot $HostedFixtureRoot -OutputFormat Json 2>&1)
        $exitCode = if ($null -ne $LASTEXITCODE) { $LASTEXITCODE } else { 0 }
        $global:LASTEXITCODE = 0
        return [pscustomobject]@{
            exitCode = $exitCode
            output = ($output | Out-String).Trim()
        }
    }
    finally {
        if ($null -eq $previousFailureInjection) {
            Remove-Item Env:HOSTED_CATALOG_APPLY_TEST_FAIL_AFTER_REPLACE -ErrorAction SilentlyContinue
        }
        else {
            $env:HOSTED_CATALOG_APPLY_TEST_FAIL_AFTER_REPLACE = $previousFailureInjection
        }
    }
}

function Get-TargetHashes {
    param([Parameter(Mandatory = $true)][string]$HostedFixtureRoot)

    $catalog = Get-Content -LiteralPath (Join-Path $HostedFixtureRoot 'copilot-rule-catalog/instruction-catalog.json') -Raw | ConvertFrom-Json
    $paths = @(
        (Join-Path $HostedFixtureRoot 'copilot-rule-catalog/instruction-catalog.json'),
        (Join-Path $HostedFixtureRoot 'copilot-rule-catalog/protected-rules.json')
    ) + @(Get-ChildItem -LiteralPath (Join-Path $HostedFixtureRoot 'authored-rules/protected') -Filter '*.rules.md' -File | Select-Object -ExpandProperty FullName) + @($catalog.surfaces | ForEach-Object { Join-Path $HostedFixtureRoot ([string]$_.outputPath) })
    return @($paths | ForEach-Object { Get-Sha256 -Path $_ })
}

try {
    Write-TestProgress -Name 'schema-failure' -Detail 'Rejecting malformed approval before writes'
    $invalidRoot = New-TestHostedRoot -Name 'invalid-schema'
    $invalidApprovalPath = Join-Path $invalidRoot 'invalid-approved-rules.json'
    $invalidApproval = New-Approval -HostedFixtureRoot $invalidRoot
    $invalidApproval.mutations = @()
    Write-JsonFixture -Path $invalidApprovalPath -Value $invalidApproval
    $invalidBefore = Get-TargetHashes -HostedFixtureRoot $invalidRoot
    $invalidResult = Invoke-Apply -HostedFixtureRoot $invalidRoot -ApprovalPath $invalidApprovalPath
    $invalidAfter = Get-TargetHashes -HostedFixtureRoot $invalidRoot
    Add-TestResult -Name 'invalid-schema-read-only' -Passed ($invalidResult.exitCode -ne 0 -and (@(Compare-Object $invalidBefore $invalidAfter).Count -eq 0)) -Detail $(if ($invalidResult.exitCode -ne 0) { 'Malformed approval failed without changing catalog-owned files.' } else { 'Malformed approval was accepted.' })

    Write-TestProgress -Name 'catalog-precondition' -Detail 'Rejecting stale catalog hash before writes'
    $staleRoot = New-TestHostedRoot -Name 'stale-hash'
    $staleApprovalPath = Join-Path $staleRoot 'stale-approved-rules.json'
    Write-JsonFixture -Path $staleApprovalPath -Value (New-Approval -HostedFixtureRoot $staleRoot -CatalogSha256 ('0' * 64))
    $staleBefore = Get-TargetHashes -HostedFixtureRoot $staleRoot
    $staleResult = Invoke-Apply -HostedFixtureRoot $staleRoot -ApprovalPath $staleApprovalPath
    $staleAfter = Get-TargetHashes -HostedFixtureRoot $staleRoot
    Add-TestResult -Name 'stale-hash-read-only' -Passed ($staleResult.exitCode -ne 0 -and $staleResult.output -like '*catalog precondition failed*' -and @(Compare-Object $staleBefore $staleAfter).Count -eq 0) -Detail $(if ($staleResult.exitCode -ne 0) { 'Stale approval failed without changing catalog-owned files.' } else { 'Stale approval was accepted.' })

    Write-TestProgress -Name 'protected-boundary' -Detail 'Rejecting protected rule IDs before writes'
    $protectedRoot = New-TestHostedRoot -Name 'protected-rule'
    $protectedApprovalPath = Join-Path $protectedRoot 'protected-approved-rules.json'
    $protectedApproval = New-Approval -HostedFixtureRoot $protectedRoot
    $protectedApproval.mutations[0].rule.id = 'IMPL-WF-000'
    Write-JsonFixture -Path $protectedApprovalPath -Value $protectedApproval
    $protectedBefore = Get-TargetHashes -HostedFixtureRoot $protectedRoot
    $protectedResult = Invoke-Apply -HostedFixtureRoot $protectedRoot -ApprovalPath $protectedApprovalPath
    $protectedAfter = Get-TargetHashes -HostedFixtureRoot $protectedRoot
    Add-TestResult -Name 'protected-rule-read-only' -Passed ($protectedResult.exitCode -ne 0 -and $protectedResult.output -like '*cannot mutate protected rule IDs*' -and @(Compare-Object $protectedBefore $protectedAfter).Count -eq 0) -Detail $(if ($protectedResult.exitCode -ne 0) { 'Protected rule mutation failed without changing catalog-owned files.' } else { 'A protected rule mutation was accepted.' })

    Write-TestProgress -Name 'successful-apply' -Detail 'Applying one rule through staged generation and atomic replacement'
    $successRoot = New-TestHostedRoot -Name 'success'
    $successApprovalPath = Join-Path $successRoot 'approved-rules.json'
    Write-JsonFixture -Path $successApprovalPath -Value (New-Approval -HostedFixtureRoot $successRoot)
    $successResult = Invoke-Apply -HostedFixtureRoot $successRoot -ApprovalPath $successApprovalPath
    $successCatalogPath = Join-Path $successRoot 'copilot-rule-catalog/instruction-catalog.json'
    $successCatalogContent = Get-Content -LiteralPath $successCatalogPath -Raw
    $successCatalog = $successCatalogContent | ConvertFrom-Json
    $appliedRule = @($successCatalog.rules | Where-Object id -eq 'IMPL-WF-999')
    $placement = @($successCatalog.surfaces | Where-Object id -eq 'implementation').sections | Where-Object heading -eq 'Create And Import Behavior'
    $generatedImplementation = Get-Content -LiteralPath (Join-Path $successRoot '.github/instructions/azurerm-go.instructions.md') -Raw
    $successPassed = $successResult.exitCode -eq 0 -and $appliedRule.Count -eq 1 -and
        (@($appliedRule[0].sourceIds).Count -eq 0) -and
        ('IMPL-WF-999' -in @($placement.ruleIds)) -and
        $null -ne $successCatalog.canonicalCandidateMappings.'IMPL-WF-999' -and
        $successCatalog.lastSemanticReview -ceq '2026-09-23' -and
        -not $successCatalogContent.Contains('sourceRelationships') -and
        $generatedImplementation.Contains('- `[IMPL-WF-999]` [legacy, typed] Apply the fixture lifecycle safeguard')
    Add-TestResult -Name 'approved-add-projection' -Passed $successPassed -Detail $(if ($successPassed) { 'Approved Add updated the catalog, placement, mapping, model scope, and generated instruction without persisting source relationships.' } else { $successResult.output })

    $generationOutput = @(& pwsh -NoProfile -File $generatorPath -CatalogPath $successCatalogPath -ProtectedRulesPath (Join-Path $successRoot 'copilot-rule-catalog/protected-rules.json') -ProtectedRulesSourceRoot (Join-Path $successRoot 'authored-rules/protected') -HostedRoot $successRoot -OutputFormat Json 2>&1)
    $generationValid = $LASTEXITCODE -eq 0 -and (($generationOutput | Out-String) | ConvertFrom-Json).success
    $global:LASTEXITCODE = 0
    Add-TestResult -Name 'applied-generation-fresh' -Passed $generationValid -Detail $(if ($generationValid) { 'Applied catalog reproduces byte-identical generated instructions.' } else { ($generationOutput | Out-String).Trim() })

    Write-TestProgress -Name 'replacement-rollback' -Detail 'Injecting a mid-replacement failure and verifying byte-identical rollback'
    $rollbackRoot = New-TestHostedRoot -Name 'rollback'
    $rollbackApprovalPath = Join-Path $rollbackRoot 'approved-rules.json'
    Write-JsonFixture -Path $rollbackApprovalPath -Value (New-Approval -HostedFixtureRoot $rollbackRoot)
    $rollbackBefore = Get-TargetHashes -HostedFixtureRoot $rollbackRoot
    $rollbackResult = Invoke-Apply -HostedFixtureRoot $rollbackRoot -ApprovalPath $rollbackApprovalPath -FailAfterReplace 1
    $rollbackAfter = Get-TargetHashes -HostedFixtureRoot $rollbackRoot
    $rollbackPassed = $rollbackResult.exitCode -ne 0 -and $rollbackResult.output -like '*Injected catalog apply replacement failure*' -and @(Compare-Object $rollbackBefore $rollbackAfter).Count -eq 0
    Add-TestResult -Name 'partial-write-rollback' -Passed $rollbackPassed -Detail $(if ($rollbackPassed) { 'Injected replacement failure restored every catalog-owned file byte-for-byte.' } else { $rollbackResult.output })
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
    $result | ConvertTo-Json -Depth 8
}
else {
    Write-ValidationSectionHeader -Title 'Hosted catalog approval apply test summary'
    Write-ValidationSummary -Fields ([ordered]@{
        Status = $result.status.ToUpperInvariant()
        Tests = $result.testCount
        Issues = $result.issueCount
    })
    Write-ValidationSectionHeader -Title 'Catalog apply tests'
    Write-ValidationTwoColumnTable -Rows @($result.tests) -FirstHeader 'Status' -FirstProperty 'status' -SecondHeader 'Test' -SecondProperty 'name' -FirstWidth 10 -UppercaseFirst
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
