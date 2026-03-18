---
applyTo: "website/docs/**/*.html.markdown"
description: "Shared documentation compliance contract (single source of truth) used by both docs-writer (writer) and /code-review-docs (auditor)."
---

# Docs Compliance Contract

This file is the **single source of truth** for documentation compliance rules in this repository.

## Consumers

Two independent workflows MUST follow this contract:

- **Writer**: `.github/skills/docs-writer/SKILL.md` (docs-writer)
  - Goal: produce docs that satisfy all applicable rules in this contract.
  - Output format is not prescribed by this contract.

- **Auditor**: `.github/prompts/code-review-docs.prompt.md` (`/code-review-docs`)
  - Goal: detect and report violations of rules in this contract.
  - Output structure is defined by the prompt, but the rules enforced MUST come from this contract.

## Canonical sources of truth (precedence)

Use these sources with the following roles:
- Upstream contributor standards in the target repo: `contributing/topics/reference-documentation-standards.md`
  - Baseline source for provider documentation standards.
  - Applicable upstream standards MUST be represented in this contract.
- This contract: `.github/instructions/docs-compliance-contract.instructions.md`
  - Authoritative compliance rules for this repository.
  - Audits and edits MUST enforce this contract.
- This repo’s docs instruction file: `.github/instructions/documentation-guidelines.instructions.md`
  - Companion guidance only.
  - May explain workflows, provide examples, and add heuristics, but MUST NOT weaken or contradict this contract.

Conflict resolution:
- This contract is authoritative for documentation compliance in this repository.
- Upstream contributor standards are the baseline reference, but this contract MAY extend or be stricter than upstream to close gaps and prevent run-to-run drift.
- If upstream contributor standards add or tighten a standard, update this contract so coverage is preserved.
- If upstream contributor standards explicitly contradict a contract rule:
  - Follow the contract for this repository’s audits/edits.
  - Treat the discrepancy as a signal to re-evaluate the rule and (if appropriate) update either the contract or the local docs instructions.
- If the companion guidance differs from this contract, follow this contract and update the guidance to re-align.

## Rule IDs

Rules are identified by stable IDs so both the writer and auditor can reference the same requirement without drifting.

Contract example guidance:
- Examples in this contract should be synthetic and generic (for example `azurerm_foo_bar`) unless a real identifier is strictly required to explain a deterministic algorithm.

ID format:
- `DOCS-<AREA>-<NNN>`

Areas:
- `EX` = examples (Terraform code blocks in `Example*` sections)
- `NOTE` = notes (`->` / `~>` / `!>` markers, required notes)
- `ARG` = arguments reference (ordering, parity)
- `ATTR` = attributes reference (ordering, coverage)
- `OBS` = observation-only guidance (non-blocking findings)
- `LANG` = language quality (typos, grammar)
- `FMT` = formatting conventions (backticks, canonical intro lines)
- `FM` = frontmatter
- `STRUCT` = required sections + section order
- `IMP` = import instructions/examples (resources)
- `SHAPE` = schema shape parity (block vs inline vs map)
- `WORD` = wording conventions (ForceNew, enum phrasing)
- `TIMEOUT` = timeouts formatting/readability
- `LINK` = link hygiene
- `SEC` = secret/material exposure
- `DEPR` = next-major (vNext) deprecations
- `EVID` = evidence/verification guardrails

## Evidence hierarchy

When a rule requires behavioral claims, use this evidence order:
- Terraform schema + provider implementation (`internal/**`)
- Vendored SDK constants/models in this repo (`vendor/**`) when referenced by validation logic (enums, cipher suites, SDK constants)
- Existing provider docs (tone/phrasing patterns)
- Azure docs for semantics only (service behavior/background), not for provider validation/requirements

If you cannot locate workspace evidence for a claim that affects validity, do not guess.

---

# Contract Rules

## Evidence & guardrails

### DOCS-EVID-001: Do not guess when evidence is required
- **Rule**: If a compliance-relevant claim cannot be backed by schema/implementation evidence (for example example value validity, import ID shape, conditional requirements), do not guess.
- **Writer behavior**: prefer removing/avoiding the unproven claim, or locate evidence.
- **Auditor behavior**: record an Issue stating evidence could not be proven.

---

## Observations

### DOCS-OBS-001: Prefer boolean `*_enabled` over string toggles (observation-only)
- **Rule**: When schema evidence shows an argument is a `TypeString` enum that is effectively a boolean toggle (for example allowed values `Enabled`/`Disabled`, `Enable`/`Disable`, or `On`/`Off`), prefer a boolean `*_enabled` field.
- **Tri-state nuance**: if a third value exists (for example `None`), a string enum may be justified.
- **Auditor behavior**: report as an **Observation** only (not an Issue), unless the docs are incorrect relative to the current schema.
- **Docs behavior**: documentation MUST describe the schema as it exists today. This observation must NOT be used to justify rewriting docs to a hypothetical boolean field; it should only surface as an observation about schema design.

