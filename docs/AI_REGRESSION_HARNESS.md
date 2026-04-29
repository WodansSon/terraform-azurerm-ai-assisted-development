# AI Regression Harness

This document defines the objective benchmark model for evaluating this repository's AI prompts, instructions, and skills.

## Goal

The current validation model is strong for structural correctness, but still weak for behavioral regressions.

Today we can validate things like:

- Contract structure
- Markdown formatting
- Manifest coverage
- Release packaging

What remains subjective is whether prompt, instruction, and skill behavior gets better or worse over time. This harness foundation exists to make those evaluations repeatable and evidence-based.

## Core Principle

The benchmark must score behavior, not prose.

The harness should not fail a run because the wording changed. It should fail a run because the run:
- Missed a must-catch issue
- Raised a false positive that should not be raised
- Used the wrong tool flow
- Loaded the wrong rule family
- Violated the expected output contract

## What Makes The Benchmark Objective

The benchmark becomes objective when all of the following are fixed:

- The repository snapshot under evaluation
- The changed files or patch fixture
- The task being invoked
- The expected rules that should apply
- The adjudicated must-catch and must-not-flag outcomes
- The scoring rubric

**_Human judgment is still required when authoring and approving a case_**, but once a case is adjudicated the day-to-day scoring should be automatic.

## Repository Layout

The initial foundation lives under `tools/regression/`:
- `tools/regression/README.md`
- `tools/regression/config/score-weights.json`
- `tools/regression/schema/review-case.schema.json`
- `tools/regression/schema/review-result.schema.json`
- `tools/regression/cases/`
- `tools/regression/new-regression-result-template.ps1`
- `tools/regression/score-regression-case.ps1`
- `tools/regression/run-regression-example.ps1`
- `tools/regression/run-regression-case.ps1`
- `tools/regression/hydrate-regression-run.ps1`
- `tools/regression/clean-regression-runs.ps1`

This is repo-only maintenance tooling. It is not installer payload.

## Case Model

Each case should define:

- A stable case ID
- The task or prompt being invoked
- The intended scope and changed files
- The expected rule families that should activate
- A must-catch set
- A must-not-flag set
- The expected tool behavior
- The required output structure checks

Cases should be sanitized fixtures, not live PR links.

## Scoring Model

The initial score model is weighted toward correctness over formatting.

- Must-catch recall
- False-positive control
- Severity correctness
- Scope and tool correctness
- Output compliance
- Determinism

The exact weights live in `tools/regression/config/score-weights.json`.

## Score Weights File

The `tools/regression/config/score-weights.json` file controls two things:

- How much each scoring dimension contributes to the final overall score
- The minimum thresholds required for a run to count as passing

### Think of the file as two separate layers:

- `weights`
	- This section controls score composition.
	- It answers: `How much should each dimension matter in the weighted overall score?`
- `passGuidance`
	- This section controls pass or fail policy.
	- It answers: `After the score is calculated, what minimum conditions are required for the run to count as passing?`

Those two sections do different jobs and should be read in order:

- The harness calculates the per-dimension scores
- The harness applies the `weights` section to compute the weighted overall score
- The harness applies the `passGuidance` section to decide whether that scored run is allowed to pass

That means a run can have a high overall score and still fail if it violates a stricter policy floor in `passGuidance`. All numeric values in this file are designed to be easy to reason about as percentages.

### General guidance for the whole file:

- Each value under `weights` should normally be a number from `0` to `100`
- Each numeric value under `passGuidance` should normally be a number from `0` to `100`
- `allowFalsePositives` is a boolean, so its valid values are `true` or `false`

## The `weights` Section

The `weights` section controls how the overall score is calculated.

### General guidance for `weights`:

- The values under `weights` should normally add up to `100`
- Keeping the total at `100` lets reviewers read each weight as a percentage share of the final score
- Totals above `100` or below `100` are not invalid mathematically, but they make the scoring policy harder to reason about

### What higher and lower values mean in the `weights` section:

- A higher weight means that scoring dimension has more influence on the final overall score
- A lower weight means that scoring dimension has less influence on the final overall score
- A weight of `0` effectively removes that dimension from the weighted score

### Current scoring dimensions:

