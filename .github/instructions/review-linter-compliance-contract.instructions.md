---
description: "Shared azurerm-linter compliance contract used by /code-review-local-changes and /code-review-committed-changes."
---

# Review Linter Compliance Contract

This file is the single source of truth for `azurerm-linter` execution and reporting in this repository's generic code review workflows.

## Consumers

Two independent review workflows MUST follow this contract:

- Consumer: `.github/prompts/code-review-local-changes.prompt.md`
  - Role: Auditor
  - Requires EOF Load: yes
  - Goal: execute and classify `azurerm-linter` deterministically for local workspace reviews.
- Consumer: `.github/prompts/code-review-committed-changes.prompt.md`
  - Role: Auditor
  - Requires EOF Load: yes
  - Goal: execute and classify `azurerm-linter` deterministically for committed branch or PR reviews.

The prompts define when the linter step runs.
This contract defines how `azurerm-linter` is executed, classified, and serialized into the final review payload.

## Canonical sources of truth (precedence)

Use these sources with the following roles:

- The shared code review contract: `.github/instructions/code-review-compliance-contract.instructions.md`
  - Authoritative for fresh-run evidence rules, finding classification, handoff requirements, and final review integration.
- This contract: `.github/instructions/review-linter-compliance-contract.instructions.md`
  - Authoritative for `azurerm-linter` applicability, execution shape, status classification, and payload semantics.
- The presentation contract and presentation payload schema
  - Authoritative for how the linter payload is rendered into the final review body.
- Current-run `azurerm-linter` output
  - Authoritative for the actual linter result when a run completed and produced classifiable output.

Conflict resolution:

- This contract is authoritative for `azurerm-linter` execution, status mapping, and payload population.
- The shared code review contract remains authoritative for evidence rules, issue classification, handoff serialization, and final review output semantics.
- The presentation contract and presentation schema remain authoritative for final rendered section layout.
- If this contract would contradict a successfully completed current-run `azurerm-linter` payload about what the tool actually reported, the current-run tool output wins for that run's factual result.

## Rule IDs

Rules are identified by stable IDs so both review prompts can reference the same linter requirement set without drifting.

ID format:
- REVIEW-LINT-<NNN>

Area:
- LINT = `azurerm-linter` execution and reporting

## Evidence hierarchy

When a linter claim affects applicability, status, or reported findings, use this evidence order:

1. The completed current-run `azurerm-linter` output
2. The current review scope resolved by the active prompt
3. The shared code review contract
4. This contract

If evidence is missing for a linter claim that would change the status or reported findings, do not guess.

# Contract Rules

## azurerm-linter

### REVIEW-LINT-001: Include linter execution data in every review payload
- Rule: Both review prompts must populate linter execution data in the final review payload.
- Rule: That payload data must exist even when the tool is not applicable or cannot be run.

### REVIEW-LINT-002: Run azurerm-linter when the scoped changes include provider Go files
- Rule: If the reviewed change-set includes files under `internal/**/*.go` or `internal/**/*_test.go`, attempt azurerm-linter.
- Rule: If no such files are in scope, set the linter payload status to `Not applicable`.

### REVIEW-LINT-002A: Local installation is required for linter execution
- Rule: Review prompts should rely on a locally installed `azurerm-linter` binary.
- Rule: Treat `azurerm-linter` as a standalone locally installed CLI, not as a Go toolchain command.
- Rule: Do not fetch or execute `azurerm-linter` via `go run` from a remote module path during review.
- Rule: The minimum supported `azurerm-linter` version for review is `v0.2.0`.
- Rule: If the local binary is missing, older than `v0.2.0`, or the tool cannot be executed reliably, set the linter payload status to `Not run` and include a short install hint in the payload summary pointing to the upstream repository and the local install command.

