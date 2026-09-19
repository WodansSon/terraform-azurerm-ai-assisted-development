[CmdletBinding()]
param(
    [ValidateSet('Text', 'Json')]
    [string]$OutputFormat = 'Text'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))
$hostedRoot = Join-Path $repoRoot 'hosted_copilot'
$catalogRoot = Join-Path $hostedRoot 'copilot-rule-catalog'
$sourceCatalogPath = Join-Path $catalogRoot 'instruction-catalog.json'
$sourceSchemaPath = Join-Path $catalogRoot 'instruction-catalog.schema.json'
$targetCatalogPath = Join-Path $catalogRoot 'instruction-catalog-v4.json'
$targetSchemaPath = Join-Path $catalogRoot 'instruction-catalog-v4.schema.json'
$transformerPath = Join-Path $PSScriptRoot 'Convert-InstructionCatalogV4.ps1'
$generatorPath = Join-Path $PSScriptRoot '../commands/catalog/Generate-Instructions.ps1'
$validationOutputModulePath = Join-Path $repoRoot 'tools/ValidationOutput.psm1'
$expectedRuleCount = 54
$expectedRelationshipCount = 37
$expectedAcceptedAt = '2026-09-01T08:54:55.0000000Z'
$expectedMigrationRationale = 'Migrated from the accepted legacy sourceIds catalog relationship.'
$results = [Collections.Generic.List[object]]::new()
$issues = [Collections.Generic.List[string]]::new()
$tempRoot = Join-Path ([IO.Path]::GetTempPath()) ("hosted-v4-catalog-{0}" -f [Guid]::NewGuid().ToString('N'))

Import-Module -Name $validationOutputModulePath -Force

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

function Invoke-TransformationTest {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][string]$SuccessDetail,
        [Parameter(Mandatory = $true)][scriptblock]$Action
    )

    try {
        & $Action
        Add-TestResult -Name $Name -Passed $true -Detail $SuccessDetail
    }
    catch {
        Add-TestResult -Name $Name -Passed $false -Detail $_.Exception.Message
    }
}

function Invoke-PowerShellFile {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [string[]]$Arguments = @()
    )

    $global:LASTEXITCODE = 0
    $output = @(& pwsh -NoProfile -File $Path @Arguments 2>&1)
    $exitCode = if ($null -ne $LASTEXITCODE) { $LASTEXITCODE } else { 0 }
    $global:LASTEXITCODE = 0
    return [pscustomobject]@{ exitCode = $exitCode; output = ($output | Out-String).Trim() }
}

function Copy-JsonValue {
    param([Parameter(Mandatory = $true)][object]$Value)

    return ($Value | ConvertTo-Json -Depth 100 -Compress) | ConvertFrom-Json -DateKind String
}

function Get-ObjectWithoutProperties {
    param(
        [Parameter(Mandatory = $true)][object]$Value,
        [Parameter(Mandatory = $true)][string[]]$Excluded
    )

    $result = [ordered]@{}
    foreach ($property in $Value.PSObject.Properties) {
        if ($property.Name -notin $Excluded) {
            $result[$property.Name] = $property.Value
        }
    }
    return $result
}

function Get-LegacyRelationshipTuples {
    param([Parameter(Mandatory = $true)][object[]]$Rules)

    return @($Rules | ForEach-Object {
        $rule = $_
        @($rule.sourceIds) | ForEach-Object { "contributor-guidance|$($_)|$($rule.id)" }
    })
}

function Get-V4RelationshipTuples {
    param([Parameter(Mandatory = $true)][object[]]$Relationships)

    return @($Relationships | ForEach-Object { "$($_.sourceRef.sourceDefinitionId)|$($_.sourceRef.sourceId)|$($_.hostedRuleId)" })
}

function Assert-SameValues {
    param(
        [Parameter(Mandatory = $true)][string[]]$Expected,
        [Parameter(Mandatory = $true)][string[]]$Actual,
        [Parameter(Mandatory = $true)][string]$Name
    )

    $difference = @(Compare-Object -ReferenceObject @($Expected | Sort-Object) -DifferenceObject @($Actual | Sort-Object) -SyncWindow 0)
    if ($difference.Count -gt 0) {
        throw "$Name differ: $($difference | ForEach-Object { "$($_.SideIndicator)$($_.InputObject)" } | Out-String)"
    }
}

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

