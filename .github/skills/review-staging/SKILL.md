---
name: review-staging
description: "BETA: Preserve a frozen committed-review baseline, adjudicate human challenges or missed findings, and stage the settled state as an unsubmitted GitHub pending review after exact-plan approval. Use only after a successful committed review."
---

# Review Staging (BETA)

## Scope

Use this skill only after an eligible frozen `/code-review-committed-changes` result.

It preserves that audit as immutable provenance, maintains a durable post-review challenge state, validates human-proposed changes against targeted pull request evidence, and transforms the settled candidate findings into one verified GitHub pending review.

This skill does not rerun the full review, modify the original audit baseline, modify repository files, or submit reviews.

## Mandatory contract and schema load

Before building a staging plan:

- Read `.github/instructions/review-staging-compliance-contract.instructions.md` to EOF and verify `<!-- REVIEW-STAGE-CONTRACT-EOF -->`.
- Read `.github/instructions/code-review-compliance-contract.instructions.md` to EOF and verify `<!-- REVIEW-CONTRACT-EOF -->`.
- Read `.github/instructions/review-staging-plan.schema.json` end-to-end.
- Read `.github/instructions/review-workflow-handoff.schema.json` end-to-end when structured moderated records are supplied.
- Apply every applicable `REVIEW-STAGE-*` rule exactly.

If any required file cannot be fully loaded, stop without creating or changing GitHub review content.

## Procedure

### Establish eligible frozen input

- Select only an explicitly supplied frozen committed-review result or the latest normal successful `/code-review-committed-changes` result in the current conversation.
- Verify `Preflight complete: yes` and the routed review-skill footer before treating rendered findings as frozen.
- Prefer schema-conformant moderated records when they are explicitly available; otherwise use the final rendered `ISSUES` and `OBSERVATIONS` entries.
- Preserve each finding's final classification, confidence, concrete problem, effect, suggested change, files, and locations.
- When confidence is not exposed by a rendered review, record it as `unknown` rather than inventing certainty.
- Snapshot every original visible finding before accepting challenges.
- Initialize a separate adjudication ledger with `state=open` and one retained candidate for each original finding.
- Do not import strengths, recommendations, future considerations, linter summaries, or overall-assessment text into the staging plan.
- Stop if no eligible frozen findings exist.

### Resolve the pull request and authenticated user

- Resolve one repository owner, repository name, and pull request number from explicit user input or authoritative active pull request context.
- Fail closed when explicit and active pull request identifiers conflict unless the user explicitly overrides the active context.
- Read the pull request's current head commit and complete changed-file diff using GitHub-backed tools or read-only GitHub API access.
- Resolve the authenticated GitHub user and inspect reviews on the pull request for an existing pending review owned by that user.
- If an existing pending review exists, return its URL when available and stop without changing it.
- Confirm every frozen finding path belongs to the pull request changed-file set.

### Adjudicate human challenges

- Resume the current conversation's adjudication ledger when one exists; never recreate it from only the latest user message.
- Treat invocation of `/stage-pending-pr-review` as opening the staging session and initializing the adjudication ledger from the frozen baseline.
- Do not infer adjudicated dispositions from ordinary discussion that occurred before the staging session opened.
- When the invocation contains a challenge or proposed missed concern, process it as the first staging challenge after initialization and keep adjudication open until every challenge is resolved.
- Otherwise, settle the unchanged initialized candidate set and build the complete preview in the same invocation.
- Do not stop a bare invocation after only showing candidate findings or asking the user to request the staging preview.
- Accept targeted user input that:
  - disputes an existing finding or its classification, confidence, wording, effect, correction, scope, or inclusion
  - identifies a potential issue or observation the audit may have missed
  - asks for clarification before deciding whether a finding should remain
- Keep the immutable source snapshot unchanged.
- For a dispute, inspect only the affected finding's directly necessary pull request evidence and guidance.
- For a proposed missed finding, inspect only the proposed concern and its directly necessary paths, locations, and guidance.
- Do not use targeted adjudication to resume broad audit discovery or add unrelated AI findings.
- Record each challenge with its statement, target finding IDs, evidence-backed rationale, final disposition, and resulting finding IDs.
- Apply one of these outcomes:
  - retain the candidate when the original finding remains supported
  - revise or reclassify the candidate when the challenge is supported in part or in full
  - withdraw the candidate when evidence disproves or resolves it
  - add an `origin=human` candidate when a proposed missed concern is supported
  - add an uncertain concern only as an observation or non-blocking question
  - reject an unsupported claim without staging it as fact
- After each challenge, show retained, revised, reclassified, withdrawn, and added findings with concise rationales.
- Keep `state=open` while the user is challenging or asking for changes.
- When the user asks to proceed to staging or confirms adjudication is complete, set `state=settled` and build a new preview.
- If the user challenges a preview, invalidate it and any prior approval, return to `state=open`, adjudicate the challenge, and generate a replacement preview only after the state settles again.
- If no active findings remain, report the settled empty state and stop without creating a pending review.

