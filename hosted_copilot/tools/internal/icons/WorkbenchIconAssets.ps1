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
        if ([IO.Path]::GetExtension($fileName) -cnotin @('.md', '.txt')) {
            throw "Runtime companions must be legal or attribution notices: $fileName"
        }
        $filePath = Join-Path $directory.FullName $fileName
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
        [string] $IconRoot,

        [string] $SourceRoot = $PSScriptRoot
    )

    $families = @(Get-ChildItem -LiteralPath $SourceRoot -Directory -Force | Sort-Object Name -CaseSensitive)
    if (-not $families.Count) { throw 'The Workbench requires configured icon families' }
    $assets = [Collections.Generic.List[string]]::new()
    $assets.Add('sprite.svg')
    $prefixes = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    foreach ($family in $families) {
        $runtime = Read-WorkbenchIconRuntime -IconDirectory $family.FullName
        if (-not $prefixes.Add($runtime.Configuration.symbolPrefix)) {
            throw "Duplicate icon symbol prefix: $($runtime.Configuration.symbolPrefix)"
        }
        foreach ($fileName in $runtime.RuntimeFiles | Where-Object { $_ -cne 'sprite.svg' }) {
            $assets.Add("$($family.Name)/legal/$fileName")
        }
    }
    foreach ($asset in $assets) {
        $file = Get-Item -LiteralPath (Join-Path $IconRoot $asset) -Force -ErrorAction Stop
        if ($file.PSIsContainer -or ($file.Attributes -band [IO.FileAttributes]::ReparsePoint)) {
            throw "Runtime icon assets must be ordinary files: $asset"
        }
        for ($ancestor = $file.Directory; $null -ne $ancestor; $ancestor = $ancestor.Parent) {
            if ($ancestor.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw 'Runtime icon assets must not use links or junctions' }
        }
    }
    $unexpected = @(Get-ChildItem -LiteralPath $IconRoot -Recurse -File -Force | Where-Object {
        [IO.Path]::GetRelativePath([IO.Path]::GetFullPath($IconRoot), $_.FullName).Replace('\', '/') -cnotin $assets
    })
    if ($unexpected.Count) { throw 'The runtime sprite directory contains undeclared assets' }
    $assets
}

function Get-WorkbenchIconSymbols {
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
    [pscustomobject]@{
        Runtime = $runtime
        Symbols = $symbols
    }
}

