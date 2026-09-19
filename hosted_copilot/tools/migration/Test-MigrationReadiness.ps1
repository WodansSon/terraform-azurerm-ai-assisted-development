[CmdletBinding()]
param(
    [ValidateSet('Text', 'Json')]
    [string]$OutputFormat = 'Text'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$repoRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))
$validationOutputModulePath = Join-Path $repoRoot 'tools/ValidationOutput.psm1'
Import-Module -Name $validationOutputModulePath -Force

$reconciliationRoot = Join-Path $repoRoot 'hosted_copilot/copilot-rule-catalog/assessment-reconciliation'
$compatibilitySchemaPath = Join-Path $reconciliationRoot 'version-3-field-compatibility.schema.json'
$compatibilityPath = Join-Path $reconciliationRoot 'version-3-field-compatibility.json'
$retirementSchemaPath = Join-Path $reconciliationRoot 'version-3-retirement-inventory.schema.json'
$retirementPath = Join-Path $reconciliationRoot 'version-3-retirement-inventory.json'
$commandSurfaceSchemaPath = Join-Path $PSScriptRoot 'tool-command-surface.schema.json'
$commandSurfacePath = Join-Path $PSScriptRoot 'tool-command-surface.json'
$commandMapPath = Join-Path $PSScriptRoot '../README.md'
$ruleIntakeReviewSchemaPath = Join-Path $repoRoot 'hosted_copilot/copilot-rule-catalog/rule-intake-review.schema.json'
$baselineSchemaPath = Join-Path $repoRoot 'hosted_copilot/copilot-rule-catalog/rule-assessments/assessment-baseline.schema.json'
$catalogPath = Join-Path $repoRoot 'hosted_copilot/copilot-rule-catalog/instruction-catalog.json'
$seedRelativePath = 'local-only-docs/HOSTED_ORIGINAL_54_RULES_SEED.json'
$seedPath = Join-Path $repoRoot $seedRelativePath
$acceptedCommit = '97b08a2a80ed6ca23e7a6ce5d17b878f70c20bbc'
$acceptedCatalogPath = 'hosted_copilot/copilot-rule-catalog/instruction-catalog.json'
$acceptedRepository = 'https://github.com/WodansSon/terraform-azurerm-ai-assisted-development'
$acceptedPullRequest = 43
$expectedRuleCount = 54
$expectedLegacyTupleCount = 37

$results = [Collections.Generic.List[object]]::new()
$issues = [Collections.Generic.List[string]]::new()
$script:compatibility = $null
$script:retirement = $null
$script:commandSurface = $null
$script:seed = $null
$script:baselineCatalog = $null
$script:currentCatalog = $null

function Add-TestResult {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][bool]$Passed,
        [Parameter(Mandatory = $true)][string]$Detail
    )

    $results.Add([pscustomobject]@{ name = $Name; status = if ($Passed) { 'passed' } else { 'failed' }; detail = $Detail })
    if (-not $Passed) {
        $issues.Add("$Name`: $Detail")
    }
}

function Invoke-ReadinessTest {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][string]$SuccessDetail,
        [Parameter(Mandatory = $true)][scriptblock]$Action
    )

    try {
        & $Action
        Add-TestResult -Name $Name -Passed $true -Detail $SuccessDetail
    }
    catch {
        Add-TestResult -Name $Name -Passed $false -Detail $_.Exception.Message
    }
}

function Assert-OrdinalEntries {
    param(
        [Parameter(Mandatory = $true)][object[]]$Entries,
        [Parameter(Mandatory = $true)][string]$Name
    )

    $duplicateIds = @($Entries | Group-Object id | Where-Object Count -gt 1)
    if ($duplicateIds.Count -gt 0) {
        throw "$Name contains duplicate IDs: $(@($duplicateIds.Name) -join ', ')"
    }
    for ($index = 0; $index -lt $Entries.Count; $index++) {
        $expected = $index + 1
        if ([int]$Entries[$index].ordinal -ne $expected) {
            throw "$Name entry $($Entries[$index].id) has ordinal $($Entries[$index].ordinal); expected $expected"
        }
    }
}

