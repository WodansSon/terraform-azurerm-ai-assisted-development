---
applyTo: "website/docs/**/*.html.markdown"
description: This document outlines the standards and guidelines for writing documentation for Terraform resources and data sources in the AzureRM provider.
---

# Documentation Guidelines

<a id="documentation-guidelines"></a>

This document outlines the standards and guidelines for writing documentation for Terraform resources and data sources in the AzureRM provider.

<a id="quick-navigation"></a>

**Quick navigation:**

Core: <a href="#canonical-sources">Canonical sources</a> | <a href="#optional-ai-docs-review">Optional AI docs review</a> | <a href="#ai-docs-checks">AI docs checks</a> | <a href="#🚨-critical-pre-implementation-requirements-🚨">Pre-Implementation</a> | <a href="#📋-provider-documentation-standards-note-formatting">Note formatting</a>

AI checks: <a href="#ai-docs-style-enforcement">Style enforcement</a> | <a href="#ai-docs-forcenew-subset">ForceNew subset switching</a> | <a href="#ai-docs-enabled-fields">`*_enabled` wording</a> | <a href="#ai-docs-block-placement">Block placement</a> | <a href="#ai-docs-secrets">Secrets</a> | <a href="#ai-docs-audit">Schema parity</a> | <a href="#ai-docs-quick-audit">Quick audit</a> | <a href="#ai-docs-post-edit">Post-edit</a>

Reference: <a href="#📚-key-differences-resources-vs-data-sources">Resources vs data sources</a> | <a href="#🏗️-documentation-structure">Doc structure</a> | <a href="#📄-resource-documentation-template">Resource template</a> | <a href="#📊-data-source-documentation-template">Data source template</a> | <a href="#✍️-writing-guidelines">Writing guidelines</a> | <a href="#💡-example-configuration-guidelines">Examples</a> | <a href="#📁-import-documentation">Import</a> | <a href="#⏱️-timeout-documentation">Timeouts</a> | <a href="#☁️-azure-specific-documentation-patterns">Azure patterns</a> | <a href="#📋-attributes-reference-differences">Attributes</a> | <a href="#📝-field-documentation-rules">Field rules</a>

<a id="canonical-sources"></a>

## Canonical sources (must follow)

This file is a companion guide. Documentation compliance rules are defined by the docs compliance contract:
- `.github/instructions/docs-compliance-contract.instructions.md` (see "Canonical sources of truth (precedence)").

Rules:
- Treat `contributing/topics/reference-documentation-standards.md` (in the target `hashicorp/terraform-provider-azurerm` repo) as the baseline reference.
- Use this instruction file for authoring guidance, worked examples, and AzureRM-specific heuristics.
- Do not treat this file as a second compliance source.
- If this instruction file conflicts with the docs compliance contract, follow the contract and update this file to re-align.

Practical split:
- Contract: defines what is compliant.
- This file: explains how to produce compliant docs efficiently.
- Prompt/skill: define workflow and output behavior while consuming the contract.

## Optional AI docs review (recommended)

<a id="optional-ai-docs-review"></a>

To run a complete standards + schema parity audit for the currently-open docs page, run:

- <a href="../prompts/code-review-docs.prompt.md">.github/prompts/code-review-docs.prompt.md</a>

This audit is optional and user-invoked (no CI enforcement).

## AI docs checks (migrated from docs-writer skill)

<a id="ai-docs-checks"></a>

When using AI assistance to write or review docs, treat canonical sources + precedence as defined by `.github/instructions/docs-compliance-contract.instructions.md`.

Use the contract for exact compliance requirements:
- `DOCS-FM-*`: frontmatter
- `DOCS-STRUCT-*`: required sections, section order, title shape, timeouts presence
- `DOCS-FMT-*`: canonical intro lines, backticks, formatting conventions
- `DOCS-EX-*`: examples, fences, self-containedness, secrets, `depends_on`, determinism
- `DOCS-IMP-*`: import wording and importer-derived example shapes
- `DOCS-SHAPE-*`: block vs inline vs map parity, block placement, nested ordering
- `DOCS-ARG-*` and `DOCS-ATTR-*`: coverage and ordering
- `DOCS-NOTE-*`: note markers, placement, de-duplication
- `DOCS-WORD-*`, `DOCS-TIMEOUT-*`, `DOCS-LINK-*`, `DOCS-SEC-*`, and `DOCS-EVID-*`: wording, timeouts, link hygiene, secrets, and evidence guardrails

Use this file for companion guidance:
- how to gather schema evidence
- how to choose or structure examples
- AzureRM-specific documentation heuristics
- illustrative templates and snippets

Practical authoring reminders:
- Preserve the resource vs data source distinction in tone and examples.
- Repeat the short summary sentence immediately below the top-level heading; for the exact requirement, see `DOCS-STRUCT-005` and `DOCS-WORD-003` in the contract.
- Keep argument descriptions short, then move caveats or conditions into notes.
- Prefer shared example dependencies in the primary `## Example Usage` block.
- When a rule needs exact wording or ordering, look up the contract instead of relying on memory.

### Mandatory HashiCorp docs style enforcement

<a id="ai-docs-style-enforcement"></a>

When you touch or update any existing documentation page, proactively enforce the upstream contributor style rules even if the user did not explicitly ask for style fixes.

