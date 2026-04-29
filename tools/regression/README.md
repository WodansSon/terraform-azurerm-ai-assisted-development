# Regression Harness Layout

This directory contains the repo-only foundation for an objective regression harness for prompts, instructions, and skills.

## Purpose

The goal is to turn behavioral evaluation from subjective human agreement into repeatable scoring against adjudicated fixtures.

## Layout

- `config/score-weights.json`
  - Defines the weighted score model.
- `schema/review-case.schema.json`
  - Defines the structure of a benchmark case.
- `schema/review-result.schema.json`
  - Defines the structure of a benchmark result.
- `cases/`
  - Stores individual case manifests.
- `new-regression-result-template.ps1`
  - Generates a starter result document from a case.
- `score-regression-case.ps1`
  - Scores a result document against a case and the configured weights.
- `run-regression-example.ps1`
  - Displays the fixture and sample output paths for a case and prints the score summary for the paired result.
- `run-regression-case.ps1`
  - Resolves a single case alias or case path, creates a timestamped run directory, materializes the fixture, generates a run manifest, and scaffolds output artifacts for a real evaluation run.
- `hydrate-regression-run.ps1`
  - Copies adjudicated example artifacts into a scaffolded run so the end-to-end run layout can be inspected without manual copying.
- `clean-regression-runs.ps1`
  - Deletes generated run directories for housekeeping.

## Case Authoring Rules

- Do not reference live PR numbers, authors, or branch names inside the final case artifact.
- Represent the source as a sanitized fixture.
- Focus on expected behavior, not exact wording.
- Record must-catch outcomes and must-not-flag outcomes explicitly.
- Keep cases narrow enough that the expected rule activation is deterministic.

## Future Runner Responsibilities

The future runner should:

- materialize or apply the fixture
- invoke the target prompt or skill
- capture the final output and relevant tool behavior
- score the run against the case expectations
- persist a result document matching `schema/review-result.schema.json`

## Current Status

This directory is a starter foundation, not a complete automated harness yet.

The current case manifests define the benchmark shape and intended coverage so that a runner can be added incrementally instead of inventing the model later.

The current scripts make the benchmark partially usable today:

- they scaffold result files consistently
- they compute weighted scores consistently
- they provide a stable path from manual adjudication to repeatable scoring
- they create repeatable single-case run directories for capturing real evaluation artifacts
- they can populate a scaffolded run from adjudicated example artifacts for demonstration and inspection
- they support basic cleanup of generated run directories

The repository now includes:

- one synthetic adjudicated smoke case for harness mechanics
- one sanitized adjudicated real-world case for actual review or guidance benchmarking
- one adjudicated review-side example that pairs a scored result with a sample review Markdown output
- one adjudicated docs-review example that pairs a scored result with a sample docs-review Markdown output

## Starter Commands

Generate a result template:

```powershell
pwsh -NoProfile -File ./tools/regression/new-regression-result-template.ps1 -CasePath ./tools/regression/cases/harness-smoke-resource-implementation.json -OutputPath ./tools/regression/results/harness-smoke-resource-implementation.result.json
```

Score a completed result:

```powershell
pwsh -NoProfile -File ./tools/regression/score-regression-case.ps1 -CasePath ./tools/regression/cases/harness-smoke-resource-implementation.json -ResultPath ./tools/regression/examples/harness-smoke-resource-implementation.result.json
```

Inspect an adjudicated example end to end:

```powershell
pwsh -NoProfile -File ./tools/regression/run-regression-example.ps1 -Case review-local-go-customizediff-validation
```

Scaffold a real single-case run from a case alias:

```powershell
pwsh -NoProfile -File ./tools/regression/run-regression-case.ps1 -Case review-docs-arguments-ordering
```

That command creates a new directory under `tools/regression/runs/` with:

- `run-manifest.json`
- `output/review.md`
- `output/result.json`
- a materialized `fixture/` copy when the case defines a fixture path

## Score Configuration

The scoring and pass-threshold knobs live in `config/score-weights.json`.

Use that file to tune:

- how much each scoring dimension contributes to the weighted overall score
- the minimum overall score required to pass
- the minimum must-catch recall floor
- whether any false positive is allowed in a passing run

The harness docs in `docs/AI_REGRESSION_HARNESS.md` explain the intent behind each knob. Change these values carefully, because they define benchmark policy rather than simple implementation detail.

Hydrate the latest scaffolded run from adjudicated examples:

```powershell
pwsh -NoProfile -File ./tools/regression/hydrate-regression-run.ps1 -Latest
```

Clean the latest generated run directory:

```powershell
pwsh -NoProfile -File ./tools/regression/clean-regression-runs.ps1 -Latest
```
