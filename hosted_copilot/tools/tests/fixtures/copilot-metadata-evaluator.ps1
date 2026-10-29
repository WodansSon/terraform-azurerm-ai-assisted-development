Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ('--headless' -cnotin @($args) -or '--stdio' -cnotin @($args) -or '--no-auto-update' -cnotin @($args)) {
    throw 'Synthetic metadata CLI requires headless stdio and the bundled-version policy; inference is forbidden'
}
$scenario = [Environment]::GetEnvironmentVariable('HOSTED_CLI_TEST_SCENARIO')
if ($scenario -ceq 'timeout') { $null = [Console]::In.ReadToEnd(); return }
$configuration = Get-Content -LiteralPath (Join-Path $PSScriptRoot '../../config/llm.json') -Raw | ConvertFrom-Json -DateKind String
$inputStream = [Console]::OpenStandardInput()
$outputStream = [Console]::OpenStandardOutput()
while ($true) {
    $first = $inputStream.ReadByte()
    if ($first -lt 0) { break }
    $header = [Text.StringBuilder]::new()
    [void]$header.Append([char]$first)
    while (-not $header.ToString().EndsWith("`r`n`r`n", [StringComparison]::Ordinal)) {
        if ($header.Length -ge 8192) { throw 'Synthetic metadata header exceeded its bound' }
        $next = $inputStream.ReadByte()
        if ($next -lt 0) { throw 'Synthetic metadata input ended inside its header' }
        [void]$header.Append([char]$next)
    }
    if ($header.ToString() -notmatch '(?im)^Content-Length:\s*(\d+)\s*$') { throw 'Synthetic metadata framing is invalid' }
    $length = [int]$Matches[1]
    if ($length -lt 2 -or $length -gt 4096) { throw 'Synthetic metadata request exceeded its bound' }
    $body = [byte[]]::new($length)
    $offset = 0
    while ($offset -lt $length) {
        $count = $inputStream.Read($body, $offset, $length - $offset)
        if ($count -eq 0) { throw 'Synthetic metadata input ended inside its body' }
        $offset += $count
    }
    $request = [Text.Encoding]::UTF8.GetString($body) | ConvertFrom-Json
    $result = switch -CaseSensitive ($request.method) {
        'status.get' { @{ version = '1.0.102'; protocolVersion = $(if ($scenario -ceq 'unsupported-protocol') { 2 } else { 3 }) } }
        'auth.getStatus' { @{ isAuthenticated = $scenario -cne 'unauthenticated' } }
        'models.list' {
            $models = @($configuration.normal.model, $configuration.savedRuleEvaluation.model, 'fixture-normal-model', 'fixture-saved-model' | Select-Object -Unique | ForEach-Object {
                $model = [string]$_
                if ($scenario -ceq 'missing-model' -and $model -ceq $configuration.normal.model) { return }
                [ordered]@{
                    id = $model; name = $model
                    policy = @{ state = $(if ($scenario -ceq 'disabled-model') { 'disabled' } elseif ($scenario -ceq 'unknown-policy') { 'unconfigured' } else { 'enabled' }); terms = 'Synthetic policy' }
                    capabilities = @{ supports = @{ reasoningEffort = $true; vision = $false }; limits = @{ max_context_window_tokens = 128000 } }
                    supportedReasoningEfforts = $(if ($scenario -ceq 'unsupported-effort') { @('low') } else { @('low', 'medium', 'high', 'xhigh') })
                }
            })
            if ($scenario -ceq 'duplicate-model') { $models += $models[0] }
            @{ models = $models }
        }
        default { throw 'Synthetic metadata CLI forbids non-metadata RPC methods' }
    }
    $response = [ordered]@{ jsonrpc = '2.0'; id = $request.id; result = $result }
    if ($scenario -ceq 'rpc-error' -and $request.method -ceq 'models.list') {
        $response.Remove('result')
        $response.error = @{ code = -32601; message = 'SYNTHETIC_SENSITIVE_VALUE' }
    }
    $bytes = [Text.UTF8Encoding]::new($false).GetBytes(($response | ConvertTo-Json -Depth 10 -Compress))
    $responseHeader = [Text.Encoding]::ASCII.GetBytes("Content-Length: $($bytes.Length)`r`n`r`n")
    $outputStream.Write($responseHeader, 0, $responseHeader.Length)
    $outputStream.Write($bytes, 0, $bytes.Length)
    $outputStream.Flush()
}
