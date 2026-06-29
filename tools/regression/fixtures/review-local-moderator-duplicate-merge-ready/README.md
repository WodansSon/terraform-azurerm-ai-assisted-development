# Sanitized Fixture: Local Review Moderator Duplicate Merge

This fixture is synthetic and sanitized. It defines the expected duplicate-merge behavior for the live moderator-routed review workflow.

## Scenario

The modeled local change touches these files:

- `.github/instructions/review-workflow-handoff.schema.json`
- `.github/instructions/review-moderator-compliance-contract.instructions.md`
- `.github/prompts/code-review-local-changes.prompt.md`

The reviewer, skeptic, and architect all surface the same underlying concern through schema-conformant handoff records, but with slightly different wording and evidence depth.

## Simplified Change Shape

- The workflow handoff schema preserves routed findings as shared records.
- The future moderator contract defines duplicate merging and final synthesis semantics.
- One concern appears multiple times across roles and should be merged into one final moderated record in the live workflow.

## Expected Review Behavior

A correct moderator-routed local review should:

- Merge duplicate routed concerns into one final finding.
- Preserve the strongest evidence and combined role attribution in the merged record.
- Avoid emitting separate final issues that restate the same underlying problem.

## Expected Must-Catch Outcomes

- `duplicate-routed-findings-merge-into-one-record`
- `strongest-evidence-survives-merge`

## Expected Must-Not-Flag Outcomes

- `duplicate-concern-emitted-twice`
