[CmdletBinding()]
param(
    [string]$RepositoryRoot = (Join-Path $PSScriptRoot '..'),

    [string[]]$LockPath = @(),

    [string[]]$AdditionalLockPath = @(),

    [switch]$Fix,

    [switch]$AllowBreakingFix,

    [ValidateSet('Text', 'Json')]
    [string]$OutputFormat = 'Text'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Import-Module (Join-Path $PSScriptRoot 'ValidationOutput.psm1') -Force
$suiteStopwatch = [Diagnostics.Stopwatch]::StartNew()
$validationRows = [Collections.Generic.List[object]]::new()

$resolvedRepositoryRoot = [IO.Path]::GetFullPath($RepositoryRoot)
$repositoryPrefix = $resolvedRepositoryRoot.TrimEnd([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar) + [IO.Path]::DirectorySeparatorChar
$npmCommandName = if ($IsWindows) { 'npm.cmd' } else { 'npm' }
$npmCommand = Get-Command $npmCommandName -ErrorAction SilentlyContinue
$gitCommand = Get-Command git -ErrorAction SilentlyContinue

if ($null -eq $npmCommand) {
    throw 'npm was not found on PATH'
}
if ($null -eq $gitCommand) {
    throw 'git was not found on PATH'
}
if ($AllowBreakingFix -and -not $Fix) {
    throw 'AllowBreakingFix requires Fix'
}
if ($PSBoundParameters.ContainsKey('LockPath') -and $AdditionalLockPath.Count -gt 0) {
    throw 'LockPath cannot be combined with AdditionalLockPath'
}

function Add-NpmValidationResult {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][bool]$Passed,
        [Parameter(Mandatory = $true)][Diagnostics.Stopwatch]$Stopwatch,
        [AllowNull()][object]$Report,
        [string]$Failure
    )

    $Stopwatch.Stop()
    $status = if ($Passed) { 'passed' } else { 'failed' }
    $validationRows.Add([pscustomobject]@{ name = $Name; status = $status; durationSeconds = $Stopwatch.Elapsed.TotalSeconds })
    if ($OutputFormat -eq 'Text') {
        if ($null -ne $Report) {
            $counts = $Report.counts
            Write-Host (Format-ValidationStatusLine -Status $Report.securityStatus -Name 'security audit' -Detail "critical=$($counts.critical), high=$($counts.high), moderate=$($counts.moderate), low=$($counts.low)" -IndentLevel 1)
            $diagnosticDetail = if ($Report.diagnosticsStatus -ceq 'passed') { 'No stderr diagnostics' } else { $Report.diagnostics }
            Write-Host (Format-ValidationStatusLine -Status $Report.diagnosticsStatus -Name 'npm diagnostics' -Detail $diagnosticDetail -IndentLevel 1)
        }
        $detail = if ($Passed) { Format-ValidationDuration -DurationSeconds $Stopwatch.Elapsed.TotalSeconds } else { $Failure }
        Write-Host (Format-ValidationStatusLine -Status $status -Name $Name -Detail $detail -NameWidth $npmValidationNameWidth)
    }
}

function Resolve-RepositoryPath {
    param([Parameter(Mandatory = $true)][string]$Path)

    $resolvedPath = [IO.Path]::GetFullPath((Join-Path $resolvedRepositoryRoot $Path))
    if (-not $resolvedPath.StartsWith($repositoryPrefix, [StringComparison]::OrdinalIgnoreCase)) {
        throw "npm lockfile path escapes the repository root: $Path"
    }
    return $resolvedPath
}

function Protect-NpmDiagnostic {
    param([AllowEmptyString()][string]$Text)

    $safe = [regex]::Replace($Text, '(?s)-----BEGIN [A-Z ]*PRIVATE KEY-----.*?-----END [A-Z ]*PRIVATE KEY-----', '[REDACTED PRIVATE KEY]')
    $safe = [regex]::Replace($safe, '(?i)\b(?:Bearer|Basic)\s+[^\s,;]+', '[REDACTED AUTHORIZATION]')
    $safe = [regex]::Replace($safe, '(?i)\b((?:[A-Za-z_-]*token|password|passwd|secret|api[_-]?key|authorization|accountkey|sharedaccesssignature)\s*[:=]\s*)(?:"[^"]*"|''[^'']*''|[^\s,;]+)', '$1[REDACTED]')
    $safe = [regex]::Replace($safe, '(?i)https?://[^\s<>"'']+', [Text.RegularExpressions.MatchEvaluator]{
        param($match)
        $uri = $null
        if ([Uri]::TryCreate($match.Value, [UriKind]::Absolute, [ref]$uri) -and ($uri.UserInfo -or $uri.Query -or $uri.Fragment)) { return '[REDACTED URL]' }
        return $match.Value
    })
    return $safe.Trim()
}

