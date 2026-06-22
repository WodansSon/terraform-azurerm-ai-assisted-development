# AI Toolkit Alignment Checklist

This checklist is for maintainers of this repository.

Use it when you want to answer questions like:

- Is the AI toolkit up to date?
- Did we wire a new contract family completely?
- Does bootstrap/install include the right runtime payload?
- Did we update the docs that explain the current rule model?

For repo-level customization layering, migration sequencing, and regression-safe modernization of prompts, instructions, skills, and agents, also consult:

- `docs/AI_CUSTOMIZATION_ARCHITECTURE_STANDARD.md`

This is a maintenance checklist for this repository only. It is not part of the runtime toolkit that gets installed into target repositories.

## Repo-Only Maintenance Skills

This repository also includes repo-only maintainer skills:

- `.github/skills/ai-toolkit-maintenance/SKILL.md`
- `.github/skills/changelog-maintenance/SKILL.md`

Use them when you want the agent to run repository-maintainer workflows for you.

Example invocations:

- `/ai-toolkit-maintenance check whether the AI toolkit is up to date`
- `/ai-toolkit-maintenance run the alignment checklist for the current branch`
- `/ai-toolkit-maintenance validate that the changed files complete the alignment checklist`
- `/ai-toolkit-maintenance check whether this file should be runtime payload or repo-only`
- `/changelog-maintenance update the changelog for the current branch`
- `/changelog-maintenance prepare the next release section from Unreleased`
- `/changelog-maintenance normalize the Unreleased entries to the approved taxonomy`

Notes:

- These skills are repo-only and should not be added to `installer/file-manifest.config`.
- If the request is "is the AI toolkit up to date?" and upstream contributor alignment is relevant, the skill should run `tools/check-upstream-contributor-drift.ps1` as part of the workflow and report the result.
- If the slash command does not appear immediately in VS Code, reload the window and try again.

## Upstream Contributor Sources

When local AI guidance is meant to align with the upstream HashiCorp contributor docs, use the repo-only source map at:

- `tools/config/upstream-contributor.json`

That file stores tracked upstream contributor source baselines under `hashicorp/terraform-provider-azurerm/contributing/topics/`.

Tracked-source baselines live in that file, but local topic-to-file and topic-to-rule relationships should be derived dynamically by the drift checker from exact upstream topic references already present in repo files and rule evidence blocks.

Use `https://github.com/hashicorp/terraform-provider-azurerm/tree/main/contributing` as the canonical remote contributor-doc root when comparing local installer-repo references to upstream docs.

## Current Contract Families

The current contract-driven domains are:

- `.github/instructions/code-review-compliance-contract.instructions.md`
- `.github/instructions/docs-compliance-contract.instructions.md`
- `.github/instructions/implementation-compliance-contract.instructions.md`
- `.github/instructions/testing-compliance-contract.instructions.md`

## Current High-Signal Implementation Rule

The current implementation guidance explicitly treats Azure resource IDs as a case-insensitive read problem and a canonical-write problem:

- read, import, refresh, and migration paths should parse resource IDs through the shared typed parser instead of relying on raw string equality against Azure-returned IDs
- provider-managed IDs written back to state should use the parser's canonical `.ID()` form instead of preserving arbitrary casing returned by the RP

This is meant to reduce Terraform phantom diffs and lookup failures caused by Azure static-segment casing drift.

## Alignment Checklist

### 1. Contract structure is valid

For each changed or new `*-contract.instructions.md` file, confirm it still has:

- Frontmatter
- `## Consumers`
- `## Canonical sources of truth (precedence)`
- `Conflict resolution:`
- `## Rule IDs`
- `## Evidence hierarchy`
- A contract EOF marker comment as the last non-empty line

If the contract uses provenance, only use supported labels:

- `Published upstream standard`
- `Inferred maintainer convention`
- `Local safeguard`

Within a letter-suffixed sibling rule family such as `REVIEW-SCOPE-005A` and `REVIEW-SCOPE-005B`:

- Keep sibling rule headings ordered by full rule ID.
- Do not renumber existing rules solely to improve ordering.
- If ordering drift is found while touching that family, fix it before publishing the repo package.

### 2. Consumer files are aligned to the contract

For every declared consumer in a contract:

- The file exists
- The file references the contract path
- Any consumer marked `Requires EOF Load: yes` explicitly mentions loading the contract to EOF

Typical consumers include:

- Prompts in `.github/prompts/`
- Skills in `.github/skills/`
- Routing instructions in `.github/instructions/ai-skill-routing-*.instructions.md`

### 3. Companion guidance points back to the contract

If a contract declares companion guidance, each companion file should:

- Explicitly state that it is companion guidance
- Point back to the contract path
- Defer compliance authority to the contract instead of acting as a second authority source

### 3A. Runtime guidance examples stay generic

For runtime guidance under `.github/copilot-instructions.md`, `.github/instructions/`, and `.github/skills/`:

