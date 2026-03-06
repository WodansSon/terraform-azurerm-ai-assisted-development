---
description: "Code review (docs) + schema parity prompt for Terraform AzureRM Provider"
---

# 📋 Code Review - Docs (AzureRM)

# 🚫 EXECUTION GUARDRAILS (READ FIRST)

## Audit-only mode
This prompt is **audit-only**. Do not modify files. Do not propose or apply patches unless the user explicitly asks for fixes.

## Renderer artifact
Some chat UIs may display a leading `-` before this prompt's content. Treat that as a rendering artifact and **do not** comment on it. Proceed with the audit.

## Required active file
This prompt audits the **currently-open documentation page** under `website/docs/**`.

If the active editor is not a file under `website/docs/**` (for example if the active editor is this prompt file, or a README), do **not** attempt the audit.

Instead, respond with:

"Cannot run code-review-docs: active file is not under `website/docs/**`. Open the target docs page and re-run this prompt."

Audit the **currently-open** documentation page under `website/docs/**` for:
- AzureRM documentation standards, and
- parity with the Terraform schema under `internal/**`.

When reviewing documentation standards, treat these as authoritative:
- `contributing/topics/reference-documentation-standards.md`
- `.github/instructions/documentation-guidelines.instructions.md`

Do not treat `.github/skills/docs-writer/SKILL.md` as a canonical rules source. The skill exists for workflow/orchestration; the rules live in the upstream contributor standards + instruction files.

This audit is **optional** and **user-invoked** (no CI enforcement).

## Minimal user input policy
Assume the user may invoke this prompt with minimal instructions (for example: "make it compliant" / "make it match HashiCorp standards").

When this prompt is invoked, you must run the **entire** mandatory procedure below and you must not skip checks simply because the user did not explicitly mention them.

## Determinism policy (mandatory)
This prompt is used in a review→apply→re-review loop. To avoid run-to-run "guessing":

- Do not present multiple fix options (no "either A or B"). Choose a single fix.
- Every Issue must have a patch-ready fix that is fully specified (exact replacement text/snippet), not a vague instruction.
- When fixing ordering issues, always include the complete corrected list/block in the patch-ready section.
- Prefer the smallest deterministic fix that removes the Issue and is consistent with the rules in this prompt and HashiCorp's documentation standards (for example `contributing/topics/reference-documentation-standards.md`).

## ⚡ Mandatory procedure

### 0) Load canonical standards

- If `contributing/topics/reference-documentation-standards.md` exists in the current workspace, read it and apply it.
- Read and apply `.github/instructions/documentation-guidelines.instructions.md`.

### 1) Identify the Terraform object from the doc path
- Resource docs: `website/docs/r/<name>.html.markdown` → `azurerm_<name>`
- Data source docs: `website/docs/d/<name>.html.markdown` → `azurerm_<name>`

Also record the **doc type** from the path:
- `website/docs/r/**` => **Resource** documentation rules
- `website/docs/d/**` => **Data Source** documentation rules

### 2) Locate the schema in `internal/**`
- Search under `internal/**` for the Terraform name (e.g. `azurerm_<name>`).
- Open the relevant registration/implementation files until you find the Terraform schema definition.
- Record the schema file path(s) used.

If you cannot find the schema, say so explicitly and continue with a docs-only standards review.

### 3) Extract schema facts (from the schema definition)
From the schema, extract:
- required arguments
- optional arguments
- computed attributes
- ForceNew fields (`ForceNew: true`)
- constraints that affect docs (e.g. `ConflictsWith`, `ExactlyOneOf`, `AtLeastOneOf`, validations), if clearly visible

**Mandatory: validate all example-used fields against schema evidence (not just `name`)**
- Enumerate every argument assignment used in any Terraform configuration block under headings starting with `Example` (for example: `name = ...`, `sku_name = ...`, `ttl = ...`, nested blocks, and meta-arguments like `depends_on`).
- For each referenced field, locate and record the relevant schema/implementation evidence that constrains it, including (when present):
  - `ValidateFunc` (regex/length/charset/enums)
  - `ConflictsWith`, `ExactlyOneOf`, `AtLeastOneOf`, `RequiredWith`
  - Diff-time / CustomizeDiff constraints and any helper validation functions
- Use that evidence to verify the example values are valid and pasteable.

**Mandatory: Example Validation Matrix (no silent validation):**
- Under `## 🟡 **OBSERVATIONS**`, add a subsection named `Example Validation Matrix`.
- For each Example Terraform configuration block (each fenced `hcl` block under headings starting with `Example`), list every example-used field as a separate bullet with:
  - the resource/data type it belongs to (e.g. `azurerm_virtual_network`)
  - the field path (e.g. `name`, `sku_name`, `identity.0.type`)
  - the example value as written
  - the evidence source (schema file path + the specific constraint type, e.g. `ValidateFunc`, `ConflictsWith`, diff-time validation)
  - the validation result: `validated: pass` or `validated: fail`
- If any line is `validated: fail`, you must record an **Issue** and provide a patch-ready fix.
- If you cannot locate the relevant schema/implementation evidence for any example-used field, record an **Issue** (example validity cannot be proven) and do not guess a compliant value.

