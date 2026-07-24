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
- Classify the complete changed-path inventory before reading patches.
- Hard-stop when unrelated primary changes span service packages with exactly:
  - `Cannot run draft-pr-description: unrelated primary changes span multiple service packages. Identify the primary change or split the branch, then re-run this prompt.`
- Before opening material files, build one complete direct-read plan from the changed-path inventory.
- In one and only one concurrent Phase 2 tool batch, inspect compact evidence only for:
  - Every independently user-facing changed implementation surface, including existing Resources, Data Sources, Actions, or provider behavior that does not drive the title.
  - Registration or feature wiring needed to identify the surface.
  - Matching tests and documentation needed for checklist decisions.
  - Resource Identity or List Resource companions when changed.
  - Security-sensitive changes when the changed paths or compact patches indicate them.
- Prefer targeted symbol, exact-text, and file reads. Do not emit or reread one repository-wide patch.
- Read known changed files directly. Do not search for exact paths already present in the inventory, list the service directory after ownership is known, or enumerate test functions merely to prove changed test coverage.
- Treat matching changed test paths as authored-test evidence. Read test content only when one material coverage claim remains unresolved.
- Use search only when the changed-path inventory does not identify the owning file or symbol. Do not stage implementation, test, and documentation evidence across successive rounds.
- Use the checked-in contract for title, checklist, changelog, and body policy. Do not reload upstream contributor guides during drafting.

## Phase 3: Draft Once

- Route the collected evidence through `.github/skills/pr-description/SKILL.md` once.
- Produce one schema-conformant payload containing:
  - The selected worktree, branch, and `HEAD`.
  - One title and one concise title explanation.
  - The complete template-preserving body.
  - Concise unresolved evidence notes.
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
