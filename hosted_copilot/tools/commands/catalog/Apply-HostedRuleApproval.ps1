[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$ApprovalPath,

    [string]$CatalogPath = (Join-Path $PSScriptRoot '../../../copilot-rule-catalog/instruction-catalog.json'),

    [string]$ProtectedRulesPath = (Join-Path $PSScriptRoot '../../../copilot-rule-catalog/protected-rules.json'),

    [string]$ProtectedRulesSourceRoot = (Join-Path $PSScriptRoot '../../../authored-rules/protected'),

    [string]$HostedRoot = (Join-Path $PSScriptRoot '../../..'),

    [ValidateSet('Text', 'Json')]
    [string]$OutputFormat = 'Text'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$validationOutputModulePath = Join-Path $PSScriptRoot '../../../../tools/ValidationOutput.psm1'
Import-Module -Name $validationOutputModulePath -Force

function Get-Sha256 {
    param([Parameter(Mandatory = $true)][byte[]]$Bytes)

    return [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($Bytes)).ToLowerInvariant()
}

function Get-FileBytes {
    param([Parameter(Mandatory = $true)][string]$Path)

    return [IO.File]::ReadAllBytes($Path)
}

function Copy-JsonValue {
    param([Parameter(Mandatory = $true)][object]$Value)

    return ($Value | ConvertTo-Json -Depth 100 -Compress) | ConvertFrom-Json -DateKind String
}

function ConvertTo-InlineJson {
    param([Parameter(Mandatory = $true)][object]$Value)

    $compact = $Value | ConvertTo-Json -Depth 100 -Compress
    $builder = [Text.StringBuilder]::new()
    $inString = $false
    $escaped = $false
    for ($index = 0; $index -lt $compact.Length; $index++) {
        $character = $compact[$index]
        if ($inString) {
            $null = $builder.Append($character)
            if ($escaped) {
                $escaped = $false
            }
            elseif ($character -eq '\') {
                $escaped = $true
            }
            elseif ($character -eq '"') {
                $inString = $false
            }
            continue
        }

        if ($character -eq '"') {
            $inString = $true
            $null = $builder.Append($character)
            continue
        }

        switch ($character) {
            '{' {
                $null = $builder.Append('{')
                if ($index + 1 -lt $compact.Length -and $compact[$index + 1] -ne '}') {
                    $null = $builder.Append(' ')
                }
            }
            '}' {
                if ($index -gt 0 -and $compact[$index - 1] -ne '{') {
                    $null = $builder.Append(' ')
                }
                $null = $builder.Append('}')
            }
            ':' { $null = $builder.Append(': ') }
            ',' { $null = $builder.Append(', ') }
            default { $null = $builder.Append($character) }
        }
    }
    return $builder.ToString()
}

function Replace-ExactlyOnce {
    param(
        [Parameter(Mandatory = $true)][string]$Content,
        [Parameter(Mandatory = $true)][string]$OldValue,
        [Parameter(Mandatory = $true)][string]$NewValue,
        [Parameter(Mandatory = $true)][string]$Description
    )

    $firstIndex = $Content.IndexOf($OldValue, [StringComparison]::Ordinal)
    if ($firstIndex -lt 0 -or $Content.IndexOf($OldValue, $firstIndex + $OldValue.Length, [StringComparison]::Ordinal) -ge 0) {
        throw "Catalog formatting boundary was not found exactly once: $Description"
    }
    return $Content.Substring(0, $firstIndex) + $NewValue + $Content.Substring($firstIndex + $OldValue.Length)
}

function Test-EquivalentJson {
    param(
        [Parameter(Mandatory = $true)][object]$Left,
        [Parameter(Mandatory = $true)][object]$Right
    )

    return ($Left | ConvertTo-Json -Depth 100 -Compress) -ceq ($Right | ConvertTo-Json -Depth 100 -Compress)
}

function New-CatalogRule {
    param(
        [Parameter(Mandatory = $true)][object]$ApprovedRule,
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][string[]]$SourceIds
    )

    $rule = [ordered]@{
        id = [string]$ApprovedRule.id
        origin = [string]$ApprovedRule.origin
        status = [string]$ApprovedRule.status
        text = [string]$ApprovedRule.text
        provenance = @($ApprovedRule.provenance)
        sourceIds = @($SourceIds)
        evidenceIds = @($ApprovedRule.evidenceIds)
    }
    foreach ($propertyName in @('implementationModels', 'documentationGap', 'retirementReason', 'lastPlacement', 'selectionFactors', 'selectionRationale')) {
        if ($ApprovedRule.PSObject.Properties[$propertyName]) {
            $rule[$propertyName] = $ApprovedRule.$propertyName
        }
    }
    return [pscustomobject]$rule
}

