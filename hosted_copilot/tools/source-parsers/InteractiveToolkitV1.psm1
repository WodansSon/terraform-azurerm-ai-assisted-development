Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-ContentSha256 {
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string]$Content
    )

    $bytes = [Text.Encoding]::UTF8.GetBytes($Content)
    return [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($bytes)).ToLowerInvariant()
}

function Get-NormalizedRuleText {
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [AllowEmptyString()]
        [string[]]$Lines
    )

    $contentEnd = $Lines.Count - 1
    while ($contentEnd -ge 0 -and [string]::IsNullOrWhiteSpace($Lines[$contentEnd])) {
        $contentEnd--
    }
    if ($contentEnd -ge 0 -and $Lines[$contentEnd] -eq '---') {
        $contentEnd--
        while ($contentEnd -ge 0 -and [string]::IsNullOrWhiteSpace($Lines[$contentEnd])) {
            $contentEnd--
        }
    }
    if ($contentEnd -lt 0) {
        return ''
    }

    return ((@($Lines[0..$contentEnd]) | ForEach-Object { $_.TrimEnd() }) -join "`n").TrimEnd()
}

function Get-InteractiveToolkitInventoryRecords {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$CatalogPath,

        [Parameter(Mandatory = $true)]
        [string]$RepositoryRoot
    )

    $catalogSchemaPath = Join-Path (Split-Path -Parent $CatalogPath) 'rule-catalog.schema.json'
    if (-not (Test-Path -LiteralPath $CatalogPath -PathType Leaf)) {
        throw "Interactive rule catalog was not found: $CatalogPath"
    }
    if (-not (Test-Path -LiteralPath $catalogSchemaPath -PathType Leaf)) {
        throw "Interactive rule catalog schema was not found: $catalogSchemaPath"
    }

    $catalogJson = Get-Content -LiteralPath $CatalogPath -Raw
    if (-not (Test-Json -Json $catalogJson -SchemaFile $catalogSchemaPath -ErrorAction Stop)) {
        throw "Interactive rule catalog does not satisfy its schema: $CatalogPath"
    }
    $catalog = $catalogJson | ConvertFrom-Json
    $repositoryPrefix = [IO.Path]::GetFullPath($RepositoryRoot).TrimEnd([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar) + [IO.Path]::DirectorySeparatorChar
    $catalogRulesById = @{}
    foreach ($rule in @($catalog.rules)) {
        if ($catalogRulesById.ContainsKey([string]$rule.id)) {
            throw "Duplicate Interactive catalog rule ID: $($rule.id)"
        }
        $catalogRulesById[[string]$rule.id] = $rule
    }

    [string[]]$contractPaths = @($catalog.rules.contractPath | Select-Object -Unique)
    [Array]::Sort($contractPaths, [StringComparer]::Ordinal)
    $blocksById = @{}
    foreach ($relativeContractPath in $contractPaths) {
        $contractPath = [IO.Path]::GetFullPath((Join-Path $RepositoryRoot $relativeContractPath))
        if (-not $contractPath.StartsWith($repositoryPrefix, [StringComparison]::OrdinalIgnoreCase)) {
            throw "Interactive contract path escapes the repository root: $relativeContractPath"
        }
        if (-not (Test-Path -LiteralPath $contractPath -PathType Leaf)) {
            throw "Interactive contract was not found: $relativeContractPath"
        }

        $content = [IO.File]::ReadAllText($contractPath).Replace("`r`n", "`n").Replace("`r", "`n")
        [string[]]$lines = $content -split "`n"
        $lastNonEmptyLine = @($lines | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -Last 1)
        if ($lastNonEmptyLine.Count -ne 1 -or $lastNonEmptyLine[0] -notmatch '^<!-- [A-Z0-9-]+-CONTRACT-EOF -->$') {
            throw "Interactive contract is missing its EOF marker: $relativeContractPath"
        }

        for ($lineIndex = 0; $lineIndex -lt $lines.Count; $lineIndex++) {
            if ($lines[$lineIndex] -notmatch '^### (?<id>[A-Z]+(?:-[A-Z0-9]+)+-[0-9]{3}[A-Z]?): (?<title>.+)$') {
                continue
            }

            $ruleId = [string]$Matches['id']
            $title = [string]$Matches['title']
            if ($blocksById.ContainsKey($ruleId)) {
                throw "Duplicate Interactive contract rule ID: $ruleId"
            }

            $endIndex = $lineIndex + 1
            while ($endIndex -lt $lines.Count -and $lines[$endIndex] -notmatch '^#{2,3} ' -and $lines[$endIndex] -notmatch '^<!-- [A-Z0-9-]+-CONTRACT-EOF -->$') {
                $endIndex++
            }
            $normalizedText = Get-NormalizedRuleText -Lines @($lines[$lineIndex..($endIndex - 1)])
            $blocksById[$ruleId] = [pscustomobject]@{
                Title = $title
                Content = $normalizedText
                ContractPath = $relativeContractPath
            }
        }
    }

    $unknownRuleIds = @($blocksById.Keys | Where-Object { -not $catalogRulesById.ContainsKey($_) })
    if ($unknownRuleIds.Count -gt 0) {
        [Array]::Sort($unknownRuleIds, [StringComparer]::Ordinal)
        throw "Interactive contracts contain rules missing from the catalog: $($unknownRuleIds -join ', ')"
    }

    $records = [Collections.Generic.List[object]]::new()
    foreach ($rule in @($catalog.rules)) {
        $ruleId = [string]$rule.id
        if (-not $blocksById.ContainsKey($ruleId)) {
            throw "Interactive rule text was not found: $ruleId"
        }
        $block = $blocksById[$ruleId]
        if ([string]$block.ContractPath -cne [string]$rule.contractPath) {
            throw "Interactive rule $ruleId resolves from the wrong contract: $($block.ContractPath)"
        }
        if ([string]$block.Title -cne [string]$rule.title) {
            throw "Interactive rule title does not match its catalog entry: $ruleId"
        }
        $contentSha256 = Get-ContentSha256 -Content ([string]$block.Content)
        if ($contentSha256 -cne [string]$rule.contentSha256) {
            throw "Interactive rule text does not match its catalog hash: $ruleId"
        }

        $record = [ordered]@{
            sourceId = $ruleId
            presence = 'present'
            sourceLifecycle = [string]$rule.status
            location = [string]$rule.contractPath
            contentSha256 = $contentSha256
            content = [string]$block.Content
            title = [string]$rule.title
            contractPath = [string]$rule.contractPath
            provenance = [string]$rule.provenance
            evidence = @($rule.evidence)
            sourceIds = @($rule.sourceIds)
        }
        foreach ($optionalProperty in @('replacementIds', 'deprecatedOn', 'retiredOn', 'lifecycleReason')) {
            if ($rule.PSObject.Properties[$optionalProperty]) {
                $record[$optionalProperty] = $rule.$optionalProperty
            }
        }
        $records.Add($record)
    }

    return $records.ToArray()
}

Export-ModuleMember -Function Get-InteractiveToolkitInventoryRecords
