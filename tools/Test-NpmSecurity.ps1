[CmdletBinding()]
param(
    [string]$RepositoryRoot = (Join-Path $PSScriptRoot '..'),

    [string[]]$AdditionalLockPath = @(),

    [switch]$Fix,

    [switch]$AllowBreakingFix,

    [ValidateSet('Text', 'Json')]
    [string]$OutputFormat = 'Text'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

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

function Resolve-RepositoryPath {
    param([Parameter(Mandatory = $true)][string]$Path)

    $resolvedPath = [IO.Path]::GetFullPath((Join-Path $resolvedRepositoryRoot $Path))
    if (-not $resolvedPath.StartsWith($repositoryPrefix, [StringComparison]::OrdinalIgnoreCase)) {
        throw "npm lockfile path escapes the repository root: $Path"
    }
    return $resolvedPath
}

function Invoke-NpmAudit {
    param([Parameter(Mandatory = $true)][string]$PackageDirectory)

    $output = @(& $npmCommand.Source audit --prefix $PackageDirectory --package-lock-only --ignore-scripts --audit-level=low --json 2>&1)
    $exitCode = $LASTEXITCODE
    $report = try { ($output | Out-String) | ConvertFrom-Json -ErrorAction Stop } catch { $null }
    return [pscustomobject]@{
        exitCode = $exitCode
        report = $report
        output = ($output | Out-String).Trim()
    }
}

function Get-NpmFindings {
    param([AllowNull()][object]$Audit)

    if ($null -eq $Audit -or $null -eq $Audit.metadata -or $null -eq $Audit.metadata.vulnerabilities -or $null -eq $Audit.vulnerabilities) {
        throw 'npm audit did not return a complete vulnerability report'
    }

    return @($Audit.vulnerabilities.PSObject.Properties | Where-Object { $_.Value.severity -in @('low', 'moderate', 'high', 'critical') } | Sort-Object Name)
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

        $null = @(& $npmCommand.Source audit fix --prefix $stagingRoot --package-lock-only --ignore-scripts --no-fund --json 2>&1)
        $auditResult = Invoke-NpmAudit -PackageDirectory $stagingRoot
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

                $latestOutput = @(& $npmCommand.Source view $packageName version --json 2>&1)
                if ($LASTEXITCODE -ne 0) {
                    continue
                }
                $latestVersion = try { [string](($latestOutput | Out-String) | ConvertFrom-Json -ErrorAction Stop) } catch { '' }
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
                $null = @(& $npmCommand.Source install --prefix $stagingRoot --package-lock-only --ignore-scripts --no-audit --no-fund 2>&1)
                if ($LASTEXITCODE -ne 0) {
                    throw 'npm could not regenerate the staged lockfile after adding transitive overrides'
                }
                $auditResult = Invoke-NpmAudit -PackageDirectory $stagingRoot
                $findings = @(Get-NpmFindings -Audit $auditResult.report)
            }
        }

        $requiresBreakingFix = @($findings | Where-Object { $null -ne $_.Value.fixAvailable -and $_.Value.fixAvailable -isnot [bool] -and $_.Value.fixAvailable.isSemVerMajor }).Count -gt 0
        if ($findings.Count -gt 0 -and $requiresBreakingFix -and $AllowBreaking) {
            $null = @(& $npmCommand.Source audit fix --prefix $stagingRoot --package-lock-only --ignore-scripts --force --no-fund --json 2>&1)
            $auditResult = Invoke-NpmAudit -PackageDirectory $stagingRoot
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

$trackedLockPaths = @(& $gitCommand.Source -C $resolvedRepositoryRoot ls-files -- 'package-lock.json' '**/package-lock.json')
if ($LASTEXITCODE -ne 0) {
    throw 'git could not enumerate tracked npm lockfiles'
}

$lockPaths = New-Object 'System.Collections.Generic.List[string]'
foreach ($path in @($trackedLockPaths) + @($AdditionalLockPath)) {
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
foreach ($lockPath in @($lockPaths | Sort-Object)) {
    $relativeLockPath = [IO.Path]::GetRelativePath($resolvedRepositoryRoot, $lockPath).Replace('\', '/')
    $packageDirectory = Split-Path -Parent $lockPath
    $manifestPath = Join-Path $packageDirectory 'package.json'
    if (-not (Test-Path -LiteralPath $lockPath -PathType Leaf)) {
        $failures.Add("npm lockfile was not found: $relativeLockPath")
        continue
    }
    if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) {
        $failures.Add("npm lockfile does not have a package.json peer: $relativeLockPath")
        continue
    }

    try {
        $manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json -ErrorAction Stop
        $lock = Get-Content -LiteralPath $lockPath -Raw | ConvertFrom-Json -AsHashtable -ErrorAction Stop
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

        $hashesBefore = @($manifestPath, $lockPath) | ForEach-Object { (Get-FileHash -LiteralPath $_ -Algorithm SHA256).Hash }
        $auditResult = Invoke-NpmAudit -PackageDirectory $packageDirectory
        $auditExitCode = $auditResult.exitCode
        $hashesAfter = @($manifestPath, $lockPath) | ForEach-Object { (Get-FileHash -LiteralPath $_ -Algorithm SHA256).Hash }
        if (Compare-Object -ReferenceObject $hashesBefore -DifferenceObject $hashesAfter) {
            throw 'npm audit modified package.json or package-lock.json'
        }

        $audit = $auditResult.report
        $findingProperties = @(Get-NpmFindings -Audit $audit)

        $findings = @($findingProperties | ForEach-Object {
            [ordered]@{
                package = $_.Name
                severity = ([string]$_.Value.severity).ToUpperInvariant()
                affectedRange = [string]$_.Value.range
            }
        })
        $passed = $auditExitCode -eq 0 -and $findings.Count -eq 0
        $remediation = $null
        if (-not $passed -and $Fix) {
            $remediation = Invoke-NpmRemediation -ManifestPath $manifestPath -LockPath $lockPath -AllowBreaking:$AllowBreakingFix
            if ($remediation.passed) {
                $auditResult = Invoke-NpmAudit -PackageDirectory $packageDirectory
                $audit = $auditResult.report
                $findingProperties = @(Get-NpmFindings -Audit $audit)
                $findings = @($findingProperties | ForEach-Object {
                    [ordered]@{
                        package = $_.Name
                        severity = ([string]$_.Value.severity).ToUpperInvariant()
                        affectedRange = [string]$_.Value.range
                    }
                })
                $passed = $auditResult.exitCode -eq 0 -and $findings.Count -eq 0
            }
        }
        if (-not $passed) {
            $failures.Add("$relativeLockPath contains $($findings.Count) npm vulnerabilities")
        }
        $reports.Add([ordered]@{
            lockPath = $relativeLockPath
            status = if ($passed) { 'passed' } else { 'failed' }
            counts = $audit.metadata.vulnerabilities
            findings = $findings
            remediationApplied = $null -ne $remediation -and $remediation.passed
            remediationChanges = if ($null -ne $remediation) { @($remediation.changes) } else { @() }
            requiresBreakingFix = $null -ne $remediation -and $remediation.requiresBreakingFix
        })
    }
    catch {
        $failures.Add("$relativeLockPath`: $($_.Exception.Message)")
    }
}

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
    foreach ($report in $reports) {
        $counts = $report.counts
        Write-Output ("[{0}] {1}: critical={2}, high={3}, moderate={4}, low={5}" -f $report.status.ToUpperInvariant(), $report.lockPath, $counts.critical, $counts.high, $counts.moderate, $counts.low)
        foreach ($change in @($report.remediationChanges)) {
            Write-Output "  - $change"
        }
    }
    foreach ($failure in $failures) {
        Write-Output "[FAILED] $failure"
    }
    if ($lockPaths.Count -eq 0) {
        Write-Output '[PASSED] No tracked npm lockfiles were found'
    }
}

if ($failures.Count -gt 0) {
    exit 1
}