try {
    $sourceCatalog = Get-Content -LiteralPath $sourceCatalogPath -Raw | ConvertFrom-Json -DateKind String
    $targetCatalog = Get-Content -LiteralPath $targetCatalogPath -Raw | ConvertFrom-Json -DateKind String

    Invoke-TransformationTest -Name 'shadow-schema' -SuccessDetail 'The shadow candidate satisfies the strict version 4 catalog schema.' -Action {
        if (-not (Test-JsonInstance -Value $targetCatalog -SchemaPath $targetSchemaPath)) {
            throw 'Shadow candidate failed version 4 schema validation'
        }
        if ([int]$targetCatalog.schemaVersion -ne 4 -or [string]$targetCatalog.'$schema' -cne 'instruction-catalog-v4.schema.json') {
            throw 'Shadow candidate does not declare the version 4 schema'
        }
    }

    Invoke-TransformationTest -Name 'root-preservation' -SuccessDetail 'Every non-version, non-relationship catalog root value is preserved exactly.' -Action {
        $sourceRoot = Get-ObjectWithoutProperties -Value $sourceCatalog -Excluded @('$schema', 'schemaVersion', 'rules')
        $targetRoot = Get-ObjectWithoutProperties -Value $targetCatalog -Excluded @('$schema', 'schemaVersion', 'rules', 'sourceRelationships')
        if (($sourceRoot | ConvertTo-Json -Depth 100 -Compress) -cne ($targetRoot | ConvertTo-Json -Depth 100 -Compress)) {
            throw 'Non-relationship catalog root values changed during transformation'
        }
    }

    Invoke-TransformationTest -Name 'ordered-rule-preservation' -SuccessDetail 'All 54 ordered rule objects preserve every value except legacy sourceIds.' -Action {
        if (@($sourceCatalog.rules).Count -ne $expectedRuleCount -or @($targetCatalog.rules).Count -ne $expectedRuleCount) {
            throw "Expected $expectedRuleCount source and transformed rules"
        }
        for ($index = 0; $index -lt $expectedRuleCount; $index++) {
            $expectedRule = Get-ObjectWithoutProperties -Value $sourceCatalog.rules[$index] -Excluded @('sourceIds')
            if (($expectedRule | ConvertTo-Json -Depth 100 -Compress) -cne ($targetCatalog.rules[$index] | ConvertTo-Json -Depth 100 -Compress)) {
                throw "Transformed rule first differs at ordered index $index"
            }
        }
    }

    Invoke-TransformationTest -Name 'legacy-tuple-equality' -SuccessDetail 'The 37 normalized supports relationships exactly equal the Phase 0 legacy tuple set.' -Action {
        $expectedTuples = @(Get-LegacyRelationshipTuples -Rules @($sourceCatalog.rules))
        $actualTuples = @(Get-V4RelationshipTuples -Relationships @($targetCatalog.sourceRelationships))
        if ($expectedTuples.Count -ne $expectedRelationshipCount -or @($expectedTuples | Sort-Object -Unique).Count -ne $expectedRelationshipCount -or $actualTuples.Count -ne $expectedRelationshipCount -or @($actualTuples | Sort-Object -Unique).Count -ne $expectedRelationshipCount) {
            throw "Expected exactly $expectedRelationshipCount unique legacy and transformed relationship tuples"
        }
        Assert-SameValues -Expected $expectedTuples -Actual $actualTuples -Name 'Legacy and transformed relationship tuples'
    }

    Invoke-TransformationTest -Name 'migration-metadata' -SuccessDetail 'Migrated relationships use supports, immutable acceptance provenance, and no fabricated assessment evidence.' -Action {
        foreach ($relationship in @($targetCatalog.sourceRelationships)) {
            if ([string]$relationship.status -cne 'active' -or [string]$relationship.relationshipKind -cne 'supports' -or [string]$relationship.acceptedAt -cne $expectedAcceptedAt -or [string]$relationship.rationale -cne $expectedMigrationRationale -or @($relationship.assessmentEvidenceRefs).Count -ne 0 -or @($relationship.history).Count -ne 0) {
                throw "Relationship migration metadata is invalid for $($relationship.sourceRef.sourceId) -> $($relationship.hostedRuleId)"
            }
        }
    }

    Invoke-TransformationTest -Name 'relationship-lifecycle-schema' -SuccessDetail 'Relationship status, retirement reason, kind, evidence, and history shapes fail closed.' -Action {
        $activeWithRetirement = Copy-JsonValue -Value $targetCatalog
        $activeWithRetirement.sourceRelationships[0] | Add-Member -NotePropertyName retirementReason -NotePropertyValue 'Not valid while active.'
        if (Test-JsonInstance -Value $activeWithRetirement -SchemaPath $targetSchemaPath) {
            throw 'Active relationship accepted a retirement reason'
        }

        $retiredWithoutReason = Copy-JsonValue -Value $targetCatalog
        $retiredWithoutReason.sourceRelationships[0].status = 'retired'
        if (Test-JsonInstance -Value $retiredWithoutReason -SchemaPath $targetSchemaPath) {
            throw 'Retired relationship omitted its retirement reason'
        }

        $validRetired = Copy-JsonValue -Value $retiredWithoutReason
        $validRetired.sourceRelationships[0] | Add-Member -NotePropertyName retirementReason -NotePropertyValue 'Maintainer-approved relationship retirement.'
        $validRetired.sourceRelationships[0].history = @([ordered]@{ action = 'retired'; recordedAt = '2026-09-18T12:00:00.0000000Z'; rationale = 'Maintainer-approved relationship retirement.'; assessmentEvidenceRefs = @() })
        if (-not (Test-JsonInstance -Value $validRetired -SchemaPath $targetSchemaPath)) {
            throw 'Valid retired relationship history failed schema validation'
        }

        $invalidKind = Copy-JsonValue -Value $targetCatalog
        $invalidKind.sourceRelationships[0].relationshipKind = 'related'
        if (Test-JsonInstance -Value $invalidKind -SchemaPath $targetSchemaPath) {
            throw 'Assessment-only relationship kind entered accepted catalog state'
        }
    }

    Invoke-TransformationTest -Name 'deterministic-transformation' -SuccessDetail 'Repeated transformation produces the same shadow candidate bytes and freshness result.' -Action {
        $tempCatalogRoot = Join-Path $tempRoot 'transform/catalog'
        New-Item -ItemType Directory -Path $tempCatalogRoot -Force | Out-Null
        Copy-Item -LiteralPath $sourceCatalogPath, $sourceSchemaPath, $targetSchemaPath -Destination $tempCatalogRoot
        $tempSourcePath = Join-Path $tempCatalogRoot 'instruction-catalog.json'
        $tempTargetPath = Join-Path $tempCatalogRoot 'instruction-catalog-v4.json'
        $writeResult = Invoke-PowerShellFile -Path $transformerPath -Arguments @('-SourceCatalogPath', $tempSourcePath, '-OutputPath', $tempTargetPath, '-Write', '-OutputFormat', 'Json')
        if ($writeResult.exitCode -ne 0) { throw $writeResult.output }
        $firstHash = (Get-FileHash -LiteralPath $tempTargetPath -Algorithm SHA256).Hash
        $checkResult = Invoke-PowerShellFile -Path $transformerPath -Arguments @('-SourceCatalogPath', $tempSourcePath, '-OutputPath', $tempTargetPath, '-OutputFormat', 'Json')
        if ($checkResult.exitCode -ne 0) { throw $checkResult.output }
        $secondHash = (Get-FileHash -LiteralPath $tempTargetPath -Algorithm SHA256).Hash
        if ($firstHash -cne $secondHash -or $firstHash -cne (Get-FileHash -LiteralPath $targetCatalogPath -Algorithm SHA256).Hash) {
            throw 'Repeated transformation did not preserve exact candidate bytes'
        }
    }

    Invoke-TransformationTest -Name 'unknown-legacy-source-rejected' -SuccessDetail 'Transformation rejects legacy source relationships that cannot resolve to catalog source evidence.' -Action {
        $invalidRoot = Join-Path $tempRoot 'invalid/catalog'
        New-Item -ItemType Directory -Path $invalidRoot -Force | Out-Null
        Copy-Item -LiteralPath $sourceSchemaPath, $targetSchemaPath -Destination $invalidRoot
        $invalidCatalog = Copy-JsonValue -Value $sourceCatalog
        $invalidCatalog.rules[0].sourceIds = @('unknown-source')
        $invalidSourcePath = Join-Path $invalidRoot 'instruction-catalog.json'
        [IO.File]::WriteAllText($invalidSourcePath, (($invalidCatalog | ConvertTo-Json -Depth 100) + "`n"), [Text.UTF8Encoding]::new($false))
        $invalidResult = Invoke-PowerShellFile -Path $transformerPath -Arguments @('-SourceCatalogPath', $invalidSourcePath, '-OutputPath', (Join-Path $invalidRoot 'instruction-catalog-v4.json'), '-Write', '-OutputFormat', 'Json')
        if ($invalidResult.exitCode -eq 0 -or $invalidResult.output -notmatch 'unknown legacy source ID') {
            throw 'Unknown legacy source relationship was not rejected'
        }
    }

    Invoke-TransformationTest -Name 'v4-instruction-generation' -SuccessDetail 'The v4 shadow candidate deterministically reproduces every committed instruction byte.' -Action {
        $generationRoot = Join-Path $tempRoot 'generation'
        $generationCatalogRoot = Join-Path $generationRoot 'copilot-rule-catalog'
        New-Item -ItemType Directory -Path $generationCatalogRoot -Force | Out-Null
        Copy-Item -LiteralPath $targetCatalogPath, $targetSchemaPath -Destination $generationCatalogRoot
        $generationCatalogPath = Join-Path $generationCatalogRoot 'instruction-catalog-v4.json'
        $writeResult = Invoke-PowerShellFile -Path $generatorPath -Arguments @('-CatalogPath', $generationCatalogPath, '-HostedRoot', $generationRoot, '-Write', '-OutputFormat', 'Json')
        if ($writeResult.exitCode -ne 0) { throw $writeResult.output }
        $checkResult = Invoke-PowerShellFile -Path $generatorPath -Arguments @('-CatalogPath', $generationCatalogPath, '-HostedRoot', $generationRoot, '-OutputFormat', 'Json')
        if ($checkResult.exitCode -ne 0) { throw $checkResult.output }
        foreach ($surface in @($targetCatalog.surfaces)) {
            $generatedPath = Join-Path $generationRoot ([string]$surface.outputPath)
            $committedPath = Join-Path $hostedRoot ([string]$surface.outputPath)
            if ((Get-FileHash -LiteralPath $generatedPath -Algorithm SHA256).Hash -cne (Get-FileHash -LiteralPath $committedPath -Algorithm SHA256).Hash) {
                throw "Version 4 generation changed committed instruction bytes: $($surface.outputPath)"
            }
        }
    }
}
catch {
    $issues.Add($_.Exception.Message)
}
finally {
    Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
}

