# 📋 **Code Review**: local review moderator merges duplicate routed findings into one final moderated record

## 🔄 **CHANGE SUMMARY**
- **Files Changed**: 3 files (1 tracked new, 0 untracked, 2 modified, 0 deleted)
- **Line Changes**: 29 insertions, 7 deletions (tracked files only)
- **Branch**: fixture/local-review-moderator-duplicate-merge
- **Type**: unstaged local changes
- **Scope**: exercises duplicate routed findings that should converge into one final moderated record before presentation

## 📁 **FILES CHANGED**

**Modified Files:**
- `.github/instructions/review-moderator-compliance-contract.instructions.md`
- `.github/prompts/code-review-local-changes.prompt.md`

**Added Files (Tracked):**
- `.github/instructions/review-workflow-handoff.schema.json`

## 🎯 **PRIMARY CHANGES ANALYSIS**
The workflow threads a shared handoff schema through routed review roles and lets moderator merge duplicate concerns after advocate adjudication. The core risk is that the same underlying concern could still survive as repeated final findings if the duplicate-merge rules are not applied consistently.

## 📋 **DETAILED TECHNICAL REVIEW**

### 🔄 **RECURSION PREVENTION**
- **File Skipped**: none

### 🔍 **STANDARDS CHECK**
- **Contract**: shared review contract plus `REVIEW-HANDOFF-*` and `REVIEW-MOD-*` rules applied
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
- The workflow now has one explicit synthesis owner for duplicate routed concerns.

### 🟡 **OBSERVATIONS**
- None

### 🔴 **ISSUES**
- The same underlying routed concern can still be described three times across reviewer, skeptic, and architect records. The moderator path must merge those into one final moderated finding that preserves the strongest evidence and combined role attribution rather than emitting repeated final issues.

## ✅ **RECOMMENDATIONS**

### 🎯 **IMMEDIATE**
- Keep the shared handoff record identity intact through moderator merge and preserve the strongest evidence on the surviving record.

### 🔄 **FUTURE CONSIDERATIONS**
- Keep this adjudicated case in the suite so future routing refactors cannot regress back to duplicate final findings.

## 🏆 **OVERALL ASSESSMENT**
The moderator-routed workflow direction is correct, but duplicate routed concerns must converge into one final moderated finding before output is frozen.

Preflight complete: yes
Skill used: review-architect
Skill used: review-skeptic
Skill used: review-advocate
Skill used: review-moderator
