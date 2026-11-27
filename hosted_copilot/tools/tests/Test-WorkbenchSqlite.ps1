[CmdletBinding()]
param(
    [ValidateSet('Text', 'Json')]
    [string]$OutputFormat = 'Text',
    [string]$TestNamePattern = ''
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Import-Module -Name (Join-Path $PSScriptRoot '../modules/workbench/Workbench.NodeTests.psm1') -Force
Invoke-WorkbenchNodeTests -TestPath (Join-Path $PSScriptRoot 'sqlite/workbench-sqlite.test.mjs') -Title 'Hosted Workbench SQLite tests' -OutputFormat $OutputFormat -TestNamePattern $TestNamePattern
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
