[CmdletBinding()]
param(
    [ValidateSet('Text', 'Json')]
    [string]$OutputFormat = 'Text',

    [ValidateSet('Auto', 'Worktree', 'Branch', 'Combined')]
    [string]$ChangedScope = 'Auto',

    [string[]]$ChangedPaths,

    [switch]$PlanOnly,

    [switch]$InteractiveChangelogNotRequired,

    [string]$InteractiveChangelogReason,

    [switch]$HostedChangelogNotRequired,

    [string]$HostedChangelogReason,

    [switch]$SkipInteractiveRegressionHarness,

    [switch]$SkipInteractiveUpstreamDrift
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$validationOutputModulePath = Join-Path $PSScriptRoot 'ValidationOutput.psm1'
Import-Module -Name $validationOutputModulePath -Force

$ownershipPath = Join-Path $PSScriptRoot 'toolkit-ownership.json'
$interactiveValidatorPath = Join-Path $PSScriptRoot 'Validate-InteractiveToolkit.ps1'
$hostedValidatorPath = Join-Path $repoRoot 'hosted_copilot/tools/Test-Toolkit.ps1'
$gitCommand = Get-Command 'git' -ErrorAction SilentlyContinue
$explicitPathsProvided = $PSBoundParameters.ContainsKey('ChangedPaths')

function Invoke-GitCommand {
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$Arguments,

        [switch]$AllowFailure
    )

    if ($null -eq $gitCommand) {
        if ($AllowFailure) {
            return $null
        }

        throw 'git was not found on PATH'
    }

    $global:LASTEXITCODE = 0
    $output = @(& $gitCommand.Source -C $repoRoot @Arguments 2>$null)
    $exitCode = if ($null -ne $LASTEXITCODE) { $LASTEXITCODE } else { 0 }
    $global:LASTEXITCODE = 0

    if ($exitCode -ne 0) {
        if ($AllowFailure) {
            return $null
        }

        throw ("git command failed ({0}): git {1}" -f $exitCode, ($Arguments -join ' '))
    }

    return $output
}

