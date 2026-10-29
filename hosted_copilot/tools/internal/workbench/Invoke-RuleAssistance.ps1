[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$RequestPath,
    [Parameter(Mandatory)][string]$OutputPath,
    [Parameter(Mandatory)][string]$DisplayPath,
    [string]$RuleIssuesPath,
    [Parameter(Mandatory)][string]$RepositoryRoot,
    [Parameter(Mandatory)][string]$EvaluatorCommand,
    [Parameter(Mandatory)][string]$Model,
    [Parameter(Mandatory)][ValidateSet('low', 'medium', 'high', 'xhigh')][string]$ReasoningEffort
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot '../../modules/workbench/RuleAssistance.psm1')
Import-Module (Join-Path $PSScriptRoot '../../modules/shared/HostedToolkit.Helpers.psm1')
Import-Module (Join-Path $PSScriptRoot '../../modules/shared/HostedCli.psm1')
$diagnosticId = [Guid]::NewGuid().ToString('N')
$diagnostic = [ordered]@{
    schemaVersion = 1; diagnosticId = $diagnosticId; recordedAt = ConvertTo-UtcTimestamp ([DateTimeOffset]::UtcNow)
    phase = 'input-validation'; cliExitCode = $null; stdoutBytes = 0; stderrBytes = 0; answerCount = 0
    events = [ordered]@{
        'session.start' = 0; 'session.error' = 0; 'session.idle' = 0; 'session.shutdown' = 0
        'assistant.message' = 0; 'assistant.message_delta' = 0; 'assistant.turn_end' = 0
        'system.message' = 0; 'result' = 0; 'error' = 0; 'other' = 0
    }
}
trap {
    $failure = ConvertTo-RuleAssistanceError -ErrorRecord $_ -Diagnostic $diagnostic
    [Console]::Error.WriteLine((@{ error = $failure } | ConvertTo-Json -Compress))
    exit 1
}

function Assert-AssistanceProperties {
    param([object]$Value, [string[]]$Names)
    if ($null -eq $Value -or (@($Value.PSObject.Properties.Name | Sort-Object -CaseSensitive) -join "`0") -cne (@($Names | Sort-Object -CaseSensitive) -join "`0")) {
        throw (New-RuleAssistanceException -Message 'Rule assistance input has an unexpected property set')
    }
}

