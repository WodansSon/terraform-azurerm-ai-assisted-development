[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [string]$PullRequestNumber,

    [Alias('h')]
    [switch]$Help,

    [Parameter(ValueFromRemainingArguments = $true)]
    [object[]]$RemainingArguments
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$launchedWithFile = $false
$processArguments = [Environment]::GetCommandLineArgs()
for ($index = 0; $index -lt ($processArguments.Count - 1); $index++) {
    if ($processArguments[$index] -ine '-File') {
        continue
    }

    try {
        $launchedWithFile = [IO.Path]::GetFullPath($processArguments[$index + 1]) -eq [IO.Path]::GetFullPath($PSCommandPath)
    }
    catch {
        $launchedWithFile = $false
    }

    break
}

$repository = 'hashicorp/terraform-provider-azurerm'
$projectOwner = 'hashicorp'
$projectNumber = 163
$fieldName = 'ready'
$settingsPath = if ([string]::IsNullOrWhiteSpace($env:APPDATA)) { $null } else { Join-Path $env:APPDATA 'Code\User\settings.json' }
$tokenSettingName = 'terrasight.githubToken'

function Show-Help {
    $helpText = @'
  NAME: Get-PRReady.ps1

  SYNOPSIS:

    Reports which contributor set the current readiness value for an AzureRM provider pull request.

  USAGE:

    - .\tools\Get-PRReady.ps1 12345
        Query the current readiness attribution for a pull request.

    - .\tools\Get-PRReady.ps1 -Help
        Show this menu without calling GitHub GraphQL API.

  AUTHENTICATION:

    Requires a GitHub token with the `read:project` scope and access to the HashiCorp AzureRM project. The first available token is used.

    - `GH_TOKEN`
        Environment variable used first.

    - `GITHUB_TOKEN`
        Environment variable used when `GH_TOKEN` is not set.

    - `terrasight.githubToken`
        VS Code user setting used when neither environment variable is set.

  LIMITATIONS:

    Retrieving prior values and the GitHub usernames that changed them requires organization audit-log access and is not supported by this tool.
    Clearing the `ready` project field sets all readiness attribution fields to `null`.
'@

    if (-not [Console]::IsOutputRedirected -and $PSVersionTable.PSVersion.Major -ge 7) {
        $yellow = $PSStyle.Foreground.FromRgb(255, 255, 0)
        $cyan = $PSStyle.Foreground.BrightCyan
        $white = $PSStyle.Foreground.White
        $helpText = $helpText -replace '(?m)^(  [A-Z]+:)', "$yellow`$1$($PSStyle.Reset)"
        $helpText = $helpText -replace '(?m)(NAME:\x1b\[0m )(Get-PRReady\.ps1)$', "`$1$cyan`$2$($PSStyle.Reset)"
        $helpText = $helpText -replace '(?m)^(    )(-)( .+)$', "`$1$white`$2$($PSStyle.Reset)$cyan`$3$($PSStyle.Reset)"
    }

    Write-Output $helpText
    Write-Output ''
}

function Write-CliError {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Context,

        [Parameter(Mandatory = $true)]
        [string]$Message
    )

    $plainLine = "  $Context | ERROR: $Message"

    [Console]::Error.WriteLine()
    if (-not [Console]::IsErrorRedirected -and $PSVersionTable.PSVersion.Major -ge 7) {
        [Console]::Error.WriteLine("  $($PSStyle.Foreground.BrightCyan)$Context |$($PSStyle.Reset) $($PSStyle.Foreground.BrightRed)ERROR: $Message$($PSStyle.Reset)")
    }
    else {
        [Console]::Error.WriteLine($plainLine)
    }
    [Console]::Error.WriteLine()
}

function Show-ArgumentError {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Message
    )

    Write-CliError -Context 'ARGUMENTS' -Message $Message
    Show-Help

    if ($launchedWithFile) {
        $host.SetShouldExit(1)
    }
}

$remaining = @($RemainingArguments | Where-Object { $null -ne $_ })
if ($Help -and ([string]::IsNullOrWhiteSpace($PullRequestNumber)) -and $remaining.Count -eq 0) {
    Show-Help
    return
}

if ([string]::IsNullOrWhiteSpace($PullRequestNumber) -and $remaining.Count -eq 0) {
    Show-ArgumentError -Message 'A PR number is required.'
    return
}

$argumentError = $null
$resolvedPullRequestNumber = 0

if ($Help) {
    $argumentError = '`-Help` cannot be combined with other arguments.'
}
elseif ($remaining.Count -gt 0) {
    $argumentError = "Invalid argument(s): $($remaining -join ' ')"
}
elseif (-not [int]::TryParse($PullRequestNumber, [ref]$resolvedPullRequestNumber) -or $resolvedPullRequestNumber -lt 1) {
    $argumentError = "PR number must be a positive integer: $PullRequestNumber"
}

if ($null -ne $argumentError) {
    Show-ArgumentError -Message $argumentError
    return
}

