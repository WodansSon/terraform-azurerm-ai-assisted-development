# Sanitized Fixture: Local Review Handoff Schema Preservation

This fixture is synthetic and sanitized. It exists to prove that the generic local review prompt can route architect and skeptic findings through the shared handoff schema and then let the advocate resolve a candidate without changing the record shape.

## Scenario

The modeled local change touches these files:

- `.github/instructions/review-workflow-handoff.schema.json`
- `.github/prompts/code-review-local-changes.prompt.md`
- `.github/instructions/review-skeptic-compliance-contract.instructions.md`
- `.github/instructions/review-advocate-compliance-contract.instructions.md`

The schema is meant to be the shared transport between routed roles, but one prompt or contract sentence now makes it sound like the advocate may rewrite a candidate finding into prose instead of preserving the schema-backed record through adjudication.

At the same time, a naive review is tempted to flag the optional `roleNotes` field as mandatory even though the schema intentionally leaves it optional.

## Simplified Change Shape

- The local review prompt now references the shared handoff schema.
- The skeptic contract and advocate contract both point to the same schema-backed candidate set.
- One narrow wording defect still suggests the advocate can bypass the structured record.
- A second apparent schema problem is a false positive because `roleNotes` remains optional by design.

## Expected Review Behavior

A correct local code review should:

- Apply AI-customization scope rules to the prompt, schema, and contract files.
- Run the routed architect, skeptic, and advocate passes.
- Keep the real schema-preservation problem in `ISSUES`.
- Dismiss the optional-`roleNotes` false positive into `OBSERVATIONS` with a `[⚖️ ADVOCATE: ...]` note.
- Emit the routed skill markers for `review-architect`, `review-skeptic`, and `review-advocate` in the final footer.

## Expected Must-Catch Outcomes

- `schema-record-preserved-through-advocate`
- `optional-role-notes-not-required`

## Expected Must-Not-Flag Outcomes

- `schema-record-replaced-by-freeform-dialogue`
