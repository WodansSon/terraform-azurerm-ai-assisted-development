---
description: "Shared docs-review workflow used by the VS Code prompt and CLI docs-review agent."
---

# Shared Docs Review Workflow

This file defines the shared execution workflow for docs review.

Use it as the workflow layer for:

- `.github/prompts/code-review-docs.prompt.md`
- `plugins/terraform-azurerm-ai-toolkit/agents/review-docs.agent.md`

This file is not the normative rules contract.

- `.github/instructions/docs-compliance-contract.instructions.md` remains authoritative for docs rules, canonical precedence, and `DOCS-*` issue mapping.
- `.github/instructions/documentation-guidelines.instructions.md` remains authoritative for provider docs guidance.
- This file is authoritative for the docs-review execution guardrails, mandatory procedure, and output contract.

## Entry-Point Wrapper Responsibilities

The thin entrypoint that loads this workflow must supply:

- its own recursion-prevention file path
- the resolved target docs page path
- any surface-specific input mapping such as prompt active-file context or explicit `docs_path`

The shared workflow below assumes those entrypoint-specific details have already been established.

## Shared Execution Guardrails

### Audit-only mode

This workflow is audit-only. Do not modify files. Do not propose or apply patches unless the user explicitly asks for fixes.

### Minimal user input policy

Assume the user may invoke the workflow with minimal instructions (for example: `make it compliant` or `make it match HashiCorp standards`).

When this workflow is invoked, you must run the entire mandatory procedure below and you must not skip checks simply because the user did not explicitly mention them.

### Determinism policy

This workflow is used in a review→apply→re-review loop. To avoid run-to-run guessing:

- Do not present multiple fix options. Choose a single fix.
- Every Issue must have a concrete, deterministic fix.
- Do not output patch-ready replacement snippets in the review output; keep fixes concise and actionable.

No-snippets determinism guardrail:

- Not emitting snippets must not reduce correctness.
- Derive fixes internally from workspace evidence (`internal/**` then `vendor/**`) and include enough literal detail in each `Fix N` to apply deterministically.
- The text of `Fix N` is a user-facing instruction summary; do not treat it as the source of truth for the actual patch.
- Evidence sources must follow the contract evidence hierarchy:
  1. `internal/**` schema + provider implementation
  2. `vendor/**` SDK constants/models when referenced by validation logic
  3. existing in-repo docs/examples for tone/structure
  4. Azure docs (Microsoft Learn) for semantics only, as a last resort
- External/web sources must never be used to infer provider validation rules, required arguments, import ID shapes, or example values.
- External/web sources must never be used as templates for Terraform example configuration blocks.
- Azure docs may be used only for service semantics in prose/notes, as a last resort.
- Do not invent example resources or values based on typical configurations. If you cannot prove a configuration or value from workspace evidence, record an Observation and cite `DOCS-EVID-001`.

No repo-tool invocation:

- Do not suggest, attempt, or instruct running any repository tooling as part of this audit.
- This includes any docs schema validators, scaffolding tools, linters/formatters, or generator commands.
- All findings and fixes must be derived from static workspace evidence only (`website/docs/**`, `internal/**`, and `vendor/**` when referenced by validation logic).

No TODO lists / plans:

- Do not output TODO lists, task lists, plans, or checklists.
- Do not use checkbox syntax.
- Do not add extra sections like `Plan`, `Todo`, `Steps`, or `Checklist`.
- The only allowed output is the 9-heading review template defined in this workflow.

No preamble / no progress narration:

- Do not output any sentences before the 9-heading review.
- The first character of your normal output must be `#`.
- Do not output progress narration.
- If you cannot complete the audit, follow the exact hard-stop output rules below.

## Mandatory Procedure

### Optional: VS Code Todos progress

This workflow may use the VS Code Todos UI (via the `manage_todo_list` tool) to show progress.

Rules:

- If you create a Todo list, you must keep it updated as you progress.
- You must finish by marking all Todo items as `completed` before emitting the final 9-heading review output.
- Do not leave a Todo list with items stuck in `not-started` or `in-progress` at the end.

### 0) Load canonical standards

- If `contributing/topics/reference-documentation-standards.md` exists in the current workspace, read it and apply it.
- Read and apply `.github/instructions/documentation-guidelines.instructions.md`.
- Read and apply `.github/instructions/docs-compliance-contract.instructions.md` to EOF.
  - EOF marker verification is mandatory: the last non-empty line of the loaded contract must be `<!-- DOCS-CONTRACT-EOF -->`.
  - If you do not see that marker, treat the contract as not fully loaded and hard-stop.
  - If you cannot load the contract file to EOF, output exactly this one line and nothing else:
    - `Cannot run code-review-docs: docs compliance contract not fully loaded. Load .github/instructions/docs-compliance-contract.instructions.md to EOF and re-run this workflow.`

