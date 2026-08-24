---
description: "Compliance contract for challenging frozen findings and staging the adjudicated state as an unsubmitted GitHub pending pull request review."
---

# Post-Review Challenge and Pending Review Staging Compliance Contract

This contract is the single source of truth for preserving a frozen committed-review baseline, adjudicating human challenges and proposed missed issues, and converting the settled staging state into a GitHub pending review for manual inspection.

## Consumers

- Consumer: `.github/prompts/stage-pending-pr-review.prompt.md`
  - Role: Explicit user entrypoint
  - Requires EOF Load: yes
  - Goal: orchestrate post-review challenge, preview, approval, staging, verification, and final handoff.
- Consumer: `.github/skills/review-staging/SKILL.md`
  - Role: Staging procedure owner
  - Requires EOF Load: yes
  - Goal: preserve the audit baseline, adjudicate human input, and map the settled staging state into validated inline comments.

## Canonical sources of truth (precedence)

Use these sources with the following roles:

- `.github/instructions/code-review-compliance-contract.instructions.md`
  - Authoritative for frozen finding classification, evidence, scope, and semantics.
- `.github/instructions/review-workflow-handoff.schema.json`
  - Authoritative for structured finding transport when schema-conformant records are available.
- `.github/instructions/review-staging-plan.schema.json`
  - Authoritative for the immutable pre-approval staging-plan shape.
- Current pull request metadata and diff
  - Authoritative for repository identity, head commit, changed paths, and commentable locations.
- Applicable current contributor documentation
  - Authoritative for any contributor-document reference included in an inline comment.
- GitHub REST API documentation for pull request reviews
  - Authoritative for pending-review creation and verification semantics.

Conflict resolution:

- This contract is authoritative for staging safety, approval, comment mapping, GitHub mutation boundaries, verification, and output.
- The shared code review contract remains authoritative for the immutable audit baseline and its original finding meaning and classification.
- This contract is authoritative for post-review challenge dispositions and the derived staging candidate set; that state may retain, revise, withdraw, reclassify, or add a finding only through the evidence-backed challenge rules below.
- The committed-review workflow remains audit-only and must not create or submit GitHub review content.
- When current pull request metadata conflicts with frozen finding scope or commit identity, fail closed without creating a review.

## Rule IDs

Rules use the `REVIEW-STAGE-<AREA>-<NNN>` format.

Areas:

- INPUT = accepted frozen input and immutable plan construction
- CHALLENGE = human challenge and missed-finding adjudication
- MAP = finding-to-thread mapping
- COMMENT = inline comment content
- VERSION = provider-version behavior wording
- APPROVAL = explicit user approval boundary
- API = GitHub mutation restrictions
- VERIFY = post-stage verification
- OUTPUT = final user handoff

## Evidence hierarchy

Use evidence in this order:

- Frozen moderated findings from the completed committed review
- Current authoritative pull request metadata and diff
- Current workspace contributor documentation and the exact section cited by each finding
- GitHub review API responses for the created review and its comments

Do not stage a comment when required finding evidence or a commentable location cannot be established. Omit contributor-document references that are not applicable and verifiable.

# Contract Rules

## Frozen input and staging plan

### REVIEW-STAGE-INPUT-001: Staging is separate from audit

- Rule: Pending-review staging is a separate opt-in workflow that consumes already-frozen committed-review findings.
- Rule: Do not invoke staging from `.github/prompts/code-review-committed-changes.prompt.md` and do not add GitHub mutation behavior to that audit-only prompt.
- Rule: The staging workflow must not rerun the full review, reopen broad review scope, or independently discover unrelated findings.
- Rule: Targeted validation of a human challenge or human-proposed missed issue is allowed only under `REVIEW-STAGE-CHALLENGE-*`.

### REVIEW-STAGE-INPUT-002: Only frozen committed-review findings are accepted

- Rule: Accept findings only from an explicitly supplied frozen committed-review result or the latest normal successful `/code-review-committed-changes` result in the current conversation.
- Rule: A rendered review result is eligible only when its verification footer states `Preflight complete: yes` and records the required routed review skills.
- Rule: When schema-conformant moderated records are available, consume only records where `visible=true`; otherwise consume only the final rendered `ISSUES` and `OBSERVATIONS` entries.
- Rule: Exclude strengths, recommendations, future considerations, linter status summaries, and overall-assessment prose from staged comments.
- Rule: Snapshot every eligible original finding in `sourceReview.findings` before challenge adjudication and never mutate or delete that baseline snapshot.
- Rule: If no eligible frozen findings exist, fail closed without creating a review.

### REVIEW-STAGE-INPUT-003: Pull request identity and head commit are immutable

