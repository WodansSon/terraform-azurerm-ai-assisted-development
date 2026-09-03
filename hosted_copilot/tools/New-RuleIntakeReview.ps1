[CmdletBinding()]
param(
    [string]$RepositoryRoot = (Join-Path $PSScriptRoot '../..'),

    [string]$HostedCatalogPath = (Join-Path $PSScriptRoot '../copilot-rule-catalog/instruction-catalog.json'),

    [string]$IntakeLedgerPath = (Join-Path $PSScriptRoot '../copilot-rule-catalog/interactive-intake-ledger.json'),

    [string]$InteractiveCatalogPath = (Join-Path $PSScriptRoot '../../tools/interactive-rule-catalog/rule-catalog.json'),

    [string]$UpstreamBaselineDirectory,

    [string]$UpstreamCurrentDirectory,

    [string]$UpstreamCurrentCommit,

    [string]$OutputPath,

    [ValidateSet('Text', 'Json')]
    [string]$OutputFormat = 'Text'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$validationOutputModulePath = Join-Path $PSScriptRoot '../../tools/ValidationOutput.psm1'
Import-Module -Name $validationOutputModulePath -Force

$resolvedRepositoryRoot = [IO.Path]::GetFullPath($RepositoryRoot)
$resolvedHostedCatalogPath = [IO.Path]::GetFullPath($HostedCatalogPath)
$resolvedLedgerPath = [IO.Path]::GetFullPath($IntakeLedgerPath)
$resolvedInteractiveCatalogPath = [IO.Path]::GetFullPath($InteractiveCatalogPath)
$hostedCatalogSchemaPath = Join-Path (Split-Path -Parent $resolvedHostedCatalogPath) 'instruction-catalog.schema.json'
$ledgerSchemaPath = Join-Path (Split-Path -Parent $resolvedLedgerPath) 'interactive-intake-ledger.schema.json'
$interactiveCatalogSchemaPath = Join-Path (Split-Path -Parent $resolvedInteractiveCatalogPath) 'rule-catalog.schema.json'
$bundleSchemaPath = Join-Path (Split-Path -Parent $resolvedHostedCatalogPath) 'rule-intake-review.schema.json'
$guidanceCapacityPath = Join-Path $PSScriptRoot 'Get-GuidanceCapacity.ps1'
$resolvedHostedRoot = Split-Path -Parent (Split-Path -Parent $resolvedHostedCatalogPath)

function Get-FileSha256 {
    param([Parameter(Mandatory = $true)][string]$Path)

    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function Get-ContentSha256 {
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string]$Content
    )

    $bytes = [Text.Encoding]::UTF8.GetBytes($Content)
    return [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($bytes)).ToLowerInvariant()
}

function Get-NormalizedRuleText {
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [AllowEmptyString()]
        [string[]]$Lines
    )

    $contentEnd = $Lines.Count - 1
    while ($contentEnd -ge 0 -and [string]::IsNullOrWhiteSpace($Lines[$contentEnd])) {
        $contentEnd--
    }
    if ($contentEnd -ge 0 -and $Lines[$contentEnd] -eq '---') {
        $contentEnd--
        while ($contentEnd -ge 0 -and [string]::IsNullOrWhiteSpace($Lines[$contentEnd])) {
            $contentEnd--
        }
    }
    if ($contentEnd -lt 0) {
        return ''
    }

    return ((@($Lines[0..$contentEnd]) | ForEach-Object { $_.TrimEnd() }) -join "`n").TrimEnd()
}

