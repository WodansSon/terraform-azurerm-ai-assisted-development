[CmdletBinding()]
param(
    [ValidateSet('Text', 'Json')]
    [string]$OutputFormat = 'Text',

    [string[]]$MarkdownPaths = @('.github/pull_request_template.md')
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$validationOutputModulePath = Join-Path $PSScriptRoot 'ValidationOutput.psm1'
Import-Module -Name $validationOutputModulePath -Force

$repoRoot = Split-Path -Parent $PSScriptRoot
$issues = New-Object 'System.Collections.Generic.List[string]'
$validatedLinkCount = 0
$validatedFileCount = 0
$markdownLinkPattern = '!?\[[^\]]*\]\((?<target><[^>]+>|[^\s\)]+)'

foreach ($markdownPath in $MarkdownPaths) {
    $resolvedPath = if ([System.IO.Path]::IsPathRooted($markdownPath)) {
        $markdownPath
    }
    else {
        Join-Path $repoRoot $markdownPath
    }

    if (-not (Test-Path -LiteralPath $resolvedPath)) {
        $issues.Add("Markdown file was not found at $resolvedPath")
        continue
    }

    $validatedFileCount++
    $content = Get-Content -Raw -LiteralPath $resolvedPath
    $matches = [regex]::Matches($content, $markdownLinkPattern)

    foreach ($match in $matches) {
        $validatedLinkCount++
        $target = $match.Groups['target'].Value.Trim('<', '>')
        $lineNumber = [regex]::Matches($content.Substring(0, $match.Index), "`n").Count + 1

        if ($target.StartsWith('#')) {
            continue
        }

        $absoluteUri = $null
        if (-not [System.Uri]::TryCreate($target, [System.UriKind]::Absolute, [ref]$absoluteUri)) {
            $issues.Add(('{0}:{1}: copied Markdown links must use absolute HTTPS URLs, found `{2}`' -f $markdownPath, $lineNumber, $target))
            continue
        }

        if ($absoluteUri.Scheme -ne 'https') {
            $issues.Add(('{0}:{1}: copied Markdown links must use HTTPS, found `{2}`' -f $markdownPath, $lineNumber, $target))
            continue
        }

        if ($absoluteUri.Host -eq 'raw.githubusercontent.com') {
            $issues.Add(('{0}:{1}: human-facing repository links must use a GitHub `blob` or `tree` URL, found `{2}`' -f $markdownPath, $lineNumber, $target))
        }
    }
}

$result = [ordered]@{
    status = if ($issues.Count -eq 0) { 'passed' } else { 'failed' }
    markdownPaths = @($MarkdownPaths)
    validatedFileCount = $validatedFileCount
    validatedLinkCount = $validatedLinkCount
    issueCount = $issues.Count
    issues = @($issues)
}

if ($OutputFormat -eq 'Json') {
    $result | ConvertTo-Json -Depth 8
}
else {
    Write-ValidationSectionHeader -Title 'Copied Markdown link validation summary'
    Write-ValidationSummary -Fields ([ordered]@{
        Status = $result.status.ToUpperInvariant()
        'Files Checked' = $result.validatedFileCount
        'Links Checked' = $result.validatedLinkCount
        'Issue Count' = $result.issueCount
    })

    if ($issues.Count -gt 0) {
        Write-ValidationSectionHeader -Title 'Issues'
        foreach ($issue in $issues) {
            Write-Output ("  - {0}" -f $issue)
        }
    }
    Complete-ValidationTextOutput
}

if ($issues.Count -gt 0) {
    exit 1
}
