Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Resolve-HostedCliLaunch {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$EvaluatorCommand)

    $command = Get-Command $EvaluatorCommand -ErrorAction SilentlyContinue
    while ($null -ne $command -and $command.CommandType -eq [Management.Automation.CommandTypes]::Alias) { $command = $command.ResolvedCommand }
    if ($null -eq $command -or $command.CommandType -notin @([Management.Automation.CommandTypes]::Application, [Management.Automation.CommandTypes]::ExternalScript)) {
        throw 'Copilot CLI could not be resolved to an executable or script; supply its explicit path with -EvaluatorCommand'
    }
    $path = [IO.Path]::GetFullPath($command.Source)
    $item = Get-Item -LiteralPath $path
    $target = $item.ResolveLinkTarget($true)
    if ($null -ne $target) { $path = $target.FullName; $item = Get-Item -LiteralPath $path }
    $directory = Split-Path -Parent $path
    $extension = [IO.Path]::GetExtension($path).ToLowerInvariant()
    $loaderPath = $null
    if ($extension -eq '.ps1') {
        $tokens = $null
        $parseErrors = $null
        $ast = [Management.Automation.Language.Parser]::ParseFile($path, [ref]$tokens, [ref]$parseErrors)
        if ($parseErrors.Count -gt 0) { throw 'Copilot CLI PowerShell launcher cannot be parsed; supply a valid executable path with -EvaluatorCommand' }
        $strings = @($ast.FindAll({ param($node) $node -is [Management.Automation.Language.StringConstantExpressionAst] -or $node -is [Management.Automation.Language.ExpandableStringExpressionAst] }, $true))
        foreach ($value in $strings.Value) {
            if ($value -match '^\$basedir[/\\](?<relative>node_modules[/\\]@github[/\\]copilot[/\\][^/\\]+\.js)$') {
                $loaderPath = Join-Path $directory $Matches.relative
                break
            }
        }
    }
    elseif ($extension -in @('.cmd', '.bat') -or ($extension -eq '' -and $item.Length -lt 65536)) {
        $text = Get-Content -LiteralPath $path -Raw
        if ($text -match '(?:%dp0%|\$basedir)[/\\](?<relative>node_modules[/\\]@github[/\\]copilot[/\\][^"\s]+\.js)') {
            $loaderPath = Join-Path $directory $Matches.relative
        }
    }
    elseif ($extension -eq '.js') { $loaderPath = $path }

    if ($null -ne $loaderPath) {
        $loaderPath = [IO.Path]::GetFullPath($loaderPath)
        $packagePath = Join-Path (Split-Path -Parent $loaderPath) 'package.json'
        if (-not (Test-Path -LiteralPath $packagePath -PathType Leaf)) { throw 'Copilot npm launcher package metadata is missing; reinstall the CLI or supply its executable path with -EvaluatorCommand' }
        $package = Get-Content -LiteralPath $packagePath -Raw | ConvertFrom-Json -DateKind String
        $bin = if ($package.bin -is [string]) { [string]$package.bin } else { [string]$package.bin.copilot }
        if ($package.name -cne '@github/copilot' -or [IO.Path]::GetFullPath((Join-Path (Split-Path -Parent $packagePath) $bin)) -cne $loaderPath) {
            throw 'Copilot npm launcher does not match its package metadata; supply its executable path with -EvaluatorCommand'
        }
        $localNode = Join-Path $directory $(if ($IsWindows) { 'node.exe' } else { 'node' })
        $node = if (Test-Path -LiteralPath $localNode -PathType Leaf) { $localNode } else { (Get-Command node -CommandType Application -ErrorAction Stop | Select-Object -First 1).Source }
        $resolver = [Diagnostics.ProcessStartInfo]::new($node)
        $resolver.UseShellExecute = $false
        $resolver.CreateNoWindow = $true
        $resolver.RedirectStandardOutput = $true
        $resolver.RedirectStandardError = $true
        foreach ($argument in @('--input-type=module', '--eval', "import { createRequire } from 'node:module'; const require = createRequire(process.argv[1]); console.log(require.resolve('@github/copilot-' + process.platform + '-' + process.arch));", $loaderPath)) { $resolver.ArgumentList.Add($argument) }
        $process = [Diagnostics.Process]::new()
        $process.StartInfo = $resolver
        $started = $false
        try {
            $started = $process.Start()
            if (-not $started) { throw 'Copilot npm runtime resolver could not start' }
            $stdout = $process.StandardOutput.ReadToEndAsync()
            $stderr = $process.StandardError.ReadToEndAsync()
            if (-not $process.WaitForExit(10000)) { throw 'Copilot npm runtime resolution timed out' }
            $output = $stdout.GetAwaiter().GetResult()
            $null = $stderr.GetAwaiter().GetResult()
            if ($process.ExitCode -ne 0 -or $output.Length -gt 32768 -or [string]::IsNullOrWhiteSpace($output) -or $output.Trim() -match '[\r\n]') {
                throw 'Copilot npm native runtime could not be resolved; reinstall the CLI or supply its executable path with -EvaluatorCommand'
            }
            $path = [IO.Path]::GetFullPath($output.Trim())
            if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw 'Resolved Copilot npm runtime does not exist' }
        }
        finally {
            if ($started -and -not $process.HasExited) { $process.Kill($true); $process.WaitForExit() }
            $process.Dispose()
        }
        return [pscustomobject]@{ commandPath = $path; fileName = $path; arguments = @(); kind = 'npm-native' }
    }
    if ($extension -eq '.ps1') {
        return [pscustomobject]@{
            commandPath = $path; fileName = [Diagnostics.Process]::GetCurrentProcess().MainModule.FileName
            arguments = @('-NoLogo', '-NoProfile', '-NonInteractive', '-File', $path); kind = 'powershell'
        }
    }
    if ($extension -in @('.cmd', '.bat', '.js')) { throw 'Unsupported Copilot CLI wrapper; supply the executable path with -EvaluatorCommand' }
    return [pscustomobject]@{ commandPath = $path; fileName = $path; arguments = @(); kind = 'executable' }
}

