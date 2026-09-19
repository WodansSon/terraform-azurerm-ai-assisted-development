# Hosted Toolkit Commands

Only the commands listed here are supported maintainer entry points. Files beneath the future `internal/`, `modules/`, `tests/`, `migration/`, and `legacy-v3/` folders are implementation or validation details rather than an equivalent manual command surface. Reusable `.psm1` files live under `modules/`; `internal/` is reserved for implementation `.ps1` scripts.

Phase 2.5 will leave only the three normal-operation commands at the tools root. Specialized public commands will move beneath `commands/catalog/` and `commands/review/`. Until that path-only checkpoint is complete, use the current command paths shown below.

## Normal Operations

| Task | Command |
| --- | --- |
| Validate the complete Hosted Toolkit | `pwsh -NoProfile -File ./hosted_copilot/tools/Test-Toolkit.ps1` |
| Launch the Hosted Rule Workbench | `pwsh -NoProfile -File ./hosted_copilot/tools/Start-RuleWorkbench.ps1` |
| Plan or install the Hosted payload | `pwsh -NoProfile -File ./hosted_copilot/tools/Install-Toolkit.ps1` |

Review the command help before supplying operation-specific parameters. Installation defaults to a dry run.

## Catalog Maintenance

These commands move to `tools/commands/catalog/` during Phase 2.5.

| Task | Command |
| --- | --- |
| Check generated instruction freshness | `pwsh -NoProfile -File ./hosted_copilot/tools/Generate-Instructions.ps1` |
| Regenerate approved instruction changes | `pwsh -NoProfile -File ./hosted_copilot/tools/Generate-Instructions.ps1 -Write` |
| Audit live upstream source drift | `pwsh -NoProfile -File ./hosted_copilot/tools/Test-UpstreamSources.ps1 -FailOnDrift` |

Live upstream drift is an explicit maintainer audit and is not a deterministic required-CI input.

## Review Experiment

These commands move to `tools/commands/review/` during Phase 2.5.

Use the [Hosted Review Experiment Runbook](../docs/HOSTED_REVIEW_EXPERIMENT_RUNBOOK.md) for required sequencing, parameters, mutation switches, and cleanup gates.

The supported experiment commands are:

- `Initialize-ReviewBases.ps1`
- `Publish-TestCase.ps1`
- `Import-PullRequest.ps1`
- `New-ReviewPair.ps1`
- `Capture-ReviewPair.ps1`
- `Close-ReviewPair.ps1`

## Focused Development

Focused tests are invoked while changing their owning implementation and are also composed by `Test-Toolkit.ps1`. They are not normal maintainer operations. Migration-only tools exist solely to prove and complete the version 4 cutover and are removed from normal validation before archival.
