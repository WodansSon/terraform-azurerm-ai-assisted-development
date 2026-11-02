[CmdletBinding()]
param(
    [string] $IconRoot = $PSScriptRoot,
    [string] $Destination = (Join-Path $PSScriptRoot '../../../workbench/sprite'),
    [switch] $SkipPreviews
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'WorkbenchIconAssets.ps1')
New-WorkbenchSprite -IconRoot $IconRoot -Destination $Destination -SkipPreviews:$SkipPreviews
