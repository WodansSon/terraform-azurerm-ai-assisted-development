Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Import-Module (Join-Path $PSScriptRoot '../shared/HostedToolkit.Helpers.psm1')

function Get-SavedRuleAuthoritySha256 {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$RepositoryRoot,
        [Parameter(Mandatory = $true)][string]$DisplayPath,
        [Parameter(Mandatory = $true)][string]$RuleIssuesPath,
        [string]$EvaluatorCommand = 'copilot',
        [ValidateNotNullOrEmpty()][string]$Model,
        [ValidateSet('low', 'medium', 'high', 'xhigh')][string]$ReasoningEffort,
        [string]$RelationshipEvaluatorScriptPath,
        [string]$AdjudicationEvaluatorScriptPath
    )

    $llmProfile = Resolve-HostedLlmProfile -Profile savedRuleEvaluation -Model $Model -ReasoningEffort $ReasoningEffort
    $Model = $llmProfile.model
    $ReasoningEffort = $llmProfile.reasoningEffort
    $contractPath = Join-Path $RepositoryRoot 'hosted_copilot/contracts/reconciliation/rule-issue-adjudication-v4.json'
    $contract = Get-Content -LiteralPath $contractPath -Raw | ConvertFrom-Json
    $paths = @($contract.behaviorFiles) + @(
        'hosted_copilot/copilot-rule-catalog/instruction-catalog.json',
        'hosted_copilot/copilot-rule-catalog/protected-rules.json',
        'hosted_copilot/contracts/reconciliation/manual-rule-relationship.schema.json',
        'hosted_copilot/contracts/reconciliation/saved-rule-evaluation.schema.json',
        'hosted_copilot/tools/prompts/reconciliation/ManualRuleRelationship-v4.md',
        'hosted_copilot/tools/internal/reconciliation/Invoke-ManualRuleRelationship.ps1',
        'hosted_copilot/tools/internal/reconciliation/Invoke-SavedRuleEvaluation.ps1',
        'hosted_copilot/tools/modules/workbench/SavedRuleEvaluation.psm1'
    )
    $files = @($paths | Sort-Object -CaseSensitive -Unique | ForEach-Object {
        [ordered]@{ path = $_; sha256 = Get-Sha256 -Path (Join-Path $RepositoryRoot $_) }
    })
    return Get-JsonSnapshotSha256 -Value ([ordered]@{
        files = $files
        display = Get-Sha256 -Path $DisplayPath
        ruleIssues = Get-Sha256 -Path $RuleIssuesPath
        evaluator = $EvaluatorCommand
        model = $Model
        reasoningEffort = $ReasoningEffort
        checkerFixture = if ([string]::IsNullOrWhiteSpace($RelationshipEvaluatorScriptPath)) { $null } else { Get-Sha256 -Path $RelationshipEvaluatorScriptPath }
        adjudicatorFixture = if ([string]::IsNullOrWhiteSpace($AdjudicationEvaluatorScriptPath)) { $null } else { Get-Sha256 -Path $AdjudicationEvaluatorScriptPath }
    })
}

