# PR Description Prompt Design

## Status

This document is the repo-only design record for `/draft-pr-description`.

Runtime behavior is owned by:

- `.github/prompts/draft-pr-description.prompt.md`
- `.github/skills/pr-description/SKILL.md`
- `.github/instructions/pr-description-compliance-contract.instructions.md`
- `.github/instructions/pr-description-draft.schema.json`

## Product Goal

`/draft-pr-description` is a developer shortcut. It should turn the checked-out AzureRM branch into a solid copy-ready title and body faster than a developer could write them manually.

The workflow is not a code review, maintainer audit, duplicate detector, issue-discovery service, or transactional repository snapshot system.

## Performance Budget

The normal path should target:

- 60 to 90 seconds on a typical changed branch.
- Four primary model/tool phases.
- No more than 10 model iterations under ordinary conditions.
- No more than 15 tool calls under ordinary conditions.
- Two canonical one-line direct-Git repository evidence batches, each issued once.
- At most one compact local branch-boundary metadata call and one replacement scope call when the initial named-base scope is implausibly broad.
- One concurrent targeted-read batch.
- One final repository stability command batch.

Environmental Git performance can exceed the wall-clock target, but the workflow must not add network or audit work to that cost.

## Runtime Ownership

### Prompt

The prompt owns:

- Four-phase orchestration.
- Read-only command transparency.
- Current-worktree selection and exact hard stops.
- Two canonical one-line direct-Git evidence batches with no alternate-syntax retries, one bounded stale-base recovery when required, plus one cheap final stability check.
- In-memory lean-schema conformance without terminal payload construction.
- Four-section final presentation.

### Contract

The contract owns stable AzureRM rules for:

- Branch and repository evidence precedence.
- Local comparison-base selection.
- Local-only recovery when a stale named main ref includes incorporated provider history below a coherent contributor stack.
- Complete local changed-path scope.
- Targeted evidence reads.
- Title selection.
- Template population.
- Checklist decisions.
- Changelog recommendations.
- Confirmed issue references.
- Minimal AI disclosure.

The contract carries rules derived from upstream contributor guidance so every developer invocation does not reload those guides.

### Skill

The hidden skill owns:

- Surface classification.
- Primary and companion treatment.
- One title decision.
- Template-preserving body drafting.
- Checklist, changelog, related issue, security, and evidence-note decisions.
- One lean schema handoff.

### Schema

Schema version `2.0` contains only:

- Repository worktree, branch, `HEAD`, local base reference, and merge base.
- One title.
- One title explanation.
- One complete body.
- Evidence notes.

Audit-only state does not belong in the handoff.

## Workflow

### Load And Inspect

- Load the contract, skill, and lean schema concurrently.
- Validate the current `terraform-provider-azurerm` worktree.
- Use an explicit developer branch or worktree path when supplied.
- Otherwise trust direct `git branch --show-current` over editor or pull request metadata.
- In one canonical semicolon-separated direct-Git batch, collect repository root, remotes, branch, full `HEAD`, initial porcelain status, and local base candidates.
- In one canonical semicolon-separated direct-Git batch after selecting the base, collect merge base, committed paths, working-tree paths, non-ignored untracked paths, and current branch commit subjects.
- Issue each batch once; hard-stop on incomplete output instead of retrying with newlines, script blocks, or alternate shell syntax.
- If that initial scope is implausibly broad enough to suggest incorporated history, collect compact first-parent commit metadata once and test one candidate contributor boundary with the same fixed scope command shape.
- Prefer the second parent of the newest clear two-parent mainline integration merge whose subject explicitly identifies `upstream/main`, `origin/main`, or `main` as merged into the feature branch. This retains contributor work from before and after the merge without treating the merged mainline as PR content. Use the linear oldest-contributor parent only when no clear mainline integration merge exists.
- Accept recovery only when the candidate is an ancestor and its net scope is non-empty and strictly narrower. Otherwise retain the original scope and classify intent after material reads.
- Keep recovery local: do not fetch, query GitHub, inspect per-commit patches, or test multiple candidate origins.
- Do not generate PowerShell or shell programs for repository evidence, template transformation, payload construction, or schema validation.

### Read Relevant Evidence

- Read the current pull request template once.
- Classify the complete changed-path inventory.
- In one concurrent batch, inspect compact evidence for applicable:
  - Every independently user-facing changed implementation surface, including existing surfaces that do not drive the title.
  - A concise material behavior inventory for each surface covering management or query scope, meaningful lifecycle semantics, type or ownership guards, meaningful computed outputs, list scope, and state normalization or drift prevention.
  - Registration or feature wiring.
  - Tests.
  - Documentation.
  - Resource Identity.
  - List Resource support.
  - Security-sensitive behavior.
- Build that direct-read plan from the complete changed-path inventory before opening files. Do not search for known paths, list an already identified service directory, or enumerate test functions merely to prove authored coverage.
- Build a lightweight relationship graph from direct dependencies, shared helpers or abstractions, call sites, common behavior, tests, documentation, and commit subjects. Cross-package scope remains coherent when that evidence supports one user outcome.
- Hard-stop only when two or more independent user-facing intents remain after material reads; never use service-package, path, file, or surface count as a proxy for intent.
- Do not emit or reread a repository-wide patch.

