[CmdletBinding()]
param(
    [ValidateSet('Text', 'Json')][string]$OutputFormat = 'Text'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repositoryRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))
$validationOutputPath = Join-Path $repositoryRoot 'tools/ValidationOutput.psm1'
Import-Module -Name $validationOutputPath -Force
$runnerPath = Join-Path $repositoryRoot 'hosted_copilot/tools/internal/reconciliation/Invoke-RuleIssueAdjudication.ps1'
$exporterPath = Join-Path $repositoryRoot 'hosted_copilot/tools/internal/reconciliation/Export-WorkbenchRuleIssues.ps1'
$fixturePath = Join-Path $PSScriptRoot 'fixtures/rule-issue-adjudication-evaluator.ps1'
$inputSchemaPath = Join-Path $repositoryRoot 'hosted_copilot/copilot-rule-catalog/assessment-reconciliation/rule-issue-adjudication-input-v4.schema.json'
$draftSchemaPath = Join-Path $repositoryRoot 'hosted_copilot/copilot-rule-catalog/assessment-reconciliation/rule-issue-adjudication-draft-v4.schema.json'
$promptPath = Join-Path $repositoryRoot 'hosted_copilot/tools/assessment-reconciliation-prompts/RuleIssueAdjudication-v4.md'
$results = [Collections.Generic.List[object]]::new()
$issues = [Collections.Generic.List[string]]::new()
$root = Join-Path ([IO.Path]::GetTempPath()) ('hosted-rule-issue-adjudication-test-' + [Guid]::NewGuid().ToString('N'))
$null = New-Item -ItemType Directory -Path $root -Force
$hash = 'a' * 64

function Add-TestResult {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][bool]$Passed,
        [Parameter(Mandatory = $true)][string]$Detail
    )

    $results.Add([pscustomobject]@{ name = $Name; status = if ($Passed) { 'passed' } else { 'failed' }; detail = $Detail })
    if (-not $Passed) { $issues.Add("$Name`: $Detail") }
}

function New-ComponentInput {
    param(
        [Parameter(Mandatory = $true)][string]$Id,
        [Parameter(Mandatory = $true)][string]$ContentSha256,
        [switch]$Independent,
        [switch]$InvalidReference
    )

    $suffix = if ($Independent) { 'independent' } elseif ($InvalidReference) { 'invalid-reference' } else { 'protected' }
    return [ordered]@{
        '$schema' = 'rule-issue-adjudication-input-v4.schema.json'
        schemaVersion = 1
        kind = 'hosted-rule-issue-adjudication-input'
        componentId = "component:$suffix-$Id"
        sourceFiles = @([ordered]@{ sourceDefinitionId = 'maintainer-proposals'; sourceId = "SOURCE-$Id"; contentSha256 = $ContentSha256 })
        rules = @(
            [ordered]@{ id = 'IMPL-WF-000'; status = 'protected'; title = 'Protected'; text = 'Canonical text.'; contentSha256 = $hash; candidateKeys = @() },
            [ordered]@{ id = "IMPL-TEST-$Id"; status = 'proposed'; title = 'Proposal'; text = 'Candidate text.'; contentSha256 = $ContentSha256; candidateKeys = @("maintainer:SOURCE-$Id:A1") }
        )
        relationships = @([ordered]@{ id = "relationship-$Id"; sourceRuleId = "IMPL-TEST-$Id"; relatedRuleId = 'IMPL-WF-000'; relationship = 'equivalent'; rationale = 'Provisional relationship.'; candidateKey = "maintainer:SOURCE-$Id:A1" })
        operations = @([ordered]@{ candidateKey = "maintainer:SOURCE-$Id:A1"; ruleId = "IMPL-TEST-$Id"; action = 'exclude'; proposedText = 'Candidate text.'; retireHostedRuleIds = @() })
    }
}