**Mandatory: next-major (vNext) deprecated field policy**
The AzureRM provider uses a "next major version" feature-flag deprecation system to phase out legacy fields (for example `features.FivePointOh()` today).

When the schema indicates FivePointOh-based deprecation, docs should describe the **vNext** surface area:
- **Do not require deprecated legacy fields to be documented**, even if they exist in the code as 4.x-only fields.
- **Do require replacement field(s)** to be documented.

How to detect next-major deprecations while reading `internal/**`:
- Schema entries inside `if !features.<NextMajorFlag>() { ... }` blocks (for example `if !features.FivePointOh() { ... }`).
- Fields with `Deprecated:` messages mentioning removal in a major version (for example v5.0, v6.0).
- Typed model fields tagged `removedInNextMajorVersion`.

Reporting requirement:
- Explicitly list the deprecated legacy fields you detected (by name) under `## 🟡 **OBSERVATIONS**`.
- If none are visible, explicitly state: `No next-major deprecated fields detected.`

Parity rules for deprecated fields:
- If docs **include** a deprecated legacy field, mark as an **Issue** (docs should focus on current supported/vNext behavior).
- If docs **omit** a deprecated legacy field, do **not** mark it missing.

**Mandatory: extract cross-field schema constraints**
- Enumerate any cross-field constraints present in the schema (when visible), including:
  - `ConflictsWith`
  - `ExactlyOneOf`
  - `AtLeastOneOf`
  - `RequiredWith`
  - `RequiredWithAll`
  - `AtLeastOneOf` / `AtMostOneOf`-style sets (when represented via helper wrappers)
- Record each constraint as a human-readable rule (for example: "exactly one of `a`, `b`", "`x` conflicts with `y`", "at least one of `p`, `q`", "`m` is required with `n`").
- Treat these schema cross-field constraints as **documentation-required** because they change valid configuration.

**Mandatory reporting requirement (no silent passes):**
- Explicitly list the cross-field schema constraints you found.
- If none are present/visible, explicitly state: `No cross-field schema constraints found.`
- For each constraint, include schema evidence: schema file path + the argument(s) involved.

Then, locate and extract **diff-time validation / conditional requirement** facts from the provider implementation under `internal/**`:
- Search for `CustomizeDiff` and record any user-facing conditional requirements (for example: "required when X is set", "must be set when Y", "only valid when Z").
- If the schema uses helper functions (for example `CustomizeDiff:` calling other functions), follow them until you find the actual conditions.
- Treat these diff-time rules as **documentation-required constraints** when they affect successful `plan/apply`.

**Mandatory reporting requirement (no silent passes):**
- Explicitly list the diff-time constraints you found.
- If none are present/visible, explicitly state: `No diff-time constraints found.`
- For each diff-time constraint, include evidence: file path under `internal/**` + the function name (or closest identifiable snippet reference).

Then, locate and extract **implicit behavior constraints** from expand/flatten logic under `internal/**`:
- Look for behavior that is not directly represented as an argument constraint, but changes resource behavior based on configuration shape.
- Common patterns:
  - Feature enablement/disablement toggled purely by presence/absence of a nested block or list/set length (e.g. 0 blocks => disabled, 1+ blocks => enabled).
  - Provider hardcodes an Azure API value because only one value is supported and it is not exposed as a schema field.
- Treat these as **documentation-required notes** when they are user-visible and likely to surprise users.

**Mandatory reporting requirement (no silent passes):**
- Explicitly list the implicit behavior constraints you found.
- If none are present/visible, explicitly state: `No implicit behavior constraints found.`
- For each, include evidence: file path under `internal/**` + function name/snippet reference.

### 3.5) Coverage preflight (no silent skips)
- Before auditing, **enumerate every doc section** you will cover in this review (e.g. Example Usage, Arguments Reference, each nested block section, Attributes Reference, Timeouts, Import).
- If any required section is missing from the doc (based on the doc type rules below), **stop** and report it as an Issue.
- Build a quick **schema-to-doc map**:
  - For each required argument, optional argument, and computed attribute, explicitly mark: `documented` or `missing`.
  - If any required argument or computed attribute is missing, mark the review as **incomplete coverage** and report those missing items under Issues.
- Do **not** proceed with fixes until coverage is complete (missing items must be listed first).

### 4) Audit the documentation for standards + parity

#### A) Formatting and structure
Validate:
- Frontmatter includes `subcategory`, `layout`, `page_title`, `description`
- H1 matches the doc type:
  - Resources: `# azurerm_<name>`
  - Data Sources: `# Data Source: azurerm_<name>`

**Resource vs Data Source hard rules (must enforce):**

- **Resources** (`website/docs/r/**`)
  - Must include: Example Usage, Arguments Reference, Attributes Reference, Import
  - Timeouts: required **only if** the resource schema defines timeouts (look for `Timeouts:` in the resource implementation)

- **Data Sources** (`website/docs/d/**`)
  - Must include: Example Usage, Arguments Reference, Attributes Reference
  - Must **not** include: Import
  - Timeouts: required **only if** the data source schema defines timeouts (look for `Timeouts:` in the data source implementation)

**Timeouts link standard (new vs existing docs):**
- When a Timeouts section is present, validate the link uses the current format for **new** documentation pages:
  - `https://developer.hashicorp.com/terraform/language/resources/configure#define-operation-timeouts`
