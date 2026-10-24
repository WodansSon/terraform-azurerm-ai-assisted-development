[CmdletBinding()]
param(
	[Parameter(Mandatory = $true)][ValidateSet('routing', 'consolidation', 'synthesis', 'adjudication', 'manual-relationship')][string]$Stage,
	[Parameter(Mandatory = $true)][string]$InputPath,
	[string]$CatalogPath,
	[string]$ProtectedRulesPath,
	[string]$ContractPath,
	[Parameter(Mandatory = $true)][string]$SchemaPath,
	[Parameter(Mandatory = $true)][string]$PromptPath,
	[Parameter(Mandatory = $true)][string]$OutputPath,
	[Parameter(Mandatory = $true)][string]$EvaluatorCommand,
	[Parameter(Mandatory = $true)][string]$Model,
	[Parameter(Mandatory = $true)][ValidateSet('low', 'medium', 'high', 'xhigh')][string]$ReasoningEffort
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot '../../modules/shared/HostedCli.psm1')

function Get-StageJsonDiagnostic {
	param([AllowEmptyString()][string]$Json)

	try {
		$options = [Text.Json.JsonDocumentOptions]::new()
		$options.MaxDepth = 100
		$document = [Text.Json.JsonDocument]::Parse($Json, $options)
		try {
			return [ordered]@{ valid = $true; valueKind = [string]$document.RootElement.ValueKind; lineNumber = $null; bytePositionInLine = $null }
		}
		finally { $document.Dispose() }
	}
	catch {
		$exception = $_.Exception.GetBaseException()
		return [ordered]@{
			valid = $false
			valueKind = $null
			lineNumber = $(if ($exception -is [Text.Json.JsonException]) { $exception.LineNumber } else { $null })
			bytePositionInLine = $(if ($exception -is [Text.Json.JsonException]) { $exception.BytePositionInLine } else { $null })
		}
	}
}

function Get-StageSchemaDiagnostic {
	param([AllowEmptyString()][string]$Json)

	try {
		$documentOptions = [Text.Json.JsonDocumentOptions]::new()
		$documentOptions.MaxDepth = 100
		$instance = [Text.Json.Nodes.JsonNode]::Parse($Json, $null, $documentOptions)
		$schema = [Json.Schema.JsonSchema]::FromFile($resolvedInputs.SchemaPath)
		$options = [Json.Schema.EvaluationOptions]::new()
		$options.OutputFormat = [Json.Schema.OutputFormat]::Hierarchical
		$evaluation = $schema.Evaluate($instance, $options)
		$pending = [Collections.Generic.Stack[object]]::new()
		$pending.Push($evaluation)
		$errors = [Collections.Generic.List[object]]::new()
		$visited = 0
		$keywords = @('type', 'required', 'additionalProperties', 'unevaluatedProperties', 'properties', 'propertyNames', 'patternProperties', 'const', 'enum', 'pattern', 'format', 'minLength', 'maxLength', 'minItems', 'maxItems', 'uniqueItems', 'items', 'prefixItems', 'contains', 'minContains', 'maxContains', 'minimum', 'maximum', 'exclusiveMinimum', 'exclusiveMaximum', 'multipleOf', 'minProperties', 'maxProperties', 'allOf', 'anyOf', 'oneOf', 'not', 'if', 'then', 'else', 'dependentRequired', 'dependentSchemas', '$ref', 'false')
		while ($pending.Count -gt 0 -and $visited -lt 512 -and $errors.Count -lt 16) {
			$result = $pending.Pop()
			$visited++
			if ($result.IsValid) { continue }
			if ($result.HasErrors) {
				$schemaPath = [string]$result.SchemaLocation.Fragment
				if ([string]::IsNullOrEmpty($schemaPath)) { $schemaPath = '#' }
				foreach ($keyword in @($result.Errors.Keys | Sort-Object -CaseSensitive)) {
					if ($keyword -cin $keywords -and $errors.Count -lt 16 -and $schemaPath.Length -le 256) {
						$errors.Add([ordered]@{ keyword = [string]$keyword; schemaPath = $schemaPath })
					}
				}
			}
			if ($result.HasDetails) {
				foreach ($detail in $result.Details) { $pending.Push($detail) }
			}
		}
		return [ordered]@{ available = $true; errors = @($errors.ToArray()); truncated = $pending.Count -gt 0 -or $errors.Count -ge 16 }
	}
	catch { return [ordered]@{ available = $false; errors = @(); truncated = $false } }
}

