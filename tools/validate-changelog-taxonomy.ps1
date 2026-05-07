[CmdletBinding()]
param(
    [ValidateSet('Text', 'Json')]
    [string]$OutputFormat = 'Text'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$changelogPath = Join-Path $repoRoot 'CHANGELOG.md'

$approvedTaxonomy = @(
    'Review',
    'Docs',
    'Installer',
    'Implementation',
    'Testing',
    'Skill Routing',
    'Internal'
)

$groupOrder = @(
    'User-Priority',
    'Maintainer/Workflow'
)

$groupTaxonomy = @{
    'User-Priority' = @('Review', 'Docs', 'Installer')
    'Maintainer/Workflow' = @('Implementation', 'Testing', 'Skill Routing', 'Internal')
}

$taxonomyOrder = @{}
for ($index = 0; $index -lt $approvedTaxonomy.Count; $index++) {
    $taxonomyOrder[$approvedTaxonomy[$index]] = $index
}

if (-not (Test-Path -LiteralPath $changelogPath)) {
    throw "CHANGELOG.md was not found at $changelogPath"
}

$lines = Get-Content -LiteralPath $changelogPath
$issues = New-Object 'System.Collections.Generic.List[string]'
$bulletCount = 0

$sectionData = @{
    'Added' = [ordered]@{ groups = New-Object 'System.Collections.Generic.List[object]'; blankLines = New-Object 'System.Collections.Generic.List[int]' }
    'Changed' = [ordered]@{ groups = New-Object 'System.Collections.Generic.List[object]'; blankLines = New-Object 'System.Collections.Generic.List[int]' }
    'Fixed' = [ordered]@{ groups = New-Object 'System.Collections.Generic.List[object]'; blankLines = New-Object 'System.Collections.Generic.List[int]' }
}

$inUnreleased = $false
$currentSection = $null
$currentGroup = $null

for ($i = 0; $i -lt $lines.Count; $i++) {
    $line = $lines[$i]
    $lineNumber = $i + 1

    if ($line -match '^## \[Unreleased\]') {
        $inUnreleased = $true
        $currentSection = $null
        $currentGroup = $null
        continue
    }

    if ($inUnreleased -and $line -match '^## \[' -and -not ($line -match '^## \[Unreleased\]')) {
        break
    }

    if (-not $inUnreleased) {
        continue
    }

    if ($line -match '^###\s+(Added|Changed|Fixed)\s*$') {
        $currentSection = $Matches[1]
        $currentGroup = $null

        if (($i + 1) -lt $lines.Count) {
            $nextLine = $lines[$i + 1]
            if (-not [string]::IsNullOrWhiteSpace($nextLine) -and -not ($nextLine -match '^## \[') -and -not ($nextLine -match '^###\s+')) {
                $issues.Add(("Line {0}: subsection heading ``### {1}`` must be followed by a blank line before the first group bullet or entry" -f $lineNumber, $currentSection))
            }
        }

        continue
    }

    if ($null -eq $currentSection) {
        continue
    }

    if ([string]::IsNullOrWhiteSpace($line)) {
        $sectionData[$currentSection].blankLines.Add($lineNumber)
        continue
    }

    if ($line -match '^- \*\*(User-Priority|Maintainer/Workflow):\*\*$') {
        $groupName = $Matches[1]
        $groupObject = [pscustomobject]@{
            name = $groupName
            lineNumber = $lineNumber
            entries = New-Object 'System.Collections.Generic.List[object]'
        }
        $sectionData[$currentSection].groups.Add($groupObject)
        $currentGroup = $groupObject
        continue
    }

    if ($line -match '^  - \*\*\[(?<taxonomy>[^\]]+)\]\*\* - ') {
        $bulletCount++
        $taxonomy = $Matches['taxonomy']

        if ($null -eq $currentGroup) {
            $issues.Add(("Line {0}: nested changelog entry is not under a ``**User-Priority:**`` or ``**Maintainer/Workflow:**`` group bullet" -f $lineNumber))
            continue
        }

        if ($approvedTaxonomy -notcontains $taxonomy) {
            $issues.Add(("Line {0}: unknown taxonomy tag ``[{1}]``" -f $lineNumber, $taxonomy))
            continue
        }

        $expectedGroup = $null
        foreach ($groupName in $groupOrder) {
            if ($groupTaxonomy[$groupName] -contains $taxonomy) {
                $expectedGroup = $groupName
                break
            }
        }

        if ($expectedGroup -ne $currentGroup.name) {
            $issues.Add(("Line {0}: taxonomy tag ``[{1}]`` is in the wrong group; it belongs under ``{2}``" -f $lineNumber, $taxonomy, $expectedGroup))
            continue
        }

        $currentGroup.entries.Add([pscustomobject]@{
            lineNumber = $lineNumber
            taxonomy = $taxonomy
            order = $taxonomyOrder[$taxonomy]
        })
        continue
    }

    if ($line -match '^- ') {
        $issues.Add(("Line {0}: invalid top-level bullet in Unreleased; use only ``- **User-Priority:**`` or ``- **Maintainer/Workflow:**`` at the top level" -f $lineNumber))
        continue
    }

    $issues.Add(("Line {0}: unexpected content inside the Unreleased ``{1}`` section" -f $lineNumber, $currentSection))
}

foreach ($sectionName in @('Added', 'Changed', 'Fixed')) {
    $groups = @($sectionData[$sectionName].groups.ToArray())
    $blankLines = @($sectionData[$sectionName].blankLines.ToArray())

    if ($groups.Count -eq 0) {
        continue
    }

    $seenGroups = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::Ordinal)
    $previousGroupOrder = -1

    foreach ($group in $groups) {
        if ($seenGroups.Contains($group.name)) {
            $issues.Add(("Line {0}: group ``{1}`` appears more than once in the Unreleased ``{2}`` section" -f $group.lineNumber, $group.name, $sectionName))
        }
        else {
            [void]$seenGroups.Add($group.name)
        }

        $groupIndex = [array]::IndexOf($groupOrder, $group.name)
        if ($groupIndex -lt $previousGroupOrder) {
            $issues.Add(("Line {0}: group ``{1}`` is out of order in the Unreleased ``{2}`` section; ``User-Priority`` must come before ``Maintainer/Workflow``" -f $group.lineNumber, $group.name, $sectionName))
        }
        $previousGroupOrder = $groupIndex

        $entries = @($group.entries.ToArray())
        if ($entries.Count -eq 0) {
            $issues.Add(("Line {0}: group ``{1}`` in the Unreleased ``{2}`` section has no nested entries" -f $group.lineNumber, $group.name, $sectionName))
            continue
        }

        $previousTaxonomyOrder = -1
        foreach ($entry in $entries) {
            if ($entry.order -lt $previousTaxonomyOrder) {
                $issues.Add(("Line {0}: taxonomy tag ``[{1}]`` is out of order in the Unreleased ``{2}`` section; use the fixed order [Review], [Docs], [Installer], [Implementation], [Testing], [Skill Routing], [Internal]" -f $entry.lineNumber, $entry.taxonomy, $sectionName))
            }
            $previousTaxonomyOrder = $entry.order
        }

        $groupLastEntryLine = (@($entries | Select-Object -Last 1))[0].lineNumber
        $blankInsideGroup = @($blankLines | Where-Object { $_ -gt $group.lineNumber -and $_ -lt $groupLastEntryLine })
        foreach ($blankLine in $blankInsideGroup) {
            $issues.Add(("Line {0}: unexpected blank line inside the ``{1}`` group in the Unreleased ``{2}`` section" -f $blankLine, $group.name, $sectionName))
        }
    }

    if ($groups.Count -gt 1) {
        for ($groupIndex = 0; $groupIndex -lt ($groups.Count - 1); $groupIndex++) {
            $current = $groups[$groupIndex]
            $next = $groups[$groupIndex + 1]
            $currentLastEntryLine = (@($current.entries.ToArray() | Select-Object -Last 1))[0].lineNumber
            $blankBetweenGroups = @($blankLines | Where-Object { $_ -gt $currentLastEntryLine -and $_ -lt $next.lineNumber })

            if ($blankBetweenGroups.Count -ne 1 -or $next.lineNumber -ne ($currentLastEntryLine + 2)) {
                $issues.Add(("Section ``{0}`` under Unreleased must contain exactly one blank line between the ``{1}`` and ``{2}`` groups" -f $sectionName, $current.name, $next.name))
            }
        }
    }
}

$result = [ordered]@{
    status = if ($issues.Count -eq 0) { 'passed' } else { 'failed' }
    changelogPath = $changelogPath
    section = 'Unreleased'
    approvedTaxonomy = $approvedTaxonomy
    groupOrder = $groupOrder
    bulletsChecked = $bulletCount
    issueCount = $issues.Count
    issues = @($issues)
}

if ($OutputFormat -eq 'Json') {
    $result | ConvertTo-Json -Depth 8
}
else {
    Write-Output 'Changelog taxonomy validation summary'
    Write-Output ("  Status            : {0}" -f $result.status)
    Write-Output ("  Changelog Path    : {0}" -f $result.changelogPath)
    Write-Output ("  Section           : {0}" -f $result.section)
    Write-Output ("  Bullets Checked   : {0}" -f $result.bulletsChecked)
    Write-Output ("  Issue Count       : {0}" -f $result.issueCount)
    Write-Output ("  Approved Taxonomy : {0}" -f (($approvedTaxonomy | ForEach-Object { "[{0}]" -f $_ }) -join ', '))
    Write-Output ("  Group Order       : {0}" -f (($groupOrder | ForEach-Object { "[{0}]" -f $_ }) -join ' -> '))

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
