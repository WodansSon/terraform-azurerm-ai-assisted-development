[CmdletBinding()]
param(
    [ValidateSet('Text', 'Json')]
    [string]$OutputFormat = 'Text'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$modulePath = Join-Path $PSScriptRoot 'ValidationOutput.psm1'
Import-Module -Name $modulePath -Force

$issues = New-Object 'System.Collections.Generic.List[string]'

function Assert-OutputSequence {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name,

        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [object[]]$Actual,

        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [object[]]$Expected
    )

    $actualText = @($Actual | ForEach-Object { [string]$_ }) -join "`n"
    $expectedText = @($Expected | ForEach-Object { [string]$_ }) -join "`n"
    if ($actualText -cne $expectedText) {
        $issues.Add("$Name output does not match the validation presentation contract")
    }
}

$separator = '-' * 51
Assert-OutputSequence -Name 'section header' -Actual @(Write-ValidationSectionHeader -Title 'Validation checks') -Expected @('', $separator, 'VALIDATION CHECKS', $separator, '')

Assert-OutputSequence -Name 'status line' -Actual @(
    Format-ValidationStatusLine -Status 'passed' -Name 'catalog' -Detail '1.25s'
) -Expected @('[PASSED]   catalog                        : 1.25s')

Assert-OutputSequence -Name 'wide status label' -Actual @(
    Format-ValidationStatusLine -Status 'unchanged' -Name 'catalog' -Detail 'current'
) -Expected @('[UNCHANGED] catalog                        : current')

Assert-OutputSequence -Name 'long status line' -Actual @(
    Format-ValidationStatusLine -Status 'passed' -Name 'long-name' -Detail '1.25s' -NameWidth 40
) -Expected @('[PASSED]   long-name                                : 1.25s')

$stageNames = @('validate-artifacts', 'write-provenance-report')
$stageNameWidth = Get-ValidationNameWidth -Names $stageNames
Assert-OutputSequence -Name 'computed name width' -Actual @($stageNameWidth) -Expected @('23')
Assert-OutputSequence -Name 'nested status alignment' -Actual @(
    Format-ValidationStatusLine -Status 'running' -Name $stageNames[0] -Detail 'IN PROGRESS' -NameWidth $stageNameWidth -IndentLevel 2
    Format-ValidationStatusLine -Status 'passed' -Name $stageNames[1] -Detail '1.25s' -NameWidth $stageNameWidth -IndentLevel 2
) -Expected @(
    '    [RUNNING]  validate-artifacts      : IN PROGRESS',
    '    [PASSED]   write-provenance-report : 1.25s'
)

Assert-OutputSequence -Name 'relayed child line' -Actual @(
    Add-ValidationIndent -Line '  [PASSED]   validate-artifacts             : 4.17s'
) -Expected @('    [PASSED]   validate-artifacts             : 4.17s')

Assert-OutputSequence -Name 'leaf duration' -Actual @(
    Format-ValidationDuration -DurationSeconds 1.25
) -Expected @('1.25s')

Assert-OutputSequence -Name 'summary' -Actual @(
    Write-ValidationSummary -Fields ([ordered]@{ Status = 'PASSED'; 'Issue Count' = 0 })
) -Expected @(
    '  Status      : PASSED',
    '  Issue Count : 0'
)

$statusRows = @(
    [pscustomobject]@{ name = 'catalog'; status = 'passed'; durationSeconds = 1.25; detail = 'catalog is current' },
    [pscustomobject]@{ name = 'markdown'; status = 'skipped'; durationSeconds = 0; detail = 'not applicable' }
)
Assert-OutputSequence -Name 'status table' -Actual @(
    Write-ValidationStatusTable -Rows $statusRows -IncludeDetail
) -Expected @(
    '  CHECK                            STATUS       DURATION',
    '  -------------------------------- ---------- ----------',
    '  catalog                          PASSED          1.25s',
    '    catalog is current',
    '  markdown                         SKIPPED            0s',
    '    not applicable'
)

Assert-OutputSequence -Name 'execution status table' -Actual @(
    Write-ValidationStatusTable -Rows @($statusRows[0]) -NameHeader 'validator' -NameWidth 24
) -Expected @(
    '  VALIDATOR                STATUS       DURATION',
    '  ------------------------ ---------- ----------',
    '  catalog                  PASSED          1.25s'
)

