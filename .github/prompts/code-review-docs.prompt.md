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

Exact failure output (mandatory):
- Output exactly this one line and nothing else:
  - `Cannot run code-review-docs: active file is not under `website/docs/**`. Open the target docs page and re-run this prompt.`

Audit the **currently-open** documentation page under `website/docs/**` for:
- AzureRM documentation standards, and
- parity with the Terraform schema under `internal/**`.

When reviewing documentation standards, treat the **canonical sources + precedence** as defined by:
- `.github/instructions/docs-compliance-contract.instructions.md` (see "Canonical sources of truth (precedence)")

Do not treat `.github/skills/docs-writer/SKILL.md` as a canonical rules source.

This audit is **optional** and **user-invoked** (no CI enforcement).

## Minimal user input policy
Assume the user may invoke this prompt with minimal instructions (for example: "make it compliant" / "make it match HashiCorp standards").

When this prompt is invoked, you must run the **entire** mandatory procedure below and you must not skip checks simply because the user did not explicitly mention them.

## Determinism policy (mandatory)
This prompt is used in a review→apply→re-review loop. To avoid run-to-run "guessing":

- Do not present multiple fix options (no "either A or B"). Choose a single fix.
- Every Issue must have a concrete, deterministic fix (no vague instruction).
- Do not output patch-ready replacement snippets in the review output; keep fixes concise and actionable.

No-snippets determinism guardrail (mandatory):
- Not emitting snippets must NOT reduce correctness.
- Derive fixes internally from workspace evidence (`internal/**` then `vendor/**`) and include enough literal detail in each `Fix N` to apply deterministically (exact argument names, exact ordering lists, exact enum values, and exact example `name` strings when constrained).
- The text of `Fix N` is a user-facing instruction summary; do not treat it as the source of truth for the actual patch.
- Evidence sources must follow the contract evidence hierarchy:
  1) `internal/**` schema + provider implementation
  2) `vendor/**` SDK constants/models when referenced by validation logic
  3) existing in-repo docs/examples for tone/structure
  4) Azure docs (Microsoft Learn) for semantics only, as a last resort
- External/web sources must NEVER be used to infer provider validation rules, required arguments, import ID shapes, or example values.
- External/web sources must NEVER be used as templates for Terraform example configuration blocks.
- Azure docs may be used only for service semantics in prose/notes, as a last resort.
- Do not invent example resources or values based on "typical" configurations. If you cannot prove a configuration/value from workspace evidence, record an Observation and cite `DOCS-EVID-001`.

No repo-tool invocation (mandatory):
- Do NOT suggest, attempt, or instruct running any repository tooling as part of this audit.
  - This includes (but is not limited to) any docs schema validators, scaffolding tools, linters/formatters, or generator commands (for example `go run ...`, `make docs`, `website-scaffold`, `documentfmt`, `document-lint`, or similar).
- All findings and fixes must be derived from static workspace evidence only (`website/docs/**`, `internal/**`, and `vendor/**` when referenced by validation logic).
- Prefer the smallest deterministic fix that removes the Issue and is consistent with the rules in this prompt and HashiCorp's documentation standards (for example `contributing/topics/reference-documentation-standards.md`).

No TODO lists / plans (mandatory; output determinism):
- Do not output TODO lists, task lists, plans, or checklists.
- Do not use checkbox syntax (e.g. `- [ ]` / `- [x]`).
- Do not add extra sections like "Plan", "Todo", "Steps", or "Checklist".
- The only allowed output is the 9-heading review template defined in this prompt.

If you cannot complete the audit (for example contract not loaded to EOF), follow the exact hard-stop output rules below.

## ⚡ Mandatory procedure

### Optional: VS Code Todos progress (must not regress)
This prompt may use the VS Code Todos UI (via the `manage_todo_list` tool) to show progress.

Rules (mandatory):
- If you create a Todo list, you MUST keep it updated as you progress.
- You MUST finish by marking all Todo items as `completed` before emitting the final 9-heading review output.
- Do NOT leave a Todo list with items stuck in `not-started` or `in-progress` at the end.
- If you are not going to update the Todo list, do not create it.

### 0) Load canonical standards

- If `contributing/topics/reference-documentation-standards.md` exists in the current workspace, read it and apply it.
- Read and apply `.github/instructions/documentation-guidelines.instructions.md`.
- Read and apply `.github/instructions/docs-compliance-contract.instructions.md` **to EOF** (entire file).
  - EOF marker verification (mandatory): the last non-empty line of the loaded contract MUST be `<!-- DOCS-CONTRACT-EOF -->`.
    - If you do not see that marker, treat the contract as not fully loaded and hard-stop.
  - Hard-stop: if you cannot load the contract file to EOF (for example due to partial context), do not proceed with the audit.
  - In that case, exact failure output (mandatory):
    - Output exactly this one line and nothing else:
      - `Cannot run code-review-docs: docs compliance contract not fully loaded. Load `.github/instructions/docs-compliance-contract.instructions.md` to EOF and re-run this prompt.`
  - Output rule (mandatory): do not narrate this step.
    - Do not say the contract is long.
    - Do not say you are continuing to read it.
    - Either complete the audit normally, or hard-stop with the exact failure text above.

### 1) Identify the Terraform object from the doc path
- Resource docs: `website/docs/r/<name>.html.markdown` → `azurerm_<name>`
- Data source docs: `website/docs/d/<name>.html.markdown` → `azurerm_<name>`
- List-resource docs: `website/docs/list-resources/<name>.html.markdown` → `azurerm_<name>`
- Ephemeral-resource docs: `website/docs/ephemeral-resources/<name>.html.markdown` → `azurerm_<name>`
- Function docs: `website/docs/functions/<name>.html.markdown` → `<name>`

Also record the **doc type** from the path:
- `website/docs/r/**` => **Resource** documentation rules
- `website/docs/d/**` => **Data Source** documentation rules
- `website/docs/list-resources/**` => **List Resource** documentation rules
- `website/docs/ephemeral-resources/**` => **Ephemeral Resource** documentation rules
- `website/docs/functions/**` => **Function** documentation rules

### 2) Locate the schema in `internal/**`
- Search under `internal/**` for the Terraform name (e.g. `azurerm_<name>`).
- Open the relevant registration/implementation files until you find the Terraform schema definition.
- For list-resource docs, locate both the base resource implementation and the corresponding `*_resource_list.go` implementation so you can verify the list query config schema and the list-resource-specific example behavior.
- For ephemeral-resource docs, locate the corresponding `*_ephemeral.go` implementation and the service `registration.go` entry so you can verify the ephemeral schema and the registration pattern.
- For function docs, locate the corresponding implementation under `internal/provider/function/<name>.go` and its test file under `internal/provider/function/`.
- Record the schema file path(s) used.

If you cannot find the schema, say so explicitly and continue with a docs-only standards review.

### 3) Extract schema facts (from the schema definition)
From the schema, extract:
- required arguments
- optional arguments
- computed attributes
- ForceNew fields (`ForceNew: true`)
- constraints that affect docs (e.g. `ConflictsWith`, `ExactlyOneOf`, `AtLeastOneOf`, validations), if clearly visible

List-resource specialization (mandatory):
- For list-resource docs, treat the list resource config schema as the authoritative source for `Argument Reference`.
- For list-resource docs, validate the `list "azurerm_<name>" ...` examples against the list resource config schema and any list-resource-specific behavior proven by the `*_resource_list.go` implementation.

Ephemeral-resource specialization (mandatory):
- For ephemeral-resource docs, treat the `*_ephemeral.go` schema as the authoritative source for `Argument Reference` and `Attributes Reference`.
- For ephemeral-resource docs, validate the `ephemeral "azurerm_<name>" ...` examples against the ephemeral resource schema and any implementation-backed behavior proven by `Open(...)`.

Function specialization (mandatory):
- For function docs, treat the implementation under `internal/provider/function/<name>.go` as the authoritative source for the function name, summary, signature, arguments, and return shape.
- For function docs, validate `provider::azurerm::<name>(...)` usage against the function `Definition(...)` and `Run(...)` implementations rather than ordinary resource schema rules.

**Mandatory: validate all example-used fields against schema evidence (not just `name`)**
- Enumerate every argument assignment used in any Terraform configuration block under headings starting with `Example` (for example: `name = ...`, `sku_name = ...`, `ttl = ...`, nested blocks, and meta-arguments like `depends_on`).
- Mandatory scope expansion (prevents skipped auxiliary blocks):
  - This validation applies to **every** Terraform `resource`, `data`, and `ephemeral` block that appears in any `Example*` section, not only the primary object being documented.
  - For each such block type (for example `azurerm_resource_group`, `azurerm_dns_zone`, or `azurerm_key_vault_secret` in an `ephemeral` block), you MUST locate its schema under `internal/**` and validate the example-used fields against that schema/implementation evidence.
  - For function docs, also validate every `provider::azurerm::<name>(...)` call in `Example*` sections against the implementation under `internal/provider/function/<name>.go`.
- For each referenced field, locate and record the relevant schema/implementation evidence that constrains it, including (when present):
  - `ValidateFunc` (regex/length/charset/enums)
  - `ConflictsWith`, `ExactlyOneOf`, `AtLeastOneOf`, `RequiredWith`
  - Diff-time / CustomizeDiff constraints and any helper validation functions
- Use that evidence to verify the example values are valid and pasteable.

Vendored constants allowance (mandatory):
- If the schema/validation logic references SDK constants/enums (e.g. cipher suite constants), use `vendor/**` as supporting evidence for the allowed values.

**Mandatory: deterministic example naming + ValidateFunc evidence (no invented names):**
- If you must introduce new Terraform blocks into a resource example to satisfy self-containedness (`DOCS-EX-003`), any name-like string values you add or rename MUST follow `DOCS-EX-015` (derive from the Terraform type suffix; do not make up values like `example-route`).
- If the value is constrained by `ValidateFunc`/validation logic, you MUST derive a compliant deterministic value from workspace evidence.
  - Primary: `internal/**` validation logic.
  - Supporting (when referenced): `vendor/**` SDK constants/enums.
  - Guardrail: if you cannot prove the allowed charset/length/enum from workspace evidence, do not guess a placeholder; record an Observation and cite `DOCS-EVID-001`.

**Mandatory: apply `DOCS-EX-015` only when a rename is required (contract-accurate):**
- `DOCS-EX-015` is a deterministic *derivation rule* for replacement values when you must propose/apply a rename.
- Do NOT treat `DOCS-EX-015` as a blanket requirement that every Example `name = "..."` literal must equal the type-derived value.
- When you do need to rename a name-like value (for example to satisfy `DOCS-EX-007`, or to replace an invalid value per `DOCS-EX-016`, or when adding/updating resource-example scaffolding blocks for self-containedness), derive the new value per `DOCS-EX-015` and ensure it is ValidateFunc-safe per `DOCS-EX-016`.

Generalized deterministic-name preference (nit-level; evidence-gated):
- For any Terraform `resource`/`data` block in `Example*` sections, when a `name = "..."` **string literal** is present:
  - If the value does not follow `DOCS-EX-007` (missing `example-`/`existing-` where feasible), record a 🔵 Low nit Issue and propose a deterministic rename per `DOCS-EX-015`.
  - If the value follows the prefix convention but does not match the `DOCS-EX-015` type-derived value, you MUST record a 🔵 Low nit Issue recommending renaming to the type-derived value **only when** schema/implementation evidence proves that the derived value is valid for that specific field (`DOCS-EX-016`).
    - If the field has domain/label-style constraints (for example DNS zone names, hostnames) and the type-derived value cannot be proven valid, do not suggest an exact-match rename; keep it as-is and, if needed, record an Observation per `DOCS-EVID-001`.

**Mandatory: evidence-gated renames (prevents invalid “fixes”):**
- You MUST NOT propose or apply a rename for any Example string literal (including `name` and other name-like fields) unless you can cite schema/implementation evidence for that specific field’s constraints (for example `ValidateFunc`, enum validation, length bounds, charset/regex).
- If you cannot prove the replacement value is valid for that field from `internal/**` (and `vendor/**` only when referenced by validation logic), do NOT guess a “better” example value; record an Observation and cite `DOCS-EVID-001`.
- This evidence gate applies even to nit-level example naming conventions (`DOCS-EX-007`) and deterministic derivation (`DOCS-EX-015`).

**Mandatory: internal example validation (no silent skip; compact output):**
- Perform the full validation described above, but do not print a full per-field matrix.
- Output rule (default/compact):
  - Only surface validation failures as **Issues** (with schema/implementation evidence + a concrete fix step).
  - In `## 🟡 **OBSERVATIONS**`, include at most one short line summarizing example validation status, for example: `Example validation: 0 failures` or `Example validation: 3 failures (see Issues)`.

### 3.5) Extract additional evidence (compact; contract-driven)
In addition to the schema snapshot above, extract and report (or state `none` for each):
- **Next-major deprecated fields**: detect next-major deprecations from `internal/**` (feature flag blocks / `Deprecated:` / typed model tags).
- **Cross-field constraints**: from schema (`ConflictsWith`, `ExactlyOneOf`, `AtLeastOneOf`, `RequiredWith*`, etc.).
- **Diff-time constraints**: follow the `CustomizeDiff` call chain to the actual condition logic.
- **Implicit behavior constraints**: expand/flatten behavior that changes semantics based on block presence/shape.

Evidence requirements:
- Always cite `internal/**` file path + function/helper name for any diff-time/implicit behavior claim.
- Use `vendor/**` only as supporting evidence when validation logic references SDK constants/enums.

Doc requirements (contract-driven):
- In resource docs, any constraint that affects valid config must be documented as notes per `DOCS-NOTE-*`.
- In data source docs, enforce the contract rule that field documentation stays concise and limited to explaining what the field is, with no field-level note blocks.
- In list-resource docs, enforce the contract rule that query-argument documentation stays concise and limited to explaining what the field is, with no field-level note blocks.
- In ephemeral-resource docs, enforce the contract rule that query arguments and exported attributes stay concise and limited to what the field is, with only the top-level runtime-support note.
- In function docs, enforce the contract rule that the `Arguments` section stays concise and parameter-focused, with only the top-level runtime-support note.
- If evidence cannot be proven, do not guess; record an Observation per `DOCS-EVID-001`.

### 4) Audit the documentation (contract-driven)
Audit the active docs page against `.github/instructions/docs-compliance-contract.instructions.md`.

Full-coverage rule (mandatory; handles large docs without user guidance):
- You MUST audit the entire page end-to-end.
- The user MUST NOT have to tell you which sections to check.
- Do not ask the user to "scope" the audit to specific sections as a workaround for page length.
- If the page is large, you MUST still cover all required sections by doing internal passes (below) rather than skipping content.
- Output rule: do not mention page length or reading progress.

Internal multi-pass audit (mandatory):
- **Index pass (internal only)**: build a mental index of major headings and block subsections.
- **Structure pass**: enforce `DOCS-FM-*` and `DOCS-STRUCT-*` (frontmatter, required sections, section order).
    - Mandatory exact-intro checks (contract-driven; prevents tiny drift):
    - Under `## Attributes Reference` for resource and data source docs, the intro line MUST be exactly: `In addition to the Arguments listed above - the following Attributes are exported:` (hyphen form, not a comma).
      - Under `## Argument Reference` for list-resource docs, the intro line MUST be exactly: `This list resource supports the following arguments:`.
    - Under `## Attributes Reference` for ephemeral-resource docs, the intro line MUST be exactly: `The following attributes are exported:`.
- **Arguments/Attributes pass**:
    - Top-level ordering and coverage (`DOCS-ARG-*`, `DOCS-ATTR-*`)
    - Block shape + subsection placement/order (`DOCS-SHAPE-001/002/003/004/005`)
    - Nested field ordering inside each block subsection (`DOCS-SHAPE-006`, `DOCS-ATTR-005`)
    - Bullet conciseness + note splitting (`DOCS-ARG-011`, `DOCS-NOTE-*`)
    - Trigger (mandatory; prevents misses): in resource docs, if any argument bullet contains more than 2 sentences OR mixes definition text with validation-style constraints (length/charset/regex/start/end rules) OR contains both a long constraints clause and the ForceNew sentence, you MUST treat it as a `DOCS-ARG-011` failure and split the constraints into an inline note under the bullet.
    - Data source rule (mandatory): in data source docs, if a field bullet contains extended caveats or a field-level note block, you MUST treat it as a contract failure and require the text to be reduced to a short explanation of what the field is.
    - List-resource rule (mandatory): in list-resource docs, if a query-argument bullet contains extended caveats or a field-level note block, you MUST treat it as a contract failure and require the text to be reduced to a short explanation of what the field is.
    - Ephemeral-resource rule (mandatory): in ephemeral-resource docs, if an argument or attribute bullet contains extended caveats or a field-level note block, you MUST treat it as a contract failure and require the text to be reduced to a short explanation of what the field is.
    - Function rule (mandatory): in function docs, if an argument item contains extended caveats or a field-level note block, you MUST treat it as a contract failure and require the text to be reduced to a short explanation of what the parameter is.
    - Note format (mandatory): when a resource field note is required, the inline note MUST use `(->|~>|!>) **Note:**` per `DOCS-NOTE-003`.
    - **Examples pass**: enforce `DOCS-EX-*` (fences, resource self-containedness, data source lookup behavior, list-resource query examples, ephemeral-resource examples, function call examples, required `depends_on` preservation, ValidateFunc-safe values, no secrets).
- **Import/Timeouts/Wording pass**: enforce `DOCS-IMP-*` (resources), `DOCS-TIMEOUT-*` (if present), and `DOCS-WORD-*`.

If you cannot confidently verify a section due to missing workspace evidence, do not guess; record an Observation and cite `DOCS-EVID-001`.

Output rules (keep compact; no snippets):
- **Issues**: must map to `DOCS-*` rule IDs and include schema/implementation evidence.
- **Minimal fixes**: `Fix N` steps only (no fenced/indented blocks); include exact ordering lists and exact constrained literal values when needed.
- **Notes coverage**: in Observations, include a compact "required notes coverage" summary (constraints extracted vs documented notes).

No TODO/tasklist rule (mandatory; avoids confusing stale checklists):
- Do NOT output Markdown task lists anywhere (no `- [ ]` / `- [x]`).
- Do NOT output a separate "TODO" section or checklist.
- The actionable task list for end users is `## 🛠️ **MINIMAL FIXES (PATCH-READY)**`.
- The status checklist is `## 📊 **DOC STANDARDS CHECK**` (Pass/Fail rows).

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
- Do not output `## 🏆 **OVERALL ASSESSMENT**` until after you have completed `## 🛠️ **MINIMAL FIXES (PATCH-READY)**` (all fix steps included).

Heading emission guardrail (mandatory; prevents accidental duplicate headings):
- You MUST NOT output any of the 9 required heading lines anywhere except as the actual section headings.
- Do NOT start any non-heading line with `#` or `##`.
- If you need to refer to a required section in prose (for example in an Issue `Location`), write it as plain text like `OVERALL ASSESSMENT section` (no leading `#`).

Two-phase generation rule (mandatory; enables validation without duplication):
- You MUST perform two internal passes:
  1) Draft pass (internal only): gather evidence and draft the review structure.
  2) Validation pass (internal only): re-check the draft for correctness, missing evidence, and contract mapping; then trim any duplicate text.
- Output rule: emit the structured review **exactly once** (a single 9-heading review) after the validation pass.
- Do not restart the template, do not repeat any headings, and do not re-emit `## 🏆 **OVERALL ASSESSMENT**`.
- If you realize you forgot content during drafting, fix it internally before you emit output (do not append a second mini-review).

Atomic output buffering rule (mandatory; prevents multi-pass leakage):
- Treat both passes as strictly internal. Do NOT emit any portion of the 9-heading review during Draft pass or mid-Validation pass.
- Before emitting any user-visible text, assemble the entire 9-heading review in an internal buffer (all sections, including `## 🏆 **OVERALL ASSESSMENT**` and, when applicable, the final `Do you want me to apply a patch?` line).
- Emit the buffer exactly once as the final output. Do not "stream" partial sections, then revise by reprinting headings.
- If you detect any duplicate headings while assembling the buffer, delete the duplicates before emitting (keep only the first complete 9-heading review).

Post-review patch question rule (mandatory; prevents restarts but keeps the handoff):
- You MUST include exactly one patch handoff question when there is at least one Issue:
  - `Do you want me to apply a patch?`
- Place it immediately after the OVERALL ASSESSMENT section.
- It must appear at most once, must not be a heading, and must be the last non-footer line you generate.
  - Absolute terminator: after outputting `Do you want me to apply a patch?`, stop generating prompt output immediately (the docs-writer skill may append its verification footer externally).
  - Formatting guardrail: the patch question MUST be on its own line and MUST end with a newline so it cannot concatenate with any following content.

Docs-writer footer interaction rule (mandatory; prevents duplicated assessments):
- The docs-writer skill may append a verification footer after your output:
  - `Preflight complete: ...`
  - `Skill used: docs-writer`
- You MUST NOT output these lines yourself.
- Treat those lines as an external trailer. Your job is to end cleanly before them.
- If you ever see a line starting with `Preflight complete:` or `Skill used:` in the output (even if appended externally), stop generating immediately and do not emit any further headings or content.

Skill footer rule (mandatory; prevents duplicate sections):
- Do not output `Preflight complete:` or `Skill used:` lines anywhere in the structured review.
- The docs-writer skill appends its verification footer after the review output; emitting these lines inside the review causes template restarts and duplicated sections.


# 📋 **Code Review - Docs**: ${terraform_name}

## 📌 **COMPLIANCE RESULT**
- **Status**: Valid / Invalid
- **Doc File**: ${docs_file_path}
- **Doc Type**: Resource / Data Source / List Resource / Ephemeral Resource / Function

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
- **Frontmatter**: Pass/Fail + missing keys (if any)
- **Section Order**: Pass/Fail + missing sections (if any)
- **Argument Ordering**: Pass/Fail (resource/data source/ephemeral docs: ID segments first per contract ordering, `location` next when present, remaining required alphabetical, then optional alphabetical, `tags` last; list-resource docs: query arguments alphabetical; function docs: arguments follow signature order)
- **Argument Bullet Conciseness**: Pass/Fail (resource docs: long bullets split into inline notes per `DOCS-ARG-011`; data source, list-resource, ephemeral-resource, and function docs: entries stay short and field-definitional)
- **Nested Block Field Ordering**: Pass/Fail (nested args: required alpha then optional alpha, `tags` last via `DOCS-SHAPE-006`; nested attrs: `id` first then alpha via `DOCS-ATTR-005`)
- **Schema Shape**: Pass/Fail (docs describe blocks vs inline fields consistently with schema)
- **Attributes Coverage**: Pass/Fail (`id` first, computed attrs present, remaining alphabetical; no other exceptions)
- **ForceNew Wording**: Pass/Fail (resources only, missing “Changing this forces…” sentence)
- **Conditional Notes**: Pass/Fail (resource docs: cross-field/conditional requirements from schema constraints and `CustomizeDiff` are documented using `~> **Note:**`; data source, list-resource, ephemeral-resource, and function docs: field-level note blocks are absent and field text stays concise)
- **Note Notation**: Pass/Fail (->/~>/!> exact format + marker meaning matches note content)
- **Note Accuracy**: Pass/Fail (note content matches schema/diff-time/implicit behavior; no contradictory or incomplete constraints)
- **Timeouts Readability**: Pass/Fail (convert defaults >60 minutes to hours)
- **Import Text**: Pass/Fail (resources only, resource-specific sentence per `DOCS-IMP-002`; list-resource, ephemeral-resource, and function docs should omit a top-level Import section)
- **Import Example**: Pass/Fail (resources only, ID shape matches importer/parser)
- **Link Locales**: Pass/Fail (no locale segments like `/en-us/` in URLs)
- **Examples**: Pass/Fail (resource docs: examples are functional and self-contained; data source docs: examples demonstrate existing-object lookup behavior without unnecessary backing-resource scaffolding; list-resource docs: examples demonstrate Terraform `list` query usage; ephemeral-resource docs: examples demonstrate Terraform `ephemeral` usage; function docs: examples demonstrate `provider::azurerm::<name>(...)` usage; no hard-coded secrets)
- **Example Invariants**: Pass/Fail (resource docs: preserve example-adjacent notes per `DOCS-EX-018`, preserve existing `depends_on` per `DOCS-EX-004`, do not replace references with invented literals per `DOCS-EX-019`, ensure transitive self-containedness per `DOCS-EX-020`, preserve reference semantics per `DOCS-EX-021`; data source docs: follow `DOCS-EX-022` lookup-example rules; list-resource docs: follow `DOCS-EX-023` list-query rules; ephemeral-resource docs: follow `DOCS-EX-024`; function docs: follow `DOCS-EX-025`)
- **Example `name` Values**: Pass/Fail (nit-level; Example `name` values follow `DOCS-EX-007` where feasible and satisfy `DOCS-EX-016` constraints; when a rename is required, the replacement value is derived deterministically per `DOCS-EX-015`)

## 🟢 **STRENGTHS**
- ...

## 🟡 **OBSERVATIONS**
- ...
- Notes: ...
- Required notes coverage: ...

## 🔴 **ISSUES** (only actual problems)

Rule tagging (mandatory; prevents drift):
- Every Issue MUST include one or more `DOCS-...` rule IDs from `.github/instructions/docs-compliance-contract.instructions.md`.
- If you cannot map a finding to a contract rule, do not report it as an Issue. Instead, treat it as a suggested improvement or update the contract (out of band).

### ${🔧/⛏️/❓} ${summary}
* **Priority**: 🔥 Critical / 🔴 High / 🟡 Medium / 🔵 Low / ✅ Good
* **Location**: ${doc_section_or_argument_name}
* **Rule ID(s)**: ${DOCS-...}
* **Schema Evidence**: ${what_in_schema_proves_this}
* **Problem**: clear description
* **Suggested Fix**: one sentence only (single line), referencing the relevant `Fix N` in `## 🛠️ **MINIMAL FIXES (PATCH-READY)**`.
  - Do not include any replacement text, any bullet lists, or any multi-step "from/to" descriptions here.

Hard guardrail (mandatory):
- Do not include any multi-line snippets anywhere in `## 🔴 **ISSUES**` (no fenced code blocks, no indented code blocks, no "from/to" blocks, no embedded replacement paragraphs).
- If you accidentally drafted multi-line snippet content inside Issues, delete it and move the detailed fix steps into `## 🛠️ **MINIMAL FIXES (PATCH-READY)**` before emitting output.

## 🛠️ **MINIMAL FIXES (PATCH-READY)**
This section is **mandatory** and must contain concise, deterministic fix steps for every Issue.

Determinism rules (mandatory):
- Do not include code blocks or patch snippets.
- Provide exactly one fix path per Issue (no A/B options).
- Use `### Fix N: <short summary>` headings.
- Each fix must be implementable without guessing (name exact section/argument/block and what to add/change/remove).

If there are **no Issues**, write exactly one bullet:
- `No changes required.`

## 🏆 **OVERALL ASSESSMENT**

Content rules (user-facing only; do not include internal process notes here):
- Start with a single-line verdict: `**Result:** Pass` or `**Result:** Needs Changes`
- Insert exactly one blank line after the verdict line.
- Then output a patch plan summary that describes what the proposed patch would change (future/conditional tense).
  - Do NOT write this in a way that implies the doc is already fixed.
  - This summary must align with the Issues and `Fix N` steps (no new work items).
- Then add one short paragraph summarizing what must change to become compliant.

Hard stop rule (mandatory; prevents duplicate sections):
- After the final sentence of this section:
  - If there are Issues: output exactly one final line `Do you want me to apply a patch?` and then stop.
  - If there are no Issues: stop generating immediately.
  - Do not emit anything after that (no footers, no extra headings, no second assessment).

Post-pass trimming rule (mandatory):
- Before finalizing the response, scan your draft output and ensure:
  - `## 🏆 **OVERALL ASSESSMENT**` appears exactly once
  - nothing appears after the end of `## 🏆 **OVERALL ASSESSMENT**` except (when Issues exist) a single final line: `Do you want me to apply a patch?`
  - when Issues exist: `Do you want me to apply a patch?` appears exactly once
  - when Issues exist: no headings (`#` or `##`) appear after the patch question line
  - if any duplicate content exists (fix steps, headings, repeated assessment), delete the duplicates and keep only the first complete 9-heading review.

Patch plan summary (mandatory when Issues exist; output after the verdict):
- Output this exact line:
  - `**Fix coverage:** All reported 🔴 Issues have concrete fix steps in MINIMAL FIXES.`
- Then output 3–6 bullets describing what the patch would change, using future/conditional tense (e.g. "will", "would").
  - These bullets must be specific (name the section/argument/block) and must not include code.
  - The bullets must not claim execution (avoid "fixed", "updated", "corrected" without qualifiers).
  - Allowed phrasing examples: "Will update …", "Would make …", "Will document …", "Would normalize …".
  - If there are more than 6 Issues/Fix steps:
    - Group related fixes into themes so you can stay within 3–6 bullets.
    - Include one final catch-all bullet that references the remaining items, for example:
      - ``And would apply the remaining fixes listed in `MINIMAL FIXES` above.``
      - (Optional when helpful) You may include a Fix range, but prefer plain language.
    - Do not omit major themes (schema parity, examples, ordering/notes/import/timeouts).

Spacing rule (mandatory; output formatting):
- When Issues exist and you output `Do you want me to apply a patch?`, insert exactly one blank line immediately before that question.

Formatting rules:
- If there are Issues, the last non-footer line you generate must be exactly: `Do you want me to apply a patch?`
- If there are no Issues, the last non-footer line you generate must be the last line of `## 🏆 **OVERALL ASSESSMENT**`.
