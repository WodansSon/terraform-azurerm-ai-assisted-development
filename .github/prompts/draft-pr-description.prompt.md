---
description: "Draft an AzureRM pull request title and copy-ready body from the current branch change-set."
---

# Draft AzureRM Pull Request Description

## Purpose

Produce a useful copy-ready pull request title and body quickly from the checked-out AzureRM worktree. This is a drafting shortcut, not a repository audit.

## Guardrails

- Treat every invocation as a fresh run.
- Do not pull, fetch, merge, rebase, checkout, commit, push, reset, clean, edit files, or run tests.
- Before each terminal batch, display its exact commands under `[Read-only] {{PURPOSE}}`.
- Use terminal only for the fixed literal Git commands listed below. Do not generate PowerShell or shell variables, loops, conditionals, script blocks, here-strings, file reads, string replacement, JSON construction, or schema-validation programs.
- Use tool-native file reads and searches for every non-Git operation.
- Batch independent commands and reads. Do not repeat evidence already collected in the current run.
- Use the validated current worktree and direct Git branch unless the developer explicitly supplies another branch or worktree path.
- Treat editor, workspace, source-control, and pull request branch metadata as advisory when it conflicts with direct Git.
- Use local Git refs only. Do not refresh remote-tracking refs or search GitHub for pull requests or issues.
- Keep the normal workflow to the four phases below. Add another model/tool round only when one concrete missing fact blocks an accurate title or body.

## Phase 1: Load And Inspect

- Load these files concurrently to EOF:
  - `.github/instructions/pr-description-compliance-contract.instructions.md`
  - `.github/skills/pr-description/SKILL.md`
  - `.github/instructions/pr-description-draft.schema.json`
- Verify the contract and skill EOF markers.
- If a prerequisite is missing or incomplete, hard-stop with exactly:
  - `Cannot run draft-pr-description: required workflow files are missing, incomplete, or stale. Confirm the PR description contract, skill, and schema are installed and readable to EOF.`
- In one `[Read-only] Repository identity and base candidates` batch, run exactly this one-line command once:
  - `git rev-parse --show-toplevel; git remote -v; git branch --show-current; git rev-parse HEAD; git status --porcelain=v1 --untracked-files=all; git rev-parse --verify upstream/main; git rev-parse --verify origin/main; git rev-parse --verify main`
- Do not issue the commands as newline-separated input or retry them in another shell form.
- If the batch does not return repository root, remotes, branch, `HEAD`, status, and at least one usable base candidate, hard-stop with exactly:
  - `Cannot run draft-pr-description: the fixed repository identity batch returned incomplete output. Re-run the prompt in a fresh terminal.`
- Validate the `terraform-provider-azurerm` repository name, expected structure, and remotes using direct Git output plus tool-native file inspection.
- Resolve the first usable local base in this order: `upstream/main`, `origin/main`, local `main`.
- In one `[Read-only] Repository change scope` batch, substitute only the selected literal ref for `{{BASE_REFERENCE}}` and run exactly this one-line command once:
  - `git merge-base HEAD {{BASE_REFERENCE}}; git diff --name-status --find-renames {{BASE_REFERENCE}}...HEAD; git diff --name-status --find-renames HEAD; git ls-files --others --exclude-standard; git log --format=%s {{BASE_REFERENCE}}..HEAD`
- Do not retry or reformat the batch. If merge base or path inventory output is incomplete, hard-stop with exactly:
  - `Cannot run draft-pr-description: the fixed repository change-scope batch returned incomplete output. Re-run the prompt in a fresh terminal.`
- Treat the union of committed, working-tree, and non-ignored untracked paths as the complete change scope.
- Classify whether the initial inventory is implausibly broad across service packages, commit subjects, or unrelated path families while keeping generated, vendored, test, documentation, registration, Resource Identity, and List Resource paths subordinate.
- Treat breadth only as a possible stale-base signal. Do not classify cross-package scope as unrelated before material evidence is read.
- If the initial inventory is implausibly broad enough to suggest incorporated history, run one `[Read-only] Local branch boundary evidence` batch with exactly this one-line command after substituting only the selected literal ref for `{{BASE_REFERENCE}}`:
  - `git log --first-parent --format="%H%x09%P%x09%an%x09%ae%x09%cn%x09%ce%x09%s" {{BASE_REFERENCE}}..HEAD`
- Do not run this batch for an ordinary coherent scope. Do not include per-commit patches or path inventories in it.
- Derive exactly one `{{CANDIDATE_ORIGIN}}` from the metadata. Prefer the second parent of the newest clear two-parent mainline integration merge whose subject explicitly identifies `upstream/main`, `origin/main`, or `main` as merged into the feature branch.
- When no clear mainline integration merge exists, require a clear contiguous contributor change stack at the branch tip and use the first parent of its oldest commit as `{{CANDIDATE_ORIGIN}}`.
- Do not test both candidate forms in one run.
- Run one `[Read-only] Recovered repository change scope` batch with exactly this one-line command after substituting only that literal commit:
  - `git merge-base HEAD {{CANDIDATE_ORIGIN}}; git diff --name-status --find-renames {{CANDIDATE_ORIGIN}}...HEAD; git diff --name-status --find-renames HEAD; git ls-files --others --exclude-standard; git log --format=%s {{CANDIDATE_ORIGIN}}..HEAD`