$runtimeParameters = @{
    RepositoryRoot = $RepositoryRoot; DisplayPath = $DisplayPath
    RuleIssuesPath = $RuleIssuesPath
    EvaluatorCommand = $EvaluatorCommand; Model = $Model; ReasoningEffort = $ReasoningEffort
}
$runtime = Get-RuleAssistanceRuntime @runtimeParameters
$request = Get-Content -LiteralPath $RequestPath -Raw | ConvertFrom-Json -Depth 100 -DateKind String
$hasViewKind = $null -ne $request.PSObject.Properties['viewKind']
$viewKind = if ($hasViewKind) { [string]$request.viewKind } else { 'candidate-sources' }
if (($hasViewKind -and $request.viewKind -isnot [string]) -or $viewKind -cnotin @('candidate-sources', 'assessment-results', 'rule-issues')) {
    throw (New-RuleAssistanceException -Message 'Rule assistance view is invalid')
}
$isRuleIssue = $viewKind -ceq 'rule-issues'
$requestProperties = if ($isRuleIssue) {
    @('schemaVersion', 'requestId', 'authoritySha256', 'viewKind', 'ruleIssueId', 'ruleIssuesSha256', 'messages')
} else {
    @('schemaVersion', 'requestId', 'authoritySha256', 'candidateKey', 'sourceHash', 'proposedText', 'messages')
}
if ($hasViewKind -and -not $isRuleIssue) { $requestProperties += 'viewKind' }
Assert-AssistanceProperties $request $requestProperties
$requestId = [Guid]::Empty
if ($request.schemaVersion -ne 1 -or -not [Guid]::TryParseExact([string]$request.requestId, 'D', [ref]$requestId) -or
    [string]$request.authoritySha256 -cne $runtime.authoritySha256) {
    throw (New-RuleAssistanceException -Message 'Rule assistance context changed; reload the current Workbench before asking again')
}
if (-not $isRuleIssue -and ($request.proposedText -isnot [string] -or [string]::IsNullOrWhiteSpace($request.proposedText) -or $request.proposedText.Length -gt 20000)) {
    throw (New-RuleAssistanceException -Message 'Rule assistance requires current rule wording between 1 and 20000 characters')
}
$messages = @($request.messages)
if (-not $messages.Count -or $messages.Count % 2 -ne 1) { throw (New-RuleAssistanceException -Message 'Rule assistance conversation must end with a maintainer message') }
for ($index = 0; $index -lt $messages.Count; $index++) {
    $message = $messages[$index]
    Assert-AssistanceProperties $message @('role', 'content')
    $expectedRole = if ($index % 2 -eq 0) { 'user' } else { 'assistant' }
    $maximumLength = if ($expectedRole -ceq 'user') { 8000 } else { 40064 }
    if ($message.role -cne $expectedRole -or $message.content -isnot [string] -or [string]::IsNullOrWhiteSpace($message.content) -or $message.content.Length -gt $maximumLength) {
        throw (New-RuleAssistanceException -Message 'Rule assistance conversation contains an invalid turn')
    }
}
$displayJson = Get-Content -LiteralPath $DisplayPath -Raw
$schemaPath = Join-Path $RepositoryRoot 'hosted_copilot/contracts/workbench/workbench-display-v4.schema.json'
if (-not ($displayJson | Test-Json -SchemaFile $schemaPath -ErrorAction Stop)) { throw (New-RuleAssistanceException -Message 'Rule assistance display snapshot is invalid') }
$displaySchema = Get-Content -LiteralPath $schemaPath -Raw | ConvertFrom-Json -Depth 100
$display = $displayJson | ConvertFrom-Json -Depth 100 -DateKind String
$catalog = @($display.catalog.rules | Where-Object status -CEQ 'active' | ForEach-Object {
    [ordered]@{ id = $_.id; status = $_.status; text = $_.text }
}) + @($display.catalog.protectedRules | ForEach-Object {
    [ordered]@{ id = $_.id; status = 'protected'; text = $_.text }
})
if ($isRuleIssue) {
    if ([string]::IsNullOrWhiteSpace($RuleIssuesPath) -or $request.ruleIssuesSha256 -isnot [string] -or $request.ruleIssueId -isnot [string] -or
        [string]::IsNullOrWhiteSpace($request.ruleIssueId) -or $request.ruleIssuesSha256 -cne $runtime.ruleIssuesSha256) {
        throw (New-RuleAssistanceException -Message 'Rule assistance issue identity is unknown or stale')
    }
    $issueJson = Get-Content -LiteralPath $RuleIssuesPath -Raw
    $issueSchemaPath = Join-Path $RepositoryRoot 'hosted_copilot/contracts/workbench/workbench-rule-issues-v4.schema.json'
    if (-not ($issueJson | Test-Json -SchemaFile $issueSchemaPath -ErrorAction Stop)) {
        throw (New-RuleAssistanceException -Message 'Rule assistance issue snapshot is invalid')
    }
    $issueBundle = $issueJson | ConvertFrom-Json -Depth 100 -DateKind String
    $issueSourcesHash = Get-JsonSnapshotSha256 -Value @($issueBundle.sourceFiles | Sort-Object sourceDefinitionId, sourceId)
    $displaySourcesHash = Get-JsonSnapshotSha256 -Value @($display.sourceFiles | Sort-Object sourceDefinitionId, sourceId)
    $issues = @($issueBundle.issues | Where-Object id -CEQ $request.ruleIssueId)
    if ($issueSourcesHash -cne $displaySourcesHash -or $issues.Count -ne 1) {
        throw (New-RuleAssistanceException -Message 'Rule assistance issue snapshot does not match the Workbench')
    }
    $issue = $issues[0]
    if ((@($issue.rules.id | Sort-Object -Unique -CaseSensitive) -join "`0") -cne (@($issue.ruleIds | Sort-Object -CaseSensitive) -join "`0")) {
        throw (New-RuleAssistanceException -Message 'Rule assistance issue is missing affected rule evidence')
    }
    $issueCandidates = @($issue.candidateKeys | ForEach-Object {
        $candidateKey = $_
        $matches = @($display.candidates | Where-Object { "$($_.source.lane):$($_.source.id):$($_.assessment.id)" -ceq $candidateKey })
        if ($matches.Count -ne 1) { throw (New-RuleAssistanceException -Message 'Rule assistance issue candidate evidence is missing') }
        $matches[0]
    })
    $context = [ordered]@{
        viewKind = $viewKind; ruleIssue = $issue; candidateEvidence = $issueCandidates
        catalog = $catalog; guidanceCapacity = $display.guidanceCapacity; messages = $messages
    }
    $promptNames = @('RuleIssueAssistance.md')
} else {
    $candidates = @($display.candidates | Where-Object { "$($_.source.lane):$($_.source.id):$($_.assessment.id)" -ceq $request.candidateKey })
    if ($candidates.Count -ne 1 -or $candidates[0].source.contentSha256 -cne $request.sourceHash) { throw (New-RuleAssistanceException -Message 'Rule assistance candidate identity is unknown or stale') }
    $candidate = $candidates[0]
    $ruleId = if ($candidate.catalogMapping.hostedRuleId) { [string]$candidate.catalogMapping.hostedRuleId } else { [string]$candidate.recommendation.hostedId }
    if ([string]::IsNullOrWhiteSpace($ruleId) -or $ruleId -cin @($display.catalog.protectedRules.id)) { throw (New-RuleAssistanceException -Message 'Rule assistance requires a non-protected candidate target') }
    $context = [ordered]@{
        viewKind = $viewKind
        currentRule = [ordered]@{ id = $ruleId; baselineText = $candidate.recommendation.ruleText; proposedText = $request.proposedText }
        recordedAssessment = [ordered]@{
            assessedTextSha256 = Get-Sha256 -Content $candidate.recommendation.ruleText
            matchesCurrentWording = $request.proposedText -ceq $candidate.recommendation.ruleText
            assessment = $candidate.assessment
            recommendation = $candidate.recommendation
        }
        scoringDefinitions = [ordered]@{
            selectionFactors = $displaySchema.'$defs'.selectionFactors
            existingCoverage = $displaySchema.'$defs'.coverage
        }
        sources = @($candidate.members | ForEach-Object {
            [ordered]@{
                id = $_.source.id; lane = $_.source.lane; text = $_.source.text
                contentSha256 = $_.source.contentSha256; provenance = $_.source.provenance
                assessment = $_.assessment
                meaningCoverageRationale = $_.meaningCoverageRationale
                catalogMapping = $_.catalogMapping
            }
        })
        catalog = $catalog
        guidanceCapacity = $display.guidanceCapacity
        messages = $messages
    }
    $promptNames = @('RuleAssistance.md')
    if ($viewKind -ceq 'assessment-results') { $promptNames += 'AssessmentAssistance.md' }
}
$promptRoot = Join-Path $RepositoryRoot 'hosted_copilot/tools/prompts/chat'
$prompt = (($promptNames | ForEach-Object { Get-Content -LiteralPath (Join-Path $promptRoot $_) -Raw }) -join "`n") + "`n## Supplied Context`n" + ($context | ConvertTo-Json -Depth 100 -Compress)
$promptBytes = [Text.Encoding]::UTF8.GetByteCount($prompt)
if ($promptBytes -gt $runtime.maximumPromptBytes) {
    throw (New-RuleAssistanceException -Message "Rule assistance input requires $promptBytes bytes and exceeds the $($runtime.maximumPromptBytes)-byte input budget. Clear the conversation and try again. No catalog rules or conversation turns were dropped.")
}
$diagnostic.phase = 'cli-start'
$launch = Resolve-HostedCliLaunch -EvaluatorCommand $EvaluatorCommand
$workingDirectory = Split-Path -Parent $RequestPath
$startInfo = New-HostedCliStartInfo -Launch $launch -WorkingDirectory $workingDirectory -Arguments @(
    '-C', $workingDirectory, '--no-color', '--stream', 'off', '--no-custom-instructions', '--no-ask-user',
    '--disable-builtin-mcps', '--no-auto-update', '--disallow-temp-dir', '--no-remote-export',
    '--model', $Model, '--reasoning-effort', $ReasoningEffort, '--context', 'default',
    '--available-tools', '--output-format', 'json', '--log-level', 'none', '--log-dir', (Join-Path $workingDirectory 'logs')
)
$process = [Diagnostics.Process]::new()
$process.StartInfo = $startInfo
$stopwatch = [Diagnostics.Stopwatch]::StartNew()
$started = $false
try {
    $started = $process.Start()
    if (-not $started) { throw (New-RuleAssistanceException -Message 'Rule assistance CLI did not start') }
    $stdout = $process.StandardOutput.ReadToEndAsync()
    $stderr = $process.StandardError.ReadToEndAsync()
    $process.StandardInput.Write($prompt)
    $process.StandardInput.Close()
    $process.WaitForExit()
    $output = $stdout.GetAwaiter().GetResult()
    $errorOutput = $stderr.GetAwaiter().GetResult()
    $diagnostic.cliExitCode = $process.ExitCode
    $diagnostic.stdoutBytes = [Text.Encoding]::UTF8.GetByteCount($output)
    $diagnostic.stderrBytes = [Text.Encoding]::UTF8.GetByteCount($errorOutput)
    if ($process.ExitCode -ne 0) {
        throw (New-RuleAssistanceException -Message "The local Copilot CLI exited with code $($process.ExitCode). No reply was accepted." -Code 'cli-exit')
    }
}
finally {
    if ($started -and -not $process.HasExited) { $process.Kill($true); $process.WaitForExit() }
    $process.Dispose()
}
$stopwatch.Stop()
$diagnostic.phase = 'cli-output'
$answerJson = Get-RuleAssistanceCliAnswer -Output $output -Model $Model -Diagnostic $diagnostic
$diagnostic.phase = 'answer-validation'
try { $valid = $answerJson | Test-Json -SchemaFile (Join-Path $promptRoot '../../../contracts/workbench/rule-assistance-result.schema.json') -ErrorAction Stop }
catch { throw (New-RuleAssistanceException -Message 'Rule assistance answer did not satisfy its response contract' -Code 'invalid-response') }
if (-not $valid) { throw (New-RuleAssistanceException -Message 'Rule assistance answer did not satisfy its response contract' -Code 'invalid-response') }
$answer = $answerJson | ConvertFrom-Json -Depth 100
if ($isRuleIssue -and $null -ne $answer.suggestedWording) {
    throw (New-RuleAssistanceException -Message 'Rule Issue assistance cannot return an ambiguously targeted replacement' -Code 'invalid-response')
}
if ([string]::IsNullOrWhiteSpace($answer.message) -or ($null -ne $answer.suggestedWording -and [string]::IsNullOrWhiteSpace($answer.suggestedWording))) {
    throw (New-RuleAssistanceException -Message 'Rule assistance returned an empty answer or suggestion' -Code 'invalid-response')
}
$diagnostic.phase = 'context-validation'
if ((Get-RuleAssistanceRuntime @runtimeParameters).authoritySha256 -cne $runtime.authoritySha256) { throw (New-RuleAssistanceException -Message 'Rule assistance context changed during the request; ask again using the current Workbench') }
$result = [ordered]@{
    schemaVersion = 1; requestId = $request.requestId
    authoritySha256 = $runtime.authoritySha256
    catalogSha256 = $runtime.catalogSha256; protectedRulesSha256 = $runtime.protectedRulesSha256
    model = $Model; reasoningEffort = $ReasoningEffort; elapsedMilliseconds = $stopwatch.ElapsedMilliseconds
    catalogRuleIds = @($catalog.id); message = $answer.message; suggestedWording = $answer.suggestedWording
}
if ($hasViewKind) { $result.viewKind = $viewKind }
if ($isRuleIssue) {
    $result.ruleIssueId = $request.ruleIssueId
    $result.ruleIssuesSha256 = $runtime.ruleIssuesSha256
} else {
    $result.candidateKey = $request.candidateKey
    $result.proposedTextSha256 = Get-Sha256 -Content $request.proposedText
}
$diagnostic.phase = 'response-write'
[IO.File]::WriteAllText($OutputPath, ($result | ConvertTo-Json -Depth 100 -Compress), [Text.UTF8Encoding]::new($false))
