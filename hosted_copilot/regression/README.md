# Hosted Review Regression Evidence:

This directory owns controlled Hosted review cases, the paired-result schema, and local experiment evidence.

## Tracked Assets:

- `cases/` contains canonical before and after fixtures with expected findings.
- `schema/paired-review-result.schema.json` defines adjudicated paired result records.
- `../tools/Capture-HostedReviewPair.ps1` captures paired GitHub review evidence.
- `../tools/Test-HostedReviewResults.ps1` validates local result records and recomputes their totals.

## Local Artifacts:

- `raw/` contains complete GitHub API evidence and profile-blinded adjudication views.
- `results/` contains adjudicated paired result records.
- Both directories are generated and Git-ignored.
- A clean clone can contain neither directory and still pass Hosted validation.

## Capture A Pair:

Capture both completed reviews using the source commit and ownership-manifest hash recorded by the deployed Hosted baseline:

```powershell
pwsh -NoProfile -File ./hosted_copilot/tools/Capture-HostedReviewPair.ps1 `
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

It writes a complete raw capture and a profile-blinded view beneath `raw/<fixtureId>/`.

## Prepare A Live Pair:

- Materialize the case's `before` snapshot at `targetPath` on both base branches before creating either pull request branch.
- Apply the same `before`-to-`after` change on both pull request branches so only intentional seeded defects appear in each diff.
- Do not model a modification case by adding the complete `after` snapshot as a new file; that exposes unchanged fixture scaffolding as reviewable pull request content.
- Keep any implementation or schema evidence required by the case identical on both base branches.
- Use fresh pull requests for every independent run; repeated reviews on one pull request invoke product-side deduplication against earlier review feedback.

## Adjudicate And Validate:

Classify every captured comment as `expected`, `unexpected-valid`, `false-positive`, or `duplicate`. Record any expected rule not found as a miss, save the pair beneath `results/<fixtureId>/`, and validate all local records:

```powershell
pwsh -NoProfile -File ./hosted_copilot/tools/Test-HostedReviewResults.ps1
```

Use the instantiated `github/copilot-code-review` session for `modelName` and `reasoningLevel`. Preserve `COPILOT_AGENT_MODEL` as configured-primary evidence, classify other instantiated sessions by `clientName`, and do not report configured-only detector models as executed sessions. Treat the requested `Lite` or `Balanced` review effort and the internal session `ReasoningEffort` as separate evidence; do not translate one into the other. Missing or changed Actions-log markers produce `partial` or `unavailable` runtime evidence with explicit diagnostics instead of aborting review capture or silently asserting a model. Use `unknown` only when product-generated evidence is unavailable, and do not infer model identity from pull request titles. Unknown or differing primary-model evidence prevents a direct instruction-profile conclusion.
