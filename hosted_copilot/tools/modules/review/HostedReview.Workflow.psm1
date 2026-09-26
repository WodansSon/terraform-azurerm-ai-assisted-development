Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

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

function Get-ProfileSummary {
    param(
        [Parameter(Mandatory = $true)]
        $Findings,

        [Parameter(Mandatory = $true)]
        [string[]]$MissedFindings
    )

    return [ordered]@{
        expectedFound = @($Findings | Where-Object classification -eq 'expected').Count
        missed = $MissedFindings.Count
        duplicates = @($Findings | Where-Object classification -eq 'duplicate').Count
        unexpectedValid = @($Findings | Where-Object classification -eq 'unexpected-valid').Count
        falsePositives = @($Findings | Where-Object classification -eq 'false-positive').Count
    }
}

function ConvertTo-RuntimeEvidence {
    param($Runtime)

    if ($null -eq $Runtime) {
        return $null
    }

    return [ordered]@{
        captureStatus = [string]$Runtime.captureStatus
        diagnostics = @($Runtime.diagnostics)
        actionRunId = Get-OptionalPropertyValue -InputObject $Runtime -Name 'actionRunId'
        actionRunAttempt = Get-OptionalPropertyValue -InputObject $Runtime -Name 'actionRunAttempt'
        actionRunUrl = Get-OptionalPropertyValue -InputObject $Runtime -Name 'actionRunUrl'
        actionLogSha256 = Get-OptionalPropertyValue -InputObject $Runtime -Name 'actionLogSha256'
        parserVersion = [string]$Runtime.parserVersion
        source = if ([string]$Runtime.captureStatus -eq 'complete') { 'actions_log' } else { 'unavailable' }
        configuredPrimaryModel = Get-OptionalPropertyValue -InputObject $Runtime -Name 'configuredPrimaryModel'
        modelSessions = @($Runtime.modelSessions)
        maxPromptTokens = if ($null -eq $Runtime.maxPromptTokens) { $null } else { [int]$Runtime.maxPromptTokens }
        memoryCount = if ($null -eq $Runtime.memoryCount) { $null } else { [int]$Runtime.memoryCount }
        skillCatalogEntries = if ($null -eq $Runtime.skillCatalogEntries) { $null } else { [int]$Runtime.skillCatalogEntries }
        invokedSkills = @($Runtime.invokedSkills)
        configuredAuxiliaryModels = $Runtime.configuredAuxiliaryModels
        deduplication = $Runtime.deduplication
    }
}

function Get-ComparisonStatus {
    param(
        [Parameter(Mandatory = $true)]
        $Profiles
    )

    $productGenerated = @($Profiles | Where-Object modelEvidenceSource -eq 'product_generated')
    if ($productGenerated.Count -ne 2) {
        return [pscustomobject]@{
            status = 'aggregate-only'
            reasons = @('Complete product-generated model evidence was not available for both reviews.')
        }
    }

    $modelKeys = @($Profiles | ForEach-Object { "$($_.modelName)|$($_.reasoningLevel)" } | Sort-Object -Unique)
    if ($modelKeys.Count -ne 1) {
        return [pscustomobject]@{
            status = 'confounded'
            reasons = @('The reviews used different model or reasoning configurations.')
        }
    }

    return [pscustomobject]@{
        status = 'direct'
        reasons = @()
    }
}

