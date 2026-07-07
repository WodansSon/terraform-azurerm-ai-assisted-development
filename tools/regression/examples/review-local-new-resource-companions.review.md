# 📋 **Code Review**: local new-resource implementation without required companion artifacts ## 🔄 **CHANGE SUMMARY**
- **Files Changed**: 2 files (2 tracked new, 0 untracked, 0 modified, 0 deleted)
- **Line Changes**: 96 insertions, 0 deletions (tracked files only)
- **Branch**: fixture/local-new-resource
- **Type**: unstaged local changes
- **Scope**: adds a brand-new resource implementation and registration entry without the required list-resource companions ## 📁 **FILES CHANGED** **Added Files (Tracked):**
- `internal/services/example/example_resource.go`
- `internal/services/example/registration.go` ## 🎯 **PRIMARY CHANGES ANALYSIS**
The change introduces a new resource, but it stops at the base resource and registration path. Under the current implementation and testing workflow, that is incomplete because the new resource also needs the corresponding list resource, list query tests, and list-resource docs. ## 📋 **DETAILED TECHNICAL REVIEW** ### 🔄 **RECURSION PREVENTION**
- **File Skipped**: none ### 🔍 **STANDARDS CHECK**
- **Contract**: shared review contract applied
- **Repo Guidance**: implementation and testing guidance loaded for `internal/**/*.go` scope
- **Scope Rules**: `REVIEW-SCOPE-005` and `REVIEW-SCOPE-005A` were directly relevant because the change adds a brand-new provider resource
- **Docs Contract**: not applicable
- **Notes**: for a new resource, the review must consider required companion artifacts even when those files are absent from the diff ### 🧰 **AZURERM LINTER**
- **Version**: v0.2.0
- **Status**: No issues
- **Run Scope**: filtered local-diff scope
- **Issue Count**: 0
- **Summary**: linter completed successfully with no findings for the changed packages ### 🎯 **MUST FIX**
- None ### 🟢 **STRENGTHS**
- The base resource registration path is present and the new resource is wired into the service registration. ### 🟡 **OBSERVATIONS**
- The issue here is workflow completeness, not a linter-detectable Go syntax or style problem. ### 🔴 **ISSUES**
- This adds a brand-new resource but does not include the mandatory companion artifacts required by the current upstream-backed workflow: the corresponding list resource, the list query tests, and the list-resource docs under `website/docs/list-resources/`. Without an explicit maintainer-reviewed exception path, that should be treated as incomplete new-resource work. ## ✅ **RECOMMENDATIONS** ### 🎯 **IMMEDIATE**
- Add the `*_resource_list.go` implementation, the corresponding `*_resource_list_test.go` query coverage, and the list-resource docs page under `website/docs/list-resources/`, or explicitly document the maintainer-reviewed upstream exception path if listing is genuinely not supported. ### 🔄 **FUTURE CONSIDERATIONS**
- Keep future new-resource reviews keyed to the companion-artifact workflow so the base resource path is not treated as sufficient on its own. ## 🏆 **OVERALL ASSESSMENT**
The base resource work is directionally correct, but the change is incomplete until the mandatory new-resource companion artifacts, including the list-resource docs, are present or explicitly excepted.
