param(
    [Parameter(Mandatory)]
    [string] $CasePath,

    [Parameter(Mandatory)]
    [string] $OutputPath,

    [string] $RunId
)

$ErrorActionPreference = "Stop"

function Get-JsonFile {
    param([string] $Path)

    if (-not (Test-Path -LiteralPath $Path)) {
        throw "file not found: $Path"
    }

    return Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json
}

$case = Get-JsonFile -Path $CasePath

$toolExecution = [ordered]@{}
foreach ($property in $case.expectedTools.PSObject.Properties) {
    $toolExecution[$property.Name] = ""
}

$result = [ordered]@{
    caseId = $case.id
    runId = if ([string]::IsNullOrWhiteSpace($RunId)) { [guid]::NewGuid().Guid } else { $RunId }
    timestampUtc = [DateTime]::UtcNow.ToString("o")
    task = $case.task
    model = ""
    pass = $false
    overallScore = 0
    scores = [ordered]@{
        mustCatchRecall = 0
        falsePositiveControl = 0
        severityCorrectness = 0
        scopeAndToolCorrectness = 0
        outputCompliance = 0
        determinism = 0
    }
    findings = [ordered]@{
        caught = @()
        missed = @()
        falsePositives = @()
    }
    severityChecks = [ordered]@{
        matched = 0
        total = $case.mustCatch.Count
    }
    scopeChecks = [ordered]@{
        ruleFamiliesAppliedCorrectly = $false
        toolingBehaviorCorrect = $false
    }
    toolExecution = $toolExecution
    outputChecks = [ordered]@{
        requiredSectionsPresent = $false
        requiredMarkersPresent = $false
    }
    determinismChecks = [ordered]@{
        materiallyEquivalentAcrossRuns = $false
    }
    notes = ""
}

$directory = Split-Path -Parent $OutputPath
if ($directory -and -not (Test-Path -LiteralPath $directory)) {
    New-Item -ItemType Directory -Path $directory -Force | Out-Null
}

$result | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $OutputPath

Write-Output "Created regression result template: $OutputPath"
