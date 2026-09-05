---
description: "Review Terraform AzureRM resource, data source, list-resource, ephemeral-resource, and function documentation for schema accuracy, usable examples, imports, and required wording."
applyTo: "website/docs/**/*.html.markdown"
---

# AzureRM Documentation Review Rules:

Apply these rules only when the changed lines introduce or expose an actionable documentation defect. Verify schema- and implementation-dependent claims in `internal/**` before commenting.

## Evidence And Coverage:

- `[DOCS-EVID-001]` Do not guess about fields, constraints, defaults, conditional requirements, lifecycle behavior, or import IDs. Report a finding only when repository evidence proves the expected behavior.
- `[DOCS-ARG-001]` Every documented argument must exist in schema, and every schema-exposed argument relevant to the documented object must be documented.
- `[DOCS-ARG-007]` Every schema-required argument and nested block must be documented as required and included in the primary example.
- `[DOCS-ATTR-002]` Every user-relevant computed attribute exposed by schema must be documented under **Attributes Reference**.
- `[DOCS-LANG-001]` Fix obvious documentation typos and grammar mistakes. Report one only when the correction is unambiguous and can be stated as an exact replacement.
- `[DOCS-LINK-001]` Documentation URLs must avoid locale segments such as `/en-us/` unless the target requires them.

## Frontmatter And Structure:

- `[DOCS-FM-001]` Reference documentation must begin with YAML frontmatter containing `subcategory`, `layout`, `page_title`, and `description`.
- `[DOCS-FM-006]` The frontmatter `layout` must be `azurerm`.
- `[DOCS-FM-009]` Ephemeral-resource docs must use `page_title: "Azure Resource Manager: azurerm_<name>"`.
- `[DOCS-FM-010]` Function docs must use `page_title: "Azure Resource Manager: <name>"` without the `azurerm_` prefix.
- `[DOCS-FMT-001]` Resource and data source docs must use the exact introductions `The following arguments are supported:` under **Arguments Reference** and `In addition to the Arguments listed above - the following Attributes are exported:` under **Attributes Reference**.
- `[DOCS-STRUCT-001]` Resource documentation must contain **Example Usage**, **Arguments Reference**, **Attributes Reference**, and **Import**. Data source documentation must contain the first three sections and must not contain **Import**.
- `[DOCS-STRUCT-003]` Include **Timeouts** only when the schema defines timeouts for the documented object.
- `[DOCS-STRUCT-007]` Ephemeral-resource docs must carry the exact note `~> **Note:** Ephemeral Resources are supported in Terraform 1.10 and later.` between the title and the summary sentence.
- `[DOCS-STRUCT-008]` Function docs must carry the exact note `~> **Note:** Provider-defined functions are supported in Terraform 1.8 and later, and are available from version 4.0 of the provider.` between the title and the summary sentence.

## Examples And Imports:

- `[DOCS-EX-000]` The primary example must be functional for its stated scenario.
- `[DOCS-EX-003]` A resource example must declare every referenced resource, data source, and module needed to apply it.
- `[DOCS-EX-004]` An existing `depends_on` must be preserved with the same referenced objects when an example is rewritten. Fix self-containedness by declaring the missing objects, not by weakening or deleting `depends_on`.
- `[DOCS-EX-005]` Examples must not hard-code secrets; use input variables for secret values.
- `[DOCS-EX-008]` Reference examples must not include `terraform` or `provider` blocks unless the documented object requires an explicitly supported exception.
- `[DOCS-EX-010]` Example values must satisfy schema validation, enum casing, and cross-field requirements.
- `[DOCS-EX-017]` Do not introduce a new `depends_on` in an example unless schema or implementation evidence proves the ordering requirement.
- `[DOCS-EX-018]` A note that states required sequencing or validation for an example must survive an example rewrite. If the change makes the note inaccurate, correct the note rather than removing it.
- `[DOCS-EX-019]` Do not replace Terraform references such as `azurerm_*.example.*`, `data.*.*`, or `module.*` with invented literal values. Declare the missing referenced objects on the same page instead.
- `[DOCS-EX-020]` Declarations added to make an example self-contained must themselves be runnable, including every schema-required argument and block for the added objects.
- `[DOCS-EX-021]` Do not convert an argument value between a Terraform reference and a literal as a convenience workaround unless schema or implementation evidence proves the replacement is correct.
- `[DOCS-EX-022]` Data source examples must demonstrate the intended lookup of an existing object, and may assume the looked-up object already exists.
- `[DOCS-EX-023]` List-resource examples must use `list "azurerm_<name>" "example"` syntax and demonstrate the intended query scopes, including any supported narrowed query.
- `[DOCS-EX-024]` Ephemeral-resource examples must use `ephemeral "azurerm_<name>" "example"` syntax for the primary documented object.
- `[DOCS-EX-025]` Function examples must call the documented function through `provider::azurerm::<name>(...)` syntax.
- `[DOCS-FMT-004]` A code block that contains a nested triple-backtick block must use four backticks for its outer opening and closing fences.
- `[DOCS-IMP-001]` A resource import example must match the resource importer or typed resource ID parser exactly.
- `[DOCS-IMP-002]` A resource **Import** section must include a `shell` fenced `terraform import azurerm_<type>.example <resource_id>` command.
- `[DOCS-IMP-003]` Resource import examples must use the `.example` instance name and the all-zeros subscription stub `00000000-0000-0000-0000-000000000000`.

