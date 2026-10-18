[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$RequestPath,

    [Parameter(Mandatory = $true)]
    [string]$OutputPath,

    [string]$RepositoryRoot = (Join-Path $PSScriptRoot '../../../..'),

    [string]$CacheDirectory = (Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'hosted-workbench/manual-relationship-cache'),

    [string]$EvaluatorCommand = 'copilot',

    [string]$EvaluatorScriptPath,

    [string]$ComparedRulesPath,

    [string]$Model = 'gpt-5.4',

    [ValidateSet('low', 'medium', 'high', 'xhigh')]
    [string]$ReasoningEffort = 'high'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-Sha256 {
    param(
        [byte[]]$Bytes,
        [string]$Content,
        [string]$Path
    )

    if ($null -ne $Bytes) {
        return [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($Bytes)).ToLowerInvariant()
    }
    if (-not [string]::IsNullOrEmpty($Path)) {
        return Get-Sha256 -Bytes ([IO.File]::ReadAllBytes($Path))
    }
    return Get-Sha256 -Bytes ([Text.Encoding]::UTF8.GetBytes([string]$Content))
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
    $temporaryPath = "$Path.$([Guid]::NewGuid().ToString('N')).tmp"
    try {
        [IO.File]::WriteAllText($temporaryPath, (($Value | ConvertTo-Json -Depth 100) + "`n"), [Text.UTF8Encoding]::new($false))
        [IO.File]::Move($temporaryPath, $Path, $true)
    }
    finally {
        Remove-Item -LiteralPath $temporaryPath -Force -ErrorAction SilentlyContinue
    }
}

$resolvedRepositoryRoot = [IO.Path]::GetFullPath($RepositoryRoot)
$resolvedRequestPath = [IO.Path]::GetFullPath($RequestPath)
$resolvedOutputPath = [IO.Path]::GetFullPath($OutputPath)
$resolvedCacheDirectory = [IO.Path]::GetFullPath($CacheDirectory)
$catalogPath = Join-Path $resolvedRepositoryRoot 'hosted_copilot/copilot-rule-catalog/instruction-catalog.json'
$protectedRulesPath = Join-Path $resolvedRepositoryRoot 'hosted_copilot/copilot-rule-catalog/protected-rules.json'
$schemaPath = Join-Path $resolvedRepositoryRoot 'hosted_copilot/copilot-rule-catalog/assessment-reconciliation/manual-rule-relationship.schema.json'
$promptPath = Join-Path $resolvedRepositoryRoot 'hosted_copilot/tools/assessment-reconciliation-prompts/ManualRuleRelationship-v4.md'
foreach ($path in @($resolvedRequestPath, $catalogPath, $protectedRulesPath, $schemaPath, $promptPath)) {
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "Required manual relationship input was not found: $path"
    }
}
if ($resolvedCacheDirectory.StartsWith(($resolvedRepositoryRoot.TrimEnd('\', '/') + [IO.Path]::DirectorySeparatorChar), [StringComparison]::OrdinalIgnoreCase)) {
    throw 'CacheDirectory must be outside the source repository'
}

$request = Get-Content -LiteralPath $resolvedRequestPath -Raw | ConvertFrom-Json
$expectedRequestProperties = @('candidateKey', 'category', 'placement', 'ruleId', 'ruleTextBase64')
if (Compare-Object -ReferenceObject $expectedRequestProperties -DifferenceObject @($request.PSObject.Properties.Name | Sort-Object)) {
    throw 'Manual relationship request has an unexpected property set'
}
if ([string]$request.category -notin @('implementation', 'testing', 'documentation')) {
    throw 'Manual relationship request category is invalid'
}
if ([string]::IsNullOrWhiteSpace([string]$request.candidateKey) -or [string]::IsNullOrWhiteSpace([string]$request.ruleId) -or [string]::IsNullOrWhiteSpace([string]$request.placement)) {
    throw 'Manual relationship request identity is incomplete'
}
try {
    $ruleTextBytes = [Convert]::FromBase64String([string]$request.ruleTextBase64)
    $ruleText = [Text.UTF8Encoding]::new($false, $true).GetString($ruleTextBytes)
}
catch {
    throw 'Manual relationship request rule text is not valid base64-encoded UTF-8'
}
if ([string]::IsNullOrWhiteSpace($ruleText) -or $ruleText.Length -gt 20000) {
    throw 'Manual relationship request rule text must contain between 1 and 20000 characters'
}

$catalog = Get-Content -LiteralPath $catalogPath -Raw | ConvertFrom-Json
$protectedRules = Get-Content -LiteralPath $protectedRulesPath -Raw | ConvertFrom-Json
$catalogLocations = @{}
foreach ($surface in @($catalog.surfaces)) {
    foreach ($section in @($surface.sections)) {
        foreach ($hostedRuleId in @($section.ruleIds)) {
            $catalogLocations[[string]$hostedRuleId] = [string]$surface.id
        }
    }
}
$knownRules = @(
    @($catalog.rules | Where-Object { [string]$_.status -ceq 'active' -and $catalogLocations[[string]$_.id] -ceq [string]$request.category })
    @($protectedRules.rules | Where-Object { [string]$_.surfaceId -ceq [string]$request.category })
) | Where-Object { [string]$_.id -cne [string]$request.ruleId }
if (-not [string]::IsNullOrWhiteSpace($ComparedRulesPath)) {
    $knownRules = @(Get-Content -LiteralPath $ComparedRulesPath -Raw | ConvertFrom-Json -Depth 100 -DateKind String)
    $knownIds = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    foreach ($rule in $knownRules) {
        if ([string]::IsNullOrWhiteSpace([string]$rule.text) -or [string]$rule.status -notin @('active', 'protected', 'proposed') -or [string]$rule.id -ceq [string]$request.ruleId -or -not $knownIds.Add([string]$rule.id)) { throw 'Compared rules contain an invalid or duplicate rule' }
    }
}
$payload = [ordered]@{
    schemaVersion = 1
    candidateKey = [string]$request.candidateKey
    ruleId = [string]$request.ruleId
    ruleText = $ruleText
    ruleTextSha256 = Get-Sha256 -Bytes $ruleTextBytes
    category = [string]$request.category
    placement = [string]$request.placement
    hostedRules = @($knownRules | ForEach-Object {
        [ordered]@{
            id = [string]$_.id
            text = [string]$_.text
            status = [string]$_.status
        }
    })
}
$evaluatorIdentity = $EvaluatorCommand
$resolvedEvaluatorScriptPath = $null
if (-not [string]::IsNullOrWhiteSpace($EvaluatorScriptPath)) {
    $resolvedEvaluatorScriptPath = [IO.Path]::GetFullPath($EvaluatorScriptPath)
    if (-not (Test-Path -LiteralPath $resolvedEvaluatorScriptPath -PathType Leaf)) {
        throw "Evaluator script was not found: $resolvedEvaluatorScriptPath"
    }
    $evaluatorIdentity = 'script:' + (Get-Sha256 -Path $resolvedEvaluatorScriptPath)
}
$cacheIdentity = [ordered]@{
    schemaVersion = 1
    payloadSha256 = Get-Sha256 -Content ($payload | ConvertTo-Json -Depth 20 -Compress)
    hostedCatalogSha256 = Get-Sha256 -Path $catalogPath
    protectedRulesSha256 = Get-Sha256 -Path $protectedRulesPath
    schemaSha256 = Get-Sha256 -Path $schemaPath
    promptSha256 = Get-Sha256 -Path $promptPath
    nativeEvaluatorSha256 = Get-Sha256 -Path (Join-Path $PSScriptRoot 'Invoke-CopilotReconciliationStage.ps1')
    evaluator = $evaluatorIdentity
    model = $Model
    reasoningEffort = $ReasoningEffort
}
$cacheKey = Get-Sha256 -Content ($cacheIdentity | ConvertTo-Json -Compress)
$cachePath = Join-Path $resolvedCacheDirectory "$cacheKey.json"
function Assert-ManualRelationshipResult {
    param([object]$Result)
    if ([string]$Result.ruleTextSha256 -cne [string]$payload.ruleTextSha256) { throw 'Manual relationship evaluator changed the rule text hash' }
    $knownRuleIds = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    foreach ($rule in $knownRules) { $null = $knownRuleIds.Add([string]$rule.id) }
    $seenRuleIds = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    foreach ($relationship in @($Result.relationships)) {
        if (-not $knownRuleIds.Contains([string]$relationship.hostedRuleId) -or -not $seenRuleIds.Add([string]$relationship.hostedRuleId)) { throw 'Manual relationship evaluator referenced an unknown or duplicate Hosted rule' }
    }
}
if (Test-Path -LiteralPath $cachePath -PathType Leaf) {
    $cacheEntry = Get-Content -LiteralPath $cachePath -Raw | ConvertFrom-Json
    if ([string]$cacheEntry.cacheKey -ceq $cacheKey -and ($cacheEntry.identity | ConvertTo-Json -Compress) -ceq ($cacheIdentity | ConvertTo-Json -Compress)) {
        $cachedResultJson = $cacheEntry.result | ConvertTo-Json -Depth 20
        if ($cachedResultJson | Test-Json -SchemaFile $schemaPath -ErrorAction Stop) {
            Assert-ManualRelationshipResult -Result $cacheEntry.result
            Write-JsonAtomically -Path $resolvedOutputPath -Value $cacheEntry.result
            [ordered]@{ status = 'passed'; cache = 'hit'; cacheKey = $cacheKey; outputPath = $resolvedOutputPath } | ConvertTo-Json -Compress
            exit 0
        }
    }
}

$runDirectory = Join-Path ([IO.Path]::GetTempPath()) "hosted-manual-rule-$([Guid]::NewGuid().ToString('N'))"
try {
    $null = New-Item -ItemType Directory -Path $runDirectory -Force
    $payloadPath = Join-Path $runDirectory 'manual-rule-relationship-input.json'
    $runSchemaPath = Join-Path $runDirectory 'manual-rule-relationship.schema.json'
    $runPromptPath = Join-Path $runDirectory 'ManualRuleRelationship-v4.md'
    $responsePath = Join-Path $runDirectory 'manual-rule-relationship-result.json'
    Write-JsonAtomically -Path $payloadPath -Value $payload
    Copy-Item -LiteralPath $schemaPath -Destination $runSchemaPath
    Copy-Item -LiteralPath $promptPath -Destination $runPromptPath

    if ($null -ne $resolvedEvaluatorScriptPath) {
        $output = @(& pwsh -NoProfile -File $resolvedEvaluatorScriptPath -PayloadPath $payloadPath -SchemaPath $runSchemaPath -PromptPath $runPromptPath -OutputPath $responsePath -Model $Model -ReasoningEffort $ReasoningEffort 2>&1)
        if ($LASTEXITCODE -ne 0) {
            throw "Manual relationship evaluator script failed: $(($output | Out-String).Trim())"
        }
    }
    else {
        $nativeParameters = @{
            Stage = 'manual-relationship'; InputPath = $payloadPath; SchemaPath = $runSchemaPath
            PromptPath = $runPromptPath; OutputPath = $responsePath; EvaluatorCommand = $EvaluatorCommand
            Model = $Model; ReasoningEffort = $ReasoningEffort
        }
        $output = @(& pwsh -NoProfile -NonInteractive -File (Join-Path $PSScriptRoot 'Invoke-CopilotReconciliationStage.ps1') @nativeParameters 2>&1)
        if ($LASTEXITCODE -ne 0) {
            throw "Manual relationship evaluator failed: $(($output | Out-String).Trim())"
        }
    }

    $resultJson = Get-Content -LiteralPath $responsePath -Raw
    if (-not ($resultJson | Test-Json -SchemaFile $runSchemaPath -ErrorAction Stop)) {
        throw 'Manual relationship evaluator result does not satisfy its schema'
    }
    $result = $resultJson | ConvertFrom-Json
    Assert-ManualRelationshipResult -Result $result
    Write-JsonAtomically -Path $resolvedOutputPath -Value $result
    Write-JsonAtomically -Path $cachePath -Value ([ordered]@{
        schemaVersion = 1
        kind = 'hosted-manual-rule-relationship-cache'
        cacheKey = $cacheKey
        identity = $cacheIdentity
        result = $result
    })
    [ordered]@{ status = 'passed'; cache = 'miss'; cacheKey = $cacheKey; outputPath = $resolvedOutputPath } | ConvertTo-Json -Compress
}
finally {
    Remove-Item -LiteralPath $runDirectory -Recurse -Force -ErrorAction SilentlyContinue
}
