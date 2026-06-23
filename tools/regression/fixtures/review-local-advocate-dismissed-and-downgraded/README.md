# Sanitized Fixture: Local Review Advocate Outcomes

This fixture is synthetic and sanitized. It exists to prove that the generic local review prompt routes candidate Issues through the advocate second pass and lands dismissed versus downgraded outcomes in the correct final sections.

## Scenario

The modeled local change touches these files:

- `.github/prompts/code-review-committed-changes.prompt.md`
- `.github/instructions/review-advocate-compliance-contract.instructions.md`

The prompt edit keeps Step 6 wired to the advocate skill and contract, but one narrow wording change still overstates a prompt requirement. At the same time, a naive first-pass review is tempted to raise a second issue against a contract-backed design choice that is actually intentional.

## Simplified Change Shape

- The prompt still delegates outcome mapping to the advocate contract.
- One changed sentence in the prompt overstates a verification requirement and should remain a reduced-severity Issue after review.
- Another apparent problem is a false positive because the dedicated advocate contract intentionally owns that behavior, so the advocate pass should dismiss it.

## Expected Review Behavior

A correct local code review should:

- Apply AI-customization scope rules to the prompt and contract files
- Produce candidate Issues during the primary pass
- Invoke the `review-advocate` skill as the second-pass quality gate
- Keep the real wording-drift problem in `ISSUES` at reduced severity
- Move the false-positive finding into `OBSERVATIONS` with a `[⚖️ ADVOCATE: ...]` note
- Emit the `review-advocate` skill verification marker in the final footer because the advocate pass actually ran

## Expected Must-Catch Outcomes

- `advocate-dismissed-finding-observation`
- `advocate-downgraded-finding-stays-in-issues`

## Expected Must-Not-Flag Outcomes

- `dismissed-finding-left-in-issues`
