Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Import-Module -Name (Join-Path $PSScriptRoot 'AuthoredRules.psm1') -Force

function Get-MaintainerProposalInventoryRecords {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$SourcePaths,

        [Parameter(Mandatory = $true)]
        [string]$RepositoryRoot
    )

    $remoteSourcePaths = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    $utf8 = [Text.UTF8Encoding]::new($false, $true)

    foreach ($sourcePath in $SourcePaths) {
        if (-not (Test-Path -LiteralPath $sourcePath -PathType Leaf)) {
            throw "Maintainer rule source was not found: $sourcePath"
        }

        try {
            $content = $utf8.GetString([IO.File]::ReadAllBytes($sourcePath))
        }
        catch {
            throw "Maintainer rule source is not valid UTF-8: $sourcePath"
        }
        if ($content.Length -gt 0 -and $content[0] -eq [char]0xFEFF) {
            throw "Maintainer rule source must not contain a UTF-8 BOM: $sourcePath"
        }

        [string[]]$lines = $content.Replace("`r`n", "`n").Replace("`r", "`n") -split "`n"
        if ($lines.Count -lt 4 -or $lines[0] -cne '---') {
            throw "Maintainer rule source frontmatter is invalid: $sourcePath"
        }
        $frontmatterEnd = [Array]::IndexOf($lines, '---', 1)
        if ($frontmatterEnd -lt 1) {
            throw "Maintainer rule source frontmatter is invalid: $sourcePath"
        }

        $frontmatter = @{}
        foreach ($line in $lines[1..($frontmatterEnd - 1)]) {
            if ($line -notmatch '^(?<key>[A-Za-z][A-Za-z0-9]*): (?<value>\S.*)$') {
                throw "Maintainer rule source frontmatter is invalid: $sourcePath"
            }
            $key = [string]$Matches['key']
            if ($frontmatter.ContainsKey($key)) {
                throw "Maintainer rule source repeats frontmatter field $key`: $sourcePath"
            }
            $frontmatter[$key] = [string]$Matches['value']
        }

        $isRemote = $frontmatter.ContainsKey('remoteRulesVersion')
        $expectedKeys = if ($isRemote) { @('description', 'remoteRulesVersion', 'surface') } else { @('description', 'surface') }
        $actualKeys = @($frontmatter.Keys | Sort-Object)
        if (($actualKeys -join [char]0) -cne ($expectedKeys -join [char]0)) {
            throw "Maintainer rule source has unsupported frontmatter fields: $sourcePath"
        }
        if ($isRemote) {
            if ([string]$frontmatter.remoteRulesVersion -cne '1') {
                throw "Maintainer rule source has unsupported remoteRulesVersion: $sourcePath"
            }
            $null = $remoteSourcePaths.Add([IO.Path]::GetFullPath($sourcePath))
        }
    }

    $blocks = @(Get-AuthoredRuleBlocks -SourcePaths $SourcePaths -RepositoryRoot $RepositoryRoot -ChannelName 'Maintainer' -AllowedFields @('Rule', 'Provenance', 'Rationale', 'Status') -AllowedFrontmatterFields @('description', 'surface', 'remoteRulesVersion'))
    $records = [Collections.Generic.List[object]]::new()
    $allowedProvenance = @('confirmed-maintainer-convention', 'inferred-maintainer-convention', 'local-safeguard')
    foreach ($block in $blocks) {
        foreach ($requiredField in @('Rule', 'Provenance', 'Rationale')) {
            if (-not $block.fields.ContainsKey($requiredField)) {
                throw "Maintainer rule $($block.id) is missing field $requiredField"
            }
        }
        if ([string]$block.fields['Provenance'] -cnotin $allowedProvenance) {
            throw "Maintainer rule $($block.id) has unsupported provenance $($block.fields['Provenance'])"
        }
        $sourceStatus = if ($block.fields.ContainsKey('Status')) { [string]$block.fields['Status'] } else { 'active' }
        if ($sourceStatus -cnotin @('active', 'retired')) {
            throw "Maintainer rule $($block.id) has unsupported status $sourceStatus"
        }
        $records.Add([ordered]@{
            sourceId = [string]$block.id
            presence = 'present'
            sourceLifecycle = $sourceStatus
            location = [string]$block.relativeSourcePath
            contentSha256 = [string]$block.contentSha256
            content = [string]$block.normalizedContent
            title = [string]$block.title
            surface = [string]$block.surface
            ruleText = [string]$block.fields['Rule']
            provenance = [string]$block.fields['Provenance']
            rationale = [string]$block.fields['Rationale']
            evidence = @()
        })
    }
    foreach ($sourcePath in $remoteSourcePaths) {
        $relativeSourcePath = [IO.Path]::GetRelativePath($RepositoryRoot, $sourcePath).Replace('\', '/')
        $remoteRecords = @($records | Where-Object { [string]$_.location -ceq $relativeSourcePath })
        if ($remoteRecords.Count -eq 0) {
            throw "Remote Rules source does not contain any rules: $sourcePath"
        }
        if ($remoteRecords.Count -gt 999) {
            throw "Remote Rules source contains more than 999 rules: $sourcePath"
        }
        $surfacePrefix = switch ([string]$remoteRecords[0].surface) {
            'documentation' { 'DOCS' }
            'implementation' { 'IMPL' }
            'testing' { 'TEST' }
            default { $null }
        }
        foreach ($record in $remoteRecords) {
            if ([string]$record.sourceId -cnotmatch "^$surfacePrefix-REMOTE-[A-F0-9]{8}-[0-9]{3}$") {
                throw "Remote Rules source ID is invalid: $($record.sourceId)"
            }
        }
    }

    return $records.ToArray()
}

Export-ModuleMember -Function Get-MaintainerProposalInventoryRecords
