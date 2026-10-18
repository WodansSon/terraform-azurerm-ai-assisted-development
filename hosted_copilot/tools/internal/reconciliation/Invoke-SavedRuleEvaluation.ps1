[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$RequestPath,
    [Parameter(Mandatory = $true)][string]$OutputPath,
    [Parameter(Mandatory = $true)][string]$DisplayPath,
    [Parameter(Mandatory = $true)][string]$RuleIssuesPath,
    [string]$RepositoryRoot = (Join-Path $PSScriptRoot '../../../..'),
    [string]$CacheDirectory = (Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'hosted-workbench/manual-relationship-cache'),
    [string]$EvaluatorCommand = 'copilot',
    [string]$EvaluatorScriptPath,
    [string]$AdjudicationEvaluatorScriptPath,
    [string]$Model = 'gpt-5.4',
    [ValidateSet('low', 'medium', 'high', 'xhigh')][string]$ReasoningEffort = 'high'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
trap {
    [Console]::Error.WriteLine(([ordered]@{ error = [string]$_.Exception.Message } | ConvertTo-Json -Compress))
    throw $_
}
Import-Module (Join-Path $PSScriptRoot '../../modules/shared/HostedToolkit.Helpers.psm1')
Import-Module (Join-Path $PSScriptRoot '../../modules/workbench/SavedRuleEvaluation.psm1')
Import-Module (Join-Path $PSScriptRoot '../../modules/reconciliation/RuleIssueAdjudication.psm1')

function Assert-Properties {
    param([object]$Value, [string[]]$Names)
    if ($null -eq $Value -or (@($Value.PSObject.Properties.Name | Sort-Object -CaseSensitive) -join "`0") -cne (@($Names | Sort-Object -CaseSensitive) -join "`0")) { throw 'Saved-rule request has an unexpected property set' }
}

function Read-RuleText {
    param([string]$Encoded)
    $text = [Text.UTF8Encoding]::new($false, $true).GetString([Convert]::FromBase64String($Encoded))
    if ([string]::IsNullOrWhiteSpace($text) -or $text.Length -gt 20000) { throw 'Saved rule text must contain between 1 and 20000 characters' }
    return $text
}

function Assert-RelationshipOwnership {
    param([object]$Relationship)
    $key = [string]$Relationship.candidateKey
    $sourceId = [string]$Relationship.sourceRuleId
    $relatedId = [string]$Relationship.relatedRuleId
    if (-not $records.ContainsKey($key) -or $records[$key].id -cne $sourceId -or -not $rules.ContainsKey($relatedId) -or $sourceId -ceq $relatedId) { throw 'Saved-rule provisional relationship has invalid ownership' }
}

$catalogRoot = Join-Path $RepositoryRoot 'hosted_copilot/copilot-rule-catalog'
$schemaRoot = Join-Path $catalogRoot 'assessment-reconciliation'
$request = Get-Content -LiteralPath $RequestPath -Raw | ConvertFrom-Json -Depth 100 -DateKind String
Assert-Properties $request @('schemaVersion', 'requestId', 'authoritySha256', 'candidateKey', 'ruleTextBase64', 'sourceFiles', 'proposals', 'priorRelationships')
if ($request.schemaVersion -ne 2 -or [string]$request.requestId -cnotmatch '^[0-9a-f-]{36}$' -or [string]$request.authoritySha256 -cnotmatch '^[0-9a-f]{64}$') { throw 'Saved-rule request identity is invalid' }
$authorityParameters = @{
    RepositoryRoot = $RepositoryRoot; DisplayPath = $DisplayPath; RuleIssuesPath = $RuleIssuesPath
    EvaluatorCommand = $EvaluatorCommand; Model = $Model; ReasoningEffort = $ReasoningEffort
    RelationshipEvaluatorScriptPath = $EvaluatorScriptPath; AdjudicationEvaluatorScriptPath = $AdjudicationEvaluatorScriptPath
}
$authority = Get-SavedRuleAuthoritySha256 @authorityParameters
if ([string]$request.authoritySha256 -cne $authority) { throw 'Saved-rule authority changed; reload the current Workbench before checking again' }
$displayJson = Get-Content -LiteralPath $DisplayPath -Raw
$issuesJson = Get-Content -LiteralPath $RuleIssuesPath -Raw
if (-not ($displayJson | Test-Json -SchemaFile (Join-Path $schemaRoot 'workbench-display-v4.schema.json') -ErrorAction Stop) -or -not ($issuesJson | Test-Json -SchemaFile (Join-Path $schemaRoot 'workbench-rule-issues-v4.schema.json') -ErrorAction Stop)) { throw 'Saved-rule source snapshots are invalid' }
$display = $displayJson | ConvertFrom-Json -Depth 100 -DateKind String
$originalIssues = $issuesJson | ConvertFrom-Json -Depth 100 -DateKind String
$sourceIdentity = { param($files) @($files | ForEach-Object { "$($_.sourceDefinitionId)`0$($_.sourceId)`0$($_.contentSha256)" } | Sort-Object -CaseSensitive) -join "`n" }
if ((& $sourceIdentity $display.sourceFiles) -cne (& $sourceIdentity $request.sourceFiles) -or (& $sourceIdentity $display.sourceFiles) -cne (& $sourceIdentity $originalIssues.sourceFiles)) { throw 'Saved-rule source snapshot does not match the running Workbench' }

$rules = @{}
foreach ($rule in @($display.catalog.rules)) {
    $rules[[string]$rule.id] = [ordered]@{ id = [string]$rule.id; status = [string]$rule.status; title = [string]$rule.id; text = [string]$rule.text; candidateKeys = @() }
}
foreach ($rule in @($display.catalog.protectedRules)) {
    $rules[[string]$rule.id] = [ordered]@{ id = [string]$rule.id; status = 'protected'; title = [string]$rule.title; text = [string]$rule.text; candidateKeys = @() }
}
$records = @{}
foreach ($candidate in @($display.candidates)) {
    $key = "$($candidate.source.lane):$($candidate.source.id):$($candidate.assessment.id)"
    $id = if ($null -ne $candidate.catalogMapping.hostedRuleId) { [string]$candidate.catalogMapping.hostedRuleId } else { [string]$candidate.recommendation.hostedId }
    if ([string]::IsNullOrWhiteSpace($id)) { continue }
    if ($records.ContainsKey($key)) { throw 'Saved-rule source contains duplicate candidate identity' }
    if (-not $rules.ContainsKey($id)) { $rules[$id] = [ordered]@{ id = $id; status = 'proposed'; title = [string]$candidate.assessment.title; text = [string]$candidate.recommendation.ruleText; candidateKeys = @() } }
    if ($rules[$id].status -ceq 'protected') { throw 'Saved-rule candidate cannot own a protected rule' }
    $rules[$id].candidateKeys = @($rules[$id].candidateKeys) + @($key)
    $records[$key] = [ordered]@{ candidate = $candidate; key = $key; id = $id; baseline = [string]$candidate.recommendation.ruleText; proposal = $null }
}
if (-not $records.ContainsKey([string]$request.candidateKey)) { throw 'Saved-rule request references an unknown candidate' }
$seen = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
$catalogRules = @($rules.Values | Where-Object { $_.status -cne 'proposed' } | Sort-Object { $_.id } | ForEach-Object {
    [ordered]@{ id = $_.id; status = $_.status; title = $_.title; text = $_.text; contentSha256 = Get-Sha256 -Content $_.text; candidateKeys = @($_.candidateKeys) }
})
$workingTexts = @{}
foreach ($proposal in @($request.proposals)) {
    Assert-Properties $proposal @('candidateKey', 'sourceHash', 'action', 'inPlan', 'proposedTextBase64', 'retireHostedRuleIds')
    $key = [string]$proposal.candidateKey
    if (-not $records.ContainsKey($key) -or -not $seen.Add($key)) { throw 'Saved-rule proposal references an unknown or duplicate candidate' }
    $record = $records[$key]
    if ([string]$proposal.sourceHash -cne [string]$record.candidate.source.contentSha256) { throw 'Saved-rule proposal has stale source content' }
    $allowedActions = switch ($rules[$record.id].status) {
        'active' { @('no-change', 'update', 'retire', 'defer') }
        'retired' { @('no-change', 'restore', 'defer') }
        'proposed' { @('no-change', 'add', 'exclude', 'defer') }
    }
    if ([string]$proposal.action -notin $allowedActions) { throw 'Saved-rule proposal action is invalid for its catalog status' }
    foreach ($retireId in @($proposal.retireHostedRuleIds)) {
        $newRetirement = [string]$retireId -cnotin @($record.candidate.recommendation.retireHostedRuleIds)
        if (($newRetirement -and (-not $proposal.inPlan -or [string]$proposal.action -notin @('add', 'update', 'restore', 'no-change'))) -or
            [string]$retireId -ceq [string]$record.id -or -not $rules.ContainsKey([string]$retireId) -or
            $rules[[string]$retireId].status -cne 'active' -or @($proposal.retireHostedRuleIds | Where-Object { $_ -ceq $retireId }).Count -ne 1) {
            throw 'Saved-rule proposal retirements require explicit plan membership and distinct known active rules'
        }
    }
    $text = Read-RuleText ([string]$proposal.proposedTextBase64)
    if ($proposal.inPlan -isnot [bool]) { throw 'Saved-rule proposal plan membership must be boolean' }
    $record.proposal = [ordered]@{ candidateKey = $key; sourceHash = [string]$proposal.sourceHash; action = [string]$proposal.action; inPlan = $proposal.inPlan; proposedText = $text; retireHostedRuleIds = @($proposal.retireHostedRuleIds | Sort-Object -CaseSensitive -Unique) }
    if ($key -ceq [string]$request.candidateKey -or $proposal.inPlan -or $text -cne $record.baseline) {
        if ($workingTexts.ContainsKey($record.id) -and $workingTexts[$record.id] -cne $text) { throw 'Current proposals contain conflicting wording for one rule identity' }
        $workingTexts[$record.id] = $text
        $rules[$record.id].text = $text
    }
}
if ($seen.Count -ne $records.Count) { throw 'Saved-rule request must contain the complete current proposal snapshot' }
$edited = $records[[string]$request.candidateKey]
$plannedRetirements = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
foreach ($record in @($records.Values | Where-Object { $_.proposal.inPlan })) {
    foreach ($retireId in @($record.proposal.retireHostedRuleIds)) {
        if (-not $plannedRetirements.Add([string]$retireId) -or @($records.Values | Where-Object {
            $_.id -ceq [string]$retireId -and $_.proposal.inPlan -and $_.proposal.action -in @('add', 'update', 'restore', 'retire')
        }).Count -gt 0) { throw 'Saved-rule proposal contains duplicate retirements or a conflicting planned mutation' }
    }
}
$editedText = Read-RuleText ([string]$request.ruleTextBase64)
if ([string]$edited.proposal.proposedText -cne $editedText) { throw 'Saved-rule text disagrees with its proposal snapshot' }

$relationshipKinds = @('equivalent', 'partial-overlap', 'assessment-extends-hosted', 'assessment-narrows-hosted', 'conflicts')
foreach ($relationship in @($request.priorRelationships)) {
    if ([string]$relationship.relationship -in $relationshipKinds) { Assert-RelationshipOwnership $relationship }
}
$currentRule = @($display.catalog.rules | Where-Object { $_.id -ceq $edited.id -and $_.status -ceq 'active' })
$unchanged = $currentRule.Count -eq 1 -and $edited.proposal.action -ceq 'no-change' -and -not $edited.proposal.inPlan -and
    $editedText.Replace("`r`n", "`n") -ceq ([string]$currentRule[0].text).Replace("`r`n", "`n")
if ($unchanged) {
    $result = [ordered]@{
        schemaVersion = 4; evaluationMode = 'unchanged'; candidateKey = $edited.key; requestId = [string]$request.requestId
        ruleTextSha256 = Get-Sha256 -Content $editedText; authoritySha256 = $authority
        evaluationContextSha256 = Get-JsonSnapshotSha256 -Depth 100 -Value ([ordered]@{ authority = $authority; candidateKey = $edited.key; proposals = @($request.proposals); evaluationMode = 'unchanged' })
        scopeReview = [ordered]@{
            disposition = 'within-scope'; ownerRuleId = $null; baselineQuote = $edited.baseline; proposalQuote = $editedText
            rationale = 'The proposed wording matches the current Hosted rule; the original assessment and Rule Issues are retained without evaluation. No fresh relationship assessment was performed.'
            wordingStatus = 'acceptable'; wordingRationale = 'The exact current Hosted wording is retained; no edited wording was accepted.'
        }
        affectedRuleIds = @($edited.id)
        coveredProposals = @($edited.proposal)
        assessments = @(); ruleIssues = $originalIssues
    }
    if (-not (($result | ConvertTo-Json -Depth 100) | Test-Json -SchemaFile (Join-Path $schemaRoot 'saved-rule-evaluation.schema.json') -ErrorAction Stop)) { throw 'Unchanged saved-rule result does not satisfy its result contract' }
    if ((Get-SavedRuleAuthoritySha256 @authorityParameters) -cne $authority) { throw 'Saved-rule authority changed during validation' }
    $null = Write-JsonSnapshot -Path $OutputPath -Value $result -Depth 100
    [ordered]@{ status = 'unchanged'; outputPath = $OutputPath; evaluatedCount = 0 } | ConvertTo-Json -Compress
    return
}

$runDirectory = Join-Path ([IO.Path]::GetTempPath()) ('hosted-saved-rule-' + [Guid]::NewGuid().ToString('N'))
$null = New-Item -ItemType Directory -Path $runDirectory
try {
    $comparedRules = @($rules.Values | Where-Object { $_.id -cne $edited.id -and $_.status -cne 'retired' } | Sort-Object { $_.id })
    $comparedPath = Join-Path $runDirectory 'compared-rules.json'
    Write-JsonSnapshot -Path $comparedPath -Value $comparedRules -Depth 100
    $checkerRequestPath = Join-Path $runDirectory 'checker-request.json'
    Write-JsonSnapshot -Path $checkerRequestPath -Value ([ordered]@{
        candidateKey = $edited.key; ruleId = $edited.id; ruleTextBase64 = [string]$request.ruleTextBase64
        category = [string]$edited.candidate.recommendation.category; placement = [string]$edited.candidate.recommendation.placement
    })
    $checkerOutputPath = Join-Path $runDirectory 'checker-result.json'
    $checkerParameters = @{
        RequestPath = $checkerRequestPath; OutputPath = $checkerOutputPath; RepositoryRoot = $RepositoryRoot
        CacheDirectory = (Join-Path $CacheDirectory 'checker'); ComparedRulesPath = $comparedPath
        EvaluatorCommand = $EvaluatorCommand; Model = $Model; ReasoningEffort = $ReasoningEffort
    }
    if (-not [string]::IsNullOrWhiteSpace($EvaluatorScriptPath)) { $checkerParameters.EvaluatorScriptPath = $EvaluatorScriptPath }
    $null = & (Join-Path $PSScriptRoot 'Invoke-ManualRuleRelationship.ps1') @checkerParameters
    $checked = Get-Content -LiteralPath $checkerOutputPath -Raw | ConvertFrom-Json -Depth 100 -DateKind String
    $edges = @{}
    $provisional = @($originalIssues.issues | ForEach-Object { $_.relationships }) + @($request.priorRelationships)
    foreach ($relationship in @($checked.relationships)) {
        $provisional += [pscustomobject]@{ candidateKey = $edited.key; sourceRuleId = $edited.id; relatedRuleId = [string]$relationship.hostedRuleId; relationship = [string]$relationship.relationship; rationale = [string]$relationship.rationale }
    }
    foreach ($relationship in $provisional) {
        $key = [string]$relationship.candidateKey
        $sourceId = [string]$relationship.sourceRuleId
        $relatedId = [string]$relationship.relatedRuleId
        if ([string]$relationship.relationship -notin $relationshipKinds) { continue }
        Assert-RelationshipOwnership $relationship
        $identity = "$key`0$sourceId`0$relatedId"
        $edges[$identity] = [ordered]@{ id = 'saved:' + (Get-Sha256 -Content $identity); sourceRuleId = $sourceId; relatedRuleId = $relatedId; relationship = [string]$relationship.relationship; rationale = [string]$relationship.rationale; candidateKey = $key }
    }
    $members = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    $null = $members.Add($edited.id)
    if ($edited.proposal.inPlan) {
        foreach ($retireId in @($edited.proposal.retireHostedRuleIds)) { $null = $members.Add([string]$retireId) }
    }
    do {
        $expanded = $false
        foreach ($edge in $edges.Values) {
            if ($members.Contains($edge.sourceRuleId) -or $members.Contains($edge.relatedRuleId)) {
                if ($members.Add($edge.sourceRuleId)) { $expanded = $true }
                if ($members.Add($edge.relatedRuleId)) { $expanded = $true }
            }
            foreach ($record in @($records.Values | Where-Object { $members.Contains($_.id) -and $_.proposal.inPlan })) {
                foreach ($retireId in @($record.proposal.retireHostedRuleIds)) {
                    if ($members.Add([string]$retireId)) { $expanded = $true }
                }
            }
        }
    } while ($expanded)
    $componentRecords = @($records.Values | Where-Object { $members.Contains($_.id) } | Sort-Object { $_.key })
    $sourceFiles = @($display.sourceFiles)
    $contextHash = Get-JsonSnapshotSha256 -Depth 100 -Value ([ordered]@{ authority = $authority; candidateKey = $edited.key; proposals = @($request.proposals); relationships = @($edges.Values | Sort-Object { $_.id }) })
    $component = [ordered]@{
        '$schema' = 'rule-issue-adjudication-input-v4.schema.json'; schemaVersion = 1; kind = 'hosted-rule-issue-adjudication-input'
        componentId = 'saved:' + $edited.id; sourceFiles = $sourceFiles
        rules = @($rules.Values | Sort-Object { $_.id } | ForEach-Object { [ordered]@{ id = $_.id; status = $_.status; title = $_.title; text = $_.text; contentSha256 = Get-Sha256 -Content $_.text; candidateKeys = @($_.candidateKeys) } })
        relationships = @($edges.Values | Where-Object { $members.Contains($_.sourceRuleId) -and $members.Contains($_.relatedRuleId) } | Sort-Object { $_.id })
        operations = @($componentRecords | ForEach-Object { [ordered]@{ candidateKey = $_.key; ruleId = $_.id; action = $_.proposal.action; proposedText = $_.proposal.proposedText; retireHostedRuleIds = @($_.proposal.retireHostedRuleIds) } })
        editContext = [ordered]@{
            candidateKey = $edited.key; intendedCandidateKey = $edited.key
            baselineText = $edited.baseline; baselineSha256 = Get-Sha256 -Content $edited.baseline
            appendText = if ($editedText.StartsWith($edited.baseline, [StringComparison]::Ordinal)) { $editedText.Substring($edited.baseline.Length) } else { $null }
            evaluationContextSha256 = $contextHash
            assessmentContext = [ordered]@{
                catalogRules = $catalogRules
                sources = @()
            }
            proposals = @($componentRecords | ForEach-Object { [ordered]@{ candidateKey = $_.key; inPlan = $_.proposal.inPlan; baselineText = $_.baseline; proposedText = $_.proposal.proposedText; ruleTextSha256 = Get-Sha256 -Content $_.proposal.proposedText; retireHostedRuleIds = @($_.proposal.retireHostedRuleIds) } })
        }
    }
    $assessmentKeys = @(Get-SavedRuleAssessmentProposals -Component $component | ForEach-Object candidateKey)
    $component.editContext.assessmentContext.sources = @($componentRecords | Where-Object { $_.key -cin $assessmentKeys } | ForEach-Object {
                    [ordered]@{
                        candidateKey = $_.key
                        category = [string]$_.candidate.recommendation.category
                        sourceRules = @($_.candidate.members | ForEach-Object {
                            [ordered]@{ id = [string]$_.source.id; text = [string]$_.source.text; meaning = [string]$_.assessment.sourceMeaning }
                        })
                    }
                })
    $componentPath = Join-Path $runDirectory 'component.json'
    Write-JsonSnapshot -Path $componentPath -Value $component -Depth 100
    $adjudicationPath = Join-Path $runDirectory 'adjudication.json'
    $adjudicationParameters = @{
        RepositoryRoot = $RepositoryRoot; ComponentPaths = @($componentPath); OutputPath = $adjudicationPath
        CacheDirectory = (Join-Path $CacheDirectory 'adjudication'); EvaluatorCommand = $EvaluatorCommand
        Model = $Model; ReasoningEffort = $ReasoningEffort; MaxParallelShards = 1; OutputFormat = 'Json'; Quiet = $true
    }
    if (-not [string]::IsNullOrWhiteSpace($AdjudicationEvaluatorScriptPath)) { $adjudicationParameters.EvaluatorScriptPath = $AdjudicationEvaluatorScriptPath }
    $null = & (Join-Path $PSScriptRoot 'Invoke-RuleIssueAdjudication.ps1') @adjudicationParameters
    $adjudication = Get-Content -LiteralPath $adjudicationPath -Raw | ConvertFrom-Json -Depth 100 -DateKind String
    $drafts = @($adjudication.components)
    if ($drafts.Count -ne 1) { throw 'Saved-rule adjudication must return exactly one complete component' }
    $componentObject = ($component | ConvertTo-Json -Depth 100) | ConvertFrom-Json -Depth 100 -DateKind String
    $finalIssues = @(ConvertTo-WorkbenchRuleIssues -Component $componentObject -Draft $drafts[0])
    if ((Get-SavedRuleAuthoritySha256 @authorityParameters) -cne $authority) { throw 'Saved-rule authority changed during evaluation' }
    $artifact = [ordered]@{
        '$schema' = 'workbench-rule-issues-v4.schema.json'; schemaVersion = 4; kind = 'hosted-rule-workbench-rule-issues'
        generatedAt = ConvertTo-UtcTimestamp -Value ([DateTime]::UtcNow); readOnly = $true; sourceFiles = @($display.sourceFiles); issues = $finalIssues
    }
    if (-not (($artifact | ConvertTo-Json -Depth 100) | Test-Json -SchemaFile (Join-Path $schemaRoot 'workbench-rule-issues-v4.schema.json') -ErrorAction Stop)) { throw 'Saved-rule issues do not satisfy the shared display contract' }
    $result = [ordered]@{
        schemaVersion = 4; candidateKey = $edited.key; requestId = [string]$request.requestId
        ruleTextSha256 = Get-Sha256 -Content $editedText; authoritySha256 = $authority; evaluationContextSha256 = $contextHash
        scopeReview = $drafts[0].scopeReview; affectedRuleIds = @($members | Sort-Object -CaseSensitive)
        coveredProposals = @($componentRecords | ForEach-Object { $_.proposal }); assessments = @($drafts[0].assessments); ruleIssues = $artifact
    }
    if (-not (($result | ConvertTo-Json -Depth 100) | Test-Json -SchemaFile (Join-Path $schemaRoot 'saved-rule-evaluation.schema.json') -ErrorAction Stop)) { throw 'Saved-rule evaluation does not satisfy its result contract' }
    Write-JsonSnapshot -Path $OutputPath -Value $result -Depth 100
    [ordered]@{ status = 'passed'; outputPath = $OutputPath; issueCount = $finalIssues.Count } | ConvertTo-Json -Compress
}
finally {
    Remove-Item -LiteralPath $runDirectory -Recurse -Force
}
