# 📋 **Code Review**: docs data source lookup example standard ## 📊 **CHANGE SUMMARY**
- **Files Changed**: 1 files (0 new, 1 modified, 0 deleted)
- **Scale**: 5 insertions, 1 deletion
- **Branch**: fixture/docs-datasource-example vs origin/main
- **Scope**: updates a data source docs example to use a minimal existing-object lookup configuration ## 📁 **FILES CHANGED** **Modified Files:**
- `website/docs/d/example_subnet.html.markdown` ## 🎯 **PRIMARY CHANGES ANALYSIS**
The docs update changes the example strategy for a data source page so it demonstrates an existing-object lookup instead of a self-contained resource-style scaffold. ## 📋 **DETAILED TECHNICAL REVIEW** ### 🔄 **RECURSION PREVENTION**
- **File Skipped**: none ### 🔍 **STANDARDS CHECK**
- **Contract**: docs compliance contract applied
- **Repo Guidance**: documentation guidance loaded
- **Scope Rules**: docs-only review path applied
- **Docs Contract**: `DOCS-EX-000`, `DOCS-EX-022`, and `DOCS-EX-010` were directly relevant
- **Notes**: the review treats the example as an existing-object lookup for a data source rather than requiring resource-style scaffolding ### 🧰 **AZURERM LINTER**
- **Version**: n/a
- **Status**: Not applicable
- **Run Scope**: n/a
- **Issue Count**: 0
- **Summary**: docs-only scope ### 🎯 **MUST FIX**
- None ### 🟢 **STRENGTHS**
- The example follows the clarified data source pattern by using only the identifying arguments required to look up an existing object. ### 🟡 **OBSERVATIONS**
- The review correctly avoids forcing resource scaffolding onto a data source example that is teaching an existing-object lookup scenario. ### 🔴 **ISSUES**
- None ## ✅ **RECOMMENDATIONS** ### 🎯 **IMMEDIATE**
- Keep `DOCS-EX-022` authoritative for data source pages when reviewing example strategy. ### 🔄 **FUTURE CONSIDERATIONS**
- Preserve this fixture so docs review does not regress back to resource-style self-containedness requirements for data source examples. ## 🏆 **OVERALL ASSESSMENT**
The docs update is aligned with the clarified data source example standard and should not be blocked for lacking backing-resource scaffolding.
