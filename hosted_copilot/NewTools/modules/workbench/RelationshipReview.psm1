Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Import-Module (Join-Path $PSScriptRoot '../shared/HostedToolkit.Helpers.psm1')

function New-RelationshipReviewException {
    param([Parameter(Mandatory)][string]$Code)
    $exception = [InvalidOperationException]::new($Code)
    $exception.Data['RelationshipReviewCode'] = $Code
    return $exception
}

function Wait-RelationshipReviewTask {
    param(
        [Parameter(Mandatory)][Threading.Tasks.Task]$Task,
        [Parameter(Mandatory)][Diagnostics.Stopwatch]$Watch,
        [Parameter(Mandatory)][int]$DeadlineMilliseconds
    )

    $remaining = $DeadlineMilliseconds - [int]$Watch.ElapsedMilliseconds
    if ($remaining -le 0 -or -not $Task.Wait($remaining)) { throw (New-RelationshipReviewException 'deadline') }
    return $Task.GetAwaiter().GetResult()
}

function Get-RelationshipReviewFailure {
    param([Parameter(Mandatory)][string]$Code)
    $policies = @{
        'invalid-response' = @('The checker could not produce a usable result. Your saved rule is unchanged. Try again.', $true, 'retry')
        'service-unavailable' = @('The checking service is temporarily unavailable. Your saved rule is unchanged. Try again.', $true, 'retry')
        'deadline' = @('The relationship check reached its five-minute limit. No result was accepted. Try again.', $true, 'retry')
        'snapshot-changed' = @('The rule or catalog changed. Save the current wording or reload the Workbench, then run a new check.', $false, 'refresh-snapshot')
        'invalid-request' = @('The current proposal cannot be checked. Review its action and rule identity, then save it again.', $false, 'correct-proposal')
        'runtime-unavailable' = @('The relationship checker could not use its configured evaluator. Check GitHub Copilot authentication and configured model access, then restart the Workbench.', $false, 'restart')
        'unexpected-failure' = @('The relationship check could not be completed. No result was accepted. Report the failure code and recovery action shown with this error; no raw evaluator output is exposed.', $false, 'report-failure')
    }
    if (-not $policies.ContainsKey($Code)) { $Code = 'unexpected-failure' }
    $policy = $policies[$Code]
    return [ordered]@{ code = $Code; message = $policy[0]; retryable = $policy[1]; recovery = $policy[2] }
}

function Get-RelationshipReviewRuntime {
    param([Parameter(Mandatory)][string]$RepositoryRoot, [Parameter(Mandatory)][string]$DisplayPath)
    $paths = @(
        'hosted_copilot/NewTools/modules/workbench/RelationshipReview.psm1',
        'hosted_copilot/NewTools/modules/workbench/RuleAssistance.psm1',
        'hosted_copilot/NewTools/modules/workbench/SavedRuleEvaluation.psm1',
        'hosted_copilot/NewTools/modules/shared/HostedToolkit.Helpers.psm1',
        'hosted_copilot/NewTools/modules/shared/HostedCli.psm1',
        'hosted_copilot/NewContracts/workbench/workbench-display-v4.schema.json',
        'hosted_copilot/NewTools/internal/workbench/Invoke-RelationshipReview.ps1',
        'hosted_copilot/NewTools/prompts/reconciliation/RelationshipReview-v1.md'
    )
    $profile = Resolve-HostedLlmProfile -Profile ruleEvaluation
    $authority = [ordered]@{
        display = Get-Sha256 -Path $DisplayPath
        files = @($paths | ForEach-Object { [ordered]@{ path = $_; sha256 = Get-Sha256 -Path (Join-Path $RepositoryRoot $_) } })
        model = $profile.model; reasoningEffort = $profile.reasoningEffort
    }
    return [ordered]@{ schemaVersion = 1; authoritySha256 = Get-JsonSnapshotSha256 -Value $authority; model = $profile.model; reasoningEffort = $profile.reasoningEffort; deadlineMilliseconds = 300000 }
}

