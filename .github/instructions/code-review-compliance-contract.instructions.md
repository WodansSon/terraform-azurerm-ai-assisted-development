---
description: "Shared code review compliance contract used by /code-review-local-changes and /code-review-committed-changes."
---

# Code Review Compliance Contract

This file is the single source of truth for code review compliance in this repository.

## Consumers

Two independent review workflows MUST follow this contract:

- Consumer: `.github/prompts/code-review-local-changes.prompt.md`
  - Role: Auditor
  - Requires EOF Load: yes
  - Goal: review local workspace changes deterministically.
- Consumer: `.github/prompts/code-review-committed-changes.prompt.md`
  - Role: Auditor
  - Requires EOF Load: yes
  - Goal: review committed branch changes deterministically.

The prompts define the execution flow and output template.
This contract defines the review rules, evidence hierarchy, finding classification, and azurerm-linter handling.

## Canonical sources of truth (precedence)

Use these sources with the following roles:

- Workspace contributor guidance
  - Repo-level contributor documentation in common workspace locations such as `CONTRIBUTING.md` and `contributing/README.md`
  - .github/pull_request_template.md
  - README or subsystem documentation when directly relevant to touched files
- Workspace file-scoped instructions and skills
  - .github/instructions/**/*.instructions.md
  - .github/skills/**/SKILL.md
- Target-provider contributor guidance, when present in the workspace or explicitly fetched as evidence
  - contributing/topics/**/*.md
  - Especially acceptance testing, documentation, naming, schema, and PR guidance in hashicorp/terraform-provider-azurerm
- This contract
  - Authoritative for review methodology in this repository
  - Defines evidence rules, classification rules, and linter reporting requirements

Conflict resolution:

- This contract is authoritative for review process, finding classification, verification requirements, and linter section behavior.
- Current workspace contributor documentation is authoritative for repo-specific expectations.
- File-scoped instructions and loaded skills are authoritative for the files they govern.
- If older prompt wording conflicts with current contributor guidance or file-scoped instructions, follow the contributor guidance and this contract.
- If upstream provider guidance is used, it must not override explicit current-workspace guidance unless the workspace is the provider repo under review or the workspace guidance explicitly defers to upstream.

## Rule IDs

Rules are identified by stable IDs so both review prompts can reference the same requirement set without drifting.

ID format:
- REVIEW-<AREA>-<NNN>

Areas:
- EVID = evidence and verification guardrails
- CLASS = finding classification
- FILE = change-set coverage and file handling
- SCOPE = file-type-specific review coverage
- TEST = acceptance test review guidance
- OBS = observation-only design guidance
- LINT = azurerm-linter behavior
- OUT = required review output semantics

## Evidence hierarchy

When a review claim affects correctness, severity, or merge readiness, use this evidence order:

1. Changed files and the actual diff under review
2. Current workspace contributor guidance and file-scoped instructions
3. Current workspace implementation details, tests, and surrounding code
4. Tool output, including azurerm-linter
5. External references for semantics only, when workspace evidence is insufficient

If evidence is missing for a claim that would change severity or requested action, do not guess.

# Contract Rules

## Evidence and verification

### REVIEW-EVID-001: Do not guess when evidence is required
- Rule: If a compliance-relevant or correctness-relevant claim cannot be backed by available evidence, do not invent it.
- Reviewer behavior: downgrade to an Observation, ask for clarification, or explicitly state that evidence could not be proven.

### REVIEW-EVID-002: Verify display artifacts before flagging formatting or encoding issues
- Rule: Terminal wrapping, diff truncation, and chat rendering artifacts must be verified against actual file content before being reported as Issues.
- Reviewer behavior: use file reads to confirm the content before flagging syntax, formatting, encoding, or line-break corruption.

### REVIEW-EVID-003: Attribute policies to real sources
- Rule: Do not claim that a style or implementation rule is mandatory unless it is supported by a current contributor document, instruction file, skill, implementation pattern, or this contract.
- Reviewer behavior: avoid invented policy language such as "must" or "required" when the source only supports a preference.

