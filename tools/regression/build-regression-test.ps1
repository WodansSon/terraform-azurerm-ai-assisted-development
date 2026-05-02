param(
    [string] $SpecPath,

    [string] $Id,

    [string] $Title,

    [ValidateSet("code-review-local-changes", "code-review-committed-changes", "code-review-docs", "docs-writer", "resource-implementation", "acceptance-testing")]
    [string] $Task,

    [string] $Description,

    [string[]] $ChangedFiles,

    [ValidateSet("real-pr", "local-diff", "synthetic")]
    [string] $SourceKind = "real-pr",

    [ValidateSet("planned", "ready", "adjudicated", "retired")]
    [string] $CaseStatus = "planned",

    [string] $ScopeNotes,

    [string] $CaseNotes,

    [string[]] $MustCatchDescription,

    [string[]] $MustNotFlagDescription,

    [switch] $IncludeSampleOutput,

    [switch] $Force,

    [string] $CasesDirectory = (Join-Path $PSScriptRoot "cases"),

    [string] $FixturesDirectory = (Join-Path $PSScriptRoot "fixtures"),

    [string] $ResultsDirectory = (Join-Path $PSScriptRoot "results")
)

$ErrorActionPreference = "Stop"

. (Join-Path $PSScriptRoot "test/TestSpecDefinition.ps1")

function Get-HclDecodedString {
    param([string] $Value)

    $decoded = $Value -replace '\\"', '"'
    $decoded = $decoded -replace '\\\\', '\\'
    return $decoded
}

function Get-HclStringArrayValues {
    param([string] $Content)

    $values = @()
    $matches = [regex]::Matches($Content, '"((?:[^"\\]|\\.)*)"')
    foreach ($match in $matches) {
        $values += Get-HclDecodedString -Value $match.Groups[1].Value
    }

    return $values
}

function Get-HclAssignment {
    param([string] $Line)

    if ($Line -match '^([a-z_]+)\s*=\s*"((?:[^"\\]|\\.)*)"\s*$') {
        return [pscustomobject]@{ key = $Matches[1]; kind = 'string'; value = (Get-HclDecodedString -Value $Matches[2]) }
    }

    if ($Line -match '^([a-z_]+)\s*=\s*(true|false)\s*$') {
        return [pscustomobject]@{ key = $Matches[1]; kind = 'bool'; value = ($Matches[2] -eq 'true') }
    }

    if ($Line -match '^([a-z_]+)\s*=\s*\[\s*\]\s*$') {
        return [pscustomobject]@{ key = $Matches[1]; kind = 'array'; value = @() }
    }

    if ($Line -match '^([a-z_]+)\s*=\s*\[(.*)\]\s*$') {
        return [pscustomobject]@{ key = $Matches[1]; kind = 'array'; value = @(Get-HclStringArrayValues -Content $Matches[2]) }
    }

    if ($Line -match '^([a-z_]+)\s*=\s*\[$') {
        return [pscustomobject]@{ key = $Matches[1]; kind = 'array-start'; value = $null }
    }

    throw "unsupported HCL assignment: $Line"
}

function Get-HclBraceDelta {
    param([string] $Line)

    $sanitized = [regex]::Replace($Line, '"(?:[^"\\]|\\.)*"|''(?:[^''\\]|\\.)*''', '')
    $openCount = ([regex]::Matches($sanitized, '\{')).Count
    $closeCount = ([regex]::Matches($sanitized, '\}')).Count
    return ($openCount - $closeCount)
}

function Get-ConfigBlockBody {
    param(
        [string[]] $Lines,
        [int] $StartLineIndex
    )

    $bodyLines = @()
    $braceDepth = 1
    $lineIndex = $StartLineIndex + 1

    while ($lineIndex -lt $Lines.Count) {
        $rawLine = $Lines[$lineIndex]
        $updatedDepth = $braceDepth + (Get-HclBraceDelta -Line $rawLine)

        if ($updatedDepth -lt 0) {
            throw "invalid brace structure inside config block"
        }

        if ($updatedDepth -eq 0 -and $rawLine.Trim() -eq '}') {
            $braceDepth = $updatedDepth
            break
        }

        $bodyLines += $rawLine.TrimEnd()
        $braceDepth = $updatedDepth
        $lineIndex++
    }

    if ($braceDepth -ne 0) {
        throw "unterminated config block in regression test spec"
    }

    return [pscustomobject]@{
        body = (($bodyLines -join "`n").Trim())
        endLineIndex = $lineIndex
    }
}