## Argument Accuracy:

- `[DOCS-FMT-005]` Argument and attribute entries must use `*` as the Markdown list marker, matching the contributor-guide templates; do not use `-` for these entries.
- `[DOCS-ARG-003]` A resource argument with `ForceNew: true` must end with the exact sentence `Changing this forces a new resource to be created.` Non-resource documentation must not use ForceNew wording.
- `[DOCS-ARG-004]` A schema default must be documented with a `Defaults to ...` sentence.
- `[DOCS-ARG-005]` A schema validation or enum constraint must be documented using the canonical possible-values wording.
- `[DOCS-ARG-011]` Argument bullets must stay concise and field-definitional, but sentence count alone is not a defect. Keep the field definition, possible values, defaults, and the ForceNew sentence in the bullet, and move caveats, conditional requirements, or rationale into a note.
- `[DOCS-ARG-012]` List-resource query arguments must be ordered required first, then optional, sorted alphabetically within each group.
- `[DOCS-ARG-013]` Function arguments must be documented in implementation signature order and rendered as ordered list items rather than resource-style argument bullets.
- `[DOCS-ATTR-004]` Do not special-case `name`, `resource_group_name`, `location`, or `tags` under **Attributes Reference**. Order is `id` first, then the remaining attributes alphabetically.
- `[DOCS-DEPR-002]` When schema or implementation evidence shows a field is legacy-only and outside the vNext surface, that field must not appear in **Arguments Reference** or **Attributes Reference**.

## Schema Shape Parity:

- `[DOCS-SHAPE-001]` Documentation must match the schema structural shape: a nested block is documented as a block with its own nested-field section, a scalar is not documented as a block, and a `TypeMap` is documented as a map.
- `[DOCS-SHAPE-005]` A list or set of primitives must be documented as a list of values, never as a nested block with named subfields.
- `[DOCS-SHAPE-007]` Directional block references must match the subsection position, so `as defined below` requires that subsection to appear after the reference.

## Notes:

- `[DOCS-NOTE-002]` Cross-field requirements, conflicts, and diff-time constraints that affect valid configuration must be documented and must agree with schema or implementation behavior.
- `[DOCS-NOTE-006]` Notes that warn about ForceNew behavior must use the `~> **Note:**` warning marker.
- `[DOCS-NOTE-008]` Do not state the same conditional requirement or conflict in more than one note, including inverse phrasing. Merge equivalent notes into a single note.
- `[DOCS-NOTE-009]` Data source, list-resource, ephemeral-resource, and function documentation must not use field-level note blocks; keep those field descriptions limited to what the field is.

## Wording:

- `[DOCS-WORD-002]` Use `Possible values are ...` for multiple values, `The only possible value is ...` for one value, and `Possible values range between ...` for a numeric range.
- `[DOCS-WORD-003]` Resource summaries start with `Manages`; data source summaries start with `Gets information about`; list-resource summaries start with `Lists`; ephemeral-resource summaries start with `Use this to access information about`; and function summaries describe the function behavior.
- `[DOCS-WORD-005]` Use the Oxford comma in every documentation prose list of three or more items, including possible-value lists.
- `[DOCS-WORD-006]` In **Attributes Reference**, **Timeouts**, and **Import**, prose about the documented object must use the canonical resource name from the summary sentence rather than a broader generic noun.
- `[DOCS-WORD-007]` Capitalize Azure object names in prose, for example `Resource Group` rather than `resource group`, when referring to the Azure object rather than generic grouping.

## Provenance:

- `DOCS-FMT-005` is a mandatory convention prescribed by upstream contributor-guide templates and reinforced by direct maintainer confirmation.
- `DOCS-WORD-005` is a mandatory confirmed maintainer convention and an upstream documentation gap.
- The remaining rules preserve published contributor requirements or evidence-backed provider conventions selected for the Hosted experiment.
