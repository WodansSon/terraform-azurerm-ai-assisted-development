[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$DisplayPath,
    [Parameter(Mandatory = $true)][string]$RuleIssuesPath,
    [Parameter(Mandatory = $true)][string]$TemporaryDirectory,
    [switch]$Quiet,
    [ValidateRange(0, 10)][int]$IndentLevel = 0
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repositoryRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))
Import-Module (Join-Path $repositoryRoot 'tools/ValidationOutput.psm1')
$toolsRoot = Join-Path $repositoryRoot 'hosted_copilot\tools'
$workbenchRoot = Join-Path $repositoryRoot 'hosted_copilot\workbench'
$display = Get-Content -LiteralPath $DisplayPath -Raw | ConvertFrom-Json -Depth 100
$candidate = @($display.candidates | Where-Object { $_.recommendation.hostedId -ceq 'REVIEW-REPO-001' })[0]
$candidateKey = "$($candidate.source.lane):$($candidate.source.id):$($candidate.assessment.id)"
$messages = [Collections.Generic.List[Net.Http.HttpRequestMessage]]::new()

function New-FixtureRequest {
    param([string]$Method, [string]$Uri, [string]$Body, [string]$Token)

    $message = [Net.Http.HttpRequestMessage]::new([Net.Http.HttpMethod]::new($Method), $Uri)
    if ($Body) { $message.Content = [Net.Http.StringContent]::new($Body, [Text.Encoding]::UTF8, 'application/json') }
    if ($Token) { $message.Headers.Add('X-Workbench-Operation-Token', $Token) }
    $messages.Add($message)
    return $message
}

function Receive-FixtureResponse {
    param([object]$Task, [int]$TimeoutMilliseconds = 2000)

    if (-not $Task.Wait($TimeoutMilliseconds)) {
        throw "HTTP response exceeded ${TimeoutMilliseconds}ms while validation was held"
    }
    return $Task.GetAwaiter().GetResult()
}

function New-FixturePayload {
    param([string]$Text, [string]$Authority)

    $encoded = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($Text))
    $request = [ordered]@{
        schemaVersion = 2
        requestId = [Guid]::NewGuid().ToString('D')
        authoritySha256 = $Authority
        candidateKey = $candidateKey
        ruleTextBase64 = $encoded
        sourceFiles = @($display.sourceFiles)
        proposals = @($display.candidates | ForEach-Object {
            $key = "$($_.source.lane):$($_.source.id):$($_.assessment.id)"
            [ordered]@{
                candidateKey = $key
                sourceHash = [string]$_.source.contentSha256
                action = 'no-change'
                inPlan = $false
                proposedTextBase64 = if ($key -ceq $candidateKey) { $encoded } else { [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes([string]$_.recommendation.ruleText)) }
                retireHostedRuleIds = @()
            }
        })
        priorRelationships = @()
    }
    return @{ payloadBase64 = [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes(($request | ConvertTo-Json -Depth 100 -Compress))) } | ConvertTo-Json -Compress
}

function Wait-FixtureWorker {
    param([string]$ControlDirectory, [string]$Text, [object]$Task)

    $hash = [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData([Text.Encoding]::UTF8.GetBytes($Text))).ToLowerInvariant()
    $marker = Join-Path $ControlDirectory "started-$hash.json"
    $deadline = [DateTimeOffset]::UtcNow.AddSeconds(15)
    while (-not (Test-Path -LiteralPath $marker)) {
        if ($Task.IsCompleted) {
            $response = $Task.GetAwaiter().GetResult()
            $body = $response.Content.ReadAsStringAsync().GetAwaiter().GetResult() | ConvertFrom-Json
            throw "Validation ended before the held evaluator started: $($response.StatusCode): $($body.error)"
        }
        if ([DateTimeOffset]::UtcNow -gt $deadline) { throw 'Held evaluator did not start' }
        Start-Sleep -Milliseconds 25
    }
    return Get-Content -LiteralPath $marker -Raw | ConvertFrom-Json
}

