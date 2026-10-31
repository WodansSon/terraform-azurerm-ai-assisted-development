Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$null = [Console]::In.ReadToEnd()
$mode = [Environment]::GetEnvironmentVariable('HOSTED_RELATIONSHIP_FIXTURE_MODE')
$content = if ($mode -ceq 'invalid') { '{"findings":[],"operations":[]}' } else { '{"findings":[]}' }
if ($mode -ceq 'tools') { Write-Output '{"type":"tool.execution_start","data":{}}' }
Write-Output '{"type":"model.call_start","data":{}}'
Write-Output (([ordered]@{ type = 'assistant.message'; data = @{ model = 'gpt-6-luna'; content = $content } }) | ConvertTo-Json -Compress)
Write-Output '{"type":"assistant.turn_end","data":{}}'
Write-Output '{"type":"result","data":{}}'
