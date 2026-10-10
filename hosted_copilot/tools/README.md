# Hosted Toolkit Commands

Only the commands listed here are supported maintainer entry points. The four normal-operation commands remain at the tools root. Specialized catalog commands live beneath `commands/catalog/`.

Files beneath `internal/`, `modules/`, and `tests/` are implementation or validation details rather than an equivalent manual command surface. Reusable `.psm1` files live under `modules/`; `internal/` is reserved for implementation `.ps1` scripts. Shared cross-workflow primitives live under `modules/shared/`, review compatibility and workflow composition live under `modules/review/`, source-format parsers live under `modules/source-parsers/`, and Workbench runtime composition lives under `modules/workbench/`. Retired migration and version 3 tools are preserved under `local-only-docs/obsolete-v3/`.

`modules/shared/HostedGitHub.Helpers.psm1` exclusively owns GitHub CLI process execution and reusable API, CODEOWNERS, and fork-target primitives. Workbench, review, and source-collection consumers retain their domain-specific policy but must delegate authenticated GitHub CLI execution to that shared module.

## Normal Operations

| Task | Command |
| --- | --- |
| Validate the complete Hosted Toolkit | `pwsh -NoProfile -File ./hosted_copilot/tools/Test-HostedRules.ps1` |
| Launch the Hosted Rule Workbench | `pwsh -NoProfile -File ./hosted_copilot/tools/Start-RuleWorkbench.ps1` |
| Plan or install the Hosted payload | `pwsh -NoProfile -File ./hosted_copilot/tools/Install-HostedRules.ps1` |
| Run or resume a controlled Hosted review | `pwsh -NoProfile -File ./hosted_copilot/tools/Invoke-HostedReview.ps1 -RepoDirectory <provider-fork> -CaseId <case-id>` |

Review the command help before supplying operation-specific parameters. Installation defaults to a dry run.

Ordinary Workbench launch refreshes static assets, validates the live GitHub identity, local CODEOWNERS membership, writable fork, and synchronization status, and serves the last jointly validated display and Rule Issues artifacts without source collection or semantic work. Run `pwsh -NoProfile -File ./hosted_copilot/tools/Start-RuleWorkbench.ps1 -Rebuild` when current sources must be collected and the staged artifacts regenerated. Assessment results are stored in one locked `%LOCALAPPDATA%\hosted-workbench\assessment-cache\assessment-cache.json` ledger. Reconciliation results are stored in one locked `%LOCALAPPDATA%\hosted-workbench\reconciliation-cache\reconciliation-cache.json` ledger. Source IDs locate ledger entries; only source file content hashes control semantic reuse. The staged display remains presentation state rather than semantic cache evidence or a freshness authority.

During an explicit rebuild, assessment and reconciliation run up to three cache misses concurrently, merge cached, recovered, and evaluated results deterministically, and report progress. Each ledger update takes a short exclusive lock, rereads and merges the latest entries, then atomically replaces the ledger so concurrent Workbench processes cannot lose completed results. Failed evaluator attempts retain their draft and validation reason. Collection, assessment, reconciliation, or validation failure leaves the previous staged artifacts untouched.

## Catalog Maintenance

| Task | Command |
| --- | --- |
| Check generated instruction freshness | `pwsh -NoProfile -File ./hosted_copilot/tools/commands/catalog/Generate-Instructions.ps1` |
| Regenerate approved instruction changes | `pwsh -NoProfile -File ./hosted_copilot/tools/commands/catalog/Generate-Instructions.ps1 -Write` |
| Audit live upstream source drift | `pwsh -NoProfile -File ./hosted_copilot/tools/commands/catalog/Test-UpstreamSources.ps1 -FailOnDrift` |

Live upstream drift is an explicit maintainer audit and is not a deterministic required-CI input.

## Hosted Review

Use [Hosted Review](../docs/HOSTED_REVIEW.md) for the complete local workflow. `Invoke-HostedReview.ps1` creates or resumes a controlled review, exits while GitHub reviews are pending, guides local maintainer adjudication, validates the result, and performs cleanup only with `-Cleanup`.

Review branch topology, evidence capture, and result construction are internal implementation details. Do not invoke scripts beneath `internal/review/` directly.

## Focused Development

Focused tests are invoked while changing their owning implementation and are also composed by `Test-HostedRules.ps1`. They are not normal maintainer operations. Migration-only tools exist solely to prove and complete the version 4 cutover and are removed from normal validation before archival.
