[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$PayloadPath,
    [Parameter(Mandatory = $true)][string]$SchemaPath,
    [Parameter(Mandatory = $true)][string]$PromptPath,
    [Parameter(Mandatory = $true)][string]$OutputPath,
    [Parameter(Mandatory = $true)][string]$Model,
    [Parameter(Mandatory = $true)][string]$ReasoningEffort
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$controlDirectory = $env:HOSTED_WORKBENCH_TEST_CONTROL_DIRECTORY
if ([string]::IsNullOrWhiteSpace($controlDirectory) -or -not (Test-Path -LiteralPath $controlDirectory -PathType Container)) {
    throw 'Held evaluator requires its dedicated test control directory'
}
$payload = Get-Content -LiteralPath $PayloadPath -Raw | ConvertFrom-Json
$markerPath = Join-Path $controlDirectory "started-$($payload.ruleTextSha256).json"
$releasePath = Join-Path $controlDirectory 'release'
$child = $null
try {
    if (-not (Test-Path -LiteralPath $releasePath)) {
        $startInfo = [Diagnostics.ProcessStartInfo]::new('pwsh')
        $startInfo.UseShellExecute = $false
        $startInfo.CreateNoWindow = $true
        foreach ($argument in @('-NoProfile', '-NonInteractive', '-Command', 'Start-Sleep -Seconds 60')) {
            $startInfo.ArgumentList.Add($argument)
        }
        $child = [Diagnostics.Process]::Start($startInfo)
    }
    [IO.File]::WriteAllText("$markerPath.tmp", (@{
        worker = $PID
        child = if ($null -ne $child) { $child.Id } else { $null }
        model = $Model
        effort = $ReasoningEffort
    } | ConvertTo-Json -Compress))
    [IO.File]::Move("$markerPath.tmp", $markerPath, $true)
    $deadline = [DateTimeOffset]::UtcNow.AddSeconds(45)
    while (-not (Test-Path -LiteralPath $releasePath)) {
        if ([DateTimeOffset]::UtcNow -gt $deadline) { throw 'Held evaluator was not released by its test' }
        Start-Sleep -Milliseconds 25
    }
    & (Join-Path $PSScriptRoot 'manual-relationship-evaluator.ps1') @PSBoundParameters
}
finally {
    if ($null -ne $child) {
        if (-not $child.HasExited) { $child.Kill($true); $child.WaitForExit() }
        $child.Dispose()
    }
}
