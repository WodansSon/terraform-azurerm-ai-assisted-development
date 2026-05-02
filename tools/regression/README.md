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
- `schema/run-manifest.schema.json`
  - Defines the structure of the deterministic single-run execution envelope manifest.
- `schema/history-snapshot.schema.json`
  - Defines the structure of a persisted suite-history snapshot.
- `validate-regression-artifacts.ps1`
  - Validates case and result artifacts against the harness schemas and core fixture-consistency checks.
- `new-regression-test.ps1`
  - Writes the contributor-facing HCL test template under `tools/regression/test/`.
- `build-regression-test.ps1`
  - Builds the internal harness artifacts from a contributor-facing HCL test file.
- `publish-regression-test.ps1`
  - Maintainer-facing helper that promotes a scaffolded regression test example into the adjudicated examples corpus.
- `test/TestSpecDefinition.ps1`
  - Codifies the accepted contributor-facing test blocks, fields, and enum values in one place.
- `write-regression-history-snapshot.ps1`
  - Writes a timestamped suite-history snapshot using the stable suite JSON output and current repository metadata.
- `summarize-regression-history.ps1`
  - Summarizes score and pass-rate trends across saved suite-history snapshots.
- `run-regression-harness.ps1`
  - Orchestrates the human-friendly end-to-end flow: validation, suite scoring, history snapshotting, and history summarization.
- `cases/`
  - Stores individual case manifests.
- `new-regression-result-template.ps1`
  - Generates a starter result document from a case.
- `score-regression-case.ps1`
  - Scores a result document against a case and the configured weights.
- `run-regression-suite.ps1`
  - Scores the adjudicated example corpus as a suite and reports direct target-skill coverage.
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

- Materialize or apply the fixture
- Invoke the target prompt or skill
- Capture the final output and relevant tool behavior
- Score the run against the case expectations
- Persist a result document matching `schema/review-result.schema.json`

## Current Status

This directory is a starter foundation, not a complete automated harness yet.

The current case manifests define the benchmark shape and intended coverage so that a runner can be added incrementally instead of inventing the model later.

The current scripts make the benchmark partially usable today:

- They scaffold result files consistently
- They compute weighted scores consistently
- They validate case and result artifacts against the benchmark schemas before scoring
- They can score the adjudicated example corpus as a suite and report which target skills have direct case coverage
- They provide a stable path from manual adjudication to repeatable scoring
- They create repeatable single-case run directories with snapshotted case and weights inputs plus explicit capture metadata
- They can populate a scaffolded run from adjudicated example artifacts for demonstration and inspection
- They can persist suite-history snapshots for later comparison
- They can summarize score and pass-rate trends across those saved snapshots
- They can orchestrate the common human execution path through one top-level harness command
- They support basic cleanup of generated run directories

The repository now includes:

- One synthetic adjudicated smoke case for harness mechanics
- One sanitized adjudicated real-world case for actual review or guidance benchmarking
- One adjudicated review-side example that pairs a scored result with a sample review Markdown output
- One adjudicated docs-review example that pairs a scored result with a sample review Markdown output
- One adjudicated committed-review example that pairs a scored result with a sample review Markdown output

The current direct target-skill scope for the harness is:

- `docs-writer`
- `resource-implementation`
- `acceptance-testing`

The repo-only `ai-toolkit-maintenance` skill is intentionally excluded from this benchmark surface.

## Starter Commands

Contributor-facing authoring entry point:

```powershell
pwsh -NoProfile -File ./tools/regression/new-regression-test.ps1 -Id my-new-case -Task resource-implementation
```

Preferred HCL contributor flow:

```powershell
pwsh -NoProfile -File ./tools/regression/new-regression-test.ps1 -Id my-new-case -Task resource-implementation
pwsh -NoProfile -File ./tools/regression/build-regression-test.ps1 -SpecPath ./tools/regression/test/my-new-case.hcl
```

That flow lets contributors author one HCL test spec under `tools/regression/test/` while the harness tool generates the internal case, fixture, and draft result artifacts automatically.

The HCL surface is intentionally shaped to feel closer to a Terraform acceptance test than a raw manifest:

```hcl
AccTest "example-case" "basic" {
  title = "Example benchmark title"

  test_case {
    task        = "resource-implementation"
    source_kind = "real-pr"
    case_status = "planned"
    notes       = "Optional scope notes."

    changed_files = [
      "internal/services/example/example_resource.go",
    ]

    config {
      resource "azurerm_example_resource" "test" {
        name = "example"
      }
    }
  }

  rules {
    description           = "Plain-language scenario description."
    notes                 = "Optional maintainer notes."
    include_sample_output = false

    must_catch {
      description = "Prefer stronger validation when the accepted values are knowable."
      severity    = "medium"
      file        = "internal/services/example/example_resource.go"
    }

    must_not_flag {
      description = "Do not invent unsupported schema constraints."
    }
  }
}
```

