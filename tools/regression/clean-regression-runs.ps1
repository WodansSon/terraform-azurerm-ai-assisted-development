[CmdletBinding(SupportsShouldProcess)]
param(
    [string] $RunId,

    [switch] $Latest,

    [switch] $All,

    [string] $RunsDirectory = (Join-Path $PSScriptRoot "runs")
)

$ErrorActionPreference = "Stop"

$selectedModeCount = 0
if ($Latest) {
    $selectedModeCount++
}
if ($All) {
    $selectedModeCount++
}
if (-not [string]::IsNullOrWhiteSpace($RunId)) {
    $selectedModeCount++
}

if ($selectedModeCount -ne 1) {
    throw "specify exactly one of -RunId, -Latest, or -All"
}

if (-not (Test-Path -LiteralPath $RunsDirectory)) {
    Write-Output "No regression runs directory found: $RunsDirectory"
    return
}

$targets = @()

if ($All) {
    $targets = @(Get-ChildItem -LiteralPath $RunsDirectory -Directory)
}
elseif ($Latest) {
    $latestRun = Get-ChildItem -LiteralPath $RunsDirectory -Directory | Sort-Object Name -Descending | Select-Object -First 1
    if ($latestRun) {
        $targets = @($latestRun)
    }
}
else {
    $explicitTarget = Get-ChildItem -LiteralPath $RunsDirectory -Directory | Where-Object { $_.Name -eq $RunId }
    if ($explicitTarget) {
        $targets = @($explicitTarget)
    }
}

if ($targets.Count -eq 0) {
    Write-Output "No matching regression run directories found."
    return
}

foreach ($target in $targets) {
    if ($PSCmdlet.ShouldProcess($target.FullName, "Remove regression run directory")) {
        Remove-Item -LiteralPath $target.FullName -Recurse -Force
        Write-Output "Removed: $($target.FullName)"
    }
}
