[CmdletBinding()]
param(
    [string]$PluginRoot = (Join-Path (Split-Path -Parent $PSScriptRoot) '..\plugins\terraform-azurerm-ai-toolkit'),
    [string]$OutputRoot,
    [string]$PackageName = 'terraform-azurerm-ai-toolkit',
    [string]$MarketplaceName = 'terraform-azurerm-ai-toolkit-local',
    [switch]$SkipValidate,
    [switch]$StartCli
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$helperRoot = [System.IO.Path]::GetFullPath($PSScriptRoot)
$resolvedPluginRoot = [System.IO.Path]::GetFullPath($PluginRoot)
$exportHelperPath = Join-Path $helperRoot 'export-plugin.ps1'

if ([string]::IsNullOrWhiteSpace($OutputRoot)) {
    $OutputRoot = Join-Path $resolvedPluginRoot 'export\staged'
}

$resolvedOutputRoot = [System.IO.Path]::GetFullPath($OutputRoot)
$stagedPluginRoot = Join-Path $resolvedOutputRoot $PackageName
$marketplaceRoot = $resolvedOutputRoot
$marketplaceInstallSpec = '{0}@{1}' -f $PackageName, $MarketplaceName

function Get-CopilotTextOutput {
    param(
        [Parameter(Mandatory)]
        [string[]]$Arguments
    )

    $output = & copilot @Arguments 2>&1
    return @($output | ForEach-Object { "$_" })
}

function Test-OutputContains {
    param(
        [AllowNull()]
        [AllowEmptyString()]
        [object]$Lines,
        [Parameter(Mandatory)]
        [string]$Needle
    )

    if ($null -eq $Lines) {
        return $false
    }

    $lineArray = @($Lines | ForEach-Object { "$_" })
    if ($lineArray.Count -eq 0) {
        return $false
    }

    return ($lineArray | Where-Object { $_ -match [regex]::Escape($Needle) } | Measure-Object).Count -gt 0
}

if (-not (Get-Command copilot -ErrorAction SilentlyContinue)) {
    throw 'The `copilot` CLI was not found on PATH.'
}

$exportArguments = @(
    '-NoProfile'
    '-File'
    $exportHelperPath
    '-PluginRoot'
    $resolvedPluginRoot
    '-OutputRoot'
    $resolvedOutputRoot
    '-PackageName'
    $PackageName
    '-MarketplaceName'
    $MarketplaceName
    '-Clean'
)

if ($SkipValidate) {
    $exportArguments += '-SkipValidate'
}

& pwsh @exportArguments | Out-Null

$pluginListOutput = Get-CopilotTextOutput -Arguments @('plugin', 'list')
if (Test-OutputContains -Lines $pluginListOutput -Needle $PackageName) {
    & copilot plugin uninstall $PackageName | Out-Null
}

$marketplaceListOutput = Get-CopilotTextOutput -Arguments @('plugin', 'marketplace', 'list')
if (Test-OutputContains -Lines $marketplaceListOutput -Needle $MarketplaceName) {
    & copilot plugin marketplace remove $MarketplaceName | Out-Null
}

& copilot plugin marketplace add $marketplaceRoot | Out-Null
& copilot plugin install $marketplaceInstallSpec | Out-Null

Write-Output 'Playground staged plugin smoke-test summary'
Write-Output ("  Plugin Root        : {0}" -f $resolvedPluginRoot)
Write-Output ("  Staged Plugin      : {0}" -f $stagedPluginRoot)
Write-Output ("  Marketplace Root   : {0}" -f $marketplaceRoot)
Write-Output ("  Marketplace Name   : {0}" -f $MarketplaceName)
Write-Output ("  Installed Plugin   : {0}" -f $marketplaceInstallSpec)
Write-Output ''
Write-Output 'Next step'
if ($StartCli) {
    Write-Output '  Starting GitHub Copilot CLI with no additional arguments.'
    & copilot
}
else {
    Write-Output '  Start a fresh Copilot CLI session and verify the installed plugin agents with `/agent`.'
}
