# Hosted Toolkit Commands

Only the commands listed here are supported maintainer entry points. The four normal-operation commands remain at the tools root. Specialized catalog commands live beneath `commands/catalog/`; the read-only adoption preflight lives beneath `commands/adoption/`.

Only the four public `.ps1` entry points and this README belong directly in the tools root. Files beneath supporting folders are implementation or validation details, not an equivalent manual command surface. Reusable `.psm1` files live under `modules/`; implementation scripts, including the Node icon renderer, live under their owning `internal/` workflow. Shared cross-workflow primitives live under `modules/shared/`, review compatibility and workflow composition live under `modules/review/`, source-format parsers live under `modules/source-parsers/`, and Workbench runtime composition lives under `modules/workbench/`. Retired migration and version 3 tools are preserved under `local-only-docs/obsolete-v3/`.

- `config/` contains repository adoption and token policy, model profiles, and the deployment package manifest.
- `npm/` contains the validation package manifest, lockfile, and installed `node_modules/`. Dependency commands use `--prefix ./hosted_copilot/tools/npm`; moving these files does not change the locked graph.
- `internal/icons/Render-WorkbenchIconPreview.cjs` is an implementation helper, invoked by the icon-preview wrapper rather than a public command.

`modules/shared/HostedGitHub.Helpers.psm1` exclusively owns GitHub CLI process execution and reusable API, CODEOWNERS, and fork-target primitives. Workbench, review, and source-collection consumers retain their domain-specific policy but must delegate authenticated GitHub CLI execution to that shared module.

## Contract And Prompt Libraries

All local evaluator instructions live under [prompts/](prompts/README.md), grouped into assessment, reconciliation, chat, and shared templates. Runtime code loads those files rather than embedding instruction prose. The library index documents consumers, behavior-authority registration, boundaries, and the configuration-versus-engine separation required for adoption beyond the current AzureRM use case.

Behavior descriptors and JSON schemas live in the separate [contract library](../contracts/README.md), grouped by task. Configuration and rule data remain under the rule catalog; validation loads schemas explicitly from the contract library rather than assuming they live beside input data.

## Repository Adoption And Token Policy

[config/adoption.json](config/adoption.json) is repo-local maintainer configuration, not deployed review guidance. It owns the canonical review upstream, references to the source-definition set, catalog and protected rules, and the guidance token policy. Model profiles remain in [config/llm.json](config/llm.json). Source repositories belong to individual lane definitions and can differ from the review upstream; changing that upstream does not authorize access or bypass fork-family validation.

Paths declared in the descriptor are relative to the Hosted Toolkit root (`hosted_copilot/`), not the repository root or the descriptor's parent directory. Its `$comment` records that convention in the JSON itself. Paths inside referenced source-definition documents retain their own contract's resolution rules.

The descriptor's `tokenPolicy` contains:

- `estimator`: The supported `character-quarter-estimate-v1` algorithm estimates tokens with the ceiling of character count divided by four.
- `safetyMarginPercent`: The configured percentage added to each file's estimate before checking budgets. Combined views sum the guarded counts of their members.
- `maximumGuidanceTokens`: The ceiling on all unique configured guidance files, counted once rather than summing overlapping combined views. This is an engineering allocation, not evidence of the model runtime's actual context capacity.
- `areas`: Named file allocations. Use `surfaceId` to reference a catalog surface's output path or `path` for shared repository or skill guidance. Each area requires a positive `budgetTokens`; file paths and report names must be unique. Every deployed catalog surface must be accounted for.
- `combinations`: Named applicable-review views with explicit area `members` and independent budgets. Unknown or duplicate members are rejected. Areas and combined views are deployed guidance allocations, not source lanes.

Multiple skills use separate entries in `areas`, each with a unique name, file path and budget. Include each skill's area name only in the combined review views where it applies; `skill` is the initial profile's area name, not a singleton configuration property.

