[CmdletBinding()]
param(
    [ValidateSet('Text', 'Json')]
    [string]$OutputFormat = 'Text'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Import-Module (Join-Path $PSScriptRoot '../../../tools/ValidationOutput.psm1') -Force
$helpModulePath = Join-Path $PSScriptRoot '../modules/shared/HostedCommandHelp.psm1'
$fixturePath = Join-Path $PSScriptRoot 'fixtures/command-help-fixture.ps1'
$workbenchLauncherPath = Join-Path $PSScriptRoot '../Start-RuleWorkbench.ps1'
$installerPath = Join-Path $PSScriptRoot '../Install-HostedRules.ps1'
$reviewCommandPath = Join-Path $PSScriptRoot '../Invoke-HostedReview.ps1'
$validatorPath = Join-Path $PSScriptRoot '../Test-HostedRules.ps1'
Import-Module $helpModulePath -Force

$results = [Collections.Generic.List[object]]::new()
$issues = [Collections.Generic.List[string]]::new()
$tempRoot = Join-Path ([IO.Path]::GetTempPath()) ('hosted-command-help-test-' + [guid]::NewGuid().ToString('N'))
$null = New-Item -ItemType Directory -Path $tempRoot -Force
$ansiPattern = [regex]::Escape([string][char]27) + '\[[0-9;]*m'

function Add-TestResult {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][bool]$Passed,
        [Parameter(Mandatory = $true)][string]$Detail
    )

    $results.Add([pscustomobject]@{ name = $Name; status = if ($Passed) { 'passed' } else { 'failed' }; detail = $Detail })
    if (-not $Passed) {
        $issues.Add("$Name`: $Detail")
    }
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