- If the page uses the legacy Terraform.io link (for example `https://www.terraform.io/language/resources/syntax#operation-timeouts`):
  - If the docs file appears to be **newly added** in git (e.g. `git status` shows it as untracked/added), mark this as an **Issue** and fail the relevant standards check.
  - If the docs file already existed (modified but not newly added), record this as an **Observation** (existing pages may keep the older link for consistency).
  - If you cannot determine whether the file is new vs existing from the available context, default to **Observation**.

**Timeouts duration readability (mandatory):**
- If a Timeouts section is present, validate each timeout bullet uses human-readable durations.
- **Rule:** when a default duration is greater than 60 minutes, it must be documented in hours.
  - Example rewrites:
    - `(Defaults to 720 minutes)` → `(Defaults to 12 hours)`
    - `(Defaults to 1440 minutes)` → `(Defaults to 24 hours)`
  - Keep minutes for `<= 60 minutes` (e.g. `5 minutes`, `30 minutes`).
- If the Timeouts section uses minutes for a value >60, mark as an **Issue** and provide a patch-ready replacement.

**Import example correctness (mandatory for resources):**
- For resources, validate the Import section:
  - uses the standard wording: "can be imported using the resource id, e.g." (or equivalent), and
  - includes a `terraform import <resource_address> <resource_id>` example.
- Validate the **shape** of the example resource ID against the provider implementation:
  - Find the `Importer:` block and identify the parsing function used (e.g. `parse.<X>ID(...)` or `afdcustomdomains.ParseCustomDomainID(...)`).
  - Derive the expected ID segment pattern from the corresponding ID type (prefer the `.ID()` / constructor format used in Create/Read) and ensure the doc’s example matches that pattern.
- If the Import example ID is malformed (missing required segments, wrong provider/resource types, placeholder missing subscription GUID, etc.), mark as an **Issue** and provide a patch-ready corrected import line.

#### B) Arguments Reference parity and ordering
- All schema required args must be documented
- Documented args must exist in schema
- **Next-major deprecation parity:** if you detect legacy fields that are only present outside next-major mode (e.g. `if !features.<NextMajorFlag>()` or `removedInNextMajorVersion`), do **not** require them to be documented; if they are documented, flag as an Issue.
- **Schema shape parity (block vs inline):** docs must match the schema's structural shape.
  - If schema defines an argument as a **nested block** (typically `TypeList`/`TypeSet` with `Elem: &Resource{Schema: ...}` and `MaxItems: 1` for single blocks), docs must describe it as a `... block` and include a section like: "A `${block}` block supports the following:" listing the nested fields.
  - If schema defines an argument as a **scalar/inline field** (`TypeString`/`TypeBool`/`TypeInt`/etc.), docs must not describe it as a block and must not document nested subfields under it.
  - If schema defines an argument as a **collection of primitives** (`TypeList`/`TypeSet` with `Elem: &Schema{Type: ...}`), docs should describe it as a list/set of values (not as a block with named subfields).
  - If schema defines an argument as a **map** (`TypeMap`), docs must describe it as a map and not as a block.
  - If docs describe `${arg}` as a block but schema indicates `${arg}` is an inline field (common when blocks have been flattened), mark as a parity failure and suggest updating the docs to reflect the flattened field shape.
- Argument ordering must follow `contributing/topics/reference-documentation-standards.md`:
  1. `name` (if present)
  2. `resource_group_name` (if present)
  3. `location` (if present)
  4. remaining required arguments (alphabetical)
  5. optional arguments (alphabetical), with `tags` last (if present)

**Mandatory patch-ready ordering fixes (top-level, one-pass reliability):**
- If you flag any ordering issue for the **top-level** argument bullets under `## Arguments Reference` (including required-vs-optional grouping, or alphabetical ordering inside a group), your `## 🛠️ **MINIMAL FIXES (PATCH-READY)**` section must include the **full corrected top-level bullet list snippet** (the entire argument bullet list for that section), already reordered.
- Do not write a vague instruction like "move `tls` above `dns_zone_id`" without showing the exact corrected bullet list.
- If the doc contains commented-out example blocks adjacent to the argument list, keep them in place and do not let comments break the required/optional grouping.
- **Resources only:** for every ForceNew field in schema, the argument description must end with a ForceNew sentence.
  - Use the standard generic sentence: `Changing this forces a new resource to be created.`
  - Audit rule: if a ForceNew sentence is missing entirely, mark as an **Issue**.
  - If a ForceNew sentence is present but does not match the standard generic sentence, mark as an **Issue** and suggest rewriting it to the standard form.
- **Data sources:** do not use "Changing this forces a new … to be created" wording (data sources do not create resources)
- If schema validations constrain values (e.g. `validation.StringInSlice`, `validation.IntBetween`), docs must include "Possible values …" using the standard phrasing.
- **Mandatory enum phrasing rewrites (no exceptions when found):**
  - Replace `Valid options are` with `Possible values include`.
  - Replace `Valid values are` with `Possible values include`.
  - Replace `Possible values are` with `Possible values include`.
  - If any of these legacy phrases appear anywhere in the doc page, mark it as an **Issue** and suggest the minimal rewrite.
- If schema defines a default value, docs must include "Defaults to `...`."

