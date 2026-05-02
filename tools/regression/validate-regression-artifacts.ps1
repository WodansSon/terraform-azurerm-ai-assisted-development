param(
    [string[]] $CasePath,

    [string[]] $ResultPath,

    [string] $CasesDirectory = (Join-Path $PSScriptRoot "cases"),

    [string] $ExamplesDirectory = (Join-Path $PSScriptRoot "examples"),

    [string] $CaseSchemaPath = (Join-Path $PSScriptRoot "schema/review-case.schema.json"),

    [string] $ResultSchemaPath = (Join-Path $PSScriptRoot "schema/review-result.schema.json"),

    [ValidateSet("text", "json")]
    [string] $Output = "text",

    [switch] $AsJson
)

$ErrorActionPreference = "Stop"

if ($AsJson) {
    $Output = "json"
}

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

function Resolve-ArtifactPaths {
    param(
        [string[]] $ExplicitPaths,
        [string] $DefaultDirectory,
        [string] $Filter
    )

    if ($ExplicitPaths.Count -gt 0) {
        return @($ExplicitPaths | ForEach-Object { (Resolve-Path -LiteralPath $_).Path } | Select-Object -Unique)
    }

    if (-not (Test-Path -LiteralPath $DefaultDirectory)) {
        return @()
    }

    return @(Get-ChildItem -LiteralPath $DefaultDirectory -Filter $Filter | Sort-Object Name | ForEach-Object { $_.FullName })
}

function Get-JsonFile {
    param([string] $Path)

    if (-not (Test-Path -LiteralPath $Path)) {
        throw "file not found: $Path"
    }

    return Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json
}

function Test-JsonSchemaFile {
    param(
        [string] $Path,
        [string] $SchemaPath,
        [string] $Kind
    )

    $content = Get-Content -LiteralPath $Path -Raw
    $isValid = $content | Test-Json -SchemaFile $SchemaPath
    if (-not $isValid) {
        throw "$Kind schema validation failed: $Path"
    }
}

$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$CasePath = Expand-ListParameter -Value $CasePath
$ResultPath = Expand-ListParameter -Value $ResultPath

$resolvedCasePaths = Resolve-ArtifactPaths -ExplicitPaths $CasePath -DefaultDirectory $CasesDirectory -Filter *.json
$resolvedResultPaths = Resolve-ArtifactPaths -ExplicitPaths $ResultPath -DefaultDirectory $ExamplesDirectory -Filter *.result.json

$validatedCases = @{}
$validatedResults = @()

foreach ($casePathItem in $resolvedCasePaths) {
    Test-JsonSchemaFile -Path $casePathItem -SchemaPath $CaseSchemaPath -Kind "case file"
    $case = Get-JsonFile -Path $casePathItem

    if ($validatedCases.ContainsKey($case.id)) {
        throw "duplicate case id '$($case.id)' found in '$casePathItem'"
    }

    if ($case.fixture.mode -ne "none" -and [string]::IsNullOrWhiteSpace($case.fixture.path)) {
        throw "case file '$casePathItem' requires fixture.path when fixture.mode is '$($case.fixture.mode)'"
    }

    if (-not [string]::IsNullOrWhiteSpace($case.fixture.path)) {
        $fixtureAbsolutePath = Join-Path $repoRoot $case.fixture.path
        if (-not (Test-Path -LiteralPath $fixtureAbsolutePath)) {
            throw "fixture path not found for case '$($case.id)': $fixtureAbsolutePath"
        }
    }

    $validatedCases[$case.id] = [pscustomobject]@{
        definition = $case
        path = $casePathItem
    }
}

foreach ($resultPathItem in $resolvedResultPaths) {
    Test-JsonSchemaFile -Path $resultPathItem -SchemaPath $ResultSchemaPath -Kind "result file"
    $result = Get-JsonFile -Path $resultPathItem

    if (-not $validatedCases.ContainsKey($result.caseId)) {
        throw "result file '$resultPathItem' references unknown case id '$($result.caseId)'"
    }

    $matchingCase = $validatedCases[$result.caseId].definition
    if ($matchingCase.task -ne $result.task) {
        throw "result file '$resultPathItem' task '$($result.task)' does not match case '$($matchingCase.id)' task '$($matchingCase.task)'"
    }

    $validatedResults += [pscustomobject]@{
        caseId = $result.caseId
        path = $resultPathItem
    }
}

$summary = [ordered]@{
    caseFileCount = $resolvedCasePaths.Count
    resultFileCount = $resolvedResultPaths.Count
    validatedCaseIds = @($validatedCases.Keys | Sort-Object)
    validatedResultCaseIds = @($validatedResults | ForEach-Object { $_.caseId } | Sort-Object -Unique)
}

if ($Output -eq "json") {
    $summary | ConvertTo-Json -Depth 10
    return
}

Write-Output "Regression artifact validation summary"
Write-Output "  Case Files       : $($summary.caseFileCount)"
Write-Output "  Result Files     : $($summary.resultFileCount)"
Write-Output "  Validated Cases  : $(if ($summary.validatedCaseIds.Count -gt 0) { $summary.validatedCaseIds -join ', ' } else { 'none' })"
Write-Output "  Validated Results: $(if ($summary.validatedResultCaseIds.Count -gt 0) { $summary.validatedResultCaseIds -join ', ' } else { 'none' })"
