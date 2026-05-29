# AI Customization Architecture Standard

This document defines how this repository should structure GitHub Copilot and VS Code AI customizations going forward.

Purpose:

- preserve current functionality and determinism while modernizing the customization system
- align the repository to current first-party GitHub Copilot and VS Code customization guidance
- reduce user friction from too many entrypoints without hiding important behavior in fragile instruction text
- give maintainers a regression-safe migration path for existing instructions, prompts, skills, and review workflows

This is a repo-only maintainer document. It is not runtime payload and must not be added to `installer/file-manifest.config`.

Actionable follow-up inventory:

- `docs/AI_CUSTOMIZATION_MIGRATION_INVENTORY.md`

## First-Party Basis

This standard is based on the current first-party guidance from:

- VS Code custom instructions guidance
- VS Code prompt files guidance
- VS Code agent skills guidance
- GitHub Copilot repository custom instructions guidance

Key takeaways from that guidance:

- keep always-on instructions concise and focused
- use file-scoped instructions for targeted rules, not for all workflow logic
- use prompt files for explicit, user-invoked tasks
- use skills for reusable multi-step capabilities that the model can load when relevant
- use agents when the user needs a simpler front door for a specialized domain
- use executable tooling for enforcement instead of endlessly expanding prose instructions

## Design Goals

- No regression in current review or implementation behavior during migration.
- No reduction in determinism for rule-heavy workflows.
- No increase in required user steps for common workflows.
- No silent movement of normative rules out of contract files.
- No prompt removal until replacement behavior is validated.

## Layer Responsibilities

### `.github/copilot-instructions.md`

Use this file for stable, repo-wide guidance that should apply across most tasks.

Keep it focused on:

- repository purpose and layout
- critical build, test, and validation entrypoints
- high-level architecture facts
- global safety or workflow constraints
- cross-cutting conventions that truly apply everywhere

Do not use it for:

- detailed file-type-specific rules
- long step-by-step task workflows
- duplicated contract logic
- specialized implementation playbooks

### `.github/instructions/*.instructions.md`

Use scoped instruction files for targeted rules that apply only to particular files, paths, languages, or workflows.

Instruction files should generally fall into one of these categories:

- contract files
- routing files
- companion pattern guides

#### Contract files

Use contracts as the normative source for exact compliance requirements.

Contract files must contain:

- stable rule IDs
- explicit precedence
- evidence expectations
- consumer definitions
- conflict resolution

Contracts are the highest-authority repository layer for their domain.

#### Routing files

Use routing files to tell the AI which skills and contracts must be consulted for matching work.

Routing files should be short and deterministic.
They should not become a second implementation guide.

#### Companion guides

Use companion guides for:

- worked examples
- pattern explanations
- heuristics
- migration notes
- illustrative templates

Companion guides must not become the primary home for:

- normative compliance rules that belong in contracts
- large user-facing workflow entrypoints
- guidance that should instead live in a skill

### `.github/skills/*/SKILL.md`

Use skills for reusable, multi-step capabilities.

Skills are the preferred home for:

- implementation workflows
- review workflows
- testing workflows
- migration playbooks
- procedures that benefit from examples, scripts, or supporting resources

Skills should be used when the AI should be able to load the workflow automatically based on relevance.

Preferred skill pattern:

- user-facing entrypoints remain minimal
- workflow complexity lives in skills
- routing files point the AI at the right skill(s)
- skills may later be hidden from slash-command UX if they should load automatically rather than be user-invoked

### `.github/prompts/*.prompt.md`

Use prompt files as explicit user entrypoints for lightweight or discoverable tasks.

Prompt files are appropriate when:

- the user should intentionally choose the workflow
- the prompt is a thin task wrapper
- the task is easier to discover as a slash command

Prompt files are not the preferred place for hidden orchestration.

Do not rely on instructions to make prompt files behave like invisible background plumbing.
If the agent should load behavior automatically, that behavior belongs in skills plus routing.

### Custom agents

Use custom agents when the user needs a simpler front door for a domain with many internal steps.

Good candidates:

- review workflows
- maintainer toolkit workflows
- specialized provider-maintenance domains

Agents are a user-experience simplifier, not a replacement for contracts.

### Scripts, hooks, MCP, and validators

If a rule should be enforced, detected, or validated mechanically, prefer tooling over prose.

Use tooling for:

- drift detection
- contract validation
- changelog validation
- regression harness checks
- installer payload verification

Use prose only for the parts that cannot be enforced mechanically.

## Current Repository Classification

### Always-on runtime guidance

- `.github/copilot-instructions.md`
  - role: repository-wide always-on guidance
  - target state: concise, stable, high-signal, non-task-specific

### Normative runtime contracts

- `.github/instructions/code-review-compliance-contract.instructions.md`
- `.github/instructions/docs-compliance-contract.instructions.md`
- `.github/instructions/implementation-compliance-contract.instructions.md`
- `.github/instructions/testing-compliance-contract.instructions.md`

These remain the authoritative rule layers for their domains.

### Runtime routing files

- `.github/instructions/ai-skill-routing-resource-implementation.instructions.md`
- `.github/instructions/ai-skill-routing-docs.instructions.md`
- `.github/instructions/ai-skill-routing-tests.instructions.md`

These should stay short and focused on deterministic routing.

### Runtime companion guides