**Field description vs note split (mandatory, readability):**
- For each argument bullet, keep the bullet text to a crisp definition of what the field is/does (prefer 1 sentence; 2 max).
- If the bullet includes extra caveats, conditional guidance, setup instructions, or multi-paragraph explanations, move that content into an inline note immediately under the field it applies to.
  - Use `-> **Note:**` for informational guidance.
  - Use `~> **Note:**` for conditional requirements/conflicts/ForceNew guidance that prevents common configuration errors.
  - Use `!> **Note:**` for irreversible/high-impact warnings.
- When you apply this split, provide a patch-ready replacement that includes both:
  1) the shortened bullet, and
  2) the new note block directly below it.

**Nested block arguments (ordering rules):**
- For each block subsection under `## Arguments Reference` (e.g. `A <block> block supports the following:`), verify nested field ordering follows the same contributor rules:
  1. Required nested arguments first (alphabetical).
  2. Optional nested arguments next (alphabetical), with `tags` always last if present.
  3. If nested arguments include ID segments such as `name` / `resource_group_name`, or include `location`, those should appear first in the same order used for top-level arguments.
  4. Apply the same rules recursively for nested blocks inside blocks.

**Mandatory patch-ready ordering fixes (one-pass reliability):**
- If you flag an ordering issue for any nested block, your `## 🛠️ **MINIMAL FIXES (PATCH-READY)**` section must include the **full corrected block snippet** (the entire nested bullet list for that block), already reordered.
- Do not write a vague instruction like "reorder alphabetically" without showing the exact corrected order.
- Keep any note blocks (->/~>/!>) attached to the field they describe when moving bullets.

#### C) Attributes Reference parity
- All schema computed attributes must be present in Attributes Reference
- Ordering must follow `contributing/topics/reference-documentation-standards.md`: `id` first, then remaining attributes alphabetical
- Attribute descriptions must be concise and must not include possible/default values

**Nested block attributes (ordering rules):**
- For each block subsection under `## Attributes Reference` (e.g. `A <block> block exports the following:`), verify nested attribute ordering is:
  1. the `id` attribute (if present)
  2. the remaining nested attributes, sorted alphabetically

#### D) Notes / note notation
- All note blocks must use the exact standard format: `(->|~>|!>) **Note:** ...`
- Flag invalid/legacy note styles (e.g. `Important:`, `NOTE:`, missing marker, wrong casing)
- **Semantic validation (marker must match meaning):** validate that the chosen marker is appropriate for what the note says.
  - `->` (informational): tips, extra context, recommendations, external links, clarifications that do not prevent errors or warn about irreversible impact.
  - `~>` (warning): guidance to avoid configuration errors or surprising behavior that is *reversible* (e.g. conditional requirements, conflicts, exactly-one-of, ForceNew behavior, API limitations that block create/update, deprecation/retirement where a configuration will error).
  - `!>` (caution): irreversible or high-impact guidance (e.g. data loss, permanent deletion, cannot be undone/disabled, security exposure with serious consequences).
  - **ForceNew-related guidance** should generally be `~> **Note:**` (do not use `->` for ForceNew warnings).
  - If a note’s content indicates one marker but another is used, mark **Note Notation** as fail and add an Issue suggesting the correct marker.
- Breaking changes should not be documented as notes (they belong in the changelog/upgrade guide)

**Note correctness (content must match code/schema):**
- When a note claims a conditional requirement, conflict, implicit behavior, or a forced value, validate it against what you extracted from:
  - schema cross-field constraints
  - `CustomizeDiff`/diff-time validation
  - implicit behavior constraints (expand/flatten)
- If a note is **contradictory** or materially **incomplete** compared to the extracted rule(s), mark this as an **Issue**.
  - Example: a note says "enabled when zero blocks" but code says "disabled when zero blocks".
  - Example: a note lists only one of two allowed/required cases.
- Prefer minimal edits: rewrite the note text to match the extracted rule and keep the marker appropriate (`~>` for reversible but error-prone constraints).
- **Placement rule:** if a note applies to a single field, place it inline with that field. If it applies to multiple fields or a combined behavior, place it after the relevant list to preserve ordering.

**Conditional requirements (MUST be documented as notes):**
- If the schema (for example `ConflictsWith`, `ExactlyOneOf`, `AtLeastOneOf`, `RequiredWith*`), `CustomizeDiff`/diff-time validation, or implicit behavior constraints (from expand/flatten) enforce cross-field/conditional behavior, the docs must include a `~> **Note:**` that describes the condition in a user-actionable way.
- If such constraints exist in code but are not documented as notes, mark as an **Issue**.

**Note de-duplication (mandatory when applicable):**
- If two or more `~> **Note:**` blocks describe the same conditional constraint in opposite directions (for example "X is required when Y" and "X cannot be specified unless Y"), prefer combining them into a **single** note that states both sides.
- Prefer a single sentence when possible.
- Example combined note pattern (adjust wording to match the extracted constraint evidence):
  - `~> **Note:** The `X` block is required when `Y` is set to `A` and must not be specified when `Y` is not set to `A`.`

**Required-notes coverage checklist (MUST produce):**
- Build a checklist of "required notes" from these sources:
  1) schema cross-field constraints you extracted (for example `ConflictsWith`, `ExactlyOneOf`, `AtLeastOneOf`, `RequiredWith*`)
  2) diff-time constraints you extracted (from `CustomizeDiff` and helper functions)
  3) implicit behavior constraints you extracted (from expand/flatten logic)
