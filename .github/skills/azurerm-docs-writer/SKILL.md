---
name: azurerm-docs-writer
description: Write or update terraform-provider-azurerm documentation pages (website/docs/**/*.html.markdown) in HashiCorp style. Use when creating/updating resource or data source docs, fixing docs lint issues, or when you need to find correct argument/attribute descriptions.
---

# HashiCorp Docs Writer (AzureRM Provider)

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

## Scope

Intended for use with the HashiCorp `terraform-provider-azurerm` repository (`website/docs` and `internal/`). Works best with repo search + access to the schema implementation.

Use this skill when working on Terraform AzureRM provider documentation pages under:

- `website/docs/r/*.html.markdown` (resources)
- `website/docs/d/*.html.markdown` (data sources)

Your goal is to produce docs that match provider conventions and stay consistent with the actual Terraform schema.

## Where to look (glossary)

- Example name/value conventions: `Examples`
- ForceNew phrasing rules: `ForceNew` sections
- Enum phrasing + Oxford comma: `Enum wording` + `Oxford comma`
- Enabled boolean phrasing: `Boolean *_enabled` fields
- Block placement rules: `Block placement`
- Attributes ordering: `Attributes Reference ordering`
- Audit expectations: `Schema + docs audit` + `Quick audit checklist`
- Timeouts link + duration wording: `Timeouts link hygiene` + `Timeout duration readability`
- Output marker rules: `Verification (assistant response only)`

## Decision tree (fast path)

- Active file is not under `website/docs/**`: do not run docs work under this skill.
- `website/docs/r/**` (Resource): must have Example Usage, Arguments Reference, Attributes Reference, Import; include Timeouts only if schema defines timeouts.
- `website/docs/d/**` (Data Source): must have Example Usage, Arguments Reference, Attributes Reference; do not include Import; include Timeouts only if schema defines timeouts.
- If the user requests a test/dry run: use **Testing mode** (scaffold with `-website-path website_scaffold_tmp`).
- Editing Example Usage: apply the full `Examples` rules.
- Editing enums/"valid values" wording: enforce `Possible values include ...` + Oxford comma.
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

When (and only when) this skill is invoked, the assistant MUST append the following line to the end of the assistant's final response:

Skill used: azurerm-docs-writer

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
   - Normal: `go run ./internal/tools/website-scaffold -type resource -name azurerm_service_resource -brand-name "Service Resource" -resource-id "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/group1/providers/Microsoft.Service/resources/resource1" -website-path website`
   - Testing mode: `go run ./internal/tools/website-scaffold -type resource -name azurerm_service_resource -brand-name "Service Resource" -resource-id "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/group1/providers/Microsoft.Service/resources/resource1" -website-path website_scaffold_tmp`

   Example (data source):
   - Normal: `go run ./internal/tools/website-scaffold -type data -name azurerm_service_resource -brand-name "Service Resource" -website-path website`
   - Testing mode: `go run ./internal/tools/website-scaffold -type data -name azurerm_service_resource -brand-name "Service Resource" -website-path website_scaffold_tmp`

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

## Mandatory HashiCorp docs style enforcement

When you touch or update any existing documentation page, you must proactively enforce HashiCorp contributor doc style rules even if the user did not explicitly request “style fixes”.

This is not optional: if you see a rule violation while editing a page, you must fix it as part of the same change.

At minimum, always enforce:

- **Oxford comma for 3+ values**
   - If a sentence lists three or more values in prose, it must include the Oxford comma.
   - This applies to any prose list of 3+ backticked values (enums, modes, SKU names, replication types, etc.), not only “Possible values include …” sentences.
   - Example:
      - Incorrect: Possible values include `Default`, `InitiatorOnly` and `ResponderOnly`.
      - Correct: Possible values include `Default`, `InitiatorOnly`, and `ResponderOnly`.
   - This applies to phrases like: “Possible values are …”, “Possible values include …”, “Currently supported values are …”, etc.

