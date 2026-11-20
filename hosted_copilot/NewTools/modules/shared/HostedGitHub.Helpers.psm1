Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Invoke-HostedGitHubCli {
    param(
        [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string[]]$Arguments,
        [AllowEmptyString()][string]$InputText
    )

    $ghCommand = Get-Command gh -ErrorAction SilentlyContinue
    if ($null -eq $ghCommand) {
        throw 'gh was not found on PATH'
    }

    $startInfo = [Diagnostics.ProcessStartInfo]::new()
    $startInfo.FileName = $ghCommand.Source
    $startInfo.UseShellExecute = $false
    $startInfo.RedirectStandardInput = $PSBoundParameters.ContainsKey('InputText')
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true
    $startInfo.StandardOutputEncoding = [Text.UTF8Encoding]::new($false)
    $startInfo.StandardErrorEncoding = [Text.UTF8Encoding]::new($false)
    foreach ($argument in $Arguments) {
        $startInfo.ArgumentList.Add($argument)
    }

    $process = [Diagnostics.Process]::new()
    $process.StartInfo = $startInfo
    try {
        $null = $process.Start()
        if ($startInfo.RedirectStandardInput) {
            $process.StandardInput.Write($InputText)
            $process.StandardInput.Close()
        }
        $stdoutTask = $process.StandardOutput.ReadToEndAsync()
        $stderrTask = $process.StandardError.ReadToEndAsync()
        $process.WaitForExit()
        $exitCode = $process.ExitCode
        $stdout = $stdoutTask.GetAwaiter().GetResult()
        $stderr = $stderrTask.GetAwaiter().GetResult()
    }
    finally {
        $process.Dispose()
    }

    if ($exitCode -ne 0) {
        $diagnostic = if ([string]::IsNullOrWhiteSpace($stderr)) { $stdout.Trim() } else { $stderr.Trim() }
        throw "GitHub CLI command failed: $diagnostic"
    }

    return $stdout
}

function Invoke-HostedGitHubApi {
    param(
        [Parameter(Mandatory = $true)][string]$Endpoint,
        [ValidateSet('GET', 'POST', 'PATCH')][string]$Method = 'GET',
        [Collections.IDictionary]$Fields = @{},
        [string]$Accept = 'application/vnd.github+json',
        [string]$Jq,
        [switch]$Raw
    )

    $arguments = [Collections.Generic.List[string]]::new()
    foreach ($argument in @('api', $Endpoint, '--method', $Method, '-H', "Accept: $Accept")) {
        $arguments.Add($argument)
    }
    foreach ($key in @($Fields.Keys | Sort-Object)) {
        $arguments.Add('-f')
        $arguments.Add("$key=$($Fields[$key])")
    }
    if (-not [string]::IsNullOrWhiteSpace($Jq)) {
        $arguments.Add('--jq')
        $arguments.Add($Jq)
    }

    try {
        $stdout = Invoke-HostedGitHubCli -Arguments $arguments
    }
    catch {
        throw "GitHub API request failed for $Endpoint`: $($_.Exception.Message)"
    }

    $content = $stdout.Trim()
    if ($Raw -or -not [string]::IsNullOrWhiteSpace($Jq)) {
        return $content
    }
    if ([string]::IsNullOrWhiteSpace($content)) {
        return $null
    }
    return $content | ConvertFrom-Json
}

function Get-HostedToolkitCodeOwners {
    param([Parameter(Mandatory = $true)][string]$CodeOwnersPath)

    if (-not (Test-Path -LiteralPath $CodeOwnersPath -PathType Leaf)) {
        return @()
    }

    [string[]]$owners = @()
    foreach ($line in Get-Content -LiteralPath $CodeOwnersPath) {
        $trimmed = $line.Trim()
        if ([string]::IsNullOrWhiteSpace($trimmed) -or $trimmed.StartsWith('#')) {
            continue
        }
        $parts = @($trimmed -split '\s+' | Where-Object { $_ })
        if ($parts.Count -ge 2 -and $parts[0] -in @('*', '/hosted_copilot/')) {
            $owners = @($parts[1..($parts.Count - 1)])
        }
    }
    return $owners
}

function Get-HostedGitHubForkTarget {
    param(
        [Parameter(Mandatory = $true)][string]$Login,
        [string]$RepositoryName = 'terraform-provider-azurerm',
        [string]$CanonicalRepository = 'hashicorp/terraform-provider-azurerm'
    )

    $repositoryNameWithOwner = "$Login/$RepositoryName"
    $repository = Invoke-HostedGitHubApi -Endpoint "repos/$repositoryNameWithOwner"
    if ($repository.fork -ne $true -or [string]$repository.parent.full_name -cne $CanonicalRepository) {
        throw "The authenticated user's $RepositoryName repository is not a valid fork of $CanonicalRepository"
    }

    $branch = [string]$repository.default_branch
    $commit = Invoke-HostedGitHubApi -Endpoint "repos/$repositoryNameWithOwner/commits/$branch" -Jq '.sha'
    if ($commit -notmatch '^[0-9a-f]{40}$') {
        throw "The target commit for $repositoryNameWithOwner@$branch could not be resolved"
    }

    $upstreamRepository = [string]$repository.parent.full_name
    $upstreamBranch = [string]$repository.parent.default_branch
    $comparison = try {
        Invoke-HostedGitHubApi -Endpoint "repos/$upstreamRepository/compare/$upstreamBranch...$Login`:$branch"
    }
    catch {
        $null
    }

    return [pscustomobject]@{
        repository = [string]$repository.full_name
        branch = $branch
        commit = $commit
        upstreamRepository = $upstreamRepository
        upstreamBranch = $upstreamBranch
        aheadBy = if ($null -ne $comparison) { [int]$comparison.ahead_by } else { $null }
        behindBy = if ($null -ne $comparison) { [int]$comparison.behind_by } else { $null }
    }
}

Export-ModuleMember -Function @(
    'Invoke-HostedGitHubCli',
    'Invoke-HostedGitHubApi',
    'Get-HostedToolkitCodeOwners',
    'Get-HostedGitHubForkTarget'
)
