[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$SiteDirectory,
    [Parameter(Mandatory = $true)][ValidateRange(1024, 65535)][int]$Port,
    [Parameter(Mandatory = $true)][string]$ShutdownToken,
    [Parameter(Mandatory = $true)][string]$OperationToken,
    [Parameter(Mandatory = $true)][string]$RepositoryRoot,
    [Parameter(Mandatory = $true)][string]$ManualRelationshipPath,
    [Parameter(Mandatory = $true)][string]$ManualRelationshipCacheDirectory,
    [string]$EvaluatorCommand = 'copilot',
    [string]$Model = 'gpt-5.4',
    [ValidateSet('low', 'medium', 'high', 'xhigh')][string]$ReasoningEffort = 'high',
    [string]$RelationshipEvaluatorScriptPath,
    [ValidateRange(1, 2147483647)][int]$OwnerProcessId,
    [switch]$NoLaunch
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$resolvedSiteDirectory = [IO.Path]::GetFullPath($SiteDirectory)
$url = "http://127.0.0.1:$Port/"

function Write-HttpResponse {
    param(
        [Parameter(Mandatory = $true)][IO.Stream]$Stream,
        [Parameter(Mandatory = $true)][int]$StatusCode,
        [Parameter(Mandatory = $true)][string]$StatusText,
        [Parameter(Mandatory = $true)][string]$ContentType,
        [Parameter(Mandatory = $true)][byte[]]$Body,
        [Parameter(Mandatory = $true)][bool]$IncludeBody
    )

    $headers = @(
        "HTTP/1.1 $StatusCode $StatusText",
        "Content-Type: $ContentType",
        "Content-Length: $($Body.Length)",
        'Cache-Control: no-store',
        "Content-Security-Policy: default-src 'self'; script-src 'self'; style-src 'self'; font-src 'self'; connect-src 'self'; img-src 'self' data:; object-src 'none'; base-uri 'none'; frame-ancestors 'none'",
        'X-Content-Type-Options: nosniff',
        'Referrer-Policy: no-referrer',
        'Connection: close',
        '',
        ''
    ) -join "`r`n"
    $headerBytes = [Text.Encoding]::ASCII.GetBytes($headers)
    $Stream.Write($headerBytes, 0, $headerBytes.Length)
    if ($IncludeBody -and $Body.Length -gt 0) {
        $Stream.Write($Body, 0, $Body.Length)
    }
    $Stream.Flush()
}

function Test-RequestToken {
    param(
        [AllowNull()][string]$Candidate,
        [Parameter(Mandatory = $true)][string]$Expected
    )

    if ([string]::IsNullOrWhiteSpace($Candidate) -or $Candidate.Length -ne $Expected.Length) {
        return $false
    }
    $candidateBytes = [Text.Encoding]::ASCII.GetBytes($Candidate)
    $expectedBytes = [Text.Encoding]::ASCII.GetBytes($Expected)
    return [Security.Cryptography.CryptographicOperations]::FixedTimeEquals($candidateBytes, $expectedBytes)
}

function Read-HttpRequestBody {
    param(
        [Parameter(Mandatory = $true)][IO.StreamReader]$Reader,
        [Parameter(Mandatory = $true)][hashtable]$Headers,
        [ValidateRange(1, 1048576)][int]$MaximumBytes = 131072
    )

    $contentLengthValue = [string]$Headers['Content-Length']
    $contentLength = 0
    if (-not [int]::TryParse($contentLengthValue, [ref]$contentLength) -or $contentLength -lt 1 -or $contentLength -gt $MaximumBytes) {
        throw 'Request body length is invalid'
    }
    $buffer = New-Object char[] $contentLength
    $offset = 0
    while ($offset -lt $contentLength) {
        $read = $Reader.ReadBlock($buffer, $offset, $contentLength - $offset)
        if ($read -le 0) {
            throw 'Request body ended before Content-Length bytes were read'
        }
        $offset += $read
    }
    return -join $buffer
}

$listener = [Net.Sockets.TcpListener]::new([Net.IPAddress]::Loopback, $Port)
$allowedHosts = @("127.0.0.1:$Port", "localhost:$Port")
try {
    $listener.Start()
    if (-not $NoLaunch) {
        Start-Process $url
    }

    $shutdownRequested = $false
    while (-not $shutdownRequested) {
        if ($OwnerProcessId -and -not (Get-Process -Id $OwnerProcessId -ErrorAction SilentlyContinue)) {
            break
        }
        $acceptTask = $listener.AcceptTcpClientAsync()
        while (-not $acceptTask.Wait(250)) {
            if ($OwnerProcessId -and -not (Get-Process -Id $OwnerProcessId -ErrorAction SilentlyContinue)) {
                $shutdownRequested = $true
                break
            }
        }
        if ($shutdownRequested) {
            break
        }
        $client = $acceptTask.GetAwaiter().GetResult()
        $stream = $null
        try {
            $stream = $client.GetStream()
            $reader = [IO.StreamReader]::new($stream, [Text.Encoding]::UTF8, $false, 1024, $true)
            $requestLine = $reader.ReadLine()
            if ([string]::IsNullOrWhiteSpace($requestLine)) {
                continue
            }
            $requestHeaders = @{}
            while ($true) {
                $headerLine = $reader.ReadLine()
                if ([string]::IsNullOrEmpty($headerLine)) {
                    break
                }
                if ($headerLine -match '^(?<name>[^:]+):\s*(?<value>.*)$') {
                    $requestHeaders[[string]$Matches['name']] = [string]$Matches['value']
                }
            }

            if ($requestLine -notmatch '^(?<method>[A-Z]+) (?<target>\S+) HTTP/1\.[01]$') {
                Write-HttpResponse -Stream $stream -StatusCode 400 -StatusText 'Bad Request' -ContentType 'text/plain; charset=utf-8' -Body ([Text.Encoding]::UTF8.GetBytes('Bad Request')) -IncludeBody $true
                continue
            }

            $method = [string]$Matches['method']
            $requestUri = [Uri]("http://127.0.0.1$($Matches['target'])")
            $requestHost = [string]$requestHeaders['Host']
            if ([string]::IsNullOrWhiteSpace($requestHost) -or $requestHost.Trim() -notin $allowedHosts) {
                Write-HttpResponse -Stream $stream -StatusCode 421 -StatusText 'Misdirected Request' -ContentType 'text/plain; charset=utf-8' -Body ([Text.Encoding]::UTF8.GetBytes('Misdirected Request')) -IncludeBody $true
                continue
            }
            if ($method -eq 'POST' -and $requestUri.AbsolutePath -eq '/shutdown') {
                $providedToken = [string]$requestHeaders['X-Workbench-Shutdown-Token']
                if (-not (Test-RequestToken -Candidate $providedToken -Expected $ShutdownToken)) {
                    Write-HttpResponse -Stream $stream -StatusCode 403 -StatusText 'Forbidden' -ContentType 'text/plain; charset=utf-8' -Body ([Text.Encoding]::UTF8.GetBytes('Forbidden')) -IncludeBody $true
                    continue
                }
                Write-HttpResponse -Stream $stream -StatusCode 200 -StatusText 'OK' -ContentType 'application/json; charset=utf-8' -Body ([Text.Encoding]::UTF8.GetBytes('{"status":"shutting-down"}')) -IncludeBody $true
                $shutdownRequested = $true
                continue
            }

            if ($method -eq 'POST' -and $requestUri.AbsolutePath -eq '/reconcile-rule') {
                $providedToken = [string]$requestHeaders['X-Workbench-Operation-Token']
                if (-not (Test-RequestToken -Candidate $providedToken -Expected $OperationToken)) {
                    Write-HttpResponse -Stream $stream -StatusCode 403 -StatusText 'Forbidden' -ContentType 'text/plain; charset=utf-8' -Body ([Text.Encoding]::UTF8.GetBytes('Forbidden')) -IncludeBody $true
                    continue
                }
                $requestPath = Join-Path ([IO.Path]::GetTempPath()) "hosted-rule-request-$([Guid]::NewGuid().ToString('N')).json"
                $outputPath = Join-Path ([IO.Path]::GetTempPath()) "hosted-rule-result-$([Guid]::NewGuid().ToString('N')).json"
                try {
                    $requestBody = Read-HttpRequestBody -Reader $reader -Headers $requestHeaders
                    $requestEnvelope = $requestBody | ConvertFrom-Json
                    if (Compare-Object -ReferenceObject @('payloadBase64') -DifferenceObject @($requestEnvelope.PSObject.Properties.Name)) {
                        throw 'Request envelope has an unexpected property set'
                    }
                    $requestBytes = [Convert]::FromBase64String([string]$requestEnvelope.payloadBase64)
                    if ($requestBytes.Length -lt 1 -or $requestBytes.Length -gt 65536) {
                        throw 'Decoded request payload length is invalid'
                    }
                    $null = [Text.UTF8Encoding]::new($false, $true).GetString($requestBytes)
                    [IO.File]::WriteAllBytes($requestPath, $requestBytes)
                    $relationshipParameters = @{
                        RequestPath = $requestPath
                        OutputPath = $outputPath
                        RepositoryRoot = $RepositoryRoot
                        CacheDirectory = $ManualRelationshipCacheDirectory
                        EvaluatorCommand = $EvaluatorCommand
                        Model = $Model
                        ReasoningEffort = $ReasoningEffort
                    }
                    if (-not [string]::IsNullOrWhiteSpace($RelationshipEvaluatorScriptPath)) {
                        $relationshipParameters.EvaluatorScriptPath = $RelationshipEvaluatorScriptPath
                    }
                    $relationshipOutput = @(& pwsh -NoProfile -File $ManualRelationshipPath @relationshipParameters 2>&1)
                    if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $outputPath -PathType Leaf)) {
                        throw "Scoped relationship evaluator failed: $(($relationshipOutput | Out-String).Trim())"
                    }
                    Write-HttpResponse -Stream $stream -StatusCode 200 -StatusText 'OK' -ContentType 'application/json; charset=utf-8' -Body ([IO.File]::ReadAllBytes($outputPath)) -IncludeBody $true
                }
                catch {
                    Write-Warning "Scoped relationship check failed: $($_.Exception.Message)"
                    Write-HttpResponse -Stream $stream -StatusCode 500 -StatusText 'Internal Server Error' -ContentType 'application/json; charset=utf-8' -Body ([Text.Encoding]::UTF8.GetBytes('{"error":"Scoped relationship check failed"}')) -IncludeBody $true
                }
                finally {
                    Remove-Item -LiteralPath $requestPath, $outputPath -Force -ErrorAction SilentlyContinue
                }
                continue
            }

            if ($method -notin @('GET', 'HEAD')) {
                Write-HttpResponse -Stream $stream -StatusCode 405 -StatusText 'Method Not Allowed' -ContentType 'text/plain; charset=utf-8' -Body ([Text.Encoding]::UTF8.GetBytes('Method Not Allowed')) -IncludeBody $true
                continue
            }

            $relativePath = [Uri]::UnescapeDataString($requestUri.AbsolutePath).TrimStart('/')
            if ([string]::IsNullOrWhiteSpace($relativePath)) {
                $relativePath = 'index.html'
            }
            $requestedPath = [IO.Path]::GetFullPath((Join-Path $resolvedSiteDirectory $relativePath.Replace('/', [IO.Path]::DirectorySeparatorChar)))
            $sitePrefix = $resolvedSiteDirectory.TrimEnd([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar) + [IO.Path]::DirectorySeparatorChar
            if (-not $requestedPath.StartsWith($sitePrefix, [StringComparison]::OrdinalIgnoreCase) -or -not (Test-Path -LiteralPath $requestedPath -PathType Leaf)) {
                Write-HttpResponse -Stream $stream -StatusCode 404 -StatusText 'Not Found' -ContentType 'text/plain; charset=utf-8' -Body ([Text.Encoding]::UTF8.GetBytes('Not Found')) -IncludeBody ($method -eq 'GET')
                continue
            }

            $contentType = switch ([IO.Path]::GetExtension($requestedPath).ToLowerInvariant()) {
                '.html' { 'text/html; charset=utf-8' }
                '.js' { 'text/javascript; charset=utf-8' }
                '.css' { 'text/css; charset=utf-8' }
                '.svg' { 'image/svg+xml' }
                '.json' { 'application/json; charset=utf-8' }
                default { 'application/octet-stream' }
            }
            $body = [IO.File]::ReadAllBytes($requestedPath)
            Write-HttpResponse -Stream $stream -StatusCode 200 -StatusText 'OK' -ContentType $contentType -Body $body -IncludeBody ($method -eq 'GET')
        }
        catch {
            if ($null -ne $stream -and $stream.CanWrite) {
                try {
                    Write-HttpResponse -Stream $stream -StatusCode 500 -StatusText 'Internal Server Error' -ContentType 'text/plain; charset=utf-8' -Body ([Text.Encoding]::UTF8.GetBytes('Internal Server Error')) -IncludeBody $true
                }
                catch { }
            }
        }
        finally {
            $client.Dispose()
        }
    }
}
finally {
    $listener.Stop()
}
