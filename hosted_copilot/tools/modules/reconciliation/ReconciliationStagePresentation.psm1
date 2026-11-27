Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Import-Module (Join-Path $PSScriptRoot '../shared/HostedToolkit.Helpers.psm1')

$reconciliationStagePresentation = @{
    routing = [pscustomobject]@{ displayName = 'Initial Assessment Grouping'; bootstrapBytesPerSecondPerWorker = 500 }
    consolidation = [pscustomobject]@{ displayName = 'Group Consolidation'; bootstrapBytesPerSecondPerWorker = 325 }
    synthesis = [pscustomobject]@{ displayName = 'Recommendation Synthesis'; bootstrapBytesPerSecondPerWorker = 450 }
    adjudication = [pscustomobject]@{ displayName = 'Rule Issue Adjudication'; bootstrapBytesPerSecondPerWorker = 500 }
}
$reconciliationCurrentStageProgress = $null

function Get-ReconciliationStagePresentation {
    param([Parameter(Mandatory = $true)][ValidateSet('routing', 'consolidation', 'synthesis', 'adjudication')][string]$Stage)

    return $reconciliationStagePresentation[$Stage]
}

function Write-ReconciliationStagePlan {
    param(
        [Parameter(Mandatory = $true)][string]$DisplayName,
        [Parameter(Mandatory = $true)][string]$InputLabel,
        [Parameter(Mandatory = $true)][int]$InputCount,
        [Parameter(Mandatory = $true)][int]$BatchCount,
        [Parameter(Mandatory = $true)][int]$CachedCount,
        [Parameter(Mandatory = $true)][int]$PendingCount,
        [Parameter(Mandatory = $true)][int]$WorkerCount,
        [Parameter(Mandatory = $true)][long]$PendingPayloadBytes,
        [Parameter(Mandatory = $true)][long]$EstimatedMilliseconds
    )

    $script:reconciliationCurrentStageProgress = [pscustomobject]@{ completedCount = $CachedCount; totalCount = $BatchCount }
    if ($DisplayName -in @('Group Consolidation', 'Recommendation Synthesis')) {
        Write-ValidationSectionHeader -Title $DisplayName | Write-Host
    }
    Write-Host ("  {0,-17}: {1}" -f 'Stage', $DisplayName)
    Write-Host ("  {0,-17}: {1} total" -f $InputLabel, $InputCount)
    if ($PendingCount -eq 0) {
        Write-Host ("  {0,-17}: {1} total | {2} cached" -f 'Batches', $BatchCount, $CachedCount)
        Write-Host ("  {0,-17}: Fully cached" -f 'Execution')
        return
    }
    Write-Host ("  {0,-17}: {1} total | {2} cached | {3} pending" -f 'Batches', $BatchCount, $CachedCount, $PendingCount)
    Write-Host ("  {0,-17}: {1}" -f 'Workers', $WorkerCount)
    Write-Host ("  {0,-17}: {1}" -f 'Payload', (Format-ByteSize -Bytes $PendingPayloadBytes))
    Write-Host ("  {0,-17}: {1}" -f 'Estimated', (Format-ElapsedDuration -Milliseconds $EstimatedMilliseconds))
    Write-Host ''
}

function Write-ReconciliationBatchStarted {
    param(
        [Parameter(Mandatory = $true)][string]$Stage,
        [Parameter(Mandatory = $true)][object]$WorkerEvent
    )

    $shortShardKey = [string]$WorkerEvent.ShardKey
    $shortShardKey = $shortShardKey.Substring(0, [Math]::Min($shortShardKey.Length, $Stage.Length + 13))
    Write-Host (Format-ValidationStatusLine -Status 'running' -Name "reconciliation/$Stage batch $($WorkerEvent.ShardNumber)/$($WorkerEvent.ShardCount)" -Detail ("{0} ({1})" -f $shortShardKey, (Format-ByteSize -Bytes ([long]$WorkerEvent.PayloadSizeBytes))) -NameWidth 42)
}

function Write-ReconciliationBatchPassed {
    param(
        [Parameter(Mandatory = $true)][string]$Stage,
        [Parameter(Mandatory = $true)][object]$Work,
        [Parameter(Mandatory = $true)][long]$TotalElapsedMilliseconds,
        [Parameter(Mandatory = $true)][long]$BatchElapsedMilliseconds,
        [Parameter(Mandatory = $true)][long]$RemainingMilliseconds
    )

    $script:reconciliationCurrentStageProgress.completedCount++
    $detail = "Total Elapsed {0} : [Batch: {1}] : [Remaining: {2}]" -f (Format-ElapsedDuration -Milliseconds $TotalElapsedMilliseconds), (Format-ElapsedDuration -Milliseconds $BatchElapsedMilliseconds), (Format-ElapsedDuration -Milliseconds $RemainingMilliseconds)
    Write-Host (Format-ValidationStatusLine -Status 'passed' -Name "reconciliation/$Stage batch $($script:reconciliationCurrentStageProgress.completedCount)/$($script:reconciliationCurrentStageProgress.totalCount)" -Detail $detail -NameWidth 42)
}

function Write-ReconciliationBatchFailure {
    param(
        [Parameter(Mandatory = $true)][string]$Stage,
        [Parameter(Mandatory = $true)][object]$Work,
        [Parameter(Mandatory = $true)][string]$ErrorMessage,
        [Parameter(Mandatory = $true)][bool]$CanRetry,
        [Parameter(Mandatory = $true)][long]$TotalElapsedMilliseconds,
        [Parameter(Mandatory = $true)][long]$BatchElapsedMilliseconds,
        [Parameter(Mandatory = $true)][long]$RemainingMilliseconds
    )

    foreach ($diagnosticLine in @(Format-IndentedDiagnostic -Label ("[ERROR] Batch {0}/{1}:" -f $Work.ShardNumber, $Work.ShardCount) -Message $ErrorMessage)) {
        Write-Host $diagnosticLine
    }
    $status = if ($CanRetry) { 'retrying' } else { 'failed' }
    $detail = if ($CanRetry) {
        "Total Elapsed {0} : [Batch: {1}] : [Remaining: {2}]" -f (Format-ElapsedDuration -Milliseconds $TotalElapsedMilliseconds), (Format-ElapsedDuration -Milliseconds $BatchElapsedMilliseconds), (Format-ElapsedDuration -Milliseconds $RemainingMilliseconds)
    }
    else {
        "Total Elapsed {0} : [Batch: {1}]" -f (Format-ElapsedDuration -Milliseconds $TotalElapsedMilliseconds), (Format-ElapsedDuration -Milliseconds $BatchElapsedMilliseconds)
    }
    Write-Host (Format-ValidationStatusLine -Status $status -Name "reconciliation/$Stage batch $($Work.ShardNumber)/$($Work.ShardCount)" -Detail $detail -NameWidth 42)
}

Export-ModuleMember -Function @(
    'Get-ReconciliationStagePresentation',
    'Write-ReconciliationStagePlan',
    'Write-ReconciliationBatchStarted',
    'Write-ReconciliationBatchPassed',
    'Write-ReconciliationBatchFailure'
)
