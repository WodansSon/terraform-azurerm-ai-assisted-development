Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Import-Module -Name (Join-Path $PSScriptRoot '../../../../tools/ValidationOutput.psm1')

function ConvertFrom-WorkbenchNodeTestReport {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][AllowEmptyString()][string]$Report,
        [Parameter(Mandatory)][int]$ExitCode,
        [AllowEmptyString()][string]$Diagnostics = ''
    )

    $results = [Collections.Generic.List[object]]::new()
    $issues = [Collections.Generic.List[string]]::new()
    try {
        $settings = [Xml.XmlReaderSettings]::new()
        $settings.DtdProcessing = [Xml.DtdProcessing]::Prohibit
        $settings.XmlResolver = $null
        $reader = [Xml.XmlReader]::Create([IO.StringReader]::new($Report), $settings)
        try {
            $document = [Xml.XmlDocument]::new()
            $document.XmlResolver = $null
            $document.Load($reader)
        }
        finally { $reader.Dispose() }
        if ($document.DocumentElement.LocalName -notin @('testsuites', 'testsuite') -or $document.DocumentElement.NamespaceURI) { throw 'Unexpected JUnit document root.' }
        $cases = @($document.SelectNodes('//testcase'))
        if ($cases.Count -eq 0) { throw 'No test cases were reported.' }
        foreach ($case in $cases) {
            $name = $case.GetAttribute('name')
            $shortName = ''
            $description = $name
            for ($diagnostic = $case.NextSibling; $null -ne $diagnostic; $diagnostic = $diagnostic.NextSibling) {
                if ($diagnostic.NodeType -eq [Xml.XmlNodeType]::Element) { break }
                if ($diagnostic.NodeType -ne [Xml.XmlNodeType]::Comment -or -not $diagnostic.Value.TrimStart().StartsWith('{')) { continue }
                try { $metadata = $diagnostic.Value | ConvertFrom-Json -AsHashtable -Depth 10 -DateKind String }
                catch { continue }
                if ($metadata.ContainsKey('shortName')) {
                    if ($null -ne $metadata.shortName -and $metadata.shortName -isnot [string]) { throw 'JUnit shortName metadata must be a string.' }
                    $shortName = [string]$metadata.shortName
                }
                if ($metadata.ContainsKey('description')) {
                    if ($null -ne $metadata.description -and $metadata.description -isnot [string]) { throw 'JUnit description metadata must be a string.' }
                    if (-not [string]::IsNullOrWhiteSpace($metadata.description)) { $description = $metadata.description }
                }
            }
            if ([string]::IsNullOrWhiteSpace($shortName)) { $shortName = $name }
            if ([string]::IsNullOrWhiteSpace($shortName)) { $shortName = 'test-{0:000}' -f ($results.Count + 1) }
            if ([string]::IsNullOrWhiteSpace($name)) { $name = $shortName }
            if ([string]::IsNullOrWhiteSpace($description)) { $description = $name }
            $durationSeconds = 0.0
            if (-not [double]::TryParse($case.GetAttribute('time'), [Globalization.NumberStyles]::Float, [Globalization.CultureInfo]::InvariantCulture, [ref]$durationSeconds) -or -not [double]::IsFinite($durationSeconds) -or $durationSeconds -lt 0) {
                throw 'JUnit reported an invalid test duration.'
            }
            $failures = @($case.SelectNodes('./failure | ./error'))
            $skip = $case.SelectSingleNode('./skipped')
            $status = if ($failures.Count -gt 0 -or $case.HasAttribute('failure')) { 'failed' } elseif ($null -ne $skip) { 'skipped' } else { 'passed' }
            $detail = if ($failures.Count -gt 0) {
                (@($failures | ForEach-Object { if ([string]::IsNullOrWhiteSpace($_.InnerText)) { $_.GetAttribute('message') } else { $_.InnerText } }) -join "`n").Trim()
            }
            elseif ($case.HasAttribute('failure')) { $case.GetAttribute('failure') }
            elseif ($null -ne $skip) {
                $reason = $skip.GetAttribute('message').Trim()
                if (-not $reason) { $reason = $skip.InnerText.Trim() }
                if (-not $reason -or $reason -eq 'true') { 'No skip reason supplied.' } else { $reason }
            }
            else { 'Assertions passed.' }
            $results.Add([pscustomobject]@{ name = $name; shortName = $shortName; description = $description; status = $status; detail = $detail; durationSeconds = $durationSeconds })
            if ($status -eq 'failed') { $issues.Add("$name`: $detail") }
        }
        foreach ($failure in $document.SelectNodes('//failure[not(parent::testcase)] | //error[not(parent::testcase)]')) {
            $issues.Add("Test suite failure: $($failure.InnerText)")
        }
        if (@($results | Where-Object { $_.status -ne 'skipped' }).Count -eq 0) { $issues.Add('No tests executed; all reported tests were skipped.') }
    }
    catch { $issues.Add("Invalid JUnit test report: $($_.Exception.Message)") }
    if (($ExitCode -ne 0 -and $issues.Count -eq 0) -or $ExitCode -notin @(0, 1)) { $issues.Add("Test runner exited with code $ExitCode.") }
    $failed = @($results | Where-Object { $_.status -eq 'failed' }).Count
    $skipped = @($results | Where-Object { $_.status -eq 'skipped' }).Count
    return [pscustomobject][ordered]@{
        status = if ($issues.Count -eq 0) { 'passed' } else { 'failed' }
        testCount = $results.Count
        passedCount = @($results | Where-Object { $_.status -eq 'passed' }).Count
        failedCount = $failed
        skippedCount = $skipped
        issueCount = $issues.Count
        exitCode = if ($ExitCode -gt 0) { $ExitCode } elseif ($issues.Count -gt 0) { 1 } else { 0 }
        tests = $results.ToArray()
        issues = $issues.ToArray()
        diagnostics = $Diagnostics.Trim()
        nativeExitCode = $ExitCode
    }
}

