[CmdletBinding()]
param(
    [string]$RepositoryRoot = (Join-Path $PSScriptRoot '../../../..'),
    [string]$DisplayPath = (Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'hosted-workbench/site/workbench-display.json'),
    [string]$OutputPath,
    [string]$DisplaySchemaPath = (Join-Path $PSScriptRoot '../../../copilot-rule-catalog/assessment-reconciliation/workbench-display-v4.schema.json'),
    [string]$RuleIssuesSchemaPath = (Join-Path $PSScriptRoot '../../../copilot-rule-catalog/assessment-reconciliation/workbench-rule-issues-v4.schema.json'),
    [string]$AdjudicationInputSchemaPath = (Join-Path $PSScriptRoot '../../../copilot-rule-catalog/assessment-reconciliation/rule-issue-adjudication-input-v4.schema.json'),
    [string]$AdjudicationDraftSchemaPath = (Join-Path $PSScriptRoot '../../../copilot-rule-catalog/assessment-reconciliation/rule-issue-adjudication-draft-v4.schema.json'),
    [string]$AdjudicationPromptPath = (Join-Path $PSScriptRoot '../../assessment-reconciliation-prompts/RuleIssueAdjudication-v4.md'),
    [string]$AdjudicatorPath = (Join-Path $PSScriptRoot 'Invoke-RuleIssueAdjudication.ps1'),
    [string]$CacheDirectory = (Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'hosted-workbench/rule-issue-adjudication-cache'),
    [string]$ResumeRunDirectory,
    [string]$EvaluatorCommand = 'copilot',
    [string]$EvaluatorScriptPath,
    [string]$Model = 'gpt-5.4',
    [ValidateSet('low', 'medium', 'high', 'xhigh')][string]$ReasoningEffort = 'high',
    [ValidateRange(0, 3)][int]$MaxRetries = 1,
    [ValidateRange(1, 8)][int]$MaxParallelBatches = 3,
    [object]$GeneratedAt = [DateTime]::UtcNow,
    [ValidateSet('Text', 'Json')][string]$OutputFormat = 'Text',
    [switch]$ShowProgress
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$helpersPath = Join-Path $PSScriptRoot '../../modules/shared/HostedToolkit.Helpers.psm1'
$validationOutputPath = Join-Path $PSScriptRoot '../../../../tools/ValidationOutput.psm1'
Import-Module -Name $helpersPath -Force
Import-Module -Name $validationOutputPath -Force

$resolvedRepositoryRoot = [IO.Path]::GetFullPath($RepositoryRoot)
$resolvedDisplayPath = [IO.Path]::GetFullPath($DisplayPath)
$resolvedOutputPath = if ([string]::IsNullOrWhiteSpace($OutputPath)) {
    Join-Path (Split-Path -Parent $resolvedDisplayPath) 'workbench-rule-issues.json'
}
else {
    [IO.Path]::GetFullPath($OutputPath)
}
$resolvedDisplaySchemaPath = [IO.Path]::GetFullPath($DisplaySchemaPath)
$resolvedRuleIssuesSchemaPath = [IO.Path]::GetFullPath($RuleIssuesSchemaPath)
$resolvedAdjudicationInputSchemaPath = [IO.Path]::GetFullPath($AdjudicationInputSchemaPath)
$resolvedAdjudicationDraftSchemaPath = [IO.Path]::GetFullPath($AdjudicationDraftSchemaPath)
$resolvedAdjudicationPromptPath = [IO.Path]::GetFullPath($AdjudicationPromptPath)
$resolvedAdjudicatorPath = [IO.Path]::GetFullPath($AdjudicatorPath)

foreach ($requiredPath in @($resolvedDisplayPath, $resolvedDisplaySchemaPath, $resolvedRuleIssuesSchemaPath, $resolvedAdjudicationInputSchemaPath, $resolvedAdjudicationDraftSchemaPath, $resolvedAdjudicationPromptPath, $resolvedAdjudicatorPath)) {
    if (-not (Test-Path -LiteralPath $requiredPath -PathType Leaf)) {
        throw "Required Rule Issues input was not found: $requiredPath"
    }
}

function Get-CandidateKey {
    param([Parameter(Mandatory = $true)][object]$Candidate)

    return '{0}:{1}:{2}' -f [string]$Candidate.source.lane, [string]$Candidate.source.id, [string]$Candidate.assessment.id
}

function Get-RetirementRuleIds {
    param([Parameter(Mandatory = $true)][object]$Candidate)

    $ruleIds = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    foreach ($ruleId in @($Candidate.recommendation.retireHostedRuleIds)) {
        $null = $ruleIds.Add([string]$ruleId)
    }
    if ([string]$Candidate.recommendation.action -ceq 'retire' -and $null -ne $Candidate.recommendation.targetHostedId) {
        $null = $ruleIds.Add([string]$Candidate.recommendation.targetHostedId)
    }
    return @($ruleIds | Sort-Object -CaseSensitive)
}

function Format-RuleIdList {
    param([Parameter(Mandatory = $true)][AllowEmptyCollection()][string[]]$RuleIds)

    $values = @($RuleIds | Sort-Object -CaseSensitive -Unique)
    if ($values.Count -eq 0) { return '' }
    if ($values.Count -eq 1) { return $values[0] }
    if ($values.Count -eq 2) { return "$($values[0]) and $($values[1])" }
    return (@($values[0..($values.Count - 2)]) -join ', ') + ", and $($values[-1])"
}

function Write-JsonAtomically {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][object]$Value
    )

    $directory = Split-Path -Parent $Path
    if (-not (Test-Path -LiteralPath $directory -PathType Container)) {
        $null = New-Item -ItemType Directory -Path $directory -Force
    }
    $temporaryPath = Join-Path $directory ('.' + [IO.Path]::GetFileName($Path) + '.' + [Guid]::NewGuid().ToString('N') + '.tmp')
    try {
        [IO.File]::WriteAllText($temporaryPath, (($Value | ConvertTo-Json -Depth 100) + "`n"), [Text.UTF8Encoding]::new($false))
        [IO.File]::Move($temporaryPath, $Path, $true)
    }
    finally {
        Remove-Item -LiteralPath $temporaryPath -Force -ErrorAction SilentlyContinue
    }
}

