[CmdletBinding()]
param(
    [string]$RepositoryRoot = (Join-Path $PSScriptRoot '../..'),

    [string]$SourceDefinitionPath = (Join-Path $PSScriptRoot '../copilot-rule-catalog/source-definitions/maintainer-proposals.json'),

    [string]$HostedCatalogPath = (Join-Path $PSScriptRoot '../copilot-rule-catalog/instruction-catalog.json'),

    [string]$UpstreamCurrentCommit,

    [ValidateRange(1, 5)]
    [int]$MaximumRequestAttempts = 3,

    [ValidateRange(0, 60000)]
    [int]$RetryDelayMilliseconds = 1000,

    [Parameter(Mandatory = $true)]
    [string]$OutputPath,

    [ValidateSet('Text', 'Json')]
    [string]$OutputFormat = 'Text'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$sourceEvidenceModulePath = Join-Path $PSScriptRoot 'SourceEvidenceValidation.psm1'
Import-Module -Name $sourceEvidenceModulePath -Force
$helpersPath = Join-Path $PSScriptRoot 'HostedToolkit.Helpers.psm1'
Import-Module -Name $helpersPath -Force

function Test-JsonFile {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$SchemaPath
    )

    if (-not (Test-Json -Json (Get-Content -LiteralPath $Path -Raw) -SchemaFile $SchemaPath -ErrorAction Stop)) {
        throw "JSON does not satisfy its schema: $Path"
    }
}