For exact compliance behavior, use the contract as the source of truth:
- `DOCS-FMT-*` for canonical lines and formatting
- `DOCS-WORD-*` for wording conventions
- `DOCS-ATTR-*` and `DOCS-TIMEOUT-*` for attribute ordering and timeout presentation

At minimum, enforce these high-signal items:

- Oxford comma for 3+ values
  - Incorrect: Possible values are `Default`, `InitiatorOnly` and `ResponderOnly`.
  - Correct: Possible values are `Default`, `InitiatorOnly`, and `ResponderOnly`.
- Enum wording (provider standard)
  - Prefer: `Possible values are ...`
  - Rewrite: `Valid values are ...`, `Valid options are ...`, and `Possible values include ...`.
- ForceNew subset switching
  - Avoid "and vice versa"; use the explicit two-group wording (see `ForceNew subset-switch wording`).
- Apply style rules to the entire bullet
  - If you edit an Arguments Reference bullet, enforce enum wording and Oxford commas consistently throughout that bullet.
- Consistent value quoting
  - Enum values must be wrapped in backticks.
- Attributes Reference ordering
  - `id` first, remaining attributes alphabetical.
  - Do not bury `id` in the middle of the list.
- Timeouts duration readability
  - Defaults >60 minutes are expressed in hours.
  - Prefer: `(Defaults to 1 hour)` over `(Defaults to 60 minutes)`
  - Prefer: `(Defaults to 2 hours)` over `(Defaults to 120 minutes)`
- Timeouts link hygiene
  - Prefer the developer.hashicorp.com timeouts link when adding/standardizing the section.
  - If an existing page already uses the legacy terraform.io link and you are not touching the timeouts content, keep it unchanged for consistency.

### Timeouts and import

For exact requirements, see `DOCS-TIMEOUT-*`, `DOCS-IMP-*`, and `DOCS-EVID-001` in the contract.

Companion guidance:
- Use the current timeouts link for new or standardized sections.
- Express defaults greater than 60 minutes as hours for readability.
- When verifying imports, derive the shape from implementation evidence rather than example drift.

### ForceNew subset-switch wording (high-signal)

<a id="ai-docs-forcenew-subset"></a>

If ForceNew behavior is triggered when switching between subsets of values (for example between two groups inside an enum), document it explicitly and bidirectionally.

Companion guidance:
- Avoid “and vice versa” in ForceNew conditions.
- Prefer the canonical "between these two groups" wording from the contract and use it consistently when a field switches between enumerated subsets:
  - Changing this forces a new resource to be created when changing `{{FIELD_NAME}}` between these two groups: `A`, `B`, and `C`; `D`, `E`, and `F`.

This rewrite is preferred because it is bidirectional, removes “vice versa”, and makes the boundary-switch behavior unambiguous.

### Boolean `*_enabled` fields (canonical phrasing)

<a id="ai-docs-enabled-fields"></a>

For boolean fields ending in `_enabled`, use the contract for exact compliance and this file for phrasing guidance:
- In resource docs, prefer: Whether `{{THING}}` is enabled.
- When a default is known in resource docs, add a separate sentence: Defaults to `<value>`.
- In data source docs, prefer: Whether `{{THING}}` is enabled.

Derive `<thing>` from the field name:
- Remove the trailing `_enabled`.
- Replace underscores with spaces.
- Wrap the result in backticks.

### Block placement and ordering (mandatory)

<a id="ai-docs-block-placement"></a>

Do not place all block subsections in one location.

For exact placement, article, separator, and ordering rules, see `DOCS-SHAPE-*` in the contract.

Rules:
- Block arguments belong under `## Arguments Reference`:
  - Example bullet:
    ```markdown
    * `identity` - (Optional) An `identity` block as defined below.
    ```
  - Example subsection heading:
    An `identity` block supports the following:
- Block attributes belong under `## Attributes Reference`:
  - Example bullet:
    ```markdown
    * `identity` - An `identity` block as defined below.
    ```
  - Example subsection heading:
    An `identity` block exports the following:
- Indefinite article rule:
  - Use `An` when the block name starts with `a`, `e`, `i`, `o`, or `u` (after stripping backticks); otherwise use `A`.
- Nested field ordering:
  - Block arguments: required first (alphabetical), then optional (alphabetical), with `tags` last when present.
  - Block attributes: `id` first (if present), then remaining attributes alphabetical.

### Attributes Reference wording restrictions

In `## Attributes Reference`, do not use argument-only phrases such as:
- `Defaults to ...`
- `Possible values are ...`

In `## Attributes Reference`, do not use lifecycle, mutation, or import wording such as:
- `Creates ...`
- `Updates ...`
- `Deletes ...`
- `Changing this forces a new resource to be created.`
- `Import ...`

Attributes should be concise and describe what is exported.

### Frontmatter and document shape

For exact frontmatter, section, and title rules, see `DOCS-FM-*` and `DOCS-STRUCT-*` in the contract.

This file's templates below are illustrative. When a template and the contract differ, update the template and follow the contract.

### TODO placeholder resolution ladder (when scaffolding)

When you encounter scaffolded `TODO` text, resolve it using verifiable sources in this order:
1) Terraform schema + provider implementation (preferred)
2) Existing provider docs for tone/phrasing
3) Official Azure docs for semantics only (write provider-style wording)
4) If still ambiguous: document only what you can verify

