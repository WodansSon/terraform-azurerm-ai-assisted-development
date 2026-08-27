[CmdletBinding()]
param(
    [ValidateSet('Text', 'Json')]
    [string]$OutputFormat = 'Text'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))
$hostedRoot = Join-Path $repoRoot 'hosted_copilot'
$architecturePath = Join-Path $repoRoot 'docs/HOSTED_COPILOT_CODE_REVIEW_ARCHITECTURE.md'
$changelogPath = Join-Path $PSScriptRoot 'CHANGELOG.md'
$forbiddenVersionPath = Join-Path $PSScriptRoot 'VERSION'
$packageManifestPath = Join-Path $PSScriptRoot 'package-manifest.json'
$interactiveManifestPath = Join-Path $repoRoot 'installer/file-manifest.config'
$hostedRuntimePath = Join-Path $hostedRoot '.github'

$issues = New-Object 'System.Collections.Generic.List[string]'
$checks = New-Object 'System.Collections.Generic.List[object]'
$checkStartTimes = @{}

function Write-TextSectionHeader {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Title
    )

    $separator = '-' * 51

    Write-Output ''
    Write-Output $separator
    Write-Output $Title.ToUpperInvariant()
    Write-Output $separator
}

function Format-StatusLine {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Status,

        [Parameter(Mandatory = $true)]
        [string]$Name,

        [Parameter(Mandatory = $true)]
        [string]$Detail
    )

    $statusLabel = "[{0}]" -f $Status.ToUpperInvariant()

    return ("{0,-11}{1,-30}: {2}" -f $statusLabel, $Name, $Detail)
}

function Start-ValidationCheck {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name
    )

    $checkStartTimes[$Name] = Get-Date
    if ($OutputFormat -eq 'Text') {
        Write-Host (Format-StatusLine -Status 'running' -Name $Name -Detail 'IN PROGRESS')
    }
}

function Add-CheckResult {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name,

        [Parameter(Mandatory = $true)]
        [bool]$Passed,

        [Parameter(Mandatory = $true)]
        [string]$Detail
    )

    $durationSeconds = 0
    if ($checkStartTimes.ContainsKey($Name)) {
        $durationSeconds = [Math]::Round(((Get-Date) - $checkStartTimes[$Name]).TotalSeconds, 2)
        $checkStartTimes.Remove($Name)
    }

    $status = if ($Passed) { 'passed' } else { 'failed' }

    $checks.Add([pscustomobject]@{
        name = $Name
        status = $status
        success = $Passed
        durationSeconds = $durationSeconds
        detail = $Detail
    })

    if ($OutputFormat -eq 'Text') {
        Write-Host (Format-StatusLine -Status $status -Name $Name -Detail ("{0}s" -f $durationSeconds))
    }
}

function Add-SkippedCheck {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name,

        [Parameter(Mandatory = $true)]
        [string]$Detail
    )

    $checks.Add([pscustomobject]@{
        name = $Name
        status = 'skipped'
        success = $true
        durationSeconds = 0
        detail = $Detail
    })

    if ($OutputFormat -eq 'Text') {
        Write-Host (Format-StatusLine -Status 'skipped' -Name $Name -Detail 'NOT APPLICABLE')
    }
}

function Add-ValidationIssue {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name,

        [Parameter(Mandatory = $true)]
        [string]$Issue
    )

    $issues.Add($Issue)
    Add-CheckResult -Name $Name -Passed $false -Detail $Issue
}

$runtimeStarted = (Test-Path -LiteralPath $hostedRuntimePath) -or (Test-Path -LiteralPath $packageManifestPath)
$phase = if ($runtimeStarted) { 'runtime' } else { 'design' }
$purpose = 'experiment-support'
$deploymentModel = 'source-checkout'

if ($OutputFormat -eq 'Text') {
    Write-TextSectionHeader -Title 'Hosted toolkit validation'
    Write-Output ("  Purpose     : {0}" -f $purpose.ToUpperInvariant())
    Write-Output ("  Deployment  : {0}" -f $deploymentModel.ToUpperInvariant())
    Write-Output ("  Phase       : {0}" -f $phase.ToUpperInvariant())
    Write-Output ''
}

