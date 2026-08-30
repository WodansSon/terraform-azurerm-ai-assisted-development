[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$Repository,

    [Parameter(Mandatory = $true)]
    [int]$ControlPullRequest,

    [Parameter(Mandatory = $true)]
    [int]$HostedPullRequest,

    [Parameter(Mandatory = $true)]
    [ValidatePattern('^[A-Za-z0-9][A-Za-z0-9._-]*$')]
    [string]$FixtureId,

    [Parameter(Mandatory = $true)]
    [ValidatePattern('^[A-Za-z0-9][A-Za-z0-9._-]*$')]
    [string]$RunId,

    [Parameter(Mandatory = $true)]
    [ValidateSet('Lite', 'Medium')]
    [string]$ReviewEffort,

    [Parameter(Mandatory = $true)]
    [ValidatePattern('^[0-9a-f]{40}$')]
    [string]$SourceCommit,

    [Parameter(Mandatory = $true)]
    [ValidatePattern('^[0-9a-f]{64}$')]
    [string]$ManifestHash,

    [string]$RegressionDirectory = (Join-Path $PSScriptRoot '../regression')
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Invoke-GitHubApi {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Endpoint
    )

    $originalOutputEncoding = [Console]::OutputEncoding
    try {
        [Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)
        $output = & $script:ghCommand.Source api $Endpoint -H 'Accept: application/vnd.github+json'
        if ($LASTEXITCODE -ne 0) {
            throw "GitHub API request failed: $Endpoint"
        }
    }
    finally {
        [Console]::OutputEncoding = $originalOutputEncoding
    }

    return $output | ConvertFrom-Json
}

function Get-StringSha256 {
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string]$Value
    )

    $bytes = [System.Text.Encoding]::UTF8.GetBytes($Value)
    $hash = [System.Security.Cryptography.SHA256]::HashData($bytes)
    return [Convert]::ToHexString($hash).ToLowerInvariant()
}

function Get-OptionalPropertyValue {
    param(
        [Parameter(Mandatory = $true)]
        $InputObject,

        [Parameter(Mandatory = $true)]
        [string]$Name
    )

    $property = $InputObject.PSObject.Properties[$Name]
    if ($null -eq $property) {
        return $null
    }

    return $property.Value
}

function Get-PullRequestEvidence {
    param(
        [Parameter(Mandatory = $true)]
        [int]$Number,

        [Parameter(Mandatory = $true)]
        [string]$ExpectedProfile
    )

    $pullRequest = Invoke-GitHubApi -Endpoint "repos/$Repository/pulls/$Number"
    $files = @(Invoke-GitHubApi -Endpoint "repos/$Repository/pulls/$Number/files?per_page=100")
    if ($pullRequest.changed_files -gt 100) {
        throw "Pull request #$Number has more than 100 changed files; paged capture is required"
    }
    if ($files.Count -ne $pullRequest.changed_files) {
        throw "Pull request #$Number file capture is incomplete"
    }

    $reviews = @(Invoke-GitHubApi -Endpoint "repos/$Repository/pulls/$Number/reviews?per_page=100")
    $matchingReviews = @($reviews | Where-Object {
            $_.user.login -match '^copilot-pull-request-reviewer' -and
            $_.body -match "Review effort level:\*\*\s+$([regex]::Escape($ReviewEffort))"
        } | Sort-Object submitted_at)
    if ($matchingReviews.Count -eq 0) {
        throw "Pull request #$Number has no completed Copilot $ReviewEffort review"
    }
    $review = $matchingReviews[-1]

    $comments = @(Invoke-GitHubApi -Endpoint "repos/$Repository/pulls/$Number/comments?per_page=100" | Where-Object pull_request_review_id -eq $review.id)
    $timeline = @(Invoke-GitHubApi -Endpoint "repos/$Repository/issues/$Number/timeline?per_page=100")
    $requestEvents = @($timeline | Where-Object {
            $requestedReviewer = Get-OptionalPropertyValue -InputObject $_ -Name 'requested_reviewer'
            $_.event -eq 'review_requested' -and
            $null -ne $requestedReviewer -and
            $requestedReviewer.login -eq 'Copilot' -and
            [DateTimeOffset]$_.created_at -le [DateTimeOffset]$review.submitted_at
        } | Sort-Object created_at)
    if ($requestEvents.Count -eq 0) {
        throw "Pull request #$Number has no Copilot review request event before review $($review.id)"
    }

    $orderedFiles = @($files | Sort-Object filename | ForEach-Object {
            $patch = Get-OptionalPropertyValue -InputObject $_ -Name 'patch'
            if ($null -eq $patch) {
                throw "Pull request #$Number file $($_.filename) has no patch content"
            }
            $previousFilename = Get-OptionalPropertyValue -InputObject $_ -Name 'previous_filename'
            [ordered]@{
                filename = [string]$_.filename
                status = [string]$_.status
                previousFilename = if ($null -eq $previousFilename) { $null } else { [string]$previousFilename }
                patch = [string]$patch
            }
        })
    $patchMaterial = $orderedFiles | ConvertTo-Json -Depth 5 -Compress

    return [ordered]@{
        instructionProfile = $ExpectedProfile
        pullRequest = [ordered]@{
            number = $Number
            url = [string]$pullRequest.html_url
            baseBranch = [string]$pullRequest.base.ref
            baseCommit = [string]$pullRequest.base.sha
            headBranch = [string]$pullRequest.head.ref
            headCommit = [string]$pullRequest.head.sha
        }
        review = [ordered]@{
            id = [int64]$review.id
            state = [string]$review.state
            body = [string]$review.body
            requestedAt = ([DateTimeOffset]$requestEvents[-1].created_at).ToUniversalTime().ToString('o')
            reviewedAt = ([DateTimeOffset]$review.submitted_at).ToUniversalTime().ToString('o')
            commitId = [string]$review.commit_id
            reviewer = [string]$review.user.login
            reviewEffort = $ReviewEffort
        }
        files = $orderedFiles
        changedFiles = @($orderedFiles | ForEach-Object { $_.filename })
        diffHash = Get-StringSha256 -Value $patchMaterial
        comments = @($comments | ForEach-Object {
                $line = Get-OptionalPropertyValue -InputObject $_ -Name 'line'
                [ordered]@{
                    id = [int64]$_.id
                    url = [string]$_.html_url
                    path = [string]$_.path
                    line = if ($null -eq $line) { $null } else { [int]$line }
                    body = [string]$_.body
                }
            })
    }
}

