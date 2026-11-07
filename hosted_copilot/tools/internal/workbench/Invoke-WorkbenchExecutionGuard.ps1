[CmdletBinding()]
param([Parameter(Mandatory)][ValidateSet('claim', 'release', 'cancel-children')][string]$Action)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$request = [Console]::In.ReadToEnd() | ConvertFrom-Json -Depth 10
if ($request.pid -lt 1 -or $request.pid -gt [int]::MaxValue -or $request.nonce -cnotmatch '^[a-f0-9]{32}$') {
    throw 'Execution lock requires a valid process identity and acquisition ID'
}
$databasePath = [IO.Path]::GetFullPath([string]$request.databasePath)
$lockPath = $databasePath + '.assessment.lock'
if (-not [IO.Path]::IsPathRooted($request.databasePath) -or $databasePath.StartsWith('\\')) { throw 'Execution lock requires an absolute local database path' }
$comparison = if ($IsWindows) { [StringComparison]::OrdinalIgnoreCase } else { [StringComparison]::Ordinal }

function Get-OwnerStart {
    param([int]$ProcessId)

    try { $owner = [Diagnostics.Process]::GetProcessById($ProcessId) }
    catch [ArgumentException] { return $null }
    try { return $owner.StartTime.ToUniversalTime().Ticks.ToString([Globalization.CultureInfo]::InvariantCulture) }
    finally { $owner.Dispose() }
}