- For each item in the checklist, explicitly state whether the docs contain a corresponding note.
  - If present: record the doc section/argument it appears under and a short summary.
  - If present but incorrect/incomplete: mark as an **Issue** and suggest corrected wording.
  - If missing: record what note should be added and mark it as an **Issue**.
- Put the checklist under `## 🟡 **OBSERVATIONS**` (even when everything passes) so missing notes are easy to spot.

**Mandatory reporting requirement (no silent passes):**
- Enumerate **all** note blocks found in the doc (including ones that are fully compliant).
- If there are no notes, explicitly state: `No note blocks found.`
- Put this enumeration under the `## 🟡 **OBSERVATIONS**` section (even when `Note Notation` is `pass`).
- For each note, include: marker (`->`/`~>`/`!>`), the heading/section it appears in (or the argument/attribute name), and a short one-line summary of what it says.

#### E) Example Usage correctness
- Example must include all schema required args
- Example must not include a `terraform` or `provider` block
- Example should be functional and self-contained (no undefined references)
- Resource/data source instance name should generally be `example`

**Mandatory: preserve example meta-arguments (prevents depends_on regressions):**
- When rewriting any Terraform configuration example block under an `Example*` heading, preserve any existing meta-arguments that appear in the original example (especially `depends_on`).
- `depends_on` rules:
  - Atomic copy rule (mandatory): if the original example contains a `depends_on = [...]` line, copy that `depends_on` line verbatim into the rewritten example block.
    - Only modify it if you can cite concrete schema/implementation evidence that a dependency is unnecessary or incorrect, and if you also update any doc note that claimed it was required.
  - If the original example includes `depends_on = [...]`, the rewritten example must also include `depends_on` with the same referenced resources (unless you can cite concrete provider/schema evidence that the ordering constraint is unnecessary and you also update any doc note that claimed it was required).
  - If the docs prose/note says you **must** include `depends_on` referencing specific resources, the example must include that `depends_on` exactly as described (do not weaken it to fewer dependencies).
  - Never remove `depends_on` to satisfy “minimal examples” or “self-containedness”; fix self-containedness by adding missing referenced resources.

**Mandatory: preserve required Example notes when rewriting examples:**
- If an `Example*` section contains a note immediately above the example that describes required sequencing/validation (for example “You must include `depends_on` … otherwise validation fails”), do not delete that note when rewriting the example.
- If you change the example in a way that would invalidate the note, update the note so it remains accurate.

**Mandatory: HCL validity sanity pass (Example sections only):**
- For every fenced Terraform configuration block under headings starting with `Example` (i.e. `hcl` blocks), perform a final structural sanity pass:
  - Braces are balanced (every `{` has a matching `}`)
  - No orphan attributes exist outside a block (for example a line like `resource_group_name = ...` after a resource block has closed)
  - No extra trailing `}` or stray `)`
  - No duplicate closing braces caused by copy/paste
- If the example fails this sanity pass, record an **Issue** and provide a patch-ready full corrected example block.

**Mandatory: example rewrite cleanup (prevents leftover lines):**
- When you fix or rewrite any Terraform configuration example under an `Example*` heading, provide a patch-ready fix as a **full fenced block replacement** (rewrite the entire ```hcl block).
- Do not provide partial edits that only show added lines; the fix must include both removals and the final correct block so leftover lines cannot remain.
- After writing the corrected block, re-scan it for:
  - mis-indented or out-of-block attributes
  - duplicate attributes introduced by merging old and new content
  - stray closing braces
  - meta-argument preservation (mandatory): if the original example block contained `depends_on = [...]` (or the section note requires it), verify the rewritten block still contains that `depends_on = [...]` line verbatim (including all referenced resources). If it does not, treat the rewrite as invalid and rewrite the block again before continuing.

**Mandatory: example minimalism (required-only by default):**
- Examples must be copy/pasteable and should include **only required arguments** by default.
- Do not add optional arguments to an example unless they are necessary to:
  - satisfy schema constraints (including `ValidateFunc` naming constraints, cross-field constraints, or diff-time rules), or
  - demonstrate the specific behavior described by that Example section heading.
- If an example contains optional arguments that are not necessary for validity or the scenario, mark it as an **Issue** and provide a patch-ready minimal rewrite.
- **Mandatory: code fence language (avoid false positives; deterministic scope)**
  - **Scope (strict):** enforce fence-language rules **only** for fenced code blocks under headings that start with `Example` (for example `## Example Usage`, `## Example ...`).
  - **Out of scope:** do **not** flag or rewrite fence languages for code blocks outside `Example*` headings (for example `## Arguments Reference`, `## Import`, `## Timeouts`, `## Attributes Reference`).
    - If you notice suspicious/unlabeled fences outside Example sections, you may record an **Observation** only, but do not create an **Issue** for it.
  - **Terraform configuration** examples must use fenced code blocks labeled `hcl` (for example: ```hcl).
  - **Terraform CLI command** examples must use fenced code blocks labeled `shell` (single commands) or `shell-session` (transcript-style with prompts/output).
  - If an Example section uses an unlabeled fence (plain ```), record an **Issue** and provide a patch-ready rewrite with the correct fence language:
    - use `hcl` when the block is Terraform configuration (starts with `resource`, `data`, `module`, `variable`, `output`, etc.)
    - use `shell`/`shell-session` when the block is CLI commands (starts with `terraform`, `$ terraform`, etc.)
  - If an Example section uses a Terraform configuration fence other than `hcl` (for example ```terraform), record an **Issue** and provide a patch-ready fix that rewrites the fence info string to `hcl`.
- **Mandatory: example naming scan (no silent skip)**
  - Scan every `name = "..."` style assignment inside `## Example Usage` (and any other heading starting with `Example`) and evaluate whether the **string value** follows the naming convention below.
  - If any name-like value violates the convention, you must:
    1) record a **⛏️ Nit Issue** (🔵 Low) describing the non-compliant value(s), and
    2) include a patch-ready fix under `## 🛠️ **MINIMAL FIXES (PATCH-READY)**` with exact line replacements (or a full corrected example block).
