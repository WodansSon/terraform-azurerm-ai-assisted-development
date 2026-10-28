[CmdletBinding()]
param(
    [Parameter()]
    [string] $IconDirectory = (Join-Path $PSScriptRoot '../../../workbench/icons/fluent')
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'WorkbenchIconAssets.ps1')
New-WorkbenchIconAssets -IconDirectory $IconDirectory
