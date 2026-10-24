Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$arguments = @($args)
if ('-p' -cin $arguments -or '--prompt' -cin $arguments -or '' -cin $arguments) { throw 'Inline evaluation must use stdin without a prompt argument' }
$directoryIndex = [Array]::IndexOf($arguments, '-C')
$modelIndex = [Array]::IndexOf($arguments, '--model')
$effortIndex = [Array]::IndexOf($arguments, '--effort')
if ($directoryIndex -lt 0 -or $modelIndex -lt 0 -or $effortIndex -lt 0) { throw 'Native evaluator arguments are incomplete' }
$directory = [string]$arguments[$directoryIndex + 1]
$model = [string]$arguments[$modelIndex + 1]
$effort = [string]$arguments[$effortIndex + 1]
$prompt = [Console]::In.ReadToEnd()
$marker = "`n## Supplied Files`n"
$offset = $prompt.LastIndexOf($marker, [StringComparison]::Ordinal)
if ($offset -lt 0 -or -not $prompt.Contains('## Boundaries', [StringComparison]::Ordinal)) { throw 'Inline evaluation omitted its prompt or boundaries' }
$files = $prompt.Substring($offset + $marker.Length) | ConvertFrom-Json -Depth 100 -DateKind String
foreach ($property in $files.PSObject.Properties) {
    $expected = Get-Content -LiteralPath (Join-Path $directory $property.Name) -Raw | ConvertFrom-Json -Depth 100 -DateKind String
    if (($expected | ConvertTo-Json -Depth 100 -Compress) -cne ($property.Value | ConvertTo-Json -Depth 100 -Compress)) { throw 'Inline evaluation changed authoritative file contents' }
}
$manual = $null -ne $files.PSObject.Properties['manual-rule-relationship-input.json']
if ($manual) {
    $result = [ordered]@{ schemaVersion = 1; ruleTextSha256 = $files.'manual-rule-relationship-input.json'.ruleTextSha256; relationships = @() }
    $targets = @()
}
else {
    $inputData = $files.'stage-input.json'
    $targets = @($inputData.payload.editContext.assessmentContext.sources.candidateKey)
    $resultPath = Join-Path $directory 'inline-fixture-result.json'
    & (Join-Path $PSScriptRoot 'rule-issue-adjudication-evaluator.ps1') -Stage adjudication `
        -InputPath (Join-Path $directory 'stage-input.json') -CatalogPath (Join-Path $directory 'instruction-catalog.json') `
        -ProtectedRulesPath (Join-Path $directory 'protected-rules.json') -ContractPath (Join-Path $directory 'stage-contract.json') `
        -SchemaPath (Join-Path $directory 'stage-result.schema.json') -PromptPath (Join-Path $directory 'stage-prompt.md') `
        -OutputPath $resultPath -EvaluatorCommand 'native-inline-fixture' -Model $model -ReasoningEffort $effort
    $result = Get-Content -LiteralPath $resultPath -Raw | ConvertFrom-Json -Depth 100 -DateKind String
}
$metricsPath = [Environment]::GetEnvironmentVariable('HOSTED_TEST_COPILOT_METRICS')
if ([string]::IsNullOrWhiteSpace($metricsPath)) { throw 'Native inline fixture requires a metrics path' }
[IO.File]::AppendAllText($metricsPath, (([ordered]@{
    manual = $manual; bytes = [Text.Encoding]::UTF8.GetByteCount($prompt); fileCount = @($files.PSObject.Properties).Count
    candidates = $targets; model = $model; effort = $effort
} | ConvertTo-Json -Compress) + "`n"))
[Console]::Error.WriteLine('Synthetic legitimate CLI diagnostic on stderr.')
[ordered]@{ type = 'assistant.message'; data = [ordered]@{ model = $model; content = ($result | ConvertTo-Json -Depth 100 -Compress) } } | ConvertTo-Json -Depth 100 -Compress