function Get-ProjectedSourceIds {
    param(
        [Parameter(Mandatory = $true)][object]$Mutation,
        [AllowNull()][object]$ExistingRule,
        [Parameter(Mandatory = $true)][string[]]$KnownSourceIds
    )

    $sourceIds = [Collections.Generic.List[string]]::new()
    $existingSourceIds = if ($null -ne $ExistingRule -and $ExistingRule.PSObject.Properties['sourceIds']) { @($ExistingRule.sourceIds) } else { @() }
    foreach ($sourceId in $existingSourceIds) {
        if (-not $sourceIds.Contains([string]$sourceId)) {
            $sourceIds.Add([string]$sourceId)
        }
    }
    foreach ($relationship in @($Mutation.sourceRelationships)) {
        $sourceId = [string]$relationship.sourceId
        if ([string]$relationship.sourceDefinitionId -ceq 'contributor-guidance' -and $sourceId -in $KnownSourceIds -and -not $sourceIds.Contains($sourceId)) {
            $sourceIds.Add($sourceId)
        }
    }
    return $sourceIds.ToArray()
}

function Render-CatalogContent {
    param(
        [Parameter(Mandatory = $true)][string]$OriginalContent,
        [Parameter(Mandatory = $true)][object]$OriginalCatalog,
        [Parameter(Mandatory = $true)][object]$Catalog
    )

    $newline = if ($OriginalContent.Contains("`r`n")) { "`r`n" } else { "`n" }
    $content = $OriginalContent
    $content = Replace-ExactlyOnce -Content $content -OldValue "  `"lastSemanticReview`": `"$($OriginalCatalog.lastSemanticReview)`"" -NewValue "  `"lastSemanticReview`": `"$($Catalog.lastSemanticReview)`"" -Description 'lastSemanticReview'

    for ($surfaceIndex = 0; $surfaceIndex -lt @($Catalog.surfaces).Count; $surfaceIndex++) {
        $originalSurface = $OriginalCatalog.surfaces[$surfaceIndex]
        $surface = $Catalog.surfaces[$surfaceIndex]
        for ($sectionIndex = 0; $sectionIndex -lt @($surface.sections).Count; $sectionIndex++) {
            $originalSection = $originalSurface.sections[$sectionIndex]
            $section = $surface.sections[$sectionIndex]
            if (-not (Test-EquivalentJson -Left $originalSection -Right $section)) {
                $content = Replace-ExactlyOnce -Content $content -OldValue ('        ' + (ConvertTo-InlineJson -Value $originalSection)) -NewValue ('        ' + (ConvertTo-InlineJson -Value $section)) -Description "surface $($surface.id) section $($section.heading)"
            }
        }
    }

    $mappingLines = [Collections.Generic.List[string]]::new()
    $mappingLines.Add('  "canonicalCandidateMappings": {')
    $mappingProperties = @($Catalog.canonicalCandidateMappings.PSObject.Properties)
    for ($index = 0; $index -lt $mappingProperties.Count; $index++) {
        $property = $mappingProperties[$index]
        $suffix = if ($index -lt $mappingProperties.Count - 1) { ',' } else { '' }
        $mappingLines.Add("    `"$($property.Name)`": $(ConvertTo-InlineJson -Value $property.Value)$suffix")
    }
    $mappingLines.Add('  },')
    $mappingBlock = $mappingLines -join $newline
    $mappingStart = $content.IndexOf('  "canonicalCandidateMappings": {', [StringComparison]::Ordinal)
    $rulesStart = $content.IndexOf('  "rules": [', $mappingStart, [StringComparison]::Ordinal)
    if ($mappingStart -lt 0 -or $rulesStart -lt 0) {
        throw 'Catalog mapping or rule formatting boundary was not found'
    }
    $content = $content.Substring(0, $mappingStart) + $mappingBlock + $newline + $content.Substring($rulesStart)

    $ruleLines = [Collections.Generic.List[string]]::new()
    $ruleLines.Add('  "rules": [')
    $rules = @($Catalog.rules)
    for ($index = 0; $index -lt $rules.Count; $index++) {
        $suffix = if ($index -lt $rules.Count - 1) { ',' } else { '' }
        $ruleLines.Add("    $(ConvertTo-InlineJson -Value $rules[$index])$suffix")
    }
    $ruleLines.Add('  ]')
    $ruleBlock = $ruleLines -join $newline
    $rulesStart = $content.IndexOf('  "rules": [', [StringComparison]::Ordinal)
    $rulesEndMarker = $newline + '  ]' + $newline + '}'
    $rulesEnd = $content.LastIndexOf($rulesEndMarker, [StringComparison]::Ordinal)
    if ($rulesStart -lt 0 -or $rulesEnd -lt $rulesStart) {
        throw 'Catalog rule formatting boundary was not found'
    }
    $content = $content.Substring(0, $rulesStart) + $ruleBlock + $content.Substring($rulesEnd + $rulesEndMarker.Length - 1)
    return $content
}

