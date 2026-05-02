# Case Authoring Guide

Each case file in this directory represents one adjudicated or planned benchmark scenario.

## Required Traits

Each case should define:

- The task under test
- The expected rule families
- The must-catch findings or behaviors
- The must-not-flag findings or behaviors
- The expected tool behavior
- The required output structure

## Sanitization Rule

Final case artifacts should not depend on live PR links or contributor identity.

Use neutral case IDs and scenario summaries instead.

Modeled changed-file paths may still use real repository locations when that is necessary to preserve realistic routing or rule activation. Keep the actual fixture content under `tools/regression/fixtures/` rather than creating benchmark-only files in the live repo surface.

## Status Progression

- `planned`
- `ready`
- `adjudicated`
- `retired`

## Corpus Growth Rule

Whenever a real prompt or skill run misses an important issue, raises a recurring false positive, or shows a workflow regression, convert that incident into a new case here.

## Adjudication Rule

When promoting a case to `adjudicated`:

- Attach or reference a sanitized fixture
- Ensure the final artifact does not contain a live PR link or contributor identity
- Capture at least one expected good-result example if practical
- Add a sample human-readable output artifact when the case is prompt-review-oriented and output structure matters to the benchmark

## Example Pairing Rule

For adjudicated review-style cases, prefer keeping three artifacts together:

- The case definition
- The sample review Markdown output
- The sample scored result JSON
