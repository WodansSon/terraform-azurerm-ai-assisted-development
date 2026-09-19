# Hosted Review

`Invoke-HostedReview.ps1` is the only supported maintainer entry point for controlled Hosted review comparison. It owns setup, durable run discovery, evidence capture, local adjudication, result validation, reporting, and approved cleanup.

## Start Or Resume

Run the command from the AI-assisted development repository and provide the local writable AzureRM provider fork plus a controlled case:

```powershell
pwsh -NoProfile -File ./hosted_copilot/tools/Invoke-HostedReview.ps1 `
  -RepoDirectory C:\github.com\WodansSon\terraform-provider-azurerm `
  -CaseId documentation-example-validation-v2 `
  -ReviewEffort Lite
```

The first invocation initializes or verifies the required provider-fork state, publishes the controlled change, and opens matching Control and Hosted pull requests. It then prints both pull request URLs and exits.

Request the displayed `Lite` or `Balanced` Copilot review on both pull requests. GitHub does not expose an API for selecting review effort, so this is the only manual GitHub step.

After both reviews finish, rerun the same command. The command discovers the unfinished run automatically, captures both reviews, and guides blinded local adjudication with numbered choices. Maintainers classify comments and provide concise reasons; they do not edit JSON, calculate hashes, identify branches, or invoke lifecycle stages.

If either review is incomplete, the command prints the required pull request links and exits. It never waits, polls, or requires a chat session to remain active.

## Result

After adjudication, the command writes a schema-valid local result and prints a comparison of expected findings, misses, additional valid findings, false positives, and runtime limitations. Generated evidence remains beneath `hosted_copilot/regression/raw/` and `hosted_copilot/regression/results/`; both directories are Git-ignored.

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

Persistent review bases are preserved. Scripts beneath `hosted_copilot/tools/internal/review/` are implementation details and must not be invoked as maintainer commands.