- **Avoid “and vice versa” in ForceNew conditions**
   - If you are documenting a ForceNew condition that applies in both directions between two sets of values, do not rely on “and vice versa”.
   - If the text contains the phrase “and vice versa”, you must rewrite the sentence to remove it.
   - Prefer an explicit, bidirectional phrasing that preserves meaning, e.g.:
      - Prefer: “Changing this forces a new {{RESOURCE_NAME}} to be created when changing `{{FIELD_NAME}}` between these two groups: `A`, `B`, and `C`; `D`, `E`, and `F`.”
      - Avoid: “... when types `A`, `B` and `C` are changed to `D`, `E` or `F` and vice versa.”

- **ForceNew conditions for “subset switching” enums**
   - When a ForceNew is triggered specifically by switching between two subsets of values within the same enum, document it as a “between subsets” rule.
   - Preferred pattern:
      - “Changing this forces a new {{RESOURCE_NAME}} to be created when changing `{{FIELD_NAME}}` between these two groups: `A`, `B`, and `C`; `D`, `E`, and `F`.”
   - Avoid patterns that read like a one-way transformation or require “vice versa”.

- **Enum wording (provider standard)**
   - When documenting enumerated values, use provider-standard phrasing:
      - Prefer: `Possible values include ...`
         - Avoid: `Valid options are ...` / `Valid values are ...`
   - Mandatory rewrites when editing docs:
      - Replace `Valid options are` with `Possible values include`
      - Replace `Valid values are` with `Possible values include`
      - Replace `Possible values are` with `Possible values include`
   - Ensure values are wrapped in backticks and use the Oxford comma when listing 3+ values.

- **Boolean `*_enabled` fields (canonical wording)**
   - For boolean fields ending in `_enabled`, avoid “Boolean, enable …”, “Boolean, enables …”, or “Set to true to …”.
   - Canonical phrasing depends on section:
      - **Arguments Reference** (bullets containing `(Required)`/`(Optional)`):
         - “Should `<thing>` be enabled?”
      - **Attributes Reference** (exported/computed attributes):
         - “Is `<thing>` enabled.”
   - Derive `<thing>` from the field name:
      - Start with the field name (for example `sftp_enabled`).
      - Remove the trailing `_enabled`.
      - Replace remaining underscores with spaces.
      - Wrap the resulting `<thing>` in backticks.
   - Example:
      - Input: `sftp_enabled`
      - Arguments: “Should `sftp` be enabled? Defaults to `false`.” (if a default is known)
      - Attributes: “Is `sftp` enabled.”

- **Block placement (mandatory)**
   - Do not place all block subsections in one location.
   - **Block arguments** must appear under `## Arguments Reference`:
      - Top-level bullet example (use `A`/`An` as appropriate):
         - `* `identity` - (Optional) An `identity` block as defined below.`
      - Subsection heading example (use `A`/`An` as appropriate):
         - An `identity` block supports the following:
      - Placement: after the top-level arguments list (typically after a `---`) and before `## Attributes Reference`.
   - **Block attributes** must appear under `## Attributes Reference`:
      - Top-level bullet example (use `A`/`An` as appropriate):
         - `* `identity` - An `identity` block as defined below.`
      - Subsection heading example (use `A`/`An` as appropriate):
         - An `identity` block exports the following:
      - Placement: after the top-level attributes list (typically after a `---`) and before `## Timeouts`.
   - **Indefinite article rule (A vs An)**
      - Use `An` when the block name starts with a vowel character (`a`, `e`, `i`, `o`, `u`) after stripping backticks.
      - Otherwise use `A`.
      - Example: An `identity` block supports the following:
   - Use the subsection verb to classify the block:
      - If it says `supports the following`, it is an argument block.
      - If it says `exports the following`, it is an attribute block.

