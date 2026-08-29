[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$targetScriptPath = Join-Path $PSScriptRoot 'Get-PRReady.ps1'
$issues = New-Object 'System.Collections.Generic.List[string]'
$testCount = 0

function Confirm-Condition {
    param(
        [Parameter(Mandatory = $true)]
        [bool]$Condition,

        [Parameter(Mandatory = $true)]
        [string]$Message
    )

    if (-not $Condition) {
        throw $Message
    }
}

function Invoke-ScriptProcess {
    param(
        [AllowEmptyCollection()]
        [string[]]$Arguments = @(),

        [string[]]$RemovedEnvironmentVariables = @()
    )

    $startInfo = [System.Diagnostics.ProcessStartInfo]::new()
    $startInfo.FileName = (Get-Process -Id $PID).Path
    $startInfo.UseShellExecute = $false
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true
    $startInfo.ArgumentList.Add('-NoProfile')
    $startInfo.ArgumentList.Add('-File')
    $startInfo.ArgumentList.Add($targetScriptPath)
    foreach ($argument in $Arguments) {
        $startInfo.ArgumentList.Add($argument)
    }
    foreach ($variableName in $RemovedEnvironmentVariables) {
        [void]$startInfo.Environment.Remove($variableName)
    }

    $process = [System.Diagnostics.Process]::new()
    $process.StartInfo = $startInfo
    try {
        if (-not $process.Start()) {
            throw 'failed to start PowerShell test process'
        }

        $standardOutput = $process.StandardOutput.ReadToEndAsync()
        $standardError = $process.StandardError.ReadToEndAsync()
        $process.WaitForExit()

        return [pscustomobject]@{
            exitCode = $process.ExitCode
            standardOutput = $standardOutput.GetAwaiter().GetResult()
            standardError = $standardError.GetAwaiter().GetResult()
        }
    }
    finally {
        $process.Dispose()
    }
}

function New-ProjectResponse {
    param([AllowNull()][object]$FieldValue)

    return [pscustomobject]@{
        data = [pscustomobject]@{
            repository = [pscustomobject]@{
                pullRequest = [pscustomobject]@{
                    number = 12345
                    title = 'Offline test PR'
                    url = 'https://github.com/hashicorp/terraform-provider-azurerm/pull/12345'
                    projectItems = [pscustomobject]@{
                        pageInfo = [pscustomobject]@{
                            hasNextPage = $false
                            endCursor = $null
                        }
                        nodes = @(
                            [pscustomobject]@{
                                project = [pscustomobject]@{
                                    number = 163
                                    owner = [pscustomobject]@{ login = 'hashicorp' }
                                }
                                fieldValueByName = $FieldValue
                            }
                        )
                    }
                }
            }
        }
    }
}

function Invoke-MockedLookup {
    param([AllowNull()][object]$FieldValue)

    $global:prReadyMockResponse = New-ProjectResponse -FieldValue $FieldValue
    $previousToken = $env:GH_TOKEN
    $previousAppData = $env:APPDATA
    try {
        $env:GH_TOKEN = 'offline-test-token'
        $env:APPDATA = $null
        Set-Item -Path Function:\Invoke-RestMethod -Value {
            return $global:prReadyMockResponse
        }

        $output = @(& $targetScriptPath 12345)
        return (($output -join [Environment]::NewLine) | ConvertFrom-Json)
    }
    finally {
        Remove-Item Function:\Invoke-RestMethod -ErrorAction SilentlyContinue
        Remove-Variable -Name prReadyMockResponse -Scope Global -ErrorAction SilentlyContinue
        $env:GH_TOKEN = $previousToken
        $env:APPDATA = $previousAppData
    }
}

function Invoke-MockedBatchLookup {
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$PullRequestNumbers,

        [int[]]$MissingPullRequestNumbers = @(),

        [int[]]$AuthenticationFailureNumbers = @()
    )

    $global:prReadyMockCalls = [System.Collections.Generic.List[int]]::new()
    $global:prReadyMissingNumbers = [System.Collections.Generic.HashSet[int]]::new()
    foreach ($missingPullRequestNumber in $MissingPullRequestNumbers) {
        [void]$global:prReadyMissingNumbers.Add($missingPullRequestNumber)
    }
    $global:prReadyAuthenticationFailureNumbers = [System.Collections.Generic.HashSet[int]]::new()
    foreach ($authenticationFailureNumber in $AuthenticationFailureNumbers) {
        [void]$global:prReadyAuthenticationFailureNumbers.Add($authenticationFailureNumber)
    }

    $previousToken = $env:GH_TOKEN
    $previousAppData = $env:APPDATA
    $standardError = [Console]::Error
    $errorWriter = [IO.StringWriter]::new()
    try {
        $env:GH_TOKEN = 'offline-test-token'
        $env:APPDATA = $null
        Set-Item -Path Function:\Invoke-RestMethod -Value {
            param($Uri, $Method, $Headers, $Body, $ContentType)

            $pullRequestNumber = [int](($Body | ConvertFrom-Json).variables.pullRequestNumber)
            $global:prReadyMockCalls.Add($pullRequestNumber)
            if ($global:prReadyAuthenticationFailureNumbers.Contains($pullRequestNumber)) {
                return [pscustomobject]@{
                    errors = @([pscustomobject]@{ message = 'Unauthorized request (403).' })
                }
            }

            if ($global:prReadyMissingNumbers.Contains($pullRequestNumber)) {
                return [pscustomobject]@{
                    errors = @([pscustomobject]@{ message = "Could not resolve to a PullRequest with the number of $pullRequestNumber." })
                }
            }

            return [pscustomobject]@{
                data = [pscustomobject]@{
                    repository = [pscustomobject]@{
                        pullRequest = [pscustomobject]@{
                            number = $pullRequestNumber
                            title = "Offline test PR $pullRequestNumber"
                            url = "https://github.com/hashicorp/terraform-provider-azurerm/pull/$pullRequestNumber"
                            projectItems = [pscustomobject]@{
                                pageInfo = [pscustomobject]@{
                                    hasNextPage = $false
                                    endCursor = $null
                                }
                                nodes = @(
                                    [pscustomobject]@{
                                        project = [pscustomobject]@{
                                            number = 163
                                            owner = [pscustomobject]@{ login = 'hashicorp' }
                                        }
                                        fieldValueByName = [pscustomobject]@{
                                            name = 'ready'
                                            createdAt = '2026-01-01T00:00:00Z'
                                            updatedAt = '2026-01-02T00:00:00Z'
                                            creator = [pscustomobject]@{ login = 'example-user' }
                                        }
                                    }
                                )
                            }
                        }
                    }
                }
            }
        }

        [Console]::SetError($errorWriter)
        $output = @(& $targetScriptPath $PullRequestNumbers)
        [Console]::SetError($standardError)

        return [pscustomobject]@{
            results = @($output | ForEach-Object { $_ | ConvertFrom-Json })
            calls = @($global:prReadyMockCalls)
            error = $errorWriter.ToString() -replace "`e\[[0-9;]*m", ''
        }
    }
    finally {
        [Console]::SetError($standardError)
        Remove-Item Function:\Invoke-RestMethod -ErrorAction SilentlyContinue
        Remove-Variable -Name prReadyMockCalls -Scope Global -ErrorAction SilentlyContinue
        Remove-Variable -Name prReadyMissingNumbers -Scope Global -ErrorAction SilentlyContinue
        Remove-Variable -Name prReadyAuthenticationFailureNumbers -Scope Global -ErrorAction SilentlyContinue
        $env:GH_TOKEN = $previousToken
        $env:APPDATA = $previousAppData
        $errorWriter.Dispose()
    }
}

