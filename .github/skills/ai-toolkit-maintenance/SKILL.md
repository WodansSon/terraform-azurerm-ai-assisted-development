---
name: ai-toolkit-maintenance
description: Maintain this repository's AI toolkit scaffolding and alignment. Use when checking contract/consumer alignment, deciding whether files belong in the shipped bundle, updating the installer manifest, or validating repo-only AI guidance changes.
---

# AI Toolkit Maintenance

## Scope

This skill is for maintainers of this repository only.

Use it when working on the AI toolkit infrastructure in this repo, especially when:

- checking whether the toolkit is up to date
- checking upstream contributor drift and interpreting whether local AI guidance still aligns
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
- `tools/config/upstream-contributor.json`
- `CONTRIBUTING.md`
- `.github/pull_request_template.md`
- `installer/file-manifest.config`
- `CHANGELOG.md`
- `tools/check-upstream-contributor-drift.ps1`
- `tools/validate-contracts.ps1`
- `.github/.markdownlint.json`
- the current contract, companion, prompt, and skill files under `.github/`

## Mandatory: read the entire skill

Before applying this skill, read this file to EOF.

## Preflight checklist

Before making AI-toolkit maintenance changes with this skill, complete this checklist:

- [ ] I have read this skill to EOF.
- [ ] I have read `docs/AI_TOOLKIT_ALIGNMENT_CHECKLIST.md` to EOF.
- [ ] I have identified whether upstream HashiCorp contributor docs under `contributing/topics/` are part of the change I am making.
- [ ] If upstream contributor alignment is in scope, I will run `pwsh -NoProfile -File ./tools/check-upstream-contributor-drift.ps1` before concluding the toolkit is current.
- [ ] I have identified whether the target change is runtime payload or repo-maintenance-only.
- [ ] I have identified whether the change also requires updates to `installer/file-manifest.config`, `docs/CODE_REVIEW_RULES.md`, or `CHANGELOG.md`.

If preflight is incomplete, do not proceed with toolkit-maintenance work.

## Default authoring pattern

- Use titled subsections plus bullets for AI-toolkit prose.
- Let heading order and bullet indentation convey sequence.
- Avoid fragile ordered-list structures in `.github/skills/`, `.github/prompts/`, and `.github/instructions/`.

## Maintenance workflow

### MAINT-UPSTREAM-001: Review upstream PR workflow guidance before changing local maintainer workflow

- Rule: When local AI guidance changes contributor or maintainer PR workflow expectations, review upstream `guide-opening-a-pr.md` first and keep local workflow guidance aligned unless there is a deliberate repo-only reason to be stricter.
- **Provenance**: Published upstream standard.
- **Evidence**:
  - Upstream contributor guidance in `hashicorp/terraform-provider-azurerm/contributing/topics/guide-opening-a-pr.md` under `Process` and `What makes a good PR?`
  - That guidance defines the baseline PR process, checklist, testing expectations, and title/body expectations that local maintainer workflow should not drift away from casually

### MAINT-UPSTREAM-002: Keep local changelog-responsibility guidance aligned with upstream maintainer flow

- Rule: Do not tell normal contributors to update changelog entries as part of the routine PR workflow when upstream maintainer guidance says changelog handling belongs to maintainers during merge.
- **Provenance**: Published upstream standard.
- **Evidence**:
  - Upstream contributor guidance in `hashicorp/terraform-provider-azurerm/contributing/topics/maintainer-merging.md` says contributors should not be concerned with updating the changelog as part of a PR
  - Upstream contributor guidance in `hashicorp/terraform-provider-azurerm/contributing/topics/guide-opening-a-pr.md` says the maintainer updates `CHANGELOG.md`

### MAINT-UPSTREAM-003: Treat the drift checker as deterministic detection, then use AI for semantic review