$displayContent = Get-Content -LiteralPath $resolvedDisplayPath -Raw
if (-not ($displayContent | Test-Json -SchemaFile $resolvedDisplaySchemaPath -ErrorAction Stop)) {
    throw "Workbench display does not satisfy its schema: $resolvedDisplayPath"
}
$display = $displayContent | ConvertFrom-Json -DateKind String
$relationshipKinds = [ordered]@{
    equivalent = 'duplicate'
    'partial-overlap' = 'overlap'
    'assessment-extends-hosted' = 'overlap'
    'assessment-narrows-hosted' = 'overlap'
    conflicts = 'contradiction'
}
$rulesById = @{}
$protectedRuleIds = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
$candidateRecords = [Collections.Generic.List[object]]::new()
$candidateRecordsByRuleId = @{}

foreach ($rule in @($display.catalog.rules)) {
    $rulesById[[string]$rule.id] = [pscustomobject]@{
        id = [string]$rule.id
        status = [string]$rule.status
        text = [string]$rule.text
        title = [string]$rule.id
    }
}
foreach ($rule in @($display.catalog.protectedRules)) {
    $ruleId = [string]$rule.id
    $null = $protectedRuleIds.Add($ruleId)
    $rulesById[$ruleId] = [pscustomobject]@{
        id = $ruleId
        status = 'protected'
        text = [string]$rule.text
        title = [string]$rule.title
    }
}
foreach ($candidate in @($display.candidates)) {
    $candidateKey = Get-CandidateKey -Candidate $candidate
    $sourceRuleId = if ($null -ne $candidate.catalogMapping.hostedRuleId) {
        [string]$candidate.catalogMapping.hostedRuleId
    }
    else {
        [string]$candidate.recommendation.hostedId
    }
    if (-not $rulesById.ContainsKey($sourceRuleId)) {
        $rulesById[$sourceRuleId] = [pscustomobject]@{
            id = $sourceRuleId
            status = 'proposed'
            text = [string]$candidate.recommendation.ruleText
            title = [string]$candidate.assessment.title
        }
    }
    $record = [pscustomobject]@{
        Candidate = $candidate
        CandidateKey = $candidateKey
        SourceRuleId = $sourceRuleId
        RetirementRuleIds = @(Get-RetirementRuleIds -Candidate $candidate)
    }
    $candidateRecords.Add($record)
    if (-not $candidateRecordsByRuleId.ContainsKey($sourceRuleId)) {
        $candidateRecordsByRuleId[$sourceRuleId] = [Collections.Generic.List[object]]::new()
    }
    $candidateRecordsByRuleId[$sourceRuleId].Add($record)
}

