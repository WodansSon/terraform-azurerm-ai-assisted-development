[CmdletBinding()]
param(
    [ValidateSet('Text', 'Json')]
    [string]$OutputFormat = 'Text',

    [string]$ArchitecturePath,

    [ValidateRange(1, 1000)]
    [int]$ExpectedWidth = 68
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$validationOutputModulePath = Join-Path $PSScriptRoot 'ValidationOutput.psm1'
Import-Module -Name $validationOutputModulePath -Force

$repoRoot = Split-Path -Parent $PSScriptRoot
if ([string]::IsNullOrWhiteSpace($ArchitecturePath)) {
    $ArchitecturePath = Join-Path $repoRoot 'docs/ARCHITECTURE.md'
}
elseif (-not [System.IO.Path]::IsPathRooted($ArchitecturePath)) {
    $ArchitecturePath = Join-Path $repoRoot $ArchitecturePath
}

if (-not (Test-Path -LiteralPath $ArchitecturePath)) {
    throw "architecture document was not found at $ArchitecturePath"
}

$lines = Get-Content -LiteralPath $ArchitecturePath
$issues = New-Object 'System.Collections.Generic.List[string]'
$heading = '## System Architecture'
$headingIndex = [Array]::IndexOf($lines, $heading)
$fenceStart = -1
$fenceEnd = -1
$validatedRowCount = 0

if ($headingIndex -lt 0) {
    $issues.Add("Missing required heading ``$heading``")
}
else {
    for ($i = $headingIndex + 1; $i -lt $lines.Count; $i++) {
        if ($lines[$i] -eq '```') {
            $fenceStart = $i
            break
        }
    }

    if ($fenceStart -lt 0) {
        $issues.Add("Missing opening code fence after ``$heading``")
    }
    else {
        for ($i = $fenceStart + 1; $i -lt $lines.Count; $i++) {
            if ($lines[$i] -eq '```') {
                $fenceEnd = $i
                break
            }
        }

        if ($fenceEnd -lt 0) {
            $issues.Add("Missing closing code fence for ``$heading``")
        }
    }
}

if ($fenceStart -ge 0 -and $fenceEnd -ge 0) {
    for ($i = $fenceStart + 1; $i -lt $fenceEnd; $i++) {
        $line = $lines[$i]
        if ([string]::IsNullOrWhiteSpace($line)) {
            continue
        }

        $validatedRowCount++
        $lineNumber = $i + 1
        $displayWidth = [System.Globalization.StringInfo]::ParseCombiningCharacters($line).Count

        if ($displayWidth -ne $ExpectedWidth) {
            $issues.Add(("Line {0}: expected width {1}, found {2}: {3}" -f $lineNumber, $ExpectedWidth, $displayWidth, $line))
        }

        if ($line -notmatch '[┐│┘]$') {
            $issues.Add(("Line {0}: missing aligned right-edge border: {1}" -f $lineNumber, $line))
        }

        if ($line -match '[^\s│]│') {
            $issues.Add(("Line {0}: content must have at least one padding space before a vertical border: {1}" -f $lineNumber, $line))
        }
    }
}

$result = [ordered]@{
    status = if ($issues.Count -eq 0) { 'passed' } else { 'failed' }
    architecturePath = $ArchitecturePath
    heading = $heading
    expectedWidth = $ExpectedWidth
    validatedRowCount = $validatedRowCount
    issueCount = $issues.Count
    issues = @($issues)
}

if ($OutputFormat -eq 'Json') {
    $result | ConvertTo-Json -Depth 8
}
else {
    Write-ValidationSectionHeader -Title 'Architecture layout validation summary'
    Write-ValidationSummary -Fields ([ordered]@{
        Status = $result.status.ToUpperInvariant()
        'Architecture Path' = $result.architecturePath
        'Expected Row Width' = $result.expectedWidth
        'Validated Rows' = $result.validatedRowCount
        'Issue Count' = $result.issueCount
    })

    if ($issues.Count -gt 0) {
        Write-ValidationSectionHeader -Title 'Issues'
        foreach ($issue in $issues) {
            Write-Output ("  - {0}" -f $issue)
        }
    }
    Complete-ValidationTextOutput
}

if ($issues.Count -gt 0) {
    exit 1
}
