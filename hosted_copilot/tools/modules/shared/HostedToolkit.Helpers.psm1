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

function Invoke-WithExclusiveFileLock {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][scriptblock]$Operation,
        [object[]]$ArgumentList = @(),
        [ValidateRange(1, 300000)][int]$TimeoutMilliseconds = 30000
    )

    $directory = Split-Path -Parent $Path
    if (-not (Test-Path -LiteralPath $directory -PathType Container)) {
        $null = New-Item -ItemType Directory -Path $directory -Force
    }
    $stopwatch = [Diagnostics.Stopwatch]::StartNew()
    $lockStream = $null
    while ($null -eq $lockStream) {
        try {
            $lockStream = [IO.File]::Open($Path, [IO.FileMode]::OpenOrCreate, [IO.FileAccess]::ReadWrite, [IO.FileShare]::None)
        }
        catch [IO.IOException] {
            if ($stopwatch.ElapsedMilliseconds -ge $TimeoutMilliseconds) {
                throw "Timed out waiting for exclusive file lock: $Path"
            }
            [Threading.Thread]::Sleep(25)
        }
    }
    try {
        return & $Operation @ArgumentList
    }
    finally {
        $lockStream.Dispose()
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

function Format-ElapsedDuration {
    param([Parameter(Mandatory = $true)][long]$Milliseconds)

    $duration = [TimeSpan]::FromMilliseconds([Math]::Max(0, $Milliseconds))
    return '{0:00}:{1:00}:{2:00}' -f [Math]::Floor($duration.TotalHours), $duration.Minutes, $duration.Seconds
}

function Format-ByteSize {
    param([Parameter(Mandatory = $true)][long]$Bytes)

    if ($Bytes -ge 1MB) {
        return '{0:N1} MB' -f ($Bytes / 1MB)
    }
    return '{0:N0} KB' -f ($Bytes / 1KB)
}

function Format-IndentedDiagnostic {
    param(
        [Parameter(Mandatory = $true)][string]$Message,
        [string]$Label = 'Error:',
        [ValidateRange(40, 200)][int]$Width = 110,
        [ValidateRange(0, 10)][int]$IndentLevel = 2
    )

    $indent = '  ' * $IndentLevel
    $availableWidth = $Width - $indent.Length
    $words = @((($Label.Trim() + ' ' + (($Message -replace '\s+', ' ').Trim())).Trim()) -split ' ')
    $lines = [Collections.Generic.List[string]]::new()
    $line = ''
    foreach ($word in $words) {
        if ($line.Length -gt 0 -and ($line.Length + 1 + $word.Length) -gt $availableWidth) {
            $lines.Add($indent + $line)
            $line = $word
        }
        elseif ($line.Length -eq 0) {
            $line = $word
        }
        else {
            $line += ' ' + $word
        }
    }
    if ($line.Length -gt 0) {
        $lines.Add($indent + $line)
    }
    return $lines.ToArray()
}

function Get-EvaluatorFailureMessage {
    param(
        [Parameter(Mandatory = $true)][string]$EvaluatorName,
        [Parameter(Mandatory = $true)][int]$ExitCode,
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][object[]]$Output
    )

    [string[]]$outputLines = @($Output | ForEach-Object { ([string]$_).Trim() } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    $structuredMessages = [Collections.Generic.List[string]]::new()
    foreach ($line in $outputLines) {
        try {
            $event = $line | ConvertFrom-Json
            $eventMessages = [Collections.Generic.List[object]]::new()
            $messageProperty = $event.PSObject.Properties['message']
            if ($null -ne $messageProperty) {
                $eventMessages.Add($messageProperty.Value)
            }
            $errorProperty = $event.PSObject.Properties['error']
            if ($null -ne $errorProperty) {
                if ($errorProperty.Value -is [string]) {
                    $eventMessages.Add($errorProperty.Value)
                }
                elseif ($null -ne $errorProperty.Value -and $null -ne $errorProperty.Value.PSObject.Properties['message']) {
                    $eventMessages.Add($errorProperty.Value.PSObject.Properties['message'].Value)
                }
            }
            $dataProperty = $event.PSObject.Properties['data']
            if ($null -ne $dataProperty -and $null -ne $dataProperty.Value) {
                $dataMessageProperty = $dataProperty.Value.PSObject.Properties['message']
                if ($null -ne $dataMessageProperty) {
                    $eventMessages.Add($dataMessageProperty.Value)
                }
                $dataErrorProperty = $dataProperty.Value.PSObject.Properties['error']
                if ($null -ne $dataErrorProperty) {
                    if ($dataErrorProperty.Value -is [string]) {
                        $eventMessages.Add($dataErrorProperty.Value)
                    }
                    elseif ($null -ne $dataErrorProperty.Value -and $null -ne $dataErrorProperty.Value.PSObject.Properties['message']) {
                        $eventMessages.Add($dataErrorProperty.Value.PSObject.Properties['message'].Value)
                    }
                }
            }
            foreach ($message in $eventMessages) {
                if (-not [string]::IsNullOrWhiteSpace([string]$message)) {
                    $structuredMessages.Add(([string]$message).Trim())
                }
            }
        }
        catch {
        }
    }

    $detail = if ($structuredMessages.Count -gt 0) {
        @($structuredMessages | Select-Object -Unique) -join '; '
    }
    elseif ($outputLines.Count -gt 0) {
        $outputLines -join ' '
    }
    else {
        $null
    }
    $prefix = "$EvaluatorName exited with code $ExitCode"
    if ([string]::IsNullOrWhiteSpace($detail)) {
        return "$prefix without diagnostic output"
    }
    return "$prefix`: $detail"
}

function Get-EstimatedRemainingMilliseconds {
    param(
        [Parameter(Mandatory = $true)][long]$CompletedPayloadBytes,
        [Parameter(Mandatory = $true)][long]$CompletedElapsedMilliseconds,
        [Parameter(Mandatory = $true)][long]$RemainingPayloadBytes,
        [Parameter(Mandatory = $true)][int]$MaxParallelBatches,
        [Parameter(Mandatory = $true)][ValidateRange(1, 1000000)][int]$BootstrapBytesPerSecondPerWorker
    )

    if ($RemainingPayloadBytes -le 0) {
        return 0L
    }
    if ($CompletedPayloadBytes -le 0 -or $CompletedElapsedMilliseconds -le 0) {
        return [long][Math]::Ceiling(($RemainingPayloadBytes / ([double]$BootstrapBytesPerSecondPerWorker * [Math]::Max(1, $MaxParallelBatches))) * 1000)
    }
    $bytesPerMillisecondPerWorker = [double]$CompletedPayloadBytes / [double]$CompletedElapsedMilliseconds
    return [long][Math]::Ceiling($RemainingPayloadBytes / ($bytesPerMillisecondPerWorker * [Math]::Max(1, $MaxParallelBatches)))
}

Export-ModuleMember -Function ConvertTo-UtcTimestamp, Get-Sha256, Get-FileSnapshot, ConvertTo-OrdinalMap, Get-JsonSnapshotSha256, Write-JsonSnapshot, Invoke-WithExclusiveFileLock, Get-BehaviorManifestSha256, Format-ElapsedDuration, Format-ByteSize, Format-IndentedDiagnostic, Get-EvaluatorFailureMessage, Get-EstimatedRemainingMilliseconds