### Suppress duplicate existing feedback

- Retrieve all existing inline review threads with every reply and open, resolved, or outdated state, all submitted review bodies, and all top-level pull request discussion comments; follow pagination to completion.
- Compare every otherwise active candidate using its underlying concern, affected surface, consequence, and correction path rather than exact wording alone.
- Treat a suggestion-only thread as equivalent when its replacement establishes the same concern and correction.
- For materially equivalent feedback, preserve the frozen finding, set the staging disposition to `suppressed`, record the feedback URL, author, kind, state, and equivalence rationale, and create no new comment.
- Suppress equivalent feedback regardless of author or whether the thread is open, resolved, or outdated.
- Keep a candidate only when current-head evidence proves a distinct concern or recurrence not covered by the prior feedback, and record that distinction.
- If any feedback surface is incomplete, stop before preview rather than assuming no duplicate exists.
- If every candidate is suppressed, report that no new feedback remains and do not build or create an empty review.

### Map settled findings to comments

- Apply `REVIEW-STAGE-MAP-*` to active retained, revised, reclassified, and added findings only.
- Never create a comment for a withdrawn finding, but preserve its baseline snapshot and disposition in the plan.
- Split independent changes across paths or locations into separate comments.
- Consolidate only an indivisible cross-path finding, anchor it at the strongest representative diff location, and include every covered path.
- Preserve explicitly uncertain or non-high-confidence findings as non-blocking questions.
- Select `RIGHT` for a target line in the new side of the diff and `LEFT` for a removed target line on the old side.
- Verify each path, line, and side is commentable on the current pull request head.
- If the ideal affected line is not commentable, use the strongest commentable line in the same relevant hunk or path only when the body can point to the actual affected code unambiguously.
- Put the actual re-anchored path, line, side, and body in the preview; never substitute an anchor after approval.
- If any eligible finding cannot be mapped without guessing or omission, stop before preview.

### Build comment bodies

- Write concise, natural review prose that begins with an evidence-backed observation.
- Prefer a collaborative question when it sounds natural, but use a direct courteous request when forcing a question would sound artificial; do not weaken or manufacture uncertainty around a confirmed finding.
- Use respectful qualifiers such as `It looks like` when they invite correction without weakening verified evidence.
- Do not use audit-style labels, blame, commands, condescension, or minimizing words such as `obviously`, `simply`, or `just`.
- Apply the contributor-facing tone and focus requirements in `REVIEW-STAGE-COMMENT-001` without restating or extending them.
- For uncertain findings, ask one concrete question and make the uncertainty clear in the prose without adding workflow labels.
- Include one fenced `suggestion` block only when the exact replacement is proven and directly applicable at the approved diff anchor.
- Otherwise include a normal code block only when an illustrative example materially clarifies the request; use prose when no safe exact or illustrative code is available.
- If the finding spans multiple code paths, identify the covered paths in the problem or question text.
- Apply `REVIEW-STAGE-VERSION-001` whenever `SixPointOh` or version-gated provider behavior is relevant.
- Verify the actual feature predicate from current pull request evidence and never invent `features.FivePointOh()` for a `features.SixPointOh()` branch.
- When relevant, find one applicable current contributor document and verify the cited heading in that document.
- When verified, end with exactly one reference line in the form `**Reference:** [document-name (section)](raw GitHub URL)`.
- Build an included raw URL under `https://raw.githubusercontent.com/hashicorp/terraform-provider-azurerm/main/` from the verified contributor-document path.
- If no relevant reference can be verified, omit the reference line and continue with the self-contained comment.
- If a candidate reference is malformed, inapplicable, or unverifiable, remove it before preview rather than failing the comment or substituting weaker guidance.
- Do not include finding IDs, role names, confidence labels, workflow narration, or staging metadata in the comment body.

### Build and validate the immutable plan

- Create one in-memory object conforming to `.github/instructions/review-staging-plan.schema.json`.
- Set `schemaVersion` to `1.1`, `sourceReview.mode` to `committed`, `sourceReview.frozen` to `true`, and `reviewBody` to the empty string.
- Populate `sourceReview.findings` from the immutable original snapshots.
- Set `adjudication.state` to `settled` and populate its complete challenge and finding ledgers.
- Populate `existingFeedback` with the checked head commit, complete-source flags, and one evidence-backed check for every otherwise active candidate.
- Verify every comment `findingId` resolves to one active adjudicated finding and that every active finding maps to the required independently resolvable comment or justified consolidated thread.
- Set `expectedCommentCount` to the exact number of planned comments.
- Set `expectedFileCoverage` to the sorted unique set of comment anchor paths.
- Select a brief acknowledgment for `requestChangesSummary` from verified current-conversation or authoritative pull request review and commit history: first-review wording for a first pass, follow-up wording only after proven earlier feedback and contributor updates, or a neutral thank-you when history is unclear.
- Keep that acknowledgment natural and specific to the interaction without inventing prior reviews, pushed changes, or addressed feedback.
- Build the substantive requests only from blocking findings in the settled staging candidate set, including validated human-added findings. Exclude withdrawn findings and mention uncertain findings only as non-blocking questions.
- If no blocking issues exist, follow the acknowledgment by stating that no blocking changes remain and identify any non-blocking questions for manual consideration.
- Validate field presence, allowed values, count equality, file coverage, finding coverage, comment content, included references, and diff locations.
- Do not add an `event` field to the staging plan or API payload.

