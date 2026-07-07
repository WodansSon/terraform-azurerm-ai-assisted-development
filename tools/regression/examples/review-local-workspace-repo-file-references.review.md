# 📋 **Code Review**: local review preserves workspace-repo-relative file references for presentation workflow files ## 🔄 **CHANGE SUMMARY**
- **Files Changed**: 2 files (0 new, 2 modified, 0 deleted)
- **Type**: local workspace review
- **Branch**: fixture/local-review-file-references
- **Scope**: verifies that a local review keeps rendered file references workspace-repo-relative instead of leaking machine-local or editor-session links ## 📁 **FILES CHANGED** **Modified Files:**
- `.github/prompts/code-review-local-changes.prompt.md`
- `.github/instructions/review-presentation-compliance-contract.instructions.md` **Added Files:**
- None **Deleted Files:**
- None **Skipped Vendored Files:** 0 ## 🎯 **PRIMARY CHANGES ANALYSIS**
The modeled local review concerns presentation-workflow files only. The benchmarked requirement is that the final rendered review preserves workspace-repo-relative file references instead of rewriting them into editor-session or machine-local path forms. ## 📋 **DETAILED TECHNICAL REVIEW** ### 🔄 **RECURSION PREVENTION**
- None ### 🔍 **STANDARDS CHECK**
- **Contract**: shared review contract applied together with `REVIEW-PRESENT-004E` for final file-reference rendering
- **Repo Guidance**: local-review path applied for workspace-only scope
- **Scope Rules**: `REVIEW-SCOPE-004` and `REVIEW-OUT-*` were directly relevant because the review covered AI-customization workflow files and stable rendered references
- **Docs Contract**: not applicable
- **Notes**: rendered file references remain workspace-repo-relative throughout the review body ### 🧰 **AZURERM LINTER**
- **Version**: n/a
- **Status**: Not applicable
- **Run Scope**: n/a
- **Issue Count**: n/a
- **Summary**: no provider Go files were in scope ### 🎯 **MUST FIX**
- None ### 🟢 **STRENGTHS**
- The rendered review keeps `.github/prompts/code-review-local-changes.prompt.md` and `.github/instructions/review-presentation-compliance-contract.instructions.md` as stable workspace-repo-relative references rather than editor-local or absolute-disk links. ### 🟡 **OBSERVATIONS**
- None ### 🔴 **ISSUES**
- None ## ✅ **RECOMMENDATIONS** ### 🎯 **IMMEDIATE**
- None ### 🔄 **FUTURE CONSIDERATIONS**
- Preserve this regression so future presentation changes do not reintroduce machine-local or editor-local file references into local-review output. ## 🏆 **OVERALL ASSESSMENT**
The local-review output is acceptable when it preserves workspace-repo-relative file references in the rendered review body and avoids leaking editor-session or machine-local path forms. Preflight complete: yes
Skill used: review-architect
Skill used: review-skeptic