function Start-RelationshipReviewRequest {
    param(
        [Parameter(Mandatory)][Management.Automation.Runspaces.RunspacePool]$RunspacePool,
        [Parameter(Mandatory)][Net.Sockets.TcpClient]$Client,
        [Parameter(Mandatory)][string]$RequestBody,
        [Parameter(Mandatory)][Collections.IDictionary]$Parameters
    )
    Import-Module (Join-Path $PSScriptRoot 'SavedRuleEvaluation.psm1')
    $directory = Join-Path ([IO.Path]::GetTempPath()) ('hosted-relationship-review-' + [guid]::NewGuid().ToString('N'))
    $null = [IO.Directory]::CreateDirectory($directory)
    try {
        $envelope = $RequestBody | ConvertFrom-Json -Depth 5 -DateKind String
        Assert-RelationshipReviewProperties $envelope @('payloadBase64')
        $bytes = [Convert]::FromBase64String([string]$envelope.payloadBase64)
        $json = [Text.UTF8Encoding]::new($false, $true).GetString($bytes)
        $requestPath = Join-Path $directory 'request.json'
        [IO.File]::WriteAllText($requestPath, $json, [Text.UTF8Encoding]::new($false))
        $workerParameters = @{} + $Parameters
        $workerParameters.RequestPath = $requestPath
        $workerParameters.OutputPath = Join-Path $directory 'response.json'
        return Start-SavedRuleEvaluationRequest -RunspacePool $RunspacePool -Client $Client -OperationName 'Relationship review' -CleanupDirectory $directory -ScriptPath (Join-Path $PSScriptRoot '../../internal/workbench/Invoke-RelationshipReview.ps1') -Parameters $workerParameters
    } catch {
        Remove-Item -LiteralPath $directory -Recurse -Force
        throw (New-RelationshipReviewException 'invalid-request')
    }
}

function Assert-RelationshipReviewProperties {
    param([object]$Value, [string[]]$Names)
    if ($null -eq $Value -or (@($Value.PSObject.Properties.Name | Sort-Object -CaseSensitive) -join "`0") -cne (@($Names | Sort-Object -CaseSensitive) -join "`0")) {
        throw (New-RelationshipReviewException 'invalid-request')
    }
}

