Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
if ('--headless' -cin @($args)) {
	& (Join-Path $PSScriptRoot 'copilot-metadata-evaluator.ps1') @args
	return
}
$requestText = [Console]::In.ReadToEnd()
$profile = (Get-Content -LiteralPath (Join-Path $PSScriptRoot '../../config/llm.json') -Raw | ConvertFrom-Json -DateKind String).ruleEvaluation
if ('--model' -cin @($args)) {
	$modelIndex = [Array]::IndexOf([object[]]$args, '--model')
	if ($args[$modelIndex + 1] -cne $profile.model) { throw 'Relationship fixture received the wrong model profile' }
}
$mode = [Environment]::GetEnvironmentVariable('HOSTED_RELATIONSHIP_FIXTURE_MODE')
$markerPath = [Environment]::GetEnvironmentVariable('HOSTED_RELATIONSHIP_FIXTURE_MARKER')
if ($markerPath) {
	$count = if (Test-Path -LiteralPath $markerPath) { [int](Get-Content -LiteralPath $markerPath -Raw) } else { 0 }
	[IO.File]::WriteAllText($markerPath, [string]($count + 1))
}
if ($mode -cin @('conflict', 'by-wording')) {
	$dataMarker = "## Supplied Quoted Catalog Data`n"
	$dataOffset = $requestText.IndexOf($dataMarker, [StringComparison]::Ordinal)
	if ($dataOffset -lt 0) { throw 'Relationship fixture did not receive framed catalog input' }
	$inputData = $requestText.Substring($dataOffset + $dataMarker.Length) | ConvertFrom-Json -Depth 100 -DateKind String
	$changedRule = @($inputData.effectiveCatalog | Where-Object { $_.id -ceq $inputData.changedRuleIds[0] })[0]
	if ($mode -ceq 'by-wording') {
		$mode = if ($changedRule.text.Contains('SYNTHETIC_RELATIONSHIP_CONFLICT', [StringComparison]::Ordinal)) { 'conflict' } else { 'success' }
	}
}
$content = if ($mode -ceq 'invalid') { '{"findings":[],"operations":[]}' } else { '{"findings":[]}' }
if ($mode -ceq 'conflict') {
	$relatedRule = @($inputData.effectiveCatalog | Where-Object { $_.id -ceq 'IMPL-PATCH-001' })[0]
	$content = @{ findings = @(@{ ruleId = $changedRule.id; relatedRuleId = $relatedRule.id; relationship = 'conflicts'; ruleQuote = $changedRule.text; relatedQuote = $relatedRule.text; rationale = 'Synthetic conflict used to exercise approval rejection.' }) } | ConvertTo-Json -Depth 10 -Compress
}
if ($mode -ceq 'tools') { Write-Output '{"type":"tool.execution_start","data":{}}' }
Write-Output '{"type":"model.call_start","data":{}}'
Write-Output (([ordered]@{ type = 'assistant.message'; data = @{ model = $profile.model; content = $content } }) | ConvertTo-Json -Compress)
Write-Output '{"type":"assistant.turn_end","data":{}}'
Write-Output '{"type":"result","data":{}}'
