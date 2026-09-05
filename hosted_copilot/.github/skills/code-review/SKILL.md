---
name: code-review
description: "Review Terraform AzureRM pull requests for actionable implementation, acceptance-test, and documentation defects using repository evidence and compact path-specific rules."
user-invocable: false
---

# AzureRM Code Review:

## Procedure:

- Identify the changed implementation, acceptance-test, or documentation surfaces.
- Read the diff before opening supporting files.
- For each possible defect, inspect only the nearest schema, parser, model, test, documentation, or neighboring implementation needed to prove or disprove it.
- Apply the repository-wide instructions and every path-specific rule matching the changed file.
- Inspect existing review feedback when GitHub context exposes it and suppress materially equivalent comments.
- Emit only actionable findings attached to changed lines.

## Comment Requirements:

- State the concrete failure condition and its consequence.
- Cite the stable rule ID when a path-specific rule applies.
- Keep the comment focused on one defect.
- Do not emit broad summaries, praise, optional refactors, or unsupported concerns.

## Boundaries:

- Do not reproduce multi-role review orchestration, handoff records, moderation passes, presentation schemas, or pending-review staging.
- Do not treat skill selection as the enforcement boundary; mandatory requirements remain in path-specific instructions.
- Do not modify files, submit reviews, or claim external validation unless the review environment explicitly authorizes and records that action.
