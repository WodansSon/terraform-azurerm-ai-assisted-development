Set-StrictMode -Version Latest

function Get-HostedReviewRepositoryFromRemote {
    param(
        [Parameter(Mandatory = $true)]
        [string]$RepoDirectory,

        [string]$Remote = 'origin'
    )

    $gitCommand = Get-Command git -ErrorAction SilentlyContinue
    if ($null -eq $gitCommand) {
        throw 'git was not found on PATH'
    }

    $remoteUrl = @(& $gitCommand.Source -C $RepoDirectory config --get "remote.$Remote.url" 2>&1)
    if ($LASTEXITCODE -ne 0 -or $remoteUrl.Count -ne 1) {
        throw "Could not resolve Git remote `$Remote` from $RepoDirectory"
    }

    $match = [regex]::Match(([string]$remoteUrl[0]).Trim(), '^(?:https://github\.com/|git@github\.com:|ssh://git@github\.com/)(?<repository>[^/\s]+/[^/\s]+?)(?:\.git)?$')
    if (-not $match.Success) {
        throw "Git remote `$Remote` is not a supported GitHub repository URL: $($remoteUrl[0])"
    }

    return $match.Groups['repository'].Value
}

function Invoke-HostedReviewGitHubApi {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Endpoint,

        [ValidateSet('GET', 'POST', 'PATCH')]
        [string]$Method = 'GET',

        [hashtable]$Fields = @{},

        [string]$Accept = 'application/vnd.github+json',

        [switch]$Raw
    )

    $ghCommand = Get-Command gh -ErrorAction SilentlyContinue
    if ($null -eq $ghCommand) {
        throw 'gh was not found on PATH'
    }

    $arguments = @('api', $Endpoint, '--method', $Method, '-H', "Accept: $Accept")
    foreach ($key in $Fields.Keys) {
        $arguments += @('-f', "$key=$($Fields[$key])")
    }
    $output = @(& $ghCommand.Source @arguments 2>&1)
    if ($LASTEXITCODE -ne 0) {
        throw "GitHub API request failed: $((($output | Out-String).Trim()))"
    }

    $content = $output -join "`n"
    if ($Raw) {
        return $content
    }

    return $content | ConvertFrom-Json
}

function Assert-HostedReviewWritableFork {
    param(
        [Parameter(Mandatory = $true)]
        [string]$RepoDirectory
    )

    $repository = Get-HostedReviewRepositoryFromRemote -RepoDirectory $RepoDirectory
    if ($repository.Equals('hashicorp/terraform-provider-azurerm', [StringComparison]::OrdinalIgnoreCase)) {
        throw 'Write operations against `hashicorp/terraform-provider-azurerm` are prohibited; use a personal writable fork'
    }

    $metadata = Invoke-HostedReviewGitHubApi -Endpoint "repos/$repository"
    $authenticatedUser = Invoke-HostedReviewGitHubApi -Endpoint 'user'
    if (-not [bool]$metadata.fork) {
        throw "Write operations require a GitHub fork; $repository is not reported as a fork"
    }
    $canonicalRepository = 'hashicorp/terraform-provider-azurerm'
    $sourceRepository = if ($null -ne $metadata.source) {
        [string]$metadata.source.full_name
    }
    elseif ($null -ne $metadata.parent) {
        [string]$metadata.parent.full_name
    }
    else {
        $null
    }
    if (-not $canonicalRepository.Equals($sourceRepository, [StringComparison]::OrdinalIgnoreCase)) {
        throw "Write operations require a fork of $canonicalRepository; found $repository"
    }
    if (-not ([string]$metadata.owner.login).Equals([string]$authenticatedUser.login, [StringComparison]::OrdinalIgnoreCase)) {
        throw "Write operations require a personal fork owned by the authenticated GitHub user `$($authenticatedUser.login)`; found $repository"
    }
    if ($null -ne $metadata.permissions -and -not [bool]$metadata.permissions.push) {
        throw "The authenticated GitHub user does not have push permission for $repository"
    }

    return [pscustomobject]@{
        repository = [string]$metadata.full_name
        parentRepository = if ($null -eq $metadata.parent) { $null } else { [string]$metadata.parent.full_name }
        sourceRepository = $sourceRepository
        authenticatedUser = [string]$authenticatedUser.login
    }
}

Export-ModuleMember -Function @(
    'Get-HostedReviewRepositoryFromRemote',
    'Invoke-HostedReviewGitHubApi',
    'Assert-HostedReviewWritableFork'
)