function Assert-RelativeSourcePath {
    param(
        [Parameter(Mandatory = $true)][string]$Value,
        [Parameter(Mandatory = $true)][string]$Name,
        [switch]$AllowGlob
    )

    if ([IO.Path]::IsPathRooted($Value) -or $Value.Contains('\')) {
        throw "$Name must be a repository-relative path using `/`: $Value"
    }
    $segments = @($Value -split '/')
    if ($segments.Count -eq 0 -or @($segments | Where-Object { $_ -in @('', '.', '..') }).Count -ne 0) {
        throw "$Name contains an empty or dot segment: $Value"
    }
    if (-not $AllowGlob -and $Value.IndexOfAny([char[]]'*?[]{}!') -ge 0) {
        throw "$Name cannot contain glob syntax: $Value"
    }
    if ($AllowGlob) {
        foreach ($segment in $segments) {
            if ($segment.Contains('**') -and $segment -ne '**') {
                throw "$Name uses `**` outside a complete path segment: $Value"
            }
            if ($segment.IndexOfAny([char[]]'?[]{}!') -ge 0) {
                throw "$Name contains unsupported glob syntax: $Value"
            }
        }
    }
}

function Convert-SourcePatternToRegex {
    param([Parameter(Mandatory = $true)][string]$Pattern)

    Assert-RelativeSourcePath -Value $Pattern -Name 'File pattern' -AllowGlob
    $segments = @($Pattern -split '/')
    $parts = [Collections.Generic.List[string]]::new()
    for ($index = 0; $index -lt $segments.Count; $index++) {
        $segment = $segments[$index]
        if ($segment -eq '**') {
            if ($index -eq $segments.Count - 1) {
                $parts.Add('(?:[^/]+(?:/|$))*')
            }
            else {
                $parts.Add('(?:[^/]+/)*')
            }
            continue
        }

        $escaped = [Regex]::Escape($segment).Replace('\*', '[^/]*')
        $parts.Add($escaped)
        if ($index -lt $segments.Count - 1) {
            $parts.Add('/')
        }
    }

    return [Regex]::new('^' + ($parts -join '') + '$', [Text.RegularExpressions.RegexOptions]::CultureInvariant)
}

function Assert-NoReparsePoint {
    param(
        [Parameter(Mandatory = $true)][string]$Root,
        [Parameter(Mandatory = $true)][string]$Path
    )

    $current = [IO.Path]::GetFullPath($Path)
    $rootPath = [IO.Path]::GetFullPath($Root).TrimEnd([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar)
    while ($true) {
        $item = Get-Item -LiteralPath $current -Force
        if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
            throw "Source path cannot traverse a symbolic link or reparse point: $Path"
        }
        if ($current -eq $rootPath) {
            break
        }
        $parent = Split-Path -Parent $current
        if ([string]::IsNullOrWhiteSpace($parent) -or $parent.Length -ge $current.Length) {
            throw "Source path escapes its configured root: $Path"
        }
        $current = $parent
    }
}

function Get-MatchedSourceFiles {
    param(
        [Parameter(Mandatory = $true)][string]$Root,
        [Parameter(Mandatory = $true)][string[]]$Includes,
        [string[]]$Excludes = @()
    )

    $includeRegexes = @($Includes | ForEach-Object { Convert-SourcePatternToRegex -Pattern $_ })
    $excludeRegexes = @($Excludes | ForEach-Object { Convert-SourcePatternToRegex -Pattern $_ })
    $matches = [Collections.Generic.List[object]]::new()
    $caseInsensitivePaths = @{}

    foreach ($file in @(Get-ChildItem -LiteralPath $Root -File -Recurse -Force)) {
        Assert-NoReparsePoint -Root $Root -Path $file.FullName
        $relativePath = [IO.Path]::GetRelativePath($Root, $file.FullName).Replace('\', '/')
        $included = @($includeRegexes | Where-Object { $_.IsMatch($relativePath) }).Count -ne 0
        $excluded = @($excludeRegexes | Where-Object { $_.IsMatch($relativePath) }).Count -ne 0
        if (-not $included -or $excluded) {
            continue
        }

        $caseKey = $relativePath.ToUpperInvariant()
        if ($caseInsensitivePaths.ContainsKey($caseKey) -and $caseInsensitivePaths[$caseKey] -cne $relativePath) {
            throw "Source paths differ only by case: $($caseInsensitivePaths[$caseKey]) and $relativePath"
        }
        $caseInsensitivePaths[$caseKey] = $relativePath
        $matches.Add([pscustomobject]@{ RelativePath = $relativePath; FullName = $file.FullName })
    }

    $matches.Sort([Comparison[object]]{
        param($left, $right)
        return [StringComparer]::Ordinal.Compare([string]$left.RelativePath, [string]$right.RelativePath)
    })
    return $matches.ToArray()
}

function Get-OrdinallySortedRecords {
    param([Parameter(Mandatory = $true)][object[]]$Records)

    $sorted = [Collections.Generic.List[object]]::new()
    foreach ($record in $Records) {
        $sorted.Add($record)
    }
    $sorted.Sort([Comparison[object]]{
        param($left, $right)
        return [StringComparer]::Ordinal.Compare([string]$left.sourceId, [string]$right.sourceId)
    })
    return $sorted.ToArray()
}

function Get-CanonicalFileSetSha256 {
    param([Parameter(Mandatory = $true)][object[]]$Files)

    $builder = [Text.StringBuilder]::new()
    foreach ($file in $Files) {
        $null = $builder.Append([string]$file.RelativePath).Append([char]0).Append((Get-Sha256 -Path ([string]$file.FullName))).Append([char]0)
    }
    return Get-Sha256 -Content $builder.ToString()
}

function Get-InventoryRevisionFiles {
    param(
        [Parameter(Mandatory = $true)][string]$RepositoryRoot,
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][object[]]$MatchedFiles,
        [Parameter(Mandatory = $true)][object[]]$Records
    )

    $repositoryPrefix = $RepositoryRoot.TrimEnd([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar) + [IO.Path]::DirectorySeparatorChar
    $paths = [Collections.Generic.Dictionary[string,object]]::new([StringComparer]::Ordinal)
    foreach ($matchedFile in $MatchedFiles) {
        $relativePath = [IO.Path]::GetRelativePath($RepositoryRoot, [string]$matchedFile.FullName).Replace('\', '/')
        $paths[$relativePath] = [pscustomobject]@{ RelativePath = $relativePath; FullName = [string]$matchedFile.FullName }
    }
    foreach ($record in $Records) {
        Assert-RelativeSourcePath -Value ([string]$record.location) -Name 'Inventory record location'
        $fullPath = [IO.Path]::GetFullPath((Join-Path $RepositoryRoot ([string]$record.location)))
        if (-not $fullPath.StartsWith($repositoryPrefix, [StringComparison]::OrdinalIgnoreCase) -or -not (Test-Path -LiteralPath $fullPath -PathType Leaf)) {
            throw "Inventory record location is outside the repository or does not exist: $($record.location)"
        }
        Assert-NoReparsePoint -Root $RepositoryRoot -Path $fullPath
        $paths[[string]$record.location] = [pscustomobject]@{ RelativePath = [string]$record.location; FullName = $fullPath }
    }

    $files = [Collections.Generic.List[object]]::new()
    foreach ($file in $paths.Values) {
        $files.Add($file)
    }
    $files.Sort([Comparison[object]]{
        param($left, $right)
        return [StringComparer]::Ordinal.Compare([string]$left.RelativePath, [string]$right.RelativePath)
    })
    return $files.ToArray()
}

function Invoke-SourceInventoryParser {
    param(
        [Parameter(Mandatory = $true)][object]$Definition,
        [Parameter(Mandatory = $true)][string]$RepositoryRoot,
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][object[]]$MatchedFiles,
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][object[]]$RemoteDocuments,
        [AllowNull()][object]$SourceRevision,
        [AllowNull()][object]$HostedCatalog
    )

    switch ([string]$Definition.parser) {
        'maintainer-proposals-v2' {
            $modulePath = Join-Path $RepositoryRoot 'hosted_copilot/tools/source-parsers/MaintainerProposalsV2.psm1'
            Import-Module $modulePath -Force
            return @(Get-MaintainerProposalInventoryRecords -SourcePaths @($MatchedFiles.FullName) -RepositoryRoot $RepositoryRoot -KnownHostedRuleIds @($HostedCatalog.rules.id))
        }
        'interactive-toolkit-v2' {
            if ($MatchedFiles.Count -ne 1 -or [string]$MatchedFiles[0].RelativePath -cne 'rule-catalog.json') {
                throw 'Interactive Toolkit source definition must resolve exactly rule-catalog.json'
            }
            $modulePath = Join-Path $RepositoryRoot 'hosted_copilot/tools/source-parsers/InteractiveToolkitV2.psm1'
            Import-Module $modulePath -Force
            return @(Get-InteractiveToolkitInventoryRecords -CatalogPath ([string]$MatchedFiles[0].FullName) -RepositoryRoot $RepositoryRoot)
        }
        'contributor-guidance-v2' {
            if ([string]$Definition.root.kind -cne 'github') {
                throw 'Contributor Guidance parser requires a GitHub source root'
            }
            $modulePath = Join-Path $RepositoryRoot 'hosted_copilot/tools/source-parsers/ContributorGuidanceV2.psm1'
            Import-Module $modulePath -Force
            return @(Get-ContributorGuidanceInventoryRecords -Documents $RemoteDocuments -Repository ([string]$Definition.root.repository) -ResolvedCommit ([string]$SourceRevision.resolvedCommit) -RootPath ([string]$Definition.root.path))
        }
        default {
            throw "Unsupported parser '$($Definition.parser)'"
        }
    }
}

function Invoke-GitHubCliJson {
    param(
        [Parameter(Mandatory = $true)][string[]]$Arguments,
        [string]$InputJson
    )

    $gh = Get-Command gh -ErrorAction SilentlyContinue
    if ($null -eq $gh) {
        throw 'GitHub CLI is not available'
    }

    $startInfo = [Diagnostics.ProcessStartInfo]::new()
    $startInfo.FileName = $gh.Source
    $startInfo.UseShellExecute = $false
    $startInfo.RedirectStandardInput = $true
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true
    $startInfo.StandardOutputEncoding = [Text.UTF8Encoding]::new($false)
    $startInfo.StandardErrorEncoding = [Text.UTF8Encoding]::new($false)
    foreach ($argument in $Arguments) {
        $startInfo.ArgumentList.Add($argument)
    }

    $process = [Diagnostics.Process]::new()
    $process.StartInfo = $startInfo
    $null = $process.Start()
    if (-not [string]::IsNullOrEmpty($InputJson)) {
        $process.StandardInput.Write($InputJson)
    }
    $process.StandardInput.Close()
    $standardOutput = $process.StandardOutput.ReadToEnd()
    $standardError = $process.StandardError.ReadToEnd()
    $process.WaitForExit()
    if ($process.ExitCode -ne 0) {
        throw "GitHub CLI request failed: $($standardError.Trim())"
    }
    return $standardOutput | ConvertFrom-Json -ErrorAction Stop
}

function Test-GitHubTransientFailure {
    param([Parameter(Mandatory = $true)][object]$Failure)

    $graphQlErrorTypes = @($Failure.Exception.Data['GitHubGraphQLErrorTypes'])
    if (@($graphQlErrorTypes | Where-Object { [string]$_ -ceq 'RATE_LIMITED' }).Count -gt 0) {
        return $true
    }
    try {
        $statusCode = [int]$Failure.Exception.Response.StatusCode
        if ($statusCode -in @(408, 429, 500, 502, 503, 504)) {
            return $true
        }
    }
    catch {
    }
    return [string]$Failure.Exception.Message -match '(?i)(timeout|timed out|rate limit|secondary rate|connection reset|connection closed|temporar|\b408\b|\b429\b|\b500\b|\b502\b|\b503\b|\b504\b)'
}

function Get-GitHubRetryAfterMilliseconds {
    param([Parameter(Mandatory = $true)][object]$Failure)

    try {
        $retryAfter = $Failure.Exception.Response.Headers.RetryAfter
        if ($null -ne $retryAfter.Delta) {
            return [int][Math]::Ceiling($retryAfter.Delta.TotalMilliseconds)
        }
        if ($null -ne $retryAfter.Date) {
            return [int][Math]::Max(0, [Math]::Ceiling(($retryAfter.Date - [DateTimeOffset]::UtcNow).TotalMilliseconds))
        }
    }
    catch {
    }
    if ([string]$Failure.Exception.Message -match '(?i)retry-after\D+(?<seconds>[0-9]+)') {
        return [int]$Matches.seconds * 1000
    }
    return 0
}

function Invoke-GitHubRestRequestOnce {
    param([Parameter(Mandatory = $true)][string]$Path)

    $token = if (-not [string]::IsNullOrWhiteSpace($env:GITHUB_TOKEN)) { $env:GITHUB_TOKEN } else { $env:GH_TOKEN }
    if (-not [string]::IsNullOrWhiteSpace($token)) {
        return Invoke-RestMethod -Method Get -Uri "https://api.github.com$Path" -Headers @{
            Accept = 'application/vnd.github+json'
            Authorization = "Bearer $token"
            'User-Agent' = 'terraform-azurerm-ai-assisted-development'
            'X-GitHub-Api-Version' = '2022-11-28'
        }
    }

    $gh = Get-Command gh -ErrorAction SilentlyContinue
    if ($null -ne $gh) {
        return Invoke-GitHubCliJson -Arguments @('api', $Path)
    }

    return Invoke-RestMethod -Method Get -Uri "https://api.github.com$Path" -Headers @{
        Accept = 'application/vnd.github+json'
        'User-Agent' = 'terraform-azurerm-ai-assisted-development'
        'X-GitHub-Api-Version' = '2022-11-28'
    }
}

function Invoke-GitHubRestRequest {
    param([Parameter(Mandatory = $true)][string]$Path)

    return Invoke-SourceEvidenceWithRetry -Operation "GitHub REST request $Path" -MaximumAttempts $MaximumRequestAttempts -BaseDelayMilliseconds $RetryDelayMilliseconds -ShouldRetry {
        param($failure)
        return Test-GitHubTransientFailure -Failure $failure
    } -GetRetryAfterMilliseconds {
        param($failure)
        return Get-GitHubRetryAfterMilliseconds -Failure $failure
    } -Action {
        return Invoke-GitHubRestRequestOnce -Path $Path
    }
}

function Invoke-GitHubGraphQLRequestOnce {
    param([Parameter(Mandatory = $true)][object]$Request)

    $requestJson = $Request | ConvertTo-Json -Depth 20 -Compress
    $token = if (-not [string]::IsNullOrWhiteSpace($env:GITHUB_TOKEN)) { $env:GITHUB_TOKEN } else { $env:GH_TOKEN }
    if (-not [string]::IsNullOrWhiteSpace($token)) {
        return Invoke-RestMethod -Method Post -Uri 'https://api.github.com/graphql' -ContentType 'application/json' -Headers @{
            Authorization = "Bearer $token"
            'User-Agent' = 'terraform-azurerm-ai-assisted-development'
        } -Body $requestJson
    }

    $gh = Get-Command gh -ErrorAction SilentlyContinue
    if ($null -eq $gh) {
        throw 'Contributor Guidance collection requires GITHUB_TOKEN, GH_TOKEN, or an authenticated GitHub CLI'
    }
    return Invoke-GitHubCliJson -Arguments @('api', 'graphql', '--input', '-') -InputJson $requestJson
}

function Invoke-GitHubGraphQLRequest {
    param([Parameter(Mandatory = $true)][object]$Request)

    return Invoke-SourceEvidenceWithRetry -Operation 'GitHub GraphQL request' -MaximumAttempts $MaximumRequestAttempts -BaseDelayMilliseconds $RetryDelayMilliseconds -ShouldRetry {
        param($failure)
        return Test-GitHubTransientFailure -Failure $failure
    } -GetRetryAfterMilliseconds {
        param($failure)
        return Get-GitHubRetryAfterMilliseconds -Failure $failure
    } -Action {
        $response = Invoke-GitHubGraphQLRequestOnce -Request $Request
        if ($response.PSObject.Properties['errors'] -and @($response.errors).Count -gt 0) {
            $message = @($response.errors | ForEach-Object { [string]$_.message }) -join '; '
            $errorTypes = @($response.errors | ForEach-Object { [string]$_.type } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Sort-Object -Unique)
            $exception = [InvalidOperationException]::new("GitHub GraphQL returned errors: $message")
            $exception.Data['GitHubGraphQLErrorTypes'] = $errorTypes
            throw $exception
        }
        return $response
    }
}

function Get-GitHubSourceDocuments {
    param(
        [Parameter(Mandatory = $true)][object]$Definition,
        [string]$RequestedCommit
    )

    $repository = [string]$Definition.root.repository
    if ($repository -cne 'hashicorp/terraform-provider-azurerm') {
        throw "Unsupported GitHub source repository: $repository"
    }
    Assert-RelativeSourcePath -Value ([string]$Definition.root.path) -Name 'GitHub source root path'
    if (-not [string]::IsNullOrWhiteSpace($RequestedCommit) -and $RequestedCommit -notmatch '^[0-9a-f]{40}$') {
        throw 'UpstreamCurrentCommit must be a lowercase 40-character Git commit hash'
    }

    $selectedRef = if ([string]::IsNullOrWhiteSpace($RequestedCommit)) { [string]$Definition.root.ref } else { $RequestedCommit }
    $encodedRef = [Uri]::EscapeDataString($selectedRef)
    $commitResponse = Invoke-GitHubRestRequest -Path "/repos/$repository/commits/$encodedRef"
    $resolvedCommit = ([string]$commitResponse.sha).ToLowerInvariant()
    if ($resolvedCommit -notmatch '^[0-9a-f]{40}$') {
        throw "GitHub did not resolve a valid commit for ref $selectedRef"
    }
    if (-not [string]::IsNullOrWhiteSpace($RequestedCommit) -and $resolvedCommit -cne $RequestedCommit) {
        throw "GitHub resolved commit $resolvedCommit instead of requested commit $RequestedCommit"
    }

    $treeSha = ([string]$commitResponse.commit.tree.sha).ToLowerInvariant()
    if ($treeSha -notmatch '^[0-9a-f]{40}$') {
        throw "GitHub commit $resolvedCommit did not include a valid tree"
    }

    foreach ($rootSegment in @(([string]$Definition.root.path) -split '/')) {
        $treeLevel = Invoke-GitHubRestRequest -Path "/repos/$repository/git/trees/$treeSha"
        $matchingEntries = @($treeLevel.tree | Where-Object { [string]$_.path -ceq $rootSegment -and [string]$_.type -ceq 'tree' })
        if ($matchingEntries.Count -ne 1) {
            throw "GitHub source root was not found at commit $resolvedCommit`: $($Definition.root.path)"
        }
        $treeSha = ([string]$matchingEntries[0].sha).ToLowerInvariant()
    }

    $treeResponse = Invoke-GitHubRestRequest -Path "/repos/$repository/git/trees/$treeSha`?recursive=1"
    if ([bool]$treeResponse.truncated) {
        throw "GitHub tree listing was truncated at commit $resolvedCommit"
    }

    $includeRegexes = @($Definition.files | ForEach-Object { Convert-SourcePatternToRegex -Pattern ([string]$_) })
    $excludeRegexes = @($Definition.exclude | ForEach-Object { Convert-SourcePatternToRegex -Pattern ([string]$_) })
    $rootPrefix = ([string]$Definition.root.path).TrimEnd('/') + '/'
    $matches = [Collections.Generic.List[object]]::new()
    $caseInsensitivePaths = @{}
    foreach ($entry in @($treeResponse.tree)) {
        if ([string]$entry.type -cne 'blob') {
            continue
        }
        $relativePath = [string]$entry.path
        $fullPath = $rootPrefix + $relativePath
        $included = @($includeRegexes | Where-Object { $_.IsMatch($relativePath) }).Count -ne 0
        $excluded = @($excludeRegexes | Where-Object { $_.IsMatch($relativePath) }).Count -ne 0
        if (-not $included -or $excluded) {
            continue
        }

        $caseKey = $relativePath.ToUpperInvariant()
        if ($caseInsensitivePaths.ContainsKey($caseKey) -and $caseInsensitivePaths[$caseKey] -cne $relativePath) {
            throw "GitHub source paths differ only by case: $($caseInsensitivePaths[$caseKey]) and $relativePath"
        }
        $caseInsensitivePaths[$caseKey] = $relativePath
        $matches.Add([pscustomobject]@{ RelativePath = $relativePath; FullPath = $fullPath; Oid = ([string]$entry.sha).ToLowerInvariant() })
    }
    if ($matches.Count -eq 0) {
        throw "Source definition did not match any files: $($Definition.id)"
    }
    $matches.Sort([Comparison[object]]{
        param($left, $right)
        return [StringComparer]::Ordinal.Compare([string]$left.RelativePath, [string]$right.RelativePath)
    })

    $repositoryParts = @($repository -split '/')
    $documents = [Collections.Generic.List[object]]::new()
    $totalCost = 0
    $remaining = $null
    $chunkSize = 20
    for ($chunkStart = 0; $chunkStart -lt $matches.Count; $chunkStart += $chunkSize) {
        $chunkEnd = [Math]::Min($chunkStart + $chunkSize - 1, $matches.Count - 1)
        $chunk = @($matches[$chunkStart..$chunkEnd])
        $variableDefinitions = [Collections.Generic.List[string]]::new()
        $variableDefinitions.Add('$owner: String!')
        $variableDefinitions.Add('$name: String!')
        $fields = [Collections.Generic.List[string]]::new()
        $variables = [ordered]@{ owner = $repositoryParts[0]; name = $repositoryParts[1] }
        for ($index = 0; $index -lt $chunk.Count; $index++) {
            $variableName = "expression$index"
            $variableDefinitions.Add("`$$variableName`: String!")
            $fields.Add("blob$index`: object(expression: `$$variableName) { ... on Blob { byteSize isBinary isTruncated oid text } }")
            $variables[$variableName] = "$resolvedCommit`:$($chunk[$index].FullPath)"
        }
        $query = "query($($variableDefinitions -join ', ')) { repository(owner: `$owner, name: `$name) { $($fields -join ' ') } rateLimit { cost remaining } }"
        $response = Invoke-GitHubGraphQLRequest -Request ([ordered]@{ query = $query; variables = $variables })
        if ($response.PSObject.Properties['errors'] -and @($response.errors).Count -gt 0) {
            throw "GitHub GraphQL returned errors for commit $resolvedCommit"
        }
        if ($null -eq $response.data.repository) {
            throw "GitHub GraphQL did not return repository $repository"
        }
        $totalCost += [int]$response.data.rateLimit.cost
        $remaining = [int]$response.data.rateLimit.remaining

        for ($index = 0; $index -lt $chunk.Count; $index++) {
            $alias = "blob$index"
            $property = $response.data.repository.PSObject.Properties[$alias]
            if ($null -eq $property -or $null -eq $property.Value) {
                throw "GitHub GraphQL did not return blob $($chunk[$index].FullPath)"
            }
            $blob = $property.Value
            if ([bool]$blob.isBinary -or [bool]$blob.isTruncated -or $null -eq $blob.text) {
                throw "GitHub GraphQL returned an unreadable blob for $($chunk[$index].FullPath)"
            }
            if (([string]$blob.oid).ToLowerInvariant() -cne [string]$chunk[$index].Oid) {
                throw "GitHub GraphQL blob identity mismatch for $($chunk[$index].FullPath)"
            }
            if ([Text.Encoding]::UTF8.GetByteCount([string]$blob.text) -ne [int]$blob.byteSize) {
                throw "GitHub GraphQL blob size mismatch for $($chunk[$index].FullPath)"
            }
            $documents.Add([pscustomobject]@{ RelativePath = [string]$chunk[$index].RelativePath; Content = [string]$blob.text })
        }
    }

    return [pscustomobject]@{
        Documents = $documents.ToArray()
        SourceRevision = [ordered]@{
            kind = 'github-commit'
            configuredRef = [string]$Definition.root.ref
            overrideUsed = -not [string]::IsNullOrWhiteSpace($RequestedCommit)
            resolvedCommit = $resolvedCommit
        }
        RateLimit = [ordered]@{ cost = $totalCost; remaining = $remaining }
    }
}

function Write-JsonAtomically {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][object]$Value
    )

    $directory = Split-Path -Parent $Path
    if (-not (Test-Path -LiteralPath $directory -PathType Container)) {
        $null = New-Item -ItemType Directory -Path $directory -Force
    }
    $temporaryPath = Join-Path $directory ('.' + [IO.Path]::GetFileName($Path) + '.' + [guid]::NewGuid().ToString('N') + '.tmp')
    try {
        [IO.File]::WriteAllText($temporaryPath, (($Value | ConvertTo-Json -Depth 30) + "`n"), [Text.UTF8Encoding]::new($false))
        [IO.File]::Move($temporaryPath, $Path, $true)
    }
    finally {
        if (Test-Path -LiteralPath $temporaryPath) {
            Remove-Item -LiteralPath $temporaryPath -Force
        }
    }
}