function New-HostedCliStartInfo {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object]$Launch,
        [Parameter(Mandatory)][string]$WorkingDirectory,
        [Parameter(Mandatory)][string[]]$Arguments,
        [bool]$RedirectStandardInput = $true
    )

    $start = [Diagnostics.ProcessStartInfo]::new($Launch.fileName)
    $start.WorkingDirectory = $WorkingDirectory
    $start.UseShellExecute = $false
    $start.CreateNoWindow = $true
    $start.RedirectStandardInput = $RedirectStandardInput
    $start.RedirectStandardOutput = $true
    $start.RedirectStandardError = $true
    if ($RedirectStandardInput) { $start.StandardInputEncoding = [Text.UTF8Encoding]::new($false) }
    $start.StandardOutputEncoding = [Text.UTF8Encoding]::new($false)
    $start.StandardErrorEncoding = [Text.UTF8Encoding]::new($false)
    foreach ($argument in @($Launch.arguments) + $Arguments) { $start.ArgumentList.Add($argument) }
    return $start
}

function Stop-HostedCliPreflight {
    param([string]$Message)

    $exception = [InvalidOperationException]::new($Message)
    $exception.Data['HostedCliSafe'] = $true
    throw $exception
}

function Read-HostedCliRpcMessage {
    param([IO.Stream]$Stream, [Threading.CancellationToken]$Cancellation)

    $header = [Text.StringBuilder]::new()
    $single = [byte[]]::new(1)
    while (-not $header.ToString().EndsWith("`r`n`r`n", [StringComparison]::Ordinal)) {
        if ($header.Length -ge 8192) { Stop-HostedCliPreflight 'Copilot CLI metadata header exceeded its size bound' }
        $count = $Stream.ReadAsync($single, 0, 1, $Cancellation).GetAwaiter().GetResult()
        if ($count -eq 0) { Stop-HostedCliPreflight 'Copilot CLI closed its metadata transport; verify the installed CLI supports headless stdio RPC' }
        [void]$header.Append([char]$single[0])
    }
    if ($header.ToString() -notmatch '(?im)^Content-Length:\s*(\d+)\s*$') { Stop-HostedCliPreflight 'Copilot CLI returned invalid metadata framing' }
    $length = [int]$Matches[1]
    if ($length -lt 2 -or $length -gt 4194304) { Stop-HostedCliPreflight 'Copilot CLI metadata body exceeded its size bound' }
    $bytes = [byte[]]::new($length)
    $offset = 0
    while ($offset -lt $length) {
        $count = $Stream.ReadAsync($bytes, $offset, $length - $offset, $Cancellation).GetAwaiter().GetResult()
        if ($count -eq 0) { Stop-HostedCliPreflight 'Copilot CLI returned an incomplete metadata response' }
        $offset += $count
    }
    return ([Text.UTF8Encoding]::new($false, $true).GetString($bytes) | ConvertFrom-Json -Depth 50 -DateKind String)
}

