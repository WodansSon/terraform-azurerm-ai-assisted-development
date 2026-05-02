param(
    [string] $Case,

    [string] $CasePath,

    [string] $ResultPath,

    [string] $ReviewPath,

    [switch] $ShowFixture,

    [switch] $ShowReview
)

$ErrorActionPreference = "Stop"

function Show-Usage {
    param([string[]] $AvailableCases)

    Write-Output "Usage: pwsh -NoProfile -File ./tools/regression/run-regression-example.ps1 -Case <case-id> [-ShowFixture] [-ShowReview]"
    Write-Output "   or: pwsh -NoProfile -File ./tools/regression/run-regression-example.ps1 -CasePath <case.json> [-ShowFixture] [-ShowReview]"
    Write-Output ""
    Write-Output "Available case aliases:"

    foreach ($case in $AvailableCases) {
        Write-Output "  - $case"
    }
}

function Get-JsonFile {
    param([string] $Path)

    if (-not (Test-Path -LiteralPath $Path)) {
        throw "file not found: $Path"
    }

    return Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json
}

function Resolve-DefaultArtifactPath {
    param(
        [string] $BaseDirectory,
        [string] $CaseId,
        [string] $Extension
    )

    $candidate = Join-Path $BaseDirectory ($CaseId + $Extension)
    if (Test-Path -LiteralPath $candidate) {
        return $candidate
    }

    return $null
}

function Resolve-CaseFile {
    param(
        [string] $Case,
        [string] $CasePath,
        [string] $CasesDirectory,
        [string] $RepoRoot
    )

    $availableCaseFiles = @()
    if (Test-Path -LiteralPath $CasesDirectory) {
        $availableCaseFiles = @(Get-ChildItem -LiteralPath $CasesDirectory -Filter *.json | Sort-Object BaseName)
    }

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

$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$casesDirectory = Join-Path $PSScriptRoot "cases"
$resolvedCasePath = Resolve-CaseFile -Case $Case -CasePath $CasePath -CasesDirectory $casesDirectory -RepoRoot $repoRoot
$caseDefinition = Get-JsonFile -Path $resolvedCasePath

if (-not $ResultPath) {
    $ResultPath = Resolve-DefaultArtifactPath -BaseDirectory (Join-Path $PSScriptRoot "examples") -CaseId $caseDefinition.id -Extension ".result.json"
}

if (-not $ReviewPath) {
    $ReviewPath = Resolve-DefaultArtifactPath -BaseDirectory (Join-Path $PSScriptRoot "examples") -CaseId $caseDefinition.id -Extension ".review.md"
}

Write-Output "Regression example"
Write-Output "  Case ID    : $($caseDefinition.id)"
Write-Output "  Task       : $($caseDefinition.task)"
Write-Output "  Status     : $($caseDefinition.caseStatus)"
Write-Output "  Case Path  : $resolvedCasePath"

if ($caseDefinition.fixture.mode -ne "none" -and $caseDefinition.fixture.path) {
    $fixturePath = Join-Path $repoRoot $caseDefinition.fixture.path
    Write-Output "  Fixture    : $fixturePath"
    if ($ShowFixture -and (Test-Path -LiteralPath $fixturePath)) {
        Write-Output ""
        Write-Output "--- Fixture Preview ---"
        Get-Content -LiteralPath $fixturePath
        Write-Output ""
    }
}

if ($ReviewPath) {
    Write-Output "  Review     : $ReviewPath"
    if ($ShowReview -and (Test-Path -LiteralPath $ReviewPath)) {
        Write-Output ""
        Write-Output "--- Review Preview ---"
        Get-Content -LiteralPath $ReviewPath
        Write-Output ""
    }
}

if ($ResultPath) {
    Write-Output "  Result     : $ResultPath"
    Write-Output ""
    & pwsh -NoProfile -File (Join-Path $PSScriptRoot "score-regression-case.ps1") -CasePath $resolvedCasePath -ResultPath $ResultPath
}
else {
    Write-Output "  Result     : not found"
}
