Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Import-Module (Join-Path $PSScriptRoot '../shared/HostedToolkit.Helpers.psm1')

function Get-ReconciliationProperty {
    param(
        [Parameter(Mandatory = $true)][object]$Value,
        [Parameter(Mandatory = $true)][string]$Name,
        [switch]$AllowMissing
    )

    if ($Value -is [Collections.IDictionary]) {
        if ($Value.Contains($Name)) {
            return $Value[$Name]
        }
    }
    else {
        $property = $Value.PSObject.Properties[$Name]
        if ($null -ne $property) {
            return $property.Value
        }
    }
    if ($AllowMissing) {
        return $null
    }
    throw "Required reconciliation property `$Name` is missing."
}

function Get-SemanticNodeKey {
    param(
        [Parameter(Mandatory = $true)][ValidateSet('assessment', 'catalog-rule', 'protected-rule')][string]$NodeType,
        [Parameter(Mandatory = $true)][object]$Identity
    )

    if ($NodeType -ceq 'assessment') {
        return "assessment:$(Get-JsonSnapshotSha256 -Value $Identity)"
    }
    return "${NodeType}:$([string](Get-ReconciliationProperty -Value $Identity -Name 'ruleId'))"
}

function New-SemanticComponent {
    param(
        [Parameter(Mandatory = $true)][string[]]$NodeKeys,
        [Parameter(Mandatory = $true)][Collections.IDictionary]$NodesByKey,
        [AllowEmptyString()][string]$SemanticSummary
    )

    [Array]::Sort($NodeKeys, [StringComparer]::Ordinal)
    $summary = if ([string]::IsNullOrWhiteSpace($SemanticSummary)) {
        @($NodeKeys | ForEach-Object { [string](Get-ReconciliationProperty -Value $NodesByKey[$_] -Name 'routingText') }) -join "`n"
    }
    else {
        $SemanticSummary
    }
    return [pscustomobject][ordered]@{
        componentKey = "component:$(Get-JsonSnapshotSha256 -Value $NodeKeys)"
        nodeKeys = $NodeKeys
        summary = $summary
    }
}

function Split-ReconciliationPayloads {
    param(
        [Parameter(Mandatory = $true)][object[]]$Items,
        [Parameter(Mandatory = $true)][ValidateRange(1, [int]::MaxValue)][int]$MaxBytes,
        [Parameter(Mandatory = $true)][string]$CollectionName,
        [Parameter(Mandatory = $true)][string]$Stage,
        [Parameter(Mandatory = $true)][scriptblock]$GetItemKey
    )

    $shards = [Collections.Generic.List[object]]::new()
    $current = [Collections.Generic.List[object]]::new()
    foreach ($item in $Items) {
        $candidateItems = @($current.ToArray()) + @($item)
        $candidatePayload = [ordered]@{ $CollectionName = $candidateItems }
        $candidateBytes = (ConvertTo-JsonSnapshotBytes -Value $candidatePayload).Length
        if ($candidateBytes -gt $MaxBytes -and $current.Count -gt 0) {
            $payload = [ordered]@{ $CollectionName = @($current.ToArray()) }
            $bytes = (ConvertTo-JsonSnapshotBytes -Value $payload).Length
            $shards.Add([pscustomobject][ordered]@{ shardKey = "${Stage}:$(Get-JsonSnapshotSha256 -Value $payload)"; byteCount = $bytes; payload = $payload })
            $current.Clear()
            $candidateItems = @($item)
            $candidatePayload = [ordered]@{ $CollectionName = $candidateItems }
            $candidateBytes = (ConvertTo-JsonSnapshotBytes -Value $candidatePayload).Length
        }
        if ($candidateBytes -gt $MaxBytes) {
            $itemKey = & $GetItemKey $item
            throw ('{0} item `{1}` requires {2} bytes and exceeds the {0} shard budget of {3} bytes.' -f $Stage, $itemKey, $candidateBytes, $MaxBytes)
        }
        $current.Add($item)
    }
    if ($current.Count -gt 0) {
        $payload = [ordered]@{ $CollectionName = @($current.ToArray()) }
        $bytes = (ConvertTo-JsonSnapshotBytes -Value $payload).Length
        $shards.Add([pscustomobject][ordered]@{ shardKey = "${Stage}:$(Get-JsonSnapshotSha256 -Value $payload)"; byteCount = $bytes; payload = $payload })
    }
    return $shards.ToArray()
}

