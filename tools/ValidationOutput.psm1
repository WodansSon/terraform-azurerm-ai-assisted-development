Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Write-ValidationSectionHeader {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Title
    )

    $separator = '-' * 51

    Write-Output ''
    Write-Output $separator
    Write-Output $Title.ToUpperInvariant()
    Write-Output $separator
    Write-Output ''
}

function Format-ValidationStatusLine {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Status,

        [Parameter(Mandatory = $true)]
        [string]$Name,

        [Parameter(Mandatory = $true)]
        [string]$Detail,

        [ValidateRange(1, 200)]
        [int]$NameWidth = 30,

        [Nullable[int]]$AlignmentWidth,

        [switch]$Child,

        [ValidateRange(1, 10)]
        [int]$Level = 1
    )

    if (-not $Child -and $PSBoundParameters.ContainsKey('Level')) {
        throw 'Validation nesting levels require the Child switch.'
    }
    if ($null -eq $AlignmentWidth) { $AlignmentWidth = $NameWidth }
    $padding = if ($Child) { 2 * $Level } else { 0 }
    $NameWidth = $AlignmentWidth - $padding
    if ($AlignmentWidth -gt 200 -or $NameWidth -lt 1) {
        throw 'Validation alignment width must accommodate the declared nesting level.'
    }
    $statusLabel = "[{0}]" -f $Status.ToUpperInvariant()
    $indent = ' ' * $padding

    return ("{0}{1,-10} {2,-$NameWidth} : {3}" -f $indent, $statusLabel, $Name, $Detail)
}

function Format-ValidationLifecycleLine {
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet('running', 'passed', 'failed', 'skipped')]
        [string]$Status,

        [Parameter(Mandatory = $true)]
        [string]$Name,

        [string]$Description,

        [Nullable[double]]$DurationSeconds,

        [string]$ResultDetail,

        [Nullable[int]]$AlignmentWidth,

        [ValidateRange(1, 200)]
        [int]$NameWidth = 30,

        [switch]$Child,

        [ValidateRange(1, 10)]
        [int]$Level = 1
    )

    if (-not $Child -and $PSBoundParameters.ContainsKey('Level')) {
        throw 'Validation nesting levels require the Child switch.'
    }
    $indentLevel = if ($Child) { $Level } else { 0 }
    if ($null -eq $AlignmentWidth) { $AlignmentWidth = $NameWidth }
    $NameWidth = $AlignmentWidth - (2 * $indentLevel)
    if ($AlignmentWidth -gt 200 -or $NameWidth -lt 1 -or $Name.Length -gt $NameWidth) {
        throw 'Validation alignment width must accommodate the label and its declared nesting level.'
    }
    if ($Status -in @('passed', 'failed')) {
        if ($null -eq $DurationSeconds -or -not [double]::IsFinite($DurationSeconds) -or $DurationSeconds -lt 0) {
            throw 'Completed validation checks require a finite nonnegative duration.'
        }
        $detail = Format-ValidationDuration -DurationSeconds $DurationSeconds
        if (-not [string]::IsNullOrWhiteSpace($ResultDetail)) { $detail += " - $ResultDetail" }
    }
    else {
        if ($null -ne $DurationSeconds) { throw 'Running and skipped validation checks must not report an execution duration.' }
        $detail = $Description
    }
    if ([string]::IsNullOrWhiteSpace($detail)) {
        return ('  ' * $indentLevel) + ('[{0}]' -f $Status.ToUpperInvariant()).PadRight(10) + ' ' + $Name
    }
    $nesting = if ($Child) { @{ Child = $true; Level = $Level } } else { @{} }
    return Format-ValidationStatusLine -Status $Status -Name $Name -Detail $detail -AlignmentWidth $AlignmentWidth @nesting
}

function Get-ValidationNameWidth {
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [string[]]$Names,

        [ValidateRange(1, 200)]
        [int]$MinimumWidth = 1
    )

    $longestNameWidth = @($Names | ForEach-Object { $_.Length } | Measure-Object -Maximum)[0].Maximum
    return [Math]::Max($MinimumWidth, [int]$longestNameWidth)
}

