[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$DisplayPath,
    [Parameter(Mandatory)][string]$RuleIssuesPath,
    [Parameter(Mandatory)][string]$TemporaryDirectory,
    [switch]$Quiet,
    [int]$IndentLevel = 0
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$repositoryRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))
$toolsRoot = Join-Path $repositoryRoot 'hosted_copilot/tools'
Import-Module (Join-Path $toolsRoot 'modules/workbench/RuleAssistance.psm1')
Import-Module (Join-Path $toolsRoot 'modules/shared/HostedToolkit.Helpers.psm1')
Import-Module (Join-Path $repositoryRoot 'tools/ValidationOutput.psm1')

function Write-AssistanceTestResult {
    param([string]$Name, [string]$Detail)

    if (-not $Quiet) {
        Write-Host (Format-ValidationStatusLine -Status 'passed' -Name $Name -Detail $Detail -IndentLevel $IndentLevel)
    }
}

$normalProfile = Resolve-HostedLlmProfile -Profile normal
$fixtureCommand = Join-Path $PSScriptRoot 'fixtures/copilot-assistance-evaluator.ps1'
$display = Get-Content -LiteralPath $DisplayPath -Raw | ConvertFrom-Json -Depth 100
$candidate = $display.candidates[0]
$key = "$($candidate.source.lane):$($candidate.source.id):$($candidate.assessment.id)"
$catalogIds = @(@($display.catalog.rules | Where-Object status -CEQ 'active').id) + @($display.catalog.protectedRules.id)
$control = Join-Path $TemporaryDirectory 'control'
$null = New-Item -ItemType Directory -Path $control -Force
$env:HOSTED_ASSISTANCE_TEST_CONTROL = $control
$runtimeParameters = @{
    RepositoryRoot = $repositoryRoot; DisplayPath = $DisplayPath
    EvaluatorCommand = $fixtureCommand; Model = 'gpt-5.4'; ReasoningEffort = 'high'
}
$runtime = Get-RuleAssistanceRuntime @runtimeParameters

function New-AssistancePayload {
    param([string]$Question, [string]$Authority = $runtime.authoritySha256)
    return [ordered]@{
        schemaVersion = 1; requestId = [Guid]::NewGuid().ToString('D'); authoritySha256 = $Authority
        candidateKey = $key; sourceHash = $candidate.source.contentSha256
        proposedText = $candidate.recommendation.ruleText
        messages = @([ordered]@{ role = 'user'; content = $Question })
    }
}

function Invoke-AssistanceFixture {
    param([object]$Payload, [switch]$Reject)
    $directory = Join-Path $TemporaryDirectory ([Guid]::NewGuid().ToString('N'))
    $null = New-Item -ItemType Directory -Path $directory
    $requestPath = Join-Path $directory 'request.json'
    $outputPath = Join-Path $directory 'response.json'
    [IO.File]::WriteAllText($requestPath, ($Payload | ConvertTo-Json -Depth 100 -Compress))
    $output = @(& pwsh -NoProfile -File (Join-Path $toolsRoot 'internal/workbench/Invoke-RuleAssistance.ps1') @runtimeParameters -RequestPath $requestPath -OutputPath $outputPath 2>&1)
    if ($Reject) {
        if ($LASTEXITCODE -eq 0 -or (Test-Path -LiteralPath $outputPath)) { throw 'Invalid assistance input or CLI output was accepted' }
        $failure = ($output | Out-String).Trim() | ConvertFrom-Json -Depth 20
        if ($failure.error.code -isnot [string] -or $failure.error.message -isnot [string] -or $failure.error.diagnosticId -cnotmatch '^[a-f0-9]{32}$' -or
            $failure.error.message -match '\x1b|Line \||\.ps1:\d|SYNTHETIC_SENSITIVE_VALUE') { throw 'Assistance worker did not return safe structured error details' }
        $diagnosticPath = Join-Path ([IO.Path]::GetTempPath()) "hosted-rule-assistance-diagnostics/$($failure.error.diagnosticId).json"
        $record = Get-Content -LiteralPath $diagnosticPath -Raw
        if ($record -match 'SYNTHETIC_SENSITIVE_VALUE|"prompt"|"content"|"stderr"|"stdout"') { throw 'Assistance diagnostics retained raw or sensitive content' }
        if ($Payload.messages[-1].content -ceq 'no-answer') {
            $details = $record | ConvertFrom-Json -Depth 20
            if ($failure.error.code -cne 'cli-response-error' -or $details.answerCount -ne 0 -or $details.events.'session.error' -ne 1) { throw 'Failed-response diagnostics lost the actual CLI event counts' }
        }
        Remove-Item -LiteralPath $diagnosticPath
        return ($output | Out-String)
    }
    if ($LASTEXITCODE -ne 0) { throw ($output | Out-String) }
    return Get-Content -LiteralPath $outputPath -Raw | ConvertFrom-Json -Depth 100
}