Do not leave `TODO` placeholders in the final documentation (do not leave `TODO` placeholders in the final doc output).

### Post-edit validation checklist (high-signal)

After editing a docs page, re-check:
- Arguments ordering (required/optional grouping, `name`/`resource_group_name`/`location` first when present, `tags` last)
- Attributes ordering (`id` first, then alphabetical)
- Notes use correct markers (`->`/`~>`/`!>`) and placement
- Examples are fenced correctly in `Example*` sections (`hcl` for config, `shell`/`shell-session` for CLI) and contain no hard-coded secrets
- Import example ID shape matches importer/parser evidence

For the authoritative pass/fail criteria, use the contract and the deterministic review prompt.

### Secrets in examples (mandatory)

<a id="ai-docs-secrets"></a>

Examples must not contain hard-coded secrets (passwords, tokens, shared keys, client secrets, private keys, SAS tokens, etc.).

If you see a hard-coded secret in an example:
- Replace it with a Terraform `var.<name>` reference (for example `var.client_secret`). The `<name>` must be context-aware and match the setting being configured.
- Do not add a full `variable` block unless it materially improves the clarity of the example.

Preferred pattern (minimal):
```hcl
resource "azurerm_..." "example" {
  client_secret = var.client_secret
}
```

### Schema + docs audit (recommended)

<a id="ai-docs-audit"></a>

After writing or updating a page, run a standards + schema parity pass.

- For a deterministic audit procedure + output format, use `.github/prompts/code-review-docs.prompt.md`.
- If you cannot locate the schema under `internal/**` in the target repo, state that explicitly and perform a docs-standards-only review.

### Quick audit checklist (high-signal)

<a id="ai-docs-quick-audit"></a>

Use the contract rule families as the audit checklist instead of relying on this section as a second rule source:
- `DOCS-FM-*` and `DOCS-STRUCT-*`
- `DOCS-ARG-*`, `DOCS-ATTR-*`, and `DOCS-SHAPE-*`
- `DOCS-EX-*`, `DOCS-IMP-*`, and `DOCS-TIMEOUT-*`
- `DOCS-WORD-*`, `DOCS-LINK-*`, `DOCS-DEPR-*`, and `DOCS-EVID-*`

Companion reminders:
- Preserve product casing in short descriptions.
- Do not invent undocumented fields or example values.
- Prefer locale-neutral Learn links when adding external references.

### Mandatory post-edit validation (no exceptions)

<a id="ai-docs-post-edit"></a>

After modifying a docs page under `website/docs/**`:
- Re-check ordering rules (Arguments/Attributes + nested blocks)
- Re-check note markers + placement
- Re-check examples (fences, secrets, self-contained references)
- Re-run the deterministic audit (`/code-review-docs`) and fix Issues before considering the page done

Ensure Markdown formatting passes linting.

The contract remains the source of truth for what constitutes an Issue.

Do not treat fence-language choices outside headings starting with `Example` as failures for this rule.

### Patch failure rule

<a id="ai-docs-patch-failure"></a>

If an edit fails to apply, re-open the target section and retry. Do not proceed without validating the change.

### Where to get field descriptions (when not obvious)

When the wording is not already obvious from the page:
1) Prefer the Terraform schema + provider implementation (preferred)
2) Existing provider docs for tone/phrasing
3) Azure docs for semantics only (write provider-style wording)
4) If still ambiguous: document only what you can verify

### Output expectation

<a id="ai-docs-output-expectation"></a>

- Preferred: apply the change directly to the target file (or provide a precise diff/patch).
- If the user explicitly requests the full page content, output it only when it is reasonably sized.
- For very large pages, patch the file and summarize the updated sections instead of pasting the full page.

### Common doc rules (quick checklist)

<a id="ai-docs-common-checklist"></a>

- Use Terraform names exactly (`azurerm_*`).
- Keep Arguments Reference ordered (required then optional; `name`/`resource_group_name`/`location` first when present; `tags` last).
- Keep Attributes Reference ordered (`id` first, then alphabetical).
- Do not invent fields that are not in the schema.
- Keep examples realistic and minimal; include only required fields unless an optional field is required to demonstrate behavior.

<a id="🚨-critical-pre-implementation-requirements-🚨"></a>

## 🚨 **CRITICAL: PRE-IMPLEMENTATION REQUIREMENTS** 🚨

**⚠️ MANDATORY BEFORE ANY DOCUMENTATION CHANGES ⚠️**

**BEFORE making ANY documentation changes, you MUST:**

1. **📋 READ NOTE FORMATTING GUIDELINES FIRST**
    - Scroll to <a href="#📋-provider-documentation-standards-note-formatting">Provider Documentation Standards (Note Formatting)</a>
    - Review the three note types: Informational (`->`), Warning (`~>`), Caution (`!>`)
    - Understand the categorization criteria for each type

2. **🎯 CATEGORIZE YOUR CONTENT**
   - **Informational (`-> **Note:**`)**: Additional useful information, recommendations, tips, external links
   - **Warning (`~> **Note:**`)**: Information to avoid errors that won't cause irreversible changes (ForceNew behavior, conditional requirements)
   - **Caution (`!> **Note:**`)**: Critical information about irreversible changes, data loss, permanent effects

