[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$RepoDirectory,

    [ValidatePattern('^[A-Za-z0-9][A-Za-z0-9._-]*$')]
    [string]$CaseId,

    [ValidateSet('Lite', 'Balanced')]
    [string]$ReviewEffort = 'Lite',

    [switch]$NewRun,

    [switch]$Cleanup
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$hostedRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$regressionDirectory = Join-Path $hostedRoot 'regression'
$rawDirectory = Join-Path $regressionDirectory 'raw'
$resultsDirectory = Join-Path $regressionDirectory 'results'
$casesDirectory = Join-Path $regressionDirectory 'cases'
$workflowModulePath = Join-Path $PSScriptRoot 'modules/review/HostedReview.Workflow.psm1'
$initializePath = Join-Path $PSScriptRoot 'internal/review/Initialize-ReviewBases.ps1'
$publishPath = Join-Path $PSScriptRoot 'internal/review/Publish-TestCase.ps1'
$capturePath = Join-Path $PSScriptRoot 'internal/review/Capture-ReviewPair.ps1'
$closePath = Join-Path $PSScriptRoot 'internal/review/Close-ReviewPair.ps1'
$validatorPath = Join-Path $PSScriptRoot 'tests/Test-ReviewResults.ps1'
$schemaPath = Join-Path $regressionDirectory 'schema/paired-review-result.schema.json'

Import-Module $workflowModulePath -Force
Import-Module (Join-Path $PSScriptRoot 'modules/shared/HostedToolkit.Helpers.psm1') -Force

function Invoke-Git {
    $arguments = @($args)
    $output = @(& $script:gitCommand.Source -C $script:resolvedRepoDirectory @arguments 2>&1)
    if ($LASTEXITCODE -ne 0) {
        throw "git $($arguments -join ' ') failed: $((($output | Out-String).Trim()))"
    }
    return $output
}

function Invoke-JsonStage {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,

        [Parameter(Mandatory = $true)]
        [object[]]$Arguments
    )

    $output = @(& $Path @Arguments 2>&1)
    if ($LASTEXITCODE -ne 0) {
        throw (($output | Out-String).Trim())
    }
    return ($output -join [Environment]::NewLine) | ConvertFrom-Json
}

function Get-CaseRecord {
    param([Parameter(Mandatory = $true)][string]$Id)

    $matches = @(Get-ChildItem -LiteralPath $casesDirectory -Filter 'case.json' -File -Recurse | Where-Object {
            (Get-Content -LiteralPath $_.FullName -Raw | ConvertFrom-Json).id -eq $Id
        })
    if ($matches.Count -ne 1) {
        throw "CaseId must resolve to exactly one controlled case: $Id"
    }
    return Get-Content -LiteralPath $matches[0].FullName -Raw | ConvertFrom-Json
}

function Get-RunRecords {
    $records = New-Object 'System.Collections.Generic.List[object]'
    if (-not (Test-Path -LiteralPath $rawDirectory -PathType Container)) {
        return @()
    }
    foreach ($path in @(Get-ChildItem -LiteralPath $rawDirectory -Filter '*.pair.json' -File -Recurse)) {
        try {
            $pair = Get-Content -LiteralPath $path.FullName -Raw | ConvertFrom-Json
            if ($pair.schemaVersion -ne 2 -or
                $null -eq $pair.sourceProvenance -or
                [string]$pair.sourceProvenance.type -ne 'synthetic_case') {
                continue
            }
            $fixtureId = [string]$pair.sourceProvenance.caseId
            $resultPath = Join-Path $resultsDirectory "$fixtureId/$($pair.runId).json"
            $records.Add([pscustomobject]@{
                    pair = $pair
                    pairPath = $path.FullName
                    fixtureId = $fixtureId
                    capturePath = Join-Path $rawDirectory "$fixtureId/$($pair.runId).json"
                    blindPath = Join-Path $rawDirectory "$fixtureId/$($pair.runId).blind.json"
                    resultPath = $resultPath
                    completed = Test-Path -LiteralPath $resultPath -PathType Leaf
                    modifiedAt = $path.LastWriteTimeUtc
                })
        }
        catch {
            throw "Invalid pair record $($path.FullName): $($_.Exception.Message)"
        }
    }
    return @($records.ToArray())
}