- Resources: for user-supplied name-like argument values (for example `name = "..."`), the string value must start with the prefix `example-` where feasible (subject to service naming constraints).
  - This does not apply to Terraform block labels like `resource "..." "example"`.
  - Derivation rule (mandatory, deterministic): derive the example value from the **Terraform block type that the argument belongs to**, not from the doc topic.
    - Example: for `resource "azurerm_resource_group" "example" { name = "..." }` the name must be derived from `azurerm_resource_group` (e.g. `example-resource-group`), even if the doc page is about a different service.
  - Default to a descriptive value derived from the full Terraform resource type:
    - Base: the resource type suffix with underscores replaced by hyphens (kebab-case)
    - Example: `azurerm_resource_group` -> `example-resource-group`
    - Example: `azurerm_virtual_network` -> `example-virtual-network`
  - ValidateFunc-safe fallback (mandatory): if schema `ValidateFunc` evidence indicates hyphens are not allowed for the field value, do **not** use kebab-case.
    - Use a lowercase, no-separator form instead:
      - Prefix rule (mandatory): do not use the `example-` prefix when hyphens are forbidden. Use the prefix `example` (no hyphen).
      - `example` + `<resource type suffix>` with underscores removed
      - Example: `azurerm_virtual_network` -> `examplevirtualnetwork`
    - Hyphen enforcement (mandatory): if `ValidateFunc` forbids hyphens for the field, any example value containing `-` is invalid and must be recorded as an **Issue** and rewritten.
    - Guardrail (generic; prevents regressions when schema evidence is missed): if you cannot locate reliable validation evidence (schema `ValidateFunc` and/or equivalent implementation constraints) for any example-used field value, you must:
      1) mark that field as unproven in the Example Validation Matrix (with `validated: fail`),
      2) record an **Issue** stating that constraints could not be proven from schema/implementation evidence, and
      3) not guess a rewritten example value.
    - If further constraints exist (length/charset/regex), adjust deterministically:
      1) remove disallowed separators/characters
      2) if too long: truncate from the right
      3) if still invalid/ambiguous: abbreviate minimally using schema evidence and record an Issue rather than guessing
  - If the full resource-type-derived value would violate naming constraints, use the schema field's `ValidateFunc` as evidence and abbreviate only as much as required to be compliant.
  - If the schema indicates additional naming constraints (length/charset/regex) via `ValidateFunc`, you must validate that the proposed example value satisfies those constraints.
  - If you cannot confidently derive a compliant value from the available schema evidence, do not guess; instead, mark it as an **Issue** and state what constraint evidence is missing/unclear.
  - A value that merely contains `example` but does not start with `example-` (for example `rg-example`) does **not** satisfy this convention and must be flagged.
  - If this convention is not followed, record it as a **⛏️ Nit Issue** with **🔵 Low** priority and provide a minimal patch-ready rename.
  - Do **not** mark the overall review `Invalid` solely due to example naming conventions.
- Data sources: for required identifier-like argument values, the string value must start with the prefix `existing-` where feasible.
  - If this convention is not followed, record it as a **⛏️ Nit Issue** with **🔵 Low** priority and provide a minimal patch-ready rename.
  - Do **not** mark the overall review `Invalid` solely due to example naming conventions.
- **Mandatory security rule:** no hard-coded secrets (passwords/tokens/keys/client secrets/private keys/SAS tokens).
  - If hard-coded secrets are present, mark as an **Issue** with **🔥 Critical** priority.
  - Suggested fix must be patch-ready:
    - replace the literal with a context-appropriate `var.<name>` reference
    - do not require adding a `variable` block unless needed for clarity
- Example references must be internally consistent

**Non-self-contained examples (mandatory deterministic fix):**
- If you find a Terraform code block under any heading that starts with `Example` (for example `## Example DNS Record Usage`) and it references resources not defined elsewhere on the same page, mark it as an **Issue**.
- **Mandatory: reference scan (no silent skip)**
  - For each Terraform code block under any heading that starts with `Example` (including `## Example Usage`), enumerate:
    - all `resource` blocks declared in that block (type + name)
    - all `data` blocks declared in that block (type + name)
    - all `module` blocks declared in that block (name)
    - all references used in expressions to `azurerm_*.*`, `data.*.*`, and `module.*`.
  - Explicitly state whether each referenced object is declared somewhere on the same page.
  - If any reference is not declared on the page, the example is not self-contained and this must be recorded as an **Issue** with a patch-ready fix.
