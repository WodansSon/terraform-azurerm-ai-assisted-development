# 📋 **Code Review**: local acceptance-test heredoc mixes tabs and spaces in embedded Terraform

## 🔄 **CHANGE SUMMARY**
- **Files Changed**: 1 file (0 tracked new, 0 untracked, 1 modified, 0 deleted)
- **Line Changes**: 6 insertions, 0 deletions (tracked files only)
- **Branch**: fixture/local-review-example
- **Type**: unstaged local changes
- **Scope**: updates an acceptance-test helper and leaves embedded Terraform indentation in a mixed tab-and-space state

## 📁 **FILES CHANGED**

**Modified Files:**
- `internal/services/example/example_resource_test.go`

## 🎯 **PRIMARY CHANGES ANALYSIS**
The changed acceptance-test helper keeps the Go wrapper shape intact, but the embedded Terraform config uses tab-prefixed lines and mixed tabs-plus-spaces for alignment inside the heredoc.

## 📋 **DETAILED TECHNICAL REVIEW**

### 🔄 **RECURSION PREVENTION**
- **File Skipped**: none

### 🔍 **STANDARDS CHECK**
- **Contract**: shared review contract applied
- **Repo Guidance**: testing guidance loaded for `internal/**/*_test.go` scope
- **Scope Rules**: `REVIEW-SCOPE-005` and `REVIEW-TEST-003` were directly relevant because the changed file is an acceptance-test Go file with embedded Terraform
- **Docs Contract**: not applicable
- **Notes**: embedded Terraform formatting in acceptance tests is reviewable from file evidence and does not require test execution to prove

### 🧰 **AZURERM LINTER**
- **Version**: v0.2.0
- **Status**: No issues
- **Run Scope**: filtered local-diff scope
- **Issue Count**: 0
- **Summary**: linter completed successfully with no findings for the changed packages

### 🎯 **MUST FIX**
- None

### 🟢 **STRENGTHS**
- The acceptance-test helper structure is otherwise straightforward and easy to update.

### 🟡 **OBSERVATIONS**
- None.

### 🔴 **ISSUES**
- The embedded Terraform configuration in `internal/services/example/example_resource_test.go` uses tabs and mixed tabs-plus-spaces for indentation inside the heredoc. Acceptance-test Terraform config lines should use two-space indentation only, so this formatting drift should be corrected before merge.

## ✅ **RECOMMENDATIONS**

### 🎯 **IMMEDIATE**
- Replace the tab-prefixed and mixed-indentation Terraform lines in the heredoc with consistently two-space-indented configuration lines.

### 🔄 **FUTURE CONSIDERATIONS**
- Use the companion `Embedded Terraform Formatting` examples when editor tab rendering makes indentation look aligned even though the underlying whitespace is mixed.

## 🏆 **OVERALL ASSESSMENT**
The change is small, but the embedded Terraform formatting issue is a real merge blocker because the repository acceptance-test formatting rules require two-space indentation without tabs inside heredoc configuration blocks.