function Get-WorktreePath {
    $paths = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
    $statusLines = @(Invoke-GitCommand -Arguments @('status', '--porcelain', '--untracked-files=all') -AllowFailure)

    foreach ($statusLine in $statusLines) {
        if ([string]::IsNullOrWhiteSpace($statusLine) -or $statusLine.Length -lt 4) {
            continue
        }

        $pathValue = $statusLine.Substring(3).Trim()
        if ($pathValue -match ' -> ') {
            $pathValue = ($pathValue -split ' -> ')[-1]
        }

        if (-not [string]::IsNullOrWhiteSpace($pathValue)) {
            [void]$paths.Add($pathValue.Replace('\', '/'))
        }
    }

    return @($paths | Sort-Object)
}

function Get-BranchPath {
    $candidateRefs = @()
    if (-not [string]::IsNullOrWhiteSpace($env:GITHUB_BASE_REF)) {
        $candidateRefs += @("origin/$($env:GITHUB_BASE_REF)", $env:GITHUB_BASE_REF)
    }
    $candidateRefs += @('origin/main', 'upstream/main', 'main')

    foreach ($candidateRef in @($candidateRefs | Select-Object -Unique)) {
        if ($null -eq (Invoke-GitCommand -Arguments @('rev-parse', '--verify', $candidateRef) -AllowFailure)) {
            continue
        }

        $paths = @(Invoke-GitCommand -Arguments @('diff', '--name-only', "$candidateRef...HEAD") -AllowFailure)
        if ($null -ne $paths) {
            return @($paths | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | ForEach-Object { $_.Replace('\', '/') } | Sort-Object -Unique)
        }
    }

    return @()
}

function Resolve-ChangedPath {
    if ($explicitPathsProvided) {
        return [pscustomobject]@{
            scope = 'explicit'
            paths = @($ChangedPaths | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | ForEach-Object {
                $normalizedPath = $_.Replace('\', '/')
                if ($normalizedPath.StartsWith('./')) {
                    $normalizedPath.Substring(2)
                }
                else {
                    $normalizedPath
                }
            } | Sort-Object -Unique)
        }
    }

    $worktreePaths = @(Get-WorktreePath)
    $branchPaths = @(Get-BranchPath)

    switch ($ChangedScope) {
        'Worktree' { return [pscustomobject]@{ scope = 'worktree'; paths = $worktreePaths } }
        'Branch' { return [pscustomobject]@{ scope = 'branch'; paths = $branchPaths } }
        'Combined' { return [pscustomobject]@{ scope = 'combined'; paths = @($worktreePaths + $branchPaths | Sort-Object -Unique) } }
        'Auto' {
            if ($worktreePaths.Count -gt 0) {
                return [pscustomobject]@{ scope = 'worktree'; paths = $worktreePaths }
            }

            return [pscustomobject]@{ scope = 'branch'; paths = $branchPaths }
        }
    }
}

function Invoke-ProfileValidator {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name,

        [Parameter(Mandatory = $true)]
        [string]$Path,

        [string[]]$Arguments = @()
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        return [pscustomobject]@{
            name = $Name
            status = 'failed'
            exitCode = 1
            detail = "Validator was not found at $Path"
            result = $null
        }
    }

    $childOutputFormat = if ($OutputFormat -eq 'Text') { 'Text' } else { 'Json' }
    $validatorName = "validator/{0}" -f $Name.ToLowerInvariant().Replace(' toolkit', '')
    if ($OutputFormat -eq 'Text') {
        Write-Host (Format-ValidationStatusLine -Status 'running' -Name $validatorName -Detail 'IN PROGRESS')
    }

    $started = Get-Date
    $global:LASTEXITCODE = 0
    $output = @(& pwsh -NoProfile -File $Path -OutputFormat $childOutputFormat @Arguments 2>&1 | ForEach-Object {
        if ($OutputFormat -eq 'Text' -and ([string]$_) -match '^\s*\[(RUNNING|PASSED|FAILED|SKIPPED)\]') {
            Write-Host (Add-ValidationIndent -Line ([string]$_))
        }

        Write-Output $_
    })
    $exitCode = if ($null -ne $LASTEXITCODE) { $LASTEXITCODE } else { 0 }
    $durationSeconds = [Math]::Round(((Get-Date) - $started).TotalSeconds, 2)
    $outputText = ($output | Out-String).Trim()
    $parsedResult = $null

    if ($childOutputFormat -eq 'Json' -and -not [string]::IsNullOrWhiteSpace($outputText)) {
        try {
            $parsedResult = $outputText | ConvertFrom-Json
        }
        catch {
            $exitCode = 1
        }
    }

    $reportedStatus = $null
    $reportedIssues = @()
    if ($null -ne $parsedResult) {
        if ($parsedResult.PSObject.Properties.Name -contains 'status') {
            $reportedStatus = $parsedResult.status
        }
        elseif ($parsedResult.PSObject.Properties.Name -contains 'overallStatus') {
            $reportedStatus = $parsedResult.overallStatus
        }
        if ($parsedResult.PSObject.Properties.Name -contains 'issues') {
            $reportedIssues = @($parsedResult.issues | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) })
        }
    }

    if ($reportedStatus -eq 'failed' -and $exitCode -eq 0) {
        $exitCode = 1
    }

    if ($OutputFormat -eq 'Text') {
        $profileStatus = if ($exitCode -eq 0) { 'passed' } else { 'failed' }
        $durationDetail = Format-ValidationDuration -DurationSeconds $durationSeconds
        Write-Host (Format-ValidationStatusLine -Status $profileStatus -Name $validatorName -Detail $durationDetail)
    }

    return [pscustomobject]@{
        name = $Name
        status = if ($exitCode -eq 0) { 'passed' } else { 'failed' }
        exitCode = $exitCode
        durationSeconds = $durationSeconds
        detail = if ($reportedIssues.Count -gt 0) { "Validator reported $reportedStatus`: $($reportedIssues -join '; ')" } elseif (-not [string]::IsNullOrWhiteSpace($reportedStatus)) { "Validator reported $reportedStatus." } elseif ($exitCode -eq 0) { 'Validator completed successfully.' } else { $outputText }
        result = $parsedResult
    }
}

function Invoke-RepositoryCheck {
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [string[]]$Paths
    )

    $checkIssues = New-Object 'System.Collections.Generic.List[string]'
    $existingMarkdownPaths = @($Paths | Where-Object {
        $_.EndsWith('.md', [System.StringComparison]::OrdinalIgnoreCase) -and (Test-Path -LiteralPath (Join-Path $repoRoot $_))
    })

    if ($existingMarkdownPaths.Count -gt 0) {
        $npxCommand = Get-Command 'npx.cmd' -ErrorAction SilentlyContinue
        if ($null -eq $npxCommand) {
            $npxCommand = Get-Command 'npx' -ErrorAction SilentlyContinue
        }

        if ($null -eq $npxCommand) {
            $checkIssues.Add('npx was not found on PATH')
        }
        else {
            Push-Location $repoRoot
            try {
                $global:LASTEXITCODE = 0
                $markdownOutput = @(& $npxCommand.Source -y --prefer-offline markdownlint-cli2 @existingMarkdownPaths --config '.github/.markdownlint.json' 2>&1)
                $markdownExitCode = if ($null -ne $LASTEXITCODE) { $LASTEXITCODE } else { 0 }
            }
            finally {
                Pop-Location
            }

            if ($markdownExitCode -ne 0) {
                $checkIssues.Add(("Markdown validation failed: {0}" -f (($markdownOutput | Out-String).Trim())))
            }
        }
    }

    if ($null -eq $gitCommand) {
        $checkIssues.Add('git was not found on PATH')
    }
    elseif ($Paths.Count -gt 0) {
        $global:LASTEXITCODE = 0
        $diffOutput = @(& $gitCommand.Source -C $repoRoot diff --check -- @Paths 2>&1)
        $diffExitCode = if ($null -ne $LASTEXITCODE) { $LASTEXITCODE } else { 0 }
        $global:LASTEXITCODE = 0

        if ($diffExitCode -ne 0) {
            $checkIssues.Add(("Whitespace validation failed: {0}" -f (($diffOutput | Out-String).Trim())))
        }
    }

    return [pscustomobject]@{
        name = 'Repository maintenance'
        status = if ($checkIssues.Count -eq 0) { 'passed' } else { 'failed' }
        exitCode = if ($checkIssues.Count -eq 0) { 0 } else { 1 }
        detail = if ($checkIssues.Count -eq 0) { 'Applicable shared repository checks passed.' } else { $checkIssues -join [Environment]::NewLine }
    }
}

if (-not (Test-Path -LiteralPath $ownershipPath)) {
    throw "Toolkit ownership map was not found at $ownershipPath"
}

$ownershipMap = Get-Content -LiteralPath $ownershipPath -Raw | ConvertFrom-Json
$supportedOwnership = @('interactive', 'hosted', 'shared', 'repository-maintenance')
$classification = New-Object 'System.Collections.Generic.List[object]'
$unknownPaths = New-Object 'System.Collections.Generic.List[string]'
$resolution = Resolve-ChangedPath

foreach ($changedPath in $resolution.paths) {
    $matchedRule = $null
    foreach ($rule in $ownershipMap.rules) {
        if ($supportedOwnership -notcontains $rule.ownership) {
            throw "Unsupported ownership '$($rule.ownership)' for pattern '$($rule.pattern)'"
        }

        if ($changedPath -like $rule.pattern) {
            $matchedRule = $rule
            break
        }
    }

    if ($null -eq $matchedRule) {
        $unknownPaths.Add($changedPath)
        $classification.Add([pscustomobject]@{ path = $changedPath; ownership = 'unknown'; pattern = $null })
        continue
    }

    $classification.Add([pscustomobject]@{ path = $changedPath; ownership = $matchedRule.ownership; pattern = $matchedRule.pattern })
}

$classifiedOwnership = @($classification.ToArray() | Select-Object -ExpandProperty ownership -Unique)
$runInteractive = ($classifiedOwnership -contains 'interactive') -or ($classifiedOwnership -contains 'shared')
$runHosted = ($classifiedOwnership -contains 'hosted') -or ($classifiedOwnership -contains 'shared')
$runRepositoryChecks = ($classifiedOwnership -contains 'repository-maintenance') -or ($classifiedOwnership -contains 'shared')
$requiredValidators = @()
if ($runInteractive) { $requiredValidators += 'Interactive Toolkit' }
if ($runHosted) { $requiredValidators += 'Hosted Toolkit' }

$changelogIssues = New-Object 'System.Collections.Generic.List[string]'
$interactiveChangelogChanged = $resolution.paths -contains 'CHANGELOG.md'
$hostedChangelogChanged = $resolution.paths -contains 'hosted_copilot/CHANGELOG.md'

if ($InteractiveChangelogNotRequired -and [string]::IsNullOrWhiteSpace($InteractiveChangelogReason)) {
    throw 'InteractiveChangelogNotRequired requires InteractiveChangelogReason'
}
if ($HostedChangelogNotRequired -and [string]::IsNullOrWhiteSpace($HostedChangelogReason)) {
    throw 'HostedChangelogNotRequired requires HostedChangelogReason'
}

$interactiveChangelogStatus = if (-not $runInteractive) {
    'not-applicable'
}
elseif ($interactiveChangelogChanged) {
    'updated'
}
elseif ($InteractiveChangelogNotRequired) {
    'waived'
}
else {
    if (-not $PlanOnly) {
        $changelogIssues.Add('Interactive Toolkit changes require CHANGELOG.md or an explicit Interactive Toolkit changelog waiver')
    }
    'required'
}

$hostedChangelogStatus = if (-not $runHosted) {
    'not-applicable'
}
elseif ($hostedChangelogChanged) {
    'updated'
}
elseif ($HostedChangelogNotRequired) {
    'waived'
}
else {
    if (-not $PlanOnly) {
        $changelogIssues.Add('Hosted Toolkit changes require hosted_copilot/CHANGELOG.md or an explicit Hosted Toolkit changelog waiver')
    }
    'required'
}

if ($OutputFormat -eq 'Text' -and -not $PlanOnly) {
    Write-ValidationSectionHeader -Title 'Changed Toolkit validation'
}

$executions = New-Object 'System.Collections.Generic.List[object]'
if (-not $PlanOnly -and $unknownPaths.Count -eq 0) {
    if ($runInteractive) {
        $interactiveArguments = @()
        if ($InteractiveChangelogNotRequired) {
            $interactiveArguments += @('-ChangelogNotRequired', '-ChangelogReason', $InteractiveChangelogReason)
        }
        if ($SkipInteractiveRegressionHarness) { $interactiveArguments += '-SkipRegressionHarness' }
        if ($SkipInteractiveUpstreamDrift) { $interactiveArguments += '-SkipUpstreamDrift' }

        $executions.Add((Invoke-ProfileValidator -Name 'Interactive Toolkit' -Path $interactiveValidatorPath -Arguments $interactiveArguments))
    }

    if ($runHosted) {
        $executions.Add((Invoke-ProfileValidator -Name 'Hosted Toolkit' -Path $hostedValidatorPath))
    }
}

$executionFailures = @($executions.ToArray() | Where-Object { $_.status -eq 'failed' })
$repositoryExecution = $null
if (-not $PlanOnly -and $unknownPaths.Count -eq 0 -and $runRepositoryChecks) {
    $repositoryPaths = @($classification.ToArray() | Where-Object { $_.ownership -in @('repository-maintenance', 'shared') } | Select-Object -ExpandProperty path)
    $repositoryExecution = Invoke-RepositoryCheck -Paths $repositoryPaths
}

$repositoryFailed = $null -ne $repositoryExecution -and $repositoryExecution.status -eq 'failed'
$status = if ($unknownPaths.Count -gt 0 -or $executionFailures.Count -gt 0 -or $changelogIssues.Count -gt 0 -or $repositoryFailed) {
    'failed'
}
elseif ($PlanOnly) {
    'planned'
}
else {
    'passed'
}

$result = [ordered]@{
    status = $status
    purpose = 'repository-maintenance'
    scope = $resolution.scope
    planOnly = [bool]$PlanOnly
    changedPathCount = $resolution.paths.Count
    classifications = @($classification.ToArray())
    requiredValidators = $requiredValidators
    repositoryChecksRequired = $runRepositoryChecks
    changelogDecisions = [ordered]@{
        interactive = $interactiveChangelogStatus
        hosted = $hostedChangelogStatus
    }
    changelogIssues = @($changelogIssues.ToArray())
    repositoryExecution = $repositoryExecution
    executions = @($executions.ToArray())
    unknownPaths = @($unknownPaths.ToArray())
}

if ($OutputFormat -eq 'Json') {
    $result | ConvertTo-Json -Depth 12
}
else {
    Write-ValidationSectionHeader -Title 'Changed Toolkit validation summary'
    Write-ValidationSummary -Fields ([ordered]@{
        Status = $result.status.ToUpperInvariant()
        Purpose = $result.purpose.ToUpperInvariant()
        Scope = $result.scope.ToUpperInvariant()
        'Changed Paths' = $result.changedPathCount
        'Required Validators' = $(if ($requiredValidators.Count -gt 0) { $requiredValidators -join ', ' } else { 'none' })
        'Repository Checks' = $(if ($runRepositoryChecks) { 'required' } else { 'not required' })
        'Interactive Changelog' = $interactiveChangelogStatus.ToUpperInvariant()
        'Hosted Changelog' = $hostedChangelogStatus.ToUpperInvariant()
    })

    if ($classification.Count -gt 0) {
        Write-ValidationSectionHeader -Title 'Classifications'
        Write-ValidationTwoColumnTable -Rows $classification.ToArray() -FirstHeader 'OWNERSHIP' -FirstProperty 'ownership' -SecondHeader 'PATH' -SecondProperty 'path' -UppercaseFirst
    }

    if ($executions.Count -gt 0) {
        Write-ValidationSectionHeader -Title 'Executions'
        Write-ValidationStatusTable -Rows $executions.ToArray() -NameHeader 'VALIDATOR' -NameWidth 24
    }

    if ($executionFailures.Count -gt 0) {
        Write-ValidationSectionHeader -Title 'Execution failures'
        foreach ($execution in $executionFailures) {
            Write-Output ("  {0}" -f (Format-ValidationStatusLine -Status $execution.status -Name $execution.name -Detail $execution.detail))
        }
    }

    if ($null -ne $repositoryExecution) {
        Write-ValidationSectionHeader -Title 'Repository checks'
        Write-Output ("  {0}" -f (Format-ValidationStatusLine -Status $repositoryExecution.status -Name $repositoryExecution.name -Detail $repositoryExecution.detail))
    }

    if ($changelogIssues.Count -gt 0) {
        Write-ValidationSectionHeader -Title 'Changelog issues'
        foreach ($issue in $changelogIssues) {
            Write-Output "  - $issue"
        }
    }

    Complete-ValidationTextOutput
}

if ($status -eq 'failed') {
    exit 1
}