- Rule: Resolve one authoritative repository owner, repository name, pull request number, and current head commit before building the staging plan.
- Rule: Frozen finding paths must belong to that pull request's changed-file set.
- Rule: Bind the staging plan to the current pull request head commit and re-read that head immediately before mutation.
- Rule: If the head commit, pull request identity, or changed-file scope differs from the validated plan, discard approval and rebuild the plan before asking again.

### REVIEW-STAGE-INPUT-004: Validate the complete plan before approval

- Rule: Build one in-memory staging plan conforming to `.github/instructions/review-staging-plan.schema.json` before asking for approval.
- Rule: Build the plan only after every recorded challenge has a final disposition and the adjudication state is `settled`.
- Rule: Validate every comment body, included contributor reference, path, line, side, and covered-path mapping before approval.
- Rule: Validate every target as commentable in the current pull request diff before approval.
- Rule: Do not create a partial plan or silently omit an eligible finding because one target cannot be staged.

## Human challenge and missed-finding adjudication

### REVIEW-STAGE-CHALLENGE-001: Preserve a durable two-layer review state

- Rule: Keep the frozen audit baseline and the post-review adjudication ledger as separate state layers throughout the conversation.
- Rule: The baseline preserves every original visible finding exactly as reviewed; the adjudication ledger records user challenges, targeted validation, dispositions, and the current staging candidate set.
- Rule: Do not overwrite the baseline when a staging candidate is revised, withdrawn, reclassified, or superseded.
- Rule: If conversational state is unavailable, require the user to supply the frozen review plus any prior challenge history; do not reconstruct missing dispositions from memory or guesswork.

### REVIEW-STAGE-CHALLENGE-002: Users may challenge existing findings

- Rule: After an eligible committed review, allow the user to dispute a finding's correctness, classification, confidence, wording, effect, correction path, scope, or staging eligibility.
- Rule: Validate the challenge with targeted reads of the same pull request evidence and applicable guidance; do not rerun the full audit.
- Rule: Record the user's statement, affected finding IDs, validation evidence, final disposition, rationale, and resulting finding IDs in the adjudication ledger.
- Rule: Allowed final dispositions for an existing finding are `retained`, `revised`, `withdrawn`, or `reclassified`.

### REVIEW-STAGE-CHALLENGE-003: Users may propose missed findings

- Rule: After an eligible committed review, allow the user to identify a potential issue or observation the audit may have missed.
- Rule: Validate only the proposed concern and the directly necessary code paths, diff locations, and guidance needed to determine whether it is supported.
- Rule: Add the concern to the staging candidate set with `origin=human` and `disposition=added` when evidence supports it.
- Rule: When evidence supports risk or uncertainty but not an asserted defect, add it as an observation or non-blocking question rather than a blocking issue.
- Rule: When evidence does not support the proposed concern, record a rejected challenge with the reason and do not stage the claim as fact.

### REVIEW-STAGE-CHALLENGE-004: Challenge adjudication remains evidence-bound

- Rule: A user challenge may change the staging candidate set but must not manufacture evidence, contributor policy, or code behavior.
- Rule: Preserve one evidence-backed rationale for every accepted, partially accepted, or rejected challenge.
- Rule: Do not add unrelated AI-discovered findings during targeted challenge validation; invite a fresh committed review when broad scope must be reopened.
- Rule: If the user wants an unproven concern preserved for author discussion, stage it only as a clearly non-blocking question.

### REVIEW-STAGE-CHALLENGE-005: Challenges settle before preview

- Rule: Keep the adjudication state `open` while any challenge is unresolved or while the user is still requesting review changes.
- Rule: After each disposition, show the current candidate findings and preserved withdrawn findings so the human reviewer can challenge further or request the staging preview.
- Rule: Do not build an approvable preview until the user indicates challenge adjudication is complete or asks to proceed to staging.
- Rule: A challenge raised after preview invalidates that preview and any approval, returns the state to `open`, and requires a new settled plan and approval.
- Rule: If no active candidate findings remain after adjudication, return the settled empty state and do not create an empty pending review.

## Finding-to-thread mapping

### REVIEW-STAGE-MAP-001: Use one thread per actionable location

- Rule: Create one inline comment for each independent actionable file and location in the settled staging candidate set so each thread can be resolved separately.
- Rule: When one finding identifies independent corrections in multiple files or locations, create separate comments rather than one broad thread.
- Rule: Do not duplicate the same correction at multiple nearby lines in one file.

### REVIEW-STAGE-MAP-002: Consolidation is reserved for genuinely cross-path findings

- Rule: Use one consolidated thread only when the finding is one indivisible concern whose correctness genuinely spans multiple code paths.
- Rule: Anchor a consolidated thread at the most representative commentable line and name every covered path in the comment body and plan.
- Rule: Do not use consolidation merely to reduce comment count or group findings that can be fixed and resolved independently.