function Show-ReviewRequest {
    param([Parameter(Mandatory = $true)]$Run)

    Write-Output ''
    Write-Output 'Hosted review is ready for the only required GitHub action.'
    Write-Output "Request a $($Run.pair.reviewEffort) Copilot review on both pull requests:"
    Write-Output "  Control: $($Run.pair.control.url)"
    Write-Output "  Hosted : $($Run.pair.hosted.url)"
    Write-Output ''
    Write-Output 'After both reviews finish, rerun this same command. Nothing is waiting or polling.'
}

function Read-Adjudications {
    param(
        [Parameter(Mandatory = $true)]$BlindCapture,
        [Parameter(Mandatory = $true)]$Case
    )

    $expected = @($Case.expectedFindings)
    $result = @{}
    Write-Output ''
    Write-Output 'Expected findings:'
    for ($index = 0; $index -lt $expected.Count; $index++) {
        Write-Output "  $($index + 1). [$($expected[$index].ruleId)] $($expected[$index].reason)"
    }

    foreach ($profile in @($BlindCapture.profiles)) {
        $slot = [string]$profile.slot
        $slotDecisions = @{}
        $previousComments = New-Object 'System.Collections.Generic.List[object]'
        Write-Output ''
        Write-Output "Adjudicate blinded profile $slot"
        foreach ($comment in @($profile.comments)) {
            $ordinal = $previousComments.Count + 1
            Write-Output ''
            Write-Output "Comment $ordinal"
            Write-Output "  File: $($comment.path):$($comment.line)"
            Write-Output "  $($comment.body)"

            $classification = $null
            while ($null -eq $classification) {
                $choice = (Read-Host 'Classify as [e]xpected, [u]nexpected-valid, [f]alse-positive, or [d]uplicate').Trim().ToLowerInvariant()
                $classification = switch ($choice) {
                    'e' { 'expected' }
                    'u' { 'unexpected-valid' }
                    'f' { 'false-positive' }
                    'd' { 'duplicate' }
                    default { $null }
                }
            }

            $ruleIds = @()
            $duplicateOf = $null
            if ($classification -eq 'expected') {
                while ($ruleIds.Count -eq 0) {
                    $selection = (Read-Host 'Expected finding number(s), comma-separated').Trim()
                    $numbers = @($selection -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ -match '^[1-9][0-9]*$' } | ForEach-Object { [int]$_ })
                    if ($numbers.Count -gt 0 -and @($numbers | Where-Object { $_ -gt $expected.Count }).Count -eq 0) {
                        $ruleIds = @($numbers | ForEach-Object { [string]$expected[$_ - 1].ruleId } | Sort-Object -Unique)
                    }
                }
            }
            elseif ($classification -eq 'duplicate') {
                if ($previousComments.Count -eq 0) {
                    throw 'The first comment in a profile cannot be classified as a duplicate'
                }
                while ($null -eq $duplicateOf) {
                    $selection = (Read-Host "Earlier comment number [1-$($previousComments.Count)]").Trim()
                    if ($selection -match '^[1-9][0-9]*$' -and [int]$selection -le $previousComments.Count) {
                        $duplicateOf = [int64]$previousComments[[int]$selection - 1].id
                    }
                }
            }

            $reason = ''
            while ([string]::IsNullOrWhiteSpace($reason)) {
                $reason = (Read-Host 'Reason').Trim()
            }
            $slotDecisions[[string]$comment.id] = [pscustomobject]@{
                classification = $classification
                ruleIds = $ruleIds
                duplicateOf = $duplicateOf
                reason = $reason
            }
            $previousComments.Add($comment)
        }
        $result[$slot] = $slotDecisions
    }
    return $result
}

