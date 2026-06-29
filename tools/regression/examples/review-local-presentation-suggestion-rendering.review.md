# 📋 **Code Review**: local review preserves moderator-owned suggestion rendering and positive-feedback semantics through the presentation layer

## 🔄 **CHANGE SUMMARY**
- **Files Changed**: 4 files (0 tracked new, 0 untracked, 4 modified, 0 deleted)
- **Line Changes**: 36 insertions, 9 deletions (tracked files only)
- **Branch**: fixture/local-review-presentation-suggestion
- **Type**: unstaged local changes
- **Scope**: exercises the new moderator-owned presentation hints and render-only suggestion-style output path

## 📁 **FILES CHANGED**

**Modified Files:**
- `.github/instructions/review-workflow-handoff.schema.json`
- `.github/instructions/review-moderator-compliance-contract.instructions.md`
- `.github/instructions/review-presentation-compliance-contract.instructions.md`
- `.github/prompts/code-review-local-changes.prompt.md`

## 🎯 **PRIMARY CHANGES ANALYSIS**
The workflow now expects moderator to attach deterministic presentation hints for surviving findings and the presentation layer to render those hints as structured finding cards, including GitHub-style suggestion blocks and differentiated positive-feedback strengths, without prompt-side derivation.

## 📋 **DETAILED TECHNICAL REVIEW**

### 🔄 **RECURSION PREVENTION**
- **File Skipped**: none

### 🔍 **STANDARDS CHECK**
- **Contract**: shared review contract plus `REVIEW-HANDOFF-*`, `REVIEW-MOD-*`, and `REVIEW-PRESENT-*` rules applied
- **Repo Guidance**: `review-architect`, `review-skeptic`, `review-advocate`, and `review-moderator`
- **Scope Rules**: `REVIEW-SCOPE-004` was directly relevant because the change touched AI-customization workflow files
- **Docs Contract**: not applicable
- **Notes**: no vendored files in scope

### 🧰 **AZURERM LINTER**
- **Version**: n/a
- **Status**: Not applicable
- **Run Scope**: n/a
- **Issue Count**: n/a
- **Summary**: no provider Go files in scope

### 🎯 **MUST FIX**
- None

### 🟢 **STRENGTHS**
#### 🚀 Positive feedback: Moderator now owns rich-display semantics end to end
* **Priority**: ⭐ Notable
* **File**: `.github/instructions/review-moderator-compliance-contract.instructions.md`
* **Evidence**: The workflow now routes deterministic presentation hints through moderator-owned records instead of leaving the final rendering layer to reconstruct that intent later.
* **Impact**: This goes beyond baseline transport correctness and makes the review output resilient when the underlying service or workflow requires non-obvious rendering hints such as suggestion blocks.

#### 🚀 Positive feedback: The prompt transport path stays narrow and standards-compliant
* **Priority**: ✅ Good
* **File**: `.github/prompts/code-review-local-changes.prompt.md`
* **Evidence**: The prompt is framed as transport-only for moderated `presentation` metadata and avoids reopening review reasoning in the presentation pass.
* **Impact**: The workflow follows the intended contract layering cleanly without introducing unnecessary orchestration complexity.

### 🟡 **OBSERVATIONS**
- None

### 🔴 **ISSUES**
#### 🔧 Change request: Prompt still leaves rich-display semantics outside moderator ownership
* **Priority**: 🔴 High
* **File**: `.github/prompts/code-review-local-changes.prompt.md`
* **Evidence**: The prompt still implies it may shape structured finding objects instead of treating moderator-owned `presentation` hints as the only canonical source for review type, suggested change, current code, corrected code, and code language.
* **Impact**: Prompt-side invention can drift away from the final moderated finding and make suggestion-style rendering nondeterministic.
* **Suggested Change**: Tighten the prompt wording so it transports only frozen moderated `presentation` hints and never invents missing rich-display semantics.

**Current Code:**

```markdown
- For `mustFix`, `strengths`, `observations`, `issues`, `immediateRecommendations`, and `futureConsiderations`, use structured finding objects from the schema only when the final moderated finding already carries deterministic `presentation` hints or when the corresponding display fields are otherwise already frozen by the shared workflow record.
```

**Suggested Code:**

```suggestion
- For `mustFix`, `strengths`, `observations`, `issues`, `immediateRecommendations`, and `futureConsiderations`, use structured finding objects from the schema only when the final moderated finding already carries deterministic `presentation` hints.
```

## ✅ **RECOMMENDATIONS**

### 🎯 **IMMEDIATE**
- Keep moderator as the canonical owner of rich-display semantics and keep the prompt limited to transport.

### 🔄 **FUTURE CONSIDERATIONS**
- Extend the adjudicated corpus if the renderer grows other GitHub-style affordances such as line comments or multi-snippet suggestion blocks, or if the positive-feedback taxonomy grows beyond `good` and `notable`.

## 🏆 **OVERALL ASSESSMENT**
The new model is directionally correct, but it needs explicit regression coverage around moderator-owned presentation hints, suggestion-style rendering, and positive-feedback priority semantics so future prompt or contract edits cannot silently flatten the output again.

Preflight complete: yes
Skill used: review-architect
Skill used: review-skeptic
Skill used: review-advocate
Skill used: review-moderator
