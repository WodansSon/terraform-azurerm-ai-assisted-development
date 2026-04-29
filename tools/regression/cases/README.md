# Case Authoring Guide

Each case file in this directory represents one adjudicated or planned benchmark scenario.

## Required Traits

Each case should define:

- the task under test
- the expected rule families
- the must-catch findings or behaviors
- the must-not-flag findings or behaviors
- the expected tool behavior
- the required output structure

## Sanitization Rule

Final case artifacts should not depend on live PR links or contributor identity.

Use neutral case IDs and scenario summaries instead.

## Status Progression

- `planned`
- `ready`
- `adjudicated`
- `retired`

## Corpus Growth Rule

Whenever a real prompt or skill run misses an important issue, raises a recurring false positive, or shows a workflow regression, convert that incident into a new case here.

## Adjudication Rule

When promoting a case to `adjudicated`:

- attach or reference a sanitized fixture
- ensure the final artifact does not contain a live PR link or contributor identity
- capture at least one expected good-result example if practical
- add a sample human-readable output artifact when the case is prompt-review-oriented and output structure matters to the benchmark

## Example Pairing Rule

For adjudicated review-style cases, prefer keeping three artifacts together:

- the case definition
- the sample review Markdown output
- the sample scored result JSON
