# 📋 **Code Review**: local AI-toolkit wording alignment with no candidate Issues ## 🔄 **CHANGE SUMMARY**
- **Files Changed**: 2 files (0 tracked new, 0 untracked, 2 modified, 0 deleted)
- **Line Changes**: 10 insertions, 6 deletions (tracked files only)
- **Branch**: fixture/local-review-advocate-skip
- **Type**: unstaged local changes
- **Scope**: aligns advocate skill and contract wording without changing prompt wiring or deterministic outcome behavior ## 📁 **FILES CHANGED** **Modified Files:**
- `.github/skills/review-advocate/SKILL.md`
- `.github/instructions/review-advocate-compliance-contract.instructions.md` ## 🎯 **PRIMARY CHANGES ANALYSIS**
The change aligns wording between the dedicated advocate skill and the advocate contract, but it does not alter prompt orchestration, contract ownership boundaries, or the deterministic outcome mapping. ## 📋 **DETAILED TECHNICAL REVIEW** ### 🔄 **RECURSION PREVENTION**
- **File Skipped**: none ### 🔍 **STANDARDS CHECK**
- **Contract**: shared review contract applied
- **Repo Guidance**: AI-customization review scope applied for `.github/instructions/**` and `.github/skills/**`
- **Scope Rules**: `REVIEW-SCOPE-004` was directly relevant because the change touched AI customization files
- **Docs Contract**: not applicable
- **Notes**: the change is wording alignment only and does not alter shipped runtime boundaries or output semantics ### 🧰 **AZURERM LINTER**
- **Version**: n/a
- **Status**: Not applicable
- **Run Scope**: n/a
- **Issue Count**: n/a
- **Summary**: no provider Go files are in scope ### 🎯 **MUST FIX**
- None ### 🟢 **STRENGTHS**
- The skill and contract continue to keep authority boundaries clear: the skill describes the method and the contract owns the deterministic rules.
- The update does not reintroduce the removed instruction-file design. ### 🟡 **OBSERVATIONS**
- None. ### 🔴 **ISSUES**
- None ## ✅ **RECOMMENDATIONS** ### 🎯 **IMMEDIATE**
- No blocking follow-up is required for this wording-alignment change. ### 🔄 **FUTURE CONSIDERATIONS**
- Preserve this regression case so future advocate-surface edits do not accidentally emit verification markers when no candidate Issues exist. ## 🏆 **OVERALL ASSESSMENT**
The change is acceptable. The primary review pass produces no candidate Issues, so the advocate second pass should not run and no advocate-specific verification marker should appear.