$edges = [Collections.Generic.List[object]]::new()
foreach ($record in $candidateRecords) {
    $candidate = $record.Candidate
    foreach ($coverage in @($candidate.recommendation.relatedHostedCoverage)) {
        $relationship = [string]$coverage.relationship
        $relatedRuleId = [string]$coverage.hostedRuleId
        if (-not $relationshipKinds.Contains($relationship) -or $relatedRuleId -ceq $record.SourceRuleId -or -not $rulesById.ContainsKey($relatedRuleId)) {
            continue
        }
        $edges.Add([pscustomobject]@{
            Id = ''
            SourceRuleId = $record.SourceRuleId
            RelatedRuleId = $relatedRuleId
            Relationship = $relationship
            Kind = [string]$relationshipKinds[$relationship]
            Rationale = [string]$coverage.rationale
            CandidateKey = $record.CandidateKey
        })
    }
}

$orderedEdges = @($edges | Sort-Object -Property SourceRuleId, RelatedRuleId, Relationship, CandidateKey)
$adjacency = @{}
for ($edgeIndex = 0; $edgeIndex -lt $orderedEdges.Count; $edgeIndex++) {
    $edge = $orderedEdges[$edgeIndex]
    $edge.Id = 'relationship-{0:D5}' -f ($edgeIndex + 1)
    foreach ($ruleId in @($edge.SourceRuleId, $edge.RelatedRuleId)) {
        if (-not $adjacency.ContainsKey($ruleId)) {
            $adjacency[$ruleId] = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
        }
    }
    $null = $adjacency[$edge.SourceRuleId].Add($edge.RelatedRuleId)
    $null = $adjacency[$edge.RelatedRuleId].Add($edge.SourceRuleId)
}

$components = [Collections.Generic.List[object]]::new()
$visitedRuleIds = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
foreach ($startRuleId in @($adjacency.Keys | Sort-Object -CaseSensitive)) {
    if (-not $visitedRuleIds.Add($startRuleId)) { continue }
    $queue = [Collections.Generic.Queue[string]]::new()
    $memberSet = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    $queue.Enqueue($startRuleId)
    while ($queue.Count -gt 0) {
        $ruleId = $queue.Dequeue()
        $null = $memberSet.Add($ruleId)
        foreach ($relatedRuleId in @($adjacency[$ruleId] | Sort-Object -CaseSensitive)) {
            if ($visitedRuleIds.Add($relatedRuleId)) {
                $queue.Enqueue($relatedRuleId)
            }
        }
    }
    $componentEdges = @($orderedEdges | Where-Object { $memberSet.Contains($_.SourceRuleId) -and $memberSet.Contains($_.RelatedRuleId) })
    $ruleIds = @($memberSet | Sort-Object -CaseSensitive)
    $components.Add([pscustomobject]@{
        ComponentId = 'component:' + $ruleIds[0]
        RuleIds = $ruleIds
        Edges = $componentEdges
    })
}

$runDirectory = Join-Path ([IO.Path]::GetTempPath()) ('hosted-rule-issue-export/' + [Guid]::NewGuid().ToString('N'))
$componentDirectory = Join-Path $runDirectory 'components'
$null = New-Item -ItemType Directory -Path $componentDirectory -Force
$componentInputs = @{}
$componentInputPaths = [Collections.Generic.List[string]]::new()
$sourceDefinitionByLane = @{ contributor = 'contributor-guidance'; interactive = 'interactive-toolkit'; maintainer = 'maintainer-proposals' }
$sourceFilesByKey = @{}
foreach ($sourceFile in @($display.sourceFiles)) {
    $sourceFilesByKey["$([string]$sourceFile.sourceDefinitionId)`0$([string]$sourceFile.sourceId)"] = $sourceFile
}