- Accept the recovered origin only when the reported merge base equals `{{CANDIDATE_ORIGIN}}`, the recovered scope is non-empty, strictly removes incorporated history from the initial inventory, and leaves a materially narrower contributor tip stack.
- On acceptance, replace the selected base and merge base with the candidate commit and use only the recovered committed scope plus the unchanged working-tree and untracked scope.
- If no clear candidate exists or the candidate is not strictly narrower, do not run another recovery pass; retain the original scope and resolve intent coherence from material evidence in Phase 2.
- When the developer supplied no branch or worktree, direct Git owns branch selection. Do not search for a branch named only by editor or pull request metadata.
- When the current worktree is unsuitable, inspect only an explicit developer-supplied path or ask for one. Do not scan development roots or invoke WSL to locate another clone.
- Hard-stop on the wrong repository or missing AzureRM structure with exactly:
  - `Cannot run draft-pr-description: the current worktree is not terraform-provider-azurerm. Open or provide the AzureRM provider worktree and re-run this prompt.`
- Hard-stop on `main` with exactly:
  - `Cannot run draft-pr-description: the current branch is main. Switch to the candidate pull request branch and re-run this prompt.`
- Hard-stop when no local base or merge base resolves with exactly:
  - `Cannot run draft-pr-description: no local comparison base could be resolved. Provide upstream/main, origin/main, or local main, then re-run this prompt.`
- Hard-stop when the complete tracked and untracked scope is empty with exactly:
  - `Cannot run draft-pr-description: no changes were found relative to the resolved local comparison base.`

## Phase 2: Read Relevant Evidence

- Read the current worktree's `.github/pull_request_template.md` once.
- If the template is missing, hard-stop with exactly:
  - `Cannot run draft-pr-description: required workflow source is missing: .github/pull_request_template.md.`
- Classify the complete changed-path inventory before reading patches, but do not hard-stop from package, path, file, or surface counts alone.
- Before opening material files, build one complete direct-read plan from the changed-path inventory.
- In one and only one concurrent Phase 2 tool batch, inspect compact evidence only for:
  - Every independently user-facing changed implementation surface, including existing Resources, Data Sources, Actions, or provider behavior that does not drive the title.
  - The material behavior inventory for each surface: management or query scope, meaningful lifecycle semantics, type or ownership guards, meaningful computed outputs, list scope, state normalization or drift prevention, and removal or disable transitions that actively clear API-retained values.
  - One or more atomic records for every material behavior, each containing the owning Terraform surface, exact lifecycle path or paths, behavior kind, and observable outcome. Keep plan, import, create, read, update, delete, and list paths distinct, and do not transfer retry, wait, validation, guard, clear, normalization, or other behavior across owners or paths merely because they share a helper or change intent.
  - Any changed custom request marshaller, payload builder, workaround client, or equivalent update helper that decides whether configured values are omitted or actively cleared. Read only its compact comment and clear-path logic, and retain the observable behavior rather than its mechanics.
  - Changed enabling implementation evidence for any claimed new compatibility between a new surface and an existing consumer. Do not treat a new object flowing through an unchanged ID, schema, or association path as a change to that consumer.
  - Registration or feature wiring needed to identify the surface.
  - Matching tests and documentation needed for checklist decisions.
  - Resource Identity or List Resource companions when changed.
  - Security-sensitive changes when the changed paths or compact patches indicate them.
- Prefer targeted symbol, exact-text, and file reads. Do not emit or reread one repository-wide patch.
- Read known changed files directly. Do not search for exact paths already present in the inventory, list the service directory after ownership is known, or enumerate test functions merely to prove changed test coverage.
- Treat matching changed test paths as authored-test evidence. Read test content only when one material coverage claim remains unresolved.
- Use search only when the changed-path inventory does not identify the owning file or symbol. Do not stage implementation, test, and documentation evidence across successive rounds.
- After the evidence batch, build one lightweight relationship graph across user-facing surfaces using shared symbols or helpers, direct call sites, common schema or lifecycle behavior, registration and ownership links, companion tests and documentation, commit subjects, and one explainable user outcome.
- Classify each existing-surface behavior as a bug fix or enhancement from its observable effect. Treat proven corrections to premature lifecycle success, failed cleanup, valid operations that failed or hung, drift, or API-retained residual state as bug fixes even when polling, serialization, or client changes implement them; keep implementation-only refactors subordinate.
- Treat directly evidenced cross-service dependencies, shared provider or framework helpers, common abstractions, and resources consumed by other resources as one connected change intent.
- Hard-stop only when two or more independent user-facing intents remain and one title plus one coherent description cannot honestly represent them, using exactly:
  - `Cannot run draft-pr-description: multiple independent change intents remain after dependency analysis. Identify the primary change or split the branch, then re-run this prompt.`
