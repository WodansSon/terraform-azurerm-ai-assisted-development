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

### 0) Load the shared review contracts
- Read and apply `.github/instructions/code-review-compliance-contract.instructions.md` to EOF.
- Read and apply `.github/instructions/review-linter-compliance-contract.instructions.md` to EOF.
- EOF marker verification is mandatory for both contracts:
  - `.github/instructions/code-review-compliance-contract.instructions.md` -> `<!-- REVIEW-CONTRACT-EOF -->`
  - `.github/instructions/review-linter-compliance-contract.instructions.md` -> `<!-- REVIEW-LINT-CONTRACT-EOF -->`
- If either contract is not fully loaded, hard-stop and output exactly this one line and nothing else:
  - `Cannot run code-review-committed-changes: review contracts not fully loaded. Load .github/instructions/code-review-compliance-contract.instructions.md and .github/instructions/review-linter-compliance-contract.instructions.md to EOF and re-run this prompt.`

### 0A) Load the review coverage matrix schema
- Read and apply `.github/instructions/review-coverage-matrix.schema.json` to EOF before Step 2A.
- If the schema is not fully loaded, hard-stop and output exactly this one line and nothing else:
  - `Cannot run code-review-committed-changes: review coverage matrix schema not fully loaded. Load .github/instructions/review-coverage-matrix.schema.json to EOF and re-run this prompt.`

### 0B) Load routed workflow and final presentation prerequisites
- Before Step 1 begins, explicitly load each routed workflow skill and contract that the normal successful review path may require:
  - `.github/skills/review-coordinator/SKILL.md`
  - `.github/skills/review-architect/SKILL.md`
  - `.github/instructions/review-architect-compliance-contract.instructions.md`
  - `.github/skills/review-skeptic/SKILL.md`
  - `.github/instructions/review-skeptic-compliance-contract.instructions.md`
  - `.github/skills/review-advocate/SKILL.md`
  - `.github/instructions/review-advocate-compliance-contract.instructions.md`
  - `.github/skills/review-moderator/SKILL.md`
  - `.github/instructions/review-moderator-compliance-contract.instructions.md`
  - `.github/skills/review-presentation/SKILL.md`
  - `.github/instructions/review-presentation-compliance-contract.instructions.md`
  - `.github/instructions/review-presentation-input.schema.json`
- For routed workflow skill files in this step, EOF marker verification is mandatory. The last non-empty line must be the matching skill EOF marker comment:
  - `.github/skills/review-coordinator/SKILL.md` -> `<!-- REVIEW-COORD-SKILL-EOF -->`
  - `.github/skills/review-architect/SKILL.md` -> `<!-- REVIEW-ARCH-SKILL-EOF -->`
  - `.github/skills/review-skeptic/SKILL.md` -> `<!-- REVIEW-SKEP-SKILL-EOF -->`
  - `.github/skills/review-advocate/SKILL.md` -> `<!-- REVIEW-ADV-SKILL-EOF -->`
  - `.github/skills/review-moderator/SKILL.md` -> `<!-- REVIEW-MOD-SKILL-EOF -->`
  - `.github/skills/review-presentation/SKILL.md` -> `<!-- REVIEW-PRESENT-SKILL-EOF -->`