function Merge-ReconciliationGroups {
    param(
        [Parameter(Mandatory = $true)][object[]]$Items,
        [object[]]$Suggestions = @(),
        [Parameter(Mandatory = $true)][string]$ItemKeyProperty,
        [Parameter(Mandatory = $true)][string]$SuggestionKeysProperty,
        [Parameter(Mandatory = $true)][string]$Stage
    )

    $itemsByKey = @{}
    foreach ($item in $Items) {
        $key = [string](Get-ReconciliationProperty -Value $item -Name $ItemKeyProperty)
        if ($itemsByKey.ContainsKey($key)) {
            throw "Duplicate $Stage input key `$key`."
        }
        $itemsByKey[$key] = $item
    }

    $mentioned = @{}
    $groups = [Collections.Generic.List[object]]::new()
    foreach ($suggestion in $Suggestions) {
        [string[]]$keys = @((Get-ReconciliationProperty -Value $suggestion -Name $SuggestionKeysProperty) | ForEach-Object { [string]$_ })
        if ($keys.Count -eq 0) {
            throw "$Stage suggestion must contain at least one key."
        }
        $local = @{}
        foreach ($key in $keys) {
            if (-not $itemsByKey.ContainsKey($key)) {
                throw "$Stage suggestion references unknown key `$key`."
            }
            if ($local.ContainsKey($key) -or $mentioned.ContainsKey($key)) {
                throw "$Stage suggestion contains duplicate membership for key `$key`."
            }
            $local[$key] = $true
            $mentioned[$key] = $true
        }
        [Array]::Sort($keys, [StringComparer]::Ordinal)
        $groups.Add([pscustomobject][ordered]@{
            keys = @($keys)
            semanticSummary = [string](Get-ReconciliationProperty -Value $suggestion -Name 'semanticSummary' -AllowMissing)
        })
    }

    [string[]]$allKeys = @($itemsByKey.Keys)
    [Array]::Sort($allKeys, [StringComparer]::Ordinal)
    foreach ($key in $allKeys) {
        if (-not $mentioned.ContainsKey($key)) {
            $groups.Add([pscustomobject][ordered]@{ keys = @($key); semanticSummary = $null })
        }
    }
    return $groups.ToArray()
}

