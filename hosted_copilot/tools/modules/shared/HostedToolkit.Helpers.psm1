Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function ConvertTo-UtcTimestamp {
    param([Parameter(Mandatory = $true)][object]$Value)

    try {
        if ($Value -is [datetimeoffset]) {
            $utcDateTime = ([datetimeoffset]$Value).UtcDateTime
        }
        elseif ($Value -is [datetime]) {
            $utcDateTime = ([datetime]$Value).ToUniversalTime()
        }
        else {
            $utcDateTime = [datetimeoffset]::Parse(
                [string]$Value,
                [Globalization.CultureInfo]::InvariantCulture,
                [Globalization.DateTimeStyles]::AllowWhiteSpaces
            ).UtcDateTime
        }
        return $utcDateTime.ToString('o', [Globalization.CultureInfo]::InvariantCulture)
    }
    catch {
        throw "Invalid timestamp: $Value"
    }
}

function Get-Sha256 {
    [CmdletBinding(DefaultParameterSetName = 'Content')]
    param(
        [Parameter(Mandatory = $true, ParameterSetName = 'Content')]
        [AllowEmptyString()]
        [string]$Content,

        [Parameter(Mandatory = $true, ParameterSetName = 'Bytes')]
        [AllowEmptyCollection()]
        [byte[]]$Bytes,

        [Parameter(Mandatory = $true, ParameterSetName = 'Path')]
        [string]$Path
    )

    if ($PSCmdlet.ParameterSetName -eq 'Content') {
        $Bytes = [Text.Encoding]::UTF8.GetBytes($Content)
    }
    elseif ($PSCmdlet.ParameterSetName -eq 'Path') {
        return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
    }

    return [Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($Bytes)).ToLowerInvariant()
}

function Get-FileSnapshot {
    param([Parameter(Mandatory = $true)][string]$Path)

    $stream = [IO.File]::Open($Path, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::None)
    try {
        $buffer = [IO.MemoryStream]::new()
        try {
            $stream.CopyTo($buffer)
            [byte[]]$bytes = $buffer.ToArray()
        }
        finally {
            $buffer.Dispose()
        }
    }
    finally {
        $stream.Dispose()
    }

    $offset = if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) { 3 } else { 0 }
    return [pscustomobject]@{
        Bytes = $bytes
        Content = [Text.UTF8Encoding]::new($false, $true).GetString($bytes, $offset, $bytes.Length - $offset)
        Sha256 = Get-Sha256 -Bytes $bytes
    }
}

function ConvertTo-OrdinalMap {
    param([Parameter(Mandatory = $true)][object]$Value)

    $valuesByName = @{}
    if ($Value -is [Collections.IDictionary]) {
        foreach ($key in $Value.Keys) {
            $valuesByName[[string]$key] = $Value[$key]
        }
    }
    else {
        foreach ($property in $Value.PSObject.Properties) {
            $valuesByName[[string]$property.Name] = $property.Value
        }
    }

    [string[]]$names = @($valuesByName.Keys)
    [Array]::Sort($names, [StringComparer]::Ordinal)
    $result = [ordered]@{}
    foreach ($name in $names) {
        $result[$name] = $valuesByName[$name]
    }
    return $result
}

function ConvertTo-JsonSnapshotBytes {
    param(
        [Parameter(Mandatory = $true)][object]$Value,
        [ValidateRange(1, 100)][int]$Depth = 40
    )

    return [Text.UTF8Encoding]::new($false).GetBytes(($Value | ConvertTo-Json -Depth $Depth) + "`n")
}

function Get-JsonSnapshotSha256 {
    param(
        [Parameter(Mandatory = $true)][object]$Value,
        [ValidateRange(1, 100)][int]$Depth = 40
    )

    [byte[]]$bytes = ConvertTo-JsonSnapshotBytes -Value $Value -Depth $Depth
    return Get-Sha256 -Bytes $bytes
}

function Write-JsonSnapshot {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][object]$Value,
        [ValidateRange(1, 100)][int]$Depth = 40
    )

    $directory = Split-Path -Parent $Path
    if (-not (Test-Path -LiteralPath $directory -PathType Container)) {
        $null = New-Item -ItemType Directory -Path $directory -Force
    }
    [byte[]]$bytes = ConvertTo-JsonSnapshotBytes -Value $Value -Depth $Depth
    $temporaryPath = Join-Path $directory ('.' + [IO.Path]::GetFileName($Path) + '.' + [guid]::NewGuid().ToString('N') + '.tmp')
    try {
        [IO.File]::WriteAllBytes($temporaryPath, $bytes)
        [IO.File]::Move($temporaryPath, $Path, $false)
    }
    catch [IO.IOException] {
        if (Test-Path -LiteralPath $Path) {
            throw "JSON snapshot output already exists: $Path"
        }
        throw
    }
    finally {
        Remove-Item -LiteralPath $temporaryPath -Force -ErrorAction SilentlyContinue
    }

    return [pscustomobject]@{
        Path = $Path
        Sha256 = Get-Sha256 -Bytes $bytes
        ByteCount = $bytes.Length
    }
}

function Get-BehaviorManifestSha256 {
    param(
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][string[]]$IdentityValues,
        [Parameter(Mandatory = $true)][string[]]$BehaviorFiles,
        [Parameter(Mandatory = $true)][string]$RepositoryRoot,
        [Parameter(Mandatory = $true)][string]$ManifestName
    )

    [string[]]$sortedFiles = @($BehaviorFiles)
    [Array]::Sort($sortedFiles, [StringComparer]::Ordinal)
    if (@(Compare-Object $BehaviorFiles $sortedFiles -SyncWindow 0).Count -ne 0) {
        throw "$ManifestName behaviorFiles must use ordinal sort order"
    }
    if (@($BehaviorFiles | Group-Object -CaseSensitive | Where-Object Count -gt 1).Count -ne 0) {
        throw "$ManifestName behaviorFiles must not contain duplicates"
    }

    $builder = [Text.StringBuilder]::new()
    foreach ($identityValue in $IdentityValues) {
        $null = $builder.Append($identityValue).Append([char]0)
    }
    foreach ($relativePath in $sortedFiles) {
        if ([IO.Path]::IsPathRooted($relativePath) -or $relativePath.Contains('\') -or @($relativePath -split '/' | Where-Object { $_ -in @('', '.', '..') }).Count -ne 0) {
            throw "$ManifestName behavior file is not repository-relative: $relativePath"
        }
        $fullPath = [IO.Path]::GetFullPath((Join-Path $RepositoryRoot $relativePath))
        if (-not (Test-Path -LiteralPath $fullPath -PathType Leaf)) {
            throw "$ManifestName behavior file was not found: $relativePath"
        }
        $null = $builder.Append($relativePath).Append([char]0).Append((Get-Sha256 -Path $fullPath)).Append([char]0)
    }
    return Get-Sha256 -Content $builder.ToString()
}

Export-ModuleMember -Function ConvertTo-UtcTimestamp, Get-Sha256, Get-FileSnapshot, ConvertTo-OrdinalMap, Get-JsonSnapshotSha256, Write-JsonSnapshot, Get-BehaviorManifestSha256