- The presentation schema file `.github/instructions/review-presentation-input.schema.json` does not use a Markdown EOF marker; verify that it is readable end-to-end in the current run.
- Do not defer routed-skill, routed-contract, or presentation-path availability checks until after findings are drafted or frozen.
- If any routed workflow skill, routed contract, presentation contract, or presentation schema cannot be loaded to EOF in this preflight phase, hard-stop and output exactly this one line and nothing else:
  - `Cannot run code-review-committed-changes: the routed review workflow is incomplete or stale in this workspace. Refresh the AI toolkit files, then confirm these exact files are present and readable end-to-end: .github/skills/review-coordinator/SKILL.md; .github/skills/review-architect/SKILL.md; .github/instructions/review-architect-compliance-contract.instructions.md; .github/skills/review-skeptic/SKILL.md; .github/instructions/review-skeptic-compliance-contract.instructions.md; .github/skills/review-advocate/SKILL.md; .github/instructions/review-advocate-compliance-contract.instructions.md; .github/skills/review-moderator/SKILL.md; .github/instructions/review-moderator-compliance-contract.instructions.md; .github/skills/review-presentation/SKILL.md; .github/instructions/review-presentation-compliance-contract.instructions.md; .github/instructions/review-presentation-input.schema.json.`

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
- Use a JSON-returning request shape for that HTTPS call, for example a shell-native REST request that yields JSON directly rather than formatted response text.
- If the authoritative response is too large for comfortable inline transport, reduce it in-process to the scope fields you actually need or write a current-run transient JSON artifact from that already-authoritative response; do not try to parse terminal spill banners or other wrapper text as JSON.
- Treat summary-only results, browser links, and forbidden spill or cache paths as insufficient for initial PR scope resolution; ignore them and continue with the next allowed GitHub-backed PR-files path.
- Treat tool-produced saved-output artifacts under user-profile or cache paths such as `AppData`, `workspaceStorage`, `chat-session-resources`, `content.json`, or `content.txt` as forbidden spill-file transports when they are being offered as the initial authoritative PR-files payload.
- Do not use `read_file` or shell commands against pre-existing or tool-spilled local artifacts to reconstruct authoritative PR scope. After authoritative PR scope is already established from an allowed source, the current run may generate a transient local transport artifact from that already-authoritative dataset when size or tool-shape limits require it.
- Do not auto-fallback to `gh api` for PR file retrieval. Use `gh` only when the user explicitly asks to use `gh`.
- If authoritative PR scope still cannot be resolved after the contract-defined retrieval paths are exhausted, hard-stop and output exactly this one line and nothing else:
  - `Cannot run code-review-committed-changes: authoritative PR scope could not be resolved from allowed local context, GitHub-backed review tools, or direct shell-native GitHub PR-files retrieval. Pre-authority local spill files remain forbidden. Re-run with a branch-wide committed review if you want to skip PR-scoped resolution.`
- After PR scope is resolved, use repo-local evidence for per-file inspection unless the user explicitly requests remote-source verification.
- Before Step 2A begins, verify that every non-deleted scoped file required for deterministic review coverage is inspectable from repo-local committed evidence.
- If authoritative PR scope includes a non-deleted changed file that is missing from the local committed checkout or otherwise not inspectable from repo-local committed evidence, hard-stop and output exactly this one line and nothing else:
  - `Cannot run code-review-committed-changes: authoritative PR scope includes non-deleted changed files that are missing from the local committed checkout. Sync the local branch to the reviewed PR commit set and re-run this prompt.`
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
- When `internal/**/*_test.go` files are in scope, also read `.github/instructions/testing-compliance-contract.instructions.md` and `.github/instructions/testing-guidelines.instructions.md`, and apply exact `TEST-*` rules to those test files.
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
- Apply the linter contract exactly for applicability, repo-root resolution, PR-scope resolution, committed-review invocation shape, blocking behavior, classification, and payload population.
- If no in-scope provider Go files exist, mark the linter section as `Not applicable`.
- Do not restate or improvise linter execution rules beyond what the linter contract already defines.

### 5) Primary reviewer pass (binding: review-reviewer)
- This step is mandatory after Step 3A has validated the coverage matrix and after Step 4 has handled the linter path when applicable.
- Invoke the `review-reviewer` skill (`.github/skills/review-reviewer/SKILL.md`), read it to EOF, and have it load and apply `.github/instructions/code-review-compliance-contract.instructions.md` plus the already-loaded docs, testing, and other scoped guidance relevant to the current run.
- The `review-reviewer` skill owns full change-set inspection, mandatory issue-class execution, `REVIEW-COORD-003A` first-pass ownership and lifecycle handling where applicable, immediate `REVIEW-HANDOFF-006A` emission, and linkage-state maintenance for the primary review pass.
- The prompt owns only stage order, hard-stop strings, routed-role invocation, and final output orchestration; it must not restate the primary review method beyond routing this skill.
- Observable proof requirement: when this step runs, `review-reviewer` is an actually-used skill, so the verification footer MUST include a `Skill used: review-reviewer` line before any later routed-skill entries.
- If the `review-reviewer` skill cannot be loaded to EOF, hard-stop and output exactly this one line and nothing else:
  - `Cannot run code-review-committed-changes: review-reviewer skill not fully loaded. Load .github/skills/review-reviewer/SKILL.md to EOF and re-run this prompt.`