function Invoke-AtomicReplacement {
    param([Parameter(Mandatory = $true)][object[]]$Files)

    $temporaryPaths = [Collections.Generic.List[string]]::new()
    $replacedCount = 0
    try {
        foreach ($file in $Files) {
            $currentBytes = Get-FileBytes -Path $file.Path
            if ((Get-Sha256 -Bytes $currentBytes) -cne $file.OriginalSha256) {
                throw "Target changed after staging: $($file.Path)"
            }
            $temporaryPath = Join-Path (Split-Path -Parent $file.Path) ('.' + [IO.Path]::GetFileName($file.Path) + '.' + [guid]::NewGuid().ToString('N') + '.tmp')
            [IO.File]::WriteAllBytes($temporaryPath, $file.StagedBytes)
            $temporaryPaths.Add($temporaryPath)
            $file | Add-Member -NotePropertyName TemporaryPath -NotePropertyValue $temporaryPath
        }

        foreach ($file in $Files) {
            [IO.File]::Move([string]$file.TemporaryPath, [string]$file.Path, $true)
            $replacedCount++
            $failureAfterReplace = [int]($env:HOSTED_CATALOG_APPLY_TEST_FAIL_AFTER_REPLACE ?? 0)
            if ($failureAfterReplace -gt 0 -and $replacedCount -eq $failureAfterReplace) {
                throw 'Injected catalog apply replacement failure'
            }
        }
    }
    catch {
        foreach ($file in $Files) {
            [IO.File]::WriteAllBytes([string]$file.Path, [byte[]]$file.OriginalBytes)
        }
        throw
    }
    finally {
        foreach ($temporaryPath in $temporaryPaths) {
            Remove-Item -LiteralPath $temporaryPath -Force -ErrorAction SilentlyContinue
        }
    }
}

$resolvedApprovalPath = [IO.Path]::GetFullPath($ApprovalPath)
$resolvedCatalogPath = [IO.Path]::GetFullPath($CatalogPath)
$resolvedProtectedRulesPath = [IO.Path]::GetFullPath($ProtectedRulesPath)
$resolvedProtectedRulesSourceRoot = [IO.Path]::GetFullPath($ProtectedRulesSourceRoot)
$resolvedHostedRoot = [IO.Path]::GetFullPath($HostedRoot)
$approvalSchemaPath = Join-Path $resolvedHostedRoot 'copilot-rule-catalog/assessment-reconciliation/approved-rules-v4.schema.json'
$catalogSchemaPath = Join-Path (Split-Path -Parent $resolvedCatalogPath) 'instruction-catalog.schema.json'
$protectedRulesSchemaPath = Join-Path (Split-Path -Parent $resolvedProtectedRulesPath) 'protected-rules.schema.json'
$generatorPath = Join-Path $PSScriptRoot 'Generate-Instructions.ps1'
$protectedGeneratorPath = Join-Path $PSScriptRoot 'Generate-ProtectedRules.ps1'

