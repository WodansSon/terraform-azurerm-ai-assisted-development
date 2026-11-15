Set-StrictMode -Version Latest

function Start-WorkbenchActivity {
    param(
        [Parameter(Mandatory)][ValidatePattern('^[A-Za-z][A-Za-z0-9 -]*$')][string]$Name,
        [Diagnostics.Stopwatch]$Clock = [Diagnostics.Stopwatch]::StartNew()
    )

    [pscustomobject]@{
        Name = $Name
        Clock = $Clock
        Active = $true
        Interactive = -not [Console]::IsOutputRedirected -and $Host.UI.SupportsVirtualTerminal
        Drawn = $false
        CursorHidden = $false
        Frame = 0
        NextFrameMilliseconds = $Clock.ElapsedMilliseconds + 1000
        ExitCode = $null
        StderrCharacters = 0L
    }
}

function Update-WorkbenchActivity {
    param(
        [Parameter(Mandatory)][object]$Activity,
        [Parameter(Mandatory)][ValidatePattern('^[A-Za-z][A-Za-z0-9 -]*$')][string]$Name
    )

    $Activity.Name = $Name
}

function Clear-WorkbenchActivity {
    param([Parameter(Mandatory)][object]$Activity)

    if ($Activity.Drawn) {
        [Console]::Write("`r$([char]27)[K")
        $Activity.Drawn = $false
    }
}

function Write-WorkbenchActivityFrame {
    param(
        [Parameter(Mandatory)][object]$Activity,
        [switch]$Force,
        [ValidateRange(0, [int]::MaxValue)][Nullable[int]]$WindowWidth
    )

    if (-not $Activity.Active -or -not $Activity.Interactive) { return }
    $elapsed = $Activity.Clock.Elapsed
    if (-not $Force -and $elapsed.TotalMilliseconds -lt $Activity.NextFrameMilliseconds) { return }
    if ($elapsed.TotalMilliseconds -ge $Activity.NextFrameMilliseconds) {
        $Activity.Frame = ($Activity.Frame + 1) % 4
        $Activity.NextFrameMilliseconds = $elapsed.TotalMilliseconds + 1000
    }
    if (-not $Activity.CursorHidden) {
        $Activity.CursorHidden = $true
        [Console]::Write("$([char]27)[?25l")
    }
    $dots = @('.', '..', '...', '')[$Activity.Frame]
    $duration = '{0:00}:{1:00}:{2:00}' -f [int][Math]::Floor($elapsed.TotalHours), $elapsed.Minutes, $elapsed.Seconds
    $line = '{0}: {1,-3} [Elapsed: {2}]' -f $Activity.Name, $dots, $duration
    if ($null -eq $WindowWidth) { $WindowWidth = [Console]::WindowWidth }
    $width = [Math]::Max(1, $WindowWidth - 1)
    if ($line.Length -gt $width) { $line = '{0} {1,-3} {2}' -f $Activity.Name, $dots, $duration }
    if ($line.Length -gt $width) { $line = $line.Substring(0, $width) }
    [Console]::Write("`r" + $PSStyle.Foreground.Yellow + $line + $PSStyle.Reset + "$([char]27)[K")
    $Activity.Drawn = $true
}

function Stop-WorkbenchActivity {
    param([Parameter(Mandatory)][object]$Activity)

    $Activity.Active = $false
    try { Clear-WorkbenchActivity -Activity $Activity }
    finally {
        if ($Activity.CursorHidden) {
            [Console]::Write($PSStyle.Reset + "$([char]27)[?25h")
            $Activity.CursorHidden = $false
        }
    }
}

function Invoke-WorkbenchActivityProcess {
    param(
        [Parameter(Mandatory)][string[]]$Arguments,
        [Parameter(Mandatory)][string]$InputObject,
        [Parameter(Mandatory)][object]$Activity
    )

    $process = [Diagnostics.Process]::new()
    $started = $false
    try {
        $process.StartInfo.FileName = (Get-Command node -CommandType Application -ErrorAction Stop).Source
        $process.StartInfo.UseShellExecute = $false
        $process.StartInfo.CreateNoWindow = $true
        $process.StartInfo.RedirectStandardInput = $true
        $process.StartInfo.RedirectStandardOutput = $true
        $process.StartInfo.RedirectStandardError = $true
        $process.StartInfo.StandardInputEncoding = [Text.UTF8Encoding]::new($false)
        $process.StartInfo.StandardOutputEncoding = [Text.UTF8Encoding]::new($false)
        $process.StartInfo.StandardErrorEncoding = [Text.UTF8Encoding]::new($false)
        $process.StartInfo.WorkingDirectory = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath('.')
        foreach ($argument in $Arguments) { $process.StartInfo.ArgumentList.Add($argument) }
        $started = $process.Start()
        if (-not $started) { throw 'Native analysis process did not start' }
        $process.StandardInput.WriteLine($InputObject)
        $process.StandardInput.Close()
        $stdout = $process.StandardOutput.ReadLineAsync()
        $stderrBuffer = [char[]]::new(4096)
        $stderr = $process.StandardError.ReadAsync($stderrBuffer, 0, $stderrBuffer.Length)
        $exited = $process.WaitForExitAsync()
        Write-WorkbenchActivityFrame -Activity $Activity -Force
        while ($null -ne $stdout -or $null -ne $stderr -or -not $exited.IsCompleted) {
            if ($null -ne $stdout -and $stdout.IsCompleted) {
                $line = $stdout.GetAwaiter().GetResult()
                if ($null -eq $line) { $stdout = $null }
                else {
                    Clear-WorkbenchActivity -Activity $Activity
                    Write-Output $line
                    $stdout = $process.StandardOutput.ReadLineAsync()
                    Write-WorkbenchActivityFrame -Activity $Activity -Force
                }
            }
            if ($null -ne $stderr -and $stderr.IsCompleted) {
                $count = $stderr.GetAwaiter().GetResult()
                if ($count -eq 0) { $stderr = $null }
                else {
                    $Activity.StderrCharacters += $count
                    $stderr = $process.StandardError.ReadAsync($stderrBuffer, 0, $stderrBuffer.Length)
                }
            }
            Write-WorkbenchActivityFrame -Activity $Activity
            $pending = @($stdout, $stderr, $exited | Where-Object { $null -ne $_ -and -not $_.IsCompleted })
            if ($pending.Count -gt 0) { $null = [Threading.Tasks.Task]::WaitAny([Threading.Tasks.Task[]]$pending, 1000) }
        }
        $null = $exited.GetAwaiter().GetResult()
        $Activity.ExitCode = $process.ExitCode
    } finally {
        try {
            if ($started -and -not $process.HasExited) {
                $process.Kill($true)
                if (-not $process.WaitForExit(5000)) { throw 'Native analysis child processes did not stop; execution ownership requires inspection' }
            }
        } finally {
            try { Stop-WorkbenchActivity -Activity $Activity }
            finally { $process.Dispose() }
        }
    }
}

Export-ModuleMember -Function Start-WorkbenchActivity, Update-WorkbenchActivity, Stop-WorkbenchActivity, Invoke-WorkbenchActivityProcess
