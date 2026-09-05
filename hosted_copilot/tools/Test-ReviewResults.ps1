[CmdletBinding()]
param(
    [string]$ResultsDirectory = (Join-Path $PSScriptRoot '../regression/results'),

    [string]$CasesDirectory = (Join-Path $PSScriptRoot '../regression/cases'),

    [string]$SchemaPath = (Join-Path $PSScriptRoot '../regression/schema/paired-review-result.schema.json'),

    [ValidateSet('Text', 'Json')]
    [string]$OutputFormat = 'Text'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$validationOutputModulePath = Join-Path $PSScriptRoot '../../tools/ValidationOutput.psm1'
Import-Module -Name $validationOutputModulePath -Force

function Get-ProfileSummary {
    param(
        [Parameter(Mandatory = $true)]
        $Profile
    )

    return [ordered]@{
        expectedFound = @($Profile.actualFindings | Where-Object classification -eq 'expected').Count
        missed = @($Profile.missedFindings).Count
        duplicates = @($Profile.actualFindings | Where-Object classification -eq 'duplicate').Count
        unexpectedValid = @($Profile.actualFindings | Where-Object classification -eq 'unexpected-valid').Count
        falsePositives = @($Profile.actualFindings | Where-Object classification -eq 'false-positive').Count
    }
}

function Get-OptionalPropertyValue {
    param(
        [Parameter(Mandatory = $true)]
        $InputObject,

        [Parameter(Mandatory = $true)]
        [string]$Name
    )

    $property = $InputObject.PSObject.Properties[$Name]
    if ($null -eq $property) {
        return $null
    }

    return $property.Value
}

if (-not (Test-Path -LiteralPath $SchemaPath -PathType Leaf)) {
    throw "Paired review result schema was not found: $SchemaPath"
}

$resultPaths = @(if (Test-Path -LiteralPath $ResultsDirectory -PathType Container) {
    @(Get-ChildItem -LiteralPath $ResultsDirectory -Filter '*.json' -File -Recurse | Sort-Object FullName)
}
else {
    @()
})

$issues = New-Object 'System.Collections.Generic.List[string]'
$validatedRuns = New-Object 'System.Collections.Generic.List[string]'
foreach ($resultPath in $resultPaths) {
    try {
        $content = Get-Content -LiteralPath $resultPath.FullName -Raw
        if (-not ($content | Test-Json -SchemaFile $SchemaPath)) {
            throw 'schema validation failed'
        }
        $record = $content | ConvertFrom-Json
        $profiles = @($record.profiles)
        $profileNames = @($profiles.instructionProfile | Sort-Object -Unique)
        $slots = @($profiles.slot | Sort-Object -Unique)
        if (($profileNames -join ',') -ne 'control,hosted' -or ($slots -join ',') -ne 'A,B') {
            throw 'profiles must contain one control, one hosted, and slots A and B'
        }
        if (@($profiles | Where-Object diffHash -ne $record.diffHash).Count -gt 0) {
            throw 'profile diff hashes must match the pair diff hash'
        }

        $casePath = Get-ChildItem -LiteralPath $CasesDirectory -Filter 'case.json' -File -Recurse | Where-Object {
            (Get-Content -LiteralPath $_.FullName -Raw | ConvertFrom-Json).id -eq $record.fixtureId
        }
        if (@($casePath).Count -ne 1) {
            throw "fixtureId must resolve to exactly one case: $($record.fixtureId)"
        }
        $case = Get-Content -LiteralPath $casePath.FullName -Raw | ConvertFrom-Json
        $expectedRuleIds = @($case.expectedFindings.ruleId | Sort-Object -Unique)

        foreach ($profile in $profiles) {
            $runtimeEvidence = Get-OptionalPropertyValue -InputObject $profile -Name 'runtimeEvidence'
            if ($profile.modelEvidenceSource -eq 'product_generated') {
                if ($null -eq $runtimeEvidence) {
                    throw "$($profile.instructionProfile) product-generated model evidence requires runtimeEvidence"
                }
                if ($runtimeEvidence.source -ne 'actions_log') {
                    throw "$($profile.instructionProfile) runtimeEvidence.source must be actions_log"
                }
                if ($runtimeEvidence.captureStatus -ne 'complete') {
                    throw "$($profile.instructionProfile) product-generated model evidence requires complete runtime capture"
                }
                $primarySessions = @($runtimeEvidence.modelSessions | Where-Object role -eq 'primary_review')
                if ($primarySessions.Count -ne 1) {
                    throw "$($profile.instructionProfile) runtimeEvidence must contain exactly one primary_review session"
                }
                if ($primarySessions[0].sessionType -ne 'copilot-sdk' -or $primarySessions[0].clientName -ne 'github/copilot-code-review') {
                    throw "$($profile.instructionProfile) primary_review session identity is invalid"
                }
                if ($primarySessions[0].modelName -ne $profile.modelName -or $primarySessions[0].reasoningLevel -ne $profile.reasoningLevel) {
                    throw "$($profile.instructionProfile) primary_review session does not match profile model evidence"
                }
            }
            elseif ($null -ne $runtimeEvidence -and $runtimeEvidence.captureStatus -eq 'complete') {
                throw "$($profile.instructionProfile) complete runtimeEvidence requires product_generated modelEvidenceSource"
            }

            if ((@($profile.expectedFindings | Sort-Object -Unique) -join ',') -ne ($expectedRuleIds -join ',')) {
                throw "$($profile.instructionProfile) expectedFindings do not match case $($record.fixtureId)"
            }
            $findingIds = @($profile.actualFindings.id)
            if (@($findingIds | Group-Object | Where-Object Count -gt 1).Count -gt 0) {
                throw "$($profile.instructionProfile) actualFindings contain duplicate IDs"
            }

            $classificationLists = @{
                duplicate = @($profile.duplicateFindings)
                'unexpected-valid' = @($profile.unexpectedFindings)
                'false-positive' = @($profile.falsePositiveFindings)
            }
            foreach ($classification in $classificationLists.Keys) {
                $classifiedIds = @($profile.actualFindings | Where-Object classification -eq $classification | ForEach-Object id | Sort-Object)
                $recordedIds = @($classificationLists[$classification] | Sort-Object)
                if (($classifiedIds -join ',') -ne ($recordedIds -join ',')) {
                    throw "$($profile.instructionProfile) $classification finding IDs do not match actualFindings"
                }
            }

            $foundRuleIds = @($profile.actualFindings | Where-Object classification -eq 'expected' | ForEach-Object ruleId | Sort-Object -Unique)
            $computedMisses = @($expectedRuleIds | Where-Object { $_ -notin $foundRuleIds } | Sort-Object)
            if (($computedMisses -join ',') -ne (@($profile.missedFindings | Sort-Object) -join ',')) {
                throw "$($profile.instructionProfile) missedFindings do not match expected finding coverage"
            }

            $summaryName = [string]$profile.instructionProfile
            $computedSummary = Get-ProfileSummary -Profile $profile
            foreach ($property in $computedSummary.Keys) {
                if ([int]$record.summary.$summaryName.$property -ne [int]$computedSummary[$property]) {
                    throw "$summaryName summary.$property does not match actual findings"
                }
            }
        }

        if ($record.adjudication.status -eq 'adjudicated' -and $null -eq $record.adjudication.completedAt) {
            throw 'adjudicated records require adjudication.completedAt'
        }
        $validatedRuns.Add([string]$record.runId)
    }
    catch {
        $issues.Add("$($resultPath.FullName): $($_.Exception.Message)")
    }
}

$result = [ordered]@{
    status = if ($issues.Count -eq 0) { 'passed' } else { 'failed' }
    resultCount = $resultPaths.Count
    validatedRuns = @($validatedRuns.ToArray())
    issueCount = $issues.Count
    issues = @($issues.ToArray())
}

if ($OutputFormat -eq 'Json') {
    $result | ConvertTo-Json -Depth 10
}
else {
    Write-ValidationSectionHeader -Title 'Hosted paired review result validation summary'
    Write-ValidationSummary -Fields ([ordered]@{
        Status = $result.status.ToUpperInvariant()
        'Result Count' = $result.resultCount
        'Issue Count' = $result.issueCount
    })
    if ($result.issues.Count -gt 0) {
        Write-ValidationSectionHeader -Title 'Issues'
    }
    foreach ($issue in $result.issues) {
        Write-Output "  - $issue"
    }
    Complete-ValidationTextOutput
}

if ($issues.Count -gt 0) {
    exit 1
}
