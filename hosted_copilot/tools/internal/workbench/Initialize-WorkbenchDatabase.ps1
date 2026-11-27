<#
.SYNOPSIS
Creates a new branch database from a published catalog or initial rules JSON.
.DESCRIPTION
Uses the published catalog when present, otherwise imports initial-rules.json as the first baseline without approval or publication. Collects the configured source and protected captures, verifies the database after reopening, and never replaces an existing database. New assessment/reconciliation is still required.
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
$baselineProbe = @'
import { readFile } from 'node:fs/promises';
import { pathToFileURL } from 'node:url';
const moduleUrl = pathToFileURL(process.argv[1]);
const { readInitialCatalogSource } = await import(moduleUrl);
const { parseInitialRulesJson } = await import(new URL('./WorkbenchInitialCatalog.mjs', moduleUrl));
const profile = JSON.parse(await readFile(process.argv[2], 'utf8'));
const source = await readInitialCatalogSource({ root: process.argv[3] });
if (source.format === 'initial-rules-json') parseInitialRulesJson(source, profile);
console.log(JSON.stringify(source));
'@
$baselineCaptureText = [string](& node --input-type=module --eval $baselineProbe (Join-Path $PSScriptRoot '../../modules/workbench/WorkbenchPublishedGuidance.mjs') (Join-Path $PSScriptRoot '../../config/workbench-terraform-profile.json') $hostedRoot)
if ($LASTEXITCODE -ne 0) { throw 'Initial catalog input is invalid; no database was created' }
$baseline = $baselineCaptureText | ConvertFrom-Json -Depth 100
if ($baseline.format -ceq 'published-catalog' -and -not (Test-Json -Json $baseline.content -SchemaFile (Join-Path $hostedRoot 'contracts/catalog/instruction-catalog.schema.json') -ErrorAction Stop)) {
    throw 'Published catalog does not satisfy its schema; the initial rules fallback was not selected'
}
Write-Host "[PASSED]   baseline-capture : Selected $($baseline.format) from $($baseline.relativePath)"
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
    if ($baseline.format -ceq 'published-catalog') { $request.catalogJson = $baseline.content }
    else { $request.initialRulesCapture = $baseline }
    $currentBaselineText = [string](& node --input-type=module --eval $baselineProbe (Join-Path $PSScriptRoot '../../modules/workbench/WorkbenchPublishedGuidance.mjs') (Join-Path $PSScriptRoot '../../config/workbench-terraform-profile.json') $hostedRoot)
    if ($LASTEXITCODE -ne 0 -or $currentBaselineText -cne $baselineCaptureText) { throw 'Initial catalog input changed during source capture; retry initialization' }
    Write-Host '[RUNNING]  database-create : Persisting fresh captured facts'
    $result = ($request | ConvertTo-Json -Depth 100 -Compress) | & node (Join-Path $PSScriptRoot '../../modules/workbench/WorkbenchDatabase.mjs') create $resolvedDatabasePath
    if ($LASTEXITCODE -ne 0) { throw 'Fresh database creation failed without replacing existing state' }
    Import-Module (Join-Path $PSScriptRoot '../../modules/workbench/Workbench.DatabaseLocation.psm1') -Force
    Set-WorkbenchDatabaseLocation -RepositoryRoot $repositoryRoot -BranchRef $branch.Trim() -DatabasePath $resolvedDatabasePath
    Write-Host '[PASSED]   database-create : Initial baseline and source facts verified after reopening; no new approval or fork publication was recorded and analysis is still required'
    $result
} finally {
    Remove-Item -LiteralPath $captureRoot -Recurse -Force -ErrorAction SilentlyContinue
}
