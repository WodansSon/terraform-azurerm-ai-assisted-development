[CmdletBinding()]
param(
    [string]$HostedRoot = (Join-Path $PSScriptRoot '../../..'),
    [string]$DescriptorPath = 'adoption.json',
    [ValidateSet('Text', 'Json')][string]$OutputFormat = 'Text'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $PSScriptRoot '../../modules/shared/HostedAdoption.psm1')
Import-Module (Join-Path $PSScriptRoot '../../../../tools/ValidationOutput.psm1')
$findings = [Collections.Generic.List[object]]::new()
$reviewUpstream = $null
$configuration = $null

function Add-AdoptionFinding {
    param(
        [string]$CheckId,
        [ValidateSet('passed', 'requires-adaptation', 'invalid', 'not-assessed')][string]$Status,
        [string]$Reason,
        [object[]]$RequiredChanges = @(),
        [string[]]$RelatedFiles = @(),
        [string[]]$Verification = @()
    )
    $findings.Add([pscustomobject][ordered]@{ checkId = $CheckId; status = $Status; reason = $Reason; requiredChanges = @($RequiredChanges); relatedFiles = @($RelatedFiles | Sort-Object -Unique); verification = @($Verification) })
}

function Read-AdoptionJson {
    param([string]$RelativePath)
    $path = Resolve-HostedAdoptionPath -HostedRoot $configuration.hostedRoot -RelativePath $RelativePath
    return Get-Content -LiteralPath $path -Raw | ConvertFrom-Json -Depth 100
}

function Test-AdoptionJson {
    param([object]$Value, [string]$SchemaPath)
    return [bool](($Value | ConvertTo-Json -Depth 100) | Test-Json -SchemaFile (Join-Path $PSScriptRoot "../../../$SchemaPath") -ErrorAction SilentlyContinue)
}

function Read-AdoptionScriptAst {
    param([string]$RelativePath)
    $tokens = $null; $errors = $null
    $path = Resolve-HostedAdoptionPath -HostedRoot $configuration.hostedRoot -RelativePath $RelativePath
    $ast = [Management.Automation.Language.Parser]::ParseFile($path, [ref]$tokens, [ref]$errors)
    if ($errors.Count) { return $null }
    return $ast
}

if ($OutputFormat -eq 'Text') {
    Write-ValidationSectionHeader -Title 'Hosted repository adoption'
    Write-Host (Format-ValidationStatusLine -Status running -Name 'declared-inputs' -Detail 'Checking configuration and known integration boundaries without source evaluation or network access')
}

try {
    $configuration = Get-HostedAdoptionConfiguration -HostedRoot $HostedRoot -DescriptorPath $DescriptorPath
    $reviewUpstream = $configuration.descriptor.reviewUpstream
    Add-AdoptionFinding descriptor passed 'The descriptor satisfies its contract and all declared references remain inside HostedRoot.'
}
catch { Add-AdoptionFinding descriptor invalid 'The descriptor is missing, malformed, unsafe, or rejected by its schema.' -RelatedFiles @('contracts/adoption/repository-adoption.schema.json') }

