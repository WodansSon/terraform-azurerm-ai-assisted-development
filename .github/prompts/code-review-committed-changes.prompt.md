---
description: "Code review for committed changes using the shared review contract and a dedicated azurerm-linter section."
---

# 📋 Code Review - Committed Changes

# 🚫 EXECUTION GUARDRAILS (READ FIRST)

## Audit-only mode
This prompt is audit-only. Do not modify files. Do not propose or apply patches unless the user explicitly asks for fixes.
Do not run unit tests, acceptance tests, `go test`, `runTests`, or other test commands as part of the normal review flow unless the user explicitly asks for test execution.
Do not run helper scripts, ad hoc shell snippets, or terminal calculations for trivial deterministic checks such as string length, simple literal comparisons, or obvious regex-shape questions during normal review flow.
Do not invent or execute repo-local prerequisite scripts, validation wrappers, or guessed helper entrypoints unless they are explicitly named in this prompt, the shared contract, current workspace guidance, or the user's request.

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
Do not reuse, paraphrase, or summarize a previous review body, even if the reviewed diff and findings are unchanged.
If this invocation completes the mandatory procedure successfully, emit the full current review template defined by this prompt.
If the fresh-run requirements are not satisfied, hard-stop and output exactly this one line and nothing else:
  - `Cannot run code-review-committed-changes: fresh-run requirements not satisfied. Re-run the mandatory procedure from step 0 in this invocation.`

## Command authorization
The required read-only git commands and `azurerm-linter` commands in this prompt are already authorized by the prompt itself.
That authorization includes the mandatory branch and diff commands plus targeted follow-on read-only git inspection commands scoped to already identified in-scope files, such as `git diff -- <paths>` and `git show <rev>:<path>`.
Read-only shell-native HTTPS requests to the GitHub pull-request files endpoint are authorized when step 1 requires authoritative PR file scope for a deterministic PR number.
Read-only `gh api` pull-request metadata commands are authorized only when the user explicitly asks to use `gh`.
Execute the required review commands immediately when their step applies.
Do not stop to ask the user for confirmation before running them.
Do not emit a preamble that asks permission or waits for approval before running them.

## Determinism policy
- Follow the shared review contract, not stale prompt memory.
- Do not guess when evidence is missing.
- Do not present multiple alternative fixes unless the user explicitly asks for options.
- Do not output plans or TODO lists.
- Do not begin the normal review output until the audit is complete and the findings set is frozen.
- If you realize another read, verification step, or finding is needed while drafting, stop drafting silently, finish the audit, refreeze the findings set, and then emit one complete review body.
- Perform at least one additional silent completeness pass over the fully drafted review before emitting any user-visible output.
- Assemble the entire review in an internal buffer and emit it exactly once after that completeness pass succeeds.
- The only allowed normal output is the review template defined in this prompt, plus the Step 5 verification footer when one or more skills were actually used.
- Do not compare the current run to earlier runs in the conversation; state only the facts established in the current invocation.
- Do not short-circuit to wording such as `same findings as before`, `no change from the last review`, or other abbreviated carry-over summaries.

## Mandatory procedure

### 0) Load the shared review contract
- Read and apply `.github/instructions/code-review-compliance-contract.instructions.md` to EOF.
- EOF marker verification is mandatory: the last non-empty line must be `<!-- REVIEW-CONTRACT-EOF -->`.
- If the contract is not fully loaded, hard-stop and output exactly this one line and nothing else:
  - `Cannot run code-review-committed-changes: code review contract not fully loaded. Load .github/instructions/code-review-compliance-contract.instructions.md to EOF and re-run this prompt.`

### 0A) Load the review coverage matrix schema
- Read and apply `.github/instructions/review-coverage-matrix.schema.json` to EOF before Step 2A.
- If the schema is not fully loaded, hard-stop and output exactly this one line and nothing else:
  - `Cannot run code-review-committed-changes: review coverage matrix schema not fully loaded. Load .github/instructions/review-coverage-matrix.schema.json to EOF and re-run this prompt.`

