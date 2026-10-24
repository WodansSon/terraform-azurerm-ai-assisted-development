[CmdletBinding()]
param(
    [Parameter()]
    [string] $IconDirectory = (Join-Path $PSScriptRoot '../../../workbench/icons/fluent')
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'WorkbenchIconPreview.ps1')

$commit = 'a347af95478f989038cccbf085978865264c048a'
$iconNames = @(
    'checkmark-circle-20-regular',
    'checkmark-circle-20-filled',
    'dismiss-circle-20-regular',
    'dismiss-circle-20-filled',
    'error-circle-20-regular',
    'error-circle-20-filled',
    'important-20-regular',
    'important-20-filled',
    'info-20-regular',
    'info-20-filled',
    'question-circle-20-regular',
    'question-circle-20-filled',
    'warning-20-regular',
    'warning-20-filled',
    'shield-checkmark-20-regular',
    'shield-checkmark-20-filled',
    'shield-dismiss-20-regular',
    'shield-dismiss-20-filled',
    'shield-error-20-regular',
    'shield-error-20-filled',
    'shield-question-20-regular',
    'shield-question-20-filled',
    'shield-task-20-regular',
    'shield-task-20-filled',
    'document-add-20-regular',
    'document-add-20-filled',
    'document-bullet-list-20-regular',
    'document-bullet-list-20-filled',
    'document-checkmark-20-regular',
    'document-checkmark-20-filled',
    'document-dismiss-20-regular',
    'document-dismiss-20-filled',
    'document-edit-20-regular',
    'document-edit-20-filled',
    'document-error-20-regular',
    'document-error-20-filled',
    'document-lock-20-regular',
    'document-lock-20-filled',
    'document-search-20-regular',
    'document-search-20-filled',
    'document-sync-20-regular',
    'document-sync-20-filled',
    'document-text-20-regular',
    'document-text-20-filled',
    'approvals-app-20-regular',
    'approvals-app-20-filled',
    'arrow-sync-circle-20-regular',
    'arrow-sync-circle-20-filled',
    'book-information-20-regular',
    'book-information-20-filled',
    'bot-sparkle-20-regular',
    'bot-sparkle-20-filled',
    'brain-circuit-20-regular',
    'brain-circuit-20-filled',
    'certificate-20-regular',
    'certificate-20-filled',
    'clipboard-checkmark-20-regular',
    'clipboard-checkmark-20-filled',
    'clipboard-task-list-ltr-20-regular',
    'clipboard-task-list-ltr-20-filled',
    'data-usage-20-regular',
    'data-usage-20-filled',
    'gauge-20-regular',
    'gauge-20-filled',
    'history-20-regular',
    'history-20-filled',
    'lightbulb-20-regular',
    'lightbulb-20-filled',
    'person-feedback-20-regular',
    'person-feedback-20-filled',
    'target-arrow-20-regular',
    'target-arrow-20-filled',
    'arrow-routing-20-regular',
    'arrow-routing-20-filled',
    'arrow-routing-rectangle-multiple-20-regular',
    'arrow-routing-rectangle-multiple-20-filled',
    'arrow-split-20-regular',
    'arrow-split-20-filled',
    'flow-20-regular',
    'flow-20-filled',
    'flowchart-20-regular',
    'flowchart-20-filled',
    'link-multiple-20-regular',
    'link-multiple-20-filled',
    'connected-20-regular',
    'connected-20-filled',
    'group-list-20-regular',
    'group-list-20-filled',
    'shape-intersect-20-regular',
    'shape-intersect-20-filled',
    'merge-20-regular',
    'merge-20-filled',
    'stack-20-regular',
    'stack-20-filled',
    'stack-arrow-forward-20-regular',
    'stack-arrow-forward-20-filled',
    'gavel-20-regular',
    'gavel-20-filled',
    'gavel-prohibited-20-regular',
    'gavel-prohibited-20-filled',
    'scales-20-regular',
    'scales-20-filled',
    'checkbox-checked-sync-20-regular',
    'checkbox-checked-sync-20-filled',
    'flag-checkered-20-regular',
    'flag-checkered-20-filled',
    'ribbon-20-regular',
    'ribbon-20-filled',
    'ribbon-off-20-regular',
    'ribbon-off-20-filled',
    'person-edit-20-regular',
    'person-edit-20-filled',
    'archive-20-regular',
    'archive-20-filled',
    'archive-arrow-back-20-regular',
    'archive-arrow-back-20-filled',
    'arrow-undo-20-regular',
    'arrow-undo-20-filled',
    'arrow-redo-20-regular',
    'arrow-redo-20-filled',
    'arrow-sync-checkmark-20-regular',
    'arrow-sync-checkmark-20-filled',
    'arrow-sync-dismiss-20-regular',
    'arrow-sync-dismiss-20-filled',
    're-order-20-regular',
    're-order-20-filled',
    'document-copy-20-regular',
    'document-copy-20-filled',
    'document-arrow-right-20-regular',
    'document-arrow-right-20-filled',
    'clipboard-search-20-regular',
    'clipboard-search-20-filled',
    'clipboard-text-ltr-20-regular',
    'clipboard-text-ltr-20-filled',
    'text-quote-20-regular',
    'text-quote-20-filled',
    'database-search-20-regular',
    'database-search-20-filled',
    'task-list-square-sparkle-20-regular',
    'task-list-square-sparkle-20-filled',
    'wand-20-regular',
    'wand-20-filled'
)
$coreIconNames = @($iconNames)
$runtimeIconNames = @(
    'arrow-undo-20-filled',
    'arrow-routing-20-regular',
    'arrow-split-20-regular',
    'checkmark-circle-20-filled',
    'gauge-16-regular',
    'info-20-regular',
    'link-dismiss-16-filled',
    'link-multiple-16-filled',
    'warning-20-regular'
)

