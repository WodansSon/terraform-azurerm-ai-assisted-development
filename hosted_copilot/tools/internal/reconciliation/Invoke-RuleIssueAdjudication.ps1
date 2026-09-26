[CmdletBinding()]
param(
    [string]$RepositoryRoot = (Join-Path $PSScriptRoot '../../../..'),
    [Parameter(Mandatory = $true)][string[]]$ComponentPaths,
    [Parameter(Mandatory = $true)][string]$OutputPath,
    [string]$InputSchemaPath = (Join-Path $PSScriptRoot '../../../copilot-rule-catalog/assessment-reconciliation/rule-issue-adjudication-input-v4.schema.json'),
    [string]$DraftSchemaPath = (Join-Path $PSScriptRoot '../../../copilot-rule-catalog/assessment-reconciliation/rule-issue-adjudication-draft-v4.schema.json'),
    [string]$PromptPath = (Join-Path $PSScriptRoot '../../assessment-reconciliation-prompts/RuleIssueAdjudication-v4.md'),
    [string]$CacheDirectory = (Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'hosted-workbench/rule-issue-adjudication-cache'),
    [string]$ResumeRunDirectory,
    [string]$EvaluatorCommand = 'copilot',
    [string]$EvaluatorScriptPath,
    [string]$Model = 'gpt-5.4',
    [ValidateSet('low', 'medium', 'high', 'xhigh')][string]$ReasoningEffort = 'high',
    [ValidateRange(0, 3)][int]$MaxRetries = 1,
    [ValidateRange(1, 8)][int]$MaxParallelBatches = 3,
    [ValidateSet('Text', 'Json')][string]$OutputFormat = 'Text',
    [switch]$Quiet
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$helpersPath = Join-Path $PSScriptRoot '../../modules/shared/HostedToolkit.Helpers.psm1'
$validationOutputPath = Join-Path $PSScriptRoot '../../../../tools/ValidationOutput.psm1'
Import-Module -Name $helpersPath -Force
Import-Module -Name $validationOutputPath -Force
$stopwatch = [Diagnostics.Stopwatch]::StartNew()
$adjudicationBootstrapBytesPerSecondPerWorker = 600

function Get-EvaluatorJson {
    param([Parameter(Mandatory = $true)][AllowEmptyString()][string]$Content)

    $trimmed = $Content.Trim()
    if ($trimmed.StartsWith('```json', [StringComparison]::OrdinalIgnoreCase) -and $trimmed.EndsWith('```', [StringComparison]::Ordinal)) {
        $trimmed = $trimmed.Substring(7, $trimmed.Length - 10).Trim()
    }
    elseif ($trimmed.StartsWith('```', [StringComparison]::Ordinal) -and $trimmed.EndsWith('```', [StringComparison]::Ordinal)) {
        $trimmed = $trimmed.Substring(3, $trimmed.Length - 6).Trim()
    }
    $objectStart = $trimmed.IndexOf('{')
    $objectEnd = $trimmed.LastIndexOf('}')
    if ($objectStart -lt 0 -or $objectEnd -lt $objectStart) {
        throw 'Evaluator response does not contain a JSON object'
    }
    return $trimmed.Substring($objectStart, $objectEnd - $objectStart + 1)
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

function Read-AdjudicationCacheLedger {
    param([Parameter(Mandatory = $true)][string]$Path)

    $entries = @{}
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        return $entries
    }
    $ledger = Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json -DateKind String
    if (Compare-Object -ReferenceObject @('entries', 'kind', 'schemaVersion') -DifferenceObject @($ledger.PSObject.Properties.Name | Sort-Object)) {
        throw 'Rule Issue adjudication cache ledger has an unexpected property set'
    }
    if ([int]$ledger.schemaVersion -ne 1 -or [string]$ledger.kind -cne 'hosted-rule-issue-adjudication-cache') {
        throw 'Rule Issue adjudication cache ledger header is invalid'
    }
    foreach ($entry in @($ledger.entries)) {
        if (Compare-Object -ReferenceObject @('componentId', 'result', 'rules', 'sourceFiles') -DifferenceObject @($entry.PSObject.Properties.Name | Sort-Object)) {
            throw 'Rule Issue adjudication cache entry has an unexpected property set'
        }
        $componentId = [string]$entry.componentId
        if ($entries.ContainsKey($componentId)) {
            throw "Rule Issue adjudication cache contains duplicate component: $componentId"
        }
        $entries[$componentId] = $entry
    }
    return $entries
}

function Write-AdjudicationCacheLedger {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [object[]]$UpdatedEntries = @(),
        [string[]]$RemovedKeys = @()
    )

    return Invoke-WithExclusiveFileLock -Path ($Path + '.lock') -Operation {
        param($LedgerPath, $Updates, $Removals)

        $entries = Read-AdjudicationCacheLedger -Path $LedgerPath
        foreach ($componentId in @($Removals)) {
            $entries.Remove([string]$componentId)
        }
        foreach ($entry in @($Updates)) {
            $entries[[string]$entry.componentId] = $entry
        }
        Write-JsonAtomically -Path $LedgerPath -Value ([ordered]@{
            schemaVersion = 1
            kind = 'hosted-rule-issue-adjudication-cache'
            entries = @($entries.Values | Sort-Object -Property componentId)
        })
        return $entries
    } -ArgumentList @($Path, @($UpdatedEntries), @($RemovedKeys))
}