function New-HostedReviewResult {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        $Capture,

        [Parameter(Mandatory = $true)]
        $Case,

        [Parameter(Mandatory = $true)]
        [hashtable]$Adjudications,

        [Parameter(Mandatory = $true)]
        [string]$RawCapturePath,

        [Parameter(Mandatory = $true)]
        [string]$CompletedAt
    )

    $expectedRuleIds = @($Case.expectedFindings.ruleId | Sort-Object -Unique)
    $profiles = New-Object 'System.Collections.Generic.List[object]'
    foreach ($capturedProfile in @($Capture.profiles)) {
        $slot = [string]$capturedProfile.slot
        $evidence = $capturedProfile.evidence
        $profileAdjudications = $Adjudications[$slot]
        if ($null -eq $profileAdjudications) {
            throw "Adjudications are missing for slot $slot"
        }

        $findings = New-Object 'System.Collections.Generic.List[object]'
        foreach ($comment in @($evidence.comments)) {
            $decision = $profileAdjudications[[string]$comment.id]
            if ($null -eq $decision) {
                throw "Adjudication is missing for comment $($comment.id) in slot $slot"
            }
            $ruleIds = @($decision.ruleIds | Sort-Object -Unique)
            if ($decision.classification -eq 'expected' -and $ruleIds.Count -eq 0) {
                throw "Expected comment $($comment.id) must reference at least one expected rule"
            }
            if (@($ruleIds | Where-Object { $_ -notin $expectedRuleIds }).Count -gt 0) {
                throw "Comment $($comment.id) references a rule outside the case expectations"
            }

            $findings.Add([ordered]@{
                id = [int64]$comment.id
                url = [string]$comment.url
                path = [string]$comment.path
                line = if ($null -eq $comment.line) { $null } else { [int]$comment.line }
                body = [string]$comment.body
                classification = [string]$decision.classification
                ruleIds = $ruleIds
                duplicateOf = if ($null -eq $decision.duplicateOf) { $null } else { [int64]$decision.duplicateOf }
                adjudicationReason = [string]$decision.reason
            })
        }

        $foundRuleIds = @($findings | Where-Object classification -eq 'expected' | ForEach-Object ruleIds | Sort-Object -Unique)
        $missedRuleIds = @($expectedRuleIds | Where-Object { $_ -notin $foundRuleIds } | Sort-Object)
        $runtime = Get-OptionalPropertyValue -InputObject $evidence -Name 'runtime'
        $runtimeEvidence = ConvertTo-RuntimeEvidence -Runtime $runtime
        $modelEvidenceSource = if ($null -ne $runtimeEvidence -and $runtimeEvidence.captureStatus -eq 'complete') { 'product_generated' } else { 'unavailable' }

        $profile = [ordered]@{
            slot = $slot
            instructionProfile = [string]$evidence.instructionProfile
            instructionProfileCommit = [string]$evidence.pullRequest.baseCommit
            fixtureCommit = [string]$evidence.pullRequest.headCommit
            diffHash = [string]$evidence.diffHash
            reviewEffort = [string]$evidence.review.reviewEffort
            modelName = if ($null -eq $runtime -or [string]::IsNullOrWhiteSpace([string]$runtime.modelName)) { 'unknown' } else { [string]$runtime.modelName }
            reasoningLevel = if ($null -eq $runtime -or [string]::IsNullOrWhiteSpace([string]$runtime.reasoningLevel)) { 'unknown' } else { [string]$runtime.reasoningLevel }
            modelEvidenceSource = $modelEvidenceSource
            hostedReviewRuntimeVersion = if ($null -eq $runtime -or [string]::IsNullOrWhiteSpace([string]$runtime.runtimeVersion)) { 'unknown' } else { [string]$runtime.runtimeVersion }
            requestedAt = [string]$evidence.review.requestedAt
            reviewedAt = [string]$evidence.review.reviewedAt
            pullRequest = [ordered]@{
                number = [int]$evidence.pullRequest.number
                url = [string]$evidence.pullRequest.url
                baseBranch = [string]$evidence.pullRequest.baseBranch
                baseCommit = [string]$evidence.pullRequest.baseCommit
                headBranch = [string]$evidence.pullRequest.headBranch
                headCommit = [string]$evidence.pullRequest.headCommit
                reviewId = [int64]$evidence.review.id
            }
            expectedFindings = $expectedRuleIds
            actualFindings = @($findings.ToArray())
            duplicateFindings = @($findings | Where-Object classification -eq 'duplicate' | ForEach-Object id)
            unexpectedFindings = @($findings | Where-Object classification -eq 'unexpected-valid' | ForEach-Object id)
            falsePositiveFindings = @($findings | Where-Object classification -eq 'false-positive' | ForEach-Object id)
            missedFindings = $missedRuleIds
            comparisonStatus = ''
        }
        if ($null -ne $runtimeEvidence) {
            $profile['runtimeEvidence'] = $runtimeEvidence
        }
        $profiles.Add($profile)
    }

    $comparison = Get-ComparisonStatus -Profiles @($profiles.ToArray())
    foreach ($profile in $profiles) {
        $profile.comparisonStatus = $comparison.status
    }
    $control = @($profiles | Where-Object instructionProfile -eq 'control')
    $hosted = @($profiles | Where-Object instructionProfile -eq 'hosted')
    if ($control.Count -ne 1 -or $hosted.Count -ne 1) {
        throw 'Capture must contain exactly one control and one hosted profile'
    }

    return [ordered]@{
        schemaVersion = 2
        runId = [string]$Capture.runId
        repository = [string]$Capture.repository
        fixtureId = [string]$Capture.fixtureId
        capturedAt = [string]$Capture.capturedAt
        sourceCommit = [string]$Capture.sourceCommit
        manifestHash = [string]$Capture.manifestHash
        adjudication = [ordered]@{
            status = 'adjudicated'
            method = 'blinded-profile-labels'
            completedAt = $CompletedAt
            mappingRevealedAfterAdjudication = $true
        }
        changedFiles = @($Capture.changedFiles)
        diffHashAlgorithm = [string]$Capture.diffHashAlgorithm
        diffHash = [string]$Capture.diffHash
        profiles = @($profiles.ToArray())
        summary = [ordered]@{
            comparisonStatus = $comparison.status
            confoundingReasons = @($comparison.reasons)
            control = Get-ProfileSummary -Findings $control[0].actualFindings -MissedFindings $control[0].missedFindings
            hosted = Get-ProfileSummary -Findings $hosted[0].actualFindings -MissedFindings $hosted[0].missedFindings
        }
        rawCapturePath = $RawCapturePath.Replace('\', '/')
    }
}

Export-ModuleMember -Function New-HostedReviewResult
