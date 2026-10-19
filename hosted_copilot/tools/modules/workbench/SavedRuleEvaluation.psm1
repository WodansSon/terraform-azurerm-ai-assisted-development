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
        [string]$Model = 'gpt-6-luna',
        [string]$ReasoningEffort = 'medium',
        [string]$RelationshipEvaluatorScriptPath,
        [string]$AdjudicationEvaluatorScriptPath
    )

    $contractPath = Join-Path $RepositoryRoot 'hosted_copilot/copilot-rule-catalog/assessment-reconciliation/rule-issue-adjudication-v4.json'
    $contract = Get-Content -LiteralPath $contractPath -Raw | ConvertFrom-Json
    $paths = @($contract.behaviorFiles) + @(
        'hosted_copilot/copilot-rule-catalog/instruction-catalog.json',
        'hosted_copilot/copilot-rule-catalog/protected-rules.json',
        'hosted_copilot/copilot-rule-catalog/assessment-reconciliation/manual-rule-relationship.schema.json',
        'hosted_copilot/copilot-rule-catalog/assessment-reconciliation/saved-rule-evaluation.schema.json',
        'hosted_copilot/tools/assessment-reconciliation-prompts/ManualRuleRelationship-v4.md',
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
                    Write-Warning "$($request.OperationName) failed: $($exception.Message)"
                    $failureBody = [ordered]@{ error = [string]$exception.Message } | ConvertTo-Json -Compress
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
