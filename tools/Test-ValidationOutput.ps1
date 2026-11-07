[CmdletBinding()]
param(
    [ValidateSet('Text', 'Json')]
    [string]$OutputFormat = 'Text',

    [ValidateSet('All', 'Interactive', 'Hosted')]
    [string]$ProductScope = 'All'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$modulePath = Join-Path $PSScriptRoot 'ValidationOutput.psm1'
Import-Module -Name $modulePath -Force

$issues = New-Object 'System.Collections.Generic.List[string]'
$results = New-Object 'System.Collections.Generic.List[object]'
$suiteStopwatch = [Diagnostics.Stopwatch]::StartNew()
$checkStopwatch = [Diagnostics.Stopwatch]::StartNew()

if ($OutputFormat -eq 'Text') {
    Write-ValidationSectionHeader -Title 'Validation output contracts'
    Write-Host (Format-ValidationLifecycleLine -Status 'running' -Name 'output-contracts')
}

function Add-OutputTestResult {
    param([string]$Name, [bool]$Passed)

    $checkStopwatch.Stop()
    $status = if ($Passed) { 'passed' } else { 'failed' }
    $results.Add([pscustomobject]@{
        name = $Name
        status = $status
        durationSeconds = $checkStopwatch.Elapsed.TotalSeconds
    })
    $checkStopwatch.Restart()
}

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
    $passed = $actualText -ceq $expectedText
    if (-not $passed) {
        $issues.Add("$Name output does not match the validation presentation contract")
    }
    Add-OutputTestResult -Name $Name -Passed $passed
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
Assert-OutputSequence -Name 'passing lifecycle' -Actual @(
    Format-ValidationLifecycleLine -Status running -Name 'check-1' -Description 'Verify the complete source description' -NameWidth 12
    Format-ValidationLifecycleLine -Status passed -Name 'check-1' -DurationSeconds 1.25 -NameWidth 12
) -Expected @(
    '[RUNNING]  check-1      : Verify the complete source description',
    '[PASSED]   check-1      : 1.25s'
)
Assert-OutputSequence -Name 'failed lifecycle' -Actual @(
    Format-ValidationLifecycleLine -Status running -Name 'check-2' -Description 'Verify rollback' -AlignmentWidth 14 -Child
    Format-ValidationLifecycleLine -Status failed -Name 'check-2' -DurationSeconds 0.5 -AlignmentWidth 14 -Child
) -Expected @(
    '  [RUNNING]  check-2      : Verify rollback',
    '  [FAILED]   check-2      : 0.5s'
)
Assert-OutputSequence -Name 'skipped lifecycle' -Actual @(
    Format-ValidationLifecycleLine -Status skipped -Name 'check-3' -Description 'Not applicable on this platform' -AlignmentWidth 14 -Child
) -Expected @('  [SKIPPED]  check-3      : Not applicable on this platform')
Assert-OutputSequence -Name 'parent and child lifecycle' -Actual @(
    Format-ValidationLifecycleLine -Status running -Name 'parent' -Description 'Build fixtures' -AlignmentWidth 20
    Format-ValidationLifecycleLine -Status running -Name 'child' -Description 'Verify fixture' -AlignmentWidth 20 -Child -Level 1
    Format-ValidationLifecycleLine -Status passed -Name 'child' -DurationSeconds 0.25 -AlignmentWidth 20 -Child -Level 1
    Format-ValidationLifecycleLine -Status passed -Name 'parent' -DurationSeconds 1.25 -AlignmentWidth 20
) -Expected @(
    ('[RUNNING]  {0,-20} : Build fixtures' -f 'parent'),
    ('  [RUNNING]  {0,-18} : Verify fixture' -f 'child'),
    ('  [PASSED]   {0,-18} : 0.25s' -f 'child'),
    ('[PASSED]   {0,-20} : 1.25s' -f 'parent')
)
Assert-OutputSequence -Name 'nested failure and skip alignment' -Actual @(
    Format-ValidationLifecycleLine -Status failed -Name 'grandchild' -DurationSeconds 0.5 -AlignmentWidth 24 -Child -Level 2
    Format-ValidationLifecycleLine -Status skipped -Name 'optional-child' -Description 'Not applicable' -AlignmentWidth 24 -Child -Level 1
) -Expected @(
    ('    [FAILED]   {0,-20} : 0.5s' -f 'grandchild'),
    ('  [SKIPPED]  {0,-22} : Not applicable' -f 'optional-child')
)
Assert-OutputSequence -Name 'three child levels' -Actual @(
    Format-ValidationLifecycleLine -Status passed -Name 'root' -DurationSeconds 1 -AlignmentWidth 24
    Format-ValidationLifecycleLine -Status passed -Name 'child' -DurationSeconds 0.75 -AlignmentWidth 24 -Child
    Format-ValidationLifecycleLine -Status passed -Name 'grandchild' -DurationSeconds 0.5 -AlignmentWidth 24 -Child -Level 2
    Format-ValidationLifecycleLine -Status passed -Name 'great-grandchild' -DurationSeconds 0.25 -AlignmentWidth 24 -Child -Level 3
) -Expected @(
    ('[PASSED]   {0,-24} : 1s' -f 'root'),
    ('  [PASSED]   {0,-22} : 0.75s' -f 'child'),
    ('    [PASSED]   {0,-20} : 0.5s' -f 'grandchild'),
    ('      [PASSED]   {0,-18} : 0.25s' -f 'great-grandchild')
)
Assert-OutputSequence -Name 'default child alignment' -Actual @(
    Format-ValidationLifecycleLine -Status passed -Name 'root' -DurationSeconds 1
    Format-ValidationLifecycleLine -Status passed -Name 'child' -DurationSeconds 0.5 -Child
) -Expected @(
    ('[PASSED]   {0,-30} : 1s' -f 'root'),
    ('  [PASSED]   {0,-28} : 0.5s' -f 'child')
)
Assert-OutputSequence -Name 'explicit completion evidence' -Actual @(
    Format-ValidationLifecycleLine -Status passed -Name 'packages' -DurationSeconds 0.25 -ResultDetail 'CURRENT (MATCHES AUDITED LOCKFILE)' -NameWidth 12
) -Expected @('[PASSED]   packages     : 0.25s - CURRENT (MATCHES AUDITED LOCKFILE)')
foreach ($invalidLifecycle in @(
    @{ Status = 'passed'; Name = 'missing-duration' },
    @{ Status = 'failed'; Name = 'invalid-duration'; DurationSeconds = -1 },
    @{ Status = 'passed'; Name = 'nonfinite-duration'; DurationSeconds = [double]::NaN },
    @{ Status = 'skipped'; Name = 'skipped-duration'; DurationSeconds = 1 },
    @{ Status = 'running'; Name = 'insufficient-width'; AlignmentWidth = 10; Child = $true },
    @{ Status = 'running'; Name = 'level-without-child'; Level = 1 },
    @{ Status = 'running'; Name = 'zero-child-level'; Child = $true; Level = 0 },
    @{ Status = 'running'; Name = 'negative-child-level'; Child = $true; Level = -1 },
    @{ Status = 'running'; Name = 'excessive-child-level'; Child = $true; Level = 11 }
)) {
    $rejected = $false
    try { Format-ValidationLifecycleLine @invalidLifecycle | Out-Null } catch { $rejected = $true }
    if (-not $rejected) { $issues.Add("$($invalidLifecycle.Name) was accepted by the lifecycle formatter") }
    Add-OutputTestResult -Name "lifecycle rejection/$($invalidLifecycle.Name)" -Passed $rejected
}
$stageNameWidth = Get-ValidationNameWidth -Names $stageNames
Assert-OutputSequence -Name 'computed name width' -Actual @($stageNameWidth) -Expected @('23')
Assert-OutputSequence -Name 'nested status alignment' -Actual @(
    Format-ValidationStatusLine -Status 'running' -Name $stageNames[0] -Detail 'IN PROGRESS' -AlignmentWidth ($stageNameWidth + 4) -Child -Level 2
    Format-ValidationStatusLine -Status 'passed' -Name $stageNames[1] -Detail '1.25s' -AlignmentWidth ($stageNameWidth + 4) -Child -Level 2
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

Assert-OutputSequence -Name 'duration precision' -Actual @(
    Format-ValidationDuration -DurationSeconds 13.9885322
    Format-ValidationDuration -DurationSeconds 21.3602894
    Format-ValidationDuration -DurationSeconds 20.8940928
    Format-ValidationDuration -DurationSeconds 0.0049
    Format-ValidationDuration -DurationSeconds 0.0051
    Format-ValidationDuration -DurationSeconds 1.999
    Format-ValidationDuration -DurationSeconds 0
) -Expected @('13.99s', '21.36s', '20.89s', '0s', '0.01s', '2s', '0s')

Assert-OutputSequence -Name 'child duration precision' -Actual @(
    Format-ValidationStatusLine -Status 'passed' -Name 'server/internal' -Detail (Format-ValidationDuration -DurationSeconds 13.9885322) -AlignmentWidth 32 -Child
) -Expected @('  [PASSED]   server/internal                : 13.99s')

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

Assert-OutputSequence -Name 'long status table names' -Actual @(
    Write-ValidationStatusTable -Rows @(
        [pscustomobject]@{ name = 'assistance-startup-module-refresh'; status = 'passed'; durationSeconds = 2.38 },
        [pscustomobject]@{ name = 'assistance-error-details'; status = 'passed'; durationSeconds = 0.02 }
    ) -NameHeader 'Test'
) -Expected @(
    '  TEST                              STATUS       DURATION',
    '  --------------------------------- ---------- ----------',
    '  assistance-startup-module-refresh PASSED          2.38s',
    '  assistance-error-details          PASSED          0.02s'
)

Assert-OutputSequence -Name 'long status table header' -Actual @(
    Write-ValidationStatusTable -Rows @($statusRows[0]) -NameHeader 'Verification' -NameWidth 4
) -Expected @(
    '  VERIFICATION STATUS       DURATION',
    '  ------------ ---------- ----------',
    '  catalog      PASSED          1.25s'
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
    'Test-ChangedToolkitRouting.ps1',
    'Test-ValidationOutput.ps1',
    'npm-validation/Test-NpmSecurity.ps1',
    'Validate-ChangedToolkits.ps1'
)
if ($ProductScope -in @('All', 'Interactive')) {
    $presentationConsumers += @(
        'check-upstream-contributor-drift.ps1',
        'Test-InteractiveRuleCatalog.ps1',
        'Test-PRReady.ps1',
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
        'regression/write-regression-provenance-report.ps1'
    )
}
if ($ProductScope -in @('All', 'Hosted')) {
    $presentationConsumers += @(
        '../hosted_copilot/tools/tests/Test-InstructionGeneration.ps1',
        '../hosted_copilot/tools/tests/Test-ReviewResults.ps1',
        '../hosted_copilot/tools/tests/Test-RuleAssistance.ps1',
        '../hosted_copilot/tools/tests/Test-RuleWorkbench.ps1',
        '../hosted_copilot/tools/Test-HostedRules.ps1',
        '../hosted_copilot/tools/commands/catalog/Test-UpstreamSources.ps1'
    )
}
foreach ($relativePath in $presentationConsumers) {
    $checkStopwatch.Restart()
    $priorIssueCount = $issues.Count
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
    Add-OutputTestResult -Name "consumer/$([IO.Path]::GetFileName($relativePath))" -Passed ($issues.Count -eq $priorIssueCount)
}

if ($ProductScope -in @('All', 'Hosted')) {
    foreach ($relativePath in @(
        'Test-ValidationOutput.ps1',
        '../hosted_copilot/tools/Test-HostedRules.ps1',
        '../hosted_copilot/tools/tests/Test-RuleWorkbench.ps1',
        '../hosted_copilot/tools/tests/Test-RuleAssistance.ps1'
    )) {
        $checkStopwatch.Restart()
        $priorIssueCount = $issues.Count
        $consumerPath = Join-Path $PSScriptRoot $relativePath
        if (-not (Test-Path -LiteralPath $consumerPath -PathType Leaf)) {
            $issues.Add("$relativePath is a required duration-format consumer but is missing")
            Add-OutputTestResult -Name "duration owner/$([IO.Path]::GetFileName($relativePath))" -Passed $false
            continue
        }
        $tokens = $null
        $parseErrors = $null
        $consumerAst = [Management.Automation.Language.Parser]::ParseFile($consumerPath, [ref]$tokens, [ref]$parseErrors)
        $localDurationFormatting = @($consumerAst.FindAll({
            param($node)
            if ($node -is [Management.Automation.Language.InvokeMemberExpressionAst] -and $node.Member.Value -eq 'Round') {
                return @($node.Arguments | Where-Object { $_.Extent.Text -match 'TotalSeconds|durationSeconds' }).Count -gt 0
            }
            return $node -is [Management.Automation.Language.BinaryExpressionAst] -and
                $node.Operator -eq [Management.Automation.Language.TokenKind]::Format -and
                $node.Left -is [Management.Automation.Language.StringConstantExpressionAst] -and
                $node.Left.Value -match '^\{0(?::[^}]*)?\}s$' -and $node.Right.Extent.Text -match 'durationSeconds'
        }, $true))
        if ($parseErrors.Count) {
            $issues.Add("$relativePath must parse before its duration-format contract can be checked")
        }
        elseif ($localDurationFormatting.Count) {
            $issues.Add("$relativePath must delegate elapsed-time display precision to Format-ValidationDuration")
        }
        Add-OutputTestResult -Name "duration owner/$([IO.Path]::GetFileName($relativePath))" -Passed ($issues.Count -eq $priorIssueCount)
    }

    $checkStopwatch.Restart()
    $preparationOutput = & {
        $path = Join-Path $PSScriptRoot '../hosted_copilot/tools/tests/Test-RuleWorkbench.ps1'
        $ast = [Management.Automation.Language.Parser]::ParseFile($path, [ref]$null, [ref]$null)
        $helper = $ast.Find({ param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq 'Write-PreparationStatus' }, $true)
        . ([scriptblock]::Create($helper.Extent.Text))
        $OutputFormat = 'Text'
        $script:statusNameWidth = 40
        $testStartTimes = @{}
        $lines = @(& {
            Write-PreparationStatus -Status running -Name 'fixtures' -Detail 'Prepare fixtures'
            Write-PreparationStatus -Status running -Name 'source' -Detail 'Prepare source' -Parent 'fixtures'
            Write-PreparationStatus -Status running -Name 'records' -Detail 'Validate records' -Parent 'source' -Level 2
            Write-PreparationStatus -Status running -Name 'fields' -Detail 'Validate fields' -Parent 'records' -Level 3
            Write-PreparationStatus -Status passed -Name 'fields' -Parent 'records' -Level 3
            Write-PreparationStatus -Status passed -Name 'records' -Parent 'source' -Level 2
            Write-PreparationStatus -Status passed -Name 'source' -Parent 'fixtures'
            Write-PreparationStatus -Status passed -Name 'fixtures'
        } 6>&1 | ForEach-Object { $_.ToString() })
        return [pscustomobject]@{
            padding = @($lines | ForEach-Object { [regex]::Match($_, '^ *').Length })
            columns = @($lines | ForEach-Object { $_.IndexOf(' : ') } | Sort-Object -Unique)
            timers = $testStartTimes.Count
        }
    }
    $preparationPassed = ($preparationOutput.padding -join ',') -ceq '0,2,4,6,6,4,2,0' -and $preparationOutput.columns.Count -eq 1 -and $preparationOutput.timers -eq 0
    if (-not $preparationPassed) { $issues.Add('The actual preparation helper must preserve declared nesting, aligned separators and completed timer cleanup') }
    Add-OutputTestResult -Name 'Hosted preparation nesting' -Passed $preparationPassed

    $checkStopwatch.Restart()
    $assistanceOutput = & {
        $path = Join-Path $PSScriptRoot '../hosted_copilot/tools/tests/Test-RuleAssistance.ps1'
        $ast = [Management.Automation.Language.Parser]::ParseFile($path, [ref]$null, [ref]$null)
        foreach ($helperName in @('Start-AssistanceTest', 'Add-AssistanceTestResult')) {
            $helper = $ast.Find({ param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -eq $helperName }, $true)
            . ([scriptblock]::Create($helper.Extent.Text))
        }
        $Quiet = $false
        $AlignmentWidth = 40
        $testResults = [Collections.Generic.List[object]]::new()
        $lines = @(& {
            foreach ($depth in 1..3) {
                $nesting = @{ Child = $true; Level = $depth }
                Start-AssistanceTest -Name 'assistance-check' -Detail 'Verify grounded context'
                Add-AssistanceTestResult -Name 'assistance-check' -Detail 'Grounded context verified'
            }
        } 6>&1 | ForEach-Object { $_.ToString() })
        return [pscustomobject]@{
            padding = @($lines | ForEach-Object { [regex]::Match($_, '^ *').Length })
            columns = @($lines | ForEach-Object { $_.IndexOf(' : ') } | Sort-Object -Unique)
            descriptions = @($lines | Where-Object { $_ -match 'Verify grounded context' }).Count
            results = $testResults.Count
        }
    }
    $assistancePassed = ($assistanceOutput.padding -join ',') -ceq '2,2,4,4,6,6' -and $assistanceOutput.columns.Count -eq 1 -and $assistanceOutput.descriptions -eq 3 -and $assistanceOutput.results -eq 3
    if (-not $assistancePassed) { $issues.Add('The actual assistance helpers must preserve nesting and alignment without repeating descriptions on completion') }
    Add-OutputTestResult -Name 'Hosted assistance nesting' -Passed $assistancePassed

    $checkStopwatch.Restart()
    $nodeGroupingPassed = & {
        $path = Join-Path $PSScriptRoot '../hosted_copilot/tools/modules/workbench/Workbench.NodeTests.psm1'
        Import-Module $path -Force
        $report = ConvertFrom-WorkbenchNodeTestReport -Report '<testsuites><testcase name="passing case" time="1.25"/><!-- {"shortName":"pass-check","description":"passing case"} --><testcase name="skipped case" time="0"><skipped message="Not configured"/></testcase><testcase name="failed case" time="0.5"><failure>Expected fixture failure</failure></testcase><!-- {"shortName":"fail-check","description":"failed case"} --></testsuites>' -ExitCode 1
        $ast = (Get-Command Invoke-WorkbenchNodeTests).ScriptBlock.Ast
        $loop = $ast.Find({ param($node) $node -is [Management.Automation.Language.ForEachStatementAst] -and $node.Variable.VariablePath.UserPath -eq 'test' }, $true)
        $renderLoop = [scriptblock]::Create($loop.Extent.Text)
        $lines = @(& (Get-Module Workbench.NodeTests) {
            param($RenderLoop, $Report)
            $result = $Report
            $alignmentWidth = 30
            & $RenderLoop
        } $renderLoop $report 6>&1 | ForEach-Object { $_.ToString() })
        $padding = @($lines | ForEach-Object { [regex]::Match($_, '^ *').Length })
        $parent = Format-ValidationLifecycleLine -Status failed -Name 'JUnit tests' -DurationSeconds 2
        $columns = @(@($lines) + @($parent) | ForEach-Object { $_.IndexOf(' : ') } | Sort-Object -Unique)
        return ($padding -join ',') -ceq '2,2,2,2,2' -and $columns.Count -eq 1 -and
            $lines[0] -match '^  \[RUNNING\]\s+pass-check\s+: passing case$' -and
            $lines[1] -match '^  \[PASSED\]\s+pass-check\s+: 1[.,]25s$' -and
            $lines[2] -match '^  \[SKIPPED\]\s+skipped case\s+: Not configured$' -and
            $lines[3] -match '^  \[RUNNING\]\s+fail-check\s+: failed case$' -and
            $lines[4] -match '^  \[FAILED\]\s+fail-check\s+: 0[.,]5s$' -and
            $report.testCount -eq 3 -and $report.skippedCount -eq 1 -and $report.failedCount -eq 1 -and $report.issueCount -eq 1 -and $report.exitCode -eq 1
    }
    if (-not $nodeGroupingPassed) { $issues.Add('Native case rows must be children of the JUnit activity, with one skipped row and unchanged failure counts and exit status') }
    Add-OutputTestResult -Name 'Hosted JUnit activity children' -Passed $nodeGroupingPassed

    $checkStopwatch.Restart()
    $labelReport = ConvertFrom-WorkbenchNodeTestReport -Report '<testsuites><testcase name="metadata probe" time="0"/><!-- {"shortName":"metadata-probe","description":"Probe structured metadata"} --><testcase name="skip probe" time="0"><skipped message="Synthetic skip reason"/></testcase><testcase time="0"/><testcase name="native name" time="0"/><!-- {"shortName":"   ","description":""} --><testcase name=" " time="0"/></testsuites>' -ExitCode 0
    $labelsPassed = $labelReport.status -ceq 'passed' -and
        (@($labelReport.tests.shortName) -join ',') -ceq 'metadata-probe,skip probe,test-003,native name,test-005' -and
        $labelReport.tests[0].name -ceq 'metadata probe' -and $labelReport.tests[0].description -ceq 'Probe structured metadata' -and
        $labelReport.tests[1].detail -ceq 'Synthetic skip reason' -and $labelReport.skippedCount -eq 1 -and $labelReport.passedCount -eq 4
    if (-not $labelsPassed) { $issues.Add('Native labels must prefer explicit shortName, then native name, then numbered fallback without losing skips or original names') }
    Add-OutputTestResult -Name 'Hosted JUnit label precedence' -Passed $labelsPassed

    $checkStopwatch.Restart()
    $diagnosticReport = ConvertFrom-WorkbenchNodeTestReport -Report '<testsuites><testcase name="first" time="0"/><!-- {"shortName":"first-short"} --><!-- {invalid diagnostic --><testcase name="second" time="0"/><!-- {"unrelated":"diagnostic"} --></testsuites>' -ExitCode 0
    $invalidMetadataReport = ConvertFrom-WorkbenchNodeTestReport -Report '<testsuites><testcase name="invalid metadata" time="0"/><!-- {"shortName":42} --></testsuites>' -ExitCode 0
    $diagnosticsPassed = $diagnosticReport.status -ceq 'passed' -and $diagnosticReport.tests[0].shortName -ceq 'first-short' -and
        $diagnosticReport.tests[1].shortName -ceq 'second' -and $invalidMetadataReport.status -ceq 'failed' -and $invalidMetadataReport.issueCount -eq 1
    if (-not $diagnosticsPassed) { $issues.Add('Diagnostic metadata must stay with its owning case, ignore unrelated comments and reject invalid field types') }
    Add-OutputTestResult -Name 'Hosted JUnit metadata boundaries' -Passed $diagnosticsPassed
}

foreach ($relativePath in @('Validate-ChangedToolkits.ps1') + $(if ($ProductScope -in @('All', 'Interactive')) { @('validate-ai-toolkit.ps1') } else { @() })) {
    $checkStopwatch.Restart()
    $priorIssueCount = $issues.Count
    $consumerContent = Get-Content -LiteralPath (Join-Path $PSScriptRoot $relativePath) -Raw
    if ($consumerContent -notmatch '\^\\s\*\\\[\(RUNNING\|PASSED\|FAILED\|SKIPPED\)\\\]' -or $consumerContent -notmatch 'Add-ValidationIndent -Line') {
        $issues.Add("$relativePath does not preserve nested child status indentation")
    }
    Add-OutputTestResult -Name "nested statuses/$([IO.Path]::GetFileName($relativePath))" -Passed ($issues.Count -eq $priorIssueCount)
}

if ($ProductScope -in @('All', 'Interactive')) {
    $checkStopwatch.Restart()
    $priorIssueCount = $issues.Count
    $interactiveValidationContent = Get-Content -LiteralPath (Join-Path $PSScriptRoot 'validate-ai-toolkit.ps1') -Raw
    if ($interactiveValidationContent -match "-Name 'npm-install'" -or
        $interactiveValidationContent -notmatch "-Name 'npm-packages'.*-RunningDetail 'VERIFYING AUDITED LOCKFILE'.*-SuccessDetail 'CURRENT \(MATCHES AUDITED LOCKFILE\)'" -or
        $interactiveValidationContent -notmatch 'function Test-NpmPackageGraphCurrent' -or
        $interactiveValidationContent -notmatch "npm-validation/node_modules/\.package-lock\.json" -or
        $interactiveValidationContent -notmatch 'if \(-not \(Test-NpmPackageGraphCurrent') {
        $issues.Add('Interactive npm validation must report package currency against the audited lockfile instead of labeling the result as an install')
    }
    Add-OutputTestResult -Name 'Interactive npm audit/package wording' -Passed ($issues.Count -eq $priorIssueCount)
}

if ($ProductScope -in @('All', 'Hosted')) {
    $checkStopwatch.Restart()
    $priorIssueCount = $issues.Count
    $hostedWorkbenchValidationContent = Get-Content -LiteralPath (Join-Path $PSScriptRoot '../hosted_copilot/tools/tests/Test-RuleWorkbench.ps1') -Raw
    if ($hostedWorkbenchValidationContent -match "Start-TestResult -Name 'locked-browser-dependencies'" -or
        $hostedWorkbenchValidationContent -notmatch '\$dependencyRunningDetail = if \(\$auditPassed\) \{ ''VERIFYING AUDITED LOCKFILE'' \} else \{ ''VERIFYING INSTALLED LOCKFILE GRAPH'' \}' -or
        $hostedWorkbenchValidationContent -notmatch 'Start-TestResult -Name ''npm-packages'' -RunningDetail \$dependencyRunningDetail' -or
        $hostedWorkbenchValidationContent -notmatch '\$lockedDependencySuccessDetail = if \(\$auditPassed\) \{ ''CURRENT \(MATCHES AUDITED LOCKFILE\)'' \} else \{ ''CURRENT \(MATCHES LOCKFILE; UNVERIFIED\)'' \}' -or
        $hostedWorkbenchValidationContent -notmatch 'Add-TestResult -Name ''npm-packages''.*-SuccessDetail \$lockedDependencySuccessDetail' -or
        $hostedWorkbenchValidationContent -notmatch 'function Test-NpmPackageGraphCurrent' -or
        $hostedWorkbenchValidationContent -notmatch "node_modules/\.package-lock\.json") {
        $issues.Add('Hosted npm validation must skip redundant installs and distinguish audited from unverified lockfile currency')
    }
    Add-OutputTestResult -Name 'Hosted npm audit/package wording' -Passed ($issues.Count -eq $priorIssueCount)
}

$suiteStopwatch.Stop()
$result = [ordered]@{
    status = if ($issues.Count -eq 0) { 'passed' } else { 'failed' }
    testCount = $results.Count
    passedCount = @($results | Where-Object status -CEQ 'passed').Count
    failedCount = @($results | Where-Object status -CEQ 'failed').Count
    skippedCount = @($results | Where-Object status -CEQ 'skipped').Count
    elapsedSeconds = $suiteStopwatch.Elapsed.TotalSeconds
    tests = $results.ToArray()
    issueCount = $issues.Count
    issues = @($issues.ToArray())
}

if ($OutputFormat -eq 'Json') {
    $result | ConvertTo-Json -Depth 4
}
else {
    $progressNameWidth = Get-ValidationNameWidth -Names (@('output-contracts') + @($results.name)) -MinimumWidth 30
    Write-Output ''
    foreach ($test in $results) {
        Write-Host (Format-ValidationLifecycleLine -Status running -Name $test.name -NameWidth $progressNameWidth)
        Write-Host (Format-ValidationLifecycleLine -Status $test.status -Name $test.name -DurationSeconds $test.durationSeconds -NameWidth $progressNameWidth)
    }
    Write-Output ''
    Write-Host (Format-ValidationLifecycleLine -Status $result.status -Name 'output-contracts' -DurationSeconds $result.elapsedSeconds -NameWidth $progressNameWidth)
    Write-ValidationSectionHeader -Title 'Validation output contract test summary'
    Write-ValidationSummary -Fields ([ordered]@{
        Status = $result.status.ToUpperInvariant()
        Scope = $ProductScope
        Tests = $result.testCount
        Passed = $result.passedCount
        Failed = $result.failedCount
        Skipped = $result.skippedCount
        'Issue Count' = $result.issueCount
        Elapsed = Format-ValidationDuration -DurationSeconds $result.elapsedSeconds
    })
    Write-ValidationSectionHeader -Title 'Validation output contract tests'
    $nameWidth = Get-ValidationNameWidth -Names @($results.name) -MinimumWidth 32
    Write-ValidationStatusTable -Rows $results.ToArray() -NameHeader 'Test' -NameWidth $nameWidth
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
