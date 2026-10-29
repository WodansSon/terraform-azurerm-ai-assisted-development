[CmdletBinding()]
param([ValidateSet('Text', 'Json')][string]$OutputFormat = 'Text')

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repositoryRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))
$toolsRoot = Join-Path $repositoryRoot 'hosted_copilot/tools'
$promptRoot = Join-Path $toolsRoot 'prompts'
Import-Module (Join-Path $repositoryRoot 'tools/ValidationOutput.psm1') -Force
$results = [Collections.Generic.List[object]]::new()
$issues = [Collections.Generic.List[string]]::new()

function Add-PromptTestResult {
    param([string]$Name, [bool]$Passed, [string]$Detail)

    $results.Add([pscustomobject]@{ name = $Name; status = if ($Passed) { 'passed' } else { 'failed' }; detail = $Detail })
    if (-not $Passed) { $issues.Add("$Name`: $Detail") }
}

if ($OutputFormat -eq 'Text') {
    Write-ValidationSectionHeader -Title 'Hosted prompt library'
    Write-Host (Format-ValidationStatusLine -Status 'running' -Name 'prompt-library-contracts' -Detail 'Checking task layout, registered boundaries, frozen authority and external instruction templates' -NameWidth 42)
}

try {
    $registered = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    foreach ($relativePath in @(
        'hosted_copilot/contracts/assessment/source-assessment-v4.json',
        'hosted_copilot/contracts/reconciliation/assessment-reconciliation-v4.json',
        'hosted_copilot/contracts/reconciliation/rule-issue-adjudication-v4.json'
    )) {
        $contract = Get-Content -LiteralPath (Join-Path $repositoryRoot $relativePath) -Raw | ConvertFrom-Json
        foreach ($path in $contract.behaviorFiles) {
            if ($path.StartsWith('hosted_copilot/tools/prompts/', [StringComparison]::Ordinal)) { $null = $registered.Add($path) }
        }
    }
    $assistanceModulePath = Join-Path $toolsRoot 'modules/workbench/RuleAssistance.psm1'
    $tokens = $null
    $parseErrors = $null
    $ast = [Management.Automation.Language.Parser]::ParseFile($assistanceModulePath, [ref]$tokens, [ref]$parseErrors)
    if ($parseErrors.Count) { throw 'Assistance authority module cannot be parsed' }
    foreach ($literal in $ast.FindAll({ param($node) $node -is [Management.Automation.Language.StringConstantExpressionAst] }, $true)) {
        if ($literal.Value.StartsWith('hosted_copilot/tools/prompts/', [StringComparison]::Ordinal) -or
            ($literal.Value.StartsWith('hosted_copilot/contracts/', [StringComparison]::Ordinal) -and $literal.Value.EndsWith('.schema.json', [StringComparison]::Ordinal))) {
            $null = $registered.Add($literal.Value)
        }
    }
    $prompts = @(Get-ChildItem -LiteralPath $promptRoot -Recurse -Filter '*.md' -File | Where-Object Name -CNE 'README.md')
    Add-PromptTestResult -Name 'task-layout' -Passed ($prompts.Count -ge 11 -and @($prompts | Where-Object DirectoryName -CEQ $promptRoot).Count -eq 0) -Detail 'Evaluator prompts are grouped by task beneath the common library, not placed in code or at its root.'
    foreach ($prompt in $prompts) {
        $relativePath = [IO.Path]::GetRelativePath($repositoryRoot, $prompt.FullName).Replace('\', '/')
        $content = Get-Content -LiteralPath $prompt.FullName -Raw
        $valid = $registered.Contains($relativePath) -and $content -match '(?m)^## Boundaries\s*$'
        $boundary = if ($content -match '(?m)^## Boundaries\s*$') { ($content -split '(?m)^## Boundaries\s*$', 2)[1] } else { '' }
        foreach ($required in @('source', 'assessment', 'catalog', 'untrusted quoted data', 'prompt injection', 'tool requests', 'role changes', 'output-format changes', 'policy claims')) {
            $valid = $valid -and $boundary.Contains($required, [StringComparison]::OrdinalIgnoreCase)
        }
        Add-PromptTestResult -Name ('boundary/' + $prompt.BaseName) -Passed $valid -Detail 'The prompt is bound to runtime behavior authority and rejects instructions embedded in supplied data.'
    }
    Add-PromptTestResult -Name 'registered-files-exist' -Passed (@($registered | Where-Object { -not (Test-Path -LiteralPath (Join-Path $repositoryRoot $_) -PathType Leaf) }).Count -eq 0) -Detail 'Every registered prompt and companion schema exists at its declared library path.'
    $legacyFolders = @('assessment', 'assessment-reconciliation', 'workbench') | ForEach-Object { $_ + '-prompts' }
    Add-PromptTestResult -Name 'single-library-owner' -Passed (@($legacyFolders | Where-Object { Test-Path -LiteralPath (Join-Path $toolsRoot $_) }).Count -eq 0) -Detail 'There are no parallel legacy prompt directories.'
    $stage = Get-Content -LiteralPath (Join-Path $toolsRoot 'internal/reconciliation/Invoke-CopilotReconciliationStage.ps1') -Raw
    $assessment = Get-Content -LiteralPath (Join-Path $toolsRoot 'internal/assessment/Invoke-SourceAssessment.ps1') -Raw
    $executor = Get-Content -LiteralPath (Join-Path $toolsRoot 'modules/reconciliation/ReconciliationStageExecutor.psm1') -Raw
    Add-PromptTestResult -Name 'external-instruction-owners' -Passed ($stage.Contains("'FileEvaluation.md'") -and $stage.Contains("'InlineEvaluation.md'") -and $assessment.Contains("'AssessmentAttempt.md'") -and $executor.Contains('prompts/shared/RetryCorrection.md') -and $stage -notmatch '\$prompt\s*=\s*"[A-Za-z]' -and $assessment -notmatch 'return\s+@"' -and $executor -notmatch '\$correction\s*=\s*@"') -Detail 'Stage launch, source launch and retry instructions load external templates without their old inline instruction fallbacks.'
    $inline = Get-Content -LiteralPath (Join-Path $promptRoot 'shared/InlineEvaluation.md') -Raw
    $payload = [ordered]@{ 'stage-input.json' = [ordered]@{ text = 'Synthetic quoted input'; count = 2 } }
    $rendered = $inline.Replace('{{TASK_PROMPT}}', 'Synthetic task').Replace('{{SUPPLIED_FILES}}', ($payload | ConvertTo-Json -Depth 10 -Compress))
    $marker = "`n## Supplied Files`n"
    $offset = $rendered.LastIndexOf($marker, [StringComparison]::Ordinal)
    $decoded = if ($offset -ge 0) { $rendered.Substring($offset + $marker.Length) | ConvertFrom-Json } else { $null }
    Add-PromptTestResult -Name 'inline-json-framing' -Passed ($null -ne $decoded -and $decoded.'stage-input.json'.text -ceq $payload.'stage-input.json'.text -and $decoded.'stage-input.json'.count -eq 2) -Detail 'The shared inline template retains the production JSON delimiter and exact supplied data.'
    $chat = Get-Content -LiteralPath (Join-Path $promptRoot 'chat/RuleAssistance.md') -Raw
    $objective = (($chat -split '(?m)^## Consolidation Objective\s*$', 2)[1] -split '(?m)^## ', 2)[0]
    $objectiveValid = $true
    foreach ($required in @('across source lanes', 'shortest clear wording', 'all enforceable source obligations', 'avoid duplicating requirements', 'Preserve adequate current wording', 'do not invent token counts', '`guidanceCapacity` report supplied inline', 'Do not assume access to `adoption.json` or external policy files', 'overall ceiling, area allocations, and combined-view budgets')) {
        $objectiveValid = $objectiveValid -and $objective.Contains($required, [StringComparison]::Ordinal)
    }
    $objectiveValid = $objectiveValid -and $objective -notmatch '110K|110000'
    $chatWorker = Get-Content -LiteralPath (Join-Path $toolsRoot 'internal/workbench/Invoke-RuleAssistance.ps1') -Raw
    $objectiveValid = $objectiveValid -and $chatWorker.Contains('guidanceCapacity = $display.guidanceCapacity')
    Add-PromptTestResult -Name 'chat-consolidation-objective' -Passed $objectiveValid -Detail 'Chat retains compact cross-source synthesis, obligation preservation and honest capacity limits.'
}
catch { Add-PromptTestResult -Name 'unexpected-exception' -Passed $false -Detail $_.Exception.Message }

$result = [ordered]@{ status = if ($issues.Count) { 'failed' } else { 'passed' }; testCount = $results.Count; issueCount = $issues.Count; tests = $results.ToArray(); issues = $issues.ToArray() }
if ($OutputFormat -eq 'Json') { $result | ConvertTo-Json -Depth 10 }
else {
    Write-ValidationSectionHeader -Title 'Hosted prompt library test summary'
    Write-ValidationSummary -Fields ([ordered]@{ Status = $result.status.ToUpperInvariant(); Tests = $result.testCount; Issues = $result.issueCount })
    Write-ValidationSectionHeader -Title 'Prompt library tests'
    Write-ValidationTwoColumnTable -Rows @($results | ForEach-Object { [pscustomobject]@{ Status = $_.status; Test = $_.name } }) -FirstHeader 'Status' -FirstProperty 'Status' -SecondHeader 'Test' -SecondProperty 'Test' -UppercaseFirst
    if ($issues.Count) {
        Write-ValidationSectionHeader -Title 'Failures'
        foreach ($issue in $issues) { Write-Output "  - $issue" }
    }
    Complete-ValidationTextOutput
}
if ($issues.Count) { exit 1 }