3. **✅ VALIDATE BEFORE IMPLEMENTATION**
   - Ask yourself: "What type of information am I documenting?"
   - Choose the appropriate note format based on the categorization criteria
   - ForceNew behavior = Warning note (`~> **Note:**`) - users need to avoid configuration errors
   - Azure service limitations = Often caution notes (`!> **Note:**`) if irreversible
   - Additional information/tips = Informational notes (`-> **Note:**`)

**🚫 COMMON MISTAKES TO AVOID:**
- Using informational notes (`->`) for ForceNew behavior warnings
- Using warning notes (`~>`) for simple tips or external links
- Using caution notes (`!>`) for reversible configuration changes

**📋 ENFORCEMENT CHECKLIST:**
- [ ] Read the note formatting guidelines section first
- [ ] Categorized the information type according to the criteria
- [ ] Chosen the appropriate note format based on impact and reversibility
- [ ] Verified the format matches the content type (warning for ForceNew, etc.)

---
<a href="#documentation-guidelines">⬆️ Back to top</a>

<a id="📚-key-differences-resources-vs-data-sources"></a>

## 📚 Key Differences: Resources vs Data Sources

**Language Patterns:**
- **Resources**: Use action verbs - `Manages`, `Creates`, `Configures`
- **Data Sources**: Use retrieval verbs - `Gets information about`, `Use this data source to access information about`

**Description Patterns:**
```markdown
# Resource Description
description: |-
  Manages a Service Resource.

# Data Source Description
description: |-
  Gets information about an existing Service Resource.
```

**Argument Types:**
- **Resources**: Arguments are for configuration (Required/Optional)
- **Data Sources**: Arguments are for identification/filtering (Required for lookup)

**Attributes Reference:**
- **Resources**: Exports computed values after creation/update
- **Data Sources**: Exports all available information from existing resources

**Timeout Blocks:**
- **Resources**: Include all CRUD operations
- **Data Sources**: Only include read operation

