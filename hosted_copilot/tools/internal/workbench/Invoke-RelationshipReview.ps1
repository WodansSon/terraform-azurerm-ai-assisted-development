[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$RepositoryRoot,
    [Parameter(Mandatory)][string]$DisplayPath,
    [Parameter(Mandatory)][string]$RequestPath,
    [Parameter(Mandatory)][string]$OutputPath,
    [string]$ReceiptDirectory,
    [string]$EvaluatorCommand = 'copilot',
    [string]$EvaluatorScriptPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot '../../modules/workbench/RelationshipReview.psm1') -DisableNameChecking
Import-Module (Join-Path $PSScriptRoot '../../modules/shared/HostedToolkit.Helpers.psm1')
Import-Module (Join-Path $PSScriptRoot '../../modules/shared/HostedCli.psm1')
$watch = [Diagnostics.Stopwatch]::StartNew()
$process = $null
$started = $false
try {
    $runtime = Get-RelationshipReviewRuntime -RepositoryRoot $RepositoryRoot -DisplayPath $DisplayPath
    $request = Get-Content -LiteralPath $RequestPath -Raw | ConvertFrom-Json -Depth 100 -DateKind String
    if ($request.authoritySha256 -cne $runtime.authoritySha256) { throw (New-RelationshipReviewException 'snapshot-changed') }
    $displayJson = Get-Content -LiteralPath $DisplayPath -Raw
    $displaySchema = Join-Path $RepositoryRoot 'hosted_copilot/contracts/workbench/workbench-display-v4.schema.json'
    if (-not (Test-Json -Json $displayJson -SchemaFile $displaySchema -ErrorAction Stop)) { throw (New-RelationshipReviewException 'invalid-request') }
    $inputData = Get-RelationshipReviewInput -Display ($displayJson | ConvertFrom-Json -Depth 100 -DateKind String) -Request $request
    $schema = Get-RelationshipReviewResponseSchema $inputData
    $schemaJson = $schema | ConvertTo-Json -Depth 30 -Compress
    $inputJson = $inputData | ConvertTo-Json -Depth 100 -Compress
    $prompt = Get-Content -LiteralPath (Join-Path $RepositoryRoot 'hosted_copilot/tools/prompts/reconciliation/RelationshipReview-v1.md') -Raw
    $requestText = $prompt + "`n`n## Supplied Response Schema`n" + $schemaJson + "`n`n## Supplied Quoted Catalog Data`n" + $inputJson
    $result = [pscustomobject]@{ findings = @() }
    if ($inputData.changedRuleIds.Count -gt 0) {
        if ($EvaluatorScriptPath) {
            $start = [Diagnostics.ProcessStartInfo]::new('pwsh')
            $start.UseShellExecute = $false
            $start.RedirectStandardInput = $true
            $start.RedirectStandardOutput = $true
            $start.RedirectStandardError = $true
            foreach ($argument in @('-NoProfile', '-NonInteractive', '-File', $EvaluatorScriptPath)) { $start.ArgumentList.Add($argument) }
        } else {
            try { $launch = Resolve-HostedCliLaunch -EvaluatorCommand $EvaluatorCommand }
            catch { throw (New-RelationshipReviewException 'runtime-unavailable') }
            $directory = Split-Path -Parent $OutputPath
            $start = New-HostedCliStartInfo -Launch $launch -WorkingDirectory $directory -Arguments @(
                '-C', $directory, '--no-color', '--stream', 'off', '--no-custom-instructions', '--no-ask-user', '--disable-builtin-mcps', '--no-auto-update', '--disallow-temp-dir', '--no-remote-export',
                '--model', $runtime.model, '--reasoning-effort', $runtime.reasoningEffort, '--context', 'default', '--available-tools', '--output-format', 'json', '--log-level', 'none', '--log-dir', (Join-Path $directory 'logs')
            )
        }
        $process = [Diagnostics.Process]::new()
        $process.StartInfo = $start
        try { $started = $process.Start() }
        catch { throw (New-RelationshipReviewException 'runtime-unavailable') }
        if (-not $started) { throw (New-RelationshipReviewException 'runtime-unavailable') }
        $stdout = $process.StandardOutput.ReadToEndAsync()
        $stderr = $process.StandardError.ReadToEndAsync()
        $null = Wait-RelationshipReviewTask -Task ($process.StandardInput.WriteAsync($requestText)) -Watch $watch -DeadlineMilliseconds $runtime.deadlineMilliseconds
        $process.StandardInput.Close()
        $remaining = [Math]::Max(1, $runtime.deadlineMilliseconds - [int]$watch.ElapsedMilliseconds)
        if (-not $process.WaitForExit($remaining)) { throw (New-RelationshipReviewException 'deadline') }
        $output = Wait-RelationshipReviewTask -Task $stdout -Watch $watch -DeadlineMilliseconds $runtime.deadlineMilliseconds
        $null = Wait-RelationshipReviewTask -Task $stderr -Watch $watch -DeadlineMilliseconds $runtime.deadlineMilliseconds
        if ($process.ExitCode -ne 0) { throw (New-RelationshipReviewException 'runtime-unavailable') }
        Import-Module (Join-Path $PSScriptRoot '../../modules/workbench/RuleAssistance.psm1') -DisableNameChecking
        try {
            $diagnostic = [ordered]@{ events = [ordered]@{ other = 0; 'model.call_start' = 0 }; answerCount = 0 }
            $answer = Get-RuleAssistanceCliAnswer -Output $output -Model $runtime.model -Diagnostic $diagnostic
        } catch {
            $base = $_.Exception.GetBaseException()
            $knownCode = $base.Data['RuleAssistanceCode']
            $code = if ($knownCode -cin @('cli-response-error', 'tool-operation')) { 'runtime-unavailable' } else { 'invalid-response' }
            throw (New-RelationshipReviewException $code)
        }
        if ($diagnostic.events['model.call_start'] -ne 1) { throw (New-RelationshipReviewException 'invalid-response') }
        $result = Test-RelationshipReviewResult -Json $answer.Trim() -InputData $inputData
    }
    if ($watch.ElapsedMilliseconds -gt $runtime.deadlineMilliseconds) { throw (New-RelationshipReviewException 'deadline') }
    $current = Get-RelationshipReviewRuntime -RepositoryRoot $RepositoryRoot -DisplayPath $DisplayPath
    if ($current.authoritySha256 -cne $runtime.authoritySha256) { throw (New-RelationshipReviewException 'snapshot-changed') }
    $response = [ordered]@{
        schemaVersion = 1; requestId = $request.requestId; candidateKey = $request.candidateKey
        authoritySha256 = $runtime.authoritySha256; snapshotKey = $request.snapshotKey
        inputSha256 = Get-JsonSnapshotSha256 -Value $inputData -Depth 100
        changedRuleIds = $inputData.changedRuleIds; removedRuleIds = $inputData.removedRuleIds
        effectiveRuleIds = @($inputData.effectiveCatalog | ForEach-Object id); findings = @($result.findings)
        elapsedMilliseconds = [int]$watch.ElapsedMilliseconds; model = $runtime.model; reasoningEffort = $runtime.reasoningEffort
    }
    if ($ReceiptDirectory) {
        $null = [IO.Directory]::CreateDirectory($ReceiptDirectory)
        $receipt = [ordered]@{ candidateKey = $request.candidateKey; authoritySha256 = $runtime.authoritySha256;
            contextSha256 = Get-JsonSnapshotSha256 -Depth 100 -Value ([ordered]@{ sourceFiles = $request.sourceFiles; proposals = $request.proposals }); result = $response }
        Write-JsonSnapshot -Path (Join-Path $ReceiptDirectory ([string]$request.requestId + '.json')) -Value $receipt
    }
    Write-JsonSnapshot -Path $OutputPath -Value $response
} catch {
    $exception = $_.Exception.GetBaseException()
    $code = if ($exception.Data.Contains('RelationshipReviewCode')) { [string]$exception.Data['RelationshipReviewCode'] } else { 'unexpected-failure' }
    [Console]::Error.WriteLine((@{ error = (Get-RelationshipReviewFailure $code) } | ConvertTo-Json -Compress))
    throw [InvalidOperationException]::new('Relationship review failed; raw diagnostics were not returned')
} finally {
    if ($null -ne $process) {
        if ($started -and -not $process.HasExited) { $process.Kill($true); $process.WaitForExit() }
        $process.Dispose()
    }
    $watch.Stop()
}
