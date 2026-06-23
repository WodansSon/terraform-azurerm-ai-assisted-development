# 📋 **Code Review**: local advocate pass resolves dismissed and downgraded findings

## 🔄 **CHANGE SUMMARY**
- **Files Changed**: 2 files (0 tracked new, 0 untracked, 2 modified, 0 deleted)
- **Line Changes**: 14 insertions, 5 deletions (tracked files only)
- **Branch**: fixture/local-review-advocate-outcomes
- **Type**: unstaged local changes
- **Scope**: updates committed-review prompt orchestration alongside the dedicated advocate contract

## 📁 **FILES CHANGED**

**Modified Files:**
- `.github/prompts/code-review-committed-changes.prompt.md`
- `.github/instructions/review-advocate-compliance-contract.instructions.md`

## 🎯 **PRIMARY CHANGES ANALYSIS**
The change keeps the prompt wired to the dedicated advocate skill and contract, but one prompt sentence still overstates a verification requirement. A second apparent problem is not a real defect because the dedicated advocate contract intentionally owns that outcome behavior.

## 📋 **DETAILED TECHNICAL REVIEW**

### 🔄 **RECURSION PREVENTION**
- **File Skipped**: none

### 🔍 **STANDARDS CHECK**
- **Contract**: shared review contract applied
- **Repo Guidance**: AI-customization review scope applied for `.github/prompts/**` and `.github/instructions/**`
- **Scope Rules**: `REVIEW-SCOPE-004` and `REVIEW-CLASS-006` were directly relevant because the change touched prompt orchestration and the dedicated advocate contract
- **Docs Contract**: not applicable
- **Notes**: the advocate pass ran because the primary review produced candidate Issues, so the final output must reflect deterministic post-advocate outcomes

### 🧰 **AZURERM LINTER**
- **Version**: n/a
- **Status**: Not applicable
- **Run Scope**: n/a
- **Issue Count**: n/a
- **Summary**: no provider Go files are in scope

### 🎯 **MUST FIX**
- None

### 🟢 **STRENGTHS**
- The prompt continues to delegate advocate behavior to the dedicated skill and contract instead of re-embedding rule text locally.

### 🟡 **OBSERVATIONS**
- The change does not restate the dismissed-versus-downgraded outcome mapping locally in the prompt. `[⚖️ ADVOCATE: the dedicated advocate contract intentionally owns outcome mapping, so local restatement would reintroduce drift.]`

### 🔴 **ISSUES**
- The committed-review prompt wording still overstates the observable proof requirement by making the verification-footer behavior sound broader than the final output contract requires. That is a real issue, but it is narrower than a full behavior-break claim and should remain in `ISSUES` at reduced severity after the advocate pass.

## ✅ **RECOMMENDATIONS**

### 🎯 **IMMEDIATE**
- Narrow the prompt wording so it describes the verification-footer requirement precisely without overstating the broader output contract.

### 🔄 **FUTURE CONSIDERATIONS**
- Preserve this regression case so future prompt or advocate-contract edits keep dismissed and downgraded findings in their correct final sections.

## 🏆 **OVERALL ASSESSMENT**
The advocate pass is wired correctly and the dismissed-versus-downgraded outcomes land in the right sections, but the remaining prompt wording issue should be corrected before merge.

Preflight complete: yes
Skill used: review-advocate