foreach ($component in @($components | Sort-Object ComponentId)) {
    $ruleIds = @($component.RuleIds)
    $componentCandidateRecords = @($candidateRecords | Where-Object { $_.SourceRuleId -in $ruleIds -or @($_.RetirementRuleIds | Where-Object { $_ -in $ruleIds }).Count -gt 0 })
    $componentSourceFiles = @($componentCandidateRecords | ForEach-Object {
        $sourceDefinitionId = [string]$sourceDefinitionByLane[[string]$_.Candidate.source.lane]
        $key = "$sourceDefinitionId`0$([string]$_.Candidate.source.id)"
        if (-not $sourceFilesByKey.ContainsKey($key)) {
            throw "Rule Issue component references unknown source file: $key"
        }
        $sourceFilesByKey[$key]
    } | Sort-Object -Property sourceDefinitionId, sourceId -Unique)
    $inputRules = @($ruleIds | ForEach-Object {
        $ruleId = [string]$_
        $rule = $rulesById[$ruleId]
        [ordered]@{
            id = $ruleId
            status = [string]$rule.status
            title = [string]$rule.title
            text = [string]$rule.text
            contentSha256 = Get-Sha256 -Content ([string]$rule.text)
            candidateKeys = @($componentCandidateRecords | Where-Object SourceRuleId -ceq $ruleId | ForEach-Object CandidateKey | Sort-Object -CaseSensitive -Unique)
        }
    })
    $inputRelationships = @($component.Edges | ForEach-Object {
        [ordered]@{
            id = [string]$_.Id
            sourceRuleId = [string]$_.SourceRuleId
            relatedRuleId = [string]$_.RelatedRuleId
            relationship = [string]$_.Relationship
            rationale = [string]$_.Rationale
            candidateKey = [string]$_.CandidateKey
        }
    })
    $inputOperations = @($componentCandidateRecords | ForEach-Object {
        [ordered]@{
            candidateKey = [string]$_.CandidateKey
            ruleId = [string]$_.SourceRuleId
            action = [string]$_.Candidate.recommendation.action
            proposedText = [string]$_.Candidate.recommendation.ruleText
            retireHostedRuleIds = @($_.RetirementRuleIds)
        }
    } | Sort-Object -Property candidateKey)
    $componentInput = [ordered]@{
        '$schema' = 'rule-issue-adjudication-input-v4.schema.json'
        schemaVersion = 1
        kind = 'hosted-rule-issue-adjudication-input'
        componentId = [string]$component.ComponentId
        sourceFiles = $componentSourceFiles
        rules = $inputRules
        relationships = $inputRelationships
        operations = $inputOperations
    }
    $componentInputJson = $componentInput | ConvertTo-Json -Depth 100
    if (-not ($componentInputJson | Test-Json -SchemaFile $resolvedAdjudicationInputSchemaPath -ErrorAction Stop)) {
        throw "Rule Issue component $($component.ComponentId) does not satisfy its schema"
    }
    $componentPath = Join-Path $componentDirectory ("component-{0:D3}.json" -f ($componentInputPaths.Count + 1))
    [IO.File]::WriteAllText($componentPath, $componentInputJson + "`n", [Text.UTF8Encoding]::new($false))
    $componentInputPaths.Add($componentPath)
    $componentInputs[[string]$component.ComponentId] = $componentInput
}

