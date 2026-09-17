Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$helpersPath = Join-Path $PSScriptRoot '../HostedToolkit.Helpers.psm1'
Import-Module -Name $helpersPath

function Get-NormalizedRuleBlock {
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
    if ($contentEnd -lt 0) {
        return ''
    }

    return ((@($Lines[0..$contentEnd]) | ForEach-Object { $_.TrimEnd() }) -join "`n").TrimEnd()
}

function Get-MaintainerProposalInventoryRecords {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$SourcePaths,

        [Parameter(Mandatory = $true)]
        [string]$RepositoryRoot,

        [string[]]$KnownHostedRuleIds = @()
    )

    $allowedProvenance = @('confirmed-maintainer-convention', 'inferred-maintainer-convention', 'local-safeguard')
    $idPrefixes = @{ documentation = 'DOCS-'; implementation = 'IMPL-'; testing = 'TEST-' }
    $knownHostedRules = @{}
    foreach ($ruleId in $KnownHostedRuleIds) {
        $knownHostedRules[$ruleId] = $true
    }

    $orderedSourcePaths = [string[]]@($SourcePaths)
    [Array]::Sort($orderedSourcePaths, [StringComparer]::Ordinal)
    $records = [Collections.Generic.List[object]]::new()
    $seenIds = @{}

    foreach ($sourcePath in $orderedSourcePaths) {
        if (-not (Test-Path -LiteralPath $sourcePath -PathType Leaf)) {
            throw "Maintainer rule source was not found: $sourcePath"
        }

        $content = [IO.File]::ReadAllText($sourcePath).Replace("`r`n", "`n").Replace("`r", "`n")
        [string[]]$lines = $content -split "`n"
        if ($lines.Count -lt 4 -or $lines[0] -ne '---') {
            throw "Maintainer rule source frontmatter is invalid: $sourcePath"
        }

        $frontmatterEnd = [Array]::IndexOf($lines, '---', 1)
        if ($frontmatterEnd -lt 1) {
            throw "Maintainer rule source frontmatter is invalid: $sourcePath"
        }

        $surfaceLines = @($lines[1..($frontmatterEnd - 1)] | Where-Object { $_ -match '^surface: (?<surface>[a-z]+)$' })
        if ($surfaceLines.Count -ne 1) {
            throw "Maintainer rule source must declare one surface: $sourcePath"
        }
        $null = $surfaceLines[0] -match '^surface: (?<surface>[a-z]+)$'
        $surface = [string]$Matches['surface']
        if (-not $idPrefixes.ContainsKey($surface)) {
            throw "Maintainer rule source has unsupported surface $surface`: $sourcePath"
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
                    throw "Maintainer rule heading is invalid at $sourcePath`:$($lineIndex + 1)"
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
                throw "Maintainer rule $ruleId does not match the $surface surface"
            }
            if ($seenIds.ContainsKey($ruleId)) {
                throw "Duplicate maintainer rule ID: $ruleId"
            }
            $seenIds[$ruleId] = $true

            $fields = @{}
            for ($fieldLineIndex = $startIndex + 1; $fieldLineIndex -le $endIndex; $fieldLineIndex++) {
                $line = $lines[$fieldLineIndex]
                if ([string]::IsNullOrWhiteSpace($line) -or $line -match '^<!--' -or $line -match '^-->$') {
                    continue
                }
                if ($line -notmatch '^- (?<name>Rule|Provenance|Rationale|Status): (?<value>\S.*)$') {
                    throw "Maintainer rule $ruleId contains unsupported content: $line"
                }
                $fieldName = [string]$Matches['name']
                if ($fields.ContainsKey($fieldName)) {
                    throw "Maintainer rule $ruleId repeats field $fieldName"
                }
                $fields[$fieldName] = [string]$Matches['value']
            }

            foreach ($requiredField in @('Rule', 'Provenance', 'Rationale')) {
                if (-not $fields.ContainsKey($requiredField)) {
                    throw "Maintainer rule $ruleId is missing field $requiredField"
                }
            }
            if ($fields['Provenance'] -notin $allowedProvenance) {
                throw "Maintainer rule $ruleId has unsupported provenance $($fields['Provenance'])"
            }

            $sourceStatus = if ($fields.ContainsKey('Status')) { [string]$fields['Status'] } else { 'active' }
            if ($sourceStatus -notin @('active', 'retired')) {
                throw "Maintainer rule $ruleId has unsupported status $sourceStatus"
            }
            if ($sourceStatus -eq 'retired' -and -not $knownHostedRules.ContainsKey($ruleId)) {
                throw "Retired maintainer rule $ruleId does not map to a Hosted rule"
            }

            $normalizedBlock = Get-NormalizedRuleBlock -Lines @($lines[$startIndex..$endIndex])
            $relativeSourcePath = [IO.Path]::GetRelativePath($RepositoryRoot, $sourcePath).Replace('\', '/')
            $records.Add([ordered]@{
                sourceId = $ruleId
                presence = 'present'
                sourceLifecycle = $sourceStatus
                location = $relativeSourcePath
                contentSha256 = Get-Sha256 -Content $normalizedBlock
                content = $normalizedBlock
                title = $title
                surface = $surface
                ruleText = [string]$fields['Rule']
                provenance = [string]$fields['Provenance']
                rationale = [string]$fields['Rationale']
                evidence = @()
            })
        }
    }

    return $records.ToArray()
}

Export-ModuleMember -Function Get-MaintainerProposalInventoryRecords
