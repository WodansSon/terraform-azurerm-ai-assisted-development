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

## Frontmatter And Structure:

- `[DOCS-FM-001]` Reference documentation must begin with YAML frontmatter containing `subcategory`, `layout`, `page_title`, and `description`.
- `[DOCS-FM-006]` The frontmatter `layout` must be `azurerm`.
- `[DOCS-STRUCT-001]` Resource documentation must contain **Example Usage**, **Arguments Reference**, **Attributes Reference**, and **Import**. Data source documentation must contain the first three sections and must not contain **Import**.
- `[DOCS-STRUCT-003]` Include **Timeouts** only when the schema defines timeouts for the documented object.

## Examples And Imports:

- `[DOCS-EX-000]` The primary example must be functional for its stated scenario.
- `[DOCS-EX-003]` A resource example must declare every referenced resource, data source, and module needed to apply it.
- `[DOCS-EX-005]` Examples must not hard-code secrets; use input variables for secret values.
- `[DOCS-EX-008]` Reference examples must not include `terraform` or `provider` blocks unless the documented object requires an explicitly supported exception.
- `[DOCS-EX-010]` Example values must satisfy schema validation, enum casing, and cross-field requirements.
- `[DOCS-IMP-001]` A resource import example must match the resource importer or typed resource ID parser exactly.
- `[DOCS-IMP-002]` A resource **Import** section must include a `shell` fenced `terraform import azurerm_<type>.example <resource_id>` command.

## Argument Accuracy:

- `[DOCS-ARG-003]` A resource argument with `ForceNew: true` must end with the exact sentence `Changing this forces a new resource to be created.` Non-resource documentation must not use ForceNew wording.
- `[DOCS-ARG-004]` A schema default must be documented with a `Defaults to ...` sentence.
- `[DOCS-ARG-005]` A schema validation or enum constraint must be documented using the canonical possible-values wording.
- `[DOCS-NOTE-002]` Cross-field requirements, conflicts, and diff-time constraints that affect valid configuration must be documented and must agree with schema or implementation behavior.

## Wording:

- `[DOCS-WORD-002]` Use `Possible values are ...` for multiple values, `The only possible value is ...` for one value, and `Possible values range between ...` for a numeric range.
- `[DOCS-WORD-003]` Resource summaries start with `Manages`; data source summaries start with `Gets information about`; list-resource summaries start with `Lists`; ephemeral-resource summaries start with `Use this to access information about`; and function summaries describe the function behavior.
- `[DOCS-WORD-005]` Use the Oxford comma in every documentation prose list of three or more items, including possible-value lists.

`DOCS-WORD-005` is a mandatory confirmed maintainer convention and an upstream documentation gap. The remaining rules preserve published contributor requirements or evidence-backed provider conventions selected for the Hosted experiment.