function Write-StageResponseDiagnostic {
	param(
		[ValidateSet('json-extraction', 'json-parse', 'schema-validation')][string]$Phase,
		[AllowEmptyString()][string]$Content,
		[AllowEmptyString()][string]$ExtractedJson = '',
		[object]$SchemaDiagnostic = $null
	)

	$diagnostic = [ordered]@{
		schemaVersion = 1
		kind = 'hosted-stage-response-diagnostic'
		stage = $Stage
		phase = $Phase
		assistantCharacterCount = $Content.Length
		extractedCharacterCount = $ExtractedJson.Length
		markdownFence = $Content.TrimStart().StartsWith('```', [StringComparison]::Ordinal)
		assistantJson = Get-StageJsonDiagnostic -Json $Content
		extractedJson = $(if ($ExtractedJson.Length -gt 0) { Get-StageJsonDiagnostic -Json $ExtractedJson } else { $null })
		schemaDiagnostic = $SchemaDiagnostic
	}
	try {
		[IO.File]::WriteAllText("$OutputPath.diagnostic.json", (($diagnostic | ConvertTo-Json -Depth 8) + "`n"), [Text.UTF8Encoding]::new($false))
	}
	catch { Write-Warning 'Response diagnostics could not be retained.' }
}

function Get-StageEvaluatorJson {
	param([Parameter(Mandatory = $true)][AllowEmptyString()][string]$Content)

	$trimmed = $Content.Trim()
	if ($trimmed.StartsWith('```json', [StringComparison]::OrdinalIgnoreCase) -and $trimmed.EndsWith('```', [StringComparison]::Ordinal)) {
		$trimmed = $trimmed.Substring(7, $trimmed.Length - 10).Trim()
	}
	elseif ($trimmed.StartsWith('```', [StringComparison]::Ordinal) -and $trimmed.EndsWith('```', [StringComparison]::Ordinal)) {
		$trimmed = $trimmed.Substring(3, $trimmed.Length - 6).Trim()
	}
	$objectStart = $trimmed.IndexOf('{')
	$objectEnd = $trimmed.LastIndexOf('}')
	if ($objectStart -lt 0 -or $objectEnd -lt $objectStart) {
		throw 'Copilot evaluator response does not contain a JSON object.'
	}
	return $trimmed.Substring($objectStart, $objectEnd - $objectStart + 1)
}

Remove-Item -LiteralPath "$OutputPath.diagnostic.json" -Force -ErrorAction SilentlyContinue
$resolvedInputs = @{}
$pathNames = @('InputPath', 'SchemaPath', 'PromptPath')
if ($Stage -cne 'manual-relationship') { $pathNames += @('CatalogPath', 'ProtectedRulesPath', 'ContractPath') }
foreach ($pathName in $pathNames) {
	if ([string]::IsNullOrWhiteSpace([string](Get-Variable -Name $pathName -ValueOnly))) { throw "Copilot $Stage requires $pathName" }
	$resolvedPath = [IO.Path]::GetFullPath([string](Get-Variable -Name $pathName -ValueOnly))
	if (-not (Test-Path -LiteralPath $resolvedPath -PathType Leaf)) {
		throw "Copilot reconciliation stage input was not found: $resolvedPath"
	}
	$resolvedInputs[$pathName] = $resolvedPath
}
$workingDirectory = Split-Path -Parent $resolvedInputs.InputPath
$launch = Resolve-HostedCliLaunch -EvaluatorCommand $EvaluatorCommand

$promptDirectory = Join-Path $PSScriptRoot '../../prompts/shared'
$prompt = (Get-Content -LiteralPath (Join-Path $promptDirectory 'FileEvaluation.md') -Raw).Replace('{{STAGE}}', $Stage)
$inputData = Get-Content -LiteralPath $resolvedInputs.InputPath -Raw | ConvertFrom-Json -Depth 100 -DateKind String
$inline = $Stage -ceq 'manual-relationship' -or ($Stage -ceq 'adjudication' -and $null -ne $inputData.payload.PSObject.Properties['editContext'])
if ($inline) {
	$files = [ordered]@{}
	foreach ($pathName in @($pathNames | Where-Object { $_ -cne 'PromptPath' })) {
		$path = $resolvedInputs[$pathName]
		$files[[IO.Path]::GetFileName($path)] = Get-Content -LiteralPath $path -Raw | ConvertFrom-Json -Depth 100 -DateKind String
	}
	$prompt = (Get-Content -LiteralPath (Join-Path $promptDirectory 'InlineEvaluation.md') -Raw).
		Replace('{{TASK_PROMPT}}', (Get-Content -LiteralPath $resolvedInputs.PromptPath -Raw)).
		Replace('{{SUPPLIED_FILES}}', ($files | ConvertTo-Json -Depth 100 -Compress))
}
$promptArguments = @(if (-not $inline) { '-p'; $prompt })
$processInfo = New-HostedCliStartInfo -Launch $launch -WorkingDirectory $workingDirectory -RedirectStandardInput:$inline -Arguments (@('-C', $workingDirectory) + $promptArguments + @(
	'--no-color',
	'--stream', 'off',
	'--no-custom-instructions',
	'--no-ask-user',
	'--disable-builtin-mcps',
	'--no-auto-update',
	'--disallow-temp-dir',
	'--model', $Model,
	'--effort', $ReasoningEffort,
	'--available-tools=view',
	'--output-format', 'json'
))

