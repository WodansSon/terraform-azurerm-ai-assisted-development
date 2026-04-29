[CmdletBinding()]
param(
    [string] $RunDirectory,

    [switch] $Latest,

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

function Resolve-RunDirectory {
    param(
        [string] $RunDirectory,
        [bool] $Latest,
        [string] $RunsDirectory
    )

    if (($Latest -and -not [string]::IsNullOrWhiteSpace($RunDirectory)) -or (-not $Latest -and [string]::IsNullOrWhiteSpace($RunDirectory))) {
        throw "specify exactly one of -RunDirectory or -Latest"
    }

    if ($Latest) {
        $latestRun = Get-ChildItem -LiteralPath $RunsDirectory -Directory | Sort-Object Name -Descending | Select-Object -First 1
        if (-not $latestRun) {
            throw "no regression run directories found under $RunsDirectory"
        }

        return $latestRun.FullName
    }

    return (Resolve-Path -LiteralPath $RunDirectory).Path
}

$resolvedRunDirectory = Resolve-RunDirectory -RunDirectory $RunDirectory -Latest:$Latest -RunsDirectory $RunsDirectory
$manifestPath = Join-Path $resolvedRunDirectory "run-manifest.json"
$manifest = Get-JsonFile -Path $manifestPath

$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$examplesDirectory = Join-Path $PSScriptRoot "examples"

$reviewSource = Join-Path $examplesDirectory ($manifest.case.id + ".review.md")
$resultSource = Join-Path $examplesDirectory ($manifest.case.id + ".result.json")

if (-not (Test-Path -LiteralPath $reviewSource)) {
    throw "review example not found for case '$($manifest.case.id)': $reviewSource"
}

if (-not (Test-Path -LiteralPath $resultSource)) {
    throw "result example not found for case '$($manifest.case.id)': $resultSource"
}

$reviewDestination = Join-Path $repoRoot $manifest.artifacts.reviewOutputPath
$resultDestination = Join-Path $repoRoot $manifest.artifacts.resultOutputPath

Copy-Item -LiteralPath $reviewSource -Destination $reviewDestination -Force
Copy-Item -LiteralPath $resultSource -Destination $resultDestination -Force

Write-Output "Regression run hydrated from adjudicated example"
Write-Output "  Run Directory : $resolvedRunDirectory"
Write-Output "  Case ID       : $($manifest.case.id)"
Write-Output "  Review Source : $reviewSource"
Write-Output "  Result Source : $resultSource"
Write-Output ""
Write-Output "Next command:"
Write-Output "  $($manifest.commands.score)"
