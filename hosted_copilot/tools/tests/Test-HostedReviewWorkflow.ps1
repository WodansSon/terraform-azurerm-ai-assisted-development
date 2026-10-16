[CmdletBinding()]
param(
    [ValidateSet('Text', 'Json')]
    [string]$OutputFormat = 'Text'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$hostedRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
$workflowModulePath = Join-Path $hostedRoot 'tools/modules/review/HostedReview.Workflow.psm1'
$resultValidatorPath = Join-Path $hostedRoot 'tools/tests/Test-ReviewResults.ps1'
$caseDirectory = Join-Path $hostedRoot 'regression/cases'
$schemaPath = Join-Path $hostedRoot 'regression/schema/paired-review-result.schema.json'
$tempRoot = Join-Path ([IO.Path]::GetTempPath()) ("hosted-review-workflow-$([guid]::NewGuid().ToString('N'))")
$resultsDirectory = Join-Path $tempRoot 'results'
$validationOutputModulePath = Join-Path $hostedRoot '../tools/ValidationOutput.psm1'

Import-Module $workflowModulePath -Force
Import-Module $validationOutputModulePath -Force
$passed = $false
$failure = $null
if ($OutputFormat -eq 'Text') {
    Write-ValidationSectionHeader -Title 'Hosted review workflow'
    Write-Host (Format-ValidationStatusLine -Status 'running' -Name 'offline-result' -Detail 'Building and validating one controlled paired-review result')
}
New-Item -ItemType Directory -Path $resultsDirectory -Force | Out-Null
try {
    $case = Get-Content -LiteralPath (Join-Path $caseDirectory 'documentation/example-validation-v2/case.json') -Raw | ConvertFrom-Json
    $capture = [pscustomobject]@{
        runId = 'offline-01'
        repository = 'example/terraform-provider-azurerm'
        fixtureId = [string]$case.id
        capturedAt = '2026-09-19T00:00:00.0000000Z'
        sourceCommit = '1111111111111111111111111111111111111111'
        manifestHash = '2222222222222222222222222222222222222222222222222222222222222222'
        diffHashAlgorithm = 'sha256-github-file-patches-v1'
        diffHash = '3333333333333333333333333333333333333333333333333333333333333333'
        changedFiles = @('website/docs/r/hosted_fixture_format_validation.html.markdown')
        profiles = @(
            [pscustomobject]@{
                slot = 'A'
                evidence = [pscustomobject]@{
                    instructionProfile = 'control'
                    pullRequest = [pscustomobject]@{ number = 1; url = 'https://github.com/example/terraform-provider-azurerm/pull/1'; baseBranch = 'control-base'; baseCommit = '4444444444444444444444444444444444444444'; headBranch = 'control-review/source-pr-1/offline-01'; headCommit = '5555555555555555555555555555555555555555' }
                    review = [pscustomobject]@{ id = 10; reviewEffort = 'Lite'; requestedAt = '2026-09-19T00:01:00.0000000Z'; reviewedAt = '2026-09-19T00:02:00.0000000Z' }
                    runtime = $null
                    diffHash = '3333333333333333333333333333333333333333333333333333333333333333'
                    comments = @([pscustomobject]@{ id = 100; url = 'https://github.com/example/terraform-provider-azurerm/pull/1#discussion_r100'; path = 'website/docs/r/hosted_fixture_format_validation.html.markdown'; line = 10; body = 'Combined valid finding.' })
                }
            },
            [pscustomobject]@{
                slot = 'B'
                evidence = [pscustomobject]@{
                    instructionProfile = 'hosted'
                    pullRequest = [pscustomobject]@{ number = 2; url = 'https://github.com/example/terraform-provider-azurerm/pull/2'; baseBranch = 'hosted-base'; baseCommit = '6666666666666666666666666666666666666666'; headBranch = 'hosted-review/source-pr-1/offline-01'; headCommit = '7777777777777777777777777777777777777777' }
                    review = [pscustomobject]@{ id = 20; reviewEffort = 'Lite'; requestedAt = '2026-09-19T00:01:00.0000000Z'; reviewedAt = '2026-09-19T00:02:00.0000000Z' }
                    runtime = $null
                    diffHash = '3333333333333333333333333333333333333333333333333333333333333333'
                    comments = @([pscustomobject]@{ id = 200; url = 'https://github.com/example/terraform-provider-azurerm/pull/2#discussion_r200'; path = 'website/docs/r/hosted_fixture_format_validation.html.markdown'; line = 10; body = 'Combined expected finding.' })
                }
            }
        )
    }
    $adjudications = @{
        A = @{ '100' = [pscustomobject]@{ classification = 'unexpected-valid'; ruleIds = @(); duplicateOf = $null; reason = 'Valid additional issue.' } }
        B = @{ '200' = [pscustomobject]@{ classification = 'expected'; ruleIds = @('DOCS-WORD-005', 'DOCS-FMT-005'); duplicateOf = $null; reason = 'One comment covers both formatting rules.' } }
    }

    $result = New-HostedReviewResult -Capture $capture -Case $case -Adjudications $adjudications -RawCapturePath 'raw/documentation-example-validation-v2/offline-01.json' -CompletedAt '2026-09-19T00:03:00.0000000Z'
    $resultPath = Join-Path $resultsDirectory 'documentation-example-validation-v2/offline-01.json'
    New-Item -ItemType Directory -Path (Split-Path -Parent $resultPath) -Force | Out-Null
    $result | ConvertTo-Json -Depth 30 | Set-Content -LiteralPath $resultPath -Encoding utf8NoBOM

    $pwsh = Get-Command pwsh -ErrorAction Stop
    $validationOutput = @(& $pwsh.Source -NoProfile -File $resultValidatorPath -ResultsDirectory $resultsDirectory -CasesDirectory $caseDirectory -SchemaPath $schemaPath -OutputFormat Json 2>&1)
    if ($LASTEXITCODE -ne 0) {
        throw "Generated result validation failed: $((($validationOutput | Out-String).Trim()))"
    }
    $validation = ($validationOutput -join [Environment]::NewLine) | ConvertFrom-Json
    if ($validation.status -ne 'passed' -or $validation.resultCount -ne 1) {
        throw 'Generated result did not pass focused validation'
    }
    if (@($result.profiles | Where-Object instructionProfile -eq 'hosted')[0].missedFindings -contains 'DOCS-FMT-005') {
        throw 'Combined expected finding was incorrectly recorded as missed'
    }

    $passed = $true
}
catch {
    $failure = $_.Exception.Message
}
finally {
    Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
}

$resultSummary = [ordered]@{
    status = if ($passed) { 'passed' } else { 'failed' }
    testCount = 1
    passedCount = if ($passed) { 1 } else { 0 }
    failedCount = if ($passed) { 0 } else { 1 }
    tests = @([ordered]@{ name = 'offline-result'; status = if ($passed) { 'passed' } else { 'failed' } })
    issues = @($(if ($null -eq $failure) { @() } else { @($failure) }))
}
if ($OutputFormat -eq 'Json') {
    $resultSummary | ConvertTo-Json -Depth 5
}
else {
    Write-ValidationSectionHeader -Title 'Hosted review workflow test summary'
    Write-ValidationSummary -Fields ([ordered]@{
        Status = $resultSummary.status.ToUpperInvariant()
        Tests = $resultSummary.testCount
        Passed = $resultSummary.passedCount
        Failed = $resultSummary.failedCount
    })
    Write-ValidationSectionHeader -Title 'Hosted review workflow tests'
    Write-ValidationTwoColumnTable -Rows $resultSummary.tests -FirstHeader 'Status' -FirstProperty 'status' -SecondHeader 'Test' -SecondProperty 'name' -UppercaseFirst
    if (-not $passed) {
        Write-ValidationSectionHeader -Title 'Failures'
        Write-Output "  - $failure"
    }
    Complete-ValidationTextOutput
}
if (-not $passed) {
    exit 1
}
