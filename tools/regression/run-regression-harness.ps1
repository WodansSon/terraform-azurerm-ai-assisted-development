param(
    [string[]] $Task,

    [string[]] $CaseStatus = @("adjudicated"),

    [string] $LatestDirectory = (Join-Path $PSScriptRoot "results/latest"),

    [string] $HistoryDirectory = (Join-Path $PSScriptRoot "results/history"),

    [ValidateSet("text", "json")]
    [string] $Output = "text"
)

$ErrorActionPreference = "Stop"

function Expand-ListParameter {
    param([string[]] $Value)

    $expanded = @()
    foreach ($entry in $Value) {
        if ([string]::IsNullOrWhiteSpace($entry)) {
            continue
        }

        $expanded += @($entry -split "," | ForEach-Object { $_.Trim() } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    }

    return @($expanded | Select-Object -Unique)
}

function Initialize-Directory {
    param([string] $Path)

    if (-not (Test-Path -LiteralPath $Path)) {
        New-Item -ItemType Directory -Path $Path -Force | Out-Null
    }
}

function Remove-LatestOutputs {
    param([string] $LatestDirectory)

    if (-not (Test-Path -LiteralPath $LatestDirectory)) {
        return
    }

    Get-ChildItem -LiteralPath $LatestDirectory -File | Remove-Item -Force
}

$Task = Expand-ListParameter -Value $Task
$CaseStatus = Expand-ListParameter -Value $CaseStatus

Initialize-Directory -Path $LatestDirectory
Initialize-Directory -Path $HistoryDirectory
Remove-LatestOutputs -LatestDirectory $LatestDirectory

$validationJsonPath = Join-Path $LatestDirectory "validation.json"
$suiteTextPath = Join-Path $LatestDirectory "regression-suite.txt"
$suiteJsonPath = Join-Path $LatestDirectory "regression-suite.json"
$historySnapshotLatestPath = Join-Path $LatestDirectory "regression-history-snapshot.json"
$historySummaryTextPath = Join-Path $LatestDirectory "regression-history-summary.txt"
$historySummaryJsonPath = Join-Path $LatestDirectory "regression-history-summary.json"
$harnessSummaryJsonPath = Join-Path $LatestDirectory "regression-harness-summary.json"

$sharedArguments = @{}
if ($Task.Count -gt 0) {
    $sharedArguments.Task = $Task
}
if ($CaseStatus.Count -gt 0) {
    $sharedArguments.CaseStatus = $CaseStatus
}

$validationJson = & pwsh -NoProfile -File (Join-Path $PSScriptRoot "validate-regression-artifacts.ps1") -Output json | ConvertFrom-Json
$validationJson | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $validationJsonPath

$suiteText = & pwsh -NoProfile -File (Join-Path $PSScriptRoot "run-regression-suite.ps1") @sharedArguments
$suiteText | Set-Content -LiteralPath $suiteTextPath

$suiteJson = & pwsh -NoProfile -File (Join-Path $PSScriptRoot "run-regression-suite.ps1") @sharedArguments -Output json | ConvertFrom-Json
$suiteJson | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $suiteJsonPath

$existingHistoryFiles = @()
if (Test-Path -LiteralPath $HistoryDirectory) {
    $existingHistoryFiles = @(Get-ChildItem -LiteralPath $HistoryDirectory -Filter *.json | ForEach-Object { $_.FullName })
}

$historySnapshotJson = & pwsh -NoProfile -File (Join-Path $PSScriptRoot "write-regression-history-snapshot.ps1") @sharedArguments -HistoryDirectory $HistoryDirectory -Output json | ConvertFrom-Json
$historySnapshotJson | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $historySnapshotLatestPath

$newHistoryFiles = @(Get-ChildItem -LiteralPath $HistoryDirectory -Filter *.json | Where-Object { $existingHistoryFiles -notcontains $_.FullName } | Sort-Object Name)
$createdHistorySnapshotPath = if ($newHistoryFiles.Count -gt 0) { $newHistoryFiles[-1].FullName } else { $null }

$historySummaryText = & pwsh -NoProfile -File (Join-Path $PSScriptRoot "summarize-regression-history.ps1") -HistoryDirectory $HistoryDirectory
$historySummaryText | Set-Content -LiteralPath $historySummaryTextPath

$historySummaryJson = & pwsh -NoProfile -File (Join-Path $PSScriptRoot "summarize-regression-history.ps1") -HistoryDirectory $HistoryDirectory -Output json | ConvertFrom-Json
$historySummaryJson | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $historySummaryJsonPath

$summary = [ordered]@{
    validation = [ordered]@{
        path = $validationJsonPath
        caseFileCount = [int]$validationJson.caseFileCount
        resultFileCount = [int]$validationJson.resultFileCount
    }
    suite = [ordered]@{
        textPath = $suiteTextPath
        jsonPath = $suiteJsonPath
        selectedCaseCount = [int]$suiteJson.selectedCaseCount
        scoredCaseCount = [int]$suiteJson.scoredCaseCount
        skippedCaseCount = [int]$suiteJson.skippedCaseCount
    }
    history = [ordered]@{
        snapshotPath = $historySnapshotLatestPath
        persistedSnapshotPath = $createdHistorySnapshotPath
        summaryTextPath = $historySummaryTextPath
        summaryJsonPath = $historySummaryJsonPath
        snapshotId = $historySnapshotJson.snapshotId
        snapshotCount = [int]$historySummaryJson.snapshotCount
    }
    filters = [ordered]@{
        task = @($Task)
        caseStatus = @($CaseStatus)
    }
}

$summary | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $harnessSummaryJsonPath

if ($Output -eq "json") {
    $summary | ConvertTo-Json -Depth 20
    return
}

Write-Output "Regression harness run complete"
Write-Output "  Latest Directory : $LatestDirectory"
Write-Output "  Validation JSON  : $validationJsonPath"
Write-Output "  Suite Text       : $suiteTextPath"
Write-Output "  Suite JSON       : $suiteJsonPath"
Write-Output "  History Snapshot : $historySnapshotLatestPath"
if (-not [string]::IsNullOrWhiteSpace($createdHistorySnapshotPath)) {
    Write-Output "  History Archive  : $createdHistorySnapshotPath"
}
Write-Output "  History Summary  : $historySummaryTextPath"
Write-Output ""
Write-Output "Latest metrics"
Write-Output "  Cases Selected   : $($summary.suite.selectedCaseCount)"
Write-Output "  Cases Scored     : $($summary.suite.scoredCaseCount)"
Write-Output "  Snapshots Saved  : $($summary.history.snapshotCount)"
