function Get-RegressionTestDefinition {
    return [ordered]@{
        rootBlocks = @("AccTest")
        defaultRootBlock = "AccTest"
        defaultRootSecondaryLabel = "basic"
        defaultRunName = "basic"
        enums = [ordered]@{
            task = @(
                "code-review-local-changes",
                "code-review-committed-changes",
                "code-review-docs",
                "docs-writer",
                "resource-implementation",
                "acceptance-testing"
            )
            sourceKind = @("real-pr", "local-diff", "synthetic")
            caseStatus = @("planned", "ready", "adjudicated", "retired")
            severity = @("low", "medium", "high")
        }
        allowedFields = [ordered]@{
            root = @("title")
            test_case = @("task", "source_kind", "case_status", "changed_files", "notes")
            config = @()
            rules = @("description", "notes", "include_sample_output")
            must_catch = @("description", "severity", "file")
            must_not_flag = @("description")
        }
    }
}

function Assert-RegressionTestAllowedValue {
    param(
        $Definition,
        [string] $EnumName,
        [string] $Value,
        [string] $Context
    )

    if ([string]::IsNullOrWhiteSpace($Value)) {
        return
    }

    if ($Definition.enums.Keys -notcontains $EnumName) {
        throw "unknown regression test enum '$EnumName'"
    }

    if ($Definition.enums[$EnumName] -notcontains $Value) {
        throw "$Context must be one of: $($Definition.enums[$EnumName] -join ', ')"
    }
}