function Invoke-NpmCommand {
    param([Parameter(Mandatory = $true)][string[]]$Arguments)

    $worker = [Management.Automation.PowerShell]::Create()
    try {
        $null = $worker.AddScript({
            param($CommandPath, $CommandArguments)
            $PSNativeCommandUseErrorActionPreference = $false
            $output = @(& $CommandPath @CommandArguments)
            [pscustomobject]@{ exitCode = $LASTEXITCODE; stdout = ($output | Out-String).Trim() }
        }).AddArgument($npmCommand.Source).AddArgument($Arguments)
        $results = @($worker.Invoke())
        if ($results.Count -ne 1 -or $null -eq $results[0].exitCode) { throw 'npm execution did not return an exit code and output' }
        return [pscustomobject]@{
            exitCode = $results[0].exitCode
            stdout = $results[0].stdout
            stderr = Protect-NpmDiagnostic -Text (($worker.Streams.Error | ForEach-Object { $_.ToString() }) -join "`n")
        }
    } finally { $worker.Dispose() }
}

function ConvertFrom-NpmAuditOutput {
    param([Parameter(Mandatory = $true)][object]$CommandResult)

    $report = try { $CommandResult.stdout | ConvertFrom-Json -ErrorAction Stop } catch { $null }
    return [pscustomobject]@{
        exitCode = $CommandResult.exitCode
        report = $report
        stderr = $CommandResult.stderr
    }
}

function Assert-NpmNoDiagnostics {
    param([Parameter(Mandatory = $true)][object]$CommandResult)

    if (-not [string]::IsNullOrWhiteSpace($CommandResult.stderr)) {
        throw "npm diagnostics must be resolved: $($CommandResult.stderr)"
    }
}

function Invoke-NpmAudit {
    param([Parameter(Mandatory = $true)][string]$PackageDirectory)

    $result = Invoke-NpmCommand -Arguments @('audit', '--prefix', $PackageDirectory, '--package-lock-only', '--ignore-scripts', '--audit-level=low', '--json')
    return ConvertFrom-NpmAuditOutput -CommandResult $result
}

function Get-NpmFindings {
    param([AllowNull()][object]$Audit)

    if ($null -eq $Audit -or $null -eq $Audit.metadata -or $null -eq $Audit.metadata.vulnerabilities -or $null -eq $Audit.vulnerabilities) {
        throw 'npm audit did not return a complete vulnerability report'
    }

    return @($Audit.vulnerabilities.PSObject.Properties | Where-Object { $_.Value.severity -in @('low', 'moderate', 'high', 'critical') } | Sort-Object Name)
}

function ConvertTo-NpmFindingReport {
    param([Parameter(Mandatory = $true)][object]$Finding)

    $packageName = [string]$Finding.Name
    $vulnerability = $Finding.Value
    $advisories = @($vulnerability.via | ForEach-Object {
        if ($_ -is [string]) {
            "Affected through $_"
        }
        elseif (-not [string]::IsNullOrWhiteSpace([string]$_.title)) {
            [string]$_.title
        }
        else {
            "Affected through $([string]$_.name)"
        }
    })
    $dependencyPath = if ($vulnerability.isDirect) {
        'Direct dependency'
    }
    elseif (@($vulnerability.effects).Count -gt 0) {
        "Required by $(@($vulnerability.effects) -join ', ')"
    }
    else {
        'Transitive dependency'
    }
    $remediation = if ($vulnerability.fixAvailable -is [bool]) {
        if ($vulnerability.fixAvailable) { 'A compatible fix is available' } else { 'No compatible fix is reported' }
    }
    else {
        "Set $($vulnerability.fixAvailable.name) to $($vulnerability.fixAvailable.version)"
    }

    return [ordered]@{
        package = $packageName
        severity = ([string]$vulnerability.severity).ToUpperInvariant()
        advisory = $advisories -join '; '
        affectedRange = [string]$vulnerability.range
        dependencyPath = $dependencyPath
        remediation = $remediation
    }
}

