[CmdletBinding()]
param(
    [ValidateSet('none', 'clean', 'warning', 'malformed', 'nonzero', 'vulnerable', 'secret')]
    [string]$FixtureMode = 'none',

    [ValidateSet('Text', 'Json')]
    [string]$OutputFormat = 'Text'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ($FixtureMode -ne 'none') {
    $count = if ($FixtureMode -ceq 'vulnerable') { 1 } else { 0 }
    $report = [ordered]@{ auditReportVersion = 2; vulnerabilities = @{}; metadata = @{ vulnerabilities = @{ total = $count; info = 0; low = $count; moderate = 0; high = 0; critical = 0 } } }
    if ($count) {
        $report.vulnerabilities['fixture-package'] = [ordered]@{ name = 'fixture-package'; severity = 'low'; isDirect = $true;
            via = @(@{ name = 'fixture-package'; title = 'Synthetic advisory' }); effects = @(); range = '*'; nodes = @('node_modules/fixture-package'); fixAvailable = $false }
    }
    if ($FixtureMode -ceq 'malformed') { [Console]::Out.WriteLine('not json') }
    else { [Console]::Out.WriteLine(($report | ConvertTo-Json -Depth 10 -Compress)) }
    if ($FixtureMode -ceq 'warning') { [Console]::Error.WriteLine('npm warn An arbitrary future diagnostic, not a compatibility-specific message.') }
    if ($FixtureMode -ceq 'secret') { [Console]::Error.WriteLine('npm warn password=SYNTHETIC_PASSWORD https://synthetic:SYNTHETIC_PASSWORD@example.invalid/?token=SYNTHETIC_TOKEN') }
    if ($FixtureMode -cin @('nonzero', 'vulnerable')) { exit 1 }
    return
}

Import-Module (Join-Path $PSScriptRoot '../ValidationOutput.psm1') -Force

$results = [Collections.Generic.List[object]]::new()
$issues = [Collections.Generic.List[string]]::new()
$suiteStopwatch = [Diagnostics.Stopwatch]::StartNew()
$checkStopwatch = [Diagnostics.Stopwatch]::new()
$currentTest = 'production-helpers'

function Start-NpmBoundaryTest {
    param([Parameter(Mandatory = $true)][string]$Name)

    $checkStopwatch.Restart()
    if ($OutputFormat -eq 'Text') {
        Write-Host (Format-ValidationStatusLine -Status 'running' -Name $Name -Detail 'IN PROGRESS')
    }
}

function Add-NpmBoundaryResult {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][bool]$Passed,
        [string]$Message
    )

    $checkStopwatch.Stop()
    $status = if ($Passed) { 'passed' } else { 'failed' }
    $results.Add([pscustomobject]@{ name = $Name; status = $status; durationSeconds = $checkStopwatch.Elapsed.TotalSeconds })
    if (-not $Passed) { $issues.Add("$Name`: $Message") }
    if ($OutputFormat -eq 'Text') {
        $detail = if ($Passed) { Format-ValidationDuration -DurationSeconds $checkStopwatch.Elapsed.TotalSeconds } else { $Message }
        Write-Host (Format-ValidationStatusLine -Status $status -Name $Name -Detail $detail)
    }
}

