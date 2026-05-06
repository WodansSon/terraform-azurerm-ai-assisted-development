# 📋 **Code Review**: docs ephemeral-resource page-shape regression

## 📊 **CHANGE SUMMARY**
- **Files Changed**: 1 files (0 new, 1 modified, 0 deleted)
- **Scale**: 5 insertions, 2 deletions
- **Branch**: fixture/docs-ephemeral-shape vs origin/main
- **Scope**: updates an ephemeral-resource docs page but drifts toward ordinary resource-doc structure and examples

## 📁 **FILES CHANGED**

**Modified Files:**
- `website/docs/ephemeral-resources/example_secret.html.markdown`

## 🎯 **PRIMARY CHANGES ANALYSIS**
The docs update changes an ephemeral-resource page, but it uses the ordinary resource title and example form and omits the required Terraform 1.10 support note.

## 📋 **DETAILED TECHNICAL REVIEW**

### 🔄 **RECURSION PREVENTION**
- **File Skipped**: none

### 🔍 **STANDARDS CHECK**
- **Contract**: docs compliance contract applied
- **Repo Guidance**: documentation guidance loaded
- **Scope Rules**: docs-only review path applied
- **Docs Contract**: `DOCS-STRUCT-*`, `DOCS-FMT-*`, `DOCS-WORD-003`, and `DOCS-EX-024` were directly relevant
- **Notes**: the review treats `website/docs/ephemeral-resources/**` as a first-class docs type instead of forcing ordinary resource-doc expectations onto the page

### 🧰 **AZURERM LINTER**
- **Version**: n/a
- **Status**: Not applicable
- **Run Scope**: n/a
- **Issue Count**: 0
- **Summary**: docs-only scope

### 🎯 **MUST FIX**
- None

### 🟢 **STRENGTHS**
- The review stays grounded in the ephemeral-resource doc type rather than treating the page like a generic resource page.

### 🟡 **OBSERVATIONS**
- The correct remediation is structural: restore the ephemeral-resource title, Terraform 1.10 support note, and Terraform `ephemeral` example shape.

### 🔴 **ISSUES**
- This page is under `website/docs/ephemeral-resources/`, so it should use the `Ephemeral:` title form and the required Terraform 1.10 support note rather than ordinary resource-doc wording.
- The example should be a Terraform `ephemeral` example for the documented ephemeral resource, not a `resource` block example.

## ✅ **RECOMMENDATIONS**

### 🎯 **IMMEDIATE**
- Rewrite the page to use the ephemeral-resource doc structure: `# Ephemeral: azurerm_example_secret`, the required Terraform 1.10 support note, and `ephemeral "azurerm_example_secret" "example"` examples.

### 🔄 **FUTURE CONSIDERATIONS**
- Keep ephemeral-resource docs benchmarked separately from ordinary resource and data source pages so `/code-review-docs` does not regress back to the wrong doc type.

## 🏆 **OVERALL ASSESSMENT**
The page is not following the ephemeral-resource doc type yet and should be corrected before merge.
