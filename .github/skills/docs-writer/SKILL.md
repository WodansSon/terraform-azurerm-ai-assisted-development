---
name: docs-writer
description: Write or update terraform-provider-azurerm documentation pages (website/docs/**/*.html.markdown) in HashiCorp style. Use when creating/updating resource or data source docs, fixing docs lint issues, or when you need to find correct argument/attribute descriptions.
---
# docs-writer (AzureRM Provider)

## Canonical sources of truth (do not hardcode drift-prone rules here)

When writing or reviewing docs, treat these as canonical sources (in priority order):

1. The upstream contributor standards doc in the target repo: `contributing/topics/reference-documentation-standards.md` (HashiCorp-owned; may change over time).
2. This repo’s instruction file applied to docs pages: `.github/instructions/documentation-guidelines.instructions.md`.

Rules:
- If the upstream contributor standards differ from this skill or local heuristics, follow the upstream file.
- Do not duplicate large rule lists in this skill; keep this skill focused on workflow/orchestration and pointers to the canonical sources.
- If the upstream file is not present/visible in the workspace, state that explicitly and fall back to the instruction file.
## Mandatory: read the entire skill
Before applying this skill, scan this file end-to-end. Do not stop after the first N lines.

If time-constrained, at minimum full-text search within this file for these headings/keywords and apply any relevant rules:
- `Examples`
- `ForceNew`
- `Enum wording`
- `Boolean *_enabled`
- `Block placement`
- `Attributes Reference ordering`
- `Quick audit checklist`
- `### Quick audit checklist (high-signal)`

## Preflight checklist (hard stop; do not proceed on partial reads)

Before you start an audit or edit, you MUST complete this checklist. If you cannot truthfully complete it (for example because the UI only loaded part of this skill), you MUST stop and request the remaining context.

Checklist:
- [ ] I have read this skill file end-to-end (or loaded all remaining sections until EOF).
- [ ] I have located and applied: **Example naming conventions** and **Naming constraints (ValidateFunc)**.
- [ ] I have located and applied: **Code fence language (mandatory in Example sections)**.

Hard-stop rule:
- If preflight is not complete, do not audit and do not propose edits.
- If preflight is not complete, you MUST respond with EXACTLY the following two lines (no additional text before or after):
   - `Preflight complete: no (skill file not fully loaded; load this skill to EOF, then re-run /docs-writer)`
   - `Skill used: docs-writer`

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
- add missing required notes (schema constraints, `CustomizeDiff`, and implicit behavior)

Do not require the user to explicitly ask for these checks.

## Where to look (glossary)
- Canonical docs standards (upstream): `contributing/topics/reference-documentation-standards.md`
- Canonical docs guidance (this repo): `.github/instructions/documentation-guidelines.instructions.md`
- Example name/value conventions: `Examples`
- ForceNew phrasing rules: `ForceNew` sections
- Enum phrasing + Oxford comma: `Enum wording` + `Oxford comma`
- Enabled boolean phrasing: `Boolean *_enabled` fields
- Block placement rules: `Block placement`
- Attributes ordering: `Attributes Reference ordering`
- Next-major deprecations (vNext-only docs): `Next-major (vNext) deprecated field handling`
- Audit expectations: `Schema + docs audit` + `Quick audit checklist`
- Timeouts link + duration wording: `Timeouts link hygiene` + `Timeout duration readability`
- Output marker rules: `Verification (assistant response only)`

## Decision tree (fast path)
- If the **Preflight checklist** is not complete: stop, request/load remaining skill context, then restart.
- If user intent is review/audit/check: run an audit-style report first and do not edit files unless the user explicitly asks for fixes.
- If user intent is fix/apply/update: run a quick audit-first pass (schema parity + ordering + required notes), then proceed with edits.
- Active file is not under `website/docs/**`: do not run docs work under this skill.
- `website/docs/r/**` (Resource): must have Example Usage, Arguments Reference, Attributes Reference, Import; include Timeouts only if schema defines timeouts.
- `website/docs/d/**` (Data Source): must have Example Usage, Arguments Reference, Attributes Reference; do not include Import; include Timeouts only if schema defines timeouts.
- If the schema indicates next-major deprecations (vNext flag / `removedInNextMajorVersion`): do not document legacy fields, do not require them for parity, and ensure replacement fields are documented.
- If the user requests a test/dry run: use **Testing mode** (scaffold with `-website-path website_scaffold_tmp`).
- Editing Example Usage: apply the full `Examples` rules.
- Editing enums/"valid values" wording: enforce `Possible values include ...` + Oxford comma (and rewrite any `Possible values are ...` you see).
- Editing `*_enabled`: enforce canonical `*_enabled` phrasing rules.

## Testing mode (scaffold into scratch)
When the user indicates they are testing / doing a dry run, treat the session as **testing mode**.

Trigger phrases (any of these): `test`, `testing`, `dry run`, `scaffold-only`, `generate into scratch`.

