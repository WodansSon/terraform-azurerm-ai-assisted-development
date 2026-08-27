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
$installerPath = Join-Path $PSScriptRoot 'Install-HostedCopilot.ps1'
$interactiveManifestPath = Join-Path $repoRoot 'installer/file-manifest.config'
$hostedRuntimePath = Join-Path $hostedRoot '.github'
$repositoryInstructionsPath = Join-Path $hostedRuntimePath 'copilot-instructions.md'
$documentationInstructionsPath = Join-Path $hostedRuntimePath 'instructions/azurerm-docs.instructions.md'
$reviewSkillPath = Join-Path $hostedRuntimePath 'skills/code-review/SKILL.md'
$userDocumentationPath = Join-Path $hostedRoot 'docs/HOSTED_COPILOT_CODE_REVIEW.md'
$documentationFixturePath = Join-Path $PSScriptRoot 'regression/fixtures/documentation-phase-one'
$tokenEstimator = 'utf8-byte-upper-bound-v1'

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

function Get-Sha256Hash {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function Get-Utf8ByteCount {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    return [System.Text.Encoding]::UTF8.GetByteCount((Get-Content -LiteralPath $Path -Raw))
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
    Write-Output ("  Token Guard : {0}" -f $tokenEstimator.ToUpperInvariant())
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

$manifestConfig = $null
if (Test-Path -LiteralPath $packageManifestPath) {
    Start-ValidationCheck -Name 'package-manifest'
    try {
        $manifestConfig = Get-Content -LiteralPath $packageManifestPath -Raw | ConvertFrom-Json
        if ($manifestConfig.schemaVersion -ne 1) {
            throw "unsupported schemaVersion $($manifestConfig.schemaVersion)"
        }
        if ([string]::IsNullOrWhiteSpace([string]$manifestConfig.packageIdentity)) {
            throw 'packageIdentity is empty'
        }
        if ([string]::IsNullOrWhiteSpace([string]$manifestConfig.installedStatePath)) {
            throw 'installedStatePath is empty'
        }
        if (@($manifestConfig.files).Count -eq 0) {
            throw 'files is empty'
        }
        Add-CheckResult -Name 'package-manifest' -Passed $true -Detail 'Hosted Toolkit package manifest schema is valid.'
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

if ($runtimeStarted) {
    Start-ValidationCheck -Name 'runtime-layout'
    $requiredRuntimePaths = @(
        $repositoryInstructionsPath,
        $documentationInstructionsPath,
        $reviewSkillPath,
        $userDocumentationPath,
        $installerPath
    )
    $missingRuntimePaths = @($requiredRuntimePaths | Where-Object { -not (Test-Path -LiteralPath $_ -PathType Leaf) })
    if ($missingRuntimePaths.Count -eq 0) {
        Add-CheckResult -Name 'runtime-layout' -Passed $true -Detail 'Phase One runtime, installer, and user documentation paths exist.'
    }
    else {
        Add-ValidationIssue -Name 'runtime-layout' -Issue ("Required Phase One paths are missing: {0}" -f ($missingRuntimePaths -join ', '))
    }

    Start-ValidationCheck -Name 'instruction-frontmatter'
    if (Test-Path -LiteralPath $documentationInstructionsPath -PathType Leaf) {
        $instructionContent = Get-Content -LiteralPath $documentationInstructionsPath -Raw
        $frontmatterValid = $instructionContent -match '(?s)\A---\r?\n(?<frontmatter>.*?)\r?\n---\r?\n'
        if ($frontmatterValid) {
            $frontmatter = $matches['frontmatter']
            $frontmatterValid = $frontmatter -match '(?m)^description:\s*".+"\s*$' -and $frontmatter -match '(?m)^applyTo:\s*"website/docs/\*\*/\*.html\.markdown"\s*$'
        }
        if ($frontmatterValid) {
            Add-CheckResult -Name 'instruction-frontmatter' -Passed $true -Detail 'Documentation instructions use the exact Phase One applyTo pattern and a description.'
        }
        else {
            Add-ValidationIssue -Name 'instruction-frontmatter' -Issue 'Documentation instruction frontmatter is invalid or does not use applyTo "website/docs/**/*.html.markdown"'
        }
    }
    else {
        Add-ValidationIssue -Name 'instruction-frontmatter' -Issue "Documentation instructions were not found at $documentationInstructionsPath"
    }

    Start-ValidationCheck -Name 'skill-metadata'
    if (Test-Path -LiteralPath $reviewSkillPath -PathType Leaf) {
        $skillContent = Get-Content -LiteralPath $reviewSkillPath -Raw
        $skillMetadataValid = $skillContent -match '(?s)\A---\r?\n(?<frontmatter>.*?)\r?\n---\r?\n'
        if ($skillMetadataValid) {
            $skillFrontmatter = $matches['frontmatter']
            $skillMetadataValid = $skillFrontmatter -match '(?m)^name:\s*code-review\s*$' -and $skillFrontmatter -match '(?m)^description:\s*".*review.*"\s*$'
        }
        if ($skillMetadataValid) {
            Add-CheckResult -Name 'skill-metadata' -Passed $true -Detail 'Review skill metadata has the required name and review-focused description.'
        }
        else {
            Add-ValidationIssue -Name 'skill-metadata' -Issue 'Review skill metadata must define name code-review and a review-focused description'
        }
    }
    else {
        Add-ValidationIssue -Name 'skill-metadata' -Issue "Review skill was not found at $reviewSkillPath"
    }

    if ($null -ne $manifestConfig) {
        Start-ValidationCheck -Name 'manifest-coverage'
        $requiredOwnedPaths = @(
            '.github/copilot-instructions.md',
            '.github/instructions/azurerm-docs.instructions.md',
            '.github/skills/code-review/SKILL.md',
            'docs/HOSTED_COPILOT_CODE_REVIEW.md'
        )
        $manifestSourcePaths = @($manifestConfig.files | ForEach-Object { ([string]$_.sourcePath).Replace('\', '/') })
        $manifestTargetPaths = @($manifestConfig.files | ForEach-Object { ([string]$_.targetPath).Replace('\', '/') })
        $missingOwnedPaths = @($requiredOwnedPaths | Where-Object { $_ -notin $manifestSourcePaths -or $_ -notin $manifestTargetPaths })
        $unexpectedOwnedPaths = @($manifestSourcePaths | Where-Object { $_ -notin $requiredOwnedPaths })
        $duplicateTargets = @($manifestTargetPaths | Group-Object | Where-Object Count -gt 1)
        if ($missingOwnedPaths.Count -eq 0 -and $unexpectedOwnedPaths.Count -eq 0 -and $duplicateTargets.Count -eq 0) {
            Add-CheckResult -Name 'manifest-coverage' -Passed $true -Detail 'Manifest owns exactly the four Phase One deployable files.'
        }
        else {
            Add-ValidationIssue -Name 'manifest-coverage' -Issue ("Manifest coverage mismatch: missing={0}; unexpected={1}; duplicateTargets={2}" -f ($missingOwnedPaths -join ', '), ($unexpectedOwnedPaths -join ', '), $duplicateTargets.Count)
        }

        Start-ValidationCheck -Name 'manifest-hashes'
        $hashIssues = New-Object 'System.Collections.Generic.List[string]'
        foreach ($file in @($manifestConfig.files)) {
            $sourceRelativePath = ([string]$file.sourcePath).Replace('/', [System.IO.Path]::DirectorySeparatorChar)
            $sourcePath = [System.IO.Path]::GetFullPath((Join-Path $hostedRoot $sourceRelativePath))
            $hostedPrefix = $hostedRoot.TrimEnd([System.IO.Path]::DirectorySeparatorChar) + [System.IO.Path]::DirectorySeparatorChar
            if (-not $sourcePath.StartsWith($hostedPrefix, [System.StringComparison]::OrdinalIgnoreCase)) {
                $hashIssues.Add("sourcePath escapes hosted_copilot: $($file.sourcePath)")
                continue
            }
            if (-not (Test-Path -LiteralPath $sourcePath -PathType Leaf)) {
                $hashIssues.Add("sourcePath is missing: $($file.sourcePath)")
                continue
            }
            $actualHash = Get-Sha256Hash -Path $sourcePath
            if ($actualHash -ne ([string]$file.hash).ToLowerInvariant()) {
                $hashIssues.Add("hash mismatch: $($file.sourcePath)")
            }
        }
        if ($hashIssues.Count -eq 0) {
            Add-CheckResult -Name 'manifest-hashes' -Passed $true -Detail 'Every manifest hash matches its Hosted source file.'
        }
        else {
            Add-ValidationIssue -Name 'manifest-hashes' -Issue ($hashIssues -join '; ')
        }
    }
    else {
        Add-SkippedCheck -Name 'manifest-coverage' -Detail 'Manifest coverage requires a valid package manifest.'
        Add-SkippedCheck -Name 'manifest-hashes' -Detail 'Manifest hash validation requires a valid package manifest.'
    }

    Start-ValidationCheck -Name 'guidance-budgets'
    if ((Test-Path -LiteralPath $repositoryInstructionsPath) -and (Test-Path -LiteralPath $documentationInstructionsPath) -and (Test-Path -LiteralPath $reviewSkillPath)) {
        $repositoryBytes = Get-Utf8ByteCount -Path $repositoryInstructionsPath
        $documentationBytes = Get-Utf8ByteCount -Path $documentationInstructionsPath
        $skillBytes = Get-Utf8ByteCount -Path $reviewSkillPath
        $combinedBytes = $repositoryBytes + $documentationBytes + $skillBytes
        $budgetPassed = $repositoryBytes -le 2000 -and $documentationBytes -le 8000 -and $skillBytes -le 3000 -and $combinedBytes -le 25000
        $budgetDetail = "$tokenEstimator bytes: repository=$repositoryBytes/2000; documentation=$documentationBytes/8000; skill=$skillBytes/3000; combined=$combinedBytes/25000"
        if ($budgetPassed) {
            Add-CheckResult -Name 'guidance-budgets' -Passed $true -Detail $budgetDetail
        }
        else {
            Add-ValidationIssue -Name 'guidance-budgets' -Issue "Hosted guidance exceeds its conservative budget: $budgetDetail"
        }
    }
    else {
        Add-ValidationIssue -Name 'guidance-budgets' -Issue 'Hosted guidance budgets require all Phase One runtime guidance files'
    }

    Start-ValidationCheck -Name 'installer-dry-run'
    if ((Test-Path -LiteralPath $installerPath -PathType Leaf) -and $null -ne $manifestConfig) {
        $tempRepo = Join-Path ([System.IO.Path]::GetTempPath()) ("hosted-toolkit-validation-" + [guid]::NewGuid().ToString('N'))
        try {
            $null = New-Item -ItemType Directory -Path $tempRepo
            $gitCommand = Get-Command git -ErrorAction SilentlyContinue
            if ($null -eq $gitCommand) {
                throw 'git was not found on PATH'
            }
            & $gitCommand.Source -C $tempRepo init --quiet
            if ($LASTEXITCODE -ne 0) {
                throw 'temporary Git repository initialization failed'
            }
            $dryRunOutput = @(& pwsh -NoProfile -File $installerPath -RepoDirectory $tempRepo -OutputFormat Json 2>&1)
            if ($LASTEXITCODE -ne 0) {
                throw (($dryRunOutput | Out-String).Trim())
            }
            $dryRunResult = ($dryRunOutput | Out-String) | ConvertFrom-Json
            if (-not $dryRunResult.success -or $dryRunResult.mode -ne 'dry-run') {
                throw 'installer did not report a successful dry run'
            }
            if (@(Get-ChildItem -LiteralPath $tempRepo -Force | Where-Object Name -ne '.git').Count -ne 0) {
                throw 'installer dry run wrote files to the target repository'
            }
            Add-CheckResult -Name 'installer-dry-run' -Passed $true -Detail 'Installer dry run planned Phase One additions without writing to a temporary target.'
        }
        catch {
            Add-ValidationIssue -Name 'installer-dry-run' -Issue "Hosted installer dry run failed: $($_.Exception.Message)"
        }
        finally {
            if (Test-Path -LiteralPath $tempRepo) {
                Remove-Item -LiteralPath $tempRepo -Recurse -Force
            }
            $global:LASTEXITCODE = 0
        }
    }
    else {
        Add-ValidationIssue -Name 'installer-dry-run' -Issue 'Installer dry-run validation requires the installer and a valid package manifest'
    }

    Start-ValidationCheck -Name 'documentation-fixture'
    $fixtureConfigPath = Join-Path $documentationFixturePath 'fixture.json'
    try {
        $fixtureConfig = Get-Content -LiteralPath $fixtureConfigPath -Raw | ConvertFrom-Json
        $beforePath = Join-Path $documentationFixturePath ([string]$fixtureConfig.beforePath)
        $afterPath = Join-Path $documentationFixturePath ([string]$fixtureConfig.afterPath)
        $expectedRuleIds = @($fixtureConfig.expectedFindings | ForEach-Object { [string]$_.ruleId })
        $documentationRuleContent = Get-Content -LiteralPath $documentationInstructionsPath -Raw
        if ($fixtureConfig.schemaVersion -ne 1 -or $fixtureConfig.surface -ne 'documentation') {
            throw 'fixture schemaVersion or surface is invalid'
        }
        if (-not (Test-Path -LiteralPath $beforePath) -or -not (Test-Path -LiteralPath $afterPath)) {
            throw 'fixture beforePath or afterPath is missing'
        }
        if ($expectedRuleIds.Count -eq 0) {
            throw 'fixture expectedFindings is empty'
        }
        foreach ($ruleId in $expectedRuleIds) {
            if ($documentationRuleContent -notmatch [regex]::Escape("[$ruleId]")) {
                throw "fixture references unknown Hosted documentation rule $ruleId"
            }
        }
        Add-CheckResult -Name 'documentation-fixture' -Passed $true -Detail "Controlled documentation fixture defines $($expectedRuleIds.Count) expected findings backed by Hosted rule IDs."
    }
    catch {
        Add-ValidationIssue -Name 'documentation-fixture' -Issue "Controlled documentation fixture is invalid: $($_.Exception.Message)"
    }
}
else {
    foreach ($runtimeCheck in @('runtime-layout', 'instruction-frontmatter', 'skill-metadata', 'manifest-coverage', 'manifest-hashes', 'guidance-budgets', 'installer-dry-run', 'documentation-fixture')) {
        Add-SkippedCheck -Name $runtimeCheck -Detail 'Runtime validation is not applicable during the design phase.'
    }
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
    tokenEstimator = $tokenEstimator
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
    Write-Output ("  Token Guard : {0}" -f $result.tokenEstimator.ToUpperInvariant())
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