- Prefer generic placeholders such as `{{RESOURCE_NAME}}`, `{{FIELD_NAME}}`, and `{{SERVICE_NAME}}` for broad rules and worked patterns
- Avoid concrete resource-specific examples when the rule is meant to generalize across the provider
- Keep concrete resource names only when they are part of intentional evidence, a regression fixture, or a dedicated examples document

### 4. Rule-reference and architecture documentation is still accurate

Update `docs/CODE_REVIEW_RULES.md` when either of these happens:

- A new contract family is added
- A new rule area is introduced that is useful for end users to understand

You do not need to update it for every new individual rule inside an already-documented area.

Update repo-only architecture and maintainer reference docs when the repository's customization layout or responsibilities materially change, for example:

- `docs/ARCHITECTURE.md` when the repo structure, runtime payload, or repo-only maintenance tooling model changes
- `docs/AI_CUSTOMIZATION_ARCHITECTURE_STANDARD.md` when the contract, routing, prompt, skill, or payload-boundary direction changes
- `docs/AI_REGRESSION_HARNESS.md` when the harness entrypoints, scoring flow, or maintainer benchmark model changes materially

### 5. Runtime payload and maintenance tooling stay separated

When a new file is added, decide whether it is:

- Runtime toolkit payload
- Repo-maintenance-only tooling

Runtime toolkit payload belongs in `installer/file-manifest.config` if it must be copied into target repositories.

Typical runtime payload files:

- `.github/copilot-instructions.md`
- `.github/instructions/**`
- `.github/prompts/**`
- `.github/skills/**`
- `.vscode/settings.json`

Typical maintenance-only files that should stay out of the installed payload:

- `tools/config/upstream-contributor.json`
- `tools/validate-ai-toolkit.ps1`
- `tools/validate-changelog-taxonomy.ps1`
- `tools/validate-contracts.ps1`
- `tools/check-upstream-contributor-drift.ps1`
- `.github/workflows/contracts-validation.yml`
- `.github/skills/ai-toolkit-maintenance/SKILL.md`
- `.github/skills/changelog-maintenance/SKILL.md`
- Repo-only maintenance checklists like this file

### 6. Changelog and release docs are aligned

When the runtime toolkit changes in a user-visible way:

- Update `CHANGELOG.md`
- If the change affects release or maintenance expectations, update `.github/workflows/RELEASING.md` when needed

For new `CHANGELOG.md` entries under `## [Unreleased]`:

- Use grouped top-level bullets when a subsection has entries:
	- `- **User-Priority:**`
	- `- **Maintainer/Workflow:**`
- Put actual changelog entries under those groups as nested bullets in the form `  - **[Taxonomy]** - entry`
- Approved taxonomy tags are `[Review]`, `[Docs]`, `[Implementation]`, `[Testing]`, `[Installer]`, `[Skill Routing]`, and `[Internal]`
- Use the fixed display order inside each subsection: `[Review]`, `[Docs]`, `[Installer]`, then `[Implementation]`, `[Testing]`, `[Skill Routing]`, `[Internal]`
- Treat `[Review]`, `[Docs]`, and `[Installer]` as the user-priority group
- Treat `[Implementation]`, `[Testing]`, `[Skill Routing]`, and `[Internal]` as the maintainer/workflow group
- If both groups appear in the same `Added`, `Changed`, or `Fixed` subsection, insert exactly one blank line between the two top-level group bullets
- If only one group appears in a subsection, do not emit the empty group and do not add a separator blank line just for formatting
- Prefer the user-facing capability tag over `[Internal]` when the change materially affects end-user behavior
- Use `[Internal]` for repo-only harness, validation, scaffolding, or maintainer workflow changes
- Do not churn older release sections just to retrofit taxonomy unless that is the explicit task
- Preserve the repo's current changelog shape: `Unreleased` plus empty `Added`, `Changed`, and `Fixed` headings when those sections have no entries

### 7. Validation passes

Preferred one-shot maintainer validation:

```powershell
pwsh -NoProfile -File ./tools/validate-ai-toolkit.ps1
```

That command runs the current repo-level maintainer validation flow in one pass:

- Explicit changelog-decision validation for current branch changes
- Changelog taxonomy validation for `Unreleased` entries
- Contract validation
- Markdown lint for `.github/`, `docs/`, and `CHANGELOG.md`
- Regression harness validation and suite scoring
- Upstream contributor drift detection

If the current branch intentionally does not need a changelog entry, make that explicit instead of relying on path-based inference:

```powershell
pwsh -NoProfile -File ./tools/validate-ai-toolkit.ps1 -ChangelogNotRequired -ChangelogReason "Repo-only maintenance change with no release-note impact"
```

When you need the machine-readable summary:

```powershell
pwsh -NoProfile -File ./tools/validate-ai-toolkit.ps1 -OutputFormat Json
```

If you intentionally want the summary without failing on unresolved upstream drift:

```powershell
pwsh -NoProfile -File ./tools/validate-ai-toolkit.ps1 -AllowDrift
```

If you want CI-style behavior that still fails on changed tracked sources or rule issues but tolerates the currently known uncovered topic catalog gaps:

```powershell
pwsh -NoProfile -File ./tools/validate-ai-toolkit.ps1 -AllowCatalogIssues
```