function Invoke-HostedCliMetadataRpc {
    param(
        [Diagnostics.Process]$Process,
        [int]$Identifier,
        [ValidateSet('status.get', 'auth.getStatus', 'models.list')][string]$Method,
        [Threading.CancellationToken]$Cancellation
    )

    $request = [ordered]@{ jsonrpc = '2.0'; id = $Identifier; method = $Method; params = @{} } | ConvertTo-Json -Compress
    $bytes = [Text.UTF8Encoding]::new($false).GetBytes($request)
    $header = [Text.Encoding]::ASCII.GetBytes("Content-Length: $($bytes.Length)`r`n`r`n")
    $Process.StandardInput.BaseStream.Write($header, 0, $header.Length)
    $Process.StandardInput.BaseStream.Write($bytes, 0, $bytes.Length)
    $Process.StandardInput.BaseStream.Flush()
    for ($messageCount = 0; $messageCount -lt 100; $messageCount++) {
        $message = Read-HostedCliRpcMessage -Stream $Process.StandardOutput.BaseStream -Cancellation $Cancellation
        if ($null -eq $message -or $message.jsonrpc -cne '2.0') { Stop-HostedCliPreflight 'Copilot CLI returned an invalid metadata envelope' }
        if ($null -eq $message.PSObject.Properties['id']) { continue }
        if ([string]$message.id -cne [string]$Identifier) { Stop-HostedCliPreflight 'Copilot CLI metadata transport requested an unsupported client interaction; no handler was executed' }
        if ($null -ne $message.PSObject.Properties['error']) {
            $code = [int]$message.error.code
            Stop-HostedCliPreflight "Copilot CLI metadata query failed during $Method (RPC code $code); verify CLI compatibility, account access, and network connectivity"
        }
        if ($null -eq $message.PSObject.Properties['result']) { Stop-HostedCliPreflight 'Copilot CLI metadata response omitted its result' }
        return $message.result
    }
    Stop-HostedCliPreflight 'Copilot CLI metadata response exceeded its message bound'
}

