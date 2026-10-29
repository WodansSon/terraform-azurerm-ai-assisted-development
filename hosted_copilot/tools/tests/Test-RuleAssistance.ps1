[CmdletBinding(DefaultParameterSetName = 'Http')]
param(
    [Parameter(Mandatory)][string]$DisplayPath,
    [Parameter(Mandatory, ParameterSetName = 'Http')][Parameter(ParameterSetName = 'Worker')][string]$RuleIssuesPath,
    [Parameter(Mandatory, ParameterSetName = 'Worker')][switch]$WorkerOnly,
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

$testResults = [Collections.Generic.List[object]]::new()
$currentTestName = 'assistance-inputs'
$suiteStopwatch = [Diagnostics.Stopwatch]::StartNew()
$caseStopwatch = [Diagnostics.Stopwatch]::StartNew()

function Start-AssistanceTest {
    param([string]$Name, [string]$Detail)

    $script:currentTestName = $Name
    $script:caseStopwatch = [Diagnostics.Stopwatch]::StartNew()
    if (-not $Quiet) {
        Write-Host (Format-ValidationStatusLine -Status 'running' -Name $Name -Detail $Detail -IndentLevel $IndentLevel)
    }
}

function Add-AssistanceTestResult {
    param([string]$Name, [string]$Detail)

    $caseStopwatch.Stop()
    $durationSeconds = $caseStopwatch.Elapsed.TotalSeconds
    $testResults.Add([pscustomobject]@{ name = $Name; status = 'passed'; detail = $Detail; durationSeconds = $durationSeconds })
    if (-not $Quiet) {
        Write-Host (Format-ValidationStatusLine -Status 'passed' -Name $Name -Detail (Format-ValidationDuration -DurationSeconds $durationSeconds) -IndentLevel $IndentLevel)
    }
}

function Complete-AssistanceTestOutput {
    $suiteStopwatch.Stop()
    if ($Quiet -or $IndentLevel -gt 0) { return }
    $failures = @($testResults | Where-Object status -CEQ 'failed')
    Write-ValidationSectionHeader -Title 'Hosted rule assistance test summary'
    Write-ValidationSummary -Fields ([ordered]@{ Status = if ($failures.Count) { 'FAILED' } else { 'PASSED' }; Tests = $testResults.Count; Issues = $failures.Count; Elapsed = Format-ValidationDuration -DurationSeconds $suiteStopwatch.Elapsed.TotalSeconds })
    Write-ValidationSectionHeader -Title 'Assistance tests'
    Write-ValidationStatusTable -Rows $testResults.ToArray() -NameHeader 'Test'
    if ($failures.Count) {
        Write-ValidationSectionHeader -Title 'Failures'
        foreach ($failure in $failures) { Write-Output "  - $($failure.name): $($failure.detail)" }
    }
    Complete-ValidationTextOutput
}

trap {
    $caseStopwatch.Stop()
    $durationSeconds = $caseStopwatch.Elapsed.TotalSeconds
    $testResults.Add([pscustomobject]@{ name = $currentTestName; status = 'failed'; detail = $_.Exception.Message; durationSeconds = $durationSeconds })
    if (-not $Quiet) {
        Write-Host (Format-ValidationStatusLine -Status 'failed' -Name $currentTestName -Detail (Format-ValidationDuration -DurationSeconds $durationSeconds) -IndentLevel $IndentLevel)
    }
    Complete-AssistanceTestOutput
    if ($Quiet -or $IndentLevel -gt 0) {
        [Console]::Error.WriteLine("$($currentTestName): $($_.Exception.Message)")
    }
    exit 1
}

if (-not $Quiet -and $IndentLevel -eq 0) { Write-ValidationSectionHeader -Title 'Hosted rule assistance tests' }

$normalProfile = Resolve-HostedLlmProfile -Profile normal
$fixtureCommand = Join-Path $PSScriptRoot 'fixtures/copilot-assistance-evaluator.ps1'
$display = Get-Content -LiteralPath $DisplayPath -Raw | ConvertFrom-Json -Depth 100 -DateKind String
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
if (-not [string]::IsNullOrWhiteSpace($RuleIssuesPath)) { $runtimeParameters.RuleIssuesPath = $RuleIssuesPath }
$runtime = Get-RuleAssistanceRuntime @runtimeParameters

function New-AssistancePayload {
    param([string]$Question, [string]$Authority = $runtime.authoritySha256, [object]$ContextCandidate = $candidate)
    return [ordered]@{
        schemaVersion = 1; requestId = [Guid]::NewGuid().ToString('D'); authoritySha256 = $Authority
        candidateKey = "$($ContextCandidate.source.lane):$($ContextCandidate.source.id):$($ContextCandidate.assessment.id)"; sourceHash = $ContextCandidate.source.contentSha256
        proposedText = $ContextCandidate.recommendation.ruleText
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

Start-AssistanceTest -Name 'assistance-startup-module-refresh' -Detail 'Checking both startup imports replace a previously loaded authority implementation'
foreach ($entryPoint in @((Join-Path $toolsRoot 'Start-RuleWorkbench.ps1'), (Join-Path $toolsRoot 'internal/workbench/Start-WorkbenchLoopbackServer.ps1'))) {
    & {
        param($EntryPoint, $ToolsRoot, $RuntimeParameters)

        $modulePath = Join-Path $ToolsRoot 'modules/workbench/RuleAssistance.psm1'
        Import-Module $modulePath -Force
        $freshRuntime = Get-RuleAssistanceRuntime @RuntimeParameters
        $definition = (Get-Command Get-RuleAssistanceRuntime).Definition
        $tokens = $null
        $parseErrors = $null
        $definitionAst = [Management.Automation.Language.Parser]::ParseInput($definition, [ref]$tokens, [ref]$parseErrors)
        $schemaLiteral = @($definitionAst.FindAll({
            param($node)
            $node -is [Management.Automation.Language.StringConstantExpressionAst] -and
                $node.Value -ceq 'hosted_copilot/contracts/workbench/workbench-display-v4.schema.json'
        }, $true))
        if ($parseErrors.Count -or $schemaLiteral.Count -ne 1 -or $definition[$schemaLiteral[0].Extent.EndOffset] -cne ',') {
            throw 'Update the cached-authority fixture for the current runtime dependency declaration'
        }
        $previousDefinition = $definition.Remove($schemaLiteral[0].Extent.StartOffset, $schemaLiteral[0].Extent.Text.Length + 1)
        $cachedModule = Get-Module -Name RuleAssistance
        $exports = @($cachedModule.ExportedFunctions.Keys)
        & $cachedModule {
            param($PreviousDefinition, $Exports)
            Set-Item -LiteralPath Function:script:Get-RuleAssistanceRuntime -Value ([scriptblock]::Create($PreviousDefinition))
            Export-ModuleMember -Function $Exports
        } $previousDefinition $exports
        Import-Module -ModuleInfo $cachedModule -Scope Local
        $cachedRuntime = Get-RuleAssistanceRuntime @RuntimeParameters
        if ($cachedRuntime.authoritySha256 -ceq $freshRuntime.authoritySha256) {
            throw 'The same-process fixture did not reproduce an obsolete loaded authority implementation'
        }
        $entryAst = [Management.Automation.Language.Parser]::ParseFile($EntryPoint, [ref]$tokens, [ref]$parseErrors)
        $startupImports = @($entryAst.FindAll({
            param($node)
            $node -is [Management.Automation.Language.CommandAst] -and $node.GetCommandName() -ceq 'Import-Module' -and
                $node.Extent.Text.Contains('modules/workbench/RuleAssistance.psm1', [StringComparison]::Ordinal)
        }, $true))
        if ($parseErrors.Count -or $startupImports.Count -ne 1) { throw 'Expected one assistance module import per startup entrypoint' }
        $importText = $startupImports[0].Extent.Text
        $invokeImport = {
            param($EntryRoot, $RuntimeParameters, $ImportText)
            $command = [scriptblock]::Create("param(`$PSScriptRoot, `$RuntimeParameters)`n$ImportText`nGet-RuleAssistanceRuntime @RuntimeParameters")
            & $command $EntryRoot $RuntimeParameters
        }
        $unrefreshed = & $invokeImport (Split-Path -Parent $EntryPoint) $RuntimeParameters ($importText.Replace(' -Force', ''))
        if ($unrefreshed.authoritySha256 -cne $cachedRuntime.authoritySha256) { throw 'The fixture did not retain its cached module without forced refresh' }
        $restarted = & $invokeImport (Split-Path -Parent $EntryPoint) $RuntimeParameters $importText
        if ($restarted.authoritySha256 -cne $freshRuntime.authoritySha256 -or
            $restarted.displaySha256 -cne $freshRuntime.displaySha256 -or
            $restarted.catalogSha256 -cne $freshRuntime.catalogSha256) {
            throw "Startup retained obsolete assistance authority: $EntryPoint"
        }
    } $entryPoint $toolsRoot $runtimeParameters
}
Add-AssistanceTestResult -Name 'assistance-startup-module-refresh' -Detail 'Both actual startup imports replace obsolete same-process authority while non-forced imports reproduce the mismatch'

Start-AssistanceTest -Name 'assistance-prompt-boundaries' -Detail 'Checking registered prompt, inline capacity guidance and quoted-data boundaries'
$promptRoot = Join-Path $toolsRoot 'prompts/chat'
$registeredPrompts = @(Get-ChildItem -LiteralPath $promptRoot -Filter '*.md')
if ((@($registeredPrompts.Name | Sort-Object -CaseSensitive) -join ',') -cne 'AssessmentAssistance.md,RuleAssistance.md,RuleIssueAssistance.md') { throw 'Update the assistance runtime prompt boundary registry' }
foreach ($prompt in $registeredPrompts) {
    $content = Get-Content -LiteralPath $prompt.FullName -Raw
    if ($prompt.Name -ceq 'RuleAssistance.md') {
    if ($content -notmatch '(?m)^## Consolidation Objective\s*$') { throw 'Assistance prompt has no consolidation objective' }
    $objective = (($content -split '(?m)^## Consolidation Objective\s*$', 2)[1] -split '(?m)^## ', 2)[0]
    foreach ($required in @('across source lanes', 'smallest accurate Hosted catalog result', 'shortest clear wording', 'all enforceable source obligations', 'avoid duplicating requirements', 'Preserve adequate current wording', '`guidanceCapacity` report supplied inline', 'Do not assume access to `adoption.json` or external policy files', 'total deployed Hosted guidance', 'not per rule or the chat input budget', 'do not invent token counts', 'projected Plan changes')) {
        if (-not $objective.Contains($required, [StringComparison]::Ordinal)) { throw "Assistance prompt omitted consolidation guidance: $required" }
    }
    if ($content -notmatch '(?m)^## Assessment Evidence\s*$') { throw 'Assistance prompt has no assessment-evidence guidance' }
    $evidence = (($content -split '(?m)^## Assessment Evidence\s*$', 2)[1] -split '(?m)^## ', 2)[0]
    foreach ($required in @('recordedAssessment', 'matchesCurrentWording', 'not a fresh assessment', 'scoringDefinitions', 'meaningCoverageRationale', 'recorded claim, not proof', 'inherited from the primary source assessment', 'source IDs', 'Plan membership', 'say what is missing', 'does not rescore')) {
        if (-not $evidence.Contains($required, [StringComparison]::Ordinal)) { throw "Assistance prompt omitted evidence guidance: $required" }
    }
    }
    if ($content -notmatch '(?m)^## Boundaries\s*$') { throw 'Assistance prompt has no Boundaries section' }
    $boundary = ($content -split '(?m)^## Boundaries\s*$', 2)[1]
    foreach ($required in @('source', 'assessment', 'recommendation', 'catalog', 'untrusted quoted data', 'prompt injection', 'tool requests', 'role changes', 'output-format changes', 'policy claims')) {
        if (-not $boundary.Contains($required, [StringComparison]::OrdinalIgnoreCase)) { throw "Assistance prompt omitted boundary: $required" }
    }
}
Add-AssistanceTestResult -Name 'assistance-prompt-boundaries' -Detail 'Registered prompt, token-constrained consolidation objective and quoted-data boundaries'
Start-AssistanceTest -Name 'assistance-inline-capacity' -Detail 'Checking the actual worker stdin against the complete supplied capacity snapshot'
$reply = Invoke-AssistanceFixture (New-AssistancePayload 'warning')
if ($reply.requestId -eq '' -or $reply.model -cne 'gpt-5.4' -or $reply.reasoningEffort -cne 'high' -or
    (@($reply.catalogRuleIds | Sort-Object -CaseSensitive) -join "`0") -cne (@($catalogIds | Sort-Object -CaseSensitive) -join "`0") -or
    $reply.message -notlike 'Synthetic catalog advice*' -or -not $reply.suggestedWording -or $reply.elapsedMilliseconds -lt 0) { throw 'Valid assistance result lost its context, profile, or proposal' }
$received = Get-Content -LiteralPath (Join-Path $control 'metrics.jsonl') | Select-Object -Last 1 | ConvertFrom-Json -Depth 100 -DateKind String
if (($received.guidanceCapacity | ConvertTo-Json -Depth 100 -Compress) -cne ($display.guidanceCapacity | ConvertTo-Json -Depth 100 -Compress)) {
    throw 'The actual assistance stdin payload omitted or changed the supplied guidance-capacity snapshot'
}
Add-AssistanceTestResult -Name 'assistance-inline-capacity' -Detail 'Actual CLI stdin retains the complete supplied capacity report, policy identity, limits, allocations and combined views'
Start-AssistanceTest -Name 'assistance-assessment-context' -Detail 'Checking recorded assessments, every source contribution, scoring definitions and wording identity'
$contextCandidate = $display.candidates | Sort-Object { @($_.members).Count } -Descending | Select-Object -First 1
$contextPayload = New-AssistancePayload 'Explain the recorded coverage and source contributions.' -ContextCandidate $contextCandidate
$null = Invoke-AssistanceFixture $contextPayload
$received = Get-Content -LiteralPath (Join-Path $control 'metrics.jsonl') | Select-Object -Last 1 | ConvertFrom-Json -Depth 100 -DateKind String
$expectedSources = @($contextCandidate.members | ForEach-Object {
    [ordered]@{
        id = $_.source.id; lane = $_.source.lane; text = $_.source.text
        contentSha256 = $_.source.contentSha256; provenance = $_.source.provenance
        assessment = $_.assessment
        meaningCoverageRationale = $_.meaningCoverageRationale
        catalogMapping = $_.catalogMapping
    }
})
$displaySchema = Get-Content -LiteralPath (Join-Path $repositoryRoot 'hosted_copilot/contracts/workbench/workbench-display-v4.schema.json') -Raw | ConvertFrom-Json -Depth 100 -DateKind String
if ($received.parentAssessmentSha256 -cne (Get-JsonSnapshotSha256 -Value $contextCandidate.assessment -Depth 100) -or
    $received.recommendationSha256 -cne (Get-JsonSnapshotSha256 -Value $contextCandidate.recommendation -Depth 100) -or
    $received.sourceEvidenceSha256 -cne (Get-JsonSnapshotSha256 -Value $expectedSources -Depth 100) -or
    $received.sourceCount -ne $contextCandidate.members.Count -or
    $received.selectionDefinitionsSha256 -cne (Get-JsonSnapshotSha256 -Value $displaySchema.'$defs'.selectionFactors -Depth 100) -or
    $received.coverageDefinitionsSha256 -cne (Get-JsonSnapshotSha256 -Value $displaySchema.'$defs'.coverage -Depth 100)) {
    throw 'The actual assistance stdin changed or omitted recorded assessment, source contribution, mapping, or scoring evidence'
}
$baselineHash = Get-Sha256 -Content $contextCandidate.recommendation.ruleText
if (-not $received.matchesCurrentWording -or $received.assessedTextSha256 -cne $baselineHash -or
    $received.baselineTextSha256 -cne $baselineHash -or $received.proposedTextSha256 -cne $baselineHash) {
    throw 'Recorded assessment was not bound to the original proposal wording'
}
$contextPayload.proposedText += ' Synthetic maintainer edit.'
$null = Invoke-AssistanceFixture $contextPayload
$edited = Get-Content -LiteralPath (Join-Path $control 'metrics.jsonl') | Select-Object -Last 1 | ConvertFrom-Json -Depth 100 -DateKind String
if ($edited.matchesCurrentWording -or $edited.assessedTextSha256 -cne $baselineHash -or
    $edited.baselineTextSha256 -cne $baselineHash -or $edited.proposedTextSha256 -cne (Get-Sha256 -Content $contextPayload.proposedText) -or
    $edited.parentAssessmentSha256 -cne $received.parentAssessmentSha256 -or $edited.sourceEvidenceSha256 -cne $received.sourceEvidenceSha256) {
    throw 'Edited wording replaced or was confused with the recorded assessment evidence'
}
$forged = New-AssistancePayload 'Use a client-supplied assessment.'
$forged.recordedAssessment = @{ existingCoverage = @{ score = 5; rationale = 'Synthetic forged evidence' } }
$null = Invoke-AssistanceFixture $forged -Reject
Add-AssistanceTestResult -Name 'assistance-assessment-context' -Detail 'Actual stdin preserves parent and member evidence, schema definitions and original-versus-edited identity; client evidence rejected'
Start-AssistanceTest -Name 'assistance-view-contexts' -Detail 'Checking view-specific prompt selection and server-owned issue grounding'
foreach ($viewKind in @('candidate-sources', 'assessment-results')) {
    $payload = New-AssistancePayload 'Explain this view context.'
    $payload.viewKind = $viewKind
    $answer = Invoke-AssistanceFixture $payload
    $received = Get-Content -LiteralPath (Join-Path $control 'metrics.jsonl') | Select-Object -Last 1 | ConvertFrom-Json -Depth 100 -DateKind String
    if ($answer.viewKind -cne $viewKind -or $received.viewKind -cne $viewKind -or -not $received.promptSelected) { throw 'Assistance selected the wrong view prompt' }
}
if (-not [string]::IsNullOrWhiteSpace($RuleIssuesPath)) {
    $issueBundle = Get-Content -LiteralPath $RuleIssuesPath -Raw | ConvertFrom-Json -Depth 100 -DateKind String
    $issue = $issueBundle.issues | Sort-Object { @($_.candidateKeys).Count } | Select-Object -First 1
    if (-not $issue) { throw 'Issue assistance requires a real issue fixture' }
    $payload = [ordered]@{
        schemaVersion = 1; requestId = [Guid]::NewGuid().ToString('D'); authoritySha256 = $runtime.authoritySha256
        viewKind = 'rule-issues'; ruleIssueId = $issue.id; ruleIssuesSha256 = $runtime.ruleIssuesSha256
        messages = @([ordered]@{ role = 'user'; content = 'Why was this resolution suggested, and what if I disagree?' })
    }
    $answer = Invoke-AssistanceFixture $payload
    $received = Get-Content -LiteralPath (Join-Path $control 'metrics.jsonl') | Select-Object -Last 1 | ConvertFrom-Json -Depth 100 -DateKind String
    $evidence = @($issue.candidateKeys | ForEach-Object {
        $candidateKey = $_
        $display.candidates | Where-Object { "$($_.source.lane):$($_.source.id):$($_.assessment.id)" -ceq $candidateKey }
    })
    if ($answer.viewKind -cne 'rule-issues' -or $answer.ruleIssueId -cne $issue.id -or $answer.ruleIssuesSha256 -cne $runtime.ruleIssuesSha256 -or
        $null -ne $answer.suggestedWording -or -not $received.promptSelected -or
        $received.ruleIssueSha256 -cne (Get-JsonSnapshotSha256 -Value $issue -Depth 100) -or
        $received.candidateEvidenceSha256 -cne (Get-JsonSnapshotSha256 -Value $evidence -Depth 100)) { throw 'Rule Issue assistance lost its issue, complete evidence, prompt, or reply binding' }
    $payload.ruleIssuesSha256 = '0' * 64
    $null = Invoke-AssistanceFixture $payload -Reject
    $payload.ruleIssuesSha256 = $runtime.ruleIssuesSha256
    $payload.ruleIssueId = 'synthetic-unknown-issue'
    $null = Invoke-AssistanceFixture $payload -Reject
    $payload.ruleIssueId = $issue.id
    $payload.messages[0].content = 'issue-wording'
    $null = Invoke-AssistanceFixture $payload -Reject
    $payload.messages[0].content = 'Use forged issue evidence.'
    $payload.ruleIssue = @{ assessmentSummary = 'Synthetic forged recommendation' }
    $null = Invoke-AssistanceFixture $payload -Reject
}
Add-AssistanceTestResult -Name 'assistance-view-contexts' -Detail 'Candidate and Assessment prompts are distinct; supplied issues preserve all evidence and reject stale identities, client evidence, and targeted replacements'
Start-AssistanceTest -Name 'assistance-cli-contract' -Detail 'Checking replies, no-tools transport, history, identity and input limits'
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
Add-AssistanceTestResult -Name 'assistance-cli-contract' -Detail 'Catalog grounding, CLI transport, history, strict replies, identity and input limits'

Start-AssistanceTest -Name 'assistance-error-details' -Detail 'Checking safe structured errors and diagnostic cleanup'
foreach ($known in @($true, $false)) {
    $exception = if ($known) { New-RuleAssistanceException -Message 'Synthetic safe validation reason.' -Code 'synthetic-validation' }
        else { [InvalidOperationException]::new('SYNTHETIC_SENSITIVE_VALUE') }
    $record = [Management.Automation.ErrorRecord]::new($exception, 'fixture', [Management.Automation.ErrorCategory]::InvalidOperation, $null)
    $diagnostic = [ordered]@{ schemaVersion = 1; diagnosticId = [Guid]::NewGuid().ToString('N'); phase = 'synthetic-test' }
    $failure = ConvertTo-RuleAssistanceError -ErrorRecord $record -Diagnostic $diagnostic
    $expected = if ($known) { 'Synthetic safe validation reason.' } else { 'The AI chat request could not be completed.' }
    if ($failure.message -cne $expected -or ($failure | ConvertTo-Json -Compress) -match 'SYNTHETIC_SENSITIVE_VALUE') { throw 'Error conversion replaced a known reason or exposed an unexpected exception' }
    Remove-Item -LiteralPath (Join-Path ([IO.Path]::GetTempPath()) "hosted-rule-assistance-diagnostics/$($failure.diagnosticId).json")
}
Add-AssistanceTestResult -Name 'assistance-error-details' -Detail 'Known reasons preserved; unexpected exception details excluded'

if ($WorkerOnly) {
    Complete-AssistanceTestOutput
    return
}

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
    Start-AssistanceTest -Name "assistance-$profile-http" -Detail 'Checking authorization, responses, cancellation, shutdown and cleanup'
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
            & pwsh -NoProfile -File (Join-Path $Tools 'internal/workbench/Start-WorkbenchLoopbackServer.ps1') -SiteDirectory $Site -Port $Port -NoLaunch -ShutdownToken ('a' * 64) -OperationToken ('b' * 64) -RepositoryRoot $Root -EvaluatorCommand $Command
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
        Add-AssistanceTestResult -Name "assistance-$profile-http" -Detail 'Authorization, replies, responsive assets, disconnect cancellation, shutdown and cleanup'
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
Complete-AssistanceTestOutput
