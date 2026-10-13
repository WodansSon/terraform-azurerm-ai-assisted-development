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

if ($OutputFormat -eq 'Text') {
    Write-ValidationSectionHeader -Title 'Hosted Rule Issue adjudication'
}

function Add-TestResult {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][bool]$Passed,
        [Parameter(Mandatory = $true)][string]$Detail
    )

    $results.Add([pscustomobject]@{ name = $Name; status = if ($Passed) { 'passed' } else { 'failed' }; detail = $Detail })
    if (-not $Passed) { $issues.Add("$Name`: $Detail") }
}

function Write-TestProgress {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][string]$Detail
    )

    if ($OutputFormat -eq 'Text') {
        Write-Host (Format-ValidationStatusLine -Status 'running' -Name $Name -Detail $Detail -NameWidth 42)
    }
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
    Write-TestProgress -Name 'first-run-evaluates-components' -Detail 'Evaluating every uncached Rule Issue component'
    $first = & $runnerPath @parameters | ConvertFrom-Json
    $firstSet = Get-Content -LiteralPath $parameters.OutputPath -Raw | ConvertFrom-Json -Depth 100
    Add-TestResult -Name 'first-run-evaluates-components' -Passed ([int]$first.evaluatedComponentCount -eq 2 -and [int]$first.cachedComponentCount -eq 0) -Detail 'The first run evaluates every uncached component.'
    Write-TestProgress -Name 'hierarchical-adjudication-cache' -Detail 'Checking v2 adjudication shards and legacy cache exclusion'
    $hierarchicalCachePath = Join-Path $parameters.CacheDirectory 'hierarchical-reconciliation-cache.json'
    $hierarchicalCache = Get-Content -LiteralPath $hierarchicalCachePath -Raw | ConvertFrom-Json -DateKind String
    $hierarchicalCacheValid = [int]$hierarchicalCache.schemaVersion -eq 2 -and
        [string]$hierarchicalCache.kind -ceq 'hosted-hierarchical-reconciliation-cache' -and
        @($hierarchicalCache.entries).Count -eq 2 -and
        @($hierarchicalCache.entries | Where-Object { [string]$_.stage -cne 'adjudication' -or [string]$_.shardKey -cnotmatch '^adjudication:[0-9a-f]{64}$' }).Count -eq 0 -and
        -not (Test-Path -LiteralPath (Join-Path $parameters.CacheDirectory 'rule-issue-adjudication-cache.json') -PathType Leaf)
    Add-TestResult -Name 'hierarchical-adjudication-cache' -Passed $hierarchicalCacheValid -Detail 'Rule Issue components use only v2 adjudication shards and never create the legacy component ledger.'
    Write-TestProgress -Name 'independent-component-produces-no-issue' -Detail 'Checking rejection of a provisional relationship'
    Add-TestResult -Name 'independent-component-produces-no-issue' -Passed (@($firstSet.components | Where-Object componentId -like '*independent*' | ForEach-Object { @($_.issues).Count })[0] -eq 0) -Detail 'AI can reject every provisional edge without producing a Rule Issue.'
    Write-TestProgress -Name 'protected-canonical-wording' -Detail 'Checking immutable protected wording'
    $protectedIssue = @($firstSet.components | Where-Object componentId -like '*protected*')[0].issues[0]
    Add-TestResult -Name 'protected-canonical-wording' -Passed ([string]$protectedIssue.wording.status -ceq 'canonical' -and [string]$protectedIssue.wording.text -ceq 'Canonical text.') -Detail 'Protected adjudication preserves exact canonical wording.'

    Write-TestProgress -Name 'second-run-reuses-components' -Detail 'Reusing unchanged adjudication shards'
    $parameters.OutputPath = Join-Path $root 'second.json'
    $second = & $runnerPath @parameters | ConvertFrom-Json
    Add-TestResult -Name 'second-run-reuses-components' -Passed ([int]$second.cachedComponentCount -eq 2 -and [int]$second.evaluatedComponentCount -eq 0) -Detail 'Unchanged component source and rule hashes reuse cached adjudication.'

    Write-TestProgress -Name 'changed-component-reevaluates-only-itself' -Detail 'Invalidating only the changed component shard'
    $changed = New-ComponentInput -Id '001' -ContentSha256 ('b' * 64)
    [IO.File]::WriteAllText($componentPaths[0], (($changed | ConvertTo-Json -Depth 30) + "`n"), [Text.UTF8Encoding]::new($false))
    $parameters.OutputPath = Join-Path $root 'third.json'
    $third = & $runnerPath @parameters | ConvertFrom-Json
    Add-TestResult -Name 'changed-component-reevaluates-only-itself' -Passed ([int]$third.cachedComponentCount -eq 1 -and [int]$third.evaluatedComponentCount -eq 1) -Detail 'A changed direct source hash invalidates only its component adjudication.'

    Write-TestProgress -Name 'behavior-change-invalidates-cache' -Detail 'Binding cache authority to every declared behavior file'
    $authorityRepositoryRoot = Join-Path $root 'authority-repository'
    $null = New-Item -ItemType Directory -Path $authorityRepositoryRoot -Force
    $authorityBehaviorPath = Join-Path $authorityRepositoryRoot 'behavior.ps1'
    $authorityPresentationPath = Join-Path $authorityRepositoryRoot 'presentation.psm1'
    [IO.File]::WriteAllText($authorityBehaviorPath, "'first'`n", [Text.UTF8Encoding]::new($false))
    [IO.File]::WriteAllText($authorityPresentationPath, "'first presentation'`n", [Text.UTF8Encoding]::new($false))
    $authorityContractPath = Join-Path $root 'rule-issue-adjudication-v4.json'
    $authorityContract = [ordered]@{ '$schema' = 'rule-issue-adjudication-contract.schema.json'; schemaVersion = 1; contractId = 'rule-issue-adjudication-v4'; behaviorFiles = @('behavior.ps1'); presentationFiles = @('presentation.psm1') }
    [IO.File]::WriteAllText($authorityContractPath, (($authorityContract | ConvertTo-Json -Depth 10) + "`n"), [Text.UTF8Encoding]::new($false))
    $authorityParameters = @{} + $parameters
    $authorityParameters.RepositoryRoot = $authorityRepositoryRoot
    $authorityParameters.AdjudicationContractPath = $authorityContractPath
    $authorityParameters.ContractSchemaPath = Join-Path $repositoryRoot 'hosted_copilot/copilot-rule-catalog/assessment-reconciliation/rule-issue-adjudication-contract.schema.json'
    $authorityParameters.CacheDirectory = Join-Path $root 'authority-cache'
    $authorityParameters.OutputPath = Join-Path $root 'authority-first.json'
    $authorityFirst = & $runnerPath @authorityParameters | ConvertFrom-Json
    $authorityParameters.OutputPath = Join-Path $root 'authority-second.json'
    $authoritySecond = & $runnerPath @authorityParameters | ConvertFrom-Json
    [IO.File]::WriteAllText($authorityPresentationPath, "'second presentation'`n", [Text.UTF8Encoding]::new($false))
    $authorityParameters.OutputPath = Join-Path $root 'authority-presentation.json'
    $authorityPresentation = & $runnerPath @authorityParameters | ConvertFrom-Json
    [IO.File]::WriteAllText($authorityBehaviorPath, "'second'`n", [Text.UTF8Encoding]::new($false))
    $authorityParameters.OutputPath = Join-Path $root 'authority-behavior.json'
    $authorityBehavior = & $runnerPath @authorityParameters | ConvertFrom-Json
    $behaviorAuthorityValid = [int]$authorityFirst.evaluatedComponentCount -eq 2 -and
        [int]$authoritySecond.cachedComponentCount -eq 2 -and
        [int]$authorityPresentation.cachedComponentCount -eq 2 -and
        [int]$authorityPresentation.evaluatedComponentCount -eq 0 -and
        [int]$authorityBehavior.cachedComponentCount -eq 0 -and
        [int]$authorityBehavior.evaluatedComponentCount -eq 2
    Add-TestResult -Name 'behavior-change-invalidates-cache' -Passed $behaviorAuthorityValid -Detail 'Presentation-only changes preserve adjudication cache reuse while declared semantic behavior changes invalidate every shard.'

    Write-TestProgress -Name 'non-member-rule-reference-rejected' -Detail 'Rejecting visible references to non-member rule IDs'
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

    Write-TestProgress -Name 'exporter-uses-reconciliation-authority' -Detail 'Checking provisional relationship ownership'
    $exporterText = Get-Content -LiteralPath $exporterPath -Raw
    $authorityBoundary = $exporterText -match 'candidate\.recommendation\.relatedHostedCoverage' -and $exporterText -match 'Candidate\.members' -and $exporterText -notmatch 'candidate\.assessment\.relatedHostedCoverage' -and $exporterText -notmatch '\$actionable\s*='
    Add-TestResult -Name 'exporter-uses-reconciliation-authority' -Passed $authorityBoundary -Detail 'The exporter builds provisional edges from reconciliation output and contains no action-based semantic heuristic.'

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
    Write-ValidationSectionHeader -Title 'Hosted Rule Issue adjudication test summary'
    Write-ValidationSummary -Fields ([ordered]@{ Status = $result.status.ToUpperInvariant(); Tests = $result.testCount; Issues = $result.issueCount })
    Write-ValidationSectionHeader -Title 'Rule Issue adjudication tests'
    Write-ValidationTwoColumnTable -Rows @($results | ForEach-Object { [pscustomobject]@{ Status = $_.status; Test = $_.name } }) -FirstHeader 'Status' -FirstProperty 'Status' -SecondHeader 'Test' -SecondProperty 'Test' -UppercaseFirst
    if ($issues.Count -gt 0) {
        Write-ValidationSectionHeader -Title 'Failures'
        foreach ($issue in $issues) {
            Write-Output "  - $issue"
        }
    }
    Complete-ValidationTextOutput
}
if ($issues.Count -gt 0) { exit 1 }
