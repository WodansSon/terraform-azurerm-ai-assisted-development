# Hosted Review Experiment Runbook

Use the lifecycle commands in this document instead of creating branches or pull requests manually.

## Invariant

- `control-base`, `hosted-base`, and `test-content` are the persistent experiment branches.
- `control-base` and `test-content` point exactly at one pinned provider commit.
- `hosted-base` descends from `control-base` and adds only the Hosted package.
- Synthetic `test-case/...` and imported `imported-pr/...` source branches open canonical pull requests against `test-content` and remain separate from disposable mirror heads.
- Every run mirrors one source pull request into disposable `control-review/source-pr-<number>/<run>` and `hosted-review/source-pr-<number>/<run>` heads.
- The two pull requests contain identical case patches and identical title and body text.
- Capture evidence before deleting the disposable heads.
- Never reuse or force-push a run head. GitHub associates closed pull requests and review history with those branch commits.
- Mutating commands refuse the canonical HashiCorp repository, arbitrary forks, and forks not owned by the authenticated GitHub user.
- New pair records use schema version 2 and are written beneath `regression/raw/source-pr-<number>/`. Pair, capture, summary, and result files are ignored local evidence and must not be committed.

## Initialize Bases

Initialize the persistent bases once for a fixed provider commit and Hosted package:

```powershell
./hosted_copilot/tools/commands/review/Initialize-ReviewBases.ps1 `
  -RepoDirectory C:\github.com\WodansSon\terraform-provider-azurerm `
  -PinnedCommit <provider-main-commit> `
  -Initialize `
  -Push
```

Omit `-Initialize` to verify existing bases. Rebuild all three bases when the pinned provider commit or Hosted package changes. Do not rewrite bases while a run is active.

Initialization records the deployed toolkit source commit and package-manifest hash in `.github/hosted-copilot-installed-state.json` on `hosted-base`. Pair creation reads that file and carries both values into the pair record automatically so captured results remain bound to the exact Hosted baseline.

## Choose Review Effort

`ReviewEffort` accepts `Lite` or `Balanced`. Use the same value for both mirror reviews in one run. This requested product setting is recorded as experiment evidence and is distinct from the internal model-session `ReasoningEffort`; do not translate one into the other.

## Author A Synthetic Case

Each case owns one repository-shaped content tree. Add any number of implementation, test, documentation, or supporting files beneath `content/`:

```text
cases/<surface>/<case-id>/
  case.json
  content/
    internal/services/example/example_resource.go
    internal/services/example/example_resource_test.go
    website/docs/r/example.html.markdown
```

`case.json` sets `contentRoot` to `content` and records expected findings with repository-relative `path`, `ruleId`, `match`, and `reason` values. The lifecycle derives the complete changed-file set from Git. Content under `.github/` is prohibited because it could alter the reviewer being tested.

## Publish A Synthetic Case

Run validation without changing Git or GitHub:

```powershell
./hosted_copilot/tools/commands/review/Publish-TestCase.ps1 `
  -RepoDirectory C:\github.com\WodansSon\terraform-provider-azurerm `
  -CaseId documentation-example-validation-v2 `
  -RunId lite-01 `
  -ReviewEffort Lite
```

Add `-Create` to create or update the case's source PR against `test-content`, create or synchronize the mirror pair, and write:

```text
hosted_copilot/regression/raw/source-pr-<number>/<run-id>.pair.json
```

Request the configured review effort on both pull requests within the same test window. Do not request a second review on either pull request.

## Import A Real Pull Request

Use a real HashiCorp AzureRM pull request as the canonical change set:

```powershell
./hosted_copilot/tools/commands/review/Import-PullRequest.ps1 `
  -RepoDirectory C:\github.com\WodansSon\terraform-provider-azurerm `
  -PullRequest 33138 `
  -RunId lite-01 `
  -ReviewEffort Lite
```

When `-SourceRepository` is omitted, the command uses the writable fork's upstream parent. Set `-SourceRepository owner/terraform-provider-azurerm` to import a pull request numbered in another AzureRM fork. The source must be HashiCorp's AzureRM provider or one of its forks.

The default invocation validates source lineage, captures every changed file, rejects `.github/` changes, downloads the canonical GitHub diff, and proves it applies to `test-content`. Add `-Create` to create or update an `imported-pr/...` source PR against `test-content` and create or synchronize its mirror pair. Imported runs are exploratory unless expected findings are separately defined before review.

## Mirror An Existing Source PR

Any open pull request in the personal fork that targets `test-content` can drive a pair:

```powershell
./hosted_copilot/tools/commands/review/New-ReviewPair.ps1 `
  -RepoDirectory C:\github.com\WodansSon\terraform-provider-azurerm `
  -SourcePullRequest <source-pr-number> `
  -RunId lite-01 `
  -ReviewEffort Lite
```

Add `-Create` to open the mirror pair. After updating the source PR, rerun the same command with the same run ID and `-Create` to synchronize both mirror heads. Use a new run ID when a fresh independent review pair is required.

The generated schema-version-2 pair record stores source provenance, both pull requests and mirror commits, changed files, diff hash, requested review effort, and the source commit and manifest hash read from the deployed Hosted baseline. Maintainers do not calculate or enter those baseline values during a normal run.

## Capture A Pair

After both reviews complete, use the pair record as the only input:

```powershell
./hosted_copilot/tools/commands/review/Capture-ReviewPair.ps1 `
  -PairPath ./hosted_copilot/regression/raw/source-pr-<source-pr-number>/<run-id>.pair.json
```

Capture writes these files beside the pair record:

- `<run-id>.json` contains the complete unblinded capture and runtime evidence.
- `<run-id>.blind.json` contains profile-blinded review comments for adjudication.
- `<run-id>.summary.md` contains a readable runtime, model, skill, memory, and deduplication summary.

`Capture-ReviewPair.ps1` can read existing schema-version-1 pair records for historical evidence recovery. New runs must use the schema-version-2 record created by `New-ReviewPair.ps1`. The lower-level manual capture form is documented in `../regression/README.md`; use it only when recovering evidence that predates pair records, and never invent `SourceCommit` or `ManifestHash` values.

## Close A Pair

Validate cleanup without changing Git or GitHub:

```powershell
./hosted_copilot/tools/commands/review/Close-ReviewPair.ps1 `
  -RepoDirectory C:\github.com\WodansSon\terraform-provider-azurerm `
  -PairPath ./hosted_copilot/regression/raw/source-pr-<source-pr-number>/<run-id>.pair.json
```

Add `-Close` to close both pull requests and delete only their disposable local and remote heads. The command validates the `control-review/source-pr-<number>/<run>` and `hosted-review/source-pr-<number>/<run>` topology and refuses cleanup unless `<run-id>.json` exists beside the pair record. Use `-AllowMissingCapture` only to abandon a failed run that cannot produce evidence.

## Recovery

- Pair creation rolls back both heads and any partially opened pull request when setup fails.
- If automatic recovery reports an issue, use the branch and pull request identities printed in the error. Do not delete any persistent base.
- If base verification fails, finish or abandon active runs, delete all three bases, and initialize them again from one pinned commit.
- Generated pair, capture, summary, and result files are ignored local evidence and must not be committed.
