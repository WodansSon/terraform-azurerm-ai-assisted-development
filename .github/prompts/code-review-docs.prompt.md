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
- `.github/skills/docs-writer/SKILL.md` (this repo's enforcement rules)

This audit is **optional** and **user-invoked** (no CI enforcement).

## Minimal user input policy
Assume the user may invoke this prompt with minimal instructions (for example: "make it compliant" / "make it match HashiCorp standards").

When this prompt is invoked, you must run the **entire** mandatory procedure below and you must not skip checks simply because the user did not explicitly mention them.

## ⚡ Mandatory procedure

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

#### B) Arguments Reference parity and ordering
- All schema required args must be documented
- Documented args must exist in schema
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
- **Resources only:** for every ForceNew field in schema, the argument description must end with a ForceNew sentence.
  - Use the standard generic sentence: `Changing this forces a new resource to be created.`
  - Audit rule: if a ForceNew sentence is missing entirely, mark as an **Issue**.
  - If a ForceNew sentence is present but does not match the standard generic sentence, mark as an **Issue** and suggest rewriting it to the standard form.
- **Data sources:** do not use "Changing this forces a new … to be created" wording (data sources do not create resources)
- If schema validations constrain values (e.g. `validation.StringInSlice`, `validation.IntBetween`), docs must include "Possible values …" using the standard phrasing.
- Standard phrasing preference: use `Possible values include ...` (avoid `Valid values are ...`, `Valid options are ...`, and prefer rewriting `Possible values are ...` to `Possible values include ...` when touched).
- If schema defines a default value, docs must include "Defaults to `...`."

**Nested block arguments (ordering rules):**
- For each block subsection under `## Arguments Reference` (e.g. `A <block> block supports the following:`), verify nested field ordering follows the same contributor rules:
  1. Required nested arguments first (alphabetical).
  2. Optional nested arguments next (alphabetical), with `tags` always last if present.
  3. If nested arguments include ID segments such as `name` / `resource_group_name`, or include `location`, those should appear first in the same order used for top-level arguments.
  4. Apply the same rules recursively for nested blocks inside blocks.

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
- Resources: for user-supplied name-like argument values (for example `name = "..."`), prefer values prefixed with `example-` (subject to service naming constraints).
  - This does not apply to Terraform block labels like `resource "..." "example"`.
  - Prefer deriving the suffix from the specific resource type of the block (e.g. `azurerm_spring_cloud_service` -> `example-spring-cloud-service`).
  - If this convention is not followed, record it as an **Observation** (not an Issue) and do not fail compliance solely for this.
- Data sources: prefer descriptive `existing-...` placeholders for required identifiers.
  - If this convention is not followed, record it as an **Observation** (not an Issue) and do not fail compliance solely for this.
- No hard-coded secrets (passwords/tokens/keys). Use `variable` with `sensitive = true` or a generator pattern.
- Example references must be internally consistent

#### F) Language
- Fix obvious grammar/spelling and consistency issues

#### G) Link hygiene
- Documentation links should be locale-neutral.
- Flag links containing locale path segments such as `/en-us/`, `/en-gb/`, `/de-de/`, etc.
- Suggested fix is to remove the locale segment (e.g. prefer `https://learn.microsoft.com/azure/...` over `https://learn.microsoft.com/en-us/azure/...`) unless there is a strong reason the localized link is required.

## ✅ Review output format (use this exact structure)

Output must be **rendered Markdown**.

- Do **not** wrap the review output in triple-backtick code fences.
- Use real headings, bullets, and bold text so it renders in chat.
- Use the section headings **exactly as written below** (including the emoji). Do not rename headings or remove emoji.


# 📋 **Code Review - Docs**: ${terraform_name}

## 📌 **COMPLIANCE RESULT**
- **Status**: Valid / Invalid
- **Doc File**: ${docs_file_path}
- **Doc Type**: Resource / Data Source

## 🧾 **SCHEMA SNAPSHOT**
- **Schema File(s)**: ${schema_file_paths}
- **Required Args**: ${required_args}
- **Optional Args**: ${optional_args}
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
- **Link Locales**: pass/fail (no locale segments like `/en-us/` in URLs)
- **Examples**: pass/fail (functional/self-contained, no hard-coded secrets; naming conventions like `example-...` are observations)

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

## 🏆 **OVERALL ASSESSMENT**

If any Issues are found, end the response with:

"Do you want me to apply a patch?"
One paragraph summary of what to change to become compliant.

### Notes
- Always cite the schema file path(s) you used.
- Prefer referencing doc section headings / argument names over line numbers.
- Do not invent schema fields; if schema cannot be located, explicitly say so and run a docs-only standards check.

### Individual Suggestions Format (legend)

**Priority System:** 🔥 Critical → 🔴 High → 🟡 Medium → 🔵 Low → ⭐ Notable → ✅ Good

**Review Type Icons:**
* 🔧 Change request - Standards/parity issues requiring fixes
* ❓ Question - Clarification needed about schema intent or doc meaning
* ⛏️ Nitpick - Minor style/consistency issues (typos, wording, formatting)
* ♻️ Refactor suggestion - Structural doc improvements (only when necessary)
* 🤔 Thought/concern - Potential mismatch or ambiguous behavior requiring discussion
* 🚀 Positive feedback - Excellent documentation patterns worth highlighting
* ℹ️ Explanatory note - Context about schema behavior or provider conventions
* 📌 Future consideration - Larger scope items for follow-up
