[CmdletBinding()]
param(
    [string]$RootPath = (Join-Path $PSScriptRoot '..'),

    [string]$CatalogPath = (Join-Path $PSScriptRoot 'interactive-rule-catalog/rule-catalog.json'),

    [string]$SchemaPath = (Join-Path $PSScriptRoot 'interactive-rule-catalog/rule-catalog.schema.json'),

    [string]$UpstreamManifestPath = (Join-Path $PSScriptRoot 'config/upstream-contributor.json'),

    [string]$InstallerManifestPath = (Join-Path $PSScriptRoot '../installer/file-manifest.config'),

    [ValidateSet('Text', 'Json')]
    [string]$OutputFormat = 'Text'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$validationOutputModulePath = Join-Path $PSScriptRoot 'ValidationOutput.psm1'
Import-Module -Name $validationOutputModulePath -Force

$repoRoot = [IO.Path]::GetFullPath($RootPath)
$resolvedCatalogPath = [IO.Path]::GetFullPath($CatalogPath)
$resolvedSchemaPath = [IO.Path]::GetFullPath($SchemaPath)
$resolvedUpstreamManifestPath = [IO.Path]::GetFullPath($UpstreamManifestPath)
$resolvedInstallerManifestPath = [IO.Path]::GetFullPath($InstallerManifestPath)
$issues = New-Object 'System.Collections.Generic.List[string]'

function Get-ContentSha256 {
    param(
        [Parameter(Mandatory = $true)]
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
    $contentLines = @($Lines[0..$contentEnd])
    $normalizedContent = (($contentLines | ForEach-Object { $_.TrimEnd() }) -join "`n").TrimEnd()
    return [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData([Text.Encoding]::UTF8.GetBytes($normalizedContent))).ToLowerInvariant()
}

function Get-OptionalPropertyValues {
    param(
        [Parameter(Mandatory = $true)]
        $InputObject,

        [Parameter(Mandatory = $true)]
        [string]$Name
    )

    $property = $InputObject.PSObject.Properties[$Name]
    if ($null -eq $property) {
        return @()
    }

    return @($property.Value)
}

function Get-ContractRuleInventory {
    param(
        [Parameter(Mandatory = $true)]
        [string]$RepositoryRoot
    )

    $inventory = New-Object 'System.Collections.Generic.List[object]'
    $contractRoot = Join-Path $RepositoryRoot '.github/instructions'
    $contractPaths = @(Get-ChildItem -LiteralPath $contractRoot -Filter '*-compliance-contract.instructions.md' -File | Sort-Object Name)

    foreach ($contractPath in $contractPaths) {
        $lines = @(Get-Content -LiteralPath $contractPath.FullName)
        $relativePath = [IO.Path]::GetRelativePath($RepositoryRoot, $contractPath.FullName).Replace('\', '/')
        $frontmatterDelimiterCount = 0
        foreach ($line in $lines) {
            if ($line -ne '---') {
                continue
            }
            $frontmatterDelimiterCount++
            if ($frontmatterDelimiterCount -gt 2) {
                $issues.Add("Runtime contract contains a non-semantic horizontal divider: $relativePath")
            }
        }

        for ($lineIndex = 0; $lineIndex -lt $lines.Count; $lineIndex++) {
            if ($lines[$lineIndex] -notmatch '^### (?<id>[A-Z]+(?:-[A-Z0-9]+)+-[0-9]{3}[A-Z]?): (?<title>.+)$') {
                continue
            }

            $ruleId = $Matches['id']
            $title = $Matches['title']
            $endIndex = $lineIndex + 1
            while ($endIndex -lt $lines.Count -and $lines[$endIndex] -notmatch '^#{2,3} ' -and $lines[$endIndex] -notmatch '^<!-- [A-Z0-9-]+-CONTRACT-EOF -->$') {
                $endIndex++
            }

            $ruleLines = @($lines[$lineIndex..($endIndex - 1)])
            if (@($ruleLines | Where-Object { $_ -match '^- \*\*(?:Provenance|Evidence)\*\*:' }).Count -gt 0) {
                $issues.Add("$ruleId retains embedded provenance or evidence metadata in $relativePath")
            }

            $inventory.Add([pscustomobject]@{
                    id = $ruleId
                    title = $title
                    contractPath = $relativePath
                    contentSha256 = Get-ContentSha256 -Lines $ruleLines
                })
        }
    }

    return @($inventory.ToArray())
}

if (-not (Test-Path -LiteralPath $resolvedSchemaPath -PathType Leaf)) {
    throw "Interactive rule catalog schema was not found: $resolvedSchemaPath"
}
if (-not (Test-Path -LiteralPath $resolvedCatalogPath -PathType Leaf)) {
    throw "Interactive rule catalog was not found: $resolvedCatalogPath"
}
if (-not (Test-Path -LiteralPath $resolvedUpstreamManifestPath -PathType Leaf)) {
    throw "Upstream contributor manifest was not found: $resolvedUpstreamManifestPath"
}
if (-not (Test-Path -LiteralPath $resolvedInstallerManifestPath -PathType Leaf)) {
    throw "Installer manifest was not found: $resolvedInstallerManifestPath"
}

$catalogContent = Get-Content -LiteralPath $resolvedCatalogPath -Raw
if (-not ($catalogContent | Test-Json -SchemaFile $resolvedSchemaPath)) {
    $issues.Add('Interactive rule catalog schema validation failed')
}

$catalog = $catalogContent | ConvertFrom-Json
$upstreamManifest = Get-Content -LiteralPath $resolvedUpstreamManifestPath -Raw | ConvertFrom-Json
$installerManifestContent = Get-Content -LiteralPath $resolvedInstallerManifestPath -Raw
$contractRules = @(Get-ContractRuleInventory -RepositoryRoot $repoRoot)
$catalogRules = @($catalog.rules)
$catalogRelativePaths = @(
    [IO.Path]::GetRelativePath($repoRoot, $resolvedCatalogPath).Replace('\', '/'),
    [IO.Path]::GetRelativePath($repoRoot, $resolvedSchemaPath).Replace('\', '/')
)
$shippedCatalogPaths = @($catalogRelativePaths | Where-Object { $installerManifestContent -match "(?m)^$([regex]::Escape($_))$" })
foreach ($shippedCatalogPath in $shippedCatalogPaths) {
    $issues.Add("Repo-only Interactive rule catalog file is listed in the installer manifest: $shippedCatalogPath")
}

$duplicateContractRuleIds = @($contractRules | Group-Object id | Where-Object Count -gt 1 | ForEach-Object Name)
foreach ($ruleId in $duplicateContractRuleIds) {
    $issues.Add("Contract rule ID appears more than once: $ruleId")
}

$duplicateCatalogRuleIds = @($catalogRules | Group-Object id | Where-Object Count -gt 1 | ForEach-Object Name)
foreach ($ruleId in $duplicateCatalogRuleIds) {
    $issues.Add("Catalog rule ID appears more than once: $ruleId")
}

$contractRulesById = @{}
foreach ($contractRule in $contractRules) {
    $contractRulesById[[string]$contractRule.id] = $contractRule
}

$catalogRulesById = @{}
foreach ($catalogRule in $catalogRules) {
    $catalogRulesById[[string]$catalogRule.id] = $catalogRule
}

$upstreamSourceIds = @($upstreamManifest.sources | ForEach-Object { [string]$_.id })
foreach ($catalogRule in $catalogRules) {
    $ruleId = [string]$catalogRule.id
    foreach ($sourceId in @($catalogRule.sourceIds)) {
        if ($sourceId -notin $upstreamSourceIds) {
            $issues.Add("$ruleId references unknown upstream source ID: $sourceId")
        }
    }

    foreach ($replacementId in @(Get-OptionalPropertyValues -InputObject $catalogRule -Name 'replacementIds')) {
        if (-not $catalogRulesById.ContainsKey([string]$replacementId)) {
            $issues.Add("$ruleId references unknown replacement rule ID: $replacementId")
        }
        elseif ($catalogRulesById[[string]$replacementId].status -eq 'retired') {
            $issues.Add("$ruleId references retired replacement rule ID: $replacementId")
        }
    }

    $contractRule = if ($contractRulesById.ContainsKey($ruleId)) { $contractRulesById[$ruleId] } else { $null }
    if ($catalogRule.status -eq 'retired') {
        if ($null -ne $contractRule) {
            $issues.Add("Retired catalog rule remains in a runtime contract: $ruleId")
        }
        continue
    }

    if ($null -eq $contractRule) {
        $issues.Add("$($catalogRule.status) catalog rule is missing from runtime contracts: $ruleId")
        continue
    }
    if ($catalogRule.contractPath -ne $contractRule.contractPath) {
        $issues.Add("$ruleId contract path mismatch: catalog=$($catalogRule.contractPath), runtime=$($contractRule.contractPath)")
    }
    if ($catalogRule.title -ne $contractRule.title) {
        $issues.Add("$ruleId title mismatch: catalog=$($catalogRule.title), runtime=$($contractRule.title)")
    }
    if ($catalogRule.contentSha256 -ne $contractRule.contentSha256) {
        $issues.Add("$ruleId runtime content changed without a matching catalog hash update")
    }
}

foreach ($contractRule in $contractRules) {
    if (-not $catalogRulesById.ContainsKey([string]$contractRule.id)) {
        $issues.Add("Runtime contract rule is missing from the catalog: $($contractRule.id)")
    }
    elseif ($catalogRulesById[[string]$contractRule.id].status -eq 'retired') {
        $issues.Add("Runtime contract rule is cataloged as retired: $($contractRule.id)")
    }
}

$result = [ordered]@{
    status = if ($issues.Count -eq 0) { 'passed' } else { 'failed' }
    catalogPath = [IO.Path]::GetRelativePath($repoRoot, $resolvedCatalogPath).Replace('\', '/')
    contractFileCount = @($contractRules.contractPath | Sort-Object -Unique).Count
    contractRuleCount = $contractRules.Count
    catalogRuleCount = $catalogRules.Count
    shippedCatalogFileCount = $shippedCatalogPaths.Count
    activeRuleCount = @($catalogRules | Where-Object status -eq 'active').Count
    deprecatedRuleCount = @($catalogRules | Where-Object status -eq 'deprecated').Count
    retiredRuleCount = @($catalogRules | Where-Object status -eq 'retired').Count
    unclassifiedRuleCount = @($catalogRules | Where-Object provenance -eq 'unclassified').Count
    issueCount = $issues.Count
    issues = @($issues.ToArray())
}

if ($OutputFormat -eq 'Json') {
    $result | ConvertTo-Json -Depth 10
}
else {
    Write-ValidationSectionHeader -Title 'Interactive rule catalog validation summary'
    Write-ValidationSummary -Fields ([ordered]@{
            Status = $result.status.ToUpperInvariant()
            'Contract Files' = $result.contractFileCount
            'Contract Rules' = $result.contractRuleCount
            'Catalog Rules' = $result.catalogRuleCount
            'Catalog Files Shipped' = $result.shippedCatalogFileCount
            Active = $result.activeRuleCount
            Deprecated = $result.deprecatedRuleCount
            Retired = $result.retiredRuleCount
            Unclassified = $result.unclassifiedRuleCount
            'Issue Count' = $result.issueCount
        })

    if ($issues.Count -gt 0) {
            Write-ValidationSectionHeader -Title 'Issues'
            foreach ($issue in $issues) {
                Write-Output ("  - {0}" -f $issue)
            }
    }

    Complete-ValidationTextOutput
}

if ($issues.Count -gt 0) {
    exit 1
}
