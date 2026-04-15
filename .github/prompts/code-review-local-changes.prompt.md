---
description: "Code review for local changes using the shared review contract and a dedicated azurerm-linter section."
---

# 📋 Code Review - Local Changes

# 🚫 EXECUTION GUARDRAILS (READ FIRST)

## Audit-only mode
This prompt is audit-only. Do not modify files. Do not propose or apply patches unless the user explicitly asks for fixes.

## Recursion prevention
If the local change-set includes `.github/prompts/code-review-local-changes.prompt.md`, skip only that file and disclose the skip in the review output.

## Minimal user input policy
Assume the user may invoke this prompt with minimal instructions. Run the full procedure below even if the request is short.

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
- The first character of the normal review output must be `#`.

## Mandatory procedure

### 0) Load the shared review contract
- Read and apply `.github/instructions/code-review-compliance-contract.instructions.md` to EOF.
- EOF marker verification is mandatory: the last non-empty line must be `<!-- REVIEW-CONTRACT-EOF -->`.
- If the contract is not fully loaded, hard-stop and output exactly this one line and nothing else:
  - `Cannot run code-review-local-changes: code review contract not fully loaded. Load .github/instructions/code-review-compliance-contract.instructions.md to EOF and re-run this prompt.`

### 1) Gather the local change-set
Use `run_in_terminal` with `mode: "sync"`, a concrete `goal`, and a short `timeout` for each command.
Execute these required commands directly when this step begins; do not pause for confirmation.

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
- Use the unstaged diff as the primary review scope when it is non-empty.
- If the unstaged tracked diff is empty, fall back to the staged diff.
- If `git status --porcelain=v1` shows untracked files, inspect each reviewed untracked file with `read_file`.
- If there are no tracked, staged, or untracked changes, hard-stop and output exactly:
  - `☠️ Argh! There be no changes here! ☠️`

### 2) Classify files accurately
- Parse `git status --porcelain=v1` to distinguish modified, added, deleted, and untracked files.
- Parse `git diff --stat` carefully so deleted files are not counted as modified files.
- Do not omit any file that belongs to the selected review scope.

### 3) Load applicable workspace standards
- Discover repo-level contributor guidance in the current workspace before reading it.
- Check `CONTRIBUTING.md` and `contributing/README.md`, then read the applicable file(s) that exist.
- When reviewing a `terraform-provider-azurerm` style workspace, treat `contributing/README.md` as the repo-level contributor guide when present.
- Read `.github/pull_request_template.md` when present.
- Read any file-scoped instructions or skills that directly govern the changed files.
- If the review scope includes `website/docs/**/*.html.markdown`, also read `.github/instructions/docs-compliance-contract.instructions.md` and `.github/instructions/documentation-guidelines.instructions.md`, and apply `DOCS-*` rules only to those docs files.
- If provider contributor guidance exists in the current workspace or is explicitly fetched as evidence, apply it only where relevant.
- Use the precedence rules from the shared review contract.

### 4) Run azurerm-linter when applicable
- If the reviewed change-set includes files under `internal/**/*.go` or `internal/**/*_test.go`, attempt azurerm-linter and report it in its own section.
- When this step applies, execute the required repo-root and linter commands directly; do not pause for confirmation.
- Use `run_in_terminal` with `mode: "sync"`, a concrete `goal`, and a longer timeout for the linter command than for the quick git inspection commands.
- Wait for the linter command to finish before classifying the linter section.
- Do not report `Not run` merely because the initial wait window elapsed while the linter command was still running.
- Local review prefers exact local-scope linting from the repo root:
  - Automatically resolve the git repo root by running `git rev-parse --show-toplevel`; do not ask the user for the repo root
  - Run the linter from that repo root
  - Run filtered mode first using a direct `azurerm-linter` invocation without `--pr`
  - Treat filtered mode as the baseline review behavior for this feature
  - Do not add a `--no-filter` workaround pass during ordinary review runs