$ghCommand = Get-Command 'gh' -ErrorAction SilentlyContinue
if ($null -eq $ghCommand) {
    throw 'GitHub CLI was not found on PATH'
}
$control = Get-PullRequestEvidence -Number $ControlPullRequest -ExpectedProfile 'control'
$hosted = Get-PullRequestEvidence -Number $HostedPullRequest -ExpectedProfile 'hosted'
if (($control.changedFiles -join "`n") -ne ($hosted.changedFiles -join "`n")) {
    throw 'Control and Hosted pull requests do not have identical changed-file sets'
}
if ($control.diffHash -ne $hosted.diffHash) {
    throw 'Control and Hosted pull requests do not have identical file patches'
}

$capturedAt = [DateTimeOffset]::UtcNow.ToString('o')
$rawRelativePath = "raw/$FixtureId/$RunId.json"
$blindRelativePath = "raw/$FixtureId/$RunId.blind.json"
$rawPath = Join-Path $RegressionDirectory $rawRelativePath
$blindPath = Join-Path $RegressionDirectory $blindRelativePath
$rawDirectory = Split-Path -Parent $rawPath
New-Item -ItemType Directory -Path $rawDirectory -Force | Out-Null

$slotOrder = if ((Get-Random -Minimum 0 -Maximum 2) -eq 0) { @($control, $hosted) } else { @($hosted, $control) }
$rawRecord = [ordered]@{
    schemaVersion = 1
    runId = $RunId
    repository = $Repository
    fixtureId = $FixtureId
    capturedAt = $capturedAt
    sourceCommit = $SourceCommit
    manifestHash = $ManifestHash.ToLowerInvariant()
    diffHashAlgorithm = 'sha256-github-file-patches-v1'
    diffHash = $control.diffHash
    changedFiles = $control.changedFiles
    profiles = @($slotOrder | ForEach-Object -Begin { $slotIndex = 0 } -Process {
            $slot = @('A', 'B')[$slotIndex]
            $slotIndex++
            [ordered]@{ slot = $slot; evidence = $_ }
        })
}
$blindRecord = [ordered]@{
    schemaVersion = 1
    runId = $RunId
    fixtureId = $FixtureId
    reviewEffort = $ReviewEffort
    changedFiles = $control.changedFiles
    profiles = @($rawRecord.profiles | ForEach-Object {
            [ordered]@{
                slot = $_.slot
                comments = $_.evidence.comments
            }
        })
}

$rawRecord | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $rawPath -Encoding utf8NoBOM
$blindRecord | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $blindPath -Encoding utf8NoBOM

[pscustomobject]@{
    success = $true
    rawPath = [System.IO.Path]::GetFullPath($rawPath)
    blindPath = [System.IO.Path]::GetFullPath($blindPath)
    diffHash = $control.diffHash
    changedFiles = $control.changedFiles
    controlReviewId = $control.review.id
    hostedReviewId = $hosted.review.id
} | ConvertTo-Json -Depth 5