function Set-RegressionTestValue {
    param(
        $Spec,
        [string] $ContextName,
        $ContextData,
        $Assignment
    )

    $definition = Get-RegressionTestDefinition

    switch ($ContextName) {
        'root' {
            switch ($Assignment.key) {
                'title' { $Spec.title = [string]$Assignment.value; break }
                default { throw "unsupported root property '$($Assignment.key)' in regression test spec" }
            }
            break
        }
        'test_case' {
            switch ($Assignment.key) {
                'task' {
                    Assert-RegressionTestAllowedValue -Definition $definition -EnumName 'task' -Value ([string]$Assignment.value) -Context 'test_case.task'
                    $Spec.task = [string]$Assignment.value
                    break
                }
                'source_kind' {
                    Assert-RegressionTestAllowedValue -Definition $definition -EnumName 'sourceKind' -Value ([string]$Assignment.value) -Context 'test_case.source_kind'
                    $Spec.sourceKind = [string]$Assignment.value
                    break
                }
                'case_status' {
                    Assert-RegressionTestAllowedValue -Definition $definition -EnumName 'caseStatus' -Value ([string]$Assignment.value) -Context 'test_case.case_status'
                    $Spec.caseStatus = [string]$Assignment.value
                    break
                }
                'changed_files' { $Spec.changedFiles = @($Assignment.value); break }
                'notes' { $Spec.scopeNotes = [string]$Assignment.value; break }
                default { throw "unsupported property '$($Assignment.key)' inside test_case block" }
            }
            break
        }
        'config' {
            switch ($Assignment.key) {
                'body' { $Spec.config = [string]$Assignment.value; break }
                default { throw "unsupported property '$($Assignment.key)' inside config block" }
            }
            break
        }
        'rules' {
            switch ($Assignment.key) {
                'description' { $Spec.description = [string]$Assignment.value; break }
                'notes' { $Spec.caseNotes = [string]$Assignment.value; break }
                'include_sample_output' { $Spec.includeSampleOutput = [bool]$Assignment.value; break }
                default { throw "unsupported property '$($Assignment.key)' inside rules block" }
            }
            break
        }
        'must_catch' {
            switch ($Assignment.key) {
                'description' { $ContextData.description = [string]$Assignment.value; break }
                'severity' {
                    Assert-RegressionTestAllowedValue -Definition $definition -EnumName 'severity' -Value ([string]$Assignment.value) -Context 'must_catch.severity'
                    $ContextData.severity = [string]$Assignment.value
                    break
                }
                'file' { $ContextData.file = [string]$Assignment.value; break }
                default { throw "unsupported property '$($Assignment.key)' inside must_catch block" }
            }
            break
        }
        'must_not_flag' {
            switch ($Assignment.key) {
                'description' { $ContextData.description = [string]$Assignment.value; break }
                default { throw "unsupported property '$($Assignment.key)' inside must_not_flag block" }
            }
            break
        }
        default {
            throw "unsupported regression test context '$ContextName'"
        }
    }
}

