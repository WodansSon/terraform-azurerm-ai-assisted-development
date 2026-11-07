[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$Stage,
    [Parameter(Mandatory)][string]$Model,
    [Parameter(Mandatory)][ValidateSet('low', 'medium', 'high', 'xhigh')][string]$ReasoningEffort,
    [Parameter(Mandatory)][string]$ExpectedPromptSha256,
    [Parameter(Mandatory)][string]$ExpectedSchemaSha256,
    [string]$EvaluatorCommand = 'copilot',
    [ValidateRange(1, 1800)][int]$TimeoutSeconds = 600
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$hostedRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))
Import-Module (Join-Path $PSScriptRoot '../../modules/shared/HostedCli.psm1') -Force
$registry = Get-Content -LiteralPath (Join-Path $hostedRoot 'contracts/workbench/native-evaluation-stages-v4.json') -Raw | ConvertFrom-Json
$selected = @($registry.stages | Where-Object { $_.code -ceq $Stage })
if ($registry.schemaVersion -ne 4 -or $selected.Count -ne 1) { throw 'Native evaluator stage is not registered' }
$promptPath = Join-Path $hostedRoot $selected[0].prompt
$schemaPath = Join-Path $hostedRoot $selected[0].resultSchema
if ((Get-FileHash -LiteralPath $promptPath -Algorithm SHA256).Hash.ToLowerInvariant() -cne $ExpectedPromptSha256 -or
    (Get-FileHash -LiteralPath $schemaPath -Algorithm SHA256).Hash.ToLowerInvariant() -cne $ExpectedSchemaSha256) {
    throw 'Native evaluator prompt or result contract changed after request registration'
}
$inputText = [Console]::In.ReadToEnd()
$inputData = $inputText | ConvertFrom-Json -Depth 100 -DateKind String
if ($inputData.stage -cne $Stage) { throw 'Native input does not match the requested stage' }
$promptText = Get-Content -LiteralPath $promptPath -Raw
$schemaText = Get-Content -LiteralPath $schemaPath -Raw
$inlinePrompt = "$promptText`n`n## Output Contract`n$schemaText`n`n## Untrusted Quoted Input`n$inputText"
$launch = Resolve-HostedCliLaunch -EvaluatorCommand $EvaluatorCommand
$workingDirectory = Join-Path ([IO.Path]::GetTempPath()) ('hosted-native-evaluation-' + [guid]::NewGuid().ToString('N'))
$null = New-Item -ItemType Directory -Path $workingDirectory
$process = [Diagnostics.Process]::new()
$started = $false
try {
    $process.StartInfo = New-HostedCliStartInfo -Launch $launch -WorkingDirectory $workingDirectory -Arguments @(
        '-C', $workingDirectory, '--no-color', '--stream', 'off', '--no-custom-instructions', '--no-ask-user',
        '--disable-builtin-mcps', '--no-auto-update', '--disallow-temp-dir', '--no-remote-export',
        '--model', $Model, '--reasoning-effort', $ReasoningEffort, '--available-tools', '--output-format', 'json'
    )
    $started = $process.Start()
    if (-not $started) { throw 'Native evaluator process did not start' }
    $stdoutTask = $process.StandardOutput.ReadToEndAsync()
    $stderrTask = $process.StandardError.ReadToEndAsync()
    $process.StandardInput.Write($inlinePrompt)
    $process.StandardInput.Close()
    if (-not $process.WaitForExit($TimeoutSeconds * 1000)) {
        $process.Kill($true)
        $process.WaitForExit()
        throw 'Native evaluator exceeded its bounded timeout'
    }
    $stdout = $stdoutTask.GetAwaiter().GetResult()
    $stderr = $stderrTask.GetAwaiter().GetResult()
    if ($process.ExitCode -ne 0) {
        $failureCategory = 'cli-exit'
        $failurePatterns = [ordered]@{
            'cli-options' = '(?i)unknown option|unexpected argument|unrecognized argument'
            'prompt-mode' = '(?i)no prompt|no input|non-interactive|tty'
            'authentication' = '(?i)not authenticated|authentication|sign in'
            'permissions' = '(?i)permission|denied|available-tools|deny-tool'
            'model-settings' = '(?i)model|reasoning|effort'
            'working-directory' = '(?i)directory|folder|trust'
        }
        foreach ($candidate in $failurePatterns.GetEnumerator()) {
            if ($stderr -match $candidate.Value) { $failureCategory = $candidate.Key; break }
        }
        [Console]::Error.WriteLine((@{ kind = 'native-cli-exit'; category = $failureCategory; exitCode = $process.ExitCode;
            stdoutBytes = [Text.Encoding]::UTF8.GetByteCount($stdout); stderrBytes = [Text.Encoding]::UTF8.GetByteCount($stderr) } | ConvertTo-Json -Compress))
        throw "Native evaluator failed with code $($process.ExitCode); stderr byte count $([Text.Encoding]::UTF8.GetByteCount($stderr)); response content omitted"
    }
    $messages = [Collections.Generic.List[object]]::new()
    foreach ($line in ($stdout -split "`r?`n")) {
        if ([string]::IsNullOrWhiteSpace($line)) { continue }
        try { $event = $line | ConvertFrom-Json -Depth 100 -DateKind String }
        catch { throw 'Native evaluator stdout contains a non-JSON event; content omitted' }
        if ($event.type -ceq 'assistant.message') { $messages.Add($event.data) }
    }
    if ($messages.Count -eq 0 -or $messages[$messages.Count - 1].model -cne $Model) { throw 'Native evaluator did not return the requested model response' }
    $content = [string]$messages[$messages.Count - 1].content
    try {
        if (-not ($content | Test-Json -SchemaFile $schemaPath -ErrorAction Stop)) { throw 'Invalid result' }
        $result = $content | ConvertFrom-Json -Depth 100 -DateKind String
    } catch { throw 'Native evaluator response failed its result contract; content omitted' }
    $result | ConvertTo-Json -Depth 100 -Compress
} finally {
    if ($started -and -not $process.HasExited) { $process.Kill($true); $process.WaitForExit() }
    $process.Dispose()
    Remove-Item -LiteralPath $workingDirectory -Recurse -Force -ErrorAction SilentlyContinue
}