### REVIEW-EVID-004: Discover contributor-guidance paths before claiming absence
- Rule: Do not assume repo-level contributor guidance always lives at `CONTRIBUTING.md`.
- Rule: Check common workspace locations such as `CONTRIBUTING.md` and `contributing/README.md` before claiming contributor guidance is absent.
- Rule: When reviewing a `terraform-provider-azurerm` style workspace, treat `contributing/README.md` as repo-level contributor guidance when present.

### REVIEW-EVID-005: Perform post-tool verification silently
- Rule: When tool output needs confirmation against current file content, diff context, or surrounding code, perform that verification silently.
- Rule: Do not narrate intermediate verification steps such as reading files, checking lines, confirming linter findings, or comparing tool output against workspace content.
- Rule: Reviews should present only the final evidence-backed conclusions, not the internal process used to reach them.

### REVIEW-EVID-006: Every invocation is a fresh audit run
- Rule: Every invocation of a code review prompt is a new audit run.
- Rule: Do not reuse prior git output, linter output, file classifications, or review conclusions from earlier turns in the conversation.
- Rule: A previous review in the conversation is not evidence for the current run.
- Rule: All review findings must be based on commands and file reads executed during the current invocation.
- Rule: If the required commands for the selected review type were not rerun in the current invocation, do not emit a normal review output.

### REVIEW-EVID-007: Describe only current-run facts
- Rule: Do not compare the current review invocation to earlier invocations in user-visible output.
- Rule: Do not use comparative carry-over wording such as `still`, `again`, `reloaded`, `same as before`, `remains`, or `continues` when describing current-run evidence unless directly quoting user input or tool output.
- Rule: State current-run facts directly from the evidence gathered in the current invocation.

### REVIEW-EVID-008: Do not reuse prior review body text
- Rule: Do not reuse, quote, paraphrase, or summarize a prior review body as the current review output, even when the reviewed change-set and findings are unchanged.
- Rule: Reconstruct the review body from current-run evidence and the current prompt/template requirements for every invocation.

## Finding classification

### REVIEW-CLASS-001: Issues are for actual problems only
- Rule: An Issue must be a real defect, regression, policy violation, missing requirement, or correctness risk with evidence.
- Rule: Do not place stylistic preferences or speculative concerns in Issues.

### REVIEW-CLASS-002: Observations are non-blocking
- Rule: Observations capture design concerns, preferences, uncertainty, or follow-up ideas that are not clearly blocking.
- Rule: If the current implementation is acceptable under the available evidence, keep it out of Issues even if another design might be preferable.

### REVIEW-CLASS-003: Strengths must be factual
- Rule: Strengths should call out concrete, evidenced positives.
- Rule: Do not use Strengths to pad the review with generic praise.

### REVIEW-CLASS-004: One finding, one classification
- Rule: The same underlying concern must not appear in both Observations and Issues.
- Rule: If severity is uncertain, choose the lower justified classification and explain why.

### REVIEW-CLASS-005: Fixes must be deterministic
- Rule: Each Issue should point to a single, concrete correction path.
- Rule: Do not present multiple alternative fixes unless the user explicitly asked for options.

## Change-set coverage and file handling

### REVIEW-FILE-001: Review the full change-set in scope
- Rule: Every changed file reported by the selected diff scope must be considered.
- Rule: Do not silently skip files.

### REVIEW-FILE-002: Classify changed files accurately
- Rule: Added, modified, deleted, staged, and untracked files must be counted and described accurately.
- Rule: Do not misclassify deleted files as modified files, or untracked files as tracked additions.

### REVIEW-FILE-003: Self-review recursion prevention is explicit
- Rule: If the active review prompt file itself is part of the reviewed change-set, skip only that specific file.
- Rule: The skip must be disclosed explicitly in the review output.

## File-type-specific review coverage