function Invoke-SavedRuleEvaluationProcess {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$ScriptPath,
        [Parameter(Mandatory = $true)][Collections.IDictionary]$Parameters,
        [Net.Sockets.Socket]$ClientSocket,
        [string]$OperationName = 'Scoped relationship check'
    )

    $startInfo = [Diagnostics.ProcessStartInfo]::new('pwsh')
    $startInfo.UseShellExecute = $false
    $startInfo.CreateNoWindow = $true
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true
    $startInfo.StandardOutputEncoding = [Text.Encoding]::UTF8
    $startInfo.StandardErrorEncoding = [Text.Encoding]::UTF8
    foreach ($argument in @('-NoProfile', '-NonInteractive', '-File', $ScriptPath)) {
        $startInfo.ArgumentList.Add($argument)
    }
    foreach ($key in $Parameters.Keys) {
        if ($key -in @('EvaluatorScriptPath', 'AdjudicationEvaluatorScriptPath') -and [string]::IsNullOrWhiteSpace([string]$Parameters[$key])) { continue }
        $startInfo.ArgumentList.Add("-$key")
        $startInfo.ArgumentList.Add([string]$Parameters[$key])
    }
    $process = [Diagnostics.Process]::new()
    $process.StartInfo = $startInfo
    $started = $false
    try {
        if ($null -ne $ClientSocket -and $ClientSocket.Poll(0, [Net.Sockets.SelectMode]::SelectRead) -and $ClientSocket.Available -eq 0) {
            throw [OperationCanceledException]::new("$OperationName cancelled before its worker started")
        }
        $started = $process.Start()
        $stdout = $process.StandardOutput.ReadToEndAsync()
        $stderr = $process.StandardError.ReadToEndAsync()
        do {
            $completed = $process.WaitForExit(100)
            if ($null -ne $ClientSocket) {
                try {
                    $disconnected = $ClientSocket.Poll(0, [Net.Sockets.SelectMode]::SelectRead) -and $ClientSocket.Available -eq 0
                }
                catch [Net.Sockets.SocketException] {
                    $disconnected = $true
                }
                if ($disconnected) {
                    throw [OperationCanceledException]::new("$OperationName cancelled because its client disconnected")
                }
            }
        } while (-not $completed)
        $output = @($stdout.GetAwaiter().GetResult(), $stderr.GetAwaiter().GetResult()) -split '\r?\n'
        if ($process.ExitCode -ne 0 -or -not (Test-Path -LiteralPath $Parameters.OutputPath -PathType Leaf)) {
            if ($OperationName -ceq 'Rule assistance') {
                $failures = @(
                    foreach ($line in $output) {
                        try {
                            $value = $line | ConvertFrom-Json -Depth 10 -DateKind String
                            $failure = $value.error
                            if ((($failure.PSObject.Properties.Name | Sort-Object -CaseSensitive) -join ',') -cne 'code,diagnosticId,message') { continue }
                            if ($failure.code -isnot [string] -or $failure.code -cnotmatch '^[a-z][a-z0-9-]{0,63}$' -or $failure.message -isnot [string] -or
                                [string]::IsNullOrWhiteSpace($failure.message) -or $failure.message.Length -gt 2000 -or $failure.message -match '[\x00-\x08\x0b\x0c\x0e-\x1f]' -or
                                ($null -ne $failure.diagnosticId -and ($failure.diagnosticId -isnot [string] -or $failure.diagnosticId -cnotmatch '^[a-f0-9]{32}$'))) { continue }
                            $failure
                        }
                        catch { }
                    }
                )
                $failure = if ($failures.Count -eq 1) { $failures[0] } else {
                    [pscustomobject]@{ code = 'rule-assistance-failed'; message = 'The AI chat request could not be completed.'; diagnosticId = $null }
                }
                $exception = [InvalidOperationException]::new($failure.message)
                $exception.Data['RuleAssistanceError'] = $failure
                throw $exception
            }
            throw (Get-EvaluatorFailureMessage -EvaluatorName $OperationName -ExitCode $process.ExitCode -Output $output)
        }
    }
    finally {
        if ($started -and -not $process.HasExited) {
            try { $process.Kill($true) }
            catch [InvalidOperationException] { if (-not $process.HasExited) { throw } }
            $process.WaitForExit()
        }
        $process.Dispose()
    }
}

function Start-SavedRuleEvaluationRequest {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][Management.Automation.Runspaces.RunspacePool]$RunspacePool,
        [Parameter(Mandatory = $true)][string]$ScriptPath,
        [Parameter(Mandatory = $true)][Collections.IDictionary]$Parameters,
        [Parameter(Mandatory = $true)][Net.Sockets.TcpClient]$Client,
        [string]$OperationName = 'Scoped relationship check',
        [string]$CleanupDirectory
    )

    $worker = [Management.Automation.PowerShell]::Create()
    try {
        $worker.RunspacePool = $RunspacePool
        $null = $worker.AddScript({
            param($ModulePath, $ScriptPath, $Parameters, $ClientSocket, $OperationName)
            Set-StrictMode -Version Latest
            $ErrorActionPreference = 'Stop'
            Import-Module $ModulePath
            Invoke-SavedRuleEvaluationProcess -ScriptPath $ScriptPath -Parameters $Parameters -ClientSocket $ClientSocket -OperationName $OperationName
        }).AddArgument($MyInvocation.MyCommand.Module.Path).AddArgument($ScriptPath).AddArgument($Parameters).AddArgument($Client.Client).AddArgument($OperationName)
        return [pscustomobject]@{
            Worker = $worker
            Completion = $worker.BeginInvoke()
            Client = $Client
            RequestPath = $Parameters.RequestPath
            OutputPath = $Parameters.OutputPath
            OperationName = $OperationName
            CleanupDirectory = $CleanupDirectory
        }
    }
    catch {
        $worker.Dispose()
        throw
    }
}