---

## Frontmatter

### DOCS-FM-001: Required frontmatter keys
- **Rule**: Docs pages must include required frontmatter keys as defined by repo standards.
- **Minimum** (as enforced today): `subcategory`, `layout`, `page_title`, `description`.

### DOCS-FM-007: Frontmatter must appear at the beginning of the file
- **Rule**: Resource and data source reference docs MUST include YAML frontmatter at the beginning of the documentation file.

### DOCS-FM-003: Resource `page_title` canonical format
- **Scope**: resource docs under `website/docs/r/**`.
- **Rule**: Resource docs MUST use the canonical YAML `page_title` format: `page_title: "Azure Resource Manager: azurerm_<name>"`.

### DOCS-FM-002: Data source `page_title` must include "Data Source:"
- **Scope**: data source docs under `website/docs/d/**`.
- **Rule**: You must include `Data Source:` in the YAML `page_title`.
- **Rule**: Use the canonical format: `page_title: "Azure Resource Manager: Data Source: azurerm_<name>"`.

### DOCS-FM-004: Frontmatter `description` must match the doc type summary style
- **Rule**: The YAML `description` MUST be a short summary sentence matching the doc type.
- **Rule**: Resource docs MUST use the canonical resource summary style defined by `DOCS-WORD-003` (for example `Manages ...`).
- **Rule**: Data source docs MUST use the canonical data source summary style defined by `DOCS-WORD-003` (for example `Gets information about an existing ...`).

### DOCS-FM-005: `subcategory` must match the service website category
- **Rule**: The YAML `subcategory` value MUST match the website category used for that service in the target provider repo.
- **Rule**: When the target repo exposes an allowed-category list or existing service docs, use that evidence instead of guessing.
- **Rule**: If multiple valid website categories exist for the same service, match the existing documentation for that service.
- **Guardrail**: if the correct category cannot be proven from workspace evidence or the target repo standards, do not guess (see `DOCS-EVID-001`).

### DOCS-FM-006: `layout` must be `azurerm`
- **Rule**: The YAML `layout` value for resource and data source reference docs MUST be `azurerm`.

---

## Structure

### DOCS-STRUCT-006: Reference doc path and filename must match the Terraform name
- **Rule**: Resource documentation for `azurerm_<name>` MUST live at `website/docs/r/<name>.html.markdown`.
- **Rule**: Data source documentation for `azurerm_<name>` MUST live at `website/docs/d/<name>.html.markdown`.
- **Rule**: The documentation filename MUST match the Terraform type suffix exactly.

### DOCS-STRUCT-001: Required sections by doc type
- **Resource docs** (`website/docs/r/**`) MUST include: `Example Usage`, `Arguments Reference`, `Attributes Reference`, `Import`.
- **Data source docs** (`website/docs/d/**`) MUST include: `Example Usage`, `Arguments Reference`, `Attributes Reference`.
- **Data source docs** MUST NOT include: `Import`.

### DOCS-STRUCT-002: Section order
- **Rule**: Section order must follow repo standards (for example: Examples before Arguments, then Attributes, then Timeouts (if present), then Import (resources)).

### DOCS-STRUCT-003: Timeouts section presence
- **Rule**: Include a `Timeouts` section only when the schema defines timeouts for the object.

### DOCS-STRUCT-004: Document title heading by doc type
- **Resources** (`website/docs/r/**`): the top-level heading must be `# azurerm_<name>`.
- **Data sources** (`website/docs/d/**`): the top-level heading must be `# Data Source: azurerm_<name>`.

### DOCS-STRUCT-005: Summary sentence must appear directly below the title
- **Rule**: Immediately below the top-level heading, the page MUST include a short summary sentence.
- **Rule**: Resource docs MUST use the canonical resource summary style defined by `DOCS-WORD-003` (for example `Manages ...`).
- **Rule**: Data source docs MUST use the canonical data source summary style defined by `DOCS-WORD-003` (for example `Gets information about ...`).

---

## Formatting

### DOCS-FMT-001: Canonical section intro lines
- Under `## Arguments Reference`: `The following arguments are supported:`
- Under `## Attributes Reference`: `In addition to the Arguments listed above - the following Attributes are exported:`

### DOCS-FMT-002: Backticks for arguments and values
- **Rule**: Always use backticks around argument/attribute names (for example `resource_group_name`).
- **Rule**: Always use backticks around specific values/enums (for example `Standard`, `Premium`).

### DOCS-FMT-003: Use the most specific code fence language
- **Rule**: Code fences should use the most specific language that matches the snippet.
- **Rule**: Terraform configuration snippets MUST use `hcl` fences; do not use `terraform` fences for HCL configuration.

---

## Import (resources)

