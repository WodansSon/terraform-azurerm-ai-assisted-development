param(
    [string[]] $Task,

    [string[]] $CaseStatus,

    [string] $CasesDirectory = (Join-Path $PSScriptRoot "cases"),

    [string] $JsonOutputPath,

    [string] $MarkdownOutputPath,

    [ValidateSet("text", "json")]
    [string] $Output = "text"
)

$ErrorActionPreference = "Stop"

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

function Initialize-Directory {
    param([string] $Path)

    if ([string]::IsNullOrWhiteSpace($Path)) {
        return
    }

    if (-not (Test-Path -LiteralPath $Path)) {
        New-Item -ItemType Directory -Path $Path -Force | Out-Null
    }
}

function Get-JsonFile {
    param([string] $Path)

    if (-not (Test-Path -LiteralPath $Path)) {
        throw "file not found: $Path"
    }

    return Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json
}

$Task = Expand-ListParameter -Value $Task
$CaseStatus = Expand-ListParameter -Value $CaseStatus

if (-not (Test-Path -LiteralPath $CasesDirectory)) {
    throw "cases directory not found: $CasesDirectory"
}

$caseFiles = @(Get-ChildItem -LiteralPath $CasesDirectory -Filter *.json | Sort-Object BaseName)
$cases = @()
foreach ($caseFile in $caseFiles) {
    $case = Get-JsonFile -Path $caseFile.FullName
    if ($Task.Count -gt 0 -and $Task -notcontains [string]$case.task) {
        continue
    }
    if ($CaseStatus.Count -gt 0 -and $CaseStatus -notcontains [string]$case.caseStatus) {
        continue
    }

    $cases += [pscustomobject]@{
        id = [string]$case.id
        title = [string]$case.title
        task = [string]$case.task
        caseStatus = [string]$case.caseStatus
        originKind = [string]$case.provenance.originKind
        originSummary = [string]$case.provenance.originSummary
        whyItMattered = [string]$case.provenance.whyItMattered
        genericCondition = [string]$case.provenance.genericCondition
        notes = [string]$case.provenance.notes
        casePath = $caseFile.FullName
    }
}

$originKindSummary = @(
    $cases |
        Group-Object -Property originKind |
        Sort-Object Name |
        ForEach-Object {
            [pscustomobject]@{
                originKind = [string]$_.Name
                caseCount = $_.Count
            }
        }
)

$taskSummary = @(
    $cases |
        Group-Object -Property task |
        Sort-Object Name |
        ForEach-Object {
            [pscustomobject]@{
                task = [string]$_.Name
                caseCount = $_.Count
            }
        }
)

$report = [ordered]@{
    generatedUtc = [DateTime]::UtcNow.ToString("o")
    filters = [ordered]@{
        task = @($Task)
        caseStatus = @($CaseStatus)
    }
    summary = [ordered]@{
        caseCount = $cases.Count
        originKinds = $originKindSummary
        tasks = $taskSummary
    }
    cases = @($cases)
}

if (-not [string]::IsNullOrWhiteSpace($JsonOutputPath)) {
    $jsonDirectory = Split-Path -Parent $JsonOutputPath
    Initialize-Directory -Path $jsonDirectory
    $report | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $JsonOutputPath
}

if (-not [string]::IsNullOrWhiteSpace($MarkdownOutputPath)) {
    $markdownDirectory = Split-Path -Parent $MarkdownOutputPath
    Initialize-Directory -Path $markdownDirectory

    $markdownLines = @(
        '# Regression Provenance Report',
        '',
        ('Generated: {0}' -f $report.generatedUtc),
        '',
        '## Summary',
        '',
        ('- Cases: {0}' -f $report.summary.caseCount),
        ('- Task Filter: {0}' -f $(if ($Task.Count -gt 0) { $Task -join ', ' } else { 'all' })),
        ('- Status Filter: {0}' -f $(if ($CaseStatus.Count -gt 0) { $CaseStatus -join ', ' } else { 'all' })),
        '',
        '## Origin Kinds',
        ''
    )

    foreach ($origin in $report.summary.originKinds) {
        $markdownLines += ('- `{0}`: {1}' -f $origin.originKind, $origin.caseCount)
    }

    $markdownLines += @(
        '',
        '## Cases',
        ''
    )

    foreach ($case in $report.cases) {
        $markdownLines += @(
            ('### {0}' -f $case.id),
            '',
            ('- Title: {0}' -f $case.title),
            ('- Task: `{0}`' -f $case.task),
            ('- Status: `{0}`' -f $case.caseStatus),
            ('- Origin Kind: `{0}`' -f $case.originKind),
            ('- Origin Summary: {0}' -f $case.originSummary),
            ('- Why It Mattered: {0}' -f $case.whyItMattered),
            ('- Generic Condition: {0}' -f $case.genericCondition)
        )

        if (-not [string]::IsNullOrWhiteSpace($case.notes)) {
            $markdownLines += ('- Notes: {0}' -f $case.notes)
        }

        $markdownLines += ''
    }

    $markdownLines | Set-Content -LiteralPath $MarkdownOutputPath
}

if ($Output -eq 'json') {
    $report | ConvertTo-Json -Depth 20
    return
}

Write-Output 'Regression provenance report generated'
Write-Output "  Cases Included   : $($report.summary.caseCount)"
if (-not [string]::IsNullOrWhiteSpace($JsonOutputPath)) {
    Write-Output "  JSON Output      : $JsonOutputPath"
}
if (-not [string]::IsNullOrWhiteSpace($MarkdownOutputPath)) {
    Write-Output "  Markdown Output  : $MarkdownOutputPath"
}
