[CmdletBinding()]
param(
    [ValidateSet('Text', 'Json')]
    [string]$OutputFormat = 'Text'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$validationOutputModulePath = Join-Path $PSScriptRoot '../../tools/ValidationOutput.psm1'
Import-Module -Name $validationOutputModulePath -Force

$hostedRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$generatorPath = Join-Path $PSScriptRoot 'Generate-Instructions.ps1'
$sourceCatalogPath = Join-Path $hostedRoot 'rules/instruction-catalog.json'
$sourceSchemaPath = Join-Path $hostedRoot 'rules/instruction-catalog.schema.json'
$results = New-Object 'System.Collections.Generic.List[object]'
$issues = New-Object 'System.Collections.Generic.List[string]'
$tempRoot = Join-Path ([IO.Path]::GetTempPath()) ("hosted-instruction-generation-{0}" -f [Guid]::NewGuid().ToString('N'))

function Add-TestResult {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name,

        [Parameter(Mandatory = $true)]
        [bool]$Passed,

        [Parameter(Mandatory = $true)]
        [string]$Detail
    )

    $results.Add([pscustomobject]@{
        name = $Name
        status = if ($Passed) { 'passed' } else { 'failed' }
        detail = $Detail
    })
    if (-not $Passed) {
        $issues.Add("$Name`: $Detail")
    }
}

function Invoke-Generator {
    param([switch]$Write)

    $arguments = @(
        '-NoProfile',
        '-File', $generatorPath,
        '-CatalogPath', (Join-Path $tempRoot 'rules/instruction-catalog.json'),
        '-HostedRoot', $tempRoot,
        '-OutputFormat', 'Json'
    )
    if ($Write) {
        $arguments += '-Write'
    }

    $global:LASTEXITCODE = 0
    $output = @(& pwsh @arguments 2>&1)
    $exitCode = if ($null -ne $LASTEXITCODE) { $LASTEXITCODE } else { 0 }
    $global:LASTEXITCODE = 0

    [pscustomobject]@{
        exitCode = $exitCode
        output = ($output | Out-String).Trim()
    }
}

try {
    $rulesDirectory = Join-Path $tempRoot 'rules'
    New-Item -ItemType Directory -Path $rulesDirectory -Force | Out-Null
    Copy-Item -LiteralPath $sourceCatalogPath -Destination (Join-Path $rulesDirectory 'instruction-catalog.json')
    Copy-Item -LiteralPath $sourceSchemaPath -Destination (Join-Path $rulesDirectory 'instruction-catalog.schema.json')

    $catalog = Get-Content -LiteralPath $sourceCatalogPath -Raw | ConvertFrom-Json
    foreach ($surface in @($catalog.surfaces)) {
        $sourcePath = Join-Path $hostedRoot ([string]$surface.outputPath)
        $targetPath = Join-Path $tempRoot ([string]$surface.outputPath)
        New-Item -ItemType Directory -Path (Split-Path -Parent $targetPath) -Force | Out-Null
        Copy-Item -LiteralPath $sourcePath -Destination $targetPath
    }

    $baseline = Invoke-Generator
    Add-TestResult -Name 'baseline-freshness' -Passed ($baseline.exitCode -eq 0) -Detail $(if ($baseline.exitCode -eq 0) { 'Current catalog reproduces all committed instruction files.' } else { $baseline.output })

    $tempCatalogPath = Join-Path $rulesDirectory 'instruction-catalog.json'
    $catalog.rules[0].origin = 'hosted-catalog-addition'
    $catalog | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $tempCatalogPath -Encoding utf8NoBOM
    $catalogAddition = Invoke-Generator
    Add-TestResult -Name 'catalog-addition-origin' -Passed ($catalogAddition.exitCode -eq 0) -Detail $(if ($catalogAddition.exitCode -eq 0) { 'Catalog-native rule origin passes schema validation without changing output.' } else { $catalogAddition.output })

    $firstOutputPath = Join-Path $tempRoot ([string]$catalog.surfaces[0].outputPath)
    $beforeStaleHash = (Get-FileHash -LiteralPath $firstOutputPath -Algorithm SHA256).Hash
    $catalog.rules[0].text = "$($catalog.rules[0].text) Regression probe."
    $catalog | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $tempCatalogPath -Encoding utf8NoBOM
    $staleCheck = Invoke-Generator
    $afterStaleHash = (Get-FileHash -LiteralPath $firstOutputPath -Algorithm SHA256).Hash
    $staleReadOnlyPassed = $staleCheck.exitCode -ne 0 -and $beforeStaleHash -eq $afterStaleHash
    Add-TestResult -Name 'stale-check-read-only' -Passed $staleReadOnlyPassed -Detail $(if ($staleReadOnlyPassed) { 'Check mode detects stale output without modifying it.' } else { 'Check mode did not fail read-only for stale output.' })

    $writeResult = Invoke-Generator -Write
    $afterWriteHash = (Get-FileHash -LiteralPath $firstOutputPath -Algorithm SHA256).Hash
    $writePassed = $writeResult.exitCode -eq 0 -and $afterWriteHash -ne $beforeStaleHash
    Add-TestResult -Name 'explicit-write' -Passed $writePassed -Detail $(if ($writePassed) { 'Write mode updates stale generated output explicitly.' } else { $writeResult.output })
}
catch {
    $issues.Add($_.Exception.Message)
}
finally {
    Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
}

$result = [ordered]@{
    status = if ($issues.Count -eq 0) { 'passed' } else { 'failed' }
    testCount = $results.Count
    issueCount = $issues.Count
    tests = $results.ToArray()
    issues = $issues.ToArray()
}

if ($OutputFormat -eq 'Json') {
    $result | ConvertTo-Json -Depth 6
}
else {
    Write-ValidationSectionHeader -Title 'Hosted instruction generation test summary'
    Write-ValidationSummary -Fields ([ordered]@{
        Status = $result.status.ToUpperInvariant()
        Tests = $result.testCount
        'Issue Count' = $result.issueCount
    })
    Write-ValidationSectionHeader -Title 'Generation tests'
    Write-ValidationTwoColumnTable -Rows @($results.ToArray()) -FirstHeader 'status' -FirstProperty 'status' -SecondHeader 'test' -SecondProperty 'name' -UppercaseFirst
    if ($issues.Count -gt 0) {
        Write-ValidationSectionHeader -Title 'Issues'
        foreach ($issue in $issues) {
            Write-Output "  - $issue"
        }
    }
    Complete-ValidationTextOutput
}

if ($result.status -eq 'failed') {
    exit 1
}