function Add-ValidationIndent {
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string]$Line,

        [ValidateRange(0, 10)]
        [int]$IndentLevel = 1
    )

    return (('  ' * $IndentLevel) + $Line)
}

function Format-ValidationDuration {
    param(
        [Parameter(Mandatory = $true)]
        [double]$DurationSeconds
    )

    return ("{0:0.##}s" -f $DurationSeconds)
}

function Write-ValidationSummary {
    param(
        [Parameter(Mandatory = $true)]
        [System.Collections.IDictionary]$Fields
    )

    $labelWidth = @($Fields.Keys | ForEach-Object { ([string]$_).Length } | Measure-Object -Maximum)[0].Maximum
    foreach ($entry in $Fields.GetEnumerator()) {
        Write-Output ("  {0,-$labelWidth} : {1}" -f $entry.Key, $entry.Value)
    }
}

function Write-ValidationStatusTable {
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [object[]]$Rows,

        [string]$NameHeader = 'CHECK',

        [string]$NameProperty = 'name',

        [string]$StatusProperty = 'status',

        [string]$DurationProperty = 'durationSeconds',

        [int]$NameWidth = 32,

        [switch]$IncludeDetail,

        [string]$DetailProperty = 'detail'
    )

    $names = @($NameHeader.ToUpperInvariant()) + @($Rows | ForEach-Object { [string]$_.$NameProperty })
    $NameWidth = [Math]::Max($NameWidth, (Get-ValidationNameWidth -Names $names))
    Write-Output ("  {0,-$NameWidth} {1,-10} {2,10}" -f $NameHeader.ToUpperInvariant(), 'STATUS', 'DURATION')
    Write-Output ("  {0,-$NameWidth} {1,-10} {2,10}" -f ('-' * $NameWidth), ('-' * 10), ('-' * 10))
    foreach ($row in $Rows) {
        $name = [string]$row.$NameProperty
        $status = ([string]$row.$StatusProperty).ToUpperInvariant()
        $duration = Format-ValidationDuration -DurationSeconds $row.$DurationProperty
        Write-Output ("  {0,-$NameWidth} {1,-10} {2,10}" -f $name, $status, $duration)
        if ($IncludeDetail) {
            Write-Output ("    {0}" -f $row.$DetailProperty)
        }
    }
}

function Write-ValidationTwoColumnTable {
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [object[]]$Rows,

        [Parameter(Mandatory = $true)]
        [string]$FirstHeader,

        [Parameter(Mandatory = $true)]
        [string]$FirstProperty,

        [Parameter(Mandatory = $true)]
        [string]$SecondHeader,

        [Parameter(Mandatory = $true)]
        [string]$SecondProperty,

        [int]$FirstWidth = 24,

        [switch]$UppercaseFirst
    )

    Write-Output ("  {0,-$FirstWidth} {1}" -f $FirstHeader.ToUpperInvariant(), $SecondHeader.ToUpperInvariant())
    Write-Output ("  {0,-$FirstWidth} {1}" -f ('-' * $FirstWidth), ('-' * 24))
    foreach ($row in $Rows) {
        $firstValue = [string]$row.$FirstProperty
        if ($UppercaseFirst) {
            $firstValue = $firstValue.ToUpperInvariant()
        }
        Write-Output ("  {0,-$FirstWidth} {1}" -f $firstValue, $row.$SecondProperty)
    }
}

function Complete-ValidationTextOutput {
    Write-Output ''
}

Export-ModuleMember -Function @(
    'Write-ValidationSectionHeader',
    'Format-ValidationStatusLine',
    'Format-ValidationLifecycleLine',
    'Get-ValidationNameWidth',
    'Add-ValidationIndent',
    'Format-ValidationDuration',
    'Write-ValidationSummary',
    'Write-ValidationStatusTable',
    'Write-ValidationTwoColumnTable',
    'Complete-ValidationTextOutput'
)
