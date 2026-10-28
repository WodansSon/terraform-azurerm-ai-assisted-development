Set-StrictMode -Version Latest
. (Join-Path $PSScriptRoot 'WorkbenchIconPreview.ps1')

function Read-WorkbenchIconRuntime {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $IconDirectory
    )

    $directory = Get-Item -LiteralPath $IconDirectory -Force -ErrorAction Stop
    if (-not $directory.PSIsContainer -or ($directory.Attributes -band [IO.FileAttributes]::ReparsePoint)) {
        throw 'An icon family must be an ordinary directory'
    }
    for ($ancestor = $directory.Parent; $null -ne $ancestor; $ancestor = $ancestor.Parent) {
        if ($ancestor.Attributes -band [IO.FileAttributes]::ReparsePoint) {
            throw 'An icon family must not use links or junctions'
        }
    }
    $configurationPath = Join-Path $directory.FullName 'runtime.json'
    $configurationFile = Get-Item -LiteralPath $configurationPath -Force -ErrorAction Stop
    if ($configurationFile.PSIsContainer -or ($configurationFile.Attributes -band [IO.FileAttributes]::ReparsePoint) -or $configurationFile.Length -gt 65536) {
        throw 'The icon runtime configuration must be a bounded ordinary file'
    }
    $json = Get-Content -LiteralPath $configurationPath -Raw
    $schemaPath = Join-Path $PSScriptRoot '../../../contracts/workbench/icon-runtime.schema.json'
    if (-not ($json | Test-Json -SchemaFile $schemaPath -ErrorAction Stop)) {
        throw 'The icon runtime configuration does not satisfy its schema'
    }
    $configuration = $json | ConvertFrom-Json
    $sourceFiles = @(Get-ChildItem -LiteralPath $directory.FullName -Filter '*.svg' -File -Force |
        Where-Object { $_.Name -notin @('sprite.svg', 'preview.svg') } | Sort-Object Name -CaseSensitive)
    if (-not $sourceFiles.Count) { throw 'An icon family must contain source artwork' }
    foreach ($sourceFile in $sourceFiles) {
        if ($sourceFile.BaseName -cnotmatch '^[a-z0-9]+(?:-[a-z0-9]+)*$' -or ($sourceFile.Attributes -band [IO.FileAttributes]::ReparsePoint)) {
            throw "Invalid icon source file: $($sourceFile.Name)"
        }
    }
    foreach ($iconName in $configuration.sprite.icons) {
        if ($iconName -cnotin $sourceFiles.BaseName) {
            throw "Runtime icon has no source artwork: $iconName"
        }
    }
    foreach ($fileName in $configuration.runtimeFiles) {
        if ($fileName -cne 'sprite.svg' -and [IO.Path]::GetExtension($fileName) -cnotin @('.md', '.txt')) {
            throw "Runtime companions must be legal or attribution notices: $fileName"
        }
        $filePath = Join-Path $directory.FullName $fileName
        if ($fileName -ceq 'sprite.svg' -and -not (Test-Path -LiteralPath $filePath)) { continue }
        $file = Get-Item -LiteralPath $filePath -Force -ErrorAction Stop
        if ($file.PSIsContainer -or ($file.Attributes -band [IO.FileAttributes]::ReparsePoint)) {
            throw "Runtime icon assets must be ordinary files: $fileName"
        }
    }
    $legalFiles = @(Get-ChildItem -LiteralPath $directory.FullName -File -Force |
        Where-Object { $_.Name -cmatch '^LICENSE(?:[._-].*)?$|^NOTICE(?:[._-].*)?$|^ATTRIBUTION\.md$' })
    foreach ($legalFile in $legalFiles) {
        if ($legalFile.Name -cnotin $configuration.runtimeFiles) {
            throw "The runtime configuration omits a legal notice: $($legalFile.Name)"
        }
    }
    [pscustomobject]@{
        Directory = $directory.FullName
        Configuration = $configuration
        PreviewIconNames = @($sourceFiles.BaseName)
        RuntimeIconNames = @($configuration.sprite.icons)
        RuntimeFiles = @($configuration.runtimeFiles)
    }
}

function Get-WorkbenchRuntimeIconAssets {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $IconRoot
    )

    $families = @(Get-ChildItem -LiteralPath $IconRoot -Directory -Force | Sort-Object Name -CaseSensitive)
    if (-not $families.Count) { throw 'The Workbench requires configured icon families' }
    $prefixes = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    foreach ($family in $families) {
        $runtime = Read-WorkbenchIconRuntime -IconDirectory $family.FullName
        if (-not $prefixes.Add($runtime.Configuration.symbolPrefix)) {
            throw "Duplicate icon symbol prefix: $($runtime.Configuration.symbolPrefix)"
        }
        foreach ($fileName in $runtime.RuntimeFiles) {
            $assetPath = Join-Path $family.FullName $fileName
            if (-not (Test-Path -LiteralPath $assetPath -PathType Leaf)) {
                throw "Required runtime icon asset is missing: $($family.Name)/$fileName"
            }
            "$($family.Name)/$fileName"
        }
    }
}

