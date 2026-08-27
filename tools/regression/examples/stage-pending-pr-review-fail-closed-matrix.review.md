## Fail-Closed Matrix

- No frozen review: `Cannot run stage-pending-pr-review: no eligible frozen committed-review findings are available in this conversation or supplied input.`
- Missing footer: `Cannot run stage-pending-pr-review: the committed-review result is missing its required verification footer. Nothing was staged.`
- Open challenge: `Cannot run stage-pending-pr-review: human challenge adjudication is unresolved. Settle every challenge before previewing a staging plan.`
- Changed pull request head: approval discarded; replacement preview required
- Existing pending review: creation blocked
- Non-empty top-level body: plan invalid
- Any `event` property: plan invalid
- Unverified contributor reference: omitted; comment retained
- Predicate not proven from current evidence: asserted version claim blocked

## Challenge Outcomes

- Unsupported human-proposed issue: Rejected as unsupported and preserved only in the challenge ledger.
- Plausible but unproven human concern:

  Could the service apply a different precedence rule when both routing fields are present?

  It is not included in the request-changes summary as an established blocker.

## Existing Feedback Outcomes

- Incomplete thread pages, replies, review bodies, discussion comments, or thread state: `Cannot run stage-pending-pr-review: existing pull request feedback could not be fully retrieved and compared. Nothing was staged.`
- New equivalent feedback after approval: approval discarded; replacement preview required.
- Partial or empty feedback response: not accepted as a complete no-duplicate result.
- A stale approved duplicate is never published.

## Anchor Outcomes

- Desired unchanged line with an unambiguous nearby changed line: Re-anchor requires replacement preview and approval.
- The preview shows the actual changed-line anchor and names the affected nearby code in the body.
- No accurate commentable line: fail closed before approval.
- Anchor changed after approval: approval discarded.

## Transport and API Outcomes

- Mutation transport: checked structured tool, deterministic single physical line, or approved structured payload mechanism only.
- Missing definitive create response: Existing pending review checked before retry.
- Existing pending review found: stop without another mutation.
- Guessed review-specific REST comments endpoint: forbidden.
- Incremental GraphQL thread construction: forbidden as the normal path.
- Null GraphQL thread: failure.
- Post-creation automatic comment edit: forbidden.

## Verification Outcomes

- Review must remain `PENDING` with an empty body and null `submitted_at`.
- Commit, count, coverage, anchors, and bodies must equal the approved plan.
- Verification mismatch: report only; no repair or submission.
- Human reviewers inspect and optionally edit the pending review, then submit it manually in GitHub.
- Any later automated submission requires a new explicit instruction outside this workflow.