### REVIEW-LINT-002B: Execute azurerm-linter from the git repo root
- Rule: Before running azurerm-linter, resolve the git repository root with `git rev-parse --show-toplevel`.
- Rule: Execute azurerm-linter from that repo root, not from an arbitrary subdirectory.
- Rule: Change to that resolved repo-root working directory before invoking the plain local CLI command.
- Rule: When the reviewed repository root is also the active workspace root, execute azurerm-linter from that workspace root.
- Rule: Do not execute azurerm-linter from a parent directory, sibling workspace folder, or any location outside the active reviewed workspace.
- Rule: Run the linter in the current platform's native shell environment using the plain local CLI invocation, and keep stdout clean for the primary JSON-mode run by redirecting stderr to the active shell's null device using native syntax such as PowerShell `2>$null`, POSIX `2>/dev/null`, or cmd.exe `2>nul`.
- Rule: Do not rewrite the command through another runtime environment or wrapper such as `wsl`, `wsl --cd`, `bash -lc`, `sh -lc`, `cmd /c`, or `powershell -Command`, and do not replace the direct invocation with generated scripts, composite wrapper lines, or inline variable-assignment wrappers.
- Rule: Use `run_in_terminal` in `mode: "sync"` for azurerm-linter without an explicit timeout so the tool can wait for natural completion in one blocking call.
- Rule: If that sync azurerm-linter call unexpectedly returns control with a live terminal ID or a runtime note that the command may still be running, treat that state as still blocked. Do not inspect partial terminal output, do not resume other review work, and do not emit user-visible commentary until the same linter run has completed and the linter payload can be classified.
- Rule: Do not kill, restart, or replace the active linter run, and do not launch a second azurerm-linter pass during normal review merely because the primary run did not yield valid stdout JSON.
- Rule: If the primary linter run does not produce a classifiable completed result, do not continue the review from file evidence alone; fail closed with `Not run` in the linter payload or hard-stop the review as the active prompt requires.

azurerm-linter execution-state decision table:

| Condition | Required action |
| --- | --- |
| In-scope provider Go files exist | Run one blocking sync `azurerm-linter` call |
| The sync linter call is still running | Stay blocked and do no unrelated review work |
| The sync linter call returns early with a live terminal ID or runtime note that it may still be running | Treat it as still blocked; do not query partial output |
| The completed run yields valid JSON findings | Classify from the completed JSON payload |
| The completed run deterministically reports zero findings | Classify as `No issues` |
| The completed run deterministically reports `no packages to analyze` for zero changed packages | Classify as `Not applicable` |
| The completed run deterministically reports a tool-availability or invocation problem | Classify as `Not run` |
| The completed run is still unclassifiable | Fail closed rather than continuing the review |

### REVIEW-LINT-002C: Default to filtered mode first
- Rule: The preferred review-time lint pass is normal filtered JSON mode with shell-native stderr suppression: `azurerm-linter -output json` plus the active shell's null-device redirection for stderr.
- Rule: Do not default to `--no-filter`.
- Rule: Treat filtered mode as the primary run because it is faster and scoped to the current diff shape detected by the tool.
- Rule: Use stdout JSON as the authoritative structured source for payload fields describing linter version, status, run scope, issue count, summary, and actionable findings whenever a valid JSON payload is present.
- Rule: Treat stderr as diagnostics only; do not trigger a second linter pass just to recover diagnostic text during normal review.
- Rule: Normal review runs should rely on filtered azurerm-linter mode as the authoritative baseline, and should not add a `--no-filter` workaround pass for deletion-only diffs or `0` changed lines during ordinary review runs.
- Rule: If the user explicitly asks for broader package debt or manual no-filter validation, disclose that this is broader than the standard review scope.

### REVIEW-LINT-002E: Match linter invocation to the review type deterministically
- Rule: Local review should use a direct native filtered `azurerm-linter -output json` invocation without `--pr`, plus shell-native stderr-to-null redirection so stdout isolates the JSON payload.
- Rule: Committed review should use the direct native invocation `azurerm-linter --pr=<number> -output json` when a valid pull request number can be determined deterministically from explicit review context, plus shell-native stderr-to-null redirection so stdout isolates the JSON payload.
- Rule: The shell-native stderr-to-null redirection must match the active shell and OS, such as PowerShell `2>$null`, POSIX shells `2>/dev/null`, or cmd.exe `2>nul`.
- Rule: Allowed PR number sources are:
  - the active pull request context, when available
  - the currently open or viewed pull request context, when available
  - an explicit PR number provided by the user or prompt invocation text
- Rule: Do not guess or invent a PR number from the branch name, diff text, commit messages, or other ambiguous signals.
- Rule: If explicit user-supplied PR context conflicts with environment PR context and there is no explicit user override, do not run the linter.
- Rule: If committed review cannot determine a valid PR number, report the linter payload as `Not run` with a concise summary that instructs the user to provide an explicit PR number or run the review from an active ready-for-review pull request context.
- Rule: When the PR number was not provided explicitly in the committed review invocation, that summary should include an example of how to pass one, such as `/code-review-committed-changes PR 12345`.

### REVIEW-LINT-003: Allowed azurerm-linter payload statuses
- Rule: The linter payload must use exactly one of these statuses:
  - Issues found
  - No issues
  - Not applicable
  - Not run

