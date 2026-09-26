Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$helpersPath = Join-Path $PSScriptRoot '../shared/HostedToolkit.Helpers.psm1'
Import-Module -Name $helpersPath

function Get-ContributorSourceId {
    param([Parameter(Mandatory = $true)][string]$RelativePath)

    if ($RelativePath -ceq 'README.md') {
        return 'contributing-readme'
    }
    if ($RelativePath -notmatch '^(?:topics/)?(?<path>[a-z0-9-]+(?:/[a-z0-9-]+)*)\.md$') {
        throw "Contributor document path cannot produce a stable source ID: $RelativePath"
    }
    return $Matches['path'].Replace('/', '-')
}

function Get-ContributorGuidanceInventoryRecords {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [object[]]$Documents,

        [Parameter(Mandatory = $true)]
        [string]$Repository,

        [Parameter(Mandatory = $true)]
        [ValidatePattern('^[0-9a-f]{40}$')]
        [string]$ResolvedCommit,

        [Parameter(Mandatory = $true)]
        [string]$RootPath
    )

    if ($Repository -cne 'hashicorp/terraform-provider-azurerm') {
        throw "Unsupported Contributor Guidance repository: $Repository"
    }

    $orderedDocuments = [Collections.Generic.List[object]]::new()
    foreach ($document in $Documents) {
        $orderedDocuments.Add($document)
    }
    $orderedDocuments.Sort([Comparison[object]]{
        param($left, $right)
        return [StringComparer]::Ordinal.Compare([string]$left.RelativePath, [string]$right.RelativePath)
    })

    $records = [Collections.Generic.List[object]]::new()
    $seenIds = @{}
    foreach ($document in $orderedDocuments) {
        $relativePath = [string]$document.RelativePath
        $sourceId = Get-ContributorSourceId -RelativePath $relativePath
        if ($seenIds.ContainsKey($sourceId)) {
            throw "Duplicate Contributor Guidance source ID: $sourceId"
        }
        $seenIds[$sourceId] = $true

        $content = ([string]$document.Content).Replace("`r`n", "`n").Replace("`r", "`n")
        $titleMatch = [regex]::Match($content, '(?m)^# (?<title>\S.*)$')
        if (-not $titleMatch.Success) {
            throw "Contributor document is missing one H1 title: $relativePath"
        }
        $location = "$RootPath/$relativePath"
        $records.Add([ordered]@{
            sourceId = $sourceId
            presence = 'present'
            sourceLifecycle = 'active'
            location = $location
            contentSha256 = Get-Sha256 -Content $content
            content = $content
            title = $titleMatch.Groups['title'].Value.Trim()
            repository = $Repository
            resolvedCommit = $ResolvedCommit
            referenceUrl = "https://github.com/$Repository/blob/$ResolvedCommit/$location"
        })
    }

    return $records.ToArray()
}

Export-ModuleMember -Function Get-ContributorGuidanceInventoryRecords
