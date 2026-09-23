---
description: "Maintainer-authored documentation review rule proposals for Hosted Copilot."
surface: documentation
---

# Maintainer Documentation Rule Proposals

Add rules using this format:

<!--
### DOCS-MAINT-001: Concise rule title

- Rule: Write one concise, enforceable review rule.
- Provenance: confirmed-maintainer-convention
- Rationale: Explain why the rule is authoritative and useful to Hosted review.
-->

### DOCS-FM-009: Ephemeral resource `page_title` canonical format

- Rule: Ephemeral-resource docs must use `page_title: "Azure Resource Manager: azurerm_<name>"`.
- Provenance: inferred-maintainer-convention
- Rationale: PR 47 audited this rule against the complete contributor guide and identified it as a genuine supplemental requirement.

### DOCS-FM-010: Function `page_title` canonical format

- Rule: Function docs must use `page_title: "Azure Resource Manager: <name>"` without the `azurerm_` prefix.
- Provenance: inferred-maintainer-convention
- Rationale: PR 47 audited this rule against the complete contributor guide and identified it as a genuine supplemental requirement.

### DOCS-STRUCT-007: Ephemeral-resource runtime support note

- Rule: Ephemeral-resource docs must carry the exact note `~> **Note:** Ephemeral Resources are supported in Terraform 1.10 and later.` between the title and the summary sentence.
- Provenance: inferred-maintainer-convention
- Rationale: PR 47 audited this rule against the complete contributor guide and identified it as a genuine supplemental requirement.

### DOCS-STRUCT-008: Function runtime support note

- Rule: Function docs must carry the exact note `~> **Note:** Provider-defined functions are supported in Terraform 1.8 and later, and are available from version 4.0 of the provider.` between the title and the summary sentence.
- Provenance: inferred-maintainer-convention
- Rationale: PR 47 audited this rule against the complete contributor guide and identified it as a genuine supplemental requirement.

### DOCS-DEPR-002: Legacy (non-vNext) fields must not be documented

- Rule: When schema or implementation evidence shows a field is legacy-only and outside the vNext surface, that field must not appear in **Arguments Reference** or **Attributes Reference**.
- Provenance: inferred-maintainer-convention
- Rationale: PR 47 audited this rule against the complete contributor guide and identified it as a genuine supplemental requirement.

### DOCS-EX-004: Preserve required `depends_on` verbatim when rewriting examples

- Rule: An existing `depends_on` must be preserved with the same referenced objects when an example is rewritten. Fix self-containedness by declaring the missing objects, not by weakening or deleting `depends_on`.
- Provenance: inferred-maintainer-convention
- Rationale: PR 47 audited this rule against the complete contributor guide and identified it as a genuine supplemental requirement.

### DOCS-EX-017: Do not introduce net-new `depends_on` without evidence

- Rule: Do not introduce a new `depends_on` in an example unless schema or implementation evidence proves the ordering requirement.
- Provenance: inferred-maintainer-convention
- Rationale: PR 47 audited this rule against the complete contributor guide and identified it as a genuine supplemental requirement.

### DOCS-EX-018: Preserve example-adjacent notes when rewriting examples

- Rule: A note that states required sequencing or validation for an example must survive an example rewrite. If the change makes the note inaccurate, correct the note rather than removing it.
- Provenance: inferred-maintainer-convention
- Rationale: PR 47 audited this rule against the complete contributor guide and identified it as a genuine supplemental requirement.

### DOCS-EX-019: Do not replace Terraform references with invented literals

- Rule: Do not replace Terraform references such as `azurerm_*.example.*`, `data.*.*`, or `module.*` with invented literal values. Declare the missing referenced objects on the same page instead.
- Provenance: inferred-maintainer-convention
- Rationale: PR 47 audited this rule against the complete contributor guide and identified it as a genuine supplemental requirement.

### DOCS-EX-020: Example self-containedness must be transitive

- Rule: Declarations added to make an example self-contained must themselves be runnable, including every schema-required argument and block for the added objects.
- Provenance: inferred-maintainer-convention
- Rationale: PR 47 audited this rule against the complete contributor guide and identified it as a genuine supplemental requirement.

### DOCS-EX-021: Preserve reference semantics in examples

- Rule: Do not convert an argument value between a Terraform reference and a literal as a convenience workaround unless schema or implementation evidence proves the replacement is correct.
- Provenance: inferred-maintainer-convention
- Rationale: PR 47 audited this rule against the complete contributor guide and identified it as a genuine supplemental requirement.

### DOCS-EX-022: Data source examples should demonstrate existing-object lookups

- Rule: Data source examples must demonstrate the intended lookup of an existing object, and may assume the looked-up object already exists.
- Provenance: inferred-maintainer-convention
- Rationale: PR 47 audited this rule against the complete contributor guide and identified it as a genuine supplemental requirement.

### DOCS-EX-023: List-resource examples must demonstrate list queries

- Rule: List-resource examples must use `list "azurerm_<name>" "example"` syntax and demonstrate the intended query scopes, including any supported narrowed query.
- Provenance: inferred-maintainer-convention
- Rationale: PR 47 audited this rule against the complete contributor guide and identified it as a genuine supplemental requirement.

### DOCS-EX-024: Ephemeral-resource examples must demonstrate ephemeral reads

- Rule: Ephemeral-resource examples must use `ephemeral "azurerm_<name>" "example"` syntax for the primary documented object.
- Provenance: inferred-maintainer-convention
- Rationale: PR 47 audited this rule against the complete contributor guide and identified it as a genuine supplemental requirement.

### DOCS-EX-025: Function examples must call provider-defined functions

- Rule: Function examples must call the documented function through `provider::azurerm::<name>(...)` syntax.
- Provenance: inferred-maintainer-convention
- Rationale: PR 47 audited this rule against the complete contributor guide and identified it as a genuine supplemental requirement.