function Get-RegressionTestSpec {
    param([string] $Path)

    if (-not (Test-Path -LiteralPath $Path)) {
        throw "file not found: $Path"
    }

    $spec = [ordered]@{
        id = $null
        title = $null
        runName = $null
        task = $null
        description = $null
        config = $null
        sourceKind = 'real-pr'
        caseStatus = 'planned'
        scopeNotes = $null
        caseNotes = $null
        changedFiles = @()
        includeSampleOutput = $false
        mustCatch = @()
        mustNotFlag = @()
    }

    $lines = Get-Content -LiteralPath $Path
    $seenRoot = $false
    $blockStack = New-Object System.Collections.ArrayList
    $currentArray = $null
    $currentArrayValues = @()
    $lineIndex = 0

    while ($lineIndex -lt $lines.Count) {
        $rawLine = $lines[$lineIndex]
        $line = $rawLine.Trim()
        if ([string]::IsNullOrWhiteSpace($line) -or $line -match '^(#|//)') {
            $lineIndex++
            continue
        }

        if ($null -ne $currentArray) {
            if ($line -eq ']') {
                $assignment = [pscustomobject]@{ key = $currentArray.key; kind = 'array'; value = @($currentArrayValues) }
                Set-RegressionTestValue -Spec $spec -ContextName $currentArray.contextName -ContextData $currentArray.contextData -Assignment $assignment
                $currentArray = $null
                $currentArrayValues = @()
                $lineIndex++
                continue
            }

            $currentArrayValues += @(Get-HclStringArrayValues -Content $line)
            $lineIndex++
            continue
        }

        if (-not $seenRoot) {
            if ($line -match '^(AccTest)\s+"([a-zA-Z0-9-]+)"\s+"([a-zA-Z0-9_-]+)"\s*\{$') {
                $spec.id = Convert-ToKebabCase -Value $Matches[2]
                $spec.runName = $Matches[3]
                $seenRoot = $true
                [void]$blockStack.Add([pscustomobject]@{ name = 'test'; label = $spec.id; data = $null })
                $lineIndex++
                continue
            }

            throw "expected regression test root block, got: $line"
        }

        if ($line -eq '}') {
            if ($blockStack.Count -eq 0) {
                throw "unexpected closing brace in regression test spec"
            }

            $currentBlock = $blockStack[$blockStack.Count - 1]
            $blockStack.RemoveAt($blockStack.Count - 1)

            switch ($currentBlock.name) {
                'must_catch' {
                    if ([string]::IsNullOrWhiteSpace($currentBlock.data.description)) {
                        throw "must_catch block requires description"
                    }
                    if ([string]::IsNullOrWhiteSpace($currentBlock.data.severity)) {
                        $currentBlock.data.severity = 'medium'
                    }
                    $spec.mustCatch += [pscustomobject]$currentBlock.data
                }
                'must_not_flag' {
                    if ([string]::IsNullOrWhiteSpace($currentBlock.data.description)) {
                        throw "must_not_flag block requires description"
                    }
                    $spec.mustNotFlag += [pscustomobject]$currentBlock.data
                }
            }

            $lineIndex++
            continue
        }

        if ($line -match '^config\s*\{$') {
            $currentContext = if ($blockStack.Count -gt 0) { $blockStack[$blockStack.Count - 1] } else { $null }
            if ($null -eq $currentContext -or $currentContext.name -ne 'test_case') {
                throw "config block must be nested inside test_case"
            }
            $configBlock = Get-ConfigBlockBody -Lines $lines -StartLineIndex $lineIndex
            $spec.config = $configBlock.body
            $lineIndex = $configBlock.endLineIndex + 1
            continue
        }

        if ($line -match '^rules\s*\{$') {
            $currentContext = if ($blockStack.Count -gt 0) { $blockStack[$blockStack.Count - 1] } else { $null }
            if ($null -eq $currentContext -or $currentContext.name -ne 'test') {
                throw "rules block must be a direct child of AccTest"
            }
            [void]$blockStack.Add([pscustomobject]@{ name = 'rules'; label = $spec.runName; data = $null })
            $lineIndex++
            continue
        }

        if ($line -match '^(test_case|must_catch|must_not_flag)\s*\{$') {
            $blockName = $Matches[1]
            $blockData = if ($blockName -in @('must_catch', 'must_not_flag')) { [ordered]@{} } else { $null }
            [void]$blockStack.Add([pscustomobject]@{ name = $blockName; label = $null; data = $blockData })
            $lineIndex++
            continue
        }

        $currentContext = if ($blockStack.Count -gt 0) { $blockStack[$blockStack.Count - 1] } else { $null }
        $contextName = if ($null -eq $currentContext -or $currentContext.name -eq 'test') { 'root' } else { $currentContext.name }
        $contextData = if ($null -eq $currentContext) { $null } else { $currentContext.data }

        $assignment = Get-HclAssignment -Line $line
        if ($assignment.kind -eq 'array-start') {
            if ($assignment.key -ne 'changed_files') {
                throw "only changed_files supports array syntax in regression test specs"
            }
            $currentArray = [pscustomobject]@{
                key = $assignment.key
                contextName = $contextName
                contextData = $contextData
            }
            $currentArrayValues = @()
            $lineIndex++
            continue
        }

        Set-RegressionTestValue -Spec $spec -ContextName $contextName -ContextData $contextData -Assignment $assignment
        $lineIndex++
    }

    if (-not $seenRoot) {
        throw "regression test spec did not define a test block"
    }

    if ([string]::IsNullOrWhiteSpace($spec.id) -or [string]::IsNullOrWhiteSpace($spec.title) -or [string]::IsNullOrWhiteSpace($spec.task) -or [string]::IsNullOrWhiteSpace($spec.description)) {
        throw "regression test spec is missing one of the required properties: id, title, task, description"
    }

    if ($spec.changedFiles.Count -eq 0) {
        throw "regression test spec must define at least one changed_files entry"
    }

    if ([string]::IsNullOrWhiteSpace($spec.task)) {
        throw "regression test spec must define task inside test_case"
    }

    if ([string]::IsNullOrWhiteSpace($spec.config)) {
        throw "regression test spec must define config inside test_case"
    }

    return [pscustomobject]$spec
}

