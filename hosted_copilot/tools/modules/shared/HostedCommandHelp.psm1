Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$commonParameterNames = @(
    'Debug',
    'ErrorAction',
    'ErrorVariable',
    'InformationAction',
    'InformationVariable',
    'OutBuffer',
    'OutVariable',
    'PipelineVariable',
    'ProgressAction',
    'Verbose',
    'WarningAction',
    'WarningVariable'
)

function ConvertTo-HostedHelpText {
    param([AllowNull()][object]$Value)

    if ($null -eq $Value) {
        return ''
    }
    if ($Value -is [string]) {
        return ([string]$Value).Trim()
    }
    $textProperty = $Value.PSObject.Properties['Text']
    if ($null -ne $textProperty) {
        return (ConvertTo-HostedHelpText -Value $textProperty.Value)
    }
    if ($Value -is [Collections.IEnumerable] -and $Value -isnot [Collections.IDictionary]) {
        return (@($Value | ForEach-Object { ConvertTo-HostedHelpText -Value $_ }) | Where-Object { $_ } | Join-String -Separator ' ').Trim()
    }
    return ([string]$Value).Trim()
}

function Format-HostedHelpParagraph {
    param(
        [Parameter(Mandatory = $true)][AllowEmptyString()][string]$Text,
        [Parameter(Mandatory = $true)][ValidateRange(40, 200)][int]$Width,
        [ValidateRange(0, 12)][int]$Indent = 2
    )

    $prefix = ' ' * $Indent
    $availableWidth = [Math]::Max(20, $Width - $Indent)
    $words = @(($Text -replace '\s+', ' ').Trim() -split ' ' | Where-Object { $_ })
    if ($words.Count -eq 0) {
        return @($prefix.TrimEnd())
    }
    $lines = [Collections.Generic.List[string]]::new()
    $line = ''
    foreach ($word in $words) {
        if ($line.Length -gt 0 -and ($line.Length + 1 + $word.Length) -gt $availableWidth) {
            $lines.Add($prefix + $line)
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
        $lines.Add($prefix + $line)
    }
    return $lines.ToArray()
}

function Get-HostedHelpTerminalWidth {
    try {
        return [Math]::Min(140, [Math]::Max(72, [int]$Host.UI.RawUI.WindowSize.Width))
    }
    catch {
        return 100
    }
}

function Get-HostedHelpParameterSyntax {
    param([Parameter(Mandatory = $true)][object]$Parameter)

    if ($Parameter.ParameterType -eq [Management.Automation.SwitchParameter]) {
        return ''
    }
    $validateSet = @($Parameter.Attributes | Where-Object { $_ -is [Management.Automation.ValidateSetAttribute] })
    if ($validateSet.Count -gt 0) {
        return '<' + ($validateSet[0].ValidValues -join '|') + '>'
    }
    if ($Parameter.ParameterType -in @([int], [long], [double], [decimal])) {
        return '<number>'
    }
    if ($Parameter.ParameterType -eq [string]) {
        return '<text>'
    }
    return '<' + $Parameter.ParameterType.Name + '>'
}

function Get-HostedHelpDefaultValue {
    param(
        [Parameter(Mandatory = $true)][object]$Parameter,
        [AllowNull()][object]$HelpParameter
    )

    if ($Parameter.ParameterType -eq [Management.Automation.SwitchParameter] -or $null -eq $HelpParameter) {
        return ''
    }
    $defaultValue = ConvertTo-HostedHelpText -Value $HelpParameter.DefaultValue
    if (-not $defaultValue -or $defaultValue -in @('None', '0', 'False') -or $defaultValue -match '[\(\)\[\]]') {
        return ''
    }
    return $defaultValue
}

function Format-HostedHelpParameterSyntax {
    param(
        [Parameter(Mandatory = $true)][string]$Syntax,
        [switch]$UseColor
    )

    if (-not $UseColor -or $PSStyle.OutputRendering -eq [Management.Automation.OutputRendering]::PlainText -or $Syntax -notmatch '^<(?<content>.*)>$') {
        return $Syntax
    }
    $formattedValues = @($matches['content'] -split '\|' | ForEach-Object { "$($PSStyle.Foreground.Yellow)$_$($PSStyle.Reset)" }) -join '|'
    return "<$formattedValues>"
}

function Format-HostedHelpSectionHeading {
    param(
        [Parameter(Mandatory = $true)][string]$Text,
        [switch]$UseColor
    )

    if ($UseColor -and $PSStyle.OutputRendering -ne [Management.Automation.OutputRendering]::PlainText) {
        return "$($PSStyle.Foreground.Yellow)$Text$($PSStyle.Reset)"
    }
    return $Text
}

function Format-HostedHelpArgument {
    param(
        [Parameter(Mandatory = $true)][string]$Text,
        [switch]$UseColor
    )

    if ($UseColor -and $PSStyle.OutputRendering -ne [Management.Automation.OutputRendering]::PlainText) {
        return "$($PSStyle.Foreground.Magenta)$Text$($PSStyle.Reset)"
    }
    return $Text
}

function Format-HostedHelpLiteral {
    param(
        [Parameter(Mandatory = $true)][string]$Text,
        [switch]$UseColor
    )

    if ($UseColor -and $PSStyle.OutputRendering -ne [Management.Automation.OutputRendering]::PlainText) {
        return "$($PSStyle.Foreground.Cyan)$Text$($PSStyle.Reset)"
    }
    return $Text
}

function Format-HostedHelpInlineLiterals {
    param(
        [Parameter(Mandatory = $true)][string]$Text,
        [switch]$UseColor
    )

    return [regex]::Replace($Text, '`(?<literal>[^`]+)`', {
            param($match)
            Format-HostedHelpLiteral -Text $match.Groups['literal'].Value -UseColor:$UseColor
        })
}

function Format-HostedHelpCommand {
    param(
        [Parameter(Mandatory = $true)][string]$Text,
        [switch]$UseColor
    )

    $scriptMatch = [regex]::Match($Text, '\.ps1(?=\s|$)', [Text.RegularExpressions.RegexOptions]::IgnoreCase)
    if (-not $scriptMatch.Success) {
        return (Format-HostedHelpLiteral -Text $Text -UseColor:$UseColor)
    }
    $commandPrefix = $Text.Substring(0, $scriptMatch.Index + $scriptMatch.Length)
    $scriptArguments = $Text.Substring($scriptMatch.Index + $scriptMatch.Length)
    $formattedArguments = [regex]::Replace($scriptArguments, '(?<!\S)-(?:\?|[A-Za-z][A-Za-z0-9]*)', {
            param($match)
            if ($UseColor -and $PSStyle.OutputRendering -ne [Management.Automation.OutputRendering]::PlainText) {
                return "$($PSStyle.Foreground.Magenta)$($match.Value)$($PSStyle.Reset)$($PSStyle.Foreground.Cyan)"
            }
            return $match.Value
        })
    return (Format-HostedHelpLiteral -Text ($commandPrefix + $formattedArguments) -UseColor:$UseColor)
}

function Get-HostedCommandHelp {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$ScriptPath,
        [string]$DisplayName,
        [Collections.IDictionary]$ParameterGroups,
        [switch]$UseColor,
        [ValidateRange(0, 200)][int]$Width = 0
    )

    $resolvedScriptPath = [IO.Path]::GetFullPath($ScriptPath)
    if (-not (Test-Path -LiteralPath $resolvedScriptPath -PathType Leaf)) {
        throw "Command help script was not found: $resolvedScriptPath"
    }
    if ([IO.Path]::GetExtension($resolvedScriptPath) -cne '.ps1') {
        throw "Command help requires a PowerShell script: $resolvedScriptPath"
    }
    if ($Width -eq 0) {
        $Width = Get-HostedHelpTerminalWidth
    }
    elseif ($Width -lt 40) {
        throw 'Command help width must be 0 for automatic sizing or at least 40.'
    }

    $command = Get-Command -Name $resolvedScriptPath -CommandType ExternalScript -ErrorAction Stop
    $help = Get-Help -Name $resolvedScriptPath -Full -ErrorAction Stop
    $lines = [Collections.Generic.List[string]]::new()
    $separator = '-' * [Math]::Min(51, $Width)
    if ([string]::IsNullOrWhiteSpace($DisplayName)) {
        $DisplayName = [IO.Path]::GetFileNameWithoutExtension($resolvedScriptPath)
    }

    $lines.Add('')
    $lines.Add($separator)
    $lines.Add($DisplayName.ToUpperInvariant())
    $lines.Add($separator)
    $lines.Add('')

    $synopsis = ConvertTo-HostedHelpText -Value $help.Synopsis
    if ($synopsis) {
        $lines.Add((Format-HostedHelpSectionHeading -Text 'SUMMARY' -UseColor:$UseColor))
        $lines.Add('')
        foreach ($line in @(Format-HostedHelpParagraph -Text $synopsis -Width $Width)) {
            $lines.Add($line)
        }
        $lines.Add('')
    }

    $examples = @($help.Examples.Example)
    if ($examples.Count -gt 0) {
        $lines.Add((Format-HostedHelpSectionHeading -Text 'USAGE' -UseColor:$UseColor))
        $lines.Add('')
        foreach ($example in $examples) {
            $codeLines = @((ConvertTo-HostedHelpText -Value $example.Code) -split '\r?\n' | Where-Object { $_ })
            $description = ConvertTo-HostedHelpText -Value $example.Remarks
            if ($codeLines.Count -gt 0) {
                $lines.Add('  ' + (Format-HostedHelpCommand -Text $codeLines[0].Trim() -UseColor:$UseColor))
            }
            if (-not $description -and $codeLines.Count -gt 1) {
                $description = ($codeLines[1..($codeLines.Count - 1)] -join ' ').Trim()
            }
            if ($description) {
                foreach ($line in @(Format-HostedHelpParagraph -Text $description -Width $Width -Indent 4)) {
                    $lines.Add($line)
                }
            }
            $lines.Add('')
        }
    }

    $helpParametersByName = @{}
    foreach ($helpParameter in @($help.Parameters.Parameter)) {
        $helpParametersByName[[string]$helpParameter.Name] = $helpParameter
    }
    $commandParameters = @($command.Parameters.Values | Where-Object { $_.Name -notin $commonParameterNames -and $_.Name -notin @('Help', 'Detailed') })
    $parametersByName = [Collections.Generic.Dictionary[string, object]]::new([StringComparer]::Ordinal)
    foreach ($parameter in $commandParameters) {
        $parametersByName.Add([string]$parameter.Name, $parameter)
    }
    if ($null -eq $ParameterGroups -or $ParameterGroups.Count -eq 0) {
        $ParameterGroups = [ordered]@{ 'Options' = @($commandParameters.Name | Sort-Object) }
    }
    $groupedParameterNames = [Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    foreach ($group in $ParameterGroups.GetEnumerator()) {
        if ([string]::IsNullOrWhiteSpace([string]$group.Key)) {
            throw 'Command help parameter group names must not be empty.'
        }
        $lines.Add((Format-HostedHelpSectionHeading -Text ([string]$group.Key).ToUpperInvariant() -UseColor:$UseColor))
        $lines.Add('')
        foreach ($parameterName in @($group.Value)) {
            if (-not $parametersByName.ContainsKey([string]$parameterName)) {
                throw "Command help group $($group.Key) references unknown parameter $parameterName."
            }
            if (-not $groupedParameterNames.Add([string]$parameterName)) {
                throw "Command help parameter $parameterName appears in more than one group."
            }
            $parameter = $parametersByName[[string]$parameterName]
            $helpParameter = $helpParametersByName[[string]$parameterName]
            $syntax = Get-HostedHelpParameterSyntax -Parameter $parameter
            $defaultValue = Get-HostedHelpDefaultValue -Parameter $parameter -HelpParameter $helpParameter
            $optionLine = '  ' + (Format-HostedHelpArgument -Text "-$parameterName" -UseColor:$UseColor)
            if ($syntax) {
                $optionLine += ' ' + (Format-HostedHelpParameterSyntax -Syntax $syntax -UseColor:$UseColor)
            }
            if ($defaultValue) {
                $optionLine += '  Default: ' + (Format-HostedHelpLiteral -Text $defaultValue -UseColor:$UseColor)
            }
            $lines.Add($optionLine)
            $description = if ($null -eq $helpParameter) { '' } else { ConvertTo-HostedHelpText -Value $helpParameter.Description }
            if ($description) {
                foreach ($line in @(Format-HostedHelpParagraph -Text $description -Width $Width -Indent 4)) {
                    $lines.Add((Format-HostedHelpInlineLiterals -Text $line -UseColor:$UseColor))
                }
            }
            $lines.Add('')
        }
    }
    $missingParameterNames = @($commandParameters.Name | Where-Object { -not $groupedParameterNames.Contains([string]$_) })
    if ($missingParameterNames.Count -gt 0) {
        throw "Command help groups do not include parameters: $($missingParameterNames -join ', ')."
    }

    $lines.Add((Format-HostedHelpSectionHeading -Text 'HELP' -UseColor:$UseColor))
    $lines.Add('')
    $helpArguments = @('-Help', '-h', '-Detailed') | ForEach-Object { Format-HostedHelpArgument -Text $_ -UseColor:$UseColor }
    $lines.Add('  ' + ($helpArguments -join ', ') + '  Show this curated reference.')

    $notes = ConvertTo-HostedHelpText -Value $help.AlertSet.Alert
    if ($notes) {
        $lines.Add('')
        $lines.Add((Format-HostedHelpSectionHeading -Text 'NOTES' -UseColor:$UseColor))
        $lines.Add('')
        foreach ($line in @(Format-HostedHelpParagraph -Text $notes -Width $Width)) {
            $lines.Add($line)
        }
    }

    $links = @($help.RelatedLinks.NavigationLink)
    if ($links.Count -gt 0) {
        $lines.Add('')
        $lines.Add((Format-HostedHelpSectionHeading -Text 'RELATED LINKS' -UseColor:$UseColor))
        $lines.Add('')
        foreach ($link in $links) {
            $linkTextProperty = $link.PSObject.Properties['LinkText']
            $uriProperty = $link.PSObject.Properties['Uri']
            $linkText = if ($null -eq $linkTextProperty) { '' } else { ConvertTo-HostedHelpText -Value $linkTextProperty.Value }
            $uri = if ($null -eq $uriProperty) { '' } else { ConvertTo-HostedHelpText -Value $uriProperty.Value }
            $lines.Add('  ' + (Format-HostedHelpLiteral -Text (@($linkText, $uri) | Where-Object { $_ } | Join-String -Separator ': ') -UseColor:$UseColor))
        }
        $lines.Add('')
    }

    return $lines.ToArray()
}

function Show-HostedCommandHelp {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$ScriptPath,
        [string]$DisplayName,
        [Collections.IDictionary]$ParameterGroups,
        [ValidateRange(0, 200)][int]$Width = 0
    )

    $useColor = $Host.UI.SupportsVirtualTerminal -and $PSStyle.OutputRendering -ne [Management.Automation.OutputRendering]::PlainText
    Get-HostedCommandHelp -ScriptPath $ScriptPath -DisplayName $DisplayName -ParameterGroups $ParameterGroups -UseColor:$useColor -Width $Width | Write-Output
}

Export-ModuleMember -Function @(
    'Get-HostedCommandHelp',
    'Show-HostedCommandHelp'
)