### 1) Identify the Terraform object from the docs path

- Resource docs: `website/docs/r/<name>.html.markdown` → `azurerm_<name>`
- Data source docs: `website/docs/d/<name>.html.markdown` → `azurerm_<name>`
- List-resource docs: `website/docs/list-resources/<name>.html.markdown` → `azurerm_<name>`
- Ephemeral-resource docs: `website/docs/ephemeral-resources/<name>.html.markdown` → `azurerm_<name>`
- Function docs: `website/docs/functions/<name>.html.markdown` → `<name>`

Also record the doc type from the path:

- `website/docs/r/**` => Resource
- `website/docs/d/**` => Data Source
- `website/docs/list-resources/**` => List Resource
- `website/docs/ephemeral-resources/**` => Ephemeral Resource
- `website/docs/functions/**` => Function

### 2) Locate the schema in `internal/**`

- Search under `internal/**` for the Terraform name.
- Open the relevant registration and implementation files until you find the Terraform schema definition.
- For list-resource docs, locate both the base resource implementation and the corresponding `*_resource_list.go` implementation.
- For ephemeral-resource docs, locate the corresponding `*_ephemeral.go` implementation and the service `registration.go` entry.
- For function docs, locate the corresponding implementation under `internal/provider/function/<name>.go` and its test file.
- Record the schema file path(s) used.

If you cannot find the schema, say so explicitly and continue with a docs-only standards review.

### 3) Extract schema facts and evidence

From the schema, extract:

- required arguments
- optional arguments
- computed attributes
- ForceNew fields
- constraints that affect docs

Additional evidence to extract:

- next-major deprecated fields
- cross-field constraints
- diff-time constraints
- implicit behavior constraints

Evidence requirements:

- Always cite `internal/**` file path + function/helper name for any diff-time or implicit behavior claim.
- Use `vendor/**` only as supporting evidence when validation logic references SDK constants or enums.
- If evidence cannot be proven, do not guess; record an Observation per `DOCS-EVID-001`.

### 4) Audit the documentation

Audit the target docs page against `.github/instructions/docs-compliance-contract.instructions.md`.

Full-coverage rule:

- Audit the entire page end-to-end.
- The user must not have to tell you which sections to check.
- Do not ask the user to scope the audit to specific sections.

Internal multi-pass audit:

- Structure pass: enforce `DOCS-FM-*` and `DOCS-STRUCT-*`.
- Arguments/Attributes pass: enforce `DOCS-ARG-*`, `DOCS-ATTR-*`, `DOCS-SHAPE-*`, `DOCS-NOTE-*`, and `DOCS-EX-*`.
- Import/Timeouts/Wording pass: enforce `DOCS-IMP-*`, `DOCS-TIMEOUT-*`, and `DOCS-WORD-*`.

Output rules:

- Issues must map to `DOCS-*` rule IDs and include schema or implementation evidence.
- `MINIMAL FIXES (PATCH-READY)` must contain concise `Fix N` steps only.
- In Observations, include a compact required-notes-coverage summary.

### 5) Produce the review output

- Keep every Issue grounded in exact `DOCS-*` rule IDs.
- Keep fixes deterministic and concise.
- Ask whether to apply a patch only when issues exist.

## Review Output Format

Output must be rendered Markdown.

- Do not wrap the review output in triple-backtick fences.
- Use the section headings exactly as written below.

1. `# 📋 **Code Review - Docs**: ${terraform_name}`
2. `## 📌 **COMPLIANCE RESULT**`
3. `## 🧾 **SCHEMA SNAPSHOT**`
4. `## 📊 **DOC STANDARDS CHECK**`
5. `## 🟢 **STRENGTHS**`
6. `## 🟡 **OBSERVATIONS**`
7. `## 🔴 **ISSUES** (only actual problems)`
8. `## 🛠️ **MINIMAL FIXES (PATCH-READY)**`
9. `## 🏆 **OVERALL ASSESSMENT**`

The structured review must be emitted exactly once.
If there are Issues, output exactly one final line `Do you want me to apply a patch?` after the OVERALL ASSESSMENT section and then stop.

<!-- REVIEW-DOCS-WORKFLOW-EOF -->