### REVIEW-SCOPE-001: Always review user-visible content quality
- Rule: For any changed user-visible text, review spelling, grammar, command accuracy, naming consistency, and professional but community-friendly tone.
- Rule: Do not treat visible text quality as out of scope just because the file is not code.

### REVIEW-SCOPE-002: Review command examples and snippets for plausibility
- Rule: When changed content includes commands, flags, paths, or usage examples, review them for internal consistency with the repository's current behavior and terminology.
- Rule: If full execution is not possible, assess the examples against workspace evidence and note any unverified assumptions.

### REVIEW-SCOPE-003: Installer and script changes must consider cross-platform drift
- Rule: When PowerShell, Bash, installer entrypoints, or shared installer manifests change, review for cross-platform behavior drift.
- Rule: If a user-visible behavior or message changes in one installer path, check whether the corresponding PowerShell and Bash paths remain aligned when the workspace guidance expects parity.
- Rule: Pay particular attention to bootstrap versus release-bundle messaging, shared manifest usage, and command-line help examples.

### REVIEW-SCOPE-004: Prompt, instruction, and skill changes must review determinism and alignment
- Rule: When `.github/prompts/**`, `.github/instructions/**`, `.github/skills/**`, or related customization files change, review for determinism, source precedence, and rule alignment.
- Rule: Check for duplicated normative rules when a shared contract exists, stale embedded policy that can drift, broken recursion-prevention logic, and unstable or contradictory output-shape requirements.
- Rule: Exact hard-stop text, verification markers, and other deliberately stable user-facing strings must be preserved unless there is an intentional reason to change them.

### REVIEW-SCOPE-004A: Reference docs under website/docs defer to the docs compliance contract
- Rule: When the review scope includes files under `website/docs/**/*.html.markdown`, load and apply `.github/instructions/docs-compliance-contract.instructions.md` and `.github/instructions/documentation-guidelines.instructions.md` for those files.
- Rule: For those files, the `DOCS-*` rules are the canonical documentation compliance rules.
- Rule: The generic code review contract continues to govern overall review flow, evidence handling, classification, and output shape.
- Rule: The docs-writer verification footer and docs-only prompt output contract do not apply to `/code-review-local-changes` or `/code-review-committed-changes`.
- Rule: Do not extend `DOCS-*` rules to non-reference docs such as `README.md`, `docs/*.md`, or other markdown files unless a future contract explicitly does so.

### REVIEW-SCOPE-005: Go implementation and acceptance-test files defer to scoped guidance
- Rule: When the review scope includes `internal/**/*.go` or `internal/**/*_test.go`, load and apply the applicable file-scoped instructions and skills.
- Rule: Use those sources as the primary checklist for provider implementation and acceptance-test concerns rather than relying on stale prompt summaries.

### REVIEW-SCOPE-006: Manifest and bundle changes must match shipped content expectations
- Rule: When file manifests, release-bundle lists, or installer packaging inputs change, review whether the changed entries remain consistent with the repository structure and the expected shipped assets.
- Rule: Treat missing or mismatched prompt, instruction, skill, or installer entries as reviewable issues when the manifest is intended to distribute them.

## Acceptance-test review guidance

### REVIEW-TEST-001: ImportStep guidance is evidence-based, not absolute
- Rule: Treat ImportStep as strong evidence that configured state is validated, but not as a blanket prohibition on all additional checks.
- Rule: Additional explicit checks are acceptable when they verify behavior that ImportStep does not cover.

### REVIEW-TEST-002: RequiresImport patterns follow current contributor guidance
- Rule: Evaluate requires-import tests against the active contributor guidance and the resource's actual behavior.
- Rule: Do not report a requires-import pattern as wrong solely because it differs from an older prompt preference.