The initial descriptor retains the existing AzureRM allocations and combined memberships, a 25% safety margin, and the 110,000-token deployed-guidance ceiling. The reader and capacity-report validator enforce the configured set rather than assuming three source lanes or eight reports. Missing or malformed configuration fails without an AzureRM fallback. Reports bind the resolved policy, and display generation rejects stale, missing, duplicated or arithmetically inconsistent reports. Browser token estimates and advisory AI use the display snapshot's margin and limits.

Run the offline adoption preflight:

```powershell
pwsh -NoProfile -File ./hosted_copilot/tools/commands/adoption/Test-RepositoryAdoption.ps1
```

Use `-HostedRoot <profile-root>` for a prepared local profile and `-DescriptorPath <relative-json-path>` for an alternative descriptor inside that root. `-OutputFormat Json` emits findings suitable for automation. Paths cannot escape the root or traverse symbolic links or junctions. The preflight runs only installed deterministic capacity code, not commands named by input data; it performs no collection, inference, authorization request, rewriting, staging, or cache migration.

| Finding Status | Meaning |
| --- | --- |
| `passed` | The stated structural, accounting or declaration check succeeded; this is not universal readiness |
| `requires-adaptation` | A confirmed restriction or exhausted budget needs attention |
| `invalid` | A required input or dependency is missing, unsafe, malformed or inconsistent |
| `not-assessed` | Compatibility needs integration review beyond an offline check |

Each finding contains its reason, `requiredChanges`, `relatedFiles`, and verification commands. Required changes are evidence-backed; related behavior files are review points, not a claim that every dependency must be edited. The checker recognizes only known static parser/repository declarations and reports unrecognized declarations as unassessed rather than executing them or guessing support. A source schema's repository-only rejection is distinguished from other malformed source configuration.

Process exit codes are `0` for fully passing checks, `1` for invalid inputs or required adaptations, and `2` for review still required. The initial profile intentionally returns `2`: source-format semantics, arbitrary rule categories, current Workbench surface mappings, live GitHub access and actual runtime limits cannot be established by this command.

The descriptor currently drives preflight and capacity configuration; it does not automatically rewire the existing collection/review entry points, replace supported parser implementations, generalize the browser's surface map, or grant new repository permissions. The preflight is a migration checklist rather than an automatic code migration engine. Keep these integration boundaries explicit when preparing another repository.

Run [Test-RepositoryAdoption.ps1](tests/Test-RepositoryAdoption.ps1) for focused policy, alternate-profile, browser-calculation and read-only diagnostic tests. Normal Hosted validation also runs this suite. A policy change requires explicit reconstruction of staged displays before use; the live Workbench and saved artifacts are not silently rewritten. An explicit rebuild may require fresh inference when behavior authority changes.

## Focused SQLite Validation

Run the connection and source-ingestion suites independently:

```powershell
pwsh -NoProfile -File ./hosted_copilot/tools/tests/Test-WorkbenchSqlite.ps1
pwsh -NoProfile -File ./hosted_copilot/tools/tests/Test-WorkbenchSourceIngestion.ps1
```

Each PowerShell wrapper runs only its corresponding native test file under `tests/sqlite/`. It prints one `[RUNNING]  JUnit tests.` line, collects Node's built-in JUnit results, and formats each test's status and reported duration using the Hosted output helpers. Skipped tests show `[SKIPPED]` and their reason on the same row. The summary and failure details follow; a test failure does not count again merely because Node exits with code 1. Add `-OutputFormat Json` for structured results. No custom Node reporter, browser run, npm installation, collection, or live workspace migration is involved.

## Test Output

Each suite uses one title for its opening and `<title> SUMMARY` heading. The JUnit runner activity owns its indented case rows without adding another test to the summary counts. Executed cases display a running row and a timed completion row; skipped cases display one `[SKIPPED]` row with their reason, without a running row or execution duration. Failed cases retain their evidence in the separate failure section. Output ends with the standard summary and any failure details, without an extra success footer.

