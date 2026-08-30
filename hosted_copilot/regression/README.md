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

The command refuses pairs with different changed-file sets or GitHub file patches. It writes a complete raw capture and a profile-blinded view beneath `raw/<fixtureId>/`.

## Prepare A Live Pair:

- Materialize the case's `before` snapshot at `targetPath` on both base branches before creating either pull request branch.
- Apply the same `before`-to-`after` change on both pull request branches so only intentional seeded defects appear in each diff.
- Do not model a modification case by adding the complete `after` snapshot as a new file; that exposes unchanged fixture scaffolding as reviewable pull request content.
- Keep any implementation or schema evidence required by the case identical on both base branches.

## Adjudicate And Validate:

Classify every captured comment as `expected`, `unexpected-valid`, `false-positive`, or `duplicate`. Record any expected rule not found as a miss, save the pair beneath `results/<fixtureId>/`, and validate all local records:

```powershell
pwsh -NoProfile -File ./hosted_copilot/tools/Test-HostedReviewResults.ps1
```

Use `unknown` rather than inferring model or reasoning metadata that GitHub does not expose. Unknown or differing model evidence prevents a direct instruction-profile conclusion.