Start-ValidationCheck -Name 'architecture'
if (Test-Path -LiteralPath $architecturePath) {
    Add-CheckResult -Name 'architecture' -Passed $true -Detail 'Hosted Toolkit architecture document exists.'
}
else {
    Add-ValidationIssue -Name 'architecture' -Issue "Hosted Toolkit architecture document was not found at $architecturePath"
}

Start-ValidationCheck -Name 'changelog'
if (Test-Path -LiteralPath $changelogPath) {
    $changelogContent = Get-Content -LiteralPath $changelogPath -Raw
    $unreleasedMatch = [regex]::Match($changelogContent, '(?ms)^## \[Unreleased\]\s*(?<body>.*?)(?=^## \[|\z)')
    $requiredSections = @('Added', 'Changed', 'Fixed')
    $missingSections = @()

    if (-not $unreleasedMatch.Success) {
        $missingSections = $requiredSections
    }
    else {
        $unreleasedBody = $unreleasedMatch.Groups['body'].Value
        foreach ($section in $requiredSections) {
            if ($unreleasedBody -notmatch "(?m)^### $section\s*$") {
                $missingSections += $section
            }
        }
    }

    if ($missingSections.Count -eq 0) {
        Add-CheckResult -Name 'changelog' -Passed $true -Detail 'Hosted Toolkit changelog contains Unreleased Added, Changed, and Fixed sections.'
    }
    else {
        Add-ValidationIssue -Name 'changelog' -Issue ("Hosted Toolkit changelog is missing required Unreleased sections: {0}" -f ($missingSections -join ', '))
    }
}
else {
    Add-ValidationIssue -Name 'changelog' -Issue "Hosted Toolkit changelog was not found at $changelogPath"
}

Start-ValidationCheck -Name 'deployment-model'
if (Test-Path -LiteralPath $forbiddenVersionPath) {
    Add-ValidationIssue -Name 'deployment-model' -Issue 'Hosted Toolkit is deployed directly from this source repository and must not define tools/hosted-copilot/VERSION'
}
else {
    Add-CheckResult -Name 'deployment-model' -Passed $true -Detail 'Hosted Toolkit uses direct source deployment without a separate version file or release bundle.'
}

if (Test-Path -LiteralPath $packageManifestPath) {
    Start-ValidationCheck -Name 'package-manifest'
    try {
        $null = Get-Content -LiteralPath $packageManifestPath -Raw | ConvertFrom-Json
        Add-CheckResult -Name 'package-manifest' -Passed $true -Detail 'Hosted Toolkit package manifest is valid JSON.'
    }
    catch {
        Add-ValidationIssue -Name 'package-manifest' -Issue "Hosted Toolkit package manifest is not valid JSON: $($_.Exception.Message)"
    }
}
elseif ($runtimeStarted) {
    Start-ValidationCheck -Name 'package-manifest'
    Add-ValidationIssue -Name 'package-manifest' -Issue 'Hosted Toolkit runtime assets exist, but tools/hosted-copilot/package-manifest.json is missing'
}
else {
    Add-SkippedCheck -Name 'package-manifest' -Detail 'No package manifest is required during the design phase.'
}

Start-ValidationCheck -Name 'isolation'
if (Test-Path -LiteralPath $interactiveManifestPath) {
    $interactiveManifestReferences = @(Get-Content -LiteralPath $interactiveManifestPath | Where-Object { $_ -match 'hosted_copilot' })
    if ($interactiveManifestReferences.Count -eq 0) {
        Add-CheckResult -Name 'isolation' -Passed $true -Detail 'Interactive Toolkit manifest does not reference Hosted Toolkit paths.'
    }
    else {
        Add-ValidationIssue -Name 'isolation' -Issue 'Interactive Toolkit manifest must not include Hosted Toolkit paths'
    }
}
else {
    Add-ValidationIssue -Name 'isolation' -Issue "Interactive Toolkit manifest was not found at $interactiveManifestPath"
}