### REVIEW-LINT-003A: Treat "no packages to analyze" as Not applicable when caused by zero changed files
- Rule: If azurerm-linter output shows that it found zero changed files or zero changed packages for the selected scope and then prints `Error: no packages to analyze`, classify the linter payload as `Not applicable` rather than `Not run`.
- Rule: In this case, record the tool output in the payload summary, set the payload issue count to `0` or `n/a`, and keep the actionable-finding payload empty except for the explicit empty-state marker.
- Rule: Do not treat this specific output shape as a tool failure requiring an install hint.

### REVIEW-LINT-003B: Treat flag and usage parse errors as Not run due to invocation error
- Rule: If azurerm-linter exits with a flag parsing or usage error such as `flag provided but not defined` and prints its usage help, classify the linter payload as `Not run`.
- Rule: In this case, record the command error in the payload summary, keep the actionable-finding payload empty except for the explicit empty-state marker, and do not emit an install hint unless there is separate evidence that the binary is missing.
- Rule: When the corrected command form is deterministic from the prompt context, include that correction in the payload summary.

### REVIEW-LINT-003C: Prefer JSON payloads when available
- Rule: When azurerm-linter emits a valid JSON payload, treat that payload as the authoritative source for the linter payload object and actionable-finding entries.
- Rule: Ignore human-readable preamble logs when a valid JSON payload is present, except when they are needed to explain a non-JSON failure.
- Rule: Extract the JSON object from the linter output even if log lines precede it.
- Rule: If `-output json` is unsupported by the installed binary and the tool reports a flag or usage parse error, classify the linter payload as `Not run` rather than falling back to text scraping.
- Rule: If a valid JSON payload is present but its `version` field is missing, unparsable, or lower than `v0.2.0`, classify the linter payload as `Not run` and state in the payload summary that JSON review mode requires `azurerm-linter v0.2.0` or newer.

### REVIEW-LINT-003D: Only truly unclassifiable linter completion fails closed
- Rule: If the primary azurerm-linter run completes and deterministically reports findings, zero findings, or a known `Not applicable`/`Not run` shape, classify that completed result normally.
- Rule: Fail closed only when the primary azurerm-linter run completes but still does not produce a classifiable result for the required review flow.
- Rule: In that case, either report the linter payload as `Not run` with a concise reason from the completed run or hard-stop if the active prompt requires a classifiable linter result before review output.
- Rule: Do not replace missing linter classification with broader ad hoc file auditing or first-person narration about continuing anyway.

### REVIEW-LINT-003E: Completed zero-issue runs are valid classifications
- Rule: A completed azurerm-linter run that deterministically reports zero findings is a successful classifiable outcome, not a failure.
- Rule: In that case, use the `No issues` status in the linter payload and keep the actionable-finding payload as the explicit empty-state marker.
- Rule: Do not treat a completed zero-issue run as `Not run` merely because the tool found nothing to report.
- Rule: For filtered local or PR runs, `No issues` means only that the completed filtered linter run reported zero findings for its executed scope.
- Rule: Do not describe a zero-finding filtered run as proof that the reviewed file, package, change-set, or branch is issue-free outside the linter's filtered scope.

### REVIEW-LINT-004: azurerm-linter findings are reported as issues
- Rule: When azurerm-linter reports findings for the executed linter scope, report them as issues.
- Rule: Do not downgrade, suppress, or reclassify azurerm-linter findings based on contributor guidance preferences.
- Rule: If the executed linter scope is broader or narrower than the reviewed diff, disclose that scope mismatch, but still report the linter findings found in the executed scope.
- Rule: azurerm-linter findings must not remain only inside the linter execution payload; they must also be surfaced as review issues and actionable linter entries in the final payload.
- Rule: The linter payload is the execution report. The review issue set is where the blocking findings remain visible to downstream stages.
- Rule: A clean linter payload must not be used to dismiss or suppress independently evidenced review issues that were established outside the linter result.