### 1) Gather the committed change-set
Use GitHub-backed pull request tools for PR metadata and changed-file scope resolution whenever they can provide the authoritative PR payload.
Use `run_in_terminal` with `mode: "sync"`, a concrete `goal`, and a short `timeout` only for the required git commands in this step, targeted follow-on read-only git inspection commands on already identified in-scope files, the direct shell-native HTTPS PR-files request when the contract requires it, and `gh api` only when the user explicitly asks to use `gh`.
The commands in steps 1 and 4 must be executed again for each invocation of this prompt, even if they were executed earlier in the conversation.

Run this command first and do not repeat it:

```text
git branch --show-current
```

Determine committed review scope in this order:

- Apply `REVIEW-FILE-004` and `REVIEW-EVID-*` exactly when resolving PR scope, including the committed-review scope decision table in the shared contract.
- Treat explicit PR numbers and environment PR identifiers as deterministic inputs for GitHub-backed PR scope resolution.
- For an explicit PR number, first issue the preferred direct shell-native HTTPS request to `https://api.github.com/repos/<owner>/<repo>/pulls/<number>/files`, using pagination when needed and without relying on `gh`.
- Treat summary-only results, browser links, and forbidden spill or cache paths as insufficient for PR scope resolution; ignore them and continue with the next allowed GitHub-backed PR-files path.
- Treat tool-produced saved-output artifacts under user-profile or cache paths such as `AppData`, `workspaceStorage`, `chat-session-resources`, `content.json`, or `content.txt` as forbidden spill-file transports, not as authoritative PR-files payloads.
- Do not use `read_file` or shell commands against those saved-output artifacts to reconstruct PR scope.
- Do not auto-fallback to `gh api` for PR file retrieval. Use `gh` only when the user explicitly asks to use `gh`.
- If authoritative PR scope still cannot be resolved after the contract-defined retrieval paths are exhausted, hard-stop and output exactly this one line and nothing else:
  - `Cannot run code-review-committed-changes: authoritative PR scope could not be resolved from allowed local context, GitHub-backed review tools, or direct shell-native GitHub PR-files retrieval. Local spill files remain forbidden. Re-run with a branch-wide committed review if you want to skip PR-scoped resolution.`
- After PR scope is resolved, use repo-local evidence for per-file inspection unless the user explicitly requests remote-source verification.
- If explicit user-supplied PR context and environment PR context both exist, resolve them before continuing:
  - If they match, use that PR.
  - If they conflict, hard-stop and output exactly this one line and nothing else:
    - `☠️ Argh! Cannot sail the code-review-committed-changes sea, yer PR bearings be crossed. Environment PR be <environment_pr>, but ye supplied <supplied_pr>. Set a proper course and set sail with true bearings, or declare the supplied PR be takin’ command o’er the current course. ☠️`
  - Only if the user explicitly states that the supplied PR should override the active PR context may the supplied PR number win.
- Only if no authoritative pull request context exists, or when the user explicitly asks for a branch-wide committed review, run these commands in order and do not repeat them:

```text
git --no-pager diff --stat --no-prefix origin/main...HEAD
git --no-pager diff --no-prefix --unified=3 origin/main...HEAD
```

Rules:
- Apply `REVIEW-FILE-001` through `REVIEW-FILE-005` and `REVIEW-EVID-*` exactly rather than restating those rules from memory.
- If the authoritative committed review scope is empty, hard-stop and output exactly:
  - `☠️ Argh! Shiver me source files! This branch be cleaner than a swabbed deck! Push some code, Ye Lily-livered scallywag! ☠️`
- If the committed review scope is large, inspect the changed files individually rather than rerunning broader scope commands.
- If additional commit-by-commit context is genuinely needed after reviewing the committed review scope, inspect the relevant commit(s) individually instead of making commit history a mandatory first step.

### 2) Classify files accurately
- Parse the diff stat carefully so added, modified, and deleted files are counted correctly.
- Do not silently skip files that belong to the committed review scope.
- Identify files under `vendor/**`, exclude them from actionable review targets, and report only the skipped vendored-file count per `REVIEW-FILE-005`.

