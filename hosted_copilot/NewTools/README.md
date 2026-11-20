# New Hosted Rule Workbench

This is the isolated, temporary successor to the legacy Workbench. Work on the new implementation here; keep the legacy runtime unchanged as a behavioral reference until an explicitly approved cutover.

## Source Owners

- [NewWorkbench](../NewWorkbench/) owns the client.
- [workbench](../workbench/) owns the shared favicon, assistance waiting phrases, and LLM branding map.
- [NewTools](./) owns its launcher, backend, prompts, model configuration, and tests.
- [NewContracts](../NewContracts/) owns its independent workflow schemas and evaluator contracts.
- [tools/internal/icons](../tools/internal/icons/) owns the shared icon inventory, manifests, legal originals, previews, and generator; [workbench/sprite](../workbench/sprite/) owns their single generated runtime payload, validated by the shared [icon runtime schema](../contracts/workbench/icon-runtime.schema.json).
- [NewCopilotRuleCatalog/source-definitions](../NewCopilotRuleCatalog/source-definitions/) owns its source-intake configuration.
- [NewRegression](../NewRegression/workbench/) owns its browser journeys.
- [NewDocs](../NewDocs/HOSTED_RULE_WORKBENCH_UI_SPEC.md) owns the copied UI specification with the implemented prototype changes.

The existing published catalog, protected rules, and source guidance remain read-only inputs. They are not duplicated into a competing published catalog. Application implementations, prompts, workflow schemas, and mutable state stay separate. Both Workbenches consume the same npm toolchain, icon workflow, and settled static assets.

## Shared Dependencies

Both Workbench implementations use the single pinned npm manifest, lockfile, and installed packages in [tools/npm](../tools/npm/). Browser runners, icon-preview rendering, and validation use that shared toolchain without sharing application code or saved state. Keep this tooling when archiving the legacy Workbench; do not create a second npm installation for the new implementation.

The [favicon](../workbench/favicon.svg), [assistance waiting phrases](../workbench/assistance-waiting-phrases.json), and [LLM branding map](../workbench/llm-brands.json) remain at their existing Workbench paths. New's launcher and browser fixtures stage those exact files into its separate site under unchanged relative URLs. Do not retain duplicate New source copies or move these shared assets when archiving legacy application code.

## Launch

```powershell
pwsh -NoProfile -File .\hosted_copilot\NewTools\Start-RuleWorkbench.ps1
```

The default origin is `http://127.0.0.1:43157/`. Staged assets and caches use separate `hosted-new-workbench` locations. IndexedDB and the active-session key use `hosted-rule-new-workbench`; no legacy draft is imported or migrated.

An empty site requires an explicit `-Rebuild` or `-DisplaySourceDirectory` containing the two validated display artifacts. The latter copies no browser decisions or runtime credentials. Do not select the legacy site as `-SiteDirectory`, reuse its port, or overwrite its assets.

## Validation

```powershell
pwsh -NoProfile -File .\hosted_copilot\NewTools\tests\Test-RuleWorkbench.ps1
node --test .\hosted_copilot\NewTools\tests\new-workbench.test.mjs .\hosted_copilot\NewTools\tests\workbench-editing.test.mjs
pwsh -NoProfile -File .\hosted_copilot\NewTools\tests\Test-RuleWorkbench.ps1 -Run browser-playwright-journeys -Journey manual-rule-editing,maintainer-consolidation,relationship-review,storage-isolation
pwsh -NoProfile -File .\hosted_copilot\NewTools\tests\Test-RuleWorkbench.ps1 -Run relationship-production-server
pwsh -NoProfile -File .\hosted_copilot\NewTools\tests\Test-RuleWorkbench.ps1 -Run rule-assistance
```

The prototype port preserves explicit acceptance, atomic decision saves, protected rules, stale-write checks, and separate publication validation. It does not initialize SQL, migrate saved work, publish catalog changes, or archive the legacy runtime. The retained prior SQL implementation is not part of this copy.

The complete suite must pass both browser frameworks, their coverage parity check, backend checks, and authenticated shutdown. Focused journey passes do not replace this gate. Browser readiness fixtures complete required relationship checks with the existing offline evaluator or complete request-bound mocks; runtime refreshes retain the synthetic CODEOWNER identity. Capacity assertions use the policy-bound fixture, including reserved guidance, rather than obsolete fixed limits. Visual checks retain normal motion and wait for real paint or animation completion.

The mixed-sibling lifecycle journey restores earlier wording, verifies that stale evidence cannot establish readiness, and completes a fresh explicit check through the actual backend with the offline evaluator. It checks the outgoing wording, new request identity, persisted result, and readiness while preserving the other sibling's pending state. This does not establish live-model semantic correctness.

## Status-Bar Icon Assets

New's status bar uses a 28px row, 12px text with a 16px line height, and 16px icon slots. The shell and narrow assistance drawer follow the shared status-height variable; toasts retain 4px clearance above the bar. The approval slot reserves enough fixed width for Draft, Ready, and Blocked without shifting adjacent entries.

The shared [runtime sprite](../workbench/sprite/sprite.svg) supplies these native 16px variants:

| Meaning | Sprite symbol |
| --- | --- |
| Branch | `codicon-git-branch` |
| Warning | `codicon-warning` |
| Excluded | `codicon-circle-slash` |
| Mapped | `fluent-link-multiple-16-regular` |
| Not Mapped | `fluent-link-dismiss-16-regular` |
| Promotion Approval | `codicon-shield` |

The source artwork and family runtime selections live in the shared [tools/internal/icons](../tools/internal/icons/) workflow. Regenerate its single sprite and complete source-inventory previews with:

```powershell
pwsh -NoProfile -File .\hosted_copilot\tools\internal\icons\New-WorkbenchSprite.ps1
```

Both launchers and their browser fixtures stage this same sprite and its manifest-owned legal notices into separate sites; there is no New icon inventory, generator, schema, or generated sprite copy. New's [statusbar.js](../NewWorkbench/statusbar.js) selects the icons above, while its [styles.css](../NewWorkbench/styles.css) owns sizing. Legacy retains its independent selections and styling.
