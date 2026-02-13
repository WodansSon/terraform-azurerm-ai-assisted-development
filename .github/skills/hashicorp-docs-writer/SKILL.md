---
name: hashicorp-docs-writer
description: Write or update terraform-provider-azurerm documentation pages (website/docs/**/*.html.markdown) in HashiCorp style. Use when creating/updating resource or data source docs, fixing docs lint issues, or when you need to find correct argument/attribute descriptions.
---

# HashiCorp Docs Writer (AzureRM Provider)

## Scope

Intended for use with the HashiCorp `terraform-provider-azurerm` repository (`website/docs` and `internal/`). Works best with repo search + access to the schema implementation.

Use this skill when working on Terraform AzureRM provider documentation pages under:

- `website/docs/r/*.html.markdown` (resources)
- `website/docs/d/*.html.markdown` (data sources)

Your goal is to produce docs that match provider conventions and stay consistent with the actual Terraform schema.

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
   - `go run ./internal/tools/website-scaffold -type resource -name azurerm_service_resource -brand-name "Service Resource" -resource-id "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/group1/providers/Microsoft.Service/resources/resource1" -website-path website`

   Example (data source):
   - `go run ./internal/tools/website-scaffold -type data -name azurerm_service_resource -brand-name "Service Resource" -website-path website`

3. Start from an existing page or template
   - Prefer copying the structure of the closest existing resource/data source doc in `website/docs/`.

4. Ensure schema parity (do not invent fields)
   - Find the corresponding resource/data source implementation under `internal/services/**`.
   - Extract:
     - required vs optional arguments
     - `ForceNew` behavior ("Changing this forces a new …")
     - computed attributes
     - defaults, allowed values, and constraints

5. Write clean docs content
   - Keep sentences short, factual, and present tense.
   - Avoid copying vendor documentation verbatim; paraphrase.

6. Remove scaffold placeholders
   - Search for `TODO` in the generated page and replace with verified, provider-style descriptions.

7. Validate
   - Ensure Markdown formatting passes linting.
   - If available, run a schema parity audit (automated or manual check).

## Required structure (high level)

A typical resource doc page should include:

- YAML frontmatter (`subcategory`, `layout`, `page_title`, `description`)
- Title header (e.g. `# azurerm_...`)
- Short description repeated after the title
- `## Example Usage` (only create subsections if configurations differ meaningfully)
- `## Arguments Reference`
- `## Attributes Reference`
- `## Timeouts` (resources only)
- `## Import` (resources only)

A typical data source doc page should include:

- YAML frontmatter
- Title header (e.g. `# Data Source: azurerm_...`)
- `## Example Usage`
- `## Arguments Reference`
- `## Attributes Reference`

## Notes and warnings (HashiCorp doc style)

Use the correct note prefix:

- Informational: `-> **Note:**` (tips, extra info)
- Warning: `~> **Note:**` (to prevent common errors, e.g. ForceNew / conditional requirements)
- Caution: `!> **Note:**` (irreversible changes, data loss)

Do not use a mild note where a warning/caution is required.

## Schema + docs audit (recommended)

After writing or updating a page, run a standards + schema parity pass.

- For the full, structured audit procedure and output format, use: `.github/prompts/docs-schema-audit.prompt.md`

If you cannot locate the schema under `internal/**`, say so explicitly and do a docs-standards-only review.

### Quick audit checklist (high-signal)

- **Doc type and required sections**
   - Resource docs must include: Example Usage, Arguments Reference, Attributes Reference, Import
   - Data source docs must include: Example Usage, Arguments Reference, Attributes Reference (no Import)
   - Timeouts section is required only if the schema defines timeouts

- **Parity**
   - All required args are documented
   - No undocumented args appear (do not invent fields)
   - All computed attributes are in Attributes Reference (`id` first)

- **Schema shape**
   - Blocks vs inline fields match the schema (do not document nested fields for scalars/maps)
   - Collections of primitives are described as lists/sets, not blocks

- **Ordering**
   - Arguments ordered per provider reference-doc standards (IDs first, then `location`, then required alpha, then optional alpha, `tags` last)

- **ForceNew wording (resources only)**
   - Every ForceNew arg includes: "Changing this forces a new … to be created."

- **Notes**
   - Notes use exact `->` / `~>` / `!>` markers and the marker matches the note’s impact

- **Examples**
   - Includes all required args, no `provider`/`terraform` blocks, no hard-coded secrets, internally consistent references

- **Link hygiene**
   - Prefer locale-neutral Learn links (avoid `/en-us/` etc.)

## Where to get field descriptions (when not obvious)

When you need to document an argument/attribute and the wording is not already present:

1. Prefer the provider schema
   - Look for `Description:` values in schema definitions.
   - For typed resources, also check how fields are expanded/flattened.

2. Use existing provider docs as the source of truth for tone and phrasing
   - Search `website/docs/` for the same field name (for example, `resource_group_name`, `location`, `tags`, `identity`, etc.).

3. Use Azure service docs only for semantics (not wording)
   - Confirm what the field *means* and any constraints.
   - Write your own short phrasing that matches provider style.

4. If still ambiguous, document only what you can verify
   - Avoid listing possible values unless you can confirm them from code/constants.
   - Prefer: “Possible values include …” only when confirmed.

## Common doc rules (quick checklist)

- Use Terraform names exactly (`azurerm_*`).
- Ensure `Arguments Reference` reflects Required/Optional/Computed accurately.
- Mention `ForceNew` in the argument description.
- Keep field order sensible (Required first, then Optional; keep `tags` last).
- Keep examples realistic and minimal.
- Include correct import format and a real-looking example ID.

## Output expectation

When asked to write or update docs, produce:

- The full updated page content (not partial snippets) OR a precise diff.
- A short checklist of what you verified against the schema.
