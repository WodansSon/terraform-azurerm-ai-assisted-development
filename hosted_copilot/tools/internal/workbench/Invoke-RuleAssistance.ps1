[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$RequestPath,
    [Parameter(Mandatory)][string]$OutputPath,
    [Parameter(Mandatory)][string]$DisplayPath,
    [Parameter(Mandatory)][string]$RepositoryRoot,
    [Parameter(Mandatory)][string]$EvaluatorCommand,
    [Parameter(Mandatory)][string]$Model,
    [Parameter(Mandatory)][ValidateSet('low', 'medium', 'high', 'xhigh')][string]$ReasoningEffort
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot '../../modules/workbench/RuleAssistance.psm1')
Import-Module (Join-Path $PSScriptRoot '../../modules/shared/HostedToolkit.Helpers.psm1')

function Assert-AssistanceProperties {
    param([object]$Value, [string[]]$Names)
    if ($null -eq $Value -or (@($Value.PSObject.Properties.Name | Sort-Object -CaseSensitive) -join "`0") -cne (@($Names | Sort-Object -CaseSensitive) -join "`0")) {
        throw 'Rule assistance input has an unexpected property set'
    }
}

$runtimeParameters = @{
    RepositoryRoot = $RepositoryRoot; DisplayPath = $DisplayPath
    EvaluatorCommand = $EvaluatorCommand; Model = $Model; ReasoningEffort = $ReasoningEffort
}
$runtime = Get-RuleAssistanceRuntime @runtimeParameters
$request = Get-Content -LiteralPath $RequestPath -Raw | ConvertFrom-Json -Depth 100 -DateKind String
Assert-AssistanceProperties $request @('schemaVersion', 'requestId', 'authoritySha256', 'candidateKey', 'sourceHash', 'proposedText', 'messages')
$requestId = [Guid]::Empty
if ($request.schemaVersion -ne 1 -or -not [Guid]::TryParseExact([string]$request.requestId, 'D', [ref]$requestId) -or
    [string]$request.authoritySha256 -cne $runtime.authoritySha256) {
    throw 'Rule assistance context changed; reload the current Workbench before asking again'
}
if ($request.proposedText -isnot [string] -or [string]::IsNullOrWhiteSpace($request.proposedText) -or $request.proposedText.Length -gt 20000) {
    throw 'Rule assistance requires current rule wording between 1 and 20000 characters'
}
$messages = @($request.messages)
if (-not $messages.Count -or $messages.Count % 2 -ne 1) { throw 'Rule assistance conversation must end with a maintainer message' }
for ($index = 0; $index -lt $messages.Count; $index++) {
    $message = $messages[$index]
    Assert-AssistanceProperties $message @('role', 'content')
    $expectedRole = if ($index % 2 -eq 0) { 'user' } else { 'assistant' }
    $maximumLength = if ($expectedRole -ceq 'user') { 8000 } else { 40064 }
    if ($message.role -cne $expectedRole -or $message.content -isnot [string] -or [string]::IsNullOrWhiteSpace($message.content) -or $message.content.Length -gt $maximumLength) {
        throw 'Rule assistance conversation contains an invalid turn'
    }
}
$displayJson = Get-Content -LiteralPath $DisplayPath -Raw
$schemaPath = Join-Path $RepositoryRoot 'hosted_copilot/copilot-rule-catalog/assessment-reconciliation/workbench-display-v4.schema.json'
if (-not ($displayJson | Test-Json -SchemaFile $schemaPath -ErrorAction Stop)) { throw 'Rule assistance display snapshot is invalid' }
$display = $displayJson | ConvertFrom-Json -Depth 100 -DateKind String
$candidates = @($display.candidates | Where-Object { "$($_.source.lane):$($_.source.id):$($_.assessment.id)" -ceq $request.candidateKey })
if ($candidates.Count -ne 1 -or $candidates[0].source.contentSha256 -cne $request.sourceHash) { throw 'Rule assistance candidate identity is unknown or stale' }
$candidate = $candidates[0]
$ruleId = if ($candidate.catalogMapping.hostedRuleId) { [string]$candidate.catalogMapping.hostedRuleId } else { [string]$candidate.recommendation.hostedId }
$catalog = @($display.catalog.rules | Where-Object status -CEQ 'active' | ForEach-Object {
    [ordered]@{ id = $_.id; status = $_.status; text = $_.text }
}) + @($display.catalog.protectedRules | ForEach-Object {
    [ordered]@{ id = $_.id; status = 'protected'; text = $_.text }
})
if ([string]::IsNullOrWhiteSpace($ruleId) -or $ruleId -cin @($display.catalog.protectedRules.id)) { throw 'Rule assistance requires a non-protected candidate target' }
$context = [ordered]@{
    currentRule = [ordered]@{ id = $ruleId; baselineText = $candidate.recommendation.ruleText; proposedText = $request.proposedText }
    sources = @($candidate.members | ForEach-Object { [ordered]@{ id = $_.source.id; text = $_.source.text; provenance = $_.source.provenance } })
    catalog = $catalog
    messages = $messages
}
$promptRoot = Join-Path $RepositoryRoot 'hosted_copilot/tools/workbench-prompts'
$prompt = (Get-Content -LiteralPath (Join-Path $promptRoot 'RuleAssistance.md') -Raw) + "`n## Supplied Context`n" + ($context | ConvertTo-Json -Depth 100 -Compress)
$promptBytes = [Text.Encoding]::UTF8.GetByteCount($prompt)
if ($promptBytes -gt $runtime.maximumPromptBytes) {
    throw "Rule assistance input requires $promptBytes bytes and exceeds the $($runtime.maximumPromptBytes)-byte input budget. Clear the conversation and try again. No catalog rules or conversation turns were dropped."
}
$command = Get-Command $EvaluatorCommand -ErrorAction Stop
$workingDirectory = Split-Path -Parent $RequestPath
$startInfo = [Diagnostics.ProcessStartInfo]::new()
$prefix = @()
if ($command.CommandType -eq [Management.Automation.CommandTypes]::ExternalScript) {
    $startInfo.FileName = [Diagnostics.Process]::GetCurrentProcess().MainModule.FileName
    $prefix = @('-NoLogo', '-NoProfile', '-NonInteractive', '-File', [string]$command.Source)
}
else { $startInfo.FileName = $command.Source }
$startInfo.WorkingDirectory = $workingDirectory
$startInfo.UseShellExecute = $false
$startInfo.CreateNoWindow = $true
$startInfo.RedirectStandardInput = $true
$startInfo.RedirectStandardOutput = $true
$startInfo.RedirectStandardError = $true
$startInfo.StandardInputEncoding = [Text.UTF8Encoding]::new($false)
$startInfo.StandardOutputEncoding = [Text.UTF8Encoding]::new($false)
$startInfo.StandardErrorEncoding = [Text.UTF8Encoding]::new($false)
foreach ($argument in $prefix + @(
    '-C', $workingDirectory, '--no-color', '--stream', 'off', '--no-custom-instructions', '--no-ask-user',
    '--disable-builtin-mcps', '--no-auto-update', '--disallow-temp-dir', '--no-remote-export',
    '--model', $Model, '--reasoning-effort', $ReasoningEffort, '--context', 'default',
    '--available-tools', '--output-format', 'json', '--log-level', 'none', '--log-dir', (Join-Path $workingDirectory 'logs')
)) { $startInfo.ArgumentList.Add($argument) }
$process = [Diagnostics.Process]::new()
$process.StartInfo = $startInfo
$stopwatch = [Diagnostics.Stopwatch]::StartNew()
$started = $false
try {
    $started = $process.Start()
    if (-not $started) { throw 'Rule assistance CLI did not start' }
    $stdout = $process.StandardOutput.ReadToEndAsync()
    $stderr = $process.StandardError.ReadToEndAsync()
    $process.StandardInput.Write($prompt)
    $process.StandardInput.Close()
    $process.WaitForExit()
    $output = $stdout.GetAwaiter().GetResult()
    $null = $stderr.GetAwaiter().GetResult()
    if ($process.ExitCode -ne 0) { throw "Rule assistance CLI exited with code $($process.ExitCode). Check local CLI authentication and availability; no reply was accepted." }
}
finally {
    if ($started -and -not $process.HasExited) { $process.Kill($true); $process.WaitForExit() }
    $process.Dispose()
}
$stopwatch.Stop()
$answers = [Collections.Generic.List[object]]::new()
foreach ($line in ($output -split '\r?\n' | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })) {
    try { $event = $line | ConvertFrom-Json -Depth 100 -DateKind String }
    catch { throw 'Rule assistance CLI returned invalid JSONL; no reply was accepted' }
    if ($event.type -clike 'tool.*') { throw 'Rule assistance CLI attempted a tool operation; no reply was accepted' }
    if ($event.type -ceq 'assistant.message') {
        if ($event.data.model -cne $Model) { throw 'Rule assistance CLI returned an unexpected model' }
        $answers.Add($event.data)
    }
}
if ($answers.Count -ne 1) { throw 'Rule assistance CLI must return exactly one completed answer' }
$answerJson = [string]$answers[0].content
try { $valid = $answerJson | Test-Json -SchemaFile (Join-Path $promptRoot 'rule-assistance-result.schema.json') -ErrorAction Stop }
catch { throw 'Rule assistance answer did not satisfy its response contract' }
if (-not $valid) { throw 'Rule assistance answer did not satisfy its response contract' }
$answer = $answerJson | ConvertFrom-Json -Depth 100
if ([string]::IsNullOrWhiteSpace($answer.message) -or ($null -ne $answer.suggestedWording -and [string]::IsNullOrWhiteSpace($answer.suggestedWording))) {
    throw 'Rule assistance returned an empty answer or suggestion'
}
if ((Get-RuleAssistanceRuntime @runtimeParameters).authoritySha256 -cne $runtime.authoritySha256) { throw 'Rule assistance context changed during the request; ask again using the current Workbench' }
$result = [ordered]@{
    schemaVersion = 1; requestId = $request.requestId; candidateKey = $request.candidateKey
    authoritySha256 = $runtime.authoritySha256; proposedTextSha256 = Get-Sha256 -Content $request.proposedText
    catalogSha256 = $runtime.catalogSha256; protectedRulesSha256 = $runtime.protectedRulesSha256
    model = $Model; reasoningEffort = $ReasoningEffort; elapsedMilliseconds = $stopwatch.ElapsedMilliseconds
    catalogRuleIds = @($catalog.id); message = $answer.message; suggestedWording = $answer.suggestedWording
}
[IO.File]::WriteAllText($OutputPath, ($result | ConvertTo-Json -Depth 100 -Compress), [Text.UTF8Encoding]::new($false))