- Use the checked-in contract for title, checklist, changelog, and body policy. Do not reload upstream contributor guides during drafting.

## Phase 3: Draft Once

- Route the collected evidence through `.github/skills/pr-description/SKILL.md` once.
- Require the description to represent every material user-facing behavior from the compact inventory once, combining related items into concise prose.
- Draft only from the atomic behavior records. Expand every grouped subject, lifecycle-path list, and conjunction into individual claims before finalizing prose or changelog lines; require an exact owner, path, behavior kind, and outcome record for every expanded claim.
- When combining surfaces or lifecycle paths, state only the intersection of atomic claims proven for every named surface and path. Keep every non-shared retry, wait, validation, guard, clear, normalization, or outcome separately attributed.
- When the inventory proves that removing or disabling configuration actively clears API-retained values, require the description to state that observable removal behavior without naming serialization, request-payload, custom-client, or polling mechanics.
- When active clearing applies to multiple independently configured retained-value families, name each affected family compactly rather than retaining only the family observed by polling.
- Do not claim new compatibility, support, or association behavior for an existing surface without changed enabling implementation evidence on that surface.
- Suppress routine client wiring, registration, helper names, generated code, vendoring, and SDK plumbing when they only support those behaviors.
- Do not add review findings, correctness judgments, missing-work analysis, recommendations, or field-by-field implementation narration.
- Produce one schema-conformant payload containing:
  - The selected worktree, branch, and `HEAD`.
  - One title and one concise title explanation.
  - The complete template-preserving body.
  - Concise unresolved evidence notes.
- Assemble the complete body by inserting responses into the loaded template skeleton. Do not recreate immutable template lines from remembered or familiar AzureRM template text.
- Preserve conservative claims:
  - Do not claim tests ran without observed current-run output or explicit developer-provided results.
  - Determine whether tests and documentation exist from changed-file evidence independently from whether tests ran.
  - Leave contributor acknowledgements and duplicate/issue-review confirmations unchecked.
- Include confirmed related issues only from explicit developer input or qualifying current-branch commit messages. Otherwise use `No related issue confirmed.`
- Include the template's minimal AI disclosure because this workflow drafted the title and body:
  - Check `AI Assisted`.
  - State `AI was used to draft the PR title and description.`
- Do not run duplicate pull request or potential issue searches.

## Phase 4: Check And Render

- Immediately before rendering, run one `[Read-only] Repository stability check` batch containing exactly this one-line command:
  - `git rev-parse HEAD; git status --porcelain=v1 --untracked-files=all`
- Compare the final `HEAD` and status output with Phase 1. If either differs, hard-stop with exactly:
  - `Cannot run draft-pr-description: repository state changed during drafting. Stop concurrent edits and re-run this prompt.`
- Compare every immutable body line with the already-loaded template. Permit only evidence insertion, example or claim placeholder replacement, and checklist-marker changes from `[ ]` to `[x]`; restore every other mismatch in memory.
- Compare ordered URL tokens in immutable draft lines with the corresponding loaded template lines. Restore every mismatch before rendering, even when the replacement URL appears valid.
- Verify that existing Resource and Data Source changelog owner tokens use the contract's exact undecorated form, with only Terraform names in code formatting.
- Re-expand grouped description and changelog wording into atomic claims and remove or narrow any claim without a matching owner, lifecycle path, behavior kind, and observable outcome record.
- Do not rewrite or shorten template prose, links, URLs, comments, headings, checklist text, Community Note content, rollback text, or the final note.
- Check the in-memory payload once against the already-loaded `.github/instructions/pr-description-draft.schema.json` before rendering.
- Do not invoke the terminal, serialize the payload into a command, reread the template, or construct a second payload solely for schema validation.
- If validation fails, hard-stop with exactly:
  - `Cannot run draft-pr-description: pr-description produced a schema-invalid draft payload. Refresh the workflow files and re-run this prompt.`
- Render exactly:

  ````markdown
  ## Suggested PR Title

  ```text
  {{TITLE}}
  ```

  ## Why This Title

  {{ONE_EVIDENCE_BASED_SENTENCE}}

  ## Draft PR Body

  ```markdown
  {{COMPLETE_COPY_READY_BODY}}
  ```

  ## Evidence Notes

  {{EVIDENCE_GAP_BULLETS_OR_EXACT_EMPTY_SENTENCE}}

  Preflight complete: yes
  Skill used: pr-description
  ````

- Render `No unresolved evidence gaps.` when no gaps remain.
- Emit no alternate titles, process narration, search section, or text after `Skill used: pr-description`.