- Rule: `tools/check-upstream-contributor-drift.ps1` uses pure logic only: tracked-source hash comparison, current upstream topic discovery from the upstream contributor index, exact local topic-reference discovery, and exact rule-evidence reference validation.
- Rule: It must not use heuristics to guess which local files or rules an upstream topic probably maps to.
- Rule: Exact-reference aggregation is only for proving local links that are already explicitly written in repo content. It is not the semantic mapping step.
- Rule: When the request is to check whether the AI toolkit is up to date, or when upstream HashiCorp contributor alignment is in scope, running `tools/check-upstream-contributor-drift.ps1` is a core step of this skill rather than an optional extra.
- Rule: When the drift checker reports changed upstream sources or rule issues, follow it with an AI-assisted maintainer review before changing local rules, provenance labels, or evidence blocks.
- Rule: When the drift checker reports uncovered upstream topics or dynamically mapped untracked topics, use AI-assisted review to decide whether a new tracked source or local guidance update is needed.
- Rule: Do not rewrite local guidance solely because a source hash changed; first determine whether the upstream change actually changes the meaning of the guidance.
- **Provenance**: Local safeguard.
- **Evidence**:
  - Added because pure logic can prove exact references and exact drift states, but cannot prove semantic equivalence or meaning-preserving upstream rewrites
  - The repo-only maintainer workflow needs an explicit handoff from deterministic detection to AI-assisted semantic review rather than heuristic auto-mapping

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

- Keep upstream contributor guidance aligned without hardcoding it blindly:
  - Use `tools/config/upstream-contributor.json` for tracked-source baselines only.
  - Treat `https://github.com/hashicorp/terraform-provider-azurerm/tree/main/contributing` as the canonical remote contributor-doc root when comparing local references to upstream docs from this installer repo.
  - Run `pwsh -NoProfile -File ./tools/check-upstream-contributor-drift.ps1` to detect when tracked upstream docs have changed since the local baseline.
  - Let the drift checker derive local mappings dynamically from exact upstream topic references already present in repo files and rule evidence blocks.
  - Use AI semantic matching after that deterministic pass to assess uncovered, changed, renamed, or merged upstream topics that do not already have explicit local links.
  - Do not add heuristic mapping rules to the script. If exact references are missing, let the drift checker surface that as a maintainer review event.
  - Treat the drift checker as the deterministic detection stage only; if it reports changed sources or rule issues, perform an AI-assisted semantic review before editing local guidance.
  - When a tracked upstream doc changes, review the dynamically discovered local references and remove any conflicting local rules while preserving verified tribal knowledge that still does not conflict.

- Run the repo maintenance checks:
  - Run `pwsh -NoProfile -File ./tools/check-upstream-contributor-drift.ps1` when local AI guidance is meant to stay aligned with upstream HashiCorp contributor docs.
  - Run `pwsh -NoProfile -File ./tools/validate-contracts.ps1` after contract or consumer changes.
  - Run `npx -y markdownlint-cli2 ".github/**/*.md" "docs/**/*.md" --config .github/.markdownlint.json` after Markdown-based AI-toolkit changes.

## Output expectation

When asked to maintain the AI toolkit in this repository, provide:

- The files that need to stay aligned
- Whether `tools/check-upstream-contributor-drift.ps1` was run, and if not, why it was out of scope
- Which upstream contributor docs were reviewed or reported as drifted
- Whether the upstream topic catalog changed, including uncovered upstream topics, dynamically mapped untracked topics, stale tracked topics, or stale local topic references
- Which dynamically discovered local rule IDs need provenance or evidence review
- Which uncovered or changed upstream topics require AI semantic mapping review because no explicit local link already exists
- Which changes are runtime payload versus repo-only
- What validations were run
- Any remaining alignment gaps

## Verification (assistant response only)

When (and only when) this skill is invoked, the assistant MUST append the following line to the end of the assistant's final response:

Skill used: ai-toolkit-maintenance

Rules:
- Do NOT write this marker into any repository file.
- Do NOT emit the marker in intermediate/progress updates; only in the final response.
