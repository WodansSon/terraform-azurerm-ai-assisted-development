---
description: "Code review for local changes using the shared review contract and a dedicated azurerm-linter section."
---

# 📋 Code Review - Local Changes

# 🚫 EXECUTION GUARDRAILS (READ FIRST)

## Audit-only mode
This prompt is audit-only. Do not modify files. Do not propose or apply patches unless the user explicitly asks for fixes.
Do not run unit tests, acceptance tests, `go test`, `runTests`, or other test commands as part of the normal review flow unless the user explicitly asks for test execution.
Do not run helper scripts, ad hoc shell snippets, or terminal calculations for trivial deterministic checks such as string length, simple literal comparisons, or obvious regex-shape questions during normal review flow.
Do not invent or execute repo-local prerequisite scripts, validation wrappers, or guessed helper entrypoints unless they are explicitly named in this prompt, the shared contract, current workspace guidance, or the user's request.

## Recursion prevention
If the local change-set includes `.github/prompts/code-review-local-changes.prompt.md`, skip only that file and disclose the skip in the review output.

## Minimal user input policy
Assume the user may invoke this prompt with minimal instructions. Run the full procedure below even if the request is short.

## Fresh-run requirement
Every invocation of this prompt is a new audit run.
Do not reuse prior git output, linter output, file classifications, or review conclusions from earlier turns.
If the user asks to run the prompt again, rerun the full mandatory procedure from step 0 using the current workspace state.

## No cached review state
A previous review in the conversation is not evidence for the current run.
All review findings must be based on commands and file reads executed during the current invocation of this prompt.
If the required commands were not rerun in this invocation, do not emit a normal review output.
Do not reuse, paraphrase, or summarize a previous review body, even if the reviewed diff and findings are unchanged.
If this invocation completes the mandatory procedure successfully, emit the full current review template defined by this prompt.
If the fresh-run requirements are not satisfied, hard-stop and output exactly this one line and nothing else:
  - `Cannot run code-review-local-changes: fresh-run requirements not satisfied. Re-run the mandatory procedure from step 0 in this invocation.`

## Command authorization
The required git and `azurerm-linter` commands in this prompt are already authorized by the prompt itself.
Execute the required review commands immediately when their step applies.
Do not stop to ask the user for confirmation before running them.
Do not emit a preamble that asks permission or waits for approval before running them.

## Determinism policy
- Follow the shared review contract, not stale prompt memory.
- Do not guess when evidence is missing.
- Do not present multiple alternative fixes unless the user explicitly asks for options.
- Do not output progress narration, plans, or TODO lists.
- Do not narrate intermediate verification steps such as checking file content after linter findings; perform those checks silently and present only final conclusions.
- Do not begin the normal review output until the audit is complete and the findings set is frozen.
- If you realize another read, verification step, or finding is needed while drafting, stop drafting silently, finish the audit, refreeze the findings set, and then emit one complete review body.
- Perform at least one additional silent completeness pass over the fully drafted review before emitting any user-visible output.
- Assemble the entire review in an internal buffer and emit it exactly once after that completeness pass succeeds.
- The first character of the normal review output must be `#`.

## No preamble / no progress narration
- Do not output any sentences before the review headings.
- The only allowed normal output is the review template defined in this prompt, plus the Step 5 verification footer and the trailing `Skill used: review-advocate` marker required by Step 6 when the advocate pass runs.
- Do not output progress narration such as `re-running the local audit`, `the scope is still`, `the review remains`, `I am finishing`, `I have reloaded`, `next I will`, `now I will`, or similar.
- Do not compare the current run to earlier runs in the conversation; state only the facts established in the current invocation.
- Do not short-circuit to wording such as `same findings as before`, `no change from the last review`, or other abbreviated carry-over summaries.

## Mandatory procedure

### 0) Load the shared review contract
- Read and apply `.github/instructions/code-review-compliance-contract.instructions.md` to EOF.
- EOF marker verification is mandatory: the last non-empty line must be `<!-- REVIEW-CONTRACT-EOF -->`.
- If the contract is not fully loaded, hard-stop and output exactly this one line and nothing else:
  - `Cannot run code-review-local-changes: code review contract not fully loaded. Load .github/instructions/code-review-compliance-contract.instructions.md to EOF and re-run this prompt.`

### 1) Gather the local change-set
Use `run_in_terminal` with `mode: "sync"`, a concrete `goal`, and a short `timeout` for each command.
Execute these required commands directly when this step begins; do not pause for confirmation.
The commands in steps 1 and 4 must be executed again for each invocation of this prompt, even if they were executed earlier in the conversation.