function Test-GeneratedResult {
    param(
        [Parameter(Mandatory = $true)]$Result,
        [Parameter(Mandatory = $true)][string]$FixtureId,
        [Parameter(Mandatory = $true)][string]$RunId
    )

    $tempRoot = Join-Path ([IO.Path]::GetTempPath()) ("hosted-review-result-$([guid]::NewGuid().ToString('N'))")
    $tempResultPath = Join-Path $tempRoot "$FixtureId/$RunId.json"
    New-Item -ItemType Directory -Path (Split-Path -Parent $tempResultPath) -Force | Out-Null
    try {
        $Result | ConvertTo-Json -Depth 30 | Set-Content -LiteralPath $tempResultPath -Encoding utf8NoBOM
        $pwsh = Get-Command pwsh -ErrorAction Stop
        $output = @(& $pwsh.Source -NoProfile -File $validatorPath -ResultsDirectory $tempRoot -CasesDirectory $casesDirectory -SchemaPath $schemaPath -OutputFormat Json 2>&1)
        if ($LASTEXITCODE -ne 0) {
            throw "Generated result validation failed: $((($output | Out-String).Trim()))"
        }
    }
    finally {
        Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}

function Show-ResultSummary {
    param([Parameter(Mandatory = $true)]$Result)

    Write-Output ''
    Write-Output 'Hosted review comparison complete'
    Write-Output "  Status : $($Result.summary.comparisonStatus)"
    Write-Output "  Control: $($Result.summary.control.expectedFound) expected, $($Result.summary.control.missed) missed, $($Result.summary.control.unexpectedValid) additional valid, $($Result.summary.control.falsePositives) false positive"
    Write-Output "  Hosted : $($Result.summary.hosted.expectedFound) expected, $($Result.summary.hosted.missed) missed, $($Result.summary.hosted.unexpectedValid) additional valid, $($Result.summary.hosted.falsePositives) false positive"
    foreach ($reason in @($Result.summary.confoundingReasons)) {
        Write-Output "  Limit  : $reason"
    }
}

$resolvedRepoDirectory = [IO.Path]::GetFullPath($RepoDirectory)
$gitCommand = Get-Command git -ErrorAction SilentlyContinue
if ($null -eq $gitCommand) { throw 'git was not found on PATH' }
if (-not (Test-Path -LiteralPath (Join-Path $resolvedRepoDirectory '.git'))) {
    throw "RepoDirectory is not a Git repository root: $resolvedRepoDirectory"
}
if (-not [string]::IsNullOrWhiteSpace((Invoke-Git status --porcelain | Out-String))) {
    throw "RepoDirectory must have a clean working tree: $resolvedRepoDirectory"
}

$runs = @(Get-RunRecords)
$matchingRuns = @($runs | Where-Object {
        [string]::IsNullOrWhiteSpace($CaseId) -or $_.fixtureId -eq $CaseId
    } | Sort-Object modifiedAt -Descending)
$activeRuns = @($matchingRuns | Where-Object { -not $_.completed })
$run = if ($NewRun) { $null } elseif ($activeRuns.Count -gt 0) { $activeRuns[0] } elseif ($matchingRuns.Count -gt 0) { $matchingRuns[0] } else { $null }

if ([string]::IsNullOrWhiteSpace($CaseId)) {
    if ($activeRuns.Count -gt 1) {
        Write-Output 'More than one unfinished controlled review exists. Rerun with one of these CaseId values:'
        $activeRuns.fixtureId | Sort-Object -Unique | ForEach-Object { Write-Output "  $_" }
        return
    }
    if ($null -eq $run) {
        Write-Output 'No controlled review exists. Start one by supplying -CaseId.'
        return
    }
    $CaseId = $run.fixtureId
}

$case = Get-CaseRecord -Id $CaseId
if ($null -eq $run) {
    if ($Cleanup) {
        throw 'No completed Hosted review is available for cleanup'
    }
    $controlBaseExists = $true
    try { $pinnedCommit = ([string]@(Invoke-Git rev-parse --verify control-base)[0]).Trim() } catch { $controlBaseExists = $false }
    if (-not $controlBaseExists) {
        $pinnedCommit = ([string]@(Invoke-Git rev-parse --verify origin/main)[0]).Trim()
        $null = Invoke-JsonStage -Path $initializePath -Arguments @('-RepoDirectory', $resolvedRepoDirectory, '-PinnedCommit', $pinnedCommit, '-Initialize', '-Push', '-OutputFormat', 'Json')
    }
    else {
        $null = Invoke-JsonStage -Path $initializePath -Arguments @('-RepoDirectory', $resolvedRepoDirectory, '-PinnedCommit', $pinnedCommit, '-OutputFormat', 'Json')
    }

    $runId = "$($ReviewEffort.ToLowerInvariant())-$([DateTimeOffset]::UtcNow.ToString('yyyyMMdd-HHmmss'))"
    $created = Invoke-JsonStage -Path $publishPath -Arguments @('-RepoDirectory', $resolvedRepoDirectory, '-CaseId', $CaseId, '-RunId', $runId, '-ReviewEffort', $ReviewEffort, '-Create', '-OutputFormat', 'Json')
    $pair = Get-Content -LiteralPath $created.pairPath -Raw | ConvertFrom-Json
    $run = [pscustomobject]@{
        pair = $pair
        pairPath = [string]$created.pairPath
        fixtureId = $CaseId
        capturePath = Join-Path $rawDirectory "$CaseId/$runId.json"
        blindPath = Join-Path $rawDirectory "$CaseId/$runId.blind.json"
        resultPath = Join-Path $resultsDirectory "$CaseId/$runId.json"
        completed = $false
        modifiedAt = [DateTime]::UtcNow
    }
    Show-ReviewRequest -Run $run
    return
}

$ReviewEffort = [string]$run.pair.reviewEffort

if (Test-Path -LiteralPath $run.resultPath -PathType Leaf) {
    $result = Get-Content -LiteralPath $run.resultPath -Raw | ConvertFrom-Json
    Show-ResultSummary -Result $result
    if ($Cleanup) {
        $null = Invoke-JsonStage -Path $closePath -Arguments @('-RepoDirectory', $resolvedRepoDirectory, '-PairPath', $run.pairPath, '-Close', '-OutputFormat', 'Json')
        Write-Output 'Disposable review pull requests and branches were removed.'
    }
    else {
        Write-Output 'Rerun with -Cleanup to approve removal of the disposable review pull requests and branches.'
    }
    return
}

if (-not (Test-Path -LiteralPath $run.capturePath -PathType Leaf)) {
    try {
        $null = Invoke-JsonStage -Path $capturePath -Arguments @('-PairPath', $run.pairPath)
    }
    catch {
        if ($_.Exception.Message -match 'has no completed Copilot (?:Lite|Balanced) review') {
            Show-ReviewRequest -Run $run
            return
        }
        throw
    }
}

if (-not (Test-Path -LiteralPath $run.blindPath -PathType Leaf)) {
    throw "Blinded capture was not created: $($run.blindPath)"
}
$capture = Get-Content -LiteralPath $run.capturePath -Raw | ConvertFrom-Json
$blindCapture = Get-Content -LiteralPath $run.blindPath -Raw | ConvertFrom-Json
$adjudications = Read-Adjudications -BlindCapture $blindCapture -Case $case
$rawCapturePath = [IO.Path]::GetRelativePath($regressionDirectory, $run.capturePath).Replace('\', '/')
$result = New-HostedReviewResult -Capture $capture -Case $case -Adjudications $adjudications -RawCapturePath $rawCapturePath -CompletedAt (ConvertTo-UtcTimestamp -Value ([DateTimeOffset]::UtcNow))
Test-GeneratedResult -Result $result -FixtureId $CaseId -RunId ([string]$run.pair.runId)
New-Item -ItemType Directory -Path (Split-Path -Parent $run.resultPath) -Force | Out-Null
$result | ConvertTo-Json -Depth 30 | Set-Content -LiteralPath $run.resultPath -Encoding utf8NoBOM
Show-ResultSummary -Result $result
Write-Output "Result  : $($run.resultPath)"
Write-Output 'Rerun with -Cleanup to approve removal of the disposable review pull requests and branches.'
