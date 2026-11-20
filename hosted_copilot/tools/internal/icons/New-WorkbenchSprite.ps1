[CmdletBinding()]
param(
    [string] $IconRoot = $PSScriptRoot,
    [ValidateNotNullOrEmpty()]
    [string[]] $Destination = @(
        (Join-Path $PSScriptRoot '../../../workbench/sprite')
    ),
    [switch] $SkipPreviews
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'WorkbenchIconAssets.ps1')
for ($index = 0; $index -lt $Destination.Count; $index++) {
    New-WorkbenchSprite -IconRoot $IconRoot -Destination $Destination[$index] -SkipPreviews:($SkipPreviews -or $index -gt 0)
}