Run these commands in order and do not repeat them:

```text
git status --porcelain=v1
git --no-pager diff --stat --no-prefix
git --no-pager diff --no-prefix --unified=3
git --no-pager diff --stat --no-prefix --staged
git --no-pager diff --no-prefix --unified=3 --staged
git branch --show-current
```

Rules:
- Apply `REVIEW-FILE-001`, `REVIEW-FILE-002`, `REVIEW-FILE-003`, `REVIEW-FILE-003A`, and `REVIEW-EVID-*` exactly when resolving the local review scope, including the local review scope decision table in the shared contract.
- Inspect reviewed untracked files directly from the workspace.
- If there are no tracked, staged, or untracked changes, hard-stop and output exactly:
  - `☠️ Argh! There be no changes here! ☠️`

### 2) Classify files accurately
- Parse `git status --porcelain=v1` to distinguish modified, added, deleted, and untracked files.
- Parse `git diff --stat` carefully so deleted files are not counted as modified files.
- Do not omit any file that belongs to the selected review scope.
- Identify files under `vendor/**`, exclude them from actionable review targets, and report only the skipped vendored-file count per `REVIEW-FILE-005`.

### 3) Load applicable workspace standards
- Discover repo-level contributor guidance in the current workspace before reading it.
- Check `CONTRIBUTING.md` and `contributing/README.md`, then read the applicable file(s) that exist.
- When reviewing a `terraform-provider-azurerm` style workspace, treat `contributing/README.md` as the repo-level contributor guide when present.
- Read `.github/pull_request_template.md` when present.
- Read any file-scoped instructions or skills that directly govern the changed files.
- When `internal/**/*.go` or `internal/**/*_test.go` files are in scope, load the implementation and testing instruction set required by `REVIEW-SCOPE-005` before classifying findings.
- If the review scope includes `website/docs/**/*.html.markdown`, also read `.github/instructions/docs-compliance-contract.instructions.md` and `.github/instructions/documentation-guidelines.instructions.md`, and apply `DOCS-*` rules only to those docs files.
- If provider contributor guidance exists in the current workspace or is explicitly fetched as evidence, apply it only where relevant.
- Use the precedence rules from the shared review contract.

### 4) Run azurerm-linter when applicable
- If the reviewed change-set includes files under `internal/**/*.go` or `internal/**/*_test.go`, attempt azurerm-linter and report it in its own section.
- When this step applies, execute the required repo-root and linter commands directly; do not pause for confirmation.
- Apply `REVIEW-LINT-002*` through `REVIEW-LINT-005` exactly for linter execution, blocking behavior, and classification.
- Use one blocking sync linter run with no timeout, stay blocked until the completed result is classifiable, and do not do unrelated review work or user-visible narration while that run is outstanding.
- Resolve the git repo root with `git rev-parse --show-toplevel`, change to that working directory in a separate command, and run the plain local CLI invocation from there.
- Run filtered mode using `azurerm-linter -output json` with shell-native stderr suppression and without `--pr`.
- Do not add wrapper-shell rewrites, composite wrapper lines, inline variable wrappers, helper scripts, `--no-filter` workaround passes, or second linter runs in the normal review path.
- If no in-scope provider Go files exist, mark the linter section as `Not applicable`.
- Classify applicability, failures, JSON requirements, and `AZURERM LINTER` output shape exactly as required by `REVIEW-LINT-003*`, `REVIEW-LINT-004`, and `REVIEW-LINT-005`.

