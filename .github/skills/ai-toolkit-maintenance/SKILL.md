---
name: ai-toolkit-maintenance
description: Maintain this repository's AI toolkit scaffolding and alignment. Use when checking contract/consumer alignment, deciding whether files belong in the shipped bundle, updating the installer manifest, or validating repo-only AI guidance changes.
---

# AI Toolkit Maintenance

## Scope

This skill is for maintainers of this repository only.

Use it when working on the AI toolkit infrastructure in this repo, especially when:

- checking whether the toolkit is up to date
- updating contracts, companion guidance, prompts, or skills together
- deciding whether a file is runtime payload or repo-maintenance-only
- updating `installer/file-manifest.config`
- updating `docs/CODE_REVIEW_RULES.md`
- updating `CHANGELOG.md` for toolkit changes
- validating contract-model and markdown alignment after AI-toolkit edits

This skill is intentionally repo-only. It is not part of the shipped runtime toolkit and should not be added to `installer/file-manifest.config`.

## Canonical sources of truth

When doing AI-toolkit maintenance in this repository, use these sources in this order:

- `docs/AI_TOOLKIT_ALIGNMENT_CHECKLIST.md`
- `installer/file-manifest.config`
- `CHANGELOG.md`
- `tools/validate-contracts.ps1`
- `.github/.markdownlint.json`
- the current contract, companion, prompt, and skill files under `.github/`

## Mandatory: read the entire skill

Before applying this skill, read this file to EOF.

## Preflight checklist

Before making AI-toolkit maintenance changes with this skill, complete this checklist:

- [ ] I have read this skill to EOF.
- [ ] I have read `docs/AI_TOOLKIT_ALIGNMENT_CHECKLIST.md` to EOF.
- [ ] I have identified whether the target change is runtime payload or repo-maintenance-only.
- [ ] I have identified whether the change also requires updates to `installer/file-manifest.config`, `docs/CODE_REVIEW_RULES.md`, or `CHANGELOG.md`.

If preflight is incomplete, do not proceed with toolkit-maintenance work.

## Default authoring pattern

- Use titled subsections plus bullets for AI-toolkit prose.
- Let heading order and bullet indentation convey sequence.
- Avoid fragile ordered-list structures in `.github/skills/`, `.github/prompts/`, and `.github/instructions/`.

## Maintenance workflow

- Classify the change first:
  - Decide whether the file belongs in shipped runtime payload or repo-only maintenance tooling.
  - Leave repo-only files out of `installer/file-manifest.config`.

- Keep authority boundaries clear:
  - Contracts remain the authority where they exist.
  - Companion guidance should point back to the relevant contract.
  - Skills and routing files should not become competing authority sources.

- Update adjacent surfaces together when needed:
  - Runtime payload changes may require manifest updates.
  - New contract families or rule areas may require `docs/CODE_REVIEW_RULES.md` updates.
  - User-visible toolkit changes should be reflected in `CHANGELOG.md`.

- Run the repo maintenance checks:
  - Run `pwsh -NoProfile -File ./tools/validate-contracts.ps1` after contract or consumer changes.
  - Run `npx -y markdownlint-cli2 ".github/**/*.md" "docs/**/*.md" --config .github/.markdownlint.json` after Markdown-based AI-toolkit changes.

## Output expectation

When asked to maintain the AI toolkit in this repository, provide:

- The files that need to stay aligned
- Which changes are runtime payload versus repo-only
- What validations were run
- Any remaining alignment gaps

## Verification (assistant response only)

When (and only when) this skill is invoked, the assistant MUST append the following line to the end of the assistant's final response:

Skill used: ai-toolkit-maintenance

Rules:
- Do NOT write this marker into any repository file.
- Do NOT emit the marker in intermediate/progress updates; only in the final response.