- On every normal successful routed review path, append a verification footer after `## 🏆 **OVERALL ASSESSMENT**` and after no other text.
- The verification footer must contain `Preflight complete: yes` followed by one `Skill used: <name>` line for each actually used routed review skill, in canonical routed stage order.
- Do not infer a skill from file type alone or from loading contracts or instruction files; emit `Skill used:` lines only for skills that were actually loaded and used.
- If `Repo Guidance` states that a skill was loaded or used, the verification footer must include the matching `Skill used:` line.
- Maintain a current-run routed-stage execution ledger through Steps 2A-8.
- For the normal successful routed path, `requiredStages` must be exactly `review-coordinator`, `review-reviewer`, `review-architect`, `review-skeptic`, `review-advocate`, `review-moderator`, `review-presentation`, in that order.
- Do not emit any text after the verification footer.
- After the normal review output begins, do not add second-pass findings, self-corrections, or review-amendment text; restart the silent audit instead if more verification is needed.
- Before Step 5A begins, invoke the post-review linkage-validation sub-phase required by `REVIEW-COORD-006B` over the frozen current-run findings set and the structured coverage matrix.
- Treat that router-owned linkage-validation sub-phase as the contract-defined backstop over already-emitted state, not as prompt-local bookkeeping or permission to postpone emission until the end of Step 5.
- If that router-owned linkage-validation sub-phase fails, hard-stop and output exactly this one line and nothing else:
  - `Cannot run code-review-committed-changes: reviewer discovered evidence-backed concerns that were not serialized into the REVIEW-HANDOFF record set. Materialize the missing handoff records and re-run this prompt.`

### 5A) Architect evaluation (internal design-direction pass)
- This step is mandatory after Step 5 has gathered the change-set evidence, even when the primary review pass is otherwise about to conclude with no findings.
- Do not start this step unless the structured coverage matrix validated in Step 3A is complete.
- Invoke the `review-architect` skill (`.github/skills/review-architect/SKILL.md`), read it to EOF, and have it load and apply `.github/instructions/review-architect-compliance-contract.instructions.md` (the `REVIEW-ARCH-*` rules) to evaluate structural fit, naming direction, and maintainability.
- Any architect finding added at this step must be represented as a `REVIEW-HANDOFF-*` intermediate record that conforms to `.github/instructions/review-workflow-handoff.schema.json`, with `classification` set to `observation` or `issue` as appropriate and `visible=true` unless a later duplicate merge absorbs it.
- This is prompt-governed workflow machinery for the single-workflow design. It may add observations or mandatory-source-backed issues, but it must not emit its own section, freeze outcomes, or change the final review template.
- Treat this execution order as a determinism choice owned by the prompt, not as an authority ranking between roles.
- Observable proof requirement: when this step runs, `review-architect` is an actually-used skill, so the Step 5 verification footer MUST include a `Skill used: review-architect` line before any later routed-skill entries.
- If the `review-architect` skill or its contract cannot be loaded to EOF, hard-stop and output exactly this one line and nothing else:
  - `Cannot run code-review-committed-changes: review-architect skill or contract not fully loaded. Load .github/skills/review-architect/SKILL.md and .github/instructions/review-architect-compliance-contract.instructions.md to EOF and re-run this prompt.`

### 5B) Skeptic evaluation (internal adversarial pass)
- This step is mandatory after the architect pass has completed and before the advocate pass, even when the primary review pass is otherwise about to conclude with no findings.
- Do not start this step unless the structured coverage matrix validated in Step 3A is complete.
- Invoke the `review-skeptic` skill (`.github/skills/review-skeptic/SKILL.md`), read it to EOF, and have it load and apply `.github/instructions/review-skeptic-compliance-contract.instructions.md` (the `REVIEW-SKEP-*` rules) to attack the diff for missed defects and weakly-supported reasoning.
- Any skeptic finding added or strengthened at this step must use the same schema-backed `REVIEW-HANDOFF-*` intermediate record shape; enrich existing records when the concern already exists.
- This is prompt-governed workflow machinery for the single-workflow design. It may add net-new issues or observations or strengthen existing findings with new evidence, but it must not emit its own section, freeze outcomes, or change the final review template.
- Observable proof requirement: when this step runs, `review-skeptic` is an actually-used skill, so the Step 5 verification footer MUST include a `Skill used: review-skeptic` line before any later adjudication or moderation entries.
- If the `review-skeptic` skill or its contract cannot be loaded to EOF, hard-stop and output exactly this one line and nothing else:
  - `Cannot run code-review-committed-changes: review-skeptic skill or contract not fully loaded. Load .github/skills/review-skeptic/SKILL.md and .github/instructions/review-skeptic-compliance-contract.instructions.md to EOF and re-run this prompt.`

