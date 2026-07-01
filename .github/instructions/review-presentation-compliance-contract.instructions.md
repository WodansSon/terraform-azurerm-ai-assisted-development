---
description: "Presentation-pass compliance contract (single source of truth) used by the review-presentation skill as the render-only final presentation layer for generic code review output."
---

# Review Presentation Compliance Contract

This file is the single source of truth for the final review-presentation technique in this repository.

## Consumers

Three workflow surfaces MUST follow this contract:

- Consumer: `.github/skills/review-presentation/SKILL.md`
  - Role: Renderer
  - Command: `review-presentation` skill, invoked as the governed final presentation pass after findings are frozen
  - Requires EOF Load: yes
  - Goal: render frozen review data into the standard final review body without changing findings, severity, or classification.
- Consumer: `.github/prompts/code-review-local-changes.prompt.md`
  - Role: Orchestrator
  - Requires EOF Load: yes
  - Goal: build the local-review presentation payload and hand it to the renderer.
- Consumer: `.github/prompts/code-review-committed-changes.prompt.md`
  - Role: Orchestrator
  - Requires EOF Load: yes
  - Goal: build the committed-review presentation payload and hand it to the renderer.

The review prompts orchestrate when presentation runs.
The review-presentation skill encapsulates the reusable rendering method.
This contract defines the presentation-specific deterministic rules.
The presentation payload schema lives at `.github/instructions/review-presentation-input.schema.json`.

## Canonical sources of truth (precedence)

Use these sources with the following roles:

- The shared code review contract: `.github/instructions/code-review-compliance-contract.instructions.md`
  - Authoritative for overall review flow, evidence handling, finding classification, hard-stop ownership, and the frozen review state that presentation must not change.
  - This presentation contract refines only how frozen review data is rendered in the successful-output path.
- The moderator contract: `.github/instructions/review-moderator-compliance-contract.instructions.md`
  - Authoritative for the final moderated findings set that presentation renders.
- The presentation payload schema: `.github/instructions/review-presentation-input.schema.json`
  - Authoritative for the concrete runtime payload shape consumed by the renderer.
- This contract: `.github/instructions/review-presentation-compliance-contract.instructions.md`
  - Authoritative for output-template structure, section rendering, and footer rendering rules in this repository.
- The presentation skill: `.github/skills/review-presentation/SKILL.md`
  - Reusable rendering method: how to turn the frozen payload into the final review body without changing its meaning.

Conflict resolution:

- This contract is authoritative for the final successful review template, section order, footer rendering, and empty-state rendering in the routed presentation workflow.
- The shared code review contract remains authoritative for scope resolution, evidence handling, classification semantics, hard-stop behavior, and frozen-findings requirements.
- The moderator contract remains authoritative for what the final moderated findings set contains before presentation.
- The presentation payload schema remains authoritative for the payload field set and field meanings the renderer consumes.
- If this contract would contradict the frozen findings state established by the shared code review contract, the shared code review contract wins and the renderer must preserve the frozen findings state exactly.

## Rule IDs

Rules are identified by stable IDs so the presentation skill and the review prompts reference the same requirement set without drifting.

ID format:
- REVIEW-PRESENT-<NNN>

Area:
- PRESENT = final review presentation rendering

## Evidence hierarchy

When the renderer decides how to present a review, weigh authority in this order:

1. The presentation payload supplied by the routed prompt
2. The presentation payload schema
3. This contract
4. The shared code review contract for frozen-findings and footer semantics

If a rendering decision cannot be backed by this authority chain, prefer the narrower mechanical rendering choice rather than inventing new prose.

# Contract Rules

## Final review presentation rendering

### REVIEW-PRESENT-001: Presentation is render-only
- Rule: The renderer must not add, remove, merge, split, downgrade, upgrade, dismiss, or reinterpret findings.
- Rule: The renderer must not change severity, classification, evidence, or verdict semantics.
- Rule: The renderer may only organize the supplied frozen review data into the standard output template.

