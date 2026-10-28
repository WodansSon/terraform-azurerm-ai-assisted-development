Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Import-Module (Join-Path $PSScriptRoot 'HostedToolkit.Helpers.psm1')

function Resolve-HostedAdoptionPath {
    param([Parameter(Mandatory)][string]$HostedRoot, [Parameter(Mandatory)][string]$RelativePath)

    if ([IO.Path]::IsPathRooted($RelativePath) -or $RelativePath.Contains('\') -or @($RelativePath.Split('/') | Where-Object { $_ -in @('', '.', '..') }).Count) {
        throw 'Adoption paths must remain Hosted-root-relative without empty or dot segments'
    }
    $root = [IO.Path]::GetFullPath($HostedRoot).TrimEnd([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar)
    $path = [IO.Path]::GetFullPath((Join-Path $root $RelativePath))
    if (-not $path.StartsWith($root + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) { throw 'Adoption path escapes HostedRoot' }
    $current = $path
    while ($current.Length -ge $root.Length) {
        if ((Test-Path -LiteralPath $current) -and ((Get-Item -LiteralPath $current -Force).Attributes -band [IO.FileAttributes]::ReparsePoint)) { throw 'Adoption paths cannot traverse symbolic links or junctions' }
        if ($current -ceq $root) { break }
        $current = Split-Path -Parent $current
    }
    return $path
}

function Get-HostedAdoptionConfiguration {
    param([Parameter(Mandatory)][string]$HostedRoot, [string]$DescriptorPath = 'tools/config/adoption.json')

    $root = [IO.Path]::GetFullPath($HostedRoot)
    $path = Resolve-HostedAdoptionPath -HostedRoot $root -RelativePath $DescriptorPath
    $json = Get-Content -LiteralPath $path -Raw
    $schemaPath = Join-Path $PSScriptRoot '../../../contracts/adoption/repository-adoption.schema.json'
    if (-not (Test-Json -Json $json -SchemaFile $schemaPath -ErrorAction SilentlyContinue)) { throw 'Adoption descriptor does not satisfy its schema' }
    $descriptor = $json | ConvertFrom-Json -Depth 50
    foreach ($reference in @($descriptor.sourceDefinitionSet, $descriptor.catalog, $descriptor.protectedRules)) {
        $null = Resolve-HostedAdoptionPath -HostedRoot $root -RelativePath $reference
    }
    return [pscustomobject]@{ hostedRoot = $root; descriptorPath = $path; descriptor = $descriptor }
}

function Get-HostedTokenPolicy {
    param([Parameter(Mandatory)][object]$Configuration)

    $descriptor = $Configuration.descriptor
    $catalogPath = Resolve-HostedAdoptionPath -HostedRoot $Configuration.hostedRoot -RelativePath $descriptor.catalog
    $catalog = Get-Content -LiteralPath $catalogPath -Raw | ConvertFrom-Json -Depth 100
    $names = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    $paths = [Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    $areas = [Collections.Generic.List[object]]::new()
    foreach ($area in $descriptor.tokenPolicy.areas) {
        if (-not $names.Add($area.name)) { throw 'Token policy contains duplicate report names' }
        $relativePath = if ($area.PSObject.Properties['surfaceId']) {
            $surfaces = @($catalog.surfaces | Where-Object id -CEQ $area.surfaceId)
            if ($surfaces.Count -ne 1) { throw 'Token policy surface must identify exactly one catalog surface' }
            [string]$surfaces[0].outputPath
        }
        else { [string]$area.path }
        $null = Resolve-HostedAdoptionPath -HostedRoot $Configuration.hostedRoot -RelativePath $relativePath
        if (-not $paths.Add($relativePath)) { throw 'Token policy cannot count a guidance file more than once' }
        if ($area.budgetTokens -gt $descriptor.tokenPolicy.maximumGuidanceTokens) { throw 'Area budget exceeds the overall guidance ceiling' }
        $areas.Add([pscustomobject][ordered]@{ name = $area.name; path = $relativePath; budgetTokens = $area.budgetTokens })
    }
    foreach ($surface in $catalog.surfaces) {
        if (-not $paths.Contains([string]$surface.outputPath)) { throw 'Token policy must account for every deployed catalog surface' }
    }
    $areaNames = @($areas.name)
    foreach ($combination in $descriptor.tokenPolicy.combinations) {
        if (-not $names.Add($combination.name)) { throw 'Token policy contains duplicate report names' }
        if (@($combination.members | Where-Object { $_ -cnotin $areaNames }).Count) { throw 'Token policy combination references an unknown area' }
        if ($combination.budgetTokens -gt $descriptor.tokenPolicy.maximumGuidanceTokens) { throw 'Combined budget exceeds the overall guidance ceiling' }
    }
    $policy = [ordered]@{
        estimator = $descriptor.tokenPolicy.estimator
        safetyMarginPercent = $descriptor.tokenPolicy.safetyMarginPercent
        maximumGuidanceTokens = $descriptor.tokenPolicy.maximumGuidanceTokens
        areas = $areas.ToArray()
        combinations = @($descriptor.tokenPolicy.combinations)
    }
    return [pscustomobject]@{ policy = [pscustomobject]$policy; sha256 = Get-JsonSnapshotSha256 -Value $policy }
}

function Assert-HostedGuidanceCapacity {
    param([Parameter(Mandatory)][object]$Capacity, [Parameter(Mandatory)][object]$TokenPolicy)

    $policy = $TokenPolicy.policy
    $json = $Capacity | ConvertTo-Json -Depth 50
    if (-not (Test-Json -Json $json -SchemaFile (Join-Path $PSScriptRoot '../../../contracts/catalog/guidance-capacity.schema.json') -ErrorAction SilentlyContinue)) { throw 'Guidance capacity does not satisfy its schema' }
    if ($Capacity.tokenPolicySha256 -cne $TokenPolicy.sha256 -or $Capacity.estimator -cne $policy.estimator -or $Capacity.safetyMarginPercent -ne $policy.safetyMarginPercent -or $Capacity.maximumGuidanceTokens -ne $policy.maximumGuidanceTokens) { throw 'Guidance capacity does not bind the current token policy' }
    $specs = @($policy.areas) + @($policy.combinations)
    if ($Capacity.reportCount -ne $specs.Count -or @($Capacity.reports).Count -ne $specs.Count) { throw 'Guidance capacity must cover every configured report exactly once' }
    $reports = @{}
    foreach ($report in $Capacity.reports) {
        if ($reports.ContainsKey($report.name)) { throw 'Guidance capacity contains duplicate reports' }
        $reports[$report.name] = $report
    }
    foreach ($spec in $specs) {
        if (-not $reports.ContainsKey($spec.name)) { throw 'Guidance capacity omitted a configured report' }
        $report = $reports[$spec.name]
        if ($spec.PSObject.Properties['path']) {
            $kind = 'file'; $paths = @($spec.path)
            $estimated = [long][Math]::Ceiling($report.characterCount / 4.0)
            $guarded = [long][Math]::Ceiling($estimated * (1 + $policy.safetyMarginPercent / 100.0))
        }
        else {
            $kind = 'combined'
            $members = @($spec.members | ForEach-Object { $reports[$_] })
            $paths = @($members | ForEach-Object { $_.paths })
            if ($report.characterCount -ne ($members | Measure-Object characterCount -Sum).Sum) { throw 'Combined character counts do not match configured members' }
            $estimated = [long]($members | Measure-Object estimatedTokens -Sum).Sum
            $guarded = [long]($members | Measure-Object guardedTokens -Sum).Sum
        }
        if ($report.kind -cne $kind -or ($report.paths -join "`n") -cne ($paths -join "`n") -or $report.budgetTokens -ne $spec.budgetTokens -or $report.estimatedTokens -ne $estimated -or $report.guardedTokens -ne $guarded -or $report.budgetHeadroomTokens -ne ($spec.budgetTokens - $guarded) -or $report.withinBudget -ne ($guarded -le $spec.budgetTokens) -or $report.utilizationPercent -ne [Math]::Round($guarded / $spec.budgetTokens * 100, 2)) { throw 'Guidance capacity report does not match its configured allocation' }
    }
    $total = [long](@($policy.areas | ForEach-Object { $reports[$_.name] }) | Measure-Object guardedTokens -Sum).Sum
    $status = if ($total -le $policy.maximumGuidanceTokens -and @($Capacity.reports | Where-Object { -not $_.withinBudget }).Count -eq 0) { 'passed' } else { 'failed' }
    if ($Capacity.totalGuardedTokens -ne $total -or $Capacity.status -cne $status) { throw 'Guidance capacity overall accounting is inconsistent' }
}

Export-ModuleMember -Function Resolve-HostedAdoptionPath, Get-HostedAdoptionConfiguration, Get-HostedTokenPolicy, Assert-HostedGuidanceCapacity
