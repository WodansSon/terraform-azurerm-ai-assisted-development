# Workbench Browser Regression

This directory owns executable browser journeys for the Hosted Rule Workbench.

## Ownership

- `behavior-manifest.json` maps authoritative Workbench behavior IDs to executable journeys.
- `playwright/` is the target browser regression harness for user-visible workflows.
- `puppeteer/` temporarily runs the same current viewport suite while Playwright coverage is completed.
- `../../docs/HOSTED_COPILOT_CODE_REVIEW_IMPLEMENTATION.md` remains authoritative for intended behavior.
- `../../tools/Test-RuleWorkbench.ps1` remains the supported validation entrypoint.

## Behavior Changes

When Workbench behavior changes, update the authoritative implementation contract and the journey mapped to that behavior ID. Add a new behavior ID when the contract introduces a separately testable user-visible invariant.

The behavior manifest must reference an existing journey, and each journey must declare exactly the behavior IDs assigned to it. The Playwright runner rejects missing, duplicate, stale, or mismatched mappings.

## Framework Transition

Both frameworks execute `shared/WorkbenchViewportSuite.cjs`, and validation requires identical assertion and viewport totals. Playwright is the target harness; remove the temporary Puppeteer consumer after behavior ownership fully moves to Playwright.

## Validation

Run the complete Workbench suite:

```powershell
pwsh -NoProfile -File ./hosted_copilot/tools/Test-RuleWorkbench.ps1
```

The Hosted Toolkit profile invokes the same suite through `Test-Toolkit.ps1`.

## Visible Playback

Start an owned Workbench, watch all Playwright journeys, and verify shutdown and cleanup:

```powershell
pwsh -NoProfile -File ./hosted_copilot/tools/Test-RuleWorkbenchHeaded.ps1
```

Use `-TestCase all` to play the complete suite explicitly, `-TestCase candidate-decorations` to play one journey, `-SlowMo 500` to change the per-action delay, or `-Port 43167` to select another available owned port. `-Journey` is an equivalent alias for `-TestCase`. Headed viewport playback resizes the visible Chromium window for every tested width, continues through every width when a checkpoint fails, and prints both frame and viewport dimensions. Owned playback fails when the selected port is occupied, clicks **Close Workbench** after the final journey, verifies the self-contained closed screen and stopped server, and removes its temporary staging directory even when playback fails.

The manifest-owned `browser-zoom` journey uses Chrome's real per-tab zoom API at `100%`, `125%`, `150%`, and `200%` in one fixed large Workbench window. It verifies that the CSS viewport shrinks from `1920x900` to `960x450` while the physical window remains fixed and the Workbench avoids clipping, overlap, page-level overflow, and unsupported-device fallback.

Use `-Url http://127.0.0.1:43165/` only to attach to an existing Workbench. Attach mode verifies the Workbench identity but does not shut down or remove resources it does not own.
