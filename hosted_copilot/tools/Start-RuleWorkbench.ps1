[CmdletBinding()]
param(
    [ValidateRange(1024, 65535)]
    [int]$Port = 43143,

    [ValidateRange(1, 2147483647)]
    [int]$OwnerProcessId,

    [string]$SiteDirectory = (Join-Path ([IO.Path]::GetTempPath()) 'hosted-rule-workbench/site'),

    [string]$BundlePath,

    [string]$AssessmentCachePath = (Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'terraform-azurerm-ai-assisted-development/hosted-rule-intake/assessment-cache.json'),

    [string]$AssessmentBaselinePath = (Join-Path $PSScriptRoot '../copilot-rule-catalog/rule-assessments/assessment-baseline.json'),

    [string]$AssessmentScriptPath = (Join-Path $PSScriptRoot 'Invoke-RuleIntakeAssessment.ps1'),

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

    [switch]$RepairMissingAssessmentFields,

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
$workbenchIconSource = Join-Path $workbenchSource 'icons'
$assessmentPath = [IO.Path]::GetFullPath($AssessmentScriptPath)
$bundleSchemaPath = Join-Path $PSScriptRoot '../copilot-rule-catalog/rule-intake-review.schema.json'
$resolvedSiteDirectory = [IO.Path]::GetFullPath($SiteDirectory)
$repositoryPrefix = $repositoryRoot.TrimEnd([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar) + [IO.Path]::DirectorySeparatorChar
if ($resolvedSiteDirectory.StartsWith($repositoryPrefix, [StringComparison]::OrdinalIgnoreCase)) {
    throw 'SiteDirectory must be outside the source repository'
}

foreach ($requiredPath in @($workbenchSource, $workbenchIconSource, $assessmentPath, $bundleSchemaPath)) {
    if (-not (Test-Path -LiteralPath $requiredPath)) {
        throw "Required Workbench source was not found: $requiredPath"
    }
}

if (-not (Test-Path -LiteralPath $resolvedSiteDirectory -PathType Container)) {
    New-Item -ItemType Directory -Path $resolvedSiteDirectory -Force | Out-Null
}

$ownedAssetNames = @('index.html', 'app.js', 'hierarchical-view.js', 'styles.css', 'favicon.svg')
foreach ($assetName in $ownedAssetNames) {
    Copy-Item -LiteralPath (Join-Path $workbenchSource $assetName) -Destination (Join-Path $resolvedSiteDirectory $assetName) -Force
}
Copy-Item -LiteralPath $workbenchIconSource -Destination $resolvedSiteDirectory -Recurse -Force

$shutdownTokenBytes = New-Object byte[] 32
[Security.Cryptography.RandomNumberGenerator]::Fill($shutdownTokenBytes)
$shutdownToken = [Convert]::ToHexString($shutdownTokenBytes).ToLowerInvariant()
$maintainerIdentity = [ordered]@{
    status = 'unavailable'
    login = $null
    isCodeOwner = $false
    reason = 'GitHub CLI authentication is required for CODEOWNER-only Workbench actions.'
}
$targetRepository = [ordered]@{
    status = 'unavailable'
    repository = $null
    branch = $null
    commit = $null
    upstreamRepository = $null
    upstreamBranch = $null
    aheadBy = $null
    behindBy = $null
    reason = 'GitHub CLI authentication is required to resolve the promotion target.'
}
$ghCommand = Get-Command gh -ErrorAction SilentlyContinue
if ($null -ne $ghCommand) {
    $loginOutput = @(& $ghCommand.Source api user --jq .login 2>$null)
    if ($LASTEXITCODE -eq 0 -and -not [string]::IsNullOrWhiteSpace(($loginOutput | Out-String))) {
        $login = ($loginOutput | Select-Object -First 1).Trim()
        $codeOwnersPath = Join-Path $repositoryRoot '.github/CODEOWNERS'
        $applicableOwners = @()
        if (Test-Path -LiteralPath $codeOwnersPath -PathType Leaf) {
            foreach ($line in Get-Content -LiteralPath $codeOwnersPath) {
                $trimmed = $line.Trim()
                if ([string]::IsNullOrWhiteSpace($trimmed) -or $trimmed.StartsWith('#')) { continue }
                $parts = @($trimmed -split '\s+' | Where-Object { $_ })
                if ($parts.Count -ge 2 -and $parts[0] -in @('*', '/hosted_copilot/')) {
                    $applicableOwners = @($parts[1..($parts.Count - 1)])
                }
            }
        }
        $isCodeOwner = $applicableOwners -contains "@$login"
        $maintainerIdentity = [ordered]@{
            status = if ($isCodeOwner) { 'validated' } else { 'unauthorized' }
            login = $login
            isCodeOwner = $isCodeOwner
            reason = if ($isCodeOwner) { $null } else { 'The authenticated GitHub user is not a CODEOWNER for Hosted Toolkit changes.' }
        }

        $repositoryName = "$login/terraform-provider-azurerm"
        $repositoryOutput = @(& $ghCommand.Source api "repos/$repositoryName" 2>$null)
        if ($LASTEXITCODE -eq 0) {
            $repository = ($repositoryOutput | Out-String) | ConvertFrom-Json
            $branch = [string]$repository.default_branch
            $commitOutput = @(& $ghCommand.Source api "repos/$repositoryName/commits/$branch" --jq .sha 2>$null)
            $commit = ($commitOutput | Select-Object -First 1).Trim()
            if ($LASTEXITCODE -eq 0 -and $repository.fork -eq $true -and $repository.parent.full_name -eq 'hashicorp/terraform-provider-azurerm' -and $commit -match '^[0-9a-f]{40}$') {
                $upstreamRepository = [string]$repository.parent.full_name
                $upstreamBranch = [string]$repository.parent.default_branch
                $comparisonOutput = @(& $ghCommand.Source api "repos/$upstreamRepository/compare/$upstreamBranch...$login`:$branch" 2>$null)
                $comparison = if ($LASTEXITCODE -eq 0) { ($comparisonOutput | Out-String) | ConvertFrom-Json } else { $null }
                $targetRepository = [ordered]@{
                    status = 'validated'
                    repository = [string]$repository.full_name
                    branch = $branch
                    commit = $commit
                    upstreamRepository = $upstreamRepository
                    upstreamBranch = $upstreamBranch
                    aheadBy = if ($null -ne $comparison) { [int]$comparison.ahead_by } else { $null }
                    behindBy = if ($null -ne $comparison) { [int]$comparison.behind_by } else { $null }
                    reason = $null
                }
            }
            else {
                $targetRepository.reason = "The authenticated user's terraform-provider-azurerm repository is not a valid fork promotion target."
            }
        }
        else {
            $targetRepository.reason = "The authenticated user's terraform-provider-azurerm fork could not be resolved."
        }
    }
}
$shutdownConfig = [ordered]@{
    shutdownToken = $shutdownToken
    maintainerIdentity = $maintainerIdentity
    targetRepository = $targetRepository
} | ConvertTo-Json -Compress
[IO.File]::WriteAllText((Join-Path $resolvedSiteDirectory 'shutdown-config.js'), "globalThis.__HOSTED_RULE_WORKBENCH__ = $shutdownConfig;`n", [Text.UTF8Encoding]::new($false))

$stagedBundlePath = Join-Path $resolvedSiteDirectory 'rule-intake-review.json'
$resolvedBundlePath = if ([string]::IsNullOrWhiteSpace($BundlePath)) { $null } else { [IO.Path]::GetFullPath($BundlePath) }
$assessmentResult = $null

function Update-StagedBundle {
    if ($null -eq $resolvedBundlePath) {
        $assessmentOutputFormat = if ($OutputFormat -eq 'Text') { 'Text' } else { 'Json' }
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
            '-OutputFormat', $assessmentOutputFormat
        )
        if ($ForceAssessment) {
            $assessmentArguments += '-Force'
        }
        if ($RepairMissingAssessmentFields) {
            $assessmentArguments += '-RepairMissingFields'
        }
        if ($OutputFormat -eq 'Text') {
            Write-Host '[RUNNING]  assessment                  : Collecting candidates and resolving AI assessments'
            & pwsh @assessmentArguments 2>&1 | ForEach-Object { Write-Host $_ }
            if ($LASTEXITCODE -ne 0) {
                throw 'Rule intake assessment failed; review the assessment output above'
            }
            Write-Host '[PASSED]   assessment                  : Candidate bundle is ready for Workbench staging'
        }
        else {
            $bundleOutput = @(& pwsh @assessmentArguments 2>&1)
            if ($LASTEXITCODE -ne 0) {
                throw "Rule intake assessment failed: $(($bundleOutput | Out-String).Trim())"
            }
            try {
                $script:assessmentResult = ($bundleOutput | Out-String) | ConvertFrom-Json
            }
            catch {
                throw "Rule intake assessment did not return valid JSON: $($_.Exception.Message)"
            }
        }
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
$stagedCandidates = @($stagedBundle.interactiveCandidates) + @($stagedBundle.maintainerCandidates) + @($stagedBundle.upstreamCandidates)
$url = "http://127.0.0.1:$Port/"
$result = [ordered]@{
    status = 'ready'
    url = $url
    siteDirectory = $resolvedSiteDirectory
    bundlePath = $stagedBundlePath
    discoveredCandidateCount = $stagedCandidates.Count
    evaluatedCandidateCount = @($stagedCandidates | Where-Object { $_.PSObject.Properties['assessments'] }).Count
    ruleCandidateCount = @($stagedCandidates | ForEach-Object { @($_.assessments) }).Count
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
            Assessment = $(if ($null -eq $resolvedBundlePath) { 'COMPLETED ABOVE' } else { 'PREBUILT BUNDLE' })
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
$allowedHosts = @("127.0.0.1:$Port", "localhost:$Port")
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
            Assessment = $(if ($null -eq $resolvedBundlePath) { 'COMPLETED ABOVE' } else { 'PREBUILT BUNDLE' })
            'Capacity Reports' = $result.capacityReportCount
            'Site Directory' = $resolvedSiteDirectory
            'Repository Writes' = 'DISABLED'
        })
        Write-Output 'Press Ctrl+C to stop the Workbench.'
        Complete-ValidationTextOutput
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
            $requestHost = [string]$requestHeaders['Host']
            if ([string]::IsNullOrWhiteSpace($requestHost) -or $requestHost.Trim() -notin $allowedHosts) {
                Write-HttpResponse -Stream $stream -StatusCode 421 -StatusText 'Misdirected Request' -ContentType 'text/plain; charset=utf-8' -Body ([Text.Encoding]::UTF8.GetBytes('Misdirected Request')) -IncludeBody $true
                continue
            }
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