The lower-level commands remain available for debugging and targeted re-runs.

Run:

```powershell
pwsh -NoProfile -File ./tools/validate-changelog-taxonomy.ps1
```

```powershell
pwsh -NoProfile -File ./tools/validate-contracts.ps1
```

When local AI guidance is meant to stay aligned with upstream HashiCorp contributor docs, also run:

```powershell
pwsh -NoProfile -File ./tools/check-upstream-contributor-drift.ps1
```

Use JSON output if you want the machine-readable report:

```powershell
pwsh -NoProfile -File ./tools/validate-contracts.ps1 -OutputFormat Json
```

```powershell
pwsh -NoProfile -File ./tools/check-upstream-contributor-drift.ps1 -OutputFormat Json
```

The JSON report now groups dynamically discovered rule coverage by local file as well as by upstream source, so you can review provenance and evidence gaps contract-by-contract instead of only source-by-source.

The drift checker is intentionally deterministic. It detects upstream source changes plus local provenance/evidence gaps using pure logic only, and it derives local mappings only from exact upstream topic references already present in repo files and rule evidence blocks. It does not use heuristics and it does not decide whether an upstream wording change is semantically meaningful. Exact-reference aggregation only proves links that already exist explicitly in repo content; it is not the semantic mapping step. When the report shows changed sources, uncovered upstream topics, tracked topics without explicit local references, dynamically mapped untracked topics, stale tracked topics, stale local topic references, or rule issues, follow it with an AI-assisted semantic maintainer review before changing local guidance.

The same applies to topic-catalog drift: if the report shows uncovered upstream topics, dynamically mapped untracked topics, stale tracked topics, or stale local topic references, treat that as a maintainer review event and decide whether the manifest or local guidance needs to change.

If the drift check reports upstream changes, review the mapped local consumers in `tools/config/upstream-contributor.json` and update any conflicting local rules while preserving verified local tribal knowledge that still does not conflict with upstream guidance.

When rule-level mappings exist, use the drift report to review the current provenance label and evidence bullets for each mapped rule ID before changing the rule text.

If the current file contents and workspace validators are clean but the VS Code Problems tab still shows old YAML errors, treat them as potentially stale editor diagnostics before assuming the workflow is still broken.

Practical recovery step:

- Reload the VS Code window so the YAML language service rebuilds diagnostics from the current on-disk files

### 8. Bootstrap payload matches expectations

When the runtime payload changes, confirm bootstrap/install copies the expected runtime files from the manifest and does not accidentally include maintenance tooling.

At a minimum, verify that:

- New runtime contracts are copied
- New or updated routing instructions are copied
- Updated skills are copied
- Maintenance-only scripts are not copied into target repositories

### 9. Avoid known formatting and validation traps

When maintaining AI-toolkit support docs and checklists in this repository:

- Prefer flat bullet lists over numbered lists when the exact sequence is not important
- Avoid adding ordered lists just for presentation symmetry
- If a document is intended to be machine-read, copied into prompts, or reused in validation-sensitive contexts, favor simpler Markdown structures

Standard authoring pattern for AI-toolkit files:

- Use titled subsections to express the major stages or categories
- Use flat or nested bullets under each title to express the concrete guidance
- Let heading order and bullet indentation convey sequence instead of explicit numbering
- Treat this as the default pattern for `.github/skills/`, `.github/prompts/`, and `.github/instructions/`

This is a practical safeguard. The CI/CD pipeline validates Markdown with `DavidAnson/markdownlint-cli2-action@v18`, and we have previously hit `MD029` failures in AI-toolkit files.

Known failure pattern:

- Multiple top-level ordered lists under the same section that each restart at `1.`
- Mixed ordered-list numbering styles that make markdownlint treat the numbering as inconsistent

Practical rule:

- If the content is just a set of guidance bullets, use unordered lists
- If you truly need an ordered list, keep one consistent ordered-list sequence instead of creating multiple sibling ordered lists that each restart at `1.`
- Prefer titled subsections plus bullets for procedural guidance, letting heading order and bullet indentation convey sequence without explicit numbering

Pay extra attention to files under:

- `.github/skills/`
- `.github/prompts/`
- `.github/instructions/`

If one of those files uses ordered lists only for presentation, flatten it to bullets.

Local pre-check equivalent:

```powershell
npx -y markdownlint-cli2 ".github/**/*.md" "docs/**/*.md" --config .github/.markdownlint.json
```

## Quick “Is Everything Up To Date?” Answer Flow

When asked whether the AI toolkit is up to date, check these in order:

- `pwsh -NoProfile -File ./tools/validate-ai-toolkit.ps1` passes.
- `installer/file-manifest.config` includes all required runtime payload files.
- `docs/CODE_REVIEW_RULES.md` still matches the current contract families and rule areas.
- Repo-only architecture and benchmark docs still describe the current layout and maintainer workflow shape.
- `CHANGELOG.md` reflects the current release state.
- No new contract, skill, prompt, or companion file was added without corresponding alignment updates.

If all six are true, the toolkit is usually aligned enough to answer “yes” with confidence.
