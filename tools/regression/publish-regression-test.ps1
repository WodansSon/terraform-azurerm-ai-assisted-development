param(
    [string] $CaseId,

    [string] $SpecPath,

    [string] $CasePath,

    [string] $ResultPath,

    [string] $ReviewPath,

    [ValidateSet("ready", "adjudicated")]
    [string] $TargetStatus = "adjudicated",

    [switch] $Force,

    [string] $CasesDirectory = (Join-Path $PSScriptRoot "cases"),

    [string] $ExamplesDirectory = (Join-Path $PSScriptRoot "examples"),

    [string] $ResultsDirectory = (Join-Path $PSScriptRoot "results")
)

$ErrorActionPreference = "Stop"

function Get-JsonFile {
    param([string] $Path)

    if (-not (Test-Path -LiteralPath $Path)) {
        throw "file not found: $Path"
    }

    return Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json
}

function Resolve-CasePath {
    param(
        [string] $CaseId,
        [string] $SpecPath,
        [string] $CasePath,
        [string] $CasesDirectory
    )

    if ([string]::IsNullOrWhiteSpace($CaseId) -and [string]::IsNullOrWhiteSpace($CasePath) -and [string]::IsNullOrWhiteSpace($SpecPath)) {
        throw "specify -CaseId, -SpecPath, or -CasePath"
    }

    if (-not [string]::IsNullOrWhiteSpace($CasePath)) {
        return (Resolve-Path -LiteralPath $CasePath).Path
    }

    if (-not [string]::IsNullOrWhiteSpace($SpecPath)) {
        if (-not (Test-Path -LiteralPath $SpecPath)) {
            throw "file not found: $SpecPath"
        }

        $specRoot = Select-String -Path $SpecPath -Pattern '^\s*AccTest\s+"([a-zA-Z0-9-]+)"\s+"([a-zA-Z0-9_-]+)"\s*\{' | Select-Object -First 1
        if ($null -eq $specRoot) {
            throw "could not resolve test id from spec: $SpecPath"
        }

        $CaseId = $specRoot.Matches[0].Groups[1].Value
    }

    return (Resolve-Path -LiteralPath (Join-Path $CasesDirectory ($CaseId + ".json"))).Path
}

function Assert-CanWriteFile {
    param(
        [string] $Path,
        [switch] $Force
    )

    if ((Test-Path -LiteralPath $Path) -and -not $Force) {
        throw "target already exists: $Path"
    }
}

$resolvedCasePath = Resolve-CasePath -CaseId $CaseId -SpecPath $SpecPath -CasePath $CasePath -CasesDirectory $CasesDirectory
$case = Get-JsonFile -Path $resolvedCasePath

if ([string]::IsNullOrWhiteSpace($ResultPath)) {
    $ResultPath = Join-Path $ResultsDirectory ($case.id + ".result.json")
}

if ([string]::IsNullOrWhiteSpace($ReviewPath)) {
    $candidateReviewPath = Join-Path $ResultsDirectory ($case.id + ".review.md")
    if (Test-Path -LiteralPath $candidateReviewPath) {
        $ReviewPath = $candidateReviewPath
    }
}

$exampleResultPath = Join-Path $ExamplesDirectory ($case.id + ".result.json")
$exampleReviewPath = Join-Path $ExamplesDirectory ($case.id + ".review.md")

Assert-CanWriteFile -Path $exampleResultPath -Force:$Force
if (-not [string]::IsNullOrWhiteSpace($ReviewPath)) {
    Assert-CanWriteFile -Path $exampleReviewPath -Force:$Force
}

Copy-Item -LiteralPath $ResultPath -Destination $exampleResultPath -Force
if (-not [string]::IsNullOrWhiteSpace($ReviewPath)) {
    Copy-Item -LiteralPath $ReviewPath -Destination $exampleReviewPath -Force
}

$updatedCase = [ordered]@{}
foreach ($property in $case.PSObject.Properties) {
    $updatedCase[$property.Name] = $property.Value
}
$updatedCase.caseStatus = $TargetStatus

$updatedCase | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $resolvedCasePath

& pwsh -NoProfile -File (Join-Path $PSScriptRoot "validate-regression-artifacts.ps1") -CasePath $resolvedCasePath -ResultPath $exampleResultPath | Out-Null

Write-Output "Regression test published"
Write-Output "  Case File        : $resolvedCasePath"
Write-Output "  Result Example   : $exampleResultPath"
if (-not [string]::IsNullOrWhiteSpace($ReviewPath)) {
    Write-Output "  Review Example   : $exampleReviewPath"
}
Write-Output "  Updated Status   : $TargetStatus"