$process = [Diagnostics.Process]::new()
$process.StartInfo = $processInfo
try {
	if (-not $process.Start()) {
		throw 'Copilot evaluator process did not start.'
	}
	$stdoutTask = $process.StandardOutput.ReadToEndAsync()
	$stderrTask = $process.StandardError.ReadToEndAsync()
	if ($inline) {
		$process.StandardInput.Write($prompt)
		$process.StandardInput.Close()
	}
	$process.WaitForExit()
	$stdout = $stdoutTask.GetAwaiter().GetResult()
	$stderr = $stderrTask.GetAwaiter().GetResult()
	if ($process.ExitCode -ne 0) {
		throw "Copilot evaluator exited with code $($process.ExitCode); stderr contained $([Text.Encoding]::UTF8.GetByteCount($stderr)) bytes and was omitted from diagnostics"
	}
}
finally {
	$process.Dispose()
}

$assistantMessages = @($stdout -split "`r?`n" | ForEach-Object {
	$line = ([string]$_).Trim()
	if (-not [string]::IsNullOrWhiteSpace($line)) {
		try {
			$event = $line | ConvertFrom-Json -DateKind String
		}
		catch {
			throw 'Copilot evaluator returned a non-JSONL event; response contents were omitted from diagnostics'
		}
		if ([string]$event.type -ceq 'assistant.message' -and -not [string]::IsNullOrWhiteSpace([string]$event.data.content)) {
			$event.data
		}
	}
})
if ($assistantMessages.Count -eq 0) {
	throw 'Copilot evaluator did not return an assistant message.'
}
$assistantMessage = $assistantMessages[-1]
if ([string]$assistantMessage.model -cne $Model) {
	throw 'Copilot evaluator used a model other than the requested model.'
}
$content = [string]$assistantMessage.content
try {
	$resultJson = Get-StageEvaluatorJson -Content $content
}
catch {
	Write-StageResponseDiagnostic -Phase 'json-extraction' -Content $content
	throw "Copilot $Stage response does not contain an extractable JSON object; response contents were omitted from diagnostics"
}
try {
	if (-not ($resultJson | Test-Json -SchemaFile $resolvedInputs.SchemaPath -ErrorAction Stop)) {
		throw 'Stage result does not satisfy its schema.'
	}
}
catch {
	$jsonDiagnostic = Get-StageJsonDiagnostic -Json $resultJson
	if (-not $jsonDiagnostic.valid) {
		Write-StageResponseDiagnostic -Phase 'json-parse' -Content $content -ExtractedJson $resultJson
		throw "Copilot $Stage result contains invalid JSON at zero-based line $($jsonDiagnostic.lineNumber), byte $($jsonDiagnostic.bytePositionInLine); response contents were omitted from diagnostics"
	}
	$schemaDiagnostic = Get-StageSchemaDiagnostic -Json $resultJson
	Write-StageResponseDiagnostic -Phase 'schema-validation' -Content $content -ExtractedJson $resultJson -SchemaDiagnostic $schemaDiagnostic
	$keywords = @($schemaDiagnostic.errors | ForEach-Object keyword | Sort-Object -CaseSensitive -Unique) -join ', '
	$detail = if ($keywords) { "failed schema keywords: $keywords" } else { 'structured schema details unavailable' }
	throw "Copilot $Stage result does not satisfy its schema ($detail); response contents were omitted from diagnostics"
}

[IO.File]::WriteAllText($OutputPath, ($resultJson + "`n"), [Text.UTF8Encoding]::new($false))
