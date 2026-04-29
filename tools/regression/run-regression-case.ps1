param(
    [string] $Case,

    [string] $CasePath,

    [string] $RunsDirectory = (Join-Path $PSScriptRoot "runs")
)

$ErrorActionPreference = "Stop"

function Get-JsonFile {
    param([string] $Path)

    if (-not (Test-Path -LiteralPath $Path)) {
        throw "file not found: $Path"
    }

    return Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json
}

function Get-RelativeRepoPath {
    param(
        [string] $RepoRoot,
        [string] $Path
    )

    return [System.IO.Path]::GetRelativePath($RepoRoot, $Path)
}

function Get-AvailableCases {
    param([string] $CasesDirectory)

    if (-not (Test-Path -LiteralPath $CasesDirectory)) {
        return @()
    }

    return @(Get-ChildItem -LiteralPath $CasesDirectory -Filter *.json | Sort-Object BaseName)
}

function Show-Usage {
    param(
        [string[]] $AvailableCases
    )

    Write-Output "Usage: pwsh -NoProfile -File ./tools/regression/run-regression-case.ps1 -Case <case-id>"
    Write-Output "   or: pwsh -NoProfile -File ./tools/regression/run-regression-case.ps1 -CasePath <case.json>"
    Write-Output ""
    Write-Output "Available case aliases:"

    foreach ($availableCase in $AvailableCases) {
        Write-Output "  - $availableCase"
    }
}

function Resolve-CaseFile {
    param(
        [string] $Case,
        [string] $CasePath,
        [string] $CasesDirectory,
        [string] $RepoRoot
    )

    $availableCaseFiles = Get-AvailableCases -CasesDirectory $CasesDirectory
    $availableAliases = @($availableCaseFiles | ForEach-Object { $_.BaseName })

    if (([string]::IsNullOrWhiteSpace($Case) -and [string]::IsNullOrWhiteSpace($CasePath)) -or
        (-not [string]::IsNullOrWhiteSpace($Case) -and -not [string]::IsNullOrWhiteSpace($CasePath))) {
        Show-Usage -AvailableCases $availableAliases
        throw "specify exactly one of -Case or -CasePath"
    }

    if (-not [string]::IsNullOrWhiteSpace($CasePath)) {
        return Resolve-Path -LiteralPath $CasePath
    }

    $matches = @($availableCaseFiles | Where-Object { $_.BaseName -eq $Case -or $_.Name -eq $Case })
    if ($matches.Count -eq 0) {
        Show-Usage -AvailableCases $availableAliases
        throw "unknown case alias: $Case"
    }

    if ($matches.Count -gt 1) {
        throw "case alias is ambiguous: $Case"
    }

    return Resolve-Path -LiteralPath $matches[0].FullName
}

function Initialize-Directory {
    param([string] $Path)

    if (-not (Test-Path -LiteralPath $Path)) {
        New-Item -ItemType Directory -Path $Path -Force | Out-Null
    }
}

function Copy-Fixture {
    param(
        [string] $SourcePath,
        [string] $FixtureDirectory
    )

    if (-not (Test-Path -LiteralPath $SourcePath)) {
        throw "fixture source not found: $SourcePath"
    }

    Initialize-Directory -Path $FixtureDirectory

    if ((Get-Item -LiteralPath $SourcePath).PSIsContainer) {
        Copy-Item -LiteralPath $SourcePath -Destination $FixtureDirectory -Recurse -Force
        return Join-Path $FixtureDirectory (Split-Path -Leaf $SourcePath)
    }

    $destinationPath = Join-Path $FixtureDirectory (Split-Path -Leaf $SourcePath)
    Copy-Item -LiteralPath $SourcePath -Destination $destinationPath -Force
    return $destinationPath
}

$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$casesDirectory = Join-Path $PSScriptRoot "cases"
$resolvedCasePath = Resolve-CaseFile -Case $Case -CasePath $CasePath -CasesDirectory $casesDirectory -RepoRoot $repoRoot
$caseDefinition = Get-JsonFile -Path $resolvedCasePath

$runTimestamp = Get-Date -Format "yyyyMMdd-HHmmss"
$runId = "$runTimestamp-$($caseDefinition.id)"
$runDirectory = Join-Path $RunsDirectory $runId
$outputDirectory = Join-Path $runDirectory "output"
$fixtureDirectory = Join-Path $runDirectory "fixture"

Initialize-Directory -Path $runDirectory
Initialize-Directory -Path $outputDirectory