### 2A) Build a deterministic coverage plan
- Invoke the `review-coordinator` skill (`.github/skills/review-coordinator/SKILL.md`), read it to EOF, and have it apply the shared contract's `REVIEW-COORD-*` rules to build the current-run coverage matrix before standards loading or finding drafting.
- The coverage matrix must have a structured internal representation that conforms to `.github/instructions/review-coverage-matrix.schema.json`.
- The coverage matrix must enumerate changed implementation files in fixed lexical order, the required lifecycle/control windows for each applicable surface, required overlap surfaces for any brand-new resource, and the mandatory provider issue-class checks for the change-set.
- For changed implementation files under `internal/**/*.go`, inspect applicable windows in this fixed order: `Importer`, `Create`, `Read`, `Update`, `Delete`, `CustomizeDiff`, explicit validation or mode or ownership helpers, then companion registration, tests, docs, and association surfaces when applicable.
- When the review scope adds a brand-new resource under `internal/**/*.go`, add overlapping sibling surfaces that can manage the same remote object, existing data sources or list resources that expose the same remote object shape, route or association or referencing surfaces, and explicit mode or ownership validation helpers to the same deterministic matrix even when those files are unchanged.
- For each unchanged overlap surface added by Step 2A, materialize an explicit coverage row by file path in the structured matrix rather than recording only a category-level note.
- The active editor file, search result ordering, and PR wording must not change the initial coverage order.
- Step 2A is the build phase only: construct the structured matrix and perform the fixed-order control-window routing before findings are drafted.
- Do not draft findings or start any routed role from this build phase alone; standards-dependent completion validation happens later in Step 3A.
- Observable proof requirement: when this step runs, `review-coordinator` is an actually-used skill, so the verification footer MUST include a `Skill used: review-coordinator` line before any later routed-skill entries.
- If the `review-coordinator` skill cannot be loaded to EOF, hard-stop and output exactly this one line and nothing else:
  - `Cannot run code-review-committed-changes: review-coordinator skill not fully loaded. Load .github/skills/review-coordinator/SKILL.md to EOF and re-run this prompt.`

### 3) Load applicable workspace standards
- Discover repo-level contributor guidance in the current workspace before reading it.
- Check `CONTRIBUTING.md` and `contributing/README.md`, then read the applicable file(s) that exist.
- When reviewing a `terraform-provider-azurerm` style workspace, treat `contributing/README.md` as the repo-level contributor guide when present.
- Read `.github/pull_request_template.md` when present.
- Read any file-scoped instructions or skills that directly govern the changed files.
- When `internal/**/*.go` or `internal/**/*_test.go` files are in scope, load the implementation and testing instruction set required by `REVIEW-SCOPE-005` before classifying findings.
- If the review scope includes `website/docs/**/*.html.markdown`, also read `.github/instructions/docs-compliance-contract.instructions.md` and `.github/instructions/documentation-guidelines.instructions.md`, and apply `DOCS-*` rules only to those docs files.
- When `website/docs/**/*.html.markdown` files are in scope, audit those docs files using the docs contract instead of generic schema-parity assumptions.
- For docs files in committed review scope, treat `DOCS-DEPR-*` as authoritative for next-major deprecations: legacy non-vNext fields may be intentionally removed from live reference docs and moved to versioned upgrade guides.
- Do not raise an Issue solely because a legacy field still exists on a non-vNext implementation path when the docs contract and docs guidance classify that field as legacy-only and require it to stay out of current reference docs.
- For docs files in committed review scope, every docs Issue must cite at least one exact `DOCS-*` rule ID that supports the claim.
- If no exact `DOCS-*` rule supports a proposed docs Issue, demote it to an Observation or omit it.
- If provider contributor guidance exists in the current workspace or is explicitly fetched as evidence, apply it only where relevant.
- Use the precedence rules from the shared review contract.