$summary = [ordered]@{
    status = if ($issues.Count -eq 0) { 'passed' } else { 'failed' }
    testCount = $results.Count
    issueCount = $issues.Count
    ruleCount = if (Test-Path -LiteralPath $targetCatalogPath) { @((Get-Content -LiteralPath $targetCatalogPath -Raw | ConvertFrom-Json).rules).Count } else { 0 }
    relationshipCount = if (Test-Path -LiteralPath $targetCatalogPath) { @((Get-Content -LiteralPath $targetCatalogPath -Raw | ConvertFrom-Json).sourceRelationships).Count } else { 0 }
    tests = $results.ToArray()
    issues = $issues.ToArray()
}

if ($OutputFormat -eq 'Json') {
    $summary | ConvertTo-Json -Depth 8
}
else {
    Write-ValidationSectionHeader -Title 'Hosted version 4 catalog transformation'
    Write-ValidationSummary -Fields ([ordered]@{
        Status = $summary.status.ToUpperInvariant()
        Tests = $summary.testCount
        Issues = $summary.issueCount
        Rules = $summary.ruleCount
        Relationships = $summary.relationshipCount
    })
    Write-Output ''
    Write-ValidationTwoColumnTable -Rows $results.ToArray() -FirstHeader 'Status' -FirstProperty 'status' -SecondHeader 'Test' -SecondProperty 'name' -UppercaseFirst
    if ($issues.Count -gt 0) {
        Write-ValidationSectionHeader -Title 'Failures'
        foreach ($issue in $issues) { Write-Output "  - $issue" }
    }
    Complete-ValidationTextOutput
}

if ($summary.status -ne 'passed') {
    exit 1
}