function Invoke-TestCase {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name,

        [Parameter(Mandatory = $true)]
        [scriptblock]$Test
    )

    $script:testCount++
    try {
        $null = & $Test
        Write-Output ("[PASSED] {0}" -f $Name)
    }
    catch {
        $issues.Add(("{0}: {1}" -f $Name, $_.Exception.Message))
        Write-Output ("[FAILED] {0}" -f $Name)
    }
}

if (-not (Test-Path -LiteralPath $targetScriptPath -PathType Leaf)) {
    throw "target script was not found: $targetScriptPath"
}

Invoke-TestCase -Name 'help-output' -Test {
    $result = Invoke-ScriptProcess -Arguments @('-Help')
    Confirm-Condition -Condition ($result.exitCode -eq 0) -Message 'expected exit code 0'
    Confirm-Condition -Condition ([string]::IsNullOrWhiteSpace($result.standardError)) -Message 'expected empty stderr'
    Confirm-Condition -Condition (-not $result.standardOutput.Contains([char]27)) -Message 'redirected help contains ANSI escapes'
    Confirm-Condition -Condition ($result.standardOutput -match '(?m)^  NAME: Get-PRReady\.ps1\r?$') -Message 'NAME section is missing'
    Confirm-Condition -Condition ($result.standardOutput -match '(?m)^  USAGE:\r?$') -Message 'USAGE section is missing'
    Confirm-Condition -Condition ($result.standardOutput -match '(?m)^  AUTHENTICATION:\r?$') -Message 'AUTHENTICATION section is missing'
    Confirm-Condition -Condition ($result.standardOutput -match '(?m)^  LIMITATIONS:\r?$') -Message 'LIMITATIONS section is missing'
    Confirm-Condition -Condition ($result.standardOutput -match 'Get-PRReady\.ps1 12345,23456,34567') -Message 'multiple PR usage is missing'
}

