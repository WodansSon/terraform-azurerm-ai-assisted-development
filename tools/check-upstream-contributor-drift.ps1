param(
    [string] $ManifestPath = "tools/config/upstream-contributor.json",
    [ValidateSet("Text", "Json")]
    [string] $OutputFormat = "Text",
    [switch] $FailOnDrift
)

$ErrorActionPreference = "Stop"
$comparisonMode = "deterministic-source-drift-and-explicit-reference-discovery"
$resolvedManifestPath = if ([System.IO.Path]::IsPathRooted($ManifestPath)) {
    $ManifestPath
}
else {
    Join-Path (Get-Location).Path $ManifestPath
}

if (-not (Test-Path -LiteralPath $resolvedManifestPath)) {
    throw "manifest file not found: $ManifestPath"
}

$manifest = Get-Content -LiteralPath $resolvedManifestPath -Raw | ConvertFrom-Json

$repoRoot = Split-Path -Parent $PSScriptRoot
$workingDirectoryRoot = (Get-Location).Path

if (-not $manifest.sources -or $manifest.sources.Count -eq 0) {
    throw "manifest does not contain any sources"
}

if (-not $manifest.catalog) {
    throw "manifest does not contain a catalog section"
}

if (-not $manifest.catalog.contributorTreeUrl) {
    throw "manifest catalog does not contain contributorTreeUrl"
}

if (-not $manifest.catalog.topicContentsApiUrl) {
    throw "manifest catalog does not contain topicContentsApiUrl"
}

function Format-DriftStatusLine {
    param(
        [Parameter(Mandatory = $true)]
        [string] $Status,

        [Parameter(Mandatory = $true)]
        [string] $Name,

        [Parameter(Mandatory = $true)]
        [string] $Detail
    )

    $statusLabel = "[{0}]" -f $Status.ToUpperInvariant()

    return ("{0,-11}{1,-52}: {2}" -f $statusLabel, $Name, $Detail)
}

function Start-DriftStage {
    param(
        [Parameter(Mandatory = $true)]
        [string] $Name
    )

    if ($OutputFormat -eq "Text") {
        Write-Host (Format-DriftStatusLine -Status "running" -Name ("upstream-drift/{0}" -f $Name) -Detail "IN PROGRESS")
    }

    return (Get-Date)
}

function Complete-DriftStage {
    param(
        [Parameter(Mandatory = $true)]
        [string] $Name,

        [Parameter(Mandatory = $true)]
        [datetime] $Started
    )

    if ($OutputFormat -eq "Text") {
        $durationSeconds = [Math]::Round(((Get-Date) - $Started).TotalSeconds, 2)
        Write-Host (Format-DriftStatusLine -Status "passed" -Name ("upstream-drift/{0}" -f $Name) -Detail ("{0}s" -f $durationSeconds))
    }
}

$githubMarkdownRoot = Join-Path $repoRoot ".github"
$docsMarkdownRoot = Join-Path $repoRoot "docs"
$markdownRoots = @($githubMarkdownRoot, $docsMarkdownRoot)

$contributorTreeUrl = $manifest.catalog.contributorTreeUrl.TrimEnd('/')

if (-not (Test-Path -LiteralPath $githubMarkdownRoot) -and -not (Test-Path -LiteralPath $docsMarkdownRoot)) {
    $repoRoot = $workingDirectoryRoot
    $githubMarkdownRoot = Join-Path $repoRoot ".github"
    $docsMarkdownRoot = Join-Path $repoRoot "docs"
    $markdownRoots = @($githubMarkdownRoot, $docsMarkdownRoot)
}

