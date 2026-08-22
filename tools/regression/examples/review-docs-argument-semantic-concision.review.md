# Code Review: argument semantic concision

## CHANGE SUMMARY

- **Files Changed**: 1 modified resource documentation page
- **Scope**: reviews one argument bullet containing required standard semantics and a supplemental caveat

## FILES CHANGED

- `website/docs/r/example_gateway.html.markdown`

## PRIMARY CHANGES ANALYSIS

The argument correctly keeps its definition, `Possible values are`, `Defaults to`, and `Changing this forces a new resource to be created.` sentences together in the bullet. Those four standard sentences are compliant; sentence count alone is not evidence of a `DOCS-ARG-011` failure.

## DETAILED TECHNICAL REVIEW

### STANDARDS CHECK

- `DOCS-ARG-011` requires semantic concision rather than a numeric sentence cap.
- The enum, default, and ForceNew sentences are required core semantics and remain in the bullet.
- The regional-capacity guidance is supplemental operational advice rather than field-definitional schema content.

### STRENGTHS

- Canonical possible-value wording is present.
- The default is documented inline.
- The ForceNew sentence is correctly placed at the end of the core argument semantics.

## ISSUES

- `DOCS-ARG-011`: move only the supplemental regional-capacity guidance into an adjacent informational note. Keep `Possible values are`, `Defaults to`, and `Changing this forces a new resource to be created.` in the field bullet.

## OVERALL ASSESSMENT

The bullet needs one targeted note split, not a rewrite driven by sentence count.