function Assert-RequiredValues {
    param(
        [Parameter(Mandatory = $true)][string[]]$Expected,
        [Parameter(Mandatory = $true)][string[]]$Actual,
        [Parameter(Mandatory = $true)][string]$Name
    )

    $difference = @(Compare-Object -ReferenceObject @($Expected | Sort-Object) -DifferenceObject @($Actual | Sort-Object))
    if ($difference.Count -gt 0) {
        throw "$Name mismatch: $($difference | ForEach-Object { "$($_.SideIndicator)$($_.InputObject)" } | Out-String)"
    }
}

function Assert-EvidencePaths {
    param([Parameter(Mandatory = $true)][object[]]$Entries)

    foreach ($entry in $Entries) {
        $paths = @([string]$entry.currentOwnerPath) + @($entry.evidencePaths | ForEach-Object { [string]$_ })
        foreach ($relativePath in $paths) {
            if ($relativePath.Contains('\') -or [IO.Path]::IsPathRooted($relativePath) -or $relativePath -match '(?:^|/)\.\.(?:/|$)') {
                throw "Entry $($entry.id) contains a non-repository-relative path: $relativePath"
            }
            $fullPath = [IO.Path]::GetFullPath((Join-Path $repoRoot $relativePath))
            $repoPrefix = $repoRoot.TrimEnd([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar) + [IO.Path]::DirectorySeparatorChar
            if (-not $fullPath.StartsWith($repoPrefix, [StringComparison]::OrdinalIgnoreCase) -or -not (Test-Path -LiteralPath $fullPath)) {
                throw "Entry $($entry.id) references a missing or escaping evidence path: $relativePath"
            }
        }
    }
}

function Get-ReachableSchemaPropertyPaths {
    param(
        [Parameter(Mandatory = $true)][object]$RootSchema,
        [Parameter(Mandatory = $true)][object]$Node,
        [string]$Prefix = ''
    )

    $paths = [Collections.Generic.List[string]]::new()
    if ($null -ne $Node.PSObject.Properties['$ref']) {
        $reference = [string]$Node.'$ref'
        if ($reference -notmatch '^#\/\$defs\/(?<name>[^/]+)$') {
            throw "Unsupported local schema reference: $reference"
        }
        $definition = $RootSchema.'$defs'.PSObject.Properties[$Matches.name].Value
        foreach ($path in @(Get-ReachableSchemaPropertyPaths -RootSchema $RootSchema -Node $definition -Prefix $Prefix)) {
            $paths.Add($path)
        }
        return $paths.ToArray()
    }
    if ($null -ne $Node.PSObject.Properties['properties']) {
        foreach ($property in $Node.properties.PSObject.Properties) {
            $path = if ([string]::IsNullOrEmpty($Prefix)) { $property.Name } else { "$Prefix.$($property.Name)" }
            $paths.Add($path)
            foreach ($childPath in @(Get-ReachableSchemaPropertyPaths -RootSchema $RootSchema -Node $property.Value -Prefix $path)) {
                $paths.Add($childPath)
            }
        }
    }
    if ($null -ne $Node.PSObject.Properties['items']) {
        foreach ($childPath in @(Get-ReachableSchemaPropertyPaths -RootSchema $RootSchema -Node $Node.items -Prefix "$Prefix[]")) {
            $paths.Add($childPath)
        }
    }
    return $paths.ToArray()
}

function Get-OrderedRuleJson {
    param([Parameter(Mandatory = $true)][object[]]$Rules)

    return @($Rules | ForEach-Object { $_ | ConvertTo-Json -Depth 100 -Compress })
}

function Assert-OrderedRulesEqual {
    param(
        [Parameter(Mandatory = $true)][object[]]$Expected,
        [Parameter(Mandatory = $true)][object[]]$Actual,
        [Parameter(Mandatory = $true)][string]$Name
    )

    $expectedJson = @(Get-OrderedRuleJson -Rules $Expected)
    $actualJson = @(Get-OrderedRuleJson -Rules $Actual)
    if ($expectedJson.Count -ne $actualJson.Count) {
        throw "$Name rule count differs: expected $($expectedJson.Count), actual $($actualJson.Count)"
    }
    for ($index = 0; $index -lt $expectedJson.Count; $index++) {
        if ($expectedJson[$index] -cne $actualJson[$index]) {
            throw "$Name first differs at ordered rule index $index"
        }
    }
}

function Get-LegacyTuples {
    param([Parameter(Mandatory = $true)][object[]]$Rules)

    return @($Rules | ForEach-Object {
        $rule = $_
        @($rule.sourceIds) | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) } | ForEach-Object {
            "{0}`0{1}" -f [string]$_, [string]$rule.id
        }
    })
}

