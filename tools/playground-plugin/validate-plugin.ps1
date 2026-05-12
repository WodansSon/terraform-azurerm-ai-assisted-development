[CmdletBinding()]
param(
    [string]$PluginRoot = (Join-Path (Split-Path -Parent $PSScriptRoot) '..\plugins\terraform-azurerm-ai-toolkit'),
    [switch]$SkipSync
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Test-ValidEmailAddress {
    param(
        [string]$Value
    )

    if ([string]::IsNullOrWhiteSpace($Value)) {
        return $false
    }

    try {
        $mailAddress = [System.Net.Mail.MailAddress]::new($Value)
        return $mailAddress.Address -eq $Value
    }
    catch {
        return $false
    }
}

$resolvedPluginRoot = [System.IO.Path]::GetFullPath($PluginRoot)
$issues = New-Object 'System.Collections.Generic.List[string]'

$requiredFiles = @(
    '.claude-plugin\plugin.json',
    'agency.json',
    'README.md',
    'agents\review-local.agent.md',
    'agents\review-committed.agent.md',
    'agents\review-docs.agent.md',
    'tools\resolve-committed-review-scope.ps1',
    'tools\validate-target-repo-preflight.ps1'
)

$requiredRepoHelpers = @(
    'validate-plugin.ps1',
    'export-plugin.ps1',
    'test-staged-plugin.ps1'
)

if (-not (Test-Path -LiteralPath $resolvedPluginRoot)) {
    throw "Plugin root was not found at $resolvedPluginRoot"
}

$sourceInstallerManifestPath = [System.IO.Path]::GetFullPath((Join-Path $resolvedPluginRoot '..\..\installer\file-manifest.config'))
if (-not (Test-Path -LiteralPath $sourceInstallerManifestPath)) {
    $issues.Add("Missing required installer manifest source: installer/file-manifest.config")
}

foreach ($relativePath in $requiredFiles) {
    $fullPath = Join-Path $resolvedPluginRoot $relativePath
    if (-not (Test-Path -LiteralPath $fullPath)) {
        $issues.Add("Missing required plugin file: $relativePath")
    }
}

$pluginManifestPath = Join-Path $resolvedPluginRoot '.claude-plugin\plugin.json'
if (Test-Path -LiteralPath $pluginManifestPath) {
    try {
        $pluginManifest = Get-Content -LiteralPath $pluginManifestPath -Raw | ConvertFrom-Json -ErrorAction Stop
        foreach ($propertyName in @('name', 'description', 'version', 'author')) {
            if (-not $pluginManifest.PSObject.Properties.Name.Contains($propertyName)) {
                $issues.Add("Plugin manifest is missing required property '$propertyName'")
            }
        }

        if ($pluginManifest.PSObject.Properties.Name.Contains('author')) {
            foreach ($authorPropertyName in @('name', 'email')) {
                if (-not $pluginManifest.author.PSObject.Properties.Name.Contains($authorPropertyName)) {
                    $issues.Add("Plugin manifest author is missing required property '$authorPropertyName'")
                }
            }

            if ($pluginManifest.author.PSObject.Properties.Name.Contains('name')) {
                if ([string]::IsNullOrWhiteSpace($pluginManifest.author.name) -or $pluginManifest.author.name -match '^TODO:') {
                    $issues.Add("Plugin manifest author.name must be set to a non-placeholder value")
                }
            }

            if ($pluginManifest.author.PSObject.Properties.Name.Contains('email')) {
                if (-not (Test-ValidEmailAddress -Value $pluginManifest.author.email)) {
                    $issues.Add("Plugin manifest author.email must be a valid email address")
                }
            }
        }
    }
    catch {
        $issues.Add("Plugin manifest is not valid JSON: $($_.Exception.Message)")
    }
}

$agencyManifestPath = Join-Path $resolvedPluginRoot 'agency.json'
if (Test-Path -LiteralPath $agencyManifestPath) {
    try {
        $agencyManifest = Get-Content -LiteralPath $agencyManifestPath -Raw | ConvertFrom-Json -ErrorAction Stop
        if (-not $agencyManifest.PSObject.Properties.Name.Contains('engines')) {
            $issues.Add("agency.json is missing required property 'engines'")
        }
    }
    catch {
        $issues.Add("agency.json is not valid JSON: $($_.Exception.Message)")
    }
}

$helperRoot = Split-Path -Parent $PSCommandPath
foreach ($helperName in $requiredRepoHelpers) {
    $helperPath = Join-Path $helperRoot $helperName
    if (-not (Test-Path -LiteralPath $helperPath)) {
        $issues.Add("Missing required plugin helper: tools/playground-plugin/$helperName")
    }
}

Write-Output 'Playground plugin validation summary'
Write-Output ("  Plugin Root  : {0}" -f $resolvedPluginRoot)
Write-Output ("  Issue Count  : {0}" -f $issues.Count)

if ($issues.Count -gt 0) {
    Write-Output ''
    Write-Output 'Issues'
    foreach ($issue in $issues) {
        Write-Output ("  - {0}" -f $issue)
    }
    exit 1
}

Write-Output '  Status       : passed'
