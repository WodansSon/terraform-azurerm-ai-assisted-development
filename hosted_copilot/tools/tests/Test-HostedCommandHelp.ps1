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
Import-Module (Join-Path $PSScriptRoot '../modules/shared/HostedToolkit.Helpers.psm1') -Force
Import-Module (Join-Path $PSScriptRoot '../modules/shared/HostedCli.psm1') -Force

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

    Write-TestProgress -Name 'tools-root-layout' -Detail 'Checking that only public entry points and the README occupy the tools root'
    $rootFiles = @(Get-ChildItem -LiteralPath (Join-Path $PSScriptRoot '..') -File | ForEach-Object Name | Sort-Object)
    $expectedRootFiles = @('Install-HostedRules.ps1', 'Invoke-HostedReview.ps1', 'README.md', 'Start-RuleWorkbench.ps1', 'Test-HostedRules.ps1') | Sort-Object
    Add-TestResult -Name 'tools-root-layout' -Passed (@(Compare-Object $expectedRootFiles $rootFiles).Count -eq 0) -Detail 'The tools root contains exactly the four public commands and README; support files belong in their owning folders.'

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

    Write-TestProgress -Name 'workbench-model-profiles' -Detail 'Checking centralized normal and saved-rule profile resolution'
    $profileCases = @(
        @{ Path = $workbenchLauncherPath; Parameters = @('Model', 'AssessmentReasoningEffort'); Profiles = @('normal') },
        @{ Path = (Join-Path $PSScriptRoot '../internal/workbench/Start-WorkbenchLoopbackServer.ps1'); Parameters = @('AssistanceModel', 'AssistanceReasoningEffort'); Profiles = @('normal') },
        @{ Path = (Join-Path $PSScriptRoot '../internal/reconciliation/Invoke-SavedRuleEvaluation.ps1'); Parameters = @('Model', 'ReasoningEffort'); Profiles = @('savedRuleEvaluation') }
    )
    foreach ($relativePath in @(
        'assessment/Invoke-SourceAssessment.ps1',
        'assessment/New-SourceAssessmentBaseline.ps1',
        'reconciliation/Invoke-AssessmentReconciliation.ps1',
        'reconciliation/Export-WorkbenchRuleIssues.ps1',
        'reconciliation/Invoke-ManualRuleRelationship.ps1',
        'reconciliation/Invoke-RuleIssueAdjudication.ps1'
    )) {
        $profileCases += @{ Path = (Join-Path $PSScriptRoot "../internal/$relativePath"); Parameters = @('Model', 'ReasoningEffort'); Profiles = @('normal') }
    }
    $profilesValid = $true
    foreach ($profileCase in $profileCases) {
        $parameters = (Get-Command -Name $profileCase.Path -CommandType ExternalScript).ScriptBlock.Ast.ParamBlock.Parameters
        foreach ($name in $profileCase.Parameters) {
            $parameter = @($parameters | Where-Object { $_.Name.VariablePath.UserPath -ceq $name })
            $profilesValid = $profilesValid -and $parameter.Count -eq 1 -and
                $null -eq $parameter[0].DefaultValue
        }
        $content = Get-Content -LiteralPath $profileCase.Path -Raw
        foreach ($profile in $profileCase.Profiles) {
            $profilesValid = $profilesValid -and $content.Contains("Resolve-HostedLlmProfile -Profile $profile ")
        }
    }
    $authorityCommand = Get-Command Get-SavedRuleAuthoritySha256 -ErrorAction SilentlyContinue
    if ($null -eq $authorityCommand) {
        Import-Module (Join-Path $PSScriptRoot '../modules/workbench/SavedRuleEvaluation.psm1') -Force
        $authorityCommand = Get-Command Get-SavedRuleAuthoritySha256
    }
    $authorityAst = $authorityCommand.ScriptBlock.Ast
    $authorityParameters = $(if ($authorityAst -is [Management.Automation.Language.FunctionDefinitionAst]) { $authorityAst.Body.ParamBlock.Parameters } else { $authorityAst.ParamBlock.Parameters })
    $profilesValid = $profilesValid -and @($authorityParameters | Where-Object { $_.Name.VariablePath.UserPath -cin @('Model', 'ReasoningEffort') -and $null -ne $_.DefaultValue }).Count -eq 0
    Add-TestResult -Name 'workbench-model-profiles' -Passed $profilesValid -Detail 'All normal and saved entry points resolve their role through the shared loader without literal model or effort defaults.'

    Write-TestProgress -Name 'llm-configuration' -Detail 'Checking central configuration, independent overrides, and fail-closed invalid inputs'
    $configurationPath = Join-Path $PSScriptRoot '../config/llm.json'
    $configuration = Get-Content -LiteralPath $configurationPath -Raw | ConvertFrom-Json -DateKind String
    $normalProfile = Resolve-HostedLlmProfile -Profile normal
    $savedProfile = Resolve-HostedLlmProfile -Profile savedRuleEvaluation
    Add-TestResult -Name 'llm-central-defaults' -Passed ($normalProfile.model -ceq $configuration.normal.model -and $normalProfile.reasoningEffort -ceq $configuration.normal.reasoningEffort -and $savedProfile.model -ceq $configuration.savedRuleEvaluation.model -and $savedProfile.reasoningEffort -ceq $configuration.savedRuleEvaluation.reasoningEffort) -Detail 'Both role defaults are read from the single Hosted LLM configuration.'
    $modelOverride = Resolve-HostedLlmProfile -Profile normal -Model 'fixture-model-override'
    $effortOverride = Resolve-HostedLlmProfile -Profile savedRuleEvaluation -ReasoningEffort 'xhigh'
    Add-TestResult -Name 'llm-independent-overrides' -Passed ($modelOverride.model -ceq 'fixture-model-override' -and $modelOverride.reasoningEffort -ceq $normalProfile.reasoningEffort -and $effortOverride.model -ceq $savedProfile.model -and $effortOverride.reasoningEffort -ceq 'xhigh') -Detail 'An explicit model or effort overrides only that setting and preserves the selected role.'
    $validConfiguration = [ordered]@{
        normal = [ordered]@{ model = 'fixture-normal'; reasoningEffort = 'high' }
        savedRuleEvaluation = [ordered]@{ model = 'fixture-saved'; reasoningEffort = 'medium' }
    }
    $changedConfigurationPath = Join-Path $tempRoot 'llm-valid.json'
    [IO.File]::WriteAllText($changedConfigurationPath, ($validConfiguration | ConvertTo-Json -Depth 5))
    $changedProfile = Resolve-HostedLlmProfile -Profile normal -ConfigurationPath $changedConfigurationPath
    $validConfiguration.normal.model = 'fixture-normal-changed'
    [IO.File]::WriteAllText($changedConfigurationPath, ($validConfiguration | ConvertTo-Json -Depth 5))
    $reloadedProfile = Resolve-HostedLlmProfile -Profile normal -ConfigurationPath $changedConfigurationPath
    $unchangedSavedProfile = Resolve-HostedLlmProfile -Profile savedRuleEvaluation -ConfigurationPath $changedConfigurationPath
    Add-TestResult -Name 'llm-configuration-reload' -Passed ($changedProfile.model -ceq 'fixture-normal' -and $reloadedProfile.model -ceq 'fixture-normal-changed' -and $unchangedSavedProfile.model -ceq 'fixture-saved') -Detail 'A newly resolved profile reads the file without a stale process-global model cache or cross-role changes.'
    $invalidConfigurations = @(
        @{ Name = 'missing'; Json = $null },
        @{ Name = 'malformed'; Json = '{' },
        @{ Name = 'null'; Json = 'null' },
        @{ Name = 'missing-role'; Json = '{"normal":{"model":"fixture","reasoningEffort":"high"}}' },
        @{ Name = 'missing-setting'; Json = '{"normal":{"model":"fixture"},"savedRuleEvaluation":{"model":"fixture","reasoningEffort":"medium"}}' },
        @{ Name = 'invalid-effort'; Json = '{"normal":{"model":"fixture","reasoningEffort":"invalid"},"savedRuleEvaluation":{"model":"fixture","reasoningEffort":"medium"}}' },
        @{ Name = 'empty-model'; Json = '{"normal":{"model":" ","reasoningEffort":"high"},"savedRuleEvaluation":{"model":"fixture","reasoningEffort":"medium"}}' },
        @{ Name = 'extra-setting'; Json = '{"normal":{"model":"fixture","reasoningEffort":"high","fallback":"fixture"},"savedRuleEvaluation":{"model":"fixture","reasoningEffort":"medium"}}' }
    )
    foreach ($case in $invalidConfigurations) {
        $path = Join-Path $tempRoot "llm-$($case.Name).json"
        if ($null -ne $case.Json) { [IO.File]::WriteAllText($path, $case.Json) }
        $rejected = $false
        try { $null = Resolve-HostedLlmProfile -Profile normal -ConfigurationPath $path } catch { $rejected = $true }
        Add-TestResult -Name "llm-rejects-$($case.Name)" -Passed $rejected -Detail 'Invalid or missing configuration fails rather than falling back to a hidden model.'
    }

    Write-TestProgress -Name 'cli-model-preflight' -Detail 'Checking metadata-only CLI launch, both profiles, and negative outcomes'
    $metadataFixture = Join-Path $PSScriptRoot 'fixtures/copilot-metadata-evaluator.ps1'
    $launch = Resolve-HostedCliLaunch -EvaluatorCommand $metadataFixture
    $profiles = [ordered]@{ normal = $normalProfile; savedRuleEvaluation = $savedProfile }
    $previousScenario = [Environment]::GetEnvironmentVariable('HOSTED_CLI_TEST_SCENARIO')
    try {
        [Environment]::SetEnvironmentVariable('HOSTED_CLI_TEST_SCENARIO', $null)
        $availability = Get-HostedCliAvailability -Launch $launch -Profiles $profiles
        Add-TestResult -Name 'cli-model-preflight' -Passed ($availability.protocolVersion -eq 3 -and $availability.profiles.Count -eq 2 -and $availability.commandPath -ceq $launch.commandPath) -Detail 'The complete fixture answers only status, authentication, and model metadata; both resolved profiles are required.'
        foreach ($case in @(
            @{ Scenario = 'unauthenticated'; Expected = 'not authenticated' },
            @{ Scenario = 'missing-model'; Expected = 'unavailable for profile' },
            @{ Scenario = 'disabled-model'; Expected = 'disabled for profile' },
            @{ Scenario = 'unknown-policy'; Expected = 'availability could not be verified' },
            @{ Scenario = 'unsupported-effort'; Expected = 'reasoning effort.*unsupported' },
            @{ Scenario = 'duplicate-model'; Expected = 'duplicate model metadata' },
            @{ Scenario = 'unsupported-protocol'; Expected = 'requires protocol 3' },
            @{ Scenario = 'rpc-error'; Expected = 'RPC code -32601' },
            @{ Scenario = 'timeout'; Expected = 'timed out' }
        )) {
            [Environment]::SetEnvironmentVariable('HOSTED_CLI_TEST_SCENARIO', $case.Scenario)
            $diagnostic = ''
            try { $null = Get-HostedCliAvailability -Launch $launch -Profiles $profiles -TimeoutSeconds $(if ($case.Scenario -ceq 'timeout') { 1 } else { 10 }) } catch { $diagnostic = [string]$_.Exception.Message }
            Add-TestResult -Name "cli-preflight-$($case.Scenario)" -Passed ($diagnostic -match $case.Expected -and -not $diagnostic.Contains('SYNTHETIC_SENSITIVE_VALUE')) -Detail 'The precheck fails actionably without accepting an availability conclusion or exposing raw diagnostic content.'
        }
    }
    finally { [Environment]::SetEnvironmentVariable('HOSTED_CLI_TEST_SCENARIO', $previousScenario) }
    $nativePath = (Get-Command pwsh -CommandType Application | Select-Object -First 1).Source
    $nativeLaunch = Resolve-HostedCliLaunch -EvaluatorCommand $nativePath
    Add-TestResult -Name 'cli-direct-launch-resolution' -Passed ($nativeLaunch.kind -ceq 'executable' -and $nativeLaunch.arguments.Count -eq 0) -Detail 'Explicit native executable paths resolve without installing a second CLI or changing PATH and aliases; this is a resolver check, not installer validation.'
    $spaceDirectory = Join-Path $tempRoot 'CLI path with spaces'
    $null = New-Item -ItemType Directory -Path $spaceDirectory
    $spaceScript = Join-Path $spaceDirectory 'metadata.ps1'
    [IO.File]::WriteAllText($spaceScript, ("& '" + $metadataFixture.Replace("'", "''") + "' @args"))
    $spaceLaunch = Resolve-HostedCliLaunch -EvaluatorCommand $spaceScript
    $spaceAvailability = Get-HostedCliAvailability -Launch $spaceLaunch -Profiles $profiles
    Add-TestResult -Name 'cli-path-with-spaces' -Passed ($spaceAvailability.profiles.Count -eq 2 -and $spaceLaunch.arguments[-1] -ceq $spaceScript) -Detail 'The shared launch descriptor preserves a script path containing spaces as one argument.'
    $nodeIdentity = (& node --input-type=module --eval 'console.log(JSON.stringify({platform:process.platform,arch:process.arch}))') | ConvertFrom-Json
    if ($LASTEXITCODE -ne 0) { throw 'Node identity could not be resolved for the synthetic npm installation' }
    $npmDirectory = Join-Path $spaceDirectory 'npm'
    $packageDirectory = Join-Path $npmDirectory 'node_modules/@github/copilot'
    $platformPackageDirectory = Join-Path $packageDirectory "node_modules/@github/copilot-$($nodeIdentity.platform)-$($nodeIdentity.arch)"
    $null = New-Item -ItemType Directory -Path $platformPackageDirectory -Force
    $runtimePath = Join-Path $platformPackageDirectory $(if ($IsWindows) { 'copilot.exe' } else { 'copilot' })
    [IO.File]::WriteAllText($runtimePath, 'Synthetic resolution-only runtime; not executed')
    [IO.File]::WriteAllText((Join-Path $packageDirectory 'package.json'), ('{"name":"@github/copilot","version":"1.0.0","bin":{"copilot":"npm-loader.js"}}'))
    [IO.File]::WriteAllText((Join-Path $packageDirectory 'npm-loader.js'), 'throw new Error("Resolution-only fixture must not execute its loader");')
    [IO.File]::WriteAllText((Join-Path $platformPackageDirectory 'package.json'), ('{"main":"' + [IO.Path]::GetFileName($runtimePath) + '"}'))
    $shimPath = Join-Path $npmDirectory 'copilot.ps1'
    [IO.File]::WriteAllText($shimPath, '$basedir = Split-Path $MyInvocation.MyCommand.Definition -Parent' + "`n" + '& node "$basedir/node_modules/@github/copilot/npm-loader.js" @args')
    $npmLaunch = Resolve-HostedCliLaunch -EvaluatorCommand $shimPath
    Add-TestResult -Name 'cli-npm-powershell-resolution' -Passed ($npmLaunch.kind -ceq 'npm-native' -and $npmLaunch.commandPath -ceq $runtimePath -and $npmLaunch.arguments.Count -eq 0) -Detail 'Package metadata and Node resolution normalize a synthetic npm shim and nested platform package beneath a path containing spaces without running the shim.'
    if ($IsWindows) {
        $cmdPath = Join-Path $npmDirectory 'copilot.cmd'
        [IO.File]::WriteAllText($cmdPath, '@echo off' + "`r`n" + 'set dp0=%~dp0' + "`r`n" + 'node "%dp0%\node_modules\@github\copilot\npm-loader.js" %*')
        $cmdLaunch = Resolve-HostedCliLaunch -EvaluatorCommand $cmdPath
        Add-TestResult -Name 'cli-npm-command-resolution' -Passed ($cmdLaunch.kind -ceq 'npm-native' -and $cmdLaunch.commandPath -ceq $runtimePath) -Detail 'The npm command wrapper selects the same synthetic platform executable without shell-based RPC.'
    }
    [IO.File]::WriteAllText((Join-Path $packageDirectory 'package.json'), '{"name":"not-copilot","bin":{"copilot":"npm-loader.js"}}')
    $invalidNpmRejected = $false
    try { $null = Resolve-HostedCliLaunch -EvaluatorCommand $shimPath } catch { $invalidNpmRejected = $_.Exception.Message -match 'package metadata' }
    Add-TestResult -Name 'cli-npm-metadata-mismatch' -Passed $invalidNpmRejected -Detail 'A launcher whose package identity disagrees is rejected without switching to a different installation.'
    $launcherSource = Get-Content -LiteralPath $workbenchLauncherPath -Raw
    Add-TestResult -Name 'cli-preflight-before-staging' -Passed ($launcherSource.IndexOf('Get-HostedCliAvailability -Launch', [StringComparison]::Ordinal) -lt $launcherSource.IndexOf('Copy-Item -LiteralPath (Join-Path $workbenchSource', [StringComparison]::Ordinal)) -Detail 'Workbench availability is checked before staging writes, and help returns before preflight.'
    $blockedSite = Join-Path $tempRoot 'preflight-blocked-site'
    $null = New-Item -ItemType Directory -Path $blockedSite
    $sentinel = Join-Path $blockedSite 'app.js'
    [IO.File]::WriteAllText($sentinel, 'Synthetic prior staged asset')
    $blockedOutput = @(& pwsh -NoProfile -File $workbenchLauncherPath -SiteDirectory $blockedSite -EvaluatorCommand $metadataFixture -Model 'fixture-unavailable-startup' -SkipGitHubAuthorization -StageOnly -NoLaunch -OutputFormat Json 2>&1)
    $blockedExitCode = $LASTEXITCODE
    Add-TestResult -Name 'cli-failed-startup-preserves-staging' -Passed ($blockedExitCode -ne 0 -and ($blockedOutput | Out-String) -match 'unavailable for profile' -and (Get-Content -LiteralPath $sentinel -Raw) -ceq 'Synthetic prior staged asset' -and @(Get-ChildItem -LiteralPath $blockedSite -Force).Count -eq 1) -Detail 'A real launcher invocation with an unavailable synthetic model fails before asset replacement, token creation, staging, rebuilding, or server startup.'
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