Native labels prefer an optional `shortName`, then the native JUnit `name` unchanged, then `test-001` or the corresponding report-local ordinal when neither is supplied. Optional JSON diagnostics supply the short label and a separate description without replacing the native test identity:

```javascript
import assert from 'node:assert/strict';
import { test } from 'node:test';

test('metadata probe', (context) => {
	context.diagnostic(JSON.stringify({
		shortName: 'metadata-probe',
		description: 'Probe structured metadata',
	}));
	assert.equal(2 + 3, 5);
});

test('skip probe', { skip: 'Synthetic skip reason' }, () => {});
```

The built-in JUnit reporter places these diagnostics in comments following their owning test case. Blank or omitted metadata falls back to the native name; malformed unrelated diagnostic comments are ignored, and invalid metadata field types fail report validation. Descriptions appear on running rows only when distinct from the label. Completion rows contain the label and duration, while skipped rows retain the reason. Structured results preserve the original name alongside the resolved short name and description. A skipped callback does not execute, so it cannot emit diagnostics; its native name remains available as its label.

The shared PowerShell status and lifecycle formatters accept `-Child -Level 1` for children, `-Child -Level 2` for grandchildren, and so on. Every level adds two spaces. `-Child` alone defaults to level 1; `-Level` without `-Child` is rejected. Supply one `-AlignmentWidth` for the whole group so the renderer aligns `:` separators across levels. Preparation preserves its declared parent relationships, and the assistance helper receives the caller's nesting level and alignment width. The formatters do not retain an `-IndentLevel` compatibility parameter.

## Normal Operations

| Task | Command |
| --- | --- |
| Validate the complete Hosted Toolkit | `pwsh -NoProfile -File ./hosted_copilot/tools/Test-HostedRules.ps1` |
| Launch the Hosted Rule Workbench | `pwsh -NoProfile -File ./hosted_copilot/tools/Start-RuleWorkbench.ps1` |
| Plan or install the Hosted payload | `pwsh -NoProfile -File ./hosted_copilot/tools/Install-HostedRules.ps1` |
| Run or resume a controlled Hosted review | `pwsh -NoProfile -File ./hosted_copilot/tools/Invoke-HostedReview.ps1 -RepoDirectory <provider-fork> -CaseId <case-id>` |

All four normal-operation commands use the shared Hosted help renderer. Use `-Help`, `-h`, or `-Detailed` for the same curated workflow-first view on each command. PowerShell retains its native `-?` and `Get-Help` behavior. Installation defaults to a dry run.

Ordinary Workbench launch first checks CLI model availability, then refreshes static assets, validates the live GitHub identity, local CODEOWNERS membership, writable fork, and synchronization status, and serves the last jointly validated display and Rule Issues artifacts without source collection or semantic work. Availability discovery is authenticated metadata access, not an inference request. Run `pwsh -NoProfile -File ./hosted_copilot/tools/Start-RuleWorkbench.ps1 -Rebuild` when current sources must be collected and the staged artifacts regenerated. A rebuild always executes deterministic collection, cache resolution, artifact reconstruction, schema validation, and atomic publication. A displayed phase therefore does not imply a model call: its `cached` and `evaluated` counts are authoritative. Add `-Force` only when every semantic result must be reevaluated, and use `-StageOnly` to validate and publish artifacts without starting the server.

