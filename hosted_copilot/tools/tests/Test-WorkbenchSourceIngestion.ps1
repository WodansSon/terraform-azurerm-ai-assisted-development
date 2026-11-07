[CmdletBinding()]
param(
    [ValidateSet('Text', 'Json')]
    [string]$OutputFormat = 'Text'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Import-Module -Name (Join-Path $PSScriptRoot '../modules/workbench/Workbench.NodeTests.psm1') -Force
Invoke-WorkbenchNodeTests -TestPath (Join-Path $PSScriptRoot 'sqlite/workbench-source-ingestion.test.mjs') -Title 'Hosted Workbench source ingestion tests' -OutputFormat $OutputFormat
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
