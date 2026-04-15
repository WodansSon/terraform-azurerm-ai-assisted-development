---
description: "Code review for committed changes using the shared review contract and a dedicated azurerm-linter section."
---

# 📋 Code Review - Committed Changes

# 🚫 EXECUTION GUARDRAILS (READ FIRST)

## Audit-only mode
This prompt is audit-only. Do not modify files. Do not propose or apply patches unless the user explicitly asks for fixes.

## Recursion prevention
If the committed change-set includes `.github/prompts/code-review-committed-changes.prompt.md`, skip only that file and disclose the skip in the review output.

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
- The first character of the normal review output must be `#`.

## Mandatory procedure

### 0) Load the shared review contract
- Read and apply `.github/instructions/code-review-compliance-contract.instructions.md` to EOF.
- EOF marker verification is mandatory: the last non-empty line must be `<!-- REVIEW-CONTRACT-EOF -->`.
- If the contract is not fully loaded, hard-stop and output exactly this one line and nothing else:
  - `Cannot run code-review-committed-changes: code review contract not fully loaded. Load .github/instructions/code-review-compliance-contract.instructions.md to EOF and re-run this prompt.`

### 1) Gather the committed change-set
Use `run_in_terminal` with `mode: "sync"`, a concrete `goal`, and a short `timeout` for each command.
Execute these required commands directly when this step begins; do not pause for confirmation.
The commands in steps 1 and 4 must be executed again for each invocation of this prompt, even if they were executed earlier in the conversation.

Run these commands in order and do not repeat them:

```text
git branch --show-current
git --no-pager diff --stat --no-prefix origin/main...HEAD
git --no-pager diff --no-prefix --unified=3 origin/main...HEAD
```

Rules:
- Review the committed diff against `origin/main...HEAD`.
- If the committed diff is empty, hard-stop and output exactly:
  - `☠️ Argh! Shiver me source files! This branch be cleaner than a swabbed deck! Push some code, Ye Lily-livered scallywag! ☠️`
- If the diff is large, inspect the changed files individually rather than rerunning the branch-wide commands.
- If additional commit-by-commit context is genuinely needed after reviewing the diff, inspect the relevant commit(s) individually instead of making commit history a mandatory first step.

### 2) Classify files accurately
- Parse the diff stat carefully so added, modified, and deleted files are counted correctly.
- Do not silently skip files that belong to the committed review scope.

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
- If the committed change-set includes files under `internal/**/*.go` or `internal/**/*_test.go`, attempt azurerm-linter and report it in its own section.
- When this step applies, execute the required repo-root and linter commands directly; do not pause for confirmation.
- Use `run_in_terminal` with `mode: "sync"`, a concrete `goal`, and a longer timeout for the linter command than for the quick git inspection commands.
- Wait for the linter command to finish before classifying the linter section.
- Do not report `Not run` merely because the initial wait window elapsed while the linter command was still running.
- Committed review prefers exact committed-scope linting:
  - Automatically resolve the git repo root by running `git rev-parse --show-toplevel`; do not ask the user for the repo root
  - Run the linter from that repo root
  - Determine a valid pull request number deterministically from explicit review context only
  - Allowed PR number sources are:
    - the active pull request context, when available
    - the currently open or viewed pull request context, when available
    - an explicit PR number supplied by the user or prompt invocation text
  - If a valid PR number is available, run `azurerm-linter --pr=<number> -output json`
  - Do not guess or invent a PR number from the branch name, diff text, commit messages, or other ambiguous signals