Invoke-ReadinessTest -Name 'inventory-schema-validation' -SuccessDetail 'Both Phase 0 inventories satisfy strict Draft 2020-12 schemas.' -Action {
    foreach ($pair in @(
        @{ Data = $compatibilityPath; Schema = $compatibilitySchemaPath },
        @{ Data = $retirementPath; Schema = $retirementSchemaPath }
    )) {
        $content = Get-Content -LiteralPath $pair.Data -Raw
        if (-not ($content | Test-Json -SchemaFile $pair.Schema -ErrorAction Stop)) {
            throw "Schema validation failed: $($pair.Data)"
        }
    }
    $script:compatibility = Get-Content -LiteralPath $compatibilityPath -Raw | ConvertFrom-Json
    $script:retirement = Get-Content -LiteralPath $retirementPath -Raw | ConvertFrom-Json
}

Invoke-ReadinessTest -Name 'inventory-order-and-identity' -SuccessDetail 'Inventory IDs are unique and entries use contiguous deterministic ordinals.' -Action {
    Assert-OrdinalEntries -Entries @($script:compatibility.entries) -Name 'Field compatibility inventory'
    Assert-OrdinalEntries -Entries @($script:retirement.entries) -Name 'Retirement inventory'
}

Invoke-ReadinessTest -Name 'inventory-evidence-paths' -SuccessDetail 'Every current owner and evidence path exists beneath the repository root.' -Action {
    Assert-EvidencePaths -Entries @($script:compatibility.entries)
    Assert-EvidencePaths -Entries @($script:retirement.entries)
}

Invoke-ReadinessTest -Name 'command-surface-schema-validation' -SuccessDetail 'The Phase 2.5 command-surface move plan satisfies its strict schema.' -Action {
    $content = Get-Content -LiteralPath $commandSurfacePath -Raw
    if (-not ($content | Test-Json -SchemaFile $commandSurfaceSchemaPath -ErrorAction Stop)) {
        throw 'Command-surface move plan schema validation failed'
    }
    $script:commandSurface = $content | ConvertFrom-Json
    $entries = @($script:commandSurface.entries)
    $duplicatePaths = @($entries | Group-Object currentPath | Where-Object Count -gt 1)
    if ($duplicatePaths.Count -gt 0) {
        throw "Command-surface move plan repeats current paths: $(@($duplicatePaths.Name) -join ', ')"
    }
    for ($index = 0; $index -lt $entries.Count; $index++) {
        $expectedOrdinal = $index + 1
        if ([int]$entries[$index].ordinal -ne $expectedOrdinal) {
            throw "Command-surface entry $($entries[$index].currentPath) has ordinal $($entries[$index].ordinal); expected $expectedOrdinal"
        }
    }
}

