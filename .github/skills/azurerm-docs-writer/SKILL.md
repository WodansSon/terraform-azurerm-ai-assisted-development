---
name: azurerm-docs-writer
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
       - conditional requirements and cross-field constraints (from schema and diff/validation logic)

    When documenting conditional behavior, prefer the provider implementation as the source of truth and keep notes high-signal:
    - Primary sources for conditional requirements that should be documented as notes:
       - Schema constraints (for example: conflicts, exactly-one-of, at-least-one-of, required-with)
       - Diff-time validation (`CustomizeDiff`), including conditions like "required when X is set" or "must be one of these values when Y".
    - Secondary sources:
       - Inline checks in Create/Update, and constraints implied by expand/flatten.
       - Only document these when they are user-facing constraints that affect successful apply and are not already obvious from schema/diff-time validation.

    How to present constraints (avoid note spam):
    - Prefer embedding simple, field-local constraints in the field description (for example: "Possible values are …").
    - Use a `~> **Note:**` only for cross-field/conditional requirements that commonly trip users up.
    - For simple enum validation in `ValidateFunc`, document allowed values in the field description rather than adding extra notes.

5. Write clean docs content
   - Keep sentences short, factual, and present tense.
   - Avoid copying vendor documentation verbatim; paraphrase.

6. Remove scaffold placeholders
   - Search for `TODO` in the generated page and replace with verified, provider-style descriptions.
   - Do not leave `TODO` placeholders in the final doc output.
   - If you cannot resolve a `TODO` from verifiable sources, replace it with the minimal verified description and explicitly list the remaining uncertainty in your output checklist.

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

### Frontmatter rule: data source `page_title`

For data source docs under `website/docs/d/**`, the doc type is already implied by the path.

- Do not include `Data Source:` in the YAML `page_title`.
- Use: `page_title: "Azure Resource Manager: azurerm_<name>"`

Example:

- Incorrect: `page_title: "Azure Resource Manager: Data Source: azurerm_cdn_frontdoor_custom_domain"`
- Correct: `page_title: "Azure Resource Manager: azurerm_cdn_frontdoor_custom_domain"`

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
   - Also check how fields are expanded/flattened in the implementation (typed or untyped) to document actual behavior.

   When you need to map a Terraform field to the Azure API (property names, enum strings, nested shapes):
   - Follow the provider implementation first (expand/flatten functions and the request payload construction) and document what the code actually sends.
   - Then confirm details from the Azure SDK model types/constants used by that code by jumping to the referenced type/constant definition.
     - If the repo has a `vendor/` directory, SDK models/constants are typically under `vendor/<module path>/...` (exact subfolders vary by SDK).
     - Otherwise, use the imported package path/type name from the code and jump to definition to locate the model/constant.

2. Use existing provider docs as the source of truth for tone and phrasing
   - Search `website/docs/` for the same field name (for example, `resource_group_name`, `location`, `tags`, `identity`, etc.).

3. Use Azure service docs only for semantics (not wording)
   - Confirm what the field *means* and any constraints.
   - Write your own short phrasing that matches provider style.

   When validating semantics/constraints, prefer official sources in this order:
   - Microsoft Learn (concepts, constraints, examples)
   - Azure REST API reference (property meaning, allowed values, and defaults)
   - Swagger/OpenAPI specs (when available) for enum values and shapes
   - Azure SDK models/constants (to confirm actual enum strings and behavior)

4. If still ambiguous, document only what you can verify
   - Avoid listing possible values unless you can confirm them from code/constants.
   - Prefer: “Possible values include …” only when confirmed.

## Common doc rules (quick checklist)

- Use Terraform names exactly (`azurerm_*`).
- When listing 3+ possible values, use the Oxford comma.
   - Incorrect: Possible values are `Default`, `InitiatorOnly` and `ResponderOnly`.
   - Correct: Possible values are `Default`, `InitiatorOnly`, and `ResponderOnly`.
- Ensure `Arguments Reference` reflects Required/Optional/Computed accurately.
- Mention `ForceNew` in the argument description.
- Document conditional requirements and cross-field constraints (especially ones enforced in `CustomizeDiff`/validation) using `->`/`~>`/`!>` notes as appropriate.
- Keep field order sensible:
   - List **Required** arguments first, then **Optional** arguments.
   - Within **each** group (Required, then Optional), order fields as:
      1) `name` (if present)
      2) `resource_group_name` (if present)
      3) `location` (if present)
      4) all remaining fields in that group in alphabetical order
      5) `tags` last (if present)
   - Example (Required): `name`, `resource_group_name`, `location`, `sku_name`
- Keep examples realistic and minimal; include only required fields unless an optional field is needed to demonstrate a behavior.
- Include correct import format and a real-looking example ID.

## Output expectation

When asked to write or update docs, produce:

- The full updated page content (not partial snippets) OR a precise diff.
- A short checklist of what you verified against the schema.

<!-- This footer is a temporary debug/validation marker for the POC and should be removed once the feature is released. -->
At the end of the document, append this single footer line:

!> **Generated by the AzureRM Vibe Coding Documentatin-Writer Skill.**