- If no in-scope provider Go files exist, mark the linter section as `Not applicable`.
- If no valid pull request number can be determined for the committed branch changes, mark the linter section as `Not run` and instruct the user to create a draft PR and run the review again.
- If the local binary is missing or the tool cannot be run or scoped correctly, mark the section as `Not run` and state the reason.
- If the tool reports `Found 0 changed files` or otherwise has no changed packages to analyze and prints `Error: no packages to analyze`, treat that result as `Not applicable`, not `Not run`.
- If the tool reports a flag or usage parse error such as `flag provided but not defined` and prints usage help, treat that result as `Not run` due to invocation error, not as an install problem.
- Require `azurerm-linter v0.1.8` or newer for review-time JSON mode.
- When the local binary is missing, older than `v0.1.8`, or execution fails for tool-availability reasons, include an install hint pointing to `https://github.com/QixiaLu/azurerm-linter` and `go install github.com/qixialu/azurerm-linter@latest`.
- Report azurerm-linter findings from the executed filtered linter scope as `Issues`.
- Do not leave azurerm-linter findings only inside the `AZURERM LINTER` subsection; also surface them in the main `### 🔴 **ISSUES**` section.
- Structure the linter section from the actual tool output:
  - When a valid JSON payload is present, use `version` as the linter version, use `summary.issue_count` as the issue count, and ignore human-readable preamble logs for structured fields
  - When a valid JSON payload is absent, the tool footer such as `Found X issue(s)` may be used as the issue count when present
  - Put remote/worktree/package-detection/loading/cleanup logs into `Summary`, not the `### 🎯 **MUST FIX**` section
  - Put only actual violation lines into the `### 🎯 **MUST FIX**` section
  - If there are no violations, set the `### 🎯 **MUST FIX**` section to a single bullet: `- None`
  - If there are multiple violations, render a separate `### 🎯 **MUST FIX**` section after the linter execution report and list one normalized `CHECKID path:line: message` entry per bullet
  - When a valid JSON payload is present, derive findings from `findings[]`, derive the reviewer-facing summary from JSON `summary` and `scope` fields, and trim any duplicated leading check ID from `message`
  - If a valid JSON payload is present but `version` is lower than `v0.1.8`, use `Status: Not run`, keep the `### 🎯 **MUST FIX**` section as `- None`, and state that JSON review mode requires `azurerm-linter v0.1.8` or newer
  - Normalize temporary worktree paths to repo-relative paths when deterministic; otherwise keep the raw path
  - If the output shape is `Found 0 changed files` plus `Error: no packages to analyze`, use `Status: Not applicable`, not `Not run`
  - If the output shape is a flag or usage parse error, use `Status: Not run`, keep the `### 🎯 **MUST FIX**` section as `- None`, and do not show an install hint unless the binary is actually missing
  - If `-output json` is unsupported and the tool reports a flag or usage parse error, report that as `Not run`, state that review requires `azurerm-linter v0.1.8` or newer, and do not fall back to text scraping
  - Do not invent broader-scope fallback reporting fields in the normal review flow
  - Keep successful linter output concise and reviewer-facing; do not dump branch, upstream, merge-base, command, log-file, or similar debug details unless they materially explain the result
  - Limit the `### 🧰 **AZURERM LINTER**` execution report to `Version`, `Status`, `Run Scope`, `Issue Count`, and `Summary`
  - Follow it with a separate `### 🎯 **MUST FIX**` section
  - Use the completed linter output, not partial early output, when determining `Version`, `Status`, `Issue Count`, `Summary`, and the `### 🎯 **MUST FIX**` section
  - If the local binary is not found, do not attempt remote execution; report `Not run` and direct the user to install the tool locally
  - If no valid PR number can be determined, use `Status: Not run`, `Run Scope: PR scope`, `Issue Count: n/a`, and a summary that tells the user to create a draft PR and run the review again
  - If the PR number was not supplied explicitly in the committed review invocation, include an example such as `/code-review-committed-changes PR 12345` in that summary
  - Do not ask the user to approve `git rev-parse --show-toplevel` or `azurerm-linter` execution during the normal review flow
  - Do not create temporary scripts or persisted temp log files to run or parse the linter in the normal review flow
  - If a direct linter run cannot be interpreted deterministically, report `Not run` with a concise reason instead of adding execution scaffolding

### 5) Produce the review output
- Review the full committed change-set.
- Findings must follow the shared review contract, including `REVIEW-EVID-*`, `REVIEW-CLASS-*`, and `REVIEW-LINT-*` behavior.
- Apply the file-type coverage rules from `REVIEW-SCOPE-*` so installer/script, AI customization, manifest, and user-visible content checks are not skipped.
- Keep the review concise but complete.

## Output format (use this exact structure)

Output must be rendered Markdown.

- Do not wrap the review in triple-backtick fences.
- Do not output text before the review headings.
- Emit each heading exactly once and in this order.

1. `# 📋 **Code Review**: ${change_description}`
2. `## 📊 **CHANGE SUMMARY**`
3. `## 📁 **FILES CHANGED**`
4. `## 🎯 **PRIMARY CHANGES ANALYSIS**`
5. `## 📋 **DETAILED TECHNICAL REVIEW**`
6. `## ✅ **RECOMMENDATIONS**`
7. `## 🏆 **OVERALL ASSESSMENT**`

Use this template:

```markdown
# 📋 **Code Review**: ${change_description}

## 📊 **CHANGE SUMMARY**
- **Files Changed**: [number] files ([tracked_additions] new, [modifications] modified, [deletions] deleted)
- **Scale**: [insertions] insertions, [deletions] deletions
- **Branch**: [current_branch] vs origin/main
- **Scope**: [brief summary of what changed]

## 📁 **FILES CHANGED**

**Modified Files:**
- `path/to/file`

**Added Files:**
- `path/to/file`

**Deleted Files:**
- `path/to/file`

## 🎯 **PRIMARY CHANGES ANALYSIS**
[Brief explanation of the branch changes and their purpose.]

## 📋 **DETAILED TECHNICAL REVIEW**

### 🔄 **RECURSION PREVENTION**
- **File Skipped**: `.github/prompts/code-review-committed-changes.prompt.md` - Cannot review code review prompt itself to prevent infinite loops

### 🔍 **STANDARDS CHECK**
- **Contract**: [shared review contract rules applied]
- **Repo Guidance**: [contributor docs / instructions / skills actually used]
- **Scope Rules**: [which `REVIEW-SCOPE-*` rules were relevant]
- **Docs Contract**: [whether `DOCS-*` rules were loaded for `website/docs/**/*.html.markdown` files in scope]
- **Notes**: [scope-specific guidance that affected severity or classification]

### 🧰 **AZURERM LINTER**
- **Version**: [JSON `version`, `n/a`, or `unknown` when the tool could not be interrogated reliably]
- **Status**: [Issues found/No issues/Not applicable/Not run]
- **Run Scope**: [PR scope via `--pr=<number>` or `n/a`]
- **Issue Count**: [JSON `summary.issue_count`, tool footer such as `Found X issue(s)`, `0`, or `n/a`, when helpful]
- **Summary**: [result summary or failure reason]

### 🎯 **MUST FIX**
- `None`
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
[Overall assessment and merge-readiness recommendation.]
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