function New-HierarchicalSemanticLedger {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][object]$AssessmentBaseline,
        [Parameter(Mandatory = $true)][object]$Catalog,
        [Parameter(Mandatory = $true)][object]$ProtectedCatalog
    )

    $nodes = [Collections.Generic.List[object]]::new()
    foreach ($entry in @(Get-ReconciliationProperty -Value $AssessmentBaseline -Name 'entries')) {
        $sourceRef = Get-ReconciliationProperty -Value $entry -Name 'sourceRef'
        foreach ($assessment in @(Get-ReconciliationProperty -Value $entry -Name 'assessments')) {
            $assessmentRef = [ordered]@{
                sourceDefinitionId = [string](Get-ReconciliationProperty -Value $sourceRef -Name 'sourceDefinitionId')
                sourceId = [string](Get-ReconciliationProperty -Value $sourceRef -Name 'sourceId')
                contentSha256 = [string](Get-ReconciliationProperty -Value $sourceRef -Name 'contentSha256')
                assessmentId = [string](Get-ReconciliationProperty -Value $assessment -Name 'assessmentId')
            }
            $hostedApplicable = [bool](Get-ReconciliationProperty -Value $assessment -Name 'hostedApplicable')
            $title = [string](Get-ReconciliationProperty -Value $assessment -Name 'title')
            $sourceMeaning = [string](Get-ReconciliationProperty -Value $assessment -Name 'sourceMeaning')
            $impact = [string](Get-ReconciliationProperty -Value $assessment -Name 'impactDescription')
            $nodes.Add([pscustomobject][ordered]@{
                nodeKey = Get-SemanticNodeKey -NodeType 'assessment' -Identity $assessmentRef
                nodeType = 'assessment'
                sourceRef = $assessmentRef
                sourceContentSha256 = [string]$assessmentRef.contentSha256
                applicability = [pscustomobject][ordered]@{ hostedApplicable = $hostedApplicable; rationale = [string](Get-ReconciliationProperty -Value $assessment -Name 'applicabilityRationale') }
                routingText = "$title`n$sourceMeaning`n$impact"
                original = $assessment
            })
        }
    }

    foreach ($catalogRule in @(Get-ReconciliationProperty -Value $Catalog -Name 'rules')) {
        $ruleId = [string](Get-ReconciliationProperty -Value $catalogRule -Name 'id')
        $identity = [ordered]@{ ruleId = $ruleId }
        $nodes.Add([pscustomobject][ordered]@{
            nodeKey = Get-SemanticNodeKey -NodeType 'catalog-rule' -Identity $identity
            nodeType = 'catalog-rule'
            sourceRef = [pscustomobject][ordered]@{ catalog = 'mutable'; ruleId = $ruleId }
            sourceContentSha256 = Get-JsonSnapshotSha256 -Value $catalogRule
            applicability = [pscustomobject][ordered]@{ hostedApplicable = $true; rationale = 'Mutable catalog rules are Hosted semantic nodes.' }
            routingText = "$ruleId`n$([string](Get-ReconciliationProperty -Value $catalogRule -Name 'text'))"
            original = $catalogRule
        })
    }

    foreach ($protectedRule in @(Get-ReconciliationProperty -Value $ProtectedCatalog -Name 'rules')) {
        $ruleId = [string](Get-ReconciliationProperty -Value $protectedRule -Name 'id')
        $identity = [ordered]@{ ruleId = $ruleId }
        $title = [string](Get-ReconciliationProperty -Value $protectedRule -Name 'title' -AllowMissing)
        $nodes.Add([pscustomobject][ordered]@{
            nodeKey = Get-SemanticNodeKey -NodeType 'protected-rule' -Identity $identity
            nodeType = 'protected-rule'
            sourceRef = [pscustomobject][ordered]@{ catalog = 'protected'; ruleId = $ruleId }
            sourceContentSha256 = Get-JsonSnapshotSha256 -Value $protectedRule
            applicability = [pscustomobject][ordered]@{ hostedApplicable = $true; rationale = 'Protected catalog rules are Hosted semantic nodes.' }
            routingText = "$ruleId`n$title`n$([string](Get-ReconciliationProperty -Value $protectedRule -Name 'text'))"
            original = $protectedRule
        })
    }

    $orderedNodes = @($nodes.ToArray() | Sort-Object -Property nodeKey -CaseSensitive)
    $duplicateNode = @($orderedNodes | Group-Object -Property nodeKey | Where-Object Count -gt 1 | Select-Object -First 1)
    if ($duplicateNode.Count -gt 0) {
        throw "Semantic ledger contains duplicate node key `$($duplicateNode[0].Name)`."
    }
    $excluded = @($orderedNodes | Where-Object { $_.nodeType -ceq 'assessment' -and -not $_.applicability.hostedApplicable } | ForEach-Object nodeKey)
    $eligible = @($orderedNodes | Where-Object { $_.nodeType -ne 'assessment' -or $_.applicability.hostedApplicable } | ForEach-Object nodeKey)
    return [pscustomobject][ordered]@{
        schemaVersion = 1
        nodes = $orderedNodes
        excludedAssessmentNodeKeys = $excluded
        eligibleNodeKeys = $eligible
        nodesSha256 = Get-JsonSnapshotSha256 -Value $orderedNodes
    }
}

function New-ByteBoundRoutingShards {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][object]$Ledger,
        [Parameter(Mandatory = $true)][ValidateRange(1, [int]::MaxValue)][int]$MaxBytes
    )

    $eligible = @{}
    foreach ($key in @(Get-ReconciliationProperty -Value $Ledger -Name 'eligibleNodeKeys')) {
        $eligible[[string]$key] = $true
    }
    $routingNodes = @((Get-ReconciliationProperty -Value $Ledger -Name 'nodes') | Where-Object { $eligible.ContainsKey([string]$_.nodeKey) } | ForEach-Object {
        [pscustomobject][ordered]@{ nodeKey = $_.nodeKey; nodeType = $_.nodeType; sourceRef = $_.sourceRef; sourceContentSha256 = $_.sourceContentSha256; applicability = $_.applicability; semanticSummary = $_.routingText }
    })
    return @(Split-ReconciliationPayloads -Items $routingNodes -MaxBytes $MaxBytes -CollectionName 'nodes' -Stage 'routing' -GetItemKey { param($item) $item.nodeKey })
}

