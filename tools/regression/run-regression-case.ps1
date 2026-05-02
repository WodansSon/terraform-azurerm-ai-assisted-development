param(
    [string] $Case,

    [string] $CasePath,

    [string] $RunsDirectory = (Join-Path $PSScriptRoot "runs")
)

$ErrorActionPreference = "Stop"

function Get-JsonFile {
    param([string] $Path)

    if (-not (Test-Path -LiteralPath $Path)) {
        throw "file not found: $Path"
    }

    return Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json
}

function Get-RelativeRepoPath {
    param(
        [string] $RepoRoot,
        [string] $Path
    )

    return [System.IO.Path]::GetRelativePath($RepoRoot, $Path)
}

function Get-AvailableCases {
    param([string] $CasesDirectory)

    if (-not (Test-Path -LiteralPath $CasesDirectory)) {
        return @()
    }

    return @(Get-ChildItem -LiteralPath $CasesDirectory -Filter *.json | Sort-Object BaseName)
}

function Show-Usage {
    param(
        [string[]] $AvailableCases
    )

    Write-Output "Usage: pwsh -NoProfile -File ./tools/regression/run-regression-case.ps1 -Case <case-id>"
    Write-Output "   or: pwsh -NoProfile -File ./tools/regression/run-regression-case.ps1 -CasePath <case.json>"
    Write-Output ""
    Write-Output "Available case aliases:"

    foreach ($availableCase in $AvailableCases) {
        Write-Output "  - $availableCase"
    }
}

function Resolve-CaseFile {
    param(
        [string] $Case,
        [string] $CasePath,
        [string] $CasesDirectory,
        [string] $RepoRoot
    )

    $availableCaseFiles = Get-AvailableCases -CasesDirectory $CasesDirectory
    $availableAliases = @($availableCaseFiles | ForEach-Object { $_.BaseName })

    if (([string]::IsNullOrWhiteSpace($Case) -and [string]::IsNullOrWhiteSpace($CasePath)) -or
        (-not [string]::IsNullOrWhiteSpace($Case) -and -not [string]::IsNullOrWhiteSpace($CasePath))) {
        Show-Usage -AvailableCases $availableAliases
        throw "specify exactly one of -Case or -CasePath"
    }

    if (-not [string]::IsNullOrWhiteSpace($CasePath)) {
        return Resolve-Path -LiteralPath $CasePath
    }

    $matches = @($availableCaseFiles | Where-Object { $_.BaseName -eq $Case -or $_.Name -eq $Case })
    if ($matches.Count -eq 0) {
        Show-Usage -AvailableCases $availableAliases
        throw "unknown case alias: $Case"
    }

    if ($matches.Count -gt 1) {
        throw "case alias is ambiguous: $Case"
    }

    return Resolve-Path -LiteralPath $matches[0].FullName
}

function Initialize-Directory {
    param([string] $Path)

    if (-not (Test-Path -LiteralPath $Path)) {
        New-Item -ItemType Directory -Path $Path -Force | Out-Null
    }
}

function Copy-Fixture {
    param(
        [string] $SourcePath,
        [string] $FixtureDirectory
    )

    if (-not (Test-Path -LiteralPath $SourcePath)) {
        throw "fixture source not found: $SourcePath"
    }

    Initialize-Directory -Path $FixtureDirectory

    if ((Get-Item -LiteralPath $SourcePath).PSIsContainer) {
        Copy-Item -LiteralPath $SourcePath -Destination $FixtureDirectory -Recurse -Force
        return Join-Path $FixtureDirectory (Split-Path -Leaf $SourcePath)
    }

    $destinationPath = Join-Path $FixtureDirectory (Split-Path -Leaf $SourcePath)
    Copy-Item -LiteralPath $SourcePath -Destination $destinationPath -Force
    return $destinationPath
}

function Copy-SnapshotFile {
    param(
        [string] $SourcePath,
        [string] $DestinationPath
    )

    $destinationDirectory = Split-Path -Parent $DestinationPath
    Initialize-Directory -Path $destinationDirectory
    Copy-Item -LiteralPath $SourcePath -Destination $DestinationPath -Force
}

function Get-FileSha256 {
    param([string] $Path)

    if (-not (Test-Path -LiteralPath $Path) -or (Get-Item -LiteralPath $Path).PSIsContainer) {
        return $null
    }

    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash
}

