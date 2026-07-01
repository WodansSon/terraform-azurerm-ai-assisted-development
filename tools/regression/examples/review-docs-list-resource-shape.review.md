# 📋 **Code Review**: docs list-resource page-shape regression ## 📊 **CHANGE SUMMARY**
- **Files Changed**: 1 files (0 new, 1 modified, 0 deleted)
- **Scale**: 6 insertions, 3 deletions
- **Branch**: fixture/docs-list-resource-shape vs origin/main
- **Scope**: updates a list-resource docs page but drifts toward ordinary resource-doc structure and examples ## 📁 **FILES CHANGED** **Modified Files:**
- `website/docs/list-resources/example_network_profile.html.markdown` ## 🎯 **PRIMARY CHANGES ANALYSIS**
The docs update changes a list-resource page, but it uses the ordinary resource title, summary, section intro, and example form instead of the list-resource-specific doc shape. ## 📋 **DETAILED TECHNICAL REVIEW** ### 🔄 **RECURSION PREVENTION**
- **File Skipped**: none ### 🔍 **STANDARDS CHECK**
- **Contract**: docs compliance contract applied
- **Repo Guidance**: documentation guidance loaded
- **Scope Rules**: docs-only review path applied
- **Docs Contract**: `DOCS-STRUCT-*`, `DOCS-FMT-*`, `DOCS-WORD-003`, and `DOCS-EX-023` were directly relevant
- **Notes**: the review treats `website/docs/list-resources/**` as a first-class docs type instead of forcing ordinary resource-doc expectations onto the page ### 🧰 **AZURERM LINTER**
- **Version**: n/a
- **Status**: Not applicable
- **Run Scope**: n/a
- **Issue Count**: 0
- **Summary**: docs-only scope ### 🎯 **MUST FIX**
- None ### 🟢 **STRENGTHS**
- The review stays grounded in the list-resource doc type instead of treating the page like a generic resource page. ### 🟡 **OBSERVATIONS**
- The correct remediation is structural: restore the list-resource title, summary, section intro, and Terraform `list` query examples. ### 🔴 **ISSUES**
- This page is under `website/docs/list-resources/`, so it should use the list-resource title and summary shape rather than ordinary resource-doc wording.
- The example should be a Terraform `list` query example for the documented list resource, not a `resource` block example. ## ✅ **RECOMMENDATIONS** ### 🎯 **IMMEDIATE**
- Rewrite the page to use the list-resource doc structure: `# List resource: azurerm_example_network_profile`, a `Lists... resources.` summary, `## Argument Reference`, and `list "azurerm_example_network_profile" "example"` examples. ### 🔄 **FUTURE CONSIDERATIONS**
- Keep list-resource docs benchmarked separately from ordinary resource and data source pages so `/code-review-docs` does not regress back to the wrong doc type. ## 🏆 **OVERALL ASSESSMENT**
The page is not following the list-resource doc type yet and should be corrected before merge.
