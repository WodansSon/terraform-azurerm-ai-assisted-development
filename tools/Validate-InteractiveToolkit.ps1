[CmdletBinding()]
param(
    [ValidateSet('Text', 'Json')]
    [string]$OutputFormat = 'Text',

    [ValidateSet('Auto', 'Worktree', 'Branch', 'Combined')]
    [string]$ChangedRegressionScope = 'Auto',

    [switch]$SkipChangelog,

    [switch]$ChangelogNotRequired,

    [string]$ChangelogReason,

    [switch]$SkipRegressionHarness,

    [switch]$SkipUpstreamDrift,

    [switch]$AllowCatalogIssues,

    [switch]$AllowDrift
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$arguments = @{
    OutputFormat = $OutputFormat
    ChangedRegressionScope = $ChangedRegressionScope
}

foreach ($switchName in @('SkipChangelog', 'ChangelogNotRequired', 'SkipRegressionHarness', 'SkipUpstreamDrift', 'AllowCatalogIssues', 'AllowDrift')) {
    if ($PSBoundParameters.ContainsKey($switchName)) {
        $arguments[$switchName] = $true
    }
}

if ($PSBoundParameters.ContainsKey('ChangelogReason')) {
    $arguments.ChangelogReason = $ChangelogReason
}

& (Join-Path $PSScriptRoot 'validate-ai-toolkit.ps1') @arguments
$exitCode = if ($null -ne $LASTEXITCODE) { $LASTEXITCODE } else { 0 }

if ($exitCode -ne 0) {
    exit $exitCode
}