### DOCS-IMP-001: Import example correctness
- **Scope**: resources only.
- **Rule**: Import instruction/example must match the provider importer/parser ID shape.
- **Rule**: If the import ID shape cannot be proven from code, do not guess (see DOCS-EVID-001).

### DOCS-IMP-002: Import section must include standard wording and example
- **Scope**: resources only.
- **Rule**: Import section MUST include a resource-specific sentence of the form:
  - `A <Resource Name> can be imported using the `resource id`, e.g.`
  - Use `An` instead of `A` when `<Resource Name>` starts with a vowel.
  - `<Resource Name>` should match the resource name used in the page’s summary sentence (see `DOCS-WORD-003`) and should be singular.
- **Rule**: Import section MUST include a `shell` fenced block containing a `terraform import <resource_address> <resource_id>` example.

### DOCS-IMP-003: Import example determinism (stubs and placeholders)
- **Scope**: resources only.
- **Rule**: The import command MUST use the `.example` instance name, for example: `terraform import azurerm_<type>.example <resource_id>`.
- **Rule**: The subscription ID in the example resource ID MUST be the all-zeros stub: `00000000-0000-0000-0000-000000000000`.
- **Rule**: Name-like placeholder segments in the example resource ID MUST be mechanically derived from the preceding path key to avoid AI-invented values.
  - **Algorithm**:
    1) when an ARM ID path includes a key/value pair like `.../<key>/<value>...`, set `<value>` to `<singular(key)>1`
    2) `singular(key)` is `key` with a trailing `s` removed when present
    3) preserve the key's casing in the derived name (for example `customDomains` -> `customDomain1`)
  - **Special-cases**:
    - `resourceGroups/<value>` MUST use `resourceGroup1`

---

## Schema shape parity

### DOCS-SHAPE-001: Block vs inline vs map parity
- **Rule**: Docs must match the schema's structural shape.
- If schema defines a nested block (commonly `TypeList`/`TypeSet` with `Elem: &Resource{Schema: ...}` and `MaxItems: 1`), docs must describe a `${block}` block and list nested fields under a "A `${block}` block supports the following:" section.
- If schema defines a scalar/inline field (`TypeString`/`TypeBool`/`TypeInt`/etc.), docs must not describe it as a block and must not document nested subfields.
- If schema defines a map (`TypeMap`), docs must describe it as a map (not a block).

### DOCS-SHAPE-005: Primitive list/set parity
- **Rule**: If schema defines a list/set of primitives (for example `TypeList`/`TypeSet` with `Elem: &schema.Schema{Type: schema.TypeString}` or other primitive types), docs must describe it as a list/set of values.
- **Rule**: Docs must not describe a primitive list/set as a nested block with named subfields.

### DOCS-SHAPE-002: Block placement and phrasing by section
- **Rule**: Block arguments belong under `## Arguments Reference`.
  - Bullet: ``* `<block>` - (Optional) A `<block>` block as defined below.`` (use `(Required)` when required)
  - Subsection heading: `A `<block>` block supports the following:`
- **Rule**: Block attributes belong under `## Attributes Reference`.
  - Bullet: ``* `<block>` - A `<block>` block as defined below.``
  - Subsection heading: `A `<block>` block exports the following:`

### DOCS-SHAPE-003: Indefinite article for block headings
- **Rule**: Use `An` when the block name starts with `a`, `e`, `i`, `o`, or `u` (after stripping backticks); otherwise use `A`.

### DOCS-SHAPE-004: Block subsections placement and ordering
- **Rule**: Block subsections must appear after all top-level bullets for their section.
- **Rule**: When multiple block subsections exist within a section, they must be ordered alphabetically by block name.

### DOCS-SHAPE-006: Nested block argument ordering (Arguments Reference)
- **Scope**: nested field bullets inside a block subsection under `## Arguments Reference` (i.e. under `A `<block>` block supports the following:`).
- **Rule**: Nested fields MUST be ordered as:
  1) required nested arguments first (alphabetical)
  2) optional nested arguments next (alphabetical)
  3) `tags` always last when present
- **Rule**: Required vs optional MUST be derived from the nested schema (do not guess).
- **Rule**: Any note blocks that apply to a nested field MUST remain directly attached to that field when reordering.

### DOCS-SHAPE-007: Directional block references must match subsection position
- **Scope**: block references inside block subsections (for example nested bullets that describe another documented block subsection in the same page section).
- **Rule**: When directional wording is used for a referenced block subsection in the same section, `as defined above` MUST be used when the referenced block subsection appears earlier in that section, and `as defined below` MUST be used when the referenced block subsection appears later in that section.
- **Rule**: This does not change the canonical top-level block bullet pattern under `## Arguments Reference` or `## Attributes Reference`, which continues to use `as defined below`.

