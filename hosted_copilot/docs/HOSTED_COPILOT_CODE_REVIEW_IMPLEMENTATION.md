# Hosted Copilot Code Review Implementation Guide:

This guide defines how to implement the Hosted Toolkit described in [`docs/HOSTED_COPILOT_CODE_REVIEW_ARCHITECTURE.md`](../../docs/HOSTED_COPILOT_CODE_REVIEW_ARCHITECTURE.md).

The architecture document remains authoritative for product boundaries, rationale, trust, budgets, and adoption criteria. This guide owns the implementation sequence and the concrete first-party GitHub repository shape used during the Experiment MVP.

## Implementation Boundary:

Build the Hosted Toolkit directly from GitHub's documented customization model. Do not copy, transform, or depend on customization files from prior experiments in another repository.

Prior experiments are evidence about prompt limits, review behavior, and evaluation design. They are not an implementation source, migration baseline, or package layout.

All Hosted Toolkit files must be authored beneath `hosted_copilot/`. Nothing in this guide changes the Interactive Toolkit runtime, installer manifest, release bundle, or validation ownership.

## First-Party GitHub Shape:

GitHub documents the following repository customization paths for Copilot code review:

- [Repository-wide custom instructions](https://docs.github.com/en/copilot/customizing-copilot/adding-repository-custom-instructions-for-github-copilot) use `.github/copilot-instructions.md`.
- Path-specific custom instructions use `NAME.instructions.md` files beneath `.github/instructions/`.
- Each path-specific instruction file begins with YAML frontmatter containing an `applyTo` glob.
- Repository-wide and every matching path-specific instruction file are combined for a reviewed file.
- [Agent skills used by code review](https://docs.github.com/en/copilot/using-github-copilot/code-review/using-copilot-code-review#mcp-servers-and-agent-skills) live beneath `.github/skills/`; a review-focused directory name and description improve relevance.
- Repository instructions, agent instructions, and agent skills are read from the pull request head branch.
- Custom instructions must remain enabled for Copilot code review in repository settings.

The Hosted Toolkit source must mirror those destination paths exactly:

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
  docs/
    HOSTED_COPILOT_CODE_REVIEW.md
    HOSTED_COPILOT_CODE_REVIEW_IMPLEMENTATION.md
    HOSTED_REVIEW_EXPERIMENT_RUNBOOK.md
  regression/
    README.md
    cases/
    schema/
    raw/
    results/
  tools/
    Capture-ReviewPair.ps1
    Close-ReviewPair.ps1
    Review.Common.psm1
    Import-PullRequest.ps1
    Initialize-ReviewBases.ps1
    Install-Toolkit.ps1
    New-ReviewPair.ps1
    Publish-TestCase.ps1
    Test-ReviewResults.ps1
    Test-Toolkit.ps1
    package-manifest.json
```

The relative path below `hosted_copilot/` is the destination path in the target repository. The implementation must not introduce a generated package directory, path-rewriting layer, Hosted release bundle, or Hosted version file.

## Experiment MVP Scope:

The Experiment MVP implements only the assets required to test whether compact Hosted guidance improves Copilot code review without reproducing the Interactive Toolkit.

**Implement During The Experiment:**

- Compact repository-wide review guidance
- Compact Go, acceptance-test, and documentation instructions
- Curated mandatory maintainer conventions identified from the Interactive Toolkit, including tribal knowledge, with each rule's requirement strength, provenance, and Hosted applicability reviewed before inclusion
- One review-focused agent skill
- A package manifest for exact deployment ownership
- A source-checkout deployment script with dry-run support
- Hosted structure, isolation, and token-budget validation
- Controlled test cases and result records for paired reviews
- User-facing Hosted setup and maintenance documentation

**Defer Until Adoption:**

- A normalized rule database
- Deterministic instruction generation
- Automated upstream contributor-document synchronization
- Production-scale regression infrastructure
- Hosted-specific CI rollout
- Versioned Hosted releases or archives

During the experiment, runtime instructions are curated source files and are frozen by Git commit. They must still preserve stable rule IDs and evidence traceability so successful rules can later move into normalized sources without changing their meaning.

## Runtime File Responsibilities:

### Repository-Wide Instructions:

`hosted_copilot/.github/copilot-instructions.md` contains only guidance needed for every Hosted review:

- Repository purpose and important evidence locations
- Actionable-defect threshold
- Evidence hierarchy
- Duplicate-feedback avoidance
- Concise inline-comment expectations
- Trust rules for Hosted customization changes
- Pointers to deterministic checks that are safe in the Hosted environment

Do not place detailed Go, test, or documentation requirements in this file.

### Go Instructions:

`hosted_copilot/.github/instructions/azurerm-go.instructions.md` uses:

```yaml
---
applyTo: "internal/**/*.go"
---
```

It contains compact, high-value rules that can identify correctness, compatibility, Azure API, Terraform state, schema, lifecycle, or provider behavior defects.

The Go instructions also apply to acceptance-test files. Shared Go requirements belong here and must not be repeated in the test supplement.

### Test Instructions:

`hosted_copilot/.github/instructions/azurerm-tests.instructions.md` uses:

```yaml
---
applyTo: "internal/**/*_test.go"
---
```

It supplements the Go instructions with acceptance-test-specific requirements. It focuses on lifecycle coverage, import behavior, assertion defects, unsafe execution claims, and established provider test patterns.

### Documentation Instructions:

`hosted_copilot/.github/instructions/azurerm-docs.instructions.md` uses:

```yaml
---
applyTo: "website/docs/**/*.html.markdown"
---
```

It contains published documentation requirements and mandatory confirmed maintainer conventions. Published requirements include canonical contributor-guide examples and templates when they prescribe the required documentation shape, including `*` list markers for argument and attribute entries. It must also include the Oxford comma requirement for documentation prose lists of three or more items.

### Review Skill:

`hosted_copilot/.github/skills/code-review/SKILL.md` defines one compact review procedure:

- Classify the changed file surface.
- Read the diff and nearest evidence needed to prove or disprove a concern.
- Apply the repository-wide and matching path-specific rules.
- Inspect existing review feedback when GitHub context makes it available.
- Suppress materially equivalent comments.
- Emit only actionable, line-addressable findings.
- Keep each comment concise and include the applicable stable rule ID.

The skill must not reproduce Interactive Toolkit roles, handoff schemas, frozen audits, moderation, presentation passes, or pending-review staging.

Mandatory requirements remain in path-specific instructions. Skill relevance is not a sufficient enforcement boundary.

## Guidance Budgets:

Use the architecture's conservative engineering budgets:

| Surface | Maximum budget |
| --- | ---: |
| Repository-wide guidance | `2K tokens` |
| Shared Go instructions | `8K tokens` |
| Test supplement | `4K tokens` |
| Documentation instructions | `8K tokens` |
| Review skill | `3K tokens` |
| Maximum combined guidance | `25K tokens` |

The Hosted validator must measure each runtime file and every applicable combined surface. A test file loads repository-wide, Go, test, and potentially relevant skill guidance; the combined check must reflect cumulative loading rather than validating each file in isolation.

Token measurement is an engineering guardrail, not a claim about GitHub's unpublished prompt-accounting implementation. The validator uses `character-quarter-estimate-25pct-v1`, based on Microsoft Learn's documented approximation that [one token is approximately four characters in English](https://learn.microsoft.com/azure/azure-functions/functions-bindings-openai-embeddings-input#usage). It calculates the raw estimate as `ceiling(character count / 4)`, applies 25% safety headroom as a local safeguard, and compares the guarded estimate with each budget. Microsoft also documents that [the specific tokenization method varies by LLM](https://learn.microsoft.com/dotnet/ai/conceptual/understanding-tokens), so text and JSON output report the estimator by name plus the raw and guarded values. This method has no external package dependency and does not claim to reproduce GitHub's undisclosed model tokenizer.

## Implementation Sequence:

### Phase One: Documentation Vertical Slice:

Create the smallest deployable review package:

- Repository-wide instructions
- Documentation instructions
- Review skill
- Initial package manifest
- Hosted installer dry-run
- Hosted validation for layout, isolation, frontmatter, and documentation-surface budget
- One controlled documentation test case with expected findings

This phase proves head-branch discovery, path matching, skill relevance, deployment, token measurement, and result capture on the best-bounded review surface.

### Phase Two: Go Review Surface:

Add compact Go instructions and controlled implementation test cases. Include only rules with clear defect impact and evidence support.

Extend validation to calculate the repository-wide plus Go plus review-skill budget.

### Phase Three: Acceptance-Test Surface:

Add the test supplement and controlled acceptance-test cases. Verify that test reviews load both Go and test instructions without duplicated rule meaning.

Extend validation to calculate the repository-wide plus Go plus test plus review-skill budget.

### Phase Four: Controlled Hosted Evaluation:

Deploy from the current source checkout into the writable test fork and run paired reviews:

- Use identical test changes and verify identical changed-file sets and diff hashes.
- Use the same review effort for each pair.
- Record the source commit and manifest hashes.
- Record observed model metadata and its evidence source when available.
- Mark comparisons with different or unknown models as confounded.
- Record expected findings, misses, duplicates, false positives, and unexpected findings.

#### Paired Branch And Pull Request Topology:

Pin the local fork's current `main` commit for the experiment. Point immutable `control-base` and `test-content` at that exact commit, then create `hosted-base` by installing and committing only the Hosted overlay on top of `control-base`. Author or import each canonical change on a source branch and open it as a pull request against `test-content`. For every run, mirror that source pull request's exact diff onto disposable Control and Hosted heads. Open the review pair only after their changed-file sets and diff hashes match.

| Experiment Path | Starting Point | Contents | Pull Request Target |
| --- | --- | --- | --- |
| Control base | Pinned local fork `main` | No Hosted overlay | None; unchanged control baseline |
| Hosted base | `control-base` | Hosted overlay and installed-state record only | None; unchanged Hosted baseline |
| Test-content base | Same pinned local fork `main` | No accumulated test changes | Target for canonical source PRs |
| Source PR | `test-case/...`, `imported-pr/...`, or another authoring branch | One canonical test change | `test-content` |
| Control review head | `control-base` | Source PR diff on `control-review/source-pr-<number>/<run>` | `control-base` |
| Hosted review head | `hosted-base` | Same source PR diff on `hosted-review/source-pr-<number>/<run>` | `hosted-base` |

```mermaid
%%{init: {"theme":"dark","themeVariables":{"fontFamily":"Segoe UI, Arial, sans-serif","fontSize":"14px","background":"#111418","primaryTextColor":"#e6edf3","lineColor":"#9da7b3"},"flowchart":{"htmlLabels":true,"wrappingWidth":600}}}%%
flowchart TB
  fork["Personal AzureRM fork"]

  subgraph bases["<b>Persistent base branches</b>"]
    direction LR
    controlBase["Immutable <b>control-base</b><br/>Pinned commit, no Hosted overlay"]
    hostedBase["Immutable <b>hosted-base</b><br/>Pinned commit plus Hosted overlay"]
    testContent["Immutable <b>test-content</b><br/>Pinned commit, source PR target"]
  end

  sourceHead["Source branch<br/><b>test-case/...</b> or <b>imported-pr/...</b>"]
  sourcePr["Canonical source PR<br/>head: source branch<br/>base: test-content"]
  mirror["Mirror source PR diff"]
  controlHead["<b>control-review/source-pr-&lt;number&gt;/&lt;run&gt;</b>"]
  hostedHead["<b>hosted-review/source-pr-&lt;number&gt;/&lt;run&gt;</b>"]
  controlPr["Control PR<br/>head: control-review<br/>base: control-base"]
  hostedPr["Hosted PR<br/>head: hosted-review<br/>base: hosted-base"]
  review["<b>Request GitHub Copilot review on both pull requests</b>"]
  compare["<b>Compare the review results:</b> Expected <b>findings</b>, <b>misses</b>, <b>duplicates</b>, <b>false positives</b>, and <b>unexpected</b> findings"]

  fork -->|"<b>branch</b>"| controlBase
  fork -->|"<b>branch</b>"| hostedBase
  fork -->|"<b>branch</b>"| testContent
  fork -->|"<b>Authored repo tests or imported PR changes</b>"| sourceHead
  sourceHead -->|"<b>head</b>"| sourcePr
  testContent -. "<b>base</b>" .-> sourcePr
  sourcePr --> mirror
  mirror -->|"<b>apply exact diff</b>"| controlHead
  mirror -->|"<b>apply exact diff</b>"| hostedHead
  controlBase -->|"<b>branch</b>"| controlHead
  hostedBase -->|"<b>branch</b>"| hostedHead
  controlHead -->|"<b>head</b>"| controlPr
  controlBase -. "<b>base</b>" .-> controlPr
  hostedHead -->|"<b>head</b>"| hostedPr
  hostedBase -. "<b>base</b>" .-> hostedPr
  controlPr --> review
  hostedPr --> review
  review --> compare

  classDef source fill:#142b1a,stroke:#3fb950,stroke-width:1px,color:#e6edf3
  classDef prerequisite fill:#332a16,stroke:#d29922,stroke-width:1px,color:#f0f3f6
  classDef canonical fill:#12355b,stroke:#58a6ff,stroke-width:2px,color:#f0f6fc
  classDef control fill:#17283a,stroke:#6cb6ff,stroke-width:1px,color:#e6edf3
  classDef hosted fill:#17283a,stroke:#6cb6ff,stroke-width:1px,color:#e6edf3
  classDef action fill:#332a16,stroke:#d29922,stroke-width:1px,color:#f0f3f6
  classDef result fill:#261f3d,stroke:#a78bfa,stroke-width:1px,color:#f0f3f6

  class fork source
  class controlBase,hostedBase prerequisite
  class testContent prerequisite
  class sourceHead,sourcePr canonical
  class mirror action
  class controlHead control
  class hostedHead hosted
  class controlPr control
  class hostedPr hosted
  class review action
  class compare result
  linkStyle default stroke:#9da7b3,stroke-width:2px
```

For each test, open two matching pull requests in the writable fork. The control pull request targets `control-base`, and the Hosted pull request targets `hosted-base`. Both pull requests must contain the same planned test change.

The control and Hosted test-change commits cannot have the same Git commit SHA because they have different parent commits. Equality means that both temporary source branches apply the same test change and that each pull request, measured against its corresponding base branch, has the same changed-file set and diff hash. The Hosted overlay must be inherited from `hosted-base`; it must not appear in the Hosted test pull request diff.

Before requesting either review:

- Verify `control-base` and `hosted-base` start from the same pinned local fork `main` commit.
- Verify `control-base` contains no Hosted package files.
- Verify `hosted-base` contains the manifest-owned files and installed-state record from the approved source commit.
- Author each synthetic case as a repository-shaped content tree and derive its changed-file set from Git.
- Import real pull request diffs only from HashiCorp's AzureRM provider or one of its forks.
- Reject test changes under `.github/` so a test cannot alter its own review configuration.
- Verify each temporary source branch changes only the test-case paths expected for its case.
- Verify the paired pull request diffs have identical changed-file sets and diff hashes.
- Open the control pull request against `control-base` and the Hosted pull request against `hosted-base`.
- Keep `control-base` and `hosted-base` unchanged for every repeated run in the comparison set.
- Apply the same review effort, repository settings, MCP configuration, memory setting, and review trigger.
- Request both reviews within the same test window.

#### Phase Four Automation:

Use `HOSTED_REVIEW_EXPERIMENT_RUNBOOK.md` and the lifecycle commands instead of creating branches and pull requests manually:

- `Initialize-ReviewBases.ps1` creates or verifies the three persistent bases.
- `Publish-TestCase.ps1` creates or updates a synthetic source PR against `test-content` and delegates mirror creation.
- `Import-PullRequest.ps1` creates or updates an imported source PR against `test-content` and delegates mirror creation.
- `New-ReviewPair.ps1` mirrors one source PR into Control and Hosted heads, proves patch equality, opens or synchronizes both pull requests, and writes the pair record.
- `Capture-ReviewPair.ps1` consumes the pair record and writes raw, blinded, and readable evidence.
- `Close-ReviewPair.ps1` requires captured evidence by default, closes both pull requests, and removes only disposable heads.

The commands enforce the following contract:

- Accept the pinned upstream commit, change source, run identifier, and review effort as explicit inputs.
- Create or verify immutable `control-base`, `hosted-base`, and `test-content` branches without rewriting existing experiment history.
- Deploy the Hosted overlay only to `hosted-base` through `Install-Toolkit.ps1`.
- Require each canonical source PR to target `test-content`, then apply its exact diff independently to Control and Hosted review heads.
- Guard every mutation so it can target only the authenticated user's writable fork of HashiCorp's AzureRM provider.
- Refuse to continue when changed-file sets or diff hashes differ.
- Push all three persistent bases and both temporary mirror heads, then open the control pull request against `control-base` and the Hosted pull request against `hosted-base` only after the pair passes validation.
- Record branch names, base and head commits, source commit, manifest hash, test-case identity, diff hash, pull request URLs, review effort, request timestamps, and observed model evidence.
- Resolve each review to one GitHub Actions run and record the Actions-log hash, configured primary model, instantiated primary and sub-agent sessions by `clientName`, configured-only auxiliary models, runtime version, `MaxPromptTokens`, memory count, loaded skills, and previous-feedback deduplication counts.
- Create fresh pull requests for each independent run because GitHub deduplicates new candidates against prior feedback on the same pull request.
- Keep review invocation and result capture separate from deployment approval.

Historical pull request titles are contextual evidence only. They do not select the Hosted review model and must not be treated as authoritative runtime metadata.

#### Phase Four Result Artifacts:

Reusable result infrastructure is checked in beneath `hosted_copilot/`: controlled cases under `regression/cases/`, the paired-result schema under `regression/schema/`, and capture and validation commands under `tools/`.

Generated evidence remains local to the maintainer checkout:

- `regression/raw/` contains pair records, complete GitHub captures, profile-blinded adjudication views, and readable summaries.
- `regression/results/` contains schema-valid paired result records after adjudication.
- Both generated directories are Git-ignored and must not be committed.
- `Test-ReviewResults.ps1` validates all local result records when present and succeeds with zero records in a clean clone.
- The final experiment conclusion and adoption rationale are checked in after evaluation; individual generated runs are not.

## Package Manifest Requirements:

`hosted_copilot/tools/package-manifest.json` owns the exact deployable file set.

The initial schema must support:

- A manifest schema version
- Deployable paths relative to `hosted_copilot/` and mirrored beneath the target repository root
- File ownership by the Hosted package
- A stable package identity for installed-state comparison

Phase One fixes these camel-case manifest properties:

- `schemaVersion`
- `packageIdentity`
- `installedStatePath`
- `files`

Each `files` entry is one relative path string. The same path resolves beneath `hosted_copilot/` for the source and beneath `RepoDirectory` for the destination; path rewriting is not supported.

The checked-in manifest is an ownership map and does not contain file hashes. The installer computes source hashes from the current checkout during dry run and installation. The generated installed-state record uses `schemaVersion`, `packageIdentity`, `commit`, `manifestHash`, and `files`; each installed file records its derived `targetPath` and verified deployed `hash`.

The manifest must not include the implementation guide, Hosted changelog, experiment test artifacts, or other maintainer-only files unless the target repository needs them to operate or maintain the installed Hosted Toolkit.

The installer and validator consume this shared schema rather than defining parallel interpretations.

## Installer Requirements:

`Install-Toolkit.ps1` runs from this source checkout and accepts an explicit target repository directory.

**Dry-Run Behavior:**

- Resolve all paths through the manifest.
- Report additions, updates, unchanged files, owned modifications, and unowned collisions.
- Write nothing to the target repository.
- Report the source Git commit when available.
- Exit nonzero for an invalid manifest, missing source, unsafe path, or unapproved collision.

**Install Behavior:**

- Merge into existing `.github/`, `tools/`, and `docs/` directories without replacing unrelated content.
- Create only manifest-owned destination files.
- Fail closed when an unowned destination already exists.
- Require explicit approval before replacing a collision or locally modified package-owned file.
- Compute source hashes from the current checkout and verify every copied file against its computed source hash.
- Record installed hashes and source commit for later ownership checks.

The Hosted installer must not call, import, overwrite, or otherwise depend on the Interactive Toolkit installer or `installer/file-manifest.config`.

## Validation Requirements:

`Test-Toolkit.ps1` remains the complete Hosted profile validator. As each phase is implemented, extend it to enforce:

- Required Hosted layout
- Valid instruction frontmatter and exact `applyTo` patterns
- Review-focused skill metadata
- Package-manifest schema and complete owned-file coverage
- Manifest source containment, existence, and hashability
- Installer-computed source and installed-state hash agreement
- No Interactive Toolkit runtime dependencies
- No Hosted `VERSION` or release bundle
- Per-file and cumulative token budgets
- Installer dry-run behavior against a temporary target
- Markdown validity
- Mermaid rendering with explicitly pinned, supported Mermaid CLI and Puppeteer versions
- Controlled test-case schema and result completeness
- Local result schema conformance and recomputed adjudication totals when result records are present
- Git-ignored raw captures, readable pair summaries, and result records with no generated evidence tracked in source

The validator must continue to distinguish design phase from runtime phase. Runtime gates become mandatory when `.github/` runtime assets or `package-manifest.json` appear.

Text output must use the same execution-state contract as the Interactive Toolkit one-shot validator:

- Report the Hosted purpose, deployment model, and current `DESIGN` or `RUNTIME` phase before executing checks
- Report each check transition with `[RUNNING]`, `[PASSED]`, `[FAILED]`, or `[SKIPPED]`
- Treat phase-dependent checks that do not apply as `SKIPPED`, not `PASSED`
- Report the duration of every executed check
- End with a check, status, and duration table plus detailed failure output when applicable

JSON output must suppress all progress and presentation text. It must return only the structured result containing the same overall status, purpose, deployment model, phase, check statuses, durations, and issues represented by text mode.

## Deployment And Repository Settings:

Use a writable fork for implementation and controlled evaluation. Deployment to another maintainer's repository requires that repository's owner or administrator to approve files and configure settings.

Before requesting a Hosted review:

- Deploy the overlay through the Hosted installer dry run and review every collision.
- Install only after the exact plan is approved.
- Commit the deployed files on the pull request head branch.
- Confirm custom instructions are enabled for Copilot code review.
- Select and record the review effort.
- Confirm any required agent skill and MCP settings are available.

GitHub's built-in MCP server is read-only for the current repository by default. Additional MCP tools are repository settings, not files owned by this overlay, and must be separately approved by a repository administrator.

## Experiment Acceptance Gates:

The Experiment MVP is complete only when:

- Documentation, Go, and acceptance-test reviews complete without the captured prompt-size failure.
- Every runtime path is first-party supported and manifest owned.
- The installer can preview and deploy without modifying unrelated target files.
- The Hosted validator passes all cumulative guidance budgets.
- Controlled comparisons use identical test-change diffs and review effort.
- Results distinguish useful findings, misses, duplicates, false positives, and model-confounded runs.
- The evidence supports an explicit decision to adopt, revise, or stop the Hosted Toolkit direction.

Passing the experiment does not automatically authorize production generation, synchronization, CI, or release machinery. Those remain adoption decisions.

## Naming Consistency And Immediate Next Step:

The Hosted package manifest, installed-state record, installer, and validator must reuse existing Interactive Toolkit terminology when an equivalent concept already exists. Equivalent concepts must not be renamed solely because they belong to the Hosted Toolkit. Introduce Hosted-specific terminology only when the direct source-deployment model has no Interactive Toolkit equivalent.

The following minimum vocabulary is fixed for the Hosted implementation:

| Concept | Shared term | Hosted use |
| --- | --- | --- |
| Target repository directory | `RepoDirectory` | Installer parameter and resolved deployment root |
| Manifest file location | `ManifestPath` | Path to `package-manifest.json` |
| Parsed manifest | `ManifestConfig` | Validated manifest data consumed by the installer and validator |
| Manifest-owned file | `Path` | Relative path mirrored from `hosted_copilot/` beneath `RepoDirectory` |
| Source file | `SourcePath` | Path beneath `hosted_copilot/` |
| Target file | `TargetPath` | Same relative `Path` beneath `RepoDirectory` |
| Source provenance | `Commit` | Git commit of the source checkout when available |
| Content integrity | `Hash` | SHA-256 value for source, target, and installed-state comparisons |
| Validation result | `Valid`, `Reason`, and `Issues` | Structured validation outcome and diagnostics |
| Operation result | `Success` | Structured installer outcome |
| Execution state | `Status` | `running`, `passed`, `failed`, or `skipped` check state |
| Check duration | `DurationSeconds` | Elapsed execution time for a validation check |

This table fixes shared conceptual terminology, not JSON property casing. The manifest schema must apply one consistent casing convention when its properties are implemented.

Hosted-only concepts with no Interactive equivalent, including the installed-state record, per-file package ownership, and installed hashes, may introduce new terms. Those terms must remain consistent between the manifest, installer, validator, and user-facing Hosted documentation.

Do not carry Interactive-only version, build-fingerprint, release-bundle, or archive terminology into the Hosted Toolkit. The Hosted Toolkit remains unversioned and source deployed.

With this naming convention established, the local Phase One documentation package, Phase Two Go package, and Phase Three acceptance-test package are implemented. The next step is Phase Four: deploy the approved source package into the writable test fork and run controlled Hosted evaluation. Deployment and Hosted evaluation remain separate approval steps; no target-repository deployment is authorized by these implementation milestones alone.