foreach ($requiredPath in @($resolvedApprovalPath, $resolvedCatalogPath, $resolvedProtectedRulesPath, $approvalSchemaPath, $catalogSchemaPath, $protectedRulesSchemaPath, $generatorPath, $protectedGeneratorPath)) {
    if (-not (Test-Path -LiteralPath $requiredPath -PathType Leaf)) {
        throw "Required catalog apply input was not found: $requiredPath"
    }
}
if (-not (Test-Path -LiteralPath $resolvedProtectedRulesSourceRoot -PathType Container)) {
    throw "Required protected rule source was not found: $resolvedProtectedRulesSourceRoot"
}

if ($OutputFormat -eq 'Text') {
    Write-ValidationSectionHeader -Title 'Hosted catalog approval apply'
    Write-Host (Format-ValidationStatusLine -Status 'running' -Name 'approval-validation' -Detail 'Validating approval schema and catalog precondition')
}

$approvalContent = Get-Content -LiteralPath $resolvedApprovalPath -Raw
if (-not ($approvalContent | Test-Json -SchemaFile $approvalSchemaPath -ErrorAction Stop)) {
    throw 'Approved rules schema validation failed'
}
$approval = $approvalContent | ConvertFrom-Json -DateKind String
$catalogBytes = Get-FileBytes -Path $resolvedCatalogPath
$catalogSha256 = Get-Sha256 -Bytes $catalogBytes
if ($catalogSha256 -cne [string]$approval.catalogContentSha256) {
    throw "Approved rules catalog precondition failed: expected $($approval.catalogContentSha256), found $catalogSha256"
}
$catalogContent = [Text.UTF8Encoding]::new($false, $true).GetString($catalogBytes)
if (-not ($catalogContent | Test-Json -SchemaFile $catalogSchemaPath -ErrorAction Stop)) {
    throw 'Hosted instruction catalog schema validation failed before apply'
}
$originalCatalog = $catalogContent | ConvertFrom-Json -DateKind String
$catalog = Copy-JsonValue -Value $originalCatalog
$protectedRulesContent = Get-Content -LiteralPath $resolvedProtectedRulesPath -Raw
if (-not ($protectedRulesContent | Test-Json -SchemaFile $protectedRulesSchemaPath -ErrorAction SilentlyContinue)) {
    throw 'Protected rules catalog schema validation failed before apply'
}
$protectedRules = $protectedRulesContent | ConvertFrom-Json -DateKind String
$protectedRuleIds = @($protectedRules.rules | ForEach-Object { [string]$_.id })
$protectedGenerationOutput = @(& pwsh -NoProfile -File $protectedGeneratorPath -SourceRoot $resolvedProtectedRulesSourceRoot -RepositoryRoot ([IO.Path]::GetFullPath((Join-Path $resolvedHostedRoot '..'))) -OutputPath $resolvedProtectedRulesPath -OutputFormat Json 2>&1)
if ($LASTEXITCODE -ne 0) {
    throw "Protected rules must be freshly generated before apply: $(($protectedGenerationOutput | Out-String).Trim())"
}

$mutationIds = @($approval.mutations | ForEach-Object { [string]$_.rule.id })
if (@($mutationIds | Group-Object -CaseSensitive | Where-Object Count -gt 1).Count -gt 0) {
    throw 'Approved rules contains duplicate mutation rule IDs'
}
if (@($mutationIds | Where-Object { $_ -in $protectedRuleIds }).Count -gt 0) {
    throw "Approved rules cannot mutate protected rule IDs: $(@($mutationIds | Where-Object { $_ -in $protectedRuleIds }) -join ', ')"
}

$knownSourceIds = @($catalog.sources | ForEach-Object { [string]$_.id })
$rules = [Collections.Generic.List[object]]::new()
@($catalog.rules) | ForEach-Object { $rules.Add($_) }
$rulesById = @{}
foreach ($rule in $rules) { $rulesById[[string]$rule.id] = $rule }