function Assert-FixtureWorkersStopped {
    param([object]$Worker)

    $deadline = [DateTimeOffset]::UtcNow.AddSeconds(5)
    do {
        $remaining = @(Get-Process -Id $Worker.worker, $Worker.child -ErrorAction SilentlyContinue)
        if ($remaining.Count) { Start-Sleep -Milliseconds 25 }
    } while ($remaining.Count -and [DateTimeOffset]::UtcNow -lt $deadline)
    if ($remaining.Count) { throw 'Request cleanup left its evaluator or descendant running' }
}

foreach ($profile in @('internal', 'production', 'production-override')) {
    $expectedModel = if ($profile -eq 'production-override') { 'fixture-saved-model' } else { 'gpt-6-luna' }
    $expectedEffort = if ($profile -eq 'production-override') { 'low' } else { 'medium' }
    $profileDirectory = Join-Path $TemporaryDirectory $profile
    $siteDirectory = Join-Path $profileDirectory 'site'
    $controlDirectory = Join-Path $profileDirectory 'control'
    $null = New-Item -ItemType Directory -Path $siteDirectory, $controlDirectory -Force
    foreach ($asset in @('index.html', 'app.js', 'assistance-waiting-phrases.json', 'llm-brands.json', 'hierarchical-view.js', 'statusbar.js', 'styles.css', 'favicon.svg', 'icons')) {
        Copy-Item -LiteralPath (Join-Path $workbenchRoot $asset) -Destination $siteDirectory -Recurse
    }
    Copy-Item -LiteralPath $DisplayPath -Destination (Join-Path $siteDirectory 'workbench-display.json')
    Copy-Item -LiteralPath $RuleIssuesPath -Destination (Join-Path $siteDirectory 'workbench-rule-issues.json')
    $config = @{ shutdownToken = 'a' * 64; operationToken = 'b' * 64 } | ConvertTo-Json -Compress
    [IO.File]::WriteAllText((Join-Path $siteDirectory 'shutdown-config.js'), "globalThis.__HOSTED_RULE_WORKBENCH__ = $config;")
    $probe = [Net.Sockets.TcpListener]::new([Net.IPAddress]::Loopback, 0)
    $probe.Start()
    $port = ([Net.IPEndPoint]$probe.LocalEndpoint).Port
    $probe.Stop()
    $serverJob = Start-Job -ScriptBlock {
        param($Profile, $ToolsRoot, $SiteDirectory, $ControlDirectory, $ProfileDirectory, $RepositoryRoot, $Port)
        $env:HOSTED_WORKBENCH_TEST_CONTROL_DIRECTORY = $ControlDirectory
        $heldEvaluator = Join-Path $ToolsRoot 'tests\fixtures\held-relationship-evaluator.ps1'
        $adjudicator = Join-Path $ToolsRoot 'tests\fixtures\rule-issue-adjudication-evaluator.ps1'
        $env:HOSTED_WORKBENCH_TEST_ADJUDICATION_METRICS = Join-Path $ProfileDirectory 'adjudication-metrics.jsonl'
        $evaluatorCommand = Join-Path $ToolsRoot 'tests/fixtures/copilot-metadata-evaluator.ps1'
        if ($Profile -in @('production', 'production-override')) {
            $savedProfileArguments = @()
            if ($Profile -eq 'production-override') {
                $savedProfileArguments = @('-SavedRuleEvaluationModel', 'fixture-saved-model', '-SavedRuleEvaluationReasoningEffort', 'low')
            }
            & pwsh -NoProfile -File (Join-Path $ToolsRoot 'Start-RuleWorkbench.ps1') -SiteDirectory $SiteDirectory -Port $Port -NoLaunch -SkipGitHubAuthorization -RelationshipEvaluatorScriptPath $heldEvaluator -AdjudicationEvaluatorScriptPath $adjudicator -ManualRelationshipCacheDirectory (Join-Path $ProfileDirectory 'cache') -EvaluatorCommand $evaluatorCommand -Model 'fixture-normal-model' -AssessmentReasoningEffort xhigh @savedProfileArguments
        }
        else {
            & pwsh -NoProfile -File (Join-Path $ToolsRoot 'internal\workbench\Start-WorkbenchLoopbackServer.ps1') -SiteDirectory $SiteDirectory -Port $Port -NoLaunch -ShutdownToken ('a' * 64) -OperationToken ('b' * 64) -RepositoryRoot $RepositoryRoot -ManualRelationshipPath (Join-Path $ToolsRoot 'internal\reconciliation\Invoke-ManualRuleRelationship.ps1') -ManualRelationshipCacheDirectory (Join-Path $ProfileDirectory 'cache') -RelationshipEvaluatorScriptPath $heldEvaluator -AdjudicationEvaluatorScriptPath $adjudicator -EvaluatorCommand $evaluatorCommand
        }
    } -ArgumentList $profile, $toolsRoot, $siteDirectory, $controlDirectory, $profileDirectory, $repositoryRoot, $port
    $http = [Net.Http.HttpClient]::new()
    $http.Timeout = [TimeSpan]::FromSeconds(30)
    $baseUrl = "http://127.0.0.1:$port"
    $runtime = $null
    $cancellation = [Threading.CancellationTokenSource]::new()
    $profileName = "server/$profile"
    $profileStopwatch = [Diagnostics.Stopwatch]::StartNew()
    if (-not $Quiet) {
        Write-Host (Format-ValidationStatusLine -Status 'running' -Name $profileName -Detail 'IN PROGRESS' -IndentLevel $IndentLevel)
    }
    try {
        $deadline = [DateTimeOffset]::UtcNow.AddSeconds(30)
        while ($null -eq $runtime) {
            try {
                $runtimeResponse = $http.GetAsync("$baseUrl/runtime-config").GetAwaiter().GetResult()
                if ($runtimeResponse.StatusCode -ne 200) { throw 'Server runtime configuration was not available' }
                $runtime = $runtimeResponse.Content.ReadAsStringAsync().GetAwaiter().GetResult() | ConvertFrom-Json
            }
            catch [Net.Http.HttpRequestException] {
                if ([DateTimeOffset]::UtcNow -gt $deadline -or $serverJob.State -in @('Failed', 'Completed')) {
                    throw "$profile server did not start"
                }
                Start-Sleep -Milliseconds 50
            }
        }
        $text = "$($candidate.recommendation.ruleText) Responsive $profile check."
        $pending = $http.SendAsync((New-FixtureRequest POST "$baseUrl/reconcile-rule" (New-FixturePayload $text $runtime.savedRuleAuthoritySha256) $runtime.operationToken))
        $worker = Wait-FixtureWorker $controlDirectory $text $pending
        if ($worker.model -cne $expectedModel -or $worker.effort -cne $expectedEffort) {
            throw "$profile did not use its independent saved-rule profile for discovery"
        }
        foreach ($path in @('/icons/codicons/sprite.svg', '/styles.css', '/', '/runtime-config', '/shutdown-config')) {
            $response = Receive-FixtureResponse ($http.GetAsync("$baseUrl$path"))
            if ($response.StatusCode -ne 200 -or $pending.IsCompleted) { throw "$profile did not serve $path while validation was running" }
        }
        $head = Receive-FixtureResponse ($http.SendAsync((New-FixtureRequest HEAD "$baseUrl/icons/codicons/sprite.svg")))
        if ($head.StatusCode -ne 200 -or $head.Content.ReadAsByteArrayAsync().GetAwaiter().GetResult().Length -ne 0) {
            throw "$profile did not preserve HEAD behavior during validation"
        }
        $unauthorized = Receive-FixtureResponse ($http.SendAsync((New-FixtureRequest POST "$baseUrl/reconcile-rule" '{"payloadBase64":"e30="}')))
        $foreignHost = New-FixtureRequest GET "$baseUrl/styles.css"
        $foreignHost.Headers.Host = 'attacker.example'
        $misdirected = Receive-FixtureResponse ($http.SendAsync($foreignHost))
        if ($unauthorized.StatusCode -ne 403 -or $misdirected.StatusCode -ne 421) { throw "$profile weakened request authorization during validation" }
        $queuedText = "$($candidate.recommendation.ruleText) Queued $profile check."
        $queued = $http.SendAsync((New-FixtureRequest POST "$baseUrl/reconcile-rule" (New-FixturePayload $queuedText $runtime.savedRuleAuthoritySha256) $runtime.operationToken))
        $null = Receive-FixtureResponse ($http.GetAsync("$baseUrl/styles.css"))
        $queuedHash = [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData([Text.Encoding]::UTF8.GetBytes($queuedText))).ToLowerInvariant()
        if ($queued.IsCompleted -or (Test-Path -LiteralPath (Join-Path $controlDirectory "started-$queuedHash.json"))) {
            throw "$profile did not preserve serialized evaluator ownership"
        }
        [IO.File]::WriteAllText((Join-Path $controlDirectory 'release'), 'release')
        foreach ($task in @($pending, $queued)) {
            $response = Receive-FixtureResponse $task 20000
            $json = $response.Content.ReadAsStringAsync().GetAwaiter().GetResult()
            $schema = Join-Path $repositoryRoot 'hosted_copilot/contracts/reconciliation/saved-rule-evaluation.schema.json'
            if ($response.StatusCode -ne 200) {
                $failure = $json | ConvertFrom-Json
                throw "$profile saved-rule evaluation failed with HTTP $([int]$response.StatusCode): $($failure.error)"
            }
            if (-not ($json | Test-Json -SchemaFile $schema -ErrorAction Stop)) { throw "$profile did not publish a validated result" }
        }
        $adjudicationMetrics = @(Get-Content -LiteralPath (Join-Path $profileDirectory 'adjudication-metrics.jsonl') | ForEach-Object { $_ | ConvertFrom-Json })
        if ($adjudicationMetrics.Count -ne 2 -or @($adjudicationMetrics | Where-Object {
            $_.model -cne $expectedModel -or $_.effort -cne $expectedEffort
        }).Count -ne 0) {
            throw "$profile did not use its independent saved-rule profile for adjudication"
        }
        Assert-FixtureWorkersStopped $worker
        $invalid = Receive-FixtureResponse ($http.SendAsync((New-FixtureRequest POST "$baseUrl/reconcile-rule" (New-FixturePayload $text ('0' * 64)) $runtime.operationToken))) 10000
        $failure = $invalid.Content.ReadAsStringAsync().GetAwaiter().GetResult() | ConvertFrom-Json
        if ($invalid.StatusCode -ne 500 -or $failure.error -notlike '*authority changed*') { throw "$profile did not surface evaluator failure through HTTP" }
        Remove-Item -LiteralPath (Join-Path $controlDirectory 'release')
        $cancelText = "$($candidate.recommendation.ruleText) Cancel $profile check."
        $cancelled = $http.SendAsync((New-FixtureRequest POST "$baseUrl/reconcile-rule" (New-FixturePayload $cancelText $runtime.savedRuleAuthoritySha256) $runtime.operationToken), $cancellation.Token)
        $cancelWorker = Wait-FixtureWorker $controlDirectory $cancelText $cancelled
        $cancellation.Cancel()
        Assert-FixtureWorkersStopped $cancelWorker
        $null = Receive-FixtureResponse ($http.GetAsync("$baseUrl/icons/codicons/sprite.svg"))
        $shutdownText = "$($candidate.recommendation.ruleText) Shutdown $profile check."
        $shutdownPending = $http.SendAsync((New-FixtureRequest POST "$baseUrl/reconcile-rule" (New-FixturePayload $shutdownText $runtime.savedRuleAuthoritySha256) $runtime.operationToken))
        $shutdownWorker = Wait-FixtureWorker $controlDirectory $shutdownText $shutdownPending
        Move-Item -LiteralPath (Join-Path $siteDirectory 'workbench-display.json') -Destination (Join-Path $profileDirectory 'unavailable-display.json')
        $brokenRuntime = Receive-FixtureResponse ($http.GetAsync("$baseUrl/runtime-config"))
        if ($brokenRuntime.StatusCode -ne 500) { throw "$profile fixture did not make evaluator configuration unavailable" }
        $shutdownHead = Receive-FixtureResponse ($http.SendAsync((New-FixtureRequest HEAD "$baseUrl/shutdown-config")))
        if ($shutdownHead.StatusCode -ne 200 -or $shutdownHead.Content.ReadAsByteArrayAsync().GetAwaiter().GetResult().Length -ne 0) {
            throw "$profile shutdown configuration did not preserve HEAD while evaluation configuration was broken"
        }
        $shutdownResponse = Receive-FixtureResponse ($http.GetAsync("$baseUrl/shutdown-config"))
        if ($shutdownResponse.StatusCode -ne 200 -or -not $shutdownResponse.Headers.CacheControl.NoStore) {
            throw "$profile shutdown configuration was unavailable or cacheable"
        }
        $shutdownConfig = $shutdownResponse.Content.ReadAsStringAsync().GetAwaiter().GetResult() | ConvertFrom-Json
        if (@($shutdownConfig.PSObject.Properties).Count -ne 1 -or $shutdownConfig.shutdownToken -cne $runtime.shutdownToken) {
            throw "$profile shutdown configuration did not return only its server-owned shutdown capability"
        }
        $invalidShutdown = New-FixtureRequest POST "$baseUrl/shutdown"
        $invalidShutdown.Headers.Add('X-Workbench-Shutdown-Token', 'invalid')
        $invalidShutdownResponse = Receive-FixtureResponse ($http.SendAsync($invalidShutdown))
        if ($invalidShutdownResponse.StatusCode -ne 403) { throw "$profile shutdown accepted an invalid capability" }
        $shutdown = New-FixtureRequest POST "$baseUrl/shutdown"
        $shutdown.Headers.Add('X-Workbench-Shutdown-Token', [string]$shutdownConfig.shutdownToken)
        $response = Receive-FixtureResponse ($http.SendAsync($shutdown))
        if ($response.StatusCode -ne 200 -or -not (Wait-Job -Job $serverJob -Timeout 10)) { throw "$profile did not shut down during evaluation" }
        Assert-FixtureWorkersStopped $shutdownWorker
        $null = Receive-Job -Job $serverJob -ErrorAction Stop
        if ($serverJob.State -ne 'Completed') { throw "$profile server did not finish cleanly" }
        if (-not $Quiet) {
            Write-Host (Format-ValidationStatusLine -Status 'passed' -Name $profileName -Detail (Format-ValidationDuration -DurationSeconds $profileStopwatch.Elapsed.TotalSeconds) -IndentLevel $IndentLevel)
        }
    }
    catch {
        if (-not $Quiet) {
            Write-Host (Format-ValidationStatusLine -Status 'failed' -Name $profileName -Detail (Format-ValidationDuration -DurationSeconds $profileStopwatch.Elapsed.TotalSeconds) -IndentLevel $IndentLevel)
        }
        throw
    }
    finally {
        $http.Dispose()
        $cancellation.Dispose()
        if ($serverJob.State -notin @('Completed', 'Failed', 'Stopped')) {
            if ($null -ne $runtime) {
                $cleanup = [Net.Http.HttpClient]::new()
                $cleanup.Timeout = [TimeSpan]::FromSeconds(5)
                try {
                    $shutdown = New-FixtureRequest POST "$baseUrl/shutdown"
                    $shutdown.Headers.Add('X-Workbench-Shutdown-Token', [string]$runtime.shutdownToken)
                    $null = $cleanup.SendAsync($shutdown).GetAwaiter().GetResult()
                    $null = Wait-Job -Job $serverJob -Timeout 10
                }
                finally { $cleanup.Dispose() }
            }
            if ($serverJob.State -notin @('Completed', 'Failed', 'Stopped')) { Stop-Job -Job $serverJob }
        }
        Remove-Job -Job $serverJob -Force
        foreach ($message in $messages) { $message.Dispose() }
        $messages.Clear()
    }
}
