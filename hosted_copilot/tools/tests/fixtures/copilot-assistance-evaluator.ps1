Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ('--headless' -cin @($args)) {
    & (Join-Path $PSScriptRoot 'copilot-metadata-evaluator.ps1') @args
    return
}

Import-Module (Join-Path $PSScriptRoot '../../modules/shared/HostedToolkit.Helpers.psm1')

$arguments = @($args)
$modelIndex = [Array]::IndexOf($arguments, '--model')
$effortIndex = [Array]::IndexOf($arguments, '--reasoning-effort')
$toolsIndex = [Array]::IndexOf($arguments, '--available-tools')
if ($modelIndex -lt 0 -or $effortIndex -lt 0 -or $toolsIndex -lt 0 -or $arguments[$toolsIndex + 1] -cne '--output-format' -or '-p' -cin $arguments) {
    throw 'Assistance CLI arguments did not preserve the inline no-tools boundary'
}
$prompt = [Console]::In.ReadToEnd()
$marker = "`n## Supplied Context`n"
$offset = $prompt.LastIndexOf($marker, [StringComparison]::Ordinal)
if ($offset -lt 0 -or -not $prompt.Contains('## Boundaries', [StringComparison]::Ordinal)) { throw 'Assistance prompt boundaries are missing' }
$context = $prompt.Substring($offset + $marker.Length) | ConvertFrom-Json -Depth 100 -DateKind String
$question = [string]$context.messages[-1].content
$isRuleIssue = $context.viewKind -ceq 'rule-issues'
$control = [Environment]::GetEnvironmentVariable('HOSTED_ASSISTANCE_TEST_CONTROL')
if ([string]::IsNullOrWhiteSpace($control)) { throw 'Synthetic assistance requires an isolated test control directory' }
$metrics = [ordered]@{
    model = $arguments[$modelIndex + 1]; effort = $arguments[$effortIndex + 1]
    bytes = [Text.Encoding]::UTF8.GetByteCount($prompt)
    ruleIds = @($context.catalog.id); messageCount = @($context.messages).Count
    sourceCount = if ($isRuleIssue) { @($context.candidateEvidence | ForEach-Object { $_.members }).Count } else { @($context.sources).Count }; workingDirectory = (Get-Location).Path
    guidanceCapacity = $context.guidanceCapacity
    viewKind = $context.viewKind
}
if ($isRuleIssue) {
    $metrics.ruleIssueSha256 = Get-JsonSnapshotSha256 -Value $context.ruleIssue -Depth 100
    $metrics.candidateEvidenceSha256 = Get-JsonSnapshotSha256 -Value @($context.candidateEvidence) -Depth 100
    $metrics.promptSelected = $prompt.StartsWith('# Hosted Rule Issue Assistance', [StringComparison]::Ordinal)
} else {
    $metrics.promptSelected = if ($context.viewKind -ceq 'assessment-results') { $prompt.Contains('# Hosted Assessment Assistance', [StringComparison]::Ordinal) } else { -not $prompt.Contains('# Hosted Assessment Assistance', [StringComparison]::Ordinal) }
    $evidenceMetrics = [ordered]@{
    parentAssessmentSha256 = Get-JsonSnapshotSha256 -Value $context.recordedAssessment.assessment -Depth 100
    recommendationSha256 = Get-JsonSnapshotSha256 -Value $context.recordedAssessment.recommendation -Depth 100
    sourceEvidenceSha256 = Get-JsonSnapshotSha256 -Value @($context.sources) -Depth 100
    selectionDefinitionsSha256 = Get-JsonSnapshotSha256 -Value $context.scoringDefinitions.selectionFactors -Depth 100
    coverageDefinitionsSha256 = Get-JsonSnapshotSha256 -Value $context.scoringDefinitions.existingCoverage -Depth 100
    assessedTextSha256 = $context.recordedAssessment.assessedTextSha256
    baselineTextSha256 = Get-Sha256 -Content $context.currentRule.baselineText
    proposedTextSha256 = Get-Sha256 -Content $context.currentRule.proposedText
    matchesCurrentWording = $context.recordedAssessment.matchesCurrentWording
    }
    foreach ($entry in $evidenceMetrics.GetEnumerator()) { $metrics[$entry.Key] = $entry.Value }
}
[IO.File]::AppendAllText((Join-Path $control 'metrics.jsonl'), (($metrics | ConvertTo-Json -Depth 100 -Compress) + "`n"))
if ($question -ceq 'hold') {
    $childInfo = [Diagnostics.ProcessStartInfo]::new('pwsh')
    $childInfo.UseShellExecute = $false
    foreach ($argument in @('-NoProfile', '-NonInteractive', '-Command', 'Start-Sleep -Seconds 120')) { $childInfo.ArgumentList.Add($argument) }
    $child = [Diagnostics.Process]::Start($childInfo)
    try {
        [IO.File]::WriteAllText((Join-Path $control 'held.json'), (@{ worker = $PID; child = $child.Id; directory = (Get-Location).Path } | ConvertTo-Json -Compress))
        while (-not (Test-Path -LiteralPath (Join-Path $control 'release'))) { Start-Sleep -Milliseconds 25 }
    }
    finally {
        if (-not $child.HasExited) { $child.Kill($true); $child.WaitForExit() }
        $child.Dispose()
    }
}
if ($question -ceq 'cli-failure') { throw 'Synthetic CLI failure' }
if ($question -ceq 'warning') { [Console]::Error.WriteLine('Synthetic legitimate warning; stdout remains JSONL.') }
if ($question -ceq 'tool-event') { '{"type":"tool.execution_start","data":{}}' }
if ($question -ceq 'no-answer') { '{"type":"session.error","data":{"message":"SYNTHETIC_SENSITIVE_VALUE"}}'; return }
$answer = [ordered]@{ message = 'Synthetic catalog advice <img src=x onerror=alert(1)>.'; suggestedWording = if ($isRuleIssue -and $question -cne 'issue-wording') { $null } else { 'Preserve the selected rule obligations and review the complete proposed wording.' } }
if ($question -ceq 'invalid-shape') { $answer.Remove('message') }
$event = [ordered]@{ type = 'assistant.message'; data = [ordered]@{
    model = if ($question -ceq 'wrong-model') { 'unexpected-model' } else { $arguments[$modelIndex + 1] }
    content = $answer | ConvertTo-Json -Compress
} }
if ($question -cin @('multiple-messages', 'two-structured-messages')) {
    $commentary = if ($question -ceq 'two-structured-messages') { '{"message":"Synthetic intermediate reply","suggestedWording":null}' } else { 'Synthetic commentary before the final response.' }
    @{ type = 'assistant.message'; data = @{ model = $arguments[$modelIndex + 1]; content = $commentary } } | ConvertTo-Json -Depth 10 -Compress
}
if ($question -ceq 'empty-intermediate') {
    @{ type = 'assistant.message'; data = @{ model = $arguments[$modelIndex + 1]; content = ''; reasoningText = 'Synthetic intermediate reasoning' } } | ConvertTo-Json -Depth 10 -Compress
}
if ($question -ceq 'empty-final') {
    $event | ConvertTo-Json -Depth 100 -Compress
    $event.data.content = ''
}
if ($question -ceq 'invalid-final') {
    $event | ConvertTo-Json -Depth 100 -Compress
    $event.data.content = 'Synthetic invalid final JSON'
}
if ($question -ceq 'nested-agent') { $event['agentId'] = 'synthetic-child-agent' }
if ($question -ceq 'embedded-tool-request') { $event.data['toolRequests'] = @(@{ toolCallId = 'synthetic-call'; name = 'synthetic-tool'; arguments = @{} }) }
if ($question -ceq 'null-tool-requests') { $event.data['toolRequests'] = $null }
$serializedEvent = $event | ConvertTo-Json -Depth 100 -Compress
$serializedEvent
if ($question -cne 'missing-turn-end') { '{"type":"assistant.turn_end","data":{}}' }
if ($question -ceq 'multiple-answers') { $serializedEvent; '{"type":"assistant.turn_end","data":{}}' }
if ($question -cne 'missing-result') { '{"type":"result"}' }
if ($question -ceq 'duplicate-result') { '{"type":"result"}' }
if ($question -ceq 'trailing-message') { $serializedEvent }