$resultOutputPath = Join-Path $outputDirectory "result.json"
$reviewOutputPath = Join-Path $outputDirectory "review.md"
$manifestPath = Join-Path $runDirectory "run-manifest.json"

$fixtureSourcePath = $null
$fixtureMaterializedPath = $null
if ($caseDefinition.fixture.mode -ne "none" -and $caseDefinition.fixture.path) {
    $fixtureSourcePath = Join-Path $repoRoot $caseDefinition.fixture.path
    $fixtureMaterializedPath = Copy-Fixture -SourcePath $fixtureSourcePath -FixtureDirectory $fixtureDirectory
}

& pwsh -NoProfile -File (Join-Path $PSScriptRoot "new-regression-result-template.ps1") -CasePath $resolvedCasePath -OutputPath $resultOutputPath | Out-Null

$reviewPlaceholder = @(
    "# Review Output Placeholder",
    "",
    "Case ID: $($caseDefinition.id)",
    "Task: $($caseDefinition.task)",
    "",
    "Replace this file with the captured human-readable prompt or skill output for this run."
)
$reviewPlaceholder | Set-Content -LiteralPath $reviewOutputPath

$resolvedCaseAbsolutePath = $resolvedCasePath.Path
$relativeCasePath = Get-RelativeRepoPath -RepoRoot $repoRoot -Path $resolvedCaseAbsolutePath
$relativeManifestPath = Get-RelativeRepoPath -RepoRoot $repoRoot -Path $manifestPath
$relativeReviewOutputPath = Get-RelativeRepoPath -RepoRoot $repoRoot -Path $reviewOutputPath
$relativeResultOutputPath = Get-RelativeRepoPath -RepoRoot $repoRoot -Path $resultOutputPath
$relativeFixtureSourcePath = if ($fixtureSourcePath) { Get-RelativeRepoPath -RepoRoot $repoRoot -Path $fixtureSourcePath } else { $null }
$relativeFixtureMaterializedPath = if ($fixtureMaterializedPath) { Get-RelativeRepoPath -RepoRoot $repoRoot -Path $fixtureMaterializedPath } else { $null }

$manifest = [ordered]@{
    version = 1
    runId = $runId
    createdUtc = [DateTime]::UtcNow.ToString("o")
    case = [ordered]@{
        id = $caseDefinition.id
        task = $caseDefinition.task
        status = $caseDefinition.caseStatus
        casePath = $relativeCasePath
    }
    fixture = [ordered]@{
        mode = $caseDefinition.fixture.mode
        sourcePath = $relativeFixtureSourcePath
        materializedPath = $relativeFixtureMaterializedPath
    }
    artifacts = [ordered]@{
        reviewOutputPath = $relativeReviewOutputPath
        resultOutputPath = $relativeResultOutputPath
        manifestPath = $relativeManifestPath
    }
    commands = [ordered]@{
        hydrateExample = "pwsh -NoProfile -File ./tools/regression/hydrate-regression-run.ps1 -RunDirectory ./$([System.IO.Path]::GetRelativePath($repoRoot, $runDirectory))"
        score = "pwsh -NoProfile -File ./tools/regression/score-regression-case.ps1 -CasePath ./$relativeCasePath -ResultPath ./$relativeResultOutputPath"
        previewExample = "pwsh -NoProfile -File ./tools/regression/run-regression-example.ps1 -CasePath ./$relativeCasePath -ShowFixture -ShowReview"
    }
    nextSteps = @(
        "optionally hydrate the run from adjudicated example artifacts using the hydrateExample command",
        "replace the review file with the captured human-readable output for a real run",
        "update the generated result file with the adjudicated outcome for the run",
        "run the score command from this manifest to compute the weighted benchmark result"
    )
}

$manifest | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $manifestPath

Write-Output "Regression run scaffold created"
Write-Output "  Case ID         : $($caseDefinition.id)"
Write-Output "  Task            : $($caseDefinition.task)"
Write-Output "  Run ID          : $runId"
Write-Output "  Run Directory   : $runDirectory"
if ($fixtureMaterializedPath) {
    Write-Output "  Fixture Copy    : $fixtureMaterializedPath"
}
Write-Output "  Review Output   : $reviewOutputPath"
Write-Output "  Result Template : $resultOutputPath"
Write-Output "  Run Manifest    : $manifestPath"
Write-Output ""
Write-Output "Next command:"
Write-Output "  $($manifest.commands.hydrateExample)"