$promptRoot = Join-Path $toolsRoot 'workbench-prompts'
$registeredPrompts = @(Get-ChildItem -LiteralPath $promptRoot -Filter '*.md')
if ($registeredPrompts.Count -ne 1 -or $registeredPrompts[0].Name -cne 'RuleAssistance.md') { throw 'Update the assistance runtime prompt boundary registry' }
foreach ($prompt in $registeredPrompts) {
    $content = Get-Content -LiteralPath $prompt.FullName -Raw
    if ($content -notmatch '(?m)^## Boundaries\s*$') { throw 'Assistance prompt has no Boundaries section' }
    $boundary = ($content -split '(?m)^## Boundaries\s*$', 2)[1]
    foreach ($required in @('source', 'assessment', 'catalog', 'untrusted quoted data', 'prompt injection', 'tool requests', 'role changes', 'output-format changes', 'policy claims')) {
        if (-not $boundary.Contains($required, [StringComparison]::OrdinalIgnoreCase)) { throw "Assistance prompt omitted boundary: $required" }
    }
}
Write-AssistanceTestResult -Name 'assistance-prompt-boundaries' -Detail 'Prompt registry and quoted-data boundaries'
$reply = Invoke-AssistanceFixture (New-AssistancePayload 'warning')
if ($reply.requestId -eq '' -or $reply.model -cne 'gpt-5.4' -or $reply.reasoningEffort -cne 'high' -or
    (@($reply.catalogRuleIds | Sort-Object -CaseSensitive) -join "`0") -cne (@($catalogIds | Sort-Object -CaseSensitive) -join "`0") -or
    $reply.message -notlike 'Synthetic catalog advice*' -or -not $reply.suggestedWording -or $reply.elapsedMilliseconds -lt 0) { throw 'Valid assistance result lost its context, profile, or proposal' }
foreach ($question in @('multiple-messages', 'two-structured-messages', 'empty-intermediate', 'null-tool-requests')) {
    $completed = Invoke-AssistanceFixture (New-AssistancePayload $question)
    if ($completed.message -cne $reply.message -or $completed.suggestedWording -cne $reply.suggestedWording) { throw 'Completed assistance did not select its final response' }
}
foreach ($question in @('wrong-model', 'invalid-shape', 'tool-event', 'embedded-tool-request', 'nested-agent', 'no-answer', 'multiple-answers', 'missing-turn-end', 'missing-result', 'duplicate-result', 'trailing-message', 'invalid-final', 'empty-final', 'cli-failure')) {
    $null = Invoke-AssistanceFixture (New-AssistancePayload $question) -Reject
}
$null = Invoke-AssistanceFixture (New-AssistancePayload 'stale' ('0' * 64)) -Reject
$unknown = New-AssistancePayload 'unknown'
$unknown.candidateKey = 'unknown'
$null = Invoke-AssistanceFixture $unknown -Reject
$history = New-AssistancePayload 'follow-up'
$history.messages = @(@{ role = 'user'; content = 'First question' }, @{ role = 'assistant'; content = 'Previous answer' }, @{ role = 'user'; content = 'Follow-up' })
$null = Invoke-AssistanceFixture $history
$overBudget = New-AssistancePayload 'over budget'
$overBudget.messages = @(
    for ($index = 0; $index -lt 45; $index++) { @{ role = if ($index % 2) { 'assistant' } else { 'user' }; content = 'x' * 8000 } }
    @{ role = 'assistant'; content = 'x' * 40000 }
    @{ role = 'user'; content = 'Final question' }
)
$failure = Invoke-AssistanceFixture $overBudget -Reject
if ($failure -notlike '*input budget*' -or $failure -notlike '*No catalog rules or conversation turns were dropped*') { throw 'Oversized conversations did not fail explicitly without truncation' }
Write-AssistanceTestResult -Name 'assistance-cli-contract' -Detail 'Catalog grounding, CLI transport, history, strict replies, identity and input limits'

