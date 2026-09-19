# Hosted Review Regression Evidence:

This directory owns controlled Hosted review cases, the review-result schema, Workbench regression assets, and local comparison evidence.

## Tracked Assets:

- `cases/` contains repository-shaped canonical content trees with expected findings.
- `workbench/` contains schema-backed browser behavior mappings, target Playwright journeys, and a temporary Puppeteer consumer of the same current viewport suite.
- `schema/paired-review-result.schema.json` defines adjudicated comparison records.
- `../tools/Invoke-HostedReview.ps1` is the only supported maintainer command for starting or resuming a controlled review.
- `../tools/tests/Test-ReviewResults.ps1` is the internal result validator invoked by `Test-Toolkit.ps1`; it is not a separate maintainer command.

## Local Artifacts:

- `raw/` contains complete GitHub API evidence, profile-blinded adjudication views, and readable pair summaries.
- `results/` contains adjudicated paired result records.
- Both directories are generated and Git-ignored.
- A clean clone can contain neither directory and still pass Hosted validation.

## Run A Controlled Review:

Follow [Hosted Review](../docs/HOSTED_REVIEW.md). The same command starts and resumes the workflow:

```powershell
pwsh -NoProfile -File ./hosted_copilot/tools/Invoke-HostedReview.ps1 `
  -RepoDirectory C:\github.com\WodansSon\terraform-provider-azurerm `
  -CaseId documentation-example-validation-v2 `
  -ReviewEffort Lite
```

The command owns repository preparation, comparison pull requests, evidence capture, blinded local adjudication, result construction, validation, and reporting. It exits while GitHub reviews are pending and resumes from local evidence when rerun. Cleanup requires the explicit `-Cleanup` switch.

Maintainers do not invoke internal lifecycle scripts, supply branch names or artifact paths, calculate hashes, edit result JSON, or keep an AI session running. The architecture document's **Historical Provenance** section records why controlled comparison exists and how the current workflow evolved.