function Invoke-NpmRemediation {
    param(
        [Parameter(Mandatory = $true)][string]$ManifestPath,
        [Parameter(Mandatory = $true)][string]$LockPath,
        [switch]$AllowBreaking
    )

    $relativeManifestPath = [IO.Path]::GetRelativePath($resolvedRepositoryRoot, $ManifestPath).Replace('\', '/')
    $relativeLockPath = [IO.Path]::GetRelativePath($resolvedRepositoryRoot, $LockPath).Replace('\', '/')
    $gitStatus = @(& $gitCommand.Source -C $resolvedRepositoryRoot status --short -- $relativeManifestPath $relativeLockPath)
    if ($LASTEXITCODE -ne 0) {
        throw "git could not inspect npm manifests for remediation: $relativeLockPath"
    }
    if ($gitStatus.Count -gt 0) {
        throw "npm remediation requires clean tracked manifests: $relativeLockPath"
    }

    $stagingRoot = Join-Path ([IO.Path]::GetTempPath()) ("npm-security-fix-{0}" -f [Guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $stagingRoot -Force | Out-Null
    try {
        Copy-Item -LiteralPath $ManifestPath, $LockPath -Destination $stagingRoot
        $stagedManifestPath = Join-Path $stagingRoot 'package.json'
        $stagedLockPath = Join-Path $stagingRoot 'package-lock.json'
        $originalManifest = Get-Content -LiteralPath $stagedManifestPath -Raw | ConvertFrom-Json -AsHashtable -ErrorAction Stop

        $fixResult = Invoke-NpmCommand -Arguments @('audit', 'fix', '--prefix', $stagingRoot, '--package-lock-only', '--ignore-scripts', '--no-fund', '--json')
        Assert-NpmNoDiagnostics $fixResult
        $auditResult = Invoke-NpmAudit -PackageDirectory $stagingRoot
        Assert-NpmNoDiagnostics $auditResult
        $findings = @(Get-NpmFindings -Audit $auditResult.report)

        if ($findings.Count -gt 0) {
            $stagedManifest = Get-Content -LiteralPath $stagedManifestPath -Raw | ConvertFrom-Json -AsHashtable -ErrorAction Stop
            $stagedLock = Get-Content -LiteralPath $stagedLockPath -Raw | ConvertFrom-Json -AsHashtable -ErrorAction Stop
            if (-not $stagedManifest.ContainsKey('overrides')) {
                $stagedManifest['overrides'] = [ordered]@{}
            }

            $overrideAdded = $false
            foreach ($finding in @($findings | Where-Object { -not $_.Value.isDirect })) {
                $packageName = [string]$finding.Name
                $lockedPackage = $stagedLock['packages']["node_modules/$packageName"]
                if ($null -eq $lockedPackage) {
                    continue
                }

                $latestOutput = Invoke-NpmCommand -Arguments @('view', $packageName, 'version', '--json')
                Assert-NpmNoDiagnostics $latestOutput
                if ($latestOutput.exitCode -ne 0) {
                    continue
                }
                $latestVersion = try { [string]($latestOutput.stdout | ConvertFrom-Json -ErrorAction Stop) } catch { '' }
                $currentVersion = [string]$lockedPackage['version']
                $currentSemanticVersion = try { [Management.Automation.SemanticVersion]$currentVersion } catch { $null }
                $latestSemanticVersion = try { [Management.Automation.SemanticVersion]$latestVersion } catch { $null }
                if ($null -eq $currentSemanticVersion -or $null -eq $latestSemanticVersion -or $latestSemanticVersion.Major -ne $currentSemanticVersion.Major -or $latestSemanticVersion -le $currentSemanticVersion) {
                    continue
                }

                $stagedManifest['overrides'][$packageName] = $latestVersion
                $overrideAdded = $true
            }

            if ($overrideAdded) {
                [IO.File]::WriteAllText($stagedManifestPath, (($stagedManifest | ConvertTo-Json -Depth 20) + "`n"), [Text.UTF8Encoding]::new($false))
                $installResult = Invoke-NpmCommand -Arguments @('install', '--prefix', $stagingRoot, '--package-lock-only', '--ignore-scripts', '--no-audit', '--no-fund')
                Assert-NpmNoDiagnostics $installResult
                if ($installResult.exitCode -ne 0) {
                    throw 'npm could not regenerate the staged lockfile after adding transitive overrides'
                }
                $auditResult = Invoke-NpmAudit -PackageDirectory $stagingRoot
                Assert-NpmNoDiagnostics $auditResult
                $findings = @(Get-NpmFindings -Audit $auditResult.report)
            }
        }

        $requiresBreakingFix = @($findings | Where-Object { $null -ne $_.Value.fixAvailable -and $_.Value.fixAvailable -isnot [bool] -and $_.Value.fixAvailable.isSemVerMajor }).Count -gt 0
        if ($findings.Count -gt 0 -and $requiresBreakingFix -and $AllowBreaking) {
            $fixResult = Invoke-NpmCommand -Arguments @('audit', 'fix', '--prefix', $stagingRoot, '--package-lock-only', '--ignore-scripts', '--force', '--no-fund', '--json')
            Assert-NpmNoDiagnostics $fixResult
            $auditResult = Invoke-NpmAudit -PackageDirectory $stagingRoot
            Assert-NpmNoDiagnostics $auditResult
            $findings = @(Get-NpmFindings -Audit $auditResult.report)
        }
        if ($auditResult.exitCode -ne 0 -or $findings.Count -gt 0) {
            return [pscustomobject]@{ passed = $false; requiresBreakingFix = $requiresBreakingFix; changes = @() }
        }

        $updatedManifest = Get-Content -LiteralPath $stagedManifestPath -Raw | ConvertFrom-Json -AsHashtable -ErrorAction Stop
        $changes = New-Object 'System.Collections.Generic.List[string]'
        foreach ($dependencyGroup in @('dependencies', 'devDependencies', 'optionalDependencies')) {
            if (-not $updatedManifest.ContainsKey($dependencyGroup)) {
                continue
            }
            foreach ($dependency in @($updatedManifest[$dependencyGroup].GetEnumerator() | Sort-Object Key)) {
                $previous = if ($originalManifest.ContainsKey($dependencyGroup) -and $originalManifest[$dependencyGroup].ContainsKey($dependency.Key)) { [string]$originalManifest[$dependencyGroup][$dependency.Key] } else { '' }
                if ($previous -ne [string]$dependency.Value) {
                    $changes.Add("$dependencyGroup $($dependency.Key): $(if ($previous) { $previous } else { '<none>' }) -> $($dependency.Value)")
                }
            }
        }
        $updatedOverrides = if ($updatedManifest.ContainsKey('overrides')) { @($updatedManifest['overrides'].GetEnumerator() | Sort-Object Key) } else { @() }
        foreach ($override in $updatedOverrides) {
            $previous = if ($originalManifest.ContainsKey('overrides') -and $originalManifest['overrides'].ContainsKey($override.Key)) { [string]$originalManifest['overrides'][$override.Key] } else { '' }
            if ($previous -ne [string]$override.Value) {
                $changes.Add("override $($override.Key): $(if ($previous) { $previous } else { '<none>' }) -> $($override.Value)")
            }
        }

        $manifestBytes = [IO.File]::ReadAllBytes($ManifestPath)
        $lockBytes = [IO.File]::ReadAllBytes($LockPath)
        try {
            Copy-Item -LiteralPath $stagedManifestPath -Destination $ManifestPath -Force
            Copy-Item -LiteralPath $stagedLockPath -Destination $LockPath -Force
        }
        catch {
            [IO.File]::WriteAllBytes($ManifestPath, $manifestBytes)
            [IO.File]::WriteAllBytes($LockPath, $lockBytes)
            throw
        }
        return [pscustomobject]@{ passed = $true; requiresBreakingFix = $false; changes = $changes.ToArray() }
    }
    finally {
        Remove-Item -LiteralPath $stagingRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}

$candidateLockPaths = @($LockPath)
if (-not $PSBoundParameters.ContainsKey('LockPath')) {
    $trackedLockPaths = @(& $gitCommand.Source -C $resolvedRepositoryRoot ls-files -- 'package-lock.json' '**/package-lock.json')
    if ($LASTEXITCODE -ne 0) {
        throw 'git could not enumerate tracked npm lockfiles'
    }
    $candidateLockPaths = @($trackedLockPaths) + @($AdditionalLockPath)
}

$lockPaths = New-Object 'System.Collections.Generic.List[string]'
foreach ($path in $candidateLockPaths) {
    if ([string]::IsNullOrWhiteSpace([string]$path)) {
        continue
    }
    $resolvedPath = Resolve-RepositoryPath -Path ([string]$path)
    if (-not $lockPaths.Contains($resolvedPath)) {
        $lockPaths.Add($resolvedPath)
    }
}

$reports = New-Object 'System.Collections.Generic.List[object]'
$failures = New-Object 'System.Collections.Generic.List[string]'
$npmValidationNameWidth = Get-ValidationNameWidth -Names @($lockPaths | ForEach-Object { [IO.Path]::GetRelativePath($resolvedRepositoryRoot, $_).Replace('\', '/') }) -MinimumWidth 30
if ($OutputFormat -eq 'Text') { Write-ValidationSectionHeader -Title 'npm security validation' }
foreach ($resolvedLockPath in @($lockPaths | Sort-Object)) {
    $relativeLockPath = [IO.Path]::GetRelativePath($resolvedRepositoryRoot, $resolvedLockPath).Replace('\', '/')
    $checkStopwatch = [Diagnostics.Stopwatch]::StartNew()
    $failureCountBefore = $failures.Count
    $currentReport = $null
    if ($OutputFormat -eq 'Text') { Write-Host (Format-ValidationStatusLine -Status 'running' -Name $relativeLockPath -Detail 'IN PROGRESS' -NameWidth $npmValidationNameWidth) }
    $packageDirectory = Split-Path -Parent $resolvedLockPath
    $manifestPath = Join-Path $packageDirectory 'package.json'
    if (-not (Test-Path -LiteralPath $resolvedLockPath -PathType Leaf)) {
        $failures.Add("npm lockfile was not found: $relativeLockPath")
        Add-NpmValidationResult -Name $relativeLockPath -Passed $false -Stopwatch $checkStopwatch -Failure $failures[$failures.Count - 1]
        continue
    }
    if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) {
        $failures.Add("npm lockfile does not have a package.json peer: $relativeLockPath")
        Add-NpmValidationResult -Name $relativeLockPath -Passed $false -Stopwatch $checkStopwatch -Failure $failures[$failures.Count - 1]
        continue
    }

    try {
        $manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json -ErrorAction Stop
        $lock = Get-Content -LiteralPath $resolvedLockPath -Raw | ConvertFrom-Json -AsHashtable -ErrorAction Stop
        if ($manifest.private -ne $true) {
            throw 'package.json must set private to true'
        }
        if ($lock['lockfileVersion'] -lt 2 -or $null -eq $lock['packages']) {
            throw 'package-lock.json must use the npm integrity-lock format'
        }
        $rootPackage = $lock['packages']['']
        foreach ($dependencyGroup in @('dependencies', 'devDependencies', 'optionalDependencies')) {
            if ($null -eq $manifest.PSObject.Properties[$dependencyGroup]) {
                continue
            }
            foreach ($dependency in @($manifest.$dependencyGroup.PSObject.Properties)) {
                $lockedVersion = [string]$rootPackage[$dependencyGroup][$dependency.Name]
                $lockedPackage = $lock['packages']["node_modules/$($dependency.Name)"]
                if ($lockedVersion -ne [string]$dependency.Value -or $null -eq $lockedPackage -or [string]::IsNullOrWhiteSpace([string]$lockedPackage['integrity'])) {
                    throw "dependency $($dependency.Name) is not covered by the npm integrity lock"
                }
            }
        }

        $hashesBefore = @($manifestPath, $resolvedLockPath) | ForEach-Object { (Get-FileHash -LiteralPath $_ -Algorithm SHA256).Hash }
        $auditResult = Invoke-NpmAudit -PackageDirectory $packageDirectory
        $auditExitCode = $auditResult.exitCode
        $hashesAfter = @($manifestPath, $resolvedLockPath) | ForEach-Object { (Get-FileHash -LiteralPath $_ -Algorithm SHA256).Hash }
        if (Compare-Object -ReferenceObject $hashesBefore -DifferenceObject $hashesAfter) {
            throw 'npm audit modified package.json or package-lock.json'
        }

        $audit = $auditResult.report
        $findingProperties = @(Get-NpmFindings -Audit $audit)

        $findings = @($findingProperties | ForEach-Object { ConvertTo-NpmFindingReport -Finding $_ })
        $securityPassed = $findings.Count -eq 0
        $diagnosticsPassed = [string]::IsNullOrWhiteSpace($auditResult.stderr)
        $passed = $auditExitCode -eq 0 -and $securityPassed -and $diagnosticsPassed
        $remediation = $null
        if (-not $securityPassed -and $diagnosticsPassed -and $Fix) {
            $remediation = Invoke-NpmRemediation -ManifestPath $manifestPath -LockPath $resolvedLockPath -AllowBreaking:$AllowBreakingFix
            if ($remediation.passed) {
                $auditResult = Invoke-NpmAudit -PackageDirectory $packageDirectory
                $audit = $auditResult.report
                $findingProperties = @(Get-NpmFindings -Audit $audit)
                $findings = @($findingProperties | ForEach-Object { ConvertTo-NpmFindingReport -Finding $_ })
                $auditExitCode = $auditResult.exitCode
                $securityPassed = $findings.Count -eq 0
                $diagnosticsPassed = [string]::IsNullOrWhiteSpace($auditResult.stderr)
                $passed = $auditExitCode -eq 0 -and $securityPassed -and $diagnosticsPassed
            }
        }
        if (-not $securityPassed) {
            $failures.Add("$relativeLockPath contains $($findings.Count) npm vulnerabilities")
        }
        if ($auditExitCode -ne 0 -and $securityPassed) {
            $failures.Add("$relativeLockPath`: npm audit exited with code $auditExitCode")
        }
        if (-not $diagnosticsPassed) {
            $failures.Add("$relativeLockPath`: npm diagnostics must be resolved: $($auditResult.stderr)")
        }
        $currentReport = [ordered]@{
            lockPath = $relativeLockPath
            status = if ($passed) { 'passed' } else { 'failed' }
            securityStatus = if ($securityPassed) { 'passed' } else { 'failed' }
            diagnosticsStatus = if ($diagnosticsPassed) { 'passed' } else { 'failed' }
            auditExitCode = $auditExitCode
            diagnostics = $auditResult.stderr
            counts = $audit.metadata.vulnerabilities
            findings = $findings
            remediationApplied = $null -ne $remediation -and $remediation.passed
            remediationChanges = if ($null -ne $remediation) { @($remediation.changes) } else { @() }
            requiresBreakingFix = $null -ne $remediation -and $remediation.requiresBreakingFix
        }
        $reports.Add($currentReport)
    }
    catch {
        $failures.Add("$relativeLockPath`: $($_.Exception.Message)")
    }
    $checkPassed = $failures.Count -eq $failureCountBefore
    $failureDetail = if ($checkPassed) { '' } else { $failures[$failures.Count - 1] }
    Add-NpmValidationResult -Name $relativeLockPath -Passed $checkPassed -Stopwatch $checkStopwatch -Report $currentReport -Failure $failureDetail
}
$suiteStopwatch.Stop()

$result = [ordered]@{
    status = if ($failures.Count -eq 0) { 'passed' } else { 'failed' }
    threshold = 'low'
    lockfileCount = $lockPaths.Count
    reports = $reports.ToArray()
    failures = $failures.ToArray()
}

if ($OutputFormat -eq 'Json') {
    $result | ConvertTo-Json -Depth 8
}
else {
    Write-ValidationSectionHeader -Title 'npm security validation summary'
    $passedCount = @($validationRows | Where-Object { $_.status -ceq 'passed' }).Count
    Write-ValidationSummary -Fields ([ordered]@{
        Status = $result.status.ToUpperInvariant()
        Lockfiles = $lockPaths.Count
        Passed = $passedCount
        Failed = $validationRows.Count - $passedCount
        Threshold = 'LOW'
        Duration = Format-ValidationDuration -DurationSeconds $suiteStopwatch.Elapsed.TotalSeconds
    })
    foreach ($report in $reports) {
        foreach ($change in @($report.remediationChanges)) {
            Write-Output "  - $change"
        }
    }
    if ($failures.Count) {
        Write-ValidationSectionHeader -Title 'Failures'
        foreach ($failure in $failures) { Write-Output "  - $failure" }
    }
    Complete-ValidationTextOutput
}

if ($failures.Count -gt 0) {
    exit 1
}