- **Apply style rules to the entire bullet**
   - When you update an Arguments Reference bullet, apply these style rules to every sentence in that bullet (not only the first sentence).
   - In particular, enforce Oxford commas inside any ForceNew condition sentence (for example lists in “… `A`, `B` and `C` …” and “… `D`, `E` or `F` …”).

- **ForceNew rewrite (subset switching) — canonical form**
   - If you see the pattern “... when types `A`, `B` and `C` are changed to `D`, `E` or `F` and vice versa”, rewrite it into the canonical “two groups” form:
      - “Changing this forces a new {{RESOURCE_NAME}} to be created when changing `{{FIELD_NAME}}` between these two groups: `A`, `B`, and `C`; `D`, `E`, and `F`.”
   - This rewrite is preferred because it is bidirectional, removes “vice versa”, and makes the boundary-switch behavior unambiguous.

- **Consistent value quoting**
   - Enum/possible values must be wrapped in backticks.

- **Timeout duration readability**
   - In the `## Timeouts` section, if a default timeout is **60 minutes or greater**, express it in **hours** (use correct singular/plural), rather than minutes.
   - Example:
      - Prefer: `(Defaults to 1 hour)` over `(Defaults to 60 minutes)`
      - Prefer: `(Defaults to 2 hours)` over `(Defaults to 120 minutes)`

- **Timeouts link hygiene**
   - When adding a new `## Timeouts` section, use: `https://developer.hashicorp.com/terraform/language/resources/configure#define-operation-timeouts`
   - When editing an existing page that already uses the legacy Terraform.io timeouts link, keep it unchanged unless you are explicitly updating the timeouts content or standardizing links across the provider.

- **Attributes Reference descriptions (no argument-only phrases)**
   - In `## Attributes Reference`, do not include argument-only phrases such as:
      - `Defaults to ...`
      - `Possible values include ...`
   - Attributes should be concise and describe what is returned.

- **Attributes Reference ordering**
   - In `## Attributes Reference`, always list `id` as the first exported attribute.
   - List remaining exported attributes in alphabetical order.
   - Do not bury `id` in the middle of the list.

If you are only asked to make a narrow change, still apply these style rules to any lines you touch and to any immediately-adjacent “Possible values …” lines in the same section.

1. Remove scaffold placeholders
   - Search for `TODO` in the generated page and replace with verified, provider-style descriptions.
   - Do not leave `TODO` placeholders in the final doc output.
   - Follow the **TODO resolution ladder** below before giving up. If you still cannot resolve a `TODO` from verifiable sources, replace it with the minimal verified description and explicitly list the remaining uncertainty in your output checklist.

   **TODO resolution ladder (use before giving up):**
   1. Provider schema + implementation (preferred)
      - `Description:` strings in schema
      - expand/flatten behavior in `internal/**`
      - validation/CustomizeDiff rules that create user-facing constraints
   2. Existing provider docs for tone/phrasing
      - Search `website/docs/**` for the same argument/attribute name
   3. Official Microsoft / Azure sources for semantics (not wording)
      - Prefer Microsoft Learn and Azure REST API reference for meaning, constraints, and allowed values
      - Use Swagger/OpenAPI specs when needed to confirm enum strings/shapes
      - When available in the environment, use the Microsoft Learn MCP tools to look up details:
        - `mcp_microsoft_doc_microsoft_docs_search` (find the right page)
        - `mcp_microsoft_doc_microsoft_docs_fetch` (read the full page)
      - As a fallback, use `fetch_webpage` for specific URLs when MCP fetch is not applicable
   4. If still ambiguous
      - Document only what you can verify from code/schema
      - Add a short uncertainty note to your output checklist describing what could not be confirmed

2. Validate
   - Ensure Markdown formatting passes linting.
   - If available, run a schema parity audit (automated or manual check).