### 6) Advocate commentary pass (binding: advocate)
- This step is mandatory on every normal successful routed review path after Step 5 and any prior routed intermediate passes; it must not be skipped, summarized, deferred, or simulated.
- Do not start this step unless the structured coverage matrix validated in Step 3A is complete.
- The advocate pass for this workflow is `review-advocate`.
- Invoke the `review-advocate` skill (`.github/skills/review-advocate/SKILL.md`), read it to EOF, and have it load and apply `.github/instructions/review-advocate-compliance-contract.instructions.md` (the `REVIEW-ADV-*` rules) to challenge the existing findings set.
- If the primary review pass plus the routed architect and skeptic passes produced no findings, invoke the advocate pass with an explicit empty structured finding set and treat the result as a deterministic no-op rather than skipping the stage.
- Consume the full schema-conformant `REVIEW-HANDOFF-*` intermediate record set, preserve the shared fields, and add advocate `roleNotes`, evidence, or reasoning where the defense is supported.
- Do not add a separate advocate section to the review body; this routed pass is invisible machinery that only enriches the shared finding set before moderation.
- Observable proof requirement: because this step now runs on every normal successful routed review path, `review-advocate` is an actually-used skill and the Step 5 verification footer MUST include a `Skill used: review-advocate` line before the final `Skill used: review-moderator` entry.
- If the `review-advocate` skill or its contract cannot be loaded to EOF, hard-stop and output exactly this one line and nothing else:
  - `Cannot run code-review-committed-changes: review-advocate skill or contract not fully loaded. Load .github/skills/review-advocate/SKILL.md and .github/instructions/review-advocate-compliance-contract.instructions.md to EOF and re-run this prompt.`

### 7) Final moderation owner (binding: moderator)
- This step is mandatory on every normal successful review path after Step 5 and any routed adjudication steps; it must not be skipped, summarized, deferred, or simulated.
- Do not start this step unless the structured coverage matrix validated in Step 3A is complete.
- The final moderation owner for this workflow is `review-moderator`.
- Invoke the `review-moderator` skill (`.github/skills/review-moderator/SKILL.md`), read it to EOF, and have it load and apply `.github/instructions/review-moderator-compliance-contract.instructions.md` (the `REVIEW-MOD-*` rules) to merge duplicates, normalize surviving records, and produce the final moderated finding set for presentation.
- Consume the schema-conformant `REVIEW-HANDOFF-*` intermediate record set for the run, including the explicit empty-record-set case, preserve record identity and core semantics when records exist, and use moderation only for duplicate merge, wording normalization, severity normalization, final `classification`, final `visible`, and presentation readiness.
- Freeze the review findings set only after the moderator pass completes.
- Do not add a separate final-moderation section to the review body; the moderator binding is invisible machinery that only determines the final visible `ISSUES` and `OBSERVATIONS` set per the routed contract.
- Observable proof requirement: because this step now runs on every normal successful routed review path, `review-moderator` is an actually-used skill and the Step 5 verification footer MUST include a `Skill used: review-moderator` line. Because the moderator pass runs last, that line MUST be the final `Skill used:` entry and the last non-empty line of the response.
- If the `review-moderator` skill or its contract cannot be loaded to EOF, hard-stop and output exactly this one line and nothing else:
  - `Cannot run code-review-committed-changes: review-moderator skill or contract not fully loaded. Load .github/skills/review-moderator/SKILL.md and .github/instructions/review-moderator-compliance-contract.instructions.md to EOF and re-run this prompt.`
- If earlier steps produced no schema-conformant intermediate findings, invoke moderator with an explicit empty record set and freeze a deterministic zero-findings result instead of skipping this step.

### 8) Final presentation renderer
- This step is mandatory on the normal successful review path after the findings set is frozen; it must not be skipped, summarized, deferred, or simulated.
- Explicitly load `.github/instructions/review-presentation-input.schema.json` to EOF in the current run before invoking the presentation skill; do not assume that loading the presentation contract or skill implicitly loaded the schema.
- Build a presentation payload that conforms to `.github/instructions/review-presentation-input.schema.json`.
- For committed review, populate at minimum: `reviewMode=committed`, `changeDescription`, `changeSummaryLines`, `modifiedFiles`, `addedFiles`, `deletedFiles`, `skippedVendoredFiles`, `primaryChangesAnalysis`, `recursionPreventionLines`, `standardsCheckLines`, `linterReport`, `mustFix`, `strengths`, `observations`, `issues`, `immediateRecommendations`, `futureConsiderations`, `overallAssessment`, and required `verificationFooter`.
- When `verificationFooter` is present, populate `requiredStages` and `executedStages` from the current-run routed-stage execution ledger.
- For the normal successful routed path, `requiredStages` and `executedStages` must both be exactly `review-coordinator`, `review-reviewer`, `review-architect`, `review-skeptic`, `review-advocate`, `review-moderator`, `review-presentation`, in that order.
- Derive `verificationFooter.skillsUsed` mechanically from `executedStages`, preserving order and omitting only the render-only `review-presentation` stage.
- If `requiredStages` and `executedStages` differ in content or order, hard-stop and output exactly this one line and nothing else:
  - `Cannot run code-review-committed-changes: required routed review stages did not all execute in canonical order. Re-run this prompt under the latest workflow files.`
