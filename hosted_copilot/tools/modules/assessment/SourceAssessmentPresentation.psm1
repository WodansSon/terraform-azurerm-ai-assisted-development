Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Import-Module (Join-Path $PSScriptRoot '../shared/HostedToolkit.Helpers.psm1')

function Get-SourceAssessmentBootstrapBytesPerSecondPerWorker {
    return 400
}

function Write-SourceAssessmentCacheSkipped {
    param([Parameter(Mandatory = $true)][string]$Detail)

    Write-Host (Format-ValidationStatusLine -Status 'skipped' -Name 'source-assessment/cache' -Detail $Detail -NameWidth 42)
}

function Write-SourceAssessmentPlan {
    param(
        [Parameter(Mandatory = $true)][int]$TotalSourceCount,
        [Parameter(Mandatory = $true)][int]$CachedSourceCount,
        [Parameter(Mandatory = $true)][int]$RecoveredSourceCount,
        [Parameter(Mandatory = $true)][int]$PendingSourceCount,
        [Parameter(Mandatory = $true)][int]$BatchCount,
        [Parameter(Mandatory = $true)][int]$WorkerCount,
        [Parameter(Mandatory = $true)][long]$PendingPayloadBytes,
        [Parameter(Mandatory = $true)][long]$EstimatedMilliseconds
    )

    if ($PendingSourceCount -eq 0) {
        Write-Host ("  Sources   : {0} total | {1} cached | {2} recovered" -f $TotalSourceCount, $CachedSourceCount, $RecoveredSourceCount)
        $execution = if ($RecoveredSourceCount -eq 0) { 'Fully cached' } else { 'No evaluation required' }
        Write-Host ("  Execution : {0}" -f $execution)
        return
    }
    Write-Host ("  Sources   : {0} total | {1} cached | {2} recovered | {3} pending" -f $TotalSourceCount, $CachedSourceCount, $RecoveredSourceCount, $PendingSourceCount)
    Write-Host ("  Batches   : {0} pending" -f $BatchCount)
    Write-Host ("  Workers   : {0}" -f $WorkerCount)
    Write-Host ("  Payload   : {0}" -f (Format-ByteSize -Bytes $PendingPayloadBytes))
    Write-Host ("  Estimated : {0}" -f (Format-ElapsedDuration -Milliseconds $EstimatedMilliseconds))
    Write-Host ''
    Write-Host (Format-ValidationStatusLine -Status 'running' -Name 'source-assessment' -Detail ("Evaluating {0} pending sources across {1} batches" -f $PendingSourceCount, $BatchCount) -NameWidth 42)
}

function Write-SourceAssessmentBatchStarted {
    param([Parameter(Mandatory = $true)][object]$WorkerResult)

    Write-Host (Format-ValidationStatusLine -Status 'running' -Name "source-assessment $($WorkerResult.BatchNumber)/$($WorkerResult.BatchCount)" -Detail ("{0} ({1} sources)" -f $WorkerResult.BatchId, $WorkerResult.SourceCount) -NameWidth 42)
}

function Write-SourceAssessmentBatchPassed {
    param(
        [Parameter(Mandatory = $true)][object]$Batch,
        [Parameter(Mandatory = $true)][long]$TotalElapsedMilliseconds,
        [Parameter(Mandatory = $true)][long]$BatchElapsedMilliseconds,
        [Parameter(Mandatory = $true)][long]$RemainingMilliseconds
    )

    $detail = "Total Elapsed {0} : [Batch: {1}] : [Remaining: {2}]" -f (Format-ElapsedDuration -Milliseconds $TotalElapsedMilliseconds), (Format-ElapsedDuration -Milliseconds $BatchElapsedMilliseconds), (Format-ElapsedDuration -Milliseconds $RemainingMilliseconds)
    Write-Host (Format-ValidationStatusLine -Status 'passed' -Name "source-assessment $($Batch.BatchNumber)/$($Batch.BatchCount)" -Detail $detail -NameWidth 42)
}

function Write-SourceAssessmentBatchFailure {
    param(
        [Parameter(Mandatory = $true)][object]$Batch,
        [Parameter(Mandatory = $true)][string]$ErrorMessage,
        [Parameter(Mandatory = $true)][bool]$CanRetry,
        [Parameter(Mandatory = $true)][long]$TotalElapsedMilliseconds,
        [Parameter(Mandatory = $true)][long]$BatchElapsedMilliseconds,
        [Parameter(Mandatory = $true)][long]$RemainingMilliseconds
    )

    foreach ($diagnosticLine in @(Format-IndentedDiagnostic -Label ("[ERROR] Batch {0}/{1}:" -f $Batch.BatchNumber, $Batch.BatchCount) -Message $ErrorMessage)) {
        Write-Host $diagnosticLine
    }
    $status = if ($CanRetry) { 'retrying' } else { 'failed' }
    $detail = if ($CanRetry) {
        "Total Elapsed {0} : [Batch: {1}] : [Remaining: {2}]" -f (Format-ElapsedDuration -Milliseconds $TotalElapsedMilliseconds), (Format-ElapsedDuration -Milliseconds $BatchElapsedMilliseconds), (Format-ElapsedDuration -Milliseconds $RemainingMilliseconds)
    }
    else {
        "Total Elapsed {0} : [Batch: {1}]" -f (Format-ElapsedDuration -Milliseconds $TotalElapsedMilliseconds), (Format-ElapsedDuration -Milliseconds $BatchElapsedMilliseconds)
    }
    Write-Host (Format-ValidationStatusLine -Status $status -Name "source-assessment $($Batch.BatchNumber)/$($Batch.BatchCount)" -Detail $detail -NameWidth 42)
}

function Write-SourceAssessmentCompleted {
    param(
        [Parameter(Mandatory = $true)][object]$Result,
        [Parameter(Mandatory = $true)][long]$ElapsedMilliseconds
    )

    $detail = "{0} sources | {1} cached | {2} recovered | {3} evaluated : [Elapsed: {4}]" -f $Result.sourceCount, $Result.cachedSourceCount, $Result.recoveredSourceCount, $Result.evaluatedSourceCount, (Format-ElapsedDuration -Milliseconds $ElapsedMilliseconds)
    Write-Host (Format-ValidationStatusLine -Status 'passed' -Name 'source-assessment' -Detail $detail -NameWidth 42)
}

Export-ModuleMember -Function @(
    'Get-SourceAssessmentBootstrapBytesPerSecondPerWorker',
    'Write-SourceAssessmentCacheSkipped',
    'Write-SourceAssessmentPlan',
    'Write-SourceAssessmentBatchStarted',
    'Write-SourceAssessmentBatchPassed',
    'Write-SourceAssessmentBatchFailure',
    'Write-SourceAssessmentCompleted'
)
