# 📋 **Code Review**: committed-review docs deprecation policy handling ## 🔄 **CHANGE SUMMARY**
- **Files Changed**: 3 files (0 new, 0 deleted, 3 modified)
- **Line Changes**: 14 insertions, 7 deletions
- **Branch**: fixture/committed-review-docs-depr
- **Scope**: reviews a mixed PR with provider implementation, live reference docs, and a versioned upgrade guide ## 📁 **FILES CHANGED** **Modified Files:**
- `internal/services/example/example_custom_domain_resource.go`
- `website/docs/r/example_custom_domain.html.markdown`
- `website/docs/guides/example-upgrade-guide.html.markdown` ## 🎯 **PRIMARY CHANGES ANALYSIS**
The modeled PR keeps the provider-compatible transitional path while moving legacy-field migration guidance out of the live reference doc and into the 5.0 upgrade guide. The benchmarked requirement is that committed review honors the docs contract's next-major deprecation policy instead of demanding legacy-field parity in the live docs. ## 📋 **DETAILED TECHNICAL REVIEW** ### 🔄 **RECURSION PREVENTION**
- **File Skipped**: none ### 🔍 **STANDARDS CHECK**
- **Contract**: shared review contract applied
- **Repo Guidance**: committed-review path applied with docs contract and documentation guidance loaded for the reference docs in scope
- **Scope Rules**: `REVIEW-SCOPE-004A`, `DOCS-DEPR-001`, `DOCS-DEPR-002`, and `DOCS-EVID-001` were directly relevant because the PR includes live reference docs and a versioned upgrade guide alongside implementation changes
- **Docs Contract**: loaded and applied for the `website/docs/**/*.html.markdown` files in scope
- **Notes**: the review treats the legacy `minimum_tls_version` field as non-vNext and accepts its removal from the live reference docs while keeping migration guidance in the upgrade guide, consistent with `DOCS-DEPR-001` and `DOCS-DEPR-002` ### 🧰 **AZURERM LINTER**
- **Version**: v0.2.0
- **Status**: No issues
- **Run Scope**: PR-scoped diff for the committed review context
- **Issue Count**: 0
- **Summary**: linter completed successfully for the in-scope provider Go change with no findings ### 🎯 **MUST FIX**
- None ### 🟢 **STRENGTHS**
- The review applies `DOCS-DEPR-001` and `DOCS-DEPR-002` instead of treating the live reference doc as requiring legacy-field parity with the transitional implementation path. ### 🟡 **OBSERVATIONS**
- The migration note belongs in `website/docs/guides/example-upgrade-guide.html.markdown`, not in the live resource reference doc. ### 🔴 **ISSUES**
- None ## ✅ **RECOMMENDATIONS** ### 🎯 **IMMEDIATE**
- Keep `DOCS-DEPR-001` and `DOCS-DEPR-002` authoritative in mixed committed reviews whenever `website/docs/**/*.html.markdown` files are part of the PR scope. ### 🔄 **FUTURE CONSIDERATIONS**
- Preserve this regression case so committed review does not regress back to generic docs-parity findings for legacy non-vNext fields. ## 🏆 **OVERALL ASSESSMENT**
The committed-review flow is acceptable when it treats legacy non-vNext fields as intentionally absent from live reference docs and keeps migration guidance in the versioned upgrade guide.
