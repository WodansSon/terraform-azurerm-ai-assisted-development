param(
    [Parameter(Mandatory)]
    [string] $CasePath,

    [Parameter(Mandatory)]
    [string] $ResultPath,

    [string] $WeightsPath = (Join-Path $PSScriptRoot "config/score-weights.json"),

    [switch] $AsJson
)

$ErrorActionPreference = "Stop"

function Get-JsonFile {
    param([string] $Path)

    if (-not (Test-Path -LiteralPath $Path)) {
        throw "file not found: $Path"
    }

    return Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json
}

function Get-PercentScore {
    param(
        [double] $Numerator,
        [double] $Denominator
    )

    if ($Denominator -le 0) {
        return 100.0
    }

    return [Math]::Round(($Numerator / $Denominator) * 100.0, 2)
}

function Get-BoolScore {
    param([bool] $Value)
    if ($Value) {
        return 100.0
    }

    return 0.0
}

$case = Get-JsonFile -Path $CasePath
$result = Get-JsonFile -Path $ResultPath
$weights = Get-JsonFile -Path $WeightsPath

if ($case.id -ne $result.caseId) {
    throw "case id mismatch: case '$($case.id)' vs result '$($result.caseId)'"
}

if ($case.task -ne $result.task) {
    throw "task mismatch: case '$($case.task)' vs result '$($result.task)'"
}

$mustCatchKeys = @($case.mustCatch | ForEach-Object { $_.key })
$caughtKeys = @($result.findings.caught)
$falsePositiveKeys = @($result.findings.falsePositives)

$caughtMustCatchCount = @($caughtKeys | Where-Object { $mustCatchKeys -contains $_ } | Select-Object -Unique).Count
$mustCatchRecall = Get-PercentScore -Numerator $caughtMustCatchCount -Denominator $mustCatchKeys.Count

$mustNotFlagCount = @($case.mustNotFlag).Count
$falsePositiveCount = @($falsePositiveKeys | Select-Object -Unique).Count
$falsePositiveControl = if ($falsePositiveCount -eq 0) {
    100.0
}
elseif ($mustNotFlagCount -gt 0) {
    [Math]::Round([Math]::Max(0.0, 100.0 - (($falsePositiveCount / $mustNotFlagCount) * 100.0)), 2)
}
else {
    0.0
}

$severityCorrectness = Get-PercentScore -Numerator $result.severityChecks.matched -Denominator $result.severityChecks.total

$expectedToolChecks = @()
foreach ($property in $case.expectedTools.PSObject.Properties) {
    $actualValue = $result.toolExecution.PSObject.Properties[$property.Name].Value
    $expectedToolChecks += [bool]($actualValue -eq $property.Value)
}

$toolExpectationScore = if ($expectedToolChecks.Count -eq 0) {
    100.0
}
else {
    Get-PercentScore -Numerator (@($expectedToolChecks | Where-Object { $_ }).Count) -Denominator $expectedToolChecks.Count
}

$scopeAndToolCorrectness = [Math]::Round((
        (Get-BoolScore -Value $result.scopeChecks.ruleFamiliesAppliedCorrectly) +
        (Get-BoolScore -Value $result.scopeChecks.toolingBehaviorCorrect) +
        $toolExpectationScore
    ) / 3.0, 2)

$outputCompliance = [Math]::Round((
        (Get-BoolScore -Value $result.outputChecks.requiredSectionsPresent) +
        (Get-BoolScore -Value $result.outputChecks.requiredMarkersPresent)
    ) / 2.0, 2)

$determinism = Get-BoolScore -Value $result.determinismChecks.materiallyEquivalentAcrossRuns

$weightedOverall = [Math]::Round((
        ($mustCatchRecall * $weights.weights.mustCatchRecall) +
        ($falsePositiveControl * $weights.weights.falsePositiveControl) +
        ($severityCorrectness * $weights.weights.severityCorrectness) +
        ($scopeAndToolCorrectness * $weights.weights.scopeAndToolCorrectness) +
        ($outputCompliance * $weights.weights.outputCompliance) +
        ($determinism * $weights.weights.determinism)
    ) / 100.0, 2)

$pass = $true
if ($weightedOverall -lt $weights.passGuidance.minimumOverallScore) {
    $pass = $false
}

if ($mustCatchRecall -lt $weights.passGuidance.minimumMustCatchRecall) {
    $pass = $false
}

if (-not $weights.passGuidance.allowFalsePositives -and $falsePositiveCount -gt 0) {
    $pass = $false
}

$summary = [ordered]@{
    caseId = $case.id
    task = $case.task
    pass = $pass
    overallScore = $weightedOverall
    scores = [ordered]@{
        mustCatchRecall = $mustCatchRecall
        falsePositiveControl = $falsePositiveControl
        severityCorrectness = $severityCorrectness
        scopeAndToolCorrectness = $scopeAndToolCorrectness
        outputCompliance = $outputCompliance
        determinism = $determinism
    }
    counts = [ordered]@{
        mustCatch = $mustCatchKeys.Count
        caughtMustCatch = $caughtMustCatchCount
        falsePositives = $falsePositiveCount
    }
}

if ($AsJson) {
    $summary | ConvertTo-Json -Depth 10
    return
}

Write-Output "Regression score summary"
Write-Output "  Case             : $($summary.caseId)"
Write-Output "  Task             : $($summary.task)"
Write-Output "  Pass             : $($summary.pass)"
Write-Output "  Overall Score    : $($summary.overallScore)"
Write-Output "  Must-catch Recall: $($summary.scores.mustCatchRecall)"
Write-Output "  False Positives  : $($summary.scores.falsePositiveControl)"
Write-Output "  Severity         : $($summary.scores.severityCorrectness)"
Write-Output "  Scope/Tool       : $($summary.scores.scopeAndToolCorrectness)"
Write-Output "  Output           : $($summary.scores.outputCompliance)"
Write-Output "  Determinism      : $($summary.scores.determinism)"