function Remove-SavedRuleEvaluationRequest {
    param([Parameter(Mandatory = $true)][object]$Request)

    $Request.Worker.Dispose()
    $Request.Client.Dispose()
    foreach ($path in @($Request.RequestPath, $Request.OutputPath)) {
        if ([IO.File]::Exists($path)) { [IO.File]::Delete($path) }
    }
    if ($Request.CleanupDirectory -and [IO.Directory]::Exists($Request.CleanupDirectory)) {
        Remove-Item -LiteralPath $Request.CleanupDirectory -Recurse -Force
    }
}

function Receive-SavedRuleEvaluationRequests {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][Collections.Generic.List[object]]$Requests,
        [Parameter(Mandatory = $true)][scriptblock]$WriteResponse
    )

    for ($index = $Requests.Count - 1; $index -ge 0; $index--) {
        $request = $Requests[$index]
        if (-not $request.Completion.IsCompleted) { continue }
        try {
            $response = $null
            try {
                $null = $request.Worker.EndInvoke($request.Completion)
                $response = @{
                    StatusCode = 200
                    StatusText = 'OK'
                    Body = [IO.File]::ReadAllBytes($request.OutputPath)
                }
            }
            catch {
                $exception = $_.Exception.GetBaseException()
                if ($exception -is [OperationCanceledException]) {
                    Write-Verbose $exception.Message
                }
                else {
                    if ($request.OperationName -ceq 'Rule assistance') {
                        $failure = $exception.Data['RuleAssistanceError']
                        if ($null -eq $failure) { $failure = [ordered]@{ code = 'rule-assistance-failed'; message = 'The AI chat request could not be completed.'; diagnosticId = $null } }
                        Write-Warning "Rule assistance failed: $($failure.code). Diagnostic reference: $($failure.diagnosticId)"
                        $failureBody = [ordered]@{ error = $failure } | ConvertTo-Json -Depth 5 -Compress
                    }
                    else {
                        Write-Warning "$($request.OperationName) failed: $($exception.Message)"
                        $failureBody = [ordered]@{ error = [string]$exception.Message } | ConvertTo-Json -Compress
                    }
                    $response = @{
                        StatusCode = 500
                        StatusText = 'Internal Server Error'
                        Body = [Text.Encoding]::UTF8.GetBytes($failureBody)
                    }
                }
            }
            if ($null -ne $response) {
                try {
                    & $WriteResponse -Stream $request.Client.GetStream() @response -ContentType 'application/json; charset=utf-8' -IncludeBody $true
                }
                catch [IO.IOException] {
                    Write-Verbose "Scoped relationship response connection closed: $($_.Exception.Message)"
                }
                catch [Net.Sockets.SocketException] {
                    Write-Verbose "Scoped relationship response connection closed: $($_.Exception.Message)"
                }
            }
        }
        finally {
            Remove-SavedRuleEvaluationRequest -Request $request
            $Requests.RemoveAt($index)
        }
    }
}

function Stop-SavedRuleEvaluationRequests {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][AllowEmptyCollection()][Collections.Generic.List[object]]$Requests)

    foreach ($request in $Requests) {
        try { $request.Worker.Stop() }
        finally { Remove-SavedRuleEvaluationRequest -Request $request }
    }
    $Requests.Clear()
}

Export-ModuleMember -Function Get-SavedRuleAuthoritySha256, Invoke-SavedRuleEvaluationProcess, Start-SavedRuleEvaluationRequest, Receive-SavedRuleEvaluationRequests, Stop-SavedRuleEvaluationRequests
