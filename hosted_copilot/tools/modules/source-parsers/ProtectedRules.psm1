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

    $capture = Get-ProtectedRulesCapture -SourceRoot $SourceRoot -RepositoryRoot $RepositoryRoot
    return $capture.Catalog
}

function Get-ProtectedRulesCapture {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$SourceRoot,

        [Parameter(Mandatory = $true)]
        [string]$RepositoryRoot
    )

    $resolvedSourceRoot = [IO.Path]::GetFullPath($SourceRoot)
    $resolvedRepositoryRoot = [IO.Path]::GetFullPath($RepositoryRoot)
    $comparison = if ([OperatingSystem]::IsWindows()) { [StringComparison]::OrdinalIgnoreCase } else { [StringComparison]::Ordinal }
    $repositoryPrefix = $resolvedRepositoryRoot.TrimEnd([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar) + [IO.Path]::DirectorySeparatorChar
    if (-not $resolvedSourceRoot.Equals($resolvedRepositoryRoot, $comparison) -and -not $resolvedSourceRoot.StartsWith($repositoryPrefix, $comparison)) {
        throw 'Protected rule sources must be inside the bound repository'
    }
    if (-not (Test-Path -LiteralPath $resolvedSourceRoot -PathType Container)) {
        throw "Protected rules source directory was not found: $resolvedSourceRoot"
    }
    for ($ancestor = Get-Item -LiteralPath $resolvedSourceRoot -Force; $null -ne $ancestor; $ancestor = $ancestor.Parent) {
        if ($ancestor.Attributes -band [IO.FileAttributes]::ReparsePoint) {
            throw 'Protected rule sources must not use links or junctions'
        }
    }
    $requiredSurfaces = @('documentation', 'implementation', 'testing')
    foreach ($surface in $requiredSurfaces) {
        $surfacePath = Join-Path $resolvedSourceRoot "$surface.rules.md"
        if (-not (Test-Path -LiteralPath $surfacePath -PathType Leaf)) {
            throw "Protected rules are missing surface file: $surface"
        }
    }

    $sourcePaths = @(Get-ChildItem -LiteralPath $resolvedSourceRoot -Filter '*.rules.md' -File -Force | Select-Object -ExpandProperty FullName | Sort-Object -CaseSensitive)
    foreach ($surface in $requiredSurfaces) {
        $requiredPath = Join-Path $resolvedSourceRoot "$surface.rules.md"
        if (@($sourcePaths | Where-Object { [string]::Equals($_, $requiredPath, $comparison) }).Count -ne 1) {
            throw "Protected rules are missing surface file: $surface"
        }
    }
    $streams = [Collections.Generic.List[IO.FileStream]]::new()
    $sourceBytes = @{}
    $files = [Collections.Generic.List[object]]::new()
    try {
        foreach ($sourcePath in $sourcePaths) {
            $file = Get-Item -LiteralPath $sourcePath -Force
            if ($file.Attributes -band [IO.FileAttributes]::ReparsePoint) {
                throw 'Protected rule sources must not use links or junctions'
            }
            $stream = [IO.File]::Open($sourcePath, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::Read)
            $streams.Add($stream)
            $buffer = [IO.MemoryStream]::new()
            try {
                $stream.CopyTo($buffer)
                $bytes = $buffer.ToArray()
            }
            finally { $buffer.Dispose() }
            $sourceBytes[$sourcePath] = $bytes
            $files.Add([pscustomobject]@{
                relativePath = [IO.Path]::GetRelativePath($resolvedRepositoryRoot, $sourcePath).Replace('\', '/')
                contentBytes = $bytes
                contentSha256 = [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($bytes)).ToLowerInvariant()
            })
        }
        $currentPaths = @(Get-ChildItem -LiteralPath $resolvedSourceRoot -Filter '*.rules.md' -File -Force | Select-Object -ExpandProperty FullName | Sort-Object -CaseSensitive)
        if (@(Compare-Object $sourcePaths $currentPaths -CaseSensitive).Count) {
            throw 'Protected rule file set changed during capture'
        }
        $blocks = @(Get-AuthoredRuleBlocks -SourceBytes $sourceBytes -RepositoryRoot $resolvedRepositoryRoot -ChannelName 'Protected' -AllowedFields @('Rule', 'Provenance', 'Rationale'))
    }
    finally {
        foreach ($stream in $streams) { $stream.Dispose() }
    }
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

    return [pscustomobject]@{
        Files = $files.ToArray()
        Blocks = $blocks
        Catalog = [ordered]@{
            '$schema' = 'protected-rules.schema.json'
            schemaVersion = 1
            rules = $rules.ToArray()
        }
    }
}

function ConvertTo-ProtectedRulesJson {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [object]$Catalog
    )

    return ($Catalog | ConvertTo-Json -Depth 20).Replace("`r`n", "`n") + "`n"
}

Export-ModuleMember -Function Get-ProtectedRulesCatalog, Get-ProtectedRulesCapture, ConvertTo-ProtectedRulesJson
