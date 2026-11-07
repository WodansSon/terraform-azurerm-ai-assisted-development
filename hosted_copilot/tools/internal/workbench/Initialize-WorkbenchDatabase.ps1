<#
.SYNOPSIS
Creates a new branch database from current configured source captures.
.DESCRIPTION
Collects and parses current sources into a new database. Does not load legacy displays, cached assessments, saved inventory ledgers, or accepted catalog results. Source collection is not assessment/reconciliation readiness.
.PARAMETER DatabasePath
Explicit new local destination with an existing parent directory. Existing files are never replaced.
.PARAMETER SkipUpstream
Explicitly excludes remote source collection for a local-only initialization attempt.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$DatabasePath,
    [switch]$SkipUpstream
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$repositoryRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../../..'))
$hostedRoot = Join-Path $repositoryRoot 'hosted_copilot'
$resolvedDatabasePath = [IO.Path]::GetFullPath($DatabasePath)
if (Test-Path -LiteralPath $resolvedDatabasePath) { throw 'Database creation refuses an existing destination' }
if (-not (Test-Path -LiteralPath (Split-Path -Parent $resolvedDatabasePath) -PathType Container)) { throw 'Database destination parent must already exist' }
Import-Module (Join-Path $PSScriptRoot '../../modules/source-parsers/ProtectedRules.psm1') -Force
$branch = [string](& git -C $repositoryRoot symbolic-ref --quiet HEAD)
if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($branch)) { throw 'Database creation requires a named branch' }
$commit = [string](& git -C $repositoryRoot rev-parse HEAD)
if ($LASTEXITCODE -ne 0) { throw 'Cannot capture the current repository identity' }
$sourceSetPath = Join-Path $hostedRoot 'copilot-rule-catalog/source-definitions/source-definition-set.json'
$sourceSet = Get-Content -LiteralPath $sourceSetPath -Raw | ConvertFrom-Json
$profile = Get-Content -LiteralPath (Join-Path $PSScriptRoot '../../config/workbench-terraform-profile.json') -Raw | ConvertFrom-Json -Depth 100
$captureRoot = Join-Path ([IO.Path]::GetTempPath()) ('hosted-native-capture-' + [guid]::NewGuid().ToString('N'))
$null = New-Item -ItemType Directory -Path $captureRoot
try {
    $captures = [Collections.Generic.List[object]]::new()
    $ordinal = 0
    foreach ($definitionId in @($sourceSet.sourceDefinitionIds)) {
        $definitionPath = Join-Path $hostedRoot "copilot-rule-catalog/source-definitions/$definitionId.json"
        $definitionText = [IO.File]::ReadAllText($definitionPath)
        $definition = $definitionText | ConvertFrom-Json
        if ($SkipUpstream -and $definition.root.kind -ceq 'github') {
            Write-Host "[SKIPPED]  source-collection/$definitionId : Explicit local-only initialization"
            continue
        }
        Write-Host "[RUNNING]  source-collection/$definitionId : Capturing current source bytes"
        $capturePath = Join-Path $captureRoot "$definitionId.json"
        $null = & (Join-Path $PSScriptRoot '../collection/New-SourceInventory.ps1') -RepositoryRoot $repositoryRoot -SourceDefinitionPath $definitionPath -HostedCatalogPath (Join-Path $captureRoot 'no-legacy-catalog.json') -OutputPath $capturePath -OutputFormat Json
        if (-not (Test-Path -LiteralPath $capturePath -PathType Leaf)) { throw 'Fresh source capture did not complete' }
        $parser = Get-Content -LiteralPath (Join-Path $hostedRoot "contracts/parsers/$($definition.parser).json") -Raw | ConvertFrom-Json
        $laneCode = switch ($definitionId) { 'interactive-toolkit' { 'interactive' }; 'maintainer-proposals' { 'maintainer' }; 'contributor-guidance' { 'contributor' }; default { throw 'Unregistered current-profile source lane' } }
        $captures.Add([ordered]@{ definition = $definition; definitionJson = $definitionText; inventoryJson = [IO.File]::ReadAllText($capturePath);
            parserContract = $parser; lane = [ordered]@{ code = $laneCode; label = $definition.displayName; displayOrder = $ordinal++ } })
        Write-Host "[PASSED]   source-collection/$definitionId : Fresh capture complete"
    }
    $protected = Get-ProtectedRulesCapture -SourceRoot (Join-Path $hostedRoot 'authored-rules/protected') -RepositoryRoot $repositoryRoot
    $blocks = @($protected.Blocks | ForEach-Object {
        [ordered]@{ id = $_.id; surfaceCode = $_.surface; title = $_.title; content = $_.normalizedContent; contentSha256 = $_.contentSha256;
            text = $_.fields['Rule']; provenance = $_.fields['Provenance']; protectionReason = $_.fields['Rationale']; relativePath = $_.relativeSourcePath }
    })
    $request = [ordered]@{
        repository = [ordered]@{ canonicalName = 'local:' + [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData([Text.Encoding]::UTF8.GetBytes($repositoryRoot))).ToLowerInvariant();
            branchRef = $branch.Trim(); commitOid = $commit.Trim() }
        profile = $profile
        captures = $captures.ToArray()
        protectedCapture = [ordered]@{ parserContractSha256 = (Get-FileHash -LiteralPath (Join-Path $PSScriptRoot '../../modules/source-parsers/ProtectedRules.psm1') -Algorithm SHA256).Hash.ToLowerInvariant();
            requiredFiles = @($protected.Files.relativePath); files = @($protected.Files); blocks = $blocks }
    }
    Write-Host '[RUNNING]  database-create : Persisting fresh captured facts'
    $result = ($request | ConvertTo-Json -Depth 100 -Compress) | & node (Join-Path $PSScriptRoot '../../modules/workbench/WorkbenchDatabase.mjs') create $resolvedDatabasePath
    if ($LASTEXITCODE -ne 0) { throw 'Fresh database creation failed without replacing existing state' }
    Write-Host '[PASSED]   database-create : Source facts persisted; new analysis is still required'
    $result
} finally {
    Remove-Item -LiteralPath $captureRoot -Recurse -Force -ErrorAction SilentlyContinue
}