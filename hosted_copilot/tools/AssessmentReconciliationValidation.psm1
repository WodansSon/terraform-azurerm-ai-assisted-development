Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$helpersPath = Join-Path $PSScriptRoot 'HostedToolkit.Helpers.psm1'
Import-Module -Name $helpersPath

function Get-HostedRuleChangeRecommendationsContractSha256 {
    param(
        [Parameter(Mandatory = $true)][object]$Contract,
        [Parameter(Mandatory = $true)][string]$RepositoryRoot
    )

    $families = [Collections.Generic.List[object]]::new()
    foreach ($family in @($Contract.idAllocation.families)) {
        $families.Add([ordered]@{
            category = [string]$family.category
            placement = [string]$family.placement
            idFamily = [string]$family.idFamily
        })
    }
    $families.Sort([Comparison[object]]{
        param($left, $right)
        $leftKey = [string]$left.category + [char]0 + [string]$left.placement + [char]0 + [string]$left.idFamily
        $rightKey = [string]$right.category + [char]0 + [string]$right.placement + [char]0 + [string]$right.idFamily
        return [StringComparer]::Ordinal.Compare($leftKey, $rightKey)
    })
    $allocationIdentity = [ordered]@{
        numericWidth = [int]$Contract.idAllocation.numericWidth
        families = $families.ToArray()
    } | ConvertTo-Json -Depth 10 -Compress

    return Get-BehaviorManifestSha256 -IdentityValues @([string]$Contract.contractId, $allocationIdentity) -BehaviorFiles @($Contract.behaviorFiles) -RepositoryRoot $RepositoryRoot -ManifestName "Hosted rule change recommendations contract $($Contract.contractId)"
}

function Get-AssessmentReconciliationReviewContractSha256 {
    param(
        [Parameter(Mandatory = $true)][object]$Contract,
        [Parameter(Mandatory = $true)][string]$RepositoryRoot
    )

    return Get-BehaviorManifestSha256 -IdentityValues @([string]$Contract.contractId) -BehaviorFiles @($Contract.behaviorFiles) -RepositoryRoot $RepositoryRoot -ManifestName "Assessment reconciliation review contract $($Contract.contractId)"
}

Export-ModuleMember -Function Get-HostedRuleChangeRecommendationsContractSha256, Get-AssessmentReconciliationReviewContractSha256