foreach ($mutation in @($approval.mutations)) {
    $ruleId = [string]$mutation.rule.id
    $action = [string]$mutation.action
    $existingRule = if ($rulesById.ContainsKey($ruleId)) { $rulesById[$ruleId] } else { $null }
    $existingMappingProperty = $catalog.canonicalCandidateMappings.PSObject.Properties[$ruleId]
    if ($action -ceq 'add') {
        if ($null -ne $existingRule -or $null -ne $existingMappingProperty) {
            throw "Add mutation targets an existing catalog rule: $ruleId"
        }
        $canonicalOwner = @($catalog.canonicalCandidateMappings.PSObject.Properties | Where-Object { Test-EquivalentJson -Left $_.Value -Right $mutation.canonicalCandidate })
        if ($canonicalOwner.Count -gt 0) {
            throw "Add mutation canonical candidate already owns catalog rule $($canonicalOwner[0].Name)"
        }
    }
    else {
        if ($null -eq $existingRule -or $null -eq $existingMappingProperty) {
            throw "$action mutation targets a missing catalog rule: $ruleId"
        }
        if (-not (Test-EquivalentJson -Left $existingMappingProperty.Value -Right $mutation.canonicalCandidate)) {
            throw "$action mutation cannot change canonical candidate ownership for catalog rule $ruleId"
        }
        if ($action -in @('update', 'retire') -and [string]$existingRule.status -cne 'active') {
            throw "$action mutation requires an active catalog rule: $ruleId"
        }
        if ($action -ceq 'restore' -and [string]$existingRule.status -cne 'retired') {
            throw "Restore mutation requires a retired catalog rule: $ruleId"
        }
    }

    foreach ($surface in @($catalog.surfaces)) {
        foreach ($section in @($surface.sections)) {
            $section.ruleIds = @($section.ruleIds | Where-Object { [string]$_ -cne $ruleId })
        }
    }

    if ($action -ne 'retire') {
        if (@($mutation.placements).Count -ne 1) {
            throw "Active catalog rule $ruleId must have exactly one placement"
        }
        $placement = $mutation.placements[0]
        $surface = @($catalog.surfaces | Where-Object { [string]$_.id -ceq [string]$placement.surfaceId })
        if ($surface.Count -ne 1) {
            throw "Mutation placement references an unknown surface for rule $ruleId"
        }
        $section = @($surface[0].sections | Where-Object { [string]$_.heading -ceq [string]$placement.sectionHeading })
        if ($section.Count -ne 1) {
            throw "Mutation placement references an unknown section for rule $ruleId"
        }
        $section[0].ruleIds = @($section[0].ruleIds) + $ruleId
    }

    $sourceIds = @(Get-ProjectedSourceIds -Mutation $mutation -ExistingRule $existingRule -KnownSourceIds $knownSourceIds)
    $projectedRule = New-CatalogRule -ApprovedRule $mutation.rule -SourceIds $sourceIds
    if ($null -eq $existingRule) {
        $rules.Add($projectedRule)
        $catalog.canonicalCandidateMappings | Add-Member -NotePropertyName $ruleId -NotePropertyValue (Copy-JsonValue -Value $mutation.canonicalCandidate)
    }
    else {
        $existingIndex = $rules.IndexOf($existingRule)
        $rules[$existingIndex] = $projectedRule
    }
    $rulesById[$ruleId] = $projectedRule
}
$catalog.rules = $rules.ToArray()
$catalog.lastSemanticReview = [datetimeoffset]::Parse([string]$approval.approvedAt, [Globalization.CultureInfo]::InvariantCulture).UtcDateTime.ToString('yyyy-MM-dd')
$candidateCatalogContent = Render-CatalogContent -OriginalContent $catalogContent -OriginalCatalog $originalCatalog -Catalog $catalog
$candidateCatalogBytes = [Text.UTF8Encoding]::new($false).GetBytes($candidateCatalogContent)
if (-not ($candidateCatalogContent | Test-Json -SchemaFile $catalogSchemaPath -ErrorAction Stop)) {
    throw 'Staged Hosted instruction catalog schema validation failed'
}

