[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$InputPath,
    [Parameter(Mandatory = $true)][string]$SchemaPath,
    [Parameter(Mandatory = $true)][string]$PromptPath,
    [Parameter(Mandatory = $true)][string]$OutputPath,
    [Parameter(Mandatory = $true)][string]$Model,
    [Parameter(Mandatory = $true)][string]$ReasoningEffort
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$request = Get-Content -LiteralPath $InputPath -Raw | ConvertFrom-Json -DateKind String
$independent = [string]$request.componentId -like '*independent*'
$invalidReference = [string]$request.componentId -like '*invalid-reference*'
$decisions = @($request.relationships | ForEach-Object {
    [ordered]@{
        relationshipId = [string]$_.id
        disposition = if ($independent) { 'independent' } else { 'issue' }
        relationship = if ($independent) { 'none' } else { [string]$_.relationship }
        rationale = if ($independent) { 'The exact obligations can coexist independently.' } else { 'The exact obligations require one maintainer decision.' }
    }
})
$issues = @()
if (-not $independent) {
    $protectedRules = @($request.rules | Where-Object status -eq 'protected')
    $hasConflict = @($decisions | Where-Object relationship -eq 'conflicts').Count -gt 0
    $hasEquivalent = @($decisions | Where-Object relationship -eq 'equivalent').Count -gt 0
    $classification = if ($protectedRules.Count -gt 1) { 'protected-integrity' } elseif ($protectedRules.Count -eq 1 -and $hasConflict) { 'protected-conflict' } elseif ($protectedRules.Count -eq 1) { 'protected-coverage' } elseif ($hasConflict) { 'contradiction' } elseif ($hasEquivalent) { 'duplicate' } else { 'overlap' }
    $dispositions = @($request.rules | ForEach-Object {
        $rule = $_
        $operation = @($request.operations | Where-Object ruleId -eq $rule.id | Select-Object -First 1)
        $disposition = if ($rule.status -eq 'protected') {
            'keep'
        }
        elseif ($operation.Count -eq 0) {
            'review'
        }
        else {
            switch ([string]$operation[0].action) {
                'add' { 'promote' }
                'restore' { 'promote' }
                'update' { 'replace' }
                default { [string]$operation[0].action }
            }
        }
        [ordered]@{ ruleId = [string]$rule.id; disposition = $disposition }
    })
    $promotionOperations = @($request.operations | Where-Object action -in @('add', 'update', 'restore'))
    $wording = if ($protectedRules.Count -eq 1) {
        [ordered]@{ status = 'canonical'; label = 'Canonical Protected Wording'; presentation = 'section'; text = [string]$protectedRules[0].text; sourceRuleId = [string]$protectedRules[0].id }
    }
    elseif ($promotionOperations.Count -eq 1) {
        $operation = $promotionOperations[0]
        $member = @($request.rules | Where-Object id -eq $operation.ruleId)[0]
        [ordered]@{ status = 'selected'; label = 'Suggested Consolidated Wording'; presentation = $(if ([string]$member.text -ceq [string]$operation.proposedText) { 'member' } else { 'section' }); text = [string]$operation.proposedText; sourceRuleId = [string]$operation.ruleId }
    }
    else {
        [ordered]@{ status = 'unresolved'; label = 'Consolidated Wording Unresolved'; presentation = 'section'; reason = 'No single final wording was selected.' }
    }
    $issues = @([ordered]@{
        anchorRuleId = [string]$request.rules[0].id
        classification = $classification
        title = 'Fixture relationship group'
        bannerTitle = 'Fixture Rule Issue'
        bannerMessage = 'Fixture relationships require one maintainer decision.'
        blocking = $protectedRules.Count -gt 1
        ruleIds = @($request.rules.id)
        relationshipIds = @($request.relationships.id)
        ruleDispositions = $dispositions
        assessmentSummary = if ($invalidReference) { 'IMPL-FAKE-999 must remain the owner.' } else { 'The fixture rules require one coherent maintainer decision.' }
        wording = $wording
        recommendedMaintainerAction = [ordered]@{ summary = 'Review the fixture operations.'; operations = @($request.operations | Where-Object action -ne 'no-change') }
    })
}
$result = [ordered]@{
    '$schema' = 'rule-issue-adjudication-draft-v4.schema.json'
    schemaVersion = 1
    kind = 'hosted-rule-issue-adjudication-draft'
    componentId = [string]$request.componentId
    relationshipDecisions = $decisions
    issues = $issues
}
$json = $result | ConvertTo-Json -Depth 100
if (-not ($json | Test-Json -SchemaFile $SchemaPath -ErrorAction Stop)) {
    throw 'Fixture adjudication does not satisfy its schema'
}
[IO.File]::WriteAllText($OutputPath, $json + "`n", [Text.UTF8Encoding]::new($false))
