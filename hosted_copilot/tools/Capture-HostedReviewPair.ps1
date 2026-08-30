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

function Invoke-GitHubRunLog {
    param(
        [Parameter(Mandatory = $true)]
        [int64]$RunId
    )

    $originalOutputEncoding = [Console]::OutputEncoding
    try {
        [Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)
        $output = & $script:ghCommand.Source run view $RunId --repo $Repository --log
        if ($LASTEXITCODE -ne 0) {
            throw "GitHub Actions log request failed for run $RunId"
        }
    }
    finally {
        [Console]::OutputEncoding = $originalOutputEncoding
    }

    return $output -join "`n"
}

function Get-RegexValues {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Text,

        [Parameter(Mandatory = $true)]
        [string]$Pattern
    )

    return @([regex]::Matches($Text, $Pattern) | ForEach-Object { $_.Groups['value'].Value } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Sort-Object -Unique)
}

function Get-FirstRegexValue {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Text,

        [Parameter(Mandatory = $true)]
        [string]$Pattern
    )

    $values = @(Get-RegexValues -Text $Text -Pattern $Pattern)
    if ($values.Count -eq 0) {
        return $null
    }

    return $values[0]
}

function ConvertTo-ModelEvidence {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Descriptor
    )

    $descriptorMatch = [regex]::Match($Descriptor, '^(?<model>.+?)(?:\[ReasoningEffort=(?<reasoning>[^\]]+)\])?$')
    if (-not $descriptorMatch.Success) {
        throw "Model descriptor is invalid: $Descriptor"
    }

    $modelName = $descriptorMatch.Groups['model'].Value -replace '^sweagent-capi:', '' -replace '^capi-prod-', ''
    $reasoningLevel = if ($descriptorMatch.Groups['reasoning'].Success) { $descriptorMatch.Groups['reasoning'].Value } else { 'unknown' }
    return [ordered]@{
        rawModel = $Descriptor
        modelName = $modelName
        reasoningLevel = $reasoningLevel
    }
}

