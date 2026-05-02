param(
    [string[]] $Task,

    [string[]] $CaseStatus = @("adjudicated"),

    [string] $HistoryDirectory = (Join-Path $PSScriptRoot "results/history"),

    [string] $OutputPath,

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

function Get-RepositorySnapshot {
    param([string] $RepoRoot)

    $snapshot = [ordered]@{
        headBranch = $null
        headCommit = $null
        worktreeHasChanges = $null
        worktreeHasUntrackedChanges = $null
    }

    if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
        return $snapshot
    }

    try {
        $snapshot.headCommit = (& git -C $RepoRoot rev-parse HEAD).Trim()
    }
    catch {
    }

    try {
        $snapshot.headBranch = (& git -C $RepoRoot rev-parse --abbrev-ref HEAD).Trim()
    }
    catch {
    }

    try {
        $statusLines = @(& git -C $RepoRoot status --porcelain)
        $snapshot.worktreeHasChanges = $statusLines.Count -gt 0
        $snapshot.worktreeHasUntrackedChanges = @($statusLines | Where-Object { $_ -like '??*' }).Count -gt 0
    }
    catch {
    }

    return $snapshot
}

$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$Task = Expand-ListParameter -Value $Task
$CaseStatus = Expand-ListParameter -Value $CaseStatus

$suiteArguments = @{}
if ($Task.Count -gt 0) {
    $suiteArguments.Task = $Task
}
if ($CaseStatus.Count -gt 0) {
    $suiteArguments.CaseStatus = $CaseStatus
}

$suiteSummary = & pwsh -NoProfile -File (Join-Path $PSScriptRoot "run-regression-suite.ps1") @suiteArguments -Output json | ConvertFrom-Json
$repositorySnapshot = Get-RepositorySnapshot -RepoRoot $repoRoot

$scoredCases = @($suiteSummary.caseResults | Where-Object { $_.scored })
$passCount = @($scoredCases | Where-Object { $_.pass }).Count
$failCount = @($scoredCases | Where-Object { -not $_.pass }).Count
$scoreValues = @($scoredCases | ForEach-Object { [double]$_.overallScore })
$averageOverallScore = if ($scoreValues.Count -gt 0) { [Math]::Round((($scoreValues | Measure-Object -Average).Average), 2) } else { 0.0 }
$minimumOverallScore = if ($scoreValues.Count -gt 0) { [Math]::Round((($scoreValues | Measure-Object -Minimum).Minimum), 2) } else { 0.0 }
$maximumOverallScore = if ($scoreValues.Count -gt 0) { [Math]::Round((($scoreValues | Measure-Object -Maximum).Maximum), 2) } else { 0.0 }
$passRate = if ($scoredCases.Count -gt 0) { [Math]::Round(($passCount / $scoredCases.Count) * 100.0, 2) } else { 0.0 }
$coveredSkillCount = @($suiteSummary.targetSkillCoverage | Where-Object { $_.status -eq "covered" }).Count

$timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
$commitSuffix = if (-not [string]::IsNullOrWhiteSpace($repositorySnapshot.headCommit)) {
    $repositorySnapshot.headCommit.Substring(0, [Math]::Min(8, $repositorySnapshot.headCommit.Length))
}
else {
    "local"
}
$snapshotId = "$timestamp-$commitSuffix"

if ([string]::IsNullOrWhiteSpace($OutputPath)) {
    Initialize-Directory -Path $HistoryDirectory
    $OutputPath = Join-Path $HistoryDirectory ($snapshotId + ".json")
}
else {
    $outputDirectory = Split-Path -Parent $OutputPath
    if (-not [string]::IsNullOrWhiteSpace($outputDirectory)) {
        Initialize-Directory -Path $outputDirectory
    }
}

$snapshot = [ordered]@{
    version = 1
    snapshotId = $snapshotId
    createdUtc = [DateTime]::UtcNow.ToString("o")
    repositorySnapshot = $repositorySnapshot
    filters = [ordered]@{
        task = @($Task)
        caseStatus = @($CaseStatus)
    }
    metrics = [ordered]@{
        selectedCaseCount = [int]$suiteSummary.selectedCaseCount
        scoredCaseCount = [int]$suiteSummary.scoredCaseCount
        passCount = $passCount
        failCount = $failCount
        skippedCaseCount = [int]$suiteSummary.skippedCaseCount
        passRate = $passRate
        averageOverallScore = $averageOverallScore
        minimumOverallScore = $minimumOverallScore
        maximumOverallScore = $maximumOverallScore
        coveredSkillCount = $coveredSkillCount
    }
    suite = $suiteSummary
}

$snapshot | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $OutputPath

$schemaPath = Join-Path $PSScriptRoot "schema/history-snapshot.schema.json"
$isValid = (Get-Content -LiteralPath $OutputPath -Raw) | Test-Json -SchemaFile $schemaPath
if (-not $isValid) {
    throw "generated regression history snapshot failed schema validation: $OutputPath"
}

if ($Output -eq "json") {
    $snapshot | ConvertTo-Json -Depth 20
    return
}

Write-Output "Regression history snapshot created"
Write-Output "  Snapshot ID      : $snapshotId"
Write-Output "  Output Path      : $OutputPath"
Write-Output "  Selected Cases   : $($snapshot.metrics.selectedCaseCount)"
Write-Output "  Scored Cases     : $($snapshot.metrics.scoredCaseCount)"
Write-Output "  Pass Count       : $($snapshot.metrics.passCount)"
Write-Output "  Fail Count       : $($snapshot.metrics.failCount)"
Write-Output "  Average Score    : $($snapshot.metrics.averageOverallScore)"