function Read-LockRecord {
    if (-not [IO.File]::Exists($lockPath)) { return $null }
    $file = Get-Item -LiteralPath $lockPath -Force
    if (($file.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0 -or $file.Length -gt 4096) { throw 'Execution lock ownership is uncertain' }
    if ($file.Length -eq 0) { return [pscustomobject]@{ legacy = $true } }
    try { $record = [IO.File]::ReadAllText($lockPath) | ConvertFrom-Json -Depth 10 }
    catch { throw 'Execution lock ownership is uncertain; malformed owner record' }
    $names = @($record.PSObject.Properties.Name | Sort-Object -CaseSensitive)
    if (($names -join ',') -cne 'databasePath,kind,nonce,pid,processStartTicks,schemaVersion' -or
        $record.kind -cne 'hosted-workbench-execution-lock' -or $record.schemaVersion -ne 1 -or
        $record.pid -lt 1 -or $record.pid -gt [int]::MaxValue -or $record.nonce -cnotmatch '^[a-f0-9]{32}$' -or
        $record.processStartTicks -cnotmatch '^\d+$' -or -not [string]::Equals($record.databasePath, $databasePath, $comparison)) {
        throw 'Execution lock ownership is uncertain; unsupported owner record'
    }
    return $record
}

function Assert-LegacyLockAbandoned {
    if (-not $IsWindows) { throw 'Legacy ownerless lock recovery cannot establish process ownership on this platform' }
    $escapedName = [IO.Path]::GetFileName([IO.Path]::GetDirectoryName($databasePath)).Replace("'", "''")
    $queries = @(
        "CommandLine LIKE '%WorkbenchDatabase.mjs%' AND CommandLine LIKE '%$escapedName%'",
        "CommandLine LIKE '%Invoke-NativeEvaluation.ps1%'",
        "CommandLine LIKE '%hosted-native-evaluation-%'"
    )
    foreach ($query in $queries) {
        $owners = @(Get-CimInstance -ClassName Win32_Process -Filter $query -Property ProcessId -ErrorAction Stop |
            Where-Object { $_.ProcessId -ne $request.pid -and $_.ProcessId -ne $PID })
        if ($owners.Count) { throw 'Legacy execution lock ownership is uncertain; an associated worker may still be live' }
    }
    $probe = [IO.File]::Open($lockPath, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::None)
    $probe.Dispose()
}

$keyPath = if ($IsWindows) { $databasePath.ToUpperInvariant() } else { $databasePath }
$digest = [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData([Text.Encoding]::UTF8.GetBytes($keyPath)))
$mutex = [Threading.Mutex]::new($false, 'HostedWorkbenchExecution-' + $digest)
$acquired = $false
try {
    try { $acquired = $mutex.WaitOne(0) }
    catch [Threading.AbandonedMutexException] { $acquired = $true }
    if (-not $acquired) {
        @{ failureCode = 'execution-already-running' } | ConvertTo-Json -Compress
        return
    }
    $record = Read-LockRecord
    if ($Action -eq 'claim') {
        $start = Get-OwnerStart -ProcessId $request.pid
        if ($null -eq $start) { throw 'Execution lock claimant is no longer live' }
        $recovered = $false
        if ($null -ne $record) {
            if ($null -ne $record.PSObject.Properties['legacy']) { Assert-LegacyLockAbandoned }
            else {
                $ownerStart = Get-OwnerStart -ProcessId $record.pid
                if ($ownerStart -ceq $record.processStartTicks) {
                    @{ failureCode = 'execution-already-running' } | ConvertTo-Json -Compress
                    return
                }
            }
            [IO.File]::Delete($lockPath)
            $recovered = $true
        }
        $ownerRecord = [ordered]@{ kind = 'hosted-workbench-execution-lock'; schemaVersion = 1; databasePath = $databasePath;
            pid = $request.pid; processStartTicks = $start; nonce = $request.nonce }
        $stagingPath = $lockPath + '.' + $request.nonce + '.pending'
        $stream = [IO.File]::Open($stagingPath, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::None)
        try {
            $bytes = [Text.UTF8Encoding]::new($false).GetBytes(($ownerRecord | ConvertTo-Json -Compress))
            $stream.Write($bytes, 0, $bytes.Length)
            $stream.Flush($true)
        } finally { $stream.Dispose() }
        try { [IO.File]::Move($stagingPath, $lockPath, $false) }
        finally { if ([IO.File]::Exists($stagingPath)) { [IO.File]::Delete($stagingPath) } }
        [ordered]@{ processStartTicks = $start; recovered = $recovered } | ConvertTo-Json -Compress
    } elseif ($Action -eq 'release') {
        if ($null -ne $record -and $null -eq $record.PSObject.Properties['legacy'] -and
            $record.pid -eq $request.pid -and $record.nonce -ceq $request.nonce -and $record.processStartTicks -ceq $request.processStartTicks) {
            [IO.File]::Delete($lockPath)
        }
        '{}' | Write-Output
    } else {
        if ($null -eq $record -or $null -ne $record.PSObject.Properties['legacy'] -or $record.pid -ne $request.pid -or
            $record.nonce -cne $request.nonce -or $record.processStartTicks -cne $request.processStartTicks -or
            (Get-OwnerStart -ProcessId $request.pid) -cne $record.processStartTicks) { throw 'Cancellation requires the current execution owner' }
        if (-not $IsWindows) { throw 'Native child ownership inspection is not supported on this platform' }
        $children = @(Get-CimInstance -ClassName Win32_Process -Filter "ParentProcessId = $($request.pid)" -Property ProcessId, CreationDate)
        foreach ($child in $children) {
            if ($child.ProcessId -eq $PID) { continue }
            try { $ownedChild = [Diagnostics.Process]::GetProcessById($child.ProcessId) }
            catch [ArgumentException] { continue }
            try {
                $childStart = $ownedChild.StartTime.ToUniversalTime()
                if ($childStart.Ticks -lt [long]$record.processStartTicks -or
                    [Math]::Abs($childStart.Ticks - $child.CreationDate.ToUniversalTime().Ticks) -ge 10) {
                    throw 'Cancellation child ownership changed before termination'
                }
                $ownedChild.Kill($true)
                $ownedChild.WaitForExit()
            } finally { $ownedChild.Dispose() }
        }
        '{}' | Write-Output
    }
} finally {
    if ($acquired) { $mutex.ReleaseMutex() }
    $mutex.Dispose()
}
