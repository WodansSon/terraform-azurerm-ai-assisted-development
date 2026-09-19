# Hosted Review Regression Evidence:

This directory owns controlled Hosted review cases, the paired-result schema, and local experiment evidence.

## Tracked Assets:

- `cases/` contains repository-shaped canonical content trees with expected findings.
- `workbench/` contains schema-backed browser behavior mappings, target Playwright journeys, and a temporary Puppeteer consumer of the same current viewport suite.
- `schema/paired-review-result.schema.json` defines adjudicated paired result records.
- `../tools/commands/review/Initialize-ReviewBases.ps1` creates or verifies the three persistent bases.
- `../tools/commands/review/Publish-TestCase.ps1` creates or updates a synthetic source PR against `test-content`.
- `../tools/commands/review/Import-PullRequest.ps1` creates or updates an imported source PR against `test-content`.
- `../tools/commands/review/New-ReviewPair.ps1` mirrors one source PR into identical disposable Control and Hosted review heads.
- `../tools/commands/review/Capture-ReviewPair.ps1` captures paired GitHub review evidence.
- `../tools/commands/review/Close-ReviewPair.ps1` closes a captured pair and deletes only its disposable heads.
- `../tools/tests/Test-ReviewResults.ps1` is the internal result validator invoked by `Test-Toolkit.ps1`; it is not a separate maintainer command.

## Local Artifacts:

- `raw/` contains complete GitHub API evidence, profile-blinded adjudication views, and readable pair summaries.
- `results/` contains adjudicated paired result records.
- Both directories are generated and Git-ignored.
- A clean clone can contain neither directory and still pass Hosted validation.

## Capture Review Evidence:

Follow `../docs/HOSTED_REVIEW_EXPERIMENT_RUNBOOK.md` for the complete lifecycle. The normal capture command requires only the pair record created by `New-ReviewPair.ps1`:

```powershell
pwsh -NoProfile -File ./hosted_copilot/tools/commands/review/Capture-ReviewPair.ps1 `
  -PairPath ./hosted_copilot/regression/raw/source-pr-<source-pr-number>/<run-id>.pair.json
```

New pair records use schema version 2. They contain source provenance, the repository and source pull request, both mirror pull requests, changed files, diff hash, review effort, source commit, and manifest hash. Maintainers should not calculate or enter those values during a normal run.

Capture writes `<run-id>.json`, `<run-id>.blind.json`, and `<run-id>.summary.md` beside the pair record. These contain the complete evidence, profile-blinded adjudication input, and readable runtime summary respectively.

### Legacy Manual Capture:

Use the lower-level manual form only to recover completed review evidence that predates pair records. `ManifestHash` identifies the exact Hosted package manifest deployed to `hosted-base`, preventing captured results from being attributed to the wrong toolkit baseline. `SourceCommit` identifies the toolkit source commit recorded by that same deployment.

Read both values from the installed-state file committed on `hosted-base`, then pass them to the capture command:

```powershell
$state = git -C C:\github.com\WodansSon\terraform-provider-azurerm `
  show hosted-base:.github/hosted-copilot-installed-state.json |
  ConvertFrom-Json

pwsh -NoProfile -File ./hosted_copilot/tools/commands/review/Capture-ReviewPair.ps1 `
  -Repository WodansSon/terraform-provider-azurerm `
  -ControlPullRequest 1 `
  -HostedPullRequest 2 `
  -FixtureId documentation-example-validation-v2 `
  -RunId lite-01 `
  -ReviewEffort Lite `
  -SourceCommit $state.commit `
  -ManifestHash $state.manifestHash
```

The command refuses pairs with different changed-file sets or GitHub file patches. It resolves each completed review to exactly one `Running Copilot Code Review` Actions run using the pull request number, reviewed head commit, and review window. The raw capture records the Actions-log hash, deployed baseline identity, configured primary model, every instantiated model session and its `clientName` role, configured-only auxiliary models, runtime version, `MaxPromptTokens`, memory count, loaded skills, and previous-feedback deduplication counts. The caller must have permission to read Actions logs.

In reports, present this value as **`MaxPromptTokens`: 110,000**. It is an observed GitHub Copilot review runtime field, not actual token usage or a user-configurable setting.

Manual capture writes the same three artifacts beneath `raw/<FixtureId>/`. The summary lists instantiated models by role, keeps configured-only auxiliary models separate, and presents runtime, skill, memory, and deduplication evidence without replacing the JSON source evidence.

## Prepare A Live Pair:

- Keep `control-base` and `test-content` pinned, and keep `hosted-base` limited to the Hosted overlay.
- Author synthetic cases as repository-shaped `content/` trees containing the complete intended change set.
- Open each canonical change as a source PR against `test-content`, then mirror its exact diff into Control and Hosted review heads.
- Import real pull request diffs only from HashiCorp's AzureRM provider or one of its forks.
- Reject `.github/` changes so test content cannot change the reviewer configuration.
- Use fresh pull requests for every independent run; repeated reviews on one pull request invoke product-side deduplication against earlier review feedback.

## Current Pipeline Boundary:

`Capture-ReviewPair.ps1` completes the implemented evidence pipeline. It collects runtime evidence and writes the raw, blinded, and readable summary artifacts. Maintainers use `<run-id>.summary.md` to understand the conditions under which each review ran; they do not extract or populate runtime fields manually.

The original Phase Four experiment used an AI assistant interactively after capture to review `<run-id>.blind.json`, classify the findings, and write `results/<fixture-id>/<run-id>.json`. That chat-driven step was never packaged as a reusable prompt, skill, agent, or command. The current supported command surface therefore ends at capture, and maintainers should not construct adjudicated result JSON manually.

The architecture document's **Historical Provenance** section records the immutable pull request pairs and implementation commits that produced this boundary.

When a result record exists, normal Hosted Toolkit validation invokes `Test-ReviewResults.ps1` internally to verify it. Maintainers do not run that focused validator directly.