The canonical shape treats `test_case { config { ... } }` as real nested HCL.

Maintainer promotion entry point:

```powershell
pwsh -NoProfile -File ./tools/regression/publish-regression-test.ps1 -SpecPath ./tools/regression/test/my-new-case.hcl
```

That command promotes the reviewed draft artifacts into the adjudicated examples corpus and updates the case status.

Recommended human entry point:

```powershell
pwsh -NoProfile -File ./tools/regression/run-regression-harness.ps1
```

That command orchestrates the current stable harness flow in the correct order and writes the latest machine-readable and text outputs under `tools/regression/results/latest/`.

Generate a result template:

```powershell
pwsh -NoProfile -File ./tools/regression/new-regression-result-template.ps1 -CasePath ./tools/regression/cases/harness-smoke-resource-implementation.json -OutputPath ./tools/regression/results/harness-smoke-resource-implementation.result.json
```

Score a completed result:

```powershell
pwsh -NoProfile -File ./tools/regression/score-regression-case.ps1 -CasePath ./tools/regression/cases/harness-smoke-resource-implementation.json -ResultPath ./tools/regression/examples/harness-smoke-resource-implementation.result.json
```

Emit the score summary as JSON:

```powershell
pwsh -NoProfile -File ./tools/regression/score-regression-case.ps1 -CasePath ./tools/regression/cases/harness-smoke-resource-implementation.json -ResultPath ./tools/regression/examples/harness-smoke-resource-implementation.result.json -Output json
```

Validate the current case and example-result corpus against the harness schemas:

```powershell
pwsh -NoProfile -File ./tools/regression/validate-regression-artifacts.ps1
```

Emit the validation summary as JSON:

```powershell
pwsh -NoProfile -File ./tools/regression/validate-regression-artifacts.ps1 -Output json
```

Score the adjudicated example corpus and report target-skill coverage:

```powershell
pwsh -NoProfile -File ./tools/regression/run-regression-suite.ps1
```

Emit the suite summary as JSON:

```powershell
pwsh -NoProfile -File ./tools/regression/run-regression-suite.ps1 -Output json
```

Write a timestamped suite-history snapshot under `tools/regression/results/history/`:

```powershell
pwsh -NoProfile -File ./tools/regression/write-regression-history-snapshot.ps1
```

Write the suite-history snapshot to a specific path:

```powershell
pwsh -NoProfile -File ./tools/regression/write-regression-history-snapshot.ps1 -OutputPath ./tools/regression/results/history/latest.json
```

Summarize the saved regression-history snapshots:

```powershell
pwsh -NoProfile -File ./tools/regression/summarize-regression-history.ps1
```

Emit the history summary as JSON:

```powershell
pwsh -NoProfile -File ./tools/regression/summarize-regression-history.ps1 -Output json
```

Focus the suite output on the direct target skills only:

```powershell
pwsh -NoProfile -File ./tools/regression/run-regression-suite.ps1 -Task docs-writer,resource-implementation,acceptance-testing -CaseStatus planned,ready,adjudicated
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
- `input/case.json`
- `input/score-weights.json`
- `capture/execution-metadata.json`
- `output/review.md`
- `output/result.json`
- A materialized `fixture/` copy when the case defines a fixture path

The single-case scaffold now acts as a deterministic execution envelope:

- It snapshots the case definition used for the run
- It snapshots the scoring weights used for the run
- It records the current repository branch, commit, and dirty-state metadata in the manifest and capture file
- It keeps future scoring tied to the snapshotted inputs instead of whatever the live case or weight file may become later

## Score Configuration

The scoring and pass-threshold knobs live in `config/score-weights.json`.

Use that file to tune:

- How much each scoring dimension contributes to the weighted overall score
- The minimum overall score required to pass
- The minimum must-catch recall floor
- Whether any false positive is allowed in a passing run

The harness docs in `docs/AI_REGRESSION_HARNESS.md` explain the intent behind each knob. Change these values carefully, because they define benchmark policy rather than simple implementation detail.

Hydrate the latest scaffolded run from adjudicated examples:

```powershell
pwsh -NoProfile -File ./tools/regression/hydrate-regression-run.ps1 -Latest
```

Clean the latest generated run directory:

```powershell
pwsh -NoProfile -File ./tools/regression/clean-regression-runs.ps1 -Latest
```

The repository also includes a report-only CI workflow at `.github/workflows/regression-harness-validation.yml` that shells through `tools/validate-ai-toolkit.ps1 -SkipUpstreamDrift` and publishes the latest generated regression reports as workflow artifacts.