function Get-RelationshipReviewInput {
    param([Parameter(Mandatory)][object]$Display, [Parameter(Mandatory)][object]$Request, [switch]$PlanOnly)

    Assert-RelationshipReviewProperties $Request @('schemaVersion', 'requestId', 'authoritySha256', 'snapshotKey', 'candidateKey', 'sourceFiles', 'proposals')
    if ($Request.schemaVersion -ne 1 -or [string]$Request.requestId -cnotmatch '^[a-f0-9-]{36}$' -or
        [string]$Request.authoritySha256 -cnotmatch '^[a-f0-9]{64}$' -or [string]$Request.snapshotKey -cnotmatch '^[a-f0-9]{64}$') {
        throw (New-RelationshipReviewException 'invalid-request')
    }
    $identity = { param($files) @($files | ForEach-Object { "$($_.sourceDefinitionId)`0$($_.sourceId)`0$($_.contentSha256)" } | Sort-Object -CaseSensitive) -join "`n" }
    if ((& $identity $Request.sourceFiles) -cne (& $identity $Display.sourceFiles)) { throw (New-RelationshipReviewException 'snapshot-changed') }
    $rules = [Collections.Generic.Dictionary[string, object]]::new([StringComparer]::Ordinal)
    foreach ($rule in @($Display.catalog.rules)) {
        $status = [string]$rule.status
        if ($rules.ContainsKey([string]$rule.id)) { throw (New-RelationshipReviewException 'invalid-request') }
        $rules.Add([string]$rule.id, [ordered]@{ id = [string]$rule.id; status = $status; text = [string]$rule.text })
    }
    foreach ($rule in @($Display.catalog.protectedRules)) {
        if ($rules.ContainsKey([string]$rule.id)) { throw (New-RelationshipReviewException 'invalid-request') }
        $rules.Add([string]$rule.id, [ordered]@{ id = [string]$rule.id; status = 'protected'; text = [string]$rule.text })
    }
    $records = [Collections.Generic.Dictionary[string, object]]::new([StringComparer]::Ordinal)
    foreach ($candidate in $Display.candidates) {
        $key = "$($candidate.source.lane):$($candidate.source.id):$($candidate.assessment.id)"
        $id = if ($null -ne $candidate.catalogMapping.hostedRuleId) { [string]$candidate.catalogMapping.hostedRuleId } else { [string]$candidate.recommendation.hostedId }
        if ([string]::IsNullOrWhiteSpace($id)) { continue }
        if ($records.ContainsKey($key) -or ($rules.ContainsKey($id) -and $rules[$id].status -ceq 'protected')) {
            throw (New-RelationshipReviewException 'invalid-request')
        }
        $records.Add($key, [ordered]@{ candidate = $candidate; id = $id; proposal = $null })
    }
    if (-not $records.ContainsKey([string]$Request.candidateKey)) { throw (New-RelationshipReviewException 'invalid-request') }
    $seen = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    foreach ($proposal in @($Request.proposals)) {
        Assert-RelationshipReviewProperties $proposal @('candidateKey', 'sourceHash', 'action', 'inPlan', 'proposedTextBase64', 'retireHostedRuleIds')
        $key = [string]$proposal.candidateKey
        if (-not $records.ContainsKey($key) -or -not $seen.Add($key) -or $proposal.inPlan -isnot [bool]) { throw (New-RelationshipReviewException 'invalid-request') }
        $record = $records[$key]
        if ([string]$proposal.sourceHash -cne [string]$record.candidate.source.contentSha256) { throw (New-RelationshipReviewException 'snapshot-changed') }
        try { $text = [Text.UTF8Encoding]::new($false, $true).GetString([Convert]::FromBase64String([string]$proposal.proposedTextBase64)) }
        catch { throw (New-RelationshipReviewException 'invalid-request') }
        if ([string]::IsNullOrWhiteSpace($text) -or $text.Length -gt 20000) { throw (New-RelationshipReviewException 'invalid-request') }
        $status = if ($rules.ContainsKey($record.id)) { $rules[$record.id].status } else { 'proposed' }
        $allowed = switch ($status) { 'active' { @('no-change', 'update', 'retire', 'defer') } 'retired' { @('no-change', 'restore', 'defer') } default { @('no-change', 'add', 'exclude', 'defer') } }
        if (($proposal.inPlan -and $null -eq $proposal.action) -or ($null -ne $proposal.action -and [string]$proposal.action -cnotin $allowed) -or
            ($proposal.action -ceq 'no-change' -and $text.Replace("`r`n", "`n") -cne ([string]$record.candidate.recommendation.ruleText).Replace("`r`n", "`n"))) {
            throw (New-RelationshipReviewException 'invalid-request')
        }
        $retirements = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
        foreach ($retireId in @($proposal.retireHostedRuleIds)) {
            if (-not $retirements.Add([string]$retireId) -or [string]$retireId -ceq $record.id -or
                -not $rules.ContainsKey([string]$retireId) -or $rules[[string]$retireId].status -cne 'active') { throw (New-RelationshipReviewException 'invalid-request') }
        }
        $record.proposal = [ordered]@{ action = $proposal.action; inPlan = $proposal.inPlan; text = $text; retireHostedRuleIds = @($proposal.retireHostedRuleIds) }
    }
    if ($seen.Count -ne $records.Count) { throw (New-RelationshipReviewException 'invalid-request') }
    if (-not $PlanOnly) {
        $subject = $records[[string]$Request.candidateKey]
        $comparisons = [Collections.Generic.List[object]]::new()
        $versions = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
        $comparisons.Add([ordered]@{ id = $subject.id; status = 'proposed'; text = $subject.proposal.text })
        foreach ($rule in $rules.Values) {
            if ($rule.id -ceq $subject.id -or $rule.status -cnotin @('active', 'protected')) { continue }
            if ($versions.Add("$($rule.id)`0$($rule.text)")) { $comparisons.Add($rule) }
        }
        foreach ($record in $records.Values) {
            if ($record.id -ceq $subject.id) { continue }
            if ($versions.Add("$($record.id)`0$($record.proposal.text)")) {
                $comparisons.Add([ordered]@{ id = $record.id; status = 'proposed'; text = $record.proposal.text })
            }
        }
        return [ordered]@{
            changedRuleIds = @($subject.id)
            removedRuleIds = @()
            effectiveCatalog = @($comparisons | Sort-Object -Property id, text -CaseSensitive)
        }
    }
    $effective = [Collections.Generic.Dictionary[string, object]]::new([StringComparer]::Ordinal)
    foreach ($rule in $rules.Values) { if ($rule.status -cin @('active', 'protected')) { $effective.Add($rule.id, $rule) } }
    $changed = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    $removed = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    $mutated = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    foreach ($entry in $records.GetEnumerator()) {
        $record = $entry.Value
        $proposal = $record.proposal
        $subject = $entry.Key -ceq [string]$Request.candidateKey
        $edited = $proposal.text.Replace("`r`n", "`n") -cne ([string]$record.candidate.recommendation.ruleText).Replace("`r`n", "`n")
        if (-not $proposal.inPlan -and ($PlanOnly -or -not $subject -or -not $edited)) { continue }
        $action = $proposal.action
        if (-not $proposal.inPlan) {
            $action = if (-not $rules.ContainsKey($record.id)) { 'add' } elseif ($rules[$record.id].status -ceq 'retired') { 'restore' } else { 'update' }
        }
        if ($action -cin @('add', 'update', 'restore', 'retire')) {
            if (-not $mutated.Add($record.id)) { throw (New-RelationshipReviewException 'invalid-request') }
            if ($action -ceq 'retire') {
                $null = $effective.Remove($record.id)
                $null = $removed.Add($record.id)
            } else {
                $effective[$record.id] = [ordered]@{ id = $record.id; status = 'active'; text = $proposal.text }
                $null = $changed.Add($record.id)
            }
        }
        if ($proposal.inPlan) {
            foreach ($retireId in $proposal.retireHostedRuleIds) {
                if (-not $rules.ContainsKey([string]$retireId) -or $rules[[string]$retireId].status -cne 'active' -or
                    [string]$retireId -ceq $record.id -or -not $mutated.Add([string]$retireId)) { throw (New-RelationshipReviewException 'invalid-request') }
                $null = $effective.Remove([string]$retireId)
                $null = $removed.Add([string]$retireId)
            }
        }
    }
    return [ordered]@{ changedRuleIds = @($changed | Sort-Object -CaseSensitive); removedRuleIds = @($removed | Sort-Object -CaseSensitive); effectiveCatalog = @($effective.Values | Sort-Object { $_.id } -CaseSensitive) }
}