function Invoke-WorkbenchNodeTests {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$TestPath,
        [Parameter(Mandatory)][string]$Title,
        [ValidateSet('Text', 'Json')][string]$OutputFormat = 'Text'
    )

    if ($OutputFormat -eq 'Text') {
        Write-ValidationSectionHeader -Title $Title
        Write-Host (Format-ValidationLifecycleLine -Status running -Name 'JUnit tests.')
    }
    $timer = [Diagnostics.Stopwatch]::StartNew()
    $report = ''
    $diagnostics = ''
    $exitCode = 1
    try {
        if (-not (Test-Path -LiteralPath $TestPath -PathType Leaf)) { throw 'The selected native test file does not exist.' }
        $node = Get-Command node -CommandType Application -ErrorAction Stop
        $start = [Diagnostics.ProcessStartInfo]::new()
        $start.FileName = $node.Source
        $start.UseShellExecute = $false
        $start.CreateNoWindow = $true
        $start.RedirectStandardOutput = $true
        $start.RedirectStandardError = $true
        $start.StandardOutputEncoding = [Text.UTF8Encoding]::new($false)
        $start.StandardErrorEncoding = [Text.UTF8Encoding]::new($false)
        $start.WorkingDirectory = [IO.Path]::GetDirectoryName([IO.Path]::GetFullPath($TestPath))
        foreach ($argument in @('--test', '--test-reporter=junit', [IO.Path]::GetFullPath($TestPath))) { $start.ArgumentList.Add($argument) }
        $process = [Diagnostics.Process]::new()
        $process.StartInfo = $start
        try {
            if (-not $process.Start()) { throw 'Node test process could not start.' }
            $stdout = $process.StandardOutput.ReadToEndAsync()
            $stderr = $process.StandardError.ReadToEndAsync()
            $completed = $process.WaitForExit(120000)
            if (-not $completed) {
                $process.Kill($true)
                $process.WaitForExit()
            }
            $report = $stdout.GetAwaiter().GetResult()
            $diagnostics = $stderr.GetAwaiter().GetResult()
            if (-not $completed) { throw 'Test runner exceeded the 120-second limit.' }
            $exitCode = $process.ExitCode
        }
        finally { $process.Dispose() }
    }
    catch { $diagnostics = "$diagnostics`n$($_.Exception.Message)".Trim() }
    $result = ConvertFrom-WorkbenchNodeTestReport -Report $report -ExitCode $exitCode -Diagnostics $diagnostics
    $timer.Stop()
    if ($OutputFormat -eq 'Json') { $result | ConvertTo-Json -Depth 10 }
    else {
        $alignmentWidth = Get-ValidationNameWidth -Names (@('JUnit tests') + @($result.tests | ForEach-Object { '  ' + $_.shortName })) -MinimumWidth 30
        foreach ($test in $result.tests) {
            $label = $test.shortName
            if ($test.status -eq 'skipped') {
                $skipDescription = if ($test.description -ceq $label) { $test.detail } else { "$($test.description) - $($test.detail)" }
                Write-Host (Format-ValidationLifecycleLine -Status skipped -Name $label -Description $skipDescription -AlignmentWidth $alignmentWidth -Child -Level 1)
                continue
            }
            $runningDescription = if ($test.description -ceq $label) { '' } else { $test.description }
            Write-Host (Format-ValidationLifecycleLine -Status running -Name $label -Description $runningDescription -AlignmentWidth $alignmentWidth -Child -Level 1)
            Write-Host (Format-ValidationLifecycleLine -Status $test.status -Name $label -DurationSeconds $test.durationSeconds -AlignmentWidth $alignmentWidth -Child -Level 1)
        }
        Write-Host (Format-ValidationLifecycleLine -Status $result.status -Name 'JUnit tests' -DurationSeconds $timer.Elapsed.TotalSeconds -AlignmentWidth $alignmentWidth)
        Write-ValidationSectionHeader -Title "$Title summary"
        Write-ValidationSummary -Fields ([ordered]@{
            Status = $result.status.ToUpperInvariant()
            Tests = $result.testCount
            Passed = $result.passedCount
            Failed = $result.failedCount
            Skipped = $result.skippedCount
            Issues = $result.issueCount
        })
        if ($result.issueCount -gt 0) {
            Write-ValidationSectionHeader -Title 'Failures'
            foreach ($issue in $result.issues) { Write-Output "  - $issue" }
        }
        if ($result.diagnostics) {
            Write-Output '  Additional output from the test process (not attributed to an individual test):'
            Write-Output $result.diagnostics
        }
        Complete-ValidationTextOutput
    }
    $global:LASTEXITCODE = $result.exitCode
}

Export-ModuleMember -Function ConvertFrom-WorkbenchNodeTestReport, Invoke-WorkbenchNodeTests
