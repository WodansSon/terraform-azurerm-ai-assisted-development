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
$command = Get-Command $EvaluatorCommand -ErrorAction SilentlyContinue
if ($null -eq $command) {
	throw "Copilot evaluator command was not found: $EvaluatorCommand"
}

$prompt = "Read stage-input.json, instruction-catalog.json, protected-rules.json, stage-contract.json, stage-result.schema.json, and stage-prompt.md in the current directory. Evaluate the complete bounded $Stage shard and return only the JSON object required by stage-result.schema.json."
$inputData = Get-Content -LiteralPath $resolvedInputs.InputPath -Raw | ConvertFrom-Json -Depth 100 -DateKind String
$inline = $Stage -ceq 'manual-relationship' -or ($Stage -ceq 'adjudication' -and $null -ne $inputData.payload.PSObject.Properties['editContext'])
if ($inline) {
	$files = [ordered]@{}
	foreach ($pathName in @($pathNames | Where-Object { $_ -cne 'PromptPath' })) {
		$path = $resolvedInputs[$pathName]
		$files[[IO.Path]::GetFileName($path)] = Get-Content -LiteralPath $path -Raw | ConvertFrom-Json -Depth 100 -DateKind String
	}
	$prompt = "All required files are supplied in full below. Evaluate their contents without tool calls.`n`n" + (Get-Content -LiteralPath $resolvedInputs.PromptPath -Raw) + "`n`n## Supplied Files`n" + ($files | ConvertTo-Json -Depth 100 -Compress)
}
$processInfo = [Diagnostics.ProcessStartInfo]::new()
$commandPrefixArguments = @()
if ($command.CommandType -eq [Management.Automation.CommandTypes]::ExternalScript) {
	$processInfo.FileName = [Diagnostics.Process]::GetCurrentProcess().MainModule.FileName
	$commandPrefixArguments = @('-NoLogo', '-NoProfile', '-NonInteractive', '-File', [string]$command.Source)
}
else {
	$processInfo.FileName = $command.Source
}
$processInfo.WorkingDirectory = $workingDirectory
$processInfo.UseShellExecute = $false
$processInfo.RedirectStandardOutput = $true
$processInfo.RedirectStandardError = $true
$processInfo.RedirectStandardInput = $inline
$processInfo.StandardOutputEncoding = [Text.UTF8Encoding]::new($false)
$processInfo.StandardErrorEncoding = [Text.UTF8Encoding]::new($false)
if ($inline) { $processInfo.StandardInputEncoding = [Text.UTF8Encoding]::new($false) }
$promptArguments = @(if (-not $inline) { '-p'; $prompt })
foreach ($argument in @($commandPrefixArguments) + @('-C', $workingDirectory) + $promptArguments + @(
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
)) {
	$null = $processInfo.ArgumentList.Add([string]$argument)
}

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
		throw "Copilot evaluator exited with code $($process.ExitCode): $($stderr.Trim())"
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
			throw "Copilot evaluator returned a non-JSONL event: $line"
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
	throw "Copilot evaluator used model $($assistantMessage.model) instead of $Model."
}
$resultJson = Get-StageEvaluatorJson -Content ([string]$assistantMessage.content)
try {
	if (-not ($resultJson | Test-Json -SchemaFile $resolvedInputs.SchemaPath -ErrorAction Stop)) {
		throw 'Stage result does not satisfy its schema.'
	}
}
catch {
	throw "Copilot $Stage result does not satisfy its schema: $($_.Exception.Message)"
}

[IO.File]::WriteAllText($OutputPath, ($resultJson + "`n"), [Text.UTF8Encoding]::new($false))