- Populate `changeDescription` as a concise change-focused title derived from the authoritative PR title, `changeSummaryLines`, and `primaryChangesAnalysis`; do not use only `PR <number>` when the current run established a more informative description.
- When populating `modifiedFiles`, `addedFiles`, `deletedFiles`, and any file-bearing structured findings, use PR-scoped or repo-scoped paths or path-plus-line references only.
- Do not place editor-local, spill-path, or absolute-disk links into the payload, including `vscode-file://`, `vscode://`, `file://`, `workbench.html`, `AppData`, `workspaceStorage`, `C:\`, or `/Users/` references.
- When authoritative PR scope is available, keep file references PR-scoped or repo-scoped instead of converting them to local editor links or absolute disk paths.
- If the frozen payload contains any forbidden local-link marker, hard-stop and output exactly this one line and nothing else:
  - `Cannot run code-review-committed-changes: final payload contains editor-local or absolute-disk file references. Rebuild the payload with repo-scoped or PR-scoped file references and re-run this prompt.`
- Populate `linterReport` and `mustFix` exactly as required by the linter contract and the presentation schema.
- For `strengths`, structured finding objects remain optional when the payload intentionally uses simple strength bullets.
- For non-empty `observations` and `issues`, use structured finding objects only. The only allowed plain-string content in those sections is the explicit empty-state payload `- None`.
- Populate `immediateRecommendations` and `futureConsiderations` only as plain follow-up bullets derived from already-visible issues or observations; do not use those sections as alternate homes for review findings.
- Treat moderator output as the sole source for visible `ISSUES` and `OBSERVATIONS`: transport only moderated records where `visible=true`, group them only by moderator-owned `classification`, and carry only moderator-owned `presentation` fields into the payload.
- If a moderator-visible observation or issue does not carry the presentation fields required by the current schema and presentation contract, hard-stop and output exactly this one line and nothing else:
  - `Cannot run code-review-committed-changes: final moderated findings are not presentation-complete under the current review-presentation contract. Rebuild the moderated finding set with structured presentation fields and re-run this prompt.`
- Do not derive or invent `summary`, `reviewType`, `impact`, `evidence`, `suggestedChange`, `currentCode`, `correctedCode`, `codeLanguage`, or any other rich-display semantics in this prompt.
- Invoke the `review-presentation` skill (`.github/skills/review-presentation/SKILL.md`), read it to EOF, confirm that `.github/instructions/review-presentation-compliance-contract.instructions.md` and `.github/instructions/review-presentation-input.schema.json` were both explicitly loaded to EOF in the current run, and only then render the final review body.
- The presentation skill is render-only. It must not change findings, severity, classification, recommendations, or verdict semantics.
- The presentation skill owns the normal successful review body. After this step begins, emit exactly the rendered review body and nothing else.
- When `verificationFooter` is present, preserve the supplied routed-skill order and do not add `review-presentation` to `skillsUsed`.
- If the `review-presentation` skill, contract, or schema cannot be loaded to EOF, hard-stop and output exactly this one line and nothing else:
  - `Cannot run code-review-committed-changes: review-presentation skill, contract, or schema not fully loaded. Load .github/skills/review-presentation/SKILL.md, .github/instructions/review-presentation-compliance-contract.instructions.md, and .github/instructions/review-presentation-input.schema.json to EOF and re-run this prompt.`
- Before emitting the first character of the final review body, verify all of the following silently from the frozen current-run payload and the assistant-emitted markdown body: that the payload contains no prompt-invented issue or observation semantics beyond moderator-owned `visible`, `classification`, and `presentation`, and that neither the payload nor the assistant-emitted markdown body contains forbidden local-link markers such as `vscode-file://`, `vscode://`, `file://`, `workbench.html`, `AppData`, `workspaceStorage`, `C:\`, or `/Users/`.
- If any of those checks fail, abort the normal output path, silently rebuild the current-run payload or findings once when possible, and re-run the final presentation step.
- If exact presentation compliance still cannot be satisfied after that silent retry, hard-stop and output exactly this one line and nothing else:
  - `Cannot run code-review-committed-changes: final review body could not be rendered in exact compliance with the current review-presentation contract. Re-run the current audit and presentation steps under the latest contracts.`

## Output format

- On the normal successful path, the final review body is owned by Step 8's `review-presentation` renderer.
- Do not duplicate or override that template in this prompt.
- Prompt-owned hard-stop messages remain prompt-owned.
