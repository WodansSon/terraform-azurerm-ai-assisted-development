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

$directSkillTasks = @(
    "docs-writer",
    "resource-implementation",
    "acceptance-testing"
)

$skillCoverageTargets = @(
    [pscustomobject]@{ name = 'docs-writer'; matchMode = 'task'; matchValue = 'docs-writer'; section = 'direct' },
    [pscustomobject]@{ name = 'resource-implementation'; matchMode = 'task'; matchValue = 'resource-implementation'; section = 'direct' },
    [pscustomobject]@{ name = 'acceptance-testing'; matchMode = 'task'; matchValue = 'acceptance-testing'; section = 'direct' },
    [pscustomobject]@{ name = 'review-coordinator'; matchMode = 'regex'; matchValue = 'Skill used:\s*review-coordinator'; section = 'routed' },
    [pscustomobject]@{ name = 'review-architect'; matchMode = 'regex'; matchValue = 'Skill used:\s*review-architect'; section = 'routed' },
    [pscustomobject]@{ name = 'review-skeptic'; matchMode = 'regex'; matchValue = 'Skill used:\s*review-skeptic'; section = 'routed' },
    [pscustomobject]@{ name = 'review-advocate'; matchMode = 'regex'; matchValue = 'Skill used:\s*review-advocate'; section = 'routed' },
    [pscustomobject]@{ name = 'review-moderator'; matchMode = 'regex'; matchValue = 'Skill used:\s*review-moderator'; section = 'routed' },
    [pscustomobject]@{ name = 'review-presentation'; matchMode = 'regex'; matchValue = 'review-presentation-compliance-contract\.instructions\.md'; section = 'routed' },
    [pscustomobject]@{ name = 'custom-poller-migration'; matchMode = 'regex'; matchValue = 'Skill used:\s*custom-poller-migration'; section = 'routed' }
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

function Test-CaseMatchesSkillCoverageTarget {
    param(
        $CaseRecord,
        $CoverageTarget
    )

    switch ($CoverageTarget.matchMode) {
        'task' {
            return [string]$CaseRecord.definition.task -eq [string]$CoverageTarget.matchValue
        }

        'regex' {
            return [string]$CaseRecord.coverageText -match [string]$CoverageTarget.matchValue
        }
    }

    throw "unsupported skill coverage match mode '$($CoverageTarget.matchMode)'"
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
        coverageText = ($case | ConvertTo-Json -Depth 100)
    }
}

$selectedCases = @($allCases | Where-Object {
        ($Task.Count -eq 0 -or $Task -contains $_.definition.task) -and
        ($CaseStatus.Count -eq 0 -or $CaseStatus -contains $_.definition.caseStatus)
    })

if ($selectedCases.Count -gt 0) {
    $selectedCasePaths = @($selectedCases | ForEach-Object { $_.casePath } | Select-Object -Unique)
    $selectedResultPaths = @($selectedCases | Where-Object { $_.exampleResultPath } | ForEach-Object { $_.exampleResultPath } | Select-Object -Unique)

    $validatorArguments = @{
        CasePath = $selectedCasePaths
    }

    if ($selectedResultPaths.Count -gt 0) {
        $validatorArguments.ResultPath = $selectedResultPaths
    }

    & (Join-Path $PSScriptRoot 'validate-regression-artifacts.ps1') @validatorArguments | Out-Null
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

$skillCoverage = @()
foreach ($coverageTarget in $skillCoverageTargets) {
    $matchingCases = @($allCases | Where-Object { Test-CaseMatchesSkillCoverageTarget -CaseRecord $_ -CoverageTarget $coverageTarget })
    $adjudicatedCases = @($matchingCases | Where-Object { $_.definition.caseStatus -eq "adjudicated" })
    $exampleResultCases = @($matchingCases | Where-Object { $_.exampleResultPath })

    $skillCoverage += [pscustomobject]@{
        skill = $coverageTarget.name
        section = $coverageTarget.section
        caseCount = $matchingCases.Count
        adjudicatedCount = $adjudicatedCases.Count
        exampleResultCount = $exampleResultCases.Count
        status = Get-SkillCoverageStatus -CaseCount $matchingCases.Count -AdjudicatedCount $adjudicatedCases.Count -ExampleResultCount $exampleResultCases.Count
    }
}

$targetSkillCoverage = @($skillCoverage | Where-Object { $_.section -eq 'direct' } | ForEach-Object {
    [pscustomobject]@{
        task = $_.skill
        caseCount = $_.caseCount
        adjudicatedCount = $_.adjudicatedCount
        exampleResultCount = $_.exampleResultCount
        status = $_.status
    }
})

$routedSkillCoverage = @($skillCoverage | Where-Object { $_.section -eq 'routed' })

$summary = [ordered]@{
    selectedCaseCount = $selectedCases.Count
    scoredCaseCount = @($caseResults | Where-Object { $_.scored }).Count
    skippedCaseCount = @($caseResults | Where-Object { -not $_.scored }).Count
    filters = [ordered]@{
        task = if ($Task.Count -gt 0) { @($Task) } else { @() }
        caseStatus = if ($CaseStatus.Count -gt 0) { @($CaseStatus) } else { @() }
    }
    targetSkillCoverage = $targetSkillCoverage
    routedSkillCoverage = $routedSkillCoverage
    skillCoverage = $skillCoverage
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
Write-Output "Direct skill task coverage"
foreach ($coverage in $targetSkillCoverage) {
    Write-Output "  $($coverage.task): cases=$($coverage.caseCount), adjudicated=$($coverage.adjudicatedCount), exampleResults=$($coverage.exampleResultCount), status=$($coverage.status)"
}

Write-Output ""
Write-Output "Routed and companion skill coverage"
foreach ($coverage in $routedSkillCoverage) {
    Write-Output "  $($coverage.skill): cases=$($coverage.caseCount), adjudicated=$($coverage.adjudicatedCount), exampleResults=$($coverage.exampleResultCount), status=$($coverage.status)"
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