if ($null -ne $configuration) {
    foreach ($inputSpec in @(
        @{ name = 'catalog'; reference = $configuration.descriptor.catalog; schema = 'contracts/catalog/instruction-catalog.schema.json' },
        @{ name = 'protected-rules'; reference = $configuration.descriptor.protectedRules; schema = 'contracts/catalog/protected-rules.schema.json' }
    )) {
        try {
            $value = Read-AdoptionJson $inputSpec.reference
            if (-not (Test-AdoptionJson $value $inputSpec.schema)) { throw 'Schema mismatch' }
            Add-AdoptionFinding $inputSpec.name passed 'The declared input satisfies the installed validation contract.' -RelatedFiles @($inputSpec.reference, $inputSpec.schema)
        }
        catch { Add-AdoptionFinding $inputSpec.name invalid 'The declared input is missing or does not satisfy the installed contract; review the configuration and schema together.' -RelatedFiles @($inputSpec.reference, $inputSpec.schema) }
    }
    try {
        $policy = Get-HostedTokenPolicy -Configuration $configuration
        foreach ($area in $policy.policy.areas) {
            $path = Resolve-HostedAdoptionPath -HostedRoot $configuration.hostedRoot -RelativePath $area.path
            if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw 'Missing guidance file' }
        }
        Add-AdoptionFinding token-policy passed 'Every allocation, catalog surface, guidance file and combined membership resolves; actual capacity enforcement is performed by Get-GuidanceCapacity.' -RelatedFiles @('adoption.json', 'tools/internal/workbench/Get-GuidanceCapacity.ps1') -Verification @('tools/tests/Test-RepositoryAdoption.ps1')
        $capacityOutput = @(& pwsh -NoProfile -File (Join-Path $PSScriptRoot '../../internal/workbench/Get-GuidanceCapacity.ps1') -HostedRoot $configuration.hostedRoot -DescriptorPath $DescriptorPath -OutputFormat Json 2>$null)
        $capacity = ($capacityOutput | Out-String) | ConvertFrom-Json -Depth 50
        Assert-HostedGuidanceCapacity -Capacity $capacity -TokenPolicy $policy
        if ($capacity.status -ceq 'passed') {
            Add-AdoptionFinding capacity passed 'Current guidance satisfies every configured area, combined view and overall ceiling.' -RelatedFiles @('adoption.json', 'tools/internal/workbench/Get-GuidanceCapacity.ps1')
        }
        else {
            Add-AdoptionFinding capacity requires-adaptation 'Current guidance exceeds one or more declared budgets; review the content and intended allocations without bypassing enforcement.' -RelatedFiles @('adoption.json', 'tools/internal/workbench/Get-GuidanceCapacity.ps1') -Verification @('tools/internal/workbench/Get-GuidanceCapacity.ps1')
        }
    }
    catch { Add-AdoptionFinding token-policy invalid 'Token policy allocations, paths, catalog references or combination membership are invalid.' -RelatedFiles @('adoption.json', 'contracts/adoption/repository-adoption.schema.json') }

    $collectorPath = 'tools/internal/collection/New-SourceInventory.ps1'
    $collectorAst = $null
    $parserIds = @()
    try {
        $collectorAst = Read-AdoptionScriptAst $collectorPath
        if ($null -ne $collectorAst) {
            $parserFunction = $collectorAst.Find({ param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -ceq 'Invoke-SourceInventoryParser' }, $true)
            if ($null -ne $parserFunction) {
                $switches = @($parserFunction.FindAll({ param($node) $node -is [Management.Automation.Language.SwitchStatementAst] }, $true))
                if ($switches.Count -eq 1) {
                    $clauses = @($switches[0].Clauses)
                    if (@($clauses | Where-Object { $_.Item1 -isnot [Management.Automation.Language.StringConstantExpressionAst] }).Count -eq 0) { $parserIds = @($clauses | ForEach-Object { $_.Item1.Value }) }
                }
            }
        }
    }
    catch { $parserIds = @() }
    try {
        $set = Read-AdoptionJson $configuration.descriptor.sourceDefinitionSet
        if (-not (Test-AdoptionJson $set 'contracts/sources/source-definition-set.schema.json')) { throw 'Invalid lane set' }
        [string[]]$sortedIds = @($set.sourceDefinitionIds)
        [Array]::Sort($sortedIds, [StringComparer]::Ordinal)
        if (@(Compare-Object $sortedIds @($set.sourceDefinitionIds) -SyncWindow 0).Count) { throw 'Lane set must use ordinal order' }
        $definitionRoot = Split-Path -Parent $configuration.descriptor.sourceDefinitionSet
        Add-AdoptionFinding source-lanes passed 'The required lane set is explicitly declared, rather than inferred from directory contents.' -RelatedFiles @($configuration.descriptor.sourceDefinitionSet)
        foreach ($id in $set.sourceDefinitionIds) {
            $definitionReference = ($definitionRoot + '/' + $id + '.json').Replace('\', '/')
            try {
                $definition = Read-AdoptionJson $definitionReference
                if ($definition.id -cne $id) { throw 'Invalid source definition identity' }
                if (-not (Test-AdoptionJson $definition 'contracts/sources/source-definition.schema.json')) {
                    $sourceSchema = Get-Content -LiteralPath (Join-Path $PSScriptRoot '../../../contracts/sources/source-definition.schema.json') -Raw | ConvertFrom-Json -Depth 50
                    $githubBranch = @($sourceSchema.properties.root.oneOf | Where-Object { $_.properties.kind.const -ceq 'github' })
                    if ($definition.root.kind -ceq 'github' -and $githubBranch.Count -eq 1 -and $definition.root.repository -cmatch '^[A-Za-z0-9][A-Za-z0-9_.-]*/[A-Za-z0-9][A-Za-z0-9_.-]*$') {
                        $expectedRepository = [string]$githubBranch[0].properties.repository.const
                        $comparison = ($definition | ConvertTo-Json -Depth 50) | ConvertFrom-Json -Depth 50
                        $comparison.root.repository = $expectedRepository
                        if ($definition.root.repository -cne $expectedRepository -and (Test-AdoptionJson $comparison 'contracts/sources/source-definition.schema.json')) {
                            $changes = [Collections.Generic.List[object]]::new()
                            $changes.Add([ordered]@{ file = 'contracts/sources/source-definition.schema.json'; action = 'Adapt the repository constraint to the declared guidance source without weakening path or source-identity validation.' })
                            if ($null -ne $collectorAst) {
                                $githubFunction = $collectorAst.Find({ param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -ceq 'Get-GitHubSourceDocuments' }, $true)
                                if ($null -ne $githubFunction) {
                                    $guards = @($githubFunction.FindAll({ param($node) $node -is [Management.Automation.Language.BinaryExpressionAst] -and $node.Operator -eq [Management.Automation.Language.TokenKind]::Cne -and $node.Left -is [Management.Automation.Language.VariableExpressionAst] -and $node.Left.VariablePath.UserPath -ceq 'repository' -and $node.Right -is [Management.Automation.Language.StringConstantExpressionAst] -and $node.Right.Value -ceq $expectedRepository }, $true))
                                    if ($guards.Count -eq 1) { $changes.Add([ordered]@{ file = $collectorPath; action = 'Adapt the matching source repository guard while preserving pinned revision, path and access checks.' }) }
                                }
                            }
                            Add-AdoptionFinding "lane/$id/source-repository" requires-adaptation 'The declared GitHub source is structurally valid but blocked by an installed repository constraint.' -RequiredChanges $changes.ToArray() -RelatedFiles @($definitionReference, 'contracts/sources/source-definition.schema.json', $collectorPath) -Verification @('tools/tests/Test-SourceInventory.ps1')
                            continue
                        }
                    }
                    throw 'Invalid source definition'
                }
                if ([IO.Path]::IsPathRooted($definition.root.path) -or $definition.root.path.Contains('\') -or @($definition.root.path.Split('/') | Where-Object { $_ -in @('', '.', '..') }).Count) { throw 'Invalid source root' }
                $contractReference = "contracts/parsers/$($definition.parser).json"
                $contract = Read-AdoptionJson $contractReference
                if ($contract.parserId -cne $definition.parser -or -not (Test-AdoptionJson $contract 'contracts/parsers/parser-contract.schema.json')) { throw 'Invalid parser contract' }
                $related = [Collections.Generic.List[string]]::new()
                $related.Add($definitionReference); $related.Add($contractReference)
                foreach ($dependency in $contract.behaviorFiles) {
                    if (-not $dependency.StartsWith('hosted_copilot/', [StringComparison]::Ordinal)) { throw 'Foreign dependency' }
                    $reference = $dependency.Substring('hosted_copilot/'.Length)
                    $path = Resolve-HostedAdoptionPath -HostedRoot $configuration.hostedRoot -RelativePath $reference
                    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw 'Missing dependency' }
                    $related.Add($reference)
                }
                Add-AdoptionFinding "lane/$id/contracts" passed 'The source definition, parser contract and declared behavior files resolve; this does not establish source-format compatibility.' -RelatedFiles $related.ToArray()
                if (-not $parserIds.Count) {
                    Add-AdoptionFinding "lane/$id/dispatch" not-assessed 'Collector dispatch is not a recognized static declaration; invocation compatibility requires review.' -RelatedFiles @($collectorPath, $contractReference)
                }
                elseif ($definition.parser -cnotin $parserIds) {
                    Add-AdoptionFinding "lane/$id/dispatch" requires-adaptation 'The declared parser ID is absent from the installed collector dispatch.' -RequiredChanges @([ordered]@{ file = $collectorPath; action = 'Integrate the reviewed parser with collection and test its normalized record output.' }) -RelatedFiles $related.ToArray() -Verification @('tools/tests/Test-SourceInventory.ps1')
                }
                else { Add-AdoptionFinding "lane/$id/dispatch" passed 'The installed collector declares a route for this parser ID; document-format and semantic correctness still require parser tests.' -RelatedFiles @($collectorPath, $contractReference) }
            }
            catch { Add-AdoptionFinding "lane/$id/contracts" invalid 'The lane definition, parser contract or behavior dependencies are missing, unsafe, or rejected by the installed schemas. Review these contracts before adapting source formats.' -RelatedFiles @($definitionReference, 'contracts/sources/source-definition.schema.json', $collectorPath) -Verification @('tools/tests/Test-SourceInventory.ps1') }
        }
    }
    catch { Add-AdoptionFinding source-lanes invalid 'The declared source-definition set is missing, unsafe or invalid.' -RelatedFiles @($configuration.descriptor.sourceDefinitionSet, 'contracts/sources/source-definition-set.schema.json') }

    $reviewPath = 'tools/internal/review/Import-PullRequest.ps1'
    try {
        $reviewAst = Read-AdoptionScriptAst $reviewPath
        if ($null -eq $reviewAst) { throw 'Unknown declaration' }
        $assignments = @($reviewAst.FindAll({ param($node) $node -is [Management.Automation.Language.AssignmentStatementAst] -and $node.Left -is [Management.Automation.Language.VariableExpressionAst] -and $node.Left.VariablePath.UserPath -ceq 'canonicalRepository' }, $true))
        if ($assignments.Count -ne 1) { throw 'Unknown declaration' }
        $literals = @($assignments[0].Right.FindAll({ param($node) $node -is [Management.Automation.Language.StringConstantExpressionAst] }, $true))
        if ($literals.Count -ne 1 -or $assignments[0].Right.Extent.Text -cne $literals[0].Extent.Text) { throw 'Computed declaration' }
        if (-not $reviewUpstream.Equals($literals[0].Value, [StringComparison]::OrdinalIgnoreCase)) {
            Add-AdoptionFinding review-upstream requires-adaptation 'The installed review integration declares a different canonical repository.' -RequiredChanges @([ordered]@{ file = $reviewPath; action = 'Adapt canonical repository validation while preserving verified fork-family and authorization checks.' }) -RelatedFiles @($reviewPath) -Verification @('tools/tests/Test-HostedReviewWorkflow.ps1')
        }
        else { Add-AdoptionFinding review-upstream passed 'The installed canonical repository declaration matches the requested review upstream; live authorization is not assessed.' -RelatedFiles @($reviewPath) }
    }
    catch { Add-AdoptionFinding review-upstream not-assessed 'The installed review repository declaration is dynamic, missing or unrecognized and requires manual review.' -RelatedFiles @($reviewPath) }
    Add-AdoptionFinding integration-coverage not-assessed 'Parser input formats, arbitrary rule categories, Workbench surface mappings, runtime model limits, live GitHub authorization and fork relationships require integration review; this offline report does not establish universal adoption readiness.' -RelatedFiles @('contracts/sources/source-inventory.schema.json', 'workbench/app.js', $collectorPath, $reviewPath)
}

$statuses = @($findings.status)
$status = if ('invalid' -cin $statuses) { 'invalid' } elseif ('requires-adaptation' -cin $statuses) { 'changes-required' } elseif ('not-assessed' -cin $statuses) { 'review-required' } else { 'passed' }
$result = [ordered]@{ schemaVersion = 1; kind = 'hosted-repository-adoption-preflight'; status = $status; reviewUpstream = $reviewUpstream; findings = $findings.ToArray() }
if ($OutputFormat -eq 'Json') { $result | ConvertTo-Json -Depth 30 }
else {
    Write-ValidationSectionHeader -Title 'Hosted repository adoption summary'
    Write-ValidationSummary -Fields ([ordered]@{ Status = $status.ToUpperInvariant(); Checks = $findings.Count; 'Read Only' = 'Yes'; 'Network Access' = 'None' })
    Write-ValidationSectionHeader -Title 'Adoption findings'
    Write-ValidationTwoColumnTable -Rows $findings.ToArray() -FirstHeader 'status' -FirstProperty 'status' -SecondHeader 'check' -SecondProperty 'checkId' -UppercaseFirst
    Write-ValidationSectionHeader -Title 'Integration review'
    foreach ($finding in @($findings | Where-Object status -CNE 'passed')) {
        Write-ValidationSummary -Fields ([ordered]@{ Check = $finding.checkId; Status = $finding.status.ToUpperInvariant(); Reason = $finding.reason })
        $details = @(
            foreach ($change in $finding.requiredChanges) { [pscustomobject]@{ action = 'change'; detail = "$($change.file): $($change.action)" } }
            foreach ($reference in $finding.relatedFiles) { [pscustomobject]@{ action = 'review'; detail = $reference } }
            foreach ($reference in $finding.verification) { [pscustomobject]@{ action = 'verify'; detail = $reference } }
        )
        if ($details.Count) {
            Write-ValidationTwoColumnTable -Rows $details -FirstHeader 'action' -FirstProperty 'action' -SecondHeader 'detail' -SecondProperty 'detail' -UppercaseFirst
        }
        Complete-ValidationTextOutput
    }
    Complete-ValidationTextOutput
}
if ($status -in @('invalid', 'changes-required')) { exit 1 }
if ($status -eq 'review-required') { exit 2 }