function Merge-LocalRoutingSuggestions {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][object]$Ledger,
        [object[]]$Suggestions = @()
    )

    $nodesByKey = @{}
    $eligibleNodes = [Collections.Generic.List[object]]::new()
    $eligible = @{}
    foreach ($key in @(Get-ReconciliationProperty -Value $Ledger -Name 'eligibleNodeKeys')) {
        $eligible[[string]$key] = $true
    }
    foreach ($node in @(Get-ReconciliationProperty -Value $Ledger -Name 'nodes')) {
        $key = [string]$node.nodeKey
        if ($eligible.ContainsKey($key)) {
            $nodesByKey[$key] = $node
            $eligibleNodes.Add($node)
        }
    }
    $groups = @(Merge-ReconciliationGroups -Items $eligibleNodes.ToArray() -Suggestions $Suggestions -ItemKeyProperty 'nodeKey' -SuggestionKeysProperty 'nodeKeys' -Stage 'routing')
    $components = @($groups | ForEach-Object { New-SemanticComponent -NodeKeys @($_.keys) -NodesByKey $nodesByKey -SemanticSummary ([string]$_.semanticSummary) } | Sort-Object -Property componentKey -CaseSensitive)
    return $components
}

function New-ByteBoundConsolidationShards {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][object[]]$Components,
        [Parameter(Mandatory = $true)][ValidateRange(1, [int]::MaxValue)][int]$MaxBytes
    )

    $summaries = @($Components | Sort-Object -Property componentKey -CaseSensitive | ForEach-Object {
        [pscustomobject][ordered]@{ componentKey = $_.componentKey; nodeCount = @($_.nodeKeys).Count; summary = [string]$_.summary }
    })
    if ($summaries.Count -eq 0) {
        return @()
    }

    $emptyPayloadBytes = (ConvertTo-JsonSnapshotBytes -Value ([ordered]@{ components = @() })).Length
    $blockBudget = [Math]::Max($emptyPayloadBytes + 1, [int][Math]::Floor(($MaxBytes + $emptyPayloadBytes) / 2))
    $blocks = [Collections.Generic.List[object[]]]::new()
    $current = [Collections.Generic.List[object]]::new()
    foreach ($summary in $summaries) {
        $candidate = @($current.ToArray()) + @($summary)
        $candidateBytes = (ConvertTo-JsonSnapshotBytes -Value ([ordered]@{ components = $candidate })).Length
        if ($candidateBytes -gt $blockBudget -and $current.Count -gt 0) {
            $blocks.Add(@($current.ToArray()))
            $current.Clear()
            $candidate = @($summary)
            $candidateBytes = (ConvertTo-JsonSnapshotBytes -Value ([ordered]@{ components = $candidate })).Length
        }
        if ($candidateBytes -gt $MaxBytes) {
            throw "Consolidation component `$($summary.componentKey)` requires $candidateBytes bytes and exceeds the consolidation shard budget of $MaxBytes bytes."
        }
        $current.Add($summary)
    }
    if ($current.Count -gt 0) {
        $blocks.Add(@($current.ToArray()))
    }

    $shards = [Collections.Generic.List[object]]::new()
    for ($leftIndex = 0; $leftIndex -lt $blocks.Count; $leftIndex++) {
        for ($rightIndex = $leftIndex; $rightIndex -lt $blocks.Count; $rightIndex++) {
            $items = if ($leftIndex -eq $rightIndex) { @($blocks[$leftIndex]) } else { @($blocks[$leftIndex]) + @($blocks[$rightIndex]) }
            $payload = [ordered]@{ components = $items }
            $bytes = (ConvertTo-JsonSnapshotBytes -Value $payload).Length
            if ($bytes -gt $MaxBytes) {
                throw "Consolidation block pair $leftIndex/$rightIndex requires $bytes bytes and exceeds the consolidation shard budget of $MaxBytes bytes."
            }
            $shards.Add([pscustomobject][ordered]@{ shardKey = "consolidation:$(Get-JsonSnapshotSha256 -Value $payload)"; byteCount = $bytes; payload = $payload })
        }
    }
    return $shards.ToArray()
}

