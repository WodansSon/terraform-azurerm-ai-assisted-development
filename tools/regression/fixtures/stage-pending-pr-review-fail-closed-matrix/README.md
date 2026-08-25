# Sanitized Fixture: Pending Review Fail-Closed Matrix

This fixture converts empirical lessons from the first live pending-review staging trial into synthetic subscenarios.

## Input Scenarios

- No frozen committed-review result is available.
- A rendered committed review exists but its successful verification footer is missing.
- One human challenge remains unresolved.

## Challenge Scenarios

- A human proposes a missed issue that targeted evidence disproves.
- A human proposes a plausible concern that cannot be proven as a defect.

## Anchor Scenarios

- The desired line is unchanged, but a nearby changed line in the same hunk can anchor an unambiguous comment.
- No line in the relevant hunk or path can anchor the finding accurately.
- The approved anchor changes before mutation.

## GitHub State Scenarios

- The pull request head changes after approval.
- One page of review threads, review bodies, top-level discussion, thread replies, or thread resolution state cannot be retrieved before preview.
- Another reviewer posts materially equivalent feedback after preview and approval but before mutation.
- The authenticated user already owns a pending review.
- The proposed payload contains a non-empty body or an `event` property.
- A comment has no relevant contributor guidance, or its candidate reference is malformed, non-raw, or cannot be verified.
- A comment invents `features.FivePointOh()` even though current evidence uses `features.SixPointOh()`.

## Transport and API Scenarios

- A multiline PowerShell command executes only its first physical line and returns no definitive review identity.
- An ambiguous create result is followed by a proposed blind retry.
- A guessed review-specific REST comments endpoint is proposed for incremental construction.
- Incremental GraphQL thread creation returns null data without errors.

## Verification Scenarios

- The created review state, top-level body, submission timestamp, commit, comment count, path coverage, anchor, or body differs from the approved plan.
- A post-creation comment edit is proposed as automatic recovery.
- A submission event is proposed after a failure.

Every subscenario must fail closed, suppress feedback already owned by an existing pull request thread, downgrade an uncertain human concern to a non-blocking question, or omit an unverifiable candidate reference while retaining the comment. No scenario may assume partial feedback history is complete, publish a duplicate from stale approval, create a second review, partially construct a review, repair a review automatically, or submit anything.