- `mustCatchRecall`
	- **Description:** Measures whether the run actually surfaced the adjudicated must-catch findings.
	- **Reason:** This is intentionally the largest weight because missing a real issue is worse than wording differences.
	- **Expected range:** `0` to `100`.
	- **Higher value:** Must-catch recall matters more in the overall score.
	- **Lower value:** The harness becomes more tolerant of missing important issues, which is usually a bad tradeoff.
- `falsePositiveControl`
	- **Description:** Measures whether the run avoided raising issues that the case explicitly says must not be flagged.
	- **Reason:** This stays heavily weighted because noisy reviews reduce trust in the harness quickly.
	- **Expected range:** `0` to `100`.
	- **Higher value:** False positives hurt the score more strongly.
	- **Lower value:** The harness becomes more permissive of noisy or overreaching output.
- `severityCorrectness`
	- **Description:** Measures whether the important findings were classified at the expected severity.
	- **Reason:** Finding the right issue is important, but classifying it correctly is also part of trustworthy review behavior.
	- **Expected range:** `0` to `100`.
	- **Higher value:** Severity mismatches matter more.
	- **Lower value:** The harness cares less about whether the right issue was classified at the right level.
- `scopeAndToolCorrectness`
	- **Description:** Measures whether the right rule families and tool behavior were applied for the case.
	- **Reason:** A run that uses the wrong tools or applies the wrong rules can look plausible while still being fundamentally unreliable.
	- **Expected range:** `0` to `100`.
	- **Higher value:** Using the right scope and tools matters more in the final score.
	- **Lower value:** The harness becomes more forgiving of incorrect tool or scope behavior.
- `outputCompliance`
	- **Description:** Measures whether required sections or markers are present in the output artifact.
	- **Reason:** Some workflows depend on stable output structure, even when prose wording is allowed to vary.
	- **Expected range:** `0` to `100`.
	- **Higher value:** Output-shape compliance matters more.
	- **Lower value:** The harness focuses less on formatting and required sections.
- `determinism`
	- **Description:** Measures whether repeated runs are materially equivalent.
	- **Reason:** A regression benchmark loses value quickly if the same case produces meaningfully different outcomes from run to run.
	- **Expected range:** `0` to `100`.
	- **Higher value:** Run-to-run stability matters more.
	- **Lower value:** The harness becomes more tolerant of variability.

## The `passGuidance` Section

The `passGuidance` section does not change how the score is calculated. It changes how the harness interprets the score after calculation, this is effectivly the policy gate.

### What higher and lower values mean in `passGuidance`:

- A higher pass threshold makes the benchmark stricter
- A lower pass threshold makes the benchmark more permissive
- A stricter `passGuidance` block can cause a run to fail even when the weighted overall score still looks relatively strong

### Current pass-guidance knobs:

- `minimumOverallScore`
	- **Description:** The weighted overall score required for a run to pass.
	- **Reason:** This is the broad policy threshold for deciding whether the full score profile is acceptable.
	- **Expected range:** `0` to `100`.
	- **Higher value:** stricter overall pass criteria.
	- **Lower value:** easier overall pass criteria.
- `minimumMustCatchRecall`
	- **Description:** A floor for must-catch recall so a run cannot pass on formatting or low-severity behavior while still missing the important issue.
	- **Reason:** This protects the harness from approving runs that look polished but fail at the main job of catching important issues.
	- **Expected range:** `0` to `100`.
	- **Higher value:** stricter requirement that important issues must be found.
	- **Lower value:** more tolerance for missing must-catch findings.
- `allowFalsePositives`
	- **Description:** Whether a run with any false positives is allowed to pass.
	- **Reason:** This is a policy choice about whether noise is acceptable while the harness and corpus are still maturing.
	- **Valid values:** `true` or `false`.
	  - **`true`:** More permissive, useful during early experimentation if the corpus is still immature.
	  - **`false`:** Stricter, better when false positives are considered a serious trust problem.

## How `weights` And `passGuidance` Affect Each Other

The simplest way to think about the interaction is:

- `weights` decide the shape of the score
- `passGuidance` decides whether that score is good enough

### Examples:

- If `mustCatchRecall` has a very high weight, then missing important findings will drag the weighted overall score down sharply.
- Even if the weighted overall score stays high, a high `minimumMustCatchRecall` can still force the run to fail.
- If `allowFalsePositives` is `false`, then even a strong weighted score may still fail when the run invents issues that should not have been flagged.

### Why these knobs matter:

- A higher `minimumOverallScore` makes the harness stricter overall
- A higher `minimumMustCatchRecall` makes it harder for a run to pass while missing core issues
- `allowFalsePositives: false` keeps the benchmark conservative while the corpus is still small and trust-sensitive

In other words, `weights` shape the score distribution, while `passGuidance` sets the policy boundary for accepting or rejecting the run.

These values are policy choices, not immutable truths. They should be adjusted only when the team has enough case coverage to justify changing the strictness.

## Initial Corpus Strategy

The starter corpus is intentionally small and covers the main current review and guidance surfaces:

- Local code review
- Committed code review
- Docs review
- Implementation guidance
- Acceptance-testing guidance

These starter cases are planning manifests first. They define the shape and expectations of the future corpus even before a full runner exists.

The first non-synthetic adjudicated case should be treated as the reference pattern for future case authoring:

- Sanitize the historical source
- Remove PR identity from the final artifact
- Preserve the real failure mode and expected review behavior
- Attach a scored example result when practical

## Case Lifecycle

Recommended states:

- `planned`: Case idea exists, but fixture or gold-set data is incomplete
- `ready`: Fixture exists and expected outcomes are drafted
- `adjudicated`: Expectations are reviewed and can be used for scoring
- `retired`: No longer representative, but retained for history

## Runner Expectations

The future runner should:

- prepare a clean fixture workspace
- invoke the exact prompt or skill under test
- capture the output and tool behavior
- score the run against the adjudicated case expectations
- emit a machine-readable result object that matches `review-result.schema.json`

The current starter scripts do not execute prompts or skills yet. They solve the next smaller problem first:

- Scaffold a result document from a case definition
- Score a completed result document against a case and the weighted rubric
- Present the case fixture, sample review output, and score summary together for easier inspection
- Create a repeatable single-case run directory with a manifest and placeholder artifacts so a real run can be captured consistently
- Hydrate a scaffolded run from adjudicated example artifacts so the full run layout can be inspected end to end
- Clean generated run directories as routine housekeeping

That means the repository now supports repeatable scoring once a human or later automation has produced a result file.

## Non-Goals

This foundation does not attempt to:

- Force exact output snapshots
- Replace human review of new benchmark cases
- Act as a release blocker until the corpus is broad enough to be trusted

## Recommended Rollout

Start with the starter corpus as a reporting-only benchmark.

After enough real cases are adjudicated, use the score trends to detect regressions before changes are merged. Only later should this become a CI gate.

## Starter Workflow

The initial benchmark workflow is:

- Choose a case from `tools/regression/cases/`.
- Scaffold a single run with `tools/regression/run-regression-case.ps1`.
- Optionally hydrate the scaffold from adjudicated example artifacts with `tools/regression/hydrate-regression-run.ps1`.
- Fill in or replace the generated review artifact from a real prompt or skill run.
- Update the generated result file for the adjudicated outcome.
- Score it with `tools/regression/score-regression-case.ps1`.
- Review the weighted score and pass or fail guidance.

## Single-Case Orchestrator

The first-pass orchestrator intentionally keeps execution simple:

- It accepts one case at a time
- It resolves a case alias to a case manifest under `tools/regression/cases/`
- It creates a timestamped run directory under `tools/regression/runs/`
- It generates a run manifest plus placeholder review and result artifacts

This keeps the single-case lifecycle stable before any batch or suite features are introduced.

## Run Hydration

The hydrator exists to make the run layout easier to understand.

It does not execute prompts or skills. Instead, it copies the sample review and sample result artifacts for an adjudicated case into an already scaffolded run directory so that the full end-to-end artifact shape can be inspected quickly.

## Run Cleanup

Generated run directories are intentionally ignored in git.

Use the cleanup script to remove:

- A single run by ID
- The latest run
- All generated runs

## Adjudicated Case Pattern

The repository now includes two distinct examples:

- A synthetic smoke case used to validate harness mechanics
- A sanitized adjudicated real-world case used to show how a historical miss or review correction should be preserved without keeping live PR identity

The repository now also includes a docs-review adjudicated case so the benchmark shows three distinct output styles:

- Implementation guidance
- Local code review
- Docs review

The repository also now includes a review-side adjudicated example with a sample Markdown review body so maintainers can see the intended human-readable output shape alongside the machine-readable scoring artifact.

Use the real-world case as the authoring pattern when converting future historical incidents into benchmark fixtures.