function Get-RelationshipReviewResponseSchema {
    param([Parameter(Mandatory)][object]$InputData)
    $schema = [ordered]@{
        '$schema' = 'https://json-schema.org/draft/2020-12/schema'; type = 'object'; additionalProperties = $false; required = @('findings')
        properties = [ordered]@{ findings = [ordered]@{
            type = 'array'; uniqueItems = $true
            items = [ordered]@{ type = 'object'; additionalProperties = $false; required = @('ruleId', 'relatedRuleId', 'relationship', 'ruleQuote', 'relatedQuote', 'relatedText', 'rationale')
                properties = [ordered]@{
                    ruleId = @{ type = 'string'; enum = @($InputData.changedRuleIds) }
                    relatedRuleId = @{ type = 'string'; enum = @($InputData.effectiveCatalog | ForEach-Object id | Sort-Object -Unique -CaseSensitive) }
                    relationship = @{ enum = @('equivalent', 'partial-overlap', 'conflicts') }
                    ruleQuote = @{ type = 'string'; minLength = 1 }; relatedQuote = @{ type = 'string'; minLength = 1 }; relatedText = @{ type = 'string'; minLength = 1 }; rationale = @{ type = 'string'; minLength = 1 }
                }
            }
        } }
    }
    if (@($InputData.changedRuleIds).Count -eq 0) {
        $schema.properties.findings.Remove('items')
        $schema.properties.findings.maxItems = 0
    }
    return $schema
}