Invoke-TestCase -Name 'missing-pr-number' -Test {
    $result = Invoke-ScriptProcess
    Confirm-Condition -Condition ($result.exitCode -eq 1) -Message 'expected exit code 1'
    Confirm-Condition -Condition ($result.standardError -match '(?m)^  ARGUMENTS \| ERROR: A PR number is required\.\r?$') -Message 'required argument error is missing'
    Confirm-Condition -Condition ($result.standardOutput -match '(?m)^  USAGE:\r?$') -Message 'help output is missing'
    Confirm-Condition -Condition ($result.standardError -notmatch 'Exception:|Line \|') -Message 'native PowerShell diagnostics leaked'
}

Invoke-TestCase -Name 'unknown-arguments' -Test {
    $result = Invoke-ScriptProcess -Arguments @('-Foo', 'bar')
    Confirm-Condition -Condition ($result.exitCode -eq 1) -Message 'expected exit code 1'
    Confirm-Condition -Condition ($result.standardError -match '(?m)^  ARGUMENTS \| ERROR: Invalid argument\(s\): -Foo bar\r?$') -Message 'unknown argument error is missing'
    Confirm-Condition -Condition ($result.standardOutput -match '(?m)^  USAGE:\r?$') -Message 'help output is missing'
}

Invoke-TestCase -Name 'invalid-pr-number' -Test {
    $result = Invoke-ScriptProcess -Arguments @('invalid')
    Confirm-Condition -Condition ($result.exitCode -eq 1) -Message 'expected exit code 1'
    Confirm-Condition -Condition ($result.standardError -match '(?m)^  ARGUMENTS \| ERROR: PR number must be a positive integer: invalid\r?$') -Message 'invalid PR number error is missing'
}

Invoke-TestCase -Name 'invalid-pr-number-list' -Test {
    $result = Invoke-ScriptProcess -Arguments @('12345,invalid')
    Confirm-Condition -Condition ($result.exitCode -eq 1) -Message 'expected exit code 1'
    Confirm-Condition -Condition ($result.standardError -match '(?m)^  ARGUMENTS \| ERROR: PR numbers must be a comma-separated list of positive integers: 12345,invalid\r?$') -Message 'invalid PR number list error is missing'
    Confirm-Condition -Condition ($result.standardOutput -match '(?m)^  USAGE:\r?$') -Message 'help output is missing'
}

