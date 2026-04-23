---
name: docs-writer
description: Write or update terraform-provider-azurerm documentation pages (website/docs/**/*.html.markdown) in HashiCorp style. Use when creating/updating resource or data source docs, fixing docs lint issues, or when you need to find correct argument/attribute descriptions.
---
# docs-writer (AzureRM Provider)

## Canonical sources of truth (contract-driven)

When writing or reviewing docs, use `.github/instructions/docs-compliance-contract.instructions.md` as the single source of truth for:
- which sources are canonical
- precedence/conflict resolution

Do not duplicate drift-prone canonical-source lists in this skill.

## Mandatory: read the entire skill
Before applying this skill, read this file to EOF.

## Preflight checklist (hard stop; do not proceed on partial reads)

Before you start an audit or edit, you MUST complete this checklist. If you cannot truthfully complete it (for example because the UI only loaded part of this skill), you MUST stop and request the remaining context.

Checklist:
- [ ] I have read this skill file end-to-end (or loaded all remaining sections until EOF).
- [ ] I have loaded the shared docs compliance contract `.github/instructions/docs-compliance-contract.instructions.md` to EOF and applied all applicable `DOCS-*` rules.
- [ ] I have located and applied: **Example naming conventions** and **Naming constraints (ValidateFunc)**.
- [ ] I have located and applied: **Code fence language (mandatory in Example sections)**.

Hard-stop rule:
- If preflight is not complete, do not audit and do not propose edits.
- If preflight is not complete, you MUST respond with EXACTLY the following two lines (no additional text before or after):
   - `Preflight complete: no (skill/contract file not fully loaded to EOF; load missing context, then re-run /docs-writer)`
   - `Skill used: docs-writer`

No narration rule (mandatory):
- Do not narrate preflight or contract reading progress (for example: "contract is long", "continuing to read", "loading to EOF").
- Either proceed with the requested work (after silently satisfying preflight), or hard-stop with the exact two lines above.

## Scope
Intended for use with the HashiCorp `terraform-provider-azurerm` repository (`website/docs` and `internal/`). Works best with repo search + access to the schema implementation.

Use this skill when working on Terraform AzureRM provider documentation pages under:

- `website/docs/r/*.html.markdown` (resources)
- `website/docs/d/*.html.markdown` (data sources)

Your goal is to produce docs that match provider conventions and stay consistent with the actual Terraform schema.

## Minimal user input policy
Assume the user request may be minimal (for example: "fix this doc" / "make it compliant" / "follow Hashi standards").

When this skill is invoked, you must still:
- verify schema parity and enforce ordering
- enforce the standard generic ForceNew sentence
- add missing required notes where the contract permits them (for example resource field notes and example-adjacent notes), and enforce the data source no-field-notes rule

Do not require the user to explicitly ask for these checks.

## Contract compliance (mandatory; prevents drift)

The shared rules contract `.github/instructions/docs-compliance-contract.instructions.md` is the hard compliance checklist.

Canonical sources + precedence:
- Follow the contract section "Canonical sources of truth (precedence)".

Writer requirement:
- When writing or fixing docs, ensure the final doc satisfies all applicable `DOCS-...` rules.
- If you cannot fully satisfy the contract (for example missing schema evidence, ambiguous behavior, or missing required doc structure), you must say so and list the failing `DOCS-...` rule IDs with a one-line reason for each.

Evidence hierarchy reminder (mandatory):
- Use workspace evidence in this order: `internal/**` → `vendor/**` (SDK constants/models) → existing in-repo docs/examples (tone/structure) → Azure docs (semantics only).
- Do not use Azure docs (or any web source) to infer provider-required arguments, validation rules (`ValidateFunc`), import ID shapes, or example values.

Auditor independence:
- Do not require the `/code-review-docs` structured output format when operating under this skill.
- This skill may still produce brief audit notes, but contract compliance must be enforced.

## Quick checklist (high-signal; contract-driven)
Use this to avoid missing common compliance breakpoints. The authoritative details live in `.github/instructions/docs-compliance-contract.instructions.md`.

- Structure + frontmatter: `DOCS-FM-*`, `DOCS-STRUCT-*`
- Arguments parity + ordering + shape: `DOCS-ARG-*`, `DOCS-SHAPE-*` (including bullet split via `DOCS-ARG-011`)
- Bullet split trigger (mandatory; prevents misses): in resource docs, if an argument bullet mixes the definition with validation-style constraints (length/charset/regex/start/end rules) or includes the ForceNew sentence plus constraints, split constraints into an inline note per `DOCS-ARG-011` + `DOCS-NOTE-003`; in data source docs, keep the bullet short and field-definitional instead of adding a field-level note.
- Nested block field ordering: `DOCS-SHAPE-006`, `DOCS-ATTR-005`
- ForceNew + wording hygiene: `DOCS-WORD-*` (including enum phrasing + Oxford comma) and `DOCS-ARG-003/006/009`
- Azure object-name wording: keep canonical Azure proper-name capitalization such as `Resource Group` in field prose per `DOCS-WORD-007`
- Notes required/marker correctness + de-dup: `DOCS-NOTE-*`
- Examples (no deletions, self-contained, depends_on rules, ValidateFunc-safe values): `DOCS-EX-*` + `DOCS-EVID-001`
- Example invariants: `DOCS-EX-004`, `DOCS-EX-018`, `DOCS-EX-019`
- Example self-containedness closure: `DOCS-EX-003`, `DOCS-EX-011`, `DOCS-EX-020`
- Example reference semantics: `DOCS-EX-021`
- Example `name` values (including scaffolding): `DOCS-EX-015`, `DOCS-EX-016`
- Example `name` values (type-derived): `DOCS-EX-015`, `DOCS-EX-016`
- Import correctness (resources only): `DOCS-IMP-*`
- Timeouts (only if schema defines): `DOCS-TIMEOUT-*`
- Links + language polish: `DOCS-LINK-001`, `DOCS-LANG-001`
- vNext/legacy field handling: `DOCS-DEPR-*`