function Test-RelationshipReviewResult {
    param([Parameter(Mandatory)][string]$Json, [Parameter(Mandatory)][object]$InputData)
    $schema = Get-RelationshipReviewResponseSchema $InputData | ConvertTo-Json -Depth 30 -Compress
    try { if (-not (Test-Json -Json $Json -Schema $schema -ErrorAction Stop)) { throw 'invalid' } }
    catch { throw (New-RelationshipReviewException 'invalid-response') }
    $result = $Json | ConvertFrom-Json -Depth 30 -DateKind String
    $pairs = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    foreach ($finding in $result.findings) {
        $subject = @($InputData.effectiveCatalog | Where-Object { $_.id -ceq $finding.ruleId })
        $related = @($InputData.effectiveCatalog | Where-Object { $_.id -ceq $finding.relatedRuleId -and $_.text -ceq $finding.relatedText })
        $pair = "$($finding.ruleId)`0$($finding.relatedRuleId)`0$($finding.relatedText)"
        if ($finding.ruleId -ceq $finding.relatedRuleId -or -not $pairs.Add($pair) -or
            $subject.Count -ne 1 -or $related.Count -ne 1 -or
            -not $subject[0].text.Contains($finding.ruleQuote, [StringComparison]::Ordinal) -or
            -not $related[0].text.Contains($finding.relatedQuote, [StringComparison]::Ordinal)) { throw (New-RelationshipReviewException 'invalid-response') }
    }
    return $result
}

