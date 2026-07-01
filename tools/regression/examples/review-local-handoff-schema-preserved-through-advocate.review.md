# 📋 **Code Review**: local review preserves schema-backed handoff records through advocate resolution ## 🔄 **CHANGE SUMMARY**
- **Files Changed**: 4 files (1 tracked new, 0 untracked, 3 modified, 0 deleted)
- **Line Changes**: 41 insertions, 8 deletions (tracked files only)
- **Branch**: fixture/local-review-handoff-schema
- **Type**: unstaged local changes
- **Scope**: adds a shared workflow handoff schema and aligns the local review prompt plus skeptic and advocate contracts to use it ## 📁 **FILES CHANGED** **Modified Files:**
- `.github/prompts/code-review-local-changes.prompt.md`
- `.github/instructions/review-skeptic-compliance-contract.instructions.md`
- `.github/instructions/review-advocate-compliance-contract.instructions.md` **Added Files (Tracked):**
- `.github/instructions/review-workflow-handoff.schema.json` ## 🎯 **PRIMARY CHANGES ANALYSIS**
The change introduces a shared handoff schema for routed review roles and threads it through the local review workflow. The design is directionally correct, but one wording path still suggests advocate adjudication could bypass the schema-backed record shape. ## 📋 **DETAILED TECHNICAL REVIEW** ### 🔄 **RECURSION PREVENTION**
- **File Skipped**: none ### 🔍 **STANDARDS CHECK**
- **Contract**: shared review contract applied
- **Repo Guidance**: AI-customization review scope applied for `.github/prompts/**` and `.github/instructions/**`
- **Scope Rules**: `REVIEW-SCOPE-004`, `REVIEW-HANDOFF-*`, `REVIEW-SKEP-002`, and `REVIEW-ADV-005` were directly relevant because the change defines a workflow schema and routes it through skeptic and advocate behavior
- **Docs Contract**: not applicable
- **Notes**: the routed architect, skeptic, and advocate passes all ran because the local review prompt now treats the schema-backed handoff as workflow machinery ### 🧰 **AZURERM LINTER**
- **Version**: n/a
- **Status**: Not applicable
- **Run Scope**: n/a
- **Issue Count**: n/a
- **Summary**: no provider Go files are in scope ### 🎯 **MUST FIX**
- None ### 🟢 **STRENGTHS**
- The change creates one concrete runtime JSON schema for routed-role findings instead of leaving the handoff shape as prompt-only prose. ### 🟡 **OBSERVATIONS**
- Treating optional `roleNotes` as mandatory would be a false positive. `[⚖️ ADVOCATE: the shared schema intentionally keeps roleNotes optional, so missing roleNotes alone does not break the handoff record shape.]` ### 🔴 **ISSUES**
- One wording path still implies the advocate may bypass the shared handoff record and replace a routed candidate with prose. That breaks the point of the shared schema and should be corrected so adjudication preserves the same record shape while changing only status or severity. ## ✅ **RECOMMENDATIONS** ### 🎯 **IMMEDIATE**
- Narrow the prompt or contract wording so it states explicitly that advocate adjudication preserves the shared schema-backed handoff record. ### 🔄 **FUTURE CONSIDERATIONS**
- Keep this regression case in the adjudicated corpus so future workflow changes cannot silently revert back to prose-only routed findings. ## 🏆 **OVERALL ASSESSMENT**
The workflow direction is correct and materially closer to the roadmap end state. The remaining wording drift around schema preservation should be fixed before relying on the handoff shape as the durable transport between roles. Preflight complete: yes
Skill used: review-architect
Skill used: review-skeptic
Skill used: review-advocate
