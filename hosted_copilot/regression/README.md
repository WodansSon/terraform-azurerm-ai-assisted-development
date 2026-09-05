# Hosted Review Regression Evidence:

This directory owns controlled Hosted review cases, the paired-result schema, and local experiment evidence.

## Tracked Assets:

- `cases/` contains repository-shaped canonical content trees with expected findings.
- `schema/paired-review-result.schema.json` defines adjudicated paired result records.
- `../tools/Initialize-ReviewBases.ps1` creates or verifies the three persistent bases.
- `../tools/Publish-TestCase.ps1` creates or updates a synthetic source PR against `test-content`.
- `../tools/Import-PullRequest.ps1` creates or updates an imported source PR against `test-content`.
- `../tools/New-ReviewPair.ps1` mirrors one source PR into identical disposable Control and Hosted review heads.
- `../tools/Capture-ReviewPair.ps1` captures paired GitHub review evidence.
- `../tools/Close-ReviewPair.ps1` closes a captured pair and deletes only its disposable heads.
- `../tools/Test-ReviewResults.ps1` validates local result records and recomputes their totals.

## Local Artifacts:

- `raw/` contains complete GitHub API evidence, profile-blinded adjudication views, and readable pair summaries.
- `results/` contains adjudicated paired result records.
- Both directories are generated and Git-ignored.
- A clean clone can contain neither directory and still pass Hosted validation.

## Run A Pair:

Follow `../docs/HOSTED_REVIEW_EXPERIMENT_RUNBOOK.md`. The normal lifecycle is initialize once, create a pair, request both reviews, capture by pair record, then close by pair record.

The lower-level manual capture form remains available for existing evidence that predates pair records:

Capture both completed reviews using the source commit and ownership-manifest hash recorded by the deployed Hosted baseline:

```powershell
pwsh -NoProfile -File ./hosted_copilot/tools/Capture-ReviewPair.ps1 `
  -Repository WodansSon/terraform-provider-azurerm `
  -ControlPullRequest 1 `
  -HostedPullRequest 2 `
  -FixtureId documentation-example-validation-v2 `
  -RunId lite-01 `
  -ReviewEffort Lite `
  -SourceCommit 0000000000000000000000000000000000000000 `
  -ManifestHash 0000000000000000000000000000000000000000000000000000000000000000
```

The command refuses pairs with different changed-file sets or GitHub file patches. It resolves each completed review to exactly one `Running Copilot Code Review` Actions run using the pull request number, reviewed head commit, and review window. The raw capture records the Actions-log hash, configured primary model, every instantiated model session and its `clientName` role, configured-only auxiliary models, runtime version, `MaxPromptTokens`, memory count, loaded skills, and previous-feedback deduplication counts. The caller must have permission to read Actions logs.

In reports, present this value as **`MaxPromptTokens`: 110,000**. It is an observed GitHub Copilot review runtime field, not actual token usage or a user-configurable setting.

It writes a complete raw capture, a profile-blinded view, and a readable Markdown summary beneath `raw/<fixtureId>/`. The summary lists instantiated models by role, keeps configured-only auxiliary models separate, and presents runtime, skill, memory, and deduplication evidence without replacing the JSON source evidence.

## Prepare A Live Pair:

- Keep `control-base` and `test-content` pinned, and keep `hosted-base` limited to the Hosted overlay.
- Author synthetic cases as repository-shaped `content/` trees containing the complete intended change set.
- Open each canonical change as a source PR against `test-content`, then mirror its exact diff into Control and Hosted review heads.
- Import real pull request diffs only from HashiCorp's AzureRM provider or one of its forks.
- Reject `.github/` changes so test content cannot change the reviewer configuration.
- Use fresh pull requests for every independent run; repeated reviews on one pull request invoke product-side deduplication against earlier review feedback.

## Adjudicate And Validate:

Classify every captured comment as `expected`, `unexpected-valid`, `false-positive`, or `duplicate`. Record any expected rule not found as a miss, save the pair beneath `results/<fixtureId>/`, and validate all local records:

```powershell
pwsh -NoProfile -File ./hosted_copilot/tools/Test-ReviewResults.ps1
```

Use the instantiated `github/copilot-code-review` session for `modelName` and `reasoningLevel`. Preserve `COPILOT_AGENT_MODEL` as configured-primary evidence, classify other instantiated sessions by `clientName`, and do not report configured-only detector models as executed sessions. Treat the requested `Lite` or `Balanced` review effort and the internal session `ReasoningEffort` as separate evidence; do not translate one into the other. Missing or changed Actions-log markers produce `partial` or `unavailable` runtime evidence with explicit diagnostics instead of aborting review capture or silently asserting a model. Use `unknown` only when product-generated evidence is unavailable, and do not infer model identity from pull request titles. Unknown or differing primary-model evidence prevents a direct instruction-profile conclusion.