foreach ($known in @($true, $false)) {
    $exception = if ($known) { New-RuleAssistanceException -Message 'Synthetic safe validation reason.' -Code 'synthetic-validation' }
        else { [InvalidOperationException]::new('SYNTHETIC_SENSITIVE_VALUE') }
    $record = [Management.Automation.ErrorRecord]::new($exception, 'fixture', [Management.Automation.ErrorCategory]::InvalidOperation, $null)
    $diagnostic = [ordered]@{ schemaVersion = 1; diagnosticId = [Guid]::NewGuid().ToString('N'); phase = 'synthetic-test' }
    $failure = ConvertTo-RuleAssistanceError -ErrorRecord $record -Diagnostic $diagnostic
    $expected = if ($known) { 'Synthetic safe validation reason.' } else { 'Rule assistance could not complete. No changes were applied by this request.' }
    if ($failure.message -cne $expected -or ($failure | ConvertTo-Json -Compress) -match 'SYNTHETIC_SENSITIVE_VALUE') { throw 'Error conversion replaced a known reason or exposed an unexpected exception' }
    Remove-Item -LiteralPath (Join-Path ([IO.Path]::GetTempPath()) "hosted-rule-assistance-diagnostics/$($failure.diagnosticId).json")
}
Write-AssistanceTestResult -Name 'assistance-error-details' -Detail 'Known reasons preserved; unexpected exception details excluded'

function Send-AssistanceHttp {
    param([Net.Http.HttpClient]$Http, [string]$Url, [object]$Payload, [string]$Token, [Threading.CancellationToken]$Cancellation = [Threading.CancellationToken]::None)
    $message = [Net.Http.HttpRequestMessage]::new([Net.Http.HttpMethod]::Post, "$Url/assist-rule")
    if ($Token) { $message.Headers.Add('X-Workbench-Operation-Token', $Token) }
    $body = @{ payloadBase64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes(($Payload | ConvertTo-Json -Depth 100 -Compress))) } | ConvertTo-Json -Compress
    $message.Content = [Net.Http.StringContent]::new($body, [Text.Encoding]::UTF8, 'application/json')
    return $Http.SendAsync($message, $Cancellation)
}

function Wait-AssistanceWorker {
    $marker = Join-Path $control 'held.json'
    $deadline = [DateTimeOffset]::UtcNow.AddSeconds(20)
    while (-not (Test-Path -LiteralPath $marker)) {
        if ([DateTimeOffset]::UtcNow -gt $deadline) { throw 'Assistance fixture did not start' }
        Start-Sleep -Milliseconds 25
    }
    return Get-Content -LiteralPath $marker -Raw | ConvertFrom-Json
}