if (Test-Path -LiteralPath $architecturePath) {
    Start-ValidationCheck -Name 'architecture-style'
    $architectureLines = Get-Content -LiteralPath $architecturePath
    $badHeadings = @($architectureLines | Where-Object { $_ -cmatch '^#{1,6}\s+.*[^:]$' })
    $badBullets = @($architectureLines | Where-Object { $_ -cmatch '^\s*-\s+[a-z]' })
    $badLabels = @($architectureLines | Where-Object { $_ -cmatch '^[A-Za-z\[].*:$' })

    if ($badHeadings.Count -eq 0 -and $badBullets.Count -eq 0 -and $badLabels.Count -eq 0) {
        Add-CheckResult -Name 'architecture-style' -Passed $true -Detail 'Architecture headings, labels, and bullet capitalization follow repository conventions.'
    }
    else {
        Add-ValidationIssue -Name 'architecture-style' -Issue ("Architecture style issues: headings={0}, lowercase bullets={1}, unbolded labels={2}" -f $badHeadings.Count, $badBullets.Count, $badLabels.Count)
    }
}
else {
    Add-SkippedCheck -Name 'architecture-style' -Detail 'Architecture style validation requires the architecture document.'
}

$npxCommand = Get-Command 'npx.cmd' -ErrorAction SilentlyContinue
if ($null -eq $npxCommand) {
    $npxCommand = Get-Command 'npx' -ErrorAction SilentlyContinue
}

if ($null -eq $npxCommand) {
    Start-ValidationCheck -Name 'markdown'
    Add-ValidationIssue -Name 'markdown' -Issue 'npx was not found on PATH'
}
else {
    Start-ValidationCheck -Name 'markdown'
    Push-Location $repoRoot
    try {
        $global:LASTEXITCODE = 0
        $markdownOutput = @(& $npxCommand.Source -y --prefer-offline markdownlint-cli2 'hosted_copilot/**/*.md' 'docs/HOSTED_COPILOT_CODE_REVIEW_ARCHITECTURE.md' --config '.github/.markdownlint.json' 2>&1)
        $markdownExitCode = if ($null -ne $LASTEXITCODE) { $LASTEXITCODE } else { 0 }
    }
    finally {
        Pop-Location
    }

    if ($markdownExitCode -eq 0) {
        Add-CheckResult -Name 'markdown' -Passed $true -Detail 'Hosted Toolkit Markdown passed markdownlint.'
    }
    else {
        Add-ValidationIssue -Name 'markdown' -Issue ("Hosted Toolkit Markdown failed markdownlint: {0}" -f (($markdownOutput | Out-String).Trim()))
    }
}

$result = [ordered]@{
    status = if ($issues.Count -eq 0) { 'passed' } else { 'failed' }
    purpose = $purpose
    deploymentModel = $deploymentModel
    phase = $phase
    repoRoot = $repoRoot
    hostedRoot = $hostedRoot
    checks = @($checks.ToArray())
    issueCount = $issues.Count
    issues = @($issues.ToArray())
}

if ($OutputFormat -eq 'Json') {
    $result | ConvertTo-Json -Depth 10
}
else {
    Write-TextSectionHeader -Title 'Hosted toolkit validation summary'
    Write-Output ("  Status      : {0}" -f $result.status.ToUpperInvariant())
    Write-Output ("  Purpose     : {0}" -f $result.purpose.ToUpperInvariant())
    Write-Output ("  Deployment  : {0}" -f $result.deploymentModel.ToUpperInvariant())
    Write-Output ("  Phase       : {0}" -f $result.phase.ToUpperInvariant())
    Write-Output ("  Hosted Root : {0}" -f $result.hostedRoot)
    Write-Output ("  Issue Count : {0}" -f $result.issueCount)

    Write-TextSectionHeader -Title 'Validation checks'
    Write-Output ("  {0,-32} {1,-10} {2,10}" -f 'CHECK', 'STATUS', 'DURATION')
    Write-Output ("  {0,-32} {1,-10} {2,10}" -f ('-' * 32), ('-' * 10), ('-' * 10))
    foreach ($check in $checks) {
        Write-Output ("  {0,-32} {1,-10} {2,10}" -f $check.name, $check.status.ToUpperInvariant(), ("{0}s" -f $check.durationSeconds))
    }

    if ($issues.Count -gt 0) {
        Write-TextSectionHeader -Title 'Failures'
        foreach ($check in @($checks | Where-Object { -not $_.success })) {
            Write-Output ("  {0}" -f (Format-StatusLine -Status 'failed' -Name $check.name -Detail $check.detail))
        }
    }

    Write-Output ''
}

if ($issues.Count -gt 0) {
    exit 1
}
