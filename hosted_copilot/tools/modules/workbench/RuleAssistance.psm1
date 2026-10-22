Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Import-Module (Join-Path $PSScriptRoot '../shared/HostedToolkit.Helpers.psm1')
Import-Module (Join-Path $PSScriptRoot 'SavedRuleEvaluation.psm1')

function New-RuleAssistanceException {
    param([Parameter(Mandatory)][string]$Message, [string]$Code = 'rule-assistance-failed')

    $exception = [InvalidOperationException]::new($Message)
    $exception.Data['RuleAssistancePublicError'] = $true
    $exception.Data['RuleAssistanceCode'] = $Code
    return $exception
}

function ConvertTo-RuleAssistanceError {
    param(
        [Parameter(Mandatory)][Management.Automation.ErrorRecord]$ErrorRecord,
        [Parameter(Mandatory)][Collections.IDictionary]$Diagnostic
    )

    $exception = $ErrorRecord.Exception.GetBaseException()
    $known = $exception.Data['RuleAssistancePublicError'] -eq $true
    $code = if ($known) { [string]$exception.Data['RuleAssistanceCode'] } else { 'rule-assistance-failed' }
    $message = if ($known) { $exception.Message } else { 'Rule assistance could not complete. No changes were applied by this request.' }
    $Diagnostic['code'] = $code
    $Diagnostic['message'] = $message
    $reference = [string]$Diagnostic['diagnosticId']
    try {
        $directory = Join-Path ([IO.Path]::GetTempPath()) 'hosted-rule-assistance-diagnostics'
        $null = [IO.Directory]::CreateDirectory($directory)
        [IO.File]::WriteAllText((Join-Path $directory "$reference.json"), ($Diagnostic | ConvertTo-Json -Depth 10 -Compress), [Text.UTF8Encoding]::new($false))
    }
    catch { $reference = $null }
    return [ordered]@{ code = $code; message = $message; diagnosticId = $reference }
}

function Get-RuleAssistanceCliAnswer {
    param(
        [Parameter(Mandatory)][AllowEmptyString()][string]$Output,
        [Parameter(Mandatory)][string]$Model,
        [Parameter(Mandatory)][Collections.IDictionary]$Diagnostic
    )

    $message = $null
    $completedMessage = $null
    $turnCount = 0
    $resultCount = 0
    foreach ($line in ($Output -split '\r?\n' | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })) {
        try { $event = $line | ConvertFrom-Json -Depth 100 -DateKind String }
        catch { throw (New-RuleAssistanceException -Message 'Rule assistance CLI returned invalid JSONL; no reply was accepted' -Code 'invalid-response') }
        if ($null -eq $event -or $event -is [array] -or $null -eq $event.PSObject.Properties['type'] -or $event.type -isnot [string]) {
            throw (New-RuleAssistanceException -Message 'Rule assistance CLI returned an invalid event; no reply was accepted' -Code 'invalid-response')
        }
        $eventKey = if ($Diagnostic.events.Contains($event.type)) { $event.type } else { 'other' }
        $Diagnostic.events[$eventKey]++
        if ($event.type -clike 'tool.*') {
            throw (New-RuleAssistanceException -Message 'Rule assistance CLI attempted a tool operation; no reply was accepted' -Code 'tool-operation')
        }
        if ($event.type -cin @('session.error', 'error', 'session.abort')) {
            throw (New-RuleAssistanceException -Message 'The local Copilot CLI reported a failed or aborted response. No reply was accepted.' -Code 'cli-response-error')
        }
        if ($event.type -cin @('assistant.message', 'assistant.turn_end', 'result') -and
            $null -ne $event.PSObject.Properties['agentId'] -and -not [string]::IsNullOrEmpty([string]$event.agentId)) {
            throw (New-RuleAssistanceException -Message 'Rule assistance CLI returned a nested-agent response; no reply was accepted' -Code 'invalid-response')
        }
        if ($event.type -ceq 'assistant.message') {
            $Diagnostic.answerCount++
            if ($turnCount -ne 0 -or $resultCount -ne 0) {
                throw (New-RuleAssistanceException -Message 'Rule assistance CLI returned another message after its completed turn; no reply was accepted' -Code 'ambiguous-response')
            }
            if ($event.data.model -cne $Model) {
                throw (New-RuleAssistanceException -Message 'Rule assistance CLI returned an unexpected model' -Code 'unexpected-model')
            }
            if ($null -ne $event.data.PSObject.Properties['toolRequests'] -and $null -ne $event.data.toolRequests -and @($event.data.toolRequests).Count -gt 0) {
                throw (New-RuleAssistanceException -Message 'Rule assistance CLI attempted a tool operation; no reply was accepted' -Code 'tool-operation')
            }
            $message = $event.data
        }
        elseif ($event.type -ceq 'assistant.turn_end') {
            $turnCount++
            if ($turnCount -ne 1 -or $resultCount -ne 0 -or $null -eq $message) {
                throw (New-RuleAssistanceException -Message 'Rule assistance CLI did not return one unambiguous completed turn; no reply was accepted' -Code 'ambiguous-response')
            }
            $completedMessage = $message
            $message = $null
        }
        elseif ($event.type -ceq 'result') {
            $resultCount++
            if ($resultCount -ne 1 -or $turnCount -ne 1 -or $null -eq $completedMessage) {
                throw (New-RuleAssistanceException -Message 'Rule assistance CLI returned an invalid or duplicate completion; no reply was accepted' -Code 'ambiguous-response')
            }
        }
    }
    if ($null -eq $completedMessage -or $turnCount -ne 1 -or $resultCount -ne 1) {
        throw (New-RuleAssistanceException -Message 'The local Copilot CLI did not complete its response. No reply was accepted.' -Code 'incomplete-response')
    }
    if ($null -eq $completedMessage.PSObject.Properties['content'] -or $completedMessage.content -isnot [string] -or [string]::IsNullOrWhiteSpace($completedMessage.content)) {
        throw (New-RuleAssistanceException -Message 'Rule assistance CLI completed with an empty final message; no reply was accepted' -Code 'invalid-response')
    }
    return $completedMessage.content
}