if (-not (Test-Path -LiteralPath $IconDirectory -PathType Container)) {
    throw "The vendored Fluent icon directory '$IconDirectory' does not exist."
}
if (-not (Test-Path -LiteralPath (Join-Path $IconDirectory 'ATTRIBUTION.md') -PathType Leaf)) {
    throw "The vendored Fluent icon attribution is missing from '$IconDirectory'."
}

$iconNames = @(Get-ChildItem -LiteralPath $IconDirectory -Filter '*.svg' -File |
    Where-Object { $_.Name -notin @('sprite.svg', 'preview.svg') } |
    ForEach-Object { $_.BaseName } |
    Sort-Object)
$invalidNames = @($iconNames | Where-Object { $_ -notmatch '^[a-z0-9]+(?:-[a-z0-9]+)*-(16|20)-(regular|filled)$' })
$incompletePairs = @($iconNames |
    Group-Object { $_ -replace '-(regular|filled)$', '' } |
    Where-Object { $_.Count -ne 2 })
$missingCoreIcons = @($coreIconNames | Where-Object { $_ -notin $iconNames })
$missingRuntimeIcons = @($runtimeIconNames | Where-Object { $_ -notin $iconNames })
if ($invalidNames.Count -gt 0) {
    throw "The vendored Fluent icon inventory contains invalid names: $($invalidNames -join ', ')."
}
if ($incompletePairs.Count -gt 0) {
    throw "The vendored Fluent icon inventory contains incomplete Regular/Filled pairs: $($incompletePairs.Name -join ', ')."
}
if ($missingCoreIcons.Count -gt 0) {
    throw "The vendored Fluent icon inventory is missing required core icons: $($missingCoreIcons -join ', ')."
}
if ($missingRuntimeIcons.Count -gt 0) {
    throw "The vendored Fluent icon inventory is missing runtime icons: $($missingRuntimeIcons -join ', ')."
}

$symbolByName = @{}
$symbols = foreach ($iconName in $iconNames) {
    $sourcePath = Join-Path $IconDirectory "$iconName.svg"
    if (-not (Test-Path -LiteralPath $sourcePath -PathType Leaf)) {
        throw "The vendored Fluent icon '$iconName' is missing from '$IconDirectory'."
    }
    $svg = (Get-Content -LiteralPath $sourcePath -Raw).Trim()
    $match = [regex]::Match($svg, '^<svg[^>]*viewBox="(?<viewBox>[^"]+)"[^>]*>(?<content>[\s\S]*)</svg>$')
    $sizeMatch = [regex]::Match($iconName, '-(?<size>16|20)-(regular|filled)$')
    $expectedViewBox = "0 0 $($sizeMatch.Groups['size'].Value) $($sizeMatch.Groups['size'].Value)"
    if (-not $match.Success -or -not $sizeMatch.Success -or $match.Groups['viewBox'].Value -ne $expectedViewBox) {
        throw "Fluent icon '$iconName' does not use the supported SVG viewBox."
    }
    $content = $match.Groups['content'].Value.Trim() -replace '\s+fill="#212121"', ''
    if (-not $content) {
        throw "Fluent icon '$iconName' is empty."
    }
    $symbol = "  <symbol id=`"fluent-$iconName`" viewBox=`"$expectedViewBox`">$content</symbol>"
    $symbolByName[$iconName] = $symbol
    $symbol
}
$runtimeSymbols = @($runtimeIconNames | ForEach-Object { $symbolByName[$_] })

$sprite = @(
    '<svg xmlns="http://www.w3.org/2000/svg">'
    '<!-- Generated by hosted_copilot/tools/internal/workbench/New-WorkbenchFluentIconSprite.ps1. -->'
    '<!-- Source: https://github.com/microsoft/fluentui-system-icons/tree/a347af95478f989038cccbf085978865264c048a/assets -->'
    $runtimeSymbols
    '</svg>'
) -join "`n"
$spritePath = Join-Path $IconDirectory 'sprite.svg'
Set-Content -LiteralPath $spritePath -Value $sprite -Encoding utf8NoBOM
$previewPngPath = New-WorkbenchIconPreview -IconDirectory $IconDirectory -FamilyName 'Microsoft Fluent UI System Icons' -Commit $commit -SymbolPrefix 'fluent' -IconNames $iconNames -SymbolMarkup $symbols

[pscustomobject]@{
    Status = 'generated'
    Commit = $commit
    IconCount = $runtimeIconNames.Count
    PreviewIconCount = $iconNames.Count
    SpritePath = $spritePath
    PreviewPngPath = $previewPngPath
    AttributionPath = (Join-Path $IconDirectory 'ATTRIBUTION.md')
}
