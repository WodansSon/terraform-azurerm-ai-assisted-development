Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Invoke-PrivacyGit {
    param([string]$RepositoryRoot, [string[]]$Arguments)

    $git = Get-Command git -CommandType Application -ErrorAction Stop
    $start = [Diagnostics.ProcessStartInfo]::new($git.Source)
    $start.UseShellExecute = $false
    $start.RedirectStandardOutput = $true
    $start.RedirectStandardError = $true
    foreach ($name in @($start.Environment.Keys | Where-Object { $_ -like 'GIT_TRACE*' -or $_ -eq 'GIT_CURL_VERBOSE' })) {
        $null = $start.Environment.Remove($name)
    }
    foreach ($argument in @('-C', $RepositoryRoot) + $Arguments) { $start.ArgumentList.Add($argument) }
    $process = [Diagnostics.Process]::new()
    $process.StartInfo = $start
    $buffer = [IO.MemoryStream]::new()
    try {
        $null = $process.Start()
        $stdout = $process.StandardOutput.BaseStream.CopyToAsync($buffer)
        $stderr = $process.StandardError.ReadToEndAsync()
        $process.WaitForExit()
        $null = $stdout.GetAwaiter().GetResult()
        $diagnostic = $stderr.GetAwaiter().GetResult()
        if ($process.ExitCode -ne 0 -or -not [string]::IsNullOrWhiteSpace($diagnostic)) {
            throw 'Privacy Git inspection failed; raw diagnostics omitted'
        }
        return ,$buffer.ToArray()
    } finally {
        $buffer.Dispose()
        $process.Dispose()
    }
}

function Get-PrivacyRules {
    param([string[]]$PrivateIdentifier = @())

    $rules = [Collections.Generic.List[object]]::new()
    $definitions = [ordered]@{
        'personal-home-path' = '(?i)(?:\b[a-z]:[\\/]+(?:Users|Documents and Settings)[\\/]+|/(?:Users|home)/)(?![<{$%])[^\s\\/<>`"'']+'
        'private-workspace-artifact' = '(?i)\bhosted-db-v1-measured-[a-f0-9]{32}\b'
        'private-key' = '-----BEGIN (?:[A-Z]+ )?PRIVATE KEY-----'
        'github-credential' = '\b(?:gh[pousr]_[A-Za-z0-9]{30,}|github_pat_[A-Za-z0-9_]{50,})\b'
        'cloud-access-key' = '\bAKIA[0-9A-Z]{16}\b'
        'personal-email' = '(?i)\b[A-Z0-9._%+-]+@[A-Z0-9.-]+\.[A-Z]{2,}\b'
    }
    foreach ($definition in $definitions.GetEnumerator()) {
        $rules.Add([pscustomobject]@{ code = $definition.Key; expression = [regex]::new($definition.Value, [Text.RegularExpressions.RegexOptions]::CultureInvariant, [TimeSpan]::FromSeconds(2)) })
    }
    foreach ($identifier in $PrivateIdentifier | Select-Object -Unique) {
        if ([string]::IsNullOrWhiteSpace($identifier)) { throw 'Private identifiers must be nonempty' }
        $rules.Add([pscustomobject]@{ code = 'private-identifier'; expression = [regex]::new('(?i)(?<![A-Z0-9_])' + [regex]::Escape($identifier) + '(?![A-Z0-9_])',
            [Text.RegularExpressions.RegexOptions]::CultureInvariant, [TimeSpan]::FromSeconds(2)) })
    }
    return $rules.ToArray()
}

function Get-PrivacySafePath {
    param([string]$Path, [object[]]$Rules)

    $safe = $Path
    foreach ($rule in $Rules) { $safe = $rule.expression.Replace($safe, '[REDACTED]') }
    return [regex]::Replace($safe, '[\x00-\x1f\x7f]', [Text.RegularExpressions.MatchEvaluator]{
        param($match)
        return '\u{0:X4}' -f [int][char]$match.Value
    })
}

function Test-PrivacyRuleMatch {
    param([object]$Rule, [string]$Text)

    if (-not $Rule.expression.IsMatch($Text)) { return $false }
    if ($Rule.code -ceq 'personal-home-path') {
        foreach ($match in $Rule.expression.Matches($Text)) {
            $segment = ($match.Value -split '[\\/]')[-1]
            if ($segment -ine 'example' -and $segment -cne '...') { return $true }
        }
        return $false
    }
    if ($Rule.code -cne 'personal-email') { return $true }
    foreach ($match in $Rule.expression.Matches($Text)) {
        try { $domain = [Net.Mail.MailAddress]::new($match.Value).Host.ToLowerInvariant() }
        catch { return $true }
        $synthetic = $false
        foreach ($suffix in @('example', 'invalid', 'test', 'example.com', 'example.org', 'example.net')) {
            if ($domain -ceq $suffix -or $domain.EndsWith('.' + $suffix, [StringComparison]::Ordinal)) { $synthetic = $true; break }
        }
        if (-not $synthetic) { return $true }
    }
    return $false
}