### 3A) Validate deterministic coverage matrix completion
- Invoke the validation sub-phase of the already-loaded `review-coordinator` skill, using the already-loaded `.github/instructions/review-coverage-matrix.schema.json`, to validate matrix completion after Step 3 has loaded the applicable workspace standards and scoped guidance.
- Complete the standards-dependent issue-class checks that require loaded contributor guidance, implementation guidance, testing guidance, or docs-contract guidance.
- Validate that every required row exists, every required lifecycle/control window is present in `completedWindows` or `notApplicableWindows`, every required issue class is present in `completedIssueClasses` or `notApplicableIssueClasses`, every top-level required issue class is present in `completedIssueClasses` or `notApplicableIssueClasses`, and every unchanged overlap surface remains materialized as an explicit file-path row.
- Do not proceed to findings or any routed role until the Step 3A validation phase has marked the structured coverage matrix complete.
- If the structured coverage matrix is incomplete after Step 3A validation, hard-stop and output exactly this one line and nothing else:
  - `Cannot run code-review-committed-changes: deterministic coverage matrix not complete after standards loading. Complete the required review-coordinator rows and re-run this prompt.`

### 4) Run azurerm-linter when applicable
- If the committed change-set includes files under `internal/**/*.go` or `internal/**/*_test.go`, attempt azurerm-linter and report it in its own section.
- When this step applies, execute the required repo-root and linter commands directly; do not pause for confirmation.
- Apply `REVIEW-LINT-002*` through `REVIEW-LINT-005` exactly for linter execution, blocking behavior, and classification, including the azurerm-linter execution-state decision table in the shared contract.
- Use one blocking sync linter run with no timeout, stay blocked until the completed result is classifiable, and do not do unrelated review work or user-visible narration while that run is outstanding.
- Resolve the git repo root with `git rev-parse --show-toplevel`, change to that working directory in a separate command, and run the plain local CLI invocation from there.
- Determine the PR number exactly as required by `REVIEW-LINT-002E`; do not guess or invent one.
- If a valid PR number is available, run `azurerm-linter --pr=<number> -output json` with shell-native stderr suppression.
- Do not add wrapper-shell rewrites, composite wrapper lines, inline variable wrappers, helper scripts, `--no-filter` workaround passes, or second linter runs in the normal review path.
- If no in-scope provider Go files exist, mark the linter section as `Not applicable`.
- Classify applicability, failures, JSON requirements, and `AZURERM LINTER` output shape exactly as required by `REVIEW-LINT-003*`, `REVIEW-LINT-004`, and `REVIEW-LINT-005`.