function Get-RuleAssistanceRuntime {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$RepositoryRoot,
        [Parameter(Mandatory)][string]$DisplayPath,
        [Parameter(Mandatory)][string]$EvaluatorCommand,
        [Parameter(Mandatory)][string]$Model,
        [Parameter(Mandatory)][string]$ReasoningEffort
    )

    $files = @(
        'hosted_copilot/tools/workbench-prompts/RuleAssistance.md',
        'hosted_copilot/tools/workbench-prompts/rule-assistance-result.schema.json',
        'hosted_copilot/tools/modules/workbench/RuleAssistance.psm1',
        'hosted_copilot/tools/internal/workbench/Invoke-RuleAssistance.ps1'
        'hosted_copilot/tools/modules/shared/HostedCli.psm1'
    ) | ForEach-Object { [ordered]@{ path = $_; sha256 = Get-Sha256 -Path (Join-Path $RepositoryRoot $_) } }
    $display = Get-Content -LiteralPath $DisplayPath -Raw | ConvertFrom-Json -Depth 100 -DateKind String
    return [ordered]@{
        model = $Model
        reasoningEffort = $ReasoningEffort
        maximumPromptBytes = 393216
        displaySha256 = Get-Sha256 -Path $DisplayPath
        catalogSha256 = $display.catalog.contentSha256
        protectedRulesSha256 = $display.catalog.protectedRulesContentSha256
        authoritySha256 = Get-JsonSnapshotSha256 -Value ([ordered]@{
            files = @($files); display = Get-Sha256 -Path $DisplayPath
            evaluator = $EvaluatorCommand; model = $Model; effort = $ReasoningEffort
        })
    }
}

function Start-RuleAssistanceRequest {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][Management.Automation.Runspaces.RunspacePool]$RunspacePool,
        [Parameter(Mandatory)][Net.Sockets.TcpClient]$Client,
        [Parameter(Mandatory)][string]$RequestBody,
        [Parameter(Mandatory)][Collections.IDictionary]$Parameters
    )

    $envelope = $RequestBody | ConvertFrom-Json -Depth 100 -DateKind String
    if (@($envelope.PSObject.Properties.Name).Count -ne 1 -or $null -eq $envelope.PSObject.Properties['payloadBase64']) {
        throw (New-RuleAssistanceException -Message 'Rule assistance request envelope is invalid' -Code 'invalid-request')
    }
    $bytes = [Convert]::FromBase64String([string]$envelope.payloadBase64)
    if ($bytes.Length -lt 1 -or $bytes.Length -gt 524288) { throw (New-RuleAssistanceException -Message 'Rule assistance request exceeds its input limit' -Code 'invalid-request') }
    $null = [Text.UTF8Encoding]::new($false, $true).GetString($bytes)
    $directory = Join-Path ([IO.Path]::GetTempPath()) "hosted-rule-assistance-$([Guid]::NewGuid().ToString('N'))"
    $null = New-Item -ItemType Directory -Path $directory
    try {
        $workerParameters = @{} + $Parameters
        $workerParameters.RequestPath = Join-Path $directory 'request.json'
        $workerParameters.OutputPath = Join-Path $directory 'response.json'
        [IO.File]::WriteAllBytes($workerParameters.RequestPath, $bytes)
        $scriptPath = Join-Path $Parameters.RepositoryRoot 'hosted_copilot/tools/internal/workbench/Invoke-RuleAssistance.ps1'
        return Start-SavedRuleEvaluationRequest -RunspacePool $RunspacePool -ScriptPath $scriptPath -Parameters $workerParameters -Client $Client -OperationName 'Rule assistance' -CleanupDirectory $directory
    }
    catch {
        Remove-Item -LiteralPath $directory -Recurse -Force
        throw
    }
}

Export-ModuleMember -Function Get-RuleAssistanceRuntime, Start-RuleAssistanceRequest, New-RuleAssistanceException, ConvertTo-RuleAssistanceError, Get-RuleAssistanceCliAnswer
