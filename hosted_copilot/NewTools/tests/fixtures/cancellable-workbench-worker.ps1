[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$MarkerPath,
    [Parameter(Mandatory = $true)][string]$OutputPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$startInfo = [Diagnostics.ProcessStartInfo]::new('pwsh')
$startInfo.UseShellExecute = $false
$startInfo.CreateNoWindow = $true
foreach ($argument in @('-NoProfile', '-NonInteractive', '-Command', 'Start-Sleep -Seconds 45')) {
    $startInfo.ArgumentList.Add($argument)
}
$child = [Diagnostics.Process]::Start($startInfo)
try {
    [IO.File]::WriteAllText("$MarkerPath.tmp", (@{ worker = $PID; child = $child.Id } | ConvertTo-Json -Compress))
    [IO.File]::Move("$MarkerPath.tmp", $MarkerPath)
    Start-Sleep -Seconds 30
    [IO.File]::WriteAllText($OutputPath, '{"unexpectedCompletion":true}')
}
finally {
    if (-not $child.HasExited) {
        $child.Kill($true)
        $child.WaitForExit()
    }
    $child.Dispose()
}
