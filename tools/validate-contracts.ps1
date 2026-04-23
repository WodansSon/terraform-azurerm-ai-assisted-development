[CmdletBinding()]
param(
    [string]$RootPath = (Join-Path $PSScriptRoot '..'),

    [ValidateSet('Text', 'Json')]
    [string]$OutputFormat = 'Text'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$allowedProvenanceLabels = @(
    'Published upstream standard',
    'Inferred maintainer convention',
    'Local safeguard'
)

$requiredContractHeadings = @(
    '## Canonical sources of truth (precedence)',
    'Conflict resolution:',
    '## Rule IDs',
    '## Evidence hierarchy'
)

function Get-NormalizedRelativePath {
    param(
        [Parameter(Mandatory = $true)]
        [string]$BasePath,

        [Parameter(Mandatory = $true)]
        [string]$TargetPath
    )

    $baseFullPath = [System.IO.Path]::GetFullPath($BasePath)
    $targetFullPath = [System.IO.Path]::GetFullPath($TargetPath)
    $relativePath = [System.IO.Path]::GetRelativePath($baseFullPath, $targetFullPath)

    return $relativePath.Replace('\', '/')
}

function Get-HeadingLineIndexes {
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string[]]$Lines,

        [Parameter(Mandatory = $true)]
        [string]$Pattern
    )

    $indexes = @()

    for ($i = 0; $i -lt $Lines.Count; $i++) {
        if ($Lines[$i] -match $Pattern) {
            $indexes += $i
        }
    }

    return $indexes
}

function Get-SectionLines {
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string[]]$Lines,

        [Parameter(Mandatory = $true)]
        [string]$HeadingText
    )

    $headingIndex = -1

    for ($i = 0; $i -lt $Lines.Count; $i++) {
        if ($Lines[$i].Trim() -eq $HeadingText) {
            $headingIndex = $i
            break
        }
    }

    if ($headingIndex -lt 0) {
        return @()
    }

    $sectionLines = @()

    for ($i = $headingIndex + 1; $i -lt $Lines.Count; $i++) {
        if ($HeadingText -eq '## Canonical sources of truth (precedence)' -and $Lines[$i].Trim() -eq 'Conflict resolution:') {
            break
        }

        if ($Lines[$i] -match '^##\s+') {
            break
        }

        $sectionLines += $Lines[$i]
    }

    return $sectionLines
}

function Get-ContractConsumers {
    param(
        [Parameter(Mandatory = $true)]
        [string]$RepoRoot,

        [Parameter(Mandatory = $true)]
        [string]$RelativeContractPath
    )

    $searchRoots = @(
        (Join-Path $RepoRoot '.github/prompts'),
        (Join-Path $RepoRoot '.github/skills'),
        (Join-Path $RepoRoot '.github/instructions')
    )

    $consumers = New-Object 'System.Collections.Generic.HashSet[string]'

    foreach ($searchRoot in $searchRoots) {
        if (-not (Test-Path -LiteralPath $searchRoot)) {
            continue
        }

        $files = Get-ChildItem -LiteralPath $searchRoot -Recurse -File

        foreach ($file in $files) {
            $fileRelativePath = Get-NormalizedRelativePath -BasePath $RepoRoot -TargetPath $file.FullName
            if ($fileRelativePath -eq $RelativeContractPath) {
                continue
            }

            $rawContent = Get-Content -LiteralPath $file.FullName -Raw

            if ($rawContent.Contains($RelativeContractPath)) {
                [void]$consumers.Add($fileRelativePath)
            }
        }
    }

    return @($consumers | Sort-Object)
}

function Get-DeclaredConsumers {
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string[]]$Lines
    )

    $consumerSection = Get-SectionLines -Lines $Lines -HeadingText '## Consumers'
    $declaredConsumers = New-Object 'System.Collections.Generic.List[object]'
    $invalidConsumerLines = New-Object 'System.Collections.Generic.List[string]'
    $currentConsumer = $null

    foreach ($line in $consumerSection) {
        $trimmedLine = $line.Trim()

        if ($trimmedLine -match '^- Consumer:\s+`?(\.github\/[A-Za-z0-9_./-]+)`?$') {
            if ($null -ne $currentConsumer) {
                $declaredConsumers.Add([PSCustomObject]$currentConsumer)
            }

            $currentConsumer = [ordered]@{
                path = $Matches[1]
                role = $null
                command = $null
                requiresEofLoad = $false
            }
        }
        elseif ($null -ne $currentConsumer -and $line -match '^\s+-\s+Role:\s+(.+)$') {
            $currentConsumer.role = $Matches[1].Trim()
        }
        elseif ($null -ne $currentConsumer -and $line -match '^\s+-\s+Command:\s+(.+)$') {
            $currentConsumer.command = $Matches[1].Trim()
        }
        elseif ($null -ne $currentConsumer -and $line -match '^\s+-\s+Requires EOF Load:\s+(yes|no)$') {
            $currentConsumer.requiresEofLoad = ($Matches[1] -eq 'yes')
        }
        elseif ($line -match '^- ' -and $trimmedLine -notmatch '^- Role:' -and $trimmedLine -notmatch '^- Goal:' -and $trimmedLine -notmatch '^- Command:' -and $trimmedLine -ne '') {
            $invalidConsumerLines.Add($trimmedLine)
        }
    }

    if ($null -ne $currentConsumer) {
        $declaredConsumers.Add([PSCustomObject]$currentConsumer)
    }

    return [PSCustomObject]@{
        consumers = @($declaredConsumers | Sort-Object path)
        invalidLines = @($invalidConsumerLines)
    }
}