Invoke-TestCase -Name 'empty-pr-number-list-elements' -Test {
    foreach ($inputValue in @('12345,,23456', ',12345', '12345,')) {
        $result = Invoke-ScriptProcess -Arguments @($inputValue)
        Confirm-Condition -Condition ($result.exitCode -eq 1) -Message "expected exit code 1 for $inputValue"
        Confirm-Condition -Condition ($result.standardError -match 'PR numbers must be a comma-separated list of positive integers') -Message "list error is missing for $inputValue"
    }
}

Invoke-TestCase -Name 'pr-number-numeric-boundaries' -Test {
    foreach ($inputValue in @('0', '-1', '2147483648', '12345,0')) {
        $result = Invoke-ScriptProcess -Arguments @($inputValue)
        Confirm-Condition -Condition ($result.exitCode -eq 1) -Message "expected exit code 1 for $inputValue"
        Confirm-Condition -Condition ($result.standardError -match '(?m)^  ARGUMENTS \| ERROR:') -Message "numeric error is missing for $inputValue"
    }
}

Invoke-TestCase -Name 'missing-authentication' -Test {
    $result = Invoke-ScriptProcess -Arguments @('12345,23456') -RemovedEnvironmentVariables @('GH_TOKEN', 'GITHUB_TOKEN', 'APPDATA')
    Confirm-Condition -Condition ($result.exitCode -eq 1) -Message 'expected exit code 1'
    Confirm-Condition -Condition ([string]::IsNullOrWhiteSpace($result.standardOutput)) -Message 'authentication failure emitted success output'
    Confirm-Condition -Condition ($result.standardError -match '(?m)^  AUTHENTICATION \| ERROR: GitHub token was not found') -Message 'authentication error is missing'
}

Invoke-TestCase -Name 'nested-invalid-invocation' -Test {
    $standardError = [Console]::Error
    try {
        [Console]::SetError([IO.TextWriter]::Null)
        $output = @(& $targetScriptPath -Foo bar) | Out-String
    }
    finally {
        [Console]::SetError($standardError)
    }

    $plainOutput = $output -replace "`e\[[0-9;]*m", ''
    Confirm-Condition -Condition ($plainOutput -match '(?m)^  USAGE:') -Message 'nested help output is missing'
}

Invoke-TestCase -Name 'populated-ready-field' -Test {
    $fieldValue = [pscustomobject]@{
        name = 'ready'
        createdAt = '2026-01-01T00:00:00Z'
        updatedAt = '2026-01-02T00:00:00Z'
        creator = [pscustomobject]@{ login = 'example-user' }
    }
    $result = Invoke-MockedLookup -FieldValue $fieldValue
    Confirm-Condition -Condition ($result.Number -eq 12345) -Message 'PR number does not match'
    Confirm-Condition -Condition ($result.ReadyValue -eq 'ready') -Message 'ready value does not match'
    Confirm-Condition -Condition ($result.ChangedBy -eq 'example-user') -Message 'contributor does not match'
}

Invoke-TestCase -Name 'cleared-ready-field' -Test {
    $result = Invoke-MockedLookup -FieldValue $null
    Confirm-Condition -Condition ($result.Number -eq 12345) -Message 'PR number does not match'
    Confirm-Condition -Condition ($null -eq $result.ReadyValue) -Message 'ready value should be null'
    Confirm-Condition -Condition ($null -eq $result.ChangedBy) -Message 'contributor should be null'
    Confirm-Condition -Condition ($null -eq $result.CreatedAt) -Message 'created timestamp should be null'
    Confirm-Condition -Condition ($null -eq $result.UpdatedAt) -Message 'updated timestamp should be null'
}