function Get-HostedCliAvailability {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][object]$Launch,
        [Parameter(Mandatory)][Collections.IDictionary]$Profiles,
        [ValidateRange(1, 120)][int]$TimeoutSeconds = 45
    )

    $directory = Join-Path ([IO.Path]::GetTempPath()) ('hosted-cli-preflight-' + [guid]::NewGuid().ToString('N'))
    $null = New-Item -ItemType Directory -Path $directory
    $process = [Diagnostics.Process]::new()
    $process.StartInfo = New-HostedCliStartInfo -Launch $Launch -WorkingDirectory $directory -Arguments @(
        '--headless', '--stdio', '--no-auto-update', '--no-custom-instructions', '--disable-builtin-mcps',
        '--no-remote-export', '--disable-client-telemetry', '--log-level', 'none', '--log-dir', (Join-Path $directory 'logs')
    )
    $deadline = [Threading.CancellationTokenSource]::new([TimeSpan]::FromSeconds($TimeoutSeconds))
    $started = $false
    $stderr = $null
    try {
        $started = $process.Start()
        if (-not $started) { Stop-HostedCliPreflight 'Copilot CLI metadata process could not start' }
        $stderr = $process.StandardError.BaseStream.CopyToAsync([IO.Stream]::Null)
        $status = Invoke-HostedCliMetadataRpc -Process $process -Identifier 1 -Method status.get -Cancellation $deadline.Token
        if ($status.version -isnot [string] -or $status.version -notmatch '^\d+\.\d+\.\d+(?:[-+][A-Za-z0-9.-]+)?$' -or $status.protocolVersion -ne 3) {
            Stop-HostedCliPreflight 'Copilot CLI does not report a supported version and metadata protocol; this precheck requires protocol 3'
        }
        $auth = Invoke-HostedCliMetadataRpc -Process $process -Identifier 2 -Method auth.getStatus -Cancellation $deadline.Token
        if ($auth.isAuthenticated -isnot [bool]) { Stop-HostedCliPreflight 'Copilot CLI authentication status could not be verified' }
        if (-not $auth.isAuthenticated) { Stop-HostedCliPreflight 'Copilot CLI is not authenticated; sign in with the configured CLI before starting the Workbench' }
        $catalog = Invoke-HostedCliMetadataRpc -Process $process -Identifier 3 -Method models.list -Cancellation $deadline.Token
        if ($catalog.models -isnot [array] -or $catalog.models.Count -gt 2048) { Stop-HostedCliPreflight 'Copilot CLI returned an invalid or oversized model catalog' }
        $resolvedProfiles = [Collections.Generic.List[object]]::new()
        foreach ($name in $Profiles.Keys) {
            $profile = $Profiles[$name]
            $entries = @($catalog.models | Where-Object { $null -ne $_.PSObject.Properties['id'] -and $_.id -ceq $profile.model })
            if ($entries.Count -eq 0) {
                Stop-HostedCliPreflight "Copilot CLI model '$($profile.model)' is unavailable for profile '$name'; update hosted_copilot/tools/llm.json or the explicit CLI override"
            }
            if ($entries.Count -ne 1) { Stop-HostedCliPreflight "Copilot CLI returned duplicate model metadata for profile '$name'" }
            $entry = $entries[0]
            if ($null -eq $entry.PSObject.Properties['policy'] -or $null -eq $entry.policy -or $null -eq $entry.policy.PSObject.Properties['state']) {
                Stop-HostedCliPreflight "Copilot CLI model policy is missing for profile '$name'; availability could not be verified"
            }
            if ($entry.policy.state -ceq 'disabled') { Stop-HostedCliPreflight "Copilot CLI model '$($profile.model)' is disabled for profile '$name'; check account policy or select an enabled model" }
            if ($entry.policy.state -cne 'enabled') { Stop-HostedCliPreflight "Copilot CLI model policy is not enabled for profile '$name'; availability could not be verified" }
            if ($entry.capabilities.supports.reasoningEffort -isnot [bool] -or -not $entry.capabilities.supports.reasoningEffort -or
                $entry.supportedReasoningEfforts -isnot [array] -or $profile.reasoningEffort -cnotin $entry.supportedReasoningEfforts) {
                Stop-HostedCliPreflight "Copilot CLI reasoning effort '$($profile.reasoningEffort)' is unsupported for model '$($profile.model)' in profile '$name'; update hosted_copilot/tools/llm.json or the explicit CLI override"
            }
            $resolvedProfiles.Add([ordered]@{ name = [string]$name; model = [string]$profile.model; reasoningEffort = [string]$profile.reasoningEffort })
        }
        return [pscustomobject]@{ version = [string]$status.version; protocolVersion = 3; commandPath = $Launch.commandPath; profiles = $resolvedProfiles.ToArray() }
    }
    catch {
        if ($_.Exception.Data.Contains('HostedCliSafe')) { throw }
        if ($deadline.IsCancellationRequested) { Stop-HostedCliPreflight 'Copilot CLI metadata precheck timed out; check CLI compatibility and connectivity; no model availability conclusion was accepted' }
        Stop-HostedCliPreflight 'Copilot CLI metadata transport failed; check the configured executable, authentication, network, and protocol compatibility; raw diagnostics were not exposed'
    }
    finally {
        if ($started) {
            try { $process.StandardInput.Close() } catch {}
            if (-not $process.WaitForExit(5000)) { $process.Kill($true); $process.WaitForExit() }
            if ($null -ne $stderr) { try { $null = $stderr.Wait(1000) } catch {} }
        }
        $deadline.Dispose()
        $process.Dispose()
        Remove-Item -LiteralPath $directory -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Export-ModuleMember -Function Resolve-HostedCliLaunch, New-HostedCliStartInfo, Get-HostedCliAvailability
