[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$RepoRoot,

    [ValidateSet('CliReview')]
    [string]$Profile = 'CliReview',

    [ValidateSet('Json', 'Text')]
    [string]$OutputFormat = 'Json'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Resolve-ValidationManifestPath {
    $pluginRoot = Split-Path -Parent $PSScriptRoot
    $candidatePaths = @(
        (Join-Path $pluginRoot 'manifest\file-manifest.config'),
        (Join-Path $PSScriptRoot '..\..\..\installer\file-manifest.config')
    )

    foreach ($candidatePath in $candidatePaths) {
        $resolvedCandidatePath = [System.IO.Path]::GetFullPath($candidatePath)
        if (Test-Path -LiteralPath $resolvedCandidatePath) {
            return $resolvedCandidatePath
        }
    }

    throw 'Cannot resolve target-repo preflight manifest: no bundled or repo-local installer manifest was found.'
}

function Get-ManifestSections {
    param(
        [Parameter(Mandatory)]
        [string]$ManifestPath
    )

    $sections = [ordered]@{}
    $currentSection = $null

    foreach ($line in Get-Content -LiteralPath $ManifestPath) {
        $trimmedLine = $line.Trim()
        if ([string]::IsNullOrWhiteSpace($trimmedLine) -or $trimmedLine.StartsWith('#')) {
            continue
        }

        if ($trimmedLine.StartsWith('[') -and $trimmedLine.EndsWith(']')) {
            $currentSection = $trimmedLine.TrimStart('[').TrimEnd(']')
            if (-not $sections.Contains($currentSection)) {
                $sections[$currentSection] = New-Object 'System.Collections.Generic.List[string]'
            }

            continue
        }

        if ($null -ne $currentSection) {
            $sections[$currentSection].Add($trimmedLine)
        }
    }

    return $sections
}

function Get-ProfileSections {
    param(
        [Parameter(Mandatory)]
        [string]$ValidationProfile
    )

    switch ($ValidationProfile) {
        'CliReview' {
            return @('MAIN_FILES', 'INSTRUCTION_FILES', 'PROMPT_FILES', 'SKILL_FILES')
        }
        default {
            throw "Unsupported validation profile '$ValidationProfile'"
        }
    }
}

$resolvedRepoRoot = [System.IO.Path]::GetFullPath($RepoRoot)
if (-not (Test-Path -LiteralPath $resolvedRepoRoot)) {
    throw "Repo root was not found at $resolvedRepoRoot"
}

$manifestPath = Resolve-ValidationManifestPath
$manifestSections = Get-ManifestSections -ManifestPath $manifestPath
$requiredSections = @(Get-ProfileSections -ValidationProfile $Profile)
$missingManifestSections = @($requiredSections | Where-Object { -not $manifestSections.Contains($_) })

if ($missingManifestSections.Count -gt 0) {
    throw "Cannot validate target repo preflight: manifest '$manifestPath' is missing required sections: $($missingManifestSections -join ', ')"
}

$expectedFiles = New-Object 'System.Collections.Generic.List[object]'
foreach ($sectionName in $requiredSections) {
    foreach ($relativePath in $manifestSections[$sectionName]) {
        $expectedFiles.Add([pscustomobject]@{
            section = $sectionName
            path = $relativePath
        })
    }
}

$missingFiles = New-Object 'System.Collections.Generic.List[object]'
$missingFilesBySection = [ordered]@{}
foreach ($sectionName in $requiredSections) {
    $missingFilesBySection[$sectionName] = New-Object 'System.Collections.Generic.List[string]'
}

foreach ($expectedFile in $expectedFiles) {
    $targetPath = Join-Path $resolvedRepoRoot $expectedFile.path
    if (-not (Test-Path -LiteralPath $targetPath)) {
        $missingFiles.Add($expectedFile)
        $missingFilesBySection[$expectedFile.section].Add($expectedFile.path)
    }
}

$result = [ordered]@{}
$result.repoRoot = $resolvedRepoRoot
$result.manifestPath = $manifestPath
$result.profile = $Profile
$result.requiredSections = [string[]]$requiredSections
$result.expectedFileCount = $expectedFiles.Count
$result.missingFileCount = $missingFiles.Count
$result.missingFiles = $missingFiles.ToArray()
$result.missingFilesBySection = [ordered]@{}
$result.isValid = ($missingFiles.Count -eq 0)

foreach ($sectionName in $requiredSections) {
    $result.missingFilesBySection[$sectionName] = $missingFilesBySection[$sectionName].ToArray()
}

if ($OutputFormat -eq 'Json') {
    ($result | ConvertTo-Json -Depth 6) + "`n" | Write-Output
    return
}

Write-Output ("Repo Root: {0}" -f $result.repoRoot)
Write-Output ("Manifest Path: {0}" -f $result.manifestPath)
Write-Output ("Profile: {0}" -f $result.profile)
Write-Output ("Required Sections: {0}" -f ($result.requiredSections -join ', '))
Write-Output ("Expected File Count: {0}" -f $result.expectedFileCount)
Write-Output ("Missing File Count: {0}" -f $result.missingFileCount)
Write-Output ("Valid: {0}" -f $(if ($result.isValid) { 'true' } else { 'false' }))

if (-not $result.isValid) {
    Write-Output 'Missing Files:'
    foreach ($sectionName in $result.requiredSections) {
        foreach ($relativePath in $result.missingFilesBySection[$sectionName]) {
            Write-Output ("  - [{0}] {1}" -f $sectionName, $relativePath)
        }
    }
}
