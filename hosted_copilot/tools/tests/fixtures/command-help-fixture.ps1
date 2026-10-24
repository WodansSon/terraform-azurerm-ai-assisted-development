<#
.SYNOPSIS
Exercises the shared Hosted command help renderer.

.DESCRIPTION
Provides default and alternate parameter sets plus an operation-only side effect for focused help validation.

.PARAMETER Help
Displays the curated Hosted command help and exits without performing fixture work.

.PARAMETER Detailed
Displays the curated Hosted command help and exits without performing fixture work.

.PARAMETER Name
Specifies the name rendered by the default operation.

.PARAMETER Alternate
Selects the alternate operation.

.EXAMPLE
pwsh -NoProfile -File ./command-help-fixture.ps1
Runs the default fixture operation.

.EXAMPLE
pwsh -NoProfile -File ./command-help-fixture.ps1 -Alternate
Runs the alternate fixture operation.

.NOTES
This fixture exists only for deterministic command-help validation.

.LINK
https://learn.microsoft.com/powershell/module/microsoft.powershell.core/about/about_comment_based_help
#>
[CmdletBinding(DefaultParameterSetName = 'Default')]
param(
    [Parameter(Mandatory, ParameterSetName = 'Help')]
    [Alias('h')]
    [switch]$Help,

    [Parameter(Mandatory, ParameterSetName = 'Detailed')]
    [switch]$Detailed,

    [Parameter(ParameterSetName = 'Default')]
    [string]$Name = 'World',

    [Parameter(Mandatory, ParameterSetName = 'Alternate')]
    [switch]$Alternate
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Import-Module (Join-Path $PSScriptRoot '../../modules/shared/HostedCommandHelp.psm1') -Force

if ($Help -or $Detailed) {
    Show-HostedCommandHelp -ScriptPath $PSCommandPath
    return
}

if (-not [string]::IsNullOrWhiteSpace($env:HOSTED_COMMAND_HELP_SENTINEL)) {
    [IO.File]::WriteAllText($env:HOSTED_COMMAND_HELP_SENTINEL, 'operation-ran')
}

if ($Alternate) {
    Write-Output 'Alternate operation'
}
else {
    Write-Output "Hello $Name"
}