### REVIEW-TEST-003: Embedded Terraform in acceptance tests follows terrafmt
- Rule: When reviewing files under `internal/**/*_test.go`, inspect embedded Terraform configuration strings, including raw string literals used to define acceptance-test configuration.
- Rule: For embedded Terraform blocks, treat `terrafmt` output as the canonical formatting standard.
- Rule: Flag obvious formatting drift that would likely fail `terrafmt` or `make tflint`.
- Rule: Within embedded Terraform blocks, tabs used for indentation are not acceptable; follow normal `terrafmt` indentation, which is typically two spaces per nesting level.
- Rule: Scope this rule only to embedded Terraform blocks inside Go acceptance-test strings; do not treat tabs in normal Go source as a formatting issue.
- Rule: Do not assume `azurerm-linter` will catch formatting problems inside embedded Terraform strings.

## Observation-only design guidance

### REVIEW-OBS-001: Boolean toggle schema preference is observation-only by default
- Rule: If a string enum behaves like a boolean toggle, prefer a boolean *_enabled shape for new schema design.
- Rule: This is an Observation unless current workspace guidance makes it a mandatory rule for the reviewed change.

### REVIEW-OBS-002: StringIsNotEmpty alone is not automatically an Issue
- Rule: A TypeString field using only validation.StringIsNotEmpty is not, by itself, sufficient evidence for an Issue.
- Rule: Escalate only when current guidance or clear implementation context shows stronger validation is both feasible and required.

## azurerm-linter

### REVIEW-LINT-001: Include a dedicated azurerm-linter section in every review
- Rule: Both review prompts must emit a standalone azurerm-linter section.
- Rule: The section must appear even when the tool is not applicable or cannot be run.

### REVIEW-LINT-002: Run azurerm-linter when the scoped changes include provider Go files
- Rule: If the reviewed change-set includes files under internal/**/*.go or internal/**/*_test.go, attempt azurerm-linter.
- Rule: If no such files are in scope, report the section as Not applicable.

### REVIEW-LINT-002A: Local installation is required for linter execution
- Rule: Review prompts should rely on a locally installed `azurerm-linter` binary.
- Rule: Treat `azurerm-linter` as a standalone locally installed CLI, not as a Go toolchain command.
- Rule: Do not fetch or execute `azurerm-linter` via `go run` from a remote module path during review.
- Rule: The minimum supported `azurerm-linter` version for review is `v0.2.0`.
- Rule: If the local binary is missing, older than `v0.2.0`, or the tool cannot be executed reliably, report the linter section as `Not run` and include a short install hint pointing to the upstream repository and the local install command.

### REVIEW-LINT-002B: Execute azurerm-linter from the git repo root
- Rule: Before running azurerm-linter, resolve the git repository root with `git rev-parse --show-toplevel`.
- Rule: Execute azurerm-linter from that repo root, not from an arbitrary subdirectory.
- Rule: Run the linter in the current platform's native shell environment using the plain local CLI invocation.
- Rule: For the primary JSON-mode run, keep stdout clean by redirecting stderr to the active shell's null device using native syntax.
- Rule: Examples of native stderr suppression include PowerShell `2>$null`, POSIX shells `2>/dev/null`, and cmd.exe `2>nul`.
- Rule: Do not rewrite the command through another runtime environment or wrapper such as `wsl`, `wsl --cd`, `bash -lc`, `sh -lc`, `cmd /c`, or `powershell -Command`.
- Rule: On Windows, the expected review-time linter command is plain `azurerm-linter ...` from the resolved repo root, not a WSL-prefixed equivalent.
- Rule: Record the resolved working directory only when it is needed to explain `Not run`, scope ambiguity, or debugging details.
- Rule: In the normal review path, run azurerm-linter directly rather than through generated shell scripts or PowerShell wrapper scripts.
- Rule: Use a longer sync timeout for azurerm-linter than for the quick git inspection commands.
- Rule: Wait for the linter command to finish before classifying the linter section result.
- Rule: Do not classify the linter section as `Not run` merely because the initial wait window elapsed while the linter process was still executing.
- Rule: If the stderr-suppressed JSON-mode run does not produce valid stdout JSON or otherwise cannot be classified deterministically, rerun azurerm-linter once without stderr suppression to capture diagnostic text for classification.

