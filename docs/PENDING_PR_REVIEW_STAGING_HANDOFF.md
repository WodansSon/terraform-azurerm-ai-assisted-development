# Pending PR Review Staging: Empirical Workflow Handoff

## Purpose

This document records how a completed AzureRM code review was converted into a human-controlled pending GitHub review during PR 32239. It is an implementation handoff for the AI toolkit, not a second policy source.

The authoritative owner of staging behavior should remain:

- `.github/instructions/review-staging-compliance-contract.instructions.md`

The prompt and skill should consume that contract:

- `.github/prompts/stage-pending-pr-review.prompt.md`
- `.github/skills/review-staging/SKILL.md`

Regression cases should verify the safety boundary and API behavior. `AGENTS.md` should contain only concise repository-wide guardrails.

## Outcome

The workflow produced one GitHub review with:

- state `PENDING`
- an empty top-level review body
- 15 inline comments across 13 files
- no review submission event
- no approval, general comment, or request-changes action
- a separate copy-ready request-changes summary for the human reviewer

The human reviewer retained control throughout: they challenged findings, refined wording, inspected the pending comments, edited them manually, and remained responsible for submitting the final review.

## End-to-End Workflow

### 1. Complete and freeze the audit

Run the committed-review workflow to completion before staging anything on GitHub. The audit remains read-only and produces the evidence-backed findings baseline.

Do not add GitHub mutation behavior to the committed-review prompt. Staging is a separate, explicitly invoked workflow.

### 2. Adjudicate findings with the human reviewer

The initial review was not staged immediately. The human reviewer challenged terminology and severity first.

Important refinements included:

- replacing ambiguous "5.0 versus 6.0" wording with:
  - current provider 5.x: `!features.SixPointOh()`
  - vNext 6.0: `features.SixPointOh()`
- confirming that no `FivePointOh()` gate existed
- distinguishing proven defects from uncertain API-precedence questions
- reducing the perceived scope from "major rework" to localized changes
- converting the uncertain Logic App routing concern into a non-blocking question

The staging workflow must preserve the frozen audit as immutable provenance while keeping these human-approved revisions in a separate adjudication ledger.

### 3. Map findings to independently resolvable threads

The human reviewer preferred one inline thread per actionable location. This made each correction easier for the contributor to understand, implement, and resolve.

The final mapping used:

- four separate comments for duplicate `VnetRouteAllEnabled` assignments
- one comment for the overwritten client-certificate compatibility branch
- one consolidated non-blocking question for Logic App routing behavior spanning create and update
- one comment for the `site_update_strategy` documentation ordering and wording
- eight separate comments for the same wording defect in eight documentation files

Use one thread per file and location when fixes are independently actionable. Consolidate only when one indivisible concern genuinely spans multiple code paths.

### 4. Make every comment contributor-facing

Each actionable comment evolved toward this structure:

1. State the concrete problem.
2. Explain the effect on current provider 5.x or vNext 6.0 behavior.
3. Provide one correction path or focused code example.
4. When relevant, end with one verified applicable contributor-document reference.

The human reviewer standardized references in this form:

```markdown
**Reference:** [document-name (section)](absolute GitHub URL)
```

Examples used during the review included:

- `guide-breaking-changes (breaking-schema-changes-and-deprecations)`
- `guide-new-fields-to-resource (Extending a Resource)`
- `reference-documentation-standards (ordering)`
- `reference-documentation-standards (descriptions)`

The live review happened to have applicable guidance for every comment. The generalized workflow should omit the reference line when no relevant reference can be verified; it should not block the comment or force unrelated guidance.

Do not put workflow metadata, finding IDs, confidence labels, role names, or phrases such as "Draft inline review comments" into contributor-facing comments or the review body.

### 5. Preview before mutation

Before creating a pending review, the toolkit should show the human reviewer:

- repository and pull request number
- bound head commit
- exact comment count
- every target path, line, and side
- complete comment bodies
- file coverage
- consolidation decisions
- the separate request-changes summary
- confirmation that the top-level body will be empty
- confirmation that nothing will be submitted

Any wording, scope, location, reference, or finding change invalidates approval and requires a new preview.

### 6. Bind staging to current GitHub state

Immediately before mutation, resolve and verify:

- authenticated GitHub user
- repository identity
- pull request number
- current head SHA
- current changed-file set
- absence of another pending review owned by the authenticated user
- commentability of every target line

For PR 32239, the review was bound to head SHA:

```text
36ed9a8aac50f9fc2801ed8fd814d0d94ed70cb7
```

If the head or any approved plan value changes, stop and require a new preview and approval.

### 7. Create one pending review without submitting it

The preferred operation is one atomic request:

```http
POST /repos/{owner}/{repo}/pulls/{pull_number}/reviews
```

The payload should contain only:

```json
{
  "commit_id": "<approved-head-sha>",
  "body": "",
  "comments": [
    {
      "path": "<changed-path>",
      "line": 123,
      "side": "RIGHT",
      "body": "<approved-comment>"
    }
  ]
}
```

Omit `event` entirely. Never send `APPROVE`, `COMMENT`, or `REQUEST_CHANGES` from this workflow.

### 8. Verify the pending review

After creation, retrieve the review and all review comments. Require:

- state exactly `PENDING`
- top-level body exactly empty
- `submitted_at` absent or null
- commit ID equal to the approved head
- actual comment count equal to the approved count
- actual path coverage equal to approved file coverage
- every path, line, side, and body equal to the approved plan

