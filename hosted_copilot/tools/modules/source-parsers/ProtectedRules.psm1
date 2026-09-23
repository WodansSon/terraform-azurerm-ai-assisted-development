Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$authoredRulesPath = Join-Path $PSScriptRoot 'AuthoredRules.psm1'
Import-Module -Name $authoredRulesPath -Force

function Get-ProtectedRulesCatalog {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$SourceRoot,

        [Parameter(Mandatory = $true)]
        [string]$RepositoryRoot
    )

    $resolvedSourceRoot = [IO.Path]::GetFullPath($SourceRoot)
    if (-not (Test-Path -LiteralPath $resolvedSourceRoot -PathType Container)) {
        throw "Protected rules source directory was not found: $resolvedSourceRoot"
    }
    foreach ($surface in @('documentation', 'implementation', 'testing')) {
        $surfacePath = Join-Path $resolvedSourceRoot "$surface.rules.md"
        if (-not (Test-Path -LiteralPath $surfacePath -PathType Leaf)) {
            throw "Protected rules are missing surface file: $surface"
        }
    }

    $sourcePaths = @(Get-ChildItem -LiteralPath $resolvedSourceRoot -Filter '*.rules.md' -File | Select-Object -ExpandProperty FullName)
    $blocks = @(Get-AuthoredRuleBlocks -SourcePaths $sourcePaths -RepositoryRoot $RepositoryRoot -ChannelName 'Protected' -AllowedFields @('Rule', 'Provenance', 'Rationale'))
    $allowedProvenance = @('confirmed-maintainer-convention', 'inferred-maintainer-convention', 'local-safeguard')
    $rules = [Collections.Generic.List[object]]::new()

    foreach ($block in $blocks) {
        foreach ($requiredField in @('Rule', 'Provenance', 'Rationale')) {
            if (-not $block.fields.ContainsKey($requiredField)) {
                throw "Protected rule $($block.id) is missing field $requiredField"
            }
        }
        if ([string]$block.fields['Provenance'] -cnotin $allowedProvenance) {
            throw "Protected rule $($block.id) has unsupported provenance $($block.fields['Provenance'])"
        }

        $rule = [ordered]@{
            id = [string]$block.id
            status = 'protected'
            surfaceId = [string]$block.surface
            title = [string]$block.title
            text = [string]$block.fields['Rule']
            provenance = [string]$block.fields['Provenance']
            protectionReason = [string]$block.fields['Rationale']
            impact = 100
            sourcePath = [string]$block.relativeSourcePath
            contentSha256 = [string]$block.contentSha256
        }
        $rules.Add($rule)
    }

    return [ordered]@{
        '$schema' = 'protected-rules.schema.json'
        schemaVersion = 1
        rules = $rules.ToArray()
    }
}

function ConvertTo-ProtectedRulesJson {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [object]$Catalog
    )

    return ($Catalog | ConvertTo-Json -Depth 20) + "`n"
}

Export-ModuleMember -Function Get-ProtectedRulesCatalog, ConvertTo-ProtectedRulesJson