function Find-PrivacyText {
    param([string]$Text, [string]$Path, [object[]]$Rules, [string]$Revision = '')

    $safePath = Get-PrivacySafePath -Path $Path -Rules $Rules
    $lineNumber = 0
    foreach ($line in $Text -split "`n") {
        $lineNumber += 1
        foreach ($rule in $Rules) {
            if (Test-PrivacyRuleMatch -Rule $rule -Text $line) {
                [pscustomobject]@{ rule = $rule.code; path = $safePath; line = $lineNumber; revision = $Revision }
            }
        }
    }
    foreach ($rule in $Rules) {
        if (Test-PrivacyRuleMatch -Rule $rule -Text $Path) {
            [pscustomobject]@{ rule = $rule.code; path = $safePath; line = 0; revision = $Revision }
        }
    }
}

function ConvertFrom-PrivacyBytes {
    param([byte[]]$Bytes)

    if ($Bytes.Length -ge 2 -and $Bytes[0] -eq 255 -and $Bytes[1] -eq 254) { return [Text.Encoding]::Unicode.GetString($Bytes) }
    if ($Bytes.Length -ge 2 -and $Bytes[0] -eq 254 -and $Bytes[1] -eq 255) { return [Text.Encoding]::BigEndianUnicode.GetString($Bytes) }
    return [Text.Encoding]::UTF8.GetString($Bytes)
}

