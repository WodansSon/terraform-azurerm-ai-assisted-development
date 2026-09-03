# Hosted Copilot Code Review:

This repository uses compact, path-specific instructions for GitHub Copilot code review. The Hosted Toolkit is deployed directly from a pinned source commit of `terraform-azurerm-ai-assisted-development`; it is independent from that project's Interactive Toolkit and installer.

## Installed Files:

- `.github/copilot-instructions.md` defines the required review procedure, finding threshold, evidence order, feedback shape, and customization trust boundary used for every review.
- `.github/instructions/azurerm-go.instructions.md` defines Go implementation review rules for `internal/**/*.go`.
- `.github/instructions/azurerm-tests.instructions.md` supplements the Go rules with acceptance-test review requirements for `internal/**/*_test.go`.
- `.github/instructions/azurerm-docs.instructions.md` defines documentation review rules for `website/docs/**/*.html.markdown`.
- `.github/skills/code-review/SKILL.md` defines the compact review procedure required for every review, including the complete contributor-guide read that precedes any finding.
- `docs/HOSTED_COPILOT_CODE_REVIEW.md` provides this operating reference.
- `.github/hosted-copilot-installed-state.json` records package ownership, source commit, and installed hashes after deployment.

## Source Maintenance:

The source repository keeps path-specific rules in `hosted_copilot/copilot-rule-catalog/instruction-catalog.json`. The catalog preserves published upstream standards, maintainer conventions, and local safeguards as separate provenance classes. Generated files under `hosted_copilot/.github/instructions/` must not be edited directly.

Check generated-file freshness without writing:

```powershell
pwsh -NoProfile -File ./hosted_copilot/tools/Generate-Instructions.ps1
```

After approving a catalog change, regenerate explicitly with `-Write`. Check cited HashiCorp contributor sources independently with:

```powershell
pwsh -NoProfile -File ./hosted_copilot/tools/Test-UpstreamSources.ps1 -FailOnDrift
```

Source drift never updates the catalog automatically. Review changed meaning before changing rule text or accepting a new baseline. Missing upstream coverage does not weaken confirmed or inferred maintainer conventions.

## Deployment:

Run the installer from the source checkout and pass the target repository explicitly:

```powershell
pwsh -NoProfile -File ./hosted_copilot/tools/Install-Toolkit.ps1 `
  -RepoDirectory C:\path\to\terraform-provider-azurerm
```

The default operation is a dry run. Review every reported addition, update, owned modification, and unowned collision before installing.

Install the approved plan with:

```powershell
pwsh -NoProfile -File ./hosted_copilot/tools/Install-Toolkit.ps1 `
  -RepoDirectory C:\path\to\terraform-provider-azurerm `
  -Install
```

Use `-Force` only after reviewing a reported unowned collision or a locally modified package-owned file. The installer merges owned files into existing directories and does not replace unrelated `.github/`, `docs/`, or `tools/` content.

## Validation:

Validate the Hosted source package with:

```powershell
pwsh -NoProfile -File ./hosted_copilot/tools/Test-Toolkit.ps1
```

The validator reports each check as `RUNNING`, `PASSED`, `FAILED`, or `SKIPPED`, and enforces runtime layout, catalog schema and freshness, upstream drift, manifest ownership, deployment-time hashing, frontmatter, per-surface and cumulative guidance budgets, installer dry-run safety, and test-case integrity. Use `-SkipUpstreamDrift` only for explicit offline diagnosis.

## Repository Settings:

- Enable custom instructions for GitHub Copilot code review.
- Commit the installed files on the pull request head branch because Hosted review reads customization from that branch.
- Select and record the same review effort for controlled comparisons.
- Treat the model selected by GitHub as observed metadata, not as a controllable experiment input.