function Get-InteractiveRuleTextById {
    param(
        [Parameter(Mandatory = $true)][string]$Root,
        [Parameter(Mandatory = $true)][object[]]$Rules
    )

    $result = @{}
    foreach ($contractGroup in @($Rules | Where-Object status -ne 'retired' | Group-Object contractPath)) {
        $contractPath = [IO.Path]::GetFullPath((Join-Path $Root ([string]$contractGroup.Name)))
        $rootPrefix = $Root.TrimEnd([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar) + [IO.Path]::DirectorySeparatorChar
        if (-not $contractPath.StartsWith($rootPrefix, [StringComparison]::OrdinalIgnoreCase)) {
            throw "Interactive contract path escapes the repository root: $($contractGroup.Name)"
        }
        if (-not (Test-Path -LiteralPath $contractPath -PathType Leaf)) {
            throw "Interactive contract was not found: $($contractGroup.Name)"
        }

        $lines = @(Get-Content -LiteralPath $contractPath)
        for ($lineIndex = 0; $lineIndex -lt $lines.Count; $lineIndex++) {
            if ($lines[$lineIndex] -notmatch '^### (?<id>[A-Z]+(?:-[A-Z0-9]+)+-[0-9]{3}[A-Z]?): (?<title>.+)$') {
                continue
            }

            $ruleId = [string]$Matches['id']
            $endIndex = $lineIndex + 1
            while ($endIndex -lt $lines.Count -and $lines[$endIndex] -notmatch '^#{2,3} ' -and $lines[$endIndex] -notmatch '^<!-- [A-Z0-9-]+-CONTRACT-EOF -->$') {
                $endIndex++
            }
            $normalizedText = Get-NormalizedRuleText -Lines @($lines[$lineIndex..($endIndex - 1)])
            $result[$ruleId] = $normalizedText
        }
    }

    return $result
}

function Get-UpstreamRelativePath {
    param([Parameter(Mandatory = $true)][string]$RawUrl)

    $match = [regex]::Match($RawUrl, '^https://raw\.githubusercontent\.com/[^/]+/[^/]+/[^/]+/(?<path>.+)$')
    if (-not $match.Success) {
        throw "Unsupported upstream raw URL: $RawUrl"
    }
    return $match.Groups['path'].Value
}

function Get-UpstreamContent {
    param(
        [Parameter(Mandatory = $true)][string]$Repository,
        [Parameter(Mandatory = $true)][string]$Commit,
        [Parameter(Mandatory = $true)][string]$RelativePath,
        [string]$Directory
    )

    if (-not [string]::IsNullOrWhiteSpace($Directory)) {
        $root = [IO.Path]::GetFullPath($Directory)
        $path = [IO.Path]::GetFullPath((Join-Path $root $RelativePath.Replace('/', [IO.Path]::DirectorySeparatorChar)))
        $rootPrefix = $root.TrimEnd([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar) + [IO.Path]::DirectorySeparatorChar
        if (-not $path.StartsWith($rootPrefix, [StringComparison]::OrdinalIgnoreCase)) {
            throw "Upstream fixture path escapes its root: $RelativePath"
        }
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
            throw "Upstream fixture was not found: $path"
        }
        return [IO.File]::ReadAllText($path)
    }

    $uri = "https://raw.githubusercontent.com/$Repository/$Commit/$RelativePath"
    return (Invoke-WebRequest -UseBasicParsing -Uri $uri).Content
}

function Get-CurrentUpstreamCommit {
    param(
        [Parameter(Mandatory = $true)][string]$Repository,
        [Parameter(Mandatory = $true)][string]$Ref,
        [string]$RequestedCommit
    )

    if (-not [string]::IsNullOrWhiteSpace($RequestedCommit)) {
        if ($RequestedCommit -notmatch '^[0-9a-f]{40}$') {
            throw 'UpstreamCurrentCommit must be a lowercase 40-character Git commit hash'
        }
        return $RequestedCommit
    }

    $headers = @{ 'User-Agent' = 'terraform-azurerm-ai-assisted-development' }
    $response = Invoke-RestMethod -Uri "https://api.github.com/repos/$Repository/commits/$Ref" -Headers $headers
    return [string]$response.sha
}

foreach ($requiredPath in @($resolvedHostedCatalogPath, $hostedCatalogSchemaPath, $resolvedLedgerPath, $ledgerSchemaPath, $resolvedInteractiveCatalogPath, $interactiveCatalogSchemaPath, $bundleSchemaPath, $guidanceCapacityPath)) {
    if (-not (Test-Path -LiteralPath $requiredPath -PathType Leaf)) {
        throw "Required rule intake file was not found: $requiredPath"
    }
}

$hostedCatalogContent = Get-Content -LiteralPath $resolvedHostedCatalogPath -Raw
if (-not ($hostedCatalogContent | Test-Json -SchemaFile $hostedCatalogSchemaPath -ErrorAction Stop)) {
    throw 'Hosted instruction catalog schema validation failed'
}
$ledgerContent = Get-Content -LiteralPath $resolvedLedgerPath -Raw
if (-not ($ledgerContent | Test-Json -SchemaFile $ledgerSchemaPath -ErrorAction Stop)) {
    throw 'Interactive intake ledger schema validation failed'
}
$interactiveCatalogContent = Get-Content -LiteralPath $resolvedInteractiveCatalogPath -Raw
if (-not ($interactiveCatalogContent | Test-Json -SchemaFile $interactiveCatalogSchemaPath -ErrorAction Stop)) {
    throw 'Interactive rule catalog schema validation failed'
}

$hostedCatalog = $hostedCatalogContent | ConvertFrom-Json
$ledger = $ledgerContent | ConvertFrom-Json
$interactiveCatalog = $interactiveCatalogContent | ConvertFrom-Json
$currentUpstreamCommit = Get-CurrentUpstreamCommit -Repository ([string]$hostedCatalog.upstreamSnapshot.repository) -Ref ([string]$hostedCatalog.upstreamSnapshot.currentRef) -RequestedCommit $UpstreamCurrentCommit
$capacityOutput = @(& pwsh -NoProfile -File $guidanceCapacityPath -HostedRoot $resolvedHostedRoot -OutputFormat Json 2>&1)
if ($LASTEXITCODE -ne 0) {
    throw "Hosted guidance capacity collection failed: $(($capacityOutput | Out-String).Trim())"
}
$guidanceCapacity = ($capacityOutput | Out-String) | ConvertFrom-Json

$hostedRulesById = @{}
foreach ($rule in @($hostedCatalog.rules)) {
    $hostedRulesById[[string]$rule.id] = $rule
}
$placementsByRuleId = @{}
foreach ($surface in @($hostedCatalog.surfaces)) {
    foreach ($section in @($surface.sections)) {
        foreach ($ruleId in @($section.ruleIds)) {
            $id = [string]$ruleId
            if (-not $placementsByRuleId.ContainsKey($id)) {
                $placementsByRuleId[$id] = New-Object 'System.Collections.Generic.List[object]'
            }
            $placementsByRuleId[$id].Add([pscustomobject]@{
                surfaceId = [string]$surface.id
                sectionHeading = [string]$section.heading
            })
        }
    }
}

$upstreamCandidates = New-Object 'System.Collections.Generic.List[object]'
foreach ($source in @($hostedCatalog.sources)) {
    $relativePath = Get-UpstreamRelativePath -RawUrl ([string]$source.rawUrl)
    $baselineContent = Get-UpstreamContent -Repository ([string]$hostedCatalog.upstreamSnapshot.repository) -Commit ([string]$hostedCatalog.upstreamSnapshot.baselineCommit) -RelativePath $relativePath -Directory $UpstreamBaselineDirectory
    $baselineHash = Get-ContentSha256 -Content $baselineContent
    if ($baselineHash -ne [string]$source.baselineSha256) {
        throw "Pinned upstream baseline does not match catalog hash for $($source.id)"
    }
    $currentContent = Get-UpstreamContent -Repository ([string]$hostedCatalog.upstreamSnapshot.repository) -Commit $currentUpstreamCommit -RelativePath $relativePath -Directory $UpstreamCurrentDirectory
    $currentHash = Get-ContentSha256 -Content $currentContent
    $changed = $currentHash -ne $baselineHash
    $upstreamCandidates.Add([pscustomobject]@{
        id = [string]$source.id
        title = [string]$source.title
        referenceUrl = [string]$source.referenceUrl
        baselineSha256 = $baselineHash
        currentSha256 = $currentHash
        state = if ($changed) { 'changed' } else { 'current' }
        requiresReview = $changed
        affectedHostedRuleIds = @($hostedCatalog.rules | Where-Object { $_.status -eq 'active' -and $_.sourceIds -contains $source.id } | ForEach-Object { [string]$_.id } | Sort-Object)
        baselineContent = $baselineContent
        currentContent = $currentContent
    })
}

$interactiveRuleTextById = Get-InteractiveRuleTextById -Root $resolvedRepositoryRoot -Rules @($interactiveCatalog.rules)
$ledgerDecisionsById = @{}
foreach ($decision in @($ledger.decisions)) {
    $ledgerDecisionsById[[string]$decision.sourceRuleId] = $decision
}
$unknownLedgerRuleIds = @($ledger.decisions | Where-Object { $_.sourceRuleId -notin $interactiveCatalog.rules.id } | ForEach-Object { [string]$_.sourceRuleId })
if ($unknownLedgerRuleIds.Count -gt 0) {
    throw "Intake ledger references rules missing from the Interactive catalog: $($unknownLedgerRuleIds -join ', ')"
}

$interactiveCandidates = New-Object 'System.Collections.Generic.List[object]'
foreach ($rule in @($interactiveCatalog.rules | Sort-Object contractPath, id)) {
    $ruleId = [string]$rule.id
    $ruleText = if ($rule.status -eq 'retired') { $null } elseif ($interactiveRuleTextById.ContainsKey($ruleId)) { [string]$interactiveRuleTextById[$ruleId] } else { throw "Interactive rule text was not found: $ruleId" }
    if ($null -ne $ruleText -and (Get-ContentSha256 -Content $ruleText) -ne [string]$rule.contentSha256) {
        throw "Interactive rule text does not match its catalog hash: $ruleId"
    }

    $priorDecision = if ($ledgerDecisionsById.ContainsKey($ruleId)) { $ledgerDecisionsById[$ruleId] } else { $null }
    $changeReasons = New-Object 'System.Collections.Generic.List[string]'
    $state = 'current'
    if ($null -eq $priorDecision) {
        $state = if ($rule.status -eq 'retired') { 'retired' } else { 'new' }
        $changeReasons.Add('no-ledger-decision')
    }
    elseif ($rule.status -eq 'retired' -and $priorDecision.sourceStatus -ne 'retired') {
        $state = 'retired'
        $changeReasons.Add('source-retired')
    }
    elseif ($priorDecision.sourceContentSha256 -ne $rule.contentSha256 -or $priorDecision.sourceStatus -ne $rule.status -or $priorDecision.sourceContractPath -ne $rule.contractPath) {
        $state = 'changed'
        if ($priorDecision.sourceContentSha256 -ne $rule.contentSha256) { $changeReasons.Add('content-hash-changed') }
        if ($priorDecision.sourceStatus -ne $rule.status) { $changeReasons.Add('lifecycle-changed') }
        if ($priorDecision.sourceContractPath -ne $rule.contractPath) { $changeReasons.Add('contract-path-changed') }
    }
    elseif ($priorDecision.decision -eq 'deferred') {
        $state = 'deferred'
        $changeReasons.Add('prior-decision-deferred')
    }

    $relatedIds = New-Object 'System.Collections.Generic.List[string]'
    if ($hostedRulesById.ContainsKey($ruleId)) {
        $relatedIds.Add($ruleId)
    }
    if ($null -ne $priorDecision) {
        foreach ($hostedRuleId in @($priorDecision.hostedRuleIds)) {
            if (-not $relatedIds.Contains([string]$hostedRuleId)) {
                $relatedIds.Add([string]$hostedRuleId)
            }
        }
    }
    $relatedHostedRules = @($relatedIds | ForEach-Object {
        $hostedRule = $hostedRulesById[$_]
        [object[]]$placements = if ($placementsByRuleId.ContainsKey([string]$hostedRule.id)) {
            @($placementsByRuleId[[string]$hostedRule.id].ToArray())
        }
        else {
            @()
        }
        [pscustomobject]@{
            id = [string]$hostedRule.id
            status = [string]$hostedRule.status
            text = [string]$hostedRule.text
            placements = $placements
        }
    })

    $interactiveCandidates.Add([pscustomobject]@{
        id = $ruleId
        title = [string]$rule.title
        contractPath = [string]$rule.contractPath
        sourceStatus = [string]$rule.status
        contentSha256 = [string]$rule.contentSha256
        provenance = [string]$rule.provenance
        evidence = @($rule.evidence)
        sourceIds = @($rule.sourceIds)
        ruleText = $ruleText
        state = $state
        requiresReview = $state -ne 'current'
        changeReasons = @($changeReasons.ToArray())
        priorDecision = $priorDecision
        relatedHostedRules = $relatedHostedRules
    })
}

$stateCounts = [ordered]@{}
foreach ($state in @('new', 'changed', 'retired', 'deferred', 'current')) {
    $stateCounts[$state] = @($interactiveCandidates | Where-Object state -eq $state).Count
}
$currentInteractiveCatalogHash = Get-FileSha256 -Path $resolvedInteractiveCatalogPath
$result = [ordered]@{
    '$schema' = 'rule-intake-review.schema.json'
    schemaVersion = 1
    generatedAt = [DateTimeOffset]::UtcNow.ToString('o')
    readOnly = $true
    refreshMode = 'regenerate-read-only-bundle'
    snapshots = [ordered]@{
        hostedCatalogSha256 = Get-FileSha256 -Path $resolvedHostedCatalogPath
        intakeLedgerSha256 = Get-FileSha256 -Path $resolvedLedgerPath
        upstream = [ordered]@{
            repository = [string]$hostedCatalog.upstreamSnapshot.repository
            baselineCommit = [string]$hostedCatalog.upstreamSnapshot.baselineCommit
            currentRef = [string]$hostedCatalog.upstreamSnapshot.currentRef
            currentCommit = $currentUpstreamCommit
        }
        interactive = [ordered]@{
            catalogPath = [string]$ledger.sourceSnapshot.catalogPath
            previousCatalogSha256 = [string]$ledger.sourceSnapshot.catalogSha256
            currentCatalogSha256 = $currentInteractiveCatalogHash
            catalogChanged = $currentInteractiveCatalogHash -ne [string]$ledger.sourceSnapshot.catalogSha256
        }
    }
    summary = [ordered]@{
        upstreamSourceCount = $upstreamCandidates.Count
        changedUpstreamCount = @($upstreamCandidates | Where-Object state -eq 'changed').Count
        interactiveRuleCount = $interactiveCandidates.Count
        interactiveReviewCount = @($interactiveCandidates | Where-Object requiresReview).Count
        interactiveCurrentCount = $stateCounts.current
        interactiveStateCounts = $stateCounts
    }
    guidanceCapacity = $guidanceCapacity
    upstreamCandidates = $upstreamCandidates.ToArray()
    interactiveCandidates = $interactiveCandidates.ToArray()
}

$resultJson = $result | ConvertTo-Json -Depth 30
if (-not ($resultJson | Test-Json -SchemaFile $bundleSchemaPath -ErrorAction Stop)) {
    throw 'Generated rule intake review bundle schema validation failed'
}

if (-not [string]::IsNullOrWhiteSpace($OutputPath)) {
    $resolvedOutputPath = [IO.Path]::GetFullPath($OutputPath)
    $outputDirectory = Split-Path -Parent $resolvedOutputPath
    if (-not (Test-Path -LiteralPath $outputDirectory -PathType Container)) {
        New-Item -ItemType Directory -Path $outputDirectory | Out-Null
    }
    [IO.File]::WriteAllText($resolvedOutputPath, $resultJson + "`n", [Text.UTF8Encoding]::new($false))
}

if ($OutputFormat -eq 'Json') {
    Write-Output $resultJson
}
else {
    Write-ValidationSectionHeader -Title 'Hosted rule intake review bundle'
    Write-ValidationSummary -Fields ([ordered]@{
        'Upstream Sources' = $result.summary.upstreamSourceCount
        'Changed Upstream' = $result.summary.changedUpstreamCount
        'Interactive Rules' = $result.summary.interactiveRuleCount
        'Interactive Review' = $result.summary.interactiveReviewCount
        'Interactive Current' = $result.summary.interactiveCurrentCount
        'Guarded Headroom' = (@($result.guidanceCapacity.reports | Where-Object kind -eq 'combined' | ForEach-Object { "$($_.name)=$($_.budgetHeadroomTokens)" }) -join '; ')
        'Updates Repository' = $false
        'Output Path' = $(if ([string]::IsNullOrWhiteSpace($OutputPath)) { '(not written)' } else { [IO.Path]::GetFullPath($OutputPath) })
    })
    Complete-ValidationTextOutput
}