$twoColumnRows = @(
    [pscustomobject]@{ ownership = 'hosted'; path = 'hosted_copilot/CHANGELOG.md' }
)
Assert-OutputSequence -Name 'two-column table' -Actual @(
    Write-ValidationTwoColumnTable -Rows $twoColumnRows -FirstHeader 'ownership' -FirstProperty 'ownership' -SecondHeader 'path' -SecondProperty 'path' -UppercaseFirst
) -Expected @(
    '  OWNERSHIP                PATH',
    '  ------------------------ ------------------------',
    '  HOSTED                   hosted_copilot/CHANGELOG.md'
)

Assert-OutputSequence -Name 'text output ending' -Actual @(Complete-ValidationTextOutput) -Expected @('')

$presentationConsumers = @(
    'check-upstream-contributor-drift.ps1',
    'Test-ChangedToolkitRouting.ps1',
    'Test-InteractiveRuleCatalog.ps1',
    'Test-PRReady.ps1',
    'Test-ValidationOutput.ps1',
    'Validate-ChangedToolkits.ps1',
    'validate-ai-toolkit.ps1',
    'validate-architecture-layout.ps1',
    'validate-changelog-consistency.ps1',
    'validate-changelog-taxonomy.ps1',
    'validate-contracts.ps1',
    'validate-copied-markdown-links.ps1',
    'validate-runtime-line-endings.ps1',
    'regression/run-regression-harness.ps1',
    'regression/run-regression-suite.ps1',
    'regression/score-regression-case.ps1',
    'regression/summarize-regression-history.ps1',
    'regression/validate-regression-artifacts.ps1',
    'regression/write-regression-history-snapshot.ps1',
    'regression/write-regression-provenance-report.ps1',
    '../hosted_copilot/tools/Test-InstructionGeneration.ps1',
    '../hosted_copilot/tools/Test-ReviewResults.ps1',
    '../hosted_copilot/tools/Test-Toolkit.ps1',
    '../hosted_copilot/tools/Test-UpstreamSources.ps1'
)
foreach ($relativePath in $presentationConsumers) {
    $consumerPath = Join-Path $PSScriptRoot $relativePath
    $consumerContent = Get-Content -LiteralPath $consumerPath -Raw
    if ($consumerContent -notmatch 'ValidationOutput\.psm1' -or $consumerContent -notmatch 'Write-ValidationSectionHeader') {
        $issues.Add("$relativePath does not consume the shared validation presentation contract")
    }
    if ($consumerContent -notmatch 'Complete-ValidationTextOutput') {
        $issues.Add("$relativePath does not use the shared validation output terminator")
    }
    if ($consumerContent -match '(?m)^function\s+(Write-TextSectionHeader|Format-HarnessStatusLine|Format-DriftStatusLine)\s*\{') {
        $issues.Add("$relativePath defines a private validation presentation formatter")
    }
}

foreach ($relativePath in @('Validate-ChangedToolkits.ps1', 'validate-ai-toolkit.ps1')) {
    $consumerContent = Get-Content -LiteralPath (Join-Path $PSScriptRoot $relativePath) -Raw
    if ($consumerContent -notmatch '\^\\s\*\\\[\(RUNNING\|PASSED\|FAILED\|SKIPPED\)\\\]' -or $consumerContent -notmatch 'Add-ValidationIndent -Line') {
        $issues.Add("$relativePath does not preserve nested child status indentation")
    }
}

$result = [ordered]@{
    status = if ($issues.Count -eq 0) { 'passed' } else { 'failed' }
    issueCount = $issues.Count
    issues = @($issues.ToArray())
}

if ($OutputFormat -eq 'Json') {
    $result | ConvertTo-Json -Depth 4
}
else {
    Write-ValidationSectionHeader -Title 'Validation output contract test summary'
    Write-ValidationSummary -Fields ([ordered]@{
        Status = $result.status.ToUpperInvariant()
        'Issue Count' = $result.issueCount
    })
    if ($issues.Count -gt 0) {
        Write-ValidationSectionHeader -Title 'Issues'
        foreach ($issue in $issues) {
            Write-Output "  - $issue"
        }
    }
    Complete-ValidationTextOutput
}

if ($issues.Count -gt 0) {
    exit 1
}
