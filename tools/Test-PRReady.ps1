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
        [string[]]$Arguments = @()
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

Invoke-TestCase -Name 'nested-invalid-invocation' -Test {
    $standardError = [Console]::Error
    try {
        [Console]::SetError([IO.TextWriter]::Null)
        $output = @(& $targetScriptPath -Foo bar) | Out-String
    }
    finally {
        [Console]::SetError($standardError)
    }

    Confirm-Condition -Condition ($output -match '(?m)^  USAGE:') -Message 'nested help output is missing'
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