### REVIEW-LINT-002C: Default to filtered mode first
- Rule: The preferred review-time lint pass is normal filtered JSON mode with shell-native stderr suppression: `azurerm-linter -output json` plus the active shell's null-device redirection for stderr.
- Rule: Do not default to `--no-filter`.
- Rule: Treat filtered mode as the primary run because it is faster and scoped to the current diff shape detected by the tool.
- Rule: Use stdout JSON as the authoritative structured source for `Version`, `Status`, `Run Scope`, `Issue Count`, `Summary`, and `### 🎯 **MUST FIX**` content whenever a valid JSON payload is present.
- Rule: Treat stderr as diagnostics only, and consult it only when the primary stdout-only JSON run must be rerun to classify `Not applicable` or `Not run` outcomes.

### REVIEW-LINT-002D: Treat filtered mode as the normal review baseline
- Rule: Normal review runs should rely on filtered azurerm-linter mode as the authoritative baseline.
- Rule: Do not add a `--no-filter` workaround pass for deletion-only diffs or `0` changed lines during ordinary review runs.
- Rule: If the user explicitly asks for broader package debt or manual no-filter validation, disclose that this is broader than the standard review scope.

### REVIEW-LINT-002E: Match linter invocation to the review type deterministically
- Rule: Local review should use a direct native filtered `azurerm-linter -output json` invocation without `--pr`.
- Rule: Committed review should use the direct native invocation `azurerm-linter --pr=<number> -output json` when a valid pull request number can be determined deterministically from explicit review context.
- Rule: Allowed PR number sources are:
  - the active pull request context, when available
  - the currently open or viewed pull request context, when available
  - an explicit PR number provided by the user or prompt invocation text
- Rule: Do not guess or invent a PR number from the branch name, diff text, commit messages, or other ambiguous signals.
- Rule: If committed review cannot determine a valid PR number, report the linter section as `Not run` with a concise summary that instructs the user to create a draft PR and run the review again.
- Rule: When the PR number was not provided explicitly in the committed review invocation, that summary should include an example of how to pass one, such as `/code-review-committed-changes PR 12345`.

### REVIEW-LINT-003: Allowed azurerm-linter section statuses
- Rule: The linter section must use exactly one of these statuses:
  - Issues found
  - No issues
  - Not applicable
  - Not run

### REVIEW-LINT-003A: Treat "no packages to analyze" as Not applicable when caused by zero changed files
- Rule: If azurerm-linter output shows that it found zero changed files or zero changed packages for the selected scope and then prints `Error: no packages to analyze`, classify the linter section as `Not applicable` rather than `Not run`.
- Rule: In this case, record the tool output in `Summary`, set `Issue Count` to `0` or `n/a`, and keep the `### 🎯 **MUST FIX**` section as `- None`.
- Rule: Do not treat this specific output shape as a tool failure requiring an install hint.

### REVIEW-LINT-003B: Treat flag and usage parse errors as Not run due to invocation error
- Rule: If azurerm-linter exits with a flag parsing or usage error such as `flag provided but not defined` and prints its usage help, classify the linter section as `Not run`.
- Rule: In this case, record the command error in `Summary`, keep the `### 🎯 **MUST FIX**` section as `- None`, and do not emit an install hint unless there is separate evidence that the binary is missing.
- Rule: When the corrected command form is deterministic from the prompt context, include that correction in `Summary`.

### REVIEW-LINT-003C: Prefer JSON payloads when available
- Rule: When azurerm-linter emits a valid JSON payload, treat that payload as the authoritative source for `Version`, `Status`, `Run Scope`, `Issue Count`, `Summary`, and `### 🎯 **MUST FIX**` content.
- Rule: Ignore human-readable preamble logs when a valid JSON payload is present, except when they are needed to explain a non-JSON failure.
- Rule: Extract the JSON object from the linter output even if log lines precede it.
- Rule: If `-output json` is unsupported by the installed binary and the tool reports a flag or usage parse error, classify the section as `Not run` rather than falling back to text scraping.
- Rule: If a valid JSON payload is present but its `version` field is missing, unparsable, or lower than `v0.2.0`, classify the section as `Not run` and state that JSON review mode requires `azurerm-linter v0.2.0` or newer.