In testing mode:
- Scaffold docs into a scratch website root using `-website-path website_scaffold_tmp`.
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

If you cannot complete preflight due to missing context, you MUST stop and respond with:

Preflight complete: no (skill file not fully loaded; load this skill to EOF, then re-run /docs-writer)
Skill used: docs-writer

In that preflight-failed case, the response must contain no other content (no analysis, no audit, no Observations, no suggested edits).

Rules:
- Do NOT write this marker into any repository file (docs, code, generated files).
- If multiple skills are invoked, each skill should append its own `Skill used: ...` line.
- Do NOT emit the marker in intermediate/progress updates; only in the final response.

## Template tokens (placeholders)
When you need a placeholder in examples or guidance, always use the explicit token format `{{TOKEN_NAME}}`.

Rules:
- Use ALL-CAPS token names with underscores (for example `{{RESOURCE_NAME}}`, `{{FIELD_NAME}}`).
- Do not use ambiguous placeholders like `<name>` or `...`.
- Do not leave tokens in final repository output; tokens are for skill guidance/examples only.
- If any `{{...}}` token would appear in final output, replace it before responding.

## Validation reporting (no false claims)
Do not include a `Validation:` section in your response unless the user explicitly asked you to run validations.

Never claim a command "passes" (for example `document-lint`, `documentfmt`, `go test`, etc.) unless you actually executed it in the current environment and observed a successful exit.

If the user wants validation, prefer phrasing like "To validate, run: …" rather than asserting results.

## Decide the approach first
- Creating a brand-new doc page: scaffold first (preferred) using the provider tool, then edit.
- Updating an existing doc page: do not re-scaffold; edit the existing file and verify schema parity.

~> **Note:** The scaffold tool writes the target `website/docs/...` file. Only use it to generate a new page, otherwise you may overwrite edits.

## Workflow (recommended)
1. Identify what you are documenting
   - Resource doc: "Manages a …"
   - Data source doc: "Gets information about …"

2. Scaffold the initial page when possible
   - If you're working inside the `hashicorp/terraform-provider-azurerm` repo, prefer using the built-in docs scaffold tool to generate the baseline page from the registered schema:
      - `internal/tools/website-scaffold/main.go`
   - This gets you the correct file location (`website/docs/r|d/...`) and a schema-aligned Arguments/Attributes structure quickly.
   - You must still review and improve the generated wording (the scaffold intentionally emits some `TODO` placeholders).

   Example (resource):
   - Normal: `go run ./internal/tools/website-scaffold -type resource -name azurerm_example_resource -brand-name "Example Resource" -resource-id "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/group1/providers/Microsoft.Example/resources/resource1" -website-path website`
   - Testing mode: `go run ./internal/tools/website-scaffold -type resource -name azurerm_example_resource -brand-name "Example Resource" -resource-id "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/group1/providers/Microsoft.Example/resources/resource1" -website-path website_scaffold_tmp`

   Example (data source):
   - Normal: `go run ./internal/tools/website-scaffold -type data -name azurerm_example_resource -brand-name "Example Resource" -website-path website`
   - Testing mode: `go run ./internal/tools/website-scaffold -type data -name azurerm_example_resource -brand-name "Example Resource" -website-path website_scaffold_tmp`

3. Start from an existing page or template
   - Prefer copying the structure of the closest existing resource/data source doc in `website/docs/`.

4. Ensure schema parity (do not invent fields)
   - Find the corresponding resource/data source implementation under `internal/services/**`.
   - Extract:
      - required vs optional arguments
      - `ForceNew` behavior ("Changing this forces a new …")
      - computed attributes
      - defaults, allowed values, and constraints
         - conditional requirements and cross-field constraints (from schema and diff/validation logic)

   Follow the canonical docs rules for next-major deprecations, conditional notes, and ordering:
   - Upstream: `contributing/topics/reference-documentation-standards.md`
   - This repo: `.github/instructions/documentation-guidelines.instructions.md`

5. Write clean docs content
   - Keep sentences short, factual, and present tense.
   - Avoid copying vendor documentation verbatim; paraphrase.


## Docs standards enforcement (canonical)

Do not maintain large, drift-prone checklists in this skill.

When editing or reviewing docs, follow the canonical sources:
- Upstream contributor standards: `contributing/topics/reference-documentation-standards.md`
- This repo’s docs instructions: `.github/instructions/documentation-guidelines.instructions.md`

For a deterministic audit procedure + required output structure, use `/code-review-docs` (`.github/prompts/code-review-docs.prompt.md`).

## When wording is unclear

Use this source order:
1) Terraform schema + provider implementation
2) Existing provider docs (tone/phrasing)
3) Azure docs for semantics only (write provider-style wording)
4) If still ambiguous: document only what you can verify

## Output expectations

- Prefer applying edits directly to the target doc file (patch/diff).
- For very large pages, avoid pasting full content; patch the file and summarize the changed sections.
