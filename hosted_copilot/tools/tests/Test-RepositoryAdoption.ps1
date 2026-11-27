[CmdletBinding()]
param([ValidateSet('Text', 'Json')][string]$OutputFormat = 'Text')

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$hostedRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../..'))
Import-Module (Join-Path $PSScriptRoot '../modules/shared/HostedAdoption.psm1') -Force
Import-Module (Join-Path $PSScriptRoot '../../../tools/ValidationOutput.psm1') -Force
$capacityCommand = Join-Path $PSScriptRoot '../internal/workbench/Get-GuidanceCapacity.ps1'
$preflightCommand = Join-Path $PSScriptRoot '../commands/adoption/Test-RepositoryAdoption.ps1'
$temporary = Join-Path ([IO.Path]::GetTempPath()) ('hosted-adoption-tests-' + [guid]::NewGuid().ToString('N'))
$template = Join-Path $temporary 'template'
$results = [Collections.Generic.List[object]]::new()
$issues = [Collections.Generic.List[string]]::new()

function Write-FixtureJson {
    param([string]$Path, [object]$Value)
    [IO.File]::WriteAllText($Path, ($Value | ConvertTo-Json -Depth 100), [Text.UTF8Encoding]::new($false))
}

function Copy-FixtureInput {
    param([string]$Reference)
    $destination = Join-Path $template $Reference
    $null = New-Item -ItemType Directory -Path (Split-Path -Parent $destination) -Force
    Copy-Item -LiteralPath (Join-Path $hostedRoot $Reference) -Destination $destination -Force
}

function New-AdoptionFixture {
    param([string]$Name)
    $root = Join-Path $temporary $Name
    $null = New-Item -ItemType Directory -Path $root -Force
    Get-ChildItem -LiteralPath $template -Force | Copy-Item -Destination $root -Recurse -Force
    return $root
}

function Read-FixtureDescriptor {
    param([string]$Root)
    return Get-Content -LiteralPath (Join-Path $Root 'tools/config/adoption.json') -Raw | ConvertFrom-Json -Depth 50
}

function Get-FixturePolicy {
    param([string]$Root)
    return Get-HostedTokenPolicy -Configuration (Get-HostedAdoptionConfiguration -HostedRoot $Root)
}

function Invoke-CapacityFixture {
    param([string]$Root)
    $output = @(& pwsh -NoProfile -File $capacityCommand -HostedRoot $Root -OutputFormat Json 2>$null)
    $code = $LASTEXITCODE
    return [pscustomobject]@{ exitCode = $code; value = ($output | Out-String) | ConvertFrom-Json -Depth 50 }
}

function Invoke-PreflightFixture {
    param([string]$Root, [ValidateSet('Text', 'Json')][string]$OutputFormat = 'Json')
    $output = @(& pwsh -NoProfile -File $preflightCommand -HostedRoot $Root -OutputFormat $OutputFormat 2>$null)
    $code = $LASTEXITCODE
    $text = $output | Out-String
    $value = if ($OutputFormat -eq 'Json') { $text | ConvertFrom-Json -Depth 50 } else { $null }
    return [pscustomobject]@{ exitCode = $code; value = $value; text = $text }
}

function Assert-Fixture {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw $Message }
}

function Assert-Rejected {
    param([scriptblock]$Action)
    $rejected = $false
    try { & $Action | Out-Null } catch { $rejected = $true }
    Assert-Fixture $rejected 'The invalid configuration or report was not rejected'
}

function Invoke-AdoptionCase {
    param([string]$Name, [scriptblock]$Action)
    try {
        $root = New-AdoptionFixture $Name
        & $Action $root
        $results.Add([pscustomobject]@{ name = $Name; status = 'passed'; detail = 'The configured boundary behaved as required.' })
    }
    catch {
        $issues.Add("$Name`: $($_.Exception.Message)")
        $results.Add([pscustomobject]@{ name = $Name; status = 'failed'; detail = $_.Exception.Message })
    }
}

