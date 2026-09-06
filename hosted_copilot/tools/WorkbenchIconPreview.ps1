Set-StrictMode -Version Latest

function New-WorkbenchIconPreview {
    param(
        [Parameter(Mandatory = $true)]
        [string]$IconDirectory,

        [Parameter(Mandatory = $true)]
        [string]$FamilyName,

        [Parameter(Mandatory = $true)]
        [string]$Commit,

        [Parameter(Mandatory = $true)]
        [string]$SymbolPrefix,

        [Parameter(Mandatory = $true)]
        [string[]]$IconNames
    )

    $edgePath = @(
        (Get-Command msedge -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Source -First 1)
        $(if (${env:ProgramFiles(x86)}) { Join-Path ${env:ProgramFiles(x86)} 'Microsoft\Edge\Application\msedge.exe' })
        $(if ($env:ProgramFiles) { Join-Path $env:ProgramFiles 'Microsoft\Edge\Application\msedge.exe' })
    ) | Where-Object { $_ -and (Test-Path -LiteralPath $_ -PathType Leaf) } | Select-Object -First 1
    if (-not $edgePath) {
        throw 'Microsoft Edge is required to generate the icon preview PNG.'
    }

    $spritePath = Join-Path $IconDirectory 'sprite.svg'
    $spriteContent = Get-Content -LiteralPath $spritePath -Raw
    $symbols = [regex]::Matches($spriteContent, '<symbol\b[\s\S]*?</symbol>') | ForEach-Object { $_.Value }
    $columns = [Math]::Min(6, [Math]::Ceiling([Math]::Sqrt($IconNames.Count)))
    $rows = [Math]::Ceiling($IconNames.Count / $columns)
    $width = 48 + ($columns * 176)
    $height = 100 + ($rows * 92)
    $cards = for ($index = 0; $index -lt $IconNames.Count; $index += 1) {
        $iconName = $IconNames[$index]
        $x = 24 + (($index % $columns) * 176)
        $y = 76 + ([Math]::Floor($index / $columns) * 92)
        $label = [Security.SecurityElement]::Escape($iconName)
        @"
  <g transform="translate($x $y)">
    <rect width="160" height="76" rx="6" fill="#161b22" stroke="#30363d"/>
    <svg x="64" y="12" width="32" height="32" fill="#f0f6fc"><use href="#$SymbolPrefix-$iconName"/></svg>
    <text x="80" y="61" fill="#b1bac4" font-family="Segoe UI, Arial, sans-serif" font-size="12" text-anchor="middle">$label</text>
  </g>
"@
    }
    $escapedFamilyName = [Security.SecurityElement]::Escape($FamilyName)
    $previewSvg = @"
<svg xmlns="http://www.w3.org/2000/svg" width="$width" height="$height" viewBox="0 0 $width $height">
  <rect width="100%" height="100%" fill="#0d1117"/>
  <defs>$($symbols -join '')</defs>
  <text x="24" y="32" fill="#f0f6fc" font-family="Segoe UI, Arial, sans-serif" font-size="20" font-weight="600">$escapedFamilyName sprite</text>
  <text x="24" y="55" fill="#8c959f" font-family="Segoe UI, Arial, sans-serif" font-size="12">$($IconNames.Count) included icons · commit $Commit</text>
$($cards -join "`n")
</svg>
"@
    $previewSvgPath = Join-Path $IconDirectory 'preview.svg'
    $previewPngPath = Join-Path $IconDirectory 'preview.png'
    $temporaryProfile = Join-Path ([IO.Path]::GetTempPath()) ('workbench-icon-preview-' + [guid]::NewGuid().ToString('N'))
    try {
        Set-Content -LiteralPath $previewSvgPath -Value $previewSvg -Encoding utf8NoBOM
        Remove-Item -LiteralPath $previewPngPath -Force -ErrorAction SilentlyContinue
        $previewUri = [Uri]::new([IO.Path]::GetFullPath($previewSvgPath)).AbsoluteUri
        $arguments = @('--headless=new', '--disable-gpu', '--hide-scrollbars', '--no-first-run', "--user-data-dir=$temporaryProfile", "--window-size=$width,$height", "--screenshot=$previewPngPath", $previewUri)
        $process = Start-Process -FilePath $edgePath -ArgumentList $arguments -Wait -PassThru
        if ($process.ExitCode -ne 0 -or -not (Test-Path -LiteralPath $previewPngPath -PathType Leaf)) {
            throw "Failed to generate '$previewPngPath'."
        }
    }
    finally {
        Remove-Item -LiteralPath $temporaryProfile -Recurse -Force -ErrorAction SilentlyContinue
        Remove-Item -LiteralPath $previewSvgPath -Force -ErrorAction SilentlyContinue
    }

    $previewPngPath
}
