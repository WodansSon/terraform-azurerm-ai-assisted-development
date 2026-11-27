Set-StrictMode -Version Latest

function Write-WorkbenchAuditWarning {
    param([Parameter(Mandatory)][object]$Event)

    if ((@($Event.PSObject.Properties.Name | Sort-Object -CaseSensitive) -join ',') -cne 'code,correlationGuid,kind,persistence' -or
        $Event.kind -cne 'audit-warning' -or $Event.code -cne 'workbench-event-log-incomplete' -or
        $Event.persistence -cnotin @('not-recorded', 'uncertain') -or
        $Event.correlationGuid -isnot [string] -or $Event.correlationGuid -cnotmatch '^[0-9a-f]{8}(-[0-9a-f]{4}){3}-[0-9a-f]{12}$') {
        throw 'Invalid safe Event Log warning; raw content omitted'
    }
    $detail = if ($Event.persistence -ceq 'uncertain') { 'Event Log recording could not be confirmed' } else { 'An Event Log entry was not saved' }
    Write-Warning "$detail. The operation outcome is reported separately. Correlation ID: $($Event.correlationGuid)" -WarningAction Continue
}

function Invoke-WorkbenchAuditTransition {
    param(
        [Parameter(Mandatory)][object]$Audit,
        [Parameter(Mandatory)][ValidateSet('start', 'finish')][string]$Transition,
        [ValidateSet('succeeded', 'failed', 'refused', 'cancelled', 'reused')][string]$Outcome,
        [Collections.IDictionary]$Facts = @{}
    )

    if ($Audit.TransportFailed) { return }
    $previousExitCode = if (Test-Path variable:global:LASTEXITCODE) { $global:LASTEXITCODE } else { 0 }
    try {
        $request = [ordered]@{ actionCode = $Audit.ActionCode; correlationGuid = $Audit.CorrelationGuid; context = $Audit.Context;
            transition = $Transition; facts = $Facts }
        if ($Outcome) { $request.outcome = $Outcome }
        if ($Audit.DatabaseGuid) { $request.databaseGuid = $Audit.DatabaseGuid }
        $output = ($request | ConvertTo-Json -Compress -Depth 20) |
            & node (Join-Path $PSScriptRoot 'WorkbenchDatabase.mjs') audit $Audit.DatabasePath 2>$null
        if ($LASTEXITCODE -ne 0) { throw 'Audit transport did not complete' }
        $packet = ($output -join "`n") | ConvertFrom-Json -Depth 20 -DateKind String
        Update-WorkbenchAuditContext -Audit $Audit -Context $packet.context
        if ($null -ne $packet.warning) { Write-WorkbenchAuditWarning -Event $packet.warning }
    } catch {
        # An unreadable reply cannot prove whether the child committed; do not retry an unacknowledged event.
        $Audit.TransportFailed = $true
        $Audit.Context = [pscustomobject]@{ correlationGuid = $Audit.CorrelationGuid; rootActionCode = $Audit.ActionCode;
            persistence = 'uncertain'; warningIssued = $true; activeActionCode = $Audit.ActionCode;
            activeStartedAt = [DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds(); rootStarted = $true }
        Write-WorkbenchAuditWarning -Event ([pscustomobject]@{ kind = 'audit-warning'; code = 'workbench-event-log-incomplete';
            persistence = 'uncertain'; correlationGuid = $Audit.CorrelationGuid })
    } finally { $global:LASTEXITCODE = $previousExitCode }
}

function Update-WorkbenchAuditContext {
    param([Parameter(Mandatory)][object]$Audit, [Parameter(Mandatory)][object]$Context)

    if ($Context.correlationGuid -cne $Audit.CorrelationGuid -or $Context.rootActionCode -cne $Audit.ActionCode -or
        $Context.persistence -cnotin @('recorded', 'not-recorded', 'uncertain') -or
        $Context.warningIssued -isnot [bool] -or $Context.rootStarted -isnot [bool] -or
        ($null -ne $Context.activeActionCode -and
            ($Context.activeActionCode -isnot [string] -or $Context.activeActionCode -cnotmatch '^[a-z][a-z0-9-]*$'))) {
        throw 'Audit transport returned an invalid operation context; raw content omitted'
    }
    $Audit.Context = $Context
}

function New-WorkbenchAudit {
    param(
        [Parameter(Mandatory)][string]$DatabasePath,
        [Parameter(Mandatory)][ValidateNotNullOrEmpty()][string]$ActionCode,
        [string]$DatabaseGuid,
        [Collections.IDictionary]$Facts = @{}
    )

    $audit = [pscustomobject]@{ DatabasePath = $DatabasePath; DatabaseGuid = $DatabaseGuid; ActionCode = $ActionCode;
        CorrelationGuid = [guid]::NewGuid().ToString(); Context = $null; TransportFailed = $false }
    Invoke-WorkbenchAuditTransition -Audit $audit -Transition start -Facts $Facts
    return $audit
}

Export-ModuleMember -Function New-WorkbenchAudit, Invoke-WorkbenchAuditTransition, Write-WorkbenchAuditWarning, Update-WorkbenchAuditContext
