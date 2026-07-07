# 📋 **Code Review**: committed review catches conditional required-field docs parity gaps

## 🔄 **CHANGE SUMMARY**
- **Files Changed**: 3 files (0 new, 0 deleted, 3 modified)
- **Line Changes**: 11 insertions, 4 deletions
- **Branch**: fixture/committed-review-conditional-required-docs
- **Scope**: reviews a mixed PR with validator logic, provider implementation, and a changed reference docs page

## 📁 **FILES CHANGED**
**Modified Files:**
- `internal/services/example/example_rule_definition_validation.go`
- `internal/services/example/example_batch_resource.go`
- `website/docs/r/example_batch_resource.html.markdown`

## 🎯 **PRIMARY CHANGES ANALYSIS**
The modeled PR changes validator logic and the companion resource docs in the same scope. The validator requires `duration_value` when `duration_mode` is `AlwaysOverride` or `OverrideWhenMissing`, but the docs page still describes `duration_value` generically without documenting that conditional requirement. The benchmarked behavior is that committed review preserves this validator-to-doc parity gap instead of treating the docs as complete just because the field is mentioned somewhere on the page.

## 📋 **DETAILED TECHNICAL REVIEW**

### 🔄 **RECURSION PREVENTION**
- **File Skipped**: none

### 🔍 **STANDARDS CHECK**
- **Contract**: shared review contract applied
- **Repo Guidance**: committed-review path applied with docs evidence checks because validator logic and the changed reference docs are both in scope
- **Scope Rules**: `REVIEW-COORD-004` and `DOCS-EVID-001` were directly relevant because the same review scope includes validator logic and a changed docs page whose conditional requirement can be proven from workspace evidence
- **Docs Contract**: applied to the changed `website/docs/r/example_batch_resource.html.markdown` page for validator-backed docs parity
- **Notes**: the review must not treat field mention alone as sufficient when the validator shows the field becomes conditionally required for specific `duration_mode` values

### 🧰 **AZURERM LINTER**
- **Version**: v0.2.0
- **Status**: No issues
- **Run Scope**: PR-scoped diff for the committed review context
- **Issue Count**: 0
- **Summary**: linter completed successfully for the in-scope provider Go changes with no findings that change the review outcome

### 🎯 **MUST FIX**
- None

### 🟢 **STRENGTHS**
- The validator and docs page are both in scope, so the conditional requirement can be proven from current-run evidence instead of guessed.

### 🟡 **OBSERVATIONS**
- None

### 🔴 **ISSUES**
- `website/docs/r/example_batch_resource.html.markdown` does not document that `duration_value` becomes required when `duration_mode` is `AlwaysOverride` or `OverrideWhenMissing`. Because the validator enforces those two mode-specific requirements, the docs currently present `duration_value` as optional in situations where the implementation treats it as a blocking conditional requirement.

## ✅ **RECOMMENDATIONS**

### 🎯 **IMMEDIATE**
- Update `website/docs/r/example_batch_resource.html.markdown` to state that `duration_value` is required when `duration_mode` is `AlwaysOverride` or `OverrideWhenMissing`.

### 🔄 **FUTURE CONSIDERATIONS**
- Keep this adjudicated case in the suite so mixed committed reviews do not regress back to treating field mention alone as sufficient docs coverage when validator-backed conditional requirements exist.

## 🏆 **OVERALL ASSESSMENT**
The committed-review flow is correct only if it preserves the validator-backed docs parity issue for `duration_value` instead of treating the docs page as complete because the field is mentioned somewhere on the page.
