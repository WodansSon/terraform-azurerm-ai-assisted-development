<#
.SYNOPSIS
Starts the isolated native SQL Workbench New comparison instance.
.DESCRIPTION
Validates the current repository branch database, completed native analysis, published guidance, runtime assets, and assigned
CLI models before serving SQL facts and explicit wording revisions. Does not initialize a workspace, collect sources, or invoke inference.
.PARAMETER DatabasePath
Optional override for the existing native workspace database location.
.PARAMETER EvaluatorCommand
Copilot CLI executable used for authenticated model and reasoning-effort availability checks without inference.
.PARAMETER Port
Loopback port override. Uses the normal legacy default when omitted.
.PARAMETER NoLaunch
Starts the server without opening a browser.
.PARAMETER Help
Shows command help without opening the database.
.PARAMETER Detailed
Shows command help without opening the database.
.EXAMPLE
./Start-RuleWorkbenchNew.ps1 -NoLaunch -Port 43148
Starts Workbench New for side-by-side comparison using this repository's initialized database.
.NOTES
Both launchers default to 43143. Use explicit ports 43147 and 43148 for side-by-side comparison.
Source wording Save uses the local SQL database. Evaluator, Plan and approval integration remain separate work.
.LINK
Get-Help
#>
[CmdletBinding(DefaultParameterSetName = 'Default')]
param(
    [Parameter(ParameterSetName = 'Default')][string]$DatabasePath,
    [Parameter(ParameterSetName = 'Default')][ValidateNotNullOrEmpty()][string]$EvaluatorCommand = 'copilot',
    [Parameter(ParameterSetName = 'Default')][ValidateRange(1024, 65535)][int]$Port = 43143,
    [Parameter(ParameterSetName = 'Default')][switch]$NoLaunch,
    [Parameter(Mandatory, ParameterSetName = 'Help')][Alias('h')][switch]$Help,
    [Parameter(Mandatory, ParameterSetName = 'Detailed')][switch]$Detailed
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
if ($Help -or $Detailed) {
    Import-Module (Join-Path $PSScriptRoot 'modules/shared/HostedCommandHelp.psm1') -Force
    Show-HostedCommandHelp -ScriptPath $PSCommandPath -DisplayName 'Workbench New Help' -ParameterGroups ([ordered]@{
        'Storage' = @('DatabasePath')
        'AI Availability' = @('EvaluatorCommand')
        'Server And Output' = @('Port', 'NoLaunch')
    })
    return
}
Import-Module (Join-Path $PSScriptRoot '../../tools/ValidationOutput.psm1') -Force
Import-Module (Join-Path $PSScriptRoot 'modules/shared/HostedCli.psm1') -Force
Import-Module (Join-Path $PSScriptRoot 'modules/workbench/Workbench.Audit.psm1') -Force
$checks = [Collections.Generic.List[object]]::new()
$startupAudit = $null

function Add-WorkbenchNewLaunchCheck {
    param([string]$Name, [ValidateSet('passed', 'failed')][string]$Status, [string]$Detail)

    $checks.Add([pscustomobject]@{ name = $Name; status = $Status })
    Format-ValidationStatusLine -Status $Status -Name $Name -Detail $Detail -NameWidth 42 | Write-Host
}

function Write-WorkbenchNewLaunchSummary {
    param([string]$Status, [string[]]$FailureMessages = @())

    Write-ValidationSectionHeader -Title 'Workbench New Startup Summary' | Write-Host
    Write-ValidationSummary -Fields ([ordered]@{
        Status = $Status
        Checks = $checks.Count
        Passed = @($checks | Where-Object status -CEQ 'passed').Count
        Failed = @($checks | Where-Object status -CEQ 'failed').Count
    }) | Write-Host
    Write-Host ''
    Write-ValidationTwoColumnTable -Rows $checks.ToArray() -FirstHeader 'Status' -FirstProperty 'status' -SecondHeader 'Check' -SecondProperty 'name' -UppercaseFirst | Write-Host
    if ($Status -ceq 'FAILED') {
        Write-ValidationSectionHeader -Title 'Failure Summary' | Write-Host
        foreach ($message in $FailureMessages) { Write-Host ('  - ' + $message) }
    } else {
        Complete-ValidationTextOutput | Write-Host
    }
}

function Invoke-WorkbenchNewLaunchProbe {
    param([string]$NodePath, [string]$ServerPath, [Collections.IDictionary]$Context)

    $probe = [Diagnostics.Process]::new()
    $probe.StartInfo.FileName = $NodePath
    $probe.StartInfo.UseShellExecute = $false
    $probe.StartInfo.CreateNoWindow = $true
    $probe.StartInfo.RedirectStandardInput = $true
    $probe.StartInfo.RedirectStandardOutput = $true
    $probe.StartInfo.RedirectStandardError = $true
    $probe.StartInfo.ArgumentList.Add($ServerPath)
    $probeStarted = $false
    try {
        $probeStarted = $probe.Start()
        if (-not $probeStarted) { throw 'Native launch preflight process could not start' }
        $output = $probe.StandardOutput.ReadToEndAsync()
        $diagnostics = $probe.StandardError.BaseStream.CopyToAsync([IO.Stream]::Null)
        $probe.StandardInput.WriteLine(($Context | ConvertTo-Json -Compress))
        $probe.StandardInput.Close()
        if (-not $probe.WaitForExit(30000)) { throw 'Native launch preflight timed out' }
        $packet = $output.GetAwaiter().GetResult() | ConvertFrom-Json -Depth 30 -DateKind String
        $null = $diagnostics.GetAwaiter().GetResult()
        if ($packet.kind -cnotin @('preflight', 'failed') -or ($probe.ExitCode -ne 0 -and $packet.kind -cne 'failed')) {
            throw 'Native launch preflight returned an invalid response'
        }
        return $packet
    } finally {
        if ($probeStarted -and -not $probe.HasExited) { $probe.Kill($true); $probe.WaitForExit() }
        $probe.Dispose()
    }
}

$phase = 'runtime'
$phaseDetail = 'PowerShell 7.5 or newer and Node with SQLite support are required'
try {
    Write-ValidationSectionHeader -Title 'Workbench New Launch Requirements' | Write-Host
    if ($PSVersionTable.PSVersion -lt [version]'7.5') { throw $phaseDetail }
    $node = Get-Command node -CommandType Application -ErrorAction Stop
    Add-WorkbenchNewLaunchCheck -Name $phase -Status passed -Detail 'PowerShell runtime and Node executable resolved'
    $phase = 'repository-database'
    $phaseDetail = 'A named repository branch and its initialized SQL database are required; initialize explicitly rather than creating one during launch'
    $repositoryRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
    $branchRef = [string](& git -C $repositoryRoot symbolic-ref --quiet HEAD 2>$null)
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($branchRef)) { throw $phaseDetail }
    $branchRef = $branchRef.Trim()
    if ([string]::IsNullOrWhiteSpace($DatabasePath)) {
        Import-Module (Join-Path $PSScriptRoot 'modules/workbench/Workbench.DatabaseLocation.psm1') -Force
        $DatabasePath = Get-WorkbenchDatabaseLocation -RepositoryRoot $repositoryRoot -BranchRef $branchRef
    }
    $startupAudit = New-WorkbenchAudit -DatabasePath $DatabasePath -ActionCode start-workbench -Facts @{ requestedPort = $Port }
    if (-not (Test-Path -LiteralPath $DatabasePath -PathType Leaf)) { throw $phaseDetail }
    Add-WorkbenchNewLaunchCheck -Name $phase -Status passed -Detail 'Recorded repository/branch database found; no initialization performed'
    $phase = 'github-context'
    $phaseDetail = 'GitHub authorization and target-repository context must validate'
    Import-Module (Join-Path $PSScriptRoot 'modules/workbench/Workbench.GitHubContext.psm1') -Force
    $githubContext = Get-HostedWorkbenchGitHubContext -RepositoryRoot $repositoryRoot
    if ($githubContext.maintainerIdentity.status -cnotin @('validated', 'unauthorized') -or $githubContext.targetRepository.status -cne 'validated') { throw $phaseDetail }
    Add-WorkbenchNewLaunchCheck -Name $phase -Status passed -Detail 'GitHub identity and target context validated'
    $phase = 'native-preflight'
    $phaseDetail = 'The selected SQL schema and repository/branch binding must validate; no migration is performed during launch'
    $serverPath = Join-Path $PSScriptRoot 'modules/workbench/WorkbenchNewServer.mjs'
    $launchContext = [ordered]@{ databasePath = [IO.Path]::GetFullPath($DatabasePath); repositoryRoot = $repositoryRoot;
        branchRef = $branchRef; port = $Port; ownerProcessId = $PID; targetRepository = $githubContext.targetRepository; preflightOnly = $true }
    $preflight = Invoke-WorkbenchNewLaunchProbe -NodePath $node.Source -ServerPath $serverPath -Context $launchContext
    foreach ($check in $preflight.checks) { Add-WorkbenchNewLaunchCheck -Name $check.name -Status $check.status -Detail $check.detail }
    if ($preflight.kind -cne 'preflight') { throw $phaseDetail }
    Add-WorkbenchNewLaunchCheck -Name $phase -Status passed -Detail 'SQLite schema and repository/branch binding validated without writes'
    $phase = 'llm-availability'
    $phaseDetail = 'Every assigned model must be available through an authenticated compatible Copilot CLI'
    Write-ValidationSectionHeader -Title 'LLM Availability' | Write-Host
    $profiles = [ordered]@{}
    foreach ($assignment in $preflight.llmAssignments) {
        if ($assignment.providerCode -cne 'github-copilot' -or $assignment.adapterCode -cne 'copilot-cli' -or $profiles.Contains($assignment.taskCode)) { throw $phaseDetail }
        $profiles[$assignment.taskCode] = @{ model = $assignment.model; reasoningEffort = $assignment.reasoningEffort }
    }
    if ($profiles.Count -eq 0) { throw $phaseDetail }
    $cliLaunch = Resolve-HostedCliLaunch -EvaluatorCommand $EvaluatorCommand
    $availability = Get-HostedCliAvailability -Launch $cliLaunch -Profiles $profiles
    foreach ($profile in $availability.profiles) {
        Add-WorkbenchNewLaunchCheck -Name ('llm/' + $profile.name) -Status passed -Detail "$($profile.model)/$($profile.reasoningEffort); CLI $($availability.version)"
    }
    $phase = 'workspace-readiness'
    $phaseDetail = 'Launch refused: complete the explicitly selected native ingestion/analysis workflow and resolve the failed checks before opening the UI'
    if (-not $preflight.ready -or @($checks | Where-Object status -CEQ 'failed').Count -gt 0) { throw $phaseDetail }
    $launchContext['llmAssignments'] = @($preflight.llmAssignments)
    $launchContext.preflightOnly = $false
} catch {
    if ($null -ne $startupAudit) { Invoke-WorkbenchAuditTransition -Audit $startupAudit -Transition finish -Outcome failed }
    $detail = if ($_.Exception.Data.Contains('HostedCliSafe')) { $_.Exception.Message } else { $phaseDetail }
    Add-WorkbenchNewLaunchCheck -Name $phase -Status failed -Detail $detail
    Write-WorkbenchNewLaunchSummary -Status FAILED -FailureMessages @(
        'Workbench New was not started. Resolve the failed checks above and try again.'
        'No ingestion or inference was performed.'
    )
    Complete-ValidationTextOutput | Write-Host
    $global:LASTEXITCODE = 1
    exit 1
}

