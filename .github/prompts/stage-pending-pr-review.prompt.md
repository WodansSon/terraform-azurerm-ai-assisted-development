---
description: "BETA: Challenge frozen committed-review findings, validate human-proposed missed issues, and stage the settled state as an unsubmitted GitHub pending review after explicit approval."
---

# Challenge and Stage Pending Pull Request Review (BETA)

## Safety boundary

This is a BETA opt-in staging workflow, not a code review or review-submission workflow. The workflow and output shape may change while real-world usage is evaluated.

- Never submit, approve, comment, or request changes automatically.
- Never modify repository files.
- Never mutate the frozen audit baseline.
- Change the staging candidate set only through evidence-backed `REVIEW-STAGE-CHALLENGE-*` adjudication of human input.
- Never treat this prompt invocation as approval to create the pending review.

## Required procedure

### Load staging prerequisites

- Read `.github/instructions/review-staging-compliance-contract.instructions.md` to EOF and verify `<!-- REVIEW-STAGE-CONTRACT-EOF -->`.
- Read `.github/skills/review-staging/SKILL.md` to EOF and verify `<!-- REVIEW-STAGING-SKILL-EOF -->`.
- Read `.github/instructions/review-staging-plan.schema.json` end-to-end.
- If any prerequisite is unavailable or incomplete, hard-stop with exactly:
  - `Cannot run stage-pending-pr-review: staging contract, skill, or schema not fully loaded. Refresh the AI toolkit files and re-run this prompt.`

### Establish and adjudicate review state

- Invoke `review-staging` and apply the `REVIEW-STAGE-*` rules to the eligible frozen committed-review findings.
- Do not rerun `/code-review-committed-changes` or perform a new broad audit.
- If no eligible frozen committed-review findings are available, hard-stop with exactly:
  - `Cannot run stage-pending-pr-review: no eligible frozen committed-review findings are available in this conversation or supplied input.`
- If a committed-review result is present but lacks the required successful verification footer, hard-stop with exactly:
  - `Cannot run stage-pending-pr-review: the committed-review result is missing its required verification footer. Nothing was staged.`
- Preserve the original findings as the immutable baseline and initialize or resume the post-review adjudication ledger.
- Allow the human reviewer to challenge existing findings, request revisions or omissions, and propose issues or observations the audit may have missed.
- Validate each challenge narrowly against the same pull request evidence and applicable guidance.
- After each challenge, return the current candidate and withdrawn finding state without mutating GitHub.
- Continue until the human asks to proceed to staging or confirms that adjudication is complete.

### Build the preview

- Require the adjudication state to be `settled` and all challenges to have final dispositions.
- If any challenge remains unresolved, hard-stop with exactly:
  - `Cannot run stage-pending-pr-review: human challenge adjudication is unresolved. Settle every challenge before previewing a staging plan.`
- If the authenticated user already owns a pending review on the pull request, hard-stop with exactly:
  - `Cannot run stage-pending-pr-review: the authenticated user already has a pending review on this pull request. Inspect or remove that review manually before staging another.`
- Omit any candidate contributor reference that is inapplicable or cannot be verified; do not fail an otherwise valid comment solely because it has no reference.
- If any finding or diff location cannot be validated, hard-stop with exactly:
  - `Cannot run stage-pending-pr-review: the complete staging plan could not be validated against the current pull request head and contributor guidance. Nothing was staged.`
- Render the complete preview and ask for explicit approval as required by `REVIEW-STAGE-APPROVAL-*`.
- End the turn after asking. Do not mutate GitHub in the preview turn.

### Stage only after approval

- On a new explicit affirmative response, revalidate the exact approved plan and current pull request head.
- If the user challenges or changes the review instead of approving, return to adjudication, invalidate the preview, and do not mutate GitHub.
- If the plan changed, render the replacement preview and request approval again.
- Create one pending review atomically under `REVIEW-STAGE-API-001`.
- Do not call a review submission endpoint under any circumstance in this workflow.

### Verify and return

- Apply `REVIEW-STAGE-VERIFY-*` immediately after creation.
- Return the pending-review URL, verified `PENDING` state, comment count, file coverage, non-submission statement, and separate copy-ready `REQUEST_CHANGES` summary.
- Append `Skill used: review-staging` as the final line of a successful staged-review response.
- Never submit the pending review unless the user later gives a new explicit instruction outside this workflow.