For the legacy Workbench and retained standalone commands, [config/llm.json](config/llm.json) owns model and reasoning-effort defaults. Its `default` profile supplies source assessment, baseline generation, reconciliation, rebuild-time adjudication, standalone discovery, and AI Assistance; `ruleEvaluation` supplies saved-rule reevaluation and explicit relationship review. Both legacy Workbench startup paths pass the complete validated JSON profile collection to availability checking rather than maintaining another list. Saving wording, applying published recommendations, and opening promotion preview do not automatically invoke rule evaluation. Retained standalone reconciliation tools resolve their declared profiles through the same loader. Missing or invalid configuration fails without a hidden fallback model. Existing explicit `-Model` and effort arguments retain their selected-profile behavior. Configuration takes effect on the next command or server launch; changing the file does not restage or restart an existing Workbench. The native database analysis command instead resolves versioned master-profile task assignments from its bound database; see the [database routing checkpoint](../docs/WORKBENCH_SQLITE_V1_DESIGN.md#master-profile-llm-routing-checkpoint-2026-11-06).

### CLI Availability And Installation Nuances

- Both Workbench server entrypoints require metadata preflight. The main launcher reports `LLM Availability` before staging writes, source collection, or rebuilding. Help does not invoke it; `-StageOnly` and `-SkipGitHubAuthorization` do not bypass CLI authentication or availability.
- [HostedCli.psm1](modules/shared/HostedCli.psm1) owns launch resolution and bounded headless-stdio JSON-RPC. It calls only `status.get`, `auth.getStatus`, and `models.list`; it creates no conversation and sends no prompt. Protocol 3, authenticated status, exact configured model IDs, enabled policy, and support for each selected reasoning effort are required. Missing, duplicate, disabled, or incomplete metadata fails without a silent model fallback. Catalog, authentication, and transport failures are not evidence of global model retirement.
- Metadata-preflight failures identify the query, bounded numeric CLI version/protocol when known, configured-entry ordinal, and expected field/type. Unknown values remain `unknown`; entry `0` means no configured model was reached. Error messages omit configured entry/model/effort strings, raw response/stderr, version suffixes, user paths, credentials, and personal information. Process setup uses the same sanitized boundary. Check the installed CLI's protocol-3 compatibility, the reported field, connectivity/account policy, and the applicable master-profile assignment or legacy configuration; do not paste raw authentication or diagnostic payloads into reports.
- The precheck and inference workers use the same shared resolver, normalized configured executable, inherited process environment, and `--no-auto-update` policy. An npm installation is resolved through its launcher, verified package metadata, and Node module resolution rather than guessed global directories. Explicit executable paths are supported without modifying PATH or aliases. Explicit PowerShell evaluator implementations must provide the same metadata protocol; unrecognized batch wrappers fail with executable-path guidance.
- A Windows npm PowerShell shim can interfere with an open framed stdio exchange even when ordinary prompt calls work. On 2026-10-22, the shim-based probe timed out, while direct invocation of that npm installation's platform executable returned CLI `1.0.102`, protocol `3`, authenticated status, and enabled entries supporting the configured Sol/high and Luna/medium settings. This is evidence for that installed runtime and transport, not proof of all npm versions, standalone installers, operating systems, or future CLI protocols.
- Testing the npm-bundled native executable by explicit path exercises the direct-executable launch path without installing a second CLI or changing command precedence. It does not test a standalone installer's packaging, PATH integration, or upgrade behavior. Verify those in an isolated VM or CI environment. Fixtures cover resolution and protocol behavior separately from real-installation integration.
- Availability is checked at startup, not continuously. Later account, policy, network, quota, installation, or provider changes can still fail an inference request, and successful metadata does not establish schema correctness or preservation. Restart after changing the configured CLI, profiles, or installation. The check applies to local CLI maintenance jobs, not GitHub's separately managed hosted PR-review agent, and adds no Ollama provider routing.
- Both server entrypoints force-refresh the assistance module on every launch, including restarts with `&` in an existing PowerShell terminal. Previously imported authority logic must not outlive a server restart and disagree with fresh request workers. Runtime freshness checks remain strict; a page reload is not a substitute for loading the current server module.

### Workbench Runtime Data

Assessment results are stored in the locked `%LOCALAPPDATA%\hosted-workbench\assessment-cache\assessment-cache.json` ledger. Source Assessment reuses content-addressed per-source entries after current-schema and current-input validation; use `-Force` when a behavior-authority change requires semantic reevaluation rather than compatible result reuse. Hierarchical reconciliation shards are stored beneath `%LOCALAPPDATA%\hosted-workbench\reconciliation-cache\`, and Rule Issue adjudication shards are stored beneath `%LOCALAPPDATA%\hosted-workbench\hierarchical-rule-issue-adjudication-cache\`. Reconciliation cache identity binds exact semantic content and declared behavior authority, while audit-only timestamps do not affect synthesis identity. Source Assessment and reconciliation contracts copy `presentationFiles` into retained run snapshots without treating wording, labels, timing estimates, or spacing as semantic cache authority. The staged display remains presentation state rather than semantic cache evidence or a freshness authority.

During an explicit rebuild, assessment and reconciliation run up to three cache misses concurrently, merge cached, recovered, and evaluated results deterministically, and report progress. Source Assessment shows its workload before lifecycle rows when evaluation is pending; a fully reused run reports source totals and `Execution: Fully cached` without zero-work metrics or evaluation lifecycle rows. Hierarchical reconciliation reports `Initial Assessment Grouping`, `Group Consolidation`, and `Recommendation Synthesis` as visually distinct sections; fully cached stages use the same concise execution state. Running, retrying, and failed rows identify the actual shard, while Passed rows report aggregate completed progress including cached batches, so two cached batches plus one successful evaluation ends at `batch 3/3`. Rule Issue Adjudication still derives current components and reconstructs the Rule Issues artifact on every rebuild, but cached components do not invoke the model. Summaries report cached and evaluated totals plus elapsed time, and `Workbench UI Artifact Publication` atomically publishes the candidate display and Rule Issues artifacts before the condition-aware `Workbench Summary` is rendered. Each cache update preserves validated work immediately so concurrent or interrupted Workbench processes cannot lose completed results. Failed evaluator attempts retain their draft and validation reason. Collection, assessment, reconciliation, or validation failure leaves the previous staged artifacts untouched.

Candidate Details also provides [AI Assistance](../docs/HOSTED_RULE_WORKBENCH_UI_SPEC.md#ai-assistance), using the normal model/effort profile. Each authenticated request checks the current editor wording against the full active and protected catalog snapshot with a tool-disabled local CLI. Replies are advisory and copy-only; they never save wording, select actions, or approve mutations. Save persists exact maintainer wording without AI certification, while original rebuild assessments and published Rule Issues remain evidence. Clear Conversation preserves the draft and unsent input; rule switches and reload reset the browser-only conversation. Other draft and projected Plan changes are outside its catalog context. Oversized complete prompts fail without truncation. Workbench temporary files are cleaned up, but Clear does not control the CLI provider's independent session retention.

Full icon libraries, per-family preview PNGs, manifests, legal originals, and generation code live under [internal/icons](internal/icons). Regenerate the one combined runtime sprite and all previews with `pwsh -NoProfile -File ./hosted_copilot/tools/internal/icons/New-WorkbenchSprite.ps1`; add `-SkipPreviews` when preserving existing PNGs. The [LLM inventory](internal/icons/llms/ATTRIBUTION.md) retains all 340 standard brand glyphs, while its manifest selects four for runtime. The [presentation-only branding map](../workbench/llm-brands.json) remains UI-owned. Unknown models retain the question-mark branding fallback; missing dynamic symbols show a red hatched placeholder and a tooltip naming the missing icon, without weakening required-symbol validation.

Runtime output lives under `workbench/sprite/`: one `sprite.svg`, plus each included family's original legal documents under `<family>/legal/`. Every launch stages only those files and removes obsolete launcher-owned `icons/` output. Source artwork, PNGs, manifests, assessment artifacts, unrelated site data, and caches remain untouched. `SiteDirectory` must be a physical directory outside the repository; source, destination, and legacy staged asset trees reject unsafe links or junctions. SQLite stores none of these icon assets.

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