## Evidence extraction procedures (mandatory; drift prevention)

These procedures exist to keep `/docs-writer` aligned with `/code-review-docs` and prevent run-to-run drift.

### CustomizeDiff / diff-time constraint extraction (follow the chain)
When auditing or updating docs notes for conditional requirements:
- Search `internal/**` for `CustomizeDiff` for the target resource/data source.
- If `CustomizeDiff` is assigned via a wrapper/shim (for example `pluginsdk.CustomizeDiffShim(...)`, shared helper constructors, or functions returned by other functions), follow the call chain until you reach the function(s) that contain the actual field conditions.
- Extract each condition as a user-facing rule (for example: "`x` is required when `y` is set", "`x` conflicts with `y`", "`x` is only valid when `y` is `A`").
- Evidence requirement (do not skip): record the `internal/**` file path and the function name (or closest identifiable helper function name) that contains the condition.
- Guardrail: if you cannot reach the actual condition logic from available evidence (dynamic/opaque/indirection you cannot resolve), do not guess; state what could not be proven and list the relevant `DOCS-...` rule IDs impacted (see `DOCS-EVID-001`).

### Importer / import ID shape derivation (follow parser → ID type → formatter)
When auditing or writing the Import section:
- Locate the object’s `Importer:` in `internal/**`.
- Identify the parsing function or ID type used.
- Open the parsing function/type and determine the canonical segment set/order it expects.
- Cross-check Create/Read evidence:
   - find where the resource/data source constructs the ID during Create/Update, and
   - find where the ID is parsed/validated during Read.
- Prefer the canonical ID formatter used by Create/Read (the `.ID()` method or constructor) to derive the import ID example shape.
- Passthrough guardrail: if the importer is a passthrough import (for example `schema.ImportStatePassthrough` or similar) and no canonical parse/ID type can be proven from `Importer:`, derive the shape from Create/Read evidence instead.
- Final guardrail: if no canonical ID shape can be proven from implementation evidence, do not guess an import ID; state what evidence is missing/unclear and treat it as non-actionable until proven (see `DOCS-EVID-001`).

### Examples remediation (mandatory; no deletions)
When fixing Example sections:
- If an Example is not self-contained, fix it by adding the missing `resource`/`data`/`module` declarations to the page (prefer adding shared objects to `## Example Usage`).
- Do not delete an `Example*` section or remove a fenced Terraform configuration block as a remediation (see `DOCS-EX-012`).
- If an existing example contains `depends_on = [...]`, preserve it verbatim and add any missing referenced declarations rather than weakening/removing `depends_on` entries (see `DOCS-EX-004`).
- Preserve any example-adjacent notes that describe sequencing/validation requirements; if the example changes, update the note to remain accurate and evidence-based rather than deleting it (see `DOCS-EX-018`).
- Editing `*_enabled`: enforce canonical `*_enabled` phrasing rules.

## Docs scaffolding tool policy (new pages only)
The AzureRM provider repo has a website scaffold tool which can generate a baseline `website/docs/**` page from the registered schema.

Mandatory policy:
- **Default behavior:** when updating/fixing an existing docs page, edit the existing file in place. Do NOT run scaffolding.
- **Use scaffolding only when creating a brand-new docs page from scratch**, meaning the target docs file does not already exist under `website/docs/r/**` or `website/docs/d/**`.
- Also allow scaffolding when (and only when) the user explicitly asks for a scaffold/dry-run baseline to compare (see Testing mode).

Guardrails:
- Never use scaffolding as part of an audit-only workflow. Audits should be static, evidence-based reviews.
- Do not use scaffolding to "refresh" an existing page; it can overwrite intentional prose and examples.

## Testing mode (scaffold into scratch)
When the user indicates they are testing / doing a dry run, treat the session as **testing mode**.

Trigger phrases (any of these): `test`, `testing`, `dry run`, `scaffold-only`, `generate into scratch`.

In testing mode:
- Scaffold docs into a scratch website root using `-website-path website_scaffold_tmp` **only** when either:
  - the user explicitly requested scaffolding/dry-run output, or
  - you are creating a brand-new docs page that does not already exist.
- Expected output paths:
  - Resource: `website_scaffold_tmp/docs/r/<name>.html.markdown`
  - Data source: `website_scaffold_tmp/docs/d/<name>.html.markdown`
- Do not rename or move existing docs as a test harness; scaffold into scratch then diff.
  - Diff tip: `git diff --no-index website_scaffold_tmp/docs/r/<name>.html.markdown website/docs/r/<name>.html.markdown`
  - Diff tip (data source): `git diff --no-index website_scaffold_tmp/docs/d/<name>.html.markdown website/docs/d/<name>.html.markdown`

## Verification (assistant response only)
When (and only when) this skill is invoked, the assistant MUST append the following lines to the end of the assistant's final response (in this order):

Preflight complete: yes
Skill used: docs-writer

Guards (mandatory; prevents duplicated sections):
- Emit these footer lines only after the full user-visible work is complete.
- Each footer line must be on its own line (ensure a newline before `Preflight complete:` and between the two lines).
- Do not output any other content after `Skill used: docs-writer`.

Rules (mandatory):
- Do NOT write the verification marker into any repository file.
- Do NOT emit the marker in intermediate/progress updates; only in the final response.

Validation reporting (no false claims):
- Never claim a command "passes" unless you actually ran it and saw a successful exit.