### DOCS-SHAPE-008: Block subsection separators
- **Scope**: `## Arguments Reference` and `## Attributes Reference`.
- **Rule**: Insert `---` immediately before the first block subsection heading that follows the top-level bullet list.
- **Rule**: Insert `---` between adjacent block subsections.
- **Rule**: Do not insert `---` between ordinary top-level argument or attribute bullets.

---

## Examples

### DOCS-EX-000: Examples must be functional
- **Rule**: Examples MUST be functional; a user should be able to copy/paste and run `terraform plan` without errors.

### DOCS-EX-001: Example Terraform config fences must be `hcl`
- **Scope**: fenced Terraform configuration blocks under headings that start with `Example` (e.g. `## Example Usage`, `## Example ...`).
- **Rule**: Terraform configuration examples MUST use fenced blocks labeled `hcl`.
- **Out of scope**: code blocks outside `Example*` headings.

### DOCS-EX-002: Example Terraform CLI fences must be `shell` or `shell-session`
- **Scope**: fenced CLI blocks under headings that start with `Example`.
- **Rule**: CLI examples MUST use `shell` (single command) or `shell-session` (prompt/output transcript).

### DOCS-EX-003: Examples must be self-contained
- **Rule**: Every Terraform reference used in an Example configuration (`resource`, `data`, `module`, expressions like `azurerm_*.*`, `data.*.*`, `module.*`) MUST be declared somewhere on the same doc page.
- **Allowed pattern**: define shared resources in `## Example Usage`, reference them from other examples on the same page.
- **Remediation rule**: if an Example is not self-contained, fix it by adding the missing `resource`/`data`/`module` declarations to the page (typically in `## Example Usage`), not by deleting the Example section/block.

### DOCS-EX-020: Example self-containedness must be transitive
- **Scope**: Example Terraform configuration blocks (`## Example*`).
- **Rule**: When you add missing `resource`/`data`/`module` declarations to satisfy `DOCS-EX-003`, you MUST ensure the resulting Example is fully runnable:
  - Newly added declarations MUST include all schema-required arguments/blocks for those objects (see `DOCS-EX-011`).
  - Any Terraform references introduced by the newly added declarations MUST also be declared on the same doc page.
  - Repeat until there are no undeclared references (transitive closure).
- **Rule**: Do not stop after fixing only the first-level missing reference if doing so leaves the Example non-functional.
- **Guardrail**: if you cannot complete transitive self-containedness without guessing due to missing workspace evidence, record an Observation and cite `DOCS-EVID-001`.

### DOCS-EX-021: Preserve reference semantics in examples
- **Scope**: Example Terraform configuration blocks (`## Example*`).
- **Rule**: Do not change an argument value from a Terraform reference to a literal (or from a literal to a reference) as a convenience workaround unless schema/implementation evidence proves the replacement is correct and intended.
  - Examples of Terraform references: `azurerm_*.example.*`, `data.*.*`, `module.*`.
  - Examples of problematic "convenience" rewrites: replacing a reference with a plausible-looking hostname/domain string, or removing a reference entirely.
- **Default behavior**: preserve the original reference intent and make the Example self-contained by declaring the referenced object(s) per `DOCS-EX-003`/`DOCS-EX-020`.
- **Guardrail**: if evidence is insufficient to justify a reference↔literal change, do not guess; record an Observation per `DOCS-EVID-001`.

### DOCS-EX-019: Do not replace Terraform references with invented literals
- **Scope**: Example Terraform configuration blocks (`## Example*`).
- **Rule**: When fixing Example self-containedness or undeclared references, you MUST NOT replace Terraform references (for example `azurerm_*.example.*`, `data.*.*`, `module.*`) with invented literal string values (for example `"example.foo.azure.com"`) as a shortcut.
- **Required remediation**: declare the missing referenced `resource`/`data`/`module` blocks on the same doc page (see `DOCS-EX-003`).
- **Exception**: you may replace a reference with a literal only when schema/implementation evidence proves the literal value form and constraints deterministically and the Example is explicitly teaching a literal value scenario (see `DOCS-EX-010`/`DOCS-EX-016`). Otherwise record an Observation per `DOCS-EVID-001`.
- **Independence**: this rule is independent of `DOCS-EX-004`/`DOCS-EX-018`; preserving existing required `depends_on` and example-adjacent notes remains mandatory.

### DOCS-EX-004: Preserve required `depends_on` verbatim when rewriting examples
- **Rule**: If an existing example contains `depends_on = [...]`, it MUST be preserved with the same referenced objects when rewriting that example.
- **Rule**: If prose/note explicitly requires `depends_on` referencing specific objects, the example MUST include that `depends_on` exactly (do not weaken it).
- **How to fix self-containedness**: add missing referenced resources; do not delete/simplify `depends_on`.
- **Hard rule**: if `depends_on` references objects not declared on the page, you MUST add the missing declarations rather than removing those entries.
- **Non-negotiable**: do not remove or shorten an existing `depends_on` to make an example "simpler".

