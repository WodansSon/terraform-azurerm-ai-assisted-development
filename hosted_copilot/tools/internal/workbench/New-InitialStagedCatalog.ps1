<#
.SYNOPSIS
Creates the initial Terraform staged catalog from current Hosted instructions and the review skill.
.DESCRIPTION
Captures all five profile-owned guidance files and their identified rules. Validates the bootstrap boundary before writing the staged catalog. Refuses an existing destination and does not approve, publish, initialize a database, or read a legacy catalog.
#>
[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$hostedRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))
$modulePath = Join-Path $hostedRoot 'tools/modules/workbench/WorkbenchPublishedGuidance.mjs'
$profilePath = Join-Path $hostedRoot 'tools/config/workbench-terraform-profile.json'
$schemaPath = Join-Path $hostedRoot 'contracts/catalog/instruction-catalog-bootstrap.schema.json'
$destination = Join-Path $hostedRoot 'copilot-rule-catalog/staged/instruction-catalog.json'
if (Test-Path -LiteralPath $destination) { throw 'Initial catalog creation refuses an existing staged catalog' }
$nodeScript = @'
import { readFile } from 'node:fs/promises';
import { pathToFileURL } from 'node:url';
const { buildInitialStagedCatalog } = await import(pathToFileURL(process.argv[1]));
const profile = JSON.parse(await readFile(process.argv[2], 'utf8'));
const catalog = await buildInitialStagedCatalog({ root: process.argv[3], profile });
process.stdout.write(JSON.stringify(catalog, null, 2) + '\n');
'@
Write-Host '[RUNNING]  initial-staged-catalog : Capturing current Hosted instructions and review skill'
$output = & node --input-type=module --eval $nodeScript $modulePath $profilePath $hostedRoot
if ($LASTEXITCODE -ne 0) { throw 'Initial staged catalog capture failed; no catalog was written' }
$serialized = ($output -join "`n") + "`n"
if (-not (Test-Json -Json $serialized -SchemaFile $schemaPath -ErrorAction Stop)) {
    throw 'Initial staged catalog failed its bootstrap schema; no catalog was written'
}
$catalog = $serialized | ConvertFrom-Json -Depth 100
foreach ($file in $catalog.files) {
    if ((Get-FileHash -LiteralPath (Join-Path $hostedRoot $file.relativePath) -Algorithm SHA256).Hash.ToLowerInvariant() -cne $file.contentSha256) {
        throw "Required guidance changed before staging: $($file.relativePath)"
    }
}
$directory = Split-Path -Parent $destination
if (-not (Test-Path -LiteralPath $directory -PathType Container)) { $null = New-Item -ItemType Directory -Path $directory }
for ($ancestor = Get-Item -LiteralPath $directory -Force; $null -ne $ancestor; $ancestor = $ancestor.Parent) {
    if ($ancestor.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'Staged catalog directory must not use links or junctions' }
}
$stream = [IO.File]::Open($destination, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::None)
try {
    $bytes = [Text.UTF8Encoding]::new($false).GetBytes($serialized)
    $stream.Write($bytes, 0, $bytes.Length)
    $stream.Flush($true)
} finally { $stream.Dispose() }
Write-Host "[PASSED]   initial-staged-catalog : Captured $($catalog.files.Count) guidance files and $($catalog.rules.Count) identified rules; no approval or publication recorded"
Write-Host 'Staged catalog: hosted_copilot/copilot-rule-catalog/staged/instruction-catalog.json'