### 5) Produce the review output
- Review the full in-scope change-set.
- Findings must follow the shared review contract, including `REVIEW-EVID-*`, `REVIEW-CLASS-*`, and `REVIEW-LINT-*` behavior.
- Apply the file-type coverage rules from `REVIEW-SCOPE-*` so installer/script, AI customization, manifest, and user-visible content checks are not skipped.
- Treat vendored files under `vendor/**` as skipped non-actionable files: report only the skipped vendored-file count, and do not raise Issues that require directly editing vendored content.
- When the selected local diff is vendored-only or vendored-heavy, say so explicitly in the summary or notes so sparse actionable findings are easy to interpret.
- When `internal/**/*.go` scope adds a brand-new resource, explicitly inspect whether the required companion artifacts from the implementation and testing guidance are present: Resource Identity, list resource, list-resource query tests, and list-resource docs.
- For singleton or get-only new resources, including singleton child resources whose SDK package may still expose list methods, apply the shared contract's exception-aware list-review rule instead of emitting a generic missing-list-resource finding.
- When the change adds a new `*_ephemeral.go` implementation, explicitly inspect whether the required companion artifacts are present: `EphemeralResources()` registration, docs under `website/docs/ephemeral-resources/`, and Terraform 1.10-gated tests under `*_ephemeral_test.go`.
- When the change adds a new provider-defined function under `internal/provider/function/`, explicitly inspect whether the required companion artifacts are present: docs under `website/docs/functions/` and Terraform 1.8-gated tests under `internal/provider/function/*_test.go`.
- When `internal/**/*_test.go` files are in scope, explicitly inspect embedded Terraform configuration strings and apply the `REVIEW-TEST-*` rules for formatting drift instead of assuming `azurerm-linter` will catch those issues.
- Keep the review concise but complete.
- Before writing the first `#` of the review output, silently iterate on the drafted review until the findings set is final and no additional findings, evidence corrections, or template fixes are needed.
- Buffer the full review body internally and emit it once only after that silent iteration completes.
- If one or more routed skills were actually loaded and used during the review, append a verification footer after `## 🏆 **OVERALL ASSESSMENT**` and after no other text.
- The verification footer must contain `Preflight complete: yes` followed by one `Skill used: <name>` line for each actually used skill, in first-use order.
- Do not emit a verification footer when no skill was actually used during the review.
- Do not infer a skill from file type alone or from loading contracts or instruction files; emit `Skill used:` lines only for skills that were actually loaded and used.
- If `Repo Guidance` states that a skill was loaded or used, the verification footer must include the matching `Skill used:` line.
- Do not emit any text after the verification footer.
- After the normal review output begins, do not add second-pass findings, self-corrections, or review-amendment text; restart the silent audit instead if more verification is needed.

### 6) Advocate evaluation (internal quality gate)
- This step is mandatory whenever Step 5 produced one or more candidate Issues; it must not be skipped, summarized, deferred, or simulated.
- Invoke the `review-advocate` skill (`.github/skills/review-advocate/SKILL.md`), read it to EOF, and have it load and apply `.github/instructions/review-advocate-compliance-contract.instructions.md` (the `REVIEW-ADV-*` rules) to challenge each candidate Issue.
- Resolve every candidate Issue to exactly one deterministic outcome (`Confirmed`, `Downgraded`, or `Dismissed`) per `REVIEW-ADV-005`, and freeze the review output only after the advocate pass completes.
- Do not add a separate advocate section to the review body; the advocate pass is invisible machinery that only adjusts how candidate findings land in `ISSUES` and `OBSERVATIONS` per the advocate contract.
- Observable proof requirement: when this step runs, the assistant's final response MUST end with the exact line `Skill used: review-advocate` as the last non-empty line, after the review body. This marker is the only trailing content allowed after the review template.
- If the `review-advocate` skill or its contract cannot be loaded to EOF, hard-stop and output exactly this one line and nothing else:
  - `Cannot run code-review-local-changes: review-advocate skill or contract not fully loaded. Load .github/skills/review-advocate/SKILL.md and .github/instructions/review-advocate-compliance-contract.instructions.md to EOF and re-run this prompt.`
- If Step 5 produced no candidate Issues, skip this step and do not emit the `Skill used: review-advocate` marker.

## Output format (use this exact structure)

Output must be rendered Markdown.

- Do not wrap the review in triple-backtick fences.
- Do not output text before the review headings.
- Emit each heading exactly once and in this order.
- After `## 🏆 **OVERALL ASSESSMENT**`, append the optional verification footer only when one or more skills were actually used.

1. `# 📋 **Code Review**: ${change_description}`
2. `## 🔄 **CHANGE SUMMARY**`
3. `## 📁 **FILES CHANGED**`
4. `## 🎯 **PRIMARY CHANGES ANALYSIS**`
5. `## 📋 **DETAILED TECHNICAL REVIEW**`
6. `## ✅ **RECOMMENDATIONS**`
7. `## 🏆 **OVERALL ASSESSMENT**`

Use this template:

