param(
    [string] $HistoryDirectory = (Join-Path $PSScriptRoot "results/history"),

    [int] $Latest = 10,

    [ValidateSet("text", "json")]
    [string] $Output = "text"
)

$ErrorActionPreference = "Stop"

function Get-JsonFile {
    param([string] $Path)

    if (-not (Test-Path -LiteralPath $Path)) {
        throw "file not found: $Path"
    }

    return Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json
}

function Get-SnapshotFiles {
    param([string] $HistoryDirectory)

    if (-not (Test-Path -LiteralPath $HistoryDirectory)) {
        return @()
    }

    return @(Get-ChildItem -LiteralPath $HistoryDirectory -Filter *.json | Sort-Object Name)
}

function Convert-ToCaseResultMap {
    param($CaseResults)

    $map = @{}
    foreach ($caseResult in @($CaseResults)) {
        $map[$caseResult.id] = $caseResult
    }

    return $map
}

$snapshotFiles = Get-SnapshotFiles -HistoryDirectory $HistoryDirectory
if ($snapshotFiles.Count -eq 0) {
    throw "no regression history snapshots found under $HistoryDirectory"
}

$schemaPath = Join-Path $PSScriptRoot "schema/history-snapshot.schema.json"
$snapshots = @()
foreach ($snapshotFile in $snapshotFiles) {
    $content = Get-Content -LiteralPath $snapshotFile.FullName -Raw
    $isValid = $content | Test-Json -SchemaFile $schemaPath
    if (-not $isValid) {
        throw "history snapshot schema validation failed: $($snapshotFile.FullName)"
    }

    $snapshot = $content | ConvertFrom-Json
    $snapshots += [pscustomobject]@{
        path = $snapshotFile.FullName
        data = $snapshot
    }
}

$orderedSnapshots = @($snapshots | Sort-Object { [DateTime]$_.data.createdUtc })
$windowSnapshots = if ($Latest -gt 0 -and $orderedSnapshots.Count -gt $Latest) {
    @($orderedSnapshots | Select-Object -Last $Latest)
}
else {
    $orderedSnapshots
}

$latestSnapshot = $windowSnapshots[-1]
$previousSnapshot = if ($windowSnapshots.Count -gt 1) { $windowSnapshots[-2] } else { $null }

$regressions = @()
$improvements = @()

if ($previousSnapshot) {
    $previousCaseResults = Convert-ToCaseResultMap -CaseResults $previousSnapshot.data.suite.caseResults
    $latestCaseResults = Convert-ToCaseResultMap -CaseResults $latestSnapshot.data.suite.caseResults

    $caseIds = @($previousCaseResults.Keys + $latestCaseResults.Keys | Sort-Object -Unique)
    foreach ($caseId in $caseIds) {
        if (-not $previousCaseResults.ContainsKey($caseId) -or -not $latestCaseResults.ContainsKey($caseId)) {
            continue
        }

        $previousCase = $previousCaseResults[$caseId]
        $latestCase = $latestCaseResults[$caseId]
        $previousScore = if ($null -ne $previousCase.overallScore) { [double]$previousCase.overallScore } else { 0.0 }
        $latestScore = if ($null -ne $latestCase.overallScore) { [double]$latestCase.overallScore } else { 0.0 }
        $delta = [Math]::Round(($latestScore - $previousScore), 2)

        if ($previousCase.scored -and $latestCase.scored) {
            if (($previousCase.pass -and -not $latestCase.pass) -or $delta -lt 0) {
                $regressions += [pscustomobject]@{
                    caseId = $caseId
                    previousPass = [bool]$previousCase.pass
                    latestPass = [bool]$latestCase.pass
                    previousScore = $previousScore
                    latestScore = $latestScore
                    delta = $delta
                }
            }
            elseif ((-not $previousCase.pass -and $latestCase.pass) -or $delta -gt 0) {
                $improvements += [pscustomobject]@{
                    caseId = $caseId
                    previousPass = [bool]$previousCase.pass
                    latestPass = [bool]$latestCase.pass
                    previousScore = $previousScore
                    latestScore = $latestScore
                    delta = $delta
                }
            }
        }
    }
}

$summary = [ordered]@{
    snapshotCount = $orderedSnapshots.Count
    windowCount = $windowSnapshots.Count
    latestSnapshot = [ordered]@{
        snapshotId = $latestSnapshot.data.snapshotId
        createdUtc = $latestSnapshot.data.createdUtc
        headBranch = $latestSnapshot.data.repositorySnapshot.headBranch
        headCommit = $latestSnapshot.data.repositorySnapshot.headCommit
        metrics = $latestSnapshot.data.metrics
    }
    previousSnapshot = if ($previousSnapshot) {
        [ordered]@{
            snapshotId = $previousSnapshot.data.snapshotId
            createdUtc = $previousSnapshot.data.createdUtc
            headBranch = $previousSnapshot.data.repositorySnapshot.headBranch
            headCommit = $previousSnapshot.data.repositorySnapshot.headCommit
            metrics = $previousSnapshot.data.metrics
        }
    }
    else {
        $null
    }
    deltas = if ($previousSnapshot) {
        [ordered]@{
            averageOverallScore = [Math]::Round(([double]$latestSnapshot.data.metrics.averageOverallScore - [double]$previousSnapshot.data.metrics.averageOverallScore), 2)
            passRate = [Math]::Round(([double]$latestSnapshot.data.metrics.passRate - [double]$previousSnapshot.data.metrics.passRate), 2)
            selectedCaseCount = [int]$latestSnapshot.data.metrics.selectedCaseCount - [int]$previousSnapshot.data.metrics.selectedCaseCount
        }
    }
    else {
        $null
    }
    regressions = $regressions
    improvements = $improvements
    latestCoverage = $latestSnapshot.data.suite.targetSkillCoverage
}

if ($Output -eq "json") {
    $summary | ConvertTo-Json -Depth 20
    return
}

Write-Output "Regression history summary"
Write-Output "  Snapshot Count   : $($summary.snapshotCount)"
Write-Output "  Window Count     : $($summary.windowCount)"
Write-Output "  Latest Snapshot  : $($summary.latestSnapshot.snapshotId)"
Write-Output "  Latest Avg Score : $($summary.latestSnapshot.metrics.averageOverallScore)"
Write-Output "  Latest Pass Rate : $($summary.latestSnapshot.metrics.passRate)"
if ($summary.previousSnapshot) {
    Write-Output "  Previous Snapshot: $($summary.previousSnapshot.snapshotId)"
    Write-Output "  Avg Score Delta  : $($summary.deltas.averageOverallScore)"
    Write-Output "  Pass Rate Delta  : $($summary.deltas.passRate)"
}
else {
    Write-Output "  Previous Snapshot: none"
}

Write-Output ""
Write-Output "Regressions"
if ($summary.regressions.Count -eq 0) {
    Write-Output "  None"
}
else {
    foreach ($regression in $summary.regressions) {
        Write-Output "  $($regression.caseId): $($regression.previousScore) -> $($regression.latestScore)"
    }
}

Write-Output ""
Write-Output "Improvements"
if ($summary.improvements.Count -eq 0) {
    Write-Output "  None"
}
else {
    foreach ($improvement in $summary.improvements) {
        Write-Output "  $($improvement.caseId): $($improvement.previousScore) -> $($improvement.latestScore)"
    }
}