Invoke-TestCase -Name 'multiple-ready-fields' -Test {
    $result = Invoke-MockedBatchLookup -PullRequestNumbers 12345,23456
    Confirm-Condition -Condition (($result.results.Number -join ',') -eq '12345,23456') -Message 'results do not preserve input order'
    Confirm-Condition -Condition (($result.calls -join ',') -eq '12345,23456') -Message 'lookup calls do not preserve input order'
    Confirm-Condition -Condition ([string]::IsNullOrWhiteSpace($result.error)) -Message 'successful batch wrote an error'
}

Invoke-TestCase -Name 'non-numeric-order-is-preserved' -Test {
    $result = Invoke-MockedBatchLookup -PullRequestNumbers 34567,12345,23456
    Confirm-Condition -Condition (($result.results.Number -join ',') -eq '34567,12345,23456') -Message 'results were sorted instead of preserving input order'
    Confirm-Condition -Condition (($result.calls -join ',') -eq '34567,12345,23456') -Message 'lookup calls were sorted instead of preserving input order'
}

Invoke-TestCase -Name 'whitespace-in-pr-number-list' -Test {
    $result = Invoke-MockedBatchLookup -PullRequestNumbers '12345, 23456'
    Confirm-Condition -Condition (($result.results.Number -join ',') -eq '12345,23456') -Message 'whitespace changed result order'
    Confirm-Condition -Condition (($result.calls -join ',') -eq '12345,23456') -Message 'whitespace changed lookup calls'
}

Invoke-TestCase -Name 'mixed-batch-continues-and-deduplicates' -Test {
    $result = Invoke-MockedBatchLookup -PullRequestNumbers '12345,99999,23456,12345' -MissingPullRequestNumbers 99999
    Confirm-Condition -Condition (($result.results.Number -join ',') -eq '12345,23456') -Message 'successful results do not preserve input order after a failure'
    Confirm-Condition -Condition (($result.calls -join ',') -eq '12345,99999,23456') -Message 'lookup calls are not ordered and deduplicated'
    Confirm-Condition -Condition ($result.error -match 'PR 99999 \| ERROR: Pull request was not found') -Message 'existing contextual PR error is missing'
}

Invoke-TestCase -Name 'all-failure-batch' -Test {
    $result = Invoke-MockedBatchLookup -PullRequestNumbers '99998,99999' -MissingPullRequestNumbers 99998,99999
    Confirm-Condition -Condition ($result.results.Count -eq 0) -Message 'all-failure batch emitted success output'
    Confirm-Condition -Condition (($result.calls -join ',') -eq '99998,99999') -Message 'all-failure batch did not attempt every PR'
    Confirm-Condition -Condition ($result.error -match 'PR 99998 \| ERROR: Pull request was not found') -Message 'first PR error is missing'
    Confirm-Condition -Condition ($result.error -match 'PR 99999 \| ERROR: Pull request was not found') -Message 'second PR error is missing'
}

Invoke-TestCase -Name 'mid-batch-authentication-failure' -Test {
    $result = Invoke-MockedBatchLookup -PullRequestNumbers '12345,99999,23456' -AuthenticationFailureNumbers 99999
    Confirm-Condition -Condition (($result.results.Number -join ',') -eq '12345') -Message 'authentication failure emitted later success output'
    Confirm-Condition -Condition (($result.calls -join ',') -eq '12345,99999') -Message 'lookups continued after authentication failure'
    Confirm-Condition -Condition ($result.error -match 'AUTHENTICATION \| ERROR: GitHub GraphQL query failed: Unauthorized request \(403\)\.') -Message 'authentication error is missing'
}

Write-Output ''
Write-Output 'PR readiness utility test summary'
Write-Output ("  Tests : {0}" -f $testCount)
Write-Output ("  Issues: {0}" -f $issues.Count)

if ($issues.Count -gt 0) {
    Write-Output ''
    foreach ($issue in $issues) {
        Write-Output ("  - {0}" -f $issue)
    }

    throw 'PR readiness utility regression tests failed'
}

$global:LASTEXITCODE = 0