$adjudicationSet = [ordered]@{ schemaVersion = 1; kind = 'hosted-rule-issue-adjudication-set'; components = @() }
$adjudicationResult = [pscustomobject]@{ componentCount = 0; cachedComponentCount = 0; evaluatedComponentCount = 0; cacheDirectory = [IO.Path]::GetFullPath($CacheDirectory) }
if ($componentInputPaths.Count -gt 0) {
    if ($ShowProgress) {
        Write-ValidationSectionHeader -Title 'Export Workbench Rule Issues' | Write-Host
    }
    $adjudicationSetPath = Join-Path $runDirectory 'rule-issue-adjudication-set.json'
    $adjudicationParameters = @{
        RepositoryRoot = $resolvedRepositoryRoot
        ComponentPaths = $componentInputPaths.ToArray()
        OutputPath = $adjudicationSetPath
        InputSchemaPath = $resolvedAdjudicationInputSchemaPath
        DraftSchemaPath = $resolvedAdjudicationDraftSchemaPath
        PromptPath = $resolvedAdjudicationPromptPath
        CacheDirectory = $CacheDirectory
        EvaluatorCommand = $EvaluatorCommand
        Model = $Model
        ReasoningEffort = $ReasoningEffort
        MaxRetries = $MaxRetries
        MaxParallelBatches = $MaxParallelBatches
        OutputFormat = 'Json'
        Quiet = -not $ShowProgress
    }
    if (-not [string]::IsNullOrWhiteSpace($ResumeRunDirectory)) { $adjudicationParameters.ResumeRunDirectory = $ResumeRunDirectory }
    if (-not [string]::IsNullOrWhiteSpace($EvaluatorScriptPath)) { $adjudicationParameters.EvaluatorScriptPath = $EvaluatorScriptPath }
    $adjudicationOutput = @(& $resolvedAdjudicatorPath @adjudicationParameters 2>&1)
    if (-not (Test-Path -LiteralPath $adjudicationSetPath -PathType Leaf)) {
        throw "Rule Issue adjudication failed: $(($adjudicationOutput | Out-String).Trim())"
    }
    $adjudicationResult = ($adjudicationOutput | Out-String) | ConvertFrom-Json
    $adjudicationSet = Get-Content -LiteralPath $adjudicationSetPath -Raw | ConvertFrom-Json -DateKind String
}

$issues = [Collections.Generic.List[object]]::new()
$issueIds = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
foreach ($draft in @($adjudicationSet.components)) {
    $componentInput = $componentInputs[[string]$draft.componentId]
    if ($null -eq $componentInput) { throw "Adjudication returned an unknown component: $($draft.componentId)" }
    $ruleById = @{}
    foreach ($rule in @($componentInput.rules)) { $ruleById[[string]$rule.id] = $rule }
    $relationshipById = @{}
    foreach ($relationship in @($componentInput.relationships)) { $relationshipById[[string]$relationship.id] = $relationship }
    $decisionById = @{}
    foreach ($decision in @($draft.relationshipDecisions)) { $decisionById[[string]$decision.relationshipId] = $decision }
    foreach ($adjudicatedIssue in @($draft.issues)) {
        $issueRuleIds = @($adjudicatedIssue.ruleIds)
        $issueProtectedRuleIds = @($issueRuleIds | Where-Object { [string]$ruleById[$_].status -ceq 'protected' } | Sort-Object -CaseSensitive)
        $relationshipIdentity = @($adjudicatedIssue.relationshipIds | Sort-Object -CaseSensitive)[0]
        $issueId = if ($issueProtectedRuleIds.Count -gt 0) { 'protected:' + ($issueProtectedRuleIds -join '+') + ':' + $relationshipIdentity } else { 'relationship:' + [string]$adjudicatedIssue.anchorRuleId + ':' + $relationshipIdentity }
        if (-not $issueIds.Add($issueId)) { throw "Adjudication produced duplicate issue ID: $issueId" }
        $dispositionByRuleId = @{}
        foreach ($entry in @($adjudicatedIssue.ruleDispositions)) { $dispositionByRuleId[[string]$entry.ruleId] = [string]$entry.disposition }
        $finalRelationships = @($adjudicatedIssue.relationshipIds | ForEach-Object {
            $relationship = $relationshipById[[string]$_]
            $decision = $decisionById[[string]$_]
            [ordered]@{
                sourceRuleId = [string]$relationship.sourceRuleId
                relatedRuleId = [string]$relationship.relatedRuleId
                relationship = [string]$decision.relationship
                kind = [string]$relationshipKinds[[string]$decision.relationship]
                rationale = [string]$decision.rationale
                candidateKey = [string]$relationship.candidateKey
            }
        } | Sort-Object -Property sourceRuleId, relatedRuleId, relationship, candidateKey)
        $selectedOperations = @($adjudicatedIssue.recommendedMaintainerAction.operations | Sort-Object -Property candidateKey)
        $finalRules = @($issueRuleIds | ForEach-Object {
            $rule = $ruleById[[string]$_]
            [ordered]@{
                id = [string]$rule.id
                status = [string]$rule.status
                disposition = [string]$dispositionByRuleId[[string]$rule.id]
                text = [string]$rule.text
                candidateKeys = @($rule.candidateKeys)
            }
        })
        $candidateKeys = @($finalRules.candidateKeys + $finalRelationships.candidateKey + $selectedOperations.candidateKey | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) } | Sort-Object -CaseSensitive -Unique)
        $label = switch ([string]$adjudicatedIssue.classification) {
            'protected-integrity' { 'Protected Integrity' }
            'protected-conflict' { 'Protected Conflict' }
            'protected-coverage' { 'Protected Coverage' }
            'contradiction' { 'Contradiction' }
            'duplicate' { 'Duplicate' }
            'overlap' { 'Overlap' }
        }
        $issues.Add([ordered]@{
            id = $issueId
            classification = [string]$adjudicatedIssue.classification
            label = $label
            title = [string]$adjudicatedIssue.title
            bannerTitle = [string]$adjudicatedIssue.bannerTitle
            bannerMessage = [string]$adjudicatedIssue.bannerMessage
            blocking = [bool]$adjudicatedIssue.blocking
            ruleIds = $issueRuleIds
            protectedRuleIds = $issueProtectedRuleIds
            candidateKeys = $candidateKeys
            rules = $finalRules
            relationships = $finalRelationships
            assessmentSummary = [string]$adjudicatedIssue.assessmentSummary
            wording = $adjudicatedIssue.wording
            recommendedMaintainerAction = [ordered]@{
                summary = [string]$adjudicatedIssue.recommendedMaintainerAction.summary
                operations = $selectedOperations
            }
        })
    }
}