function Set-AlternatePolicy {
    param([string]$Root)
    $descriptor = Read-FixtureDescriptor $Root
    $descriptor.reviewUpstream = 'example-team/example-project'
    $descriptor.tokenPolicy.safetyMarginPercent = 10
    $descriptor.tokenPolicy.maximumGuidanceTokens = 1000
    $descriptor.tokenPolicy.areas = @(
        [ordered]@{ name = 'handbook'; surfaceId = 'handbook'; budgetTokens = 200 },
        [ordered]@{ name = 'security'; surfaceId = 'security'; budgetTokens = 200 }
    )
    $descriptor.tokenPolicy.combinations = @([ordered]@{ name = 'complete-review'; members = @('handbook', 'security'); budgetTokens = 400 })
    $catalogPath = Join-Path $Root $descriptor.catalog
    $catalog = Get-Content $catalogPath -Raw | ConvertFrom-Json -Depth 100
    $catalog.surfaces = @($catalog.surfaces | Select-Object -First 2)
    $catalog.surfaces[0].id = 'handbook'; $catalog.surfaces[0].outputPath = '.github/instructions/handbook.instructions.md'
    $catalog.surfaces[1].id = 'security'; $catalog.surfaces[1].outputPath = '.github/instructions/security.instructions.md'
    Write-FixtureJson $catalogPath $catalog
    [IO.File]::WriteAllText((Join-Path $Root '.github/instructions/handbook.instructions.md'), ('x' * 41))
    [IO.File]::WriteAllText((Join-Path $Root '.github/instructions/security.instructions.md'), ('y' * 13))
    Write-FixtureJson (Join-Path $Root 'tools/config/adoption.json') $descriptor
}

if ($OutputFormat -eq 'Text') {
    Write-ValidationSectionHeader -Title 'Hosted repository adoption tests'
    Write-Host (Format-ValidationStatusLine -Status running -Name 'policy-and-preflight-boundaries' -Detail 'Checking real descriptor shapes, alternate allocations, exact report coverage and read-only diagnostics' -NameWidth 44)
}