function Invoke-RepositoryPrivacyScan {
    param(
        [string]$RepositoryRoot,
        [ValidateSet('Worktree', 'Staged', 'Outgoing')][string]$Scope = 'Worktree',
        [string[]]$PrivateIdentifier = @(),
        [string]$BaseRef = '',
        [string]$HeadRef = 'HEAD'
    )

    $root = [IO.Path]::GetFullPath($RepositoryRoot)
    $root = [Text.UTF8Encoding]::new($false, $true).GetString((Invoke-PrivacyGit -RepositoryRoot $root -Arguments @('rev-parse', '--show-toplevel'))).Trim()
    $root = [IO.Path]::GetFullPath($root)
    $rules = @(Get-PrivacyRules -PrivateIdentifier $PrivateIdentifier)
    if ($Scope -eq 'Outgoing') {
        if ([string]::IsNullOrWhiteSpace($BaseRef)) { throw 'Outgoing inspection requires an explicit baseline' }
        return Invoke-OutgoingPrivacyScan -RepositoryRoot $root -Rules $rules -BaseRef $BaseRef -HeadRef $HeadRef
    }
    if ($BaseRef -ne '' -or $HeadRef -cne 'HEAD') { throw 'Commit references require Outgoing scope' }
    if ($Scope -eq 'Staged') {
        $unmerged = Invoke-PrivacyGit -RepositoryRoot $root -Arguments @('ls-files', '-z', '--unmerged')
        if ($unmerged.Length -gt 0) { throw 'Privacy inspection refuses an unresolved index' }
    }
    $arguments = if ($Scope -eq 'Staged') { @('diff', '--cached', '--name-only', '-z', '--diff-filter=ACMRT') } else { @('ls-files', '-z', '--cached', '--others', '--exclude-standard') }
    $listing = [Text.UTF8Encoding]::new($false, $true).GetString((Invoke-PrivacyGit -RepositoryRoot $root -Arguments $arguments))
    $paths = @($listing.Split([char]0, [StringSplitOptions]::RemoveEmptyEntries) | Select-Object -Unique)
    $deleted = @{}
    if ($Scope -eq 'Worktree') {
        $deletedListing = [Text.UTF8Encoding]::new($false, $true).GetString((Invoke-PrivacyGit -RepositoryRoot $root -Arguments @('ls-files', '-z', '--deleted')))
        foreach ($path in $deletedListing.Split([char]0, [StringSplitOptions]::RemoveEmptyEntries)) { $deleted[$path] = $true }
    }
    $findings = [Collections.Generic.List[object]]::new()
    $files = 0
    foreach ($path in $paths) {
        if ($Scope -eq 'Staged') {
            $bytes = Invoke-PrivacyGit -RepositoryRoot $root -Arguments @('cat-file', 'blob', (':' + $path))
        } else {
            if ($deleted.ContainsKey($path)) { continue }
            $fullPath = [IO.Path]::GetFullPath((Join-Path $root $path))
            $relative = [IO.Path]::GetRelativePath($root, $fullPath)
            if ($relative -eq '..' -or $relative.StartsWith('..' + [IO.Path]::DirectorySeparatorChar)) { throw 'Worktree path escaped repository boundary' }
            $entry = Get-Item -LiteralPath $fullPath -Force -ErrorAction Stop
            while ($entry.FullName -ne $root) {
                if (($entry.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw 'Privacy inspection refuses linked worktree paths' }
                $entry = Get-Item -LiteralPath (Split-Path -Parent $entry.FullName) -Force -ErrorAction Stop
            }
            $bytes = [IO.File]::ReadAllBytes($fullPath)
        }
        foreach ($finding in @(Find-PrivacyText -Text (ConvertFrom-PrivacyBytes -Bytes $bytes) -Path $path -Rules $rules)) { $findings.Add($finding) }
        $files += 1
    }
    return [pscustomobject]@{ scope = $Scope; files = $files; revisions = 0; baseline = $null; head = $null; findings = $findings.ToArray() }
}

function Resolve-PrivacyCommit {
    param([string]$RepositoryRoot, [string]$Reference)

    $commit = [Text.Encoding]::ASCII.GetString((Invoke-PrivacyGit -RepositoryRoot $RepositoryRoot -Arguments @('rev-parse', '--verify', '--end-of-options', ($Reference + '^{commit}')))).Trim()
    if ($commit -cnotmatch '^(?:[a-f0-9]{40}|[a-f0-9]{64})$') { throw 'Git commit identity could not be verified' }
    return $commit
}

function Invoke-OutgoingPrivacyScan {
    param([string]$RepositoryRoot, [object[]]$Rules, [string]$BaseRef, [string]$HeadRef)

    $head = Resolve-PrivacyCommit -RepositoryRoot $RepositoryRoot -Reference $HeadRef
    $baseline = if ($BaseRef -cmatch '^(?:0{40}|0{64})$') { $null } else { Resolve-PrivacyCommit -RepositoryRoot $RepositoryRoot -Reference $BaseRef }
    $range = if ($null -eq $baseline) { $head } else { $baseline + '..' + $head }
    $listing = [Text.Encoding]::ASCII.GetString((Invoke-PrivacyGit -RepositoryRoot $RepositoryRoot -Arguments @('rev-list', '--reverse', $range)))
    $commits = @($listing -split "`n" | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | ForEach-Object { $_.Trim() })
    $findings = [Collections.Generic.List[object]]::new()
    $blobCache = @{}
    $files = 0
    foreach ($commit in $commits) {
        if ($commit -cnotmatch '^(?:[a-f0-9]{40}|[a-f0-9]{64})$') { throw 'Outgoing commit list was invalid' }
        $message = ConvertFrom-PrivacyBytes -Bytes (Invoke-PrivacyGit -RepositoryRoot $RepositoryRoot -Arguments @('show', '-s', '--format=%B', $commit))
        foreach ($match in @(Find-PrivacyText -Text $message -Path '[commit-message]' -Rules $Rules -Revision $commit)) { $findings.Add($match) }
        $tree = [Text.UTF8Encoding]::new($false, $true).GetString((Invoke-PrivacyGit -RepositoryRoot $RepositoryRoot -Arguments @('ls-tree', '-r', '-z', $commit)))
        foreach ($entry in $tree.Split([char]0, [StringSplitOptions]::RemoveEmptyEntries)) {
            $parsed = [regex]::Match($entry, '\A(?<mode>[0-9]{6}) (?<type>blob|commit) (?<identity>[a-f0-9]{40}|[a-f0-9]{64})\t(?<path>[\s\S]+)\z')
            if (-not $parsed.Success -or $parsed.Groups['type'].Value -cne 'blob') { throw 'An outgoing tree entry requires separate inspection' }
            $identity = $parsed.Groups['identity'].Value
            $path = $parsed.Groups['path'].Value
            if (-not $blobCache.ContainsKey($identity)) {
                $bytes = Invoke-PrivacyGit -RepositoryRoot $RepositoryRoot -Arguments @('cat-file', 'blob', $identity)
                $blobCache[$identity] = @(Find-PrivacyText -Text (ConvertFrom-PrivacyBytes -Bytes $bytes) -Path '' -Rules $Rules)
            }
            $safePath = Get-PrivacySafePath -Path $path -Rules $Rules
            foreach ($match in $blobCache[$identity]) {
                $findings.Add([pscustomobject]@{ rule = $match.rule; path = $safePath; line = $match.line; revision = $commit })
            }
            foreach ($match in @(Find-PrivacyText -Text '' -Path $path -Rules $Rules -Revision $commit)) { $findings.Add($match) }
            $files += 1
        }
    }
    return [pscustomobject]@{ scope = 'Outgoing'; files = $files; revisions = $commits.Count; baseline = $baseline; head = $head; findings = $findings.ToArray() }
}

Export-ModuleMember -Function Get-PrivacyRules, Find-PrivacyText, Invoke-RepositoryPrivacyScan
