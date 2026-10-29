Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$authoredRulesPath = Join-Path $PSScriptRoot 'AuthoredRules.psm1'
Import-Module -Name $authoredRulesPath -Force

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
    $knownHostedRules = @{}
    foreach ($ruleId in $KnownHostedRuleIds) {
        $knownHostedRules[$ruleId] = $true
    }

    $blocks = @(Get-AuthoredRuleBlocks -SourcePaths $SourcePaths -RepositoryRoot $RepositoryRoot -ChannelName 'Maintainer' -AllowedFields @('Rule', 'Provenance', 'Rationale', 'Status') -AllowedFrontmatterFields @('description', 'surface', 'remoteRulesVersion'))
    $records = [Collections.Generic.List[object]]::new()
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
        if ($sourceStatus -ceq 'retired' -and -not $knownHostedRules.ContainsKey([string]$block.id)) {
            throw "Retired maintainer rule $($block.id) does not map to a Hosted rule"
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

    return $records.ToArray()
}

Export-ModuleMember -Function Get-MaintainerProposalInventoryRecords