- **Do not delete or convert "Example …" Terraform code blocks into prose.** An Example section must remain copy/pasteable Terraform.

**depends_on preservation rule (mandatory; prevents regressions):**
- If an Example block includes a `depends_on = [...]` meta-argument, do not remove entries purely to make the example “self-contained”.
- If the example is not self-contained because `depends_on` references missing resources, fix it by **adding the missing referenced resources** to the page (prefer the primary `## Example Usage` block), not by weakening `depends_on`.
- If the surrounding docs text/note explicitly requires a `depends_on` that references multiple resources (for example both a route and a security policy), preserve all required references.
- If an Example section's prose/note says the user **must** include `depends_on` referencing specific resources, then the Example HCL must include that `depends_on`.
  - If the Example HCL omits it, record a **🔴 Issue** (not a Nit) and provide a patch-ready fix.
- Net-new docs guidance (mandatory): do not introduce `depends_on` in examples unless you can cite concrete schema/implementation evidence that ordering is required (or the doc is explicitly teaching an ordering constraint).
- If you cannot reliably determine whether the doc page is net-new vs existing from the available context, default to the conservative behavior: treat it as existing and preserve the `depends_on` intent.
- Only remove or simplify `depends_on` if you can cite concrete schema/implementation evidence that it is unnecessary (and if you also update any note that claimed it was required).
- In `## 🛠️ **MINIMAL FIXES (PATCH-READY)**`, choose exactly one fix (do not offer multiple options):
  1) **Preferred:** expand the primary `## Example Usage` code block to define the missing referenced resources once, then keep the secondary example block referencing them.
  2) If there is no primary Example Usage block, expand the example block itself to include the missing resource definitions.
- "Self-contained" for this rule means: all referenced Terraform resources/data sources used in the example code exist somewhere on the same page (typically in `## Example Usage`).

#### F) Language
- Fix obvious grammar/spelling and consistency issues

#### G) Link hygiene
- Documentation links should be locale-neutral.
- Flag links containing locale path segments such as `/en-us/`, `/en-gb/`, `/de-de/`, etc.
- Suggested fix is to remove the locale segment (e.g. prefer `https://learn.microsoft.com/azure/...` over `https://learn.microsoft.com/en-us/azure/...`) unless there is a strong reason the localized link is required.

## Prompt-only guidance (do not include as headings in output)

Notes:
- Always cite the schema file path(s) you used.
- Prefer referencing doc section headings / argument names over line numbers.
- Do not invent schema fields; if schema cannot be located, explicitly say so and run a docs-only standards check.

Individual Suggestions Format (legend):
- Priority System: 🔥 Critical → 🔴 High → 🟡 Medium → 🔵 Low → ⭐ Notable → ✅ Good
- Review Type Icons:
  - 🔧 Change request - Standards/parity issues requiring fixes
  - ❓ Question - Clarification needed about schema intent or doc meaning
  - ⛏️ Nitpick - Minor style/consistency issues (typos, wording, formatting)
  - ♻️ Refactor suggestion - Structural doc improvements (only when necessary)
  - 🤔 Thought/concern - Potential mismatch or ambiguous behavior requiring discussion
  - 🚀 Positive feedback - Excellent documentation patterns worth highlighting
  - ℹ️ Explanatory note - Context about schema behavior or provider conventions
  - 📌 Future consideration - Larger scope items for follow-up

## ✅ Review output format (use this exact structure)

Output must be **rendered Markdown**.

- Do **not** wrap the review output in triple-backtick code fences.
- Use real headings, bullets, and bold text so it renders in chat.
- Use the section headings **exactly as written below** (including the emoji). Do not rename headings or remove emoji.

Hard determinism rules (mandatory):
- Output must contain exactly one instance of each heading listed below, in this exact order:
  1) `# 📋 **Code Review - Docs**: ${terraform_name}`
  2) `## 📌 **COMPLIANCE RESULT**`
  3) `## 🧾 **SCHEMA SNAPSHOT**`
  4) `## 📊 **DOC STANDARDS CHECK**`
  5) `## 🟢 **STRENGTHS**`
  6) `## 🟡 **OBSERVATIONS**`
  7) `## 🔴 **ISSUES** (only actual problems)`
  8) `## 🛠️ **MINIMAL FIXES (PATCH-READY)**`
  9) `## 🏆 **OVERALL ASSESSMENT**`
- Do not output `## 🏆 **OVERALL ASSESSMENT**` until after you have completed `## 🛠️ **MINIMAL FIXES (PATCH-READY)**` including all snippets, the required self-check, and the explicit confirmations.

Footer rules (mandatory; prevents template restarts):
- After the Overall Assessment content (including the final question when applicable), output exactly these two lines (no bullets, no heading), each on its own line:
  - `Preflight complete: yes`
  - `Skill used: docs-writer`
- These two footer lines must appear exactly once and must be the final lines of the response.
- If you emit the line `Skill used: docs-writer` at any point, you must not output anything else after it.


# 📋 **Code Review - Docs**: ${terraform_name}