function Test-RelationshipReviewApproval {
    param([Parameter(Mandatory)][object]$Request, [Parameter(Mandatory)][string]$RepositoryRoot, [Parameter(Mandatory)][string]$DisplayPath, [Parameter(Mandatory)][string]$ReceiptDirectory)
    Assert-RelationshipReviewProperties $Request @('schemaVersion', 'authoritySha256', 'sourceFiles', 'proposals', 'receipts')
    $runtime = Get-RelationshipReviewRuntime -RepositoryRoot $RepositoryRoot -DisplayPath $DisplayPath
    if ($Request.schemaVersion -ne 1 -or $Request.authoritySha256 -cne $runtime.authoritySha256) { throw (New-RelationshipReviewException 'snapshot-changed') }
    $display = Get-Content -LiteralPath $DisplayPath -Raw | ConvertFrom-Json -Depth 100 -DateKind String
    $required = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    $candidateRecords = @{}
    foreach ($candidate in $display.candidates) { $candidateRecords["$($candidate.source.lane):$($candidate.source.id):$($candidate.assessment.id)"] = $candidate }
    foreach ($proposal in $Request.proposals) {
        if (-not $proposal.inPlan) { continue }
        if (-not $candidateRecords.ContainsKey([string]$proposal.candidateKey)) { throw (New-RelationshipReviewException 'invalid-request') }
        $candidate = $candidateRecords[[string]$proposal.candidateKey]
        $text = [Text.UTF8Encoding]::new($false, $true).GetString([Convert]::FromBase64String([string]$proposal.proposedTextBase64))
        if ($proposal.action -cin @('add', 'update', 'retire', 'restore') -or $text.Replace("`r`n", "`n") -cne ([string]$candidate.recommendation.ruleText).Replace("`r`n", "`n") -or @($proposal.retireHostedRuleIds).Count) { $null = $required.Add([string]$proposal.candidateKey) }
    }
    $seen = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    $receipts = [Collections.Generic.List[object]]::new()
    foreach ($entry in $Request.receipts) {
        Assert-RelationshipReviewProperties $entry @('candidateKey', 'requestId')
        $receiptId = [guid]::Empty
        if (-not [guid]::TryParseExact([string]$entry.requestId, 'D', [ref]$receiptId) -or -not $seen.Add([string]$entry.candidateKey)) { throw (New-RelationshipReviewException 'invalid-request') }
        $path = Join-Path $ReceiptDirectory ($receiptId.ToString() + '.json')
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw (New-RelationshipReviewException 'snapshot-changed') }
        $receipt = Get-Content -LiteralPath $path -Raw | ConvertFrom-Json -Depth 100 -DateKind String
        $proposal = @($Request.proposals | Where-Object { $_.candidateKey -ceq $entry.candidateKey })
        if ($proposal.Count -ne 1) { throw (New-RelationshipReviewException 'invalid-request') }
        $contextHash = Get-RelationshipReviewContextHash -SourceFiles $Request.sourceFiles -Proposal $proposal[0]
        if ($receipt.candidateKey -cne $entry.candidateKey -or $receipt.authoritySha256 -cne $runtime.authoritySha256 -or $receipt.contextSha256 -cne $contextHash) { throw (New-RelationshipReviewException 'snapshot-changed') }
        $receipts.Add($receipt)
        $null = $required.Remove([string]$entry.candidateKey)
    }
    if ($required.Count) { throw (New-RelationshipReviewException 'snapshot-changed') }
    if (@($Request.proposals).Count) {
        $probe = [pscustomobject][ordered]@{ schemaVersion = 1; requestId = [guid]::NewGuid().ToString(); authoritySha256 = $runtime.authoritySha256; snapshotKey = '0' * 64;
            candidateKey = [string]$Request.proposals[0].candidateKey; sourceFiles = $Request.sourceFiles; proposals = $Request.proposals }
        $projection = Get-RelationshipReviewInput -Display $display -Request $probe -PlanOnly
        foreach ($ruleId in $projection.changedRuleIds) {
            $rule = @($projection.effectiveCatalog | Where-Object { $_.id -ceq $ruleId })[0]
            foreach ($related in $projection.effectiveCatalog) {
                if ($related.id -ceq $ruleId) { continue }
                $covered = $false
                foreach ($receipt in $receipts) {
                    $subjectId = [string]$receipt.result.changedRuleIds[0]
                    $subject = @($receipt.comparisonRules | Where-Object { $_.id -ceq $subjectId })[0]
                    if ($subject.id -ceq $rule.id -and $subject.text -ceq $rule.text) {
                        $target = $related
                    } elseif ($subject.id -ceq $related.id -and $subject.text -ceq $related.text) {
                        $target = $rule
                    } else { continue }
                    if (@($receipt.comparisonRules | Where-Object { $_.id -ceq $target.id -and $_.text -ceq $target.text }).Count -eq 0) { continue }
                    if (@($receipt.result.findings | Where-Object { $_.relatedRuleId -ceq $target.id -and $_.relatedText -ceq $target.text }).Count) { throw (New-RelationshipReviewException 'snapshot-changed') }
                    $covered = $true
                }
                if (-not $covered) { throw (New-RelationshipReviewException 'snapshot-changed') }
            }
        }
    }
    return [ordered]@{ valid = $true }
}

function Get-RelationshipReviewContextHash {
    param([Parameter(Mandatory)][object]$SourceFiles, [Parameter(Mandatory)][object]$Proposal)
    return Get-JsonSnapshotSha256 -Depth 100 -Value ([ordered]@{
        sourceFiles = $SourceFiles
        candidateKey = $Proposal.candidateKey
        sourceHash = $Proposal.sourceHash
        proposedTextBase64 = $Proposal.proposedTextBase64
    })
}

Export-ModuleMember -Function New-RelationshipReviewException, Wait-RelationshipReviewTask, Get-RelationshipReviewFailure, Get-RelationshipReviewRuntime, Start-RelationshipReviewRequest, Get-RelationshipReviewInput, Get-RelationshipReviewResponseSchema, Test-RelationshipReviewResult, Test-RelationshipReviewApproval, Get-RelationshipReviewContextHash
