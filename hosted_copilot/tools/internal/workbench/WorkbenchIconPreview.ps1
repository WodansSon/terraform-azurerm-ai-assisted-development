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
        [string[]]$IconNames,

        [Parameter()]
        [string[]]$SymbolMarkup
    )

    $rendererPath = Join-Path $PSScriptRoot '../../Render-WorkbenchIconPreview.cjs'
    if (-not (Test-Path -LiteralPath $rendererPath -PathType Leaf)) {
        throw "Workbench icon preview renderer was not found: $rendererPath"
    }
    $nodeCommand = Get-Command node -ErrorAction Stop

    $symbols = if ($null -ne $SymbolMarkup -and $SymbolMarkup.Count -gt 0) {
        @($SymbolMarkup)
    }
    else {
        $spritePath = Join-Path $IconDirectory 'sprite.svg'
        $spriteContent = Get-Content -LiteralPath $spritePath -Raw
        @([regex]::Matches($spriteContent, '<symbol\b[\s\S]*?</symbol>') | ForEach-Object { $_.Value })
    }
    $columns = [Math]::Min(6, [Math]::Ceiling([Math]::Sqrt($IconNames.Count)))
    $rows = [Math]::Ceiling($IconNames.Count / $columns)
    $width = 48 + ($columns * 176)
    $height = 100 + ($rows * 104)
    $cards = for ($index = 0; $index -lt $IconNames.Count; $index += 1) {
        $iconName = $IconNames[$index]
        $x = 24 + (($index % $columns) * 176)
        $y = 76 + ([Math]::Floor($index / $columns) * 104)
        $labelParts = @($iconName -split '-')
        $labelLines = @($iconName)
        if ($iconName.Length -gt 24 -and $labelParts.Count -gt 1) {
            $bestSplit = 1
            $bestDifference = [int]::MaxValue
            for ($split = 1; $split -lt $labelParts.Count; $split += 1) {
                $leftLength = (($labelParts[0..($split - 1)] -join '-').Length)
                $rightLength = (($labelParts[$split..($labelParts.Count - 1)] -join '-').Length)
                $difference = [Math]::Abs($leftLength - $rightLength)
                if ($difference -lt $bestDifference) {
                    $bestSplit = $split
                    $bestDifference = $difference
                }
            }
            $labelLines = @(
                $labelParts[0..($bestSplit - 1)] -join '-'
                $labelParts[$bestSplit..($labelParts.Count - 1)] -join '-'
            )
        }
        $escapedLabelLines = @($labelLines | ForEach-Object { [Security.SecurityElement]::Escape($_) })
        $labelMarkup = if ($escapedLabelLines.Count -eq 1) {
            "    <text x=`"80`" y=`"69`" fill=`"#b1bac4`" font-family=`"Segoe UI, Arial, sans-serif`" font-size=`"12`" text-anchor=`"middle`">$($escapedLabelLines[0])</text>"
        }
        else {
            "    <text x=`"80`" y=`"62`" fill=`"#b1bac4`" font-family=`"Segoe UI, Arial, sans-serif`" font-size=`"11`" text-anchor=`"middle`"><tspan x=`"80`">$($escapedLabelLines[0])</tspan><tspan x=`"80`" dy=`"14`">$($escapedLabelLines[1])</tspan></text>"
        }
        @"
  <g transform="translate($x $y)">
    <rect width="160" height="88" rx="6" fill="#161b22" stroke="#30363d"/>
    <svg x="64" y="12" width="32" height="32" fill="#f0f6fc" color="#f0f6fc"><use href="#$SymbolPrefix-$iconName"/></svg>
$labelMarkup
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
    try {
        Set-Content -LiteralPath $previewSvgPath -Value $previewSvg -Encoding utf8NoBOM
        Remove-Item -LiteralPath $previewPngPath -Force -ErrorAction SilentlyContinue
        $rendererOutput = @(& $nodeCommand.Source $rendererPath $previewSvgPath $previewPngPath $width $height 2>&1)
        $rendererExitCode = if ($null -ne $LASTEXITCODE) { $LASTEXITCODE } else { 0 }
        if ($rendererExitCode -ne 0 -or -not (Test-Path -LiteralPath $previewPngPath -PathType Leaf)) {
            throw "Failed to generate '$previewPngPath': $(($rendererOutput | Out-String).Trim())"
        }
    }
    finally {
        Remove-Item -LiteralPath $previewSvgPath -Force -ErrorAction SilentlyContinue
    }

    $previewPngPath
}