function Merge-ConsolidationSuggestions {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][object]$Ledger,
        [Parameter(Mandatory = $true)][object[]]$Components,
        [object[]]$Suggestions = @()
    )

    $nodesByKey = @{}
    foreach ($node in @(Get-ReconciliationProperty -Value $Ledger -Name 'nodes')) {
        $nodesByKey[[string]$node.nodeKey] = $node
    }
    $componentsByKey = @{}
    $parentByKey = @{}
    foreach ($component in $Components) {
        $componentKey = [string]$component.componentKey
        if ($componentsByKey.ContainsKey($componentKey)) {
            throw "Duplicate consolidation input key `$componentKey`."
        }
        $componentsByKey[$componentKey] = $component
        $parentByKey[$componentKey] = $componentKey
    }

    $findRoot = {
        param([string]$Key)

        $root = $Key
        while ([string]$parentByKey[$root] -cne $root) {
            $root = [string]$parentByKey[$root]
        }
        $cursor = $Key
        while ([string]$parentByKey[$cursor] -cne $root) {
            $next = [string]$parentByKey[$cursor]
            $parentByKey[$cursor] = $root
            $cursor = $next
        }
        return $root
    }

    $validatedSuggestions = [Collections.Generic.List[object]]::new()
    foreach ($suggestion in $Suggestions) {
        [string[]]$componentKeys = @((Get-ReconciliationProperty -Value $suggestion -Name 'componentKeys') | ForEach-Object { [string]$_ })
        if ($componentKeys.Count -lt 2) {
            throw 'Consolidation suggestion must contain at least two component keys.'
        }
        $localKeys = @{}
        foreach ($componentKey in $componentKeys) {
            if (-not $componentsByKey.ContainsKey($componentKey)) {
                throw "Consolidation suggestion references unknown key `$componentKey`."
            }
            if ($localKeys.ContainsKey($componentKey)) {
                throw "Consolidation suggestion contains duplicate component key `$componentKey`."
            }
            $localKeys[$componentKey] = $true
        }
        [Array]::Sort($componentKeys, [StringComparer]::Ordinal)
        $anchorRoot = & $findRoot $componentKeys[0]
        foreach ($componentKey in @($componentKeys | Select-Object -Skip 1)) {
            $otherRoot = & $findRoot $componentKey
            if ($anchorRoot -cne $otherRoot) {
                $survivor = @($anchorRoot, $otherRoot | Sort-Object -CaseSensitive)[0]
                $mergedRoot = if ($survivor -ceq $anchorRoot) { $otherRoot } else { $anchorRoot }
                $parentByKey[$mergedRoot] = $survivor
                $anchorRoot = $survivor
            }
        }
        $validatedSuggestions.Add([pscustomobject][ordered]@{ componentKeys = @($componentKeys); semanticSummary = [string](Get-ReconciliationProperty -Value $suggestion -Name 'semanticSummary' -AllowMissing) })
    }

    $keysByRoot = @{}
    foreach ($componentKey in @($componentsByKey.Keys | Sort-Object -CaseSensitive)) {
        $root = & $findRoot $componentKey
        if (-not $keysByRoot.ContainsKey($root)) {
            $keysByRoot[$root] = [Collections.Generic.List[string]]::new()
        }
        $keysByRoot[$root].Add($componentKey)
    }

    $merged = @($keysByRoot.Keys | Sort-Object -CaseSensitive | ForEach-Object {
        $root = [string]$_
        [string[]]$groupComponentKeys = @($keysByRoot[$root].ToArray())
        [Array]::Sort($groupComponentKeys, [StringComparer]::Ordinal)
        if ($groupComponentKeys.Count -eq 1) {
            $componentsByKey[$groupComponentKeys[0]]
        }
        else {
            $nodeKeys = @($groupComponentKeys | ForEach-Object { @(Get-ReconciliationProperty -Value $componentsByKey[[string]$_] -Name 'nodeKeys') })
            $summary = @($validatedSuggestions | Where-Object {
                $suggestionRoot = & $findRoot ([string]$_.componentKeys[0])
                $suggestionRoot -ceq $root -and -not [string]::IsNullOrWhiteSpace([string]$_.semanticSummary)
            } | ForEach-Object { [string]$_.semanticSummary } | Sort-Object -Unique -CaseSensitive | Select-Object -First 1)
            New-SemanticComponent -NodeKeys @($nodeKeys) -NodesByKey $nodesByKey -SemanticSummary ([string]$summary)
        }
    } | Sort-Object -Property componentKey -CaseSensitive)
    return $merged
}