function Test-AdjudicationDraft {
    param(
        [Parameter(Mandatory = $true)][object]$Component,
        [Parameter(Mandatory = $true)][object]$Draft
    )

    if ([string]$Draft.componentId -cne [string]$Component.componentId) {
        throw 'Adjudication changed the component ID'
    }
    $inputRelationshipIds = @($Component.relationships.id | Sort-Object -CaseSensitive)
    $decisionIds = @($Draft.relationshipDecisions.relationshipId | Sort-Object -CaseSensitive)
    if (@(Compare-Object $inputRelationshipIds $decisionIds -SyncWindow 0).Count -ne 0 -or @($decisionIds | Sort-Object -Unique).Count -ne $decisionIds.Count) {
        throw 'Adjudication must decide every input relationship exactly once'
    }
    $knownRuleIds = [Collections.Generic.HashSet[string]]::new([string[]]@($Component.rules.id), [StringComparer]::Ordinal)
    $knownOperationKeys = [Collections.Generic.HashSet[string]]::new([string[]]@($Component.operations.candidateKey), [StringComparer]::Ordinal)
    $relationshipById = @{}
    foreach ($relationship in @($Component.relationships)) {
        $relationshipById[[string]$relationship.id] = $relationship
    }
    $decisionById = @{}
    foreach ($decision in @($Draft.relationshipDecisions)) {
        $decisionById[[string]$decision.relationshipId] = $decision
    }
    $usedRelationshipIds = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    foreach ($issue in @($Draft.issues)) {
        if (-not $knownRuleIds.Contains([string]$issue.anchorRuleId)) {
            throw 'Adjudication issue anchor must identify a known component rule'
        }
        $issueRuleIds = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
        foreach ($ruleId in @($issue.ruleIds)) {
            if (-not $knownRuleIds.Contains([string]$ruleId) -or -not $issueRuleIds.Add([string]$ruleId)) {
                throw 'Adjudication issue contains an unknown or duplicate rule ID'
            }
        }
        if (-not $issueRuleIds.Contains([string]$issue.anchorRuleId)) {
            throw 'Adjudication issue does not include its anchor rule'
        }
        $displayTextFields = [ordered]@{
            title = [string]$issue.title
            bannerTitle = [string]$issue.bannerTitle
            bannerMessage = [string]$issue.bannerMessage
            assessmentSummary = [string]$issue.assessmentSummary
            recommendedMaintainerAction = [string]$issue.recommendedMaintainerAction.summary
        }
        if ([string]$issue.wording.status -ceq 'unresolved') {
            $displayTextFields['wordingReason'] = [string]$issue.wording.reason
        }
        foreach ($field in $displayTextFields.GetEnumerator()) {
            foreach ($match in [regex]::Matches([string]$field.Value, '\b[A-Z]+(?:-[A-Z0-9]+)+-[0-9]{3}[A-Z]?\b')) {
                if (-not $issueRuleIds.Contains([string]$match.Value)) {
                    throw "Adjudication issue $($field.Key) references non-member rule ID $($match.Value)"
                }
            }
        }
        $dispositionRuleIds = @($issue.ruleDispositions.ruleId | Sort-Object -CaseSensitive)
        if (@(Compare-Object @($issue.ruleIds | Sort-Object -CaseSensitive) $dispositionRuleIds -SyncWindow 0).Count -ne 0 -or @($dispositionRuleIds | Sort-Object -Unique).Count -ne $dispositionRuleIds.Count) {
            throw 'Adjudication issue must assign one disposition to every member rule'
        }
        foreach ($relationshipId in @($issue.relationshipIds)) {
            if (-not $relationshipById.ContainsKey([string]$relationshipId) -or -not $usedRelationshipIds.Add([string]$relationshipId)) {
                throw 'Adjudication issue contains an unknown or duplicate relationship ID'
            }
            $decision = $decisionById[[string]$relationshipId]
            if ([string]$decision.disposition -cne 'issue') {
                throw 'Adjudication issue references an independent relationship'
            }
            $relationship = $relationshipById[[string]$relationshipId]
            if (-not $issueRuleIds.Contains([string]$relationship.sourceRuleId) -or -not $issueRuleIds.Contains([string]$relationship.relatedRuleId)) {
                throw 'Adjudication issue omits a relationship member rule'
            }
        }
        $dispositionByRuleId = @{}
        foreach ($entry in @($issue.ruleDispositions)) {
            $dispositionByRuleId[[string]$entry.ruleId] = [string]$entry.disposition
        }
        $candidateOperationByKey = @{}
        foreach ($operation in @($Component.operations)) {
            $candidateOperationByKey[[string]$operation.candidateKey] = $operation
        }
        $selectedOperations = @($issue.recommendedMaintainerAction.operations)
        $selectedCandidateKeys = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
        foreach ($operation in $selectedOperations) {
            $candidateKey = [string]$operation.candidateKey
            if (-not $knownOperationKeys.Contains($candidateKey) -or -not $selectedCandidateKeys.Add($candidateKey)) {
                throw 'Adjudication operation contains an unknown or duplicate candidate key'
            }
            $candidateOperation = $candidateOperationByKey[$candidateKey]
            if ([string]$operation.ruleId -cne [string]$candidateOperation.ruleId -or -not $issueRuleIds.Contains([string]$operation.ruleId)) {
                throw 'Adjudication operation changed candidate-owned rule identity or references a non-member rule'
            }
            $operationRule = @($Component.rules | Where-Object { [string]$_.id -ceq [string]$operation.ruleId })[0]
            $allowedActions = switch ([string]$operationRule.status) {
                'active' { @('update', 'retire', 'defer') }
                'retired' { @('restore', 'defer') }
                'proposed' { @('add', 'exclude', 'defer') }
                default { @() }
            }
            if ([string]$operation.action -notin $allowedActions) {
                throw "Adjudication action $($operation.action) is invalid for $($operation.ruleId) with status $($operationRule.status)"
            }
            foreach ($retireRuleId in @($operation.retireHostedRuleIds)) {
                $retireRule = @($Component.rules | Where-Object { [string]$_.id -ceq [string]$retireRuleId })[0]
                if ($null -eq $retireRule -or [string]$retireRule.status -cne 'active') {
                    throw 'Adjudication can retire only known active member rules'
                }
            }
            $expectedDisposition = switch ([string]$operation.action) {
                'add' { 'promote' }
                'restore' { 'promote' }
                'update' { 'replace' }
                'retire' { 'retire' }
                'exclude' { 'exclude' }
                'defer' { 'defer' }
            }
            if ([string]$dispositionByRuleId[[string]$operation.ruleId] -cne $expectedDisposition) {
                throw "Adjudication disposition for $($operation.ruleId) does not match selected action $($operation.action)"
            }
        }
        $protectedRules = @($Component.rules | Where-Object { [string]$_.id -in @($issue.ruleIds) -and [string]$_.status -ceq 'protected' })
        $protectedRuleIds = @($protectedRules | ForEach-Object { [string]$_.id })
        $protectedDispositions = @($issue.ruleDispositions | Where-Object { [string]$_.ruleId -in $protectedRuleIds -and [string]$_.disposition -cne 'keep' })
        if ($protectedDispositions.Count -gt 0) {
            throw 'Protected rules must have keep disposition'
        }
        if ($protectedRules.Count -gt 1) {
            if ([string]$issue.classification -cne 'protected-integrity' -or -not [bool]$issue.blocking -or [string]$issue.wording.status -cne 'unresolved') {
                throw 'Multiple protected rules require blocking protected-integrity adjudication with unresolved wording'
            }
        }
        elseif ($protectedRules.Count -eq 1) {
            if ([string]$issue.classification -notin @('protected-conflict', 'protected-coverage') -or [bool]$issue.blocking) {
                throw 'Single-protected-rule adjudication has an invalid classification or blocking state'
            }
            if ([string]$issue.wording.status -cne 'canonical' -or [string]$issue.wording.sourceRuleId -cne [string]$protectedRules[0].id -or [string]$issue.wording.text -cne [string]$protectedRules[0].text) {
                throw 'Single-protected-rule adjudication must preserve exact canonical wording'
            }
        }
        elseif ([string]$issue.classification -like 'protected-*') {
            throw 'Non-protected adjudication cannot use a protected classification'
        }
        if ([string]$issue.wording.status -ceq 'selected') {
            $matchingOperations = @($selectedOperations | Where-Object { [string]$_.ruleId -ceq [string]$issue.wording.sourceRuleId -and [string]$_.action -in @('add', 'update', 'restore') -and [string]$_.proposedText -ceq [string]$issue.wording.text })
            $member = @($Component.rules | Where-Object { [string]$_.id -ceq [string]$issue.wording.sourceRuleId })[0]
            $memberSuppliesWording = $null -ne $member -and [string]$member.text -ceq [string]$issue.wording.text -and [string]$dispositionByRuleId[[string]$member.id] -in @('keep', 'promote')
            if ($matchingOperations.Count -ne 1 -and -not $memberSuppliesWording) {
                throw 'Selected adjudication wording must match one final mutation or one exact retained member'
            }
            if ([string]$issue.wording.presentation -ceq 'member' -and -not $memberSuppliesWording) {
                throw 'Member-presented wording must match one retained or promoted member exactly'
            }
        }
        $issueRelationshipKinds = @($issue.relationshipIds | ForEach-Object { [string]$decisionById[[string]$_].relationship })
        $expectedClassification = if ($protectedRules.Count -gt 1) {
            'protected-integrity'
        }
        elseif ($protectedRules.Count -eq 1 -and 'conflicts' -in $issueRelationshipKinds) {
            'protected-conflict'
        }
        elseif ($protectedRules.Count -eq 1) {
            'protected-coverage'
        }
        elseif ('conflicts' -in $issueRelationshipKinds) {
            'contradiction'
        }
        elseif (@($issueRelationshipKinds | Where-Object { $_ -cne 'equivalent' }).Count -eq 0) {
            'duplicate'
        }
        else {
            'overlap'
        }
        if ([string]$issue.classification -cne $expectedClassification) {
            throw "Adjudication classification $($issue.classification) does not match relationship evidence $expectedClassification"
        }
    }
    $materialDecisionIds = @($Draft.relationshipDecisions | Where-Object { [string]$_.disposition -ceq 'issue' } | ForEach-Object { [string]$_.relationshipId } | Sort-Object -CaseSensitive)
    if (@(Compare-Object $materialDecisionIds @($usedRelationshipIds | Sort-Object -CaseSensitive) -SyncWindow 0).Count -ne 0) {
        throw 'Every material relationship must appear in exactly one adjudicated issue'
    }
}