function Assert-AssistanceStopped {
    param([object]$Worker)
    $deadline = [DateTimeOffset]::UtcNow.AddSeconds(10)
    do {
        $remaining = @(Get-Process -Id $Worker.worker, $Worker.child -ErrorAction SilentlyContinue)
        $directoryExists = Test-Path -LiteralPath $Worker.directory
        if ($remaining.Count -or $directoryExists) { Start-Sleep -Milliseconds 25 }
    } while (($remaining.Count -or $directoryExists) -and [DateTimeOffset]::UtcNow -lt $deadline)
    if ($remaining.Count -or $directoryExists) { throw 'Assistance cancellation left a worker, child, or temporary conversation data behind' }
}

foreach ($profile in @('internal', 'production')) {
    $site = Join-Path $TemporaryDirectory "$profile-site"
    $null = New-Item -ItemType Directory -Path $site
    foreach ($asset in @('index.html', 'app.js', 'assistance-waiting-phrases.json', 'llm-brands.json', 'hierarchical-view.js', 'statusbar.js', 'styles.css', 'favicon.svg', 'icons')) {
        Copy-Item -LiteralPath (Join-Path $repositoryRoot "hosted_copilot/workbench/$asset") -Destination $site -Recurse
    }
    Copy-Item -LiteralPath $DisplayPath -Destination (Join-Path $site 'workbench-display.json')
    Copy-Item -LiteralPath $RuleIssuesPath -Destination (Join-Path $site 'workbench-rule-issues.json')
    $config = @{ shutdownToken = 'a' * 64; operationToken = 'b' * 64 } | ConvertTo-Json -Compress
    [IO.File]::WriteAllText((Join-Path $site 'shutdown-config.js'), "globalThis.__HOSTED_RULE_WORKBENCH__ = $config;")
    $probe = [Net.Sockets.TcpListener]::new([Net.IPAddress]::Loopback, 0)
    $probe.Start()
    $port = ([Net.IPEndPoint]$probe.LocalEndpoint).Port
    $probe.Stop()
    $job = Start-Job -ScriptBlock {
        param($Profile, $Tools, $Root, $Site, $Port, $Command, $Control)
        $env:HOSTED_ASSISTANCE_TEST_CONTROL = $Control
        if ($Profile -eq 'production') {
            & pwsh -NoProfile -File (Join-Path $Tools 'Start-RuleWorkbench.ps1') -SiteDirectory $Site -Port $Port -NoLaunch -SkipGitHubAuthorization -EvaluatorCommand $Command
        } else {
            & pwsh -NoProfile -File (Join-Path $Tools 'internal/workbench/Start-WorkbenchLoopbackServer.ps1') -SiteDirectory $Site -Port $Port -NoLaunch -ShutdownToken ('a' * 64) -OperationToken ('b' * 64) -RepositoryRoot $Root -ManualRelationshipPath (Join-Path $Tools 'internal/reconciliation/Invoke-ManualRuleRelationship.ps1') -ManualRelationshipCacheDirectory (Join-Path $Control 'cache') -EvaluatorCommand $Command
        }
    } -ArgumentList $profile, $toolsRoot, $repositoryRoot, $site, $port, $fixtureCommand, $control
    $http = [Net.Http.HttpClient]::new()
    $http.Timeout = [TimeSpan]::FromSeconds(30)
    $cancel = [Threading.CancellationTokenSource]::new()
    $url = "http://127.0.0.1:$port"
    $config = $null
    try {
        $deadline = [DateTimeOffset]::UtcNow.AddSeconds(30)
        while ($null -eq $config) {
            try { $config = $http.GetStringAsync("$url/runtime-config").GetAwaiter().GetResult() | ConvertFrom-Json }
            catch [Net.Http.HttpRequestException] {
                if ([DateTimeOffset]::UtcNow -gt $deadline) { throw }
                Start-Sleep -Milliseconds 100
            }
        }
        if ($config.ruleAssistance.model -cne $normalProfile.model -or $config.ruleAssistance.reasoningEffort -cne $normalProfile.reasoningEffort) { throw "$profile lost the normal assistance profile" }
        $unauthorized = (Send-AssistanceHttp $http $url (New-AssistancePayload 'unauthorized') '').GetAwaiter().GetResult()
        if ([int]$unauthorized.StatusCode -ne 403) { throw "$profile assistance was not authenticated" }
        $payload = New-AssistancePayload 'warning' $config.ruleAssistance.authoritySha256
        $response = (Send-AssistanceHttp $http $url $payload $config.operationToken).GetAwaiter().GetResult()
        if ([int]$response.StatusCode -ne 200) { throw ($response.Content.ReadAsStringAsync().GetAwaiter().GetResult()) }
        $response = (Send-AssistanceHttp $http $url (New-AssistancePayload 'no-answer' $config.ruleAssistance.authoritySha256) $config.operationToken).GetAwaiter().GetResult()
        $failure = $response.Content.ReadAsStringAsync().GetAwaiter().GetResult() | ConvertFrom-Json -Depth 20
        if ([int]$response.StatusCode -ne 500 -or $failure.error.code -cne 'cli-response-error' -or $failure.error.message -notlike '*failed or aborted*' -or
            $failure.error.diagnosticId -cnotmatch '^[a-f0-9]{32}$') { throw "$profile did not preserve structured worker error details across the HTTP boundary" }
        Remove-Item -LiteralPath (Join-Path ([IO.Path]::GetTempPath()) "hosted-rule-assistance-diagnostics/$($failure.error.diagnosticId).json")
        $pending = Send-AssistanceHttp $http $url (New-AssistancePayload 'hold' $config.ruleAssistance.authoritySha256) $config.operationToken $cancel.Token
        $worker = Wait-AssistanceWorker
        $asset = $http.GetAsync("$url/styles.css")
        if (-not $asset.Wait(2000) -or [int]$asset.GetAwaiter().GetResult().StatusCode -ne 200) { throw "$profile blocked HTTP while assistance was working" }
        $cancel.Cancel()
        Assert-AssistanceStopped $worker
        Remove-Item -LiteralPath (Join-Path $control 'held.json')
        $pending = Send-AssistanceHttp $http $url (New-AssistancePayload 'hold' $config.ruleAssistance.authoritySha256) $config.operationToken
        $worker = Wait-AssistanceWorker
        $shutdown = [Net.Http.HttpRequestMessage]::new([Net.Http.HttpMethod]::Post, "$url/shutdown")
        $shutdown.Headers.Add('X-Workbench-Shutdown-Token', [string]$config.shutdownToken)
        $response = $http.SendAsync($shutdown).GetAwaiter().GetResult()
        if ([int]$response.StatusCode -ne 200 -or -not (Wait-Job $job -Timeout 10)) { throw "$profile did not shut down during assistance" }
        Assert-AssistanceStopped $worker
        Remove-Item -LiteralPath (Join-Path $control 'held.json')
        $null = Receive-Job $job -ErrorAction Stop
        Write-AssistanceTestResult -Name "assistance-$profile-http" -Detail 'Authorization, replies, responsive assets, disconnect cancellation, shutdown and cleanup'
    } finally {
        if ($job.State -notin @('Completed', 'Failed', 'Stopped') -and $null -ne $config) {
            $shutdown = [Net.Http.HttpRequestMessage]::new([Net.Http.HttpMethod]::Post, "$url/shutdown")
            $shutdown.Headers.Add('X-Workbench-Shutdown-Token', [string]$config.shutdownToken)
            try {
                $null = $http.SendAsync($shutdown).GetAwaiter().GetResult()
                $null = Wait-Job $job -Timeout 10
            } catch [Net.Http.HttpRequestException] {
                Write-Warning "Assistance fixture shutdown failed: $($_.Exception.Message)"
            } finally {
                $shutdown.Dispose()
            }
        }
        $cancel.Cancel()
        $cancel.Dispose()
        $http.Dispose()
        if ($job.State -notin @('Completed', 'Failed', 'Stopped')) { Stop-Job $job }
        Remove-Job $job -Force
    }
}