function Get-ReviewRuntimeEvidence {
    param(
        [Parameter(Mandatory = $true)]
        [int]$Number,

        [Parameter(Mandatory = $true)]
        [string]$HeadCommit,

        [Parameter(Mandatory = $true)]
        [DateTimeOffset]$RequestedAt,

        [Parameter(Mandatory = $true)]
        [DateTimeOffset]$ReviewedAt
    )

    $runsResponse = Invoke-GitHubApi -Endpoint "repos/$Repository/actions/runs?head_sha=$HeadCommit&per_page=100"
    $runs = @(Get-OptionalPropertyValue -InputObject $runsResponse -Name 'workflow_runs')
    $candidates = New-Object 'System.Collections.Generic.List[object]'
    foreach ($run in $runs) {
        $linkedPullRequests = @(Get-OptionalPropertyValue -InputObject $run -Name 'pull_requests')
        $linkedNumbers = @($linkedPullRequests | ForEach-Object { [int]$_.number })
        $createdAt = [DateTimeOffset]$run.created_at
        if ($run.name -eq 'Running Copilot Code Review' -and
            $run.status -eq 'completed' -and
            $run.conclusion -eq 'success' -and
            $run.head_sha -eq $HeadCommit -and
            $Number -in $linkedNumbers -and
            $createdAt -ge $RequestedAt.AddMinutes(-1) -and
            $createdAt -le $ReviewedAt.AddMinutes(1)) {
            $candidates.Add($run)
        }
    }
    if ($candidates.Count -ne 1) {
        return [ordered]@{
            captureStatus = 'unavailable'
            diagnostics = @("Expected exactly one completed Actions run for pull request #$Number and head $HeadCommit; found $($candidates.Count)")
            actionRunId = $null
            actionRunAttempt = $null
            actionRunUrl = $null
            actionLogSha256 = $null
            parserVersion = 'actions-log-v1'
            modelName = 'unknown'
            reasoningLevel = 'unknown'
            modelEvidenceSource = 'unavailable'
            configuredPrimaryModel = $null
            modelSessions = @()
            runtimeVersion = 'unknown'
            maxPromptTokens = $null
            memoryCount = $null
            skillCatalogEntries = $null
            invokedSkills = @()
            configuredAuxiliaryModels = [ordered]@{
                deduplication = $null
                grouping = $null
                curation = $null
                severity = $null
            }
            deduplication = [ordered]@{
                previousFetched = $null
                newCandidates = $null
                duplicatesRemoved = $null
            }
        }
    }

    $run = $candidates[0]
    try {
        $log = Invoke-GitHubRunLog -RunId ([int64]$run.id)
    }
    catch {
        return [ordered]@{
            captureStatus = 'unavailable'
            diagnostics = @($_.Exception.Message)
            actionRunId = [int64]$run.id
            actionRunAttempt = [int]$run.run_attempt
            actionRunUrl = [string]$run.html_url
            actionLogSha256 = $null
            parserVersion = 'actions-log-v1'
            modelName = 'unknown'
            reasoningLevel = 'unknown'
            modelEvidenceSource = 'unavailable'
            configuredPrimaryModel = $null
            modelSessions = @()
            runtimeVersion = 'unknown'
            maxPromptTokens = $null
            memoryCount = $null
            skillCatalogEntries = $null
            invokedSkills = @()
            configuredAuxiliaryModels = [ordered]@{
                deduplication = $null
                grouping = $null
                curation = $null
                severity = $null
            }
            deduplication = [ordered]@{
                previousFetched = $null
                newCandidates = $null
                duplicatesRemoved = $null
            }
        }
    }
    $diagnostics = New-Object 'System.Collections.Generic.List[string]'
    $sessionMatches = @([regex]::Matches($log, 'Creating\s+(?<sessionType>[^\r\n]+?)\s+session with model:\s*(?<model>[^\r\n]+?)\s+and clientName:\s*(?<clientName>[^\s\r\n]+)'))
    $modelSessions = @($sessionMatches | ForEach-Object {
            $clientName = $_.Groups['clientName'].Value
            $role = if ($clientName -eq 'github/copilot-code-review') {
                'primary_review'
            }
            elseif ($clientName.StartsWith('github/copilot-code-review/')) {
                $clientName.Substring('github/copilot-code-review/'.Length) -replace '[^A-Za-z0-9]+', '_'
            }
            else {
                'other'
            }
            $model = ConvertTo-ModelEvidence -Descriptor $_.Groups['model'].Value
            [ordered]@{
                sessionType = $_.Groups['sessionType'].Value
                role = $role
                clientName = $clientName
                rawModel = $model.rawModel
                modelName = $model.modelName
                reasoningLevel = $model.reasoningLevel
                evidenceToken = $_.Value
            }
        })
    $primarySessions = @($modelSessions | Where-Object role -eq 'primary_review')
    if ($primarySessions.Count -ne 1) {
        $diagnostics.Add("Expected exactly one instantiated github/copilot-code-review primary session; found $($primarySessions.Count)")
    }

    $configuredPrimaryModels = @(Get-RegexValues -Text $log -Pattern 'COPILOT_AGENT_MODEL:\s*(?<value>[^\s\r\n]+)')
    if ($configuredPrimaryModels.Count -gt 1) {
        $diagnostics.Add("Found conflicting COPILOT_AGENT_MODEL values: $($configuredPrimaryModels -join ', ')")
    }
    $configuredPrimaryModel = if ($configuredPrimaryModels.Count -eq 1) {
        $model = ConvertTo-ModelEvidence -Descriptor $configuredPrimaryModels[0]
        [ordered]@{
            rawModel = $model.rawModel
            modelName = $model.modelName
            reasoningLevel = $model.reasoningLevel
            evidenceToken = "COPILOT_AGENT_MODEL: $($configuredPrimaryModels[0])"
        }
    }
    else {
        $null
    }

    $primaryModel = if ($primarySessions.Count -eq 1) {
        $primarySessions[0]
    }
    elseif ($null -ne $configuredPrimaryModel) {
        $configuredPrimaryModel
    }
    else {
        [ordered]@{ modelName = 'unknown'; reasoningLevel = 'unknown' }
    }

    $runtimeVersions = @(Get-RegexValues -Text $log -Pattern 'autofind\.js version:\s*(?<value>[0-9.]+)')
    if ($runtimeVersions.Count -gt 1) {
        $diagnostics.Add("Found conflicting autofind.js versions: $($runtimeVersions -join ', ')")
    }
    if ($runtimeVersions.Count -eq 0) {
        $diagnostics.Add('Missing autofind.js version marker')
    }
    $runtimeVersion = if ($runtimeVersions.Count -eq 1) { $runtimeVersions[0] } else { 'unknown' }
    $maxPromptTokens = Get-FirstRegexValue -Text $log -Pattern 'MaxPromptTokens=(?<value>[0-9]+)'
    if ($null -eq $maxPromptTokens) {
        $diagnostics.Add('Missing MaxPromptTokens marker')
    }
    return [ordered]@{
        captureStatus = if ($diagnostics.Count -eq 0) { 'complete' } else { 'partial' }
        diagnostics = @($diagnostics)
        actionRunId = [int64]$run.id
        actionRunAttempt = [int]$run.run_attempt
        actionRunUrl = [string]$run.html_url
        actionLogSha256 = Get-StringSha256 -Value $log
        parserVersion = 'actions-log-v1'
        modelName = $primaryModel.modelName
        reasoningLevel = $primaryModel.reasoningLevel
        modelEvidenceSource = 'actions_log'
        configuredPrimaryModel = $configuredPrimaryModel
        modelSessions = $modelSessions
        runtimeVersion = $runtimeVersion
        maxPromptTokens = $maxPromptTokens
        memoryCount = Get-FirstRegexValue -Text $log -Pattern 'Retrieved memory prompts \((?<value>[0-9]+) memor(?:y|ies)\)'
        skillCatalogEntries = Get-FirstRegexValue -Text $log -Pattern '\[skills\].*?catalogEntries=(?<value>[0-9]+)'
        invokedSkills = @(Get-RegexValues -Text $log -Pattern '\[skills\].*?invoked:\s*name="(?<value>[^"]+)"')
        configuredAuxiliaryModels = [ordered]@{
            deduplication = Get-FirstRegexValue -Text $log -Pattern 'DedupModelName=(?<value>[^;]+)'
            grouping = Get-FirstRegexValue -Text $log -Pattern 'GroupingWithinReviewModelName=(?<value>[^;]+)'
            curation = Get-FirstRegexValue -Text $log -Pattern 'LateFindsCurationModelName=(?<value>[^;]+)'
            severity = Get-FirstRegexValue -Text $log -Pattern 'SeverityClassifierModelName=(?<value>[^;]+)'
        }
        deduplication = [ordered]@{
            previousFetched = Get-FirstRegexValue -Text $log -Pattern '\[dedup_previous\] complete.*?previous_fetched=(?<value>[0-9]+)'
            newCandidates = Get-FirstRegexValue -Text $log -Pattern '\[dedup_previous\] complete.*?new_candidates=(?<value>[0-9]+)'
            duplicatesRemoved = Get-FirstRegexValue -Text $log -Pattern '\[dedup_previous\] complete.*?duplicates_removed=(?<value>[0-9]+)'
        }
    }
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
    $requestedAt = [DateTimeOffset]$requestEvents[-1].created_at
    $reviewedAt = [DateTimeOffset]$review.submitted_at
    $runtime = Get-ReviewRuntimeEvidence -Number $Number -HeadCommit ([string]$review.commit_id) -RequestedAt $requestedAt -ReviewedAt $reviewedAt

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
            requestedAt = $requestedAt.ToUniversalTime().ToString('o')
            reviewedAt = $reviewedAt.ToUniversalTime().ToString('o')
            commitId = [string]$review.commit_id
            reviewer = [string]$review.user.login
            reviewEffort = $ReviewEffort
        }
        runtime = $runtime
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
    controlModel = $control.runtime.modelName
    controlReasoningLevel = $control.runtime.reasoningLevel
    hostedModel = $hosted.runtime.modelName
    hostedReasoningLevel = $hosted.runtime.reasoningLevel
} | ConvertTo-Json -Depth 5