### REVIEW-STAGE-MAP-003: Uncertain findings are non-blocking questions

- Rule: When a settled finding is explicitly uncertain or lacks high confidence, preserve it as a non-blocking question rather than an asserted defect.
- Rule: Begin that comment with `**Question (non-blocking):**` and ask one concrete question grounded in the frozen evidence.
- Rule: Do not turn uncertainty into a blocking request through stronger staging language.

### REVIEW-STAGE-MAP-004: Re-anchor only to an approved commentable line

- Rule: When the ideal code line is unchanged or otherwise not commentable, choose the strongest commentable changed line in the same relevant hunk or path only when the comment body can identify the actual affected code unambiguously.
- Rule: Preview the actual anchor path, line, side, and body before approval; do not silently substitute a nearby line during mutation.
- Rule: Any re-anchoring after preview invalidates approval and requires a replacement preview.
- Rule: If no commentable anchor can preserve the finding accurately, fail closed rather than creating a misleading thread.

## Inline comment content

### REVIEW-STAGE-COMMENT-001: Every comment is self-contained

- Rule: Every inline comment must state the concrete problem, its effect, and one suggested change or code example.
- Rule: Use the labels `**Problem:**`, `**Effect:**`, and `**Suggested change:**` for actionable findings.
- Rule: For a non-blocking question, use `**Question (non-blocking):**`, `**Why it matters:**`, and `**Suggested change if confirmed:**`.
- Rule: Keep one deterministic correction path; do not offer competing alternatives unless the settled finding itself requires a choice from the author.

### REVIEW-STAGE-COMMENT-002: Applicable verified contributor guidance is optional

- Rule: When applicable contributor guidance can be verified, end the inline comment with exactly one reference in this format: `**Reference:** [document-name (section)](raw GitHub URL)`.
- Rule: Include a reference only when the document and exact section are relevant to that comment and verified from the current contributor guidance.
- Rule: An included URL must be an absolute raw GitHub URL under `https://raw.githubusercontent.com/hashicorp/terraform-provider-azurerm/` and identify the referenced Markdown document.
- Rule: Do not substitute an internal contract, skill, prompt, editor-local link, rendered GitHub blob URL, or merely adjacent guidance for a contributor-document reference.
- Rule: If a candidate reference is inapplicable, malformed, or cannot be verified, omit the entire reference line before preview and continue staging the comment.
- Rule: Never invent or force a reference, and never fail the comment solely because no verified applicable reference exists.

### REVIEW-STAGE-COMMENT-003: Review bodies contain no workflow metadata

- Rule: Do not add internal labels or workflow narration such as `Draft inline review comments`, finding IDs, role names, confidence metadata, staging notes, or tool summaries to an inline comment.
- Rule: Leave the pending review's top-level body exactly empty.

## Provider-version wording

### REVIEW-STAGE-VERSION-001: Distinguish current and vNext behavior explicitly

- Rule: When a finding concerns a `SixPointOh` feature branch, identify current provider 5.x behavior as `current provider 5.x (\`!features.SixPointOh()\`)`.
- Rule: Identify vNext 6.0 behavior as `vNext 6.0 (\`features.SixPointOh()\`)`.
- Rule: Do not use ambiguous labels such as `current`, `legacy`, `new`, or `future` without the matching version and predicate.
- Rule: If a comment discusses both branches, state both labels and keep their effects separate.

### REVIEW-STAGE-VERSION-002: Verify the real feature predicate

- Rule: Verify the feature predicate from the current pull request evidence before writing version-gated comment text.
- Rule: Do not invent or substitute `features.FivePointOh()` when the implementation uses `features.SixPointOh()`.
- Rule: If the controlling predicate cannot be proven, keep the version claim out of an asserted defect and ask a non-blocking question when appropriate.

## Explicit approval

### REVIEW-STAGE-APPROVAL-001: Preview precedes approval

- Rule: Before any mutation, show the user the pull request, bound head commit, challenge dispositions, settled candidate findings, exact comment count, file coverage, consolidation decisions, full inline comment bodies, and the separate copy-ready `REQUEST_CHANGES` summary.
- Rule: State that the top-level review body will be empty and the review will remain pending.
- Rule: Ask the user in natural conversational text whether to stage that exact plan, then stop and wait for the answer.

### REVIEW-STAGE-APPROVAL-002: Approval applies only to the exact plan

- Rule: Do not treat invocation of the staging prompt, approval of the earlier audit, or a general request to review the pull request as approval to create the pending review.
- Rule: Proceed only after a new explicit affirmative response to the displayed staging plan.
- Rule: Any new challenge or change to the adjudication ledger, pull request head, comment count, file coverage, comment body, target location, reference, or summary invalidates approval and requires a new settled preview and approval.