function Expand-ListParameter {
    param([string[]] $Value)

    $expanded = @()
    foreach ($entry in $Value) {
        if ([string]::IsNullOrWhiteSpace($entry)) {
            continue
        }

        $expanded += @($entry -split "," | ForEach-Object { $_.Trim() } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    }

    return @($expanded | Select-Object -Unique)
}

function Initialize-Directory {
    param([string] $Path)

    if (-not (Test-Path -LiteralPath $Path)) {
        New-Item -ItemType Directory -Path $Path -Force | Out-Null
    }
}

function Convert-ToKebabCase {
    param([string] $Value)

    $normalized = $Value.ToLowerInvariant()
    $normalized = [Regex]::Replace($normalized, "[^a-z0-9]+", "-")
    return $normalized.Trim('-')
}

function Read-RequiredValue {
    param(
        [string] $Prompt,
        [string] $CurrentValue
    )

    if (-not [string]::IsNullOrWhiteSpace($CurrentValue)) {
        return $CurrentValue.Trim()
    }

    while ($true) {
        $value = Read-Host $Prompt
        if (-not [string]::IsNullOrWhiteSpace($value)) {
            return $value.Trim()
        }
    }
}

function Read-TaskValue {
    param([string] $CurrentValue)

    if (-not [string]::IsNullOrWhiteSpace($CurrentValue)) {
        return $CurrentValue
    }

    $allowedTasks = @(
        "code-review-local-changes",
        "code-review-committed-changes",
        "code-review-docs",
        "docs-writer",
        "resource-implementation",
        "acceptance-testing"
    )

    Write-Output "Select task:"
    for ($i = 0; $i -lt $allowedTasks.Count; $i++) {
        Write-Output "  $($i + 1). $($allowedTasks[$i])"
    }

    while ($true) {
        $selection = Read-Host "Task number"
        $index = 0
        if ([int]::TryParse($selection, [ref]$index) -and $index -ge 1 -and $index -le $allowedTasks.Count) {
            return $allowedTasks[$index - 1]
        }
    }
}

function Read-ListValue {
    param(
        [string] $Prompt,
        [string[]] $CurrentValue
    )

    $expanded = Expand-ListParameter -Value $CurrentValue
    if ($expanded.Count -gt 0) {
        return $expanded
    }

    while ($true) {
        $value = Read-Host $Prompt
        $expanded = Expand-ListParameter -Value @($value)
        if ($expanded.Count -gt 0) {
            return $expanded
        }
    }
}

function Read-OptionalValue {
    param(
        [string] $Prompt,
        [string] $CurrentValue
    )

    if (-not [string]::IsNullOrWhiteSpace($CurrentValue)) {
        return $CurrentValue.Trim()
    }

    return (Read-Host $Prompt).Trim()
}

function Read-YesNoValue {
    param(
        [string] $Prompt,
        [bool] $DefaultValue
    )

    $defaultLabel = if ($DefaultValue) { "Y/n" } else { "y/N" }
    $response = Read-Host "$Prompt [$defaultLabel]"
    if ([string]::IsNullOrWhiteSpace($response)) {
        return $DefaultValue
    }

    return @("y", "yes") -contains $response.Trim().ToLowerInvariant()
}

function Read-MustCatchItems {
    param([string[]] $Descriptions)

    $providedDescriptions = Expand-ListParameter -Value $Descriptions
    if ($providedDescriptions.Count -gt 0) {
        $items = @()
        foreach ($description in $providedDescriptions) {
            $key = Convert-ToKebabCase -Value $description
            if ([string]::IsNullOrWhiteSpace($key)) {
                $key = "must-catch-$($items.Count + 1)"
            }

            $items += [pscustomobject]@{
                key = $key
                severity = "medium"
                description = $description
            }
        }

        return $items
    }

    Write-Output "Enter must-catch findings. Leave the description empty when finished."

    $items = @()
    while ($true) {
        $description = Read-Host "Must-catch description"
        if ([string]::IsNullOrWhiteSpace($description)) {
            break
        }

        $severity = Read-Host "Severity [medium]"
        if ([string]::IsNullOrWhiteSpace($severity)) {
            $severity = "medium"
        }

        $file = Read-Host "Related file (optional)"
        $key = Convert-ToKebabCase -Value $description
        if ([string]::IsNullOrWhiteSpace($key)) {
            $key = "must-catch-$($items.Count + 1)"
        }

        $item = [ordered]@{
            key = $key
            severity = $severity
            description = $description.Trim()
        }
        if (-not [string]::IsNullOrWhiteSpace($file)) {
            $item.file = $file.Trim()
        }

        $items += [pscustomobject]$item
    }

    if ($items.Count -eq 0) {
        $items += [pscustomobject]@{
            key = "replace-me-must-catch"
            severity = "medium"
            description = "Replace this placeholder with the primary behavior or issue the harness should catch."
        }
    }

    return $items
}

function Read-MustNotFlagItems {
    param([string[]] $Descriptions)

    $providedDescriptions = Expand-ListParameter -Value $Descriptions
    if ($providedDescriptions.Count -gt 0) {
        $items = @()
        foreach ($description in $providedDescriptions) {
            $key = Convert-ToKebabCase -Value $description
            if ([string]::IsNullOrWhiteSpace($key)) {
                $key = "must-not-flag-$($items.Count + 1)"
            }

            $items += [pscustomobject]@{
                key = $key
                description = $description
            }
        }

        return $items
    }

    Write-Output "Enter must-not-flag findings. Leave the description empty when finished."

    $items = @()
    while ($true) {
        $description = Read-Host "Must-not-flag description"
        if ([string]::IsNullOrWhiteSpace($description)) {
            break
        }

        $key = Convert-ToKebabCase -Value $description
        if ([string]::IsNullOrWhiteSpace($key)) {
            $key = "must-not-flag-$($items.Count + 1)"
        }

        $items += [pscustomobject]@{
            key = $key
            description = $description.Trim()
        }
    }

    return $items
}

function Get-TaskProfile {
    param([string] $Task)

    $profiles = @{
        "code-review-local-changes" = [ordered]@{
            expectedRules = @("REVIEW-SCOPE-005", "REVIEW-LINT-*")
            expectedTools = [ordered]@{ azurermLinter = "run" }
            outputChecks = [ordered]@{ mustHaveSections = @("CHANGE SUMMARY", "FILES CHANGED", "AZURERM LINTER", "ISSUES") }
            includeSampleOutput = $true
        }
        "code-review-committed-changes" = [ordered]@{
            expectedRules = @("REVIEW-LINT-*", "REVIEW-SCOPE-005")
            expectedTools = [ordered]@{ azurermLinter = "run" }
            outputChecks = [ordered]@{ mustHaveSections = @("CHANGE SUMMARY", "FILES CHANGED", "AZURERM LINTER", "MUST FIX") }
            includeSampleOutput = $true
        }
        "code-review-docs" = [ordered]@{
            expectedRules = @("DOCS-ARG-*", "DOCS-NOTE-*", "DOCS-WORD-*")
            expectedTools = [ordered]@{}
            outputChecks = [ordered]@{ mustHaveSections = @("CHANGE SUMMARY", "DETAILED TECHNICAL REVIEW", "ISSUES") }
            includeSampleOutput = $true
        }
        "docs-writer" = [ordered]@{
            expectedRules = @("DOCS-ARG-*", "DOCS-WORD-*", "DOCS-EVID-001")
            expectedTools = [ordered]@{}
            outputChecks = [ordered]@{ mustIncludeMarkers = @("Preflight complete: yes", "Skill used: docs-writer") }
            includeSampleOutput = $false
        }
        "resource-implementation" = [ordered]@{
            expectedRules = @("IMPL-SCHEMA-*", "IMPL-ERR-*")
            expectedTools = [ordered]@{}
            outputChecks = [ordered]@{ mustIncludeMarkers = @("Skill used: resource-implementation") }
            includeSampleOutput = $false
        }
        "acceptance-testing" = [ordered]@{
            expectedRules = @("TEST-PATTERN-*", "TEST-WF-*", "TEST-RUN-*")
            expectedTools = [ordered]@{}
            outputChecks = [ordered]@{ mustIncludeMarkers = @("Skill used: acceptance-testing") }
            includeSampleOutput = $false
        }
    }

    return $profiles[$Task]
}

function Assert-CanWriteFile {
    param(
        [string] $Path,
        [switch] $Force
    )

    if ((Test-Path -LiteralPath $Path) -and -not $Force) {
        throw "target already exists: $Path"
    }
}

function Get-NormalizedMustCatchItems {
    param($Items)

    $normalized = @()
    foreach ($item in @($Items)) {
        $key = if ($item.PSObject.Properties.Name -contains 'key' -and -not [string]::IsNullOrWhiteSpace($item.key)) {
            $item.key
        }
        else {
            Convert-ToKebabCase -Value $item.description
        }

        if ([string]::IsNullOrWhiteSpace($key)) {
            $key = "must-catch-$($normalized.Count + 1)"
        }

        $entry = [ordered]@{
            key = $key
            severity = if ($item.PSObject.Properties.Name -contains 'severity' -and -not [string]::IsNullOrWhiteSpace($item.severity)) { $item.severity } else { 'medium' }
            description = $item.description
        }
        if ($item.PSObject.Properties.Name -contains 'file' -and -not [string]::IsNullOrWhiteSpace($item.file)) {
            $entry.file = $item.file
        }

        $normalized += [pscustomobject]$entry
    }

    return $normalized
}

function Get-NormalizedMustNotFlagItems {
    param($Items)

    $normalized = @()
    foreach ($item in @($Items)) {
        $key = if ($item.PSObject.Properties.Name -contains 'key' -and -not [string]::IsNullOrWhiteSpace($item.key)) {
            $item.key
        }
        else {
            Convert-ToKebabCase -Value $item.description
        }

        if ([string]::IsNullOrWhiteSpace($key)) {
            $key = "must-not-flag-$($normalized.Count + 1)"
        }

        $normalized += [pscustomobject]@{
            key = $key
            description = $item.description
        }
    }

    return $normalized
}

$parsedSpec = $null
if (-not [string]::IsNullOrWhiteSpace($SpecPath)) {
    $parsedSpec = Get-RegressionTestSpec -Path $SpecPath

    if ([string]::IsNullOrWhiteSpace($Id)) { $Id = $parsedSpec.id }
    if ([string]::IsNullOrWhiteSpace($Title)) { $Title = $parsedSpec.title }
    if ([string]::IsNullOrWhiteSpace($Task)) { $Task = $parsedSpec.task }
    if ([string]::IsNullOrWhiteSpace($Description)) { $Description = $parsedSpec.description }
    if ($ChangedFiles.Count -eq 0) { $ChangedFiles = @($parsedSpec.changedFiles) }
    if ([string]::IsNullOrWhiteSpace($ScopeNotes)) { $ScopeNotes = $parsedSpec.scopeNotes }
    if ([string]::IsNullOrWhiteSpace($CaseNotes)) { $CaseNotes = $parsedSpec.caseNotes }
    if (-not $PSBoundParameters.ContainsKey('SourceKind')) { $SourceKind = $parsedSpec.sourceKind }
    if (-not $PSBoundParameters.ContainsKey('CaseStatus')) { $CaseStatus = $parsedSpec.caseStatus }
    if (-not $PSBoundParameters.ContainsKey('IncludeSampleOutput') -and $parsedSpec.includeSampleOutput) { $IncludeSampleOutput = $true }
}

$Task = if ($null -ne $parsedSpec) {
    if ([string]::IsNullOrWhiteSpace($Task)) { throw "spec did not provide task" }
    $Task
}
else {
    Read-TaskValue -CurrentValue $Task
}
$profile = Get-TaskProfile -Task $Task

$Id = if ($null -ne $parsedSpec) {
    if ([string]::IsNullOrWhiteSpace($Id)) { throw "spec did not provide id" }
    $Id
}
else {
    Read-RequiredValue -Prompt "Case ID (kebab-case)" -CurrentValue $Id
}
$Id = Convert-ToKebabCase -Value $Id
$Title = if ($null -ne $parsedSpec) {
    if ([string]::IsNullOrWhiteSpace($Title)) { throw "spec did not provide title" }
    $Title.Trim()
}
else {
    Read-RequiredValue -Prompt "Short title" -CurrentValue $Title
}
$Description = if ($null -ne $parsedSpec) {
    if ([string]::IsNullOrWhiteSpace($Description)) { throw "spec did not provide description" }
    $Description.Trim()
}
else {
    Read-RequiredValue -Prompt "Plain-language scenario description" -CurrentValue $Description
}
$ChangedFiles = if ($null -ne $parsedSpec) {
    $expandedChangedFiles = Expand-ListParameter -Value $ChangedFiles
    if ($expandedChangedFiles.Count -eq 0) { throw "spec did not provide changed_files" }
    $expandedChangedFiles
}
else {
    Read-ListValue -Prompt "Changed file paths (comma-separated)" -CurrentValue $ChangedFiles
}
$ScopeNotes = if ($null -ne $parsedSpec) { $ScopeNotes } else { Read-OptionalValue -Prompt "Scope notes (optional)" -CurrentValue $ScopeNotes }
$CaseNotes = if ($null -ne $parsedSpec) { $CaseNotes } else { Read-OptionalValue -Prompt "Maintainer notes (optional)" -CurrentValue $CaseNotes }

$includeSampleOutputValue = if ($PSBoundParameters.ContainsKey("IncludeSampleOutput")) {
    [bool]$IncludeSampleOutput
}
elseif ($null -ne $parsedSpec) {
    [bool]$parsedSpec.includeSampleOutput
}
else {
    Read-YesNoValue -Prompt "Create a sample human-readable output placeholder" -DefaultValue ([bool]$profile.includeSampleOutput)
}

$mustCatch = if ($null -ne $parsedSpec) {
    if ($parsedSpec.mustCatch.Count -gt 0) {
        Get-NormalizedMustCatchItems -Items $parsedSpec.mustCatch
    }
    else {
        @([pscustomobject]@{
            key = 'replace-me-must-catch'
            severity = 'medium'
            description = 'Replace this placeholder with the primary behavior or issue the harness should catch.'
        })
    }
}
else {
    Read-MustCatchItems -Descriptions $MustCatchDescription
}
$mustNotFlag = if ($null -ne $parsedSpec) { Get-NormalizedMustNotFlagItems -Items $parsedSpec.mustNotFlag } else { Read-MustNotFlagItems -Descriptions $MustNotFlagDescription }

Initialize-Directory -Path $CasesDirectory
Initialize-Directory -Path $FixturesDirectory
Initialize-Directory -Path $ResultsDirectory

$casePath = Join-Path $CasesDirectory ($Id + ".json")
$fixtureDirectory = Join-Path $FixturesDirectory $Id
$fixturePath = Join-Path $fixtureDirectory "README.md"
$resultPath = Join-Path $ResultsDirectory ($Id + ".result.json")
$reviewPath = Join-Path $ResultsDirectory ($Id + ".review.md")

Assert-CanWriteFile -Path $casePath -Force:$Force
Assert-CanWriteFile -Path $fixturePath -Force:$Force
Assert-CanWriteFile -Path $resultPath -Force:$Force
if ($includeSampleOutputValue) {
    Assert-CanWriteFile -Path $reviewPath -Force:$Force
}

Initialize-Directory -Path $fixtureDirectory

$fixtureRunName = (Get-RegressionTestDefinition).defaultRunName
if ($null -ne $parsedSpec -and -not [string]::IsNullOrWhiteSpace($parsedSpec.runName)) {
    $fixtureRunName = $parsedSpec.runName
}

$fixtureContributorNote = $ScopeNotes
if ([string]::IsNullOrWhiteSpace($fixtureContributorNote)) {
    $fixtureContributorNote = "Replace this note with any context that helps maintainers understand the scenario."
}

$fixtureConfigLines = @()
if ($null -ne $parsedSpec -and -not [string]::IsNullOrWhiteSpace($parsedSpec.config)) {
    $fixtureConfigLines = @(
        "",
        "## Test Configuration",
        "",
        '```hcl',
        $parsedSpec.config,
        '```'
    )
}

$fixtureLines = @(
    "# Sanitized Fixture: $Title",
    "",
    "This fixture was scaffolded from the contributor-facing regression test command.",
    "",
    "## Named Run",
    "",
    ('`run "{0}"`' -f $fixtureRunName),
    "",
    "## Scenario",
    "",
    $Description,
    "",
    "## Modeled Changed Files",
    ""
)

foreach ($changedFile in $ChangedFiles) {
    $fixtureLines += ('- `{0}`' -f $changedFile)
}

$fixtureLines += $fixtureConfigLines

$fixtureLines += @(
    "",
    "## Contributor Notes",
    "",
    $fixtureContributorNote,
    "",
    "## Expected Must-Catch Outcomes",
    ""
)

foreach ($item in $mustCatch) {
    $fixtureLines += ('- `{0}`' -f $item.key)
}

$fixtureLines += @(
    "",
    "## Expected Must-Not-Flag Outcomes",
    ""
)

if ($mustNotFlag.Count -eq 0) {
    $fixtureLines += "- None recorded yet"
}
else {
    foreach ($item in $mustNotFlag) {
        $fixtureLines += ('- `{0}`' -f $item.key)
    }
}

$fixtureLines | Set-Content -LiteralPath $fixturePath

$case = [ordered]@{
    id = $Id
    title = $Title
    task = $Task
    caseStatus = $CaseStatus
    sourceKind = $SourceKind
    sanitized = $true
    description = $Description
    fixture = [ordered]@{
        mode = "files"
        path = "tools/regression/fixtures/$Id/README.md"
    }
    scope = [ordered]@{
        changedFiles = @($ChangedFiles)
        notes = $ScopeNotes
    }
    expectedRules = @($profile.expectedRules)
    mustCatch = @($mustCatch)
    mustNotFlag = @($mustNotFlag)
    expectedTools = $profile.expectedTools
    outputChecks = $profile.outputChecks
    notes = if ([string]::IsNullOrWhiteSpace($CaseNotes)) { "Scaffolded from the contributor-facing regression test command." } else { $CaseNotes }
}

$case | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $casePath

& pwsh -NoProfile -File (Join-Path $PSScriptRoot "new-regression-result-template.ps1") -CasePath $casePath -OutputPath $resultPath | Out-Null

if ($includeSampleOutputValue) {
    $reviewLines = @(
        "# Sample Output Placeholder: $Title",
        "",
        "Case ID: $Id",
        "Task: $Task",
        "",
        "Replace this file with a captured human-readable sample output before promotion."
    )
    $reviewLines | Set-Content -LiteralPath $reviewPath
}

& pwsh -NoProfile -File (Join-Path $PSScriptRoot "validate-regression-artifacts.ps1") -CasePath $casePath -ResultPath $resultPath | Out-Null

Write-Output "Regression test scaffold created"
Write-Output "  Case File        : $casePath"
Write-Output "  Fixture File     : $fixturePath"
Write-Output "  Result Draft     : $resultPath"
if ($includeSampleOutputValue) {
    Write-Output "  Output Draft     : $reviewPath"
}
Write-Output ""
Write-Output "Next maintainer step:"
Write-Output "  Review the scaffold, refine the draft files, and promote them with publish-regression-test.ps1 when ready."