try {
    $null = New-Item -ItemType Directory -Path $template -Force
    Copy-Item -LiteralPath (Join-Path $hostedRoot 'contracts') -Destination $template -Recurse
    Copy-Item -LiteralPath (Join-Path $hostedRoot 'copilot-rule-catalog') -Destination $template -Recurse
    Copy-FixtureInput 'tools/config/adoption.json'
    Copy-FixtureInput 'tools/internal/review/Import-PullRequest.ps1'
    foreach ($contractPath in Get-ChildItem (Join-Path $hostedRoot 'contracts/parsers') -File -Filter '*.json' | Where-Object Name -NotLike '*.schema.json') {
        $contract = Get-Content -LiteralPath $contractPath.FullName -Raw | ConvertFrom-Json
        foreach ($reference in $contract.behaviorFiles) { Copy-FixtureInput $reference.Substring('hosted_copilot/'.Length) }
    }
    $originalPolicy = Get-FixturePolicy $hostedRoot
    foreach ($area in $originalPolicy.policy.areas) { Copy-FixtureInput $area.path }

    Invoke-AdoptionCase 'current-policy' {
        param($Root)
        $capacity = Invoke-CapacityFixture $Root
        Assert-Fixture ($capacity.exitCode -eq 0 -and $capacity.value.reportCount -eq 8) 'The initial profile did not preserve its eight passing reports'
        Assert-HostedGuidanceCapacity $capacity.value (Get-FixturePolicy $Root)
    }
    Invoke-AdoptionCase 'descriptor-path-comment' {
        param($Root)
        $before = Get-FixturePolicy $Root
        $descriptor = Read-FixtureDescriptor $Root
        Assert-Fixture ($descriptor.'$comment'.Contains('hosted_copilot/') -and $descriptor.'$comment'.Contains('Referenced source-definition')) 'The descriptor does not explain its path base and referenced-document boundary'
        $descriptor.'$comment' = 'Synthetic annotation: paths are relative to hosted_copilot/.'
        Write-FixtureJson (Join-Path $Root 'tools/config/adoption.json') $descriptor
        $after = Get-FixturePolicy $Root
        Assert-Fixture ($before.sha256 -ceq $after.sha256) 'A documentation-only annotation changed the token policy'
    }
    Invoke-AdoptionCase 'multiple-skill-areas' {
        param($Root)
        $skillPath = '.github/skills/security-fixture/SKILL.md'
        $fullPath = Join-Path $Root $skillPath
        $null = New-Item -ItemType Directory -Path (Split-Path -Parent $fullPath) -Force
        [IO.File]::WriteAllText($fullPath, 'Synthetic security skill guidance.')
        $descriptor = Read-FixtureDescriptor $Root
        $descriptor.tokenPolicy.areas += [ordered]@{ name = 'security-skill'; path = $skillPath; budgetTokens = 1000 }
        $descriptor.tokenPolicy.combinations[0].members += 'security-skill'
        Write-FixtureJson (Join-Path $Root 'tools/config/adoption.json') $descriptor
        $capacity = Invoke-CapacityFixture $Root
        Assert-Fixture ($capacity.exitCode -eq 0 -and $capacity.value.reportCount -eq 9) 'Adding a second skill did not produce its independent capacity report'
        Assert-HostedGuidanceCapacity $capacity.value (Get-FixturePolicy $Root)
        $skill = @($capacity.value.reports | Where-Object name -CEQ 'security-skill')
        $combined = $capacity.value.reports | Where-Object name -CEQ 'go-combined'
        $documentation = $capacity.value.reports | Where-Object name -CEQ 'documentation-combined'
        Assert-Fixture ($skill.Count -eq 1 -and $skill[0].paths[0] -ceq $skillPath -and $skill[0].budgetTokens -eq 1000) 'The additional skill lost its path or independent allocation'
        Assert-Fixture ($skillPath -cin @($combined.paths) -and $skillPath -cnotin @($documentation.paths)) 'Combined views did not preserve explicit skill membership'
    }
    Invoke-AdoptionCase 'alternate-policy' {
        param($Root)
        Set-AlternatePolicy $Root
        $capacity = Invoke-CapacityFixture $Root
        Assert-Fixture ($capacity.exitCode -eq 0 -and $capacity.value.reportCount -eq 3 -and $capacity.value.safetyMarginPercent -eq 10) 'Alternative allocations did not control report generation'
        Assert-Fixture ($capacity.value.reports[0].estimatedTokens -eq 11 -and $capacity.value.reports[0].guardedTokens -eq 13) 'The configured estimation margin was ignored'
        Assert-HostedGuidanceCapacity $capacity.value (Get-FixturePolicy $Root)
    }
    Invoke-AdoptionCase 'overall-ceiling' {
        param($Root)
        Set-AlternatePolicy $Root
        $descriptor = Read-FixtureDescriptor $Root
        $descriptor.tokenPolicy.maximumGuidanceTokens = 15
        $descriptor.tokenPolicy.combinations = @()
        foreach ($area in $descriptor.tokenPolicy.areas) { $area.budgetTokens = 15 }
        Write-FixtureJson (Join-Path $Root 'tools/config/adoption.json') $descriptor
        $capacity = Invoke-CapacityFixture $Root
        Assert-Fixture ($capacity.exitCode -eq 1 -and $capacity.value.status -ceq 'failed' -and @($capacity.value.reports | Where-Object { -not $_.withinBudget }).Count -eq 0) 'The overall ceiling did not independently constrain passing areas'
    }
    foreach ($defect in @('duplicate-area', 'duplicate-path', 'unknown-member', 'duplicate-member', 'missing-surface', 'omitted-catalog-surface', 'path-traversal', 'absolute-path', 'allocation-over-ceiling')) {
        Invoke-AdoptionCase $defect {
            param($Root)
            $descriptor = Read-FixtureDescriptor $Root
            switch ($defect) {
                'duplicate-area' { $descriptor.tokenPolicy.areas += $descriptor.tokenPolicy.areas[0] }
                'duplicate-path' { $descriptor.tokenPolicy.areas[-1].path = $descriptor.tokenPolicy.areas[0].path }
                'unknown-member' { $descriptor.tokenPolicy.combinations[0].members += 'missing' }
                'duplicate-member' { $descriptor.tokenPolicy.combinations[0].members += $descriptor.tokenPolicy.combinations[0].members[0] }
                'missing-surface' { $descriptor.tokenPolicy.areas[1].surfaceId = 'missing' }
                'omitted-catalog-surface' { $descriptor.tokenPolicy.areas = @($descriptor.tokenPolicy.areas | Where-Object name -CNE 'documentation'); $descriptor.tokenPolicy.combinations = @() }
                'path-traversal' { $descriptor.catalog = '../outside.json' }
                'absolute-path' { $descriptor.catalog = 'C:/outside.json' }
                'allocation-over-ceiling' { $descriptor.tokenPolicy.areas[0].budgetTokens = $descriptor.tokenPolicy.maximumGuidanceTokens + 1 }
            }
            Write-FixtureJson (Join-Path $Root 'tools/config/adoption.json') $descriptor
            Assert-Rejected { Get-FixturePolicy $Root }
        }
    }
    foreach ($defect in @('missing-report', 'duplicate-report', 'wrong-arithmetic', 'wrong-combined-members', 'stale-policy')) {
        Invoke-AdoptionCase $defect {
            param($Root)
            $capacity = (Invoke-CapacityFixture $Root).value
            switch ($defect) {
                'missing-report' { $capacity.reports = @($capacity.reports | Select-Object -Skip 1); $capacity.reportCount-- }
                'duplicate-report' { $capacity.reports[1] = $capacity.reports[0] }
                'wrong-arithmetic' { $capacity.reports[0].guardedTokens++ }
                'wrong-combined-members' { $capacity.reports[-1].paths = @('wrong.md') }
                'stale-policy' {
                    $descriptor = Read-FixtureDescriptor $Root
                    $descriptor.tokenPolicy.safetyMarginPercent = 10
                    Write-FixtureJson (Join-Path $Root 'tools/config/adoption.json') $descriptor
                }
            }
            Assert-Rejected { Assert-HostedGuidanceCapacity $capacity (Get-FixturePolicy $Root) }
        }
    }
    Invoke-AdoptionCase 'read-only-report' {
        param($Root)
        $before = @(Get-ChildItem $Root -Recurse -File -Force | Sort-Object FullName | Get-FileHash | ForEach-Object Hash) -join ','
        $report = Invoke-PreflightFixture $Root
        $after = @(Get-ChildItem $Root -Recurse -File -Force | Sort-Object FullName | Get-FileHash | ForEach-Object Hash) -join ','
        Assert-Fixture ($before -ceq $after) 'The preflight changed fixture contents'
        Assert-Fixture ($report.exitCode -eq 2 -and $report.value.status -ceq 'review-required' -and @($report.value.findings | Where-Object status -CEQ 'invalid').Count -eq 0) 'Unassessed integration work was omitted or misreported as readiness'
    }
    Invoke-AdoptionCase 'preflight-text-output' {
        param($Root)
        $report = Invoke-PreflightFixture $Root -OutputFormat Text
        Assert-Fixture ($report.exitCode -eq 2 -and $report.text -match '(?m)^\s+STATUS\s+CHECK\r?$') 'The text report does not use the standard status-first table'
        Assert-Fixture ($report.text -match '(?m)^\s+PASSED\s+descriptor\r?$' -and $report.text -match '(?m)^\s+NOT-ASSESSED\s+integration-coverage\r?$') 'The text report lost its exact finding statuses or check identities'
        Assert-Fixture ($report.text -match '(?m)^\s+Check\s+: integration-coverage\r?$' -and $report.text -match '(?m)^\s+ACTION\s+DETAIL\r?$' -and $report.text -match '(?m)^\s+REVIEW\s+contracts/sources/source-inventory.schema.json\r?$') 'Integration details do not use the shared summary and action-table layout'
    }
    Invoke-AdoptionCase 'preflight-text-required-changes' {
        param($Root)
        $descriptor = Read-FixtureDescriptor $Root
        $descriptor.reviewUpstream = 'example-team/example-project'
        Write-FixtureJson (Join-Path $Root 'tools/config/adoption.json') $descriptor
        $report = Invoke-PreflightFixture $Root -OutputFormat Text
        Assert-Fixture ($report.exitCode -eq 1 -and $report.text -match '(?m)^\s+REQUIRES-ADAPTATION\s+review-upstream\r?$') 'The text report changed an adaptation finding or its exit code'
        Assert-Fixture ($report.text -match '(?m)^\s+CHANGE\s+tools/internal/review/Import-PullRequest.ps1: Adapt canonical repository validation' -and $report.text -match '(?m)^\s+VERIFY\s+tools/tests/Test-HostedReviewWorkflow.ps1\r?$') 'The text report omitted actionable change and verification details'
    }
    Invoke-AdoptionCase 'different-review-upstream' {
        param($Root)
        $descriptor = Read-FixtureDescriptor $Root; $descriptor.reviewUpstream = 'example-team/example-project'
        Write-FixtureJson (Join-Path $Root 'tools/config/adoption.json') $descriptor
        $report = Invoke-PreflightFixture $Root
        $finding = $report.value.findings | Where-Object checkId -CEQ 'review-upstream'
        Assert-Fixture ($report.exitCode -eq 1 -and $finding.status -ceq 'requires-adaptation' -and $finding.requiredChanges[0].file -ceq 'tools/internal/review/Import-PullRequest.ps1') 'The actual canonical repository restriction was not reported precisely'
    }
    Invoke-AdoptionCase 'renamed-single-lane' {
        param($Root)
        $definitionRoot = Join-Path $Root 'copilot-rule-catalog/source-definitions'
        $definition = Get-Content (Join-Path $definitionRoot 'maintainer-proposals.json') -Raw | ConvertFrom-Json
        $definition.id = 'security-guidance'
        Write-FixtureJson (Join-Path $definitionRoot 'security-guidance.json') $definition
        $set = Get-Content (Join-Path $definitionRoot 'source-definition-set.json') -Raw | ConvertFrom-Json
        $set.sourceDefinitionIds = @('security-guidance')
        Write-FixtureJson (Join-Path $definitionRoot 'source-definition-set.json') $set
        $report = Invoke-PreflightFixture $Root
        Assert-Fixture ($report.exitCode -eq 2 -and @($report.value.findings | Where-Object checkId -CEQ 'lane/security-guidance/contracts').Count -eq 1) 'The preflight assumed the original lane names or count'
    }
    Invoke-AdoptionCase 'unknown-parser-route' {
        param($Root)
        $definitionPath = Join-Path $Root 'copilot-rule-catalog/source-definitions/maintainer-proposals.json'
        $definition = Get-Content $definitionPath -Raw | ConvertFrom-Json
        $contract = Get-Content (Join-Path $Root "contracts/parsers/$($definition.parser).json") -Raw | ConvertFrom-Json
        $definition.parser = 'custom-policy-v1'; $contract.parserId = 'custom-policy-v1'
        Write-FixtureJson $definitionPath $definition
        Write-FixtureJson (Join-Path $Root 'contracts/parsers/custom-policy-v1.json') $contract
        $report = Invoke-PreflightFixture $Root
        $finding = $report.value.findings | Where-Object checkId -CEQ 'lane/maintainer-proposals/dispatch'
        Assert-Fixture ($report.exitCode -eq 1 -and $finding.status -ceq 'requires-adaptation' -and $finding.requiredChanges[0].file -ceq 'tools/internal/collection/New-SourceInventory.ps1') 'Contract existence was mistaken for collector support'
    }
    Invoke-AdoptionCase 'unsafe-descriptor' {
        param($Root)
        $descriptor = Read-FixtureDescriptor $Root; $descriptor.catalog = '../outside.json'
        Write-FixtureJson (Join-Path $Root 'tools/config/adoption.json') $descriptor
        $report = Invoke-PreflightFixture $Root
        Assert-Fixture ($report.exitCode -eq 1 -and $report.value.status -ceq 'invalid') 'Unsafe references were not rejected with structured diagnostics'
    }
    Invoke-AdoptionCase 'different-guidance-repository' {
        param($Root)
        $path = Join-Path $Root 'copilot-rule-catalog/source-definitions/contributor-guidance.json'
        $definition = Get-Content $path -Raw | ConvertFrom-Json
        $definition.root.repository = 'example-team/standards'
        Write-FixtureJson $path $definition
        $report = Invoke-PreflightFixture $Root
        $finding = $report.value.findings | Where-Object checkId -CEQ 'lane/contributor-guidance/source-repository'
        Assert-Fixture ($report.exitCode -eq 1 -and $finding.status -ceq 'requires-adaptation' -and $finding.requiredChanges.Count -eq 2) 'Confirmed source schema and collector restrictions were not reported as adaptations'
    }
    Invoke-AdoptionCase 'over-budget-preflight' {
        param($Root)
        $descriptor = Read-FixtureDescriptor $Root
        $descriptor.tokenPolicy.areas[0].budgetTokens = 1
        Write-FixtureJson (Join-Path $Root 'tools/config/adoption.json') $descriptor
        $report = Invoke-PreflightFixture $Root
        $finding = $report.value.findings | Where-Object checkId -CEQ 'capacity'
        Assert-Fixture ($report.exitCode -eq 1 -and $finding.status -ceq 'requires-adaptation') 'The preflight ignored actual capacity exhaustion'
    }
    Invoke-AdoptionCase 'missing-descriptor' {
        param($Root)
        Remove-Item (Join-Path $Root 'tools/config/adoption.json')
        $report = Invoke-PreflightFixture $Root
        Assert-Fixture ($report.exitCode -eq 1 -and $report.value.status -ceq 'invalid') 'Missing configuration used a hidden fallback'
    }
        Invoke-AdoptionCase 'browser-policy-calculations' {
                param($Root)
                $script = @'
const fs = require("node:fs");
const vm = require("node:vm");
const assert = require("node:assert/strict");
const source = fs.readFileSync(process.argv[1], "utf8");
function declaration(name) {
    const start = source.indexOf(`function ${name}(`);
    assert(start >= 0, `Missing production function: ${name}`);
    const end = source.indexOf("\nfunction ", start + 1);
    return source.slice(start, end < 0 ? source.length : end);
}
const context = {
    state: { bundle: { guidanceCapacity: { safetyMarginPercent: 10, maximumGuidanceTokens: 50 } } },
    GUIDANCE_CAPACITY_BUCKETS: [{ surface: "repository", reportName: "repository" }, { surface: "implementation", reportName: "go" }],
    getPlanCandidates: () => [],
    getCapacityReports: () => [
        { name: "repository", kind: "file", paths: ["repository.md"], guardedTokens: 10, budgetTokens: 100 },
        { name: "go", kind: "file", paths: ["implementation.md"], guardedTokens: 20, budgetTokens: 200 },
        { name: "skill", kind: "file", paths: ["skill.md"], guardedTokens: 10, budgetTokens: 100 }
    ]
};
vm.createContext(context);
vm.runInContext(["estimateGuardedTokens", "getGuidanceCapacityProjection", "getProjectedCapacityDelta"].map(declaration).join("\n"), context);
assert.equal(context.estimateGuardedTokens("x".repeat(41)), 13);
context.state.bundle.guidanceCapacity.safetyMarginPercent = 0;
assert.equal(context.estimateGuardedTokens("xxxx"), 1);
assert.equal(context.getGuidanceCapacityProjection().budgetTokens, 40);
assert.equal(context.getGuidanceCapacityProjection().projectedHeadroomTokens, 10);
context.getGuidanceCapacityProjection = () => ({ buckets: [{ reportName: "go", draftDeltaTokens: 13 }, { reportName: "repository", draftDeltaTokens: 2 }] });
assert.equal(context.getProjectedCapacityDelta({ name: "renamed-combination", paths: ["implementation.md"] }), 13);
assert.equal(context.getProjectedCapacityDelta({ name: "renamed-combination", paths: ["implementation.md", "repository.md"] }), 15);
'@
                $output = @(& node -e $script (Join-Path $hostedRoot 'workbench/app.js') 2>&1)
                if ($LASTEXITCODE -ne 0) { throw ($output | Out-String) }
        }
}
catch { $issues.Add($_.Exception.Message) }
finally { if (Test-Path $temporary) { Remove-Item -LiteralPath $temporary -Recurse -Force -ErrorAction SilentlyContinue } }

$result = [ordered]@{ status = if ($issues.Count) { 'failed' } else { 'passed' }; testCount = $results.Count; issueCount = $issues.Count; tests = $results.ToArray(); issues = $issues.ToArray() }
if ($OutputFormat -eq 'Json') { $result | ConvertTo-Json -Depth 20 }
else {
    Write-ValidationSectionHeader -Title 'Hosted repository adoption test summary'
    Write-ValidationSummary -Fields ([ordered]@{ Status = $result.status.ToUpperInvariant(); Tests = $result.testCount; Issues = $result.issueCount })
    Write-ValidationSectionHeader -Title 'Adoption tests'
    Write-ValidationTwoColumnTable -Rows @($results | ForEach-Object { [pscustomobject]@{ status = $_.status; test = $_.name } }) -FirstHeader status -FirstProperty status -SecondHeader test -SecondProperty test -UppercaseFirst
    if ($issues.Count) { Write-ValidationSectionHeader -Title 'Failures'; foreach ($issue in $issues) { Write-Output "  $issue" } }
    Complete-ValidationTextOutput
}
if ($issues.Count) { exit 1 }