try {
    if ($OutputFormat -eq 'Text') {
        Write-ValidationSectionHeader -Title 'Hosted command help'
    }

    Write-TestProgress -Name 'native-help-content' -Detail 'Reading standard PowerShell help and parameter-set metadata'
    $nativeHelp = Get-Help -Name $fixturePath -Full
    $fixtureCommand = Get-Command -Name $fixturePath -CommandType ExternalScript
    $nativeHelpValid = [string]$nativeHelp.Synopsis -like '*shared Hosted command help renderer*' -and
        @($nativeHelp.Parameters.Parameter | Where-Object Name -CEQ 'Name').Count -eq 1 -and
        @($nativeHelp.Examples.Example).Count -eq 2 -and
        [string]@($fixtureCommand.ParameterSets | Where-Object IsDefault)[0].Name -ceq 'Default' -and
        @($fixtureCommand.ParameterSets.Name | Sort-Object) -join ',' -ceq 'Alternate,Default,Detailed,Help'
    Add-TestResult -Name 'native-help-content' -Passed $nativeHelpValid -Detail 'Comment-based help and native parameter sets remain the command authority.'

    Write-TestProgress -Name 'shared-help-rendering' -Detail 'Rendering one deterministic template from native command metadata'
    $renderedLines = @(Get-HostedCommandHelp -ScriptPath $fixturePath -Width 90)
    $renderedText = $renderedLines -join "`n"
    $renderingValid = $renderedText -match '(?m)^COMMAND-HELP-FIXTURE$' -and
        $renderedText -match '(?m)^SUMMARY$' -and
        $renderedText -match '(?m)^USAGE$' -and
        $renderedText -match '(?m)^OPTIONS$' -and
        $renderedText -match '(?m)^  -Name <text>  Default: World$' -and
        $renderedText -match '(?m)^HELP$' -and
        $renderedText -match '(?m)^NOTES$' -and
        $renderedText -match '(?m)^RELATED LINKS$'
    Add-TestResult -Name 'shared-help-rendering' -Passed $renderingValid -Detail 'The renderer presents native help through the fixed Hosted layout.'

    Write-TestProgress -Name 'help-alias-equivalence' -Detail 'Invoking curated and native help without operation side effects'
    $sentinelPath = Join-Path $tempRoot 'operation.marker'
    $previousSentinel = $env:HOSTED_COMMAND_HELP_SENTINEL
    $env:HOSTED_COMMAND_HELP_SENTINEL = $sentinelPath
    try {
        $outputs = [Collections.Generic.List[string]]::new()
        $aliasExitCodes = [Collections.Generic.List[int]]::new()
        foreach ($helpArgument in @('-Help', '-h', '-Detailed')) {
            $helpOutput = @(& pwsh -NoProfile -File $fixturePath $helpArgument 2>&1)
            $aliasExitCodes.Add($LASTEXITCODE)
            $outputs.Add(($helpOutput | Out-String).Trim())
        }
        $nativeQuestionHelp = @(& pwsh -NoProfile -File $fixturePath '-?' 2>&1)
        $nativeQuestionExitCode = $LASTEXITCODE
    }
    finally {
        if ($null -eq $previousSentinel) {
            Remove-Item Env:HOSTED_COMMAND_HELP_SENTINEL -ErrorAction SilentlyContinue
        }
        else {
            $env:HOSTED_COMMAND_HELP_SENTINEL = $previousSentinel
        }
    }
    $aliasesValid = @($aliasExitCodes | Where-Object { $_ -ne 0 }).Count -eq 0 -and
        @($outputs | Sort-Object -Unique).Count -eq 1 -and
        $nativeQuestionExitCode -eq 0 -and
        ($nativeQuestionHelp | Out-String) -match 'Exercises the shared Hosted command help renderer' -and
        -not (Test-Path -LiteralPath $sentinelPath)
    Add-TestResult -Name 'help-alias-equivalence' -Passed $aliasesValid -Detail 'Help, h, and Detailed return identical curated output, while native question-mark help succeeds and every help path exits before fixture work.'

    Write-TestProgress -Name 'registered-command-help' -Detail 'Validating all four maintainer command menus and native help topics'
    $registeredCommands = @(
        @{ Path = $workbenchLauncherPath; Title = 'HOSTED RULE WORKBENCH HELP'; Synopsis = 'Launches or rebuilds the Hosted Rule Workbench'; Groups = @('WORKFLOW OPTIONS', 'SERVER AND OUTPUT', 'EVALUATION', 'STORAGE AND RECOVERY', 'AUTHORIZATION') },
        @{ Path = $installerPath; Title = 'HOSTED RULES INSTALLATION HELP'; Synopsis = 'Plans or installs the Hosted Toolkit payload'; Groups = @('DEPLOYMENT OPTIONS', 'TARGET AND PACKAGE', 'OUTPUT') },
        @{ Path = $reviewCommandPath; Title = 'HOSTED REVIEW WORKFLOW HELP'; Synopsis = 'Starts, resumes, adjudicates, or cleans up a controlled Hosted review'; Groups = @('REVIEW LIFECYCLE', 'REVIEW QUALITY', 'TARGET REPOSITORY') },
        @{ Path = $validatorPath; Title = 'HOSTED RULES VALIDATION HELP'; Synopsis = 'Validates the complete Hosted Toolkit source checkout'; Groups = @('VALIDATION SCOPE', 'OUTPUT') }
    )
    $commonParameterNames = @('Verbose', 'Debug', 'ErrorAction', 'WarningAction', 'InformationAction', 'ProgressAction', 'ErrorVariable', 'WarningVariable', 'InformationVariable', 'OutVariable', 'OutBuffer', 'PipelineVariable')
    $registeredCommandsValid = $true
    $isolatedLocalAppData = Join-Path $tempRoot 'isolated-local-app-data'
    $previousLocalAppData = $env:LOCALAPPDATA
    $env:LOCALAPPDATA = $isolatedLocalAppData
    try {
        foreach ($registeredCommand in $registeredCommands) {
            $command = Get-Command -Name $registeredCommand.Path -CommandType ExternalScript
            $nativeHelp = Get-Help -Name $registeredCommand.Path -Full
            $commandParameterNames = @($command.Parameters.Values | Where-Object { $_.Name -notin $commonParameterNames } | ForEach-Object Name)
            $operationalParameterNames = @($commandParameterNames | Where-Object { $_ -notin @('Help', 'Detailed') })
            $nativeHelpParameterNames = @($nativeHelp.Parameters.Parameter | ForEach-Object Name)
            $customOutputs = [Collections.Generic.List[string]]::new()
            foreach ($helpArgument in @('-Help', '-h', '-Detailed')) {
                $customOutput = @(& pwsh -NoProfile -File $registeredCommand.Path $helpArgument 2>&1)
                if ($LASTEXITCODE -ne 0) {
                    $registeredCommandsValid = $false
                }
                $normalizedOutput = (($customOutput | Out-String) -replace "`r`n", "`n") -replace $ansiPattern, ''
                $customOutputs.Add($normalizedOutput.Trim())
            }
            $nativeQuestionOutput = @(& pwsh -NoProfile -File $registeredCommand.Path '-?' 2>&1)
            $nativeQuestionExitCode = $LASTEXITCODE
            $customText = $customOutputs[0]
            $registeredCommandsValid = $registeredCommandsValid -and
                @($customOutputs | Sort-Object -Unique).Count -eq 1 -and
                $nativeQuestionExitCode -eq 0 -and
                ($nativeQuestionOutput | Out-String) -match [regex]::Escape([string]$registeredCommand.Synopsis) -and
                $customText -match "(?m)^$([regex]::Escape([string]$registeredCommand.Title))$" -and
                @($registeredCommand.Groups | Where-Object { $customText -notmatch "(?m)^$([regex]::Escape([string]$_))$" }).Count -eq 0 -and
                @($operationalParameterNames | Where-Object { ([regex]::Matches($customText, "(?m)^  -$([regex]::Escape($_))(?: |$)")).Count -ne 1 }).Count -eq 0 -and
                @($commandParameterNames | Where-Object { $_ -notin $nativeHelpParameterNames }).Count -eq 0 -and
                @($command.ParameterSets.Name | Where-Object { $_ -ceq 'Help' }).Count -eq 1 -and
                @($command.ParameterSets.Name | Where-Object { $_ -ceq 'Detailed' }).Count -eq 1 -and
                $customText -notmatch 'Join-Path|GetFolderPath|Get-Help [A-Z]:'
        }
    }
    finally {
        $env:LOCALAPPDATA = $previousLocalAppData
    }
    $registeredCommandsValid = $registeredCommandsValid -and -not (Test-Path -LiteralPath $isolatedLocalAppData)
    Add-TestResult -Name 'registered-command-help' -Passed $registeredCommandsValid -Detail 'All four maintainer commands expose complete native help plus equivalent side-effect-free Help, h, and Detailed menus.'

    Write-TestProgress -Name 'workbench-argument-contract' -Detail 'Rejecting incomplete and conflicting Workbench invocations before operation'
    $forceWithoutRebuildOutput = @(& pwsh -NoProfile -File $workbenchLauncherPath -Force -StageOnly 2>&1)
    $forceWithoutRebuildExitCode = $LASTEXITCODE
    $forceWithResumeOutput = @(& pwsh -NoProfile -File $workbenchLauncherPath -Rebuild -Force -AssessmentResumeDirectory 'synthetic' -StageOnly 2>&1)
    $forceWithResumeExitCode = $LASTEXITCODE
    $helpWithPortOutput = @(& pwsh -NoProfile -File $workbenchLauncherPath -Help -Port 43147 2>&1)
    $helpWithPortExitCode = $LASTEXITCODE
    $workbenchArgumentContractValid = $forceWithoutRebuildExitCode -ne 0 -and
        ($forceWithoutRebuildOutput | Out-String) -match 'Force requires Rebuild' -and
        $forceWithResumeExitCode -ne 0 -and
        ($forceWithResumeOutput | Out-String) -match 'Parameter set cannot be resolved' -and
        $helpWithPortExitCode -ne 0 -and
        ($helpWithPortOutput | Out-String) -match 'Parameter set cannot be resolved'
    Add-TestResult -Name 'workbench-argument-contract' -Passed $workbenchArgumentContractValid -Detail 'Workbench dependencies fail actionably and native parameter sets reject mutually exclusive help, force, and resume shapes.'
}
catch {
    $issues.Add([string]$_.Exception.Message)
}
finally {
    Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
}

$status = if ($issues.Count -eq 0) { 'passed' } else { 'failed' }
$result = [ordered]@{
    status = $status
    testCount = $results.Count
    issueCount = $issues.Count
    tests = $results.ToArray()
    issues = $issues.ToArray()
}

if ($OutputFormat -eq 'Json') {
    $result | ConvertTo-Json -Depth 10
}
else {
    Write-ValidationSectionHeader -Title 'Hosted command help test summary'
    Write-ValidationSummary -Fields ([ordered]@{ Status = $status.ToUpperInvariant(); Tests = $results.Count; Issues = $issues.Count })
    Write-ValidationSectionHeader -Title 'Command help tests'
    Write-ValidationTwoColumnTable -Rows $results.ToArray() -FirstHeader 'Status' -FirstProperty 'status' -SecondHeader 'Test' -SecondProperty 'name' -FirstWidth 24 -UppercaseFirst
    if ($issues.Count -gt 0) {
        Write-ValidationSectionHeader -Title 'Failures'
        foreach ($issue in $issues) {
            Write-Output "  - $issue"
        }
    }
    Complete-ValidationTextOutput
}

if ($issues.Count -gt 0) {
    exit 1
}
