[CmdletBinding()]
param(
    [ValidateSet('Text', 'Json')]
    [string]$OutputFormat = 'Text'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$changelogPath = Join-Path $repoRoot 'CHANGELOG.md'

if (-not (Test-Path -LiteralPath $changelogPath)) {
    throw "CHANGELOG.md was not found at $changelogPath"
}

$lines = Get-Content -LiteralPath $changelogPath
$issues = New-Object 'System.Collections.Generic.List[string]'
$releaseHeadings = New-Object 'System.Collections.Generic.List[object]'
$releaseVersions = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::Ordinal)
$references = New-Object 'System.Collections.Generic.Dictionary[string, object]' ([System.StringComparer]::Ordinal)

for ($i = 0; $i -lt $lines.Count; $i++) {
    $line = $lines[$i]
    $lineNumber = $i + 1

    if ($line -match '^## \[(?<version>\d+\.\d+\.\d+)\](?:\s+-\s+\d{4}-\d{2}-\d{2})?\s*$') {
        $version = $Matches['version']
        $releaseHeadings.Add([pscustomobject]@{
            version = $version
            lineNumber = $lineNumber
        })
        [void]$releaseVersions.Add($version)
        continue
    }

    if ($line -match '^\[(?<label>[^\]]+)\]:\s+(?<url>\S+)\s*$') {
        $label = $Matches['label']
        $url = $Matches['url']

        if ($references.ContainsKey($label)) {
            $issues.Add(("Line {0}: duplicate changelog reference definition ``[{1}]``" -f $lineNumber, $label))
            continue
        }

        $references.Add($label, [pscustomobject]@{
            url = $url
            lineNumber = $lineNumber
        })
    }
}

$latestRelease = $null
if ($releaseHeadings.Count -eq 0) {
    $issues.Add('No released changelog sections were found; expected at least one ``## [X.Y.Z]`` heading below ``Unreleased``')
}
else {
    $latestRelease = $releaseHeadings[0].version
}

$repoBase = $null
foreach ($reference in $references.Values) {
    if ($reference.url -match '^https://github\.com/(?<slug>[^/\s]+/[^/\s]+)/(?:compare|releases/tag)/') {
        $repoBase = "https://github.com/$($Matches['slug'])"
        break
    }
}

if ($null -eq $repoBase) {
    $issues.Add('Could not determine the canonical GitHub repository base URL from changelog footer links')
}

if ($references.ContainsKey('Unreleased')) {
    if ($null -ne $latestRelease -and $null -ne $repoBase) {
        $expectedUnreleasedUrl = "$repoBase/compare/v$latestRelease...HEAD"
        $actualUnreleasedUrl = $references['Unreleased'].url
        if ($actualUnreleasedUrl -ne $expectedUnreleasedUrl) {
            $issues.Add(("Line {0}: ``[Unreleased]`` must target ``{1}``, found ``{2}``" -f $references['Unreleased'].lineNumber, $expectedUnreleasedUrl, $actualUnreleasedUrl))
        }
    }
}
else {
    $issues.Add('Missing changelog footer reference for ``[Unreleased]``')
}

foreach ($releaseHeading in $releaseHeadings) {
    $version = $releaseHeading.version
    if (-not $references.ContainsKey($version)) {
        $issues.Add(("Line {0}: missing changelog footer reference for released version ``[{1}]``" -f $releaseHeading.lineNumber, $version))
        continue
    }

    if ($null -eq $repoBase) {
        continue
    }

    $expectedReleaseUrl = "$repoBase/releases/tag/v$version"
    $actualReleaseUrl = $references[$version].url
    if ($actualReleaseUrl -ne $expectedReleaseUrl) {
        $issues.Add(("Line {0}: ``[{1}]`` must target ``{2}``, found ``{3}``" -f $references[$version].lineNumber, $version, $expectedReleaseUrl, $actualReleaseUrl))
    }
}

foreach ($label in $references.Keys) {
    if ($label -eq 'Unreleased') {
        continue
    }

    if ($label -notmatch '^\d+\.\d+\.\d+$') {
        continue
    }

    if (-not $releaseVersions.Contains($label)) {
        $issues.Add(("Line {0}: footer reference ``[{1}]`` does not match any released changelog heading" -f $references[$label].lineNumber, $label))
    }
}

$result = [ordered]@{
    status = if ($issues.Count -eq 0) { 'passed' } else { 'failed' }
    changelogPath = $changelogPath
    latestRelease = $latestRelease
    releaseHeadingCount = $releaseHeadings.Count
    referenceCount = $references.Count
    issueCount = $issues.Count
    issues = @($issues)
}

if ($OutputFormat -eq 'Json') {
    $result | ConvertTo-Json -Depth 8
}
else {
    Write-Output 'Changelog consistency validation summary'
    Write-Output ("  Status               : {0}" -f $result.status)
    Write-Output ("  Changelog Path       : {0}" -f $result.changelogPath)
    Write-Output ("  Latest Release       : {0}" -f $(if ($null -ne $latestRelease) { $latestRelease } else { 'n/a' }))
    Write-Output ("  Release Headings     : {0}" -f $result.releaseHeadingCount)
    Write-Output ("  Footer References    : {0}" -f $result.referenceCount)
    Write-Output ("  Issue Count          : {0}" -f $result.issueCount)

    if ($issues.Count -gt 0) {
        Write-Output ''
        Write-Output 'Issues'
        foreach ($issue in $issues) {
            Write-Output ("  - {0}" -f $issue)
        }
    }
}

if ($issues.Count -gt 0) {
    exit 1
}
