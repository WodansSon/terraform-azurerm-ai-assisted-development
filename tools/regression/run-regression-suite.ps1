param(
    [string[]] $Task,

    [string[]] $CaseStatus = @("adjudicated"),

    [string] $CasesDirectory = (Join-Path $PSScriptRoot "cases"),

    [string] $ExamplesDirectory = (Join-Path $PSScriptRoot "examples"),

    [ValidateSet("text", "json")]
    [string] $Output = "text",

    [switch] $AsJson
)

$ErrorActionPreference = "Stop"

if ($AsJson) {
    $Output = "json"
}

$targetSkillTasks = @(
    "docs-writer",
    "resource-implementation",
    "acceptance-testing"
)

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

function Get-JsonFile {
    param([string] $Path)

    if (-not (Test-Path -LiteralPath $Path)) {
        throw "file not found: $Path"
    }

    return Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json
}

function Get-CaseFiles {
    param([string] $CasesDirectory)

    if (-not (Test-Path -LiteralPath $CasesDirectory)) {
        return @()
    }

    return @(Get-ChildItem -LiteralPath $CasesDirectory -Filter *.json | Sort-Object BaseName)
}

function Resolve-ExampleArtifactPath {
    param(
        [string] $ExamplesDirectory,
        [string] $CaseId,
        [string] $Extension
    )

    $candidate = Join-Path $ExamplesDirectory ($CaseId + $Extension)
    if (Test-Path -LiteralPath $candidate) {
        return $candidate
    }

    return $null
}

function Get-SkillCoverageStatus {
    param(
        [int] $CaseCount,
        [int] $AdjudicatedCount,
        [int] $ExampleResultCount
    )

    if ($ExampleResultCount -gt 0) {
        return "covered"
    }

    if ($AdjudicatedCount -gt 0) {
        return "missing-example-result"
    }

    if ($CaseCount -gt 0) {
        return "not-yet-adjudicated"
    }

    return "no-direct-case"
}

$Task = Expand-ListParameter -Value $Task
$CaseStatus = Expand-ListParameter -Value $CaseStatus

$allCaseFiles = Get-CaseFiles -CasesDirectory $CasesDirectory
$allCases = @()

foreach ($caseFile in $allCaseFiles) {
    $case = Get-JsonFile -Path $caseFile.FullName
    $allCases += [pscustomobject]@{
        definition = $case
        casePath = $caseFile.FullName
        exampleResultPath = Resolve-ExampleArtifactPath -ExamplesDirectory $ExamplesDirectory -CaseId $case.id -Extension ".result.json"
        exampleReviewPath = Resolve-ExampleArtifactPath -ExamplesDirectory $ExamplesDirectory -CaseId $case.id -Extension ".review.md"
    }
}

$selectedCases = @($allCases | Where-Object {
        ($Task.Count -eq 0 -or $Task -contains $_.definition.task) -and
        ($CaseStatus.Count -eq 0 -or $CaseStatus -contains $_.definition.caseStatus)
    })

if ($selectedCases.Count -gt 0) {
    $validatorArguments = @{
        CasePath = @($selectedCases | ForEach-Object { $_.casePath } | Select-Object -Unique)
    }

    $selectedResultPaths = @($selectedCases | Where-Object { $_.exampleResultPath } | ForEach-Object { $_.exampleResultPath } | Select-Object -Unique)
    if ($selectedResultPaths.Count -gt 0) {
        $validatorArguments.ResultPath = $selectedResultPaths
    }

    & pwsh -NoProfile -File (Join-Path $PSScriptRoot "validate-regression-artifacts.ps1") @validatorArguments | Out-Null
}

