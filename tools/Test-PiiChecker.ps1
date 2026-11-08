[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot 'ValidationOutput.psm1') -Force
Import-Module (Join-Path $PSScriptRoot 'privacy/Pii.psm1') -Force
$results = [Collections.Generic.List[object]]::new()
function Assert-PrivacyCase {
    param([string]$Name, [bool]$Passed)
    $results.Add([pscustomobject]@{ name = $Name; status = if ($Passed) { 'passed' } else { 'failed' } })
}
$rules = @(Get-PrivacyRules -PrivateIdentifier @('synthetic-person'))
$privateHomeFixture = 'C:' + '/Users/' + 'synthetic-person' + '/work/project.sqlite'
$matches = @(Find-PrivacyText -Text $privateHomeFixture -Path 'notes.md' -Rules $rules)
Assert-PrivacyCase 'personal-home-and-identifier-detected' ($matches.rule -contains 'personal-home-path' -and $matches.rule -contains 'private-identifier')
Assert-PrivacyCase 'findings-never-contain-matched-values' (-not (($matches | ConvertTo-Json -Depth 6).Contains('synthetic-person')))
$safe = @(Find-PrivacyText -Text 'Use %LOCALAPPDATA%/<workspace-id>/workbench.sqlite or C:/Users/<user>/work; contact person@example.com' -Path 'docs/example.md' -Rules $rules)
Assert-PrivacyCase 'synthetic-and-environment-examples-accepted' ($safe.Count -eq 0)
$placeholderHomes = @('C:\Users\example\work', 'C:/Users/example/work', '/Users/example/work', '/home/example/work', 'C:\Users\...', '/Users/...', '/home/...', 'c:/uSeRs/ExAmPlE/work')
$placeholderMatches = @($placeholderHomes | ForEach-Object { Find-PrivacyText -Text $_ -Path 'docs/example.md' -Rules $rules })
Assert-PrivacyCase 'explicit-example-and-redacted-home-segments-accepted' ($placeholderMatches.Count -eq 0)
$placeholderPathMatches = @(Find-PrivacyText -Text 'Safe body' -Path 'C:/Users/example/work.md' -Rules $rules)
Assert-PrivacyCase 'synthetic-home-path-filenames-accepted' ($placeholderPathMatches.Count -eq 0)
$nearPlaceholderHomes = @(('C:' + '/Users/' + 'example-private/work'), ('/Users/' + '...-private/work'), ('/home/' + 'synthetic-person/work'))
$nearPlaceholderMatches = @($nearPlaceholderHomes | ForEach-Object { Find-PrivacyText -Text $_ -Path 'fixture.md' -Rules $rules })
Assert-PrivacyCase 'placeholder-prefixes-cannot-hide-personal-home-paths' (@($nearPlaceholderMatches | Where-Object rule -CEQ 'personal-home-path').Count -eq 3)
$editorHomeFixture = 'C:/Users/example/AppData/Roaming/Code/User/workspaceStorage/'
$editorHomeMatches = @(Find-PrivacyText -Text $editorHomeFixture -Path 'docs/example.md' -Rules $rules)
Assert-PrivacyCase 'synthetic-home-with-nested-editor-user-directory-accepted' ($editorHomeMatches.Count -eq 0)
$privateEditorFixture = $editorHomeFixture.Replace('/example/', '/SYNTHETIC-PERSON/')
$privateEditorMatches = @(Find-PrivacyText -Text $privateEditorFixture -Path 'fixture.md' -Rules $rules)
Assert-PrivacyCase 'real-account-remains-detected-case-insensitively-with-nested-user-directory' ($privateEditorMatches.rule -contains 'personal-home-path' -and $privateEditorMatches.rule -contains 'private-identifier')
$mixedHomeMatches = @(Find-PrivacyText -Text ($placeholderHomes[0] + ' ' + $privateHomeFixture) -Path 'fixture.md' -Rules $rules)
Assert-PrivacyCase 'synthetic-home-does-not-hide-another-personal-home-on-the-line' ($mixedHomeMatches.rule -contains 'personal-home-path')
$knownExampleRules = @(Get-PrivacyRules -PrivateIdentifier @('example'))
$knownExampleMatches = @(Find-PrivacyText -Text $placeholderHomes[0] -Path 'fixture.md' -Rules $knownExampleRules)
Assert-PrivacyCase 'known-local-identifier-is-not-exempted-by-placeholder-classification' ($knownExampleMatches.Count -eq 1 -and $knownExampleMatches[0].rule -ceq 'private-identifier')
$nonSyntheticEmail = 'person@' + 'example.com.actual-mail.net'
$emailMatches = @(Find-PrivacyText -Text $nonSyntheticEmail -Path 'fixture.md' -Rules $rules)
Assert-PrivacyCase 'example-domain-prefix-cannot-hide-real-email' ($emailMatches.Count -eq 1 -and $emailMatches[0].rule -eq 'personal-email')
$credential = 'ghp_' + ('A' * 36)
$credentialMatches = @(Find-PrivacyText -Text $credential -Path 'fixture.md' -Rules $rules)
Assert-PrivacyCase 'credential-findings-never-include-credential-text' ($credentialMatches.Count -eq 1 -and -not (($credentialMatches | ConvertTo-Json -Depth 6).Contains($credential)))
$pathFindings = @(Find-PrivacyText -Text 'Safe body' -Path 'notes/synthetic-person.md' -Rules $rules)
Assert-PrivacyCase 'sensitive-filenames-redacted-and-detected' ($pathFindings.Count -eq 1 -and $pathFindings[0].line -eq 0 -and $pathFindings[0].path -eq 'notes/[REDACTED].md')
$root = Join-Path ([IO.Path]::GetTempPath()) ('pii-checker-fixture-' + [guid]::NewGuid().ToString('N'))
$null = New-Item -Path $root -ItemType Directory
try {
    & git -C $root init --quiet -b main
    if ($LASTEXITCODE -ne 0) { throw 'Synthetic Git fixture initialization failed' }
    [IO.File]::WriteAllText((Join-Path $root '.gitignore'), "private/`n")
    $null = New-Item -Path (Join-Path $root 'private') -ItemType Directory
    [IO.File]::WriteAllText((Join-Path $root 'private/restart.md'), $privateHomeFixture)
    [IO.File]::WriteAllText((Join-Path $root 'tracked.md'), $privateHomeFixture)
    & git -C $root add .gitignore tracked.md
    if ($LASTEXITCODE -ne 0) { throw 'Synthetic Git staging failed' }
    [IO.File]::WriteAllText((Join-Path $root 'tracked.md'), 'Safe working copy')
    $staged = Invoke-RepositoryPrivacyScan -RepositoryRoot $root -Scope Staged -PrivateIdentifier @('synthetic-person')
    $working = Invoke-RepositoryPrivacyScan -RepositoryRoot $root -Scope Worktree -PrivateIdentifier @('synthetic-person')
    Assert-PrivacyCase 'staged-blob-not-clean-working-copy-is-scanned' ($staged.findings.Count -gt 0 -and $working.findings.Count -eq 0)
    Assert-PrivacyCase 'ignored-private-notes-not-scanned-as-worktree-content' ($working.files -eq 2)
    & git -C $root -c core.autocrlf=false add tracked.md
    & git -C $root -c user.name='Synthetic Fixture' -c user.email='fixture@example.invalid' -c commit.gpgsign=false commit --quiet -m 'Initial synthetic baseline'
    if ($LASTEXITCODE -ne 0) { throw 'Synthetic baseline commit failed' }
    $baseline = (& git -C $root rev-parse HEAD).Trim()
    [IO.File]::WriteAllText((Join-Path $root 'tracked.md'), $privateHomeFixture)
    & git -C $root -c core.autocrlf=false add tracked.md
    & git -C $root -c user.name='Synthetic Fixture' -c user.email='fixture@example.invalid' -c commit.gpgsign=false commit --quiet -m 'Intermediate sensitive fixture'
    if ($LASTEXITCODE -ne 0) { throw 'Synthetic intermediate commit failed' }
    $intermediate = (& git -C $root rev-parse HEAD).Trim()
    [IO.File]::WriteAllText((Join-Path $root 'tracked.md'), 'Safe final copy')
    & git -C $root -c core.autocrlf=false add tracked.md
    & git -C $root -c user.name='Synthetic Fixture' -c user.email='fixture@example.invalid' -c commit.gpgsign=false commit --quiet -m 'Remove sensitive fixture'
    if ($LASTEXITCODE -ne 0) { throw 'Synthetic final commit failed' }
    $outgoing = Invoke-RepositoryPrivacyScan -RepositoryRoot $root -Scope Outgoing -BaseRef $baseline -PrivateIdentifier @('synthetic-person')
    Assert-PrivacyCase 'outgoing-history-detects-secret-removed-from-head' ($outgoing.revisions -eq 2 -and $outgoing.findings.Count -gt 0 -and
        @($outgoing.findings | Where-Object revision -CEQ $intermediate).Count -gt 0 -and -not (($outgoing | ConvertTo-Json -Depth 6).Contains('synthetic-person')))
    $unknownRejected = $false
    try { $null = Invoke-RepositoryPrivacyScan -RepositoryRoot $root -Scope Outgoing -BaseRef 'not-a-real-reference' }
    catch { $unknownRejected = $true }
    Assert-PrivacyCase 'unknown-outgoing-baseline-fails-closed' $unknownRejected
    $empty = Invoke-RepositoryPrivacyScan -RepositoryRoot $root -Scope Outgoing -BaseRef HEAD
    Assert-PrivacyCase 'empty-outgoing-range-inspected-without-invented-work' ($empty.revisions -eq 0 -and $empty.files -eq 0 -and $empty.findings.Count -eq 0)
    & git -C $root -c user.name='Synthetic Fixture' -c user.email='fixture@example.invalid' -c commit.gpgsign=false commit --quiet --allow-empty -m $privateHomeFixture
    if ($LASTEXITCODE -ne 0) { throw 'Synthetic commit-message fixture failed' }
    $messageScan = Invoke-RepositoryPrivacyScan -RepositoryRoot $root -Scope Outgoing -BaseRef 'HEAD~1' -PrivateIdentifier @('synthetic-person')
    Assert-PrivacyCase 'outgoing-commit-messages-scanned-without-echoing-text' (@($messageScan.findings | Where-Object path -CEQ '[commit-message]').Count -gt 0 -and
        -not (($messageScan | ConvertTo-Json -Depth 6).Contains('synthetic-person')))
    [IO.File]::WriteAllText((Join-Path $root 'tracked.md'), $privateHomeFixture)
    & git -C $root -c core.autocrlf=false add tracked.md
    if ($LASTEXITCODE -ne 0) { throw 'Synthetic CLI fixture staging failed' }
    $runnerPath = Join-Path $PSScriptRoot 'Test-Pii.ps1'
    $cliChecks = [Collections.Generic.List[object]]::new()
    foreach ($scope in @('Staged', 'Outgoing')) {
        $start = [Diagnostics.ProcessStartInfo]::new('pwsh')
        $start.UseShellExecute = $false
        $start.RedirectStandardOutput = $true
        $start.RedirectStandardError = $true
        $arguments = @('-NoProfile', '-NonInteractive', '-File', $runnerPath, '-RepositoryRoot', $root, '-Scope', $scope, '-OutputFormat', 'Json')
        if ($scope -eq 'Outgoing') { $arguments += @('-BaseRef', 'not-a-real-reference') }
        foreach ($argument in $arguments) { $start.ArgumentList.Add($argument) }
        $process = [Diagnostics.Process]::new()
        $process.StartInfo = $start
        try {
            $null = $process.Start()
            $stdout = $process.StandardOutput.ReadToEndAsync()
            $stderr = $process.StandardError.ReadToEndAsync()
            $process.WaitForExit()
            $output = $stdout.GetAwaiter().GetResult()
            $errors = $stderr.GetAwaiter().GetResult()
            $report = $output | ConvertFrom-Json -Depth 6
            $expectedExit = if ($scope -eq 'Staged') { 1 } else { 2 }
            $valid = $process.ExitCode -eq $expectedExit -and $report.status -ceq 'failed' -and [string]::IsNullOrWhiteSpace($errors) -and
                -not $output.Contains('synthetic-person') -and -not $output.Contains($root)
            if ($scope -eq 'Outgoing') { $valid = $valid -and $report.failureCode -ceq 'privacy-inspection-incomplete' }
            $cliChecks.Add([pscustomobject]@{ scope = $scope; passed = $valid })
        } finally { $process.Dispose() }
    }
    Assert-PrivacyCase 'real-cli-finding-and-incomplete-inspection-block-with-safe-output' (@($cliChecks | Where-Object passed -EQ $false).Count -eq 0)
    $zeroBaseline = Invoke-RepositoryPrivacyScan -RepositoryRoot $root -Scope Outgoing -BaseRef ('0' * 40) -PrivateIdentifier @('synthetic-person')
    Assert-PrivacyCase 'new-branch-zero-baseline-scans-all-reachable-commits' ($zeroBaseline.revisions -eq 4 -and $zeroBaseline.findings.Count -gt 0)
    $unicodeBytes = [Text.Encoding]::Unicode.GetPreamble() + [Text.Encoding]::Unicode.GetBytes($privateHomeFixture)
    [IO.File]::WriteAllBytes((Join-Path $root 'unicode.md'), $unicodeBytes)
    [IO.File]::WriteAllBytes((Join-Path $root 'binary.dat'), ([byte[]]@(137, 80, 78, 71) + [Text.Encoding]::UTF8.GetBytes($privateHomeFixture)))
    $encoded = Invoke-RepositoryPrivacyScan -RepositoryRoot $root -Scope Worktree -PrivateIdentifier @('synthetic-person')
    Assert-PrivacyCase 'utf16-and-ascii-in-binary-artifacts-not-silently-skipped' (@($encoded.findings | Where-Object path -EQ 'unicode.md').Count -gt 0 -and
        @($encoded.findings | Where-Object path -EQ 'binary.dat').Count -gt 0)
    & git -C $root -c core.autocrlf=false add -f private/restart.md
    if ($LASTEXITCODE -ne 0) { throw 'Synthetic force-tracked private fixture failed' }
    $forced = Invoke-RepositoryPrivacyScan -RepositoryRoot $root -Scope Staged -PrivateIdentifier @('synthetic-person')
    Assert-PrivacyCase 'force-tracked-ignored-files-are-still-inspected' (@($forced.findings | Where-Object path -EQ 'private/restart.md').Count -gt 0)
    $blob = (& git -C $root rev-parse ':tracked.md').Trim()
    & git -C $root update-index --force-remove tracked.md
    $indexRecords = @(('100644 ' + $blob + " 1`ttracked.md"), ('100644 ' + $blob + " 2`ttracked.md"), ('100644 ' + $blob + " 3`ttracked.md"))
    $indexStart = [Diagnostics.ProcessStartInfo]::new((Get-Command git -CommandType Application).Source)
    $indexStart.UseShellExecute = $false
    $indexStart.RedirectStandardInput = $true
    $indexStart.RedirectStandardOutput = $true
    $indexStart.RedirectStandardError = $true
    foreach ($argument in @('-C', $root, 'update-index', '--index-info')) { $indexStart.ArgumentList.Add($argument) }
    $indexProcess = [Diagnostics.Process]::new()
    $indexProcess.StartInfo = $indexStart
    try {
        $null = $indexProcess.Start()
        $indexStdout = $indexProcess.StandardOutput.ReadToEndAsync()
        $indexStderr = $indexProcess.StandardError.ReadToEndAsync()
        $indexProcess.StandardInput.Write(($indexRecords -join "`n") + "`n")
        $indexProcess.StandardInput.Close()
        $indexProcess.WaitForExit()
        if ($indexProcess.ExitCode -ne 0 -or -not [string]::IsNullOrWhiteSpace($indexStdout.GetAwaiter().GetResult()) -or
            -not [string]::IsNullOrWhiteSpace($indexStderr.GetAwaiter().GetResult())) { throw 'Synthetic unmerged-index fixture failed' }
    } finally { $indexProcess.Dispose() }
    $conflictStages = @(& git -C $root ls-files --unmerged)
    if ($LASTEXITCODE -ne 0 -or $conflictStages.Count -ne 3) { throw 'Synthetic conflict must include all three index stages' }
    $unmergedRejected = $false
    try { $null = Invoke-RepositoryPrivacyScan -RepositoryRoot $root -Scope Staged }
    catch { $unmergedRejected = $true }
    Assert-PrivacyCase 'unresolved-index-cannot-produce-empty-passing-scan' $unmergedRejected
} finally { Remove-Item -LiteralPath $root -Recurse -Force }
Write-ValidationSectionHeader -Title 'Shared Privacy Checker Tests'
Write-ValidationSummary -Fields ([ordered]@{ Tests = $results.Count; Failed = @($results | Where-Object status -EQ 'failed').Count })
Write-Output ''
Write-ValidationTwoColumnTable -Rows $results -FirstHeader 'Status' -FirstProperty 'status' -SecondHeader 'Test' -SecondProperty 'name' -UppercaseFirst
Complete-ValidationTextOutput
if (@($results | Where-Object status -EQ 'failed').Count) { exit 1 }
