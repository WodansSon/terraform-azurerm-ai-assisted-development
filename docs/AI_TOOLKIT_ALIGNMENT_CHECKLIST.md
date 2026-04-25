# AI Toolkit Alignment Checklist

This checklist is for maintainers of this repository.

Use it when you want to answer questions like:

- is the AI toolkit up to date?
- did we wire a new contract family completely?
- does bootstrap/install include the right runtime payload?
- did we update the docs that explain the current rule model?

This is a maintenance checklist for this repository only. It is not part of the runtime toolkit that gets installed into target repositories.

## Repo-Only Maintenance Skill

This repository also includes a repo-only maintainer skill:

- `.github/skills/ai-toolkit-maintenance/SKILL.md`

Use it when you want the agent to run this checklist-oriented maintenance workflow for you.

Example invocations:

- `/ai-toolkit-maintenance check whether the AI toolkit is up to date`
- `/ai-toolkit-maintenance run the alignment checklist for the current branch`
- `/ai-toolkit-maintenance validate that the changed files complete the alignment checklist`
- `/ai-toolkit-maintenance check whether this file should be runtime payload or repo-only`

Notes:

- This skill is repo-only and should not be added to `installer/file-manifest.config`.
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

## Alignment Checklist

### 1. Contract structure is valid

For each changed or new `*-contract.instructions.md` file, confirm it still has:

- frontmatter
- `## Consumers`
- `## Canonical sources of truth (precedence)`
- `Conflict resolution:`
- `## Rule IDs`
- `## Evidence hierarchy`
- a contract EOF marker comment as the last non-empty line

If the contract uses provenance, only use supported labels:

- `Published upstream standard`
- `Inferred maintainer convention`
- `Local safeguard`

### 2. Consumer files are aligned to the contract

For every declared consumer in a contract:

- the file exists
- the file references the contract path
- any consumer marked `Requires EOF Load: yes` explicitly mentions loading the contract to EOF

Typical consumers include:

- prompts in `.github/prompts/`
- skills in `.github/skills/`
- routing instructions in `.github/instructions/ai-skill-routing-*.instructions.md`

### 3. Companion guidance points back to the contract

If a contract declares companion guidance, each companion file should:

- explicitly state that it is companion guidance
- point back to the contract path
- defer compliance authority to the contract instead of acting as a second authority source

### 4. Rule-reference documentation is still accurate

Update `docs/CODE_REVIEW_RULES.md` when either of these happens:

- a new contract family is added
- a new rule area is introduced that is useful for end users to understand

You do not need to update it for every new individual rule inside an already-documented area.

### 5. Runtime payload and maintenance tooling stay separated

When a new file is added, decide whether it is:

- runtime toolkit payload
- repo-maintenance-only tooling

Runtime toolkit payload belongs in `installer/file-manifest.config` if it must be copied into target repositories.

Typical runtime payload files:

- `.github/copilot-instructions.md`
- `.github/instructions/**`
- `.github/prompts/**`
- `.github/skills/**`
- `.vscode/settings.json`

Typical maintenance-only files that should stay out of the installed payload:

- `tools/config/upstream-contributor.json`
- `tools/validate-contracts.ps1`
- `tools/check-upstream-contributor-drift.ps1`
- `.github/workflows/contracts-validation.yml`
- `.github/skills/ai-toolkit-maintenance/SKILL.md`
- repo-only maintenance checklists like this file

### 6. Changelog and release docs are aligned

When the runtime toolkit changes in a user-visible way:

- update `CHANGELOG.md`
- if the change affects release or maintenance expectations, update `.github/workflows/RELEASING.md` when needed

### 7. Validation passes

Run:

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

- reload the VS Code window so the YAML language service rebuilds diagnostics from the current on-disk files

### 8. Bootstrap payload matches expectations

When the runtime payload changes, confirm bootstrap/install copies the expected runtime files from the manifest and does not accidentally include maintenance tooling.

At a minimum, verify that:

- new runtime contracts are copied
- new or updated routing instructions are copied
- updated skills are copied
- maintenance-only scripts are not copied into target repositories

### 9. Avoid known formatting and validation traps

When maintaining AI-toolkit support docs and checklists in this repository:

- prefer flat bullet lists over numbered lists when the exact sequence is not important
- avoid adding ordered lists just for presentation symmetry
- if a document is intended to be machine-read, copied into prompts, or reused in validation-sensitive contexts, favor simpler Markdown structures

Standard authoring pattern for AI-toolkit files:

- use titled subsections to express the major stages or categories
- use flat or nested bullets under each title to express the concrete guidance
- let heading order and bullet indentation convey sequence instead of explicit numbering
- treat this as the default pattern for `.github/skills/`, `.github/prompts/`, and `.github/instructions/`

This is a practical safeguard. The CI/CD pipeline validates Markdown with `DavidAnson/markdownlint-cli2-action@v18`, and we have previously hit `MD029` failures in AI-toolkit files.

Known failure pattern:

- multiple top-level ordered lists under the same section that each restart at `1.`
- mixed ordered-list numbering styles that make markdownlint treat the numbering as inconsistent

Practical rule:

- if the content is just a set of guidance bullets, use unordered lists
- if you truly need an ordered list, keep one consistent ordered-list sequence instead of creating multiple sibling ordered lists that each restart at `1.`
- prefer titled subsections plus bullets for procedural guidance, letting heading order and bullet indentation convey sequence without explicit numbering

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

- `pwsh -NoProfile -File ./tools/validate-contracts.ps1` passes.
- `pwsh -NoProfile -File ./tools/check-upstream-contributor-drift.ps1` reports no unresolved upstream-doc drift for the tracked sources you rely on.
- `installer/file-manifest.config` includes all required runtime payload files.
- `docs/CODE_REVIEW_RULES.md` still matches the current contract families and rule areas.
- `CHANGELOG.md` reflects the current release state.
- No new contract, skill, prompt, or companion file was added without corresponding alignment updates.

If all five are true, the toolkit is usually aligned enough to answer “yes” with confidence.