### 5) Produce the review output
- Review the full committed change-set.
- Complete the deterministic coverage matrix built in Step 2A and validated in Step 3A before drafting or freezing findings.
- Findings must follow the shared review contract, including `REVIEW-EVID-*`, `REVIEW-CLASS-*`, and `REVIEW-LINT-*` behavior.
- When multiple mandatory issue-class checks uncover distinct evidence-backed concerns, preserve each concern as its own schema-conformant intermediate record; do not stop after the first blocking defect and do not treat one concern as satisfying another required issue class.
- When a mandatory issue-class check yields an evidence-backed non-blocking concern, keep it in `OBSERVATIONS`; do not drop it solely because another issue already blocks merge or because it does not change the final verdict.
- Apply the file-type coverage rules from `REVIEW-SCOPE-*` so installer/script, AI customization, manifest, and user-visible content checks are not skipped.
- Treat vendored files under `vendor/**` as skipped non-actionable files: report only the skipped vendored-file count, and do not raise Issues that require directly editing vendored content.
- When the selected committed diff is vendored-only or vendored-heavy, say so explicitly in the summary or notes so sparse actionable findings are easy to interpret.
- When `website/docs/**/*.html.markdown` files are in scope, explicitly apply the docs contract's deprecation and upgrade-guide rules before raising docs Issues about removed legacy fields.
- When `website/docs/**/*.html.markdown` files are in scope, any docs Issue in the review body must include the exact supporting `DOCS-*` rule ID or IDs.
- Do not emit generic docs-parity Issues for `website/docs/**/*.html.markdown` files without exact `DOCS-*` rule support and evidence.
- When `internal/**/*.go` scope adds a brand-new resource, explicitly inspect whether the required companion artifacts from the implementation and testing guidance are present: Resource Identity, list resource, list-resource query tests, and list-resource docs.
- For singleton or get-only new resources, including singleton child resources whose SDK package may still expose list methods, apply the shared contract's exception-aware list-review rule instead of emitting a generic missing-list-resource finding.
- When the change adds a new `*_ephemeral.go` implementation, explicitly inspect whether the required companion artifacts are present: `EphemeralResources()` registration, docs under `website/docs/ephemeral-resources/`, and Terraform 1.10-gated tests under `*_ephemeral_test.go`.
- When the change adds a new provider-defined function under `internal/provider/function/`, explicitly inspect whether the required companion artifacts are present: docs under `website/docs/functions/` and Terraform 1.8-gated tests under `internal/provider/function/*_test.go`.
- When `internal/**/*_test.go` files are in scope, explicitly inspect embedded Terraform configuration strings and apply the `REVIEW-TEST-*` rules for formatting drift instead of assuming `azurerm-linter` will catch those issues.
- Keep the review concise but complete.
- Before any routed role runs, keep the working findings set as internal intermediate records that satisfy `REVIEW-HANDOFF-*` and conform to `.github/instructions/review-workflow-handoff.schema.json`; do not let routed roles exchange free-form unlabeled prose.
- Before writing the first `#` of the review output, silently iterate on the drafted review until the findings set is final and no additional findings, evidence corrections, or template fixes are needed.
- Buffer the full review body internally and emit it once only after that silent iteration completes.
- If one or more workflow skills were actually loaded and used during the review, append a verification footer after `## 🏆 **OVERALL ASSESSMENT**` and after no other text.
- The verification footer must contain `Preflight complete: yes` followed by one `Skill used: <name>` line for each actually used skill, in first-use order.
- Do not emit a verification footer when no skill was actually used during the review.
- Do not infer a skill from file type alone or from loading contracts or instruction files; emit `Skill used:` lines only for skills that were actually loaded and used.
- If `Repo Guidance` states that a skill was loaded or used, the verification footer must include the matching `Skill used:` line.
- Do not emit any text after the verification footer.
- After the normal review output begins, do not add second-pass findings, self-corrections, or review-amendment text; restart the silent audit instead if more verification is needed.

### 5A) Architect evaluation (internal design-direction pass)
- This step is mandatory after Step 5 has gathered the change-set evidence, even when the primary review pass is otherwise about to conclude with no candidate Issues.
- Do not start this step unless the structured coverage matrix validated in Step 3A is complete.
- Invoke the `review-architect` skill (`.github/skills/review-architect/SKILL.md`), read it to EOF, and have it load and apply `.github/instructions/review-architect-compliance-contract.instructions.md` (the `REVIEW-ARCH-*` rules) to evaluate structural fit, naming direction, and maintainability.
- Any architect finding added at this step must be represented as a `REVIEW-HANDOFF-*` intermediate record that conforms to `.github/instructions/review-workflow-handoff.schema.json`, with `status` set to `observation` or `candidate` as appropriate.
- This is prompt-governed workflow machinery for the single-workflow design. It may add Observations or mandatory-source-backed candidate Issues, but it must not emit its own section, freeze outcomes, or change the final review template.
- Treat this execution order as a determinism choice owned by the prompt, not as an authority ranking between roles.
- Observable proof requirement: when this step runs, `review-architect` is an actually-used skill, so the Step 5 verification footer MUST include a `Skill used: review-architect` line before any later routed-skill entries.
- If the `review-architect` skill or its contract cannot be loaded to EOF, hard-stop and output exactly this one line and nothing else:
  - `Cannot run code-review-committed-changes: review-architect skill or contract not fully loaded. Load .github/skills/review-architect/SKILL.md and .github/instructions/review-architect-compliance-contract.instructions.md to EOF and re-run this prompt.`