function Get-RepositorySnapshot {
    param([string] $RepoRoot)

    $snapshot = [ordered]@{
        headBranch = $null
        headCommit = $null
        worktreeHasChanges = $null
        worktreeHasUntrackedChanges = $null
    }

    if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
        return $snapshot
    }

    try {
        $snapshot.headCommit = (& git -C $RepoRoot rev-parse HEAD).Trim()
    }
    catch {
    }

    try {
        $snapshot.headBranch = (& git -C $RepoRoot rev-parse --abbrev-ref HEAD).Trim()
    }
    catch {
    }

    try {
        $statusLines = @(& git -C $RepoRoot status --porcelain)
        $snapshot.worktreeHasChanges = $statusLines.Count -gt 0
        $snapshot.worktreeHasUntrackedChanges = @($statusLines | Where-Object { $_ -like '??*' }).Count -gt 0
    }
    catch {
    }

    return $snapshot
}

$repoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$casesDirectory = Join-Path $PSScriptRoot "cases"
$resolvedCasePath = Resolve-CaseFile -Case $Case -CasePath $CasePath -CasesDirectory $casesDirectory -RepoRoot $repoRoot
$caseDefinition = Get-JsonFile -Path $resolvedCasePath

$runTimestamp = Get-Date -Format "yyyyMMdd-HHmmss"
$runId = "$runTimestamp-$($caseDefinition.id)"
$runDirectory = Join-Path $RunsDirectory $runId
$inputDirectory = Join-Path $runDirectory "input"
$captureDirectory = Join-Path $runDirectory "capture"
$outputDirectory = Join-Path $runDirectory "output"
$fixtureDirectory = Join-Path $runDirectory "fixture"

Initialize-Directory -Path $runDirectory
Initialize-Directory -Path $inputDirectory
Initialize-Directory -Path $captureDirectory
Initialize-Directory -Path $outputDirectory

$caseSnapshotPath = Join-Path $inputDirectory "case.json"
$weightsSourcePath = Join-Path $PSScriptRoot "config/score-weights.json"
$weightsSnapshotPath = Join-Path $inputDirectory "score-weights.json"
$resultOutputPath = Join-Path $outputDirectory "result.json"
$reviewOutputPath = Join-Path $outputDirectory "review.md"
$executionMetadataPath = Join-Path $captureDirectory "execution-metadata.json"
$manifestPath = Join-Path $runDirectory "run-manifest.json"

Copy-SnapshotFile -SourcePath $resolvedCasePath.Path -DestinationPath $caseSnapshotPath
Copy-SnapshotFile -SourcePath $weightsSourcePath -DestinationPath $weightsSnapshotPath

$fixtureSourcePath = $null
$fixtureMaterializedPath = $null
if ($caseDefinition.fixture.mode -ne "none" -and $caseDefinition.fixture.path) {
    $fixtureSourcePath = Join-Path $repoRoot $caseDefinition.fixture.path
    $fixtureMaterializedPath = Copy-Fixture -SourcePath $fixtureSourcePath -FixtureDirectory $fixtureDirectory
}

& pwsh -NoProfile -File (Join-Path $PSScriptRoot "new-regression-result-template.ps1") -CasePath $resolvedCasePath -OutputPath $resultOutputPath -RunId $runId | Out-Null

$reviewPlaceholder = @(
    "# Review Output Placeholder",
    "",
    "Case ID: $($caseDefinition.id)",
    "Task: $($caseDefinition.task)",
    "",
    "Replace this file with the captured human-readable prompt or skill output for this run."
)
$reviewPlaceholder | Set-Content -LiteralPath $reviewOutputPath

$resolvedCaseAbsolutePath = $resolvedCasePath.Path
$relativeCasePath = Get-RelativeRepoPath -RepoRoot $repoRoot -Path $resolvedCaseAbsolutePath
$relativeCaseSnapshotPath = Get-RelativeRepoPath -RepoRoot $repoRoot -Path $caseSnapshotPath
$relativeWeightsSnapshotPath = Get-RelativeRepoPath -RepoRoot $repoRoot -Path $weightsSnapshotPath
$relativeManifestPath = Get-RelativeRepoPath -RepoRoot $repoRoot -Path $manifestPath
$relativeReviewOutputPath = Get-RelativeRepoPath -RepoRoot $repoRoot -Path $reviewOutputPath
$relativeResultOutputPath = Get-RelativeRepoPath -RepoRoot $repoRoot -Path $resultOutputPath
$relativeExecutionMetadataPath = Get-RelativeRepoPath -RepoRoot $repoRoot -Path $executionMetadataPath
$relativeFixtureSourcePath = if ($fixtureSourcePath) { Get-RelativeRepoPath -RepoRoot $repoRoot -Path $fixtureSourcePath } else { $null }
$relativeFixtureMaterializedPath = if ($fixtureMaterializedPath) { Get-RelativeRepoPath -RepoRoot $repoRoot -Path $fixtureMaterializedPath } else { $null }
$repositorySnapshot = Get-RepositorySnapshot -RepoRoot $repoRoot

