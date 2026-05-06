# 📋 **Code Review**: docs function page-shape regression

## 📊 **CHANGE SUMMARY**
- **Files Changed**: 1 files (0 new, 1 modified, 0 deleted)
- **Scale**: 5 insertions, 2 deletions
- **Branch**: fixture/docs-function-shape vs origin/main
- **Scope**: updates a function docs page but drifts toward ordinary resource-doc structure and examples

## 📁 **FILES CHANGED**

**Modified Files:**
- `website/docs/functions/example_parse_resource_id.html.markdown`

## 🎯 **PRIMARY CHANGES ANALYSIS**
The docs update changes a function page, but it uses the ordinary resource title and section form, omits the required runtime-support note, and does not show the provider-defined function call pattern.

## 📋 **DETAILED TECHNICAL REVIEW**

### 🔄 **RECURSION PREVENTION**
- **File Skipped**: none

### 🔍 **STANDARDS CHECK**
- **Contract**: docs compliance contract applied
- **Repo Guidance**: documentation guidance loaded
- **Scope Rules**: docs-only review path applied
- **Docs Contract**: `DOCS-STRUCT-*`, `DOCS-WORD-003`, and `DOCS-EX-025` were directly relevant
- **Notes**: the review treats `website/docs/functions/**` as a first-class docs type instead of forcing ordinary resource-doc expectations onto the page

### 🧰 **AZURERM LINTER**
- **Version**: n/a
- **Status**: Not applicable
- **Run Scope**: n/a
- **Issue Count**: 0
- **Summary**: docs-only scope

### 🎯 **MUST FIX**
- None

### 🟢 **STRENGTHS**
- The review stays grounded in the function doc type rather than treating the page like a generic resource page.

### 🟡 **OBSERVATIONS**
- The correct remediation is structural: restore the function title, runtime-support note, and provider-defined function example shape.

### 🔴 **ISSUES**
- This page is under `website/docs/functions/`, so it should use the `Function:` title form, the required provider-defined function runtime-support note, and the function-specific `Signature` / `Arguments` structure.
- The example should call the documented function through `provider::azurerm::<name>(...)` rather than behaving like an ordinary resource or data source example.

## ✅ **RECOMMENDATIONS**

### 🎯 **IMMEDIATE**
- Rewrite the page to use the function doc structure: `# Function: example_parse_resource_id`, the required runtime-support note, function-call examples using `provider::azurerm::example_parse_resource_id(...)`, `## Signature`, and `## Arguments`.

### 🔄 **FUTURE CONSIDERATIONS**
- Keep function docs benchmarked separately from ordinary resource and data source pages so `/code-review-docs` does not regress back to the wrong doc type.

## 🏆 **OVERALL ASSESSMENT**
The page is not following the function doc type yet and should be corrected before merge.
