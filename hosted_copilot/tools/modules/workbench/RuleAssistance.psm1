Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Import-Module (Join-Path $PSScriptRoot '../shared/HostedToolkit.Helpers.psm1')
Import-Module (Join-Path $PSScriptRoot 'SavedRuleEvaluation.psm1')

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
        throw 'Rule assistance request envelope is invalid'
    }
    $bytes = [Convert]::FromBase64String([string]$envelope.payloadBase64)
    if ($bytes.Length -lt 1 -or $bytes.Length -gt 524288) { throw 'Rule assistance request exceeds its input limit' }
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

Export-ModuleMember -Function Get-RuleAssistanceRuntime, Start-RuleAssistanceRequest