$start = [Diagnostics.ProcessStartInfo]::new()
$start.FileName = $node.Source
$start.UseShellExecute = $false
$start.CreateNoWindow = $true
$start.RedirectStandardInput = $true
$start.RedirectStandardOutput = $true
$start.RedirectStandardError = $true
$start.StandardOutputEncoding = [Text.UTF8Encoding]::new($false)
$start.StandardErrorEncoding = [Text.UTF8Encoding]::new($false)
$start.ArgumentList.Add($serverPath)
$process = [Diagnostics.Process]::new()
$process.StartInfo = $start
$started = $false
try {
    if (-not $process.Start()) { throw 'Workbench New could not start.' }
    $started = $true
    $diagnostics = $process.StandardError.ReadToEndAsync()
    $process.StandardInput.WriteLine(($launchContext | ConvertTo-Json -Compress))
    $process.StandardInput.Close()
    $readyLine = $process.StandardOutput.ReadLine()
    if ([string]::IsNullOrWhiteSpace($readyLine)) { throw 'Workbench New startup failed; check the selected database and port availability.' }
    $ready = $readyLine | ConvertFrom-Json -DateKind String
    if ($ready.kind -ceq 'failed') {
        foreach ($check in $ready.checks) { Add-WorkbenchNewLaunchCheck -Name $check.name -Status $check.status -Detail $check.detail }
        throw 'Final server readiness checks failed'
    }
    if ($ready.kind -cne 'ready' -or $ready.url -cne "http://127.0.0.1:$Port/") { throw 'Workbench New returned an invalid startup response.' }
    Add-WorkbenchNewLaunchCheck -Name 'server-ready' -Status passed -Detail 'Final readiness rechecked; loopback server is listening'
    Write-WorkbenchNewLaunchSummary -Status PASSED
    Write-Host ''
    Write-Host 'WORKBENCH NEW - NATIVE SQL'
    Write-Host "URL: $($ready.url)"
    Write-Host 'Database: current repository workspace (SQL; explicit saves only)'
    Write-Host 'Press Ctrl+C to stop Workbench New.'
    if (-not $NoLaunch) { Start-Process $ready.url }
    Invoke-WorkbenchAuditTransition -Audit $startupAudit -Transition finish -Outcome succeeded -Facts @{ requestedPort = $Port; listenerPort = $Port }
    if (-not $process.HasExited) { Wait-Process -InputObject $process }
    $global:LASTEXITCODE = $process.ExitCode
} catch {
    if ($null -ne $startupAudit.Context.activeActionCode) { Invoke-WorkbenchAuditTransition -Audit $startupAudit -Transition finish -Outcome failed }
    Add-WorkbenchNewLaunchCheck -Name 'server-ready' -Status failed -Detail 'Server readiness, loopback port, or browser launch failed; no alternate port or workspace was selected'
    Write-WorkbenchNewLaunchSummary -Status FAILED -FailureMessages @(
        'Workbench New could not start. Resolve the failed checks above and try again.'
        'No ingestion or inference was performed.'
    )
    $global:LASTEXITCODE = 1
    exit 1
} finally {
    if ($started -and -not $process.HasExited) { $process.Kill($true); $process.WaitForExit() }
    $process.Dispose()
    Complete-ValidationTextOutput | Write-Host
}