## 📌 **COMPLIANCE RESULT**
- **Status**: Valid / Invalid
- **Doc File**: ${docs_file_path}
- **Doc Type**: Resource / Data Source

## 🧾 **SCHEMA SNAPSHOT**
- **Schema File(s)**: ${schema_file_paths}
- **Required Args**: ${required_args}
- **Optional Args**: ${optional_args}
- **Next-major Deprecated Fields**: ${next_major_deprecated_fields}
- **Computed Attributes**: ${computed_attrs}
- **ForceNew Fields**: ${force_new_fields}
- **Cross-field Constraints**: ${cross_field_constraints}
- **Diff-time Constraints**: ${diff_time_constraints}
- **Implicit Behavior Constraints**: ${implicit_behavior_constraints}

## 📊 **DOC STANDARDS CHECK**
- **Frontmatter**: pass/fail + missing keys (if any)
- **Section Order**: pass/fail + missing sections (if any)
- **Argument Ordering**: pass/fail (`name`, `resource_group_name`, `location` first when present, then remaining required alphabetical, then optional alphabetical, `tags` last)
- **Schema Shape**: pass/fail (docs describe blocks vs inline fields consistently with schema)
- **Attributes Coverage**: pass/fail (`id` first, computed attrs present, remaining alphabetical; no other exceptions)
- **ForceNew Wording**: pass/fail (resources only, missing “Changing this forces…” sentence)
- **Conditional Notes**: pass/fail (cross-field/conditional requirements from schema constraints and `CustomizeDiff` are documented using `~> **Note:**`)
- **Note Notation**: pass/fail (->/~>/!> exact format + marker meaning matches note content)
- **Note Accuracy**: pass/fail (note content matches schema/diff-time/implicit behavior; no contradictory or incomplete constraints)
- **Timeouts Readability**: pass/fail (convert defaults >60 minutes to hours)
- **Import Example**: pass/fail (resources only, ID shape matches importer/parser)
- **Link Locales**: pass/fail (no locale segments like `/en-us/` in URLs)
- **Examples**: pass/fail (functional/self-contained, no hard-coded secrets; naming conventions are low-priority nit issues with patch-ready fixes, but do not make the page `Invalid` by themselves)

## 🟢 **STRENGTHS**
- ...

## 🟡 **OBSERVATIONS**
- ...
- Notes: ...
- Required notes coverage: ...

## 🔴 **ISSUES** (only actual problems)

### ${🔧/⛏️/❓} ${summary}
* **Priority**: 🔥 Critical / 🔴 High / 🟡 Medium / 🔵 Low / ✅ Good
* **Location**: ${doc_section_or_argument_name}
* **Schema Evidence**: ${what_in_schema_proves_this}
* **Problem**: clear description
* **Suggested Fix**: minimal edit/snippet

## 🛠️ **MINIMAL FIXES (PATCH-READY)**
Provide a minimal set of edits/snippets that fix all 🔴 Issues. Keep changes small and targeted.

Ordering rule (mandatory): complete this entire section (snippets + required self-check + explicit confirmations) **before** writing `## 🏆 **OVERALL ASSESSMENT**`. Do not move the self-check or confirmations outside this section.

Placement rule (mandatory): all `### Snippet ...` blocks must appear inside this section and nowhere else.

### Required self-check (prevents repeated findings)
- After writing the patch-ready snippets, re-list each 🔴 Issue as a checklist item and state: `fixed by snippet <X>`.
- If any Issue is not fully fixed by the provided snippet(s), you must either:
  - expand the snippet to fully fix it, or
  - change the Issue classification (for example, if it is actually not a real issue).
- Checklist formatting rule (determinism/readability):
  - Do not use emoji in the checklist items.
  - Use this exact format for each item: `- Issue "<issue_title>": fixed by snippet <X>`

### Explicit confirmations (must be the final lines of MINIMAL FIXES)
- all Terraform **configuration** code fences under headings starting with `Example` use `hcl` (no ```terraform or unlabeled fences remain for Terraform config examples)
- all Terraform **CLI command** examples under headings starting with `Example` use `shell` or `shell-session` (no unlabeled fences remain for CLI examples)
- all Terraform code blocks under headings starting with `Example` are self-contained (no undefined references)
- if any Example block originally included `depends_on = [...]` (or an Example note requires it), the final rewritten Example blocks still include the exact `depends_on = [...]` line verbatim (no dependencies removed)
- if any Example section includes `depends_on` (or a note requires it), the final rewritten Example blocks still include the required `depends_on` entries (not removed or weakened)

Ordering guard (mandatory): the last lines of `## 🛠️ **MINIMAL FIXES (PATCH-READY)**` must be the explicit confirmations above. Do not place any other content after them except `## 🏆 **OVERALL ASSESSMENT**`.

## 🏆 **OVERALL ASSESSMENT**

Content rules (user-facing only; do not include internal process notes here):
- Start with a single-line verdict: `Result: pass` or `Result: needs changes`
- Then add one short paragraph summarizing what must change to become compliant.
- If any 🔴 Issues are found, end this section with the exact question:
  - `Do you want me to apply a patch?`

Formatting rules:
- The question `Do you want me to apply a patch?` must be on its own line.
- If the question is present, it must be the final line of the Overall Assessment section content.