if ($OutputFormat -eq 'Text') { Write-ValidationSectionHeader -Title 'npm security boundary tests' }
try {
    Start-NpmBoundaryTest -Name $currentTest
    $sourcePath = Join-Path $PSScriptRoot '../Test-NpmSecurity.ps1'
    $tokens = $null
    $parseErrors = $null
    $ast = [Management.Automation.Language.Parser]::ParseFile($sourcePath, [ref]$tokens, [ref]$parseErrors)
    if ($parseErrors.Count) { throw 'The npm security check does not parse' }
    foreach ($name in @('Protect-NpmDiagnostic', 'Invoke-NpmCommand', 'ConvertFrom-NpmAuditOutput')) {
        $definition = $ast.Find({ param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -ceq $name }, $false)
        if ($null -eq $definition) { throw "Missing production helper: $name" }
        . ([scriptblock]::Create($definition.Extent.Text))
    }
    $npmCommand = Get-Command pwsh -ErrorAction Stop
    Add-NpmBoundaryResult -Name $currentTest -Passed $true
    foreach ($mode in @('clean', 'warning', 'malformed', 'nonzero', 'vulnerable', 'secret')) {
        $currentTest = "boundary/$mode"
        Start-NpmBoundaryTest -Name $currentTest
        try {
            $command = Invoke-NpmCommand -Arguments @('-NoProfile', '-NonInteractive', '-File', $PSCommandPath, '-FixtureMode', $mode)
            $audit = ConvertFrom-NpmAuditOutput -CommandResult $command
            if ($mode -ceq 'malformed') {
                if ($null -ne $audit.report) { throw 'Malformed stdout was accepted as an audit report' }
            } else {
                if ($null -eq $audit.report -or $audit.report.metadata.vulnerabilities.total -ne $(if ($mode -ceq 'vulnerable') { 1 } else { 0 })) { throw "Stdout security evidence was lost: $mode" }
            }
            $expectedExitCode = if ($mode -cin @('nonzero', 'vulnerable')) { 1 } else { 0 }
            if ($audit.exitCode -ne $expectedExitCode) { throw "Exit code was lost: $mode" }
            if ($mode -cin @('warning', 'secret')) {
                if ([string]::IsNullOrWhiteSpace($audit.stderr)) { throw "Stderr was dropped: $mode" }
            } elseif ($audit.stderr) { throw "Unexpected stderr: $mode" }
            if ($mode -ceq 'warning' -and $audit.stderr -cne 'npm warn An arbitrary future diagnostic, not a compatibility-specific message.') { throw 'The arbitrary npm warning was reinterpreted or altered' }
            if ($mode -ceq 'secret' -and $audit.stderr -match 'SYNTHETIC_PASSWORD|SYNTHETIC_TOKEN') { throw 'Sensitive diagnostic values were not redacted' }
            Add-NpmBoundaryResult -Name $currentTest -Passed $true
        } catch {
            Add-NpmBoundaryResult -Name $currentTest -Passed $false -Message $_.Exception.Message
        }
    }
    $tempRoot = Join-Path ([IO.Path]::GetTempPath()) ('npm-security-boundary-' + [guid]::NewGuid().ToString('N'))
    $originalPath = $env:PATH
    try {
        $null = [IO.Directory]::CreateDirectory($tempRoot)
        $packageDirectory = Join-Path $tempRoot 'fixture'
        $null = [IO.Directory]::CreateDirectory($packageDirectory)
        $manifest = @{ name = 'synthetic-npm-security-fixture'; version = '0.0.0'; private = $true }
        $lock = @{ name = $manifest.name; version = $manifest.version; lockfileVersion = 3; packages = @{ '' = @{ name = $manifest.name; version = $manifest.version } } }
        [IO.File]::WriteAllText((Join-Path $packageDirectory 'package.json'), ($manifest | ConvertTo-Json -Depth 10))
        [IO.File]::WriteAllText((Join-Path $packageDirectory 'package-lock.json'), ($lock | ConvertTo-Json -Depth 10))
        $shimPath = Join-Path $tempRoot $(if ($IsWindows) { 'npm.cmd' } else { 'npm' })
        $pwshPath = (Get-Command pwsh).Source
        foreach ($mode in @('clean', 'warning', 'malformed', 'nonzero', 'vulnerable', 'secret')) {
            $currentTest = "complete/$mode"
            Start-NpmBoundaryTest -Name $currentTest
            try {
                if ($IsWindows) {
                    $shim = "@echo off`r`n`"$pwshPath`" -NoProfile -NonInteractive -File `"$PSCommandPath`" -FixtureMode $mode`r`n"
                } else {
                    $shim = "#!/bin/sh`nexec '$($pwshPath.Replace("'", "'\''"))' -NoProfile -NonInteractive -File '$($PSCommandPath.Replace("'", "'\''"))' -FixtureMode $mode`n"
                }
                [IO.File]::WriteAllText($shimPath, $shim, [Text.UTF8Encoding]::new($false))
                if (-not $IsWindows) { [IO.File]::SetUnixFileMode($shimPath, [IO.UnixFileMode]::UserRead -bor [IO.UnixFileMode]::UserWrite -bor [IO.UnixFileMode]::UserExecute) }
                $env:PATH = $tempRoot + [IO.Path]::PathSeparator + $originalPath
                $output = @(& pwsh -NoProfile -NonInteractive -File $sourcePath -RepositoryRoot $tempRoot -LockPath 'fixture/package-lock.json' -OutputFormat Json)
                $exitCode = $LASTEXITCODE
                $reportResult = ($output | Out-String) | ConvertFrom-Json -Depth 20 -ErrorAction Stop
                if ($mode -ceq 'clean') {
                    if ($exitCode -ne 0 -or $reportResult.status -cne 'passed' -or $reportResult.reports[0].securityStatus -cne 'passed' -or $reportResult.reports[0].diagnosticsStatus -cne 'passed') { throw 'The clean audit did not pass' }
                } else {
                    if ($exitCode -ne 1 -or $reportResult.status -cne 'failed') { throw "The complete check accepted $mode" }
                    if ($mode -ceq 'malformed') {
                        if ($reportResult.reports.Count -ne 0 -or -not ($reportResult.failures -match 'complete vulnerability report')) { throw 'Malformed output was not identified as an unusable security report' }
                    } else {
                        $auditReport = $reportResult.reports[0]
                        $expectedSecurity = if ($mode -ceq 'vulnerable') { 'failed' } else { 'passed' }
                        $expectedDiagnostics = if ($mode -cin @('warning', 'secret')) { 'failed' } else { 'passed' }
                        if ($auditReport.securityStatus -cne $expectedSecurity -or $auditReport.diagnosticsStatus -cne $expectedDiagnostics) { throw "Security and diagnostics were conflated: $mode" }
                        if ($mode -ceq 'nonzero' -and -not ($reportResult.failures -match 'exited with code 1')) { throw 'The nonzero command exit was not reported' }
                        if ($mode -ceq 'warning' -and $auditReport.diagnostics -cne 'npm warn An arbitrary future diagnostic, not a compatibility-specific message.') { throw 'The npm warning was not preserved in the complete report' }
                        if ($mode -ceq 'secret' -and ($output | Out-String) -match 'SYNTHETIC_PASSWORD|SYNTHETIC_TOKEN') { throw 'The complete report exposed synthetic sensitive values' }
                    }
                }
                $textOutput = @(& pwsh -NoProfile -NonInteractive -File $sourcePath -RepositoryRoot $tempRoot -LockPath 'fixture/package-lock.json')
                $textExitCode = $LASTEXITCODE
                $text = $textOutput -join "`n"
                if ($textExitCode -ne $exitCode) { throw "Text formatting changed the CI exit code: $mode" }
                if ($text -notmatch 'NPM SECURITY VALIDATION\n' -or $text -notmatch 'NPM SECURITY VALIDATION SUMMARY\n' -or $text -notmatch '\[RUNNING\]\s+fixture/package-lock.json\s+:' -or $text -notmatch '(?m)^  Status\s+: (PASSED|FAILED)$') { throw "The production checker does not use shared text presentation: $mode" }
                if ($mode -ceq 'warning' -and $text -notmatch 'npm warn An arbitrary future diagnostic') { throw 'The warning is not visible in text output' }
                if ($mode -ceq 'secret' -and $text -match 'SYNTHETIC_PASSWORD|SYNTHETIC_TOKEN') { throw 'Text output exposed synthetic sensitive values' }
                Add-NpmBoundaryResult -Name $currentTest -Passed $true
            } catch {
                Add-NpmBoundaryResult -Name $currentTest -Passed $false -Message $_.Exception.Message
            }
        }
    } finally {
        $env:PATH = $originalPath
        if (Test-Path -LiteralPath $tempRoot) { Remove-Item -LiteralPath $tempRoot -Recurse -Force }
    }
} catch {
    Add-NpmBoundaryResult -Name $currentTest -Passed $false -Message $_.Exception.Message
} finally { $suiteStopwatch.Stop() }

$passedCount = @($results | Where-Object { $_.status -ceq 'passed' }).Count
$result = [ordered]@{ status = if ($issues.Count) { 'failed' } else { 'passed' }; tests = $results.Count; passed = $passedCount; failed = $results.Count - $passedCount;
    durationSeconds = $suiteStopwatch.Elapsed.TotalSeconds; results = $results.ToArray(); issues = $issues.ToArray() }
if ($OutputFormat -eq 'Json') {
    $result | ConvertTo-Json -Depth 8
} else {
    Write-ValidationSectionHeader -Title 'npm security boundary test summary'
    Write-ValidationSummary -Fields ([ordered]@{ Status = $result.status.ToUpperInvariant(); Tests = $result.tests; Passed = $result.passed; Failed = $result.failed;
        Duration = Format-ValidationDuration -DurationSeconds $suiteStopwatch.Elapsed.TotalSeconds })
    if ($issues.Count) {
        Write-ValidationSectionHeader -Title 'Failures'
        foreach ($issue in $issues) { Write-Output "  - $issue" }
    }
    Complete-ValidationTextOutput
}
if ($issues.Count) { exit 1 }