### REVIEW-PRESENT-002: Presentation consumes the schema payload exactly
- Rule: The renderer must consume a payload that conforms to `.github/instructions/review-presentation-input.schema.json`.
- Rule: The renderer must not invent missing required fields.
- Rule: If the required schema, contract, or skill cannot be loaded to EOF, the prompt must hard-stop instead of emitting a partial review body.

### REVIEW-PRESENT-003: Section order and headings are fixed
- Rule: The normal successful review body must render these headings exactly once and in this order:
  - `# 📋 **Code Review**: ${changeDescription}`
  - local mode: `## 🔄 **CHANGE SUMMARY**`
  - committed mode: `## 📊 **CHANGE SUMMARY**`
  - `## 📁 **FILES CHANGED**`
  - `## 🎯 **PRIMARY CHANGES ANALYSIS**`
  - `## 📋 **DETAILED TECHNICAL REVIEW**`
  - `## ✅ **RECOMMENDATIONS**`
  - `## 🏆 **OVERALL ASSESSMENT**`
- Rule: The renderer must not add a new reader-visible section outside this template.
- Rule: The renderer must not output any text before the review headings.
- Rule: The renderer must not wrap the review body in triple-backtick fences.

### REVIEW-PRESENT-003A: Canonical sample output block is the visual audit reference
- Rule: This sample block is the canonical visual reference for the final rendered review body.
- Rule: The sample is illustrative, not a second normative rule source.
- Rule: The sample exists to show the default rendered hierarchy: section order, bullet-first section content, empty-state handling, and footer placement.
- Rule: Placeholder tokens such as `${changeDescription}` are schematic placeholders only. The renderer must substitute payload values and must not emit those placeholder tokens literally.
- Rule: The sample intentionally shows the normal plain-bullet issue shape. The optional richer finding-card shape with code snippets is specified by the explicit rules below.
- Rule: If the sample block and the explicit `REVIEW-PRESENT-*` rules would ever appear to disagree, the explicit rule text and the presentation input schema win.
- Rule: For a concrete maintainer-only rendered example, use the adjudicated review outputs under `tools/regression/examples/`; those repo-only examples are not runtime contract authority.
- Rule: Local review uses the same overall shape, but replaces `## 📊 **CHANGE SUMMARY**` with `## 🔄 **CHANGE SUMMARY**`.

````markdown
# 📋 **Code Review**: ${changeDescription}

## 📊 **CHANGE SUMMARY**
- ${changeSummaryLine1}

## 📁 **FILES CHANGED**

**Modified Files:**
- ${modifiedFile1}

**Added Files:**
- ${addedFile1}

**Deleted Files:**
- None

**Skipped Vendored Files:** ${skippedVendoredFiles}

## 🎯 **PRIMARY CHANGES ANALYSIS**
${primaryChangesAnalysis}

## 📋 **DETAILED TECHNICAL REVIEW**

### 🔄 **RECURSION PREVENTION**
- ${recursionPreventionLine}

### 🔍 **STANDARDS CHECK**
- ${standardsCheckLine1}

### 🧰 **AZURERM LINTER**
- **Version**: ${linterVersion}
- **Status**: ${linterStatus}
- **Run Scope**: ${linterRunScope}
- **Issue Count**: ${linterIssueCount}
- **Summary**: ${linterSummary}

