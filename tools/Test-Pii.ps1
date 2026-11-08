[CmdletBinding()]
param(
    [string]$RepositoryRoot = (Join-Path $PSScriptRoot '..'),
    [ValidateSet('Worktree', 'Staged', 'Outgoing')][string]$Scope = 'Worktree',
    [string]$BaseRef = '',
    [string]$HeadRef = 'HEAD',
    [ValidateSet('Text', 'Json')][string]$OutputFormat = 'Text'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'ValidationOutput.psm1') -Force
Import-Module (Join-Path $PSScriptRoot 'privacy/Pii.psm1') -Force
$exitCode = 0
try {
    $identifiers = @($env:USERNAME, $env:COMPUTERNAME)
    if (-not [string]::IsNullOrWhiteSpace($env:USERPROFILE)) { $identifiers += Split-Path -Leaf $env:USERPROFILE }
    if (-not [string]::IsNullOrWhiteSpace($env:USER)) { $identifiers += $env:USER }
    $identifiers = @($identifiers | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -Unique)
    if ($identifiers.Count -eq 0) { throw 'Local identity checks could not be established' }
    $scan = Invoke-RepositoryPrivacyScan -RepositoryRoot $RepositoryRoot -Scope $Scope -PrivateIdentifier $identifiers -BaseRef $BaseRef -HeadRef $HeadRef
    $exitCode = if ($scan.findings.Count -gt 0) { 1 } else { 0 }
    $result = [pscustomobject]@{ status = if ($exitCode) { 'failed' } else { 'passed' }; scope = $Scope; files = $scan.files;
        revisions = $scan.revisions; baseline = $scan.baseline; head = $scan.head; findings = $scan.findings; failureCode = $null }
} catch {
    $exitCode = 2
    $result = [pscustomobject]@{ status = 'failed'; scope = $Scope; files = 0; revisions = 0; baseline = $null; head = $null; findings = @(); failureCode = 'privacy-inspection-incomplete' }
}
if ($OutputFormat -eq 'Json') { $result | ConvertTo-Json -Depth 6 }
else {
    Write-ValidationSectionHeader -Title 'Repository Privacy Check'
    Write-ValidationSummary -Fields ([ordered]@{ Status = $result.status.ToUpperInvariant(); Scope = $Scope; Files = $result.files; Revisions = $result.revisions; Findings = $result.findings.Count })
    if ($result.failureCode) { Format-ValidationStatusLine -Status failed -Name 'privacy-inspection' -Detail 'Inspection could not complete; no passing privacy claim or raw diagnostics' }
    if ($result.findings.Count -gt 0) {
        Write-ValidationSectionHeader -Title 'Privacy Findings'
        foreach ($finding in $result.findings) {
            $detail = $finding.path + ':' + $finding.line
            if ($finding.revision) { $detail += ' [' + $finding.revision + ']' }
            Format-ValidationStatusLine -Status failed -Name $finding.rule -Detail $detail
        }
    }
    Complete-ValidationTextOutput
}
exit $exitCode
