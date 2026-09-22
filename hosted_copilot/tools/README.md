# Hosted Toolkit Commands

Only the commands listed here are supported maintainer entry points. The four normal-operation commands remain at the tools root. Specialized catalog commands live beneath `commands/catalog/`.

Files beneath `internal/`, `modules/`, and `tests/` are implementation or validation details rather than an equivalent manual command surface. Reusable `.psm1` files live under `modules/`; `internal/` is reserved for implementation `.ps1` scripts. Retired migration and version 3 tools are preserved under `local-only-docs/obsolete-v3/`.

## Normal Operations

| Task | Command |
| --- | --- |
| Validate the complete Hosted Toolkit | `pwsh -NoProfile -File ./hosted_copilot/tools/Test-HostedRules.ps1` |
| Launch the Hosted Rule Workbench | `pwsh -NoProfile -File ./hosted_copilot/tools/Start-RuleWorkbench.ps1` |
| Rebuild semantic Workbench data | `pwsh -NoProfile -File ./hosted_copilot/tools/Start-RuleWorkbench.ps1 -Rebuild` |
| Plan or install the Hosted payload | `pwsh -NoProfile -File ./hosted_copilot/tools/Install-HostedRules.ps1` |
| Run or resume a controlled Hosted review | `pwsh -NoProfile -File ./hosted_copilot/tools/Invoke-HostedReview.ps1 -RepoDirectory <provider-fork> -CaseId <case-id>` |

Review the command help before supplying operation-specific parameters. Installation defaults to a dry run.

The normal Workbench command refreshes static UI assets, validates `%LOCALAPPDATA%\hosted-workbench\site\workbench-display.json`, and serves that last good display. It never runs source collection, assessment, or reconciliation. If no validated display exists yet, the command fails with an explicit instruction to run `-Rebuild`.

`-Rebuild` is the only normal operation that performs semantic work. It reuses validated per-source assessments from `%LOCALAPPDATA%\hosted-workbench\assessment-cache`, validated source-defined reconciliation batches from `%LOCALAPPDATA%\hosted-workbench\reconciliation-cache`, and compatible toolkit-managed artifacts from failed runs. Only changed semantic identities return to model evaluation. Reconciliation runs up to three cache misses concurrently, merges all cached, recovered, and evaluated results deterministically, and reports progress. Failed evaluator attempts retain their draft and validation reason. A successful rebuild schema-validates the new display before atomically replacing the last good display; collection, assessment, reconciliation, or validation failure leaves the previous display untouched. Cache, recovery, and concurrency parameters are diagnostic or controlled rebuild overrides, not UI-restart requirements.

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
