[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$Version,

    [string]$Commit,

    [string]$OutputRoot,

    [switch]$SkipArchive,

    [switch]$SkipVerifyChecksum,

    [switch]$SkipWsl,

    [switch]$Force
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Copy-ItemSafe {
    param(
        [Parameter(Mandatory)]
        [string]$Path,

        [Parameter(Mandatory)]
        [string]$Destination
    )

    if (-not (Test-Path $Path)) {
        throw "Required path not found: $Path"
    }

    $parent = Split-Path -Parent $Destination
    if ($parent) {
        New-Item -ItemType Directory -Path $parent -Force | Out-Null
    }

    Copy-Item -Path $Path -Destination $Destination -Recurse -Force
}

function Copy-DirectoryContentsSafe {
    param(
        [Parameter(Mandatory)]
        [string]$SourceDirectory,

        [Parameter(Mandatory)]
        [string]$DestinationDirectory
    )

    if (-not (Test-Path $SourceDirectory)) {
        throw "Required path not found: $SourceDirectory"
    }

    New-Item -ItemType Directory -Path $DestinationDirectory -Force | Out-Null

    Get-ChildItem -Path $SourceDirectory -Force | ForEach-Object {
        Copy-Item -Path $_.FullName -Destination (Join-Path $DestinationDirectory $_.Name) -Recurse -Force
    }
}

function Get-ManifestSectionEntries {
    param(
        [Parameter(Mandatory)]
        [string]$ManifestPath,

        [Parameter(Mandatory)]
        [string[]]$Sections
    )

    $entries = [System.Collections.Generic.List[string]]::new()
    $currentSection = ''

    foreach ($line in Get-Content -Path $ManifestPath) {
        $trimmed = $line.Trim()
        if ($trimmed -match '^\[(.+)\]$') {
            $currentSection = $matches[1]
            continue
        }

        if (-not $trimmed -or $trimmed.StartsWith('#')) {
            continue
        }

        if ($currentSection -in $Sections) {
            $entries.Add($trimmed)
        }
    }

    return @($entries | Select-Object -Unique)
}

function Resolve-ShortCommit {
    param([string]$RepoRoot)

    $git = Get-Command git -ErrorAction SilentlyContinue
    if ($null -eq $git) {
        throw 'git is required to resolve the default commit for the dry-run bundle'
    }

    $sha = @(& $git.Source -C $RepoRoot rev-parse --short HEAD 2>$null)
    if ($LASTEXITCODE -ne 0) {
        throw 'failed to resolve git commit from the current repository'
    }

    $resolved = ($sha | Select-Object -First 1).Trim().ToLowerInvariant()
    if (-not $resolved) {
        throw 'resolved git commit was empty'
    }

    return $resolved
}

$repoRoot = Split-Path -Parent $PSScriptRoot
$installerSourceRoot = Join-Path $repoRoot 'installer'
$manifestPath = Join-Path $installerSourceRoot 'file-manifest.config'
$verifyScriptPath = Join-Path $PSScriptRoot 'verify-bundle-checksum.ps1'
$validationModulePath = Join-Path $installerSourceRoot 'modules/powershell/ValidationEngine.psm1'

if (-not $Commit) {
    $Commit = Resolve-ShortCommit -RepoRoot $repoRoot
}

$Commit = $Commit.Trim().ToLowerInvariant()
if ($Commit -notmatch '^[0-9a-f]{7,40}$') {
    throw 'commit must be a 7-40 character hexadecimal git sha'
}

if (-not $OutputRoot) {
    $OutputRoot = Join-Path $repoRoot 'release-dry-run'
}

$stageName = ('v{0}-{1}' -f $Version, $Commit) -replace '[^0-9A-Za-z._-]', '_'
$stageRoot = Join-Path $OutputRoot $stageName
$installerRoot = Join-Path $stageRoot '.terraform-azurerm-ai-installer'

if (Test-Path $stageRoot) {
    if (-not $Force) {
        throw "dry-run output already exists: $stageRoot`nUse -Force to replace it."
    }

    Remove-Item -Path $stageRoot -Recurse -Force
}

New-Item -ItemType Directory -Path $installerRoot -Force | Out-Null
New-Item -ItemType Directory -Path (Join-Path $installerRoot 'modules/powershell') -Force | Out-Null
New-Item -ItemType Directory -Path (Join-Path $installerRoot 'modules/bash') -Force | Out-Null

Copy-ItemSafe -Path (Join-Path $installerSourceRoot 'install-copilot-setup.ps1') -Destination (Join-Path $installerRoot 'install-copilot-setup.ps1')
Copy-ItemSafe -Path (Join-Path $installerSourceRoot 'install-copilot-setup.sh') -Destination (Join-Path $installerRoot 'install-copilot-setup.sh')
Copy-ItemSafe -Path $manifestPath -Destination (Join-Path $installerRoot 'file-manifest.config')
Copy-DirectoryContentsSafe -SourceDirectory (Join-Path $installerSourceRoot 'modules/powershell') -DestinationDirectory (Join-Path $installerRoot 'modules/powershell')
Copy-DirectoryContentsSafe -SourceDirectory (Join-Path $installerSourceRoot 'modules/bash') -DestinationDirectory (Join-Path $installerRoot 'modules/bash')
Set-Content -Path (Join-Path $installerRoot 'VERSION') -Value $Version -NoNewline -Force

$payloadRoot = Join-Path $installerRoot 'aii'
New-Item -ItemType Directory -Path $payloadRoot -Force | Out-Null

$manifestSections = @('MAIN_FILES', 'INSTRUCTION_FILES', 'PROMPT_FILES', 'SKILL_FILES', 'UNIVERSAL_FILES')
$manifestEntries = Get-ManifestSectionEntries -ManifestPath $manifestPath -Sections $manifestSections
foreach ($entry in $manifestEntries) {
    $sourcePath = Join-Path $repoRoot $entry
    $destinationPath = Join-Path $payloadRoot $entry
    Copy-ItemSafe -Path $sourcePath -Destination $destinationPath
}

Import-Module $validationModulePath -Force | Out-Null
$checksumResult = Write-InstallerChecksum -InstallerRoot $installerRoot -Version $Version -Commit $Commit
if (-not $checksumResult.Valid) {
    throw "failed to generate installer checksum: $($checksumResult.Reason)"
}

if (-not $SkipVerifyChecksum) {
    & $verifyScriptPath -InstallerRoot $installerRoot -SkipWsl:$SkipWsl
    if ($LASTEXITCODE -ne 0) {
        throw 'installer bundle checksum verification failed'
    }
}

Push-Location $stageRoot
try {
    $createdArtifacts = [System.Collections.Generic.List[string]]::new()

    if (-not $SkipArchive) {
        $versionedZip = Join-Path $stageRoot ("terraform-azurerm-ai-installer-v{0}.zip" -f $Version)
        Compress-Archive -Path '.terraform-azurerm-ai-installer' -DestinationPath $versionedZip -Force
        $createdArtifacts.Add($versionedZip)

        $stableZip = Join-Path $stageRoot 'terraform-azurerm-ai-installer.zip'
        Copy-Item -Path $versionedZip -Destination $stableZip -Force
        $createdArtifacts.Add($stableZip)

        $tarCommand = Get-Command tar -ErrorAction SilentlyContinue
        if ($null -ne $tarCommand) {
            $versionedTar = Join-Path $stageRoot ("terraform-azurerm-ai-installer-v{0}.tar.gz" -f $Version)
            & $tarCommand.Source -czf $versionedTar '.terraform-azurerm-ai-installer'
            if ($LASTEXITCODE -ne 0) {
                throw 'failed to create tar.gz archive for dry-run bundle'
            }
            $createdArtifacts.Add($versionedTar)

            $stableTar = Join-Path $stageRoot 'terraform-azurerm-ai-installer.tar.gz'
            Copy-Item -Path $versionedTar -Destination $stableTar -Force
            $createdArtifacts.Add($stableTar)
        }
        else {
            Write-Host 'tar was not found; skipping tar.gz archive generation' -ForegroundColor Yellow
        }

        if ($createdArtifacts.Count -gt 0) {
            $checksumsPath = Join-Path $stageRoot 'checksums.txt'
            $checksums = foreach ($artifact in $createdArtifacts) {
                $hash = (Get-FileHash -Path $artifact -Algorithm SHA256).Hash.ToLowerInvariant()
                '{0}  {1}' -f $hash, (Split-Path -Leaf $artifact)
            }
            $checksums | Set-Content -Path $checksumsPath
            $createdArtifacts.Add($checksumsPath)
        }
    }

    Write-Host ''
    Write-Host 'Dry-run release bundle created successfully' -ForegroundColor Green
    Write-Host ('  Version        : {0}' -f $Version) -ForegroundColor Cyan
    Write-Host ('  Commit         : {0}' -f $Commit.ToUpperInvariant()) -ForegroundColor Cyan
    Write-Host ('  Installer Root : {0}' -f $installerRoot) -ForegroundColor Cyan
    Write-Host ('  Output Root    : {0}' -f $stageRoot) -ForegroundColor Cyan
    if (-not $SkipArchive) {
        Write-Host '  Artifacts:' -ForegroundColor Cyan
        Get-ChildItem -Path $stageRoot -File | Sort-Object Name | ForEach-Object {
            Write-Host ('    - {0}' -f $_.FullName) -ForegroundColor White
        }
    }

    Write-Host ''
    Write-Host 'Next step:' -ForegroundColor Cyan
    Write-Host ('  & "{0}" -RepoDirectory "<path-to-terraform-provider-azurerm>"' -f (Join-Path $installerRoot 'install-copilot-setup.ps1')) -ForegroundColor White
}
finally {
    Pop-Location
}
