[CmdletBinding()]
param(
    [string]$HostedRoot = (Join-Path $PSScriptRoot '..'),

    [ValidateSet('Text', 'Json')]
    [string]$OutputFormat = 'Text'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$validationOutputModulePath = Join-Path $PSScriptRoot '../../tools/ValidationOutput.psm1'
Import-Module -Name $validationOutputModulePath -Force

$resolvedHostedRoot = [IO.Path]::GetFullPath($HostedRoot)
$estimator = 'character-quarter-estimate-25pct-v1'
$safetyMarginPercent = 25
$fileSpecs = @(
    [pscustomobject]@{ name = 'repository'; path = '.github/copilot-instructions.md'; budgetTokens = 2000 },
    [pscustomobject]@{ name = 'go'; path = '.github/instructions/azurerm-go.instructions.md'; budgetTokens = 8000 },
    [pscustomobject]@{ name = 'test'; path = '.github/instructions/azurerm-tests.instructions.md'; budgetTokens = 4000 },
    [pscustomobject]@{ name = 'documentation'; path = '.github/instructions/azurerm-docs.instructions.md'; budgetTokens = 8000 },
    [pscustomobject]@{ name = 'skill'; path = '.github/skills/code-review/SKILL.md'; budgetTokens = 3000 }
)
$combinedSpecs = @(
    [pscustomobject]@{ name = 'go-combined'; members = @('repository', 'go', 'skill'); budgetTokens = 25000 },
    [pscustomobject]@{ name = 'test-combined'; members = @('repository', 'go', 'test', 'skill'); budgetTokens = 25000 },
    [pscustomobject]@{ name = 'documentation-combined'; members = @('repository', 'documentation', 'skill'); budgetTokens = 25000 }
)

function New-CapacityReport {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][ValidateSet('file', 'combined')][string]$Kind,
        [Parameter(Mandatory = $true)][string[]]$Paths,
        [Parameter(Mandatory = $true)][long]$CharacterCount,
        [Parameter(Mandatory = $true)][long]$EstimatedTokens,
        [Parameter(Mandatory = $true)][long]$GuardedTokens,
        [Parameter(Mandatory = $true)][long]$BudgetTokens
    )

    return [pscustomobject]@{
        name = $Name
        kind = $Kind
        paths = $Paths
        characterCount = $CharacterCount
        estimatedTokens = $EstimatedTokens
        guardedTokens = $GuardedTokens
        budgetTokens = $BudgetTokens
        budgetHeadroomTokens = $BudgetTokens - $GuardedTokens
        utilizationPercent = [Math]::Round(($GuardedTokens / $BudgetTokens) * 100, 2)
        withinBudget = $GuardedTokens -le $BudgetTokens
    }
}

$reports = New-Object 'System.Collections.Generic.List[object]'
$reportsByName = @{}
foreach ($spec in $fileSpecs) {
    $path = [IO.Path]::GetFullPath((Join-Path $resolvedHostedRoot ([string]$spec.path)))
    $rootPrefix = $resolvedHostedRoot.TrimEnd([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar) + [IO.Path]::DirectorySeparatorChar
    if (-not $path.StartsWith($rootPrefix, [StringComparison]::OrdinalIgnoreCase)) {
        throw "Guidance path escapes HostedRoot: $($spec.path)"
    }
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        throw "Hosted guidance file was not found: $path"
    }

    $characterCount = [IO.File]::ReadAllText($path).Length
    $estimatedTokens = [long][Math]::Ceiling($characterCount / 4)
    $guardedTokens = [long][Math]::Ceiling($estimatedTokens * 1.25)
    $report = New-CapacityReport -Name $spec.name -Kind file -Paths @([string]$spec.path) -CharacterCount $characterCount -EstimatedTokens $estimatedTokens -GuardedTokens $guardedTokens -BudgetTokens $spec.budgetTokens
    $reports.Add($report)
    $reportsByName[[string]$spec.name] = $report
}

foreach ($spec in $combinedSpecs) {
    $members = @($spec.members | ForEach-Object { $reportsByName[[string]$_] })
    $report = New-CapacityReport -Name $spec.name -Kind combined -Paths @($members | ForEach-Object { $_.paths }) -CharacterCount (($members | Measure-Object characterCount -Sum).Sum) -EstimatedTokens (($members | Measure-Object estimatedTokens -Sum).Sum) -GuardedTokens (($members | Measure-Object guardedTokens -Sum).Sum) -BudgetTokens $spec.budgetTokens
    $reports.Add($report)
    $reportsByName[[string]$spec.name] = $report
}

$result = [ordered]@{
    status = if (@($reports | Where-Object { -not $_.withinBudget }).Count -eq 0) { 'passed' } else { 'failed' }
    estimator = $estimator
    safetyMarginPercent = $safetyMarginPercent
    reportCount = $reports.Count
    reports = $reports.ToArray()
}

if ($OutputFormat -eq 'Json') {
    $result | ConvertTo-Json -Depth 8
}
else {
    Write-ValidationSectionHeader -Title 'Hosted guidance capacity'
    Write-ValidationSummary -Fields ([ordered]@{
        Status = $result.status.ToUpperInvariant()
        Estimator = $result.estimator
        'Safety Margin' = "$($result.safetyMarginPercent)%"
        Reports = $result.reportCount
    })
    Write-ValidationSectionHeader -Title 'Capacity reports'
    $rows = @($reports | ForEach-Object {
        [pscustomobject]@{
            surface = $_.name
            capacity = "$($_.guardedTokens) / $($_.budgetTokens) guarded tokens; $($_.budgetHeadroomTokens) headroom"
        }
    })
    Write-ValidationTwoColumnTable -Rows $rows -FirstHeader 'surface' -FirstProperty 'surface' -SecondHeader 'capacity' -SecondProperty 'capacity'
    Complete-ValidationTextOutput
}

if ($result.status -eq 'failed') {
    exit 1
}