function Get-GitHubToken {
    if (-not [string]::IsNullOrWhiteSpace($env:GH_TOKEN)) {
        return $env:GH_TOKEN
    }

    if (-not [string]::IsNullOrWhiteSpace($env:GITHUB_TOKEN)) {
        return $env:GITHUB_TOKEN
    }

    if ([string]::IsNullOrWhiteSpace($settingsPath) -or -not (Test-Path -LiteralPath $settingsPath -PathType Leaf)) {
        throw 'GitHub token was not found in GH_TOKEN, GITHUB_TOKEN, or VS Code user settings.'
    }

    $settings = Get-Content -LiteralPath $settingsPath -Raw | ConvertFrom-Json
    $tokenProperty = $settings.PSObject.Properties[$tokenSettingName]
    if ($null -eq $tokenProperty -or [string]::IsNullOrWhiteSpace([string]$tokenProperty.Value)) {
        throw "GitHub token setting was not found or was empty: $tokenSettingName"
    }

    return [string]$tokenProperty.Value
}

function Get-ProjectReadyAttribution {
    $repositoryParts = $repository.Split('/')

$query = @'
query(
  $repositoryOwner: String!
  $repositoryName: String!
  $pullRequestNumber: Int!
  $fieldName: String!
  $endCursor: String
) {
  repository(owner: $repositoryOwner, name: $repositoryName) {
    pullRequest(number: $pullRequestNumber) {
      number
      title
      url
      projectItems(first: 100, after: $endCursor) {
        pageInfo {
          hasNextPage
          endCursor
        }
        nodes {
          project {
            number
            owner {
              ... on Organization {
                login
              }
              ... on User {
                login
              }
            }
          }
          fieldValueByName(name: $fieldName) {
            ... on ProjectV2ItemFieldSingleSelectValue {
              name
              createdAt
              updatedAt
              creator {
                login
              }
            }
          }
        }
      }
    }
  }
}
'@

    $token = Get-GitHubToken
    $headers = @{
        Accept = 'application/vnd.github+json'
        Authorization = "Bearer $token"
        'X-GitHub-Api-Version' = '2022-11-28'
    }
    $endCursor = $null
    $pullRequest = $null
    $projectItem = $null

    do {
        $variables = @{
            repositoryOwner = $repositoryParts[0]
            repositoryName = $repositoryParts[1]
            pullRequestNumber = $resolvedPullRequestNumber
            fieldName = $fieldName
            endCursor = $endCursor
        }
        $body = @{
            query = $query
            variables = $variables
        } | ConvertTo-Json -Depth 5

        $response = Invoke-RestMethod -Uri 'https://api.github.com/graphql' -Method Post -Headers $headers -Body $body -ContentType 'application/json'
        $errorsProperty = $response.PSObject.Properties['errors']
        if ($null -ne $errorsProperty -and $errorsProperty.Value) {
            $errorMessages = @($errorsProperty.Value.message)
            if ($errorMessages -match 'Could not resolve to a PullRequest') {
                throw "Pull request was not found: $repository#$resolvedPullRequestNumber"
            }

            throw "GitHub GraphQL query failed: $($errorMessages -join '; ')"
        }

        $pullRequest = $response.data.repository.pullRequest
        if ($null -eq $pullRequest) {
            throw "Pull request was not found: $repository#$resolvedPullRequestNumber"
        }

        $projectItem = $pullRequest.projectItems.nodes | Where-Object {
            $_.project.number -eq $projectNumber -and $_.project.owner.login -eq $projectOwner
        } | Select-Object -First 1

        $pageInfo = $pullRequest.projectItems.pageInfo
        $endCursor = $pageInfo.endCursor
    } while ($null -eq $projectItem -and $pageInfo.hasNextPage)

    if ($null -eq $projectItem) {
        throw "Pull request $repository#$resolvedPullRequestNumber was not found in $projectOwner project $projectNumber"
    }

    $fieldValue = $projectItem.fieldValueByName
    $result = [ordered]@{
        Number = $pullRequest.number
        Title = $pullRequest.title
        Url = $pullRequest.url
        ReadyValue = if ($null -ne $fieldValue) { $fieldValue.name } else { $null }
        ChangedBy = if ($null -ne $fieldValue -and $null -ne $fieldValue.creator) { $fieldValue.creator.login } else { $null }
        CreatedAt = if ($null -ne $fieldValue) { $fieldValue.createdAt } else { $null }
        UpdatedAt = if ($null -ne $fieldValue) { $fieldValue.updatedAt } else { $null }
    }

    $result | ConvertTo-Json
}

try {
    Get-ProjectReadyAttribution
}
catch {
    $errorMessage = $_.Exception.Message
    $errorContext = if ($errorMessage -match '^Pull request') {
        "PR $resolvedPullRequestNumber"
    }
    elseif ($errorMessage -match '(?i)token|authentication|unauthorized|forbidden|\b401\b|\b403\b|read:project') {
        'AUTHENTICATION'
    }
    elseif ($errorMessage -match '^GitHub GraphQL query failed') {
        'GITHUB'
    }
    else {
        'SCRIPT'
    }

    Write-CliError -Context $errorContext -Message $errorMessage
    if ($launchedWithFile) {
        $host.SetShouldExit(1)
    }
}