**Import Documentation:**
- **Resources**: Include import section with example
- **Data Sources**: Omit import section (data sources don't support import)

---
<a href="#documentation-guidelines">⬆️ Back to top</a>

<a id="🏗️-documentation-structure"></a>

## 🏗️ Documentation Structure

**File Organization:**
```text
website/docs/
 r/                                # Resource documentation
    service_resource.html.markdown
 d/                                # Data source documentation
    service_resource.html.markdown
 guides/                           # Provider guides and tutorials
     guide_name.html.markdown
```

**File Naming:**
- **Resources**: `r/service_resourcetype.html.markdown`
- **Data Sources**: `d/service_resourcetype.html.markdown`
- Use lowercase with underscores, match Terraform resource name exactly

---
<a href="#documentation-guidelines">⬆️ Back to top</a>

<a id="📄-resource-documentation-template"></a>

## 📄 Resource Documentation Template

### Standard Resource Documentation Structure

This template is illustrative. Exact compliance still comes from the docs compliance contract.

````markdown
---
subcategory: "Service Name"
layout: "azurerm"
page_title: "Azure Resource Manager: azurerm_service_resource"
description: |-
  Manages a Service Resource.
---

# azurerm_service_resource

Manages a Service Resource.

## Example Usage

```hcl
resource "azurerm_resource_group" "example" {
  name     = "example-resource-group"
  location = "West Europe"
}

resource "azurerm_service_resource" "example" {
  name                = "example-service-resource"
  resource_group_name = azurerm_resource_group.example.name
  location            = azurerm_resource_group.example.location

  sku_name = "Standard"

  tags = {
    environment = "Production"
  }
}
```

## Arguments Reference

The following arguments are supported:

* `name` - (Required) The name of the Service Resource. Changing this forces a new resource to be created.

* `resource_group_name` - (Required) The name of the Resource Group where the Service Resource should exist. Changing this forces a new resource to be created.

* `location` - (Required) The Azure Region where the Service Resource should exist. Changing this forces a new resource to be created.

* `auto_scaling_enabled` - (Optional) Whether `auto scaling` is enabled. Defaults to `true`.

* `sku_name` - (Optional) The SKU name for this Service Resource. Possible values are `Standard` and `Premium`.

* `tags` - (Optional) A mapping of tags to assign to the resource.

## Attributes Reference

In addition to the Arguments listed above - the following Attributes are exported:

* `id` - The ID of the Service Resource.

* `endpoint` - The endpoint URL of the Service Resource.

## Timeouts

The `timeouts` block allows you to specify [timeouts](https://developer.hashicorp.com/terraform/language/resources/configure#define-operation-timeouts) for certain actions:

* `create` - (Defaults to 30 minutes) Used when creating the Service Resource.
* `read` - (Defaults to 5 minutes) Used when retrieving the Service Resource.
* `update` - (Defaults to 30 minutes) Used when updating the Service Resource.
* `delete` - (Defaults to 30 minutes) Used when deleting the Service Resource.

## Import

A Service Resource can be imported using the `resource id`, e.g.

```shell
terraform import azurerm_service_resource.example /subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/resourceGroup1/providers/Microsoft.Service/resources/resource1
```
````

### Example Usage Subsections

**Standard Pattern**: Use only "## Example Usage" without subsections for most resources.

**When to Add Subsections**: Only create subsections under "Example Usage" when demonstrating meaningfully different configurations:

**Valid Subsection Scenarios:**
- **Platform variations**: "### Windows Function App" vs "### Linux Function App"
- **Authentication methods**: "### (with Base64 Certificate)" vs "### (with Key Vault Certificate)"
- **Deployment modes**: "### Standard Deployment" vs "### Premium Deployment with Custom Domain"
- **Integration patterns**: "### With Virtual Network" vs "### With Private Endpoint"

**Subsection Naming Convention:**
- Use descriptive names that clearly indicate the variation: "### Windows Function App"
- Include context in parentheses when helpful: "### (with Key Vault Certificate)"
- Avoid generic terms like "Basic", "Simple", or "Advanced"

**What NOT to create subsections for:**
- Minor field variations (add to main example instead)
- Single optional field demonstrations
- Tag variations or simple property changes

---
<a href="#documentation-guidelines">⬆️ Back to top</a>

<a id="📊-data-source-documentation-template"></a>

## 📊 Data Source Documentation Template

### Standard Data Source Documentation Structure

This template is illustrative. Exact compliance still comes from the docs compliance contract.

````markdown
---
subcategory: "Service Name"
layout: "azurerm"
page_title: "Azure Resource Manager: Data Source: azurerm_service_resource"
description: |-
  Gets information about an existing Service Resource.
---

# Data Source: azurerm_service_resource

Use this data source to access information about an existing Service Resource.

## Example Usage

```hcl
data "azurerm_service_resource" "example" {
  name                = "existing-service-resource"
  resource_group_name = "existing-resource-group"
}

output "service_resource_id" {
  value = data.azurerm_service_resource.example.id
}
```

## Arguments Reference

The following arguments are supported:

* `name` - (Required) The name of this Service Resource.

* `resource_group_name` - (Required) The name of the Resource Group where the Service Resource exists.

## Attributes Reference

In addition to the Arguments listed above - the following Attributes are exported:

* `id` - The ID of the Service Resource.

* `location` - The Azure Region where the Service Resource exists.

* `sku_name` - The SKU name of the Service Resource.

* `tags` - A mapping of tags assigned to the resource.

## Timeouts

The `timeouts` block allows you to specify [timeouts](https://developer.hashicorp.com/terraform/language/resources/configure#define-operation-timeouts) for certain actions:

* `read` - (Defaults to 5 minutes) Used when retrieving the Service Resource.
````

---
<a href="#documentation-guidelines">⬆️ Back to top</a>

<a id="✍️-writing-guidelines"></a>

## ✍️ Writing Guidelines

### Language and Tone
- **Resources**: Use present tense action verbs ("manages", "creates", "configures")
- **Data Sources**: Use present tense retrieval verbs ("gets", "retrieves", "accesses")
- Be concise and clear, write for both beginners and experts

### Formatting Standards
- **Arguments**: Always use backticks around argument names: `argument_name`
- **Values**: Use backticks around specific values: `Standard`, `Premium`
- **Code blocks**:
  - Terraform configuration examples must use `hcl` fenced code blocks (for example: ```hcl)
  - Terraform CLI command examples (for example `terraform import ...`) must use `shell` fenced code blocks (for example: ```shell)

### Front Matter Requirements
```yaml
---
subcategory: "Service Name"                                  # Azure service category
layout: "azurerm"                                            # Always "azurerm"
page_title: "Azure Resource Manager: azurerm_resource_name"  # Resource page title; for data sources use: "Azure Resource Manager: Data Source: azurerm_resource_name"
description: |-                                              # Brief description
  Manages a Service Resource.                                # For resources
  Gets information about an existing Service Resource.       # For data sources
---
```

**Note:** The `subcategory` value should match the service name from `./internal/services/[service-name]/registration.go`. For exact frontmatter requirements, use `DOCS-FM-*` in the contract.

### Nested Block Documentation
```markdown
---

A `configuration` block supports the following:

* `required_setting` - (Required) Description of the required setting.

* `optional_setting` - (Optional) Description of the optional setting. Defaults to `default_value`.
```

---
<a href="#documentation-guidelines">⬆️ Back to top</a>

<a id="💡-example-configuration-guidelines"></a>

## 💡 Example Configuration Guidelines

### Example naming conventions (provider style)

Rules:
- Resources: user-supplied name-like argument values (for example `name = "..."`) should start with the prefix `example-` where feasible.
- Data sources: required identifier-like argument values should start with the prefix `existing-` where feasible.
- Derive example values from the Terraform **block type being named**, not from the doc topic.
- Prefer deriving the suffix from the full Terraform resource type so examples are predictable.
  - Default: kebab-case (underscores replaced with hyphens), for example `azurerm_resource_group` -> `example-resource-group`.
  - ValidateFunc-safe fallback: if the schema `ValidateFunc` evidence indicates hyphens are not allowed, do not use kebab-case. Use a lowercase no-separator form instead (for example `azurerm_cdn_frontdoor_firewall_policy` -> `examplecdnfrontdoorfirewallpolicy`).
- Honor naming constraints from the schema field `ValidateFunc` when present; abbreviate only as much as required to satisfy validation.

Naming constraints (mandatory; use schema evidence):
- Before finalizing a name-like example value, consult the Terraform schema for that specific field and use the field's `ValidateFunc` to determine naming constraints.

### Example `depends_on` guidance (deterministic)

Rules:
- Existing docs: do not remove or weaken `depends_on` entries in examples purely to make a snippet “self-contained”. If `depends_on` references resources not declared on the page, fix self-containedness by adding the missing referenced resources (prefer the primary `## Example Usage` block).
- Net-new docs: do not introduce `depends_on` unless you have concrete schema/implementation evidence that ordering is required (or the example is explicitly teaching an ordering constraint).
- If a note says `depends_on` must reference multiple resources (for example both a route and a security policy), preserve all required references.
- If you cannot reliably determine whether a page is net-new vs existing, default to preserving `depends_on` intent.

### The "None" Value Pattern in Documentation

When documenting resources that implement the "None" value pattern (where users omit optional fields instead of explicitly setting "None" values), examples should reflect this behavior:

**Example Considerations:**
- Show meaningful field access in outputs rather than fields that might be omitted due to the "None" pattern
- For log scrubbing examples, demonstrate accessing `match_variable` rather than `enabled` since `enabled` follows the "None" pattern
- Focus examples on fields that users actually configure and can reliably access

**Good Example Pattern:**
```hcl
output "log_scrubbing_match_variable" {
  value = data.azurerm_cdn_frontdoor_profile.example.log_scrubbing_rule.0.match_variable
}
```

**Pattern to Avoid:**
```hcl
output "log_scrubbing_enabled" {
  value = data.azurerm_cdn_frontdoor_profile.example.log_scrubbing_rule.0.enabled
}
```

### Example Configuration Strategy

When adding new fields to existing resources, follow this guidance for documentation examples:

**Do Not Update Existing Examples (Standard for Simple Fields):**
- **Simple optional fields**: Do not add to existing basic/complete examples (e.g., `auto_scaling_enabled = true`, `timeout_seconds = 300`)
- **Common configuration options**: Do not update existing examples for basic settings
- **Straightforward additions**: Fields that don't require complex explanation or setup should not clutter existing examples

**Create New Examples (Only for Complex Features):**
- **Complex nested configurations**: Features requiring significant block structures or multiple related fields
- **Advanced use cases**: Features that require specific prerequisites or detailed explanation
- **Feature-specific scenarios**: When the field represents a distinct feature that warrants its own demonstration
- **Conditional configurations**: When field usage depends on specific combinations of other settings

**Example Decision Matrix:**
- **Do not update existing**: `response_timeout_seconds = 120` (simple timeout field)
- **Do not update existing**: `auto_scaling_enabled = false` (basic boolean toggle)
- **New example needed**: Complex nested `security_policy` block with multiple sub-configurations
- **New example needed**: Advanced `custom_domain` setup requiring certificates and DNS validation

---
<a href="#documentation-guidelines">⬆️ Back to top</a>

<a id="📁-import-documentation"></a>

## 📁 Import Documentation

### Resource Import Format

This section is companion guidance only. Use the contract for exact import wording and example determinism.
````markdown
## Import

A Service Resource can be imported using the `resource id`, e.g.

```shell
terraform import azurerm_service_resource.example /subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/resourceGroup1/providers/Microsoft.Service/resources/resource1
```
````

### Import example correctness (mandatory)

Rules:
- The Import example resource ID must match the provider implementation for the resource.
- Derive the expected ID shape from the resource `Importer:` implementation (the parsing function used) and the ID type/constructor used in Create/Read.
- Do not guess ID formats; if you cannot locate the importer/parser evidence, treat the example as unverifiable and locate the evidence first.

### Data Source Import (Not Applicable)
Data sources do not support import operations, so this section should be omitted from data source documentation.

---
<a href="#documentation-guidelines">⬆️ Back to top</a>

<a id="⏱️-timeout-documentation"></a>

## ⏱️ Timeout Documentation

### Resource Timeout Block
```markdown
## Timeouts

The `timeouts` block allows you to specify [timeouts](https://developer.hashicorp.com/terraform/language/resources/configure#define-operation-timeouts) for certain actions:

* `create` - (Defaults to 30 minutes) Used when creating the Resource.
* `read` - (Defaults to 5 minutes) Used when retrieving the Resource.
* `update` - (Defaults to 30 minutes) Used when updating the Resource.
* `delete` - (Defaults to 30 minutes) Used when deleting the Resource.
```

### Timeout default readability (mandatory)

Companion guidance:
- When documenting timeout defaults greater than 60 minutes, express them in hours (for example `12 hours`, `24 hours`) rather than raw minutes.

### Data Source Timeout Block
```markdown
## Timeouts

The `timeouts` block allows you to specify [timeouts](https://developer.hashicorp.com/terraform/language/resources/configure#define-operation-timeouts) for certain actions:

* `read` - (Defaults to 5 minutes) Used when retrieving the Resource.
```

---
<a href="#documentation-guidelines">⬆️ Back to top</a>

<a id="☁️-azure-specific-documentation-patterns"></a>

## ☁️ Azure-Specific Documentation Patterns

### Resource Location Documentation
```markdown
* `location` - (Required) The Azure Region where the Resource should exist. Changing this forces a new resource to be created.
```

### Data Source Location Documentation
```markdown
* `location` - The Azure Region where the Resource exists.
```

### Resource Group Documentation
```markdown
# For Resources
* `resource_group_name` - (Required) The name of the Resource Group where the Resource should exist. Changing this forces a new resource to be created.

# For Data Sources
* `resource_group_name` - (Required) The name of the Resource Group where the Resource exists.
```

### Tags Documentation
```markdown
# For Resources
* `tags` - (Optional) A mapping of tags to assign to the resource.

# For Data Sources
* `tags` - A mapping of tags assigned to the resource.
```

### SKU Documentation
```markdown
# For Resources
* `sku_name` - (Required) The SKU name for this Resource. Possible values are `Standard_S1`, `Standard_S2`, and `Premium_P1`.

# For Data Sources
* `sku_name` - The SKU name of the Resource.
```

---
<a href="#documentation-guidelines">⬆️ Back to top</a>

<a id="📋-attributes-reference-differences"></a>

## 📋 Attributes Reference Differences

### Resource Attributes
- Focus on what becomes available after creation
- Include computed values and system-generated properties
- Show what can be referenced by other resources

**Ordering:**
- List `id` first.
- List all remaining attributes in alphabetical order.
- Do not special-case `name`, `resource_group_name`, `location`, or `tags` under `## Attributes Reference`.

```markdown
## Attributes Reference

In addition to the Arguments listed above - the following Attributes are exported:

* `id` - The ID of the Service Resource.

* `endpoint` - The endpoint URL of the Service Resource.
```

### Data Source Attributes
- Include all available information from the existing resource
- Show comprehensive details that can be used elsewhere
- Focus on what information is retrieved

```markdown
## Attributes Reference

In addition to the Arguments listed above - the following Attributes are exported:

* `id` - The ID of the Service Resource.

* `location` - The Azure Region where the Service Resource exists.

* `sku_name` - The SKU name of the Service Resource.

* `resource_enabled` - Is the `resource` enabled?

* `configuration` - A `configuration` block as defined below.

* `endpoint` - The endpoint URL of the Service Resource.

* `tags` - A mapping of tags assigned to the resource.
```

---
<a href="#documentation-guidelines">⬆️ Back to top</a>

<a id="📝-field-documentation-rules"></a>

## 📝 Field Documentation Rules

### 🚨 **CRITICAL: Field Ordering Standards - MUST FOLLOW**

For exact ordering requirements, use `DOCS-ARG-*`, `DOCS-ATTR-*`, and `DOCS-SHAPE-*` in the contract. This section explains the house style and common review expectations.

**⚠️ MANDATORY ALPHABETICAL ORDERING ⚠️**

**BEFORE writing ANY field documentation, you MUST:**

1. **📋 CATEGORIZE FIELDS**
   - Required fields → Group 1 (comes first)
   - Optional fields → Group 2 (comes second)

2. **🔤 ALPHABETIZE WITHIN GROUPS**
   - Sort required fields alphabetically: `api_version`, `capacity`, `database_name` (after the common Azure fields)
   - Sort optional fields alphabetically: `auto_scaling_enabled`, `retention_days`, `sku_name`, with `tags` at end

   **📝 Note**: Common Azure fields follow a specific standard order within their category:
   - **Required**: `name`, `resource_group_name`, `location` (in this exact order), then other required fields A-Z
   - **Optional**: Other optional fields A-Z, then `tags` at the very end

3. **✅ FINAL VALIDATION**
   - Check: Are all required fields listed before optional fields?
   - Check: Are fields within each group in alphabetical order?
   - Check: Does this match the pattern in other resources?

### Field Ordering Standards
- **Required fields first**: Always list required fields before optional fields in argument documentation
- **Alphabetical within category**: Within required and optional groups, list fields alphabetically
- **Consistent structure**: Maintain the same field ordering pattern across all block documentation

### 📋 **Alphabetical Ordering Checklist**
- [ ] Required fields grouped first
- [ ] Required fields follow standard order: `name`, `resource_group_name`, `location` first, then other required fields A-Z
- [ ] Optional fields grouped second
- [ ] Optional fields sorted A-Z, with `tags` at the very end
- [ ] Common Azure field pattern followed consistently across all resources

### Note Format Standards
- **Use note blocks for conditional behavior**: When field usage depends on other field values, use note format instead of inline descriptions
- **Note syntax**: Use `~> **Note:**` format for important behavioral information
- **Clear conditional logic**: Explain exactly when fields are used vs ignored
- **Separate concerns**: Keep the main field description simple, use notes for complex conditional behavior

Example of proper field documentation:
```markdown
## Arguments Reference

The following arguments are supported:

* `name` - (Required) The name of the Service Resource. Changing this forces a new resource to be created.

* `resource_group_name` - (Required) The name of the Resource Group where the Service Resource should exist. Changing this forces a new resource to be created.

* `location` - (Required) The Azure Region where the Service Resource should exist. Changing this forces a new resource to be created.

* `auto_scaling_enabled` - (Optional) Whether `auto scaling` is enabled. Defaults to `true`.

* `sku_name` - (Optional) The SKU name for this Service Resource. Possible values are `Standard` and `Premium`.

* `timeout_seconds` - (Optional) The timeout in seconds. Defaults to `300`.

* `tags` - (Optional) A mapping of tags to assign to the resource.
```

**✅ Notice the alphabetical pattern:**
- **Required**: `name`, `resource_group_name`, `location` (A-Z)
- **Optional**: `auto_scaling_enabled`, `sku_name`, `timeout_seconds`, `tags` (A-Z)

### Azure-Specific Documentation Standards
- **Valid values only**: Only document values that are actually supported by the provider implementation and service behavior
- **API validation**: Verify all possible values against Terraform schema evidence first, then Azure SDK constants and service documentation when appropriate
- **Cross-reference validation**: When implementing similar features across resources, ensure consistent value documentation
- **SDK alignment**: Match documentation values with Azure SDK enum constants where applicable

### Deprecation and Breaking Change Documentation

**Deprecated Field Documentation:**
When fields are deprecated using the provider's "next major version" feature flag system (for example `FivePointOh` today), follow HashiCorp's standard practice:

**Remove deprecated fields from documentation** - Users will receive deprecation warnings directly from the resource implementation when they use deprecated fields. Documentation should only show the current, supported fields.

```markdown
# Only document the new field - remove the deprecated field entirely
* `new_field` - (Optional) New field description that replaces the deprecated `legacy_field`.
```

**Breaking Change Documentation Rules:**
- **Remove deprecated fields**: Do not document deprecated fields - users get warnings from the resource itself
- **Document replacement fields**: Focus documentation on the new, supported field patterns
- **Upgrade guides**: Document migration paths in version-specific upgrade guides, not in resource documentation
- **Clean documentation**: Keep resource documentation focused on current functionality

**Documentation Updates During Breaking Changes:**
- **Current version docs**: Remove deprecated fields, document only current supported fields
- **Major version docs**: Clean up all legacy references and focus on current API
- **Upgrade guides**: Migration instructions belong in upgrade guides, not resource docs

**For complete deprecation patterns and next-major feature flag usage, see:** [Schema Patterns - FivePointOh Feature Flag Patterns](./schema-patterns.instructions.md#🚀-fivepointoh-feature-flag-patterns)

### Cross-Implementation Documentation Consistency

When documenting related Azure resources (like Linux and Windows VMSS), ensure consistency across implementations:

**Field Documentation Consistency:**
- **Identical descriptions**: Use the same field descriptions for shared functionality across resource variants
- **Consistent validation rules**: Document the same validation requirements for equivalent fields
- **Synchronized note blocks**: Apply identical conditional logic notes to both implementations
- **Cross-reference accuracy**: When updating one variant's documentation, verify and update the related variant

**Common Mistakes to Avoid:**
- **Inconsistent rank field requirements**: Ensure both Linux and Windows VMSS document identical rank field usage patterns
- **Mismatched default value claims**: Verify that default value documentation matches actual Azure SDK behavior
- **Divergent validation patterns**: Maintain identical validation logic documentation across related resources

**Documentation Validation Checklist:**
- [ ] Field requirements match between Linux and Windows variants
- [ ] Default value claims verified against Azure SDK behavior
- [ ] Note blocks use consistent conditional logic across implementations
- [ ] Examples demonstrate the same patterns for equivalent functionality

---
<a href="#documentation-guidelines">⬆️ Back to top</a>

<a id="📋-provider-documentation-standards-note-formatting"></a>

## 📋 Provider Documentation Standards (Note Formatting)

### Note Block Standards
All notes should follow the exact same format (`(->|~>|!>) **Note:**`) where level of importance is indicated through the different types of notes as documented below.

Breaking changes should not be included in resource documentation notes:
- Breaking changes in a minor version should be added to the top of the changelog
- Breaking changes in a major version should be added to the upgrade guide

### Informational Note (`-> **Note:**`)
Use informational note blocks when providing additional useful information, recommendations and/or tips to the user.

**Example - Additional information on supported values:**
```markdown
* `type` - (Required) The type. Possible values are `This`, `That`, and `Other`.

-> **Note:** More information on each of the supported types can be found in [type documentation](https://docs.microsoft.com/azure/service-name/)
```

### Warning Note (`~> **Note:**`)
Use warning note blocks when providing information that the user needs to avoid certain errors, however if these errors are encountered they should not break anything or cause irreversible changes.

**Example - Conditional argument requirements:**
```markdown
* `optional_argument_enabled` - (Optional) Whether `optional argument` is enabled. Defaults to `false`.

* `optional_argument` - (Optional) An optional argument.

~> **Note:** The argument `optional_argument` is required when `optional_argument_enabled` is set to `true`.
```

### Caution Note (`!> **Note:**`)
Use caution note blocks when providing critical information on potential irreversible changes, data loss or other things that can negatively affect a user's environment.

**Example - Irreversible changes:**
```markdown
* `irreversible_argument_enabled` - (Optional) Whether `irreversible argument` is enabled. Defaults to `false`.

!> **Note:** The argument `irreversible_argument_enabled` cannot be disabled after being enabled.
```

### Note Formatting Guidelines
- **Consistent format**: Always use the exact syntax patterns shown above
- **Appropriate level**: Choose the right note type based on the severity and impact of the information
- **Clear messaging**: Provide actionable information that helps users avoid problems
- **Avoid overuse**: Use notes for important information, not obvious functionality
- **Reference linking**: Include links to external documentation when helpful

## 📚 Related Implementation Guidance (On-Demand)

### **Advanced Patterns**
- 📐 **Schema Patterns**: [schema-patterns.instructions.md](./schema-patterns.instructions.md) - Schema design and validation (includes deprecation patterns with FivePointOh)

### **Quality & Compliance**
- 📋 **Code Clarity**: [code-clarity-enforcement.instructions.md](./code-clarity-enforcement.instructions.md) - Comment and code quality standards

---
<a href="#documentation-guidelines">⬆️ Back to top</a>
