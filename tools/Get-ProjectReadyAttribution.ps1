[CmdletBinding()]
param(
    [Parameter(Mandatory = $true, Position = 0)]
    [ValidateRange(1, [int]::MaxValue)]
    [int]$PullRequestNumber,

    [string]$Repository = 'hashicorp/terraform-provider-azurerm',

    [string]$ProjectOwner = 'hashicorp',

    [ValidateRange(1, [int]::MaxValue)]
    [int]$ProjectNumber = 163,

    [string]$FieldName = 'ready',

    [string]$SettingsPath = (Join-Path $env:APPDATA 'Code\User\settings.json'),

    [string]$TokenSettingName = 'terrasight.githubToken'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-GitHubToken {
    if (-not [string]::IsNullOrWhiteSpace($env:GH_TOKEN)) {
        return $env:GH_TOKEN
    }

    if (-not [string]::IsNullOrWhiteSpace($env:GITHUB_TOKEN)) {
        return $env:GITHUB_TOKEN
    }

    if (-not (Test-Path -LiteralPath $SettingsPath -PathType Leaf)) {
        throw "GitHub token was not found in GH_TOKEN, GITHUB_TOKEN, or settings file: $SettingsPath"
    }

    $settings = Get-Content -LiteralPath $SettingsPath -Raw | ConvertFrom-Json
    $tokenProperty = $settings.PSObject.Properties[$TokenSettingName]
    if ($null -eq $tokenProperty -or [string]::IsNullOrWhiteSpace([string]$tokenProperty.Value)) {
        throw "GitHub token setting was not found or was empty: $TokenSettingName"
    }

    return [string]$tokenProperty.Value
}

$repositoryParts = $Repository.Split('/', [System.StringSplitOptions]::RemoveEmptyEntries)
if ($repositoryParts.Count -ne 2) {
    throw "Repository must use the owner/name format: $Repository"
}

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
        fieldName = $FieldName
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
        throw "Pull request was not found: $Repository#$PullRequestNumber"
      }

      throw "GitHub GraphQL query failed: $($errorMessages -join '; ')"
    }

    $pullRequest = $response.data.repository.pullRequest
    if ($null -eq $pullRequest) {
        throw "Pull request was not found: $Repository#$PullRequestNumber"
    }

    $projectItem = $pullRequest.projectItems.nodes | Where-Object {
        $_.project.number -eq $ProjectNumber -and $_.project.owner.login -eq $ProjectOwner
    } | Select-Object -First 1

    $pageInfo = $pullRequest.projectItems.pageInfo
    $endCursor = $pageInfo.endCursor
} while ($null -eq $projectItem -and $pageInfo.hasNextPage)

if ($null -eq $projectItem) {
    throw "Pull request $Repository#$PullRequestNumber was not found in $ProjectOwner project $ProjectNumber"
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