if ($OutputFormat -eq 'Text') {
    Write-Host (Format-ValidationStatusLine -Status 'running' -Name 'staged-generation' -Detail 'Generating and validating catalog-owned instruction files outside the repository')
}
$stageRoot = Join-Path ([IO.Path]::GetTempPath()) ('hosted-catalog-apply-' + [guid]::NewGuid().ToString('N'))
$stageHostedRoot = Join-Path $stageRoot 'hosted_copilot'
try {
    $stageCatalogDirectory = Join-Path $stageHostedRoot 'copilot-rule-catalog'
    New-Item -ItemType Directory -Path $stageCatalogDirectory -Force | Out-Null
    [IO.File]::WriteAllBytes((Join-Path $stageCatalogDirectory 'instruction-catalog.json'), $candidateCatalogBytes)
    Copy-Item -LiteralPath $catalogSchemaPath -Destination (Join-Path $stageCatalogDirectory 'instruction-catalog.schema.json')
    Copy-Item -LiteralPath $resolvedProtectedRulesPath -Destination (Join-Path $stageCatalogDirectory 'protected-rules.json')
    Copy-Item -LiteralPath $protectedRulesSchemaPath -Destination (Join-Path $stageCatalogDirectory 'protected-rules.schema.json')
    $stageProtectedRulesSourceRoot = Join-Path $stageHostedRoot 'authored-rules/protected'
    New-Item -ItemType Directory -Path $stageProtectedRulesSourceRoot -Force | Out-Null
    Copy-Item -Path (Join-Path $resolvedProtectedRulesSourceRoot '*.rules.md') -Destination $stageProtectedRulesSourceRoot
    foreach ($surface in @($catalog.surfaces)) {
        $sourcePath = Join-Path $resolvedHostedRoot ([string]$surface.outputPath)
        $stagePath = Join-Path $stageHostedRoot ([string]$surface.outputPath)
        New-Item -ItemType Directory -Path (Split-Path -Parent $stagePath) -Force | Out-Null
        Copy-Item -LiteralPath $sourcePath -Destination $stagePath
    }

    $generationOutput = @(& pwsh -NoProfile -File $generatorPath -CatalogPath (Join-Path $stageCatalogDirectory 'instruction-catalog.json') -ProtectedRulesPath (Join-Path $stageCatalogDirectory 'protected-rules.json') -ProtectedRulesSourceRoot $stageProtectedRulesSourceRoot -HostedRoot $stageHostedRoot -Write -OutputFormat Json 2>&1)
    if ($LASTEXITCODE -ne 0) {
        throw (($generationOutput | Out-String).Trim())
    }
    $generationResult = ($generationOutput | Out-String) | ConvertFrom-Json
    if (-not $generationResult.success -or $generationResult.mode -cne 'write') {
        throw 'Staged Hosted instruction generation did not report success'
    }

    $targets = [Collections.Generic.List[object]]::new()
    $targets.Add([pscustomobject]@{
        Path = $resolvedCatalogPath
        OriginalBytes = $catalogBytes
        OriginalSha256 = $catalogSha256
        StagedBytes = $candidateCatalogBytes
    })
    foreach ($surface in @($catalog.surfaces)) {
        $targetPath = Join-Path $resolvedHostedRoot ([string]$surface.outputPath)
        $targetBytes = Get-FileBytes -Path $targetPath
        $stagePath = Join-Path $stageHostedRoot ([string]$surface.outputPath)
        $targets.Add([pscustomobject]@{
            Path = $targetPath
            OriginalBytes = $targetBytes
            OriginalSha256 = Get-Sha256 -Bytes $targetBytes
            StagedBytes = Get-FileBytes -Path $stagePath
        })
    }

    Invoke-AtomicReplacement -Files $targets.ToArray()
}
finally {
    Remove-Item -LiteralPath $stageRoot -Recurse -Force -ErrorAction SilentlyContinue
}

$newCatalogSha256 = Get-Sha256 -Bytes (Get-FileBytes -Path $resolvedCatalogPath)
$result = [ordered]@{
    status = 'passed'
    approvalPath = $resolvedApprovalPath
    catalogPath = $resolvedCatalogPath
    previousCatalogSha256 = $catalogSha256
    catalogSha256 = $newCatalogSha256
    approvedBy = [string]$approval.approvedBy.displayName
    mutationCount = @($approval.mutations).Count
    mutationRuleIds = $mutationIds
    generatedOutputs = @($catalog.surfaces | ForEach-Object { [string]$_.outputPath })
}

if ($OutputFormat -eq 'Json') {
    $result | ConvertTo-Json -Depth 6
}
else {
    Write-ValidationSectionHeader -Title 'Hosted catalog approval apply summary'
    Write-ValidationSummary -Fields ([ordered]@{
        Status = 'PASSED'
        Approver = $result.approvedBy
        Mutations = $result.mutationCount
        'Catalog SHA-256' = $result.catalogSha256
    })
    Write-ValidationSectionHeader -Title 'Applied rules'
    foreach ($ruleId in $mutationIds) {
        Write-Output (Format-ValidationStatusLine -Status 'passed' -Name $ruleId -Detail 'Catalog and generated instructions updated')
    }
    Complete-ValidationTextOutput
}
