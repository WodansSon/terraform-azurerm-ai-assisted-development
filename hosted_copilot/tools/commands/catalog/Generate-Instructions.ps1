[CmdletBinding()]
param(
    [string]$CatalogPath = (Join-Path $PSScriptRoot '../../../copilot-rule-catalog/instruction-catalog.json'),

    [string]$HostedRoot = (Join-Path $PSScriptRoot '../../..'),

    [switch]$Write,

    [ValidateSet('Text', 'Json')]
    [string]$OutputFormat = 'Text'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$validationOutputModulePath = Join-Path $PSScriptRoot '../../../../tools/ValidationOutput.psm1'
Import-Module -Name $validationOutputModulePath -Force

$resolvedCatalogPath = [IO.Path]::GetFullPath($CatalogPath)
$resolvedHostedRoot = [IO.Path]::GetFullPath($HostedRoot)

if ($OutputFormat -eq 'Text') {
    Write-ValidationSectionHeader -Title 'Hosted instruction generation'
    Write-Host (Format-ValidationStatusLine -Status 'running' -Name 'catalog-validation' -Detail 'Validating catalog schema, evidence, provenance, and rule references')
}

if (-not (Test-Path -LiteralPath $resolvedCatalogPath -PathType Leaf)) {
    throw "Instruction catalog was not found: $resolvedCatalogPath"
}

$catalogContent = Get-Content -LiteralPath $resolvedCatalogPath -Raw
$catalog = $catalogContent | ConvertFrom-Json
$schemaName = [string]$catalog.'$schema'
if ($schemaName -notin @('instruction-catalog.schema.json', 'instruction-catalog-v4.schema.json')) {
    throw "Instruction catalog declares an unsupported schema: $schemaName"
}
$schemaPath = Join-Path (Split-Path -Parent $resolvedCatalogPath) $schemaName
if (-not (Test-Path -LiteralPath $schemaPath -PathType Leaf)) {
    throw "Instruction catalog schema was not found: $schemaPath"
}

if (-not ($catalogContent | Test-Json -SchemaFile $schemaPath)) {
    throw 'Instruction catalog schema validation failed'
}

$sourceIds = @($catalog.sources | ForEach-Object { [string]$_.id })
if (@($sourceIds | Group-Object | Where-Object Count -gt 1).Count -gt 0) {
    throw 'Instruction catalog contains duplicate source IDs'
}
$evidenceIds = @($catalog.evidence | ForEach-Object { [string]$_.id })
if (@($evidenceIds | Group-Object | Where-Object Count -gt 1).Count -gt 0) {
    throw 'Instruction catalog contains duplicate evidence IDs'
}
$evidenceById = @{}
foreach ($evidenceRecord in @($catalog.evidence)) {
    $evidenceById[[string]$evidenceRecord.id] = $evidenceRecord
}

$rulesById = @{}
foreach ($rule in @($catalog.rules)) {
    if ($rulesById.ContainsKey([string]$rule.id)) {
        throw "Instruction catalog contains duplicate rule ID: $($rule.id)"
    }
    if ($null -ne $rule.PSObject.Properties['sourceIds']) {
        $unknownSourceIds = @($rule.sourceIds | Where-Object { $_ -notin $sourceIds })
        if ($unknownSourceIds.Count -gt 0) {
            throw "Rule $($rule.id) references unknown source IDs: $($unknownSourceIds -join ', ')"
        }
    }
    $unknownEvidenceIds = @($rule.evidenceIds | Where-Object { $_ -notin $evidenceIds })
    if ($unknownEvidenceIds.Count -gt 0) {
        throw "Rule $($rule.id) references unknown evidence IDs: $($unknownEvidenceIds -join ', ')"
    }
    if ($rule.provenance -contains 'confirmed-maintainer-convention' -and @($rule.evidenceIds | Where-Object { $evidenceById[$_].type -eq 'maintainer-confirmation' }).Count -eq 0) {
        throw "Confirmed maintainer rule $($rule.id) requires maintainer-confirmation evidence"
    }
    if ($rule.provenance -contains 'local-safeguard' -and @($rule.evidenceIds | Where-Object { $evidenceById[$_].type -eq 'architecture' }).Count -eq 0) {
        throw "Local safeguard rule $($rule.id) requires architecture evidence"
    }
    $rulesById[[string]$rule.id] = $rule
}

$usedRuleIds = New-Object 'System.Collections.Generic.List[string]'
$outputs = New-Object 'System.Collections.Generic.List[object]'
if ($OutputFormat -eq 'Text') {
    Write-Host (Format-ValidationStatusLine -Status 'running' -Name 'surface-rendering' -Detail 'Rendering and comparing every Hosted instruction surface')
}
foreach ($surface in @($catalog.surfaces)) {
    $lines = New-Object 'System.Collections.Generic.List[string]'
    $lines.Add('---')
    $lines.Add("description: `"$($surface.description)`"")
    $lines.Add("applyTo: `"$($surface.applyTo)`"")
    $lines.Add('---')
    $lines.Add('')
    $lines.Add("# $($surface.title):")
    $lines.Add('')
    $lines.Add([string]$surface.introduction)

    foreach ($section in @($surface.sections)) {
        $lines.Add('')
        $lines.Add("## $($section.heading):")
        $lines.Add('')
        foreach ($ruleId in @($section.ruleIds)) {
            $id = [string]$ruleId
            if (-not $rulesById.ContainsKey($id)) {
                throw "Surface $($surface.id) references unknown rule ID: $id"
            }
            $rule = $rulesById[$id]
            if ($rule.status -ne 'active') {
                throw "Surface $($surface.id) references non-active rule ID: $id"
            }
            if ($usedRuleIds.Contains($id)) {
                throw "Active rule ID is rendered more than once: $id"
            }
            $usedRuleIds.Add($id)
            $implementationModelScope = if ($surface.id -eq 'implementation') {
                " [$($rule.implementationModels -join ', ')]"
            }
            else {
                ''
            }
            $lines.Add("- ``[$id]``$implementationModelScope $($rule.text)")
        }
    }

    $lines.Add('')
    foreach ($closingLine in ([string]$surface.closing -split "`n")) {
        $lines.Add($closingLine)
    }

    $content = ($lines -join "`n") + "`n"
    $outputPath = [IO.Path]::GetFullPath((Join-Path $resolvedHostedRoot ([string]$surface.outputPath)))
    $hostedPrefix = $resolvedHostedRoot.TrimEnd([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar) + [IO.Path]::DirectorySeparatorChar
    if (-not $outputPath.StartsWith($hostedPrefix, [StringComparison]::OrdinalIgnoreCase)) {
        throw "Generated output escapes HostedRoot: $outputPath"
    }

    $existingContent = if (Test-Path -LiteralPath $outputPath -PathType Leaf) {
        [IO.File]::ReadAllText($outputPath)
    }
    else {
        $null
    }
    $fresh = $existingContent -ceq $content

    if ($Write -and -not $fresh) {
        $outputDirectory = Split-Path -Parent $outputPath
        if (-not (Test-Path -LiteralPath $outputDirectory -PathType Container)) {
            New-Item -ItemType Directory -Path $outputDirectory | Out-Null
        }
        [IO.File]::WriteAllText($outputPath, $content, [Text.UTF8Encoding]::new($false))
        $fresh = $true
    }

    $outputs.Add([pscustomobject]@{
        surface = [string]$surface.id
        path = [IO.Path]::GetRelativePath($resolvedHostedRoot, $outputPath).Replace('\', '/')
        status = if ($fresh) { 'fresh' } else { 'stale' }
    })
}

$activeRuleIds = @($catalog.rules | Where-Object status -eq 'active' | ForEach-Object { [string]$_.id } | Sort-Object)
$unusedActiveRuleIds = @($activeRuleIds | Where-Object { -not $usedRuleIds.Contains($_) })
if ($unusedActiveRuleIds.Count -gt 0) {
    throw "Active rules are not rendered: $($unusedActiveRuleIds -join ', ')"
}

$staleOutputs = @($outputs | Where-Object status -eq 'stale')
$result = [ordered]@{
    success = $staleOutputs.Count -eq 0
    mode = if ($Write) { 'write' } else { 'check' }
    catalogPath = $resolvedCatalogPath
    activeRuleCount = $activeRuleIds.Count
    retiredRuleCount = @($catalog.rules | Where-Object status -eq 'retired').Count
    outputs = $outputs.ToArray()
}

if ($OutputFormat -eq 'Json') {
    $result | ConvertTo-Json -Depth 6
}
else {
    Write-ValidationSectionHeader -Title 'Hosted instruction generation summary'
    Write-ValidationSummary -Fields ([ordered]@{
        Status = $(if ($result.success) { 'PASSED' } else { 'FAILED' })
        Mode = $result.mode.ToUpperInvariant()
        'Active Rules' = $result.activeRuleCount
        'Retired Rules' = $result.retiredRuleCount
        Outputs = $outputs.Count
        Stale = $staleOutputs.Count
    })
    Write-ValidationSectionHeader -Title 'Instruction surfaces'
    foreach ($output in $outputs) {
        Write-Output (Format-ValidationStatusLine -Status $output.status -Name $output.surface -Detail $output.path)
    }
    if (-not $result.success) {
        Write-ValidationSectionHeader -Title 'Failures'
        Write-Output '  - Generated Hosted instructions are stale; rerun with -Write after reviewing the catalog changes.'
    }
    Complete-ValidationTextOutput
}

if (-not $result.success) {
    exit 1
}