try {
    $componentPaths = [Collections.Generic.List[string]]::new()
    foreach ($definition in @(@{ Id = '001'; Independent = $false }, @{ Id = '002'; Independent = $true })) {
        $path = Join-Path $root "$($definition.Id).json"
        [IO.File]::WriteAllText($path, (((New-ComponentInput -Id $definition.Id -ContentSha256 $hash -Independent:$definition.Independent) | ConvertTo-Json -Depth 30) + "`n"), [Text.UTF8Encoding]::new($false))
        $componentPaths.Add($path)
    }
    $parameters = @{
        ComponentPaths = $componentPaths.ToArray()
        OutputPath = Join-Path $root 'first.json'
        CacheDirectory = Join-Path $root 'cache'
        EvaluatorScriptPath = $fixturePath
        InputSchemaPath = $inputSchemaPath
        DraftSchemaPath = $draftSchemaPath
        PromptPath = $promptPath
        OutputFormat = 'Json'
        Quiet = $true
    }
    $first = & $runnerPath @parameters | ConvertFrom-Json
    $firstSet = Get-Content -LiteralPath $parameters.OutputPath -Raw | ConvertFrom-Json -Depth 100
    Add-TestResult -Name 'first-run-evaluates-components' -Passed ([int]$first.evaluatedComponentCount -eq 2 -and [int]$first.cachedComponentCount -eq 0) -Detail 'The first run evaluates every uncached component.'
    Add-TestResult -Name 'independent-component-produces-no-issue' -Passed (@($firstSet.components | Where-Object componentId -like '*independent*' | ForEach-Object { @($_.issues).Count })[0] -eq 0) -Detail 'AI can reject every provisional edge without producing a Rule Issue.'
    $protectedIssue = @($firstSet.components | Where-Object componentId -like '*protected*')[0].issues[0]
    Add-TestResult -Name 'protected-canonical-wording' -Passed ([string]$protectedIssue.wording.status -ceq 'canonical' -and [string]$protectedIssue.wording.text -ceq 'Canonical text.') -Detail 'Protected adjudication preserves exact canonical wording.'

    $parameters.OutputPath = Join-Path $root 'second.json'
    $second = & $runnerPath @parameters | ConvertFrom-Json
    Add-TestResult -Name 'second-run-reuses-components' -Passed ([int]$second.cachedComponentCount -eq 2 -and [int]$second.evaluatedComponentCount -eq 0) -Detail 'Unchanged component source and rule hashes reuse cached adjudication.'

    $changed = New-ComponentInput -Id '001' -ContentSha256 ('b' * 64)
    [IO.File]::WriteAllText($componentPaths[0], (($changed | ConvertTo-Json -Depth 30) + "`n"), [Text.UTF8Encoding]::new($false))
    $parameters.OutputPath = Join-Path $root 'third.json'
    $third = & $runnerPath @parameters | ConvertFrom-Json
    Add-TestResult -Name 'changed-component-reevaluates-only-itself' -Passed ([int]$third.cachedComponentCount -eq 1 -and [int]$third.evaluatedComponentCount -eq 1) -Detail 'A changed direct source hash invalidates only its component adjudication.'

    $invalidReferencePath = Join-Path $root 'invalid-reference.json'
    [IO.File]::WriteAllText($invalidReferencePath, (((New-ComponentInput -Id '003' -ContentSha256 $hash -InvalidReference) | ConvertTo-Json -Depth 30) + "`n"), [Text.UTF8Encoding]::new($false))
    $invalidReferenceParameters = @{
        ComponentPaths = @($invalidReferencePath)
        OutputPath = Join-Path $root 'invalid-reference-result.json'
        CacheDirectory = Join-Path $root 'invalid-reference-cache'
        EvaluatorScriptPath = $fixturePath
        InputSchemaPath = $inputSchemaPath
        DraftSchemaPath = $draftSchemaPath
        PromptPath = $promptPath
        MaxRetries = 0
        OutputFormat = 'Json'
        Quiet = $true
    }
    $invalidReferenceRejected = $false
    try {
        & $runnerPath @invalidReferenceParameters | Out-Null
    }
    catch {
        $invalidReferenceRejected = [string]$_.Exception.Message -match 'non-member rule ID IMPL-FAKE-999'
    }
    Add-TestResult -Name 'non-member-rule-reference-rejected' -Passed $invalidReferenceRejected -Detail 'Visible AI-authored issue prose cannot reference a rule ID outside that issue membership.'

    $exporterText = Get-Content -LiteralPath $exporterPath -Raw
    $authorityBoundary = $exporterText -match 'candidate\.recommendation\.relatedHostedCoverage' -and $exporterText -notmatch 'candidate\.assessment\.relatedHostedCoverage' -and $exporterText -notmatch '\$actionable\s*='
    Add-TestResult -Name 'exporter-uses-reconciliation-authority' -Passed $authorityBoundary -Detail 'The exporter builds provisional edges from reconciliation output and contains no action-based semantic heuristic.'

    $runnerText = Get-Content -LiteralPath $runnerPath -Raw
    $calibratedEstimate = $runnerText -match '\$adjudicationBootstrapBytesPerSecondPerWorker\s*=\s*600' -and $runnerText -match '\[Math\]::Min\(\$MaxParallelBatches, \$pendingBatches\.Count\)'
    Add-TestResult -Name 'estimate-uses-observed-throughput-and-active-workers' -Passed $calibratedEstimate -Detail 'Rule Issue estimates use the observed phase throughput and cap worker count to pending components.'
}
catch {
    Add-TestResult -Name 'unexpected-exception' -Passed $false -Detail $_.Exception.Message
}
finally {
    Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction SilentlyContinue
}

$result = [ordered]@{
    status = if ($issues.Count -eq 0) { 'passed' } else { 'failed' }
    testCount = $results.Count
    issueCount = $issues.Count
    tests = $results.ToArray()
    issues = $issues.ToArray()
}
if ($OutputFormat -eq 'Json') {
    $result | ConvertTo-Json -Depth 10
}
else {
    Write-ValidationSectionHeader -Title 'Rule Issue adjudication test summary'
    Write-ValidationSummary -Fields ([ordered]@{ Status = $result.status.ToUpperInvariant(); Tests = $result.testCount; Passed = @($results | Where-Object status -eq 'passed').Count; Failed = $result.issueCount })
    Write-ValidationTwoColumnTable -Rows $results.ToArray() -FirstHeader 'Status' -FirstProperty 'status' -SecondHeader 'Test' -SecondProperty 'name' -UppercaseFirst
    if ($issues.Count -gt 0) { Write-ValidationIssueList -Issues $issues.ToArray() }
    Complete-ValidationTextOutput
}
if ($issues.Count -gt 0) { exit 1 }