### REVIEW-LINT-004: azurerm-linter findings are reported as issues
- Rule: When azurerm-linter reports findings for the executed linter scope, report them as issues.
- Rule: Do not downgrade, suppress, or reclassify azurerm-linter findings based on contributor guidance preferences.
- Rule: If the executed linter scope is broader or narrower than the reviewed diff, disclose that scope mismatch, but still report the linter findings found in the executed scope.
- Rule: azurerm-linter findings must not remain only inside the linter subsection; they must also be surfaced in the review's main `ISSUES` section.
- Rule: The linter subsection is the execution report. The main `ISSUES` section is where the actionable findings are enumerated.
- Rule: Actionable violation lines should appear in a separate `### 🎯 **MUST FIX**` section immediately after the `### 🧰 **AZURERM LINTER**` execution report.

### REVIEW-LINT-005: Report scope and failure reasons explicitly
- Rule: The linter section must state the scope it covered.
- Rule: The linter section should prioritize reviewer-facing results over raw execution mechanics.
- Rule: If the linter could not be executed or could not be scoped correctly, report Not run with the concrete reason.
- Rule: Do not silently omit the tool or imply that it passed when it was not run.
- Rule: When the local binary is missing or the section is reported as Not run for tool-availability reasons, include an install hint of the form:
  - Repo: [QixiaLu/azurerm-linter](https://github.com/QixiaLu/azurerm-linter)
  - Install: go install github.com/qixialu/azurerm-linter@latest
- Rule: When the section is `Not run` because the installed binary is older than `v0.2.0` or does not support `-output json`, the summary should explicitly say that review requires `azurerm-linter v0.2.0` or newer.
- Rule: Do not describe a WSL-prefixed or cross-shell-wrapped linter invocation as compliant review execution on Windows when the local binary is available natively.
- Rule: The linter section should describe the filtered run that powers the normal review flow.
- Rule: The `### 🧰 **AZURERM LINTER**` execution report should be limited to these reviewer-facing fields only:
  - Version
  - Status
  - Run Scope
  - Issue Count
  - Summary
- Rule: The normal review output should then include a separate `### 🎯 **MUST FIX**` section with the actionable lines.
- Rule: If a direct linter invocation cannot be interpreted deterministically, prefer `Not run` with a concise reason over creating extra execution scaffolding.

### REVIEW-LINT-005A: Structure the linter section from actual tool output
- Rule: When a valid JSON payload is present, capture `version` as the linter version and `summary.issue_count` as the issue count.
- Rule: When a valid JSON payload is absent, the tool's issue footer (`Found X issue(s)`) may be used as the issue count when present.
- Rule: Treat preamble and cleanup logs (for example auto-detected remote, worktree creation, changed package detection, loading packages, cleanup) as execution notes or summary material, not as findings.
- Rule: Treat only the violation lines as `### 🎯 **MUST FIX**` entries.
- Rule: If there are no linter violations, the `### 🎯 **MUST FIX**` section must contain exactly one bullet: `- None`.
- Rule: If there are one or more linter violations, the `### 🎯 **MUST FIX**` section must be introduced by that exact heading and then list one normalized violation per bullet, and must not collapse multiple violations into a single sentence.
- Rule: When a deterministic repo-relative file path and line number are available, each `### 🎯 **MUST FIX**` bullet should prefer the form `CHECKID [file:line](repo/relative/path#Lline): message`.
- Rule: In the linked form, the `file:line` token should be a single Markdown link so the visible shape matches other clickable file references in the review.
- Rule: When the basename is unambiguous within the current `### 🎯 **MUST FIX**` section, use `basename:line` as the link label.
- Rule: When the basename would be ambiguous within the current `### 🎯 **MUST FIX**` section, use `repo/relative/path:line` as both the link label and the link target label.
- Rule: If deterministic repo-relative path normalization is not possible, keep the fallback form `CHECKID path:line: message` rather than guessing.
- Rule: When a valid JSON payload is present, derive findings from `findings[]` rather than scraping text lines.
- Rule: When a JSON finding message repeats the check ID as a leading prefix (for example `AZBP010: ...`), remove that duplicate prefix when constructing the final `### 🎯 **MUST FIX**` bullet.
- Rule: When a valid JSON payload is present, derive reviewer-facing summary facts from JSON fields such as `version`, `summary.changed_files`, `summary.changed_lines`, `summary.issue_count`, `scope.mode`, and `scope.patterns` rather than from log lines.
- Rule: When filtered mode reports changed files but zero changed lines, preserve that fact in `Summary` as tool behavior, not as a trigger for a workaround pass.
- Rule: Omit low-value execution chatter such as current branch, upstream branch, merge-base, and raw loader mode from normal successful output unless it materially explains the result.
- Rule: On successful runs, prefer a concise execution report plus a separate `### 🎯 **MUST FIX**` section over field-by-field diagnostics.
- Rule: Build the normal linter subsection from the direct command output returned by the linter run.

### REVIEW-LINT-005C: Persist and inspect full linter output deterministically
- Rule: Do not create or persist temporary linter log files in the normal review path.
- Rule: Do not write generated helper scripts or log artifacts to the system temporary directory in the normal review path.
- Rule: If explicit debugging is requested later, any temporary artifacts must be clearly intentional and removed before the review run completes.

### REVIEW-LINT-005D: Do not claim absence without searching the full saved output
- Rule: Do not state that a specific rule or file was not reported by azurerm-linter unless the full saved output was searched for the relevant file path and-or rule ID.

### REVIEW-LINT-005B: Normalize finding lines when possible
- Rule: Each reported linter finding should preserve the check ID, file path, line number, and message from the tool output.
- Rule: When the tool runs in a temporary worktree and emits absolute temporary paths, convert them to repo-relative paths when this can be done deterministically.
- Rule: If deterministic path normalization is not possible, keep the raw path rather than guessing.

### REVIEW-LINT-006: Prefer exact review-scope linting
- Rule: The linter invocation should match the selected review scope as closely as possible.
- Rule: If exact scoping is not possible, disclose any broader or narrower scope in the linter section.

## Output semantics

### REVIEW-OUT-001: Reviews must be evidence-forward
- Rule: Findings should cite the affected file(s), behavior, and why the concern matters.
- Rule: Do not rely on generic labels without explanation.

### REVIEW-OUT-002: Hard-stop messages are prompt-owned
- Rule: No-changes messages and other humorous hard-stop text belong to the prompt, not the contract.
- Rule: The prompts may keep their pirate-style hard-stop messages without changing this contract.

### REVIEW-OUT-003: Missing evidence must be disclosed plainly
- Rule: When a conclusion cannot be proven, say so directly in the review rather than compensating with invented certainty.

### REVIEW-OUT-004: Normal review output must not include execution narration
- Rule: The normal review output must not include preambles, execution commentary, progress narration, or step-by-step status updates.
- Rule: Do not emit text such as `re-running the local audit`, `the scope is still`, `the review remains`, `I am finishing`, `I have reloaded`, or similar execution-process narration in user-visible review output.
- Rule: The normal review output should contain only the prompt-defined review headings and their content.

### REVIEW-OUT-005: Successful fresh runs must emit the full current template
- Rule: If the mandatory procedure succeeds for the selected review type, emit the full current prompt-defined review template.
- Rule: Do not short-circuit to a previous review, a delta-only summary, or wording such as `same findings as before` or `no change from the last review`.
- Rule: This applies even when the reviewed code, linter findings, or conclusions are unchanged from an earlier invocation.
- Rule: Current prompt/template/layout requirements are part of the output contract and must be honored on every successful fresh run.

<!-- REVIEW-CONTRACT-EOF -->
