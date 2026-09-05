# Hosted GitHub Copilot Code Review Architecture:

This document defines the proposed architecture for a compact AzureRM compliance toolkit designed specifically for hosted GitHub Copilot code review.

**This Repository Uses Two Canonical Product Names:**

- **Interactive Toolkit:** The existing VS Code-oriented toolkit with prompts, routed skills, contracts, interactive workflows, the Interactive Toolkit installer, and the existing regression harness
- **Hosted Toolkit:** The proposed compact GitHub Copilot code-review toolkit owned beneath `hosted_copilot/`

The Hosted Toolkit is a separate product profile. It is not a reduced installation mode of the Interactive Toolkit.

## Summary:

The Hosted Toolkit is necessary because GitHub Copilot code review cumulatively loads applicable repository guidance, and a live test failed while adding the system message after the hosted Copilot runtime reported a `110K`-token maximum.

**[GitHub's Hosted Code Review Documentation](https://docs.github.com/en/copilot/using-github-copilot/code-review/using-copilot-code-review) and [Repository Custom-Instructions Documentation](https://docs.github.com/en/copilot/customizing-copilot/adding-repository-custom-instructions-for-github-copilot) Establish That:**

- `.github/copilot-instructions.md` is repository-wide guidance for hosted review.
- Every path-specific `.github/instructions/**/*.instructions.md` file matching a reviewed file is also applied.
- Repository-wide and matching path-specific instructions are combined rather than selected as alternatives.
- Hosted review can additionally use `AGENTS.md`, relevant agent skills, MCP context, repository evidence, and an ephemeral GitHub Actions environment.
- Instructions and skills are read from the pull request head branch.

**A Captured Debug Log from a Live Review of `<owner>/terraform-provider-azurerm` PR `<number>` Provides Direct Runtime Evidence:**

```text
MaxPromptTokens=110000
Error: Prompt too big after adding system message
```

This proves that the hosted GitHub Copilot runtime supplied and enforced a `110K` maximum prompt size and that prompt construction exceeded it when the system message was added. The repository did not configure this value. The log does not prove that the `110K` allowance is reserved exclusively for the system message and referenced instruction files, nor does it identify every component already present in the prompt at that stage.

GitHub and Microsoft Learn currently do not publish that numeric limit or define its accounting boundary. This architecture therefore treats the `110K` value as captured runtime behavior, not as a documented total model context-window limit or a stable public product guarantee.

**Measurement of the Interactive Toolkit Explains That Result:**

- An implementation Go file can match about `318 KB` of repository-wide and Go-scoped instruction content.
- A Go acceptance-test file can match about `375 KB` because both general Go and test instructions apply.
- A provider documentation file can match about `140 KB` before the changed file and supporting evidence are loaded.
- Relevant skills and explicitly referenced guidance can add further instruction material to the assembled prompt.
- The pull request diff, nearby code, existing review discussion, tool output, reasoning, and final comments also consume review resources, but neither the captured log nor a public source found during this design work establishes whether they count against the same `110K` prompt limit.

The Interactive Toolkit's many broad `applyTo` files work for its routed workflows but are unsuitable for hosted review when GitHub combines every matching file. The Hosted Toolkit must therefore use a separately maintained, compact instruction set rather than load or trim the Interactive Toolkit runtime dynamically.

**The Resulting Design Is a Fully Isolated, Copy-Ready `hosted_copilot/` Overlay With:**

- A maximum `25K`-token engineering budget for hosted system and instruction guidance on any review surface
- Compact contracts derived from HashiCorp contributor guidance
- Mandatory confirmed maintainer conventions, including the Oxford comma requirement for all documentation
- Hosted-only generation, semantic validation, regression, manifest, and installation tooling
- Shared repo-local presentation formatting for validation and test report renderers
- No runtime or installer dependency on the Interactive Toolkit

## Status:

- Design discussion only.
- No Hosted Toolkit runtime assets are implemented in this repository.
- Initial design-phase maintainer tooling is implemented: the Hosted Toolkit changelog, phase-aware validator, explicit ownership map, changed-toolkit dispatcher, and routing self-test.
- The target implementation will be authored under `hosted_copilot/` in this repository as a copy-ready overlay for the provider fork.
- This document is repo-only maintainer guidance and must not be added to `installer/file-manifest.config`.

## Isolation Invariant:

The Hosted Toolkit must remain fully isolated from the Interactive Toolkit implementation.

- Hosted Toolkit runtime files must not be added to the Interactive Toolkit installer manifest.
- The Interactive Toolkit installer must not install, update, remove, or validate Hosted Toolkit files.
- All Hosted product rules, semantic validators, regression test artifacts, documentation, runtime files, and operational scripts must live under `hosted_copilot/` in this repository. Repo-local validation presentation functions remain shared maintenance infrastructure.
- Paths beneath `hosted_copilot/` must mirror their final paths in the target repository.
- Installing the Hosted Toolkit means copying the contents of `hosted_copilot/` into the target repository root.
- Hosted generators, semantic validators, regression test artifacts, deployment state, and provenance must remain independent.
- Repo-local validation and test report renderers may use shared presentation functions that do not participate in runtime behavior, generation, semantic decisions, deployment, or either toolkit package.
- Hosted Toolkit runtime instructions must not import, load, or depend on Interactive Toolkit contracts, prompts, skills, schemas, or companion guidance.
- The Hosted Toolkit implementation may use this repository as migration evidence while its initial rules are curated, but it must own the resulting rules after migration.
- Later rule sharing must be an explicit, human-reviewed port between independent implementations, never a runtime include or automatic synchronization dependency.
- Activity in one toolkit must not block, mutate, or silently alter the other toolkit.

This separation exists because the two profiles have different execution models, context limits, trust boundaries, workflows, and distribution risks.

## Problem Statement:

The Interactive Toolkit was designed for VS Code workflows with explicit prompts, routed skills, contract loading, structured handoffs, regression-backed role passes, and human adjudication.

Hosted GitHub Copilot code review combines all applicable repository guidance. Installing the Interactive Toolkit in a provider fork caused hosted review to fail with `Prompt too big after adding system message` while the hosted Copilot runtime reported `MaxPromptTokens=110000`.

**The Current Source Payload Demonstrates Why:**

- `.github/copilot-instructions.md` contains about `20 KB` and is treated as repository-wide guidance by hosted GitHub review.
- An Interactive Toolkit `internal/**/*.go` review can match about `318 KB` of current repository-wide and Go-scoped instruction content before code, tool output, skills, or the pull request diff are considered.
- An `internal/**/*_test.go` review can match about `375 KB` because both general Go and test-specific instructions apply.
- A `website/docs/**/*.html.markdown` review can match about `140 KB` before the documentation change and supporting implementation evidence are considered.
- Multiple files with the same broad `applyTo` pattern are cumulative on GitHub; splitting guidance into many files does not reduce context when every file still matches.

The Hosted Toolkit must therefore be designed around a strict system-and-instruction guidance budget rather than produced by copying the Interactive Toolkit and removing a few files.

## First-Party Hosted Behavior:

**The Architecture Relies on the Following Hosted GitHub Copilot Code Review Behavior:**

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
- Public GitHub and Microsoft Learn documentation does not currently publish the captured `110K` prompt limit or specify which prompt components count toward it.

These constraints mean the Hosted Toolkit cannot reproduce the Interactive Toolkit's frozen audit, challenge, moderation, presentation, or pending-review staging lifecycle.

## Design Goals:

- Keep hosted system and instruction guidance comfortably below the observed prompt-construction failure boundary.
- Apply documented HashiCorp contributor requirements.
- Preserve selected mandatory maintainer knowledge that is not explicitly documented.
- Keep rule provenance, requirement strength, and documentation gaps distinct.
- Review published contributor guidance and Interactive Toolkit rules as independent candidate sources without making either source an automatic runtime dependency.
- Produce concise, evidence-backed inline findings.
- Load only guidance relevant to the changed file surface.
- Use deterministic tooling for checks that do not require model reasoning.
- Make upstream documentation drift visible without automatically reinterpreting changed prose.
- Report impact, estimated token cost, and remaining Hosted guidance capacity before approving candidate rules.
- Keep generated runtime files reproducible and reviewable.
- Protect hosted instructions from unreviewed pull request changes.

## Non-Goals:

- Reproducing the Interactive Toolkit's multi-role review workflow.
- Porting the pending-review staging or human challenge workflow.
- Drafting pull request descriptions.
- Implementing resource or documentation changes.
- Loading every Interactive Toolkit rule into hosted review.
- Treating historical pull request comments as authoritative training data.
- Unattended conversion of changed contributor prose or Interactive Toolkit rules into new Hosted compliance requirements.

## Experiment MVP Handoff:

The first implementation milestone is a controlled experiment, not production adoption.

**Experiment Objective:**

Prove that a compact Hosted Toolkit can complete useful AzureRM pull request reviews within the observed hosted prompt boundary and can outperform or complement contributor-guidance-only review on identical test cases without introducing unacceptable false positives.

**Current Experiment Scaffold:**

- Implemented: Hosted changelog, phase-aware Hosted validator, toolkit ownership map, changed-toolkit dispatcher, routing self-test, and architecture authority
- Not yet implemented: Hosted runtime instructions, review skill, package manifest, direct deployment script, controlled test-case execution, and scored experiment results
- Repository-only: The changed-toolkit dispatcher protects maintenance boundaries but is not an experiment success criterion

**Required Experiment Artifacts:**

- Compact repository-wide, Go, test, and documentation instructions under `hosted_copilot/.github/`
- One review-focused Hosted skill under `hosted_copilot/.github/skills/code-review/`
- `package-manifest.json` containing the exact deployable paths, mirrored from `hosted_copilot/` into the target repository
- `Install-Toolkit.ps1` accepting an explicit target fork directory and supporting dry-run deployment from the current checkout
- `Test-Toolkit.ps1` enforcing structure, isolation, Markdown validity, and per-surface token budgets
- A normalized rule catalog and schema that preserve upstream, maintainer, and local provenance independently
- Deterministic path-specific instruction generation and read-only drift detection across the complete upstream contributor-document set
- A Hosted-owned intake ledger that records semantic decisions for every reviewed Interactive Toolkit rule without creating a runtime synchronization dependency
- Explicitly invoked, incremental AI-assisted candidate review with deterministic evidence, hash-bound cache reuse, impact weighting, projected token budgets, and explicit maintainer approval before catalog changes
- A local Hosted Rule Workbench that presents intake as one guided promotion process while preserving PowerShell as the only repository-write boundary
- A controlled test-case matrix with identical diffs, fixed review effort, expected findings, and blinded result adjudication

**Experiment Acceptance Criteria:**

- The installer can preview and deploy the overlay from this checkout into the target fork without replacing unrelated files
- Hosted review completes on implementation, acceptance-test, and documentation surfaces without the captured prompt-size failure
- Every paired comparison uses identical test changes and review effort
- Results record expected findings, misses, duplicate comments, unexpected findings, and observed model metadata
- The experiment produces enough repeated evidence to decide whether to adopt, revise, or stop the Hosted Toolkit direction

**Deferred Until an Adoption Decision:**

- Unattended semantic interpretation or automatic application of upstream contributor or Interactive Toolkit changes
- A production regression harness beyond the controlled experiment test-case matrix
- Hosted-specific CI rollout and long-term operational monitoring
- Any versioned release, archive, or publication workflow

During the experiment, normalized rule sources and deterministic generation are required so evaluation uses reproducible guidance without losing maintainer conventions. Generated runtime files remain committed and frozen by source commit. Production automation beyond read-only drift detection remains an adoption decision.

## Target Hosted Package Layout:

`hosted_copilot/` is both the authoritative ownership boundary and the copy-ready repository overlay:

```text
hosted_copilot/
  CHANGELOG.md
  .github/
    copilot-instructions.md
    instructions/
      azurerm-go.instructions.md
      azurerm-tests.instructions.md
      azurerm-docs.instructions.md
    skills/
      code-review/
        SKILL.md
  copilot-rule-catalog/
    instruction-catalog.json
    instruction-catalog.schema.json
    interactive-intake-ledger.json
    interactive-intake-ledger.schema.json
    rule-intake-review.schema.json
    promotion-plan.schema.json
    promotion-receipt.schema.json
    rule-assessments/
      assessment-baseline.json
      assessment-baseline.schema.json
    audit/
  regression/
    README.md
    cases/
    schema/
    raw/
    results/
  tools/
    package-manifest.json
    Install-Toolkit.ps1
    Generate-Instructions.ps1
    Invoke-RuleIntakeAssessment.ps1
    Invoke-RulePromotion.ps1
    New-RuleIntakeReview.ps1
    Publish-RuleIntakeAssessmentBaseline.ps1
    Start-RuleWorkbench.ps1
    Test-InstructionGeneration.ps1
    Test-RuleIntakeAssessment.ps1
    Test-RuleIntakeReview.ps1
    Test-UpstreamSources.ps1
    Test-Toolkit.ps1
  docs/
    HOSTED_COPILOT_CODE_REVIEW.md
  workbench/
    index.html
    app.js
    styles.css
```

- `.github/` is the hosted runtime customization exactly as it must appear in the target repository.
- `copilot-rule-catalog/` owns normalized rules, shared rule assessments, intake decisions, promotion schemas, and append-only promotion receipts.
- `regression/` owns controlled cases, schemas, and local experiment artifacts. Cases, schemas, and operating guidance are checked in; generated `raw/` captures and `results/` records remain local and Git-ignored.
- `tools/` owns assessment, generation, validation, promotion, and deployment support.
- `workbench/` owns the static local review interface. It is maintainer tooling and is not deployed into the target provider repository.
- `CHANGELOG.md` owns Hosted Toolkit development and deployment history.
- `tools/package-manifest.json` owns the exact set of mirrored relative paths installed and updated by the hosted package.
- `tools/Install-Toolkit.ps1` owns safe deployment into a target repository.
- `docs/HOSTED_COPILOT_CODE_REVIEW.md` explains the installed Hosted Toolkit and its maintenance commands.
- Generated path-specific instruction files are written directly beneath `hosted_copilot/.github/`, committed, and frozen by source commit. They must not be edited manually.

Nothing under `hosted_copilot/` is Interactive Toolkit runtime payload.

## Copy-Ready Hosted Runtime:

**GitHub Discovers Hosted Review Customizations Only from Supported Root `.github/` Paths. Copying the Contents of `hosted_copilot/` into the Target Repository Places the Runtime Files at Those Required Paths:**

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

Files with the same names or roles in the Interactive Toolkit are not shared dependencies. The Interactive Toolkit installer must ignore the complete `hosted_copilot/` tree.

### Hosted Deployment:

The overlay remains manually copyable, but `Install-Toolkit.ps1` is the recommended deployment path because repository roots commonly contain an existing `.github/` tree.

The Hosted Toolkit is deployed directly from the current source checkout into a target fork. It does not use a separate release bundle, archive, or version file. Reproducibility comes from the source Git commit, the manifest ownership map, and the exact deployed hashes recorded in installed state.

**The Hosted Installer Must:**

- Resolve every source and destination from `package-manifest.json`
- Accept the target fork directory explicitly and read source files from the current repository checkout
- Support a dry-run mode that reports additions, updates, collisions, and unchanged files without writing
- Copy hidden paths such as `.github/` correctly
- Create missing directories without replacing unrelated directory contents
- Detect an existing destination file before writing
- Update only files already owned by the hosted package and listed in the manifest
- Fail closed when an unowned destination path already exists, including `.github/copilot-instructions.md`
- Require explicit approval before replacing a colliding or locally modified file
- Preserve unrelated `.github/`, `tools/`, and `docs/` content
- Compute source hashes from the current checkout during every dry run and installation
- Verify copied content against the computed source hashes after installation
- Record the source Git commit when available, the ownership-manifest hash, and the verified deployed file hashes in installed state
- Avoid calling, importing, or modifying the Interactive Toolkit installer and manifest

Manual copying must follow the same ownership boundary. It must merge directories rather than replace them and must not overwrite existing files without review.

### Repository-Wide Instructions:

`.github/copilot-instructions.md` should contain only guidance that every hosted review needs:

- Repository purpose and high-level layout
- The review evidence hierarchy
- The instruction that findings must identify an actionable defect
- The instruction to avoid materially duplicate existing review feedback
- The required concise inline-comment shape
- The trust rule for changes to hosted customization files
- Pointers to deterministic validation commands when available

It must not contain detailed implementation, testing, or documentation rules.

### Go Instructions:

`.github/instructions/azurerm-go.instructions.md` should apply to `internal/**/*.go` and contain a compact set of high-value implementation rules.

- Include requirements that can produce concrete correctness, compatibility, state, API, or provider-behavior defects.
- Exclude lengthy examples and general educational material.
- Exclude workflow orchestration and role definitions.
- Prefer one atomic requirement per stable rule ID.
- Keep shared Go guidance compact enough that loading it alongside test guidance remains safe.

### Test Instructions:

`.github/instructions/azurerm-tests.instructions.md` should apply to `internal/**/*_test.go` and supplement the compact Go contract.

- Focus on missing lifecycle coverage, incorrect test patterns, unsafe execution claims, and assertion defects.
- Preserve mandatory testing conventions supported by contributor guidance or maintained provider precedent.
- Avoid duplicating general Go requirements already present in the Go instructions.

### Documentation Instructions:

`.github/instructions/azurerm-docs.instructions.md` should apply to `website/docs/**/*.html.markdown`.

- Include published contributor documentation standards.
- Include mandatory maintainer conventions that contributor documentation leaves implicit.
- Require the Oxford comma for all documentation prose lists of three or more items.
- Preserve schema and implementation evidence requirements for field validity, examples, ordering, defaults, and lifecycle claims.
- Keep lengthy provenance evidence outside the runtime contract unless a dispute requires it.

### Review Skill:

`.github/skills/code-review/SKILL.md` should define the small hosted review procedure:

- Classify changed files by review surface
- Inspect the diff and the nearest evidence required to validate a concern
- Use configured GitHub context to inspect existing review feedback when available
- Suppress materially equivalent comments
- Emit only actionable, line-addressable findings
- Keep each comment concise and identify the applicable rule ID
- Avoid broad summaries, role handoffs, moderation records, or presentation schemas

Mandatory compliance rules must remain in path-specific instructions because hosted skill selection is relevance-based and should not be the sole enforcement dependency.

## Hosted Guidance Budget:

The `110K` value is a captured GitHub Copilot runtime limit, not a repository setting or a documented total model context window. The debug log proves that adding the system message caused the assembled prompt to exceed that maximum. It does not prove that only the system message and referenced instruction files count toward the maximum. Public GitHub and Microsoft Learn documentation reviewed for this design does not define that accounting boundary.

The `25K` limit below is this project's conservative engineering budget for hosted guidance that may be assembled into that prompt. It is not an estimate of total review token usage and does not assert that pull request diffs, tool results, reasoning, or generated comments count against the same product limit.

**Initial Design Budgets:**

| Surface | Maximum instruction budget |
| --- | ---: |
| Repository-wide guidance | `2K tokens` |
| Shared Go contract | `8K tokens` |
| Test supplement | `4K tokens` |
| Documentation contract | `8K tokens` |
| Review skill | `3K tokens` |
| Maximum combined hosted guidance for one review | `25K tokens` |

**Separately from the Hosted-Guidance Budget, a Useful Review Still Needs Capacity for:**

- Platform and tool instructions
- Pull request diff
- Nearby implementation evidence
- Existing review discussion
- Tool and MCP output
- Reasoning and final inline comments

The generator and validation pipeline must reject generated hosted-guidance output that exceeds its surface budget. It cannot validate GitHub's unpublished total runtime context accounting.

Budget reporting must distinguish the dependency-free character-quarter estimate from actual runtime consumption, which GitHub does not expose. For each runtime file and combined review surface, report estimated tokens, guarded tokens with the required 25% margin, the approved budget, remaining guarded tokens, and utilization. Every candidate proposal must render the complete proposed catalog in a temporary Hosted root and report its token delta plus projected post-change values.

## Rule Source Model:

The Hosted Toolkit must maintain normalized rules under `hosted_copilot/copilot-rule-catalog/`, outside the runtime instruction files. Generated files under `hosted_copilot/.github/` must not become a second rule authority.

The entire `hosted_copilot/` tree is an isolated distribution source. It must not be added to the Interactive Toolkit installer layout.

### Provenance Classes:

- `Published upstream standard`: explicitly stated by HashiCorp contributor guidance or prescribed through its canonical examples and templates. Template evidence is normative when it demonstrates the required contributor-facing shape rather than merely illustrating an optional style.
- `Confirmed maintainer convention`: mandatory behavior directly confirmed by HashiCorp maintainers but not explicitly stated in contributor guidance.
- `Inferred maintainer convention`: supported by repeated accepted review guidance or consistent established provider practice, without direct confirmation.
- `Local safeguard`: local protection required for stable hosted-review behavior rather than an upstream contributor requirement.

### Independent Rule Dimensions:

**Provenance Must Not Determine Enforcement Strength. Each Rule Should Record Separate Fields:**

- Stable rule ID
- Review surface
- Atomic requirement text
- Requirement level, such as `mandatory` or `advisory`
- Provenance class
- Evidence references
- Whether an upstream documentation gap exists
- Runtime inclusion decision
- Implementation model applicability for implementation rules
- Deterministic or model-based enforcement method
- Last semantic review date

A mandatory tribal requirement remains mandatory even though it is not explicitly documented.

### Implementation Model Convention:

The provider contains three concurrent implementation models. They must not be treated as interchangeable.

- `Legacy` means the function-based untyped Plugin SDK model used by most existing resources and data sources. Maintain this model for existing files unless the task explicitly includes migration.
- `Typed` means the receiver-based `internal/sdk` model. Published contributor guidance currently makes this the default for new ordinary resources and data sources.
- `Framework` means the newest framework-native direction. Current first-class framework surfaces include list resources, ephemeral resources, and provider-defined functions; future migrations may extend framework ownership without retroactively changing the model of existing files.

Review rules must declare which models they apply to. Reviewers must classify the changed file before applying model-specific lifecycle, schema, state, or callback guidance. The existence of newer typed or framework code in the same service does not authorize incidental migration of legacy or typed files.

This model hierarchy combines published upstream typed-versus-untyped guidance with direct maintainer confirmation of the framework migration direction. The catalog therefore records both published upstream and confirmed maintainer provenance where one rule describes the complete three-model boundary.

### Oxford Comma Requirement:

The Oxford comma rule is the reference case for this distinction.

- Requirement: use the Oxford comma for every documentation prose list of three or more items.
- Requirement level: mandatory.
- Provenance: confirmed maintainer convention.
- Documentation gap: yes.
- Evidence: direct HashiCorp maintainer clarification and consistent examples throughout contributor documentation.
- Runtime placement: hosted documentation contract.

The Hosted Toolkit must not weaken this rule because the contributor standards demonstrate rather than explicitly state it.

### Published Template Convention:

The argument and attribute list-marker rule is the reference case for normative template evidence.

- Requirement: use `*` as the Markdown list marker for argument and attribute entries; do not use `-` for these entries.
- Requirement level: mandatory.
- Provenance: published upstream standard reinforced by direct maintainer confirmation.
- Documentation gap: no; the canonical contributor-guide examples and templates prescribe the required shape.
- Evidence: argument, block-argument, attribute, and block-attribute templates in HashiCorp contributor guidance, plus direct maintainer clarification that reviewers enforce the pattern.
- Runtime placement: hosted documentation contract.

The Hosted Toolkit must treat prescribed contributor templates as authoritative even when adjacent prose does not restate every formatting token as a `MUST` requirement.

## Candidate Migration Policy:

The current Interactive Toolkit contains useful migration evidence but is not the Hosted Toolkit runtime source.

### Independent Candidate Channels:

**The Hosted Maintenance Workflow Has Three Independent Semantic Intake Channels:**

- **Upstream contributor channel:** Review the contributor README and every indexed contributor topic for published standards, changed meaning, new requirements, and removed requirements.
- **Interactive knowledge channel:** Review every Interactive Toolkit rule for maintainer conventions, local safeguards, or cross-cutting review behavior that contributor documentation does not preserve.
- **Maintainer proposal channel:** Review instruction-style Markdown rules authored directly under `hosted_copilot/copilot-rule-catalog/maintainer-rules/` for missing Hosted behavior that neither other channel contains.

Maintainer proposal files are hand-authored source records, not runtime instructions. They remain outside the deployed package manifest. The collector validates their surface-specific IDs and required `Rule`, `Provenance`, and `Rationale` fields, hashes each normalized block, maps exact Hosted rule IDs, and generates structured candidate JSON. Maintainers never hand-author the generated candidate or assessment JSON.

The first Interactive baseline contains 349 active rules. All 349 must receive a persisted intake decision, even when their contract family appears unrelated to Hosted review. Direct implementation, testing, and documentation rules should be reviewed first, followed by cross-cutting review rules and then workflow-specific families. Contract-family routing is a review order, not permission to silently exclude rules.

The Interactive rule catalog provides stable IDs, contract ownership, lifecycle, hashes, provenance, and source mappings. The hand-authored Interactive contracts remain authoritative for rule wording. Intake tooling must include the exact contract rule block in semantic evidence rather than treating the catalog title as complete rule text.

### Hosted-Owned Intake Ledger:

`hosted_copilot/copilot-rule-catalog/interactive-intake-ledger.json` records the latest approved decision for each reviewed Interactive rule. Supported durable decisions are `equivalent`, `included`, `excluded`, and `deferred`. Each record must preserve source identity and hash, lifecycle status, rationale, review date, mapped Hosted rule IDs, and the evidence-backed selection factors used for the decision.

An unchanged source content hash keeps the prior decision current. A new rule, changed content hash, or lifecycle transition reopens semantic review. The ledger is Hosted-owned maintenance evidence, is not runtime guidance, and must not be installed into the target provider repository.

Normal Hosted validation may validate the ledger schema and internal references, but it must not compare the ledger with the current Interactive Toolkit automatically. Interactive comparison is an explicitly invoked maintenance audit so changes to one toolkit do not block or mutate the other.

### Impact-Weighted Selection:

Eligibility requires Hosted applicability, actionable or foundational value, sufficient evidence, and no material duplication by stronger Hosted behavior. Eligible candidates are rated from zero through five for severity, frequency, breadth, Hosted detectability, evidence strength, false-positive risk, and redundancy.

The AI semantic review pass owns eligibility analysis, factor ratings, and selection rationale. The maintainer reviews these outputs and owns the final disposition and approval, but does not edit factor values in the Workbench. Disagreement with an assessment requires deferral or a new AI assessment rather than an untracked manual score change.

**Calculate Impact As:**

$$
\operatorname{impact}=\max(0,6S+3F+3B+4D+4E-5R-3O)
$$

**For a Positive Guarded Token Delta, Calculate Token Efficiency As:**

$$
\operatorname{efficiency}=100\times\frac{\operatorname{impact}}{\operatorname{guardedTokenDelta}}
$$

Store the factor ratings and rationale, then derive impact and efficiency. Use these values to order candidates and explain limited-capacity tradeoffs, never to make an automatic inclusion or retirement decision. Foundational safeguards may use an explicit maintainer-approved override when their primary value is improving the reliability of many other rules; overrides do not bypass evidence, token projection, or final approval.

### Hosted Rule Workbench:

The Hosted Rule Workbench is the maintainer-facing orchestration layer for semantic intake and promotion. It uses familiar catalog, comparison, selection, running-total, and confirmation patterns without presenting rules as commercial products.

The Workbench supports laptop and desktop browsers only. Handset-width viewports and browsers that identify as mobile must display an unsupported-device screen instead of loading the review workspace or initializing persisted draft state.

`Start-RuleWorkbench.ps1` invokes the deterministic collector and incremental semantic assessor, stages the static Workbench with the completed bundle in an external temporary directory, and serves it from a stable loopback origin. The catalog-owned baseline under `hosted_copilot/copilot-rule-catalog/rule-assessments/` supplies source- and Hosted-catalog-bound assessments to every checkout. `Invoke-RuleIntakeAssessment.ps1` resolves each candidate through machine-local context cache, committed baseline, and finally the local Copilot CLI. A new checkout therefore evaluates only candidates that changed after the committed baseline rather than rebuilding the complete assessment set.

The local cache context includes the Hosted catalog hash, evaluator contract hash, model, and reasoning effort. Each source-specific model batch runs from an isolated temporary directory containing only its candidate packet, current Hosted catalog, and assessment schema; Copilot receives only the read-only `view` tool, returns structured JSONL, and must report the configured model. The command schema-validates every response, retries malformed output within a fixed bound, writes cache and bundle artifacts outside the repository, and never applies catalog or ledger changes. Supplying `BundlePath` directly to the assessor bypasses collection but still resolves assessments; supplying it to the Workbench launcher stages that already completed bundle without invoking the assessor.

This is maintainer-invoked experiment support, not unattended semantic synchronization. A changed Interactive rule or upstream document invalidates only its matching baseline and cache entries when the remaining context is unchanged. A changed Hosted catalog invalidates the shared baseline because every equivalence judgment used that catalog; evaluator-contract, model, or reasoning changes invalidate the narrower local cache context. `Publish-RuleIntakeAssessmentBaseline.ps1` previews by default and updates the shared baseline only with explicit `-Publish` after a maintainer accepts a complete assessed bundle. The server binds only to `127.0.0.1`, serves static files through `GET` and `HEAD`, exposes no repository-write API, and uses a stable default port so browser storage remains available across launches. **Close Workbench** sends the sole mutating request, a per-launch-token-authenticated `POST /shutdown` that stops only the local server process. A port override creates a different browser-storage origin and must be reported clearly.

The Workbench uses IndexedDB for review bundles, read-only AI assessments, maintainer decisions, provisional applicability overrides, evidence notes, and resumable drafts. Local storage holds only lightweight preferences and the active session identifier. Each persisted decision, assessment, and override is keyed to source identity and content hash; changed source content reopens the candidate instead of inheriting stale analysis. Draft schema version 3 stores a mutually exclusive rule action, independent promotion-plan membership, and source-bound provisional overrides; unreleased earlier draft shapes are rejected rather than migrated. Maintainers can export and import current draft state independently from browser storage.

Semantic evaluation completes before a candidate enters either Workbench tree. Do not show an unevaluated candidate or synthesize placeholder scores. Directly below the shared search toolbar, a tab control switches between complete **Candidate Sources** and **Assessment Results** child workspaces. The search toolbar queries only the dataset owned by the selected tab. **Candidate Sources** contains AI-applicable candidates plus candidates provisionally reincluded by a maintainer and is the sole source for decisions and promotion-plan membership. Within Candidate Sources, connected **Candidates** and **Details** tabs replace one full-width view with the other. Candidate activation opens Details; returning to Candidates preserves tree expansion, selection, sorting, and scrolling; Details without a selection displays a **Select a candidate** empty state. **Assessment Results** uses the same always-visible nested-tab model: connected **Assessments** and **Details** tabs replace one full-width pane with the other at every supported viewport. Activating an assessment row opens Details, returning to Assessments preserves selection and row highlighting, and Details without a selection displays **Select an assessment result**. Applying a provisional override removes that row from active exclusions while preserving the original assessment and override record in persisted audit data.

On desktop, keep the top bar and left stage rail fixed to the viewport. Within Catalog, keep metrics, search, outer workspace tabs, and the Candidates/Details tabs fixed while only the active candidate tree, assessment-result list, or detail form scrolls. Within Promotion Plan, keep the page header and Plan Projection fixed while the candidate table owns vertical and horizontal scrolling with sticky column headings. Within Preview, keep the page header and Draft Summary fixed while one right-hand review container scrolls Proposed Changes, Payload Changes, and Raw Selection Payload together. Below the desktop breakpoint, retain the document-flow responsive layout instead of forcing nested fixed-height regions.

Both outer tab children organize results beneath non-selectable **Interactive Toolkit**, **Contributor Guidance**, and **Maintainer Proposals** source roots. Switching outer tabs changes visibility only and preserves each tab's folders, selection, sort state, scroll position, rendered detail, and independent search query. Candidate-list column headers belong to each row-bearing subsection rather than floating globally above unrelated folders. Candidate Sources headers sort only their owning subsection, use compact labels, and default to Candidate ascending with a visible direction chevron. Assessment Results headers remain informational and are not sortable. Interactive and maintainer rules retain navigation-only category folders in the candidate view, while Contributor Guidance rules are direct children of their source root. Each eligible candidate shows source lifecycle and authoritative Hosted catalog status separately. `Mapped` means the bundle identifies one or more active Hosted rules; `Retired mapping` means only retired Hosted rules remain; `Not mapped` means no authoritative mapping exists. In Tokens, unsigned values show current guarded usage and signed values show an explicit action's estimated delta. When an overridden exclusion has no AI-generated token delta, estimate its maintained proposed text with the same guarded character-quarter method for Candidate, Details, Plan, and capacity displays. The eligible-tree checkbox controls only promotion-plan membership and never infers an action. Clicking or keyboard-activating a candidate row opens its complete source rule and AI assessment in the full-width Details view without changing plan membership or collapsing the tree. When a candidate or assessment-result row has focus, Up and Down Arrow move selection and focus to the previous or next visible row, clamp at list boundaries, and scroll the target into view. Folder summaries retain native disclosure-key behavior, and focused promotion-plan checkboxes retain native checkbox-key behavior.

An authenticated Hosted CODEOWNER can provisionally contest an AI exclusion from Assessment Results. The launcher resolves the current GitHub CLI identity and applicable CODEOWNERS entry; ordinary read-only use remains available when identity validation fails, while override controls fail closed with an actionable reason. A provisional override records the original and effective applicability, required rationale, authenticated GitHub login, timestamp, and source-content SHA-256 without mutating the AI assessment. Applying it atomically removes the row from active Assessment Results, adds it once to the dedicated **Overrides** group, and creates an unresolved in-plan decision without inferring Add, Update, or Retire. Undo, uncheck, and Remove Override atomically remove the override and decision, return the row to active exclusions, and clear stale selection highlights; Restore reinstates both records. Draft import and export plus the hash-bound approval selection carry the override. This is transparent trusted-maintainer discretion, not tamper-proof two-person enforcement; normal pull request review remains the governance layer and the future promotion planner must persist the override in its audit artifacts.

**The Workbench Presents One Guided Process:**

- **Catalog:** Search evaluated upstream and Interactive candidates, compare source lifecycle with Hosted catalog status, add selected actions to the promotion plan with leaf checkboxes, track the plan count, and open candidate details independently without rebuilding expanded tree folders.
- **Assessment:** Display the complete source rule, exact mapped Hosted rule IDs, text and placement, separate related-coverage analysis, AI recommendation, impact description, token cost, projected headroom, all factor ratings, selection rationale, and proposed wording. The maintainer chooses one status-constrained action and records rationale. Unmapped candidates allow no change, add, exclude, or defer; mapped candidates allow no change, update, retire, or defer. AI recommendation remains advisory and every new maintainer decision begins at no change.
- **Promotion plan:** Collect every checked candidate independently from Rule Action. Mark selected `No Change` items as **Needs action**, route that control directly to Rule Actions, and require an explicit Add, Update, or Retire plus rationale before approval. Per-row Undo removes the complete saved decision and any provisional override so action, rationale, proposed text, membership, list placement, and selection return to defaults; immediate Restore reinstates the full decision and override snapshots from the notification.
- **Capacity:** Show current and projected guarded tokens, remaining capacity, utilization, impact, and token efficiency for every affected surface.
- **Preview:** Render every planned add, update, and retirement as a GitHub-style unified rule diff with green additions, red removals, neutral context, line numbers, and action context. Compare only changed selection-payload fragments side by side against default Workbench selection state, and retain the complete raw selection JSON in a collapsed audit disclosure. Highlight and navigate complete in-plan Add, Update, and applicability-override records in the raw payload. Do not offer or retain an `update` action when current and proposed Hosted rule text are identical.
- **Approval:** On Preview, require selected-rule rationale and manual approver identity before **Approve & Export** freezes the exact selection payload, calculates its SHA-256 hash, and exports an immutable approval handoff. Any later selection or rationale change requires a new handoff.

Browser state is resumable working state, not repository authority. The current Workbench exports a hash-bound approval handoff, not a repository-ready promotion plan, and exposes no write endpoint. The future promotion planner must resolve section placement, rule IDs, generated-output hashes, source-baseline decisions, regression changes, and staged validation before producing the complete promotion plan. `Invoke-RulePromotion.ps1` must independently validate that plan, recompute its exact file-byte hash, verify source snapshots and repository preconditions, recreate the preview, and apply only that plan. It must fail before writing when any source, catalog, ledger, generated output, regression input, or expected hash has changed.

### Atomic Promotion And Audit:

A promotion is one coherent repository change containing approved catalog rules, section mappings, ledger decisions, accepted source baselines, required regression assets, and generated instructions. Source baseline acceptance must identify the semantic decision that authorizes it; a digest change alone is never sufficient.

The promotion command stages all outputs outside the repository, validates the complete staged Hosted Toolkit, and only then replaces the approved repository files. If staging or validation fails, the repository remains unchanged. After successful replacement, it reruns complete Hosted validation. A post-write failure is reported as an incomplete promotion requiring maintainer intervention; the command must not silently roll back or overwrite concurrent work.

Every successful promotion adds one immutable receipt under `hosted_copilot/copilot-rule-catalog/audit/`, named with its UTC timestamp and promotion-plan hash. The receipt records the plan hash, approver attribution and method, source snapshot hashes, decisions and selection factors, Hosted rule IDs and section placement, before-and-after catalog and generated-output hashes, token reports, regression assets, validations, and outcome.

Locally entered or Git-configured identity is attribution, not cryptographic authentication. Capture authenticated GitHub identity when available and label manual identity honestly. Git commit authorship and pull request approval remain the strongest final review evidence. Receipts are Hosted-owned maintenance history, never runtime payload.

**Initial Candidate Groups:**

- Published upstream rules are baseline candidates.
- Confirmed and inferred maintainer conventions are tribal-knowledge candidates.
- Local safeguards require individual review because many protect Interactive Toolkit orchestration and do not apply to hosted review.
- Rules without provenance require classification only when selected for hosted migration.

**Selection Should Favor Rules That Are:**

- Mandatory or high-impact
- Supported by durable evidence
- Likely to identify actionable defects
- Concise enough for hosted execution
- Applicable across the provider rather than one historical resource
- Not already enforced more reliably by deterministic tooling

Do not migrate Interactive Toolkit role machinery, transport schemas, prompt mechanics, or presentation requirements.

## Maintenance Pipeline:

The hosted source-maintenance flow should be deterministic until semantic judgment is required.

- Track the contributor README and every contributor topic it indexes, independently from whether an active Hosted rule currently cites that document.
- Pin each tracked upstream source to a recorded content digest.
- Pin the reviewed upstream source set to one immutable baseline commit so changed documents have reproducible before text.
- Discover upstream source drift through a PowerShell maintenance command.
- Report changed sources, affected rule mappings, untracked contributor topics, and stale catalog topics.
- Build a read-only semantic-review bundle containing changed upstream text, complete Interactive rule blocks requiring review, current Hosted mappings, and source hashes.
- Classify Interactive candidates as new, changed, retired, deferred, or current by comparing the current catalog with source-hashed ledger decisions.
- Regenerate candidates by restarting the Workbench or invoking the collector and assessor directly; do not expose a browser refresh action that cannot rebuild the server-staged bundle.
- Classify candidates through AI-assisted semantic review and calculate impact, guarded token delta, token efficiency, and projected remaining capacity.
- Stop for explicit maintainer approval before changing source baselines, intake decisions, normalized rules, generated instructions, or regression expectations.
- Do not rewrite normalized rules solely because a digest changed.
- Require a maintainer to decide whether the changed prose alters rule meaning.
- Update approved normalized rules manually.
- Generate compact runtime instructions deterministically from the normalized rule records.
- Validate generated files against committed output.
- Measure each generated surface against its token budget.
- Validate rule IDs, required metadata, source links, duplicate mappings, and conflicting requirements.
- Update `package-manifest.json` only when the hosted package intentionally adds, removes, or relocates an owned path.
- Preview deployment with `Install-Toolkit.ps1` in dry-run mode before writing to a target repository.
- Require review of rules whose evidence disappeared or whose upstream source was renamed or removed.

The scripts own drift detection, validation, and rendering. They do not own semantic interpretation or baseline acceptance.

## Deterministic Enforcement:

Rules that can be checked reliably without model reasoning should use scripts, linters, or CI.

**Examples Include:**

- Generated-file freshness
- Token-budget limits
- Rule schema validation
- Provenance and evidence completeness
- Tracked-source digest changes
- Complete contributor-topic catalog coverage
- Interactive intake-ledger schema, decision completeness, selection factors, and Hosted rule-reference validity
- Read-only semantic-review bundle generation
- Structured current and projected token-budget reporting
- Deterministic impact and token-efficiency calculations
- Duplicate stable rule IDs
- Forbidden dependencies on Interactive Toolkit files
- Required frontmatter and supported hosted paths
- Formatting checks with established low false-positive behavior

Semantic checks remain in the compact runtime contracts.

## Head-Branch Trust Boundary:

Hosted GitHub review reads repository instructions, agent instructions, and skills from the pull request head branch. A contributor can therefore change the guidance used to review the same pull request.

**Required Protections:**

- Add hosted instruction, skill, rule-source, generator, and validation paths to `CODEOWNERS`.
- Require human approval for every change to those paths.
- Treat pull requests changing hosted AI policy as security-sensitive maintenance changes.
- Do not rely on Copilot's review of a pull request that changes the instructions governing that review.
- Validate generated output in required CI.
- Consider organization-level guidance for immutable trust rules when the repository owner controls that surface.

These controls reduce accidental or malicious policy weakening but do not make head-branch instructions an immutable authority.

## Hosted Review Output:

The Hosted Toolkit should optimize for native inline comments.

**Each Finding Should Contain:**

- The concrete problem
- The observable effect or risk
- A specific correction
- The stable hosted rule ID
- A source link only when it materially helps the contributor understand the requirement

The review should not emit Interactive Toolkit handoff records, frozen finding sets, moderation metadata, or pending-review plans.

Because hosted Copilot cannot interact with human replies as a continuation of the review, challenges and adjudication remain human review activities outside this profile.

## Existing Feedback:

The hosted review skill should inspect existing pull request feedback through GitHub context when available and suppress materially equivalent comments.

**This Is a Best-Effort Safeguard Rather than a Platform Guarantee:**

- GitHub documents that re-reviews may repeat resolved or downvoted feedback.
- MCP and agentic context use may vary by review.
- The profile should not claim deterministic deduplication unless a separate required tool proves it.

Regression evaluation should measure duplicate-comment behavior explicitly.

## Validation and Regression:

The Hosted Toolkit should own a separate validation and regression system.

**Minimum Validation:**

- Source-rule schema validation
- Generated-output reproducibility
- Per-surface token-budget enforcement
- No references to Interactive Toolkit runtime paths
- Supported hosted frontmatter and glob validation
- Markdown lint
- Source-drift reporting
- Policy-file CODEOWNERS coverage

**Minimum Regression Corpus:**

- Known implementation defects
- Known acceptance-test defects
- Known documentation defects
- Mandatory tribal-rule violations, including Oxford comma cases
- Clean changes that should produce no comment
- Duplicate existing-review feedback
- Large pull requests that exercise context limits
- Pull requests that modify hosted customization files

Hosted evaluation must score both defect recall and false positives. A smaller contract is successful only if it remains useful and defensible under the hosted budget.

### Controlled Comparative Evaluation:

**The Historical Hosted-Review Experiments Compared Two Instruction Profiles:**

- `Contribution Guide`: contributor documentation plus a focused review skill
- `AI Toolkit`: the adapted toolkit instruction and skill package

Six paired test cases used the same head branch, changed-file set, and commit tip across both profiles. However, every pair used different model or reasoning labels. Those runs demonstrate useful test-case reuse, but they cannot isolate instruction-profile effectiveness from model capability.

PR-title labels such as `[AI Toolkit][gpt-5.6-sol-xhigh]` are manually maintained experiment metadata. They are useful historical evidence but are not authoritative runtime attribution unless corroborated by a debug log or another product-generated record.

[GitHub's model usage documentation](https://docs.github.com/en/copilot/concepts/agents/code-review#model-usage) states that Copilot code review uses a product-controlled mix of models and that model switching is not supported. [GitHub's review effort documentation](https://docs.github.com/en/copilot/concepts/agents/code-review#review-effort-level) identifies `Lite` and `Balanced` as the supported user-facing control and explains that `Balanced` routes reviews to a higher-reasoning model. The hosted test design must therefore control review effort and record the underlying model as observed metadata when it is available.

**[GitHub's Review-Request Documentation](https://docs.github.com/en/copilot/using-github-copilot/code-review/using-copilot-code-review#choosing-a-review-effort-level) Explains How the Effective Review Effort Is Selected:**

- For a manual review on GitHub.com, the person requesting Copilot review selects `Lite` or `Balanced` under **Copilot** in the pull request's **Reviewers** section.
- For automatic reviews, an organization owner or repository administrator can set the default review effort.
- A repository administrator can override the organization default for that repository.
- The pull request overview produced after review identifies the effort level used for that run.

Review effort is a request or repository-policy control; it is not a direct model selector. A user with read-only repository access cannot configure the automatic-review default, although they may be able to choose an effort when manually requesting a review if repository policy and their Copilot access permit it.

#### Owner and Administrator Controls:

GitHub does not provide an organization or repository setting for selecting a default LLM for Copilot code review. Organization and repository owners must not treat the Copilot **Models** settings as a code-review model selector; GitHub's model usage documentation states that those settings control Copilot Chat and that code review may use other product-selected models.

**The Word "Owner" Has Two Distinct Meanings in This Configuration:**

| Repository Ownership | Who Controls the Automatic-Review Effort | Effective Behavior |
| --- | --- | --- |
| **Personal-Account Fork** | The personal account owner, acting as repository administrator | Sets `Lite` or `Balanced` in the fork's repository settings; there is no organization default |
| **Organization-Owned Fork** | The organization owner sets the organization default; a repository administrator can set a fork-specific override | The repository setting overrides the organization default |
| **Repository Where the User Has `READ` Access Only** | Neither role is available to that user | The user can inspect committed files but cannot change the automatic-review default |

**The Configuration Paths Are:**

- **Organization Default:** Open the organization's **Settings**, select **Copilot**, then select `Lite` or `Balanced` next to **Review effort level**, as described in [Configuring review effort level for an organization](https://docs.github.com/en/copilot/how-tos/copilot-on-github/set-up-copilot/configure-automatic-review#configuring-review-effort-level-for-an-organization).
- **Repository or Personal-Fork Setting:** Open the repository's **Settings**, select **Copilot**, then select `Lite` or `Balanced` next to **Review effort level**, as described in [Configuring review effort level for a repository](https://docs.github.com/en/copilot/how-tos/copilot-on-github/set-up-copilot/configure-automatic-review#configuring-review-effort-level-for-a-repository).

A fork's permissions and settings are independent of its upstream repository. Access to one does not grant administrative access to the other, and being named in `CODEOWNERS` does not grant repository permissions.

This effort setting affects all automatic Copilot reviews. A person requesting a manual review selects the effort for that request in the pull request's **Reviewers** section. **In both cases, GitHub retains control of the underlying LLM model routing.**

**For Each Comparison:**

- Keep `control-base` immutable as the control baseline and keep `hosted-base` immutable as the Hosted baseline
- Author synthetic changes as repository-shaped content trees or import canonical diffs from real AzureRM pull requests
- Keep `test-content` as an immutable source-PR base at the pinned Control commit, and mirror each source PR diff into separate Control and Hosted review heads
- Reject `.github/` test changes and guard all writes to the authenticated user's personal AzureRM fork
- Apply the same canonical test change and verify an identical changed-file set and diff hash against `control-base` and `hosted-base`; the resulting commits have different SHAs because their parents differ
- Use the same review effort, repository settings, MCP configuration, memory setting, and review trigger
- Request paired reviews within the same test window to reduce product-version drift
- Run multiple independent review attempts for each profile because model output is nondeterministic
- Capture the instruction-profile commit, test-change commit, diff hash, review effort, timestamp, and hosted-review runtime version
- Capture model name and reasoning level when product-generated logs expose them
- Treat the matched `Running Copilot Code Review` Actions log as product-generated model evidence; record its hash, configured primary model, every instantiated model session and its `clientName` role, configured-only auxiliary models, runtime version, `MaxPromptTokens`, memory and skill counts, and deduplication statistics
- Attribute the review to the instantiated `github/copilot-code-review` session; do not treat deduplication or configured-only grouping, curation, and severity models as the primary reviewer
- Record requested review effort and internal session reasoning separately; `Lite` does not imply a matching `ReasoningEffort` label
- Preserve review evidence when Actions-log parsing is incomplete; record `partial` or `unavailable` runtime status with explicit diagnostics and do not claim direct model attribution
- Record a title-supplied model label separately with evidence source `pr_title`
- Use `unknown` when model identity is unavailable rather than inferring it
- Classify a direct pair as model-confounded when model or reasoning evidence differs
- Score expected findings, unexpected findings, duplicate findings, and missed findings without using the profile label during adjudication
- Use fresh pull requests for every independent run so previous-feedback deduplication cannot suppress new candidates
- Use one persistent `control-base` and `hosted-base` pair for a fixed provider commit, Hosted package, and case set; create and delete only disposable paired heads for each run
- Use the Hosted lifecycle commands and generated pair record instead of manual branch and pull request choreography

**Comparative Reports Must Separate:**

- Same-model and same-reasoning comparisons, which can support a direct instruction-profile conclusion
- Unknown-model comparisons, which can support aggregate observations only after repeated paired runs
- Known cross-model comparisons, which remain historical evidence but cannot establish that one instruction profile is more effective

**The Hosted Regression Record Should Include:**

- `instruction_profile`
- `instruction_profile_commit`
- `fixture_id`
- `fixture_commit`
- `diff_hash`
- `review_effort`
- `model_name`
- `reasoning_level`
- `model_evidence_source`
- `hosted_review_runtime_version`
- `runtime_evidence`
- `reviewed_at`
- `expected_findings`
- `actual_findings`
- `duplicate_findings`
- `unexpected_findings`
- `missed_findings`
- `comparison_status`

This metadata belongs to the Hosted Toolkit regression system and must not be added to the Interactive Toolkit regression schema.

**Generated Experiment Evidence Remains Local:**

- `hosted_copilot/regression/raw/` stores complete GitHub API captures and profile-blinded adjudication views.
- `hosted_copilot/regression/results/` stores schema-valid paired result records after adjudication.
- Both directories are Git-ignored because they are generated experiment state available in the maintainer's local checkout.
- The schema, capture tool, validation tool, controlled cases, and final experiment conclusion are checked in.
- Hosted validation validates local result records when present and succeeds with zero records in a clean clone.

### Repository Validation Dispatch:

Profile validators must remain deterministic and validate their complete owned profile when called directly. They must not inspect the changed-file set and silently exit or route execution to a different product profile. Temporary delegation between compatibility entrypoints for the same profile is allowed during command migration.

**The Repository Uses `tools/Validate-ChangedToolkits.ps1` for Change-Aware Local and CI Validation:**

| Changed Ownership | Required Validation |
| --- | --- |
| Interactive Toolkit only | Run `tools/Validate-InteractiveToolkit.ps1` |
| Hosted Toolkit only | Run `hosted_copilot/tools/Test-Toolkit.ps1` |
| Both toolkits | Run both profile validators and report both results |
| Repository maintenance only | Run shared repository checks without requiring either product validator or product changelog |
| Shared path | Run both profile validators plus applicable shared checks |
| Unclassified path | Fail closed and require an explicit ownership decision |

**The Ordered Ownership Map in `tools/toolkit-ownership.json` Classifies:**

- Interactive Toolkit runtime paths owned by `installer/file-manifest.config`, its installer, regression harness, and Interactive Toolkit maintenance surfaces
- The complete `hosted_copilot/**` tree and this architecture document as Hosted Toolkit paths
- `AGENTS.md` and other explicitly designated maintainer-only files as repository maintenance
- Shared configuration and dispatcher files that can affect both toolkits as shared paths
- Shared repo-local validation presentation modules and contract tests that affect both maintenance profiles

**When Both Toolkits Change, the Dispatcher Must:**

- Run both validators even if the first validator fails
- Preserve separate validation results and diagnostics for each toolkit
- Fail the combined check if either required validator fails
- Require independent changelog decisions for both toolkits
- Avoid creating a deployment dependency between the toolkits

During migration, `tools/Validate-InteractiveToolkit.ps1` delegates to the existing `tools/validate-ai-toolkit.ps1` implementation. After the implementation moves to the canonical entrypoint, the existing path should remain as a compatibility wrapper until all documented and CI callers migrate.

### Deployment and Changelog Ownership:

**The Two Toolkits Have Independent Changelog and Distribution Models:**

- Root `CHANGELOG.md` and `installer/VERSION` belong to the Interactive Toolkit
- `hosted_copilot/CHANGELOG.md` tracks Hosted Toolkit development and deployment history
- The Hosted Toolkit has no separate `VERSION`, release bundle, archive, or publication workflow under the current source-deployment model
- Repository-maintenance-only changes require neither product changelog by default
- Interactive Toolkit changes require an Interactive Toolkit changelog update or an explicit Interactive Toolkit waiver
- Hosted Toolkit changes require a Hosted Toolkit changelog update or an explicit Hosted Toolkit waiver
- Mixed changes require independent decisions for both changelogs
- Shared changes require both changelog decisions when they affect both product runtimes or deployment behavior

The dispatcher accepts separate waiver inputs: `-InteractiveChangelogNotRequired` with `-InteractiveChangelogReason` and `-HostedChangelogNotRequired` with `-HostedChangelogReason`. A waiver for one toolkit must never satisfy the other toolkit's changelog gate.

Combined validation is a repository convenience, not a combined distribution gate. The Interactive Toolkit remains versioned, packaged, and released; the Hosted Toolkit remains directly deployed, independently validated, and recoverable from its source commit, ownership-manifest hash, and installed file hashes.

## Rollout Direction:

### Design and Inventory:

- Inventory customization files in the target provider fork.
- Measure the exact hosted payload currently loaded for implementation, tests, and documentation.
- Identify the target repository and ownership model for hosted source rules and generated files.
- Confirm CODEOWNERS and required-check capabilities.

### Rule Curation:

- Select the smallest useful upstream baseline.
- Inventory confirmed and inferred maintainer conventions.
- Classify selected unprovenanced rules.
- Exclude Interactive Toolkit orchestration safeguards.
- Record mandatory documentation gaps explicitly.

### Generation and Validation:

- Define the normalized rule schema.
- Implement the PowerShell drift, generation, and validation commands.
- Generate the isolated hosted runtime profile.
- Add token-budget and dependency-boundary checks.
- Maintain `Test-Toolkit.ps1`, Hosted Toolkit changelog validation, and phase-aware runtime gates as the Hosted Toolkit develops.
- Maintain the repository-level changed-toolkit dispatcher, explicit ownership map, and routing self-test.
- Migrate the Interactive Toolkit validator implementation to its canonical entrypoint while preserving the existing compatibility entrypoint.

### Hosted Evaluation:

- Test the profile on controlled pull requests in the fork.
- Compare findings against known expected issues.
- Run paired profile comparisons using identical test changes and review effort.
- Capture model and reasoning evidence when available and mark mismatched pairs as confounded.
- Measure context use, duplicate feedback, false positives, and missed defects.
- Reduce or refine rules before expanding the profile.

### Protected Adoption:

- Generate runtime instructions directly under `hosted_copilot/.github/`.
- Run `Install-Toolkit.ps1` in dry-run mode against the target repository.
- Review and resolve every reported destination collision before installation.
- Install the manifest-owned contents of `hosted_copilot/` into the target repository root without path transformation.
- Commit the copied `.github/`, `tools/`, and hosted documentation paths in the target repository.
- Require CODEOWNERS review for hosted policy changes.
- Enable hosted Copilot review with custom instructions.
- Monitor live reviews and update normalized rules through the isolated maintenance process.

## Open Design Decisions:

- The exact post-adoption mechanism for evolving the ownership manifest and installed-state schema.
- The explicit approval mechanism for first-install collisions and locally modified package-owned files.
- Whether GitHub publishes or support confirms which prompt components count toward `MaxPromptTokens`; until then, preserve the captured `110000` value and exact failure stage without asserting an exclusive system-message scope.
- Which deterministic provider checks can run within hosted review without consuming excessive setup time or context.
- Whether organization-level instructions are available for immutable trust-boundary guidance.
- The initial rule count and exact token budget for each surface after measurement in the target repository.
- The number of independent paired runs required before an unknown-model aggregate comparison is considered stable.
- How live hosted review outcomes are captured for regression without treating comments as automatically correct guidance.

## Success Criteria:

**The Design Is Ready for Implementation When:**

- The Hosted Toolkit and Interactive Toolkit ownership boundaries are explicit
- No Hosted Toolkit runtime dependency points into the Interactive Toolkit
- The changed-toolkit dispatcher handles Interactive-only, Hosted-only, shared, mixed, repository-maintenance, and unknown paths deterministically
- Interactive Toolkit and Hosted Toolkit changelog decisions and distribution models remain independent
- Each review surface has an approved token budget
- Selected rules have requirement strength, provenance, evidence, and runtime decisions
- The Oxford comma and other mandatory tribal requirements are preserved
- Source drift cannot silently rewrite rule meaning
- Hosted Toolkit installation can preview and detect collisions without invoking the Interactive Toolkit installer
- Hosted policy paths require human ownership review
- Hosted comparative results identify model-confounded and unknown-model runs instead of attributing every difference to instructions
- The target regression corpus can distinguish useful findings from false positives
