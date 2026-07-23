---
description: "Draft an AzureRM pull request title and copy-ready body from the complete current branch change-set."
---

# Draft AzureRM Pull Request Description

## Execution guardrails

### Fresh-run requirement

- Treat every invocation as a new drafting run.
- Do not reuse repository state, base resolution, diff output, searches, classifications, validation evidence, or draft content from an earlier turn.
- Execute the full procedure even when the user supplies no arguments.

### Read-only authorization

- The read-only Git, repository inspection, pull request metadata, open pull request search, and open issue search operations required below are authorized by this prompt.
- A read-only fetch of the selected `upstream/main` or `origin/main` ref is authorized.
- Do not pull, merge, rebase, commit, push, checkout, reset, clean, edit files, or otherwise change repository or branch state.
- Do not run tests automatically. Use test output only when it was explicitly gathered in the current invocation or is eligible existing pull request evidence under the contract.

### Determinism

- Follow the loaded contract rather than prompt memory.
- Do not guess missing facts or emit alternate titles.
- Do not begin normal output until the structured payload is complete and schema-valid.
- Emit the normal response exactly once and add no text after its verification footer.

## Mandatory procedure

### Load prerequisites

- Read `.github/instructions/pr-description-compliance-contract.instructions.md` to EOF.
- Verify its final non-empty line is `<!-- PRDESC-CONTRACT-EOF -->`.
- Read `.github/skills/pr-description/SKILL.md` to EOF.
- Verify its final non-empty line is `<!-- PRDESC-SKILL-EOF -->`.
- Read `.github/instructions/pr-description-draft.schema.json` to EOF.
- If any prerequisite is absent, unreadable, or not fully loaded, hard-stop with exactly:
  - `Cannot run draft-pr-description: required workflow files are missing, incomplete, or stale. Confirm the PR description contract, skill, and schema are installed and readable to EOF.`

### Verify repository eligibility

- Apply `PRDESC-PRE-*`.
- Confirm the repository name is `terraform-provider-azurerm` and the expected AzureRM structure exists.
- Determine the current branch.
- If the repository is ineligible, hard-stop with exactly:
  - `Cannot run draft-pr-description: this prompt only supports hashicorp/terraform-provider-azurerm or a fork with the same repository name and expected AzureRM structure.`
- If the current branch is `main`, hard-stop with exactly:
  - `Cannot run draft-pr-description: the current branch is main. Switch to the candidate pull request branch and re-run this prompt.`

### Resolve the comparison base

- Apply `PRDESC-BASE-*` in exact priority order.
- Use authoritative existing pull request metadata for the current branch when available.
- Otherwise inspect `upstream/main`, then `origin/main`, then local `main`.
- Attempt the authorized read-only fetch when selecting a remote-tracking ref.
- Resolve the selected commit and compute its merge base with `HEAD`.
- If no base or merge base can be resolved, hard-stop with exactly:
  - `Cannot run draft-pr-description: no comparison base could be resolved. Configure upstream/main, provide a usable origin/main, or identify the pull request base ref, then re-run this prompt.`

### Load base-revision authorities

- Load every file required by `PRDESC-PRE-003` from the selected base commit with read-only Git inspection.
- Do not substitute candidate-branch copies for missing base-revision files.
- If a required file is missing, hard-stop with exactly this form, replacing the placeholder with the repo-relative path:
  - `Cannot run draft-pr-description: required base-revision source is missing: {{MISSING_PATH}}.`

### Collect the complete change-set

- Apply `PRDESC-SCOPE-001`.
- Gather one merge-base-to-working-tree tracked diff with name status and full patch content.
- Gather non-ignored untracked paths with `git ls-files --others --exclude-standard` and inspect their contents.
- Gather current branch commit messages from merge base through `HEAD` for explicit issue references and supporting context.
- If the complete tracked and untracked scope is empty, hard-stop with exactly:
  - `Cannot run draft-pr-description: no changes were found relative to the resolved comparison base.`

### Classify and perform pre-draft searches

- Route the current-run evidence through `.github/skills/pr-description/SKILL.md`.
- Apply `PRDESC-SCOPE-*` and stop before drafting when unrelated primary changes span service packages.
- On that conflict, hard-stop with exactly:
  - `Cannot run draft-pr-description: unrelated primary changes span multiple service packages. Identify the primary change or split the branch, then re-run this prompt.`
- Search open pull requests for every exact changed Terraform surface name in lexical order.
- Treat unavailable open pull request search as an evidence gap and leave its checklist item unchecked.

### Draft the title, body, and decisions

- Have the `pr-description` skill apply `PRDESC-EVID-*`, `PRDESC-TITLE-*`, `PRDESC-BODY-*`, `PRDESC-CHECK-*`, and `PRDESC-CHANGELOG-*`.
- Produce one title, one evidence-based title explanation, the complete template-preserving body, checklist decisions, changelog decision, and evidence gaps.
- Do not render user-visible output yet.

### Search for potential related issues

- After title and body drafting, apply `PRDESC-ISSUE-002` through `PRDESC-ISSUE-004`.
- Search open issues only; exclude pull requests.
- Keep the search advisory and non-blocking.
- Return successful no-match or unavailable status explicitly.

### Validate the structured payload

- Have the `pr-description` skill finish the handoff required by `PRDESC-OUT-001`.
- Validate the entire payload against `.github/instructions/pr-description-draft.schema.json` before rendering.
- If validation fails, hard-stop with exactly:
  - `Cannot run draft-pr-description: pr-description produced a schema-invalid draft payload. Refresh the workflow files and re-run this prompt.`

## Output format

- Apply `PRDESC-OUT-002` and `PRDESC-OUT-003` exactly.
- Render only this shape:

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

  ## Potential Related Issues

  {{ISSUE_TABLE_OR_EXACT_NO_RESULTS_OR_UNAVAILABLE_SENTENCE}}

  Preflight complete: yes
  Skill used: pr-description
  ````

- Use the exact table header `Issue | Title | Why it may relate` when candidates exist.
- Render `No unresolved evidence gaps.` when the payload has no evidence gaps.
- Render `No potential related issues found.` after a successful search with no candidates.
- Render `Potential related issue search unavailable.` when search is unavailable.
- Do not emit any text after `Skill used: pr-description`.