- If no in-scope provider Go files exist, mark the linter section as `Not applicable`.
- If the local binary is missing or the tool cannot be run, mark the section as `Not run` and state the reason.
- If the tool reports no changed files or no changed packages to analyze and prints `Error: no packages to analyze`, treat that result as `Not applicable`, not `Not run`.
- If the tool reports a flag or usage parse error such as `flag provided but not defined` and prints usage help, treat that result as `Not run` due to invocation error, not as an install problem.
- When the local binary is missing or execution fails for tool-availability reasons, include an install hint pointing to `https://github.com/QixiaLu/azurerm-linter` and `go install github.com/qixialu/azurerm-linter@latest`.
- Report azurerm-linter findings from the executed filtered linter scope as `Issues`.
- Do not leave azurerm-linter findings only inside the `AZURERM LINTER` subsection; also surface them in the main `### 🔴 **ISSUES**` section.
- Structure the linter section from the actual tool output:
  - Use the tool footer such as `Found X issue(s)` as the issue count when present
  - Put branch/package-detection/loading/cleanup logs into `Summary`, not the `🎯 Must Fix:` block
  - Put only actual violation lines into the `🎯 Must Fix:` block
  - If there are no violations, set the `🎯 Must Fix:` block to `None`
  - If there are multiple violations, introduce a standalone `🎯 Must Fix:` label and render one normalized `CHECKID path:line: message` entry per bullet below it
  - Normalize temporary or absolute paths to repo-relative paths when deterministic; otherwise keep the raw path
  - If the output shape is `Found 0 changed files` plus `Error: no packages to analyze`, use `Status: Not applicable`, not `Not run`
  - If the output shape is a flag or usage parse error, use `Status: Not run`, keep the `🎯 Must Fix:` block as `None`, and do not show an install hint unless the binary is actually missing
  - Do not invent broader-scope fallback reporting fields in the normal review flow
  - Keep successful linter output concise and reviewer-facing; do not dump branch, upstream, merge-base, command, log-file, or similar debug details unless they materially explain the result
  - Limit the normal linter subsection to `Status`, `Run Scope`, `Issue Count`, `Summary`, and the `🎯 Must Fix:` block
  - Use the completed linter output, not partial early output, when determining `Status`, `Issue Count`, `Summary`, and the `🎯 Must Fix:` block
  - If the local binary is not found, do not attempt remote execution; report `Not run` and direct the user to install the tool locally
  - Do not ask the user to approve `git rev-parse --show-toplevel` or `azurerm-linter` execution during the normal review flow
  - Do not create temporary scripts or persisted temp log files to run or parse the linter in the normal review flow
  - If a direct linter run cannot be interpreted deterministically, report `Not run` with a concise reason instead of adding execution scaffolding

### 5) Produce the review output
- Review the full in-scope change-set.
- Findings must follow the shared review contract, including `REVIEW-EVID-*`, `REVIEW-CLASS-*`, and `REVIEW-LINT-*` behavior.
- Apply the file-type coverage rules from `REVIEW-SCOPE-*` so installer/script, AI customization, manifest, and user-visible content checks are not skipped.
- Keep the review concise but complete.

## Output format (use this exact structure)

Output must be rendered Markdown.

- Do not wrap the review in triple-backtick fences.
- Do not output text before the review headings.
- Emit each heading exactly once and in this order.

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
- **Notes**: [scope-specific guidance that affected severity or classification]

### 🧰 **AZURERM LINTER**
- **Status**: [Issues found/No issues/Not applicable/Not run]
- **Run Scope**: [filtered local-diff scope or `n/a`]
- **Issue Count**: [number from tool footer such as `Found X issue(s)`, `0`, or `n/a`, when helpful]
- **Summary**: [result summary or failure reason]
**🎯 Must Fix:** `None`
- [when violations exist, replace `None` with one normalized `CHECKID path:line: message` entry per bullet]

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
```

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