### DOCS-IMP-003: Import example determinism (stubs and placeholders)

- Rule: Resource import examples must use the `.example` instance name and the all-zeros subscription stub `00000000-0000-0000-0000-000000000000`.
- Provenance: inferred-maintainer-convention
- Rationale: PR 47 audited this rule against the complete contributor guide and identified it as a genuine supplemental requirement.

### DOCS-FMT-004: Outer fences must contain nested code fences safely

- Rule: A code block that contains a nested triple-backtick block must use four backticks for its outer opening and closing fences.
- Provenance: inferred-maintainer-convention
- Rationale: PR 47 audited this rule against the complete contributor guide and identified it as a genuine supplemental requirement.

### DOCS-ARG-011: Argument bullet concision is semantic, not numeric

- Rule: Argument bullets must stay concise and field-definitional, but sentence count alone is not a defect. Keep the field definition, possible values, defaults, and the ForceNew sentence in the bullet, and move caveats, conditional requirements, or rationale into a note.
- Provenance: local-safeguard
- Rationale: PR 47 audited this rule against the complete contributor guide and identified it as a genuine supplemental requirement.

### DOCS-ARG-012: List-resource query arguments should be ordered alphabetically

- Rule: List-resource query arguments must be ordered required first, then optional, sorted alphabetically within each group.
- Provenance: inferred-maintainer-convention
- Rationale: PR 47 audited this rule against the complete contributor guide and identified it as a genuine supplemental requirement.

### DOCS-ARG-013: Function argument lists must follow function signature order

- Rule: Function arguments must be documented in implementation signature order and rendered as ordered list items rather than resource-style argument bullets.
- Provenance: inferred-maintainer-convention
- Rationale: PR 47 audited this rule against the complete contributor guide and identified it as a genuine supplemental requirement.

### DOCS-ATTR-004: Do not special-case common fields in Attributes Reference

- Rule: Do not special-case `name`, `resource_group_name`, `location`, or `tags` under **Attributes Reference**. Order is `id` first, then the remaining attributes alphabetically.
- Provenance: inferred-maintainer-convention
- Rationale: PR 47 audited this rule against the complete contributor guide and identified it as a genuine supplemental requirement.

### DOCS-NOTE-006: ForceNew guidance must use `~> **Note:**`

- Rule: Notes that warn about ForceNew behavior must use the `~> **Note:**` warning marker.
- Provenance: inferred-maintainer-convention
- Rationale: PR 47 audited this rule against the complete contributor guide and identified it as a genuine supplemental requirement.

### DOCS-NOTE-008: De-duplicate equivalent notes

- Rule: Do not state the same conditional requirement or conflict in more than one note, including inverse phrasing. Merge equivalent notes into a single note.
- Provenance: inferred-maintainer-convention
- Rationale: PR 47 audited this rule against the complete contributor guide and identified it as a genuine supplemental requirement.

### DOCS-NOTE-009: Data source, list-resource, ephemeral-resource, and function field notes are prohibited

- Rule: Data source, list-resource, ephemeral-resource, and function documentation must not use field-level note blocks; keep those field descriptions limited to what the field is.
- Provenance: inferred-maintainer-convention
- Rationale: PR 47 audited this rule against the complete contributor guide and identified it as a genuine supplemental requirement.

### DOCS-SHAPE-001: Block vs inline vs map parity

- Rule: Documentation must match the schema structural shape: a nested block is documented as a block with its own nested-field section, a scalar is not documented as a block, and a `TypeMap` is documented as a map.
- Provenance: inferred-maintainer-convention
- Rationale: PR 47 audited this rule against the complete contributor guide and identified it as a genuine supplemental requirement.

### DOCS-SHAPE-005: Primitive list/set parity

- Rule: A list or set of primitives must be documented as a list of values, never as a nested block with named subfields.
- Provenance: inferred-maintainer-convention
- Rationale: PR 47 audited this rule against the complete contributor guide and identified it as a genuine supplemental requirement.

### DOCS-SHAPE-007: Directional block references must match subsection position

- Rule: Directional block references must match the subsection position, so `as defined below` requires that subsection to appear after the reference.
- Provenance: inferred-maintainer-convention
- Rationale: PR 47 audited this rule against the complete contributor guide and identified it as a genuine supplemental requirement.

### DOCS-WORD-006: Use the canonical resource name in section prose

- Rule: In **Attributes Reference**, **Timeouts**, and **Import**, prose about the documented object must use the canonical resource name from the summary sentence rather than a broader generic noun.
- Provenance: inferred-maintainer-convention
- Rationale: PR 47 audited this rule against the complete contributor guide and identified it as a genuine supplemental requirement.

### DOCS-WORD-007: Use Azure proper-name capitalization in field prose

- Rule: Capitalize Azure object names in prose, for example `Resource Group` rather than `resource group`, when referring to the Azure object rather than generic grouping.
- Provenance: inferred-maintainer-convention
- Rationale: PR 47 audited this rule against the complete contributor guide and identified it as a genuine supplemental requirement.

### DOCS-LANG-001: Fix obvious typos and grammar

- Rule: Fix obvious documentation typos and grammar mistakes. Report one only when the correction is unambiguous and can be stated as an exact replacement.
- Provenance: inferred-maintainer-convention
- Rationale: PR 47 audited this rule against the complete contributor guide and identified it as a genuine supplemental requirement.

### DOCS-LINK-001: Locale-neutral Microsoft Learn links

- Rule: Documentation URLs must avoid locale segments such as `/en-us/` unless the target requires them.
- Provenance: inferred-maintainer-convention
- Rationale: PR 47 audited this rule against the complete contributor guide and identified it as a genuine supplemental requirement.
