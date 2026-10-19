Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$arguments = @($args)
$modelIndex = [Array]::IndexOf($arguments, '--model')
$effortIndex = [Array]::IndexOf($arguments, '--reasoning-effort')
$toolsIndex = [Array]::IndexOf($arguments, '--available-tools')
if ($modelIndex -lt 0 -or $effortIndex -lt 0 -or $toolsIndex -lt 0 -or $arguments[$toolsIndex + 1] -cne '--output-format' -or '-p' -cin $arguments) {
    throw 'Assistance CLI arguments did not preserve the inline no-tools boundary'
}
$prompt = [Console]::In.ReadToEnd()
$marker = "`n## Supplied Context`n"
$offset = $prompt.LastIndexOf($marker, [StringComparison]::Ordinal)
if ($offset -lt 0 -or -not $prompt.Contains('## Boundaries', [StringComparison]::Ordinal)) { throw 'Assistance prompt boundaries are missing' }
$context = $prompt.Substring($offset + $marker.Length) | ConvertFrom-Json -Depth 100
$question = [string]$context.messages[-1].content
$control = [Environment]::GetEnvironmentVariable('HOSTED_ASSISTANCE_TEST_CONTROL')
if ([string]::IsNullOrWhiteSpace($control)) { throw 'Synthetic assistance requires an isolated test control directory' }
$metrics = [ordered]@{
    model = $arguments[$modelIndex + 1]; effort = $arguments[$effortIndex + 1]
    bytes = [Text.Encoding]::UTF8.GetByteCount($prompt)
    ruleIds = @($context.catalog.id); messageCount = @($context.messages).Count
    sourceCount = @($context.sources).Count; workingDirectory = (Get-Location).Path
}
[IO.File]::AppendAllText((Join-Path $control 'metrics.jsonl'), (($metrics | ConvertTo-Json -Compress) + "`n"))
if ($question -ceq 'hold') {
    $childInfo = [Diagnostics.ProcessStartInfo]::new('pwsh')
    $childInfo.UseShellExecute = $false
    foreach ($argument in @('-NoProfile', '-NonInteractive', '-Command', 'Start-Sleep -Seconds 120')) { $childInfo.ArgumentList.Add($argument) }
    $child = [Diagnostics.Process]::Start($childInfo)
    try {
        [IO.File]::WriteAllText((Join-Path $control 'held.json'), (@{ worker = $PID; child = $child.Id; directory = (Get-Location).Path } | ConvertTo-Json -Compress))
        while (-not (Test-Path -LiteralPath (Join-Path $control 'release'))) { Start-Sleep -Milliseconds 25 }
    }
    finally {
        if (-not $child.HasExited) { $child.Kill($true); $child.WaitForExit() }
        $child.Dispose()
    }
}
if ($question -ceq 'cli-failure') { throw 'Synthetic CLI failure' }
if ($question -ceq 'warning') { [Console]::Error.WriteLine('Synthetic legitimate warning; stdout remains JSONL.') }
if ($question -ceq 'tool-event') { '{"type":"tool.execution_start","data":{}}' }
$answer = [ordered]@{ message = 'Synthetic catalog advice <img src=x onerror=alert(1)>.'; suggestedWording = 'Preserve the selected rule obligations and review the complete proposed wording.' }
if ($question -ceq 'invalid-shape') { $answer.Remove('message') }
$event = [ordered]@{ type = 'assistant.message'; data = [ordered]@{
    model = if ($question -ceq 'wrong-model') { 'unexpected-model' } else { $arguments[$modelIndex + 1] }
    content = $answer | ConvertTo-Json -Compress
} } | ConvertTo-Json -Depth 100 -Compress
$event
if ($question -ceq 'multiple-answers') { $event }
