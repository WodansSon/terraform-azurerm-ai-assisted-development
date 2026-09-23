Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-AuthoredRuleSha256 {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Content
    )

    $bytes = [Text.Encoding]::UTF8.GetBytes($Content)
    $hash = [Security.Cryptography.SHA256]::HashData($bytes)
    return [Convert]::ToHexString($hash).ToLowerInvariant()
}

function Get-AuthoredRuleBlocks {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$SourcePaths,

        [Parameter(Mandatory = $true)]
        [string]$RepositoryRoot,

        [Parameter(Mandatory = $true)]
        [string]$ChannelName,

        [Parameter(Mandatory = $true)]
        [string[]]$AllowedFields,

        [string[]]$AllowedFrontmatterFields = @('description', 'surface')
    )

    $idPrefixes = @{ documentation = 'DOCS-'; implementation = 'IMPL-'; testing = 'TEST-' }
    $orderedSourcePaths = [string[]]@($SourcePaths)
    [Array]::Sort($orderedSourcePaths, [StringComparer]::Ordinal)
    $records = [Collections.Generic.List[object]]::new()
    $seenIds = @{}
    $utf8 = [Text.UTF8Encoding]::new($false, $true)

    foreach ($sourcePath in $orderedSourcePaths) {
        if (-not (Test-Path -LiteralPath $sourcePath -PathType Leaf)) {
            throw "$ChannelName rule source was not found: $sourcePath"
        }

        try {
            $content = $utf8.GetString([IO.File]::ReadAllBytes($sourcePath))
        }
        catch {
            throw "$ChannelName rule source is not valid UTF-8: $sourcePath"
        }
        if ($content.Length -gt 0 -and $content[0] -eq [char]0xFEFF) {
            throw "$ChannelName rule source must not contain a UTF-8 BOM: $sourcePath"
        }

        [string[]]$lines = $content.Replace("`r`n", "`n").Replace("`r", "`n") -split "`n"
        if ($lines.Count -lt 4 -or $lines[0] -cne '---') {
            throw "$ChannelName rule source frontmatter is invalid: $sourcePath"
        }
        $frontmatterEnd = [Array]::IndexOf($lines, '---', 1)
        if ($frontmatterEnd -lt 1) {
            throw "$ChannelName rule source frontmatter is invalid: $sourcePath"
        }

        $frontmatter = @{}
        foreach ($line in $lines[1..($frontmatterEnd - 1)]) {
            if ($line -notmatch '^(?<key>[A-Za-z][A-Za-z0-9]*): (?<value>\S.*)$') {
                throw "$ChannelName rule source frontmatter is invalid: $sourcePath"
            }
            $key = [string]$Matches['key']
            if ($frontmatter.ContainsKey($key)) {
                throw "$ChannelName rule source repeats frontmatter field $key`: $sourcePath"
            }
            $frontmatter[$key] = [string]$Matches['value']
        }
        foreach ($requiredField in @('description', 'surface')) {
            if (-not $frontmatter.ContainsKey($requiredField)) {
                throw "$ChannelName rule source is missing frontmatter field $requiredField`: $sourcePath"
            }
        }
        $unsupportedFrontmatter = @($frontmatter.Keys | Where-Object { $_ -notin $AllowedFrontmatterFields })
        if ($unsupportedFrontmatter.Count -gt 0) {
            throw "$ChannelName rule source has unsupported frontmatter fields: $sourcePath"
        }

        $surface = [string]$frontmatter.surface
        if (-not $idPrefixes.ContainsKey($surface)) {
            throw "$ChannelName rule source has unsupported surface $surface`: $sourcePath"
        }

        $headingIndexes = [Collections.Generic.List[int]]::new()
        $insideComment = $false
        for ($lineIndex = $frontmatterEnd + 1; $lineIndex -lt $lines.Count; $lineIndex++) {
            if ($lines[$lineIndex] -match '^\s*<!--') {
                $insideComment = $lines[$lineIndex] -notmatch '-->\s*$'
                continue
            }
            if ($insideComment) {
                if ($lines[$lineIndex] -match '-->\s*$') {
                    $insideComment = $false
                }
                continue
            }
            if ($lines[$lineIndex] -match '^### ') {
                if ($lines[$lineIndex] -notmatch '^### (?<id>[A-Z]+(?:-[A-Z0-9]+)+-[0-9]{3}[A-Z]?): (?<title>.+)$') {
                    throw "$ChannelName rule heading is invalid at $sourcePath`:$($lineIndex + 1)"
                }
                $headingIndexes.Add($lineIndex)
            }
        }

        for ($headingPosition = 0; $headingPosition -lt $headingIndexes.Count; $headingPosition++) {
            $startIndex = $headingIndexes[$headingPosition]
            $endIndex = if ($headingPosition + 1 -lt $headingIndexes.Count) { $headingIndexes[$headingPosition + 1] - 1 } else { $lines.Count - 1 }
            $null = $lines[$startIndex] -match '^### (?<id>[A-Z]+(?:-[A-Z0-9]+)+-[0-9]{3}[A-Z]?): (?<title>.+)$'
            $ruleId = [string]$Matches['id']
            $title = [string]$Matches['title']
            if (-not $ruleId.StartsWith($idPrefixes[$surface], [StringComparison]::Ordinal)) {
                throw "$ChannelName rule $ruleId does not match the $surface surface"
            }
            if ($seenIds.ContainsKey($ruleId)) {
                throw "Duplicate $ChannelName rule ID: $ruleId"
            }
            $seenIds[$ruleId] = $true

            $fields = @{}
            for ($fieldLineIndex = $startIndex + 1; $fieldLineIndex -le $endIndex; $fieldLineIndex++) {
                $line = $lines[$fieldLineIndex]
                if ([string]::IsNullOrWhiteSpace($line)) {
                    continue
                }
                if ($line -notmatch '^- (?<name>[^:]+): (?<value>\S.*)$') {
                    throw "$ChannelName rule $ruleId contains unsupported content: $line"
                }
                $fieldName = [string]$Matches['name']
                if ($fieldName -notin $AllowedFields) {
                    throw "$ChannelName rule $ruleId contains unsupported field $fieldName"
                }
                if ($fields.ContainsKey($fieldName)) {
                    throw "$ChannelName rule $ruleId repeats field $fieldName"
                }
                $fields[$fieldName] = [string]$Matches['value']
            }

            $normalizedLines = @($lines[$startIndex..$endIndex])
            while ($normalizedLines.Count -gt 0 -and [string]::IsNullOrWhiteSpace($normalizedLines[-1])) {
                $normalizedLines = @($normalizedLines[0..($normalizedLines.Count - 2)])
            }
            $normalizedContent = ((@($normalizedLines) | ForEach-Object { $_.TrimEnd() }) -join "`n").TrimEnd()
            $records.Add([pscustomobject]@{
                id = $ruleId
                title = $title
                surface = $surface
                fields = $fields
                sourcePath = $sourcePath
                relativeSourcePath = [IO.Path]::GetRelativePath($RepositoryRoot, $sourcePath).Replace('\', '/')
                normalizedContent = $normalizedContent
                contentSha256 = Get-AuthoredRuleSha256 -Content $normalizedContent
                frontmatter = $frontmatter
            })
        }
    }

    return $records.ToArray()
}

Export-ModuleMember -Function Get-AuthoredRuleBlocks
