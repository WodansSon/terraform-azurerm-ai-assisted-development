param(
    [Parameter(Mandatory)]
    [string] $Id,

    [string] $Title,

    [ValidateSet("code-review-local-changes", "code-review-committed-changes", "code-review-docs", "docs-writer", "resource-implementation", "acceptance-testing")]
    [string] $Task = "resource-implementation",

    [string] $SpecDirectory = (Join-Path $PSScriptRoot "test"),

    [switch] $Force
)

$ErrorActionPreference = "Stop"

. (Join-Path $PSScriptRoot "test/TestSpecDefinition.ps1")

$definition = Get-RegressionTestDefinition

function Initialize-Directory {
    param([string] $Path)

    if (-not (Test-Path -LiteralPath $Path)) {
        New-Item -ItemType Directory -Path $Path -Force | Out-Null
    }
}

function Convert-ToKebabCase {
    param([string] $Value)

    $normalized = $Value.ToLowerInvariant()
    $normalized = [Regex]::Replace($normalized, "[^a-z0-9]+", "-")
    return $normalized.Trim('-')
}

$Id = Convert-ToKebabCase -Value $Id
if ([string]::IsNullOrWhiteSpace($Id)) {
    throw "id must contain at least one alphanumeric character"
}

if ([string]::IsNullOrWhiteSpace($Title)) {
    $Title = "Replace with a short human-readable benchmark title"
}

Assert-RegressionTestAllowedValue -Definition $definition -EnumName "task" -Value $Task -Context "task"

Initialize-Directory -Path $SpecDirectory

$specPath = Join-Path $SpecDirectory ($Id + ".hcl")
if ((Test-Path -LiteralPath $specPath) -and -not $Force) {
    throw "spec already exists: $specPath"
}

$content = @(
    ('{0} "{1}" "{2}" {{' -f $definition.defaultRootBlock, $Id, $definition.defaultRootSecondaryLabel),
    ('  title       = "{0}"' -f $Title),
    '',
    '  test_case {',
    ('    task        = "{0}"' -f $Task),
    '    source_kind = "real-pr"',
    '    case_status = "planned"',
    '    notes       = "Replace with optional scope notes."',
    '',
    '    changed_files = [',
    '      "path/to/changed/file.ext",',
    '    ]',
    '',
    '    config {',
    '      resource "azurerm_example_resource" "test" {',
    '        name = "example"',
    '      }',
    '    }',
    '  }',
    '',
    '  rules {',
    '    description           = "Replace with a plain-language scenario description."',
    '    notes                 = "Replace with optional maintainer notes."',
    '    include_sample_output = false',
    '',
    '    must_catch {',
    '      description = "Replace with the primary behavior or issue the harness should catch."',
    '      severity    = "medium"',
    '      file        = "path/to/changed/file.ext"',
    '    }',
    '',
    '    must_not_flag {',
    '      description = "Replace with a behavior the harness must not flag."',
    '    }',
    '  }',
    '}'
)

$content | Set-Content -LiteralPath $specPath

Write-Output "Regression test HCL scaffold created"
Write-Output "  Spec File        : $specPath"
Write-Output ""
Write-Output "Next step:"
Write-Output "  Edit the HCL file, then run build-regression-test.ps1 -SpecPath $specPath"