For PR 32239, final verification reported 15 comments across these paths:

```text
internal/services/appservice/helpers/linux_web_app_schema.go (1)
internal/services/appservice/helpers/web_app_slot_schema.go (2)
internal/services/appservice/helpers/windows_web_app_schema.go (1)
internal/services/logic/logic_app_standard_resource.go (2)
website/docs/r/function_app_flex_consumption.html.markdown (1)
website/docs/r/linux_function_app.html.markdown (1)
website/docs/r/linux_function_app_slot.html.markdown (1)
website/docs/r/linux_web_app.html.markdown (1)
website/docs/r/linux_web_app_slot.html.markdown (1)
website/docs/r/windows_function_app.html.markdown (1)
website/docs/r/windows_function_app_slot.html.markdown (1)
website/docs/r/windows_web_app.html.markdown (1)
website/docs/r/windows_web_app_slot.html.markdown (1)
```

Return the pending-review URL and verification result to the user. Do not submit or repair a mismatched review automatically.

### 9. Keep the request-changes summary separate

Generate a concise copy-ready request-changes body from blocking findings only. Do not include uncertain questions as established blockers.

The summary is returned to the human reviewer in chat. It is not written into the pending review body and is never posted automatically.

Submitting the pending review is a separate operation that requires a new explicit user instruction.

## API and Tooling Lessons from the Live Run

### Multiline PowerShell transport failed silently

The terminal integration executed only the first physical line of a multiline PowerShell command. Two attempts to build and send a complete JSON payload therefore became no-ops.

Toolkit implication:

- use a checked structured API tool where available
- otherwise use a deterministic single-line command or an approved structured payload mechanism
- verify mutation results instead of assuming command success
- query for an existing pending review before retrying to prevent duplicates

### Appending comments through the guessed REST endpoint failed

After an empty pending review was created, this attempted endpoint returned HTTP 404:

```text
POST /repos/{owner}/{repo}/pulls/{pull_number}/reviews/{review_id}/comments
```

Do not rely on that endpoint for incremental construction.

Toolkit implication:

- prefer the atomic review-creation payload
- fail closed if atomic creation cannot be completed
- do not make partial review construction the normal path

### GraphQL could create review threads on commentable lines

The `addPullRequestReviewThread` mutation worked when anchored to a newly added line in the diff. It returned a null thread without an error when the requested line was not commentable.

Toolkit implication:

- validate every line against the PR diff before mutation
- treat a null thread as failure even when GraphQL returns no errors
- do not assume a nearby unchanged line is commentable

### Re-anchoring was necessary for duplicate assignments

The desired comment target was an unchanged unconditional assignment immediately above a newly added `!features.SixPointOh()` guard. GitHub would not create a thread on the unchanged line, so the comments were anchored on the new guard line and explicitly referred to the unconditional assignment immediately above it.

Toolkit implication:

- choose the strongest commentable line that still makes the correction unambiguous
- preview the actual anchor and body before approval
- do not silently change the approved anchor during staging

### Draft comment editing required GraphQL

A REST attempt to patch a comment attached to the pending review returned HTTP 404. The `updatePullRequestReviewComment` GraphQL mutation successfully updated the body.

This was recovery from an exploratory run, not the desired workflow. Atomic creation should make post-creation edits unnecessary.

### The top-level review body must remain empty

The pending review was initially created with this internal text:

```text
Draft inline review comments for the App Service API 2025-05-01 update.
```

The human reviewer correctly rejected it as non-reviewer-facing workflow narration. It was removed, leaving the review body empty.

Toolkit implication:

- set `body` to `""` in the approved plan and API payload
- verify the body is still empty after creation
- keep all staging status and verification details in the assistant response only

## Safety Invariants

The toolkit implementation should enforce these invariants:

- committed and local review workflows remain audit-only
- staging is separate and opt-in
- no mutation occurs in the preview turn
- exact-plan approval is required in a later turn
- the PR head is revalidated after approval
- one pending review is created atomically
- the top-level body is empty
- no submission event is included
- existing pending reviews fail closed
- comments are self-contained and independently resolvable
- uncertain findings remain non-blocking questions
- current provider 5.x and vNext 6.0 wording is explicit
- GitHub state, count, coverage, anchors, and bodies are verified
- the request-changes summary remains separate
- review submission always requires a new explicit instruction

## Recommended Regression Coverage

Add deterministic cases for:

- no eligible frozen review
- missing review verification footer
- unresolved human challenge
- human-revised finding preserved separately from the frozen baseline
- human-proposed finding accepted, rejected, or converted to a non-blocking question
- independent multi-file corrections split into separate threads
- genuine cross-path concern consolidated once
- uncommentable target line
- changed PR head after approval
- existing pending review
- non-empty top-level review body
- accidental `event` field
- inapplicable, malformed, or unverifiable candidate reference omitted without dropping the comment
- ambiguous `FivePointOh` wording for a `SixPointOh` branch
- comment count or file-coverage mismatch
- null GraphQL thread without explicit errors
- attempted automatic review submission

## Definition of Done

The workflow is complete only when:

1. the audit baseline remains unchanged
2. all human challenges have settled dispositions
3. the exact staging plan has been previewed and approved
4. the approved PR head and targets remain current
5. one pending review exists with an empty body
6. all approved inline comments are present and verified
7. nothing has been submitted
8. the human reviewer receives the pending-review URL
9. the human reviewer receives a separate request-changes summary
10. the assistant states that submission requires a new explicit instruction
