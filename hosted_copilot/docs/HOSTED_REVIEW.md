# Hosted Review Regression Harness

`Invoke-HostedReview.ps1` is the only supported maintainer entry point for controlled Hosted review comparison. It owns setup, durable run discovery, evidence capture, local adjudication, result validation, reporting, and approved cleanup.

## What It Proves

The harness compares GitHub Copilot review behavior with and without the final Hosted Rules package. It applies the same known-defect change to two pull requests, uses the same review effort, verifies identical changed-file sets and diff hashes, and records expected findings, misses, duplicates, additional valid findings, and false positives.

This is the end-to-end quality regression step for the deployed Hosted Rules package. It does not run Workbench source collection, assessment, reconciliation, or promotion. Those stages decide what belongs in the Hosted catalog and generated runtime files. The harness tests the resulting package after `Install-HostedRules.ps1` deploys it to the Hosted comparison base.

## What `CaseId` Means

`CaseId` selects a controlled regression fixture beneath `hosted_copilot/regression/cases/`. It is not a branch name, run identifier, or schema version. The command resolves the selected fixture's `case.json`, publishes its repository-shaped content as one canonical source pull request, and generates all branch and run names.

The example `documentation-example-validation-v2` selects [the second documentation validation fixture](../regression/cases/documentation/example-validation-v2/case.json). Its `-v2` suffix distinguishes that expanded fixture from the original two-finding documentation case; it is unrelated to the paired-result schema version.

Current controlled cases are:

- `documentation-example-validation` checks an invalid example value and missing Oxford comma.
- `documentation-example-validation-v2` adds an invalid argument-list marker to those documentation defects.
- `implementation-patch-and-id-canonicalization` checks PATCH clearing and canonical Azure resource ID state.
- `testing-callback-poller-deadline` checks timeout ownership around Azure polling in test callbacks.
- `testing-embedded-terraform-indentation` checks Terraform formatting embedded in Go test strings.

## Comparison Topology

The command prepares three persistent bases in the authenticated maintainer's writable AzureRM fork:

- `control-base` contains the pinned provider commit without Hosted Rules.
- `hosted-base` starts from the same pinned commit and contains only the manifest-owned Hosted Rules package and installed-state record.
- `test-content` starts from the same pinned commit and receives canonical source pull requests for controlled cases.

For each run, the command mirrors the canonical source pull request diff onto disposable `control-review/...` and `hosted-review/...` heads. It opens the Control pull request against `control-base` and the Hosted pull request against `hosted-base` only after proving that both review diffs have the same changed files and diff hash. The commit SHAs differ because the two heads have different parent commits.

## Start Or Resume

Run the command from the AI-assisted development repository. `RepoDirectory` identifies the clean local checkout of the authenticated maintainer's writable AzureRM fork, and `CaseId` identifies the controlled fixture:

```powershell
pwsh -NoProfile -File ./hosted_copilot/tools/Invoke-HostedReview.ps1 `
  -RepoDirectory C:\github.com\WodansSon\terraform-provider-azurerm `
  -CaseId documentation-example-validation-v2 `
  -ReviewEffort Lite
```

The first invocation initializes or verifies the three persistent bases, publishes the selected controlled change, creates fresh disposable review heads, and opens matching Control and Hosted pull requests. It then prints both pull request URLs and exits.

Request the displayed `Lite` or `Balanced` Copilot review on both pull requests. GitHub does not expose an API for selecting review effort, so this is the only manual GitHub step.

After both reviews finish, rerun the same command. The command discovers the unfinished run automatically, captures both reviews, and guides blinded local adjudication with numbered choices. Maintainers classify comments and provide concise reasons; they do not edit JSON, calculate hashes, identify branches, or invoke lifecycle stages.

If either review is incomplete, the command prints the required pull request links and exits. It never waits, polls, or requires a chat session to remain active.

## Result And Schema

After adjudication, the command writes a local result validated against [`paired-review-result.schema.json`](../regression/schema/paired-review-result.schema.json) and prints a comparison of expected findings, misses, additional valid findings, false positives, and runtime limitations. New adjudicated results use schema version 2. The schema continues to accept version 1 historical records; this compatibility has no relationship to a fixture name ending in `-v2`.

Generated evidence remains beneath `hosted_copilot/regression/raw/` and `hosted_copilot/regression/results/`; both directories are Git-ignored. Captured metadata includes the installed Hosted source commit and manifest hash, the exact review diff identity, requested review effort, and available product-generated model evidence. A comparison is marked confounded when the observed model or reasoning evidence differs, and unknown model identity is not inferred.

One Copilot comment can satisfy several expected rules. The adjudication prompt accepts comma-separated expected-finding numbers so the result does not report a false miss for a combined comment.

After a case is complete, use `-NewRun` to start another independent comparison. The command generates the run identity and fresh pull requests automatically.

## Cleanup

Cleanup is never automatic. After reviewing the result, explicitly approve removal of disposable pull requests and branches:

```powershell
pwsh -NoProfile -File ./hosted_copilot/tools/Invoke-HostedReview.ps1 `
  -RepoDirectory C:\github.com\WodansSon\terraform-provider-azurerm `
  -CaseId documentation-example-validation-v2 `
  -ReviewEffort Lite `
  -Cleanup
```

Persistent `control-base`, `hosted-base`, and `test-content` branches are preserved for repeated comparisons against the same pinned provider commit and Hosted package. Only the disposable paired review pull requests and their `control-review/...` and `hosted-review/...` heads are removed. Scripts beneath `hosted_copilot/tools/internal/review/` are implementation details and must not be invoked as maintainer commands.
