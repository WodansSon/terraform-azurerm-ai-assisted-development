# Hosted GitHub Copilot Code Review Architecture

This document defines the proposed architecture for a compact AzureRM compliance profile designed specifically for hosted GitHub Copilot code review.

The hosted solution is a separate product profile. It is not a reduced installation mode of the normal Terraform AzureRM AI-Assisted Development toolkit.

## Summary

The hosted profile is necessary because GitHub Copilot code review cumulatively loads applicable repository guidance, and a live test failed while adding the system message after the hosted Copilot runtime reported a 110K-token maximum.

[GitHub's hosted code review documentation](https://docs.github.com/en/copilot/using-github-copilot/code-review/using-copilot-code-review) and [repository custom-instructions documentation](https://docs.github.com/en/copilot/customizing-copilot/adding-repository-custom-instructions-for-github-copilot) establish that:

- `.github/copilot-instructions.md` is repository-wide guidance for hosted review.
- Every path-specific `.github/instructions/**/*.instructions.md` file matching a reviewed file is also applied.
- Repository-wide and matching path-specific instructions are combined rather than selected as alternatives.
- Hosted review can additionally use `AGENTS.md`, relevant agent skills, MCP context, repository evidence, and an ephemeral GitHub Actions environment.
- Instructions and skills are read from the pull request head branch.

A captured debug log from a live review of `<owner>/terraform-provider-azurerm` PR `<number>` provides direct runtime evidence:

```text
MaxPromptTokens=110000
Error: Prompt too big after adding system message
```

This proves that the hosted GitHub Copilot runtime supplied and enforced a 110K maximum prompt size and that prompt construction exceeded it when the system message was added. The repository did not configure this value. The log does not prove that the 110K allowance is reserved exclusively for the system message and referenced instruction files, nor does it identify every component already present in the prompt at that stage.

GitHub and Microsoft Learn currently do not publish that numeric limit or define its accounting boundary. This architecture therefore treats the 110K value as captured runtime behavior, not as a documented total model context-window limit or a stable public product guarantee.

Measurement of the normal toolkit explains that result:

- An implementation Go file can match about 318 KB of repository-wide and Go-scoped instruction content.
- A Go acceptance-test file can match about 375 KB because both general Go and test instructions apply.
- A provider documentation file can match about 140 KB before the changed file and supporting evidence are loaded.
- Relevant skills and explicitly referenced guidance can add further instruction material to the assembled prompt.
- The pull request diff, nearby code, existing review discussion, tool output, reasoning, and final comments also consume review resources, but neither the captured log nor a public source found during this design work establishes whether they count against the same 110K prompt limit.

The normal toolkit's many broad `applyTo` files work for its interactive routed workflows but are unsuitable for hosted review when GitHub combines every matching file. The hosted solution must therefore use a separately maintained, compact instruction set rather than load or trim the normal runtime dynamically.

The resulting design is a fully isolated, copy-ready `hosted_copilot/` overlay with:

- a maximum 25K-token engineering budget for hosted system and instruction guidance on any review surface
- compact contracts derived from HashiCorp contributor guidance
- mandatory confirmed maintainer conventions, including the Oxford comma requirement for all documentation
- hosted-only generation, validation, regression, manifest, and installation tooling
- no runtime or installer dependency on the normal toolkit

## Status

- Design discussion only.
- No hosted runtime assets are implemented in this repository.
- The target implementation will be authored under `hosted_copilot/` in this repository as a copy-ready overlay for the provider fork.
- This document is repo-only maintainer guidance and must not be added to `installer/file-manifest.config`.

## Isolation Invariant

The hosted solution must remain fully isolated from the normal toolkit implementation.

- Hosted runtime files must not be added to the normal toolkit installer manifest.
- The normal installer must not install, update, remove, or validate hosted-review files.
- All hosted source rules, scripts, validators, regression fixtures, documentation, and runtime files must live under `hosted_copilot/` in this repository.
- Paths beneath `hosted_copilot/` must mirror their final paths in the target repository.
- Installing the hosted solution means copying the contents of `hosted_copilot/` into the target repository root.
- Hosted generators, validators, regression fixtures, release artifacts, and versioning must remain independent.
- Hosted runtime instructions must not import, load, or depend on normal toolkit contracts, prompts, skills, schemas, or companion guidance.
- The hosted implementation may use this repository as migration evidence while its initial rules are curated, but it must own the resulting rules after migration.
- Later rule sharing must be an explicit, human-reviewed port between independent implementations, never a runtime include or automatic synchronization dependency.
- A failure or release in one profile must not block, mutate, or silently alter the other profile.

This separation exists because the two profiles have different execution models, context limits, trust boundaries, workflows, and release risks.

## Problem Statement

The normal toolkit was designed for interactive VS Code workflows with explicit prompts, routed skills, contract loading, structured handoffs, regression-backed role passes, and human adjudication.

Hosted GitHub Copilot code review combines all applicable repository guidance. Installing the normal toolkit in a provider fork caused hosted review to fail with `Prompt too big after adding system message` while the hosted Copilot runtime reported `MaxPromptTokens=110000`.

The current source payload demonstrates why:

- `.github/copilot-instructions.md` contains about 20 KB and is treated as repository-wide guidance by hosted GitHub review.
- A normal `internal/**/*.go` review can match about 318 KB of current repository-wide and Go-scoped instruction content before code, tool output, skills, or the pull request diff are considered.
- An `internal/**/*_test.go` review can match about 375 KB because both general Go and test-specific instructions apply.
- A `website/docs/**/*.html.markdown` review can match about 140 KB before the documentation change and supporting implementation evidence are considered.
- Multiple files with the same broad `applyTo` pattern are cumulative on GitHub; splitting guidance into many files does not reduce context when every file still matches.

The hosted profile must therefore be designed around a strict system-and-instruction guidance budget rather than produced by copying the normal toolkit and removing a few files.

## First-Party Hosted Behavior

The architecture relies on the following hosted GitHub Copilot code review behavior:

- `.github/copilot-instructions.md` supplies repository-wide review guidance.
- `.github/instructions/**/*.instructions.md` supplies path-specific guidance for matching files.
- Repository-wide and all matching path-specific instructions are combined.
- `AGENTS.md` can supply repository and directory-specific agent context.
- Review-focused agent skills under `.github/skills/` can be used when relevant.
- Configured MCP servers can provide additional evidence.
- Agentic review runs in an ephemeral GitHub Actions environment that can be customized.
- Instructions, agent guidance, and skills are read from the pull request head branch.
- Copilot submits comment-only reviews and does not approve, request changes, or block merging.
- Human replies to Copilot review comments are not visible to Copilot as an interactive continuation.
- Re-reviews can repeat earlier feedback, including feedback that humans resolved or dismissed.
- Public GitHub and Microsoft Learn documentation does not currently publish the captured 110K prompt limit or specify which prompt components count toward it.

These constraints mean the hosted profile cannot reproduce the normal toolkit's frozen audit, challenge, moderation, presentation, or pending-review staging lifecycle.

## Design Goals

- Keep hosted system and instruction guidance comfortably below the observed prompt-construction failure boundary.
- Apply documented HashiCorp contributor requirements.
- Preserve selected mandatory maintainer knowledge that is not explicitly documented.
- Keep rule provenance, requirement strength, and documentation gaps distinct.
- Produce concise, evidence-backed inline findings.
- Load only guidance relevant to the changed file surface.
- Use deterministic tooling for checks that do not require model reasoning.
- Make upstream documentation drift visible without automatically reinterpreting changed prose.
- Keep generated runtime files reproducible and reviewable.
- Protect hosted instructions from unreviewed pull request changes.

## Non-Goals

- Reproducing the normal toolkit's multi-role review workflow.
- Porting the pending-review staging or human challenge workflow.
- Drafting pull request descriptions.
- Implementing resource or documentation changes.
- Loading every normal toolkit rule into hosted review.
- Treating historical pull request comments as authoritative training data.
- Automatically converting changed contributor prose into new compliance requirements.

## Hosted Package Layout

`hosted_copilot/` is both the authoritative ownership boundary and the copy-ready repository overlay:

```text
hosted_copilot/
  .github/
    copilot-instructions.md
    instructions/
      azurerm-go.instructions.md
      azurerm-tests.instructions.md
      azurerm-docs.instructions.md
    skills/
      code-review/
        SKILL.md
  tools/
    hosted-copilot/
      rules/
        upstream-rules.yaml
        maintainer-conventions.yaml
        hosted-safeguards.yaml
      regression/
      package-manifest.json
      Install-HostedCopilot.ps1
      Sync-ContributorGuidance.ps1
      Build-HostedInstructions.ps1
      Test-HostedInstructions.ps1
  docs/
    HOSTED_COPILOT_CODE_REVIEW.md
```

- `.github/` is the hosted runtime customization exactly as it must appear in the target repository.
- `tools/hosted-copilot/rules/` owns normalized rule records and provenance.
- `tools/hosted-copilot/` owns synchronization, generation, validation, and regression support.
- `tools/hosted-copilot/package-manifest.json` owns the exact set of paths installed and updated by the hosted package.
- `tools/hosted-copilot/Install-HostedCopilot.ps1` owns safe deployment into a target repository.
- `docs/HOSTED_COPILOT_CODE_REVIEW.md` explains the installed hosted profile and its maintenance commands.
- Generated instruction files are written directly beneath `hosted_copilot/.github/` and must not be edited manually.

Nothing under `hosted_copilot/` is normal toolkit runtime payload.

## Copy-Ready Hosted Runtime

GitHub discovers hosted review customizations only from supported root `.github/` paths. Copying the contents of `hosted_copilot/` into the target repository places the runtime files at those required paths:

```text
.github/
  copilot-instructions.md
  instructions/
    azurerm-go.instructions.md
    azurerm-tests.instructions.md
    azurerm-docs.instructions.md
  skills/
    code-review/
      SKILL.md
```

No path rewriting or second packaging layer is required. The relative path of every file beneath `hosted_copilot/` is its destination path in the target repository.

Files with the same names or roles in the normal toolkit are not shared dependencies. The normal installer must ignore the complete `hosted_copilot/` tree.

### Hosted Deployment

The overlay remains manually copyable, but `Install-HostedCopilot.ps1` is the recommended deployment path because repository roots commonly contain an existing `.github/` tree.

The hosted installer must:

- resolve every source and destination from `package-manifest.json`
- support a dry-run mode that reports additions, updates, collisions, and unchanged files without writing
- copy hidden paths such as `.github/` correctly
- create missing directories without replacing unrelated directory contents
- detect an existing destination file before writing
- update only files already owned by the hosted package and listed in the manifest
- fail closed when an unowned destination path already exists, including `.github/copilot-instructions.md`
- require explicit approval before replacing a colliding or locally modified file
- preserve unrelated `.github/`, `tools/`, and `docs/` content
- verify copied content against source hashes after installation
- avoid calling, importing, or modifying the normal toolkit installer and manifest

Manual copying must follow the same ownership boundary. It must merge directories rather than replace them and must not overwrite existing files without review.

### Repository-Wide Instructions

`.github/copilot-instructions.md` should contain only guidance that every hosted review needs:

- repository purpose and high-level layout
- the review evidence hierarchy
- the instruction that findings must identify an actionable defect
- the instruction to avoid materially duplicate existing review feedback
- the required concise inline-comment shape
- the trust rule for changes to hosted customization files
- pointers to deterministic validation commands when available

It must not contain detailed implementation, testing, or documentation rules.

### Go Instructions

`.github/instructions/azurerm-go.instructions.md` should apply to `internal/**/*.go` and contain a compact set of high-value implementation rules.

- Include requirements that can produce concrete correctness, compatibility, state, API, or provider-behavior defects.
- Exclude lengthy examples and general educational material.
- Exclude workflow orchestration and role definitions.
- Prefer one atomic requirement per stable rule ID.
- Keep shared Go guidance compact enough that loading it alongside test guidance remains safe.

### Test Instructions

`.github/instructions/azurerm-tests.instructions.md` should apply to `internal/**/*_test.go` and supplement the compact Go contract.

- Focus on missing lifecycle coverage, incorrect test patterns, unsafe execution claims, and assertion defects.
- Preserve mandatory testing conventions supported by contributor guidance or maintained provider precedent.
- Avoid duplicating general Go requirements already present in the Go instructions.

### Documentation Instructions

`.github/instructions/azurerm-docs.instructions.md` should apply to `website/docs/**/*.html.markdown`.

- Include published contributor documentation standards.
- Include mandatory maintainer conventions that contributor documentation leaves implicit.
- Require the Oxford comma for all documentation prose lists of three or more items.
- Preserve schema and implementation evidence requirements for field validity, examples, ordering, defaults, and lifecycle claims.
- Keep lengthy provenance evidence outside the runtime contract unless a dispute requires it.

### Review Skill

`.github/skills/code-review/SKILL.md` should define the small hosted review procedure:

- classify changed files by review surface
- inspect the diff and the nearest evidence required to validate a concern
- use configured GitHub context to inspect existing review feedback when available
- suppress materially equivalent comments
- emit only actionable, line-addressable findings
- keep each comment concise and identify the applicable rule ID
- avoid broad summaries, role handoffs, moderation records, or presentation schemas

Mandatory compliance rules must remain in path-specific instructions because hosted skill selection is relevance-based and should not be the sole enforcement dependency.

## Hosted Guidance Budget

The 110K value is a captured GitHub Copilot runtime limit, not a repository setting or a documented total model context window. The debug log proves that adding the system message caused the assembled prompt to exceed that maximum. It does not prove that only the system message and referenced instruction files count toward the maximum. Public GitHub and Microsoft Learn documentation reviewed for this design does not define that accounting boundary.

The 25K limit below is this project's conservative engineering budget for hosted guidance that may be assembled into that prompt. It is not an estimate of total review token usage and does not assert that pull request diffs, tool results, reasoning, or generated comments count against the same product limit.

Initial design budgets:

| Surface | Maximum instruction budget |
| --- | ---: |
| Repository-wide guidance | 2K tokens |
| Shared Go contract | 8K tokens |
| Test supplement | 4K tokens |
| Documentation contract | 8K tokens |
| Review skill | 3K tokens |
| Maximum combined hosted guidance for one review | 25K tokens |

Separately from the hosted-guidance budget, a useful review still needs capacity for:

- platform and tool instructions
- pull request diff
- nearby implementation evidence
- existing review discussion
- tool and MCP output
- reasoning and final inline comments

The generator and validation pipeline must reject generated hosted-guidance output that exceeds its surface budget. It cannot validate GitHub's unpublished total runtime context accounting.

## Rule Source Model

The hosted profile must maintain normalized rules under `hosted_copilot/tools/hosted-copilot/rules/`, outside the runtime instruction files. Generated files under `hosted_copilot/.github/` must not become a second rule authority.

The entire `hosted_copilot/` tree is an isolated distribution source. It must not be added to the normal toolkit installer layout.

### Provenance Classes

- `Published upstream standard`: explicitly stated by HashiCorp contributor guidance.
- `Confirmed maintainer convention`: mandatory behavior directly confirmed by HashiCorp maintainers but not explicitly stated in contributor guidance.
- `Inferred maintainer convention`: supported by repeated accepted review guidance or consistent established provider practice, without direct confirmation.
- `Hosted safeguard`: local protection required for stable hosted-review behavior rather than an upstream contributor requirement.

### Independent Rule Dimensions

Provenance must not determine enforcement strength. Each rule should record separate fields:

- stable rule ID
- review surface
- atomic requirement text
- requirement level, such as `mandatory` or `advisory`
- provenance class
- evidence references
- whether an upstream documentation gap exists
- runtime inclusion decision
- deterministic or model-based enforcement method
- last semantic review date

A mandatory tribal requirement remains mandatory even though it is not explicitly documented.

### Oxford Comma Requirement

The Oxford comma rule is the reference case for this distinction.

- Requirement: use the Oxford comma for every documentation prose list of three or more items.
- Requirement level: mandatory.
- Provenance: confirmed maintainer convention.
- Documentation gap: yes.
- Evidence: direct HashiCorp maintainer clarification and consistent examples throughout contributor documentation.
- Runtime placement: hosted documentation contract.

The hosted profile must not weaken this rule because the contributor standards demonstrate rather than explicitly state it.

## Candidate Migration Policy

The current normal toolkit contains useful migration evidence but is not the hosted runtime source.

Initial candidate groups:

- Published upstream rules are baseline candidates.
- Confirmed and inferred maintainer conventions are tribal-knowledge candidates.
- Local safeguards require individual review because many protect normal toolkit orchestration and do not apply to hosted review.
- Rules without provenance require classification only when selected for hosted migration.

Selection should favor rules that are:

- mandatory or high-impact
- supported by durable evidence
- likely to identify actionable defects
- concise enough for hosted execution
- applicable across the provider rather than one historical resource
- not already enforced more reliably by deterministic tooling

Do not migrate normal toolkit role machinery, transport schemas, prompt mechanics, or presentation requirements.

## Maintenance Pipeline

The hosted source-maintenance flow should be deterministic until semantic judgment is required.

- Pin each tracked upstream source to a recorded content digest.
- Discover upstream source drift through a PowerShell maintenance command.
- Report changed source sections and affected rule mappings.
- Do not rewrite normalized rules solely because a digest changed.
- Require a maintainer to decide whether the changed prose alters rule meaning.
- Update approved normalized rules manually.
- Generate compact runtime instructions deterministically from the normalized rule records.
- Validate generated files against committed output.
- Measure each generated surface against its token budget.
- Validate rule IDs, required metadata, source links, duplicate mappings, and conflicting requirements.
- Update `package-manifest.json` only when the hosted package intentionally adds, removes, or relocates an owned target path.
- Preview deployment with `Install-HostedCopilot.ps1` in dry-run mode before writing to a target repository.
- Require review of rules whose evidence disappeared or whose upstream source was renamed or removed.

The script owns synchronization, validation, and rendering. It does not own semantic interpretation.

## Deterministic Enforcement

Rules that can be checked reliably without model reasoning should use scripts, linters, or CI.

Examples include:

- generated-file freshness
- token-budget limits
- rule schema validation
- provenance and evidence completeness
- tracked-source digest changes
- duplicate stable rule IDs
- forbidden dependencies on normal toolkit files
- required frontmatter and supported hosted paths
- formatting checks with established low false-positive behavior

Semantic checks remain in the compact runtime contracts.

## Head-Branch Trust Boundary

Hosted GitHub review reads repository instructions, agent instructions, and skills from the pull request head branch. A contributor can therefore change the guidance used to review the same pull request.

Required protections:

- Add hosted instruction, skill, rule-source, generator, and validation paths to `CODEOWNERS`.
- Require human approval for every change to those paths.
- Treat pull requests changing hosted AI policy as security-sensitive maintenance changes.
- Do not rely on Copilot's review of a pull request that changes the instructions governing that review.
- Validate generated output in required CI.
- Consider organization-level guidance for immutable trust rules when the repository owner controls that surface.

These controls reduce accidental or malicious policy weakening but do not make head-branch instructions an immutable authority.

## Hosted Review Output

The hosted profile should optimize for native inline comments.

Each finding should contain:

- the concrete problem
- the observable effect or risk
- a specific correction
- the stable hosted rule ID
- a source link only when it materially helps the contributor understand the requirement

The review should not emit normal toolkit handoff records, frozen finding sets, moderation metadata, or pending-review plans.

Because hosted Copilot cannot interact with human replies as a continuation of the review, challenges and adjudication remain human review activities outside this profile.

## Existing Feedback

The hosted review skill should inspect existing pull request feedback through GitHub context when available and suppress materially equivalent comments.

This is a best-effort safeguard rather than a platform guarantee:

- GitHub documents that re-reviews may repeat resolved or downvoted feedback.
- MCP and agentic context use may vary by review.
- The profile should not claim deterministic deduplication unless a separate required tool proves it.

Regression evaluation should measure duplicate-comment behavior explicitly.

## Validation and Regression

The hosted project should own a separate validation and regression system.

Minimum validation:

- source-rule schema validation
- generated-output reproducibility
- per-surface token-budget enforcement
- no references to normal toolkit runtime paths
- supported hosted frontmatter and glob validation
- Markdown lint
- source-drift reporting
- policy-file CODEOWNERS coverage

Minimum regression corpus:

- known implementation defects
- known acceptance-test defects
- known documentation defects
- mandatory tribal-rule violations, including Oxford comma cases
- clean changes that should produce no comment
- duplicate existing-review feedback
- large pull requests that exercise context limits
- pull requests that modify hosted customization files

Hosted evaluation must score both defect recall and false positives. A smaller contract is successful only if it remains useful and defensible under the hosted budget.

## Rollout Direction

### Design and Inventory

- Inventory customization files in the target provider fork.
- Measure the exact hosted payload currently loaded for implementation, tests, and documentation.
- Identify the target repository and ownership model for hosted source rules and generated files.
- Confirm CODEOWNERS and required-check capabilities.

### Rule Curation

- Select the smallest useful upstream baseline.
- Inventory confirmed and inferred maintainer conventions.
- Classify selected unprovenanced rules.
- Exclude normal toolkit orchestration safeguards.
- Record mandatory documentation gaps explicitly.

### Generation and Validation

- Define the normalized rule schema.
- Implement the PowerShell drift, generation, and validation commands.
- Generate the isolated hosted runtime profile.
- Add token-budget and dependency-boundary checks.

### Hosted Evaluation

- Test the profile on controlled pull requests in the fork.
- Compare findings against known expected issues.
- Measure context use, duplicate feedback, false positives, and missed defects.
- Reduce or refine rules before expanding the profile.

### Protected Adoption

- Generate runtime instructions directly under `hosted_copilot/.github/`.
- Run `Install-HostedCopilot.ps1` in dry-run mode against the target repository.
- Review and resolve every reported destination collision before installation.
- Install the manifest-owned contents of `hosted_copilot/` into the target repository root without path transformation.
- Commit the copied `.github/`, `tools/hosted-copilot/`, and hosted documentation paths in the target repository.
- Require CODEOWNERS review for hosted policy changes.
- Enable hosted Copilot review with custom instructions.
- Monitor live reviews and update normalized rules through the isolated maintenance process.

## Open Design Decisions

- The exact manifest schema for ownership, source hashes, and previously installed hashes.
- The explicit approval mechanism for first-install collisions and locally modified package-owned files.
- Whether GitHub publishes or support confirms which prompt components count toward `MaxPromptTokens`; until then, preserve the captured `110000` value and exact failure stage without asserting an exclusive system-message scope.
- Which deterministic provider checks can run within hosted review without consuming excessive setup time or context.
- Whether organization-level instructions are available for immutable trust-boundary guidance.
- The initial rule count and exact token budget for each surface after measurement in the target repository.
- How live hosted review outcomes are captured for regression without treating comments as automatically correct guidance.

## Success Criteria

The design is ready for implementation when:

- the hosted and normal toolkit ownership boundaries are explicit
- no hosted runtime dependency points into the normal toolkit
- each review surface has an approved token budget
- selected rules have requirement strength, provenance, evidence, and runtime decisions
- the Oxford comma and other mandatory tribal requirements are preserved
- source drift cannot silently rewrite rule meaning
- hosted installation can preview and detect collisions without invoking the normal installer
- hosted policy paths require human ownership review
- the target regression corpus can distinguish useful findings from false positives