$caseResults = @()
foreach ($selectedCase in $selectedCases) {
    $scoreSummary = $null
    $skipReason = $null

    if ($selectedCase.definition.caseStatus -ne "adjudicated") {
        $skipReason = "case status '$($selectedCase.definition.caseStatus)' is not runnable"
    }
    elseif (-not $selectedCase.exampleResultPath) {
        $skipReason = "example result artifact not found"
    }
    else {
        $scoreSummary = & pwsh -NoProfile -File (Join-Path $PSScriptRoot "score-regression-case.ps1") -CasePath $selectedCase.casePath -ResultPath $selectedCase.exampleResultPath -Output json | ConvertFrom-Json
    }

    $caseResults += [pscustomobject]@{
        id = $selectedCase.definition.id
        task = $selectedCase.definition.task
        caseStatus = $selectedCase.definition.caseStatus
        scored = [bool]$scoreSummary
        pass = if ($scoreSummary) { [bool]$scoreSummary.pass } else { $null }
        overallScore = if ($scoreSummary) { [double]$scoreSummary.overallScore } else { $null }
        exampleResultPath = $selectedCase.exampleResultPath
        exampleReviewPath = $selectedCase.exampleReviewPath
        skipReason = $skipReason
    }
}

$targetSkillCoverage = @()
foreach ($skillTask in $targetSkillTasks) {
    $taskCases = @($allCases | Where-Object { $_.definition.task -eq $skillTask })
    $adjudicatedCases = @($taskCases | Where-Object { $_.definition.caseStatus -eq "adjudicated" })
    $exampleResultCases = @($taskCases | Where-Object { $_.exampleResultPath })

    $targetSkillCoverage += [pscustomobject]@{
        task = $skillTask
        caseCount = $taskCases.Count
        adjudicatedCount = $adjudicatedCases.Count
        exampleResultCount = $exampleResultCases.Count
        status = Get-SkillCoverageStatus -CaseCount $taskCases.Count -AdjudicatedCount $adjudicatedCases.Count -ExampleResultCount $exampleResultCases.Count
    }
}

$summary = [ordered]@{
    selectedCaseCount = $selectedCases.Count
    scoredCaseCount = @($caseResults | Where-Object { $_.scored }).Count
    skippedCaseCount = @($caseResults | Where-Object { -not $_.scored }).Count
    filters = [ordered]@{
        task = if ($Task.Count -gt 0) { @($Task) } else { @() }
        caseStatus = if ($CaseStatus.Count -gt 0) { @($CaseStatus) } else { @() }
    }
    targetSkillCoverage = $targetSkillCoverage
    caseResults = $caseResults
}

if ($Output -eq "json") {
    $summary | ConvertTo-Json -Depth 10
    return
}

Write-Output "Regression suite summary"
Write-Output "  Selected Cases  : $($summary.selectedCaseCount)"
Write-Output "  Scored Cases    : $($summary.scoredCaseCount)"
Write-Output "  Skipped Cases   : $($summary.skippedCaseCount)"
Write-Output "  Task Filter     : $(if ($Task.Count -gt 0) { $Task -join ', ' } else { 'all' })"
Write-Output "  Status Filter   : $(if ($CaseStatus.Count -gt 0) { $CaseStatus -join ', ' } else { 'all' })"
Write-Output ""
Write-Output "Target skill coverage"
foreach ($coverage in $targetSkillCoverage) {
    Write-Output "  $($coverage.task): cases=$($coverage.caseCount), adjudicated=$($coverage.adjudicatedCount), exampleResults=$($coverage.exampleResultCount), status=$($coverage.status)"
}

Write-Output ""
Write-Output "Case results"
if ($caseResults.Count -eq 0) {
    Write-Output "  No cases matched the requested filters."
}
else {
    foreach ($caseResult in $caseResults) {
        if ($caseResult.scored) {
            Write-Output "  $(if ($caseResult.pass) { 'PASS' } else { 'FAIL' })  $($caseResult.overallScore)  $($caseResult.id)  [$($caseResult.task)]"
        }
        else {
            Write-Output "  SKIP  $($caseResult.id)  [$($caseResult.task)]  $($caseResult.skipReason)"
        }
    }
}