$artifact = [ordered]@{
    '$schema' = 'workbench-rule-issues-v4.schema.json'
    schemaVersion = 4
    kind = 'hosted-rule-workbench-rule-issues'
    generatedAt = ConvertTo-UtcTimestamp -Value $GeneratedAt
    readOnly = $true
    sourceFiles = @($display.sourceFiles)
    issues = @($issues | Sort-Object -Property @{ Expression = { [bool]$_.blocking }; Descending = $true }, classification, id)
}
$artifactJson = $artifact | ConvertTo-Json -Depth 100
if (-not ($artifactJson | Test-Json -SchemaFile $resolvedRuleIssuesSchemaPath -ErrorAction Stop)) {
    throw 'Generated Workbench Rule Issues artifact does not satisfy its schema'
}
Write-JsonAtomically -Path $resolvedOutputPath -Value $artifact
Remove-Item -LiteralPath $runDirectory -Recurse -Force -ErrorAction SilentlyContinue
$ruleIssuesSha256 = Get-Sha256 -Path $resolvedOutputPath

$result = [ordered]@{
    status = 'passed'
    displayPath = $resolvedDisplayPath
    outputPath = $resolvedOutputPath
    issueCount = $issues.Count
    protectedIssueCount = @($issues | Where-Object { @($_.protectedRuleIds).Count -gt 0 }).Count
    blockingIssueCount = @($issues | Where-Object blocking).Count
    componentCount = [int]$adjudicationResult.componentCount
    cachedComponentCount = [int]$adjudicationResult.cachedComponentCount
    evaluatedComponentCount = [int]$adjudicationResult.evaluatedComponentCount
    cacheDirectory = [string]$adjudicationResult.cacheDirectory
    ruleIssuesSha256 = $ruleIssuesSha256
}
if ($OutputFormat -eq 'Json') {
    $result | ConvertTo-Json -Depth 5 -Compress
}
else {
    Write-ValidationSectionHeader -Title 'Summary' | Write-Host
    Write-ValidationSummary -Fields ([ordered]@{
        Status = ([string]$result.status).ToUpperInvariant()
        Components = $result.componentCount
        Issues = $result.issueCount
        'Cached Components' = $result.cachedComponentCount
        'Evaluated Components' = $result.evaluatedComponentCount
        Output = $result.outputPath
        'Rule Issues SHA-256' = $result.ruleIssuesSha256
    }) | Write-Host
    Complete-ValidationTextOutput | Write-Output
}