### REVIEW-LINT-005: Populate scope and failure reasons explicitly
- Rule: The linter payload must state the scope it covered.
- Rule: The linter payload should prioritize reviewer-facing results over raw execution mechanics.
- Rule: If the linter could not be executed or could not be scoped correctly, report `Not run` with the concrete reason in the payload summary.
- Rule: Do not silently omit the tool or imply that it passed when it was not run.
- Rule: When the local binary is missing or the payload is reported as `Not run` for tool-availability reasons, include an install hint of the form:
  - Repo: [QixiaLu/azurerm-linter](https://github.com/QixiaLu/azurerm-linter)
  - Install: go install github.com/qixialu/azurerm-linter@latest
- Rule: When the payload is `Not run` because the installed binary is older than `v0.2.0` or does not support `-output json`, the summary should explicitly say that review requires `azurerm-linter v0.2.0` or newer.
- Rule: Do not describe a WSL-prefixed or cross-shell-wrapped linter invocation as compliant review execution on Windows when the local binary is available natively.
- Rule: The linter payload should describe the filtered run that powers the normal review flow.
- Rule: The linter payload should provide these reviewer-facing facts only:
  - Version
  - Status
  - Run Scope
  - Issue Count
  - Summary
- Rule: The actionable linter entries should be supplied separately from the linter report fields so presentation can render them in its own section.
- Rule: If a direct linter invocation cannot be interpreted deterministically, prefer `Not run` with a concise reason over creating extra execution scaffolding.

### REVIEW-LINT-005A: Populate the linter payload from actual tool output
- Rule: When a valid JSON payload is present, capture `version` as the linter version and `summary.issue_count` as the issue count.
- Rule: When a valid JSON payload is absent, the tool's issue footer (`Found X issue(s)`) may be used as the issue count when present.
- Rule: Treat preamble and cleanup logs (for example auto-detected remote, worktree creation, changed package detection, loading packages, cleanup) as execution notes or summary material, not as findings.
- Rule: Treat only the violation lines as actionable linter entries in the payload.
- Rule: If there are no linter violations, the actionable linter payload must contain exactly one explicit empty-state bullet: `- None`.
- Rule: If there are one or more linter violations, the actionable linter payload must list one normalized violation per entry and must not collapse multiple violations into a single sentence.
- Rule: When a deterministic repo-relative file path and line number are available, each actionable linter entry should prefer the form `CHECKID [file:line](repo/relative/path#Lline): message`.
- Rule: In the linked form, the `file:line` token should be a single Markdown link so the visible shape matches other clickable file references in the review.
- Rule: When the basename is unambiguous within the actionable linter payload, use `basename:line` as the link label.
- Rule: When the basename would be ambiguous within the actionable linter payload, use `repo/relative/path:line` as both the link label and the link target label.
- Rule: If deterministic repo-relative path normalization is not possible, keep the fallback form `CHECKID path:line: message` rather than guessing.
- Rule: When a valid JSON payload is present, derive actionable entries from `findings[]` rather than scraping text lines.
- Rule: When a JSON finding message repeats the check ID as a leading prefix (for example `AZBP010: ...`), remove that duplicate prefix when constructing the actionable linter entry.
- Rule: When a valid JSON payload is present, derive reviewer-facing summary facts from JSON fields such as `version`, `summary.changed_files`, `summary.changed_lines`, `summary.issue_count`, `scope.mode`, and `scope.patterns` rather than from log lines.
- Rule: When a filtered run reports package patterns, populate `Run Scope` with scope-qualified language such as `Filtered local scope over ` + the resolved package pattern list, or `Filtered PR scope over ` + the resolved package pattern list.
- Rule: Keep `Summary` focused on the linter result and counts from the filtered run; do not use `Summary` wording that implies the reviewed code generally has no issues beyond that linter scope.
- Rule: When filtered mode reports changed files but zero changed lines, preserve that fact in the payload summary as tool behavior, not as a trigger for a workaround pass.
- Rule: Omit low-value execution chatter such as current branch, upstream branch, merge-base, and raw loader mode from the normal payload unless it materially explains the result.
- Rule: Build the linter report payload from the direct command output returned by the linter run.

### REVIEW-LINT-005B: Normalize finding lines when possible
- Rule: Each reported linter finding should preserve the check ID, file path, line number, and message from the tool output.
- Rule: When the tool runs in a temporary worktree and emits absolute temporary paths, convert them to repo-relative paths when this can be done deterministically.
- Rule: If deterministic path normalization is not possible, keep the raw path rather than guessing.

### REVIEW-LINT-005C: Persist and inspect full linter output deterministically
- Rule: Do not create or persist temporary linter log files in the normal review path.
- Rule: Do not write generated helper scripts or log artifacts to the system temporary directory in the normal review path.
- Rule: If explicit debugging is requested later, any temporary artifacts must be clearly intentional and removed before the review run completes.

### REVIEW-LINT-005D: Do not claim absence without searching the full saved output
- Rule: Do not state that a specific rule or file was not reported by azurerm-linter unless the full saved output was searched for the relevant file path and-or rule ID.

### REVIEW-LINT-006: Prefer exact review-scope linting
- Rule: The linter invocation should match the selected review scope as closely as possible.
- Rule: If exact scoping is not possible, disclose any broader or narrower scope in the linter payload summary.

<!-- REVIEW-LINT-CONTRACT-EOF -->