Invoke-ReadinessTest -Name 'command-surface-exact-coverage' -SuccessDetail 'Every repository-owned PowerShell file is classified exactly once with one valid Phase 2.5 destination.' -Action {
    $toolsRoot = Join-Path $repoRoot 'hosted_copilot/tools'
    $actualPaths = @(Get-ChildItem -LiteralPath $toolsRoot -Recurse -File | Where-Object {
        $_.Extension -in @('.ps1', '.psm1') -and $_.FullName -notlike "*$([IO.Path]::DirectorySeparatorChar)node_modules$([IO.Path]::DirectorySeparatorChar)*"
    } | ForEach-Object { [IO.Path]::GetRelativePath($repoRoot, $_.FullName).Replace('\', '/') } | Sort-Object)
    $declaredPaths = @($script:commandSurface.entries.currentPath | ForEach-Object { [string]$_ } | Sort-Object)
    Assert-RequiredValues -Expected $actualPaths -Actual $declaredPaths -Name 'Command-surface file coverage'

    $duplicatePlannedPaths = @($script:commandSurface.entries | Group-Object plannedPath | Where-Object Count -gt 1)
    if ($duplicatePlannedPaths.Count -gt 0) {
        throw "Command-surface move plan repeats destinations: $(@($duplicatePlannedPaths.Name) -join ', ')"
    }

    $commandMap = Get-Content -LiteralPath $commandMapPath -Raw
    $retirementIds = @($script:retirement.entries.id | ForEach-Object { [string]$_ })
    $rootCommandNames = @('Install-Toolkit.ps1', 'Invoke-HostedReview.ps1', 'Start-RuleWorkbench.ps1', 'Test-Toolkit.ps1')
    $catalogCommandNames = @('Generate-Instructions.ps1', 'Test-UpstreamSources.ps1')
    foreach ($entry in @($script:commandSurface.entries)) {
        $currentPath = [string]$entry.currentPath
        $plannedPath = [string]$entry.plannedPath
        $extension = [IO.Path]::GetExtension($currentPath)
        switch ([string]$entry.classification) {
            'maintainer-command' {
                $fileName = [IO.Path]::GetFileName($currentPath)
                $expectedPath = if ($fileName -in $rootCommandNames) {
                    "hosted_copilot/tools/$fileName"
                }
                elseif ($fileName -in $catalogCommandNames) {
                    "hosted_copilot/tools/commands/catalog/$fileName"
                }
                else {
                    throw "Maintainer command is not assigned to an approved command group: $currentPath"
                }
                if ($extension -cne '.ps1' -or $plannedPath -cne $expectedPath -or [string]$entry.documentationPath -cne 'hosted_copilot/tools/README.md' -or -not $commandMap.Contains($fileName)) {
                    throw "Maintainer command classification is invalid: $currentPath"
                }
            }
            'internal-implementation' {
                if ($extension -cne '.ps1' -or $plannedPath -cnotlike 'hosted_copilot/tools/internal/*.ps1') {
                    throw "Internal implementation destination is invalid: $currentPath"
                }
            }
            'module' {
                if ($extension -cne '.psm1' -or $plannedPath -cnotlike 'hosted_copilot/tools/modules/*.psm1') {
                    throw "Module destination is invalid: $currentPath"
                }
            }
            'focused-test' {
                if ($extension -cne '.ps1' -or $plannedPath -cnotlike 'hosted_copilot/tools/tests/*.ps1') {
                    throw "Focused test destination is invalid: $currentPath"
                }
            }
            'migration-only' {
                if ($extension -cne '.ps1' -or $plannedPath -cnotlike 'hosted_copilot/tools/migration/*.ps1' -or [string]$entry.retirementInventoryId -notin $retirementIds) {
                    throw "Migration-only destination or retirement binding is invalid: $currentPath"
                }
            }
            'legacy-v3' {
                if ($extension -cne '.ps1' -or $plannedPath -cnotlike 'hosted_copilot/tools/legacy-v3/*.ps1' -or [string]$entry.retirementInventoryId -notin $retirementIds) {
                    throw "Legacy version 3 destination or retirement binding is invalid: $currentPath"
                }
            }
            default { throw "Unsupported command-surface classification: $($entry.classification)" }
        }
    }
}

Invoke-ReadinessTest -Name 'assessment-baseline-field-coverage' -SuccessDetail 'Every reachable version 3 assessment-baseline property appears exactly once.' -Action {
    $baselineSchema = Get-Content -LiteralPath $baselineSchemaPath -Raw | ConvertFrom-Json
    $expectedFields = @(Get-ReachableSchemaPropertyPaths -RootSchema $baselineSchema -Node $baselineSchema | Sort-Object -Unique)
    $baselineEntries = @($script:compatibility.entries | Where-Object sourceAuthority -eq 'assessment-baseline-schema')
    $actualFields = @($baselineEntries | ForEach-Object { @($_.version3Fields) } | ForEach-Object { [string]$_ })
    $duplicates = @($actualFields | Group-Object | Where-Object Count -gt 1)
    if ($duplicates.Count -gt 0) {
        throw "Assessment baseline fields are mapped more than once: $(@($duplicates.Name) -join ', ')"
    }
    Assert-RequiredValues -Expected $expectedFields -Actual $actualFields -Name 'Assessment baseline field coverage'
}

Invoke-ReadinessTest -Name 'rule-intake-review-field-coverage' -SuccessDetail 'Every reachable version 3 Workbench bundle property appears exactly once.' -Action {
    $bundleSchema = Get-Content -LiteralPath $ruleIntakeReviewSchemaPath -Raw | ConvertFrom-Json
    $expectedFields = @(Get-ReachableSchemaPropertyPaths -RootSchema $bundleSchema -Node $bundleSchema | Sort-Object -Unique)
    $bundleEntries = @($script:compatibility.entries | Where-Object sourceAuthority -eq 'rule-intake-review-schema')
    $actualFields = @($bundleEntries | ForEach-Object { @($_.version3Fields) } | ForEach-Object { [string]$_ })
    $duplicates = @($actualFields | Group-Object | Where-Object Count -gt 1)
    if ($duplicates.Count -gt 0) {
        throw "Workbench bundle fields are mapped more than once: $(@($duplicates.Name) -join ', ')"
    }
    Assert-RequiredValues -Expected $expectedFields -Actual $actualFields -Name 'Workbench bundle field coverage'
}

$requiredCompatibilityIds = @(
    'V3-COMPAT-BASELINE-SCHEMA', 'V3-COMPAT-BASELINE-SCHEMA-VERSION', 'V3-COMPAT-BASELINE-GENERATED-AT', 'V3-COMPAT-BASELINE-HOSTED-CATALOG-HASH', 'V3-COMPAT-BASELINE-SOURCE-BUNDLE-HASH', 'V3-COMPAT-BASELINE-ENTRIES',
    'V3-COMPAT-ENTRY-SOURCE-TYPE', 'V3-COMPAT-ENTRY-ID', 'V3-COMPAT-ENTRY-SOURCE-CONTENT-HASH', 'V3-COMPAT-ENTRY-ASSESSMENTS',
    'V3-COMPAT-ASSESSMENT-ID', 'V3-COMPAT-ASSESSMENT-TITLE', 'V3-COMPAT-ASSESSMENT-CANDIDATE-STATE', 'V3-COMPAT-ASSESSMENT-TARGET-HOSTED-ID', 'V3-COMPAT-ASSESSMENT-PROPOSED-HOSTED-ID', 'V3-COMPAT-ASSESSMENT-STATUS', 'V3-COMPAT-ASSESSMENT-SOURCE-CONTENT-HASH', 'V3-COMPAT-ASSESSMENT-ASSESSED-AT', 'V3-COMPAT-ASSESSMENT-EVALUATOR', 'V3-COMPAT-ASSESSMENT-HOSTED-APPLICABLE', 'V3-COMPAT-ASSESSMENT-APPLICABILITY-RATIONALE', 'V3-COMPAT-ASSESSMENT-HOSTED-CATEGORY', 'V3-COMPAT-ASSESSMENT-RECOMMENDATION', 'V3-COMPAT-ASSESSMENT-SUMMARY', 'V3-COMPAT-ASSESSMENT-IMPACT', 'V3-COMPAT-ASSESSMENT-CURRENT-COVERAGE', 'V3-COMPAT-ASSESSMENT-AFFECTED-SURFACES', 'V3-COMPAT-ASSESSMENT-GUARDED-TOKEN-DELTA', 'V3-COMPAT-ASSESSMENT-PROPOSED-TEXT', 'V3-COMPAT-ASSESSMENT-SELECTION-FACTORS', 'V3-COMPAT-ASSESSMENT-SELECTION-RATIONALE',
    'V3-COMPAT-FACTOR-SEVERITY', 'V3-COMPAT-FACTOR-FREQUENCY', 'V3-COMPAT-FACTOR-BREADTH', 'V3-COMPAT-FACTOR-HOSTED-DETECTABILITY', 'V3-COMPAT-FACTOR-EVIDENCE-STRENGTH', 'V3-COMPAT-FACTOR-FALSE-POSITIVE-RISK', 'V3-COMPAT-FACTOR-REDUNDANCY',
    'V3-COMPAT-BUNDLE-ENVELOPE', 'V3-COMPAT-BUNDLE-SNAPSHOTS', 'V3-COMPAT-BUNDLE-SUMMARY', 'V3-COMPAT-BUNDLE-CAPACITY', 'V3-COMPAT-BUNDLE-HOSTED-RULES', 'V3-COMPAT-UPSTREAM-CANDIDATE', 'V3-COMPAT-INTERACTIVE-CANDIDATE', 'V3-COMPAT-MAINTAINER-CANDIDATE',
    'V3-COMPAT-SESSION-ENVELOPE', 'V3-COMPAT-SESSION-DECISIONS', 'V3-COMPAT-SESSION-OVERRIDES', 'V3-COMPAT-SESSION-BULK-OPERATIONS', 'V3-COMPAT-DRAFT-EXPORT', 'V3-COMPAT-APPROVAL-PAYLOAD', 'V3-COMPAT-APPROVAL-DECISION', 'V3-COMPAT-APPROVAL-HANDOFF', 'V3-COMPAT-WORKBENCH-CONSTANTS'
)
Invoke-ReadinessTest -Name 'required-compatibility-families' -SuccessDetail 'All explicit version 3 Workbench field families are inventoried.' -Action {
    Assert-RequiredValues -Expected $requiredCompatibilityIds -Actual @($script:compatibility.entries.id) -Name 'Required compatibility IDs'
}

$requiredRetirementIds = @(
    'V3-RETIRE-PRODUCER-COLLECTOR', 'V3-RETIRE-PRODUCER-ASSESSMENT', 'V3-RETIRE-PRODUCER-BASELINE-PUBLISHER', 'V3-RETIRE-PRODUCER-CAPACITY', 'V3-RETIRE-PRODUCER-WORKBENCH-STAGING', 'V3-RETIRE-PRODUCER-DRAFT', 'V3-RETIRE-PRODUCER-APPROVAL',
    'V3-RETIRE-SCHEMA-RULE-INTAKE-REVIEW', 'V3-RETIRE-SCHEMA-ASSESSMENT-BASELINE', 'V3-RETIRE-SCHEMA-INTAKE-LEDGER', 'V3-RETIRE-SCHEMA-PROMOTION-PLAN', 'V3-RETIRE-SCHEMA-PROMOTION-RECEIPT',
    'V3-RETIRE-DATA-INTAKE-LEDGER', 'V3-RETIRE-DATA-ASSESSMENT-BASELINE', 'V3-RETIRE-DATA-CANONICAL-CATALOG', 'V3-RETIRE-CACHE-ASSESSMENT', 'V3-RETIRE-CACHE-RUN-ARTIFACTS', 'V3-RETIRE-SESSION-ACTIVE-KEY', 'V3-RETIRE-SESSION-INDEXEDDB',
    'V3-RETIRE-LAUNCHER-SERVER-PARAMETERS', 'V3-RETIRE-LAUNCHER-ASSESSMENT-PARAMETERS', 'V3-RETIRE-LAUNCHER-DEFAULT-ASSESSMENT', 'V3-RETIRE-STAGED-BUNDLE-FILENAME',
    'V3-RETIRE-VALIDATOR-TOOLKIT-REGISTRATION', 'V3-RETIRE-VALIDATOR-RULE-INTAKE', 'V3-RETIRE-VALIDATOR-ASSESSMENT', 'V3-RETIRE-VALIDATOR-WORKBENCH',
    'V3-RETIRE-BROWSER-SCHEMA-CONSTANTS', 'V3-RETIRE-BROWSER-BUNDLE-READS', 'V3-RETIRE-BROWSER-ASSESSMENT-READS', 'V3-RETIRE-BROWSER-CAPACITY-READS', 'V3-RETIRE-BROWSER-SESSION-DRAFT-READS', 'V3-RETIRE-BROWSER-APPROVAL-READS',
    'V3-RETIRE-FIXTURE-RULE-INTAKE', 'V3-RETIRE-FIXTURE-ASSESSMENT', 'V3-RETIRE-FIXTURE-WORKBENCH', 'V3-RETIRE-FIXTURE-BROWSER-JOURNEYS',
    'V3-RETIRE-WORKFLOW-CANDIDATE-VIEWS', 'V3-RETIRE-WORKFLOW-ASSESSMENT-RESULTS', 'V3-RETIRE-WORKFLOW-APPLICABILITY-OVERRIDE', 'V3-RETIRE-WORKFLOW-DECISION-PLAN', 'V3-RETIRE-WORKFLOW-CAPACITY', 'V3-RETIRE-WORKFLOW-PREVIEW-APPROVAL', 'V3-RETIRE-WORKFLOW-DRAFT-PERSISTENCE', 'V3-RETIRE-WORKFLOW-SHUTDOWN',
    'V3-RETIRE-MIGRATION-CATALOG-TRANSFORMER', 'V3-RETIRE-MIGRATION-CATALOG-TRANSFORMATION-TEST', 'V3-RETIRE-MIGRATION-READINESS-TEST', 'V3-RETIRE-MIGRATION-FIELD-COMPATIBILITY-SCHEMA', 'V3-RETIRE-MIGRATION-FIELD-COMPATIBILITY-DATA', 'V3-RETIRE-MIGRATION-RETIREMENT-SCHEMA', 'V3-RETIRE-MIGRATION-RETIREMENT-DATA', 'V3-RETIRE-MIGRATION-COMMAND-SURFACE-SCHEMA', 'V3-RETIRE-MIGRATION-COMMAND-SURFACE-DATA'
)
$requiredDependencyClasses = @('producer', 'schema', 'durable-artifact', 'cache', 'session-key', 'launcher-parameter', 'launcher-default', 'staged-filename', 'validator-registration', 'browser-schema-constant', 'browser-field-read', 'fixture-family', 'renderer-workflow')
Invoke-ReadinessTest -Name 'required-retirement-dependencies' -SuccessDetail 'All explicit version 3 dependency IDs and dependency classes are inventoried.' -Action {
    Assert-RequiredValues -Expected $requiredRetirementIds -Actual @($script:retirement.entries.id) -Name 'Required retirement IDs'
    Assert-RequiredValues -Expected $requiredDependencyClasses -Actual @($script:retirement.entries.dependencyClass | Sort-Object -Unique) -Name 'Required retirement dependency classes'
}

Invoke-ReadinessTest -Name 'seed-provenance-and-ignore-boundary' -SuccessDetail 'The ignored seed exists with exact accepted repository, PR, commit, path, and blob provenance.' -Action {
    if (-not (Test-Path -LiteralPath $seedPath -PathType Leaf)) {
        throw "Ignored preservation seed is missing: $seedRelativePath"
    }
    $script:seed = Get-Content -LiteralPath $seedPath -Raw | ConvertFrom-Json
    $git = Get-Command git -ErrorAction Stop
    $blobId = (& $git.Source -C $repoRoot rev-parse "$acceptedCommit`:$acceptedCatalogPath").Trim()
    if ($LASTEXITCODE -ne 0) { throw 'Could not resolve the accepted catalog blob ID' }
    $ignoredPath = @(& $git.Source -C $repoRoot check-ignore -- $seedRelativePath)
    if ($LASTEXITCODE -ne 0 -or $ignoredPath.Count -ne 1) { throw 'Preservation seed is not ignored' }
    $trackedPath = @(& $git.Source -C $repoRoot ls-files -- $seedRelativePath)
    if ($LASTEXITCODE -ne 0 -or $trackedPath.Count -ne 0) { throw 'Preservation seed must remain untracked' }
    if ([string]$script:seed.sourceRepository -cne $acceptedRepository -or [int]$script:seed.pullRequest -ne $acceptedPullRequest -or [string]$script:seed.commit -cne $acceptedCommit -or [string]$script:seed.catalogPath -cne $acceptedCatalogPath -or [string]$script:seed.catalogBlobId -cne $blobId) {
        throw 'Preservation seed provenance does not match the accepted baseline'
    }
}

Invoke-ReadinessTest -Name 'accepted-seed-ordered-rules' -SuccessDetail 'The seed preserves the accepted commit ordered rule objects exactly.' -Action {
    $git = Get-Command git -ErrorAction Stop
    $baselineJson = @(& $git.Source -C $repoRoot show "$acceptedCommit`:$acceptedCatalogPath") -join "`n"
    if ($LASTEXITCODE -ne 0) { throw 'Could not read the accepted catalog from Git' }
    $script:baselineCatalog = $baselineJson | ConvertFrom-Json
    Assert-OrderedRulesEqual -Expected @($script:baselineCatalog.rules) -Actual @($script:seed.rules) -Name 'Accepted catalog versus seed'
}

Invoke-ReadinessTest -Name 'current-catalog-ordered-rules' -SuccessDetail 'The current canonical catalog ordered rule objects still equal the preserved seed.' -Action {
    $script:currentCatalog = Get-Content -LiteralPath $catalogPath -Raw | ConvertFrom-Json
    Assert-OrderedRulesEqual -Expected @($script:seed.rules) -Actual @($script:currentCatalog.rules) -Name 'Seed versus current catalog'
}

Invoke-ReadinessTest -Name 'canonical-rule-count' -SuccessDetail 'Accepted seed and current catalog both contain exactly 54 rules.' -Action {
    if (@($script:seed.rules).Count -ne $expectedRuleCount -or @($script:currentCatalog.rules).Count -ne $expectedRuleCount) {
        throw "Expected $expectedRuleCount rules in both seed and current catalog"
    }
}

Invoke-ReadinessTest -Name 'legacy-source-tuples' -SuccessDetail 'The preserved and current catalogs contain exactly 37 unique legacy sourceId-to-hostedRuleId tuples.' -Action {
    $seedTuples = @(Get-LegacyTuples -Rules @($script:seed.rules))
    $currentTuples = @(Get-LegacyTuples -Rules @($script:currentCatalog.rules))
    if ($seedTuples.Count -ne $expectedLegacyTupleCount -or @($seedTuples | Sort-Object -Unique).Count -ne $expectedLegacyTupleCount) {
        throw "Seed legacy tuple count or uniqueness differs from $expectedLegacyTupleCount"
    }
    if ($currentTuples.Count -ne $expectedLegacyTupleCount -or @($currentTuples | Sort-Object -Unique).Count -ne $expectedLegacyTupleCount) {
        throw "Current catalog legacy tuple count or uniqueness differs from $expectedLegacyTupleCount"
    }
    Assert-RequiredValues -Expected $seedTuples -Actual $currentTuples -Name 'Legacy source tuples'
}

$status = if ($issues.Count -eq 0) { 'passed' } else { 'failed' }
$summary = [ordered]@{
    status = $status
    testCount = $results.Count
    issueCount = $issues.Count
    compatibilityEntryCount = @($script:compatibility.entries).Count
    retirementEntryCount = @($script:retirement.entries).Count
    ruleCount = if ($null -eq $script:seed) { 0 } else { @($script:seed.rules).Count }
    legacyTupleCount = if ($null -eq $script:seed) { 0 } else { @(Get-LegacyTuples -Rules @($script:seed.rules)).Count }
    tests = $results.ToArray()
    issues = $issues.ToArray()
}

if ($OutputFormat -eq 'Json') {
    $summary | ConvertTo-Json -Depth 8
}
else {
    Write-ValidationSectionHeader -Title 'Hosted v4 migration readiness'
    Write-ValidationSummary -Fields ([ordered]@{
        Status = $status.ToUpperInvariant()
        Tests = $results.Count
        Issues = $issues.Count
        'Compatibility Entries' = $summary.compatibilityEntryCount
        'Retirement Entries' = $summary.retirementEntryCount
        'Preserved Rules' = $summary.ruleCount
        'Legacy Tuples' = $summary.legacyTupleCount
    })
    Write-Output ''
    Write-ValidationTwoColumnTable -Rows @($results | ForEach-Object { [pscustomobject]@{ Status = $_.status; Test = $_.name } }) -FirstHeader 'Status' -FirstProperty 'Status' -SecondHeader 'Test' -SecondProperty 'Test' -UppercaseFirst
    if ($issues.Count -gt 0) {
        Write-ValidationSectionHeader -Title 'Failures'
        foreach ($issue in $issues) { Write-Output "  - $issue" }
    }
    Complete-ValidationTextOutput
}

if ($status -ne 'passed') {
    exit 1
}