### 5B) Skeptic evaluation (internal adversarial pass)
- This step is mandatory after the architect pass has completed and before the advocate pass, even when the primary review pass is otherwise about to conclude with no candidate Issues.
- Do not start this step unless the structured coverage matrix validated in Step 3A is complete.
- Invoke the `review-skeptic` skill (`.github/skills/review-skeptic/SKILL.md`), read it to EOF, and have it load and apply `.github/instructions/review-skeptic-compliance-contract.instructions.md` (the `REVIEW-SKEP-*` rules) to attack the diff for missed defects and weakly-supported reasoning.
- Any skeptic finding added or strengthened at this step must use the same schema-backed `REVIEW-HANDOFF-*` intermediate record shape; enrich existing records when the concern already exists.
- This is prompt-governed workflow machinery for the single-workflow design. It may add net-new candidate Issues or strengthen existing candidates with new evidence, but it must not emit its own section, freeze outcomes, or change the final review template.
- Observable proof requirement: when this step runs, `review-skeptic` is an actually-used skill, so the Step 5 verification footer MUST include a `Skill used: review-skeptic` line before any later adjudication or moderation entries.
- If the `review-skeptic` skill or its contract cannot be loaded to EOF, hard-stop and output exactly this one line and nothing else:
  - `Cannot run code-review-committed-changes: review-skeptic skill or contract not fully loaded. Load .github/skills/review-skeptic/SKILL.md and .github/instructions/review-skeptic-compliance-contract.instructions.md to EOF and re-run this prompt.`

### 6) Advocate adjudication gate (binding: advocate)
- This step is mandatory whenever Step 5 or any routed intermediate pass produced one or more candidate Issues; it must not be skipped, summarized, deferred, or simulated.
- Do not start this step unless the structured coverage matrix validated in Step 3A is complete.
- The candidate-level false-positive-defense and status-adjudication gate for this workflow is `review-advocate`.
- Invoke the `review-advocate` skill (`.github/skills/review-advocate/SKILL.md`), read it to EOF, and have it load and apply `.github/instructions/review-advocate-compliance-contract.instructions.md` (the `REVIEW-ADV-*` rules) to challenge each candidate Issue.
- Consume only schema-conformant `REVIEW-HANDOFF-*` intermediate records whose `status` is `candidate`, preserve the other handoff fields, and update `status` to `confirmed`, `downgraded`, or `dismissed` per `REVIEW-ADV-005`.
- Resolve every candidate Issue from the primary review pass and the routed architect and skeptic passes to exactly one deterministic outcome (`Confirmed`, `Downgraded`, or `Dismissed`) per `REVIEW-ADV-005`, then hand the adjudicated workflow record set to final moderation.
- Do not add a separate advocate-adjudication section to the review body; this routed gate is invisible machinery that only adjusts record status and downstream landing behavior per the routed contract.
- Observable proof requirement: when this step runs, `review-advocate` is an actually-used skill, so the Step 5 verification footer MUST include a `Skill used: review-advocate` line before the final `Skill used: review-moderator` entry when moderation also runs.
- If the `review-advocate` skill or its contract cannot be loaded to EOF, hard-stop and output exactly this one line and nothing else:
  - `Cannot run code-review-committed-changes: review-advocate skill or contract not fully loaded. Load .github/skills/review-advocate/SKILL.md and .github/instructions/review-advocate-compliance-contract.instructions.md to EOF and re-run this prompt.`
- If the primary review pass plus the routed architect and skeptic passes produced no candidate Issues, skip this step and do not emit the `Skill used: review-advocate` marker.

### 7) Final moderation owner (binding: moderator)
- This step is mandatory on every normal successful review path after Step 5 and any routed adjudication steps; it must not be skipped, summarized, deferred, or simulated.
- Do not start this step unless the structured coverage matrix validated in Step 3A is complete.
- The final moderation owner for this workflow is `review-moderator`.
- Invoke the `review-moderator` skill (`.github/skills/review-moderator/SKILL.md`), read it to EOF, and have it load and apply `.github/instructions/review-moderator-compliance-contract.instructions.md` (the `REVIEW-MOD-*` rules) to merge duplicates, normalize surviving records, and produce the final moderated finding set for presentation.
- Consume the schema-conformant `REVIEW-HANDOFF-*` intermediate record set for the run, including the explicit empty-record-set case, preserve record identity and status semantics when records exist, and use moderation only for duplicate merge, wording normalization, severity normalization, and final visible-set selection.
- Freeze the review findings set only after the moderator pass completes.
- Do not add a separate final-moderation section to the review body; the moderator binding is invisible machinery that only determines the final visible `ISSUES` and `OBSERVATIONS` set per the routed contract.
- Observable proof requirement: because this step now runs on every normal successful routed review path, `review-moderator` is an actually-used skill and the Step 5 verification footer MUST include a `Skill used: review-moderator` line. Because the moderator pass runs last, that line MUST be the final `Skill used:` entry and the last non-empty line of the response.
- If the `review-moderator` skill or its contract cannot be loaded to EOF, hard-stop and output exactly this one line and nothing else:
  - `Cannot run code-review-committed-changes: review-moderator skill or contract not fully loaded. Load .github/skills/review-moderator/SKILL.md and .github/instructions/review-moderator-compliance-contract.instructions.md to EOF and re-run this prompt.`
