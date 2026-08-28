[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [ValidateRange(1, [int]::MaxValue)]
    [int]$PullRequestNumber,

    [Alias('h')]
    [switch]$Help
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$repository = 'hashicorp/terraform-provider-azurerm'
$projectOwner = 'hashicorp'
$projectNumber = 163
$fieldName = 'ready'
$settingsPath = Join-Path $env:APPDATA 'Code\User\settings.json'
$tokenSettingName = 'terrasight.githubToken'

function Show-Help {
    @'
Get-PRReady.ps1

Reports who set the current readiness value for an AzureRM provider pull request.

USAGE:

  - .\tools\Get-PRReady.ps1 12345
      Query the current readiness attribution for a pull request.

  - .\tools\Get-PRReady.ps1 -Help
      Show this menu without calling GitHub.

AUTHENTICATION:

Requires a GitHub token with the `read:project` scope and access to the HashiCorp AzureRM project. The first available token is used.

  - `GH_TOKEN`
      Environment variable used first.

  - `GITHUB_TOKEN`
      Environment variable used when `GH_TOKEN` is not set.

  - `terrasight.githubToken`
      VS Code user setting used when neither environment variable is set.

LIMITATION:

  - Only the current value is available; prior values and actors require organization audit-log access and are not available to this tool.
  - Clearing the `ready` project field sets all readiness attribution fields to `null`.
'@ | Write-Output
    Write-Output ''
}

if ($Help -or $PullRequestNumber -eq 0) {
    Show-Help
    return
}

function Get-GitHubToken {
    if (-not [string]::IsNullOrWhiteSpace($env:GH_TOKEN)) {
        return $env:GH_TOKEN
    }

    if (-not [string]::IsNullOrWhiteSpace($env:GITHUB_TOKEN)) {
        return $env:GITHUB_TOKEN
    }

    if (-not (Test-Path -LiteralPath $settingsPath -PathType Leaf)) {
        throw "GitHub token was not found in GH_TOKEN, GITHUB_TOKEN, or settings file: $settingsPath"
    }

    $settings = Get-Content -LiteralPath $settingsPath -Raw | ConvertFrom-Json
    $tokenProperty = $settings.PSObject.Properties[$tokenSettingName]
    if ($null -eq $tokenProperty -or [string]::IsNullOrWhiteSpace([string]$tokenProperty.Value)) {
        throw "GitHub token setting was not found or was empty: $tokenSettingName"
    }

    return [string]$tokenProperty.Value
}

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
        pullRequestNumber = $PullRequestNumber
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
          throw "Pull request was not found: $repository#$PullRequestNumber"
        }

        throw "GitHub GraphQL query failed: $($errorMessages -join '; ')"
    }

    $pullRequest = $response.data.repository.pullRequest
    if ($null -eq $pullRequest) {
      throw "Pull request was not found: $repository#$PullRequestNumber"
    }

    $projectItem = $pullRequest.projectItems.nodes | Where-Object {
      $_.project.number -eq $projectNumber -and $_.project.owner.login -eq $projectOwner
    } | Select-Object -First 1

    $pageInfo = $pullRequest.projectItems.pageInfo
    $endCursor = $pageInfo.endCursor
} while ($null -eq $projectItem -and $pageInfo.hasNextPage)

if ($null -eq $projectItem) {
  throw "Pull request $repository#$PullRequestNumber was not found in $projectOwner project $projectNumber"
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