function New-WorkbenchIconAssets {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $IconDirectory
    )

    $runtime = Read-WorkbenchIconRuntime -IconDirectory $IconDirectory
    $configuration = $runtime.Configuration
    $symbols = @{}
    foreach ($iconName in $runtime.PreviewIconNames) {
        $settings = [Xml.XmlReaderSettings]::new()
        $settings.DtdProcessing = [Xml.DtdProcessing]::Prohibit
        $settings.XmlResolver = $null
        $reader = [Xml.XmlReader]::Create((Join-Path $runtime.Directory "$iconName.svg"), $settings)
        try {
            $document = [Xml.XmlDocument]::new()
            $document.PreserveWhitespace = $true
            $document.XmlResolver = $null
            $document.Load($reader)
        }
        finally { $reader.Dispose() }
        $root = $document.DocumentElement
        $viewBox = $root.GetAttribute('viewBox')
        if ($root.LocalName -cne 'svg' -or $root.NamespaceURI -cne 'http://www.w3.org/2000/svg' -or $viewBox -cnotmatch '^0 0 [1-9][0-9]* [1-9][0-9]*$' -or -not $root.InnerXml.Trim()) {
            throw "Invalid SVG icon geometry: $iconName"
        }
        if ($configuration.colorMode -ceq 'monochrome') {
            foreach ($node in $document.SelectNodes('//*[@fill="#212121"]')) {
                $node.SetAttribute('fill', 'currentColor')
            }
        }
        $presentation = foreach ($attributeName in @('fill', 'fill-rule', 'clip-rule')) {
            $value = $root.GetAttribute($attributeName)
            if ($value) { " $attributeName=`"$([Security.SecurityElement]::Escape($value))`"" }
        }
        $style = $root.GetAttribute('style')
        if ($style -cnotin @('', 'flex:none;line-height:1', 'flex:none;line-height:1;filter:grayscale(100%)')) {
            throw "Unsupported SVG root styling: $iconName"
        }
        if ($style.EndsWith(';filter:grayscale(100%)', [StringComparison]::Ordinal)) {
            $presentation += ' filter="grayscale(100%)"'
        }
        $symbols[$iconName] = "  <symbol id=`"$($configuration.symbolPrefix)-$iconName`" viewBox=`"$viewBox`"$($presentation -join '')>$($root.InnerXml.Trim())</symbol>"
    }
    $sprite = @(
        '<svg xmlns="http://www.w3.org/2000/svg">'
        '<!-- Generated by hosted_copilot/tools/internal/workbench/WorkbenchIconAssets.ps1. -->'
        "<!-- Source: $($configuration.sourceUrl) -->"
        $runtime.RuntimeIconNames | ForEach-Object { $symbols[$_] }
        '</svg>'
    ) -join "`n"
    $spritePath = Join-Path $runtime.Directory 'sprite.svg'
    [IO.File]::WriteAllText($spritePath, $sprite + "`n", [Text.UTF8Encoding]::new($false))
    $previewPath = New-WorkbenchIconPreview -IconDirectory $runtime.Directory -FamilyName $configuration.familyName -Commit $configuration.revision -SymbolPrefix $configuration.symbolPrefix -IconNames $runtime.PreviewIconNames -SymbolMarkup @($runtime.PreviewIconNames | ForEach-Object { $symbols[$_] })
    [pscustomobject]@{
        Status = 'generated'
        Family = $configuration.familyName
        IconCount = $runtime.RuntimeIconNames.Count
        PreviewIconCount = $runtime.PreviewIconNames.Count
        SpritePath = $spritePath
        PreviewPngPath = $previewPath
    }
}

function Copy-WorkbenchRuntimeIconAssets {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $IconRoot,

        [Parameter(Mandatory)]
        [string] $Destination
    )

    $assets = @(Get-WorkbenchRuntimeIconAssets -IconRoot $IconRoot)
    $destinationPath = [IO.Path]::GetFullPath($Destination)
    $sourcePath = [IO.Path]::GetFullPath($IconRoot)
    $sourcePrefix = $sourcePath.TrimEnd([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar) + [IO.Path]::DirectorySeparatorChar
    $destinationPrefix = $destinationPath.TrimEnd([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar) + [IO.Path]::DirectorySeparatorChar
    if ($destinationPath.Equals($sourcePath, [StringComparison]::OrdinalIgnoreCase) -or $destinationPath.StartsWith($sourcePrefix, [StringComparison]::OrdinalIgnoreCase) -or $sourcePath.StartsWith($destinationPrefix, [StringComparison]::OrdinalIgnoreCase)) {
        throw 'Runtime icon staging must not overlap source artwork'
    }
    for ($ancestor = [IO.DirectoryInfo]::new($destinationPath); $null -ne $ancestor; $ancestor = $ancestor.Parent) {
        if ($ancestor.Exists -and ($ancestor.Attributes -band [IO.FileAttributes]::ReparsePoint)) {
            throw 'Runtime icon staging must not use links or junctions'
        }
    }
    if (Test-Path -LiteralPath $destinationPath) {
        if (@(Get-ChildItem -LiteralPath $destinationPath -Recurse -Force -Attributes ReparsePoint).Count) {
            throw 'Runtime icon staging must not contain links or junctions'
        }
        Remove-Item -LiteralPath $destinationPath -Recurse -Force
    }
    foreach ($asset in $assets) {
        $target = Join-Path $destinationPath $asset
        New-Item -ItemType Directory -Path (Split-Path -Parent $target) -Force | Out-Null
        Copy-Item -LiteralPath (Join-Path $IconRoot $asset) -Destination $target -Force
    }
}