### Preview and wait for approval

- Display:
  - repository and pull request number
  - full bound head commit
  - every challenge disposition and rationale
  - the settled retained, revised, reclassified, withdrawn, and added finding state
  - every existing-feedback check and each suppressed finding with its matched feedback URL
  - exact comment count
  - exact file coverage
  - any consolidated finding and all paths it covers
  - every complete inline comment as `### Comment N`, `**File:**`, `**Line:**`, and `**Review Comment:**`, followed by the exact contributor-facing body in a fenced `markdown` block
  - the separate copy-ready Request Changes Summary
  - confirmation that the top-level review body will be empty and no review will be submitted
- Keep `side` in the immutable plan but omit raw `RIGHT` and `LEFT` values from the human preview; mark only a removed-line anchor as ` (removed line)` after its displayed line number.
- Make clear that the numbered heading and placement fields are chat-only metadata and only the fenced Markdown body will be added to GitHub.
- Ask `**Stage this exact pending review on \`owner/repository#number\`: "pull request title"?**` using the authoritative repository identity and current pull request title.
- Stop and wait. Do not call a mutating tool in the same turn as the preview.
- Treat only a new explicit affirmative answer as approval.
- Treat a dispute, proposed missed issue, wording change, omission request, or other review change as a challenge rather than approval.

### Revalidate after approval

- Re-read the pull request title and head commit immediately after approval and before mutation.
- Retrieve the complete existing feedback set again and repeat the duplicate check immediately before mutation.
- If new or changed feedback duplicates or supersedes an approved comment, discard approval and render a replacement preview without that duplicate.
- Reconfirm the authenticated user has no existing pending review.
- Reconfirm the baseline snapshots and complete adjudication ledger match the approved plan.
- Reconfirm every planned path, line, side, body, and included contributor reference matches the approved plan.
- If the title or any approved value changed, discard approval, rebuild the preview, and ask again.

### Create the pending review atomically

- Prefer a GitHub-backed tool only when it can create a pending review with the exact required payload and expose the created review ID.
- Otherwise use authenticated `gh api` after approval; do not request, print, or persist an authentication token.
- Serialize the payload with the shell's structured JSON facilities rather than hand-building escaped JSON.
- Use a checked structured tool, deterministic single-physical-line command, or another approved payload mechanism that executes as one complete operation; do not rely on multiline terminal transport.
- Send one request to `POST /repos/{owner}/{repo}/pulls/{pull_number}/reviews` containing only:
  - `commit_id`: the approved head commit
  - `body`: `""`
  - `comments`: the complete array of `path`, `line`, `side`, and `body` values
- Omit `event` entirely.
- Require a definitive response containing the created review ID.
- If creation returns no definitive result, query for an existing pending review before considering a retry and never retry blindly.
- Do not append comments through `POST /repos/{owner}/{repo}/pulls/{pull_number}/reviews/{review_id}/comments`.
- Do not use incremental GraphQL thread creation as a fallback for the atomic request.
- Treat null GraphQL thread or comment data as failure even when no GraphQL errors are returned.
- Do not automatically update anchors or bodies after creation; report mismatches for human inspection.
- Never call `POST /repos/{owner}/{repo}/pulls/{pull_number}/reviews/{review_id}/events` in this workflow.

### Verify the staged review

- Retrieve `GET /repos/{owner}/{repo}/pulls/{pull_number}/reviews/{review_id}`.
- Require `state=PENDING`, an empty body, absent or null `submitted_at`, and the approved `commit_id`.
- Retrieve every page from `GET /repos/{owner}/{repo}/pulls/{pull_number}/reviews/{review_id}/comments`.
- Compare actual and expected comment count, unique path coverage, path, line, side, and body.
- On mismatch, report the exact verification failure and review URL without another mutation.

### Return the handoff

- Return the pending-review URL, verified state, comment count, and file coverage.
- State explicitly that nothing was submitted.
- Return the approved Request Changes Summary in a separate Markdown code block.
- Tell the human reviewer to inspect and optionally edit the pending comments, then submit the review manually in GitHub when satisfied.
- State that this workflow never submits the review; any later automated submission would require a new explicit user instruction outside this workflow.

## Output verification

On a successful staged-review response, append this final line:

`Skill used: review-staging`

Do not write the verification marker into the pending review or any repository file.

<!-- REVIEW-STAGING-SKILL-EOF -->