function New-WorkbenchSprite {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $IconRoot,

        [Parameter(Mandatory)]
        [string] $Destination,

        [switch] $SkipPreviews
    )

    $families = @(Get-ChildItem -LiteralPath $IconRoot -Directory -Force | Sort-Object Name -CaseSensitive)
    if (-not $families.Count) { throw 'The Workbench requires configured icon families' }
    $symbolIds = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    $prefixes = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    $generatedFamilies = @(
        foreach ($family in $families) {
            if ($family.Name -cnotmatch '^[a-z][a-z0-9-]*$') { throw 'Invalid icon family directory name' }
            $generated = Get-WorkbenchIconSymbols -IconDirectory $family.FullName
            if (-not $prefixes.Add($generated.Runtime.Configuration.symbolPrefix)) { throw 'Duplicate icon symbol prefix' }
            foreach ($iconName in $generated.Runtime.RuntimeIconNames) {
                $symbolId = "$($generated.Runtime.Configuration.symbolPrefix)-$iconName"
                if (-not $symbolIds.Add($symbolId)) { throw "Duplicate icon symbol: $symbolId" }
            }
            [pscustomobject]@{ Name = $family.Name; Assets = $generated }
        }
    )
    $sourcePath = [IO.Path]::GetFullPath($IconRoot)
    $destinationPath = [IO.Path]::GetFullPath($Destination)
    $sourcePrefix = $sourcePath.TrimEnd([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar) + [IO.Path]::DirectorySeparatorChar
    $destinationPrefix = $destinationPath.TrimEnd([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar) + [IO.Path]::DirectorySeparatorChar
    if ($destinationPath.Equals($sourcePath, [StringComparison]::OrdinalIgnoreCase) -or $destinationPath.StartsWith($sourcePrefix, [StringComparison]::OrdinalIgnoreCase) -or $sourcePath.StartsWith($destinationPrefix, [StringComparison]::OrdinalIgnoreCase)) {
        throw 'Sprite output must not overlap source artwork'
    }
    for ($ancestor = [IO.DirectoryInfo]::new($destinationPath); $null -ne $ancestor; $ancestor = $ancestor.Parent) {
        if ($ancestor.Exists -and ($ancestor.Attributes -band [IO.FileAttributes]::ReparsePoint)) {
            throw 'Sprite output must not use links or junctions'
        }
    }
    if ((Test-Path -LiteralPath $destinationPath) -and @(Get-ChildItem -LiteralPath $destinationPath -Recurse -Force -Attributes ReparsePoint).Count) {
        throw 'Sprite output must not contain links or junctions'
    }
    $sprite = @(
        '<svg xmlns="http://www.w3.org/2000/svg">'
        '<!-- Generated by the Workbench icon asset builder. -->'
        foreach ($family in $generatedFamilies) {
            "<!-- Source: $($family.Assets.Runtime.Configuration.sourceUrl) -->"
            foreach ($iconName in $family.Assets.Runtime.RuntimeIconNames) { $family.Assets.Symbols[$iconName] }
        }
        '</svg>'
    ) -join "`n"
    $document = [xml]$sprite
    $ids = @($document.SelectNodes('//*[@id]') | ForEach-Object { $_.GetAttribute('id') })
    if (@($ids | Sort-Object -Unique -CaseSensitive).Count -ne $ids.Count) { throw 'The combined sprite contains duplicate SVG IDs' }
    foreach ($attribute in $document.SelectNodes('//@*')) {
        foreach ($reference in [regex]::Matches($attribute.Value, 'url\(#(?<id>[^)]+)\)')) {
            if ($reference.Groups['id'].Value -cnotin $ids) { throw 'The combined sprite contains an unresolved SVG fragment' }
        }
    }
    $stagingPath = Join-Path ([IO.Path]::GetTempPath()) ('hosted-sprite-' + [guid]::NewGuid().ToString('N'))
    try {
        foreach ($family in $generatedFamilies) {
            $runtime = $family.Assets.Runtime
            $legalDirectory = Join-Path $stagingPath "$($family.Name)/legal"
            $null = New-Item -ItemType Directory -Path $legalDirectory -Force
            foreach ($fileName in $runtime.RuntimeFiles) {
                Copy-Item -LiteralPath (Join-Path $runtime.Directory $fileName) -Destination (Join-Path $legalDirectory $fileName) -Force
            }
            if (-not $SkipPreviews) {
                $null = New-WorkbenchIconPreview -IconDirectory $runtime.Directory -FamilyName $runtime.Configuration.familyName -Commit $runtime.Configuration.revision -SymbolPrefix $runtime.Configuration.symbolPrefix -IconNames $runtime.PreviewIconNames -SymbolMarkup @($runtime.PreviewIconNames | ForEach-Object { $family.Assets.Symbols[$_] })
            }
        }
        [IO.File]::WriteAllText((Join-Path $stagingPath 'sprite.svg'), $sprite + "`n", [Text.UTF8Encoding]::new($false))
        Copy-WorkbenchRuntimeIconAssets -IconRoot $stagingPath -Destination $destinationPath -SourceRoot $IconRoot
    }
    finally {
        if (Test-Path -LiteralPath $stagingPath) { Remove-Item -LiteralPath $stagingPath -Recurse -Force }
    }
    $spritePath = Join-Path $destinationPath 'sprite.svg'
    [pscustomobject]@{ Status = 'generated'; IconCount = $symbolIds.Count; FamilyCount = $families.Count; SpritePath = $spritePath }
}

function Copy-WorkbenchRuntimeIconAssets {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string] $IconRoot,

        [Parameter(Mandatory)]
        [string] $Destination,

        [string] $SourceRoot = $PSScriptRoot
    )

    $assets = @(Get-WorkbenchRuntimeIconAssets -IconRoot $IconRoot -SourceRoot $SourceRoot)
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
