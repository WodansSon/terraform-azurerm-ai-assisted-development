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
        [string]$Model = 'gpt-5.4',
        [string]$ReasoningEffort = 'high',
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

Export-ModuleMember -Function Get-SavedRuleAuthoritySha256
