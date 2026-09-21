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
pwsh -NoProfile -File ./hosted_copilot/tools/tests/Test-RuleWorkbench.ps1
```

Run any reported subtest independently by passing its exact name to `-Run`:

```powershell
pwsh -NoProfile -File ./hosted_copilot/tools/tests/Test-RuleWorkbench.ps1 -Run local-icon-family-sprites
```

Focused execution always runs the Hosted npm security audit and verifies the installed package graph against the audited lockfile. The harness then runs only the requested subtest and its required staging, browser-runtime, or loopback-server prerequisites. The focused-run catalog is checked against every reported test name so newly added tests cannot silently become full-suite-only.

Run one Playwright journey with the same owned synthetic fixture and server lifecycle:

```powershell
pwsh -NoProfile -File ./hosted_copilot/tools/tests/Test-RuleWorkbench.ps1 -Run browser-playwright-journeys -Journey promotion-preview-review
```

Add the valueless `-Headed` switch to watch the selected Playwright journey:

```powershell
pwsh -NoProfile -File ./hosted_copilot/tools/tests/Test-RuleWorkbench.ps1 -Run browser-playwright-journeys -Journey promotion-preview-review -Headed
```

Omit `-Journey` to watch the complete Playwright journey suite:

```powershell
pwsh -NoProfile -File ./hosted_copilot/tools/tests/Test-RuleWorkbench.ps1 -Run browser-playwright-journeys -Headed
```

Use `-Journey` and `-Headed` only with `-Run browser-playwright-journeys`. Omitting `-Headed` keeps execution headless, and omitting `-Journey` runs every Playwright journey. Browser-backed focused runs install or verify their locked runtime automatically; static checks do not launch a browser or loopback server.

The Hosted Toolkit profile invokes the same suite through `Test-HostedRules.ps1`.

## Visible Playback

Use the normal Playwright journey test with `-Headed`. It retains the audited dependencies, owned random-port Workbench, synthetic fixture, authenticated shutdown, result checks, and temporary cleanup used by headless validation. Headed viewport playback resizes the visible Chromium window for every tested width, continues through every width when a checkpoint fails, and prints both frame and viewport dimensions.

The manifest-owned `browser-zoom` journey uses Chrome's real per-tab zoom API at `100%`, `125%`, `150%`, and `200%` in one fixed large Workbench window. It verifies that the CSS viewport shrinks from `1920x900` to `960x450` while the physical window remains fixed and the Workbench avoids clipping, overlap, page-level overflow, and unsupported-device fallback.