### DOCS-EX-017: Do not introduce net-new `depends_on` without evidence
- **Rule**: Do not introduce `depends_on` in examples unless schema/implementation evidence proves ordering is required, or the docs are explicitly teaching an ordering constraint.
- **Guardrail**: If ordering requirements cannot be proven from schema/implementation evidence, do not add `depends_on` (see DOCS-EVID-001).

### DOCS-EX-018: Preserve example-adjacent notes when rewriting examples
- **Scope**: notes immediately above or directly associated with a Terraform configuration block under headings that start with `Example`.
- **Rule**: If an `Example*` section contains a note that describes required sequencing/validation (for example, it claims a specific `depends_on` is required), you MUST preserve that note when rewriting the example.
- **Rule**: If you change the example in a way that would make the note inaccurate, rewrite the note so it remains correct and evidence-based (do not delete it to avoid the obligation).

### DOCS-EX-005: Examples must not hard-code secrets
- **Rule**: Examples must not contain passwords/tokens/keys/client secrets/private keys/SAS tokens.
- **Fix**: replace literals with `var.<name>` or similar non-secret placeholders.

### DOCS-EX-006: Example minimalism
- **Rule**: Examples should include only required arguments by default.
- **Exception**: include optional arguments only when required for validity (schema/diff-time constraints) or to demonstrate the example’s stated scenario.

### DOCS-EX-007: Example naming convention (nit-level)
- **Rule**: Where feasible, name-like string values should start with `example-` (resources) or `existing-` (data sources).
- **Severity**: drift from this convention is a **nit** and must not, by itself, make a doc review invalid.
- **Auditor behavior**: when this convention is violated and a deterministic rename can be derived from workspace evidence (see `DOCS-EX-015`/`DOCS-EX-016`), report it as a low-priority Issue with a concrete fix step.

Additional auditor behavior (deterministic suffix; nit-level):
- Even when a name-like value already uses the correct prefix (`example-`/`existing-`), if it does not match the deterministic `DOCS-EX-015` type-derived value, the auditor SHOULD still recommend renaming it to the type-derived value when (and only when) schema/implementation evidence proves the type-derived value is valid for that specific field (`DOCS-EX-016`).
- If that validity cannot be proven from workspace evidence, do not guess; record an Observation per `DOCS-EVID-001`.

### DOCS-EX-008: Examples must not include `terraform` or `provider` blocks
- **Rule**: Example Terraform configuration blocks must not include a `terraform { ... }` block or a `provider { ... }` block.

### DOCS-EX-009: Example HCL must be syntactically valid
- **Rule**: Example Terraform configuration blocks must be valid HCL (balanced braces, correct block structure, no obvious truncation).

### DOCS-EX-010: Example values must satisfy schema/implementation constraints
- **Rule**: Example values must satisfy naming/value constraints expressed by schema validations (`ValidateFunc`, enum validations like `validation.StringInSlice`, etc.) and any clearly enforceable diff-time rules.
- **Rule**: If validity cannot be proven from schema/implementation evidence, do not guess compliant values (see DOCS-EVID-001).

### DOCS-EX-011: Examples must include all schema required arguments
- **Rule**: Each Example Terraform configuration block for the primary object being documented must include all schema required arguments/blocks for that object.
- **Rationale**: examples must be copy/pasteable and should not fail due to missing required inputs.

### DOCS-EX-012: Example sections must remain copy/pasteable Terraform
- **Rule**: Do not delete or convert "Example …" Terraform configuration blocks into prose. An `Example*` section must contain copy/pasteable Terraform configuration.
- **Rule**: Do not remove an `Example*` section (or its fenced Terraform configuration block) as a remediation for self-containedness or other example failures.

### DOCS-EX-013: Example instance name convention (style)
- **Rule**: Generally, the resource/data source instance name in examples should be `example`.
- **Severity**: deviations are typically style-level and should not, by themselves, make a page invalid.

### DOCS-EX-014: Avoid multiple examples when possible
- **Rule**: Avoid multiple examples unless a specific configuration is particularly difficult to configure.
- **Rule**: If many complex examples are needed, prefer using the repository `examples/` folder instead of expanding the docs page.

### DOCS-EX-015: Deterministic example name value derivation (nit-level)
- **Scope**: Example Terraform configuration blocks (`## Example*`).
- **Rule**: When the auditor/writer must propose or apply a rename for a name-like argument value, the replacement must be derived deterministically from the Terraform resource/data source type owning the argument.
  - **Resources**: prefer `example-<type-suffix>` where `<type-suffix>` is the Terraform type suffix with underscores replaced by hyphens (for example `azurerm_foo_bar` -> `example-foo-bar`).
  - **Data sources**: prefer `existing-<type-suffix>` using the same derivation.