- If earlier steps produced no schema-conformant intermediate findings, invoke moderator with an explicit empty record set and freeze a deterministic zero-findings result instead of skipping this step.

### 8) Final presentation renderer
- This step is mandatory on the normal successful review path after the findings set is frozen; it must not be skipped, summarized, deferred, or simulated.
- Build a presentation payload that conforms to `.github/instructions/review-presentation-input.schema.json`.
- For committed review, populate at minimum: `reviewMode=committed`, `changeDescription`, `changeSummaryLines`, `modifiedFiles`, `addedFiles`, `deletedFiles`, `skippedVendoredFiles`, `primaryChangesAnalysis`, `recursionPreventionLines`, `standardsCheckLines`, `linterLines`, `mustFix`, `strengths`, `observations`, `issues`, `immediateRecommendations`, `futureConsiderations`, `overallAssessment`, and optional `verificationFooter`.
- When populating `modifiedFiles`, `addedFiles`, `deletedFiles`, and any file-bearing structured findings, use PR-scoped or repo-scoped paths or path-plus-line references only.
- Do not place editor-local, spill-path, or absolute-disk links into the payload, including `vscode-file://`, `vscode://`, `file://`, `workbench.html`, `AppData`, `workspaceStorage`, `C:\`, or `/Users/` references.
- When authoritative PR scope is available, keep file references PR-scoped or repo-scoped instead of converting them to local editor links or absolute disk paths.
- For `mustFix`, supply normalized actionable linter lines or the explicit empty-state bullet `- None`.
- For `strengths`, `observations`, `issues`, `immediateRecommendations`, and `futureConsiderations`, use structured finding objects from the schema only when the final moderated finding already carries deterministic `presentation` hints or when the corresponding display fields are otherwise already frozen by the shared workflow record.
- Treat the moderator-owned `presentation` object on surviving moderated handoff records as the canonical source for rich-display semantics.
- Do not derive or invent `reviewType`, `suggestedChange`, `currentCode`, `correctedCode`, `codeLanguage`, or any other rich-display semantics in this prompt.
- Invoke the `review-presentation` skill (`.github/skills/review-presentation/SKILL.md`), read it to EOF, and have it load and apply `.github/instructions/review-presentation-compliance-contract.instructions.md` together with `.github/instructions/review-presentation-input.schema.json` to render the final review body.
- The presentation skill is render-only. It must not change findings, severity, classification, recommendations, or verdict semantics.
- The presentation skill owns the normal successful review body. After this step begins, emit exactly the rendered review body and nothing else.
- When `verificationFooter` is present, preserve the supplied routed-skill order and do not add `review-presentation` to `skillsUsed`.
- If the `review-presentation` skill, contract, or schema cannot be loaded to EOF, hard-stop and output exactly this one line and nothing else:
  - `Cannot run code-review-committed-changes: review-presentation skill, contract, or schema not fully loaded. Load .github/skills/review-presentation/SKILL.md, .github/instructions/review-presentation-compliance-contract.instructions.md, and .github/instructions/review-presentation-input.schema.json to EOF and re-run this prompt.`

## Output format

- On the normal successful path, the final review body is owned by Step 8's `review-presentation` renderer.
- Do not duplicate or override that template in this prompt.
- Prompt-owned hard-stop messages remain prompt-owned.