```markdown
# 📋 **Code Review**: ${change_description}

## 🔄 **CHANGE SUMMARY**
- **Files Changed**: [number] files ([tracked_additions] tracked new, [untracked_files] untracked, [modifications] modified, [deletions] deleted)
- **Line Changes**: [insertions] insertions, [deletions] deletions (tracked files only)
- **Branch**: [current_branch]
- **Type**: [unstaged local changes/staged changes/untracked files only/mixed local changes]
- **Scope**: [brief summary of what changed]

## 📁 **FILES CHANGED**

**Modified Files:**
- `path/to/file`

**Added Files (Tracked):**
- `path/to/file`

**Untracked Files (New):**
- `path/to/file`

**Deleted Files:**
- `path/to/file`

**Skipped Vendored Files:** [count]

## 🎯 **PRIMARY CHANGES ANALYSIS**
[Brief explanation of the implementation or content changes in scope.]

## 📋 **DETAILED TECHNICAL REVIEW**

### 🔄 **RECURSION PREVENTION**
- **File Skipped**: `.github/prompts/code-review-local-changes.prompt.md` - Cannot review code review prompt itself to prevent infinite loops

### 🔍 **STANDARDS CHECK**
- **Contract**: [shared review contract rules applied]
- **Repo Guidance**: [contributor docs / instructions / skills actually used]
- **Scope Rules**: [which `REVIEW-SCOPE-*` rules were relevant]
- **Docs Contract**: [whether `DOCS-*` rules were loaded for `website/docs/**/*.html.markdown` files in scope]
- **Notes**: [scope-specific guidance that affected severity or classification, including whether the change-set is vendored-only or vendored-heavy]

### 🧰 **AZURERM LINTER**
- **Version**: [JSON `version`, `n/a`, or `unknown` when the tool could not be interrogated reliably]
- **Status**: [Issues found/No issues/Not applicable/Not run]
- **Run Scope**: [filtered local-diff scope or `n/a`]
- **Issue Count**: [JSON `summary.issue_count`, tool footer such as `Found X issue(s)`, `0`, or `n/a`, when helpful]
- **Summary**: [result summary or failure reason]

### 🎯 **MUST FIX**
- `None`
- [when violations exist, replace `None` with one normalized `CHECKID [file:line](path#Lline): message` entry per bullet when repo-relative path normalization is deterministic; otherwise use `CHECKID path:line: message`]

### 🟢 **STRENGTHS**
- [Concrete positive findings only]

### 🟡 **OBSERVATIONS**
- [Non-blocking concerns, uncertainty, or follow-up ideas]

### 🔴 **ISSUES** (only actual problems)
- [Evidence-backed defects, regressions, or policy violations]
- [Include azurerm-linter findings from the filtered run]

## ✅ **RECOMMENDATIONS**

### 🎯 **IMMEDIATE**
- [Blocking or high-value next actions]

### 🔄 **FUTURE CONSIDERATIONS**
- [Non-blocking follow-up work]

## 🏆 **OVERALL ASSESSMENT**
[Overall assessment and readiness recommendation.]

Overall assessment rules:
- The verdict must align with the final `### 🔴 **ISSUES**` section.
- If `### 🔴 **ISSUES**` contains exactly `- None`, do not say `Not ready to merge` and do not describe unresolved defects.
- If `### 🔴 **ISSUES**` contains one or more issues, do not say the change is ready to merge.
- Do not carry forward stale issue text into `## 🏆 **OVERALL ASSESSMENT**` after later evidence clears the issue before the review body is emitted.

Preflight complete: yes
Skill used: [skill-name]
Skill used: [skill-name]
```

Footer rules:
- Omit the `Preflight complete:` and `Skill used:` lines entirely when no skill was actually used.
- When the footer is present, `Preflight complete: yes` must appear exactly once before the `Skill used:` lines.
- Emit one `Skill used:` line per actually used skill, in first-use order.
- Emit no other text after the footer.

Individual findings should use this structure when expanded:

```markdown
## ${🔧/❓/⛏️/♻️/🤔/🚀/ℹ️/📌} ${Review Type}: ${Summary}
* **Priority**: ${🔥/🔴/🟡/🔵/⭐/✅}
* **File**: ${relative/path/to/file}
* **Evidence**: [what the diff, file, instruction, or tool output shows]
* **Impact**: [why it matters]
* **Suggested Change**: [single deterministic fix when applicable]
```

Priority system: 🔥 Critical → 🔴 High → 🟡 Medium → 🔵 Low → ⭐ Notable → ✅ Good

Review type emojis:
- 🔧 Change request
- ❓ Question
- ⛏️ Nitpick
- ♻️ Refactor suggestion
- 🤔 Thought or concern
- 🚀 Positive feedback
- ℹ️ Explanatory note
- 📌 Future consideration