### 🎯 **MUST FIX**
- None
<!-- or one normalized linter bullet per line when findings exist -->
<!-- CHECKID [file:line](path#Lline): message -->

### 🟢 **STRENGTHS**
- ${strengthBullet}

### 🟡 **OBSERVATIONS**
- ${observationBullet}

### 🔴 **ISSUES**
- ${issueBulletOrNone}

## ✅ **RECOMMENDATIONS**

### 🎯 **IMMEDIATE**
- ${immediateRecommendation}

### 🔄 **FUTURE CONSIDERATIONS**
- ${futureConsideration}

## 🏆 **OVERALL ASSESSMENT**
${overallAssessment}

Preflight complete: yes
Skill used: ${skillName1}
````

### REVIEW-PRESENT-004: Section bodies render from payload data only
- Rule: `CHANGE SUMMARY` renders the supplied `changeSummaryLines` in payload order.
- Rule: `FILES CHANGED` renders only the file groups relevant to the review mode, using the payload arrays and `skippedVendoredFiles` count.
- Rule: `DETAILED TECHNICAL REVIEW` renders the supplied recursion-prevention, standards-check, linter, must-fix, strengths, observations, and issues data without reclassification.
- Rule: `RECOMMENDATIONS` renders the supplied immediate and future-consideration items without inventing new follow-up work.
- Rule: When a list-backed section is empty, the renderer should emit exactly one bullet: `- None`.

### REVIEW-PRESENT-004A: `MUST FIX` is the linter-action section
- Rule: `### 🎯 **MUST FIX**` renders the supplied `mustFix` entries as plain bullet lines in payload order.
- Rule: `mustFix` is reserved for normalized actionable linter lines or the explicit empty-state bullet `- None`.
- Rule: The renderer must not render structured finding cards inside `### 🎯 **MUST FIX**`.

Example:

```markdown
### 🎯 **MUST FIX**
- AZBP123 [resource.go:88](internal/services/example/resource.go#L88): add a nil guard before dereferencing the optional identity block
```

### REVIEW-PRESENT-004B: Structured findings preserve the legacy expanded card format
- Rule: When a finding item in `strengths`, `observations`, `issues`, `immediateRecommendations`, or `futureConsiderations` is a structured finding object from `.github/instructions/review-presentation-input.schema.json`, render it in this exact shape instead of the normal plain-bullet form:

```markdown
#### ${reviewTypeEmoji} ${reviewTypeLabel}: ${summary}
* **Priority**: ${priorityEmoji}
* **File**: ${file}
* **Evidence**: ${evidence}
* **Impact**: ${impact}
* **Suggested Change**: ${suggestedChange}
```

- Rule: If `suggestedChange` is absent, omit the `Suggested Change` line.
- Rule: If `currentCode` is present, render a `**Current Code:**` label followed by a fenced code block using `codeLanguage` when supplied.
- Rule: If `currentCode` and `correctedCode` are both present, render a `**Suggested Code:**` label followed by a fenced code block containing only the replacement snippet, using `codeLanguage` when supplied.
- Rule: If `correctedCode` is present without `currentCode`, render a fenced code block immediately after the `Suggested Change` line, using `codeLanguage` when supplied.
- Rule: Plain string items remain plain bullets in input order and are the default shape when no structured finding object is supplied.

Example:

````markdown
### 🔴 **ISSUES**
#### 🔧 Change request: ${summary}
* **Priority**: ${priorityEmoji}
* **File**: ${file}
* **Evidence**: ${evidence}
* **Impact**: ${impact}
* **Suggested Change**: ${suggestedChange}

**Current Code:**

```text
${currentCode}
```

**Suggested Code:**

```text
${correctedCode}
```
````

### REVIEW-PRESENT-004C: Presentation priority and review-type mappings remain active
- Rule: Structured finding `priority` is a presentation-layer display value. It should stay aligned with workflow severity language when the finding came from routed review roles.
- Rule: For structured findings rendered in `ISSUES` and `IMMEDIATE`, `priority` should be one of `critical`, `high`, `medium`, or `low`.
- Rule: For structured findings rendered in `OBSERVATIONS` or `FUTURE CONSIDERATIONS`, the aligned workflow-derived value is `observation`.
- Rule: `notable` is reserved for stronger positive-feedback rendering, for example when a developer made a non-obvious but correct design or implementation choice that aligns with contributor guidance, provider patterns, or service constraints.
- Rule: `good` is reserved for ordinary positive-feedback rendering in `STRENGTHS`, for example when a developer followed contributor guidance or provider patterns correctly and delivered the expected baseline implementation without any unusual workaround or extra validation machinery.
- Rule: `notable` and `good` must not be used for `ISSUES`.
- Rule: Structured finding `priority` values map as follows:
  - `critical` -> `🔥 Critical`
  - `high` -> `🔴 High`
  - `medium` -> `🟡 Medium`
  - `low` -> `🔵 Low`
  - `observation` -> `ℹ️ Observation`
  - `notable` -> `⭐ Notable`
  - `good` -> `✅ Good`
- Rule: Structured finding `reviewType` values map as follows:
  - `change-request` -> `🔧 Change request`
  - `nitpick` -> `⛏️ Nitpick`
  - `refactor-suggestion` -> `♻️ Refactor suggestion`
  - `thought-or-concern` -> `🤔 Thought or concern`
  - `positive-feedback` -> `🚀 Positive feedback`
  - `future-consideration` -> `📌 Future consideration`
- Rule: Review-type intent remains stable even in the multi-skill workflow:
  - `change-request`: a concrete problem or required correction.
  - `nitpick`: the code is acceptable and not expected to break behavior, but there is a small better way to express it.
  - `refactor-suggestion`: the behavior is acceptable, but the code could be made cleaner, smaller, or easier to understand through a more substantial simplification than a nitpick.
  - `thought-or-concern`: the code appears to follow the documented rules, but there is still a reviewer concern that may warrant closer inspection by the developer.
  - `positive-feedback`: an explicit positive callout. Pair with `good` for baseline standards-compliant work and `notable` for above-and-beyond or non-obvious correct implementation work.
  - `future-consideration`: non-blocking follow-up work or a worthwhile future improvement that should not be treated as a present defect.

### REVIEW-PRESENT-004D: Shared output keeps the legacy explanatory sections
- Rule: The final rendered review body continues to support both plain bullet findings and expanded finding cards in the same section when the payload supplies them.
- Rule: The renderer must not collapse an expanded finding card into a plain bullet merely because a section also contains plain bullet items.

### REVIEW-PRESENT-004E: File references must stay stable and non-local
- Rule: File references rendered in the final review body must use stable repo-scoped references supplied by the payload; they must not be rewritten into editor-local placeholder URIs or absolute on-disk paths.
- Rule: The renderer must not emit editor-local, spill-path, or absolute-disk references such as `vscode-file://`, `vscode://`, `file://`, `workbench.html`, `AppData`, `workspaceStorage`, `C:\`, `/Users/`, or other machine-local path prefixes anywhere in the review body.
- Rule: For committed reviews with authoritative PR scope, file references should remain PR-scoped or repo-scoped references derived from that authoritative scope rather than local editor-session links.
- Rule: For local reviews, file references should remain workspace-repo-relative paths or workspace-repo-relative path plus line references, not PR links, editor-session links, or absolute disk paths.
- Rule: If the payload supplies plain repo-relative paths, preserve them as such instead of inventing richer editor-local or absolute-disk links.

### REVIEW-PRESENT-005: Footer rendering is deterministic
- Rule: The verification footer is rendered only when the optional `verificationFooter` object is present.
- Rule: When the footer is present, render `Preflight complete: yes` exactly once before the `Skill used:` lines.
- Rule: Render one `Skill used:` line per `verificationFooter.skillsUsed` entry, in the supplied order.
- Rule: The renderer must not add `review-presentation` to the footer.
- Rule: The renderer must not emit any text after the footer.

### REVIEW-PRESENT-006: Prompt and renderer authority stay separated
- Rule: Prompts own hard-stop messages, workflow routing, and whether the successful-output path is reached.
- Rule: The renderer owns only the normal successful review body after the findings set is frozen.
- Rule: Prompts may transport moderated findings into the presentation payload, but they must not invent missing rich-display semantics such as `reviewType`, `suggestedChange`, `currentCode`, `correctedCode`, or `codeLanguage`.
- Rule: The renderer must not introduce new workflow logic, scope decisions, or post-freeze verification steps.

### REVIEW-PRESENT-007: Overall assessment must preserve frozen verdict semantics
- Rule: The renderer must render the supplied `overallAssessment` as-is except for normal heading placement.
- Rule: The renderer must not rewrite the verdict to contradict the frozen `ISSUES` state.

<!-- REVIEW-PRESENT-CONTRACT-EOF -->