- **Clarification (mandatory)**: for `name` arguments inside Example HCL blocks, the default value MUST use the **full** owning block's Terraform type suffix (not an abbreviated last segment).
  - Do NOT truncate to the last underscore-delimited segment.
  - Synthetic example: `azurerm_foo_bar_baz` -> `example-foo-bar-baz` (not `example-baz`).
- **Clarification (mandatory)**: this applies to **all** Example blocks on the page, including auxiliary/scaffolding blocks added for self-containedness.
  - Do NOT base an auxiliary block's `name` on the primary resource's type or scenario wording.
  - Synthetic example: if an Example includes both `azurerm_foo_widget` (primary) and `azurerm_bar_dependency` (auxiliary), use `example-foo-widget` and `example-bar-dependency` respectively (not `example-foo-widget-dependency`).
- **Writer behavior**: when you create or update any Example Terraform block (including auxiliary blocks added for self-containedness), you MUST apply this derivation to `name` unless `DOCS-EX-016`/ValidateFunc evidence proves it would be invalid.
- **ValidateFunc-safe fallback**: if schema/implementation evidence shows the preferred value would be invalid, derive a deterministic value that satisfies all proven constraints (allowed characters, separators, casing, and length bounds).
  - Separator selection must be evidence-driven:
    - Prefer `-` when allowed.
    - Otherwise prefer `_` when allowed.
    - Otherwise use no separator when separators are forbidden.
  - Apply proven character/casing constraints:
    - Remove or replace disallowed characters using only transformations justified by evidence.
    - If evidence requires lowercase/uppercase, apply it.
  - Apply proven length constraints:
    - If a maximum length is proven, truncate from the right to fit.
    - If a minimum length is proven and the derived value is shorter, pad deterministically using only characters proven valid by evidence (prefer `1` if digits are allowed; otherwise `a` if letters are allowed).
  - Guardrail: if you cannot determine the allowed character set/separators/length bounds from schema/implementation evidence, or cannot satisfy constraints deterministically (for example a complex regex requirement), do not guess a renamed value (see DOCS-EVID-001).
- **Severity**: this is a nit-level compliance rule and must not, by itself, make a page invalid.

### DOCS-EX-016: Example values must respect ValidateFunc constraints
- **Scope**: Example Terraform configuration blocks (`## Example*`).
- **Rule**: If schema/implementation evidence constrains a string value (for example via `ValidateFunc`, regex, length bounds, charset restrictions, or an enum), any example value violating that constraint is invalid and must be fixed.
- **Example**: if evidence forbids hyphens for a field value, any example value containing `-` is invalid.

---

## Notes

### DOCS-NOTE-001: Note markers must match severity
- `-> **Note:**` informational / guidance
- `~> **Note:**` important operational guidance / pitfalls
- `!> **Note:**` high-impact caution / irreversible or risky actions

### DOCS-NOTE-002: Required conditional notes must be documented
- **Rule**: Cross-field requirements from schema constraints and diff-time validation (e.g., `CustomizeDiff`, expand/flatten rules that enforce compatibility) MUST be documented as notes where they affect valid configuration.
- **Rule**: If a note claims a requirement (e.g. ordering/`depends_on`), the example must match it.

### DOCS-NOTE-005: Conditional requirements must use `~> **Note:**`
- **Rule**: Notes describing conditional requirements/conflicts/compatibility rules that prevent configuration errors MUST use `~> **Note:**` (not `->`).

### DOCS-NOTE-006: ForceNew guidance must use `~> **Note:**`
- **Rule**: Notes warning about ForceNew-related behavior (or guidance intended to prevent ForceNew surprises) should use `~> **Note:**`.

### DOCS-NOTE-003: Note formatting
- **Rule**: Notes must use the exact format: `(->|~>|!>) **Note:** <text>`.

### DOCS-NOTE-004: Note correctness
- **Rule**: Note content must not contradict schema/implementation behavior.
- **Rule**: If a note states a requirement, the schema/implementation must support it; otherwise rewrite/remove the claim.

### DOCS-NOTE-007: Do not document breaking changes as notes
- **Rule**: Do not add breaking changes as notes in resource documentation.
- **Rule**: Breaking changes in a minor version belong in the changelog; breaking changes in a major version belong in the upgrade guide.

### DOCS-NOTE-008: De-duplicate equivalent notes
- **Rule**: Do not document the same conditional requirement/conflict multiple times in separate notes.
- **Rule**: If two or more notes describe the same constraint (including inverse phrasing), they MUST be merged into a single note that states the full constraint clearly.
- **Example combined note pattern** (adjust wording to match the extracted constraint evidence):
  - `~> **Note:** The `X` block is required when `Y` is set to `A` and must not be specified when `Y` is not set to `A`.`

---

## Arguments Reference

### DOCS-ARG-001: Schema parity (no invented or missing fields)
- **Rule**: Docs must not describe fields that do not exist in the schema.
- **Rule**: Docs must cover schema-exposed arguments/blocks that materially affect configuration validity.

