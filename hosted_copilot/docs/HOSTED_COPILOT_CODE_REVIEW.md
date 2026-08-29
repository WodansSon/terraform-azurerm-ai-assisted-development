# Hosted Copilot Code Review:

This repository uses compact, path-specific instructions for GitHub Copilot code review. The Hosted Toolkit is deployed directly from a pinned source commit of `terraform-azurerm-ai-assisted-development`; it is independent from that project's Interactive Toolkit and installer.

## Installed Files:

- `.github/copilot-instructions.md` defines the finding threshold, evidence order, feedback shape, and customization trust boundary used for every review.
- `.github/instructions/azurerm-go.instructions.md` defines Go implementation review rules for `internal/**/*.go`.
- `.github/instructions/azurerm-tests.instructions.md` supplements the Go rules with acceptance-test review requirements for `internal/**/*_test.go`.
- `.github/instructions/azurerm-docs.instructions.md` defines documentation review rules for `website/docs/**/*.html.markdown`.
- `.github/skills/code-review/SKILL.md` defines the compact review procedure GitHub may load when relevant.
- `docs/HOSTED_COPILOT_CODE_REVIEW.md` provides this operating reference.
- `.github/hosted-copilot-installed-state.json` records package ownership, source commit, and installed hashes after deployment.

## Deployment:

Run the installer from the source checkout and pass the target repository explicitly:

```powershell
pwsh -NoProfile -File ./hosted_copilot/tools/hosted-copilot/Install-HostedCopilot.ps1 `
  -RepoDirectory C:\path\to\terraform-provider-azurerm
```

The default operation is a dry run. Review every reported addition, update, owned modification, and unowned collision before installing.

Install the approved plan with:

```powershell
pwsh -NoProfile -File ./hosted_copilot/tools/hosted-copilot/Install-HostedCopilot.ps1 `
  -RepoDirectory C:\path\to\terraform-provider-azurerm `
  -Install
```

Use `-Force` only after reviewing a reported unowned collision or a locally modified package-owned file. The installer merges owned files into existing directories and does not replace unrelated `.github/`, `docs/`, or `tools/` content.

## Validation:

Validate the Hosted source package with:

```powershell
pwsh -NoProfile -File ./hosted_copilot/tools/hosted-copilot/Test-HostedToolkit.ps1
```

The validator reports each check as `RUNNING`, `PASSED`, `FAILED`, or `SKIPPED`, and enforces runtime layout, manifest ownership, hashes, frontmatter, per-surface and cumulative guidance budgets, installer dry-run safety, and test-case integrity.

## Repository Settings:

- Enable custom instructions for GitHub Copilot code review.
- Commit the installed files on the pull request head branch because Hosted review reads customization from that branch.
- Select and record the same review effort for controlled comparisons.
- Treat the model selected by GitHub as observed metadata, not as a controllable experiment input.