function Convert-ToRepoRelativePath {
    param(
        [Parameter(Mandatory = $true)]
        [string] $FullPath
    )

    $relative = Resolve-Path -LiteralPath $FullPath | ForEach-Object {
        $_.Path.Substring($repoRoot.Length).TrimStart([char[]]@([char]'\', [char]'/' ))
    }

    return ($relative -replace "\\", "/")
}

function Convert-ToCanonicalUpstreamTopicUrl {
    param(
        [Parameter(Mandatory = $true)]
        [string] $Reference
    )

    $trimmed = $Reference.Trim()

    if ([string]::IsNullOrWhiteSpace($trimmed)) {
        return $null
    }

    if ($trimmed.Contains('*') -or $trimmed.Contains('?')) {
        return $null
    }

    if ($trimmed -match '^(https://github\.com/hashicorp/terraform-provider-azurerm/tree/main/contributing/topics/[^)\s]+\.md)$') {
        return $matches[1]
    }

    if ($trimmed -match '^https://raw\.githubusercontent\.com/hashicorp/terraform-provider-azurerm/main/contributing/topics/([^)\s]+\.md)$') {
        return "$contributorTreeUrl/topics/$($matches[1])"
    }

    if ($trimmed -match '^hashicorp/terraform-provider-azurerm/contributing/topics/([^)\s]+\.md)$') {
        return "$contributorTreeUrl/topics/$($matches[1])"
    }

    if ($trimmed -match '^contributing/topics/([^)\s]+\.md)$') {
        return "$contributorTreeUrl/topics/$($matches[1])"
    }

    if ($trimmed -match '^topics/([^)\s]+\.md)$') {
        return "$contributorTreeUrl/topics/$($matches[1])"
    }

    return $null
}

function Get-UpstreamTopicPaths {
    param(
        [Parameter(Mandatory = $true)]
        [string] $ContentsApiUrl
    )

    $pendingUrls = [System.Collections.Generic.Queue[string]]::new()
    $pendingUrls.Enqueue($ContentsApiUrl)
    $topicPaths = @()
    $headers = @{ Accept = "application/vnd.github+json"; "User-Agent" = "terraform-azurerm-ai-toolkit-drift-checker" }
    $token = if (-not [string]::IsNullOrWhiteSpace($env:GITHUB_TOKEN)) {
        $env:GITHUB_TOKEN
    }
    elseif (-not [string]::IsNullOrWhiteSpace($env:GH_TOKEN)) {
        $env:GH_TOKEN
    }

    if (-not [string]::IsNullOrWhiteSpace($token)) {
        $headers.Authorization = "Bearer $token"
    }

    while ($pendingUrls.Count -gt 0) {
        $response = Invoke-RestMethod -Uri $pendingUrls.Dequeue() -Headers $headers
        $entries = @($response)

        foreach ($entry in $entries) {
            if ($entry.type -eq "dir") {
                $pendingUrls.Enqueue($entry.url)
                continue
            }

            if ($entry.type -eq "file" -and $entry.path -match '^contributing/topics/(.+\.md)$') {
                $topicPath = Convert-ToCanonicalUpstreamTopicUrl -Reference $entry.path
                if ($null -ne $topicPath) {
                    $topicPaths += $topicPath
                }
            }
        }
    }

    $topicPaths | Sort-Object -Unique
}

function Get-TrackedTopicMetadata {
    param(
        [Parameter(Mandatory = $true)]
        [object[]] $Sources,
        [Parameter(Mandatory = $true)]
        [string] $TopicBaseRawUrlPrefix
    )

    $Sources |
        Where-Object { $_.rawUrl -like "$TopicBaseRawUrlPrefix*" -and $_.rawUrl -match '/contributing/topics/.+\.md$' } |
        ForEach-Object {
            $path = $null
            if ($_.rawUrl -match '/contributing/topics/(.+\.md)$') {
                $path = Convert-ToCanonicalUpstreamTopicUrl -Reference ("contributing/topics/{0}" -f $matches[1])
            }

            [pscustomobject]@{
                id = $_.id
                title = $_.title
                domain = $_.domain
                rawUrl = $_.rawUrl
                path = $path
            }
        }
}

function Get-CandidateMarkdownFiles {
    $files = @()

    foreach ($root in $markdownRoots) {
        if (Test-Path -LiteralPath $root) {
            $files += Get-ChildItem -LiteralPath $root -Recurse -File -Filter *.md
        }
    }

    $files | Sort-Object FullName -Unique
}

function Get-TopicMatchesFromText {
    param(
        [Parameter(Mandatory = $true)]
        [string] $Text
    )

    $pattern = 'https://github\.com/hashicorp/terraform-provider-azurerm/tree/main/contributing/topics/[^)\s]+\.md|https://raw\.githubusercontent\.com/hashicorp/terraform-provider-azurerm/main/contributing/topics/[^)\s]+\.md|hashicorp/terraform-provider-azurerm/contributing/topics/[^)\s]+\.md|contributing/topics/[^)\s]+\.md|topics/[^)\s]+\.md'

    [regex]::Matches($Text, $pattern) |
        ForEach-Object { Convert-ToCanonicalUpstreamTopicUrl -Reference $_.Value } |
        Where-Object { $null -ne $_ } |
        Sort-Object -Unique
}

function Get-LocalTopicFileReferences {
    Get-CandidateMarkdownFiles | ForEach-Object {
        $file = $_
        $text = Get-Content -LiteralPath $file.FullName -Raw
        $repoRelativePath = Convert-ToRepoRelativePath -FullPath $file.FullName

        Get-TopicMatchesFromText -Text $text | ForEach-Object {
            [pscustomobject]@{
                file = $repoRelativePath
                topicPath = $_
            }
        }
    }
}

function Get-RuleInventory {
    Get-CandidateMarkdownFiles | ForEach-Object {
        $file = $_
        $lines = Get-Content -LiteralPath $file.FullName
        $repoRelativePath = Convert-ToRepoRelativePath -FullPath $file.FullName
        $startIndexes = @()

        for ($i = 0; $i -lt $lines.Count; $i++) {
            if ($lines[$i] -match '^###\s+([A-Z]+-[A-Z]+-\d+):') {
                $startIndexes += [pscustomobject]@{
                    lineIndex = $i
                    ruleId = $matches[1]
                }
            }
        }

        foreach ($start in $startIndexes) {
            $endIndex = $lines.Count
            foreach ($candidate in $startIndexes) {
                if ($candidate.lineIndex -gt $start.lineIndex) {
                    $endIndex = $candidate.lineIndex
                    break
                }
            }

            $section = @($lines[$start.lineIndex..($endIndex - 1)])
            $provenance = $null
            $evidenceLines = @()
            $evidenceIndex = -1

            foreach ($line in $section) {
                if ($line -match '^- \*\*Provenance\*\*:\s*(.+?)\.?\s*$') {
                    $provenance = $matches[1].Trim()
                    break
                }
            }

            for ($i = 0; $i -lt $section.Count; $i++) {
                if ($section[$i] -match '^- \*\*Evidence\*\*:') {
                    $evidenceIndex = $i
                    break
                }
            }

            if ($evidenceIndex -ge 0) {
                for ($i = $evidenceIndex + 1; $i -lt $section.Count; $i++) {
                    $line = $section[$i]

                    if ($line -match '^\s+-\s+') {
                        $evidenceLines += $line.Trim()
                        continue
                    }

                    if ($line.Trim() -eq '') {
                        continue
                    }

                    break
                }
            }

            $evidenceTopicPaths = @($evidenceLines | ForEach-Object { Get-TopicMatchesFromText -Text $_ } | Sort-Object -Unique)

            [pscustomobject]@{
                file = $repoRelativePath
                ruleId = $start.ruleId
                startLine = $start.lineIndex + 1
                provenance = $provenance
                evidenceLines = @($evidenceLines)
                evidenceTopicPaths = @($evidenceTopicPaths)
            }
        }
    }
}

function Get-SourceDriftResults {
    param(
        [Parameter(Mandatory = $true)]
        [object[]] $Sources
    )

    $results = @()

    foreach ($source in $Sources) {
        try {
            $content = (Invoke-WebRequest -UseBasicParsing -Uri $source.rawUrl).Content
            $bytes = [System.Text.Encoding]::UTF8.GetBytes($content)
            $currentHash = [System.BitConverter]::ToString([System.Security.Cryptography.SHA256]::HashData($bytes)).Replace('-', '').ToLowerInvariant()

            $results += [pscustomobject]@{
                id = $source.id
                title = $source.title
                domain = $source.domain
                rawUrl = $source.rawUrl
                referenceUrl = $source.referenceUrl
                baselineSha256 = $source.baselineSha256
                currentSha256 = $currentHash
                status = if ($currentHash -eq $source.baselineSha256) { "unchanged" } else { "changed" }
                reviewNotes = @($source.reviewNotes)
            }
        }
        catch {
            $results += [pscustomobject]@{
                id = $source.id
                title = $source.title
                domain = $source.domain
                rawUrl = $source.rawUrl
                referenceUrl = $source.referenceUrl
                baselineSha256 = $source.baselineSha256
                currentSha256 = $null
                status = "fetch-failed"
                reviewNotes = @($source.reviewNotes)
                error = $_.Exception.Message
            }
        }
    }

    $results
}

$stageStarted = Start-DriftStage -Name "discover-upstream-topics"
$upstreamTopicPaths = Get-UpstreamTopicPaths -ContentsApiUrl $manifest.catalog.topicContentsApiUrl
Complete-DriftStage -Name "discover-upstream-topics" -Started $stageStarted

$stageStarted = Start-DriftStage -Name "scan-local-guidance"
$trackedTopicMetadata = Get-TrackedTopicMetadata -Sources @($manifest.sources) -TopicBaseRawUrlPrefix $manifest.catalog.topicBaseRawUrlPrefix
$trackedTopicPaths = @($trackedTopicMetadata.path | Sort-Object -Unique)
$markdownFiles = @(& {
    foreach ($root in $markdownRoots) {
        if (Test-Path -LiteralPath $root) {
            Get-ChildItem -LiteralPath $root -Recurse -File -Filter *.md
        }
    }
} | Sort-Object FullName -Unique)
$markdownFilePaths = @($markdownFiles | Where-Object { $null -ne $_ -and $null -ne $_.FullName } | ForEach-Object { $_.FullName })
$localTopicFileReferences = @()
if ($markdownFilePaths.Count -gt 0 -and (Get-Command rg -ErrorAction SilentlyContinue)) {
    Push-Location $repoRoot
    try {
        $pattern = 'https://github\.com/hashicorp/terraform-provider-azurerm/tree/main/contributing/topics/[^)\s]+\.md|https://raw\.githubusercontent\.com/hashicorp/terraform-provider-azurerm/main/contributing/topics/[^)\s]+\.md|hashicorp/terraform-provider-azurerm/contributing/topics/[^)\s]+\.md|contributing/topics/[^)\s]+\.md|topics/[^)\s]+\.md'
        $localTopicFileReferences = @(& {
            & rg --no-heading -n -o $pattern .github docs
        } | ForEach-Object {
            if ($_ -match '^(?<file>[^:]+):(?<line>\d+):(?<topic>.+)$') {
                $topicPath = Convert-ToCanonicalUpstreamTopicUrl -Reference $matches.topic
                if ($null -ne $topicPath) {
                    [pscustomobject]@{
                        file = ($matches.file -replace '\\', '/')
                        topicPath = $topicPath
                    }
                }
            }
        })
    }
    finally {
        Pop-Location
    }
}
elseif ($markdownFilePaths.Count -gt 0) {
    $pattern = 'https://github\.com/hashicorp/terraform-provider-azurerm/tree/main/contributing/topics/[^)\s]+\.md|https://raw\.githubusercontent\.com/hashicorp/terraform-provider-azurerm/main/contributing/topics/[^)\s]+\.md|hashicorp/terraform-provider-azurerm/contributing/topics/[^)\s]+\.md|contributing/topics/[^)\s]+\.md|topics/[^)\s]+\.md'
    $localTopicFileReferences = @(Select-String -Path $markdownFilePaths -Pattern $pattern -AllMatches | ForEach-Object {
        $repoRelativePath = Convert-ToRepoRelativePath -FullPath $_.Path
        foreach ($topicPath in @($_.Matches | ForEach-Object { Convert-ToCanonicalUpstreamTopicUrl -Reference $_.Value } | Where-Object { $null -ne $_ } | Sort-Object -Unique)) {
            [pscustomobject]@{
                file = $repoRelativePath
                topicPath = $topicPath
            }
        }
    })
}
$ruleInventory = @($markdownFiles | ForEach-Object {
    $file = $_
    $lines = Get-Content -LiteralPath $file.FullName
    $repoRelativePath = Convert-ToRepoRelativePath -FullPath $file.FullName
    $startIndexes = @()

    for ($i = 0; $i -lt $lines.Count; $i++) {
        if ($lines[$i] -match '^###\s+([A-Z]+-[A-Z]+-\d+):') {
            $startIndexes += [pscustomobject]@{
                lineIndex = $i
                ruleId = $matches[1]
            }
        }
    }

    foreach ($start in $startIndexes) {
        $endIndex = $lines.Count
        foreach ($candidate in $startIndexes) {
            if ($candidate.lineIndex -gt $start.lineIndex) {
                $endIndex = $candidate.lineIndex
                break
            }
        }

        $section = @($lines[$start.lineIndex..($endIndex - 1)])
        $provenance = $null
        $evidenceLines = @()
        $evidenceIndex = -1

        foreach ($line in $section) {
            if ($line -match '^- \*\*Provenance\*\*:\s*(.+?)\.?\s*$') {
                $provenance = $matches[1].Trim()
                break
            }
        }

        for ($i = 0; $i -lt $section.Count; $i++) {
            if ($section[$i] -match '^- \*\*Evidence\*\*:') {
                $evidenceIndex = $i
                break
            }
        }

        if ($evidenceIndex -ge 0) {
            for ($i = $evidenceIndex + 1; $i -lt $section.Count; $i++) {
                $line = $section[$i]

                if ($line -match '^\s+-\s+') {
                    $evidenceLines += $line.Trim()
                    continue
                }

                if ($line.Trim() -eq '') {
                    continue
                }

                break
            }
        }

        $evidenceTopicPaths = @($evidenceLines | ForEach-Object { Get-TopicMatchesFromText -Text $_ } | Sort-Object -Unique)

        [pscustomobject]@{
            file = $repoRelativePath
            ruleId = $start.ruleId
            startLine = $start.lineIndex + 1
            provenance = $provenance
            evidenceLines = @($evidenceLines)
            evidenceTopicPaths = @($evidenceTopicPaths)
        }
    }
})
$dynamicRuleTopicReferences = @($ruleInventory | Where-Object { $_.evidenceTopicPaths.Count -gt 0 })
$localTopicFileReferencesByPath = @()
if ($localTopicFileReferences.Count -gt 0) {
    $localTopicFileReferencesByPath = @($localTopicFileReferences | Group-Object topicPath | Sort-Object Name | ForEach-Object {
        [pscustomobject]@{
            topicPath = $_.Name
            files = @($_.Group.file | Sort-Object -Unique)
        }
    })
}
$allLocalTopicReferencePaths = @(($localTopicFileReferencesByPath.topicPath + $dynamicRuleTopicReferences.evidenceTopicPaths) | Sort-Object -Unique)
$ruleReferencesByTopicPath = @($dynamicRuleTopicReferences | ForEach-Object {
    foreach ($topicPath in $_.evidenceTopicPaths) {
        [pscustomobject]@{
            topicPath = $topicPath
            file = $_.file
            ruleId = $_.ruleId
            startLine = $_.startLine
        }
    }
} | Group-Object topicPath | Sort-Object Name | ForEach-Object {
    [pscustomobject]@{
        topicPath = $_.Name
        rules = @($_.Group | Sort-Object file, ruleId)
    }
})
Complete-DriftStage -Name "scan-local-guidance" -Started $stageStarted

$stageStarted = Start-DriftStage -Name "evaluate-catalog-and-rules"
$untrackedUpstreamTopicPaths = @($upstreamTopicPaths | Where-Object { $trackedTopicPaths -notcontains $_ } | Sort-Object -Unique)
$dynamicallyReferencedTrackedTopicPaths = @($trackedTopicPaths | Where-Object { $allLocalTopicReferencePaths -contains $_ } | Sort-Object -Unique)
$trackedTopicPathsWithoutExplicitLocalReferences = @($trackedTopicPaths | Where-Object { $allLocalTopicReferencePaths -notcontains $_ } | Sort-Object -Unique)
$dynamicallyMappedUntrackedTopicPaths = @($untrackedUpstreamTopicPaths | Where-Object { $allLocalTopicReferencePaths -contains $_ } | Sort-Object -Unique)
$uncoveredUpstreamTopicPaths = @($untrackedUpstreamTopicPaths | Where-Object { $allLocalTopicReferencePaths -notcontains $_ } | Sort-Object -Unique)
$staleTrackedTopicPaths = @($trackedTopicPaths | Where-Object { $upstreamTopicPaths -notcontains $_ } | Sort-Object -Unique)
$staleLocalTopicReferencePaths = @($allLocalTopicReferencePaths | Where-Object { $upstreamTopicPaths -notcontains $_ } | Sort-Object -Unique)

$ruleIssues = @($ruleInventory | ForEach-Object {
    $status = "ok"
    $recommendedAction = $null

    if ($_.provenance -eq "Published upstream standard") {
        if ($_.evidenceTopicPaths.Count -eq 0) {
            $status = "missing-upstream-topic-reference"
            $recommendedAction = 'add at least one exact upstream `https://github.com/hashicorp/terraform-provider-azurerm/tree/main/contributing/topics/*.md` reference, or another supported canonicalizable upstream topic reference, in the rule evidence block; otherwise downgrade the provenance label if the rule is not directly upstream-backed'
        }
        elseif (@($_.evidenceTopicPaths | Where-Object { $upstreamTopicPaths -notcontains $_ }).Count -gt 0) {
            $status = "stale-upstream-topic-reference"
            $recommendedAction = 'update the evidence block to point to a current upstream contributor topic before keeping this rule as `Published upstream standard`'
        }
    }

    if ($status -ne "ok") {
        [pscustomobject]@{
            file = $_.file
            ruleId = $_.ruleId
            startLine = $_.startLine
            provenance = $_.provenance
            evidenceTopicPaths = @($_.evidenceTopicPaths)
            status = $status
            recommendedAction = $recommendedAction
        }
    }
})

$ruleIssueCountsByFile = @($ruleIssues | Group-Object file | ForEach-Object {
    [pscustomobject]@{
        file = $_.Name
        issueCount = $_.Count
    }
})
$rulesByFile = @($ruleInventory | Group-Object file | Sort-Object Name | ForEach-Object {
    $fileName = $_.Name
    $issueCountEntry = $ruleIssueCountsByFile | Where-Object { $_.file -eq $fileName } | Select-Object -First 1
    $issueCount = if ($issueCountEntry) { $issueCountEntry.issueCount } else { 0 }

    [pscustomobject]@{
        file = $fileName
        ruleCount = $_.Count
        issueCount = $issueCount
        rules = @($_.Group | Sort-Object ruleId)
    }
})
$ruleIssuesByFile = @($ruleIssues | Group-Object file | Sort-Object Name | ForEach-Object {
    [pscustomobject]@{
        file = $_.Name
        issueCount = $_.Count
        rules = @($_.Group | Sort-Object ruleId)
    }
})
Complete-DriftStage -Name "evaluate-catalog-and-rules" -Started $stageStarted

$stageStarted = Start-DriftStage -Name "fetch-and-map-tracked-sources"
$sourceResults = Get-SourceDriftResults -Sources @($manifest.sources) | ForEach-Object {
    $source = $_
    $topicPath = $null
    if ($source.rawUrl -match '/contributing/topics/(.+\.md)$') {
        $topicPath = Convert-ToCanonicalUpstreamTopicUrl -Reference ("contributing/topics/{0}" -f $matches[1])
    }

    $fileReferenceEntry = $null
    $ruleReferenceEntry = $null

    if ($topicPath) {
        $fileReferenceEntry = $localTopicFileReferencesByPath | Where-Object { $_.topicPath -eq $topicPath } | Select-Object -First 1
        $ruleReferenceEntry = $ruleReferencesByTopicPath | Where-Object { $_.topicPath -eq $topicPath } | Select-Object -First 1
    }
    elseif (-not [string]::IsNullOrWhiteSpace($source.referenceUrl)) {
        $referenceUrls = @($source.referenceUrl, $source.rawUrl) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Sort-Object -Unique
        $referencedFiles = @($markdownFiles | Where-Object {
            $text = Get-Content -LiteralPath $_.FullName -Raw
            @($referenceUrls | Where-Object { $text.Contains($_) }).Count -gt 0
        } | ForEach-Object { Convert-ToRepoRelativePath -FullPath $_.FullName } | Sort-Object -Unique)
        $referencedRules = @($ruleInventory | Where-Object {
            $evidenceText = $_.evidenceLines -join "`n"
            @($referenceUrls | Where-Object { $evidenceText.Contains($_) }).Count -gt 0
        } | ForEach-Object {
            [pscustomobject]@{
                file = $_.file
                ruleId = $_.ruleId
                startLine = $_.startLine
            }
        } | Sort-Object file, ruleId)

        if ($referencedFiles.Count -gt 0) {
            $fileReferenceEntry = [pscustomobject]@{ files = $referencedFiles }
        }
        if ($referencedRules.Count -gt 0) {
            $ruleReferenceEntry = [pscustomobject]@{ rules = $referencedRules }
        }
    }

    [pscustomobject]@{
        id = $source.id
        title = $source.title
        domain = $source.domain
        rawUrl = $source.rawUrl
        referenceUrl = $source.referenceUrl
        topicPath = $topicPath
        baselineSha256 = $source.baselineSha256
        currentSha256 = $source.currentSha256
        status = $source.status
        reviewNotes = @($source.reviewNotes)
        dynamicReferencedFiles = if ($fileReferenceEntry) { @($fileReferenceEntry.files) } else { @() }
        dynamicReferencedRules = if ($ruleReferenceEntry) { @($ruleReferenceEntry.rules) } else { @() }
        error = $source.error
    }
}
Complete-DriftStage -Name "fetch-and-map-tracked-sources" -Started $stageStarted

$changed = @($sourceResults | Where-Object { $_.status -eq "changed" })
$failed = @($sourceResults | Where-Object { $_.status -eq "fetch-failed" })
$unmappedReferenceSources = @($sourceResults | Where-Object {
    -not [string]::IsNullOrWhiteSpace($_.referenceUrl) -and
    $_.dynamicReferencedFiles.Count -eq 0 -and
    $_.dynamicReferencedRules.Count -eq 0
})
$sourceReferenceIssueCount = $unmappedReferenceSources.Count
$catalogIssueCount = $uncoveredUpstreamTopicPaths.Count + $staleTrackedTopicPaths.Count + $staleLocalTopicReferencePaths.Count + $trackedTopicPathsWithoutExplicitLocalReferences.Count
$semanticReviewRequired = ($changed.Count -gt 0 -or $failed.Count -gt 0 -or $ruleIssues.Count -gt 0 -or $sourceReferenceIssueCount -gt 0 -or $catalogIssueCount -gt 0 -or $dynamicallyMappedUntrackedTopicPaths.Count -gt 0)

if ($OutputFormat -eq "Json") {
    [pscustomobject]@{
        manifest = $ManifestPath
        comparisonMode = $comparisonMode
        performsSemanticComparison = $false
        usesHeuristics = $false
        semanticReviewRequired = $semanticReviewRequired
        semanticReviewGuidance = 'This script uses pure logic only: upstream topic discovery, tracked-source hash comparison, explicit local reference discovery, and rule evidence validation. It canonicalizes contributor-topic references against the remote contributor-doc root and maps non-catalog sources through exact manifest-declared reference URLs. It does not use heuristics or AI to infer semantic mappings inside the detector. Exact-reference aggregation only proves links that are already explicitly present in repo content. If `changedCount`, `sourceReferenceIssueCount`, `catalogIssueCount`, `ruleIssueCount`, `trackedTopicPathsWithoutExplicitLocalReferences`, or `dynamicallyMappedUntrackedTopicPaths` is non-zero, follow up with an AI-assisted semantic maintainer review to decide whether uncovered or changed upstream sources should change local guidance, whether new tracked sources are needed, and whether provenance or evidence updates are required.'
        diagnostics = [pscustomobject]@{
            markdownFileCount = $markdownFiles.Count
            markdownFilePathCount = $markdownFilePaths.Count
            localTopicReferenceCount = $localTopicFileReferences.Count
            localTopicReferenceGroupCount = $localTopicFileReferencesByPath.Count
            ruleInventoryCount = $ruleInventory.Count
            dynamicRuleTopicReferenceCount = $dynamicRuleTopicReferences.Count
            ruleReferenceGroupCount = $ruleReferencesByTopicPath.Count
        }
        totalSources = $sourceResults.Count
        changedCount = $changed.Count
        failedCount = $failed.Count
        ruleIssueCount = $ruleIssues.Count
        sourceReferenceIssueCount = $sourceReferenceIssueCount
        catalogIssueCount = $catalogIssueCount
        catalog = [pscustomobject]@{
            contributorTreeUrl = $contributorTreeUrl
            readmeRawUrl = $manifest.catalog.readmeRawUrl
            topicContentsApiUrl = $manifest.catalog.topicContentsApiUrl
            discoveryMode = "github-contents-api"
            upstreamTopicPaths = $upstreamTopicPaths
            trackedTopicPaths = $trackedTopicPaths
            dynamicallyReferencedTrackedTopicPaths = $dynamicallyReferencedTrackedTopicPaths
            trackedTopicPathsWithoutExplicitLocalReferences = $trackedTopicPathsWithoutExplicitLocalReferences
            dynamicallyMappedUntrackedTopicPaths = $dynamicallyMappedUntrackedTopicPaths
            uncoveredUpstreamTopicPaths = $uncoveredUpstreamTopicPaths
            staleTrackedTopicPaths = $staleTrackedTopicPaths
            staleLocalTopicReferencePaths = $staleLocalTopicReferencePaths
            localTopicFileReferencesByPath = $localTopicFileReferencesByPath
            ruleReferencesByTopicPath = $ruleReferencesByTopicPath
        }
        rulesByFile = $rulesByFile
        ruleIssuesByFile = $ruleIssuesByFile
        ruleIssues = $ruleIssues
        unmappedReferenceSources = $unmappedReferenceSources
        sources = $sourceResults
    } | ConvertTo-Json -Depth 7
}
else {
    Write-Host "Upstream Contributor Drift Report"
    Write-Host "Manifest: $ManifestPath"
    Write-Host "Comparison Mode: $comparisonMode"
    Write-Host "Performs Semantic Comparison: false"
    Write-Host "Uses Heuristics: false"
    Write-Host "Sources Checked: $($sourceResults.Count)"
    Write-Host "Changed: $($changed.Count)"
    Write-Host "Fetch Failed: $($failed.Count)"
    Write-Host "Rule Issues: $($ruleIssues.Count)"
    Write-Host "Source Reference Issues: $sourceReferenceIssueCount"
    Write-Host "Catalog Issues: $catalogIssueCount"
    Write-Host "Semantic Review Required: $semanticReviewRequired"
    Write-Host ("Diagnostics: markdown files={0}, markdown paths={1}, local topic refs={2}, local topic groups={3}, rule inventory={4}, dynamic rule refs={5}, rule topic groups={6}" -f $markdownFiles.Count, $markdownFilePaths.Count, $localTopicFileReferences.Count, $localTopicFileReferencesByPath.Count, $ruleInventory.Count, $dynamicRuleTopicReferences.Count, $ruleReferencesByTopicPath.Count)
    Write-Host ("Canonical Contributor Root: {0}" -f $contributorTreeUrl)
    Write-Host "Note: This script uses pure logic only. It compares tracked source hashes, discovers current upstream topics, canonicalizes contributor-topic references, and maps non-catalog sources through exact manifest-declared reference URLs. Exact-reference aggregation proves existing explicit links only; AI semantic review is still required for uncovered, changed, merged, renamed, or structurally revised upstream sources."
    Write-Host ""

    Write-Host "Catalog Coverage Summary"
    Write-Host ("  upstream topics                         : {0}" -f $upstreamTopicPaths.Count)
    Write-Host ("  tracked upstream topics                 : {0}" -f $trackedTopicPaths.Count)
    Write-Host ("  dynamically referenced tracked topics   : {0}" -f $dynamicallyReferencedTrackedTopicPaths.Count)
    Write-Host ("  dynamically mapped untracked topics     : {0}" -f $dynamicallyMappedUntrackedTopicPaths.Count)
    Write-Host ("  uncovered upstream topics               : {0}" -f $uncoveredUpstreamTopicPaths.Count)
    Write-Host ("  stale tracked topics                    : {0}" -f $staleTrackedTopicPaths.Count)
    Write-Host ("  stale local topic references            : {0}" -f $staleLocalTopicReferencePaths.Count)

    foreach ($path in $trackedTopicPathsWithoutExplicitLocalReferences) {
        Write-Host ("  tracked-without-explicit-local-reference: {0}" -f $path)
    }

    foreach ($path in $dynamicallyMappedUntrackedTopicPaths) {
        Write-Host ("  dynamically-mapped-untracked-topic      : {0}" -f $path)
    }

    foreach ($path in $uncoveredUpstreamTopicPaths) {
        Write-Host ("  uncovered-upstream-topic                : {0}" -f $path)
    }

    foreach ($path in $staleTrackedTopicPaths) {
        Write-Host ("  stale-tracked-topic                     : {0}" -f $path)
    }

    foreach ($path in $staleLocalTopicReferencePaths) {
        Write-Host ("  stale-local-topic-reference             : {0}" -f $path)
    }

    foreach ($source in $unmappedReferenceSources) {
        Write-Host ("  unmapped-source-reference               : {0} ({1})" -f $source.id, $source.referenceUrl)
    }

    Write-Host ""

    foreach ($result in $sourceResults) {
        Write-Host ("[{0}] {1}" -f $result.status.ToUpperInvariant(), $result.title)
        Write-Host ("  domain: {0}" -f $result.domain)
        Write-Host ("  source: {0}" -f $result.rawUrl)

        if ($result.referenceUrl) {
            Write-Host ("  reference: {0}" -f $result.referenceUrl)
        }

        if ($result.topicPath) {
            Write-Host ("  topic : {0}" -f $result.topicPath)
        }

        if ($result.status -eq "changed") {
            Write-Host ("  baseline: {0}" -f $result.baselineSha256)
            Write-Host ("  current : {0}" -f $result.currentSha256)
        }

        if ($result.status -eq "fetch-failed") {
            Write-Host ("  error   : {0}" -f $result.error)
        }

        foreach ($note in @($result.reviewNotes)) {
            Write-Host ("  review  : {0}" -f $note)
        }

        foreach ($file in @($result.dynamicReferencedFiles)) {
            Write-Host ("  local-file: {0}" -f $file)
        }

        foreach ($rule in @($result.dynamicReferencedRules)) {
            Write-Host ("  local-rule: {0} ({1}:{2})" -f $rule.ruleId, $rule.file, $rule.startLine)
        }

        Write-Host ""
    }

    if ($ruleIssuesByFile.Count -gt 0) {
        Write-Host "Rule Issue Summary"
        foreach ($fileGroup in $ruleIssuesByFile) {
            Write-Host ("  {0}: {1} issue(s)" -f $fileGroup.file, $fileGroup.issueCount)
            foreach ($rule in @($fileGroup.rules)) {
                Write-Host ("    {0} ({1})" -f $rule.ruleId, $rule.status)
            }
        }
        Write-Host ""
    }

    if ($rulesByFile.Count -gt 0) {
        Write-Host "Local Rule File Summary"
        foreach ($fileGroup in $rulesByFile) {
            Write-Host ("  {0}: {1} rule(s), {2} issue(s)" -f $fileGroup.file, $fileGroup.ruleCount, $fileGroup.issueCount)
        }
        Write-Host ""
    }

    if ($semanticReviewRequired) {
        Write-Host "Recommended Next Step"
        Write-Host "  Run an AI-assisted semantic maintainer review to decide whether changed tracked sources, non-catalog sources without exact local references, newly uncovered upstream topics, tracked topics without explicit local references, dynamically mapped untracked topics, stale tracked topics, or stale local references require updates to local guidance, evidence, or tracked-source baselines."
        Write-Host ""
    }
}

if ($failed.Count -gt 0) {
    exit 1
}

if ($FailOnDrift -and ($changed.Count -gt 0 -or $catalogIssueCount -gt 0 -or $ruleIssues.Count -gt 0 -or $sourceReferenceIssueCount -gt 0 -or $dynamicallyMappedUntrackedTopicPaths.Count -gt 0)) {
    exit 2
}

exit 0
