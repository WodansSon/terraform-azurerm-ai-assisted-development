# Verifies that an extracted installer bundle passes checksum validation.
# Optionally cross-checks the computed hash with a Bash implementation.
# - On Windows: uses WSL if available (and not skipped).
# - On non-Windows: uses native bash if available.
#
# Usage examples:
#   pwsh -NoProfile -File .\tools\verify-bundle-checksum.ps1 -InstallerRoot "$env:USERPROFILE\.terraform-azurerm-ai-installer"
#   pwsh -NoProfile -File .\tools\verify-bundle-checksum.ps1 -StageFromRepo
#

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$InstallerRoot,

    [Parameter(Mandatory = $false)]
    [switch]$StageFromRepo,

    # Historical name; when set, skips all Bash/WSL cross-checking.
    [Parameter(Mandatory = $false)]
    [switch]$SkipWsl
)

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

    Copy-Item -Path $Path -Destination $Destination -Recurse -Force
}

$repoRoot = Split-Path $PSScriptRoot -Parent
$sourceInstaller = Join-Path $repoRoot 'installer'

if ($StageFromRepo) {
    $tempRoot = if ($env:TEMP) { $env:TEMP } else { [System.IO.Path]::GetTempPath() }
    $stagingRoot = Join-Path $tempRoot ("azurerm-ai-installer-staging-" + [Guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path $stagingRoot | Out-Null

    Copy-ItemSafe -Path (Join-Path $sourceInstaller 'install-copilot-setup.ps1') -Destination $stagingRoot
    Copy-ItemSafe -Path (Join-Path $sourceInstaller 'install-copilot-setup.sh') -Destination $stagingRoot
    Copy-ItemSafe -Path (Join-Path $sourceInstaller 'file-manifest.config') -Destination $stagingRoot
    Copy-ItemSafe -Path (Join-Path $sourceInstaller 'VERSION') -Destination $stagingRoot
    Copy-ItemSafe -Path (Join-Path $sourceInstaller 'modules') -Destination (Join-Path $stagingRoot 'modules')
    Copy-ItemSafe -Path (Join-Path $sourceInstaller 'aii') -Destination (Join-Path $stagingRoot 'aii')

    $InstallerRoot = $stagingRoot
}

if (-not $InstallerRoot) {
    throw "Specify -InstallerRoot or use -StageFromRepo"
}

$InstallerRoot = (Resolve-Path $InstallerRoot).Path

$modulePath = Join-Path $InstallerRoot (Join-Path 'modules' (Join-Path 'powershell' 'ValidationEngine.psm1'))
if (-not (Test-Path $modulePath)) {
    # If we are running from the repo, use repo module for verification.
    $modulePath = Join-Path $sourceInstaller (Join-Path 'modules' (Join-Path 'powershell' 'ValidationEngine.psm1'))
}

Import-Module $modulePath -Force | Out-Null

# Ensure a checksum file exists for verification.
$checksumFile = Join-Path $InstallerRoot 'aii.checksum'
if (-not (Test-Path $checksumFile)) {
    Write-Host "aii.checksum not found; generating one for local verification" -ForegroundColor Yellow
    Write-InstallerChecksum -InstallerRoot $InstallerRoot -Version 'test' | Out-Null
}

$result = Test-InstallerChecksum -InstallerRoot $InstallerRoot
if (-not $result.Valid) {
    Write-Host "FAIL: $($result.Reason)" -ForegroundColor Red
    if ($result.Expected -and $result.Actual) {
        Write-Host "Expected: $($result.Expected)" -ForegroundColor Yellow
        Write-Host "Actual   : $($result.Actual)" -ForegroundColor Yellow
    }
    exit 1
}

Write-Host "PASS: PowerShell checksum validation succeeded" -ForegroundColor Green
$psHash = $result.Hash

if (-not $SkipWsl) {
    $bashScript = 'set -euo pipefail
root="$1"

# Convert Windows path to /mnt/... if wslpath is available
if command -v wslpath >/dev/null 2>&1; then
  root="$(wslpath -a -u "$1")"
fi

manifest="${root}/file-manifest.config"
payload="${root}/aii"

hash_file() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$1" | awk ''{print $1}''
  else
    shasum -a 256 "$1" | awk ''{print $1}''
  fi
}

manifest_hash=$(hash_file "${manifest}")

tmp="$(mktemp)"
printf "%s  %s\n" "${manifest_hash}" "file-manifest.config" > "${tmp}"
while IFS= read -r file; do
  rel="${file#${payload}/}"
  fh=$(hash_file "${file}")
  printf "%s  %s\n" "${fh}" "aii/${rel}" >> "${tmp}"
done < <(find "${payload}" -type f | LC_ALL=C sort)

if command -v sha256sum >/dev/null 2>&1; then
  sha256sum "${tmp}" | awk ''{print $1}''
else
  shasum -a 256 "${tmp}" | awk ''{print $1}''
fi

rm -f "${tmp}"'

    if ($IsWindows) {
        $wsl = Get-Command wsl -ErrorAction SilentlyContinue
        if ($wsl) {
            try {
                $wslHash = & wsl -e bash -lc $bashScript _ $InstallerRoot
                $wslHash = ($wslHash | Select-Object -First 1).Trim()

                if ($wslHash -and $psHash -and ($wslHash.ToLowerInvariant() -eq $psHash.ToLowerInvariant())) {
                    Write-Host "PASS: WSL/Bash checksum matches PowerShell" -ForegroundColor Green
                } else {
                    Write-Host "WARN: WSL/Bash checksum did not match PowerShell" -ForegroundColor Yellow
                    Write-Host "  WSL : $wslHash" -ForegroundColor Yellow
                    Write-Host "  PS  : $psHash" -ForegroundColor Yellow
                }
            }
            catch {
                Write-Host "WARN: WSL checksum cross-check failed: $($_.Exception.Message)" -ForegroundColor Yellow
            }
        }
    } else {
        $bash = Get-Command bash -ErrorAction SilentlyContinue
        if ($bash) {
            try {
                $bashHash = & bash -lc $bashScript _ $InstallerRoot
                $bashHash = ($bashHash | Select-Object -First 1).Trim()

                if ($bashHash -and $psHash -and ($bashHash.ToLowerInvariant() -eq $psHash.ToLowerInvariant())) {
                    Write-Host "PASS: Bash checksum matches PowerShell" -ForegroundColor Green
                } else {
                    Write-Host "WARN: Bash checksum did not match PowerShell" -ForegroundColor Yellow
                    Write-Host "  Bash: $bashHash" -ForegroundColor Yellow
                    Write-Host "  PS  : $psHash" -ForegroundColor Yellow
                }
            }
            catch {
                Write-Host "WARN: Bash checksum cross-check failed: $($_.Exception.Message)" -ForegroundColor Yellow
            }
        }
    }
}