$executionMetadata = [ordered]@{
    version = 1
    runId = $runId
    captureStatus = "scaffolded"
    executionMode = "fixture-driven"
    liveRepoStateUsed = $false
    repositorySnapshot = $repositorySnapshot
    modeledContext = [ordered]@{
        task = $caseDefinition.task
        changedFiles = @($caseDefinition.scope.changedFiles)
        scopeNotes = $caseDefinition.scope.notes
    }
    invocation = [ordered]@{
        executor = ""
        target = ""
        source = ""
        commandLine = ""
        notes = ""
    }
}

$executionMetadata | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $executionMetadataPath

$manifest = [ordered]@{
    version = 2
    runId = $runId
    createdUtc = [DateTime]::UtcNow.ToString("o")
    case = [ordered]@{
        id = $caseDefinition.id
        task = $caseDefinition.task
        status = $caseDefinition.caseStatus
        casePath = $relativeCasePath
    }
    fixture = [ordered]@{
        mode = $caseDefinition.fixture.mode
        sourcePath = $relativeFixtureSourcePath
        materializedPath = $relativeFixtureMaterializedPath
    }
    repositorySnapshot = $repositorySnapshot
    inputs = [ordered]@{
        caseSnapshotPath = $relativeCaseSnapshotPath
        caseSnapshotSha256 = Get-FileSha256 -Path $caseSnapshotPath
        weightsSnapshotPath = $relativeWeightsSnapshotPath
        weightsSnapshotSha256 = Get-FileSha256 -Path $weightsSnapshotPath
    }
    capture = [ordered]@{
        executionMetadataPath = $relativeExecutionMetadataPath
    }
    executionEnvelope = [ordered]@{
        mode = "fixture-driven"
        liveRepoStateRequired = $false
        captureStatus = "scaffolded"
        modeledChangedFiles = @($caseDefinition.scope.changedFiles)
        modeledScopeNotes = $caseDefinition.scope.notes
    }
    artifacts = [ordered]@{
        reviewOutputPath = $relativeReviewOutputPath
        resultOutputPath = $relativeResultOutputPath
        manifestPath = $relativeManifestPath
    }
    commands = [ordered]@{
        hydrateExample = "pwsh -NoProfile -File ./tools/regression/hydrate-regression-run.ps1 -RunDirectory ./$([System.IO.Path]::GetRelativePath($repoRoot, $runDirectory))"
        validate = "pwsh -NoProfile -File ./tools/regression/validate-regression-artifacts.ps1 -CasePath ./$relativeCaseSnapshotPath -ResultPath ./$relativeResultOutputPath"
        score = "pwsh -NoProfile -File ./tools/regression/score-regression-case.ps1 -CasePath ./$relativeCaseSnapshotPath -ResultPath ./$relativeResultOutputPath -WeightsPath ./$relativeWeightsSnapshotPath"
        previewExample = "pwsh -NoProfile -File ./tools/regression/run-regression-example.ps1 -CasePath ./$relativeCaseSnapshotPath -ShowFixture -ShowReview"
    }
    nextSteps = @(
        "optionally hydrate the run from adjudicated example artifacts using the hydrateExample command",
        "fill in capture/execution-metadata.json with the exact executor, command, and invocation notes for the real run",
        "replace the review file with the captured human-readable output for a real run",
        "update the generated result file with the adjudicated outcome for the run",
        "run the validate command from this manifest before scoring to confirm the captured artifacts are still structurally valid",
        "run the score command from this manifest to compute the weighted benchmark result against the snapshotted case and weights"
    )
}

$manifest | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $manifestPath

$runManifestSchemaPath = Join-Path $PSScriptRoot "schema/run-manifest.schema.json"
$manifestIsValid = (Get-Content -LiteralPath $manifestPath -Raw) | Test-Json -SchemaFile $runManifestSchemaPath
if (-not $manifestIsValid) {
    throw "generated run manifest failed schema validation: $manifestPath"
}

Write-Output "Regression run scaffold created"
Write-Output "  Case ID         : $($caseDefinition.id)"
Write-Output "  Task            : $($caseDefinition.task)"
Write-Output "  Run ID          : $runId"
Write-Output "  Run Directory   : $runDirectory"
if ($fixtureMaterializedPath) {
    Write-Output "  Fixture Copy    : $fixtureMaterializedPath"
}
Write-Output "  Case Snapshot   : $caseSnapshotPath"
Write-Output "  Weights Snapshot: $weightsSnapshotPath"
Write-Output "  Capture Metadata: $executionMetadataPath"
Write-Output "  Review Output   : $reviewOutputPath"
Write-Output "  Result Template : $resultOutputPath"
Write-Output "  Run Manifest    : $manifestPath"
Write-Output ""
Write-Output "Next command:"
Write-Output "  $($manifest.commands.validate)"
