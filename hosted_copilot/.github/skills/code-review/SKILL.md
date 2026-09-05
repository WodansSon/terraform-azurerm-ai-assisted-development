---
name: code-review
description: "Review Terraform AzureRM pull requests for actionable implementation, acceptance-test, and documentation defects using repository evidence and compact path-specific rules."
user-invocable: false
---

# AzureRM Code Review:

## Contributor Guide:

The contributor guide is the golden standard. Read it completely before producing any finding.

- Recursively enumerate every Markdown file under `contributing/`. Do not rely only on the links in `contributing/README.md`.
- Read every enumerated file in full, including topics that do not initially appear relevant to the change.
- Confirm every enumerated file was read in this review. Do not rely on memory, summaries, or assumptions about any part of the guide.
- Build a checklist of the guide requirements that apply to the changed surfaces.
- Report the review as blocked when the guide cannot be enumerated or an enumerated file cannot be read. Do not silently skip part of the guide.

Path-specific rules are supplemental. They carry requirements the guide does not already mandate, or raise a guide recommendation to a requirement.

## Procedure:

- Complete the contributor guide step before analyzing the diff or drafting any finding.
- Identify the changed implementation, acceptance-test, or documentation surfaces.
- Read the diff before opening supporting files.
- For each possible defect, inspect only the nearest schema, parser, model, test, documentation, or neighboring implementation needed to prove or disprove it.
- Evaluate every changed file against the guide checklist, then apply the repository-wide instructions and every path-specific rule matching the changed file.
- Inspect existing review feedback when GitHub context exposes it and suppress materially equivalent comments.
- Emit only actionable findings attached to changed lines.

## Comment Requirements:

- State the concrete failure condition and its consequence.
- Cite the stable rule ID when a path-specific rule applies, and otherwise cite the contributor guide file and section that requires the change.
- Keep the comment focused on one defect.
- Do not emit broad summaries, praise, optional refactors, or unsupported concerns.

## Boundaries:

- Do not reproduce multi-role review orchestration, handoff records, moderation passes, presentation schemas, or pending-review staging.
- Do not treat skill selection as the enforcement boundary; mandatory requirements remain in the contributor guide and path-specific instructions.
- Do not modify files, submit reviews, or claim external validation unless the review environment explicitly authorizes and records that action.
