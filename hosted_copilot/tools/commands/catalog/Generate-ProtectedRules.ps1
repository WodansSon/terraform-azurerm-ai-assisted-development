[CmdletBinding()]
param(
    [string]$SourceRoot = (Join-Path $PSScriptRoot '../../../authored-rules/protected'),

    [string]$RepositoryRoot = (Join-Path $PSScriptRoot '../../../../'),

    [string]$OutputPath = (Join-Path $PSScriptRoot '../../../copilot-rule-catalog/protected-rules.json'),

    [switch]$Write,

    [ValidateSet('Text', 'Json')]
    [string]$OutputFormat = 'Text'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$validationOutputModulePath = Join-Path $PSScriptRoot '../../../../tools/ValidationOutput.psm1'
$parserModulePath = Join-Path $PSScriptRoot '../../modules/source-parsers/ProtectedRules.psm1'
Import-Module -Name $validationOutputModulePath -Force
Import-Module -Name $parserModulePath -Force

$resolvedSourceRoot = [IO.Path]::GetFullPath($SourceRoot)
$resolvedRepositoryRoot = [IO.Path]::GetFullPath($RepositoryRoot)
$resolvedOutputPath = [IO.Path]::GetFullPath($OutputPath)
$registry = Get-ProtectedRulesCatalog -SourceRoot $resolvedSourceRoot -RepositoryRoot $resolvedRepositoryRoot

$content = ConvertTo-ProtectedRulesJson -Catalog $registry
$protectedSchemaPath = Join-Path (Split-Path -Parent $resolvedOutputPath) 'protected-rules.schema.json'
if (-not ($content | Test-Json -SchemaFile $protectedSchemaPath -ErrorAction SilentlyContinue)) {
    throw 'Protected rules schema validation failed'
}
$existingContent = if (Test-Path -LiteralPath $resolvedOutputPath -PathType Leaf) { [IO.File]::ReadAllText($resolvedOutputPath) } else { $null }
$fresh = $existingContent -ceq $content

if ($Write -and -not $fresh) {
    $outputDirectory = Split-Path -Parent $resolvedOutputPath
    if (-not (Test-Path -LiteralPath $outputDirectory -PathType Container)) {
        New-Item -ItemType Directory -Path $outputDirectory -Force | Out-Null
    }
    [IO.File]::WriteAllText($resolvedOutputPath, $content, [Text.UTF8Encoding]::new($false))
    $fresh = $true
}

$result = [ordered]@{
    status = if ($fresh) { 'passed' } else { 'failed' }
    mode = if ($Write) { 'write' } else { 'check' }
    sourceRoot = $resolvedSourceRoot
    outputPath = $resolvedOutputPath
    ruleCount = @($registry.rules).Count
    fresh = $fresh
}

if ($OutputFormat -eq 'Json') {
    $result | ConvertTo-Json -Depth 4
}
else {
    Write-ValidationSectionHeader -Title 'Protected rule generation'
    Write-ValidationSummary -Fields ([ordered]@{
        Status = $result.status.ToUpperInvariant()
        Mode = $result.mode.ToUpperInvariant()
        Rules = $result.ruleCount
        Fresh = $result.fresh
    })
    if (-not $fresh) {
        Write-ValidationSectionHeader -Title 'Failures'
        Write-Output '  - Generated protected rules are stale; rerun with -Write after reviewing the Markdown sources.'
    }
    Complete-ValidationTextOutput
}

if (-not $fresh) {
    exit 1
}