function Get-CompanionInstructionPaths {
    param(
        [Parameter(Mandatory = $true)]
        [string]$RelativeContractPath,

        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string[]]$CanonicalSourceSection,

        [Parameter()]
        [AllowEmptyString()]
        [string[]]$DetailedCompanionSection = @()
    )

    $companionPaths = New-Object 'System.Collections.Generic.HashSet[string]'

    $sourceLines = @($CanonicalSourceSection) + @($DetailedCompanionSection)

    foreach ($line in $sourceLines) {
        if ($line -match '^\-\s+.*(`)?(\.github\/instructions\/[A-Za-z0-9_./-]+\.instructions\.md)(`)?') {
            $candidatePath = $Matches[2]

            if ($candidatePath -ne $RelativeContractPath -and $candidatePath -notmatch '\/.*-contract\.instructions\.md$') {
                [void]$companionPaths.Add($candidatePath)
            }
        }
    }

    return @($companionPaths | Sort-Object)
}

function Get-LastNonEmptyLine {
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string[]]$Lines
    )

    for ($i = $Lines.Count - 1; $i -ge 0; $i--) {
        if ($Lines[$i].Trim() -ne '') {
            return $Lines[$i].TrimEnd()
        }
    }

    return $null
}

function Get-ContractReport {
    param(
        [Parameter(Mandatory = $true)]
        [string]$RepoRoot,

        [Parameter(Mandatory = $true)]
        [System.IO.FileInfo]$ContractFile
    )

    $lines = Get-Content -LiteralPath $ContractFile.FullName
    $relativePath = Get-NormalizedRelativePath -BasePath $RepoRoot -TargetPath $ContractFile.FullName
    $titleLine = ($lines | Where-Object { $_ -match '^#\s+' } | Select-Object -First 1)
    $canonicalSourceSection = Get-SectionLines -Lines $lines -HeadingText '## Canonical sources of truth (precedence)'
    $detailedCompanionSection = Get-SectionLines -Lines $lines -HeadingText '## Detailed companion guidance'
    $ruleHeadingIndexes = Get-HeadingLineIndexes -Lines $lines -Pattern '^###\s+'
    $declaredConsumerInfo = Get-DeclaredConsumers -Lines $lines
    $declaredConsumers = @($declaredConsumerInfo.consumers)
    $lastNonEmptyLine = Get-LastNonEmptyLine -Lines $lines

    $errors = New-Object 'System.Collections.Generic.List[string]'
    $warnings = New-Object 'System.Collections.Generic.List[string]'

    foreach ($heading in $requiredContractHeadings) {
        if (-not ($lines -contains $heading)) {
            $errors.Add("Missing required contract heading: $heading")
        }
    }

    if (-not $titleLine) {
        $errors.Add('Missing top-level contract heading')
    }

    if (-not ($lines -contains '## Consumers')) {
        $errors.Add('Missing required contract heading: ## Consumers')
    }

    if ($declaredConsumers.Count -eq 0) {
        $errors.Add('Consumers section does not declare any Consumer lines with .github paths')
    }

    foreach ($invalidConsumerLine in $declaredConsumerInfo.invalidLines) {
        $errors.Add("Consumers section contains a non-standard bullet. Use '- Consumer: <path>' entries: $invalidConsumerLine")
    }

    if (-not $lastNonEmptyLine) {
        $errors.Add('Contract file is empty')
    }
    elseif ($lastNonEmptyLine -notmatch '^<!-- [A-Z0-9-]+-CONTRACT-EOF -->$') {
        $errors.Add('Last non-empty line must be a contract EOF marker comment such as <!-- DOCS-CONTRACT-EOF -->')
    }

    $canonicalSources = @()
    foreach ($line in $canonicalSourceSection) {
        if ($line -match '^\-\s+') {
            $canonicalSources += $line.Substring(2).Trim()
        }
    }

    if ($canonicalSources.Count -eq 0) {
        $warnings.Add('Canonical sources section does not contain any top-level source entries')
    }

    $companionInstructionPaths = @(Get-CompanionInstructionPaths -RelativeContractPath $relativePath -CanonicalSourceSection $canonicalSourceSection -DetailedCompanionSection $detailedCompanionSection)

    $provenanceRuleCount = 0
    $rulesWithEvidenceCount = 0

    foreach ($ruleIndex in $ruleHeadingIndexes) {
        $ruleHeading = $lines[$ruleIndex]
        $ruleId = $ruleHeading -replace '^###\s+', ''
        $ruleLines = @()

        for ($i = $ruleIndex + 1; $i -lt $lines.Count; $i++) {
            if ($lines[$i] -match '^###\s+' -or $lines[$i] -match '^##\s+') {
                break
            }

            $ruleLines += $lines[$i]
        }

        $provenanceLineIndex = -1
        $evidenceLineIndex = -1
        $provenanceValue = $null

        for ($i = 0; $i -lt $ruleLines.Count; $i++) {
            if ($ruleLines[$i] -match '^- \*\*Provenance\*\*:\s*(.+)$') {
                $provenanceLineIndex = $i
                $provenanceValue = $Matches[1].Trim().TrimEnd('.')
            }

            if ($ruleLines[$i] -match '^- \*\*Evidence\*\*:\s*$') {
                $evidenceLineIndex = $i
            }
        }

        if ($evidenceLineIndex -ge 0 -and $provenanceLineIndex -lt 0) {
            $errors.Add("$ruleId has evidence but no provenance label")
        }

        if ($provenanceLineIndex -ge 0) {
            $provenanceRuleCount++

            if ($allowedProvenanceLabels -notcontains $provenanceValue) {
                $errors.Add("$ruleId uses unsupported provenance label: $provenanceValue")
            }

            if ($evidenceLineIndex -lt 0) {
                $errors.Add("$ruleId has provenance but no evidence block")
            }
            elseif ($evidenceLineIndex -lt $provenanceLineIndex) {
                $errors.Add("$ruleId places evidence before provenance")
            }
            else {
                $rulesWithEvidenceCount++

                $hasEvidenceItems = $false
                for ($i = $evidenceLineIndex + 1; $i -lt $ruleLines.Count; $i++) {
                    $trimmedLine = $ruleLines[$i].TrimEnd()

                    if ($trimmedLine -eq '') {
                        continue
                    }

                    if ($trimmedLine -match '^- \*\*') {
                        break
                    }

                    if ($trimmedLine -match '^  -\s+' -or $trimmedLine -match '^\s{2,}-\s+') {
                        $hasEvidenceItems = $true
                        break
                    }

                    if ($trimmedLine -match '^###\s+' -or $trimmedLine -match '^##\s+') {
                        break
                    }
                }

                if (-not $hasEvidenceItems) {
                    $errors.Add("$ruleId has an evidence heading but no evidence bullet items")
                }
            }
        }
    }

    $consumers = Get-ContractConsumers -RepoRoot $RepoRoot -RelativeContractPath $relativePath

    $declaredConsumerPaths = @($declaredConsumers | ForEach-Object { $_.path })
    $eofLoadConsumerCount = @($declaredConsumers | Where-Object { $_.requiresEofLoad }).Count

    foreach ($declaredConsumer in $declaredConsumers) {
        $declaredConsumerPath = $declaredConsumer.path
        $declaredConsumerFullPath = Join-Path $RepoRoot ($declaredConsumerPath.Replace('/', '\'))

        if (-not (Test-Path -LiteralPath $declaredConsumerFullPath)) {
            $errors.Add("Declared consumer path does not exist: $declaredConsumerPath")
        }
        elseif ($consumers -notcontains $declaredConsumerPath) {
            $errors.Add("Declared consumer is not discoverable by repository reference scan: $declaredConsumerPath")
        }
        else {
            $consumerRawContent = Get-Content -LiteralPath $declaredConsumerFullPath -Raw

            if (-not $consumerRawContent.Contains($relativePath)) {
                $errors.Add("Declared consumer does not reference its contract path: $declaredConsumerPath")
            }

            if ($declaredConsumer.requiresEofLoad -and $consumerRawContent -notmatch 'to EOF') {
                $errors.Add("Declared consumer is marked 'Requires EOF Load: yes' but does not mention loading the contract to EOF: $declaredConsumerPath")
            }
        }
    }

    foreach ($companionInstructionPath in $companionInstructionPaths) {
        $companionInstructionFullPath = Join-Path $RepoRoot ($companionInstructionPath.Replace('/', '\'))

        if (-not (Test-Path -LiteralPath $companionInstructionFullPath)) {
            $errors.Add("Companion instruction path does not exist: $companionInstructionPath")
            continue
        }

        $companionRawContent = Get-Content -LiteralPath $companionInstructionFullPath -Raw

        if (-not $companionRawContent.Contains($relativePath)) {
            $errors.Add("Companion instruction does not point back to its contract: $companionInstructionPath")
        }
    }

    return [PSCustomObject]@{
        path = $relativePath
        title = if ($titleLine) { $titleLine -replace '^#\s+', '' } else { $null }
        canonicalSources = $canonicalSources
        companionInstructionCount = $companionInstructionPaths.Count
        companionInstructions = $companionInstructionPaths
        declaredConsumerCount = $declaredConsumers.Count
        declaredConsumers = $declaredConsumerPaths
        eofLoadConsumerCount = $eofLoadConsumerCount
        consumerCount = $consumers.Count
        consumers = $consumers
        eofMarker = $lastNonEmptyLine
        ruleCount = $ruleHeadingIndexes.Count
        provenanceRuleCount = $provenanceRuleCount
        rulesWithEvidenceCount = $rulesWithEvidenceCount
        errors = @($errors)
        warnings = @($warnings)
    }
}

function Write-TextReport {
    param(
        [Parameter(Mandatory = $true)]
        [string]$RepoRoot,

        [Parameter(Mandatory = $true)]
        [object[]]$Reports
    )

    Write-Host 'Contract Validation Report'
    Write-Host "Repository: $RepoRoot"
    Write-Host "Contracts Found: $($Reports.Count)"
    Write-Host ''

    foreach ($report in $Reports) {
        $status = if ($report.errors.Count -eq 0) { 'PASS' } else { 'FAIL' }
        Write-Host "[$status] $($report.path)"
        Write-Host "  Title: $($report.title)"
        Write-Host "  Rules: $($report.ruleCount)"
        Write-Host "  Provenance Rules: $($report.provenanceRuleCount)"
        Write-Host "  Companion Instructions: $($report.companionInstructionCount)"
        Write-Host "  Declared Consumers: $($report.declaredConsumerCount)"
        Write-Host "  EOF-Load Consumers: $($report.eofLoadConsumerCount)"
        Write-Host "  Consumers: $($report.consumerCount)"
        Write-Host "  Canonical Sources: $($report.canonicalSources.Count)"
        Write-Host "  EOF Marker: $($report.eofMarker)"

        if ($report.companionInstructions.Count -gt 0) {
            foreach ($companionInstruction in $report.companionInstructions) {
                Write-Host "    companion instruction: $companionInstruction"
            }
        }

        if ($report.declaredConsumers.Count -gt 0) {
            foreach ($declaredConsumer in $report.declaredConsumers) {
                Write-Host "    declared consumer: $declaredConsumer"
            }
        }

        if ($report.canonicalSources.Count -gt 0) {
            foreach ($source in $report.canonicalSources) {
                Write-Host "    - $source"
            }
        }

        if ($report.consumers.Count -gt 0) {
            foreach ($consumer in $report.consumers) {
                Write-Host "    consumer: $consumer"
            }
        }

        if ($report.warnings.Count -gt 0) {
            foreach ($warning in $report.warnings) {
                Write-Host "  warning: $warning"
            }
        }

        if ($report.errors.Count -gt 0) {
            foreach ($error in $report.errors) {
                Write-Host "  error: $error"
            }
        }

        Write-Host ''
    }
}

$resolvedRootPath = [System.IO.Path]::GetFullPath($RootPath)
$contractFiles = Get-ChildItem -LiteralPath (Join-Path $resolvedRootPath '.github/instructions') -Filter '*-contract.instructions.md' -File | Sort-Object FullName

if ($contractFiles.Count -eq 0) {
    throw 'No contract instruction files were found under .github/instructions'
}

$reports = foreach ($contractFile in $contractFiles) {
    Get-ContractReport -RepoRoot $resolvedRootPath -ContractFile $contractFile
}

if ($OutputFormat -eq 'Json') {
    $reports | ConvertTo-Json -Depth 8
}
else {
    Write-TextReport -RepoRoot $resolvedRootPath -Reports $reports
}

$failureCount = @($reports | Where-Object { $_.errors.Count -gt 0 }).Count

if ($failureCount -gt 0) {
    exit 1
}