function New-RehydratedSynthesisBatches {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][object]$Ledger,
        [Parameter(Mandatory = $true)][object[]]$Components,
        [Parameter(Mandatory = $true)][ValidateRange(1, [int]::MaxValue)][int]$MaxBytes
    )

    $nodesByKey = @{}
    foreach ($node in @(Get-ReconciliationProperty -Value $Ledger -Name 'nodes')) {
        $nodesByKey[[string]$node.nodeKey] = $node
    }
    $eligible = @{}
    foreach ($key in @(Get-ReconciliationProperty -Value $Ledger -Name 'eligibleNodeKeys')) {
        $eligible[[string]$key] = $true
    }
    $covered = @{}
    $rehydrated = [Collections.Generic.List[object]]::new()
    foreach ($component in @($Components | Sort-Object -Property componentKey -CaseSensitive)) {
        $componentKey = [string]$component.componentKey
        $componentNodes = @($component.nodeKeys | ForEach-Object {
            $nodeKey = [string]$_
            if (-not $eligible.ContainsKey($nodeKey)) {
                throw "Synthesis component `$componentKey` references ineligible or unknown node `$nodeKey`."
            }
            if ($covered.ContainsKey($nodeKey)) {
                throw "Synthesis components contain duplicate node membership for `$nodeKey`."
            }
            $covered[$nodeKey] = $true
            $nodesByKey[$nodeKey]
        })
        if (@($componentNodes | Where-Object nodeType -CEQ 'assessment').Count -gt 0) {
            $rehydrated.Add([pscustomobject][ordered]@{ componentKey = $componentKey; nodes = $componentNodes })
        }
    }
    foreach ($nodeKey in $eligible.Keys) {
        if (-not $covered.ContainsKey($nodeKey)) {
            throw "Synthesis components omit eligible node `$nodeKey`."
        }
    }
    foreach ($nodeKey in @((Get-ReconciliationProperty -Value $Ledger -Name 'excludedAssessmentNodeKeys') | Sort-Object -CaseSensitive)) {
        $node = $nodesByKey[[string]$nodeKey]
        if ($null -eq $node -or [string]$node.nodeType -cne 'assessment') {
            throw "Excluded assessment node `$nodeKey` is missing from the semantic ledger."
        }
        $excludedComponent = New-SemanticComponent -NodeKeys @([string]$nodeKey) -NodesByKey $nodesByKey
        $rehydrated.Add([pscustomobject][ordered]@{ componentKey = [string]$excludedComponent.componentKey; nodes = @($node) })
    }

    try {
        return @(Split-ReconciliationPayloads -Items $rehydrated.ToArray() -MaxBytes $MaxBytes -CollectionName 'components' -Stage 'synthesis' -GetItemKey { param($item) $item.componentKey })
    }
    catch {
        if ($_.Exception.Message -like 'synthesis item *') {
            throw ($_.Exception.Message -replace '^synthesis item `([^`]+)` requires ([0-9]+) bytes and exceeds the synthesis shard budget of ([0-9]+) bytes\.$', 'Semantic component `$1` requires $2 bytes and exceeds the synthesis batch budget of $3 bytes; semantic components are indivisible.')
        }
        throw
    }
}

Export-ModuleMember -Function @(
    'New-HierarchicalSemanticLedger',
    'New-ByteBoundRoutingShards',
    'Merge-LocalRoutingSuggestions',
    'New-ByteBoundConsolidationShards',
    'Merge-ConsolidationSuggestions',
    'New-RehydratedSynthesisBatches'
)