$resolvedRepositoryRoot = [IO.Path]::GetFullPath($RepositoryRoot).TrimEnd([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar)
$repositoryPrefix = $resolvedRepositoryRoot + [IO.Path]::DirectorySeparatorChar
$resolvedOutputPath = [IO.Path]::GetFullPath($OutputPath)
$resolvedCacheDirectory = [IO.Path]::GetFullPath($CacheDirectory)
foreach ($externalPath in @($resolvedOutputPath, $resolvedCacheDirectory)) {
    if ($externalPath.StartsWith($repositoryPrefix, [StringComparison]::OrdinalIgnoreCase)) {
        throw 'Rule Issue adjudication output and cache paths must be outside the repository root'
    }
}
$resolvedInputSchemaPath = [IO.Path]::GetFullPath($InputSchemaPath)
$resolvedDraftSchemaPath = [IO.Path]::GetFullPath($DraftSchemaPath)
$resolvedPromptPath = [IO.Path]::GetFullPath($PromptPath)
foreach ($requiredPath in @($resolvedInputSchemaPath, $resolvedDraftSchemaPath, $resolvedPromptPath)) {
    if (-not (Test-Path -LiteralPath $requiredPath -PathType Leaf)) {
        throw "Required Rule Issue adjudication file was not found: $requiredPath"
    }
}
$resolvedComponentPaths = @($ComponentPaths | ForEach-Object { [IO.Path]::GetFullPath($_) })
if ($resolvedComponentPaths.Count -eq 0) {
    throw 'Rule Issue adjudication requires at least one component'
}
$resolvedEvaluatorScriptPath = if ([string]::IsNullOrWhiteSpace($EvaluatorScriptPath)) { $null } else { [IO.Path]::GetFullPath($EvaluatorScriptPath) }
$resolvedResumeRunDirectory = if ([string]::IsNullOrWhiteSpace($ResumeRunDirectory)) { $null } else { [IO.Path]::GetFullPath($ResumeRunDirectory) }
$runDirectory = Join-Path ([IO.Path]::GetTempPath()) ('hosted-rule-issue-adjudication/' + [Guid]::NewGuid().ToString('N'))
$batchRoot = Join-Path $runDirectory 'components'
$null = New-Item -ItemType Directory -Path $batchRoot -Force
$batches = [Collections.Generic.List[object]]::new()
foreach ($componentPath in $resolvedComponentPaths) {
    $componentJson = Get-Content -LiteralPath $componentPath -Raw
    if (-not ($componentJson | Test-Json -SchemaFile $resolvedInputSchemaPath -ErrorAction Stop)) {
        throw "Rule Issue adjudication input does not satisfy its schema: $componentPath"
    }
    $component = $componentJson | ConvertFrom-Json -DateKind String
    $number = $batches.Count + 1
    $directory = Join-Path $batchRoot ('component-{0:D3}' -f $number)
    $null = New-Item -ItemType Directory -Path $directory -Force
    $inputPath = Join-Path $directory 'rule-issue-adjudication-input.json'
    [IO.File]::WriteAllText($inputPath, $componentJson, [Text.UTF8Encoding]::new($false))
    [IO.File]::WriteAllBytes((Join-Path $directory 'rule-issue-adjudication-input-v4.schema.json'), [IO.File]::ReadAllBytes($resolvedInputSchemaPath))
    [IO.File]::WriteAllBytes((Join-Path $directory 'rule-issue-adjudication-draft-v4.schema.json'), [IO.File]::ReadAllBytes($resolvedDraftSchemaPath))
    [IO.File]::WriteAllBytes((Join-Path $directory 'RuleIssueAdjudication-v4.md'), [IO.File]::ReadAllBytes($resolvedPromptPath))
    $batches.Add([pscustomobject]@{
        Number = $number
        ComponentId = [string]$component.componentId
        Directory = $directory
        InputPath = $inputPath
        Input = $component
        RelationshipCount = @($component.relationships).Count
        SourceFiles = @($component.sourceFiles)
        Rules = @($component.rules | ForEach-Object { [ordered]@{ id = [string]$_.id; status = [string]$_.status; contentSha256 = [string]$_.contentSha256 } })
        PayloadSizeBytes = [long]((Get-Item -LiteralPath $inputPath).Length + (Get-Item -LiteralPath $resolvedPromptPath).Length)
    })
}

$cacheLedgerPath = Join-Path $resolvedCacheDirectory 'rule-issue-adjudication-cache.json'
$cacheEntries = Invoke-WithExclusiveFileLock -Path ($cacheLedgerPath + '.lock') -Operation {
    param($LedgerPath)
    try { Read-AdjudicationCacheLedger -Path $LedgerPath }
    catch {
        Remove-Item -LiteralPath $LedgerPath -Force -ErrorAction SilentlyContinue
        return @{}
    }
} -ArgumentList @($cacheLedgerPath)
$validatedDrafts = @{}
$cachedCount = 0
foreach ($batch in $batches) {
    if (-not $cacheEntries.ContainsKey($batch.ComponentId)) { continue }
    $entry = $cacheEntries[$batch.ComponentId]
    try {
        if ((@($entry.sourceFiles) | ConvertTo-Json -Compress) -cne (@($batch.SourceFiles) | ConvertTo-Json -Compress) -or
            (@($entry.rules) | ConvertTo-Json -Compress) -cne (@($batch.Rules) | ConvertTo-Json -Compress)) {
            throw 'cached Rule Issue adjudication inputs do not match'
        }
        $draftJson = $entry.result | ConvertTo-Json -Depth 100
        if (-not ($draftJson | Test-Json -SchemaFile $resolvedDraftSchemaPath -ErrorAction Stop)) {
            throw 'cached Rule Issue adjudication does not satisfy its schema'
        }
        $draft = $draftJson | ConvertFrom-Json -DateKind String
        Test-AdjudicationDraft -Component $batch.Input -Draft $draft
        $validatedDrafts[$batch.ComponentId] = $draft
        $cachedCount++
    }
    catch {
        $cacheEntries = Write-AdjudicationCacheLedger -Path $cacheLedgerPath -RemovedKeys @($batch.ComponentId)
    }
}

if ($null -ne $resolvedResumeRunDirectory -and (Test-Path -LiteralPath $resolvedResumeRunDirectory -PathType Container)) {
    foreach ($batch in $batches) {
        if ($validatedDrafts.ContainsKey($batch.ComponentId)) { continue }
        $retainedDirectory = Join-Path $resolvedResumeRunDirectory ('components/component-{0:D3}' -f $batch.Number)
        $retainedInputPath = Join-Path $retainedDirectory 'rule-issue-adjudication-input.json'
        $retainedDraftPath = Join-Path $retainedDirectory 'rule-issue-adjudication-draft.json'
        if (-not (Test-Path -LiteralPath $retainedInputPath -PathType Leaf) -or -not (Test-Path -LiteralPath $retainedDraftPath -PathType Leaf)) { continue }
        try {
            $retainedInput = Get-Content -LiteralPath $retainedInputPath -Raw | ConvertFrom-Json -DateKind String
            if ((@($retainedInput.sourceFiles) | ConvertTo-Json -Compress) -cne (@($batch.SourceFiles) | ConvertTo-Json -Compress) -or
                (@($retainedInput.rules | ForEach-Object { [ordered]@{ id = [string]$_.id; status = [string]$_.status; contentSha256 = [string]$_.contentSha256 } }) | ConvertTo-Json -Compress) -cne (@($batch.Rules) | ConvertTo-Json -Compress)) {
                continue
            }
            $draftJson = Get-Content -LiteralPath $retainedDraftPath -Raw
            if (-not ($draftJson | Test-Json -SchemaFile $resolvedDraftSchemaPath -ErrorAction Stop)) { continue }
            $draft = $draftJson | ConvertFrom-Json -DateKind String
            Test-AdjudicationDraft -Component $batch.Input -Draft $draft
            $validatedDrafts[$batch.ComponentId] = $draft
            $cacheUpdate = [ordered]@{ componentId = $batch.ComponentId; sourceFiles = @($batch.SourceFiles); rules = @($batch.Rules); result = $draft }
            $cacheEntries = Write-AdjudicationCacheLedger -Path $cacheLedgerPath -UpdatedEntries @($cacheUpdate)
        }
        catch { }
    }
}

$pendingBatches = @($batches | Where-Object { -not $validatedDrafts.ContainsKey($_.ComponentId) })
$evaluationBatchCount = $pendingBatches.Count
for ($pendingIndex = 0; $pendingIndex -lt $pendingBatches.Count; $pendingIndex++) {
    $pendingBatches[$pendingIndex] | Add-Member -NotePropertyName ProgressNumber -NotePropertyValue ($pendingIndex + 1) -Force
}
if (-not $Quiet) {
    $pendingPayload = if ($pendingBatches.Count -eq 0) { 0L } else { [long]@($pendingBatches | Measure-Object -Property PayloadSizeBytes -Sum)[0].Sum }
    $pendingRelationshipCount = if ($pendingBatches.Count -eq 0) { 0 } else { [int]@($pendingBatches | Measure-Object -Property RelationshipCount -Sum)[0].Sum }
    $totalRelationshipCount = @($batches | Measure-Object -Property RelationshipCount -Sum)[0].Sum
    $activeWorkerCount = [Math]::Max(1, [Math]::Min($MaxParallelBatches, $pendingBatches.Count))
    $initialEstimate = Get-EstimatedRemainingMilliseconds -CompletedPayloadBytes 0 -CompletedElapsedMilliseconds 0 -RemainingPayloadBytes $pendingPayload -MaxParallelBatches $activeWorkerCount -BootstrapBytesPerSecondPerWorker $adjudicationBootstrapBytesPerSecondPerWorker
    Write-ValidationSummary -Fields ([ordered]@{
        Relationships = "{0} total | {1} pending" -f $totalRelationshipCount, $pendingRelationshipCount
        Components = "{0} total | {1} cached | {2} pending" -f $batches.Count, $cachedCount, $pendingBatches.Count
        Workers = $MaxParallelBatches
        Payload = Format-ByteSize -Bytes $pendingPayload
        Estimated = Format-ElapsedDuration -Milliseconds $initialEstimate
    }) | Write-Host
    if ($pendingBatches.Count -gt 0) { Complete-ValidationTextOutput | Write-Host }
}

$evaluatorCommandPath = $null
if ($pendingBatches.Count -gt 0 -and $null -eq $resolvedEvaluatorScriptPath) {
    $command = Get-Command $EvaluatorCommand -ErrorAction SilentlyContinue
    if ($null -eq $command) { throw "Evaluator command was not found: $EvaluatorCommand" }
    $evaluatorCommandPath = $command.Source
}
$batchErrors = @{}
for ($attempt = 1; $attempt -le ($MaxRetries + 1) -and $pendingBatches.Count -gt 0; $attempt++) {
    $retryBatches = [Collections.Generic.List[object]]::new()
    $workerEvaluatorScriptPath = $resolvedEvaluatorScriptPath
    $workerEvaluatorCommandPath = $evaluatorCommandPath
    $workerModel = $Model
    $workerReasoningEffort = $ReasoningEffort
    $pendingBatches | ForEach-Object -Parallel {
        $batch = $_
        [pscustomobject]@{ Kind = 'started'; Number = $batch.Number; ProgressNumber = $batch.ProgressNumber; ComponentId = $batch.ComponentId; RelationshipCount = $batch.RelationshipCount; Attempt = $using:attempt }
        $batchStopwatch = [Diagnostics.Stopwatch]::StartNew()
        $output = @()
        try {
            $responsePath = Join-Path $batch.Directory 'rule-issue-adjudication-draft.json'
            if ($null -ne $using:workerEvaluatorScriptPath) {
                $parameters = @{
                    InputPath = $batch.InputPath
                    SchemaPath = Join-Path $batch.Directory 'rule-issue-adjudication-draft-v4.schema.json'
                    PromptPath = Join-Path $batch.Directory 'RuleIssueAdjudication-v4.md'
                    OutputPath = $responsePath
                    Model = $using:workerModel
                    ReasoningEffort = $using:workerReasoningEffort
                }
                $output = @(& pwsh -NoProfile -File $using:workerEvaluatorScriptPath @parameters 2>&1)
                if ($LASTEXITCODE -ne 0) { throw "Evaluator script failed: $(($output | Out-String).Trim())" }
            }
            else {
                $prompt = 'Read rule-issue-adjudication-input.json, rule-issue-adjudication-draft-v4.schema.json, and RuleIssueAdjudication-v4.md in the current directory. Adjudicate every provisional relationship and write only the requested JSON object in your final response.'
                $output = @(& $using:workerEvaluatorCommandPath -C $batch.Directory -p $prompt --no-color --stream off --no-custom-instructions --no-ask-user --disable-builtin-mcps --no-auto-update --disallow-temp-dir --model $using:workerModel --effort $using:workerReasoningEffort --available-tools=view --output-format json 2>&1)
                if ($LASTEXITCODE -ne 0) { throw "Copilot evaluator exited with code $LASTEXITCODE" }
            }
            [pscustomobject]@{ Kind = 'completed'; Number = $batch.Number; Succeeded = $true; ElapsedMilliseconds = [long]$batchStopwatch.ElapsedMilliseconds; Output = @($output | ForEach-Object { [string]$_ }); Error = '' }
        }
        catch {
            [pscustomobject]@{ Kind = 'completed'; Number = $batch.Number; Succeeded = $false; ElapsedMilliseconds = [long]$batchStopwatch.ElapsedMilliseconds; Output = @($output | ForEach-Object { [string]$_ }); Error = [string]$_.Exception.Message }
        }
    } -ThrottleLimit $MaxParallelBatches | ForEach-Object {
        $workerResult = $_
        $batch = @($batches | Where-Object Number -eq ([int]$workerResult.Number))[0]
        if ([string]$workerResult.Kind -ceq 'started') {
            if (-not $Quiet -and [int]$workerResult.Attempt -eq 1) {
                Write-Host (Format-ValidationStatusLine -Status 'running' -Name ("rule-issue-adjudication {0}/{1}" -f $batch.ProgressNumber, $evaluationBatchCount) -Detail ("{0} ({1} relationships)" -f $batch.ComponentId, $batch.RelationshipCount) -NameWidth 42)
            }
            return
        }
        $responsePath = Join-Path $batch.Directory 'rule-issue-adjudication-draft.json'
        try {
            if (-not [bool]$workerResult.Succeeded) { throw [string]$workerResult.Error }
            if ($null -eq $resolvedEvaluatorScriptPath) {
                $assistantMessages = @($workerResult.Output | ForEach-Object {
                    $line = ([string]$_).Trim()
                    if (-not [string]::IsNullOrWhiteSpace($line)) {
                        try { $event = $line | ConvertFrom-Json } catch { throw "Copilot evaluator returned a non-JSONL event: $line" }
                        if ($event.type -eq 'assistant.message' -and -not [string]::IsNullOrWhiteSpace([string]$event.data.content)) { $event.data }
                    }
                })
                if ($assistantMessages.Count -eq 0) { throw 'Copilot evaluator did not return an assistant message' }
                if ([string]$assistantMessages[-1].model -cne $Model) { throw "Copilot evaluator used model $($assistantMessages[-1].model) instead of $Model" }
                [IO.File]::WriteAllText($responsePath, (Get-EvaluatorJson -Content ([string]$assistantMessages[-1].content)) + "`n", [Text.UTF8Encoding]::new($false))
            }
            $draftJson = Get-Content -LiteralPath $responsePath -Raw
            if (-not ($draftJson | Test-Json -SchemaFile $resolvedDraftSchemaPath -ErrorAction Stop)) { throw 'Rule Issue adjudication draft does not satisfy its schema' }
            $draft = $draftJson | ConvertFrom-Json -DateKind String
            Test-AdjudicationDraft -Component $batch.Input -Draft $draft
            $validatedDrafts[$batch.ComponentId] = $draft
            $cacheUpdate = [ordered]@{ componentId = $batch.ComponentId; sourceFiles = @($batch.SourceFiles); rules = @($batch.Rules); result = $draft }
            $cacheEntries = Write-AdjudicationCacheLedger -Path $cacheLedgerPath -UpdatedEntries @($cacheUpdate)
            $batchErrors.Remove($batch.ComponentId)
            if (-not $Quiet) {
                Write-Host (Format-ValidationStatusLine -Status 'passed' -Name ("rule-issue-adjudication {0}/{1}" -f $batch.ProgressNumber, $evaluationBatchCount) -Detail ("Total Elapsed {0} : [Batch: {1}]" -f (Format-ElapsedDuration -Milliseconds ([long]$stopwatch.ElapsedMilliseconds)), (Format-ElapsedDuration -Milliseconds ([long]$workerResult.ElapsedMilliseconds))) -NameWidth 42)
            }
        }
        catch {
            $batchErrors[$batch.ComponentId] = [string]$_.Exception.Message
            $retryBatches.Add($batch)
            if (-not $Quiet) {
                foreach ($diagnosticLine in @(Format-IndentedDiagnostic -Label ("[ERROR] Component {0}/{1}:" -f $batch.ProgressNumber, $evaluationBatchCount) -Message ([string]$_.Exception.Message))) {
                    Write-Host $diagnosticLine
                }
                Write-Host (Format-ValidationStatusLine -Status $(if ($attempt -le $MaxRetries) { 'retrying' } else { 'failed' }) -Name ("rule-issue-adjudication {0}/{1}" -f $batch.ProgressNumber, $evaluationBatchCount) -Detail ("Total Elapsed {0} : [Batch: {1}]" -f (Format-ElapsedDuration -Milliseconds ([long]$stopwatch.ElapsedMilliseconds)), (Format-ElapsedDuration -Milliseconds ([long]$workerResult.ElapsedMilliseconds))) -NameWidth 42)
            }
        }
    }
    $pendingBatches = @($retryBatches.ToArray())
}
if ($pendingBatches.Count -gt 0) {
    $details = @($pendingBatches | ForEach-Object { "$($_.ComponentId): $($batchErrors[$_.ComponentId])" })
    throw "Rule Issue adjudication failed after $($MaxRetries + 1) attempts: $($details -join '; '). Run artifacts were retained at $runDirectory"
}

$resultSet = [ordered]@{
    schemaVersion = 1
    kind = 'hosted-rule-issue-adjudication-set'
    components = @($batches | Sort-Object Number | ForEach-Object { $validatedDrafts[$_.ComponentId] })
}
Write-JsonAtomically -Path $resolvedOutputPath -Value $resultSet
Remove-Item -LiteralPath $runDirectory -Recurse -Force -ErrorAction SilentlyContinue
$result = [ordered]@{
    status = 'passed'
    outputPath = $resolvedOutputPath
    componentCount = $batches.Count
    cachedComponentCount = $cachedCount
    evaluatedComponentCount = $batches.Count - $cachedCount
    cacheDirectory = $resolvedCacheDirectory
    elapsed = Format-ElapsedDuration -Milliseconds ([long]$stopwatch.ElapsedMilliseconds)
}
if ($OutputFormat -eq 'Json') { $result | ConvertTo-Json -Compress }
else { $result | Format-List | Out-String | Write-Output }
