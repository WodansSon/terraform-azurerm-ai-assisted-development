[CmdletBinding()]
param(
    [ValidateRange(1024, 65535)]
    [int]$Port = 43143,

    [string]$SiteDirectory = (Join-Path ([IO.Path]::GetTempPath()) 'hosted-rule-workbench/site'),

    [string]$BundlePath,

    [string]$AssessmentCachePath = (Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'terraform-azurerm-ai-assisted-development/hosted-rule-intake/assessment-cache.json'),

    [string]$AssessmentBaselinePath = (Join-Path $PSScriptRoot '../copilot-rule-catalog/rule-assessments/assessment-baseline.json'),

    [string]$AssessmentModel = 'gpt-5.4',

    [ValidateSet('low', 'medium', 'high', 'xhigh')]
    [string]$AssessmentReasoningEffort = 'high',

    [ValidateRange(1, 50)]
    [int]$AssessmentBatchSize = 20,

    [ValidateRange(1, 20)]
    [int]$UpstreamAssessmentBatchSize = 5,

    [ValidateRange(0, 3)]
    [int]$AssessmentMaxRetries = 1,

    [string]$EvaluatorCommand = 'copilot',

    [switch]$ForceAssessment,

    [switch]$StageOnly,

    [switch]$NoLaunch,

    [ValidateSet('Text', 'Json')]
    [string]$OutputFormat = 'Text'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$validationOutputModulePath = Join-Path $PSScriptRoot '../../tools/ValidationOutput.psm1'
Import-Module -Name $validationOutputModulePath -Force

$repositoryRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
$workbenchSource = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../workbench'))
$assessmentPath = Join-Path $PSScriptRoot 'Invoke-RuleIntakeAssessment.ps1'
$bundleSchemaPath = Join-Path $PSScriptRoot '../copilot-rule-catalog/rule-intake-review.schema.json'
$resolvedSiteDirectory = [IO.Path]::GetFullPath($SiteDirectory)
$repositoryPrefix = $repositoryRoot.TrimEnd([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar) + [IO.Path]::DirectorySeparatorChar
if ($resolvedSiteDirectory.StartsWith($repositoryPrefix, [StringComparison]::OrdinalIgnoreCase)) {
    throw 'SiteDirectory must be outside the source repository'
}

foreach ($requiredPath in @($workbenchSource, $assessmentPath, $bundleSchemaPath)) {
    if (-not (Test-Path -LiteralPath $requiredPath)) {
        throw "Required Workbench source was not found: $requiredPath"
    }
}

if (-not (Test-Path -LiteralPath $resolvedSiteDirectory -PathType Container)) {
    New-Item -ItemType Directory -Path $resolvedSiteDirectory -Force | Out-Null
}

$ownedAssetNames = @('index.html', 'app.js', 'styles.css')
foreach ($assetName in $ownedAssetNames) {
    Copy-Item -LiteralPath (Join-Path $workbenchSource $assetName) -Destination (Join-Path $resolvedSiteDirectory $assetName) -Force
}

$shutdownTokenBytes = New-Object byte[] 32
[Security.Cryptography.RandomNumberGenerator]::Fill($shutdownTokenBytes)
$shutdownToken = [Convert]::ToHexString($shutdownTokenBytes).ToLowerInvariant()
$shutdownConfig = [ordered]@{ shutdownToken = $shutdownToken } | ConvertTo-Json -Compress
[IO.File]::WriteAllText((Join-Path $resolvedSiteDirectory 'shutdown-config.js'), "globalThis.__HOSTED_RULE_WORKBENCH__ = $shutdownConfig;`n", [Text.UTF8Encoding]::new($false))

$stagedBundlePath = Join-Path $resolvedSiteDirectory 'rule-intake-review.json'
$resolvedBundlePath = if ([string]::IsNullOrWhiteSpace($BundlePath)) { $null } else { [IO.Path]::GetFullPath($BundlePath) }
$assessmentResult = $null

function Update-StagedBundle {
    if ($null -eq $resolvedBundlePath) {
        $assessmentArguments = @(
            '-NoProfile',
            '-File', $assessmentPath,
            '-RepositoryRoot', $repositoryRoot,
            '-OutputPath', $stagedBundlePath,
            '-CachePath', $AssessmentCachePath,
            '-BaselinePath', $AssessmentBaselinePath,
            '-Model', $AssessmentModel,
            '-ReasoningEffort', $AssessmentReasoningEffort,
            '-BatchSize', $AssessmentBatchSize,
            '-UpstreamBatchSize', $UpstreamAssessmentBatchSize,
            '-MaxRetries', $AssessmentMaxRetries,
            '-EvaluatorCommand', $EvaluatorCommand,
            '-OutputFormat', 'Json'
        )
        if ($ForceAssessment) {
            $assessmentArguments += '-Force'
        }
        $bundleOutput = @(& pwsh @assessmentArguments 2>&1)
        if ($LASTEXITCODE -ne 0) {
            throw "Rule intake assessment failed: $(($bundleOutput | Out-String).Trim())"
        }
        $script:assessmentResult = ($bundleOutput | Out-String) | ConvertFrom-Json
    }
    else {
        if (-not (Test-Path -LiteralPath $resolvedBundlePath -PathType Leaf)) {
            throw "BundlePath was not found: $resolvedBundlePath"
        }
        $bundleContent = Get-Content -LiteralPath $resolvedBundlePath -Raw
        if (-not ($bundleContent | Test-Json -SchemaFile $bundleSchemaPath -ErrorAction Stop)) {
            throw 'BundlePath does not satisfy the rule intake review schema'
        }
        [IO.File]::WriteAllText($stagedBundlePath, $bundleContent.TrimEnd() + "`n", [Text.UTF8Encoding]::new($false))
    }

    $content = Get-Content -LiteralPath $stagedBundlePath -Raw
    if (-not ($content | Test-Json -SchemaFile $bundleSchemaPath -ErrorAction Stop)) {
        throw 'Staged Workbench bundle does not satisfy the rule intake review schema'
    }
    return ($content | ConvertFrom-Json)
}

$stagedBundle = Update-StagedBundle
$stagedCandidates = @($stagedBundle.interactiveCandidates) + @($stagedBundle.upstreamCandidates)
$url = "http://127.0.0.1:$Port/"
$result = [ordered]@{
    status = 'ready'
    url = $url
    siteDirectory = $resolvedSiteDirectory
    bundlePath = $stagedBundlePath
    discoveredCandidateCount = $stagedCandidates.Count
    evaluatedCandidateCount = @($stagedCandidates | Where-Object { $_.PSObject.Properties['assessment'] -and $null -ne $_.assessment }).Count
    capacityReportCount = @($stagedBundle.guidanceCapacity.reports).Count
    assessment = $assessmentResult
    readOnly = $true
    allowedMethods = @('GET', 'HEAD')
    shutdownEndpoint = 'POST /shutdown'
    serving = -not $StageOnly
}

if ($StageOnly) {
    if ($OutputFormat -eq 'Json') {
        $result | ConvertTo-Json -Depth 5
    }
    else {
        Write-ValidationSectionHeader -Title 'Hosted Rule Workbench staging'
        Write-ValidationSummary -Fields ([ordered]@{
            Status = $result.status.ToUpperInvariant()
            'Discovered Candidates' = $result.discoveredCandidateCount
            'AI-Evaluated Candidates' = $result.evaluatedCandidateCount
            'Assessment Cache Hits' = $(if ($null -eq $assessmentResult) { '(prebuilt bundle)' } else { $assessmentResult.cacheHitCount })
            'Assessment Baseline Hits' = $(if ($null -eq $assessmentResult) { '(prebuilt bundle)' } else { $assessmentResult.baselineHitCount })
            'New Assessments' = $(if ($null -eq $assessmentResult) { '(prebuilt bundle)' } else { $assessmentResult.evaluatedCount })
            'Capacity Reports' = $result.capacityReportCount
            'Site Directory' = $result.siteDirectory
            Serving = $result.serving
        })
        Complete-ValidationTextOutput
    }
    return
}

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
        "Content-Security-Policy: default-src 'self'; script-src 'self' https://cdn.jsdelivr.net; style-src 'self' https://fonts.googleapis.com; font-src https://fonts.gstatic.com; connect-src 'self'; img-src 'self' data:; object-src 'none'; base-uri 'none'; frame-ancestors 'none'",
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

function Test-ShutdownToken {
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

$listener = [Net.Sockets.TcpListener]::new([Net.IPAddress]::Loopback, $Port)
try {
    $listener.Start()
    if (-not $NoLaunch) {
        Start-Process $url
    }
    if ($OutputFormat -eq 'Json') {
        $result | ConvertTo-Json -Depth 5
    }
    else {
        Write-ValidationSectionHeader -Title 'Hosted Rule Workbench'
        Write-ValidationSummary -Fields ([ordered]@{
            Status = 'READY'
            URL = $url
            'Discovered Candidates' = $result.discoveredCandidateCount
            'AI-Evaluated Candidates' = $result.evaluatedCandidateCount
            'Assessment Cache Hits' = $(if ($null -eq $assessmentResult) { '(prebuilt bundle)' } else { $assessmentResult.cacheHitCount })
            'Assessment Baseline Hits' = $(if ($null -eq $assessmentResult) { '(prebuilt bundle)' } else { $assessmentResult.baselineHitCount })
            'New Assessments' = $(if ($null -eq $assessmentResult) { '(prebuilt bundle)' } else { $assessmentResult.evaluatedCount })
            'Capacity Reports' = $result.capacityReportCount
            'Site Directory' = $resolvedSiteDirectory
            'Repository Writes' = 'DISABLED'
        })
        Write-Output 'Press Ctrl+C to stop the Workbench.'
        Complete-ValidationTextOutput
    }

    $shutdownRequested = $false
    while (-not $shutdownRequested) {
        $client = $listener.AcceptTcpClient()
        $stream = $null
        try {
            $stream = $client.GetStream()
            $reader = [IO.StreamReader]::new($stream, [Text.Encoding]::ASCII, $false, 1024, $true)
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
            if ($method -eq 'POST' -and $requestUri.AbsolutePath -eq '/shutdown') {
                $providedToken = [string]$requestHeaders['X-Workbench-Shutdown-Token']
                if (-not (Test-ShutdownToken -Candidate $providedToken -Expected $shutdownToken)) {
                    Write-HttpResponse -Stream $stream -StatusCode 403 -StatusText 'Forbidden' -ContentType 'text/plain; charset=utf-8' -Body ([Text.Encoding]::UTF8.GetBytes('Forbidden')) -IncludeBody $true
                    continue
                }
                $shutdownBody = [Text.Encoding]::UTF8.GetBytes('{"status":"shutting-down"}')
                Write-HttpResponse -Stream $stream -StatusCode 200 -StatusText 'OK' -ContentType 'application/json; charset=utf-8' -Body $shutdownBody -IncludeBody $true
                $shutdownRequested = $true
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
