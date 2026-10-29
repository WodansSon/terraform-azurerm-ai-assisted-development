Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Import-Module (Join-Path $PSScriptRoot '../shared/HostedGitHub.Helpers.psm1') -Force

function Get-HostedWorkbenchGitHubContext {
    param(
        [Parameter(Mandatory = $true)][string]$RepositoryRoot,
        [switch]$SkipGitHubAuthorization
    )

    $maintainerIdentity = [ordered]@{
        status = 'unavailable'
        login = $null
        isCodeOwner = $false
        reason = 'GitHub CLI authentication is required for CODEOWNER-only Workbench actions.'
    }
    $targetRepository = [ordered]@{
        status = 'unavailable'
        repository = $null
        branch = $null
        commit = $null
        upstreamRepository = $null
        upstreamBranch = $null
        aheadBy = $null
        behindBy = $null
        reason = 'GitHub CLI authentication is required to resolve the promotion target.'
    }
    if ($SkipGitHubAuthorization) {
        return [pscustomobject]@{
            maintainerIdentity = $maintainerIdentity
            targetRepository = $targetRepository
        }
    }

    try {
        $login = Invoke-HostedGitHubApi -Endpoint user -Jq '.login'
    }
    catch {
        return [pscustomobject]@{
            maintainerIdentity = $maintainerIdentity
            targetRepository = $targetRepository
        }
    }

    $codeOwnersPath = Join-Path $RepositoryRoot '.github/CODEOWNERS'
    $applicableOwners = @(Get-HostedToolkitCodeOwners -CodeOwnersPath $codeOwnersPath)
    $isCodeOwner = "@$login" -in $applicableOwners
    $maintainerIdentity = [ordered]@{
        status = if ($isCodeOwner) { 'validated' } else { 'unauthorized' }
        login = $login
        isCodeOwner = $isCodeOwner
        reason = if ($isCodeOwner) { $null } else { 'The authenticated GitHub user is not a CODEOWNER for Hosted Toolkit changes.' }
    }

    try {
        $target = Get-HostedGitHubForkTarget -Login $login
        $targetRepository = [ordered]@{
            status = 'validated'
            repository = $target.repository
            branch = $target.branch
            commit = $target.commit
            upstreamRepository = $target.upstreamRepository
            upstreamBranch = $target.upstreamBranch
            aheadBy = $target.aheadBy
            behindBy = $target.behindBy
            reason = $null
        }
    }
    catch {
        $targetRepository.reason = if ($_.Exception.Message -match 'not a valid fork') {
            "The authenticated user's terraform-provider-azurerm repository is not a valid fork promotion target."
        }
        else {
            "The authenticated user's terraform-provider-azurerm fork could not be resolved."
        }
    }

    return [pscustomobject]@{
        maintainerIdentity = $maintainerIdentity
        targetRepository = $targetRepository
    }
}

Export-ModuleMember -Function Get-HostedWorkbenchGitHubContext
