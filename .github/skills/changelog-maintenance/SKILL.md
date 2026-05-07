---
name: changelog-maintenance
description: Maintain this repository's changelog taxonomy, entry wording, and release-section structure. Use when adding or editing CHANGELOG.md entries, preparing a release section, or normalizing changelog entries to the repo taxonomy.
---

# Changelog Maintenance

## Scope

This skill is for maintainers of this repository only.

Use it when:

- adding or updating `CHANGELOG.md` entries for current branch changes
- preparing a release section from `Unreleased`
- applying or correcting changelog taxonomy prefixes
- checking whether changelog wording is user-facing enough
- keeping the repo changelog shape consistent over time

This skill is intentionally repo-only. It is not part of the shipped runtime toolkit and should not be added to `installer/file-manifest.config`.

## Canonical sources of truth

When maintaining the changelog in this repository, use these sources in this order:

- `CHANGELOG.md`
- `docs/AI_TOOLKIT_ALIGNMENT_CHECKLIST.md`
- `.github/pull_request_template.md`
- `tools/validate-ai-toolkit.ps1`
- `tools/validate-changelog-taxonomy.ps1`

## Mandatory: read the entire skill

Before applying this skill, read this file to EOF.

## Preflight checklist

Before editing `CHANGELOG.md` with this skill, complete this checklist:

- [ ] I have read this skill to EOF.
- [ ] I have reviewed the current top of `CHANGELOG.md` before editing it.
- [ ] I have identified whether the change is user-facing or repo-internal.
- [ ] I have identified the correct taxonomy prefix for each new or changed bullet.
- [ ] I have identified whether this is an `Unreleased` update or a release-prep move.

If preflight is incomplete, do not proceed with changelog work.

## Approved taxonomy

Use exactly one of these taxonomy tags for each nested changelog entry:

- `[Review]`
- `[Docs]`
- `[Installer]`
- `[Implementation]`
- `[Testing]`
- `[Skill Routing]`
- `[Internal]`

## Taxonomy groups and display order

Use this fixed display order inside each of `### Added`, `### Changed`, and `### Fixed`:

User-priority group:

- `[Review]`
- `[Docs]`
- `[Installer]`

Maintainer/workflow group:

- `[Implementation]`
- `[Testing]`
- `[Skill Routing]`
- `[Internal]`

If both groups are present in the same subsection:

- list the user-priority group first
- insert exactly one blank line between the two top-level group bullets
- list the maintainer/workflow group second

If only one group is present in a subsection:

- do not emit the empty group
- do not add a separator blank line just for formatting

Render the subsection using grouped top-level bullets plus nested entries:

```markdown
### Added

- **User-Priority:**
	- **[Review]** - ...
	- **[Docs]** - ...

- **Maintainer/Workflow:**
	- **[Implementation]** - ...
	- **[Internal]** - ...
```

Within the same taxonomy tag, preserve the original bullet order unless there is a specific reason to reorder.

## Taxonomy selection rules

- Use exactly one taxonomy tag per nested changelog bullet.
- Prefer the user-facing capability tag when a change materially affects end-user behavior.
- Use `[Internal]` for repo-only harness, validation, scaffolding, or maintainer workflow changes.
- Treat `[Implementation]`, `[Testing]`, `[Skill Routing]`, and `[Internal]` as maintainer/workflow-oriented tags for display ordering purposes.
- Treat `[Review]`, `[Docs]`, and `[Installer]` as user-priority tags for display ordering purposes.
- Do not use repo-structure labels such as `instructions` or `skills` as the primary taxonomy when a capability tag is clearer.

## Wording rules

- Lead with user-visible effect before internal mechanism where possible.
- Keep the first clause understandable without requiring repository-internal knowledge.
- Mention file paths only when they materially help the reader understand the scope.
- Avoid changelog bullets that are accurate but only meaningful to repository maintainers unless the entry is intentionally tagged `[Internal]`.

## Structure rules

- Keep the `## [Unreleased]` section present at the top of the changelog.
- Under `Unreleased`, keep `### Added`, `### Changed`, and `### Fixed` headings present even when they are empty.
- When preparing a release, move the relevant `Unreleased` bullets into the dated release section.
- After creating a release section, restore empty `Added`, `Changed`, and `Fixed` headings under `Unreleased`.
- Preserve the repository's current release-section shape, including empty release subsection headings when the repo already keeps them.
- Keep exactly one blank line after each `### Added`, `### Changed`, or `### Fixed` heading before the first grouped bullet or entry.
- Inside each `Added`, `Changed`, or `Fixed` subsection, render entries under `**User-Priority:**` and `**Maintainer/Workflow:**` top-level bullets when those groups are present.
- Nested entries must use the form `  - **[Taxonomy]** - entry`.
- Keep the fixed taxonomy order above so readers learn one predictable scan pattern.

## Validation

After changing the changelog, run:

```powershell
pwsh -NoProfile -File ./tools/validate-changelog-taxonomy.ps1
```

Preferred one-shot validation:

```powershell
pwsh -NoProfile -File ./tools/validate-ai-toolkit.ps1
```

## Output expectation

When asked to maintain the changelog, provide:

- the taxonomy tags used and why
- whether the entries are user-facing or internal
- whether the work changed `Unreleased`, a release section, or both
- what validation was run

## Verification (assistant response only)

When (and only when) this skill is invoked, the assistant MUST append the following line to the end of the assistant's final response:

Skill used: changelog-maintenance

Rules:
- Do NOT write this marker into repository files.
- Do NOT emit the marker in intermediate/progress updates; only in the final response.
