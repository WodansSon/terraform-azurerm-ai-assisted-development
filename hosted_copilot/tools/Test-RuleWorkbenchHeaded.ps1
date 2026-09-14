[CmdletBinding()]
param(
    [uri]$Url,

    [ValidateRange(1024, 65535)]
    [int]$Port = 43143,

    [Alias('TestCase')]
    [ValidatePattern('^[a-z0-9-]+$')]
    [string]$Journey = 'all',

    [ValidateRange(0, 2000)]
    [int]$SlowMo = 250,

    [ValidateRange(1000, 5000)]
    [int]$TransitionDelay = 1000
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ($Url -and ($Url.Scheme -ne 'http' -or $Url.Host -notin @('127.0.0.1', 'localhost'))) {
    throw 'Url must use HTTP and target the local Workbench at `127.0.0.1` or `localhost`'
}
if ($Url -and $PSBoundParameters.ContainsKey('Port')) {
    throw 'Specify either `Url` to attach to an existing Workbench or `Port` to start an owned Workbench, not both'
}

$runnerPath = Join-Path $PSScriptRoot '../regression/workbench/playwright/run.cjs'
$manifestPath = Join-Path $PSScriptRoot '../regression/workbench/behavior-manifest.json'
$launcherPath = Join-Path $PSScriptRoot 'Start-RuleWorkbench.ps1'
$playwrightPackagePath = Join-Path $PSScriptRoot 'node_modules/@playwright/test/package.json'
$puppeteerPackagePath = Join-Path $PSScriptRoot 'node_modules/puppeteer/package.json'

foreach ($requiredPath in @($runnerPath, $manifestPath, $launcherPath)) {
    if (-not (Test-Path -LiteralPath $requiredPath -PathType Leaf)) {
        throw "Required Workbench playback file is missing: $requiredPath"
    }
}

if (-not (Test-Path -LiteralPath $playwrightPackagePath -PathType Leaf) -or -not (Test-Path -LiteralPath $puppeteerPackagePath -PathType Leaf)) {
    $npmCommandName = if ($IsWindows) { 'npm.cmd' } else { 'npm' }
    $npmCommand = Get-Command $npmCommandName -ErrorAction Stop
    Write-Host 'Installing integrity-locked browser dependencies...'
    & $npmCommand.Source ci --prefix $PSScriptRoot --no-audit --no-fund
    if ($LASTEXITCODE -ne 0) {
        throw 'Integrity-locked browser dependencies could not be installed'
    }
}

if ($Journey -ne 'all') {
    $manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
    $journeyNames = @($manifest.behaviors | ForEach-Object { [IO.Path]::GetFileNameWithoutExtension(([IO.Path]::GetFileNameWithoutExtension([string]$_.journey))) } | Sort-Object -Unique)
    if ($Journey -notin $journeyNames) {
        throw "Journey must be one of: all, $($journeyNames -join ', ')"
    }
}

function Test-PortInUse {
    param([Parameter(Mandatory = $true)][int]$TargetPort)

    $client = [Net.Sockets.TcpClient]::new()
    try {
        return $client.ConnectAsync([Net.IPAddress]::Loopback, $TargetPort).Wait(250) -and $client.Connected
    }
    catch {
        return $false
    }
    finally {
        $client.Dispose()
    }
}

function Assert-WorkbenchIdentity {
    param([Parameter(Mandatory = $true)][uri]$TargetUrl)

    $originBuilder = [UriBuilder]::new($TargetUrl)
    $originBuilder.Path = '/'
    $originBuilder.Query = ''
    $originBuilder.Fragment = ''
    $origin = $originBuilder.Uri
    $bundleUri = [uri]::new($origin, 'rule-intake-review.json')

    try {
        $pageResponse = Invoke-WebRequest -Uri $origin.AbsoluteUri -Method Get -TimeoutSec 5 -SkipHttpErrorCheck
        $bundleResponse = Invoke-WebRequest -Uri $bundleUri.AbsoluteUri -Method Get -TimeoutSec 5 -SkipHttpErrorCheck
    }
    catch {
        throw "Workbench port $($TargetUrl.Port) is not available at $($origin.AbsoluteUri)"
    }

    $pageIdentityValid = $pageResponse.StatusCode -eq 200 -and $pageResponse.Content -match '<title>Hosted Copilot Rule Manager</title>' -and $pageResponse.Content -match '<script src="app\.js" defer></script>'
    $bundleIdentityValid = $false
    if ($bundleResponse.StatusCode -eq 200) {
        try {
            $bundle = $bundleResponse.Content | ConvertFrom-Json
            $bundleIdentityValid = $bundle.'$schema' -eq 'rule-intake-review.schema.json' -and $bundle.readOnly -eq $true
        }
        catch { }
    }

    if (-not $pageIdentityValid -or -not $bundleIdentityValid) {
        throw "Port $($TargetUrl.Port) is in use but does not serve a Hosted Copilot Rule Workbench"
    }
}

$ownedServer = -not $Url
$serverJob = $null
$serverProcessId = $null
$siteDirectory = $null
$resultPath = Join-Path ([IO.Path]::GetTempPath()) ("hosted-rule-workbench-headed-result-" + [guid]::NewGuid().ToString('N') + '.json')
$playbackFailure = $null
$cleanupFailure = $null
if ($ownedServer) {
    if (Test-PortInUse -TargetPort $Port) {
        throw "Port $Port is already in use; choose an available port"
    }
    $Url = [uri]"http://127.0.0.1:$Port/"
    $siteDirectory = Join-Path ([IO.Path]::GetTempPath()) ("hosted-rule-workbench-headed-" + [guid]::NewGuid().ToString('N'))
    $serverJob = Start-Job -ScriptBlock {
        param($WorkbenchLauncherPath, $WorkbenchSiteDirectory, $WorkbenchPort, $WorkbenchOwnerProcessId)
        & $WorkbenchLauncherPath -SiteDirectory $WorkbenchSiteDirectory -Port $WorkbenchPort -OwnerProcessId $WorkbenchOwnerProcessId -NoLaunch
    } -ArgumentList $launcherPath, $siteDirectory, $Port, $PID

    $deadline = [DateTimeOffset]::UtcNow.AddMinutes(5)
    while (-not (Test-PortInUse -TargetPort $Port) -and [DateTimeOffset]::UtcNow -lt $deadline) {
        if ($serverJob.State -in @('Failed', 'Completed', 'Stopped')) {
            $serverOutput = (Receive-Job -Job $serverJob | Out-String).Trim()
            throw "Owned Workbench failed to start: $serverOutput"
        }
    }
    if (-not (Test-PortInUse -TargetPort $Port)) {
        throw "Owned Workbench did not start on port $Port"
    }
    $serverProcessId = (Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction Stop | Select-Object -First 1).OwningProcess
}

try {
    Assert-WorkbenchIdentity -TargetUrl $Url

    $nodeExecutable = (Get-Command node -ErrorAction Stop).Source
    $runnerArguments = @($runnerPath, $Url.AbsoluteUri, '--headed', '--slow-mo', [string]$SlowMo, '--transition-delay', [string]$TransitionDelay, '--result-file', $resultPath)
    if ($Journey -ne 'all') {
        $runnerArguments += @('--journey', $Journey)
    }
    if ($ownedServer) {
        $runnerArguments += '--shutdown-at-end'
    }

    $journeyLabel = if ($Journey -eq 'all') { 'all journeys' } else { $Journey }
    Write-Host "Playing $journeyLabel at $($Url.AbsoluteUri) with ${SlowMo}ms action delay and ${TransitionDelay}ms transition delay..."
    & $nodeExecutable @runnerArguments
    if ($LASTEXITCODE -ne 0) {
        throw 'Visible Playwright playback failed; see the streamed error above'
    }

    if (-not (Test-Path -LiteralPath $resultPath -PathType Leaf)) {
        throw 'Visible Playwright playback did not produce its result file'
    }
    $result = Get-Content -LiteralPath $resultPath -Raw | ConvertFrom-Json
    if ($ownedServer -and -not $result.shutdownVerified) {
        throw 'Visible Playwright playback did not verify Close Workbench'
    }
    if ($ownedServer) {
        $null = Wait-Job -Job $serverJob -Timeout 10
        if ($serverJob.State -ne 'Completed' -or (Test-PortInUse -TargetPort $Port)) {
            throw "Close Workbench did not stop the owned server on port $Port"
        }
    }
    Write-Host "Passed $($result.assertionCount) assertions across $($result.journeyCount) visible Playwright journey(s) covering $($result.behaviorCount) behavior ID(s)."
}
catch {
    $playbackFailure = $_
}
finally {
    try {
        if ($ownedServer -and $serverProcessId) {
            $serverProcess = Get-Process -Id $serverProcessId -ErrorAction SilentlyContinue
            if ($serverProcess) {
                Stop-Process -Id $serverProcessId -Force -ErrorAction Stop
                Wait-Process -Id $serverProcessId -Timeout 5 -ErrorAction SilentlyContinue
            }
        }
        if ($serverJob) {
            if ($serverJob.State -notin @('Completed', 'Failed', 'Stopped')) {
                Stop-Job -Job $serverJob -ErrorAction Stop
            }
            Remove-Job -Job $serverJob -Force -ErrorAction Stop
        }
        if ($ownedServer) {
            $deadline = [DateTimeOffset]::UtcNow.AddSeconds(5)
            while ((Test-PortInUse -TargetPort $Port) -and [DateTimeOffset]::UtcNow -lt $deadline) { }
            if (Test-PortInUse -TargetPort $Port) {
                throw "Owned Workbench port $Port remains open after cleanup"
            }
        }
        if ($siteDirectory -and (Test-Path -LiteralPath $siteDirectory)) {
            Remove-Item -LiteralPath $siteDirectory -Recurse -Force -ErrorAction Stop
        }
        if (Test-Path -LiteralPath $resultPath) {
            Remove-Item -LiteralPath $resultPath -Force -ErrorAction Stop
        }
    }
    catch {
        $cleanupFailure = $_
    }
}

if ($playbackFailure) {
    if ($cleanupFailure) {
        Write-Error -ErrorRecord $cleanupFailure -ErrorAction Continue
    }
    throw $playbackFailure
}
if ($cleanupFailure) {
    throw $cleanupFailure
}
