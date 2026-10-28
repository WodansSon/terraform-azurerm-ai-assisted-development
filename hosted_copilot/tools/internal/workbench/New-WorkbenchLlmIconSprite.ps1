[CmdletBinding()]
param(
    [Parameter()]
    [string] $IconDirectory = (Join-Path $PSScriptRoot '../../../workbench/icons/llms')
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'WorkbenchIconAssets.ps1')
New-WorkbenchIconAssets -IconDirectory $IconDirectory