## GitHub mutation boundary

### REVIEW-STAGE-API-001: Create only an unsubmitted pending review

- Rule: Use a GitHub review API or authenticated client capable of creating a pull request review in `PENDING` state.
- Rule: Prefer a GitHub-backed review tool when it exposes pending-review creation with the required exact payload semantics; otherwise an authenticated `gh api` call is allowed only after `REVIEW-STAGE-APPROVAL-002` is satisfied.
- Rule: Create the review with one atomic request containing the bound `commit_id`, an empty `body`, and the complete `comments` array.
- Rule: Omit the `event` property entirely. Do not send `APPROVE`, `COMMENT`, `REQUEST_CHANGES`, an empty event value, or any other submission event.
- Rule: Do not create comments individually before the pending review exists and do not continue after a partial mutation failure.

### REVIEW-STAGE-API-002: Submission is outside this workflow

- Rule: Never call the review submission endpoint, approve, request changes, or submit a general comment in this workflow.
- Rule: Never infer submission approval from approval to stage the pending review.
- Rule: A later submission requires a new explicit user instruction after manual inspection and is a separate action outside this staging workflow.

### REVIEW-STAGE-API-003: Existing pending reviews fail closed

- Rule: Before preview, determine whether the authenticated user already owns a pending review on the pull request.
- Rule: If an existing pending review is present, fail closed and return its URL when available; do not replace, update, delete, or merge into it automatically.

### REVIEW-STAGE-API-004: Mutation transport must be deterministic and retry-safe

- Rule: Prefer a checked structured API tool; otherwise use a deterministic single-physical-line command or another approved structured payload mechanism that the active terminal integration will execute as one complete operation.
- Rule: Do not depend on a multiline terminal command when the integration may execute only its first physical line.
- Rule: Require a definitive creation response containing the review identity; do not infer success from an empty terminal result or lack of an error.
- Rule: Before any retry after an ambiguous or failed creation attempt, query for an existing pending review owned by the authenticated user and fail closed if one exists.
- Rule: Never blind-retry a review mutation.

### REVIEW-STAGE-API-005: Incremental thread construction and automatic repair are forbidden

- Rule: Do not append comments through a guessed `POST /repos/{owner}/{repo}/pulls/{pull_number}/reviews/{review_id}/comments` endpoint.
- Rule: Do not replace the atomic creation request with incremental `addPullRequestReviewThread` mutations or other partial review construction.
- Rule: If a GitHub-backed tool internally returns null thread or comment data without GraphQL errors, treat the operation as failed rather than successful.
- Rule: Do not automatically repair comment anchors or bodies with `updatePullRequestReviewComment` or another post-creation mutation; report verification mismatches for human inspection.
- Rule: Human reviewers may edit the pending review manually after inspection, but the staging workflow must not perform those edits automatically.

## Post-stage verification

### REVIEW-STAGE-VERIFY-001: Verify review state and non-submission

- Rule: Retrieve the created review by ID immediately after creation.
- Rule: Require `state` to equal `PENDING`, the top-level `body` to be empty, `submitted_at` to be absent or null, and `commit_id` to match the approved plan.
- Rule: Treat any other state or submission timestamp as verification failure and do not perform another mutation in response.

### REVIEW-STAGE-VERIFY-002: Verify comments and file coverage

- Rule: Retrieve all comments for the created review, including pagination when necessary.
- Rule: Require the actual comment count to equal `expectedCommentCount` and the normalized actual path set to equal `expectedFileCoverage`.
- Rule: Require each comment's path, line, side, and body to match the approved plan.
- Rule: If verification fails, report the mismatch and pending-review URL without submitting, deleting, or repairing the review automatically.

## Final output

### REVIEW-STAGE-OUTPUT-001: Return the pending review for inspection

- Rule: On successful verification, return the pending-review URL and state plainly that it remains unsubmitted.
- Rule: Report the verified comment count and file coverage.
- Rule: Do not include internal staging metadata in the GitHub review body; user-visible verification belongs only in the assistant response.

### REVIEW-STAGE-OUTPUT-002: Keep the request-changes summary separate

- Rule: Return the same copy-ready `REQUEST_CHANGES` summary that the user approved in a separate Markdown code block.
- Rule: Derive the summary only from blocking findings in the settled staging candidate set, including validated human-added findings, and do not present withdrawn or uncertain findings as established blockers.
- Rule: Do not post or submit that summary automatically.
- Rule: End by stating that submission requires a new explicit instruction.

<!-- REVIEW-STAGE-CONTRACT-EOF -->
