[CmdletBinding()]
param(
    [string]$PluginRoot = (Join-Path (Split-Path -Parent $PSScriptRoot) '..\plugins\terraform-azurerm-ai-toolkit'),
    [string]$OutputRoot,
    [string]$PackageName = 'terraform-azurerm-ai-toolkit',
    [string]$MarketplaceName = 'terraform-azurerm-ai-toolkit-local',
    [switch]$Clean,
    [switch]$Zip,
    [switch]$SkipValidate
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$resolvedPluginRoot = [System.IO.Path]::GetFullPath($PluginRoot)
$helperRoot = [System.IO.Path]::GetFullPath($PSScriptRoot)
$resolvedInstallerManifestPath = [System.IO.Path]::GetFullPath((Join-Path $helperRoot '..\..\installer\file-manifest.config'))

if ([string]::IsNullOrWhiteSpace($OutputRoot)) {
    $OutputRoot = Join-Path $resolvedPluginRoot 'export\staged'
}

$resolvedOutputRoot = [System.IO.Path]::GetFullPath($OutputRoot)
$stagedPluginRoot = Join-Path $resolvedOutputRoot $PackageName
$marketplaceRoot = $resolvedOutputRoot
$marketplaceManifestDirectory = Join-Path $marketplaceRoot '.claude-plugin'
$marketplaceManifestPath = Join-Path $marketplaceManifestDirectory 'marketplace.json'

if (-not (Test-Path -LiteralPath $resolvedPluginRoot)) {
    throw "Plugin root was not found at $resolvedPluginRoot"
}

if (-not (Test-Path -LiteralPath $resolvedInstallerManifestPath)) {
    throw "Installer manifest was not found at $resolvedInstallerManifestPath"
}

$validateHelperPath = Join-Path $helperRoot 'validate-plugin.ps1'
if (-not $SkipValidate) {
    & $validateHelperPath -PluginRoot $resolvedPluginRoot | Out-Null
}

$pluginManifestPath = Join-Path $resolvedPluginRoot '.claude-plugin\plugin.json'
$pluginManifest = Get-Content -LiteralPath $pluginManifestPath -Raw | ConvertFrom-Json -ErrorAction Stop

if ($Clean -and (Test-Path -LiteralPath $resolvedOutputRoot)) {
    Remove-Item -LiteralPath $resolvedOutputRoot -Recurse -Force
}

New-Item -ItemType Directory -Path $stagedPluginRoot -Force | Out-Null

$copyEntries = @(
    [pscustomobject]@{ Source = '.claude-plugin'; Target = '.claude-plugin'; Type = 'directory' }
    [pscustomobject]@{ Source = 'agency.json'; Target = 'agency.json'; Type = 'file' }
    [pscustomobject]@{ Source = 'README.md'; Target = 'README.md'; Type = 'file' }
    [pscustomobject]@{ Source = 'agents'; Target = 'agents'; Type = 'directory' }
    [pscustomobject]@{ Source = 'tools\resolve-committed-review-scope.ps1'; Target = 'tools\resolve-committed-review-scope.ps1'; Type = 'file' }
    [pscustomobject]@{ Source = 'tools\validate-target-repo-preflight.ps1'; Target = 'tools\validate-target-repo-preflight.ps1'; Type = 'file' }
)

foreach ($entry in $copyEntries) {
    $sourcePath = Join-Path $resolvedPluginRoot $entry.Source
    $targetPath = Join-Path $stagedPluginRoot $entry.Target
    $targetParent = Split-Path -Parent $targetPath

    if (-not (Test-Path -LiteralPath $sourcePath)) {
        throw "Required export input was not found at $sourcePath"
    }

    New-Item -ItemType Directory -Path $targetParent -Force | Out-Null

    if ($entry.Type -eq 'directory') {
        Copy-Item -LiteralPath $sourcePath -Destination $targetPath -Recurse -Force
    }
    else {
        Copy-Item -LiteralPath $sourcePath -Destination $targetPath -Force
    }
}

$manifestTargetPath = Join-Path $stagedPluginRoot 'manifest\file-manifest.config'
New-Item -ItemType Directory -Path (Split-Path -Parent $manifestTargetPath) -Force | Out-Null
Copy-Item -LiteralPath $resolvedInstallerManifestPath -Destination $manifestTargetPath -Force

New-Item -ItemType Directory -Path $marketplaceManifestDirectory -Force | Out-Null
$marketplaceManifest = [ordered]@{
    name = $MarketplaceName
    owner = [ordered]@{
        name = 'Local Plugin Test Marketplace'
    }
    metadata = [ordered]@{
        description = 'Local marketplace for testing the Terraform AzureRM AI Toolkit staged plugin export.'
        version = '0.0.0-dev'
    }
    plugins = @(
        [ordered]@{
            name = $pluginManifest.name
            source = $PackageName
            description = $pluginManifest.description
            version = $pluginManifest.version
            author = [ordered]@{
                name = $pluginManifest.author.name
                email = $pluginManifest.author.email
            }
            repository = $pluginManifest.repository
            license = $pluginManifest.license
            keywords = @($pluginManifest.keywords)
        }
    )
}

($marketplaceManifest | ConvertTo-Json -Depth 8) + "`n" | Set-Content -LiteralPath $marketplaceManifestPath -NoNewline

$zipPath = $null
if ($Zip) {
    $zipPath = Join-Path $resolvedOutputRoot ("{0}.zip" -f $PackageName)
    if (Test-Path -LiteralPath $zipPath) {
        Remove-Item -LiteralPath $zipPath -Force
    }

    Compress-Archive -Path $stagedPluginRoot -DestinationPath $zipPath -Force
}

Write-Output 'Playground plugin export summary'
Write-Output ("  Plugin Root       : {0}" -f $resolvedPluginRoot)
Write-Output ("  Staged Plugin     : {0}" -f $stagedPluginRoot)
Write-Output ("  Marketplace Root  : {0}" -f $marketplaceRoot)
Write-Output ("  Marketplace Name  : {0}" -f $MarketplaceName)
Write-Output ("  Validation        : {0}" -f $(if ($SkipValidate) { 'skipped' } else { 'passed-before-export' }))
Write-Output ("  Zip Package       : {0}" -f $(if ($Zip) { $zipPath } else { 'not requested' }))
Write-Output ''
Write-Output 'Suggested marketplace test'
Write-Output ("  copilot plugin marketplace add {0}" -f $marketplaceRoot.Replace('\', '/'))
Write-Output ("  copilot plugin install {0}@{1}" -f $pluginManifest.name, $MarketplaceName)
Write-Output ''
Write-Output 'Suggested direct install fallback'
Write-Output ("  copilot plugin install {0}" -f $stagedPluginRoot.Replace('\', '/'))
if ($Zip) {
    Write-Output 'Suggested zip inspection'
    Write-Output ("  {0}" -f $zipPath)
}