- `.github/instructions/implementation-guide.instructions.md`
- `.github/instructions/azure-patterns.instructions.md`
- `.github/instructions/code-clarity-enforcement.instructions.md`
- `.github/instructions/error-patterns.instructions.md`
- `.github/instructions/schema-patterns.instructions.md`
- `.github/instructions/testing-guidelines.instructions.md`
- `.github/instructions/documentation-guidelines.instructions.md`
- `.github/instructions/provider-guidelines.instructions.md`
- `.github/instructions/security-compliance.instructions.md`
- `.github/instructions/api-evolution-patterns.instructions.md`
- `.github/instructions/migration-guide.instructions.md`
- `.github/instructions/performance-optimization.instructions.md`
- `.github/instructions/troubleshooting-decision-trees.instructions.md`

Target state for these files:

- smaller and more focused
- less decorative framing
- less duplicated workflow logic
- more explicit separation between examples, heuristics, and normative rules

### Runtime prompts

- `.github/prompts/code-review-local-changes.prompt.md`
- `.github/prompts/code-review-committed-changes.prompt.md`
- `.github/prompts/code-review-docs.prompt.md`

Current classification:

- explicit user-facing review entrypoints
- compatibility-sensitive
- should not be removed early in the migration

Near-term target state:

- keep these prompts working
- move reusable review logic behind them into contracts and skills where practical
- avoid increasing the number of required user-invoked prompts

### Runtime skills

- `.github/skills/resource-implementation/SKILL.md`
- `.github/skills/custom-poller-migration/SKILL.md`
- `.github/skills/acceptance-testing/SKILL.md`
- `.github/skills/docs-writer/SKILL.md`

Current classification:

- correct primitive for specialized workflows
- preferred home for additional reusable workflow logic

### Repo-only maintainer assets

- `docs/AI_TOOLKIT_ALIGNMENT_CHECKLIST.md`
- `tools/check-upstream-contributor-drift.ps1`
- `tools/validate-ai-toolkit.ps1`
- `tools/validate-contracts.ps1`
- `tools/validate-changelog-taxonomy.ps1`
- `tools/config/upstream-contributor.json`
- repo-only maintainer skills and supporting docs

These remain outside the installed payload.

## Review Workflow Position

Because review UX is already considered difficult by the team, prompt multiplication is a regression risk.

Near-term rule:

- keep the three existing review prompts as compatibility entrypoints
- do not require users to chain multiple prompt invocations to finish one review task
- do not attempt to hide prompt orchestration inside instructions

Preferred future direction:

- consolidate shared review logic into contracts and skills
- keep user-facing review entrypoints minimal
- consider a single review front door only after parity is proven by regression coverage

## Regression-Safe Migration Rules

When modernizing the customization system:

- do not remove a runtime prompt, skill, or instruction file until an equivalent replacement exists
- do not move normative rule text out of contract files unless all consumers are updated accordingly
- do not convert a user-facing prompt into a skill-only workflow if that would require more user steps than today
- do not replace deterministic prompt-owned hard-stop behavior with open-ended skill prose
- do not shrink always-on guidance until the missing facts are preserved in a more appropriate layer
- do not assume newer layering automatically improves outcomes; validate it with the repo's harness and maintainer checks

## Migration Phases

### Phase 0: Architecture definition

Purpose:

- define the target structure without changing runtime behavior

Allowed changes:

- repo-only docs
- classification work
- migration guardrails

Forbidden changes:

- prompt removal
- skill removal
- runtime manifest changes
- behavior-changing instruction rewrites without parity evidence

### Phase 1: Classification and correctness cleanup

Purpose:

- identify what each runtime file is for
- fix clearly wrong or stale guidance

Allowed changes:

- stale example fixes
- outdated pattern corrections
- routing clarifications

### Phase 2: Move workflow logic to the right layer

Purpose:

- shift specialized procedures out of giant companion guides and into skills where appropriate

Rules:

- keep current user-facing entrypoints stable
- preserve deterministic behavior during the move
- prefer adding internal skill support before simplifying user-facing entrypoints

### Phase 3: Simplify user entrypoints

Purpose:

- reduce user friction only after internal routing and skill behavior are stable

Rules:

- introduce simplified front doors only after parity is demonstrated
- keep old entrypoints as compatibility aliases until the regression harness proves the replacement is safe

### Phase 4: Retire redundant surfaces

Purpose:

- remove duplication after parity has been proven

Rules:

- remove only what is demonstrably redundant
- preserve compatibility until maintainers intentionally retire it

## Required Validation Before Runtime Migration

Before any runtime customization behavior is changed:

- `pwsh -NoProfile -File ./tools/validate-ai-toolkit.ps1` passes
- `pwsh -NoProfile -File ./tools/check-upstream-contributor-drift.ps1` passes when upstream alignment is in scope
- relevant regression harness coverage exists for the changed workflow
- new behavior is benchmarked against the old workflow when the change affects prompts, reviews, or routing
- installer payload classification is re-checked before any manifest change

For review workflow changes specifically:

- keep current review prompt functionality until replacement behavior is validated
- add or update regression cases before retiring or collapsing prompts
- prefer backwards-compatible entrypoint additions over destructive entrypoint replacements

## Immediate Maintainer Actions

- Use this document as the architecture target before broad instruction-file cleanup.
- Keep fixing obviously stale or incorrect guidance now.
- Do not begin wide cosmetic rewrites until each affected runtime file has been classified under this standard.
- Prefer skills plus routing over new user-facing prompts when adding specialized workflow behavior.