3. Final checklist (before finishing)
   - Verify `## Arguments Reference` required arguments are ordered with `name`, `resource_group_name`, and `location` first (when present).
   - Verify `## Arguments Reference` lists `tags` last (when present).
   - Verify `## Attributes Reference` lists `id` first, and the remaining exported attributes are in alphabetical order.

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

## Canonical section intro lines

When writing or standardizing a page, use these conventional intro lines:

- Under `## Arguments Reference`:
- Under `## Arguments Reference`:
  - `The following arguments are supported:`
- Under `## Attributes Reference`:
  - Resources: `In addition to the Arguments listed above - the following Attributes are exported:`
  - Data sources: `In addition to the Arguments listed above - the following Attributes are exported:`

Do not invent alternative section intro wording unless the page already uses a provider-standard variant.

## Resource vs data source wording guardrails

- Resource doc lead sentence should start with: `Manages ...`
- Data source doc lead sentence should start with: `Gets information about ...`
- Data source docs must not include resource-only wording (for example ForceNew language).

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

- **Attributes Reference ordering**
   - `id` is the first exported attribute and all remaining exported attributes are in alphabetical order

- **ForceNew wording (resources only)**
   - Every ForceNew arg includes: "Changing this forces a new {{RESOURCE_NAME}} to be created."
   - Do not use the generic noun `resource` (avoid: "Changing this forces a new resource to be created.").
   - Set `{{RESOURCE_NAME}}` to the specific Azure resource name used by the page (preferred):
      - Use the noun from the page description/title, e.g. "Storage Account", "Key Vault", "Virtual Network".
      - Keep it consistent across the page (same capitalization and wording).
   - If you cannot reliably determine the Azure resource name from the page content, use a deterministic fallback:
      - "Changing this forces a new `azurerm_<name>` to be created." (Terraform resource name in backticks)

- **Notes**
   - Notes use exact `->` / `~>` / `!>` markers and the marker matches the note’s impact

- **Examples**
   - Includes all required args, no `provider`/`terraform` blocks, no hard-coded secrets, internally consistent references
   - Resources: for user-supplied name-like arguments (for example `name`, `profile_name`, `vault_name`), use descriptive values prefixed with `example-` where feasible.
      - Avoid generic placeholders like `"example"`.
      - This applies to argument values like `name = "..."`, not Terraform block labels like `resource "..." "example"`.
      - Prefer a deterministic, descriptive suffix derived from the Terraform **resource type of the block you are editing**:
         - Take the Terraform resource type (for example `azurerm_spring_cloud_service`).
         - Remove the `azurerm_` prefix.
         - Replace underscores with hyphens.
         - Use: `example-<result>`.
         - Example: `azurerm_spring_cloud_service` -> `example-spring-cloud-service`.
      - Only shorten this if required by a documented service naming constraint (length/charset), and keep it as descriptive as possible.
   - Data sources: prefer descriptive `existing-...` placeholders for required identifiers.
      - Avoid the bare placeholder value `"existing"`.

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
- When listing 3+ possible values, use the Oxford comma.
   - Incorrect: Possible values include `Default`, `InitiatorOnly` and `ResponderOnly`.
   - Correct: Possible values include `Default`, `InitiatorOnly`, and `ResponderOnly`.
- Ensure `Arguments Reference` reflects Required/Optional/Computed accurately.
- Mention `ForceNew` in the argument description.
- Document conditional requirements and cross-field constraints (especially ones enforced in `CustomizeDiff`/validation) using `->`/`~>`/`!>` notes as appropriate.
- Keep field order sensible:
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

- Preferred: apply the change directly to the target file (or produce a precise diff/patch).
- If the user explicitly requests the full page content, output it only when it is reasonably sized for chat output.
- For very large pages (for example, long resources like AKS), do not drop content or omit required markers due to output length. Instead:
   - Update the file via a diff/patch.
   - Then output a short tail excerpt (e.g. the last ~20 lines) that includes the relevant updated section.

Always include a short checklist of what you verified against the schema.