$resolvedRepositoryRoot = [IO.Path]::GetFullPath($RepositoryRoot).TrimEnd([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar)
$resolvedDefinitionPath = [IO.Path]::GetFullPath($SourceDefinitionPath)
$resolvedCatalogPath = [IO.Path]::GetFullPath($HostedCatalogPath)
$resolvedOutputPath = [IO.Path]::GetFullPath($OutputPath)
$repositoryPrefix = $resolvedRepositoryRoot + [IO.Path]::DirectorySeparatorChar
if ($resolvedOutputPath.StartsWith($repositoryPrefix, [StringComparison]::OrdinalIgnoreCase)) {
    throw 'Staged inventory output must be outside the repository root'
}

$definitionSchemaPath = Join-Path (Split-Path -Parent $resolvedDefinitionPath) 'source-definition.schema.json'
$catalogRoot = Split-Path -Parent $resolvedCatalogPath
$inventorySchemaPath = Join-Path $catalogRoot 'source-inventories/source-inventory.schema.json'
$contractSchemaPath = Join-Path $catalogRoot 'parser-contracts/parser-contract.schema.json'
foreach ($requiredPath in @($resolvedDefinitionPath, $definitionSchemaPath, $inventorySchemaPath, $contractSchemaPath)) {
    if (-not (Test-Path -LiteralPath $requiredPath -PathType Leaf)) {
        throw "Required source inventory input was not found: $requiredPath"
    }
}

Test-JsonFile -Path $resolvedDefinitionPath -SchemaPath $definitionSchemaPath
$definition = Get-Content -LiteralPath $resolvedDefinitionPath -Raw | ConvertFrom-Json
$contractPath = Join-Path $catalogRoot "parser-contracts/$($definition.parser).json"
if (-not (Test-Path -LiteralPath $contractPath -PathType Leaf)) {
    throw "Parser contract was not found: $contractPath"
}
Test-JsonFile -Path $contractPath -SchemaPath $contractSchemaPath
$contract = Get-Content -LiteralPath $contractPath -Raw | ConvertFrom-Json
if ([string]$contract.parserId -cne [string]$definition.parser) {
    throw "Parser contract ID does not match the source definition: $($definition.parser)"
}
$parserContractSha256 = $null

$matchedFiles = @()
$remoteDocuments = @()
$sourceRevision = $null
$rateLimit = $null
switch ([string]$definition.root.kind) {
    'repository' {
        Assert-RelativeSourcePath -Value ([string]$definition.root.path) -Name 'Source root path'
        $resolvedSourceRoot = [IO.Path]::GetFullPath((Join-Path $resolvedRepositoryRoot ([string]$definition.root.path)))
        if (-not $resolvedSourceRoot.StartsWith($repositoryPrefix, [StringComparison]::OrdinalIgnoreCase) -or -not (Test-Path -LiteralPath $resolvedSourceRoot -PathType Container)) {
            throw "Source root is outside the repository or does not exist: $($definition.root.path)"
        }
        Assert-NoReparsePoint -Root $resolvedRepositoryRoot -Path $resolvedSourceRoot
        $matchedFiles = @(Get-MatchedSourceFiles -Root $resolvedSourceRoot -Includes @($definition.files) -Excludes @($definition.exclude))
        if ($matchedFiles.Count -eq 0) {
            throw "Source definition did not match any files: $($definition.id)"
        }
        break
    }
    'github' {
        $remoteCollection = Get-GitHubSourceDocuments -Definition $definition -RequestedCommit $UpstreamCurrentCommit
        $remoteDocuments = @($remoteCollection.Documents)
        $sourceRevision = $remoteCollection.SourceRevision
        $rateLimit = $remoteCollection.RateLimit
        break
    }
    default {
        throw "Source root kind is not implemented by this collector: $($definition.root.kind)"
    }
}

$catalog = $null
if ([string]$definition.parser -ceq 'maintainer-proposals-v2') {
    $catalogSchemaPath = Join-Path (Split-Path -Parent $resolvedCatalogPath) 'instruction-catalog.schema.json'
    foreach ($requiredPath in @($resolvedCatalogPath, $catalogSchemaPath)) {
        if (-not (Test-Path -LiteralPath $requiredPath -PathType Leaf)) {
            throw "Required Maintainer Proposal parser input was not found: $requiredPath"
        }
    }
    Test-JsonFile -Path $resolvedCatalogPath -SchemaPath $catalogSchemaPath
    $catalog = Get-Content -LiteralPath $resolvedCatalogPath -Raw | ConvertFrom-Json
}
$records = @(Invoke-SourceInventoryParser -Definition $definition -RepositoryRoot $resolvedRepositoryRoot -MatchedFiles $matchedFiles -RemoteDocuments $remoteDocuments -SourceRevision $sourceRevision -HostedCatalog $catalog)

$sortedRecords = @(Get-OrdinallySortedRecords -Records @($records))
$inventorySha256 = Get-Sha256 -Content ($sortedRecords | ConvertTo-Json -Depth 20 -Compress)

if ([string]$definition.root.kind -ceq 'repository') {
    $revisionFiles = @(Get-InventoryRevisionFiles -RepositoryRoot $resolvedRepositoryRoot -MatchedFiles $matchedFiles -Records $sortedRecords)
    $snapshotRoot = Join-Path ([IO.Path]::GetTempPath()) ('hosted-source-inventory-snapshot-' + [guid]::NewGuid().ToString('N'))
    try {
        $snapshotRevisionFiles = [Collections.Generic.List[object]]::new()
        foreach ($revisionFile in $revisionFiles) {
            $snapshot = Get-SourceEvidenceFileSnapshot -Path ([string]$revisionFile.FullName)
            $snapshotPath = Join-Path $snapshotRoot ([string]$revisionFile.RelativePath)
            $snapshotDirectory = Split-Path -Parent $snapshotPath
            if (-not (Test-Path -LiteralPath $snapshotDirectory -PathType Container)) {
                $null = New-Item -ItemType Directory -Path $snapshotDirectory -Force
            }
            [IO.File]::WriteAllBytes($snapshotPath, $snapshot.Bytes)
            $snapshotRevisionFiles.Add([pscustomobject]@{ RelativePath = [string]$revisionFile.RelativePath; FullName = $snapshotPath })
        }
        foreach ($behaviorFile in @($contract.behaviorFiles)) {
            $behaviorSourcePath = Join-Path $resolvedRepositoryRoot ([string]$behaviorFile)
            $behaviorSnapshotPath = Join-Path $snapshotRoot ([string]$behaviorFile)
            $behaviorSnapshotDirectory = Split-Path -Parent $behaviorSnapshotPath
            if (-not (Test-Path -LiteralPath $behaviorSnapshotDirectory -PathType Container)) {
                $null = New-Item -ItemType Directory -Path $behaviorSnapshotDirectory -Force
            }
            [IO.File]::WriteAllBytes($behaviorSnapshotPath, (Get-SourceEvidenceFileSnapshot -Path $behaviorSourcePath).Bytes)
        }
        $parserContractSha256 = Get-SourceEvidenceParserContractSha256 -Contract $contract -RepositoryRoot $snapshotRoot
        $snapshotMatchedFiles = @($matchedFiles | ForEach-Object {
            $relativePath = [IO.Path]::GetRelativePath($resolvedRepositoryRoot, [string]$_.FullName).Replace('\', '/')
            [pscustomobject]@{ RelativePath = [string]$_.RelativePath; FullName = Join-Path $snapshotRoot $relativePath }
        })
        $records = @(Invoke-SourceInventoryParser -Definition $definition -RepositoryRoot $snapshotRoot -MatchedFiles $snapshotMatchedFiles -RemoteDocuments @() -SourceRevision $null -HostedCatalog $catalog)
        $sortedRecords = @(Get-OrdinallySortedRecords -Records $records)
        $inventorySha256 = Get-Sha256 -Content ($sortedRecords | ConvertTo-Json -Depth 20 -Compress)
        $worktreeSha256 = Get-CanonicalFileSetSha256 -Files $snapshotRevisionFiles.ToArray()
    }
    finally {
        Remove-Item -LiteralPath $snapshotRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
    $resolvedCommit = $null
    $worktreeDirty = $true
    $git = Get-Command git -ErrorAction SilentlyContinue
    if ($null -ne $git) {
        $headOutput = @(& $git.Source -C $resolvedRepositoryRoot rev-parse HEAD 2>$null)
        if ($LASTEXITCODE -eq 0 -and $headOutput.Count -eq 1 -and $headOutput[0] -match '^[0-9a-fA-F]{40}$') {
            $resolvedCommit = ([string]$headOutput[0]).ToLowerInvariant()
        }
        $statusArguments = @('-C', $resolvedRepositoryRoot, 'status', '--porcelain=v1', '--untracked-files=all', '--') + @($revisionFiles.RelativePath)
        $statusOutput = @(& $git.Source @statusArguments 2>$null)
        if ($LASTEXITCODE -eq 0) {
            $worktreeDirty = $statusOutput.Count -ne 0
        }
    }
    $sourceRevision = [ordered]@{
        kind = 'repository-worktree'
        resolvedCommit = $resolvedCommit
        worktreeDirty = $worktreeDirty
        worktreeSha256 = $worktreeSha256
    }
}
else {
    $snapshotRoot = Join-Path ([IO.Path]::GetTempPath()) ('hosted-source-inventory-behavior-' + [guid]::NewGuid().ToString('N'))
    try {
        foreach ($behaviorFile in @($contract.behaviorFiles)) {
            $behaviorSourcePath = Join-Path $resolvedRepositoryRoot ([string]$behaviorFile)
            $behaviorSnapshotPath = Join-Path $snapshotRoot ([string]$behaviorFile)
            $behaviorSnapshotDirectory = Split-Path -Parent $behaviorSnapshotPath
            if (-not (Test-Path -LiteralPath $behaviorSnapshotDirectory -PathType Container)) {
                $null = New-Item -ItemType Directory -Path $behaviorSnapshotDirectory -Force
            }
            [IO.File]::WriteAllBytes($behaviorSnapshotPath, (Get-SourceEvidenceFileSnapshot -Path $behaviorSourcePath).Bytes)
        }
        $parserContractSha256 = Get-SourceEvidenceParserContractSha256 -Contract $contract -RepositoryRoot $snapshotRoot
        $records = @(Invoke-SourceInventoryParser -Definition $definition -RepositoryRoot $snapshotRoot -MatchedFiles @() -RemoteDocuments $remoteDocuments -SourceRevision $sourceRevision -HostedCatalog $catalog)
        $sortedRecords = @(Get-OrdinallySortedRecords -Records $records)
        $inventorySha256 = Get-Sha256 -Content ($sortedRecords | ConvertTo-Json -Depth 20 -Compress)
    }
    finally {
        Remove-Item -LiteralPath $snapshotRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}

$configuration = [ordered]@{
    sourceDefinitionId = [string]$definition.id
    root = $definition.root
    files = @($definition.files)
    exclude = @($definition.exclude)
    parserId = [string]$definition.parser
    parserContractSha256 = $parserContractSha256
}
$inventoryConfigurationSha256 = Get-Sha256 -Content ($configuration | ConvertTo-Json -Depth 10 -Compress)

$inventory = [ordered]@{
    '$schema' = 'source-inventory.schema.json'
    schemaVersion = 1
    sourceDefinitionId = [string]$definition.id
    sourceDefinitionSha256 = Get-Sha256 -Path $resolvedDefinitionPath
    inventoryConfigurationSha256 = $inventoryConfigurationSha256
    collectorVersion = 1
    parserId = [string]$definition.parser
    parserContractSha256 = $parserContractSha256
    collectedAt = ConvertTo-UtcTimestamp -Value ([DateTime]::UtcNow)
    collection = [ordered]@{
        complete = $true
        sourceRevision = $sourceRevision
        inventorySha256 = $inventorySha256
    }
    records = $sortedRecords
}

$inventoryJson = $inventory | ConvertTo-Json -Depth 30
if (-not (Test-Json -Json $inventoryJson -SchemaFile $inventorySchemaPath -ErrorAction Stop)) {
    throw 'Generated source inventory does not satisfy its schema'
}
Write-JsonAtomically -Path $resolvedOutputPath -Value $inventory

$result = [ordered]@{
    status = 'passed'
    sourceDefinitionId = [string]$definition.id
    parserId = [string]$definition.parser
    recordCount = $records.Count
    outputPath = $resolvedOutputPath
    inventorySha256 = $inventorySha256
}
if ($null -ne $rateLimit) {
    $result.rateLimit = $rateLimit
}
if ($OutputFormat -eq 'Json') {
    $result | ConvertTo-Json -Depth 5
}
else {
    Write-Output "Source inventory generated: $($result.sourceDefinitionId) ($($result.recordCount) records)"
    Write-Output "Output: $($result.outputPath)"
    Write-Output "Inventory SHA-256: $($result.inventorySha256)"
}
