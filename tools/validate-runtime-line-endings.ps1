[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$RuntimeRoot,

    [Parameter(Mandatory = $true)]
    [string]$ManifestPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$RuntimeRoot = (Resolve-Path -LiteralPath $RuntimeRoot).Path
$ManifestPath = (Resolve-Path -LiteralPath $ManifestPath).Path

$manifestEntries = @(Get-Content -LiteralPath $ManifestPath | ForEach-Object { $_.Trim() } | Where-Object {
    $_ -and -not $_.StartsWith('#') -and -not $_.StartsWith('[')
})
$runtimeTextFiles = @($manifestEntries | Where-Object {
    [IO.Path]::GetExtension($_).ToLowerInvariant() -in @('.md', '.json')
})
$missingFiles = [System.Collections.Generic.List[string]]::new()
$lineEndingViolations = [System.Collections.Generic.List[string]]::new()

foreach ($relativePath in $runtimeTextFiles) {
    $fullPath = Join-Path $RuntimeRoot $relativePath
    if (-not (Test-Path -LiteralPath $fullPath -PathType Leaf)) {
        $missingFiles.Add($relativePath)
        continue
    }

    $bytes = [IO.File]::ReadAllBytes($fullPath)
    if ($bytes -contains [byte]13) {
        $lineEndingViolations.Add($relativePath)
    }
}

if ($missingFiles.Count -gt 0) {
    throw ("Manifest-managed AI text files are missing: {0}" -f ($missingFiles -join ', '))
}

if ($lineEndingViolations.Count -gt 0) {
    throw ("Manifest-managed AI text files must use LF line endings: {0}" -f ($lineEndingViolations -join ', '))
}

Write-Output ("Validated LF line endings in {0} manifest-managed AI text files." -f $runtimeTextFiles.Count)