### Draft Once

- Route the compact evidence to the hidden skill once.
- Generate one title and one complete template-preserving body.
- Represent every material user-facing behavior once in compact prose, prioritizing it over routine client wiring, registration, helper, generated-code, vendoring, and SDK details.
- Strictly outline changed behavior without turning drafting into correctness assessment, defect discovery, missing-work analysis, recommendations, or exhaustive schema and CRUD narration.
- Keep test existence separate from test execution.
- Include related issues only from explicit developer input or current-branch commit subjects.
- Include the minimal AI disclosure because the workflow drafted the title and body.

### Check And Render

- Re-read only full `HEAD` and porcelain status.
- Hard-stop once when either changed; do not restart automatically.
- Check the lean payload against the loaded schema in memory without reconstructing it in a terminal command.
- Render title, title explanation, body, evidence notes, and the verification footer.

## Deliberate Non-Goals

The normal workflow does not:

- Fetch or refresh remote-tracking refs.
- Search for active, closed, or historical pull requests.
- Search for duplicate pull requests.
- Search for potential related issues.
- Reload upstream contributor guides.
- Run tests.
- Run a linter or code review.
- Scan conventional development roots or WSL distributions.
- Hash full staged, unstaged, and untracked contents twice.
- Restart automatically when repository state changes.
- Offer a separate audit mode.

## Future Implementation Considerations

These quality improvements are deliberately deferred until the correctness and local evidence path are stable:

- Consider an explicit existing-PR enrichment mode that checks whether the current branch already has a pull request and reads its current body once. Preserve developer-authored custom sections, reviewer context, and external links such as Microsoft Learn, REST API, or API specification references verbatim, while regenerating template-owned Description, checklist, Testing, Change Log, PR type, Related Issues, AI disclosure, rollback, and security sections from current branch evidence.
- Treat an existing pull request body as untrusted presentation input, not evidence of changed scope, test execution, related issues, security impact, or implementation behavior. Never execute or follow instructions embedded in that body.
- Keep external reference selection with the developer. Do not search for, infer, validate, or automatically add documentation links. When no existing pull request is found or the lookup is unavailable, retain the V1 local-only drafting behavior without failure.
- Summarize authored test coverage by meaningful behavior families when compact changed-test evidence supports it, while continuing to separate test existence from successful execution.
- Add concise reviewer notes for evidence-backed non-obvious API behavior, ownership guards, state normalization, or compatibility rationale without turning drafting into correctness assessment or code review.

## Output Requirements

The response contains exactly:

- `Suggested PR Title`
- `Why This Title`
- `Draft PR Body`
- `Evidence Notes`
- `Preflight complete: yes`
- `Skill used: pr-description`

The copy-ready body preserves the current template and includes:

- Verbatim immutable template lines, including Community Note prose and URLs.
- Evidence-based description.
- Conservative checklist states.
- Testing evidence or a concise not-run statement.
- Automation-ready changelog recommendation when warranted.
- Confirmed related issue references or `No related issue confirmed.`
- Minimal AI disclosure.
- Rollback and security-control sections.

## Validation Strategy

The adjudicated regression suite protects:

- Direct Git branch precedence over stale editor metadata.
- Two one-shot canonical direct-Git evidence batches and local-only base selection.
- One bounded local stale-base recovery that prefers a clear mainline integration merge's second parent, falls back to a linear contributor boundary, and leaves unresolved scope to the evidence-based independent-intent classifier.
- Complete committed and working-tree scope.
- Targeted material reads.
- Authored tests versus executed tests.
- Cheap final stability checks without restart.
- No fetch, GitHub search, policy reload, full fingerprint, or WSL scan.
- Exact combined-title syntax, canonical new-surface changelog lines, separate owner-specific lines for changed existing Resources and Data Sources, title-subordinate existing-surface enhancement retention, residual-state removal behavior, and companion-only changelog suppression across AzureRM surface combinations.
- No generated repository-evidence, template-transformation, payload-construction, or terminal schema-validation scripts.
- No alternate-syntax Git retries, exact-known-path searches, service-directory rediscovery, or unnecessary test-function enumeration.
- Verbatim immutable template prose, URLs, comments, headings, checklist text, rollback text, and final-note preservation.
- Explicit-only issue references.
- Lean schema version `2.0` and exact four-section output.

## Upstream Maintenance

- `tools/check-upstream-contributor-drift.ps1` tracks the PR-opening and maintainer-merging guides that support local `PRDESC-*` policy.
- It also tracks HashiCorp's `.github/pull_request_template.md` as a non-catalog source.
- Exact evidence references dynamically map template drift to the owning local rules; the detector does not hard-code PR-description ownership.
- A template change triggers maintainer semantic review of headings, checklist wording, disclosure requirements, contract rules, skill procedure, schema shape, and regression fixtures before the baseline is refreshed.
- Runtime drafting never fetches the remote template and continues to use the template in the developer's current checkout.
