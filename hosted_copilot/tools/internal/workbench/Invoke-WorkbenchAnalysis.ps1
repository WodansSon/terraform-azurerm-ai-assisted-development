<#
.SYNOPSIS
Runs native source assessment or continues its downstream stages against an explicitly selected branch database.
.DESCRIPTION
Records evaluation identity in the database before each restricted inference call and commits validated results afterward. Does not import legacy assessments, collect sources, approve changes, or replace the current analysis head before reconciliation/adjudication.
.PARAMETER ResumeRunId
Explicit existing run to continue after compatible pinned inputs and evaluator identity are verified. Completed results are retained. Cannot be combined with Force.
.PARAMETER ContinueRunId
Explicit source-assessed run whose reconciliation and adjudication should continue. Does not rerun source assessment. Cannot be combined with ResumeRunId or Force.
.PARAMETER AdjudicationOnly
Requires ContinueRunId and fully committed reconciliation. Verifies and recovers earlier phases without dispatching them; permits a repaired adjudicator when earlier attempts have no completed or active results.
.PARAMETER StagePayloadBudgetBytes
Maximum downstream quoted-input size. Requires ContinueRunId when explicitly configured.
.PARAMETER EvaluatorPayloadBudgetBytes
Maximum downstream request size including prompt and output contract. Requires ContinueRunId when explicitly configured.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$DatabasePath,
    [Parameter(Mandatory)][string]$DatabaseGuid,
    [string]$EvaluatorCommand = 'copilot',
    [ValidateRange(1, 16)][int]$MaxParallelBatches = 3,
    [ValidateRange(1, 2147483647)][int]$StagePayloadBudgetBytes = 262144,
    [ValidateRange(1, 2147483647)][int]$EvaluatorPayloadBudgetBytes = 393216,
    [ValidateRange(1, 2147483647)][int]$ResumeRunId,
    [ValidateRange(1, 2147483647)][int]$ContinueRunId,
    [switch]$AdjudicationOnly,
    [switch]$Force
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot '../../modules/shared/HostedCli.psm1') -Force
Import-Module (Join-Path $PSScriptRoot '../../modules/shared/HostedToolkit.Helpers.psm1') -Force
Import-Module (Join-Path $PSScriptRoot '../../../../tools/ValidationOutput.psm1') -Force
Import-Module (Join-Path $PSScriptRoot '../../modules/workbench/Workbench.Activity.psm1') -Force
Import-Module (Join-Path $PSScriptRoot '../../modules/workbench/Workbench.Audit.psm1') -Force
$resolvedDatabasePath = [IO.Path]::GetFullPath($DatabasePath)
if ($StagePayloadBudgetBytes -gt $EvaluatorPayloadBudgetBytes) { throw 'Stage payload budget cannot exceed the complete evaluator budget' }
if ($ContinueRunId -le 0 -and ($PSBoundParameters.ContainsKey('StagePayloadBudgetBytes') -or $PSBoundParameters.ContainsKey('EvaluatorPayloadBudgetBytes'))) {
    throw 'Explicit downstream byte budgets require ContinueRunId'
}
$analysisClock = [Diagnostics.Stopwatch]::StartNew()
$commandOutput = [pscustomobject]@{ Completed = $false }
if ($ResumeRunId -gt 0 -and $Force) { throw 'ResumeRunId cannot be combined with Force; fresh evaluation requires a new run' }
if ($ContinueRunId -gt 0 -and ($ResumeRunId -gt 0 -or $Force)) { throw 'ContinueRunId cannot be combined with ResumeRunId or Force' }
if ($AdjudicationOnly -and $ContinueRunId -le 0) { throw 'AdjudicationOnly requires ContinueRunId' }
$auditAction = if ($ContinueRunId -gt 0) { if ($AdjudicationOnly) { 'adjudicate' } else { 'reconcile' } } else { 'assess' }
$auditFacts = @{}
if ($ResumeRunId -gt 0) { $auditFacts.runId = $ResumeRunId }
elseif ($ContinueRunId -gt 0) { $auditFacts.runId = $ContinueRunId }
$analysisAudit = New-WorkbenchAudit -DatabasePath $resolvedDatabasePath -DatabaseGuid $DatabaseGuid -ActionCode $auditAction -Facts $auditFacts
try {
$runtimeRequest = [ordered]@{ databaseGuid = $DatabaseGuid }
$runtimeJson = ($runtimeRequest | ConvertTo-Json -Compress) | & node (Join-Path $PSScriptRoot '../../modules/workbench/WorkbenchDatabase.mjs') llm-runtime $resolvedDatabasePath
if ($LASTEXITCODE -ne 0) { throw 'Cannot resolve LLM assignments from the selected master-profile database' }
$runtime = $runtimeJson | ConvertFrom-Json -Depth 100
$assignedModels = [ordered]@{}
foreach ($assignment in $runtime.assignments) {
    if ($assignment.providerCode -cne 'github-copilot' -or $assignment.adapterCode -cne 'copilot-cli') { throw 'Assigned LLM uses an unsupported native transport' }
    $assignedModels[$assignment.taskCode] = @{ model = $assignment.model; reasoningEffort = $assignment.reasoningEffort }
}
Write-ValidationSectionHeader -Title 'Database Workspace' | Write-Host
Write-ValidationSummary -Fields ([ordered]@{
    Database = $resolvedDatabasePath
    'Database GUID' = $DatabaseGuid
    Storage = if ($ContinueRunId -gt 0) { 'SQLite; retained source assessments; native downstream continuation; no legacy JSON result import' } else { 'SQLite; fresh source assessments; no legacy JSON result import' }
    Inspection = 'SQLite 3.37.0 or newer is required for STRICT tables'
}) | Write-Host
Write-ValidationSectionHeader -Title 'LLM Availability' | Write-Host
$launch = Resolve-HostedCliLaunch -EvaluatorCommand $EvaluatorCommand
$availability = Get-HostedCliAvailability -Launch $launch -Profiles $assignedModels
$analysisChecks = [Collections.Generic.List[object]]::new()
foreach ($availableProfile in $availability.profiles) {
    Format-ValidationStatusLine -Status 'passed' -Name $availableProfile.name -Detail "$($availableProfile.model)/$($availableProfile.reasoningEffort); CLI $($availability.version)" | Write-Host
    $analysisChecks.Add([pscustomobject]@{ status = 'passed'; name = $availableProfile.name })
}
function Complete-NativeCommandTextOutput {
    if ($commandOutput.Completed) { return }
    $commandOutput.Completed = $true
    Complete-ValidationTextOutput | Write-Host
}
function Write-NativeFailureSummary {
    param([object[]]$Checks, [string[]]$Failures)

    Write-ValidationSectionHeader -Title 'Native Analysis Summary' | Write-Host
    Write-ValidationSummary -Fields ([ordered]@{ Status = 'FAILED'; Checks = $Checks.Count;
        Passed = @($Checks | Where-Object status -CEQ 'passed').Count; Failed = @($Checks | Where-Object status -CEQ 'failed').Count }) | Write-Host
    Write-ValidationSectionHeader -Title 'Native Analysis Checks' | Write-Host
    Write-ValidationTwoColumnTable -Rows $Checks -FirstHeader 'Status' -FirstProperty 'status' -SecondHeader 'Check' -SecondProperty 'name' -UppercaseFirst | Write-Host
    Write-ValidationSectionHeader -Title 'Failures' | Write-Host
    foreach ($failure in $Failures) { Write-Host ('  - ' + $failure) }
    Complete-NativeCommandTextOutput
}
function Format-NativeEvaluationFailure {
    param([object]$Event)

    if ($Event.failureCode -isnot [string] -or $Event.failureCode -cnotmatch '^[a-z][a-z0-9-]{0,63}$') {
        throw 'Database evaluation emitted invalid failure metadata; raw content omitted'
    }
    if ($null -eq $Event.PSObject.Properties['failureStage']) {
        if ($Event.failureCode -ceq 'evaluator-result-contract-invalid') {
            return 'Evaluator response failed its result contract; raw response content omitted'
        }
        return 'Evaluation failed; the original reason is unavailable in safe diagnostics'
    }
    if ($Event.failureStage -cnotin @('request', 'evaluate', 'commit') -or
        $Event.failureReason -isnot [string] -or $Event.failureReason.Length -eq 0 -or $Event.failureReason.Length -gt 512 -or
        $Event.failureReason -cmatch '[^\x20-\x7e]' -or
        ($null -ne $Event.failurePath -and ($Event.failurePath -isnot [string] -or $Event.failurePath.Length -gt 256 -or
            $Event.failurePath -cnotmatch '^/(groups|components|dispositions|assessments|relationshipDecisions|issues)(/([a-z][A-Za-z]*|0|[1-9][0-9]*))*$'))) {
        throw 'Database evaluation emitted invalid safe failure details; raw content omitted'
    }
    $detail = $Event.failureStage + ': ' + $Event.failureReason
    if ($null -ne $Event.failurePath) { $detail += ' at ' + $Event.failurePath }
    return $detail
}
function Write-NativeExecutionRefusal {
    param([object]$Event, [object[]]$CompletedChecks)

    if ((@($Event.PSObject.Properties.Name | Sort-Object -CaseSensitive) -join ',') -cne 'code,kind' -or
        $Event.kind -cne 'execution-refused' -or $Event.code -cne 'workbench-execution-already-running') {
        throw 'Database execution emitted an unsupported refusal event; raw content omitted'
    }
    $checks = @($CompletedChecks) + @([pscustomobject]@{ status = 'failed'; name = 'execution-guard' })
    Write-ValidationSectionHeader -Title 'Native Analysis' | Write-Host
    Format-ValidationStatusLine -Status failed -Name 'execution-guard' -Detail 'Already running or starting for this database; wait for the active command to finish or cancel it' -AlignmentWidth 42 | Write-Host
    Write-NativeFailureSummary -Checks $checks -Failures @('Another analysis command is already running or starting for this database')
}
function Invoke-NativeDownstreamContinuation {
    param([Collections.IDictionary]$Request, [string]$BridgePath, [string]$SelectedDatabasePath, [int]$WorkerLimit, [object[]]$CompletedChecks)

    $phases = @('routing', 'consolidation', 'synthesis', 'adjudication')
    $phaseIndex = 0
    $plan = $null
    $active = @{}
    $completed = [Collections.Generic.HashSet[int]]::new()
    $failedBatches = [Collections.Generic.HashSet[int]]::new()
    $checkRecords = [Collections.Generic.List[object]]::new()
    foreach ($check in $CompletedChecks) { $checkRecords.Add($check) }
    $failureMessages = [Collections.Generic.List[string]]::new()
    $completion = $null
    $result = $null
    $refusal = $null
    $failureEvent = $null
    $preparationDetails = @{
        routing = 'Validating committed assessments and measuring routing batches'
        consolidation = 'Validating routing components and measuring the global comparison'
        synthesis = 'Rehydrating source evidence and planning indivisible components'
        adjudication = 'Planning all group/baseline and cross-group comparisons'
    }
    $preparationClock = [Diagnostics.Stopwatch]::StartNew()
    Write-ValidationSectionHeader -Title ('Native ' + $phases[$phaseIndex] + ' Preparation') | Write-Host
    Format-ValidationStatusLine -Status running -Name ($phases[$phaseIndex] + '-preparation') -Detail $preparationDetails[$phases[$phaseIndex]] -AlignmentWidth 42 | Write-Host
    $activity = Start-WorkbenchActivity -Name 'Preparing Routing' -Clock $analysisClock
    Invoke-WorkbenchActivityProcess -Arguments @($BridgePath, 'continue-analysis', $SelectedDatabasePath) -InputObject ($Request | ConvertTo-Json -Compress) -Activity $activity | ForEach-Object {
        try { $event = $_ | ConvertFrom-Json -Depth 100 -DateKind String }
        catch { throw 'Database continuation emitted invalid structured progress; raw content omitted' }
        if ($null -ne $event.PSObject.Properties['kind'] -and $event.kind -ceq 'audit-warning') {
            Write-WorkbenchAuditWarning -Event $event
            return
        }
        if ($null -ne $event.PSObject.Properties['kind'] -and $event.kind -ceq 'audit-context') {
            Update-WorkbenchAuditContext -Audit $analysisAudit -Context $event.context
            return
        }
        if ($null -ne $refusal -or $null -ne $failureEvent) { throw 'Database continuation emitted output after a terminal failure' }
        if ($null -ne $event.PSObject.Properties['kind'] -and $event.kind -ceq 'execution-refused') {
            if ($phaseIndex -ne 0 -or $null -ne $plan -or $active.Count -ne 0) { throw 'Database continuation refused an already active execution' }
            Stop-WorkbenchActivity -Activity $activity
            Write-NativeExecutionRefusal -Event $event -CompletedChecks $CompletedChecks
            $refusal = $event
            return
        }
        if ($null -ne $event.PSObject.Properties['kind'] -and $event.kind -ceq 'execution-failed') {
            if ((@($event.PSObject.Properties.Name | Sort-Object -CaseSensitive) -join ',') -cne 'code,kind,phase' -or
                $event.code -cne 'workbench-native-stage-failed' -or $phaseIndex -ge $phases.Count -or $event.phase -cne $phases[$phaseIndex] -or
                $null -eq $plan -or $failedBatches.Count -eq 0 -or $active.Count -ne 0) {
                throw 'Database continuation failure does not match settled failed work; raw content omitted'
            }
            Stop-WorkbenchActivity -Activity $activity
            Write-NativeFailureSummary -Checks $checkRecords.ToArray() -Failures $failureMessages.ToArray()
            $failureEvent = $event
            return
        }
        if ($null -ne $event.PSObject.Properties['kind'] -and $event.kind -ceq 'downstream-progress') {
            if ($event.runId -ne $Request.runId -or $null -ne $completion) { throw 'Database continuation progress does not match its selected run' }
            if ($event.state -ceq 'complete') {
                if ($phaseIndex -ne $phases.Count -or $active.Count -ne 0 -or $event.outcome -cne 'complete') { throw 'Database continuation completed without all required phases' }
                Stop-WorkbenchActivity -Activity $activity
                $completion = $event
                return
            }
            if ($phaseIndex -ge $phases.Count -or $event.phase -cne $phases[$phaseIndex]) { throw 'Database continuation emitted an unexpected phase' }
            if ($event.state -ceq 'plan') {
                if ($null -ne $plan -or $event.batchCount -lt 0 -or $event.recoveredBatchCount -lt 0 -or
                    $event.workerCount -ne [Math]::Min($WorkerLimit, $event.batchCount)) { throw 'Database continuation emitted an invalid workload plan' }
                $plan = $event
                $active.Clear()
                $completed.Clear()
                $failedBatches.Clear()
                $preparationClock.Stop()
                Update-WorkbenchActivity -Activity $activity -Name ('Processing ' + [Globalization.CultureInfo]::InvariantCulture.TextInfo.ToTitleCase($event.phase))
                Format-ValidationStatusLine -Status passed -Name ($event.phase + '-preparation') -Detail "Bounded workload planned : [Elapsed: $(Format-ElapsedDuration -Milliseconds $preparationClock.ElapsedMilliseconds)]" -AlignmentWidth 42 | Write-Host
                $checkRecords.Add([pscustomobject]@{ status = 'passed'; name = $event.phase + '-preparation' })
                Write-ValidationSectionHeader -Title ('Processing Native ' + $event.phase) | Write-Host
                $fields = [ordered]@{ Batches = "$($event.batchCount) pending | $($event.recoveredBatchCount) recovered" }
                if ($event.phase -ceq 'adjudication' -and $null -ne $event.PSObject.Properties['comparisonCount']) {
                    $fields.Relationships = "$($event.comparisonCount) recorded | $($event.componentCount) complete components"
                }
                if ($event.batchCount -eq 0) { $fields.Execution = 'No evaluation required' }
                else {
                    $fields.Workers = $event.workerCount
                    $fields.Payload = Format-ByteSize -Bytes $event.pendingPayloadBytes
                    $fields.Estimated = Format-ElapsedDuration -Milliseconds $event.estimatedMilliseconds
                }
                Write-ValidationSummary -Fields $fields | Write-Host
                Write-Host ''
                return
            }
            if ($null -eq $plan) { throw 'Database continuation progress requires an active plan' }
            if ($event.state -ceq 'phase-complete') {
                if ($active.Count -ne 0 -or $completed.Count -ne $plan.batchCount -or $event.evaluatedBatchCount -ne $plan.batchCount -or
                    $event.recoveredBatchCount -ne $plan.recoveredBatchCount -or $event.batchCount -ne ($plan.batchCount + $plan.recoveredBatchCount)) {
                    throw 'Database continuation phase completion does not cover its planned work'
                }
                Format-ValidationStatusLine -Status passed -Name $event.phase -Detail "$($event.evaluatedBatchCount) evaluated | $($event.recoveredBatchCount) recovered : [Elapsed: $(Format-ElapsedDuration -Milliseconds $event.totalElapsedMilliseconds)]" -AlignmentWidth 42 | Write-Host
                $phaseIndex += 1
                $plan = $null
                if ($phaseIndex -lt $phases.Count) {
                    $preparationClock.Restart()
                    Update-WorkbenchActivity -Activity $activity -Name ('Preparing ' + [Globalization.CultureInfo]::InvariantCulture.TextInfo.ToTitleCase($phases[$phaseIndex]))
                    Write-ValidationSectionHeader -Title ('Native ' + $phases[$phaseIndex] + ' Preparation') | Write-Host
                    Format-ValidationStatusLine -Status running -Name ($phases[$phaseIndex] + '-preparation') -Detail $preparationDetails[$phases[$phaseIndex]] -AlignmentWidth 42 | Write-Host
                } else {
                    Update-WorkbenchActivity -Activity $activity -Name 'Completing Analysis'
                }
                return
            }
            $batch = [int]$event.batchNumber
            if ($batch -lt 1 -or $batch -gt $plan.batchCount -or $event.batchCount -ne $plan.batchCount -or $completed.Contains($batch) -or $failedBatches.Contains($batch)) {
                throw 'Database continuation emitted an invalid batch identity'
            }
            $name = "$($event.phase) $batch/$($event.batchCount)"
            if ($event.state -ceq 'running') {
                if ($failedBatches.Count -gt 0 -or $active.ContainsKey($batch) -or $active.Count -ge $plan.workerCount) { throw 'Database continuation dispatched after failure or exceeded its active worker plan' }
                $active[$batch] = $event.evaluationId
                Format-ValidationStatusLine -Status running -Name $name -Detail 'Evaluating database evidence' -AlignmentWidth 42 | Write-Host
            } elseif ($event.state -ceq 'passed') {
                if (-not $active.ContainsKey($batch) -or $active[$batch] -ne $event.evaluationId -or $event.completedBatchCount -ne ($completed.Count + 1)) {
                    throw 'Database continuation completed an inactive or inconsistent batch'
                }
                $active.Remove($batch)
                $null = $completed.Add($batch)
                $checkRecords.Add([pscustomobject]@{ status = 'passed'; name = $name })
                $detail = "Total Elapsed $(Format-ElapsedDuration -Milliseconds $event.totalElapsedMilliseconds) : [Batch: $(Format-ElapsedDuration -Milliseconds $event.batchElapsedMilliseconds)] : [Remaining: $(Format-ElapsedDuration -Milliseconds $event.remainingMilliseconds)]"
                Format-ValidationStatusLine -Status passed -Name $name -Detail $detail -AlignmentWidth 42 | Write-Host
            } elseif ($event.state -ceq 'failed') {
                $active.Remove($batch)
                $null = $failedBatches.Add($batch)
                $checkRecords.Add([pscustomobject]@{ status = 'failed'; name = $name })
                $failureDetail = Format-NativeEvaluationFailure -Event $event
                $failureMessages.Add($name + ' ' + $failureDetail + '; committed results retained; unresolved work requires recovery')
                $detail = "Total Elapsed $(Format-ElapsedDuration -Milliseconds $event.totalElapsedMilliseconds) : [Batch: $(Format-ElapsedDuration -Milliseconds $event.batchElapsedMilliseconds)] : " + $failureDetail
                Format-ValidationStatusLine -Status failed -Name $name -Detail $detail -AlignmentWidth 42 | Write-Host
            } else { throw 'Database continuation emitted an unsupported lifecycle event' }
        } elseif ($event.outcome -ceq 'complete') {
            if ($null -eq $completion -or $event.runId -ne $completion.runId -or $event.groupCount -ne $completion.groupCount -or
                $event.comparisonCount -ne $completion.comparisonCount) { throw 'Database continuation summary does not match committed completion' }
            $result = $event
        } else { throw 'Database continuation emitted an unsupported result; raw content omitted' }
    }
    $LASTEXITCODE = $activity.ExitCode
    if ($null -ne $refusal) {
        if ($LASTEXITCODE -ne 1) { throw 'Database execution refusal requires a nonzero failure exit code' }
        return $refusal
    }
    if ($null -ne $failureEvent) {
        if ($LASTEXITCODE -ne 1) { throw 'Database settled failure requires a nonzero failure exit code' }
        return $failureEvent
    }
    if ($LASTEXITCODE -ne 0 -or $null -eq $result) { throw 'Database continuation did not complete; committed results retained; current analysis head was not advanced' }
    return $result
}

if ($ContinueRunId -gt 0) {
    $downstreamRequest = [ordered]@{ databaseGuid = $DatabaseGuid; runId = $ContinueRunId; llmAssignmentIds = @($runtime.assignments.assignmentId);
        evaluatorCommand = $launch.commandPath; cliVersion = $availability.version; maxParallelBatches = $MaxParallelBatches;
        budgets = [ordered]@{ stagePayloadBudgetBytes = $StagePayloadBudgetBytes; evaluatorPayloadBudgetBytes = $EvaluatorPayloadBudgetBytes } }
    $downstreamRequest.adjudicationOnly = [bool]$AdjudicationOnly
    $downstreamRequest.auditContext = $analysisAudit.Context
    $downstreamResult = Invoke-NativeDownstreamContinuation -Request $downstreamRequest -BridgePath (Join-Path $PSScriptRoot '../../modules/workbench/WorkbenchDatabase.mjs') -SelectedDatabasePath $resolvedDatabasePath -WorkerLimit $MaxParallelBatches -CompletedChecks $analysisChecks.ToArray()
    if ($null -ne $downstreamResult.PSObject.Properties['kind'] -and $downstreamResult.kind -in @('execution-refused', 'execution-failed')) { exit 1 }
    Write-ValidationSectionHeader -Title 'Native Analysis Summary' | Write-Host
    Write-ValidationSummary -Fields ([ordered]@{ Status = 'ANALYSIS COMPLETE; UI integration still pending'; Run = $downstreamResult.runId;
        Sources = $downstreamResult.sourceCount; Assessments = $downstreamResult.assessmentCount; Groups = $downstreamResult.groupCount;
        Comparisons = $downstreamResult.comparisonCount; 'Ready for UI' = $downstreamResult.readyForUi }) | Write-Host
    Complete-NativeCommandTextOutput
    return
}

$request = [ordered]@{ databaseGuid = $DatabaseGuid; llmAssignmentIds = @($runtime.assignments.assignmentId);
    evaluatorCommand = $launch.commandPath; cliVersion = $availability.version; force = [bool]$Force; maxParallelBatches = $MaxParallelBatches;
    auditContext = $analysisAudit.Context }
$operation = 'assess'
if ($ResumeRunId -gt 0) {
    $request.Remove('force')
    $request.runId = $ResumeRunId
    $operation = 'resume-assess'
}
Write-ValidationSectionHeader -Title 'Source Assessment' | Write-Host
$activity = Start-WorkbenchActivity -Name 'Preparing Source Assessment' -Clock $analysisClock
$activeBatches = @{}
$completedBatches = [Collections.Generic.HashSet[int]]::new()
$assessmentFailures = [Collections.Generic.List[string]]::new()
$assessmentChecks = [Collections.Generic.List[object]]::new()
foreach ($check in $analysisChecks) { $assessmentChecks.Add($check) }
$assessmentPlan = $null
$completionEvent = $null
$analysisResult = $null
$executionRefusal = $null
Invoke-WorkbenchActivityProcess -Arguments @((Join-Path $PSScriptRoot '../../modules/workbench/WorkbenchDatabase.mjs'), $operation, $resolvedDatabasePath) -InputObject ($request | ConvertTo-Json -Compress) -Activity $activity | ForEach-Object {
    try { $event = $_ | ConvertFrom-Json -Depth 100 -DateKind String }
    catch { throw 'Database assessment emitted invalid structured progress; raw content omitted' }
    if ($null -ne $event.PSObject.Properties['kind'] -and $event.kind -ceq 'audit-warning') {
        Write-WorkbenchAuditWarning -Event $event
        return
    }
    if ($null -ne $event.PSObject.Properties['kind'] -and $event.kind -ceq 'audit-context') {
        Update-WorkbenchAuditContext -Audit $analysisAudit -Context $event.context
        return
    }
    if ($null -ne $executionRefusal) { throw 'Database assessment emitted output after an execution refusal' }
    if ($null -ne $event.PSObject.Properties['kind'] -and $event.kind -ceq 'execution-refused') {
        if ($null -ne $assessmentPlan -or $activeBatches.Count -ne 0) { throw 'Database assessment refused an already active execution' }
        Stop-WorkbenchActivity -Activity $activity
        Write-NativeExecutionRefusal -Event $event -CompletedChecks $analysisChecks.ToArray()
        $executionRefusal = $event
        return
    }
    if ($null -ne $event.PSObject.Properties['kind'] -and $event.kind -ceq 'assessment-progress') {
        if ($event.state -ceq 'plan') {
            if ($null -ne $assessmentPlan -or $event.totalSourceCount -ne ($event.cachedSourceCount + $event.recoveredSourceCount + $event.pendingSourceCount) -or
                $event.workerCount -ne [Math]::Min($MaxParallelBatches, $event.batchCount)) { throw 'Database assessment emitted an invalid workload plan' }
            $assessmentPlan = $event
            Update-WorkbenchActivity -Activity $activity -Name 'Processing Source Assessment'
            $fields = [ordered]@{ Sources = "$($event.totalSourceCount) total | $($event.cachedSourceCount) cached | $($event.recoveredSourceCount) recovered" }
            if ($event.pendingSourceCount -eq 0) {
                $fields.Execution = 'No evaluation required'
            } else {
                $fields.Sources += " | $($event.pendingSourceCount) pending"
                $fields.Batches = "$($event.batchCount) pending"
                $fields.Workers = $event.workerCount
                $fields.Payload = Format-ByteSize -Bytes $event.pendingPayloadBytes
                $fields.Estimated = Format-ElapsedDuration -Milliseconds $event.estimatedMilliseconds
            }
            Write-ValidationSummary -Fields $fields | Write-Host
            if ($event.pendingSourceCount -gt 0) {
                Write-Host ''
                Format-ValidationStatusLine -Status running -Name 'source-assessment' -Detail "Evaluating $($event.pendingSourceCount) pending sources across $($event.batchCount) batches" -AlignmentWidth 42 | Write-Host
            }
            return
        }
        if ($null -eq $assessmentPlan -or $event.runId -ne $assessmentPlan.runId -or $null -ne $completionEvent) { throw 'Database assessment progress does not match an active workload plan' }
        if ($event.state -ceq 'complete') {
            if ($activeBatches.Count -ne 0 -or $completedBatches.Count -ne $assessmentPlan.batchCount -or $event.completedSources -ne $assessmentPlan.totalSourceCount) {
                throw 'Database assessment completion does not cover its planned batches'
            }
            Stop-WorkbenchActivity -Activity $activity
            $completionEvent = $event
            $detail = "$($event.sourceCount) sources | $($event.cachedSourceCount) cached | $($event.recoveredSourceCount) recovered | $($event.evaluatedSourceCount) evaluated : [Elapsed: $(Format-ElapsedDuration -Milliseconds $event.totalElapsedMilliseconds)]"
            Format-ValidationStatusLine -Status passed -Name 'source-assessment' -Detail $detail -AlignmentWidth 42 | Write-Host
            return
        }
        $batchNumber = [int]$event.batchNumber
        if ($batchNumber -lt 1 -or $batchNumber -gt $assessmentPlan.batchCount -or $event.batchCount -ne $assessmentPlan.batchCount -or $completedBatches.Contains($batchNumber)) {
            throw 'Database assessment emitted an invalid batch identity'
        }
        $name = "source-assessment $batchNumber/$($event.batchCount)"
        if ($event.state -ceq 'running') {
            if ($activeBatches.ContainsKey($batchNumber) -or $activeBatches.Count -ge $assessmentPlan.workerCount) { throw 'Database assessment exceeded its planned active workers' }
            $activeBatches[$batchNumber] = $event.evaluationId
            $displayBatchId = '{0}-{1:D3}' -f $event.sourceDefinitionId, $batchNumber
            Format-ValidationStatusLine -Status running -Name $name -Detail "$displayBatchId ($($event.sourceCount) sources)" -AlignmentWidth 42 | Write-Host
        } elseif ($event.state -ceq 'passed') {
            if (-not $activeBatches.ContainsKey($batchNumber) -or $activeBatches[$batchNumber] -ne $event.evaluationId) { throw 'Database assessment completed an inactive batch' }
            $activeBatches.Remove($batchNumber)
            $null = $completedBatches.Add($batchNumber)
            $assessmentChecks.Add([pscustomobject]@{ status = 'passed'; name = $name })
            $detail = "Total Elapsed $(Format-ElapsedDuration -Milliseconds $event.totalElapsedMilliseconds) : [Batch: $(Format-ElapsedDuration -Milliseconds $event.batchElapsedMilliseconds)] : [Remaining: $(Format-ElapsedDuration -Milliseconds $event.remainingMilliseconds)]"
            Format-ValidationStatusLine -Status passed -Name $name -Detail $detail -AlignmentWidth 42 | Write-Host
        } elseif ($event.state -ceq 'failed') {
            $activeBatches.Remove($batchNumber)
            $failureDetail = Format-NativeEvaluationFailure -Event $event
            $assessmentFailures.Add($name + ' ' + $failureDetail)
            $assessmentChecks.Add([pscustomobject]@{ status = 'failed'; name = $name })
            $detail = "Total Elapsed $(Format-ElapsedDuration -Milliseconds $event.totalElapsedMilliseconds) : [Batch: $(Format-ElapsedDuration -Milliseconds $event.batchElapsedMilliseconds)] : " + $failureDetail
            Format-ValidationStatusLine -Status failed -Name $name -Detail $detail -AlignmentWidth 42 | Write-Host
        } else { throw 'Database assessment emitted an invalid lifecycle transition; raw content omitted' }
    } elseif ($null -ne $event.PSObject.Properties['assessmentComplete'] -and $event.assessmentComplete -eq $true) {
        if ($null -eq $completionEvent -or $event.runId -ne $completionEvent.runId -or $event.completedSources -ne $completionEvent.completedSources -or
            $event.completedAssessments -ne $completionEvent.completedAssessments) { throw 'Database assessment summary does not match committed completion' }
        $analysisResult = $event
    } else { throw 'Database assessment emitted an unsupported event; raw content omitted' }
}
$LASTEXITCODE = $activity.ExitCode
if ($null -ne $executionRefusal) {
    if ($LASTEXITCODE -ne 1) { throw 'Database execution refusal requires a nonzero failure exit code' }
    exit 1
}
if ($LASTEXITCODE -ne 0 -or $null -eq $analysisResult) {
    Format-ValidationStatusLine -Status failed -Name 'source-assessment' -Detail 'Incomplete; committed batches retained; unresolved sources require explicit recovery' -AlignmentWidth 42 | Write-Host
    if ($assessmentFailures.Count -gt 0) {
        Write-NativeFailureSummary -Checks $assessmentChecks.ToArray() -Failures $assessmentFailures.ToArray()
    }
    throw 'Database source assessment did not complete; committed results were retained and the current analysis head was not changed'
}
Write-ValidationSectionHeader -Title 'Source Assessment Summary' | Write-Host
Write-ValidationSummary -Fields ([ordered]@{
    Status = 'ASSESSMENT COMPLETE; reconciliation/adjudication still required'
    Run = $analysisResult.runId
    Sources = $analysisResult.completedSources
    Assessments = $analysisResult.completedAssessments
    'Ready for UI' = $analysisResult.readyForUi
}) | Write-Host
Complete-NativeCommandTextOutput
} finally {
    if ($null -ne $analysisAudit.Context.activeActionCode) { Invoke-WorkbenchAuditTransition -Audit $analysisAudit -Transition finish -Outcome failed }
}