### DOCS-ARG-002: Required vs optional ordering
- **Rule**: Arguments must follow the upstream provider ordering:
  1) any arguments that make up the resource/data source ID, with the last user-specified segment (usually `name`) first
  2) `location` (if present)
  3) remaining required arguments (alphabetical)
  4) optional arguments (alphabetical), with `tags` always last

### DOCS-ARG-003: ForceNew behavior must be documented
- **Rule**: For `ForceNew: true` arguments, include the standard ForceNew sentence (see DOCS-WORD-001).

### DOCS-ARG-010: ID-segment ordering must be evidence-based
- **Rule**: Arguments that form the resource/data source ID (ID segments) must be identified using schema/implementation evidence (not assumptions).
- **Auditor behavior**: when enforcing ID-segment ordering, cite evidence from `internal/**` (for example the resource ID parser/type used by Importer/Create/Read).
- **Guardrail**: if you cannot confidently determine which arguments are ID segments from evidence, do not guess an ordering-based Issue; record an Observation describing what evidence is missing (see DOCS-EVID-001).

### DOCS-ARG-008: Argument descriptions must be concise
- **Rule**: Argument descriptions should be concise and avoid excessive detail or external links.
- **Rule**: If more detail is needed, use a note block under the argument.

### DOCS-ARG-011: Argument bullet length cap
- **Rule**: Each argument bullet description MUST be a crisp definition of the field (prefer 1 sentence; 2 sentences maximum).
- **Rule**: Additional caveats, conditional requirements, setup instructions, or multi-paragraph explanations MUST be moved into an inline note under the argument (see DOCS-ARG-008 and DOCS-NOTE-003).
- **Placement**: The note block MUST appear immediately under the argument bullet it applies to (do not move this content into a separate “Notes” section, and do not leave it embedded in the bullet).
- **Marker**: Use `-> **Note:**` for informational setup/background. Use `~> **Note:**` when the note describes a conditional requirement/conflict that affects valid configuration.

Example (rewrite long bullet to bullet + note):
- Before (non-compliant):
  - ``* `foo_id` - (Optional) The ID of the related resource. If you are using a managed DNS service ...``
- After (compliant):
  - ``* `foo_id` - (Optional) The ID of the related resource.``
  - `-> **Note:** If you are using a managed DNS service, you may need to delegate your DNS zone; otherwise validate by creating the required DNS records manually.`

### DOCS-ARG-009: ForceNew sentence placement
- **Scope**: resources only.
- **Rule**: When present, the ForceNew sentence must appear at the end of the argument description.

### DOCS-ARG-006: ForceNew sentence scope (resources vs data sources)
- **Rule**: Resource docs must use the ForceNew sentence for `ForceNew: true` fields.
- **Rule**: Data source docs must not use ForceNew wording (data sources do not create resources).

### DOCS-ARG-007: Required arguments must be documented
- **Rule**: All schema required arguments/blocks must be documented in Arguments Reference.

### DOCS-ARG-004: Defaults must be documented
- **Rule**: When schema defines a default value, docs must include a `Defaults to ...` sentence.

### DOCS-ARG-005: Validations must be documented (when constraining user input)
- **Rule**: When schema validations constrain values (enums, bounds, etc.), docs must describe allowed values using the standard wording (see DOCS-WORD-002).

---

## Attributes Reference

### DOCS-ATTR-001: Attributes ordering
- **Rule**: `id` first, then remaining computed attributes alphabetical.

### DOCS-ATTR-002: Computed attribute coverage
- **Rule**: Computed attributes surfaced by the schema should be documented.

### DOCS-ATTR-003: Attribute descriptions must not include defaults/enums
- **Rule**: Attribute descriptions should be concise and must not include possible values or default values (those belong in Arguments Reference).

### DOCS-ATTR-004: Do not special-case common fields in Attributes Reference
- **Rule**: Do not special-case `name`, `resource_group_name`, `location`, or `tags` under `## Attributes Reference`.
- **Rule**: Ordering is always `id` first, then remaining attributes alphabetical.

### DOCS-ATTR-005: Nested block attribute ordering (Attributes Reference)
- **Scope**: nested attribute bullets inside a block subsection under `## Attributes Reference` (i.e. under `A `<block>` block exports the following:`).
- **Rule**: If a nested `id` attribute is present, it MUST be listed first.
- **Rule**: Remaining nested attributes MUST be listed alphabetically.
- **Rule**: Any note blocks that apply to a nested attribute MUST remain directly attached to that attribute when reordering.

---

## Wording

### DOCS-WORD-003: Resource vs data source summary sentence
- **Rule**: Resource docs should start with an action verb (prefer `Manages ...`).
- **Rule**: Data source docs should start with a retrieval verb (prefer `Gets information about ...`).
- **Rule**: Data source docs must not use resource-only wording (for example `Manages`, `Creates`, or ForceNew wording).

