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

function Get-CaseStringValues {
    param(
        $Node,
        [string] $Path = '',
        [switch] $SkipProvenance
    )

    $values = @()

    if ($null -eq $Node) {
        return @()
    }

    if ($SkipProvenance -and $Path -like 'provenance*') {
        return @()
    }

    if ($Node -is [string]) {
        return @([pscustomobject]@{ path = $Path; value = $Node })
    }

    if ($Node -is [System.Collections.IDictionary]) {
        foreach ($key in $Node.Keys) {
            $childPath = if ([string]::IsNullOrWhiteSpace($Path)) { [string]$key } else { "$Path.$key" }
            $values += @(Get-CaseStringValues -Node $Node[$key] -Path $childPath -SkipProvenance:$SkipProvenance)
        }
        return @($values)
    }

    if ($Node -is [System.Collections.IEnumerable] -and -not ($Node -is [string])) {
        $index = 0
        foreach ($item in $Node) {
            $childPath = "${Path}[$index]"
            $values += @(Get-CaseStringValues -Node $item -Path $childPath -SkipProvenance:$SkipProvenance)
            $index++
        }
        return @($values)
    }

    foreach ($property in $Node.PSObject.Properties) {
        $childPath = if ([string]::IsNullOrWhiteSpace($Path)) { $property.Name } else { "$Path.$($property.Name)" }
        $values += @(Get-CaseStringValues -Node $property.Value -Path $childPath -SkipProvenance:$SkipProvenance)
    }

    return @($values)
}

function Assert-NoForbiddenSyntheticAnchors {
    param(
        [string] $Content,
        [string] $ArtifactPath,
        [string] $ArtifactKind
    )

    $forbiddenPatterns = @(
        [pscustomobject]@{ label = 'non-example service path'; regex = 'internal/services/(?!example/)[a-z0-9_-]+/' },
        [pscustomobject]@{ label = 'non-example resource doc path'; regex = 'website/docs/r/(?!example_)[a-z0-9_-]+\.html\.markdown' },
        [pscustomobject]@{ label = 'non-example guide path'; regex = 'website/docs/guides/(?!example-)[a-z0-9._-]+\.html\.markdown' },
        [pscustomobject]@{ label = 'non-example Terraform resource type'; regex = 'azurerm_(?!example_)[a-z0-9_]+' },
        [pscustomobject]@{ label = 'service-specific Front Door anchor'; regex = 'Front Door|AzureFrontDoor|cdn_frontdoor_' },
        [pscustomobject]@{ label = 'historical reference'; regex = '(?i)\bhistorical\b|derived from a real|live PR identity|live upstream file contents|retaining live PR identity|real PR|real review|real docs-review|real committed-review|real local review|real implementation-guidance|real contributor-guidance|real mixed committed-review|real false-positive class|real docs-remediation|real new-resource|real prompt or skill run' },
        [pscustomobject]@{ label = 'PR number reference'; regex = '(?i)\bPR\s*#\d+\b|\bpull request\s*#\d+\b|\bupstream PR\s*#\d+\b' }
    )

    foreach ($pattern in $forbiddenPatterns) {
        if ($Content -match $pattern.regex) {
            throw "$ArtifactKind contains forbidden synthetic anchor '$($pattern.label)' in '$ArtifactPath'"
        }
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

    if ($case.sourceKind -ne 'synthetic') {
        throw "case file '$casePathItem' must use sourceKind 'synthetic'"
    }

    if (-not $case.sanitized) {
        throw "case file '$casePathItem' must remain sanitized"
    }

    $caseStrings = @(Get-CaseStringValues -Node $case -SkipProvenance)
    foreach ($stringValue in $caseStrings) {
        Assert-NoForbiddenSyntheticAnchors -Content $stringValue.value -ArtifactPath "$casePathItem::$($stringValue.path)" -ArtifactKind 'case file'
    }

    if ($case.fixture.mode -ne "none" -and [string]::IsNullOrWhiteSpace($case.fixture.path)) {
        throw "case file '$casePathItem' requires fixture.path when fixture.mode is '$($case.fixture.mode)'"
    }

    if (-not [string]::IsNullOrWhiteSpace($case.fixture.path)) {
        $fixtureAbsolutePath = Join-Path $repoRoot $case.fixture.path
        if (-not (Test-Path -LiteralPath $fixtureAbsolutePath)) {
            throw "fixture path not found for case '$($case.id)': $fixtureAbsolutePath"
        }

        $fixtureContent = Get-Content -LiteralPath $fixtureAbsolutePath -Raw
        Assert-NoForbiddenSyntheticAnchors -Content $fixtureContent -ArtifactPath $fixtureAbsolutePath -ArtifactKind 'fixture file'

        $reviewExamplePath = Join-Path $ExamplesDirectory ($case.id + '.review.md')
        if (Test-Path -LiteralPath $reviewExamplePath) {
            $reviewContent = Get-Content -LiteralPath $reviewExamplePath -Raw
            Assert-NoForbiddenSyntheticAnchors -Content $reviewContent -ArtifactPath $reviewExamplePath -ArtifactKind 'review example'
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

    $resultContent = Get-Content -LiteralPath $resultPathItem -Raw
    Assert-NoForbiddenSyntheticAnchors -Content $resultContent -ArtifactPath $resultPathItem -ArtifactKind 'result file'

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