### DOCS-WORD-004: `*_enabled` field phrasing differs by section
- **Rule**: In `## Arguments Reference`, for boolean fields ending in `_enabled`, prefer: `Should <thing> be enabled?` (include defaults when known).
- **Rule**: In `## Attributes Reference`, prefer: `Is <thing> enabled?`
- **Rule**: Derive `<thing>` from the field name by removing the trailing `_enabled`, replacing underscores with spaces, and wrapping the result in backticks.

### DOCS-WORD-001: ForceNew sentence
- **Rule**: The ForceNew sentence MUST be exactly: `Changing this forces a new resource to be created.`

### DOCS-WORD-002: Enum wording
- **Rule**: Use `Possible values are ...`.
- **Single-value case**: use `The only possible value is ...`.
- **Range case**: use `Possible values range between `x` and `y`.` when the validation defines a numeric range.
- **Rule (mandatory rewrite):** replace legacy enum phrasing with the canonical phrasing.
  - Replace `Valid options are` with `Possible values are`.
  - Replace `Valid values are` with `Possible values are`.
  - Replace `Possible values include` with `Possible values are`.

### DOCS-WORD-005: Oxford comma for lists
- **Rule**: For lists of 3+ items in prose (including enum lists), use the Oxford comma.
- **Example**: `Possible values are `A`, `B`, and `C`.` (not `Possible values are `A`, `B` and `C`.`)

### DOCS-WORD-006: Use the canonical resource name in section prose
- **Scope**: resource docs under `website/docs/r/**`.
- **Rule**: In `## Attributes Reference`, `## Timeouts`, and `## Import`, prose that refers to the documented resource object MUST use the page's canonical resource name from the summary sentence, not a broader generic service object name.
- **Rule**: The canonical resource name is the singular resource noun phrase used in the summary sentence (for example, from `Manages an Orchestrated Virtual Machine Scale Set ...`, use `Orchestrated Virtual Machine Scale Set`).
- **Rule**: This applies to descriptive phrases such as attribute descriptions, timeout action lines, and import lead-in sentences.
- **Examples**:
  - Prefer `The ID of the Orchestrated Virtual Machine Scale Set.` over `The ID of the Virtual Machine Scale Set.`
  - Prefer `Used when creating the Orchestrated Virtual Machine Scale Set.` over `Used when creating the Virtual Machine Scale Set.`

---

## Timeouts

### DOCS-TIMEOUT-001: Duration readability
- **Rule**: Defaults greater than 60 minutes must be expressed in hours (and match the schema default where available).
- **Rule**: Keep minutes for values `<= 60 minutes`.
- **Example rewrites**:
  - `(Defaults to 720 minutes)` → `(Defaults to 12 hours)`
  - `(Defaults to 1440 minutes)` → `(Defaults to 24 hours)`

### DOCS-TIMEOUT-002: Timeouts link format
- **Rule**: For new resources, use `https://developer.hashicorp.com/terraform/language/resources/configure#define-operation-timeouts`.
- **Rule**: For existing resources, keep the legacy `https://www.terraform.io/language/resources/syntax#operation-timeouts` link to maintain consistency unless updating the section.

### DOCS-TIMEOUT-003: New vs existing timeouts link enforcement
- **Rule**: If a documentation page is newly added, any Timeouts section must use the new developer.hashicorp.com link (see DOCS-TIMEOUT-002).
- **Auditor behavior**:
  - If you can determine the docs page is newly added from the available git context, treat a legacy link as an Issue.
  - If the page is existing/modified, treat a legacy link as allowed (no Issue).
  - If you cannot determine new vs existing from available context, record an Observation (not an Issue).

---

## Language

### DOCS-LANG-001: Fix obvious typos and grammar
- **Rule**: Obvious typos and grammar mistakes in documentation must be fixed.
- **Auditor behavior**: only raise an Issue when the fix is unambiguous and can be provided as an exact patch-ready replacement.

---

## Links

### DOCS-LINK-001: Locale-neutral Microsoft Learn links
- **Rule**: Avoid locale segments like `/en-us/` in documentation URLs unless required.

---

## Deprecations (vNext)

### DOCS-DEPR-001: Next-major deprecations
- **Rule**: When schema indicates next-major deprecations (feature flag patterns), docs should focus on vNext surface area.
- **Rule**: Do not require documenting legacy fields that are not part of the vNext surface area (for example fields gated behind a next-major feature flag, or fields marked as deprecated/removed in the next major version).

### DOCS-DEPR-002: Legacy (non-vNext) fields must not be documented
- **Rule**: When schema/implementation evidence indicates a field is legacy-only (not part of the vNext surface area), docs MUST NOT document that field.
- **Auditor behavior**: if a legacy-only field appears in `## Arguments Reference` or `## Attributes Reference`, record an Issue.

<!-- DOCS-CONTRACT-EOF -->
